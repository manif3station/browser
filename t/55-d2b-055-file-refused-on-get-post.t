use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-055: browser.get/browser.post must refuse --file (only browser.png
# reads it), instead of silently accepting and ignoring it.

eval { Browser::CLI::execute( method => 'GET', argv => [ 'https://example.test', '--file', '/tmp/should-not-matter' ] ) };
like( $@, qr/--file/, 'browser.get refuses --file' );
like( $@, qr/browser\.png/, 'browser.get names browser.png as the command that reads --file' );

eval { Browser::CLI::execute( method => 'POST', argv => [ 'https://example.test', '--file', '/tmp/should-not-matter' ] ) };
like( $@, qr/--file/, 'browser.post refuses --file' );
like( $@, qr/browser\.png/, 'browser.post names browser.png as the command that reads --file' );

my $runner_calls = 0;
my %runner_args;
{
    package FakeRunner;
    sub new { bless {}, shift }
}
no warnings 'once';
local *FakeRunner::request = sub {
    my ( $self, %args ) = @_;
    $runner_calls++;
    %runner_args = %args;
    return { file => '/tmp/should-not-matter.png' };
};

my $result = Browser::CLI::execute(
    method => 'PNG',
    argv   => [ 'https://example.test', '--file', '/tmp/should-not-matter' ],
    runner => FakeRunner->new,
);
is( $runner_calls, 1, 'browser.png --file is unaffected and still reaches the runner' );
is( $runner_args{file}, '/tmp/should-not-matter', 'the runner actually receives the --file value for browser.png' );
is( $result->{file}, '/tmp/should-not-matter.png', 'browser.png --file result is passed through unchanged' );

done_testing();
