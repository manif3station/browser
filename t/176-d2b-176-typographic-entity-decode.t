use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Search;

# D2B-176: Browser::Search::_decode_entities only decoded amp/lt/gt/quot
# /apos (D2B-050/054) plus numeric/hex references and surrogate pairs -
# common typographic entities realistically found in real search-engine
# snippet/title text (nbsp, mdash, ndash, curly quotes, hellip, copy,
# trade, reg) were left as literal entity text. This is a genuine
# behavior addition - these assertions are written to fail against the
# pre-fix code first.

is( Browser::Search::_decode_entities('a&nbsp;b'), "a\x{00A0}b", '&nbsp; decodes to U+00A0 non-breaking space' );
is( Browser::Search::_decode_entities('day&mdash;night'), "day\x{2014}night", '&mdash; decodes to U+2014 em dash' );
is( Browser::Search::_decode_entities('day&ndash;night'), "day\x{2013}night", '&ndash; decodes to U+2013 en dash' );
is( Browser::Search::_decode_entities('&lsquo;quoted&rsquo;'), "\x{2018}quoted\x{2019}", '&lsquo;/&rsquo; decode to U+2018/U+2019 curly single quotes' );
is( Browser::Search::_decode_entities('&ldquo;quoted&rdquo;'), "\x{201C}quoted\x{201D}", '&ldquo;/&rdquo; decode to U+201C/U+201D curly double quotes' );
is( Browser::Search::_decode_entities('wait&hellip;'), "wait\x{2026}", '&hellip; decodes to U+2026 ellipsis' );
is( Browser::Search::_decode_entities('Acme&copy;'), "Acme\x{00A9}", '&copy; decodes to U+00A9 copyright sign' );
is( Browser::Search::_decode_entities('Acme&trade;'), "Acme\x{2122}", '&trade; decodes to U+2122 trademark sign' );
is( Browser::Search::_decode_entities('Acme&reg;'), "Acme\x{00AE}", '&reg; decodes to U+00AE registered sign' );

is( Browser::Search::_decode_entities('a&foobar;b'), 'a&foobar;b', 'a genuinely unsupported named entity is left unchanged, matching the existing fallback' );

is( Browser::Search::_decode_entities('Ben &amp; Jerry&#39;s'), q{Ben & Jerry's}, 'existing D2B-050 amp/numeric-decimal decoding is unaffected' );
is( Browser::Search::_decode_entities('&quot;quoted&quot; &#x27;text&#x27;'), q{"quoted" 'text'}, 'existing D2B-050 quot/hex decoding is unaffected' );

done_testing();
