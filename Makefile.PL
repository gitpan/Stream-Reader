
#
# Stream::Reader Makefile maker
#

use 5.005;
use ExtUtils::MakeMaker;

WriteMakefile(
  NAME           => 'Stream::Reader',
  VERSION_FROM   => 'lib/Stream/Reader.pm',
  ABSTRACT_FROM  => 'lib/Stream/Reader.pod',
  AUTHOR         => 'Andrian Zubko aka Ondr, <ondr@mail.ru>'
);
