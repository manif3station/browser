package Browser::Runner;

use strict;
use warnings;

use Digest::SHA qw(sha256_hex);
use Encode qw(decode_utf8);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use JSON::PP qw(encode_json);

use Browser::Runner::BrowserPath ();
use Browser::Runner::NodeRuntime ();

sub new {
    my ( $class, %args ) = @_;
    return bless \%args, $class;
}

sub request {
    my ( $self, %args ) = @_;
    my $method = uc( $args{method} || q{} );
    die "Unsupported method: $method" if $method ne 'GET' && $method ne 'POST' && $method ne 'PNG';

    my $playwright = $self->{playwright_factory}
      ? $self->{playwright_factory}->(%args)
      : _new_playwright();

    my $browser;
    my $page;
    my $result;

    eval {
        $browser = $playwright->launch( Browser::Runner::BrowserPath::_launch_options(%args) );
        $page    = $browser->newPage();
        $result = $method eq 'GET'
          ? _run_get( $page, browser => $browser, playwright => $playwright, %args )
          : $method eq 'POST'
          ? _run_post( $page, browser => $browser, playwright => $playwright, %args )
          : _run_png( $page, browser => $browser, playwright => $playwright, %args );
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

sub _screenshot_path {
    my ($requested) = @_;
    if ( defined $requested && $requested ne q{} ) {
        return $requested if $requested =~ /\.png\z/i;
        return $requested . '.png';
    }

    my $tmp = File::Spec->tmpdir();
    my $random = substr sha256_hex( join q{:}, time(), $$, rand(), {} ), 0, 16;
    return File::Spec->catfile( $tmp, "browser-$random.png" );
}

sub _run_get {
    my ( $page, %args ) = @_;
    my $response = $page->goto( $args{url}, _goto_options(%args) );
    _await_user(%args) if $args{interactive};
    _maybe_inject_jquery( $page, %args );
    my $script_result = _run_script(
        $page,
        response => $response,
        %args,
    );
    my $headers   = $response ? ( $response->headers() || {} ) : {};
    my $body      = $page->content();
    my $body_text = _page_text($page);
    my $title     = eval { $page->title() } || q{};
    my $result = {
        method        => 'GET',
        requested_url => $args{url},
        final_url     => $page->url(),
        status        => $response ? $response->status() : undef,
        title         => $title,
        content_type  => $headers->{'content-type'},
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
    my $wait_until = $args{wait_until} || ( $args{interactive} ? 'load' : 'networkidle' );
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
    _await_user(%args) if $args{interactive};
    _maybe_inject_jquery( $page, %args );
    my $script_result = _run_script(
        $page,
        response => $response,
        %args,
    );

    my $result = {
        method        => 'POST',
        requested_url => $args{url},
        final_url     => $page->url(),
        status        => $status,
        content_type  => $headers->{'content-type'},
        body          => $body,
        body_text     => _page_text($page),
    };
    $result->{is_captcha} = _is_captcha_page(
        title     => eval { $page->title() } || q{},
        body      => $html,
        body_text => $result->{body_text},
    );
    $result->{script_result} = $script_result if defined $args{script};
    return $result;
}

sub _run_png {
    my ( $page, %args ) = @_;
    my $response = $page->goto( $args{url}, _goto_options(%args) );
    _await_user(%args) if $args{interactive};

    my $file = _screenshot_path( $args{file} );
    my $dir = dirname($file);
    make_path($dir) if defined $dir && $dir ne q{} && !-d $dir;

    $page->screenshot(
        {
            path     => $file,
            fullPage => JSON::PP::true,
        }
    );

    return {
        method        => 'PNG',
        requested_url => $args{url},
        final_url     => $page->url(),
        status        => $response ? $response->status() : undef,
        title         => $page->title(),
        file          => $file,
    };
}

sub _run_script {
    my ( $page, %args ) = @_;
    return if !defined $args{script};
    return _run_controller_script( $page, %args ) if $args{controller};
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
    my $home_root = $ENV{HOME} || die 'HOME is required for browser skill jQuery injection';
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

    return 1 if $body =~ /g-recaptcha|h-captcha|recaptcha\/api|hcaptcha\.com/;
    return 1 if $title =~ /\bcaptcha\b/;
    return 1 if $title =~ /unusual traffic/;
    return 1 if $title =~ /verify you are human/;
    return 0;
}

sub _response_document {
    my (%args) = @_;
    my $body = defined $args{body} ? $args{body} : q{};
    my $content_type = lc( $args{content_type} || q{} );
    return $body if $content_type =~ m{text/html} || $content_type =~ m{xhtml\+xml} || $body =~ m{\A\s*<!doctype html}i || $body =~ m{\A\s*<html}i;
    return $body if $body =~ m{\A\s*<([a-zA-Z][a-zA-Z0-9]*)\b[^>]*>.*</\1>\s*\z}si;

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
