use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-035: _ensure_node_runtime unconditionally prepends $node_modules to
# NODE_PATH on every call, with no check for whether it's already present.
# In a long-lived process that calls it more than once, NODE_PATH grows
# with the same duplicate path on every call, unboundedly.

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
local $ENV{NODE_PATH};

Browser::Runner::NodeRuntime::_ensure_node_runtime();
Browser::Runner::NodeRuntime::_ensure_node_runtime();

my $node_modules = File::Spec->catdir( $temp_root, 'node_modules' );
my $sep = Browser::Runner::NodeRuntime::_path_list_separator();
my @entries = split /\Q$sep\E/, $ENV{NODE_PATH};
my @matches = grep { $_ eq $node_modules } @entries;

is( scalar(@matches), 1, 'calling _ensure_node_runtime twice in one process leaves the module path in NODE_PATH only once, not twice' );
is( $entries[0], $node_modules, 'the module path still appears first in NODE_PATH' );

{
    # Meaningful-empty-entry and pre-existing-duplicate regression: NODE_PATH
    # entries other than the module path itself must survive unchanged,
    # including empty segments (which Node resolves relative to cwd) and
    # separator-adjacent duplicates already present before this call.
    local $ENV{NODE_PATH} = join $sep, $node_modules, q{}, 'some-other-path', $node_modules;
    Browser::Runner::NodeRuntime::_ensure_node_runtime();
    my @seeded_entries = split /\Q$sep\E/, $ENV{NODE_PATH}, -1;
    is_deeply(
        \@seeded_entries,
        [ $node_modules, q{}, 'some-other-path' ],
        'pre-existing duplicate module-path entries are collapsed to one (kept first), while an unrelated empty segment and other paths are preserved unchanged'
    );
}

done_testing();
