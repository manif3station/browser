use strict;
use warnings;

use Cwd ();
use File::Spec;
use Test::More;

# D2B-137: browser.post's --data never sends a Content-Type header, and
# no --header flag exists anywhere to set one, yet no doc file mentioned
# this - every example ('--data name=dashboard') reads like form data,
# which could mislead a reader into assuming form-encoding happens
# automatically. This test asserts all three doc files carry the actual
# negation claims (not just the bare keywords), anchored on the shared
# "POST body" phrase each file's --data documentation uses.

my $skill_root = Cwd::abs_path('.');

for my $doc_file ( 'README.md', File::Spec->catfile( 'docs', 'usage.md' ), 'SKILLS.md' ) {
    my $path = File::Spec->catfile( $skill_root, $doc_file );
    open my $fh, '<', $path or die "Unable to read $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh;

    if ( $content =~ /(POST body(?:(?!\n\n).){0,400})/s ) {
        my $excerpt = $1;
        like(
            $excerpt,
            qr/never explicitly sets a\s*`?Content-Type`?\s*header/i,
            "${doc_file}'s --data documentation states --data never explicitly sets a Content-Type header (D2B-137)"
        );
        like(
            $excerpt,
            qr/no\s*`?--header`?\s*flag/i,
            "${doc_file}'s --data documentation states there is no --header flag to set one (D2B-137)"
        );
    }
    else {
        fail("$doc_file has no 'POST body' --data mention to check (D2B-137)");
    }
}

done_testing();
