use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-169: closes the untested Getopt::Long ambiguous-abbreviation error
# path in lib/Browser/Runner.pm's sibling module Browser::CLI. --engine
# and --engines both start with "engine", so an abbreviation matching
# both (e.g. --e) triggers Getopt::Long's own ambiguous-option
# detection, which execute_search already surfaces correctly via its
# existing "Invalid options: ..." die - giving exit code 2, matching
# this skill's shared exit-2 error convention. No behavioral change -
# the path already does the right thing; this test proves and
# documents it.

{
    package FakeSearchRunner;
    sub new { bless { calls => [] }, shift }
    sub request {
        my ( $self, %args ) = @_;
        push @{ $self->{calls} }, {%args};
        return { is_captcha => 0, body => q{} };
    }
}

eval {
    Browser::CLI::execute_search(
        argv   => [ '--e', 'google', 'query' ],
        runner => FakeSearchRunner->new(),
    );
};
like(
    $@,
    qr/Invalid options:.*ambiguous/,
    'execute_search refuses an abbreviated flag ambiguous between --engine and --engines'
);
like(
    $@,
    qr/engine/,
    'the ambiguous-option message names the colliding flags'
);

my $exit_code = Browser::CLI::main_search(
    argv      => [ '--e', 'google', 'query' ],
    output_fh => do { open my $fh, '>', \my $out; $fh },
    error_fh  => do { open my $fh, '>', \my $err; $fh },
    runner    => FakeSearchRunner->new(),
);
is( $exit_code, 2, 'the ambiguous --e abbreviation exits with the shared exit code 2, matching every other browser.search validation failure' );

done_testing();
