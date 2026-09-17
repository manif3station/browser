use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-029: on the success path, Browser::Runner::request calls
# $playwright->quit() unwrapped after $result is already fully computed.
# If quit() itself throws (e.g. an already-dead browser process, a closed
# pipe), the exception propagates and the caller loses a successful,
# fully-computed result entirely instead of getting it back - unlike the
# error path, which already wraps its own quit() call in eval for exactly
# this reason.

{
    package FakePage;
    sub new { bless {}, shift }
    sub goto { return undef }
    sub url { return 'https://example.test/' }
    sub title { return 'Example' }
    sub content { return '<html></html>' }
    sub evaluate { return q{} }
}

{
    package FakeBrowser;
    sub new  { bless {}, shift }
    sub newPage { return FakePage->new }
}

{
    package FakePlaywrightQuitDies;
    sub new    { bless {}, shift }
    sub launch { return FakeBrowser->new }
    sub quit   { die "playwright process already exited\n"; }
}

my $runner = Browser::Runner->new( playwright_factory => sub { return FakePlaywrightQuitDies->new } );

my $result = eval {
    $runner->request( method => 'GET', url => 'https://example.test/' );
};
my $error = $@;

ok( !$error, 'a quit() failure after a successful GET does not propagate as a fatal error' )
  or diag("Got error instead of a result: $error");
is( ref $result, 'HASH', 'the successfully computed result is still returned even though quit() failed' );
is( $result->{final_url}, 'https://example.test/', 'the returned result is the real, correctly computed one, not an empty placeholder' );

done_testing();
