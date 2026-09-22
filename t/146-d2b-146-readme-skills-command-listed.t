use strict;
use warnings;

use Test::More;

# D2B-146: README.md's own "Developer Dashboard Feature Added" and
# "Layout" sections listed only 3 of the 4 real dotted commands and only
# 4 of the 5 real cli/* entrypoints, omitting `dashboard browser.skills`
# and `cli/skills` entirely - despite README.md documenting
# browser.skills' behavior in prose elsewhere in the same file, and
# despite SKILLS.md's own equivalent layout list already listing it.

open my $fh, '<', 'README.md' or die "Unable to open README.md: $!";
my $text = do { local $/; <$fh> };
close $fh;

# Anchored to the next level-2 header (or EOF) so a level-3 (###)
# subsection heading elsewhere in the file cannot truncate the capture -
# a Codex review round caught that the original (.*?)\n## form was not
# anchored to a line start and could stop early or match incidentally.
my ($feature_added_section) = $text =~ /^## Developer Dashboard Feature Added\n(.*?)(?=^## |\z)/ms;
ok( defined $feature_added_section, 'README.md has a Developer Dashboard Feature Added section' );
like( $feature_added_section, qr/^- the dotted command `dashboard browser\.skills`/m, 'README.md\'s Feature Added section lists dashboard browser.skills as its own bullet, not just an incidental mention' );

my ($layout_section) = $text =~ /^## Layout\n(.*?)(?=^## |\z)/ms;
ok( defined $layout_section, 'README.md has a Layout section' );
like( $layout_section, qr/^- `cli\/skills`/m, 'README.md\'s Layout section lists cli/skills as its own bullet, not just an incidental mention' );

# Regression guard: the other 3 commands/entrypoints are still listed as
# their own bullets.
for my $command (qw(get post png search)) {
    like( $feature_added_section, qr/^- the dotted command `dashboard browser\.$command`/m, "D2B-146 regression guard: Feature Added section still lists browser.$command as its own bullet" );
    like( $layout_section, qr/^- `cli\/$command`/m, "D2B-146 regression guard: Layout section still lists cli/$command as its own bullet" );
}

done_testing();
