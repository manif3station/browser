use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use Browser::Runner ();
use Browser::Runner::NodeRuntime ();

# D2B-199: Windows GitHub Actions runners (and Windows generally) never
# set $ENV{HOME} - they set $ENV{USERPROFILE} instead. Both
# NodeRuntime.pm's _ensure_node_runtime and Runner.pm's _jquery_path did
# a bare '$ENV{HOME} || die', so every browser.* invocation died
# immediately on Windows regardless of browser, confirmed live against
# a real failing GitHub Actions job (run 35764460588, windows-latest +
# firefox: "HOME is required for browser skill Node dependencies").
# _home_root() must fall back to USERPROFILE when HOME is unset.

{
    my $temp_root = tempdir( CLEANUP => 1 );
    local $ENV{HOME}        = q{};
    local $ENV{USERPROFILE} = $temp_root;
    is( Browser::Runner::NodeRuntime::_home_root(), $temp_root,
        '_home_root falls back to USERPROFILE when HOME is unset' );
}

{
    local $ENV{HOME}        = q{};
    local $ENV{USERPROFILE} = q{};
    eval { Browser::Runner::NodeRuntime::_home_root() };
    like( $@, qr/HOME \(or USERPROFILE on Windows\) is required/,
        '_home_root dies naming both env vars when neither is set' );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    local $ENV{HOME}        = $temp_root;
    local $ENV{USERPROFILE} = q{};
    is( Browser::Runner::NodeRuntime::_home_root(), $temp_root,
        '_home_root prefers HOME over USERPROFILE when both are set' );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    local $ENV{HOME}        = q{};
    local $ENV{USERPROFILE} = $temp_root;
    eval { Browser::Runner::_jquery_path() };
    like( $@, qr/Missing jQuery runtime/,
        'Runner.pm::_jquery_path resolves via USERPROFILE when HOME is unset (fails later, on the missing jquery file, not on HOME)' );
}

done_testing();
