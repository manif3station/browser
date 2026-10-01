package Browser::CLI;

use strict;
use warnings;

use Encode ();
use File::Spec;
use Getopt::Long qw(GetOptionsFromArray);
use JSON::PP qw(encode_json);

use Browser::CLI::TableOutput ();
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
        print {$error_fh} _encode_output_text( sanitize_error($error) ), "\n";
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
        ( $format, $filtered_argv ) = eval { Browser::CLI::TableOutput::extract_output_format( $args{argv} || [] ) };
        if ( my $error = $@ ) {
            print {$error_fh} sanitize_error($error), "\n";
            return 2;
        }
        $args{argv} = $filtered_argv;
    }

    my ( $exit_code, $result ) = _run_and_report_errors( \&execute, $output_fh, $error_fh, %args );
    return $exit_code if defined $exit_code;

    if ( $method eq 'PNG' || $method eq 'PDF' ) {
        print {$output_fh} _encode_output_text( $result->{file} ), "\n";
        return 0;
    }

    return $format eq 'table'
      ? Browser::CLI::TableOutput::print_table_result( $method, $result, $output_fh )
      : _print_json_result_or_report_error( $result, $output_fh, $error_fh );
}

# D2B-096: --help was never a declared option on any of the four
# browser.* commands, so Getopt::Long reported it as an unknown option
# instead of printing usage and exiting cleanly, as is conventional.
sub _usage_get_post_png {
    my ($method) = @_;
    my $verb = $method eq 'GET' ? 'browser.get' : $method eq 'POST' ? 'browser.post' : $method eq 'PNG' ? 'browser.png' : 'browser.pdf';
    my $output_line = ( $method eq 'GET' || $method eq 'POST' )
      ? "  -o, --output FORMAT     json (default, full payload) or table (a human-readable\n"
      . "                          summary - see docs/usage.md; not available on browser.png/browser.pdf)\n"
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
  -o, --output FORMAT     json (default, full payload) or table (a human-readable
                          summary - see docs/usage.md)
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

    # D2B-247: an error raised through Playwright's request code is a Carp
    # backtrace - the message, then tab-indented lines of the form
    # "Package::sub(args) called at FILE line N" (and "eval {...} called at
    # ..."). None of them ends in a period, so the pattern below never matched
    # them and the whole trace was printed: internal file paths, object
    # addresses and the caller's own arguments (14 lines for a mistyped
    # --script). Each such line is dropped, together with the newline before
    # it, so whatever follows the last one (a closing parenthesis in an
    # aggregated search failure, say) stays attached to the message.
    $error =~ s{\n\t[^\n]*?\bcalled at \S+ line \d+\.?}{}g;

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
# D2B-239: @ARGV is raw bytes (see D2B-086 above) but the library below
# takes character strings - uri_escape_utf8 in Browser::Search and the
# json/table output all encode characters - so a non-ASCII URL or query
# was encoded twice (q=caf%C3%83%C2%A9 for 'café') and the search engine
# was asked for the wrong term. The positional url and query are decoded
# where they leave execute()/execute_search(), and (D2B-240) the data,
# script and file option values at the call in execute() - deliberately
# not all of argv: decoding everything would put characters into error
# messages that echo user text and would break the byte-sequence match in
# _trim_engine_name. Anything that is not valid UTF-8, or is already a
# character string, is returned unchanged.
sub _decode_argv_text {
    my ($value) = @_;
    return $value if !defined $value;
    my $copy    = $value;
    my $decoded = eval { Encode::decode( 'UTF-8', $copy, Encode::FB_CROAK() ) };
    return defined $decoded ? $decoded : $value;
}

# D2B-240: the counterpart of _decode_argv_text for text printed with no
# encoding layer. A decoded value is a UTF-8-flagged character string and
# must be encoded on the way out; anything else (a default temp path from
# $TMPDIR, an error that only echoes raw argv bytes) is already bytes and
# is printed as it is - encoding it again would double-encode it.
sub _encode_output_text {
    my ($text) = @_;
    return $text if !defined $text || !utf8::is_utf8($text);
    return Encode::encode( 'UTF-8', $text );
}

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
    $url = _decode_argv_text($url);
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

    # D2B-240: same bytes-versus-characters problem D2B-239 fixed for the
    # positional url/query - Playwright's Perl client JSON-encodes every
    # command argument as characters, so these three were encoded twice
    # (a POST body, a page script and an output file name). Decoded here
    # and only here: the values other argv-echoing errors print (engine
    # names, unexpected arguments, ...) must stay bytes.
    # D2B-243: except the script in controller mode. There it is Perl
    # source that Browser::Runner string-evals, so decoding it turned its
    # literals into characters and an accented literal the script printed
    # came out as a lone invalid byte; the runner gets it as typed.
    $options{$_} = _decode_argv_text( $options{$_} ) for qw(data file);
    $options{script} = _decode_argv_text( $options{script} ) if !$controller;
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
        ( $format, $filtered_argv ) = eval { Browser::CLI::TableOutput::extract_output_format( $args{argv} || [] ) };
        if ( my $error = $@ ) {
            print {$error_fh} sanitize_error($error), "\n";
            return 2;
        }
        $args{argv} = $filtered_argv;
    }

    my ( $exit_code, $result ) = _run_and_report_errors( \&execute_search, $output_fh, $error_fh, %args );
    return $exit_code if defined $exit_code;

    return $format eq 'table'
      ? Browser::CLI::TableOutput::print_search_table_result( $result, $output_fh )
      : _print_json_result_or_report_error( $result, $output_fh, $error_fh );
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
    $query = _decode_argv_text($query);
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
