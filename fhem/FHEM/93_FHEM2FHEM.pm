##############################################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use HttpUtils;


sub FHEM2FHEM_Read($);
sub FHEM2FHEM_Ready($);
sub FHEM2FHEM_OpenDev($$);
sub FHEM2FHEM_CloseDev($);
sub FHEM2FHEM_Disconnected($);
sub FHEM2FHEM_Define($$);
sub FHEM2FHEM_Undef($$);

sub
FHEM2FHEM_Initialize($)
{
  my ($hash) = @_;

# Provider
  $hash->{ReadFn}  = "FHEM2FHEM_Read";
  $hash->{WriteFn} = "FHEM2FHEM_Write";
  $hash->{ReadyFn} = "FHEM2FHEM_Ready";
  $hash->{SetFn}   = "FHEM2FHEM_Set";
  $hash->{AttrFn}  = "FHEM2FHEM_Attr";
  $hash->{noRawInform} = 1;

# Normal devices
  $hash->{DefFn}   = "FHEM2FHEM_Define";
  $hash->{UndefFn} = "FHEM2FHEM_Undef";
  no warnings 'qw';
  my @attrList = qw(
    addStateEvent:1,0
    disable:0,1
    disabledForIntervals
    dummy:1,0
    eventOnly:1,0
    excludeEvents
    loopThreshold
    keepaliveInterval
    reportConnected:1,0
    setState
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList);
}

#####################################
sub
FHEM2FHEM_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a < 4 || @a > 5 || !($a[3] =~ m/^(LOG|RAW):(.*)$/)) {
    my $msg = "wrong syntax: define <name> FHEM2FHEM host[:port][:SSL] ".
                        "[LOG:regexp|RAW:device] {portpasswort}";
    Log3 $hash, 2, $msg;
    return $msg;
  }

  $hash->{informType} = $1;
  if($1 eq "LOG") {
    $hash->{regexp} = $2;

  } else {
    my $rdev = $2;
    my $iodev = $defs{$rdev};
    return "Undefined local device $rdev" if(!$iodev);
    $hash->{rawDevice} = $rdev;

    my $iomod = $modules{$iodev->{TYPE}};
    $hash->{Clients} = $iodev->{Clients} ? $iodev->{Clients} :$iomod->{Clients};
    $hash->{MatchList} = $iomod->{MatchList} if($iomod->{MatchList});

  }

  my $dev = $a[2];
  if($dev =~ m/^(.*):SSL$/) {
    $dev = $1;
    $hash->{SSL} = 1;
  }
  if($dev !~ m/^.+:[0-9]+$/) {       # host:port
    $dev = "$dev:7072";
    $hash->{Host} = $dev;
  }

  if($hash->{OLDDEF} && $hash->{OLDDEF} =~ m/^([^ \t]+)/) {; # Forum #30242
    delete($readyfnlist{"$hash->{NAME}.$1"});
  }

  $hash->{Host} = $dev;
  $hash->{portpassword} = $a[4] if(@a == 5);

  FHEM2FHEM_CloseDev($hash);    # Modify...
  return FHEM2FHEM_OpenDev($hash, 0);
}

#####################################
sub
FHEM2FHEM_Undef($$)
{
  my ($hash, $arg) = @_;
  FHEM2FHEM_CloseDev($hash); 
  return undef;
}

sub
FHEM2FHEM_Write($$)
{
  my ($hash,$fn,$msg) = @_;
  my $dev = $hash->{Host};

  if(!$hash->{TCPDev2}) {
    my $conn;
    if($hash->{SSL}) {
      $conn = IO::Socket::SSL->new(PeerAddr => $dev);
    } else {
      $conn = IO::Socket::INET->new(PeerAddr => $dev);
    }
    return if(!$conn);  # Hopefuly it is reported elsewhere
    $hash->{TCPDev2} = $conn;
    F2F_sw($hash->{TCPDev2}, $hash->{portpassword} . "\n")
        if($hash->{portpassword});
  }

  my $rdev = $hash->{rawDevice};
  F2F_sw($hash->{TCPDev2}, "iowrite $rdev $fn $msg\n");
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
FHEM2FHEM_Read($)
{
  my ($hash) = @_;
  my $buf;
  my $res = sysread($hash->{TCPDev}, $buf, 256);

  if($hash->{SSL} && !defined($res) && $! == EWOULDBLOCK) {
    my $es = $hash->{TCPDev}->errstr;
    $hash->{wantWrite} = 1 if($es == &IO::Socket::SSL::SSL_WANT_WRITE);
    $hash->{wantRead}  = 1 if($es == &IO::Socket::SSL::SSL_WANT_READ);
    return "";
  }

  if(!defined($buf) || length($buf) == 0) {
    FHEM2FHEM_Disconnected($hash);
    return;
  }

  $buf = Encode::decode('UTF-8', $buf) if($unicodeEncoding);

  my $name = $hash->{NAME};
  return if(IsDisabled($name));
  my $excl = AttrVal($name, "excludeEvents", undef);
  my $threshold = AttrVal($name, "loopThreshold", 0); # 122300

  my $data = $hash->{PARTIAL};
  #Log3 $hash, 5, "FHEM2FHEM/RAW: $data/$buf";
  $data .= $buf;

  if($hash->{".waitingForSet"}  && $data =~ m/\0/) {
    if($data !~ m/^(.*)\0(.*)\0(.*)$/s) {
      $hash->{PARTIAL} = $data;
      return;
    }

    my $resp = $2;
    if($hash->{".lcmd"}) {
      Log3 $name, 4, "Remote command response:$resp";
      asyncOutput($hash->{".lcmd"}, $resp);
      delete($hash->{".lcmd"});
    } else {
      Log3 $name, 3, "Remote command response:$resp";
    }
    $hash->{cmdResponse} = $resp;
    delete($hash->{".waitingForSet"});
    delete($hash->{".lcmd"});

    $data = $1.$3; # Continue with the rest
  }

  while($data =~ m/\n/) {
    my $rmsg;
    ($rmsg,$data) = split("\n", $data, 2);
    $rmsg =~ s/\r//;

    if($hash->{informType} eq "LOG") {
      my ($type, $rname, $msg) = split(" ", $rmsg, 3);
      next if(!defined($msg)); # Bogus data
      my $re = $hash->{regexp};
      next if($re && !($rname =~ m/^$re$/ || "$rname:$msg" =~ m/^$re$/));
      next if($excl && ($rname =~ m/^$excl$/ || "$rname:$msg" =~ m/^$excl$/));
      Log3 $name, 4, "$rname: $rmsg";

      if(!$defs{$rname}) {
        $defs{$rname}{NAME}  = $rname;
        $defs{$rname}{TYPE}  = $type;
        $defs{$rname}{STATE} = $msg;
        $defs{$rname}{FAKEDEVICE} = 1; # Avoid set/attr/delete/etc in notify
        $defs{$rname}{TEMPORARY} = 1;  # Do not save it
        DoTrigger($rname, $msg);
        delete($defs{$rname});
        delete($attr{$rname}); # Forum #73490

      } else {
        if(AttrVal($name,"eventOnly",0)) {
          DoTrigger($rname, $msg);
        } else {
          my $reading = "state";
          if($msg =~ m/^([^:]*): (.*)$/) {
            $reading = $1; $msg = $2;
          }
          my $age = ($threshold ? ReadingsAge($rname,$reading,undef) : 99999);
          if(defined($age) && $age < $threshold) {
            Log3 $name, 4, "$name: ignoring $rname $reading $msg, ".
                           "threshold $threshold, age:$age";
            next;
          }
          if($reading eq "state" && AttrVal($name, "setState", 0)) {
            AnalyzeCommand($hash, "set $rname $msg");
          } else {
            readingsSingleUpdate($defs{$rname}, $reading, $msg, 1);
          }
        }

      }

    } else {    # RAW
      my ($type, $rname, $msg) = split(" ", $rmsg, 3);
      my $rdev = $hash->{rawDevice};
      next if(!$rname || $rname ne $rdev);
      my $dbg_rmsg = $rmsg;
      $dbg_rmsg =~ s/([^ -~])/"(".ord($1).")"/ge;
      Log3 $name, 4, "$name: RAW RCVD: $dbg_rmsg";
      Dispatch($defs{$rdev}, $msg, undef);

    }
  }
  $hash->{PARTIAL} = $data;
}


#####################################
sub
FHEM2FHEM_Ready($)
{
  my ($hash) = @_;

  return FHEM2FHEM_OpenDev($hash, 1);
}

########################
sub
FHEM2FHEM_CloseDev($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $dev = $hash->{Host};

  return if(!$dev);
  
  $hash->{TCPDev}->close() if($hash->{TCPDev});
  $hash->{TCPDev2}->close() if($hash->{TCPDev2});
  delete($hash->{NEXT_OPEN});
  delete($hash->{TCPDev});
  delete($hash->{TCPDev2});
  delete($selectlist{"$name.$dev"});
  delete($readyfnlist{"$name.$dev"});
  delete($hash->{FD});
}

########################
sub
FHEM2FHEM_OpenDev($$)
{
  my ($hash, $reopen) = @_;
  my $dev = $hash->{Host};
  my $name = $hash->{NAME};

  $hash->{PARTIAL} = "";
  Log3 $name, 3, "FHEM2FHEM opening $name at $dev"
        if(!$reopen);

  return if($hash->{NEXT_OPEN} && time() <= $hash->{NEXT_OPEN});
  return if(IsDisabled($name));

  my $doTailWork = sub($$$) {
    my ($h, $err, undef) = @_;

    if($err) {
      Log3($name, 3, "Can't connect to $dev: $!") if(!$reopen);
      $readyfnlist{"$name.$dev"} = $hash;
      $hash->{STATE} = "disconnected";
      $hash->{NEXT_OPEN} = time()+60;
      return;
    }
    my $conn = $h->{conn};
    delete($hash->{NEXT_OPEN});
    $conn->setsockopt(SOL_SOCKET, SO_KEEPALIVE, 1);
    $hash->{TCPDev} = $conn;
    $hash->{FD} = $conn->fileno();
    delete($readyfnlist{"$name.$dev"});
    $selectlist{"$name.$dev"} = $hash;

    if($reopen) {
      Log3 $name, 1, "FHEM2FHEM $dev reappeared ($name)";
    } else {
      Log3 $name, 3, "FHEM2FHEM device opened ($name)";
    }

    $hash->{STATE}= "connected";
    DoTrigger($name, "CONNECTED") if($reopen);
    F2F_sw($hash->{TCPDev}, $hash->{portpassword} . "\n")
          if($hash->{portpassword});
    my $type = AttrVal($hash->{NAME},"addStateEvent",0) ? "onWithState" : "on";
    my $msg = $hash->{informType} eq "LOG" ? 
                  "inform $type $hash->{regexp}" : "inform raw";
    F2F_sw($hash->{TCPDev}, $msg . "\n");
    F2F_sw($hash->{TCPDev}, "trigger global CONNECTED $name\n")
      if(AttrVal($name, "reportConnected", 0));

    my $ki = AttrVal($hash->{NAME}, "keepaliveInterval", 0);
    InternalTimer(gettimeofday()+$ki, "FHEM2FHEM_keepalive", $hash) if($ki);
  };

  return HttpUtils_Connect({     # Nonblocking
    url     => $hash->{SSL} ? "https://$dev/" : "http://$dev/",
    NAME    => $name,
    noConn2 => 1,
    callback=> $doTailWork
  });
}

sub
FHEM2FHEM_Disconnected($)
{
  my $hash = shift;
  my $dev = $hash->{Host};
  my $name = $hash->{NAME};

  return if(!defined($hash->{FD}));                 # Already deleted
  Log3 $name, 1, "$dev disconnected, waiting to reappear";
  FHEM2FHEM_CloseDev($hash);
  $readyfnlist{"$name.$dev"} = $hash;               # Start polling
  $hash->{STATE} = "disconnected";

  return if(IsDisabled($name)); #Forum #39386

  # Without the following sleep the open of the device causes a SIGSEGV,
  # and following opens block infinitely. Only a reboot helps.
  sleep(5);

  DoTrigger($name, "DISCONNECTED");
}


sub
F2F_sw($$)
{
  my ($io, $buf) = @_;
  $buf = Encode::encode('UTF-8', $buf) if($unicodeEncoding);
  return syswrite($io, $buf);
}

sub
FHEM2FHEM_Set($@)
{
  my ($hash, @a) = @_;
  my %sets = ( reopen=>"noArg", cmd=>"textField" );

  return "set needs at least one parameter" if(@a < 2);
  return "Unknown argument $a[1], choose one of ".
        join(" ", map {"$_:$sets{$_}"} sort keys %sets) if(!$sets{$a[1]});
  return "$a[1] needs at least one parameter"
  	if(@a < 3 && $sets{$a[1]} ne "noArg");
  
  if($a[1] eq "reopen") {
    FHEM2FHEM_CloseDev($hash);
    FHEM2FHEM_OpenDev($hash, 0);
  }

  if($a[1] eq "cmd") {
    return "Not connected" if(!$hash->{TCPDev});
    my $cmd = join(" ",@a[2..$#a]);
    $cmd = '{my $r=fhem("'.$cmd.'");; defined($r) ? "\\0$r\\0" : $r}'."\n";
    F2F_sw($hash->{TCPDev}, $cmd);
    $hash->{".lcmd"} = $hash->{CL};
    $hash->{".waitingForSet"} = 1;
  }
  return undef;
}

sub
FHEM2FHEM_Attr(@)
{
  my ($type, $devName, $attrName, @param) = @_;
  my $hash = $defs{$devName};

  if($attrName eq "addStateEvent") {
    $attr{$devName}{$attrName} = 1;
    FHEM2FHEM_CloseDev($hash);
    FHEM2FHEM_OpenDev($hash, 1);
  }

  if($attrName eq "keepaliveInterval") {
    return "Numeric argument expected" if($param[0] !~ m/^\d+$/);
    InternalTimer(gettimeofday()+$param[0], "FHEM2FHEM_keepalive", $hash)
      if($param[0] && $hash->{TCPDev});
  }

  return undef;
}

sub
FHEM2FHEM_keepalive($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $ki = AttrVal($name, "keepaliveInterval", 0);
  return if(!$ki || !$hash->{TCPDev});

  HttpUtils_Connect({
    url => "http://$hash->{Host}/", noConn2 => 1,
    callback=> sub {
      my ($h, $err, undef) = @_;
      if($err) {
        Log3 $name, 4, "$name keepalive: $err";
        return FHEM2FHEM_Disconnected($hash);
      }
      $h->{conn}->close();
      InternalTimer(gettimeofday()+$ki, "FHEM2FHEM_keepalive", $hash);
    }
  });
}

1;

=pod
=item helper
=item summary    connect two FHEM instances
=item summary_DE verbindet zwei FHEM Installationen
=begin html

<a id="FHEM2FHEM"></a>
<h3>FHEM2FHEM</h3>
<ul>
  FHEM2FHEM is a helper module to connect separate FHEM installations.
  <br><br>
  <a id="FHEM2FHEM-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FHEM2FHEM &lt;host&gt;[:&lt;portnr&gt;][:SSL]
    [LOG:regexp|RAW:devicename] {portpassword}
    </code>
  <br>
  <br>
  Connect to the <i>remote</i> FHEM on &lt;host&gt;. &lt;portnr&gt; is a telnet
  port on the remote FHEM, defaults to 7072. The optional :SSL suffix is
  needed, if the remote FHEM configured SSL for this telnet port. In this case
  the IO::Socket::SSL perl module must be installed for the local host too.<br>
  <br>
  Notes:
  <ul>
    <li>if the remote FHEM is on a separate host, the telnet port on the remote
      FHEM must be specified with the global option.</li>
    <li>as of FHEM 5.9 the telnet instance is not configured in default fhem.cfg, so
    it has to be defined, e.g. as
    <ul><code>
    define telnetPort telnet 7072 global
    </code></ul>
    </li>
  </ul>
  <br>

  The next parameter specifies the connection
  type:
  <ul>
  <li>LOG<br>
    Using this type you will receive all events generated by the remote FHEM,
    just like when using the <a href="#inform">inform on</a> command, and you
    can use these events just like any local event for <a
    href="#FileLog">FileLog </a> or <a href="#notify">notify</a>.
    The regexp will prefilter the events distributed locally, for the syntax
    see the notify definition.<br>
    Drawbacks: the remote devices wont be created locally, so list wont
    show them and it is not possible to manipulate them from the local
    FHEM. It is possible to create a device with the same name on both FHEM
    instances, but if both of them receive the same event (e.g. because both
    of them have a CUL attached), then all associated FileLogs/notifys will be
    triggered twice.<br>
    If the remote device is created with the same name locally (e.g. as dummy),
    then the local readings are also updated.
    </li>
  <li>RAW<br>
    By using this type the local FHEM will receive raw events from the remote
    FHEM device <i>devicename</i>, just like if it would be attached to the
    local FHEM.
    Drawback: only devices using the Dispatch function (CUL, FHZ, CM11,
    SISPM, RFXCOM, TCM, TRX, TUL) generate raw messages, and you must create a
    FHEM2FHEM instance for each remote device.<br>
    <i>devicename</i> must exist on the local
    FHEM server too with the same name and same type as the remote device, but
    with the device-node "none", so it is only a dummy device. 
    All necessary attributes (e.g. <a href="#rfmode">rfmode</a> if the remote
    CUL is in HomeMatic mode) must also be set for the local device.
    Do not reuse a real local device, else duplicate filtering (see dupTimeout)
    won't work correctly.
    </li>
  </ul>
  The last parameter specifies an optional portpassword, if the remote server
  activated <a href="#portpassword">portpassword</a>.
  <br>
  Examples:
  <ul>
    <code>define ds1 FHEM2FHEM 192.168.178.22:7072 LOG:.*</code><br>
    <br>
    <code>define RpiCUL CUL none 0000</code><br>
    <code>define ds2 FHEM2FHEM 192.168.178.22:7072 RAW:RpiCUL</code><br>
    and on the RPi (192.168.178.22):<br>
    <code>rename CUL_0 RpiCUL</code><br>
  </ul>
  </ul>
  <br>

  <a id="FHEM2FHEM-set"></a>
  <b>Set </b>
  <ul>
    <li>reopen<br>
	Reopens the connection to the device and reinitializes it.</li><br>
    <li>cmd &lt;FHEM-command&gt;<br>
        issues the FHEM-command on the remote machine. Note: a possible answer
        can be seen if it is issued in a telnet session or in the FHEMWEB
        "command execution window", but not when issued in the other FHEMWEB
        input lines. </li><br>

  </ul>

  <a id="FHEM2FHEM-get"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a id="FHEM2FHEM-attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#dummy">dummy</a></li>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
    <li><a id="FHEM2FHEM-eventOnly">eventOnly</a><br>
      if set, generate only events, do not set corresponding readings.
      This is a compatibility feature, available only for LOG-Mode.
      </li>
    <li><a id="FHEM2FHEM-attr-addStateEvent">addStateEvent</a><br>
      if set, state events are transmitted correctly. Notes: this is relevant
      only with LOG mode, setting it will generate an additional "reappeared"
      Log entry, and the remote FHEM must support inform onWithState (i.e. must
      be up to date).
      </li>
    <li><a id="FHEM2FHEM-attr-excludeEvents">excludeEvents &lt;regexp&gt;</a>
      do not publish events matching &lt;regexp&gt;. Note: ^ and $ are
      automatically added to the regexp, like in notify, FileLog, etc.
      </li>
     <li><a id="FHEM2FHEM-attr-keepaliveInterval">keepaliveInterval &lt;sec&gt
         </a><br>
       issues an empty command regularly in order to detect a stale TCP
       connection faster than the OS.</li>
     <li><a id="FHEM2FHEM-attr-loopThreshold">loopThreshold</a><br>
       helps avoiding endless loops. If set, the last update of a given
       reading must be older than the current value in seconds. Take care if
       event-on-* attributes are also set.
       </li>
    <li><a id="FHEM2FHEM-attr-setState">setState</a>
      if set to 1, and there is a local device with the same name, then remote
      set commands will be executed for the local device.
      </li>
     <li><a id="FHEM2FHEM-attr-reportConnected">reportConnected</a>
       if set (to 1), a  "global CONNECTED &lt;name&gt;" Event will be generated
       after connection established on the telnet server. This might be used to
       resend changed values.
       </li> 
  </ul>

</ul>

=end html

=begin html_DE

<a id="FHEM2FHEM"></a>
<h3>FHEM2FHEM</h3>
<ul>
   FHEM2FHEM ist ein Hilfsmodul, um mehrere FHEM-Installationen zu verbinden.
   <br><br>
   <a id="FHEM2FHEM-define"></a>
   <b>Define</b>
   <ul>
    <code>define &lt;name&gt; FHEM2FHEM &lt;host&gt;[:&lt;portnr&gt;][:SSL] [LOG:regexp|RAW:devicename] {portpassword}
    </code>
   <br>
   <br>
    Zum <i>remote (entfernten)</i> FHEM auf Rechner &lt;host&gt; verbinden.
    &lt;portnr&gt; ist der telnetPort des remote FHEM, Standardport ist 7072.
    Der Zusatz :SSL wird ben&ouml;tigt, wenn das remote FHEM
    SSL-Verschl&uuml;sselung voraussetzt.  Auch auf dem lokalen Host muss dann
    das Perl-Modul IO::Socket::SSL installiert sein.<br>

  <br>
  Achtung:
  <ul>
    <li>
     Wenn das remote FHEM auf einem eigenen Host l&auml;uft, muss
     "telnetPort" des remote FHEM mit der global Option definiert sein.
      </li>
    <li>ab FHEM Version 5.9 wird in der ausgelieferten Initialversion der fhem.cfg
      keine telnet Instanz vorkonfiguriert, man muss sie z.Bsp.
      folgenderma&szlig;en definieren:
      <ul><code>
      define telnetPort telnet 7072 global
      </code></ul>
      </li>
  </ul>
  <br>


   Der n&auml;chste Parameter spezifiziert den Verbindungs-Typ:
   <ul>
   <li>LOG<br>
    Bei Verwendung dieses Verbindungstyps werden alle Ereignisse (Events) der
    remote FHEM-Installation empfangen.  Die Ereignisse sehen aus wie die, die
    nach <a href="#inform">inform on</a> Befehl erzeugt werden. Sie k&ouml;nnen
    wie lokale Ereignisse durch <a href="#FileLog">FileLog </a> oder <a
    href="#notify">notify</a> genutzt werden und mit einem regul&auml;ren
    Ausdruck gefiltert werden. Die Syntax daf&uuml;r ist unter der
    notify-Definition beschrieben.<br>

    Einschr&auml;nkungen: die Ger&auml;te der remote Installation werden nicht
    lokal angelegt und k&ouml;nnen weder mit list angezeigt noch lokal
    angesprochen werden.  Auf beiden FHEM-Installationen k&ouml;nnen
    Ger&auml;te gleichen Namens angelegt werden, aber wenn beide dasselbe
    Ereignis empfangen (z.B. wenn an beiden Installationen CULs angeschlossen
    sind), werden alle FileLogs und notifys doppelt ausgel&ouml;st.<br>
    Falls man lokal Ger&auml;te mit dem gleichen Namen (z.Bsp. als dummy)
    angelegt hat, dann werden die Readings von dem lokalen Ger&auml;t
    aktualisiert.
    </li>

   <li>RAW<br>
    Bei diesem Verbindungstyp werden unaufbereitete Ereignisse (raw messages)
    des remote FHEM-Ger&auml;ts <i>devicename</i> genau so empfangen, als
    w&auml;re das Ger&auml;t lokal verbunden.<br>

    Einschr&auml;nkungen: nur Ger&auml;te, welche die "Dispatch-Funktion"
    unterst&uuml;tzen (CUL, FHZ, CM11, SISPM, RFXCOM, TCM, TRX, TUL) erzeugen
    raw messages, und f&uuml;r jedes entfernte Ger&auml;t muss ein eigenes
    FHEM2FHEM Objekt erzeugt werden.<br>

    <i>devicename</i> muss mit demselben Namen und Typ wie das Remote Devive
    angelegt sein, aber als Dummy, d.h. als device-node "none".
    Zus&auml;tzlich m&uuml;ssen alle notwendigen Attribute lokal gesetzt sein
    (z.B. <a href="#rfmode">rfmode</a>, wenn die remote CUL im HomeMatic-Modus
    l&auml;uft).  Die Verwendung bereits bestehender lokaler Ger&auml;te ist zu
    vermeiden, weil sonst die Duplikatsfilterung nicht richtig funktioniert
    (siehe dupTimeout).  </li>

   </ul>
   Der letzte Parameter enth&auml;lt das Passwort des Remote-Servers, wenn dort
   eines aktiviert ist <a href="#portpassword">portpassword</a>.

   <br>
   Beispiele:
   <ul>
     <code>define ds1 FHEM2FHEM 192.168.178.22:7072 LOG:.*</code><br>
     <br>
     <code>define RpiCUL CUL none 0000</code><br>
     <code>define ds2 FHEM2FHEM 192.168.178.22:7072 RAW:RpiCUL</code><br> und auf dem RPi (192.168.178.22):<br>
     <code>rename CUL_0 RpiCUL</code><br>
   </ul>
   </ul>
   <br>

   <a id="FHEM2FHEM-set"></a>
   <b>Set </b>
   <ul>
     <li>reopen<br>
 	&Ouml;ffnet die Verbindung erneut.</li>
    <li>cmd &lt;FHEM-command&gt;<br>
        f&uuml;rt FHEM-command auf dem entfernten Rechner aus. Achtung: eine
        Fehlermeldung ist nur dann sichtbar, falls der Befehl in einer
        Telnet-Sitzung oder in der mehrzeiligen FHEMWEB Befehlsdialog
        eingegeben wurde.</li><br>
   </ul>

   <a id="FHEM2FHEM-get"></a>
   <b>Get</b> <ul>N/A</ul><br>

   <a id="FHEM2FHEM-attr"></a>
   <b>Attribute</b>
   <ul>
     <li><a href="#dummy">dummy</a></li>
     <li><a href="#disable">disable</a></li>
     <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
     <li><a id="FHEM2FHEM-attr-eventOnly">eventOnly</a><br>
       falls gesetzt, werden nur die Events generiert, und es wird kein
       Reading aktualisiert. Ist nur im LOG-Mode aktiv.
       </li>
     <li><a id="FHEM2FHEM-attr-addStateEvent">addStateEvent</a><br>
       falls gesetzt, werden state Events als solche uebertragen. Zu beachten:
       das Attribut ist nur f&uuml;r LOG-Mode relevant, beim Setzen wird eine
       zus&auml;tzliche reopened Logzeile generiert, und die andere Seite muss
       aktuell sein.
       </li>
     <li><a id="FHEM2FHEM-attr-excludeEvents">excludeEvents &lt;regexp&gt;</a>
       die auf das &lt;regexp&gt; zutreffende Events werden nicht
       bereitgestellt. Achtung: ^ und $ werden automatisch hinzugefuuml;gt, wie
       bei notify, FileLog, usw.
       </li>
     <li><a id="FHEM2FHEM-attr-keepaliveInterval">keepaliveInterval &lt;sec&gt
         </a><br>
       setzt regelmaessig einen leeren Befehl ab, um einen Verbindungsabbruch
       frueher als das OS feststellen zu koennen.</li>
     <li><a id="FHEM2FHEM-attr-loopThreshold">loopThreshold</a><br>
       hilft Endlosschleifen zu vermeiden. Falls gesetzt, muss die letzte
       &Auml;nderung des gleichen Readings mehr als der Wert in Sekunden alt
       sein. Achtung bei gesetzten event-on-* Attributen.</li>
     <li><a id="FHEM2FHEM-attr-setState">setState</a>
       falls gesetzt (auf 1), und ein lokales Ger&auml;t mit dem gleichen Namen
       existiert, dann werden set Befehle vom entfernten Ger&auml;t als Solches
       &uuml;bertragen.
       </li>
     <li><a id="FHEM2FHEM-attr-reportConnected">reportConnected</a>
       falls gesetzt (auf 1), dann wird auf dem Telnet-Server nach dem
       Verbinden das "global CONNECTED &lt;name&gt;" Event erzeugt. Das
       erm&ouml;glicht z.Bsp. das erneute Senden ge&auml;nderter Zust&auml;nde.
       </li> 
   </ul>
</ul>

=end html_DE

=cut
