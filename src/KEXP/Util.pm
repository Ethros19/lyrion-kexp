package Plugins::KEXP::Util;

# Pure helpers with no Lyrion dependencies, so they can be unit tested
# outside the server (see tests/util.t).

use strict;
use Exporter qw(import);
use Time::Local qw(timegm);

our @EXPORT_OK = qw(parseTime isoUTC stationParts dayKey formatDay formatClock
                    parseRfc822 parseRssItems parseSessionNotes formatDuration
                    genresForTags);

my @DAYS   = qw(Sun Mon Tue Wed Thu Fri Sat);
my @MONTHS = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
my %MONTH_NUM = map { $MONTHS[$_] => $_ } 0 .. 11;

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

# "Thu, 22 Oct 2026 11:00:00 +0000" -> epoch
sub parseRfc822 {
	my $str = shift || return;

	my ($d, $mon, $y, $H, $M, $S, $tz) = $str =~
		/(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d\d):(\d\d)(?::(\d\d))?\s*([+-]\d{4}|GMT|UTC|Z)?/
		or return;
	defined(my $m = $MONTH_NUM{ ucfirst lc $mon }) or return;

	my $offset = 0;
	if ($tz && $tz =~ /([+-])(\d\d)(\d\d)/) {
		$offset = ($2 * 3600 + $3 * 60) * ($1 eq '-' ? -1 : 1);
	}

	return timegm($S || 0, $M, $H, $d, $m, $y) - $offset;
}

sub _xmlText {
	my $s = shift;
	return '' unless defined $s;
	$s =~ s/^\s*<!\[CDATA\[(.*?)\]\]>\s*$/$1/s;
	$s =~ s/&lt;/</g;
	$s =~ s/&gt;/>/g;
	$s =~ s/&quot;/"/g;
	$s =~ s/&apos;|&#39;/'/g;
	$s =~ s/&#x([0-9a-fA-F]+);/chr(hex $1)/ge;
	$s =~ s/&#(\d+);/chr($1)/ge;
	$s =~ s/&amp;/&/g;
	$s =~ s/^\s+|\s+$//g;
	return $s;
}

# <description> is CDATA-wrapped HTML in this feed, but may be entity-escaped
sub _descHtml {
	my $s = shift;
	return '' unless defined $s;
	return $1 if $s =~ /^\s*<!\[CDATA\[(.*?)\]\]>\s*$/s;
	return _xmlText($s);
}

# LMS bundles HTML::Entities (Slim::Formats::XML uses it); fall back to the
# XML basics if it's ever missing
my $HAS_ENTITIES = eval { require HTML::Entities; 1 };

# HTML fragment -> plain text
sub _htmlText {
	my $s = shift;
	$s =~ s/<[^>]+>//g;
	$s = $HAS_ENTITIES ? HTML::Entities::decode_entities($s) : _xmlText($s);
	$s =~ s/\x{a0}/ /g;
	$s =~ s/^\s+|\s+$//g;
	$s =~ s/\s+/ /g;
	return $s;
}

my $BOILERPLATE = qr/support the show|omnystudio|privacy information|join this channel/i;
my $ROLE_LINE   = qr/^[^:]{1,40}:\s/;          # "Host: Cheryl Waters"
my $DASH        = qr/\s[-\x{2013}\x{2014}]\s/;  # "Ben Gibbard - Vocals"

# Session notes HTML -> ($intro, \@setlist). Episode notes have changed
# format over the years; in order of reliability the setlist is:
#   1. an HTML list (<ol>/<ul>), 2020 onwards
#   2. a "Songs: A / B / C" line
#   3. a paragraph of one title per line (<br>), between intro and credits
#   4. inline "Recorded … - 4 songs: A, B, C." (2014-2019)
sub parseSessionNotes {
	my $html = shift;
	return ('', undef) unless defined $html && length $html;

	# paragraphs as lists of non-empty lines, minus podcast boilerplate
	my @paras;
	for my $p (split m{</?(?:p|ol|ul)\b[^>]*>}i, $html) {
		my @lines = grep { length } map { _htmlText($_) } split m{<br\s*/?>|</li>}i, $p;
		push @paras, \@lines if @lines && join(' ', @lines) !~ $BOILERPLATE;
	}

	my $intro = @paras ? join(' ', @{ $paras[0] }) : '';
	my $setlist;

	if ($html =~ m{<[ou]l\b[^>]*>(.*?)</[ou]l>}is) {
		my @songs = grep { length && !/http/ && length() <= 100 }
		            map { _htmlText($_) } $1 =~ m{<li\b[^>]*>(.*?)</li>}gis;
		$setlist = \@songs if @songs;
	}

	if (!$setlist) {
		for my $p (@paras) {
			my $line = join(' / ', @$p);
			if ($line =~ m{^\s*(?:songs|set\s*list|tracks?)\s*:\s*(.+)$}i) {
				my @songs = grep { length } map { s/^\s+|\s+$//gr } split m{\s+/\s+}, $1;
				if (@songs) { $setlist = \@songs; last }
			}
		}
	}

	if (!$setlist) {
		for my $p (@paras[1 .. $#paras]) {
			next if @$p < 2;
			next if grep { length() > 80 || /http/ || $_ =~ $ROLE_LINE || /^recorded\b/i } @$p;
			next if 2 * (grep { $_ =~ $DASH } @$p) >= @$p;
			$setlist = [ map { s/^\d+\s*[.)]\s*//r } @$p ];
			last;
		}
	}

	if (!$setlist) {
		for my $p (@paras) {
			if (join(' ', @$p) =~ m{\d+\s+songs?\s*[:\-\x{2013}]\s*(.+?)\.?\s*$}i) {
				my @songs = grep { length } map { s/^\s+|\s+$//gr } split /,\s*/, $1;
				if (@songs) { $setlist = \@songs; last }
			}
		}
	}

	# drop a trailing run of "Name - Instrument" lines that leaked in
	if ($setlist) {
		my @songs = @$setlist;
		pop @songs while @songs > 1 && $songs[-1] =~ $DASH && grep { $_ !~ $DASH } @songs[0 .. $#songs - 1];
		$setlist = \@songs;
	}

	$intro = substr($intro, 0, 497) . '...' if length $intro > 500;
	return ($intro, $setlist);
}

# Minimal podcast RSS parser: just what we need, and fast enough for a
# ~5 MB feed (XML::Simple takes seconds and would block the server).
sub parseRssItems {
	my $xml = shift;
	my @items;

	while ($xml =~ m{<item>(.*?)</item>}gs) {
		my $item = $1;

		my ($url) = $item =~ m{<enclosure[^>]*\burl="([^"]+)"};
		next unless $url;

		my ($title) = $item =~ m{<title>(.*?)</title>}s;
		$title = _xmlText($title);

		my $artist = $title;
		$artist =~ s/\s*[(\[]\s*Live on KEXP[^)\]]*[)\]]\s*$//i;
		$artist =~ s/\s*[-|:]\s*Live on KEXP.*$//i;

		my ($image) = $item =~ m{<itunes:image[^>]*\bhref="([^"]+)"};
		my ($dur)   = $item =~ m{<itunes:duration>([^<]+)</itunes:duration>};
		my ($date)  = $item =~ m{<pubDate>([^<]+)</pubDate>};

		# itunes:duration is seconds, MM:SS or HH:MM:SS
		my $secs = 0;
		if (defined $dur) {
			my @p = reverse split /:/, $dur;
			$secs = ($p[0] || 0) + ($p[1] || 0) * 60 + ($p[2] || 0) * 3600;
		}

		my ($desc) = $item =~ m{<description>(.*?)</description>}s;
		my ($intro, $setlist) = parseSessionNotes(_descHtml($desc));

		push @items, {
			title  => $title,
			artist => $artist || $title,
			url    => _xmlText($url),
			image  => $image ? _xmlText($image) : undef,
			secs   => $secs,
			date   => parseRfc822($date),
			intro  => $intro,
			setlist => $setlist,
		};
	}

	return [ sort { ($b->{date} || 0) <=> ($a->{date} || 0) } @items ];
}

# 1145 -> "19 min", 4000 -> "1 hr 7 min"
sub formatDuration {
	my $secs = shift || return '';
	my $min = int($secs / 60 + 0.5);
	return $min < 60 ? "$min min" : sprintf('%d hr %d min', int($min / 60), $min % 60);
}

# Program tags -> browseable genres. KEXP tags every daytime show
# "Rock, Eclectic, Variety Mix", so the generic tags are dropped when a
# program has anything more specific, and close neighbours are merged.
my %GENERIC = map { lc $_ => 1 } ('Rock', 'Eclectic', 'KEXP', 'DJ', 'Local', 'Live', 'Live Music');
my %GENRE_MAP = (
	'variety'           => 'Variety Mix',
	'variety mix'       => 'Variety Mix',
	'wave'              => 'Post-Punk & Synth',
	'synth'             => 'Post-Punk & Synth',
	'post punk'         => 'Post-Punk & Synth',
	'ebm'               => 'Post-Punk & Synth',
	'blues'             => 'Roots, Blues & Country',
	'country'           => 'Roots, Blues & Country',
	'roots'             => 'Roots, Blues & Country',
	'rockabilly'        => 'Roots, Blues & Country',
	'afrobeat'          => 'African & Afrobeat',
	'african'           => 'African & Afrobeat',
	'psychedelic'       => 'Psychedelic & Experimental',
	'experimental'      => 'Psychedelic & Experimental',
	'public affairs'    => 'Talk & Public Affairs',
	'pacific northwest' => 'Northwest & Local',
	'bay area'          => 'Northwest & Local',
);

sub genresForTags {
	my @tags = grep { length } map { s/^\s+|\s+$//gr } split /,/, (shift // '');

	my @specific = grep { !$GENERIC{ lc $_ } } @tags;
	@specific = grep { lc($_) ne 'kexp' } @tags unless @specific;    # e.g. just "Rock"

	my %seen;
	my @genres = grep { !$seen{$_}++ } map { $GENRE_MAP{ lc $_ } || $_ } @specific;
	return @genres ? @genres : ('Other');
}

1;
