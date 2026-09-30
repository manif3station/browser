use strict;
use warnings;

use Test::More;
use File::Spec;
use File::Basename qw(dirname basename);

# D2B-148: cli/get/post/png/search's own EXIT STATUS POD said the vague
# "non-zero" for their failure exit code, even though
# Browser::CLI::main()/main_search() (which all four delegate to) can
# only ever return exactly 0 or 2 - no other exit path exists. This left
# cli/skills's own EXIT STATUS POD (D2B-147), which explicitly claims to
# match "every other browser.* command's convention" of exiting 2, with
# no way to verify that claim from the docs alone.

my $repo_root = File::Spec->catdir( dirname(__FILE__), '..' );

# D2B-236: this list used to be maintained by hand (get post png search
# skills) and had drifted - cli/pdf was never in it, so its EXIT STATUS
# POD went unchecked. It is now derived from the scripts actually in
# cli/, so a script added later is checked automatically, and a floor
# plus an explicit pdf check stop an empty or truncated glob passing.
my @commands = sort map { basename($_) } glob File::Spec->catfile( $repo_root, 'cli', '*' );
cmp_ok( scalar @commands, '>=', 6, 'found the cli scripts to check (at least the six known ones)' );
ok( ( grep { $_ eq 'pdf' } @commands ), 'cli/pdf is among the scripts checked' );

for my $command (@commands) {
    my $path = File::Spec->catfile( $repo_root, 'cli', $command );
    open my $fh, '<', $path or die "Unable to open $path: $!";
    my $text = do { local $/; <$fh> };
    close $fh;

    my ($exit_status_section) = $text =~ /^=head1 EXIT STATUS\n\n(.*?)\n\n/ms;
    ok( defined $exit_status_section, "cli/$command has an EXIT STATUS POD section" );
    like( $exit_status_section, qr/C<2>/, "cli/${command}'s EXIT STATUS POD names C<2> explicitly, not just \"non-zero\"" );
}

done_testing();
