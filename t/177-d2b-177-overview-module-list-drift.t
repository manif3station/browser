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

my @runner_modules = glob 'lib/Browser/Runner/*.pm';
ok( scalar @runner_modules >= 1, 'found at least one lib/Browser/Runner/*.pm module to check' );

open my $fh, '<', 'docs/overview.md' or die "Unable to read docs/overview.md: $!";
my $overview = do { local $/; <$fh> };
close $fh or die "Unable to close docs/overview.md: $!";

for my $path (@runner_modules) {
    my $basename = basename($path);
    ok( index( $overview, $basename ) >= 0, "docs/overview.md names $basename" );
}

done_testing();
