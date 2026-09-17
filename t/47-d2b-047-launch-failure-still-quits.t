use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-047: Browser::Runner::request calls $playwright->launch(...) and
# $browser->newPage() BEFORE the eval block that guards quit() cleanup.
# If either of those two calls dies (e.g. launch() succeeds in starting a
# real browser process but newPage() then fails), $playwright->quit() is
# never called at all - the already-started browser process leaks, with
# no cleanup attempt whatsoever.

{
    package FakeBrowserNewPageDies;
    sub new     { bless {}, shift }
    sub newPage { die "newPage failed - simulated page-creation error\n" }
}

{
    package FakePlaywrightTracksQuit;
    sub new       { bless { quit_called => 0 }, shift }
    sub launch    { return FakeBrowserNewPageDies->new }
    sub quit      { my ($self) = @_; $self->{quit_called}++; return 1 }
}

my $playwright = FakePlaywrightTracksQuit->new;
my $runner = Browser::Runner->new( playwright_factory => sub { return $playwright } );

eval {
    $runner->request( method => 'GET', url => 'https://example.test/' );
};
like( $@, qr/newPage failed/, 'the newPage() failure still propagates as an error' );
is( $playwright->{quit_called}, 1, 'quit() is still called even though newPage() (not the eval-guarded script/run logic) is what failed' );

done_testing();
