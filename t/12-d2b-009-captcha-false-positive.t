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

# D2B-073: a title where "captcha" is embedded without a leading word
# boundary (e.g. "reCAPTCHA") must also be flagged - the trailing \b is
# kept so a plural like "captchas" is still not flagged.
ok(
    Browser::Runner::_is_captcha_page(
        title     => 'reCAPTCHA verification required',
        body      => '<html><body>blocked</body></html>',
        body_text => 'blocked',
    ),
    'a title with "reCAPTCHA" embedded (no leading word boundary) is now flagged'
);
ok(
    !Browser::Runner::_is_captcha_page(
        title     => 'How CAPTCHAs work',
        body      => '<html><body>informational</body></html>',
        body_text => 'informational',
    ),
    'a title using the plural "CAPTCHAs" is still not flagged (trailing word boundary preserved)'
);

# D2B-073 false-positive guard: the fix specifically adds a "recaptcha"
# check (not a general "any word ending in captcha" widening), so an
# unrelated title that merely ends in "captcha" without being "recaptcha"
# must NOT be flagged.
ok(
    !Browser::Runner::_is_captcha_page(
        title     => 'NoCaptcha documentation',
        body      => '<html><body>informational</body></html>',
        body_text => 'informational',
    ),
    'an unrelated title ending in "captcha" (e.g. "NoCaptcha") that is not "recaptcha" is not flagged'
);

# D2B-083: _is_captcha_page's body-markup check ('g-recaptcha|h-captcha|
# recaptcha/api|hcaptcha.com') was a bare substring match, so a
# documentation page showing example widget integration markup inside a
# <pre> block was flagged as a real challenge page. Narrowed to require
# an attribute-assignment or script/iframe-src context instead.
ok(
    !Browser::Runner::_is_captcha_page(
        title => 'Integration Guide',
        body  => '<html><body><h1>Integration Guide</h1><p>Add this snippet to your page:</p><pre>&lt;div class="g-recaptcha" data-sitekey="your-key"&gt;&lt;/div&gt;</pre></body></html>',
    ),
    'a documentation page showing example reCAPTCHA integration markup inside a <pre> block is not flagged'
);

ok(
    Browser::Runner::_is_captcha_page(
        title => 'Example',
        body  => '<html><body><script src="https://www.google.com/recaptcha/api.js"></script></body></html>',
    ),
    'a page loading the real recaptcha/api script (quoted attribute) is still flagged'
);

# Codex review round 1: the initial quoted-only regex missed real
# widgets using unquoted attribute syntax, which is valid HTML - a
# genuine regression versus the original substring match.
ok(
    Browser::Runner::_is_captcha_page(
        title => 'Example',
        body  => '<html><body><script src=https://www.google.com/recaptcha/api.js></script></body></html>',
    ),
    'a page loading the real recaptcha/api script via an unquoted attribute is still flagged'
);
ok(
    Browser::Runner::_is_captcha_page(
        title => 'Example',
        body  => '<html><body><div class=g-recaptcha></div></body></html>',
    ),
    'a page with a real reCAPTCHA widget using an unquoted class attribute is still flagged'
);

done_testing();
