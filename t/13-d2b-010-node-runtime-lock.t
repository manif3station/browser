use strict;
use warnings;

use Fcntl qw(:flock);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-010: _ensure_node_runtime must hold an exclusive lock around the
# whole stale-check-and-install sequence, so a second concurrent caller
# cannot race the clear+copy of the shared node_modules tree.

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

my $lock_path = Browser::Runner::NodeRuntime::_node_runtime_lock_path( home_root => $temp_root );

my $observed_locked = 0;
{
    no warnings 'redefine';
    local *Browser::Runner::NodeRuntime::_node_runtime_is_current = sub {
        # While the runtime lock should be held, try (non-blocking) to take
        # our own exclusive lock on the same file - it must fail.
        open my $probe_fh, '>>', $lock_path or die "Unable to open probe lock file: $!";
        my $got_lock = flock( $probe_fh, LOCK_EX | LOCK_NB );
        $observed_locked = 1 if !$got_lock;
        flock( $probe_fh, LOCK_UN ) if $got_lock;
        close $probe_fh;
        return 1;    # runtime is "current" so no install work runs in this test
    };
    Browser::Runner::NodeRuntime::_ensure_node_runtime();
}

ok( $observed_locked, '_ensure_node_runtime holds an exclusive lock during the stale-check-and-install sequence' );

done_testing();
