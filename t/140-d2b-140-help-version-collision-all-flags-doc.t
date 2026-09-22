use strict;
use warnings;

use Test::More;
use Browser::CLI;

# The equals-form negative cases below fall through past the help/version
# short-circuit and reach execute()'s real $runner->request() call (since
# --script=--help/--browser=--help/etc. is a syntactically valid Getopt::Long
# value, just a literal string "--help") - a FakeRunner avoids a real
# Playwright browser launch, network call, or (for --file) a stray file
# write to the working directory for what is otherwise a documentation-only
# ticket's test.
package FakeRunner;
sub new { bless {}, shift }
sub request {
    my ( $self, %args ) = @_;
    return { method => $args{method}, requested_url => $args{url}, status => 200 };
}
package main;

# D2B-140: D2B-138 documented the --help/--version argv-collision only for
# --data. The same pre-parse scan in _argv_requests_help/_argv_requests_version
# (lib/Browser/CLI.pm) inspects the whole argv before any flag value is
# assigned, so the collision applies to every string-valued flag, wherever
# supported across the four commands. This asserts the docs now say so, and
# table-drives execute()/execute_search() across all seven flags to prove it
# behaviorally, not just via the private pre-scan helpers - checking the
# actual help/version payload content, not just a truthy marker, and
# confirming the equals-form escape for every one of the seven flags.

my @doc_files = ( 'README.md', 'docs/usage.md', 'SKILLS.md' );

for my $doc_file (@doc_files) {
    open my $fh, '<', $doc_file or die "Unable to open ${doc_file}: $!";
    my $text = do { local $/; <$fh> };
    close $fh;

    like(
        $text,
        qr/every\s+string-valued\s+flag/i,
        "${doc_file} names the general --help/--version collision rule across flags, not just --data"
    );
}

# Each row: [ method, flag, applicable-command-description ]
my @get_post_png_flags = (
    [ 'GET',  'script',      '--script on browser.get' ],
    [ 'GET',  'browser',     '--browser on browser.get' ],
    [ 'GET',  'wait-until',  '--wait-until on browser.get' ],
    [ 'POST', 'data',        '--data on browser.post' ],
    [ 'PNG',  'file',        '--file on browser.png' ],
);

for my $row (@get_post_png_flags) {
    my ( $method, $flag, $label ) = @$row;

    my $help_result = Browser::CLI::execute(
        method => $method,
        argv   => [ 'https://example.test', "--$flag", '--help' ],
    );
    ok( $help_result->{help}, "D2B-140: $label --help (separate tokens) returns help instead of using the flag" );
    like( $help_result->{usage}, qr/^Usage:/m, "D2B-140: $label --help returns real usage text, not just a truthy marker" );

    my $version_result = Browser::CLI::execute(
        method => $method,
        argv   => [ 'https://example.test', "--$flag", '--version' ],
    );
    ok( $version_result->{version}, "D2B-140: $label --version (separate tokens) returns version instead of using the flag" );
    like( $version_result->{version_string}, qr/^\d+\.\d+/, "D2B-140: $label --version returns a real version string, not just a truthy marker" );

    my $equals_result = eval {
        Browser::CLI::execute(
            method => $method,
            argv   => [ 'https://example.test', "--$flag=--help" ],
            runner => FakeRunner->new(),
        );
    };
    ok(
        !( ref $equals_result eq 'HASH' && $equals_result->{help} ),
        "D2B-140: $label=--help (equals-form, one token) is NOT detected as a help request"
    );
}

for my $flag (qw(engine engines)) {
    my $help_result = Browser::CLI::execute_search(
        argv => [ 'test query', "--$flag", '--help' ],
    );
    ok( $help_result->{help}, "D2B-140: --$flag on browser.search --help (separate tokens) returns help instead of using the flag" );
    like( $help_result->{usage}, qr/^Usage:/m, "D2B-140: --$flag on browser.search --help returns real usage text, not just a truthy marker" );

    my $version_result = Browser::CLI::execute_search(
        argv => [ 'test query', "--$flag", '--version' ],
    );
    ok( $version_result->{version}, "D2B-140: --$flag on browser.search --version (separate tokens) returns version instead of using the flag" );
    like( $version_result->{version_string}, qr/^\d+\.\d+/, "D2B-140: --$flag on browser.search --version returns a real version string, not just a truthy marker" );

    my $equals_result = eval {
        Browser::CLI::execute_search(
            argv => [ 'test query', "--$flag=--help" ],
        );
    };
    ok(
        !( ref $equals_result eq 'HASH' && $equals_result->{help} ),
        "D2B-140: --$flag=--help (equals-form, one token) on browser.search is NOT detected as a help request"
    );
}

done_testing();
