use strict;
use warnings;

use File::Basename qw(basename);
use Test::More;

use lib 'lib';

# D2B-177: docs/overview.md's Delivery section drifted after D2B-155
# extracted VersionCompare.pm from NodeRuntime.pm - SKILLS.md and
# README.md were both updated at the time, but docs/overview.md was
# missed. This test guards against this class of drift recurring for
# any current or future file in lib/Browser/Runner/.
#
# D2B-217: the original glob only covered lib/Browser/Runner/*.pm, so
# it would not have caught the identical drift class recurring in
# lib/Browser/CLI/ after D2B-216 extracted TableOutput.pm there -
# broadened to cover both directories.
#
# D2B-232: two separate bugs found together while broadening this
# further. First, neither glob above descends into a subdirectory, so
# lib/Browser/Runner/NodeRuntime/Install.pm (D2B-198's extraction
# target) was invisible to this guard. Second, and more serious: `,`
# has *lower* precedence than `=`, so `my @x = (A), (B);` only ever
# assigns A to @x - B is evaluated in void context and silently
# discarded. That means D2B-217's own "broadened to cover both
# directories" never actually worked: @checked_modules only ever held
# lib/Browser/Runner/*.pm's matches, and lib/Browser/CLI/*.pm's files
# (TableOutput.pm) were never checked against docs/overview.md at all.
# Fixed by putting every glob inside one list, and adding a second
# level of glob for a subdirectory under each directory.

my @checked_modules = (
    glob('lib/Browser/Runner/*.pm'), glob('lib/Browser/Runner/*/*.pm'),
    glob('lib/Browser/CLI/*.pm'),    glob('lib/Browser/CLI/*/*.pm'),
);
ok( scalar @checked_modules >= 1, 'found at least one module to check' );

# D2B-232: guards both bugs above - Install.pm (subdirectory) and
# TableOutput.pm (the CLI/*.pm glob that D2B-217 silently dropped).
ok( ( grep { basename($_) eq 'Install.pm' } @checked_modules ), 'checked_modules includes a subdirectory module (Install.pm)' );
ok( ( grep { basename($_) eq 'TableOutput.pm' } @checked_modules ), 'checked_modules includes the CLI/*.pm module (TableOutput.pm)' );

open my $fh, '<', 'docs/overview.md' or die "Unable to read docs/overview.md: $!";
my $overview = do { local $/; <$fh> };
close $fh or die "Unable to close docs/overview.md: $!";

for my $path (@checked_modules) {
    my $basename = basename($path);
    ok( index( $overview, $basename ) >= 0, "docs/overview.md names $basename" );
}

done_testing();
