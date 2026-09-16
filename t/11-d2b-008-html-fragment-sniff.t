use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-008: _response_document's HTML sniff must recognize HTML fragments
# that lack a <!doctype html>/<html> wrapper and have no text/html
# content-type, instead of escaping them into a <pre> block.

my $html_body = Browser::Runner::_response_document( body => '<div id="x">hi</div>', content_type => undef );
unlike( $html_body, qr/&lt;div/, 'a bare HTML fragment body is not HTML-escaped' );
like( $html_body, qr/<div id="x">hi<\/div>/, 'a bare HTML fragment body is set as real markup, unmodified' );

my $xhtml_body = Browser::Runner::_response_document( body => '<p>hello</p>', content_type => 'application/xhtml+xml' );
unlike( $xhtml_body, qr/&lt;p/, 'application/xhtml+xml content-type is treated as HTML' );

my $json_body = Browser::Runner::_response_document( body => '{"a":1}', content_type => 'application/json' );
like( $json_body, qr/browser-post-body/, 'a genuinely non-HTML body is still wrapped in the <pre> fallback' );
unlike( $json_body, qr/\A\{"a":1\}\z/, 'a genuinely non-HTML JSON body is not returned as raw unwrapped text' );

done_testing();
