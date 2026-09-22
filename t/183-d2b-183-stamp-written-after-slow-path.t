use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use Browser::Runner::NodeRuntime;

# D2B-183: _write_node_runtime_stamp was only ever called from inside
# _ensure_node_runtime's own "just ran _install_node_runtime" branch, so
# the fast stamp-comparison path never engaged for the common case where
# Developer Dashboard's own top-level npm install populated node_modules
# directly - _node_runtime_is_current always fell through to the slow
# per-dependency _installed_modules_satisfy_package_json check, on every
# single call, forever. This pins that a successful slow-path check now
# writes the stamp too, not only a successful install.

my $temp_root = tempdir( CLEANUP => 1 );

# Simulate a DD-managed install: node_modules populated directly, no
# skill-internal _install_node_runtime ever run, so no stamp exists yet.
for my $module ( [ express => '5.1.2' ] ) {
    my ( $name, $version ) = @{$module};
    my $module_dir = File::Spec->catdir( $temp_root, 'node_modules', $name );
    make_path($module_dir);
    open my $installed_fh, '>', File::Spec->catfile( $module_dir, 'package.json' )
      or die "Unable to write installed package.json for $name: $!";
    print {$installed_fh} qq|{"name":"$name","version":"$version"}\n|;
    close $installed_fh or die "Unable to close installed package.json for $name: $!";
}

my $package_json = File::Spec->catfile( $temp_root, 'package.json' );
open my $package_fh, '>', $package_json or die "Unable to write temp package.json: $!";
print {$package_fh} qq|{"name":"browser-skill-test","version":"0.01.0","dependencies":{"express":"^5.1.0"}}\n|;
close $package_fh;

my $stamp_path = Browser::Runner::NodeRuntime::_node_runtime_stamp_path( home_root => $temp_root );
ok( !-f $stamp_path, 'no stamp exists before the first currency check (DD-managed install, never through this skill\'s own install)' );

my $is_current_1 = Browser::Runner::NodeRuntime::_node_runtime_is_current(
    home_root    => $temp_root,
    package_json => $package_json,
);
ok( $is_current_1, 'first check confirms currency via the slow per-dependency path' );
ok( -f $stamp_path, 'the stamp is now written after the slow-path check succeeded, not only after an install' );

my $fingerprint = Browser::Runner::NodeRuntime::_package_json_fingerprint($package_json);
is( Browser::Runner::NodeRuntime::_read_node_runtime_stamp( home_root => $temp_root ), $fingerprint,
    'the written stamp matches the current package.json fingerprint' );

# Remove the per-module installed package.json so the slow path would now
# fail if it ran again - proving the second call trusts the fast stamp
# path instead of repeating the slow check.
unlink File::Spec->catfile( $temp_root, 'node_modules', 'express', 'package.json' );

my $is_current_2 = Browser::Runner::NodeRuntime::_node_runtime_is_current(
    home_root    => $temp_root,
    package_json => $package_json,
);
ok( $is_current_2, 'second check still reports current via the fast stamp path, even though the slow path\'s own evidence was removed' );

done_testing();
