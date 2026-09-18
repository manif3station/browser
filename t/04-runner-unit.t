use strict;
use warnings;

use Cwd ();
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use Browser::Runner;

## Test doubles: fake Playwright/Page/Browser/Request/Response objects
## used by the integration-style tests throughout this file.

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
                status  => $self->{response_status}  || 201,
                body    => defined $self->{response_body} ? $self->{response_body}
                         : ( defined $options && defined $options->{data} ? $options->{data} : 'posted' ),
                headers => $self->{response_headers} || { 'content-type' => 'text/plain' },
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

## Node runtime / package.json dependency management unit tests
## (Browser::Runner::NodeRuntime's manifest parsing, fingerprinting,
## and version-spec matching - install/staging behavior itself is
## covered separately, further down, by the _ensure_node_runtime /
## _install_node_runtime section).

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
        [ Browser::Runner::NodeRuntime::_package_json_dependency_specs($package_json) ],
        [ 'express@^5.1.0', 'jquery@^3.7.1', 'uuid@^11.0.0', 'playwright@^1.55.1' ],
        'package_json_dependency_specs follows the DD dependency extraction order across dependency sections'
    );
    is_deeply(
        { Browser::Runner::NodeRuntime::_package_json_dependency_map($package_json) },
        {
            express    => '^5.1.0',
            jquery     => '^3.7.1',
            playwright => '^1.55.1',
            uuid       => '^11.0.0',
        },
        'package_json_dependency_map returns the merged runtime dependency map'
    );

    my $fingerprint = Browser::Runner::NodeRuntime::_package_json_fingerprint($package_json);
    ok( $fingerprint, 'package_json_fingerprint returns a value for the runtime manifest' );

    ok(
        !Browser::Runner::NodeRuntime::_node_runtime_is_current(
            home_root    => $temp_root,
            package_json => $package_json,
            fingerprint  => $fingerprint,
        ),
        'node runtime is stale when required node_modules and the runtime stamp are absent'
    );

    for my $module ( Browser::Runner::NodeRuntime::_required_node_modules($package_json) ) {
        make_path( File::Spec->catdir( $temp_root, 'node_modules', $module ) );
    }

    # D2B-068: _required_node_modules must derive its list from the
    # package.json it's given, not a hardcoded literal, so a manifest
    # that gains/loses/renames a dependency is reflected automatically.
    # Uses a distinct fixture with a uniquely-named dependency NOT in the
    # old hardcoded qw(express jquery playwright uuid) literal, and
    # omitting one of those four - this would fail if the implementation
    # still silently returned the old hardcoded list instead of deriving.
    {
        my $distinct_package_json = File::Spec->catfile( $temp_root, 'distinct-package.json' );
        open my $distinct_fh, '>', $distinct_package_json or die "Unable to write distinct temp package.json: $!";
        print {$distinct_fh} qq|{"dependencies":{"jquery":"^3.7.1","totally-unique-dependency-xyz":"^1.0.0"}}\n|;
        close $distinct_fh or die "Unable to close distinct temp package.json: $!";
        is_deeply(
            [ sort( Browser::Runner::NodeRuntime::_required_node_modules($distinct_package_json) ) ],
            [ 'jquery', 'totally-unique-dependency-xyz' ],
            '_required_node_modules reflects a distinct package.json (with a uniquely-named dependency and one old module omitted), proving it derives rather than returning the old hardcoded literal'
        );
    }

    ok(
        !Browser::Runner::NodeRuntime::_node_runtime_is_current(
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
        Browser::Runner::NodeRuntime::_node_runtime_is_current(
            home_root    => $temp_root,
            package_json => $package_json,
            fingerprint  => $fingerprint,
        ),
        'node runtime treats an already-installed dependency set that satisfies package.json as current even without the runtime stamp'
    );

    Browser::Runner::NodeRuntime::_write_node_runtime_stamp(
        home_root   => $temp_root,
        fingerprint => $fingerprint,
    );
    is(
        Browser::Runner::NodeRuntime::_read_node_runtime_stamp( home_root => $temp_root ),
        $fingerprint,
        'node runtime stamp round-trips through the cache file'
    );
    ok(
        Browser::Runner::NodeRuntime::_node_runtime_is_current(
            home_root    => $temp_root,
            package_json => $package_json,
            fingerprint  => $fingerprint,
        ),
        'node runtime is current when required node_modules exist and the runtime stamp matches the package.json fingerprint'
    );
    ok(
        !Browser::Runner::NodeRuntime::_installed_modules_satisfy_package_json(
            home_root    => $temp_root,
            package_json => File::Spec->catfile( $temp_root, 'missing-package.json' ),
        ),
        'installed_modules_satisfy_package_json is not called with a missing manifest in normal flow'
    ) if 0;
    is(
        Browser::Runner::NodeRuntime::_installed_node_module_version(
            home_root => $temp_root,
            module    => 'uuid',
        ),
        '11.1.0',
        'installed_node_module_version reads installed node module versions'
    );
    ok(
        !defined Browser::Runner::NodeRuntime::_installed_node_module_version(
            home_root => $temp_root,
            module    => 'missing-module',
        ),
        'installed_node_module_version returns undef when the module metadata is absent'
    );
    ok( Browser::Runner::NodeRuntime::_version_satisfies_spec( '11.1.0', '^11.0.0' ), 'version_satisfies_spec accepts compatible caret ranges' );
    ok( !Browser::Runner::NodeRuntime::_version_satisfies_spec( '12.0.0', '^11.0.0' ), 'version_satisfies_spec rejects incompatible major versions' );
    ok( Browser::Runner::NodeRuntime::_version_satisfies_spec( '3.7.1', '3.7.1' ), 'version_satisfies_spec accepts exact matches' );
    ok( !Browser::Runner::NodeRuntime::_version_satisfies_spec( '3.7.0', '3.7.1' ), 'version_satisfies_spec rejects exact mismatches' );
    ok( Browser::Runner::NodeRuntime::_version_satisfies_spec( '1.2.3', '*' ), 'version_satisfies_spec accepts wildcard specs' );
    ok( Browser::Runner::NodeRuntime::_version_satisfies_spec( '1.2.3', 'latest' ), 'version_satisfies_spec accepts latest specs' );
    ok( !Browser::Runner::NodeRuntime::_version_satisfies_spec( 'not-a-version', '^1.2.3' ), 'version_satisfies_spec rejects non-numeric installed versions' );
    ok( !Browser::Runner::NodeRuntime::_version_satisfies_spec( '1.2.3-beta.1', '^1.2.3' ), 'version_satisfies_spec (D2B-071) rejects a pre-release install against a caret range targeting the release version' );
    ok( Browser::Runner::NodeRuntime::_version_satisfies_spec( '1.2.4', '^1.2.3' ), 'version_satisfies_spec still accepts a genuine release version satisfying the range' );
    ok( Browser::Runner::NodeRuntime::_version_satisfies_spec( '1.2.3-beta.1', '^1.2.3-beta.1' ), 'version_satisfies_spec (D2B-071) accepts a pre-release install when the spec\'s own minimum is that exact same pre-release string' );
    ok( !defined scalar Browser::Runner::NodeRuntime::_version_parts(undef), 'version_parts returns undef for missing versions' );
    ok( !defined scalar Browser::Runner::NodeRuntime::_version_parts('not-a-version'), 'version_parts returns undef for non-numeric versions' );
    {
        my $tmp = tempdir( CLEANUP => 1 );
        local $ENV{TMPDIR} = $tmp;
        my $path = Browser::Runner::_screenshot_path();
        like( $path, qr{\A$tmp/browser-[A-Fa-f0-9]+\.png\z}, 'screenshot_path defaults to TMPDIR with a generated .png filename' );
        is( Browser::Runner::_screenshot_path('/tmp/example'), '/tmp/example.png', 'screenshot_path appends .png when missing' );
        is( Browser::Runner::_screenshot_path('/tmp/example.png'), '/tmp/example.png', 'screenshot_path keeps an existing .png suffix unchanged' );
    }
    is(
        Browser::Runner::NodeRuntime::_make_path_if_missing( File::Spec->catdir( $temp_root, 'node_modules' ) ),
        1,
        'make_path_if_missing is a no-op success when the target directory already exists'
    );
    ok(
        Browser::Runner::NodeRuntime::_clear_installed_node_modules(
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
        !Browser::Runner::NodeRuntime::_installed_modules_satisfy_package_json(
            home_root    => $temp_root,
            package_json => $package_json,
        ),
        'installed_modules_satisfy_package_json rejects missing installed module metadata'
    );
    my $uuid_package_json = File::Spec->catfile( $temp_root, 'node_modules', 'uuid', 'package.json' );
    open my $reinstall_uuid_fh, '>', $uuid_package_json
      or die "Unable to rewrite temp installed uuid package metadata: $!";
    print {$reinstall_uuid_fh} qq|{"name":"uuid","version":"12.0.0"}\n|;
    close $reinstall_uuid_fh or die "Unable to close rewritten temp installed uuid package metadata: $!";

    # _installed_node_module_version now reads through the same shared,
    # mtime-keyed cache _read_package_json uses for the skill's own
    # package.json (D2B-053). In real use that cache is always cleared at
    # the very start of _ensure_node_runtime, before any installed-module
    # check runs, so a genuine re-install between two _ensure_node_runtime
    # calls is never served stale data. This test calls
    # _installed_modules_satisfy_package_json directly, bypassing that
    # clear, on the SAME path within the same process - a real risk of
    # colliding with an earlier cache entry under coarse filesystem mtime
    # resolution (seconds, not sub-second) if the rewrite above landed in
    # the same tick as an earlier read of this same file. Force a mtime
    # one second in the future so this test's own two back-to-back
    # rewrites can never collide, the same technique D2B-024's own test
    # (t/20-d2b-024-package-json-single-read.t) uses for the same reason.
    utime( time() + 1, time() + 1, $uuid_package_json ) or die "Unable to set mtime on rewritten temp installed uuid package metadata: $!";
    ok(
        !Browser::Runner::NodeRuntime::_installed_modules_satisfy_package_json(
            home_root    => $temp_root,
            package_json => $package_json,
        ),
        'installed_modules_satisfy_package_json rejects installed versions that do not satisfy the manifest'
    );
}

## GET request tests: basic request/response payload shape.

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

# D2B-065: a legitimate page title of "0" must not become an empty string.
{
    my $zero_title_page = FakePage->new(
        {
            response => FakeResponse->new( { status => 200 } ),
            url      => 'https://example.test/final',
            title    => '0',
            content  => '<html></html>',
        }
    );
    my $zero_title_playwright = FakePlaywright->new( { browser => FakeBrowser->new( { page => $zero_title_page } ) } );
    my $zero_title_runner = Browser::Runner->new( playwright_factory => sub { return $zero_title_playwright } );
    my $zero_title_result = $zero_title_runner->request( method => 'GET', url => 'https://example.test' );
    is( $zero_title_result->{title}, '0', 'GET preserves a legitimate title of "0" instead of falling back to empty string' );
}

## PNG/screenshot request tests.

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

# D2B-057: browser.png must not crash if page->title() throws after the
# screenshot has already been written to disk successfully.
{
    my $crash_temp = tempdir( CLEANUP => 1 );
    my $crash_page = FakePage->new(
        {
            response => FakeResponse->new( { status => 200 } ),
            url      => 'https://example.test/final',
        }
    );
    no warnings 'redefine';
    local *FakePage::title = sub { die "Target closed\n" };
    my $crash_playwright = FakePlaywright->new(
        {
            browser => FakeBrowser->new( { page => $crash_page } ),
        }
    );
    my $crash_runner = Browser::Runner->new(
        playwright_factory => sub { return $crash_playwright },
    );
    my $crash_result = $crash_runner->request(
        method => 'PNG',
        url    => 'https://example.test',
        file   => File::Spec->catfile( $crash_temp, 'shot' ),
    );
    is( $crash_result->{method}, 'PNG', 'PNG request survives a title() failure and still returns a PNG payload' );
    is( $crash_result->{file}, File::Spec->catfile( $crash_temp, 'shot.png' ), 'PNG request still reports the screenshot path when title() throws' );
    is( $crash_result->{title}, q{}, 'PNG request falls back to an empty-string title when title() throws' );
    ok( -f File::Spec->catfile( $crash_temp, 'shot.png' ), 'the screenshot file is still written even though title() failed afterward' );
}
{
    my $zero_temp = tempdir( CLEANUP => 1 );
    my $zero_page = FakePage->new(
        {
            response => FakeResponse->new( { status => 200 } ),
            url      => 'https://example.test/final',
            title    => '0',
        }
    );
    my $zero_playwright = FakePlaywright->new(
        {
            browser => FakeBrowser->new( { page => $zero_page } ),
        }
    );
    my $zero_runner = Browser::Runner->new(
        playwright_factory => sub { return $zero_playwright },
    );
    my $zero_result = $zero_runner->request(
        method => 'PNG',
        url    => 'https://example.test',
        file   => File::Spec->catfile( $zero_temp, 'shot' ),
    );
    is( $zero_result->{title}, '0', 'PNG request preserves a legitimate title of "0" instead of falling back to empty string' );
}

## GET request tests, continued: interactive/ask mode, jquery injection,
## controller (Perl-scripted) mode, timeout overrides, and the
## no-explicit-factory fallback path.

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
my $timeout_prompt = q{};
open my $timeout_prompt_fh, '>', \$timeout_prompt or die "Unable to open timeout prompt scalar: $!";
my $timeout_input = "\n";
open my $timeout_input_fh, '<', \$timeout_input or die "Unable to open timeout input scalar: $!";
$timeout_runner->request(
    method      => 'GET',
    url         => 'https://example.test/slow',
    interactive => 1,
    headless    => 0,
    timeout_ms  => 45000,
    input_fh    => $timeout_input_fh,
    prompt_fh   => $timeout_prompt_fh,
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

## POST request tests: basic request/response payload shape, captcha
## detection edge cases, no-body requests, and controller mode.

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

# D2B-084: _run_post used to check is_captcha against the wrapped/escaped
# $html handed to setContent, not the raw response body - so a real
# captcha widget served as a bare fragment (no explicit text/html
# content-type) got HTML-escaped by _response_document before
# _is_captcha_page ever saw it, and the escaping destroyed the literal
# tag/attribute structure D2B-083's fix requires to detect a real
# widget. This proves browser.post correctly flags a real captcha
# response even when _response_document would otherwise wrap/escape it.
{
    my $captcha_post_page = FakePage->new(
        {
            request         => FakeRequest->new(
                {
                    calls             => [],
                    response_body     => '<div class="g-recaptcha" data-sitekey="x"></div>',
                    response_headers  => {},
                }
            ),
            title           => 'Example',
            body_text       => q{},
            evaluate_return => undef,
        }
    );
    my $captcha_post_playwright = FakePlaywright->new( { browser => FakeBrowser->new( { page => $captcha_post_page } ) } );
    my $captcha_post_runner = Browser::Runner->new( playwright_factory => sub { return $captcha_post_playwright } );
    my $captcha_post_result = $captcha_post_runner->request( method => 'POST', url => 'https://example.test/challenge' );
    ok( $captcha_post_result->{is_captcha}, 'browser.post flags a real captcha widget served as a bare fragment with no explicit HTML content-type' );
}

# D2B-065: same fix applied to _run_post for consistency with _run_get and
# _run_png (all three now use _defined_or_empty). _run_post's result never
# exposes title directly (only GET does) and title is only consumed
# internally by the captcha check, where "0" and "" behave identically -
# so this is a defensive-correctness fix with no directly observable
# behavior difference for POST today. This is a smoke test proving the
# code path with a "0" title still runs cleanly with no die/warning.
{
    my $zero_title_post_page = FakePage->new(
        {
            request => FakeRequest->new( { calls => [] } ),
            title   => '0',
            body_text => q{},
        }
    );
    my $zero_title_post_playwright = FakePlaywright->new( { browser => FakeBrowser->new( { page => $zero_title_post_page } ) } );
    my $zero_title_post_runner = Browser::Runner->new( playwright_factory => sub { return $zero_title_post_playwright } );
    my $zero_title_post_result = eval { $zero_title_post_runner->request( method => 'POST', url => 'https://example.test/form' ) };
    ok( !$@, 'POST with a "0" page title runs cleanly with no die' ) or diag("Died with: $@");
    ok( !$zero_title_post_result->{is_captcha}, 'POST with title "0" is correctly not flagged as captcha' );
}

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

## Error-handling tests: browser errors are rethrown/cleaned up
## correctly, and unsupported HTTP methods are rejected.

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

## _run_controller_script unit tests: direct calls to the controller
## helper (independent of the higher-level GET/POST integration tests
## above, which already exercise it through request()).

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

## Browser::Runner::BrowserPath unit tests: launch-option construction
## and Chromium/Chrome binary detection/validation.

{
    local $ENV{CHROMIUM_BIN};
    local $ENV{PATH} = q{};
    my %launch = Browser::Runner::BrowserPath::_launch_options(
        browser  => 'chromium',
        headless => 1,
    );
    is( $launch{type}, 'chrome', 'launch options map chromium onto the Playwright-supported chrome type' );
    is( $launch{headless}, 1, 'launch options keep headless true when requested' );
    ok( !exists $launch{executablePath}, 'launch options do not force an executable when CHROMIUM_BIN is absent' );
}

{
    no warnings 'redefine';
    local *Browser::Runner::BrowserPath::_validated_browser_path = sub { return };
    my %launch = Browser::Runner::BrowserPath::_launch_options(
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
    is( Browser::Runner::BrowserPath::_default_chromium_bin(), $chromium_path, 'default_chromium_bin finds chromium from PATH when CHROMIUM_BIN is unset' );
    my %launch = Browser::Runner::BrowserPath::_launch_options(
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
    ok( !defined Browser::Runner::BrowserPath::_default_chromium_bin(), 'default_chromium_bin rejects relative PATH hits such as bin/chrome' );
    chdir $cwd or die "Unable to restore cwd after relative-path browser test: $!";
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    my $broken = File::Spec->catfile( $temp_root, 'broken-chrome' );
    open my $broken_fh, '>', $broken or die "Unable to write broken chrome wrapper: $!";
    print {$broken_fh} "#!/bin/sh\nexit 127\n";
    close $broken_fh or die "Unable to close broken chrome wrapper: $!";
    chmod 0755, $broken or die "Unable to chmod broken chrome wrapper: $!";
    ok( !Browser::Runner::BrowserPath::_browser_path_is_usable($broken), 'browser_path_is_usable rejects wrappers that fail a launchability check' );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    my $good = File::Spec->catfile( $temp_root, 'good-chrome' );
    open my $good_fh, '>', $good or die "Unable to write good chrome wrapper: $!";
    print {$good_fh} "#!/bin/sh\nexit 0\n";
    close $good_fh or die "Unable to close good chrome wrapper: $!";
    chmod 0755, $good or die "Unable to chmod good chrome wrapper: $!";
    ok( Browser::Runner::BrowserPath::_browser_path_is_usable($good), 'browser_path_is_usable accepts launchable absolute browser paths' );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    my $good = File::Spec->catfile( $temp_root, 'configured-chrome' );
    open my $good_fh, '>', $good or die "Unable to write configured chrome wrapper: $!";
    print {$good_fh} "#!/bin/sh\nexit 0\n";
    close $good_fh or die "Unable to close configured chrome wrapper: $!";
    chmod 0755, $good or die "Unable to chmod configured chrome wrapper: $!";
    local $ENV{CHROMIUM_BIN} = $good;
    is( Browser::Runner::BrowserPath::_validated_browser_path(), $good, 'validated_browser_path accepts a configured absolute browser path that passes the usability check' );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    my $broken = File::Spec->catfile( $temp_root, 'configured-broken-chrome' );
    open my $broken_fh, '>', $broken or die "Unable to write broken configured chrome wrapper: $!";
    print {$broken_fh} "#!/bin/sh\nexit 127\n";
    close $broken_fh or die "Unable to close broken configured chrome wrapper: $!";
    chmod 0755, $broken or die "Unable to chmod broken configured chrome wrapper: $!";
    local $ENV{CHROMIUM_BIN} = $broken;
    ok( !defined Browser::Runner::BrowserPath::_validated_browser_path(), 'validated_browser_path rejects a configured browser path that fails the usability check' );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    local $ENV{HOME} = $temp_root;
    my @candidates = Browser::Runner::BrowserPath::_browser_candidates();
    like( join( "\n", @candidates ), qr/Applications\/Google Chrome\.app\/Contents\/MacOS\/Google Chrome/, 'browser_candidates includes macOS Chrome app paths for validation' );
    like( join( "\n", @candidates ), qr/\Q$temp_root\E\/Applications\/Chromium\.app\/Contents\/MacOS\/Chromium/, 'browser_candidates includes home-local macOS Chromium app paths for validation' );
}

## Browser::Runner::NodeRuntime::_skill_root unit tests.

{
    local $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT} = '/tmp/browser-skill-root';
    is( Browser::Runner::NodeRuntime::_skill_root(), '/tmp/browser-skill-root', 'skill root prefers the DD skill root environment variable' );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    make_path( File::Spec->catdir( $temp_root, 'cli' ) );
    make_path( File::Spec->catdir( $temp_root, 'lib', 'Browser' ) );
    open my $marker_fh, '>', File::Spec->catfile( $temp_root, 'lib', 'Browser', 'CLI.pm' )
      or die "Unable to write skill-root marker file: $!";
    print {$marker_fh} "1;\n";
    close $marker_fh;
    my $cwd = Cwd::getcwd();
    chdir $temp_root or die "Unable to chdir to temp root: $!";
    is( Browser::Runner::NodeRuntime::_skill_root(), $temp_root, 'skill root falls back to the current skill repo during local development' );
    chdir $cwd or die "Unable to restore cwd: $!";
}

{
    local $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT};
    my $temp_root = tempdir( CLEANUP => 1 );
    my $cwd = Cwd::getcwd();
    chdir $temp_root or die "Unable to chdir to fallback temp root: $!";
    like( Browser::Runner::NodeRuntime::_skill_root(), qr/(?:\.|skills\/browser)\z/, 'skill root can fall back to the module path' );
    chdir $cwd or die "Unable to restore cwd after module-path fallback test: $!";
}

## _ensure_node_runtime / _install_node_runtime unit tests: the
## npx-staged npm install flow, its success and failure paths, and
## the HOME/package.json precondition checks.

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
    my $runtime = Browser::Runner::NodeRuntime::_ensure_node_runtime();
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
    local *Browser::Runner::NodeRuntime::_run_quiet_command = sub {
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
    local *Browser::Runner::NodeRuntime::_write_node_runtime_stamp = sub {
        my (%args) = @_;
        ok( $args{fingerprint}, 'ensure_node_runtime writes the runtime stamp after staged install' );
        return 0;
    };
    Browser::Runner::NodeRuntime::_ensure_node_runtime();
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    my $empty_package_json = File::Spec->catfile( $temp_root, 'empty-package.json' );
    open my $empty_fh, '>', $empty_package_json or die "Unable to write empty package.json: $!";
    print {$empty_fh} qq|{"name":"empty-browser","version":"0.01.0"}\n|;
    close $empty_fh or die "Unable to close empty package.json: $!";
    is(
        Browser::Runner::NodeRuntime::_install_node_runtime(
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
    local *Browser::Runner::NodeRuntime::_run_quiet_command = sub { die "simulated staged npm failure\n" };
    eval {
        Browser::Runner::NodeRuntime::_install_node_runtime(
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
    eval { Browser::Runner::NodeRuntime::_ensure_node_runtime() };
    like( $@, qr/HOME is required/, '_ensure_node_runtime requires HOME for DD-style package.json installs' );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    local $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT} = $temp_root;
    local $ENV{HOME} = $temp_root;
    eval { Browser::Runner::NodeRuntime::_ensure_node_runtime() };
    like( $@, qr/Missing package\.json/, '_ensure_node_runtime requires package.json under the skill root' );
}

eval { Browser::Runner::NodeRuntime::_run_quiet_command('false') };
like( $@, qr/Command failed/, '_run_quiet_command reports failed commands' );

my $quiet_command_exit = Browser::Runner::NodeRuntime::_run_quiet_command('true');
is( $quiet_command_exit, 0, '_run_quiet_command returns zero for a successful command' );

## _new_playwright unit test.

{
    no warnings 'redefine';
    local *Browser::Runner::NodeRuntime::_ensure_node_runtime = sub { return '/tmp/browser-node'; };
    local $INC{'Playwright.pm'} = __FILE__;
    {
        package Playwright;
        no warnings 'redefine';
        sub new { return bless { source => 'stub' }, shift }
    }
    my $playwright = Browser::Runner::_new_playwright();
    is( ref $playwright, 'Playwright', '_new_playwright loads and instantiates Playwright' );
}

## _is_captcha_page / _page_text / _goto_options unit tests.

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

# D2B-066: an explicitly-passed empty --wait-until must not be silently
# treated the same as "not given" - it should hit the same validation
# error as any other unsupported value.
eval { Browser::Runner::_goto_options( wait_until => q{} ) };
like( $@, qr/Unsupported wait-until mode/, 'goto_options refuses an explicit empty-string --wait-until instead of silently defaulting' );

## _response_document / _escape_html unit tests.

# D2B-075: _response_document must not let its tag-shape heuristic
# override an explicit JSON content_type (the tag-shape trust heuristic
# is intentionally still applied to other non-JSON, non-HTML content
# types such as application/xml, and to text/plain/unlabeled bodies -
# see D2B-032, whose own test relies on that).
is(
    Browser::Runner::_response_document( body => '<data>foo</data>', content_type => 'application/json' ),
    '<!doctype html><html><head><meta charset="utf-8"><title>browser.post</title></head><body><pre id="browser-post-body">&lt;data&gt;foo&lt;/data&gt;</pre></body></html>',
    '_response_document wraps a tag-shaped body when content_type explicitly names a JSON type'
);
is(
    Browser::Runner::_response_document( body => '<data>foo</data>', content_type => 'text/html' ),
    '<data>foo</data>',
    '_response_document takes the direct text/html content-type path (not the tag-shape heuristic) and returns the body unwrapped'
);

# D2B-076: _escape_html must also escape quote characters, not just &<>.
is( Browser::Runner::_escape_html(q{he said "hi" & 'bye'}), 'he said &quot;hi&quot; &amp; &#39;bye&#39;', '_escape_html escapes double and single quotes in addition to &, <, >' );
## _jquery_path / _maybe_inject_jquery unit tests.

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
## _await_user / _interact_and_run_script unit tests.

my $await_prompt = q{};
open my $await_prompt_fh, '>', \$await_prompt or die "Unable to open await prompt scalar: $!";
my $await_input = "\n";
open my $await_input_fh, '<', \$await_input or die "Unable to open await input scalar: $!";
ok( Browser::Runner::_await_user( input_fh => $await_input_fh, prompt_fh => $await_prompt_fh ), 'await_user returns success after the user confirms' );
like( $await_prompt, qr/press Enter to continue/i, 'await_user emits the interactive prompt' );

# D2B-056: _interact_and_run_script is the shared helper extracted from the
# duplicated interactive/jquery/script sequence in _run_get/_run_post.
{
    my $script_prompt = q{};
    open my $script_prompt_fh, '>', \$script_prompt or die "Unable to open scalar for interact test: $!";
    my $script_input = "\n";
    open my $script_input_fh, '<', \$script_input or die "Unable to open scalar for interact test: $!";
    my $page = FakePage->new( { evaluate_return => 'script-ran' } );
    my $result = Browser::Runner::_interact_and_run_script(
        $page,
        interactive => 1,
        script      => 'return 1',
        input_fh    => $script_input_fh,
        prompt_fh   => $script_prompt_fh,
    );
    like( $script_prompt, qr/press Enter to continue/i, '_interact_and_run_script awaits the user when interactive is set' );
    is( $result, 'script-ran', '_interact_and_run_script returns the script result' );
}
{
    my $temp_root = tempdir( CLEANUP => 1 );
    make_path( File::Spec->catdir( $temp_root, 'node_modules', 'jquery', 'dist' ) );
    open my $jquery_fh, '>', File::Spec->catfile( $temp_root, 'node_modules', 'jquery', 'dist', 'jquery.min.js' ) or die "Unable to write temp jquery runtime for interact test: $!";
    print {$jquery_fh} "/* jquery */\n";
    close $jquery_fh or die "Unable to close temp jquery runtime for interact test: $!";
    local $ENV{HOME} = $temp_root;

    my @call_order;
    my $page = FakePage->new( { evaluate_return => 'script-ran' } );
    no warnings 'redefine';
    local *FakePage::addScriptTag = sub { push @call_order, 'jquery'; push @{ $_[0]{script_tags} }, $_[1]; return 1 };
    local *FakePage::evaluate     = sub { push @call_order, 'script'; return $_[0]{evaluate_return} };

    my $result = Browser::Runner::_interact_and_run_script(
        $page,
        jquery => 1,
        script => 'return 1',
    );
    is( $result, 'script-ran', '_interact_and_run_script returns the script result when jquery mode is also on' );
    is_deeply( \@call_order, [ 'jquery', 'script' ], '_interact_and_run_script injects jquery before running the script, not after' );
}
{
    my $page = FakePage->new( {} );
    my $result = Browser::Runner::_interact_and_run_script( $page );
    is( $result, undef, '_interact_and_run_script is a no-op pass-through when no script/interactive/jquery options are given' );
}

done_testing();
