use strict;
use warnings;

use Test::More;

# D2B-206: cpanfile declared only 'requires Playwright' and 'requires
# URI::Escape' - no test_requires stanza at all. t/193-...t uses
# YAML::XS, a non-core XS module, but it was nowhere in cpanfile. A
# genuinely fresh 'cpanm --installdeps .' (not the shared perl-test
# Docker image, which happens to already have YAML::XS from another
# skill) would fail t/193 with a missing-module error. This test
# guards that cpanfile actually declares every non-core module used
# by the test suite that isn't already a `requires` production
# dependency.

open my $fh, '<', 'cpanfile' or die "Unable to read cpanfile: $!";
my $cpanfile = do { local $/; <$fh> };
close $fh or die "Unable to close cpanfile: $!";

ok( index( $cpanfile, 'YAML::XS' ) >= 0, "cpanfile declares YAML::XS, used by t/193-d2b-193-cross-platform-workflow.t" );
# Anchored to a live statement start (^test_requires, not a bare
# substring anywhere in the line) and a terminating semicolon, so a
# commented-out "# test_requires 'YAML::XS';" cannot false-pass this.
like( $cpanfile, qr/^test_requires\s+'YAML::XS'\s*;/m, "YAML::XS is declared via an active test_requires statement, not requires or a comment" );

done_testing();
