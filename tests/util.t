use strict;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";   # Plugins::KEXP::* shim -> src/KEXP

use Plugins::KEXP::Util qw(parseTime isoUTC dayKey formatDay formatClock genresForTags aacTiming adtsSync);

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

# AAC archive timing: exact average when plausible, else the typical 133 kbps
{
	my ($bitrate, $secs) = aacTiming(189_822_006, 10800, 620);
	is($bitrate, int(189_822_006 * 8 / 11420), 'bitrate from size / (pre-roll + show)');
	is(int($secs), 11420, 'file length = pre-roll + show');

	($bitrate, $secs) = aacTiming(36_161_096, 10800, 741);    # truncated file
	is($bitrate, 133_000, 'truncated file -> typical bitrate');
	is(int($secs), int(36_161_096 * 8 / 133_000), '... and its real length');

	is_deeply([aacTiming(undef, 10800, 600)], [133_000, 11400], 'no size -> pre-roll + show');
	is_deeply([aacTiming(undef, undef, 600)], [133_000, undef], 'nothing known');
}

# ADTS sync: skip junk and false 0xFFF syncs, need a matching next header
{
	# LC, 44.1 kHz, stereo, frame length $n
	my $frame = sub { my $n = shift; pack('C7', 0xFF, 0xF1, 0x50, 0x80 | ($n >> 11), ($n >> 3) & 0xFF, (($n & 7) << 5) | 0x1F, 0xFC) . ("\x00" x ($n - 7)) };
	my $fake  = "\xFF\xF1\x50\x80\x01\x00\x00";    # plausible header, no frame after it

	is(adtsSync($frame->(300) . $frame->(310)), 0, 'aligned');
	is(adtsSync("junk" . $fake . "xx" . $frame->(300) . $frame->(300)), 13, 'skips junk and a false sync');
	is(adtsSync("junk" . $frame->(300)), undef, 'needs the next header');
	is(adtsSync(''), undef, 'empty');
}

done_testing;
