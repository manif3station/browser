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
# subs got called. It is shared across every file _read_package_json is
# ever called on - the skill's own package.json AND each installed
# module's own package.json (read while checking installed versions) -
# so D2B-120's fixtures (added so this test's runtime genuinely reports
# current and never falls through to a real npx install) legitimately
# add one more distinct file to the count: the skill's package.json (1)
# plus the one dependency currently listed, express (1) = 2. What D2B-024
# actually guards against - reading the SAME file's content twice in one
# call - is unaffected: neither file is read more than once here.

my $temp_root = tempdir( CLEANUP => 1 );

# D2B-120: each module directory also gets its own installed package.json
# with a version satisfying the spec below, so _installed_modules_satisfy_
# package_json reports the runtime as already current and _ensure_node_
# runtime never falls through to a real npx/npm install - the ~9s of real
# subprocess overhead this test used to add with no bearing on what it
# actually verifies (package.json single-read/no-stale-cache behavior).
for my $module (
    [ express    => '5.1.2' ],
    [ jquery     => '3.7.1' ],
    [ playwright => '1.55.1' ],
    [ uuid       => '11.1.0' ],
  )
{
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

$Browser::Runner::NodeRuntime::PACKAGE_JSON_READ_COUNT = 0;

# No stored stamp exists yet, so this falls through to the real
# dependency-map comparison - exercising both raw-read call paths
# (fingerprint, then dependency-map) in one call.
Browser::Runner::NodeRuntime::_node_runtime_is_current(
    home_root    => $temp_root,
    package_json => $package_json,
);

is( $Browser::Runner::NodeRuntime::PACKAGE_JSON_READ_COUNT, 2,
    q{package.json (the skill's own, plus its one currently-listed dependency, express) is each read from disk exactly once per _node_runtime_is_current call - no file is read twice (D2B-024/D2B-120)} );

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
