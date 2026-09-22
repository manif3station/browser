use strict;
use warnings;

use Test::More;
use File::Spec;
use File::Basename qw(dirname);

# D2B-159: README.md and docs/usage.md's URL-missing-check claim still
# described the pre-D2B-156 behavior ("only refused when truly absent or
# an empty string"), never updated when D2B-156 (this session) widened
# the check to also refuse a whitespace-only URL. TDD red: not yet fixed.

my $repo_root = File::Spec->catdir( dirname(__FILE__), '..' );

for my $file (qw(README.md docs/usage.md)) {
    my $path = File::Spec->catfile( $repo_root, $file );
    open my $fh, '<', $path or die "Unable to open $path: $!";
    my $text = do { local $/; <$fh> };
    close $fh;

    unlike( $text, qr/only refused as missing when it is truly absent or an empty string/, "$file no longer states the stale pre-D2B-156 URL-missing rule" );
    my ($zero_clarification_line) = $text =~ /^(.*single character `0` is accepted.*)$/m;
    ok( defined $zero_clarification_line, "$file still keeps the 0-is-accepted clarification" );
    like( $zero_clarification_line // q{}, qr/whitespace-only/, "${file}'s URL-missing rule (the same line as the 0-clarification) mentions whitespace-only (D2B-156)" );
}

done_testing();
