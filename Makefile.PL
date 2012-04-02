use 5.008008;
use ExtUtils::MakeMaker;
use ExtUtils::Constant qw(WriteConstants);

use Config;

WriteMakefile(
    NAME              => 'Mac::FSEvents',
    VERSION_FROM      => 'lib/Mac/FSEvents.pm',
    PREREQ_PM         => {},
    ABSTRACT_FROM     => 'lib/Mac/FSEvents.pm',
    AUTHOR            => 'Andy Grundman <andy@hybridized.org>',
    LIBS              => [''],
    LDDLFLAGS         => $Config{lddlflags} . ' -framework CoreServices -framework CoreFoundation',
    DEFINE            => '',
    INC               => '-I.',
);

my @names = qw{
    kFSEventStreamCreateFlagNone
    kFSEventStreamCreateFlagWatchRoot
    kFSEventStreamCreateFlagIgnoreSelf
    kFSEventStreamCreateFlagFileEvents
};

foreach my $element ( @names ) {
    my $c_name = $element;

    my $perl_name = $c_name;
    $perl_name =~ s/kFSEventStreamCreateFlag//; # strip off leading name
    $perl_name =~ s/([a-z])([A-Z])/"$1_$2"/ge;  # convert camel case to underscores
    $perl_name = uc($perl_name);                # uppercase

    $element = {
        name  => $perl_name,
        value => $c_name,
        macro => 1,
    };
}

WriteConstants(
    NAME  => 'Mac::FSEvents',
    NAMES => \@names,
);
