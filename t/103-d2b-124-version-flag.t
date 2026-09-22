use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-124: none of the four browser.* commands declared a --version
# flag - there was no CLI-level way to check the installed skill's
# version without reading .env by hand. Mirrors --help's own
# top-priority short-circuit pattern (D2B-096).

sub _write_env {
    my ($dir, $version) = @_;
    my $env_path = File::Spec->catfile( $dir, '.env' );
    open my $fh, '>', $env_path or die "Unable to write temp .env: $!";
    print {$fh} "VERSION=$version\n";
    close $fh or die "Unable to close temp .env: $!";
    return $env_path;
}

for my $method (qw(GET POST PNG)) {
    my $temp_root = tempdir( CLEANUP => 1 );
    _write_env( $temp_root, '9.99' );
    local $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT} = $temp_root;

    my $output = q{};
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";

    my $rc = Browser::CLI::main(
        method    => $method,
        argv      => ['--version'],
        output_fh => $output_fh,
    );
    close $output_fh;

    is( $rc, 0, "browser.$method --version exits 0" );
    is( $output, "9.99\n", "browser.$method --version prints exactly the .env VERSION value" );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    _write_env( $temp_root, '9.99' );
    local $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT} = $temp_root;

    my $output = q{};
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";

    my $rc = Browser::CLI::main_search(
        argv      => ['--version'],
        output_fh => $output_fh,
    );
    close $output_fh;

    is( $rc, 0, 'browser.search --version exits 0' );
    is( $output, "9.99\n", 'browser.search --version prints exactly the .env VERSION value' );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    _write_env( $temp_root, '9.99' );
    local $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT} = $temp_root;

    my $output = q{};
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";

    my $rc = Browser::CLI::main(
        method    => 'GET',
        argv      => [ '--version', '--data', 'x' ],
        output_fh => $output_fh,
    );
    close $output_fh;

    is( $rc, 0, '--version combined with other flags still short-circuits, not dying or running a request' );
    is( $output, "9.99\n", '--version output is unaffected by sibling flags' );
}

# --help must still win over --version, exactly like it wins over every
# other flag/validation (D2B-096) - this ticket must not change --help's
# own priority.
{
    my $temp_root = tempdir( CLEANUP => 1 );
    _write_env( $temp_root, '9.99' );
    local $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT} = $temp_root;

    my $output = q{};
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";

    my $rc = Browser::CLI::main(
        method    => 'GET',
        argv      => [ '--help', '--version' ],
        output_fh => $output_fh,
    );
    close $output_fh;

    is( $rc, 0, '--help combined with --version still exits 0' );
    like( $output, qr/\AUsage: browser\.get/, '--help wins over --version when both are given' );
    unlike( $output, qr/9\.99/, '--help output does not also print the version string' );
}

# Missing/unreadable .env must fail clearly, not silently print an empty
# or wrong version.
{
    my $temp_root = tempdir( CLEANUP => 1 );    # deliberately no .env written
    local $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT} = $temp_root;

    my $error_output = q{};
    open my $error_fh, '>', \$error_output or die "Unable to open error scalar: $!";

    my $rc = Browser::CLI::main(
        method   => 'GET',
        argv     => ['--version'],
        error_fh => $error_fh,
    );
    close $error_fh;

    is( $rc, 2, '--version with a missing .env fails clearly rather than printing an empty/wrong version' );
    like( $error_output, qr/\.env/, 'the missing-.env error names the file it could not read' );
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

    is( $rc, 2, 'without --version, a genuinely missing URL still errors normally (regression guard)' );
    like( $error_output, qr/Missing URL/, 'the normal missing-URL error message is unaffected by the --version addition' );
}

# D2B-124 (Codex review round 1): a .env with a genuinely empty VERSION
# value (e.g. "VERSION=" with nothing after the '=') must fail clearly,
# not silently succeed with a blank version string.
{
    my $temp_root = tempdir( CLEANUP => 1 );
    _write_env( $temp_root, q{} );
    local $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT} = $temp_root;

    my $error_output = q{};
    open my $error_fh, '>', \$error_output or die "Unable to open error scalar: $!";

    my $rc = Browser::CLI::main(
        method   => 'GET',
        argv     => ['--version'],
        error_fh => $error_fh,
    );
    close $error_fh;

    is( $rc, 2, '--version with an empty VERSION value in .env fails clearly rather than printing a blank version' );
    like( $error_output, qr/empty/i, 'the empty-VERSION error explains the problem' );
}

done_testing();
