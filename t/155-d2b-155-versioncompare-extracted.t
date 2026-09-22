use strict;
use warnings;

use Test::More;
use File::Spec;
use File::Basename qw(dirname);
use lib File::Spec->catdir( dirname(__FILE__), '..', 'lib' );

use Browser::Runner::VersionCompare ();
use Browser::Runner::NodeRuntime ();

# D2B-155: lib/Browser/Runner/NodeRuntime.pm had grown to 499 lines, 1
# under this project's own 500-line decomposition threshold. The
# self-contained semver-subset comparator (_version_satisfies_spec,
# _version_parts, _compare_version_parts) is extracted into a new
# Browser::Runner::VersionCompare module with public names. This is TDD
# red: the new module does not exist yet.

ok( Browser::Runner::VersionCompare->can('version_satisfies_spec'), 'VersionCompare exposes version_satisfies_spec' );
ok( Browser::Runner::VersionCompare->can('version_parts'), 'VersionCompare exposes version_parts' );
ok( Browser::Runner::VersionCompare->can('compare_version_parts'), 'VersionCompare exposes compare_version_parts' );

ok( Browser::Runner::VersionCompare::version_satisfies_spec( '1.2.5', '^1.0.0' ), 'version_satisfies_spec works via the new module' );
is_deeply( [ Browser::Runner::VersionCompare::version_parts('1.2.5') ], [ 1, 2, 5 ], 'version_parts works via the new module' );
is( Browser::Runner::VersionCompare::compare_version_parts( [ 1, 2, 5 ], [ 1, 2, 4 ] ), 1, 'compare_version_parts works via the new module' );

ok( !Browser::Runner::NodeRuntime->can('_version_satisfies_spec'), 'the old private _version_satisfies_spec no longer exists on NodeRuntime' );
ok( !Browser::Runner::NodeRuntime->can('_version_parts'), 'the old private _version_parts no longer exists on NodeRuntime' );
ok( !Browser::Runner::NodeRuntime->can('_compare_version_parts'), 'the old private _compare_version_parts no longer exists on NodeRuntime' );

my $node_runtime_path = File::Spec->catdir( dirname(__FILE__), '..', 'lib', 'Browser', 'Runner', 'NodeRuntime.pm' );
open my $fh, '<', $node_runtime_path or die "Unable to open $node_runtime_path: $!";
my @lines = <$fh>;
close $fh;
ok( scalar(@lines) < 480, 'lib/Browser/Runner/NodeRuntime.pm dropped comfortably under 500 lines after extraction (currently ' . scalar(@lines) . ')' );

my $repo_root = File::Spec->catdir( dirname(__FILE__), '..' );
for my $file (qw(t/04-runner-unit.t t/16-d2b-013-module-split.t)) {
    my $path = File::Spec->catfile( $repo_root, $file );
    open my $fh2, '<', $path or die "Unable to open $path: $!";
    my $text = do { local $/; <$fh2> };
    close $fh2;
    unlike( $text, qr/\b_version_satisfies_spec\b|\b_version_parts\b|\b_compare_version_parts\b/, "$file no longer references the old private version-comparator names" );
}

done_testing();
