use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Test::More;

# D2B-251: browser.pdf (D2B-196) shares almost every behaviour browser.png has -
# the leading-dash URL misparse, the negative --timeout-ms refusal, --timeout-ms 0,
# headless by default, --ask/--askme, --data and --wait-until handling, the
# concurrent-install lock - but eleven lines in README.md and docs/usage.md
# described those behaviours as applying to "browser.get/browser.post/browser.png"
# and never mentioned pdf. D2B-205 (docs/overview.md's lists) and D2B-244 (three
# --help statements) fixed the same drift once each; this pins the whole class: any
# line in README.md or docs/usage.md that names browser.png together with
# browser.get or browser.post must also mention pdf.
#
# The checks first assert that the files were read and that enough such lines exist
# for the scan to mean something, so a reworded document fails loudly instead of
# passing on nothing.

sub _lines {
    my ($path) = @_;
    open my $fh, '<:encoding(UTF-8)', $path or die "Unable to open $path: $!";
    my @lines = <$fh>;
    close $fh;
    chomp @lines;
    return @lines;
}

my $scanned = 0;
for my $file ( 'README.md', 'docs/usage.md' ) {
    my @lines = _lines($file);
    cmp_ok( scalar @lines, '>', 100, "read $file" );

    my @listing;
    for my $i ( 0 .. $#lines ) {
        next if $lines[$i] !~ /browser\.png/;
        next if $lines[$i] !~ /browser\.(?:get|post)/;
        push @listing, [ $i + 1, $lines[$i] ];
    }
    $scanned += @listing;
    cmp_ok( scalar @listing, '>=', 3, "$file has lines that list browser.png with browser.get or browser.post" );

    for my $entry (@listing) {
        my ( $number, $text ) = @{$entry};
        like( $text, qr/pdf/i, "$file line $number: a line that lists browser.png with get or post also names pdf" );
    }
}

cmp_ok( $scanned, '>=', 12, 'the scan covered the lines it is meant to (the eleven fixed ones plus those that already named pdf)' );

done_testing();
