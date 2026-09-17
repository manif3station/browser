use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Search;

# D2B-050: Browser::Search::_strip_tags only strips HTML tags - it never
# decodes HTML entities. A real search-engine result page commonly encodes
# ampersands, apostrophes, and quotes as entities in link text/snippets, so
# the returned title/snippet fields contain the literal entity text instead
# of the real character.

is( Browser::Search::_strip_tags('Ben &amp; Jerry&#39;s'), q{Ben & Jerry's}, 'named entity &amp; and numeric decimal entity &#39; are both decoded' );
is( Browser::Search::_strip_tags('<b>Rock &amp;amp; Roll</b>'), 'Rock &amp; Roll', 'a double-encoded &amp;amp; inside a real tag is stripped to one decode pass (&amp;), matching standard single-pass entity decoding rather than recursively unescaping' );
is( Browser::Search::_strip_tags('&quot;quoted&quot; &#x27;text&#x27;'), q{"quoted" 'text'}, 'named &quot; and numeric hex &#x27; entities are decoded' );
is( Browser::Search::_strip_tags('<span>plain text</span>'), 'plain text', 'plain text with no entities is unaffected (no regression)' );

my $result = eval { Browser::Search::_strip_tags('bad &#999999999999999999999; entity') };
ok( !$@, 'an out-of-Unicode-range numeric entity does not crash the decoder' ) or diag("Died with: $@");

done_testing();
