use strict;
use warnings;

use JSON::PP qw(decode_json);
use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-208: this workspace's own CLAUDE.md documents a DD skill CLI
# output contract - "default output is a human-readable summary
# (pretty table); -o json emits the full underlying payload, not a
# summarized copy." None of browser.get/browser.post/browser.search
# followed that (no -o flag existed at all). Rather than flip the
# default (a breaking change for every existing caller of this
# skill's JSON output, including the 1000+ assertions already in this
# suite), -o/--output is added with json kept as the default and
# table as a new opt-in - satisfying the letter of the convention
# without a compatibility break. See D2B-208's own key_details for
# the full rationale.

{
    package TestRunner;

    sub new { bless {}, shift }

    sub request {
        my ( $self, %args ) = @_;
        return {
            method        => $args{method},
            requested_url => $args{url},
            final_url     => $args{url},
            status        => 200,
            title         => $args{method} eq 'GET' ? 'Example Title' : undef,
            content_type  => 'text/html',
            headers       => { 'content-type' => 'text/html' },
            body          => '<html></html>',
            body_text     => q{},
            is_captcha    => 0,
            script_result => $args{script},
        };
    }
}

sub _run_main {
    my (%args) = @_;
    my $output = q{};
    my $error  = q{};
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";
    open my $error_fh,  '>', \$error  or die "Unable to open error scalar: $!";
    my $rc = Browser::CLI::main( %args, output_fh => $output_fh, error_fh => $error_fh );
    close $output_fh;
    close $error_fh;
    return ( $rc, $output, $error );
}

# Default (no -o given): unchanged raw-JSON behavior.
{
    my ( $rc, $output, $error ) = _run_main(
        method => 'GET',
        argv   => ['https://example.test'],
        runner => TestRunner->new(),
    );
    is( $rc, 0, 'default output: exit 0' );
    my $decoded = decode_json($output);
    is( $decoded->{method}, 'GET', 'default output: still raw JSON, unchanged shape' );
}

# -o json explicit: same decoded structure as the default (no behavior
# change) - compared after decoding, not as raw bytes, since JSON::PP's
# key order for two separate hashref instances (one per request() call)
# was never a stable byte-for-byte guarantee even before this ticket,
# in this test or in real separate-process CLI invocations.
{
    my ( $rc_default, $output_default, undef ) = _run_main(
        method => 'GET',
        argv   => ['https://example.test'],
        runner => TestRunner->new(),
    );
    my ( $rc_json, $output_json, undef ) = _run_main(
        method => 'GET',
        argv   => [ 'https://example.test', '--output', 'json' ],
        runner => TestRunner->new(),
    );
    is( $rc_json, $rc_default, '-o json: same exit code as default' );
    is_deeply( decode_json($output_json), decode_json($output_default), '-o json: same decoded structure as the default (no behavior change)' );
}

# -o table: human-readable summary, not raw JSON.
{
    my ( $rc, $output, $error ) = _run_main(
        method => 'GET',
        argv   => [ 'https://example.test', '--output', 'table' ],
        runner => TestRunner->new(),
    );
    is( $rc, 0, '-o table: exit 0' );
    ok( !eval { decode_json($output); 1 }, '-o table: output is not raw JSON' );
    like( $output, qr/method\s+GET/,                  '-o table: shows method' );
    like( $output, qr/requested_url\s+https:\/\/example\.test/, '-o table: shows requested_url' );
    like( $output, qr/title\s+Example Title/,          '-o table: shows title for GET' );
}

# Codex QA-gate review: _render_field_table's undef->empty fallback
# needs a fixture with a genuinely missing rendered field - every
# other table test above supplies a value for every row.
{
    package TestUndefStatusRunner;

    sub new { bless {}, shift }

    sub request {
        my ( $self, %args ) = @_;
        return {
            method        => $args{method},
            requested_url => $args{url},
            final_url     => $args{url},
            status        => undef,
            title         => 'Example Title',
            content_type  => 'text/html',
        };
    }
}

{
    my ( $rc, $output, $error ) = _run_main(
        method => 'GET',
        argv   => [ 'https://example.test', '--output', 'table' ],
        runner => TestUndefStatusRunner->new(),
    );
    is( $rc, 0, '-o table with an undefined field: exit 0' );
    like( $output, qr/status\s*\n/, '-o table with an undefined field: renders as an empty value, not "undef" or a warning' );
}

# -o table: is_captcha=true and a defined script_result both need
# their own coverage - the base TestRunner above always returns
# is_captcha=>0 and no --script is passed in the tests above, so
# _print_table_result's is_captcha ternary and its script_result
# conditional row would otherwise only ever take one branch.
{
    package TestCaptchaScriptRunner;

    sub new { bless {}, shift }

    sub request {
        my ( $self, %args ) = @_;
        return {
            method        => $args{method},
            requested_url => $args{url},
            final_url     => $args{url},
            status        => 200,
            title         => 'Example Title',
            content_type  => 'text/html',
            is_captcha    => 1,
            script_result => $args{script},
        };
    }
}

{
    my ( $rc, $output, $error ) = _run_main(
        method => 'GET',
        argv   => [ 'https://example.test', '--script', 'return 1', '-o', 'table' ],
        runner => TestCaptchaScriptRunner->new(),
    );
    is( $rc, 0, '-o table with -o (short form), is_captcha=true, and --script given: exit 0' );
    like( $output, qr/is_captcha\s+yes/,      '-o table: is_captcha=true renders as yes' );
    like( $output, qr/script_result\s+yes/,   '-o table: a defined script_result gets its own row' );
}

# -o table on POST: no title field (title is GET-only per the result
# payload shape both SKILLS.md and Runner.pm's _run_post agree on).
{
    my ( $rc, $output, $error ) = _run_main(
        method => 'POST',
        argv   => [ 'https://example.test', '--output', 'table' ],
        runner => TestRunner->new(),
    );
    is( $rc, 0, '-o table on POST: exit 0' );
    unlike( $output, qr/^title\b/m, '-o table on POST: no title row (GET-only field)' );
}

# Unsupported value: clear error, exit 2, nothing printed to stdout.
{
    my ( $rc, $output, $error ) = _run_main(
        method => 'GET',
        argv   => [ 'https://example.test', '--output', 'xml' ],
        runner => TestRunner->new(),
    );
    is( $rc, 2, 'unsupported -o value: exit 2' );
    is( $output, q{}, 'unsupported -o value: nothing printed to stdout' );
    like( $error, qr/Unsupported output format: xml/, 'unsupported -o value: names the bad value and expected ones' );
}

# Codex QA-gate review: -o/--output as the LAST token, with no value
# and no --help/--version to bypass extraction, needs its own direct
# test - the earlier "--version --output" cases exercise this
# differently, since --version's own priority check skips extraction
# entirely before this guard is ever reached.
{
    my ( $rc, $output, $error ) = _run_main(
        method => 'GET',
        argv   => [ 'https://example.test', '-o' ],
        runner => TestRunner->new(),
    );
    is( $rc, 2, '-o with no value and no --help/--version: exit 2' );
    like( $error, qr/--output requires a value/, '-o with no value and no --help/--version: names the missing-value error' );
}

# D2B-096's --help/--version top-priority guarantee must still hold
# even with a malformed --output alongside it (Codex round 1 found
# this broken: --output was extracted/validated before execute()'s
# own --help/--version pre-scan ever ran, so a broken --output value
# wrongly won over --help/--version instead of the reverse).
{
    my ( $rc, $output, $error ) = _run_main(
        method => 'GET',
        argv   => [ 'https://example.test', '--help', '--output', 'xml' ],
        runner => TestRunner->new(),
    );
    is( $rc, 0, '--help still wins over a malformed --output value: exit 0' );
    like( $output, qr/Usage: browser\.get/, '--help still wins over a malformed --output value: prints usage' );
}
{
    my ( $rc, $output, $error ) = _run_main(
        method => 'GET',
        argv   => [ 'https://example.test', '--version', '--output' ],
        runner => TestRunner->new(),
    );
    is( $rc, 0, '--version still wins over a missing --output value: exit 0' );
}

# --output=table (equals-form) is also accepted.
{
    my ( $rc, $output, $error ) = _run_main(
        method => 'GET',
        argv   => [ 'https://example.test', '--output=table' ],
        runner => TestRunner->new(),
    );
    is( $rc, 0, '--output=table (equals-form): exit 0' );
    like( $output, qr/method\s+GET/, '--output=table (equals-form): renders a table' );
}

# A literal '--' end-of-options separator stops _extract_output_format's
# own scan too (mirroring Getopt::Long's own semantics, same as the
# existing --help/--version pre-scan) - everything from '--' onward,
# including a literal '--output'/'table' pair, is passed through
# untouched as positional argv rather than being extracted as the
# output-format flag.
{
    my ( $rc, $output, $error ) = _run_main(
        method => 'GET',
        argv   => [ 'https://example.test', '--', '--output', 'table' ],
        runner => TestRunner->new(),
    );
    is( $rc, 2, "a literal -- stops output-format extraction: --output/table pass through as positional args, refused as unexpected" );
    like( $error, qr/Unexpected arguments/, "a literal -- stops output-format extraction: names the leftover positional args" );
}

# -o is out of scope for browser.png/browser.pdf (this ticket's own
# scope.excluded) - passing it there is refused the same way any other
# unrecognized flag is, not silently accepted and ignored.
{
    my ( $rc, $output, $error ) = _run_main(
        method => 'PNG',
        argv   => [ 'https://example.test', '--output', 'table' ],
        runner => TestRunner->new(),
    );
    is( $rc, 2, '-o on browser.png: refused (out of this ticket\'s scope), not silently ignored' );
}

# browser.search: -o table too.
{
    package TestSearchRunner;

    sub new { bless {}, shift }

    sub request {
        my ( $self, %args ) = @_;
        return {
            method     => 'GET',
            is_captcha => 0,
            body       => '<li class="b_algo"><h2><a href="https://example.test/a">Result A</a></h2><div class="b_caption"><p>Snippet A</p></div>',
        };
    }
}

# Codex QA-gate review round 2: _print_search_table_result's
# result-item loop needs a zero-results fixture too - D2B-144 already
# established that a short/trivial body with zero parsed results is a
# genuine successful outcome, not a failure, so the table renderer
# must handle that case cleanly (no numbered rows, result_count 0).
{
    package TestZeroResultsSearchRunner;

    sub new { bless {}, shift }

    sub request {
        my ( $self, %args ) = @_;
        return {
            method     => 'GET',
            is_captcha => 0,
            body       => 'short trivial body',
        };
    }
}

{
    my $output = q{};
    my $error  = q{};
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";
    open my $error_fh,  '>', \$error  or die "Unable to open error scalar: $!";
    my $rc = Browser::CLI::main_search(
        argv      => [ 'test query', '--output', 'table' ],
        runner    => TestZeroResultsSearchRunner->new(),
        output_fh => $output_fh,
        error_fh  => $error_fh,
    );
    close $output_fh;
    close $error_fh;
    is( $rc, 0, 'browser.search -o table with zero results: exit 0 (D2B-144: a short trivial body is success, not failure)' );
    like( $output, qr/result_count\s+0/, 'browser.search -o table with zero results: shows result_count 0' );
    unlike( $output, qr/^\s*\d+\.\s/m, 'browser.search -o table with zero results: no numbered result rows' );
}

# --help still wins over a malformed --output on browser.search too.
{
    my $output = q{};
    my $error  = q{};
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";
    open my $error_fh,  '>', \$error  or die "Unable to open error scalar: $!";
    my $rc = Browser::CLI::main_search(
        argv      => [ 'test query', '--help', '--output', 'xml' ],
        runner    => TestSearchRunner->new(),
        output_fh => $output_fh,
        error_fh  => $error_fh,
    );
    close $output_fh;
    close $error_fh;
    is( $rc, 0, 'browser.search: --help still wins over a malformed --output value: exit 0' );
    like( $output, qr/Usage: browser\.search/, 'browser.search: --help still wins over a malformed --output value: prints usage' );
}

# Codex round 2: browser.search's --version branch needs its own
# regression case too - --help alone doesn't exercise it.
{
    my $output = q{};
    my $error  = q{};
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";
    open my $error_fh,  '>', \$error  or die "Unable to open error scalar: $!";
    my $rc = Browser::CLI::main_search(
        argv      => [ 'test query', '--version', '--output' ],
        runner    => TestSearchRunner->new(),
        output_fh => $output_fh,
        error_fh  => $error_fh,
    );
    close $output_fh;
    close $error_fh;
    is( $rc, 0, 'browser.search: --version still wins over a missing --output value: exit 0' );
}

# browser.search's own -o error-handling branch (no --help/--version
# involved this time) needs direct coverage too.
{
    my $output = q{};
    my $error  = q{};
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";
    open my $error_fh,  '>', \$error  or die "Unable to open error scalar: $!";
    my $rc = Browser::CLI::main_search(
        argv      => [ 'test query', '--output', 'xml' ],
        runner    => TestSearchRunner->new(),
        output_fh => $output_fh,
        error_fh  => $error_fh,
    );
    close $output_fh;
    close $error_fh;
    is( $rc, 2, 'browser.search: unsupported -o value: exit 2' );
    is( $output, q{}, 'browser.search: unsupported -o value: nothing printed to stdout' );
    like( $error, qr/Unsupported output format: xml/, 'browser.search: unsupported -o value: names the bad value' );
}

{
    my $output = q{};
    my $error  = q{};
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";
    open my $error_fh,  '>', \$error  or die "Unable to open error scalar: $!";
    my $rc = Browser::CLI::main_search(
        argv      => [ 'test query', '--output', 'table' ],
        runner    => TestSearchRunner->new(),
        output_fh => $output_fh,
        error_fh  => $error_fh,
    );
    close $output_fh;
    close $error_fh;
    is( $rc, 0, 'browser.search -o table: exit 0' );
    ok( !eval { decode_json($output); 1 }, 'browser.search -o table: output is not raw JSON' );
    like( $output, qr/query\s+test query/,   'browser.search -o table: shows query' );
    like( $output, qr/engine_used\s+bing/,   'browser.search -o table: shows engine_used' );
    like( $output, qr/Result A/,             'browser.search -o table: lists the result title' );
}

done_testing();
