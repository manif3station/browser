package Browser::Search;

use strict;
use warnings;

use Browser::Runner ();
use URI::Escape qw(uri_escape_utf8);

sub _default_engines {
    return (
        { name => 'bing',       url => sub { 'https://www.bing.com/search?q=' . uri_escape_utf8( $_[0] ) } },
        { name => 'google',     url => sub { 'https://www.google.com/search?q=' . uri_escape_utf8( $_[0] ) } },
        { name => 'duckduckgo', url => sub { 'https://html.duckduckgo.com/html/?q=' . uri_escape_utf8( $_[0] ) } },
    );
}

sub search {
    my (%args) = @_;
    my $query = $args{query};
    die "Missing query" if !defined $query || $query =~ /\A\s*\z/;

    my @engines = $args{engines} ? @{ $args{engines} } : _default_engines();
    die "At least one engine is required" if !@engines;

    my $max = defined $args{max} ? $args{max} : 10;
    die "--max must not be negative" if $max < 0;
    my $runner = $args{runner} || Browser::Runner->new();

    # Bounded so several default engines tried sequentially can't stack
    # multiple Playwright ~30s waits into a much longer effective hang.
    my $timeout_ms = defined $args{timeout_ms} ? $args{timeout_ms} : 10_000;

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

        my $results = _parse_results( engine => $engine->{name}, body => $result->{body} );
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
    my $engine = $args{engine} || q{};
    my $body   = defined $args{body} ? $args{body} : q{};

    return _parse_bing($body)       if $engine eq 'bing';
    return _parse_google($body)     if $engine eq 'google';
    return _parse_duckduckgo($body) if $engine eq 'duckduckgo';
    return [];
}

sub _parse_bing {
    my ($body) = @_;
    my @results;
    while ( $body =~ m{<li\s+class="b_algo">.*?<h2><a\s+href="([^"]+)">(.*?)</a></h2>.*?<div\s+class="b_caption"><p>(.*?)</p>}gs ) {
        push @results, { url => $1, title => _strip_tags($2), snippet => _strip_tags($3) };
    }
    return _rank(@results);
}

sub _parse_google {
    my ($body) = @_;
    my @results;
    while ( $body =~ m{<div\s+class="g">\s*<a\s+href="([^"]+)"><h3>(.*?)</h3></a>\s*<span\s+class="VwiC3b">(.*?)</span>}gs ) {
        push @results, { url => $1, title => _strip_tags($2), snippet => _strip_tags($3) };
    }
    return _rank(@results);
}

sub _parse_duckduckgo {
    my ($body) = @_;
    my @results;
    while ( $body =~ m{<a\s+class="result__a"\s+href="([^"]+)">(.*?)</a>\s*<a\s+class="result__snippet">(.*?)</a>}gs ) {
        push @results, { url => $1, title => _strip_tags($2), snippet => _strip_tags($3) };
    }
    return _rank(@results);
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
    amp  => '&',
    lt   => '<',
    gt   => '>',
    quot => '"',
    apos => q{'},
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
    return chr($codepoint);
}

1;
