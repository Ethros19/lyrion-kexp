package Plugins::KEXP::Plugin;

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

use Plugins::KEXP::API;
use Plugins::KEXP::ProtocolHandler;
use Plugins::KEXP::Util qw(dayKey formatDay formatClock);

use constant LIVE_URL => 'https://kexp.streamguys1.com/kexp160.aac';

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
		$then->([ grep { !$_->{live} } @$shows ]);
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

		$cb->({ items => [
			map {
				my $when = formatDay($_->{start}, $_->{tzOffset}) . ', ' . formatClock($_->{start}, $_->{tzOffset});
				_showItem($_, $_->{host} ? "$when  $_->{host}" : $when);
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

1;
