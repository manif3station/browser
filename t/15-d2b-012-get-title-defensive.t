use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-012: browser.get's title() lookup (feeding both the result's own
# 'title' field and is_captcha detection) must be defensively wrapped the
# same way browser.post's identical is_captcha title lookup already is,
# so a title() failure does not abort the whole GET request.

{
    package FakeThrowingTitlePage;
    sub new { bless {}, shift }
    sub goto { return undef }
    sub url { return 'https://example.test/final' }
    sub content { return '<html><body>ok</body></html>' }
    sub title { die "title() exploded\n" }
    sub evaluate { return '' }
}

my $page = FakeThrowingTitlePage->new;

my $result = eval {
    Browser::Runner::_run_get(
        $page,
        url => 'https://example.test',
    );
};
my $error = $@;

ok( !$error, 'browser.get does not abort when title() throws' )
    or diag("_run_get died: $error");
is( $result->{title}, q{}, 'title field falls back to empty string when title() throws' )
    if !$error;
ok( !$result->{is_captcha}, 'is_captcha is computed (false) against the empty fallback title, not left undefined' )
    if !$error;

done_testing();
