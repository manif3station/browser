use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-173: _is_captcha_page did not recognize Cloudflare's own
# interstitial/block pages, which use neither the word "captcha" nor
# any recognized widget markup. This is a genuine behavior addition -
# unlike this session's recent coverage-only tickets - so these
# assertions are written to fail against the pre-fix code first.

ok(
    Browser::Runner::_is_captcha_page( title => 'Just a moment...', body => q{} ),
    '_is_captcha_page detects Cloudflare\'s "Just a moment..." JS-challenge interstitial title'
);

ok(
    Browser::Runner::_is_captcha_page( title => 'Attention Required! | Cloudflare', body => q{} ),
    '_is_captcha_page detects Cloudflare\'s "Attention Required! | Cloudflare" block-page title'
);

ok(
    !Browser::Runner::_is_captcha_page( title => 'Welcome to Example Corp', body => '<html>ok</html>' ),
    '_is_captcha_page still leaves an unrelated title/page unflagged'
);

done_testing();
