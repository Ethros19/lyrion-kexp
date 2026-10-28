use strict;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";   # Plugins::KEXP::* shim -> src/KEXP

use Plugins::KEXP::Util qw(parseTime isoUTC dayKey formatDay formatClock genresForTags);

my ($epoch, $tz) = parseTime('2026-10-27T22:00:36-07:00');
is($tz, -7 * 3600, 'keeps station offset');
is(isoUTC($epoch), '2026-10-28T05:00:36Z', 'converts to UTC');
is(dayKey($epoch, $tz), '2026-10-27', 'station-local day');
is(formatDay($epoch, $tz), 'Tue Oct 27', 'day label');
is(formatClock($epoch, $tz), '10:00 PM', 'clock label');

is(formatClock(scalar parseTime('2026-10-26T00:05:00-07:00'), $tz), '12:05 AM', 'midnight hour');
is(formatClock(scalar parseTime('2026-10-26T12:30:00-07:00'), $tz), '12:30 PM', 'noon hour');
is(scalar parseTime('2026-10-26T07:00:00Z'), scalar parseTime('2026-10-26T00:00:00-07:00'), 'Z equals offset form');
is(parseTime('garbage'), undef, 'rejects junk');

is_deeply([genresForTags('Rock,Eclectic,Variety Mix')], ['Variety Mix'], 'daytime shows -> Variety Mix');
is_deeply([genresForTags('Wave,Synth,Post Punk,EBM')], ['Post-Punk & Synth'], 'merged neighbours');
is_deeply([genresForTags('Metal,Rock')], ['Metal'], 'generic Rock dropped');
is_deeply([genresForTags('Latin,World')], ['Latin', 'World'], 'multiple genres');
is_deeply([genresForTags('Rock')], ['Rock'], 'generic kept when nothing else');
is_deeply([genresForTags('KEXP')], ['Other'], 'meaningless tag -> Other');
is_deeply([genresForTags(undef)], ['Other'], 'no tags -> Other');
is_deeply([genresForTags('Shoegaze')], ['Shoegaze'], 'unknown tags pass through');

done_testing;
