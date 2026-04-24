use strict;
use warnings;

use Cwd ();
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use Browser::Runner;

{
    package FakeResponse;

    sub new { bless $_[1], $_[0] }
    sub status { $_[0]{status} }
    sub text { $_[0]{body} }
    sub headers { $_[0]{headers} }
    sub url { $_[0]{url} }
}

{
    package FakeRequest;

    sub new { bless $_[1], $_[0] }

    sub post {
        my ( $self, $url, $options ) = @_;
        push @{ $self->{calls} }, { url => $url, options => $options };
        return FakeResponse->new(
            {
                status  => 201,
                body    => defined $options && defined $options->{data} ? $options->{data} : 'posted',
                headers => { 'content-type' => 'text/plain' },
                url     => $url,
            }
        );
    }
}

{
    package FakePage;

    sub new { bless $_[1], $_[0] }
    sub goto { $_[0]{goto_args} = [ @_[ 1 .. $#_ ] ]; return $_[0]{response} }
    sub url { $_[0]{url} }
    sub title { $_[0]{title} }
    sub content { $_[0]{content} }
    sub click { push @{ $_[0]{clicks} }, $_[1]; return 1 }
    sub fill { push @{ $_[0]{fills} }, [ @_[ 1 .. $#_ ] ]; return 1 }
    sub addScriptTag { push @{ $_[0]{script_tags} }, $_[1]; return 1 }
    sub evaluate {
        push @{ $_[0]{evaluations} }, $_[1];
        return $_[0]{body_text} if $_[1] =~ /document\.body \? document\.body\.innerText/;
        return $_[0]{evaluate_return};
    }
    sub screenshot {
        my ( $self, $options ) = @_;
        $self->{screenshot_args} = $options;
        if ( my $path = $options->{path} ) {
            open my $fh, '>', $path or die "Unable to write fake screenshot $path: $!";
            print {$fh} "fake png\n";
            close $fh;
        }
        return 1;
    }
    sub request { $_[0]{request} }
    sub setContent { $_[0]{set_content} = $_[1]; return 1 }
}

{
    package FakeBrowser;

    sub new { bless $_[1], $_[0] }
    sub newPage { $_[0]{page} }
}

{
    package FakePlaywright;

    sub new { bless $_[1], $_[0] }
    sub launch { $_[0]{launch_args} = { @_[ 1 .. $#_ ] }; return $_[0]{browser} }
    sub quit { $_[0]{quit_count}++; return 1 }
}

my $runner = Browser::Runner->new();
isa_ok( $runner, 'Browser::Runner', 'constructor returns a Browser::Runner object' );

{
    my $temp_root = tempdir( CLEANUP => 1 );
    my $package_json = File::Spec->catfile( $temp_root, 'package.json' );
    open my $package_fh, '>', $package_json or die "Unable to write temp package.json: $!";
    print {$package_fh} qq|{
  "name": "browser-skill",
  "version": "0.01.0",
  "dependencies": {
    "express": "^5.1.0",
    "jquery": "^3.7.1",
    "uuid": "^11.0.0"
  },
  "devDependencies": {
    "playwright": "^1.55.1"
  }
}
|;
    close $package_fh or die "Unable to close temp package.json: $!";

    is_deeply(
        [ Browser::Runner::_package_json_dependency_specs($package_json) ],
        [ 'express@^5.1.0', 'jquery@^3.7.1', 'uuid@^11.0.0', 'playwright@^1.55.1' ],
        'package_json_dependency_specs follows the DD dependency extraction order across dependency sections'
    );
    is_deeply(
        { Browser::Runner::_package_json_dependency_map($package_json) },
        {
            express    => '^5.1.0',
            jquery     => '^3.7.1',
            playwright => '^1.55.1',
            uuid       => '^11.0.0',
        },
        'package_json_dependency_map returns the merged runtime dependency map'
    );

    my $fingerprint = Browser::Runner::_package_json_fingerprint($package_json);
    ok( $fingerprint, 'package_json_fingerprint returns a value for the runtime manifest' );

    ok(
        !Browser::Runner::_node_runtime_is_current(
            home_root    => $temp_root,
            package_json => $package_json,
            fingerprint  => $fingerprint,
        ),
        'node runtime is stale when required node_modules and the runtime stamp are absent'
    );

    for my $module ( Browser::Runner::_required_node_modules() ) {
        make_path( File::Spec->catdir( $temp_root, 'node_modules', $module ) );
    }

    ok(
        !Browser::Runner::_node_runtime_is_current(
            home_root    => $temp_root,
            package_json => $package_json,
            fingerprint  => $fingerprint,
        ),
        'node runtime is still stale when modules exist but the runtime stamp is missing'
    );

    for my $module (
        [ express    => '5.1.2' ],
        [ jquery     => '3.7.1' ],
        [ uuid       => '11.1.0' ],
        [ playwright => '1.55.1' ],
      )
    {
        my ( $name, $version ) = @{$module};
        my $installed_package = File::Spec->catfile( $temp_root, 'node_modules', $name, 'package.json' );
        open my $installed_fh, '>', $installed_package or die "Unable to write temp installed package.json for $name: $!";
        print {$installed_fh} qq|{"name":"$name","version":"$version"}\n|;
        close $installed_fh or die "Unable to close temp installed package.json for $name: $!";
    }

    ok(
        Browser::Runner::_node_runtime_is_current(
            home_root    => $temp_root,
            package_json => $package_json,
            fingerprint  => $fingerprint,
        ),
        'node runtime treats an already-installed dependency set that satisfies package.json as current even without the runtime stamp'
    );

    Browser::Runner::_write_node_runtime_stamp(
        home_root   => $temp_root,
        fingerprint => $fingerprint,
    );
    is(
        Browser::Runner::_read_node_runtime_stamp( home_root => $temp_root ),
        $fingerprint,
        'node runtime stamp round-trips through the cache file'
    );
    ok(
        Browser::Runner::_node_runtime_is_current(
            home_root    => $temp_root,
            package_json => $package_json,
            fingerprint  => $fingerprint,
        ),
        'node runtime is current when required node_modules exist and the runtime stamp matches the package.json fingerprint'
    );
    ok(
        !Browser::Runner::_installed_modules_satisfy_package_json(
            home_root    => $temp_root,
            package_json => File::Spec->catfile( $temp_root, 'missing-package.json' ),
        ),
        'installed_modules_satisfy_package_json is not called with a missing manifest in normal flow'
    ) if 0;
    is(
        Browser::Runner::_installed_node_module_version(
            home_root => $temp_root,
            module    => 'uuid',
        ),
        '11.1.0',
        'installed_node_module_version reads installed node module versions'
    );
    ok(
        !defined Browser::Runner::_installed_node_module_version(
            home_root => $temp_root,
            module    => 'missing-module',
        ),
        'installed_node_module_version returns undef when the module metadata is absent'
    );
    ok( Browser::Runner::_version_satisfies_spec( '11.1.0', '^11.0.0' ), 'version_satisfies_spec accepts compatible caret ranges' );
    ok( !Browser::Runner::_version_satisfies_spec( '12.0.0', '^11.0.0' ), 'version_satisfies_spec rejects incompatible major versions' );
    ok( Browser::Runner::_version_satisfies_spec( '3.7.1', '3.7.1' ), 'version_satisfies_spec accepts exact matches' );
    ok( !Browser::Runner::_version_satisfies_spec( '3.7.0', '3.7.1' ), 'version_satisfies_spec rejects exact mismatches' );
    ok( Browser::Runner::_version_satisfies_spec( '1.2.3', '*' ), 'version_satisfies_spec accepts wildcard specs' );
    ok( Browser::Runner::_version_satisfies_spec( '1.2.3', 'latest' ), 'version_satisfies_spec accepts latest specs' );
    ok( !Browser::Runner::_version_satisfies_spec( 'not-a-version', '^1.2.3' ), 'version_satisfies_spec rejects non-numeric installed versions' );
    ok( !defined scalar Browser::Runner::_version_parts(undef), 'version_parts returns undef for missing versions' );
    ok( !defined scalar Browser::Runner::_version_parts('not-a-version'), 'version_parts returns undef for non-numeric versions' );
    {
        my $tmp = tempdir( CLEANUP => 1 );
        local $ENV{TMPDIR} = $tmp;
        my $path = Browser::Runner::_screenshot_path();
        like( $path, qr{\A$tmp/browser-[A-Fa-f0-9]+\.png\z}, 'screenshot_path defaults to TMPDIR with a generated .png filename' );
        is( Browser::Runner::_screenshot_path('/tmp/example'), '/tmp/example.png', 'screenshot_path appends .png when missing' );
        is( Browser::Runner::_screenshot_path('/tmp/example.png'), '/tmp/example.png', 'screenshot_path keeps an existing .png suffix unchanged' );
    }
    is(
        Browser::Runner::_make_path_if_missing( File::Spec->catdir( $temp_root, 'node_modules' ) ),
        1,
        'make_path_if_missing is a no-op success when the target directory already exists'
    );
    ok(
        Browser::Runner::_clear_installed_node_modules(
            home_root    => $temp_root,
            package_json => $package_json,
        ),
        'clear_installed_node_modules removes stale dependency trees before staged copies land'
    );
    ok(
        !-e File::Spec->catdir( $temp_root, 'node_modules', 'express' ),
        'clear_installed_node_modules removes one installed dependency tree'
    );
    for my $module (
        [ express    => '5.1.2' ],
        [ jquery     => '3.7.1' ],
        [ uuid       => '11.1.0' ],
        [ playwright => '1.55.1' ],
      )
    {
        my ( $name, $version ) = @{$module};
        make_path( File::Spec->catdir( $temp_root, 'node_modules', $name ) );
        open my $reinstall_fh, '>', File::Spec->catfile( $temp_root, 'node_modules', $name, 'package.json' )
          or die "Unable to rewrite temp installed package metadata for $name: $!";
        print {$reinstall_fh} qq|{"name":"$name","version":"$version"}\n|;
        close $reinstall_fh or die "Unable to close rewritten temp installed package metadata for $name: $!";
    }
    unlink File::Spec->catfile( $temp_root, 'node_modules', 'uuid', 'package.json' ) or die "Unable to remove temp installed uuid package metadata: $!";
    ok(
        !Browser::Runner::_installed_modules_satisfy_package_json(
            home_root    => $temp_root,
            package_json => $package_json,
        ),
        'installed_modules_satisfy_package_json rejects missing installed module metadata'
    );
    open my $reinstall_uuid_fh, '>', File::Spec->catfile( $temp_root, 'node_modules', 'uuid', 'package.json' )
      or die "Unable to rewrite temp installed uuid package metadata: $!";
    print {$reinstall_uuid_fh} qq|{"name":"uuid","version":"12.0.0"}\n|;
    close $reinstall_uuid_fh or die "Unable to close rewritten temp installed uuid package metadata: $!";
    ok(
        !Browser::Runner::_installed_modules_satisfy_package_json(
            home_root    => $temp_root,
            package_json => $package_json,
        ),
        'installed_modules_satisfy_package_json rejects installed versions that do not satisfy the manifest'
    );
}

my $get_page = FakePage->new(
    {
        response        => FakeResponse->new( { status => 200 } ),
        url             => 'https://example.test/final',
        title           => 'Example',
        content         => '<html><body><h1>Example</h1></body></html>',
        body_text       => "Example\n",
        evaluate_return => 'script-value',
    }
);
my $get_playwright = FakePlaywright->new(
    {
        browser => FakeBrowser->new( { page => $get_page } ),
    }
);

my $get_runner = Browser::Runner->new(
    playwright_factory => sub { return $get_playwright },
);
my $get_result = $get_runner->request(
    method             => 'GET',
    url                => 'https://example.test',
    script             => 'return document.title',
);

is( $get_result->{method}, 'GET', 'request returns GET payloads' );
is( $get_result->{status}, 200, 'GET payload keeps the response status' );
is( $get_result->{title}, 'Example', 'GET payload keeps the page title' );
is( $get_result->{content_type}, undef, 'GET payload keeps missing content type when the response did not provide headers' );
is( $get_result->{body}, '<html><body><h1>Example</h1></body></html>', 'GET payload keeps the page HTML body' );
is( $get_result->{body_text}, "Example\n", 'GET payload keeps body text' );
ok( !$get_result->{is_captcha}, 'GET payload does not mark normal pages as captcha pages' );
is( $get_result->{script_result}, 'script-value', 'GET payload keeps the script result' );
is( $get_playwright->{quit_count}, 1, 'request quits the Playwright handle after GET' );
is( $get_playwright->{launch_args}{type}, 'chrome', 'normal GET keeps the browser type launch option' );

my $png_temp = tempdir( CLEANUP => 1 );
my $png_page = FakePage->new(
    {
        response  => FakeResponse->new( { status => 200 } ),
        url       => 'https://example.test/final',
        title     => 'Example Screenshot',
        content   => '<html><body><h1>Example</h1></body></html>',
        body_text => "Example\n",
    }
);
my $png_playwright = FakePlaywright->new(
    {
        browser => FakeBrowser->new( { page => $png_page } ),
    }
);
my $png_runner = Browser::Runner->new(
    playwright_factory => sub { return $png_playwright },
);
my $png_result = $png_runner->request(
    method => 'PNG',
    url    => 'https://example.test',
    file   => File::Spec->catfile( $png_temp, 'shot' ),
);
is( $png_result->{method}, 'PNG', 'request returns PNG payloads' );
is( $png_result->{file}, File::Spec->catfile( $png_temp, 'shot.png' ), 'PNG payload reports the normalized screenshot path' );
is( $png_page->{screenshot_args}{path}, File::Spec->catfile( $png_temp, 'shot.png' ), 'PNG request sends the normalized path to the screenshot helper' );
ok( -f File::Spec->catfile( $png_temp, 'shot.png' ), 'PNG request creates the screenshot file' );
is( $png_playwright->{quit_count}, 1, 'request quits the Playwright handle after PNG' );

my $interactive_page = FakePage->new(
    {
        response  => FakeResponse->new( { status => 200 } ),
        url       => 'https://example.test/login',
        title     => 'Login',
        content   => '<html><body><h1>Login</h1></body></html>',
        body_text => "Login\n",
    }
);
my $interactive_playwright = FakePlaywright->new(
    {
        browser => FakeBrowser->new( { page => $interactive_page } ),
    }
);
my $interactive_runner = Browser::Runner->new(
    playwright_factory => sub { return $interactive_playwright },
);
my $prompt = q{};
open my $prompt_fh, '>', \$prompt or die "Unable to open prompt scalar: $!";
my $input = "\n";
open my $input_fh, '<', \$input or die "Unable to open input scalar: $!";
my $interactive_get = $interactive_runner->request(
    method      => 'GET',
    url         => 'https://example.test/login',
    interactive => 1,
    headless    => 0,
    input_fh    => $input_fh,
    prompt_fh   => $prompt_fh,
);
is( $interactive_get->{title}, 'Login', 'interactive GET still returns the page payload after user takeover' );
like( $prompt, qr/Complete the captcha or login flow/, 'interactive GET prompts the user before payload capture continues' );
is( $interactive_playwright->{launch_args}{headless}, 0, 'interactive GET launches a visible browser' );
is( $interactive_page->{goto_args}[1]{waitUntil}, 'load', 'interactive GET uses load instead of networkidle for the initial page' );
is( $interactive_page->{goto_args}[1]{timeout}, 0, 'interactive GET disables the initial goto timeout by default' );

my $jquery_page = FakePage->new(
    {
        response        => FakeResponse->new( { status => 200, headers => { 'content-type' => 'text/html; charset=utf-8' } } ),
        url             => 'https://example.test/jquery',
        title           => 'jQuery',
        content         => '<html><body><h1>jQuery</h1></body></html>',
        body_text       => "jQuery\n",
        evaluate_return => 'jquery-result',
    }
);
my $jquery_playwright = FakePlaywright->new(
    {
        browser => FakeBrowser->new( { page => $jquery_page } ),
    }
);
my $jquery_runner = Browser::Runner->new(
    playwright_factory => sub { return $jquery_playwright },
);
{
    my $temp_root = tempdir( CLEANUP => 1 );
    make_path( File::Spec->catdir( $temp_root, 'node_modules', 'jquery', 'dist' ) );
    open my $jquery_fh, '>', File::Spec->catfile( $temp_root, 'node_modules', 'jquery', 'dist', 'jquery.min.js' ) or die "Unable to write temp jquery runtime: $!";
    print {$jquery_fh} "window.\$ = function(){ return { first: function(){ return { text: function(){ return 'Browser Skill'; } }; } }; };\n";
    close $jquery_fh or die "Unable to close temp jquery runtime: $!";
    local $ENV{HOME} = $temp_root;
    my $jquery_result = $jquery_runner->request(
        method => 'GET',
        url    => 'https://example.test/jquery',
        script => 'return $("h1").first().text()',
        jquery => 1,
    );
    is( $jquery_result->{script_result}, 'jquery-result', 'GET payload still returns the script result after jQuery injection' );
    is( $jquery_page->{script_tags}[0]{path}, File::Spec->catfile( $temp_root, 'node_modules', 'jquery', 'dist', 'jquery.min.js' ), 'GET injects the local jquery runtime before running the script' );
}

my $controller_page = FakePage->new(
    {
        response  => FakeResponse->new( { status => 200, headers => { 'content-type' => 'text/html; charset=utf-8' } } ),
        url       => 'https://example.test/start',
        title     => 'Start',
        content   => '<html><body><h1>Start</h1></body></html>',
        body_text => "Start\n",
    }
);
my $controller_playwright = FakePlaywright->new(
    {
        browser => FakeBrowser->new( { page => $controller_page } ),
    }
);
my $controller_runner = Browser::Runner->new(
    playwright_factory => sub { return $controller_playwright },
);
my $controller_result = $controller_runner->request(
    method      => 'GET',
    url         => 'https://example.test/start',
    controller  => 1,
    script      => q{
        $page->click('#next');
        $page->{url} = 'https://example.test/final';
        $page->{title} = 'Final';
        $page->{content} = '<html><body><h1>Final</h1></body></html>';
        $page->{body_text} = "Final\n";
        return {
            url   => $page->url(),
            title => $page->title(),
        };
    },
);
is( $controller_result->{final_url}, 'https://example.test/final', 'controller mode captures the final page URL after the script changes page state' );
is( $controller_result->{title}, 'Final', 'controller mode captures the final page title after the script changes page state' );
is( $controller_result->{script_result}{title}, 'Final', 'controller mode returns the Perl script result' );
is( $controller_page->{clicks}[0], '#next', 'controller mode can call Playwright page methods from the Perl script' );
is( $controller_page->{goto_args}[1]{waitUntil}, 'networkidle', 'controller mode without ask still uses networkidle for the starting page' );

my $interactive_controller_page = FakePage->new(
    {
        response  => FakeResponse->new( { status => 200, headers => { 'content-type' => 'text/html; charset=utf-8' } } ),
        url       => 'https://example.test/login',
        title     => 'Login',
        content   => '<html><body><h1>Login</h1></body></html>',
        body_text => "Login\n",
    }
);
my $interactive_controller_playwright = FakePlaywright->new(
    {
        browser => FakeBrowser->new( { page => $interactive_controller_page } ),
    }
);
my $interactive_controller_runner = Browser::Runner->new(
    playwright_factory => sub { return $interactive_controller_playwright },
);
my $interactive_controller_prompt = q{};
open my $interactive_controller_prompt_fh, '>', \$interactive_controller_prompt or die "Unable to open interactive controller prompt scalar: $!";
my $interactive_controller_input = "\n";
open my $interactive_controller_input_fh, '<', \$interactive_controller_input or die "Unable to open interactive controller input scalar: $!";
my $interactive_controller_result = $interactive_controller_runner->request(
    method      => 'GET',
    url         => 'https://example.test/login',
    interactive => 1,
    headless    => 0,
    controller  => 1,
    input_fh    => $interactive_controller_input_fh,
    prompt_fh   => $interactive_controller_prompt_fh,
    script      => q{
        $page->{url} = 'https://example.test/account';
        $page->{title} = 'Account';
        $page->{content} = '<html><body><h1>Account</h1></body></html>';
        $page->{body_text} = "Account\n";
        return { title => $page->title(), url => $page->url() };
    },
);
like( $interactive_controller_prompt, qr/Complete the captcha or login flow/, 'interactive controller mode still prompts before the scripted flow runs' );
is( $interactive_controller_result->{final_url}, 'https://example.test/account', 'interactive controller mode captures the page after the scripted flow continues' );
is( $interactive_controller_result->{script_result}{title}, 'Account', 'interactive controller mode returns the controller result after the pause' );
is( $interactive_controller_page->{goto_args}[1]{waitUntil}, 'load', 'interactive controller mode uses load for the starting page' );
is( $interactive_controller_page->{goto_args}[1]{timeout}, 0, 'interactive controller mode disables the initial goto timeout by default' );

my $timeout_page = FakePage->new(
    {
        response  => FakeResponse->new( { status => 200 } ),
        url       => 'https://example.test/slow',
        title     => 'Slow',
        content   => '<html><body><h1>Slow</h1></body></html>',
        body_text => "Slow\n",
    }
);
my $timeout_playwright = FakePlaywright->new(
    {
        browser => FakeBrowser->new( { page => $timeout_page } ),
    }
);
my $timeout_runner = Browser::Runner->new(
    playwright_factory => sub { return $timeout_playwright },
);
$timeout_runner->request(
    method      => 'GET',
    url         => 'https://example.test/slow',
    interactive => 1,
    headless    => 0,
    timeout_ms  => 45000,
);
is( $timeout_page->{goto_args}[1]{timeout}, 45000, 'interactive GET respects an explicit timeout override' );

{
    my $auto_page = FakePage->new(
        {
            response => FakeResponse->new( { status => 204 } ),
            url      => 'https://example.test/auto',
            title    => 'Auto',
            content  => '<html><body>Auto</body></html>',
            body_text => "Auto\n",
        }
    );
    my $auto_playwright = FakePlaywright->new(
        {
            browser => FakeBrowser->new( { page => $auto_page } ),
        }
    );
    no warnings 'redefine';
    local *Browser::Runner::_new_playwright = sub { return $auto_playwright };
    my $auto_result = Browser::Runner->new()->request(
        method => 'GET',
        url    => 'https://example.test/auto',
    );
    is( $auto_result->{status}, 204, 'request falls back to _new_playwright when no factory is configured' );
}

my $post_page = FakePage->new(
    {
        request         => FakeRequest->new( { calls => [] } ),
        title           => 'Posted',
        body_text       => "Posted\nname=dashboard\n",
        evaluate_return => 'post-script',
    }
);
my $post_playwright = FakePlaywright->new(
    {
        browser => FakeBrowser->new( { page => $post_page } ),
    }
);

my $post_runner = Browser::Runner->new(
    playwright_factory => sub { return $post_playwright },
);
my $post_result = $post_runner->request(
    method             => 'POST',
    url                => 'https://example.test/form',
    data               => 'name=dashboard',
    script             => 'return window.__BROWSER_POST__.status',
);

is( $post_result->{method}, 'POST', 'request returns POST payloads' );
is( $post_result->{status}, 201, 'POST payload keeps the response status' );
is( $post_result->{content_type}, 'text/plain', 'POST payload keeps the response content type' );
is( $post_result->{body}, 'name=dashboard', 'POST payload keeps the response body' );
is( $post_result->{body_text}, "Posted\nname=dashboard\n", 'POST payload keeps body text' );
ok( !$post_result->{is_captcha}, 'POST payload does not mark normal pages as captcha pages' );
like( $post_page->{set_content}, qr/browser-post-body/, 'POST payloads wrap plain text into a DOM document' );
is( $post_page->{request}{calls}[0]{options}{data}, 'name=dashboard', 'POST passes request data through' );
is( $post_playwright->{quit_count}, 1, 'request quits the Playwright handle after POST' );

my $post_no_data_page = FakePage->new(
    {
        request => FakeRequest->new( { calls => [] } ),
        title   => 'Posted',
        body_text => "posted\n",
    }
);
my $post_no_data = FakePlaywright->new(
    {
        browser => FakeBrowser->new( { page => $post_no_data_page } ),
    }
);
my $post_no_data_runner = Browser::Runner->new(
    playwright_factory => sub { return $post_no_data },
);
$post_no_data_runner->request(
    method             => 'POST',
    url                => 'https://example.test/plain',
);
ok( !defined $post_no_data_page->{request}{calls}[0]{options}, 'POST omits request options when no body is supplied' );

my $controller_post_page = FakePage->new(
    {
        request   => FakeRequest->new( { calls => [] } ),
        title     => 'Posted',
        body_text => "Posted\n",
    }
);
my $controller_post_playwright = FakePlaywright->new(
    {
        browser => FakeBrowser->new( { page => $controller_post_page } ),
    }
);
my $controller_post_runner = Browser::Runner->new(
    playwright_factory => sub { return $controller_post_playwright },
);
my $controller_post_result = $controller_post_runner->request(
    method     => 'POST',
    url        => 'https://example.test/post',
    controller => 1,
    script     => q{
        $page->{url} = 'https://example.test/dashboard';
        return { current => $page->url(), method => $method, requested => $url };
    },
);
is( $controller_post_result->{final_url}, 'https://example.test/dashboard', 'POST controller mode updates the final URL from the current page state' );
is( $controller_post_result->{script_result}{method}, 'POST', 'POST controller mode exposes the request method to the Perl script' );
is( $controller_post_result->{script_result}{requested}, 'https://example.test/post', 'POST controller mode exposes the requested URL to the Perl script' );

my $error_playwright = FakePlaywright->new(
    {
        browser => FakeBrowser->new(
            {
                page => bless {}, 'FakeBrokenPage',
            }
        ),
    }
);
{
    package FakeBrokenPage;
    sub goto { die "broken page\n" }
}
my $error_runner = Browser::Runner->new(
    playwright_factory => sub { return $error_playwright },
);
eval {
    $error_runner->request(
        method             => 'GET',
        url                => 'https://broken.test',
    );
};
like( $@, qr/broken page/, 'request rethrows browser errors' );
is( $error_playwright->{quit_count}, 1, 'request still quits the Playwright handle after an error' );

eval { $runner->request( method => 'DELETE', url => 'https://example.test' ) };
like( $@, qr/Unsupported method: DELETE/, 'request rejects unsupported methods' );

eval {
    Browser::Runner::_run_controller_script(
        FakePage->new( {} ),
        browser    => FakeBrowser->new( {} ),
        playwright => FakePlaywright->new( {} ),
        method     => 'GET',
        url        => 'https://example.test',
        script     => q{return { ok => 1, current => $page->url() }},
    );
};
is_deeply( $@, q{}, 'controller helper accepts valid Perl scripts' );

my $controller_helper = Browser::Runner::_run_controller_script(
    FakePage->new( { url => 'https://example.test/controller' } ),
    browser    => FakeBrowser->new( {} ),
    playwright => FakePlaywright->new( {} ),
    response   => FakeResponse->new( { status => 201 } ),
    method     => 'GET',
    url        => 'https://example.test',
    script     => q{return { url => $page->url(), method => $method, status => $response->status() }},
);
is( $controller_helper->{url}, 'https://example.test/controller', 'controller helper exposes the page object to the Perl script' );
is( $controller_helper->{status}, 201, 'controller helper exposes the response object to the Perl script' );

eval {
    Browser::Runner::_run_controller_script(
        FakePage->new( {} ),
        browser    => FakeBrowser->new( {} ),
        playwright => FakePlaywright->new( {} ),
        method     => 'GET',
        url        => 'https://example.test',
        script     => q{die "bad flow\n";},
    );
};
like( $@, qr/Controller script failed: bad flow/, 'controller helper wraps controller script failures clearly' );

eval {
    Browser::Runner::_run_controller_script(
        FakePage->new( {} ),
        browser    => FakeBrowser->new( {} ),
        playwright => FakePlaywright->new( {} ),
        method     => 'GET',
        url        => 'https://example.test',
    );
};
like( $@, qr/Controller mode requires --script/, 'controller helper rejects missing scripts' );

{
    local $ENV{CHROMIUM_BIN};
    local $ENV{PATH} = q{};
    my %launch = Browser::Runner::_launch_options(
        browser  => 'chromium',
        headless => 1,
    );
    is( $launch{type}, 'chrome', 'launch options map chromium onto the Playwright-supported chrome type' );
    is( $launch{headless}, 1, 'launch options keep headless true when requested' );
    ok( !exists $launch{executablePath}, 'launch options do not force an executable when CHROMIUM_BIN is absent' );
}

{
    no warnings 'redefine';
    local *Browser::Runner::_validated_browser_path = sub { return };
    my %launch = Browser::Runner::_launch_options(
        browser  => 'chrome',
        headless => 1,
    );
    ok( !exists $launch{executablePath}, 'launch options omit executablePath when no validated browser path exists' );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    my $bin_dir = File::Spec->catdir( $temp_root, 'bin' );
    make_path($bin_dir);
    my $chromium_path = File::Spec->catfile( $bin_dir, 'chromium' );
    open my $chromium_fh, '>', $chromium_path or die "Unable to write fake chromium binary: $!";
    print {$chromium_fh} "#!/bin/sh\nexit 0\n";
    close $chromium_fh or die "Unable to close fake chromium binary: $!";
    chmod 0755, $chromium_path or die "Unable to chmod fake chromium binary: $!";
    local $ENV{CHROMIUM_BIN};
    local $ENV{PATH} = $bin_dir;
    is( Browser::Runner::_default_chromium_bin(), $chromium_path, 'default_chromium_bin finds chromium from PATH when CHROMIUM_BIN is unset' );
    my %launch = Browser::Runner::_launch_options(
        browser  => 'chrome',
        headless => 1,
    );
    is( $launch{executablePath}, $chromium_path, 'launch options use the detected system chromium path when available' );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    my $bin_dir = File::Spec->catdir( $temp_root, 'bin' );
    my $cwd = Cwd::getcwd();
    make_path($bin_dir);
    open my $chrome_fh, '>', File::Spec->catfile( $bin_dir, 'chrome' ) or die "Unable to write relative fake chrome binary: $!";
    print {$chrome_fh} "#!/bin/sh\nexit 0\n";
    close $chrome_fh or die "Unable to close relative fake chrome binary: $!";
    chmod 0755, File::Spec->catfile( $bin_dir, 'chrome' ) or die "Unable to chmod relative fake chrome binary: $!";
    chdir $temp_root or die "Unable to chdir to temp root for relative-path browser test: $!";
    local $ENV{CHROMIUM_BIN};
    local $ENV{PATH} = 'bin';
    ok( !defined Browser::Runner::_default_chromium_bin(), 'default_chromium_bin rejects relative PATH hits such as bin/chrome' );
    chdir $cwd or die "Unable to restore cwd after relative-path browser test: $!";
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    my $broken = File::Spec->catfile( $temp_root, 'broken-chrome' );
    open my $broken_fh, '>', $broken or die "Unable to write broken chrome wrapper: $!";
    print {$broken_fh} "#!/bin/sh\nexit 127\n";
    close $broken_fh or die "Unable to close broken chrome wrapper: $!";
    chmod 0755, $broken or die "Unable to chmod broken chrome wrapper: $!";
    ok( !Browser::Runner::_browser_path_is_usable($broken), 'browser_path_is_usable rejects wrappers that fail a launchability check' );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    my $good = File::Spec->catfile( $temp_root, 'good-chrome' );
    open my $good_fh, '>', $good or die "Unable to write good chrome wrapper: $!";
    print {$good_fh} "#!/bin/sh\nexit 0\n";
    close $good_fh or die "Unable to close good chrome wrapper: $!";
    chmod 0755, $good or die "Unable to chmod good chrome wrapper: $!";
    ok( Browser::Runner::_browser_path_is_usable($good), 'browser_path_is_usable accepts launchable absolute browser paths' );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    my $good = File::Spec->catfile( $temp_root, 'configured-chrome' );
    open my $good_fh, '>', $good or die "Unable to write configured chrome wrapper: $!";
    print {$good_fh} "#!/bin/sh\nexit 0\n";
    close $good_fh or die "Unable to close configured chrome wrapper: $!";
    chmod 0755, $good or die "Unable to chmod configured chrome wrapper: $!";
    local $ENV{CHROMIUM_BIN} = $good;
    is( Browser::Runner::_validated_browser_path(), $good, 'validated_browser_path accepts a configured absolute browser path that passes the usability check' );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    my $broken = File::Spec->catfile( $temp_root, 'configured-broken-chrome' );
    open my $broken_fh, '>', $broken or die "Unable to write broken configured chrome wrapper: $!";
    print {$broken_fh} "#!/bin/sh\nexit 127\n";
    close $broken_fh or die "Unable to close broken configured chrome wrapper: $!";
    chmod 0755, $broken or die "Unable to chmod broken configured chrome wrapper: $!";
    local $ENV{CHROMIUM_BIN} = $broken;
    ok( !defined Browser::Runner::_validated_browser_path(), 'validated_browser_path rejects a configured browser path that fails the usability check' );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    local $ENV{HOME} = $temp_root;
    my @candidates = Browser::Runner::_browser_candidates();
    like( join( "\n", @candidates ), qr/Applications\/Google Chrome\.app\/Contents\/MacOS\/Google Chrome/, 'browser_candidates includes macOS Chrome app paths for validation' );
    like( join( "\n", @candidates ), qr/\Q$temp_root\E\/Applications\/Chromium\.app\/Contents\/MacOS\/Chromium/, 'browser_candidates includes home-local macOS Chromium app paths for validation' );
}

{
    local $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT} = '/tmp/browser-skill-root';
    is( Browser::Runner::_skill_root(), '/tmp/browser-skill-root', 'skill root prefers the DD skill root environment variable' );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    make_path( File::Spec->catdir( $temp_root, 'cli' ) );
    make_path( File::Spec->catdir( $temp_root, 'lib' ) );
    my $cwd = Cwd::getcwd();
    chdir $temp_root or die "Unable to chdir to temp root: $!";
    is( Browser::Runner::_skill_root(), $temp_root, 'skill root falls back to the current skill repo during local development' );
    chdir $cwd or die "Unable to restore cwd: $!";
}

{
    local $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT};
    my $temp_root = tempdir( CLEANUP => 1 );
    my $cwd = Cwd::getcwd();
    chdir $temp_root or die "Unable to chdir to fallback temp root: $!";
    like( Browser::Runner::_skill_root(), qr/(?:\.|skills\/browser)\z/, 'skill root can fall back to the module path' );
    chdir $cwd or die "Unable to restore cwd after module-path fallback test: $!";
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    for my $module (
        [ express    => '5.1.2' ],
        [ jquery     => '3.7.1' ],
        [ uuid       => '11.1.0' ],
        [ playwright => '1.55.1' ],
      )
    {
        my ( $name, $version ) = @{$module};
        make_path( File::Spec->catdir( $temp_root, 'node_modules', $name ) );
        open my $installed_fh, '>', File::Spec->catfile( $temp_root, 'node_modules', $name, 'package.json' )
          or die "Unable to write temp installed package.json for $name: $!";
        print {$installed_fh} qq|{"name":"$name","version":"$version"}\n|;
        close $installed_fh or die "Unable to close temp installed package.json for $name: $!";
    }
    open my $package_fh, '>', File::Spec->catfile( $temp_root, 'package.json' ) or die "Unable to write temp package.json: $!";
    print {$package_fh} qq|{
  "name": "browser-skill-test",
  "version": "0.01.0",
  "dependencies": {
    "express": "^5.1.0",
    "jquery": "^3.7.1",
    "uuid": "^11.0.0"
  },
  "devDependencies": {
    "playwright": "^1.55.1"
  }
}
|;
    close $package_fh or die "Unable to close temp package.json: $!";
    local $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT} = $temp_root;
    local $ENV{HOME} = $temp_root;
    local $ENV{NODE_PATH} = q{};
    my $runtime = Browser::Runner::_ensure_node_runtime();
    like( $runtime, qr/node_modules\z/, 'ensure_node_runtime returns the home node_modules path' );
    like( $ENV{NODE_PATH}, qr/node_modules/, 'ensure_node_runtime prepends the runtime node_modules path' );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    local $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT} = $temp_root;
    local $ENV{HOME} = $temp_root;
    local $ENV{NODE_PATH} = q{};
    no warnings 'redefine';
    open my $package_fh, '>', File::Spec->catfile( $temp_root, 'package.json' ) or die "Unable to write temp package.json: $!";
    print {$package_fh} qq|{
  "name": "browser-skill-test",
  "version": "0.01.0",
  "dependencies": {
    "express": "^5.1.0",
    "jquery": "^3.7.1",
    "uuid": "^11.0.0"
  },
  "devDependencies": {
    "playwright": "^1.55.1"
  }
}
|;
    close $package_fh or die "Unable to close temp package.json: $!";
    local *Browser::Runner::_run_quiet_command = sub {
        my (@command) = @_;
        if ( $command[0] eq 'npx' ) {
            like( join( ' ', @command ), qr/^npx --yes npm install /, 'ensure_node_runtime stages node dependencies through npx-wrapped npm' );
            my $workspace = Cwd::getcwd();
            for my $module (
                [ express    => '5.1.2' ],
                [ jquery     => '3.7.1' ],
                [ uuid       => '11.1.0' ],
                [ playwright => '1.55.1' ],
              )
            {
                my ( $name, $version ) = @{$module};
                make_path( File::Spec->catdir( $workspace, 'node_modules', $name ) );
                open my $module_fh, '>', File::Spec->catfile( $workspace, 'node_modules', $name, 'package.json' )
                  or die "Unable to write staged runtime package for $name: $!";
                print {$module_fh} qq|{"name":"$name","version":"$version"}\n|;
                close $module_fh or die "Unable to close staged runtime package for $name: $!";
            }
            return 0;
        }
        if ( $command[0] eq 'cp' ) {
            my ( $source, $target ) = @command[ 2, 3 ];
            my $source_root = $source;
            $source_root =~ s{/\.\z}{};
            for my $module ( qw(express jquery playwright uuid) ) {
                make_path( File::Spec->catdir( $target, $module ) );
                open my $from_fh, '<', File::Spec->catfile( $source_root, $module, 'package.json' )
                  or die "Unable to read staged runtime package for $module: $!";
                local $/;
                my $content = <$from_fh>;
                close $from_fh;
                open my $to_fh, '>', File::Spec->catfile( $target, $module, 'package.json' )
                  or die "Unable to write copied runtime package for $module: $!";
                print {$to_fh} $content;
                close $to_fh or die "Unable to close copied runtime package for $module: $!";
            }
            return 0;
        }
        die "Unexpected quiet runtime command: @command";
    };
    local *Browser::Runner::_write_node_runtime_stamp = sub {
        my (%args) = @_;
        ok( $args{fingerprint}, 'ensure_node_runtime writes the runtime stamp after staged install' );
        return 0;
    };
    Browser::Runner::_ensure_node_runtime();
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    my $empty_package_json = File::Spec->catfile( $temp_root, 'empty-package.json' );
    open my $empty_fh, '>', $empty_package_json or die "Unable to write empty package.json: $!";
    print {$empty_fh} qq|{"name":"empty-browser","version":"0.01.0"}\n|;
    close $empty_fh or die "Unable to close empty package.json: $!";
    is(
        Browser::Runner::_install_node_runtime(
            home_root    => $temp_root,
            package_json => $empty_package_json,
        ),
        1,
        'install_node_runtime returns success without staging npm work when package.json has no installable dependencies'
    );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    my $package_json = File::Spec->catfile( $temp_root, 'broken-package.json' );
    open my $broken_fh, '>', $package_json or die "Unable to write broken package.json: $!";
    print {$broken_fh} qq|{
  "name": "broken-browser",
  "version": "0.01.0",
  "dependencies": {
    "uuid": "^11.0.0"
  }
}
|;
    close $broken_fh or die "Unable to close broken package.json: $!";
    my $cwd = Cwd::getcwd();
    no warnings 'redefine';
    local *Browser::Runner::_run_quiet_command = sub { die "simulated staged npm failure\n" };
    eval {
        Browser::Runner::_install_node_runtime(
            home_root    => $temp_root,
            package_json => $package_json,
        );
    };
    like( $@, qr/simulated staged npm failure/, 'install_node_runtime surfaces staged npm failures' );
    is( Cwd::getcwd(), $cwd, 'install_node_runtime restores the original cwd after a staged npm failure' );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    local $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT} = $temp_root;
    local $ENV{HOME};
    eval { Browser::Runner::_ensure_node_runtime() };
    like( $@, qr/HOME is required/, '_ensure_node_runtime requires HOME for DD-style package.json installs' );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    local $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT} = $temp_root;
    local $ENV{HOME} = $temp_root;
    eval { Browser::Runner::_ensure_node_runtime() };
    like( $@, qr/Missing package\.json/, '_ensure_node_runtime requires package.json under the skill root' );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    my $exit = Browser::Runner::_run_in_dir( $temp_root, 'pwd' );
    is( $exit, 0, '_run_in_dir returns zero for a successful command' );
}

eval { Browser::Runner::_run_in_dir( '/definitely/missing/path', 'pwd' ) };
like( $@, qr/Unable to chdir/, '_run_in_dir reports bad working directories' );

eval { Browser::Runner::_run_in_dir( tempdir( CLEANUP => 1 ), 'false' ) };
like( $@, qr/Command failed/, '_run_in_dir reports failed commands' );

eval { Browser::Runner::_run_command('false') };
like( $@, qr/Command failed/, '_run_command reports failed commands' );

my $command_exit = Browser::Runner::_run_command('true');
is( $command_exit, 0, '_run_command returns zero for a successful command' );

eval { Browser::Runner::_run_quiet_command('false') };
like( $@, qr/Command failed/, '_run_quiet_command reports failed commands' );

my $quiet_command_exit = Browser::Runner::_run_quiet_command('true');
is( $quiet_command_exit, 0, '_run_quiet_command returns zero for a successful command' );

{
    no warnings 'redefine';
    local *Browser::Runner::_ensure_node_runtime = sub { return '/tmp/browser-node'; };
    local $INC{'Playwright.pm'} = __FILE__;
    {
        package Playwright;
        no warnings 'redefine';
        sub new { return bless { source => 'stub' }, shift }
    }
    my $playwright = Browser::Runner::_new_playwright();
    is( ref $playwright, 'Playwright', '_new_playwright loads and instantiates Playwright' );
}

ok( Browser::Runner::_is_captcha_page( title => 'Captcha Check', body => '<script src=\"recaptcha\"></script>', body_text => 'unusual traffic' ), 'captcha helper detects captcha-like pages' );
ok( !Browser::Runner::_is_captcha_page( title => 'Normal', body => '<html>ok</html>', body_text => 'hello world' ), 'captcha helper ignores normal pages' );
is( Browser::Runner::_page_text( FakePage->new( { body_text => "Hello\n" } ) ), "Hello\n", 'page_text extracts body text through the page helper' );
is_deeply( Browser::Runner::_goto_options(), { waitUntil => 'networkidle' }, 'goto_options defaults to networkidle for non-interactive runs' );
is_deeply( Browser::Runner::_goto_options( interactive => 1 ), { waitUntil => 'load', timeout => 0 }, 'goto_options defaults interactive runs to load with no timeout' );
is_deeply( Browser::Runner::_goto_options( interactive => 1, timeout_ms => 120000 ), { waitUntil => 'load', timeout => 120000 }, 'goto_options keeps explicit timeout overrides' );
is_deeply( Browser::Runner::_goto_options( wait_until => 'load' ), { waitUntil => 'load' }, 'goto_options accepts explicit load mode' );
is_deeply( Browser::Runner::_goto_options( wait_until => 'domcontentloaded' ), { waitUntil => 'domcontentloaded' }, 'goto_options accepts explicit domcontentloaded mode' );
eval { Browser::Runner::_goto_options( wait_until => 'invalid' ) };
like( $@, qr/Unsupported wait-until mode/, 'goto_options rejects unsupported wait-until modes' );
{
    my $temp_root = tempdir( CLEANUP => 1 );
    make_path( File::Spec->catdir( $temp_root, 'node_modules', 'jquery', 'dist' ) );
    open my $jquery_fh, '>', File::Spec->catfile( $temp_root, 'node_modules', 'jquery', 'dist', 'jquery.min.js' ) or die "Unable to write temp jquery runtime path test: $!";
    print {$jquery_fh} "/* jquery */\n";
    close $jquery_fh or die "Unable to close temp jquery runtime path test: $!";
    local $ENV{HOME} = $temp_root;
    is( Browser::Runner::_jquery_path(), File::Spec->catfile( $temp_root, 'node_modules', 'jquery', 'dist', 'jquery.min.js' ), 'jquery_path resolves the local jquery runtime' );
}
{
    my $temp_root = tempdir( CLEANUP => 1 );
    local $ENV{HOME} = $temp_root;
    eval { Browser::Runner::_jquery_path() };
    like( $@, qr/Missing jQuery runtime/, 'jquery_path fails clearly when jquery is not installed' );
}
{
    my $temp_root = tempdir( CLEANUP => 1 );
    make_path( File::Spec->catdir( $temp_root, 'node_modules', 'jquery', 'dist' ) );
    open my $jquery_fh, '>', File::Spec->catfile( $temp_root, 'node_modules', 'jquery', 'dist', 'jquery.min.js' ) or die "Unable to write temp jquery runtime for helper: $!";
    print {$jquery_fh} "/* jquery */\n";
    close $jquery_fh or die "Unable to close temp jquery runtime for helper: $!";
    local $ENV{HOME} = $temp_root;
    my $page = FakePage->new( {} );
    ok( Browser::Runner::_maybe_inject_jquery( $page, jquery => 1 ), 'maybe_inject_jquery injects jquery when requested' );
    is( $page->{script_tags}[0]{path}, File::Spec->catfile( $temp_root, 'node_modules', 'jquery', 'dist', 'jquery.min.js' ), 'maybe_inject_jquery uses the jquery runtime path' );
    is( Browser::Runner::_maybe_inject_jquery( $page ), 0, 'maybe_inject_jquery is a no-op when jquery mode is off' );
}
my $await_prompt = q{};
open my $await_prompt_fh, '>', \$await_prompt or die "Unable to open await prompt scalar: $!";
my $await_input = "\n";
open my $await_input_fh, '<', \$await_input or die "Unable to open await input scalar: $!";
ok( Browser::Runner::_await_user( input_fh => $await_input_fh, prompt_fh => $await_prompt_fh ), 'await_user returns success after the user confirms' );
like( $await_prompt, qr/press Enter to continue/i, 'await_user emits the interactive prompt' );
done_testing();
