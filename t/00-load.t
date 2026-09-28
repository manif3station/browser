use strict;
use warnings;

use Test::More;

use lib 'lib';

use_ok('Browser::CLI');
use_ok('Browser::CLI::TableOutput');
use_ok('Browser::Runner');
use_ok('Browser::Search');
use_ok('Browser::Runner::NodeRuntime');
use_ok('Browser::Runner::BrowserPath');
use_ok('Browser::Runner::VersionCompare');
use_ok('Browser::Runner::Capture');
use_ok('Browser::Runner::NodeRuntime::Install');

done_testing();
