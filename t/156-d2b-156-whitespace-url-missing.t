use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-156: Browser::CLI::execute's URL check (lib/Browser/CLI.pm:214) only
# rejected !defined/eq-empty-string, unlike browser.search's query check
# (line 288) which correctly uses a whitespace-only regex. A whitespace-only
# URL passed through untouched instead of being refused with "Missing URL".
# TDD red: this is not yet fixed.

{
    package FakeRunner;
    sub new { bless {}, shift }
    sub request { my ( $self, %args ) = @_; return {}; }
}

for my $method (qw(GET POST PNG)) {
    eval {
        Browser::CLI::execute(
            method => $method,
            argv   => [' '],
            runner => FakeRunner->new,
        );
    };
    like( $@, qr/Missing URL/, "execute() refuses a whitespace-only URL argument for $method" );
}

# Regression guard: '0' must remain accepted (D2B-025).
my @captured_urls;
{
    package FakeRunner0;
    sub new { bless {}, shift }
    sub request { my ( $self, %args ) = @_; push @captured_urls, $args{url}; return {}; }
}
eval {
    Browser::CLI::execute(
        method => 'GET',
        argv   => ['0'],
        runner => FakeRunner0->new,
    );
};
is( $@, q{}, "execute() still does not die when the URL argument is the literal string '0'" );
is( $captured_urls[-1], '0', "execute() still passes url => '0' through to the runner unchanged" );

done_testing();
