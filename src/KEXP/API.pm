package Plugins::KEXP::API;

# Thin async client for the public KEXP API (api.kexp.org).
#
# Archive layout (observed): every show has one static MP3 on the
# streamguys CDN covering [show start - 10 min, show end], 128 kbps CBR,
# with byte-range support. get_streaming_url tells us which file holds a
# given timestamp and the offset (seconds) into it.

use strict;

use JSON::XS::VersionOneAndTwo;

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Cache;
use Slim::Utils::Log;

use Plugins::KEXP::Util qw(parseTime isoUTC genresForTags);

use constant BASE         => 'https://api.kexp.org';
use constant ARCHIVE_DAYS => 14;

my $log   = logger('plugin.kexp');
my $cache = Slim::Utils::Cache->new;

# in-memory copies so getMetadataFor never has to wait on the network
my %shows;
my %plays;
my %inflight;
my %programNames;

sub _get {
	my ($url, $cb, $ttl) = @_;

	my $key = "kexp:$url";
	if ($ttl && (my $cached = $cache->get($key))) {
		return $cb->($cached);
	}

	main::DEBUGLOG && $log->debug("GET $url");

	Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $data = eval { from_json(shift->content) };
			if ($@ || !$data) {
				$log->error("Bad JSON from $url: $@");
				return $cb->();
			}
			$cache->set($key, $data, $ttl) if $ttl;
			$cb->($data);
		},
		sub {
			my (undef, $error) = @_;
			$log->error("Request failed for $url: $error");
			$cb->();
		},
		{ timeout => 15 },
	)->get($url);
}

use constant MAX_PAGES => 5;

# Follow DRF-style "next" links and hand back all results. /v2/plays/ always
# returns a "next" link, even past the end, so also stop on a short page.
sub _getAll {
	my ($url, $cb, $ttl, $acc, $page) = @_;
	$acc  ||= [];
	$page ||= 1;

	my ($limit) = $url =~ /[?&]limit=(\d+)/;

	_get($url, sub {
		my $data = shift || return $cb->(@$acc ? $acc : undef);
		my $results = $data->{results} || [];
		push @$acc, @$results;

		my $next = $data->{next};
		if ($next && @$results && (!$limit || @$results >= $limit) && $page < MAX_PAGES) {
			return _getAll($next, $cb, $ttl, $acc, $page + 1);
		}
		$cb->($acc);
	}, $ttl);
}

sub _normalizeShow {
	my $raw = shift;

	my ($start, $offset) = parseTime($raw->{start_time});
	my $hosts = join(' & ', grep { $_ } @{ $raw->{host_names} || [] });

	return {
		id      => $raw->{id},
		program => $raw->{program_name} || 'KEXP',
		programId => $raw->{program},
		host    => $hosts,
		title   => ($raw->{program_name} || 'KEXP') . ($hosts ? " with $hosts" : ''),
		tagline => $raw->{tagline},
		image   => $raw->{image_uri} || $raw->{program_image_uri},
		programImage => $raw->{program_image_uri},
		start   => $start,
		tzOffset => $offset,
		genres  => [ genresForTags($raw->{program_tags}) ],
	};
}

sub _remember {
	my $show = shift;
	$shows{ $show->{id} } = $show;
	$programNames{ $show->{programId} } = $show->{program} if $show->{programId};
	$cache->set('kexp:show:' . $show->{id}, $show, '30 days');
}

# All shows still inside the archive window, newest first. Each show gets
# an `end` (the next show's start); the show currently on air has none and
# is flagged `live` since its archive file is still being written.
sub recentShows {
	my ($class, $cb) = @_;

	my $after = isoUTC(time() - ARCHIVE_DAYS * 86400);

	_getAll(BASE . "/v2/shows/?format=json&limit=500&start_time_after=$after", sub {
		my $results = shift || return $cb->();

		my @list = sort { $b->{start} <=> $a->{start} }
		           grep { $_->{start} }
		           map  { _normalizeShow($_) } @$results;

		for my $i (0 .. $#list) {
			if ($i == 0) {
				$list[$i]->{live} = 1;
			}
			else {
				$list[$i]->{end} = $list[$i - 1]->{start};
			}
			_remember($list[$i]);
		}

		$cb->(\@list);
	}, 300);
}

# Still playable? The archive drops a show 14 days after it started; keep a
# margin so nothing in a (cached) menu expires while you're looking at it.
use constant EXPIRY_MARGIN => 30 * 60;

sub isArchived {
	my ($class, $show) = @_;
	return !$show->{live} && $show->{start} > time() - ARCHIVE_DAYS * 86400 + EXPIRY_MARGIN;
}

# Newest archived show of a program (for kexp://program/<id>/latest)
sub latestShowForProgram {
	my ($class, $programId, $cb) = @_;

	$class->recentShows(sub {
		my ($show) = grep { ($_->{programId} || 0) == $programId && $class->isArchived($_) } @{ shift() || [] };
		$cb->($show);
	});
}

sub programName {
	my ($class, $programId) = @_;
	return $programNames{$programId};
}

sub cachedShow {
	my ($class, $id) = @_;
	return $shows{$id} ||= $cache->get("kexp:show:$id");
}

sub getShow {
	my ($class, $id, $cb) = @_;

	if (my $show = $class->cachedShow($id)) {
		return $cb->($show);
	}

	_get(BASE . "/v2/shows/$id/?format=json", sub {
		my $raw = shift || return $cb->();
		my $show = _normalizeShow($raw);
		return $cb->() unless $show->{start};
		_remember($show);
		$cb->($show);
	});
}

# -> { url => 'https://...mp3', offset => seconds into file where the show starts }
sub getArchiveFile {
	my ($class, $show, $cb) = @_;

	# Ask for a moment just after the start so we never land on the
	# previous show's file at the boundary.
	my $nudge = 30;
	my $ts = isoUTC($show->{start} + $nudge);

	_get(BASE . "/get_streaming_url/?bitrate=128&timestamp=$ts", sub {
		my $data = shift;

		if (!$data || !$data->{'sg-url'}) {
			$log->warn("No archive file for show $show->{id} (older than " . ARCHIVE_DAYS . " days?)");
			return $cb->();
		}

		my $offset = ($data->{'sg-offset'} || 0) - $nudge;
		$cb->({
			url    => $data->{'sg-url'},
			offset => $offset > 0 ? $offset : 0,
		});
	}, 86400);
}

# What's on air: (latest play, current show), both normalised; either may be undef
sub nowPlaying {
	my ($class, $cb) = @_;

	my ($play, $show, $pending) = (undef, undef, 2);
	my $done = sub { $cb->($play, $show) unless --$pending };

	_get(BASE . '/v2/plays/?format=json&limit=1', sub {
		my $data = shift;
		if (my $raw = $data && $data->{results} && $data->{results}->[0]) {
			$play = {
				start  => scalar parseTime($raw->{airdate}),
				type   => $raw->{play_type} || '',
				artist => $raw->{artist},
				song   => $raw->{song},
				album  => $raw->{album},
				image  => $raw->{image_uri} || $raw->{thumbnail_uri},
			};
		}
		$done->();
	});

	_get(BASE . '/v2/shows/?format=json&limit=1', sub {
		my $data = shift;
		if (my $raw = $data && $data->{results} && $data->{results}->[0]) {
			$show = _normalizeShow($raw);
		}
		$done->();
	});
}

sub cachedPlays {
	my ($class, $id) = @_;
	return $plays{$id};
}

# Plays (tracks + air breaks) for a show, in air order
sub getPlays {
	my ($class, $id, $cb) = @_;
	$cb ||= sub {};

	if (my $list = $plays{$id}) {
		return $cb->($list);
	}

	if ($inflight{$id}) {
		push @{ $inflight{$id} }, $cb;
		return;
	}
	$inflight{$id} = [$cb];

	_getAll(BASE . "/v2/plays/?format=json&limit=500&ordering=airdate&show_ids=$id", sub {
		my $results = shift;
		my $list;

		if ($results) {
			$list = [
				map {
					{
						start  => scalar parseTime($_->{airdate}),
						type   => $_->{play_type},
						artist => $_->{artist},
						song   => $_->{song},
						album  => $_->{album},
						image  => $_->{image_uri} || $_->{thumbnail_uri},
					}
				}
				grep { ($_->{show} || 0) == $id }
				@$results
			];
			$plays{$id} = $list;
		}

		my $waiting = delete $inflight{$id};
		$_->($list) for @$waiting;
	}, 3600);
}

1;
