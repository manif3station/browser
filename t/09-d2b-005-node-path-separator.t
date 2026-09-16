use strict;
use warnings;

use Config;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-005: _ensure_node_runtime must join NODE_PATH with the platform's own
# path-list separator (_path_list_separator: $Config{path_sep} - ':' on
# Unix, ';' on Windows), not a hardcoded ':'.

is( Browser::Runner::NodeRuntime::_path_list_separator(), $Config::Config{path_sep}, '_path_list_separator returns the platform Config path_sep' );

{
    my $temp_root = tempdir( CLEANUP => 1 );
    for my $module ( Browser::Runner::NodeRuntime::_required_node_modules() ) {
        make_path( File::Spec->catdir( $temp_root, 'node_modules', $module ) );
        open my $fh, '>', File::Spec->catfile( $temp_root, 'node_modules', $module, 'package.json' )
          or die "Unable to write temp installed package.json for $module: $!";
        print {$fh} qq|{"name":"$module","version":"1.0.0"}\n|;
        close $fh;
    }
    open my $package_fh, '>', File::Spec->catfile( $temp_root, 'package.json' )
      or die "Unable to write temp package.json: $!";
    print {$package_fh} qq|{"name":"browser-skill-test","version":"0.01.0","dependencies":{}}\n|;
    close $package_fh;

    local $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT} = $temp_root;
    local $ENV{HOME} = $temp_root;
    local $ENV{NODE_PATH} = 'existing-entry';

    no warnings 'redefine';
    local *Browser::Runner::NodeRuntime::_path_list_separator = sub { return ';' };

    Browser::Runner::NodeRuntime::_ensure_node_runtime();
    like(
        $ENV{NODE_PATH}, qr/node_modules;existing-entry\z/,
        'ensure_node_runtime joins NODE_PATH with the platform separator (";" here) rather than a hardcoded ":"'
    );
}

done_testing();
