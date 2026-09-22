package Browser::Runner::VersionCompare;

use strict;
use warnings;

# D2B-155: extracted from Browser::Runner::NodeRuntime, which had grown
# to 499 lines (1 under this project's own 500-line decomposition
# threshold). This semver-subset comparator is self-contained and had
# no shared state with the rest of NodeRuntime.pm.

sub version_satisfies_spec {
    my ( $installed, $spec ) = @_;
    return 0 if !defined $installed || !defined $spec || $installed eq q{} || $spec eq q{};
    return 1 if $spec eq '*' || $spec eq 'latest';
    if ( $spec !~ /^\^/ ) {
        return $installed eq $spec if $spec =~ /^[0-9]+\.[0-9]+\.[0-9]+\z/;
        die "Unsupported version spec: $spec (expected an exact version, '*', 'latest', or a caret range like ^1.2.3)";
    }

    my $minimum = substr $spec, 1;
    return 0 if $installed =~ /-/ && $installed !~ /\A\Q$minimum\E\z/;
    my @installed = version_parts($installed);
    my @minimum   = version_parts($minimum);
    return 0 if !@installed || !@minimum;
    return 0 if $installed[0] != $minimum[0];

    if ( $minimum[0] == 0 ) {
        if ( $minimum[1] == 0 ) {
            return $installed[1] == $minimum[1] && $installed[2] == $minimum[2] ? 1 : 0;
        }
        return 0 if $installed[1] != $minimum[1];
    }

    return compare_version_parts( \@installed, \@minimum ) >= 0 ? 1 : 0;
}

sub version_parts {
    my ($value) = @_;
    return if !defined $value;
    my ($numeric) = $value =~ /\A([0-9]+(?:\.[0-9]+){0,2})/;
    return if !defined $numeric;
    my @parts = split /\./, $numeric;
    push @parts, 0 while @parts < 3;
    return @parts[ 0 .. 2 ];
}

sub compare_version_parts {
    my ( $left, $right ) = @_;
    for my $idx ( 0 .. 2 ) {
        my $cmp = ( $left->[$idx] || 0 ) <=> ( $right->[$idx] || 0 );
        return $cmp if $cmp != 0;
    }
    return 0;
}

1;
