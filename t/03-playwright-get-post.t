use strict;
use warnings FATAL => 'all';

use JSON::PP qw(decode_json);
use IO::Socket::INET;
use Test::More;
use Time::HiRes qw(sleep);

my $node_bin = _find_command('node');
my $chromium_bin = $ENV{CHROMIUM_BIN} || _find_command(qw(chromium chromium-browser google-chrome google-chrome-stable));

plan skip_all => 'Playwright integration test requires node and Chromium'
  if !$node_bin || !$chromium_bin;

my $port = _reserve_port();
my $pid = fork();
die "Unable to fork test server: $!" if !defined $pid;

if ( $pid == 0 ) {
    _run_server($port);
    exit 0;
}

eval {
    _wait_for_port($port);

    my $get_output = qx{NODE_PATH="$ENV{NODE_PATH}" CHROMIUM_BIN="$chromium_bin" $^X cli/get http://127.0.0.1:$port/get --script 'return { title: document.title, heading: document.querySelector("h1").textContent }' 2>&1};
    my $get_exit = $? >> 8;
    is( $get_exit, 0, "browser.get exits cleanly\n$get_output" );
    my $get_payload = decode_json($get_output);
    is( $get_payload->{method}, 'GET', 'browser.get reports the GET method' );
    is( $get_payload->{status}, 200, 'browser.get reports HTTP 200' );
    is( $get_payload->{title}, 'Browser Skill', 'browser.get returns the page title' );
    like( $get_payload->{body}, qr/<h1>Browser Skill<\/h1>/, 'browser.get returns the rendered page HTML' );
    is( $get_payload->{script_result}{heading}, 'Browser Skill', 'browser.get evaluates Playwright script against the DOM' );

    my $post_output = qx{NODE_PATH="$ENV{NODE_PATH}" CHROMIUM_BIN="$chromium_bin" $^X cli/post http://127.0.0.1:$port/post --data 'name=dashboard' --script 'return { heading: document.querySelector("h1").textContent, status: window.__BROWSER_POST__.status, body: document.body.textContent.trim() }' 2>&1};
    my $post_exit = $? >> 8;
    is( $post_exit, 0, "browser.post exits cleanly\n$post_output" );
    my $post_payload = decode_json($post_output);
    is( $post_payload->{method}, 'POST', 'browser.post reports the POST method' );
    is( $post_payload->{status}, 200, 'browser.post reports HTTP 200' );
    like( $post_payload->{body}, qr/name=dashboard/, 'browser.post returns the response body' );
    is( $post_payload->{script_result}{heading}, 'Posted', 'browser.post loads the response body into the page for scripting' );
    is( $post_payload->{script_result}{status}, 200, 'browser.post exposes response metadata in the page context' );
};
my $error = $@;

kill 'TERM', $pid;
waitpid $pid, 0;

die $error if $error;

done_testing();

sub _run_server {
    my ($port) = @_;
    my $server = IO::Socket::INET->new(
        LocalAddr => '127.0.0.1',
        LocalPort => $port,
        Listen    => 5,
        Proto     => 'tcp',
        ReuseAddr => 1,
    ) or die "Unable to start server: $!";

    local $SIG{TERM} = sub { exit 0 };
    local $SIG{PIPE} = 'IGNORE';

    while ( my $client = $server->accept ) {
        my $request = <$client>;
        my ( $method, $path ) = ('GET', '/');
        if ( defined $request && $request =~ m{\A([A-Z]+)\s+(\S+) } ) {
            ( $method, $path ) = ( $1, $2 );
        }

        my %headers;
        my $content_length = 0;
        while ( defined( my $line = <$client> ) ) {
            last if $line =~ /^\r?\n\z/;
            my ( $name, $value ) = split /:\s*/, $line, 2;
            next if !defined $name || !defined $value;
            $value =~ s/\r?\n\z//;
            $headers{ lc $name } = $value;
            $content_length = $value if lc($name) eq 'content-length';
        }

        my $body = q{};
        if ($content_length) {
            read $client, $body, $content_length;
        }

        my ( $status, $content_type, $response_body ) = ( 404, 'text/plain', 'not found' );
        if ( $method eq 'GET' && $path eq '/get' ) {
            $status = 200;
            $content_type = 'text/html; charset=utf-8';
            $response_body = '<!doctype html><html><head><title>Browser Skill</title></head><body><h1>Browser Skill</h1></body></html>';
        }
        elsif ( $method eq 'POST' && $path eq '/post' ) {
            $status = 200;
            $content_type = 'text/html; charset=utf-8';
            $response_body = '<!doctype html><html><head><title>Posted</title></head><body><h1>Posted</h1><p>' . $body . '</p></body></html>';
        }

        print {$client} "HTTP/1.1 $status " . ( $status == 200 ? 'OK' : 'Not Found' ) . "\r\n";
        print {$client} "Content-Type: $content_type\r\n";
        print {$client} "Content-Length: " . length($response_body) . "\r\n";
        print {$client} "Connection: close\r\n\r\n";
        print {$client} $response_body;
        close $client;
    }
}

sub _wait_for_port {
    my ($port) = @_;
    for ( 1 .. 50 ) {
        my $socket = IO::Socket::INET->new(
            PeerAddr => '127.0.0.1',
            PeerPort => $port,
            Proto    => 'tcp',
        );
        if ($socket) {
            close $socket;
            return 1;
        }
        sleep 0.1;
    }
    die "Timed out waiting for port $port";
}

sub _reserve_port {
    my $socket = IO::Socket::INET->new(
        LocalAddr => '127.0.0.1',
        LocalPort => 0,
        Listen    => 1,
        Proto     => 'tcp',
        ReuseAddr => 1,
    ) or die "Unable to reserve port: $!";
    my $port = $socket->sockport;
    close $socket;
    return $port;
}

sub _find_command {
    for my $candidate (@_) {
        my $path = qx{command -v $candidate 2>/dev/null};
        chomp $path;
        return $path if $path;
    }
    return;
}
