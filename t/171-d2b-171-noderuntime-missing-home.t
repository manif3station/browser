use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner::NodeRuntime;

# D2B-171: closes the untested missing-HOME guard in
# lib/Browser/Runner/NodeRuntime.pm's _ensure_node_runtime - the exact
# sibling of D2B-170's Runner.pm::_jquery_path finding in the sister
# module. No behavioral change - the guard already does the right
# thing; this test proves and documents it.

{
    local $ENV{HOME} = q{};
    eval { Browser::Runner::NodeRuntime::_ensure_node_runtime() };
    like(
        $@,
        qr/HOME is required for browser skill Node dependencies/,
        '_ensure_node_runtime fails clearly when HOME is not set'
    );
}

done_testing();
