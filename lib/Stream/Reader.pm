package Stream::Reader;

use 5.005;
use strict;

our $VERSION = '0.06';

# Global/system variables

our $CODE;
our $AUTOLOAD;
our $Shift;

# Autoloaded code
$CODE ||= {

# Constructor
new => <<'ENDC',
  my $class = shift;
  my $input = shift;
  my $param = ( ref($Shift = shift) eq 'HASH' )? $Shift : {};
  my $self  = {
      # System parameters
    input    => $input,
    inpos    => 0,
    inlimit  => ( defined($param->{Limit}) and $param->{Limit} >= 0 )? $param->{Limit} : 1e10,
    buffsize => ( defined($param->{BuffSize}) and $param->{BuffSize} >= 0 )? $param->{BuffSize} : 32_768,
    bufferA  => '',
    bufferB  => '',
    status   => 1,
      # System flags
    mode_B  => ( $param->{Mode} and index(uc($param->{Mode}),'B') != -1 ),
    mode_U  => ( $param->{Mode} and index(uc($param->{Mode}),'U') != -1 ),
      # Statistic parameters
    Match  => '',
    Readed => 0,
    Stored => 0,
    Total  => 0,
    Error  => 0
  };
  return bless( $self => $class );
ENDC

# Destructor
DESTROY => <<'ENDC',
  return 1;
ENDC

# Public method
readto => <<'ENDC',
  my $self  = shift;
  my $delim = ( ref($Shift = shift) eq 'ARRAY' )? $Shift : [$Shift];
  my $param = ( ref($Shift = shift) eq 'HASH' )? $Shift : {};
  my $limit = ( defined($param->{Limit}) and $param->{Limit} >= 0 )? $param->{Limit} : 1e10;
  my $wcase = ( $param->{Mode} and index(uc($param->{Mode}),'I') != -1 );
  my $max_d = 0;
  my $min_d = 1e10;
  my $error;
  my $rsize;

  # Preparing:
  #  - reseting some statistic variables
  @$self{ qw(Readed Stored Match) } = ( (0)x2, '' );
  #  - initialize output stream, if this is SCALAR and initialization required
  if( UNIVERSAL::isa($param->{Out},'SCALAR')
    and !( defined(${$param->{Out}}) and $param->{Mode} and index(uc($param->{Mode}),'A') != -1 )
  ) {
    ${$param->{Out}} = '';
  }
  #  - maximal and minimal delimiter length detection
  foreach( @$delim ) {
    $max_d = length if $max_d < length;
    $min_d = length if $min_d > length;
  }
  #  - checking status and delimiter(s) presents
  return $self->{status} unless( $self->{status} and $max_d );

  # Processing:
  while(1) {
    #  - searching
    if( length($self->{bufferA}) >= $min_d ) {
      my $found = 1e10;
      my $buffer;
      $buffer = \( $self->{mode_B}? $self->{bufferB} : lc($self->{bufferA}) ) if $wcase;
      foreach( @$delim ) {
        my $pos = $wcase? index($$buffer,lc) : index($self->{bufferA},$_);
        if( $pos != -1 and $pos < $found ) {
          $found = $pos;
          $self->{Match} = $_;
        }
      }
      if( $found < 1e10 ) {
        if( !$error and $self->{Stored} < $limit ) {
          $rsize = $found;
          $rsize = $limit - $self->{Stored} if( $rsize > $limit - $self->{Stored} );
          $error = !$self->_write( $param->{Out}, \(substr( $self->{bufferA}, 0, $rsize )) );
          $self->{Stored} += $rsize unless $error;
        }
        $self->{Readed} += $found;
        $self->{Total}  += $found;
        my $psize = $found + length($self->{Match});
        substr( $self->{bufferA}, 0, $psize, '' );
        substr( $self->{bufferB}, 0, $psize, '' ) if $self->{mode_B};
        return 1;
      }
    }
    #  - move part data to output stream
    if( length($self->{bufferA}) >= $max_d ) {
      my $psize = length($self->{bufferA}) - ($max_d - 1);
      if( !$error and $self->{Stored} < $limit ) {
        $rsize = $psize;
        $rsize = $limit - $self->{Stored} if( $rsize > $limit - $self->{Stored} );
        $error = !$self->_write( $param->{Out}, \(substr( $self->{bufferA}, 0, $rsize )) );
        $self->{Stored} += $rsize unless $error;
      }
      $self->{Readed} += $psize;
      $self->{Total}  += $psize;
      substr( $self->{bufferA}, 0, $psize, '' );
      substr( $self->{bufferB}, 0, $psize, '' ) if $self->{mode_B};
    }
    #  - if limit not ended yet then trying to fill buffer
    #  - else move last data to output stream and finish
    if( $self->{inlimit} ) {
      return 0 unless $self->_fill_buffer();
    }
    else {
      if( length $self->{bufferA} ) {
        $rsize = length $self->{bufferA};
        $self->{Readed} += $rsize;
        $self->{Total}  += $rsize;
        if( !$error and $self->{Stored} < $limit ) {
          $rsize = $limit - $self->{Stored} if( $rsize > $limit - $self->{Stored} );
          $error = !$self->_write( $param->{Out}, \(substr( $self->{bufferA}, 0, $rsize )) );
          $self->{Stored} += $rsize unless $error;
        }
        $self->{bufferA} = '';
        $self->{bufferB} = '' if $self->{mode_B};
      }
      $self->{status} = 0;
      return( ( $param->{Mode} and index(uc($param->{Mode}),'E') != -1 )? 0 : 1 );
    }
  }
ENDC

# Public method
readsome => <<'ENDC',
  my $self  = shift;
  my $limit = ( defined($Shift = shift) and $Shift >= 0 )? $Shift : 1e10;
  my $param = ( ref($Shift = shift) eq 'HASH' )? $Shift : {};
  my $rsize;
  my $error;

  # Preparing:
  #  - reseting some statistic variables
  @$self{ qw(Readed Stored Match) } = ( (0)x2, '' );
  #  - initialize output stream, if this is SCALAR and initialization required
  if( UNIVERSAL::isa($param->{Out},'SCALAR')
    and !( defined(${$param->{Out}}) and $param->{Mode} and index(uc($param->{Mode}),'A') != -1 )
  ) {
    ${$param->{Out}} = '';
  }
  #  - checking status
  return 0 unless $self->{status};

  # Processing:
  while( $self->{Readed} < $limit ) {
    #  - trying to fill buffer
    unless( length $self->{bufferA} ) {
      return 0 unless $self->_fill_buffer();
    }
    #  - if buffer still empty then break cycle
    #  - else if not enouth data in buffer, then move all data from buffer to output stream
    #  - else move necessary of characters to output stream  and break cycle
    unless( length $self->{bufferA} ) {
      $self->{status} = 0;
      return( $self->{Readed} ? 1 : 0 );
    }
    elsif( length($self->{bufferA}) <= $limit - $self->{Readed} ) {
      $error = !$self->_write( $param->{Out}, \($self->{bufferA}) ) unless $error;
      $rsize = length $self->{bufferA};
      $self->{Stored} += $rsize unless $error;
      $self->{Readed} += $rsize;
      $self->{Total}  += $rsize;
      $self->{bufferA} = '';
      $self->{bufferB} = '' if $self->{mode_B};
    }
    else {
      $rsize = $limit - $self->{Readed};
      $error = !$self->_write( $param->{Out}, \(substr( $self->{bufferA}, 0, $rsize )) ) unless $error;
      $self->{Stored} += $rsize unless $error;
      $self->{Readed} += $rsize;
      $self->{Total}  += $rsize;
      substr( $self->{bufferA}, 0, $rsize, '' );
      substr( $self->{bufferB}, 0, $rsize, '' ) if $self->{mode_B};
      last;
    }
  }
  return 1;
ENDC

# Private method: BOOL = _fill_buffer()
# Trying to filling buffer with new portion of data. Returns false on errors
_fill_buffer => <<'ENDC',
  my $self = shift;

  if( $self->{inlimit} ) { # checking stream limit
    my $buffer;
    my $result;
    # Getting new portion of data
    $result = $self->_read( \$buffer,
      ( $self->{buffsize} > $self->{inlimit} )? $self->{inlimit} : $self->{buffsize}
    );
    # Checking data
    if( !defined($result) or ($] >= 5.008001
      and !$self->{mode_U} and $result and utf8::is_utf8($buffer) and !utf8::valid($buffer)
    )) {
      # Error reading or malformed data
      @$self{ qw(Error status inlimit bufferA bufferB) } = ( qw(1 0 0), ('')x2 );
      return undef;
    } else {
      # Fixing stream limit and appending data to buffers
      $self->{inlimit}  = $result? ( $self->{inlimit} - $result ) : 0;
      $self->{bufferA} .= $buffer;
      $self->{bufferB} .= lc($buffer) if $self->{mode_B};
    }
  }
  return 1;
ENDC

# Private method: LENGTH = SELF->_read(STRREF,LENGTH)
# Trying to reading data from input stream into STRREF
_read => <<'ENDC',
  my $self   = shift;
  my $strref = shift;
  my $length = shift;
  my $result;

  # Checking type of stream:
  #  - if SCALAR, then copy part of data from SCALAR variable
  #  - if TYPEGLOB, then reading next part of data from file stream
  if( UNIVERSAL::isa($self->{input},'SCALAR') ) {
    $result = length(${$self->{input}}) - $self->{inpos};
    $result = $length if $result > $length;
    $result = 0 if $result < 0;
    $$strref = substr( ${$self->{input}}, $self->{inpos}, $result );
    $self->{inpos} += $result;
  }
  elsif( UNIVERSAL::isa($self->{input},'GLOB') ) {
    $result = read( $self->{input}, $$strref, $length );
  }
  return $result;
ENDC

# Private method: BOOL = SELF->_write(OUTPUT,STRREF)
# Storing data in output stream
_write => <<'ENDC',
  my $self   = shift;
  my $output = shift;
  my $strref = shift;
  my $result;

  # Checking type of reference:
  #  - if SCALAR, then appending data to SCALAR variable
  #  - if TYPEGLOB, then writing data to file stream
  if( UNIVERSAL::isa($output,'SCALAR') ) {
    $$output .= $$strref;
    $result = 1; # alltimes true result
  }
  elsif ( UNIVERSAL::isa($output,'GLOB') ) {
    $result = print( {$output} $$strref );
  }
  return $result;
ENDC

};

sub AUTOLOAD {
  my($name) = $AUTOLOAD =~ /([^:]+)$/;
  unless( exists $CODE->{$name} ) {
    _croak("Undefined subroutine &$AUTOLOAD called") if $^W;
  } else {
    eval "sub $name { ".delete($CODE->{$name})." }";
    if( $@ and $^W ) {
      warn $@; # it is better then nothing..
    }
    goto &$AUTOLOAD;
  }
}

# Handling warnings
sub _croak { require Carp; Carp::croak(shift) }

1;

__END__

=head1 NAME

Stream::Reader - is a stream reader

=head1 SYNOPSIS

  # Input stream can be reference to TYPEGLOB or SCALAR, output stream
  # can be the same types or undefined

  # Constructor
  $stream = Stream::Reader->new( \*IN,
    { Limit => $limit, BuffSize => $buffsize, Mode => 'UB' } );

  # Reading all before delimiter beginning from current position.
  # Delimiter is SCALAR or reference to array with many SCALAR's.
  # Returns true value on succesfull matching or if end of stream
  # expected at first time
  $bool = $stream->readto( $delimiter,
    { Out => \*OUT, Limit => $limit, Mode => 'AIE' } );

  # Reading fixed number of chars beginning from current position.
  # Returns true value if was readed number of chars more then zero or
  # end of stream was not expected yet
  $bool = $stream->readsome( $limit, { Out => \*OUT, Mode => 'A' } );

  # Mode is string, what can contains:
  #  U - modificator for constructor. disable utf-8 checking
  #  B - modificator for constructor. enable second buffer for speed up
  #      case insensitive search
  #  A - modificator for readto() and readsome(). appending data to
  #      output stream, if stream is SCALAR
  #  I - modificator for readto(). enable case insensitive search
  #  E - modificator for readto(). at end of input stream alltimes
  #      returns false value

  $number = $stream->{Total};  # total number of readed chars
  $number = $stream->{Readed}; # number of readed chars at last
                               # operation (without matched string
                               # length at readto() method)
  $number = $stream->{Stored}; # number of succesfully stored chars
                               # at last operation
  $string = $stream->{Match};  # matched string at last operation
                               # (actually for readto() only)
  $bool   = $stream->{Error};  # error status. true on error

=head1 DESCRIPTION

This is utility intended for reading data from streams. Can be used
for "on the fly" parsing big volumes data.

=head1 METHODS

=over 4

=item OBJ = Stream::Reader->new( INPUT, { ... Params ... } )

The constructor method instantiates a new Stream::Reader object.

INPUT - is a reference to file stream, opened for reading,
or reference to defined string. This is an obligatory parameter.

Params (all optionaly):

=over 2

Limit - limit size of input stream data in characters. If this
parameter is absent, not defined or less then zero, then all data
from input stream will be available for reading.

BuffSize - size of buffer in characters. If this parameter is absent,
not defined or less then zero, then will be used default buffer size
32768 characters.

FLAGS - 2 modificators are available in this method:

Mode - is string with letters-modificators:

=over 2

B - use second buffer. Can really speed up search in case
insensitive mode.

U - disable UTF-8 data check in UTF-8 mode. Use this flag if you are
absolutely sure, that your UTF-8 data is valid.

=back

=back

=item RESULT = OBJ->readto( DELIMITER, { ... Params ... } )

This method reads all data from input stream before first found
delimiter, beginning from current position.

RESULT - boolean value. True value if successfuly found delimeter
or and of input stream has expected at first time. False value
otherwise, or in case of reading error.

DELIMETER - is a string-delimeter or reference to array with
many delimeters. This is an obligatory parameter and must be
defined.

Remember! In case of many delimiters, left delimiter alltimes have
more priority then right!

Params (all optionaly):

=over 2

Out - is a reference to file stream, opened for writing,
or reference to string. If this parameter is absent then data
will not stored.

Limit - size in characters. Defines, the maximum number of
characters that must be stored in Out. If this paramter is absent,
not defined or less then zero, then this method will be trying to
store all readed data.

Mode - is string with letters-modificators:

=over 2

A - appendig data to Out if Out is a reference to string.

I - search in case insensitive mode.

E - at the end of input stream returns only false value. Without this
modificator, if end of stream expected at first time, then will be
returned true value.

=back

=back

=item RESULT = OBJ->readsome( LIMIT, { ... Params ... } )

This method reads fixed number of characters from input stream
beginning from current position.

RESULT - boolean value. True value, if any characters were read or
end of input stream is not expected yet. False value otherwise, or
in case of reading error.

LIMIT - limit size in characters, how many it is necessary to read.
If this parameter is absent, not defined or less then zero, then will
be read all available data from input stream.

Params (all optionaly):

=over 2

Out - the same as in readto() method.

Mode - is string with letters-modificators:

=over 2

A - the same as in readto() method.

=back

=back

=item Statistics:

OBJ->{Total} - total number of readed characters. Warning! This
module using block reading and real position in stream is different.

OBJ->{Readed} - number of readed characters at last operation
(without matched string length at readto() method).

OBJ->{Stored} - number of succesfully stored chars at last operation

OBJ->{Match} - matched string at last operation (actually for
readto() only)

OBJ->{Error} - boolen error status. At any reading erorrs
all operations will be stopes and this flag turned to true value.

=back

=head1 UTF-8 SUPPORT

Fully supported when using perl version 5.8.1, or higher. Input
stream, output stream and delimiters should be in UTF-8 mode. If,
during reading data from input stream in UTF-8 mode, will be detected
malformed data, then will be stoped any operations and status Error
turned to true value.

=head1 WARNINGS

Remember! This class is using block reading and before
destruct class-object, you should work with input stream only
through these class methods.

In UTF-8 mode search without case sensitive is very slowly..
It is because operation of changing case on UTF-8 data has
slow speed.

Remember, in UTF-8 mode all sizes of this module contain
characters, not bytes!

=head1 EXAMPLES

=head2 Reading configuration file:

  open( my $fh, '<', 'config.txt' ) or die $!;
  my $stream = Stream::Reader->new($fh);

  my $line;
  while( $stream->readto( "\r\n", { Out => \$line } ) ) {
    # Do something with $line
  }
  close($fh) or die $!;

=head2 Find first one of substrings in file without case sensitive:

  # Initialize array of strings
  my @strings = ( 'word1', 'word2', 'phrase 1', 'word3' );

  open( my $fh, '<', 'file.txt' ) or die $!;
  my $stream = Stream::Reader->new($fh);

  # Now, let trying to find one of substrings
  my $r = $stream->readto( \@strings, { Mode => 'IE' } );

  if( $r ) {
    print "Found substring '$stream->{Match}'\n";
  } elsif( $stream->{Error} ) {
    print "Fatal error during reading file!\n";
  } else {
    print "Nothing found..\n";
  }
  close($fh) or die $!;

=head1 Special thanks too:

Andrey Fimushkin, E<lt>plohaja@mail.ruE<gt>

=head1 AUTHOR

Andrian Zubko aka Ondr, E<lt>ondr@cpan.orgE<gt>

=cut
