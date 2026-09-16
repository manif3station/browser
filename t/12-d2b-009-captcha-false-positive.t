use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-009: _is_captcha_page must not flag a normal page that merely mentions
# captcha-related phrases in its body copy, while still catching a real
# challenge page (recaptcha/hcaptcha widget markup, or a challenge title).

ok(
    !Browser::Runner::_is_captcha_page(
        title     => 'How CAPTCHAs work',
        body      => '<html><body><p>This article explains how captcha and unusual traffic detection works.</p></body></html>',
        body_text => 'This article explains how captcha and unusual traffic detection works.',
    ),
    'an informational article mentioning captcha/unusual traffic in body copy is not flagged'
);

ok(
    !Browser::Runner::_is_captcha_page(
        title     => 'Login',
        body      => '<html><body><label>verify you are human by entering the code we sent</label></body></html>',
        body_text => 'verify you are human by entering the code we sent',
    ),
    'a login page using "verify you are human" as ordinary UI copy is not flagged'
);

ok(
    Browser::Runner::_is_captcha_page(
        title     => 'Example',
        body      => '<html><body><div class="g-recaptcha" data-sitekey="x"></div></body></html>',
        body_text => q{},
    ),
    'a page with real reCAPTCHA widget markup is still flagged'
);

ok(
    Browser::Runner::_is_captcha_page(
        title     => 'unusual traffic from your computer network',
        body      => '<html><body>blocked</body></html>',
        body_text => 'blocked',
    ),
    'a real challenge page title is still flagged'
);

done_testing();
