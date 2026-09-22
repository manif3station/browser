use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-145: --version is a real, equally-prioritized flag on all four
# commands (D2B-124), sharing --help's identical pre-parse short-circuit
# behavior, but neither _usage_get_post_png nor _usage_search's usage
# heredoc text ever mentioned it - a user relying on --help alone (rather
# than external docs) had no way to discover --version exists.

for my $method (qw(GET POST PNG)) {
    my $output = q{};
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";

    my $rc = Browser::CLI::main(
        method    => $method,
        argv      => ['--help'],
        output_fh => $output_fh,
    );
    close $output_fh;

    is( $rc, 0, "browser.$method --help exits 0" );
    like( $output, qr/--version/, "browser.$method --help's usage text mentions --version" );
}

{
    my $output = q{};
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";

    my $rc = Browser::CLI::main_search(
        argv      => ['--help'],
        output_fh => $output_fh,
    );
    close $output_fh;

    is( $rc, 0, 'browser.search --help exits 0' );
    like( $output, qr/--version/, "browser.search --help's usage text mentions --version" );
}

# Regression guard: --help itself is still documented, unaffected by
# adding --version alongside it.
for my $method (qw(GET POST PNG)) {
    my $output = q{};
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";

    Browser::CLI::main( method => $method, argv => ['--help'], output_fh => $output_fh );
    close $output_fh;

    like( $output, qr/--help/, "D2B-145 regression guard: browser.$method --help's usage text still mentions --help itself" );
}

{
    my $output = q{};
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";

    Browser::CLI::main_search( argv => ['--help'], output_fh => $output_fh );
    close $output_fh;

    like( $output, qr/--help/, 'D2B-145 regression guard: browser.search --help\'s usage text still mentions --help itself' );
}

done_testing();
