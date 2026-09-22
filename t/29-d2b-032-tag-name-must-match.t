use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-032 originally fixed _response_document's fragment-detection
# regex accepting ANY opening tag paired with ANY closing tag, never
# checking the tag names actually match. D2B-079 later removed that
# fragment-shape trust path entirely (a hand-rolled scanner cannot
# safely replicate HTML5's implicit tag-closing rules, so it was
# itself a script-injection bypass) - a fragment body (one that does
# NOT itself start with a boundary-checked <!doctype html>/<html>
# tag) with no explicit text/html content-type is now always
# escaped/wrapped, regardless of whether its tags happen to match.
# These cases are kept as regression coverage for that end state.
# D2B-174: this is narrower than it may read - a body that DOES start
# with a real <html>/<!doctype html> tag still bypasses wrapping
# under any content-type (README.md edge case 6, pinned separately in
# t/174-d2b-174-html-tag-prefix-bypass.t) - only fragment-shaped
# bodies like the ones below are unconditionally wrapped.

{
    my $mismatched = '<div>text</span>';
    my $document = Browser::Runner::_response_document( body => $mismatched, content_type => 'text/plain' );
    unlike( $document, qr{\A<div>text</span>\z}, 'a body with mismatched opening/closing tag names is NOT passed through raw as trusted HTML' );
    like( $document, qr{<pre[^>]*>}, 'a mismatched-tag body is instead escaped into the safe <pre> fallback' );
}

{
    # D2B-079: a well-formed single-root fragment is no longer trusted
    # raw either, since text/plain is not an explicit HTML content
    # type - it is escaped/wrapped, same as the mismatched case above.
    my $well_formed = '<div>text</div>';
    my $document = Browser::Runner::_response_document( body => $well_formed, content_type => 'text/plain' );
    like( $document, qr{<pre[^>]*>}, 'D2B-079: even a well-formed fragment is escaped/wrapped without an explicit HTML content-type' );
    like( $document, qr{&lt;div&gt;text&lt;/div&gt;}, 'D2B-079: the fragment content itself appears HTML-escaped inside the wrapper' );
}

{
    my $mixed_case = '<DIV>text</div>';
    my $document = Browser::Runner::_response_document( body => $mixed_case, content_type => 'text/plain' );
    like( $document, qr{<pre[^>]*>}, 'D2B-079: a mixed-case tag pair is likewise escaped/wrapped without an explicit HTML content-type' );
}

done_testing();
