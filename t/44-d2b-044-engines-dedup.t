use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-044: Browser::CLI::execute_search's --engines parsing accepts
# 'bing,bing' unchanged, producing two identical entries in the resulting
# engines list. If the first attempt is CAPTCHA-walled, Browser::Search::search
# retries the exact same walled engine a second time (wasting a full
# request/browser-launch cycle) instead of trying it only once.

{
    package FakeWalledRunner;
    sub new { bless { call_count => 0 }, shift }
    sub request {
        my ($self) = @_;
        $self->{call_count}++;
        return { is_captcha => 1, body => '<div class="g-recaptcha"></div>' };
    }
}

my $runner = FakeWalledRunner->new();
eval {
    Browser::CLI::execute_search(
        argv   => [ 'query', '--engines', 'bing,bing' ],
        runner => $runner,
    );
};
like( $@, qr/All search engines failed/, 'a fully-walled --engines list still fails as expected' );
is( $runner->{call_count}, 1, '--engines bing,bing tries bing only once, not twice, after deduplication' );

my $mixed_case_runner = FakeWalledRunner->new();
eval {
    Browser::CLI::execute_search(
        argv   => [ 'query', '--engines', 'bing,BING' ],
        runner => $mixed_case_runner,
    );
};
is( $mixed_case_runner->{call_count}, 1, '--engines bing,BING deduplicates case-insensitively too' );

done_testing();
