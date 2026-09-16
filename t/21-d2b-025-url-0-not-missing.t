use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-025: Browser::CLI::execute's URL check uses
# 'my $url = shift @argv or die "Missing URL"', so a URL whose value is the
# single character "0" - Perl's canonical false string - is wrongly refused
# as Missing URL even though a real, non-empty argument was supplied.

my @captured_urls;
{
    package FakeRunner;
    sub new { bless {}, shift }
    sub request { my ( $self, %args ) = @_; push @captured_urls, $args{url}; return {}; }
}

eval {
    Browser::CLI::execute(
        method => 'GET',
        argv   => ['0'],
        runner => FakeRunner->new,
    );
};
is( $@, q{}, "execute() does not die when the URL argument is the literal string '0'" );
is( $captured_urls[-1], '0', "execute() passes url => '0' through to the runner unchanged" );

eval { Browser::CLI::execute( method => 'GET', argv => [] ) };
like( $@, qr/Missing URL/, 'execute() still refuses a genuinely absent URL argument' );

eval { Browser::CLI::execute( method => 'GET', argv => [q{}] ) };
like( $@, qr/Missing URL/, 'execute() still refuses an empty-string URL argument' );

done_testing();
