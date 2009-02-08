use 5.008008;
use ExtUtils::MakeMaker;

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
