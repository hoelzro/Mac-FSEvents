use strict;
use warnings;

use File::Path qw(remove_tree);
use File::Slurp qw(write_file);
use File::Spec;
use Mac::FSEvents qw(:flags);
use Test::More;

BEGIN {
    unless(__PACKAGE__->can('FILE_EVENTS')) {
        plan skip_all => 'OS X 10.7 or greater needed for this test';
        exit 0;
    }
}

plan tests => 1;

my $LATENCY         = 0.5;
my $TIMEOUT         = 120;
my $EXPECTED_EVENTS = 10_000;

sub is_same_file {
    my ( $lhs, $rhs ) = @_;

    my ( $lhs_dev, $lhs_inode ) = (stat $lhs)[0, 1];
    my ( $rhs_dev, $rhs_inode ) = (stat $rhs)[0, 1];

    return $lhs_dev == $rhs_dev && $lhs_inode == $rhs_inode;
}

my $tmpdir = File::Spec->rel2abs('tmp');

remove_tree($tmpdir);
mkdir $tmpdir;

sleep 2; # make sure we don't receive an event for creating our tmpdir

my $fsevents = Mac::FSEvents->new({
    path    => $tmpdir,
    latency => $LATENCY,
    flags   => FILE_EVENTS,
});

$fsevents->watch;

sleep 2; # make sure we don't receive an event for creating our tmpdir

my $event_count = 0;

for my $n ( 1 .. $EXPECTED_EVENTS) {
    write_file(File::Spec->catfile($tmpdir, $n), 'foobar');
}

$SIG{'ALRM'} = sub { die "alarm" };

alarm $TIMEOUT;

eval {
EVENT_LOOP:
    while(my @events = $fsevents->read_events) {
        foreach my $e (@events) {
            my $path = $e->path;
            my ( undef, $dir ) = File::Spec->splitpath($path);
             
            if(is_same_file($dir, $tmpdir)) {
                $event_count++;
                last EVENT_LOOP if $event_count >= $EXPECTED_EVENTS;
            }
        }
    }
};

if($@ && $@ !~ /alarm/) {
    die $@;
}

is $event_count, $EXPECTED_EVENTS, 'every event should be seen';
