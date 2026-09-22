use strict;
use warnings;

use Cwd ();
use File::Spec;
use Test::More;

# D2B-136: D2B-131's own doc additions said browser.png's script_result
# "appears in the result... exactly as it does for browser.get/browser.post",
# implying CLI-level parity. That's only true at the Perl API level -
# dashboard browser.png's own CLI stdout only ever prints the saved file
# path (Browser::CLI::main), never the full JSON result GET/POST print.
# This test asserts the doc wording explicitly scopes the claim so a
# reader doesn't expect script_result on browser.png's own CLI stdout.

my $skill_root = Cwd::abs_path('.');

for my $doc_file ( 'README.md', File::Spec->catfile( 'docs', 'usage.md' ) ) {
    my $path = File::Spec->catfile( $skill_root, $doc_file );
    open my $fh, '<', $path or die "Unable to read $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh;

    if ( $content =~ /(browser\.png[^\n]*(?:\n[^\n]*){0,5}?script_result[^\n]*(?:\n[^\n]*){0,3})/ ) {
        my $excerpt = $1;
        like(
            $excerpt,
            qr/Perl API/,
            "${doc_file}'s script_result mention scopes the browser.get/browser.post parity claim to the Perl API (D2B-136)"
        );
        like(
            $excerpt,
            qr/CLI/,
            "${doc_file}'s script_result mention explicitly names the CLI as where that parity does not hold for browser.png (D2B-136)"
        );
    }
    else {
        fail("$doc_file has no script_result mention to check (D2B-136)");
    }
}

done_testing();
