use strict;
use warnings;

use Test::More;
use File::Spec;
use File::Basename qw(dirname);

# D2B-152: SKILLS.md's --max N bullet said only "refused if negative",
# omitting its default value (10) - unlike its own adjacent --timeout-ms
# bullet (which states "default 10s"), unlike docs/usage.md, unlike
# README.md, and unlike the CLI's own --help usage text, all of which
# correctly state the default is 10.

my $repo_root = File::Spec->catdir( dirname(__FILE__), '..' );

my $path = File::Spec->catfile( $repo_root, 'SKILLS.md' );
open my $fh, '<', $path or die "Unable to open $path: $!";
my $text = do { local $/; <$fh> };
close $fh;

# Codex review round: the original regex only checked for a bare "10"
# substring anywhere in the matched bullet line, which is not
# section-scoped and could pass on a future, unrelated --max N bullet
# elsewhere in the file. Assert the complete intended bullet text
# instead, so this test only passes for exactly the wording expected.
my ($max_bullet) = $text =~ /^(- `--max N`.*)$/m;
ok( defined $max_bullet, 'SKILLS.md has a --max N bullet' );
is( $max_bullet, '- `--max N` — default 10; refused if negative.', 'SKILLS.md\'s --max N bullet states its default value (10) explicitly, matching the exact intended wording' );

# Regression guard: the sibling --timeout-ms bullet for browser.search
# (which already states its own default, distinct from the OTHER
# --timeout-ms bullet documenting browser.get/post/png's own flag)
# remains unaffected.
my ($search_timeout_bullet) = $text =~ /^(- `--timeout-ms N` — per-engine request timeout.*)$/m;
ok( defined $search_timeout_bullet, 'SKILLS.md still has browser.search\'s own --timeout-ms N bullet' );
like( $search_timeout_bullet, qr/default 10s/, 'D2B-152 regression guard: the search --timeout-ms bullet\'s own default wording is unaffected' );

done_testing();
