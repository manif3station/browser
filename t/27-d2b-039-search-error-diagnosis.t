use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Search;

# D2B-039: when every engine fails, the error must name the REAL reason
# each one failed - a CAPTCHA wall (is_captcha) is a genuinely different
# situation from a request exception (network error, missing browser,
# timeout), and the all-walled error must not claim every failure was a
# CAPTCHA wall when some engines actually threw an exception.

{
    package FakeSearchRunner;
    sub new { my ( $class, $code ) = @_; return bless { code => $code }, $class; }
    sub request { my ( $self, %args ) = @_; return $self->{code}->(%args); }
}

# --- All engines fail via a non-captcha exception ---
{
    my $runner = FakeSearchRunner->new( sub { die "connection refused\n"; } );

    eval {
        Browser::Search::search(
            query   => 'test query',
            engines => [
                { name => 'bing',   url => sub { 'https://www.bing.com/search?q=' . $_[0] } },
                { name => 'google', url => sub { 'https://www.google.com/search?q=' . $_[0] } },
            ],
            runner  => $runner,
        );
    };
    my $error = $@;

    unlike( $error, qr/CAPTCHA/i, "an all-exception failure is not misreported as a CAPTCHA/bot-check wall" );
    like( $error, qr/connection refused/, "the real exception message (connection refused) is surfaced in the error" );
    like( $error, qr/bing/, "the error still names the bing engine" );
    like( $error, qr/google/, "the error still names the google engine" );
}

# --- Mixed: one engine walled by CAPTCHA, the other fails via exception ---
{
    my $call_count = 0;
    my $runner = FakeSearchRunner->new(
        sub {
            $call_count++;
            return { is_captcha => 1, body => q{} } if $call_count == 1;
            die "DNS resolution failed\n";
        }
    );

    eval {
        Browser::Search::search(
            query   => 'test query',
            engines => [
                { name => 'bing',   url => sub { 'https://www.bing.com/search?q=' . $_[0] } },
                { name => 'google', url => sub { 'https://www.google.com/search?q=' . $_[0] } },
            ],
            runner  => $runner,
        );
    };
    my $error = $@;

    like( $error, qr/bing.*CAPTCHA/is, "bing's genuine CAPTCHA wall is still reported as CAPTCHA-walled" );
    like( $error, qr/google.*DNS resolution failed/is, "google's real exception is reported with its actual message, not misattributed to CAPTCHA" );
}

# --- All engines genuinely CAPTCHA-walled: existing behavior is preserved ---
{
    my $runner = FakeSearchRunner->new( sub { return { is_captcha => 1, body => q{} } } );

    eval {
        Browser::Search::search(
            query   => 'test query',
            engines => [ { name => 'bing', url => sub { 'https://www.bing.com/search?q=' . $_[0] } } ],
            runner  => $runner,
        );
    };
    like( $@, qr/bing.*CAPTCHA/is, "a genuinely all-CAPTCHA-walled search still reports CAPTCHA for that engine" );
    like( $@, qr/--ask/, "the error still points to --ask when at least one engine was CAPTCHA-walled" );
}

done_testing();
