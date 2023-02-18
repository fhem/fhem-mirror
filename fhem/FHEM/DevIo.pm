##############################################
# $Id$
package main;

use strict;

sub DevIo_CloseDev($@);
sub DevIo_DecodeWS($$);
sub DevIo_Disconnected($);
sub DevIo_Expect($$$);
sub DevIo_OpenDev($$$;$);
sub DevIo_SetHwHandshake($);
sub DevIo_SimpleRead($);
sub DevIo_SimpleReadWithTimeout($$);
sub DevIo_SimpleWrite($$$;$);
sub DevIo_TimeoutRead($$;$$);

sub
DevIo_setStates($$)
{
  my ($hash, $val) = @_;
  setReadingsVal($hash, "state", $val, TimeNow());
  if($hash->{devioNoSTATE}) {
    evalStateFormat($hash);
  } else {
    $hash->{STATE} = $val;
  }
}

sub
DevIo_getState($)
{
  my ($hash) = @_;
  return ReadingsVal($hash->{NAME}, "state", "disconnected")
}

########################
# Try to read once from the device.
# "private" function
sub
DevIo_DoSimpleRead($)
{
  my ($hash) = @_;
  my ($buf, $res);

  if($hash->{USBDev}) {
    $buf = $hash->{USBDev}->input();

  } elsif($hash->{DIODev}) {
    $res = sysread($hash->{DIODev}, $buf, 4096);
    $buf = undef if(!defined($res));

  } elsif($hash->{TCPDev}) {
    $res = sysread($hash->{TCPDev}, $buf, 4096);
    $buf = "" if(!defined($res));

  } elsif($hash->{IODev}) {

    if($hash->{IOReadFn}) {
      $buf = CallFn($hash->{IODev}{NAME},"IOReadFn",$hash);

    } else {
      $buf = $hash->{IODevRxBuffer};
      $hash->{IODevRxBuffer} = "";
      $buf = "" if(!defined($buf));
    }

  }
  return $buf;
}

########################
# This is the function to read data, to be called in ReadFn.
# If there is no data, sets the device to disconnected, which results in
# polling via ReadyFn, trying to open it.
sub
DevIo_SimpleRead($)
{
  my ($hash) = @_;
  my $buf = DevIo_DoSimpleRead($hash);

  if(length($buf) == 0 && $! == EWOULDBLOCK && $hash->{SSL} && $hash->{TCPDev}) {
    my $es = $hash->{TCPDev}->errstr;
    $hash->{wantWrite} = 1 if($es == &IO::Socket::SSL::SSL_WANT_WRITE);
    $hash->{wantRead}  = 1 if($es == &IO::Socket::SSL::SSL_WANT_READ);
    return "";
  }

  ###########
  # Lets' try again: Some drivers return len(0) on the first read...
  if(defined($buf) && length($buf) == 0) {
    $buf = DevIo_SimpleReadWithTimeout($hash, 0.01); # Forum #57806
  }

  if(!defined($buf) || length($buf) == 0) {
    DevIo_Disconnected($hash);
    return undef;
  }

  return DevIo_DecodeWS($hash, $buf) if($hash->{WEBSOCKET});
  return $buf;
}

########################
# wait at most timeout seconds until the file handle gets ready
# for reading; returns undef on timeout
# NOTE1: FHEM can be blocked for $timeout seconds, DO NOT USE IT!
# NOTE2: This works on Windows only for TCP connections
sub
DevIo_SimpleReadWithTimeout($$)
{
  my ($hash, $timeout) = @_;

  my $rin = "";
  vec($rin, $hash->{FD}, 1) = 1;
  my $nfound = select($rin, undef, undef, $timeout);
  return DevIo_DoSimpleRead($hash) if($nfound> 0);
  return undef;
}

########################
# Read until the timeout occures
# NOTE1: FHEM WILL be blocked for $timeout seconds, DO NOT USE IT!
# NOTE2: This works on Windows only for TCP connections
sub
DevIo_TimeoutRead($$;$$)
{
  my ($hash, $timeout, $maxlen, $regexp) = @_;

  my $answer = "";
  $timeout = 1 if(!$timeout);
  $maxlen = 1024 if(!$maxlen);    # Avoid endless loop
  for(;;) {
    my $rin = "";
    vec($rin, $hash->{FD}, 1) = 1;
    my $nfound = select($rin, undef, undef, $timeout);
    last if($nfound <= 0);      # timeout
    my $r = DevIo_DoSimpleRead($hash);
    last if(!defined($r) || ($r eq "" && $hash->{TCPDev}));
    $answer .= $r;
    last if(length($answer) >= $maxlen || ($regexp && $answer =~ m/$regexp/));
  }
  return $answer;
}

sub
DevIo_MaskWS($$)
{
  my ($opcode,$msg) = @_;
  $opcode = pack("C",$opcode|0x80);

  my $len = length($msg);
  my $lb;
  if($len < 126) {
    $lb = chr(0x80+$len);
  } else {
    if ($len < 65536) {
      $lb = chr(0xFE).pack('n',$len);
    } else {
      $lb = chr(0xFF).chr(0x00).chr(0x00).chr(0x00).chr(0x00).pack('N',$len);
    }
  }

  my $mask = pack("L",rand(2**32));
  my @m = unpack("C*", $mask);
  my $idx = 0;
  $msg = pack("C*", map { $_ ^ $m[$idx++ % 4] } unpack("C*", $msg));
  return $opcode.$lb.$mask.$msg;
}

my %wsCloseCode = (
  1000=>"normal",
  1001=>"going away",
  1002=>"protocol error",
  1003=>"cannot accept datatype",
  1007=>"inconsistent data",
  1008=>"policy violation",
  1009=>"too big",
  1010=>"missing extension",
  1011=>"unexpected condition"
);

sub
DevIo_Ping($;$)
{
  my ($hash,$msg) = @_;
  $msg="" if(!defined($msg));
  syswrite($hash->{TCPDev}, DevIo_MaskWS(0x9, $msg)) if($hash->{WEBSOCKET});
}

sub
DevIo_DecodeWS($$)
{
  my ($hash, $buf) = @_;
  # https://tools.ietf.org/html/rfc6455
  $hash->{".WSBUF"} = "" if(!defined($hash->{".WSBUF"}));
  $hash->{".WSBUF"} .= $buf;
  my $data = $hash->{".WSBUF"};
  return "" if(length($data) < 2);

  my $fin  = (ord(substr($data,0,1)) & 0x80)?1:0;
  my $op   = (ord(substr($data,0,1)) & 0x0F);
  my $mask = (ord(substr($data,1,1)) & 0x80)?1:0;
  my $len  = (ord(substr($data,1,1)) & 0x7F);
  my $i = 2;

  if( $len == 126 ) {
    return "" if(length($data) < 4);
    $len = unpack('n', substr($data, $i, 2));
    $i += 2;
  } elsif( $len == 127 ) {
    return "" if(length($data) < 10);
    $len = unpack( 'Q>', substr($hash->{".WSBUF"},$i,8) );
    $i += 8;
  }

  my @m;
  if($mask) {
    return "" if(length($data) < $i+4);
    @m = unpack("C*", substr($data,$i,4));
    $i += 4;
  }
  return "" if(length($data) < $i+$len);

  $hash->{".WSBUF"} = substr($data, $i+$len);
  $data = substr($data, $i, $len);
  if($mask) {
    my $idx = 0;
    $data = pack("C*", map { $_ ^ $m[$idx++ % 4] } unpack("C*", $data));
  }

  # $op: 0=>Continuation, 1=>Text, 2=>Binary, 8=>Close, 9=>Ping, 10=>Pong
  Log3 $hash, 5, "Websocket msg: OP:$op LEN:$len MASK:$mask FIN:$fin";
  if($op == 1) {              # Text
    $data = Encode::decode('UTF-8', $data) if($unicodeEncoding);

  } elsif($op == 8) {         # Close
    my $clCode = unpack("n", substr($data,0,2));
    $clCode = "$clCode ($wsCloseCode{$clCode})" if($wsCloseCode{$clCode});
    $clCode .= " ".substr($data, 2) if($len > 2);
    Log3 $hash, 5, "Websocket close, reason: $clCode";
    syswrite($hash->{TCPDev}, DevIo_MaskWS(0x8,$data));
    DevIo_CloseDev($hash);
    return undef;

  } elsif($op == 9) {   # Ping
    syswrite($hash->{TCPDev}, DevIo_MaskWS(0xA, $data)); # Pong
    Log3 $hash, 5, "Websocket ping: $data" if($data);
    return DevIo_DecodeWS($hash, "");

  } elsif($op == 10) {   # Pong
    Log3 $hash, 5, "Websocket pong: $data" if($data);
    return ""

  }

  if(length($hash->{".WSBUF"})) { # There is more data to digest
    my $nd = DevIo_DecodeWS($hash, "");
    $data .= $nd if(defined($nd));
  }

  return $data;
}

########################
# Function to write data
sub
DevIo_SimpleWrite($$$;$)
{
  my ($hash, $msg, $type, $addnl) = @_; # Type: 0:binary, 1:hex, 2:ASCII
  return if(!$hash);

  my $name = $hash->{NAME};
  Log3 $name, 5, "DevIo_SimpleWrite $name: ".($type ? $msg : unpack("H*",$msg));

  $msg = pack('H*', $msg) if($type && $type == 1);
  $msg .= "\n" if($addnl);
  if($hash->{USBDev}){
    $hash->{USBDev}->write($msg);

  } elsif($hash->{TCPDev}) {
    if($hash->{WEBSOCKET}) {
      $msg = Encode::encode('UTF-8', $msg)
        if($unicodeEncoding && !$hash->{binary});
      $msg = DevIo_MaskWS($hash->{binary} ? 0x2:0x1, $msg);
    }
    syswrite($hash->{TCPDev}, $msg);

  } elsif($hash->{DIODev}) { 
    syswrite($hash->{DIODev}, $msg);

  } elsif($hash->{IODev}) { 
    CallFn($hash->{IODev}{NAME},"IOWriteFn",$hash,$msg);

  }
  select(undef, undef, undef, 0.001);
}

########################
# Write something, then read something
# reopen device if timeout occurs and write again, then read again
# NOTE1: FHEM can be blocked for $timeout seconds, DO NOT USE IT!
sub
DevIo_Expect($$$)
{
  my ($hash, $msg, $timeout) = @_;
  my $name= $hash->{NAME};
  
  my $state= DevIo_getState($hash);
  if($state ne "opened") {
    Log3 $name, 2, "Attempt to write to $state device.";
    return undef;
  }
  # write something
  return undef unless defined(DevIo_SimpleWrite($hash, $msg, 0));
  # read answer
  my $answer= DevIo_SimpleReadWithTimeout($hash, $timeout);
  return $answer unless($answer eq "");
    # the device has failed to deliver a result
  DevIo_setStates($hash, "failed");
  DoTrigger($name, "FAILED");

  # reopen device
  # unclear how to know whether the following succeeded
  Log3 $name, 2, "$name: first attempt to read timed out, ".
                        "trying to close and open the device.";

  # The next two lines are required to avoid a deadlock when the remote end
  # closes the connection upon DevIo_OpenDev, as e.g. netcat -l <port> does.
  DevIo_CloseDev($hash);
  DevIo_OpenDev($hash, 0, undef); # where to get the initfn from? 

  # write something again
  return undef unless defined(DevIo_SimpleWrite($hash, $msg, 0));

  # read answer again
  $answer= DevIo_SimpleReadWithTimeout($hash, $timeout);

  # success
  if($answer ne "") {
    DevIo_setStates($hash, "opened");
    DoTrigger($name, "CONNECTED");
    return $answer;
  }

  # ultimate failure
  Log3 $name, 2,
    "$name: second attempt to read timed out, this is an unrecoverable error.";
  DoTrigger($name, "DISCONNECTED");
  return undef; # undef means ultimate failure
}


########################
# Open a device for reading/writing data.
# Possible values for $hash->{DeviceName}:
# - device@baud[78][NEO][012] => open device, set serial-line parameters
# - hostname:port => TCP/IP client connection (set $hash->{SSL}=>1 for TLS)
# - ws:hostname:port => websocket connection (wss: sets $hash->{SSL}=1)
# - device@directio => open device without additional "magic"
# - UNIX:(SEQPACKET|STREAM):filename => Open filename as a UNIX socket
# - FHEM:DEVIO:IoDev[:IoPort] => Cascade I/O over another FHEM Device
#
# callback is only meaningful for TCP/IP, in which case a nonblocking connect
# is executed. It will be called with $hash and a (potential) error message.
# If # $hash->{SSL} is set, SSL encryption is activated.

sub
DevIo_OpenDev($$$;$)
{
  my ($hash, $reopen, $initfn, $callback) = @_;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $po;
  my $baudrate;
  ($dev, $baudrate) = split("@", $dev);
  my ($databits, $parity, $stopbits) = (8, 'none', 1);
  my $nextOpenDelay = ($hash->{nextOpenDelay} ? $hash->{nextOpenDelay} : 60);

  # Call the callback if specified, simply return in other cases
  my $doCb = sub ($) {
    my ($r) = @_;
    Log3 $name, 1, "$name: Can't connect to $dev: $r" if(!$reopen && $r);
    no strict "refs";
    $callback->($hash,$r) if($callback);
    use strict "refs";
    return ($callback ? undef : $r);
  };

  # Call initFn
  # if fails: disconnect, schedule the next polltime for reopen
  # if ok: log message, trigger CONNECTED on reopen
  my $doTailWork = sub {
    DevIo_setStates($hash, "opened");

    my $ret;
    if($initfn) {
      my $hadFD = defined($hash->{FD});
      no strict "refs";
      $ret = &$initfn($hash);
      use strict "refs";
      if($ret) {
        if($hadFD && !defined($hash->{FD})) { # Forum #54732 / ser2net
          DevIo_Disconnected($hash);
          $hash->{NEXT_OPEN} = gettimeofday() + $nextOpenDelay;

        } else {
          DevIo_CloseDev($hash);
          Log3 $name, 1, "Cannot init $dev, ignoring it ($name)";
        }
      }
    }

    if(!$ret) {
      my $l = $hash->{devioLoglevel}; # Forum #61970
      if($reopen) {
        Log3 $name, ($l ? $l:1), "$dev reappeared ($name)";
      } else {
        Log3 $name, ($l ? $l:3), "$name device opened" if(!$hash->{DevioText});
      }
    }

    DoTrigger($name, "CONNECTED") if(!$ret);
    return undef;
  };
  
  $baudrate = "" if(!defined($baudrate));
  if($baudrate =~ m/(\d+)(,([78])(,([NEO])(,([012]))?)?)?/) {
    $baudrate = $1 if(defined($1));
    $databits = $3 if(defined($3));
    $parity = 'odd'  if(defined($5) && $5 eq 'O');
    $parity = 'even' if(defined($5) && $5 eq 'E');
    $stopbits = $7 if(defined($7));
  }

  if($hash->{DevIoJustClosed}) {
    delete $hash->{DevIoJustClosed};
    return &$doCb(undef);
  }

  $hash->{PARTIAL} = "";
  my $l = $hash->{devioLoglevel}; # Forum #61970
  Log3 $name, ($l ? $l:3), ($hash->{DevioText} ? $hash->{DevioText} : "Opening").
       " $name device ". (AttrVal($name,"privacy",0) ? "(private)" : $dev)
       if(!$reopen);

  if($dev =~ m/^UNIX:(SEQPACKET|STREAM):(.*)$/) { # FBAHA
    my ($type, $fname) = ($1, $2);
    my $conn;
    eval {
      require IO::Socket::UNIX;
      $conn = IO::Socket::UNIX->new(
        Type=>($type eq "STREAM" ? SOCK_STREAM:SOCK_SEQPACKET), Peer=>$fname);
    };
    if($@) {
      Log3 $name, 1, $@;
      return &$doCb($@);
    }

    if(!$conn) {
      Log3 $name, 1, "$name: Can't connect to $dev: $!" if(!$reopen);
      $readyfnlist{"$name.$dev"} = $hash;
      DevIo_setStates($hash, "disconnected");
      return &$doCb("");
    }
    $hash->{TCPDev} = $conn;
    $hash->{FD} = $conn->fileno();
    delete($readyfnlist{"$name.$dev"});
    $selectlist{"$name.$dev"} = $hash;

  } elsif($dev =~ m/^FHEM:DEVIO:(.*)(:(.*))/) {      # Forum #46276
    my ($devName, $devPort) = ($1, $3);
    AssignIoPort($hash, $devName);
    if (defined($hash->{IODev})) {
      ($dev, $baudrate) = split("@", $hash->{DeviceName});
      $hash->{IODevPort} = $devPort if (defined($devPort));
      $hash->{IODevParameters} = $baudrate if (defined($baudrate));
      if (!CallFn($devName, "IOOpenFn", $hash)) {
        Log3 $name, 1, "$name: Can't open $dev!";
        DevIo_setStates($hash, "disconnected");
        return &$doCb("");
      }
    } else {
      DevIo_setStates($hash, "disconnected");
      return &$doCb("");
    }

  } elsif($dev =~ m,^(ws:|wss:)?([^/:]+):([0-9]+)(.*?)$,) {# TCP or websocket
   
    my ($proto, $host, $port, $path) = ($1 ? $1 : "", $2, $3, $4);
    my $hp = "$host:$port";
    if($proto eq "wss:")  {
      $hash->{SSL} = 1;
      $proto = "ws:";
    }
    if($proto eq "ws:")  {
      require MIME::Base64;
      return &$doCb('websocket is only supported with callback') if(!$callback);
    }
    $path = "/" if(!defined($path) || $path eq "");

    # This part is called every time the timeout (5sec) is expired _OR_
    # somebody is communicating over another TCP connection. As the connect
    # for non-existent devices has a delay of 3 sec, we are sitting all the
    # time in this connect. NEXT_OPEN tries to avoid this problem.
    if($hash->{NEXT_OPEN} && gettimeofday() < $hash->{NEXT_OPEN}) {
      return &$doCb(undef); # Forum 53309
    }

    delete($readyfnlist{"$name.$dev"});
    my $timeout = $hash->{TIMEOUT} ? $hash->{TIMEOUT} : 3;

    # Do common TCP/IP "afterwork":
    # if connected: set keepalive, fill selectlist, FD, TCPDev.
    # if not: report the error and schedule reconnect
    my $doTcpTail = sub($) {
      my ($conn) = @_;
      if($conn) {
        delete($hash->{NEXT_OPEN});
        $conn->setsockopt(SOL_SOCKET, SO_KEEPALIVE, 1) if(defined($conn));

      } else {
        Log3 $name, 1, "$name: Can't connect to $dev: $!" if(!$reopen && $!);
        $readyfnlist{"$name.$dev"} = $hash;
        DevIo_setStates($hash, "disconnected");
        DoTrigger($name, "DISCONNECTED") if(!$reopen);
        $hash->{NEXT_OPEN} = gettimeofday() + $nextOpenDelay;
        return 0;
      }

      $hash->{WEBSOCKET} = 1 if($proto eq "ws:");
      $hash->{TCPDev} = $conn;
      $hash->{FD} = $conn->fileno();
      $hash->{CD} = $conn;
      $selectlist{"$name.$dev"} = $hash;
      return 1;
    };

    if($callback) { # reuse the nonblocking connect from HttpUtils.
      use HttpUtils;

      my %header = ();
      if($proto eq "ws:") {
        %header = (
          "Connection" => "Upgrade",
          "Upgrade" => "websocket",
          "Sec-WebSocket-Key"=>encode_base64(pack("H*",createUniqueId()),""),
          "Sec-WebSocket-Version" => 13
        );
      }
      map { $header{$_} = $hash->{header}{$_} } keys %{$hash->{header}}
        if($hash->{header});

      my $err = HttpUtils_Connect({     # Nonblocking
        timeout => $timeout,
        url     => $hash->{SSL} ? "https://$hp$path" : "http://$hp$path",
        NAME    => $hash->{NAME},
        sslargs => $hash->{sslargs} ? $hash->{sslargs} : {},
        noConn2 => $proto eq "ws:" ? 0 : 1,
        keepalive=>$proto eq "ws:" ? 1 : 0,
        httpversion=>$proto eq "ws:" ? "1.1" : "1.0",
        header  => \%header,
        sslargs => $hash->{sslargs},
        callback=> sub() {
          my ($h, $err, undef) = @_;
          $err = "HTTP CODE $h->{code}"
                if($proto eq "ws:" && !$err && $h->{code} != 101);
          &$doTcpTail($err ? undef : $h->{conn});
          return &$doCb($err ? $err : &$doTailWork());
        }
      });
      return &$doCb($err) if($err);
      return undef;     # no double callback: connect is running in bg now

    } else {    # blocking connect
      my $conn = $haveInet6 ? 
          IO::Socket::INET6->new(PeerAddr => $hp, Timeout => $timeout) :
          IO::Socket::INET ->new(PeerAddr => $hp, Timeout => $timeout);
      return "" if(!&$doTcpTail($conn)); # no callback: no doCb
    }

  } elsif($baudrate && lc($baudrate) eq "directio") { # w/o Device::SerialPort

    if(!open($po, "+<$dev")) {
      return &$doCb(undef) if($reopen);
      Log3 $name, 1, "$name: Can't open $dev: $!";
      $readyfnlist{"$name.$dev"} = $hash;
      DevIo_setStates($hash, "disconnected");
      return &$doCb("");
    }

    $hash->{DIODev} = $po;

    if( $^O =~ /Win/ ) {
      $readyfnlist{"$name.$dev"} = $hash;
    } else {
      $hash->{FD} = fileno($po);
      delete($readyfnlist{"$name.$dev"});
      $selectlist{"$name.$dev"} = $hash;
    }


  } else {                              # USB/Serial device

    if ($^O=~/Win/) {
     eval {
       require Win32::SerialPort;
       $po = new Win32::SerialPort ($dev);
     }
    } else  {
     eval {
       require Device::SerialPort;
       $po = new Device::SerialPort ($dev);
     }
    }
    if($@) {
      Log3 $name,  1, $@;
      return &$doCb($@);
    }

    if(!$po) {
      return &$doCb(undef) if($reopen);
      Log3 $name, 1, "$name: Can't open $dev: $!";
      $readyfnlist{"$name.$dev"} = $hash;
      DevIo_setStates($hash, "disconnected");
      return &$doCb("");
    }
    $hash->{USBDev} = $po;
    if( $^O =~ /Win/ ) {
      $readyfnlist{"$name.$dev"} = $hash;
    } else {
      $hash->{FD} = $po->FILENO;
      delete($readyfnlist{"$name.$dev"});
      $selectlist{"$name.$dev"} = $hash;
    }

    if($baudrate) {
      $po->reset_error();
      my $p = ($parity eq "none" ? "N" : ($parity eq "odd" ? "O" : "E"));
      Log3 $name, 3, "Setting $name serial parameters to ".
                    "$baudrate,$databits,$p,$stopbits" if(!$hash->{DevioText});
      $po->baudrate($baudrate);
      $po->databits($databits);
      $po->parity($parity);
      $po->stopbits($stopbits);
      $po->handshake('none');

      # This part is for some Linux kernel versions whih has strange default
      # settings.  Device::SerialPort is nice: if the flag is not defined for
      # your OS then it will be ignored.

      $po->stty_icanon(0);
      #$po->stty_parmrk(0); # The debian standard install does not have it
      $po->stty_icrnl(0);
      $po->stty_echoe(0);
      $po->stty_echok(0);
      $po->stty_echoctl(0);

      # Needed for some strange distros
      $po->stty_echo(0);
      $po->stty_icanon(0);
      $po->stty_isig(0);
      $po->stty_opost(0);
      $po->stty_icrnl(0);
    }

    $po->write_settings;
  }

  return &$doCb(&$doTailWork());
}

sub
DevIo_SetHwHandshake($)
{
  my ($hash) = @_;
  $hash->{USBDev}->can_dtrdsr();
  $hash->{USBDev}->can_rtscts();
}

########################
# close the device, remove it from selectlist, 
# delete DevIo specific internals from $hash
sub
DevIo_CloseDev($@)
{
  my ($hash,$isFork) = @_;
  my $name = $hash->{NAME};
  my $dev = $hash->{DeviceName};

  return if(!$dev);
  
  if($hash->{TCPDev}) {
    if($isFork && $hash->{SSL}) { # Forum #94219
      $hash->{TCPDev}->close(SSL_no_shutdown => 1);
    } else {
      $hash->{TCPDev}->close();
    }
    delete($hash->{TCPDev});
    delete($hash->{".WSBUF"});
    delete($hash->{WEBSOCKET});

  } elsif($hash->{USBDev}) {
    if($isFork) { # SerialPort close resets the serial parameters.
      POSIX::close($hash->{USBDev}{FD});
    } else {
      $hash->{USBDev}->close() ;
    }
    delete($hash->{USBDev});

  } elsif($hash->{DIODev}) {
    close($hash->{DIODev});
    delete($hash->{DIODev});

  } elsif($hash->{IODev}) {
    eval {
      CallFn($hash->{IODev}{NAME}, "IOCloseFn", $hash);
    }; # ignore closing errors (e.g. caused by fork)
    delete($hash->{IODevParameters});
    delete($hash->{IODevPort});
    delete($hash->{IODevRxBuffer});
    delete($hash->{IODev});
    
  }
  ($dev, undef) = split("@", $dev); # Remove the baudrate
  delete($selectlist{"$name.$dev"});
  delete($readyfnlist{"$name.$dev"});
  delete($hash->{FD});
  delete($hash->{EXCEPT_FD});
  delete($hash->{PARTIAL});
  delete($hash->{NEXT_OPEN});
}

sub
DevIo_IsOpen($)
{
  my ($hash) = @_;
  return ($hash->{TCPDev} || 
          $hash->{USBDev} || 
          $hash->{DIODev} || 
          $hash->{IODevPort});
}


# Close the device, schedule the reopen via ReadyFn, trigger DISCONNECTED
sub
DevIo_Disconnected($)
{
  my $hash = shift;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $baudrate;
  ($dev, $baudrate) = split("@", $dev);

  return if(!defined($hash->{FD}));                 # Already deleted or RFR

  my $l = $hash->{devioLoglevel}; # Forum #61970
  Log3 $name, ($l ? $l:1), "$dev disconnected, waiting to reappear ($name)";
  DevIo_CloseDev($hash);
  $readyfnlist{"$name.$dev"} = $hash;               # Start polling
  DevIo_setStates($hash, "disconnected");
  $hash->{DevIoJustClosed} = 1;                     # Avoid a direct reopen

  DoTrigger($name, "DISCONNECTED");
}

1;
