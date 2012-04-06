use strict;
use warnings;
use autodie;

use Carp qw(croak);
use Cwd qw(getcwd);
use FindBin;
use File::Path qw(make_path rmtree);
use File::Spec;
use File::Temp;
use IO::Select;
use Mac::FSEvents qw(:flags);
use Time::HiRes qw(usleep);

use Test::More tests => 5;

my %capable_of;

BEGIN {
    foreach my $constant ( qw{IGNORE_SELF FILE_EVENTS} ) {
        if(__PACKAGE__->can($constant)) {
            $capable_of{$constant} = 1;
        } else {
            no strict 'refs';

            *$constant = sub {
                return 0;
            };
        }
    }
}

my $TEST_LATENCY = 0.5;
my $TIMEOUT      = 3;

my $tmpdir = "$FindBin::Bin/tmp";

sub touch_file {
    my ( $filename ) = @_;

    my $fh;
    open $fh, '>', $filename or die $!;
    close $fh;

    return;
}

sub reset_fs {
    rmtree $tmpdir if -d $tmpdir;

    mkdir $tmpdir;
}

sub with_wd (&$) {
    my ( $callback, $dir ) = @_;

    my $wd = getcwd();

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $ok = eval {
        chdir $dir or croak $!;

        $callback->();
        1;
    };
    my $error = $@;
    chdir $wd;
    die $error unless $ok;

    return;
}

sub dissect_event {
    my ( $event ) = @_;

    return {
        path => $event->path,
    };
}

sub fetch_events {
    my ( $fs, $fh ) = @_;

    my @events;

    my $sel = IO::Select->new($fh);

    while( $sel->can_read($TIMEOUT) ) {
        foreach my $event ( $fs->read_events ) {
            push @events, $event;
        }
    }

    return @events;
}

sub normalize_event {
    my ( $event ) = @_;

    my $path;

    if(ref($event) eq 'Mac::FSEvents::Event') {
        $path = $event->path;
    } else {
        $path = $event->{'path'};
    }
    $event = {};

    $event->{'path'} = File::Spec->canonpath($path);

    return $event;
}

sub cmp_events {
    my ( $lhs, $rhs ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    foreach my $event (@$lhs, @$rhs) {
        $event = normalize_event($event);
    }

    return is_deeply($lhs, $rhs);
};

sub test_flags {
    my ( $flags, $create_files, $expected_events ) = @_;

    reset_fs();

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    sleep 1; # wait for reset_fs triggered events to pass

    my $fs = Mac::FSEvents->new({
        path    => $tmpdir,
        latency => $TEST_LATENCY,
        flags   => $flags,
    });

    my $fh = $fs->watch;

    with_wd {
        $create_files->();
    } $tmpdir;

    my @events = map { normalize_event($_) } fetch_events($fs, $fh);

    $fs->stop;

    return cmp_events \@events, $expected_events;
}

sub test_watch_root {
    reset_fs();

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    with_wd {
        make_path('foo/bar');

        my $fs = Mac::FSEvents->new({
            path    => 'foo/bar',
            latency => $TEST_LATENCY,
            flags   => WATCH_ROOT,
        });

        my $fh = $fs->watch;

        usleep 100_000; # XXX wait a little for watcher to catch up;
                        # this is a bug that I'll fix!

        rename 'foo/bar', 'foo/baz' or die $!;

        my @events = fetch_events($fs, $fh);

        is scalar(@events), 1;
        ok $events[0]->root_changed;
    } $tmpdir;
}

test_flags(NONE, sub {
    touch_file 'foo.txt';
    touch_file 'bar.txt';
}, [
    { path => $tmpdir }, # one event, because it's coalesced
]);

test_watch_root();

SKIP: {
    skip q{Your platform doesn't support IGNORE_SELF}, 1 unless($capable_of{'IGNORE_SELF'});

    test_flags(IGNORE_SELF, sub {
        mkdir 'foo';

        system 'touch foo/bar.txt';
    }, [
        { path => "$tmpdir/foo" },
    ]);
}

SKIP: {
    skip q{Your platform doesn't support FILE_EVENTS}, 1 unless $capable_of{'FILE_EVENTS'};

    test_flags(FILE_EVENTS, sub {
        touch_file 'foo.txt';
        touch_file 'bar.txt';
    }, [
        { path => "$tmpdir/foo.txt" },
        { path => "$tmpdir/bar.txt" },
    ]);
}
