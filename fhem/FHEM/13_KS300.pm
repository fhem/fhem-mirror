##############################################
# $Id$
#
# modified: 2014-02-16 - betateilchen
#           - added new reading for windIndex (bft)
#           - changed to readingFnAttributes
#           - some minor code cleanups
#

package main;

use strict;
use warnings;

sub KS300_windIndex($);

#####################################
sub
KS300_Initialize($)
{
  my ($hash) = @_;

  # Message is like
  # 810d04f94027a00171212730000008
  # 81 0d 04 f9 4027a00171 212730000008

  $hash->{Match}     = "^810d04..4027a001";
  $hash->{DefFn}     = "KS300_Define";
  $hash->{UndefFn}   = "KS300_Undef";
  $hash->{ParseFn}   = "KS300_Parse";
  no warnings 'qw';
  my @attrList = qw(
    IODev
    do_not_notify:0,1
    ignore:0,1 
    model:ks300 
    rainadjustment:0,1
    strangeTempDiff
    showtime:0,1
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList)." ".$readingFnAttributes;
  $hash->{AutoCreate}=
    { "KS300.*" => {
         GPLOT => "temp4rain10:Temp/Rain,hum6wind8:Wind/Hum,",
         FILTER => "%NAME:T:.*" } };

}

#####################################
sub
KS300_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> KS300 <code> " .
          "[ml/raincounter] [wind-factor]" if(int(@a) < 3 || int(@a) > 5);
  $a[2] = lc($a[2]);
  return "Define $a[0]: wrong CODE format: specify a 4 digit hex value"
                if($a[2] !~ m/^[a-f0-9][a-f0-9][a-f0-9][a-f0-9]$/);

#  $hash->{CODE} = $a[2];
  my $rainunit = ((int(@a) > 3) ? $a[3] : 255);
  my $windunit = ((int(@a) > 4) ? $a[4] : 1.0);
  $hash->{CODE} = $a[2];
  $hash->{RAINUNIT} = $rainunit;
  $hash->{WINDUNIT} = $windunit;
  $modules{KS300}{defptr}{$a[2]} = $hash;
  AssignIoPort($hash);

  readingsSingleUpdate($hash, 'state', 'defined', 0);

  return undef;
}

#####################################
sub
KS300_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{KS300}{defptr}{$hash->{CODE}});
  return undef;
}

#####################################
# { Dispatch($defs{CUL},"810d04xx4027a00171240080009359", undef) }
sub
KS300_Parse($$)
{
  my ($hash,$msg) = @_;

  ###############################
  #          1          2
  #0123456789012345 67890123456789
  #
  #810d04f94027a001 71212730000008
  ###############################
  my @a = split("", $msg);

  ##########################
  # I've seldom (1 out of 700) seen messages of length 10 and 11 with correct
  # CRC, they seem to contain partial data (e.g. temp/wind/hum but not rain)
  # They are suppressed as of now.
  if(hex($a[3]) != 13) {
    Log3 $hash, 4, "Strange KS300 message received, won't decode ($msg)";
    return "";
  }

  if(int(keys %{ $modules{KS300}{defptr} })) {

    my @arr = keys(%{ $modules{KS300}{defptr} }); # No code is known yet
    my $dev = shift(@arr);
    my $def = $modules{KS300}{defptr}{$dev};
    my $haverain = 0;
    my $name= $def->{NAME};
    return "" if(IsIgnored($name));

    readingsBeginUpdate($def);
    my @v;
    my @txt = ( "rain_raw", "rain", "wind", "humidity", "temperature",
                "israining", "checksum", "type_raw", "unknown3", "windIndex");
    my @sfx = ( "(counter)", "(l/m2)", "(km/h)", "(%)", "(Celsius)",
        "(yes/no)", "","","","");
    my %repchanged = ("rain"=>1, "wind"=>1, "humidity"=>1, "temperature"=>1,
        "israining"=>1);

    # time
    my $tm = TimeNow();
    my $tsecs= time();  # number of non-leap seconds since January 1, 1970, UTC

    # preset current $rain_raw
    $v[0] = hex("$a[28]$a[27]$a[26]");
    my $rain_raw = $v[0];

    # get previous rain_raw
    my $rain_raw_prev = ReadingsVal($name, 'rain_raw', $rain_raw);
    ($rain_raw_prev, undef) = split(" ", $rain_raw_prev); # cut off "(counter)"

    my $rain_raw_adj = $rain_raw;       # unadjusted value as default
    my $rain_raw_adj_prev = ReadingsVal($name, 'rain_raw_adj', $rain_raw);

    if(AttrVal($name,"rainadjustment",0)) {

      # The rain values delivered by my KS300 randomly switch between two
      # different values. The offset between the two values follows no
      # identifiable principle. It is even unclear whether the problem is
      # caused by KS300 or by FHZ1300. ELV denies any problem with the KS300.
      # The problem is known to several people. For instance, see
      # http://www.ipsymcon.de/forum/showthread.php?t=3303&highlight=ks300+regen&page=3
      # The following code detects and automatically corrects these offsets.


      my $rain_raw_ofs_prev = ReadingsVal($name, 'rain_raw_ofs', 0);
      my $rain_raw_ofs = $rain_raw_ofs_prev;
      my $tsecs_prev = ReadingsVal($name, 'tsecs', 0);

      # detect error condition
      # delta is negative or delta is too large
      # see http://de.wikipedia.org/wiki/Niederschlagsintensit??t#Niederschlagsintensit.C3.A4t
      # during a thunderstorm in middle europe, 50l/m^2 rain may fall per hour
      # 50l/(m^2*h) correspond to 200 ticks/h
      # Since KS300 sends every 2,5 minutes, a maximum delta of 8 ticks would
      # be reasonable. The observed deltas are in most cases 1 or 2 orders
      # of magnitude larger.
      # The code also handles counter resets after battery replacement

      my $rain_raw_delta = $rain_raw - $rain_raw_prev;
      my $deltatsecs= ($tsecs - $tsecs_prev); # we have observed two datagrams at the same second
      $deltatsecs= 1 if($deltatsecs< 1); 
      my $thours_delta = $deltatsecs/3600.0; # in hours
      my $rain_raw_per_hour = $rain_raw_delta/$thours_delta;
      if(($rain_raw_delta<0) || ($rain_raw_per_hour> 200.0)) {
            $rain_raw_ofs = $rain_raw_ofs_prev-$rain_raw_delta;

            # If the switch in the tick count occurs simultaneously with an
            # increase due to rain, the tick is lost. We therefore assume that
            # offsets between -5 and 0 are indeed rain.

            if(($rain_raw_ofs>=-5) && ($rain_raw_ofs<0)) {
            $rain_raw_ofs= 0;
            }
            readingsBulkUpdate($def, 'rain_raw_ofs', $rain_raw_ofs, 0);
      }
      $rain_raw_adj = $rain_raw + $rain_raw_ofs;

    }

    readingsBulkUpdate($def, 'tsecs', $tsecs, 0);
    readingsBulkUpdate($def, 'rain_raw_adj', $rain_raw_adj, 0);

    # KS300 has a sensor which detects any drop of rain and immediately
    # sends out the israining message. The sensors consists of two parallel
    # strips of metal separated by a small gap. The rain bridges the gap
    # and closes the contact. If the KS300 pole is not perfectly vertical the
    # drop runs along only one side and the contact is not closed. To get the
    # israining information anyway, the respective flag is also set when the
    # a positive amount of rain is detected.

    $haverain = 1 if($rain_raw_adj != $rain_raw_adj_prev);

    $v[1] = sprintf("%0.1f", $rain_raw_adj * $def->{RAINUNIT} / 1000);
    $v[2] = sprintf("%0.1f", ("$a[25]$a[24].$a[23]"+(hex($a[17])&0x4?100:0)) *
                              $def->{WINDUNIT});
    $v[3] = "$a[22]$a[21]" + 0;
    $v[4] = "$a[20]$a[19].$a[18]" + 0;
    $v[4] = sprintf("%0.1f", $v[4]);
    $v[4] = -$v[4] if(hex($v[8]) & 8); # Negative temp
    $v[5] = ((hex($a[17]) & 0x2) || $haverain) ? "yes" : "no";
    $v[6] = $a[29];
    $v[7] = $a[16];
    $v[8] = $a[17];
    $v[9] = KS300_windIndex($v[2]);

    my $std = AttrVal($name, "strangeTempDiff", 0);
    if($std) {
      my $ov = ReadingsVal($name, 'temperature', 0);
      if($ov && abs($ov-$v[4]) > $std) {
        readingsBulkUpdate($def, 'strangeTemp', $v[4], 0);
        $v[4] = $ov;
      }
    }
    

    Log3 $def, 4, "KS300 $dev: $msg";

    my $max = int(@v);

    # For logging/summary
    my $val = "T: $v[4]  H: $v[3]  W: $v[2]  R: $v[1]  IR: $v[5]  Wi: $v[9]";
    Log3 $def, 4, "KS300 $dev: $val";
    readingsBulkUpdate($def,'state', $val);

    for(my $i = 0; $i < $max; $i++) {
      readingsBulkUpdate($def, $txt[$i], $v[$i],
                            defined($repchanged{$txt[$i]}));
    }


    ###################################
    # AVG computing

    if(!ReadingsVal($name, 'cum_day', undef)) {
      readingsBulkUpdate($def, 'cum_day', "$tm T: 0 H: 0 W: 0 R: $v[1]", 0);

    } else {

      my @cv = split(" ", ReadingsVal($name, 'cum_day',''));
      my @cd = split("[ :-]", ReadingsTimestamp($name, 'cum_day',''));

      my $csec = 3600*$cd[3] + 60*$cd[4] + $cd[5]; # Sec of last reading
      my @d = split("[ :-]", $tm);
      my $sec = 3600*$d[3] + 60*$d[4] + $d[5];     # Sec now

      my @sd = split("[ :-]", "$cv[0] $cv[1]");
      my $ssec = 3600*$sd[3] + 60*$sd[4] + $sd[5]; # Sec at start of day

      my $difft = $sec - $csec;
      $difft += 86400 if($d[2] != $cd[2]);         # Sec since last reading

      my $t = $cv[3] + $difft * $v[4];
      my $h = $cv[5] + $difft * $v[3];
      my $w = $cv[7] + $difft * $v[2];
      my $e = $cv[9];

      $val = "$cv[0] $cv[1] T: $t  H: $h  W: $w  R: $e";
      readingsBulkUpdate($def, 'cum_day', $val, 0);

      $difft = $sec - $ssec;
      $difft += 86400 if($d[2] != $sd[2]);       # Sec since last reading
      $difft = 1 if(!$difft);                    # Don't want illegal division.
      $t /= $difft; $h /= $difft; $w /= $difft; $e = $v[1] - $cv[9];

      $val = sprintf("T: %.1f  H: %d  W: %.1f  R: %.1f", $t, $h, $w, $e);
      readingsBulkUpdate($def, 'avg_day', $val, $d[2]!=$sd[2]);

      if($d[2] != $sd[2]) {                      # Day changed
        $val = "$tm T: 0 H: 0 W: 0 R: $v[1]";
        readingsBulkUpdate($def, 'cum_day', $val, 0);

        if(!ReadingsVal($name, 'cum_month', undef)) {
          $val = "1 ".ReadingsVal($name, 'avg_day','');
          readingsBulkUpdate($def, 'cum_month', $val, 0);

        } else {
          my @cmv = split(" ", ReadingsVal($name, 'cum_month',''));
          $t += $cmv[2]; $w += $cmv[4]; $h += $cmv[6];
          $cmv[0]++;
          $val = sprintf("%d T: %.1f  H: %d  W: %.1f  R: %.1f",
          $cmv[0], $t, $h, $w, $cmv[8]+$e);
          readingsBulkUpdate($def, 'cum_month', $val, 0);

          $val = sprintf("T: %.1f  H: %d  W: %.1f  R: %.1f",
                        $t/$cmv[0], $h/$cmv[0], $w/$cmv[0], $cmv[8]+$e);
          readingsBulkUpdate($def, 'avg_month', $val, $d[1]!=$sd[1]);
          if($d[1] != $sd[1]) {                  # Month changed, report it
            $val = "0 T: 0 H: 0 W: 0 R: 0";
            readingsBulkUpdate($def, 'cum_month', $val, 0);
          }
        }
      }
    }
    # AVG computing
    ###################################

    readingsEndUpdate($def,1);
    return $name;

  } else {

    Log3 $hash, 4, "KS300 detected: $msg";
    return "UNDEFINED KS300 KS300 1234";

  }
}

sub
KS300_windIndex($)
{
  #
  #  convert km/h to bft as described by
  #  http://www.meteotest.ch/wetterprognosen/prognosen_schweiz/windtabelle
  #
  my ($w) = @_;
  return  "0" if($w < 1);
  return  "1" if($w >=   1 && $w <    6);
  return  "2" if($w >=   6 && $w <   12);
  return  "3" if($w >=  12 && $w <   20);
  return  "4" if($w >=  20 && $w <   29);
  return  "5" if($w >=  29 && $w <   39);
  return  "6" if($w >=  39 && $w <   50);
  return  "7" if($w >=  50 && $w <   62);
  return  "8" if($w >=  62 && $w <   75);
  return  "9" if($w >=  75 && $w <   89);
  return "10" if($w >=  89 && $w <  103);
  return "11" if($w >= 103 && $w <= 117);
  return "12" if($w > 117);
}

1;

=pod
=item summary    module for the ELV KS300 weather station
=item summary_DE Anbindung der ELV KS300 Wetterstation
=begin html

<a name="KS300"></a>
<h3>KS300</h3>
<ul>
  Fhem can receive the KS300 or KS555 radio messages through the <a
  href="#FHZ">FHZ</a>, <a href="WS300">WS300</a> or <a href="#CUL">CUL</a>, so
  one of them must be defined first.<br> This module services messages received
  by the FHZ or CUL.<br> <br>

  <a name="KS300define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; KS300 &lt;housecode&gt; [ml/raincounter [wind-factor]]</code>
    <br><br>

    <code>&lt;housecode&gt;</code> is a four digit hex number, it must be
    specified foir historic reasons, and it is ignored.
    The ml/raincounter defaults to 255 ml, and it must be specified if you wish
    to set the wind factor, which defaults to 1.0.  <br>
    Examples:
    <ul>
      <code>define ks1 KS300 1234</code><br>
    </ul>
  </ul>
  <br>

  <a name="KS300set"></a>
  <b>Set </b>
  <ul>
    N/A
  </ul>
  <br>

  <a name="KS300get"></a>
  <b>Get</b>
  <ul>
    N/A
  </ul>
  <br>

  <a name="KS300attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#IODev">IODev</a></li>
    <li><a href="#eventMap">eventMap</a></li><br>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#model">model</a> (ks300)</li>
    <li>strangeTempDiff DIFFVAL<br>
        If set, the module will only accept temperature values when the
        difference between the reported temperature and the last recorded value
        is less than DIFFVAL.</li>
    <li>rainadjustment<br>
        If this attribute is set, fhem automatically considers rain counter
        resets after a battery change and random counter switches as
        experienced by some users.  Default is 0 (off).</li>
  </ul>
  <br>

</ul>

=end html


=begin html_DE

<a name="KS300"></a>
<h3>KS300</h3>
<ul>
  Fhem kann KS300 bzw. KS555 Funktelegramme mit einem <a href="#FHZ">FHZ</a>,
  einem <a href="WS300">WS300</a> oder einem <a href="#CUL">CUL</a> empfangen.
  Daher muss eines von diesen zuerst definiert sein.<br> Dieses Modul behandelt
  Nachrichten die mittels CUL oder FHZ empfangen werden.<br>
  <br>

  <a name="KS300define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; KS300 &lt;housecode&gt; [ml/raincounter [wind-factor]]</code>
    <br><br>

    <code>&lt;housecode&gt;</code> ist ein vierstelliger HEX-Wert, der aus
    historischen Gr&uuml;nden angegeben werden muss, es wird ignoriert.  Der
    ml/raincounter hat einen Default-Wert von 255ml, und muss angegeben sein
    wenn man den Wind-Faktor setzen will. Dieser hat einen Default-Wert von
    1.0.<br>
    Beispiele:
    <ul>
      <code>define ks1 KS300 1234</code><br>
    </ul>
  </ul>
  <br>

  <a name="KS300set"></a>
  <b>Set </b>
  <ul>
    N/A
  </ul>
  <br>

  <a name="KS300get"></a>
  <b>Get</b>
  <ul>
    N/A
  </ul>
  <br>

  <a name="KS300attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#IODev">IODev</a></li>
    <li><a href="#eventMap">eventMap</a></li><br>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#model">model</a> (ks300)</li>
    <li>rainadjustment<br>
        Wenn dieses Attribut gesetzt ist, Regenmesser resets werden automatisch
        ber&uuml;cksichtigt.  Resets treten beim Wechsel der Batterie und nach
        Beobachtung einiger Benutzer auch nach zuf&auml;lligen Schaltzyklen
        auf. Die Voreinstellung ist 0 (aus).</li>
    <li>strangeTempDiff DIFFVAL<br>
        Falls gesetzt, werden nur solche Temperaturen akzeptiert, wo der
        Unterschied bei der gemeldeten Temperatur zum letzten Wert weniger als
        DIFFVAL ist. </li>
  </ul>
  <br>

</ul>

=end html_DE

=cut
