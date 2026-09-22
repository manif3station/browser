use strict;
use warnings;

use Test::More;
use File::Spec;
use File::Basename qw(dirname);

# D2B-149: two remaining instances of the vague "non-zero" wording
# D2B-148 already fixed in cli/get/post/png/search's own EXIT STATUS
# POD - t/01-cli.t's own test description (which asserts exit code 2
# but described itself more vaguely) and one docs/usage.md bullet.

my $repo_root = File::Spec->catdir( dirname(__FILE__), '..' );

{
    my $path = File::Spec->catfile( $repo_root, 't', '01-cli.t' );
    open my $fh, '<', $path or die "Unable to open $path: $!";
    my $text = do { local $/; <$fh> };
    close $fh;

    like( $text, qr/main exits 2 on invalid input/, "t/01-cli.t's test description for the invalid-input case names exit code 2 explicitly" );
    unlike( $text, qr/exits non-zero/, "t/01-cli.t no longer describes any exit code as vaguely \"non-zero\"" );
}

{
    my $path = File::Spec->catfile( $repo_root, 'docs', 'usage.md' );
    open my $fh, '<', $path or die "Unable to open $path: $!";
    my $text = do { local $/; <$fh> };
    close $fh;

    like( $text, qr/the command exits 2/, "docs/usage.md's unreachable-URL bullet names exit code 2 explicitly" );
    unlike( $text, qr/exits non-zero/, "docs/usage.md no longer describes this case's exit code as vaguely \"non-zero\"" );
}

done_testing();
