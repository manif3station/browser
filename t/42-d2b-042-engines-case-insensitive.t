use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-042: Browser::CLI::execute_search's engine-name lookup is an exact,
# case-sensitive hash lookup against the known engine names (bing, google,
# duckduckgo). --engine Bing or --engines DuckDuckGo,BING die with
# "Unknown engine" even though the intent is unambiguous.

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
my $result = eval {
    Browser::CLI::execute_search(
        argv   => [ 'query', '--engine', 'Bing' ],
        runner => $runner,
    );
};
ok( !$@, '--engine accepts a capitalized engine name instead of dying with "Unknown engine"' ) or diag("Got error: $@");
is( $result->{engine_used}, 'bing', 'the resolved engine name is still the canonical lowercase form' ) if $result;

$runner = FakeSearchRunner->new();
$result = Browser::CLI::execute_search(
    argv   => [ 'query', '--engines', 'DuckDuckGo,BING' ],
    runner => $runner,
);
like( $runner->{calls}[0], qr/duckduckgo\.com/, '--engines resolves a mixed-case comma-separated list correctly' );

done_testing();
