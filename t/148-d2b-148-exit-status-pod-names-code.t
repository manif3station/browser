use strict;
use warnings;

use Test::More;
use File::Spec;
use File::Basename qw(dirname);

# D2B-148: cli/get/post/png/search's own EXIT STATUS POD said the vague
# "non-zero" for their failure exit code, even though
# Browser::CLI::main()/main_search() (which all four delegate to) can
# only ever return exactly 0 or 2 - no other exit path exists. This left
# cli/skills's own EXIT STATUS POD (D2B-147), which explicitly claims to
# match "every other browser.* command's convention" of exiting 2, with
# no way to verify that claim from the docs alone.

my $repo_root = File::Spec->catdir( dirname(__FILE__), '..' );

for my $command (qw(get post png search skills)) {
    my $path = File::Spec->catfile( $repo_root, 'cli', $command );
    open my $fh, '<', $path or die "Unable to open $path: $!";
    my $text = do { local $/; <$fh> };
    close $fh;

    my ($exit_status_section) = $text =~ /^=head1 EXIT STATUS\n\n(.*?)\n\n/ms;
    ok( defined $exit_status_section, "cli/$command has an EXIT STATUS POD section" );
    like( $exit_status_section, qr/C<2>/, "cli/${command}'s EXIT STATUS POD names C<2> explicitly, not just \"non-zero\"" );
}

done_testing();
