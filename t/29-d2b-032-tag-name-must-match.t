use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-032: _response_document's fragment-detection regex accepted ANY
# opening tag paired with ANY closing tag, never checking the tag names
# actually match. A malformed body like '<div>text</span>' was treated
# as trustworthy HTML and passed through raw instead of being escaped
# into the safe <pre> fallback.

{
    my $mismatched = '<div>text</span>';
    my $document = Browser::Runner::_response_document( body => $mismatched, content_type => 'text/plain' );
    unlike( $document, qr{\A<div>text</span>\z}, 'a body with mismatched opening/closing tag names is NOT passed through raw as trusted HTML' );
    like( $document, qr{<pre[^>]*>}, 'a mismatched-tag body is instead escaped into the safe <pre> fallback' );
}

{
    my $well_formed = '<div>text</div>';
    my $document = Browser::Runner::_response_document( body => $well_formed, content_type => 'text/plain' );
    is( $document, $well_formed, 'a genuinely well-formed single-root fragment still passes through unchanged, as before' );
}

{
    # HTML tag names are case-insensitive; the tightened tag-name check
    # must not introduce a regression that rejects a legitimately
    # mixed-case (if unusual) but still self-consistent fragment.
    my $mixed_case = '<DIV>text</div>';
    my $document = Browser::Runner::_response_document( body => $mixed_case, content_type => 'text/plain' );
    is( $document, $mixed_case, 'a mixed-case but self-consistent tag pair (DIV/div) is still treated as trusted HTML, not a new false-positive rejection' );
}

done_testing();
