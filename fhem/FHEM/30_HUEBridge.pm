
# $Id$

# "Hue Personal Wireless Lighting" is a trademark owned by Koninklijke Philips Electronics N.V.,
# see www.meethue.com for more information.
# I am in no way affiliated with the Philips organization.

package main;

use strict;
use warnings;

use FHEM::Meta;

#use POSIX;
use Time::HiRes qw(gettimeofday);
use JSON;
use Data::Dumper;

use HttpUtils;

use IO::Socket::INET;

use vars qw(%defs);

sub
HUEBridge_loadHUEDevice()
{
  if( !$modules{HUEDevice}{LOADED} ) {
    my $ret = CommandReload( undef, "31_HUEDevice" );
    Log3 undef, 1, $ret if( $ret );
  }
}

sub
HUEBridge_Initialize($)
{
  my ($hash) = @_;

  # Provider
  $hash->{ReadFn}  = "HUEBridge_Read";
  $hash->{WriteFn} = "HUEBridge_Write";
  $hash->{Clients} = ":HUEDevice:";

  #Consumer
  $hash->{DefFn}    = "HUEBridge_Define";
  $hash->{RenameFn} = "HUEBridge_Rename";
  $hash->{NotifyFn} = "HUEBridge_Notify";
  $hash->{SetFn}    = "HUEBridge_Set";
  $hash->{GetFn}    = "HUEBridge_Get";
  $hash->{AttrFn}   = "HUEBridge_Attr";
  $hash->{UndefFn}  = "HUEBridge_Undefine";
  $hash->{AttrList} = "key disable:1 disabledForIntervals createEventTimestampReading:1,0 eventstreamTimeout createGroupReadings:1,0 httpUtils:1,0 forceAutocreate:1,0 ignoreUnknown:1,0 noshutdown:1,0 pollDevices:1,2,0 queryAfterEvent:1,0 queryAfterSet:1,0 $readingFnAttributes";

  #$hash->{isDiscoverable} = { ssdp => {'hue-bridgeid' => '/.*/'}, upnp => {} };

  HUEBridge_loadHUEDevice();

  # reopen connections if bridge module is reloaded.
  # without this already running code might not be overwritten as it is not garbage collected due to strong references
  if( $init_done ) {
    foreach my $chash ( values %defs ) {
      next if( !$chash );
      next if( $chash->{TYPE} ne 'HUEBridge' );
      my $name = $chash->{NAME};
      if( $chash->{has_v2_api} ) {

        CommandSet( undef, "$name reconnect" );
      }
    }
  }

  return FHEM::Meta::InitMod( __FILE__, $hash );
}

sub
HUEBridge_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $buf;
  my $len = sysread($hash->{CD}, $buf, 10240);
  my $peerhost = $hash->{CD}->peerhost;
  my $peerport = $hash->{CD}->peerport;

  my $close = 0;
  if( !defined($len) || !$len ) {
    $close = 1;

  } elsif( $hash->{websocket} ) {
    $hash->{buf} .= $buf;

    if( defined(my $create = AttrVal($name,'createEventTimestampReading',undef )) ) {
      readingsSingleUpdate($hash, 'event', 'timestamp', $create ) if( defined($create) );
    }

    do {
      my $fin = (ord(substr($hash->{buf},0,1)) & 0x80)?1:0;
      my $op = (ord(substr($hash->{buf},0,1)) & 0x0F);
      my $mask = (ord(substr($hash->{buf},1,1)) & 0x80)?1:0;
      my $len = (ord(substr($hash->{buf},1,1)) & 0x7F);
      my $i = 2;
      if( $len == 126 ) {
        $len = unpack( 'n', substr($hash->{buf},$i,2) );
        $i += 2;
      } elsif( $len == 127 ) {
        $len = unpack( 'q', substr($hash->{buf},$i,8) );
        $i += 8;
      }
      if( $mask ) {
        $mask = substr($hash->{buf},$i,4);
        $i += 4;
      }
      #FIXME: hande !$fin
      return if( $len > length($hash->{buf})-$i );

      my $data = substr($hash->{buf}, $i, $len);
      $hash->{buf} = substr($hash->{buf},$i+$len);
#Log 1, ">>>$data<<<";

      if( $data eq '?' ) {
        #ignore keepalive
        #RemoveInternalTimer($hash, 'HUEBridge_openWebsocket' );
        #InternalTimer(gettimeofday()+300, 'HUEBridge_openWebsocket', $hash, 0);

      } elsif( $op == 0x01 ) {
        my $obj = eval { JSON->new->utf8(0)->decode($data) };

        if( !$obj ) {
          Log3 $name, 2, "$name: websocket: unhandled text $data";
          return;
        }
        Log3 $name, 5, "$name: websocket data: ". Dumper $obj;

        if( $obj->{t} ne 'event' ) {
          Log3 $name, 2, "$name: websocket: unhandled message type: $data";
          return;
        }

        $obj->{source} = 'event';

        my $code;
        my $id = $obj->{id};
           $id = $obj->{gid} if( $obj->{gid} && $obj->{r} eq 'scenes' );
        $code = $name ."-". $id if( $obj->{r} eq 'lights' );
        $code = $name ."-S". $id if( $obj->{r} eq 'sensors' );
        $code = $name ."-G". $id if( $obj->{r} eq 'groups' );
        $code = $name ."-G". $obj->{gid} if( $obj->{gid} && $obj->{r} eq 'scenes' );
        if( !$code ) {
          Log3 $name, 5, "$name: ignoring event: $data";
          return;
        }

        if( $id == 0xfff0
            && ($obj->{r} eq 'groups' || ($obj->{gid} && $obj->{r} eq 'scenes') ) ) {
          $code = $name .'-G0';
          Log3 $name, 5, "$name: websocket: assuming group 0 for id $id in event";

        } elsif( $id >= 0xff00
                 && ($obj->{r} eq 'groups' || ($obj->{gid} && $obj->{r} eq 'scenes') ) )  {
          Log3 $name, 4, "$name: websocket: ignoring event for id $id";
          $hash->{helper}{ignored}{$code} = 1;
          return;
        }

        if( $obj->{e} eq 'changed' ) {
          if( my $chash = $modules{HUEDevice}{defptr}{$code} ) {
            HUEDevice_Parse($chash, $obj);
            HUEBridge_updateGroups($hash, $chash->{ID}) if( !$chash->{helper}{devtype} );

            delete $hash->{helper}{ignored}{$code};

          } elsif( HUEDevice_moveToBridge( $obj->{uniqueid}, $name, $obj->{id} ) ) {
            if( my $chash = $modules{HUEDevice}{defptr}{$code} ) {
              HUEDevice_Parse($chash, $obj);

              delete $hash->{helper}{ignored}{$code};
            }

          } elsif( !$hash->{helper}{ignored}{$code} && !AttrVal($name, "ignoreUnknown", undef) ) {
            Log3 $name, 2, "$name: websocket: event for unknown device received: $code";
          }

        } elsif( $obj->{e} eq 'scene-called' ) {
          if( my $chash = $modules{HUEDevice}{defptr}{$code} ) {
            #HUEDevice_Parse($chash, $obj);
            HUEDevice_Parse($chash, { state => { scene => $obj->{scid} } } );
            #readingsSingleUpdate($hash, 'scene',  $obj->{scid}, 1 );
          }

        } elsif( $obj->{e} eq 'added' ) {
          Log3 $name, 5, "$name: websocket add: $data";
          if( !HUEDevice_moveToBridge( $obj->{uniqueid}, $name, $obj->{id} ) ) {
            HUEBridge_Autocreate($hash);
          }

          if( my $chash = $modules{HUEDevice}{defptr}{$code} ) {
            if( $obj->{r} eq 'lights' ) {
              $obj = $obj->{light};
            } elsif( $obj->{r} eq 'sensors' ) {
              $obj = $obj->{sensor};
            } elsif( $obj->{r} eq 'groups' ) {
              $obj = $obj->{group};
            }
            #maybe this instead?
            #given( $obj->{r} ){
            #   when('lights'){ $obj = $obj->{light}; }
            #  when('sensors'){ $obj = $obj->{sensor}; }
            #   when('groups'){ $obj = $obj->{group}; }
            #}

            HUEDevice_Parse($chash, $obj);
          }

        } elsif( $obj->{e} eq 'deleted' ) {
          Log3 $name, 5, "$name: todo: handle websocket delete $data";
          # do what ?

        } else {
          Log3 $name, 2, "$name: websocket: unhandled event type: $data";
        }

      } else {
        Log3 $name, 2, "$name: websocket: unhandled opcode: $data";

      }
    } while( $hash->{buf} && !$close );

  } elsif( $buf =~ m'^HTTP/1.1 101 Switching Protocols'i )  {
    $hash->{websocket} = 1;
    #my $buf = plex_msg2hash($buf, 1);
#Log 1, $buf;

    Log3 $name, 3, "$name: websocket: Switching Protocols ok";

  } else {
#Log 1, $buf;
    $close = 1;
    Log3 $name, 2, "$name: websocket: Switching Protocols failed";
  }

  if( $close ) {
    HUEBridge_closeWebsocket($hash);

    Log3 $name, 2, "$name: websocket closed";
  }
}

sub
HUEBridge_Write($@)
{
  my ($hash,$chash,$name,$id,$obj)= @_;

  return HUEBridge_Call($hash, $chash, 'groups/' . $1, $obj)  if( $id =~ m/^G(\d.*)/ );

  return HUEBridge_Call($hash, $chash, 'sensors/' . $1, $obj) if( $id =~ m/^S(\d.*)/ );

  return HUEBridge_Call($hash, $chash, 'lights/' . $id, $obj);
}

sub
HUEBridge_Detect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 3, "HUEBridge_Detect";

  my ($err,$ret) = HttpUtils_BlockingGet({
    url => "https://discovery.meethue.com/",
    #method => "GET",
  });

  if( defined($err) && $err ) {
    Log3 $name, 3, "HUEBridge_Detect: error detecting bridge: ".$err;
    return;
  }

  my $host = '';
  if( defined($ret) && $ret ne '' && $ret =~ m/^[\[{].*[\]}]$/ ) {
    my $obj = eval { JSON->new->utf8(0)->decode($ret) };
    Log3 $name, 2, "$name: json error: $@ in $ret" && return if( $@ );

    if( defined($obj->[0])
        && defined($obj->[0]->{'internalipaddress'}) ) {
      $host = $obj->[0]->{'internalipaddress'};
    }
  }

  if( !defined($host) || $host eq '' ) {
    Log3 $name, 3, 'HUEBridge_Detect: error detecting bridge.';
    return;
  }

  Log3 $name, 3, "HUEBridge_Detect: ${host}";
  $hash->{host} = $host;

  return $host;
}

sub
HUEBridge_Define($$)
{
  my ($hash, $def) = @_;

  return $@ unless ( FHEM::Meta::SetInternals($hash) );


  my @args = split("[ \t]+", $def);

  return "Usage: define <name> HUEBridge [<host>] [interval]"  if(@args < 2);

  my ($name, $type, $host, $interval) = @args;

  if( !defined($host) ) {
    $hash->{NUPNP} = 1;
    HUEBridge_Detect($hash);
  } else {
    delete $hash->{NUPNP};
  }

  $interval= 60 unless defined($interval);
  if( $interval < 10 ) { $interval = 10; }

  readingsSingleUpdate($hash, 'state', 'initialized', 1 );

  $hash->{host} = $host;
  $hash->{INTERVAL} = $interval;

  $attr{$name}{"key"} = join "",map { unpack "H*", chr(rand(256)) } 1..16 unless defined( AttrVal($name, "key", undef) );

  $hash->{helper}{ignored} = {};
  $hash->{helper}{last_config_timestamp} = 0;

  if( !defined($hash->{helper}{count}) ) {
    $modules{$hash->{TYPE}}{helper}{count} = 0 if( !defined($modules{$hash->{TYPE}}{helper}{count}) );
    $hash->{helper}{count} =  $modules{$hash->{TYPE}}{helper}{count}++;
  }

  $hash->{NOTIFYDEV} = "global";

  if( $init_done ) {
    HUEBridge_OpenDev( $hash ) if( !IsDisabled($name) );
  }

  return undef;
}
sub
HUEBridge_Rename($$$)
{
  my ($new,$old) = @_;

  foreach my $chash ( values %{$modules{HUEDevice}{defptr}} ) {
    next if( !$chash->{IODev} );
    next if( $chash->{IODev}{NAME} ne $new );   # IODev already points to the renamed device!

    HUEDevice_IODevChanged($chash, $old, $new); # updete DEF & defptr key
  }
}
sub
HUEBridge_Notify($$)
{
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  if( IsDisabled($name) > 0 ) {
    readingsSingleUpdate($hash, 'state', 'inactive', 1 ) if( ReadingsVal($name,'inactive','' ) ne 'disabled' );
    return undef;
  }

  HUEBridge_OpenDev($hash);

  return undef;
}

sub
HUEBridge_Undefine($$)
{
  my ($hash,$arg) = @_;

  HUEBridge_closeWebsocket($hash);
  HUEBridge_closeEventStream($hash);

  RemoveInternalTimer($hash);
  return undef;
}

sub
HUEBridge_hash2header($)
{
  my ($hash) = @_;

  return $hash if( ref($hash) ne 'HASH' );

  my $header;
  foreach my $key (keys %{$hash}) {
    #$header .= "\r\n" if( $header );
    $header .= "$key: $hash->{$key}\r\n";
  }

  return $header;
}
sub
HUEBridge_closeWebsocket($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash, 'HUEBridge_openWebsocket' );

  delete $hash->{buf};
  delete $hash->{websocket};

  close($hash->{CD}) if( defined($hash->{CD}) );
  delete($hash->{CD});

  delete($selectlist{$name});
  delete($hash->{FD});

  delete($hash->{PORT});
}
sub
HUEBridge_openWebsocket($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return if( !defined($hash->{websocketport}) );

  HUEBridge_closeWebsocket($hash);

  my ($host,undef) = split(':',$hash->{host},2);
  if( my $socket = IO::Socket::INET->new(PeerAddr=>"$host:$hash->{websocketport}", Timeout=>2, Blocking=>1, ReuseAddr=>1) ) {
    $hash->{CD}    = $socket;
    $hash->{FD}    = $socket->fileno();

    $hash->{PORT}  = $socket->sockport if( $socket->sockport );

    $selectlist{$name} = $hash;

    Log3 $name, 3, "$name: websocket opened to $host:$hash->{websocketport}";


    my $ret = "GET ws://$host:$hash->{websocketport} HTTP/1.1\r\n";
    $ret .= HUEBridge_hash2header( {                  'Host' => "$host:$hash->{websocketport}",
                                                   'Upgrade' => 'websocket',
                                                'Connection' => 'Upgrade',
                                                    'Pragma' => 'no-cache',
                                             'Cache-Control' => 'no-cache',
                                         'Sec-WebSocket-Key' => 'RkhFTQ==',
                                     'Sec-WebSocket-Version' => '13',
                                   } );

    $ret .= "\r\n";
#Log 1, $ret;

    syswrite($hash->{CD}, $ret );

  } else {
    Log3 $name, 2, "$name: failed to open websocket";

  }
}

sub
HUEBridge_closeEventStream($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash, "HUEBridge_openEventStream" );

  return if( !defined($hash->{helper}{HTTP_CONNECTION}) );

  $hash->{EventStream} = 'closing';
  Log3 $name, 4, "$name: EventStream: $hash->{EventStream}";

  HttpUtils_Close( $hash->{helper}{HTTP_CONNECTION} );
  delete $hash->{helper}{HTTP_CONNECTION};

  delete $hash->{buf};

  delete($hash->{EventStream});
  Log3 $name, 4, "$name: EventStream: closed";
}
sub
HUEBridge_openEventStream($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $lastID;
     $lastID = $hash->{helper}{HTTP_CONNECTION}{lastID} if( defined($hash->{helper}{HTTP_CONNECTION}) );

  HUEBridge_closeEventStream($hash);

  $hash->{EventStream} = 'connecting';
  Log3 $name, 4, "$name: EventStream: $hash->{EventStream}";

  my $params = {
               url => "https://$hash->{host}/eventstream/clip/v2",
       httpversion => '1.1',
            method => 'GET',
           timeout => AttrVal($name, 'eventstreamTimeout', 60*60),
incrementalTimeout => 1,
        noshutdown => 1,
         keepalive => 1,
            header => {                Accept => 'text/event-stream',
                        'HUE-Application-Key' => $attr{$name}{key}, },
              type => 'event',
              hash => $hash,
          callback => \&HUEBridge_dispatch,
     };
  $params->{header}{'Last-Event-ID'} = $lastID if( $lastID );

  $hash->{helper}{HTTP_CONNECTION} = {};
  map { $hash->{helper}{HTTP_CONNECTION}{$_} = $params->{$_} } keys %{$params};

  HttpUtils_NonblockingGet( $hash->{helper}{HTTP_CONNECTION} );
}

sub
HUEBridge_fillBridgeInfo($$)
{
  my ($hash,$config) = @_;
  my $name = $hash->{NAME};

  $hash->{name} = $config->{name};
  $hash->{modelid} = $config->{modelid};
  $hash->{bridgeid} = $config->{bridgeid};
  $hash->{swversion} = $config->{swversion};
  $hash->{apiversion} = $config->{apiversion};
  $hash->{zigbeechannel} = $config->{zigbeechannel};

  delete $hash->{is_deCONZ};
  if( defined($config->{websocketport})
      || defined($hash->{modelid}) && $hash->{modelid} eq 'deCONZ' ) {
    $hash->{is_deCONZ} = 1;
  }

  delete $hash->{has_v2_api};
  if( !$hash->{is_deCONZ} && $hash->{swversion} >= 1948086000 ) {
    $hash->{has_v2_api} = 1;
  }

  if( $hash->{apiversion} ) {
    my @l = split( '\.', $config->{apiversion} );
    $hash->{helper}{apiversion} = ($l[0] << 16) + ($l[1] << 8) + $l[2];
  }


  if( defined($config->{websocketport}) ) {
    $hash->{websocketport} = $config->{websocketport};
    HUEBridge_openWebsocket($hash) if( !defined($hash->{CD}) );

  } elsif( $hash->{has_v2_api} ) {
    HUEBridge_openEventStream($hash) if( !defined($hash->{helper}{HTTP_CONNECTION}) );

  }


  if( $hash->{modelid}
      && !defined($config->{'linkbutton'})
      && !defined($attr{$name}{icon}) ) {
    $attr{$name}{icon} = 'hue_filled_bridge_v1' if( $hash->{modelid} eq 'BSB001' );
    $attr{$name}{icon} = 'hue_filled_bridge_v2' if( $hash->{modelid} eq 'BSB002' );
  }
}

sub
HUEBridge_OpenDev($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  HUEBridge_Detect($hash) if( defined($hash->{NUPNP}) );

  my ($err,$ret) = HttpUtils_BlockingGet({
    url => "http://$hash->{host}/description.xml",
    method => "GET",
    timeout => 3,
  });

  if( defined($err) && $err ) {
    Log3 $name, 2, "HUEBridge_OpenDev: error reading description: ". $err;

  } else {
    Log3 $name, 5, "HUEBridge_OpenDev: got description: $ret";
    $ret =~ m/<modelName>([^<]*)/;
    $hash->{modelName} = $1;
    $ret =~ m/<manufacturer>([^<]*)/;
    $hash->{manufacturer} = $1;

  }

  my $result = HUEBridge_Call($hash, undef, 'config', undef);
  if( !defined($result) ) {
    Log3 $name, 2, "HUEBridge_OpenDev: got empty config";
    return undef;
  }
  Log3 $name, 5, "HUEBridge_OpenDev: got config " . Dumper $result;

  HUEBridge_fillBridgeInfo($hash, $result);
  if( !defined($result->{'linkbutton'}) || !AttrVal($name, 'key', undef) )
    {
      HUEBridge_Pair($hash);
      return;

    }

  $hash->{mac} = $result->{mac};

  if( !$hash->{is_deCONZ} ) {
    my $params = {
                url => "https://$hash->{host}/auth/v1",
        #httpversion => '1.1',
             method => 'GET',
            timeout => 5,
             header => { 'HUE-Application-Key' => $attr{$name}{key}, },
               type => 'application id',
               hash => $hash,
           callback => \&HUEBridge_dispatch,
       };
    HttpUtils_NonblockingGet( $params );
  }

  readingsSingleUpdate($hash, 'state', 'connected', 1 );

  HUEBridge_Autocreate($hash);
  HUEBridge_GetUpdate($hash);

  return undef;
}
sub
HUEBridge_Pair($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  readingsSingleUpdate($hash, 'state', 'pairing', 1 );

  my $result = HUEBridge_Register($hash);
  if( $result->{'error'} )
    {
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+5, "HUEBridge_Pair", $hash, 0);

      return undef;
    }

  $attr{$name}{key} = $result->{success}{username} if( $result->{success}{username} );

  readingsSingleUpdate($hash, 'state', 'paired', 1 );

  HUEBridge_OpenDev($hash);

  return undef;
}

sub
HUEBridge_string2array($)
{
  my ($lights) = @_;

  my %lights = ();
  foreach my $part ( split(',', $lights) ) {
    my $light = $part;
    $light = $defs{$light}{ID} if( defined $defs{$light} && $defs{$light}{TYPE} eq 'HUEDevice' );
    if( $light =~ m/^G/ ) {
      my $lights = $defs{$part}->{lights};
      if( $lights ) {
        foreach my $light ( split(',', $lights) ) {
          $lights{$light} = 1;
        }
      }
    } else {
      $lights{$light} = 1;
    }
  }

  my @lights = sort {$a<=>$b} keys(%lights);
  return \@lights;
}
sub
HUEBridge_scene2id($$)
{
  # hash is the bridge device
  my ($hash,$id) = @_;
  $hash = $defs{$hash} if( ref($hash) ne 'HASH' );
  return undef if( !$hash );

  if( $id =~ m/\[id=(.*)\]$/ ) {
    $id = $1;
  }

  if( my $scenes = $hash->{helper}{scenes} ) {
    return $id if( defined($hash->{helper}{scenes}{$id}) );
    $id = lc($id);
    $id =~ s/\((.*)\)$/\\\($1\\\)/;

    foreach my $key ( keys %{$scenes} ) {
      my $scene = $scenes->{$key};

      return $key if( lc($key) eq $id );
      #return $key if( $scene->{name} eq $id );
      return $key if( lc($scene->{name}) =~ m/^$id$/ );
    }
  }

  return '<unknown>';
}
sub
HUEBridge_scene2id_deCONZ($$)
{
  # hash is the client device
  my ($hash,$id) = @_;
  my $name = $hash->{NAME};
  #Log3 $name, 4, "HUEBridge_scene2id_deCONZ: $id, hash: " . Dumper $hash;
  $hash = $defs{$hash} if( ref($hash) ne 'HASH' );
  return undef if( !$hash );

  if( $id =~ m/\[id=(.*)\]$/ ) {
    $id = $1;
  }

  if( my $scenes = $hash->{helper}{scenes} ) {
    $id = lc($id);
    $id =~ s/\((.*)\)$/\\\($1\\\)/;
    for my $scene ( @{$scenes} ) {
       #Log3 $name, 4, "HUEBridge_scene2id_deCONZ scene:". Dumper $scene;
      return $scene->{id} if( lc($scene->{name}) =~ m/^$id$/ );
    }
  }

  return '<unknown>';
}

sub
HUEbridge_groupOfLights($$)
{
  my ($hash,$lights) = @_;
  $hash = $defs{$hash} if( ref($hash) ne 'HASH' );
  return undef if( !$hash );
  my $name = $hash->{NAME};

  my $group;
  foreach my $chash ( values %{$modules{HUEDevice}{defptr}} ) {
    next if( !$chash->{IODev} );
    next if( !$chash->{lights} );
    next if( $chash->{IODev}{NAME} ne $name );
    next if( $chash->{helper}{devtype} ne 'G' );
    next if( $chash->{lights} ne $lights );

    $group .= ',' if( $group );
    $group .= AttrVal($chash->{NAME}, 'alias', $chash->{NAME});
  }

  return $group;
}

sub
HUEBridge_Set($@);
sub
HUEBridge_Set($@)
{
  my ($hash, $name, $cmd, @args) = @_;
  my ($arg, @params) = @args;

  $hash->{".triggerUsed"} = 1;

  return "$name: not paired" if( ReadingsVal($name, 'state', '' ) =~ m/^link/ );
  #return "$name: not connected" if( $hash->{STATE} ne 'connected'  );

  # usage check
  if($cmd eq 'reconnect') {
    Log3 $name, 2, "$name: reconnecting";
    HUEBridge_closeWebsocket($hash);
    HUEBridge_closeEventStream($hash);

    HUEBridge_OpenDev( $hash );
    #HUEBridge_openEventStream( $hash );
    return undef;

  } elsif($cmd eq 'close') {
    HUEBridge_closeWebsocket($hash);
    HUEBridge_closeEventStream($hash);

    return undef;

  } elsif($cmd eq 'statusRequest') {
    return "usage: statusRequest" if( @args != 0 );

    $hash->{LOCAL} = 1;
    #RemoveInternalTimer($hash);
    HUEBridge_GetUpdate($hash);
    delete $hash->{LOCAL};
    return undef;

  } elsif($cmd eq 'swupdate') {
    return "usage: swupdate" if( @args != 0 );

    my $obj = {
      'swupdate' => { 'updatestate' => 3, },
    };
    my $result = HUEBridge_Call($hash, undef, 'config', $obj);

    if( !defined($result) || $result->{'error'} ) {
      return $result->{'error'}->{'description'};
    }

    $hash->{updatestate} = 3;
    $hash->{helper}{updatestate} = $hash->{updatestate};
    readingsSingleUpdate($hash, 'state', 'updating', 1 );
    return "starting update";

  } elsif($cmd eq 'autocreate') {
    return "usage: autocreate [sensors]" if( $arg && $arg ne 'sensors' );

    return HUEBridge_Autocreate($hash,1,$arg);

  } elsif($cmd eq 'autodetect') {
    return "usage: autodetect" if( @args != 0 );

    my $result = HUEBridge_Call($hash, undef, 'lights', undef, 'POST');
    return $result->{error}{description} if( $result->{error} );

    return $result->{success}{'/lights'} if( $result->{success} );

    return undef;

  } elsif($cmd eq 'delete') {
    return "usage: delete <id>" if( @args != 1 );

    if( defined $defs{$arg} && $defs{$arg}{TYPE} eq 'HUEDevice' ) {
      $arg = $defs{$arg}{ID};
    }
    return "$arg is not a hue light number" if( $arg !~ m/^\d+$/ );

    my $code = $name ."-". $arg;
    if( my $chash = $modules{HUEDevice}{defptr}{$code} ) {
      CommandDelete( undef, "$chash->{NAME}" );
      CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );
    }

    my $result = HUEBridge_Call($hash, undef, "lights/$arg", undef, 'DELETE');
    return $result->{error}{description} if( $result->{error} );

    return undef;

  } elsif($cmd eq 'creategroup') {
    return "usage: creategroup <name> <lights>" if( @args < 2 );

    my $obj = { 'name' => join( ' ', @args[0..@args-2]),
                'lights' => HUEBridge_string2array($args[@args-1]),
    };

    my $result = HUEBridge_Call($hash, undef, 'groups', $obj, 'POST');
    return $result->{error}{description} if( $result->{error} );

    if( $result->{success} ) {
      HUEBridge_Autocreate($hash);

      my $code = $name ."-G". $result->{success}{id};
      return "created $modules{HUEDevice}{defptr}{$code}->{NAME}" if( defined($modules{HUEDevice}{defptr}{$code}) );
    }

    return undef;

  } elsif($cmd eq 'deletegroup') {
    return "usage: deletegroup <id>" if( @args != 1 );

    if( defined $defs{$arg} && $defs{$arg}{TYPE} eq 'HUEDevice' ) {
      return "$arg is not a hue group" if( $defs{$arg}{ID} !~ m/^G/ );
      $defs{$arg}{ID} =~ m/G(.*)/;
      $arg = $1;
    }

    my $code = $name ."-G". $arg;
    if( my $chash = $modules{HUEDevice}{defptr}{$code} ) {
      CommandDelete( undef, "$chash->{NAME}" );
      CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );
    }

    return "$arg is not a hue group number" if( $arg !~ m/^\d+$/ );

    my $result = HUEBridge_Call($hash, undef, "groups/$arg", undef, 'DELETE');
    return $result->{error}{description} if( $result->{error} );

    return undef;

  } elsif($cmd eq 'savescene') {
    my $result;
    if( $hash->{helper}{apiversion} && $hash->{helper}{apiversion} >= (1<<16) + (11<<8) ) {
      return "usage: savescene <name> <lights>" if( @args < 2 );

      my $obj = { 'name' => join( ' ', @args[0..@args-2]),
                  'recycle' => JSON::true,
                  'lights' => HUEBridge_string2array($args[@args-1]),
      };

      $result = HUEBridge_Call($hash, undef, "scenes", $obj, 'POST');

    } else {
      return "usage: savescene <id> <name> <lights>" if( @args < 3 );

      my $obj = { 'name' => join( ' ', @args[1..@args-2]),
                  'lights' => HUEBridge_string2array($args[@args-1]),
      };
      $result = HUEBridge_Call($hash, undef, "scenes/$arg", $obj, 'PUT');

    }
    return $result->{error}{description} if( $result->{error} );

    if( $result->{success} ) {
      return "created $result->{success}{id}" if( $result->{success}{id} );
      return "created $arg";
    }

    return undef;

  } elsif($cmd eq 'modifyscene') {
    return "usage: modifyscene <id> <light> <light args>" if( @args < 3 );

    my( $light, @aa ) = @params;
    $light = $defs{$light}{ID} if( defined $defs{$light} && $defs{$light}{TYPE} eq 'HUEDevice' );

    my %obj;
    if( (my $joined = join(" ", @aa)) =~ /:/ ) {
      my @cmds = split(":", $joined);
      for( my $i = 0; $i <= $#cmds; ++$i ) {
        HUEDevice_SetParam(undef, \%obj, split(" ", $cmds[$i]) );
      }
    } else {
      my ($cmd, $value, $value2, @a) = @aa;

      HUEDevice_SetParam(undef, \%obj, $cmd, $value, $value2);
    }

    my $result;
    if( $hash->{helper}{apiversion} && $hash->{helper}{apiversion} >= (1<<16) + (11<<8) ) {
      $result = HUEBridge_Call($hash, undef, "scenes/$arg/lightstates/$light", \%obj, 'PUT');
    } else {
      $result = HUEBridge_Call($hash, undef, "scenes/$arg/lights/$light/state", \%obj, 'PUT');
    }
    return $result->{error}{description} if( $result->{error} );

    return undef;

  } elsif($cmd eq 'deletescene') {
    return "usage: deletescene <id>" if( @args != 1 );

    my $result = HUEBridge_Call($hash, undef, "scenes/$arg", undef, 'DELETE');
    return $result->{error}{description} if( $result->{error} );

    return undef;

  } elsif($cmd eq 'scene') {
    return "usage: scene <id>|<name>" if( !@args );
    $arg = HUEBridge_scene2id($hash, join(' ', @args));

    my $obj = { 'scene' => $arg };
    my $result = HUEBridge_Call($hash, undef, "groups/0/action", $obj, 'PUT');
    return $result->{error}{description} if( $result->{error} );

    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+10, "HUEBridge_GetUpdate", $hash, 0);

    return undef;

  } elsif($cmd eq 'createrule' || $cmd eq 'updaterule') {
    return "usage: createrule <name> <conditions&actions json>" if( $cmd eq 'createrule' && @args < 2 );
    return "usage: updaterule <id> <conditions&actions json>" if( $cmd eq 'updaterule' && @args < 2 );

    $args[@args-1] = '
{  "name":"Wall Switch Rule",
   "conditions":[
        {"address":"/sensors/1/state/lastupdated","operator":"dx"}
   ],
   "actions":[
        {"address":"/groups/0/action","method":"PUT", "body":{"scene":"S3"}}
]}' if( 0 || !$args[@args-1] );
    my $json = join( ' ', @args[1..@args-1]);
    my $obj = eval { JSON->new->utf8(0)->decode($json) };
    if( $@ ) {
      Log3 $name, 2, "$name: json error: $@ in $json";
      return undef;
    }

    my $result;
    if( $cmd eq 'updaterule' ) {
     $result = HUEBridge_Call($hash, undef, "rules/$args[0]", $obj, 'PUT');
    } else {
     $obj->{name} = join( ' ', @args[0..@args-2]);
     $result = HUEBridge_Call($hash, undef, 'rules', $obj, 'POST');
    }
    return $result->{error}{description} if( $result->{error} );

    return "created rule id $result->{success}{id}" if( $result->{success} && $result->{success}{id} );

    return undef;

  } elsif($cmd eq 'updateschedule') {
    return "usage: $cmd <id> <attributes json>" if( @args < 2 );
    return "$arg is not a hue schedule number" if( $arg !~ m/^\d+$/ );

    my $json = join( ' ', @args[1..@args-1]);
    my $obj = eval { JSON->new->utf8(0)->decode($json) };
    if( $@ ) {
      Log3 $name, 2, "$name: json error: $@ in $json";
      return undef;
    }

    my $result;
    $result = HUEBridge_Call($hash, undef, "schedules/$arg", $obj, 'PUT');
    return "Error: " . $result->{error}{description} if( $result->{error} );
    return "Schedule id $arg updated" if( $result->{success} );
    return undef;

  } elsif($cmd eq 'enableschedule' || $cmd eq 'disableschedule') {
    return "usage: $cmd <id>" if( @args != 1 );
    return "$arg is not a hue schedule number" if( $arg !~ m/^\d+$/ );

    my $newStatus = 'enabled';
    $newStatus = 'disabled' if($cmd eq 'disableschedule');

    $args[1] = sprintf( '{"status":"%s"}', $newStatus );
    return HUEBridge_Set($hash, $name,'updateschedule',@args)

  } elsif($cmd eq 'deleterule') {
    return "usage: deleterule <id>" if( @args != 1 );
    return "$arg is not a hue rule number" if( $arg !~ m/^\d+$/ );

    my $result = HUEBridge_Call($hash, undef, "rules/$arg", undef, 'DELETE');
    return $result->{error}{description} if( $result->{error} );

    return undef;

  } elsif($cmd eq 'createsensor') {
    return "usage: createsensor <name> <type> <uniqueid> <swversion> <modelid>" if( @args < 5 );

    return "usage: type must be one of: Switch OpenClose Presence Temperature Humidity GenericFlag GenericStatus " if( $args[@args-4] !~ m/Switch|OpenClose|Presence|Temperature|Humidity|Lightlevel|GenericFlag|GenericStatus/ );

    my $obj = { 'name' => join( ' ', @args[0..@args-5]),
                'type' => "CLIP$args[@args-4]",
                'uniqueid' => $args[@args-3],
                'swversion' => $args[@args-2],
                'modelid' => $args[@args-1],
                'manufacturername' => 'FHEM-HUE',
              };

    my $result = HUEBridge_Call($hash, undef, 'sensors', $obj, 'POST');
    return $result->{error}{description} if( $result->{error} );

    return "created sensor id $result->{success}{id}" if( $result->{success} );

#    if( $result->{success} ) {
#      my $code = $name ."-S". $result->{success}{id};
#      my $devname = "HUEDevice" . $id;
#      $devname = $name ."_". $devname if( $hash->{helper}{count} );
#      my $define = "$devname HUEDevice sensor $id IODev=$name";
#
#      Log3 $name, 4, "$name: create new device '$devname' for address '$id'";
#
#      my $cmdret= CommandDefine(undef,$define);
#
#      return "created $modules{HUEDevice}{defptr}{$code}->{NAME}" if( defined($modules{HUEDevice}{defptr}{$code}) );
#    }

    return undef;

  } elsif($cmd eq 'deletesensor') {
    return "usage: deletesensor <id>" if( @args != 1 );

    if( defined $defs{$arg} && $defs{$arg}{TYPE} eq 'HUEDevice' ) {
      return "$arg is not a hue sensor" if( $defs{$arg}{ID} !~ m/^S/ );
      $defs{$arg}{ID} =~ m/S(.*)/;
      $arg = $1;
    }

    my $code = $name ."-S". $arg;
    if( my $chash = $modules{HUEDevice}{defptr}{$code} ) {
      CommandDelete( undef, "$chash->{NAME}" );
      CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );
    }

    return "$arg is not a hue sensor number" if( $arg !~ m/^\d+$/ );

    my $result = HUEBridge_Call($hash, undef, "sensors/$arg", undef, 'DELETE');
    return $result->{error}{description} if( $result->{error} );

    return undef;

  } elsif($cmd eq 'configsensor' || $cmd eq 'setsensor' || $cmd eq 'updatesensor') {
    return "usage: $cmd <id> <json>" if( @args < 2 );

    if( defined $defs{$arg} && $defs{$arg}{TYPE} eq 'HUEDevice' ) {
      return "$arg is not a hue sensor" if( $defs{$arg}{ID} !~ m/^S/ );
      $defs{$arg}{ID} =~ m/S(.*)/;
      $arg = $1;
    }
    return "$arg is not a hue sensor number" if( $arg !~ m/^\d+$/ );

    my $json = join( ' ', @args[1..@args-1]);
    my $decoded = eval { JSON->new->utf8(0)->decode($json) };
    if( $@ ) {
      Log3 $name, 2, "$name: json error: $@ in $json";
      return undef;
    }
    $json = $decoded;

    my $endpoint = '';
    $endpoint = 'state' if( $cmd eq 'setsensor' );
    $endpoint = 'config' if( $cmd eq 'configsensor' );

    my $result = HUEBridge_Call($hash, undef, "sensors/$arg/$endpoint", $json, 'PUT');
    return $result->{error}{description} if( $result->{error} );

    my $code = $name ."-S". $arg;
    if( my $chash = $modules{HUEDevice}{defptr}{$code} ) {
      HUEDevice_GetUpdate($chash);
    }

    return undef;

  } elsif($cmd eq 'configlight' || $cmd eq 'setlight' || $cmd eq 'updatelight') {
    return "usage: $cmd <id> <json>" if( @args < 2 );

    if( defined $defs{$arg} && $defs{$arg}{TYPE} eq 'HUEDevice' ) {
      return "$arg is not a hue light" if( $defs{$arg}{ID} );
    }
    return "$arg is not a hue sensor number" if( $arg !~ m/^\d+$/ );

    my $json = join( ' ', @args[1..@args-1]);
    my $decoded = eval { JSON->new->utf8(0)->decode($json) };
    if( $@ ) {
      Log3 $name, 2, "$name: json error: $@ in $json";
      return undef;
    }
    $json = $decoded;

    my $endpoint = '';
    $endpoint = 'state' if( $cmd eq 'setlight' );
    $endpoint = 'config' if( $cmd eq 'configlight' );

    my $result = HUEBridge_Call($hash, undef, "lights/$arg/$endpoint", $json, 'PUT');
    return $result->{error}{description} if( $result->{error} );

    my $code = $name ."-". $arg;
    if( my $chash = $modules{HUEDevice}{defptr}{$code} ) {
      HUEDevice_GetUpdate($chash);
    }

    return undef;

  } elsif($cmd eq 'deletewhitelist') {
    return "usage: deletewhitelist <key>" if( @args != 1 );

    my $result = HUEBridge_Call($hash, undef, "config/whitelist/$arg", undef, 'DELETE');
    return $result->{error}{description} if( $result->{error} );

    return undef;

  } elsif($cmd eq 'touchlink') {
    return "usage: touchlink" if( @args != 0 );

    my $obj = { 'touchlink' => JSON::true };

    my $result = HUEBridge_Call($hash, undef, 'config', $obj, 'PUT');
    return $result->{error}{description} if( $result->{error} );

    return undef if( $result->{success} );

    return undef;

  } elsif($cmd eq 'checkforupdate') {
    return "usage: checkforupdate" if( @args != 0 );

    my $obj = { swupdate => {'checkforupdate' => JSON::true } };

    my $result = HUEBridge_Call($hash, undef, 'config', $obj, 'PUT');
    return $result->{error}{description} if( $result->{error} );

    return undef if( $result->{success} );

    return undef;

  } elsif($cmd eq 'active') {
    return "can't activate disabled bridge." if(AttrVal($name, "disable", undef));

    readingsSingleUpdate($hash, 'state', 'active', 1 );
    HUEBridge_OpenDev($hash);
    return undef;

  } elsif($cmd eq 'inactive') {
    readingsSingleUpdate($hash, 'state', 'inactive', 1 );
    return undef;

  } elsif($cmd eq 'refreshv2resources' ) {
    return "$name: v2 api not supported" if( !$hash->{has_v2_api} );
    HUEBridge_refreshv2resources($hash, 1);

    return "done";

  } elsif($cmd eq 'v2json' ) {
    return "usage: $cmd <v2 light id> <json>" if( !@params );

    my $params = {
                url => "https://$hash->{host}/clip/v2/resource/light/$arg",
             method => 'PUT',
            timeout => 5,
             header => { 'HUE-Application-Key' => $attr{$name}{key}, },
               type => $cmd,
               hash => $hash,
           callback => \&HUEBridge_dispatch,
               data => join( ' ', @params ),
       };

    my($err,$data) = HttpUtils_BlockingGet( $params );

    if( !$data ) {
      Log3 $name, 2, "$name: empty answer received for $cmd";
      return undef;
    } elsif( $data =~ m'HTTP/1.1 200 OK' ) {
      Log3 $name, 4, "$name: empty answer received for $cmd";
      return undef;
    } elsif( $data !~ m/^[\[{].*[\]}]$/ ) {
      #Log3 $name, 2, "$name: invalid json detected for $cmd: $data";
      #return undef;
    }

    Log3 $name, 4, "$name: got: $data";

    my $json = eval { JSON->new->utf8(0)->decode($data) };
    Log3 $name, 2, "$name: json error: $@ in $data" if( $@ );
    return undef if( !$json );

    Log3 $name, 1, "$name: error: ". Dumper $json->{errors} if( scalar @{$json->{errors}} );
    return Dumper $json if( scalar @{$json->{errors}} );

    return;

  } elsif($cmd eq 'v2effect' ) {
    return "usage: $cmd <v2 light id> <effect>" if( !@params );
    my $params = {
                url => "https://$hash->{host}/clip/v2/resource/light/$arg",
             method => 'PUT',
            timeout => 5,
             header => { 'HUE-Application-Key' => $attr{$name}{key}, },
               type => $cmd,
               hash => $hash,
           callback => \&HUEBridge_dispatch,
               data => '{"effects": {"effect": "'. $params[0] .'"}, "on": {"on": true}}',
       };

    my($err,$data) = HttpUtils_BlockingGet( $params );

    if( !$data ) {
      Log3 $name, 2, "$name: empty answer received for $cmd";
      return undef;
    } elsif( $data =~ m'HTTP/1.1 200 OK' ) {
      Log3 $name, 4, "$name: empty answer received for $cmd";
      return undef;
    } elsif( $data !~ m/^[\[{].*[\]}]$/ ) {
      #Log3 $name, 2, "$name: invalid json detected for $cmd: $data";
      #return undef;
    }

    Log3 $name, 4, "$name: got: $data";

    my $json = eval { JSON->new->utf8(0)->decode($data) };
    Log3 $name, 2, "$name: json error: $@ in $data" if( $@ );
    return undef if( !$json );

    Log3 $name, 1, "$name: error: ". Dumper $json->{errors} if( scalar @{$json->{errors}} );
    return Dumper $json if( scalar @{$json->{errors}} );

    return;

  } elsif($cmd eq 'v2scene' ) {
    return "usage: $cmd <v2 scene id>" if( @args != 1 || $args[0] eq '?' );
    my $params = {
                url => "https://$hash->{host}/clip/v2/resource/scene/$arg",
             method => 'PUT',
            timeout => 5,
             header => { 'HUE-Application-Key' => $attr{$name}{key}, },
               type => $cmd,
               hash => $hash,
           callback => \&HUEBridge_dispatch,
               #data => '{ "recall": { "action": "active" } }',
               data => '{ "recall": { "action": "dynamic_palette" } }',
       };

    my($err,$data) = HttpUtils_BlockingGet( $params );

    if( !$data ) {
      Log3 $name, 2, "$name: empty answer received for $cmd";
      return undef;
    } elsif( $data =~ m'HTTP/1.1 200 OK' ) {
      Log3 $name, 4, "$name: empty answer received for $cmd";
      return undef;
    } elsif( $data !~ m/^[\[{].*[\]}]$/ ) {
      #Log3 $name, 2, "$name: invalid json detected for $cmd: $data";
      #return undef;
    }

    Log3 $name, 4, "$name: got: $data";

    my $json = eval { JSON->new->utf8(0)->decode($data) };
    Log3 $name, 2, "$name: json error: $@ in $data" if( $@ );
    return undef if( !$json );

    Log3 $name, 1, "$name: error: ". Dumper $json->{errors} if( scalar @{$json->{errors}} );
    return Dumper $json if( scalar @{$json->{errors}} );

    return;

  } else {
    my $list = "active inactive delete creategroup deletegroup savescene deletescene modifyscene";

    if( my $scenes = $hash->{helper}{scenes} ) {
      my %count;
      map { $count{$scenes->{$_}{name}}++ } keys %{$scenes};
      $list .= " scene:". join(",", sort map { my $scene = $scenes->{$_}{name};
                                               my $group = '';
                                               if( $scenes->{$_}{lights} && $count{$scene} > 1 ) {
                                                 my $lights = join( ",", @{$scenes->{$_}{lights}} );
                                                 $group = HUEbridge_groupOfLights($hash,$lights);
                                                 $group = join( ";", map { my $l = $hash->{helper}{lights}{$_}{name}; $l?$l:$_;} @{$scenes->{$_}{lights}} ) if( !$group && $hash->{helper}{lights} );
                                                 $group = $lights if( !$group );
                                                 $group =~ s/,/;/g;
                                                 $group = '' if( $group =~ /,/ );
                                                 $group = $_ if( !$group );

                                                 $scene .= " ($group)";
                                                 $scene .= " [id=$_]" if( 1 || $group =~ /;/ );
                                               }
                                               $scene =~ s/ /#/g; $scene;
                                             } keys %{$scenes} );
    } else {
      $list .= " scene";
    }
    $list .= " swupdate:noArg" if( defined($hash->{updatestate}) && $hash->{updatestate} =~ '^2' );
    $list .= " createrule updaterule updateschedule enableschedule disableschedule deleterule createsensor deletesensor configlight configsensor setsensor updatesensor deletewhitelist touchlink:noArg checkforupdate:noArg autodetect:noArg autocreate:noArg statusRequest:noArg";

    if( $hash->{has_v2_api} ) {
      $list .= " refreshv2resources v2json v2scene ";
    }

    return "Unknown argument $cmd, choose one of $list";
  }
}

sub
HUEBridge_V2IdOfV1Id($$$)
{
  my ($hash, $type, $id) = @_;
  my $name = $hash->{NAME};
  return "undef" if( !$id );
  return "undef" if( !$type );
  return "undef" if( !$hash->{has_v2_api} );

  foreach my $resource ( values %{$hash->{helper}{resource}{by_id}} ) {
    next if( !$resource->{id_v1} );
    next if( !$resource->{type} );
    next if( $resource->{id_v1} ne $id );
    next if( $resource->{type} ne $type );

    return $resource->{id};
  }

  return undef;
}
sub
HUEBridge_GetResource($$)
{
  my ($hash, $id) = @_;
  return undef if( !$hash->{has_v2_api} );
  return undef if( !$id );

  if( my $resource = $hash->{helper}{resource}{by_id}{$id} ) {
    return $resource;
  }

  return undef;
}
sub
HUEBridge_nameOfResource($$)
{
  my ($hash, $id) = @_;
  my $name = $hash->{NAME};
  return "$name: v2 api not supported" if( !$hash->{has_v2_api} );

  if( my $resource = $hash->{helper}{resource}{by_id}{$id} ) {
    return $resource->{metadata}{name};
  }

  return '<unknown>';
}

sub
HUEBridge_Get($@)
{
  my ($hash, $name, $cmd, @args) = @_;
  my ($arg, @params) = @args;

  return "$name: not paired" if( ReadingsVal($name, 'state', '' ) =~ m/^link/ );
  #return "$name: not connected" if( $hash->{STATE} ne 'connected'  );
  return "$name: get needs at least one parameter" if( !defined($cmd) );

  # usage check
  if($cmd eq 'devices'
     || $cmd eq 'lights') {
    my $result =  HUEBridge_Call($hash, undef, 'lights', undef);
    return $result->{error}{description} if( $result->{error} );
    $hash->{helper}{lights} = $result;
    my $ret = "";
    foreach my $key ( sort {$a<=>$b} keys %{$result} ) {
      my $code = $name ."-". $key;
      my $fhem_name = '';
         $fhem_name = $modules{HUEDevice}{defptr}{$code}->{NAME} if( defined($modules{HUEDevice}{defptr}{$code}) );
      $ret .= sprintf( "%2i  %-25s %-15s %-25s", $key, $result->{$key}{name}, $fhem_name, $result->{$key}{type} );
      $ret .= sprintf( "capabilities: %s", encode_json($result->{$key}{capabilities}) ) if( $arg && $arg eq 'detail' && defined($result->{$key}{capabilities}) );
      $ret .= sprintf( "\n%2s  %-25s %-15s %-25s      config: %s", "", "", "", "", encode_json($result->{$key}{config}) ) if( $arg && $arg eq 'detail' && defined($result->{$key}{config}) );
      $ret .= sprintf( "\n%2s  %-25s %-15s %-25s       state: %s", "", "", "", "", encode_json($result->{$key}{state}) ) if( $arg && $arg eq 'detail' && defined($result->{$key}{state}) );
      $ret .= "\n";
    }
    if( $arg && $arg eq 'detail' ) {
      $ret = sprintf( "%2s  %-25s %-15s %-25s %s\n", "ID", "NAME", "FHEM", "TYPE", "DETAIL" ) .$ret if( $ret );
    } else {
      $ret = sprintf( "%2s  %-25s %-15s %-25s\n", "ID", "NAME", "FHEM", "TYPE" ) .$ret if( $ret );
    }
    return $ret;

  } elsif($cmd eq 'groups') {
    my $result =  HUEBridge_Call($hash, undef, 'groups', undef);
    return $result->{error}{description} if( $result->{error} );
    $result->{0} = { name => 'Lightset 0', type => 'LightGroup', lights => ["ALL"] };
    $hash->{helper}{groups} = $result;
    my $ret = "";
    foreach my $id ( sort {$a<=>$b} keys %{$result} ) {
      my $code = $name ."-G". $id;
      my $fhem_name;
         $fhem_name = $modules{HUEDevice}{defptr}{$code}->{NAME} if( defined($modules{HUEDevice}{defptr}{$code}) );
         $fhem_name = ' (ignored)' if( !$fhem_name && $hash->{helper}{ignored}{$code} );
         $fhem_name = '' if( !$fhem_name );
      $result->{$id}{type} = '' if( !defined($result->{$id}{type}) );     #deCONZ fix
      $result->{$id}{class} = '' if( !defined($result->{$id}{class}) );   #deCONZ fix
      $result->{$id}{lights} = [] if( !defined($result->{$id}{lights}) ); #deCONZ fix
      $ret .= sprintf( "%2i: %-15s %-15s %-15s %-15s", $id, $result->{$id}{name}, $fhem_name, $result->{$id}{type}, $result->{$id}{class} );
      if( !$arg && $hash->{helper}{lights} ) {
        $ret .= sprintf( " %s\n", join( ",", map { my $l = $hash->{helper}{lights}{$_}{name}; $l?$l:$_;} @{$result->{$id}{lights}} ) );
      } else {
        $ret .= sprintf( " %s\n", join( ",", @{$result->{$id}{lights}} ) );
      }
    }
    $ret = sprintf( "%2s  %-15s %-15s %-15s %-15s %s\n", "ID", "NAME", "FHEM", "TYPE", "CLASS", "LIGHTS" ) .$ret if( $ret );
    return $ret;

  } elsif($cmd eq 'scenes') {
    my $result =  HUEBridge_Call($hash, undef, 'scenes', undef);
    return $result->{error}{description} if( $result->{error} );
    $hash->{helper}{scenes} = $result;
    my $ret = "";
    foreach my $key ( sort {$result->{$a}{name} cmp $result->{$b}{name}} keys %{$result} ) {
      $ret .= sprintf( "%-20s %-25s %-10s", $key, $result->{$key}{name}, $result->{$key}{type} );
      $ret .= sprintf( " %i %i %i %-40s %-20s", $result->{$key}{recycle}, $result->{$key}{locked},$result->{$key}{version}, $result->{$key}{owner}, $result->{$key}{lastupdated}?$result->{$key}{lastupdated}:'' ) if( $arg && $arg eq 'detail' );
      my $lights = "";
      $lights = join( ",", @{$result->{$key}{lights}} ) if( $result->{$key}{lights} );
      my $group = HUEbridge_groupOfLights($hash,$lights);

      if( !$arg && $group ) {
        $ret .= sprintf( " %s\n", $group );

      } elsif( !$arg && $hash->{helper}{lights} ) {
        $ret .= sprintf( " %s\n", join( ",", map { my $l = $hash->{helper}{lights}{$_}{name}; $l?$l:$_;} @{$result->{$key}{lights}} ) );
      } else {
        $ret .= sprintf( " %s\n", $lights );
      }
    }
    if( $ret ) {
      my $header = sprintf( "%-20s %-25s %-10s", "ID", "NAME", "TYPE" );
      $header .= sprintf( " %s %s %s %-40s %-20s", "R", "L", "V", "OWNER", "LAST UPDATE" ) if( $arg && $arg eq 'detail' );
      $header .= sprintf( " %s\n", "LIGHTS" );
      $ret = $header . $ret;
    }
    return $ret;

  } elsif($cmd eq 'rule') {
    return "usage: rule <id>" if( @args != 1 );
    return "$arg is not a hue rule number" if( $arg !~ m/^\d+$/ );

    my $result =  HUEBridge_Call($hash, undef, "rules/$arg", undef);
    return $result->{error}{description} if( $result->{error} );
    my $ret = encode_json($result->{conditions}) ."\n". encode_json($result->{actions});
    return $ret;

  } elsif($cmd eq 'rules') {
    my $result =  HUEBridge_Call($hash, undef, 'rules', undef);
    return $result->{error}{description} if( $result->{error} );

    my $ret = "";
    foreach my $key ( sort {$a<=>$b} keys %{$result} ) {
      $ret .= sprintf( "%2i: %-20s", $key, $result->{$key}{name} );
      $ret .= sprintf( " %s", encode_json($result->{$key}{conditions}) ) if( $arg && $arg eq 'detail' );
      $ret .= sprintf( "\n%-24s %s", "", encode_json($result->{$key}{actions}) ) if( $arg && $arg eq 'detail' );
      $ret .= "\n";
    }
    if( $arg && $arg eq 'detail' ) {
      $ret = sprintf( "%2s  %-20s %s\n", "ID", "NAME", "CONDITIONS/ACTIONS" ) .$ret if( $ret );
    } else {
      $ret = sprintf( "%2s  %-20s\n", "ID", "NAME" ) .$ret if( $ret );
    }
    return $ret;
  } elsif($cmd eq 'schedules') {
    my $result =  HUEBridge_Call($hash, undef, 'schedules', undef);
    return $result->{error}{description} if( $result->{error} );

    # 064:MO
    # 032:DI
    # 016:MI
    # 008:DO
    # 004:FR
    # 002:SA
    # 001:SO
    my $ret = "";
    foreach my $key ( sort {$a<=>$b} keys %{$result} ) {
      $ret .= sprintf( "%2i: %-20s %-12s", $key, $result->{$key}{name},$result->{$key}{status} );
      $ret .= sprintf( "%s", $result->{$key}{localtime} ) if( $arg && $arg eq 'detail' );

      $ret .= "\n";
    }
    if( $arg && $arg eq 'detail' ) {
      $ret = sprintf( "%2s  %-20s %-11s %s\n", "ID", "NAME", "STATUS", "TIME" ) .$ret if( $ret );
    } else {
      $ret = sprintf( "%2s  %-20s %-12s\n", "ID", "NAME", "STATUS" ) .$ret if( $ret );
    }
    return $ret;

  } elsif($cmd eq 'sensors') {
    my $result =  HUEBridge_Call($hash, undef, 'sensors', undef);
    return $result->{error}{description} if( $result->{error} );
    my $ret = "";
    foreach my $key ( sort {$a<=>$b} keys %{$result} ) {
      my $code = $name ."-S". $key;
      my $fhem_name = '';
         $fhem_name = $modules{HUEDevice}{defptr}{$code}->{NAME} if( defined($modules{HUEDevice}{defptr}{$code}) );
         $fhem_name = ' (ignored)' if( !$fhem_name && $hash->{helper}{ignored}{$code} );
      $fhem_name = "" if( !$fhem_name );
      $ret .= sprintf( "%2i: %-20s %-15s %-20s", $key, $result->{$key}{name}, $fhem_name, $result->{$key}{type} );
      $ret .= sprintf( "\n%-56s %s", '', encode_json($result->{$key}{state}) ) if( $arg && $arg eq 'detail' );
      $ret .= sprintf( "\n%-56s %s", '', encode_json($result->{$key}{config}) ) if( $arg && $arg eq 'detail' );
      $ret .= sprintf( "\n%-56s %s", '', encode_json($result->{$key}{capabilities}) ) if( $arg && $arg eq 'detail' && defined($result->{$key}{capabilities}) );
      $ret .= "\n";
    }
    if( $arg && $arg eq 'detail' ) {
      $ret = sprintf( "%2s  %-20s %-15s %-20s %s\n", "ID", "NAME", "FHEM", "TYPE", "STATE,CONFIG,CAPABILITIES" ) .$ret if( $ret );
    } else {
      $ret = sprintf( "%2s  %-20s %-15s %-20s\n", "ID", "NAME", "FHEM", "TYPE" ) .$ret if( $ret );
    }
    return $ret;

  } elsif($cmd eq 'whitelist') {
    my $result =  HUEBridge_Call($hash, undef, 'config', undef);
    return $result->{error}{description} if( $result->{error} );
    my $ret = "";
    my $whitelist = $result->{whitelist};
    foreach my $key ( sort {$whitelist->{$a}{'last use date'} cmp $whitelist->{$b}{'last use date'}} keys %{$whitelist} ) {
      $ret .= sprintf( "%-20s %-20s %-30s %s\n", $whitelist->{$key}{'create date'}, , $whitelist->{$key}{'last use date'}, $whitelist->{$key}{name}, $key );
    }
    $ret = sprintf( "%-20s %-20s %-30s %s\n", "CREATE", "LAST USE", "NAME", "KEY" ) .$ret if( $ret );
    return $ret;

  } elsif($cmd eq 'startup' ) {
    my $result =  HUEBridge_Call($hash, undef, 'lights', undef);
    return $result->{error}{description} if( $result->{error} );
    my $ret = "";
    foreach my $key ( sort {$a<=>$b} keys %{$result} ) {
      my $code = $name ."-". $key;
      my $fhem_name = '';
      $fhem_name = $modules{HUEDevice}{defptr}{$code}->{NAME} if( defined($modules{HUEDevice}{defptr}{$code}) );
      $ret .= sprintf( "%2i: %-25s %-15s ", $key, $result->{$key}{name}, $fhem_name );
      if( !$result->{$key}{config} || !$result->{$key}{config}{startup} ) {
        $ret .= "not supported";
      } else {
        $ret .= sprintf( "%s\t%s", $result->{$key}{config}{startup}{mode}, $result->{$key}{config}{startup}{configured} );
      }
      $ret .= "\n";
    }
    $ret = sprintf( "%2s  %-25s %-15s %s\t%s\n", "ID", "NAME", "FHEM", "MODE", "CONFIGURED" ) .$ret if( $ret );
    return $ret;

  } elsif($cmd eq 'ignored' ) {
    return join( "\n", sort keys %{$hash->{helper}{ignored}} );

  } elsif($cmd eq 'v2resourcetypes' ) {
    return "$name: v2 api not supported" if( !$hash->{has_v2_api} );
    my %result;
    foreach my $entry ( values %{$hash->{helper}{resource}{by_id}} ) {
      next if( $arg && $arg ne $entry->{type} );
      $result{$entry->{id}} = 1 if( $arg );
      $result{$entry->{type}} = 1 if( !$arg );
    }
    return join( "\n", keys %result );

  } elsif($cmd eq 'v2resource' ) {
    return "$name: v2 api not supported" if( !$hash->{has_v2_api} );
    if( $arg ) {
      my $ret;
      foreach my $entry ( values %{$hash->{helper}{resource}{by_id}} ) {
        $ret .= Dumper $entry if( $entry->{id_v1} && $entry->{id_v1} =~ /$arg$/ );
      }
      foreach my $entry ( values %{$hash->{helper}{resource}{by_id}} ) {
        $ret .= Dumper $entry if( $entry->{type} && $entry->{type} eq $arg );
      }
      return $ret if( $ret );

      return Dumper $hash->{helper}{resource}{by_id}{$arg};
    }
    return Dumper $hash->{helper}{resource};

  } elsif($cmd eq 'v2devices' ) {
    return "$name: v2 api not supported" if( !$hash->{has_v2_api} );
    return "usage: $cmd [lights|sensors]" if( $arg && $arg eq '?' );

    my $ret;
    foreach my $entry ( values %{$hash->{helper}{resource}{by_id}} ) {
      next if( $entry->{type} ne 'device' );
      my(undef, $t, $id) = split( '/', $entry->{id_v1} );
      next if( $arg && $arg ne $t );
      my $code = $name ."-". $id;
      my $fhem_name = '';
         $fhem_name = $modules{HUEDevice}{defptr}{$code}->{NAME} if( defined($modules{HUEDevice}{defptr}{$code}) );
      $ret .= sprintf( "%-36s %-2s %-15s %s", $entry->{id}, $id, $fhem_name, $entry->{metadata}{name} );
      $ret .= "\n";

      foreach my $service ( sort {$a->{rtype} cmp $b->{rtype}} @{$entry->{services}} ) {
        $ret .= sprintf( "     %-36s %s", $service->{rid}, $service->{rtype} );
        $ret .= "\n";
      }
      $ret .= "\n";
    }
    $ret = sprintf( "%-36s %-2s %-15s %s\n", "ID", "V1", "FEHM", "NAME", ).
            sprintf( "     %-36s %s\n","ID", "TYPE" ).$ret if( $ret );
    return $ret;

  } elsif($cmd eq 'v2scenes' ) {
    return "$name: v2 api not supported" if( !$hash->{has_v2_api} );
    my $ret;
    foreach my $entry ( sort {$a->{group}{rid} cmp $b->{group}{rid}} values %{$hash->{helper}{resource}{by_id}} ) {
      next if( $entry->{type} ne 'scene' );
      my $room = HUEBridge_GetResource($hash,$entry->{group}{rid});
      my(undef, $t, $id) = split( '/', $room->{id_v1} );
      my $code = $name ."-G". $id;
      my $fhem_name;
         $fhem_name = $modules{HUEDevice}{defptr}{$code}->{NAME} if( defined($modules{HUEDevice}{defptr}{$code}) );
         $fhem_name = ' (ignored)' if( !$fhem_name && $hash->{helper}{ignored}{$code} );
         $fhem_name = '' if( !$fhem_name );
      $ret .= sprintf( "%-36s %-25s %s (%s", $entry->{id}, $entry->{metadata}{name}, HUEBridge_nameOfResource($hash,$entry->{group}{rid}), $fhem_name );
      if( $arg && $entry->{actions}) {
        $ret .= sprintf( ": %s\n", join( ",", map { my $l = HUEBridge_nameOfResource($hash,$_->{target}{rid}); $l?$l:$_;} @{$entry->{actions}} ) );
      }
      $ret .= ")\n";
    }
    $ret = sprintf( "%-36s %-21s %s\n", "ID", "NAME", "for GROUP" ) .$ret if( $ret );
    return $ret;

  } elsif($cmd eq 'v2effects' ) {
    return "$name: v2 api not supported" if( !$hash->{has_v2_api} );
    return "usage: $cmd [<v2 light id>]" if( $arg && $arg eq '?' );
    my $ret;
    foreach my $entry ( values %{$hash->{helper}{resource}{by_id}} ) {
      next if( !$entry->{effects} );
      next if( $arg && $arg ne $entry->{id} );
      my(undef, $t, $id) = split( '/', $entry->{id_v1} );
      my $code = $name ."-". $id;
      my $fhem_name = '';
         $fhem_name = $modules{HUEDevice}{defptr}{$code}->{NAME} if( defined($modules{HUEDevice}{defptr}{$code}) );
      $ret .= sprintf( "%-36s %-2s %-15s %s:", $entry->{id}, $id, $fhem_name, $entry->{metadata}{name} ) if( $hash->{CL} );
      $ret .= join( ',', @{$entry->{effects}{effect_values}} );
      $ret .= "\n" if( $hash->{CL} );
    }
    $ret = sprintf( "%-36s %-2s %-15s %s\n", "ID", "V1", "FEHM", "NAME", ). $ret if( $ret && $hash->{CL} );
    return $ret;

  } else {
    my $list = "lights:noArg groups:noArg scenes:noArg rule rules:noArg sensors:noArg schedules:noArg whitelist:noArg";
    if( $hash->{helper}{apiversion} && $hash->{helper}{apiversion} >= (1<<16) + (26<<8) ) {
      $list .= " startup:noArg";
    }

    if( $hash->{has_v2_api} ) {
      $list .= " v2devices v2effects v2resource v2resourcetypes v2scenes";
    }

    return "Unknown argument $cmd, choose one of $list";
  }
}

sub
HUEBridge_GetUpdate($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if(!$hash->{LOCAL}) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "HUEBridge_GetUpdate", $hash, 0);
  }

  if( $hash->{websocketport} && !$hash->{PORT} ) {
    HUEBridge_openWebsocket($hash);

  } elsif( $hash->{has_v2_api} ) {
    HUEBridge_openEventStream($hash) if( !defined($hash->{helper}{HTTP_CONNECTION}) );

  }

  my $type;
  my $result;
  my $poll_devices = AttrVal($name, "pollDevices", 2);
  if( $poll_devices ) {
    my ($now) = gettimeofday();
    if( $poll_devices > 1 || $hash->{LOCAL} || !$hash->{helper}{last_config_timestamp}
                                            || $now - $hash->{helper}{last_config_timestamp} > 300 ) {
      $result = HUEBridge_Call($hash, $hash, undef, undef);
      $hash->{helper}{last_config_timestamp} = $now;

    } else {
      $type = 'lights';
      $result = HUEBridge_Call($hash, $hash, 'lights', undef);

    }

  } else {
    $type = 'config';
    $result = HUEBridge_Call($hash, $hash, 'config', undef);
  }

  return undef if( !defined($result) );

  HUEBridge_dispatch( {hash=>$hash,chash=>$hash,type=>$type}, undef, undef, $result );

  #HUEBridge_Parse($hash, $result);

  return undef;
}

my %dim_values = (
   0 => "dim06%",
   1 => "dim12%",
   2 => "dim18%",
   3 => "dim25%",
   4 => "dim31%",
   5 => "dim37%",
   6 => "dim43%",
   7 => "dim50%",
   8 => "dim56%",
   9 => "dim62%",
  10 => "dim68%",
  11 => "dim75%",
  12 => "dim81%",
  13 => "dim87%",
  14 => "dim93%",
);
sub
HUEBridge_updateGroups($$)
{
  my($hash,$lights) = @_;
  my $name = $hash->{NAME};
  my $createGroupReadings = AttrVal($hash->{NAME},"createGroupReadings",undef);
  return if( !defined($createGroupReadings) );
  $createGroupReadings = ($createGroupReadings eq "1");

  my $groups = {};
  foreach my $light ( split(',', $lights) ) {
    foreach my $chash ( values %{$modules{HUEDevice}{defptr}} ) {
      next if( !$chash->{IODev} );
      next if( !$chash->{lights} );
      next if( $chash->{IODev}{NAME} ne $name );
      next if( $chash->{helper}{devtype} ne 'G' );
      next if( ",$chash->{lights}," !~ m/,$light,/ );
      next if( $createGroupReadings && !AttrVal($chash->{NAME},"createGroupReadings", 1) );
      next if( !$createGroupReadings && !AttrVal($chash->{NAME},"createGroupReadings", undef) );

      $groups->{$chash->{ID}} = $chash;
    }
  }

  foreach my $chash ( values %{$groups} ) {
    my $count = 0;
    my %readings;
      $readings{all_on} = 1;
      $readings{any_on} = 0;
    my ($hue,$sat,$bri);
    foreach my $light ( split(',', $chash->{lights}) ) {
      next if( !$light );
      next if( !defined($modules{HUEDevice}{defptr}{"$name-$light"}) );
      my $lhash = $modules{HUEDevice}{defptr}{"$name-$light"};
      my $current = $lhash->{helper};
      next if( !$current );
      #next if( !$current->{on} );
      next if( $current->{helper}{devtype} );

      my( $h, $s, $v );

      if( $current->{on} && $current->{colormode} && $current->{colormode} eq 'hs' ) {
        $h = $current->{hue} / 65535;
        $s = $current->{sat} / 254;
        $v = $current->{bri} / 254;

      } elsif( $current->{on} && $current->{rgb} &&  $current->{rgb}  =~ m/^(..)(..)(..)/ ) {
        my( $r, $g, $b ) = (hex($1)/255.0, hex($2)/255.0, hex($3)/255.0);
        ( $h, $s, $v ) = Color::rgb2hsv($r,$g,$b);

        $s = 0 if( !defined($s) );
      }


      if( defined($h) ) {
        #Log 1, ">>> $h $s $v";
        if( defined($hue) ) {
           my $a = $hue < $h ? $hue : $h;
           my $b = $hue < $h ? $h : $hue;

           my $d1 = $b-$a;
           my $d2 = $a+1-$b;

           if( $d1 < $d2 ) {
             $hue = $a + $d1 / 2;
           } else {
              $hue = $b + $d2 / 2;
           }

           $sat += $s;
           $bri += $v;

        } else {
          $hue = $h;
          $sat = $s;
          $bri = $v;

        }
      }

      $readings{ct} += $current->{ct} if( $current->{ct} );
      $readings{bri} += $current->{bri} if( defined($current->{bri}) );
      $readings{pct} += $current->{pct} if( defined($current->{pct}) );
      $readings{sat} += $current->{sat} if( defined($current->{sat}) );

      $readings{on} |= ($current->{on}?'1':'0');

      $readings{all_on} = 0 if( !($current->{on}?'1':'0') );
      $readings{any_on} |=  ($current->{on}?'1':'0');

      if( AttrVal($lhash->{NAME}, 'ignoreReachable', 0) ) {
        $readings{reachable} |= 1;
      } else {
        $readings{reachable} |= ($current->{reachable}?'1':'0');
      }

      if( !defined($readings{alert}) ) {
        $readings{alert} = $current->{alert};
      } elsif( $current->{alert} && $readings{alert} ne $current->{alert} ) {
        $readings{alert} = 'nonuniform';
      }
      if( !defined($readings{colormode}) ) {
        $readings{colormode} = $current->{colormode};
      } elsif( $current->{colormode} && $readings{colormode} ne $current->{colormode} ) {
        $readings{colormode} = "nonuniform";
      }
      if( !defined($readings{effect}) ) {
        $readings{effect} = $current->{effect};
      } elsif( $current->{effect} && $readings{effect} ne $current->{effect} ) {
        $readings{effect} = "nonuniform";
      }

      ++$count;
    }

    $readings{all_on} = 0 if( !$count );

    if( AttrVal($name, 'ignoreReachable', 0) ) {
      delete $readings{reachable};
    }

    if( defined($hue) && $readings{colormode} && $readings{colormode} ne "ct" ) {
      #Log 1, "$hue $sat $bri";
      $readings{colormode} = 'hs';
      $readings{hue} = int($hue * 65535);
      $readings{sat} = int($sat * 254 / $count + 0.5);

      $readings{bri} = int($bri * 254 / $count + 0.5);
      $readings{pct} = int($bri * 100 / $count + 0.5);

    } else {
      foreach my $key ( qw( ct bri pct sat ) ) {
        $readings{$key} = int($readings{$key} / $count + 0.5) if( defined($readings{$key}) );
      }
    }

    if( defined($hue) ) {
      $hue -= 1 if( $hue >= 1 );
      my ($r,$g,$b) = Color::hsv2rgb($hue,$sat/$count,$bri/$count);

      $r *= 255;
      $g *= 255;
      $b *= 255;

      $readings{rgb} = sprintf( "%02x%02x%02x", $r+0.5, $g+0.5, $b+0.5 )
    }

    if( $readings{on} ) {
      if( $readings{pct} > 0
          && $readings{pct} < 100  ) {
        $readings{state} = $dim_values{int($readings{pct}/7)};
      }
      $readings{state} = 'off' if( $readings{pct} == 0 );
      $readings{state} = 'on' if( $readings{pct} == 100 );

    } else {
      $readings{pct} = 0;
      $readings{state} = 'off';
    }
    $readings{onoff} =  $readings{on};
    delete $readings{on};

    readingsBeginUpdate($chash);
      foreach my $key ( keys %readings ) {
        if( defined($readings{$key}) ) {
          readingsBulkUpdate($chash, $key, $readings{$key}, 1) if( !defined($chash->{helper}{$key}) || $chash->{helper}{$key} ne $readings{$key} );
          $chash->{helper}{$key} = $readings{$key};
        }
      }
    readingsEndUpdate($chash,1);
  }

}

sub
HUEBridge_Parse($$)
{
  my($hash,$config) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: parse status message";
  #Log3 $name, 5, Dumper $config;

  $hash->{helper}{lights} = $config->{lights} if( $config->{lights} );
  $hash->{helper}{groups} = $config->{groups} if( $config->{groups} );
  $hash->{helper}{scenes} = $config->{scenes} if( $config->{scenes} );

  #Log 3, Dumper $config;
  $config = $config->{config} if( defined($config->{config}) );
  HUEBridge_fillBridgeInfo($hash, $config);

  if( my $utc = $config->{UTC} ) {
    substr( $utc, 10, 1, '_' );

    if( my $localtime = $config->{localtime} ) {
      $localtime = TimeNow() if( $localtime eq 'none' );
      substr( $localtime, 10, 1, '_' );

      $hash->{helper}{offsetUTC} = SVG_time_to_sec($localtime) - SVG_time_to_sec($utc);

    } else {
      Log3 $name, 2, "$name: missing localtime configuration";

    }
  }

  if( defined( $config->{swupdate} ) ) {
    my $txt = $config->{swupdate}->{text};
    readingsSingleUpdate($hash, "swupdate", $txt, 1) if( $txt && $txt ne ReadingsVal($name,"swupdate","") );
    if( defined($hash->{updatestate}) ){
      readingsSingleUpdate($hash, 'state', 'update done', 1 ) if( $config->{swupdate}->{updatestate} == 0 &&  $hash->{helper}{updatestate} >= 2 );
      readingsSingleUpdate($hash, 'state', 'update failed', 1 ) if( $config->{swupdate}->{updatestate} == 2 &&  $hash->{helper}{updatestate} == 3 );
    }

    $hash->{updatestate} = $config->{swupdate}->{updatestate};
    $hash->{helper}{updatestate} = $hash->{updatestate};
    if( $config->{swupdate}->{devicetypes} ) {
      my $devicetypes;
      $devicetypes .= 'bridge' if( $config->{swupdate}->{devicetypes}->{bridge} );
      $devicetypes .= ',' if( $devicetypes && scalar(@{$config->{swupdate}->{devicetypes}->{lights}}) );
      $devicetypes .= join( ",", @{$config->{swupdate}->{devicetypes}->{lights}} ) if( $config->{swupdate}->{devicetypes}->{lights} );

      $hash->{updatestate} .= " [$devicetypes]" if( $devicetypes );
    }

  } elsif ( defined(  $hash->{swupdate} ) ) {
    delete( $hash->{updatestate} );
    delete( $hash->{helper}{updatestate} );
  }

  #update state timestamp
  readingsSingleUpdate($hash, 'state', $hash->{READINGS}{state}{VAL}, 0);
}

sub
HUEBridge_Autocreate($;$$)
{
  my ($hash,$force,$sensors)= @_;
  my $name = $hash->{NAME};
     $force = AttrVal($name, 'forceAutocreate', $force);

  if( !$force ) {
    my $type = $hash->{TYPE};

    foreach my $d (keys %defs) {
      next if($defs{$d}{TYPE} ne 'autocreate');

      if(AttrVal($defs{$d}{NAME},'disable',undef)) {
        Log3 $name, 2, "$name: autocreate is disabled, please enable it at least for $type. see: ignoreTypes" if( !AttrVal($name, 'ignoreUnknown', undef) );
        return undef;

      } elsif( my $it = AttrVal($name, 'ignoreTypes', '') ) {
        if($it && $name =~ m/$it/i) {
          Log3 $name, 2, "$name: autocreate is disabled for $type, please enable" if( !AttrVal($name, 'ignoreUnknown', undef) );
          return undef;

        } elsif($it && "$type:$name" =~ m/$it/i) {
          Log3 $name, 2, "$name: autocreate is disabled for this bridge, please enable" if( !AttrVal($name, 'ignoreUnknown', undef) );
          return undef;
        }

      }
    }
  }

  my @ignored = (0, 0, 0);
  my @created = (0, 0, 0);
  my $result =  HUEBridge_Call($hash,undef, 'lights', undef);
  foreach my $id ( sort {$a<=>$b} keys %{$result} ) {
    my $code = $name ."-". $id;
    if( defined($modules{HUEDevice}{defptr}{$code}) ) {
      Log3 $name, 5, "$name: id '$id' already defined as '$modules{HUEDevice}{defptr}{$code}->{NAME}'";
      next;
    }

    my $devname = "HUEDevice" . $id;
    $devname = $name ."_". $devname if( $hash->{helper}{count} );
    my $define = "$devname HUEDevice $id IODev=$name";

    Log3 $name, 4, "$name: create new device '$devname' for address '$id'";

    my $cmdret = CommandDefine(undef,$define);
    if($cmdret) {
      Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$id': $cmdret";

    } else {
      $cmdret .= CommandAttr(undef,"$devname IODev $name");
      $cmdret .= CommandAttr(undef,"$devname group HUEDevice");
      $cmdret .= CommandAttr(undef,"$devname alias ". $result->{$id}{name});
      $cmdret .= CommandAttr(undef,"$devname room ". AttrVal( $name, 'room', 'HUEDevice') );

      HUEDeviceSetIcon($devname);
      $defs{$devname}{helper}{fromAutocreate} = 1 ;

      $created[0]++;
    }
  }

  $result =  HUEBridge_Call($hash,undef, 'groups', undef);
  $result->{0} = { name => "Lightset 0", type => 'LightGroup' };
  foreach my $id ( sort {$a<=>$b} keys %{$result} ) {
    my $code = $name ."-G". $id;
    if( defined($modules{HUEDevice}{defptr}{$code}) ) {
      Log3 $name, 5, "$name: id '$id' already defined as '$modules{HUEDevice}{defptr}{$code}->{NAME}'";
      next;
    }

    if( $result->{$id}{recycle}
        || $result->{$id}{type} eq 'Entertainment' ) {
      Log3 $name, 4, "$name: ignoring group $id ($result->{$id}{name}) of type $result->{$id}{type} in autocreate";
      $ignored[1]++;
      $hash->{helper}{ignored}{$code} = 1;
      next;
    }

    my $devname = "HUEGroup" . $id;
    $devname = $name ."_". $devname if( $hash->{helper}{count} );
    my $define = "$devname HUEDevice group $id IODev=$name";

    Log3 $name, 4, "$name: create new group '$devname' for address '$id'";

    my $cmdret = CommandDefine(undef,$define);
    if($cmdret) {
      Log3 $name, 1, "$name: Autocreate: An error occurred while creating group for id '$id': $cmdret";

    } else {
      $cmdret .= CommandAttr(undef,"$devname IODev $name");
      $cmdret .= CommandAttr(undef,"$devname group HUEGroup");
      $cmdret .= CommandAttr(undef,"$devname alias ". $result->{$id}{name});
      $cmdret .= CommandAttr(undef,"$devname room ". AttrVal( $name, 'room', 'HUEDevice') );

      HUEDeviceSetIcon($devname);
      $defs{$devname}{helper}{fromAutocreate} = 1 ;

      $created[1]++;
    }
  }

  if( $sensors || $hash->{websocket} || $hash->{has_v2_api} ) {
    $result =  HUEBridge_Call($hash,undef, 'sensors', undef);
    foreach my $id ( sort {$a<=>$b} keys %{$result} ) {
      my $code = $name ."-S". $id;
      if( defined($modules{HUEDevice}{defptr}{$code}) ) {
        Log3 $name, 5, "$name: id '$id' already defined as '$modules{HUEDevice}{defptr}{$code}->{NAME}'";
        next;
      }

      if( $result->{$id}{recycle}
          || $result->{$id}{type} eq 'CLIPGenericStatus' ) {
        Log3 $name, 4, "$name: ignoring sensor $id ($result->{$id}{name}) of type $result->{$id}{type} in autocreate";
        $ignored[2]++;
        $hash->{helper}{ignored}{$code} = 1;
        next;
      }

      my $devname = "HUESensor" . $id;
      $devname = $name ."_". $devname if( $hash->{helper}{count} );
      my $define = "$devname HUEDevice sensor $id IODev=$name";

      Log3 $name, 4, "$name: create new sensor '$devname' for address '$id'";

      my $cmdret = CommandDefine(undef,$define);
      if($cmdret) {
        Log3 $name, 1, "$name: Autocreate: An error occurred while creating sensor for id '$id': $cmdret";

      } else {
        $cmdret .= CommandAttr(undef,"$devname IODev $name");
        $cmdret .= CommandAttr(undef,"$devname group HUESensor");
        $cmdret .= CommandAttr(undef,"$devname alias ".$result->{$id}{name});
        $cmdret .= CommandAttr(undef,"$devname room ". AttrVal( $name, 'room', 'HUEDevice') );

        HUEDeviceSetIcon($devname);
        $defs{$devname}{helper}{fromAutocreate} = 1 ;

        $created[2]++;
      }
    }
  }

  local *sum = sub { my $sum = 0; $sum += $_ for @_;  return $sum };

  my $created = join( '/', @created );
  my $ignored = join( '/', @ignored );
  if( !$force || sum(@created) || sum(@ignored) ) {
    Log3 $name, 2, "$name: autocreate: created $created devices (ignored $ignored)";
    CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );
  }

  return "created $created devices (ignored $ignored)";
}

sub
HUEBridge_ProcessResponse($$)
{
  my ($hash,$obj) = @_;
  my $name = $hash->{NAME};

  #Log3 $name, 3, ref($obj);
  #Log3 $name, 3, "Receiving: " . Dumper $obj;

  if( ref($obj) eq 'ARRAY' ) {
    if( defined($obj->[0]->{error})) {
      my $error = $obj->[0]->{error}->{'description'};

      readingsSingleUpdate($hash, 'lastError', $error, 1 );
    }

    if( !AttrVal( $name,'queryAfterSet', 1 ) ) {
      my $successes;
      my $errors;
      my %json = ();
      foreach my $item (@{$obj}) {
        if( my $success = $item->{success} ) {
          next if( ref($success) ne 'HASH' );
          foreach my $key ( keys %{$success} ) {
            my @l = split( '/', $key );
            next if( !$l[1] );
            if( $l[1] eq 'lights' && $l[3] eq 'state' ) {
              $json{$l[2]}->{state}->{$l[4]} = $success->{$key};
              $successes++;

            } elsif( $l[1] eq 'groups' && $l[3] eq 'action' ) {
              my $code = $name ."-G". $l[2];
              if( my $chash = $modules{HUEDevice}{defptr}{$code} ) {
                if( my $lights = $chash->{lights} ) {
                  foreach my $light ( split(',', $lights) ) {
                    $json{$light}->{state}->{$l[4]} = $success->{$key};
                    $successes++;
                  }
                }
              }
            }
          }

        } elsif( my $error = $item->{error} ) {
          my $msg = $error->{'description'};
          Log3 $name, 3, $msg;
          $errors++;
        }
      }

      my $changed = "";
      foreach my $id ( keys %json ) {
        my $code = $name ."-". $id;
        if( my $chash = $modules{HUEDevice}{defptr}{$code} ) {
          #$json{$id}->{state}->{reachable} = 1;
          if( HUEDevice_Parse( $chash, $json{$id} ) ) {
            $changed .= "," if( $changed );
            $changed .= $chash->{ID};
          }
        }
      }
      HUEBridge_updateGroups($hash, $changed) if( $changed );
    }

    #return undef if( !$errors && $successes );

    return ($obj->[0]);
  } elsif( ref($obj) eq 'HASH' ) {
    return $obj;
  }

  return undef;
}

sub
HUEBridge_Register($)
{
  my ($hash) = @_;

  my $obj = {
    'devicetype' => 'fhem',
  };

  if( !$hash->{helper}{apiversion} || $hash->{helper}{apiversion} < (1<<16) + (12<<8) ) {
    $obj->{username} = AttrVal($hash->{NAME}, 'key', '');
  }

  return HUEBridge_Call($hash, undef, undef, $obj);
}

#Executes a JSON RPC
sub
HUEBridge_Call($$$$;$)
{
  my ($hash,$chash,$path,$obj,$method) = @_;
  my $name = $hash->{NAME};

  if( IsDisabled($name) ) {
    readingsSingleUpdate($hash, 'state', 'inactive', 1 ) if( ReadingsVal($name,'state','' ) ne 'inactive' );
    return undef;
  }

  #Log3 $hash->{NAME}, 5, "Sending: " . Dumper $obj;

  my $json = undef;
  $json = encode_json($obj) if $obj;

  # @TODO: repeat twice?
  for( my $attempt=0; $attempt<2; $attempt++ ) {
    my $blocking;
    my $res = undef;
    if( !defined($attr{$name}{httpUtils}) ) {
      $blocking = 1;
      $res = HUEBridge_HTTP_Call($hash,$path,$json,$method);
    } else {
      $blocking = $attr{$name}{httpUtils} < 1;
      $res = HUEBridge_HTTP_Call2($hash,$chash,$path,$json,$method);
    }

    return $res if( !$blocking || defined($res) );

    Log3 $name, 3, "HUEBridge_Call: failed, retrying";
    HUEBridge_Detect($hash) if( defined($hash->{NUPNP}) );
  }

  Log3 $name, 3, "HUEBridge_Call: failed";
  return undef;
}

#JSON RPC over HTTP
sub
HUEBridge_HTTP_Call($$$;$)
{
  my ($hash,$path,$obj,$method) = @_;
  my $name = $hash->{NAME};

  #return { state => {reachable => 0 } } if($attr{$name} && $attr{$name}{disable});

  my $uri = "http://" . $hash->{host} . "/api";
  if( defined($obj) ) {
    $method = 'PUT' if( !$method );

    if( ReadingsVal($name, 'state', '') eq 'pairing' ) {
      $method = 'POST';
    } else {
      $uri .= "/" . AttrVal($name, "key", "");
    }
  } else {
    $uri .= "/" . AttrVal($name, "key", "");
  }
  $method = 'GET' if( !$method );
  if( defined $path) {
    $uri .= "/" . $path;
  }
  #Log3 $name, 3, "Url: " . $uri;
  Log3 $name, 4, "using HUEBridge_HTTP_Request: $method ". ($path?$path:'');
  my $ret = HUEBridge_HTTP_Request(0,$uri,$method,undef,$obj,AttrVal($name,'noshutdown', 1));
  #Log3 $name, 3, Dumper $ret;
  if( !defined($ret) ) {
    return undef;
  } elsif($ret eq '') {
    return undef;
  } elsif($ret =~ /^error:(\d){3}$/) {
    my $result = { error => "HTTP Error Code $1" };
    return $result;
  }

  if( !$ret ) {
    Log3 $name, 2, "$name: empty answer received for $uri";
    return undef;
  } elsif( $ret =~ m'HTTP/1.1 200 OK' ) {
    Log3 $name, 4, "$name: empty answer received for $uri";
    return undef;
  } elsif( $ret !~ m/^[\[{].*[\]}]$/ ) {
    Log3 $name, 2, "$name: invalid json detected for $uri: $ret";
    return undef;
  }

  my $decoded = eval { JSON->new->utf8(0)->decode($ret) };
  Log3 $name, 2, "$name: json error: $@ in $ret" if( $@ );

  return HUEBridge_ProcessResponse($hash, $decoded);
}

sub
HUEBridge_HTTP_Call2($$$$;$)
{
  my ($hash,$chash,$path,$obj,$method) = @_;
  my $name = $hash->{NAME};

  #return { state => {reachable => 0 } } if($attr{$name} && $attr{$name}{disable});

  my $url = "http://" . $hash->{host} . "/api";
  my $blocking = $attr{$name}{httpUtils} < 1;
  $blocking = 1 if( !defined($chash) );
  if( defined($obj) ) {
    $method = 'PUT' if( !$method );

    if( ReadingsVal($name, 'state', '') eq 'pairing' ) {
      $method = 'POST';
      $blocking = 1;
    } else {
      $url .= "/" . AttrVal($name, "key", "");
    }
  } else {
    $url .= "/" . AttrVal($name, "key", "");
  }
  $method = 'GET' if( !$method );

  if( defined $path) {
    $url .= "/" . $path;
  }
  #Log3 $name, 3, "Url: " . $url;

#Log 2, $path;
  if( $blocking ) {
    Log3 $name, 4, "using HttpUtils_BlockingGet: $method ". ($path?$path:'');

    my($err,$data) = HttpUtils_BlockingGet({
      url => $url,
      timeout => 4,
      method => $method,
      noshutdown => AttrVal($name,'noshutdown', 1),
      header => "Content-Type: application/json",
      data => $obj,
    });

    if( !$data ) {
      Log3 $name, 2, "$name: empty answer received for $url";
      return undef;
    } elsif( $data =~ m'HTTP/1.1 200 OK' ) {
      Log3 $name, 4, "$name: empty answer received for $url";
      return undef;
    } elsif( $data !~ m/^[\[{].*[\]}]$/ ) {
      Log3 $name, 2, "$name: invalid json detected for $url: $data";
      return undef;
    }

    my $json = eval { JSON->new->utf8(0)->decode($data) };
    Log3 $name, 2, "$name: json error: $@ in $data" if( $@ );
    return undef if( !$json );

    return HUEBridge_ProcessResponse($hash, $json);

    HUEBridge_dispatch( {hash=>$hash,chash=>$chash,type=>$path},$err,$data );

  } else {
    Log3 $name, 4, "using HttpUtils_NonblockingGet: $method ". ($path?$path:'');

    my($err,$data) = HttpUtils_NonblockingGet({
      url => $url,
      timeout => 10,
      method => $method,
      noshutdown => AttrVal($name,'noshutdown', 1),
      header => "Content-Type: application/json",
      data => $obj,
      hash => $hash,
      chash => $chash,
      type => $path,
      callback => \&HUEBridge_dispatch,
    });

    return undef;
  }
}

sub
HUEBridge_schedule($$;$)
{
  my ($hash,$fn,$delay) = @_;
     $delay = 5 if( !$delay );
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: scheduling $fn in $delay secs";

  RemoveInternalTimer($hash,$fn);
  InternalTimer(gettimeofday()+$delay, $fn, $hash, 0);
}
sub
HUEBridge_refreshv2resources($;$)
{
  my ($hash,$blocking) = @_;
  my $name = $hash->{NAME};

  return if( !$hash->{has_v2_api} );

  my $params = {
              url => "https://$hash->{host}/clip/v2/resource",
           method => 'GET',
          timeout => 5,
           header => { 'HUE-Application-Key' => $attr{$name}{key}, },
             type => 'resource',
             hash => $hash,
         callback => \&HUEBridge_dispatch,
     };

  if( $blocking ) {
    my($err,$data) = HttpUtils_BlockingGet( $params );

    HUEBridge_dispatch($params, $err, $data );

  } else {
    HttpUtils_NonblockingGet( $params );

  }
}

sub
HUEBridge_dispatch($$$;$)
{
  my ($param, $err, $data, $json) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: dispatch". ($param->{url}?": $param->{url}":"");
  Log3 $name, 5, "HUEBridge_dispatch". ($param->{type}?": $param->{type}":"");

  my $type = $param->{type};

  if( $err ) {
    Log3 $name, 2, "$name: http request failed: $err";

    if( $type && $type eq 'event' ) {
      if( defined($hash->{helper}{HTTP_CONNECTION}) && defined($hash->{helper}{HTTP_CONNECTION}{lastID}) ) {
        $hash->{EventStream} = 'terminated';
        Log3 $name, 2, "$name: EventStream: $hash->{EventStream}";
        HUEBridge_openEventStream( $hash );

      } else {
        $hash->{EventStream} = 'terminated; retrying later';
        Log3 $name, 2, "$name: EventStream: $hash->{EventStream}";

        RemoveInternalTimer($hash, "HUEBridge_openEventStream" );
        InternalTimer(gettimeofday()+2, "HUEBridge_openEventStream", $hash, 0);

      }
    }

    return undef;

  } elsif( defined($type) && $type eq 'resource' ) {
    $json = eval { JSON->new->utf8(0)->decode($data) };
    Log3 $name, 2, "$name: json error: $@ in $data" if( $@ );
    Log3 $name, 1, "$name: error: ". Dumper $json->{errors} if( scalar @{$json->{errors}} );

    my $current = $hash->{helper}{resource};
    delete $hash->{helper}{resource};
    return undef if( !$json );

    $hash->{helper}{resource} = $json;
    Log3 $name, 5, "$name: received: ". Dumper $json;

    my $count = 0;
    foreach my $item (@{$json->{data}}) {
      $hash->{helper}{resource}{by_id}{$item->{id}} = $item;

      $count++ if( $current && !$current->{by_id}{$item->{id}} );
    }
    Log3 $name, 4, "$name: found $count new resources";
    HUEBridge_Autocreate($hash) if( $count );

    foreach my $resource ( values %{$hash->{helper}{resource}{by_id}} ) {
      next if( !$resource->{type} );
      next if( !$resource->{id_v1} );
      if( $resource->{type} eq 'device' ) {
        my(undef, $t, $id) = split( '/', $resource->{id_v1} );
        my $code;
           $code = $name ."-". $id if( $t eq 'lights' );
           $code = $name ."-S". $id if( $t eq 'sensors' );
           $code = $name ."-G". $id if( $t eq 'groups' );
        next if( !$code );
        if( my $chash = $modules{HUEDevice}{defptr}{$code} ) {
          $chash->{v2_id} = $resource->{id};
        }
      }
    }

    return undef;

  } elsif( defined($type) && $type eq 'event' ) {
    if( $hash->{EventStream} && $hash->{EventStream} ne 'connected' ) {
      $hash->{EventStream} = 'connected';
      Log3 $name, 4, "$name: EventStream: $hash->{EventStream}";
    }

    if( defined(my $create = AttrVal($name,'createEventTimestampReading',undef )) ) {
      readingsSingleUpdate($hash, 'event', 'timestamp', $create ) if( defined($create) );
    }

    if( $hash->{INTERVAL} && $hash->{INTERVAL} < 60 ) {
      $hash->{INTERVAL} = 60;
      Log3 $name, 2, "$name: EventStream connected, changing interval to $hash->{INTERVAL}";
    }

    CommandDeleteAttr( undef, "$name pollDevices" ) if defined( AttrVal($name, 'pollDevices', undef) );

    #Log3 $name, 5, "$name: EventStream: got: $data";

    while($data =~ m/([^:]*):\s*(.+)(\r?\n)?(.*)/) {
      my $key = $1;
      my $value = $2;
      $data = $4;

      if( !$key ) {
        Log3 $name, 5, "$name: ignoring: $value";

        HUEBridge_refreshv2resources($hash);
        next;
      }

      if( $key eq 'id' ) {
        Log3 $name, 5, "$name: EventStream: got id: $value";
        $hash->{helper}{HTTP_CONNECTION}{lastID} = $value;

      } elsif( $key eq 'data' ) {
        Log3 $name, 5, "$name: EventStream: got data: $value";

        if( $value && $value !~ m/^[\[{].*[\]}]$/ ) {
          Log3 $name, 2, "$name: EventStream: invalid json detected: $value";
          return undef;
        }

        $json = eval { JSON->new->utf8(0)->decode($value) };
        Log3 $name, 2, "$name: EventStream: json error: $@ in $value" if( $@ );

        return undef if( !$json );
        Log3 $name, 5, "$name: EventStream: received: ". Dumper $json;

        my $changed = "";
        for my $event ( @{$json} ) {
          if( $event->{type} eq 'update' ) {
            Log3 $name, 4, "$name: EventStream: got $event->{type} event";

            for my $data ( @{$event->{data}} ) {
              Log3 $name, 4, "$name:              event part for resource type $data->{type}";

              my(undef, $t, $id) = split( '/', $data->{id_v1} );
              if( !defined($t) || !defined($id) ) {
                Log3 $name, 4, "$name: EventStream: ignoring event type $data->{type}";
                Log3 $name, 5, Dumper $data;
                next;
              }

              my $code;
              $code = $name ."-". $id if( $t eq 'lights' );
              $code = $name ."-S". $id if( $t eq 'sensors' );
              $code = $name ."-G". $id if( $t eq 'groups' );
              if( !$code ) {
                # handle events for scenes ?
                Log3 $name, 4, "$name: EventStream: ignoring event for $t";
                Log3 $name, 5, Dumper $data;
                next;
              }

              if( my $chash = $modules{HUEDevice}{defptr}{$code} ) {
                my $handled = 1;
                my $creationtime = substr($event->{creationtime},0,19);
                   #substr( $creationtime, 10, 1, '_' );
                   #$creationtime = FmtDateTime( SVG_time_to_sec($creationtime) + $hash->{helper}{offsetUTC}  ) if( defined($hash->{helper}{offsetUTC}) );
                   #substr( $creationtime, 10, 1, 'T' );
                my $obj = {      state => { lastupdated => $creationtime },
                                source =>  'event',
                                 v2_id => $data->{owner}{rid},
                            v2_service => $data->{id} };
                   $obj->{v2_id} = $obj->{v2_service} if( $t eq 'groups' );

                my $device = $hash->{helper}{resource}{by_id}{$obj->{v2_id}};
                if( !$device ) {
                  Log3 $name, 2, "$name: EventStream: event for unknown device received, trying to refresh resouces";
                  HUEBridge_refreshv2resources($hash, 1);
                  $device = $hash->{helper}{resource}{by_id}{$obj->{v2_id}};
                }
                my $service = $hash->{helper}{resource}{by_id}{$obj->{v2_service}};
                if( !$service ) {
                  Log3 $name, 2, "$name: EventStream: event for unknown service received, trying to refresh resouces";
                  HUEBridge_refreshv2resources($hash, 1);
                  $service = $hash->{helper}{resource}{by_id}{$obj->{v2_service}};
                }
#Log 1, Dumper $device;
#Log 1, Dumper $service;

                if( $data->{type} eq 'motion' ) {
                  $obj->{state}{presence} = $data->{motion}{motion} if( defined($data->{motion}) );

                } elsif( $data->{type} eq 'button' ) {
                  RemoveInternalTimer($chash, 'updateFinalButtonState' );

                  my $input = $service->{metadata}{control_id};
                  my $eventtype = $data->{button}{last_event};
#Log 1, "input: $input";
#Log 1, "eventtype: $eventtype";

                  my $buttonevent;
                  if( $input
                      && defined($chash->{helper}{events})
                      && defined($chash->{helper}{events}[$input-1])
                      && defined($chash->{helper}{events}[$input-1]{$eventtype}) ) {
                    $buttonevent = $chash->{helper}{events}[$input-1]{$eventtype};

                  } elsif( $eventtype eq 'initial_press' ) {
                    $buttonevent = "${input}000";

                  } elsif( $eventtype eq 'repeat' ) {
                    $buttonevent = "${input}001";

                  } elsif( $eventtype eq 'short_release' ) {
                    $buttonevent = "${input}002";

                  } elsif( $eventtype eq 'long_release' ) {
                    $buttonevent = "${input}003";
                  }

                  $obj->{state}{input} = $input;
                  $obj->{state}{eventtype} = $eventtype;
                  $obj->{state}{buttonevent} = $buttonevent;

                } elsif( $data->{type} eq 'relative_rotary' ) {
                  $obj->{eventtype} = $data->{type};

                  if( my $last_event = $data->{relative_rotary}{last_event} ) {
                    $obj->{state}{action} = $last_event->{action};

                    if( my $rotation = $last_event->{rotation} ) {
                      $obj->{state}{steps} = $rotation->{steps};
                      $obj->{state}{direction} = $rotation->{direction};
                    }
                  }

                } elsif( $data->{type} eq 'temperature' ) {
                  $obj->{state}{temperature} = int($data->{temperature}{temperature}*100) if( defined($data->{temperature})
                                                                                              && $data->{temperature}{temperature_valid} );

                } elsif( $data->{type} eq 'light_level' ) {
                  $obj->{state}{lightlevel} = $data->{light}{light_level} if( defined($data->{light})
                                                                              && $data->{light}{light_level_valid} );
                } elsif( $data->{type} eq 'zigbee_connectivity' ) {
                  $obj->{state}{reachable} = ($data->{status} eq 'connected') ? 1 : 0;

                } elsif( $data->{type} eq 'device_power' ) {
                  if( defined($data->{power_state}) ) {
                    $obj->{state}{battery} = $data->{power_state}{battery_level};
                    $obj->{state}{battery_state} = $data->{power_state}{battery_state};
                  }

                } elsif( $data->{type} eq 'entertainment_configuration' ) {
                  Log3 $name, 4, "$name: ignoring resource type $data->{type}";
                  Log3 $name, 5, Dumper $data;
                  $handled = 0;

                } elsif( $data->{type} eq 'bridge_home' ) {
                  HUEBridge_schedule($hash,'HUEBridge_Autocreate');
                  Log3 $name, 4, "$name: ignoring resource type $data->{type}";
                  Log3 $name, 5, Dumper $data;
                  $handled = 0;

                } elsif( $data->{type} eq 'room' ) {
                  Log3 $name, 4, "$name: ignoring resource type $data->{type}";
                  Log3 $name, 5, Dumper $data;
                  $handled = 0;

                } elsif( $data->{type} eq 'zone' ) {
                  Log3 $name, 4, "$name: ignoring resource type $data->{type}";
                  Log3 $name, 5, Dumper $data;
                  $handled = 0;

                } elsif( $data->{type} eq 'grouped_light' ) {
                  Log3 $name, 4, "$name: ignoring resource type $data->{type}";
                  Log3 $name, 5, Dumper $data;
                  $handled = 0;

                } elsif( $data->{type} eq 'light'
                         || $data->{type} eq 'grouped_light' ) {
                  $obj->{state}{on} = $data->{on}{on} if( defined($data->{on}) );

                  $obj->{state}{bri} = int($data->{dimming}{brightness} * 254 / 100) if( defined($data->{dimming}) );

                  if( defined($data->{color}) ) {
                    if( my $xy = $data->{color}{xy} ) {
                      $obj->{state}{colormode} = 'xy';
                      $obj->{state}{xy} = [$xy->{x}, $xy->{y}];
                    }
                  }

                  if( defined($data->{color_temperature}) && defined($data->{color_temperature}{mirek}) ) {
                    $obj->{state}{colormode} = 'ct';
                    $obj->{state}{ct} = $data->{color_temperature}{mirek};
                  }

                  if( defined($data->{effects}) ) {
                    $obj->{state}{v2effect} = $data->{effects}{status} if( $data->{effects}{status} );
		  }

                  if( defined($data->{dynamics}) ) {
                    $obj->{state}{dynamics_speed} = $data->{dynamics}{speed} if( $data->{dynamics}{speed_valid} );
                    $obj->{state}{dynamics_status} = $data->{dynamics}{status};
		  }

                } else {
                 Log3 $name, 3, "$name: EventStream: update for unknown type '$data->{type}' received";
                 $handled = 0;

                }

                if( $handled ) {
                  Log3 $name, 5, "$name: created from event: ". Dumper $obj;

                  if( HUEDevice_Parse($chash, $obj) && !$chash->{helper}{devtype} ) {
                    $changed .= "," if( $changed );
                    $changed .= $chash->{ID};
                  }

                  delete $hash->{helper}{ignored}{$code};
                  InternalTimer(gettimeofday()+1, "updateFinalButtonState", $chash, 0) if( $data->{type} eq 'button'
                                                                                             && AttrVal( $name,'queryAfterEvent', 0 ) );
                }

              } elsif( !$hash->{helper}{ignored}{$code} && !AttrVal($name, 'ignoreUnknown', undef) ) {
                Log3 $name, 3, "$name: EventStream: update for unknown device received: $code";

                HUEBridge_schedule($hash,'HUEBridge_Autocreate');

              }
            }

          } elsif( $event->{type} eq 'add' ) {
            Log3 $name, 4, "$name: EventStream: got $event->{type} event";

            HUEBridge_schedule($hash,'HUEBridge_refreshv2resources');

          } elsif( $event->{type} eq 'delete' ) {
            Log3 $name, 4, "$name: EventStream: got $event->{type} event";

          } else { #handle type error
           Log3 $name, 3, "$name: EventStream: unknown event type $event->{type}: $data";

          }

        }

        HUEBridge_updateGroups($hash, $changed) if( $changed ); # not needed ?

      } else {
        Log3 $name, 4, "$name: EventStream: unknown event: $key: $value";

      }

    }
    return undef;

  } elsif( defined($type) && $type eq 'application id' ) {
    if( $param->{httpheader} =~ m/hue-application-id:\s?([^\s;]*)/i ) {
      $hash->{'application id'} = $1;
    }

  } elsif( $data || $json ) {
    if( !$data && !$json ) {
      Log3 $name, 2, "$name: empty answer received";
      return undef;
    } elsif( $data && $data !~ m/^[\[{].*[\]}]$/ ) {
      Log3 $name, 2, "$name: invalid json detected: $data";
      return undef;
    }

    my $queryAfterSet = AttrVal( $name,'queryAfterSet', 1 );

    if( !$json ) {
      $json = eval { JSON->new->utf8(0)->decode($data) };
      Log3 $name, 2, "$name: json error: $@ in $data" if( $@ );
    }
    return undef if( !$json );

    if( ref($json) eq 'ARRAY' ) {
      HUEBridge_ProcessResponse($hash,$json) if( !$queryAfterSet );

      if( defined($json->[0]->{error}))
        {
          my $error = $json->[0]->{error}->{'description'};

          readingsSingleUpdate($hash, 'lastError', $error, 1 );

          Log3 $name, 3, $error;
        }

      #return ($json->[0]);
    }

    if( $hash == $param->{chash} ) {
      readingsBeginUpdate($hash);
      foreach my $resource (qw(lights groups sensors scenes rules schedules)) {
        next if( !defined($json->{$resource}) );

        readingsBulkUpdateIfChanged($hash, $resource, scalar %{$json->{$resource}}, 1);
      }
      readingsEndUpdate($hash,1);
    }

    if( $hash == $param->{chash} ) {
      if( !defined($type) ) {
        HUEBridge_Parse($hash,$json);

        if( defined($json->{sensors}) ) {
          my $sensors = $json->{sensors};
          foreach my $id ( keys %{$sensors} ) {
            my $code = $name ."-S". $id;

            if( my $chash = $modules{HUEDevice}{defptr}{$code} ) {
              HUEDevice_Parse($chash, $sensors->{$id});

              delete $hash->{helper}{ignored}{$code};

            } elsif( $hash->{has_v2_api} && !$hash->{helper}{ignored}{$code} && !AttrVal($name, 'ignoreUnknown', undef) ) {
              Log3 $name, 3, "$name: data for unknown sensor received: $code";

              HUEBridge_schedule($hash,'HUEBridge_Autocreate');
            }
          }
        }

        if( defined($json->{groups}) ) {
          my $groups = $json->{groups};
          foreach my $id ( keys %{$groups} ) {
            my $code = $name ."-G". $id;

            if( my $chash = $modules{HUEDevice}{defptr}{$code} ) {
              HUEDevice_Parse($chash, $groups->{$id});

              delete $hash->{helper}{ignored}{$code};

            } elsif( !$hash->{helper}{ignored}{$code} && !AttrVal($name, 'ignoreUnknown', undef) ) {
              Log3 $name, 2, "$name: data for unknown group received: $code";

              HUEBridge_schedule($hash,'HUEBridge_Autocreate');
            }
          }
        }

        $type = 'lights';
        $json = $json->{lights};
      }

      if( $type eq 'lights' ) {
        my $changed = "";
        my $lights = $json;
        foreach my $id ( keys %{$lights} ) {
          my $code = $name ."-". $id;

          if( my $chash = $modules{HUEDevice}{defptr}{$code} ) {
            if( HUEDevice_Parse($chash, $lights->{$id}) ) {
              $changed .= "," if( $changed );
              $changed .= $chash->{ID};
            }

            delete $hash->{helper}{ignored}{$code};

          } elsif( HUEDevice_moveToBridge( $lights->{$id}{uniqueid}, $name, $id ) ) {
            if( my $chash = $modules{HUEDevice}{defptr}{$code} ) {
              HUEDevice_Parse($hash, $lights->{$id});

              delete $hash->{helper}{ignored}{$code};
            }

          } elsif( !$hash->{helper}{ignored}{$code} && !AttrVal($name, 'ignoreUnknown', undef) ) {
            Log3 $name, 3, "$name: data for unknown device received: $code";

          }
        }
        HUEBridge_updateGroups($hash, $changed) if( $changed );

      } elsif( $type =~ m/^config$/ ) {
        HUEBridge_Parse($hash,$json);

      } else {
        Log3 $name, 2, "$name: message for unknown type received: $type";
        Log3 $name, 4, Dumper $json;

      }

    } elsif( $type =~ m/^lights\/(\d+)$/ ) {
      if( HUEDevice_Parse($param->{chash}, $json) ) {
        HUEBridge_updateGroups($hash, $param->{chash}{ID});
      }

    } elsif( $type =~ m/^lights\/(\d+)\/bridgeupdatestate$/ ) {
      # only for https://github.com/bwssytems/ha-bridge
      # see https://forum.fhem.de/index.php/topic,11020.msg961555.html#msg961555
      if( $queryAfterSet ) {
        my $chash = $param->{chash};
        if( $chash->{helper}->{update_timeout} ) {
          RemoveInternalTimer($chash);
          InternalTimer(gettimeofday()+1, "HUEDevice_GetUpdate", $chash, 0);
        } else {
          RemoveInternalTimer($chash);
          HUEDevice_GetUpdate( $chash );
        }
      }

    } elsif( $type =~ m/^groups\/(\d+)$/ ) {
      HUEDevice_Parse($param->{chash}, $json);

    } elsif( $type =~ m/^sensors\/(\d+)$/ ) {
      HUEDevice_Parse($param->{chash}, $json);

    } elsif( $type =~ m/^lights\/(\d+)\/state$/ ) {
      if( $queryAfterSet ) {
        my $chash = $param->{chash};
        if( $chash->{helper}->{update_timeout} ) {
          RemoveInternalTimer($chash);
          InternalTimer(gettimeofday()+1, "HUEDevice_GetUpdate", $chash, 0);
        } else {
          RemoveInternalTimer($chash);
          HUEDevice_GetUpdate( $chash );
        }
      }

    } elsif( $type =~ m/^groups\/(\d+)\/action$/
             || $type =~ m/^groups\/(\d+)\/scenes\/(\d+)\/recall$/ ) {
      my $chash = $param->{chash};
      if( $chash->{helper}->{update_timeout} ) {
        RemoveInternalTimer($chash);
        InternalTimer(gettimeofday()+1, "HUEDevice_GetUpdate", $chash, 0);
      } else {
        RemoveInternalTimer($chash);
        HUEDevice_GetUpdate( $chash );
      }

    } else {
      Log3 $name, 2, "$name: message for unknown type received: $type";
      Log3 $name, 4, Dumper $json;

    }
  }
}

#adapted version of the CustomGetFileFromURL subroutine from HttpUtils.pm
sub
HUEBridge_HTTP_Request($$$@)
{
  my ($quiet, $url, $method, $timeout, $data, $noshutdown) = @_;
  $timeout = 4.0 if(!defined($timeout));

  my $displayurl= $quiet ? "<hidden>" : $url;
  if($url !~ /^(http|https):\/\/([^:\/]+)(:\d+)?(\/.*)$/) {
    Log3 undef, 1, "HUEBridge_HTTP_Request $displayurl: malformed or unsupported URL";
    return undef;
  }

  my ($protocol,$host,$port,$path)= ($1,$2,$3,$4);

  if(defined($port)) {
    $port =~ s/^://;
  } else {
    $port = ($protocol eq "https" ? 443: 80);
  }
  $path= '/' unless defined($path);


  my $conn;
  if($protocol eq "https") {
    eval "use IO::Socket::SSL";
    if($@) {
      Log3 undef, 1, $@;
    } else {
      $conn = IO::Socket::SSL->new(PeerAddr=>"$host:$port", Timeout=>$timeout);
    }
  } else {
    $conn = IO::Socket::INET->new(PeerAddr=>"$host:$port", Timeout=>$timeout);
  }
  if(!$conn) {
    Log3 undef, 1, "HUEBridge_HTTP_Request $displayurl: Can't connect to $protocol://$host:$port";
    undef $conn;
    return undef;
  }

  $host =~ s/:.*//;
  #my $hdr = ($data ? "POST" : "GET")." $path HTTP/1.0\r\nHost: $host\r\n";
  my $hdr = $method." $path HTTP/1.0\r\nHost: $host\r\n";
  if(defined($data)) {
    $hdr .= "Content-Length: ".length($data)."\r\n";
    $hdr .= "Content-Type: application/json";
  }
  $hdr .= "\r\n\r\n";
  syswrite $conn, $hdr;
  syswrite $conn, $data if(defined($data));
  shutdown $conn, 1 if(!$noshutdown);

  my ($buf, $ret) = ("", "");
  $conn->timeout($timeout);
  for(;;) {
    my ($rout, $rin) = ('', '');
    vec($rin, $conn->fileno(), 1) = 1;
    my $nfound = select($rout=$rin, undef, undef, $timeout);
    if($nfound <= 0) {
      Log3 undef, 1, "HUEBridge_HTTP_Request $displayurl: Select timeout/error: $!";
      undef $conn;
      return undef;
    }

    my $len = sysread($conn,$buf,65536);
    last if(!defined($len) || $len <= 0);
    $ret .= $buf;
  }

  $ret=~ s/(.*?)\r\n\r\n//s; # Not greedy: switch off the header.
  my @header= split("\r\n", $1);
  my $hostpath= $quiet ? "<hidden>" : $host . $path;
  Log3 undef, 5, "HUEBridge_HTTP_Request $displayurl: Got data, length: ".length($ret);
  if(!length($ret)) {
    Log3 undef, 4, "HUEBridge_HTTP_Request $displayurl: Zero length data, header follows...";
    for (@header) {
        Log3 undef, 4, "HUEBridge_HTTP_Request $displayurl: $_";
    }
  }
  undef $conn;
  if($header[0] =~ /^[^ ]+ ([\d]{3})/ && $1 != 200) {
    my $result = { error => "error: $1" };
    return $result;
  }
  return $ret;
}

sub
HUEBridge_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;
  $attrVal = int($attrVal) if($attrName eq "interval");
  $attrVal = 60 if($attrName eq "interval" && $attrVal < 60 && $attrVal != 0);

  if( $attrName eq "disable" ) {
    my $hash = $defs{$name};
    if( $cmd eq 'set' && $attrVal ne "0" ) {
      readingsSingleUpdate($hash, 'state', 'disabled', 1 );
    } else {
      $attr{$name}{$attrName} = 0;
      readingsSingleUpdate($hash, 'state', 'active', 1 );
      HUEBridge_OpenDev($hash);
    }
  } elsif( $attrName eq "disabledForIntervals" ) {
    my $hash = $defs{$name};
    if( $cmd eq 'set' ) {
      $attr{$name}{$attrName} = $attrVal;
    } else {
      $attr{$name}{$attrName} = "";
    }

    readingsSingleUpdate($hash, 'state', IsDisabled($name)?'disabled':'active', 1 );
    HUEBridge_OpenDev($hash) if( !IsDisabled($name) );

  }

  if( $cmd eq 'set' ) {
    if( $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return $attrName ." set to ". $attrVal;
    }
  }

  return;
}

1;

__END__

=pod
=item tag cloudfree
=item tag publicAPI
=item tag protocol:zigbee
=item summary    module for Philips HUE Bridges (and deCONZ)
=item summary_DE Modul f&uuml;r die Philips HUE Bridge (und deCONZ)
=begin html

<a id="HUEBridge"></a>
<h3>HUEBridge</h3>
<ul>
  Module to access the bridge of the philips hue lighting system.<br><br>

  The actual hue bulbs, living colors or living whites devices are defined as <a href="#HUEDevice">HUEDevice</a> devices.

  <br><br>
  All newly found lights and groups are autocreated at startup and added to the room HUEDevice.

  <br><br>
  Notes:
  <ul>
    <li>This module needs <code>JSON</code>.<br>
        Please install with '<code>cpan install JSON</code>' or your method of choice.</li>
  </ul>


  <br><br>
  <a id="HUEBridge-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; HUEBridge [&lt;host&gt;] [&lt;interval&gt;]</code><br>
    <br>

    Defines a HUEBridge device with address &lt;host&gt;.<br><br>

    If [&lt;host&gt;] is not given the module will try to autodetect the bridge with the hue portal services.<br><br>

    The bridge status will be updated every &lt;interval&gt; seconds. The default and minimum is 60.<br><br>

    After a new bridge is created the pair button on the bridge has to be pressed.<br><br>

    Examples:
    <ul>
      <code>define bridge HUEBridge 10.0.1.1</code><br>
    </ul>
  </ul><br>

  <a id="HUEBridge-get"></a>
  <b>Get</b>
  <ul>
    <a id="HUEBridge-get-lights"></a>
    <li>lights<br>
      list the lights known to the bridge.</li>
    <a id="HUEBridge-get-groups"></a>
    <li>groups<br>
      list the groups known to the bridge.</li>
    <a id="HUEBridge-get-scenes"></a>
    <li>scenes [detail]<br>
      list the scenes known to the bridge.</li>
    <a id="HUEBridge-get-schedules"></a>
    <li>schedules [detail]<br>
      list the schedules known to the bridge.</li>
    <a id="HUEBridge-get-startup"></a>
    <li>startup<br>
      show startup behavior of all known lights</li>
    <a id="HUEBridge-get-rule"></a>
    <li>rule &lt;id&gt; <br>
      list the rule with &lt;id&gt;.</li>
    <a id="HUEBridge-get-rules"></a>
    <li>rules [detail] <br>
      list the rules known to the bridge.</li>
    <a id="HUEBridge-get-sensors"></a>
    <li>sensors [detail] <br>
      list the sensors known to the bridge.</li>
    <a id="HUEBridge-get-whitelist"></a>
    <li>whitelist<br>
      list the whitlist of the bridge.</li>
  </ul><br>

  <a id="HUEBridge-set"></a>
  <b>Set</b>
  <ul>
    <a id="HUEBridge-set-autocreate"></a><li>autocreate [sensors]<br>
      Create fhem devices for all light and group devices. sensors are autocreated only if sensors parameter is given.</li>
    <a id="HUEBridge-set-autodetect"></a><li>autodetect<br>
      Initiate the detection of new ZigBee devices. After aproximately one minute any newly detected
      devices can be listed with <code>get &lt;bridge&gt; devices</code> and the corresponding fhem devices
      can be created by <code>set &lt;bridge&gt; autocreate</code>.</li>
    <a id="HUEBridge-set-delete"></a><li>delete &lt;name&gt;|&lt;id&gt;<br>
      Deletes the given device in the bridge and deletes the associated fhem device.</li>
    <a id="HUEBridge-set-creategroup"></a><li>creategroup &lt;name&gt; &lt;lights&gt;<br>
      Create a group out of &lt;lights&gt; in the bridge.
      The lights are given as a comma sparated list of fhem device names or bridge light numbers.</li>
    <a id="HUEBridge-set-deletegroup"></a><li>deletegroup &lt;name&gt;|&lt;id&gt;<br>
      Deletes the given group in the bridge and deletes the associated fhem device.</li>
    <a id="HUEBridge-set-savescene"></a><li>savescene &lt;name&gt; &lt;lights&gt;<br>
      Create a scene from the current state of &lt;lights&gt; in the bridge.
      The lights are given as a comma sparated list of fhem device names or bridge light numbers.</li>
    <a id="HUEBridge-set-modifyscene"></a><li>modifyscene &lt;id&gt; &lt;light&gt; &lt;light-args&gt;<br>
      Modifys the given scene in the bridge.</li>
    <a id="HUEBridge-set-scene"></a><li>scene &lt;id&gt;|&lr;name&gt;<br>
      Recalls the scene with the given id.</li>
    <a id="HUEBridge-set-deletescene"></a><li>deletescene &lt;id&gt;|&lr;name&gt;<br>
      Deletes the scene with the given id.</li>
    <a id="HUEBridge-set-updateschedule"></a><li>updateschedule &lt;id&gt; &lt;attributes json&gt;<br>
      updates the given schedule in the bridge with &lt;attributes json&gt; </li>
    <a id="HUEBridge-set-enableschedule"></a><li>enableschedule &lt;id&gt;<br>
      enables the given schedule</li>
    <a id="HUEBridge-set-disableschedule"></a><li>disableschedule &lt;id&gt;<br>
      disables the given schedule</li>
    <a id="HUEBridge-set-createrule"></a><li>createrule &lt;name&gt; &lt;conditions&amp;actions json&gt;<br>
      Creates a new rule in the bridge.</li>
    <a id="HUEBridge-set-deleterule"></a><li>deleterule &lt;id&gt;<br>
      Deletes the given rule in the bridge.</li>
    <a id="HUEBridge-set-updaterule"></a><li>updaterule &lt;id&gt; &lt;json&gt;<br>
      Write specified rule's toplevel data.</li>
    <a id="HUEBridge-set-createsensor"></a><li>createsensor &lt;name&gt; &lt;type&gt; &lt;uniqueid&gt; &lt;swversion&gt; &lt;modelid&gt;<br>
      Creates a new CLIP (IP) sensor in the bridge.</li>
    <a id="HUEBridge-set-deletesensor"></a><li>deletesensor &lt;id&gt;<br>
      Deletes the given sensor in the bridge and deletes the associated fhem device.</li>
    <a id="HUEBridge-set-configlight"></a><li>configlight &lt;id&gt; &lt;json&gt;<br>
      Sends the specified json string as configuration to the light &lt;id&gt;. You can use this e.g. to modify the startup behaviour
      of a light. For a full list of available options see:
      <a href="https://developers.meethue.com/develop/hue-api/supported-devices/#archetype">Config object attributes</a>
      (free Hue developer account needed, use wisely)</li>
    <a id="HUEBridge-set-configsensor"></a><li>configsensor &lt;id&gt; &lt;json&gt;<br>
      Write sensor config data.</li>
    <a id="HUEBridge-set-setsensor"></a><li>setsensor &lt;id&gt; &lt;json&gt;<br>
      Write CLIP sensor status data.</li>
    <a id="HUEBridge-set-updatesensor"></a><li>updatesensor &lt;id&gt; &lt;json&gt;<br>
      Write sensor toplevel data.</li>
    <a id="HUEBridge-set-deletewhitelist"></a><li>deletewhitelist &lt;key&gt;<br>
      Deletes the given key from the whitelist in the bridge.</li>
    <a id="HUEBridge-set-touchlink"></a><li>touchlink<br>
      perform touchlink action</li>
    <a id="HUEBridge-set-checkforupdate"></a><li>checkforupdate<br>
      perform checkforupdate action</li>
    <a id="HUEBridge-set-statusRequest"></a><li>statusRequest<br>
      Update bridge status.</li>
    <a id="HUEBridge-set-swupdate"></a><li>swupdate<br>
      Update bridge firmware. This command is only available if a new firmware is
      available (indicated by updatestate with a value of 2. The version and release date is shown in the reading swupdate.<br>
      A notify of the form <code>define HUEUpdate notify bridge:swupdate.* {...}</code>
      can be used to be informed about available firmware updates.<br></li>
    <a id="HUEBridge-set-inactive"></a><li>inactive<br>
      inactivates the current device. note the slight difference to the
      disable attribute: using set inactive the state is automatically saved
      to the statefile on shutdown, there is no explicit save necesary.<br>
      this command is intended to be used by scripts to temporarily
      deactivate the harmony device.<br>
      the concurrent setting of the disable attribute is not recommended.</li>
    <a id="HUEBridge-set-active"></a><li>active<br>
      activates the current device (see inactive).</li>
  </ul><br>

  <a id="HUEBridge-attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
    <a id="HUEBridge-attr-httpUtils"></a>
    <li>httpUtils<br>
      0 -> use HttpUtils_BlockingGet<br>
      1 -> use HttpUtils_NonblockingGet<br>
      not set -> use old module specific implementation</li>
    <a id="HUEBridge-attr-pollDevices"></a><li>pollDevices<br>
      1 -> the bridge will poll all lights in one go instead of each light polling itself independently<br>
      2 -> the bridge will poll all devices in one go instead of each device polling itself independently<br>
      default is 2. will be deleted if v2 api is detected and eventstream connects.</li>
    <a id="HUEBridge-attr-createEventTimestampReading"></a><li>createEventTimestampReading<br>
      timestamp reading for every event received<br>
      0 -> update reading without fhem event<br>
      1 -> update reading with fhem event<br>
      undef -> don't create reading</li>
    <a id="HUEBridge-attr-createGroupReadings"></a><li>createGroupReadings<br>
      create 'artificial' readings for group devices.<br>
      0 -> create readings only for group devices where createGroupReadings ist set to 1<br>
      1 -> create readings for all group devices where createGroupReadings ist not set or set to 1<br>
      undef -> do nothing</li>
    <a id="HUEBridge-attr-forceAutocreate"></a><li>forceAutocreate<br>
      try to create devices even if autocreate is disabled.</li>
    <a id="HUEBridge-attr-ignoreUnknown"></a><li>ignoreUnknown<br>
      don't try to create devices after data or events with unknown references are received.</li>
    <a id="HUEBridge-attr-queryAfterEvent"></a><li>queryAfterEvent<br>
      the bridge will request the real button state 1 sec after the final event in a quick series. default is 0.</li>
    <a id="HUEBridge-attr-queryAfterSet"></a><li>queryAfterSet<br>
      the bridge will request the real device state after a set command. default is 1.</li>
    <a id="HUEBridge-attr-noshutdown"></a><li>noshutdown<br>
      Some bridge devcies require a different type of connection handling. raspbee/deconz only works if the connection
      is not immediately closed, the philips hue bridge now shows the same behavior. so this is now the default.  </li>
  </ul><br>
</ul><br>

=end html

=encoding utf8
=for :application/json;q=META.json 30_HUEBridge.pm
{
  "abstract": "module for the philips hue bridge",
  "x_lang": {
    "de": {
      "abstract": "Modul für die Philips HUE Bridge"
    }
  },
  "resources": {
    "x_wiki": {
      "web": "https://wiki.fhem.de/wiki/Hue"
    }
  },
  "keywords": [
    "fhem-mod",
    "fhem-mod-device",
    "HUE",
    "zigbee"
  ],
  "release_status": "stable",
  "x_fhem_maintainer": [
    "justme1968"
  ],
  "x_fhem_maintainer_github": [
    "justme-1968"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.014,
        "Meta": 0,
        "JSON": 0,
        "Data::Dumper": 0,
        "IO::Socket::INET": 0
      },
      "recommends": {
      },
      "suggests": {
        "HUEDevice": 0
      }
    }
  }
}
=end :application/json;q=META.json
=cut
