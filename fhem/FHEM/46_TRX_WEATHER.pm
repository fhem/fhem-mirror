# $Id$
##############################################################################
#
# 46_TRX_WEATHER.pm
# FHEM module to decode weather sensor messages for RFXtrx
#
#     Copyright (C) 2012-2016 by Willi Herzig (Willi.Herzig@gmail.com)
#	  Maintenance since 2018 by KernSani
#
# The following devices are implemented to be received:
#
# temperature sensors (TEMP):
# * "THR128" 	is THR128/138, THC138
# * "THGR132N" 	is THC238/268,THN132,THWR288,THRN122,THN122,AW129/131
# * "THWR800" 	is THWR800
# * "RTHN318"	is RTHN318
# * "TX3_T" 	is LaCrosse TX3, TX4, TX17
# * "TS15C" 	is TS15C
# * "VIKING_02811" is Viking 02811
# * "WS2300"    is La Crosse WS2300
# * "RUBICSON"  is RUBiCSON
# * "TFA_303133" is TFA 30.3133
# * "WT0122" 	is WT0122 pool sensor
#
# humidity sensors (HYDRO):
# * "TX3" 	is LaCrosse TX3
# * "WS2300"	is LaCrosse WS2300
# * "S80"	is Inovalley S80 plant humidity sensor
#
# temperature/humidity sensors (TEMPHYDRO):
# * "THGR228N"	is THGN122/123, THGN132, THGR122/228/238/268
# * "THGR810"	is THGR810
# * "RTGR328"	is RTGR328
# * "THGR328"	is THGR328
# * "WTGR800_T"	is WTGR800
# * "THGR918"	is THGR918, THGRN228, THGN500
# * "TFATS34C"	is TFA TS34C, Cresta
# * "WT450H"	is WT260,WT260H,WT440H,WT450,WT450H
# * "VIKING_02038" is Viking 02035,02038 (02035 has no humidity)
# * "RUBICSON"  is Rubicson 
# * "EW109"     is EW109
# * "XT300" 	is Imagintronix/Opus XT300 Soil sensor
# * "WS1700"	is Alecto WS1700 and compatibles
# * "WS3500"	is Alecto WS3500, WS4500, Auriol H13726, Hama EWS1500, Meteoscan W155/W160, Ventus WS155
#
# temperature/humidity/pressure sensors (TEMPHYDROBARO):
# * "BTHR918"	is BTHR918
# * "BTHR918N"	is BTHR918N, BTHR968
#
# rain gauge sensors (RAIN):
# * "RGR918" 	is RGR126/682/918
# * "PCR800"	is PCR800
# * "TFA_RAIN"	is TFA
# * "RG700"	is UPM RG700
# * "WS2300_RAIN" is WS2300
# * "TX5_RAIN" 	is La Crosse TX5
# * "WS4500_RAIN" is Alecto WS4500, Auriol H13726, Hama EWS1500, Meteoscan W155/W160,
#
# wind sensors (WIND):
# * "WTGR800_A" is WTGR800
# * "WGR800_A"	is WGR800
# * "WGR918"	is STR918, WGR918
# * "TFA_WIND"	is TFA
# * "WDS500" is UPM WDS500u
# * "WS2300_WIND" is WS2300
# * "WS4500_WIND" is Alecto WS4500, Auriol H13726, Hama EWS1500, Meteoscan W155/W160, Ventus WS155
#
# UV Sensors:
# * "UVN128"	is Oregon UVN128, UV138
# * "UVN800"	is Oregon UVN800
# * "TFA_UV"	is TFA_UV-Sensor
#
# Date/Time Sensors:
# * "RTGR328_DATE" is RTGR328N
#
# Energy Sensors:
# * "CM160"	is OWL CM119, CM160
# * "CM180"	is OWL CM180
# * "REVOLT"	is Revolt
#
# Weighing scales (WEIGHT): 
# * "BWR101" is Oregon Scientific BWR101
# * "GR101" is Oregon Scientific GR101
#
# BBQ-Sensors (two temperature values):
# * "ET732"	is Maverick ET-732
#
# thermostats (THERMOSTAT):
# * "TH10"      is XDOM TH10
# * "TLX7506"   is Digimax TLX7506
#
# Copyright (C) 2012-2016 Willi Herzig
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# Due to RFXCOM SDK requirements this code may only be used with a RFXCOM device.
#
# Some code was derived and modified from xpl-perl 
# from the following two files:
#	xpl-perl/lib/xPL/Utils.pm:
#	xpl-perl/lib/xPL/RF/Oregon.pm:
#
#SEE ALSO
# Project website: http://www.xpl-perl.org.uk/
# AUTHOR: Mark Hindess, soft-xpl-perl@temporalanomaly.com
#
# Copyright (C) 2007, 2009 by Mark Hindess
#
# This library is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself, either Perl version 5.8.7 or,
# at your option, any later version of Perl 5 you may have available.
##################################
#
# values for "set global verbose"
# 4: log unknown prologtocols
# 5: log decoding hexlines for debugging
#
##############################################################################
#
#	CHANGELOG
#	
#	02.04.2018	support for vair CO2 sensors (forum #67734) -Thanks to vbs
#	29.03.2018	Summary for Commandref
#				
#				
##############################################################################
package main;

use strict;
use warnings;

# Hex-Debugging into READING hexline? YES = 1, NO = 0
my $TRX_HEX_debug = 0;
# Max temperatute für Maverick BBQ
my $TRX_MAX_TEMP_BBQ = 1000;

my $time_old = 0;
my $trx_rssi;

sub
TRX_WEATHER_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^..(40|4e|50|51|52|54|55|56|57|58|5a|5b|5c|5d|71).*";
  $hash->{DefFn}     = "TRX_WEATHER_Define";
  $hash->{UndefFn}   = "TRX_WEATHER_Undef";
  $hash->{ParseFn}   = "TRX_WEATHER_Parse";
  $hash->{AttrList}  = "IODev ignore:1,0 do_not_notify:1,0 ".
                       $readingFnAttributes;

}

#####################################
sub
TRX_WEATHER_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  #my $a = int(@a);
  #print "a0 = $a[0]";

  return "wrong syntax: define <name> TRX_WEATHER code" if (int(@a) < 3);

  my $name = $a[0];
  my $code = $a[2];

  if (($code =~ /^CM160/) || ($code =~ /^CM180/) || ($code =~ /^REVOLT/)) {
  	return "wrong syntax: define <name> TRX_WEATHER code [scale_current scale_total add_total]" if (int(@a) != 3 && int(@a) != 6);
  	$hash->{scale_current} = ((int(@a) == 6) ? $a[3] : 1);
  	$hash->{scale_total} = ((int(@a) == 6) ? $a[4] : 1.0);
  	$hash->{add_total} = ((int(@a) == 6) ? $a[5] : 0.0);
  } elsif ($code =~ /^RFXMETER/) {
  	return "wrong syntax: define <name> TRX_WEATHER RFXMETER [scale_current]" if (int(@a) != 3 && int(@a) != 5);
  	$hash->{scale_current} = ((int(@a) == 5) ? $a[3] : 1);
  	$hash->{value_label} = $a[4] if (int(@a) == 5);
  } else {
	return "wrong syntax: define <name> TRX_WEATHER code" if(int(@a) > 3);
  }


  $hash->{CODE} = $code;
  $modules{TRX_WEATHER}{defptr}{$code} = $hash;
  AssignIoPort($hash);

  return undef;
}

#####################################
sub
TRX_WEATHER_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{TRX_WEATHER}{defptr}{$name});
  return undef;
}

# --------------------------------------------
# sensor types 

my %types =
  (
   # THERMOSTAT
   0x4009 => { part => 'THERMOSTAT', method => \&TRX_WEATHER_common_therm, },
   # BBQ
   0x4e0a => { part => 'BBQ', method => \&TRX_WEATHER_common_bbq, },
   # TEMP
   0x5008 => { part => 'TEMP', method => \&TRX_WEATHER_common_temp, },
   # HYDRO
   0x5108 => { part => 'HYDRO', method => \&TRX_WEATHER_common_hydro, },
   # TEMP HYDRO
   0x520a => { part => 'TEMPHYDRO', method => \&TRX_WEATHER_common_temphydro, },
   # TEMP HYDRO BARO
   0x540d => { part => 'TEMPHYDROBARO', method => \&TRX_WEATHER_common_temphydrobaro, },
   # RAIN
   0x550b => { part => 'RAIN', method => \&TRX_WEATHER_common_rain, },
   0x5509 => { part => 'RAIN', method => \&TRX_WEATHER_common_rain, },   
   # WIND
   0x5610 => { part => 'WIND', method => \&TRX_WEATHER_common_anemometer, },
   # UV
   0x5709 => { part => 'UV', method => \&TRX_WEATHER_common_uv, },
   # Date/Time sensors
   0x580D => { part => 'DATE', method => \&TRX_WEATHER_common_datetime, },
   # Energy usage sensors
   0x5A11 => { part => 'ENERGY', method => \&TRX_WEATHER_common_energy, },
   0x5B13 => { part => 'ENERGY2', method => \&TRX_WEATHER_common_energy2, },
   0x5c0f => { part => 'ENERGY3', method => \&TRX_WEATHER_common_energy3, },

    # WEIGHT
   0x5D08 => { part => 'WEIGHT', method => \&TRX_WEATHER_common_weight, },

    # RFXMETER
   0x710a => { part => 'RFXMETER', method => \&TRX_WEATHER_common_rfxmeter, },
  );

# --------------------------------------------

#my $DOT = q{.};
# Important: change it to _, because FHEM uses regexp
my $DOT = q{_};

my @TRX_WEATHER_winddir_name=("N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW");

# --------------------------------------------
# The following functions are changed:
#	- some parameter like "parent" and others are removed
#	- @res array return the values directly (no usage of xPL::Message)

sub TRX_WEATHER_temperature {
  my ($bytes, $dev, $res, $off) = @_;

  my $temp =
    (
    (($bytes->[$off] & 0x80) ? -1 : 1) *
        (($bytes->[$off] & 0x7f)*256 + $bytes->[$off+1]) 
    )/10;

  push @$res, {
       		device => $dev,
       		type => 'temp',
       		current => $temp,
		units => 'Grad Celsius'
  	}

}

sub TRX_WEATHER_temperature_food {
  my ($bytes, $dev, $res, $off) = @_;

  my $temp = $bytes->[$off]*256 + $bytes->[$off+1];

  return if ($temp > $TRX_MAX_TEMP_BBQ);

  push @$res, {
       		device => $dev,
       		type => 'temp-food',
       		current => $temp,
		units => 'Grad Celsius'
  	}

}

# -----------------------------
sub TRX_WEATHER_common_therm {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;

  my $subtype = sprintf "%02x", $bytes->[1];
  my $dev_type;

  my %devname =
    (   # HEXSTRING => "NAME"
        0x00 => "TLX7506",
        0x01 => "TH10",
  );

  if (exists $devname{$bytes->[1]}) {
        $dev_type = $devname{$bytes->[1]};
  } else {
        Log3 undef, 3, "TRX_WEATHER: common_therm error undefined subtype=$subtype";
        my @res = ();
        return @res;
  }

  #my $seqnbr = sprintf "%02x", $bytes->[2];

  my $dev_str = $dev_type;
  if (TRX_WEATHER_use_longid($longids,$dev_type)) {
        $dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if ($bytes->[4] > 0) {
        $dev_str .= $DOT.sprintf("%d", $bytes->[4]);
  }

  my @res = ();

  # hexline debugging
  if ($TRX_HEX_debug) {
    my $hexline = ""; for (my $i=0;$i<@$bytes;$i++) { $hexline .= sprintf("%02x",$bytes->[$i]);}
    push @res, { device => $dev_str, type => 'hexline', current => $hexline, units => 'hex', };
  }


  my $temp = ($bytes->[5]);
  if ($temp) {
    push @res, {
        device => $dev_str,
        type => 'temp',
        current => $temp,
        units => 'Grad Celsius'
    }
  }

  my $setpoint =($bytes->[6]);
  if ($setpoint) {
      push @res, {
                device => $dev_str,
                type => 'setpoint',
                current => $setpoint,
                units => 'Grad Celsius'
        }
  }

  my $demand;
  my $t_status = ($bytes->[7] & 0x03);
  if ($t_status == 0) { $demand = 'n/a'}
  elsif ($t_status == 1) { $demand = 'on'}
  elsif ($t_status == 2) { $demand = 'off'}
  elsif ($t_status == 3) { $demand = 'initializing'}
  else {
        $demand = sprintf("unknown-%02x",$t_status);
  }

  Log3 undef, 5, "TRX_WEATHER: demand = $bytes->[7] $t_status $demand";
  push @res, {
        device => $dev_str,
        type => 'demand',
        current => sprintf("%s",$demand),
  };

  my $rssi = ($bytes->[8] & 0xf0) >> 4;

  if ($trx_rssi == 1) {
        push @res, {
                device => $dev_str,
                type => 'rssi',
                current => sprintf("%d",$rssi),
        };
  }
  return @res;
}

sub TRX_WEATHER_temperature_bbq {
  my ($bytes, $dev, $res, $off) = @_;

  my $temp = $bytes->[$off]*256 + $bytes->[$off+1];

  return if ($temp > $TRX_MAX_TEMP_BBQ);

  push @$res, {
       		device => $dev,
       		type => 'temp-bbq',
       		current => $temp,
		units => 'Grad Celsius'
  	}

}

sub TRX_WEATHER_chill_temperature {
  my ($bytes, $dev, $res, $off) = @_;

  my $temp =
    (
    (($bytes->[$off] & 0x80) ? -1 : 1) *
        (($bytes->[$off] & 0x7f)*256 + $bytes->[$off+1]) 
    )/10;

  push @$res, {
       		device => $dev,
       		type => 'chilltemp',
       		current => $temp,
		units => 'Grad Celsius'
  	}

}

sub TRX_WEATHER_humidity {
  my ($bytes, $dev, $res, $off) = @_;
  my $hum = $bytes->[$off];
  my $hum_str = ['dry', 'comfortable', 'normal',  'wet']->[$bytes->[$off+1]];
  push @$res, {
	device => $dev,
	type => 'humidity',
	current => $hum,
	string => $hum_str,
	units => '%'
  }
}

sub TRX_WEATHER_pressure {
  my ($bytes, $dev, $res, $off) = @_;

  #my $offset = 795 unless ($offset);
  my $hpa = ($bytes->[$off])*256 + $bytes->[$off+1];
  my $forecast = { 0x00 => 'noforecast',
		   0x01 => 'sunny',
                   0x02 => 'partly',
                   0x03 => 'cloudy',
                   0x04 => 'rain',
                 }->{$bytes->[$off+2]} || 'unknown';
  push @$res, {
	device => $dev,
	type => 'pressure',
	current => $hpa,
	units => 'hPa',
	forecast => $forecast,
  };
}

sub TRX_WEATHER_simple_battery {
  my ($bytes, $dev, $res, $off) = @_;

  my $battery;

  my $battery_level = $bytes->[$off] & 0x0f;
  if ($battery_level == 0x9) { $battery = 'ok'}
  elsif ($battery_level == 0x0) { $battery = 'low'}
  else { 
	$battery = sprintf("unknown-%02x",$battery_level);
  }

  push @$res, {
	device => $dev,
	type => 'battery',
	current => $battery,
  };

  my $rssi = ($bytes->[$off] & 0xf0) >> 4;

  if ($trx_rssi == 1) {
  	push @$res, {
		device => $dev,
		type => 'rssi',
		current => sprintf("%d",$rssi),
  	};
  }

}

sub TRX_WEATHER_battery {
  my ($bytes, $dev, $res, $off) = @_;

  my $battery;

  my $battery_level = ($bytes->[$off] & 0x0f) + 1;

  if ($battery_level > 5) {
    $battery = sprintf("ok %d0%%",$battery_level);
  } else {
    $battery = sprintf("low %d0%%",$battery_level);
  }

  push @$res, {
	device => $dev,
	type => 'battery',
	current => $battery,
  };

  my $rssi = ($bytes->[$off] & 0xf0) >> 4;

  if ($trx_rssi == 1) {
  	push @$res, {
		device => $dev,
		type => 'rssi',
		current => sprintf("%d",$rssi),
  	};
  }

}


# Test if to use longid for device type
sub TRX_WEATHER_use_longid {
  my ($longids,$dev_type) = @_;

  return 0 if ($longids eq "");
  return 0 if ($longids eq "0");

  return 1 if ($longids eq "1");
  return 1 if ($longids eq "ALL");

  return 1 if(",$longids," =~ m/,$dev_type,/);

  return 0;
}


# ------------------------------------------------------------
# T R X _ W E A T H E R _ c o m m o n _ a n e m o m e t e r
#    0x5610 => { part => 'WIND'
sub TRX_WEATHER_common_anemometer {
    	my $type = shift;
	my $longids = shift;
    	my $bytes = shift;

  my $subtype = sprintf "%02x", $bytes->[1];
  my $dev_type;

  my %devname =
    (	# HEXSTRING => "NAME"
	0x01 => "WTGR800_A",
	0x02 => "WGR800",
	0x03 => "WGR918",
	0x04 => "TFA_WIND",
	0x05 => "WDS500", # UPM WDS500
	0x06 => "WS2300_WIND", # WS2300
	0x07 => "WS4500_WIND", # Alecto WS4500, Auriol H13726, Hama EWS1500, Meteoscan W155/W160, Ventus WS155
  );

  if (exists $devname{$bytes->[1]}) {
  	$dev_type = $devname{$bytes->[1]};
  } else {
  	Log3 undef, 3, "TRX_WEATHER: common_anemometer error undefined subtype=$subtype";
  	my @res = ();
  	return @res;
  }

  my $dev_str = $dev_type;
  if (TRX_WEATHER_use_longid($longids,$dev_type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if ($bytes->[4] > 0) {
  	$dev_str .= $DOT.sprintf("%d", $bytes->[4]);
  }

  my @res = ();

  # hexline debugging
  if ($TRX_HEX_debug) {
    my $hexline = ""; for (my $i=0;$i<@$bytes;$i++) { $hexline .= sprintf("%02x",$bytes->[$i]);} 
    push @res, { device => $dev_str, type => 'hexline', current => $hexline, units => 'hex', };
  }

  my $dir = $bytes->[5]*256 + $bytes->[6];
  my $dirname = $TRX_WEATHER_winddir_name[int((($dir + 11.25) % 360) / 22.5)];

  my $avspeed = ($bytes->[7]*256 + $bytes->[8]) / 10;
  my $speed = ($bytes->[9]*256 + $bytes->[10]) / 10;

  if ($dev_type eq "TFA_WIND") {
  	TRX_WEATHER_temperature($bytes, $dev_str, \@res, 11); 
  	TRX_WEATHER_chill_temperature($bytes, $dev_str, \@res, 13); 
  }

  push @res, {
	device => $dev_str,
	type => 'speed',
	current => $speed,
	average => $avspeed,
	units => 'mps',
  } , {
	device => $dev_str,
	type => 'direction',
	current => $dir,
	string => $dirname,
	units => 'degrees',
  };

  TRX_WEATHER_battery($bytes, $dev_str, \@res, 15);

  return @res;
}


# --------------------------------------------------------------------
# T R X _ W E A T H E R _ c o m m o n _ b b q
#   0x4e0a => { part => 'BBQ'
#
sub TRX_WEATHER_common_bbq {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;

  my $subtype = sprintf "%02x", $bytes->[1];
  my $dev_type;

  my %devname =
    (	# HEXSTRING => "NAME"
	0x01 => "ET732",
  );

  if (exists $devname{$bytes->[1]}) {
  	$dev_type = $devname{$bytes->[1]};
  } else {
  	Log3 undef, 3, "TRX_WEATHER: common_bbq error undefined subtype=$subtype";
  	my @res = ();
  	return @res;
  }

  #my $seqnbr = sprintf "%02x", $bytes->[2];

  my $dev_str = $dev_type;
  if (TRX_WEATHER_use_longid($longids,$dev_type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[4]);
  }

  my @res = ();

  # hexline debugging
  if ($TRX_HEX_debug) {
    my $hexline = ""; for (my $i=0;$i<@$bytes;$i++) { $hexline .= sprintf("%02x",$bytes->[$i]);} 
    push @res, { device => $dev_str, type => 'hexline', current => $hexline, units => 'hex', };
  }

  TRX_WEATHER_temperature_food($bytes, $dev_str, \@res, 5); 
  TRX_WEATHER_temperature_bbq($bytes, $dev_str, \@res, 7); 
  TRX_WEATHER_simple_battery($bytes, $dev_str, \@res, 9);
  return @res;
}

#########################################
# From xpl-perl/lib/xPL/Util.pm:
sub RFXMETER_hi_nibble {
  ($_[0]&0xf0)>>4;
}
sub RFXMETER_lo_nibble {
  $_[0]&0xf;
}
sub RFXMETER_nibble_sum {
  my $c = $_[0];
  my $s = 0;
  foreach (0..$_[0]-1) {
    $s += RFXMETER_hi_nibble($_[1]->[$_]);
    $s += RFXMETER_lo_nibble($_[1]->[$_]);
  }
  $s += RFXMETER_hi_nibble($_[1]->[$_[0]]) if (int($_[0]) != $_[0]);
  return $s;
}
#####################################

sub TRX_WEATHER_common_rfxmeter {
  my $typeDev = shift;
  my $longids = shift;
  my $bytes = shift;
  
  my $dev_type;

  my %devname =
    (  # HEXSTRING => "NAME"
      0x00 => "RFXMETER",
  );

  if (exists $devname{$bytes->[1]}) {
    $dev_type = $devname{$bytes->[1]};
  } else {
    my $subtype = sprintf "%02x", $bytes->[1];
    Log3 undef, 3, "TRX_WEATHER: common_rfxmeter error undefined subtype=$subtype";
    my @res = ();
    return @res;
  }

  my $dev_str = $dev_type;
  $dev_str .= $DOT.sprintf("%d", $bytes->[3]);

  my @res = ();

  # hexline debugging
  if ($TRX_HEX_debug) {
    my $hexline = ""; for (my $i=0;$i<@$bytes;$i++) { $hexline .= sprintf("%02x",$bytes->[$i]);} 
    push @res, { device => $dev_str, type => 'hexline', current => $hexline, units => 'hex', };
  }

  if ( ($bytes->[3] + ($bytes->[4]^0xf)) != 0xff) {
    Log 4, "RFXMETER: check1 failed";
    return @res;
  }
  
  my $type = RFXMETER_hi_nibble($bytes->[5]);
  Log 4, "RFXMETER: type=$type";

  my $check = RFXMETER_lo_nibble($bytes->[5]);
  Log 4, "RFXMETER: check=$check";

# we would do the parity check here but I wasn't able to find the parity bits in the msg
# I will just assume the parity check was done inside the RfxTrx already
#  my $nibble_sum = RFXMETER_nibble_sum(5.5, $bytes);
#  my $parity = 0xf^($nibble_sum&0xf);
#  unless ($parity == $check) {
#    warn "RFXMeter parity error $parity != $check\n";
#    return @res;
#  }

  my $type_str =
      [
       'normal data packet',
       'new interval time set',
       'calibrate value',
       'new address set',
       'counter value reset to zero',
       'set 1st digit of counter value integer part',
       'set 2nd digit of counter value integer part',
       'set 3rd digit of counter value integer part',
       'set 4th digit of counter value integer part',
       'set 5th digit of counter value integer part',
       'set 6th digit of counter value integer part',
       'counter value set',
       'set interval mode within 5 seconds',
       'calibration mode within 5 seconds',
       'set address mode within 5 seconds',
       'identification packet',
      ]->[$type];
      
  unless ($type == 0) {
    warn "Unsupported rfxmeter message $type_str\n";
    return @res;
  }
  
  # the byte order of the actual value is different from the original RfxMeter protocol
  # again I assume this was done by RfxTrx
  my $current = ($bytes->[6] << 16)  + ($bytes->[7] << 8)  + ($bytes->[8]);
  Log 4, "TRX_WEATHER: current=$current";

  # I could not make sense of all bytes of the message. Example message:
  # 7100 29 8676 00 016cd8 69
  # adr  ?? ID   ?? data   ??
  
  push @res, {
       device => $dev_str,
       type => 'rfxmeter',
       current => $current,
       units => ''
  };
    
  return @res;
}

# --------------------------------------------------------------------
# T R X _ W E A T H E R _ c o m m o n _ t e m p
#   0x5008 => { part => 'TEMP'
sub TRX_WEATHER_common_temp {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;

  my $subtype = sprintf "%02x", $bytes->[1];
  my $dev_type;

  my %devname =
    (	# HEXSTRING => "NAME"
	0x01 => "THR128",
	0x02 => "THGR132N", # was THGR228N,
	0x03 => "THWR800",
	0x04 => "RTHN318",
	0x05 => "TX3", # LaCrosse TX3
	0x06 => "TS15C", 
	0x07 => "VIKING_02811", # Viking 02811
	0x08 => "WS2300", # La Crosse WS2300
	0x09 => "RUBICSON", # RUBiCSON
	0x0a => "TFA_303133", # TFA 30.3133
	0x0b => "WT0122", # WT0122
  );

  if (exists $devname{$bytes->[1]}) {
  	$dev_type = $devname{$bytes->[1]};
  } else {
  	Log3 undef, 3, "TRX_WEATHER: common_temp error undefined subtype=$subtype";
  	my @res = ();
  	return @res;
  }

  #my $seqnbr = sprintf "%02x", $bytes->[2];

  my $dev_str = $dev_type;
  if (TRX_WEATHER_use_longid($longids,$dev_type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if ($bytes->[4] > 0) {
  	$dev_str .= $DOT.sprintf("%d", $bytes->[4]);
  }

  my @res = ();

  # hexline debugging
  if ($TRX_HEX_debug) {
    my $hexline = ""; for (my $i=0;$i<@$bytes;$i++) { $hexline .= sprintf("%02x",$bytes->[$i]);} 
    push @res, { device => $dev_str, type => 'hexline', current => $hexline, units => 'hex', };
  }

  TRX_WEATHER_temperature($bytes, $dev_str, \@res, 5); 
  TRX_WEATHER_simple_battery($bytes, $dev_str, \@res, 7);
  return @res;
}

# --------------------------------------------------------------------
# T R X _ W E A T H E R _ c o m m o n _ h y d r o
#   0x5108 => { part => 'HYDRO'
sub TRX_WEATHER_common_hydro {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;

  my $subtype = sprintf "%02x", $bytes->[1];
  my $dev_type;

  my %devname =
    (	# HEXSTRING => "NAME"
	0x01 => "TX3", # LaCrosse TX3
	0x02 => "WS2300", # LaCrosse WS2300 Humidity
	0x03 => "S80", # Inovalley S80 plant humidity sensor
  );

  if (exists $devname{$bytes->[1]}) {
  	$dev_type = $devname{$bytes->[1]};
  } else {
  	Log3 undef, 3, "TRX_WEATHER: common_hydro error undefined subtype=$subtype";
  	my @res = ();
  	return @res;
  }

  my $dev_str = $dev_type;
  if (TRX_WEATHER_use_longid($longids,$dev_type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if ($bytes->[4] > 0) {
  	$dev_str .= $DOT.sprintf("%d", $bytes->[4]);
  }

  my @res = ();

  # hexline debugging
  if ($TRX_HEX_debug) {
    my $hexline = ""; for (my $i=0;$i<@$bytes;$i++) { $hexline .= sprintf("%02x",$bytes->[$i]);} 
    push @res, { device => $dev_str, type => 'hexline', current => $hexline, units => 'hex', };
  }

  TRX_WEATHER_humidity($bytes, $dev_str, \@res, 5); 
  TRX_WEATHER_simple_battery($bytes, $dev_str, \@res, 7);
  return @res;
}

# --------------------------------------------------------------------
# T R X _ W E A T H E R _ c o m m o n _ t e m p h y d r o
#   0x520a => { part => 'TEMPHYDRO'
sub TRX_WEATHER_common_temphydro {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;

  my $subtype = sprintf "%02x", $bytes->[1];
  my $dev_type;

  my %devname =
    (	# HEXSTRING => "NAME"
	0x01 => "THGR228N", # THGN122/123, THGN132, THGR122/228/238/268
	0x02 => "THGR810",
	0x03 => "RTGR328",
	0x04 => "THGR328",
	0x05 => "WTGR800_T",
	0x06 => "THGR918",
	0x07 => "TFATS34C", 
	0x08 => "WT450H", # WT260,WT260H,WT440H,WT450,WT450H
	0x09 => "VIKING_02038", # Viking 02035,02038 (02035 has no humidity)
	0x0a => "RUBICSON", # Rubicson 
	0x0b => "EW109", # EW109 
	0x0c => "XT300", # Imagintronix/Opus XT300 Soil sensor
	0x0d => "WS1700", # Alecto WS1700 and compatibles
	0x0e => "WS3500", # Alecto WS3500, WS4500, Auriol H13726, Hama EWS1500, Meteoscan W155/W160, Ventus WS155
  );

  if (exists $devname{$bytes->[1]}) {
  	$dev_type = $devname{$bytes->[1]};
  } else {
  	Log3 undef, 3, "TRX_WEATHER: common_temphydro error undefined subtype=$subtype";
  	my @res = ();
  	return @res;
  }

  my $dev_str = $dev_type;
  if (TRX_WEATHER_use_longid($longids,$dev_type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  } elsif ($dev_type eq "TFATS34C") {
  	#Log3 undef, 1,"TRX_WEATHER: TFA";
	if ($bytes->[3] > 0x20 && $bytes->[3] <= 0x3F) {
  	#Log3 undef, 1,"TRX_WEATHER: TFA 1";
		$dev_str .= $DOT."1"; 
	} elsif ($bytes->[3] >= 0x40 && $bytes->[3] <= 0x5F) {
  	#Log3 undef, 1,"TRX_WEATHER: TFA 2";
		$dev_str .= $DOT."2"; 
	} elsif ($bytes->[3] >= 0x60 && $bytes->[3] <= 0x7F) {
  	#Log3 undef, 1,"TRX_WEATHER: TFA 3";
		$dev_str .= $DOT."3"; 
	} elsif ($bytes->[3] >= 0xA0 && $bytes->[3] <= 0xBF) {
  	#Log3 undef, 1,"TRX_WEATHER: TFA 4";
		$dev_str .= $DOT."4"; 
	} elsif ($bytes->[3] >= 0xC0 && $bytes->[3] <= 0xDF) {
  	#Log3 undef, 1,"TRX_WEATHER: TFA 5";
		$dev_str .= $DOT."5"; 
	} else {
  	#Log3 undef, 1,"TRX_WEATHER: TFA 9";
		$dev_str .= $DOT."9"; 
	}
  }
  if ($dev_type ne "TFATS34C" && $bytes->[4] > 0) {
  	$dev_str .= $DOT.sprintf("%d", $bytes->[4]);
  }

  my @res = ();

  # hexline debugging
  if ($TRX_HEX_debug) {
    my $hexline = ""; for (my $i=0;$i<@$bytes;$i++) { $hexline .= sprintf("%02x",$bytes->[$i]);} 
    push @res, { device => $dev_str, type => 'hexline', current => $hexline, units => 'hex', };
  }

  TRX_WEATHER_temperature($bytes, $dev_str, \@res, 5);
  TRX_WEATHER_humidity($bytes, $dev_str, \@res, 7); 
  if ($dev_type eq "THGR918") {
  	TRX_WEATHER_battery($bytes, $dev_str, \@res, 9);
  } else {
  	TRX_WEATHER_simple_battery($bytes, $dev_str, \@res, 9);
  }
  return @res;
}

# --------------------------------------------------------------------
# T R X _ W E A T H E R _ c o m m o n _ t e m p h y d r o b a r o
#   0x540d => { part => 'TEMPHYDROBARO'
sub TRX_WEATHER_common_temphydrobaro {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;

  my $subtype = sprintf "%02x", $bytes->[1];
  my $dev_type;

  my %devname =
    (	# HEXSTRING => "NAME"
	0x01 => "BTHR918",
	0x02 => "BTHR918N",
  );

  if (exists $devname{$bytes->[1]}) {
  	$dev_type = $devname{$bytes->[1]};
  } else {
  	Log3 undef, 3, "TRX_WEATHER: common_temphydrobaro error undefined subtype=$subtype";
  	my @res = ();
  	return @res;
  }

  my $dev_str = $dev_type;
  if (TRX_WEATHER_use_longid($longids,$dev_type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if ($bytes->[4] > 0) {
  	$dev_str .= $DOT.sprintf("%d", $bytes->[4]);
  }

  my @res = ();

  # hexline debugging
  if ($TRX_HEX_debug) {
    my $hexline = ""; for (my $i=0;$i<@$bytes;$i++) { $hexline .= sprintf("%02x",$bytes->[$i]);} 
    push @res, { device => $dev_str, type => 'hexline', current => $hexline, units => 'hex', };
  }

  TRX_WEATHER_temperature($bytes, $dev_str, \@res, 5); 
  TRX_WEATHER_humidity($bytes, $dev_str, \@res, 7); 
  TRX_WEATHER_pressure($bytes, $dev_str, \@res, 9);
  TRX_WEATHER_simple_battery($bytes, $dev_str, \@res, 12);
  return @res;
}

# --------------------------------------------------------------------
# T R X _ W E A T H E R _ c o m m o n _ r a i n
#   0x550b => { part => 'RAIN'
sub TRX_WEATHER_common_rain {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;


  my $subtype = sprintf "%02x", $bytes->[1];
  my $dev_type;

  my %devname =
    (	# HEXSTRING => "NAME"
	0x01 => "RGR918",
	0x02 => "PCR800",
	0x03 => "TFA_RAIN",
	0x04 => "RG700",
	0x05 => "WS2300_RAIN", # WS2300
	0x06 => "TX5_RAIN", # La Crosse TX5
	0x07 => "WS4500_RAIN", # Alecto WS4500, Auriol H13726, Hama EWS1500, Meteoscan W155/W160,
  0x09 => "TFA_RAIN",
  );

  if (exists $devname{$bytes->[1]}) {
  	$dev_type = $devname{$bytes->[1]};
  } else {
  	Log3 undef, 3, "TRX_WEATHER: common_rain error undefined subtype=$subtype";
  	my @res = ();
  	return @res;
  }

  my $dev_str = $dev_type;
  if (TRX_WEATHER_use_longid($longids,$dev_type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if ($bytes->[4] > 0) {
  	$dev_str .= $DOT.sprintf("%d", $bytes->[4]);
  }

  my @res = ();

  # hexline debugging
  if ($TRX_HEX_debug) {
    my $hexline = ""; for (my $i=0;$i<@$bytes;$i++) { $hexline .= sprintf("%02x",$bytes->[$i]);} 
    push @res, { device => $dev_str, type => 'hexline', current => $hexline, units => 'hex', };
  }

  my $rain = $bytes->[5]*256 + $bytes->[6];
  if ($dev_type eq "RGR918") {
  	push @res, {
		device => $dev_str,
		type => 'rain',
		current => $rain,
		units => 'mm/h',
  	};
  } elsif ($dev_type eq "PCR800") {
	$rain = $rain / 100;
  	push @res, {
		device => $dev_str,
		type => 'rain',
		current => $rain,
		units => 'mm/h',
  	};
  }

  if ($dev_type ne "TX5_RAIN") {
  	my $train = ($bytes->[7]*256*256 + $bytes->[8]*256 + $bytes->[9])/10; # total rain
  	push @res, {
		device => $dev_str,
		type => 'train',
		current => $train,
		units => 'mm',
  	};
  }

  TRX_WEATHER_battery($bytes, $dev_str, \@res, 10);
  return @res;
}

my @uv_str =
  (
   qw/low low low/, # 0 - 2
   qw/medium medium medium/, # 3 - 5
   qw/high high/, # 6 - 7
   'very high', 'very high', 'very high', # 8 - 10
  );

sub TRX_WEATHER_uv_string {
  $uv_str[$_[0]] || 'dangerous';
}

# ------------------------------------------------------------
# T R X _ W E A T H E R _ c o m m o n _ u v
# *   0x5709 => { part => 'UV'
sub TRX_WEATHER_common_uv {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;

  my $subtype = sprintf "%02x", $bytes->[1];
  my $dev_type;

  my %devname =
    (	# HEXSTRING => "NAME"
	0x01 => "UVN128", # Oregon UVN128, UV138
	0x02 => "UVN800", # Oregon UVN800
	0x03 => "TFA_UV", # TFA_UV-Sensor
  );

  if (exists $devname{$bytes->[1]}) {
  	$dev_type = $devname{$bytes->[1]};
  } else {
  	Log3 undef, 3, "TRX_WEATHER: common_uv error undefined subtype=$subtype";
  	my @res = ();
  	return @res;
  }

  #my $seqnbr = sprintf "%02x", $bytes->[2];

  my $dev_str = $dev_type;
  if (TRX_WEATHER_use_longid($longids,$dev_type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if ($bytes->[4] > 0) {
  	$dev_str .= $DOT.sprintf("%d", $bytes->[4]);
  }

  my @res = ();

  # hexline debugging
  if ($TRX_HEX_debug) {
    my $hexline = ""; for (my $i=0;$i<@$bytes;$i++) { $hexline .= sprintf("%02x",$bytes->[$i]);} 
    push @res, { device => $dev_str, type => 'hexline', current => $hexline, units => 'hex', };
  }

  my $uv = $bytes->[5]/10; # UV
  my $risk = TRX_WEATHER_uv_string(int($uv));

  push @res, {
	device => $dev_str,
	type => 'uv',
	current => $uv,
	risk => $risk,
	units => '',
  };


  if ($dev_type eq "TFA_UV") {
  	TRX_WEATHER_temperature($bytes, $dev_str, \@res, 6); 
  }
  TRX_WEATHER_simple_battery($bytes, $dev_str, \@res, 8);
  return @res;
}

# ------------------------------------------------------------
# T R X _ W E A T H E R _ c o m m o n _ d a t e t i m e
#    0x580D => { part => 'DATE', method => \&TRX_WEATHER_common_datetime, },
sub TRX_WEATHER_common_datetime {
    	my $type = shift;
	my $longids = shift;
    	my $bytes = shift;

  my $subtype = sprintf "%02x", $bytes->[1];
  my $dev_type;

  my %devname =
    (	# HEXSTRING => "NAME"
	0x01 => "RTGR328_DATE", # RTGR328N datetime datagram
  );

  if (exists $devname{$bytes->[1]}) {
  	$dev_type = $devname{$bytes->[1]};
  } else {
  	Log3 undef, 3, "TRX_WEATHER: common_datetime error undefined subtype=$subtype";
  	my @res = ();
  	return @res;
  }

  my $dev_str = $dev_type;
  if (TRX_WEATHER_use_longid($longids,$dev_type)) {
  	$dev_str .= $DOT.sprintf("%02x%02x", $bytes->[3],$bytes->[4]);
  }

  my @res = ();

  # hexline debugging
  if ($TRX_HEX_debug) {
    my $hexline = ""; for (my $i=0;$i<@$bytes;$i++) { $hexline .= sprintf("%02x",$bytes->[$i]);} 
    push @res, { device => $dev_str, type => 'hexline', current => $hexline, units => 'hex', };
  }

  push @res, {
	device => $dev_str,
	type => 'date',
	current => sprintf("%02d-%02d-%02d", $bytes->[5],$bytes->[6],$bytes->[7]),
	units => 'yymmdd',
  };

  push @res, {
	device => $dev_str,
	type => 'time',
	current => sprintf("%02d:%02d:%02d", $bytes->[9],$bytes->[10],$bytes->[11]),
	units => 'hhmmss',
  };

  TRX_WEATHER_simple_battery($bytes, $dev_str, \@res, 12); 

  return @res;
}


# ------------------------------------------------------------
# T R X _ W E A T H E R _ c o m m o n _ e n e r g y ( )
#
# devices: CM119, CM160, CM180
sub TRX_WEATHER_common_energy {
    	my $type = shift;
	my $longids = shift;
    	my $bytes = shift;

  my $subtype = sprintf "%02x", $bytes->[1];
  my $dev_type;

  my %devname =
    (	# HEXSTRING => "NAME"
	0x01 => "CM160", # CM119, CM160
	0x02 => "CM180", # CM180
  );

  if (exists $devname{$bytes->[1]}) {
  	$dev_type = $devname{$bytes->[1]};
  } else {
  	Log3 undef, 3, "TRX_WEATHER: common_energy error undefined subtype=$subtype";
  	my @res = ();
  	return @res;
  }

  #my $seqnbr = sprintf "%02x", $bytes->[2];

  my $dev_str = $dev_type;
  $dev_str .= $DOT.sprintf("%02x%02x", $bytes->[3],$bytes->[4]);

  my @res = ();

  # hexline debugging
  if ($TRX_HEX_debug) {
    my $hexline = ""; for (my $i=0;$i<@$bytes;$i++) { $hexline .= sprintf("%02x",$bytes->[$i]);} 
    push @res, { device => $dev_str, type => 'hexline', current => $hexline, units => 'hex', };
  }

  my $energy_current = (
	$bytes->[6] * 256*256*256 + 
	$bytes->[7] * 256*256 +
	$bytes->[8] * 256 +
	$bytes->[9]
	);

  push @res, {
	device => $dev_str,
	type => 'energy_current',
	current => $energy_current,
	units => 'W',
  };

  my $energy_total = (
	$bytes->[10] * 256*256*256*256*256 + 
	$bytes->[11] * 256*256*256*256 +
	$bytes->[12] * 256*256*256 + 
	$bytes->[13] * 256*256 +
	$bytes->[14] * 256 +
	$bytes->[15]
	) / 223.666;
  $energy_total = $energy_total / 1000;

  push @res, {
	device => $dev_str,
	type => 'energy_total',
	current => $energy_total,
	units => 'kWh',
  };

  my $count = $bytes->[5];
  #  TRX_WEATHER_simple_battery($bytes, $dev_str, \@res, 16) if ($count==0 || $count==1 || $count==2 || $count==3 || $count==8 || $count==9);
  TRX_WEATHER_simple_battery($bytes, $dev_str, \@res, 16); 

  return @res;
}

# ------------------------------------------------------------
#  T R X _ W E A T H E R _ c o m m o n _ e n e r g y 2
#
# devices: CM180i
sub TRX_WEATHER_common_energy2 {
    	my $type = shift;
	my $longids = shift;
    	my $bytes = shift;

  my $subtype = sprintf "%02x", $bytes->[1];
  my $dev_type;

  my %devname =
    (	# HEXSTRING => "NAME"
	0x01 => "CM180I", # CM180i
  );

  if (exists $devname{$bytes->[1]}) {
  	$dev_type = $devname{$bytes->[1]};
  } else {
  	Log3 undef, 3, "TRX_WEATHER: common_energy2 error undefined subtype=$subtype";
  	my @res = ();
  	return @res;
  }

  #my $seqnbr = sprintf "%02x", $bytes->[2];

  my $dev_str = $dev_type;
  $dev_str .= $DOT.sprintf("%02x%02x", $bytes->[3],$bytes->[4]);

  my @res = ();

  # hexline debugging
  if ($TRX_HEX_debug) {
    my $hexline = ""; for (my $i=0;$i<@$bytes;$i++) { $hexline .= sprintf("%02x",$bytes->[$i]);} 
    push @res, { device => $dev_str, type => 'hexline', current => $hexline, units => 'hex', };
  }

  my $energy_count = $bytes->[5];

  if (1) {
	my $energy_current_ch1 = ($bytes->[6] * 256 + $bytes->[7])/10;
  	my $energy_current_ch2 = ($bytes->[8] * 256 + $bytes->[9])/10;
  	my $energy_current_ch3 = ($bytes->[10] * 256 + $bytes->[11]/10);

  	push @res, {
		device => $dev_str,
		type => 'energy_ch1',
		current => $energy_current_ch1,
		units => 'A',
  	};
  	push @res, {
		device => $dev_str,
		type => 'energy_ch2',
		current => $energy_current_ch2,
		units => 'A',
  	};
  	push @res, {
		device => $dev_str,
		type => 'energy_ch3',
		current => $energy_current_ch3,
		units => 'A',
  	};
  } 
  if ($energy_count == 0) {
  	my $energy_total = (
		$bytes->[12] * 256*256*256*256*256 + 
		$bytes->[13] * 256*256*256*256 +
		$bytes->[14] * 256*256*256 + 
		$bytes->[15] * 256*256 +
		$bytes->[16] * 256 +
		$bytes->[17]
	) / 223.666;
  	$energy_total = $energy_total / 1000;

	
  	push @res, {
		device => $dev_str,
		type => 'energy_total',
		current => $energy_total,
		units => 'kWh',
  	};

  }
  #  TRX_WEATHER_simple_battery($bytes, $dev_str, \@res, 16) if ($count==0 || $count==1 || $count==2 || $count==3 || $count==8 || $count==9);
  TRX_WEATHER_simple_battery($bytes, $dev_str, \@res, 18); 

  return @res;
}

# ------------------------------------------------------------
#  T R X _ W E A T H E R _ c o m m o n _ e n e r g y 3
#
# devices: REVOLT
sub TRX_WEATHER_common_energy3 {
    	my $type = shift;
	my $longids = shift;
    	my $bytes = shift;

  my $subtype = sprintf "%02x", $bytes->[1];
  my $dev_type;

  my %devname =
    (	# HEXSTRING => "NAME"
	0x01 => "REVOLT", # Revolt 
  );

  if (exists $devname{$bytes->[1]}) {
  	$dev_type = $devname{$bytes->[1]};
  } else {
  	Log3 undef, 3, "TRX_WEATHER: common_energy3 error undefined subtype=$subtype";
  	my @res = ();
  	return @res;
  }

  #my $seqnbr = sprintf "%02x", $bytes->[2];

  my $dev_str = $dev_type;
  $dev_str .= $DOT.sprintf("%02x%02x", $bytes->[3],$bytes->[4]);

  my @res = ();

  # hexline debugging
  if ($TRX_HEX_debug) {
    my $hexline = ""; for (my $i=0;$i<@$bytes;$i++) { $hexline .= sprintf("%02x",$bytes->[$i]);} 
    push @res, { device => $dev_str, type => 'hexline', current => $hexline, units => 'hex', };
  }

  my $energy_voltage = $bytes->[5];
  push @res, {
	device => $dev_str,
	type => 'energy_voltage',
	current => $energy_voltage,
	units => 'V',
  };

  my $energy_current = ($bytes->[6] * 256 + $bytes->[7]) / 100;

  push @res, {
	device => $dev_str,
	type => 'energy_current_revolt',
	current => $energy_current,
	units => 'A',
  };

  my $energy_power = ($bytes->[8] * 256 + $bytes->[9]) / 10;

  push @res, {
	device => $dev_str,
	type => 'energy_power',
	current => $energy_power,
	units => 'W',
  };

  my $energy_total = ($bytes->[10] * 256 + $bytes->[11]) / 100;

  push @res, {
	device => $dev_str,
	type => 'energy_total',
	current => $energy_total,
	units => 'kWh',
  };

  my $energy_pf = $bytes->[12] / 100;
  push @res, {
	device => $dev_str,
	type => 'energy_pf',
	current => $energy_pf,
	units => '',
  };

  my $energy_freq = $bytes->[13];
  push @res, {
	device => $dev_str,
	type => 'energy_freq',
	current => $energy_freq,
	units => 'Hz',
  };

  my $rssi = ($bytes->[14] & 0xf0) >> 4;

  if ($trx_rssi == 1) {
  	push @res, {
		device => $dev_str,
		type => 'rssi',
		current => sprintf("%d",$rssi),
  	};
  }

  return @res;
}

# ------------------------------------------------------------
#
sub TRX_WEATHER_common_weight {
    	my $type = shift;
	my $longids = shift;
    	my $bytes = shift;

  my $subtype = sprintf "%02x", $bytes->[1];
  my $dev_type;

  my %devname =
    (	# HEXSTRING => "NAME"
	0x01 => "BWR101",
	0x02 => "GR101",
  );

  if (exists $devname{$bytes->[1]}) {
  	$dev_type = $devname{$bytes->[1]};
  } else {
  	Log3 undef, 3, "TRX_WEATHER: common_weight error undefined subtype=$subtype";
  	my @res = ();
  	return @res;
  }

  #my $seqnbr = sprintf "%02x", $bytes->[2];

  my $dev_str = $dev_type;
  if (TRX_WEATHER_use_longid($longids,$dev_type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if ($bytes->[4] > 0) {
  	$dev_str .= $DOT.sprintf("%d", $bytes->[4]);
  }

  my @res = ();

  # hexline debugging
  if ($TRX_HEX_debug) {
    my $hexline = ""; for (my $i=0;$i<@$bytes;$i++) { $hexline .= sprintf("%02x",$bytes->[$i]);} 
    push @res, { device => $dev_str, type => 'hexline', current => $hexline, units => 'hex', };
  }

  my $weight = ($bytes->[5]*256 + $bytes->[6])/10;

  push @res, {
	device => $dev_str,
	type => 'weight',
	current => $weight,
	units => 'kg',
  };

  #TRX_WEATHER_simple_battery($bytes, $dev_str, \@res, 7);

  return @res;
}


# -----------------------------
sub
TRX_WEATHER_Parse($$)
{
  my ($iohash, $hexline) = @_;

  #my $hashname = $iohash->{NAME};
  #my $longid = AttrVal($hashname,"longids","");
  #Log3 $iohash, $iohash, 5 ,"2: name=$hashname, attr longids = $longid";

  my $longids = 0;
  if (defined($attr{$iohash->{NAME}}{longids})) {
  	$longids = $attr{$iohash->{NAME}}{longids};
  	#Log3 $iohash, 5,"0: attr longids = $longids";
  }

  $trx_rssi = 0;
  if (defined($attr{$iohash->{NAME}}{rssi})) {
  	$trx_rssi = $attr{$iohash->{NAME}}{rssi};
  	#Log3 $iohash, 5, "0: attr rssi = $trx_rssi";
  }

  my $time = time();
  # convert to binary
  my $msg = pack('H*', $hexline);
  if ($time_old ==0) {
  	Log3 $iohash, 5, "TRX_WEATHER: decoding delay=0 hex=$hexline";
  } else {
  	my $time_diff = $time - $time_old ;
  	Log3 $iohash, 5, "TRX_WEATHER: decoding delay=$time_diff hex=$hexline";
  }
  $time_old = $time;

  # convert string to array of bytes. Skip length byte
  my @rfxcom_data_array = ();
  foreach (split(//, substr($msg,1))) {
    push (@rfxcom_data_array, ord($_) );
  }

  my $num_bytes = ord($msg);

  if ($num_bytes < 3) {
    return;
  }

  my $type = $rfxcom_data_array[0];

  my $sensor_id = unpack('H*', chr $type);

  my $key = ($type << 8) + $num_bytes;

  my $rec = $types{$key};

  unless ($rec) {
    Log3 $iohash, 1, "TRX_WEATHER: ERROR: Unknown sensor_id=$sensor_id message='$hexline'";
    return "";
  }
  
  my $method = $rec->{method};
  unless ($method) {
    Log3 $iohash, 4, "TRX_WEATHER: Possible message from Oregon part '$rec->{part}'";
    Log3 $iohash, 4, "TRX_WEATHER: sensor_id=$sensor_id";
    return;
  }

  my @res;

  if (! defined(&$method)) {
    Log3 $iohash, 4, "TRX_WEATHER: Error: Unknown function=$method. Please define it in file $0";
    Log3 $iohash, 4, "TRX_WEATHER: sensor_id=$sensor_id\n";
    return "";
  } else {
    Log3 $iohash, 5, "TRX_WEATHER: parsing sensor_id=$sensor_id message='$hexline'";
    @res = $method->($rec->{part}, $longids, \@rfxcom_data_array);
  }

  # get device name from first entry
  my $device_name = $res[0]->{device};
  #Log3 $iohash, 5, "device_name=$device_name";

  if (! defined($device_name)) {
    Log3 $iohash, 4, "TRX_WEATHER: error device_name undefined\n";
    return "";
  }

  my $def = $modules{TRX_WEATHER}{defptr}{"$device_name"};
  if(!$def) {
	Log3 $iohash, 3, "TRX_WEATHER: Unknown device $device_name, please define it";
    	return "UNDEFINED $device_name TRX_WEATHER $device_name";
  }
  # Use $def->{NAME}, because the device may be renamed:
  my $name = $def->{NAME};
  return "" if(IsIgnored($name));

  my $n = 0;
  my $tm = TimeNow();

  my $i;
  my $val = "";
  my $sensor = "";

  readingsBeginUpdate($def);
  foreach $i (@res){
 	#print "!> i=".$i."\n";
	#printf "%s\t",$i->{device};
	if ($i->{type} eq "temp") { 
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name Temperatur ".$i->{current}." ".$i->{units};
			$val .= "T: ".$i->{current}." ";

			$sensor = "temperature";			
			readingsBulkUpdate($def, $sensor, $i->{current});
  	} 
	elsif ($i->{type} eq "temp-bbq") { 
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name Temperature-bbq ".$i->{current}." ".$i->{units};
			$val .= "TB: ".$i->{current}." ";

			$sensor = "temp-bbq";			
			readingsBulkUpdate($def, $sensor, $i->{current});
  	} 
	elsif ($i->{type} eq "temp-food") { 
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name Temperatur-food ".$i->{current}." ".$i->{units};
			$val .= "TF: ".$i->{current}." ";

			$sensor = "temp-food";			
			readingsBulkUpdate($def, $sensor, $i->{current});
  	} 
	elsif ($i->{type} eq "chilltemp") { 
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name windchill ".$i->{current}." ".$i->{units};
			$val .= "CT: ".$i->{current}." ";

			$sensor = "windchill";			
			readingsBulkUpdate($def, $sensor, $i->{current});
  	} 
	elsif ($i->{type} eq "humidity") { 
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name Luftfeuchtigkeit ".$i->{current}.$i->{units};
			$val .= "H: ".$i->{current}." ";

			$sensor = "humidity";			
			readingsBulkUpdate($def, $sensor, $i->{current});
	}
	elsif ($i->{type} eq "battery") { 
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name Batterie ".$i->{current};
			my $tmp_battery = $i->{current};
			my @words = split(/\s+/,$i->{current});
			$val .= "BAT: ".$words[0]." "; #use only first word

			#$sensor = "battery";			
			readingsBulkUpdate($def, "battery", $i->{current});
			readingsBulkUpdate($def, "batteryState", $i->{current});
	}
	elsif ($i->{type} eq "pressure") { 
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name Luftdruck ".$i->{current}." ".$i->{units}." Vorhersage=".$i->{forecast};
			# do not add it due to problems with hms.gplot
			$val .= "P: ".$i->{current}." ";

			$sensor = "pressure";			
			readingsBulkUpdate($def, $sensor, $i->{current});

			$sensor = "forecast";			
			readingsBulkUpdate($def, $sensor, $i->{forecast});
	}
	elsif ($i->{type} eq "speed") { 
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name wind_speed ".$i->{current}." wind_avspeed ".$i->{average};
			$val .= "W: ".$i->{current}." ";
			$val .= "WA: ".$i->{average}." ";

			$sensor = "wind_speed";			
			readingsBulkUpdate($def, $sensor, $i->{current});

			$sensor = "wind_avspeed";			
			readingsBulkUpdate($def, $sensor, $i->{average});
	}
	elsif ($i->{type} eq "direction") { 
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name wind_dir ".$i->{current}." ".$i->{string};
			$val .= "WD: ".$i->{current}." ";
			$val .= "WDN: ".$i->{string}." ";

			$sensor = "wind_dir";
			readingsBulkUpdate($def, $sensor, $i->{current} . " " . $i->{string});
	}
	elsif ($i->{type} eq "rain") { 
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name rain ".$i->{current};
			$val .= "RR: ".$i->{current}." ";

			$sensor = "rain_rate";			
			readingsBulkUpdate($def, $sensor, $i->{current});
	}
	elsif ($i->{type} eq "train") { 
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name train ".$i->{current};
			$val .= "TR: ".$i->{current}." ";

			$sensor = "rain_total";			
			readingsBulkUpdate($def, $sensor, $i->{current});
	}
	elsif ($i->{type} eq "flip") { 
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name flip ".$i->{current};
			$val .= "F: ".$i->{current}." ";

			$sensor = "rain_flip";			
			readingsBulkUpdate($def, $sensor, $i->{current});
	}
	elsif ($i->{type} eq "uv") { 
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name uv_val ".$i->{current}." uv_risk ".$i->{risk};
			$val .= "UV: ".$i->{current}." ";
			$val .= "UVR: ".$i->{risk}." ";

			$sensor = "uv_val";			
			readingsBulkUpdate($def, $sensor, $i->{current});

			$sensor = "uv_risk";			
			readingsBulkUpdate($def, $sensor, $i->{risk});
	}
	elsif ($i->{type} eq "energy_current") { 
			my $energy_current = $i->{current};
			if (defined($def->{scale_current})) {
				$energy_current = $energy_current * $def->{scale_current};
				Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name scale_current=".$def->{scale_current};			
			}
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name energy_current=".$energy_current;			
			$val .= "ECUR: ".$energy_current." ";

			$sensor = "energy_current";
			#readingsBulkUpdate($def, $sensor, $energy_current." ".$i->{units});
			readingsBulkUpdate($def, $sensor, $energy_current);
	}
	elsif ($i->{type} eq "energy_ch1") { 
			my $energy_current = $i->{current};
			if (defined($def->{scale_current})) {
				$energy_current = $energy_current * $def->{scale_current};
				Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name energy_ch1 scale_current=".$def->{scale_current};			
			}
			Log3 $name, 5, "TRX_WEATHER: device=$device_name CH1 energy_current=$energy_current";			
			$val .= "CH1: ".$energy_current." ";

			$sensor = "energy_ch1";
			readingsBulkUpdate($def, $sensor, $energy_current);
	}
	elsif ($i->{type} eq "energy_ch2") { 
			my $energy_current = $i->{current};
			if (defined($def->{scale_current})) {
				$energy_current = $energy_current * $def->{scale_current};
				Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name energy_ch2 scale_current=".$def->{scale_current};			
			}
			Log3 $device_name, 5, "TRX_WEATHER: name=$name device=$device_name CH2 energy_current=$energy_current";			
			$val .= "CH2: ".$energy_current." ";

			$sensor = "energy_ch2";
			readingsBulkUpdate($def, $sensor, $energy_current);
	}
	elsif ($i->{type} eq "energy_ch3") { 
			my $energy_current = $i->{current};
			if (defined($def->{scale_current})) {
				$energy_current = $energy_current * $def->{scale_current};
				Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name energy_ch3 scale_current=".$def->{scale_current};			
			}
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name CH3 energy_current=".$energy_current;			
			$val .= "CH3: ".$energy_current." ";

			$sensor = "energy_ch3";
			readingsBulkUpdate($def, $sensor, $energy_current);
	}
	elsif ($i->{type} eq "energy_current_revolt") { 
			my $energy_current = $i->{current};
			if (defined($def->{scale_current})) {
				$energy_current = $energy_current * $def->{scale_current};
				Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name scale_current=".$def->{scale_current};			
			}
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name energy_current=".$energy_current;			
			#$val .= "ECUR: ".$energy_current." ";

			$sensor = "energy_current";
			readingsBulkUpdate($def, $sensor, $energy_current." ".$i->{units});
	}
	elsif ($i->{type} eq "energy_total") { 
			my $energy_total = $i->{current};
			if (defined($def->{scale_total}) && defined($def->{add_total})) {
				$energy_total = sprintf("%.4f",$energy_total * $def->{scale_total} + $def->{add_total});
				Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name energy_total scale_total=".$def->{scale_total};			
			}
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name energy_total=$energy_total";			
			$val .= "ESUM: ".$energy_total." ";

			$sensor = "energy_total";
			#readingsBulkUpdate($def, $sensor, $energy_total." ".$i->{units});
			readingsBulkUpdate($def, $sensor, $energy_total);
	}
	elsif ($i->{type} eq "energy_power") { 
			my $energy_power = $i->{current};
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name energy_power=$energy_power";			
			$val .= "EPOW: ".$energy_power." ";

			$sensor = "energy_power";
			readingsBulkUpdate($def, $sensor, $energy_power." ".$i->{units});
	}
	elsif ($i->{type} eq "energy_voltage") { 
			my $energy_voltage = $i->{current};
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name energy_voltage=$energy_voltage";			
			#$val .= "V: ".$energy_voltage." ";

			$sensor = "voltage";
			readingsBulkUpdate($def, $sensor, $energy_voltage." ".$i->{units});
	}
	elsif ($i->{type} eq "energy_pf") { 
			my $energy_pf = $i->{current};
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name energy_pf=$energy_pf";			
			#$val .= "PF: ".$energy_pf." ";

			$sensor = "energy_pf";
			readingsBulkUpdate($def, $sensor, $energy_pf." ".$i->{units});
	}
	elsif ($i->{type} eq "energy_freq") { 
			my $energy_freq = $i->{current};
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name energy_freq=$energy_freq";			
			#$val .= "FREQ: ".$energy_freq." ";

			$sensor = "frequency";
			readingsBulkUpdate($def, $sensor, $energy_freq." ".$i->{units});

	}
	elsif ($i->{type} eq "weight") { 
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name weight ".$i->{current};
			$val .= "W: ".$i->{current}." ";

			$sensor = "weight";			
			readingsBulkUpdate($def, $sensor, $i->{current});
	}
	elsif ($i->{type} eq "hexline") { 
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name hexline ".$i->{current};
			$sensor = "hexline";			
			readingsBulkUpdate($def, $sensor, $i->{current});
	}
	elsif ($i->{type} eq "rssi") { 
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name rssi ".$i->{current};
			$sensor = "rssi";			
			readingsBulkUpdate($def, $sensor, $i->{current});
	}
	elsif ($i->{type} eq "date") { 
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name date ".$i->{current};
			$val .= $i->{current}." ";
			$sensor = "date";			
			readingsBulkUpdate($def, $sensor, $i->{current});
	}
	elsif ($i->{type} eq "time") { 
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name time ".$i->{current};
			$val .= $i->{current}." ";
			$sensor = "time";			
			readingsBulkUpdate($def, $sensor, $i->{current});
	}
	elsif ($i->{type} eq "setpoint") {
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name setpoint ".$i->{current}." ".$i->{units};
            $val .= "SP: ".$i->{current}." ";

			$sensor = "setpoint";
			readingsBulkUpdate($def, $sensor, $i->{current});
	}
	elsif ($i->{type} eq "demand") {
			Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name state ".$i->{current};
			if ($val eq "") {
				$val = "$i->{current}";
			}
			else {
				$val .= "D: ".$i->{current}." ";
			}
			$sensor = "demand";
			readingsBulkUpdate($def, $sensor, $i->{current});
	}
   	elsif ($i->{type} eq "rfxmeter") {
            my $current = $i->{current};
            $current = $current * $def->{scale_current} if (defined($def->{scale_current}));
            Log3 $name, 5, "TRX_WEATHER: name=$name device=$device_name co2 ".$i->{current}." ".$i->{units};
            $val .= (defined($def->{value_label}) ? $def->{value_label} : "V") . ": " .$current . " ";
            
            my $label = defined($def->{value_label}) ? lc $def->{value_label} : "meter";
            readingsBulkUpdate($def, $label, $current);
    }
	else { 
		Log3 $name, 1, "TRX_WEATHER: name=$name device=$device_name UNKNOWN Type: ".$i->{type}." Value: ".$i->{current} 
	}
  }

  if ("$val" ne "") {
    # remove heading and trailing space chars from $val
    $val =~ s/^\s+|\s+$//g;

    #$def->{STATE} = $val;
    readingsBulkUpdate($def, "state", $val);
  }

  readingsEndUpdate($def, 1);

  return $name;
}

1;

=pod
=item device
=item summary    interprets messages of weather sensors received by TRX
=item summary_DE interpretiert Nachrichten von Wettersensoren des TRX
=begin html

<a name="TRX_WEATHER"></a>
<h3>TRX_WEATHER</h3>
<ul>
  The TRX_WEATHER module interprets weather sensor messages received by a RTXtrx receiver. See <a href="http://www.rfxcom.com/oregon.htm">http://www.rfxcom.com/oregon.htm</a> for a list of
  Oregon Scientific weather sensors that could be received by the RFXtrx433 tranmitter. You need to define a RFXtrx433 receiver first. See
  See <a href="#TRX">TRX</a>.

  <br><br>

  <a name="TRX_WEATHERdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; TRX_WEATHER &lt;deviceid&gt;</code> <br>
    <br>
    <code>&lt;deviceid&gt;</code> 
    <ul>
	is the device identifier of the sensor. It consists of the sensors name and (only if the attribute longids is set of the RFXtrx433) an a one byte hex string (00-ff) that identifies the sensor. If an sensor uses an switch to set an additional is then this is also added. The define statement with the deviceid is generated automatically by autocreate. The following sensor names are used: <br>
	"THR128" (for THR128/138, THC138),<br>
	"THGR132N" (for THC238/268,THN132,THWR288,THRN122,THN122,AW129/131),<br>
	"THWR800", <br>
	"RTHN318", <br>
	"TX3_T" (for LaCrosse TX3, TX4, TX17),<br>
	"THGR228N" (for THGN122/123, THGN132, THGR122/228/238/268),<br>
	"THGR810",<br>
	"RTGR328",<br>
	"THGR328",<br>
	"WTGR800_T" (for temperature of WTGR800),<br>
	"THGR918" (for THGR918, THGRN228, THGN500),<br>
	"TFATS34C" (for TFA TS34C),<br>
	"BTHR918",<br>
	"BTHR918N (for BTHR918N, BTHR968),<br>
	"RGR918" (for RGR126/682/918),<br>
	"PCR800",<br>
	"TFA_RAIN" (for TFA rain sensor),<br>
	"WTGR800_A" (for wind sensor of WTGR800),<br>
	"WGR800" (for wind sensor of WGR800),<br>
	"WGR918" (for wind sensor of STR918 and WGR918),<br>
	"TFA_WIND" (for TFA wind sensor),<br>
	"BWR101" (for Oregon Scientific BWR101),<br>
	"GR101" (for Oregon Scientific GR101)
    "TLX7506" (for Digimax TLX7506),<br>
    "TH10" (for Digimax with short format),<br>
    </ul>
    <br>
    Example: <br>
    <ul>
    <code>define Tempsensor TRX_WEATHER TX3_T</code><br>
    <code>define Tempsensor3 TRX_WEATHER THR128_3</code><br>
    <code>define Windsensor TRX_WEATHER WGR918_A</code><br>
    <code>define Regensensor TRX_WEATHER RGR918</code><br>
    </ul>
  </ul>
  <br><br>
  <ul>
    <code>define &lt;name&gt; TRX_WEATHER &lt;deviceid&gt; [&lt;scale_current&gt; &lt;scale_total&gt; &lt;add_total&gt;]</code> <br>
    <br>
    <code>&lt;deviceid&gt;</code> 
    <ul>
  is the device identifier of the energy sensor. It consists of the sensors name and (only if the attribute longids is set of the RFXtrx433) an a two byte hex string (0000-ffff) that identifies the sensor. The define statement with the deviceid is generated automatically by autocreate. The following sensor names are used: <br>
	"CM160"	(for OWL CM119 or CM160),<br>
	"CM180"	(for OWL CM180),<br><br>
	"CM180i"(for OWL CM180i),<br><br>
    </ul>
    The following Readings are generated:<br>
    <ul>
      <code>"energy_current:"</code>: 
        <ul>
	Only for CM160 and CM180: current usage in Watt. If &lt;scale_current&gt is defined the result is: <code>energy_current * &lt;scale_current&gt;</code>.
        </ul>
      <code>"energy_chx:"</code>: 
        <ul>
	Only for CM180i (where chx is ch1, ch2 or ch3): current usage in Ampere. If &lt;scale_current&gt is defined the result is: <code>energy_chx * &lt;scale_current&gt;</code>.
        </ul>
      <code>"energy_total:"</code>: 
        <ul>
	current usage in kWh. If scale_total and add_total is defined the result is: <code>energy_total * &lt;scale_total&gt; + &lt;add_total&gt;</code>.
        </ul>
    <br>
    </ul>
    Example: <br>
    <ul>
    <code>define Tempsensor TRX_WEATHER CM160_1401</code><br>
    <code>define Tempsensor TRX_WEATHER CM180_1401 1 1 0</code><br>
    <code>define Tempsensor TRX_WEATHER CM180_1401 0.9 0.9 -1000</code><br>
    </ul>
  </ul>
  <br>

  <a name="TRX_WEATHERset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="TRX_WEATHERget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="TRX_WEATHERattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>



=end html
=cut
