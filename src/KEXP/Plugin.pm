package Plugins::KEXP::Plugin;

use strict;
use utf8;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

use Plugins::KEXP::API;
use Plugins::KEXP::LiveOnKEXP;
use Plugins::KEXP::Live;
use Plugins::KEXP::ProtocolHandler;
use Plugins::KEXP::Util qw(dayKey formatDay formatClock formatDuration);

use constant LIVE_URL   => Plugins::KEXP::Live::STREAM_URL;
use constant DONATE_URL => 'https://www.kexp.org/donate/';

my $log = Slim::Utils::Log->addLogCategory({
	category     => 'plugin.kexp',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_KEXP',
});

sub initPlugin {
	my $class = shift;

	Slim::Player::ProtocolHandlers->registerHandler(
		kexp => 'Plugins::KEXP::ProtocolHandler'
	);

	if (main::WEBUI) {
		require Plugins::KEXP::Settings;
		Plugins::KEXP::Settings->new;
	}

	Slim::Formats::RemoteMetadata->registerProvider(
		match => Plugins::KEXP::Live::URL_MATCH,
		func  => \&Plugins::KEXP::Live::metadataProvider,
	);

	Slim::Formats::RemoteMetadata->registerProvider(
		# Omny clip urls, before (traffic.omny.fm) and after (streamguys) redirect
		match => qr{^https?://[^/]+/d/clips/[^/]+/[^/]+/[0-9a-f-]{36}/}i,
		func  => \&Plugins::KEXP::LiveOnKEXP::metadataProvider,
	);

	$class->SUPER::initPlugin(
		feed   => \&handleFeed,
		tag    => 'kexp',
		menu   => 'radios',
		is_app => 1,
		weight => 10,
	);
}

sub getDisplayName { 'PLUGIN_KEXP' }

sub icon { __PACKAGE__->_pluginDataFor('icon') }

sub handleFeed {
	my ($client, $cb) = @_;

	$cb->({ items => [
		{
			name  => cstring($client, 'PLUGIN_KEXP_LIVE'),
			type  => 'audio',
			url   => LIVE_URL,
			image => icon(),
		},
		{
			name  => cstring($client, 'PLUGIN_KEXP_LIVE_ON_KEXP'),
			type  => 'link',
			url   => \&liveOnKexpMenu,
			image => icon(),
		},
		{
			name  => cstring($client, 'PLUGIN_KEXP_RECENT'),
			type  => 'link',
			url   => \&dayMenu,
			image => icon(),
		},
		{
			name  => cstring($client, 'PLUGIN_KEXP_PROGRAMS'),
			type  => 'link',
			url   => \&programMenu,
			image => icon(),
		},
		{
			name  => cstring($client, 'PLUGIN_KEXP_GENRES'),
			type  => 'link',
			url   => \&genreMenu,
			image => icon(),
		},
		# Web UIs that understand weblink (Material) open the page; players
		# that can't open a browser just show the address.
		{
			name    => cstring($client, 'PLUGIN_KEXP_DONATE'),
			type    => 'text',
			weblink => DONATE_URL,
			image   => icon(),
		},
	] });
}

sub _withShows {
	my ($client, $cb, $then) = @_;

	Plugins::KEXP::API->recentShows(sub {
		my $shows = shift;
		if (!$shows) {
			return $cb->({ items => [{
				name => cstring($client, 'PLUGIN_KEXP_ERROR'),
				type => 'text',
			}] });
		}
		$then->([ grep { Plugins::KEXP::API->isArchived($_) } @$shows ]);
	});
}

sub dayMenu {
	my ($client, $cb) = @_;

	_withShows($client, $cb, sub {
		my $shows = shift;

		my $tz = @$shows ? $shows->[0]->{tzOffset} : 0;
		my $today     = dayKey(time(), $tz);
		my $yesterday = dayKey(time() - 86400, $tz);

		my (@days, %seen);
		for my $show (@$shows) {
			my $key = dayKey($show->{start}, $show->{tzOffset});
			next if $seen{$key}++;

			my $label = $key eq $today     ? cstring($client, 'PLUGIN_KEXP_TODAY')
			          : $key eq $yesterday ? cstring($client, 'PLUGIN_KEXP_YESTERDAY')
			          : formatDay($show->{start}, $show->{tzOffset});

			push @days, {
				name        => $label,
				type        => 'link',
				url         => \&dayShows,
				passthrough => [$key],
				image       => icon(),
			};
		}

		$cb->({ items => \@days });
	});
}

sub dayShows {
	my ($client, $cb, undef, $key) = @_;

	_withShows($client, $cb, sub {
		my @shows = sort { $a->{start} <=> $b->{start} }
		            grep { dayKey($_->{start}, $_->{tzOffset}) eq $key } @{ shift() };

		$cb->({ items => [ map { _showItem($_, formatClock($_->{start}, $_->{tzOffset}) . '  ' . $_->{title}) } @shows ] });
	});
}

sub programMenu {
	my ($client, $cb) = @_;

	_withShows($client, $cb, sub {
		my %programs;
		for my $show (@{ shift() }) {
			push @{ $programs{ $show->{program} } }, $show;
		}

		$cb->({ items => [
			map {
				my $list = $programs{$_};
				{
					name        => $_,
					type        => 'link',
					url         => \&programShows,
					passthrough => [$_],
					image       => $list->[0]->{programImage} || icon(),
				}
			} sort { lc($a) cmp lc($b) } keys %programs
		] });
	});
}

sub programShows {
	my ($client, $cb, undef, $program) = @_;

	_withShows($client, $cb, sub {
		my @shows = grep { $_->{program} eq $program } @{ shift() };
		my @items;

		# a stable address for "newest show", so favourites and alarms don't
		# go stale when individual shows leave the archive
		if (@shows && $shows[0]->{programId}) {
			push @items, {
				name  => cstring($client, 'PLUGIN_KEXP_LATEST_EPISODE'),
				line1 => cstring($client, 'PLUGIN_KEXP_LATEST_EPISODE'),
				line2 => cstring($client, 'PLUGIN_KEXP_LATEST_HINT'),
				title => "$program (" . cstring($client, 'PLUGIN_KEXP_LATEST_EPISODE') . ')',
				type  => 'audio',
				url   => Plugins::KEXP::ProtocolHandler->latestUrl($shows[0]->{programId}),
				image => $shows[0]->{programImage} || icon(),
			};
		}

		push @items, map {
			my $when = formatDay($_->{start}, $_->{tzOffset}) . ', ' . formatClock($_->{start}, $_->{tzOffset});
			_showItem($_, $_->{host} ? "$when  $_->{host}" : $when);
		} @shows;

		$cb->({ items => \@items });
	});
}

sub genreMenu {
	my ($client, $cb) = @_;

	_withShows($client, $cb, sub {
		my (%shows, %programs);
		for my $show (@{ shift() }) {
			for my $genre (@{ $show->{genres} || ['Other'] }) {
				$shows{$genre}++;
				$programs{$genre}{ $show->{program} }++;
			}
		}

		$cb->({ items => [
			map {
				my $genre = $_;
				{
					name        => $genre,
					line1       => $genre,
					line2       => join(', ', sort keys %{ $programs{$genre} }),
					type        => 'link',
					url         => \&genreShows,
					passthrough => [$genre],
					image       => icon(),
				}
			}
			# "Other" last, everything else A-Z
			sort { ($a eq 'Other') <=> ($b eq 'Other') || lc($a) cmp lc($b) } keys %shows
		] });
	});
}

sub genreShows {
	my ($client, $cb, undef, $genre) = @_;

	_withShows($client, $cb, sub {
		my @shows = grep { grep { $_ eq $genre } @{ $_->{genres} || ['Other'] } } @{ shift() };

		$cb->({ items => [
			map {
				my $when = formatDay($_->{start}, $_->{tzOffset}) . ', ' . formatClock($_->{start}, $_->{tzOffset});
				_showItem($_, "$when  $_->{title}");
			} @shows
		] });
	});
}

# A show browses into its tracklist, but "play" on it plays the whole show
sub _showItem {
	my ($show, $label) = @_;

	return {
		name        => $label,
		line1       => $show->{title},
		line2       => $label,
		type        => 'link',
		url         => \&showMenu,
		passthrough => [$show->{id}],
		play        => "kexp://show/$show->{id}",
		image       => $show->{image} || icon(),
	};
}

sub showMenu {
	my ($client, $cb, undef, $id) = @_;

	Plugins::KEXP::API->getShow($id, sub {
		my $show = shift || return $cb->({ items => [{ name => cstring($client, 'PLUGIN_KEXP_ERROR'), type => 'text' }] });

		Plugins::KEXP::API->getPlays($id, sub {
			my $plays = shift || [];

			my @items = ({
				name  => cstring($client, 'PLUGIN_KEXP_PLAY_SHOW'),
				type  => 'audio',
				url   => "kexp://show/$id",
				image => $show->{image} || icon(),
			});

			push @items, { name => $show->{tagline}, type => 'text' } if $show->{tagline};

			for my $play (grep { $_->{type} eq 'trackplay' } @$plays) {
				my $from = $play->{start} - $show->{start};
				$from = 0 if $from < 0;

				my $label = join(' - ', grep { $_ } $play->{artist}, $play->{song});
				push @items, {
					name  => formatClock($play->{start}, $show->{tzOffset}) . '  ' . $label,
					line1 => $play->{song},
					line2 => join(' - ', grep { $_ } $play->{artist}, $play->{album}),
					type  => 'audio',
					url   => "kexp://show/$id/$from",
					image => $play->{image} || $show->{image} || icon(),
				};
			}

			$cb->({ items => \@items });
		});
	});
}

# --- Live on KEXP ---------------------------------------------------------

use constant LATEST_COUNT => 50;

sub _withEpisodes {
	my ($client, $cb, $then) = @_;

	Plugins::KEXP::LiveOnKEXP->episodes(sub {
		my $episodes = shift;
		if (!$episodes || !@$episodes) {
			return $cb->({ items => [{
				name => cstring($client, 'PLUGIN_KEXP_ERROR'),
				type => 'text',
			}] });
		}
		$then->($episodes);
	});
}

sub liveOnKexpMenu {
	my ($client, $cb) = @_;

	_withEpisodes($client, $cb, sub {
		my $episodes = shift;

		my @items = (
			{
				name  => cstring($client, 'PLUGIN_KEXP_LATEST'),
				type  => 'link',
				url   => \&lokLatest,
				image => $episodes->[0]->{image} || icon(),
			},
			{
				name  => cstring($client, 'PLUGIN_KEXP_SEARCH_ARTISTS'),
				type  => 'search',
				url   => \&lokSearch,
				image => icon(),
			},
		);

		my %seen;
		for my $year (grep { !$seen{$_}++ } map { _year($_->{date}) } @$episodes) {
			push @items, {
				name        => $year,
				type        => 'link',
				url         => \&lokYear,
				passthrough => [$year],
				image       => icon(),
			};
		}

		$cb->({ items => \@items });
	});
}

sub lokLatest {
	my ($client, $cb) = @_;

	_withEpisodes($client, $cb, sub {
		my $episodes = shift;
		my $last = $#$episodes < LATEST_COUNT - 1 ? $#$episodes : LATEST_COUNT - 1;
		$cb->({ items => [ map { _episodeItem($_) } @$episodes[0 .. $last] ] });
	});
}

sub lokYear {
	my ($client, $cb, undef, $year) = @_;

	_withEpisodes($client, $cb, sub {
		$cb->({ items => [ map { _episodeItem($_) } grep { _year($_->{date}) eq $year } @{ shift() } ] });
	});
}

sub lokSearch {
	my ($client, $cb, $args) = @_;

	my $query = lc($args->{search} || '');
	$query =~ s/^\s+|\s+$//g;
	return $cb->({ items => [] }) unless length $query;

	_withEpisodes($client, $cb, sub {
		my @hits = grep { index(lc $_->{title}, $query) >= 0 } @{ shift() };

		$cb->({ items => @hits
			? [ map { _episodeItem($_) } @hits ]
			: [{ name => cstring($client, 'EMPTY'), type => 'text' }]
		});
	});
}

sub _year {
	my $epoch = shift || return '?';
	return (gmtime($epoch))[5] + 1900;
}

sub _episodeDate {
	my $ep = shift;
	my $date = $ep->{date} ? formatDay($ep->{date}, 0) . ', ' . _year($ep->{date}) : '';
	$date =~ s/^\w+ //;    # "Oct 22, 2026" - weekday is noise here
	return $date;
}

# A session browses into its notes and setlist; "play" on it plays it
sub _episodeItem {
	my $ep = shift;

	my $date = _episodeDate($ep);
	my $info = join(' · ', grep { $_ } $date, formatDuration($ep->{secs}));

	return {
		name        => $date ? "$ep->{artist} ($date)" : $ep->{artist},
		line1       => $ep->{artist},
		line2       => $info,
		type        => 'link',
		url         => \&sessionMenu,
		passthrough => [$ep->{key}],
		play        => $ep->{url},
		image       => $ep->{image} || icon(),
	};
}

sub sessionMenu {
	my ($client, $cb, undef, $key) = @_;

	Plugins::KEXP::LiveOnKEXP->byKey($key, sub {
		my $ep = shift || return $cb->({ items => [{ name => cstring($client, 'PLUGIN_KEXP_ERROR'), type => 'text' }] });

		my $date = _episodeDate($ep);
		my @items = ({
			name     => cstring($client, 'PLUGIN_KEXP_PLAY_SESSION'),
			line2    => join(' · ', grep { $_ } $date, formatDuration($ep->{secs})),
			title    => $ep->{artist},
			artist   => 'Live on KEXP',
			album    => $date,
			type     => 'audio',
			url      => $ep->{url},
			image    => $ep->{image} || icon(),
			duration => $ep->{secs},
		});

		push @items, { name => $ep->{intro}, type => 'textarea' } if $ep->{intro};

		if (my $songs = $ep->{setlist}) {
			push @items, { name => cstring($client, 'PLUGIN_KEXP_SETLIST'), type => 'text' };
			my $n = 0;
			push @items, map { { name => ++$n . '. ' . $_, type => 'text' } } @$songs;
		}

		$cb->({ items => \@items });
	});
}

1;
