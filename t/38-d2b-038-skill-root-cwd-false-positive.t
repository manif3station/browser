use strict;
use warnings;

use Cwd qw(getcwd);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-038: _skill_root's cwd heuristic trusts any current directory that
# merely has both a 'cli' and 'lib' subdirectory, with no check that it's
# actually this skill's root. A coincidental match (e.g. an unrelated
# project directory that happens to have both dirs for its own reasons)
# false-positives to that unrelated directory instead of falling through
# to the reliable __FILE__-relative resolution.

my $decoy_root = tempdir( CLEANUP => 1 );
make_path( File::Spec->catdir( $decoy_root, 'cli' ) );
make_path( File::Spec->catdir( $decoy_root, 'lib' ) );

my $cwd = getcwd();
chdir $decoy_root or die "Unable to chdir to decoy root: $!";

local $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT};
my $resolved = Browser::Runner::NodeRuntime::_skill_root();

chdir $cwd or die "Unable to restore cwd after decoy-root test: $!";

isnt( $resolved, $decoy_root, '_skill_root does not false-positive to a decoy directory that merely has empty cli/ and lib/ subdirs' );
ok( -f File::Spec->catfile( $resolved, 'lib', 'Browser', 'CLI.pm' ), '_skill_root instead resolves to a directory that actually contains lib/Browser/CLI.pm' );

done_testing();
