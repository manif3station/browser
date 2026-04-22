use strict;
use warnings;

use JSON::PP qw(decode_json);
use Test::More;

use lib 'lib';
use Browser::CLI;

{
    package TestRunner;

    sub new { bless {}, shift }

    sub request {
        my ( $self, %args ) = @_;
        return {
            method        => $args{method},
            requested_url => $args{url},
            final_url     => $args{url},
            status        => 200,
            script_result => $args{script},
            jquery        => $args{jquery},
            data          => $args{data},
            browser       => $args{browser},
            headless      => $args{headless},
            interactive   => $args{interactive},
            timeout_ms    => $args{timeout_ms},
        };
    }
}

my $result = Browser::CLI::execute(
    method => 'GET',
    argv   => [ 'https://example.test', '--script', 'return document.title', '--browser', 'chrome', '--no-headless', '--timeout-ms', '5000' ],
    runner => TestRunner->new(),
);

is( $result->{method}, 'GET', 'execute forwards the request method' );
is( $result->{requested_url}, 'https://example.test', 'execute forwards the URL' );
is( $result->{script_result}, 'return document.title', 'execute forwards the script' );
is( $result->{browser}, 'chrome', 'execute forwards the browser type' );
is( $result->{headless}, 0, 'execute forwards headless option' );
is( $result->{timeout_ms}, 5000, 'execute forwards timeout option' );

my $interactive_result = Browser::CLI::execute(
    method => 'GET',
    argv   => [ 'https://example.test', '--ask' ],
    runner => TestRunner->new(),
);
is( $interactive_result->{interactive}, 1, 'execute enables interactive mode for --ask' );
is( $interactive_result->{headless}, 0, 'execute forces headed mode for --ask' );

$interactive_result = Browser::CLI::execute(
    method => 'GET',
    argv   => [ 'https://example.test', '--askme' ],
    runner => TestRunner->new(),
);
is( $interactive_result->{interactive}, 1, 'execute enables interactive mode for --askme' );
is( $interactive_result->{headless}, 0, 'execute forces headed mode for --askme' );

$interactive_result = Browser::CLI::execute(
    method => 'GET',
    argv   => [ 'https://example.test', '--jquery' ],
    runner => TestRunner->new(),
);
is( $interactive_result->{jquery}, 1, 'execute forwards the jquery flag' );

my $stdout = q{};
open my $stdout_fh, '>', \$stdout or die "Unable to open stdout scalar: $!";
my $stderr = q{};
open my $stderr_fh, '>', \$stderr or die "Unable to open stderr scalar: $!";

my $exit = Browser::CLI::main(
    method    => 'POST',
    argv      => [ 'https://example.test/form', '--data', 'name=dashboard' ],
    runner    => TestRunner->new(),
    output_fh => $stdout_fh,
    error_fh  => $stderr_fh,
);

is( $exit, 0, 'main exits zero on success' );
is( $stderr, q{}, 'main keeps stderr empty on success' );
my $payload = decode_json($stdout);
is( $payload->{method}, 'POST', 'main prints JSON output' );
is( $payload->{data}, 'name=dashboard', 'main prints the runner result' );

$stdout = q{};
$stderr = q{};
my $stdin = "\n";
open my $stdin_fh, '<', \$stdin or die "Unable to open stdin scalar: $!";
open $stdout_fh, '>', \$stdout or die "Unable to reopen stdout scalar: $!";
open $stderr_fh, '>', \$stderr or die "Unable to reopen stderr scalar: $!";
$exit = Browser::CLI::main(
    method    => 'GET',
    argv      => [ 'https://example.test', '--ask' ],
    runner    => TestRunner->new(),
    input_fh  => $stdin_fh,
    output_fh => $stdout_fh,
    error_fh  => $stderr_fh,
);

is( $exit, 0, 'main accepts ask-mode arguments' );
$payload = decode_json($stdout);
is( $payload->{interactive}, 1, 'main prints interactive mode in the runner result' );

$stdout = q{};
$stderr = q{};
open $stdout_fh, '>', \$stdout or die "Unable to reopen stdout scalar for jquery mode: $!";
open $stderr_fh, '>', \$stderr or die "Unable to reopen stderr scalar for jquery mode: $!";
$exit = Browser::CLI::main(
    method    => 'GET',
    argv      => [ 'https://example.test', '--jquery' ],
    runner    => TestRunner->new(),
    output_fh => $stdout_fh,
    error_fh  => $stderr_fh,
);
is( $exit, 0, 'main accepts jquery mode arguments' );
$payload = decode_json($stdout);
is( $payload->{jquery}, 1, 'main prints jquery mode in the runner result' );

$stdout = q{};
$stderr = q{};
open $stdout_fh, '>', \$stdout or die "Unable to reopen stdout scalar for invalid input: $!";
open $stderr_fh, '>', \$stderr or die "Unable to reopen stderr scalar for invalid input: $!";
$exit = Browser::CLI::main(
    method    => 'GET',
    argv      => [],
    runner    => TestRunner->new(),
    output_fh => $stdout_fh,
    error_fh  => $stderr_fh,
);

is( $exit, 2, 'main exits non-zero on invalid input' );
like( $stderr, qr/Missing URL/, 'main reports CLI parsing failures' );

done_testing();
