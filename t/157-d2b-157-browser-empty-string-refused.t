use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner::BrowserPath;

# D2B-157: _launch_options's browser default handling used
# $args{browser} || 'chrome', which silently coerced an explicit
# empty-string --browser value to the default instead of refusing it -
# unlike Browser::Runner::_goto_options's --wait-until handling, which
# already distinguishes "not given" from "given but empty" and dies on
# the latter. TDD red: this is not yet fixed.

eval { Browser::Runner::BrowserPath::_launch_options( browser => q{} ) };
like( $@, qr/Unsupported browser type/i, '_launch_options refuses an explicit empty-string --browser value instead of silently defaulting to chrome' );

my %launch = eval { Browser::Runner::BrowserPath::_launch_options() };
ok( !$@, 'omitting --browser entirely still does not die' ) or diag("Got: $@");
is( $launch{type}, 'chrome', 'omitting --browser entirely still defaults to chrome' );

done_testing();
