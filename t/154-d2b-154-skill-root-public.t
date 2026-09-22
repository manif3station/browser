use strict;
use warnings;

use Test::More;
use File::Spec;
use File::Basename qw(dirname);
use lib File::Spec->catdir( dirname(__FILE__), '..', 'lib' );

use Browser::Runner::NodeRuntime ();
use Browser::CLI ();

# D2B-154: Browser::Runner::NodeRuntime::_skill_root() (underscore-prefixed,
# private by this codebase's own convention) was called from outside its
# defining module - lib/Browser/CLI.pm:167, and from a test file. Identical
# pattern to D2B-147 (_sanitize_error) and D2B-153 (_default_engines).
# This is TDD red: skill_root() (public) does not exist yet.

ok( Browser::Runner::NodeRuntime->can('skill_root'), 'Browser::Runner::NodeRuntime exposes a public skill_root sub' );

my $root = Browser::Runner::NodeRuntime::skill_root();
ok( -f File::Spec->catfile( $root, 'lib', 'Browser', 'CLI.pm' ), 'skill_root() resolves to a directory that actually contains lib/Browser/CLI.pm' );

ok( !Browser::Runner::NodeRuntime->can('_skill_root'), 'the old private _skill_root no longer exists' );

my $repo_root = File::Spec->catdir( dirname(__FILE__), '..' );
for my $file (qw(lib/Browser/CLI.pm lib/Browser/Runner/NodeRuntime.pm t/38-d2b-038-skill-root-cwd-false-positive.t t/04-runner-unit.t)) {
    my $path = File::Spec->catfile( $repo_root, $file );
    open my $fh, '<', $path or die "Unable to open $path: $!";
    my $text = do { local $/; <$fh> };
    close $fh;
    unlike( $text, qr/\b_skill_root\b/, "$file no longer references the private _skill_root name" );
}

done_testing();
