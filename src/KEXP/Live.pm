package Plugins::KEXP::Live;

# Now-playing for the live stream from KEXP's own playlist data (song,
# album art, show and DJ), richer than the stream's built-in title. Polled
# every 30 s only while some player is on the live stream.

use strict;
use utf8;

use Slim::Utils::Log;
use Slim::Utils::Timers;

use Plugins::KEXP::API;

use constant STREAM_URL => 'https://kexp.streamguys1.com/kexp160.aac';
use constant URL_MATCH  => qr{^https?://kexp\.streamguys1\.com/kexp\d+\.(?:aac|mp3)}i;
use constant REFRESH    => 30;

my $log = logger('plugin.kexp');

my $now       = {};    # { play => {...}, show => {...} }
my $fetchedAt = 0;
my $fetching  = 0;
my $ticking   = 0;

sub _isLive {
	my $client = shift;
	my $song = $client->playingSong || return;
	my $track = $song->currentTrack || return;
	return $track->url =~ URL_MATCH;
}

sub _refresh {
	return if $fetching;
	$fetching = 1;

	Plugins::KEXP::API->nowPlaying(sub {
		my ($play, $show) = @_;
		$fetching = 0;
		$fetchedAt = time();
		return unless $play || $show;

		my $before = join('|', map { $_ // '' } @{ $now->{play} || {} }{qw(start song)}, ($now->{show} || {})->{id});
		$now = { play => $play, show => $show };
		my $after  = join('|', map { $_ // '' } @{ $play || {} }{qw(start song)}, ($show || {})->{id});

		if ($before ne $after) {
			for my $client (grep { _isLive($_) } Slim::Player::Client::clients()) {
				Slim::Control::Request::notifyFromArray($client, ['newmetadata']);
			}
		}
	});
}

sub _tick {
	if (grep { _isLive($_) } Slim::Player::Client::clients()) {
		_refresh();
		Slim::Utils::Timers::setTimer(undef, time() + REFRESH, \&_tick);
	}
	else {
		$ticking = 0;
	}
}

# Slim::Formats::RemoteMetadata provider for the live stream urls
sub metadataProvider {
	my ($client, $url) = @_;

	_refresh() if time() - $fetchedAt > REFRESH;

	if (!$ticking) {
		$ticking = 1;
		Slim::Utils::Timers::setTimer(undef, time() + REFRESH, \&_tick);
	}

	my ($play, $show) = @{$now}{qw(play show)};
	return {} unless $play || $show;    # fall back to the stream's own title

	my $icon = Plugins::KEXP::Plugin->icon;
	my $showTitle = $show ? $show->{title} : 'KEXP';

	if ($play && $play->{type} eq 'trackplay' && $play->{song}) {
		return {
			title  => $play->{song},
			artist => $play->{artist} || 'KEXP',
			album  => join(' · ', grep { $_ } $play->{album}, $showTitle),
			cover  => $play->{image} || ($show && $show->{image}) || $icon,
			icon   => $icon,
		};
	}

	# air break, or no track logged yet
	return {
		title  => $showTitle,
		artist => ($show && $show->{host}) || 'KEXP',
		album  => 'KEXP 90.3 FM',
		cover  => ($show && $show->{image}) || $icon,
		icon   => $icon,
	};
}

1;
