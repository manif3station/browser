use strict;
use warnings;

use Test::More;
use File::Spec;
use File::Basename qw(dirname);

# D2B-166: D2B-158's --script must-not-be-empty refusal (shipped this
# session) was never documented in SKILLS.md, README.md, or
# docs/usage.md. TDD red: not yet fixed.

my $repo_root = File::Spec->catdir( dirname(__FILE__), '..' );

for my $file (qw(SKILLS.md README.md docs/usage.md)) {
    my $path = File::Spec->catfile( $repo_root, $file );
    open my $fh, '<', $path or die "Unable to open $path: $!";
    my $text = do { local $/; <$fh> };
    close $fh;

    like( $text, qr/--script must not be empty/, "${file}'s --script documentation mentions the empty-value refusal (D2B-158)" );
}

done_testing();
