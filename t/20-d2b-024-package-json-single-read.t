use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-024: package.json must be read from disk and JSON-decoded at most
# once per _node_runtime_is_current call. Before this fix,
# _package_json_fingerprint and (via _installed_modules_satisfy_package_json)
# _package_json_dependency_map each opened and decoded the file
# independently - two real disk reads of the exact same content in one
# call, whenever no stamp match short-circuits the check.
#
# $Browser::Runner::NodeRuntime::PACKAGE_JSON_READ_COUNT is incremented
# only on a genuine cache-miss disk read, so it measures the thing the
# ticket actually cares about (real reads), not how many named helper
# subs got called.

my $temp_root = tempdir( CLEANUP => 1 );

for my $module ( Browser::Runner::NodeRuntime::_required_node_modules() ) {
    make_path( File::Spec->catdir( $temp_root, 'node_modules', $module ) );
}

my $package_json = File::Spec->catfile( $temp_root, 'package.json' );
open my $package_fh, '>', $package_json or die "Unable to write temp package.json: $!";
print {$package_fh} qq|{"name":"browser-skill-test","version":"0.01.0","dependencies":{"express":"^5.1.0"}}\n|;
close $package_fh;

$Browser::Runner::NodeRuntime::PACKAGE_JSON_READ_COUNT = 0;

# No stored stamp exists yet, so this falls through to the real
# dependency-map comparison - exercising both raw-read call paths
# (fingerprint, then dependency-map) in one call.
Browser::Runner::NodeRuntime::_node_runtime_is_current(
    home_root    => $temp_root,
    package_json => $package_json,
);

is( $Browser::Runner::NodeRuntime::PACKAGE_JSON_READ_COUNT, 1,
    'package.json is read from disk at most once per _node_runtime_is_current call' );

# The cache must never survive across two separate _ensure_node_runtime
# calls, even if package.json changes without its mtime changing too
# (e.g. a filesystem with coarse mtime resolution) - otherwise a
# long-lived process could read a stale dependency spec on the second
# call. Force identical mtimes across a real content change to prove it.
local $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT} = $temp_root;
local $ENV{HOME} = $temp_root;

Browser::Runner::NodeRuntime::_ensure_node_runtime();
my $first_fingerprint = Browser::Runner::NodeRuntime::_package_json_fingerprint($package_json);

my $mtime = ( stat $package_json )[9];
open my $rewrite_fh, '>', $package_json or die "Unable to rewrite temp package.json: $!";
print {$rewrite_fh} qq|{"name":"browser-skill-test","version":"0.02.0","dependencies":{"express":"^5.1.0","jquery":"^3.7.1"}}\n|;
close $rewrite_fh;
utime $mtime, $mtime, $package_json or die "Unable to force mtime on temp package.json: $!";

Browser::Runner::NodeRuntime::_ensure_node_runtime();
my $second_fingerprint = Browser::Runner::NodeRuntime::_package_json_fingerprint($package_json);

isnt( $second_fingerprint, $first_fingerprint,
    'a second _ensure_node_runtime call sees content changed since the first call, even under an identical mtime' );

done_testing();
