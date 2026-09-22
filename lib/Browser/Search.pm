package Browser::Search;

use strict;
use warnings;

use Browser::Runner ();
use URI::Escape qw(uri_escape_utf8);

# D2B-153: public (not underscore-prefixed) since Browser::CLI, a
# standalone module outside this module's own search() flow, reuses it
# to look engines up by name for --engine/--engines validation.
sub default_engines {
    return (
        { name => 'bing',       url => sub { 'https://www.bing.com/search?q=' . uri_escape_utf8( $_[0] ) },       parser => \&_parse_bing },
        { name => 'google',     url => sub { 'https://www.google.com/search?q=' . uri_escape_utf8( $_[0] ) },     parser => \&_parse_google },
        { name => 'duckduckgo', url => sub { 'https://html.duckduckgo.com/html/?q=' . uri_escape_utf8( $_[0] ) }, parser => \&_parse_duckduckgo },
    );
}

sub search {
    my (%args) = @_;
    my $query = $args{query};

    # D2B-160: this guard is unreachable through Browser::CLI::
    # execute_search(), which has its own earlier "Missing query" check
    # - deliberate defense-in-depth for any direct caller of search()
    # that bypasses the CLI. See t/160-...-search-guards-direct-call.t.
    die "Missing query" if !defined $query || $query =~ /\A\s*\z/;

    my @engines = $args{engines} ? @{ $args{engines} } : default_engines();

    # D2B-160: unreachable via the CLI (execute_search() only passes
    # engines when its own lookup already found at least one) -
    # deliberate defense-in-depth, same rationale as above.
    die "At least one engine is required" if !@engines;

    my $max = defined $args{max} ? $args{max} : 10;

    # D2B-160: unreachable via the CLI, which has its own earlier
    # "--max must not be negative" check - deliberate defense-in-depth,
    # same rationale as above.
    die "--max must not be negative" if $max < 0;
    my $runner = $args{runner} || Browser::Runner->new();

    # Bounded so several default engines tried sequentially can't stack
    # multiple Playwright ~30s waits into a much longer effective hang.
    my $timeout_ms = defined $args{timeout_ms} ? $args{timeout_ms} : 10_000;
    die "--timeout-ms must not be negative" if $timeout_ms < 0;

    my @tried;
    my @failures;
    my $any_captcha = 0;
    for my $engine (@engines) {
        my $url = $engine->{url}->($query);
        my $result = eval { $runner->request( method => 'GET', url => $url, headless => 1, timeout_ms => $timeout_ms ) };
        my $error = $@;
        push @tried, $engine->{name};

        if ( !$result ) {
            chomp $error;
            $error = 'unknown error' if !length $error;
            push @failures, "$engine->{name} (request failed: $error)";
            next;
        }
        if ( $result->{is_captcha} ) {
            $any_captcha = 1;
            push @failures, "$engine->{name} (CAPTCHA/bot-check wall)";
            next;
        }

        my $results = _parse_results( engine => $engine, body => $result->{body} );

        if ( !@$results && length( $result->{body} // q{} ) > 200 ) {
            push @failures, "$engine->{name} (no results parsed - engine markup may have changed)";
            next;
        }

        $results = [ @{$results}[ 0 .. $max - 1 ] ] if $max < @$results;

        return {
            query         => $query,
            engine_used   => $engine->{name},
            engines_tried => \@tried,
            results       => $results,
        };
    }

    my $message = 'All search engines failed: ' . join( ', ', @failures );
    $message .= ' - use --ask on browser.get for interactive search instead' if $any_captcha;
    die $message;
}

sub _parse_results {
    my (%args) = @_;
    my $engine = $args{engine};
    my $body   = defined $args{body} ? $args{body} : q{};

    return $engine->{parser}->($body) if ref $engine eq 'HASH' && ref $engine->{parser} eq 'CODE';

    # D2B-130: this by-name fallback looks unreachable from search()'s own
    # default engines (which always carry a parser), but it is deliberate
    # D2B-070 backward compatibility for any external caller of
    # search(engines => [...]) that hand-builds an engine hash without a
    # parser key - see t/63-...-search-fixes.t's "legacy dispatch" test.
    # Investigated and confirmed NOT dead code; do not remove.
    my $name = ref $engine eq 'HASH' ? ( $engine->{name} || q{} ) : ( $engine || q{} );
    return _parse_bing($body)       if $name eq 'bing';
    return _parse_google($body)     if $name eq 'google';
    return _parse_duckduckgo($body) if $name eq 'duckduckgo';
    return [];
}

# D2B-178: all 3 engine parsers below were identical except for their
# own regex - this shared helper runs the common match/build/rank
# loop, so each parser now differs only in the pattern it hands over.
sub _parse_with_regex {
    my ( $body, $regex ) = @_;
    my @results;
    while ( $body =~ /$regex/gs ) {
        push @results, { url => _decode_entities($1), title => _strip_tags($2), snippet => _strip_tags($3) };
    }
    return _rank(@results);
}

sub _parse_bing {
    my ($body) = @_;
    return _parse_with_regex( $body, qr{<li\s+class="b_algo">.*?<h2><a\s+href="([^"]+)">(.*?)</a></h2>.*?<div\s+class="b_caption"><p>(.*?)</p>}s );
}

sub _parse_google {
    my ($body) = @_;
    return _parse_with_regex( $body, qr{<div\s+class="g">\s*<a\s+href="([^"]+)"><h3>(.*?)</h3></a>\s*<span\s+class="VwiC3b">(.*?)</span>}s );
}

sub _parse_duckduckgo {
    my ($body) = @_;
    return _parse_with_regex( $body, qr{<a\s+class="result__a"\s+href="([^"]+)">(.*?)</a>\s*<a\s+class="result__snippet">(.*?)</a>}s );
}

sub _rank {
    my @results = @_;
    my $rank = 0;
    $_->{rank} = ++$rank for @results;
    return \@results;
}

sub _strip_tags {
    my ($value) = @_;
    return q{} if !defined $value;
    $value =~ s{<[^>]*>}{}g;
    $value = _decode_entities($value);
    $value =~ s{\A\s+|\s+\z}{}g;
    return $value;
}

my %NAMED_ENTITIES = (
    amp    => '&',
    lt     => '<',
    gt     => '>',
    quot   => '"',
    apos   => q{'},

    # D2B-176: common typographic entities realistically found in real
    # search-engine snippet/title text - previously left as literal
    # entity text since only the 5 entities above were mapped.
    nbsp   => "\x{00A0}",
    mdash  => "\x{2014}",
    ndash  => "\x{2013}",
    lsquo  => "\x{2018}",
    rsquo  => "\x{2019}",
    ldquo  => "\x{201C}",
    rdquo  => "\x{201D}",
    hellip => "\x{2026}",
    copy   => "\x{00A9}",
    trade  => "\x{2122}",
    reg    => "\x{00AE}",
);

sub _decode_entities {
    my ($value) = @_;
    $value =~ s{&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);}{
        my $entity = $1;
        if ( $entity =~ /^#x([0-9a-fA-F]+)\z/ ) {
            _codepoint_to_char( hex($1) ) // "&$entity;";
        }
        elsif ( $entity =~ /^#([0-9]+)\z/ ) {
            _codepoint_to_char($1) // "&$entity;";
        }
        else {
            exists $NAMED_ENTITIES{$entity} ? $NAMED_ENTITIES{$entity} : "&$entity;";
        }
    }ge;
    return $value;
}

sub _codepoint_to_char {
    my ($codepoint) = @_;
    return undef if $codepoint > 0x10FFFF;
    return undef if $codepoint >= 0xD800 && $codepoint <= 0xDFFF;
    return chr($codepoint);
}

1;
