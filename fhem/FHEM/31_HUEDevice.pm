# $Id$
# "Hue Personal Wireless Lighting" is a trademark owned by Koninklijke Philips Electronics N.V.,
# see www.meethue.com for more information.
# I am in no way affiliated with the Philips organization.

package main;

use strict;
use warnings;

use FHEM::Meta;

use Color;

#use POSIX;
use Time::HiRes qw(gettimeofday);
use JSON;
use SetExtensions;
use Time::Local;

#require "30_HUEBridge.pm";
#require "$attr{global}{modpath}/FHEM/30_HUEBridge.pm";

use vars qw($devcount);   # Maximum device number, used for storing
use vars qw(%FW_webArgs); # all arguments specified in the GET

my %hueModels = (
  LCT001 => {name => 'Hue Bulb'                 ,type => 'Extended color light'    ,subType => 'extcolordimmer',
                                                 gamut => 'B',                      icon => 'hue_filled_white_and_color_e27_b22', },
  LCT002 => {name => 'Hue Spot BR30'            ,type => 'Extended color light'    ,subType => 'extcolordimmer',
                                                 gamut => 'B',                      icon => 'hue_filled_br30.svg', },
  LCT003 => {name => 'Hue Spot GU10'            ,type => 'Extended color light'    ,subType => 'extcolordimmer',
                                                 gamut => 'B',                      icon => 'hue_filled_gu10_par16', },
  LCT007 => {name => 'Hue Bulb V2'              ,type => 'Extended color light'    ,subType => 'extcolordimmer',
                                                 gamut => 'B',                      icon => 'hue_filled_white_and_color_e27_b22', },
  LCT010 => {name => 'Hue Bulb V3'              ,type => 'Extended color light'    ,subType => 'extcolordimmer',
                                                 gamut => 'C',                      icon => 'hue_filled_white_and_color_e27_b22', },
  LCT011 => {name => 'Hue BR30'                 ,type => 'Extended color light'    ,subType => 'extcolordimmer',
                                                 gamut => 'C',                      icon => 'hue_filled_br30.svg', },
  LCT012 => {name => 'Hue color candle'         ,type => 'Extended color light'    ,subType => 'extcolordimmer',
                                                 gamut => 'C', },
  LCT014 => {name => 'Hue Bulb V3'              ,type => 'Extended color light'    ,subType => 'extcolordimmer',
                                                 gamut => 'C',                      icon => 'hue_filled_white_and_color_e27_b22', },
  LCT024 => {name => 'Hue Play'                 ,type => 'Extended color light'    ,subType => 'extcolordimmer',
                                                 gamut => 'C',                      icon => 'hue_filled_play', },
  LCX016 => {name => 'Festavia string lights'   ,type => 'Extended color light'    ,subType => 'extcolordimmer',
                                                 gamut => 'C',                      icon => 'hue2023_string_light', },
  LLC001 => {name => 'Living Colors G2'         ,type => 'Color light'             ,subType => 'colordimmer',
                                                 gamut => 'A',                      icon => 'hue_filled_iris', },
  LLC005 => {name => 'Living Colors Bloom'      ,type => 'Color light'             ,subType => 'colordimmer',
                                                 gamut => 'A',                      icon => 'hue_filled_bloom', },
  LLC006 => {name => 'Living Colors Gen3 Iris'  ,type => 'Color light'             ,subType => 'colordimmer',
                                                 gamut => 'A',                      icon => 'hue_filled_iris', },
  LLC007 => {name => 'Living Colors Gen3 Bloom' ,type => 'Color light'             ,subType => 'colordimmer',
                                                 gamut => 'A',                      icon => 'hue_filled_bloom', },
  LLC010 => {name => 'Hue Living Colors Iris'   ,type => 'Color light'             ,subType => 'colordimmer',
                                                 gamut => 'A',                      icon => 'hue_filled_iris', },
  LLC011 => {name => 'Hue Living Colors Bloom'  ,type => 'Color light'             ,subType => 'colordimmer',
                                                 gamut => 'A',                      icon => 'hue_filled_bloom', },
  LLC012 => {name => 'Hue Living Colors Bloom'  ,type => 'Color light'             ,subType => 'colordimmer',
                                                 gamut => 'A',                      icon => 'hue_filled_bloom', },
  LLC013 => {name => 'Disney Living Colors'     ,type => 'Color light'             ,subType => 'colordimmer',
                                                 gamut => 'A',                      icon => 'hue_filled_storylight', },
  LLC014 => {name => 'Living Colors Aura'       ,type => 'Color light'             ,subType => 'colordimmer',
                                                 gamut => 'A',                      icon => 'hue_filled_aura', },
  LLC020 => {name => 'Hue Go'                   ,type => 'Color light'             ,subType => 'extcolordimmer',
                                                 gamut => 'C',                      icon => 'hue_filled_go', },
  LST001 => {name => 'Hue LightStrips'          ,type => 'Color light'             ,subType => 'colordimmer',
                                                 gamut => 'A',                      icon => 'hue_filled_lightstrip', },
  LST002 => {name => 'Hue LightStrips Plus'     ,type => 'Extended color light'    ,subType => 'extcolordimmer',
                                                 gamut => 'C',                      icon => 'hue_filled_lightstrip', },
  LWB001 => {name => 'Living Whites Bulb'       ,type => 'Dimmable light'          ,subType => 'dimmer',
                                                                                    icon => 'hue_filled_living_whites', },
  LWB003 => {name => 'Living Whites Bulb'       ,type => 'Dimmable light'          ,subType => 'dimmer',
                                                                                    icon => 'hue_filled_living_whites', },
  LWB004 => {name => 'Hue Lux'                  ,type => 'Dimmable light'          ,subType => 'dimmer',
                                                                                    icon => 'hue_filled_white_and_color_e27_b22', },
  LWB006 => {name => 'Hue Lux'                  ,type => 'Dimmable light'          ,subType => 'dimmer',
                                                                                    icon => 'hue_filled_white_and_color_e27_b22', },
  LWB007 => {name => 'Hue Lux'                  ,type => 'Dimmable light'          ,subType => 'dimmer',
                                                                                    icon => 'hue_filled_white_and_color_e27_b22', },
  LWB010 => {name => 'Hue Lux'                  ,type => 'Dimmable light'          ,subType => 'dimmer',
                                                                                    icon => 'hue_filled_white_and_color_e27_b22', },
  LWB014 => {name => 'Hue Lux'                  ,type => 'Dimmable light'          ,subType => 'dimmer',
                                                                                    icon => 'hue_filled_white_and_color_e27_b22', },
  LWO003 => {name => 'Hue White Filament Bulb G125' ,type => 'Dimmable light'          ,subType => 'dimmer',
                                                                                    icon => 'hue_filled_filament', },
  LWV001 => {name => 'Hue White Filament Bulb'  ,type => 'Dimmable light'          ,subType => 'dimmer',
                                                                                    icon => 'hue_filled_filament', },
  LTO001 => {name => 'Hue Filament Bulb G93'    ,type => 'Color temperature light' ,subType => 'ctdimmer',
                                                                                    icon => 'hue_filled_filament', },
  LTO002 => {name => 'Hue Filament Bulb G125'   ,type => 'Color temperature light' ,subType => 'ctdimmer',
                                                                                    icon => 'hue_filled_filament', },
  LTO004 => {name => 'Hue Filament Bulb G25'    ,type => 'Color temperature light' ,subType => 'ctdimmer',
                                                                                    icon => 'hue_filled_filament', },
  LTW001 => {name => 'Hue A19 White Ambience'   ,type => 'Color temperature light' ,subType => 'ctdimmer',
                                                                                    icon => 'hue_filled_white_and_color_e27_b22', },
  LTW004 => {name => 'Hue A19 White Ambience'   ,type => 'Color temperature light' ,subType => 'ctdimmer', },

  LTW012 => {name => 'Hue ambiance candle'      ,type => 'Color temperature light' ,subType => 'ctdimmer',
                                                                                    icon => 'hue_filled_gu10_par16', },
  LTW013 => {name => 'Hue GU10 White Ambience'  ,type => 'Color temperature light' ,subType => 'ctdimmer',
                                                                                    icon => 'hue_filled_gu10_par16', },
  LTW014 => {name => 'Hue GU10 White Ambience'  ,type => 'Color temperature light' ,subType => 'ctdimmer',
                                                                                    icon => 'hue_filled_gu10_par16', },
  LLM001 => {name => 'Color Light Module'       ,type => 'Extended color light'    ,subType => 'extcolordimmer',
                                                 gamut => 'B', },
  LLM010 => {name => 'Color Temperature Module' ,type => 'Color temperature light' ,subType => 'ctdimmer', },
  LLM011 => {name => 'Color Temperature Module' ,type => 'Color temperature light' ,subType => 'ctdimmer', },
  LLM012 => {name => 'Color Temperature Module' ,type => 'Color temperature light' ,subType => 'ctdimmer', },
  LWL001 => {name => 'LivingWhites Outlet'      ,type => 'Dimmable plug-in unit'   ,subType => 'dimmer',
                                                                                    icon => 'hue_filled_outlet', },
  LOM001 => {name => 'Hue Smart Plug'           ,type => 'On/Off plug-in unit'     ,subType => 'switch',
                                                                                    icon => 'hue_filled_plug', },
  LOM002 => {name => 'Hue Smart Plug'           ,type => 'On/Off plug-in unit'     ,subType => 'switch',
                                                                                    icon => 'hue_filled_plug', },

  RWL020    => {name => 'Hue Dimmer Switch'     ,type => 'ZLLSwitch'               ,subType => 'sensor',
                                                                                    icon => 'hue_filled_hds', },
  RWL021    => {name => 'Hue Dimmer Switch'     ,type => 'ZLLSwitch'               ,subType => 'sensor',
                                                                                    icon => 'hue_filled_hds', },
  ZGPSWITCH => {name => 'Hue Tap'               ,type => 'ZGPSwitch'               ,subType => 'sensor',
                                                                                    icon => 'hue_filled_tap', },

  LCX002    => {name => 'Hue play gradient lightstrip'     ,type => 'Extended color light'    ,subType => 'extcolordimmer',
                                                                                    icon => 'hue_filled_lightstrip', },
  LCX004    => {name => 'Hue gradient lightstrip'          ,type => 'Extended color light', subType => 'extcolordimmer',
                                                                                    icon => 'hue_filled_lightstrip', },

  440400982841 => {name => 'Hue Play'           ,type => 'Extended color light'    ,subType => 'extcolordimmer',
                                                                                    icon => 'hue_filled_play', },

  FOHSWITCH => {name => 'Friends of Hue Switch'     ,type => 'ZGPSwitch'           ,subType => 'sensor',
                                                                                    icon => 'hue_filled_foh', },

 'FLS-H3'  => {name => 'dresden elektronik FLS-H lp'  ,type => 'Color temperature light' ,subType => 'ctdimmer',},
 'FLS-PP3' => {name => 'dresden elektronik FLS-PP lp' ,type => 'Extended color light'    ,subType => 'extcolordimmer', },

 'Flex RGBW'        => {name => 'LIGHTIFY Flex RGBW'                   ,type => 'Extended color light'    ,subType => 'extcolordimmer', },
 'Classic A60 RGBW' => {name => 'LIGHTIFY Classic A60 RGBW'            ,type => 'Extended color light'    ,subType => 'extcolordimmer', },
 'CLA60 RGBW OSRAM' => {name => 'SMART+ Classic A60 RGBW'              ,type => 'Extended color light'    ,subType => 'extcolordimmer', },
 'Gardenspot RGB'   => {name => 'LIGHTIFY Gardenspot Mini RGB'         ,type => 'Color light'             ,subType => 'colordimmer', },
 'Surface Light TW' => {name => 'LIGHTIFY Surface light tunable white' ,type => 'Color temperature light' ,subType => 'ctdimmer', },
 'Classic A60 TW'   => {name => 'LIGHTIFY Classic A60 tunable white'   ,type => 'Color temperature light' ,subType => 'ctdimmer', },
 'Classic B40 TW'   => {name => 'LIGHTIFY Classic B40 tunable white'   ,type => 'Color temperature light' ,subType => 'ctdimmer', },
 'PAR16 50 TW'      => {name => 'LIGHTIFY PAR16 50 tunable white'      ,type => 'Color temperature light' ,subType => 'ctdimmer', },
 'Classic A60'      => {name => 'LIGHTIFY Classic A60 dimmable light'  ,type => 'Dimmable Light'          ,subType => 'dimmer', },
 'Plug - LIGHTIFY'  => {name => 'LIGHTIFY Plug'                        ,type => 'On/Off plug-in unit'     ,subType => 'switch', },
 'Plug 01'          => {name => 'LIGHTIFY Plug'                        ,type => 'On/Off plug-in unit'     ,subType => 'switch', },

 'RM01' => {name => 'Busch-Jaeger ZigBee Light Link Relais', type => 'On/Off light'   ,subType => 'switch', },
 'DM01' => {name => 'Busch-Jaeger ZigBee Light Link Dimmer', type => 'Dimmable light' ,subType => 'dimmer', },
);

my %gamut = (
  A => { r => { hue =>   0, x => 0.704,  y => 0.296  },
         g => { hue => 100, x => 0.2151, y => 0.7106 },
         b => { hue => 184, x => 0.138,  y => 0.08   }, },
  B => { r => { hue =>   0, x => 0.675,  y => 0.322  },
         g => { hue => 100, x => 0.409,  y => 0.518  },
         b => { hue => 184, x => 0.167,  y => 0.04   }, },
  C => { r => { hue =>   0, x => 0.692,  y => 0.308  },
         g => { hue => 100, x => 0.17,   y => 0.7    },
         b => { hue => 184, x => 0.153,  y => 0.048  }, },
);

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


my $HUEDevice_hasDataDumper = 1;

sub HUEDevice_Initialize($)
{
  my ($hash) = @_;

  # Provide

  #Consumer
  $hash->{DefFn}    = "HUEDevice_Define";
  $hash->{UndefFn}  = "HUEDevice_Undefine";
  $hash->{SetFn}    = "HUEDevice_Set";
  $hash->{GetFn}    = "HUEDevice_Get";
  $hash->{AttrFn}   = "HUEDevice_Attr";
  $hash->{AttrList} = "IODev ".
                      "delayedUpdate:1 ".
                      "ignoreReachable:1,0 ".
                      "realtimePicker:1,0 ".
                      "color-icons:1,2 ".
                      "transitiontime ".
                      "model:".join(",", sort map { $_ =~ s/ /#/g ;$_} keys %hueModels)." ".
                      "setList:textField-long ".
                      "configList:textField-long ".
                      "subType:extcolordimmer,colordimmer,ctdimmer,dimmer,switch,blind ".
                      "readingList ".
                      $readingFnAttributes;

  #$hash->{FW_summaryFn} = "HUEDevice_summaryFn";

  FHEM_colorpickerInit();

  eval "use Data::Dumper";
  $HUEDevice_hasDataDumper = 0 if($@);

  return FHEM::Meta::InitMod( __FILE__, $hash );
}

sub
HUEDevice_devStateIcon($)
{
  my($hash) = @_;
  $hash = $defs{$hash} if( ref($hash) ne 'HASH' );

  return undef if( !$hash );
  my $name = $hash->{NAME};

  return ".*:light_question:toggle" if( !$hash->{helper}{reachable} );
  return ".*:light_toggle:toggle" if( ReadingsVal($name, 'mode', 'homeautomation') ne 'homeautomation' );

  my $pct = ReadingsVal($name, 'pct', 100);
  my $subtype = AttrVal($name, 'subType', 'extcolordimmer' );

  if( $subtype eq 'blind' ) {
    my $p = int(10-$pct/10)*10;
    return ".*:fts_window_2w" if( $p == 0 );
    return ".*:fts_shutter_$p";
  }

  if( $hash->{helper}->{devtype} && $hash->{helper}->{devtype} eq 'G' ) {
    if( $hash->{IODev} ) {
      my $createGroupReadings = AttrVal($hash->{IODev}{NAME},"createGroupReadings",undef);
      if( defined($createGroupReadings) ) {
        return undef if( $createGroupReadings && !AttrVal($hash->{NAME},"createGroupReadings", 1) );
        return undef if( !$createGroupReadings && !AttrVal($hash->{NAME},"createGroupReadings", undef) );


        return ".*:off:toggle" if( ReadingsVal($name,"onoff","0") eq "0" );

        my $pct = ReadingsVal($name,"pct","100");
        my $s = $dim_values{int($pct/7)};
        $s="on" if( $pct eq "100" );

        return ".*:$s:toggle";
      }
    }

    #return ".*:off:toggle" if( !ReadingsVal($name,'any_on',0) );
    #return ".*:on:toggle" if( ReadingsVal($name,'any_on',0) );

    return undef;
  }

  return undef if( $hash->{helper}->{devtype} );

  return ".*:off:toggle" if( ReadingsVal($name,"state","off") eq "off" );

  my $s = $dim_values{int($pct/7)};
  $s="on" if( $pct eq "100" );

  return ".*:$s:toggle" if( AttrVal($name, "model", "") eq "LWL001" );
  return ".*:$s:toggle" if( $subtype eq "dimmer" );
  return ".*:$s:toggle" if( $subtype eq "switch" );

  my $effect = ReadingsVal($name, 'effect', 'none') ne 'none'
               || ReadingsVal($name, 'v2effect', 'no_effect') ne 'no_effect'
               || ReadingsVal($name, 'dynamics_status', 'none') ne 'none'; # eq 'dynamic_palette' ?

  return ".*:light_toggle@#".CommandGet("","$name RGB").":toggle" if( $effect && $pct < 100 && AttrVal($name, "color-icons", 0) == 2 );
  return ".*:light_toggle:toggle" if( $effect && AttrVal($name, "color-icons", 0) != 0 );

  return ".*:$s@#".CommandGet("","$name RGB").":toggle" if( $pct < 100 && AttrVal($name, "color-icons", 0) == 2 );
  return ".*:on@#".CommandGet("","$name rgb").":toggle" if( AttrVal($name, "color-icons", 0) != 0 );

  return '<div style="width:32px;height:19px;'.
         'border:1px solid #fff;border-radius:8px;background-color:#'.CommandGet("","$name rgb").';"></div>';
}
sub
HUEDevice_summaryFn($$$$)
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash   = $defs{$d};
  my $name = $hash->{NAME};

  return HUEDevice_devStateIcon($hash);
}

sub
HUEDevice_IODevChanged($$$;$)
{
  my ($hash,$old,$new, $new_id) = @_;
  $hash = $defs{$hash} if( ref($hash) ne 'HASH' );
  my $name = $hash->{NAME};

  if( $hash->{TYPE} ne 'HUEDevice' ) {
    Log3 $name, 1, "$name: can't change IODev for TYPE $hash->{TYPE}";
    return undef;
  }
  if( $new_id && $hash->{helper}->{devtype} ) {
    Log3 $name, 1, "$name: can't change IODev for groups and sensors";
    return undef;
  }

  $old = AttrVal($name, "IODev", undef) if( !$old );

  my $code = $hash->{ID};
  $code = $old ."-". $code if( $old );

  delete $modules{HUEDevice}{defptr}{$code};

  AssignIoPort($hash,$new);
  if( defined($hash->{IODev}) ) {
    Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }
  $new = $hash->{IODev}->{NAME} if( defined($hash->{IODev}) );

  $hash->{ID} = $new_id if( defined($new_id) );

  $code = $hash->{ID};
  $code = $new ."-". $code if( $new );
  $modules{HUEDevice}{defptr}{$code} = $hash;

  if( $old ) {
    if( $new ) {
      $hash->{DEF} =~ s/IODev=$old/IODev=$new/;
    } else {
      $hash->{DEF} =~ s/IODev=$old//;
    }
  } elsif( $new ) {
    $hash->{DEF} .= " IODev=$new"
  }

  $hash->{NR} = $devcount++ if( $new_id && $new && $defs{$new}->{NR} > $hash->{NR} );
  $hash->{DEF} =~ s/[^\s]+/$new_id/ if( $new_id );

  $hash->{DEF} =~ s/  / /g;

  addStructChange( 'modify', $name, "$name $hash->{DEF}");

  return $new;
}

sub
HUEDevice_moveToBridge($$$) {
  my ($serial, $new, $new_id) = @_;

  my $found;

  return $found if( !$serial );
  return $found if( !$new_id );

  foreach my $hash ( values %{$modules{HUEDevice}{defptr}} ) {
    next if( !$hash->{uniqueid} );
    next if( $hash->{helper}{devtype} );
    next if( $serial ne $hash->{uniqueid} );

    my $name = $hash->{NAME};
    my $old = AttrVal( $name, 'IODev', '<unknown>' );

    next if( $old eq $new );

    Log3 $name, 2, "moving $name [$serial] from $old to $new";

    HUEDevice_IODevChanged($hash, undef, $new, $new_id);
    CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );

    $found = 1;
    last;
  }

  return $found;
}

sub
HUEDevice_Define($$) {
  my ($hash, $def) = @_;

  return $@ unless ( FHEM::Meta::SetInternals($hash) );


  my @args = split("[ \t]+", $def);

  $hash->{helper}->{devtype} = "";
  if( $args[2] eq "group" ) {
    $hash->{helper}->{devtype} = "G";
    splice( @args, 2, 1 );
  } elsif( $args[2] eq "sensor" ) {
    $hash->{helper}->{devtype} = "S";
    splice( @args, 2, 1 );
  }

  my $iodev;
  my $i = 0;
  foreach my $param ( @args ) {
    if( $param =~ m/IODev=([^\s]*)/ ) {
      $iodev = $1;
      splice( @args, $i, 1 );
      last;
    }
    $i++;
  }


  return "Usage: define <name> HUEDevice [group|sensor] <id> [interval]"  if(@args < 3);

  my ($name, $type, $id, $interval) = @args;

  $hash->{STATE} = 'Initialized' if($init_done);

  $hash->{ID} = $hash->{helper}->{devtype}.$id;

  $iodev = HUEDevice_IODevChanged( $hash, undef, $iodev ) if( !$hash->{IODev} );

  my $code = $hash->{ID};
  $code = $iodev ."-". $code if( defined($iodev) );
  my $d = $modules{HUEDevice}{defptr}{$code};
  return "HUEDevice device $hash->{ID} on HUEBridge $iodev already defined as $d->{NAME}."
         if( defined($d)
             && $d->{IODev} && $hash->{IODev} && $d->{IODev} == $hash->{IODev}
             && $d->{NAME} ne $name );

  $modules{HUEDevice}{defptr}{$code} = $hash;

  if( AttrVal($iodev, "pollDevices", 1) ) {
    $interval = undef unless defined($interval);

  } elsif( !$hash->{helper}->{devtype} ||  $hash->{helper}->{devtype} ne 'G' ) {
    $interval = 60 unless defined($interval);

  }

  $args[3] = "" if( !defined( $args[3] ) );
  if( !$hash->{helper}->{devtype} ) {
    $hash->{DEF} = "$id $args[3] IODev=$iodev" if( $iodev );

    $interval = 60 if( defined($interval) && $interval < 10 );
    $hash->{INTERVAL} = $interval;

    $hash->{helper}{on} = -1;
    $hash->{helper}{reachable} = undef;
    $hash->{helper}{colormode} = '';
    $hash->{helper}{bri} = -1;
    $hash->{helper}{ct} = -1;
    $hash->{helper}{hue} = -1;
    $hash->{helper}{sat} = -1;
    $hash->{helper}{xy} = '';
    $hash->{helper}{alert} = '';
    $hash->{helper}{effect} = '';
    $hash->{helper}{v2effect} = '';
    $hash->{helper}{dynamics_status} = '';

    $hash->{helper}{pct} = -1;
    $hash->{helper}{rgb} = "";

    $hash->{helper}{battery} = -1;

    $hash->{helper}{mode} = '';

    $hash->{helper}{lastseen} = '';

    $attr{$name}{devStateIcon} = '{(HUEDevice_devStateIcon($name),"toggle")}' if( !defined( $attr{$name}{devStateIcon} ) );

    my $icon_path = AttrVal("WEB", "iconPath", "default:fhemSVG:openautomation" );
    $attr{$name}{'color-icons'} = 2 if( !defined( $attr{$name}{'color-icons'} ) && $icon_path =~ m/openautomation/ );

  } elsif( $hash->{helper}->{devtype} eq 'G' ) {
    $hash->{DEF} = "group $id $args[3] IODev=$iodev" if( $iodev );

    $interval = 60 if( defined($interval) && $interval < 10 );
    $hash->{INTERVAL} = $interval;

    $hash->{helper}{all_on} = -1;
    $hash->{helper}{any_on} = -1;

    $attr{$name}{delayedUpdate} = 1 if( !defined( $attr{$name}{delayedUpdate} ) );

    $attr{$name}{devStateIcon} = '{(HUEDevice_devStateIcon($name),"toggle")}' if( !defined( $attr{$name}{devStateIcon} ) );

    my $icon_path = AttrVal("WEB", "iconPath", "default:fhemSVG:openautomation" );
    $attr{$name}{'color-icons'} = 2 if( !defined( $attr{$name}{'color-icons'} ) && $icon_path =~ m/openautomation/ );

    addToDevAttrList($name, "createActionReadings:1,0");
    addToDevAttrList($name, "createGroupReadings:1,0");

  } elsif( $hash->{helper}->{devtype} eq 'S' ) {
    $hash->{DEF} = "sensor $id $args[3] IODev=$iodev" if( $iodev );

    $interval = 60 if( defined($interval) && $interval < 1 );
    $hash->{INTERVAL} = $interval;

    $hash->{helper}{state} = '';
  }

  RemoveInternalTimer($hash);
  if( $init_done ) {
    HUEDevice_GetUpdate($hash);

  } else {
    InternalTimer(gettimeofday()+10, "HUEDevice_GetUpdate", $hash, 0) if( $hash->{INTERVAL} );

  }

  return undef;
}

sub
HUEDevice_Undefine($$)
{
  my ($hash,$arg) = @_;

  RemoveInternalTimer($hash);

  my $code = $hash->{ID};
     $code = $hash->{IODev}->{NAME} ."-". $code if( defined($hash->{IODev}) );

  delete($modules{HUEDevice}{defptr}{$code});

  return undef;
}

sub
HUEDevice_AddJson($$@)
{
  my ($name, $obj, $json) = @_;

  my $o = eval { JSON->new->utf8(0)->decode($json) };
  if( $@ ) {
    Log3 $name, 2, "$name: json error: $@ in $json";

  } elsif( $json !~ /\{.*\}/ ) {
    Log3 $name, 2, "$name: json error: $json";

  } else {
    foreach my $key ( keys %{$o} ) {
      $obj->{$key} = $o->{$key};
    }
  }

  return $obj;
}
sub
HUEDevice_SetParam($$@)
{
  my ($name, $obj, $cmd, $value, @aa) = @_;
  my ($value2) = @aa;

  if( $cmd eq "color" ) {
    $value = int(1000000/$value);
    $cmd = 'ct';
  } elsif( $name && $cmd eq "toggle" ) {
    $cmd = ReadingsVal($name,"onoff",1) ? "off" :"on";
  } elsif( $cmd =~ m/^dim(\d+)/ ) {
    $value2 = $value;
    $value = $1;
    $value =   0 if( $value <   0 );
    $value = 100 if( $value > 100 );
    $cmd = 'pct';
  } elsif( !defined($value) && $cmd =~ m/^(\d+)/) {
    $value2 = $value;
    $value = $1;
    $value =   0 if( $value < 0 );
    $value = 254 if( $value > 254 );
    $cmd = 'bri';
  }

  my $subtype = "extcolordimmer";
  if( $name ) {
    $subtype = AttrVal($name, "subType", $subtype);
    if( $cmd eq 'up' ) {
      $cmd = 'pct';
      $value = 100;

    } elsif( $cmd eq 'down' ) {
      $cmd = 'pct';
      $value = 0;

    } elsif( $cmd eq 'pct' && $value == 0 && $subtype ne 'blind' ) {
      $cmd = "off";
      $value = $value2;

    }
  }

  if($cmd eq 'on') {
    $obj->{'on'}  = JSON::true;
    # temporary disable for everything. hast do be disabled for groups.
    # see https://forum.fhem.de/index.php/topic,11020.msg497825.html#msg497825
    #$obj->{'bri'} = 254 if( $name && ReadingsVal($name,"bri","0") eq 0 && AttrVal($name, 'subType', 'dimmer') ne 'switch'  );
    $obj->{'transitiontime'} = $value * 10 if( defined($value) );

  } elsif($cmd eq 'off') {
    $obj->{'on'}  = JSON::false;
    $obj->{'transitiontime'} = $value * 10 if( defined($value) );

  } elsif($cmd eq "pct") {
    if( $subtype  eq 'blind' ) {
      $obj->{'pct'}  = int($value);
    }

    my $bri;
    if( $value > 50 ) {
      $bri = 2.57 * ($value-50) + 128;
    } else {
      $bri = 2.59 * ($value-50) + 128;
    }
    $bri = 0 if( $bri < 0 );
    $bri = 254 if( $bri > 254 );
    $obj->{'on'}  = JSON::true;
    $obj->{'bri'}  = int($bri);
    $obj->{'transitiontime'} = $value2 * 10 if( defined($value2) );

  } elsif($cmd eq "bri") {
    #$value = 8 if( $value < 8 && AttrVal($name, "model", "") eq "LWL001" );
    $obj->{'on'}  = JSON::true;
    $obj->{'bri'}  = 0+$value;
    $obj->{'transitiontime'} = $value2 * 10 if( defined($value2) );

  } elsif($name && $cmd eq "dimUp") {
    if( $defs{$name}->{IODev}->{helper}{apiversion} && $defs{$name}->{IODev}->{helper}{apiversion} >= (1<<16) + (7<<8) ) {
      $obj->{'on'}  = JSON::true if( !$defs{$name}->{helper}{on} );
      $obj->{'bri_inc'}  = 25;
      $obj->{'bri_inc'} = 0+$value if( defined($value) );
      #$obj->{'transitiontime'} = 1;
      #$defs{$name}->{helper}->{update_timeout} = 0;
    } else {
      my $bri = ReadingsVal($name,"bri","0");
      $bri += 25;
      $bri = 254 if( $bri > 254 );
      $obj->{'on'}  = JSON::true if( !$defs{$name}->{helper}{on} );
      $obj->{'bri'}  = 0+$bri;
      $obj->{'transitiontime'} = 1;
      #$obj->{'transitiontime'} = $value * 10 if( defined($value) );
      $defs{$name}->{helper}->{update_timeout} = 0;
    }

  } elsif($name && $cmd eq "dimDown") {
    if( $defs{$name}->{IODev}->{helper}{apiversion} && $defs{$name}->{IODev}->{helper}{apiversion} >= (1<<16) + (7<<8) ) {
      $obj->{'on'}  = JSON::true if( !$defs{$name}->{helper}{on} );
      $obj->{'bri_inc'}  = -25;
      $obj->{'bri_inc'} = 0-$value if( defined($value) );
      #$obj->{'transitiontime'} = 1;
      #$defs{$name}->{helper}->{update_timeout} = 0;
    } else {
      my $bri = ReadingsVal($name,"bri","0");
      $bri -= 25;
      $bri = 0 if( $bri < 0 );
      $obj->{'on'}  = JSON::true if( !$defs{$name}->{helper}{on} );
      $obj->{'bri'}  = 0+$bri;
      $obj->{'transitiontime'} = 1;
      #$obj->{'transitiontime'} = $value * 10 if( defined($value) );
      $defs{$name}->{helper}->{update_timeout} = 0;
    }

  } elsif($cmd eq "satUp") {
      $obj->{'on'}  = JSON::true if( $name && !$defs{$name}->{helper}{on} );
      $obj->{'sat_inc'}  = 25;
      $obj->{'sat_inc'} = 0+$value if( defined($value) );
  } elsif($cmd eq "satDown") {
      $obj->{'on'}  = JSON::true if( $name && !$defs{$name}->{helper}{on} );
      $obj->{'sat_inc'}  = -25;
      $obj->{'sat_inc'} = 0+$value if( defined($value) );

  } elsif($cmd eq "hueUp") {
      $obj->{'on'}  = JSON::true if( $name && !$defs{$name}->{helper}{on} );
      $obj->{'hue_inc'}  = 6553;
      $obj->{'hue_inc'} = 0+$value if( defined($value) );
  } elsif($cmd eq "hueDown") {
      $obj->{'on'}  = JSON::true if( $name && !$defs{$name}->{helper}{on} );
      $obj->{'hue_inc'}  = -6553;
      $obj->{'hue_inc'} = 0+$value if( defined($value) );

  } elsif($cmd eq "ctUp") {
      $obj->{'on'}  = JSON::true if( $name && !$defs{$name}->{helper}{on} );
      $obj->{'ct_inc'}  = 16;
      $obj->{'ct_inc'} = 0+$value if( defined($value) );
  } elsif($cmd eq "ctDown") {
      $obj->{'on'}  = JSON::true if( $name && !$defs{$name}->{helper}{on} );
      $obj->{'ct_inc'}  = -16;
      $obj->{'ct_inc'} = 0+$value if( defined($value) );

  } elsif($cmd eq "ct") {
    $obj->{'on'}  = JSON::true;
    $value = int(1000000/$value) if( $value > 1000 );
    $obj->{'ct'}  = 0+$value;
    $obj->{'transitiontime'} = $value2 * 10 if( defined($value2) );
  } elsif($cmd eq "hue") {
    $obj->{'on'}  = JSON::true;
    $obj->{'hue'}  = 0+$value;
    $obj->{'transitiontime'} = $value2 * 10 if( defined($value2) );
  } elsif($cmd eq "sat") {
    $obj->{'on'}  = JSON::true;
    $obj->{'sat'}  = 0+$value;
    $obj->{'transitiontime'} = $value2 * 10 if( defined($value2) );
  } elsif($cmd eq "xy" && $value =~ m/^(.+),(.+)/) {
    my ($x,$y) = ($1, $2);
    $obj->{'on'}  = JSON::true;
    $obj->{'xy'}  = [0+$x, 0+$y];
    $obj->{'transitiontime'} = $value2 * 10 if( defined($value2) );
  } elsif( $cmd eq "rgb" && $value =~ m/^(..)(..)(..)/) {
    my( $r, $g, $b ) = (hex($1)/255.0, hex($2)/255.0, hex($3)/255.0);

    my $hash = $defs{$name};
    if( $name && ( !AttrVal($name, "model", undef)
                   || AttrVal($name, "model", undef) eq 'LLC020'
                   || ($hash && $hash->{IODev} &&  $hash->{IODev}{TYPE} eq 'tradfri' ) ) ) {
      my( $h, $s, $v ) = Color::rgb2hsv($r,$g,$b);

      $obj->{'on'}  = JSON::true;
      $obj->{'hue'} = int( $h * 65535 );
      $obj->{'sat'} = int( $s * 254 );
      $obj->{'bri'} = int( $v * 254 );
    } else {
      # calculation from http://www.everyhue.com/vanilla/discussion/94/rgb-to-xy-or-hue-sat-values/p1

      my $X =  1.076450 * $r - 0.237662 * $g + 0.161212 * $b;
      my $Y =  0.410964 * $r + 0.554342 * $g + 0.034694 * $b;
      my $Z = -0.010954 * $r - 0.013389 * $g + 1.024343 * $b;
      #Log3 $name, 3, "rgb: ". $r . " " . $g ." ". $b;
      #Log3 $name, 3, "XYZ: ". $X . " " . $Y ." ". $Y;

      if( $X != 0
          || $Y != 0
          || $Z != 0 ) {
        my $x = $X / ($X + $Y + $Z);
        my $y = $Y / ($X + $Y + $Z);
        #Log3 $name, 3, "xyY:". $x . " " . $y ." ". $Y;

        $Y = 1 if( $Y > 1 );

        $x = 0 if( $x < 0);
        $x = 1 if( $x > 1);
        $y = 0 if( $y < 0);
        $y = 1 if( $y > 1);

        my $bri  = maxNum($r,$g,$b);
        #my $bri  = $Y;

        $obj->{'on'}  = JSON::true;
        $obj->{'xy'}  = [0+$x, 0+$y];
        $obj->{'bri'}  = int(254*$bri);
      } else {
        $obj->{'on'}  = JSON::false;
      }
    }
  } elsif( $cmd eq "hsv" && $value =~ m/^(..)(..)(..)/) {
    my( $h, $s, $v ) = (hex($1), hex($2), hex($3));

    $s = 254 if( $s > 254 );
    $v = 254 if( $v > 254 );

    $obj->{'on'}  = JSON::true;
    $obj->{'hue'}  = int($h*256);
    $obj->{'sat'}  = 0+$s;
    $obj->{'bri'}  = 0+$v;

  } elsif( $cmd eq "alert" ) {
    $obj->{'alert'}  = $value;

  } elsif( $cmd eq "effect" ) {
    $obj->{'on'}  = JSON::true;
    $obj->{'effect'}  = $value;

    if( defined($value2) ) {
      my $json = join( ' ', @aa);
      HUEDevice_AddJson( $name, $obj, $json );
    }

  } elsif( $cmd eq "transitiontime" ) {
    $obj->{'transitiontime'} = 0+$value;
  } elsif( $name &&  $cmd eq "delayedUpdate" ) {
    $defs{$name}->{helper}->{update_timeout} = 1;
  } elsif( $name &&  $cmd eq "immediateUpdate" ) {
    $defs{$name}->{helper}->{update_timeout} = 0;
  } elsif( $name &&  $cmd eq "noUpdate" ) {
    $defs{$name}->{helper}->{update_timeout} = -1;

  } elsif( $cmd eq 'stop' && $subtype  eq 'blind' ) {
    $obj->{stop} = JSON::true;

  } elsif( $cmd eq 'habridgeupdate' ) {
    $obj->{habridgeupdate} = JSON::true;

  } elsif( $cmd =~ /\{/ ) {
    $value='' if( !$value );
    HUEDevice_AddJson( $name, $obj, "$cmd$value ".join( ' ', @aa) );

  } elsif( $cmd eq 'v2effect' ) {
    my $hash = $defs{$name};
    my $iohash = $hash->{IODev};
    return "IODev missing" if( !$iohash );

    my $id = HUEBridge_V2IdOfV1Id( $iohash, 'light', "/lights/$hash->{ID}" );
    HUEBridge_Set( $iohash, $iohash->{NAME}, $cmd, $id, $value );

    $obj->{'on'}  = JSON::true;

  } else {

    return 0;
  }

  #Log3 $name, 5, "$name: ". Dumper $obj if($HUEDevice_hasDataDumper);

  return 1;
}
sub HUEDevice_Set($@);
sub
HUEDevice_Set($@)
{
  my ($hash, $name, @aa) = @_;
  my ($cmd, @args) = @aa;

  my %obj;
  my @match;
  my $entries;

  $hash->{helper}->{update_timeout} =  AttrVal($name, "delayedUpdate", 1);

  if( $hash->{helper}->{devtype} eq 'G' ) {
    if( $cmd eq "statusRequest" ) {
      delete $hash->{lights}; # force .associatedWith refresh

      RemoveInternalTimer($hash);
      HUEDevice_GetUpdate($hash);
      return undef;

    } elsif( $cmd eq 'lights' ) {
      return "usage: lights <lights>" if( @args != 1 );

      my $obj = { 'lights' => HUEBridge_string2array($args[0]), };

      my $result = HUEDevice_ReadFromServer($hash,$hash->{ID},$obj);
      if( $result->{success} ) {
        RemoveInternalTimer($hash);
        HUEDevice_GetUpdate($hash);
      }

      return $result->{error}{description} if( $result->{error} );
      return undef;

    } elsif( $cmd eq 'addlight' || $cmd eq 'addlights' ) {
      return "usage: $cmd <lights>" if( @args != 1 );

      my $obj = { 'lights' => HUEBridge_string2array("$hash->{lights},$args[0]"), };

      my $result = HUEDevice_ReadFromServer($hash,$hash->{ID},$obj);
      if( $result->{success} ) {
        RemoveInternalTimer($hash);
        HUEDevice_GetUpdate($hash);
      }

      return $result->{error}{description} if( $result->{error} );
      return undef;

    } elsif( $cmd eq 'removelight' || $cmd eq 'removelights' ) {
      return "usage: $cmd <lights>" if( @args != 1 );

      my $current = HUEBridge_string2array($hash->{lights});
      my %to_remove;
         @to_remove{@{HUEBridge_string2array($args[0])}} = undef;
      
      my @new = grep {not exists $to_remove{$_}} @{$current};

      my $obj = { 'lights' => \@new };

      my $result = HUEDevice_ReadFromServer($hash,$hash->{ID},$obj);
      if( $result->{success} ) {
        RemoveInternalTimer($hash);
        HUEDevice_GetUpdate($hash);
      }

      return $result->{error}{description} if( $result->{error} );
      return undef;

    } elsif( $cmd eq 'savescene' ) {
      if( $hash->{IODev} && $hash->{IODev}{helper}{apiversion} && $hash->{IODev}{helper}{apiversion} >= (1<<16) + (11<<8) ) {
        return "usage: savescene <name>" if( @args < 1 );

        return fhem( "set $hash->{IODev}{NAME} savescene ". join( ' ', @aa[1..@aa-1]). " $hash->{NAME}" );

      } else {
        return "usage: savescene <id>" if( @args != 1 );

        return fhem( "set $hash->{IODev}{NAME} savescene $aa[1] $aa[1] $hash->{NAME}" );

      }

    } elsif( $cmd eq 'deletescene' ) {
      return "usage: deletescene <id>" if( @args != 1 );

      return fhem( "set $hash->{IODev}{NAME} deletescene $aa[1]" );

    } elsif( $cmd eq 'scene' ) {
      return "usage: $cmd <id>|<name>" if( !@args || $args[0] eq '?' );
      my $arg = join( ' ', @args );
      my $deConz;
      if( $hash->{IODev} ) {
        if( $hash->{IODev}{is_deCONZ} ) {
          $deConz = 1;
          $arg = HUEBridge_scene2id_deCONZ($hash, $arg);
        } else {
          $arg = HUEBridge_scene2id($hash->{IODev}, $arg);
        }
      }

      my $obj = {'scene' => $arg};
      $hash->{helper}->{update} = 1;
      my $result;
      $result = HUEDevice_ReadFromServer($hash,"$hash->{ID}/action",$obj) if( !$deConz );
      $result = HUEDevice_ReadFromServer($hash,"$hash->{ID}/scenes/$arg/recall",$obj) if( $deConz );
      return $result->{error}{description} if( $result->{error} );

      if( defined($result) && $result->{'error'} ) {
        $hash->{STATE} = $result->{'error'}->{'description'};
        return undef;
      }

      return undef if( !defined($result) );

      if( $hash->{helper}->{update_timeout} == -1 ) {
      } elsif( $hash->{helper}->{update_timeout} ) {
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday()+$hash->{helper}->{update_timeout}, "HUEDevice_GetUpdate", $hash, 0);
      } else {
        RemoveInternalTimer($hash);
        HUEDevice_GetUpdate( $hash );
      }
      return undef;

    } elsif( $cmd eq 'v2scene' ) {
      return "<$name has no IODEV>" if( !$hash->{IODev} );
      return "$name: v2 api not supported" if( !$hash->{IODev} || !$hash->{IODev}{has_v2_api} );
      return "usage: $cmd <v2 scene id>" if( !@args || $args[0] eq '?' );

      my $arg = join( ' ', @args );

      my $v2id;
      if( $arg =~ /([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/ ) {
        $v2id = $1;

        return "no v2 scene with id $v2id found" if( !HUEBridge_nameOfResource( $hash->{IODev}, $v2id ) );

      } else {
        return "$arg is not a v2 scene id";

      }

      return CommandSet( $hash->{IODev}, "$hash->{IODev}->{NAME} v2scene $v2id" );
    }

  } elsif( $hash->{helper}->{devtype} eq 'S' ) {
    my $iohash = $hash->{IODev};
    return "IODev missing" if( !$iohash );

    my $id = $hash->{ID};
    $id = $1 if( $id =~ m/^S(\d.*)/ );

    $hash->{".triggerUsed"} = 1;

    $cmd = 'configsensor' if( $cmd eq 'config' );

    if( $cmd eq "statusRequest" ) {
      RemoveInternalTimer($hash);
      HUEDevice_GetUpdate($hash);
      return undef;

    } elsif( $cmd eq 'setsensor' || $cmd eq 'configsensor' ) {
      return "usage: $cmd <json>" if( !@args );
      return HUEBridge_Set( $iohash, $iohash->{NAME}, $cmd, $id, @args );

    } elsif( $cmd eq 'json' ) {
      return "usage: json [setsensor|configsensor] <json>" if( !@args );
      my $type = 'updatesensor';
      if( $args[0] eq 'setsensor' || $args[0] eq 'configsensor' ) {
        $type = shift @args;
       }
      return HUEBridge_Set( $iohash, $iohash->{NAME}, $type, $id, @args );

    } elsif( @match = grep { $cmd eq $_ } keys %{($hash->{helper}{setList}{cmds}?$hash->{helper}{setList}{cmds}:{})} ) {
      return HUEBridge_Set( $iohash, $iohash->{NAME}, 'setsensor', $id, $hash->{helper}{setList}{cmds}{$match[0]} );

    } elsif( $entries = $hash->{helper}{setList}{regex} ) {
      foreach my $entry (@{$entries}) {
        if( join(' ', @aa) =~ /$entry->{regex}/ ) {
          my $VALUE1 = $1;
          my $VALUE2 = $2;
          my $VALUE3 = $3;
          my $json = $entry->{json};
          if( $json =~ m/^perl:\{(.*)\}$/ ) {
            $json = eval $json;
            if($@) {
              Log3 $name, 3, "$name: setList: ". join(' ', @aa). ": ". $@;
              return "error: ". join(' ', @aa). ": ". $@;
            }
          } else {
            $json =~ s/\$1/$VALUE1/;
            $json =~ s/\$2/$VALUE2/;
            $json =~ s/\$3/$VALUE3/;
          }
          return HUEBridge_Set( $iohash, $iohash->{NAME}, 'setsensor', $id, $json );

        }
      }

    } elsif( @match = grep { $cmd eq $_ } keys %{($hash->{helper}{configList}{cmds}?$hash->{helper}{configList}{cmds}:{})} ) {
      return HUEBridge_Set( $iohash, $iohash->{NAME}, 'configsensor', $id, $hash->{helper}{configList}{cmds}{$match[0]} );

    } elsif( $entries = $hash->{helper}{configList}{regex} ) {
      foreach my $entry (@{$entries}) {
        if( join(' ', @aa) =~ /$entry->{regex}/ ) {
          my $VALUE1 = $1;
          my $VALUE2 = $2;
          my $VALUE3 = $3;
          my $json = $entry->{json};
          if( $json =~ m/^perl:\{(.*)\}$/ ) {
            $json = eval $json;
            if($@) {
              Log3 $name, 3, "$name: configList: ". join(' ', @aa). ": ". $@;
              return "error: ". join(' ', @aa). ": ". $@;
            }
          } else {
            $json =~ s/\$1/$VALUE1/;
            $json =~ s/\$2/$VALUE2/;
            $json =~ s/\$3/$VALUE3/;
          }
          return HUEBridge_Set( $iohash, $iohash->{NAME}, 'configsensor', $id, $json );

        }
      }
    }

    my $list = 'statusRequest:noArg';
    $list .= ' json' if( $hash->{type} && $hash->{type} =~ /^CLIP/ );
    $list .= ' '. join( ':noArg ', keys %{$hash->{helper}{setList}{cmds}} ) if( $hash->{helper}{setList}{cmds} );
    $list .= ':noArg' if( $hash->{helper}{setList}{cmds} );
    if( my $entries = $hash->{helper}{setList}{regex} ) {
      foreach my $entry (@{$entries}) {
        $list .= ' ';
        $list .= (split( ' ', $entry->{regex} ))[0];
        $list .= ":$entry->{opts}" if( $entry->{opts} );
      }
    }
    $list .= ' '. join( ':noArg ', keys %{$hash->{helper}{configList}{cmds}} ) if( $hash->{helper}{configList}{cmds} );
    $list .= ':noArg' if( $hash->{helper}{configList}{cmds} );
    if( my $entries = $hash->{helper}{configList}{regex} ) {
      foreach my $entry (@{$entries}) {
        $list .= ' ';
        $list .= (split( ' ', $entry->{regex} ))[0];
        $list .= ":$entry->{opts}" if( $entry->{opts} );
      }
    }

    return SetExtensions($hash, $list, $name, @aa);
  }

  $cmd = 'configlight' if( $cmd eq 'config' );

  if( $cmd eq 'rename' ) {
    my $new_name =  join( ' ', @aa[1..@aa-1]);
    my $obj = { 'name' => $new_name, };

    my $result = HUEDevice_ReadFromServer($hash,$hash->{ID},$obj);
    if( $result->{success} ) {
      RemoveInternalTimer($hash);
      HUEDevice_GetUpdate($hash);
      CommandAttr(undef,"$name alias $new_name");
      CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );
    }

    return $result->{error}{description} if( $result->{error} );
    return undef;

  } elsif( $cmd eq 'setlight' || $cmd eq 'configlight' ) {
    return "usage: $cmd <json>" if( !@args );
    my $iohash = $hash->{IODev};
    return "IODev missing" if( !$iohash );
    return HUEBridge_Set( $iohash, $iohash->{NAME}, $cmd, $hash->{ID}, @args );

  }

  if( (my $joined = join(" ", @aa)) =~ /:/ ) {
    $joined =~ s/on-till\s+[^\s]+//g; #bad workaround for: https://forum.fhem.de/index.php/topic,61636.msg728557.html#msg728557
    $joined =~ s/on-till-overnight\s+[^\s]+//g; #same bad workaround for: https://forum.fhem.de/index.php/topic,61636.msg1110193
    my @cmds = split(":", $joined);
    while( @cmds ) {
      my $cmd = shift(@cmds);

      if( $cmd =~ m/{/ ) { # } for match
        my $count = 0;
        for my $i (0..length($cmd)-1) {
          my $c = substr($cmd, $i, 1);
          ++$count if( $c eq '{' );
          --$count if( $c eq '}' );
        }

        while( $cmd && $count != 0 ) {
          my $next = shift(@cmds);
          last if( !defined($next) );
          $cmd .= ':' . $next;

          for my $i (0..length($next)-1) {
            my $c = substr($next, $i, 1);
            ++$count if( $c eq '{' );
            --$count if( $c eq '}' );
          }
        }
      }

      HUEDevice_SetParam($name, \%obj, split(" ", $cmd) );
    }
  } else {
    my ($cmd, $value, $value2, @a) = @aa;

    if( $cmd eq "statusRequest" ) {
      RemoveInternalTimer($hash);
      HUEDevice_GetUpdate($hash);
      return undef;
    }

    HUEDevice_SetParam($name, \%obj, $cmd, $value, $value2, @a);
  }

  if( %obj ) {
    if( defined($obj{on}) ) {
      $hash->{desired} = $obj{on}?1:0;

      if( defined($hash->{lights}) ) {
        foreach my $light ( split(',', $hash->{lights}) ) {
          next if( !$light );
          my $code = $light;
             $code = $hash->{IODev}->{NAME} ."-". $code if( defined($hash->{IODev}) );
          next if( !defined($modules{HUEDevice}{defptr}{$code}) );
          $modules{HUEDevice}{defptr}{$code}->{desired} = $hash->{desired};
        }
      }
    }

    if( !defined($obj{transitiontime}) ) {
      my $transitiontime = AttrVal($name, "transitiontime", undef);

      $obj{transitiontime} = 0 + $transitiontime if( defined( $transitiontime ) );
    }
  }

#  if( $hash->{helper}->{update_timeout} == -1 ) {
#    my $diff;
#    my ($seconds, $microseconds) = gettimeofday();
#    if( $hash->{helper}->{timestamp} ) {
#      my ($seconds2, $microseconds2) = @{$hash->{helper}->{timestamp}};
#
#      $diff = (($seconds-$seconds2)*1000000 + $microseconds-$microseconds2)/1000;
#    }
#    $hash->{helper}->{timestamp} = [$seconds, $microseconds];
#
#    return undef if( $diff < 100 );
#  }

  if( scalar keys %obj ) {
    my $result;
    if( $hash->{helper}->{devtype} eq 'G' ) {
      $hash->{helper}->{update} = 1;
      $result = HUEDevice_ReadFromServer($hash,"$hash->{ID}/action",\%obj);
    } elsif( defined( $obj{habridgeupdate} ) ) {
      $result = HUEDevice_ReadFromServer($hash,"$hash->{ID}/bridgeupdatestate",\%obj);
    } else {
      $result = HUEDevice_ReadFromServer($hash,"$hash->{ID}/state",\%obj);
    }

    SetExtensionsCancel($hash);

    if( defined($result) && $result->{'error'} ) {
      $hash->{STATE} = $result->{'error'}->{'description'};
      return undef;
    }

    $hash->{".triggerUsed"} = 1;
    return undef if( !defined($result) );

    if( $hash->{helper}->{update_timeout} == -1 ) {
    } elsif( $hash->{helper}->{update_timeout} ) {
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+$hash->{helper}->{update_timeout}, "HUEDevice_GetUpdate", $hash, 0);
    } else {
      RemoveInternalTimer($hash);
      HUEDevice_GetUpdate( $hash );
    }

    return undef;
  }

  my $subtype = AttrVal($name, "subType", "extcolordimmer");

  my $list = "off:noArg on:noArg toggle:noArg statusRequest:noArg";
  $list .= " pct:colorpicker,BRI,0,1,100 bri:colorpicker,BRI,0,1,254" if( $subtype =~ m/dimmer/ );
  $list .= " rgb:colorpicker,RGB" if( $subtype =~ m/color/ );
  $list .= " color:colorpicker,CT,2000,1,6500 ct:colorpicker,CT,154,1,500" if( $subtype =~ m/ct|ext/ );
  $list .= " hue:colorpicker,HUE,0,1,65535 sat:slider,0,1,254 xy" if( $subtype =~ m/color/ );

  $list = 'up:noArg stop:noArg down:noArg pct:colorpicker,BRI,0,1,100' if( $subtype eq 'blind' );

  if( $hash->{IODev} && $hash->{IODev}{helper}{apiversion} && $hash->{IODev}{helper}{apiversion} >= (1<<16) + (7<<8) ) {
    $list .= " dimUp:noArg dimDown:noArg" if( $subtype =~ m/dimmer/ );
    $list .= " ctUp:noArg ctDown:noArg" if( $subtype =~ m/ct|ext/ );
    $list .= " hueUp:noArg hueDown:noArg satUp:noArg satDown:noArg" if( $subtype =~ m/color/ );
  } elsif( !$hash->{helper}->{devtype} && $subtype =~ m/dimmer/ ) {
    $list .= " dimUp:noArg dimDown:noArg";
  }

  #$list .= " dim06% dim12% dim18% dim25% dim31% dim37% dim43% dim50% dim56% dim62% dim68% dim75% dim81% dim87% dim93% dim100%" if( $subtype =~ m/dimmer/ );

  if( $hash->{IODev} && $hash->{IODev}{TYPE} eq 'HUEBridge' ) {
    $list .= " alert:none,select,lselect";
    $list .= ",breathe,okay,channelchange,finish,stop" if( $hash->{IODev}{is_deCONZ} );

    $list .= " effect:none,colorloop" if( $subtype =~ m/color/ );

    $list .= " lights addlight removelight" if( $hash->{helper}->{devtype} eq 'G' );

    $list .= " rename";
    #$list .= " setlight configlight config" if( !$hash->{helper}->{devtype} );

    if( $hash->{helper}->{devtype} eq 'G' ) {
      $list .= " savescene deletescene";
    }

    if( $hash->{IODev}{has_v2_api} ) {
      my $id = HUEBridge_V2IdOfV1Id( $hash->{IODev}, 'light', "/lights/$hash->{ID}" );

      if( $id
          && $hash->{IODev}{helper}{resource}{by_id}{$id}
          && $hash->{IODev}{helper}{resource}{by_id}{$id}{effects} ) {
        $list .= eval { " v2effect:". join(',', @{$hash->{IODev}{helper}{resource}{by_id}{$id}{effects}{effect_values}} ) };
        if($@) {
          Log3 $name, 2, "$name: error reading effects: ". $@;
        }
      }
    }
  }

  if( $hash->{IODev} && $hash->{IODev}{is_deCONZ} ) {
    if( my $scenes = $hash->{helper}{scenes} ) {
      my @names;
      for my $scene (@{$scenes}) {
         push(@names, $scene->{name});
      }
      # my $s_scenes = join (",",(my $names = map { $_->{name}} @$scenes));
      my $scenes = join (',', @names);
      $scenes =~ s/ /#/g;
      $list .= " scene:". $scenes;
    }

  } elsif( my $scenes = $hash->{IODev}{helper}{scenes} ) {
    local *containsOneOfMyLights = sub($) {
      return 1 if( !defined($hash->{helper}{lights}) );

      my( $lights ) = @_;

      foreach my $light (@{$lights}) {
        return 1 if( defined($hash->{helper}{lights}{$light}) );
      }
      return 0;
    };
    my %count;
    map { $count{$scenes->{$_}{name}}++ } keys %{$scenes};
    $list .= " scene:". join(",", sort grep { defined } map { if( !containsOneOfMyLights($scenes->{$_}{lights}) ) {
                                                                undef;
                                                              } else {
                                                                my $scene = $scenes->{$_}{name};
                                                                if( $count{$scene} > 1 ) {
                                                                  $scene .= " [id=$_]";
                                                                 }
                                                                $scene =~ s/ /#/g; $scene;
                                                              }
                                                            } keys %{$scenes} );

  } else {
    $list .= " scene";

  }

  if( $hash->{IODev} && $hash->{IODev}{has_v2_api} ) {
    my $iohash = $hash->{IODev};
    my $id = $hash->{ID}; $id = $1 if( $id =~ m/^G(\d.*)/ );
    my $v2id = HUEBridge_V2IdOfV1Id( $iohash, 'room', "/groups/$id" );
       $v2id = HUEBridge_V2IdOfV1Id( $iohash, 'zone', "/groups/$id" ) if( !$v2id );
       $v2id = HUEBridge_V2IdOfV1Id( $iohash, 'group', "/groups/$id" ) if( !$v2id );
       #$v2id = HUEBridge_V2IdOfV1Id( $iohash, 'grouped_light', "/groups/$id" ) if( !$v2id );

    my $scenes = '';
    if( my $resources = $iohash->{helper}{resource}{by_id} ) {
      foreach my $scene ( values %{$resources} ) {
        next if( !$scene->{type} );
        next if( $scene->{type} ne 'scene' );
        local *containsOneOfMyLights = sub($) {
          return 1 if( !defined($hash->{helper}{lights}) );

          my( $scene ) = @_;


          foreach my $light (keys %{$hash->{helper}{lights}}) {
            my $id = HUEBridge_V2IdOfV1Id( $iohash, 'light', "/lights/$light" );
            foreach my $action (@{$scene->{actions}}) {
              return 1 if( $id eq $action->{target}{rid}  );
            }
          }
          return 0;
        };

        next if( !$v2id ); #fixme: optimize!
        next if( $v2id ne $scene->{group}{rid} );
        #next if( !containsOneOfMyLights($scene) );

        $scenes .= ',' if( $scenes );
        $scenes .= $scene->{metadata}{name};
        $scenes .= " [$scene->{id}]";

      }
      $scenes =~ s/ /#/g;
      $list .= " v2scene:$scenes" if( $scenes );
    }
  }

  return SetExtensions($hash, $list, $name, @aa);
}

sub
HUEDevice_cttorgb($)
{
  my ($ct) = @_;

  # calculation from http://www.tannerhelland.com/4435/convert-temperature-rgb-algorithm-code
  # adjusted by 1000K
  my $temp = (1000000/$ct)/100 + 10;

  my $r = 0;
  my $g = 0;
  my $b = 0;

  $r = 255;
  $r = 329.698727446 * ($temp - 60) ** -0.1332047592 if( $temp > 66 );
  $r = 0 if( $r < 0 );
  $r = 255 if( $r > 255 );

  if( $temp <= 66 ) {
    $g = 99.4708025861 * log($temp) - 161.1195681661;
  } else {
    $g = 288.1221695283 * ($temp - 60) ** -0.0755148492;
  }
  $g = 0 if( $g < 0 );
  $g = 255 if( $g > 255 );

  $b = 255;
  $b = 0 if( $temp <= 19 );
  if( $temp < 66 ) {
    $b = 138.5177312231 * log($temp-10) - 305.0447927307;
  }
  $b = 0 if( $b < 0 );
  $b = 255 if( $b > 255 );

  return( $r, $g, $b );
}

sub
HUEDevice_xyYtorgb($$$)
{
  # calculation from http://www.brucelindbloom.com/index.html
  my ($x,$y,$Y) = @_;
#Log 3, "xyY:". $x . " " . $y ." ". $Y;

  my $r = 0;
  my $g = 0;
  my $b = 0;

  if( $y > 0 ) {
    my $X = $x * $Y / $y;
    my $Z = (1 - $x - $y)*$Y / $y;

    if( $X > 1
        || $Y > 1
        || $Z > 1 ) {
      my $f = maxNum($X,$Y,$Z);
      $X /= $f;
      $Y /= $f;
      $Z /= $f;
    }
#Log 3, "XYZ: ". $X . " " . $Y ." ". $Y;

    $r =  0.7982 * $X + 0.3389 * $Y - 0.1371 * $Z;
    $g = -0.5918 * $X + 1.5512 * $Y + 0.0406 * $Z;
    $b =  0.0008 * $X + 0.0239 * $Y + 0.9753 * $Z;

    if( $r > 1
        || $g > 1
        || $b > 1 ) {
      my $f = maxNum($r,$g,$b);
      $r /= $f;
      $g /= $f;
      $b /= $f;
    }
#Log 3, "rgb: ". $r . " " . $g ." ". $b;

    $r *= 255;
    $g *= 255;
    $b *= 255;
  }

  return( $r, $g, $b );
}

sub
HUEDevice_Get($@)
{
  my ($hash, @a) = @_;

  my $name = $a[0];
  return "$name: get needs at least one parameter" if(@a < 2);

  my $cmd= $a[1];

  if($cmd eq "rgb") {
    my $r = 0;
    my $g = 0;
    my $b = 0;

    my $cm = ReadingsVal($name,"colormode","");
    if( $cm eq "ct" ) {
      if( ReadingsVal($name,"ct","") =~ m/(\d+) .*/ ) {
        ($r,$g,$b) = HUEDevice_cttorgb($1);
      }
    } elsif( $cm eq "hs" ) {
      my $h = ReadingsVal($name,"hue",0) / 65535.0;
      my $s = ReadingsVal($name,"sat",0) / 254.0;
      my $v = ReadingsVal($name,"bri",0) / 254.0;
      ($r,$g,$b) = Color::hsv2rgb($h,$s,$v);

      $r *= 255;
      $g *= 255;
      $b *= 255;
    } elsif( ReadingsVal($name,"xy","") =~ m/(.+),(.+)/ ) {
      my ($x,$y) = ($1, $2);
      my $Y = ReadingsVal($name,"bri",0) / 254.0;

      ($r,$g,$b) = HUEDevice_xyYtorgb($x,$y,$Y);
    }
    return sprintf( "%02x%02x%02x", $r+0.5, $g+0.5, $b+0.5 );
  } elsif($cmd eq "RGB") {
    my $r = 0;
    my $g = 0;
    my $b = 0;

    my $cm = ReadingsVal($name,"colormode","");
    if( $cm eq "ct" ) {
      if( ReadingsVal($name,"ct","") =~ m/(\d+) .*/ ) {
        ($r,$g,$b) = HUEDevice_cttorgb($1);
      }
    } elsif( $cm eq "hs" ) {
      my $h = ReadingsVal($name,"hue",0) / 65535.0;
      my $s = ReadingsVal($name,"sat",0) / 254.0;
      my $v = 1;
      ($r,$g,$b) = Color::hsv2rgb($h,$s,$v);

      $r *= 255;
      $g *= 255;
      $b *= 255;
    } elsif( ReadingsVal($name,"xy","") =~ m/(.+),(.+)/ ) {
      my ($x,$y) = ($1, $2);
      my $Y = 1;

      ($r,$g,$b) = HUEDevice_xyYtorgb($x,$y,$Y);
    }
    return sprintf( "%02x%02x%02x", $r+0.5, $g+0.5, $b+0.5 );

  } elsif ( $cmd eq "startup" ) {
    my $result = IOWrite($hash,undef,$hash->{NAME},$hash->{ID});
    return $result->{error}{description} if( $result->{error} );
    return "not supported" if( !$result->{config} || !$result->{config}{startup} );
    return "$result->{config}{startup}{mode}\t$result->{config}{startup}{configured}";
    return Dumper $result->{config}{startup};

  } elsif ( $cmd eq "v2effects" ) {
    return "<$name has no IODEV>" if( !$hash->{IODev} );
    return "$name: v2 api not supported" if( !$hash->{IODev} || !$hash->{IODev}{has_v2_api} );

    my $v2id = HUEBridge_V2IdOfV1Id( $hash->{IODev}, 'light', "/lights/$hash->{ID}" );
    return '<none>' if( !$v2id );
    return CommandGet( $hash, "$hash->{IODev}->{NAME} v2effects $v2id" );

  } elsif ( $cmd eq "devStateIcon" ) {
    return HUEDevice_devStateIcon($hash);
  }


  my $list;
  $list .= "rgb:noArg RGB:noArg devStateIcon:noArg" if( $hash->{helper}->{devtype} ne 'S' );

  if( my $subtype = $attr{$name}{subType} ) {
    $list = ' devStateIcon:noArg' if( $subtype eq 'blind' );
  }

  if( !$hash->{helper}->{devtype}
      && $hash->{IODev} && $hash->{IODev}{helper}{apiversion} && $hash->{IODev}{helper}{apiversion} >= (1<<16) + (26<<8) ) {
    $list .= " startup:noArg";
  }

  $list .= " v2effects" if( !$hash->{helper}->{devtype} && $hash->{IODev} && $hash->{IODev}{has_v2_api} );

  return "Unknown argument $cmd" if( !$list );

  return "Unknown argument $cmd, choose one of $list";
}


###################################
# This could be IORead in fhem, But there is none.
# Read http://forum.fhem.de/index.php?t=tree&goto=54027&rid=10#msg_54027
# to find out why.
sub
HUEDevice_ReadFromServer($@)
{
  my ($hash,@a) = @_;
  my $name = $hash->{NAME};

  #return if(IsDummy($name) || IsIgnored($name));

  no strict "refs";
  my $ret;
  unshift(@a,$name);
  #$ret = IOWrite($hash, @a);
  $ret = IOWrite($hash,$hash,@a);
  use strict "refs";
  return $ret;
}

sub
updateFinalButtonState($)
{
  my ($hash) = @_;
  $hash->{helper}{forceUpdate} = 1;
  HUEDevice_GetUpdate($hash);
}
sub
HUEDevice_GetUpdate($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if( $hash->{helper}->{devtype} eq 'G' ) {
    my $result = HUEDevice_ReadFromServer($hash,$hash->{ID});

    if( !defined($result) ) {
      $hash->{STATE} = "unknown";
      return;
    } elsif( $result->{'error'} ) {
      $hash->{STATE} = $result->{'error'}->{'description'};
      return;
    }

    HUEDevice_Parse($hash, $result);

  } elsif( $hash->{helper}->{devtype} eq 'S' ) {
  }

  if(!$hash->{LOCAL}) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "HUEDevice_GetUpdate", $hash, 0) if( $hash->{INTERVAL} );
  }

  return undef if( $hash->{helper}->{devtype} eq 'G' );

  my $result = HUEDevice_ReadFromServer($hash,$hash->{ID});
  if( !defined($result) ) {
    $hash->{helper}{reachable} = 0;
    #$hash->{STATE} = "unknown";
    return;
  } elsif( $result->{'error'} ) {
    $hash->{helper}{reachable} = 0;
    $hash->{STATE} = $result->{'error'}->{'description'};
    return;
  }

  HUEDevice_Parse($hash, $result);
  HUEBridge_updateGroups($hash->{IODev}, $hash->{ID}) if( $hash->{IODev} && ( $hash->{IODev}{TYPE} eq 'HUEBridge'
                                                                              || $hash->{IODev}{TYPE} eq 'tradfri' ) );
}

sub
HUEDeviceSetIcon($;$)
{
  my ($hash,$force) = @_;
  $hash = $defs{$hash} if( ref($hash) ne 'HASH' );

  return undef if( !$hash );
  my $name = $hash->{NAME};

  return if( defined($attr{$name}{icon}) && !$force );

  if( defined($hash->{modelid}) ) {
    my $model = $hueModels{$hash->{modelid}};
    return undef if( !$model );

    my $icon = $model->{icon};
    return undef if( !$icon );

    $attr{$name}{icon} = $icon;

  } elsif( $hash->{class} ) {
    my $class = lc( $hash->{class} );
    $class =~ s/ room//;
    $class =~ s/ /_/;

    $attr{$name}{icon} = "hue_room_$class";

  } elsif( defined($hash->{helper}{json}) && defined($hash->{helper}{json}{config}) ) {
    my $archetype = $hash->{helper}{json}{config}{archetype};

    # TODO ...
  }
}
sub
HUEDevice_Parse($$)
{
  my($hash,$result) = @_;
  my $name = $hash->{NAME};

  if( ref($result) ne "HASH" ) {
    if( ref($result) && $HUEDevice_hasDataDumper) {
      Log3 $name, 2, "$name: got wrong status message for $name: ". Dumper $result;
      #Log3 $name, 2, "$name: got wrong status message for $name: $result";
    } else {
      Log3 $name, 2, "$name: got wrong status message for $name: $result";
    }
    return undef;
  }

  Log3 $name, 4, "parse status message for $name";
  #Log3 $name, 5, Dumper $result if($HUEDevice_hasDataDumper);

  if( !defined($hash->{has_events})                          # only if not already checked
      && ($result->{v2_service} || $result->{t}) # only for updates from events
      && defined($hash->{IODev} && $hash->{IODev}{TYPE} eq 'HUEBridge') ) {
    $hash->{has_events} = $hash->{IODev}{has_v2_api} if( defined($hash->{IODev}{has_v2_api}) );
    $hash->{has_events} = 1 if( $hash->{IODev}{is_deCONZ} );

    Log3 $name, 4, "$name: bridge has events api: ". ($hash->{has_events} ? 1 : 0);

    if( $hash->{INTERVAL} && $hash->{has_events} ) {
      if( $hash->{IODev}{websocket}
          || (defined($hash->{IODev}{EventStream}) && $hash->{IODev}{EventStream} eq 'connected' )) {
        delete $hash->{INTERVAL};
        Log3 $name, 2, "$name: bridge has events api, events connected, removing interval";

        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday()+$hash->{INTERVAL}, "HUEDevice_GetUpdate", $hash, 0) if( $hash->{INTERVAL} );

      } else {
        delete $hash->{has_events};
        Log3 $name, 2, "$name: bridge has events api, events not jet connected";

      }
    }
  }

  $hash->{name} = $result->{name} if( defined($result->{name}) );
  $hash->{type} = $result->{type} if( defined($result->{type}) );
  $hash->{class} = $result->{class} if( defined($result->{class}) );
  $hash->{uniqueid} = $result->{uniqueid} if( defined($result->{uniqueid}) );

  $hash->{v2_id} = $result->{v2_id} if( defined($result->{v2_id}) );

  $hash->{helper}{json} = $result;

  if( $hash->{helper}->{devtype} eq 'G' ) {
    #if( !defined($attr{$name}{subType}) && $hash->{type} ) {
    #  if( $hash->{type} eq 'Room' ) {
    #    $attr{$name}{subType} = 'room';
    #
    #  } elsif( $hash->{type} eq 'LightGroup' ) {
    #    $attr{$name}{subType} = 'lightgroup';
    #  }
    #}

    $hash->{helper}{scenes} = $result->{scenes} if( defined($result->{scenes}) );

    if( $result->{lights} ) {
      $hash->{helper}{lights} = {map {$_=>1} @{$result->{lights}}};
      my $lights = join( ",", sort { $a <=> $b } @{$result->{lights}} );
      if( !defined($hash->{lights})
          || $lights ne $hash->{lights} ) {
        $hash->{lights} = $lights;

        my $lights = join (' ', map( { my $code = $_;
                                          $code = $hash->{IODev}->{NAME} ."-". $code if( defined($hash->{IODev}) );
                                       defined($modules{HUEDevice}{defptr}{$code}) ? $modules{HUEDevice}{defptr}{$code}{NAME} : '';
                                     } @{$result->{lights}}) );
        setReadingsVal( $hash, ".associatedWith", $lights, TimeNow() );
      }

    } elsif( defined($result->{lights}) ) {
      $hash->{lights} = '';
      $hash->{helper}{lights} = {};
      CommandDeleteReading( undef, "$name .associatedWith" );

    } else {
      #$hash->{lights} = '';
      #$hash->{helper}{lights} = {};
    }

    if( ref($result->{state}) eq 'HASH' ) {
      my %readings;

      if( $result->{stream}
          && (defined($hash->{helper}{stream_active}) || $result->{stream}{active}) ) {
        $readings{stream_active} = $result->{stream}{active}?1:0;
      }
      if( $result->{state} ) {
        $readings{all_on} = $result->{state}{all_on};
        $readings{any_on} = $result->{state}{any_on};
      }
      if( AttrVal($name, 'createActionReadings', 0) ) {
      if( my $state = $result->{action} ) {
        $readings{ct} = $state->{ct}; $readings{ct} .= " (".int(1000000/$readings{ct})."K)" if( $readings{ct} );
        $readings{hue} = $state->{hue};
        $readings{sat} = $state->{sat};
        $readings{bri} = $state->{bri}; $readings{bri} = $hash->{helper}{bri} if( !defined($readings{bri}) );
        $readings{xy} = $state->{'xy'}->[0] .",". $state->{'xy'}->[1] if( defined($state->{'xy'}) );
        $readings{colormode} = $state->{colormode};

        $readings{alert} = $state->{alert};
        $readings{effect} = $state->{effect};

        $readings{reachable} = $state->{reachable}?1:0 if( defined($state->{reachable}) );

        $readings{scene} = $state->{scene};
        if( defined($readings{scene}) ) {
          if( my $scenes = $hash->{helper}{scenes} ) {
            for my $scene (@{$scenes}) {
              if( $readings{scene} == $scene->{id} ) {
                $readings{scene} = $scene->{name};
                last;
              }
            }
          }
        }

        my $s = '';
        my $pct = -1;
        my $on = $state->{on}; $readings{on} = $hash->{helper}{onoff} if( !defined($on) );
        if( $on ) {
          $s = 'on';
          $readings{onoff} = 1;

          if( !defined($readings{bri}) || AttrVal($name, 'subType', 'dimmer') eq 'switch' ) {
            $pct = 100;

          } else {
            $pct = int($readings{bri} * 99 / 254 + 1);
            if( $pct > 0
                && $pct < 100  ) {
              $s = $dim_values{int($pct/7)};
            }
            $s = 'off' if( $pct == 0 );
          }
        } else {
          $on = 0;
          $s = 'off';
          $pct = 0;

          $readings{onoff} = 0;
        }

        $readings{pct} = $pct;

        $s = 'unreachable' if( defined($readings{reachable}) && !$readings{reachable} );
        #$readings{state} = $s;

      }
      }

      readingsBeginUpdate($hash);
      foreach my $key ( keys %readings ) {
        if( defined($readings{$key}) ) {
          readingsBulkUpdate($hash, $key, $readings{$key}, 1) if( !defined($hash->{helper}{$key}) || $hash->{helper}{$key} ne $readings{$key} );
          $hash->{helper}{$key} = $readings{$key};
        }
      }
      readingsEndUpdate($hash,1);

    }

    if( defined($hash->{helper}->{update}) ) {
      delete $hash->{helper}->{update};
      fhem( "set $hash->{IODev}{NAME} statusRequest" ) if( $hash->{IODev} );
      return undef;
    }

    return undef;
  }

  $hash->{modelid} = $result->{modelid} if( defined($result->{modelid}) );
  $attr{$name}{model} = $result->{modelid} if( !defined($attr{$name}{model}) && $result->{modelid} );

  $hash->{productid} = $result->{productid} if( defined($result->{productid}) );
  $hash->{swversion} = $result->{swversion} if( defined($result->{swversion}) );
  $hash->{swconfigid} = $result->{swconfigid} if( defined($result->{swconfigid}) );
  $hash->{manufacturername} = $result->{manufacturername} if( defined($result->{manufacturername}) );
  $hash->{productname} = $result->{productname} if( defined($result->{productname}) );
  $hash->{luminaireuniqueid} = $result->{luminaireuniqueid} if( defined($result->{luminaireuniqueid}) );

  if( !defined($hash->{helper}{capabilities}) ) {
    if( my $capabilities = $result->{capabilities} ) {
      if( my $inputs = $capabilities->{inputs} ) {
        $hash->{inputs} = scalar @{$inputs};

        $hash->{helper}{events} = [];
        my $i = 0;
        foreach my $input (@{$inputs}) {
          $hash->{helper}{events}[$i] = {};
          foreach my $event (@{$input->{events}}) {
            $hash->{helper}{events}[$i]{$event->{eventtype}} = $event->{buttonevent};
            $hash->{helper}{events}[$i]{$event->{buttonevent}} = $event->{eventtype};
          }

          ++$i;
        }

      }

      $hash->{helper}{capabilities} = $capabilities;
    }
  }

  #https://github.com/dresden-elektronik/deconz-rest-plugin/issues/2590
  #$hash->{lastseen} = $result->{lastseen} if( defined($result->{lastseen}) );
  $hash->{lastannounced} = $result->{lastannounced} if( defined($result->{lastannounced}) );

  $hash->{power} = $result->{power} if( defined($result->{power}) );


  if( $hash->{helper}->{devtype} eq 'S' ) {
    my %readings;

    $readings{lastseen} = $result->{lastseen} if( defined($result->{lastseen}) );

    if( my $config = $result->{config} ) {
      $hash->{on} = $config->{on}?1:0 if( defined($config->{on}) );
      $hash->{reachable} = $config->{reachable}?1:0 if( defined($config->{reachable}) );

      $hash->{url} = $config->{url} if( defined($config->{url}) );

      $hash->{lat} = $config->{lat} if( defined($config->{lat}) );
      $hash->{long} = $config->{long} if( defined($config->{long}) );
      $hash->{sunriseoffset} = $config->{sunriseoffset} if( defined($config->{sunriseoffset}) );
      $hash->{sunsetoffset} = $config->{sunsetoffset} if( defined($config->{sunsetoffset}) );

      $hash->{tholddark} = $config->{tholddark} if( defined($config->{tholddark}) );
      $hash->{sensitivity} = $config->{sensitivity} if( defined($config->{sensitivity}) );
      $hash->{ledindication} = $config->{ledindication}?1:0 if( defined($config->{ledindication}) );

      $readings{battery} = $config->{battery} if( defined($config->{battery}) );
      $readings{batteryPercent} = $config->{battery} if( defined($config->{battery}) );

      $readings{reachable} = $config->{reachable} if( defined($config->{reachable}) );
      $readings{temperature} = $config->{temperature} * 0.01 if( defined($config->{temperature}) );

      #Xiaomi Aqara Vibrationsensor (lumi.vibration.aq1)
      $hash->{sensitivitymax} = $config->{sensitivitymax} if( defined ($config->{sensitivitymax}) );

      #Eurotronic Spirit ZigBee (SPZB0001)
      $readings{heatsetpoint} = sprintf("%.1f",$config->{heatsetpoint} * 0.01) if( defined ($config->{heatsetpoint}) );
      $readings{locked} = $config->{locked}?'true':'false' if( defined ($config->{locked}) );
      $readings{displayflipped} = $config->{displayflipped}?'true':'false' if( defined ($config->{displayflipped}) );
      $readings{mode} = $config->{mode} if( defined ($config->{mode}) );
    }

    my $lastupdated;
    my $now = time;
    my $ts;
    if( my $state = $result->{state} ) {
      $lastupdated = $state->{lastupdated};

      return undef if( !$lastupdated );
      return undef if( $lastupdated eq 'none' );

      $ts = time_str2num($lastupdated);

      my $offset = 0;
      if( my $iohash = $hash->{IODev} ) {
        if( my $offset_bridge = $iohash->{helper}{offsetUTC} ) {
          $offset = $offset_bridge;
          Log3 $name, 5, "$name: using offsetUTC $offset from bridge";

        } else {
          # bridge has no offsetUTC configured, use the system offsetUTC for now
          my @t = localtime($now);
          $offset = timegm(@t) - timelocal(@t);
          Log3 $name, 5, "$name: using offsetUTC $offset from system";
        }

        $ts += $offset;
        $lastupdated = FmtDateTime($ts);

      } else {
        # what to do? can this happen?
        Log3 $name, 1, "$name: HUEDevice_Parse called without hash->{IODev}";

      }

      $readings{reachable} = ($state->{reachable}?1:0) if( defined($state->{reachable}) );

      $readings{state} = $state->{status} if( defined($state->{status}) );
      $readings{state} = $state->{flag}?'1':'0' if( defined($state->{flag}) );
      $readings{state} = $state->{open}?'open':'closed' if( defined($state->{open}) );
      $readings{state} = $state->{lightlevel} if( defined($state->{lightlevel}) && !defined($state->{lux}) );
      $readings{state} = $state->{buttonevent} if( defined($state->{buttonevent}) );
      $readings{state} = $state->{presence}?'motion':'nomotion' if( defined($state->{presence}) );
      $readings{state} = $state->{fire}?'fire':'nofire' if( defined($state->{fire}) );

      $readings{input} = $state->{input} if( defined($state->{input}) );
      $readings{eventtype} = $state->{eventtype} if( defined($state->{eventtype}) );
      $readings{eventduration} = $state->{eventduration} if( defined($state->{eventduration}) );

      $readings{action} = $state->{action} if( defined($state->{action}) );
      $readings{steps} = $state->{steps} if( defined($state->{steps}) );
      $readings{direction} = $state->{direction} if( defined($state->{direction}) );

      $readings{dark} = $state->{dark}?'1':'0' if( defined($state->{dark}) );
      $readings{humidity} = $state->{humidity} * 0.01 if( defined($state->{humidity}) );
      $readings{daylight} = $state->{daylight}?'1':'0' if( defined($state->{daylight}) );
      $readings{temperature} = $state->{temperature} * 0.01 if( defined($state->{temperature}) );
      $readings{pressure} = $state->{pressure} if( defined($state->{pressure}) );
      $readings{lightlevel} = $state->{lightlevel} if( defined($state->{lightlevel}) );
      $readings{lux} = $state->{lux} if( defined($state->{lux}) );
      $readings{power} = $state->{power} if( defined($state->{power}) );
      $readings{voltage} = $state->{voltage} if( defined($state->{voltage}) );
      $readings{current} = $state->{current} if( defined($state->{current}) );
      $readings{consumption} = $state->{consumption} if( defined($state->{consumption}) );
      $readings{water} = $state->{water} if( defined($state->{water}) );
      $readings{fire} = $state->{fire} if( defined($state->{fire}) );
      $readings{tampered} = $state->{tampered} if( defined($state->{tampered}) );
      $readings{battery} = $state->{battery} if( defined($state->{battery}) );
      $readings{batteryState} = $state->{lowbattery}?'low':'ok' if( defined($state->{lowbattery}) );
      $readings{batteryState} = $state->{battery_state} if( defined($state->{battery_state}) );
      $readings{batteryPercent} = $state->{battery} if( defined($state->{battery}) );
      $readings{alarm} = $state->{alarm}?'1':'0' if( defined($state->{alarm}) );

      #Xiaomi Aqara Vibrationsensor (lumi.vibration.aq1)
      $readings{tiltangle} = $state->{tiltangle} if( defined ($state->{tiltangle}) );
      $readings{vibration} = $state->{vibration} if( defined ($state->{vibration}) );
      $readings{orientation} = join(',', @{$state->{orientation}}) if( defined($state->{orientation}) && ref($state->{orientation}) eq 'ARRAY' );
      $readings{vibrationstrength} = $state->{vibrationstrength} if( defined ($state->{vibrationstrength}) );

      #Eurotronic Spirit ZigBee (SPZB0001)
      $readings{valve} = ceil((100/255) * $state->{valve}) if( defined ($state->{valve}) );

      #Heiman Gassensor HS1CG
      $readings{carbonmonoxide} = $state->{carbonmonoxide} if( defined($state->{carbonmonoxide}) );

      #Aqara Cube
      $readings{gesture} = $state->{gesture} if( defined($state->{gesture}) );

      #frient Air Quality Sensor
      $readings{airqualityppb} = $state->{airqualityppb} if( defined($state->{airqualityppb}) );
      $readings{airquality} = $state->{airquality} if( defined($state->{airquality}) );

      if( my $entries = $hash->{helper}{readingList} ) {
        foreach my $entry (@{$entries}) {
          $readings{$entry} = $state->{$entry} if( defined($state->{$entry}) );
        }
      }


      if( $hash->{helper}{forceUpdate}
          && defined($state->{buttonevent}) ) {
        if( $hash->{helper}{state} eq $readings{state} ) {
          delete $hash->{helper}{forceUpdate};

        } else {
          my $input = substr($state->{buttonevent}, 0, 1);
          $readings{input} = substr($state->{buttonevent}, 0, 1);
          if( $input
              && defined($hash->{helper}{events})
              && defined($hash->{helper}{events}[$input-1])
              && defined($hash->{helper}{events}[$input-1]{$state->{buttonevent}}) ) {
            $readings{eventtype} = $hash->{helper}{events}[$input-1]{$state->{buttonevent}};

          } elsif( my $type = substr($state->{buttonevent}, 2, 2) ) {
            if( $type eq '00' ) {
              $readings{eventtype} = 'initial_press';

            } elsif( $type eq '01' ) {
              $readings{eventtype} = 'repeat';

            } elsif( $type eq '02' ) {
              $readings{eventtype} = 'short_release';

            } elsif( $type eq '03' ) {
              $readings{eventtype} = 'long_release';

            }
          }

        }
      }
      $hash->{helper}{state} = $readings{state} if( defined($readings{state}) );

    }

    CommandDeleteReading( undef, "$name .lastupdated" );
    CommandDeleteReading( undef, "$name .lastupdated_local" );

    if( scalar keys %readings ) {
       readingsBeginUpdate($hash);

       my $i = 0;
       foreach my $key ( keys %readings ) {
         if( defined($readings{$key}) ) {
           if( $lastupdated ) {
             my $rut = ReadingsTimestamp($name,$key,undef);
             if( !$hash->{helper}{forceUpdate}                                 # not from queryAfterEvent
                 #&& defined($result->{source}) && $result->{source} ne 'event' # not v2 event and not deconz event
                 && !defined($result->{v2_service}) && !defined($result->{t}) # not v2 event and not deconz event
                 && $ts && defined($rut) && $ts <= time_str2num($rut) ) {      # lastupdated older than or equal to reading
               Log3 $name, 4, "$name: ignoring reading $key with timestamp $lastupdated, current reading timestamp is $rut";
               next;
             }
             #if( !$hash->{helper}{forceUpdate}                                 # not from queryAfterEvent
             #    && defined($result->{source}) && $result->{source} ne 'event' # not v2 event and not deconz event
             #    && $ts && $ts-60 > $now ) {                                   # lastupdated older than or equal to reading
             #  Log3 $name, 4, "$name: ignoring reading $key with timestamp $lastupdated, older than 60sec";
             #  next;
             #}

             $hash->{'.updateTimestamp'} = $lastupdated;
             $hash->{CHANGETIME}[$i] = $lastupdated;
           }
           readingsBulkUpdate($hash, $key, $readings{$key}, 1);

           ++$i;
         }
       }

       readingsEndUpdate($hash,1);
       delete $hash->{CHANGETIME};

       delete $hash->{helper}{forceUpdate};
     }

    return undef;
  }


  if( !defined($attr{$name}{subType}) ) {
    if( defined($attr{$name}{model}) ) {
      if( defined($hueModels{$attr{$name}{model}}{subType}) ) {
        $attr{$name}{subType} = $hueModels{$attr{$name}{model}}{subType};

        HUEDeviceSetIcon($hash) if( $hash->{helper}{fromAutocreate} );

      } elsif( $attr{$name}{model} =~ m/TW$/ ) {
        $attr{$name}{subType} = 'ctdimmer';

      } elsif( $attr{$name}{model} =~ m/RGB$/ ) {
        $attr{$name}{subType} = 'colordimmer';

      } elsif( $attr{$name}{model} =~ m/RGBW$/ ) {
        $attr{$name}{subType} = 'extcolordimmer';

      }

      delete $hash->{helper}{fromAutocreate};
    }

    if( !defined($attr{$name}{subType}) && $hash->{type} ) {
      if( $hash->{type} eq "Extended color light" ) {
        $attr{$name}{subType} = 'extcolordimmer';

      } elsif( $hash->{type} eq "Color light" ) {
        $attr{$name}{subType} = 'colordimmer';

      } elsif( $hash->{type} eq "Color temperature light" ) {
        $attr{$name}{subType} = 'ctdimmer';

      } elsif( $hash->{type} =~ m/Dimmable/ ) {
        $attr{$name}{subType} = 'dimmer';

      } elsif( $hash->{type} =~ m/On.Off/ ) {
        $attr{$name}{subType} = 'switch';

      }

    }

  } elsif( $attr{$name}{subType} eq "colordimmer" && defined($attr{$name}{model}) ) {
    $attr{$name}{subType} = $hueModels{$attr{$name}{model}}{subType} if( defined($hueModels{$attr{$name}{model}}{subType}) );
  }


  $attr{$name}{devStateIcon} = '{(HUEDevice_devStateIcon($name),"toggle")}' if( !defined( $attr{$name}{devStateIcon} ) );

  if( !defined($attr{$name}{webCmd}) && defined($attr{$name}{subType}) ) {
    my $subtype = $attr{$name}{subType};

    if( !$hash->{helper}->{devtype} ) {
      $attr{$name}{webCmd} = 'rgb:rgb ff0000:rgb DEFF26:rgb 0000ff:ct 490:ct 380:ct 270:ct 160:toggle:on:off' if( $subtype eq "extcolordimmer" );
      $attr{$name}{webCmd} = 'hue:rgb:rgb ff0000:rgb 98FF23:rgb 0000ff:toggle:on:off' if( $subtype eq "colordimmer" );
      $attr{$name}{webCmd} = 'ct:ct 490:ct 380:ct 270:ct 160:toggle:on:off' if( $subtype eq "ctdimmer" );
      $attr{$name}{webCmd} = 'pct:toggle:on:off' if( $subtype eq "dimmer" );
      $attr{$name}{webCmd} = 'toggle:on:off' if( $subtype eq "switch" );
      $attr{$name}{webCmd} = 'up:stop:down:pct' if( $subtype eq "blind" );
    } elsif( $hash->{helper}->{devtype} eq 'G' ) {
      $attr{$name}{webCmd} = 'on:off';
    }
  }

  my %readings;
  readingsBeginUpdate($hash);

  my $state = $result->{'state'};
  my $config = $result->{'config'};

  my $on        = $state->{on};
     $on = $hash->{helper}{on} if( !defined($on) );
  my $reachable = $state->{reachable}?1:0;
     $reachable = $hash->{helper}{reachable} if( !defined($state->{reachable}) );
     $reachable = 1 if( !$reachable && AttrVal($name, 'ignoreReachable', 0) );
  my $colormode = $state->{'colormode'};
  my $bri       = $state->{'bri'};
     $bri = $hash->{helper}{bri} if( !defined($bri) );
  my $ct        = $state->{'ct'};
  my $hue       = $state->{'hue'};
  my $sat       = $state->{'sat'};
  my $xy        = undef;
     $xy        = $state->{'xy'}->[0] .",". $state->{'xy'}->[1] if( defined($state->{'xy'}) );
  my $alert = $state->{alert};
  my $effect = $state->{effect};

  my $rgb       = undef;
     $rgb       = $state->{rgb} if( defined($state->{rgb}) );

  my $battery   = undef;
     $battery   = $config->{battery} if( defined($config->{battery}) );

  my $mode   = undef;
     $mode   = $state->{mode} if( defined($state->{mode}) && ($hash->{helper}{mode} || $state->{mode} ne 'homeautomation') );

  my $lastseen = undef;
     $lastseen = $result->{lastseen} if( defined($result->{lastseen}) );


  $readings{v2effect} = $state->{v2effect};
  $readings{dynamics_speed} = $state->{dynamics_speed};
  $readings{dynamics_status} = $state->{dynamics_status};


  if( defined($colormode) && $colormode ne $hash->{helper}{colormode} ) {readingsBulkUpdate($hash,"colormode",$colormode);}
  if( defined($bri) && $bri != $hash->{helper}{bri} ) {readingsBulkUpdate($hash,"bri",$bri);}
  if( defined($ct) && $ct != $hash->{helper}{ct} ) {
    if( $ct == 0 ) {
      readingsBulkUpdate($hash,"ct",$ct);
    }
    else {
      readingsBulkUpdate($hash,"ct",$ct . " (".int(1000000/$ct)."K)");
    }
  }
  if( defined($hue) && $hue != $hash->{helper}{hue} ) {readingsBulkUpdate($hash,"hue",$hue);}
  if( defined($sat) && $sat != $hash->{helper}{sat} ) {readingsBulkUpdate($hash,"sat",$sat);}
  if( defined($xy) && $xy ne $hash->{helper}{xy} ) {readingsBulkUpdate($hash,"xy",$xy);}
  if( !defined($hash->{helper}{reachable}) || $reachable != $hash->{helper}{reachable} ) {readingsBulkUpdate($hash,"reachable",$reachable?1:0);}
  if( defined($alert) && $alert ne $hash->{helper}{alert} ) {readingsBulkUpdate($hash,"alert",$alert);}
  if( defined($effect) && $effect ne $hash->{helper}{effect} ) {readingsBulkUpdate($hash,"effect",$effect);}

  if( defined($rgb) && $rgb ne $hash->{helper}{rgb} ) {readingsBulkUpdate($hash,"rgb",$rgb);}

  if( defined($battery) && $battery ne $hash->{helper}{battery} ) {readingsBulkUpdate($hash,"battery",$battery);}
  if( defined($battery) && $battery ne $hash->{helper}{battery} ) {readingsBulkUpdate($hash,'batteryPercent',$battery);}

  if( defined($mode) && $mode ne $hash->{helper}{mode} ) {readingsBulkUpdate($hash,"mode",$mode);}

  if( defined($lastseen) && $lastseen ne $hash->{helper}{lastseen} ) {readingsBulkUpdate($hash,"lastseen",$lastseen);}

  my $s = '';
  my $pct = -1;
  if( defined($state->{'pct'}) ) {
    $pct = $state->{'pct'};
    $s = $pct;

  } elsif( $on ) {
    $s = 'on';
    if( $on != $hash->{helper}{on} ) {readingsBulkUpdate($hash,"onoff",1);}

    if( $bri < 0 || AttrVal($name, 'subType', 'dimmer') eq 'switch' ) {
        $pct = 100;

    } else {
      $pct = int($bri * 99 / 254 + 1);
      if( $pct > 0
          && $pct < 100  ) {
        $s = $dim_values{int($pct/7)};

      }

      $s = 'off' if( $pct == 0 );

    }
  } else {
    $on = 0;
    $s = 'off';
    $pct = 0;
    if( $on != $hash->{helper}{on} ) {readingsBulkUpdate($hash,"onoff",0);}
  }

  $readings{dynamics_status} = 'none' if( !$on && $hash->{helper}{dynamics_status} && !defined($readings{dynamics_status}) );
  $readings{v2effect} = 'no_effect' if( !$on && $hash->{helper}{v2effect} && !defined($readings{v2effect}) );

  if( $pct != $hash->{helper}{pct} ) {readingsBulkUpdate($hash,"pct", $pct);}
  #if( $pct != $hash->{helper}{pct} ) {readingsBulkUpdate($hash,"level", $pct . ' %');}

  $s = 'unreachable' if( !$reachable );

  $hash->{helper}{on} = $on if( defined($on) );
  $hash->{helper}{reachable} = $reachable if( defined($reachable) );
  $hash->{helper}{colormode} = $colormode if( defined($colormode) );
  $hash->{helper}{bri} = $bri if( defined($bri) );
  $hash->{helper}{ct} = $ct if( defined($ct) );
  $hash->{helper}{hue} = $hue if( defined($hue) );
  $hash->{helper}{sat} = $sat if( defined($sat) );
  $hash->{helper}{xy} = $xy if( defined($xy) );
  $hash->{helper}{alert} = $alert if( defined($alert) );
  $hash->{helper}{effect} = $effect if( defined($effect) );

  $hash->{helper}{rgb} = $rgb if( defined($rgb) );

  $hash->{helper}{battery} = $battery if( defined($battery) );

  $hash->{helper}{mode} = $mode if( defined($mode) );

  $hash->{helper}{pct} = $pct;

  my $changed = $hash->{CHANGED}?1:0;

  if( $s ne $hash->{STATE} ) {readingsBulkUpdate($hash,"state",$s);}

  foreach my $key ( keys %readings ) {
    if( defined($readings{$key}) ) {
      readingsBulkUpdate($hash, $key, $readings{$key}, 1) if( !defined($hash->{helper}{$key}) || $hash->{helper}{$key} ne $readings{$key} );
      $hash->{helper}{$key} = $readings{$key};
    }
  }
  readingsEndUpdate($hash,1);

  if( defined($colormode) && !defined($rgb) ) {
    my $rgb = CommandGet("","$name rgb");
    if( $rgb ne $hash->{helper}{rgb} ) { readingsSingleUpdate($hash,"rgb", $rgb,1); };
    $hash->{helper}{rgb} = $rgb;
  }

  $hash->{helper}->{update_timeout} = -1;
  RemoveInternalTimer($hash);

  return $changed;
}

sub
HUEDevice_Attr($$$;$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  if( $attrName eq 'setList' || $attrName eq 'configList' ) {
    my $hash = $defs{$name};
    delete $hash->{helper}{$attrName};
    return "$name is not a sensor device" if( $hash->{helper}->{devtype} ne 'S' );
    #return "$name is not a CLIP sensor device" if( $hash->{type} && $hash->{type} !~ m/^CLIP/ );
    if( $cmd eq "set" && $attrVal ) {
      foreach my $line ( split( "\n", $attrVal ) ) {
        my ($cmd,$opts,$json);
        if (scalar split(':',$line) > 3 && (split(':',$line))[1] !~ /^perl/){
          ($cmd,$opts,$json) = split( ':', $line,3 );
        } else {
          ($cmd,$json) = split( ':', $line,2 );
          $opts = '';
        }
        if( $cmd =~ m'^/(.*)/$' ) {
          my $regex = $1;
          $hash->{helper}{$attrName}{'regex'} = [] if( !$hash->{helper}{$attrName}{'regex'} );
          push @{$hash->{helper}{$attrName}{'regex'}}, { regex => $regex, opts => $opts, json => $json };
        } else {
          $hash->{helper}{$attrName}{cmds}{$cmd} = $json;
        }
      }
    }

  } elsif( $attrName eq 'readingList' ) {
    my $hash = $defs{$name};
    delete $hash->{helper}{$attrName};
    return "$name is not a sensor device" if( $hash->{helper}->{devtype} ne 'S' );
    if( $cmd eq "set" && $attrVal ) {
      my @a = split("[ ,]+", $attrVal);
      $hash->{helper}{$attrName} = \@a;
    }
  }

  return;
}

1;

__END__

=pod
=item tag cloudfree
=item tag publicAPI
=item summary    Devices connected to a Phillips HUE bridge, an LIGHTIFY or TRADFRI gateway
=item summary_DE Ger&auml;te an einer Philips HUE Bridge, einem LIGHTIFY oder Tradfri Gateway
=begin html

<a id="HUEDevice"></a>
<h3>HUEDevice</h3>
<ul>
  <br>
  <a id="HUEDevice-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; HUEDevice [group|sensor] &lt;id&gt; [&lt;interval&gt;]</code><br>
    <br>

    Defines a device connected to a <a href="#HUEBridge">HUEBridge</a>.<br><br>

    This can be a hue bulb, a living colors light or a living whites bulb or dimmer plug.<br><br>

    The device status will be updated every &lt;interval&gt; seconds. 0 means no updates.
    The default and minimum is 60 if the IODev has not set pollDevices to 1.
    The default ist 0 if the IODev has set pollDevices to 1.
    Groups are updated only on definition and statusRequest, but see createGroupReadings<br>
    Sensor devices will only be autocreated with deconz bridge devices. Use <code>get &lt;bridge&gt; sensors</code> will provide the sensor id vor manual definition.<br><br>

    Examples:
    <ul>
      <code>define bulb HUEDevice 1</code><br>
      <code>define LC HUEDevice 2</code><br>
      <code>define allLights HUEDevice group 0</code>
      <code>define motion HUEDevice sensor 1</code><br>
    </ul>
  </ul><br>

  <a id="HUEDevice-readings"></a>
  <b>Readings</b>
  <ul>
    <li>bri<br>
    the brightness reported from the device. the value can be betwen 1 and 254</li>
    <li>colormode<br>
    the current colormode</li>
    <li>ct<br>
    the colortemperature in mireds and kelvin</li>
    <li>hue<br>
    the current hue</li>
    <li>pct<br>
    the current brightness in percent</li>
    <li>onoff<br>
    the current on/off state as 0 or 1</li>
    <li>sat<br>
    the current saturation</li>
    <li>xy<br>
    the current xy color coordinates</li>
    <li>state<br>
    the current state</li>
    <br>
    Notes:
      <ul>
      <li>with current bridge firware versions groups have <code>all_on</code> and <code>any_on</code> readings,
          with older firmware versions groups have no readings.</li>
      <li>not all readings show the actual device state. all readings not related to the current colormode have to be ignored.</li>
      <li>the actual state of a device controlled by a living colors or living whites remote can be different and will
          be updated after some time.</li>
      </ul><br>
  </ul><br>

  <a id="HUEDevice-set"></a>
    <b>Set</b>
    <ul>
      <li>on [&lt;ramp-time&gt;]</li>
      <li>off [&lt;ramp-time&gt;]</li>
      <li>toggle [&lt;ramp-time&gt;]</li>
      <a id="HUEDevice-set-statusRequest"></a>
      <li>statusRequest<br>
        Request device status update.</li>
      <a id="HUEDevice-set-pct"></a>
      <li>pct &lt;value&gt; [&lt;ramp-time&gt;]<br>
        dim to &lt;value&gt;<br>
        Note: the FS20 compatible dimXX% commands are also accepted.</li>
      <a id="HUEDevice-set-color"></a>
      <li>color &lt;value&gt;<br>
        set colortemperature to &lt;value&gt; kelvin.</li>
      <a id="HUEDevice-set-bri"></a>
      <li>bri &lt;value&gt; [&lt;ramp-time&gt;]<br>
        set brighness to &lt;value&gt;; range is 0-254.</li>
      <li>dimUp [delta]</li>
      <li>dimDown [delta]</li>
      <a id="HUEDevice-set-ct"></a>
      <li>ct &lt;value&gt; [&lt;ramp-time&gt;]<br>
        set colortemperature to &lt;value&gt; in mireds (range is 154-500) or kelvin (range is 2000-6493).</li>
      <li>ctUp [delta]</li>
      <li>ctDown [delta]</li>
      <a id="HUEDevice-set-hue"></a>
      <li>hue &lt;value&gt; [&lt;ramp-time&gt;]<br>
        set hue to &lt;value&gt;; range is 0-65535.</li>
      <li>hueUp [delta]</li>
      <li>hueDown [delta]</li>
      <a id="HUEDevice-set-sat"></a>
      <li>sat &lt;value&gt; [&lt;ramp-time&gt;]<br>
        set saturation to &lt;value&gt;; range is 0-254.</li>
      <li>satUp [delta]</li>
      <li>satDown [delta]</li>
      <a id="HUEDevice-set-xy"></a>
      <li>xy &lt;x&gt;,&lt;y&gt; [&lt;ramp-time&gt;]<br>
        set the xy color coordinates to &lt;x&gt;,&lt;y&gt;</li>
      <li>alert [none|select|lselect]</li>
      <li>effect [none|colorloop] [{&lt;json&gt;}]</li>
      <a id="HUEDevice-set-transitiontime"></a>
      <li>transitiontime &lt;time&gt;<br>
        set the transitiontime to &lt;time&gt; 1/10s</li>
      <a id="HUEDevice-set-rgb"></a>
      <li>rgb &lt;rrggbb&gt;<br>
        set the color to (the nearest equivalent of) &lt;rrggbb&gt;</li>
      <br>
      <li>delayedUpdate</li>
      <li>immediateUpdate</li>
      <br>
      <li>savescene &lt;id&gt;</li>
      <li>deletescene &lt;id&gt;</li>
      <li>scene</li>
      <br>
      <a id="HUEDevice-set-lights"></a>
      <li>lights &lt;lights&gt;<br>
      Only valid for groups. Changes the list of lights in this group.
      The lights are given as a comma sparated list of fhem device names or bridge light numbers.</li>
      <a id="HUEDevice-set-rename"></a>
      <li>rename &lt;new name&gt;<br>
      Renames the device in the bridge and changes the fhem alias.</li>
      <li>json [setsensor|configsensor] {&lt;json&gt;}<br>
      send <code>{&lt;json&gt;}</code> to the state or config endpoints for this device.</li>
      <li>setsensor|configsensor|config {&lt;json&gt;}<br>
      send <code>{&lt;json&gt;}</code> to the state or config endpoints for this device.</li>
      <li>setlight|configlight|config {&lt;json&gt;}<br>
        send <code>{&lt;json&gt;}</code> to the state or config endpoints for this device.
        see: <a href="#HUEBridge-set-configlight">HUEBridge:configlight</a></li>
      <li>habridgeupdate [ : &lt; on | off &gt; ] [ : &lt; bri | pct &gt; &lt; value &gt; ] <br>
      This command is only for usage of HA-Bridges that are emulating an Hue Hub. <br>
      It updates your HA-Bridge internal light state of the devices without changing the devices itself.
      <br>bri and pct have to be used in the same way as changing the brightness or dimvalue of the device. </li>
      <br>
      <li><a href="#setExtensions"> set extensions</a> are supported.</li>
      <br>
      Note:
        <ul>
        <li>&lt;ramp-time&gt; is given in seconds</li>
        <li>multiple paramters can be set at once separated by <code>:</code><br>
          Examples:<br>
            <code>set LC on : transitiontime 100</code><br>
            <code>set bulb on : bri 100 : color 4000</code><br></li>
        </ul>
    </ul><br>

  <a id="HUEDevice-get"></a>
    <b>Get</b>
    <ul>
      <li>rgb</li>
      <li>RGB</li>
      <li>startup<br>
        show startup behavior.</li>
      <li>devStateIcon<br>
      returns html code that can be used to create an icon that represents the device color in the room overview.</li>
    </ul><br>

  <a id="HUEDevice-attr"></a>
  <b>Attributes</b>
  <ul>
    <a id="HUEDevice-attr-color-icon"></a>
    <li>color-icon<br>
      1 -> use lamp color as icon color and 100% shape as icon shape<br>
      2 -> use lamp color scaled to full brightness as icon color and dim state as icon shape</li>
    <a id="HUEDevice-attr-createActionReadings"></a>
    <li>createActionReadings<br>
      create readings for the last action in group devices</li>
    <a id="HUEDevice-attr-createGroupReadings"></a>
    <li>createGroupReadings<br>
      create 'artificial' readings for group devices. default depends on the createGroupReadings setting in the bridge device.</li>
    <a id="HUEDevice-attr-ignoreReachable"></a>
    <li>ignoreReachable<br>
      ignore the reachable state that is reported by the hue bridge. assume the device is allways reachable.</li>
    <a id="HUEDevice-attr-setList"></a>
    <li>setList<br>
      The list of know set commands for sensor type devices. one command per line, eg.: <code><br>
   attr mySensor setList present:{&lt;json&gt;}\<br>
absent:{&lt;json&gt;}</code></li>
    <a id="HUEDevice-attr-configList"></a>
    <li>configList<br>
      The list of know config commands for sensor type devices. one command per line, eg.: <code><br>
attr mySensor mode:{&lt;json&gt;}\<br>
/heatsetpoint (.*)/:perl:{'{"heatsetpoint":'. $VALUE1 * 100 .'}'}<br>
/sensitivity (.*)/:0,1,2,3:{"sensitivity":$1}</code></li>
    <a id="HUEDevice-attr-readingList"></a>
    <li>readingList<br>
      The list of readings that should be created from the sensor state object. Space or comma separated.</li>
    <a id="HUEDevice-attr-subType"></a>
    <li>subType<br>
      extcolordimmer -> device has rgb and color temperatur control<br>
      colordimmer -> device has rgb controll<br>
      ctdimmer -> device has color temperature control<br>
      dimmer -> device has brightnes controll<br>
      switch -> device has on/off controll<br></li>
    <a id="HUEDevice-attr-transitiontime"></a>
    <li>transitiontime<br>
      default transitiontime for all set commands if not specified directly in the set.</li>
    <a id="HUEDevice-attr-delayedUpdate"></a>
    <li>delayedUpdate<br>
      1 -> the update of the device status after a set command will be delayed for 1 second. usefull if multiple devices will be switched.
    </li>
    <a id="HUEDevice-attr-devStateIcon"></a>
    <li>devStateIcon<br>
      will be initialized to <code>{(HUEDevice_devStateIcon($name),"toggle")}</code> to show device color as default in room overview.</li>
    <a id="HUEDevice-attr-webCmd"></a>
    <li>webCmd<br>
      will be initialized to a device specific value according to subType.</li>
  </ul>

</ul><br>

=end html

=encoding utf8
=for :application/json;q=META.json 31_HUEDevice.pm
{
  "abstract": "devices connected to a Phillips HUE bridge, an Osram LIGHTIFY gateway or a IKEA TRADFRI gateway",
  "x_lang": {
    "de": {
      "abstract": "Geräte an einer Philips HUE Bridge, einem Osram LIGHTIFY Gateway oder einem IKEA Tradfri Gateway"
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
        "Color": 0,
        "SetExtensions": 0,
        "JSON": 0,
        "Time::Local": 0
      },
      "recommends": {
      },
      "suggests": {
        "HUEBridge": 0,
        "tradfri": 0,
        "LIGHTIFY": 0
      }
    }
  }
}
=end :application/json;q=META.json
=cut
