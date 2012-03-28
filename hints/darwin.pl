#!/usr/bin/perl

use Config;

if ( $Config{myarchname} =~ /i386/ ) {
    my $os_version = qx(system_profiler SPSoftwareDataType);
    if($os_version =~ /System Version: Mac OS X (?:Server )?10\.(\d+)/) {
        if($1 >= 7) { # Lion and up
            $arch = "-arch x86_64 -arch i386 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.$1.sdk -mmacosx-version-min=10.$1";
        } elsif($1 >= 5) { # Leopard and up
            $arch = "-arch x86_64 -arch i386 -isysroot /Developer/SDKs/MacOSX10.$1.sdk -mmacosx-version-min=10.$1";
        } else {
            $arch = "-arch i386 -arch ppc";
        }
    } else {
        print "Could not parse version string!\n";
        print "Please file a bug report on CPAN, and include the following\n";
        print "in the description:\n";

        $os_version =~ s/^/> /gm;

        print $os_version;
        exit 1;
    }

    print "Adding $arch\n";
    
    my $ccflags   = $Config{ccflags};
    my $ldflags   = $Config{ldflags};
    my $lddlflags = $Config{lddlflags};
    
    # Remove extra -arch flags from these
    $ccflags  =~ s/-arch\s+\w+//g;
    $ldflags  =~ s/-arch\s+\w+//g;
    $lddlflags =~ s/-arch\s+\w+//g;

    $self->{CCFLAGS} = "$arch $ccflags";
    $self->{LDFLAGS} = "$arch -L/usr/lib $ldflags";
    $self->{LDDLFLAGS} = "$arch $lddlflags -framework CoreServices -framework CoreFoundation";
}
