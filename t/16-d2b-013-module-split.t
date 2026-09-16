use strict;
use warnings;

use Test::More;

# D2B-013: Runner.pm must be split so each resulting file is 500 lines or
# fewer. Confirms both extracted modules exist and are independently
# loadable.

use_ok('Browser::Runner::NodeRuntime');
use_ok('Browser::Runner::BrowserPath');
use_ok('Browser::Runner');

ok( Browser::Runner::NodeRuntime->can('_version_satisfies_spec'), 'NodeRuntime carries the Node dependency version logic' );
ok( Browser::Runner::BrowserPath->can('_launch_options'), 'BrowserPath carries the browser launch/discovery logic' );
ok( !Browser::Runner->can('_version_satisfies_spec'), 'Runner.pm no longer carries the moved Node dependency version logic itself' );
ok( !Browser::Runner->can('_launch_options'), 'Runner.pm no longer carries the moved browser launch/discovery logic itself' );

for my $file (qw(lib/Browser/Runner.pm lib/Browser/Runner/NodeRuntime.pm lib/Browser/Runner/BrowserPath.pm)) {
    open my $fh, '<', $file or die "Unable to read $file: $!";
    my $lines = 0;
    $lines++ while <$fh>;
    close $fh;
    ok( $lines <= 500, "$file is 500 lines or fewer (has $lines)" );
}

done_testing();
