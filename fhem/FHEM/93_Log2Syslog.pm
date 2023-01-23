##########################################################################################################################
# $Id$
##########################################################################################################################
#       93_Log2Syslog.pm
#
#       (c) 2017-2023 by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This script is part of fhem.
#
#       Fhem is free software: you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation, either version 2 of the License, or
#       (at your option) any later version.
#
#       Fhem is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#       The module is inspired by 92_rsyslog.pm (betateilchen)
#
#       Implements the Syslog Protocol according to RFCs:
#       RFC 5424  https://tools.ietf.org/html/rfc5424
#       RFC 3164 https://tools.ietf.org/html/rfc3164 and
#       TLS Transport according to RFC 5425 https://tools.ietf.org/pdf/rfc5425.pdf
#       Date and Time according to RFC 3339 https://tools.ietf.org/html/rfc3339
#       RFC 6587 Transmission of Syslog Messages over TCP
#
##########################################################################################################################
package FHEM::Log2Syslog;                                            ## no critic 'package'

use strict;
use warnings;
use TcpServerUtils;
use POSIX;
use Scalar::Util qw(looks_like_number);
use Time::HiRes qw(gettimeofday);
use Encode qw(encode_utf8 decode_utf8);
eval "use IO::Socket::INET;1"                                         or my $MissModulSocket = "IO::Socket::INET";   ## no critic 'eval'
eval "use Net::Domain qw(hostname hostfqdn hostdomain domainname);1"  or my $MissModulNDom   = "Net::Domain";        ## no critic 'eval'
eval "use FHEM::Meta;1"                                               or my $modMetaAbsent   = 1;                    ## no critic 'eval'
use GPUtils qw(GP_Import GP_Export);

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import( 
      qw(
          attr
          AttrVal 
          currlogfile                        
          CommandDelete
          defs
          deviceEvents
          devspec2array
          DoTrigger
          fhemTimeLocal
          fhemTzOffset 
          init_done
          InternalTimer
          IsDisabled
          logInform
          logopened                          
          Log3            
          modules   
          notifyRegexpChanged 
          OpenLogfile
          perlSyntaxCheck  
          readyfnlist    
          readingFnAttributes          
          RemoveInternalTimer
          readingsBeginUpdate
          readingsBulkUpdate
          readingsEndUpdate
          readingsSingleUpdate
          ReadingsVal
          ResolveDateWildcards
          selectlist
          sortTopicNum
          TcpServer_Open
          TcpServer_Accept
          TcpServer_Close
          TcpServer_SetSSL
          TimeNow            
        )
  );
  
  # Export to main context with different name
  #     my $pkg  = caller(0);
  #     my $main = $pkg;
  #     $main =~ s/^(?:.+::)?([^:]+)$/main::$1\_/g;
  #     foreach (@_) {
  #         *{ $main . $_ } = *{ $pkg . '::' . $_ };
  #     }
  GP_Export(
      qw(
          Initialize
      )
  );

}

# Versions History intern:
my %vNotesIntern = (
  "5.12.5" => "23.01.2023  Adaptation to change \%logInform in fhem.pl, Forum:#131790 ",
  "5.12.4" => "27.02.2021  don't split data by CRLF if EOF is used (in getIfData) ",
  "5.12.3" => "02.11.2020  avoid do Logfile archiving which was executed in seldom (unknown) cases ",
  "5.12.2" => "15.05.2020  permit content of 'exclErrCond' to fhemLog strings ",
  "5.12.1" => "12.05.2020  add dev to check regex of 'exclErrCond' ",
  "5.12.0" => "16.04.2020  improve IETF octet count again, internal code changes for PBP ",
  "5.11.0" => "14.04.2020  switch to packages, improve IETF octet count ",
  "5.10.3" => "11.04.2020  new reading 'Parse_Err_LastData', change octet count read ",
  "5.10.2" => "08.04.2020  code changes to stabilize send process, minor fixes ",
  "5.10.1" => "06.04.2020  support time-secfrac of RFC 3339, minor fix ",
  "5.10.0" => "04.04.2020  new attribute 'timeSpec', send and parse messages according to UTC or Local time, some minor fixes (e.g. for Octet Count) ",
  "5.9.0"  => "01.04.2020  Parser UniFi Controller Syslog (BSD Format) and Netconsole messages, more code review (e.g. remove prototypes) ",
  "5.8.3"  => "31.03.2020  fix warning uninitialized value \$pp in pattern match (m//) at line 465, Forum: topic,75426.msg1036553.html#msg1036553, some code review ",
  "5.8.2"  => "28.07.2019  fix warning uninitialized value in numeric ge (>=) at line 662 ",
  "5.8.1"  => "23.07.2019  attribute waitForEOF rename to useEOF, useEOF also for type sender ",
  "5.8.0"  => "20.07.2019  attribute waitForEOF, solution for Forum: https://forum.fhem.de/index.php/topic,75426.msg958836.html#msg958836 ",
  "5.7.0"  => "20.07.2019  change logging and chomp received data, use raw parse format if automatic mode don't detect a valid format, ".
                           "change getifdata tcp stack error handling (if sysread undef)",
  "5.6.5"  => "19.07.2019  bugfix parse BSD if ID (TAG) is used, function DbLog_splitFn -> DbLogSplit, new attribute useParsefilter ",
  "5.6.4"  => "19.07.2019  minor changes and fixes (max. lenth read to 16384, code && logging) ",
  "5.6.3"  => "18.07.2019  fix state reading if changed disabled attribute ",
  "5.6.2"  => "17.07.2019  Forum: https://forum.fhem.de/index.php/topic,75426.msg958836.html#msg958836 first try",
  "5.6.1"  => "24.03.2019  prevent module from deactivation in case of unavailable Meta.pm ",
  "5.6.0"  => "23.03.2019  attribute exclErrCond to exclude events from rating as \"error\" ",
  "5.5.0"  => "18.03.2019  prepare for Meta.pm ",
  "5.4.0"  => "17.03.2019  new feature parseProfile = Automatic ",
  "5.3.2"  => "08.02.2019  fix version numbering ",
  "5.3.1"  => "21.10.2018  get of FQDN changed ",
  "5.3.0"  => "16.10.2018  attribute sslCertPrefix added (Forum:#92030), module hints & release info order switched ",
  "5.2.1"  => "08.10.2018  setpayload of BSD-format changed, commandref revised ",
  "5.2.0"  => "02.10.2018  added direct help for attributes",
  "5.1.0"  => "01.10.2018  new get <name> versionNotes command",
  "5.0.1"  => "27.09.2018  closeSocket if write error:.* , delete readings code changed",
  "5.0.0"  => "26.09.2018  TCP-Server in Collector-mode, HIPCACHE added, PROFILE as Internal, Parse_Err_No as reading ".
                           "octetCount attribute, TCP-SSL-support, set 'reopen' command, code fixes",
  "4.8.5"  => "20.08.2018  BSD/parseFn parsing changed, BSD setpayload changed, new variable \$IGNORE in parseFn",
  "4.8.4"  => "15.08.2018  BSD parsing changed",
  "4.8.3"  => "14.08.2018  BSD setpayload changed, BSD parsing changed, Internal MYFQDN", 
  "4.8.2"  => "13.08.2018  rename makeMsgEvent to makeEvent",
  "4.8.1"  => "12.08.2018  IETF-Syslog without VERSION changed, Log verbose 1 to 2 changed in parsePayload",
  "4.8.0"  => "12.08.2018  enhanced IETF Parser to match logs without version", 
  "4.7.0"  => "10.08.2018  Parser for TPLink",
  "4.6.1"  => "10.08.2018  some perl warnings, changed IETF Parser",
  "4.6.0"  => "08.08.2018  set sendTestMessage added, Attribute 'contDelimiter', 'respectSeverity'",
  "4.5.1"  => "07.08.2018  BSD Regex changed, setpayload of BSD changed",
  "4.5.0"  => "06.08.2018  Regex capture groups used in parsePayload to set variables, parsing of BSD changed ".
                           "Attribute 'makeMsgEvent' added",
  "4.4.0"  => "04.08.2018  Attribute 'outputFields' added",
  "4.3.0"  => "03.08.2018  Attribute 'parseFn' added",
  "4.2.0"  => "03.08.2018  evaluate sender peer ip-address/hostname, use it as reading in event generation",
  "4.1.0"  => "02.08.2018  state event generation changed",
  "4.0.0"  => "30.07.2018  server mode (Collector)",
  "3.2.1"  => "04.05.2018  fix compatibility with newer IO::Socket::SSL on debian 9, attr ssldebug for ".
                           "debugging SSL messages",
  "3.2.0"  => "22.11.2017  add NOTIFYDEV if possible",
  "3.1.0"  => "28.08.2017  get-function added, commandref revised, \$readingFnAttributes deleted",
  "3.0.0"  => "27.08.2017  change attr type to protocol, ready to check in",
  "2.6.0"  => "26.08.2017  more than one Log2Syslog device can be created",
  "2.5.2"  => "26.08.2018  fix in splitting timestamp, change calcTrate using internaltimer with attr ".
                           "rateCalcRerun, function closeSocket",
  "2.5.1"  => "24.08.2017  some fixes",
  "2.5.0"  => "23.08.2017  TLS encryption available, new readings, \$readingFnAttributes",
  "2.4.1"  => "21.08.2017  changes in charFilter, change PROCID to \$hash->{SEQNO} ".
                           "switch to non-blocking in subs event/fhemLog",
  "2.4.0"  => "20.08.2017  new sub Log3slog for entries in local fhemlog only -> verbose support",
  "2.3.1"  => "19.08.2017  commandref revised ",
  "2.3.0"  => "18.08.2017  new parameter 'ident' in DEF, sub setidex, charFilter",
  "2.2.0"  => "17.08.2017  set BSD data length, set only acceptable characters (USASCII) in payload ".
                           "commandref revised ",
  "2.1.0"  => "17.08.2017  sub openSocket created",
  "2.0.0"  => "16.08.2017  create syslog without SYS::SYSLOG",
  "1.1.1"  => "13.08.2017  registrate fhemLog to %loginform in case of sending fhem-log ".
                           "attribute timeout, commandref revised",
  "1.1.0"  => "26.07.2017  add regex search to sub fhemLog",
  "1.0.0"  => "25.07.2017  initial version"
);

# Versions History extern:
my %vNotesExtern = (
  "5.10.0" => "04.04.2020 The new attribute 'timeSpec' can be set to send and receive/parse messages according to UTC or Local time format. ".
                          "Please refer to <a href=\"https://tools.ietf.org/pdf/rfc3339.pdf\">Date and Time on the Internet: Timestamps</a> for further information  ",
  "5.9.0"  => "01.04.2020 The new option \"UniFi\" of attribute \"parseProfil\" provedes a new Parser for UniFi Controller Syslog messages ".
                          "and Netconsole messages. It was tested with UniFi AP-AC-Lite but should run with all Unifi products. ",
  "5.8.1"  => "23.07.2019 New attribute \"useParsefilter\" to remove other characters than ASCII from payload before parse it. ".
                          "New attribute \"useEOF\" to parse not till the sender was sending an EOF signal (Collector), or in ".
                          "case of model Sender, after transmission an EOF signal is send. A bugfix for ".
                          "parsing BSD if the ID (TAG) is used was implemented. Minor other fixes and changes. ",
  "5.6.0"  => "23.03.2019 New attribute \"exclErrCond\" to exclude events from rating as \"Error\" even though the ".
                          "event contains the text \"Error\". ",
  "5.4.0"  => "17.03.2019 New feature parseProfile = Automatic. The module may detect the message format BSD or IETF automatically in server mode ",
  "5.3.2"  => "08.02.2019 fix version numbering ",
  "5.3.0"  => "16.10.2018 attribute sslCertPrefix added to support multiple SSL-keys (Forum:#92030)",
  "5.2.1"  => "08.10.2018 Send format of BSD changed. The TAG-field was changed to \"IDENT[PID]: \" ",
  "5.2.0"  => "02.10.2018 direct help for attributes added",
  "5.1.0"  => "29.09.2018 new get &lt;name&gt; versionNotes command ",
  "5.0.1"  => "27.09.2018 automatic reconnect to syslog-server in case of write error ",
  "5.0.0"  => "26.09.2018 Some changes:<br><li>TCP Server mode is possible now for Collector devices<\li><li>the used parse-profile is shown as Internal<\li><li>Parse_Err_No counts faulty persings since start<\li><li>new octetCount attribute switches the syslog framing method (see also RFC6587 <a href=\"https://tools.ietf.org/html/rfc6587\">Transmission of Syslog Messages over TCP</a>)<\li><li>TCP SSL-support<\li><li>new set 'reopen' command to reconnect a broken connection<\li><li>some code fixes ",
  "4.8.5"  => "20.08.2018 BSD/parseFn parse changed, BSD setpayload changed, new variable \$IGNORE in parseFn ",
  "4.8.4"  => "15.08.2018 BSD parse changed again ",
  "4.8.3"  => "14.08.2018 BSD setpayload changed, BSD parse changed, new Internal MYFQDN ", 
  "4.8.2"  => "13.08.2018 rename makeMsgEvent to makeEvent ",
  "4.8.1"  => "12.08.2018 IETF-Syslog without VERSION changed, Log verbose 1 to 2 changed in parsePayload ",
  "4.8.0"  => "12.08.2018 enhanced IETF Parser to match logs without version ", 
  "4.7.0"  => "10.08.2018 Parser for TPLink added ",
  "4.6.1"  => "10.08.2018 fix some perl warnings, changed IETF Parser ",
  "4.6.0"  => "08.08.2018 set sendTestMessage added, new attributes 'contDelimiter', 'respectSeverity' ",
  "4.5.1"  => "07.08.2018 BSD Regex changed, setpayload of BSD changed ",
  "4.5.0"  => "06.08.2018 parsing of BSD changed, attribute 'makeMsgEvent' added ",
  "4.4.0"  => "04.08.2018 Attribute 'outputFields' added ",
  "4.3.0"  => "03.08.2018 Attribute 'parseFn' added ",
  "4.2.0"  => "03.08.2018 evaluate sender peer ip-address/hostname and use it as reading in event generation ",
  "4.1.0"  => "02.08.2018 state event generation changed ",
  "4.0.0"  => "30.07.2018 Server mode (Collector) implemented ",
  "3.2.1"  => "04.05.2018 fix compatibility with newer IO::Socket::SSL on debian 9, attribute ssldebug for debugging SSL messages ",
  "3.2.0"  => "22.11.2017 add NOTIFYDEV if possible ",
  "3.1.0"  => "28.08.2017 get-function added, commandref revised ",
  "3.0.0"  => "27.08.2017 change attr type to protocol, ready to first check in ",
  "2.6.0"  => "26.08.2017 more than one Log2Syslog device can be created ",
  "2.5.2"  => "26.08.2018 attribute rateCalcRerun ",
  "2.5.1"  => "24.08.2017 some bugfixes ",
  "2.5.0"  => "23.08.2017 TLS encryption available to Sender ",
  "2.4.1"  => "21.08.2017 change PROCID to \$hash->{SEQNO}, switch to non-blocking in subs event/fhemlog ",
  "2.4.0"  => "20.08.2017 new sub for entries in local fhemlog only including verbose support ",
  "2.3.1"  => "19.08.2017 commandref revised ",
  "2.3.0"  => "18.08.2017 new parameter 'ident' in Define to indentify sylog source ",
  "2.2.0"  => "17.08.2017 set BSD data length, set only acceptable characters (USASCII) in payload ",
  "2.0.0"  => "16.08.2017 create syslog without perl module SYS::SYSLOG ",
  "1.1.0"  => "26.07.2017 add regex search to sub fhemLog ",
  "1.0.0"  => "25.07.2017 initial version "
);

# Mappinghash BSD-Formatierung Monat
my %Log2Syslog_BSDMonth = (
  "01"  => "Jan",
  "02"  => "Feb",
  "03"  => "Mar",
  "04"  => "Apr",
  "05"  => "May",
  "06"  => "Jun",
  "07"  => "Jul",
  "08"  => "Aug",
  "09"  => "Sep",
  "10"  => "Oct",
  "11"  => "Nov",
  "12"  => "Dec",
  "Jan" => "01",
  "Feb" => "02",
  "Mar" => "03",
  "Apr" => "04",
  "May" => "05",
  "Jun" => "06",
  "Jul" => "07",
  "Aug" => "08",
  "Sep" => "09",
  "Oct" => "10",
  "Nov" => "11",
  "Dec" => "12"
);

# Mappinghash Severity
my %Log2Syslog_Severity = (
  "0" => "Emergency",
  "1" => "Alert",
  "2" => "Critical",
  "3" => "Error",
  "4" => "Warning",
  "5" => "Notice",
  "6" => "Informational",
  "7" => "Debug",
  "Emergency"     => "0",
  "Alert"         => "1",
  "Critical"      => "2",
  "Error"         => "3",
  "Warning"       => "4",
  "Notice"        => "5",
  "Informational" => "6",
  "Debug"         => "7"
);

# Mappinghash Facility
my %Log2Syslog_Facility = (
  "0"  => "kernel",
  "1"  => "user",
  "2"  => "mail",
  "3"  => "system",
  "4"  => "security",
  "5"  => "syslog",
  "6"  => "printer",
  "7"  => "network",
  "8"  => "UUCP",
  "9"  => "clock",
  "10" => "security",
  "11" => "FTP",
  "12" => "NTP",
  "13" => "log_audit",
  "14" => "log_alert",
  "15" => "clock",
  "16" => "local0",
  "17" => "local1",
  "18" => "local2",
  "19" => "local3",
  "20" => "local4",
  "21" => "local5",
  "22" => "local6",
  "23" => "local7"
  );

# Längenvorgaben nach RFC3164
my %RFC3164len = ("TAG"  => 32,           # max. Länge TAG-Feld
                  "DL"   => 1024          # max. Länge Message insgesamt
                 );
                 
# Längenvorgaben nach RFC5425
my %RFC5425len = ("DL"  => 8192,          # max. Länge Message insgesamt mit TLS
                  "HST" => 255,           # max. Länge Hostname
                  "ID"  => 48,            # max. Länge APP-NAME bzw. Ident
                  "PID" => 128,           # max. Länge Proc-ID
                  "MID" => 32             # max. Länge MSGID
                  );
                  
my %vHintsExt_en = (
  "4" => "The guidelines for usage of <a href=\"https://tools.ietf.org/pdf/rfc3339.pdf\">RFC5425 Date and Time on the Internet: Timestamps</a>",
  "3" => "The <a href=\"https://tools.ietf.org/pdf/rfc5425.pdf\">RFC5425 TLS Transport Protocol</a>",
  "2" => "The basics of <a href=\"https://tools.ietf.org/html/rfc3164\">RFC3164 (BSD) protocol</a>",
  "1" => "Informations about <a href=\"https://tools.ietf.org/html/rfc5424\">RFC5424 (IETF)</a> syslog protocol"
);

my %vHintsExt_de = (
  "4" => "Die Richtlinien zur Verwendung von <a href=\"https://tools.ietf.org/pdf/rfc3339.pdf\">RFC5425 Datum und Zeit im Internet: Timestamps</a>",
  "3" => "Die Beschreibung des <a href=\"https://tools.ietf.org/pdf/rfc5425.pdf\">RFC5425 TLS Transport Protokoll</a>",
  "2" => "Die Grundlagen des <a href=\"https://tools.ietf.org/html/rfc3164\">RFC3164 (BSD)</a> Protokolls",
  "1" => "Informationen über das <a href=\"https://tools.ietf.org/html/rfc5424\">RFC5424 (IETF)</a> Syslog Protokoll"
);

###############################################################################
sub Initialize {
  my ($hash) = @_;

  $hash->{DefFn}         = \&Define;
  $hash->{UndefFn}       = \&Undef;
  $hash->{DeleteFn}      = \&Delete;
  $hash->{SetFn}         = \&Set;
  $hash->{GetFn}         = \&Get;
  $hash->{AttrFn}        = \&Attr;
  $hash->{NotifyFn}      = \&eventLog;
  $hash->{DbLog_splitFn} = \&DbLogSplit;
  $hash->{ReadFn}        = \&Read;

  $hash->{AttrList} = "addStateEvent:1,0 ".
                      "disable:1,0,maintenance ".
                      "addTimestamp:0,1 ".
                      "contDelimiter ".
                      "exclErrCond:textField-long ".
                      "logFormat:BSD,IETF ".
                      "makeEvent:no,intern,reading ".
                      "outputFields:sortable-strict,PRIVAL,FAC,SEV,TS,HOST,DATE,TIME,ID,PID,MID,SDFIELD,CONT ".
                      "parseProfile:Automatic,BSD,IETF,TPLink-Switch,UniFi,raw,ParseFn ".
                      "parseFn:textField-long ".
                      "respectSeverity:multiple-strict,Emergency,Alert,Critical,Error,Warning,Notice,Informational,Debug ".
                      "octetCount:1,0 ".
                      "protocol:UDP,TCP ".
                      "port ".
                      "rateCalcRerun ".
                      "ssldebug:0,1,2,3 ".
                      "sslCertPrefix ".
                      "TLS:1,0 ".
                      "timeout ".
                      "timeSpec:Local,UTC ".
                      "useParsefilter:0,1 ".
                      "useEOF:1,0 ".
                      $readingFnAttributes
                      ;
                      
  eval { FHEM::Meta::InitMod( __FILE__, $hash ) };    # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)

return;   
}

###############################################################################
sub Define {
  my ($hash, $def) = @_;
  my @a            = split m{\s+}x, $def;
  my $name         = $hash->{NAME};
  
  return "Error: Perl module ".$MissModulSocket." is missing. Install it on Debian with: sudo apt-get install libio-socket-multicast-perl" if($MissModulSocket);
  return "Error: Perl module ".$MissModulNDom." is missing." if($MissModulNDom);
  
  # Example Sender:        define  splunklog Log2Syslog  splunk.myds.me ident:Prod  event:.* fhem:.*
  # Example Collector:     define  SyslogServer Log2Syslog
  
  delete($hash->{HELPER}{EVNTLOG});
  delete($hash->{HELPER}{FHEMLOG});
  delete($hash->{HELPER}{IDENT});
  
  $hash->{MYHOST} = hostname();                                        # eigener Host (lt. RFC nur Hostname f. BSD)
  my $myfqdn      = hostfqdn();                                        # MYFQDN eigener Host (f. IETF)
  $myfqdn         =~ s/\.$//x if($myfqdn);
  $hash->{MYFQDN} = $myfqdn // $hash->{MYHOST};       
  
  if(int(@a)-3 < 0){                                                   # Einrichtung Servermode (Collector)
      $hash->{MODEL}   = "Collector";
      $hash->{PROFILE} = "Automatic";                          
      readingsSingleUpdate ($hash, 'Parse_Err_No', 0, 1);              # Fehlerzähler für Parse-Errors auf 0
      readingsSingleUpdate ($hash, 'Parse_Err_LastData', 'n.a.', 0);
      Log3slog             ($hash, 3, "Log2Syslog $name - entering Syslog servermode ..."); 
      initServer           ("$name,global");
  } 
  else {                                                               # Sendermode
      $hash->{MODEL} = "Sender";
      setidrex($hash,$a[3]) if($a[3]);
      setidrex($hash,$a[4]) if($a[4]);
      setidrex($hash,$a[5]) if($a[5]);
      
      eval { "Hallo" =~ m/^$hash->{HELPER}{EVNTLOG}$/x } if($hash->{HELPER}{EVNTLOG});
      return "Bad regexp: $@" if($@);
      eval { "Hallo" =~ m/^$hash->{HELPER}{FHEMLOG}$/x } if($hash->{HELPER}{FHEMLOG});
      return "Bad regexp: $@" if($@);
  
      return "Bad regexp: starting with *" 
         if((defined($hash->{HELPER}{EVNTLOG}) && $hash->{HELPER}{EVNTLOG} =~ m/^\*/x) || (defined($hash->{HELPER}{FHEMLOG}) && $hash->{HELPER}{FHEMLOG} =~ m/^\*/x));
  
      notifyRegexpChanged($hash, $hash->{HELPER}{EVNTLOG}) if($hash->{HELPER}{EVNTLOG});    # nur Events dieser Devices an NotifyFn weiterleiten, NOTIFYDEV wird gesetzt wenn möglich
        
      $hash->{PEERHOST} = $a[2];                                       # Destination Host (Syslog Server)
  }

  $hash->{SEQNO}                 = 1;                                  # PROCID in IETF, wird kontinuierlich hochgezählt
  $logInform{$hash->{NAME}}      = \&FHEM::Log2Syslog::fhemLog;        # Funktion die in hash %loginform für $name eingetragen wird
  $hash->{HELPER}{SSLVER}        = "n.a.";                             # Initialisierung
  $hash->{HELPER}{SSLALGO}       = "n.a.";                             # Initialisierung
  $hash->{HELPER}{LTIME}         = time();                             # Init Timestmp f. Ratenbestimmung
  $hash->{HELPER}{OLDSEQNO}      = $hash->{SEQNO};                     # Init Sequenznummer f. Ratenbestimmung
  $hash->{HELPER}{OLDSTATE}      = "initialized";
  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);               # Modul Meta.pm nicht vorhanden
  
  # Versionsinformationen setzen
  setVersionInfo($hash);
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate ($hash, "SSL_Version", "n.a.");
  readingsBulkUpdate ($hash, "SSL_Algorithm", "n.a.");
  readingsBulkUpdate ($hash, "Transfered_logs_per_minute", 0);
  readingsBulkUpdate ($hash, "state", "initialized") if($hash->{MODEL}=~/Sender/);
  readingsEndUpdate  ($hash,1);
  
  calcTrate($hash);                                                    # regelm. Berechnung Transfer Rate starten 
      
return;
}

#################################################################################################
#                       Syslog Collector (Server-Mode) initialisieren
#                       (im Collector Model)
#################################################################################################
sub initServer {
  my ($a)            = @_;
  my ($name,$global) = split(",",$a);
  my $hash           = $defs{$name};
  my $err;

  RemoveInternalTimer($hash, "FHEM::Log2Syslog::initServer");
  return if(IsDisabled($name) || $hash->{SERVERSOCKET});
  
  if($init_done != 1 || isMemLock($hash)) {
      InternalTimer(gettimeofday()+1, "FHEM::Log2Syslog::initServer", "$name,$global", 0);
      return;
  }
  
  # Inititialisierung FHEM ist fertig -> Attribute geladen
  my $port     = AttrVal($name, "TLS", 0)?AttrVal($name, "port", 6514):AttrVal($name, "port", 1514);
  my $protocol = lc(AttrVal($name, "protocol", "udp"));
  my $lh       = ($global ? ($global eq "global" ? undef : $global) : ($hash->{IPV6} ? "::1" : "127.0.0.1"));
  
  Log3slog ($hash, 3, "Log2Syslog $name - Opening socket on interface \"$global\" ...");
  
  if($protocol =~ /udp/) {
      $hash->{SERVERSOCKET} = IO::Socket::INET->new(
        Domain    => ($hash->{IPV6} ? AF_INET6() : AF_UNSPEC()), # Linux bug
        LocalHost => $lh,
        Proto     => $protocol,
        LocalPort => $port, 
        ReuseAddr => 1
      ); 
      if(!$hash->{SERVERSOCKET}) {
          $err = "Can't open Syslog Collector at $port: $!";
          Log3slog  ($hash, 1, "Log2Syslog $name - $err");
          readingsSingleUpdate ($hash, 'state', $err, 1);
          return;      
      }
      $hash->{FD}   = $hash->{SERVERSOCKET}->fileno();
      $hash->{PORT} = $hash->{SERVERSOCKET}->sockport();           
  } else {
      $lh     = "global" if(!$lh);
      my $ret = TcpServer_Open($hash,$port,$lh);
      if($ret) {        
          $err = "Can't open Syslog TCP Collector at $port: $ret";
          Log3slog  ($hash, 1, "Log2Syslog $name - $err");
          readingsSingleUpdate ($hash, 'state', $err, 1);
          return; 
      }
  }
  
  $hash->{PROTOCOL}         = $protocol;
  $hash->{SEQNO}            = 1;                            # PROCID wird kontinuierlich pro empfangenen Datensatz hochgezählt
  $hash->{HELPER}{OLDSEQNO} = $hash->{SEQNO};               # Init Sequenznummer f. Ratenbestimmung
  $hash->{INTERFACE}        = $lh // "global";
  
  Log3slog  ($hash, 3, "Log2Syslog $name - port $hash->{PORT}/$protocol opened for Syslog Collector on interface \"$hash->{INTERFACE}\"");
  readingsSingleUpdate ($hash, "state", "initialized", 1);
  delete($readyfnlist{"$name.$port"});
  $selectlist{"$name.$port"} = $hash;

return;
}

########################################################################################################
#                        Syslog Collector Daten empfangen (im Collector-Mode)
#  
#                                        !!!!! Achtung !!!!!
#  Kontextswitch des $hash beachten:  initialer TCP-Server <-> temporärer TCP-Server ohne SERVERSOCKET
#
########################################################################################################
# called from the global loop, when the select for hash->{FD} reports data
sub Read {                                                  ## no critic 'complexity'
  my ($hash,$reread) = @_;
  my $socket         = $hash->{SERVERSOCKET};
  
  my ($err,$sev,$data,$ts,$phost,$pl,$ignore,$st,$len,$mlen,$evt,$pen,$rhash);  
  
  return if($init_done != 1);
  
  # maximale Länge des (Syslog)-Frames als Begrenzung falls kein EOF
  # vom Sender initiiert wird (Endlosschleife vermeiden)
  # Grundeinstellungen
  $mlen = 16384;
  $len  = 8192;
  
  if($hash->{TEMPORARY}) {
      my $sname = $hash->{SNAME};
      $rhash    = $defs{$sname};
  } 
  else {
      $rhash = $hash;
  }
          
  my $pp = $rhash->{PROFILE};
  if($pp =~ /BSD/) {                                                    # Framelänge BSD-Format
      $len = $RFC3164len{DL};
  } 
  elsif ($pp =~ /IETF/) {                                               # Framelänge IETF-Format   
      $len = $RFC5425len{DL};     
  } 

  if($hash->{TEMPORARY}) {                                              # temporäre Instanz angelegt durch TcpServer_Accept
      ($st,$data,$hash) = getIfData($hash,$len,$mlen,$reread);
  }
  
  my $name   = $hash->{NAME};
  return if(IsDisabled($name) || isMemLock($hash));
  
  my $mevt   = AttrVal($name, "makeEvent",       "intern");             # wie soll Reading/Event erstellt werden
  my $sevevt = AttrVal($name, "respectSeverity", ""      );             # welcher Schweregrad soll berücksichtigt werden (default: alle)
  my $uef    = AttrVal($name, "useEOF",          0       );             # verwende EOF
  
  if($socket) {
      ($st,$data,$hash) = getIfData($hash,$len,$mlen,$reread);
  }
  
  if($data) {                                                           # parse Payload 
      my (@load,$ocount,$msg,$tail);
      if($data =~ /^(?<ocount>(\d+?))\s(?<tail>(.*))/sx) {              # Syslog Sätze mit Octet Count -> Transmission of Syslog Messages over TCP https://tools.ietf.org/html/rfc6587
          Log3slog ($hash, 4, "Log2Syslog $name - Datagramm with Octet Count detected - prepare message for Parsing ... \n");          
          use bytes;
          my $i   = 0;
          $ocount = $+{ocount};
          $tail   = $+{tail}; 
          $msg    = substr($tail,0,$ocount);
          push @load, $msg;
          
          if(length($tail) >= $ocount) {
              $tail = substr($tail,$ocount);
          } 
          else {
              $tail = substr($tail,length($msg));
          }
          
          Log3slog ($hash, 5, "Log2Syslog $name -> OCTETCOUNT$i: $ocount"); 
          Log3slog ($hash, 5, "Log2Syslog $name -> MSG$i       : $msg");
          Log3slog ($hash, 5, "Log2Syslog $name -> LENGTH_MSG$i: ".length($msg)); 
          Log3slog ($hash, 5, "Log2Syslog $name -> TAIL$i      : $tail");
          
          while($tail && $tail =~ /^(?<ocount>(\d+?))\s(?<tail>(.*))/sx) {
              $i++;
              $ocount = $+{ocount};
              $tail   = $+{tail};
              next if(!$tail); 
              $msg    = substr($tail,0,$ocount);
              push @load, $msg;
              
              if(length($tail) >= $ocount) {
                  $tail = substr($tail,$ocount);
              } 
              else {
                  $tail = substr($tail,length($msg));
              }   
              
              Log3slog ($hash, 5, "Log2Syslog $name -> OCTETCOUNT$i: $ocount"); 
              Log3slog ($hash, 5, "Log2Syslog $name -> MSG$i       : $msg");
              Log3slog ($hash, 5, "Log2Syslog $name -> LENGTH_MSG$i: ".length($msg)); 
              Log3slog ($hash, 5, "Log2Syslog $name -> TAIL$i      : $tail");  
          }
      } 
      else {
          if($uef) {
              push @load, $data;
          }
          else {
              @load = split("[\r\n]",$data);
          }
      }

      for my $line (@load) {
          next if(!$line);      
          ($err,$ignore,$sev,$phost,$ts,$pl) = parsePayload($hash,$line);       
          $hash->{SEQNO}++;
          if($err) {
              $pen = ReadingsVal($name, "Parse_Err_No", 0);
              $pen++;
              readingsSingleUpdate($hash, 'Parse_Err_No', $pen, 1);
              $st = "parse error - see logfile";
          } 
          elsif ($ignore) {
              Log3slog ($hash, 5, "Log2Syslog $name -> dataset was ignored by parseFn");
          } 
          else {
              return if($sevevt && $sevevt !~ m/$sev/x);                                # Message nicht berücksichtigen
              $st = "active";
              if($mevt =~ /intern/) {                                                   # kein Reading, nur Event
                  $pl = "$phost: $pl";
                  Trigger($hash,$ts,$pl);
              } 
              elsif ($mevt =~ /reading/x) {                                           # Reading, Event abhängig von event-on-.*
                  readingsSingleUpdate($hash, "MSG_$phost", $pl, 1);
              } 
              else {                                                                  # Reading ohne Event
                  readingsSingleUpdate($hash, "MSG_$phost", $pl, 0);
              }
          }
          $evt = ($st eq $hash->{HELPER}{OLDSTATE})?0:1;
          readingsSingleUpdate($hash, "state", $st, $evt);
          $hash->{HELPER}{OLDSTATE} = $st; 
      }
  }
      
return;
}

###############################################################################
#                  Daten vom Interface holen 
#
# Die einzige Aufgabe der Instanz mit SERVERSOCKET ist TcpServer_Accept 
# durchzufuehren (und evtl. noch Statistiken). Durch den Accept wird eine 
# weitere Instanz des gleichen Typs angelegt die eine Verbindung repraesentiert 
# und im ReadFn die eigentliche Arbeit macht:
#
# - ohne SERVERSOCKET dafuer mit CD/FD, PEER und PORT. CD/FD enthaelt den 
#   neuen Filedeskriptor.
# - mit TEMPORARY (damit es nicht gespeichert wird)
# - SNAME verweist auf die "richtige" Instanz, damit man die Attribute 
#   abfragen kann.
# - TcpServer_Accept traegt den neuen Filedeskriptor in die globale %selectlist 
#   ein. Damit wird ReadFn von fhem.pl/select mit dem temporaeren Instanzhash 
#   aufgerufen, wenn Daten genau bei dieser Verbindung anstehen.
#   (sSiehe auch "list TYPE=FHEMWEB", bzw. "man -s2 accept")
# 
###############################################################################
sub getIfData {                                       ## no critic 'complexity'
  my $hash           = shift;
  my $len            = shift;
  my $mlen           = shift;
  my $reread         = shift;
  my $name           = $hash->{NAME};
  my $socket         = $hash->{SERVERSOCKET};
  my $protocol       = lc(AttrVal($name, "protocol", "udp"));
  my ($eof,$buforun) = (0,0);
  
  if($hash->{TEMPORARY}) {
      # temporäre Instanz abgelegt durch TcpServer_Accept
      $protocol = "tcp";
  }
  
  my $st = ReadingsVal($name,"state","active");
  my ($data,$ret);
  
  if(!$reread) {
      if($socket && $protocol =~ /udp/) {                    # UDP Datagramm empfangen    
          Log3slog ($hash, 4, "Log2Syslog $name - ####################################################### ");
          Log3slog ($hash, 4, "Log2Syslog $name - #########        new Syslog UDP Receive       ######### ");
          Log3slog ($hash, 4, "Log2Syslog $name - ####################################################### ");      

          unless($socket->recv($data, $len)) {
              Log3slog ($hash, 3, "Log2Syslog $name - Seq \"$hash->{SEQNO}\" invalid data: $data"); 
              $data = '' if(length($data) == 0);
              $st   = "receive error - see logfile";
          } 
          else {
              my $dl = length($data);
              Log3slog ($hash, 5, "Log2Syslog $name - Buffer ".$dl." chars ready to parse:\n$data");
          } 
          return ($st,$data,$hash);  
      
      } elsif ($protocol =~ /tcp/) {
          if($hash->{SERVERSOCKET}) {                               # Accept and create a child
              my $nhash = TcpServer_Accept($hash, "Log2Syslog");
              return ($st,$data,$hash) if(!$nhash);
              $nhash->{CD}->blocking(0);
              if($nhash->{SSL}) {
                  my $sslver  = $nhash->{CD}->get_sslversion();
                  my $sslalgo = $nhash->{CD}->get_fingerprint(); 
                  readingsSingleUpdate($hash, "SSL_Version", $sslver, 1);
                  readingsSingleUpdate($hash, "SSL_Algorithm", $sslalgo, 1);
              }
              return ($st,$data,$hash);
          }
          
          # Child, $hash ist Hash der temporären Instanz, $shash und $sname von dem originalen Device
          my $sname = $hash->{SNAME};
          my $cname = $hash->{NAME};
          my $shash = $defs{$sname};                                # Hash des Log2Syslog-Devices bei temporärer TCP-Serverinstanz 
          my $uef   = AttrVal($sname, "useEOF", 0);
          my $tlsv  = ReadingsVal($sname,"SSL_Version",'');

          Log3slog ($shash, 4, "Log2Syslog $sname - ####################################################### ");
          Log3slog ($shash, 4, "Log2Syslog $sname - #########        new Syslog TCP Receive       ######### ");
          Log3slog ($shash, 4, "Log2Syslog $sname - ####################################################### ");
          Log3slog ($shash, 4, "Log2Syslog $sname - await EOF: $uef, SSL: $tlsv");
          Log3slog ($shash, 4, "Log2Syslog $sname - childname: $cname");
          
          $st   = ReadingsVal($sname,"state","active");
          my $c = $hash->{CD};
          if($c) {
              $shash->{HELPER}{TCPPADDR} = $hash->{PEER};             
              my $buf;
              my $off = 0;
              $ret    = sysread($c, $buf, $len);                    # returns undef on error, 0 at end of file and Integer, number of bytes read on success.                
              
              if(!defined($ret) && $! == EWOULDBLOCK()){            # error
                  $hash->{wantWrite} = 1 if(TcpServer_WantWrite($hash));
                  $hash = $shash;
                  Log3slog ($hash, 2, "Log2Syslog $sname - ERROR - TCP stack error:  $!");   
                  return ($st,undef,$hash);
              } 
              elsif (!$ret) {                                       # EOF or error
                  Log3slog ($shash, 4, "Log2Syslog $sname - Connection closed for $cname: ".(defined($ret) ? 'EOF' : $!));
                  if(!defined($ret)) {                              # error
                      CommandDelete(undef, $cname);
                      $hash = $shash;
                      return ($st,undef,$hash);
                  } 
                  else {                                            # EOF
                      $eof  = 1;
                      $data = $hash->{BUF};
                      CommandDelete(undef, $cname);     
                  }
              }
              
              if(!$eof) {
                  $hash->{BUF} .= $buf;
                  Log3slog ($shash, 5, "Log2Syslog $sname - Add $ret chars to buffer:\n$buf") if($uef && !$hash->{SSL});
              }
              
              if($hash->{SSL} && $c->can('pending')) {
                  while($c->pending()) {
                      sysread($c, $buf, 1024);
                      $hash->{BUF} .= $buf;
                  }
              }
              
              $buforun = (length($hash->{BUF}) >= $mlen)?1:0 if($hash->{BUF});
              
              if(!$uef || $hash->{SSL} || $buforun) {
                  $data = $hash->{BUF};
                  delete $hash->{BUF};
                  $hash = $shash;
                  if($data) {
                      my $dl = length($data); 
                      Log3slog ($shash, 2, "Log2Syslog $sname - WARNING - Buffer overrun ! Enforce parse data.") if($buforun);
                      Log3slog ($shash, 5, "Log2Syslog $sname - Buffer $dl chars ready to parse:\n$data");
                  }
                  return ($st,$data,$hash);
              
              } else {
                  if($eof) {
                      $hash  = $shash;
                      my $dl = length($data); 
                      Log3slog ($shash, 5, "Log2Syslog $sname - Buffer $dl chars after EOF ready to parse:\n$data") if($data);
                      return ($st,$data,$hash);                      
                  }
              }             
          }
          
      } else {
          $st   = "error - no socket opened";
          $data = '';
          return ($st,$data,$hash); 
      }
  }

return ($st,undef,$hash);  
}

###############################################################################
#                Parsen Payload für Syslog-Server
#                (im Collector Model)
###############################################################################
sub parsePayload {                                           ## no critic 'complexity'
  my ($hash,$data) = @_;
  my $name         = $hash->{NAME};
  my $pp           = AttrVal($name, "parseProfile", $hash->{PROFILE});
  my $severity     = "";
  my $facility     = "";  
  my @evf          = split q{,},AttrVal($name, "outputFields", "FAC,SEV,ID,CONT");   # auszugebene Felder im Event/Reading
  my $ignore       = 0;
  my ($to,$Mmm,$dd,$day,$ietf,$err,$pl,$tail);
  
  $data = parseFilter($data) if(AttrVal($name,"useParsefilter",0));                  # Steuerzeichen werden entfernt (Achtung auch CR/LF)

  Log3slog ($hash, 4, "Log2Syslog $name - #########             Parse Message           ######### ");
  Log3slog ($hash, 5, "Log2Syslog $name - parse profile: $pp");
  
  # Hash zur Umwandlung Felder in deren Variablen
  my ($ocount,$prival,$ts,$host,$date,$time,$id,$pid,$mid,$sdfield,$cont);
  my ($fac,$sev,$msec) = ("","","");

  my %fh = (PRIVAL  => \$prival,
            FAC     => \$fac,
            SEV     => \$sev,
            TS      => \$ts,
            HOST    => \$host,
            DATE    => \$date,
            TIME    => \$time,
            ID      => \$id,
            PID     => \$pid,
            MID     => \$mid,
            SDFIELD => \$sdfield,
            CONT    => \$cont,
            DATA    => \$data
           );
  
  my ($phost) = evalPeer($hash);                                                    # Sender Host / IP-Adresse ermitteln, $phost wird Reading im Event
  
  Log3slog ($hash, 4, "Log2Syslog $name - raw message -> $data");
  
  my $year = strftime "%Y", localtime;                                              # aktuelles Jahr
  
  if($pp =~ /^Automatic/x) {
      Log3slog($name, 4, "Log2Syslog $name - Analyze message format automatically ...");
      $pp     = "raw"; 
      $data   =~ /^<(?<prival>\d{1,3})>(?<tail>\w{3}).*$/x;
      $prival = $+{prival};
      $tail   = $+{tail};
      # Test auf BSD-Format
      if($tail && " Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec " =~ /\s$tail\s/x) {
          $pp = "BSD";
      } else {
          # Test auf IETF-Format
          $data   =~ /^((?<ocount>(\d+))\s)?<(?<prival>\d{1,3})>(?<ietf>\d{0,2})\s?(?<date>\d{4}-\d{2}-\d{2})T(?<time>\d{2}:\d{2}:\d{2}).*$/x;
          $ocount = $+{ocount};      # can octet count
          $prival = $+{prival};      # must
          $date   = $+{date};        # must
          $time   = $+{time};        # must             
          $pp     = "IETF" if($prival && $date && $time);
      }
      if($pp ne "raw") {
          $hash->{PROFILE} = "Automatic - detected format: $pp";
          Log3slog($name, 4, "Log2Syslog $name - Message format \"$pp\" detected. Try Parsing ... ");
      } else {
          Log3slog($name, 2, "Log2Syslog $name - WARNING - no message format is detected (see reading \"Parse_Err_LastData\"), \"raw\" is used instead. You can specify the correct profile by attribute \"parseProfile\" !");
          readingsSingleUpdate($hash, "Parse_Err_LastData", $data, 0);
      }
  }
  
  if($pp =~ /raw/) {
      $ts = TimeNow();
      $pl = $data;
  
  } elsif ($pp eq "BSD") { 
      # BSD Protokollformat https://tools.ietf.org/html/rfc3164
      # Beispiel data "<$prival>$month $day $time $myhost $id: $otp"
      $data   =~ /^<(?<prival>\d{1,3})>(?<tail>.*)$/x;
      $prival = $+{prival};        # must
      $tail   = $+{tail}; 
      $tail   =~ /^((?<month>\w{3})\s+(?<day>\d{1,2})\s+(?<time>\d{2}:\d{2}:\d{2}))?\s+(?<tail>.*)$/x;
      $Mmm    = $+{month};         # can
      $dd     = $+{day};           # can
      $time   = $+{time};          # can
      $tail   = $+{tail};  
      if( $Mmm && $dd && $time ) {
          my $month = $Log2Syslog_BSDMonth{$Mmm};
          $day      = sprintf("%02d",$dd);   
          $ts       = "$year-$month-$day $time";
      }      
      if($ts) {
          # Annahme: wenn Timestamp gesetzt, wird der Rest der Message ebenfalls dem Standard entsprechen
          $tail =~ /^(?<host>[^\s]*)?\s(?<tail>.*)$/x;
          $host = $+{host};          # can 
          $tail = $+{tail};
          # ein TAG-Feld (id) ist so aufgebaut->  sshd[27010]:
          $tail =~ /^((?<id>(\w+\[\w+\])):)?\s(?<cont>(.*))$/x; 
          $id   = $+{id};            # can
          if($id) {
              $id   = substr($id,0, ($RFC3164len{TAG}-1));           # Länge TAG-Feld nach RFC begrenzen
              $cont = $+{cont};      # can
          } else {
              $cont = $tail;
          }
      } else {
          # andernfalls eher kein Standardaufbau
          $cont = $tail;
      }

      if(!$prival) {
          $err = 1;
          Log3slog ($hash, 2, "Log2Syslog $name - ERROR parse msg -> $data");  
      } else {
          $cont =~ s/^(:\s*)(.*)$/$2/x;
          if(looks_like_number($prival)) {
              $facility = int($prival/8) if($prival >= 0 && $prival <= 191);
              $severity = $prival-($facility*8);
              $fac      = $Log2Syslog_Facility{$facility};
              $sev      = $Log2Syslog_Severity{$severity};
          } else {
              $err = 1;
              Log3slog ($hash, 1, "Log2Syslog $name - ERROR parse msg -> $data"); 
              readingsSingleUpdate($hash, "Parse_Err_LastData", $data, 0);              
          }
          
          $host  = "" if(!$host || $host eq "-");           
          Log3slog($name, 4, "$name - parsed message -> FAC: ".($fac // '').", SEV: ".($sev // '').", TS: ".($ts // '').", HOST: ".($host // '').", ID: ".($id // '').", CONT: ".($cont // ''));
          $phost = $host if($host);
          
          # Payload zusammenstellen für Event/Reading
          $pl = "";
          my $i = 0;
          for my $f (@evf) {
              if(${$fh{$f}}) { 
                  $pl .= " || " if($i);
                  $pl .= "$f: ".${$fh{$f}};
                  $i++;
              }
          }
      }
      
  } elsif ($pp eq "IETF") {
      # IETF Protokollformat https://tools.ietf.org/html/rfc5424 
      # Beispiel data "<14>1 2018-08-09T21:45:08+02:00 SDS1 Connection - - [synolog@6574 synotype="Connection" luser="apiuser" event="User [apiuser\] logged in from [192.168.2.45\] via [DSM\]."][meta sequenceId="1"] ﻿apiuser: User [apiuser] logged in from [192.168.2.45] via [DSM].";
      # $data =~ /^<(?<prival>\d{1,3})>(?<ietf>\d+)\s(?<date>\d{4}-\d{2}-\d{2})T(?<time>\d{2}:\d{2}:\d{2})\S*\s(?<host>\S*)\s(?<id>\S*)\s(?<pid>\S*)\s(?<mid>\S*)\s(?<sdfield>(\[.*?(?!\\\]).\]|-))\s(?<cont>.*)$/;
      $data   =~ /^((?<ocount>(\d+))\s)?<(?<prival>\d{1,3})>(?<ietf>\d{0,2})\s(?<cont>.*)$/x;
      $ocount = $+{ocount};      # can (octet count)
      $prival = $+{prival};      # must
      $ietf   = $+{ietf};        # should      
      if($ocount) {
          use bytes;
          $data = substr($data,1+length($ocount),$ocount);
          Log3slog ($hash, 4, "Log2Syslog $name - IETF second level Octet Count Datagramm detected...");
          Log3slog ($hash, 4, "Log2Syslog $name - OCTETCOUNT: $ocount");
          Log3slog ($hash, 4, "Log2Syslog $name - MSG       : $data");
      }
      
      if($prival && $ietf) {
          # Standard IETF-Syslog incl. VERSION
          if($ietf == 1) {
              $data    =~ /^<(?<prival>\d{1,3})>(?<ietf>\d{0,2})\s?(?<date>\d{4}-\d{2}-\d{2})T(?<time>\d{2}:\d{2}:\d{2})(?<msec>\.\d+)?(?<to>\S*)?\s(?<host>\S*)\s(?<id>\S*)\s?(?<pid>\S*)\s?(?<mid>\S*)\s?(?<sdfield>(\[.*?(?!\\\]).\]|-))\s(?<cont>.*)$/x;
              $prival  = $+{prival};      # must
              $ietf    = $+{ietf};        # should
              $date    = $+{date};        # must
              $time    = $+{time};        # must
              $msec    = $+{msec};        # can
              $to      = $+{to};          # Time Offset (UTC etc.) 
              $host    = $+{host};        # should 
              $id      = $+{id};          # should
              $pid     = $+{pid};         # should
              $mid     = $+{mid};         # should 
              $sdfield = $+{sdfield};     # must
              $cont    = $+{cont};        # should
          } else {
              $err = 1;
              Log3slog ($hash, 1, "Log2Syslog $name - new IETF version detected, inform Log2Syslog Maintainer");          
          }
      } else {
          # IETF-Syslog ohne VERSION
          $data    =~ /^<(?<prival>\d{1,3})>(?<date>\d{4}-\d{2}-\d{2})T(?<time>\d{2}:\d{2}:\d{2})(?<msec>\.\d+)?(?<to>\S*)?\s(?<host>\S*)\s(?<id>\S*)\s?(?<pid>\S*)\s?(?<mid>\S*)\s?(?<sdfield>(\[.*?(?!\\\]).\]|-))?\s(?<cont>.*)$/x;
          $prival  = $+{prival};      # must
          $date    = $+{date};        # must
          $time    = $+{time};        # must
          $msec    = $+{msec};        # can
          $to      = $+{to};          # Time Offset (UTC etc.) 
          $host    = $+{host};        # should 
          $id      = $+{id};          # should
          $pid     = $+{pid};         # should
          $mid     = $+{mid};         # should 
          $sdfield = $+{sdfield};     # should
          $cont    = $+{cont};        # should                        
      }      
      
      if(!$prival || !$date || !$time) {
          $err = 1;
          Log3slog ($hash, 2, "Log2Syslog $name - ERROR parse msg -> $data");          
          Log3slog ($hash, 5, "Log2Syslog $name - parsed fields -> PRI: ".($prival // '').", IETF: ".($ietf // '').", DATE: ".($date // '').", TIME: ".($time // '').", OFFSET: ".($to // '').", HOST: ".($host // '').", ID: ".($id // '').", PID: ".($pid // '').", MID: ".($mid // '').", SDFIELD: ".($sdfield // '').", CONT: ".($cont // ''));        
          readingsSingleUpdate($hash, "Parse_Err_LastData", $data, 0);
      } else {
          $ts = getTimeFromOffset ($name,$to,$date,$time,$msec);
      
          if(looks_like_number($prival)) {
              $facility = int($prival/8) if($prival >= 0 && $prival <= 191);
              $severity = $prival-($facility*8);
              $fac      = $Log2Syslog_Facility{$facility};
              $sev      = $Log2Syslog_Severity{$severity};
          } else {
              $err = 1;
              Log3slog ($hash, 2, "Log2Syslog $name - ERROR parse msg -> $data");          
          }
      
          # Längenbegrenzung nach RFC5424
          $id   = substr($id,0,   ($RFC5425len{ID}-1));
          $pid  = substr($pid,0,  ($RFC5425len{PID}-1));
          $mid  = substr($mid,0,  ($RFC5425len{MID}-1));
          $host = substr($host,0, ($RFC5425len{HST}-1));
      
          $host  = "" if(!$host || $host eq "-");           
          Log3slog($name, 4, "$name - parsed message -> FAC: ".($fac // '').", SEV: ".($sev // '').", TS: ".($ts // '').", HOST: ".($host // '').", ID: ".($id // '').", CONT: ".($cont // ''));
          $phost = $host if($host);
          
          # Payload zusammenstellen für Event/Reading
          $pl   = "";
          my $i = 0;
          for my $f (@evf) {
              if(${$fh{$f}}) { 
                  $pl .= " || " if($i);
                  $pl .= "$f: ".${$fh{$f}};
                  $i++;
              }
          }          
      }
  
  } elsif ($pp eq "TPLink-Switch") {
      # Parser für TPLink Switch
      # Beispiel data "<131>2018-08-10 09:03:58 10.0.x.y 31890 Login the web by admin on web (10.0.x.y).";
      $data   =~ /^<(?<prival>\d{1,3})>(?<date>\d{4}-\d{2}-\d{2})\s(?<time>\d{2}:\d{2}:\d{2})\s(?<host>\S*)\s(?<id>\S*)\s(?<cont>.*)$/x;
      $prival = $+{prival};      # must
      $date   = $+{date};        # must
      $time   = $+{time};        # must
      $host   = $+{host};        # should 
      $id     = $+{id};          # should
      $cont   = $+{cont};        # should
      
      if(!$prival || !$date || !$time) {
          $err = 1;
          Log3slog ($hash, 2, "Log2Syslog $name - ERROR parse msg -> $data");           
      } else {
          $ts = "$date $time";
      
          if(looks_like_number($prival)) {
              $facility = int($prival/8) if($prival >= 0 && $prival <= 191);
              $severity = $prival-($facility*8);
              $fac      = $Log2Syslog_Facility{$facility};
              $sev      = $Log2Syslog_Severity{$severity};
          } else {
              $err = 1;
              Log3slog ($hash, 2, "Log2Syslog $name - ERROR parse msg -> $data");
              readingsSingleUpdate($hash, "Parse_Err_LastData", $data, 0);              
          }
            
          $host  = "" if(!$host || $host eq "-");           
          Log3slog($name, 4, "$name - parsed message -> FAC: ".($fac // '').", SEV: ".($sev // '').", TS: ".($ts // '').", HOST: ".($host // '').", ID: ".($id // '').", CONT: ".($cont // ''));
          $phost = $host if($host);
          
          # Payload zusammenstellen für Event/Reading
          $pl   = "";
          my $i = 0;
          for my $f (@evf) {
              if(${$fh{$f}}) { 
                  $pl .= " || " if($i);
                  $pl .= "$f: ".${$fh{$f}};
                  $i++;
              }
          }          
      }
  
  } elsif ($pp eq "UniFi") {
      # Parser UniFi Controller Syslog (BSD Format) und Netconsole Messages, getestet mit UniFi AP-AC-Lite
      # Bsp raw message -> <30>Apr  1 14:28:56 U7LT,18e829a6549a,v4.0.80.10875: hostapd: ath0: STA 3c:71:bf:2c:80:7d RADIUS: starting accounting session EC85E55866B13F6F
      $ts     = TimeNow();
      $data   =~ /^<(?<prival>\d{1,3})>((?<month>\w{3})\s+(?<day>\d{1,2})\s+(?<time>\d{2}:\d{2}:\d{2}))?\s+(?<host>[^\s]*)?\s((:)?(?<id>([^:]*)):)?(?<cont>.*)$/x;
      $prival = $+{prival};                      
      if($prival) {                                                      # Syslog-Message
          $Mmm  = $+{month};      
          $dd   = $+{day};          
          $time = $+{time};
          $id   = $+{id};
          $host = $+{host};                                              # Host enthält MAC-Adresse und Softwareversion       
          $cont = $+{cont}; 
          $id   = substr($id,0, ($RFC3164len{TAG}-1)) if($id);           # Länge TAG-Feld nach RFC begrenzen  
          $host =~ s/^(.*):$/$1/xe if($host);                            # ":" am Ende exen
          if($Mmm && $dd && $time) {
              my $month = $Log2Syslog_BSDMonth{$Mmm};
              $day      = sprintf("%02d",$dd);
              $ts       = "$year-$month-$day $time";
          }
          
      } else {
          $prival = "62";                                                # Netconsole Message: Nachbau -> SEV (7*8)+6, FAC: System (Netconsole Logserver)
          $cont   = $data;
      }
      
      if(!$prival) {
          $err = 1;
          Log3slog ($hash, 2, "Log2Syslog $name - ERROR parse msg -> $data");   
          readingsSingleUpdate($hash, "Parse_Err_LastData", $data, 0);          
      
      } else {      
          if(looks_like_number($prival)) {
              $facility = int($prival/8) if($prival >= 0 && $prival <= 191);
              $severity = $prival-($facility*8);
              $fac      = $Log2Syslog_Facility{$facility};
              $sev      = $Log2Syslog_Severity{$severity};
          } else {
              $err = 1;
              Log3slog ($hash, 2, "Log2Syslog $name - ERROR: PRIVAL not number -> $data");          
          }
           
          $host = "" if(!$host || $host eq "-");           
          Log3slog($name, 4, "$name - parsed message -> FAC: ".($fac // '').", SEV: ".($sev // '').", TS: ".($ts // '').", HOST: ".($host // '').", ID: ".($id // '').", CONT: ".($cont // ''));
          # $phost = $host if($host);                                   # kein $host setzen da $host nicht Standard Name (s.o.)
          
          # Payload zusammenstellen für Event/Reading
          $pl   = "";
          my $i = 0;
          for my $f (@evf) {
              if(${$fh{$f}}) { 
                  $pl .= " || " if($i);
                  $pl .= "$f: ".${$fh{$f}};
                  $i++;
              }
          }          
      }
  
  } elsif ($pp eq "ParseFn") {                                          # user spezifisches Parsing
      my $parseFn = AttrVal( $name, "parseFn", "" );
      $ts         = TimeNow();
      
      if( $parseFn =~ m/^\s*(\{.*\})\s*$/sx ) {
          $parseFn = $1;
      } else {
          $parseFn = '';
      }
  
      if($parseFn ne '') {
          my $PRIVAL  = "";
          my $TS      = $ts;
          my $DATE    = "";
          my $TIME    = "";
          my $HOST    = "";
          my $ID      = "";
          my $PID     = "";
          my $MID     = "";
          my $CONT    = "";
          my $FAC     = "";
          my $SEV     = "";
          my $DATA    = $data;
          my $SDFIELD = "";
          my $IGNORE  = 0;

          eval $parseFn;                                        ## no critic 'eval'
          if($@) {
              Log3slog ($hash, 2, "Log2Syslog $name -> error parseFn: $@"); 
              $err = 1;
          }
                 
          $prival  = $PRIVAL  if($PRIVAL =~ /\d{1,3}/x);
          $date    = $DATE    if($DATE   =~ /^(\d{4})-(\d{2})-(\d{2})$/x);
          $time    = $TIME    if($TIME   =~ /^(\d{2}):(\d{2}):(\d{2})$/x);          
          $ts      = ($TS =~ /^(\d{4})-(\d{2})-(\d{2})\s(\d{2}):(\d{2}):(\d{2})$/x) ? $TS : ($date && $time) ? "$date $time" : $ts;
          $host    = $HOST    if(defined $HOST);
          $id      = $ID      if(defined $ID);
          $pid     = $PID     if(defined $PID);
          $mid     = $MID     if(defined $MID);
          $cont    = $CONT    if(defined $CONT);
          $fac     = $FAC     if(defined $FAC);
          $sev     = $SEV     if(defined $SEV);
          $sdfield = $SDFIELD if(defined $SDFIELD);
          $ignore  = $IGNORE  if($IGNORE =~ /\d/x);
          
          if($prival && looks_like_number($prival)) {
              $facility = int($prival/8) if($prival >= 0 && $prival <= 191);
              $severity = $prival-($facility*8);
              $fac      = $Log2Syslog_Facility{$facility};
              $sev      = $Log2Syslog_Severity{$severity};
          } else {
              $err = 1;
              Log3slog ($hash, 2, "Log2Syslog $name - ERROR parse msg -> $data");
              readingsSingleUpdate($hash, "Parse_Err_LastData", $data, 0);              
          }

          Log3slog ($name, 4, "Log2Syslog $name - parsed message -> FAC: $fac, SEV: $sev, TS: $ts, HOST: $host, ID: $id, PID: $pid, MID: $mid, CONT: $cont");
          $phost = $host if($host);                           
          
          # auszugebene Felder im Event/Reading
          my $ef = "PRIVAL,FAC,SEV,TS,HOST,DATE,TIME,ID,PID,MID,SDFIELD,CONT"; 
          @evf   = split(",",AttrVal($name, "outputFields", $ef));    
          
          # Payload zusammenstellen für Event/Reading
          $pl   = "";
          my $i = 0;
          for my $f (@evf) {
              if(${$fh{$f}}) { 
                  $pl .= " || " if($i);
                  $pl .= "$f: ".${$fh{$f}};
                  $i++;
              }
          }           
      
      } else {
          $err = 1;
          Log3slog ($hash, 1, "Log2Syslog $name - no parseFn defined."); 
      }
  
  } elsif ($pp eq "unknown") { 
      $err = 1;
      Log3slog ($hash, 1, "Log2Syslog $name - Message format could not be detected automatically. PLease check and set attribute \"parseProfile\" manually.");   
      readingsSingleUpdate($hash, "Parse_Err_LastData", $data, 0);
  }

return ($err,$ignore,$sev,$phost,$ts,$pl);
}

################################################################
#   Berechne Zeit vom Offset (Empfang) 
#   Offset     = local Time - UTC
#   local Time = Offset     + UTC  
#   UTC        = local time - Offset
#
#   Übergabe: $to, $date, $time
#   $to    = Offset (z.B. +02:00)
#   $date  = Datum YYYY-MM-DD
#   $time  = HH:MM:SS
#
################################################################
sub getTimeFromOffset {
 my ($name,$to,$date,$time,$msec) = @_;
 
 my $dt = "$date $time";
 return ($dt) if(!$to);
 
 my $tz = AttrVal($name, "timeSpec", "Local");
 
 my ($year,$month,$mday) = $date =~ /(\d{4})-(\d{2})-(\d{2})/x;
 return $dt if(!$year || !$month || !$mday);
 my ($hour,$min,$sec)    = $time =~ /(\d{2}):(\d{2}):(\d{2})/x;
 return $dt if(!$hour || !$min || !$sec);
 
 $year -= 1900;
 $month--;
 
 my ($offset,$utc);
 my $localts = fhemTimeLocal($sec, $min, $hour, $mday, $month, $year);
 $localts   .= $msec if($msec && $msec =~ /^\.\d+/x);

 if($to =~ /Z/ && $tz ne "UTC") {                      # Zulu Time wurde geliefert -> Umrechnung auf Local
     $offset = fhemTzOffset($localts);                 # Offset zwischen Localtime und UTC
     $utc    = $localts - $offset;
     $dt     = strftime ("%Y-%m-%d %H:%M:%S", localtime($utc));
 }
 
 if($to =~ /[+-:0-9]/x) {
     my $sign  = substr($to, 0, 1);
     $to       = substr $to, 1;
     my($h,$m) = split(":", $to);
     $offset   = 3600*$h + 60*$m;
     
     if($tz eq "UTC") {
         $utc = $localts - $offset;
     
     } else {
         $utc = $localts - $offset + fhemTzOffset($localts);       
     }
     $dt = strftime ("%Y-%m-%d %H:%M:%S", localtime($utc));  
 }
 
 Log3slog ($defs{$name}, 4, "Log2Syslog $name - module time zone: $tz, converted time: $dt"); 
 
return ($dt);
}  

#################################################################################################
#                       Syslog Collector Events erzeugen
#                       (im Collector Model)
#################################################################################################
sub Trigger {
  my ($hash,$ts,$pl) = @_;
  my $name           = $hash->{NAME};
  my $no_replace     = 1;                     # Ersetzung von Events durch das Attribut eventMap verhindern
  
  if($hash->{CHANGED}) {
      push @{$hash->{CHANGED}}, $pl;
  } else {
      $hash->{CHANGED}[0] = $pl;
  }
  
  if($hash->{CHANGETIME}) {
      push @{$hash->{CHANGETIME}}, $ts;
  } else {
      $hash->{CHANGETIME}[0] = $ts;
  }

  my $ret = DoTrigger($name, undef, $no_replace);
  
return;
}

###############################################################################
#               Undef Funktion
###############################################################################
sub Undef {
  my ($hash, $name) = @_;
  
  RemoveInternalTimer($hash);
  
  closeSocket ($hash,1);            # Clientsocket schließen 
  downServer($hash,1);              # Serversocket schließen, kill children

return;
}

###############################################################################
#                         Collector-Socket schließen
###############################################################################
sub downServer {
  my ($hash,$delchildren) = @_;
  my $name                = $hash->{NAME};
  my $port                = $hash->{PORT};
  my $protocol            = $hash->{PROTOCOL};
  my $ret;
  
  return if(!$hash->{SERVERSOCKET} || $hash->{MODEL} !~ /Collector/);
  Log3slog ($hash, 3, "Log2Syslog $name - Closing server socket $protocol/$port ...");
  
  if($protocol =~ /tcp/) {
      TcpServer_Close($hash);
      delete($hash->{CONNECTS});
      delete($hash->{SERVERSOCKET});
      
      if($delchildren) {
          my @children = devspec2array($name."_.*");
          for my $child (@children) {
              if($child ne $name."_.*") {
                  CommandDelete(undef, $child); 
                  Log3slog ($hash, 3, "Log2Syslog $name - child instance $child deleted."); 
              }
          }
          delete($hash->{HELPER}{SSLALGO});
          delete($hash->{HELPER}{SSLVER});
          readingsSingleUpdate($hash, "SSL_Version", "n.a.", 1);
          readingsSingleUpdate($hash, "SSL_Algorithm", "n.a.", 1);
      }
      return;
  }
  
  $ret = $hash->{SERVERSOCKET}->close();  
  
  Log3slog ($hash, 1, "Log2Syslog $name - Can't close Syslog Collector at port $port: $!") if(!$ret);
  delete($hash->{SERVERSOCKET});
  delete($selectlist {"$name.$port"});
  delete($readyfnlist{"$name.$port"});
  delete($hash->{FD});
  
return; 
}

###############################################################################
#               Delete Funktion
###############################################################################
sub Delete {
  my ($hash, $arg) = @_;
  
  delete $logInform{$hash->{NAME}};
  
return;
}

###############################################################################
#              Set
###############################################################################
sub Set {
  my ($hash, @a) = @_;
  my $name       = $a[0];
  return qq{"set $name" needs at least one argument} if ( @a < 2 );
  my $opt  = $a[1];
  my $prop = $a[2];
  
  my $setlist = "Unknown argument $opt, choose one of ".
                "reopen:noArg ".
                (($hash->{MODEL} =~ /Sender/)?"sendTestMessage ":"")
                ;
  
  return if(AttrVal($name, "disable", "") eq "1");
  
  if($opt =~ /sendTestMessage/) {
      my $own;
      if ($prop) {
          shift @a;
          shift @a;
          $own = join(" ",@a);     
      }
      sendTestMsg($hash,$own);
  
  } elsif($opt =~ /reopen/) {
        $hash->{HELPER}{MEMLOCK} = 1;
        InternalTimer(gettimeofday()+2, "FHEM::Log2Syslog::deleteMemLock", $hash, 0);     
        
        closeSocket ($hash,1);                                                                 # Clientsocket schließen
        downServer  ($hash,1);                                                                 # Serversocket schließen     
        if($hash->{MODEL} =~ /Collector/) {                                                    # Serversocket öffnen
            InternalTimer(gettimeofday()+0.5, "FHEM::Log2Syslog::deleteMemLock", $hash, 0);  
            readingsSingleUpdate ($hash, 'Parse_Err_No', 0, 1);                                # Fehlerzähler für Parse-Errors auf 0    
            readingsSingleUpdate ($hash, 'Parse_Err_LastData', 'n.a.', 0);
        }
        
  } else {
      return "$setlist";
  }  
  
return;
}

###############################################################################
#                                    Get
###############################################################################
sub Get {                                             ## no critic 'complexity'
  my ($hash, @a) = @_;
  return "\"get X\" needs at least an argument" if ( @a < 2 );
  my $name    = $a[0];
  my $opt     = $a[1];
  my $prop    = $a[2];
  my $getlist = "Unknown argument $opt, choose one of ".
                (($hash->{MODEL} !~ /Collector/)?"certInfo:noArg ":"").
                "versionNotes "
                ;

  return if(AttrVal($name, "disable", "") eq "1");
  
  my $st;
  
  my($sock,$cert);
  if ($opt =~ /certInfo/) {
      if(ReadingsVal($name,"SSL_Version","n.a.") ne "n.a.") {
          ($sock,$st) = openSocket($hash,0);
          if($sock) {
              $cert = $sock->dump_peer_certificate();
          }
      }
      return $cert if($cert);
      return "no SSL session has been created";
      
  } elsif ($opt =~ /versionNotes/) {
      my $header  = "<b>Module release information</b><br>";
      my $header1 = "<b>Helpful hints</b><br>";
      my %hs;
  
      # Ausgabetabelle erstellen
      my ($ret,$val0,$val1);
      my $i = 0;
  
      $ret  = "<html>";
  
      # Hints
      if(!$prop || $prop =~ /hints/i || $prop =~ /[\d]+/x) {
          $ret .= sprintf("<div class=\"makeTable wide\"; style=\"text-align:left\">$header1 <br>");
          $ret .= "<table class=\"block wide internals\">";
          $ret .= "<tbody>";
          $ret .= "<tr class=\"even\">";  
          if($prop && $prop =~ /[\d]+/x) {
              my @hints = split q{,},$prop;
              foreach (@hints) {
                  if(AttrVal("global","language","EN") eq "DE") {
                      $hs{$_} = $vHintsExt_de{$_};
                  } else {
                      $hs{$_} = $vHintsExt_en{$_};
                  }
              }                      
          } else {
              if(AttrVal("global","language","EN") eq "DE") {
                  %hs = %vHintsExt_de;
              } else {
                  %hs = %vHintsExt_en; 
              }
          }          
          $i = 0;
          for my $key (sortVersion("desc",keys %hs)) {
              $val0 = $hs{$key};
              $ret .= sprintf("<td style=\"vertical-align:top\"><b>$key</b>  </td><td style=\"vertical-align:top\">$val0</td>" );
              $ret .= "</tr>";
              $i++;
              if ($i & 1) {
                  # $i ist ungerade
                  $ret .= "<tr class=\"odd\">";
              } else {
                  $ret .= "<tr class=\"even\">";
              }
          }
          $ret .= "</tr>";
          $ret .= "</tbody>";
          $ret .= "</table>";
          $ret .= "</div>";
      }
  
      # Notes
      if(!$prop || $prop =~ /rel/i) {
          $ret .= sprintf("<div class=\"makeTable wide\"; style=\"text-align:left\">$header <br>");
          $ret .= "<table class=\"block wide internals\">";
          $ret .= "<tbody>";
          $ret .= "<tr class=\"even\">";
          $i = 0;
          for my $key (sortVersion("desc",keys %vNotesExtern)) {
              ($val0,$val1) = split q{\s+},$vNotesExtern{$key},2;
              $ret         .= sprintf("<td style=\"vertical-align:top\"><b>$key</b>  </td><td style=\"vertical-align:top\">$val0  </td><td>$val1</td>" );
              $ret         .= "</tr>";
              $i++;
              if ($i & 1) {                             # $i ist ungerade
                  $ret .= "<tr class=\"odd\">";
              } else {
                  $ret .= "<tr class=\"even\">";
              }
          }
          $ret .= "</tr>";
          $ret .= "</tbody>";
          $ret .= "</table>";
          $ret .= "</div>";
      }
  
      $ret .= "</html>";
                
      return $ret;
  
  } else {
      return "$getlist";
  } 
  
return;
}

###############################################################################
#      Attr
###############################################################################
sub Attr {                                            ## no critic 'complexity'
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash = $defs{$name};
    my ($do,$st);
      
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value

    if ($cmd eq "set" && $hash->{MODEL} !~ /Collector/x && $aName =~ /parseProfile|parseFn|outputFields|makeEvent|useParsefilter/x) {
         return qq{"$aName" is only valid for model "Collector"};
    }
    
    if ($cmd eq "set" && $hash->{MODEL} =~ /Collector/x && $aName =~ /addTimestamp|contDelimiter|addStateEvent|logFormat|octetCount|ssldebug|timeout|exclErrCond/x) {
         return qq{"$aName" is only valid for model "Sender"};
    }
    
    if ($aName eq "disable") {
        if($cmd eq "set") {
            return qq{Mode "$aVal" is only valid for model "Sender"} if($aVal eq "maintenance" && $hash->{MODEL} !~ /Sender/);
            $do = $aVal?1:0;
        }
        
        $do = 0 if($cmd eq "del");
        $st = ($do&&$aVal=~/maintenance/)?"maintenance":($do&&$aVal==1)?"disabled":"initialized";
        
        $hash->{HELPER}{MEMLOCK} = 1;
        InternalTimer(gettimeofday()+2, "FHEM::Log2Syslog::deleteMemLock", $hash, 0);
        
        if($do==0 || $aVal=~/maintenance/) {
            if($hash->{MODEL} =~ /Collector/) {
                downServer($hash,1);                                                 # Serversocket schließen und wieder öffnen
                InternalTimer(gettimeofday()+0.5, "FHEM::Log2Syslog::initServer", "$name,global", 0);                 
            } 
        } 
        else {
            closeSocket($hash,1);                                                    # Clientsocket schließen 
            downServer ($hash);                                                      # Serversocket schließen
        }
        readingsSingleUpdate ($hash, 'state', $st, 1);        
    }
    
    if ($aName eq "TLS") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
        
        if ($do == 0) {
            delete $hash->{SSL};
        } 
        else {
            if($hash->{MODEL} =~ /Collector/) {
                $attr{$name}{protocol} = "TCP" if(AttrVal($name, "protocol", "UDP") ne "TCP");
                TcpServer_SetSSL($hash);
            }
        }
        $hash->{HELPER}{MEMLOCK} = 1;
        InternalTimer(gettimeofday()+2, "FHEM::Log2Syslog::deleteMemLock", $hash, 0);     
        
        closeSocket($hash,1);                                                        # Clientsocket schließen
        downServer ($hash,1);                                                        # Serversocket schließen     
        
        if($hash->{MODEL} =~ /Collector/) {
            InternalTimer(gettimeofday()+0.5, "FHEM::Log2Syslog::initServer", "$name,global", 0);  # Serversocket öffnen
            readingsSingleUpdate ($hash, 'Parse_Err_No', 0, 1);                                    # Fehlerzähler für Parse-Errors auf 0
        }              
    }
    
    if ($aName =~ /rateCalcRerun/) {
        unless ($aVal =~ /^[0-9]+$/x) { return "Value of $aName is not valid. Use only figures 0-9 without decimal places !";}
        return qq{Value of "$aName" must be >= 60. Please correct it} if($aVal < 60);
        RemoveInternalTimer($hash, "FHEM::Log2Syslog::calcTrate");
        InternalTimer(gettimeofday()+5, "FHEM::Log2Syslog::calcTrate", $hash, 0);
    }
    
    if ($cmd eq "set") {
        if($aName =~ /port/) {
            if($aVal !~ m/^\d+$/x) { return " The Value of \"$aName\" is not valid. Use only figures !";}
            
            $hash->{HELPER}{MEMLOCK} = 1;
            InternalTimer(gettimeofday()+2, "FHEM::Log2Syslog::deleteMemLock", $hash, 0);
            
            if($hash->{MODEL} =~ /Collector/ && $init_done) {
                return qq{$aName "$aVal" is not valid because off privileged ports are only usable by super users. Use a port number grater than 1023.} if($aVal < 1024);
                downServer($hash,1);                                                               # Serversocket schließen
                InternalTimer(gettimeofday()+0.5, "FHEM::Log2Syslog::initServer", "$name,global", 0);
                readingsSingleUpdate ($hash, 'Parse_Err_No', 0, 1);                                # Fehlerzähler für Parse-Errors auf 0
            } elsif ($hash->{MODEL} !~ /Collector/) {
                closeSocket($hash,1);                                                              # Clientsocket schließen               
            }
        }
        
        if($aName =~ /timeout/) {
            if($aVal !~ m/^\d+(.\d+)?$/x) { return qq{The value of "$aName" is not valid. Use only integer or fractions of numbers like "0.7".}; }
        }
    }
    
    if ($aName =~ /protocol/) {
        if($aVal =~ /UDP/) {
            $attr{$name}{TLS} = 0 if(AttrVal($name, "TLS", 0));        
        }
        $hash->{HELPER}{MEMLOCK} = 1;
        InternalTimer(gettimeofday()+2, "FHEM::Log2Syslog::deleteMemLock", $hash, 0);
        
        if($hash->{MODEL} eq "Collector") {
            downServer($hash,1);                                                               # Serversocket schließen
            InternalTimer(gettimeofday()+0.5, "FHEM::Log2Syslog::initServer", "$name,global", 0);
            readingsSingleUpdate ($hash, 'Parse_Err_No', 0, 1);                                # Fehlerzähler für Parse-Errors auf 0
            readingsSingleUpdate ($hash, 'Parse_Err_LastData', 'n.a.', 0);
        } else {
            closeSocket($hash,1);                                                              # Clientsocket schließen  
        }
    }
    
    if ($cmd eq "set" && $aName =~ /parseFn/) {
         return qq{The function syntax is wrong. "$aName" must be enclosed by "{...}".} if($aVal !~ m/^\{.*\}$/sx);
         my %specials = (
             "%IGNORE"  => "0",
             "%DATA"    => "1",
             "%PRIVAL"  => "1",
             "%TS"      => "1",
             "%DATE"    => "1",
             "%TIME"    => "1",
             "%HOST"    => "1",
             "%ID"      => "1",
             "%PID"     => "1",
             "%MID"     => "1",
             "%CONT"    => "1",
             "%FAC"     => "1",
             "%SDFIELD" => "1",
             "%SEV"     => "1"
         );
         my $err = perlSyntaxCheck($aVal, %specials);
         return $err if($err);
    }
    
    if ($aName =~ /parseProfile/) {
          if ($cmd eq "set" && $aVal =~ /ParseFn/) {
              return qq{You have to define a parse-function via attribute "parseFn" first !} if(!AttrVal($name,"parseFn",""));
          }
          if ($cmd eq "set") {
              $hash->{PROFILE} = $aVal;
          } else {
              $hash->{PROFILE} = "Automatic";
          }
          readingsSingleUpdate ($hash, 'Parse_Err_No', 0, 1);                                              # Fehlerzähler für Parse-Errors auf 0
          readingsSingleUpdate ($hash, 'Parse_Err_LastData', 'n.a.', 0);  
    }
    
    if ($cmd eq "del" && $aName =~ /parseFn/ && AttrVal($name,"parseProfile","") eq "ParseFn" ) {
          return qq{You use a parse-function via attribute "parseProfile". Please change/delete attribute "parseProfile" first !};
    }
    
    if ($aName =~ /makeEvent/) {
        for my $key(keys%{$defs{$name}{READINGS}}) {
            delete($defs{$name}{READINGS}{$key}) if($key !~ /state|Transfered_logs_per_minute|SSL_.*|Parse_.*/x);
        }
    }    
    
return;
}

###############################################################
#               Log2Syslog DbLog_splitFn
###############################################################
sub DbLogSplit {
  my ($event, $device) = @_;
  my $devhash = $defs{$device};
  my ($reading, $value, $unit);

  # sds1.myds.me: <14>Jul 19 21:16:58 SDS1 Connection: User [Heiko] from [SFHEIKO1(192.168.2.205)] via [CIFS(SMB3)] accessed shared folder [photo].
  ($reading,$value) = split(/: /x,$event,2);
  $unit             = "";
  
return ($reading, $value, $unit);
}

#################################################################################
#                               Eventlogging
#################################################################################
sub eventLog {                                          ## no critic 'complexity'
  # $hash is my entry, $dev is the entry of the changed device
  my ($hash,$dev) = @_;
  my $name    = $hash->{NAME};
  my $rex     = $hash->{HELPER}{EVNTLOG};
  my $st      = ReadingsVal($name,"state","active");
  my $sendsev = AttrVal($name, "respectSeverity", "");              # Nachrichten welcher Schweregrade sollen gesendet werden
  my $uef     = AttrVal($name, "useEOF", 0);
  my ($prival,$data,$sock,$pid,$sevAstxt);
  
  if(IsDisabled($name)) {
      my $evt = ($st eq $hash->{HELPER}{OLDSTATE})?0:1;
      readingsSingleUpdate($hash, "state", $st, $evt);
      $hash->{HELPER}{OLDSTATE} = $st;
      return;
  }
  
  if($init_done != 1 || !$rex || $hash->{MODEL} !~ /Sender/ || isMemLock($hash)) {
      return;
  }
  
  my $events = deviceEvents($dev, AttrVal($name, "addStateEvent", 0));
  return if(!$events);

  my $n   = $dev->{NAME};
  my $max = int(@{$events});
  my $tn  = $dev->{NTFY_TRIGGERTIME};
  my $ct  = $dev->{CHANGETIME};
 
  for (my $i = 0; $i < $max; $i++) {
      my $txt = $events->[$i];
      $txt = "" if(!defined($txt));
      $txt = charFilter($hash,$txt);
      my $tim          = (($ct && $ct->[$i]) ? $ct->[$i] : $tn);
      my ($date,$time) = split q{ }, $tim;
  
      if($n =~ m/^$rex$/x || "$n:$txt" =~ m/^$rex$/x || "$tim:$n:$txt" =~ m/^$rex$/x) {
          my $otp             = "$n $txt";
          $otp                = "$tim $otp" if AttrVal($name,'addTimestamp',0);
          ($prival,$sevAstxt) = setPrival($hash,$otp);
          if($sendsev && $sendsev !~ m/$sevAstxt/x) {                                 # nicht senden wenn Severity nicht in "respectSeverity" enthalten
              Log3slog ($name, 5, "Log2Syslog $name - Warning - Payload NOT sent due to Message Severity not in attribute \"respectSeverity\"\n");
              next;        
          }

          ($data,$pid) = setPayload($hash,$prival,$date,$time,$otp,"event");
          next if(!$data);
          
          ($sock,$st) = openSocket($hash,0);
          
          if ($sock) {
              my $err = writeToSocket ($name,$sock,$data,$pid);
              $st     = $err if($err); 
              
              closeSocket($hash) if($uef);
          }
      }
  } 
  
  my $evt = ($st eq $hash->{HELPER}{OLDSTATE})?0:1;
  readingsSingleUpdate($hash, "state", $st, $evt);
  $hash->{HELPER}{OLDSTATE} = $st; 
                  
return "";
}

#################################################################################
#                               FHEM system logging
# Übergabe aus fhem.pl:  ($li, "$tim $loglevel: $text")
#                         $li -> Schlüssel aus %logInform
#################################################################################
sub fhemLog {
  my $name    = shift;
  my $raw     = shift;        
  
  my $hash    = $defs{$name};
  my $rex     = $hash->{HELPER}{FHEMLOG};
  my $st      = ReadingsVal ($name, 'state',     'active');
  my $sendsev = AttrVal     ($name, 'respectSeverity', '');                # Nachrichten welcher Schweregrade sollen gesendet werden
  my $uef     = AttrVal     ($name, 'useEOF',           0);
  
  my ($prival,$sock,$err,$ret,$data,$pid,$sevAstxt);
  
  if(IsDisabled($name)) {
      my $evt = $st eq $hash->{HELPER}{OLDSTATE} ? 0 : 1;
      readingsSingleUpdate ($hash, "state", $st, $evt);
      $hash->{HELPER}{OLDSTATE} = $st;
      return;
  }
  
  if($init_done != 1 || !$rex || $hash->{MODEL} !~ /Sender/ || isMemLock ($hash)) {
      return;
  }
  
  my ($date,$time,$vbose,$txt) = split " ", $raw, 4;
  $txt                         = charFilter ($hash, $txt);
  $date                        =~ s/\./-/gx;
  $vbose                       =~ s/://x;
  my $tim                      = $date.' '.$time;
  
  if($txt =~ m/^$rex$/x || "$vbose: $txt" =~ m/^$rex$/x) {
      my $otp              = "$vbose: $txt";
      $otp                 = "$tim $otp" if(AttrVal ($name, 'addTimestamp', 0));
      ($prival, $sevAstxt) = setPrival ($hash, $txt, $vbose);
      
      if($sendsev && $sendsev !~ m/$sevAstxt/x) {                     # nicht senden wenn Severity nicht in "respectSeverity" enthalten
          Log3slog ($name, 5, "Log2Syslog $name - Warning - Payload NOT sent due to Message Severity not in attribute \"respectSeverity\"\n");
          return;        
      }
      
      ($data, $pid) = setPayload($hash,$prival,$date,$time,$otp,"fhem");
      return if(!$data);
      
      ($sock, $st) = openSocket($hash,0);
      
      if ($sock) {
          $err = writeToSocket ($name,$sock,$data,$pid);
          $st  = $err if($err); 
          
          closeSocket($hash) if($uef);
      }
  }
  
  my $evt = ($st eq $hash->{HELPER}{OLDSTATE}) ? 0 : 1;
  readingsSingleUpdate ($hash, "state", $st, $evt);
  $hash->{HELPER}{OLDSTATE} = $st; 

return;
}

#################################################################################
#                               Test Message senden
#################################################################################
sub sendTestMsg {
  my ($hash,$own) = @_;                              
  my $name        = $hash->{NAME};
  
  my $st          = ReadingsVal ($name, "state", "active");
  
  my ($prival,$ts,$sock,$tim,$date,$time,$err,$ret,$data,$pid,$otp);
  
  if($own) {                                                  # eigene Testmessage ohne Formatanpassung raw senden
      $data = $own;
      $pid  = $hash->{SEQNO};                                 # PayloadID zur Nachverfolgung der Eventabfolge 
      $hash->{SEQNO}++;
  } 
  else {   
      $ts           = TimeNow();
      ($date,$time) = split q{ }, $ts;
      $date         =~ s/\./-/gx;
      $tim          = $date." ".$time;
    
      $otp    = "Test message from FHEM Syslog Client from ($hash->{MYHOST})";
      $otp    = "$tim $otp" if AttrVal($name,'addTimestamp',0);
      $prival = "14";
      
      ($data,$pid) = setPayload($hash,$prival,$date,$time,$otp,"fhem");
      return if(!$data);
  }  
    
  ($sock,$st) = openSocket($hash,0);
      
  if ($sock) {
      $ret = syswrite $sock, $data."\n" if($data);
      
      if($ret && $ret > 0) {  
          Log3slog ($name, 4, "$name - Payload sequence $pid sent\n");
          $st = "maintenance";          
      } 
      else {
          $err = $!;
          $st  = "write error: $err"; 
          Log3slog ($name, 3, "$name - Warning - Payload sequence $pid NOT sent: $err\n");           
      }  
      
      my $uef = AttrVal($name, "useEOF", 0);
      closeSocket($hash) if($uef);
  }
  
  my $evt = ($st eq $hash->{HELPER}{OLDSTATE}) ? 0 : 1;
  readingsSingleUpdate($hash, "state", $st, $evt);
  $hash->{HELPER}{OLDSTATE} = $st; 

return;
}

###############################################################################
#              Helper für ident & Regex setzen 
###############################################################################
sub setidrex { 
  my ($hash,$a) = @_;
     
  $hash->{HELPER}{EVNTLOG} = (split("event:",$a))[1] if(lc($a) =~ m/^event:.*/x);
  $hash->{HELPER}{FHEMLOG} = (split("fhem:", $a))[1] if(lc($a) =~ m/^fhem:.*/x);
  $hash->{HELPER}{IDENT}   = (split("ident:",$a))[1] if(lc($a) =~ m/^ident:.*/x);
  
return;
}

###############################################################################
#              Zeichencodierung für Payload filtern 
###############################################################################
sub charFilter { 
  my ($hash,$txt) = @_;
  my $name   = $hash->{NAME};

  # nur erwünschte Zeichen in payload, ASCII %d32-126
  $txt =~ s/ß/ss/gx;
  $txt =~ s/ä/ae/gx;
  $txt =~ s/ö/oe/gx;
  $txt =~ s/ü/ue/gx;
  $txt =~ s/Ä/Ae/gx;
  $txt =~ s/Ö/Oe/gx;
  $txt =~ s/Ü/Ue/gx;
  $txt =~ s/€/EUR/gx;
  $txt =~ tr/ A-Za-z0-9!"#$%&'()*+,-.\/:;<=>?@[\]^_`{|}~//cd;      
  
return($txt);
}

###############################################################################
#                        erstelle Socket 
###############################################################################
sub openSocket {                                      ## no critic 'complexity'
  my ($hash,$supresslog)   = @_;
  my $name     = $hash->{NAME};
  my $protocol = lc(AttrVal($name, "protocol", "udp"));
  my $port     = AttrVal($name, "TLS", 0)?AttrVal($name, "port", 6514):AttrVal($name, "port", 514);
  my $st       = "active";
      
  if($hash->{CLIENTSOCKET}) {
      if($protocol eq "tcp") {
          my $sock = $hash->{CLIENTSOCKET};
          return($hash->{CLIENTSOCKET},$st) if($sock->connected());
          closeSocket ($hash);
      } else {
          return($hash->{CLIENTSOCKET},$st);
      }
  }
  
  return if($init_done != 1 || $hash->{MODEL} !~ /Sender/);
  
  my $host     = $hash->{PEERHOST};
  my $timeout  = AttrVal($name, "timeout", 0.5);
  my $ssldbg   = AttrVal($name, "ssldebug", 0);
  my ($sock,$lo,$lof,$sslver,$sslalgo);
  
  Log3slog ($hash, 3, "Log2Syslog $name - Opening client socket on port \"$port\" ...") if(!$supresslog);
 
  if(AttrVal($name, "TLS", 0)) {
      # TLS gesicherte Verbindung
      # TLS Transport nach RFC5425 https://tools.ietf.org/pdf/rfc5425.pdf
      $attr{$name}{protocol} = "TCP" if(AttrVal($name, "protocol", "UDP") ne "TCP");
      $sslver  = "n.a.";
      $sslalgo = "n.a.";
      eval "use IO::Socket::SSL";                                ## no critic 'eval'
      if($@) {
          $st = "$@";
      } else {
          $sock = IO::Socket::INET->new(PeerHost => $host, PeerPort => $port, Proto => 'tcp', Blocking => 0);
          if (!$sock) {
              $st = "unable open socket for $host, $protocol, $port: $!";
          } else {
              $sock->blocking(1);
              $IO::Socket::SSL::DEBUG = $ssldbg;
              eval { IO::Socket::SSL->start_SSL($sock, 
                                                SSL_verify_mode          => 0,
                                                SSL_version              => "TLSv1_2:!TLSv1_1:!SSLv3:!SSLv23:!SSLv2",
                                                SSL_hostname             => $host,
                                                SSL_veriycn_scheme       => "rfc5425",
                                                SSL_veriycn_publicsuffix => '',
                                                Timeout                  => $timeout
                                                ) || undef $sock; };
              $IO::Socket::SSL::DEBUG = 0;
              if($@) {
                  $st = "SSL error: $@";
                  undef $sock;
              } elsif (!$sock) {
                  $st = "SSL error: ".IO::Socket::SSL::errstr();
                  undef $sock;
              } else  {
                  $sslver  = $sock->get_sslversion();
                  $sslalgo = $sock->get_fingerprint();
                  $sslalgo = (split("\\\$",$sslalgo))[0];
                  $lof     = "Socket opened for Host: $host, Protocol: $protocol, Port: $port, TLS: 1";
                  $st      = "active";
              }
          }
      }     
  } else {
      # erstellt ungesicherte Socket Verbindung
      $sslver  = "n.a.";
      $sslalgo = "n.a.";
      $sock    = IO::Socket::INET->new(PeerHost => $host, PeerPort => $port, Proto => $protocol, Timeout => $timeout ); 

      if (!$sock) {
          undef $sock;
          $st = "unable open socket for $host, $protocol, $port: $!";
          $lo = "Socket not opened: $!";
      } else {
          $sock->blocking(0);
          $st = "active";
          # Logausgabe (nur in das fhem Logfile !)
          $lof = "Socket opened for Host: $host, Protocol: $protocol, Port: $port, TLS: 0";
      }
  }
  
  if($sslver ne $hash->{HELPER}{SSLVER}) {
      readingsSingleUpdate($hash, "SSL_Version", $sslver, 1);
      $hash->{HELPER}{SSLVER} = $sslver;
  }
  
  if($sslalgo ne $hash->{HELPER}{SSLALGO}) {
      readingsSingleUpdate($hash, "SSL_Algorithm", $sslalgo, 1);
      $hash->{HELPER}{SSLALGO} = $sslalgo;
  }
  
  Log3slog($name, 3, "Log2Syslog $name - $lo")  if($lo);
  Log3slog($name, 3, "Log2Syslog $name - $lof") if($lof && !$supresslog && !$hash->{CLIENTSOCKET});
  
  $hash->{CLIENTSOCKET} = $sock if($sock);
    
return($sock,$st);
}

################################################################
#            schreibt Daten in geöffneten Socket
################################################################
sub writeToSocket {
  my ($name,$sock,$data,$pid) = @_;
  my $hash = $defs{$name};
  
  use bytes;
  my $err = "";
  my $ld  = length $data;
  my $ret = syswrite ($sock,$data);
  
  if(defined $ret && $ret == $ld) {
      Log3slog($name, 4, "Log2Syslog $name - Payload sequence $pid sent. ($ret of $ld bytes)\n");      
  } 
  elsif (defined $ret && $ret != $ld) {
      Log3slog($name, 3, "Log2Syslog $name - Warning - Payload sequence $pid NOT completely sent: $ret of $ld bytes \n"); 
  } 
  else {
      my $e = $!;
      $err  = "write error: $e";    
      Log3slog($name, 3, "Log2Syslog $name - Warning - Payload sequence $pid NOT sent: $e\n");   
      delete($hash->{CLIENTSOCKET});      
  }
 
return ($err);
} 

###############################################################################
#                          Socket schließen
###############################################################################
sub closeSocket {
  my ($hash,$dolog) = @_;
  my $name = $hash->{NAME};
  my $st   = "closed";
  my $evt;

  my $sock = $hash->{CLIENTSOCKET};
  
  if($sock) {     
      if (!$sock->connected()) {
          $sock->close();
          Log3slog ($hash, 3, "Log2Syslog $name - Client socket already disconnected ... closed.") if($dolog);
      } else {
          Log3slog ($hash, 3, "Log2Syslog $name - Closing client socket ...") if($dolog);
          shutdown($sock, 1);
          if(AttrVal($hash->{NAME}, "TLS", 0) && ReadingsVal($name,"SSL_Algorithm", "n.a.") ne "n.a.") {
              $sock->close(SSL_no_shutdown => 1);
              $hash->{HELPER}{SSLVER}  = "n.a.";
              $hash->{HELPER}{SSLALGO} = "n.a.";
              readingsSingleUpdate($hash, "SSL_Version", "n.a.", 1);
              readingsSingleUpdate($hash, "SSL_Algorithm", "n.a.", 1);
          } else {
              $sock->close();
          }
          Log3slog ($hash, 3, "Log2Syslog $name - Client socket closed ...") if($dolog);
      }

      delete($hash->{CLIENTSOCKET});
      
      if($dolog) {
          $evt = ($st eq $hash->{HELPER}{OLDSTATE})?0:1;
          readingsSingleUpdate($hash, "state", $st, $evt);
          $hash->{HELPER}{OLDSTATE} = $st;
      }
  }
  
return; 
}

###############################################################################
#               set PRIVAL (severity & facility)
###############################################################################
sub setPrival { 
  my ($hash,$txt,$vbose) = @_;
  my $name = $hash->{NAME};
  my $do   = 0;
  my ($prival,$sevAstxt);
  
  # Priority = (facility * 8) + severity 
  # https://tools.ietf.org/pdf/rfc5424.pdf
  
  # determine facility
  my $fac = 5;                                                                # facility by syslogd
  
  # calculate severity
  # mapping verbose level to severity
  # 0: Critical        -> 2
  # 1: Error           -> 3
  # 2: Warning         -> 4
  # 3: Notice          -> 5
  # 4: Informational   -> 6
  # 5: Debug           -> 7
  
  my $sv = 5;                                                                 # notice (default)
  
  if (defined $vbose) {
      # map verbose to severity 
      $sv = 2 if ($vbose == 0);
      $sv = 3 if ($vbose == 1);
      $sv = 4 if ($vbose == 2);
      $sv = 5 if ($vbose == 3);
      $sv = 6 if ($vbose == 4);
      $sv = 7 if ($vbose == 5);
  }
  
  if ( lc($txt) =~ m/error/ || (defined $vbose && $vbose =~ /[01]/) ) {       # error condition und exludes anwenden
      $do = 1;
      my $ees = AttrVal($name, "exclErrCond", "");
      if($ees) {
          $ees = trim($ees);
          $ees =~ s/[\n]//gx;
          $ees =~ s/,,/_ESC_/gx;
          my @excl = split(",",$ees);
          for my $e (@excl) {
              # Negativliste abarbeiten
              $e =~ s/_ESC_/,/g;
              trim($e);
              $do = 0 if($txt =~ m/$e/);        
          }
      }
      $sv = 3 if(!defined $vbose && $do);
      $sv = 5 if(defined  $vbose && !$do);                                    # Severity bei fhemLog Einträgen verbose 1 zu 'Notice' ändern
  }  
               
  $sv = 4 if (lc($txt) =~ m/warning/);                                        # warning conditions
  
  $prival   = ($fac*8)+$sv;
  $sevAstxt = $Log2Syslog_Severity{$sv};
   
return($prival,$sevAstxt);
}

###############################################################################
#               erstellen Payload für Syslog
###############################################################################
sub setPayload { 
  my ($hash,$prival,$date,$time,$otp,$lt) = @_;
  my $name   = $hash->{NAME};
  my $ident  = ($hash->{HELPER}{IDENT}?$hash->{HELPER}{IDENT}:$name)."_".$lt;
  my $myhost = $hash->{MYHOST} // "0.0.0.0";
  my $myfqdn = $hash->{MYFQDN} // $myhost;
  my $lf     = AttrVal($name, "logFormat", "IETF");
  my $cdl    = AttrVal($name, "contDelimiter", "");         # Trennzeichen vor Content (z.B. für Synology nötig)
  my $data;
  
  return if(!$otp);
  my $pid = $hash->{SEQNO};                                 # PayloadID zur Nachverfolgung der Eventabfolge 
  $hash->{SEQNO}++;

  my ($year,$month,$day) = split("-",$date);
  
  if ($lf eq "BSD") {
      # BSD Protokollformat https://tools.ietf.org/html/rfc3164
      $time   = (split(/\./x,$time))[0] if($time =~ m/\./x); # msec ist nicht erlaubt
      $month  = $Log2Syslog_BSDMonth{$month};                # Monatsmapping, z.B. 01 -> Jan
      $day    =~ s/0/ / if($day =~ m/^0.*$/x);               # in Tagen < 10 muss 0 durch Space ersetzt werden
      my $tag = substr($ident,0, $RFC3164len{TAG});          # Länge TAG Feld begrenzen
      no warnings 'uninitialized';                           ## no critic 'warnings'
      $tag  = $tag."[$pid]: ".$cdl;                          # TAG-Feld um PID und Content-Delimiter ergänzen
      $data = "<$prival>$month $day $time $myhost $tag$otp";
      use warnings;
      $data = substr($data,0, ($RFC3164len{DL}-1));          # Länge Total begrenzen
  }
  
  if ($lf eq "IETF") {
      # IETF Protokollformat https://tools.ietf.org/html/rfc5424 
      
      my $IETFver = 1;                                                    # Version von syslog Protokoll Spec RFC5424
      my $mid     = "FHEM";                                               # message ID, identify protocol of message, e.g. for firewall filter
      my $tim     = timeToRFC3339 ($name,$date,$time);                    # Zeit gemäß RFC 3339 formatieren
      my $sdfield = "[version\@Log2Syslog version=\"$hash->{HELPER}{VERSION}\"]";
      $otp        = Encode::encode_utf8($otp);

      # Längenbegrenzung nach RFC5424
      $ident  = substr($ident,0,  ($RFC5425len{ID}-1));
      $pid    = substr($pid,0,    ($RFC5425len{PID}-1));
      $mid    = substr($mid,0,    ($RFC5425len{MID}-1));
      $myfqdn = substr($myfqdn,0, ($RFC5425len{HST}-1));
      
      no warnings 'uninitialized';                          ## no critic 'warnings'
      if ($IETFver == 1) {
          $data = "<$prival>$IETFver $tim $myfqdn $ident $pid $mid $sdfield $cdl$otp";
      }
      use warnings;
  }
  
  if($data =~ /\s$/x) {$data =~ s/\s$//x;}
  $data = $data."\n";
  my $dl = length($data);                                   # Länge muss ! für TLS stimmen, sonst keine Ausgabe !
  
  # wenn Transport Layer Security (TLS) -> Transport Mapping for Syslog https://tools.ietf.org/pdf/rfc5425.pdf
  # oder Octet counting -> Transmission of Syslog Messages over TCP https://tools.ietf.org/html/rfc6587
  if(AttrVal($name, "TLS", 0) || AttrVal($name, "octetCount", 0)) { 
      $data = "$dl $data";
      Log3slog ($name, 4, "$name - Payload created with octet count length: ".$dl); 
  } 
  
  my $ldat = ($dl>130)?(substr($data,0, 130)." ..."):$data;
  Log3slog ($name, 4, "$name - Payload sequence $pid created:\n$ldat");
  
return($data,$pid);
}

################################################################
#    Offset berechnen und zu Time hinzufügen (Senden) 
#    RFC 3339: https://tools.ietf.org/html/rfc3339
################################################################
sub timeToRFC3339 {
 my ($name,$date,$time) = @_;
 
 my $dt = $date."T".$time;
 my $tz = AttrVal($name, "timeSpec", "Local");
 
 my ($year,$month,$mday) = $date =~ /(\d{4})-(\d{2})-(\d{2})/x;
 return $dt if(!$year || !$month ||!$mday);
 my ($hour,$min,$sec)    = $time =~ /(\d{2}):(\d{2}):(\d{2})/x;
 return $dt if(!$hour || !$min ||!$sec);
 
 $year -= 1900;
 $month--;
 
 my $utc;
 my $sign = "+";
 my $localts = fhemTimeLocal($sec, $min, $hour, $mday, $month, $year);
 my $offset  = fhemTzOffset($localts);
 
 if($tz ne "UTC") {                                                # Offset zwischen Localtime und UTC ermitteln und an Zeit anhängen    
     if($offset =~ /[+-]/x) {
         $sign   = substr($offset, 0, 1);
         $offset = substr $offset, 1;
     }
     my $h   = int($offset/3600);
     my $m   = ($offset-($h*3600))/60;
     $offset = $sign.sprintf("%02.0f", $h).":".sprintf("%02.0f", $m);
     $dt     = strftime ("%Y-%m-%dT%H:%M:%S$offset", localtime($localts));
 } else {                                                          # auf UTC umrechnen
     $utc = $localts - $offset;
     $dt  = strftime ("%Y-%m-%dT%H:%M:%SZ", localtime($utc));
 }

 Log3slog ($defs{$name}, 4, "Log2Syslog $name - module time zone: $tz, converted time: $dt"); 
 
return ($dt);
}

###############################################################################
#               eigene Log3-Ableitung - Schleife vermeiden
###############################################################################
sub Log3slog {
  my ($dev, $loglevel, $text) = @_;
  
  $dev = $dev->{NAME} if(defined($dev) && ref($dev) eq "HASH");
     
  if(defined($dev) &&
      defined($attr{$dev}) &&
      defined (my $devlevel = $attr{$dev}{verbose})) {
      return if($loglevel > $devlevel);
  } else {
      return if($loglevel > $attr{global}{verbose});
  }

  my ($seconds, $microseconds) = gettimeofday();
  my @t = localtime($seconds);

  my $tim = sprintf("%04d.%02d.%02d %02d:%02d:%02d",
          $t[5]+1900,$t[4]+1,$t[3], $t[2],$t[1],$t[0]);
  if($attr{global}{mseclog}) {
    $tim .= sprintf(".%03d", $microseconds/1000);
  }

  if($logopened) {
    print LOG "$tim $loglevel: $text\n";
  } else {
    print "$tim $loglevel: $text\n";
  }

return;
}

###############################################################################
#                          Bestimmung Übertragungsrate
###############################################################################
sub calcTrate {
  my ($hash) = @_;
  my $name  = $hash->{NAME};
  my $rerun = AttrVal($name, "rateCalcRerun", 60);
  
  if ($hash->{HELPER}{LTIME}+60 <= time()) {
      my $div = (time()-$hash->{HELPER}{LTIME})/60;
      my $spm = sprintf "%.0f", ($hash->{SEQNO} - $hash->{HELPER}{OLDSEQNO})/$div;
      $hash->{HELPER}{OLDSEQNO} = $hash->{SEQNO};
      $hash->{HELPER}{LTIME}    = time();
      
      my $ospm = ReadingsVal($name, "Transfered_logs_per_minute", 0);
      if($spm != $ospm) {
          readingsSingleUpdate($hash, "Transfered_logs_per_minute", $spm, 1);
      } else {
          readingsSingleUpdate($hash, "Transfered_logs_per_minute", $spm, 0);
      }
  }
  
RemoveInternalTimer($hash, "FHEM::Log2Syslog::calcTrate");
InternalTimer(gettimeofday()+$rerun, "FHEM::Log2Syslog::calcTrate", $hash, 0);

return; 
}

###############################################################################
#                  Peer IP-Adresse und Host ermitteln (Sender der Message)
###############################################################################
sub evalPeer {
  my ($hash)   = @_;
  my $name     = $hash->{NAME};
  my $socket   = $hash->{SERVERSOCKET};
  my $protocol = lc(AttrVal($name, "protocol", "udp"));
  if($hash->{TEMPORARY}) {
      # temporäre Instanz abgelegt durch TcpServer_Accept
      $protocol = "tcp";
  } 
  my ($phost,$paddr,$pport, $pipaddr);
  
  no warnings 'uninitialized';                 ## no critic 'warnings'
  if($protocol =~ /tcp/) {
      $pipaddr = $hash->{HELPER}{TCPPADDR};    # gespeicherte IP-Adresse 
      $phost = $hash->{HIPCACHE}{$pipaddr};    # zuerst IP/Host-Kombination aus Cache nehmen falls vorhanden     
      if(!$phost) {
          $paddr = inet_aton($pipaddr);      
          $phost = gethostbyaddr($paddr, AF_INET());
          $hash->{HIPCACHE}{$pipaddr} = $phost if($phost);
      }
  } elsif ($protocol =~ /udp/ && $socket) {
      # Protokoll UDP
      ($pport, $paddr) = sockaddr_in($socket->peername) if($socket->peername);
      $pipaddr = inet_ntoa($paddr) if($paddr);
      $phost = $hash->{HIPCACHE}{$pipaddr};    # zuerst IP/Host-Kombination aus Cache nehmen falls vorhanden   
      if(!$phost) {  
          $phost = gethostbyaddr($paddr, AF_INET());
          $hash->{HIPCACHE}{$pipaddr} = $phost if($phost);
      }
  }
  Log3slog ($hash, 5, "Log2Syslog $name - message peer: $phost,$pipaddr");
  use warnings;
  $phost = $phost?$phost:$pipaddr?$pipaddr:"unknown";

return ($phost); 
}

###############################################################################
#                    Memory-Lock
# - solange gesetzt erfolgt keine Socketöffnung
# - löschen Sperre über Internaltimer
###############################################################################
sub isMemLock {
  my ($hash) = @_;
  my $ret    = 0;
 
  $ret = 1 if($hash->{HELPER}{MEMLOCK});

return ($ret); 
}

sub deleteMemLock {
  my ($hash) = @_;
  
  RemoveInternalTimer($hash, "FHEM::Log2Syslog::deleteMemLock");
  delete($hash->{HELPER}{MEMLOCK});

return; 
}

################################################################
# sortiert eine Liste von Versionsnummern x.x.x
# Schwartzian Transform and the GRT transform
# Übergabe: "asc | desc",<Liste von Versionsnummern>
################################################################
sub sortVersion {
  my ($sseq,@versions) = @_;

  my @sorted = map {$_->[0]}
               sort {$a->[1] cmp $b->[1]}
               map {[$_, pack "C*", split /\./x]} @versions;
             
  @sorted = map {join ".", unpack "C*", $_}
            sort
            map {pack "C*", split /\./x} @versions;
  
  if($sseq eq "desc") {
      @sorted = reverse @sorted;
  }
  
return @sorted;
}

################################################################
#               Versionierungen des Moduls setzen
#  Die Verwendung von Meta.pm und Packages wird berücksichtigt
################################################################
sub setVersionInfo {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my $v                    = (sortTopicNum("desc",keys %vNotesIntern))[0];
  my $type                 = $hash->{TYPE};
  $hash->{HELPER}{PACKAGE} = __PACKAGE__;
  $hash->{HELPER}{VERSION} = $v;
  $hash->{MODEL}          .= " v$v";
  
  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {
      # META-Daten sind vorhanden
      $modules{$type}{META}{version} = "v".$v;                                        # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{Log2Syslog}{META}}
      if($modules{$type}{META}{x_version}) {                                          # {x_version} ( nur gesetzt wenn $Id$ im Kopf komplett! vorhanden )
          $modules{$type}{META}{x_version} =~ s/1\.1\.1/$v/gx;
      } else {
          $modules{$type}{META}{x_version} = $v; 
      }
      return $@ unless (FHEM::Meta::SetInternals($hash));                             # FVERSION wird gesetzt ( nur gesetzt wenn $Id$ im Kopf komplett! vorhanden )
      if(__PACKAGE__ eq "FHEM::$type" || __PACKAGE__ eq $type) {
          # es wird mit Packages gearbeitet -> Perl übliche Modulversion setzen
          # mit {<Modul>->VERSION()} im FHEMWEB kann Modulversion abgefragt werden
          use version 0.77; our $VERSION = FHEM::Meta::Get($hash, 'version');         ## no critic 'VERSION'                                      
      }
  } else {                                                                            # herkömmliche Modulstruktur
      $hash->{VERSION} = $v;
  }
  
return;
}

################################################################
#   Leerzeichen am Anfang / Ende eines strings entfernen           
################################################################
sub trim {
 my $str = shift;
 
 $str =~ s/^\s+|\s+$//gx;
 
return ($str);
}

################################################################
#   Check aktuelle Zeit auf Sommer/Winterzeit
#   return 1 wenn Sommerzeit (daylight saving time)
################################################################
sub isDst {
 
 my @l = localtime(time);
 
return ($l[8]);
} 

################################################################
#               Payload for Parsen filtern 
################################################################
sub parseFilter { 
  my $s = shift;
 
  $s =~ tr/ A-Za-z0-9!"#$%&'()*+,-.\/:;<=>?@[\\]^_`{|}~ßäöüÄÖÜ€°//cd;
  
return($s);
}

1;

=pod
=item helper
=item summary    forward FHEM system logs/events to a syslog server/act as a syslog server
=item summary_DE sendet FHEM Logs/Events an Syslog-Server / agiert als Syslog-Server

=begin html

<a name="Log2Syslog"></a>
<h3>Log2Syslog</h3>
<ul>
  The module sends FHEM systemlog entries and/or FHEM events to an external syslog server or act as an Syslog-Server itself 
  to receive Syslog-messages of other devices which are able to send Syslog. <br>
  The syslog protocol has been implemented according the specifications of <a href="https://tools.ietf.org/html/rfc5424"> RFC5424 (IETF)</a>,
  <a href="https://tools.ietf.org/html/rfc3164"> RFC3164 (BSD)</a> and the TLS transport protocol according to 
  <a href="https://tools.ietf.org/pdf/rfc5425.pdf"> RFC5425</a>. <br>
  <br>
  
  <b>Prerequisits</b>
  <ul>
    <br/>
    The additional perl modules "IO::Socket::INET" and "IO::Socket::SSL" (if SSL is used) must be installed on your system. <br>
    Install this package from cpan or, on Debian based installations, better by: <br><br>
    
    <code>sudo apt-get install libio-socket-multicast-perl</code><br>
    <code>sudo apt-get install libio-socket-ssl-perl</code><br><br>
    
  </ul>
  <br>
  
  <a name="Log2Syslogdefine"></a>
  <b>Definition and usage</b>
  <ul>
    <br>
    Depending of the intended purpose a Syslog-Server (MODEL Collector) or a Syslog-Client (MODEL Sender) can be  
    defined. <br>
    The Collector receives messages in Syslog-format of other Devices and hence generates Events/Readings for further 
    processing. The Sender-Device forwards FHEM Systemlog entries and/or Events to an external Syslog-Server. <br>
  </ul>
    
  <br>
  <b><h4> The Collector (Syslog-Server) </h4></b>

  <ul>    
    <b> Definition of a Collector </b>
    <br>
    
    <ul>
    <br>
        <code>define &lt;name&gt; Log2Syslog </code><br>
    <br>
    </ul>
    
    The Definition don't need any further parameter.
    In basic setup the Syslog-Server is initialized with Port=1514/UDP and the parsing profil "Automatic".
    With <a href="#Log2Syslogattr">attribute</a> "parseProfile" another formats (e.g. BSD or IETF) can be selected.
    The Syslog-Server is immediately ready for use, detect the received messages, try parsing the 
    data according the rules of RFC5424 or RFC3164 and generates FHEM-Events from received 
    Syslog-messages (pls. see Eventmonitor for the parsed data). <br>
    If the device cannot detect a valid message format, please use attribute "parseProfile" to select the valid 
    profile. <br><br>
    
    <br>
    <b>Example of a Collector: </b><br>
    
    <ul>
    <br>
        <code>define SyslogServer Log2Syslog </code><br>
    <br>
    </ul>
    
    The generated events are visible in the FHEM-Eventmonitor. <br>
    <br>

    Example of generated Events with attribute parseProfile=IETF: <br>
    <br>
    <code>
2018-07-31 17:07:24.382 Log2Syslog SyslogServer HOST: fhem.myds.me || FAC: syslog || SEV: Notice || ID: Prod_event || CONT: USV state: OL <br>
2018-07-31 17:07:24.858 Log2Syslog SyslogServer HOST: fhem.myds.me || FAC: syslog || SEV: Notice || ID: Prod_event || CONT: HMLAN2 loadLvl: low <br>
    </code> 
    <br>

    To separate fields the string "||" is used. 
    The meaning of the fields in the example is:   
    <br><br>
    
    <ul>  
    <table>  
    <colgroup> <col width=20%> <col width=80%> </colgroup>
      <tr><td> <b>HOST</b>  </td><td> the Sender of the dataset </td></tr>
      <tr><td> <b>FAC</b>   </td><td> Facility corresponding to RFC5424 </td></tr>
      <tr><td> <b>SEV</b>   </td><td> Severity corresponding to RFC5424 </td></tr>
      <tr><td> <b>ID</b>    </td><td> Ident-Tag </td></tr>
      <tr><td> <b>CONT</b>  </td><td> the message part of the received message </td></tr>
    </table>
    </ul>
    <br>
    
    The timestamp of generated events is parsed from the Syslog-message. If this information isn't delivered, the current
    timestamp of the operating system is used. <br>
    The reading name in the generated event match the parsed hostname from Syslog-message.
    If the message don't contain a hostname, the IP-address of the sender is retrieved from the network interface and 
    the hostname is determined if possible. 
    In this case the determined hostname respectively the IP-address is used as Reading in the generated event.
    <br>
    After definition of a Collectors Syslog-messages in IETF-format according to RFC5424 are expected. If the data are not
    delivered in this record format and can't be parsed, the Reading "state" will contain the message 
    <b>"parse error - see logfile"</b> and the received Syslog-data are printed into the FHEM Logfile in raw-format. The
    reading "Parse_Err_No" contains the number of parse-errors since module start.<br>
    
    By the <a href="#Log2Syslogattr">attribute</a> "parseProfile" you can try to use another predefined parse-profile  
    or you can create an own parse-profile as well. <br><br>
    
    To define an <b>own parse function</b> the 
    "parseProfile = ParseFn" has to be set and with <a href="#Log2Syslogattr">attribute</a> "parseFn" a specific 
    parse function has to be provided. <br>
    The fields used by the event and their sequential arrangement can be selected from a range with 
    <a href="#Log2Syslogattr">attribute</a> "outputFields". Depending from the used parse-profil all or a subset of 
    the available fields can be selected. Further information about it you can find in description of attribute 
    "parseProfile". <br>
    <br>
    The behavior of the event generation can be adapted by <a href="#Log2Syslogattr">attribute</a> "makeEvent". <br>
  </ul>
    
  <br>
  <b><h4> The Sender (Syslog-Client) </h4></b>

  <ul>    
    <b> Definition of a Sender </b>
    <br>
    
    <ul>
    <br>
        <code>define &lt;name&gt; Log2Syslog &lt;destination host&gt; [ident:&lt;ident&gt;] [event:&lt;regexp&gt;] [fhem:&lt;regexp&gt;]</code><br>
    <br>
    </ul>
    
    <ul>  
    <table>  
    <colgroup> <col width=25%> <col width=75%> </colgroup>
      <tr><td> <b>&lt;destination host&gt;</b> </td><td> host (name or IP-address) where the syslog server is running </td></tr>
      <tr><td> <b>[ident:&lt;ident&gt;]</b>    </td><td> optional program identifier. If not set the device name will be used as default. </td></tr>
      <tr><td> <b>[event:&lt;regexp&gt;]</b>   </td><td> optional regex to filter events for logging </td></tr>
      <tr><td> <b>[fhem:&lt;regexp&gt;]</b>    </td><td> optional regex to filter fhem system log for logging </td></tr>
    </table>
    </ul> 
    
    <br><br>
        
    After definition the new device sends all new appearing fhem systemlog entries and events to the destination host, 
    port=514/UDP format:IETF, immediately without further settings if the regex for "fhem" or "event" is set. <br>
    Without setting a regex, no fhem system log entries or events are forwarded. <br><br>

    The verbose level of FHEM system logs are converted into equivalent syslog severity level. <br>
    Thurthermore the message text will be scanned for signal terms "warning" and "error" (with case insensitivity). 
    Dependent of it the severity will be set equivalent as well. If a severity is already set by verbose level, it will be 
    overwritten by the level according to the signal term found in the message text. <br><br>
    
    <b>Lookup table Verbose-Level to Syslog severity level: </b><br><br>
    <ul>  
    <table>  
    <colgroup> <col width=50%> <col width=50%> </colgroup>
      <tr><td> <b>verbose-Level</b> </td><td> <b>Severity in Syslog</b> </td></tr>
      <tr><td> 0    </td><td> Critical </td></tr>
      <tr><td> 1    </td><td> Error </td></tr>
      <tr><td> 2    </td><td> Warning </td></tr>
      <tr><td> 3    </td><td> Notice </td></tr>
      <tr><td> 4    </td><td> Informational </td></tr>
      <tr><td> 5    </td><td> Debug </td></tr>
    </table>
    </ul>    
    <br>    
    <br>
   
    <b>Example of a Sender: </b><br>
    
    <ul>
    <br>
    <code>define splunklog Log2Syslog fhemtest 192.168.2.49 ident:Test event:.* fhem:.* </code><br/>
    <br>
    </ul>
    
    All events are forwarded like this exmple of a raw-print of a Splunk Syslog Servers shows:<br/>
    <pre>
Aug 18 21:06:46 fhemtest.myds.me 1 2017-08-18T21:06:46 fhemtest.myds.me Test_event 13339 FHEM [version@Log2Syslog version="4.2.0"] : LogDB sql_processing_time: 0.2306
Aug 18 21:06:46 fhemtest.myds.me 1 2017-08-18T21:06:46 fhemtest.myds.me Test_event 13339 FHEM [version@Log2Syslog version="4.2.0"] : LogDB background_processing_time: 0.2397
Aug 18 21:06:45 fhemtest.myds.me 1 2017-08-18T21:06:45 fhemtest.myds.me Test_event 13339 FHEM [version@Log2Syslog version="4.2.0"] : LogDB CacheUsage: 21
Aug 18 21:08:27 fhemtest.myds.me 1 2017-08-18T21:08:27.760 fhemtest.myds.me Test_fhem 13339 FHEM [version@Log2Syslog version="4.2.0"] : 4: CamTER - Informations of camera Terrasse retrieved
Aug 18 21:08:27 fhemtest.myds.me 1 2017-08-18T21:08:27.095 fhemtest.myds.me Test_fhem 13339 FHEM [version@Log2Syslog version="4.2.0"] : 4: CamTER - CAMID already set - ignore get camid
    </pre>
    
    The structure of the payload differs dependent of the used logFormat. <br><br>
    
    <b>logFormat IETF:</b> <br><br>
    "&lt;PRIVAL&gt;IETFVERS TIME MYHOST IDENT PID MID [SD-FIELD] MESSAGE" <br><br> 
        
    <ul>  
    <table>  
    <colgroup> <col width=10%> <col width=90%> </colgroup>
      <tr><td> PRIVAL   </td><td> priority value (coded from "facility" and "severity") </td></tr>
      <tr><td> IETFVERS </td><td> used version of RFC5424 specification </td></tr>
      <tr><td> TIME     </td><td> timestamp according to RFC5424 </td></tr>
      <tr><td> MYHOST   </td><td> Internal MYHOST </td></tr>
      <tr><td> IDENT    </td><td> ident-Tag from DEF if set, or else the own device name. The statement will be completed by "_fhem" (FHEM-Log) respectively "_event" (Event-Log). </td></tr>
      <tr><td> PID      </td><td> sequential Payload-ID </td></tr>
      <tr><td> MID      </td><td> fix value "FHEM" </td></tr>
      <tr><td> SD-FIELD </td><td> contains additional iformation about used module version </td></tr>
      <tr><td> MESSAGE  </td><td> the dataset to transfer </td></tr>
    </table>
    </ul>     
    <br>    
    
    <b>logFormat BSD:</b> <br><br>
    "&lt;PRIVAL&gt;MONTH DAY TIME MYHOST IDENT[PID]: MESSAGE" <br><br>
    
    <ul>  
    <table>  
    <colgroup> <col width=10%> <col width=90%> </colgroup>
      <tr><td> PRIVAL   </td><td> priority value (coded from "facility" and "severity") </td></tr>
      <tr><td> MONTH    </td><td> month according to RFC3164 </td></tr>
      <tr><td> DAY      </td><td> day of month according to RFC3164 </td></tr>
      <tr><td> TIME     </td><td> timestamp according to RFC3164 </td></tr>
      <tr><td> MYHOST   </td><td> Internal MYHOST </td></tr>
      <tr><td> TAG      </td><td> ident-Tag from DEF if set, or else the own device name. The statement will be completed by "_fhem" (FHEM-Log) respectively "_event" (Event-Log). </td></tr>
      <tr><td> PID      </td><td> the message-id (sequence number) </td></tr>
      <tr><td> MESSAGE  </td><td> the dataset to transfer </td></tr>
    </table>
    </ul>     
    <br>
        
  </ul>
  <br>

  <a name="Log2SyslogSet"></a>
  <b>Set</b>
  <ul>
    <br> 
    
    <ul>
    <li><b>reopen </b><br>
        <br>
        Closes an existing Client/Server-connection and open it again. 
        This command can be helpful in case of e.g. "broken pipe"-errors.
    </li>
    </ul>
    <br>
    
    <ul>
    <li><b>sendTestMessage [&lt;Message&gt;] </b><br>
        <br>
        With device type "Sender" a testmessage can be transfered. The format of the message depends on attribute "logFormat" 
        and contains data in BSD- or IETF-format. 
        Alternatively an own &lt;Message&gt; can be set. This message will be sent in im raw-format without  
        any conversion. The attribute "disable = maintenance" determines, that no data except test messages are sent 
        to the receiver.
    </li>
    </ul>
    <br>

  </ul>
  <br>
  
  <a name="Log2SyslogGet"></a>
  <b>Get</b>
  <ul>
    <br> 
    
    <ul>
    <li><b>certinfo </b><br>
        <br>
        On a SenderDevice the command shows informations about the server certificate in case a TLS-session was created 
        (Reading "SSL_Version" isn't "n.a.").
    </li>
    </ul>
    <br>
    
    <ul>
    <li><b>versionNotes [hints | rel | &lt;key&gt;] </b><br>
        <br>
       Shows realease informations and/or hints about the module. It contains only main release informations for module users. <br>
       If no options are specified, both release informations and hints will be shown. "rel" shows only release informations and
       "hints" shows only hints. By the &lt;key&gt;-specification only the hint with the specified number is shown.
    </li>
    </ul>
    <br>

  </ul>
  <br>  
  
  <a name="Log2Syslogattr"></a>
  <b>Attributes</b>
  <ul>
    <br>
    
    <ul>
    <a name="addTimestamp"></a>
    <li><b>addTimestamp </b><br>
        <br/>
        The attribute is only usable for device type "Sender".         
        If set, FHEM timestamps will be logged too.<br>
        Default behavior is not log these timestamps, because syslog uses own timestamps.<br>
        Maybe useful if mseclog is activated in FHEM.<br>
        <br>
        
        Example output (raw) of a Splunk syslog server: <br>
        <pre>Aug 18 21:26:55 fhemtest.myds.me 1 2017-08-18T21:26:55 fhemtest.myds.me Test_event 13339 FHEM - : 2017-08-18 21:26:55 USV state: OL
Aug 18 21:26:54 fhemtest.myds.me 1 2017-08-18T21:26:54 fhemtest.myds.me Test_event 13339 FHEM - : 2017-08-18 21:26:54 Bezug state: done
Aug 18 21:26:54 fhemtest.myds.me 1 2017-08-18T21:26:54 fhemtest.myds.me Test_event 13339 FHEM - : 2017-08-18 21:26:54 recalc_Bezug state: Next: 21:31:59
        </pre>
    </li>
    </ul>
    <br>

    <ul>
    <a name="addStateEvent"></a>
    <li><b>addStateEvent </b><br>
        <br>
        The attribute is only usable for device type "Sender".         
        If set, events will be completed with "state" if a state-event appears. <br>
        Default behavior is without getting "state".
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="contDelimiter"></a>
    <li><b>contDelimiter </b><br>
        <br>
        The attribute is only usable for device type "Sender". 
        You can set an additional character which is straight inserted before the content-field. <br>
        This possibility is useful in some special cases if the receiver need it (e.g. the Synology-Protokollcenter needs the 
        character ":" for proper function).
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="disable"></a>
    <li><b>disable [1 | 0 | maintenance] </b><br>
        <br>
        This device will be activated, deactivated respectSeverity set into the maintenance-mode. 
        In maintenance-mode a test message can be sent by the "Sender"-device (pls. see also command "set &lt;name&gt; 
        sendTestMessage").
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="exclErrCond"></a>
    <li><b>exclErrCond &lt;Pattern1,Pattern2,Pattern3,...&gt; </b><br>
        <br>
        This attribute is only usable for device type "Sender". <br>
        If within an event the text "Error" is identified, this message obtain the severity "Error" automatically.
        The attribute exclErrCond can contain a list of events separated by comma, whose severity nevertheless has not  
        to be valued as "Error". Commas within the &lt;Pattern&gt; must be escaped by ,, (double comma).
        The attribute may contain line breaks.  <br><br>
        
        <b>Example</b>
        <pre>
attr &lt;name&gt; exclErrCond Error: none, 
                        Errorcode: none,
                        Dum.Energy PV: 2853.0,, Error: none,
                        Seek_Error_Rate_,
                        Raw_Read_Error_Rate_,
                        sabotageError:,
        </pre>
    </li>
    </ul>
    <br>
    
    <ul>
    <a name="logFormat"></a>
    <li><b>logFormat [ BSD | IETF ]</b><br>
        <br>
        This attribute is only usable for device type "Sender".  
        Set the syslog protocol format. <br>
        Default value is "IETF" if not specified. 
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="makeEvent"></a>
    <li><b>makeEvent [ intern | no | reading ]</b><br>
        <br>
        The attribute is only usable for device type "Collector". 
        With this attribute the behavior of the event- and reading generation is  defined. 
        <br><br>
        
        <ul>  
        <table>  
        <colgroup> <col width=10%> <col width=90%> </colgroup>
        <tr><td> <b>intern</b>   </td><td> events are generated by module intern mechanism and only visible in FHEM eventmonitor. Readings are not created. </td></tr>
        <tr><td> <b>no</b>       </td><td> only readings like "MSG_&lt;hostname&gt;" without event generation are created </td></tr>
        <tr><td> <b>reading</b>  </td><td> readings like "MSG_&lt;hostname&gt;" are created. Events are created dependent of the "event-on-.*"-attributes </td></tr>
        </table>
        </ul> 
        
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="octetCount"></a>
    <li><b>octetCount </b><br>
        <br>
        The attribute is only usable for device type "Sender". <br>
        If set, the Syslog Framing is changed from Non-Transparent-Framing (default) to Octet-Framing.
        The Syslog-Reciver must support Octet-Framing !
        For further informations see RFC6587 <a href="https://tools.ietf.org/html/rfc6587">"Transmission of Syslog Messages 
        over TCP"</a>. 
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="outputFields"></a>
    <li><b>outputFields </b><br>
        <br>
        The attribute is only usable for device type "Collector".
        By a sortable list the desired fields of generated events can be selected.
        The meaningful usable fields are depending on the attribute <b>"parseProfil"</b>. Their meaning can be found in 
        the description of attribute "parseProfil".
        Is "outputFields" not defined, a predefined set of fields for event generation is used.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="parseFn"></a>
    <li><b>parseFn {&lt;Parsefunktion&gt;} </b><br>
        <br>
        The attribute is only usable for device type "Collector".
        The provided perl function (has to be set into "{}") will be applied to the received Syslog-message. 
        The following variables are commited to the function. They can be used for programming, processing and for 
        value return. Variables which are provided as blank, are marked as "". <br>
        In case of restrictions the expected format of variables return is specified in "()".
        Otherwise the variable is usable for free. The function must be enclosed by { }.     
        <br><br>
        
        <ul>  
        <table>  
        <colgroup> <col width=15%> <col width=30%> <col width=45%> </colgroup>
        <tr><td> <b>Variable</b>  </td><td> <b>Transfer value</b>    </td><td> <b>expected return format </b>     </td></tr>
        <tr><td> $PRIVAL          </td><td> ""                       </td><td> (0 ... 191)                        </td></tr>
        <tr><td> $FAC             </td><td> ""                       </td><td> (0 ... 23)                         </td></tr>
        <tr><td> $SEV             </td><td> ""                       </td><td> (0 ... 7)                          </td></tr>
        <tr><td> $TS              </td><td> Timestamp                </td><td> (YYYY-MM-DD hh:mm:ss)              </td></tr>
        <tr><td> $HOST            </td><td> ""                       </td><td>                                    </td></tr>
        <tr><td> $DATE            </td><td> ""                       </td><td> (YYYY-MM-DD)                       </td></tr>
        <tr><td> $TIME            </td><td> ""                       </td><td> (hh:mm:ss)                         </td></tr>
        <tr><td> $ID              </td><td> ""                       </td><td>                                    </td></tr>
        <tr><td> $PID             </td><td> ""                       </td><td>                                    </td></tr>
        <tr><td> $MID             </td><td> ""                       </td><td>                                    </td></tr>
        <tr><td> $SDFIELD         </td><td> ""                       </td><td>                                    </td></tr>
        <tr><td> $CONT            </td><td> ""                       </td><td>                                    </td></tr>
        <tr><td> $DATA            </td><td> Raw data of the message  </td><td> no return evaluation               </td></tr>
        <tr><td> $IGNORE          </td><td> 0                        </td><td> (0|1), if $IGNORE==1 
                                                                               the syslog record  ignores         </td></tr>                                           
        </table>
        </ul>
        <br>

        The names of the variables corresponding to the field names and their primary meaning  denoted in attribute 
        <b>"parseProfile"</b> (explanation of the field data). <br><br>

        <ul>
        <b>Example: </b> <br>
        # Source text: '<4> <;4>LAN IP and mask changed to 192.168.2.3 255.255.255.0' <br>
        # Task: The characters '<;4>' are to removed from the CONT-field
<pre>
{
($PRIVAL,$CONT) = ($DATA =~ /^<(\d{1,3})>\s(.*)$/);
$CONT = (split(">",$CONT))[1] if($CONT =~ /^<.*>.*$/);
} 
</pre>        
        </ul>         
              
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="parseProfile"></a>
    <li><b>parseProfile [ Automatic | BSD | IETF | ... | ParseFn | raw ] </b><br>
        <br>
        Selection of a parse profile. The attribute is only usable for device type "Collector". <br>
        In mode "Automatic" the module attempts to recognize, if the received data are from type "BSD" or "IEFT".
        If the type is not recognized, the "raw" format is used instead and a warning is generated in the FHEM log.
        <br><br>
    
        <ul>  
        <table>  
        <colgroup> <col width=20%><col width=80%> </colgroup>
        <tr><td> <b>Automatic</b>     </td><td> try to recognize the BSD or IETF message format and use it for parsing (default)  </td></tr>
        <tr><td> <b>BSD</b>           </td><td> Parsing of messages in BSD-format according to RFC3164 </td></tr>
        <tr><td> <b>IETF</b>          </td><td> Parsing of messages in IETF-format according to RFC5424 (default) </td></tr>
        <tr><td> <b>TPLink-Switch</b> </td><td> specific parser profile for TPLink switch messages </td></tr>
        <tr><td> <b>UniFi</b>         </td><td> specific parser profile for UniFi controller Syslog as well as Netconsole messages </td></tr>
        <tr><td> <b>ParseFn</b>       </td><td> Usage of an own specific parse function provided by attribute "parseFn" </td></tr>
        <tr><td> <b>raw</b>           </td><td> no parsing, events are created from the messages as received without conversion </td></tr>
        </table>
        </ul>
        <br>

        The parsed data are provided in fields. The fields to use for events and their sequence can be defined by  
        attribute <b>"outputFields"</b>. <br>
        Dependent from used "parseProfile" the following fields are filled with values and therefor it is meaningful 
        to use only the namend fields by attribute "outputFields". By the "raw"-profil the received data are not converted 
        and the event is created directly.
        <br><br>
        
        The meaningful usable fields in attribute "outputFields" depending of the particular profil: 
        <br>
        <br>
        <ul>  
        <table>  
        <colgroup> <col width=10%> <col width=90%> </colgroup>
        <tr><td> BSD     </td><td>-> PRIVAL,FAC,SEV,TS,HOST,ID,CONT  </td></tr>
        <tr><td> IETF    </td><td>-> PRIVAL,FAC,SEV,TS,HOST,DATE,TIME,ID,PID,MID,SDFIELD,CONT  </td></tr>
        <tr><td> ParseFn </td><td>-> PRIVAL,FAC,SEV,TS,HOST,DATE,TIME,ID,PID,MID,SDFIELD,CONT </td></tr>
        <tr><td> raw     </td><td>-> no selection is meaningful, the original message is used for event creation </td></tr>
        </table>
        </ul>
        <br>   
        
        Explanation of field data: 
        <br>
        <br>
        <ul>  
        <table>  
        <colgroup> <col width=20%> <col width=80%> </colgroup>
        <tr><td> PRIVAL  </td><td> coded Priority value (coded from "facility" and "severity")  </td></tr>
        <tr><td> FAC     </td><td> decoded Facility  </td></tr>
        <tr><td> SEV     </td><td> decoded Severity of message </td></tr>
        <tr><td> TS      </td><td> Timestamp containing date and time (YYYY-MM-DD hh:mm:ss) </td></tr>
        <tr><td> HOST    </td><td> Hostname / Ip-address of the Sender </td></tr>
        <tr><td> DATE    </td><td> Date (YYYY-MM-DD) </td></tr>
        <tr><td> TIME    </td><td> Time (hh:mm:ss) </td></tr>
        <tr><td> ID      </td><td> Device or application what was sending the Syslog-message  </td></tr>
        <tr><td> PID     </td><td> Programm-ID, offen reserved by process name or prozess-ID </td></tr>
        <tr><td> MID     </td><td> Type of message (arbitrary string) </td></tr>
        <tr><td> SDFIELD </td><td> Metadaten about the received Syslog-message </td></tr>
        <tr><td> CONT    </td><td> Content of the message </td></tr>
        <tr><td> DATA    </td><td> received raw-data </td></tr>
        </table>
        </ul>
        <br>   
         
        <b>Note for manual setting:</b> <br>   
        The typical record layout of the format "BSD" or "IETF" starts with: <br><br>
        <table>  
        <colgroup> <col width=25%> <col width=75%> </colgroup>
        <tr><td> <45>Mar 17 20:23:46 ...       </td><td>-> record start of the BSD message format  </td></tr>
        <tr><td> <45>1 2019-03-17T19:13:48 ... </td><td>-> record start of the IETF message format  </td></tr>
        </table>          
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="port"></a>
    <li><b>port &lt;Port&gt;</b><br>
        <br>
        The used port. For a Sender the default-port is 514.
        A Collector (Syslog-Server) uses the port 1514 per default.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="protocol"></a>
    <li><b>protocol [ TCP | UDP ]</b><br>
        <br>
        Sets the socket protocol which should be used. You can choose UDP or TCP. <br>
        Default value is "UDP" if not specified.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="rateCalcRerun"></a>
    <li><b>rateCalcRerun &lt;Zeit in Sekunden&gt; </b><br>
        <br>
        Rerun cycle for calculation of log transfer rate (Reading "Transfered_logs_per_minute") in seconds (>=60).     
        Default: 60 seconds.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="respectSeverity"></a>
    <li><b>respectSeverity </b><br>
        <br>
        Messages are only forwarded (Sender) respectively the receipt considered (Collector), whose severity is included 
        by this attribute.
        If "respectSeverity" isn't set, messages of all severity is processed.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="sslCertPrefix"></a>
    <li><b>sslCertPrefix</b><br>
        <br>
        Set the prefix for the SSL certificate, default is "certs/server-". 
        Setting this attribute you are able to specify different SSL-certificates for different Log2Syslog devices.
        See also the TLS attribute.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="ssldebug"></a>
    <li><b>ssldebug</b><br>
        <br>
        Debugging level of SSL messages. The attribute is only usable for device type "Sender". <br><br>
        <ul>
        <li> 0 - No debugging (default).  </li>
        <li> 1 - Print out errors from <a href="http://search.cpan.org/~sullr/IO-Socket-SSL-2.056/lib/IO/Socket/SSL.pod">IO::Socket::SSL</a> and ciphers from <a href="http://search.cpan.org/~mikem/Net-SSLeay-1.85/lib/Net/SSLeay.pod">Net::SSLeay</a>. </li>
        <li> 2 - Print also information about call flow from <a href="http://search.cpan.org/~sullr/IO-Socket-SSL-2.056/lib/IO/Socket/SSL.pod">IO::Socket::SSL</a> and progress information from <a href="http://search.cpan.org/~mikem/Net-SSLeay-1.85/lib/Net/SSLeay.pod">Net::SSLeay</a>. </li>
        <li> 3 - Print also some data dumps from <a href="http://search.cpan.org/~sullr/IO-Socket-SSL-2.056/lib/IO/Socket/SSL.pod">IO::Socket::SSL</a> and from <a href="http://search.cpan.org/~mikem/Net-SSLeay-1.85/lib/Net/SSLeay.pod">Net::SSLeay</a>. </li>
        </ul>
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="TLS"></a>
    <li><b>TLS</b><br>
        <br>
        A client (Sender) establish a secured connection to a Syslog-Server. 
        A Syslog-Server (Collector) provide to establish a secured connection. 
        The protocol will be switched to TCP automatically.
        <br<br>
        
        Thereby a Collector device can use TLS, a certificate has to be created or available.
        With following steps a certicate can be created: <br><br>
        
        1. in the FHEM basis directory create the directory "certs": <br>
    <pre>
    sudo mkdir /opt/fhem/certs
    </pre>
        
        2. create the SSL certicate: <br>
    <pre>
    cd /opt/fhem/certs
    sudo openssl req -new -x509 -nodes -out server-cert.pem -days 3650 -keyout server-key.pem
    </pre>      
    
        3. set file/directory permissions: <br>
    <pre>
    sudo chown -R fhem:dialout /opt/fhem/certs
    sudo chmod 644 /opt/fhem/certs/*.pem
    sudo chmod 711 /opt/fhem/certs
    </pre>
    
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="timeout"></a>
    <li><b>timeout</b><br>
        <br>
        This attribute is only usable for device type "Sender".  
        Timeout für die Verbindung zum Syslog-Server (TCP). Default: 0.5s.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="useParsefilter"></a>
    <li><b>useParsefilter</b><br>
        <br>
        If activated, all non-ASCII characters are deleted before parsing the message.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="timeSpec"></a>
    <li><b>timeSpec [Local | UTC]</b><br>
        <br>
        Use of the local or UTC time format in the device. 
        Only received time datagrams that have the specification according to RFC 3339 are converted accordingly.
        The time specification for data transmission (model Sender) always corresponds to the set time format. <br>
        Default: Local. <br><br>
        
        <ul>
          <b>Examples of supported time specifications</b> <br>
          2019-04-12T23:20:50Z       <br>
          2019-12-19T16:39:57-08:00  <br>
          2020-01-01T12:00:27+00:20  <br>
          2020-04-04T16:33:10+00:00  <br>
          2020-04-04T17:15:00+02:00  <br>
        </ul>
        
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="verbose"></a>
    <li><b>verbose</b><br>
        <br>
        Please see global <a href="#attributes">attribute</a> "verbose".
        To avoid loops, the output of verbose level of the Log2Syslog-Devices will only be reported into the local FHEM 
        Logfile and not forwarded.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="useEOF"></a>
    <li><b>useEOF</b><br>
        <br>
        <b>Model Sender (protocol TCP): </b><br>
        After every transmission the TCP-connection will be terminated with signal EOF. <br><br>
        
        <b>Model Collector: </b><br>
        No parsing until the sender has send an EOF signal. CRLF is not considered as data separator. 
        If not set, CRLF will be considered as a record separator.
        <br>
        <br>
        
        <b>Note:</b><br>
        If the sender don't use EOF signal, the data parsing is enforced after exceeding a buffer use threshold
        and the warning "Buffer overrun" is issued in the FHEM Logfile.
    </li>
    </ul>
    <br>
    <br>
    
  </ul>
  <br>  
    
  <a name="Log2Syslogreadings"></a>
  <b>Readings</b>
  <ul>
  <br> 
    <table>  
    <colgroup> <col width=35%> <col width=65%> </colgroup>
      <tr><td><b>MSG_&lt;Host&gt;</b>               </td><td> the last successful parsed Syslog-message from &lt;Host&gt; </td></tr>
      <tr><td><b>Parse_Err_LastData</b>             </td><td> the last record where the set parseProfile could not be applied successfully </td></tr>
      <tr><td><b>Parse_Err_No</b>                   </td><td> the number of parse errors since start </td></tr>
      <tr><td><b>SSL_Algorithm</b>                  </td><td> used SSL algorithm if SSL is enabled and active </td></tr>
      <tr><td><b>SSL_Version</b>                    </td><td> the used TLS-version if encryption is enabled and is active</td></tr>
      <tr><td><b>Transfered_logs_per_minute</b>     </td><td> the average number of forwarded logs/events per minute </td></tr>
    </table>    
    <br>
  </ul>
  
</ul>



=end html
=begin html_DE

<a name="Log2Syslog"></a>
<h3>Log2Syslog</h3>
<ul>
  Das Modul sendet FHEM Systemlog-Einträge und/oder Events an einen externen Syslog-Server weiter oder agiert als 
  Syslog-Server um Syslog-Meldungen anderer Geräte zu empfangen. <br>
  Die Implementierung des Syslog-Protokolls erfolgte entsprechend den Vorgaben von <a href="https://tools.ietf.org/html/rfc5424"> RFC5424 (IETF)</a>,
  <a href="https://tools.ietf.org/html/rfc3164"> RFC3164 (BSD)</a> sowie dem TLS Transport Protokoll nach 
  <a href="https://tools.ietf.org/pdf/rfc5425.pdf"> RFC5425</a>. <br>   
  <br>
  
  <b>Voraussetzungen</b>
  <ul>
    <br/>
    Es werden die Perl Module "IO::Socket::INET" und "IO::Socket::SSL" (wenn SSL benutzt) benötigt und müssen installiert sein. <br>
    Das Modul kann über CPAN oder, auf Debian Linux Systemen, besser mit <br><br>
    
    <code>sudo apt-get install libio-socket-multicast-perl</code><br>
    <code>sudo apt-get install libio-socket-ssl-perl</code><br><br>
    
    installiert werden.
  </ul>
  <br/>
  
  <a name="Log2Syslogdefine"></a>
  <b>Definition und Verwendung</b>
  <ul>
    <br>
    Je nach Verwendungszweck kann ein Syslog-Server (MODEL Collector) oder ein Syslog-Client (MODEL Sender) definiert 
    werden. <br>
    Der Collector empfängt Meldungen im Syslog-Format anderer Geräte und generiert daraus Events/Readings zur Weiterverarbeitung in 
    FHEM. Das Sender-Device leitet FHEM Systemlog Einträge und/oder Events an einen externen Syslog-Server weiter. <br>
  </ul>
    
  <br>
  <b><h4> Der Collector (Syslog-Server) </h4></b>

  <ul>    
    <b> Definition eines Collectors </b>
    <br>
    
    <ul>
    <br>
        <code>define &lt;name&gt; Log2Syslog </code><br>
    <br>
    </ul>
    
    Die Definition benötigt keine weiteren Parameter.
    In der Grundeinstellung wird der Syslog-Server mit dem Port=1514/UDP und dem Parsingprofil "Automatic" initialisiert.
    Mit dem <a href="#Log2Syslogattr">Attribut</a> "parseProfile" können alternativ andere Formate (z.B. BSD oder IETF) ausgewählt werden.
    Der Syslog-Server ist sofort betriebsbereit, versucht das Format der empfangenen Messages zu erkennen und parst die Syslog-Daten 
    entsprechend der Richtlinien nach RFC5424 oder RFC3164 und generiert aus den eingehenden Syslog-Meldungen FHEM-Events 
    (Daten sind im Eventmonitor sichtbar). <br>
    Wird das Format nicht selbständig erkannt, kann es mit dem Attribut "parseProfile" manuell festgelegt werden.
    <br><br>
    
    <br>
    <b>Beispiel für einen Collector: </b><br>
    
    <ul>
    <br>
        <code>define SyslogServer Log2Syslog </code><br>
    <br>
    </ul>
    
    Im Eventmonitor können die generierten Events kontrolliert werden. <br>
    <br>

    Beispiel von generierten Events mit Attribut parseProfile=IETF: <br>
    <br>
    <code>
2018-07-31 17:07:24.382 Log2Syslog SyslogServer HOST: fhem.myds.me || FAC: syslog || SEV: Notice || ID: Prod_event || CONT: USV state: OL <br>
2018-07-31 17:07:24.858 Log2Syslog SyslogServer HOST: fhem.myds.me || FAC: syslog || SEV: Notice || ID: Prod_event || CONT: HMLAN2 loadLvl: low <br>
    </code> 
    <br>

    Zwischen den einzelnen Feldern wird der Trenner "||" verwendet. 
    Die Bedeutung der Felder in diesem Beispiel sind:   
    <br><br>
    
    <ul>  
    <table>  
    <colgroup> <col width=20%> <col width=80%> </colgroup>
      <tr><td> <b>HOST</b>  </td><td> der Sender des Datensatzes </td></tr>
      <tr><td> <b>FAC</b>   </td><td> Facility (Kategorie) nach RFC5424 </td></tr>
      <tr><td> <b>SEV</b>   </td><td> Severity (Schweregrad) nach RFC5424 </td></tr>
      <tr><td> <b>ID</b>    </td><td> Ident-Tag </td></tr>
      <tr><td> <b>CONT</b>  </td><td> der Nachrichtenteil der empfangenen Meldung </td></tr>
    </table>
    </ul>
    <br>
    
    Der Timestamp der generierten Events wird aus den Syslogmeldungen geparst. Sollte diese Information nicht mitgeliefert 
    werden, wird der aktuelle Timestamp des Systems verwendet. <br>
    Der Name des Readings im generierten Event entspricht dem aus der Syslogmeldung geparsten Hostnamen.
    Ist der Hostname in der Meldung nicht enthalten, wird die IP-Adresse des Senders aus dem Netzwerk Interface abgerufen und 
    der Hostname ermittelt sofern möglich. 
    In diesem Fall wird der ermittelte Hostname bzw. die IP-Adresse als Reading im Event genutzt.
    <br>
    Nach der Definition des Collectors werden die Syslog-Meldungen im IETF-Format gemäß RFC5424 erwartet. Werden die Daten 
    nicht in diesem Format geliefert bzw. können nicht geparst werden, erscheint im Reading "state" die Meldung 
    <b>"parse error - see logfile"</b> und die empfangenen Syslog-Daten werden im Logfile im raw-Format ausgegeben. Das Reading
    "Parse_Err_No" enthält die Anzahl der Parse-Fehler seit Modulstart. <br>
    
    In diesem Fall kann mit dem <a href="#Log2Syslogattr">Attribut</a> "parseProfile" ein anderes vordefiniertes Parse-Profil 
    eingestellt bzw. ein eigenes Profil definiert werden. <br><br>
    
    Zur Definition einer <b>eigenen Parse-Funktion</b> wird 
    "parseProfile = ParseFn" eingestellt und im <a href="#Log2Syslogattr">Attribut</a> "parseFn" eine spezifische 
    Parse-Funktion hinterlegt. <br>
    Die im Event verwendeten Felder und deren Reihenfolge können aus einem Wertevorrat mit dem 
    <a href="#Log2Syslogattr">Attribut</a> "outputFields" bestimmt werden. Je nach verwendeter Parse-Funktion können alle oder
    nur eine Untermenge der verfügbaren Felder verwendet werden. Näheres dazu in der Beschreibung des Attributes "parseProfile". <br>
    <br>
    Das Verhalten der Eventgenerierung kann mit dem <a href="#Log2Syslogattr">Attribut</a> "makeEvent" angepasst werden. <br>
  </ul>
    
  <br>
  <b><h4> Der Sender (Syslog-Client) </h4></b>

  <ul>    
    <b> Definition eines Senders </b>
    <br>
    
    <ul>
    <br>
        <code>define &lt;name&gt; Log2Syslog &lt;Zielhost&gt; [ident:&lt;ident&gt;] [event:&lt;regexp&gt;] [fhem:&lt;regexp&gt;] </code><br>
    <br>
    </ul>
    
    <ul>  
    <table>  
    <colgroup> <col width=20%> <col width=80%> </colgroup>
      <tr><td> <b>&lt;Zielhost&gt;</b>       </td><td> Host (Name oder IP-Adresse) auf dem der Syslog-Server läuft </td></tr>
      <tr><td> <b>[ident:&lt;ident&gt;]</b>  </td><td> optionaler Programm Identifier. Wenn nicht gesetzt wird per default der Devicename benutzt. </td></tr>
      <tr><td> <b>[event:&lt;regexp&gt;]</b> </td><td> optionaler regulärer Ausdruck zur Filterung von Events zur Weiterleitung </td></tr>
      <tr><td> <b>[fhem:&lt;regexp&gt;]</b>  </td><td> optionaler regulärer Ausdruck zur Filterung von FHEM Logs zur Weiterleitung </td></tr>
    </table>
    </ul> 
    
    <br><br>
    
    Direkt nach der Definition sendet das neue Device alle neu auftretenden FHEM Systemlog Einträge und Events ohne weitere 
    Einstellungen an den Zielhost, Port=514/UDP Format=IETF, wenn reguläre Ausdrücke für "event" und/oder "fhem" angegeben wurden. <br>
    Wurde kein Regex gesetzt, erfolgt keine Weiterleitung von Events oder FHEM-Systemlogs. <br><br>
    
    Die Verbose-Level der FHEM Systemlogs werden in entsprechende Schweregrade der Syslog-Messages umgewandelt. <br>
    Weiterhin wird der Meldungstext der FHEM Systemlogs und Events nach den Signalwörtern "warning" und "error" durchsucht 
    (Groß- /Kleinschreibung wird nicht beachtet). Davon abhängig wird der Schweregrad ebenfalls äquivalent gesetzt und übersteuert 
    einen eventuell bereits durch Verbose-Level gesetzten Schweregrad.  <br><br>
    
    <b>Umsetzungstabelle Verbose-Level in Syslog-Schweregrad Stufe: </b><br><br>
    <ul>  
    <table>  
    <colgroup> <col width=40%> <col width=60%> </colgroup>
      <tr><td> <b>Verbose-Level</b> </td><td> <b>Schweregrad in Syslog</b> </td></tr>
      <tr><td> 0    </td><td> Critical </td></tr>
      <tr><td> 1    </td><td> Error </td></tr>
      <tr><td> 2    </td><td> Warning </td></tr>
      <tr><td> 3    </td><td> Notice </td></tr>
      <tr><td> 4    </td><td> Informational </td></tr>
      <tr><td> 5    </td><td> Debug </td></tr>
    </table>
    </ul>     
    <br>    
    <br>
    
    <b>Beispiel für einen Sender: </b><br>
    
    <ul>
    <br>
    <code>define splunklog Log2Syslog fhemtest 192.168.2.49 ident:Test event:.* fhem:.* </code><br/>
    <br>
    </ul>
    
    Es werden alle Events weitergeleitet wie deses Beispiel der raw-Ausgabe eines Splunk Syslog Servers zeigt:<br/>
    <pre>
Aug 18 21:06:46 fhemtest.myds.me 1 2017-08-18T21:06:46 fhemtest.myds.me Test_event 13339 FHEM [version@Log2Syslog version="4.2.0"] : LogDB sql_processing_time: 0.2306
Aug 18 21:06:46 fhemtest.myds.me 1 2017-08-18T21:06:46 fhemtest.myds.me Test_event 13339 FHEM [version@Log2Syslog version="4.2.0"] : LogDB background_processing_time: 0.2397
Aug 18 21:06:45 fhemtest.myds.me 1 2017-08-18T21:06:45 fhemtest.myds.me Test_event 13339 FHEM [version@Log2Syslog version="4.2.0"] : LogDB CacheUsage: 21
Aug 18 21:08:27 fhemtest.myds.me 1 2017-08-18T21:08:27.760 fhemtest.myds.me Test_fhem 13339 FHEM [version@Log2Syslog version="4.2.0"] : 4: CamTER - Informations of camera Terrasse retrieved
Aug 18 21:08:27 fhemtest.myds.me 1 2017-08-18T21:08:27.095 fhemtest.myds.me Test_fhem 13339 FHEM [version@Log2Syslog version="4.2.0"] : 4: CamTER - CAMID already set - ignore get camid
    </pre>

    Der Aufbau der Payload unterscheidet sich je nach verwendeten logFormat. <br><br>
    
    <b>logFormat IETF:</b> <br><br>
    "&lt;PRIVAL&gt;IETFVERS TIME MYHOST IDENT PID MID [SD-FIELD] MESSAGE" <br><br>
        
    <ul>  
    <table>  
    <colgroup> <col width=10%> <col width=90%> </colgroup>
      <tr><td> PRIVAL     </td><td> Priority Wert (kodiert aus "facility" und "severity") </td></tr>
      <tr><td> IETFVERS   </td><td> Version der benutzten RFC5424 Spezifikation </td></tr>
      <tr><td> TIME       </td><td> Timestamp nach RFC5424 </td></tr>
      <tr><td> MYHOST     </td><td> Internal MYHOST </td></tr>
      <tr><td> IDENT      </td><td> Ident-Tag aus DEF wenn angegeben, sonst der eigene Devicename. Die Angabe wird mit "_fhem" (FHEM-Log) bzw. "_event" (Event-Log) ergänzt. </td></tr>
      <tr><td> PID        </td><td> fortlaufende Payload-ID </td></tr>
      <tr><td> MID        </td><td> fester Wert "FHEM" </td></tr>
      <tr><td> [SD-FIELD] </td><td> Structured Data Feld. Enthält Informationen zur verwendeten Modulversion (die Klammern "[]" sind Bestandteil des Feldes)</td></tr>
      <tr><td> MESSAGE    </td><td> der zu übertragende Datensatz </td></tr>
    </table>
    </ul>     
    <br>    
    
    <b>logFormat BSD:</b> <br><br>
    "&lt;PRIVAL&gt;MONTH DAY TIME MYHOST IDENT[PID]: MESSAGE" <br><br>
        
    <ul>  
    <table>  
    <colgroup> <col width=10%> <col width=90%> </colgroup>
      <tr><td> PRIVAL   </td><td> Priority Wert (kodiert aus "facility" und "severity") </td></tr>
      <tr><td> MONTH    </td><td> Monatsangabe nach RFC3164 </td></tr>
      <tr><td> DAY      </td><td> Tag des Monats nach RFC3164 </td></tr>
      <tr><td> TIME     </td><td> Zeitangabe nach RFC3164 </td></tr>
      <tr><td> MYHOST   </td><td> Internal MYHOST </td></tr>
      <tr><td> TAG      </td><td> Ident-Tag aus DEF wenn angegeben, sonst der eigene Devicename. Die Angabe wird mit "_fhem" (FHEM-Log) bzw. "_event" (Event-Log) ergänzt. </td></tr>
      <tr><td> PID      </td><td> Die ID der Mitteilung (= Sequenznummer) </td></tr>
      <tr><td> MESSAGE  </td><td> der zu übertragende Datensatz </td></tr>
    </table>
    </ul>     
    <br>
  
  </ul>
  <br><br>
  
  <a name="Log2SyslogSet"></a>
  <b>Set</b>
  <ul>
    <br> 
    
    <ul>
    <li><b>reopen </b><br>
        <br>
        Schließt eine bestehende Client/Server-Verbindung und öffnet sie erneut. 
        Der Befehl kann z.B. bei "broken pipe"-Fehlern hilfreich sein.
    </li>
    </ul>
    <br>
    
    <ul>
    <li><b>sendTestMessage [&lt;Message&gt;] </b><br>
        <br>
        Mit einem Devicetyp "Sender" kann abhängig vom Attribut "logFormat" eine Testnachricht im BSD- bzw. IETF-Format 
        gesendet werden. Wird eine optionale eigene &lt;Message&gt; angegeben, wird diese Nachricht im raw-Format ohne 
        Formatanpassung (BSD/IETF) gesendet. Das Attribut "disable = maintenance" legt fest, dass keine Daten ausser eine 
        Testnachricht an den Empfänger gesendet wird.
    </li>
    </ul>
    <br>

  </ul>
  <br>
  
  <a name="Log2SyslogGet"></a>
  <b>Get</b>
  <ul>
    <br> 
    
    <ul>
    <li><b>certinfo </b><br>
        <br>
        Zeigt auf einem Sender-Device Informationen zum Serverzertifikat an sofern eine TLS-Session aufgebaut wurde 
        (Reading "SSL_Version" ist nicht "n.a.").
    </li>
    </ul>
    <br>
    
    <ul>
    <li><b>versionNotes [hints | rel | &lt;key&gt;]</b> <br>
        <br>
        Zeigt Release Informationen und/oder Hinweise zum Modul an. Es sind nur Release Informationen mit Bedeutung für den 
        Modulnutzer enthalten. <br>
        Sind keine Optionen angegben, werden sowohl Release Informationen als auch Hinweise angezeigt. "rel" zeigt nur Release
        Informationen und "hints" nur Hinweise an. Mit der &lt;key&gt;-Angabe wird der Hinweis mit der angegebenen Nummer 
        angezeigt.
        Ist das Attribut "language = DE" im global Device gesetzt, erfolgt die Ausgabe der Hinweise in deutscher Sprache.
    </li>
    </ul>
    <br>

  </ul>
  <br>

  
  <a name="Log2Syslogattr"></a>
  <b>Attribute</b>
  <ul>
    <br>
    
    <ul>
    <a name="addTimestamp"></a>
    <li><b>addTimestamp </b><br>
        <br/>
        Das Attribut ist nur für "Sender" verwendbar. Wenn gesetzt, werden FHEM Timestamps im Content-Feld der Syslog-Meldung
        mit übertragen.<br>
        Per default werden die Timestamps nicht im Content-Feld hinzugefügt, da innerhalb der Syslog-Meldungen im IETF- bzw.
        BSD-Format bereits Zeitstempel gemäß RFC-Vorgabe erstellt werden.<br>
        Die Einstellung kann hilfeich sein wenn mseclog in FHEM aktiviert ist.<br>
        <br/>
        
        Beispielausgabe (raw) eines Splunk Syslog Servers:<br/>
        <pre>Aug 18 21:26:55 fhemtest.myds.me 1 2017-08-18T21:26:55 fhemtest.myds.me Test_event 13339 FHEM - : 2017-08-18 21:26:55 USV state: OL
Aug 18 21:26:54 fhemtest.myds.me 1 2017-08-18T21:26:54 fhemtest.myds.me Test_event 13339 FHEM - : 2017-08-18 21:26:54 Bezug state: done
Aug 18 21:26:54 fhemtest.myds.me 1 2017-08-18T21:26:54 fhemtest.myds.me Test_event 13339 FHEM - : 2017-08-18 21:26:54 recalc_Bezug state: Next: 21:31:59
        </pre>
    </li>
    </ul>
    <br>

    <ul>
    <a name="addStateEvent"></a>
    <li><b>addStateEvent </b><br>
        <br>
        Das Attribut ist nur für "Sender" verwendbar. Wenn gesetzt, werden state-events mit dem Reading "state" ergänzt.<br>
        Die Standardeinstellung ist ohne state-Ergänzung.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="contDelimiter"></a>
    <li><b>contDelimiter </b><br>
        <br>
        Das Attribut ist nur für "Sender" verwendbar. Es enthält ein zusätzliches Zeichen welches unmittelber vor das 
        Content-Feld eingefügt wird. <br>
        Diese Möglichkeit ist in manchen speziellen Fällen hilfreich (z.B. kann das Zeichen ':' eingefügt werden um eine 
        ordnungsgemäße Anzeige im Synology-Protokollcenter zu erhalten).
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="disable"></a>
    <li><b>disable [1 | 0 | maintenance] </b><br>
        <br>
        Das Device wird aktiviert, deaktiviert bzw. in den Maintenance-Mode geschaltet. Im Maintenance-Mode kann mit dem 
        "Sender"-Device eine Testnachricht gesendet werden (siehe "set &lt;name&gt; sendTestMessage").
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="exclErrCond"></a>
    <li><b>exclErrCond &lt;Pattern1,Pattern2,Pattern3,...&gt; </b><br>
        <br>
        Das Attribut ist nur für "Sender" verwendbar. <br>
        Wird in einem Event der Text "Error" erkannt, bekommt diese Message automatisch den Schweregrad "Error" zugewiesen.
        Im Attribut exclErrCond kann eine durch Komma getrennte Liste von Events angegeben werden, deren Schweregrad 
        trotzdem nicht als "Error" gewertet werden soll. Kommas innerhalb von &lt;Pattern&gt; müssen mit ,, (doppeltes 
        Komma) escaped werden.
        Das Attribut kann Zeilenumbrüche enthalten.  <br><br>
        
        <b>Beispiel</b>
        <pre>
attr &lt;name&gt; exclErrCond Error: none, 
                        Errorcode: none,
                        Dum.Energy PV: 2853.0,, Error: none,
                        Seek_Error_Rate_,
                        Raw_Read_Error_Rate_,
                        sabotageError:,
        </pre>
    </li>
    </ul>
    <br>
    
    <ul>
    <a name="logFormat"></a>
    <li><b>logFormat [ BSD | IETF ]</b><br>
        <br>
        Das Attribut ist nur für "Sender" verwendbar.  Es stellt das Protokollformat ein. (default: "IETF") <br>
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="makeEvent"></a>
    <li><b>makeEvent [ intern | no | reading ]</b><br>
        <br>
        Das Attribut ist nur für "Collector" verwendbar.  Mit dem Attribut wird das Verhalten der Event- bzw.
        Readinggenerierung festgelegt. 
        <br><br>
        
        <ul>  
        <table>  
        <colgroup> <col width=10%> <col width=90%> </colgroup>
        <tr><td> <b>intern</b>   </td><td> Events werden modulintern generiert und sind nur im Eventmonitor sichtbar. Readings werden nicht erstellt. </td></tr>
        <tr><td> <b>no</b>       </td><td> es werden nur Readings der Form "MSG_&lt;Hostname&gt;" ohne Eventfunktion erstellt </td></tr>
        <tr><td> <b>reading</b>  </td><td> es werden Readings der Form "MSG_&lt;Hostname&gt;" erstellt. Events werden in Abhängigkeit der "event-on-.*"-Attribute generiert </td></tr>
        </table>
        </ul> 
        
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="octetCount"></a>
    <li><b>octetCount </b><br>
        <br>
        Das Attribut ist nur für "Sender" verfügbar. <br>
        Wenn gesetzt, wird das Syslog Framing von Non-Transparent-Framing (default) in Octet-Framing geändert.
        Der Syslog-Empfänger muss Octet-Framing unterstützen !
        Für weitere Informationen siehe RFC6587 <a href="https://tools.ietf.org/html/rfc6587">"Transmission of Syslog Messages 
        over TCP"</a>. 
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="outputFields"></a>
    <li><b>outputFields </b><br>
        <br>
        Das Attribut ist nur für "Collector" verwendbar.
        Über eine sortierbare Liste können die gewünschten Felder des generierten Events ausgewählt werden.
        Die abhängig vom Attribut <b>"parseProfil"</b> sinnvoll verwendbaren Felder und deren Bedeutung ist der Beschreibung 
        des Attributs "parseProfil" zu entnehmen.
        Ist "outputFields" nicht gesetzt, wird ein vordefinierter Satz Felder zur Eventgenerierung verwendet.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="parseFn"></a>
    <li><b>parseFn {&lt;Parsefunktion&gt;} </b><br>
        <br>
        Das Attribut ist nur für Device-MODEL "Collector" verwendbar. Es wird die eingegebene Perl-Funktion auf die 
        empfangene Syslog-Meldung angewendet. Der Funktion werden folgende Variablen übergeben die zur Verarbeitung
        und zur Werterückgabe genutzt werden können. Leer übergebene Variablen sind als "" gekennzeichnet. <br>
        Das erwartete Rückgabeformat einer Variable wird in "()" angegeben sofern sie Restriktionen unterliegt.
        Ansonsten ist die Variable frei verfügbar. Die Funktion ist in { } einzuschließen.        
        <br><br>
        
        <ul>  
        <table>  
        <colgroup> <col width=15%> <col width=25%> <col width=60%> </colgroup>
        <tr><td> <b>Variable</b>  </td><td> <b>Übergabewert</b>   </td><td> <b>erwartetes Rückgabeformat </b>  </td></tr>
        <tr><td> $PRIVAL          </td><td> ""                    </td><td> (0 ... 191)                        </td></tr>
        <tr><td> $FAC             </td><td> ""                    </td><td> (0 ... 23)                         </td></tr>
        <tr><td> $SEV             </td><td> ""                    </td><td> (0 ... 7)                          </td></tr>
        <tr><td> $TS              </td><td> Zeitstempel           </td><td> (YYYY-MM-DD hh:mm:ss)              </td></tr>
        <tr><td> $HOST            </td><td> ""                    </td><td>                                    </td></tr>
        <tr><td> $DATE            </td><td> ""                    </td><td> (YYYY-MM-DD)                       </td></tr>
        <tr><td> $TIME            </td><td> ""                    </td><td> (hh:mm:ss)                         </td></tr>
        <tr><td> $ID              </td><td> ""                    </td><td>                                    </td></tr>
        <tr><td> $PID             </td><td> ""                    </td><td>                                    </td></tr>
        <tr><td> $MID             </td><td> ""                    </td><td>                                    </td></tr>
        <tr><td> $SDFIELD         </td><td> ""                    </td><td>                                    </td></tr>
        <tr><td> $CONT            </td><td> ""                    </td><td>                                    </td></tr>
        <tr><td> $DATA            </td><td> Rohdaten der Message  </td><td> keine Rückgabeauswertung           </td></tr>
        <tr><td> $IGNORE          </td><td> 0                     </td><td> (0|1), wenn $IGNORE==1 
                                                                            wird der Syslog-Datensatz 
                                                                            ignoriert                          </td></tr>
        </table>
        </ul>
        <br>  

        Die Variablennamen korrespondieren mit den Feldnamen und deren ursprünglicher Bedeutung angegeben im Attribut 
        <b>"parseProfile"</b> (Erläuterung der Felddaten). <br><br>

        <ul>
        <b>Beispiel: </b> <br>
        # Quelltext: '<4> <;4>LAN IP and mask changed to 192.168.2.3 255.255.255.0' <br>
        # Die Zeichen '<;4>' sollen aus dem CONT-Feld entfernt werden
<pre>
{
($PRIVAL,$CONT) = ($DATA =~ /^<(\d{1,3})>\s(.*)$/);
$CONT = (split(">",$CONT))[1] if($CONT =~ /^<.*>.*$/);
} 
</pre>        
        </ul>         
              
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="parseProfile"></a>
    <li><b>parseProfile [ Automatic | BSD | IETF | ... | ParseFn | raw ] </b><br>
        <br>
        Auswahl eines Parsing-Profiles. Das Attribut ist nur für Device-Model "Collector" verwendbar. <br>
        Im Modus "Automatic" versucht das Modul zu erkennen, ob die empfangenen Daten vom Typ "BSD" oder "IEFT" sind.
        Konnte der Typ nicht erkannt werden, wird das "raw" Format genutzt und im Log eine Warnung generiert.
        <br><br>
    
        <ul>  
        <table>  
        <colgroup> <col width=15%> <col width=85%> </colgroup>
        <tr><td> <b>Automatic</b>     </td><td> Es wird versucht das Datenformat zu erkennen und das BSD-Format RFC3164 oder IETF-Format RFC5424 anzuwenden (default) </td></tr>
        <tr><td> <b>BSD</b>           </td><td> Parsing der Meldungen im BSD-Format nach RFC3164 </td></tr>
        <tr><td> <b>IETF</b>          </td><td> Parsing der Meldungen im IETF-Format nach RFC5424 (default) </td></tr>
        <tr><td> <b>TPLink-Switch</b> </td><td> spezifisches Parser Profile für TPLink Switch Meldungen </td></tr>
        <tr><td> <b>UniFi</b>         </td><td> spezifisches Parser Profile für UniFi Controller Syslog as und Netconsole Meldungen </td></tr>
        <tr><td> <b>ParseFn</b>       </td><td> Verwendung einer eigenen spezifischen Parsingfunktion im Attribut "parseFn". </td></tr>
        <tr><td> <b>raw</b>           </td><td> kein Parsing, die Meldungen werden wie empfangen in einen Event umgesetzt </td></tr>
        </table>
        </ul>
        <br>

        Die geparsten Informationen werden in Feldern zur Verfügung gestellt. Die im Event erscheinenden Felder und deren 
        Reihenfolge können mit dem Attribut <b>"outputFields"</b> bestimmt werden. <br>
        Abhängig vom verwendeten "parseProfile" oder erkannten Message-Format (Internal PROFILE) werden die folgenden 
        Felder mit Werten gefüllt und es ist dementsprechend auch nur sinnvoll die benannten Felder 
        im Attribut "outputFields" zu verwenden. Im raw-Profil werden die empfangenen Daten ohne Parsing in einen 
        Event umgewandelt.
        <br><br>
        
        Die sinnvoll im Attribut "outputFields" verwendbaren Felder des jeweilgen Profils sind: 
        <br>
        <br>
        <ul>  
        <table>  
        <colgroup> <col width=10%> <col width=90%> </colgroup>
        <tr><td> BSD     </td><td>-> PRIVAL,FAC,SEV,TS,HOST,ID,CONT  </td></tr>
        <tr><td> IETF    </td><td>-> PRIVAL,FAC,SEV,TS,HOST,DATE,TIME,ID,PID,MID,SDFIELD,CONT  </td></tr>
        <tr><td> ParseFn </td><td>-> PRIVAL,FAC,SEV,TS,HOST,DATE,TIME,ID,PID,MID,SDFIELD,CONT </td></tr>
        <tr><td> raw     </td><td>-> keine Auswahl sinnvoll, es wird immer die Originalmeldung in einen Event umgesetzt </td></tr>
        </table>
        </ul>
        <br>   
        
        Erläuterung der Felddaten: 
        <br>
        <br>
        <ul>  
        <table>  
        <colgroup> <col width=20%> <col width=80%> </colgroup>
        <tr><td> PRIVAL  </td><td> kodierter Priority Wert (kodiert aus "facility" und "severity")  </td></tr>
        <tr><td> FAC     </td><td> Kategorie (Facility)  </td></tr>
        <tr><td> SEV     </td><td> Schweregrad der Meldung (Severity) </td></tr>
        <tr><td> TS      </td><td> Zeitstempel aus Datum und Zeit (YYYY-MM-DD hh:mm:ss) </td></tr>
        <tr><td> HOST    </td><td> Hostname / Ip-Adresse des Senders </td></tr>
        <tr><td> DATE    </td><td> Datum (YYYY-MM-DD) </td></tr>
        <tr><td> TIME    </td><td> Zeit (hh:mm:ss) </td></tr>
        <tr><td> ID      </td><td> Gerät oder Applikation welche die Meldung gesendet hat  </td></tr>
        <tr><td> PID     </td><td> Programm-ID, oft belegt durch Prozessname bzw. Prozess-ID </td></tr>
        <tr><td> MID     </td><td> Typ der Mitteilung (beliebiger String) </td></tr>
        <tr><td> SDFIELD </td><td> Metadaten über die empfangene Syslog-Mitteilung </td></tr>
        <tr><td> CONT    </td><td> Inhalt der Meldung </td></tr>
        <tr><td> DATA    </td><td> empfangene Rohdaten </td></tr>
        </table>
        </ul>
        <br>

        <b>Hinweis für die manuelle Entscheidung:</b> <br>   
        Der typische Satzaufbau der Formate "BSD" bzw. "IETF" beginnt mit: <br><br>
        <table>  
        <colgroup> <col width=25%> <col width=75%> </colgroup>
        <tr><td> <45>Mar 17 20:23:46 ...       </td><td>-> Satzstart des BSD-Formats  </td></tr>
        <tr><td> <45>1 2019-03-17T19:13:48 ... </td><td>-> Satzstart des IETF-Formats  </td></tr>
        </table>                     
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="port"></a>
    <li><b>port &lt;Port&gt;</b><br>
        <br>
        Der verwendete Port. Für einen Sender ist der default-Port 514, für einen Collector (Syslog-Server) der Port 1514.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="protocol"></a>
    <li><b>protocol [ TCP | UDP ]</b><br>
        <br>
        Setzt den Protokolltyp der verwendet werden soll. Es kann UDP oder TCP gewählt werden. <br>
        Standard ist "UDP" wenn nichts spezifiziert ist.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="rateCalcRerun"></a>
    <li><b>rateCalcRerun &lt;Zeit in Sekunden&gt; </b><br>
        <br>
        Wiederholungszyklus für die Bestimmung der Log-Transferrate (Reading "Transfered_logs_per_minute") in Sekunden (>=60).        
        Default: 60 Sekunden.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="respectSeverity"></a>
    <li><b>respectSeverity </b><br>
        <br>
        Es werden nur Nachrichten übermittelt (Sender) bzw. beim Empfang berücksichtigt (Collector), deren Schweregrad im 
        Attribut enthalten ist.
        Ist "respectSeverity" nicht gesetzt, werden Nachrichten aller Schweregrade verarbeitet.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="sslCertPrefix"></a>
    <li><b>sslCertPrefix</b><br>
        <br>
        Setzt das Präfix der SSL-Zertifikate, die Voreinstellung ist "certs/server-". 
        Mit diesem Attribut kann für verschiedene Log2Syslog-Devices die Verwendung unterschiedlicher SSL-Zertifikate 
        bestimmt werden.
        Siehe auch das "TLS" Attribut.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="ssldebug"></a>
    <li><b>ssldebug</b><br>
        <br>
        Debugging Level von SSL Messages. Das Attribut ist nur für Device-MODEL "Sender" verwendbar. <br><br>
        <ul>
        <li> 0 - Kein Debugging (default).  </li>
        <li> 1 - Ausgabe Errors von from <a href="http://search.cpan.org/~sullr/IO-Socket-SSL-2.056/lib/IO/Socket/SSL.pod">IO::Socket::SSL</a> und ciphers von <a href="http://search.cpan.org/~mikem/Net-SSLeay-1.85/lib/Net/SSLeay.pod">Net::SSLeay</a>. </li>
        <li> 2 - zusätzliche Ausgabe von Informationen über den Protokollfluss von <a href="http://search.cpan.org/~sullr/IO-Socket-SSL-2.056/lib/IO/Socket/SSL.pod">IO::Socket::SSL</a> und Fortschrittinformationen von <a href="http://search.cpan.org/~mikem/Net-SSLeay-1.85/lib/Net/SSLeay.pod">Net::SSLeay</a>. </li>
        <li> 3 - zusätzliche Ausgabe einiger Dumps von <a href="http://search.cpan.org/~sullr/IO-Socket-SSL-2.056/lib/IO/Socket/SSL.pod">IO::Socket::SSL</a> und <a href="http://search.cpan.org/~mikem/Net-SSLeay-1.85/lib/Net/SSLeay.pod">Net::SSLeay</a>. </li>
        </ul>
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="TLS"></a>
    <li><b>TLS</b><br>
        <br>
        Ein Client (Sender) baut eine gesicherte Verbindung zum Syslog-Server auf. 
        Ein Syslog-Server (Collector) stellt eine gesicherte Verbindung zur Verfügung. 
        Das Protokoll schaltet automatisch auf TCP um.
        <br<br>
        
        Damit ein Collector TLS verwenden kann, muss ein Zertifikat erstellt werden bzw. vorhanden sein.
        Mit folgenden Schritten kann ein Zertifikat erzeugt werden: <br><br>
        
        1. im FHEM-Basisordner das Verzeichnis "certs" anlegen: <br>
    <pre>
    sudo mkdir /opt/fhem/certs
    </pre>
        
        2. SSL Zertifikat erstellen: <br>
    <pre>
    cd /opt/fhem/certs
    sudo openssl req -new -x509 -nodes -out server-cert.pem -days 3650 -keyout server-key.pem
    </pre>      
    
        3. Datei/Verzeichnis-Rechte setzen: <br>
    <pre>
    sudo chown -R fhem:dialout /opt/fhem/certs
    sudo chmod 644 /opt/fhem/certs/*.pem
    sudo chmod 711 /opt/fhem/certs
    </pre>  
        
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="timeout"></a>
    <li><b>timeout</b><br>
        <br>
        Das Attribut ist nur für "Sender" verwendbar.
        Timeout für die Verbindung zum Syslog-Server (TCP). <br>
        Default: 0.5s.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="timeSpec"></a>
    <li><b>timeSpec [Local | UTC]</b><br>
        <br>
        Verwendung des lokalen bzw. UTC Zeitformats im Device. 
        Nur empfangene Zeitdatagramme, die die Spezifikation gemäß RFC 3339 aufweisen, werden entsprechend umgewandelt.
        Die Zeitspezifikation beim Datenversand (Model Sender) erfolgt immer entsprechend des eingestellten Zeitformats. <br>
        Default: Local. <br><br>
        
        <ul>
          <b>Beispiele unterstützter Zeitspezifikationen</b> <br>
          2019-04-12T23:20:50Z       <br>
          2019-12-19T16:39:57-08:00  <br>
          2020-01-01T12:00:27+00:20  <br>
          2020-04-04T16:33:10+00:00  <br>
          2020-04-04T17:15:00+02:00  <br>
        </ul>
        
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="useParsefilter"></a>
    <li><b>useParsefilter</b><br>
        <br>
        Wenn aktiviert, werden vor dem Parsing der Message nicht-ASCII Zeichen entfernt.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="verbose"></a>
    <li><b>verbose</b><br>
        <br>
        Verbose-Level entsprechend dem globalen <a href="#attributes">Attribut</a> "verbose".
        Die Ausgaben der Verbose-Level von Log2Syslog-Devices werden ausschließlich im lokalen FHEM Logfile ausgegeben und
        nicht weitergeleitet um Schleifen zu vermeiden.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <a name="useEOF"></a>
    <li><b>useEOF</b><br>
        <br>
        <b>Model Sender (Protokoll TCP): </b><br> 
        Nach jedem Sendevorgang wird eine TCP-Verbindung mit EOF beendet. <br><br>
        
        <b>Model Collector: </b><br>      
        Es wird mit dem Parsing gewartet, bis der Sender ein EOF Signal gesendet hat. CRLF wird nicht als Datentrenner 
        berücksichtigt. Wenn nicht gesetzt, wird CRLF als Trennung von Datensätzen gewertet.
        <br>
        <br>
        
        <b>Hinweis:</b><br>
        Wenn der Sender kein EOF verwendet, wird nach Überschreiten eines Puffer-Schwellenwertes das Parsing der Daten erzwungen
        und die Warnung "Buffer overrun" im FHEM Log ausgegeben.
    </li>
    </ul>
    <br>
    <br>
    
  </ul>
  <br>
    
  <a name="Log2Syslogreadings"></a>
  <b>Readings</b>
  <ul>
  <br> 
    <table>  
    <colgroup> <col width=35%> <col width=65%> </colgroup>
      <tr><td><b>MSG_&lt;Host&gt;</b>               </td><td> die letzte erfolgreich geparste Syslog-Message von &lt;Host&gt; </td></tr>
      <tr><td><b>Parse_Err_LastData</b>             </td><td> der letzte Datensatz bei dem das eingestellte parseProfile nicht erfolgreich angewendet werden konnte </td></tr>
      <tr><td><b>Parse_Err_No</b>                   </td><td> die Anzahl der Parse-Fehler seit Start </td></tr>
      <tr><td><b>SSL_Algorithm</b>                  </td><td> der verwendete SSL Algorithmus wenn SSL eingeschaltet und aktiv ist </td></tr>
      <tr><td><b>SSL_Version</b>                    </td><td> die verwendete TLS-Version wenn die Verschlüsselung aktiv ist</td></tr>
      <tr><td><b>Transfered_logs_per_minute</b>     </td><td> die durchschnittliche Anzahl der übertragenen/empfangenen Logs/Events pro Minute </td></tr>
    </table>    
    <br>
  </ul>
  
</ul>
=end html_DE

=for :application/json;q=META.json 93_Log2Syslog.pm
{
  "abstract": "forward FHEM system logs/events to a syslog server or act as a syslog server itself",
  "x_lang": {
    "de": {
      "abstract": "sendet FHEM Logs/Events an einen Syslog-Server (Sender) oder agiert selbst als Syslog-Server (Collector)"
    }
  },
  "keywords": [
    "syslog",
    "syslog-server",
    "syslog-client",
    "logging"
  ],
  "version": "v1.1.1",
  "release_status": "stable",
  "author": [
    "Heiko Maaz <heiko.maaz@t-online.de>"
  ],
  "x_fhem_maintainer": [
    "DS_Starter"
  ],
  "x_fhem_maintainer_github": [
    "nasseeder1"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.014,
        "TcpServerUtils": 0,
        "Scalar::Util": 0,
        "Time::HiRes": 0,
        "Encode": 0, 
        "POSIX": 0,        
        "IO::Socket::INET": 0, 
        "Net::Domain": 0         
      },
      "recommends": {
        "IO::Socket::SSL": 0,
        "FHEM::Meta": 0        
      },
      "suggests": {
      }
    }
  }
}
=end :application/json;q=META.json

=cut
