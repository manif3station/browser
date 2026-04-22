use strict;
use warnings;

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
    sub evaluate {
        push @{ $_[0]{evaluations} }, $_[1];
        return $_[0]{body_text} if $_[1] =~ /document\.body \? document\.body\.innerText/;
        return $_[0]{evaluate_return};
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

{
    local $ENV{CHROMIUM_BIN};
    my %launch = Browser::Runner::_launch_options(
        browser  => 'chromium',
        headless => 1,
    );
    is( $launch{type}, 'chrome', 'launch options map chromium onto the Playwright-supported chrome type' );
    is( $launch{headless}, 1, 'launch options keep headless true when requested' );
    ok( !exists $launch{executablePath}, 'launch options do not force an executable when CHROMIUM_BIN is absent' );
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
    make_path( File::Spec->catdir( $temp_root, 'node_modules', 'playwright' ) );
    make_path( File::Spec->catdir( $temp_root, 'node_modules', 'express' ) );
    make_path( File::Spec->catdir( $temp_root, 'node_modules', 'uuid' ) );
    open my $package_fh, '>', File::Spec->catfile( $temp_root, 'package.json' ) or die "Unable to write temp package.json: $!";
    print {$package_fh} qq|{"name":"browser-skill-test","version":"0.01.0"}\n|;
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
    print {$package_fh} qq|{"name":"browser-skill-test","version":"0.01.0"}\n|;
    close $package_fh or die "Unable to close temp package.json: $!";
    local *Browser::Runner::_run_command = sub {
        my (@command) = @_;
        is_deeply( \@command, [ 'npm', 'install', '--prefix', $temp_root, $temp_root ], 'ensure_node_runtime uses DD package.json install behavior under HOME' );
        return 0;
    };
    Browser::Runner::_ensure_node_runtime();
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

{
    no warnings 'redefine';
    local *Browser::Runner::_ensure_node_runtime = sub { return '/tmp/browser-node'; };
    local $INC{'Playwright.pm'} = __FILE__;
    local $SIG{__WARN__} = sub {
        return if $_[0] =~ /Subroutine new redefined/;
        warn $_[0];
    };
    {
        package Playwright;
        sub new { return bless { source => 'stub' }, shift }
    }
    my $playwright = Browser::Runner::_new_playwright();
    is( ref $playwright, 'Playwright', '_new_playwright loads and instantiates Playwright' );
}

ok( Browser::Runner::_is_captcha_page( title => 'Captcha Check', body => '<script src=\"recaptcha\"></script>', body_text => 'unusual traffic' ), 'captcha helper detects captcha-like pages' );
ok( !Browser::Runner::_is_captcha_page( title => 'Normal', body => '<html>ok</html>', body_text => 'hello world' ), 'captcha helper ignores normal pages' );
is( Browser::Runner::_page_text( FakePage->new( { body_text => "Hello\n" } ) ), "Hello\n", 'page_text extracts body text through the page helper' );
my $await_prompt = q{};
open my $await_prompt_fh, '>', \$await_prompt or die "Unable to open await prompt scalar: $!";
my $await_input = "\n";
open my $await_input_fh, '<', \$await_input or die "Unable to open await input scalar: $!";
ok( Browser::Runner::_await_user( input_fh => $await_input_fh, prompt_fh => $await_prompt_fh ), 'await_user returns success after the user confirms' );
like( $await_prompt, qr/press Enter to continue/i, 'await_user emits the interactive prompt' );
done_testing();
