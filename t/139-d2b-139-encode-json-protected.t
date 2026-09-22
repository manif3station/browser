use strict;
use warnings;

use JSON::PP qw(decode_json);
use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-139: main()/main_search()'s final encode_json($result) call sat
# outside _run_and_report_errors' eval, so an unencodable $result (e.g.
# a circular reference) would die uncaught instead of going through the
# same _sanitize_error()/exit-2 convention every other failure in this
# file uses.

{
    package CircularResultRunner;

    sub new { bless {}, shift }

    sub request {
        my ( $self, %args ) = @_;
        my %result = ( method => $args{method}, requested_url => $args{url}, status => 200 );
        $result{self_reference} = \%result;    # genuinely circular
        return \%result;
    }
}

sub _capture_main {
    my (%args) = @_;
    my $stdout = q{};
    my $stderr = q{};
    open my $stdout_fh, '>', \$stdout or die "Unable to open stdout scalar: $!";
    open my $stderr_fh, '>', \$stderr or die "Unable to open stderr scalar: $!";
    my $exit = Browser::CLI::main( %args, output_fh => $stdout_fh, error_fh => $stderr_fh );
    return ( $exit, $stdout, $stderr );
}

{
    my ( $exit, $stdout, $stderr ) = _capture_main(
        method => 'GET',
        argv   => ['https://example.test'],
        runner => CircularResultRunner->new(),
    );
    is( $exit, 2, 'D2B-139: main() returns exit code 2 (not an uncaught death) when the result cannot be JSON-encoded' );
    isnt( $stderr, q{}, 'D2B-139: main() reports the encoding failure on stderr instead of staying silent' );
    is( $stdout, q{}, 'D2B-139: main() does not print partial/garbage JSON to stdout on this failure' );
}

{
    no warnings 'redefine';
    local *Browser::CLI::execute_search = sub {
        my %result = ( query => 'test' );
        $result{self_reference} = \%result;    # genuinely circular
        return \%result;
    };

    my $stdout = q{};
    my $stderr = q{};
    open my $stdout_fh, '>', \$stdout or die "Unable to open stdout scalar: $!";
    open my $stderr_fh, '>', \$stderr or die "Unable to open stderr scalar: $!";
    my $exit = Browser::CLI::main_search( argv => ['test query'], output_fh => $stdout_fh, error_fh => $stderr_fh );

    is( $exit, 2, 'D2B-139: main_search() returns exit code 2 (not an uncaught death) when the result cannot be JSON-encoded' );
    isnt( $stderr, q{}, 'D2B-139: main_search() reports the encoding failure on stderr instead of staying silent' );
    is( $stdout, q{}, 'D2B-139: main_search() does not print partial/garbage JSON to stdout on this failure' );
}

# D2B-139 regression guard: a normal, encodable result is completely
# unaffected by the fix.
{
    package NormalResultRunner;

    sub new { bless {}, shift }

    sub request {
        my ( $self, %args ) = @_;
        return { method => $args{method}, requested_url => $args{url}, status => 200 };
    }
}

{
    my ( $exit, $stdout, $stderr ) = _capture_main(
        method => 'GET',
        argv   => ['https://example.test'],
        runner => NormalResultRunner->new(),
    );
    is( $exit, 0, 'D2B-139 regression guard: main() still exits 0 for a normal, encodable result' );
    is( $stderr, q{}, 'D2B-139 regression guard: main() still keeps stderr empty on success' );
    my $payload = decode_json($stdout);
    is( $payload->{method}, 'GET', 'D2B-139 regression guard: main() still prints the normal JSON result' );
}

done_testing();
