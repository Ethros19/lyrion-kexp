package Plugins::KEXP::ProtocolHandler;

# kexp://show/<showId>[/<secondsIntoShow>]
#
# Resolves to the show's archive MP3 on the KEXP CDN and starts playback at
# the show's start (skipping the file's ~10 min pre-roll), or further in when
# a tracklist entry was picked. Pattern borrowed from Lyrion's Podcast plugin.

use strict;
use utf8;
use base qw(Slim::Player::Protocols::HTTPS);

use Time::HiRes;

use Slim::Utils::Log;

use Plugins::KEXP::API;
use Plugins::KEXP::Util qw(formatDay);

my $log = logger('plugin.kexp');

sub parseUrl {
	my $url = shift;
	return $url =~ m{^kexp://show/(\d+)(?:/(\d+))?} ? ($1, $2 || 0) : ();
}

sub scanUrl {
	my ($class, $url, $args) = @_;

	my $song = $args->{song};
	my $cb   = $args->{cb};

	my ($id, $from) = parseUrl($url) or return $cb->(undef, 'PLUGIN_KEXP_ERROR');

	Plugins::KEXP::API->getShow($id, sub {
		my $show = shift || return $cb->(undef, 'PLUGIN_KEXP_ERROR');

		Plugins::KEXP::API->getArchiveFile($show, sub {
			my $file = shift || return $cb->(undef, 'PLUGIN_KEXP_NOT_ARCHIVED');

			my $startTime = $file->{offset} + $from;

			$song->pluginData(kexp => {
				showId     => $id,
				fileOffset => $file->{offset},
			});

			# applied in getNextTrack, once the scanned track knows its bitrate
			$song->seekdata({ startTime => $startTime }) if $startTime > 0;

			# warm the tracklist so now-playing can show the current song
			Plugins::KEXP::API->getPlays($id);

			$args->{cb} = sub {
				my $track = shift;

				if ($track) {
					main::INFOLOG && $log->info("$url => " . $track->url . " from ${startTime}s");

					$song->streamUrl($track->url);
					$track->title($show->{title});
					$track->url($url);
					$song->master->currentPlaylistUpdateTime(Time::HiRes::time());
				}

				$cb->($track, @_);
			};

			$class->SUPER::scanUrl($file->{url}, $args);
		});
	});
}

sub new {
	my ($class, $args) = @_;

	# stream the CDN url, but don't clobber a redirect target
	$args->{url} = $args->{song}->streamUrl unless $args->{redir};
	return $class->SUPER::new($args);
}

sub getNextTrack {
	my ($class, $song, $successCb, $errorCb) = @_;

	if (my $startTime = ($song->seekdata || {})->{startTime}) {
		$song->seekdata($song->getSeekData($startTime));
	}

	$successCb->();
}

sub getMetadataFor {
	my ($class, $client, $url) = @_;

	my ($id) = parseUrl($url) or return {};
	my $show = Plugins::KEXP::API->cachedShow($id);
	my $icon = Plugins::KEXP::Plugin->icon;

	return { title => 'KEXP', icon => $icon, cover => $icon } unless $show;

	my $meta = {
		title  => $show->{title},
		artist => $show->{host} || 'KEXP',
		album  => 'KEXP ' . formatDay($show->{start}, $show->{tzOffset}),
		cover  => $show->{image} || $icon,
		icon   => $icon,
		type   => 'MP3 (KEXP archive)',
	};

	my $song = $client && $client->playingSong;
	return $meta unless $song && $song->currentTrack && $song->currentTrack->url eq $url;

	my $data  = $song->pluginData('kexp') || return $meta;
	my $plays = Plugins::KEXP::API->cachedPlays($id);

	if (!$plays) {
		Plugins::KEXP::API->getPlays($id);
		return $meta;
	}

	# wall-clock moment we're hearing = file start + position in file
	my $elapsed = $client->controller->playingSongElapsed || 0;
	my $now     = $show->{start} - $data->{fileOffset} + $elapsed;

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
