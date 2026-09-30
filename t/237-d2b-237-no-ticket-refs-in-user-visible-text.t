use strict;
use warnings;

use Test::More;
use File::Basename qw(dirname basename);
use File::Spec;

use lib 'lib';
use Browser::CLI;

# D2B-237: the -o/--output help line printed by --help (and the perldoc
# NAME lines of cli/get and cli/post) named the internal ticket D2B-208,
# which means nothing to a user and is an internal management identifier
# leaking into text people read at runtime. Ticket references in code
# comments, README.md, SKILLS.md, docs/ and Changes are this repo's
# deliberate changelog convention and are not checked here - only the text
# a user actually sees.

my $repo_root = File::Spec->catdir( dirname(__FILE__), '..' );

my @help_cases = (
    [ 'browser.get --help',    sub { Browser::CLI::main( method => 'GET',  argv => ['--help'], output_fh => $_[0] ) } ],
    [ 'browser.post --help',   sub { Browser::CLI::main( method => 'POST', argv => ['--help'], output_fh => $_[0] ) } ],
    [ 'browser.png --help',    sub { Browser::CLI::main( method => 'PNG',  argv => ['--help'], output_fh => $_[0] ) } ],
    [ 'browser.search --help', sub { Browser::CLI::main_search( argv => ['--help'], output_fh => $_[0] ) } ],
);

for my $case (@help_cases) {
    my ( $label, $run ) = @$case;
    my $output = q{};
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";
    $run->($output_fh);
    close $output_fh;

    ok( length $output, "$label printed usage text" );
    unlike( $output, qr/\bD2B-\d+/, "$label does not name an internal ticket" );
}

my @scripts = sort glob File::Spec->catfile( $repo_root, 'cli', '*' );
cmp_ok( scalar @scripts, '>=', 6, 'found the cli scripts to check (at least the six known ones)' );

for my $path (@scripts) {
    my $command = basename($path);
    open my $fh, '<', $path or die "Unable to open $path: $!";
    my $text = do { local $/; <$fh> };
    close $fh;

    my ($name_line) = $text =~ /^=head1 NAME\n\n(.*?)\n\n/ms;
    ok( defined $name_line, "cli/$command has a NAME line" );
    unlike( $name_line // q{}, qr/\bD2B-\d+/, "cli/${command}'s NAME line does not name an internal ticket" );
}

done_testing();
