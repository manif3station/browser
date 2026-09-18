use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-008 originally recognized HTML fragments that lacked a
# <!doctype html>/<html> wrapper and had no text/html content-type,
# trusting them as raw markup instead of escaping them into a <pre>
# block. D2B-079 removed that trust path entirely: a hand-rolled
# tag-shape/single-root check cannot safely replicate HTML5's implicit
# tag-closing rules, so it was a security bypass (a crafted body could
# smuggle a live <script> sibling past it into Playwright's
# setContent). A bare fragment with no explicit HTML content-type is
# now always escaped/wrapped - deliberately giving up the "render as
# live markup" convenience for correctness. Only an explicit
# text/html or application/xhtml+xml content-type (or a body that
# itself starts with a doctype/<html> tag) is still trusted raw.

my $bare_fragment_body = Browser::Runner::_response_document( body => '<div id="x">hi</div>', content_type => undef );
like( $bare_fragment_body, qr/&lt;div/, 'D2B-079: a bare HTML fragment with no explicit HTML content-type is now HTML-escaped, not trusted as live markup' );
like( $bare_fragment_body, qr/browser-post-body/, 'D2B-079: the bare fragment is wrapped in the safe <pre> fallback' );

my $xhtml_body = Browser::Runner::_response_document( body => '<p>hello</p>', content_type => 'application/xhtml+xml' );
unlike( $xhtml_body, qr/&lt;p/, 'application/xhtml+xml content-type is treated as HTML' );

my $json_body = Browser::Runner::_response_document( body => '{"a":1}', content_type => 'application/json' );
like( $json_body, qr/browser-post-body/, 'a genuinely non-HTML body is still wrapped in the <pre> fallback' );
unlike( $json_body, qr/\A\{"a":1\}\z/, 'a genuinely non-HTML JSON body is not returned as raw unwrapped text' );

done_testing();
