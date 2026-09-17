use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Search;

# D2B-027: the default duckduckgo engine URL must point directly at
# html.duckduckgo.com, not the bare duckduckgo.com host - verified live
# with curl -sIL that 'https://duckduckgo.com/html/?q=...' 302-redirects
# to 'https://html.duckduckgo.com/html/?q=...'. Playwright follows the
# redirect transparently, so this was never a functional bug, just an
# avoidable extra HTTP round trip on every duckduckgo search.

my %by_name = map { $_->{name} => $_ } Browser::Search::_default_engines();
my $url = $by_name{duckduckgo}{url}->('test query');

like( $url, qr{\Ahttps://html\.duckduckgo\.com/}, 'the default duckduckgo engine URL goes straight to html.duckduckgo.com, skipping the redirect hop' );

done_testing();
