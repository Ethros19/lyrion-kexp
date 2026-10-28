package Plugins::KEXP::LiveOnKEXP;

# "Live on KEXP" studio sessions, from the podcast's Omny RSS feed
# (~1,300 episodes back to 2013, plain MP3 enclosures).

use strict;

use Encode qw(decode_utf8);

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Cache;
use Slim::Utils::Log;

use Plugins::KEXP::Util qw(parseRssItems);

use constant FEED_URL => 'https://www.omnycontent.com/d/playlist/bad5d079-8dcb-4630-8770-aa090049131d/18f3a48e-1c64-43e8-96e9-aa40002038ee/856f4314-821f-46ca-bc8e-aa40002038f2/podcast.rss';
use constant TTL => 6 * 3600;

my $log   = logger('plugin.kexp');
my $cache = Slim::Utils::Cache->new;

my $episodes;
my $fetchedAt = 0;
my @waiting;
my %byClip;

# Omny clip id, stable across the tracking query strings / redirects
sub _clipId {
	my $url = shift || return;
	return $url =~ m{/clips/(?:[^/]+/){2}([0-9a-f-]{36})/}i ? lc $1 : undef;
}

sub _index {
	for my $ep (@{ $episodes || [] }) {
		$ep->{key} = _clipId($ep->{url}) || $ep->{url};
	}
	%byClip = map { $_->{key} => $_ } @{ $episodes || [] };
}

# Look up one episode by the key used in menus (Omny clip id)
sub byKey {
	my ($class, $key, $cb) = @_;
	$class->episodes(sub { $cb->($byClip{$key}) });
}

# Slim::Formats::RemoteMetadata provider, so now-playing shows the band and
# session artwork rather than the MP3's own tags
sub metadataProvider {
	my ($client, $url) = @_;

	# e.g. after a restart with a session still queued: load in the background
	__PACKAGE__->episodes(sub {}) unless $episodes;

	my $ep = $byClip{ _clipId($url) || $url } || return {};

	my $date = $ep->{date} ? Plugins::KEXP::Util::formatDay($ep->{date}, 0) : '';
	$date =~ s/^\w+ //;

	return {
		title    => $ep->{artist},
		artist   => 'Live on KEXP',
		album    => $ep->{date} ? $date . ', ' . ((gmtime($ep->{date}))[5] + 1900) : 'KEXP',
		cover    => $ep->{image},
		duration => $ep->{secs},
		type     => 'MP3 (Live on KEXP)',
	};
}

sub count { scalar @{ $episodes || [] } }

# Newest-first list of { artist, title, date, url, image, secs }
sub episodes {
	my ($class, $cb) = @_;

	if ($episodes && time() - $fetchedAt < TTL) {
		return $cb->($episodes);
	}

	if (!$episodes && (my $cached = $cache->get('kexp:liveonkexp:v2'))) {
		($episodes, $fetchedAt) = @$cached;
		_index();
		return $cb->($episodes) if time() - $fetchedAt < TTL;
	}

	push @waiting, $cb;
	return if @waiting > 1;

	my $done = sub {
		my $list = shift;
		if ($list && @$list) {
			($episodes, $fetchedAt) = ($list, time());
			_index();
			$cache->set('kexp:liveonkexp:v2', [$episodes, $fetchedAt], '7 days');
		}
		# on failure fall back to whatever we had, however stale
		my @cbs = splice @waiting;
		$_->($episodes) for @cbs;
	};

	main::DEBUGLOG && $log->debug('GET ' . FEED_URL);

	Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $xml = eval { decode_utf8(shift->content) };
			my $list = eval { parseRssItems($xml) };
			$log->error("Couldn't parse Live on KEXP feed: $@") if $@;
			$done->($list);
		},
		sub {
			$log->error("Live on KEXP feed failed: $_[1]");
			$done->();
		},
		{ timeout => 30 },
	)->get(FEED_URL);
}

1;
