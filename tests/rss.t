use strict;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use utf8;

use Plugins::KEXP::Util qw(parseRfc822 parseRssItems parseSessionNotes formatDuration);

is(parseRfc822('Thu, 22 Oct 2026 11:00:00 +0000'), 1792666800, 'rfc822 UTC');
is(parseRfc822('Wed, 26 Jun 2013 00:00:00 -0700'), parseRfc822('Wed, 26 Jun 2013 07:00:00 +0000'), 'rfc822 offset');

my $xml = <<'XML';
<rss><channel>
<item>
  <title>Numeron (Live on KEXP)</title>
  <pubDate>Wed, 21 Oct 2026 11:00:00 +0000</pubDate>
  <itunes:duration>1761</itunes:duration>
  <itunes:image href="https://img/2.jpg?t=1&amp;size=Large"/>
  <enclosure url="https://traffic.omny.fm/2.mp3?a=1&amp;b=2" length="1" type="audio/mpeg"/>
</item>
<item>
  <title><![CDATA[Sigur Rós & Friends - Live on KEXP]]></title>
  <pubDate>Thu, 22 Oct 2026 11:00:00 +0000</pubDate>
  <itunes:duration>01:02:03</itunes:duration>
  <enclosure url="https://traffic.omny.fm/1.mp3" type="audio/mpeg"/>
</item>
<item><title>No audio</title></item>
</channel></rss>
XML

my $items = parseRssItems($xml);
is(scalar @$items, 2, 'skips items without enclosure');
is($items->[0]{artist}, 'Sigur Rós & Friends', 'newest first, strips " - Live on KEXP"');
is($items->[0]{secs}, 3723, 'HH:MM:SS duration');
is($items->[1]{artist}, 'Numeron', 'strips "(Live on KEXP)"');
is($items->[1]{url}, 'https://traffic.omny.fm/2.mp3?a=1&b=2', 'decodes &amp; in url');
is($items->[1]{image}, 'https://img/2.jpg?t=1&size=Large', 'image');

is(formatDuration(1145), '19 min', 'short duration');
is(formatDuration(4000), '1 hr 7 min', 'long duration');

# --- setlists, one case per format seen in the feed ---
my ($intro, $set);

($intro, $set) = parseSessionNotes('<p>KEXP presents Sera Cahoone. Recorded July 23, 2026.</p> <ol> <li>Pulling Up Roots</li> <li>Hits Right&nbsp;</li> </ol> <p><br>Sera Cahoone - Acoustic, Vocals<br>Alex Guy - Violin</p>');
is_deeply($set, ['Pulling Up Roots', 'Hits Right'], 'html list');
is($intro, 'KEXP presents Sera Cahoone. Recorded July 23, 2026.', 'intro is first paragraph');

($intro, $set) = parseSessionNotes('<p>Intro.</p><p>Songs: I Built You A Tower / How Heavenly A State</p><p>Ben Gibbard - Vocals</p>');
is_deeply($set, ['I Built You A Tower', 'How Heavenly A State'], '"Songs:" line');

($intro, $set) = parseSessionNotes('<p>Intro.</p> <p>1. WIZARD<br>2. SIREN<br>3. Nightblood</p> <p>Riley - Vocals<br>Franco - Guitar</p> <p>Host: Tanner Ellison<br>Audio Engineer: Kevin</p><p>Support the show: https://www.kexp.org/donate</p>');
is_deeply($set, ['WIZARD', 'SIREN', 'Nightblood'], 'br paragraph, numbering stripped, musicians skipped');

($intro, $set) = parseSessionNotes('<p>Fauna Shade visit KEXP. Recorded 02/17/2016 - 4 songs: No Nostalgia, Marzipan, Delirium, Bazzle Shabbazz.</p>');
is_deeply($set, ['No Nostalgia', 'Marzipan', 'Delirium', 'Bazzle Shabbazz'], 'inline "N songs:"');

($intro, $set) = parseSessionNotes('<p>Recorded 09/27/2019. 4 songs - Weyu L&aacute;rigi Weyu, Banda.</p>');
is_deeply($set, ['Weyu Lárigi Weyu', 'Banda'], 'inline "N songs -" with named entity');

($intro, $set) = parseSessionNotes('<p>Intro.</p><ol><li>Sarniezz</li><li>Sherpa</li><li>Khn de Poitrine - Microtonal Guitars</li><li>Klek de Poitrine - Drums</li></ol>');
is_deeply($set, ['Sarniezz', 'Sherpa'], 'trailing musician lines trimmed');

($intro, $set) = parseSessionNotes('<p>Dan Bejar is hard to pin down.</p><p>Recorded June 21, 2021</p><p>Kokomo, IN</p><p>See omnystudio.com/listener for privacy information.</p>');
is($set, undef, 'no setlist when there is none');

# Real feed, when a copy is around (scripts don't download it for tests)
if (my $feed = $ENV{KEXP_FEED} and -f $ENV{KEXP_FEED}) {
	open my $fh, '<:encoding(UTF-8)', $feed or die $!;
	my $real = parseRssItems(do { local $/; <$fh> });
	cmp_ok(scalar @$real, '>', 1000, 'real feed: >1000 episodes');
	is(scalar(grep { !$_->{date} } @$real), 0, 'real feed: all dated');
	my $withSet = grep { $_->{setlist} } @$real;
	my $newest = grep { $_->{setlist} } @$real[0 .. 19];
	cmp_ok($newest, '>=', 15, "real feed: $newest/20 newest sessions have setlists (new notes format?)");
	cmp_ok($withSet / @$real, '>', 0.9, sprintf('real feed: %d/%d have setlists', $withSet, scalar @$real));
	my @odd = grep { $_->{artist} =~ /live on kexp/i } @$real;
	diag("unstripped titles: " . join(' | ', map { $_->{title} } @odd[0 .. ($#odd < 9 ? $#odd : 9)])) if @odd;
	diag("newest: $real->[0]{artist}; oldest: $real->[-1]{artist}");
}

done_testing;
