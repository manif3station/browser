package Browser::CLI;

use strict;
use warnings;

use Getopt::Long qw(GetOptionsFromArray);
use JSON::PP qw(encode_json);

use Browser::Runner;

sub main {
    my (%args) = @_;
    my $output_fh = $args{output_fh} || \*STDOUT;
    my $error_fh  = $args{error_fh}  || \*STDERR;
    my $input_fh  = $args{input_fh}  || \*STDIN;

    my $result = eval { execute(%args) };
    if ( my $error = $@ ) {
        chomp $error;
        print {$error_fh} "$error\n";
        return 2;
    }

    if ( uc( $args{method} || q{} ) eq 'PNG' ) {
        print {$output_fh} $result->{file}, "\n";
        return 0;
    }

    print {$output_fh} encode_json($result), "\n";
    return 0;
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
    ) or die "Invalid options";

    my $url = shift @argv or die "Missing URL";
    die "Unexpected arguments: @argv" if @argv;

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

1;
