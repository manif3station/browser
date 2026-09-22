use strict;
use warnings;

use Cwd ();
use File::Spec;
use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-138: browser.post --data '--help' (or '--version') is misinterpreted
# as a help/version request instead of the literal POST body, because
# Browser::CLI's pre-parse detection scans the whole argv for those literal
# tokens anywhere (deliberate, D2B-096/D2B-124), before Getopt::Long ever
# assigns --data its value. This test asserts all three doc files document
# that edge case near their --data documentation, anchored on the shared
# "POST body" phrase.

my $skill_root = Cwd::abs_path('.');

for my $doc_file ( 'README.md', File::Spec->catfile( 'docs', 'usage.md' ), 'SKILLS.md' ) {
    my $path = File::Spec->catfile( $skill_root, $doc_file );
    open my $fh, '<', $path or die "Unable to read $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh;

    if ( $content =~ /(POST body(?:(?!\n\n).){0,1000})/s ) {
        my $excerpt = $1;
        like(
            $excerpt,
            qr/--help/,
            "${doc_file}'s --data documentation mentions the --help literal-value edge case (D2B-138)"
        );
        like(
            $excerpt,
            qr/--version/,
            "${doc_file}'s --data documentation mentions the --version literal-value edge case (D2B-138)"
        );
        like(
            $excerpt,
            qr/misinterpret/i,
            "${doc_file}'s --data documentation states the value is misinterpreted, not sent as the body (D2B-138)"
        );
    }
    else {
        fail("$doc_file has no 'POST body' --data mention to check (D2B-138)");
    }
}

# D2B-138 behavioral confirmation (per code review): the documentation
# claims apply specifically to --data --help/--version as two SEPARATE
# argv elements, not the combined --data=--help/--data=--version form,
# since _argv_requests_help/_argv_requests_version only match a standalone
# argv element equal to the literal string.
ok(
    Browser::CLI::_argv_requests_help( [ 'https://example.com', '--data', '--help' ] ),
    'D2B-138: --data --help as two separate arguments genuinely triggers the help path'
);
ok(
    !Browser::CLI::_argv_requests_help( [ 'https://example.com', '--data=--help' ] ),
    'D2B-138: --data=--help as one combined argument does NOT trigger the help path'
);
ok(
    Browser::CLI::_argv_requests_version( [ 'https://example.com', '--data', '--version' ] ),
    'D2B-138: --data --version as two separate arguments genuinely triggers the version path'
);
ok(
    !Browser::CLI::_argv_requests_version( [ 'https://example.com', '--data=--version' ] ),
    'D2B-138: --data=--version as one combined argument does NOT trigger the version path'
);

done_testing();
