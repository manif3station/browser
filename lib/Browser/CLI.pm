package Browser::CLI;

use strict;
use warnings;

use Getopt::Long qw(GetOptionsFromArray);
use JSON::PP qw(encode_json);

use Browser::Runner;
use Browser::Search ();

sub main {
    my (%args) = @_;
    my $output_fh = $args{output_fh} || \*STDOUT;
    my $error_fh  = $args{error_fh}  || \*STDERR;

    my $result = eval { execute(%args) };
    if ( my $error = $@ ) {
        print {$error_fh} _sanitize_error($error), "\n";
        return 2;
    }

    if ( uc( $args{method} || q{} ) eq 'PNG' ) {
        print {$output_fh} $result->{file}, "\n";
        return 0;
    }

    print {$output_fh} encode_json($result), "\n";
    return 0;
}

sub _sanitize_error {
    my ($error) = @_;
    chomp $error;
    $error =~ s{\s+at\s+\S+\s+line\s+\d+\.\z}{};
    return $error;
}

sub execute {
    my (%args) = @_;
    my @argv = @{ $args{argv} || [] };
    my $method = uc( $args{method} || q{} );
    die "Unsupported method: $method" if $method ne 'GET' && $method ne 'POST' && $method ne 'PNG';

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
    die "Invalid options: " . _sanitize_error( join q{}, @getopt_warnings ) if !$getopt_ok;

    my $url = shift @argv;
    die "Missing URL" if !defined $url || $url eq q{};
    die "Unexpected arguments: @argv" if @argv;

    die "--timeout-ms must not be negative"
      if defined $options{timeout_ms} && $options{timeout_ms} < 0;

    my @flag_guards = (
        [ data       => 'browser.post',           sub { $_[0] ne 'POST' } ],
        [ wait_until => 'browser.get/browser.png', sub { $_[0] eq 'POST' } ],
        [ timeout_ms => 'browser.get/browser.png', sub { $_[0] eq 'POST' } ],
        [ file       => 'browser.png',             sub { $_[0] ne 'PNG' } ],
    );
    for my $guard (@flag_guards) {
        my ( $key, $reader, $blocked ) = @$guard;
        my $flag = $key eq 'wait_until' ? 'wait-until' : $key eq 'timeout_ms' ? 'timeout-ms' : $key;
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

    my $result = eval { execute_search(%args) };
    if ( my $error = $@ ) {
        print {$error_fh} _sanitize_error($error), "\n";
        return 2;
    }

    print {$output_fh} encode_json($result), "\n";
    return 0;
}

sub execute_search {
    my (%args) = @_;
    my @argv = @{ $args{argv} || [] };

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
    die "Invalid options: " . _sanitize_error( join q{}, @getopt_warnings ) if !$getopt_ok;

    my $query = shift @argv;
    die "Missing query" if !defined $query || $query =~ /\A\s*\z/;
    die "Unexpected arguments: @argv" if @argv;

    die "--max must not be negative" if $options{max} < 0;

    die "--timeout-ms must not be negative"
      if defined $options{timeout_ms} && $options{timeout_ms} < 0;

    die "--engine and --engines cannot both be given"
      if defined $options{engine} && defined $options{engines};

    my @requested_names;
    push @requested_names, $options{engine} if defined $options{engine};
    # D2B-086: Perl's \s only matches ASCII whitespace, so a
    # copy-pasted engine name padded with a non-breaking space
    # survived this trim and was rejected as unknown. @ARGV arrives as
    # raw, undecoded bytes (this codebase never decodes argv as
    # UTF-8), so a non-breaking space typed/pasted as UTF-8 is the
    # two-byte sequence \xC2\xA0, not the single decoded U+00A0
    # character - the regex must match that literal byte sequence,
    # not \x{A0}, or it only strips the trailing byte and leaves a
    # mangled \xC2 behind.
    push @requested_names, grep { $_ ne q{} } map { s/\A(?:\s|\xC2\xA0)+|(?:\s|\xC2\xA0)+\z//g; $_ } split /,/, $options{engines} if defined $options{engines};

    die "--engines named no engines at all" if defined $options{engines} && !@requested_names;

    my @engines;
    if (@requested_names) {
        my %by_name = map { lc( $_->{name} ) => $_ } Browser::Search::_default_engines();
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
