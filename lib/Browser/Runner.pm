package Browser::Runner;

use strict;
use warnings;

use Encode qw(decode_utf8);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempfile);
use JSON::PP qw(encode_json);

use Browser::Runner::BrowserPath ();
use Browser::Runner::Capture ();
use Browser::Runner::NodeRuntime ();

sub new {
    my ( $class, %args ) = @_;
    return bless \%args, $class;
}

sub request {
    my ( $self, %args ) = @_;
    my $method = uc( $args{method} || q{} );
    die "Unsupported method: $method" if $method ne 'GET' && $method ne 'POST' && $method ne 'PNG' && $method ne 'PDF';

    # D2B-196: PDF export (Chromium DevTools' printToPDF, via Playwright's
    # page->pdf()) is a Chromium-only capability - Firefox/WebKit do not
    # implement it at all. Refused here, before ever launching a browser,
    # rather than letting Playwright's own native error surface.
    if ( $method eq 'PDF' ) {
        my $normalized = lc( defined $args{browser} ? $args{browser} : 'chrome' );
        die "browser.pdf only supports Chromium-based browsers (chrome, chromium, edge) - Playwright's PDF export has no Firefox/WebKit support"
          if $normalized eq 'firefox' || $normalized eq 'webkit';
    }

    my $playwright = $self->{playwright_factory}
      ? $self->{playwright_factory}->(%args)
      : _new_playwright();

    my $browser;
    my $page;
    my $result;

    eval {
        $browser = $playwright->launch( Browser::Runner::BrowserPath::_launch_options(%args) );
        $page    = $browser->newPage();
        # D2B-195: %args already carries its own 'browser' key (the
        # requested browser-TYPE string, e.g. 'chrome') - spreading it
        # after the real $browser/$playwright objects below let that
        # string win the duplicate-key hash-flattening resolution inside
        # _run_get/_run_post/_run_png, silently replacing the real
        # Playwright::Browser object with a plain string before it ever
        # reached a controller script. The real objects must come last.
        $result = $method eq 'GET'
          ? _run_get( $page, %args, browser => $browser, playwright => $playwright )
          : $method eq 'POST'
          ? _run_post( $page, %args, browser => $browser, playwright => $playwright )
          : $method eq 'PNG'
          ? Browser::Runner::Capture::run_png( $page, %args, browser => $browser, playwright => $playwright )
          : Browser::Runner::Capture::run_pdf( $page, %args, browser => $browser, playwright => $playwright );
        1;
    } or do {
        my $error = $@ || 'Unknown browser skill error';
        eval { $playwright->quit() };
        die $error;
    };

    eval { $playwright->quit() };
    return $result;
}

sub _new_playwright {
    Browser::Runner::NodeRuntime::_ensure_node_runtime();
    require Playwright;
    return Playwright->new();
}

sub _defined_or_empty {
    my ($value) = @_;
    return defined $value ? $value : q{};
}

sub _run_get {
    my ( $page, %args ) = @_;
    my $response = $page->goto( $args{url}, _goto_options(%args) );
    my $script_result = _interact_and_run_script( $page, %args, response => $response );
    my $headers   = $response ? ( $response->headers() || {} ) : {};
    my $body      = $page->content();
    my $body_text = _page_text($page);
    my $title     = _defined_or_empty( eval { $page->title() } );
    my $result = {
        method        => 'GET',
        requested_url => $args{url},
        final_url     => $page->url(),
        status        => $response ? $response->status() : undef,
        title         => $title,
        content_type  => $headers->{'content-type'},
        headers       => $headers,
        body          => $body,
        body_text     => $body_text,
        is_captcha    => _is_captcha_page(
            title     => $title,
            body      => $body,
            body_text => $body_text,
        ),
    };
    $result->{script_result} = $script_result if defined $args{script};
    return $result;
}

sub _goto_options {
    my (%args) = @_;
    my $wait_until = defined $args{wait_until} ? $args{wait_until} : ( $args{interactive} ? 'load' : 'networkidle' );
    die "Unsupported wait-until mode: $wait_until"
      if $wait_until ne 'load' && $wait_until ne 'domcontentloaded' && $wait_until ne 'networkidle';
    my %options = (
        waitUntil => $wait_until,
    );
    if ( defined $args{timeout_ms} ) {
        $options{timeout} = $args{timeout_ms};
    }
    elsif ( $args{interactive} ) {
        $options{timeout} = 0;
    }
    return \%options;
}

sub _run_post {
    my ( $page, %args ) = @_;
    my $request = $page->request();
    my %request_options;
    $request_options{data} = $args{data} if defined $args{data};

    my $response = %request_options
      ? $request->post( $args{url}, \%request_options )
      : $request->post( $args{url} );

    my $body    = $response->text();
    my $headers = $response->headers() || {};
    my $status  = $response->status();
    my $html    = _response_document(
        body         => $body,
        content_type => $headers->{'content-type'},
    );

    $page->setContent($html);
    $page->evaluate( 'window.__BROWSER_POST__ = ' . _post_data_as_js_literal(
        {
            method => 'POST',
            status => $status,
            url    => $response->url(),
            body   => $body,
        }
    ) . '; return true;' );
    my $script_result = _interact_and_run_script( $page, %args, response => $response );

    # D2B-092: setContent() (used above to display the POST response
    # body) never itself navigates the page, so a plain, non-scripted
    # POST left $page->url() at the browser's untouched default -
    # Playwright's newPage() always starts a fresh page at literally
    # "about:blank", and this codebase's request() always launches a
    # fresh browser+page per call (see request(), above), so that
    # value is a reliable sentinel for "nothing has navigated this
    # page at all" - whether because no --script ran, because the
    # response body's own inline markup/script (evaluated by
    # setContent) didn't navigate, or because --ask's manual
    # interaction didn't either. Two earlier attempts at this fix used
    # weaker signals that Codex review found real holes in: comparing
    # URLs for before/after equality was fooled by a script that
    # deliberately navigated back to its starting URL, and checking
    # merely "did a --script argument exist" missed navigation caused
    # by the response's own embedded script or by --ask. Checking the
    # literal "about:blank" sentinel instead of trying to infer *why*
    # nothing navigated covers all of those causes uniformly.
    #
    # KNOWN, ACCEPTED LIMITATION (Codex review round 3): this sentinel
    # cannot distinguish "the page never navigated at all" from "a
    # script/response/user deliberately navigated the page BACK to
    # literally about:blank" - both leave $page->url() at that exact
    # string, and this code reports the response's real URL in
    # either case. There is no static post-hoc signal that can tell
    # these apart without Playwright's own navigation-event tracking
    # (e.g. a 'framenavigated' listener), which this codebase's
    # request()/Playwright wrapper does not use. This trades a
    # vanishingly rare, deliberate edge case (ending a POST flow back
    # at about:blank on purpose) for correctly fixing the reported,
    # common case (a plain POST always wrongly reporting about:blank
    # instead of the real response URL) - about:blank itself was
    # never a useful answer to report to a caller either way.
    my $post_page_url = $page->url();
    my $final_url = ( !defined $post_page_url || $post_page_url eq 'about:blank' ) ? $response->url() : $post_page_url;

    my $result = {
        method        => 'POST',
        requested_url => $args{url},
        final_url     => $final_url,
        status        => $status,
        content_type  => $headers->{'content-type'},
        headers       => $headers,
        body          => $body,
        body_text     => _page_text($page),
    };
    # D2B-084: check the raw response body, not $html (the possibly
    # wrapped/escaped body handed to setContent) - _response_document's
    # D2B-079 escaping destroys the literal tag/attribute structure
    # D2B-083's captcha check requires, so a real widget served as a
    # bare fragment with no explicit HTML content-type would otherwise
    # never be detected.
    $result->{is_captcha} = _is_captcha_page(
        title     => _defined_or_empty( eval { $page->title() } ),
        body      => $body,
        body_text => $result->{body_text},
    );
    $result->{script_result} = $script_result if defined $args{script};
    return $result;
}

sub _interact_and_run_script {
    my ( $page, %args ) = @_;
    _await_user(%args) if $args{interactive};
    _maybe_inject_jquery( $page, %args );
    return _run_script( $page, %args );
}

sub _run_script {
    my ( $page, %args ) = @_;

    # D2B-184: checking !defined $args{script} before $args{controller}
    # made _run_controller_script's own "Controller mode requires
    # --script" die unreachable for the omitted-flag case - only the
    # explicit empty-string case (--script '') could ever trigger it
    # (D2B-158). Controller mode is checked first now, so an omitted
    # --script in controller mode gets the same documented error an
    # empty one already did, instead of a silent no-op.
    return _run_controller_script( $page, %args ) if $args{controller};
    return if !defined $args{script};
    die "--script must not be empty" if $args{script} eq q{};
    return $page->evaluate( $args{script} );
}

sub _run_controller_script {
    my ( $page, %args ) = @_;
    die "Controller mode requires --script" if !defined $args{script} || $args{script} eq q{};

    my $controller = eval <<"EOF";
sub {
    my (\$page, \$browser, \$playwright, \$initial_response, \$method, \$url) = \@_;
    my \$response = \$initial_response;
    return sub {
        $args{script}
    }->();
}
EOF
    die "Controller script failed: $@" if $@;

    my $result = eval {
        $controller->(
            $page,
            $args{browser},
            $args{playwright},
            $args{response},
            $args{method},
            $args{url},
        );
    };
    die "Controller script failed: $@" if $@;
    return $result;
}

sub _await_user {
    my (%args) = @_;
    my $input_fh = $args{input_fh} || \*STDIN;
    my $prompt_fh = $args{prompt_fh} || \*STDERR;
    print {$prompt_fh} "Browser is open for interactive work. Complete the captcha or login flow, then press Enter to continue.\n";
    my $line = <$input_fh>;
    die "stdin is not interactive - --ask/--askme requires a real terminal to confirm on\n" if !defined $line;
    return 1;
}

sub _maybe_inject_jquery {
    my ( $page, %args ) = @_;
    return 0 if !$args{jquery};
    my $path = _jquery_path();
    $page->addScriptTag( { path => $path } );
    return 1;
}

sub _jquery_path {
    my $home_root = Browser::Runner::NodeRuntime::_home_root( context => 'browser skill jQuery injection' );
    my $path = File::Spec->catfile( $home_root, 'node_modules', 'jquery', 'dist', 'jquery.min.js' );
    die "Missing jQuery runtime at $path" if !-f $path;
    return $path;
}

sub _page_text {
    my ($page) = @_;
    return $page->evaluate(q{return document.body ? document.body.innerText : ""});
}

sub _is_captcha_page {
    my (%args) = @_;
    my $title = lc( $args{title} || q{} );
    my $body  = lc( $args{body}  || q{} );

    # D2B-083: a bare substring match here flagged documentation pages
    # that merely show example widget-integration markup (inside a
    # <pre> block, HTML-entity-escaped) as real challenge pages, since
    # escaping only affects '<'/'>' - the attribute text itself
    # ("class=\"g-recaptcha\"") survives untouched. Requiring a real,
    # unescaped opening tag (literal '<' ... '>') around the matching
    # attribute distinguishes a live widget from an escaped example
    # without attempting full HTML parsing or <pre>-block detection.
    # The attribute value itself may be double-quoted, single-quoted,
    # or bare/unquoted (all valid HTML) - Codex review round 1 found
    # the quotes-only version missed real widgets using unquoted
    # attribute syntax (e.g. src=https://...recaptcha/api.js), a
    # regression this covers by accepting any of the three forms.
    my $class_marker = qr{(?:g-recaptcha|h-captcha)};
    my $src_marker    = qr{(?:recaptcha/api|hcaptcha\.com)};
    return 1 if $body =~ m{<[a-z][^>]*\bclass\s*=\s*(?:"[^"]*\b$class_marker\b[^"]*"|'[^']*\b$class_marker\b[^']*'|[^\s>"']*\b$class_marker\b[^\s>"']*)[^>]*>};
    return 1 if $body =~ m{<[a-z][^>]*\b(?:src|action)\s*=\s*(?:"[^"]*$src_marker[^"]*"|'[^']*$src_marker[^']*'|[^\s>"']*$src_marker[^\s>"']*)[^>]*>};
    return 1 if $title =~ /\bcaptcha\b/;
    return 1 if $title =~ /recaptcha/;
    return 1 if $title =~ /unusual traffic/;
    return 1 if $title =~ /verify you are human/;

    # D2B-173: Cloudflare's own interstitial/block pages use neither
    # the word "captcha" nor any recognized widget markup, so they
    # need their own title checks - "Just a moment..." is its
    # JS-challenge interstitial, "Attention Required! | Cloudflare"
    # is its block page for flagged traffic.
    return 1 if $title =~ /just a moment/;
    return 1 if $title =~ /attention required/;
    return 0;
}

# D2B-079: the tag-shape heuristic used to only check that the body
# started with an opening tag and ended with a matching closing tag,
# with a greedy DOTALL middle - so sibling elements sharing the outer
# tag name (including an injected <script> sibling) satisfied it just
# as well as one genuinely nested element, and this trusted result was
# handed to Playwright's page->setContent (which executes embedded
# <script> tags). A depth-tracking replacement was tried, but real
# HTML has implicit tag-closing rules (e.g. <p> auto-closes when a
# block element like <div> begins) that a hand-rolled tag-stack scanner
# cannot safely replicate without reimplementing HTML5 tree
# construction - see e.g. '<p><div>ok</div><script>evil</script></p>',
# which the scanner reads as one well-formed root but a real HTML
# parser (and therefore Playwright) treats as three siblings, letting
# the script through. Rather than chase that class of bypass, the
# heuristic is removed entirely: only an explicit text/html/xhtml+xml
# content type, or a body that itself starts with a doctype/<html>
# tag, is ever trusted as raw markup. Everything else - including a
# bare, legitimately well-formed HTML fragment - is now escaped and
# wrapped, closing the vulnerability at the cost of no longer
# rendering untyped fragments as live markup (D2B-008's original
# convenience, deliberately given up here for correctness).

# D2B-080: the ASCII HTML-whitespace character class below (tab,
# newline, form feed, carriage return, space - deliberately NOT
# Perl's \s, which also matches vertical tab and other Unicode
# whitespace HTML does not treat as tag whitespace, per D2B-079's
# round 4/5 findings) is shared by every trust-boundary check in
# _content_type_is_html and _response_document, so a future fix to
# it only has to happen once.
my $HTML_WS = '[\x09\x0A\x0C\x0D\x20]';

# D2B-079: these checks are now the entire trust boundary for POST
# response bodies (the tag-shape heuristic that used to sit alongside
# them was removed for being bypassable). A substring match on the
# content type let 'application/json; note=text/html' or
# 'application/xhtml+xml-evil' slip through as trusted, and a bare
# "starts with <html"/"starts with <!doctype html" sniff with no
# boundary check let '<htmlscript>...' or '<!doctype htmlx>' slip
# through too. Both are now exact/boundary-checked.
sub _content_type_is_html {
    my ($content_type) = @_;
    my ($media_type) = split m{;}, ( $content_type // q{} ), 2;
    $media_type = lc($media_type // q{});
    $media_type =~ s/\A$HTML_WS+|$HTML_WS+\z//g;
    return $media_type eq 'text/html' || $media_type eq 'application/xhtml+xml';
}

sub _response_document {
    my (%args) = @_;
    my $body = defined $args{body} ? $args{body} : q{};
    my $content_type = $args{content_type};
    return $body
      if _content_type_is_html($content_type)
      || $body =~ m{\A$HTML_WS*<!doctype$HTML_WS+html(?=$HTML_WS|>)}i
      || $body =~ m{\A$HTML_WS*<html(?=$HTML_WS|>)}i;

    return join q{},
      '<!doctype html><html><head><meta charset="utf-8"><title>browser.post</title></head><body><pre id="browser-post-body">',
      _escape_html($body),
      '</pre></body></html>';
}

sub _escape_html {
    my ($value) = @_;
    $value =~ s/&/&amp;/g;
    $value =~ s/</&lt;/g;
    $value =~ s/>/&gt;/g;
    $value =~ s/"/&quot;/g;
    $value =~ s/'/&#39;/g;
    return $value;
}

# encode_json returns a UTF-8 encoded byte string, not a Perl character
# string; concatenating it directly with other (possibly wide-character)
# Perl strings mixes representations and can corrupt non-ASCII content.
# decode_utf8 normalizes it back to a proper character string first. On
# top of that, JSON permits U+2028/U+2029 unescaped in a string value, but
# both are legal JS line terminators when the JSON text is embedded as JS
# *source* (not parsed as JSON) - as this is, via string concatenation
# into a page.evaluate() call - so they are additionally escaped to avoid
# a POST response body breaking out of the intended JS string context.
sub _post_data_as_js_literal {
    my ($data) = @_;
    my $json = decode_utf8( encode_json($data) );
    $json =~ s/\x{2028}/\\u2028/g;
    $json =~ s/\x{2029}/\\u2029/g;
    return $json;
}

1;
