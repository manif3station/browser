use strict;
use warnings;

use Test::More;

# D2B-046: nothing guards .env's VERSION field against being malformed
# (e.g. a typo like "0.2O" or a missing value) or referring to a release
# that was never actually recorded in Changes.

my $env_text = do {
    open my $fh, '<', '.env' or die "Unable to read .env: $!";
    local $/;
    <$fh>;
};

my ($version) = $env_text =~ /^VERSION=(\S+)/m;
ok( defined $version, '.env declares a VERSION line' );
like( $version, qr/\A[0-9]+\.[0-9]+(?:\.[0-9]+)?\z/, '.env\'s VERSION is a well-formed dotted numeric version, not malformed' );

SKIP: {
    skip 'VERSION is missing/undefined - cannot cross-check against Changes', 1 if !defined $version;

    my $changes_text = do {
        open my $fh, '<', 'Changes' or die "Unable to read Changes: $!";
        local $/;
        <$fh>;
    };

    like(
        $changes_text,
        qr/^\Q$version\E\s/m,
        '.env\'s VERSION corresponds to a release actually recorded in Changes, not a value nobody ever shipped'
    );
}

done_testing();
