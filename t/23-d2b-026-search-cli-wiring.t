use strict;
use warnings;

use JSON::PP qw(decode_json);
use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-026: dashboard browser.search <query> wiring - --engine/--engines
# override the engine order, --max caps the result count, and the CLI
# contract (encode one JSON payload to stdout, exit 0; exit 2 with a
# sanitized message on error) matches browser.get/post/png exactly.

{
    package FakeSearchRunner;
    sub new { bless { calls => [] }, shift }
    sub request {
        my ( $self, %args ) = @_;
        push @{ $self->{calls} }, $args{url};
        return { is_captcha => 0, body => '<div class="g"><a href="https://example.com/x"><h3>X</h3></a><span class="VwiC3b">Y</span></div>' };
    }
}

my $runner = FakeSearchRunner->new();
my $result = Browser::CLI::execute_search(
    argv   => ['a 30B model on a mini PC'],
    runner => $runner,
);
is( $result->{query}, 'a 30B model on a mini PC', 'query is passed through' );
is( $result->{engine_used}, 'bing', 'default engine order leads with bing' );
like( $runner->{calls}[0], qr/bing\.com/, 'first request goes to bing by default' );

$runner = FakeSearchRunner->new();
$result = Browser::CLI::execute_search(
    argv   => [ 'query', '--engine', 'google' ],
    runner => $runner,
);
is( $result->{engine_used}, 'google', '--engine overrides the engine order to a single named engine' );

$runner = FakeSearchRunner->new();
$result = Browser::CLI::execute_search(
    argv   => [ 'query', '--engines', 'duckduckgo,bing' ],
    runner => $runner,
);
like( $runner->{calls}[0], qr/duckduckgo\.com/, '--engines overrides the order, trying the first named engine first' );

$runner = FakeSearchRunner->new(); # returns 1 matched result when queried against google (the engine the body's markup matches)
$result = Browser::CLI::execute_search(
    argv   => [ 'query', '--engine', 'google', '--max', '0' ],
    runner => $runner,
);
is( scalar @{ $result->{results} }, 0, '--max 0 returns zero results even when the engine has real results to return' );

$runner = FakeSearchRunner->new();
$result = Browser::CLI::execute_search(
    argv   => [ 'query', '--engine', 'google' ],
    runner => $runner,
);
is( scalar @{ $result->{results} }, 1, 'omitting --max still returns the real result (sanity check for the --max 0 case above)' );

eval { Browser::CLI::execute_search( argv => [ 'q', '--engine', 'google', '--max', '-1' ], runner => FakeSearchRunner->new() ) };
like( $@, qr/--max/, 'execute_search refuses a negative --max value' );

eval { Browser::CLI::execute_search( argv => [], runner => FakeSearchRunner->new() ) };
like( $@, qr/Missing query/, 'execute_search refuses a missing query the same way execute() refuses a missing URL' );

eval { Browser::CLI::execute_search( argv => ['   '], runner => FakeSearchRunner->new() ) };
like( $@, qr/Missing query/, 'execute_search refuses a whitespace-only query the same way it refuses a missing one' );

eval { Browser::CLI::execute_search( argv => [ 'q', '--engine', 'not-a-real-engine' ], runner => FakeSearchRunner->new() ) };
like( $@, qr/Unknown engine/, 'execute_search refuses an unrecognised --engine name' );

eval { Browser::CLI::execute_search( argv => [ 'q', '--engines', q{} ], runner => FakeSearchRunner->new() ) };
like( $@, qr/--engines/, 'execute_search refuses an --engines value that names no engines at all' );

{
    my $unicode_runner = FakeSearchRunner->new();
    Browser::CLI::execute_search( argv => ["caf\x{e9}"], runner => $unicode_runner );
    like( $unicode_runner->{calls}[0], qr/caf%C3%A9/, 'a non-ASCII query is UTF-8 encoded in the request URL, not Latin-1 encoded' );
}

my $output = q{};
open my $fh, '>', \$output or die;
my $exit = Browser::CLI::main_search( argv => ['query'], output_fh => $fh, runner => FakeSearchRunner->new() );
close $fh;
is( $exit, 0, 'main_search returns exit code 0 on success' );
my $decoded = decode_json($output);
is( $decoded->{engine_used}, 'bing', 'main_search prints the search result as one JSON payload' );

my $error_output = q{};
open my $error_fh, '>', \$error_output or die;
$exit = Browser::CLI::main_search( argv => [], error_fh => $error_fh, runner => FakeSearchRunner->new() );
close $error_fh;
is( $exit, 2, 'main_search returns exit code 2 on a refused query' );
like( $error_output, qr/Missing query/, 'main_search prints the sanitized error message' );

done_testing();
