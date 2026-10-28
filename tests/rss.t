use strict;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use utf8;

use Plugins::KEXP::Util qw(parseRfc822 parseRssItems formatDuration);

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

# Real feed, when a copy is around (scripts don't download it for tests)
if (my $feed = $ENV{KEXP_FEED} and -f $ENV{KEXP_FEED}) {
	open my $fh, '<:encoding(UTF-8)', $feed or die $!;
	my $real = parseRssItems(do { local $/; <$fh> });
	cmp_ok(scalar @$real, '>', 1000, 'real feed: >1000 episodes');
	is(scalar(grep { !$_->{date} } @$real), 0, 'real feed: all dated');
	my @odd = grep { $_->{artist} =~ /live on kexp/i } @$real;
	diag("unstripped titles: " . join(' | ', map { $_->{title} } @odd[0 .. ($#odd < 9 ? $#odd : 9)])) if @odd;
	diag("newest: $real->[0]{artist}; oldest: $real->[-1]{artist}");
}

done_testing;
