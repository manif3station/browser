package Browser::Runner;

use strict;
use warnings;

use Cwd qw(getcwd);
use File::Basename qw(dirname);
use File::Path qw(make_path);
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
          ? _run_get( $page, %args )
          : _run_post( $page, %args );
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
    my $runtime_root = File::Spec->catdir( $skill_root, 'local', 'playwright-node' );
    my $node_modules = File::Spec->catdir( $runtime_root, 'node_modules' );
    my $playwright = File::Spec->catdir( $node_modules, 'playwright' );
    my $express    = File::Spec->catdir( $node_modules, 'express' );
    my $uuid       = File::Spec->catdir( $node_modules, 'uuid' );

    make_path($runtime_root) if !-d $runtime_root;
    if ( !-d $playwright || !-d $express || !-d $uuid ) {
        local $ENV{PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD} = 1;
        _run_in_dir( $runtime_root, qw(npm install --no-save playwright express uuid) );
    }

    $ENV{NODE_PATH} = join ':', grep { defined && $_ ne q{} } $node_modules, $ENV{NODE_PATH};
    return $runtime_root;
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

sub _run_get {
    my ( $page, %args ) = @_;
    my $response = $page->goto( $args{url}, { waitUntil => 'networkidle' } );
    my $result = {
        method        => 'GET',
        requested_url => $args{url},
        final_url     => $page->url(),
        status        => $response ? $response->status() : undef,
        title         => $page->title(),
    };
    $result->{script_result} = $page->evaluate( $args{script} ) if defined $args{script};
    return $result;
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

    my $result = {
        method        => 'POST',
        requested_url => $args{url},
        final_url     => $response->url(),
        status        => $status,
        body          => $body,
    };
    $result->{script_result} = $page->evaluate( $args{script} ) if defined $args{script};
    return $result;
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
