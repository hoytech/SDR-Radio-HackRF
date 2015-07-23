use strict;

use ExtUtils::MakeMaker;

my %args = (
    NAME => 'Radio::HackRF',
    VERSION_FROM => 'lib/Radio/HackRF.pm',
    PREREQ_PM => {
      'common::sense' => 0,
      'AnyEvent' => 0,
      'Math::Int64' => '0.27_04',
    },
    LIBS => '-lhackrf',
    OBJECT => '$(O_FILES)',
    DEFINE => '',
    LICENSE => 'perl',
    dist => {
      PREOP => 'pod2text $(VERSION_FROM) > $(DISTVNAME)/README',
    },
    META_MERGE => {
      resources => {
        repository => 'git://github.com/hoytech/Radio-HackRF.git',
        bugtracker => 'https://github.com/hoytech/Radio-HackRF/issues',
      },
    },
);

WriteMakefile(%args);
