# $Id$
########################################################################################################################
#
#     73_DoorBird.pm
#     Creates the possibility to access and control the DoorBird IP door station
#
#     Author                     : Matthias Deeke 
#     e-mail                     : matthias.deeke(AT)deeke(DOT)eu
#     Fhem Forum                 : https://forum.fhem.de/index.php/topic,100758
#     Fhem Wiki                  : https://wiki.fhem.de/wiki/DoorBird
#     Source Documentation       : https://www.doorbird.com/downloads/api_lan.pdf
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#     Install the following debian packets and cpan libaries
#     sudo apt-get install -y sox && sudo apt-get install -y libsox-fmt-all && sudo apt-get install -y libsodium-dev && sudo apt-get install -y gstreamer1.0-tools
#     sudo cpan install Crypt::Argon2
#     sudo cpan install Sodium::FFI
#     sudo cpan install IO::String module
#     sudo cpan install IO::Socket
#
#     WARNING ### If you have an old version of 73_DoorBird.pm working before you have to re-image your OS since the 
#     WARNING ### new version does not work with the work-around of the old Alien 1.0.8 libary
#
#     fhem.cfg: define <devicename> DoorBird <IPv4-address> <User> <Password>
#
#     Example:
#     define myDoorBird DoorBird 192.168.178.240 Username SecretPW
#
########################################################################################################################

########################################################################################################################
# List of open Problems:
#
# Problem with error message after startup: "PERL WARNING: Prototype mismatch: sub main::memcmp: none vs ($$;$) at /usr/local/share/perl/5.24.1/Sub/Exporter.pm line 445."
# This problem has been addressed to GitHub since its based on problems with sub-libary
#
#
########################################################################################################################

package main;
use constant false => 0;
use constant true  => 1;
use strict;
use warnings;
use utf8;
use JSON;
use HttpUtils;
use Encode;
use FHEM::Meta;
use Cwd;
use MIME::Base64;
use Crypt::Argon2 qw/argon2i_raw/;
use Sodium::FFI qw(crypto_aead_chacha20poly1305_decrypt crypto_aead_chacha20poly1305_NPUBBYTES crypto_aead_chacha20poly1305_KEYBYTES);
use IO::Socket;
use IO::String;			   
use LWP::UserAgent;
use Data::Dumper;
use File::Spec::Functions ':ALL';

###START###### Initialize module ##############################################################################START####
sub DoorBird_Initialize($) {
    my ($hash)               = @_;
    $hash->{STATE}           = "Init";
    $hash->{DefFn}           = "DoorBird_Define";
    $hash->{UndefFn}         = "DoorBird_Undefine";
    $hash->{SetFn}           = "DoorBird_Set";
    $hash->{GetFn}           = "DoorBird_Get";
    $hash->{AttrFn}          = "DoorBird_Attr";
	$hash->{ReadFn}          = "DoorBird_Read";
	$hash->{DbLog_splitFn}   = "DoorBird_DbLog_splitFn";
	$hash->{FW_detailFn}     = "DoorBird_FW_detailFn";
	$hash->{NotifyFn}        = "DoorBird_Notify";										  
    $hash->{AttrList}        = "do_not_notify:1,0 " .
							   "header " .
							   "PollingTimeout:slider,1,1,20 " .
							   "MaxHistory:slider,0,1,50 " .
							   "KeepAliveTimeout " .
							   "UdpPort:6524,35344 " .
							   "ImageFileDir " .
							   "ImageFileDirMaxSize " .
							   "AudioFileDir " .
							   "AudioFileDirMaxSize " .
							   "VideoFileDir " .
							   "VideoFileDirMaxSize " .
							   "VideoFileFormat:mpeg,mpg,mp4,avi,mov,dvd,vob,ogg,ogv,mkv,flv,webm " .
							   "VideoDurationDoorbell " .
							   "VideoDurationMotion " .
							   "VideoDurationKeypad " .
							   "HistoryFilePath:1,0 " .
							   "EventReset " .
							   "SessionIdSec:slider,0,10,600 " .
							   "WaitForHistory " .
							   "OpsModeList " .
							   "disable:1,0 " .
						       "loglevel:slider,0,1,5 " .
						       $readingFnAttributes;
	return FHEM::Meta::InitMod( __FILE__, $hash );
}
####END####### Initialize module ###############################################################################END#####


###START######  Activate module after module has been used via fhem command "define" ##########################START####
sub DoorBird_Define($$) {
	my ($hash, $def)		= @_;
	my @a					= split("[ \t][ \t]*", $def);
	my $name				= $a[0];
							 #$a[1] just contains the "DoorBird" module name and we already know that! :-)
	my $url					= $a[2];

	return($@) unless(FHEM::Meta::SetInternals($hash));

	### Delete all Readings for DoorBird
	readingsDelete($hash, ".*");

	### Log Entry and state
	Log3 $name, 4, $name. " : DoorBird - Starting to define device " . $name . " with DoorBird module";
	readingsSingleUpdate($hash, "state", "define", 1);
	
	### Stop the current timer if one exists errornous 
	RemoveInternalTimer($hash);
	Log3 $name, 4, $name. " : DoorBird - InternalTimer has been removed.";
	
	
    ###START### Check whether all variables are available #####################################################START####
	if (int(@a) == 5) 
	{
		###START### Check whether IPv4 address is valid
		if ($url =~ m/^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(|:([0-9]{1,4}|[0-6][0-5][0-5][0-3][0-5])){1}$/)
		{
			Log3 $name, 4, $name. " : DoorBird - IPv4-address is valid                  : " . $url;
		}
		else
		{
			return $name .": Error - IPv4 address is not valid \n Please use \"define <devicename> DoorBird <IPv4-address> <Username> <Password>\" instead!\nExamples for <IPv4-address>:\n192.168.178.240\n192.168.178.240:0 to 192.168.178.240:65535";
		}
		####END#### Check whether IPv4 address is valid	
	}
	else
	{
	    return $name .": DoorBird - Error - Not enough parameter provided." . "\n" . "DoorBird station IPv4 address, Username and Password must be provided" ."\n". "Please use \"define <devicename> DoorBird <IPv4-address> <Username> <Password>\" instead";
	}
	####END#### Check whether all variables are available ######################################################END#####

	###START### Check whether username and password are already encrypted #####################################START####
	### If the username does not contain the "crypt" prefix, then it is still bareword
	if($a[3] =~ /^((?!crypt:).)*$/ ) {
		# Encrypt bareword username and password
		my $username 					= DoorBird_credential_encrypt($a[3]);
		my $password 					= DoorBird_credential_encrypt($a[4]);
		
		### Rewrite definition of device to remove bare passwords
		$hash->{DEF} 					= "$url $username $password";
		
		### Write encrypted credentials into hash
		$hash->{helper}{".USER"}		= $username;
		$hash->{helper}{".PASSWORD"}	= $password;

		### Write Log entry
		Log3 $name, 3, $name. " : DoorBird - Credentials have been encrypted for further use.";
	}
	### If the username contains the "crypt" prefix, then it is already encrypted
	else {
		### Write encrypted credentials into hash
		$hash->{helper}{".USER"}		= $a[3];
		$hash->{helper}{".PASSWORD"}	= $a[4];
	}
	####END#### Check whether username and password are already encrypted ######################################END#####

	###START###### Writing values to global hash ##############################################################START####
	  $hash->{NAME}										= $name;
	  $hash->{RevisonAPI}								= "0.36";
	  $hash->{helper}{SOX}	  							= "/usr/bin/sox"; #On Windows systems use "C:\Programme\sox\sox.exe"
	  $hash->{helper}{URL}	  							= $url;
	  $hash->{helper}{PollingTimeout}					= AttrVal($name,"PollingTimeout",5);
	  $hash->{helper}{KeepAliveTimeout}					= AttrVal($name, "KeepAliveTimeout", 30);
	  $hash->{helper}{MaxHistory}						= AttrVal($name, "MaxHistory", 50);
	  $hash->{helper}{HistoryTime}						= "????-??-?? ??:??";
	  $hash->{helper}{UdpPort}							= AttrVal($name, "UdpPort", 6524);
	  $hash->{helper}{SessionIdSec}						= AttrVal($name, "SessionIdSec", 540);
	  $hash->{helper}{ImageFileDir}						= AttrVal($name, "ImageFileDir", "");
	  $hash->{helper}{ImageFileDirMaxSize}				= AttrVal($name, "ImageFileDirMaxSize", 50);
	  $hash->{helper}{AudioFileDir}						= AttrVal($name, "AudioFileDir", "");
	  $hash->{helper}{AudioFileDirMaxSize}				= AttrVal($name, "AudioFileDirMaxSize", 50);
	  $hash->{helper}{VideoFileDir}						= AttrVal($name, "VideoFileDir", "");
	  $hash->{helper}{VideoFileDirMaxSize}				= AttrVal($name, "VideoFileDirMaxSize", 50);
	  $hash->{helper}{VideoFileFormat}					= AttrVal($name, "VideoFileFormat","mpeg");
	  $hash->{helper}{VideoDurationDoorbell}			= AttrVal($name, "VideoDurationDoorbell", 0);
	  $hash->{helper}{VideoDurationMotion}				= AttrVal($name, "VideoDurationMotion", 0);
	  $hash->{helper}{VideoDurationKeypad}				= AttrVal($name, "VideoDurationKeypad", 0);
	  $hash->{helper}{EventReset}						= AttrVal($name, "EventReset", 5);
	  $hash->{helper}{WaitForHistory}					= AttrVal($name, "WaitForHistory", 7);
	  $hash->{helper}{CameraInstalled}					= false;
	  $hash->{helper}{HistoryFilePath}					= 0;
	  $hash->{helper}{SessionId}						= 0;
	  $hash->{helper}{UdpMessageId}						= 0;
	  $hash->{helper}{UdpMotionId}						= 0;
	  $hash->{helper}{UdpDoorbellId}					= 0;
	  $hash->{helper}{UdpKeypadId}						= 0;
	@{$hash->{helper}{RelayAdresses}}					= (0);
	@{$hash->{helper}{Images}{History}{doorbell}}		= ();
	@{$hash->{helper}{Images}{History}{motionsensor}}	= ();
	@{$hash->{helper}{OpsModeList}}						= ();
	${$hash->{helper}{OpsModeListBackup}}[0]			= "Initial-gJ8990Gl";
	  $hash->{helper}{Images}{Individual}{Data}			= "";
	  $hash->{helper}{Images}{Individual}{Timestamp}	= "";
	  $hash->{helper}{HistoryDownloadActive} 			= false;
	  $hash->{helper}{HistoryDownloadCount}	 			= 0;
	  $hash->{reusePort} 								= AttrVal($name, 'reusePort', defined(&SO_REUSEPORT)?1:0)?1:0;
    ####END####### Writing values to global hash ##############################################################END#####

	### Check whether icon has already been defined
	if(!defined($attr{$name}{icon}))
	{
		### Set attribute with standard logo
		$attr{$name}{icon} = "doorbird";
	}
	
	### For Debugging purpose only 
	Log3 $name, 5, $name. " : DoorBird - Define H                               : " . $hash;
	Log3 $name, 5, $name. " : DoorBird - Define D                               : " . $def;
	Log3 $name, 5, $name. " : DoorBird - Define A                               : " . @a;
	Log3 $name, 5, $name. " : DoorBird - Define Name                            : " . $name;
	Log3 $name, 5, $name. " : DoorBird - Define OpsModeList                     : " . Dumper(@{$hash->{helper}{OpsModeList}});
	Log3 $name, 5, $name. " : DoorBird - Define OpsModeListBackup[0]            : " . ${$hash->{helper}{OpsModeListBackup}}[0];
	
	### Notify this device after changes on global variables
	$hash->{NOTIFYDEV} = "global,";

	### Call intitialization of sub if the initialization is done
	DoorBird_InitializeDevice($hash) if ($init_done);
	
	return undef;
}
####END####### Activate module after module has been used via fhem command "define" ############################END#####


###START###### Handle Notifications received by this module  ##################################################START####
sub DoorBird_Notify($$) {
	my ($hash, $dev) = @_;
	my $name    = $hash->{NAME};
	my $devName = $dev->{NAME}; # Device that created the events
	my $events  = deviceEvents($dev, 1);

	### For Debugging purpose only 
	Log3 $name, 5, $name. " : DoorBird - DoorBird_Notify devname                : " . $devName;
	Log3 $name, 5, $name. " : DoorBird - DoorBird_Notify events                 : " . $events =~ s/\r//g;

	### Return without any further action if the module is disabled
	return "" if(IsDisabled($name));

	### If the global variables notified an update and matches
	if($devName eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events}))
	{
		### For Debugging purpose only 
		Log3 $name, 5, $name. " : DoorBird_Notify                                   : fhem system has been initialized or config has been re-read.";
		
		### Call initialization 
		DoorBird_InitializeDevice($hash);
	}
	
	return undef;
}
###END######## Handle Notifications received by this module  ####################################################END####


##START###### Initialize the device when all attributes are available ########################################START####
sub DoorBird_InitializeDevice($) {
	my($hash) = @_;
	my $name    = $hash->{NAME};

	### Initialize Socket connection
	DoorBird_OpenSocketConn($hash);
	
	### Initialize Readings
	DoorBird_Info_Request($hash,  "");
	DoorBird_Image_Request($hash, "");
	DoorBird_Live_Video($hash, "off");

	### Initiate the timer for first time
	InternalTimer(gettimeofday()+ $hash->{helper}{KeepAliveTimeout}	, "DoorBird_LostConn",       $hash, 0);
	InternalTimer(gettimeofday()+ 10,                                 "DoorBird_RenewSessionID", $hash, 0);

	### For Debugging purpose only 
	Log3 $name, 3, $name. " : DoorBird_InitializeDevice                         : DoorBird has been initialized";

	return undef;
}
###END######## Initialize the device when all attributes are available #########################################END####

###START###### To bind unit of value to DbLog entries #########################################################START####
# sub DoorBird_DbLog_splitFn($$)
# {
   # return ();
# }
####END####### To bind unit of value to DbLog entries ##########################################################END#####


###START###### Deactivate module module after "undefine" command by fhem ######################################START####
sub DoorBird_Undefine($$) {
	my ($hash, $def)  = @_;
	my $name = $hash->{NAME};	
	my $url  = $hash->{URL};

  	### Stop the internal timer for this module
	RemoveInternalTimer($hash);

	### Close UDP scanning
	delete $selectlist{$name};
	if (defined($hash->{CD})) {
		$hash->{CD}->close();
		delete $hash->{CD};
	}
	delete $hash->{FD};
	### Add Log entry
	Log3 $name, 3, $name. " - DoorBird has been undefined. The DoorBird unit will no longer polled.";

	return undef;
}
####END####### Deactivate module module after "undefine" command by fhem #######################################END#####


###START###### Handle attributes after changes via fhem GUI ###################################################START####
sub DoorBird_Attr(@) {
	my @a                      = @_;
	my $name                   = $a[1];
	my $hash                   = $defs{$name};

	Log3 $name, 5, $name. " : DoorBird_Attr - Subfunction entered.";

	### Check whether disable attribute has been provided
	if ($a[2] eq "disable") {
		### Check whether device shall be disabled
		if ($a[3] == 1) {
			### Update STATE of device
			readingsSingleUpdate($hash, "state", "disabled", 1);
			
			### Stop the current timer
			RemoveInternalTimer($hash);
			Log3 $name, 4, $name. " : DoorBird - InternalTimer has been removed.";

			### Delete all Readings
			readingsDelete($hash, ".*");

			### Update STATE of device
			readingsSingleUpdate($hash, "state", "disconnected", 1);
			
			Log3 $name, 3, $name. " : DoorBird - Device disabled as per attribute.";
		}
		else {
			### Update STATE of device
			readingsSingleUpdate($hash, "state", "disconnected", 1);
			Log3 $name, 4, $name. " : DoorBird - Device enabled as per attribute.";
		}
	}
	### Check whether UdpPort attribute has been provided
	elsif ($a[2] eq "UdpPort") {
		### Check whether UdpPort is numeric
		if ($a[3] == int($a[3])) {
			### Set helper in hash
			$hash->{helper}{UdpPort} = $a[3];
			
			### Call initialization 
			DoorBird_InitializeDevice($hash);
		}
	}
	### Check whether PollingTimeout attribute has been provided
	elsif ($a[2] eq "PollingTimeout") {
		### Check whether PollingTimeout is numeric
		if (($a[3] == int($a[3])) && ($a[3] > 0)) {
			### Check whether PollingTimeout is positiv and smaller or equal than 10s
			if (($a[3] > 0) && ($a[3] <= 10)) {
				### Save attribute as internal
				$hash->{helper}{PollingTimeout}	= $a[3];
			}
			### If PollingTimeout is NOT positiv and smaller or equal than 10s
			else {
				### Return error message to GUI
			}
		}
		### If PollingTimeout is NOT numeric
		else {
			### Do nothing
		}
	}
	### Check whether MaxHistory attribute has been provided
	elsif ($a[2] eq "MaxHistory") {
		### Check whether MaxHistory is numeric
		if ($a[3] == int($a[3])) {
			### Check whether MaxHistory is positiv and smaller or equal than 50
			if (($a[3] >= 0) && ($a[3] <= 50)) {
				### Save attribute as internal
				$hash->{helper}{MaxHistory}	= $a[3];
			}
			### If MaxHistory is NOT positiv and smaller or equal than 50
			else {
				### Save attribute as internal
				$hash->{helper}{MaxHistory}	= 50;
			}
		}
		### If MaxHistory is NOT numeric
		else {
			### Save attribute as internal
			$hash->{helper}{MaxHistory}	= 50;
		}
	}
	### Check whether KeepAliveTimeout attribute has been provided
	elsif ($a[2] eq "KeepAliveTimeout") {
		### Remove Timer for LostConn
		RemoveInternalTimer($hash, "DoorBird_LostConn");
		
		### Check whether KeepAliveTimeout is numeric and greater or equal than 10
		if ($a[3] == int($a[3]) && ($a[3] >= 10)) {
			### Save attribute as internal
			$hash->{helper}{KeepAliveTimeout}  = $a[3];
		}
		### If KeepAliveTimeout is NOT numeric or smaller than 10
		else {
			### Save attribute as internal
			$hash->{helper}{KeepAliveTimeout}	= 30;
		}
		### Initiate the timer for first time
		InternalTimer(gettimeofday()+$hash->{helper}{KeepAliveTimeout}, "DoorBird_LostConn", $hash, 0);
	}
	### Check whether SessionIdSec attribute has been provided
	elsif ($a[2] eq "SessionIdSec") {	
		### Remove Timer for LostConn
		RemoveInternalTimer($hash, "DoorBird_RenewSessionID");

		### If the attribute has not been deleted entirely
		if (defined $a[3]) {
	
			### Check whether SessionIdSec is 0 = disabled
			if ($a[3] == int($a[3]) && ($a[3] == 0)) {
				### Save attribute as internal
				$hash->{helper}{SessionIdSec} = 0;
				$hash->{helper}{SessionId}    = 0;
			}
			### If KeepAliveTimeout is numeric and greater than 9s
			elsif ($a[3] == int($a[3]) &&  ($a[3] > 9)) {

				### Save attribute as internal
				$hash->{helper}{SessionIdSec} = $a[3];

				### Obtain SessionId
				DoorBird_RenewSessionID($hash);

				### Re-Initiate the timer
				InternalTimer(gettimeofday()+$hash->{helper}{SessionIdSec}, "DoorBird_RenewSessionID", $hash, 0);
			}
			### If KeepAliveTimeout is NOT numeric or smaller than 10
			else{
				### Save standard interval as internal
				$hash->{helper}{SessionIdSec}  = 540;
				
				### Obtain SessionId
				DoorBird_RenewSessionID($hash);
				
				### Re-Initiate the timer
				InternalTimer(gettimeofday()+$hash->{helper}{SessionIdSec}, "DoorBird_RenewSessionID", $hash, 0);
			}
		}
		### If the attribute has been deleted entirely
		else{
			### Save standard interval as internal
			$hash->{helper}{SessionIdSec}  = 540;
			
			### Obtain SessionId
			DoorBird_RenewSessionID($hash);
				
			### Re-Initiate the timer
			InternalTimer(gettimeofday()+$hash->{helper}{SessionIdSec}, "DoorBird_RenewSessionID", $hash, 0);
		}
	}
	### Check whether ImageFileDir attribute has been provided
	elsif ($a[2] eq "ImageFileDir") {
		### Check whether ImageFileSave is defined
		if (defined($a[3])) {
			### Set helper in hash
			$hash->{helper}{ImageFileDir} = $a[3];
		}
		else {
			### Set helper in hash
			$hash->{helper}{ImageFileDir} = "";
		}
	}
	### Check whether ImageFileDirMaxSize attribute has been provided
	elsif ($a[2] eq "ImageFileDirMaxSize") {	

		### If the attribute has not been deleted entirely
		if (defined $a[3]) {
			### Check whether ImageFileDirMaxSize is 0 = disabled
			if ($a[3] == int($a[3]) && ($a[3] <= 50)) {
				### Save standard value
				$hash->{helper}{ImageFileDirMaxSize} = 50;
			}
			### If ImageFileDirMaxSize is numeric and greater than 50
			elsif ($a[3] == int($a[3]) &&  ($a[3] > 50)) {

				### Save attribute as internal
				$hash->{helper}{ImageFileDirMaxSize} = $a[3];
			}
			### If KeepAliveTimeout is NOT numeric or smaller than 50
			else{
				### Save standard interval as internal
				$hash->{helper}{ImageFileDirMaxSize} = 50;
			}
		}
		### If the attribute has been deleted entirely
		else {
			### Save standard interval as internal
			$hash->{helper}{ImageFileDirMaxSize} = 50;
		}	
	}
	### Check whether AudioFileDir attribute has been provided
	elsif ($a[2] eq "AudioFileDir") {
		### Check whether AudioFileSave is defined
		if (defined($a[3])) {
			### Set helper in hash
			$hash->{helper}{AudioFileDir} = $a[3];
		}
		else {
			### Set helper in hash
			$hash->{helper}{AudioFileDir} = "";
		}
	}
	### Check whether AudioFileDirMaxSize attribute has been provided
	elsif ($a[2] eq "AudioFileDirMaxSize") {	

		### If the attribute has not been deleted entirely
		if (defined $a[3]) {
			### Check whether AudioFileDirMaxSize is 0 = disabled
			if ($a[3] == int($a[3]) && ($a[3] <= 50)) {
				### Save standard value
				$hash->{helper}{AudioFileDirMaxSize} = 50;
			}
			### If AudioFileDirMaxSize is numeric and greater than 50
			elsif ($a[3] == int($a[3]) &&  ($a[3] > 50)) {

				### Save attribute as internal
				$hash->{helper}{AudioFileDirMaxSize} = $a[3];
			}
			### If KeepAliveTimeout is NOT numeric or smaller than 50
			else{
				### Save standard interval as internal
				$hash->{helper}{AudioFileDirMaxSize} = 50;
			}
		}
		### If the attribute has been deleted entirely
		else {
			### Save standard interval as internal
			$hash->{helper}{AudioFileDirMaxSize} = 50;
		}	
	}
	### Check whether VideoFileDir attribute has been provided
	elsif ($a[2] eq "VideoFileDir") {
		### Check whether VideoFileSave is defined
		if (defined($a[3])) {
			### Set helper in hash
			$hash->{helper}{VideoFileDir} = $a[3];
		}
		else {
			### Set helper in hash
			$hash->{helper}{VideoFileDir} = "";
		}
	}
	### Check whether VideoFileDirMaxSize attribute has been provided
	elsif ($a[2] eq "VideoFileDirMaxSize") {	

		### If the attribute has not been deleted entirely
		if (defined $a[3]) {
			### Check whether VideoFileDirMaxSize is 0 = disabled
			if ($a[3] == int($a[3]) && ($a[3] <= 50)) {
				### Save standard value
				$hash->{helper}{VideoFileDirMaxSize} = 50;
			}
			### If VideoFileDirMaxSize is numeric and greater than 50
			elsif ($a[3] == int($a[3]) &&  ($a[3] > 50)) {

				### Save attribute as internal
				$hash->{helper}{VideoFileDirMaxSize} = $a[3];
			}
			### If KeepAliveTimeout is NOT numeric or smaller than 50
			else{
				### Save standard interval as internal
				$hash->{helper}{VideoFileDirMaxSize} = 50;
			}
		}
		### If the attribute has been deleted entirely
		else {
			### Save standard interval as internal
			$hash->{helper}{VideoFileDirMaxSize} = 50;
		}	
	}	
	### Check whether VideoDurationDoorbell attribute has been provided
	elsif ($a[2] eq "VideoDurationDoorbell") {
		### Check whether VideoDurationDoorbell is defined
		if (defined($a[3])) {
			### Set helper in hash
			$hash->{helper}{VideoDurationDoorbell} = $a[3];
		}
		else {
			### Set helper in hash
			$hash->{helper}{VideoDurationDoorbell} = "0";
		}
	}
	### Check whether VideoDurationMotion attribute has been provided
	elsif ($a[2] eq "VideoDurationMotion") {
		### Check whether VideoDurationMotion is defined
		if (defined($a[3])) {
			### Set helper in hash
			$hash->{helper}{VideoDurationMotion} = $a[3];
		}
		else {
			### Set helper in hash
			$hash->{helper}{VideoDurationMotion} = "0";
		}
	}	
	### Check whether VideoDurationKeypad attribute has been provided
	elsif ($a[2] eq "VideoDurationKeypad") {
		### Check whether VideoDurationKeypad is defined
		if (defined($a[3])) {
			### Set helper in hash
			$hash->{helper}{VideoDurationKeypad} = $a[3];
		}
		else {
			### Set helper in hash
			$hash->{helper}{VideoDurationKeypad} = "0";
		}
	}
	### Check whether HistoryFilePath attribute has been provided
	elsif ($a[2] eq "HistoryFilePath") {
		### Check whether HistoryFilePath is defined
		if (defined($a[3])) {
			### Set helper in hash
			$hash->{helper}{HistoryFilePath} = $a[3];
			
			if ($a[3] == true) {
				### Update the history list for images and videos
				DoorBird_History_List($hash);
			}
			else {
				### Delete all reading entries to files
				fhem("deleteReading " . $name . " HistoryFilePath.*");
			}
		}
		else {
			### Set helper in hash
			$hash->{helper}{HistoryFilePath} = "0";
			
			### Delete all reading entries to files
			fhem("deleteReading " . $name . " HistoryFilePath.*");
		}
	}
	### Check whether VideoFileFormat attribute has been provided
	elsif ($a[2] eq "VideoFileFormat") {
		### Check whether VideoFileFormat is defined
		if (defined($a[3])) {
			### Set helper in hash
			$hash->{helper}{VideoFileFormat} = $a[3];
		}
		else {
			### Set helper in hash
			$hash->{helper}{VideoFileFormat} = "mpeg";
		}
	}
	### Check whether EventReset attribute has been provided
	elsif ($a[2] eq "EventReset") {
		### Remove Timer for Event Reset
		RemoveInternalTimer($hash, "DoorBird_EventResetMotion");
		RemoveInternalTimer($hash, "DoorBird_EventResetDoorbell");
		#RemoveInternalTimer($hash, "DoorBird_EventResetKeypad");
		
		### Check whether EventReset is numeric and greater than 0
		if ($a[3] == int($a[3]) && ($a[3] > 0)) {
			### Save attribute as internal
			$hash->{helper}{EventReset}  = $a[3];
		}
		### If KeepAliveTimeout is NOT numeric or 0
		else {
			### Save attribute as internal
			$hash->{helper}{EventReset}	= 5;
		}
	}
	### Check whether WaitForHistory attribute has been provided
	elsif ($a[2] eq "WaitForHistory") {
		### Check whether WaitForHistory is numeric and greater than 5
		if ($a[3] == int($a[3]) && ($a[3] > 5)) {
			### Save attribute as internal
			$hash->{helper}{WaitForHistory}  = $a[3];
		}
		### If KeepAliveTimeout is NOT numeric or <5
		else {
			### Save attribute as internal
			$hash->{helper}{WaitForHistory}	= 5;
		}
	}
	### Check whether OpsModeList attribute has been provided
	elsif ($a[2] eq "OpsModeList") {
		
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_Attr - OpsModeList entered";
		Log3 $name, 5, $name. " : DoorBird_Attr - {OpsModeListBackup}}[0]           : " . ${$hash->{helper}{OpsModeListBackup}}[0];
		
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_Attr - OpsModeListBackup is not initial ";

		### If the attribute has not been deleted entirely or is empty
		if (defined $a[3]) {
			### Save OpsList and empty string as internal
			@{$hash->{helper}{OpsModeList}}	  = split(/ /, $a[3]);
			
			### Update depending Readings
			DoorBird_OpsModeUpdate($hash);
		}
		### If the attribute has been deleted entirely or is empty
		else {
			### Save OpsList and empty string as internal
			@{$hash->{helper}{OpsModeList}}	  = "";

			### Update depending Readings
			DoorBird_OpsModeUpdate($hash);
		}
	}	
	### If no attributes of the above known ones have been selected
	else {
		# Do nothing
	}
	return undef;
}
####END####### Handle attributes after changes via fhem GUI ####################################################END#####

###START###### Obtain value after "get" command by fhem #######################################################START####
sub DoorBird_Get($@) {
	my ( $hash, @a ) = @_;
	
	### If not enough arguments have been provided
	if ( @a < 2 )
	{
		return "\"get DoorBird\" needs at least one argument";
	}
		
	my $name	= shift @a;
	my $command	= shift @a;
	my $option	= shift @a;
	my $optionString;
	
	### Create String to avoid perl warning if option is empty
	if (defined $option) {
		$optionString = $option;
	}
	else {
		$optionString = " ";
	}
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Get - name                               : " . $name;
	Log3 $name, 5, $name. " : DoorBird_Get - command                            : " . $command;
	Log3 $name, 5, $name. " : DoorBird_Get - option                             : " . $optionString;
	
	### Define "get" menu
	my $usage	= "Unknown argument, choose one of ";
	   $usage  .= "Info_Request:noArg List_Favorites:noArg List_Schedules:noArg ";
	
	### If DoorBird has a Camera installed
	if ($hash->{helper}{CameraInstalled} == true) {
		$usage .= "Image_Request:noArg History_Request:noArg Video_Request "
	}
	### If DoorBird has NO Camera installed
	else {
		# Do not add anything
	}
	### Return values
	return $usage if $command eq '?';
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Get - usage                              : " . $usage;

	### INFO REQUEST
	if ($command eq "Info_Request") {
		### Call Subroutine and hand back return value
		return DoorBird_Info_Request($hash, $option);
	}
	### IMAGE REQUEST
	elsif ($command eq "Image_Request") {
		### Call Subroutine and hand back return value
		return DoorBird_Image_Request($hash, $option);
	}
	### VIDEO REQUEST
	elsif ($command eq "Video_Request") {
		my $VideoDuration = 10;
		### If the duration has been given use it. Otherwise use 10s
		if ( $optionString == int($optionString) and $optionString eq int($optionString) and $optionString > 0 ) {
			$VideoDuration = $optionString;
		}
		### Call Subroutine and hand back return value
		return DoorBird_Video_Request($hash, $VideoDuration, "manual", time());
	}
	### HISTORY IMAGE REQUEST
	elsif ($command eq "History_Request") {
		if ($hash->{helper}{HistoryDownloadActive} == false) {
			### Call Subroutine and hand back return value
			return DoorBird_History_Request($hash, $option);
		}
		else {
			return "History download already in progress.\nPlease wait and try again later."
		}
	}	
	### LIST FAVORITES
	elsif ($command eq "List_Favorites") {
		### Call Subroutine and hand back return value
		return DoorBird_List_Favorites($hash, $option);
	}
	### LIST SCHEDULES
	elsif ($command eq "List_Schedules") {
		### Call Subroutine and hand back return value
		return DoorBird_List_Schedules($hash, $option);
	}
	### If none of the known options has been chosen
	else {
		### Do nothing
		return
	}
	### MONITOR REQUEST
	### To be implemented via UDP
}
####END####### Obtain value after "get" command by fhem ########################################################END#####


###START###### Manipulate service after "set" command by fhem #################################################START####
sub DoorBird_Set($@) {
	my ( $hash, @a ) = @_;
	
	### If not enough arguments have been provided
	if ( @a < 2 )
	{
		return "\"get DoorBird\" needs at least one argument";
	}
	
	my $name				= shift @a;
	my $command				= shift @a;
	my $option				= shift @a;
	my $ErrorMessage		= "";
	my $optionString;
	my $AudioFileDir		=   $hash->{helper}{AudioFileDir};
	my @RelayAdresses		= @{$hash->{helper}{RelayAdresses}};
	my @OpsModeList   		= @{$hash->{helper}{OpsModeList}};
	
	### Create String to avoid perl warning if option is empty
	if (defined $option) {
		$optionString = $option;
	}
	else {
		$optionString = " ";
	}
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Set _______________________________________________________________________";
	Log3 $name, 5, $name. " : DoorBird_Set - name                               : " . $name;
	Log3 $name, 5, $name. " : DoorBird_Set - command                            : " . $command;
	Log3 $name, 5, $name. " : DoorBird_Set - option                             : " . $optionString;
	Log3 $name, 5, $name. " : DoorBird_Set - RelayAdresses                      : " . join(",", @RelayAdresses);
	Log3 $name, 5, $name. " : DoorBird_Set - OpsModeList                        : " . join(" ", @OpsModeList);
	
	### Define "set" menu
	my $usage	= "Unknown argument, choose one of";
		#$usage .= " Test";
		$usage .= " Open_Door:" . join(",", @RelayAdresses) . " OpsMode:" . join(",", @OpsModeList) . " Restart:noArg Transmit_Audio";
		$usage .= " Receive_Audio";

	### If the OpsModeList is not empty
	if ((defined(${$hash->{helper}{OpsModeList}}[0])) && (${$hash->{helper}{OpsModeList}}[0] ne "")) {

		### Log Entry for debugging purposes	
		Log3 $name, 5, $name. " : DoorBird_Set - The OpsModeList is empty";
		Log3 $name, 5, $name. " : DoorBird_Set - OpsModeList                        : " . join(" ", Dumper(@{$hash->{helper}{OpsModeList}}));

		### For each item in the list of possible Operation Modes
		foreach (@OpsModeList) {
			
			### Set Prefix for ReadingsName
			my $OpsModeReadingPrefix = "OpsMode" . $_;

			### For each DoorBirdEvent, create setlist for icon
			# $usage .= " " . $OpsModeReadingPrefix . "Icon";
		
			### For each DoorBirdEvent, create setlist for relays to be activated in case of event
			$usage .= " " . $OpsModeReadingPrefix . "DoorbellRelay:" . "Off," . join(",", @RelayAdresses);
			$usage .= " " . $OpsModeReadingPrefix . "MotionRelay:" . "Off," . join(",", @RelayAdresses);
		   #$usage .= " " . $OpsModeReadingPrefix . "KeypadRelay:"   . "Off," . join(",", @RelayAdresses);

			### If the Attribute for the directories of the audiofiles have bene provided
			if ($AudioFileDir ne "") {

				### Get current working directory
				my $cwd = getcwd();

				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_Set - working directory                  : " . $cwd;

				### If the path is given as UNIX file system format
				if ($cwd =~ /\//) {
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_Set - file system format                 : LINUX";

					### Find out whether it is an absolute path or an relative one (leading "/")
					if ($AudioFileDir =~ /^\//) {
						$AudioFileDir = $AudioFileDir;
					}
					else {
						$AudioFileDir = $cwd . "/" . $AudioFileDir;						
					}
					
					### Remove last / of directory if exists
					$AudioFileDir =~ s/\/\z//;
					
				}
				### If the path is given as Windows file system format
				elsif ($cwd =~ /\\/) {
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_Set - file system format                 : WINDOWS";

					### Find out whether it is an absolute path or an relative one (containing ":\")
					if ($AudioFileDir != /^.:\//) {
						$AudioFileDir = $cwd . $AudioFileDir;
					}
					else {
						$AudioFileDir = $AudioFileDir;						
					}
					
					### Remove last \ of directory if exists
					$AudioFileDir =~ s/\\\z//;
					
				}
				### If nothing matches above
				else {
					### Set directory to nothing
					$AudioFileDir = "";
				}
				
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_Set - AudioFileDir                       : " . $AudioFileDir;

				### Get content of subdirectory and eliminate the root directories "." and ".."
				my @AudioFileList;
				eval {
					opendir(ReadOut,$AudioFileDir) or die "Could not open '$AudioFileDir' for reading";
					@AudioFileList = grep(/^([^.]+)./, readdir(ReadOut));
					close ReadOut;
				};
				### If error message appered
				if ( $@ ) {
					$ErrorMessage = $@;
				}
				### If no error message appeared and therefore directory exists
				else {
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_Set - AudioFileList                      : " . join(",", @AudioFileList);

					### For each DoorBirdEvent, create setlist for the file path for the audio messages
					$usage .= " " . $OpsModeReadingPrefix . "DoorbellAudio:Off,". join(",", @AudioFileList);
					$usage .= " " . $OpsModeReadingPrefix . "MotionAudio:Off,". join(",", @AudioFileList);
				   #$usage .= " " . $OpsModeReadingPrefix . "KeypadAudio:Off,"  . join(",", @AudioFileList);
			   }
			}
		}
	}

	### If DoorBird has a Camera installed
	if ($hash->{helper}{CameraInstalled} == true) {
		### Create Selection List for camera
		$usage .= " Live_Video:on,off Light_On:noArg Live_Audio:on,off ";
	}
	### If DoorBird has NO Camera installed
	else {
		# Do not add anything
	}

	### Log Entry for debugging purposes
	Log3 $name, 5, $name . " : DoorBord_Set - " . $ErrorMessage;
	Log3 $name, 2, $name . " : DoorBord_Set - Could not open directory for audiofiles. See commandref for attribute \"AudioFileDir\"." if $ErrorMessage ne "";
	Log3 $name, 5, $name . " : DoorBird_Set - usage                              : " . $usage;

	### Return values
	return $usage if $command eq '?';
	
	######### Section for response on set-command ##########################################################

	### LIVE VIDEO REQUEST
	if ($command eq "Live_Video") {
		### Call Subroutine and hand back return value
		return DoorBird_Live_Video($hash, $option)	
	}
	### OPEN DOOR
	elsif ($command eq "Open_Door") {
		### Call Subroutine and hand back return value
		$hash->{helper}{OpenRelay} = $option;
		return DoorBird_Open_Door($hash);
	}
	### LIGHT ON
	elsif ($command eq "Light_On") {
		### Call Subroutine and hand back return value
		return DoorBird_Light_On($hash, $option)	
	}
	### RESTART
	elsif ($command eq "Restart") {
		### Call Subroutine and hand back return value
		return DoorBird_Restart($hash, $option)	
	}
	### LIVE AUDIO RECEIVE
	elsif ($command eq "Live_Audio") {
		### Call Subroutine and hand back return value
		return DoorBird_Live_Audio($hash, $option)	
	}
	### AUDIO RECEIVE
	elsif ($command eq "Receive_Audio") {
		### Call Subroutine and hand back return value
		return DoorBird_Receive_Audio($hash, $option)	
	}
	### AUDIO TRANSMIT
	elsif ($command eq "Transmit_Audio") {
		### Call Subroutine and hand back return value
		return DoorBird_Transmit_Audio($hash, $option)	
	}
	### TEST
	elsif ($command eq "Test") {
		DoorBird_History_List($hash);
	}
	### ADD OR CHANGE FAVORITE
	### DELETE FAVORITE
	### ADD OR UPDATE SCHEDULE ENTRY
	### DELETE SCHEDULE ENTRY
	### If none of the above have been selected
	else {
		### Update Reading
		readingsSingleUpdate($hash, $command, $option, 1);

		### Refresh Browser Window
		FW_directNotify("#FHEMWEB:$FW_wname", "location.reload()", "") if defined($FW_wname);
		
		### Save new Readings in stat file
		WriteStatefile();
		return
	}
}
####END####### Manipulate service after "Set" command by fhem ##################################################END#####

###START###### Update Readings and variables after update of Operation Mode ###################################START####
sub DoorBird_OpsModeUpdate($) {
	my ($hash)			= @_;

	### Obtain values from hash
	my $name			= $hash->{NAME};
	my @OpsModeList		= @{$hash->{helper}{OpsModeList}};
	my $OpsModeActive	= ReadingsVal($name, "OpsMode", "");
	my $AudioFileDir	= $hash->{helper}{AudioFileDir};

	### Extract all names of Readings which start with "OpsMode"
	my @OpsModeReadings = grep(/OpsMode/, keys(%{$hash->{READINGS}}));

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_OpsModeUpdate ____________________________________________________________";
	Log3 $name, 5, $name. " : DoorBird_OpsModeUpdate - OpsModeList              : " . join(" ", Dumper(@{$hash->{helper}{OpsModeList}}));
	Log3 $name, 5, $name. " : DoorBird_OpsModeUpdate - OpsModeListBackup        : " . join(" ", Dumper(@{$hash->{helper}{OpsModeListBackup}}));
	Log3 $name, 5, $name. " : DoorBird_OpsModeUpdate - Size of OpsModeList      : " . @OpsModeList;
	Log3 $name, 5, $name. " : DoorBird_OpsModeUpdate - OpsModeActive            : " . $OpsModeActive;
	Log3 $name, 5, $name. " : DoorBird_OpsModeUpdate - AudioFileDir             : " . $AudioFileDir;
	Log3 $name, 5, $name. " : DoorBird_OpsModeUpdate - Readings Current         : " . join(" ", Dumper(@OpsModeReadings));

	### If the OpsModeList has been changed
	if (join(",", @{$hash->{helper}{OpsModeListBackup}}) ne join(",", @{$hash->{helper}{OpsModeList}})) {
	### Log Entry for debugging purposes	
	Log3 $name, 5, $name. " : DoorBird_OpsModeUpdate - The OpsModeList is different from the Backup!";

		### If the OpsModeList has not been deleted (is not empty) and is not in initial state
		if ((${$hash->{helper}{OpsModeList}}[0] ne "") && (${$hash->{helper}{OpsModeListBackup}}[0] ne "Initial-gJ8990Gl")) {

			### Save new list as backup
			@{$hash->{helper}{OpsModeListBackup}} = @{$hash->{helper}{OpsModeList}};
	
			### Log Entry for debugging purposes	
			Log3 $name, 5, $name. " : DoorBird_OpsModeUpdate - The OpsModeList is filled but not in initial state!";
			Log3 $name, 5, $name. " : DoorBird_OpsModeUpdate - OpsModeList              : " . join(" ", Dumper(@{$hash->{helper}{OpsModeList}}));
			Log3 $name, 5, $name. " : DoorBird_OpsModeUpdate - Readings Old             : " . join(" ", Dumper(@OpsModeReadings));	
		
			### Delete all Readings which start with "OpsMode"
			foreach (@OpsModeReadings) {
				### Delete all depending Readings
				readingsDelete($hash, $_);
			}
			
			### Update Reading for the active Operation Mode with the first item of the list
			readingsSingleUpdate($hash, "OpsMode", ${$hash->{helper}{OpsModeList}}[0], 1);

			### For each item in the list of possible Operation Modes
			foreach (@OpsModeList) {
				
				### Set Prefix for ReadingsName
				my $OpsModeReadingPrefix = "OpsMode" . $_;
			
				### For each DoorBirdEvent, create Reading for the file path for the audio messages
				readingsSingleUpdate($hash, $OpsModeReadingPrefix . "DoorbellAudio", "", 1);
				readingsSingleUpdate($hash, $OpsModeReadingPrefix . "MotionAudio", "", 1);		
				#readingsSingleUpdate($hash, $OpsModeReadingPrefix . "KeypadAudio",   "", 1);		
				
				### For each DoorBirdEvent, create Reading for relays to be activated in case of event
				readingsSingleUpdate($hash, $OpsModeReadingPrefix . "DoorbellRelay", "", 1);
				readingsSingleUpdate($hash, $OpsModeReadingPrefix . "MotionRelay", "", 1);		
				#readingsSingleUpdate($hash, $OpsModeReadingPrefix . "KeypadRelay",   "", 1);		
			}
			### Save new Readings in stat file
			WriteStatefile();
			
			### Log Entry for debugging purposes	
			my @OpsModeReadingsNew = grep(/OpsMode/, keys(%{$hash->{READINGS}}));
			Log3 $name, 5, $name. " : DoorBird_OpsModeUpdate - Readings New             : " . Dumper(@OpsModeReadingsNew);
			
		}
		### If the OpsModeList is empty (is empty) and is not in initial state
		elsif ((${$hash->{helper}{OpsModeList}}[0] eq "") && (${$hash->{helper}{OpsModeListBackup}}[0] ne "Initial-gJ8990Gl")) {

			### Save new list as backup
			@{$hash->{helper}{OpsModeListBackup}} = @{$hash->{helper}{OpsModeList}};

			### Extract all names of Readings which start with "OpsMode"
			my @OpsModeReadings = grep(/OpsMode/, keys(%{$hash->{READINGS}}));

			### Save new list as backup
			@{$hash->{helper}{OpsModeListBackup}} = @{$hash->{helper}{OpsModeList}};	

			### Log Entry for debugging purposes	
			Log3 $name, 5, $name. " : DoorBird_OpsModeUpdate - The OpsModeList is empty but not in initial state!";
			Log3 $name, 5, $name. " : DoorBird_OpsModeUpdate - OpsModeList              : " . join(" ", Dumper(@{$hash->{helper}{OpsModeList}}));
			Log3 $name, 5, $name. " : DoorBird_OpsModeUpdate - OpsModeListBackup        : " . join(" ", Dumper(@{$hash->{helper}{OpsModeListBackup}}));
			Log3 $name, 5, $name. " : DoorBird_OpsModeUpdate - Readings to be deleted   : " . join(" ", Dumper(@OpsModeReadings));
		
			### Delete all Readings which start with "OpsMode"
			foreach (@OpsModeReadings) {
				### Delete all depending Readings
				readingsDelete($hash, $_);
			}
		}
		### If the OpsModeList has not been deleted (is not empty) and is in initial state
		elsif ((${$hash->{helper}{OpsModeList}}[0] ne "") && (${$hash->{helper}{OpsModeListBackup}}[0] eq "Initial-gJ8990Gl")) {
			### Log Entry for debugging purposes	
			Log3 $name, 5, $name. " : DoorBird_OpsModeUpdate - The OpsModeList is NOT empty and in initial state!";

			### Save new list as backup
			@{$hash->{helper}{OpsModeListBackup}} = @{$hash->{helper}{OpsModeList}};		
		}
		### If the OpsModeList has been deleted (is empty) and is in initial state
		elsif ((${$hash->{helper}{OpsModeList}}[0] eq "") && (${$hash->{helper}{OpsModeListBackup}}[0] eq "Initial-gJ8990Gl")) {
			
			### Log Entry for debugging purposes	
			Log3 $name, 5, $name. " : DoorBird_OpsModeUpdate - The OpsModeList is empty and in initial state!";
			
			### Save new list as backup
			@{$hash->{helper}{OpsModeListBackup}} = @{$hash->{helper}{OpsModeList}};		
		}
		### If the OpsModeList is in unknown state
		else {
			### Log Entry for debugging purposes	
			Log3 $name, 5, $name. " : DoorBird_OpsModeUpdate - The OpsModeList is in unknown state!";
			Log3 $name, 5, $name. " : DoorBird_OpsModeUpdate - OpsModeList              : " . join(" ", Dumper(@{$hash->{helper}{OpsModeList}}));
			Log3 $name, 5, $name. " : DoorBird_OpsModeUpdate - OpsModeListBackup Old    : " . join(" ", Dumper(@{$hash->{helper}{OpsModeListBackup}}));
			
			### Save new list as backup
			@{$hash->{helper}{OpsModeListBackup}} = @{$hash->{helper}{OpsModeList}};
			
			Log3 $name, 3, $name. " : DoorBird_OpsModeUpdate - OpsModeListBackup New    : " . join(" ", Dumper(@{$hash->{helper}{OpsModeListBackup}}));
		}
	}
	### If the OpsModeList has not been changed
	else {
		### Log Entry for debugging purposes	
		Log3 $name, 5, $name. " : DoorBird_OpsModeUpdate - The OpsModeList has not been changed.";
	}
}
####END####### Update Readings and variables after update of Operation Mode ####################################END#####

###START###### Execution of automatic events depending on operation mode ######################################START####
sub DoorBird_OpsModeExecute($$) {
	my ($hash, $OpsModeEvent)	= @_;

	### Obtain values from hash
	my $name				 =   $hash->{NAME};
	my $AudioFileDir		 =   $hash->{helper}{AudioFileDir};
	my $Sox					 =   $hash->{helper}{SOX};
	my @OpsModeList			 = @{$hash->{helper}{OpsModeList}};
	my $OpsModeActive		 = ReadingsVal($name, "OpsMode", "");
	my $OpsModeReadingPrefix = "OpsMode" . $OpsModeActive;
	my $ReadingNameRelay;
	my $ReadingNameAudio;	

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_OpsModeExecute ___________________________________________________________";
	Log3 $name, 5, $name. " : DoorBird_OpsModeExecute - OpsModeList             : " . join(" ", Dumper(@OpsModeList));
	Log3 $name, 5, $name. " : DoorBird_OpsModeExecute - OpsModeActive           : " . $OpsModeActive;
	Log3 $name, 5, $name. " : DoorBird_OpsModeExecute - AudioFileDir            : " . $AudioFileDir;
	Log3 $name, 5, $name. " : DoorBird_OpsModeExecute - OpsModeEvent            : " . $OpsModeEvent;
	
	### Get current working directory
	my $cwd = getcwd();

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_OpsModeExecute - working directory       : " . $cwd;

	### If the path is given as UNIX file system format
	if ($cwd =~ /\//) {
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_OpsModeExecute - file system format      : LINUX";

		### Find out whether it is an absolute path or an relative one (leading "/")
		if ($AudioFileDir =~ /^\//) {
			$AudioFileDir = $AudioFileDir;
		}
		else {
			$AudioFileDir = $cwd . "/" . $AudioFileDir;						
		}
		
		### Remove last / of directory if exists
		$AudioFileDir =~ s/\/\z//;
		
		### Add last / for definitiv
		$AudioFileDir .= "/";
	}
	### If the path is given as Windows file system format
	elsif ($cwd =~ /\\/) {
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_OpsModeExecute - file system format      : WINDOWS";

		### Find out whether it is an absolute path or an relative one (containing ":\")
		if ($AudioFileDir != /^.:\//) {
			$AudioFileDir = $cwd . $AudioFileDir;
		}
		else {
			$AudioFileDir = $AudioFileDir;						
		}
		
		### Remove last \ of directory if exists
		$AudioFileDir =~ s/\\\z//;
		
		### Add last \ for definitiv
		$AudioFileDir .= "\\";
	}
	### If nothing matches above
	else {
		### Set directory to nothing
		$AudioFileDir = "";
	}
	
	### If the event has been triggered by a doorbell event
	if ($OpsModeEvent =~ m/doorbell/) {
		### Construct name of reading for the current actions
		$ReadingNameRelay = $OpsModeReadingPrefix . "DoorbellRelay";
		$ReadingNameAudio = $OpsModeReadingPrefix . "DoorbellAudio";
	}
	### If the event has been triggered by a motion event
	elsif ($OpsModeEvent =~ m/motion/) {
		### Construct name of reading for the current actions
		$ReadingNameRelay = $OpsModeReadingPrefix . "MotionRelay";
		$ReadingNameAudio = $OpsModeReadingPrefix . "MotionAudio";
	}
	### If the event has been triggered by a keypad event
	elsif ($OpsModeEvent =~ m/keypad/) {
		### Construct name of reading for the current actions
		$ReadingNameRelay = $OpsModeReadingPrefix . "KeypadRelay";
		$ReadingNameAudio = $OpsModeReadingPrefix . "KeypadAudio";	
	}
	### If none of the nown events has been triggering this subroutine
	else {
		### Log Entry for debugging purposes		
		Log3 $name, 3, $name. " : DoorBird_OpsModeExecute - Unknown OpsModeEvent has been triggered. Ignoring.";
	
		### Do nothing
	}

	### Get Values of Readings
	my $ReadingValueRelay = ReadingsVal($name, "$ReadingNameRelay","");
	my $ReadingValueAudio = ReadingsVal($name, "$ReadingNameAudio","");

	### Create full path to audio file
	my $AudioFilePath = $AudioFileDir . $ReadingValueAudio;

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_OpsModeExecute - AudioFilePath           : " . $AudioFilePath;
	Log3 $name, 5, $name. " : DoorBird_OpsModeExecute - ReadingValueAudio       : " . $ReadingValueAudio;

	### Create Sox - command
	my $SoxCmd = $Sox . " " . $AudioFilePath . " -n stat stats";
	
	### Convert file
	my $AudioLength; 
	
	### If the value of the Readings for audiofile is not empty or "Off"
	if ($ReadingValueAudio ne "" && $ReadingValueAudio ne "Off") {

		### Get FileInfo and extract the length of mediafile in seconds
		my @FileInfo = qx($SoxCmd 2>&1);
		$AudioLength = $FileInfo[1];
		$AudioLength =~ s/Length \(seconds\)\://;
		$AudioLength =~ s/\s+//g;

		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_OpsModeExecute - AudioLength             : " . $AudioLength;


		### Transmit Audiofile
		DoorBird_Transmit_Audio($hash, $AudioFilePath);
		
		### Log Entry for debugging purposes
		Log3 $name, 4, $name. " : DoorBird_OpsModeExecute - Audiofile transmitted   : ". $AudioFilePath;
		
	}
	### If the value of the Readings for relay ID is not empty of "Off"
	if ($ReadingValueRelay ne "" && $ReadingValueRelay ne "Off") {

		### Execute Relay (=Open Door)
		$hash->{helper}{OpenRelay} = $ReadingValueRelay;
		InternalTimer(gettimeofday()+ $AudioLength, "DoorBird_Open_Door", $hash, 0);
		
		### Log Entry for debugging purposes
		Log3 $name, 4, $name. " : DoorBird_OpsModeExecute - Relay triggered         : ". $ReadingValueRelay;
	}
}
####END####### Execution of automatic events depending on operation mode #######################################END#####

###START###### After return of UDP message ####################################################################START####
sub DoorBird_Read($) {
	my ($hash)            = @_;
	
	### Obtain values from hash
	my $name              = $hash->{NAME};
	my $UdpMessageIdLast  = $hash->{helper}{UdpMessageId};
	my $UdpMotionIdLast   = $hash->{helper}{UdpMotionId};
	my $UdpDoorbellIdLast = $hash->{helper}{UdpDoorbellId};
	my $UdpKeypadIdLast   = $hash->{helper}{UdpKeypadId};
	my $Username 		  = DoorBird_credential_decrypt($hash->{helper}{".USER"});
	my $Password		  = DoorBird_credential_decrypt($hash->{helper}{".PASSWORD"});
	my $PollingTimeout    = $hash->{helper}{PollingTimeout};
	my $url 			  = $hash->{helper}{URL};
	my $Method			  = "GET";
	my $Header			  = "Accept: application/json";
	my $UrlPostfix;
	my $CommandURL;
	my $ReadingEvent;
	my $ReadingEventContent;
	my $err;
	my $data;
	my $buf;
	my $flags;
	
	### Get sending Peerhost
	my $PeerHost = $hash->{CD}->peerhost;
	
	### Get and unpack UDP Datagramm 
	$hash->{CD}->recv($buf, 1024, $flags);
	
	### Unpack Hex-Package
	$data = unpack("H*", $buf);
	
	### Remove Newlines for better log entries
	$buf =~ s/\n+\z//;
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Read _____________________________________________________________________";
	Log3 $name, 5, $name. " : DoorBird_Read - UDP Client said PeerHost          : " . $PeerHost	if defined($PeerHost);
	Log3 $name, 5, $name. " : DoorBird_Read - UDP Client said buf               : " . $buf =~ s/\r//g if defined($buf);
	Log3 $name, 5, $name. " : DoorBird_Read - UDP Client said flags             : " . $flags	if defined($flags);
	Log3 $name, 5, $name. " : DoorBird_Read - UDP Client said data              : " . $data		if defined($data);

	### If the UDP datagramm comes from the defined DoorBird
	if ((defined($PeerHost)) && ($PeerHost eq $url)) {
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_Read - UDP transmitted by valid PeerHost : Yes";

		### Extract message ID
		my $UdpMessageIdCurrent = $buf;
		   $UdpMessageIdCurrent =~ s/:.*//; 

		### If the first part is only numbers and therefore is the message Id of the KeepAlive datagramm
		if ($UdpMessageIdCurrent =~ /^\d+$/) {

			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Read - UdpMessage is                     : Still Alive Message";
			Log3 $name, 5, $name. " : DoorBird_Read - UdpMessageIdLast                  : " . $UdpMessageIdLast;
			Log3 $name, 5, $name. " : DoorBird_Read - UdpMessageIdCurrent               : " . $UdpMessageIdCurrent;

			### If the MessageID is integer type has not yet appeared yet
			if ((int($UdpMessageIdCurrent) == $UdpMessageIdCurrent) && ($UdpMessageIdLast != $UdpMessageIdCurrent)) {
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_Read - UDP datagram transmitted is new   : YES - Working on it.";

				### Remove timer for LostConn
				RemoveInternalTimer($hash, "DoorBird_LostConn");

				### If Reading for state is not already "connected"
				if (ReadingsVal($name, "state", "") ne "connected") {
					### Update STATE of device
					readingsSingleUpdate($hash, "state", "connected", 1);

					### Update Reading
					readingsSingleUpdate($hash, "ContactLostSince", "", 1);
				}

				### Initiate the timer for lost connection handling
				InternalTimer(gettimeofday()+ $hash->{helper}{KeepAliveTimeout}, "DoorBird_LostConn", $hash, 0);

				### Store Current UdpMessageId in hash
				$hash->{helper}{UdpMessageId} = $UdpMessageIdCurrent;
			}
			### If the UDP datagram is already known
			else {
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_Read - UDP datagram transmitted is new   : NO - Ignoring it.";
			}
		}
		### If the UDP message is an event message by comparing the first 6 hex-values ignore case sensitivity
		elsif ($data =~ /^deadbe/i) {

			### Pre-Define variable
			my $msg;
			
			### Decrypt username and password
			my $username = DoorBird_credential_decrypt($hash->{helper}{".USER"});
			my $password = DoorBird_credential_decrypt($hash->{helper}{".PASSWORD"});


			### Split up in accordance to DoorBird API description in hex values
			my $IDENT 	= substr($data, 0, 6);
			my $VERSION = substr($data, 6, 2);
		
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Read - UdpMessage is                     : Event Message";
			Log3 $name, 5, $name. " : DoorBird_Read - version of encryption used        : " . $VERSION;

			### If the version 1 of encryption in accordance to the DoorBird API is used
			if (hex($VERSION) == 1){
				### Split up in hex values in accordance to DoorBird API description for encryption version 1 
				my $OPSLIMIT 	= substr($data,     8,  8);
				my $MEMLIMIT 	= substr($data,    16,  8);
				my $SALT		= substr($data,    24, 32);
				my $NONCE		= substr($data,    56, 16);
				my $CIPHERTEXT	= substr($data,    72, 68);
				my $FiveCharPw  = substr($password, 0,  5);
			
				### Generate user friendly hex-string for data
				my $HexFriendlyData;
				for (my $i=0; $i < (length($data)/2); $i++) {
					$HexFriendlyData .= "0x" . substr($data, $i*2,  2) . " ";
				}
				
				### Generate user friendly hex-string for Ident
				my $HexFriendlyIdent;
				for (my $i=0; $i < (length($IDENT)/2); $i++) {
					$HexFriendlyIdent .= "0x" . substr($IDENT, $i*2,  2) . " ";
				}
				
				### Generate user friendly hex-string for Version
				my $HexFriendlyVersion;
				for (my $i=0; $i < (length($VERSION)/2); $i++) {
					$HexFriendlyVersion .= "0x" . substr($VERSION, $i*2,  2) . " ";
				}
				
				### Generate user friendly hex-string for OpsLimit
				my $HexFriendlyOpsLimit;
				for (my $i=0; $i < (length($OPSLIMIT)/2); $i++) {
					$HexFriendlyOpsLimit .= "0x" . substr($OPSLIMIT, $i*2,  2) . " ";
				}
				
				### Generate user friendly hex-string for MemLimit
				my $HexFriendlyMemLimit;
				for (my $i=0; $i < (length($MEMLIMIT)/2); $i++) {
					$HexFriendlyMemLimit .= "0x" . substr($MEMLIMIT, $i*2,  2) . " ";
				}
				
				### Generate user friendly hex-string for Salt
				my $HexFriendlySalt;
				for (my $i=0; $i < (length($SALT)/2); $i++) {
					$HexFriendlySalt .= "0x" . substr($SALT, $i*2,  2) . " ";
				}
				
				### Generate user friendly hex-string for Nonce
				my $HexFriendlyNonce;
				for (my $i=0; $i < (length($NONCE)/2); $i++) {
					$HexFriendlyNonce .= "0x" . substr($NONCE, $i*2,  2) . " ";
				}
				
				### Generate user friendly hex-string for CipherText
				my $HexFriendlyCipherText;
				for (my $i=0; $i < (length($CIPHERTEXT)/2); $i++) {
					$HexFriendlyCipherText .= "0x" . substr($CIPHERTEXT, $i*2,  2) . " ";
				}	
				
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_Read ------------------------------ Encryption Version 1 in accordance to DoorBird API has been used ------------------------";
				#Log3 $name, 5, $name. " : DoorBird_Read - UDP Client Udp hex                : " . $HexFriendlyData;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Client Ident hex              : " . $HexFriendlyIdent;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Client Version hex            : " . $HexFriendlyVersion;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Client OpsLimit hex           : " . $HexFriendlyOpsLimit;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Client MemLimit hex           : " . $HexFriendlyMemLimit;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Client Salt hex               : " . $HexFriendlySalt;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Client Nonce hex              : " . $HexFriendlyNonce;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Client Cipher hex             : " . $HexFriendlyCipherText;

				### Convert in accordance to API 0.24 description 
				$IDENT 		= hex($IDENT);
				$VERSION 	= hex($VERSION);
				$OPSLIMIT 	= hex($OPSLIMIT);
				$MEMLIMIT 	= hex($MEMLIMIT);
				$SALT		= pack("H*", $SALT);
				$CIPHERTEXT	= pack("H*", $CIPHERTEXT);

				### Log Entry for debugging purposes			
				Log3 $name, 5, $name. " : DoorBird_Read -- Part 2 ------------------------------------------------------------------------------------------------------------------------";
				Log3 $name, 5, $name. " : DoorBird_Read - UDP IDENT       decimal           : " . $IDENT;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP VERSION     decimal           : " . $VERSION;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP OPSLIMIT    decimal           : " . $OPSLIMIT;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP MEMLIMIT    decimal           : " . $MEMLIMIT;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP FiveCharPw  in character      : " . $FiveCharPw;

				### Create Password Hash or return error message if failed
				my $PASSWORDHASH;
				eval {
					$PASSWORDHASH = argon2i_raw($FiveCharPw, $SALT, $OPSLIMIT, $MEMLIMIT, 1, 32);
					1;
				};
				if ( $@ ) {
					Log3 $name, 3, $name . " " . $@;
					return($@);
				} 
				
				### Unpack Password Hash
				my $StrechedPWHex = unpack("H*",$PASSWORDHASH);

				### Generate user friendly hex-string
				my $StrechedPWHexFriendly;
				for (my $i=0; $i < (length($StrechedPWHex)/2); $i++) {
					$StrechedPWHexFriendly .= "0x" . substr($StrechedPWHex, $i*2,  2) . " ";
				}

				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_Read -- Part 3 ------------------------------------------------------------------------------------------------------------------------";
				Log3 $name, 5, $name. " : DoorBird_Read - UDP StrechedPW hex friendly       : " . $StrechedPWHexFriendly;

				### Extend the key to the required length by the crypto_aead_chacha20poly1305 function
				my $pack_algo_key = 'H' . crypto_aead_chacha20poly1305_KEYBYTES * 2;
				my $KEY   = pack($pack_algo_key, $StrechedPWHex);

				### Extend the nonce to the required length by the crypto_aead_chacha20poly1305 function
				my $pack_algo_nonce = 'H' . crypto_aead_chacha20poly1305_NPUBBYTES * 2;
				$NONCE = pack($pack_algo_nonce, $NONCE);

				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_Read -- Part 3 ------------------------------------------------------------------------------------------------------------------------";
				Log3 $name, 5, $name. " : DoorBird_Read - pack_algo_key                     : " . $pack_algo_key;
				Log3 $name, 5, $name. " : DoorBird_Read - pack_algo_nonce                   : " . $pack_algo_nonce;

				### Decrypt message or create error message
				eval {
					$msg = crypto_aead_chacha20poly1305_decrypt($CIPHERTEXT, undef, $NONCE, $KEY);
					1;
				};
				if ( $@ ) {
				Log3 $name, 5, $name. " : Encryption version 01 - Decryption status         : Message forged!";
				return("Encryption version 01 : Messaged forged!");
				} 

				### Log Entry for debugging purposes				
				Log3 $name, 5, $name. " : Encryption version 01 - Decryption status         : Message successfully decypted!";
				Log3 $name, 5, $name. " : DoorBird_Read - msg                               : " . $msg;
			}
			### If the version 2 of encryption in accordance to the DoorBird API is used
			elsif (hex($VERSION) == 2){
				### Split up in hex values in accordance to DoorBird API as from v0.35 description for encryption version 1 
				my $NONCE		 = substr($data,  8, 16);
				my $CIPHERTEXT	 = substr($data, 24, 68);	
			
				### Generate user friendly hex-string for data
				my $HexFriendlyData;
				for (my $i=0; $i < (length($data)/2); $i++) {
					$HexFriendlyData .= "0x" . substr($data, $i*2,  2) . " ";
				}
				
				### Generate user friendly hex-string for Ident
				my $HexFriendlyIdent;
				for (my $i=0; $i < (length($IDENT)/2); $i++) {
					$HexFriendlyIdent .= "0x" . substr($IDENT, $i*2,  2) . " ";
				}
				
				### Generate user friendly hex-string for Version
				my $HexFriendlyVersion;
				for (my $i=0; $i < (length($VERSION)/2); $i++) {
					$HexFriendlyVersion .= "0x" . substr($VERSION, $i*2,  2) . " ";
				}
				
				### Generate user friendly hex-string for Nonce
				my $HexFriendlyNonce;
				for (my $i=0; $i < (length($NONCE)/2); $i++) {
					$HexFriendlyNonce .= "0x" . substr($NONCE, $i*2,  2) . " ";
				}
				
				### Generate user friendly hex-string for CipherText
				my $HexFriendlyCipherText;
				for (my $i=0; $i < (length($CIPHERTEXT)/2); $i++) {
					$HexFriendlyCipherText .= "0x" . substr($CIPHERTEXT, $i*2,  2) . " ";
				}	
				
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_Read ------------------------------ Encryption Version 2 in accordance to DoorBird API has been used ------------------------";
				#Log3 $name, 5, $name. " : DoorBird_Read - UDP Client Udp hex                : " . $HexFriendlyData;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Client Ident hex              : " . $HexFriendlyIdent;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Client Version hex            : " . $HexFriendlyVersion;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Client Nonce hex              : " . $HexFriendlyNonce;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Client Cipher hex             : " . $HexFriendlyCipherText;

				### Convert in accordance to API 0.35 description 
				my $KEY     = $hash->{helper}{NOTIFICATION_ENCRYPTION_KEY};
				$IDENT 		= hex($IDENT);
				$VERSION 	= hex($VERSION);
			    $CIPHERTEXT = pack("H*", $CIPHERTEXT);

				### Log Entry for debugging purposes			
				Log3 $name, 5, $name. " : DoorBird_Read -- Part 2 ------------------------------------------------------------------------------------------------------------------------";
				Log3 $name, 5, $name. " : DoorBird_Read - UDP IDENT       decimal           : " . $IDENT;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP VERSION     decimal           : " . $VERSION;

				### Extend the key to the required length by the crypto_aead_chacha20poly1305 function
				my $pack_algo_key = 'H' . crypto_aead_chacha20poly1305_KEYBYTES * 2;
				$KEY   = pack($pack_algo_key, unpack("H*", $KEY));

				### Extend the nonce to the required length by the crypto_aead_chacha20poly1305 function
				my $pack_algo_nonce = 'H' . crypto_aead_chacha20poly1305_NPUBBYTES * 2;
				$NONCE = pack($pack_algo_nonce, $NONCE);

				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_Read -- Part 3 ------------------------------------------------------------------------------------------------------------------------";
				Log3 $name, 5, $name. " : DoorBird_Read - pack_algo_key                     : " . $pack_algo_key;
				Log3 $name, 5, $name. " : DoorBird_Read - pack_algo_nonce                   : " . $pack_algo_nonce;

				### Decrypt message or create error message

				eval {
					$msg = crypto_aead_chacha20poly1305_decrypt($CIPHERTEXT, undef, $NONCE, $KEY);
					1;
				};
				if ( $@ ) {
					Log3 $name, 5, $name. " : Encryption version 02 - Decryption status         : Message forged!";
					return("Encryption version 02 : Message forged!");
				} 
				
				### Log Entry for debugging purposes				
				Log3 $name, 5, $name. " : Encryption version 02 - Decryption status         : Message successfully decypted!";
				Log3 $name, 5, $name. " : DoorBird_Read - msg                               : " . $msg;
				
			}
			### If the an unknown version of encryption in accordance to the DoorBird API is used
			else {
				### Log Entry for debugging purposes
				Log3 $name, 2, $name. " : DoorBird_Read - UDP datagram version " . $VERSION . " not implemented. Consult module author to implement API updates!";
				
				### Break further evaluation
				return;
			}

			### Unpack message as hex
			#my $DecryptedMsgHex =  $msg->to_hex();
			my $DecryptedMsgHex =  unpack("H*", $msg);
			
			### Generate user friendly hex-string
			my $StrechedMsgHexFriendly;
			for (my $i=0; $i < (length($DecryptedMsgHex)/2); $i++) {
				$StrechedMsgHexFriendly .= "0x" . substr($DecryptedMsgHex, $i*2,  2) . " ";
			}
			
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Read -- Part 4 ------------------------------------------------------------------------------------------------------------------------";
			Log3 $name, 5, $name. " : DoorBird_Read - UDP Msg        hex friendly       : " . $StrechedMsgHexFriendly;

			### Split up in accordance to API 0.24 description in hex values
			my $INTERCOM_ID = substr($DecryptedMsgHex,  0, 12);
			my $EVENT 		= substr($DecryptedMsgHex, 12, 16);
			my $TIMESTAMP 	= substr($DecryptedMsgHex, 28,  8);

			### Generate user friendly hex-string for Intercom_Id
			my $Intercom_IdHexFriendly;
			for (my $i=0; $i < (length($INTERCOM_ID)/2); $i++) {
				$Intercom_IdHexFriendly .= "0x" . substr($INTERCOM_ID, $i*2,  2) . " ";
			}
			### Generate user friendly hex-string for Event
			my $EventHexFriendly;
			for (my $i=0; $i < (length($EVENT)/2); $i++) {
				$EventHexFriendly .= "0x" . substr($EVENT, $i*2,  2) . " ";
			}
			### Generate user friendly hex-string for Timestamp
			my $TimestampHexFriendly;
			for (my $i=0; $i < (length($TIMESTAMP)/2); $i++) {
				$TimestampHexFriendly .= "0x" . substr($TIMESTAMP, $i*2,  2) . " ";
			}

			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Read -- Part 5 ------------------------------------------------------------------------------------------------------------------------";
			Log3 $name, 5, $name. " : DoorBird_Read - UDP Intercom_Id hex friendly      : " . $Intercom_IdHexFriendly;
			Log3 $name, 5, $name. " : DoorBird_Read - UDP Event hex friendly            : " . $EventHexFriendly;
			Log3 $name, 5, $name. " : DoorBird_Read - UDP Timestamp hex friendly        : " . $TimestampHexFriendly;

			### Convert in accordance to API 0.24 description in hex values
			$INTERCOM_ID    = pack("H*", $INTERCOM_ID);
			$EVENT          = pack("H*", $EVENT);
			$TIMESTAMP      = hex($TIMESTAMP);

			### Convert in accordance to API 0.24 description in hex values
			my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($TIMESTAMP);
			my $TIMESTAMPHR    = sprintf ( "%04d-%02d-%02d %02d:%02d:%02d",$year+1900, $mon+1, $mday, $hour, $min, $sec);

			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Read -- Part 6 ------------------------------------------------------------------------------------------------------------------------";
			Log3 $name, 5, $name. " : DoorBird_Read - UDP Intercom_Id character         : " . $INTERCOM_ID;
			Log3 $name, 5, $name. " : DoorBird_Read - UDP EVENT character               : " . $EVENT;
			Log3 $name, 5, $name. " : DoorBird_Read - UDP TIMESTAMP UNIX                : " . $TIMESTAMP;
			Log3 $name, 5, $name. " : DoorBird_Read - UDP TIMESTAMP human readeable     : " . $TIMESTAMPHR;

			### Remove trailing whitespace
			$EVENT =~ s/\s+$//;

			### If event belongs to the current user
			if ($username =~ m/$INTERCOM_ID/){
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_Read -- Part 7 ------------------------------------------------------------------------------------------------------------------------";
				Log3 $name, 5, $name. " : DoorBird_Read - INTERCOM_ID matches username      : YES";
			
				### Create first part command URL for DoorBird
				my $UrlPrefix 		= "https://" . $url . "/bha-api/";

				### Update STATE of device
				readingsSingleUpdate($hash, "state", "Downloading image", 1);

			
				### If event has been triggered by motion sensor
				if ($EVENT =~ m/motion/) {
					### If the MessageID is integer type has not yet appeared yet
					if ((int($TIMESTAMP) == $TIMESTAMP) && ($UdpMotionIdLast != $TIMESTAMP)) {
						### Save Timestamp as new ID
						$hash->{helper}{UdpMotionId} = $TIMESTAMP;
						
						### Create name of reading for event
						$ReadingEvent 			= "motion_sensor";
						$ReadingEventContent 	= "Motion detected!";
						
						### Create Parameter for CommandURL for motionsensor events
						$UrlPostfix = "history.cgi?event=motionsensor&index=1";

						### Create complete command URL for DoorBird
						$CommandURL = $UrlPrefix . $UrlPostfix;	
						
						### Define Parameter for Non-BlockingGet
						my $param = {
							url                => $CommandURL,
							timeout            => $PollingTimeout,
							user               => $Username,
							pwd                => $Password,
							hash               => $hash,
							method             => $Method,
							header             => $Header,
							timestamp          => $TIMESTAMP,
							event              => "motionsensor",
							incrementalTimeout => 1,
							callback           => \&DoorBird_LastEvent_Image
						};

						### Initiate Bulk Update
						readingsBeginUpdate($hash);
						
						### Update readings of device
						readingsBulkUpdate($hash, "state", $ReadingEventContent, 1);
						readingsBulkUpdate($hash, $ReadingEvent, "triggered", 1);

						### Execute Readings Bulk Update
						readingsEndUpdate($hash, 1);

						### Initiate communication
						HttpUtils_NonblockingGet($param);

						### Wrap up a container and initiate the timer to reset reading "doorbell_button"
						my %Container;
						$Container{"HashReference"} = $hash;
						$Container{"Reading"} 		= $ReadingEvent;
						InternalTimer(gettimeofday()+ $hash->{helper}{EventReset}, "DoorBird_EventReset", \%Container, 0);
						
						### Execute event trigger for Operation Mode
						DoorBird_OpsModeExecute($hash, "motion");
			
						### Log Entry
						Log3 $name, 3, $name. " : An event has been triggered by the DoorBird unit  : " . $EVENT;
						Log3 $name, 5, $name. " : DoorBird_Read - Timer for reset reading in        : " . $hash->{helper}{EventReset};
					}
					### If the MessageID is integer type has appeared before
					else {
						### Do nothing
						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_Read - Motion sensor message already been sent. Ignoring it!";						
					}
				}
				### If event has been triggered by keypad
				elsif ($EVENT =~ m/keypad/) {
					### If the MessageID is integer type has not yet appeared yet
					if ((int($TIMESTAMP) == $TIMESTAMP) && ($UdpKeypadIdLast != $TIMESTAMP)) {
						### Save Timestamp as new ID
						$hash->{helper}{UdpKeypadId} = $TIMESTAMP;

						### Create name of reading for event
						$ReadingEvent 			= "keypad_pin";
						$ReadingEventContent 	= "Access via Keypad!";

						### Create Parameter for CommandURL for keypad events
						$UrlPostfix = "history.cgi?event=keypad&index=1";

						### Create complete command URL for DoorBird
						$CommandURL = $UrlPrefix . $UrlPostfix;	
						
						### Define Parameter for Non-BlockingGet
						my $param = {
							url                => $CommandURL,
							timeout            => $PollingTimeout,
							user               => $Username,
							pwd                => $Password,
							hash               => $hash,
							method             => $Method,
							header             => $Header,
							timestamp          => $TIMESTAMP,
							event              => "keypad",
							incrementalTimeout => 1,
							callback           => \&DoorBird_LastEvent_Image
						};
				
						### Initiate Bulk Update
						readingsBeginUpdate($hash);
						
						### Update readings of device
						readingsBulkUpdate($hash, "state", $ReadingEventContent, 1);
						readingsBulkUpdate($hash, $ReadingEvent, "triggered", 1);

						### Execute Readings Bulk Update
						readingsEndUpdate($hash, 1);

						### Initiate communication and close
						HttpUtils_NonblockingGet($param);

						### Wrap up a container and initiate the timer to reset reading "doorbell_button"
						my %Container;
						$Container{"HashReference"} = $hash;
						$Container{"Reading"} 		= $ReadingEvent;
						InternalTimer(gettimeofday()+ $hash->{helper}{EventReset}, "DoorBird_EventReset", \%Container, 0);
						
						### Execute event trigger for Operation Mode
						DoorBird_OpsModeExecute($hash, "keypad");

						### Log Entry
						Log3 $name, 3, $name. " : An event has been triggered by the DoorBird unit  : " . $EVENT;
						Log3 $name, 5, $name. " : DoorBird_Read - Timer for reset reading in        : " . $hash->{helper}{EventReset};
					}
					### If the MessageID is integer type has appeared before
					else {
						### Do nothing
						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_Read - Keypad message already been sent. Ignoring it!";						
					}
				}
				### If event has been triggered by doorbell -> Only a number has been transfered
				elsif (int($EVENT) == $EVENT) {
					### If the MessageID is integer type has not yet appeared yet
					if ((int($TIMESTAMP) == $TIMESTAMP) && ($UdpDoorbellIdLast != $TIMESTAMP)) {

						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_Read - Doorbell message already sent     : NO - Working on it!";

						### Save Timestamp as new ID
						$hash->{helper}{UdpDoorbellId} = $TIMESTAMP;

						### Create name of reading for event
						$ReadingEvent 			= "doorbell_button_"   . sprintf("%03d", $EVENT);
						$ReadingEventContent 	= "doorbell pressed!";
						
						### Create Parameter for CommandURL for doorbell events
						$UrlPostfix = "history.cgi?event=doorbell&index=1";

						### Create complete command URL for DoorBird
						$CommandURL = $UrlPrefix . $UrlPostfix;	
						
						### Define Parameter for Non-BlockingGet
						my $param = {
							url                => $CommandURL,
							timeout            => $PollingTimeout,
							user               => $Username,
							pwd                => $Password,
							hash               => $hash,
							method             => $Method,
							header             => $Header,
							timestamp          => $TIMESTAMP,
							event              => "doorbell",
							doorbellNo         => $EVENT,
							incrementalTimeout => 1,
							callback           => \&DoorBird_LastEvent_Image
						};
				
						### Initiate Bulk Update
						readingsBeginUpdate($hash);
						
						### Update readings of device
						readingsBulkUpdate($hash, "state", $ReadingEventContent, 1);
						readingsBulkUpdate($hash, $ReadingEvent, "triggered", 1);

						### Execute Readings Bulk Update
						readingsEndUpdate($hash, 1);

						### Initiate communication and close
						HttpUtils_NonblockingGet($param);

						### Wrap up a container and initiate the timer to reset reading "doorbell_button"
						my %Container;
						$Container{"HashReference"} = $hash;
						$Container{"Reading"} 		= $ReadingEvent;
						InternalTimer(gettimeofday()+ $hash->{helper}{EventReset}, "DoorBird_EventReset", \%Container, 0);

						### Execute event trigger for Operation Mode
						DoorBird_OpsModeExecute($hash, "doorbell");
						
						### Log Entry
						Log3 $name, 3, $name. " : An event has been triggered by the DoorBird unit  : " . $EVENT;
						Log3 $name, 5, $name. " : DoorBird_Read - Timer for reset reading in        : " . $hash->{helper}{EventReset};
					}
					### If the MessageID is integer type has appeared before
					else {
						### Do nothing
						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_Read - Doorbell message already sent     : YES - Ignoring it!";
					}
				}
				### If the event has been triggered by unknown code
				else {
					### Log Entry
					Log3 $name, 3, $name. " : Unknown event triggered by Doorbird Unit : " . $EVENT;
				}
			}
			### Event does not belong to the current user
			else {
				### Do nothing
				
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_Read -- Part 7 ------------------------------------------------------------------------------------------------------------------------";
				Log3 $name, 5, $name. " : DoorBird_Read - INTERCOM_ID does not matches username. Ignoring datagram packet!";
			}
			
			
			
		}
	}
	else {
		### Do nothing

		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_Read - UDP datagram transmitted by invalid PeerHost.";
	}
}
####END####### After return of UDP message #####################################################################END#####

###START###### Open UDP socket connection #####################################################################START####
sub DoorBird_OpenSocketConn($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $conn;
	my $port = $hash->{helper}{UdpPort};
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_OpenSocketConn - port                    : " . $port;

	### Check if connection can be opened	
	$conn = new IO::Socket::INET (
		ReusePort => $hash->{reusePort},
		LocalPort => $port,
		Proto     => 'udp'
	);
	
	### Log Entry for debugging purposes
	my $ShowConn = Dumper($conn);
	$ShowConn =~ s/[\t]//g;
	$ShowConn =~ s/[\r]//g;
	$ShowConn =~ s/[\n]//g;
	Log3 $name, 5, $name. " : DoorBird_OpenSocketConn - SocketConnection        : " . $ShowConn;
	
	
	if (defined($conn)) {
		$hash->{FD}    		= $conn->fileno();
		$hash->{CD}			= $conn;
		$selectlist{$name}	= $hash;
		
		### Log Entry for debugging purposes
		Log3 $name, 4, $name. " : DoorBird_OpenSocketConn - Socket Connection has been established";
	}
	else {
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_OpenSocketConn - Socket Connection has NOT been established";
	}
	return
}
####END####### Open UDP socket connection ######################################################################END#####

###START###### Lost Connection with DorBird unit ##############################################################START####
sub DoorBird_LostConn($) {
	my ($hash) = @_;

	### Obtain values from hash
    my $name = $hash->{NAME};

	### Create Timestamp
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
	my $TimeStamp = sprintf ( "%04d-%02d-%02d %02d:%02d:%02d",$year+1900, $mon+1, $mday, $hour, $min, $sec);
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_LostConn - Connection with DoorBird Unit lost";

	### If Reading for state is not already disconnected
	if (ReadingsVal($name, "state", "") ne "disconnected") {
		### Update STATE of device
		readingsSingleUpdate($hash, "state", "disconnected", 1);
	
		### Update Reading
		readingsSingleUpdate($hash, "ContactLostSince", $TimeStamp, 1);
	}
	return;
}
####END####### Lost Connection with DorBird unit ###############################################################END#####

###START###### Reset event reading ############################################################################START####
sub DoorBird_EventReset($) {
	my ($ContainerRef) = @_;
	
	### Transform hash-Reference into hash
	my %Container = %$ContainerRef;
	
	### Extract hash and reading to be reset
	my $hash        = $Container{"HashReference"};
	my $Reading     = $Container{"Reading"};

	### Obtain values from hash
    my $name = $hash->{NAME};

	### Log Entry for debugging purposes
	Log3 $name, 3, $name. " : DoorBird_EventReset - Reseting reading to idle    : " . $Reading;

	### Update readings of device
	readingsSingleUpdate($hash, "state",  "connected", 1);
	readingsSingleUpdate($hash, $Reading, "idle",      1);
	
	return;
}
####END####### Reset event reading #############################################################################END#####

###START###### Renew Session ID for DorBird unit ##############################################################START####
sub DoorBird_RenewSessionID($) {
	my ($hash) = @_;

	### Obtain values from hash
    my $name 	= $hash->{NAME};
	my $command	= "getsession.cgi"; 
	my $method	= "GET";
	my $header	= "Accept: application/json";
	my $err 	= " ";
	my $data 	= " ";
	my $json;
	
	### Obtain data
	($err, $data) = DoorBird_BlockGet($hash, $command, $method, $header);

	### Remove Newlines for better log entries
	my $ShowData = $data;
	$ShowData =~ s/[\t]//g if($ShowData ne "");
	$ShowData =~ s/[\r]//g if($ShowData ne "");
	$ShowData =~ s/[\n]//g if($ShowData ne "");
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_RenewSessionID  - err                    : " . $err      if(defined($err));
	Log3 $name, 5, $name. " : DoorBird_RenewSessionID  - data                   : " . $ShowData if(defined($ShowData));
	
	### If no error has been handed back
	if ($err eq "") {
		### Check if json can be parsed into hash	
		eval 
		{
			$json = decode_json(encode_utf8($data));
			1;
		}
		or do 
		{
			### Log Entry for debugging purposes
			Log3 $name, 3, $name. " : DoorBird_RenewSessionID - Data cannot parsed JSON   : Info_Request";
			return $name. " : DoorBird_RenewSessionID - Data cannot be parsed by JSON for Info_Request";
		};
	
		### Extract SessionId from hash
		$hash->{helper}{SessionId} = $json-> {BHA}{SESSIONID};
		
		### Extract NOTIFICATION_ENCRYPTION_KEY from hash if available
		if (exists($json-> {BHA}{NOTIFICATION_ENCRYPTION_KEY})) {
			$hash->{helper}{NOTIFICATION_ENCRYPTION_KEY} = $json-> {BHA}{NOTIFICATION_ENCRYPTION_KEY};
		}

		### Remove timer for LostConn
		RemoveInternalTimer($hash, "DoorBird_RenewSessionID");

		### If a time interval for the Session ID has been provided.
		if ($hash->{helper}{SessionIdSec} > 0) {
			### Initiate the timer for renewing SessionId
			InternalTimer(gettimeofday()+ $hash->{helper}{SessionIdSec}, "DoorBird_RenewSessionID", $hash, 0);

			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_RenewSessionID - Session ID refreshed    : " . $hash->{helper}{SessionId};
		}
		### If a time interval of 0 = disabled has been provided.
		else {
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_RenewSessionID - Session ID Security has been disabled - No further renewing of SessionId.";
		}
		
		### If the VideoStream has been activated
		if (ReadingsVal($name, ".VideoURL", "") ne "") {
			### Refresh Video URL
			DoorBird_Live_Video($hash, "on");
			
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_RenewSessionID - VideoUrl refreshed";
		}
		
		### If the AudioStream has been activated
		if (ReadingsVal($name, ".AudioURL", "") ne "") {
			### Refresh Video URL
			DoorBird_Live_Audio($hash, "on");
			
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_RenewSessionID - AudioUrl refreshed";
		}
		return
	}
	### If error has been handed back
	else {
		$err =~ s/^[^ ]*//;
		return "ERROR!\nError Code:" . $err;
	}
	return;
}
####END####### Renew Session ID for DorBird unit ###############################################################END#####

###START###### Display of html code preceding the "Internals"-section #########################################START####
sub DoorBird_FW_detailFn($$$$) {
	my ($FW_wname, $devname, $room, $extPage) = @_;
	my $hash 			= $defs{$devname};
	my $name 			= $hash->{NAME};
	my $ImageData		= $hash->{helper}{Images}{Individual}{Data};
	my $ImageTimeStamp	= $hash->{helper}{Images}{Individual}{Timestamp};
	
	my $VideoURL		= ReadingsVal($name, ".VideoURL", "");
	my $ImageURL		= ReadingsVal($name, ".ImageURL", "");
	my $AudioURL		= ReadingsVal($name, ".AudioURL", "");
	my $htmlCode;
	my $IconFileDir;
	my $VideoHtmlCode;
	my $ImageHtmlCode;
	my $ImageHtmlCodeBig;
	my $AudioHtmlCode;
    my $OpModHtmlCode;
	my @HistoryDoorbell;
	my @HistoryMotion;

	### If Operation Mode(s) have been provided
	if (@{$hash->{helper}{OpsModeList}} > 0) {
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_FW_detailFn - OpsModeList                : \n" . join(" ", Dumper(@{$hash->{helper}{OpsModeList}}));

		# ### Get current working directory
		# my $cwd = getcwd();

		# ### Log Entry for debugging purposes
		# Log3 $name, 5, $name. " : DoorBird_FW_detailFn - working directory          : " . $cwd;

		# ### If the path is given as UNIX file system format
		# if ($cwd =~ /\//) {
			# ### Log Entry for debugging purposes
			# Log3 $name, 5, $name. " : DoorBird_FW_detailFn - file system format         : LINUX";

			# ### Find out whether it is an absolute path or an relative one (leading "/")
			# if ($IconFileDir =~ /^\//) {
				# $IconFileDir = $IconFileDir;
			# }
			# else {
				# $IconFileDir = $cwd . "/" . $IconFileDir;						
			# }
			
			# ### Remove last / of directory if exists
			# $IconFileDir =~ s/\/\z//;
			
			# ### Add last / for definitiv
			# $IconFileDir .= "/";
			
			# ### Add IconName
			# $IconFileDir .= "www/images/default/" . ReadingsVal($name, "OpsMode" . ReadingsVal($name, "OpsMode", "") . "Icon", "");
			
			# ### Remove last .png of path if exists
			# $IconFileDir =~ s/\.png\z//;
			
			# ### Add last .png for definitiv
			# $IconFileDir .= ".png";
		# }
		# ### If the path is given as Windows file system format
		# elsif ($cwd =~ /\\/) {
			# ### Log Entry for debugging purposes
			# Log3 $name, 5, $name. " : DoorBird_FW_detailFn - file system format         : WINDOWS";

			# ### Find out whether it is an absolute path or an relative one (containing ":\")
			# if ($IconFileDir != /^.:\//) {
				# $IconFileDir = $cwd . $IconFileDir;
			# }
			# else {
				# $IconFileDir = $IconFileDir;						
			# }
			
			# ### Remove last \ of directory if exists
			# $IconFileDir =~ s/\\\z//;
			
			# ### Add last \ for definitiv
			# $IconFileDir .= "\\";

			# ### Add IconName
			# $IconFileDir .= "www\\images\\default\\ " . ReadingsVal($name, "OpsMode" . ReadingsVal($name, "OpsMode", "") . "Icon", "");
			
			# ### Remove last .png of path if exists
			# $IconFileDir =~ s/\.svg\z//;
			
			# ### Add last .png for definitiv
			# $IconFileDir .= ".png";
		# }
		# ### If nothing matches above
		# else {
			# ### Set directory to nothing
			# $IconFileDir = "";
		# }

		# ### Log Entry for debugging purposes
		# Log3 $name, 5, $name. " : DoorBird_FW_detailFn - IconFileDir                : " . $IconFileDir;

		# ### Generate html code for Operation Mode
		# $OpModHtmlCode = '<b>Operation Mode : ' . ReadingsVal($name, "OpsMode", "") . "<b>" . '<img src="' . $IconFileDir . '" alt=" Icon is unavailable">';

		### Generate html code for Operation Mode
		$OpModHtmlCode = '<b>Operation Mode : ' . ReadingsVal($name, "OpsMode", "") . "<b>";
		
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_FW_detailFn - OpModHtmlCode              : " . $OpModHtmlCode;
	}
	else {
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_FW_detailFn - OpsModeList is empty";
		
		### Leave html code for Operation Mode empty
		$OpModHtmlCode = "";
	}

	### Only if DoorBird has a Camera installed view the Image and History Part
	if ($hash->{helper}{CameraInstalled} == true) {
		
		### Log Entry for debugging purposes
		if (defined $hash->{helper}{Images}{History}{doorbell}) {
			@HistoryDoorbell = @{$hash->{helper}{Images}{History}{doorbell}};
			Log3 $name, 5, $name. " : DoorBird_FW_detailFn - Size ImageData doorbell    : " . @HistoryDoorbell;
		}
		### Log Entry for debugging purposes
		if (defined $hash->{helper}{Images}{History}{motionsensor}) {
			@HistoryMotion   = @{$hash->{helper}{Images}{History}{motionsensor}};
			Log3 $name, 5, $name. " : DoorBird_FW_detailFn - Size ImageData motion      : " . @HistoryMotion;
		}
		
		### If VideoURL is empty
		if ($VideoURL eq "") {
			### Create Standard Response
			$VideoHtmlCode = "Video Stream deactivated";
		}
		### If VideoURL is NOT empty
		else {

			### Create proper html code including popup
			my $ImageHtmlCodeBig =  "<img src=\\'" . $VideoURL . "\\'>";
			my $PopupfunctionCode = "onclick=\"FW_okDialog(\'" . $ImageHtmlCodeBig . "\') \" ";
			$VideoHtmlCode    =  '<img ' . $PopupfunctionCode . ' width="400" height="300"  src="' . $VideoURL . '">';

			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_FW_detailFn - VideoHtmlCode              : " . $VideoHtmlCode;

		}
		
		### If ImageData is empty
		if ($ImageData eq "") {
			### Create Standard Response
			$ImageHtmlCode = "Image not available";
		}
		### If ImageData is NOT empty
		else {
			### Create proper html code including popup
			my $ImageHtmlCodeBig  =  "<img src=\\'data:image/jpeg;base64," . $ImageData . "\\'><br><center>" . $ImageTimeStamp . "</center>";
			my $PopupfunctionCode = "onclick=\"FW_okDialog(\'" . $ImageHtmlCodeBig . "\') \" ";
			$ImageHtmlCode   	  =  '<img ' . $PopupfunctionCode . ' width="400" height="300" alt="tick" src="data:image/jpeg;base64,' . $ImageData . '">';
		}
		
			### If AudioURL is empty
		if ($AudioURL eq "") {
			### Create Standard Response
			$AudioHtmlCode = "Audio Stream deactivated";
		}
		### If AudioURL is NOT empty
		else {
			### Create proper html code
			$AudioHtmlCode =  '<audio id="audio_with_controls" controls src="' . $AudioURL . '" ">Your Browser cannot play this audio stream.</audio>';
		}
		#type="audio/wav
		
		### Create html Code
		$htmlCode = '
		<table border="1" style="border-collapse:separate;">
			<tbody >
				<tr>
					<td width="400px" align="center"><b>Image from ' . $ImageTimeStamp . '</b></td>
					<td width="400px" align="center"><b>Live Stream</b></td>
				</tr>
				
				<tr>
					<td id="ImageCell" width="430px" height="300px" align="center">
						' . $ImageHtmlCode  . '
					</td>
					<td id="ImageCell" width="435px" height="300px" align="center">
						' . $VideoHtmlCode . '<BR>
					</td>
				</tr>
				
				<tr>
					<td align="center">' . $OpModHtmlCode . '</td>
					<td align="center">' . $AudioHtmlCode . '</td>
				</tr>	
			</tbody>
		</table>
		';
		
		### Log Entry for debugging purposes
		#	Log3 $name, 5, $name. " : DoorBird_FW_detailFn - ImageHtmlCode              : " . $ImageHtmlCode;
		#	Log3 $name, 5, $name. " : DoorBird_FW_detailFn - VideoHtmlCode              : " . $VideoHtmlCode;
		#	Log3 $name, 5, $name. " : DoorBird_FW_detailFn - AudioHtmlCode              : " . $AudioHtmlCode;
		
		if ((@HistoryDoorbell > 0) || (@HistoryMotion > 0)) {
			$htmlCode .=	
			'
			<BR>
			<BR>
			<table border="1" style="border-collapse:separate;">
				<tbody >
					<tr>
						<td align="center" colspan="5"><b>History of events - Last download: ' . $hash->{helper}{HistoryTime} . '</b></td>
					</tr>
					<tr>
						<td align="center" colspan="2"><b>Doorbell</b></td>
						<td align="center"></td>
						<td align="center" colspan="2"><b>Motion-Sensor</b></td>
					</tr>
					<tr>
						<td width="195px" align="center"><b>Picture</b></td>
						<td width="195px" align="center"><b>Timestamp</b></td>
						<td width="20px" align="center">#</td>
						<td width="195px" align="center"><b>Picture</b></td>
						<td width="195px" align="center"><b>Timestamp</b></td>
					</tr>		
			';

			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_FW_detailFn - hash->{helper}{MaxHistory} : " . $hash->{helper}{MaxHistory};
			
			### For all entries in Picture-Array do
			for (my $i=0; $i <= ($hash->{helper}{MaxHistory} - 1); $i++) {
				
				my $ImageHtmlCodeDoorbell;
				my $ImageHtmlCodeMotion;
				
				### Create proper html code for image triggered by doorbell
				if ($HistoryDoorbell[$i]{data} ne "") {
					### If element contains an error message
					if ($HistoryDoorbell[$i]{data} =~ m/Error/) {
						$ImageHtmlCodeDoorbell     = $HistoryDoorbell[$i]{data};
					}
					### If element does not contain an error message
					else {
						### Create proper html code including popup
						my $ImageHtmlCodeBig =  "<img src=\\'data:image/jpeg;base64," . $HistoryDoorbell[$i]{data} . "\\'><br><center>" . $HistoryDoorbell[$i]{timestamp} . "</center>";
						my $PopupfunctionCode = "onclick=\"FW_okDialog(\'" . $ImageHtmlCodeBig . "\') \" ";
						$ImageHtmlCodeDoorbell    =  '<img ' . $PopupfunctionCode . ' width="190" height="auto" alt="tick" src="data:image/jpeg;base64,' . $HistoryDoorbell[$i]{data} . '">';
					}
				}
				else {
					$ImageHtmlCodeDoorbell =  'No image available';
				}
				### Create proper html code for image triggered by motionsensor
				if ($HistoryMotion[$i]{data} ne "") {
					### If element contains an error message
					if ($HistoryMotion[$i]{data} =~ m/Error/) {
						$ImageHtmlCodeMotion = $HistoryMotion[$i]{data};
					}
					### If element does not contain an error message
					else {
						### Create proper html code including popup
						my $ImageHtmlCodeBig =  "<img src=\\'data:image/jpeg;base64," . $HistoryMotion[$i]{data} . "\\'><br><center>" . $HistoryMotion[$i]{timestamp} . "</center>";
						my $PopupfunctionCode = "onclick=\"FW_okDialog(\'" . $ImageHtmlCodeBig . "\') \" ";
						$ImageHtmlCodeMotion    =  '<img ' . $PopupfunctionCode . ' width="190" height="auto" alt="tick" src="data:image/jpeg;base64,' . $HistoryMotion[$i]{data} . '">';
					}
				}
				else {
					$ImageHtmlCodeMotion =  'No image available';
				}			
				
				$htmlCode .=
				'
					<tr>
						<td align="center">' . $ImageHtmlCodeDoorbell . '</td>
						<td align="center">' . $HistoryDoorbell[$i]{timestamp} . '</td>
						<td align="center">' . ($i + 1) . '</td>
						<td align="center">' . $ImageHtmlCodeMotion . '</td>
						<td align="center">' . $HistoryMotion[$i]{timestamp} . '</td>
					</tr>
				';
				### Log Entry for debugging purposes
				#	Log3 $name, 5, $name. " : DoorBird_FW_detailFn - ImageHtmlCodeDoorbell      : " . $ImageHtmlCodeDoorbell;
				#	Log3 $name, 5, $name. " : DoorBird_FW_detailFn - ImageHtmlCodeMotion        : " . $ImageHtmlCodeMotion;
			}
			
			### Finish table
			$htmlCode .=
			'
				</tbody>
			</table>	
			';
			
		}	
	}
	### Log Entry for debugging purposes
	#	Log3 $name, 5, $name. " : DoorBird_FW_detailFn - htmlCode                   : " . $htmlCode;

	# my $infoBtn = "</td><td><a onClick='FW_cmd(FW_root+\"?cmd.$name=get $name all&XHR=1\",function(data){FW_okDialog(data)})'\>$info</a>"
	# <a href=\"#!\" onclick=\"FW_okDialog('Testtitle<br><br>TestDescription')\">Testtitle</a>
	
	return($htmlCode );
}
####END####### Display of html code preceding the "Internals"-section ##########################################END#####

###START###### Define Subfunction for INFO REQUEST ############################################################START####
sub DoorBird_Info_Request($$) {
	my ($hash, $option)	= @_;
	my $name			= $hash->{NAME};
	my $command			= "info.cgi"; 
	my $method			= "GET";
	my $header			= "Accept: application/json";
	
	my $err = " ";
	my $data = " ";
	my $json;
	
	### Obtain data
	($err, $data) = DoorBird_BlockGet($hash, $command, $method, $header);

	### Remove Newlines for better log entries
	my $ShowData = $data;
	$ShowData =~ s/[\t]//g if($ShowData ne "");
	$ShowData =~ s/[\r]//g if($ShowData ne "");
	$ShowData =~ s/[\n]//g if($ShowData ne "");

	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Info_Request - err                       : " . $err      if(defined($err));
	Log3 $name, 5, $name. " : DoorBird_Info_Request - data                      : " . $ShowData if(defined($ShowData));
	
	### If no error has been handed back
	if ($err eq "") {
		### If the option is asking for the JSON string
		if (defined($option) && ($option =~ /JSON/i)) {
			return $data;		
		}
		### If the option is asking for nothing special
		else {
			### Check if json can be parsed into hash	
			eval 
			{
				$json = decode_json(encode_utf8($data));
				1;
			}
			or do 
			{
				### Log Entry for debugging purposes
				Log3 $name, 3, $name. " : DoorBird_Info_Request - Data cannot parsed JSON   : Info_Request";
				return $name. " : DoorBird_Info_Request - Data cannot be parsed by JSON for Info_Request";
			};
			
			my $VersionContent = $json-> {BHA}{VERSION}[0];
			
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Info_Request - json                      : " . $json;
			
			### Initiate Bulk Update
			readingsBeginUpdate($hash);

			foreach my $key (keys %{$VersionContent}) {

				### If the entry are information about connected relays
				if ( $key eq "RELAYS") {
				
					### Save adresses of relays into hash
					@{$hash->{helper}{RelayAdresses}} = @{$VersionContent -> {$key}};

					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_Info_Request - No of connected relays    : " . @{$VersionContent -> {$key}};
					Log3 $name, 5, $name. " : DoorBird_Info_Request - Adresses of relays        : " . join(",", @{$VersionContent -> {$key}});
					Log3 $name, 5, $name. " : DoorBird_Info_Request - {helper}{RelayAdresses}   : " . join(",", @{$hash->{helper}{RelayAdresses}});
					
					### Delete all Readings for Relay-Addresses
					readingsDelete($hash, "RelayAddr_.*");
					
					### For all registred relays do
					my $RelayNumber =0;
					foreach my $RelayAddress (@{$VersionContent -> {$key}}) {
					
						$RelayNumber++;

						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_Info_Request - Adress of " . sprintf("%15s %-s", "Relay_" . sprintf("%02d", $RelayNumber), ": " . $RelayAddress);
						
						### Update Reading
						readingsBulkUpdate($hash, "RelayAddr_" . sprintf("%02d", $RelayNumber), $RelayAddress);
					}
				}
				### If the entry has the information about the device type
				elsif ( $key eq "DEVICE-TYPE") {
				
					### If the Device Type is not containing type numbers which have no camera installed - Currently only "DoorBird D301A - Door Intercom IP Upgrade"
					if ($VersionContent -> {$key} !~ m/301/) {
						### Set Information about Camera installed to true
						$hash->{helper}{CameraInstalled} = true;
					}
			
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_Info_Request - Content of" . sprintf("%15s %-s", $key, ": " . $VersionContent -> {$key});

					### Update Reading
					readingsBulkUpdate($hash, $key, $VersionContent -> {$key} );
				}
				### For all other entries
				else {
					
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_Info_Request - Content of" . sprintf("%15s %-s", $key, ": " . $VersionContent -> {$key});

					### Update Reading
					readingsBulkUpdate($hash, $key, $VersionContent -> {$key} );
				}
			}
			### Update SessionId
			DoorBird_RenewSessionID($hash);

			### Execute Readings Bulk Update
			readingsEndUpdate($hash, 1);

			### Download SIP Status Request
			DoorBird_SipStatus_Request($hash,"");

			### Check for Firmware-Updates
			DoorBird_FirmwareStatus($hash);
			
			return "Readings have been updated!\n";
		}
	}
	### If error has been handed back
	else {
		$err =~ s/^[^ ]*//;
		return "ERROR!\nError Code:" . $err;
	}
}
####END####### Define Subfunction for INFO REQUEST #############################################################END#####

###START###### Firmware-Update Status for DorBird unit ########################################################START####
sub DoorBird_FirmwareStatus($) {
	my ($hash) = @_;

	### Obtain values from hash
    my $name = $hash->{NAME};

	### Create Timestamp
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
	my $TimeStamp = sprintf ( "%04d-%02d-%02d %02d:%02d:%02d",$year+1900, $mon+1, $mday, $hour, $min, $sec);
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_FirmwareStatus - Checking firmware status on doorbird page";
	
	my $FirmwareVersionUnit = ReadingsVal($name, "FIRMWARE"   , 0        );
	my $FirmwareDevice      = ReadingsVal($name, "DEVICE-TYPE", "unknown");

	### Download website of changelocks
	my $html = GetFileFromURL("https://www.doorbird.com/changelog");
	
	### Get the latest firmware number for this product
	my $versions = DoorBird_parseChangelog($hash, $html);
	my $result   = DoorBird_findNewestFWVersion($hash, $versions, $FirmwareDevice);

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_FirmwareStatus - result                  : " . $result;
	
	### If the latest Firmware is installed
	if (int($FirmwareVersionUnit) == int($result)) {
		### Update Reading for Firmware-Status
		readingsSingleUpdate($hash, "Firmware-Status", "up-to-date", 1);	
		
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_FirmwareStatus - Latest firmware is installed!";
		
	}
	### If the latest Firmware is NOT installed
	elsif (int($FirmwareVersionUnit) < int($result)) {
		### Update Reading for Firmware-Status
		readingsSingleUpdate($hash, "Firmware-Status", "Firmware update required!", 1);	
		
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_FirmwareStatus - DoorBird requires firmware update!";
	}	
	### Something went wrong
	else {
		### Update Reading for Firmware-Status
		readingsSingleUpdate($hash, "Firmware-Status", "unknown", 1);
		
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_FirmwareStatus - An error occured!";
	}
	
	return;
}
####END####### Firmware-Update Status for DorBird unit #########################################################END#####

###START###### Define Subfunction for LIVE VIDEO REQUEST ######################################################START####
sub DoorBird_Live_Video($$) {
	my ($hash, $option)	= @_;

	### Obtain values from hash
	my $name			= $hash->{NAME};
	my $url 			= $hash->{helper}{URL};

	### Create complete command URL for DoorBird depending on whether SessionIdSecurity has been enabled (>0) or disabled (=0)
	my $UrlPrefix 		= "http://" . $url . "/bha-api/";
	my $UrlPostfix;
	if ($hash->{helper}{SessionIdSec} > 0) {
		$UrlPostfix 	= "?sessionid=" . $hash->{helper}{SessionId};
	}
	else {
		my $username 	= DoorBird_credential_decrypt($hash->{helper}{".USER"});
		my $password	= DoorBird_credential_decrypt($hash->{helper}{".PASSWORD"});
		$UrlPostfix 	= "?http-user=". $username . "&http-password=" . $password;
	}
	my $VideoURL 		= $UrlPrefix . "video.cgi" . $UrlPostfix;

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Live_Video - VideoURL                    : " . $VideoURL ;
	Log3 $name, 5, $name. " : DoorBird_Live_Video - VideoURL                    : Created";

	### If VideoStreaming shall be switched ON
	if ($option eq "on") {
		
		### Update Reading
		readingsSingleUpdate($hash, ".VideoURL", $VideoURL, 1);
		
		### Refresh Browser Window
		FW_directNotify("#FHEMWEB:$FW_wname", "location.reload()", "") if defined($FW_wname);
	}
	### If VideoStreaming shall be switched OFF
	elsif ($option eq "off") {
		### Update Reading
		readingsSingleUpdate($hash, ".VideoURL", "", 1);

		### Refresh Browser Window
		FW_directNotify("#FHEMWEB:$FW_wname", "location.reload()", "") if defined($FW_wname);
		
	}
	### If wrong parameter has been transfered
	else
	{
		### Do nothing - Just return
		return("ERROR!\nWrong Parameter used");
	}
	return
}
####END####### Define Subfunction for LIVE VIDEO REQUEST #######################################################END#####

###START###### Define Subfunction for LIVE AUDIO REQUEST ######################################################START####
sub DoorBird_Live_Audio($$) {
	my ($hash, $option)	= @_;

	### Obtain values from hash
	my $name			= $hash->{NAME};
	my $url 			= $hash->{helper}{URL};
	
	### Create complete command URL for DoorBird depending on whether SessionIdSecurity has been enabled (>0) or disabled (=0)
	my $UrlPrefix 		= "http://" . $url . "/bha-api/audio-receive.cgi";
	my $UrlPostfix;
	if ($hash->{helper}{SessionIdSec} > 0) {
		$UrlPostfix 	= "?sessionid=" . $hash->{helper}{SessionId};
	}
	else {
		my $username 	= DoorBird_credential_decrypt($hash->{helper}{".USER"});
		my $password	= DoorBird_credential_decrypt($hash->{helper}{".PASSWORD"});
		$UrlPostfix 	= "?http-user=". $username . "&http-password=" . $password;
	}
	my $AudioURL 		= $UrlPrefix . $UrlPostfix;

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Live_Audio - AudioURL                    : " . $AudioURL ;

	### If AudioStreaming shall be switched ON
	if ($option eq "on") {
		
		### Update Reading
		readingsSingleUpdate($hash, ".AudioURL", $AudioURL, 1);
		
		### Refresh Browser Window
		FW_directNotify("#FHEMWEB:$FW_wname", "location.reload()", "") if defined($FW_wname);
	}
	### If AudioStreaming shall be switched OFF
	elsif ($option eq "off") {
		### Update Reading
		readingsSingleUpdate($hash, ".AudioURL", "", 1);

		### Refresh Browser Window		
		FW_directNotify("#FHEMWEB:$FW_wname", "location.reload()", "") if defined($FW_wname);
	}
	### If wrong parameter has been transfered
	else
	{
		### Do nothing - Just return
		return("ERROR!\nWrong Parameter used");
	}
	return
}
####END####### Define Subfunction for LIVE AUDIO REQUEST #######################################################END#####


###START###### Define Subfunction for LIVE IMAGE REQUEST ######################################################START####
sub DoorBird_Image_Request($$) {
	my ($hash, $option)	= @_;

	### Obtain values from hash
	my $name				= $hash->{NAME};
	my $username 			= DoorBird_credential_decrypt($hash->{helper}{".USER"});
	my $password			= DoorBird_credential_decrypt($hash->{helper}{".PASSWORD"});
	my $url 				= $hash->{helper}{URL};
	my $command				= "image.cgi";
	my $method				= "GET";
	my $header				= "Accept: application/json";
	my $err					= " ";
	my $data				= " ";
	my $json				= " ";
	my $ImageFileName		= " ";
	
	### Create complete command URL for DoorBird
	my $UrlPrefix 		= "https://" . $url . "/bha-api/";
	my $UrlPostfix 		= "?http-user=". $username . "&http-password=" . $password;
	my $ImageURL 		= $UrlPrefix . $command . $UrlPostfix;

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Image_Request _____________________________________________________________";
#	Log3 $name, 5, $name. " : DoorBird_Image_Request - ImageURL                 : " . $ImageURL ;

	### Update Reading
	readingsSingleUpdate($hash, ".ImageURL", $ImageURL, 1);
		
	### Get Image Data
	($err, $data) = DoorBird_BlockGet($hash, $command, $method, $header);

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Image_Request - err                      : " . $err;
#	Log3 $name, 5, $name. " : DoorBird_Image_Request - data                     : " . $data;

	### Encode jpeg data into base64 data and remove lose newlines
    my $ImageData =  MIME::Base64::encode($data);
       $ImageData =~ s{\n}{}g;
	
	### Create Timestamp
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
	my $ImageTimeStamp		= sprintf ( "%04d-%02d-%02d %02d:%02d:%02d",$year+1900, $mon+1, $mday, $hour, $min, $sec);
	my $ImageFileTimeStamp	= sprintf ( "%04d%02d%02d-%02d%02d%02d"    ,$year+1900, $mon+1, $mday, $hour, $min, $sec);

	### Save picture and timestamp into hash
	$hash->{helper}{Images}{Individual}{Data}		= $ImageData;
	$hash->{helper}{Images}{Individual}{Timestamp} 	= $ImageTimeStamp;

	### Refresh Browser Window
	FW_directNotify("#FHEMWEB:$FW_wname", "location.reload()", "") if defined($FW_wname);

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Image_Request - hash - ImageFileDir      : " . $hash->{helper}{ImageFileDir};

	### If pictures supposed to be saved as files
	if ($hash->{helper}{ImageFileDir} ne "") {

		### Get current working directory
		my $cwd = getcwd();
		my $ImageFileDir;

		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_Image_Request - working directory        : " . $cwd;


		### If the path is given as UNIX file system format
		if ($cwd =~ /\//) {
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Image_Request - file system format       : LINUX";

			### Find out whether it is an absolute path or an relative one (leading "/")
			if ($hash->{helper}{ImageFileDir} =~ /^\//) {
				$ImageFileName = $hash->{helper}{ImageFileDir};
			}
			else {
				$ImageFileName = $cwd . "/" . $hash->{helper}{ImageFileDir};						
			}

			### Check whether the last "/" at the end of the path has been given otherwise add it an create complete path
			if ($hash->{helper}{ImageFileDir} =~ /\/\z/) {
				### Save directory
				$ImageFileDir = $ImageFileName;
				
				### Create full datapath
				$ImageFileName .=       $ImageFileTimeStamp . "_snapshot.jpg";
			}
			else {
				### Save directory
				$ImageFileDir = $ImageFileName . "/";
				
				### Create full datapath
				$ImageFileName .= "/" . $ImageFileTimeStamp . "_snapshot.jpg";
			}
		}
		### If the path is given as Windows file system format
		if ($hash->{helper}{ImageFileDir} =~ /\\/) {
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Image_Request - file system format       : WINDOWS";

			### Find out whether it is an absolute path or an relative one (containing ":\")
			if ($hash->{helper}{ImageFileDir} != /^.:\//) {
				$ImageFileName = $cwd . $hash->{helper}{ImageFileDir};
			}
			else {
				$ImageFileName = $hash->{helper}{ImageFileDir};						
			}
			
			### Save directory
			$ImageFileDir = $ImageFileName;

			### Check whether the last "/" at the end of the path has been given otherwise add it an create complete path
			if ($hash->{helper}{ImageFileDir} =~ /\\\z/) {
				### Save directory
				$ImageFileDir = $ImageFileName;
				
				### Create full datapath
				$ImageFileName .=       $ImageFileTimeStamp . "_snapshot.jpg";
			}
			else {
				### Save directory
				$ImageFileDir = $ImageFileName . "\\";
				
				### Create full datapath
				$ImageFileName .= "\\" . $ImageFileTimeStamp . "_snapshot.jpg";
			}
		}
		
		### Save filename of last snapshot into hash
		$hash->{helper}{Images}{LastSnapshotPath} = $ImageFileName;
		
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_Image_Request - ImageFileName            : " . $ImageFileName;

		### Open file or write error message in log
		open my $fh, ">", $ImageFileName or do {
			### Log Entry 
			Log3 $name, 2, $name. " : DoorBird_Image_Request -  open file error         : " . $! . " - ". $ImageFileName;
		};
		
		### Write the base64 decoded data in file
		print $fh decode_base64($ImageData) if defined($fh);
		
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_Image_Request - write file               : Successfully written " . $ImageFileName;
		
		### Update the history list for images and videos
		DoorBird_History_List($hash);
		
		### Close file or write error message in log
		close $fh or do {
			### Log Entry 
			Log3 $name, 2, $name. " : DoorBird_Image_Request - close file error         : " . $! . " - ". $ImageFileName;
		};
	
		### Free FileDirSpace if exxeeds maximum
		DoorBird_FileSpace($hash, $ImageFileDir, "jpg", $hash->{helper}{ImageFileDirMaxSize});
	}
	
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Image_Request - ImageData size           : " . length($ImageData);
	Log3 $name, 5, $name. " : DoorBird_Image_Request - ImageTimeStamp           : " . $ImageTimeStamp;
	
	return;
}
####END####### Define Subfunction for LIVE IMAGE REQUEST #######################################################END#####

###START###### Define Subfunction for LAST EVENT IMAGE REQUEST ################################################START####
sub DoorBird_LastEvent_Image($$$) {
	my ($param, $err, $data) = @_;
    my $hash = $param->{hash};

	### Obtain values from hash
    my $name         = $hash->{NAME};
	my $event        = $param->{event};
	my $timestamp	 = $param->{timestamp};
	my $VideoEvent;
	my $httpHeader;
	my $ReadingImage;

	if ($event =~ m/doorbell/ ){
		$ReadingImage 			= "doorbell_snapshot_" . sprintf("%03d", $param->{doorbellNo});
		$VideoEvent				= "doorbell_" . sprintf("%03d", $param->{doorbellNo});
	}
	elsif ($event =~ m/motion/ ){
		$ReadingImage 			= "motion_snapshot";
		$VideoEvent				= "motionsensor" 
	}
	elsif ($event =~ m/keypad/ ){
		$ReadingImage 			= "keypad_snapshot";
		$VideoEvent				= "keypad" 
	}
	else {
		### Create Log entry
		Log3 $name, 2, $name. " : DoorBird_LastEvent_Image - Unknown event. Breaking up";
		
		### Exit sub
		return
	}

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_LastEvent_Image ___________________________________________________________";
	Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - err                    : " . $err           if (defined($err  ));
	Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - length data            : " . length($data)  if (defined($data ));
	#Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - param                  : " . join("\n", @{[%{$param}]}) if (defined($param));

	### If error message available
	if ($err ne "") {
		### Create Log entry
		Log3 $name, 3, $name. " : DoorBird_LastEvent_Image - Error                  : " . $err        if (defined($err  ));
		
		### Write Last Image into reading
		readingsSingleUpdate($hash, $ReadingImage, "No image data", 1);
	}
	### if no error message available
	else {
		### If any image data available
		if (defined $data) {

			### Predefine Image Data and Image-hash and hash - reference		
			my $ImageData;
			my $ImageTimeStamp;
			my $ImageFileTimeStamp;
			my $ImageFileName;
			my %ImageDataHash;
			my $ref_ImageDataHash = \%ImageDataHash;
			
			### If http response code is 200 = OK
			if ($param->{code} == 200) {
				### Encode jpeg data into base64 data and remove lose newlines
				$ImageData =  MIME::Base64::encode($data);
				$ImageData =~ s{\n}{}g;

				### Create Timestamp
				$httpHeader = $param->{httpheader};
				$httpHeader =~ s/^[^_]*X-Timestamp: //;
				$httpHeader =~ s/\n.*//g;

				### If timestamp from history image has NOT been done since the timestamp from the event
				if ((int($timestamp) - int($httpHeader)) > 0){
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - timestamp from history image has NOT been done since the timestamp from the event.";
					Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - Image timestamp        : " . $httpHeader;
					Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - Event timestamp        : " . $timestamp;
					Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - dt                     : " . (int($timestamp) - int($httpHeader));


					### If timestamp from the event is NOT older than WaitForHistory from current time => Try again
					if ((time - int($timestamp)) <= $hash->{helper}{WaitForHistory}){

						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - timestamp of event is not older than Attribute WaitForHistory: Still time to try again";
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - Event timestamp        : " . $timestamp;
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - current timestamp      : " . time;
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - Attr WaitForHistory    : " . $hash->{helper}{WaitForHistory};
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - dt                     : " . int(time - int($timestamp));

						### Try again: Initiate communication and close
						HttpUtils_NonblockingGet($param);
							
						### Exit routine
						return;
					}
					else {
						### Log Entry for debugging purposes
						Log3 $name, 2, $name. " : DoorBird_LastEvent_Image - timestamp of event is older than than Attribute WaitForHistory: Proceeding without waiting any longer...";
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - Event timestamp        : " . $timestamp;
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - current timestamp      : " . time;
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - Attr WaitForHistory    : " . $hash->{helper}{WaitForHistory};
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - dt                     : " . int(time - int($timestamp));
						
						### Write Last Image into reading
						readingsSingleUpdate($hash, $ReadingImage, "No image data", 1);
					}
				}
				### If timestamp from history picture has been done since the timestamp from the event			
				else {
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - timestamp from history image has been done since the timestamp from the event.";
					Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - Image timestamp        : " . $httpHeader;
					Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - Event timestamp        : " . $timestamp;
					Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - dt                     : " . (int($timestamp) - int($httpHeader));
					
					my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($httpHeader);
					$ImageTimeStamp	    = sprintf ( "%04d-%02d-%02d %02d:%02d:%02d",$year+1900, $mon+1, $mday, $hour, $min, $sec);
					$ImageFileTimeStamp	= sprintf ( "%04d%02d%02d-%02d%02d%02d"    ,$year+1900, $mon+1, $mday, $hour, $min, $sec);

					### Save picture and timestamp into hash
					$hash->{helper}{Images}{Individual}{Data}		= $ImageData;
					$hash->{helper}{Images}{Individual}{Timestamp} 	= $ImageTimeStamp;
					
					### Refresh Browser Window		
					FW_directNotify("#FHEMWEB:$FW_wname", "location.reload()", "") if defined($FW_wname);

					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - hash - ImageFileDir    : " . $hash->{helper}{ImageFileDir};

					### If pictures supposed to be saved as files
					if ($hash->{helper}{ImageFileDir} ne "0") {

						### Get current working directory
						my $cwd = getcwd();

						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - working directory      : " . $cwd;

						### If the path is given as UNIX file system format
						if ($cwd =~ /\//) {
							### Log Entry for debugging purposes
							Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - file system format     : LINUX";

							### Find out whether it is an absolute path or an relative one (leading "/")
							if ($hash->{helper}{ImageFileDir} =~ /^\//) {
								$ImageFileName = $hash->{helper}{ImageFileDir};
							}
							else {
								$ImageFileName = $cwd . "/" . $hash->{helper}{ImageFileDir};						
							}

							### Check whether the last "/" at the end of the path has been given otherwise add it an create complete path
							if ($hash->{helper}{ImageFileDir} =~ /\/\z/) {
								$ImageFileName .=       $ImageFileTimeStamp . "_" . $event . ".jpg";
							}
							else {
								$ImageFileName .= "/" . $ImageFileTimeStamp . "_" . $event . ".jpg";
							}
						}

						### If the path is given as Windows file system format
						if ($hash->{helper}{ImageFileDir} =~ /\\/) {
							### Log Entry for debugging purposes
							Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - file system format     : WINDOWS";

							### Find out whether it is an absolute path or an relative one (containing ":\")
							if ($hash->{helper}{ImageFileDir} != /^.:\//) {
								$ImageFileName = $cwd . $hash->{helper}{ImageFileDir};
							}
							else {
								$ImageFileName = $hash->{helper}{ImageFileDir};						
							}

							### Check whether the last "/" at the end of the path has been given otherwise add it an create complete path
							if ($hash->{helper}{ImageFileDir} =~ /\\\z/) {
								$ImageFileName .=       $ImageFileTimeStamp . "_" . $event . ".jpg";
							}
							else {
								$ImageFileName .= "\\" . $ImageFileTimeStamp . "_" . $event . ".jpg";
							}
						}
						
						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - ImageFileName          : " . $ImageFileName;

						### Open file or write error message in log
						open my $fh, ">", $ImageFileName or do {
							### Log Entry 
							Log3 $name, 2, $name. " : DoorBird_LastEvent_Image -  open file error       : " . $! . " - ". $ImageFileName;
						};
						
						### Write the base64 decoded data in file
						print $fh decode_base64($ImageData) if defined($fh);
						
						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - write file             : Successfully written " . $ImageFileName;
						
						### Close file or write error message in log
						close $fh or do {
							### Log Entry 
							Log3 $name, 2, $name. " : DoorBird_LastEvent_Image - close file error       : " . $! . " - ". $ImageFileName;
						};
					
						### Write Last Image into reading
						readingsSingleUpdate($hash, $ReadingImage, $ImageFileName, 1);
						
						### Update the history list for images and videos
						DoorBird_History_List($hash);
					}
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - ImageData - event      : " . length($ImageData);

				}
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - Type of event          : " . $event;
			}
			### If http response code is 204 = No permission to download the event history
			elsif ($param->{code} == 204) {
				### Create Log entry
				Log3 $name, 3, $name. " : DoorBird_LastEvent_Image - Error 204              : User not authorized to download event history";
				
				### Create Error message
				$ImageData = "Error 204: The user has no permission to download the event history.";
				$ImageTimeStamp =" ";
				
				### Write Last Image into reading
				readingsSingleUpdate($hash, $ReadingImage, "No image data", 1);
			}
			### If http response code is 404 = No picture available to download the event history
			elsif ($param->{code} == 404) {
				### Create Log entry
				Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - Error 404              : No picture available to download event history. Check settings in DoorBird APP.";
				
				### Create Error message
				$ImageData = "Error 404: No picture available to download in the event history.";
				$ImageTimeStamp =" ";
				
				### Write Last Image into reading
				readingsSingleUpdate($hash, $ReadingImage, "No image data", 1);
			}
			### If http response code is none of one above
			else {
				### Create Log entry
				Log3 $name, 3, $name. " : DoorBird_LastEvent_Image - Unknown http response code    : " . $param->{code};
			
				### Create Error message
				$ImageData = "Error : " . $param->{code};
				$ImageTimeStamp =" ";
				
				### Write Last Image into reading
				readingsSingleUpdate($hash, $ReadingImage, "No image data", 1);
			}
		}
		else {
			### Write Last Image into reading
			readingsSingleUpdate($hash, $ReadingImage, "No image data", 1);
		}
	}
	
	### If the attribute VideoDuration has been set and therefore an video shall be recorded
	if    (($event =~ m/doorbell/ ) && ($hash->{helper}{VideoDurationDoorbell} > 0)){
		### Call sub for Videorecording
		DoorBird_Video_Request($hash, $hash->{helper}{VideoDurationDoorbell}, $VideoEvent, $httpHeader);
	}
	elsif (($event =~ m/motion/ )   && ($hash->{helper}{VideoDurationMotion}   > 0)){
		### Call sub for Videorecording
		DoorBird_Video_Request($hash, $hash->{helper}{VideoDurationMotion}, $VideoEvent, $httpHeader);
	}
	elsif (($event =~ m/keypad/ )   && ($hash->{helper}{VideoDurationKeypad}   > 0)){
		### Call sub for Videorecording
		DoorBird_Video_Request($hash, $hash->{helper}{VideoDurationKeypad}, $VideoEvent, $httpHeader);
	}
	return;
}
####END####### Define Subfunction for LAST EVENT IMAGE REQUEST #################################################END#####

###START###### Define Subfunction for OPEN DOOR ###############################################################START####
sub DoorBird_Open_Door($) {
	my ($hash)	= @_;
	my $name			= $hash->{NAME};
	my $relay			= $hash->{helper}{OpenRelay};
	my $command			= "open-door.cgi?r=" . $relay; 
	my $method			= "GET";
	my $header			= "Accept: application/json";
	my $username 		= DoorBird_credential_decrypt($hash->{helper}{".USER"});
	my $err;
	my $data;
	my $json;
	
	### Delete Helper
	$hash->{helper}{OpenRelay} = "";
	
	### Activate Relay
	($err, $data) = DoorBird_BlockGet($hash, $command, $method, $header);

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Open_Door - err                          : " . $err;
	Log3 $name, 5, $name. " : DoorBird_Open_Door - data                         : " . $data;
	
	### If no error message is available
	if ($err eq "") {

		### Check if json can be parsed into hash
		eval {
			$json = decode_json(encode_utf8($data));
			1;
		}
		or do {
			### Log Entry for debugging purposes
			Log3 $name, 3, $name. " : DoorBird_Open_Door - Data cannot be parsed by JSON for: Open_Door";
			return $name. " : DoorBird_Open_Door - Data cannot be parsed by JSON for Open_Door";
		};
		
		### Create return messages and log entries based on error codes returned
		if ($json->{BHA}{RETURNCODE} eq "1") {
			### Log Entry
			Log3 $name, 3, $name. " : DoorBird_Open_Door - Door ". $relay . " successfully triggered.";
			
			### Create popup message
			return "Door ". $relay . " successful triggered.";
		}
		elsif ($json->{BHA}{RETURNCODE} eq "204") {
			### Log Entry
			Log3 $name, 3, $name. " : DoorBird_Open_Door - Error 204: The user " . $username . "has no “watch-always” - permission to open the door.";
			
			### Create popup message
			return "Error 204: The user " . $username . "has no “watch-always” - permission to open the door.";
		}
		else {
			### Log Entry
			Log3 $name, 3, $name. " : DoorBird_Light_On - ERROR! - Return Code:" . $json->{BHA}{RETURNCODE};
			return "ERROR!\nReturn Code:" . $json->{BHA}{RETURNCODE};	
		}
	}
	### If error message is available
	else {
		### Log Entry
		Log3 $name, 3, $name. " : DoorBird_Light_On - ERROR! - Error Code:" . $err;
		
		### Create error message
		$err =~ s/^[^ ]*//;
		return "ERROR!\nError Code:" . $err;	
	}
}
####END####### Define Subfunction for OPEN DOOR ################################################################END#####

###START###### Define Subfunction for LIGHT ON ################################################################START####
sub DoorBird_Light_On($$) {
	my ($hash, $option)	= @_;
	my $name			= $hash->{NAME};
	my $command			= "light-on.cgi"; 
	my $method			= "GET";
	my $header			= "Accept: application/json";
	my $username 		= DoorBird_credential_decrypt($hash->{helper}{".USER"});
	my $err;
	my $data;
	my $json;

	### Activate Relay
	($err, $data) = DoorBird_BlockGet($hash, $command, $method, $header);

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Light_On - err                          : " . $err;
	Log3 $name, 5, $name. " : DoorBird_Light_On - data                         : " . $data;
	
	### If no error message is available
	if ($err eq "") {
		### Check if json can be parsed into hash
		eval {
			$json = decode_json(encode_utf8($data));
			1;
		}
		or do {
			### Log Entry for debugging purposes
			Log3 $name, 3, $name. " : DoorBird_Light_On - Data cannot be parsed by JSON for: Light_On";
			return $name. " : DoorBird_Light_On - Data cannot be parsed by JSON for Light_On";
		};
		
		### Create return messages and log entries based on error codes returned
		if ($json->{BHA}{RETURNCODE} eq "1") {
			### Log Entry
			Log3 $name, 3, $name. " : DoorBird_Light_On - Light successfully triggered.";
			
			return
		}
		elsif ($json->{BHA}{RETURNCODE} eq "204") {
			### Log Entry
			Log3 $name, 3, $name. " : DoorBird_Light_On - Error 204: The user " . $username . "has no “watch-always” - permission to switch the light ON.";
			
			### Create popup message
			return "Error 204: The user " . $username . "has no “watch-always” - permission to switch the light ON.";
		}
		else {
			### Log Entry
			Log3 $name, 3, $name. " : DoorBird_Light_On - ERROR! - Return Code:" . $json->{BHA}{RETURNCODE};
			return "ERROR!\nReturn Code:" . $json->{BHA}{RETURNCODE};	
		}
	}
	### If error message is available
	else {
		### Log Entry
		Log3 $name, 3, $name. " : DoorBird_Light_On - ERROR! - Error Code:" . $err;
		
		### Create error message
		$err =~ s/^[^ ]*//;
		return "ERROR!\nError Code:" . $err;	
	}
}
####END####### Define Subfunction for LIGHT ON #################################################################END#####

###START###### Define Subfunction for TRANSMIT AUDIO REQUEST ##################################################START####
sub DoorBird_Transmit_Audio($$) {
	my ($hash, $option)	= @_;
	
	### Obtain values from hash
	my $name				= $hash->{NAME};
	my $Username 			= DoorBird_credential_decrypt($hash->{helper}{".USER"});
	my $Password			= DoorBird_credential_decrypt($hash->{helper}{".PASSWORD"});
	my $Url 				= $hash->{helper}{URL};
	my $Sox					= $hash->{helper}{SOX};
	my $AudioDataPathOrig	= $option;
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Transmit_Audio  - ---------------------------------------------------------------";
	
	### If file exists
	if (-e $AudioDataPathOrig) {
		### Create new filepath from old filepath
		my $AudioDataNew;
		my $AudioDataSizeNew;
		my $AudioDataPathNew  = $AudioDataPathOrig;
		   $AudioDataPathNew  =~ s/\..*//;
		   $AudioDataPathNew .= ".wav";

		### If the respective .wav file already exists
		if (-e $AudioDataPathNew) {
		
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - wav file already exists : " . $AudioDataPathNew;
			
		}
		### If the respective .wav file does not exists
		else {
			
			### Create Sox - command
			my $SoxCmd = $Sox . " -V " . $AudioDataPathOrig . " " . $AudioDataPathNew;
			
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - Original Path exists    : " . $AudioDataPathOrig;
			Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - New  Path created       : " . $AudioDataPathNew;
			Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - Sox System-Command      : " . $SoxCmd;

			### Convert file
			system ($SoxCmd);
		}
		
		### Get filesize of wav file
		$AudioDataSizeNew = -s $AudioDataPathNew;

		### Get FileInfo and extract the length of wav file in seconds
		my $SoxCmd = $Sox . " " . $AudioDataPathNew . " -n stat stats";

		my @FileInfo = qx($SoxCmd 2>&1);
		my $AudioLength = $FileInfo[1];
		   $AudioLength =~ s/Length \(seconds\)\://;
		   $AudioLength =~ s/\s+//g;
		   $AudioLength = int($AudioLength);

		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - AudioLength in seconds  : " . $AudioLength;
		Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - New Filesize            : " . $AudioDataSizeNew;

				### Create complete command URL for DoorBird depending on whether SessionIdSecurity has been enabled (>0) or disabled (=0)
		my $UrlPrefix 	= "http://" . $Url . "/bha-api/audio-transmit.cgi";
		my $UrlPostfix;
		
		### If SessionIdSec is enabled
		if ($hash->{helper}{SessionIdSec} != 0) {
			   $UrlPostfix 	= "?sessionid=" . $hash->{helper}{SessionId} . " content-type=\"audio/basic\" use-content-length=true";
		}
		### Id SessionID Security is disabled
		else {
			my $username 	= DoorBird_credential_decrypt($hash->{helper}{".USER"});
			my $password	= DoorBird_credential_decrypt($hash->{helper}{".PASSWORD"});
			   $UrlPostfix 	= " content-type=\"audio/basic\" use-content-length=true user=" . $username . " passwd=" . $password;
		}
		my $CommandURL 	= $UrlPrefix . $UrlPostfix;

		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - CommandURL              : " . $CommandURL ;

		### Create the gst-lauch command
		my $GstCommand  = "gst-launch-1.0 filesrc location="; 
		   $GstCommand .= $AudioDataPathNew;
		   $GstCommand .=  " ! wavparse ! audioconvert ! audioresample ! \"audio/x-raw,format=S16LE,rate=8000,channels=1\" ! mulawenc ! \"audio/x-mulaw,rate=8000,channels=1\" ! curlhttpsink location=";
		   $GstCommand .= $CommandURL;

		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - GstCommand              : " . $GstCommand;

		### Create command for shell
		my $ShellCommand  = "timeout " . ($AudioLength + 3) . " " . $GstCommand . " &";
		
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - ShellCommand            : " . $ShellCommand;

		### Pass shell command to shell and continue with the code below
		eval {
						system($ShellCommand) or die "Could not execute" . $ShellCommand . " ". $@;
		};

		Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - File streamed successf. : " . $AudioDataPathOrig;
		Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - ---------------------------------------------------------------";
		return "The audio file: " . $AudioDataPathOrig . " has been streamed to the DoorBird";
	}
	### If Filepath does not exist
	else {
		### Log Entry
		Log3 $name, 3, $name. " : DoorBird_Transmit_Audio - Path doesn't exist      : " . $AudioDataPathOrig;
		Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - ---------------------------------------------------------------";
		return "The audio file: " . $AudioDataPathOrig . " does not exist!"
	}
}
####END####### Define Subfunction for TRANSMIT AUDIO REQUEST ###################################################END#####

###START###### Define Subfunction for RECEIVE AUDIO REQUEST ###################################################START####
sub DoorBird_Receive_Audio($$) {
	my ($hash, $option)	= @_;
	
	### Obtain values from hash
	my $name				= $hash->{NAME};
	my $Username 			= DoorBird_credential_decrypt($hash->{helper}{".USER"});
	my $Password			= DoorBird_credential_decrypt($hash->{helper}{".PASSWORD"});
	my $Url 				= $hash->{helper}{URL};
	my $Sox					= $hash->{helper}{SOX};
	my $AudioDataPathOrig	= $option;
	
	### For Test only
	my $AudioLength = 7;
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Live_Audio  - ---------------------------------------------------------------";
	
	### If file does not exist already
	if ((-e $AudioDataPathOrig) == false) {
		### Create new filepath from old filepath
		my $AudioDataNew;
		my $AudioDataSizeNew;
		my $AudioDataPathNew  = $AudioDataPathOrig;
		   $AudioDataPathNew  =~ s/\..*//;
		   $AudioDataPathNew .= ".mp3";

		### Create complete command URL for DoorBird depending on whether SessionIdSecurity has been enabled (>0) or disabled (=0)
		my $UrlPrefix 	= "http://" . $Url . "/bha-api/audio-receive.cgi";
		my $UrlPostfix;
		
		### If SessionIdSec is enabled
		if ($hash->{helper}{SessionIdSec} != 0) {
			   $UrlPostfix 	= "?sessionid=" . $hash->{helper}{SessionId};
		}
		### Id SessionID Security is disabled
		else {
			my $username 	= DoorBird_credential_decrypt($hash->{helper}{".USER"});
			my $password	= DoorBird_credential_decrypt($hash->{helper}{".PASSWORD"});
			   $UrlPostfix 	= " user=" . $username . " passwd=" . $password;
		}
		my $CommandURL 	= $UrlPrefix . $UrlPostfix;


		### Log Entry for debugging purposes
		Log3 $name, 1, $name. " : DoorBird_Live_Audio - CommandURL              : " . $CommandURL ;

		### Create the gst-lauch command
		my $GstCommand  = "gst-launch-1.0 filesrc location=<"; 
		   $GstCommand .= $CommandURL;
		   $GstCommand .=  "> ! wavparse ! audioconvert ! lame ! filesink location=";
		   $GstCommand .= $AudioDataPathNew;

		### Log Entry for debugging purposes
		Log3 $name, 1, $name. " : DoorBird_Live_Audio - GstCommand              : " . $GstCommand;

		### Create command for shell
		my $ShellCommand  = "timeout " . ($AudioLength + 3) . " " . $GstCommand . " &";
		
		### Log Entry for debugging purposes
		Log3 $name, 1, $name. " : DoorBird_Live_Audio - ShellCommand            : " . $ShellCommand;

		### Pass shell command to shell and continue with the code below
		eval {
						system($ShellCommand) or die "Could not execute" . $ShellCommand . " ". $@;
		};

		Log3 $name, 1, $name. " : DoorBird_Live_Audio - File streamed successf. : " . $AudioDataPathOrig;
		Log3 $name, 1, $name. " : DoorBird_Live_Audio - ---------------------------------------------------------------";
		return "The audio file: " . $AudioDataPathOrig . " has been streamed to the DoorBird";
	}
	### If Filepath does not exist
	else {
		### Log Entry
		Log3 $name, 1, $name. " : DoorBird_Live_Audio - Path doesn't exist      : " . $AudioDataPathOrig;
		Log3 $name, 1, $name. " : DoorBird_Live_Audio - ---------------------------------------------------------------";
		return "The audio file: " . $AudioDataPathOrig . " does not exist!"
	}
}
####END####### Define Subfunction for RECEIVE VIDEO REQUEST ####################################################END#####

###START###### Define Subfunction for HISTORY IMAGE REQUEST ###################################################START####
### https://wiki.fhem.de/wiki/HttpUtils#HttpUtils_NonblockingGet
sub DoorBird_History_Request($$) {
	my ($hash, $option)	= @_;

	### Obtain values from hash
	my $Name			= $hash->{NAME};
	my $Username 		= DoorBird_credential_decrypt($hash->{helper}{".USER"});
	my $Password		= DoorBird_credential_decrypt($hash->{helper}{".PASSWORD"});
	my $PollingTimeout  = $hash->{helper}{PollingTimeout};
	my $url 			= $hash->{helper}{URL};
	my $Method			= "GET";
	my $Header			= "Accept: application/json";
	my $err;
	my $data;
	my $UrlPostfix;
	my $CommandURL;
	
	### Create Timestamp
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
	my $ImageTimeStamp	    = sprintf ( "%04d-%02d-%02d %02d:%02d:%02d",$year+1900, $mon+1, $mday, $hour, $min, $sec);

	
	### Create first part command URL for DoorBird
	my $UrlPrefix 		= "https://" . $url . "/bha-api/";

	### If the Itereation is started for the first time = new polling
	if ($hash->{helper}{HistoryDownloadCount} == 0) {
		### Delete arrays of pictures
		@{$hash->{helper}{Images}{History}{doorbell}}		= ();
		@{$hash->{helper}{Images}{History}{motionsensor}}	= ();
		  $hash->{helper}{HistoryTime}						= $ImageTimeStamp;
		  $hash->{helper}{HistoryDownloadActive} 			= true;
	}
	
	### Define STATE message
	my $CountDown = $hash->{helper}{MaxHistory}*2 - $hash->{helper}{HistoryDownloadCount};
	
	### Update STATE of device
	readingsSingleUpdate($hash, "state", "Downloading history: " . $CountDown, 1);

	### Create the URL Index which is identical every 2nd: 1 1 2 2 3 3 4 4 5 5 6 6
	my $UrlIndex=int(int($hash->{helper}{HistoryDownloadCount})/int(2))+1;
	
	### As long the maximum ammount of Images for history events is not reached
	if ($UrlIndex <= $hash->{helper}{MaxHistory}) {
		### If the counter is even, download an image based on the doorbell event
		if (0 == $hash->{helper}{HistoryDownloadCount} % 2) {
			### Create Parameter for CommandURL for doorbell events
			$UrlPostfix = "history.cgi?event=doorbell&index=" . $UrlIndex;
		} 
		### If the counter is odd, download an image based on the motion sensor event
		else {
			### Create Parameter for CommandURL for motionsensor events
			$UrlPostfix = "history.cgi?event=motionsensor&index=" . $UrlIndex;
		}
	}
	### If the requested maximum number of Images for history events is reached
	else {
		### Reset helper
		$hash->{helper}{HistoryDownloadActive} = false;
		$hash->{helper}{HistoryDownloadCount}  = 0;
		
		### Update STATE of device
		readingsSingleUpdate($hash, "state", "connected", 1);
		
		### Refresh Browser Window		
		FW_directNotify("#FHEMWEB:$FW_wname", "location.reload()", "") if defined($FW_wname);
		
		### Return since Routine is finished or wrong parameter has been transfered.
		return
	}

	### Create complete command URL for DoorBird
	$CommandURL = $UrlPrefix . $UrlPostfix;	
	
	### Define Parameter for Non-BlockingGet
	my $param = {
		url                => $CommandURL,
		timeout            => $PollingTimeout,
		user               => $Username,
		pwd                => $Password,
		hash               => $hash,
		method             => $Method,
		header             => $Header,
		incrementalTimeout => 1,
		callback           => \&DoorBird_History_Request_Parse
	};
	
	### Initiate communication and close
	HttpUtils_NonblockingGet($param);

	return;
}

sub DoorBird_History_Request_Parse($) {
	my ($param, $err, $data) = @_;
    my $hash = $param->{hash};

	### Obtain values from hash
    my $name = $hash->{NAME};

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_History_Request ___________________________________________________________";
	Log3 $name, 5, $name. " : DoorBird_History_Request - Download Index         : " . $hash->{helper}{HistoryDownloadCount};
	Log3 $name, 5, $name. " : DoorBird_History_Request - err                    : " . $err           if (defined($err  ));
	Log3 $name, 5, $name. " : DoorBird_History_Request - length data            : " . length($data)  if (defined($data ));
#	Log3 $name, 5, $name. " : DoorBird_History_Request - param                  : " . join("\n", @{[%{$param}]}) if (defined($param));

	
	### If error message available
	if ($err ne "") {
		### Create Log entry
		Log3 $name, 3, $name. " : DoorBird_History_Request - Error                  : " . $err        if (defined($err  ));
	}
	### if no error message available
	else {
		### If any image data available
		if (defined $data) {

			### Predefine Image Data and Image-hash and hash - reference		
			my $ImageData;
			my $ImageTimeStamp;
			my $ImageFileTimeStamp;
			my $ImageFileName;
			my %ImageDataHash;
			my $ref_ImageDataHash = \%ImageDataHash;
			
			### If http response code is 200 = OK
			if ($param->{code} == 200) {
				### Encode jpeg data into base64 data and remove lose newlines
				$ImageData =  MIME::Base64::encode($data);
				$ImageData =~ s{\n}{}g;

				### Create Timestamp
				my $httpHeader = $param->{httpheader};
				   $httpHeader =~ s/^[^_]*X-Timestamp: //;
				   $httpHeader =~ s/\n.*//g;
				my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($httpHeader);
				$ImageTimeStamp	    = sprintf ( "%04d-%02d-%02d %02d:%02d:%02d",$year+1900, $mon+1, $mday, $hour, $min, $sec);
				$ImageFileTimeStamp	= sprintf ( "%04d%02d%02d-%02d%02d%02d"    ,$year+1900, $mon+1, $mday, $hour, $min, $sec);
			}
			### If http response code is 204 = Nno permission to download the event history
			elsif ($param->{code} == 204) {
				### Create Log entry
				Log3 $name, 3, $name. " : DoorBird_History_Request - Error 204              : User not authorized to download event history";
				
				### Create Error message
				$ImageData = "Error 204: The user has no permission to download the event history.";
				$ImageTimeStamp =" ";
			}
			### If http response code is 404 = No picture available to download the event history
			elsif ($param->{code} == 404) {
				### Create Log entry
				Log3 $name, 5, $name. " : DoorBird_History_Request - Error 404              : No picture available to download event history. Check settings in DoorBird APP.";
				
				### Create Error message
				$ImageData = "Error 404: No picture available to download in the event history.";
				$ImageTimeStamp =" ";
			}
			### If http response code is none of one above
			else {
				### Create Log entry
				Log3 $name, 3, $name. " : DoorBird_History_Request - Unknown http response code    : " . $param->{code};
			
				### Create Error message
				$ImageData = "Error : " . $param->{code};
				$ImageTimeStamp =" ";
			}
			
			### Create the URL Index which is identical every 2nd: 1 1 2 2 3 3 4 4 5 5 6 6
			my $UrlIndex=int(int($hash->{helper}{HistoryDownloadCount})/int(2))+1;
			
			### If the counter is even, download an image based on the doorbell event
			if (0 == $hash->{helper}{HistoryDownloadCount} % 2) {
				my $HistoryDownloadCount = $hash->{helper}{HistoryDownloadCount};
				
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_Request - doorbell - HistoryCount: " . $HistoryDownloadCount;
			
				### Save Image data and timestamp into hash
				$ref_ImageDataHash->{data}      = $ImageData;
				$ref_ImageDataHash->{timestamp} = $ImageTimeStamp;
			
				### Save image hash into array of hashes
				push (@{$hash->{helper}{Images}{History}{doorbell}}, $ref_ImageDataHash);

				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_Request - hash - ImageFileDir    : " . $hash->{helper}{ImageFileDir};

				### If pictures supposed to be saved as files
				if ($hash->{helper}{ImageFileDir} ne "0") {

					### Get current working directory
					my $cwd = getcwd();

					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_History_Request - working directory      : " . $cwd;


					### If the path is given as UNIX file system format
					if ($cwd =~ /\//) {
						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_History_Request - file system format     : LINUX";

						### Find out whether it is an absolute path or an relative one (leading "/")
						if ($hash->{helper}{ImageFileDir} =~ /^\//) {
							$ImageFileName = $hash->{helper}{ImageFileDir};
						}
						else {
							$ImageFileName = $cwd . "/" . $hash->{helper}{ImageFileDir};						
						}

						### Check whether the last "/" at the end of the path has been given otherwise add it an create complete path
						if ($hash->{helper}{ImageFileDir} =~ /\/\z/) {
							$ImageFileName .=       $ImageFileTimeStamp . "_doorbell.jpg";
						}
						else {
							$ImageFileName .= "/" . $ImageFileTimeStamp . "_doorbell.jpg";
						}
					}

					### If the path is given as Windows file system format
					if ($hash->{helper}{ImageFileDir} =~ /\\/) {
						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_History_Request - file system format     : WINDOWS";

						### Find out whether it is an absolute path or an relative one (containing ":\")
						if ($hash->{helper}{ImageFileDir} != /^.:\//) {
							$ImageFileName = $cwd . $hash->{helper}{ImageFileDir};
						}
						else {
							$ImageFileName = $hash->{helper}{ImageFileDir};						
						}

						### Check whether the last "/" at the end of the path has been given otherwise add it an create complete path
						if ($hash->{helper}{ImageFileDir} =~ /\\\z/) {
							$ImageFileName .=       $ImageFileTimeStamp . "_doorbell.jpg";
						}
						else {
							$ImageFileName .= "\\" . $ImageFileTimeStamp . "_doorbell.jpg";
						}
					}
					
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_History_Request - ImageFileName          : " . $ImageFileName;

					### Open file or write error message in log
					open my $fh, ">", $ImageFileName or do {
						### Log Entry 
						Log3 $name, 2, $name. " : DoorBird_History_Request -  open file error       : " . $! . " - ". $ImageFileName;
					};
					
					### Write the base64 decoded data in file
					print $fh decode_base64($ImageData) if defined($fh);
					
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_History_Request - write file             : Successfully written " . $ImageFileName;
					
					### Close file or write error message in log
					close $fh or do {
						### Log Entry 
						Log3 $name, 2, $name. " : DoorBird_History_Request - close file error       : " . $! . " - ". $ImageFileName;
					}
				}
				
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_Request - Index - doorbell       : " . $UrlIndex;
				Log3 $name, 5, $name. " : DoorBird_History_Request - ImageData - doorbell   : " . length($ImageData);
			} 
			### If the counter is odd, download an image based on the motion sensor event
			else {
				my $HistoryDownloadCount = $hash->{helper}{HistoryDownloadCount} - 50;
				
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_Request - motion  - HistoryCount : " . $HistoryDownloadCount;
				
				### Save Image data and timestamp into hash
				$ref_ImageDataHash->{data}      = $ImageData;
				$ref_ImageDataHash->{timestamp} = $ImageTimeStamp;
			
				### Save image hash into array of hashes
				push (@{$hash->{helper}{Images}{History}{motionsensor}}, $ref_ImageDataHash);

				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_Request - hash - ImageFileDir    : " . $hash->{helper}{ImageFileDir};

				### If pictures supposed to be saved as files
				if ($hash->{helper}{ImageFileDir} ne "0") {

					### Get current working directory
					my $cwd = getcwd();

					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_History_Request - working directory      : " . $cwd;


					### If the path is given as UNIX file system format
					if ($cwd =~ /\//) {
						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_History_Request - file system format     : LINUX";

						### Find out whether it is an absolute path or an relative one (leading "/")
						if ($hash->{helper}{ImageFileDir} =~ /^\//) {
							$ImageFileName = $hash->{helper}{ImageFileDir};
						}
						else {
							$ImageFileName = $cwd . "/" . $hash->{helper}{ImageFileDir};						
						}

						### Check whether the last "/" at the end of the path has been given otherwise add it an create complete path
						if ($hash->{helper}{ImageFileDir} =~ /\/\z/) {
							$ImageFileName .=       $ImageFileTimeStamp . "_motionsensor.jpg";
						}
						else {
							$ImageFileName .= "/" . $ImageFileTimeStamp . "_motionsensor.jpg";
						}
					}

					### If the path is given as Windows file system format
					if ($hash->{helper}{ImageFileDir} =~ /\\/) {
						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_History_Request - file system format     : WINDOWS";

						### Find out whether it is an absolute path or an relative one (containing ":\")
						if ($hash->{helper}{ImageFileDir} != /^.:\//) {
							$ImageFileName = $cwd . $hash->{helper}{ImageFileDir};
						}
						else {
							$ImageFileName = $hash->{helper}{ImageFileDir};						
						}

						### Check whether the last "/" at the end of the path has been given otherwise add it an create complete path
						if ($hash->{helper}{ImageFileDir} =~ /\\\z/) {
							$ImageFileName .=       $ImageFileTimeStamp . "_motionsensor.jpg";
						}
						else {
							$ImageFileName .= "\\" . $ImageFileTimeStamp . "_motionsensor.jpg";
						}
					}
					
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_History_Request - ImageFileName          : " . $ImageFileName;

					### Open file or write error message in log
					open my $fh, ">", $ImageFileName or do {
						### Log Entry 
						Log3 $name, 2, $name. " : DoorBird_History_Request -  open file error       : " . $! . " - ". $ImageFileName;
					};
					
					### Write the base64 decoded data in file
					print $fh decode_base64($ImageData) if defined($fh);
					
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_History_Request - write file             : Successfully written " . $ImageFileName;
					
					### Update the history list for images and videos
					DoorBird_History_List($hash);
					
					### Close file or write error message in log
					close $fh or do {
						### Log Entry 
						Log3 $name, 2, $name. " : DoorBird_History_Request - close file error       : " . $! . " - ". $ImageFileName;
					}
				}
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_Request - Index - motionsensor   : " . $UrlIndex;
				Log3 $name, 5, $name. " : DoorBird_History_Request - ImageData- motionsensor: " . length($ImageData);
			}
		}		
		### If no image data available
		else {
			### Create second part command URL for DoorBird based on iteration cycle
			if (($hash->{helper}{HistoryDownloadCount} > 0) && $hash->{helper}{HistoryDownloadCount} <= 50) {
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_Request - No Image  doorbell     : " . $hash->{helper}{HistoryDownloadCount};
			}
			elsif (($hash->{helper}{HistoryDownloadCount} > 50) && $hash->{helper}{HistoryDownloadCount} <= 100) {
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_Request - No Image  motionsensor : " . ($hash->{helper}{HistoryDownloadCount} -50);
			}
			else {
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_Request - ERROR! Wrong Index  b) : " . $hash->{helper}{HistoryDownloadCount};
			}
		}
	}
	
	### Increase Download Counter and download the next one
	$hash->{helper}{HistoryDownloadCount}++;
	DoorBird_History_Request($hash, "");
	return
}
####END####### Define Subfunction for HISTORY IMAGE REQUEST ####################################################END#####

###START###### Define Subfunction for history list update as readings #########################################START####
sub DoorBird_History_List($) {
	my ($hash)	= @_;

	### Obtain values from hash
	my $name			= $hash->{NAME};

	### If the HistoryFile List shall be created
	if ($hash->{helper}{HistoryFilePath} == true) {
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_History_List ___________________________________________________________";
		Log3 $name, 5, $name. " : DoorBird_History_List - The HistoryList has been activated. Processing...";

		### Delete all older reading entries to files
		#fhem("deleteReading " . $name . " HistoryFilePath.*", 1);
		
		foreach my $DeleteReading (keys %{$hash->{READINGS}}) {
			if ($DeleteReading =~ m/HistoryFilePath/ ){
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_List - Delete Reading            :  " . $DeleteReading;
				
				### Delete Reading
				readingsDelete($hash, $DeleteReading);
			}
		}

		### Get current working directory
		my $cwd = getcwd();

		### If the ImageFileDir has been defined and images are taken
		if ((defined($hash->{helper}{ImageFileDir})) && (($hash->{helper}{ImageFileDir} =~ m/\/fhem\/www/)) || (($hash->{helper}{ImageFileDir} =~ m/\\fhem\\www/))){
			my $ImageFileName;
			my @ImageFileList;

			### If the path is given as UNIX file system format
			if ($cwd =~ /\//) {
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_List - file system format       : UNIX";

				### Find out whether it is an absolute path or an relative one (leading "/")
				if ($hash->{helper}{ImageFileDir} =~ /^\//) {
					$ImageFileName = $hash->{helper}{ImageFileDir};
				}
				else {
					$ImageFileName = $cwd . "/" . $hash->{helper}{ImageFileDir};						
				}
			}
			
			### If the path is given as Windows file system format
			if ($hash->{helper}{ImageFileDir} =~ /\\/) {
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_List - file system format       : WINDOWS";

				### Find out whether it is an absolute path or an relative one (containing ":\")
				if ($hash->{helper}{ImageFileDir} != /^.:\//) {
					$ImageFileName = $cwd . $hash->{helper}{ImageFileDir};
				}
				else {
					$ImageFileName = $hash->{helper}{ImageFileDir};						
				}
			}
			
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_History_List - ImageFileName             : " . $ImageFileName;

			### Get list of directory items
			if (opendir(FileSearch,$ImageFileName)) {
				@ImageFileList		= readdir(FileSearch);
				close FileSearch;

				### Define Types to be searched for
				my @FileTypes		= ("motionsensor", "doorbell", "keypad", "snapshot", "manual");

				readingsBeginUpdate($hash);

				foreach my $SearchType (@FileTypes) {
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_History_List - SearchType                : " . $SearchType;
					
					### Extract all Filenames which matches the SearchType
					my @ImageFileListSearch = grep {/$SearchType/} @ImageFileList;

					### Extract all Filenames which matches the file extension
					my @ImageFileListExt = grep {/jpg/} @ImageFileListSearch;
						
					# Sort list
					@ImageFileListExt=sort(@ImageFileListExt);
						
					### Get the last n elements (hash->{helper}{MaxHistory})
					@ImageFileListExt = ($hash->{helper}{MaxHistory} >= @ImageFileListExt) ? @ImageFileListExt : @ImageFileListExt[-$hash->{helper}{MaxHistory}..-1];

					# Sort list
					@ImageFileListExt=sort({$b cmp $a} @ImageFileListExt);
						
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_History_List - ImageFileListSearch       : \n" . Dumper(@ImageFileListExt);
						
					### Update Readings
					my $index = 0;
					foreach my $FileName (@ImageFileListExt){
						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_History_List - FileName                  : " . $FileName;

						### Extract timestamp from Filename
						my $TimeStamp  = substr($FileName,0,4) . "-" . substr($FileName, 4,2) . "-" . substr($FileName, 6,2) . " ";
						   $TimeStamp .= substr($FileName,9,2) . ":" . substr($FileName,11,2) . ":" . substr($FileName,13,2);
						
						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_History_List - TimeStamp                 : " . $TimeStamp;

						### Complete relative path from /opt/fhem/www/tablet to $hash->{helper}{ImageFileDir}
						my $FilePath = abs2rel(rel2abs($ImageFileName), rel2abs("/opt/fhem/www/tablet"));
						my $ReadingsValue = $FilePath . "/" . $FileName;

						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_History_List - FilePath                  : " . $FilePath;
						
						### Create ReadingsName for Imagepath and write reading
						my $ReadingsName = "HistoryFilePath_" . $SearchType . "_Image_" . sprintf("%02d", $index);
						readingsBulkUpdate($hash, $ReadingsName, $ReadingsValue);

						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_History_List - ReadingsName-Image        : " . $ReadingsName;
						Log3 $name, 5, $name. " : DoorBird_History_List - ReadingsValue-Image       : " . $ReadingsValue;

						
						### Create ReadingsName for Timestamp and write reading
						$ReadingsName = "HistoryFilePath_" . $SearchType . "_Image_" . sprintf("%02d", $index) . "_Timestamp";
						readingsBulkUpdate($hash, $ReadingsName, $TimeStamp);

						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_History_List - ReadingsName-Timestamp    : " . $ReadingsName;
						Log3 $name, 5, $name. " : DoorBird_History_List - ReadingsValue-Timestamp   : " . $TimeStamp;

						### Increase Index
						$index++;
					}
				}
			}
			else {
				### Log Entry for warning
				Log3 $name, 2, $name. " : DoorBird_History_List - The Attribute \"ImageFileDir\" leads to an directory which produced an error! - Does it actually exist?";		
			}
		}
		else {
			### Log Entry for warning
			Log3 $name, 4, $name. " : DoorBird_History_List - The ImageFileDir has not been provided or has not been created below the web-folder e.g. \"/opt/fhem/www/doorbird-images/\"";
		}
		### If the VideoFileDir has been defined and Videos are taken
		if ((defined($hash->{helper}{VideoFileDir})) && (($hash->{helper}{VideoFileDir} =~ m/\/fhem\/www/) || (($hash->{helper}{ImageFileDir} =~ m/\\fhem\\www/)))){
			my $VideoFileName;
			my @VideoFileList;
			
			### If the path is given as UNIX file system format
			if ($cwd =~ /\//) {
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_List - file system format        : UNIX";

				### Find out whether it is an absolute path or an relative one (leading "/")
				if ($hash->{helper}{VideoFileDir} =~ /^\//) {
					$VideoFileName = $hash->{helper}{VideoFileDir};
				}
				else {
					$VideoFileName = $cwd . "/" . $hash->{helper}{VideoFileDir};						
				}
			}
			
			### If the path is given as Windows file system format
			if ($hash->{helper}{VideoFileDir} =~ /\\/) {
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_List - file system format        : WINDOWS";

				### Find out whether it is an absolute path or an relative one (containing ":\")
				if ($hash->{helper}{VideoFileDir} != /^.:\//) {
					$VideoFileName = $cwd . $hash->{helper}{VideoFileDir};
				}
				else {
					$VideoFileName = $hash->{helper}{VideoFileDir};						
				}
			}
			
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_History_List - VideoFileName             : " . $VideoFileName;

			### Get list of directory items
			if (opendir(FileSearch,$VideoFileName)) {
				@VideoFileList		= readdir(FileSearch);
				close FileSearch;

				### Define Types to be searched for
				my @FileTypes		= ("motionsensor", "doorbell", "keypad", "snapshot", "manual");

				readingsBeginUpdate($hash);

				foreach my $SearchType (@FileTypes) {
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_History_List - SearchType                : " . $SearchType;
					
					### Extract all Filenames which matches the SearchType
					my @VideoFileListSearch = grep {/$SearchType/} @VideoFileList;

					### Extract all Filenames which matches the file extension
					my @VideoFileListExt = grep {/$hash->{helper}{VideoFileFormat}/} @VideoFileListSearch;
						
					# Sort list
					@VideoFileListExt=sort(@VideoFileListExt);
						
					### Get the last n elements (hash->{helper}{MaxHistory})
					@VideoFileListExt = ($hash->{helper}{MaxHistory} >= @VideoFileListExt) ? @VideoFileListExt : @VideoFileListExt[-$hash->{helper}{MaxHistory}..-1];

					# Sort list
					@VideoFileListExt=sort({$b cmp $a} @VideoFileListExt);
						
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_History_List - VideoFileListSearch       : \n" . Dumper(@VideoFileListExt);
						
					### Update Readings
					my $index = 0;
					foreach my $FileName (@VideoFileListExt){
						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_History_List - FileName                  : " . $FileName;

						### Extract timestamp from Filename
						my $TimeStamp  = substr($FileName,0,4) . "-" . substr($FileName, 4,2) . "-" . substr($FileName, 6,2) . " ";
						   $TimeStamp .= substr($FileName,9,2) . ":" . substr($FileName,11,2) . ":" . substr($FileName,13,2);
						
						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_History_List - TimeStamp                 : " . $TimeStamp;

						### Complete relative path from /opt/fhem/www/tablet to $hash->{helper}{VideoFileDir}
						my $FilePath = abs2rel(rel2abs($VideoFileName), rel2abs("/opt/fhem/www/tablet"));
						my $ReadingsValue = $FilePath . "/" . $FileName;

						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_History_List - FilePath                  : " . $FilePath;
						
						### Create ReadingsName for Videopath and write reading
						my $ReadingsName = "HistoryFilePath_" . $SearchType . "_Video_" . sprintf("%02d", $index);
						readingsBulkUpdate($hash, $ReadingsName, $ReadingsValue);

						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_History_List - ReadingsName-Video        : " . $ReadingsName;
						Log3 $name, 5, $name. " : DoorBird_History_List - ReadingsValue-Video       : " . $ReadingsValue;

						
						### Create ReadingsName for Timestamp and write reading
						$ReadingsName = "HistoryFilePath_" . $SearchType . "_Video_" . sprintf("%02d", $index) . "_Timestamp";
						readingsBulkUpdate($hash, $ReadingsName, $TimeStamp);

						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_History_List - ReadingsName-Timestamp    : " . $ReadingsName;
						Log3 $name, 5, $name. " : DoorBird_History_List - ReadingsValue-Timestamp   : " . $TimeStamp;

						### Increase Index
						$index++;
					}
				}
			}
			else {
				### Log Entry for warning
				Log3 $name, 2, $name. " : DoorBird_History_List - The Attribute \"VideoFileDir\" leads to an directory which produced an error! - Does it actually exist?";		
			}
		}	
		else {
			### Log Entry for warning
			Log3 $name, 4, $name. " : DoorBird_History_List - The VideoFileDir has not been provided or has not been created below the web-folder e.g. \"/opt/fhem/www/doorbird-videos/\"";
		}

		### Initiate Readings Update
		readingsEndUpdate($hash, 1);
	}
	else {
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_History_List - The HistoryList has been disabled. Not Links to pictures are provided.";
	}
}
####END####### Define Subfunction for history list update as readings ##########################################END#####

###START###### Define Subfunction for VIDEO REQUEST ###########################################################START####
sub DoorBird_Video_Request($$$$) {
	my ($hash, $duration, $event, $timestamp)	= @_;

	### Obtain values from hash
	my $name			= $hash->{NAME};
	my $url 			= $hash->{helper}{URL};
	my $Method			= "GET";
	my $Header			= "Accept: application/json";
	my $VideoFileName;
	my $ReadingVideo;
	my $err;
	my $data;
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Video_Request ___________________________________________________________";
	Log3 $name, 5, $name. " : DoorBird_Video_Request - duration                 : " . $duration;
	Log3 $name, 5, $name. " : DoorBird_Video_Request - event                    : " . $event;
	Log3 $name, 5, $name. " : DoorBird_Video_Request - timestamp                : " . $timestamp;
	
	### Create name for Reading holding the filename for the event triggered video
	if ($event =~ m/doorbell/ ){
		Log3 $name, 5, $name. " : DoorBird_Video_Request - doorbell event old       : " . $event;
		### Extract doorbell pushbutton number from event
		my $DoorbellNo = $event =~ s/doorbell_//;
		### Reset event back to doorbell without pushbutton number
		$event = "doorbell";
		$ReadingVideo			= "doorbell_video_" . sprintf("%03d", $DoorbellNo);

		Log3 $name, 5, $name. " : DoorBird_Video_Request - doorbellevent new        : " . $event;
		Log3 $name, 5, $name. " : DoorBird_Video_Request - DoorbellNo               : " . $DoorbellNo;
		
	}
	elsif ($event =~ m/motionsensor/ ){
		$ReadingVideo 			= "motion_video";
	}
	elsif ($event =~ m/keypad/ ){
		$ReadingVideo 			= "keypad_video";
	}
	elsif ($event =~ m/manual/ ){
		$ReadingVideo 			= "manual_video";
	}
	else {
		### Create Log entry
		Log3 $name, 2, $name. " : DoorBird_LastEvent_Image - Unknown event. Breaking up";
		
		### Exit sub
		return
	}
	Log3 $name, 3, $name. " : DoorBird_Video_Request - ReadingVideo             : " . $ReadingVideo;
	
	### Create complete command URL for DoorBird depending on whether SessionIdSecurity has been enabled (>0) or disabled (=0)
	my $UrlPrefix 		= "http://" . $url . "/bha-api/";
	my $UrlPostfix;
	if ($hash->{helper}{SessionIdSec} > 0) {
		$UrlPostfix 	= "?sessionid=" . $hash->{helper}{SessionId};
	}
	else {
		my $username 	= DoorBird_credential_decrypt($hash->{helper}{".USER"});
		my $password	= DoorBird_credential_decrypt($hash->{helper}{".PASSWORD"});
		$UrlPostfix 	= "?http-user=". $username . "&http-password=" . $password;
	}
	my $CommandURL 		= $UrlPrefix . "video.cgi" . $UrlPostfix;

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Video_Request - CommandURL              : " . $CommandURL ;
	
	### Create Timestamp
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($timestamp);
	my $VideoFileTimeStamp	= sprintf ( "%04d%02d%02d-%02d%02d%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec);

	### Update STATE of device
	readingsSingleUpdate($hash, "state", "Retrieving video", 1);

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Video_Request - hash - VideoFileDir      : " . $hash->{helper}{VideoFileDir};

	### If attribute to video directory has been set
	if ($hash->{helper}{VideoFileDir} ne "") {

		### Get current working directory
		my $cwd = getcwd();
		my $VideoFileDir;

		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_Video_Request - working directory        : " . $cwd;

		### If the path is given as UNIX file system format
		if ($cwd =~ /\//) {
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Video_Request - file system format     : LINUX";

			### Find out whether it is an absolute path or an relative one (leading "/")
			if ($hash->{helper}{VideoFileDir} =~ /^\//) {
			
				$VideoFileName = $hash->{helper}{VideoFileDir};
			}
			else {
				$VideoFileName = $cwd . "/" . $hash->{helper}{VideoFileDir};						
			}

			### Check whether the last "/" at the end of the path has been given otherwise add it an create complete path
			if ($hash->{helper}{VideoFileDir} =~ /\/\z/) {
				### Save directory
				$VideoFileDir = $VideoFileName;
				
				### Create complete datapath
				$VideoFileName .=       $VideoFileTimeStamp . "_" . $event . "." . $hash->{helper}{VideoFileFormat};
			}
			else {
				### Save directory
				$VideoFileDir = $VideoFileName . "/";
				
				### Create complete datapath
				$VideoFileName .= "/" . $VideoFileTimeStamp . "_" . $event . "." . $hash->{helper}{VideoFileFormat};
			}
			
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Video_Request - VideoFileName            : " . $VideoFileName;

			### Create command for shell
			my $ShellCommand  = "timeout " . $duration . " ffmpeg -hide_banner -loglevel panic -re -i '" . $CommandURL . "' -filter:v setpts=4.0*PTS -y " . $VideoFileName . " &";
			
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Video_Request - ShellCommand             : " . $ShellCommand;

			### Pass shell command to shell and continue with the code below
			eval {
							system($ShellCommand) or die "Could not execute" . $ShellCommand . " ". $@;
			};
			### If error message appered
			if ( $@ ) {
			#				$ErrorMessage = $@;
			}
			
			### Write Last video into reading
			readingsSingleUpdate($hash, $ReadingVideo, $VideoFileName, 1);
		}

		### If the path is given as Windows file system format
		if ($hash->{helper}{VideoFileDir} =~ /\\/) {
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Video_Request - file system format       : WINDOWS";

			### Find out whether it is an absolute path or an relative one (containing ":\")
			if ($hash->{helper}{VideoFileDir} != /^.:\//) {
				$VideoFileName = $cwd . $hash->{helper}{VideoFileDir};
			}
			else {
				$VideoFileName = $hash->{helper}{VideoFileDir};						
			}

			### Check whether the last "/" at the end of the path has been given otherwise add it an create complete path
			if ($hash->{helper}{VideoFileDir} =~ /\\\z/) {
				### Save directory
				$VideoFileDir = $VideoFileName;
				
				### Create full datapath
				$VideoFileName .=       $VideoFileTimeStamp . "_" . $event . "." . $hash->{helper}{VideoFileFormat};
			}
			else {
				### Save directory
				$VideoFileDir = $VideoFileName . "\\";

				### Create full datapath
				$VideoFileName .= "\\" . $VideoFileTimeStamp . "_" . $event . "." . $hash->{helper}{VideoFileFormat};
			}
			
			### Log Entry for debugging purposes
			Log3 $name, 2, $name. " : DoorBird_Video_Request - Video-Request ha not been implemented for Windows file system. Contact fhem forum and WIKI.";
		}
		
		### Free FileDirSpace if exxeeds maximum
		DoorBird_FileSpace($hash, $VideoFileDir, $hash->{helper}{VideoFileFormat}, $hash->{helper}{VideoFileDirMaxSize});
		
		### Update the history list for images and videos after the video has been taken
		InternalTimer(gettimeofday()+$duration+3,"DoorBird_History_List", $hash, 0);
	}
	### If attribute to video directory has NOT been set
	else {
		### Log Entry for debugging purposes
		Log3 $name, 2, $name . " : DoorBird_Video_Request - Could not open directory for video files. See commandref for attribute \"VideoFileDir\".";
	}

	return;
}
####END####### Define Subfunction for VIDEO REQUEST ############################################################END#####
	
##START###### Define Subfunction for LIST FAVOURITES #########################################################START####
sub DoorBird_List_Favorites($$) {
	my ($hash, $option)	= @_;
	my $name			= $hash->{NAME};
	my $command			= "favorites.cgi"; 
	my $method			= "GET";
	my $header			= "Accept: application/json";
	
	my $err = " ";
	my $data = " ";
	my $json;
	
	### Obtain data
	($err, $data) = DoorBird_BlockGet($hash, $command, $method, $header);

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Get - List_Favourites - err                 : " . $err;
	Log3 $name, 5, $name. " : DoorBird_Get - List_Favourites - data                : " . $data;
	
	### If no error has been handed back
	if ($err eq "") {
		### If the option is  asking for the JSON string
		if (defined($option) && ($option =~ /JSON/i)) {
			return $data;		
		}
		### If the option is asking for nothing special
		else {
			### Check if json can be parsed into hash	
			eval 
			{
				$json = decode_json(encode_utf8($data));
				1;
			}
			or do 
			{
				### Log Entry for debugging purposes
				Log3 $name, 3, $name. " : DoorBird_Get - Data cannot be parsed by JSON for  : List_Favourites";
				return $name. " : DoorBird_Get - Data cannot be parsed by JSON for List_Favourites";
			};
			
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Get - json                               : " . $json;

			### Delete all Readings for Relay-Addresses
			fhem( "deletereading $name Favorite_.*" );
			
			### Initiate Bulk Update
			readingsBeginUpdate($hash);
			
			### For every chapter in the List of Favourites (e.g. SIP, http)
			foreach my $FavoritChapter (keys %{$json}) {
				### For every item in the List of chapters (e.g. 0, 1, 5 etc.)
				foreach my $FavoritItem (keys %{$json->{$FavoritChapter}}) {
				
					### Create first part of Reading
					my $ReadingName = "Favorite_" . $FavoritChapter . "_" . $FavoritItem;

					### Update Reading
					readingsBulkUpdate($hash, $ReadingName . "_Title", $json->{$FavoritChapter}{$FavoritItem}{title});
					readingsBulkUpdate($hash, $ReadingName . "_Value", $json->{$FavoritChapter}{$FavoritItem}{value});
										
					### Log Entry for debugging purpose
					Log3 $name, 5, $name. " : DoorBird_List_Favorites --------------------------------";
					Log3 $name, 5, $name. " : DoorBird_List_Favorites - Reading                 : " . $ReadingName;
					Log3 $name, 5, $name. " : DoorBird_List_Favorites - _Title                  : " . $json->{$FavoritChapter}{$FavoritItem}{title};
					Log3 $name, 5, $name. " : DoorBird_List_Favorites - _Value                  : " . $json->{$FavoritChapter}{$FavoritItem}{title};
				}
			}
			### Execute Readings Bulk Update
			readingsEndUpdate($hash, 1);		
			return "Readings have been updated!\nPress F5 to refresh Browser.";
		}
	}
	### If error has been handed back
	else {
		$err =~ s/^[^ ]*//;
		return "ERROR!\nError Code:" . $err;
	}
}
####END####### Define Subfunction for LIST FAVOURITES ##########################################################END#####

###START###### Define Subfunction for LIST SCHEDULES ##########################################################START####
sub DoorBird_List_Schedules($$) {
	my ($hash, $option)	= @_;
	my $name			= $hash->{NAME};
	my $command			= "schedule.cgi"; 
	my $method			= "GET";
	my $header			= "Accept: application/json";
	
	my $err = " ";
	my $data = " ";
	my $json;
	
	### Obtain data
	($err, $data) = DoorBird_BlockGet($hash, $command, $method, $header);

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Get - List_Schedules - err                  : " . $err;
	Log3 $name, 5, $name. " : DoorBird_Get - List_Schedules - data                 : " . $data;
	
	### If no error has been handed back
	if ($err eq "") {
		### If the option is  asking for the JSON string
		if (defined($option) && ($option =~ /JSON/i)) {
			return $data;		
		}
		### If the option is asking for nothing special
		else {
			### Check if json can be parsed into hash	
			eval 
			{
				$json = decode_json(encode_utf8($data));
				1;
			}
			or do 
			{
				### Log Entry for debugging purposes
				Log3 $name, 3, $name. " : DoorBird_List_Schedules - Data                    : " . $data;
				
				### Log Entry
				Log3 $name, 3, $name. " : DoorBird_Get - Data cannot be parsed by JSON for  : List_Schedules";

				return $data;
			};
			
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Get - json                               : " . $json;

			### Delete all Readings for Relay-Addresses
			fhem( "deletereading $name Schedule_.*" );
			
			### Initiate Bulk Update
			readingsBeginUpdate($hash);
			
			### For every chapter in the Array of elements
			foreach my $Schedule (@{$json}) {
	
				### Create first part of Reading
				my $ReadingNameA = "Schedule_" . $Schedule->{input} . "_";
				
				### If Parameter exists
				if ($Schedule->{param} ne "") {
					### Add Parameter
					$ReadingNameA .= $Schedule->{param} . "_";
				}

				### For every chapter in the Array of elements
				foreach my $Output (@{$Schedule->{output}}) {

					my $ReadingNameB = $ReadingNameA . $Output->{event} ."_";

	   				### If Parameter exists
					if ($Output->{param} ne "") {
						### Add Parameter
						$ReadingNameB .= $Schedule->{param} . "_";
					}
					else {
						### Add Parameter
						$ReadingNameB .= "x_";
					}
					
					
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_Get - Schedules - ReadingName            : " . $ReadingNameB;

					#					my $ReadingValue  = $Output->($Output);
					#					Log3 $name, 5, $name. " : DoorBird_Get - Schedules - ReadingValue           : " . $ReadingValue;
				}
			}
	
			### Execute Readings Bulk Update
			readingsEndUpdate($hash, 1);		
			return "Readings have been updated!\nPress F5 to refresh Browser.";
		}
	}
	### If error has been handed back
	else {
		$err =~ s/^[^ ]*//;
		return "ERROR!\nError Code:" . $err;
	}
}
####END####### Define Subfunction for LIST SCHEDULES ###########################################################END#####

###START###### Define Subfunction for RESTART #################################################################START####
sub DoorBird_Restart($$) {
	my ($hash, $option)	= @_;
	my $name			= $hash->{NAME};
	my $command			= "restart.cgi"; 
	my $method			= "GET";
	my $header			= "Accept: application/json";
	my $username 		= DoorBird_credential_decrypt($hash->{helper}{".USER"});
	my $err;
	my $data;
	my $json;

	### Activate Relay
	($err, $data) = DoorBird_BlockGet($hash, $command, $method, $header);

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Restart - err                            : " . $err;
	Log3 $name, 5, $name. " : DoorBird_Restart - data                           : " . $data;

	### If no error has been handed back
	if ($err eq "") {
		### Log Entry
		Log3 $name, 3, $name. " : DoorBird_Restart - Reboot request successfully transmitted to DoorBird";
		
		return "Reboot request successfully transmitted to DoorBird\nData: " . $data;
	}
	### If error has been handed back
	else {
		### Cut off url from error message
		$err =~ s/^[^ ]*//;

		### Log Entry
		Log3 $name, 2, $name. " : DoorBird_Restart - Reboot command failed. ErrorMsg: " . $err;

		return "ERROR!\nError Code:" . $err . "\nData: " . $data;
	}
}
####END####### Define Subfunction for RESTART ##################################################################END#####

###START###### Define Subfunction for SIP Status REQUEST ######################################################START####
sub DoorBird_SipStatus_Request($$) {
	my ($hash, $option)	= @_;
	my $name			= $hash->{NAME};
	my $command			= "sip.cgi?action=status"; 
	my $method			= "GET";
	my $header			= "Accept: application/json";
	
	my $err = " ";
	my $data = " ";
	my $json;
	
	### Obtain data
	($err, $data) = DoorBird_BlockGet($hash, $command, $method, $header);

	### Remove Newlines for better log entries
	my $ShowData = $data;
	$ShowData =~ s/[\t]//g;
	$ShowData =~ s/[\r]//g;
	$ShowData =~ s/[\n]//g;

	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_SipStatus_Req- err                       : " . $err      if(defined($err));
#	Log3 $name, 5, $name. " : DoorBird_SipStatus_Req- data                      : " . $ShowData if(defined($ShowData));
	
	### If no error has been handed back
	if ($err eq "") {
		### If the option is  asking for the JSON string
		if (defined($option) && ($option =~ /JSON/i)) {
			return $data;		
		}
		### If the option is asking for nothing special
		else {
			### Check if json can be parsed into hash	
			eval 
			{
				$json = decode_json(encode_utf8($data));
				1;
			}
			or do 
			{
				### Log Entry for debugging purposes
				Log3 $name, 3, $name. " : DoorBird_SipStatus_Req- Data cannot parsed JSON   : Info_Request";
				return $name. " : DoorBird_SipStatus_Req- Data cannot be parsed by JSON for Info_Request";
			};
			
			my $VersionContent = $json-> {BHA}{SIP}[0];
			
			### Log Entry for debugging purposes
			# Log3 $name, 5, $name. " : DoorBird_SipStatus_Req- json                      : " . Dumper($json);
			
			 ### Initiate Bulk Update
			 readingsBeginUpdate($hash);

			 foreach my $key (keys %{$VersionContent}) {

				### If the entry are information about connected INCOMING_CALL_USER
				if ( $key eq "INCOMING_CALL_USER") {

					### Split all Call User in array
					my @CallUserArray = split(";", $VersionContent -> {$key});
					
					### Log Entry for debugging purposes
					#Log3 $name, 5, $name. " : DoorBird_SipStatus_Req- CallUser                  : " . join(" ", Dumper(@CallUserArray));
					
					### Count Number of current readings containing call user 
					my $CountCurrentCallUserReadings = 0;
					foreach my  $CurrentCallUserReading (keys(%{$hash->{READINGS}})) {
						if ($CurrentCallUserReading =~ m/SIP_INCOMING_CALL_USER_/){
							$CountCurrentCallUserReadings++;
						}
					}

					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_SipStatus_Req- CurrentCallUserReadings   : " . $CountCurrentCallUserReadings;
					Log3 $name, 5, $name. " : DoorBird_SipStatus_Req- CallUserArray             : " . @CallUserArray;
					
					### If the number of call user in DoorBird unit is smaller than the number of Call user readings then delete all respective readings first
					if (@CallUserArray < $CountCurrentCallUserReadings) {
						fhem("deletereading $name SIP_INCOMING_CALL_USER_.*");
					}
					
					### For every Call-User do
					my $CallUserId;
					foreach my $CallUser (@CallUserArray) {
						
						### Increment Counter
						$CallUserId++;
						
						### Delete "sip:" if exists
						$CallUser =~ s/^[^:]*://;
					
						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_SipStatus_Req- " . sprintf("%25s %-s", "SIP_INCOMING_CALL_USER_" . sprintf("%02d",$CallUserId), ": " . "sip:" . $CallUser);

						### Update Reading
						readingsBulkUpdate($hash, "SIP_INCOMING_CALL_USER_" . sprintf("%02d",$CallUserId), "sip:" . $CallUser);
					}
				}
				### If the entry are information about connected relais
				elsif ( $key =~ m/relais:/) {
					
					### Extract number, swap to Uppercase and concat to new Readingsname
					my ($RelaisNumer) = $key =~ /(\d+)/g;

					my $NewReadingsName = uc($key);
					$NewReadingsName =~ s/:.*//;
					$NewReadingsName = "SIP_" . $NewReadingsName . "_" . sprintf("%02d",$RelaisNumer);

					### Update Reading
					readingsBulkUpdate($hash, $NewReadingsName, $VersionContent -> {$key});
					
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_SipStatus_Req- " . sprintf("%25s %-s", $key, ": " . $VersionContent -> {$key});
					Log3 $name, 5, $name. " : DoorBird_SipStatus_Req- " . sprintf("%25s %-s", "NewReadingsName", ": " . $NewReadingsName);
					Log3 $name, 5, $name. " : DoorBird_SipStatus_Req- " . sprintf("%25s %-s", "RelaisNumber",    ": " . $RelaisNumer);
				}
				### For all other entries
				else {
					
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_SipStatus_Req- " . sprintf("%25s %-s", $key, ": " . $VersionContent -> {$key});

					### Update Reading
					readingsBulkUpdate($hash, "SIP_" . $key, $VersionContent -> {$key} );
				}
			}

			### Execute Readings Bulk Update
			readingsEndUpdate($hash, 1);
			
			return "Readings have been updated!\n";
		}
	}
	### If error has been handed back
	else {
		$err =~ s/^[^ ]*//;
		return "ERROR!\nError Code:" . $err;
	}
}
####END#######  Define Subfunction for SIP Status REQUEST  #####################################################END#####


###START###### Encrypt Credential #############################################################################START####
sub DoorBird_credential_encrypt($) {
  my ($decoded) = @_;
  my $key = getUniqueId();
  my $encoded;

  return $decoded if( $decoded =~ /\Qcrypt:\E/ );

  for my $char (split //, $decoded) {
    my $encode = chop($key);
    $encoded .= sprintf("%.2x",ord($char)^ord($encode));
    $key = $encode.$key;
  }

  return 'crypt:'.$encoded;
}
####END####### Encrypt Credential ##############################################################################END#####

###START###### Decrypt Credential #############################################################################START####
sub DoorBird_credential_decrypt($) {
  my ($encoded) = @_;
  my $key = getUniqueId();
  my $decoded;

  return $encoded if( $encoded !~ /crypt:/ );
  
  $encoded = $1 if( $encoded =~ /crypt:(.*)/ );

  for my $char (map { pack('C', hex($_)) } ($encoded =~ /(..)/g)) {
    my $decode = chop($key);
    $decoded .= chr(ord($char)^ord($decode));
    $key = $decode.$key;
  }

  return $decoded;
}
####END####### Decrypt Credential ##############################################################################END#####

###START###### Blocking Get ###################################################################################START####
sub DoorBird_BlockGet($$$$) {
	### https://wiki.fhem.de/wiki/HttpUtils#HttpUtils_BlockingGet
	
	### Extract subroutine parameter from caller
	my ($hash, $ApiCom, $Method, $Header)	= @_;
	
	### Obtain values from hash
	my $name			= $hash->{NAME};
	my $username 		= DoorBird_credential_decrypt($hash->{helper}{".USER"});
	my $password		= DoorBird_credential_decrypt($hash->{helper}{".PASSWORD"});
	my $url 			= $hash->{helper}{URL};
	my $PollingTimeout  = $hash->{helper}{PollingTimeout};
	
	### Create complete command URL for DoorBird
	my $UrlPrefix 		= "https://" . $url . "/bha-api/";
	my $CommandURL 		= $UrlPrefix . $ApiCom;
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_BlockingGet - CommandURL                 : " . $CommandURL;

	my $param = {
		url               => $CommandURL,
		user              => $username,
		pwd               => $password,
		timeout           => $PollingTimeout,
		hash              => $hash,
		method            => $Method,
		header            => $Header
	};

	### Initiate communication and close
	my ($err, $data) = HttpUtils_BlockingGet($param);

	return($err, $data);
}
####END####### Blocking Get ####################################################################################END#####

###START###### Calculate relative path ########################################################################START####
sub DoorBird_Rel_Path($$) {
	my ($start,$target) = @_;
	$start 				=~ s:/[^/]+:/:;    # remove trailing filename
	my @spath 			= grep {$_ ne ''} split(/\//,$start); 
	my @tpath 			= grep {$_ ne ''} split(/\//,$target);

	# strip common start of the path
	while ( @spath && @tpath && $spath[0] eq $tpath[0]) {
		shift @spath;
		shift @tpath;
	}

	return ("../"x(@spath)).join('/', @tpath);
}
####END####### Calculate relative path #########################################################################END#####

###START###### Processing Change Log ##########################################################################START####
# Changelog parser for DoorBird changelog as of 2020-02-22 (or earlier) containing multiple product lines. 
# Returns a hash ref containing the newest version number for each product name or prefix found.
#
# Prefixes are denoted by a trailing 'x', as in the original changelog. Note:
# this means that still multiple versions matching a single product could be in the hash, 
# e. g. for different prefixes all matching the final product name.

sub DoorBird_parseChangelog($$) {
	my ($hash, $data) = @_;
	my $name = $hash->{NAME};

	my $lines = IO::String->new($data);
	my $all_versions;
	my $version;

	### Log Entry for debugging purposes
	# Log3 $name, 5, $name. " : DoorBird_parseChangelog - data                    : " . $data;


	### For all lines do
	while(my $line = <$lines>) 	{

		### If the line contains the keywords "Firmware version " followed by a number then obtain it
		if ($line =~ m/^Firmware version /) {
			( $version ) = $line =~ /(\d+)/;
		}

		### If the line contains the keywords "Products affected: " then obtain it
		elsif ($line =~ /^Products affected: (.*)$/) {

			### If version is already obtained from the changelog
			if (defined($version)) {
				
				### Split the product names into an array
				my @products = split(/,\s*/, $1);

				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_parseChangelog - found product           : " . $version;

				### For each product name mentioned in the changelog
				foreach my $product (@products) {
					### Apparently the line of the "Products affected" in current changelog file is not closed with an \r so we ignore this array - entry
					next if $product =~ /Preceding version: /;
					
					### If the Product version for the firmware ha snot yet been defined or the already obtaine version number is older than the current value
					if (!defined($all_versions->{$product}) or 0 + $all_versions->{$product} < 0 + $version) {
						
						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_parseChangelog - found firmware version  : " . $version . " for " . $product;
						
						### Save latest firmware version
						$all_versions->{$product} = $version;
					}
				}
				undef $version;
			}
			### If version cannot be found
			else {
				### Log Entry for debugging purposes
				Log3 $name, 3, $name. " : DoorBird_parseChangelog - Products without version found in changelog, ignored.";
			}
		}
	}
	return $all_versions;
}

# Find newest firmware version for this device by name or prefix.
# The versions hash ref expected as second argument should match the format returned from DoorBird_parseChangelog().
sub DoorBird_findNewestFWVersion($$$) {
	my ($hash, $versions, $product_name) = @_;
	my $name	 = $hash->{NAME};
	my $newest = 0;

	### For all version entries
	foreach my $product (sort keys %$versions)
	{
		### Optional prefix matching
		my $prefix = $product;
		$prefix =~ s/x$//;

		### If the installed product name is (partial) identical with the product name given in the changelog file entry
		if (length($prefix) <= length($product_name) and $prefix eq substr($product_name, 0, length($prefix)) and 0 + $newest < 0 + $versions->{$product}) {
			$newest = $versions->{$product};
		}
	}

	return $newest;
}
####END####### Processing Change Log ###########################################################################END#####

###START###### Limit File Space ###############################################################################START####
sub DoorBird_FileSpace($$$$) {
	my ($hash, $FileDir, $FileExt, $FileDirMaxSize) = @_;
	my $name	                   = $hash->{NAME};	

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_FileSpace - __________________________________________________________";
	Log3 $name, 5, $name. " : DoorBird_FileSpace - FileDir                      : " . $FileDir;
	Log3 $name, 5, $name. " : DoorBird_FileSpace - FileExt                      : " . $FileExt;
	Log3 $name, 5, $name. " : DoorBird_FileSpace - FileDirMaxSize               : " . $FileDirMaxSize . " MByte";

	my $SizeOfFiles = 0;
	my @FileList;
	opendir( my $dh, $FileDir )	or die "Cannot opendir '$FileDir': $!\n";

	### Search for files of specified extension (FileExt) in specified directory (FileDir)
	for my $i ( readdir( $dh ) ) {
		if ($i =~ m/$FileExt/) {
			
			push(@FileList, $FileDir . $i);
			my $s = -s $FileDir . $i;
			
			$SizeOfFiles += $s;
			$SizeOfFiles += getdirsize( $FileDir . $i ) if -d $FileDir . $i && $i !~ /^\.\.?$/;
		}
	}
	
	### Sort list of files by name => timestamp
	@FileList = sort(@FileList);
	
	### Log Entry for debugging purposes
	#Log3 $name, 5, $name. " : DoorBird_FileSpace - FileList sorted              : \n" . Dumper(@FileList);	
	
	### Transform Byte in MByte
	$SizeOfFiles = int($SizeOfFiles / 1024 / 1024);

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_FileSpace - Dirsize                      : " . $SizeOfFiles . " MByte";

	if ($SizeOfFiles > $FileDirMaxSize) {

		### Calculate Delta Volume to be deleted
		my $DeltaVol = $SizeOfFiles - $FileDirMaxSize;
		
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_FileSpace - MaxDirSize exceeded       dV : " . $DeltaVol . " MByte";

		my $CountVol = 0;
		my @FileListToBeDeleted;
		
		### If there are files available at all which could be deleted
		if (@FileList > 0) {
			my $i = 0;		
			
			### As long their need more files to be deleted
			while (($CountVol / 1024 / 1024) < $DeltaVol) {
				
				### Add to the list of deleted files
				push (@FileListToBeDeleted, $FileList[$i]);
				
				### Sum up the volume freed if file is deleted
				$CountVol += -s $FileList[$i];

				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_FileSpace - CountVol collected so far    : " . int($CountVol/1024/1024) . " MByte";

				$i++
			}

			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_FileSpace - FileListToBeDeleted          : \n" . Dumper(@FileListToBeDeleted);
		}

		### Delete oldestFile
		my $NoOfDeletedFiles = unlink @FileListToBeDeleted;
	
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_FileSpace - NumberOfDeletedFiles         : " . $NoOfDeletedFiles;
	}

	### Close directory
	closedir( $dh );
}
####END####### Limit File Space ################################################################################END#####

1;

###START###### Description for fhem commandref ################################################################START####
=pod
=encoding utf8
=item device
=item summary    Connects fhem to the DoorBird IP door station
=item summary_DE Verbindet fhem mit der DoorBird IP T&uuml;rstation
=begin html

<a id="DoorBird"></a>
<h3>DoorBird</h3>
<ul>
	<table>
		<tr>
			<td>
				The DoorBird module establishes the communication between the DoorBird - door intercommunication unit and the fhem home automation based on the official API, published by the manufacturer.<BR>
				Please make sure, that the user has been enabled the API-Operator button in the DoorBird Android/iPhone APP under "Administration -> User -> Edit -> Permission -> API-Operator".
				The following packet - installations are pre-requisite if not already installed by other modules (Examples below tested on Raspbian):<BR>
				<BR>
				<code>
					<li>sudo apt  install sox						</li>
					<li>sudo apt  install libsox-fmt-all			</li>
					<li>sudo apt  install libsodium-dev				</li>
					<li>sudo apt  install gstreamer1.0-tools    	</li>
					<li>sudo cpan install Crypt::Argon2				</li>
					<li>sudo cpan install Sodium::FFI				</li>
					<li>sudo cpan install IO::String module			</li>
					<li>sudo cpan install IO::Socket				</li>
				</code>
			</td>
		</tr>
	</table>
	<BR>
	<table>
		<tr><td><a id="DoorBird-define"></a><b>Define</b></td></tr>
		<tr><td><ul><code>define &lt;name&gt; DoorBird &lt;IPv4-address&gt; &lt;Username&gt; &lt;Password&gt;</code>																																					                                                                                                                                                                                              <BR>          </ul></td></tr>
		<tr><td><ul><ul><code>&lt;name&gt;                </code> : The name of the device. Recommendation: "myDoorBird".																																					                                                                                                                                                                                          <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><code>&lt;IPv4-address&gt;        </code> : A valid IPv4 address of the KMxxx. You might look into your router which DHCP address has been given to the DoorBird unit.																																					                                                                                                                      <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><code>&lt;Username&gt;            </code> : The username which is required to sign on the DoorBird.																																					                                                                                                                                                                                          <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><code>&lt;Password&gt;            </code> : The password which is required to sign on the DoorBird.																																					                                                                                                                                                                                          <BR>     </ul></ul></td></tr>
	</table>                                                                                                                                                                                                                                                                                                                                                                                                                                                   
	<BR>                                                                                                                                                                                                                                                                                                                                                                                                                                                       
	<table>                                                                                                                                                                                                                                                                                                                                                                                                                                                    
		<tr><td><a id="DoorBird-set"></a><b>Set</b></td></tr>                                                                                                                                                                                                                                                                                                                                                                                                  
		<tr><td><ul>The set function is able to change or activate the following features as follows:                                                                                                                                                                                                                                                                                                                                                                 <BR>     </ul>     </td></tr>
		<tr><td><ul><a id="DoorBird-set-Light_On"                                                     ></a><li><b><u><code>set Light_On                          </code></u></b> : Activates the IR lights of the DoorBird unit. The IR - light deactivates automatically by the default time within the Doorbird unit																			                                                                                                              <BR></li></ul>     </td></tr>
		<tr><td><ul><a id="DoorBird-set-Live_Audio"                                                   ></a><li><b><u><code>set Live_Audio &lt;on:off&gt;         </code></u></b> : Activate/Deactivate the Live Audio Stream of the DoorBird on or off and toggles the direct link in the <b>hidden</b> Reading <code>.AudioURL</code>															                                                                                                              <BR></li></ul>     </td></tr>
		<tr><td><ul><a id="DoorBird-set-Live_Video"                                                   ></a><li><b><u><code>set Live_Video &lt;on:off&gt;         </code></u></b> : Activate/Deactivate the Live Video Stream of the DoorBird on or off and toggles the direct link in the <b>hidden</b> Reading <code>.VideoURL</code>															                                                                                                              <BR></li></ul>     </td></tr>
		<tr><td><ul><a id="DoorBird-set-Open_Door"                                                    ></a><li><b><u><code>set Open_Door &lt;Value&gt;           </code></u></b> : Activates the Relay of the DoorBird unit with the given address. The list of installed relay addresses are imported with the initialization of parameters.													                                                                                                              <BR></li></ul>     </td></tr>
		<tr><td><ul><a id="DoorBird-set-OpsMode.*DoorbellAudio" data-pattern="OpsMode.*DoorbellAudio" ></a><li><b><u><code>set OpsMode&lt;Value&gt;DoorbellAudio </code></u></b> : A selection of the audio files stored in the directory which is defined in the attribute "AudioFileDir".	This file will be converted and send to the DoorBird to be played in case of doorbell activation.												                                                                  <BR></li></ul>     </td></tr>
		<tr><td><ul><a id="DoorBird-set-OpsMode.*DoorbellRelay" data-pattern="OpsMode.*DoorbellRelay" ></a><li><b><u><code>set OpsMode&lt;Value&gt;DoorbellRelay </code></u></b> : A selection of the installed relays which shall be activated in case of doorbell activation.                                                                                                                                                                                                                                <BR></li></ul>     </td></tr>
		<tr><td><ul><a id="DoorBird-set-OpsMode.*MotionAudio"   data-pattern="OpsMode.*MotionAudio"   ></a><li><b><u><code>set OpsMode&lt;Value&gt;MotionAudio   </code></u></b> : A selection of the audio files stored in the directory which is defined in the attribute "AudioFileDir".	This file will be converted and send to the DoorBird to be played in case of motion sensor triggering.												                                                              <BR></li></ul>     </td></tr>
		<tr><td><ul><a id="DoorBird-set-OpsMode.*MotionRelay"   data-pattern="OpsMode.*MotionRelay"   ></a><li><b><u><code>set OpsMode&lt;Value&gt;MotionRelay   </code></u></b> : A selection of the installed relays which shall be activated in case of motion sensor triggering.                                                                                                                                                                                                                           <BR></li></ul>     </td></tr>
		<tr><td><ul><a id="DoorBird-set-Receive_Audio"                                                ></a><li><b><u><code>set Receive_Audio &lt;Path&gt;        </code></u></b> : Receives an audio file and saves it. Requires a datapath to audio file to be saved. The user "fhem" needs to have write access to this directory.   	                                                                                                                                                                      <BR></li></ul>     </td></tr>
		<tr><td><ul><a id="DoorBird-set-Restart"                                                      ></a><li><b><u><code>set Restart                           </code></u></b> : Sends the command to restart (reboot) the Doorbird unit																																						                                                                                                              <BR></li></ul>     </td></tr>
		<tr><td><ul><a id="DoorBird-set-Transmit_Audio"                                               ></a><li><b><u><code>set Transmit_Audio &lt;Path&gt;       </code></u></b> : Converts a given audio file and transmits the stream to the DoorBird speaker. Requires a datapath to audio file to be converted and send. The user "fhem" needs to have write access to this directory.   	                                                                                                              <BR></li></ul>     </td></tr>
	</table>                                                                                                                                                                                                                                                                                                                                                                                                                                                       
	<BR>                                                                                                                                                                                                                                                                                                                                                                                                                                                           
	<table>                                                                                                                                                                                                                                                                                                                                                                                                                                                        
		<tr><td><a id="DoorBird-get"></a><b>Get</b></td></tr>                                                                                                                                                                                                                                                                                                                                                                                                     
		<tr><td><ul>The get function is able to obtain the following information from the DoorBird unit:<BR></ul></td></tr>                                                                                                                                                                                                                                                                                                                                            
		<tr><td><ul><a id="DoorBird-get-History_Request"                                              ></a><li><b><u><code>get History_Request                   </code></u></b> : Downloads the pictures of the last events of the doorbell and motion sensor. (Refer to attribute <code>MaxHistory</code>)																					                                                                                                                  <BR></li></ul>     </td></tr>
		<tr><td><ul><a id="DoorBird-get-Image_Request"                                                ></a><li><b><u><code>get Image_Request                     </code></u></b> : Downloads the current Image of the camera of DoorBird unit.																																					                                                                                                              <BR></li></ul>     </td></tr>
		<tr><td><ul><a id="DoorBird-get-Video_Request"                                                ></a><li><b><u><code>get Video_Request &lt;Value&gt;       </code></u></b> : Downloads the current Video of the camera of DoorBird unit for the time in seconds given.																													                                                                                                                  <BR></li></ul>     </td></tr>
		<tr><td><ul><a id="DoorBird-get-Info_Request"                                                 ></a><li><b><u><code>get Info_Request                      </code></u></b> : Downloads the current internal setup such as relay configuration, firmware version etc. of the DoorBird unit. The obtained relay adresses will be used as options for the <code>Open_Door</code> command.	                                                                                                                  <BR></li></ul>     </td></tr>
	</table>	<BR><table>
		<tr><td><a id="DoorBird-attr"></a><b>Attributes</b></td></tr>
		<tr><td><ul>The following user attributes can be used with the DoorBird module in addition to the global ones e.g. <a href="#room">room</a>.<BR></ul></td></tr>
	</table>
	<table>
		<tr><td><ul><ul><a id="DoorBird-attr-disable"                                                 ></a><li><b><u><code>disable                              </code></u></b> : Stops the device from further reacting on UDP datagrams sent by the DoorBird unit.<BR>The default value is 0 = activated                                                                                                                                                                                                   <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-KeepAliveTimeout"                                        ></a><li><b><u><code>KeepAliveTimeout                     </code></u></b> : Timeout in seconds without still-alive UDP datagrams before state of device will be set to "disconnected".<BR>The default value is 30s                                                                                                                                                                                     <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-MaxHistory"                                              ></a><li><b><u><code>MaxHistory                           </code></u></b> : Number of pictures to be downloaded from history for both - doorbell and motion sensor events.<BR>The default value is "50" which is the maximum possible.                                                                                                                                                                 <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-PollingTimeout"                                          ></a><li><b><u><code>PollingTimeout                       </code></u></b> : Timeout in seconds before download requests are terminated in cause of no reaction by DoorBird unit. Might be required to be adjusted due to network speed.<BR>The default value is 10s.                                                                                                                                   <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-UdpPort"                                                 ></a><li><b><u><code>UdpPort                              </code></u></b> : Port number to be used to receice UDP datagrams. Ports are pre-defined by firmware.<BR>The default value is port 6524                                                                                                                                                                                                      <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-SessionIdSec"                                            ></a><li><b><u><code>SessionIdSec                         </code></u></b> : Time in seconds for how long the session Id shall be valid, which is required for secure Video and Audio transmission. The DoorBird kills the session Id after 10min = 600s automatically. In case of use with CCTV recording units, this function must be disabled by setting to 0.<BR>The default value is 540s = 9min.  <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-AudioFileDir"                                            ></a><li><b><u><code>AudioFileDir                         </code></u></b> : The relative (e.g. "audio") or absolute (e.g. "/mnt/NAS/audio") with or without trailing "/" directory path to which the audio files supposed to be stored.<BR>The default value is <code>""</code> = disabled                                                                                                             <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-AudioFileDirMaxSize"                                     ></a><li><b><u><code>AudioFileDirmaxSize                  </code></u></b> : The maximum size of the AudioFileDir in Megabyte [MB]. If the maximum Size has been reached with audio files, the oldest files are deleted automatically<BR>The default value is <code>50</code> = 50MB                                                                                                                    <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-ImageFileDir"                                            ></a><li><b><u><code>ImageFileDir                         </code></u></b> : The relative (e.g. "images") or absolute (e.g. "/mnt/NAS/images") with or without trailing "/" directory path to which the image files supposed to be stored.<BR>The default value is <code>""</code> = disabled                                                                                                           <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-ImageFileDirMaxSize"                                     ></a><li><b><u><code>ImageFileDirmaxSize                  </code></u></b> : The maximum size of the ImageFileDir in Megabyte [MB]. If the maximum Size has been reached with Image files, the oldest files are deleted automatically<BR>The default value is <code>50</code> = 50MB                                                                                                                    <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-VideoFileDir"                                            ></a><li><b><u><code>VideoFileDir                         </code></u></b> : The relative (e.g. "images") or absolute (e.g. "/mnt/NAS/images") with or without trailing "/" directory path to which the video files supposed to be stored.<BR>The default value is <code>""</code> = disabled                                                                                                           <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-VideoFileDirMaxSize"                                     ></a><li><b><u><code>VideoFileDirmaxSize                  </code></u></b> : The maximum size of the VideoFileDir in Megabyte [MB]. If the maximum Size has been reached with Video files, the oldest files are deleted automatically<BR>The default value is <code>50</code> = 50MB                                                                                                                    <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-VideoFileFormat"                                         ></a><li><b><u><code>VideoFileFormat                      </code></u></b> : The file format for the video file to be stored<BR>The default value is <code>"mpeg"</code>                                                                                                                                                                                                                                <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-VideoDurationDoorbell"                                   ></a><li><b><u><code>VideoDurationDoorbell                </code></u></b> : Time in seconds for how long the video shall be recorded in case of an doorbbell event.<BR>The default value is <code>0</code> = disabled                                                                                                                                                                                  <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-VideoDurationMotion"                                     ></a><li><b><u><code>VideoDurationMotion                  </code></u></b> : Time in seconds for how long the video shall be recorded in case of an motion sensor event.<BR>The default value is <code>0</code> = disabled                                                                                                                                                                              <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-EventReset"                                              ></a><li><b><u><code>EventReset                           </code></u></b> : Time in seconds after wich the Readings for the Events Events (e.g. "doorbell_button", "motions sensor", "keypad") shal be reset to "idle".<BR>The default value is 5s                                                                                                                                                     <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-WaitForHistory"                                          ></a><li><b><u><code>WaitForHistory                       </code></u></b> : Time in seconds after wich the module shall wait for an history image triggered by an event is ready for download. Might be adjusted if fhem-Server and Doorbird unit have large differences in system time.<BR>The default value is 7s                                                                                    <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-OpsModeList"                                             ></a><li><b><u><code>OpsModeList                          </code></u></b> : A space separated list of names for operational modes (e.g. "Normal Party Fire") on which the DoorBird reacts automatically on events.<BR>The default value is <code>""</code> = disabled                                                                                                                                  <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-HistoryFilePath"                                         ></a><li><b><u><code>HistoryFilePath                      </code></u></b> : Creates relative datapaths to the last pictures, and videos in order to indicate them directly (e.g. fhem ftui widget "image")<BR>The default value is <code>"0"</code> = disabled                                                                                                                                         <BR></li></ul></ul></td></tr>
	</table>
</ul>
=end html
=begin html_DE

<a id="DoorBird"></a>
<h3>DoorBird</h3>
<ul>
	<table>
		<tr>
			<td>
				Das DoorBird Modul erm&ouml;glicht die Komminikation zwischen der DoorBird Interkommunikationseinheit und dem fhem Automationssystem basierend auf der API des Herstellers her.<BR>
				Für den vollen Funktionsumfang muss sichergestellt werden, dass das Setting "API-Operator" in der DoorBird Android/iPhone - APP unter "Administration -> User -> Edit -> Permission -> API-Operator" gesetzt ist.
				Die folgenden Software - Pakete m&uuml;ssen noch zus&auml;tzlich installiert werden, sofern dies nicht schon durch andere Module erfolgt ist. (Die Beispiele sind auf dem Raspberry JESSIE gestestet):<BR>
				<BR>
				<code>
					<li>sudo apt  install sox						</li>
					<li>sudo apt  install libsox-fmt-all			</li>
					<li>sudo apt  install libsodium-dev				</li>
					<li>sudo apt  install gstreamer1.0-tools    	</li>
					<li>sudo cpan install Crypt::Argon2				</li>
					<li>sudo cpan install Sodium::FFI				</li>
					<li>sudo cpan install IO::String module			</li>
					<li>sudo cpan install IO::Socket				</li>

				</code>
			</td>
		</tr>
	</table>
	<BR>
	<table>
		<tr><td><a id="DoorBird-define"></a><b>Define</b></td></tr>

		<tr><td><ul><code>define &lt;name&gt; DoorBird &lt;IPv4-address&gt; &lt;Username&gt; &lt;Passwort&gt;</code>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    <BR>          </ul></td></tr>
		<tr><td><ul><ul><code>&lt;name&gt;           </code> : </td><td>Der Name des Device unter fhem. Beispiel: "myDoorBird".																												                                                                                                                                                                                                                                                                                                                                                                                                            <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><code>&lt;IPv4-Addresse&gt;  </code> : </td><td>Eine g&uuml;ltige IPv4 - Addresse der DoorBird-Anlage. Ggf. muss man im Router nach der entsprechenden DHCP Addresse suchen, die der DoorBird Anlage vergeben wurde.                                                                                                                                                                                                                                                                                                                                                                                                            <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><code>&lt;Username&gt;       </code> : </td><td>Der Username zum einloggen auf der DoorBird Anlage.																													                                                                                                                                                                                                                                                                                                                                                                                                            <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><code>&lt;Passwort&gt;       </code> : </td><td>Das Passwort zum einloggen auf der DoorBird Anlage.																													                                                                                                                                                                                                                                                                                                                                                                                                            <BR>     </ul></ul></td></tr>
	</table>
	<BR>
	<table>
		<tr><td><a id="DoorBird-set"></a><b>Set</b></td></tr>
		<tr><td><ul>Die Set - Funktion ist in der lage auf der DoorBird - Anlage die folgenden Einstellungen vorzunehmen bzw. zu de-/aktivieren:                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        <BR>          </ul></td></tr>
		<tr><td><ul><a id="DoorBird-set-Light_On"                                                     ></a><li><b><u><code>set Light_On                          </code></u></b> : Schaltet das IR lichht der DoorBird Anlage ein. Das IR Licht schaltet sich automatisch nach der in der DoorBird - Anlage vorgegebenen Default Zeit wieder aus.															                                                                                                                                                                                                                                            <BR></li>     </ul></td></tr>
		<tr><td><ul><a id="DoorBird-set-Live_Audio"                                                   ></a><li><b><u><code>set Live_Audio &lt;on:off&gt;         </code></u></b> : Aktiviert/Deaktiviert den Live Audio Stream der DoorBird - Anlage Ein oder Aus und wechselt den direkten link in dem <b>versteckten</b> Reading <code>.AudioURL.</code>													                                                                                                                                                                                                                                            <BR></li>     </ul></td></tr>
		<tr><td><ul><a id="DoorBird-set-Live_Video"                                                   ></a><li><b><u><code>set Live_Video &lt;on:off&gt;         </code></u></b> : Aktiviert/Deaktiviert den Live Video Stream der DoorBird - Anlage Ein oder Aus und wechselt den direkten link in dem <b>versteckten</b> Reading <code>.VideoURL.</code>													                                                                                                                                                                                                                                            <BR></li>     </ul></td></tr>
		<tr><td><ul><a id="DoorBird-set-Open_Door"                                                    ></a><li><b><u><code>set Open_Door &lt;Value&gt;           </code></u></b> : Aktiviert das Relais der DoorBird - Anlage mit dessen Adresse. Die Liste der installierten Relais werden mit der Initialisierung der Parameter importiert.																                                                                                                                                                                                                                                            <BR></li>     </ul></td></tr>
		<tr><td><ul><a id="DoorBird-set-OpsMode.*DoorbellAudio" data-pattern="OpsMode.*DoorbellAudio" ></a><li><b><u><code>set OpsMode&lt;Value&gt;DoorbellAudio </code></u></b> : Eine Auswahl der Audio Dateien die im Unterverzeichnis abgelegt sind welches durch das Attribut "AudioFileDir" definert ist.	Diese Datei wird entsprechend konvertiert und an den DoorBird gesendet und im abgespielt sobald die Klingeltaste bet&auml;tigt wird.												                                                                                                                                                    <BR></li></ul>     </td></tr>
		<tr><td><ul><a id="DoorBird-set-OpsMode.*DoorbellRelay" data-pattern="OpsMode.*DoorbellRelay" ></a><li><b><u><code>set OpsMode&lt;Value&gt;DoorbellRelay </code></u></b> : Eine Auswahl der installierten Relays die aktiviert weerden, sobald die Klingeltaste bet&auml;tigt wird.												                                                                                                                                                    												                                                                                                            <BR></li></ul>     </td></tr>
		<tr><td><ul><a id="DoorBird-set-OpsMode.*MotionAudio"   data-pattern="OpsMode.*MotionAudio"   ></a><li><b><u><code>set OpsMode&lt;Value&gt;MotionAudio   </code></u></b> : Wine Auswahl der Audio Dateien die im Unterverzeichnis abgelegt sind welches durch das Attribut "AudioFileDir" definert ist.	Diese Datei wird entsprechend konvertiert und an den DoorBird gesendet und im abgespielt sobald der Bewegungssensor getriggert wird.                                                                                                                                                                                                    <BR></li></ul>     </td></tr>
		<tr><td><ul><a id="DoorBird-set-OpsMode.*MotionRelay"   data-pattern="OpsMode.*MotionRelay"   ></a><li><b><u><code>set OpsMode&lt;Value&gt;MotionRelay   </code></u></b> : Eine Auswahl der installierten Relays die aktiviert weerden, sobald der Bewegungssensor getriggert wird.												                                                                                                                                                    												                                                                                                            <BR></li></ul>     </td></tr>
		<tr><td><ul><a id="DoorBird-set-Receive_Audio"                                                ></a><li><b><u><code>set Receive_Audio &lt;Path&gt;        </code></u></b> : Empf&auml;ngt eine Audio-Datei und speichert diese. Es ben&ouml;tigt einen Dateipfad zu der Audio-Datei zu dem der User "fhem" Schreibrechte braucht (z.B.: /opt/fhem/audio).	                                                                                                                                                                                                                                                                                    <BR></li>     </ul></td></tr>
		<tr><td><ul><a id="DoorBird-set-Restart"                                                      ></a><li><b><u><code>set Restart                           </code></u></b> : Sendet das Kommando zum rebooten der DoorBird - Anlage.																																									                                                                                                                                                                                                                                            <BR></li>     </ul></td></tr>
		<tr><td><ul><a id="DoorBird-set-Transmit_Audio"                                               ></a><li><b><u><code>set Transmit_Audio &lt;Path&gt;       </code></u></b> : Konvertiert die angegebene Audio-Datei und sendet diese zur Ausgabe an die DoorBird - Anlage. Es ben&ouml;tigt einen Dateipfad zu der Audio-Datei zu dem der User "fhem" Schreibrechte braucht (z.B.: /opt/fhem/audio).	                                                                                                                                                                                                                                            <BR></li>     </ul></td></tr>
	</table>
	<BR>
	<table>
		<tr><td><a id="DoorBird-get"></a><b>Get</b></td></tr>
		<tr><td><ul>Die Get - Funktion ist in der lage von der DoorBird - Anlage die folgenden Informationen und Daten zu laden:                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        <BR>          </ul></td></tr>
		<tr><td><ul><a id="DoorBird-get-History_Request"                                              ></a><li><b><u><code>get History_Request                   </code></u></b> : L&auml;dt die Bilder der letzten Ereignisse durch die T&uuml;rklingel und dem Bewegungssensor herunter. (Siehe auch Attribut <code>MaxHistory</code>)                                                                                                                                                                                                                                                                                                                <BR></li>     </ul></td></tr>
		<tr><td><ul><a id="DoorBird-get-Image_Request"                                                ></a><li><b><u><code>get Image_Request                     </code></u></b> : L&auml;dt das gegenw&auml;rtige Bild der DoorBird - Kamera herunter.                                                                                                                                                                                                                                                                                                                                                                                                 <BR></li>     </ul></td></tr>
		<tr><td><ul><a id="DoorBird-get-Video_Request"                                                ></a><li><b><u><code>get Video_Request &lt;Value&gt;       </code></u></b> : L&auml;dt das gegenw&auml;rtige Video der DoorBird - Kamera f&uumlr die gegebene Zeit in Sekunden herunter.                                                                                                                                                                                                                                                                                                                                                          <BR></li>     </ul></td></tr>
		<tr><td><ul><a id="DoorBird-get-Info_Request"                                                 ></a><li><b><u><code>get Info_Request                      </code></u></b> : L&auml;dt das interne Setup (Firmware Version, Relais Konfiguration etc.) herunter. Die &uuml;bermittelten Relais-Adressen werden als Option f&uuml;r das Kommando <code>Open_Door</code> verwendet.                                                                                                                                                                                                                                                                 <BR></li>     </ul></td></tr>
	</table>
	<BR>
	<table>
		<tr><td><a id="DoorBird-attr"></a><b>Attributes</b></td></tr>
		<tr><td><ul>Die folgenden Attribute k&ouml;nnen mit dem DoorBird Module neben den globalen Attributen wie <a href="#room">room</a> verwednet werden.<BR></ul></td></tr>
	</table>
	<table>
		<tr><td><ul><ul><a id="DoorBird-attr-disable"                                                 ></a><li><b><u><code>disable                               </code></u></b> : Stoppt das Ger&auml;t von weiteren Reaktionen auf die von der DoorBird ß Anlage ausgesendeten UDP - Datageramme<BR>Der Default Wert ist 0 = aktiviert                                                                                                                                                                                                                                                                                                                <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-KeepAliveTimeout"                                        ></a><li><b><u><code>KeepAliveTimeout                      </code></u></b> : Timeout in Sekunden ohne "still-alive" - UDP Datagramme bevor der Status des Ger&auml;tes auf  "disconnected" gesetzt wird.<BR>Der Default Wert ist 30s                                                                                                                                                                                                                                                                                                              <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-MaxHistory"                                              ></a><li><b><u><code>MaxHistory                            </code></u></b> : Anzahl der herunterzuladenden Bilder aus dem Historien-Archiv sowohl f&uuml;r Ereignisse seitens der T&uuml;rklingel als auch f&uuml;r den Bewegungssensor.<BR>Der Default Wert ist "50" = Maximum.                                                                                                                                                                                                                                                                  <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-PollingTimeout"                                          ></a><li><b><u><code>PollingTimeout                        </code></u></b> : Timeout in Sekunden before der Download-Versuch aufgrund fehlender Antwort seitens der DoorBird-Anlage terminiert wird. Eine Adjustierung mag notwendig sein, sobald Netzwerk-Latenzen aufteten.<BR>Der Default-Wert ist 10s.                                                                                                                                                                                                                                        <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-UdpPort"                                                 ></a><li><b><u><code>UdpPort                               </code></u></b> : Port Nummer auf welcher das DoorBird - Modul nach den UDP Datagrammen der DoorBird - Anlage h&ouml;ren soll. Die Ports sind von der Firmware vorgegeben.<BR>Der Default Port ist 6524                                                                                                                                                                                                                                                                                <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-SessionIdSec"                                            ></a><li><b><u><code>SessionIdSec                          </code></u></b> : Zeit in Sekunden nach welcher die Session Id erneuert werden soll. Diese ist f&uuml;r die sichere &Uuml;bertragung der Video und Audio Verbindungsdaten notwendig. Die DoorBird-Unit devalidiert die Session Id automatisch nach 10min. F&uuml;r den Fall, dass die DoorBird Kamera an ein &Uuml;berwachungssystem angebunden werden soll, muss diese Funktion ausser Betrieb genommen werden indem man den Wert auf 0 setzt 0.<BR>Der Default Wert ist 540s = 9min. <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-AudioFileDir"                                            ></a><li><b><u><code>AudioFileDir                          </code></u></b> : Der relative (z.B. "audio") oder absolute (z.B. "/mnt/NAS/audio") Verzeichnispfad mit oder ohne nachfolgendem Pfadzeichen "/"  in welchen die Audio-Dateien abgelegt sind.<BR>Der Default Wert ist <code>""</code> = deaktiviert                                                                                                                                                                                                                                     <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-AudioFileDirMaxSize"                                     ></a><li><b><u><code>AudioFileDirMaxSize                   </code></u></b> : Die maximale Gr&ouml;&szlig;e des Unterverzeichnisses f&uuml;r die Audio-Dateien in Megabyte (MB). Beim Erreichen dieses Wertes, werden die &auml;ltesten Dateien automatisch gel&ouml;scht.<BR>Der Default Wert ist <code>50</code> = 50MB                                                                                                                                                                                                                          <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-ImageFileDir"                                            ></a><li><b><u><code>ImageFileDir                          </code></u></b> : Der relative (z.B. "images") oderr absolute (z.B. "/mnt/NAS/images") Verzeichnispfad mit oder ohne nachfolgendem Pfadzeichen "/"  in welchen die Video-Dateien gespeichert werden sollen.<BR>Der Default Wert ist <code>""</code> = deaktiviert                                                                                                                                                                                                                      <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-ImageFileDirMaxSize"                                     ></a><li><b><u><code>ImageFileDirMaxSize                   </code></u></b> : Die maximale Gr&ouml;&szlig;e des Unterverzeichnisses f&uuml;r die Image-Dateien in Megabyte (MB). Beim Erreichen dieses Wertes, werden die &auml;ltesten Dateien automatisch gel&ouml;scht.<BR>Der Default Wert ist <code>50</code> = 50MB                                                                                                                                                                                                                          <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-VideoFileDir"                                            ></a><li><b><u><code>VideoFileDir                          </code></u></b> : Der relative (z.B. "images") oder absolute (z.B. "/mnt/NAS/images") Verzeichnispfad mit oder ohne nachfolgendem Pfadzeichen "/"  in welchen die Bild-Dateien gespeichert werden sollen.<BR>Der Default Wert ist <code>""</code> = deaktiviert                                                                                                                                                                                                                        <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-VideoFileDirMaxSize"                                     ></a><li><b><u><code>VideoFileDirMaxSize                   </code></u></b> : Die maximale Gr&ouml;&szlig;e des Unterverzeichnisses f&uuml;r die Video-Dateien in Megabyte (MB). Beim Erreichen dieses Wertes, werden die &auml;ltesten Dateien automatisch gel&ouml;scht.<BR>Der Default Wert ist <code>50</code> = 50MB                                                                                                                                                                                                                          <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-VideoFileFormat"                                         ></a><li><b><u><code>VideoFileFormat                       </code></u></b> : Das Dateiformat f&uuml;r die Videodatei<BR>Der Default Wert ist <code>"mpeg"</code>                                                                                                                                                                                                                                                                                                                                                                                  <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-VideoDurationDoorbell"                                   ></a><li><b><u><code>VideoDurationDoorbell                 </code></u></b> : Zeit in Sekunden für wie lange das Video im Falle eines Klingel Events aufgenommen werden soll.<BR>Der Default Wert ist <code>0</code> = deaktiviert                                                                                                                                                                                                                                                                                                                 <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-VideoDurationMotion"                                     ></a><li><b><u><code>VideoDurationMotion                   </code></u></b> : Zeit in Sekunden für wie lange das Video im Falle eines Bewegungssensor Events aufgenommen werden soll.<BR>Der Default Wert ist <code>0</code> = deaktiviert                                                                                                                                                                                                                                                                                                         <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-EventReset"                                              ></a><li><b><u><code>EventReset                            </code></u></b> : Zeit in Sekunden nach welcher die Readings f&uuml;r die Events (z.B. "doorbell_button", "motions sensor", "keypad")wieder auf "idle" gesetzt werden sollen.<BR>Der Default Wert ist 5s                                                                                                                                                                                                                                                                               <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-WaitForHistory"                                          ></a><li><b><u><code>WaitForHistory                        </code></u></b> : Zeit in Sekunden die das Modul auf das Bereitstellen eines korrespondierenden History Bildes zu einem Event warten soll. Muss ggf. adjustiert werden, sobald deutliche Unterschiede in der Systemzeit zwischen fhemßServer und DoorBird Station vorliegen.<BR>Der Default Wert ist 7s                                                                                                                                                                                <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-OpsModeList"                                             ></a><li><b><u><code>OpsModeList                           </code></u></b> : Eine durch Leerzeichen getrennte Liste von Namen für Operationszust&auml;nde (e.g. "Normal Party Feuer" auf diese der DoorBird automatisch bei Events reagiert.<BR>Der Default Wert ist "" = deaktiviert                                                                                                                                                                                                                                                             <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DoorBird-attr-HistoryFilePath"                                         ></a><li><b><u><code>HistoryFilePath                       </code></u></b> : Erstellt Dateipfade zu den letzten Bildern und Videos um sie in den User Interfaces direkt anzuzeigen (e.g. fhem ftui Widget "Image")<BR>Der Default Wert ist <code>"0"</code> = disabled                                                                                                                                                                                                                                                                            <BR></li></ul></ul></td></tr>
	</table>
</ul>
=end html_DE
=for :application/json;q=META.json 73_DoorBird.pm
{
	"abstract"                       : "Connects fhem to the DoorBird IP door station",
	"description"                    : "The DoorBird module establishes the communication between the DoorBird - door intercommunication unit and the fhem home automation based on the official API, published by the manufacturer. Please make sure, that the user has been enabled the API-Operator button in the DoorBird Android/iPhone APP under Administration -> User -> Edit -> Permission -> API-Operator.",
    "version"                        : "2.00",
	"name"                           : "73_DoorBird.pm",
	"meta-spec": {
		"version"                    : "2",
		"url"                        : "http://search.cpan.org/perldoc?CPAN::Meta::Spec"
	},	
	"x_lang": {
		"de": {
			"abstract"               : "Verbindet fhem mit der DoorBird IP Türstation",
			"description"            : "Das DoorBird Modul ermöglicht die Komminikation zwischen der DoorBird Interkommunikationseinheit und dem fhem Automationssystem basierend auf der API des Herstellers her. Für den vollen Funktionsumfang muss sichergestellt werden, dass das Setting \"API-Operator\" in der DoorBird Android/iPhone - APP unter Administration -> User -> Edit -> Permission -> API-Operator gesetzt ist."
		}
	},
	"license"                        : ["GPL_2"],
	"author"                         : ["Matthias Deeke <matthias.deeke@deeke.eu>"],
	"x_fhem_maintainer"              : ["Sailor"],
	"keywords"                       : ["Doorbird", "Intercom"],
	"prereqs": {
		"runtime": {
			"requires": {
				"Crypt::Argon2"      : 0,
				"Cwd"                : 0,
				"Data::Dumper"       : 0,
				"Encode"             : 0,
				"HttpUtils"          : 0,
				"IO::Socket"         : 0,
				"IO::String"         : 0,
				"JSON"               : 0,
				"LWP::UserAgent"     : 0,
				"MIME::Base64"       : 0,
				"Sodium::FFI"        : 0,
				"constant"           : 0,
				"perl"               : 5.014,
				"strict"             : 0,
				"utf8"               : 0,
				"warnings"           : 0
			},
			"recommends": {
			},
			"suggests": {
			}
		}
	},
	"x_prereqs_os_debian": {
		"runtime": {
			"requires": {
				"sox": 0,
				"libsox-fmt-all"     : 0,
				"libsodium-dev"      : 0,
				"gstreamer1.0-tools" : 0
			},
			"recommends": {
			},
			"suggests": {
			}
		}
	},
	"resources": {
		"x_support_community": {
			"rss"                    : "https://forum.fhem.de/index.php/topic,100758.msg",
			"web"                    : "https://forum.fhem.de/index.php/topic,100758.msg",
			"subCommunity" : {
				"rss"                : "https://forum.fhem.de/index.php/topic,100758.msg",
				"title"              : "This sub-board will be first contact point",
				"web"                : "https://forum.fhem.de/index.php/topic,100758.msg"
			}
		},
		"x_wiki" : {
			"title"                  : "FHEM Wiki: DoorBird",
			"web"                    : "https://wiki.fhem.de/wiki/DoorBird"
		}
	},
	"x_support_status"               : "supported"
}
=end :application/json;q=META.json
=cut