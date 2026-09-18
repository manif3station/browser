use strict;
use warnings;

use Cwd ();
use File::Spec;
use Test::More;

# D2B-097: the browser skill had no SKILLS.md and no 'browser.skills'
# command, unlike other skills in this workspace (e.g. tira.skills)
# which provide a single, comprehensive agent-facing manual reachable
# via 'd2 <skill>.skills'.

my $skill_root = Cwd::abs_path('.');
my $skills_md  = File::Spec->catfile( $skill_root, 'SKILLS.md' );
my $cli_skills = File::Spec->catfile( $skill_root, 'cli', 'skills' );

ok( -f $skills_md, 'SKILLS.md exists at the skill root' );
ok( -f $cli_skills, 'cli/skills exists' );
ok( -x $cli_skills, 'cli/skills is executable' );

my $expected = do {
    open my $fh, '<:raw', $skills_md or die "Unable to read $skills_md: $!";
    local $/;
    <$fh>;
};

my $actual = qx{$^X $cli_skills};
my $exit   = $? >> 8;

is( $exit, 0, 'cli/skills exits 0' );
is( $actual, $expected, "cli/skills' stdout matches SKILLS.md's file contents exactly" );

done_testing();
