package Browser::Search;

use strict;
use warnings;

use Browser::Runner ();
use URI::Escape qw(uri_escape_utf8);

sub _default_engines {
    return (
        { name => 'bing',       url => sub { 'https://www.bing.com/search?q=' . uri_escape_utf8( $_[0] ) } },
        { name => 'google',     url => sub { 'https://www.google.com/search?q=' . uri_escape_utf8( $_[0] ) } },
        { name => 'duckduckgo', url => sub { 'https://duckduckgo.com/html/?q=' . uri_escape_utf8( $_[0] ) } },
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

    my @tried;
    for my $engine (@engines) {
        my $url = $engine->{url}->($query);
        my $result = eval { $runner->request( method => 'GET', url => $url ) };
        push @tried, $engine->{name};
        next if !$result || $result->{is_captcha};

        my $results = _parse_results( engine => $engine->{name}, body => $result->{body} );
        $results = [ @{$results}[ 0 .. $max - 1 ] ] if $max < @$results;

        return {
            query         => $query,
            engine_used   => $engine->{name},
            engines_tried => \@tried,
            results       => $results,
        };
    }

    die 'All search engines walled by CAPTCHA/bot-check: ' . join( ', ', @tried )
      . ' - use --ask on browser.get for interactive search instead';
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
    $value =~ s{\A\s+|\s+\z}{}g;
    return $value;
}

1;
