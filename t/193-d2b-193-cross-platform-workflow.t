use strict;
use warnings;

use Test::More;
use YAML::XS qw(LoadFile);

# D2B-193: this repo has no .github/workflows directory and no CI
# verifying a real (non-mocked) Playwright browser launch on any
# platform - every existing test that touches Browser::Runner injects a
# mock playwright_factory. This asserts the new cross-platform.yml
# workflow file exists and its job matrix covers the required OS list
# and the currently-supported (non-edge) browser types, with Windows
# arm64 explicitly excluded and documented, rather than silently missing.
#
# This is a structural test on the workflow YAML's shape, not a live
# GitHub Actions run - actually executing the workflow requires pushing
# to GitHub, which is outside this Docker test container's scope.

my $workflow_path = '.github/workflows/cross-platform.yml';

ok( -f $workflow_path, ".github/workflows/cross-platform.yml exists" )
  or diag("Not found at $workflow_path");

my $workflow = eval { LoadFile($workflow_path) };
ok( !$@, 'cross-platform.yml parses as valid YAML' ) or diag("Parse error: $@");

SKIP: {
    skip 'workflow file missing or unparseable', 5 if !$workflow;

    ok( exists $workflow->{jobs}, 'workflow defines at least one job' );

    my ($job) = values %{ $workflow->{jobs} || {} };
    ok( $job, 'the matrix job was found' );

    my $matrix = $job->{strategy}{matrix} || {};
    my @os_list      = @{ $matrix->{os}      || [] };
    my @browser_list = @{ $matrix->{browser} || [] };

    ok( ( grep { /ubuntu/i } @os_list ), 'matrix os list includes a Linux runner' );
    ok( ( grep { /macos/i } @os_list ),  'matrix os list includes a macOS runner' );
    ok( ( grep { /windows/i } @os_list ), 'matrix os list includes a Windows runner' );

    # D2B-200: edge shipped in D2B-192 and is now included in the
    # matrix - the workflow's own header comment previously deferred it
    # explicitly until D2B-192 shipped.
    is_deeply(
        [ sort @browser_list ],
        [ sort qw(chrome chromium edge firefox webkit) ],
        'matrix browser list covers every currently-supported browser type, including edge now that D2B-192 shipped'
    );

}

my $raw_yaml = '';
if ( open my $fh, '<', $workflow_path ) {
    local $/;
    $raw_yaml = <$fh>;
}
like(
    $raw_yaml,
    qr/windows.{0,80}arm64|arm64.{0,80}windows/is,
    'the workflow documents, in a comment, why Windows arm64 is absent from the matrix rather than silently omitting it'
);
unlike(
    $raw_yaml,
    qr/edge is deferred/i,
    'the workflow no longer says edge is deferred, now that D2B-192 shipped'
);
like(
    $raw_yaml,
    qr/arm.{0,80}edge|edge.{0,80}arm/is,
    'the workflow documents, in a comment, why Linux ARM64 is excluded from the edge combination (Microsoft ships no Edge build for Linux ARM64)'
);

done_testing();
