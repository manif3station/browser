use strict;
use warnings;
use utf8;

use Encode qw(encode_utf8);
use JSON::PP ();
use Test::More;

binmode Test::More->builder->output,         ':encoding(UTF-8)';
binmode Test::More->builder->failure_output, ':encoding(UTF-8)';

use lib 'lib';
use Browser::Runner;

# D2B-030: browser.post's window.__BROWSER_POST__ assignment concatenates
# encode_json's output directly into JS source text passed to
# $page->evaluate(). encode_json produces valid JSON but does not escape
# the Unicode LINE SEPARATOR or PARAGRAPH SEPARATOR characters - both are
# legal JS line terminators when they appear in source text (not JSON
# text), so a POST response body containing one can break out of the
# intended string literal and inject arbitrary script into the
# evaluate() call.

{
    package FakeResponse;
    sub new { bless $_[1], $_[0] }
    sub status  { $_[0]{status} }
    sub text    { $_[0]{body} }
    sub headers { $_[0]{headers} }
    sub url     { $_[0]{url} }
}

{
    package FakeRequest;
    sub new  { bless $_[1], $_[0] }
    sub post { my ( $self, $url, $options ) = @_; return $self->{response}; }
}

{
    package FakePage;
    sub new           { bless $_[1], $_[0] }
    sub request       { $_[0]{request} }
    sub setContent    { $_[0]{set_content} = $_[1]; return 1; }
    sub evaluate      { push @{ $_[0]{evaluations} }, $_[1]; return 1; }
    sub goto          { return $_[0]{response} }
    sub title         { return q{} }
    sub url           { return 'https://example.test/' }
}

sub _post_with_body {
    my ($body) = @_;
    my $page = FakePage->new(
        {
            request => FakeRequest->new(
                {
                    response => FakeResponse->new(
                        {
                            status  => 200,
                            body    => $body,
                            headers => { 'content-type' => 'text/plain' },
                            url     => 'https://example.test/',
                        }
                    ),
                }
            ),
        }
    );
    Browser::Runner::_run_post( $page, url => 'https://example.test/' );
    return $page->{evaluations}[0];
}

# --- LINE SEPARATOR (code point 2028 hex) ---
{
    my $body_with_separator = "\x{2028}alert('injected')//";
    my $evaluated_js = _post_with_body($body_with_separator);
    my $bytes = encode_utf8($evaluated_js);
    my $raw_bytes = "\xe2\x80\xa8";    # the line separator, encoded as UTF-8

    unlike(
        $bytes,
        qr/\Q$raw_bytes\E/,
        'window.__BROWSER_POST__ assignment JS never contains the raw UTF-8 bytes for the line-separator character - it must be JS-escaped instead'
    );

    like(
        $bytes,
        qr/\\u2028/i,
        'the line-separator character from the response body is JS-escaped in the evaluated source instead of embedded raw'
    );

    my ($json_literal) = $evaluated_js =~ /window\.__BROWSER_POST__\s*=\s*(\{.*\});\s*return true;/;
    my $decoded = JSON::PP::decode_json($json_literal);
    is( $decoded->{body}, $body_with_separator, 'the JSON literal decodes back to the exact original body containing the line-separator character, proving the string was never broken out of' );
}

# --- PARAGRAPH SEPARATOR (code point 2029 hex) ---
{
    my $body_with_separator = "\x{2029}alert('injected-2029')//";
    my $evaluated_js = _post_with_body($body_with_separator);
    my $bytes = encode_utf8($evaluated_js);
    my $raw_bytes = "\xe2\x80\xa9";    # the paragraph separator, encoded as UTF-8

    unlike(
        $bytes,
        qr/\Q$raw_bytes\E/,
        'window.__BROWSER_POST__ assignment JS never contains the raw UTF-8 bytes for the paragraph-separator character either'
    );

    like(
        $bytes,
        qr/\\u2029/i,
        'the paragraph-separator character is JS-escaped the same way the line-separator character is'
    );
}

done_testing();
