
##############################################
# $Id$
#
# 98_Text2Speech.pm
#
# written by Tobias Faust 2013-10-23
# e-mail: tobias dot faust at gmx dot net
#
##############################################

##############################################
# EDITOR=nano
# visudo
# ALL     ALL = NOPASSWD: /usr/bin/mplayer
##############################################

package main;
use strict;
use warnings;
use Blocking;
use HttpUtils;
# use Data::Dumper;

use lib ('./FHEM/lib', './lib');

sub Text2Speech_OpenDev($);
sub Text2Speech_CloseDev($);


# SetParamName -> Anzahl Paramter
my %sets = (
  "tts"    => "1",
  "volume" => "1"
);

# path to mplayer
my $mplayer 		  = 'sudo /usr/bin/mplayer';
my $mplayerOpts       = '-nolirc -noconsolecontrols';
my $mplayerNoDebug    = '-really-quiet';
my $mplayerAudioOpts  = '-ao alsa:device=';

my %ttsHost         = ("Google"     => "translate.google.com",
                       "VoiceRSS"   => "api.voicerss.org"
                       );
my %ttsLang         = ("Google"     => "tl=",
                       "VoiceRSS"   => "hl="
                       );
my %ttsQuery        = ("Google"     => "q=",
                       "VoiceRSS"   => "src="
                       );
my %ttsPath         = ("Google"     => "/translate_tts?",
                       "VoiceRSS"   => "/?"
                       );
my %ttsAddon        = ("Google"     => "client=tw-ob&ie=UTF-8",
                       "VoiceRSS"   => ""
                       );
my %ttsAPIKey       = ("Google"     => "", # kein APIKey nötig
                       "VoiceRSS"   => "key=",
                       "maryTTS"    => ''
                       );
my %ttsUser         = ("Google"     => "", # kein Username nötig
                       "VoiceRSS"   => ""  # kein Username nötig
                       );
my %ttsSpeed        = ("Google"     => "",
                       "VoiceRSS"   => "r="
                       );
my %ttsQuality       = ("Google"     => "",
                       "VoiceRSS"   => "f="
                       );
my %ttsMaxChar      = ("Google"     => 200,
                       "VoiceRSS"   => 300,
                       "SVOX-pico"  => 1000,
                       "Amazon-Polly" => 3000,
                       "maryTTS"    => 3000
                       );
my %language        = ("Google"     =>  { "Deutsch"       => "de",
                                          "English-US"    => "en-us",
                                          "Schwedisch"    => "sv",
                                          "France"        => "fr",
                                          "Spain"         => "es",
                                          "Italian"       => "it",
                                          "Chinese"       => "cn",
                                          "Dutch"         => "nl"
                                         },
                       "VoiceRSS"   =>  { "Deutsch"       => "de-de",
                                          "English-US"    => "en-us",
                                          "Schwedisch"    => "sv-se",
                                          "France"        => "fr-fr",
                                          "Spain"         => "es-es",
                                          "Italian"       => "it-it",
                                          "Chinese"       => "zh-cn",
                                          "Dutch"         => "nl-nl"
                                         },
                        "SVOX-pico" =>  { "Deutsch"       => "de-DE",
                                          "English-US"    => "en-US",
                                          "France"        => "fr-FR",
                                          "Spain"         => "es-ES",
                                          "Italian"       => "it-IT"
                                         },
                        "Amazon-Polly"=> {"Deutsch"       => "Marlene",
                                          "English-US"    => "Joanna",
                                          "Schwedisch"    => "Astrid",
                                          "France"        => "Celine",
                                          "Spain"         => "Conchita",
                                          "Italian"       => "Carla",
                                          "Chinese"       => "Zhiyu",
                                          "Dutch"         => "Lotte"
                                         }
                      );

##########################
sub Text2Speech_Initialize($)
{
  my ($hash) = @_;
  $hash->{WriteFn}   = "Text2Speech_Write";
  $hash->{ReadyFn}   = "Text2Speech_Ready";
  $hash->{DefFn}     = "Text2Speech_Define";
  $hash->{SetFn}     = "Text2Speech_Set";
  $hash->{UndefFn}   = "Text2Speech_Undefine";
  $hash->{RenameFn}  = "Text2Speech_Rename";
  $hash->{AttrFn}    = "Text2Speech_Attr";
  $hash->{AttrList}  = "disable:0,1".
                       " TTS_Delimiter".
                       " TTS_Ressource:ESpeak,SVOX-pico,Amazon-Polly,maryTTS,". join(",", sort keys %ttsHost).
                       " TTS_APIKey".
                       " TTS_User".
                       " TTS_Quality:".
                                        "48khz_16bit_stereo,".
                                        "48khz_16bit_mono,".
                                        "48khz_8bit_stereo,".
                                        "48khz_8bit_mono".
                                        "44khz_16bit_stereo,".
                                        "44khz_16bit_mono,".
                                        "44khz_8bit_stereo,".
                                        "44khz_8bit_mono".
                                        "32khz_16bit_stereo,".
                                        "32khz_16bit_mono,".
                                        "32khz_8bit_stereo,".
                                        "32khz_8bit_mono".
                                        "24khz_16bit_stereo,".
                                        "24khz_16bit_mono,".
                                        "24khz_8bit_stereo,".
                                        "24khz_8bit_mono".
                                        "22khz_16bit_stereo,".
                                        "22khz_16bit_mono,".
                                        "22khz_8bit_stereo,".
                                        "22khz_8bit_mono".
                                        "16khz_16bit_stereo,".
                                        "16khz_16bit_mono,".
                                        "16khz_8bit_stereo,".
                                        "16khz_8bit_mono".
                                        "8khz_16bit_stereo,".
                                        "8khz_16bit_mono,".
                                        "8khz_8bit_stereo,".
                                        "8khz_8bit_mono".
                       " TTS_Speed:-10,-9,-8,-7,-6,-5,-4,-3,-2,-1,0,1,2,3,4,5,6,7,8,9,10".
                       " TTS_TimeOut".
                       " TTS_CacheFileDir".
                       " TTS_UseMP3Wrap:0,1".
                       " TTS_MplayerCall".
                       " TTS_SentenceAppendix".
                       " TTS_FileMapping".
                       " TTS_FileTemplateDir".
                       " TTS_VolumeAdjust".
                       " TTS_noStatisticsLog:1,0".
                       " TTS_Language:".join(",", sort keys %{$language{"Google"}}).
                       " TTS_Language_Custom".
                       " TTS_SpeakAsFastAsPossible:1,0".
                       " TTS_OutputFile".
                       " TTS_AWS_HomeDir".
                       " TTS_RemotePlayerCall".
                       " ".$readingFnAttributes;
}


##########################
# Define <tts> Text2Speech <alsa-device>
# Define <tts> Text2Speech host[:port][:SSL] [portpassword]
##########################
sub Text2Speech_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);

  #$a[0]: Name
  #$a[1]: Type/Alias -> Text2Speech
  #$a[2]: definition
  #$a[3]: optional: portpasswd
  if(int(@a) < 3) {
    my $msg =  "wrong syntax: define <name> Text2Speech <alsa-device>\n".
    			     "see at /etc/asound.conf\n".
               "or remote syntax: define <name> Text2Speech host[:port][:SSL] [portpassword]";
    Log3 $hash, 2, $msg;
    return $msg;
  }

  my $dev = $a[2];
  if($dev =~ m/^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}).*/ ) {
    # Ein RemoteDevice ist angegeben
    # zb: 192.168.10.24:7272:SSL mypasswd

    if($dev =~ m/^(.*):SSL$/) {
      $dev = $1;
      $hash->{SSL} = 1;
    }
    if($dev !~ m/^.+:[0-9]+$/) { # host:port
      $dev = "$dev:7072";
    }
    $hash->{Host} = $dev;
    $hash->{portpassword} = $a[3] if(@a == 4);

    $hash->{MODE} = "REMOTE";
  } elsif (lc($dev) eq "none") {
    # Ein DummyDevice, Serverdevice. Nur Generierung der mp3 TTS Dateien
    $hash->{MODE} = "SERVER";
    undef $hash->{ALSADEVICE};
  } else {
    # Ein Alsadevice ist angegeben
    # pruefen, ob Alsa-Device in /etc/asound.conf definiert ist
    $hash->{MODE} = "DIRECT";
    $hash->{ALSADEVICE} = $a[2];
  }

  BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));
  delete($hash->{helper}{RUNNING_PID});

  $hash->{STATE} = "Initialized";

  my $ret = Text2Speech_loadmodules($hash, "");
  if ($ret) {
    Log3 $hash->{NAME}, 3, $ret;
  }
  Text2Speech_AddExtension( $hash->{NAME}, \&Text2Speech_getLastMp3, "$hash->{TYPE}/$hash->{NAME}/last.mp3" );
  return undef;
}

##########################
# Überprüfung und Einladen der notwendigen Module
##########################
sub Text2Speech_loadmodules($$) {
  my ($hash, $TTS_Ressource) = @_;
  eval {
    require IO::File;
    IO::File->import;
    1;
  } or return "IO::File Module not installed. Please install.";

  eval {
    require Digest::MD5;
    Digest::MD5->import;
    1;
  } or return "Digest::MD5 Module not installed. Please install.";

  eval {
    require URI::Escape;
    URI::Escape->import;
    1;
  } or return "URI::Escape Module not installed. Please install.";

  eval {
    require Text::Iconv;
    Text::Iconv->import;
    1;
  } or return "Text::Iconv Module not installed. Please install.";

  eval {
    require Encode::Guess;
    Encode::Guess->import;
    1;
  } or return "Encode::Guess Module not installed. Please install.";

  eval {
    require MP3::Info;
    MP3::Info->import;
    1;
  } or return "MP3::Info Module not installed. Please install.";

  if ($TTS_Ressource eq "Amazon-Polly") {
    # Module werden nur benötigt mit der Polly Engine
    eval {
      require Paws::Polly;
      Paws::Polly->import;
      1;
    } or return "Paws Module not installed. Please install via 'sudo cpan Paws'.";

    eval {
      require File::HomeDir;
      File::HomeDir->import;
      1;
    } or return "File::HomeDir Module not installed. Please install";
  }

  return undef;
}

#####################################
sub Text2Speech_Undefine($$)
{
 my ($hash, $arg) = @_;

 RemoveInternalTimer($hash);
 BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));
 Text2Speech_RemoveExtension( "$hash->{TYPE}/$hash->{NAME}/last.mp3" );
 Text2Speech_CloseDev($hash);

 return undef;
}

sub Text2Speech_Rename(@) {
  my ( $newname, $oldname ) = @_;
  my $hash = $defs{$newname};
  my $type = $hash->{TYPE};
  Text2Speech_RemoveExtension( "$type/$oldname/last.mp3" );
  Text2Speech_AddExtension( $newname, \&Text2Speech_getLastMp3, "$type/$newname/last.mp3" );
}

sub Text2Speech_Attr(@) {
  my @a = @_;
  my $do = 0;
  my $hash = $defs{$a[1]};
  my $value = $a[3];

  my $TTS_FileTemplateDir = AttrVal($hash->{NAME}, "TTS_FileTemplateDir", "templates");
  my $TTS_CacheFileDir = AttrVal($hash->{NAME}, "TTS_CacheFileDir", "cache");
  my $TTS_FileMapping  = AttrVal($hash->{NAME}, "TTS_FileMapping", ""); # zb, silence:silence.mp3 ring:myringtone.mp3;
  my $TTS_AWS_HomeDir = AttrVal($hash->{NAME}, "TTS_AWS_HomeDir", "/home/fhem");

  if($a[2] eq "TTS_Delimiter" && $a[0] ne "del") {
    return "wrong Delimiter syntax: [+-]a[lfn]. Please see CommandRef for Notation. \n".
           "  Example 1: +an~\n".
           "  Example 2: +al." if($value !~ m/^([+-]a[lfn]){0,1}(.){1}$/i);
    return "This Attribute is only available in direct or server mode" if($hash->{MODE} !~ m/(DIRECT|SERVER)/ );

  } elsif ($a[0] eq "set" && $a[2] eq "TTS_Ressource" && $value eq "Amazon-Polly") {
    Log3 $hash->{NAME}, 4, $hash->{NAME}. ": Wechsele auf Amazon Polly, Lade Librarys nach.";
    my $ret = Text2Speech_loadmodules($hash, $a[2]);
    if ($ret) {return $ret;} # breche ab wenn Module fehlen

    if (! -e $TTS_AWS_HomeDir."/.aws/credentials"){
      return "No AWS credentials in FHEM Homedir found, please check ".$TTS_AWS_HomeDir."/.aws/credentials \n please refer https://metacpan.org/pod/Paws#AUTHENTICATION \n\n Please check Attribute 'TTS_AWS_HomeDir' too";
    }

  } elsif ($a[0] eq "set" && $a[2] eq "TTS_Ressource") {
    return "This Attribute is only available in direct or server mode" if($hash->{MODE} !~ m/(DIRECT|SERVER)/ );

  } elsif ($a[0] eq "set" && $a[2] eq "TTS_CacheFileDir") {
    return "This Attribute is only available in direct or server mode" if($hash->{MODE} !~ m/(DIRECT|SERVER)/ );

  } elsif ($a[0] eq "set" && $a[2] eq "TTS_SpeakAsFastAsPossible") {
    return "This Attribute is only available in direct or server mode" if($hash->{MODE} !~ m/(DIRECT|SERVER)/ );

  } elsif ($a[0] eq "set" && $a[2] eq "TTS_UseMP3Wrap") {
    return "This Attribute is only available in direct or server mode" if($hash->{MODE} !~ m/(DIRECT|SERVER)/ );
    return "Attribute TTS_UseMP3Wrap is required by Attribute TTS_SentenceAppendix! Please delete it first."
      if(($a[0] eq "del") && (AttrVal($hash->{NAME}, "TTS_SentenceAppendix", undef)));

  } elsif ($a[0] eq "set" && $a[2] eq "TTS_SentenceAppendix") {
    return "This Attribute is only available in direct or server mode" if($hash->{MODE} !~ m/(DIRECT|SERVER)/ );
    return "Attribute TTS_UseMP3Wrap is required!" unless(AttrVal($hash->{NAME}, "TTS_UseMP3Wrap", undef));

    my $file = $TTS_CacheFileDir ."/". $value;
    return "File <".$file."> does not exists in CacheFileDir" if(! -e $file);

  } elsif ($a[0] eq "set" && $a[2] eq "TTS_FileTemplateDir") {
    # Verzeichnis beginnt mit /, dann absoluter Pfad, sonst Unterpfad von $TTS_CacheFileDir
    my $newDir;
    if($value =~ m/^\/.*/) { $newDir = $value; } else { $newDir = $TTS_CacheFileDir ."/". $value;}
    unless(-e ($newDir) or mkdir ($newDir)) {
      #Verzeichnis anlegen gescheitert
      return "Could not create directory: <$value>";
    }

  } elsif ($a[0] eq "set" && $a[2] eq "TTS_TimeOut") {
    return "Only Numbers allowed" if ($value !~ m/[0-9]+/);

  } elsif ($a[0] eq "set" && $a[2] eq "TTS_AWS_HomeDir") {
  	return "Your HomeDir cannot be found." if (! -e $value)

  } elsif ($a[0] eq "set" && $a[2] eq "TTS_FileMapping") {
    #Bsp: silence:silence.mp3 pling:mypling,mp3
    #ueberpruefen, ob mp3 Template existiert
    my @FileTpl = split(" ", $TTS_FileMapping);
    my $newDir;
    for(my $j=0; $j<(@FileTpl); $j++) {
      my @FileTplPc = split(/:/, $FileTpl[$j]);
      if($TTS_FileTemplateDir =~ m/^\/.*/) { $newDir = $TTS_FileTemplateDir; } else { $newDir = $TTS_CacheFileDir ."/". $TTS_FileTemplateDir;}
      return "file does not exist: <".$newDir ."/". $FileTplPc[1] .">"
        unless (-e $newDir ."/". $FileTplPc[1]);
    }
  } elsif ($a[0] eq "set" && $a[2] eq "TTS_RemotePlayerCall") {
    if( $init_done ) {
      eval $value ;
      return "Text2Speach_Attr evaluating TTS_RemotePlayerCall error: $@" if ( $@ );
    
    }
  }

  if($a[0] eq "set" && $a[2] eq "disable") {
    $do = (!defined($a[3]) || $a[3]) ? 1 : 2;
  }
  $do = 2 if($a[0] eq "del" && (!$a[2] || $a[2] eq "disable"));
  return if(!$do);

  $hash->{STATE} = ($do == 1 ? "disabled" : "Initialized");

  return undef;
}

#####################################
sub Text2Speech_Ready($)
{
my ($hash) = @_;
return Text2speech_OpenDev($hash, 1);
}

########################
sub Text2Speech_OpenDev($) {
  my ($hash) = @_;
  my $dev = $hash->{Host};
  my $name = $hash->{NAME};

  Log3 $name, 4, "Text2Speech opening $name at $dev";

  my $conn;
  if($hash->{SSL}) {
    eval "use IO::Socket::SSL";
    Log3 $name, 1, $@ if($@);
    $conn = IO::Socket::SSL->new(PeerAddr => "$dev", MultiHomed => 1) if(!$@);
  } else {
    $conn = IO::Socket::INET->new(PeerAddr => $dev, MultiHomed => 1);
  }

  if(!$conn) {
    Log3($name, 3, $hash->{NAME}.": Can't connect to $dev: $!");
    $hash->{STATE} = "disconnected";
    return "";
  } else {
    $hash->{STATE} = "Initialized";
  }

  $hash->{TCPDev} = $conn;
  $hash->{FD} = $conn->fileno();

  Log3 $name, 4, "Text2Speech device opened ($name)";

  syswrite($hash->{TCPDev}, $hash->{portpassword} . "\n")
  if($hash->{portpassword});

  return undef;
}

########################
sub Text2Speech_CloseDev($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $dev = $hash->{Host};
  return if(!$dev);

  if($hash->{TCPDev}) {
    $hash->{TCPDev}->close();
    Log3 $hash, 4, "Text2speech Device closed ($name)";
  }

  delete($hash->{TCPDev});
  delete($hash->{FD});
}

########################
sub Text2Speech_Write($$) {
  my ($hash,$msg) = @_;
  my $name = $hash->{NAME};
  my $dev = $hash->{Host};

  #my $call = "set tts tts Das ist ein Test.";
  my $call = "set $name $msg";

  #Prüfen ob PRESENCE vorhanden und present
  my $isPresent = 0;
  my $hasPRESENCE = 0;
  my $devname="";
  if ($hash->{MODE}  eq "REMOTE") {
    foreach $devname (devspec2array("TYPE=PRESENCE")) {
      if (defined $defs{$devname}->{ADDRESS} && $dev) {
        if ($dev =~ $defs{$devname}->{ADDRESS}) {
          $hasPRESENCE = 1;
          $isPresent = 1 if (ReadingsVal($devname,"presence","unknown") eq "present");
          last;
        }
      }
    }
  }
  if ($hasPRESENCE) {
    Log3 $hash, 4, $name.": found PRESENCE Device $devname for host: $dev, it\'s state is: ".($isPresent ? "present" : "absent");
    Text2Speech_OpenDev($hash) if(!$hash->{TCPDev} && $isPresent);
    #lets try again
    Text2Speech_OpenDev($hash) if(!$hash->{TCPDev} && $isPresent);
  } else {
    Log3 $hash, 4, $name.": no proper PRESENCE Device for host: $dev";
    Text2Speech_OpenDev($hash) if(!$hash->{TCPDev});
    #lets try again
    Text2Speech_OpenDev($hash) if(!$hash->{TCPDev});
  }

  if($hash->{TCPDev}) {
    Log3 $hash, 4, $name.": Write remote message to $dev: $call";
    Log3 $hash, 3, $name.": Could not write remote message ($call) at " .$hash->{Host} if(!defined(syswrite($hash->{TCPDev}, "$call\n")));
    Text2Speech_CloseDev($hash);
  }

}


###########################################################################

sub Text2Speech_Set($@)
{
  my ($hash, @a) = @_;
  my $me = $hash->{NAME};
  my $TTS_APIKey    = AttrVal($hash->{NAME}, "TTS_APIKey", undef);
  my $TTS_User      = AttrVal($hash->{NAME}, "TTS_User", undef);
  my $TTS_Ressource = AttrVal($hash->{NAME}, "TTS_Ressource", "Google");
  my $TTS_TimeOut   = AttrVal($hash->{NAME}, "TTS_TimeOut", 60);


  return "no set argument specified" if(int(@a) < 2);

  return "No APIKey specified"                  if (!defined($TTS_APIKey) && ($ttsAPIKey{$TTS_Ressource} || length($ttsAPIKey{$TTS_Ressource})>0));
  return "No Username for TTS Access specified" if ( $TTS_Ressource ne 'maryTTS' && !defined($TTS_User) && ($ttsUser{$TTS_Ressource} || length($ttsUser{$TTS_Ressource})>0));

  my $ret = Text2Speech_loadmodules($hash, $TTS_Ressource);
  if ($ret) {
    # breche ab wenn Module fehlen
    Log3 $me, 3, $ret;
    return $ret;
  }

  my $cmd = shift(@a); # Dummy
     $cmd = shift(@a); # DevName

  if(!defined($sets{$cmd})) {
    my $r = "Unknown argument $cmd, choose one of ".join(" ",sort keys %sets);
    return $r;
  }

  if($cmd ne "tts") {
    return "$cmd needs $sets{$cmd} parameter(s)" if(@a-$sets{$cmd} != 0);
  } else {
    return "$cmd needs text parameter" if(@a-$sets{$cmd} < 0);
  }

  # Abbruch falls Disabled
  return "no set cmd on a disabled device !" if(IsDisabled($me));

  if($cmd eq "tts") {

    if($hash->{MODE} eq "DIRECT" || $hash->{MODE} eq "SERVER") {
      $hash->{VOLUME} = ReadingsNum($me, "volume", 100);
      readingsSingleUpdate($hash, "playing", "1", 1);
      Text2Speech_PrepareSpeech($hash, join(" ", @a));
      $hash->{helper}{RUNNING_PID} = BlockingCall("Text2Speech_DoIt", $hash, "Text2Speech_Done", $TTS_TimeOut, "Text2Speech_AbortFn", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
    } elsif ($hash->{MODE} eq "REMOTE") {
      Text2Speech_Write($hash, "tts " . join(" ", @a));
    } else {return undef;}
  } elsif($cmd eq "volume") {
    my $vol = join(" ", @a);
    return "volume level expects 0..100 percent" if($vol !~ m/^([0-9]{1,3})$/ or $vol > 100);

    if($hash->{MODE} eq "DIRECT") {
      $hash->{VOLUME} = $vol  if($vol <= 100);
      delete($hash->{VOLUME}) if($vol > 100);
    } elsif ($hash->{MODE} eq "REMOTE") {
      Text2Speech_Write($hash, "volume $vol");
    } else {return undef;}

    readingsSingleUpdate($hash, "volume", (($vol>100)?0:$vol), 1);
  }

  return undef;
}

#####################################
# Bereitet den gesamten String vor.
# Bei Nutzung Google wird dieser in ein Array
# zerlegt mit jeweils einer maximalen
# Stringlänge von 100Chars
#
# param1: $hash
# param2: string to speech
#
#####################################
###################################
# Angabe des Delimiters: zb.: +af~
#   + -> erzwinge das Trennen, auch wenn Textbaustein < 100Zeichen
#   - -> Trenne nur wenn Textbaustein > 100Zeichen
#  af -> add first -> füge den Delimiter am Satzanfang wieder hinzu
#  al -> add last  -> füge den Delimiter am Satzende wieder hinzu
#  an -> add nothing -> Delimiter nicht wieder hinzufügen
#   ~ -> der Delimiter
###################################
sub Text2Speech_PrepareSpeech($$) {
  my ($hash, $t) = @_;
  my $me = $hash->{NAME};

  my $TTS_Ressource = AttrVal($hash->{NAME}, "TTS_Ressource", "Google");
  my $TTS_Delimiter = AttrVal($hash->{NAME}, "TTS_Delimiter", undef);
  my $TTS_FileTpl   = AttrVal($hash->{NAME}, "TTS_FileMapping", ""); # zb, silence:silence.mp3 ring:myringtone.mp3; im Text: mein Klingelton :ring: ist laut.
  my $TTS_FileTemplateDir = AttrVal($hash->{NAME}, "TTS_FileTemplateDir", "templates");

  my $TTS_ForceSplit = 0;
  my $TTS_AddDelimiter;

  # Cleanup string
  $hash->{helper}{TTS_PlayerOptions} = "";
  while ($t =~ s/^ //isg) {};
  $t =~ s/^'(.*)'$/$1/;
  $t =~ s/^"(.*)"$/$1/;

  # Check text for command string
  if ($t =~ /^\[(.*?)\](.*?)$/) {
      ($hash->{helper}{TTS_PlayerOptions}, $t) = ($1, $2);
      while ($t =~ s/^ //isg) {};
  }

  if($TTS_Delimiter && $TTS_Delimiter =~ m/^[+-]a[lfn]/i) {
    $TTS_ForceSplit = 1 if(substr($TTS_Delimiter,0,1) eq "+");
    $TTS_ForceSplit = 0 if(substr($TTS_Delimiter,0,1) eq "-");

    $TTS_AddDelimiter = substr($TTS_Delimiter,1,2); # af, al oder an

    $TTS_Delimiter = substr($TTS_Delimiter,3);

  } elsif (!$TTS_Delimiter) { # Default wenn Attr nicht gesetzt
    $TTS_Delimiter = "(?<=[\\.!?])\\s*";
    $TTS_ForceSplit = 0;
    $TTS_AddDelimiter = "";
  }

  #-- we may have problems with umlaut characters
  # ersetze Sonderzeichen die Google nicht auflösen kann
  my $converter;

  # wandle per standard alles nach UTF8
  # check only ascii, utf8 and UTF-(16|32) with BOM, if not enough use function set_suspects
  # Encode::Guess->set_suspects(qw/euc-jp shiftjis 7bit-jis/); # for japanese codepages
  my $enc = guess_encoding($t);
  if ($enc->name ne "utf8") {
    Log3 $hash, 4, "$me: ermittelte CodePage: " .$enc->name. " , konvertiere nach UTF-8";
    $converter = Text::Iconv->new($enc->name, "utf-8");
    $t = $converter->convert($t);
  }

  #if($TTS_Ressource eq "Google") {
    # Google benötigt UTF-8
    #   $t =~ s/ä/ae/g;
    #   $t =~ s/ö/oe/g;
    #   $t =~ s/ü/ue/g;
    #   $t =~ s/Ä/Ae/g;
    #   $t =~ s/Ö/Oe/g;
    #   $t =~ s/Ü/Ue/g;
    #   $t =~ s/ß/ss/g;
  #}

  if ($TTS_Ressource eq "Amazon-Polly") {
    # Amazon benötigt ISO-8859-1 bei Nutzung Region eu-central-1
    $converter = Text::Iconv->new("utf-8", "iso-8859-1");
    $t = $converter->convert($t);
  }

  my @text;
  push(@text, $t);

  # hole alle Filetemplates
  my @FileTpl = split(" ", $TTS_FileTpl);
  my @FileTplPc;

  # bei Angabe direkter MP3-Files wird hier ein temporäres Template vergeben
  for(my $i=0; $i<(@text); $i++) {
    @FileTplPc = ($text[$i] =~ /:([\w-]+?\.(?:mp3|ogg|wav)):/g);
    for(my $j=0; $j<(@FileTplPc); $j++) {
      my $tpl = "FileTpl_#".$i."_".$j; #eindeutige Templatedefinition schaffen
      Log3 $hash, 4, "$me: Angabe einer direkten MP3-Datei gefunden:  $FileTplPc[$j] => $tpl";
      push(@FileTpl, $tpl.":".$FileTplPc[$j]); #zb: FileTpl_123645875_#0:/ring.mp3
      $text[$i] =~ s/$FileTplPc[$j]/$tpl/g; # Ersetze die DateiDefinition gegen ein Template
    }
  }

  #iteriere durch die Sprachbausteine und splitte den Text bei den Filetemplates auf
  for(my $i=0; $i<(@text); $i++) {
    my $cutter = '#!#'; #eindeutigen Cutter als Delimiter bei den Filetemplates vergeben
    @FileTplPc = ($text[$i] =~ /:([^:]+):/g);
    for(my $j=0; $j<(@FileTplPc); $j++) {
      $text[$i] =~ s/:$FileTplPc[$j]:/$cutter$FileTplPc[$j]$cutter/g;
    }
    @text = Text2Speech_SplitString(\@text, 0, $cutter, 1, "");
  }

  Log3 $hash, 4, "$me: MaxChar = $ttsMaxChar{$TTS_Ressource}, Delimiter = $TTS_Delimiter, ForceSplit = $TTS_ForceSplit, AddDelimiter = $TTS_AddDelimiter";

  @text = Text2Speech_SplitString(\@text, $ttsMaxChar{$TTS_Ressource}, $TTS_Delimiter, $TTS_ForceSplit, $TTS_AddDelimiter);
  @text = Text2Speech_SplitString(\@text, $ttsMaxChar{$TTS_Ressource}, "(?<=[.!?])\\s*", 0, "");
  @text = Text2Speech_SplitString(\@text, $ttsMaxChar{$TTS_Ressource}, ",", 0, "al");
  @text = Text2Speech_SplitString(\@text, $ttsMaxChar{$TTS_Ressource}, ";", 0, "al");
  @text = Text2Speech_SplitString(\@text, $ttsMaxChar{$TTS_Ressource}, "und", 0, "af");
  @text = Text2Speech_SplitString(\@text, $ttsMaxChar{$TTS_Ressource}, ":", 0, "al");
  @text = Text2Speech_SplitString(\@text, $ttsMaxChar{$TTS_Ressource}, "\\bund\\b", 0, "af");
  @text = Text2Speech_SplitString(\@text, $ttsMaxChar{$TTS_Ressource}, " ", 0, "");

  Log3 $hash, 4, "$me: Auflistung der Textbausteine nach Aufbereitung:";
  for(my $i=0; $i<(@text); $i++) {
    # entferne führende und abschließende Leerzeichen aus jedem Textbaustein
    $text[$i] =~ s/^\s+|\s+$//g;
    for(my $j=0; $j<(@FileTpl); $j++) {
      # ersetze die FileTemplates mit den echten MP3-Files
      @FileTplPc = split(/:/, $FileTpl[$j]);
      $text[$i] = $TTS_FileTemplateDir ."/". $FileTplPc[1] if($text[$i] eq $FileTplPc[0]);
    }
    Log3 $hash, 4, "$me: $i => ".$text[$i];
  }

  push( @{$hash->{helper}{Text2Speech}}, @text );
}

#####################################
# param1: array : Text 2 Speech
# param2: string: MaxChar
# param3: string: Delimiter
# param4: int   : 1 -> es wird am Delimiter gesplittet
#                 0 -> es wird nur gesplittet, wenn Stringlänge länger als MaxChar
# param5: string: Add Delimiter to String? [al|af|<empty>] (AddLast/AddFirst)
#
# Splittet die Texte aus $hash->{helper}->{Text2Speech} anhand des
# Delimiters, wenn die Stringlänge MaxChars übersteigt.
# Ist "AddDelimiter" angegeben, so wird der Delimiter an den
# String wieder angefügt
#####################################
sub Text2Speech_SplitString($$$$$){
  my @text          = @{shift()};
  my $MaxChar       = shift;
  my $Delimiter     = shift;
  my $ForceSplit    = shift;
  my $AddDelimiter  = shift;
  my @newText;

  for(my $i=0; $i<(@text); $i++) {
    if((length($text[$i]) <= $MaxChar) && (!$ForceSplit)) { #Google kann nur 100zeichen
      push(@newText, $text[$i]);
      next;
    }

    my @b;
    if($Delimiter =~/^ $/) {
      @b = split(' ', $text[$i]);
    }
    else {
      @b = split(/$Delimiter/, $text[$i]);
    }
    if((@b)>1) {
      # setze zu kleine Textbausteine wieder zusammen bis MaxChar erreicht ist
      if(length($Delimiter)==1) {
        for(my $k=0; $k<(@b); ) {
          if($k+1<(@b) && length($b[$k])+length($b[$k+1]) <= $MaxChar) {
            $b[$k] = join($Delimiter, $b[$k], $b[$k+1]);
            splice(@b, $k+1, 1);
          }
    	  else {
    	  	$k++;
    	  }
         }
      }
      for(my $j=0; $j<(@b); $j++) {
        (my $boundaryDelimiter = $Delimiter) =~ s/^\\b(.+)\\b$/$1/g;
         $b[$j] = $b[$j] . $boundaryDelimiter if($AddDelimiter eq "al"); # Am Satzende wieder hinzufügen.
         $b[$j+1] = $boundaryDelimiter . $b[$j+1] if(($AddDelimiter eq "af") && ($b[$j+1])); # Am Satzanfang des nächsten Satzes wieder hinzufügen.
         push(@newText, $b[$j]);
      }
    }
    elsif((@b)==1) {
           push(@newText, $text[$i]);
      }
  }
  return @newText;
}

#####################################
# param1: hash  : Hash
# param2: string: Datei
#
# Erstellt den Commandstring für den Systemaufruf
#####################################
sub Text2Speech_BuildMplayerCmdString($$) {
  my ($hash, $file) = @_;
  my $cmd;

  my $TTS_MplayerCall = AttrVal($hash->{NAME}, "TTS_MplayerCall", $mplayer);
  my $TTS_VolumeAdjust = AttrVal($hash->{NAME}, "TTS_VolumeAdjust", 110);
  my $verbose = AttrVal($hash->{NAME}, "verbose", 3);

  if($hash->{VOLUME}) { # per: set <name> volume <..>
    $mplayerOpts .= " -softvol -softvol-max ". $TTS_VolumeAdjust ." -volume " . $hash->{VOLUME};
  }

  my $AlsaDevice = $hash->{ALSADEVICE};
  if($AlsaDevice eq "default") {
    $AlsaDevice = "";
    $mplayerAudioOpts = "";
  }

  my $NoDebug = $mplayerNoDebug;
  $NoDebug = "" if($verbose >= 5);
  # anstatt  mplayer wird ein anderer Player verwendet
  if ($TTS_MplayerCall !~ m/mplayer/) {
    $TTS_MplayerCall =~ s/{device}/$AlsaDevice/g;
    $TTS_MplayerCall =~ s/{volume}/$hash->{VOLUME}/g;
    $TTS_MplayerCall =~ s/{volumeadjust}/$TTS_VolumeAdjust/g;
    $TTS_MplayerCall =~ s/{file}/$file/g;
    $TTS_MplayerCall =~ s/{options}/$hash->{helper}{TTS_PlayerOptions}/g;

    $cmd = $TTS_MplayerCall;
  } else {
    $cmd = $TTS_MplayerCall . " " . $mplayerAudioOpts . $AlsaDevice . " " .$NoDebug. " " . $mplayerOpts . " " . $file;
  }


  my $mp3Duration =  Text2Speech_CalcMP3Duration($hash, $file);
  BlockingInformParent("Text2Speech_readingsSingleUpdateByName", [$hash->{NAME}, "duration", "$mp3Duration"], 0);
  return $cmd;
}

#####################################
# Benutzt um Infos aus dem Blockingprozess
# in die Readings zu schreiben
#####################################
sub Text2Speech_readingsSingleUpdateByName($$$) {
  my ($devName, $readingName, $readingVal) = @_;
  my $hash = $defs{$devName};
  Log3 $hash, 5, $hash->{NAME}.": readingsSingleUpdateByName: Dev:$devName Reading:$readingName Val:$readingVal";
  readingsSingleUpdate($hash, $readingName, $readingVal, 1);
}

#####################################
# param1: string: MP3 Datei inkl. Pfad
#
# Ermittelt die Abspieldauer einer MP3 und gibt die Zeit in Sekunden zurück.
# Die Abspielzeit wird auf eine ganze Zahl gerundet
#####################################
sub Text2Speech_CalcMP3Duration($$) {
  my $time;
  my ($hash, $file) = @_;
  eval {
    my $tag = get_mp3info($file);
    if ($tag && defined($tag->{SECS})) {
	  $time = int($tag->{SECS}+0.5);
      Log3 $hash, 4, $hash->{NAME}.": $file hat eine Länge von $time Sekunden.";
    }
  };

  if ($@) {
    Log3 $hash, 2, $hash->{NAME}.": Bei der MP3-Längenermittlung ist ein Fehler aufgetreten: $@";
    return undef;
  }
  return $time;
}


#####################################
# param1: hash  : Hash
# param2: string: Dateiname
# param2: string: Text
#
# Holt den Text mithilfe der entsprechenden TTS_Ressource
#####################################
sub Text2Speech_Download($$$) {
  my ($hash, $file, $text) = @_;

  my $TTS_Ressource = AttrVal($hash->{NAME}, "TTS_Ressource", "Google");
  my $TTS_User      = AttrVal($hash->{NAME}, "TTS_User", "");
  my $TTS_APIKey    = AttrVal($hash->{NAME}, "TTS_APIKey", "");
  my $TTS_Language  = AttrVal($hash->{NAME}, "TTS_Language_Custom", $language{$TTS_Ressource}{AttrVal($hash->{NAME}, "TTS_Language", "Deutsch")});
  my $TTS_Quality   = AttrVal($hash->{NAME}, "TTS_Quality", "");
  my $TTS_Speed     = AttrVal($hash->{NAME}, "TTS_Speed", "");
  my $cmd;

  Log3 $hash->{NAME}, 4, $hash->{NAME}.": Verwende ".$TTS_Ressource." Resource zur TTS-Generierung";

  if($TTS_Ressource =~ m/(Google|VoiceRSS)/) {
    my $HttpResponse;
    my $HttpResponseErr;
    my $fh;

    my $url  = "https://" . $ttsHost{$TTS_Ressource} . $ttsPath{$TTS_Ressource};
       $url .= $ttsLang{$TTS_Ressource} . $TTS_Language;
       $url .= "&" . $ttsAddon{$TTS_Ressource}              if(length($ttsAddon{$TTS_Ressource})>0);
       $url .= "&" . $ttsUser{$TTS_Ressource} . $TTS_User     if(length($ttsUser{$TTS_Ressource})>0);
       $url .= "&" . $ttsAPIKey{$TTS_Ressource} . $TTS_APIKey if(length($ttsAPIKey{$TTS_Ressource})>0);
       $url .= "&" . $ttsQuality{$TTS_Ressource} . $TTS_Quality if(length($ttsQuality{$TTS_Ressource})>0);
       $url .= "&" . $ttsSpeed{$TTS_Ressource} . $TTS_Speed if(length($ttsSpeed{$TTS_Ressource})>0);
       $url .= "&" . $ttsQuery{$TTS_Ressource} . uri_escape($text);

    Log3 $hash->{NAME}, 4, $hash->{NAME}.": Hole URL: ". $url;
    #$HttpResponse = GetHttpFile($ttsHost, $ttsPath . $ttsLang . $TTS_Language . "&" . $ttsQuery . uri_escape($text));
    my $param = {
                      url         => $url,
                      timeout     => 5,
                      hash        => $hash,                                                                                  # Muss gesetzt werden, damit die Callback funktion wieder $hash hat
                      method      => "GET"                                                                                  # Lesen von Inhalten
                      #httpversion => "1.1",
                      #header      => "User-Agent:Mozilla/5.0 (Windows NT 6.2; WOW64) AppleWebKit/537.22 (KHTML, like Gecko) Chrome/25.0.1364.172 Safari/537.22m"              # Den Header gemäss abzufragender Daten ändern
                      #header     => "agent: Mozilla/1.22\r\nUser-Agent: Mozilla/1.22"
                  };
    ($HttpResponseErr, $HttpResponse) = HttpUtils_BlockingGet($param);

    if(length($HttpResponseErr) > 0) {
      Log3 $hash->{NAME}, 3, $hash->{NAME}.": Fehler beim abrufen der Daten von " .$TTS_Ressource. " Translator";
      Log3 $hash->{NAME}, 3, $hash->{NAME}.": " . $HttpResponseErr;
    }

    $fh = new IO::File ">$file";
    if(!defined($fh)) {
      Log3 $hash->{NAME}, 2, $hash->{NAME}.": mp3 Datei <$file> konnte nicht angelegt werden.";
      return undef;
    }

    $fh->print($HttpResponse);
    Log3 $hash->{NAME}, 4, $hash->{NAME}.": Schreibe mp3 in die Datei $file mit ".length($HttpResponse)." Bytes";
    close($fh);
  }
  elsif ($TTS_Ressource eq "ESpeak") {
    my $FileWav = $file . ".wav";

    $cmd = "sudo espeak -vde+f3 -k5 -s150 \"" . $text . "\" -w \"" . $FileWav . "\"";
    Log3 $hash, 4, $hash->{NAME}.":" .$cmd;
    system($cmd);

    $cmd = "lame \"" . $FileWav . "\" \"" . $file . "\"";
      Log3 $hash, 4, $hash->{NAME}.":" .$cmd;
      system($cmd);
    unlink $FileWav;
  }
  elsif ($TTS_Ressource eq "SVOX-pico") {
    my $FileWav = $file . ".wav";

    $cmd = "pico2wave --lang=" . $TTS_Language . " --wave=\"" . $FileWav . "\" \"" . $text . "\"";
      Log3 $hash, 4, $hash->{NAME}.":" .$cmd;
      system($cmd);

    $cmd = "lame \"" . $FileWav . "\" \"" . $file . "\"";
      Log3 $hash, 4, $hash->{NAME}.":" .$cmd;
      system($cmd);
    unlink $FileWav;
  }
  elsif ($TTS_Ressource eq "Amazon-Polly") {
    # with awscli
    # aws polly synthesize-speech --output-format mp3 --voice-id Marlene --text '%text%' abc.mp3
    #$cmd = "aws polly synthesize-speech --output-format json --speech-mark-types='[\"viseme\"]' --voice-id " . $TTS_Language . " --text '" . $text . "' " . $file;
    #Log3 $hash, 4, $hash->{NAME}.":" .$cmd;
    #system($cmd);
    my $fh;
    my $texttype = "text";

    $texttype = "ssml" if($text =~ m/^<speak>.*<\/speak>$/);
    Log3 $hash->{NAME}, 4, $hash->{NAME}.": Folgender TextTyp wurde für ".$TTS_Ressource." erkannt: ".$texttype;

    my $polly = Paws->service('Polly', region => 'eu-central-1');
    my $res = $polly->SynthesizeSpeech(
        VoiceId => $TTS_Language,
        Text => $text,
        TextType => $texttype,
        OutputFormat => 'mp3',
    );

    $fh = new IO::File ">$file";
    if(!defined($fh)) {
      Log3 $hash->{NAME}, 2, $hash->{NAME}.": mp3 Datei <$file> konnte nicht angelegt werden.";
      return undef;
    }

    $fh->print($res->AudioStream);
    Log3 $hash->{NAME}, 4, $hash->{NAME}.": Schreibe mp3 in die Datei $file mit ". $res->RequestCharacters ." Chars";
    close($fh);
  } elsif ( $TTS_Ressource eq 'maryTTS' ) {
    my $mTTSurl  = $TTS_User;
    my($unnamed, $named) = parseParams($mTTSurl);
    $named->{host}     //= shift @{$unnamed} // '127.0.0.1';
    $named->{port}     //= shift @{$unnamed} // '59125';
    $named->{lang}     //= shift @{$unnamed} // !$TTS_Language || $TTS_Language eq 'Deutsch' ? 'de_DE' : $TTS_Language;
    $named->{voice}    //= shift @{$unnamed} // 'de_DE/thorsten_low';
    $named->{endpoint} //= shift @{$unnamed} // 'process';

    $mTTSurl = "http://$named->{host}:$named->{port}/$named->{endpoint}?INPUT_TYPE=TEXT&OUTPUT_TYPE=AUDIO&AUDIO=WAVE_FILE&LOCALE=$named->{lang}&VOICE=$named->{voice}&INPUT_TEXT="; # https://github.com/marytts/marytts-txt2wav/blob/python/txt2wav.py#L21
    $mTTSurl .= uri_escape($text);

    Log3( $hash->{NAME}, 4, "$hash->{NAME}: Hole URL: $mTTSurl" );
    my $param = {     url         => $mTTSurl,
                      timeout     => 5,
                      hash        => $hash,     # Muss gesetzt werden, damit die Callback funktion wieder $hash hat
                      method      => 'GET'      # POST can be found in https://github.com/marytts/marytts-txt2wav/blob/python/txt2wav.py#L33
                  };
    my ($maryTTSResponseErr, $maryTTSResponse) = HttpUtils_BlockingGet($param);

    if(length($maryTTSResponseErr) > 0) {
      Log3($hash->{NAME}, 3, "$hash->{NAME}: Fehler beim Abrufen der Daten von $TTS_Ressource: $maryTTSResponseErr");
      return;
    }

    my $FileWav2 = $file . '.wav';
    my $fh2 = new IO::File ">$FileWav2";
    if ( !defined $FileWav2 ) {
      Log3($hash->{NAME}, 2, "$hash->{NAME}: wav Datei <$FileWav2> konnte nicht angelegt werden.");
      return;
    }

    $fh2->print($maryTTSResponse);
    Log3($hash->{NAME}, 4, "$hash->{NAME}: Schreibe wav in die Datei $FileWav2 mit ".length $maryTTSResponse . ' Bytes');
    close $fh2;
    $cmd = qq(lame "$FileWav2" "$file");
    Log3($hash, 4, "$hash->{NAME}:$cmd");
    system $cmd;
    return unlink $FileWav2;
  }
}

#####################################
sub Text2Speech_DoIt($) {
  my ($hash) = @_;

  my $TTS_CacheFileDir = AttrVal($hash->{NAME}, "TTS_CacheFileDir", "cache");
  my $TTS_Ressource = AttrVal($hash->{NAME}, "TTS_Ressource", "Google");
  my $TTS_Language = AttrVal($hash->{NAME}, "TTS_Language", "Deutsch");
  my $TTS_SentenceAppendix = AttrVal($hash->{NAME}, "TTS_SentenceAppendix", undef); #muss eine mp3-Datei sein, ohne Pfadangabe
  my $TTS_FileTemplateDir = AttrVal($hash->{NAME}, "TTS_FileTemplateDir", "templates");
  my $TTS_OutputFile = AttrVal($hash->{NAME}, "TTS_OutputFile", undef);

  my $myFileTemplateDir;
  if($TTS_FileTemplateDir =~ m/^\/.*/) { $myFileTemplateDir = $TTS_FileTemplateDir; } else { $myFileTemplateDir = $TTS_CacheFileDir ."/". $TTS_FileTemplateDir;}

  my $verbose = AttrVal($hash->{NAME}, "verbose", 3);
  my $cmd;

  Log3 $hash->{NAME}, 4, $hash->{NAME}.": Verwende TTS Spracheinstellung: ".$TTS_Language;

  my $filename;
  my $file;

  unless(-e $TTS_CacheFileDir or mkdir $TTS_CacheFileDir) {
    #Verzeichnis anlegen gescheitert
    Log3 $hash->{NAME}, 2, $hash->{NAME}.": Angegebenes Verzeichnis $TTS_CacheFileDir konnte erstmalig nicht angelegt werden.";
    return undef;
  }

  my @Mp3WrapFiles;
  my @Mp3WrapText;

  $TTS_SentenceAppendix = $myFileTemplateDir ."/". $TTS_SentenceAppendix if($TTS_SentenceAppendix);
  undef($TTS_SentenceAppendix) if($TTS_SentenceAppendix && (! -e $TTS_SentenceAppendix));

  #Abspielliste erstellen
  my $AnzahlDownloads = 0;
  foreach my $t (@{$hash->{helper}{Text2Speech}}) {
    if(-e $t) {
      # falls eine bestimmte mp3-Datei mit absolutem Pfad gespielt werden soll
      $filename = $t;
      $file = $filename;
      Log3 $hash->{NAME}, 4, $hash->{NAME}.": $filename als direkte MP3 Datei erkannt!";
    } elsif(-e $TTS_CacheFileDir."/".$t) {
      # falls eine bestimmte mp3-Datei mit relativem Pfad gespielt werden soll
      $filename = $t;
      $file = $TTS_CacheFileDir."/".$filename;
      Log3 $hash->{NAME}, 4, $hash->{NAME}.": $filename als direkte MP3 Datei erkannt!";
    } else {
      $filename = md5_hex($TTS_Ressource ."|". $t) . ".mp3";
      $file = $TTS_CacheFileDir."/".$filename;
      Log3 $hash->{NAME}, 4, $hash->{NAME}.": Textbaustein ist keine direkte MP3 Datei, ermittle MD5 CacheNamen: $filename";
    }

    if(-e $file) {
      push(@Mp3WrapFiles, $file);
      push(@Mp3WrapText, $t);
    } else {
      # es befindet sich noch Text zum Download in der Queue
      if (AttrVal($hash->{NAME}, "TTS_SpeakAsFastAsPossible", 0) == 0 || (AttrVal($hash->{NAME}, "TTS_SpeakAsFastAsPossible", 0) == 1 && $AnzahlDownloads == 0)) {
        # nur Download wenn kein TTS_SpeakAsFastAsPossible gesetzt ist oder der erste Download erfolgen soll
        Text2Speech_Download($hash, $file, $t);
        $AnzahlDownloads ++;
        if(-e $file) {
          push(@Mp3WrapFiles, $file);
          push(@Mp3WrapText, $t);
        }
      } else {
        last;
      }
    }

    last if (AttrVal($hash->{NAME}, "TTS_UseMP3Wrap", 0) == 0);
    # ohne mp3wrap darf nur ein Textbaustein verarbeitet werden
  }

  push(@Mp3WrapFiles, $TTS_SentenceAppendix) if($TTS_SentenceAppendix);

  if (AttrVal($hash->{NAME}, "TTS_UseMP3Wrap", 0) == 1) {
    # benutze das Tool MP3Wrap um bereits einzelne vorhandene Sprachdateien
    # zusammenzuführen. Ziel: sauberer Sprachfluss
    Log3 $hash->{NAME}, 4, $hash->{NAME}.": Bearbeite per MP3Wrap jetzt den Text: ". join(" ", @Mp3WrapText);

    my $Mp3WrapFile;
    my $Mp3WrapPrefix;
    $Mp3WrapPrefix = md5_hex(join("|", @Mp3WrapFiles));

    if ($TTS_OutputFile) {
        if ($TTS_OutputFile !~ m/^\//) {
            $TTS_OutputFile = $TTS_CacheFileDir ."/".$TTS_OutputFile;
        }
        Log3 $hash->{NAME}, 4, $hash->{NAME}.": Verwende fixen Dateinamen: $TTS_OutputFile";
        $Mp3WrapFile = $TTS_OutputFile;
        unlink($Mp3WrapFile);
    } else {
        $Mp3WrapFile = $TTS_CacheFileDir ."/". $Mp3WrapPrefix . ".mp3";
    }

    if (scalar(@Mp3WrapFiles) == 1) {
      # wenn nur eine Datei, dann wird diese genutzt
      $Mp3WrapFile = $Mp3WrapFiles[0];
    } elsif(! -e $Mp3WrapFile) {
      $cmd = "mp3wrap " .$Mp3WrapFile. " " .join(" ", @Mp3WrapFiles);
      $cmd .= " >/dev/null" if($verbose < 5);

      Log3 $hash->{NAME}, 4, $hash->{NAME}.": " .$cmd;
      system($cmd);

      my $t = substr($Mp3WrapFile, 0, length($Mp3WrapFile)-4)."_MP3WRAP.mp3";
      if(-e $t){

        Log3 $hash->{NAME}, 4, $hash->{NAME}.": Benenne Datei um von <".$t."> nach <".$Mp3WrapFile.">";
        rename($t, $Mp3WrapFile);
        #falls die Datei existiert den ID3V1 und ID3V2 Tag entfernen
        my $ret = eval{ remove_mp3tag( $Mp3WrapFile, 'ALL' ) };
        Log3 $hash, 1, $hash->{NAME}.": Fehle beim entfernen der ID3 Tags: $@" if ( $@ );
        Log3 $hash, 4, $hash->{NAME}.": Die ID3 Tags ( $ret Bytes ) von $Mp3WrapFile wurden geloescht." if ( $ret > 0 );
        Log3 $hash, 4, $hash->{NAME}.": Die ID3 Tags ( 0 Bytes ) von $Mp3WrapFile wurden geloescht." if ( $ret == -1 );
        Log3 $hash->{NAME}, 3, "MP3::Info Modul fehlt, konnte MP3 Tags nicht entfernen!" if ( !$ret );

      } else {

        Log3 $hash->{NAME}, 3, $hash->{NAME}.": MP3WRAP Fehler!, Datei wurde nicht generiert.";

      }
    }

    if ($TTS_OutputFile && $TTS_OutputFile ne $Mp3WrapFile) {
      Log3 $hash->{NAME}, 4, $hash->{NAME}.": Benenne Datei um von <".$Mp3WrapFile."> nach <".$TTS_OutputFile.">";
      rename($Mp3WrapFile, $TTS_OutputFile);
      $Mp3WrapFile = $TTS_OutputFile;
    }

    if ($hash->{MODE} ne "SERVER") {
    # im Server Mode, nicht die Datei abspielen
      if(-e $Mp3WrapFile) {
        $cmd = Text2Speech_BuildMplayerCmdString($hash, $Mp3WrapFile);
        $cmd .= " >/dev/null" if($verbose < 5);

        Log3 $hash->{NAME}, 4, $hash->{NAME}.": " .$cmd;
        system($cmd);
      } else {
        Log3 $hash->{NAME}, 2, $hash->{NAME}.": Mp3Wrap Datei konnte nicht gefunden werden.";
      }
    }

    return $hash->{NAME} ."|".
           ($TTS_SentenceAppendix ? scalar(@Mp3WrapFiles)-1: scalar(@Mp3WrapFiles)) ."|".
           $Mp3WrapFile;
  }


  Log3 $hash->{NAME}, 4, $hash->{NAME}.": Bearbeite jetzt den Text: ". $hash->{helper}{Text2Speech}[0];

  if(! -e $file) { # Datei existiert noch nicht im Cache
    Text2Speech_Download($hash, $file, $hash->{helper}{Text2Speech}[0]);
  } else {
    Log3 $hash->{NAME}, 4, $hash->{NAME}.": $file gefunden, kein Download";
  }

  if(-e $file && $hash->{MODE} ne "SERVER") {
    # Datei existiert jetzt
    # im Falls Server, nicht die Datei abspielen
    $cmd = Text2Speech_BuildMplayerCmdString($hash, $file);
    $cmd .= " >/dev/null" if($verbose < 5);

    Log3 $hash->{NAME}, 4, $hash->{NAME}.":" .$cmd;
    system($cmd);
  }
  return $hash->{NAME}. "|".
         "1" ."|".
         $file;
}

####################################################
# Rückgabe der Blockingfunktion
# param1: HashName
# param2: Anzahl der abgearbeiteten Textbausteine
# param3: Dateiname der abgespielt wurde
####################################################
sub Text2Speech_Done($) {
  my ($string) = @_;
  return unless(defined($string));

  my @a = split("\\|",$string);
  my $hash = $defs{shift(@a)};
  my $tts_done = shift(@a);
  my $filename = shift(@a);

  my $TTS_TimeOut   = AttrVal($hash->{NAME}, "TTS_TimeOut", 60);

  if($filename) {
    my @text;
    for(my $i=0; $i<$tts_done; $i++) {
      push(@text, $hash->{helper}{Text2Speech}[$i]);
    }
    Text2Speech_WriteStats($hash, 1, $filename, join(" ", @text)) if (AttrVal($hash->{NAME},"TTS_noStatisticsLog", "0")==0);

    readingsBeginUpdate( $hash );
      readingsBulkUpdate($hash, 'lastFilename', $filename );
      # Update der Dauer im Servermode
      readingsBulkUpdate( $hash, 'duration', Text2Speech_CalcMP3Duration( $hash, $filename ) ) if( $hash->{MODE} eq "SERVER" );
    readingsEndUpdate( $hash, 1 );

    # Aufruf eine eines Abspielgerätes wenn das Attibut gesetzt ist
    my $playercall = AttrVal( $hash->{NAME}, 'TTS_RemotePlayerCall', '' );
    eval $playercall if( $playercall );
    Log3( $hash, 1, $hash->{NAME}." TTS_RemotePlayerCall: eval error $@.") if( $@ );
  }

  delete($hash->{helper}{RUNNING_PID});
  splice(@{$hash->{helper}{Text2Speech}}, 0, $tts_done);

  # erneutes aufrufen da ev. weiterer Text in der Warteschlange steht
  if(@{$hash->{helper}{Text2Speech}} > 0) {
    # es wurde nur ein Teil abgearbeitet
    Log3($hash,4, $hash->{NAME}.": Es wurde nur ein Teil ausgegeben und weitere Teile folgen!");

    $hash->{helper}{RUNNING_PID} = BlockingCall("Text2Speech_DoIt", $hash, "Text2Speech_Done", $TTS_TimeOut, "Text2Speech_AbortFn", $hash);
  } else {

    # alles wurde bearbeitet
    Log3($hash,4, $hash->{NAME}.": Es wurden alle Teile ausgegeben und der Befehl ist abgearbeitet.");
    readingsSingleUpdate($hash, "playing", "0", 1);
  }
}

#####################################
sub Text2Speech_AbortFn($)     {
  my ($hash) = @_;

  delete($hash->{helper}{RUNNING_PID});
  Log3 $hash->{NAME}, 2, $hash->{NAME}.": BlockingCall for ".$hash->{NAME}." was aborted";
  readingsSingleUpdate($hash, "playing", "0", 1);
}

#####################################
# Hiermit werden Statistken per DbLogModul gesammelt
# Wichitg zur Entscheidung welche Dateien aus dem Cache lange
# nicht benutzt und somit gelöscht werden koennen.
#
# param1: hash
# param2: int:    0=indirekt (über mp3wrap); 1=direkt abgespielt
# param3: string: Datei
# param4: string: Text der als mp3 abgespielt wird
#####################################
sub Text2Speech_WriteStats($$$$){
  my($hash, $typ, $file, $text) = @_;
  my $DbLogDev;

  #suche ein DbLogDevice
  return undef unless($modules{"DbLog"} && $modules{"DbLog"}{"LOADED"});
  foreach my $key (keys(%defs)) {
    if($defs{$key}{TYPE} eq "DbLog") {
      $DbLogDev = $key;
      last;
    }
  }
  return undef if($defs{$DbLogDev}{STATE} !~ m/(active|connected)/); # muss active sein!
  return undef if(AttrVal($defs{$DbLogDev}, "DbLogType", "History") !~ /Current/); # muss die Tabelle Current nutzen

  my $logdevice = $hash->{NAME} ."|". $file;
  # den letzten Value von "Usage" ermitteln um dann die Statistik um 1 zu erhoehen.
  my @LastValue = DbLog_Get($defs{$DbLogDev}, "", "current", "array", "-", "-", $logdevice.":Usage");
  my $NewValue = 1;
  $NewValue = $LastValue[0]{value} + 1 if($LastValue[0]);

  my $cmd;
  if ($NewValue == 1) {
    $cmd = "INSERT INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (\
           '".TimeNow()."','".$logdevice."','".$hash->{TYPE}."','".$text."','Usage','".$NewValue."','')";
  } else {
    $cmd = "UPDATE current SET VALUE = '".$NewValue."', TIMESTAMP = '".TimeNow()."' WHERE DEVICE ='".$logdevice."'";
  }
  DbLog_ExecSQL($defs{$DbLogDev}, $cmd);
}

#########################
sub Text2Speech_readMp3(@) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam = "$type $name Text2Speech_readMp3:";
  my $filename = ReadingsVal( $name, 'lastFilename', '' );

  if ( $filename and -e $filename ) {

    if( open my $fh, '<:raw', $filename ) {

      my $content = '';

      while (1) {
        my $success = read $fh, $content, 1024, length( $content );
        if( not defined $success ) {
          close $fh;
          Log3 $name, 1, "$iam read file \"$filename\" error: $!.";
          return undef;
        }

        last if not $success;
      }

      close $fh;
      Log3 $name, 4, "$iam file \"$filename\" content length: ".length( $content );
      return \$content;

    } else {
      Log3 $name, 1, "$iam open file \"$filename\" error: $!.";
    }

  } else {
    Log3 $name, 2, "$iam file \"$filename\" does not exist.";
  }
  return undef;
}

#########################
sub Text2Speech_getLastMp3 {
  my ($request) = @_;

  if ( $request =~ /^\/(Text2Speech)\/(\w+)\/last.mp3/ ) {

    my $type   = $1;
    my $name   = $2;
    my $hash = $defs{$name};
    my $audioData = Text2Speech_readMp3( $hash );
    return ( "text/plain; charset=utf-8","${type} ${name}: No MP3 file for webhook $request" ) if ( !$audioData );
    my $audioMime = 'audio/mpeg';
    
    return ( $audioMime, $$audioData );
  }
  return ( "text/plain; charset=utf-8", "No Text2Speech device for webhook $request" );
}

#########################
sub Text2Speech_AddExtension(@) {
    my ( $name, $func, $link ) = @_;
    my $hash = $defs{$name};
    my $type = $hash->{TYPE};

    my $url = "/$link";
    Log3( $name, 2, "Registering $type $name for URL $url..." );
    $::data{FWEXT}{$url}{deviceName} = $name;
    $::data{FWEXT}{$url}{FUNC}       = $func;
    $::data{FWEXT}{$url}{LINK}       = $link;

    return;
}

#########################
sub Text2Speech_RemoveExtension(@) {
    my ($link) = @_;
    my $url  = "/$link";
    my $name = $::data{FWEXT}{$url}{deviceName};

    Log3( $name, 2, "Unregistering URL $url..." );
    delete $::data{FWEXT}{$url};

    return;
}


1;

=pod
=item helper
=item summary    A module that converts text to speech and also plays \
the result on a local or remote loudspeaker

=item summary_DE Modul, das Text in Sprache umwandelt und das Ergebnis \
über einen lokalen oder entfernten Lautsprecher wiedergibt
=begin html

<a id="Text2Speech"></a>
<h3>Text2Speech</h3>
<ul>
  <br>
  <a id="Text2Speech-define"></a>
  <h4>Define</h4>
  <ul>
    <b>Local : </b><code>define &lt;name&gt; Text2Speech &lt;alsadevice&gt;</code><br>
    <b>Remote: </b><code>define &lt;name&gt; Text2Speech &lt;host&gt;[:&lt;portnr&gt;][:SSL] [portpassword]</code>
    <b>Server: </b><code>define &lt;name&gt; Text2Speech none</code><br>
    <p>
    This module converts any text into speech with several possible providers. The Device can be defined as locally
    or remote instance.
    </p>

    <li>
      <b>Local Device</b><br>
      <ul>
        The output will be sent to any connected audio device. For example speakers connected per jack,
        network, WiFI or Bluetooth. Playback can be done using MPlayer or any other application.<br>
        <br>
        Mplayer installation under Debian/Ubuntu/Raspbian:<br>
        <code>apt-get install mplayer</code><br>
        The given alsa device has to be configured in <code>/etc/asound.conf</code>
        <p>
          <b>Special AlsaDevice: </b><i>default</i><br>
          The internal Mplayer command will be without any audio directive if the given alsa device is <i>default</i>.
          In this case Mplayer is using the standard audio device.
        </p>
        <p>
          <b>Example:</b><br>
          <code>define MyTTS Text2Speech hw=0.0</code><br>
          <code>define MyTTS Text2Speech default</code>
        </p>
      </ul>
    </li>

    <li>
      <b>Remote Device</b><br>
      <ul>
        This module can be configured as remote-device for client-server environments. The Client has to be configured
        as local device.<br>
        Notice: the Name of the locally instance has to be the same!
        <ul>
          <li>Host: setting up IP-adress</li>
          <li>PortNr: setting up TelnetPort of FHEM; default: 7072</li>
          <li>SSL: setting up if connect over SSL; default: no SSL</li>
          <li>PortPassword: setting up the configured target telnet passwort</li>
        </ul>
        <p>
          <b>Example:</b><br>
          <code>define MyTTS Text2Speech 192.168.178.10:7072 fhempasswd</code>
          <code>define MyTTS Text2Speech 192.168.178.10</code>
        </p>
      If a PRESENCE Device is avilable for the host IP-address, than this will be used to detect the reachability instead of the blocking  internal method.
      </ul>
    </li>

    <li>
      <b>Server Device</b>
      <ul>
        In case of an usage as a server, only the mp3 file will be generated and displayed as lastFilename reading. It makes no sense to use the attribute <i>TTS_speakAsFastAsPossible</i> here.
        Its recommend, to use the attribute <i>TTS_useMP3Wrap</i>. Otherwise only the last audiobrick will be shown in reading <i>lastFilename</i>.
      </ul>
      <p>
          <b>Example:</b><br>
          <code>define MyTTS Text2Speech none</code>
        </p>
    </li>

  </ul>
</ul>

<a id="Text2Speech-set"></a>
<h4>Set</h4>
<ul>
  <a id="Text2Speech-set-tts"></a><li><b>tts</b>:<br>
    Definition of text for voice output. To output mp3 files directly, they must be specified with
    leading and closing colons. Therefore, the text itself must not contain any double punctuation.
    The mp3 files must be stored in the <i>TTS_FileTemplateDir</i> directory.
    SSML can be used for the Amazon Polly language engine. See examples.
  </li>
  <a id="Text2Speech-set-volume"></a><li><b>volume</b>:<br>
    Setting up the volume audio response.<br>
    Notice: Only available in locally instances!
  </li>
</ul><br>

<a id="Text2Speech-get"></a>
<h4>Get</h4>
<ul>N/A</ul><br>

<a id="Text2Speech-attr"></a>
<h4>Attributes</h4>
<ul>
  <a id="Text2Speech-attr-TTS_Delimiter"></a><li>TTS_Delimiter<br>
    Optional: By using the Google engine, its not possible to convert more than 100 characters in a single audio brick.
    With a delimiter the audio brick will be split at this character. A delimiter must be a single character!<br>
    By default, each audio brick will be split at sentence end. Is a single sentence longer than 100 characters,
    the sentence will be split additionally at comma, semicolon and the word <i>and</i>.<br>
    Notice: Only available in locally instances with Google engine!
  </li>

  <a id="Text2Speech-attr-TTS_Ressource"></a><li>TTS_Ressource<br>
    Optional: Selection of the Translator Engine<br>
    Notice: Only available in locally instances!
    <ul>
      <li>Google<br>
        Google Engine. Prerequisite: Active Internet connection<br>
        This engine is recommended for its quality and is used by default.
      </li>
      <li>VoiceRSS<br>
        VoiceRSS Engine. Prerequisite: Active Internet connection<br>
        Free of charge up to 350 requests per day. If you need more, you have to pay.
        This engine is also recommended due to its quality. To use this engine, you need an APIKey (see TTS_APIKey)
      </li>
      <li>ESpeak<br>
        eSpeak Engine. Prerequisite: Installation of Espeak and lame<br>
        eSpeak is an open source software speech synthesizer for English and other languages.
      </li>
      <li>SVOX-pico<br>
        SVOX-Pico TTS-Engine (from the AOSP). Prerequisite: Installation of SVOX-Pico and lame<br>
        <code>sudo apt-get install libttspico-utils lame</code><br><br>
        On ARM/Raspbian the package <code>libttspico-utils</code>,<br>
        so you may have to compile it yourself or use the precompiled package from <a target="_blank" href"http://www.robotnet.de/2014/03/20/sprich-freund-und-tritt-ein-sprachausgabe-fur-den-rasberry-pi/">this guide</a>, in short:<br>
        <code>sudo apt-get install libpopt-dev lame</code><br>
        <code>cd /tmp</code><br>
        <code>wget http://www.dr-bischoff.de/raspi/pico2wave.deb</code><br>
        <code>sudo dpkg --install pico2wave.deb</code>
      </li>
      <li>Amazon-Polly<br>
       Amazon Polly Engine. Prerequisite: Active Internet connection, Perl package Paws<br>
       Amazon service that turns text into lifelike speech. An AWS Access and Polly Aws User is required.<br>
       <code>cpan paws</code><br>
       The credentials to your AWS Polly are expected at ~/.aws/credentials<br>
       <code>[default]
         aws_secret_access_key = xxxxxxxxxxxxxxxxxxxxxx
         aws_access_key_id = xxxxxxxxxxxxxxx
       </code>
      </li>
      <li>maryTTS<br>
        <a target="_blank" href"https://github.com/marytts/marytts">maryTTS</a> or <a target="_blank" href"https://github.com/MycroftAI/mimic3">Mimic 3</a> Engine. Prerequisite: Installation of respective server and lame, appropriate settings in <a href="#Text2Speech-attr-TTS_User">TTS_User</a> attribute (if other than default settings shall be applied).<br>
        Both are open source software speech synthesizers for English and other languages.
      </li>
    </ul>
  </li>

  <a id="Text2Speech-attr-TTS_Language"></a><li>TTS_Language<br>
    Selection of different languages
  </li>

  <a id="Text2Speech-attr-TTS_Language_Custom"></a><li>TTS_Language_Custom<br>
    If you want another engine and speech of default languages, you can insert this here.<br>
    The definition depends on the used engine. This attribute overrides an TTS_Language attribute.<br>
    Please refer to the specific API reference.
  </li>

  <a id="Text2Speech-attr-TTS_APIKey"></a><li>TTS_APIKey<br>
    An APIKey is needed if you want to use VoiceRSS. You have to register at the following page:<br>
    http://www.voicerss.org/registration.aspx
  </li>

  <a id="Text2Speech-attr-TTS_User"></a><li>TTS_User<br>
    Actual only used for maryTTS (and Mimic 3). Needed in case if a TTS Engine needs a username and an APIKey for a request. <br>
    <p>(Full) example for maryTTS (values are defaults and may be left out):</p>
        <p><code>attr t2s TTS_User host=127.0.0.1 port=59125 lang=de_DE voice=de_DE/thorsten_low</code></p>
  </li>

  <a id="Text2Speech-attr-TTS_CacheFileDir"></a><li>TTS_CacheFileDir<br>
    Optional: The downloaded Google audio bricks are saved in this folder.
    No automatic delete/cleanup available.<br>
    Default: <i>cache/</i><br>
    Notice: Available on local instances only!
  </li>

  <a id="Text2Speech-attr-TTS_UseMP3Wrap"></a><li>TTS_UseMP3Wrap<br>
    For best voice output, it is recommended that the individual downloads are combined into a single file.
    Each downloaded audio bricks are concatinated to a single audio file to play with Mplayer.<br>
    Installtion of the mp3wrap package is required.<br>
    <code>apt-get install mp3wrap</code><br>
    Notice: Available on local instances only!
  </li>

  <a id="Text2Speech-attr-TTS_MplayerCall"></a><li>TTS_MplayerCall<br>
    Optional: Definition of the system call to Mplayer or a different tool.<br>
    If a tool other than Mplayer is used, the following templates apply:<br>
    <ul>
        <li>{device}</li>
        <li>{volume}</li>
        <li>{volumeadjust}</li>
        <li>{file}</li>
        <li>{options}</li>
    </ul>
    {options} are provided inside the text in parentheses during the set command.
    Used for example to set special parameters for each call separately<br>
    Example: <code>set myTTS tts [192.168.0.1:7000] This is my text</code><br><br>

    Examples:<br>
    <code>attr myTTS TTS_MplayerCall sudo /usr/bin/mplayer</code><br>
    <code>attr myTTS TTS_MplayerCall AUDIODEV={device} play -q -v {volume} {file}</code><br>
    <code>attr myTTS TTS_MplayerCall player {file} {options}</code><br>

  </li>

  <a id="Text2Speech-attr-TTS_SentenceAppendix"></a><li>TTS_SentenceAppendix<br>
    Optional: Definition of one mp3-file to append each time of audio response.<br>
    Mp3Wrap is required. The audio chunks must be downloaded to the CacheFileDir beforehand.
    Example: <code>silence.mp3</code>
  </li>

  <a id="Text2Speech-attr-TTS_FileMapping"></a><li>TTS_FileMapping<br>
    Definition of mp3files with a custom template definition. Separated by space.
    All template definitions can be used in audiobricks by <i>tts</i> command.
    The definition must begin and end with a colon.
    The mp3files must be saved in <i>TTS_FIleTemplateDir</i>.<br>
    <code>attr myTTS TTS_FileMapping ring:ringtone.mp3 beep:MyBeep.mp3</code><br>
    <code>set MyTTS tts Attention: This is my ringtone :ring: Its loud?</code>
  </li>

  <a id="Text2Speech-attr-TTS_FileTemplateDir"></a><li>TTS_FileTemplateDir<br>
    Directory to save all mp3-files are defined in <i>TTS_FileMapping</i> und <i>TTS_SentenceAppendix</i><br>
    Optional, Default: <code>cache/templates</code>
  </li>

  <a id="Text2Speech-attr-TTS_VolumeAdjust"></a><li>TTS_VolumeAdjust<br>
    Basic volume increase<br>
    Default: 110<br>
    <code>attr myTTS TTS_VolumeAdjust 400</code>
  </li>

  <a id="Text2Speech-attr-TTS_noStatisticsLog"></a><li>TTS_noStatisticsLog<br>
    If set to <b>1</b>, it prevents logging statistics to DbLog Devices, default is <b>0</b><br>
    Note: This logging is important to be able to delete cache files that have not been used for a longer period of time.
    If you disable this, you will have to clean your cache directory manually.
  </li>

  <a id="Text2Speech-attr-TTS_speakAsFastAsPossible"></a><li>TTS_speakAsFastAsPossible<br>
      Trying to get a speech as fast as possible. In case of not present audio bricks, you can
      hear a short break as the audio brick will be downloaded at this time.
      In case of a presentation of all audio bricks at local cache, this attribute has no impact.<br>
      Attribute is only valid on local or server instances.
  </li>

  <a id="Text2Speech-attr-TTS_OutputFile"></a><li>TTS_OutputFile<br>
      Definition of a fixed file name as mp3 output. The attribute is only relevant in conjunction with TTS_UseMP3Wrap.
      If a file name is specified, then TTS_CacheFileDir is also taken into account.<br>
      <code>attr myTTS TTS_OutputFile output.mp3</code><br>
      <code>attr myTTS TTS_OutputFile /media/miniDLNA/output.mp3</code><br>
  </li>

  <a id="Text2Speech-attr-TTS_RemotePlayerCall"></a><li>TTS_RemotePlayerCall<br>
      The Text2Speech devices provide a URL to the last generated mp3 file:
      <code>&lt;protocol&gt;://&lt;fhem server ip or name&gt;:&lt;fhem port&gt;/fhem/Text2Speech/&lt;device name&gt;/last.mp3.</code><br>
      If this attibute contains a remote player call, it will be executed after the last mp3 file is generated.<br>
      <code>attr &lt;device name&gt; TTS_RemotePlayerCall GetFileFromURL('&lt;protocol&gt;://&lt;remote player name or ip&gt;:&lt;remote player port&gt;/?cmd=playSound&url=&lt;protocol&gt;://&lt;fhem server name orip&gt;:&lt;fhem port&gt;/fhem/Text2Speech/&lt;device name&gt;/last.mp3&loop=false&password=&lt;password&gt;')</code><br>
  </li>

  <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>

  <li><a href="#disable">disable</a><br>
    If this attribute is activated, the sound output will be disabled.<br>
    Possible values: 0 => not disabled , 1 => disabled<br>
    Default Value is 0 (not disabled)<br><br>
  </li>

   <li><a href="#verbose">verbose</a><br>
    <b>4:</b> each step will be logged<br>
    <b>5:</b> Additionally the individual debug information from Mplayer and mp3wrap will be logged
  </li>

</ul><br>

<a id="Text2Speech-examples"></a>
<h4>Examples</h4>
<ul>
  <code>define TTS_EG_WZ Text2Speech hw=/dev/snd/controlC3</code><br>
  <code>attr TTS_EG_WZ TTS_Language English</code><br>
  <code>attr TTS_EG_WZ TTS_Ressource Amazon-Polly</code><br>
  <code>attr TTS_EG_WZ TTS_UseMP3Wrap 1</code><br><br>
  <code>set MyTTS tts &lt;speak&gt;Mary had a little lamb.&lt;/speak&gt;</code>
  <br>
  <code>define MyTTS Text2Speech hw=0.0</code><br>
  <code>set MyTTS tts The alarm system is ready.</code><br>
  <code>set MyTTS tts :beep.mp3:</code><br>
  <code>set MyTTS tts :mytemplates/alarm.mp3:The alarm system is ready.:ring.mp3:</code>
  <br>
  Example of MaryTTS and using SSML: <br>
  <code>
    define T2S Text2Speech default
    attr T2S TTS_MplayerCall /usr/bin/mplayer
    attr T2S TTS_Ressource maryTTS
    attr T2S TTS_User host=192.168.100.1 port=59125 lang=de_DE voice=de_DE/thorsten_low ssml=1
    set T2S tts '&lt;voice name="de_DE/m-ailabs_low#rebecca_braunert_plunkett"&gt;Das ist ein Test in deutsch &lt;/voice&gt;&lt;voice name="en_US/vctk_low#p236"&gt;and this is an test in english.&lt;/voice&gt;'
  </code>
</ul>

=end html
=begin html_DE

<a id="Text2Speech"></a>
<h3>Text2Speech</h3>
<ul>
  <br>
  <a id="Text2Speech-define"></a>
  <h4>Define</h4>
    <ul>
    <b>Local : </b><code>define &lt;name&gt; Text2Speech &lt;alsadevice&gt;</code><br>
    <b>Remote: </b><code>define &lt;name&gt; Text2Speech &lt;host&gt;[:&lt;portnr&gt;][:SSL] [portpassword]</code>
    <b>Server : </b><code>define &lt;name&gt; Text2Speech none</code><br>
    <p>
    Das Modul wandelt Text mittels verschiedener Provider/Ressourcen in Sprache um. Dabei kann das Device als
    Remote, Lokales Device oder als Server konfiguriert werden.
    </p>

    <li>
      <b>Local Device</b><br>
      <ul>
        Die Ausgabe wird an jedes angeschlossene Audiogerät gesendet. Zum Beispiel an einen lokalen Lautsprecher oder an
        entfernte Geräte via Netzwerk, WiFI oder Bluetooth. Die Wiedergabe kann über MPlayer oder jede andere
        Anwendung erfolgen.<br>
        <br>
        Mplayer-Installation unter Debian/Ubuntu/Raspbian:<br>
        <code>apt-get install mplayer</code><br>
        Das angegebene Alsa-Device ist in der <code>/etc/asound.conf</code> zu konfigurieren.
        <p>
          <b>Special AlsaDevice: </b><i>default</i><br>
          Ist als Alsa-Device <i>default</i> angegeben, so wird Mplayer ohne eine Audiodevice-Angabe aufgerufen.
          Dementsprechend verwendet Mplayer dann das Standard-Audio Ausgabedevice.
        </p>
        <p>
          <b>Beispiel:</b><br>
          <code>define MyTTS Text2Speech hw=0.0</code><br>
          <code>define MyTTS Text2Speech default</code>
        </p>
      </ul>
    </li>

    <li>
      <b>Remote Device</b><br>
      <ul>
        Das Modul ist Client-Server f&auml;as bedeutet, das auf der Haupt-FHEM Installation eine Text2Speech-Instanz
        als Remote definiert wird. Auf dem Client wird Text2Speech als Local definiert. Die Sprachausgabe erfolgt auf
        der lokalen Instanz.<br>
        Zu beachten ist, dass die Text2Speech Instanz (Definition als Local-Device) auf dem Zieldevice identisch benannt ist.
        <ul>
          <li>Host: Angabe der IP-Adresse</li>
          <li>PortNr: Angabe des Telnet-Ports von FHEM; default: 7072</li>
          <li>SSL: Angabe, ob der Zugriff per SSL erfolgen soll oder nicht; default: kein SSL</li>
          <li>PortPassword: Angabe des in der Ziel-FHEM-Installation angegebenen Telnet-Passworts</li>
        </ul>
        <p>
          <b>Beispiel:</b><br>
          <code>define MyTTS Text2Speech 192.168.178.10:7072 fhempasswd</code>
          <code>define MyTTS Text2Speech 192.168.178.10</code>
        </p>
        Wenn ein PRESENCE Gerät die Host-IP-Adresse abfragt, wird die blockierende interne Prüfung auf Erreichbarkeit umgangen und das PRESENCE Gerät genutzt.
      </ul>
    </li>

    <li>
      <b>Server Device</b>
      <ul>
        Im Falle der Verwendung als Server wird nur die MP3-Datei erstellt und als Reading lastFilename dargestellt.
        Es ergibt keinen Sinn hier das Attribut <i>TTS_speakAsFastAsPossible</i> zu verwenden.
        Die Verwendung des Attributs <i>TTS_useMP3Wrap</i> wird dringend empfohlen.
        Ansonsten wird hier nur der letzte Teiltext als mp3 Datei im Reading dargestellt.
      </ul>
      <p>
          <b>Beispiel:</b><br>
          <code>define MyTTS Text2Speech none</code>
      </p>
    </li>

  </ul>
</ul>

<a id="Text2Speech-set"></a>
<h4>Set</h4>
<ul>
  <li><b>tts</b>:<br>
    Setzen eines Textes zur Sprachausgabe. Um mp3-Dateien direkt auszugeben, müssen diese mit f&uuml;hrenden
    und schließenden Doppelpunkten angegebenen sein. Die MP3-Dateien müssen unterhalb des Verzeichnisses <i>TTS_FileTemplateDir</i> gespeichert sein.<br>
    Der Text selbst darf deshalb selbst keine Doppelpunkte beinhalten. <br>
    Für die Sprachengine Amazon Polly kann auch SSML verwendet werden. Siehe Beispiele.
  </li>
  <li><b>volume</b>:<br>
    Setzen der Ausgabe Lautst&auml;rke.<br>
    Achtung: Nur bei einem lokal definierter Text2Speech Instanz m&ouml;glich!
  </li>
</ul><br>

<a id="Text2Speech-get"></a>
<h4>Get</h4>
<ul>N/A</ul><br>

<a id="Text2Speech-attr"></a>
<h4>Attribute</h4>
<ul>
  <a id="Text2Speech-attr-TTS_Delimiter"></a><li>TTS_Delimiter<br>
    Optional: Wird ein Delimiter angegeben, so wird der Sprachbaustein an dieser Stelle geteilt.
    Als Delimiter ist nur ein einzelnes Zeichen zul&auml;ssig.
    Hintergrund ist die Tatsache, dass die einige Sprachengines nur eine bestimmte Anzahl an Zeichen (z. B. Google nur 100Zeichen) zul&auml;sst.<br>
    Im Standard wird nach jedem Satzende geteilt. Ist ein einzelner Satz l&auml;nger als 100 Zeichen,
    so wird zus&auml;tzlich nach Kommata, Semikolon und dem Verbindungswort <i>und</i> geteilt.<br>
    Achtung: Nur bei einem lokal definierter Text2Speech Instanz m&ouml;glich!<br>
    <b>Notation</b><br>
       + -> erzwinge das Trennen, auch wenn Textbaustein < x Zeichen<br>
       - -> trenne, nur wenn Textbaustein > x Zeichen
      af -> add first -> füge den Delimiter am Satzanfang wieder hinzu<br>
      al -> add last  -> füge den Delimiter am Satzende wieder hinzu<br>
      an -> add nothing -> Delimiter nicht wieder hinzufügen<br>
       ~ -> der Delimiter<br>
    <b>Beispiel</b><br>
    <code>attr myTTS TTS_Delimiter -al.</code>
  </li>

  <a id="Text2Speech-attr-TTS_Ressource"></a><li>TTS_Ressource<br>
    Optional: Auswahl der Sprachengine<br>
    Achtung: Nur bei einem lokal definierter Text2Speech Instanz m&ouml;glich!
    <ul>
      <li>Google<br>
        Google Sprachengine. Voraussetzung: Aktive Internetverbindung<br>
        Aufgrund der Qualit&auml;t ist der Einsatz der Engine empfohlen und daher der Standard.
      </li>
      <li>VoiceRSS<br>
        VoiceRSS Sprachengine. Voraussetzung: Aktive Internetverbindung<br>
        Die Nutzung ist frei bis zu 350 Anfragen pro Tag. Wenn mehr benötigt werden, ist ein Bezahlmodell wählbar.
        Aufgrund der Qualit&auml;t ist der Einsatz dieser Engine ebenfalls empfohlen.
        Wird diese Engine benutzt, ist ein APIKey notwendig (siehe TTS_APIKey)
      </li>
      <li>ESpeak<br>
        ESpeak Sprachengine. Voraussetzung: Installation von Espeak und lame<br>
        eSpeak ist ein Open-Source-Software-Sprachsynthesizer für Englisch und andere Sprachen.
        Die Qualit&auml; ist schlechter als die der Google Engine<br>
      </li>
      <li>SVOX-pico<br>
        SVOX-Pico TTS-Engine (aus dem AOSP). Voraussetzung: Installation von SVOX-Pico and lame<br>
        Die Sprachengine sowie <code>lame</code> müssen installiert sein:<br>
        <code>sudo apt-get install libttspico-utils lame</code><br><br>
        Für ARM/Raspbian sind die <code>libttspico-utils</code> leider nicht verfügbar,<br>
        deswegen müsste man diese selbst kompilieren oder das vorkompilierte Paket aus <a target="_blank" href"http://www.robotnet.de/2014/03/20/sprich-freund-und-tritt-ein-sprachausgabe-fur-den-rasberry-pi/">dieser Anleitung</a> verwenden, in aller K&uuml;rze:<br>
        <code>sudo apt-get install libpopt-dev lame</code><br>
        <code>cd /tmp</code><br>
        <code>wget http://www.dr-bischoff.de/raspi/pico2wave.deb</code><br>
        <code>sudo dpkg --install pico2wave.deb</code>
      </li>
      <li>Amazon-Polly<br>
       Amazon Polly Sprachengine. Voraussetzung: Aktive Internetverbindung und Perl Package Paws<br>
       Amazon-Dienst, der Text in lebensechte Sprache umwandelt. Ein AWS Konto und ein Polly AWS User müssen verfügbar sein<br>
       <code>cpan paws</code><br>
       Die Zugangsdaten zum eigenen AWS Konto müssen unter ~/.aws/credentials liegen. <br>
       <code>[default]
         aws_secret_access_key = xxxxxxxxxxxxxxxxxxxxxx
         aws_access_key_id = xxxxxxxxxxxxxxx
       </code>
      </li>
      <li>maryTTS<br>
        <a target="_blank" href"https://github.com/marytts/marytts">maryTTS</a> oder <a target="_blank" href"https://github.com/MycroftAI/mimic3">Mimic 3</a> Sprachsynthesizer, der betr. Server sowie lame muss separat installiert werden. Beides sind open source Lösungen für English und andere Sprachen.
        Über das Attribut <a href="#Text2Speech-attr-TTS_User">TTS_User</a> können ergänzende Angaben zu Server, Port und verwendeten Stimme etc. gemacht werden.<br>
      </li>
    </ul>
  </li>

  <a id="Text2Speech-attr-TTS_Language"></a><li>TTS_Language<br>
    Auswahl verschiedener Standardsprachen.
  </li>

  <a id="Text2Speech-attr-TTS_Language_Custom"></a><li>TTS_Language_Custom<br>
    Möchte man eine Sprache und Stimme abweichend der Standardsprachen verwenden, so kann man diese hier eintragen. <br>
    Die Definition ist abhängig der verwendeten Sprachengine. Dieses Attribut überschreibt ein ev. vorhandenes TTS_Langugae Attribut.<br>
    Siehe in die jeweilige API Referenz
  </li>

  <a id="Text2Speech-attr-TTS_APIKey"></a><li>TTS_APIKey<br>
    Wenn VoiceRSS genutzt wird, ist ein APIKey notwendig. Um diesen zu erhalten ist eine vorherige
    Registrierung notwendig. Anschließend erhält man den APIKey <br>
    http://www.voicerss.org/registration.aspx <br>
  </li>

  <a id="Text2Speech-attr-TTS_User"></a><li>TTS_User<br>
    Derzeit nur für maryTTS (bzw. Mimic 3) genutzt. Falls eine Sprachengine zusätzlich zum APIKey einen Usernamen im Request verlangt.<br>
    <p>(Vollständiges) Beispiel für maryTTS (die angegebenen Werte entsprechen den defaults):</p>
        <p><code>attr t2s TTS_User host=127.0.0.1 port=59125 lang=de_DE voice=de_DE/thorsten_low</code></p>
  </li>

  <a id="Text2Speech-attr-TTS_CacheFileDir"></a><li>TTS_CacheFileDir<br>
    Optional: Die per Google geladenen Sprachbausteine werden in diesem Verzeichnis zur Wiederverwendung abgelegt.
    Es findet zurzeit keine automatisierte L&ouml;schung statt.<br>
    Default: <i>cache/</i><br>
    Achtung: Nur bei einer lokal definierten Text2Speech-Instanz m&ouml;glich!
  </li>

  <a id="Text2Speech-attr-TTS_UseMP3Wrap"></a><li>TTS_UseMP3Wrap<br>
    Optional: F&uuml;r eine fl&uuml;ssige Sprachausgabe ist es zu empfehlen, die einzelnen vorher
    geladenen Sprachbausteine zu einem einzelnen Sprachbaustein zusammenfassen zu lassen bevor dieses per
    Mplayer ausgegeben werden. Dazu muss Mp3Wrap installiert werden.<br>
    <code>apt-get install mp3wrap</code><br>
    Achtung: Nur bei einer lokal definierten Text2Speech-Instanz m&ouml;glich!
  </li>

  <a id="Text2Speech-attr-TTS_MplayerCall"></a><li>TTS_MplayerCall<br>
    Optional: Angabe des Systemaufrufs für einen alternativen Player. Wird der Aufruf gesetzt,<br>
    können folgende Templates genutzt werden: <br>
    <ul>
        <li>{device}</li>
        <li>{volume}</li>
        <li>{volumeadjust}</li>
        <li>{file}</li>
        <li>{options}</li>
    </ul>
    {options} werden als Text in Klammern bei der Ausführung von set gesetzt, um beispielsweise spezielle
    Parameter für jeden Aufruf separat zu setzen<br>
    Beispiel: <code>set myTTS tts [192.168.0.1:7000] Das ist mein Text</code><br><br>

    Beispiel der Definition:<br>
    <code>attr myTTS TTS_MplayerCall sudo /usr/bin/mplayer</code><br>
    <code>attr myTTS TTS_MplayerCall AUDIODEV={device} play -q -v {volume} {file}</code><br>
    <code>attr myTTS TTS_MplayerCall player {file} {options}</code><br>
  </li>

  <a id="Text2Speech-attr-TTS_SentenceAppendix"></a><li>TTS_SentenceAppendix<br>
    Optional: Angabe einer mp3-Datei die mit jeder Sprachausgabe am Ende ausgegeben wird.<br>
    Voraussetzung ist die Nutzung von MP3Wrap. Die Sprachbausteine müssen bereits als mp3 im
    CacheFileDir vorliegen.
    Beispiel: <code>silence.mp3</code>
  </li>

  <a id="Text2Speech-attr-TTS_FileMapping"></a><li>TTS_FileMapping<br>
    Angabe von m&ouml;glichen MP3-Dateien mit deren Template-Definition. Getrennt durch Leerzeichen.
    Die Template-Definitionen können in den per <i>tts</i> &uuml;bergebenen Sprachbausteinen verwendet werden
    und m&uuml;ssen mit einem beginnenden und endenden Doppelpunkt angegeben werden.
    Die Dateien müssen im Verzeichnis <i>TTS_FileTemplateDir</i> gespeichert sein.<br>
    <code>attr myTTS TTS_FileMapping ring:ringtone.mp3 beep:MyBeep.mp3</code><br>
    <code>set MyTTS tts Achtung: hier kommt mein Klingelton :ring: War der laut?</code>
  </li>

  <a id="Text2Speech-attr-TTS_FileTemplateDir"></a><li>TTS_FileTemplateDir<br>
    Verzeichnis, in dem die per <i>TTS_FileMapping</i> und <i>TTS_SentenceAppendix</i> definierten
    MP3-Dateien gespeichert sind.<br>
    Optional, Default: <code>cache/templates</code>
  </li>

  <a id="Text2Speech-attr-TTS_VolumeAdjust"></a><li>TTS_VolumeAdjust<br>
    Anhebung der Grundlautstärke zur Anpassung an die angeschlossenen Lautsprecher. <br>
    Default: 110<br>
    <code>attr myTTS TTS_VolumeAdjust 400</code><br>
  </li>

  <a id="Text2Speech-attr-TTS_noStatisticsLog"></a><li>TTS_noStatisticsLog<br>
  <b>1</b>, verhindert das Loggen von Statistikdaten in DbLog Ger&auml;ten. Default ist <b>0</b><br>
  Hinweis: Das Logging ist wichtig um alte, lang nicht genutzte Cachedateien automatisiert zu l&ouml;schen.
  Wird die Option hier aktiviert, muss sich der Nutzer selbst darum k&uuml;ümmern.
  </li>

  <a id="Text2Speech-attr-TTS_speakAsFastAsPossible"></a><li>TTS_speakAsFastAsPossible<br>
    Es wird versucht, so schnell als möglich eine Sprachausgabe zu erzielen. Bei Sprachbausteinen
    die nicht bereits lokal vorliegen, ist eine kurze Pause wahrnehmbar. Dann wird der benötigte
    Sprachbaustein nachgeladen. Liegen alle Sprachbausteine im Cache vor, so hat dieses Attribut keine Auswirkung.<br>
    Attribut nur verfügbar bei einer lokalen oder Server Instanz
  </li>

  <a id="Text2Speech-attr-TTS_OutputFile"></a><li>TTS_OutputFile<br>
      Angabe eines fixen Dateinamens als mp3 Output. Das Attribut ist nur relevant in Verbindung mit TTS_UseMP3Wrap.<br>
      Wenn ein Dateiname angegeben wird, so wird zusätzlich TTS_CacheFileDir beachtet. Bei einer absoluten Pfadangabe
      muss der Dateipfad durch FHEM schreibbar sein.<br>
      <code>attr myTTS TTS_OutputFile output.mp3</code><br>
      <code>attr myTTS TTS_OutputFile /media/miniDLNA/output.mp3</code><br>
  </li>

  <a id="Text2Speech-attr-TTS_RemotePlayerCall"></a><li>TTS_RemotePlayerCall<br>
      Die Text2Speech Geräte stellen eine URL bereit, die auf die letzte erzeugte mp3 Datei zeigt:<br>
      <code>&lt;protocol&gt;://&lt;fhem server name or ip&gt;:&lt;fhem port&gt;/fhem/Text2Speech/&lt;device name&gt;/last.mp3</code><br>
      Wenn dieses Attribut den Aufruf eines Remoteplayers enthält, wird er nach dem Erzeugen der letzten mp3 Datei ausgeführt.<br>
      Beispiel zum Abspielen einer Datei auf einem Smartphone oder Tablet mit Fully Kiosk Browser App.<br>
      <code>attr &lt;device name&gt; TTS_RemotePlayerCall GetFileFromURL('&lt;protocol&gt;://&lt;remote player name or ip&gt;:2323/?cmd=playSound&url=&lt;protocol&gt;://&lt;fhem server name or ip&gt;:&lt;fhem port&gt;/fhem/Text2Speech/&lt;device name&gt;/last.mp3&loop=false&password=&lt;password&gt;')</code><br>
  </li>

  <li><a href="#readingFnAttributes">readingFnAttributes</a>
  </li><br>

  <li><a href="#disable">disable</a><br>
    Wird das Attribut aktiviert, wird die Audioausgabe deaktiviert.<br>
    Mögliche Werte: 0 => nicht deaktiviert , 1 => deaktiviert<br>
    Standardwert ist 0 (nicht deaktiviert)<br><br>
  </li>

  <li><a href="#verbose">verbose</a><br>
    <b>4:</b> Alle Zwischenschritte der Verarbeitung werden ausgegeben<br>
    <b>5:</b> Zus&auml;tzlich werden auch die Meldungen von Mplayer und Mp3Wrap ausgegeben
  </li>

</ul><br>

<a id="Text2Speech-examples"></a>
<h4>Beispiele</h4>
<ul>
  <code>define TTS_EG_WZ Text2Speech hw=/dev/snd/controlC3</code><br>
  <code>attr TTS_EG_WZ TTS_Language Deutsch</code><br>
  <code>attr TTS_EG_WZ TTS_MplayerCall /usr/bin/mplayer</code><br>
  <code>attr TTS_EG_WZ TTS_Ressource Amazon-Polly</code><br>
  <code>attr TTS_EG_WZ TTS_UseMP3Wrap 1</code><br><br>
  <code>set MyTTS tts &lt;speak&gt;Mary had a little lamb.&lt;/speak&gt;</code>
  <br>
  <code>define MyTTS Text2Speech hw=0.0</code><br>
  <code>set MyTTS tts Die Alarmanlage ist bereit.</code><br>
  <code>set MyTTS tts :beep.mp3:</code><br>
  <code>set MyTTS tts :mytemplates/alarm.mp3:Die Alarmanlage ist bereit.:ring.mp3:</code>
  <br>
  Beispiel MaryTTS und SSML: <br>
  <code>
    define T2S Text2Speech default
    attr T2S TTS_MplayerCall /usr/bin/mplayer
    attr T2S TTS_Ressource maryTTS
    attr T2S TTS_User host=192.168.100.1 port=59125 lang=de_DE voice=de_DE/thorsten_low ssml=1
    set T2S tts '&lt;voice name="de_DE/m-ailabs_low#rebecca_braunert_plunkett"&gt;Das ist ein Test in deutsch &lt;/voice&gt;&lt;voice name="en_US/vctk_low#p236"&gt;and this is an test in english.&lt;/voice&gt;'
  </code>
</ul>

=end html_DE
=cut
