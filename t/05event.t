#!/usr/bin/perl

use strict;

use FindBin;
use File::Path;
use File::Temp;
use IO::Select;
use Mac::FSEvents;
use Scalar::Util qw(reftype);

use Test::More tests => 7;

my $tmpdir = "$FindBin::Bin/tmp";

# clean up
rmtree $tmpdir if -d $tmpdir;

# create tmpdir
mkdir $tmpdir;

my $since;

# Test a simple event
{	
	my $fs = Mac::FSEvents->new( {
		path    => $tmpdir,
		latency => 0.5,
	} );
	
	$fs->watch;
	
	my $tmp = File::Temp->new( DIR => $tmpdir );
	
	eval {
		local $SIG{ALRM} = sub { die "alarm\n" };
		alarm 3;
	
        my $seen_event;
		READ:
		while ( my @events = $fs->read_events ) {
			for my $event ( @events ) {
				my $path = $event->path;
				$since   = $event->id;
				if ( $tmp->filename =~ /^$path/ ) {
					$seen_event = 1;
					last READ;
				}
			}
		}
        ok( $seen_event, 'event received (poll interface)' );
		
		alarm 0;
	};
	
	if ( $@ ) {
		die $@ unless $@ eq "alarm\n";
	}
    ok( ! $@, 'event received (poll interface)' );
	
	$fs->stop;
}

# Test select interface
{
	my $fs = Mac::FSEvents->new( {
		path    => $tmpdir,
		latency => 0.5,
	} );
	
	my $fh = $fs->watch;
	
	# Make sure it's a real filehandle
        is( reftype($fh), 'GLOB', 'fh is a GLOB' );
	
	my $tmp = File::Temp->new( DIR => $tmpdir );
	
	eval {
		local $SIG{ALRM} = sub { die "alarm\n" };
		alarm 3;
		
		my $sel = IO::Select->new($fh);
	
        my $seen_event;
		READ:
		while ( $sel->can_read ) {
			for my $event ( $fs->read_events ) {
				my $path = $event->path;
				if ( $tmp->filename =~ /^$path/ ) {
                    $seen_event = 1;
					last READ;
				}
			}
		}
        ok( $seen_event, 'event received (select interface)' );
		
		alarm 0;
	};
	
	if ( $@ ) {
		die $@ unless $@ eq "alarm\n";
	}
    ok( ! $@, 'event received (select interface)' );
	
	$fs->stop;
}

# Test since param and that we receive a history_done flag
{
	my $fs = Mac::FSEvents->new( {
		path    => $tmpdir,
		since   => $since,
		latency => 0.5,
	} );
	
	$fs->watch;
	
	eval {
		local $SIG{ALRM} = sub { die "alarm\n" };
		alarm 3;
	
        my $seen_event;
		READ:
		while ( my @events = $fs->read_events ) {
			for my $event ( @events ) {
				if ( $event->history_done ) {
                    $seen_event = 1;
					last READ;
				}
			}
		}
        ok( $seen_event, 'history event received' );
		
		alarm 0;
	};
	
	if ( $@ ) {
		die $@ unless $@ eq "alarm\n";
	}
    ok( ! $@, 'history event received' );
	
	$fs->stop;
}

# clean up
rmtree $tmpdir if -d $tmpdir;
