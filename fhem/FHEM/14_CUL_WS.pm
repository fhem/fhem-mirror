##############################################
# $Id$
package main;

use strict;
use warnings;

# Supports following devices:
# KS300TH     (this is redirected to the more sophisticated 14_KS300 by 00_CUL)
# S300TH  
# WS2000/WS7000
#

#####################################
sub
CUL_WS_Initialize($)
{
  my ($hash) = @_;

  # Message is like
  # K41350270

  $hash->{Match}     = "^K[A-Fa-f0-9]{5,}";
  $hash->{DefFn}     = "CUL_WS_Define";
  $hash->{UndefFn}   = "CUL_WS_Undef";
  $hash->{AttrFn}    = "CUL_WS_Attr";
  $hash->{ParseFn}   = "CUL_WS_Parse";
  no warnings 'qw';
  my @attrList = qw(
    IODev
    do_not_notify:0,1
    ignore:0,1
    model:S300TH,KS300,ASH2200
    showtime:0,1
    strangeTempDiff
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList)." ".$readingFnAttributes;

  $hash->{AutoCreate}=
    { "CUL_WS.*" => { GPLOT => "temp4hum6:Temp/Hum,",  FILTER=>"%NAME:T:.*" } };
}


#####################################
sub
CUL_WS_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> CUL_WS <code> [corr1...corr4]"
            if(int(@a) < 3 || int(@a) > 7);
  return "Define $a[0]: wrong CODE format: valid is 1-8"
                if($a[2] !~ m/^[1-8]$/);

  $hash->{CODE} = $a[2];
  $hash->{corr1} = ((int(@a) > 3) ? $a[3] : 0);
  $hash->{corr2} = ((int(@a) > 4) ? $a[4] : 0);
  $hash->{corr3} = ((int(@a) > 5) ? $a[5] : 0);
  $hash->{corr4} = ((int(@a) > 6) ? $a[6] : 0);
  $modules{CUL_WS}{defptr}{$a[2]} = $hash;
  return undef;
}

#####################################
sub
CUL_WS_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{CUL_WS}{defptr}{$hash->{CODE}}) if($hash && $hash->{CODE});
  return undef;
}


#####################################
sub
CUL_WS_Parse($$)
{
  my ($hash,$msg) = @_;
  my %tlist = ("0"=>"temp",
               "1"=>"temp/hum",
               "2"=>"rain",
               "3"=>"wind",
               "4"=>"temp/hum/press",
               "5"=>"brightness",
               "6"=>"pyro",
               "7"=>"temp/hum");

  # -wusel, 2010-01-24: *sigh* No READINGS set, bad for other modules. Trying
  # to add setting READINGS as well as STATE ...
  my $NotifyType;
  my $NotifyHumidity;
  my $NotifyTemperature;
  my $NotifyRain;
  my $NotifyIsRaining;
  my $NotifyWind;
  my $NotifyWindDir;
  my $NotifyWindSwing;
  my $NotifyBrightness;
  my $NotifyPressure;
  my %NotifyMappings = (
      "T"      => "temperature",
      "H"      => "humidity",
      "R"      => "rain",
      "IR"     => "is_raining",
      "W"      => "wind",
      "WD"     => "wind_direction",
      "WS"     => "wind_swing",
      "B"      => "brightness",
      "P"      => "pressure",
  );
 

  my @a = split("", $msg);

  my $firstbyte = hex($a[1]);
  my $cde = ($firstbyte&7) + 1;
  my $type = $tlist{$a[2]} ? $tlist{$a[2]} : "unknown";

  # There are only 8 S300 devices. In order to enable more, we try to look up
  # the name in connection with the receiver's name ("CUL868.1", "CUL433.1")
  # See attr <name> IODev XX

  my $def = $modules{CUL_WS}{defptr}{$hash->{NAME} . "." . $cde};
  $def = $modules{CUL_WS}{defptr}{$cde} if(!$def);
  if(!$def) {
    my @ac = grep { $defs{$_}{TYPE} eq "autocreate" } keys %defs;
    if(@ac) {
      my $acit = AttrVal($ac[0], "ignoreTypes", "");
      return "" if("CUL_WS_$cde" =~ m/$acit/);
    }
    Log3 $hash, 1, "CUL_WS UNDEFINED $type sensor detected, code $cde";
    return "UNDEFINED CUL_WS_$cde CUL_WS $cde";
  }

  $hash = $def;
  my $name = $hash->{NAME};
  return "" if(IsIgnored($name));
 
  my $typbyte = hex($a[2]) & 7;
  my $sfirstbyte = $firstbyte & 7;
  my $val = "";
  my $devtype = "unknown";
  my $family  = "unknown";
  my ($sgn, $tmp, $rain, $hum, $prs, $wnd);

  my $std = sub($) {
    my ($t) = @_;
    my $std = AttrVal($name, "strangeTempDiff", 0);
    if($std) {
      my $ot = ReadingsVal($name, 'temperature', 0);
      if($ot && abs($ot-$t) > $std) {
        readingsSingleUpdate($def, 'strangeTemp', $t, 0);
        $t = $ot;
      }
    }
    return $t;
  };
    

  if($sfirstbyte == 7) {
  
    if($typbyte == 0 && int(@a) > 6) {           # temp
      $sgn = ($firstbyte&8) ? -1 : 1;
      $tmp = $std->($sgn * ($a[6].$a[3].".".$a[4]) + $hash->{corr1});
      $val = "T: $tmp";
      $devtype = "Temp";
      $NotifyType="T";
      $NotifyTemperature=$tmp;
    }

    if($typbyte == 1 && int(@a) > 8) {           # temp/hum
      $sgn = ($firstbyte&8) ? -1 : 1;
      $tmp = $std->($sgn * ($a[6].$a[3].".".$a[4]) + $hash->{corr1});
      $hum = ($a[7].$a[8].".".$a[5]) + $hash->{corr2};
      $val = "T: $tmp  H: $hum";
      $devtype = "PS50";
      $family = "WS300";
      $NotifyType="T H";
      $NotifyTemperature=$tmp;
      $NotifyHumidity=$hum;
    }

    if($typbyte == 2 && int(@a) > 5) {           # rain
      #my $more = ($firstbyte&8) ? 0 : 1000;
      my $c = $hash->{corr1} ? $hash->{corr1} : 1;
      $rain = hex($a[5].$a[3].$a[4]) * $c;
      $val = "R: $rain";
      $devtype =  "Rain";
      $family = "WS7000";
      $NotifyType="R";
      $NotifyRain=$rain;
   }

    if($typbyte == 3 && int(@a) > 8) {           # wind
      my $hun = ($firstbyte&8) ? 100 : 0;
      $wnd = ($a[6].$a[3].".".$a[4])+$hun;
      my $dir  = ((hex($a[7])&3).$a[8].$a[5])+0;
      my $swing = (hex($a[7])&6) >> 2;
      $val = "W: $wnd D: $dir A: $swing";
      $devtype = "Wind";
      $family = "WS7000";
      $NotifyType="W WD WS";
      $NotifyWind=$wnd;
      $NotifyWindDir=$dir;
      $NotifyWindSwing=$swing;
    }

    if($typbyte == 4 && int(@a) > 10) {          # temp/hum/press
      $sgn = ($firstbyte&8) ? -1 : 1;
      $tmp = $std->($sgn * ($a[6].$a[3].".".$a[4]) + $hash->{corr1});
      $hum = ($a[7].$a[8].".".$a[5]) + $hash->{corr2};
      $prs = ($a[9].$a[10])+ 900 + $hash->{corr3};
      if($prs < 930) {
        $prs = $prs + 100;
      }
      $val = "T: $tmp  H: $hum  P: $prs";
      $devtype = "Indoor";
      $family = "WS7000";
      $NotifyType="T H P";
      $NotifyTemperature=$tmp;
      $NotifyHumidity=$hum;
      $NotifyPressure=$prs;
    }

    if($typbyte == 5 && int(@a) > 5) {           # brightness
      my $fakt = 1;
      my $rawfakt = ($a[6])+0;
      if($rawfakt == 1) { $fakt =   10; }
      if($rawfakt == 2) { $fakt =  100; }
      if($rawfakt == 3) { $fakt = 1000; }
     
      my $br = (hex($a[5].$a[4].$a[3])*$fakt)  + $hash->{corr1};
      $val = "B: $br";
      $devtype = "Brightness";
      $family = "WS7000";
      $NotifyType="B";
      $NotifyBrightness=$br;
    }

    if($typbyte == 6 && int(@a) > 0) {           # Pyro: wurde nie gebaut
      $devtype = "Pyro";
      $family = "WS7000";
    }

    if($typbyte == 7 && int(@a) > 8) {           # Temp/hum
      $sgn = ($firstbyte&8) ? -1 : 1;
      $tmp = $std->($sgn * ($a[6].$a[3].".".$a[4]) + $hash->{corr1});
      $hum = ($a[7].$a[8].".".$a[5]) + $hash->{corr2};
      $val = "T: $tmp  H: $hum";
      $devtype = "Temp/Hum";
      $family = "WS7000";
      $NotifyType="T H";
      $NotifyTemperature=$tmp;
      $NotifyHumidity=$hum;
    }
    
  } else {                                      # $firstbyte not 7

    if(@a == 9 && int(@a) > 8) {                 #  S300TH
      # Sanity check
      if (!($msg =~ /^K[0-9A-F]\d\d\d\d\d\d\d$/ )) {
        Log3 $name, 1,
            "Error: S300TH CUL_WS Cannot decode $msg (sanitycheck). Malformed";
        return "";
      }

      $sgn = ($firstbyte&8) ? -1 : 1;
      $tmp = $std->(sprintf("%0.1f",
                            $sgn * ($a[6].$a[3].".".$a[4]) + $hash->{corr1}));
      $hum = ($a[7].$a[8].".".$a[5]) + $hash->{corr2};
      $val = "T: $tmp  H: $hum";
      $devtype = "S300TH";
      $family = "WS300";
      $NotifyType="T H";
      $NotifyTemperature=$tmp;
      $NotifyHumidity=$hum;

    } elsif(@a == 15 && int(@a) > 14) {          # KS300/2
      my $c = $hash->{corr4} ? $hash->{corr4} : 255;
      $rain = sprintf("%0.1f", hex("$a[14]$a[11]$a[12]") * $c / 1000);
      $wnd  = sprintf("%0.1f", "$a[9]$a[10].$a[7]" + $hash->{corr3});
      $hum  = sprintf( "%02d", "$a[8]$a[5]" + $hash->{corr2});
      $tmp  = sprintf("%0.1f", ("$a[6]$a[3].$a[4]"+ $hash->{corr1}),
                             (($a[1] & 0xC) ? -1 : 1));
      my $ir = ((hex($a[1]) & 2)) ? "yes" : "no";

      $val = "T: $tmp  H: $hum  W: $wnd  R: $rain  IR: $ir";
      $devtype = "KS300/2";
      $family = "WS300";
      $NotifyType="T H W R IR";
      $NotifyTemperature=$tmp;
      $NotifyHumidity=$hum;
      $NotifyWind=$wnd;
      $NotifyRain=$rain;
      $NotifyIsRaining=$ir;

   } elsif(int(@a) > 8) {                       # WS7000 Temp/Hum sensors
      if(join("", @a[3..8]) =~ m/^\d*$/) {      # Forum 49125
        $sgn = ($firstbyte&8) ? -1 : 1;
        $tmp = $std->($sgn * ($a[6].$a[3].".".$a[4]) + $hash->{corr1});
        $hum = ($a[7].$a[8].".".$a[5]) + $hash->{corr2};
        $val = "T: $tmp  H: $hum";
        $devtype = "TH".$sfirstbyte;
        $family = "WS7000";
        $NotifyType="T H";
        $NotifyTemperature=$tmp;
        $NotifyHumidity=$hum;
      }
    }

  }

  if(!$val) {
    Log3 $name, 1, "CUL_WS Cannot decode $msg";
    return "";
  }
  Log3 $name, 4, "CUL_WS $devtype $name: $val";

  # Sanity checks
  if($NotifyTemperature && ReadingsVal($name, "temperature", undef)) {
    my $tval = ReadingsVal($name, "strangetemp",
                           ReadingsVal($name, "temperature", undef));
    my $diff = ($NotifyTemperature - $tval)+0;
    if($diff < -15.0 || $diff > 15.0) {
      Log3 $name, 2,
        "$name: Temp difference ($diff) too large: $val, skipping it";
      readingsSingleUpdate($hash, "strangetemp", $NotifyTemperature, 0);
      return "";
    }
  }
  delete $hash->{READINGS}{strangetemp} if($hash->{READINGS});

  if($NotifyPressure && ReadingsVal($name, "pressure", undef)) {
    my $tval = ReadingsVal($name, "strangepress",
                           ReadingsVal($name, "pressure", undef));
    my $diff = ($NotifyPressure - $tval)+0;
    if($diff < -10.0 || $diff > 10.0) {
      Log3 $name, 2,
        "$name: Pressure difference ($diff) too large: $val, skipping it";
      readingsSingleUpdate($hash, "strangepress", $NotifyPressure, 0);
      return "";
    }
  }
  delete $hash->{READINGS}{strangepress} if($hash->{READINGS});

  if(defined($hum) && ($hum < 0 || $hum > 100)) {
    Log3 $name, 1, "BOGUS: $name reading: $val, skipping it";
    return "";
  }

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "state", $val);

  my $i=1;
  my $j;
  my @Notifies=split(" ", $NotifyType);

  for($j=0; $j<int(@Notifies); $j++) {
    my $val = "";
         if($Notifies[$j] eq "T")  { $val = $NotifyTemperature;
    } elsif($Notifies[$j] eq "H")  { $val = $NotifyHumidity;
    } elsif($Notifies[$j] eq "R")  { $val = $NotifyRain;
    } elsif($Notifies[$j] eq "W")  { $val = $NotifyWind;
    } elsif($Notifies[$j] eq "WD") { $val = $NotifyWindDir;
    } elsif($Notifies[$j] eq "WS") { $val = $NotifyWindSwing;
    } elsif($Notifies[$j] eq "IR") { $val = $NotifyIsRaining;
    } elsif($Notifies[$j] eq "B")  { $val = $NotifyBrightness;
    } elsif($Notifies[$j] eq "P")  { $val = $NotifyPressure;
    }
    my $nm = $NotifyMappings{$Notifies[$j]};

    readingsBulkUpdate($hash, $nm, $val);
  }

  readingsBulkUpdate($hash, "DEVTYPE", $devtype, 0);
  readingsBulkUpdate($hash, "DEVFAMILY", $family, 0);
  readingsEndUpdate($hash, 1); # Notify is done by Dispatch

  return $name;
}

sub
CUL_WS_Attr(@)
{
  my @a = @_;

  # Make possible to use the same code for different logical devices when they
  # are received through different physical devices.
  return if($a[0] ne "set" || $a[2] ne "IODev");
  my $hash = $defs{$a[1]};
  my $iohash = $defs{$a[3]};
  my $cde = $hash->{CODE};
  delete($modules{CUL_WS}{defptr}{$cde});
  $modules{CUL_WS}{defptr}{$iohash->{NAME} . "." . $cde} = $hash;
  return undef;
}


1;

=pod
=item summary    devices communicating via the ELV WS protocol (S300TH, etc)
=item summary_DE Anbindung von ELV Ger&auml;ten mit dem WS Protokoll (S300TH, usw.)
=begin html

<a name="CUL_WS"></a>
<h3>CUL_WS</h3>
<ul>
  The CUL_WS module interprets S300 type of messages received by the CUL.
  <br><br>

  <a name="CUL_WSdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; CUL_WS &lt;code&gt; [corr1...corr4]</code> <br>
    <br>
    &lt;code&gt; is the code which must be set on the S300 device. Valid values
    are 1 through 8.<br>
    corr1..corr4 are up to 4 numerical correction factors, which will be added
    to the respective value to calibrate the device. Note: rain-values will be
    multiplied and not added to the correction factor.
  </ul>
  <br>

  <a name="CUL_WSset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="CUL_WSget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="CUL_WSattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#IODev">IODev</a>
      Note: by setting this attribute you can define different sets of 8
      devices in FHEM, each set belonging to a CUL. It is important, however,
      that a device is only received by the CUL defined, e.g. by using
      different Frquencies (433MHz vs 868MHz)
      </li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#model">model</a> (S300,KS300,ASH2200)</li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li>strangeTempDiff DIFFVAL<br>
        If set, the module will only accept temperature values when the
        difference between the reported temperature and the last recorded value
        is less than DIFFVAL.</li>
  </ul>
  <br>
</ul>

=end html

=begin html_DE

<a name="CUL_WS"></a>
<h3>CUL_WS</h3>
<ul>
  Das CUL_WS-Modul entschl&uuml;sselt die Nachrichten des Types S300, die von
  dem CUL empfangen wurden.
  <br><br>

  <a name="CUL_WSdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; CUL_WS &lt;code&gt; [corr1...corr4]</code> <br>
    <br>
        &lt;code&gt; ist der Code, der an dem S300 eingestellt werden muss.
        G&uuml;ltige Werte sind 1 bis 8 
    <br>
    corr1..corr4 entsprechen vier m&ouml;glichen Korrekturwerten, die den
    jeweiligen Werten hinzuaddiert werden, um die Ger&auml;te zu kalibrieren.
    Hinweis: Bei den Werten f&uuml;r Regenmengen werden die Korrekturwerte
    nicht hinzuaddiert, sondern als Faktor mit dem Regenwert multipliziert.
  </ul>
  <br>

  <a name="CUL_WSset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="CUL_WSget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="CUL_WSattr"></a>
  <b>Attribute</b>
  <ul>
    <li><a href="#IODev">IODev (!)</a>
      Achtung: mit diesem Attribut ist es m&ouml;glich mehrere 8-er Sets an
      S300-er in FHEM zu definieren. Wichtige Voraussetzung allerdings ist,
      dass nur das spezifizierte CUL das S300 empfangen kann, z.Bsp. durch
      Frequenztrennung (433MHz vs. 868MHz).
      </li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#model">model</a> (S300,KS300,ASH2200)</li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li>strangeTempDiff DIFFVAL<br>
        Falls gesetzt, werden nur solche Temperaturen akzeptiert, wo der
        Unterschied bei der gemeldeten Temperatur zum letzten Wert weniger als
        DIFFVAL ist. </li>
  </ul>
  <br>
</ul>
=end html_DE

=cut
