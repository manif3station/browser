use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner::BrowserPath;

# D2B-185: _launch_options's browser-type matching is an exact,
# case-sensitive grep against @SUPPORTED_BROWSER_TYPES (chrome, chromium,
# firefox, webkit). --browser Chrome or --browser WEBKIT die with
# "Unsupported browser type" even though the intent is unambiguous, unlike
# sibling --engine/--engines handling (D2B-042) which already normalizes case.

for my $mixed_case (qw(Chrome CHROMIUM Firefox WebKit)) {
    my %launch = eval { Browser::Runner::BrowserPath::_launch_options( browser => $mixed_case ) };
    ok( !$@, "--browser accepts a mixed-case value ($mixed_case) instead of dying with \"Unsupported browser type\"" ) or diag("Got error: $@");
    is( $launch{type}, lc($mixed_case) eq 'chromium' ? 'chrome' : lc($mixed_case), "the resolved launch type for $mixed_case is still the canonical lowercase form" ) if %launch;
}

eval { Browser::Runner::BrowserPath::_launch_options( browser => 'NotReal' ) };
like( $@, qr/Unsupported browser type/i, '_launch_options still refuses a genuinely unrecognized --browser value regardless of case' );
like( $@, qr/NotReal/, 'the error names the actual invalid value the caller gave' );

done_testing();
