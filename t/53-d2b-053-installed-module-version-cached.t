use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-053: _installed_node_module_version duplicated _read_package_json's
# open/decode logic against a different file (an installed module's own
# package.json) instead of reusing the shared, mtime-keyed cache - so it
# re-read and re-decoded the same file from disk on every call.

my $temp_root = tempdir( CLEANUP => 1 );
my $module_dir = File::Spec->catdir( $temp_root, 'node_modules', 'express' );
make_path($module_dir);

my $module_package_json = File::Spec->catfile( $module_dir, 'package.json' );
open my $fh, '>', $module_package_json or die "Unable to write temp module package.json: $!";
print {$fh} qq|{"name":"express","version":"5.1.0"}\n|;
close $fh;

$Browser::Runner::NodeRuntime::PACKAGE_JSON_READ_COUNT = 0;

my $first = Browser::Runner::NodeRuntime::_installed_node_module_version(
    home_root => $temp_root,
    module    => 'express',
);
my $second = Browser::Runner::NodeRuntime::_installed_node_module_version(
    home_root => $temp_root,
    module    => 'express',
);

is( $first,  '5.1.0', 'the installed module version is read correctly' );
is( $second, '5.1.0', 'a second call for the same module returns the same version' );
is( $Browser::Runner::NodeRuntime::PACKAGE_JSON_READ_COUNT, 1,
    'the installed module\'s package.json is read from disk at most once across two calls, via the shared cache' );

# A missing module's package.json must still return undef, not die - the
# shared cache's own die-on-missing-file behavior must not leak through.
is( Browser::Runner::NodeRuntime::_installed_node_module_version(
        home_root => $temp_root,
        module    => 'does-not-exist',
    ),
    undef,
    'a module with no installed package.json still returns undef rather than dying'
);

done_testing();
