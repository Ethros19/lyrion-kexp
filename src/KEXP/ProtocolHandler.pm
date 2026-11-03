package Plugins::KEXP::ProtocolHandler;

# kexp://show/<showId>[/<secondsIntoShow>]
# kexp://program/<programId>/latest  - newest archived show of a program,
#                                     resolved at play time (favourites, alarms)
#
# Resolves to the show's archive MP3 (occasionally AAC) on the KEXP CDN. Each
# file starts ~10 min before the show; that pre-roll is hidden: the track's
# duration is the show's length and position 0:00 is the show's start, with
# every seek shifted past the pre-roll. Pattern borrowed from Lyrion's Podcast
# plugin.

use strict;
use utf8;
use base qw(Slim::Player::Protocols::HTTPS);

use Time::HiRes;

use Slim::Utils::Errno;
use Slim::Utils::Log;

use Plugins::KEXP::API;
use Plugins::KEXP::Util qw(formatDay aacTiming adtsSync);

my $log = logger('plugin.kexp');

# Some archive files are ADTS AAC instead of MP3 (seen during KEXP's
# Oct 30 - Nov 2 2026 outage). LMS only sniffs an AAC stream's samplerate (and
# doesn't keep its size), so we supply bitrate and length ourselves, and since
# faad can't start mid-frame, a seek is proxied and trimmed to the next frame.
sub _isAac { $_[0] =~ /\.aac(?:\?|$)/i }

sub _fileSize {
	my ($url, $cb) = @_;

	Slim::Networking::SimpleAsyncHTTP->new(
		sub { $cb->(shift->headers->content_length) },
		sub { $log->warn("No size for $url: $_[1]"); $cb->() },
		{ timeout => 15 },
	)->head($url);
}

sub parseUrl {
	my $url = shift;
	return $url =~ m{^kexp://show/(\d+)(?:/(\d+))?} ? ($1, $2 || 0) : ();
}

sub parseProgramUrl {
	my $url = shift;
	return $url =~ m{^kexp://program/(\d+)/latest} ? $1 : undef;
}

sub latestUrl { "kexp://program/$_[1]/latest" }

# url -> show (and seconds into it), for either kind of url
sub _resolveShow {
	my ($url, $cb) = @_;

	if (defined(my $programId = parseProgramUrl($url))) {
		return Plugins::KEXP::API->latestShowForProgram($programId, sub { $cb->(shift, 0) });
	}

	my ($id, $from) = parseUrl($url) or return $cb->();
	Plugins::KEXP::API->getShow($id, sub { $cb->(shift, $from) });
}

sub scanUrl {
	my ($class, $url, $args) = @_;

	my $song = $args->{song};
	my $cb   = $args->{cb};

	_resolveShow($url, sub {
		my ($show, $from) = @_;
		return $cb->(undef, 'PLUGIN_KEXP_NOT_ARCHIVED') unless $show;
		my $id = $show->{id};

		Plugins::KEXP::API->getArchiveFile($show, sub {
			my $file = shift || return $cb->(undef, 'PLUGIN_KEXP_NOT_ARCHIVED');

			my $isAac = _isAac($file->{url});

			$song->pluginData(kexp => {
				showId     => $id,
				fileOffset => $file->{offset},
				format     => $isAac ? 'AAC' : 'MP3',
			});

			# applied in getNextTrack, once the scanned track knows its bitrate.
			# Show-relative; getSeekData adds the pre-roll (so even 0 seeks).
			$song->seekdata({ startTime => $from });

			# warm the tracklist so now-playing can show the current song
			Plugins::KEXP::API->getPlays($id);

			my $finish = sub {
				my $track = shift;

				if ($track) {
					# duration = the show, not the file
					if (my $secs = $track->secs) {
						$secs -= $file->{offset} if $secs > $file->{offset};
						$track->secs($secs);
						$song->duration($secs);
					}
					$song->master->currentPlaylistUpdateTime(Time::HiRes::time());
				}

				$cb->($track, @_);
			};

			$args->{cb} = sub {
				my ($track, @rest) = @_;
				return $finish->($track, @rest) unless $track;

				main::INFOLOG && $log->info("$url => " . $track->url . " from ${from}s (+$file->{offset}s pre-roll)");

				my $streamUrl = $track->url;
				$song->streamUrl($streamUrl);
				$track->title($show->{title});
				$track->url($url);

				return $finish->($track, @rest) unless $isAac && !$track->bitrate;

				_fileSize($streamUrl, sub {
					my $length = $show->{end} && $show->{end} - $show->{start};
					my ($bitrate, $secs) = aacTiming(shift, $length, $file->{offset});
					main::INFOLOG && $log->info("AAC: assuming $bitrate bps, " . ($secs ? int($secs) . 's' : 'unknown length'));
					$track->bitrate($bitrate);
					$track->secs($secs) if $secs;
					$finish->($track, @rest);
				});
			};

			$class->SUPER::scanUrl($file->{url}, $args);
		});
	});
}

sub new {
	my ($class, $args) = @_;

	# stream the CDN url, but don't clobber a redirect target
	$args->{url} = $args->{song}->streamUrl unless $args->{redir};
	my $self = $class->SUPER::new($args) || return;

	# a byte-offset seek into AAC lands mid-frame: trim to the next frame
	my $seekdata = $args->{song}->seekdata || {};
	${*$self}{kexp_adts} = '' if _isAac($args->{url}) && $seekdata->{sourceStreamOffset};

	return $self;
}

# AAC seeks need sysread below, so never let the player fetch the CDN itself
sub canDirectStream {
	my ($class, $client, $url, @rest) = @_;
	return 0 if _isAac($url);
	return $class->SUPER::canDirectStream($client, $url, @rest);
}

sub sysread {
	my $self = $_[0];
	return $self->SUPER::sysread($_[1], $_[2], $_[3]) unless defined ${*$self}{kexp_adts};

	my $bytes = $self->SUPER::sysread(my $chunk, $_[2]);
	return $bytes unless $bytes;    # EOF or would-block

	my $buf = ${*$self}{kexp_adts} .= $chunk;
	my $sync = adtsSync($buf);

	if (!defined $sync) {
		# keep looking, but give up after a sane amount of data
		if (length $buf < 65536) {
			$_[1] = '';
			$! = EINTR;
			return undef;
		}
		$log->warn('No ADTS frame found after seek; passing data through');
		$sync = 0;
	}

	main::INFOLOG && $log->info("AAC seek: skipped $sync bytes to the next frame");
	delete ${*$self}{kexp_adts};
	$_[1] = substr($buf, $sync);
	return length $_[1];
}

sub getNextTrack {
	my ($class, $song, $successCb, $errorCb) = @_;

	my $seekdata = $song->seekdata || {};
	if (defined $seekdata->{startTime} && !defined $seekdata->{sourceStreamOffset}) {
		$song->seekdata($song->getSeekData($seekdata->{startTime}));
	}

	$successCb->();
}

# Seeks arrive in show time; the file is ahead of that by the pre-roll
sub getSeekData {
	my ($class, $client, $song, $newtime) = @_;

	my $preroll = ($song->pluginData('kexp') || {})->{fileOffset} || 0;
	my $data = $class->SUPER::getSeekData($client, $song, $newtime + $preroll) || return;

	$data->{timeOffset} = $newtime;
	return $data;
}

sub getMetadataFor {
	my ($class, $client, $url) = @_;

	my $icon = Plugins::KEXP::Plugin->icon;
	my $song = $client && $client->playingSong;
	my $isCurrent = $song && $song->currentTrack && $song->currentTrack->url eq $url;

	my $id;
	if (defined(my $programId = parseProgramUrl($url))) {
		# which show "latest" turned out to be is only known once it plays
		my $data = $isCurrent && $song->pluginData('kexp');
		$id = $data->{showId} if $data;

		unless ($id) {
			my $program = Plugins::KEXP::API->programName($programId) || 'KEXP';
			return {
				title  => $program,
				artist => Slim::Utils::Strings::cstring($client, 'PLUGIN_KEXP_LATEST_EPISODE'),
				album  => 'KEXP',
				cover  => $icon,
				icon   => $icon,
			};
		}
	}
	else {
		($id) = parseUrl($url) or return {};
	}

	my $show = Plugins::KEXP::API->cachedShow($id);
	return { title => 'KEXP', icon => $icon, cover => $icon } unless $show;

	my $data = $isCurrent && $song->pluginData('kexp');

	my $meta = {
		title  => $show->{title},
		artist => $show->{host} || 'KEXP',
		album  => 'KEXP ' . formatDay($show->{start}, $show->{tzOffset}),
		cover  => $show->{image} || $icon,
		icon   => $icon,
		type   => ($data && $data->{format} || 'MP3') . ' (KEXP archive)',
	};

	return $meta unless $data;

	my $plays = Plugins::KEXP::API->cachedPlays($id);

	if (!$plays) {
		Plugins::KEXP::API->getPlays($id);
		return $meta;
	}

	# wall-clock moment we're hearing = show start + position (pre-roll hidden)
	my $elapsed = $client->controller->playingSongElapsed || 0;
	my $now     = $show->{start} + $elapsed;

	my $current;
	for my $play (@$plays) {
		last if $play->{start} > $now;
		$current = $play;
	}

	if ($current && $current->{type} eq 'trackplay' && $current->{song}) {
		$meta->{title}  = $current->{song};
		$meta->{artist} = $current->{artist} if $current->{artist};
		$meta->{album}  = join(' · ', grep { $_ } $current->{album}, $show->{title});
		$meta->{cover}  = $current->{image} if $current->{image};
	}

	# nudge clients to refresh when the on-air track changes
	my $key = $current ? $current->{start} : 0;
	if (($data->{lastPlay} || 0) != $key) {
		$data->{lastPlay} = $key;
		Slim::Control::Request::notifyFromArray($client, ['newmetadata']);
	}

	return $meta;
}

1;
