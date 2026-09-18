use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-096: none of the four browser.* commands declared a --help
# option, so Getopt::Long reported it as "Invalid options: Unknown
# option: help" instead of printing usage and exiting cleanly.

for my $method (qw(GET POST PNG)) {
    my $output = q{};
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";

    my $rc = Browser::CLI::main(
        method    => $method,
        argv      => ['--help'],
        output_fh => $output_fh,
    );
    close $output_fh;

    my $expected_verb = 'browser.' . lc($method);
    is( $rc, 0, "browser.$method --help exits 0 instead of dying with an unknown-option error" );
    like( $output, qr/\AUsage: \Q$expected_verb\E\b/, "browser.$method --help prints usage text naming the command" );
    like( $output, qr/--help/, "browser.$method --help's own usage text mentions --help itself" );
}

{
    my $output = q{};
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";

    my $rc = Browser::CLI::main(
        method    => 'POST',
        argv      => [ '--help', '--data', 'x' ],
        output_fh => $output_fh,
    );
    close $output_fh;

    is( $rc, 0, '--help combined with other flags still short-circuits to usage rather than running a request' );
    like( $output, qr/\AUsage: browser\.post/, 'usage text is printed even when other flags are also given' );
}

{
    my $output = q{};
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";

    my $rc = Browser::CLI::main_search(
        argv      => ['--help'],
        output_fh => $output_fh,
    );
    close $output_fh;

    is( $rc, 0, 'browser.search --help exits 0 instead of dying with an unknown-option error' );
    like( $output, qr/\AUsage: browser\.search/, 'browser.search --help prints usage text naming the command' );
    like( $output, qr/--engine\b/, "browser.search --help's usage text documents --engine" );
}

{
    my $error_output = q{};
    open my $error_fh, '>', \$error_output or die "Unable to open error scalar: $!";

    my $rc = Browser::CLI::main(
        method   => 'GET',
        argv     => [],
        error_fh => $error_fh,
    );
    close $error_fh;

    is( $rc, 2, 'without --help, a genuinely missing URL still errors normally (regression guard)' );
    like( $error_output, qr/Missing URL/, 'the normal missing-URL error message is unaffected by the --help addition' );
}

# Codex review round 1 found a real gap: --help was only declared as a
# Getopt::Long option, so a genuinely unknown/malformed SIBLING flag
# (parsed in the same GetOptionsFromArray call) still died before the
# post-parse help check ever ran - --help did not actually take
# priority over every other validation as claimed. Fixed by pre-scanning
# argv for a literal '--help' token before GetOptionsFromArray is even
# called. These cases must now print usage/exit 0, not die.
{
    my $output = q{};
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";

    my $rc = Browser::CLI::main(
        method    => 'GET',
        argv      => [ '--help', '--not-a-real-flag' ],
        output_fh => $output_fh,
    );
    close $output_fh;

    is( $rc, 0, '--help combined with a genuinely unknown sibling flag still short-circuits to usage, not an unknown-option error' );
    like( $output, qr/\AUsage: browser\.get/, 'usage text is printed even when an unrelated flag would otherwise fail Getopt::Long parsing' );
}

{
    my $output = q{};
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";

    my $rc = Browser::CLI::main(
        method    => 'GET',
        argv      => [ '--help', '--data' ],    # --data=s requires a value; none given
        output_fh => $output_fh,
    );
    close $output_fh;

    is( $rc, 0, '--help combined with a sibling flag missing its required value still short-circuits to usage' );
    like( $output, qr/\AUsage: browser\.get/, 'usage text is printed even when a sibling flag is missing its required argument' );
}

{
    my $output = q{};
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";

    my $rc = Browser::CLI::main_search(
        argv      => [ '--help', '--engine', 'bing', '--engines', 'google' ],    # --engine/--engines conflict
        output_fh => $output_fh,
    );
    close $output_fh;

    is( $rc, 0, 'browser.search --help combined with a conflicting --engine/--engines pair still short-circuits to usage' );
    like( $output, qr/\AUsage: browser\.search/, 'usage text is printed even when other flags would otherwise conflict' );
}

done_testing();
