use strict;
use warnings;

use Test::More;

# D2B-013: Runner.pm must be split so each resulting file is 500 lines or
# fewer. Confirms both extracted modules exist and are independently
# loadable.

use_ok('Browser::Runner::NodeRuntime');
use_ok('Browser::Runner::BrowserPath');
use_ok('Browser::Runner::VersionCompare');
use_ok('Browser::Runner');

ok( Browser::Runner::VersionCompare->can('version_satisfies_spec'), 'VersionCompare carries the Node dependency version logic (D2B-155: extracted from NodeRuntime)' );
ok( Browser::Runner::BrowserPath->can('_launch_options'), 'BrowserPath carries the browser launch/discovery logic' );
ok( !Browser::Runner->can('version_satisfies_spec'), 'Runner.pm does not carry the Node dependency version logic itself (D2B-155: lives in VersionCompare)' );
ok( !Browser::Runner->can('_launch_options'), 'Runner.pm no longer carries the moved browser launch/discovery logic itself' );

for my $file (qw(lib/Browser/Runner.pm lib/Browser/Runner/NodeRuntime.pm lib/Browser/Runner/BrowserPath.pm lib/Browser/Runner/VersionCompare.pm)) {
    open my $fh, '<', $file or die "Unable to read $file: $!";
    my $lines = 0;
    $lines++ while <$fh>;
    close $fh;
    ok( $lines <= 500, "$file is 500 lines or fewer (has $lines)" );
}

done_testing();
