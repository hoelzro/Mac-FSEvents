use strict;
use warnings;

use File::Temp;
use IO::Select;
use Mac::FSEvents;

use Test::More skip_all => 'This is a problem with FSEvents itself, it seems';

my $LATENCY = 0.5;
my $TIMEOUT = 1.0;

my $dir = File::Temp->newdir;

my $fs = Mac::FSEvents->new({
    path    => $dir->dirname,
    latency => $LATENCY,
});

my $fh  = $fs->watch;
my $sel = IO::Select->new($fh);

mkdir "$dir/foo";

my $has_events = $sel->can_read($TIMEOUT);
ok $has_events, q{we should have an event to process the first time around};

$fs->stop;

undef $fs;

rmdir "$dir/foo";

$fs = Mac::FSEvents->new({
    path    => $dir->dirname,
    latency => $LATENCY,
});

$fh         = $fs->watch;
$sel        = IO::Select->new($fh);
$has_events = $sel->can_read($TIMEOUT);

ok !$has_events, q{a new watcher shouldn't receive old events};
