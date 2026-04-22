package Browser::Runner;

use strict;
use warnings;

use Cwd qw(getcwd);
use Digest::SHA qw(sha256_hex);
use File::Basename qw(dirname);
use File::Path qw(remove_tree);
use File::Spec;
use File::Temp qw(tempdir);
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
    my $fingerprint = _package_json_fingerprint($package_json);

    if ( !_node_runtime_is_current( home_root => $home_root, package_json => $package_json, fingerprint => $fingerprint ) ) {
        _install_node_runtime(
            home_root    => $home_root,
            package_json => $package_json,
        );
        _write_node_runtime_stamp(
            home_root    => $home_root,
            fingerprint  => $fingerprint,
        );
    }

    $ENV{NODE_PATH} = join ':', grep { defined && $_ ne q{} } $node_modules, $ENV{NODE_PATH};
    return $node_modules;
}

sub _package_json_dependency_specs {
    my ($package_json) = @_;
    open my $fh, '<', $package_json or die "Unable to read $package_json: $!";
    local $/;
    my $content = <$fh>;
    close $fh;

    my $decoded = eval { JSON::PP::decode_json($content) };
    die "Unable to parse $package_json: $@" if !$decoded || $@;

    my @specs;
    for my $section ( qw(dependencies devDependencies optionalDependencies peerDependencies) ) {
        my $entries = $decoded->{$section};
        next if ref($entries) ne 'HASH';
        for my $name ( sort keys %{$entries} ) {
            my $version = $entries->{$name};
            push @specs, defined $version && $version ne q{} ? "$name\@$version" : $name;
        }
    }

    return @specs;
}

sub _package_json_fingerprint {
    my ($package_json) = @_;
    open my $fh, '<', $package_json or die "Unable to read $package_json: $!";
    local $/;
    my $content = <$fh>;
    close $fh;
    return sha256_hex($content);
}

sub _node_runtime_is_current {
    my (%args) = @_;
    my $home_root = $args{home_root} || die 'home_root is required';
    my $package_json = $args{package_json} || die 'package_json is required';
    my $fingerprint = $args{fingerprint} || _package_json_fingerprint($package_json);
    my $node_modules = File::Spec->catdir( $home_root, 'node_modules' );

    for my $module ( _required_node_modules() ) {
        return 0 if !-d File::Spec->catdir( $node_modules, $module );
    }

    my $stamp = _read_node_runtime_stamp( home_root => $home_root );
    return 1 if defined $stamp && $stamp eq $fingerprint;

    return _installed_modules_satisfy_package_json(
        home_root    => $home_root,
        package_json => $package_json,
    );
}

sub _required_node_modules {
    return qw(express jquery playwright uuid);
}

sub _install_node_runtime {
    my (%args) = @_;
    my $home_root = $args{home_root} || die 'home_root is required';
    my $package_json = $args{package_json} || die 'package_json is required';
    my @specs = _package_json_dependency_specs($package_json);
    return 1 if !@specs;

    my $workspace_parent = File::Spec->catdir( $home_root, '.developer-dashboard', 'cache', 'node-package-installs' );
    my $target_root      = File::Spec->catdir( $home_root, 'node_modules' );
    _make_path_if_missing($workspace_parent);
    _make_path_if_missing($target_root);
    my $workspace = tempdir( 'npm-install-XXXXXX', DIR => $workspace_parent, CLEANUP => 1 );
    my $workspace_package_json = File::Spec->catfile( $workspace, 'package.json' );
    open my $workspace_fh, '>', $workspace_package_json or die "Unable to write $workspace_package_json: $!";
    print {$workspace_fh} qq|{"name":"browser-skill-runtime","version":"1.0.0","private":true}\n|;
    close $workspace_fh;

    my $cwd = getcwd();
    local $ENV{PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD} = 1;
    eval {
        chdir $workspace or die "Unable to chdir to $workspace for browser skill package.json dependency install: $!";
        _run_quiet_command( 'npx', '--yes', 'npm', 'install', @specs );
        chdir $cwd or die "Unable to chdir back to $cwd after browser skill package.json dependency install: $!";
        1;
    } or do {
        my $error = $@;
        chdir $cwd if getcwd() ne $cwd;
        die $error;
    };

    my $workspace_modules = File::Spec->catdir( $workspace, 'node_modules' );
    return 1 if !-d $workspace_modules;
    _clear_installed_node_modules(
        home_root    => $home_root,
        package_json => $package_json,
    );
    _run_quiet_command( 'cp', '-R', "$workspace_modules/.", $target_root );
    return 1;
}

sub _clear_installed_node_modules {
    my (%args) = @_;
    my $home_root = $args{home_root} || die 'home_root is required';
    my $package_json = $args{package_json} || die 'package_json is required';
    my %specs = _package_json_dependency_map($package_json);
    my $target_root = File::Spec->catdir( $home_root, 'node_modules' );

    for my $module ( sort keys %specs ) {
        my $path = File::Spec->catdir( $target_root, $module );
        next if !-e $path;
        remove_tree($path);
    }

    return 1;
}

sub _installed_modules_satisfy_package_json {
    my (%args) = @_;
    my $home_root = $args{home_root} || die 'home_root is required';
    my $package_json = $args{package_json} || die 'package_json is required';
    my %specs = _package_json_dependency_map($package_json);

    for my $module ( sort keys %specs ) {
        my $installed = _installed_node_module_version(
            home_root => $home_root,
            module    => $module,
        );
        return 0 if !defined $installed;
        return 0 if !_version_satisfies_spec( $installed, $specs{$module} );
    }

    return 1;
}

sub _package_json_dependency_map {
    my ($package_json) = @_;
    open my $fh, '<', $package_json or die "Unable to read $package_json: $!";
    local $/;
    my $content = <$fh>;
    close $fh;

    my $decoded = eval { JSON::PP::decode_json($content) };
    die "Unable to parse $package_json: $@" if !$decoded || $@;

    my %specs;
    for my $section ( qw(dependencies devDependencies optionalDependencies peerDependencies) ) {
        my $entries = $decoded->{$section};
        next if ref($entries) ne 'HASH';
        @specs{ keys %{$entries} } = values %{$entries};
    }

    return %specs;
}

sub _installed_node_module_version {
    my (%args) = @_;
    my $home_root = $args{home_root} || die 'home_root is required';
    my $module = $args{module} || die 'module is required';
    my $package_json = File::Spec->catfile( $home_root, 'node_modules', $module, 'package.json' );
    return if !-f $package_json;
    open my $fh, '<', $package_json or die "Unable to read $package_json: $!";
    local $/;
    my $content = <$fh>;
    close $fh;
    my $decoded = eval { JSON::PP::decode_json($content) };
    die "Unable to parse $package_json: $@" if !$decoded || $@;
    return $decoded->{version};
}

sub _version_satisfies_spec {
    my ( $installed, $spec ) = @_;
    return 0 if !defined $installed || !defined $spec || $installed eq q{} || $spec eq q{};
    return 1 if $spec eq '*' || $spec eq 'latest';
    return $installed eq $spec if $spec !~ /^\^/;

    my $minimum = substr $spec, 1;
    my @installed = _version_parts($installed);
    my @minimum   = _version_parts($minimum);
    return 0 if !@installed || !@minimum;
    return 0 if $installed[0] != $minimum[0];
    return _compare_version_parts( \@installed, \@minimum ) >= 0 ? 1 : 0;
}

sub _version_parts {
    my ($value) = @_;
    return if !defined $value;
    my ($numeric) = $value =~ /\A([0-9]+(?:\.[0-9]+){0,2})/;
    return if !defined $numeric;
    my @parts = split /\./, $numeric;
    push @parts, 0 while @parts < 3;
    return @parts[ 0 .. 2 ];
}

sub _compare_version_parts {
    my ( $left, $right ) = @_;
    for my $idx ( 0 .. 2 ) {
        my $cmp = ( $left->[$idx] || 0 ) <=> ( $right->[$idx] || 0 );
        return $cmp if $cmp != 0;
    }
    return 0;
}

sub _make_path_if_missing {
    my ($path) = @_;
    return 1 if -d $path;
    require File::Path;
    File::Path::make_path($path);
    return 1;
}

sub _node_runtime_stamp_path {
    my (%args) = @_;
    my $home_root = $args{home_root} || die 'home_root is required';
    return File::Spec->catfile( $home_root, '.developer-dashboard', 'cache', 'browser-skill-node-runtime.sha256' );
}

sub _read_node_runtime_stamp {
    my (%args) = @_;
    my $path = _node_runtime_stamp_path(%args);
    return if !-f $path;
    open my $fh, '<', $path or die "Unable to read $path: $!";
    my $value = <$fh>;
    close $fh;
    chomp $value if defined $value;
    return $value;
}

sub _write_node_runtime_stamp {
    my (%args) = @_;
    my $path = _node_runtime_stamp_path(%args);
    my $dir = dirname($path);
    _make_path_if_missing($dir);
    open my $fh, '>', $path or die "Unable to write $path: $!";
    print {$fh} $args{fingerprint}, "\n";
    close $fh;
    return 1;
}

sub _launch_options {
    my (%args) = @_;
    my %launch = (
        headless => $args{headless} ? 1 : 0,
        type     => ( $args{browser} || 'chrome' ) eq 'chromium' ? 'chrome' : ( $args{browser} || 'chrome' ),
    );
    if ( my $path = _default_chromium_bin() ) {
        $launch{executablePath} = $path;
    }
    return %launch;
}

sub _default_chromium_bin {
    return $ENV{CHROMIUM_BIN} if $ENV{CHROMIUM_BIN};
    for my $candidate (qw(chromium chromium-browser google-chrome google-chrome-stable chrome)) {
        my $path = _find_in_path($candidate);
        return $path if $path;
    }
    return;
}

sub _find_in_path {
    my ($command) = @_;
    return if !defined $command || $command eq q{};
    for my $dir ( split /:/, ( $ENV{PATH} || q{} ) ) {
        next if !defined $dir || $dir eq q{};
        my $path = File::Spec->catfile( $dir, $command );
        return $path if -x $path && !-d $path;
    }
    return;
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

sub _run_quiet_command {
    my (@command) = @_;
    open my $stdout_save, '>&', \*STDOUT or die "Unable to save STDOUT: $!";
    open my $stderr_save, '>&', \*STDERR or die "Unable to save STDERR: $!";
    open my $null_fh, '>', File::Spec->devnull() or die "Unable to open devnull: $!";

    open STDOUT, '>&', $null_fh or die "Unable to redirect STDOUT: $!";
    open STDERR, '>&', $null_fh or die "Unable to redirect STDERR: $!";

    my $ok = system(@command) == 0;
    my $exit = $? >> 8;

    open STDOUT, '>&', $stdout_save or die "Unable to restore STDOUT: $!";
    open STDERR, '>&', $stderr_save or die "Unable to restore STDERR: $!";

    die "Command failed: @command" if !$ok;
    return $exit;
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
