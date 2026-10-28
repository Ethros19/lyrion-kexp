package Plugins::KEXP::Util;

# Pure helpers with no Lyrion dependencies, so they can be unit tested
# outside the server (see tests/util.t).

use strict;
use Exporter qw(import);
use Time::Local qw(timegm);

our @EXPORT_OK = qw(parseTime isoUTC stationParts dayKey formatDay formatClock);

my @DAYS   = qw(Sun Mon Tue Wed Thu Fri Sat);
my @MONTHS = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

# "2026-10-27T22:00:36-07:00" -> ($epoch, $utcOffsetSeconds)
# KEXP timestamps carry the station's (Pacific) offset; we keep it so menus
# can show station wall-clock time regardless of the server's time zone.
sub parseTime {
	my $str = shift || return;

	my ($y, $m, $d, $H, $M, $S, $tz) = $str =~
		/^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(?:\.\d+)?(Z|[+-]\d\d:?\d\d)?$/
		or return;

	my $offset = 0;
	if ($tz && $tz ne 'Z') {
		my ($sign, $oh, $om) = $tz =~ /([+-])(\d\d):?(\d\d)/;
		$offset = ($oh * 3600 + $om * 60) * ($sign eq '-' ? -1 : 1);
	}

	my $epoch = timegm($S, $M, $H, $d, $m - 1, $y) - $offset;
	return wantarray ? ($epoch, $offset) : $epoch;
}

sub isoUTC {
	my @t = gmtime(shift);
	return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ', $t[5] + 1900, $t[4] + 1, @t[3, 2, 1, 0]);
}

# Wall-clock parts at the given UTC offset
sub stationParts {
	my ($epoch, $offset) = @_;
	my @t = gmtime($epoch + ($offset || 0));
	return {
		year => $t[5] + 1900,
		mon  => $t[4] + 1,
		mday => $t[3],
		wday => $t[6],
		hour => $t[2],
		min  => $t[1],
	};
}

sub dayKey {
	my $p = stationParts(@_);
	return sprintf('%04d-%02d-%02d', $p->{year}, $p->{mon}, $p->{mday});
}

# "Tue Oct 27"
sub formatDay {
	my $p = stationParts(@_);
	return sprintf('%s %s %d', $DAYS[$p->{wday}], $MONTHS[$p->{mon} - 1], $p->{mday});
}

# "10:00 PM"
sub formatClock {
	my $p = stationParts(@_);
	my $h = $p->{hour} % 12 || 12;
	return sprintf('%d:%02d %s', $h, $p->{min}, $p->{hour} < 12 ? 'AM' : 'PM');
}

1;
