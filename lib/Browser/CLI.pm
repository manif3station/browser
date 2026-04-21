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

    my $result = eval { execute(%args) };
    if ( my $error = $@ ) {
        chomp $error;
        print {$error_fh} "$error\n";
        return 2;
    }

    print {$output_fh} encode_json($result), "\n";
    return 0;
}

sub execute {
    my (%args) = @_;
    my @argv = @{ $args{argv} || [] };
    my $method = uc( $args{method} || q{} );
    die "Unsupported method: $method" if $method ne 'GET' && $method ne 'POST';

    my %options = (
        browser    => 'chrome',
        'headless' => 1,
    );
    GetOptionsFromArray(
        \@argv,
        'script=s'     => \$options{script},
        'data=s'       => \$options{data},
        'browser=s'    => \$options{browser},
        'headless!'    => \$options{headless},
        'timeout-ms=i' => \$options{timeout_ms},
    ) or die "Invalid options";

    my $url = shift @argv or die "Missing URL";
    die "Unexpected arguments: @argv" if @argv;

    my $runner = $args{runner} || Browser::Runner->new();
    return $runner->request(
        method      => $method,
        url         => $url,
        script      => $options{script},
        data        => $options{data},
        browser     => $options{browser},
        headless    => $options{headless},
        timeout_ms  => $options{timeout_ms},
    );
}

1;
