package Browser::CLI::TableOutput;

use strict;
use warnings;

# D2B-216: extracted from Browser::CLI (which crossed this project's own
# 500-line guideline after D2B-208 added -o/--output table rendering) -
# the same extraction pattern already used for VersionCompare.pm
# (D2B-155), Capture.pm (D2B-196), and NodeRuntime/Install.pm (D2B-198).
# No behavior change - these four subs are moved verbatim.

# D2B-208: this workspace's own DD skill CLI output contract
# (~/projects/skills/CLAUDE.md) documents "default output is a
# human-readable summary (pretty table); -o json emits the full
# underlying payload" - this skill's commands never had an -o flag at
# all. -o/--output is pre-scanned here and stripped from argv before
# it ever reaches execute()/execute_search()'s own GetOptionsFromArray
# call, the same architecture --help/--version already use in
# Browser::CLI - keeping this a pure CLI-presentation-layer concern
# that never has to flow through execute()'s existing return-value
# contract, which is also used directly by other callers per this
# skill's own README ("at the Perl API level"). json is kept as the
# default (byte-identical to every existing caller's current behavior,
# including this suite's own 1000+ assertions) rather than flipping
# the default to table, since that would be a breaking change to
# every existing consumer of this skill's JSON output - table is
# added as a new opt-in instead.
sub extract_output_format {
    my ($argv) = @_;
    my @remaining;
    my $format;
    my $i = 0;
    while ( $i <= $#$argv ) {
        my $tok = $argv->[$i];
        if ( $tok eq '--' ) {
            push @remaining, @{$argv}[ $i .. $#$argv ];
            last;
        }
        if ( $tok eq '-o' || $tok eq '--output' ) {
            die "--output requires a value (json or table)\n" if $i == $#$argv;
            $format = $argv->[ $i + 1 ];
            $i += 2;
            next;
        }
        if ( $tok =~ /\A--output=(.*)\z/s ) {
            $format = $1;
            $i += 1;
            next;
        }
        push @remaining, $tok;
        $i += 1;
    }
    $format = 'json' if !defined $format;
    die "Unsupported output format: $format (expected json or table)\n"
      if $format ne 'json' && $format ne 'table';
    return ( $format, \@remaining );
}

# D2B-208: intentionally a summary, not the full payload - body/
# body_text/headers are omitted here exactly as the workspace's own
# convention distinguishes a table summary from -o json's full
# underlying payload; get the full detail from -o json instead.
sub print_table_result {
    my ( $method, $result, $output_fh ) = @_;
    my @rows = (
        [ method        => $result->{method} ],
        [ requested_url => $result->{requested_url} ],
        [ final_url     => $result->{final_url} ],
        [ status        => $result->{status} ],
        [ content_type  => $result->{content_type} ],
        [ is_captcha    => $result->{is_captcha} ? 'yes' : 'no' ],
    );
    push @rows, [ title => $result->{title} ] if $method eq 'GET';
    push @rows, [ script_result => 'yes (see -o json for the value)' ] if defined $result->{script_result};
    print {$output_fh} render_field_table( \@rows );
    return 0;
}

sub render_field_table {
    my ($rows) = @_;
    my $label_width = 0;
    for my $row (@$rows) {
        $label_width = length( $row->[0] ) if length( $row->[0] ) > $label_width;
    }
    my $text = q{};
    for my $row (@$rows) {
        my ( $label, $value ) = @$row;
        $value = q{} if !defined $value;
        $text .= sprintf "%-*s  %s\n", $label_width, $label, $value;
    }
    return $text;
}

sub print_search_table_result {
    my ( $result, $output_fh ) = @_;
    my @rows = (
        [ query         => $result->{query} ],
        [ engine_used   => $result->{engine_used} ],
        [ engines_tried => join( ', ', @{ $result->{engines_tried} || [] } ) ],
        [ result_count  => scalar @{ $result->{results} || [] } ],
    );
    print {$output_fh} render_field_table( \@rows );
    for my $item ( @{ $result->{results} || [] } ) {
        print {$output_fh} sprintf( "  %d. %s\n     %s\n", $item->{rank}, $item->{title}, $item->{url} );
    }
    return 0;
}

1;
