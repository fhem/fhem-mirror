# From dancer0705
#
# Receive temperature sensor
#
# Unsupported models are saved in a device named CUL_TCM97001_Unknown
#
# Copyright (C)
# 2016 Bjoern Hempel
# 2022 Ralf9
#
# This program is free software; you can redistribute it and/or modify it under 
# the terms of the GNU General Public License as published by the Free Software 
# Foundation; either version 2 of the License, or (at your option) any later 
# version.
#
# This program is distributed in the hope that it will be useful, but 
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY 
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for 
# more details.
#
# You should have received a copy of the GNU General Public License along with 
# this program; if not, write to the 
# Free Software Foundation, Inc., 
# 51 Franklin St, Fifth Floor, Boston, MA 02110, USA
#
# $Id$
#
#
# 14.06.2017 W155(TCM21...) wind/rain    pejonp
# 25.06.2017 W155(TCM21...) wind/rain    pejonp
# 04.07.2017 PFR-130        rain         pejonp
# 04.07.2017 TFA 30.3161    temp/rain    pejonp
# 22.10.2017 W174           rain         elektron-bbs/HomeAutoUser
# 06.02.2018 W044  Ventus W155 Temp/Hum  pejonp
# 06.02.2018 W132  Ventus W155 Wind/Speed/Direction  pejonp
# 
# 14.06.2020 update log Unkown: now in Unknow log output the verbose is also used by a renamed device unknown
# 14.06.2020 fix Ventus W174, update log
# 28.08.2020 add KW9015 (TFA 30.3161)
# 10.01.2021 fix Battery at the model NC_WS
# 05.04.2022 add Mebus HQ7312
#            new attribute disableCreateUndefDevice: this can be used to deactivate the creation of new devices
#            new attribute disableUnknownEvents: with this, the events can be deactivated for unknown messages
# 15.11.2023 add NX7674: fridge and freezer thermometer
##############################################

package main;


use strict;
use warnings;

use SetExtensions;
use constant { TRUE => 1, FALSE => 0 };

#
# All suported models
#
my %models = (
    "TCM97..."    => 'TCM97...',
    "ABS700"      => 'ABS700',
    "TCM21...."   => 'TCM21....',
    "TCM218943"   => 'TCM218943',
    "Prologue"    => 'Prologue',
    "Rubicson"    => 'Rubicson',
    "NC_WS"       => 'NC_WS',
    "GT_WT_02"    => 'GT_WT_02',
    "AURIOL"      => 'AURIOL',
    "Auriol_Z31743B" => 'Auriol_Z31743B',
    "Auriol_IAN"  => 'Auriol_IAN',
    "PFR_130"      => 'PFR_130',
    "Type1"       => 'Type1',
    "Mebus"       => 'Mebus',
    "Mebus7312"   => 'Mebus7312',
    "Eurochron"   => 'Eurochron',
    "KW9010"      => 'KW9010',
    "KW9015"      => 'KW9015',
    "Unknown"     => 'Unknown',
    "W174"        => 'W174',
    "W044"        => 'W044',
    "W132"        => 'W132',
    "NX7674"      => 'NX7674'
);

sub
CUL_TCM97001_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^s....."; 
  $hash->{DefFn}     = \&CUL_TCM97001_Define;
  $hash->{UndefFn}   = \&CUL_TCM97001_Undef;
  $hash->{ParseFn}   = \&CUL_TCM97001_Parse;
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 showtime:1,0 " .
                        "$readingFnAttributes " .
                        "max-deviation-temp:1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50 ".
                        "max-diff-rain:0,1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50 ".
                        "negation-batt:0,1 ".
                        "windDirectionInverse:0,1 ".
                        "disableCreateUndefDevice:0,1 ".
                        "disableUnknownEvents:0,1 ".
                        "model:".join(",", sort keys %models);

  $hash->{AutoCreate}=
        {   	
            "CUL_TCM97001_Unknown.*" => { GPLOT => "", FILTER => "%NAME", autocreateThreshold => "2:10" }, 
            "CUL_TCM97001.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"},
            "Prologue_.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"},
            "Mebus_.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"},
            "NC_WS.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"}, 
            "ABS700.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"}, 
            "Eurochron.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"}, 
            "TCM21....*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"}, 
            "TCM218943.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"},
            "TCM97..._.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"}, 
            "GT_WT_02.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"}, 
            "Type1.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"}, 
            "Rubicson.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"},    
            "AURIOL.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"},
            "Auriol_IAN.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"},
            "PFR_130.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"}, 
            "KW9010.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"},      
            "KW9015.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "", FILTER => "%NAME", autocreateThreshold => "2:180"},
            "TCM97001.*" => {  ATTR => "event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:340"},
            "W174.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "rain4:Rain,", FILTER => "%NAME", autocreateThreshold => "2:180"},
            "W044.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"},
            "W132.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"},
            "Mebus7312.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"},
            "NX7674.*"    => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4:Temp,", FILTER => "%NAME", autocreateThreshold => "2:180"},
            "Unknown_.*" => { autocreateThreshold => "2:10"}
        };
}

#############################
sub
CUL_TCM97001_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> CUL_TCM97001 <code>"
        if(int(@a) < 3 || int(@a) > 5);

  my $dp = $modules{CUL_TCM97001}{defptr};
  my $old = ($dp && $dp->{$a[2]} ? $dp->{$a[2]}{NAME} : "");
  my $olddef = $hash->{OLDDEF};
  my $op = ($hash->{OLDDEF} ? "modify":"define");
  my $oc = ($hash->{OLDDEF} ? $hash->{CODE} : "");
  if ($olddef) {
    Log3 $hash, 2 , "CUL_TCM97001_Define: a2=$a[2], dp=$dp, OLDDEF=" . $olddef . ", code=" . $hash->{CODE} . ", old=$old";
  }
  return "Cannot $op as the code $a[2] is already used by $old" if ($old && $oc ne $a[2]);
  delete($modules{CUL_TCM97001}{defptr}{$oc}) if($oc);
 
  $hash->{CODE} = $a[2];
  $hash->{lastT} =  0;
  $hash->{lastH} =  0;

  $modules{CUL_TCM97001}{defptr}{$a[2]} = $hash;
  $hash->{STATE} = "Defined";

  return undef;
}

#####################################
sub
CUL_TCM97001_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{CUL_TCM97001}{defptr}{$hash->{CODE}})
     if(defined($hash->{CODE}) &&
        defined($modules{CUL_TCM97001}{defptr}{$hash->{CODE}}));
  return undef;
}

### inserted by elektron-bbs for rain gauge Ventus W174
# Checksum for Rain Gauge VENTUS W174 Protocol Auriol
# n8 = ( 0x7 + n0 + n1 + n2 + n3 + n4 + n5 + n6 + n7 ) & 0xf
sub checksum_W174 {
  my $hash = shift;
  my $msg = shift;
  my @decReverse = ();
  my $binrev;
  foreach my $x (split('', $msg)) {
    $binrev = reverse(sprintf("%04b",hex($x)));
    push (@decReverse, oct("0b".$binrev));
  }
  my $CRC = (7 + $decReverse[0]+$decReverse[1]+$decReverse[2]+$decReverse[3]+$decReverse[4]+$decReverse[5]+$decReverse[6]+$decReverse[7]) & 15;
  if ($CRC == $decReverse[8]) {
    Log3 $hash, 5 , $hash->{NAME} . ": CUL_TCM97001 W174 checksum ok, calc CRC = ref CRC = $CRC";
    return TRUE;
  }
  Log3 $hash, 5 , $hash->{NAME} . ": CUL_TCM97001 W174 ERROR, checksum not ok!, calc CRC = $CRC, ref CRC = $decReverse[8]";
  return FALSE;
}


### inserted by pejonp 3.2.2018 Ventus W132/W044
# Checksum for Temp/Hum/Wind  Ventus W132/W0044 Protocol Auriol
# n8 = ( 0xf - n0 - n1 - n2 - n3 - n4 - n5 - n6 - n7 ) & 0xf
sub checksum_W155 {
  my $hash = shift;
  my $msg = shift;
  my @decReverse = ();
  my $binrev;
  foreach my $x (split('', $msg)) {
    $binrev = reverse(sprintf("%04b",hex($x)));
    push (@decReverse, oct("0b".$binrev));
  }
  my $CRC = (15 - $decReverse[0] - $decReverse[1] - $decReverse[2] - $decReverse[3] - $decReverse[4] - $decReverse[5] - $decReverse[6] - $decReverse[7]) & 15;
  if ($CRC == $decReverse[8]) {
    Log3 $hash, 5 , $hash->{NAME} . ": CUL_TCM97001 W155 checksum ok, calc CRC = ref CRC = $CRC";
    return TRUE;
  }
  Log3 $hash, 5 , $hash->{NAME} . ": CUL_TCM97001 W155 ERROR, checksum not ok!, calc CRC = $CRC, ref CRC = $decReverse[8]";
  return FALSE;
}

#
# CRC Check for TCM 21....
#
#sub checkCRC {
#  my $msg = shift;
#  my @a = split("", $msg);
#  my $bitReverse = "";
#  my $x = undef;
#  foreach $x (@a) {
#     my $bin3=sprintf("%04b",hex($x));
#    $bitReverse = $bitReverse . reverse($bin3); 
#  }
#  my $hexReverse = unpack("H*", pack ("B*", $bitReverse));

  #Split reversed a again
#  my @aReverse = split("", $hexReverse);

#  my $CRC = (hex($aReverse[0])+hex($aReverse[1])+hex($aReverse[2])+hex($aReverse[3])
#            +hex($aReverse[4])+hex($aReverse[5])+hex($aReverse[6])+hex($aReverse[7])) & 15;
#  if ($CRC + hex($aReverse[8]) == 15) {
#      return TRUE;
#  }
#  return FALSE;
#}

#
# CRC 4 check for PFR-130
# xor 4 bits of nibble 0 to 7
#
sub checkCRC4 {
  my $hash = shift;
  my $msg = shift;
  my @a = split("", $msg);
  if(scalar(@a)<9){
    Log3 $hash, 5 , $hash->{NAME} . ": CUL_TCM97001 PFR_130 checkCRC4 failed for msg=($msg) length<9";
    return FALSE;
  }
  # xor nibbles 0 to 7 and compare to n8, if more nibble they might have been added to fill gap
  my $CRC = ( (hex($a[0])) ^ (hex($a[1])) ^ (hex($a[2])) ^ (hex($a[3])) ^ 
             (hex($a[4])) ^ (hex($a[5])) ^ (hex($a[6])) ^ (hex($a[7])) );
  if ($CRC ==  (hex($a[8]))) {
    Log3 $hash, 5 , $hash->{NAME} . ": CUL_TCM97001 PFR_130 checksum ok, calc CRC = ref CRC = $CRC";
    return TRUE;
  }
  Log3 $hash, 5 , $hash->{NAME} . ": CUL_TCM97001 PFR_130 ERROR, checksum not ok!, calc CRC = $CRC, ref CRC = " . hex($a[8]);
  return FALSE;
}
#
# CRC 4 check for PFR-130
# xor 4 bits of nibble 0 to 7
#

sub isRain {
  my $hash = shift;
  my $msg = shift;
  my @a = split("", $msg);
  if(scalar(@a)<9){
    Log3 $hash, 5 , $hash->{NAME} . ": CUL_TCM97001 isRain failed for msg=($msg) length<9";
    return FALSE;
  }
  # if bit 0 of nibble 2 is 1 then this is no rain data
  my $isRainData = ( (hex($a[2]) & 1) );
  if ($isRainData == 1) {
    Log3 $hash, 5 , $hash->{NAME} . ": CUL_TCM97001 isRain for msg=($msg) = FALSE";
    return FALSE;
  }
  Log3 $hash, 5 , $hash->{NAME} . ": CUL_TCM97001 isRain for msg=($msg) = TRUE";
  return TRUE;
}

#
# CRC Check for KW9010 and KW9015
#
sub checkCRCKW9010 {
  my $hash = shift;
  my $msg = shift;
  my @decReverse = ();
  my $binrev;
  foreach my $x (split('', $msg)) {
    $binrev = reverse(sprintf("%04b",hex($x)));
    push (@decReverse, oct("0b".$binrev));
  }
  my $CRC = ($decReverse[0]+$decReverse[1]+$decReverse[2]+$decReverse[3]+$decReverse[4]+$decReverse[5]+$decReverse[6]+$decReverse[7]) & 15;
  if ($CRC == $decReverse[8]) {
    Log3 $hash, 5 , $hash->{NAME} . ": CUL_TCM97001 KW9010 checksum ok, calc CRC = ref CRC = $CRC";
    return TRUE;
  }
  Log3 $hash, 5 , $hash->{NAME} . ": CUL_TCM97001 KW9010 ERROR, checksum not ok!, calc CRC = $CRC, ref CRC = $decReverse[8]";
  return FALSE;
}


#
# CRC Check for Mebus
#
sub checkCRC_Mebus {
  my $msg = shift;
  my @a = split("", $msg);

  my $CRC = ((hex($a[1])+hex($a[2])+hex($a[3])
            +hex($a[4])+hex($a[5])+hex($a[6])) -1) & 15;
  my $CRCCHECKVAL= (hex($a[0]));
  if ($CRC == $CRCCHECKVAL) {
      #Log3 "Unknown", 5 , "CUL_TCM97001 Mebus checksum ok, crc = $CRC";
      return TRUE;
  }
  return FALSE;
}

#
# CRC Check for GT_WT_02
### edited by elektron-bbs for GT_WT_02
sub checkCRC_GTWT02 {
  my $msg = shift;
  my @a = split("", $msg);
  my $CRC = (hex($a[0])+hex($a[1])+hex($a[2])+hex($a[3])
            +hex($a[4])+hex($a[5])+hex($a[6])+(hex($a[7]) & 0xE));
  my $CRCCHECKVAL= (hex($a[7].$a[8].$a[9]) & 0x1F8) >> 3; 
  if ($CRC  % 64 == $CRCCHECKVAL) {
      #Log3 "Unknown", 5 , "CUL_TCM97001 GT_WT_02 checksum ok, crc = $CRC";
      return TRUE;
  }
  return FALSE;
}

#
# CRC Check for Sensor-Type1
#
sub checkCRC_Type1 {
  my $msg = shift;
  my @a = split("", $msg);

  my $CRC = (hex($a[0])+hex($a[1])+hex($a[2])+hex($a[3])
            +hex($a[4])+hex($a[5])+hex($a[6])+hex($a[7]));
  my $CRCCHECKVAL= (hex($a[7].$a[8].$a[9]) & 0x1F8) >> 3; 
  if ($CRC == $CRCCHECKVAL) {
      #Log3 "Unknown", 5 , "CUL_TCM97001 Type1 checksum ok, crc = $CRC";
      return TRUE;
  }
  return FALSE;
}

sub checkCRC_sduinoID33 {
  my $hash = shift;
  my $bitData = shift;
  my $crc = 0;

  for (my $i=0; $i < 34; $i++) {
    if (substr($bitData, $i, 1) == ($crc & 1)) {
      $crc >>= 1;
    } else {
      $crc = ($crc>>1) ^ 12;
    }
  }
  $crc ^= oct("0b" . reverse(substr($bitData, 34, 4)));
  if ($crc == oct("0b" . reverse(substr($bitData, 38, 4)))) {
    Log3 $hash, 5 , $hash->{NAME} . ": CUL_TCM97001 sduinoID33 checksum ok, calc CRC = ref CRC = $crc";
    return TRUE;
  }
  Log3 $hash, 5 , $hash->{NAME} . ": CUL_TCM97001 sduinoID3 ERROR, checksum not ok!, calc CRC = $crc, ref CRC = " . oct("0b" . reverse(substr($bitData, 38, 4)));
  return FALSE;
}

sub checkRain {
  my $hash = shift;
  my $iodev = shift;
  my $rain = shift;
  my $name = $hash->{NAME};
  my $timeSinceLastUpdate = ReadingsAge($name, "state", 0);
  
  if ($timeSinceLastUpdate < 0) {
    $timeSinceLastUpdate *= -1;
  }
  if (defined($hash->{READINGS}{rain}{VAL})) {
    my $diffRain = 0;
    my $oldRain = $hash->{READINGS}{rain}{VAL};
    if ($rain > $oldRain) {
       $diffRain = ($rain - $oldRain);
    } else {
       $diffRain = ($oldRain - $rain);
    }
    $diffRain = sprintf("%.1f", $diffRain);
    Log3 $hash, 4, "$iodev: CUL_TCM97001 $name old rain $oldRain, age $timeSinceLastUpdate, new rain $rain, diff rain $diffRain";
    my $maxDiffRain = AttrVal($name, "max-diff-rain", 0);
    if ($maxDiffRain) {
       $maxDiffRain += $timeSinceLastUpdate / 60; 					# 1.0 Liter/Minute + maxDiffRain
       $maxDiffRain = sprintf("%.1f", $maxDiffRain + 0.05);			# round 0.1
       Log3 $hash, 4, "$iodev: CUL_TCM97001 $name max difference rain $maxDiffRain l";
       if ($diffRain > $maxDiffRain) {
          Log3 $hash, 3, "$iodev: CUL_TCM97001 $name ERROR - Rain diff too large (old $oldRain, new $rain, diff $diffRain)";
          return FALSE;
       }
    }
  }
  return TRUE
}

sub checkValues {
  my $hash = shift;
  my $model = shift;
  my $temp = shift;
  my $humidy = shift;
  my $iodev = $hash->{NAME};

  if (!defined($temp)) {
    return FALSE;
  }
  if ($temp > 60 || $temp < -30) {
    Log3 $hash, 4, "$iodev: CUL_TCM97001 $model - ERROR temperature $temp";
    return FALSE;
  }
  if (defined($humidy) && ($humidy < 0 || $humidy > 100)) {
    Log3 $hash, 4, "$iodev: CUL_TCM97001 $model - ERROR humidity $humidy";
    return FALSE;
  }
  return TRUE;
}

###################################
sub
CUL_TCM97001_Parse($$)
{
  my $enableLongIDs = TRUE; # Disable short ID support, enable longIDs
  my ($hash, $msg) = @_;
  $msg = substr($msg, 1);
  my @a = split("", $msg);
  my $iodev = $hash->{NAME};
  
  my $longids = AttrVal($iodev,'longids',1);
  if ($longids =~ m/CUL_TCM97001_ShortIDs/) {	# Enable short ID support
    $enableLongIDs = FALSE;
  }
  
  my $hasUnknownDevice;
  my $defUnknown = $modules{CUL_TCM97001}{defptr}{"CUL_TCM97001_Unknown"};
  my $nameUnknown;
  if ($defUnknown) {
    $hasUnknownDevice = TRUE;
    $nameUnknown = $defUnknown->{NAME};
  }
  else {
    $hasUnknownDevice = FALSE;
    $nameUnknown = "Unknown";
  }

  my $id3 = hex($a[0] . $a[1]);
  #my $id4 = hex($a[0] . $a[1] . $a[2] . (hex($a[3]) & 0x3));

  my $def = $modules{CUL_TCM97001}{defptr}{$id3}; # test for already defined devices use old naming convention
  #my $def2 = $modules{CUL_TCM97001}{defptr}{$idType2};
  if(!$def) {
     $def = $modules{CUL_TCM97001}{defptr}{'CUL_TCM97001_'.$id3};  # use new naming convention
  }
  
  my $now = time();

  my $name = $nameUnknown;
  if($def) {
    $name = $def->{NAME};
  }

  #my $readedModel = AttrVal($name, "model", "Unknown");	# wird nicht verwendet
  my $readedModel;
  
  my $syncTimeIndex = rindex($msg,";");
  my @syncBit;
  if ($syncTimeIndex != -1) {
    my $syncTimeMsg = substr($msg, $syncTimeIndex + 1);
    @syncBit = split(":", $syncTimeMsg);
    $msg = substr($msg, 0, $syncTimeIndex);
  } else {
    $syncBit[0] = 0;
    $syncBit[1] = 4000;
  }
  
  my $rssi;
  my $l = length($msg);
  $rssi = substr($msg, $l-2, 2);
  undef($rssi) if ($rssi eq "00");
  
  if (defined($rssi))
  {
	$rssi = hex($rssi);
    $rssi = ($rssi>=128 ? (($rssi-256)/2-74) : ($rssi/2-74)) if defined($rssi);
    Log3 $hash, 4, "$iodev: CUL_TCM97001 $name $id3 ($msg) length: $l RSSI: $rssi";
  } else {
    Log3 $hash, 4, "$iodev: CUL_TCM97001 $name $id3 ($msg) length: $l"; 
  }

  my $packageOK = FALSE;
  
  my $deviceCode;
  my $batbit=undef;
  my $mode=undef;
  my $trend=undef;
  my $hashumidity = FALSE;
  my $hasbatcheck = FALSE;
  my $hastrend = FALSE;
  my $haschannel = FALSE;
  my $hasmode = FALSE;
  my $model="Unknown";
  my $temp = undef;
  my $humidity=undef;  
  my $channel = undef;
  # fuer zusaetzliche Sensoren
  #my @winddir_name=("N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW");
  my @winddir_name=("N","NE","E","SE","S","SW","W","NW","N");  #W132 Only these values were seen:0 (N), 45 (NE), 90 (E), 135 (SE), 180 (S), 225 (SW), 270 (W), 315 (NW).
  my $windSpeed = 0;
  my $windDirection = 0;
  my $windDirectionDegree = 0;
  my $windDirectionText = "N";
  my $windgrad = 0  ;
  my $windGuest = 0;
  my $rain = 0;
  my $haswindspeed = FALSE;
  my $haswind = FALSE;
  my $hasrain = FALSE;
  my $rainticks = undef;
  my $rainMM = undef;
  
  if (length($msg) == 12 && AttrVal($name, "model", "Unknown") eq "Auriol_Z31743B") {	# es kann beim Modell Auriol_Z31743B ab und zu vorkommen, dass die msg zu lang ist
    Log3 $name, 4, "$iodev: CUL_TCM97001 $name model: Auriol_Z31743B, msg:$msg too long!";
    $msg = substr($msg,0,10);
  }
  
  if (length($msg) == 8) {
    # Only tmp TCM device
    #eg. 1000 1111 0100 0011 0110 1000 = 21.8C
    #eg. --> shift2  0100 0011 0110 10
    my $tcm97id = hex($a[0] . $a[1]);
    $def = $modules{CUL_TCM97001}{defptr}{$tcm97id};
    if($def) {
      $name = $def->{NAME};
    }
    $readedModel = AttrVal($name, "model", "Unknown");
    
    if ($readedModel eq "Unknown" || $readedModel eq "ABS700") {

      $temp = (hex($a[2].$a[3]) & 0x7F)+(hex($a[5])/10);
      if ((hex($a[2]) & 0x8) == 0x8) {
        $temp = -$temp;
      }
      
		# Sanity check temperature
		if($def) {
			my $timeSinceLastUpdate = ReadingsAge($name, "state", 0);
			if ($timeSinceLastUpdate < 0) {
				$timeSinceLastUpdate *= -1;
				}
				if (defined($hash->{READINGS}{temperature}{VAL})) {
				my $diffTemp = 0;
				my $oldTemp = $hash->{READINGS}{temperature}{VAL};
				my $maxdeviation = AttrVal($name, "max-deviation-temp", 1);				# default 1 K
				if ($temp > $oldTemp) {
				$diffTemp = ($temp - $oldTemp);
				} else {
				$diffTemp = ($oldTemp - $temp);
				}
				$diffTemp = sprintf("%.1f", $diffTemp);				
				Log3 $name, 4, "$iodev: $name old temp $oldTemp, age $timeSinceLastUpdate, new temp $temp, diff temp $diffTemp";
				my $maxDiffTemp = $timeSinceLastUpdate / 60 + $maxdeviation; 			# maxdeviation + 1.0 Kelvin/Minute
				$maxDiffTemp = sprintf("%.1f", $maxDiffTemp + 0.05);					# round 0.1
				Log3 $name, 4, "$iodev:  $name max difference temperature $maxDiffTemp K";
				if ($diffTemp > $maxDiffTemp) {
				Log3 $name, 3, "$iodev:  $name ERROR - Temp diff too large (old $oldTemp, new $temp, diff $diffTemp)";
				return "";
				}
			}
		}
      if (checkValues($hash,"ABS700",$temp)) {
        $model="ABS700";
        $batbit = ((hex($a[4]) & 0x8) != 0x8);
        $mode = (hex($a[4]) & 0x4) >> 2;
      
        if (!defined($modules{CUL_TCM97001}{defptr}{$tcm97id}))
        {
            if ( $enableLongIDs == TRUE || (($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
          	{
		         $deviceCode="CUL_TCM97001_".$tcm97id;
		         Log3 $hash,4, "$iodev: CUL_TCM97001 using longid: $longids model: $model";
           	} else {
		         $deviceCode="$iodev: CUL_TCM97001_" . $model;
           	}
        } else {
        	$deviceCode=$tcm97id;
        }  
      	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
      	if($def) {
       	  $name = $def->{NAME};
        }
        else {
          goto UNDEFINED_MODEL;
        }
        $hasbatcheck = TRUE;
        $packageOK = TRUE;
        $hasmode = TRUE;
        
        $readedModel=$model;
      }
    }
    
	if ($readedModel eq "Unknown" || $readedModel eq "TCM97...") {

      $temp    = (hex($a[3].$a[4].$a[5]) >> 2) & 0xFFFF;  
      my $negative    = (hex($a[2]) >> 0) & 0x3; 

      if ($negative == 0x3) {
        $temp = (~$temp & 0x03FF) + 1;
        $temp = -$temp;
      }

      $temp = $temp / 10;

      if (checkValues($hash,"TCM97...",$temp)) {
      	$model="TCM97...";
         # I think bit 3 on byte 3 is battery warning
      	$batbit    = (hex($a[2]) >> 0) & 0x4; 
      	$batbit = ~$batbit & 0x1; # Bat bit umdrehen
      	$mode    = (hex($a[5]) >> 0) & 0x1; 
      	my $unknown    = (hex($a[4]) >> 0) & 0x2; 
	    if ($mode) {
    	  Log3 $name, 5, "$iodev: CUL_TCM97001 Mode: manual triggert";
      	} else {
       	  Log3 $name, 5, "$iodev: CUL_TCM97001 Mode: auto triggert";
      	}
     	if ($unknown) {
          Log3 $name, 5, "$iodev: CUL_TCM97001 Unknown Bit: $unknown";
      	}
        
        if (!defined($modules{CUL_TCM97001}{defptr}{$tcm97id}))
        {
            if ( $enableLongIDs == TRUE || (($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
          	{
		         $deviceCode="CUL_TCM97001_".$tcm97id;
		         Log3 $hash,4, "$iodev: CUL_TCM97001 using longid: $longids model: $model";
           	} else {
		         $deviceCode="$iodev: CUL_TCM97001_" . $model;
           	}
        } else {
        	$deviceCode=$tcm97id;
        }  
      	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
      	if($def) {
       	  $name = $def->{NAME};
        }
        else {
          goto UNDEFINED_MODEL;
        }
        $packageOK = TRUE;
        $hasbatcheck = TRUE;
        $hasmode = TRUE;
        $readedModel=$model;
      }
    }	
  } elsif (length($msg) == 10) {
  	my $idType2 = hex($a[1] . $a[2]);
    $deviceCode = $idType2;
    $def = $modules{CUL_TCM97001}{defptr}{$deviceCode};   # test for already defined devices use old naming convention
    if(!$def) {
       $deviceCode = "CUL_TCM97001_" . $idType2;          # use new naming convention
       $def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
    } 
    if($def) {
      $name = $def->{NAME};
    }
    
    $readedModel = AttrVal($name, "model", "Unknown");
    
    if (checkCRC_Mebus($msg) == TRUE && ($readedModel eq "Unknown" || $readedModel eq "Mebus")) {
        # Protocol mebus start everytime with 1001
        # Sync bit 9700ms, bit 0 = 350ms, bit 1 = 2000ms
        # e.g. 8250ED70	    1000  0010  0101  0000  1110  1101  0111
        #                   A     B     C     D     E     F     G    
        # A = CRC ((B+C+D+E+F+G)-1)
        # B+C = Random Address
        # D+E+F temp (/10) 
        # G  Bit 4,3 = Channel, Bit 2 = Battery, Bit 1 = Force sending
        $temp    = (hex($a[3].$a[4].$a[5])) & 0x3FF;  
        my $negative    = (hex($a[3])) & 0xC; 

        if ($negative == 0xC) {
          $temp = (~$temp & 0x03FF) + 1;
          $temp = -$temp;
        }
        $temp = $temp / 10;

        

        if (checkValues($hash,"Mebus",$temp)) {
            $batbit = (hex($a[6]) & 0x2) >> 1;
            #$batbit = ~$batbit & 0x1; # Bat bit umdrehen
            $mode   = (hex($a[6]) & 0x1);
            $channel = (hex($a[6]) & 0xC) >> 2;
            $model="Mebus";
     
         	if (!defined($modules{CUL_TCM97001}{defptr}{$idType2}))
         	{	
	          	if ( $enableLongIDs == TRUE || (($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
	          	{
			         $deviceCode="CUL_TCM97001_".$idType2;
			         Log3 $hash,4, "$iodev: CUL_TCM97001 using longid: $longids model: $model";
	           	} else {
			         $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
	           	}
         	}  else  {  # Fallback for already defined devices use old naming convention
         		$deviceCode=$idType2;
         	}     
          
          	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
          	if($def) {
              $name = $def->{NAME};
            }
            else {
              goto UNDEFINED_MODEL;
            }
            $packageOK = TRUE;
            
            $readedModel=$model;
            $hasmode = TRUE;
            $hasbatcheck = TRUE;
            $haschannel = TRUE;
            $id3 = $idType2;
        } else {
            $name = $nameUnknown;
        }
    }

	if ($packageOK == FALSE) {
		my $idType1 = hex($a[0] . $a[1]);
		$deviceCode = $idType1;
		$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};   # test for already defined devices use old naming convention 
		#my $def2 = $modules{CUL_TCM97001}{defptr}{$idType2};
		#my $def3 = $modules{CUL_TCM97001}{defptr}{$idType3};
		if(!$def) {
		   $deviceCode = "CUL_TCM97001_" . $idType1;          # use new naming convention
		   $def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
		}
		if($def) {
		   $name = $def->{NAME};
		#} elsif($def2) {
		#  $def = $def2;
		#  $name = $def->{NAME};
		#} elsif($def3) {
		#  $def = $def3;
		#  $name = $def->{NAME};
		}
		$readedModel = AttrVal($name, "model", "Unknown");
		
	if ($readedModel eq "AURIOL" || $readedModel eq "Auriol_Z31743B" || $readedModel eq "Unknown") {
		  # Implementation from Femduino
		  # AURIOL (Lidl Version: 09/2013)
		  #                /--------------------------------- Channel, changes after every battery change      
		  #               /           / ------------------------ Battery state 1 == Ok      
		  #              /           / /------------------------ Battery changed, Sync startet      
		  #             /           / /  ----------------------- Unknown      
		  #            /           / / /    /--------------------- neg Temp: if 1 then temp = temp - 4096
		  #           /           / / /    /---------------------- 12 Bit Temperature
		  #          /           / / /    /               /---------- ??? CRC 
		  #         /           / / /    /               /       /---- Trend 10 == rising, 01 == falling
		  #         0101 0101  1 0 00   0001 0000 1011  1100  01 00
		  # Bit     0          8 9 10   12              24       30
		  
		  my $check_Z31743B = TRUE;
		  if ($readedModel eq "Auriol_Z31743B") {
		    my $xbin = "";
		    my $checksum = 0;
		    foreach my $x (split('', $msg)) {
		      $xbin .= sprintf("%04b",hex($x));
		    }
		    for (my $x = 0; $x < 31; $x++) {
		      $checksum ^= substr($xbin, $x, 1);
		    }
		    if ($checksum ne substr($xbin, 31,1)) {
		      Log3 $name, 3, "$iodev: CUL_TCM97001 $name: ERROR Model: Auriol_Z31743B msg: $msg, checksum (parity) not ok, calc $checksum, ref " . substr($xbin, 31, 1);
		      $check_Z31743B = FALSE;
		    }
		    if ($check_Z31743B && (hex($a[2]) & 7) != 0) {	# Bit 0 - 2 muessen 0 sein
		      Log3 $name, 3, "$iodev: CUL_TCM97001 $name: ERROR Model: Auriol_Z31743B msg: $msg, 3.digit must be 0 or 8";
		      $check_Z31743B = FALSE;
		    }
		  }
		  
		  $def = $modules{CUL_TCM97001}{defptr}{$idType1};
		  if($def) {
			$name = $def->{NAME};
		  } 
		  $temp    = (hex($a[3].$a[4].$a[5])) & 0x7FF;  
		  my $negative    = (hex($a[3])) & 0x8; 
		  if ($negative == 0x8) {
			$temp = (~$temp & 0x07FF) + 1;
			$temp = -$temp;
		  }
		  $temp = $temp / 10;
		
		  if (checkValues($hash,"AURIOL",$temp) && $check_Z31743B) {
			$batbit = (hex($a[2]) & 0x8) >> 3;
			#$batbit = ~$batbit & 0x1; # Bat bit umdrehen
			$mode   = (hex($a[2]) & 0x4) >> 2;
			$channel = 0;
			$trend = (hex($a[7]) & 0x3);
			if ($readedModel eq "Unknown") {
			  $model="AURIOL";
			} else {
			  $model=$readedModel;
			}
			
			if ($deviceCode ne $idType1)  # new naming convention
			{	
				if ( $enableLongIDs == TRUE || (($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
				{
					 $deviceCode="CUL_TCM97001_".$idType1;
				} else {
					 $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
				}
			}
		  
			$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
			if($def) {
			 $name = $def->{NAME};
			}
			else {
			  goto UNDEFINED_MODEL;
			}

			$hasbatcheck = TRUE;
			if ($model eq "AURIOL") {
			  $hastrend = TRUE;
			  $hasmode = TRUE;
			}
			$packageOK = TRUE;
			
			$readedModel=$model;
		  } else {
			  $name = $nameUnknown;
		  }
		}
	}
    
  } elsif (length($msg) == 12) { 
    my $bin = undef;
    my $hlen = length($msg);
    my $blen = $hlen * 4;
    my $bitData = unpack("B$blen", pack("H$hlen", $msg));
    my $idType1 = hex($a[0] . $a[1]);
    #my $idType2 = hex($a[1] . $a[2]);
    #my $idType3 = hex($a[0] . $a[1] . $a[2] . (hex($a[3]) & 0x3));

    $deviceCode = $idType1;
    $def = $modules{CUL_TCM97001}{defptr}{$deviceCode};   # test for already defined devices use old naming convention 
    #my $def2 = $modules{CUL_TCM97001}{defptr}{$idType2};
    #my $def3 = $modules{CUL_TCM97001}{defptr}{$idType3};
    
    if(!$def) {
       my $a0 = hex($a[0]);
       if ($a0 == 5 || $a0 == 9) {	# Prologue oder NC_WS
          $deviceCode = "CUL_TCM97001_" . $a0 . "_" . hex($a[1] . $a[2]);
          $def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
          if(!$def) {
            $deviceCode = "CUL_TCM97001_" . $idType1;          # use new naming convention
            $def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
          }
       } else {
         $deviceCode = "CUL_TCM97001_" . $idType1;          # use new naming convention
         $def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
       }
    }
    if($def) {
       $name = $def->{NAME};
    #} elsif($def2) {
    #  $def = $def2;
    #  $name = $def->{NAME};
    #} elsif($def3) {
    #  $def = $def3;
    #  $name = $def->{NAME};
    }
    $readedModel = AttrVal($name, "model", "Unknown");
    Log3 $iodev, 4, "$iodev: CUL_TCM97001 Parse Name: $name , devicecode: $deviceCode , Model defined: $readedModel";
    
    if (($readedModel eq "Eurochron" || (hex($a[6]) == 0xF && $readedModel eq "Unknown" && $hash->{TYPE} !~ m/^SIGNALduino/) && $syncBit[1] < 5000)) {
      # EAS 800 
      # G is every time 1111
      #
      # 0100 1110 1001 0000 1010 0001 1111 0100 1001 
      # A    B    C    D    E    F    G    H    I
      #  
      # A+B = ID = 4E
      # C Bit 0 = Bat (1) OK
      # C Bit 1-3 = Channel 001 = 1
      # D-F = Temp (0000 1010 0001) = 161 ~ 16,1°
      # G = Unknown
      # H+I = hum (0100 1001) = 73
      $def = $modules{CUL_TCM97001}{defptr}{$idType1};
      if($def) {
        $name = $def->{NAME};
      } else {
        # Redirect to
        my $SD_WS07_ClientMatch=index($hash->{Clients},"SD_WS07");
		if ($SD_WS07_ClientMatch == -1) {
		    # Append Clients and MatchList for CUL
		    $hash->{Clients} = $hash->{Clients}.":SD_WS07:";
		    $hash->{MatchList}{"C:SD_WS07"} = "^P7#[A-Fa-f0-9]{6}F[A-Fa-f0-9]{2}";
		}
		my $dmsg = "P7#" . substr($msg, 0, $l-2, 2);
		$hash->{RAWMSG} = $msg;
		my %addvals = (RAWMSG => $msg, DMSG => $dmsg);
		Log3 $name, 5, "$iodev: CUL_TCM97001 Dispatch $dmsg to other modul";
		Dispatch($hash, $dmsg, \%addvals);  ## Dispatch to other Modules 
		return "";
      }
      $temp    = (hex($a[3].$a[4].$a[5])) & 0x7FF;
      my $negative    = (hex($a[3])) & 0x8; 
      if ($negative == 0x8) {
        $temp = (~$temp & 0x07FF) + 1;
        $temp = -$temp;
      }
      $temp = $temp / 10;

      

      $humidity = hex($a[7].$a[8]) & 0x7F;

      if (checkValues($hash,"Eurochron",$temp, $humidity)) {
        $batbit = (hex($a[2]) & 0x8) >> 3;
        #$batbit = ~$batbit & 0x1; # Bat bit umdrehen
        $mode   = (hex($a[2]) & 0x4) >> 2;
        $channel = ((hex($a[2])) & 0x3) + 1;
        $model="Eurochron";
        
        if ($deviceCode ne $idType1)  # new naming convention
     	{	
     	    if ( $enableLongIDs == TRUE || (($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
          	{
		         Log3 $hash,4, "$iodev: CUL_TCM97001 using longid: $longids model: $model";
           	} else {
		         $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
           	}
     	}     
      
      	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
        if($def) {
          $name = $def->{NAME};
        }
        else {
          goto UNDEFINED_MODEL;
        }
        if (defined($humidity)) {
          if ($humidity >= 20) {
            $hashumidity = TRUE;
          }  
        }  
        $hasbatcheck = TRUE;
        $haschannel = TRUE;
        $packageOK = TRUE;
        $hasmode = TRUE;
        
        $readedModel=$model;
        } else {
          $name = $nameUnknown;
        }
    }

		### inserted by elektron-bbs for rain gauge Ventus W174
		if (checksum_W174($hash, $msg) == TRUE && ($readedModel eq "Unknown" || $readedModel eq "W174")) {
   	   # VENTUS W174 Rain gauge
   	   # Documentation also at http://www.tfd.hu/tfdhu/files/wsprotocol/auriol_protocol_v20.pdf
			# send interval 36 seconds
   	   # * Format for Rain
   	   # *   AAAAAAAA vXXB CCCC DDDD DDDD DDDD DDDD EEEE FFFF FFFF 
   	   # *   RC            Type Rain                Checksum
   	   # *   A = Rolling Code /Device ID
   	   # *   B = Message type (xyyx = NON temp/humidity data if yy = '11')
   	   # *   v = 0: Sensor's battery voltage is normal, 1: Battery voltage is below ~2.6 V.
   	   # *  XX = 11: Non temperature/humidity data. All other type data packets have this value in this field.
   	   # *   C = fixed to 1100 for rain gauge
   	   # *   D = Rain (bitvalue * 0.25 mm)
   	   # *   E = Checksum
   	   # *   F = 0000 0000 (W174!!!)
         my @a = split("", $msg);
         my $bitReverse = "";
         my $bitUnreverse = "";
         my $x = undef;
         my $bin3;
         foreach $x (@a) {
            $bin3=sprintf("%024b",hex($x));
            $bitReverse = $bitReverse . substr(reverse($bin3),0,4); 
            $bitUnreverse = $bitUnreverse . sprintf( "%b", hex( substr($bin3,0,4) ) );
         }
         my $hexReverse = unpack("H*", pack ("B*", $bitReverse));
         my @aReverse = split("", $hexReverse);							# Split reversed a again
         Log3 $hash,5, "$iodev: CUL_TCM97001 $name original-msg: $msg , reversed nibbles: $hexReverse";
         Log3 $hash,5, "$iodev: CUL_TCM97001 $name nibble 2: $aReverse[2] , nibble 3: $aReverse[3]";
         # Nibble 2 must be x110 for rain gauge 
         # Nibble 3 must be 0x03 for rain gauge
         if ((hex($aReverse[2]) >> 1) == 3 && hex($aReverse[3]) == 0x03) {
            Log3 $hash,4, "$iodev: CUL_TCM97001 $name detected rain gauge message ok";
            $batbit = $aReverse[2] & 0b0001;									# Bat bit normal=0, low=1
            Log3 $hash,4, "$iodev: CUL_TCM97001 $name battery bit: $batbit";
            $batbit = ~$batbit & 0x1; 												# Bat bit negation
            $hasbatcheck = TRUE;
            my $rainticks = hex($aReverse[4]) + hex($aReverse[5]) * 16 + hex($aReverse[6]) * 256 + hex($aReverse[7]) * 4096;
            Log3 $hash,5, "$iodev: CUL_TCM97001 $name rain gauge swing count: $rainticks";
             #$rain = ($rainticks + ($rainticks & 1)) / 4;			# 1 tick = 0,5 l/qm
            # pejonp  3.2.2018  0,25mm Schritte nicht 0,5
            $rain = $rainticks * 0.25;
            $model="W174";
            $hasrain = TRUE;
            # Sanity check 
            if($def) {
			   $def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
			   $name = $def->{NAME};
			   return "" if (checkRain($def, $iodev, $rain) == FALSE);
           }
           else {
               goto UNDEFINED_MODEL;
           }
            Log3 $iodev,4, "$iodev: CUL_TCM97001 $name rain total: $rain l/qm";
            $readedModel=$model;
				$packageOK = TRUE;
			}
		}
    
### inserted by pejonp 3.2.2018 Ventus W132/W044
   if (checksum_W155($hash, $msg) == TRUE && ($readedModel eq "Unknown" || $readedModel eq "TCM21...." || $readedModel eq "W044" || $readedModel eq "W132")) {
        # Long with tmp
        # All nibbles must be reversed  
        # e.g. 154E800480	   0001	0101 0100 1110 1000	0000 0000 0100 1000	0000
        #                      A    B    C    D    E    F    G    H    I
        # A+B = Addess
        # C Bit 1 Battery
        # D+E+F Temp 
        # G+H Hum
        # I CRC
        #/* Documentation also at http://www.tfd.hu/tfdhu/files/wsprotocol/auriol_protocol_v20.pdf
        # * Message Format: (9 nibbles, 36 bits):
        # * Please note that bytes need to be reversed before processing!
        # *
        # * Format for Temperature Humidity
        # *   AAAAAAAA BBBB CCCC CCCC CCCC DDDDDDDD EEEE
        # *   RC       Type Temperature___ Humidity Checksum
        # *   A = Rolling Code / Device ID
        # *       Device ID: AAAABBAA BB is used for channel, base channel is 01
        # *       When channel selector is used, channel can be 10 (2) and 11 (3)
        # *   B = Message type (xyyz = temp/humidity if yy <> '11') else wind/rain sensor
        # *       x indicates battery status (0 normal, 1 voltage is below ~2.6 V)
        # *       z 0 indicates regular transmission, 1 indicates requested by pushbutton
        # *   C = Temperature (two's complement)
        # *   D = Humidity BCD format
        # *   E = Checksum

        my @a = split("", $msg);
        my $bitReverse = "";
        my $bitUnreverse = "";
        my $x = undef;
        my $bin3;
        #my $hlen = length($msg);
        #my $blen = $hlen * 4;
        #my $bitData = unpack("B$blen", pack("H$hlen", $msg));
        
        foreach $x (@a) {
           $bin3=sprintf("%024b",hex($x));
           $bitReverse = $bitReverse . substr(reverse($bin3),0,4);
           $bitUnreverse = $bitUnreverse . sprintf( "%b", hex( substr($bin3,0,4) ) );
        }
        my $hexReverse = uc(unpack("H*", pack ("B*", $bitReverse)));
        my @aReverse = split("", $hexReverse);
        my @amsg = split("", $msg);
        my $msgt = substr($bitData,9,2);
        Log3 $hash,5, "$iodev: CUL_TCM97001_01:     msg:$msg typ:$msgt";
        Log3 $hash,5, "$iodev: CUL_TCM97001_01:      aR:$hexReverse";
        Log3 $hash,5, "$iodev: CUL_TCM97001_01: bitData:$bitData ";
        $channel = oct("0b".substr( $bitData,4,2));
        $haschannel = TRUE;
        $batbit =  substr($bitData,8,1);
        $batbit = $batbit ? 0 : 1; # Bat bit umdrehen
        $hasbatcheck = TRUE;  
        # Temp/Hum 
        if ( $msgt ne "11") {
            $mode =  substr($bitData,11,1);
            $hasmode = TRUE;
            if (hex($aReverse[5]) > 3) {
               # negative temp
                $temp = ((hex($aReverse[3]) + hex($aReverse[4]) * 16 + hex($aReverse[5]) * 256));
                $temp = (~$temp & 0x03FF) + 1;
                $temp = -$temp/10;
             } else {
                # positive temp
                $temp = (hex($aReverse[3]) + hex($aReverse[4]) * 16 + hex($aReverse[5]) * 256)/10;
             }
             $humidity = hex($aReverse[7]).hex($aReverse[6]);
             $hashumidity = TRUE;
             if ($readedModel eq "Unknown") {
                $model="W044";
             } else {
                $model=$readedModel;
             }
                Log3 $hash,4, "$iodev: CUL_TCM97001_02: $model CH:$channel Bat:$batbit Mode:$mode T:$temp H:$humidity ";
                $packageOK = TRUE;
        } else {
          # Wind/Rain/Guest
          #   C = Fixed to 1000 0000 0000  Reverse 0001 0000 0000
          # * Format for Windspeed
          # *   AAAAAAAA BBBB CCCC CCCC CCCC DDDDDDDD EEEE
          # *   RC       Type                Windspd  Checksum
          # *   A = Rolling Code
          # *   B = Message type (xyyx = NON temp/humidity data if yy = '11')
          # *   C = Fixed to 1000 0000 0000   (8)
          # *   D = Windspeed  (bitvalue * 0.2 m/s, correction for webapp = 3600/1000 * 0.2 * 100 = 72)
          # *   E = Checksum
          if ((hex($a[3])== 0x8) && (hex($a[4])== 0x0)&& (hex($a[5])== 0x0)) { # Windspeed
              $windSpeed = (hex($aReverse[6]) + hex($aReverse[7]) * 16) * 0.2;
              $haswindspeed = TRUE;
              $model="W132";
              Log3 $hash,4, "$iodev: CUL_TCM97001_03:  $model  windSpeed: $windSpeed aR: $aReverse[6] $aReverse[7]";
          }
          # * Format for Winddirection & Windgust
          # *   AAAAAAAA BBBB CCCD DDDD DDDD EEEEEEEE FFFF
          # *   RC       Type      Winddir   Windgust Checksum
          # *   A = Rolling Code
          # *   B = Message type (xyyx = NON temp/humidity data if yy = '11')
          # *   C = Fixed to 111  (E)
          # *   D = Wind direction
          # *   E = Windgust (bitvalue * 0.2 m/s, correction for webapp = 3600/1000 * 0.2 * 100 = 72)
          # *   F = Checksum 
            if ((hex($amsg[3])== 0xE)|| (hex($amsg[3])== 0xF)) { # Windguest
              $windGuest = (hex($aReverse[6]) + hex($aReverse[7]) * 16) * 0.2;
              $windDirectionDegree = (hex($a[3]) & 0x1)+ ((hex($aReverse[4])*2) + (hex($aReverse[5]))*32);
              if (AttrVal($name, "windDirectionInverse", 0)) {
                 $windDirectionDegree = 360 - $windDirectionDegree;
              }
              $windDirection = int($windDirectionDegree/45); 
              $windDirectionText = $winddir_name[$windDirection];
              $haswind = TRUE;
              $model="W132";
              Log3 $hash,4, "$iodev: CUL_TCM97001_04: $model windGuest: $windGuest aR: $aReverse[6] $aReverse[7] winddirDegree:$windDirectionDegree winddir:$windDirection:$windDirectionText";
            }
          # * Format for Rain
          # *   AAAAAAAA BBBB CCCC DDDD DDDD DDDD DDDD EEEE
          # *   RC       Type      Rain                Checksum
          # *   A = Rolling Code /Device ID
          # *   B = Message type (xyyx = NON temp/humidity data if yy = '11')
          # *   C = fixed to 1100   (C)
          # *   D = Rain (bitvalue * 0.25 mm)
          # *   E = Checksum          
          if ((hex($amsg[3])== 0xC)) { # Rain
              $rain = (hex($amsg[4]) + hex($amsg[5]) + hex($amsg[6]) + hex($amsg[7])) * 0.25;
              $hasrain = TRUE;
              $model="W174";
              Log3 $hash,4, "$iodev: CUL_TCM97001_05: $model rain: $rain ";
          }
        }
    if ( checkValues($hash,"W044|TCM21....",$temp, $humidity) || $haswindspeed ||$haswind || $hasrain || $haschannel || $hasbatcheck ) {
     	if (!defined($modules{CUL_TCM97001}{defptr}{$idType1}))
     	{	
          if ( $enableLongIDs == TRUE || (($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
          	{
	             $deviceCode="CUL_TCM97001_".$idType1;
	             Log3 $hash,4, "$iodev: CUL_TCM97001_06: model: $model  $deviceCode";
           	} else {
	             $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
                Log3 $hash,4, "$iodev: CUL_TCM97001_07: model: $model  $deviceCode";
           	}
     	}  else  {  # Fallback for already defined devices use old naming convention
     		$deviceCode=$idType1;
     	}     
      	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
      	if($def) {
       	 $name = $def->{NAME};
        }
        else {
          goto UNDEFINED_MODEL;
        }
      $hasbatcheck = TRUE;
      $packageOK = TRUE;
      $readedModel=$model;
      Log3 $hash,5, "$iodev: CUL_TCM97001_09:  model:$model Rmodel:$readedModel Mode:$hasmode P:$packageOK  ";
      Log3 $hash,5, "$iodev: CUL_TCM97001_10:  Channel:$channel B:$hasbatcheck BAT:$batbit W:$haswindspeed Wind: $windDirection ";
      } else {
          $name = $nameUnknown;
       }
    }

    if (checkCRC_GTWT02($msg) == TRUE && ($readedModel eq "GT_WT_02" || $readedModel eq "Type1" || $readedModel eq "Unknown")
        || checkCRC_Type1($msg) == TRUE && ($readedModel eq "Type1" || $readedModel eq "GT_WT_02" || $readedModel eq "Unknown")) {

		### edited by elektron-bbs for Checksum
		#http://www.ludwich.de/ludwich/Temperatur.html
		#https://github.com/merbanan/rtl_433/issues/117
		#    F    F    0    0    F    9    5    5    F   
        # 1111 1111 0000 0000 1111 1001 0101 0101 1111 
        #    A    B    C    D    E    F    G    H    I 
        # A+B = Zufaellige Code wechelt beim Batteriewechsel
        # C Bit 4 Battery, 3 Manual, 2+1 Channel
        # D+E+F Temperatur, wenn es negativ wird muss man negieren und dann 1 addieren, wie im ersten Post beschrieben.
        # G+H Hum - bit 0-7 
        # I CRC
      #$def = $modules{CUL_TCM97001}{defptr}{$idType3};
		
      $temp    = (hex($a[3].$a[4].$a[5])) & 0x3FF;  
      my $negative    = (hex($a[3])) & 0xC; 
      if ($negative == 0xC) {
        $temp = (~$temp & 0x03FF) + 1;
        $temp = -$temp;
      }
      $temp = $temp / 10;
      $humidity = (hex($a[6].$a[7]) & 0x0FE) >> 1; # only the first 7 bits are the humidity

      if ($humidity > 100) {
        # HH - Workaround
        $humidity = 100;
      } elsif ($humidity < 20) {
        # LL - Workaround
        $humidity = 20;
      }

      if (checkValues($hash,"GT_WT_02|Type1",$temp,$humidity)) {
        $channel = ((hex($a[2])) & 0x3) + 1;
        $batbit  = ((hex($a[2]) & 0x8) != 0x8);
        $mode    = (hex($a[2]) & 0x4) >> 2;
        if (checkCRC_GTWT02($msg) == TRUE) {
            $model="GT_WT_02";
        } else {
            $model="Type1";
        }
      
        if ($deviceCode ne $idType1)  # new naming convention
     	{	
	      	if ( $enableLongIDs == TRUE || (($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
          	{
	             Log3 $hash,4, "$iodev: CUL_TCM97001 using longid: $longids model: $model";
           	} else {
	             $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
           	}
     	}     
      
      	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
        if($def) {
          $name = $def->{NAME};
         }
        else {
          goto UNDEFINED_MODEL;
        }
        $hashumidity = TRUE;
        $hasbatcheck = TRUE;  
        $haschannel = TRUE;   
        $hasmode = TRUE;  
        $packageOK = TRUE;
        
        $readedModel=$model;
      } else {
          $name = $nameUnknown;
      }
    }
    
    #if (checkCRC_sduinoID33($hash,$bitData) == TRUE && ($readedModel eq "Unknown" || $readedModel eq "NX7674")) {
       # https://forum.fhem.de/index.php?topic=135692.0
       # Rosenstein & Soehne, Kuehl- & Gefrierschrank-Thermometer
       #
       # 0    4    | 8    12   | 16   20   | 24   28   | 32   36   | 40
       # 00Ii iiii | ii00 cctt | tttt tttt | tt00 0000 | 000b TTxx | xx00
       # I: 0 - sensor 2, 1 - sensor 1
       # i: random id (changes on power-loss)
       # c: Channel
       # t: Temperature
       # b: battery indicator (0=>OK, 1=>LOW)
       # T: Temperature trend
       # x: crc4
       #
       # $temp = (oct("0b". substr($bitData,22,4) . substr($bitData,18,4) . substr($bitData,14,4)) - 1220) * 5 / 90.0;
       # $batbit = substr($bitData,35,1) eq "0" ? 1 : 0; 
       # $channel = substr($bitData,2,1) eq "0" ? 2 : 1;
       # $trend = oct("0b".substr($bitData,36,2));
       # if ($trend == 1 || $trend == 2) { # falling und rising tauschen
       #   $trend ^= 3;
       # }
       # $model = "NX7674";
       #
       #   if ( $enableLongIDs == TRUE || (($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
       #   {
       #     Log3 $hash,4, "$iodev: CUL_TCM97001 using longid: $longids model: $model";
       #   } else {
       #     $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
       #   }
       # $def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
       #  if($def) {
       #    $name = $def->{NAME};
       #  } else {
       #    goto UNDEFINED_MODEL;
       #  }
       #  
       # $hasbatcheck = TRUE;
       # $haschannel = TRUE;
       # $hastrend = TRUE;
       # $packageOK = TRUE;
       #
       # $readedModel=$model;
    # }
    
      #Log3 $name, 4, "CUL_TCM97001: CRC for TCM21.... Failed, checking other protocolls";
      # Check for Prologue
    if ($readedModel eq "Prologue" || (hex($a[0]) == 0x9 && $readedModel eq "Unknown")) {
        # Protocol prologue start everytime with 1001
        # e.g. 91080F614C	   1001 0001 0000 1000 0000 1111 0110 0001 0100 1100
        #                      A    B    C    D    E    F    G    H    I
        # A = Startbit 1001
        # B+C = Random Address
        # D Bit 4 Battery, 3 Manual, 2+1 Channel 
        # E+F+G Bit 15+16 negativ temp, 14-0 temp
        # H+I Hum
        #$def = $modules{CUL_TCM97001}{defptr}{$idType3};
        #$def = $modules{CUL_TCM97001}{defptr}{$idType1};
        
        $temp    = (hex($a[4].$a[5].$a[6])) & 0x3FFF;  
        my $negative    = (hex($a[4])) & 0xC; 

        if ($negative == 0xC) {
          $temp = (~$temp & 0x03FF) + 1;
          $temp = -$temp;
        }
        $temp = $temp / 10;

        if (!(hex($a[7]) == 0xC && hex($a[8]) == 0xC)) {
          $humidity = hex($a[7].$a[8]);
        }
        
        if (checkValues($hash, "Prologue", $temp, $humidity)) {
            $channel = ((hex($a[3])) & 0x3) + 1;
            $batbit = (hex($a[3]) & 0x8) >> 3;
            $batbit = ~$batbit & 0x1; # Bat bit umdrehen
            $mode = (hex($a[3]) & 0x4) >> 2;
            
            $model="Prologue";
            
            if ($deviceCode ne $idType1)  # new naming convention
            {
               if ( $enableLongIDs == TRUE || (($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
               {
                  Log3 $hash,4, "$iodev: CUL_TCM97001 using longid: $longids model: $model";
               } else {
                  $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
               }
            }
          
            $def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
            if($def) {
              $name = $def->{NAME};
            }
            else {
              goto UNDEFINED_MODEL;
            }
            if ($deviceCode =~ m/_9_/) {
                $def->{AlternativeDEFcode} = "CUL_TCM97001_$idType1";
            } elsif ($deviceCode eq "CUL_TCM97001_$idType1") {	# nur bei longid
                $def->{AlternativeDEFcode} = "CUL_TCM97001_9_" . hex($a[1] . $a[2]);
            }
            
            if (defined($humidity)) {
                if ($humidity >= 20) {
                  $hashumidity = TRUE;
                }
            }
            $hasbatcheck = TRUE;
            $hasmode = TRUE;
            $packageOK = TRUE;
            $haschannel = TRUE;
            
            $readedModel=$model;
        } else {
            $name = $nameUnknown;
        }
    } 
    
    if ($readedModel eq "NC_WS" || (hex($a[0]) == 0x5 && $readedModel eq "Unknown")) {
      # Implementation from Femduino
      # Protocol prologue start everytime with 0101
      # PEARL NC7159, LogiLink WS0002
      #                 /--------------------------------- Sensdortype      
      #                /     / ---------------------------- ID, changes after every battery change      
      #               /     /          /--------------------- Battery state 1 == Ok
      #              /     /          /  / ------------------ forced send      
      #             /     /          /  /  / ---------------- Channel (0..2)      
      #            /     /          /  /  /   / -------------- neg Temp: if 1 then temp = temp - 2048
      #           /     /          /  /  /   /   / ----------- Temp
      #          /     /          /  /  /   /   /             /-- unknown
      #         /     /          /  /  /   /   /             /  / Humidity
      #         0101  0010 1001  0 0 00   0 010 0011 0000   1 101 1101
      # Bit     0     4         12 13 14  16 17            28 29    36
      #$def = $modules{CUL_TCM97001}{defptr}{$idType3};

      $temp    = (hex($a[4].$a[5].$a[6])) & 0x7FFF;  
      my $negative    = (hex($a[4])) & 0x8; 

      if ($negative == 0x8) {
        $temp = (~$temp & 0x07FF) + 1;
        $temp = -$temp;
      }
      $temp = $temp / 10;
      
      $humidity = hex($a[7].$a[8]) & 0x7F;

      if (checkValues($hash, "NC_WS", $temp, $humidity)) {
     	$model="NC_WS";
     	$channel = ((hex($a[3])) & 0x3) + 1;
     	$batbit = (hex($a[3]) & 0x8) >> 3;
      	#$batbit = ~$batbit & 0x1; # Bat bit umdrehen
      	$mode = (hex($a[3]) & 0x4) >> 2;
     
       	if ($deviceCode ne $idType1)  # new naming convention     
     	{	
		  	if ( $enableLongIDs == TRUE || (($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
          	{
	             Log3 $hash,4, "$iodev: CUL_TCM97001 using longid: $longids model: $model";
           	} else {
	             $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
           	}
     	}     
      
      	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
      	if($def) {
       	 $name = $def->{NAME};
        }
        else {
          goto UNDEFINED_MODEL;
        }
        if ($deviceCode =~ m/_5_/) {
          $def->{AlternativeDEFcode} = "CUL_TCM97001_$idType1";
        } elsif ($deviceCode eq "CUL_TCM97001_$idType1") {	# nur bei longid
          $def->{AlternativeDEFcode} = "CUL_TCM97001_5_" . hex($a[1] . $a[2]);
        }
        $hashumidity = TRUE;
        $hasbatcheck = TRUE;
        $hasmode = TRUE;
        $packageOK = TRUE;
        $haschannel = TRUE; 
        $readedModel=$model; 
      } else {
          $name = $nameUnknown;
      }
    } 

    if ($readedModel eq "Rubicson" || (hex($a[2]) == 0x8 && $readedModel eq "Unknown")) {
      # Protocol Rubicson has as nibble C every time 1000
      # e.g. F4806B8E14	    1111 0100 1000 0000 0110 1011 1000 1110	0001 0100
      #                      A    B    C    D    E    F    G    H    I
      # A+B = Random Address
      # C = Rubicson = 1000
      # D+E+F 12 bit temp
      # G+H+I Unknown
      $def = $modules{CUL_TCM97001}{defptr}{$idType1};
      if($def) {
        $name = $def->{NAME};
      } 
      $temp    = (hex($a[3].$a[4].$a[5])) & 0x3FF;  
      my $negative    = (hex($a[3])) & 0xC; 

      if ($negative == 0xC) {
        $temp = (~$temp & 0x03FF) + 1;
        $temp = -$temp;
      }
      $temp = $temp / 10;

      if (checkValues($hash,"Rubicson",$temp)) {
        $model="Rubicson";
        $channel = 0;
        
        if ($deviceCode ne $idType1)  # new naming convention
     	{	
		  	if ( $enableLongIDs == TRUE || (($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
          	{
	             Log3 $hash,4, "$iodev: CUL_TCM97001 using longid: $longids model: $model";
           	} else {
	             $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
           	}
     	}     
      
      	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
      	if($def) {
       	 $name = $def->{NAME};
        }
        else {
          goto UNDEFINED_MODEL;
        }

        $packageOK = TRUE;
        
        $readedModel=$model;
      } else {
          $name = $nameUnknown;
      }
    }

      if ( (checkCRC4($hash, $msg) == TRUE) && (isRain($hash, $msg)==TRUE) &&($readedModel eq "PFR_130" || $readedModel eq "Unknown")) {
      # Implementation from Femduino
      # Pollin PFR_130)
      # nibbles n2, n6 and n7 hold the Rain fall ticks
      #                /--------------------------------- Channel, changes after every battery change      
      #               /           / ------------------------ Battery state 0 == Ok      
      #              /           / /------------------------ ??Battery changed, Sync startet      
      #             /           / /  ----------------------- n2 lower two bits ->rain ticks      
      #            /           / / /    /------------------- neg Temp: if 1 then temp = temp - 4096
      #           /           / / /    /-------------------- 12 Bit Temperature
      #          /           / / /    /               /----- n6,n7 rain ticks 8 bit (n2 & 0x03 n6 n7) 
      #         /           / / /    /               /       /---- n8, CRC (xor n0 to n7)
      #         0101 0101  1 0 00   0001 0000 1011  11000100 xxxx
      # Bit     0          8 9 10   12              24       32
      $def = $modules{CUL_TCM97001}{defptr}{$idType1};
      if($def) {
        $name = $def->{NAME};
      } 
      $temp    = (hex($a[3].$a[4].$a[5])) & 0x7FF;  
      my $negative    = (hex($a[3])) & 0x8; 
      if ($negative == 0x8) {
        $temp = (~$temp & 0x07FF) + 1;
        $temp = -$temp;
      }
      $temp = $temp / 10;
      Log3 $name, 5, "$iodev: CUL_TCM97001 PFR_130 Temp=$temp";
        
      # rain values Pollin PFR_130      
      $rainticks = (hex($a[2].$a[6].$a[7])) & 0x3FF; #mask n2 n6 n7 for rain ticks
      Log3 $name, 5, "$iodev: CUL_TCM97001 PFR_130 rainticks=$rainticks";
      $rainMM = $rainticks / 25 * .5; # rain height in mm/qm, verified against sensor receiver display
      Log3 $name, 5, "$iodev: CUL_TCM97001 PFR_130 rain mm=$rainMM";
      
      if (checkValues($hash,"PFR_130",$temp)) {
        $batbit = (hex($a[2]) & 0x8) >> 3; # in auriol_protocol_v20.pdf bat bit is n2 & 0x08, same
        $batbit = ~$batbit & 0x1; # Bat bit umdrehen
        $mode   = (hex($a[2]) & 0x4) >> 2; # in auriol_protocol_v20.pdf mode is: n2 & 0x01, different

        $trend = (hex($a[7]) & 0x3); # in auriol_protocol_v20.pdf there is no trend bit
        $model="PFR_130";
        my $pfrId = "";
     
     	if (!defined($modules{CUL_TCM97001}{defptr}{$idType1}))
     	{	
          if ( $enableLongIDs == TRUE || (($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
          	{
	             $deviceCode="CUL_TCM97001_".$idType1;
	             $pfrId = "_" . $idType1;
	             Log3 $hash,4, "$iodev: CUL_TCM97001 using longid: $longids model: $model";
           	} else {
	             $deviceCode="CUL_TCM97001_" . $model; # . "_" . $channel;
           	}
     	}  else  {  # Fallback for already defined devices use old naming convention
     		$deviceCode=$idType1;
     	}     
      
      	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
      	if($def) {
       	 $name = $def->{NAME};
        }
        else {
          goto UNDEFINED_MODEL;
        }

        $hasbatcheck = TRUE;
        $hastrend = FALSE; # PFR_130 has no trend
        $packageOK = TRUE;
        $hasmode = TRUE;
        
        $readedModel=$model;
      } else {
          $name = $nameUnknown;
      }
    }

    #if (($readedModel eq "Unknown" || $readedModel eq "KW9010")) {
    if (checkCRCKW9010($hash, $msg) == TRUE && ($readedModel eq "Unknown" || $readedModel eq "KW9010" || $readedModel eq "KW9015")) {
        # Re: Tchibo Wetterstation 433 MHz - KW9010
        # KW9015 (TFA 30.3161): Kanal ist immer 0 und Hum ist rain
        # See also http://forum.arduino.cc/index.php?PHPSESSID=ffoeoe9qeuv7rf4fh0d637hd74&topic=136836.msg1536416#msg1536416
        #                 /------------------------------------- Random ID part one
        #                /    / -------------------------------- Channel switch       
        #               /    /  /------------------------------- Random ID part two      
        #              /    /  /  / ---------------------------- Battery state 0 == Ok      
        #             /    /  /  / / --------------------------- Trend (continous, rising, falling      
        #            /    /  /  / /  / ------------------------- forced send      
        #           /    /  /  / /  /  / ----------------------- Temperature
        #          /    /  /  / /  /  /          /-------------- Temperature sign bit. if 1 then temp = temp - 4096
        #         /    /  /  / /  /  /          /  /------------ Humidity
        #        /    /  /  / /  /  /          /  /       /----- Checksum
        #       0110 00 10 1 00 1  000000100011  00001101 1101
        #       0110 01 00 0 10 1  100110001001  00001011 0101
        # Bit   0    4  6  8 9  11 12            24       32
        #
        #5922B07BC0 42 21.2 66
        # 0101 10 01 0 01 0 001010110000 01111011 1100 0000
        #                   000011010100 11011110
        #                      212       222-156=66
        my @a = split("", $msg);
        my $bitReverse = "";
        my $x = undef;
        foreach $x (@a) {
           $bitReverse = $bitReverse . reverse(sprintf("%04b",hex($x))); 
        }
        my $hexReverse = unpack("H*", pack ("B*", $bitReverse));
        Log3 $hash, 5 , "$iodev: KW901x CRC Matched: ($bitReverse) Hex: $hexReverse";

        #Split reversed a again
        my @aReverse = split("", $hexReverse);

        if (hex($aReverse[5]) > 3) {
           # negative temp
           $temp = ((hex($aReverse[3]) + hex($aReverse[4]) * 16 + hex($aReverse[5]) * 256));
           $temp = (~$temp & 0x03FF) + 1;
           $temp = -$temp/10;
        } else {
           # positive temp
           $temp = (hex($aReverse[3]) + hex($aReverse[4]) * 16 + hex($aReverse[5]) * 256)/10;
        }
        my $rainHum = hex($aReverse[7].$aReverse[6]);
        
        my $retCheck;
        if ($readedModel eq "Unknown") {
            $retCheck = checkValues($hash,"KW901x",$temp);
        } elsif ($readedModel eq "KW9010") {
            $humidity = $rainHum - 156;
            $retCheck = checkValues($hash,"KW9010",$temp, $humidity);
            if ($retCheck) {
                $hashumidity = TRUE;
            }
        } else {
            $retCheck = checkValues($hash,"KW9015",$temp);
            if ($retCheck) {
                $hasrain = TRUE;
                $rain = $rainHum * 0.45;
            }
        }

        if ($retCheck) {				# unplausibel Werte sonst teilweise
            $batbit = (hex($a[2]) & 0x8) >> 3;
            $batbit = ~$batbit & 0x1; # Bat bit umdrehen
            $channel = ((hex($a[1])) & 0xC) >> 2;
            $mode = (hex($a[2]) & 0x1);
            $trend = (hex($a[2]) & 0x6) >> 1;
            if ($trend == 1 || $trend == 2) { # falling und rising tauschen
               $trend ^= 3;
            }

            if ($readedModel eq "Unknown") {
               if ($channel > 0) {
                  $model="KW9010";
               }
               else {
                  $model="KW9015";
               }
            } else {
               $model=$readedModel;
            }

            if ($deviceCode ne $idType1)  # new naming convention
         	{	
		      	if ( $enableLongIDs == TRUE || (($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
              	{
		             Log3 $hash,4, "$iodev: CUL_TCM97001 using longid: $longids model: $model";
               	} else {
		             $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
               	}
         	}     
          
          	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
            if($def) {
              $name = $def->{NAME};
              return "" if (checkRain($def, $iodev, $rain) == FALSE);
            }
            else {
              goto UNDEFINED_MODEL;
            }
            #$hashumidity = TRUE;
            $packageOK = TRUE;
            $hasbatcheck = TRUE;
            $hastrend = TRUE;  
            if ($channel > 0) {
                $haschannel = TRUE;
            }
            $hasmode = TRUE;
            $readedModel=$model;
        } else {
            $name = $nameUnknown;
        }
    }

    if ($readedModel eq "Auriol_IAN" || (hex($a[7]) < 10 && hex($a[8]) < 10 && hex($a[9]) >= 1 && hex($a[9]) <= 3 && $readedModel eq "Unknown")) {
        # Auriol Message Format (rflink/Plugin_044.c):
        # 0    4    8    12   16   20   24   28   32   36
        # 1011 1111 1001 1010 0110 0001 1011 0100 1001 0001
        # B    F    9    A    6    1    B    4    9    1
        # iiii iiii ???? sbTT tttt tttt tttt hhhh hhhh ??cc
        # i = ID
        # ? = unknown (0-15 check?)
        # s = sendmode (1=manual, 0=auto)
        # b = possibly battery indicator (1=low, 0=ok)
        # T = temperature trend (2 bits) indicating temp equal/up/down
        # t = Temperature => 0x61b  (0x61b-0x4c4)=0x157 *5)=0x6b3 /9)=0xBE => 0xBE = 190 decimal!
        # h = humidity (4x10+9=49%)
        # ? = unknown (always 00?)
        # c = channel: 1 (2 bits)

      $temp = round(((hex($a[4].$a[5].$a[6]) - 1220) * 5 / 90.0), 1);
      if (hex($a[7]) < 10 && hex($a[8]) < 10) {
        $humidity = $a[7] * 10 + $a[8];
      }
      else {
        $humidity = 101;	# ungueltige humidity
      }

      if (checkValues($hash,"Auriol_IAN", $temp, $humidity)) {
        $batbit = (hex($a[3]) & 0x4) >> 2;
        $batbit = ~$batbit & 0x1; # Bat bit umdrehen
        $mode = (hex($a[3]) & 0x8) >> 3;
        $trend = hex($a[3]) & 0x3;
        $channel = (hex($a[9])) & 0x3;

        $model="Auriol_IAN";

        if ($deviceCode ne $idType1)  # new naming convention
        {
           if ( $enableLongIDs == TRUE || (($longids != "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
           {
              Log3 $hash,4, "$iodev: CUL_TCM97001 using longid: $longids model: $model";
           } else {
              $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
           }
        }

        $def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
        if($def) {
          $name = $def->{NAME};
        }
        else {
          goto UNDEFINED_MODEL;
        }
        #if ($humidity >= 20) {
        $hashumidity = TRUE;
        #}
        $hasbatcheck = TRUE;
        $haschannel = TRUE;
        $hasmode = TRUE;
        $hastrend = TRUE;
        $packageOK = TRUE;

        $readedModel=$model;
      } else {
        $name = $nameUnknown;
      }
    }
    
    if ($readedModel eq "Mebus7312" || (hex($a[6]) == 0xF && $readedModel eq "Unknown")) {
      # https://forum.fhem.de/index.php/topic,123305.msg1178527.html#msg1178527
      #
      # 0    4    8    12   16   20   24   28   32
      # iiii iiii bscc tttt tttt tttt 1111 hhhh hhhh
      # i = ID
      # s = sendmode (1=manual, 0=auto) ??? ist dies immer 0 oder aendert es sich beim druecken der Resettaste?
      # b = battery indicator (1=low, 0=ok)
      # c = channel
      # t = Temperature
      # h = humidity
      $temp = hex($a[3].$a[4].$a[5]);
      if ($temp >= 3840) {
        $temp -= 4096;
      }
      $temp /= 10;
      
      $humidity = hex($a[7].$a[8]);
      
      if (checkValues($hash,"Mebus7312", $temp, $humidity)) {
        $channel = ((hex($a[2])) & 0x3) + 1;
        $batbit = (hex($a[2]) & 0x8) >> 3;
        $model="Mebus7312";
        
        if (!defined($modules{CUL_TCM97001}{defptr}{$idType1}))
        {
          if ( $enableLongIDs == TRUE || (($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
          {
            $deviceCode="CUL_TCM97001_".$idType1;
            Log3 $hash,4, "$iodev: CUL_TCM97001 using longid: $longids model: $model, deviceCode: $deviceCode"; # deviceCode nur zum debuggen
          } else {
            $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
          }
        } else  {  # Fallback for already defined devices use old naming convention
          $deviceCode=$idType1;
        }
        
        $def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
        if($def) {
          $name = $def->{NAME};
        }
        else {
          goto UNDEFINED_MODEL;
        }

        if ($humidity > 0) {
          $hashumidity = TRUE;
        }
        $hasbatcheck = TRUE;
        $haschannel = TRUE;
        #$hastrend = TRUE;     
        $packageOK = TRUE;
        #$hasmode = TRUE;
        
        $readedModel=$model;
      } else {
          $name = $nameUnknown;
      }
    }
    
      if (($readedModel eq "AURIOL" || $readedModel eq "Unknown")) {
      # Implementation from Femduino
      # AURIOL (Lidl Version: 09/2013), Z31743B IAN 91838
      #                /--------------------------------- Channel, changes after every battery change      
      #               /           / ------------------------ Battery state 1 == Ok      
      #              /           / /------------------------ Battery changed, Sync startet      
      #             /           / /  ----------------------- Unknown      
      #            /           / / /    /--------------------- neg Temp: if 1 then temp = temp - 4096
      #           /           / / /    /---------------------- 12 Bit Temperature
      #          /           / / /    /               /---------- ??? CRC 
      #         /           / / /    /               /       /---- Trend 10 == rising, 01 == falling
      #         0101 0101  1 0 00   0001 0000 1011  1100  01 00
      # Bit     0          8 9 10   12              24       30
      $def = $modules{CUL_TCM97001}{defptr}{$idType1};
      if($def) {
        $name = $def->{NAME};
      } 
      $temp    = (hex($a[3].$a[4].$a[5])) & 0x7FF;  
      my $negative    = (hex($a[3])) & 0x8; 
      if ($negative == 0x8) {
        $temp = (~$temp & 0x07FF) + 1;
        $temp = -$temp;
      }
      $temp = $temp / 10;

      if (checkValues($hash,"AURIOL",$temp)) {
        $batbit = (hex($a[2]) & 0x8) >> 3;
        #$batbit = ~$batbit & 0x1; # Bat bit umdrehen
        $mode   = (hex($a[2]) & 0x4) >> 2;
        $channel = 0;
        $trend = (hex($a[7]) & 0x3);
        $model="AURIOL";
     
     	if (!defined($modules{CUL_TCM97001}{defptr}{$idType1}))
     	{	
		  	if ( $enableLongIDs == TRUE || (($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
          	{
	             $deviceCode="CUL_TCM97001_".$idType1;
	             Log3 $hash,4, "$iodev: CUL_TCM97001 using longid: $longids model: $model, deviceCode: $deviceCode"; # deviceCode nur zum debuggen
           	} else {
	             $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
           	}
     	}  else  {  # Fallback for already defined devices use old naming convention
     		$deviceCode=$idType1;
     	}     
      
      	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
      	if($def) {
       	 $name = $def->{NAME};
        }
        else {
          goto UNDEFINED_MODEL;
        }

        $hasbatcheck = TRUE;
        $hastrend = TRUE;     
        $packageOK = TRUE;
        $hasmode = TRUE;
        
        $readedModel=$model;
      } else {
          $name = $nameUnknown;
      }
    }

    if (($readedModel eq "TCM218943" || $readedModel eq "Unknown")) {
        #    87FFDE0AD0EB
        # 1000 0111 1111 1111 1101 1110 0000 1010 1101 0000 1110 1011
        #    A    B    C    D    E    F    G    H    I
        #
        # Binaerwerte sind invertiert!
        # A+B = Zufaellige Code wechelt beim Batteriewechsel
        # C Bit 3 Battery, 0 Manual,
        # E+F Hum - bit 0-7
        # G+H+I Hum - Temperatur, wenn es negativ wird muss man negieren und dann 1 addieren

      $temp    = (hex($a[6].$a[7].$a[8])) & 0x3FF;
      $temp = (~$temp & 0x03FF);

      my $negative    = (~hex($a[6])) & 0xC;
      if ($negative == 0xC) {
        $temp = (~$temp & 0x03FF) + 1;
        $temp = -$temp;
      }
      $temp = $temp / 10;

      $humidity = hex($a[4].$a[5]);
      $humidity = (~$humidity & 0xFF);

      if (checkValues($hash,"TCM218943", $temp, $humidity)) {
        $batbit = (hex($a[2]) & 0x8) >> 3;
        $mode    = hex($a[2]) & 0x1;
        $mode    = (~$mode & 0x1);
        $channel = 0;
        $model="TCM218943";

        if ($deviceCode ne $idType1)  # new naming convention
        {
           if ( $enableLongIDs == TRUE || (($longids != "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
           {
              Log3 $hash,4, "$iodev: CUL_TCM97001 using longid: $longids model: $model";
           } else {
              $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
           }
        }

        $def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
        if($def) {
          $name = $def->{NAME};
        }
        else {
          goto UNDEFINED_MODEL;
        }
        if ($humidity >= 20) {
          $hashumidity = TRUE;
        }
        $hasbatcheck = TRUE;
        $haschannel = FALSE;
        $hasmode = TRUE;
        $packageOK = TRUE;

        $readedModel=$model;
      } else {
        $name = $nameUnknown;
      }
    }
  } elsif (length($msg) == 14) {
    my $hlen = length($msg);
    my $blen = $hlen * 4;
    my $bitData = unpack("B$blen", pack("H$hlen", $msg));
    my $idType1 = hex($a[0] . $a[1]);
    $deviceCode = "CUL_TCM97001_" . $idType1;
    $def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
    if($def) {
       $name = $def->{NAME};
    }
    $readedModel = AttrVal($name, "model", "Unknown");
    Log3 $iodev, 4, "$iodev: CUL_TCM97001 Parse Name: $name , devicecode: $deviceCode, Model defined: $readedModel";
    
    if (checkCRC_sduinoID33($hash,$bitData) == TRUE && ($readedModel eq "Unknown" || $readedModel eq "NX7674")) {
       # https://forum.fhem.de/index.php?topic=135692.0
       # Rosenstein & Soehne, Kuehl- & Gefrierschrank-Thermometer
       #
       # 0    4    | 8    12   | 16   20   | 24   28   | 32   36   | 40
       # 00Ii iiii | ii00 cctt | tttt tttt | tt00 0000 | 000b TTxx | xx00
       # I: 0 - sensor 1, 1 - sensor 2
       # i: random id (changes on power-loss)
       # c: Channel
       # t: Temperature
       # b: battery indicator (0=>OK, 1=>LOW)
       # T: Temperature trend
       # x: crc4
       #
       # dmsg s114735400540E3 T: 15.6, Bat: ok, CH: 1
       $temp = (oct("0b". substr($bitData,22,4) . substr($bitData,18,4) . substr($bitData,14,4)) - 1220) * 5 / 90.0;
       $batbit = substr($bitData,35,1) eq "0" ? 1 : 0; 
       $channel = substr($bitData,2,1) eq "0" ? 1 : 2;
       $trend = oct("0b".substr($bitData,36,2));
       if ($trend == 1 || $trend == 2) { # falling und rising tauschen
         $trend ^= 3;
       }
       $model = "NX7674";
       
         if ( $enableLongIDs == TRUE || (($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
         {
           Log3 $hash,4, "$iodev: CUL_TCM97001 using longid: $longids model: $model";
         } else {
           $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
         }
       $def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
       if($def) {
         $name = $def->{NAME};
       } else {
         goto UNDEFINED_MODEL;
       }
         
       $hasbatcheck = TRUE;
       $haschannel = TRUE;
       $hastrend = TRUE;
       $packageOK = TRUE;
       
       $readedModel=$model;
    }
  }
  
  	# Ignoriere dieses Geraet. Das Geraet wird keine FileLogs/notifys triggern, empfangene Befehle
	# werden stillschweigend ignoriert. Das Geraet wird weder in der Device-List angezeigt,
	# noch wird es in Befehlen mit "Wildcard"-Namenspezifikation (siehe devspec) erscheinen.
	return "" if(IsIgnored($name));	# wenn Attribut "ignore" gesetzt ist, werden alle Ausgaben ignoriert
  
  if ($packageOK == TRUE) {
    # save lastT, calc rainMM sum for day and hour
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $lastDay=$mday;
    my $lastHour=$hour;
    my $rainSumDay=0;
    my $rainSumHour=0;
   
    if($def) {
      $def->{lastT} = $now;
    }
    readingsBeginUpdate($def);
    my ($val, $valH);
    my $state = "";
    
    if (defined($temp)) {
      $val = sprintf("%2.1f", ($temp) );
      $state="T: $val";
#    if ($hashumidity == TRUE) {
#      if ($model eq "Prologue") {
#         # plausibility check 
#         my $oldhumidity = ReadingsVal($name, "humidity", "unknown");
#         if ($oldhumidity eq "unknown" || ($humidity+15 > $oldhumidity && $humidity-15 < $oldhumidity)) {
#            $hashumidity = TRUE;
#         } else {
#            $hashumidity = FALSE;
#         }
#      } 
#    }
    }
    if ($model eq "PFR_130") {
      $lastDay = ReadingsVal($name, "lastDay", $lastDay);
      $lastHour = ReadingsVal($name, "lastHour", $lastHour);
      $rainSumDay=ReadingsVal($name, "RainD", $rainSumDay);
      $rainSumHour=ReadingsVal($name, "RainH", $rainSumHour);
      
      $val = sprintf("%2.1f", ($temp) );
      $state="T: $val";
      Log3 $name, 5, "$iodev: CUL_TCM97001 1. $lastDay : $lastHour : $rainSumDay : $rainSumHour";
      #rain Pollin PFR-130
      if($mday==$lastDay){
         #same day add rainMM
         $rainSumDay+=$rainMM;
      }else {
         #new day, start over
         $rainSumDay=$rainMM;
         $lastDay=$mday; #set new lastDay (Patch von hjgode)
      } 
      if($hour==$lastHour){
         $rainSumHour+=$rainMM;
      }else{
         $rainSumHour=$rainMM;
         $lastHour=$hour; # set new lastHour (Patch von hjgode)
      }
      
      readingsBulkUpdate($def, "lastDay", $lastDay );
      readingsBulkUpdate($def, "lastHour", $lastHour );
      readingsBulkUpdate($def, "RainD", $rainSumDay );
      readingsBulkUpdate($def, "RainH", $rainSumHour );
      
      Log3 $name, 5, "$iodev: CUL_TCM97001 2. $lastDay : $lastHour : $rainSumDay : $rainSumHour";
      $state="$state RainH: $rainSumHour RainD: $rainSumDay R: $rainticks Rmm: $rainMM";
      Log3 $name, 5, "$iodev: CUL_TCM97001 $name $id3 state: $state"; 
   }
      my $logtext = "";
      #zusaetzlich Daten fuer Wetterstation
    if ($hasrain == TRUE) {
         ### inserted by elektron-bbs
         #my $rain_old = ReadingsVal($name, "rain", "unknown");
         my $rain_old = ReadingsVal($name, "rain", 0);
         if ($rain != $rain_old) {
            readingsBulkUpdate($def, "israining", "yes");
         } else {
            readingsBulkUpdate($def, "israining", "no");
         }
         readingsBulkUpdate($def, "rain", $rain );
         
         $state .= " " if (length($state) > 0);
         $state .= "R: $rain";
         $logtext = " R: $rain";
         $hasrain = FALSE;
    }
    if ($haswind == TRUE) {
          readingsBulkUpdate($def, "windGust", $windGuest );
          readingsBulkUpdate($def, "windDirection", $windDirection );
          readingsBulkUpdate($def, "windDirectionDegree", $windDirectionDegree );
          readingsBulkUpdate($def, "windDirectionText", $windDirectionText );
          $state = "Wg: $windGuest "." Wd: $windDirectionText ";
          $haswind = FALSE;
    }
    if ($haswindspeed == TRUE) {
          readingsBulkUpdate($def, "windSpeed", $windSpeed );
          $state = "Ws: $windSpeed ";
          $haswindspeed = FALSE;
    }
    if (defined($temp)) {
      $logtext .= " T: $val";
    }
    if ($hashumidity == TRUE) {
      $valH = $humidity;
      $state .= " H: $valH";
      $logtext .= " H: $valH";
    }
    if($hastrend) {
      my $readTrend = ReadingsVal($name, "trend", "undef");
      $trend = ('consistent', 'falling', 'rising', 'unknown')[$trend];
      if ($readTrend ne $trend) {
        readingsBulkUpdate($def, "trend", $trend);
      }
      $logtext .= " trend: $trend";
    }
    if ($hasbatcheck) {
      if (AttrVal($name, "negation-batt", 0)) {
        $batbit = $batbit ? 0 : 1;	# Bat bit umdrehen
      }
      my $battery = ReadingsVal($name, "battery", "unknown");
      my $bat = $batbit eq "1" ? "ok" : "low";
      $logtext .= " Bat: $bat";
      if ($bat ne $battery) {
         readingsBulkUpdate($def, "battery", $bat);
         readingsBulkUpdate($def, "batteryState", $bat);
      }
      $hasbatcheck = FALSE;
    }
    if ($hasmode) {
      my $modeVal = ReadingsVal($name, "mode", "unknown");
      if ($mode) {
        $logtext .= " mode: forced";
        if ($modeVal ne  "forced") { 
          readingsBulkUpdate($def, "mode", "forced");
        }
      } else {
        if ($modeVal ne  "normal") { readingsBulkUpdate($def, "mode", "normal"); }
      }
      $hasmode = FALSE;
    }
    if ($haschannel) {
      $logtext .= " CH: $channel";
      my $readChannel = ReadingsVal($name, "channel", "");
      if (defined($readChannel) && $readChannel ne $channel) { readingsBulkUpdate($def, "channel", $channel); }
    }
    if ($logtext ne "") {
      Log3 $hash, 4, "$iodev: CUL_TCM97001 $name ID: $id3$logtext";
    }
#    if ($model eq "Prologue" || $model eq "Eurochron") {
#         # plausibility check 
#         my $oldtemp = ReadingsVal($name, "temperature", "unknown");
#         if ($oldtemp eq "unknown" || ($val+5 > $oldtemp && $val-5 < $oldtemp)) {
#            readingsBulkUpdate($def, $msgtype, $val);
#         }
#    } else { 
    if (defined($temp)) {
       readingsBulkUpdate($def, "temperature", $val);
    }
    if ($hashumidity == TRUE) {
       readingsBulkUpdate($def, "humidity", $valH);
    }

    readingsBulkUpdate($def, "state", $state);
    # for testing only
    #my $rawlen = length($msg);
    #my $rawVal = substr($msg, 0, $rawlen-2);
    #readingsBulkUpdate($def, "RAW", $rawVal);

    readingsEndUpdate($def, 1);
    if(defined($rssi)) {
      $def->{RSSI} = $rssi;
    } 
    $attr{$name}{model} = $model;

    return $name;
  } else {
    if (length($msg) == 8 || length($msg) == 10 || length($msg) == 12 || length($msg) == 14) {
    #my $defUnknown = $modules{CUL_TCM97001}{defptr}{"CUL_TCM97001_Unknown"};
    
    if (!$defUnknown) {
      Log3 $iodev, 2, "$iodev: CUL_TCM97001 Unknown device Unknown msg:s$msg, please define it";
      return "UNDEFINED Unknown CUL_TCM97001 CUL_TCM97001_Unknown"; 
    } 
    $name = $defUnknown->{NAME};
    if ($readedModel eq "Unknown") {
      Log3 $name, 4, "$iodev: CUL_TCM97001 Device not implemented yet name Unknown msg $msg";
    }
    else {
      Log3 $name, 4, "$iodev: CUL_TCM97001 Unknown msg $msg don't match to already defined Device $readedModel";
    }

      my $rawlen = length($msg);
      my $rawVal = substr($msg, 0, $rawlen-2);
      my $state="Code: $rawVal";

    if ($defUnknown) {
      $defUnknown->{lastT} = $now;
    }

    $attr{$name}{model} = $model;
    readingsBeginUpdate($defUnknown);
    readingsBulkUpdate($defUnknown, "state", $state);

      # for testing only
      #readingsBulkUpdate($defUnknown, "RAW", $rawVal);
      
      if (AttrVal($nameUnknown,'disableUnknownEvents',FALSE) == TRUE) {
        readingsEndUpdate($defUnknown, 0);
      }
      else {
        readingsEndUpdate($defUnknown, 1);
      }
      if(defined($rssi)) {
        $defUnknown->{RSSI} = $rssi;
      }

      #my $defSvg = $defs{"SVG_CUL_TCM97001_Unknown"}; 

      #if ($defSvg) {
      #  CommandDelete(undef, $defSvg->{NAME});
      #}
      return $name;
    }
  }

  return undef;

  UNDEFINED_MODEL:
  Log3 $name, 2, "$iodev: CUL_TCM97001 Unknown device $deviceCode model:$model msg:s$msg, please define it";
  if ($hasUnknownDevice == TRUE && AttrVal($nameUnknown, 'disableCreateUndefDevice', FALSE) == TRUE) {
     my $readingModelName;
     my $rn;
     my $undefModelName = $model . substr($deviceCode, rindex($deviceCode,'_'));
     if (do_undefModelReading($defUnknown, $iodev, $undefModelName, 'undefModel_a') == FALSE) { # Modell + ID passt nicht
       if (do_undefModelReading($defUnknown, $iodev, $undefModelName, 'undefModel_b') == FALSE) { # Modell + ID passt nicht
          if (ReadingsAge($nameUnknown, 'undefModel_b', 0) > ReadingsAge($nameUnknown, 'undefModel_a', 0)) { # ist undefModel_b aelter als undefModel_a?
            readingsSingleUpdate($defUnknown, 'undefModel_b', "$undefModelName,$iodev,n=1" , 0);
          }
          else {
            readingsSingleUpdate($defUnknown, 'undefModel_a', "$undefModelName,$iodev,n=1" , 0);
          }
       }
     }
     return "";
  }
  return "UNDEFINED $model" . substr($deviceCode, rindex($deviceCode,"_")) . " CUL_TCM97001 $deviceCode";
}

sub do_undefModelReading {
  my $defUnknown = shift;
  my $iodev = shift;
  my $undefModelName = shift;
  my $readingNameUndefModel = shift;
  
  my $rn;
  my $name = $defUnknown->{NAME};
  my $undefModel = ReadingsVal($name, $readingNameUndefModel, '');
  if ($undefModel eq '') {  # gibt es das reading undefModel_x noch nicht?
    readingsSingleUpdate($defUnknown, $readingNameUndefModel, "$undefModelName,$iodev,n=0" , 0); # neues reading
  }
  else { # das reading undefModel_x gibts schon
    my $readingModelName = substr($undefModel, 0, index($undefModel, ','));
    if ($undefModelName eq $readingModelName) {  # passt Modell + ID? Ja, dann n um eins erhoehen
       if (substr(ReadingsTimestamp($name, $readingNameUndefModel, 0),0,10) eq substr(FmtDateTime(time()),0,10)) { # der gleiche Tag?
         $rn = substr($undefModel, rindex($undefModel,'=')+1);
         $rn++;
       }
       else {
         $rn = 1;
       }
       readingsSingleUpdate($defUnknown, $readingNameUndefModel, "$undefModelName,$iodev,n=$rn" , 0);
    }
    else { # Modell + ID passt nicht
       return FALSE;
    }
  }
  return TRUE;
}

1;


=pod
=item summary    This module interprets temperature sensor messages.
=item summary_DE Modul verarbeitet empfangene Nachrichten von Temp-Sensoren & Wettersensoren.
=begin html

<a name="CUL_TCM97001"></a>
<h3>CUL_TCM97001</h3>
<ul>
  The CUL_TCM97001 module interprets temperature sensor messages received by a Device like CUL, CUN, SIGNALduino etc.<br>
  <br>
  <b>Supported models:</b>
  <ul>
    <li>ABS700</li>
    <li>AURIOL (older Sensors with only Temperature)</li>
    <li>Auriol_IAN (NC-3982, ADE WS 1503, Tchibo 65 722)</li>
    <li>Auriol_Z31743B</li>
    <li>Eurochron</li>
    <li>GT_WT_02</li>
    <li>KW9010</li>
    <li>KW9015 (TFA 30.3161)</li>
    <li>Mebus</li>
    <li>Mebus7312</li>
    <li>NC_WS (PEARL NC7159)</li>
    <li>TCM21....</li>
    <li>TCM218943</li>
    <li>TCM97...</li>
    <li>Type1</li>
    <li>PFR-130 (rain)</li>
    <li>Prologue (GT-WT-01)</li>
    <li>Rubicson</li>
    <li>Ventus W155(Auriol): W044(temp/hum) W132(wind) W174(rain)</li>
    </ul>
  <br>
  New received device packages are add in fhem category CUL_TCM97001 with autocreate.
  <br><br>

  <a name="CUL_TCM97001_Define"></a>
  <b>Define</b> 
  <ul>The received devices created automatically.<br>
  The ID of the defive are the first two Hex values of the package as dezimal.<br>
  </ul>
  <br>
  <a name="CUL_TCM97001 Events"></a>
  <b>Generated events:</b>
  <ul>
   <li>temperature: The temperature</li>
   <li>humidity: The humidity (if available)</li>
   <li>battery: The battery state: low or ok (if available)</li>
   <li>channel: The Channelnumber (if available)</li>
   <li>trend: The temperature trend (if available)</li>
   <li>israining: Statement rain between two measurements (if available)</li>
   <li>rain: The rain value, a consecutive number until the battery is changed (if available)</li>
   <li>winddir: The current wind direction</li>
   <li>windgrad: The current wind direction in degrees</li>
   <li>windspeed: The current wind speed</li>
   <li>windgust: windguest</li>
  </ul>
  <br>
  <b>Attributes</b>
  <ul>
    <li><a href="#IODev">IODev</a>
      Note: by setting this attribute you can define different sets of 8
      devices in FHEM, each set belonging to a Device which is capable of receiving the signals. It is important, however,
      that a device is only received by the defined IO Device, e.g. by using
      different Frquencies (433MHz vs 868MHz)
      </li>
    <li>disableCreateUndefDevice<br>
         this can be used to deactivate the creation of new devices<br>
         the new devices (Modell + ID, ioname, number) are saved in the device Unknown in the readings "undefModel_a" and "undefModel_b"</li>
    <li>disableUnknownEvents<br>
         with this, the events can be deactivated for unknown messages</li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#model">model</a> (ABS700, AURIOL, Auriol_IAN, GT_WT_02, KW9010, NC_WS, PFR-130, Prologue, Rubicson, TCM21...., TCM218943, TCM97…, Unknown, W044, W132, W174)</li>
    <li>max-deviation-temp: (default:1, allowed values: 1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50)<br>
       Maximum permissible deviation of the measured temperature from the previous value in Kelvin.</li>
    <li>max-diff-rain: Default:0 (deactive)<br>
       Maximum permissible deviation of the rainfall to the previous value in l/qm.</li>
    <li>negation-batt: invert Battery reading</li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li>windDirectionInverse: If the anemometer has been mounted upside down, the wind direction can be turned around</li>
  </ul>


</ul>

=end html

=begin html_DE

<a id="CUL_TCM97001"></a>
<h3>CUL_TCM97001</h3>
<ul>
  Das CUL_TCM97001 Modul verarbeitet von einem IO Ger&auml;t (CUL, CUN, SIGNALDuino, etc.) empfangene Nachrichten von Temperatur \ Wind \ Rain - Sensoren.<br>
  <br>
  <b>Unterst&uuml;tzte Modelle:</b>
  <ul>
    <li>ABS700</li>
    <li>AURIOL (&auml;ltere Sensoren mit nur Temperatur)</li>
    <li>Auriol_IAN (NC-3982, ADE WS 1503, Tchibo 65 722)</li>
    <li>Auriol_Z31743B</li>
    <li>Eurochron</li>
    <li>GT_WT_02</li>
    <li>KW9010</li>
    <li>KW9015 (TFA 30.3161)</li>
    <li>Mebus</li>
    <li>Mebus7312</li>
    <li>NC_WS (PEARL NC7159)</li>
    <li>TCM21....</li>
    <li>TCM218943</li>
    <li>TCM97...</li>
    <li>Type1</li>
    <li>PFR-130 (rain)</li>
    <li>Prologue (GT-WT-01)</li>
    <li>Rubicson</li>
    <li>Ventus W155(Auriol): W044(temp/hum) W132(wind) W174(rain)</li>
      </ul>
  <br>
  Neu empfangene Sensoren werden in der fhem Kategory CUL_TCM97001 per autocreate angelegt.
  <br><br>

  <a id="CUL_TCM97001-define"></a>
  <b>Define</b> 
  <ul>Die empfangenen Sensoren werden automatisch angelegt.<br>
  Die ID der angelegten Sensoren sind die ersten zwei HEX Werte des empfangenen Paketes in dezimaler Schreibweise.<br>
  </ul>
  <br>
  <a name="CUL_TCM97001 Events"></a>
  <b>Generierte Events:</b>
  <ul>
   <li>temperature: Die aktuelle Temperatur</li>
   <li>humidity: Die aktuelle Luftfeutigkeit (falls verf&uuml;gbar)</li>
   <li>battery: Der Batteriestatus: low oder ok (falls verf&uuml;gbar)</li>
   <li>channel: Kanalnummer (falls verf&uuml;gbar)</li>
   <li>trend: Der Temperaturtrend (falls verf&uuml;gbar)</li>
   <li>israining: Aussage Regen zwichen zwei Messungen (falls verf&uuml;gbar)</li>
   <li>rain: Der Regenwert, eine fortlaufende Zahl bis zum Batteriewechsel (falls verf&uuml;gbar)</li>
   <li>winddir: Die aktuelle Windrichtung</li>
   <li>windgrad: Die aktuelle Windrichtung in Grad</li>
   <li>windspeed: Die aktuelle Windgeschwindigkeit</li>
   <li>windgust: Windb&ouml;e</li>
  </ul>
  <br>
  <a id="CUL_TCM97001-attr"></a>
  <b>Attribute</b>
  <ul>
    <a id="CUL_TCM97001-attr-IODev"></a>
    <li><a href="#IODev">IODev</a>
      Spezifiziert das physische Ger&auml;t, das die Ausstrahlung der Befehle f&uuml;r das 
      "logische" Ger&auml;t ausf&uuml;hrt. Ein Beispiel f&uuml;r ein physisches Ger&auml;t ist ein CUL.<br>
      </li>
    <a id="CUL_TCM97001-attr-disableCreateUndefDevice"></a>
    <li>disableCreateUndefDevice (nur beim device Unknown)<br>
         damit kann das Anlegen neuer Devices deaktiviert werden<br>
         die neuen Devices (Modell + ID, ioname, Anzahl) werden im Device Unknown in den readings "undefModel_a" und "undefModel_b" gespeichert</li>
    <a id="CUL_TCM97001-attr-disableUnknownEvents"></a>
    <li>disableUnknownEvents (nur beim device Unknown)<br>
         damit k&ouml;nnen die events bei unbekannten Nachrichten deaktiviert werden</li>
    <a id="CUL_TCM97001-attr-do_not_notify"></a>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <a id="CUL_TCM97001-attr-ignore"></a>
    <li><a href="#ignore">ignore</a></li>
    <a id="CUL_TCM97001-attr-model"></a>
    <li>model (L&auml;nge = Codel&auml;nge + 2)<br>
    L&auml;nge = 8 (nur Temp)<br>
    - ABS700<br>
    - TCM97...<br>
    L&auml;nge = 10 (nur Temp)<br>
    - Mebus (CRC)<br>
    - AURIOL<br>
    - Auriol_Z31743B (Lidl Version: 09/2013), Z31743B IAN 91838 (checksum)<br>
    L&auml;nge = 12<br>
    - Eurochron<br>
    - W174 (CRC)<br>
    - TCM21.... (CRC)<br>
    - W044 (CRC)<br>
    - W132 (CRC)<br>
    - GT_WT_02 (CRC)<br>
    - Type1 (CRC)<br>
    - Prologue (beginnt mit 9)<br>
    - NC_WS (beginnt mit 5)<br>
    - Rubicson (3. Stelle ist 8)<br>
    - PFR_130 (CRC)<br>
    - KW9010 und KW9015(CRC)<br>
    - Auriol_IAN<br>
    - Mebus7312 (7. Stelle ist F)<br>
    - AURIOL nur Temp (Lidl Version: 09/2013), Z31743B IAN 91838<br>
    - TCM218943<br>
    L&auml;nge = 14<br>
    - NX7674 (CRC)</li>
    <a id="CUL_TCM97001-attr-max-deviation-temp"></a>
    <li>max-deviation-temp: (Default:1, erlaubte Werte: 1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50)<br>
         Maximal erlaubte Abweichung der gemessenen Temperatur zum vorhergehenden Wert in Kelvin.</li>
    <a id="CUL_TCM97001-attr-max-diff-rain"></a>
    <li>max-diff-rain: Default:0 (deaktiviert)<br>
         Maximal erlaubte Abweichung der Regenmenge zum vorhergehenden Wert in l/qm.</li>
    <a id="CUL_TCM97001-attr-negation-batt"></a>
    <li>negation-batt: Battery reading invertieren</li>
    <a id="CUL_TCM97001-attr-showtime"></a>
    <li><a href="#showtime">showtime</a></li>
    <a id="CUL_TCM97001-attr-readingFnAttributes"></a>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <a id="CUL_TCM97001-attr-windDirectionInverse"></a>
    <li>windDirectionInverse: Wenn der Windmesser auf dem Kopf montiert wurde, kann damit die Windrichtung herumgedreht werden.</li>
  </ul>


</ul>

=end html_DE
=cut
