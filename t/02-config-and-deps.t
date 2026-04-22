use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner;

ok( -f 'config/config.json', 'skill keeps a config/config.json file' );
ok( -f 'aptfile', 'skill declares Debian-family packages in aptfile' );
ok( -f 'brewfile', 'skill declares macOS packages in brewfile' );
ok( -f 'package.json', 'skill declares Node dependencies in package.json' );
ok( -f 'cpanfile', 'skill declares shared Perl dependencies in cpanfile' );

my $aptfile = do {
    open my $fh, '<', 'aptfile' or die "Unable to read aptfile: $!";
    local $/;
    <$fh>;
};
like( $aptfile, qr/^nodejs$/m, 'aptfile includes nodejs' );

my $brewfile = do {
    open my $fh, '<', 'brewfile' or die "Unable to read brewfile: $!";
    local $/;
    <$fh>;
};
like( $brewfile, qr/^node$/m, 'brewfile includes node' );

my $cpanfile = do {
    open my $fh, '<', 'cpanfile' or die "Unable to read cpanfile: $!";
    local $/;
    <$fh>;
};
like( $cpanfile, qr/requires 'Playwright';/, 'cpanfile includes the Playwright module' );

my $package_json = do {
    open my $fh, '<', 'package.json' or die "Unable to read package.json: $!";
    local $/;
    <$fh>;
};
like( $package_json, qr/"playwright"\s*:/, 'package.json includes playwright' );
like( $package_json, qr/"express"\s*:/, 'package.json includes express' );
like( $package_json, qr/"jquery"\s*:/, 'package.json includes jquery' );
like( $package_json, qr/"uuid"\s*:/, 'package.json includes uuid' );

my %launch = Browser::Runner::_launch_options(
    browser  => 'chrome',
    headless => 0,
);
is( $launch{type}, 'chrome', 'launch options use the requested browser type' );
is( $launch{headless}, 0, 'launch options respect headless settings' );

is(
    Browser::Runner::_response_document(
        body         => 'plain text',
        content_type => 'text/plain',
    ),
    '<!doctype html><html><head><meta charset="utf-8"><title>browser.post</title></head><body><pre id="browser-post-body">plain text</pre></body></html>',
    'plain POST bodies are wrapped into a DOM document'
);

is(
    Browser::Runner::_response_document(
        body         => '<html><body>ok</body></html>',
        content_type => 'text/html; charset=utf-8',
    ),
    '<html><body>ok</body></html>',
    'HTML responses stay intact'
);

is(
    Browser::Runner::_escape_html('a<&>b'),
    'a&lt;&amp;&gt;b',
    'HTML escaping protects wrapped plain-text bodies'
);

done_testing();
