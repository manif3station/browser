use strict;
use warnings;

use Test::More;
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP qw(decode_json);

my $node = 'node';
{
    open my $null_fh, '>', File::Spec->devnull() or die "open null device: $!";
    local *STDOUT = $null_fh;
    local *STDERR = $null_fh;
    if ( system( $node, '--version' ) != 0 ) {
        plan skip_all => 'requires node';
    }
}

my $dir = tempdir( CLEANUP => 1 );
my $harness_path = File::Spec->catfile( $dir, 'run-current.js' );
my $output_path  = File::Spec->catfile( $dir, 'result.json' );
my $worker_path  = File::Spec->rel2abs('libexec/persistent-browser.js');

open my $harness_fh, '>', $harness_path or die "open $harness_path: $!";
print {$harness_fh} <<'JAVASCRIPT';
'use strict';
const fs = require('node:fs');
const { runRequest } = require(process.argv[2]);
const createPage = ({ url, title, text }) => ({
  url: () => url,
  title: async () => title,
  content: async () => `<html><body>${text}</body></html>`,
  evaluate: async () => text,
});
const pages = [
  createPage({ url: 'https://one.example/', title: 'First tab', text: 'first page text' }),
  createPage({ url: 'https://two.example/', title: 'Second tab', text: 'second page text' }),
];
const context = { pages: () => pages };
runRequest(context, pages[0], { method: 'GET', current: true })
  .then(result => fs.writeFileSync(process.argv[3], JSON.stringify(result)))
  .catch(error => { console.error(error); process.exitCode = 1; });
JAVASCRIPT
close $harness_fh or die "close $harness_path: $!";

my $status = system( $node, $harness_path, $worker_path, $output_path );
is( $status, 0, 'current-page request completes with multiple open tabs' );

open my $result_fh, '<', $output_path or die "open $output_path: $!";
local $/;
my $result = decode_json(<$result_fh>);
close $result_fh;
is_deeply(
    [ map { [ $_->{index}, $_->{title}, $_->{url}, $_->{text}, $_->{session_page} ? 1 : 0 ] } @{ $result->{tabs} } ],
    [
        [ 0, 'First tab',  'https://one.example/', 'first page text',  1 ],
        [ 1, 'Second tab', 'https://two.example/', 'second page text', 0 ],
    ],
    'current GET returns snapshots for every open tab and identifies its session page',
);

done_testing();
