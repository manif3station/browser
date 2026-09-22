use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Search;

# D2B-160: Browser::Search::search() carries 3 validation guards
# (Missing query, At least one engine is required, --max must not be
# negative) that are unreachable through Browser::CLI::execute_search()
# because CLI.pm has its own earlier copies of the same checks. Verified
# via Devel::Cover -coverage branch that these 3 branches were never
# exercised (86% branch coverage on this file despite 100%
# statement/subroutine). These direct-call tests prove the guards work
# correctly for any caller that bypasses execute_search(), matching the
# D2B-130 precedent already established in this same file.

eval { Browser::Search::search( query => q{} ) };
like( $@, qr/Missing query/, 'search() directly refuses an empty query, proving this guard works for any caller bypassing execute_search()' );

eval { Browser::Search::search( query => 'test', engines => [] ) };
like( $@, qr/At least one engine is required/, 'search() directly refuses an empty engines list' );

eval { Browser::Search::search( query => 'test', max => -1 ) };
like( $@, qr/--max must not be negative/, 'search() directly refuses a negative max' );

done_testing();
