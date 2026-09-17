use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-041: Browser::CLI::execute_search's --engines parsing splits on a
# bare comma with no whitespace trimming, so a human-friendly value like
# '--engines "bing, google"' (a space after the comma) produces the
# engine name ' google' (leading space), which fails the exact-match
# lookup against the known engine names and dies with "Unknown engine".

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
        argv   => [ 'query', '--engines', 'bing, google' ],
        runner => $runner,
    );
};
ok( !$@, 'execute_search accepts --engines with whitespace around the comma instead of dying with "Unknown engine"' ) or diag("Got error: $@");
is( $result->{engine_used}, 'bing', 'the first engine name is trimmed and resolved correctly' ) if $result;

$runner = FakeSearchRunner->new();
$result = Browser::CLI::execute_search(
    argv   => [ 'query', '--engines', '  duckduckgo  ,  bing  ' ],
    runner => $runner,
);
like( $runner->{calls}[0], qr/duckduckgo\.com/, 'leading/trailing whitespace around every engine name in the list is trimmed' );

done_testing();
