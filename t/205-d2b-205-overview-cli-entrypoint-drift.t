use strict;
use warnings;

use File::Basename qw(basename);
use Test::More;

# D2B-205: docs/overview.md's Purpose paragraph and Delivery/cli list
# never mentioned browser.pdf/cli/pdf, even though it shipped in
# D2B-196 and is fully documented in README.md and docs/usage.md. This
# is the third recurrence of the same drift pattern in this file
# (D2B-101 missed cli/skills/SKILLS.md, D2B-177 missed
# VersionCompare.pm). This test generalizes over every current cli/*
# entrypoint so a future addition can't drift the same way unnoticed.

my @cli_entrypoints = glob 'cli/*';
ok( scalar @cli_entrypoints >= 1, 'found at least one cli/* entrypoint to check' );

open my $fh, '<', 'docs/overview.md' or die "Unable to read docs/overview.md: $!";
my $overview = do { local $/; <$fh> };
close $fh or die "Unable to close docs/overview.md: $!";

for my $path (@cli_entrypoints) {
    my $basename = basename($path);
    # Match the literal 'cli/<name>' path, not a bare substring of the
    # basename - "pdf" alone false-passed against Capture.pm's unrelated
    # "run_pdf" mention, hiding the exact drift this ticket exists to fix.
    ok( index( $overview, "cli/$basename" ) >= 0, "docs/overview.md names cli/$basename" );
}

done_testing();
