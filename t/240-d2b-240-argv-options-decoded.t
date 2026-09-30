use strict;
use warnings;

use Test::More;
use Encode qw(decode encode FB_CROAK LEAVE_SRC);

use lib 'lib';
use Browser::CLI;

# D2B-240: follow-up to D2B-239, which decoded only the positional URL and
# search query. The --data, --script and --file option values also come
# straight from @ARGV as raw UTF-8 bytes, but Playwright's Perl client
# JSON-encodes every command argument with encode_json, which treats its
# input as characters - so a non-ASCII POST body, page script or output
# file name was encoded twice on the way to the browser. These tests hand
# the CLI real UTF-8 bytes, exactly as @ARGV delivers them, and check what
# the runner receives and what is printed.
#
# It also pins the reason the rest of argv is NOT decoded: an error message
# that echoes argv text is printed with no encoding layer, so it is only
# correct while that text stays bytes.

# A failing comparison prints both values as diagnostics; without a layer
# the non-ASCII ones make the test framework itself warn, which would
# otherwise be counted by the no-warnings check below.
binmode( Test::More->builder->$_, ':encoding(UTF-8)' ) for qw(output failure_output todo_output);

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };

{
    package RecordingRunner;

    sub new { bless { calls => [] }, shift }

    sub request {
        my ( $self, %args ) = @_;
        push @{ $self->{calls} }, {%args};
        return {
            method        => $args{method},
            requested_url => $args{url},
            final_url     => $args{url},
            status        => 200,
            title         => 'Title',
            content_type  => 'text/html',
            headers       => {},
            body          => q{},
            body_text     => q{},
            is_captcha    => 0,
            file          => $args{file},
        };
    }
}

sub _run {
    my (%args) = @_;
    my $runner = RecordingRunner->new();
    my ( $output, $error ) = ( q{}, q{} );
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";
    open my $error_fh,  '>', \$error  or die "Unable to open error scalar: $!";
    my $rc = Browser::CLI::main( %args, runner => $runner, output_fh => $output_fh, error_fh => $error_fh );
    close $output_fh;
    close $error_fh;
    return ( $rc, $output, $error, $runner->{calls}[0] );
}

sub _chars {
    my ($bytes) = @_;
    return eval { decode( 'UTF-8', $bytes, FB_CROAK | LEAVE_SRC ) };
}

my $cafe_bytes = encode( 'UTF-8', "caf\x{e9}" );
my $cjk_bytes  = encode( 'UTF-8', "\x{4e2d}\x{6587}" );

# 1. --data on browser.post reaches the runner as characters.
{
    my ( $rc, undef, $error, $call ) = _run( method => 'POST', argv => [ 'https://example.test', '--data', $cafe_bytes ] );
    is( $rc, 0, 'post with an accented --data exits 0' ) or diag($error);
    is( $call->{data}, "caf\x{e9}", '--data reaches the runner as the decoded character string' );
}

# 2. --script on browser.get reaches the runner as characters (page script).
{
    my ( undef, undef, undef, $call ) = _run( method => 'GET', argv => [ 'https://example.test', '--script', "document.title = '$cafe_bytes'" ] );
    is( $call->{script}, "document.title = 'caf\x{e9}'", '--script reaches the runner as the decoded character string' );
}

# 3. --file on png/pdf reaches the runner as characters, and the printed
#    destination path is valid UTF-8 for the original name.
for my $case (
    [ 'PNG', 'an accented Latin-1-range name',  "/tmp/caf\x{e9}.png", "/tmp/$cafe_bytes.png" ],
    [ 'PDF', 'a name with characters above U+00FF', "/tmp/\x{4e2d}\x{6587}.pdf", "/tmp/$cjk_bytes.pdf" ],
  )
{
    my ( $method, $label, $expected_chars, $argv_bytes ) = @$case;
    my ( $rc, $output, $error, $call ) = _run( method => $method, argv => [ 'https://example.test', '--file', $argv_bytes ] );
    is( $rc, 0, "$method with --file naming $label exits 0" ) or diag($error);
    is( $call->{file}, $expected_chars, "$method --file naming $label reaches the runner as the decoded character string" );
    my $printed = _chars($output);
    ok( defined $printed, "the destination path printed for $method with $label is valid UTF-8" );
    is( $printed, "$expected_chars\n", "the destination path printed for $method with $label is the original name, not double-encoded" );
}

# 4. Pass-through guards: input that must NOT change.
{
    my ( undef, undef, undef, $ascii ) = _run( method => 'POST', argv => [ 'https://example.test', '--data', 'plain' ] );
    is( $ascii->{data}, 'plain', 'ASCII --data is unchanged' );

    my ( undef, undef, undef, $chars ) = _run( method => 'POST', argv => [ 'https://example.test', '--data', "caf\x{e9}\x{2014}" ] );
    is( $chars->{data}, "caf\x{e9}\x{2014}", '--data that is already a character string is not decoded again' );

    my ( undef, undef, undef, $latin1 ) = _run( method => 'POST', argv => [ 'https://example.test', '--data', "caf\xE9" ] );
    is( $latin1->{data}, "caf\xE9", '--data that is not valid UTF-8 is passed through unchanged' );
}

# 5. Error messages that echo argv text still print the original bytes:
#    they have no encoding layer, so decoding these values would break them.
{
    my ( $rc, undef, $error ) = _run( method => 'GET', argv => [ 'https://example.test', $cafe_bytes ] );
    is( $rc, 2, 'an unexpected extra argument exits 2' );
    like( $error, qr/\AUnexpected arguments: \Q$cafe_bytes\E\n\z/, 'the error message echoes the argv text as the original bytes, unchanged' );
}

# 6. An error raised further down that echoes the decoded --file value (the
#    real Runner::Capture dies with '--file points at an existing
#    directory: PATH') must still print the original bytes: the value is
#    now a character string, so the error output has to be encoded.
{
    package DyingRunner;
    sub new { bless {}, shift }
    sub request { my ( $self, %args ) = @_; die "--file points at an existing directory: $args{file}\n" }
}

{
    my ( $output, $error ) = ( q{}, q{} );
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";
    open my $error_fh,  '>', \$error  or die "Unable to open error scalar: $!";
    my $rc = Browser::CLI::main(
        method    => 'PNG',
        argv      => [ 'https://example.test', '--file', "/tmp/$cafe_bytes" ],
        runner    => DyingRunner->new(),
        output_fh => $output_fh,
        error_fh  => $error_fh,
    );
    close $output_fh;
    close $error_fh;
    is( $rc, 2, 'a runner failure that echoes the --file path exits 2' );
    is( $error, "--file points at an existing directory: /tmp/$cafe_bytes\n", 'the error echoing a non-ASCII --file path prints the original bytes, not mojibake or a Wide character' );
}

is_deeply( \@warnings, [], 'no warnings were emitted' ) or diag( join q{}, @warnings );

done_testing();
