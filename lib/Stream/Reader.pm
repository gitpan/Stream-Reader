package Stream::Reader;

use 5.005;
use strict;

our $VERSION = '0.03';

# Global variable(s) declaraion
my $_arg;

# Public method: Constructor
sub new {
  my $class = shift;
  my $input = shift;
  my $param = ( ref($_arg = shift) eq 'HASH' )? $_arg : {};
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
}

# Public method: readto()
sub readto {
  my $self  = shift;
  my $delim = ( ref($_arg = shift) eq 'ARRAY' )? $_arg : [$_arg];
  my $param = ( ref($_arg = shift) eq 'HASH' )? $_arg : {};
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
  ${$param->{Out}} = '' if( UNIVERSAL::isa($param->{Out},'SCALAR')
    and !( defined(${$param->{Out}}) and $param->{Mode} and index(uc($param->{Mode}),'A') != -1 ));
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
}

# Public method: readsome()
sub readsome {
  my $self  = shift;
  my $limit = ( defined($_arg = shift) and $_arg >= 0 )? $_arg : 1e10;
  my $param = ( ref($_arg = shift) eq 'HASH' )? $_arg : {};
  my $rsize;
  my $error;

  # Preparing:
  #  - reseting some statistic variables
  @$self{ qw(Readed Stored Match) } = ( (0)x2, '' );
  #  - initialize output stream, if this is SCALAR and initialization required
  ${$param->{Out}} = '' if( UNIVERSAL::isa($param->{Out},'SCALAR')
    and !( defined(${$param->{Out}}) and $param->{Mode} and index(uc($param->{Mode}),'A') != -1 ));
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
}

# Private method: BOOL = _fill_buffer()
# Trying to filling buffer with new portion of data. Returns false on errors
sub _fill_buffer {
  my $self = shift;
  return 1 unless $self->{inlimit}; # checking stream limit

  my $buffer;
  my $result;
  # Getting new portion of data
  $result = $self->_read( \($buffer),
    ( $self->{buffsize} > $self->{inlimit} )? $self->{inlimit} : $self->{buffsize} );

  # Checking data
  if( !defined($result) or ($] >= 5.008001
    and !$self->{mode_U} and $result and utf8::is_utf8($buffer) and !utf8::valid($buffer)
  )) {
    # Error reading or malformed data
    @$self{ qw(Error status inlimit bufferA bufferB) } = ( qw(1 0 0), ('')x2 );
    return 0;
  }
  else {
    # Fixing stream limit and appending data to buffers
    $self->{inlimit}  = $result? ( $self->{inlimit} - $result ) : 0;
    $self->{bufferA} .= $buffer;
    $self->{bufferB} .= lc($buffer) if $self->{mode_B};
    return 1;
  }
}

# Private method: LENGTH = SELF->_read(STRREF,LENGTH)
# Trying to reading data from input stream into STRREF
sub _read {
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
}

# Private method: BOOL = SELF->_write(OUTPUT,STRREF)
# Storing data in output stream
sub _write {
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
}

1;
