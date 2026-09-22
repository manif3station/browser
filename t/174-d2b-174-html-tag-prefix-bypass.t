use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-174: pins the html-tag-prefix bypass in _response_document,
# which is separate from (and easily confused with) the
# fragment-shape wrapping t/29-d2b-032-tag-name-must-match.t covers.
# A body that itself starts with a real <html> or <!doctype html>
# tag is trusted raw regardless of the declared content_type -
# documented in README.md edge case 6. No behavioral change - this
# test proves and documents an existing, intentional bypass.

is(
    Browser::Runner::_response_document( body => '<html><body>real page</body></html>', content_type => 'text/plain' ),
    '<html><body>real page</body></html>',
    'a body starting with a real <html> tag bypasses wrapping even under a non-HTML content_type'
);

is(
    Browser::Runner::_response_document( body => '<!doctype html><html><body>real page</body></html>', content_type => 'application/xml' ),
    '<!doctype html><html><body>real page</body></html>',
    'a body starting with <!doctype html> likewise bypasses wrapping under a non-HTML content_type'
);

is(
    Browser::Runner::_response_document( body => '<root>data</root>', content_type => 'application/xml' ),
    join( q{}, '<!doctype html><html><head><meta charset="utf-8"><title>browser.post</title></head><body><pre id="browser-post-body">', '&lt;root&gt;data&lt;/root&gt;', '</pre></body></html>' ),
    'a non-html-tag-shaped body (e.g. <root>) is still wrapped under a non-HTML content_type - the bypass is specific to <html>/<!doctype html>, not any tag'
);

done_testing();
