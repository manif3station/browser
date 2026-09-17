use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner::BrowserPath;

# D2B-033: an unrecognized --browser value was passed through unchecked
# to Playwright's own launch(), producing whatever opaque native error
# Playwright throws instead of a clear, skill-level error naming the
# invalid value and the supported list.

eval { Browser::Runner::BrowserPath::_launch_options( browser => 'notreal' ) };
like( $@, qr/Unsupported browser type/i, '_launch_options refuses an unrecognized --browser value with a clear message' );
like( $@, qr/notreal/, 'the error names the actual invalid value the caller gave' );
like( $@, qr/chrome/i, 'the error names at least one supported browser type' );

for my $valid (qw(chrome chromium firefox webkit)) {
    my %launch = eval { Browser::Runner::BrowserPath::_launch_options( browser => $valid ) };
    ok( !$@, "a genuinely supported --browser value ($valid) is still accepted without dying" ) or diag("Got: $@");
}

done_testing();
