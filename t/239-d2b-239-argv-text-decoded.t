use strict;
use warnings;

use Test::More;
use Encode qw(decode encode FB_CROAK LEAVE_SRC);
use JSON::PP qw(decode_json);

use lib 'lib';
use Browser::CLI;

# D2B-239: the positional URL and search query come straight from @ARGV,
# which is raw undecoded bytes (see the D2B-086 note in Browser::CLI), but
# the library below expects character strings. uri_escape_utf8 therefore
# double-encoded a non-ASCII search query (caf + C3 A9 became
# q=caf%C3%83%C2%A9, so the search engine was asked for 'cafÃ©'), and the
# query/requested_url values echoed in json and table output were
# double-encoded too. These tests hand the CLI real UTF-8 BYTES, exactly as
# @ARGV delivers them, and check what the library receives and what is
# printed.

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };

{
    package RecordingRunner;

    sub new { bless { urls => [] }, shift }

    sub request {
        my ( $self, %args ) = @_;
        push @{ $self->{urls} }, $args{url};
        return {
            method        => $args{method},
            requested_url => $args{url},
            final_url     => $args{url},
            status        => 200,
            title         => 'Title',
            content_type  => 'text/html',
            headers       => { 'content-type' => 'text/html' },
            body          => '<li class="b_algo"><h2><a href="https://example.test/a">Result A</a></h2><div class="b_caption"><p>Snippet A</p></div>',
            body_text     => q{},
            is_captcha    => 0,
        };
    }
}

sub _run {
    my ( $entry, %args ) = @_;
    my $runner = RecordingRunner->new();
    my ( $output, $error ) = ( q{}, q{} );
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";
    open my $error_fh,  '>', \$error  or die "Unable to open error scalar: $!";
    my $rc = $entry->( %args, runner => $runner, output_fh => $output_fh, error_fh => $error_fh );
    close $output_fh;
    close $error_fh;
    return ( $rc, $output, $error, $runner );
}

sub _search { _run( \&Browser::CLI::main_search, @_ ) }
sub _get    { _run( \&Browser::CLI::main, method => 'GET', @_ ) }

sub _chars {
    my ($bytes) = @_;
    return eval { decode( 'UTF-8', $bytes, FB_CROAK | LEAVE_SRC ) };
}

my $cafe_bytes = encode( 'UTF-8', "caf\x{e9}" );
my $cjk_bytes  = encode( 'UTF-8', "\x{4e2d}\x{6587}" );

# 1. Search URL: the accented query is percent-encoded exactly once.
{
    my ( $rc, undef, $error, $runner ) = _search( argv => [$cafe_bytes] );
    is( $rc, 0, 'search with an accented query exits 0' ) or diag($error);
    is( $runner->{urls}[0], 'https://www.bing.com/search?q=caf%C3%A9', 'the engine URL for an accented argv query is percent-encoded once, not double-encoded' );
}

# 2. CJK query, characters above U+00FF.
{
    my ( undef, undef, undef, $runner ) = _search( argv => [$cjk_bytes] );
    is( $runner->{urls}[0], 'https://www.bing.com/search?q=%E4%B8%AD%E6%96%87', 'the engine URL for a CJK argv query is percent-encoded once' );
}

# 3. The json echo of query decodes back to the typed text.
{
    my ( undef, $output ) = _search( argv => [$cafe_bytes] );
    my $decoded = eval { decode_json($output) };
    is( $decoded->{query}, "caf\x{e9}", 'json output echoes the accented query as the original text, not double-encoded' );
}

# 4. The table echo of query decodes back to the typed text.
{
    my ( undef, $output ) = _search( argv => [ $cafe_bytes, '-o', 'table' ] );
    my $text = _chars($output);
    ok( defined $text, 'search table output is valid UTF-8' );
    my $cafe = "caf\x{e9}";
    like( $text // q{}, qr/^query\s+\Q$cafe\E$/m, 'the table query row shows the original accented text, not double-encoded' );
}

# 5. get: the URL reaches the runner as characters, and both echoes are single-encoded.
{
    my ( $rc, $output, $error, $runner ) = _get( argv => ["https://example.test/$cafe_bytes"] );
    is( $rc, 0, 'get with an accented URL exits 0' ) or diag($error);
    is( $runner->{urls}[0], "https://example.test/caf\x{e9}", 'the URL handed to the runner is the decoded character string' );
    my $decoded = eval { decode_json($output) };
    is( $decoded->{requested_url}, "https://example.test/caf\x{e9}", 'json output echoes requested_url as the original text' );

    my ( undef, $table ) = _get( argv => [ "https://example.test/$cafe_bytes", '-o', 'table' ] );
    my $text = _chars($table);
    ok( defined $text, 'get table output is valid UTF-8' );
    my $cafe_url = "https://example.test/caf\x{e9}";
    like( $text // q{}, qr/^requested_url\s+\Q$cafe_url\E$/m, 'the table requested_url row shows the original accented text' );
}

# 6. Pass-through guards: input that must NOT change.
{
    my ( undef, undef, undef, $ascii ) = _search( argv => ['perl'] );
    is( $ascii->{urls}[0], 'https://www.bing.com/search?q=perl', 'an ASCII query is unchanged' );

    my ( undef, undef, undef, $chars ) = _search( argv => ["caf\x{e9}\x{2014}"] );
    is( $chars->{urls}[0], 'https://www.bing.com/search?q=caf%C3%A9%E2%80%94', 'a query that is already a character string is not decoded again' );

    my ( undef, undef, undef, $latin1 ) = _search( argv => ["caf\xE9"] );
    is( $latin1->{urls}[0], 'https://www.bing.com/search?q=caf%C3%A9', 'a query that is not valid UTF-8 is passed through unchanged' );
}

is_deeply( \@warnings, [], 'no warnings were emitted' ) or diag( join q{}, @warnings );

done_testing();
