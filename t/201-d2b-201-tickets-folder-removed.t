use strict;
use warnings;

use Test::More;

# D2B-201: the tickets/ folder (DD-*/EPIC-*/SOW.md/TESTING.md) predates
# this project's move to Tira as the board/system of record - owner
# instruction: "Remove the folder named as tickets we have Tira. We do
# not need to keep this legacy folder." This is the red/TDD driver -
# fails against the pre-removal repo state.

ok( !-d 'tickets', 'the legacy tickets/ folder no longer exists' );

for my $doc (qw(README.md SKILLS.md)) {
    open my $fh, '<', $doc or die "Unable to open $doc: $!";
    my $text = do { local $/; <$fh> };
    close $fh or die "Unable to close $doc: $!";
    unlike( $text, qr{tickets/}, "$doc no longer references the removed tickets/ folder" );
}

done_testing();
