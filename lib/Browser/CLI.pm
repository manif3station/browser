package Browser::CLI;

use strict;
use warnings;

use File::Spec;
use Getopt::Long qw(GetOptionsFromArray);
use JSON::PP qw(encode_json);

use Browser::Runner;
use Browser::Runner::NodeRuntime ();
use Browser::Search ();

# D2B-123: shared by main()/main_search() - both eval their own executor,
# report a sanitized error (exit 2) or print pre-rendered help (exit 0)
# identically; only the final successful-result formatting differs
# between callers, so that part stays in each caller instead of here.
sub _run_and_report_errors {
    my ( $executor, $output_fh, $error_fh, %args ) = @_;
    my $result = eval { $executor->(%args) };
    if ( my $error = $@ ) {
        print {$error_fh} sanitize_error($error), "\n";
        return ( 2, undef );
    }

    if ( ref $result eq 'HASH' && $result->{help} ) {
        print {$output_fh} $result->{usage};
        return ( 0, undef );
    }

    if ( ref $result eq 'HASH' && $result->{version} ) {
        print {$output_fh} $result->{version_string}, "\n";
        return ( 0, undef );
    }

    return ( undef, $result );
}

# D2B-139: shared by main()/main_search() - encode_json can itself die
# (e.g. on a circular structure), and that failure must go through the
# same sanitize_error()/exit-2 convention as every other failure in
# this file, not propagate uncaught.
sub _print_json_result_or_report_error {
    my ( $result, $output_fh, $error_fh ) = @_;
    my $json = eval { encode_json($result) };
    if ( my $error = $@ ) {
        print {$error_fh} sanitize_error($error), "\n";
        return 2;
    }
    print {$output_fh} $json, "\n";
    return 0;
}

sub main {
    my (%args) = @_;
    my $output_fh = $args{output_fh} || \*STDOUT;
    my $error_fh  = $args{error_fh}  || \*STDERR;
    my $method    = uc( $args{method} || q{} );

    # D2B-208: -o/--output is only wired up for GET/POST here - PNG/PDF
    # keep printing just the destination file path (out of this
    # ticket's scope, see its own scope.excluded), so -o on those two
    # falls straight through to execute()'s own GetOptionsFromArray,
    # which refuses it as an unrecognized option, same as any other
    # flag those two commands don't support.
    #
    # Codex review round 1: --help/--version must keep winning over a
    # malformed sibling flag (D2B-096) even when that sibling is this
    # new --output - checked first here, exactly mirroring execute()'s
    # own pre-Getopt::Long scan, so a broken --output can never
    # suppress --help/--version the way D2B-096 already guarantees for
    # every other flag.
    my $format = 'json';
    if ( ( $method eq 'GET' || $method eq 'POST' )
        && !_argv_requests_help( $args{argv} || [] )
        && !_argv_requests_version( $args{argv} || [] ) )
    {
        my $filtered_argv;
        ( $format, $filtered_argv ) = eval { _extract_output_format( $args{argv} || [] ) };
        if ( my $error = $@ ) {
            print {$error_fh} sanitize_error($error), "\n";
            return 2;
        }
        $args{argv} = $filtered_argv;
    }

    my ( $exit_code, $result ) = _run_and_report_errors( \&execute, $output_fh, $error_fh, %args );
    return $exit_code if defined $exit_code;

    if ( $method eq 'PNG' || $method eq 'PDF' ) {
        print {$output_fh} $result->{file}, "\n";
        return 0;
    }

    return $format eq 'table'
      ? _print_table_result( $method, $result, $output_fh )
      : _print_json_result_or_report_error( $result, $output_fh, $error_fh );
}

# D2B-208: this workspace's own DD skill CLI output contract
# (~/projects/skills/CLAUDE.md) documents "default output is a
# human-readable summary (pretty table); -o json emits the full
# underlying payload" - this skill's commands never had an -o flag at
# all. -o/--output is pre-scanned here and stripped from argv before
# it ever reaches execute()/execute_search()'s own GetOptionsFromArray
# call, the same architecture --help/--version already use above (see
# _argv_requests_help/_argv_requests_version) - keeping this a pure
# CLI-presentation-layer concern that never has to flow through
# execute()'s existing return-value contract, which is also used
# directly by other callers per this skill's own README ("at the Perl
# API level"). json is kept as the default (byte-identical to every
# existing caller's current behavior, including this suite's own
# 1000+ assertions) rather than flipping the default to table, since
# that would be a breaking change to every existing consumer of this
# skill's JSON output - table is added as a new opt-in instead.
sub _extract_output_format {
    my ($argv) = @_;
    my @remaining;
    my $format;
    my $i = 0;
    while ( $i <= $#$argv ) {
        my $tok = $argv->[$i];
        if ( $tok eq '--' ) {
            push @remaining, @{$argv}[ $i .. $#$argv ];
            last;
        }
        if ( $tok eq '-o' || $tok eq '--output' ) {
            die "--output requires a value (json or table)\n" if $i == $#$argv;
            $format = $argv->[ $i + 1 ];
            $i += 2;
            next;
        }
        if ( $tok =~ /\A--output=(.*)\z/s ) {
            $format = $1;
            $i += 1;
            next;
        }
        push @remaining, $tok;
        $i += 1;
    }
    $format = 'json' if !defined $format;
    die "Unsupported output format: $format (expected json or table)\n"
      if $format ne 'json' && $format ne 'table';
    return ( $format, \@remaining );
}

# D2B-208: intentionally a summary, not the full payload - body/
# body_text/headers are omitted here exactly as the workspace's own
# convention distinguishes a table summary from -o json's full
# underlying payload; get the full detail from -o json instead.
sub _print_table_result {
    my ( $method, $result, $output_fh ) = @_;
    my @rows = (
        [ method        => $result->{method} ],
        [ requested_url => $result->{requested_url} ],
        [ final_url     => $result->{final_url} ],
        [ status        => $result->{status} ],
        [ content_type  => $result->{content_type} ],
        [ is_captcha    => $result->{is_captcha} ? 'yes' : 'no' ],
    );
    push @rows, [ title => $result->{title} ] if $method eq 'GET';
    push @rows, [ script_result => 'yes (see -o json for the value)' ] if defined $result->{script_result};
    print {$output_fh} _render_field_table( \@rows );
    return 0;
}

sub _render_field_table {
    my ($rows) = @_;
    my $label_width = 0;
    for my $row (@$rows) {
        $label_width = length( $row->[0] ) if length( $row->[0] ) > $label_width;
    }
    my $text = q{};
    for my $row (@$rows) {
        my ( $label, $value ) = @$row;
        $value = q{} if !defined $value;
        $text .= sprintf "%-*s  %s\n", $label_width, $label, $value;
    }
    return $text;
}

# D2B-096: --help was never a declared option on any of the four
# browser.* commands, so Getopt::Long reported it as an unknown option
# instead of printing usage and exiting cleanly, as is conventional.
sub _usage_get_post_png {
    my ($method) = @_;
    my $verb = $method eq 'GET' ? 'browser.get' : $method eq 'POST' ? 'browser.post' : $method eq 'PNG' ? 'browser.png' : 'browser.pdf';
    my $output_line = ( $method eq 'GET' || $method eq 'POST' )
      ? "  -o, --output FORMAT     json (default, unchanged payload) or table (D2B-208, a human-\n"
      . "                          readable summary - see docs/usage.md; not available on browser.png/browser.pdf)\n"
      : q{};
    return <<USAGE;
Usage: $verb URL [OPTIONS]

  --script TEXT          Run TEXT as a page-context script (a JS page.evaluate() call,
                          or a Perl controller script with --playwright/--agent/--flow)
  --jquery                Inject jQuery before running --script
  --playwright            Run --script as a Perl controller script with \$page/\$browser
  --agent                 Alias for --playwright
  --flow                  Alias for --playwright
  --data TEXT             POST body (browser.post only)
  --browser NAME          chrome (default), chromium, firefox, webkit, or edge (case-insensitive) -
                          browser.pdf only supports chrome/chromium/edge (Chromium-only PDF export)
  --headless / --no-headless   Run headless (default) or with a visible browser window
  --ask / --askme         Open a visible browser and wait for manual confirmation before continuing
  --wait-until MODE       load, domcontentloaded, or networkidle (browser.get/browser.png/browser.pdf only)
  --timeout-ms N          Navigation timeout in milliseconds (browser.get/browser.png/browser.pdf only)
  --file PATH             Screenshot/PDF destination path (browser.png/browser.pdf only)
${output_line}  --help                  Print this usage text and exit
  --version               Print the installed skill's version and exit
USAGE
}

sub _usage_search {
    return <<'USAGE';
Usage: browser.search QUERY [OPTIONS]

  --engine NAME           Use only this engine (bing, google, or duckduckgo)
  --engines LIST          Try these engines in order, comma-separated (cannot combine with --engine)
  --max N                 Maximum results to return (default 10)
  --timeout-ms N          Per-engine request timeout in milliseconds
  -o, --output FORMAT     json (default, unchanged payload) or table (D2B-208, a human-
                          readable summary - see docs/usage.md)
  --help                  Print this usage text and exit
  --version               Print the installed skill's version and exit
USAGE
}

# D2B-147: public (not underscore-prefixed) since cli/skills, a
# standalone script outside this module's own main()/execute() flow,
# reuses it to match the same exit-2 error convention.
sub sanitize_error {
    my ($error) = @_;
    chomp $error;

    # D2B-180: was anchored to \z, so only a TRAILING "at FILE line N."
    # suffix was ever stripped. A message can carry more than one - e.g.
    # Browser::Search::search()'s aggregated failure text can embed an
    # earlier inner die's own location suffix ahead of the outer die's
    # trailing one - so this strips every occurrence, not just the last.
    $error =~ s{\s+at\s+\S+\s+line\s+\d+\.}{}g;
    return $error;
}

# D2B-086: Perl's \s only matches ASCII whitespace, so a copy-pasted
# engine name padded with a non-breaking space survived this trim and
# was rejected as unknown. @ARGV arrives as raw, undecoded bytes (this
# codebase never decodes argv as UTF-8), so a non-breaking space
# typed/pasted as UTF-8 is the two-byte sequence \xC2\xA0, not the
# single decoded U+00A0 character - the regex must match that literal
# byte sequence, not \x{A0}, or it only strips the trailing byte and
# leaves a mangled \xC2 behind.
# D2B-127: this trim was only ever applied to --engines' list-parsing,
# never to the singular --engine value, so the identical padded-name
# rejection D2B-086 fixed for one flag still happened on the other -
# applying the same regex to both closes that gap.
# D2B-151: the regex was duplicated verbatim in both call sites -
# extracted here so a future revision only needs one place to change.
sub _trim_engine_name {
    my ($name) = @_;
    $name =~ s/\A(?:\s|\xC2\xA0)+|(?:\s|\xC2\xA0)+\z//g;
    return $name;
}

# D2B-096 (Codex review round 1): --help must take priority over EVERY
# other validation, including a malformed/unknown OTHER option (e.g.
# --help --not-a-real-flag, or --help --data with no value) - but
# Getopt::Long parses the whole argv list and dies on those before a
# post-parse 'help!' check ever runs. A literal --help anywhere in argv
# is checked here, before GetOptionsFromArray is even called, so a
# broken sibling flag can never suppress --help's own short-circuit.
sub _argv_requests_help {
    my ($argv) = @_;
    return !!grep { $_ eq '--help' } _argv_before_double_dash($argv);
}

# D2B-124: --version mirrors --help's own top-priority, pre-parse
# short-circuit exactly (see D2B-096 above) - checked in execute()/
# execute_search() right after the --help check, so --help still wins
# when both are given, and a broken sibling flag can never suppress it.
sub _argv_requests_version {
    my ($argv) = @_;
    return !!grep { $_ eq '--version' } _argv_before_double_dash($argv);
}

# D2B-186: the raw pre-Getopt scan above must stop at a literal '--'
# end-of-options separator, mirroring Getopt::Long's own semantics -
# otherwise SKILLS.md's documented `-- VALUE` escape for a leading-dash
# positional argument is defeated whenever VALUE is itself the literal
# string --help/--version.
sub _argv_before_double_dash {
    my ($argv) = @_;
    for my $i ( 0 .. $#$argv ) {
        return @{$argv}[ 0 .. $i - 1 ] if $argv->[$i] eq '--';
    }
    return @$argv;
}

# .env's VERSION line is the source of truth for the installed skill's
# version. Browser::Runner::NodeRuntime::skill_root() (D2B-154: public)
# already solves the exact path-resolution problem
# (DEVELOPER_DASHBOARD_SKILL_ROOT env var, then cwd-based detection, then
# module-path fallback) this needs - reused here rather than duplicated.
sub _read_version {
    my $env_path = File::Spec->catfile( Browser::Runner::NodeRuntime::skill_root(), '.env' );
    open my $fh, '<', $env_path or die "Unable to read $env_path: $!";
    my ($version_line) = grep { /^VERSION=/ } <$fh>;
    close $fh;
    die "No VERSION line found in $env_path" if !defined $version_line;
    chomp $version_line;
    $version_line =~ s/\r\z//;
    $version_line =~ s/^VERSION=//;
    die "VERSION line in $env_path is empty" if $version_line eq q{};
    return $version_line;
}

sub execute {
    my (%args) = @_;
    my @argv = @{ $args{argv} || [] };
    my $method = uc( $args{method} || q{} );
    die "Unsupported method: $method" if $method ne 'GET' && $method ne 'POST' && $method ne 'PNG' && $method ne 'PDF';

    return { help => 1, usage => _usage_get_post_png($method) } if _argv_requests_help( \@argv );
    return { version => 1, version_string => _read_version() } if _argv_requests_version( \@argv );

    my %options = (
        browser    => 'chrome',
        'headless' => 1,
    );
    my @getopt_warnings;
    my $getopt_ok = do {
        local $SIG{__WARN__} = sub { push @getopt_warnings, $_[0] };
        GetOptionsFromArray(
            \@argv,
            'script=s'     => \$options{script},
            'jquery!'      => \$options{jquery},
            'playwright!'  => \$options{playwright},
            'agent!'       => \$options{agent},
            'flow!'        => \$options{flow},
            'data=s'       => \$options{data},
            'browser=s'    => \$options{browser},
            'headless!'    => \$options{headless},
            'ask!'         => \$options{ask},
            'askme!'       => \$options{askme},
            'wait-until=s' => \$options{wait_until},
            'timeout-ms=i' => \$options{timeout_ms},
            'file=s'       => \$options{file},
        );
    };
    die "Invalid options: " . sanitize_error( join q{}, @getopt_warnings ) if !$getopt_ok;

    my $url = shift @argv;
    die "Missing URL" if !defined $url || $url =~ /\A\s*\z/;
    die "Unexpected arguments: @argv" if @argv;

    die "--timeout-ms must not be negative"
      if defined $options{timeout_ms} && $options{timeout_ms} < 0;

    my @flag_guards = (
        [ data       => 'browser.post',                       sub { $_[0] ne 'POST' } ],
        [ wait_until => 'browser.get/browser.png/browser.pdf', sub { $_[0] eq 'POST' } ],
        [ timeout_ms => 'browser.get/browser.png/browser.pdf', sub { $_[0] eq 'POST' } ],
        [ file       => 'browser.png/browser.pdf',             sub { $_[0] ne 'PNG' && $_[0] ne 'PDF' } ],
    );
    for my $guard (@flag_guards) {
        my ( $key, $reader, $blocked ) = @$guard;
        ( my $flag = $key ) =~ tr/_/-/;
        die "--$flag is only read by $reader - it has no effect on $method"
          if defined $options{$key} && $blocked->($method);
    }

    my $interactive = $options{ask} || $options{askme} ? 1 : 0;
    my $controller = $options{playwright} || $options{agent} || $options{flow} ? 1 : 0;
    $options{headless} = 0 if $interactive;

    my $runner = $args{runner} || Browser::Runner->new();
    return $runner->request(
        method      => $method,
        url         => $url,
        script      => $options{script},
        jquery      => $options{jquery},
        controller  => $controller,
        data        => $options{data},
        browser     => $options{browser},
        headless    => $options{headless},
        interactive => $interactive,
        wait_until  => $options{wait_until},
        timeout_ms  => $options{timeout_ms},
        file        => $options{file},
        input_fh    => $args{input_fh} || \*STDIN,
        prompt_fh   => $args{error_fh} || \*STDERR,
    );
}

sub main_search {
    my (%args) = @_;
    my $output_fh = $args{output_fh} || \*STDOUT;
    my $error_fh  = $args{error_fh}  || \*STDERR;

    # Codex review round 1: same D2B-096 priority fix as main() above -
    # --help/--version must win over a malformed --output here too.
    my $format = 'json';
    if ( !_argv_requests_help( $args{argv} || [] ) && !_argv_requests_version( $args{argv} || [] ) ) {
        my $filtered_argv;
        ( $format, $filtered_argv ) = eval { _extract_output_format( $args{argv} || [] ) };
        if ( my $error = $@ ) {
            print {$error_fh} sanitize_error($error), "\n";
            return 2;
        }
        $args{argv} = $filtered_argv;
    }

    my ( $exit_code, $result ) = _run_and_report_errors( \&execute_search, $output_fh, $error_fh, %args );
    return $exit_code if defined $exit_code;

    return $format eq 'table'
      ? _print_search_table_result( $result, $output_fh )
      : _print_json_result_or_report_error( $result, $output_fh, $error_fh );
}

sub _print_search_table_result {
    my ( $result, $output_fh ) = @_;
    my @rows = (
        [ query         => $result->{query} ],
        [ engine_used   => $result->{engine_used} ],
        [ engines_tried => join( ', ', @{ $result->{engines_tried} || [] } ) ],
        [ result_count  => scalar @{ $result->{results} || [] } ],
    );
    print {$output_fh} _render_field_table( \@rows );
    for my $item ( @{ $result->{results} || [] } ) {
        print {$output_fh} sprintf( "  %d. %s\n     %s\n", $item->{rank}, $item->{title}, $item->{url} );
    }
    return 0;
}

sub execute_search {
    my (%args) = @_;
    my @argv = @{ $args{argv} || [] };

    return { help => 1, usage => _usage_search() } if _argv_requests_help( \@argv );
    return { version => 1, version_string => _read_version() } if _argv_requests_version( \@argv );

    my %options = ( max => 10 );
    my @getopt_warnings;
    my $getopt_ok = do {
        local $SIG{__WARN__} = sub { push @getopt_warnings, $_[0] };
        GetOptionsFromArray(
            \@argv,
            'engine=s'     => \$options{engine},
            'engines=s'    => \$options{engines},
            'max=i'        => \$options{max},
            'timeout-ms=i' => \$options{timeout_ms},
        );
    };
    die "Invalid options: " . sanitize_error( join q{}, @getopt_warnings ) if !$getopt_ok;

    my $query = shift @argv;
    die "Missing query" if !defined $query || $query =~ /\A\s*\z/;
    die "Unexpected arguments: @argv" if @argv;

    die "--max must not be negative" if $options{max} < 0;

    die "--timeout-ms must not be negative"
      if defined $options{timeout_ms} && $options{timeout_ms} < 0;

    die "--engine and --engines cannot both be given"
      if defined $options{engine} && defined $options{engines};

    my @requested_names;
    if ( defined $options{engine} ) {
        my $trimmed = _trim_engine_name( $options{engine} );
        # A whitespace-only --engine value trims to empty - refuse it
        # with the same specific message --engines already gives an
        # all-empty list, rather than falling through to the generic
        # "Unknown engine: " lookup failure with a blank name.
        die "--engine named no engine at all" if $trimmed eq q{};
        push @requested_names, $trimmed;
    }
    push @requested_names, grep { $_ ne q{} } map { _trim_engine_name($_) } split /,/, $options{engines} if defined $options{engines};

    die "--engines named no engines at all" if defined $options{engines} && !@requested_names;

    my @engines;
    if (@requested_names) {
        my %by_name = map { lc( $_->{name} ) => $_ } Browser::Search::default_engines();
        my %seen;
        for my $name (@requested_names) {
            my $key = lc $name;
            die "Unknown engine: $name" if !exists $by_name{$key};
            next if $seen{$key}++;
            push @engines, $by_name{$key};
        }
    }

    return Browser::Search::search(
        query      => $query,
        max        => $options{max},
        ( @engines ? ( engines => \@engines ) : () ),
        ( defined $options{timeout_ms} ? ( timeout_ms => $options{timeout_ms} ) : () ),
        runner     => $args{runner},
    );
}

1;
