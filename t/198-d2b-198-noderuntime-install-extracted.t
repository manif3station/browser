use strict;
use warnings;

use File::Basename qw(dirname);
use File::Spec;
use Test::More;

use lib 'lib';
use Browser::Runner::NodeRuntime;

# D2B-198: NodeRuntime.pm was approaching the 500-line guideline (491
# lines after D2B-199's Windows fix) - this is the red/TDD driver for
# extracting its self-contained npm-install workspace cluster
# (_install_node_runtime, _clear_installed_node_modules,
# _recursive_copy_dir) into a new Browser::Runner::NodeRuntime::Install
# module, mirroring the VersionCompare.pm precedent (D2B-155). Fails
# against the pre-extraction code (the new module does not exist yet).

my $ok = eval { require Browser::Runner::NodeRuntime::Install; 1 };
ok( $ok, 'Browser::Runner::NodeRuntime::Install module exists and loads' ) or diag("load error: $@");

SKIP: {
    skip 'module did not load', 3 if !$ok;

    ok( Browser::Runner::NodeRuntime::Install->can('install_node_runtime'), 'Install module exposes install_node_runtime' );

    ok( !Browser::Runner::NodeRuntime->can('_install_node_runtime'), 'the old private _install_node_runtime no longer exists on NodeRuntime' );
    ok( !Browser::Runner::NodeRuntime->can('_recursive_copy_dir'), 'the old private _recursive_copy_dir no longer exists on NodeRuntime' );
}

my $node_runtime_path = File::Spec->catfile( dirname(__FILE__), '..', 'lib', 'Browser', 'Runner', 'NodeRuntime.pm' );
open my $fh, '<', $node_runtime_path or die "Unable to open $node_runtime_path: $!";
my @lines = <$fh>;
close $fh;
ok( scalar(@lines) < 400, 'lib/Browser/Runner/NodeRuntime.pm drops well under 400 lines after the Install.pm extraction (currently ' . scalar(@lines) . ')' );

done_testing();
