package Browser::Runner;

use strict;
use warnings;

use Cwd qw(getcwd);
use File::Basename qw(dirname);
use File::Spec;
use JSON::PP qw(encode_json);

sub new {
    my ( $class, %args ) = @_;
    return bless \%args, $class;
}

sub request {
    my ( $self, %args ) = @_;
    my $method = uc( $args{method} || q{} );
    die "Unsupported method: $method" if $method ne 'GET' && $method ne 'POST';

    my $playwright = $self->{playwright_factory}
      ? $self->{playwright_factory}->(%args)
      : _new_playwright();

    my $browser = $playwright->launch( _launch_options(%args) );
    my $page    = $browser->newPage();
    my $result;

    eval {
        $result = $method eq 'GET'
          ? _run_get( $page, browser => $browser, playwright => $playwright, %args )
          : _run_post( $page, browser => $browser, playwright => $playwright, %args );
        1;
    } or do {
        my $error = $@ || 'Unknown browser skill error';
        eval { $playwright->quit() };
        die $error;
    };

    $playwright->quit();
    return $result;
}

sub _new_playwright {
    _ensure_node_runtime();
    require Playwright;
    return Playwright->new();
}

sub _ensure_node_runtime {
    my $skill_root = _skill_root();
    my $home_root = $ENV{HOME} || die 'HOME is required for browser skill Node dependencies';
    my $package_json = File::Spec->catfile( $skill_root, 'package.json' );
    die "Missing package.json in $skill_root" if !-f $package_json;

    my $node_modules = File::Spec->catdir( $home_root, 'node_modules' );
    my $playwright = File::Spec->catdir( $node_modules, 'playwright' );
    my $express    = File::Spec->catdir( $node_modules, 'express' );
    my $uuid       = File::Spec->catdir( $node_modules, 'uuid' );

    if ( !-d $playwright || !-d $express || !-d $uuid ) {
        local $ENV{PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD} = 1;
        _run_command( 'npm', 'install', '--prefix', $home_root, $skill_root );
    }

    $ENV{NODE_PATH} = join ':', grep { defined && $_ ne q{} } $node_modules, $ENV{NODE_PATH};
    return $node_modules;
}

sub _launch_options {
    my (%args) = @_;
    my %launch = (
        headless => $args{headless} ? 1 : 0,
        type     => ( $args{browser} || 'chrome' ) eq 'chromium' ? 'chrome' : ( $args{browser} || 'chrome' ),
    );
    if ( my $path = $ENV{CHROMIUM_BIN} ) {
        $launch{executablePath} = $path;
    }
    return %launch;
}

sub _skill_root {
    return $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT} if $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT};
    return getcwd() if -d File::Spec->catdir( getcwd(), 'cli' ) && -d File::Spec->catdir( getcwd(), 'lib' );
    return File::Spec->catdir( dirname( dirname( dirname(__FILE__) ) ) );
}

sub _run_in_dir {
    my ( $dir, @command ) = @_;
    my $cwd = getcwd();
    chdir $dir or die "Unable to chdir to $dir: $!";
    my $ok = system(@command) == 0;
    my $exit = $? >> 8;
    chdir $cwd or die "Unable to restore cwd $cwd: $!";
    die "Command failed in $dir: @command" if !$ok;
    return $exit;
}

sub _run_command {
    my (@command) = @_;
    my $ok = system(@command) == 0;
    die "Command failed: @command" if !$ok;
    return $? >> 8;
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
    my $result = {
        method        => 'GET',
        requested_url => $args{url},
        final_url     => $page->url(),
        status        => $response ? $response->status() : undef,
        title         => $page->title(),
        content_type  => $headers->{'content-type'},
        body          => $body,
        body_text     => $body_text,
        is_captcha    => _is_captcha_page(
            title     => $page->title(),
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
    $page->evaluate( 'window.__BROWSER_POST__ = ' . encode_json(
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
    scalar <$input_fh>;
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
    my $body = lc( $args{body} || q{} );
    my $body_text = lc( $args{body_text} || q{} );
    my $combined = join "\n", $title, $body, $body_text;

    return 1 if $combined =~ /recaptcha/;
    return 1 if $combined =~ /\bcaptcha\b/;
    return 1 if $combined =~ /unusual traffic/;
    return 1 if $combined =~ /verify you are human/;
    return 0;
}

sub _response_document {
    my (%args) = @_;
    my $body = defined $args{body} ? $args{body} : q{};
    my $content_type = lc( $args{content_type} || q{} );
    return $body if $content_type =~ m{text/html} || $body =~ m{\A\s*<!doctype html}i || $body =~ m{\A\s*<html}i;

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

1;
