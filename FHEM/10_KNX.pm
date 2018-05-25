##############################################
# $Id$
# ABU 20180218 restructuring, removed older documentation
# ABU 20180317 setExtensions reingebaut, set funktion
# ABU 20180319 repaired "reply"-function
# ABU 20180319 tuned "reply"-function
# ABU 20180322 switch context for put-cmd, minor fixes
# ABU 20180328 fixed get-name containing "-"
# ABU 20180408 Added attriut screening, implemented set/get/listenonly, prevent to identical GADS in one device
# ABU 20180411 Added timer functions, prevented two identical GAD in one device
# ABU 20180413 Fixed some naming issues in defined, made en-doku, removed DE-Doku
# ABU 20180416 corrected timedev in doku
# ABU 20180418 removed spam-log in "get"; replaced "$value" by "undef" in encode and decode function if model not defined
# ABU 20180419 fixed Doku, added nosuffix, added dpt1.000
# ABU 20180426 minor fixes in answering bus-requests
# ABU 20180509 Added dpt14.033
# ABU 20180519 Added dpt17.001, adjustet $PAT_GAD_OPTIONS with boundaries and whitespace 
# ABU 20180523 Added dpt7.007

#TODO Prio 1:
#
#TODO Prio 2:
#Thread nochmal nach Features durchsuchen

package main;

use strict;
use warnings;
use Encode;
use SetExtensions;

#set to 1 for debug
my $debug = 0;

#string constant for autocreate
my $modelErr = "MODEL_NOT_DEFINED";

my $OFF = "off";
my $ON = "on";
my $ONFORTIMER = "on-for-timer";
my $ONUNTIL = "on-until";
my $OFFFORTIMER = "off-for-timer";
my $OFFUNTIL = "off-until";
my $TOGGLE = "toggle";
my $RAW = "raw";
my $RGB = "rgb";
my $STRING = "string";
my $VALUE = "value";

#valid set commands
my %sets = (
	$OFF => "",
	$ON => "",
	$ONFORTIMER => "",
	$ONUNTIL => "",
	$OFFFORTIMER => "",
	$OFFUNTIL => "",
	$TOGGLE => "",
	$RAW => "",
	$RGB => "colorpicker",
	$STRING => "",
	$VALUE => ""
);

#identifier for TUL
my $id = 'C';

#regex patterns
#pattern for group-adress
my $PAT_GAD = '^[0-9]{1,2}\/[0-9]{1,2}\/[0-9]{1,3}$';
#pattern for group-adress in hex-format
#new syntax for extended adressing
my $PAT_GAD_HEX = '^[0-9a-f]{5}$';
#old syntax
#my $PAT_GAD_HEX = qr/^[0-9a-f]{4}$/;
#pattern for group-no
my $PAT_GNO = '[gG][1-9][0-9]?';
#pattern for GAD-Options
my $PAT_GAD_OPTIONS = '^\s*((get)|(set)|(listenonly))\s*$';
#pattern for GAD-suffixes
my $PAT_GAD_SUFFIX = 'nosuffix';
#pattern for forbidden GAD-Names
#my $PAT_GAD_NONAME = '((on)|(off)|(value)|(raw)|' . $PAT_GAD_OPTIONS . ')$';
#pattern for DPT
my $PAT_GAD_DPT = 'dpt\d*\.?\d*';

#CODE is the identifier for the en- and decode algos. See encode and decode functions
#UNIT is appended to state for a better reading
#FACTOR and OFFSET are used to normalize a value. value = FACTOR * (RAW - OFFSET). Must be undef for non-numeric values.
#PATTERN is used to check an trim the input-values
#MIN and MAX are used to cast numeric values. Must be undef for non-numeric dpt. Special Usecase: DPT1 - MIN represents 00, MAX represents 01
#if supplied, setlist is passed directly to fhemweb in order to show comand-buttons in the details-view (e.g. "colorpicker" or "item1,item2,item3")
#if setlist is not supplied and min/max are given, a slider is shown for numeric values. Otherwise min/max value are shown in a list
my %dpttypes = (
  #Binary value
	"dpt1" 			=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/((on)|(off)|(0?1)|(0?0))$/i, MIN=>"off", MAX=>"on"},  
	"dpt1.000" 		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/((on)|(off)|(0?1)|(0?0))$/i, MIN=>"0", MAX=>"1"},
	"dpt1.001" 		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/((on)|(off)|(0?1)|(0?0))$/i, MIN=>"off", MAX=>"on"},
	"dpt1.002" 		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(true)|(false)|(0?1)|(0?0)/i, MIN=>"false", MAX=>"true"},
	"dpt1.003" 		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(enable)|(disable)|(0?1)|(0?0)/i, MIN=>"disable", MAX=>"enable"},
	"dpt1.004"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/i, MIN=>"no ramp", MAX=>"ramp"},
	"dpt1.005"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/i, MIN=>"no alarm", MAX=>"alarm"},
	"dpt1.006"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/i, MIN=>"low", MAX=>"high"},
	"dpt1.007"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/i, MIN=>"decrease", MAX=>"increase"},
	"dpt1.008" 		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(up)|(down)|(0?1)|(0?0)/i, MIN=>"up", MAX=>"down"},
	"dpt1.009" 		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(closed)|(open)|(0?1)|(0?0)/i, MIN=>"open", MAX=>"closed"},
	"dpt1.010" 		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(start)|(stop)|(0?1)|(0?0)/i, MIN=>"stop", MAX=>"start"},
	"dpt1.011"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/i, MIN=>"inactive", MAX=>"active"},
	"dpt1.012"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/i, MIN=>"not inverted", MAX=>"inverted"},
	"dpt1.013"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/i, MIN=>"start/stop", MAX=>"cyclically"},
	"dpt1.014"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/i, MIN=>"fixed", MAX=>"calculated"},
	"dpt1.015"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/i, MIN=>"no action", MAX=>"reset"},
	"dpt1.016"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/i, MIN=>"no action", MAX=>"acknowledge"},
	"dpt1.017"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/i, MIN=>"trigger", MAX=>"trigger"},
	"dpt1.018"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/i, MIN=>"not occupied", MAX=>"occupied"},
	"dpt1.019" 		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(closed)|(open)|(0?1)|(0?0)/i, MIN=>"closed", MAX=>"open"},	
	"dpt1.021"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/i, MIN=>"logical or", MAX=>"logical and"},
	"dpt1.022"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/i, MIN=>"scene A", MAX=>"scene B"},
	"dpt1.023"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/i, MIN=>"move up/down", MAX=>"move and step mode"},

	#Step value (two-bit)
	"dpt2" 			=> {CODE=>"dpt2", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(on)|(off)|(forceon)|(forceoff)/i, MIN=>undef, MAX=>undef, SETLIST=>"on,off,forceon,forceoff"},
	  
	#Step value (four-bit)
	"dpt3" 			=> {CODE=>"dpt3", UNIT=>"", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/i, MIN=>-100, MAX=>100},

	# 1-Octet unsigned value
	"dpt5" 			=> {CODE=>"dpt5", UNIT=>"", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/i, MIN=>0, MAX=>255},
	"dpt5.001" 		=> {CODE=>"dpt5", UNIT=>"%", FACTOR=>100/255, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/i, MIN=>0, MAX=>100},  
	"dpt5.003" 		=> {CODE=>"dpt5", UNIT=>"&deg;", FACTOR=>360/255, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/i, MIN=>0, MAX=>360},
	"dpt5.004" 		=> {CODE=>"dpt5", UNIT=>"%", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/i, MIN=>0, MAX=>255},
	
	# 1-Octet signed value
	"dpt6" 			=> {CODE=>"dpt6", UNIT=>"", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/i, MIN=>-127, MAX=>127},
	"dpt6.001" 		=> {CODE=>"dpt6", UNIT=>"%", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/i, MIN=>0, MAX=>100},

	# 2-Octet unsigned Value 
	"dpt7" 			=> {CODE=>"dpt7", UNIT=>"", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/i, MIN=>0, MAX=>65535},
	"dpt7.001" 			=> {CODE=>"dpt7", UNIT=>"", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/i, MIN=>0, MAX=>65535},
	"dpt7.005" 		=> {CODE=>"dpt7", UNIT=>"s", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/i, MIN=>0, MAX=>65535},
	"dpt7.006" 		=> {CODE=>"dpt7", UNIT=>"m", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/i, MIN=>0, MAX=>65535},
	"dpt7.007" 		=> {CODE=>"dpt7", UNIT=>"h", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/i, MIN=>0, MAX=>65535},	
	"dpt7.012" 		=> {CODE=>"dpt7", UNIT=>"mA", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/i, MIN=>0, MAX=>65535},	
	"dpt7.013" 		=> {CODE=>"dpt7", UNIT=>"lux", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/i, MIN=>0, MAX=>65535},

	# 2-Octet signed Value 
	"dpt8" 			=> {CODE=>"dpt8", UNIT=>"", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/i, MIN=>-32768, MAX=>32768},
	"dpt8.005" 		=> {CODE=>"dpt8", UNIT=>"s", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/i, MIN=>-32768, MAX=>32768},
	"dpt8.010" 		=> {CODE=>"dpt8", UNIT=>"%", FACTOR=>0.01, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/i, MIN=>-32768, MAX=>32768},
	"dpt8.011" 		=> {CODE=>"dpt8", UNIT=>"&deg;", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/i, MIN=>-32768, MAX=>32768},

	# 2-Octet Float value
	"dpt9"	 		=> {CODE=>"dpt9", UNIT=>"", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/i, MIN=>-670760, MAX=>670760},
	"dpt9.001"	 	=> {CODE=>"dpt9", UNIT=>"&deg;C", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/i, MIN=>-670760, MAX=>670760},	
	"dpt9.004"	 	=> {CODE=>"dpt9", UNIT=>"lux", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/i, MIN=>-670760, MAX=>670760},	
	"dpt9.006"	 	=> {CODE=>"dpt9", UNIT=>"Pa", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/i, MIN=>-670760, MAX=>670760},	
	"dpt9.005"	 	=> {CODE=>"dpt9", UNIT=>"m/s", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/i, MIN=>-670760, MAX=>670760},	
	"dpt9.007"	 	=> {CODE=>"dpt9", UNIT=>"%", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/i, MIN=>-670760, MAX=>670760},	
	"dpt9.008"	 	=> {CODE=>"dpt9", UNIT=>"ppm", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/i, MIN=>-670760, MAX=>670760},	
	"dpt9.009"	 	=> {CODE=>"dpt9", UNIT=>"m&sup3/h", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/i, MIN=>-670760, MAX=>670760},	
	"dpt9.010"	 	=> {CODE=>"dpt9", UNIT=>"s", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/i, MIN=>-670760, MAX=>670760},	
	"dpt9.021"	 	=> {CODE=>"dpt9", UNIT=>"mA", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/i, MIN=>-670760, MAX=>670760},		
	"dpt9.024"	 	=> {CODE=>"dpt9", UNIT=>"kW", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/i, MIN=>-670760, MAX=>670760},	
	"dpt9.025"	 	=> {CODE=>"dpt9", UNIT=>"l/h", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/i, MIN=>-670760, MAX=>670760},	
	"dpt9.026"	 	=> {CODE=>"dpt9", UNIT=>"l/h", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/i, MIN=>-670760, MAX=>670760},	
	"dpt9.028"	 	=> {CODE=>"dpt9", UNIT=>"km/h", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/i, MIN=>-670760, MAX=>670760},		
  
	# Time of Day
	"dpt10"			=> {CODE=>"dpt10", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/((2[0-4]|[0?1][0-9]):(60|[0?1-5]?[0-9]):(60|[0?1-5]?[0-9]))|(now)/i, MIN=>undef, MAX=>undef},
  
	# Date  
	"dpt11"			=> {CODE=>"dpt11", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/((3[01]|[0-2]?[0-9]).(1[0-2]|0?[0-9]).(19[0-9][0-9]|2[01][0-9][0-9]))|(now)/i, MIN=>undef, MAX=>undef},
  
	# 4-Octet unsigned value (handled as dpt7)
	"dpt12" 		=> {CODE=>"dpt12", UNIT=>"", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,10}/i, MIN=>0, MAX=>4294967295},
  
	# 4-Octet Signed Value
	"dpt13" 		=> {CODE=>"dpt13", UNIT=>"", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,10}/i, MIN=>-2147483647, MAX=>2147483647},
	"dpt13.010" 	=> {CODE=>"dpt13", UNIT=>"Wh", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,10}/i, MIN=>-2147483647, MAX=>2147483647},
	"dpt13.013" 	=> {CODE=>"dpt13", UNIT=>"kWh", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,10}/i, MIN=>-2147483647, MAX=>2147483647},

	# 4-Octet single precision float
	"dpt14"			=> {CODE=>"dpt14", UNIT=>"", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,40}[.,]?\d{1,4}/i, MIN=>undef, MAX=>undef},
	"dpt14.019"		=> {CODE=>"dpt14", UNIT=>"A", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,40}[.,]?\d{1,4}/i, MIN=>undef, MAX=>undef},
	"dpt14.027"		=> {CODE=>"dpt14", UNIT=>"V", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,40}[.,]?\d{1,4}/i, MIN=>undef, MAX=>undef},
	"dpt14.033"		=> {CODE=>"dpt14", UNIT=>"Hz", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,40}[.,]?\d{1,4}/i, MIN=>undef, MAX=>undef},
	"dpt14.056"		=> {CODE=>"dpt14", UNIT=>"W", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,40}[.,]?\d{1,4}/i, MIN=>undef, MAX=>undef},
	"dpt14.068"		=> {CODE=>"dpt14", UNIT=>"&deg;C", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,40}[.,]?\d{1,4}/i, MIN=>undef, MAX=>undef},
	"dpt14.076"		=> {CODE=>"dpt14", UNIT=>"m&sup3;", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,40}[.,]?\d{1,4}/i, MIN=>undef, MAX=>undef},
	"dpt14.057"		=> {CODE=>"dpt14", UNIT=>"cos &Phi;", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,40}[.,]?\d{1,4}/i, MIN=>undef, MAX=>undef},
  
	# 14-Octet String
	"dpt16"         => {CODE=>"dpt16", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/.{1,14}/i, MIN=>undef, MAX=>undef},
	"dpt16.000"     => {CODE=>"dpt16", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/.{1,14}/i, MIN=>undef, MAX=>undef},
	"dpt16.001"     => {CODE=>"dpt16", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/.{1,14}/i, MIN=>undef, MAX=>undef},

	# 1-Octet unsigned value
	"dpt17.001" 	=> {CODE=>"dpt5", UNIT=>"", FACTOR=>1, OFFSET=>1, PATTERN=>qr/[+-]?\d{1,3}/i, MIN=>0, MAX=>63},
	
	#date and time
	"dpt19"			=> {CODE=>"dpt19", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(((3[01]|[0-2]?[0-9]).(1[0-2]|0?[0-9]).(19[0-9][0-9]|2[01][0-9][0-9]))_((2[0-4]|[0?1][0-9]):(60|[0?1-5]?[0-9]):(60|[0?1-5]?[0-9])))|(now)/i, MIN=>undef, MAX=>undef},

	# Color-Code
	"dpt232"        => {CODE=>"dpt232", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/[0-9a-f]{6}/i, MIN=>undef, MAX=>undef, SETLIST=>"colorpicker"}
);

#Init this device
#This declares the interface to fhem
#############################
sub
KNX_Initialize($) {
	my ($hash) = @_;

	$hash->{Match}     		= "^$id.*";
	$hash->{GetFn}     		= "KNX_Get";
	$hash->{SetFn}     		= "KNX_Set";
	$hash->{StateFn}   		= "KNX_State";
	$hash->{DefFn}     		= "KNX_Define";
	$hash->{UndefFn}   		= "KNX_Undef";
	$hash->{ParseFn}   		= "KNX_Parse";
	$hash->{AttrFn}   		= "KNX_Attr";
	$hash->{NotifyFn}  		= "KNX_Notify";	
	$hash->{DbLog_splitFn}  = "KNX_DbLog_split";
	$hash->{AttrList}  		= 	"IODev " .					#tells the module the IO-Device to communicate with. Optionally set within definition.
								"do_not_notify:1,0 " . 		#supress any notification (including log)
								"showtime:1,0 " . 			#shows time instead of received value in state
								"answerReading:1,0 " .		#allows FHEM to answer a read telegram								
								"stateRegex " .				#modifies state value
								"stateCmd " .				#modify state value
								"putCmd " . 				#called when the KNX bus asks for a -put reading
								"stateCopy " .				#backup content of state in this reading (only for received telegrams)
								"format " .					#supplies post-string
								"listenonly:1,0 " . 		#DEPRECATED
								"readonly:1,0 " .			#DEPRECATED
								"slider " .					#DEPRECATED
								"useSetExtensions:1,0 " .	#DEPRECATED
								"$readingFnAttributes ";	#standard attributes
}

#Define this device
#Is called at every define
#############################
sub
KNX_Define($$) {
	my ($hash, $def) = @_;
	#enable newline within define with \
	$def =~ s/\n/ /g;
	my @a = split("[ \t][ \t]*", $def);
	#device name
	my $name = $a[0];
	
	#set verbose to 5, if debug enabled
	$attr{$name}{verbose} = 5 if ($debug eq 1);

	my $tempStr = join (", ", @a);
	Log3 ($name, 5, "define $name: enter $hash, attributes: $tempStr");
	
	#too less arguments
	return "wrong syntax - define <name> KNX <group:model[:GAD-name][:set|get|listenonly]> [<group:model[:GAD-name][:set|get|listenonly]>*] [<IODev>]" if (int(@a) < 3);
	
	#check for IODev
	#is last argument not a group or a group:model pair? Then assign for IODev.
	my $lastGroupDef = int(@a);
	#if (($a[int(@a) - 1] !~ m/^[0-9]{1,2}\/[0-9]{1,2}\/[0-9]{1,3}$/i) and ($a[int(@a) - 1] !~ m/^[0-9a-f]{4}$/i) and ($a[int(@a) - 1] !~ m/[0-9a-fA-F]:[dD][pP][tT]/i))
	if (($a[int(@a) - 1] !~ m/${PAT_GAD}/i) and ($a[int(@a) - 1] !~ m/${PAT_GAD_HEX}/i) and ($a[int(@a) - 1] !~ m/[0-9a-fA-F]:[dpt]/i))
	{
		$attr{$name}{IODev} = $a[int(@a) - 1];
		$lastGroupDef--; 
	}
	
	#reset
	my $firstrun = 1;
	$hash->{GADDETAILS} = {};
	$hash->{GADTABLE} = {};
	
	#create groups and models, iterate through all possible args
	for (my $i = 2; $i < $lastGroupDef; $i++)
	{
		#backup actual GAD
		my $gadDef = $a[$i]; 
		my ($gad, $gadModel, $gadArg3, $gadArg4, $gadArg5) = split /:/, $gadDef;
		my $gadCode = undef;
		my $gadName = undef;
		my $gadOption = undef;
		my $gadNoSuffix = undef;		
		my $rdNameGet = undef;
		my $rdNameSet = undef;
		my $rdNamePut = undef;

		Log3 ($name, 5, "define $name: argCtr $i, string: $a[$i]");	

		#G-nr
		my $gadNo = $i - 1;
		
		#GAD not defined
		return "GAD not defined for group-number $gadNo" if (!defined($gad));
		
		#GAD wrong syntax
		#either 1/2/3 or 1203
		return "wrong group name format in group-number $gadNo: specify as 0-15/0-15/0-255 or as hex" if (($gad !~ m/${PAT_GAD}/i) and ($gad !~ m/${PAT_GAD_HEX}/i));
		
		#check if model supplied
		return "no model defined for group-number $gadNo" if (!defined($gadModel));
		
		if (defined ($gadArg3) and defined ($gadArg4) and defined ($gadArg5))
		{
			Log3 ($name, 5, "define $name: found GAD: $gad, MODEL: $gadModel, Arg3: $gadArg3, Arg4: $gadArg4, Arg5: $gadArg5") 
		}
		elsif (defined ($gadArg3) and defined ($gadArg4))
		{
			Log3 ($name, 5, "define $name: found GAD: $gad, MODEL: $gadModel, Arg3: $gadArg3, Arg4: $gadArg4");
		}
		elsif (defined ($gadArg3))
		{
			Log3 ($name, 5, "define $name: found GAD: $gad, MODEL: $gadModel, Arg3: $gadArg3");
		}
		
		#within autocreate no model is supplied - throw warning
		if ($gadModel eq $modelErr)
		{
			Log3 ($name, 2, "define $name: autocreate defines no model - only restricted functions are available");
		}
		else
		{
			#check model-type
			return "invalid model for group-number $gadNo. Use " .join(",", keys %dpttypes) if (!defined($dpttypes{$gadModel}));
		}
				
		#convert to string, if supplied in Hex
		#old syntax
		#$group = KNX_hexToName ($group) if ($group =~ m/^[0-9a-f]{4}$/i);
		#new syntax for extended adressing
		$gad = KNX_hexToName ($gad) if ($gad =~ m/^[0-9a-f]{5}$/i);

		#convert it vice-versa, just to be sure
		$gadCode = KNX_nameToHex ($gad);

		###GADTABLE
		#create a hash with gadCode and gadName for later mapping
		my $tableHashRef = $hash->{GADTABLE};
		#if not defined yet, define a new hash
		if (not(defined($tableHashRef)))
		{
			$tableHashRef={};
			$hash->{GADTABLE}=$tableHashRef;
		}		
		###GADTABLE
		
		return "GAD $gad may be supplied only once per device." if (defined ($tableHashRef->{$gadCode}));
		
		#Arg3 supplied? May be name or option. If not --> Error!
		if (defined ($gadArg3))
		{
			#Arg3 is an option
			if ($gadArg3 =~ m/$PAT_GAD_OPTIONS/i)
			{
				$gadOption = $gadArg3;
			}
			#Arg3 is a fordbidden name (set-command)
			elsif (defined ($sets{$gadArg3}))
			{
				return "invalid name: $gadArg3. Forbidden names: " .join(",", keys %sets) ;
			}
			elsif ($gadArg3 =~ m/$PAT_GAD_SUFFIX/i)
			{
				return "not allowed: supplied \"nosuffix\" without \"name\"" ;
			}
			#Arg3 is a name -> assign it			
			else
			{
				$gadName = $gadArg3;
			}
		}
		
		#Arg4 supplied? May be option or nosuffix. If not --> Error!
		if (defined ($gadArg4))
		{
			#Arg4 is an option
			if ($gadArg4 =~ m/$PAT_GAD_OPTIONS/i)
			{
				$gadOption = $gadArg4;
			}
			elsif ($gadArg4 =~ m/$PAT_GAD_SUFFIX/i)
			{
				$gadNoSuffix = $gadArg4;
			}
			#Arg4 is unknown
			else
			{
				return "invalid option for group-number $gadNo. Use $PAT_GAD_OPTIONS or $PAT_GAD_SUFFIX";
			}
		}

		#Arg5 supplied? Must be preventSuffix. If not --> Error!
		if (defined ($gadArg5))
		{
			if ($gadArg5 =~ m/$PAT_GAD_SUFFIX/i)
			{
				$gadNoSuffix = $gadArg5;
			}
			#Arg5 is unknown
			else
			{
				return "invalid option for group-number $gadNo. Use $PAT_GAD_SUFFIX";
			}		
		}
		
		#cache suffixes
		my $suffixGet = "-get";
		my $suffixSet = "-set";
		my $suffixPut = "-put";
		
		if (defined ($gadNoSuffix) and not ($gadNoSuffix eq ""))
		{
			$suffixGet = "";
			$suffixSet = "";
			$suffixPut = "";			
		}
		
		if (defined ($gadName) and not ($gadName eq ""))
		{
			if (defined ($gadOption) and not ($gadOption  eq ""))
			{
				#get - prohibit set
				if ($gadOption =~ m/(get)|(listenonly)/i)
				{
					$rdNameGet = $gadName . $suffixGet;
					$rdNameSet = "";
					$rdNamePut = $gadName . $suffixPut;;
				}
				#listenonly - prohibit set and put
				elsif ($gadOption =~ m/(get)|(listenonly)/i)
				{
					$rdNameGet = $gadName . $suffixGet;
					$rdNameSet = "";
					$rdNamePut = "";
				}
				#set - prohibit put and get
				elsif ($gadOption =~ m/(set)/i)
				{
					$rdNameGet = "";
					$rdNameSet = $gadName . $suffixSet;
					$rdNamePut = "";
				}
			}
			else
			{
				$rdNameGet = $gadName . $suffixGet;
				$rdNameSet = $gadName . $suffixSet;
				$rdNamePut = $gadName . $suffixPut;
			}		
		}
		else
		{
			if (defined ($gadOption) and not ($gadOption  eq ""))
			{
				#get - prohibit set
				if ($gadOption =~ m/(get)|(listenonly)/i)
				{
					$rdNameGet = "getG" . $gadNo;
					$rdNameSet = "";
					$rdNamePut = "putG" . $gadNo;
				}
				#listenonly - prohibit set and put
				elsif ($gadOption =~ m/(get)|(listenonly)/i)
				{
					$rdNameGet = "getG" . $gadNo;
					$rdNameSet = "";
					$rdNamePut = "";
				}
				#set - prohibit put and get
				elsif ($gadOption =~ m/(set)/i)
				{
					$rdNameGet = "";
					$rdNameSet = "setG" . $gadNo;
					$rdNamePut = "";
				}
			}
			else
			{
				$rdNameGet = "getG" . $gadNo;
				$rdNameSet = "setG" . $gadNo;
				$rdNamePut = "putG" . $gadNo;
			}		
		}
		
		#assuming name in old syntax, if not given...
		$gadName = "g" . $gadNo if (!defined ($gadName));
					
		my $log = "define $name: found GAD: $gad, NAME: $gadName NO: $gadNo, HEX: $gadCode, DPT: $gadModel";
		$log .= ", OPTION: $gadOption" if (defined ($gadOption));	
		Log3 ($name, 5, "$log");	
		
		#determint dpt-details
		my $dptDetails = $dpttypes{$gadModel};
		my $setlist;
		#case list is given, pass it through
		if (defined ($dptDetails->{SETLIST}))
		{
			$setlist = ":" . $dptDetails->{SETLIST};
		}
		#case number - place slider
		elsif (defined ($dptDetails->{MIN}) and ($dptDetails->{MIN} =~ m/0|[+-]?\d*[(.|,)\d*]/))
		{
			my $min = $dptDetails->{MIN};
			my $max = $dptDetails->{MAX};
			$setlist = ":slider," . $min . "," . int(($max-$min)/100) . "," . $max;
		}
		#on/off/...
		elsif (defined ($dptDetails->{MIN}))
		{
			my $min = $dptDetails->{MIN};
			my $max = $dptDetails->{MAX};
			$setlist = ":" . $min . "," . $max;
		}
		#plain input field
		else
		{
			$setlist = "";
		}		
	
		Log3 ($name, 5, "define $name, Estimated reading-names: $rdNameGet, $rdNameSet, $rdNamePut");
		Log3 ($name, 5, "define $name, SetList: $setlist") if (defined ($setlist));
		
		#add details to hash
		$hash->{GADDETAILS}{$gadName} = {GROUP => $gad, CODE => $gadCode, MODEL => $gadModel, NO => $gadNo, OPTION => $gadOption, RDNAMEGET => $rdNameGet, RDNAMESET => $rdNameSet, RDNAMEPUT => $rdNamePut, SETLIST => $setlist};
		
		#add key and value to GADTABLE
		$tableHashRef->{$gadCode} = $gadName;
		
		###DEFPTR
		my @devList = ();
		#Restore list, if at least one GAD is installed
		@devList = @{$modules{KNX}{defptr}{$gadCode}} if (defined ($modules{KNX}{defptr}{$gadCode}));
		#push actual hash to list
		push (@devList, $hash);
		#backup list
		@{$modules{KNX}{defptr}{$gadCode}} = @devList;		
		###DEFPTR
		
		#in firstrun backup gadName for later backwardCompatibility
		$hash->{FIRSTGADNAME} = $gadName if ($firstrun == 1);
		
		#create getlist for getFn
		$hash->{GETSTRING} = join (":noArg ", keys %{$hash->{GADDETAILS}}) . ":noArg";	
		
		#create setlist for setFn
		my $setString = "";	
		foreach my $key (keys %{$hash->{GADDETAILS}})
		{
			$setString .= " " if (length ($setString) > 1);
			$setString = $setString . $key . $hash->{GADDETAILS}{$key}{SETLIST}; 
		}
		$hash->{SETSTRING} = $setString;
		
		Log3 ($name, 5, "GETSTR: " . $hash->{GETSTRING} . ", SETSTR: " . $hash->{SETSTRING});
		
		$firstrun = 0;
	}
	
	#common name
	$hash->{NAME} = $name;	
	#backup name for a later rename
	$hash->{DEVNAME} = $name;
	
	#assign io-dev automatically, if not given via definition	
	AssignIoPort($hash);
	
	Log3 ($name, 5, "exit define");
	
	#debug GAD-codes
	if (0)
	{		
		foreach my $gd (keys %{$modules{KNX}{defptr}}) 
		{
			Log3 ($name, 5, "GAD: $gd");
			foreach my $dv (@{$modules{KNX}{defptr}{$gd}}) 
			{
				Log3 ($name, 5, "DEV: " . $dv->{NAME} . " (GAD: $gd)");
			}		
		}			
	}
	
	return undef;
}

#Release this device
#Is called at every delete / shutdown
#############################
sub
KNX_Undef($$) {
	my ($hash, $name) = @_;

	Log3 ($name, 5, "enter undef $name: hash: $hash name: $name");
	
	#remove hash-pointer from available devices-list
	#parse through all valid GAD in this deive
	foreach my $gadCode (keys %{$hash->{GADTABLE}}) 
	{
		my $gadName = $hash->{GADTABLE}{$gadCode};
		Log3 ($name, 5, "undef $name: remove $gadName, $gadCode");
		
		#get list of hash-pointers
		my @oldDeviceList = @{$modules{KNX}{defptr}{$gadCode}};
		my @newDeviceList = ();
		#create new list without this device
		foreach my $devHash (@oldDeviceList)
		{
			push (@newDeviceList, $devHash) if (not ($devHash == $hash));
		}
		
		#backup new list
		@{$modules{KNX}{defptr}{$gadCode}} = @newDeviceList;
	}

	Log3 ($name, 5, "exit undef");
	return undef;
}

#Places a "read" Message on the KNX-Bus
#The answer is treated as regular telegram
#############################
sub
KNX_Get($@) {
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	my $groupnr = 1;

	my $tempStr = join (", ", @a);
	Log3 ($name, 5, "enter get $name: hash: $hash, attributes: $tempStr");
	
	#not necessary any more - was used to get rid of the "-" from the checkboxes
	#splice(@a, 1, 1) if (defined ($a[1]) and ($a[1] =~ m/-/));
	my $na = int(@a);

	
	#not more then 2 arguments allowed
	Log3 ($name, 2, "get: too much arguments. Only one argument allowed (group-address). Other Arguments are discarded.") if ($na > 2);
	
	#FHEM asks with a ? at startup - no action, no log
	
	return "Unknown argument, choose one of " . $hash->{GETSTRING} if(defined($a[1]) and ($a[1] =~ m/\?/));
	
	#determine gadName to read
	#ask for first defined GAD if no argument is supplied
	my $gadName;	
	if (defined ($a[1]))
	{
		$gadName = $a[1];
	}
	else
	{
		$gadName = $hash->{FIRSTGADNAME}; 
	}
	
	#get groupCode
	my $groupc = $hash->{GADDETAILS}{$gadName}{CODE};
	#get groupAddress
	my $group = $hash->{GADDETAILS}{$gadName}{GROUP};
	#get option		
	my $option = $hash->{GADDETAILS}{$gadName}{OPTION};
	
	#return, if unknown group
	return "no valid address stored for gad: $gadName" if(!$groupc);
	
	#exit, if read is prohibited
	#return "did not request a value - \"listenonly\" is set." if (AttrVal ($name, "listenonly", 0) =~ m/1/);
	
	#exit if get is prohibited
	return "did not request a value - \"listenonly\" is set." if (defined ($option) and ($option =~ m/listenonly/i));
	return "did not request a value - \"set\" is set." if (defined ($option) and ($option =~ m/set/i));
  	
	#send read-request to the bus
	Log3 ($name, 5, "get $name: request value for GAD: $group, GAD-NAME: $gadName");
	IOWrite($hash, $id, "r" . $groupc);
	
  	Log3 ($name, 5, "exit get");
	
	return "current value for $name ($group) requested";
}

#Does something according the given cmd...
#############################
sub
KNX_Set($@) {
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	my $ret = "";
	my $na = int(@a);
	
	my $tempStr = join (", ", @a);
	#log only, if not called with cmd = ?
	Log3 ($name, 5, "enter set $name: hash: $hash, attributes: $tempStr") if ((defined ($a[1])) and (not ($a[1] eq "?")));

	#return, if no set value specified
	return "no set value specified" if($na < 2);
	
	#backup values
	my $arg1 = $a[1];
	my $arg2 = $a[2] if defined ($a[2]);
	#remove whitespaces
	$arg1 =~ s/^\s+|\s+$//gi;
	
	#FHEM asks with a "?" at startup or any reload of the device-detail-view
	#return string for enabling webfrontend to show boxes, ...
	#Log3 ($name, 5, "Unknown argument, choose one of " . $hash->{SETSTRING}) if(defined($arg1) and ($arg1 =~ m/\?/));
	return "Unknown argument, choose one of " . $hash->{SETSTRING} if(defined($arg1) and ($arg1 =~ m/\?/));
	
	#contains gadNames to be executed
	my $targetGadName = undef;
	my $cmd = undef;
	my @arg = ();
	
	#check, if old or new syntax
	#new syntax, if first arg is a valid gadName
	if (defined ($hash->{GADDETAILS}{$arg1}))
	{
		$targetGadName = $arg1;
		$cmd = $arg2;

		#backup args
		for (my $i = 3; $i <= scalar(@a); $i++) 
		{
			push (@arg, $a[$i]) if (defined ($a[$i]));
		}			
	}
	#oldsyntax
	else
	{
		#the command can be send to any of the defined groups indexed starting by 1
		#optional last argument starting with g indicates the group
		#default
		my $groupnr = 1;
		my $lastArg = $na - 1;
		#select another group, if the last arg starts with a g
		if($na > 2 && $a[$lastArg]=~ m/${PAT_GNO}/i)
		{	
			$groupnr = $a[$lastArg];
			#remove "g"
			$groupnr =~ s/^g//gi;

			$lastArg--;
		}

		#unknown groupnr
		return "group-no. not found" if(!defined($groupnr));
		
		foreach my $key (keys %{$hash->{GADDETAILS}})
		{
			$targetGadName = $key if (int ($hash->{GADDETAILS}{$key}{NO}) == int ($groupnr));
		}
		
		$cmd = $arg1;
		
		#backup args
		for (my $i = 2; $i <= $lastArg; $i++) 
		{
			push (@arg, $a[$i]) if (defined ($a[$i]));
		}
		
		if ($cmd =~ m/$RAW/i)
		{
			return "no data for cmd $cmd" if ($lastArg < 2);
		
			#check for 1-16 hex-digits
			if ($a[2] =~ m/[0-9A-F]{1,16}/i)
			{
				$cmd = $a[2];
			} 
			else
			{
				return "$a[2] has wrong syntax. Use hex-format only.";
			}
		}	 
		elsif ($cmd =~ m/$VALUE/i)
		{
			my $code = $hash->{GADDETAILS}{$targetGadName}{MODEL};
			return "\"value\" not allowed for dpt1, dpt16 and dpt232" if ($code =~ m/(dpt1$)|(dpt16$)|(dpt232$)/i);
			return "no data for cmd $cmd" if ($lastArg < 2);
			
			$cmd = $a[2];
			$cmd =~ s/,/\./g;
		} 
		#set string <val1 val2 valn>
		elsif ($cmd =~ m/$STRING/i)
		{
			my $code = $hash->{GADDETAILS}{$targetGadName}{MODEL};
			return "\"string\" only allowed for dpt16" if (not($code =~ m/(dpt16$)/i));
			return "no data for cmd $cmd" if ($lastArg < 2);
			
			$cmd = $a[2];
			for (my $i=3; $i<=$lastArg; $i++)
			{
				$cmd.= " ".$a[$i];		  
			}				
		} 	
		#set RGB <RRGGBB>
		elsif ($cmd =~ m/$RGB/i)
		{
			my $code = $hash->{GADDETAILS}{$targetGadName}{MODEL};
			return "\"RGB\" only allowed for dpt232" if (not($code =~ m/(dpt232$)/i));
			return "no data for cmd $cmd" if ($lastArg < 2);

			#check for 1-16 hex-digits
			if ($a[2] =~ m/[0-9A-F]{6}/i)
			{
				$cmd = lc($a[2]);
			} 
			else
			{
				return "$a[2] has wrong syntax. Use hex-format only.";
			}						
		}		
	}

	return "no target and cmd found" if(!defined($targetGadName) and !defined($cmd));
	return "no cmd found" if(!defined($cmd));
	return "no target found" if(!defined($targetGadName));

	$tempStr = join (" ", @arg);
	Log3 ($name, 5, "set $name: desired target is gad $targetGadName, command: $cmd, args: $tempStr");	
	
	#get details
	my $groupCode = $hash->{GADDETAILS}{$targetGadName}{CODE};
	my $option = $hash->{GADDETAILS}{$targetGadName}{OPTION};	
	my $rdString = $hash->{GADDETAILS}{$targetGadName}{RDNAMESET};
	#This contains the input 
	my $value = "";
	
	return "did not set a value - \"listenonly\" is set." if (defined ($option) and ($option =~ m/listenonly/i));
	return "did not set a value - \"get\" is set." if (defined ($option) and ($option =~ m/get/i));
	
	##############################
	#process set command with $value as output
	#
	$value = $cmd;
	#Text neads special treatment - additional args may be blanked words
	$value .= " " . join (" ", @arg) if (($hash->{GADDETAILS}{$targetGadName}{MODEL} =~ m/dpt16$/i) and (scalar (@arg) > 0));
	#Special commands for dpt1 and dpt1.001
	if ($hash->{GADDETAILS}{$targetGadName}{MODEL} =~ m/((dpt1)|(dpt1.001))$/i)
	{
		#delete any running timers
		#on-for-timer
		if ($hash->{"ON-FOR-TIMER_$groupCode"})
		{
			CommandDelete(undef, $name . "_timer_$groupCode");
			delete $hash->{"ON-FOR-TIMER_$groupCode"};
		}
		#on-until
		if($hash->{"ON-UNTIL_$groupCode"}) 
		{
			CommandDelete(undef, $name . "_until_$groupCode");
			delete $hash->{"ON-UNTIL_$groupCode"};
		}			
		#off-for-timer
		if ($hash->{"OFF-FOR-TIMER_$groupCode"})
		{
			CommandDelete(undef, $name . "_timer_$groupCode");
			delete $hash->{"OFF-FOR-TIMER_$groupCode"};
		}
		#off-until
		if($hash->{"OFF-UNTIL_$groupCode"}) 
		{
			CommandDelete(undef, $name . "_until_$groupCode");
			delete $hash->{"OFF-UNTIL_$groupCode"};
		}
		
		#set on-for-timer / off-for-timer
		if ($cmd =~ m/($ONFORTIMER)|($OFFFORTIMER)/i)
		{
			#get duration
			my $duration = sprintf("%02d:%02d:%02d", $arg[0]/3600, ($arg[0]%3600)/60, $arg[0]%60);
			Log3 ($name, 5, "set $name: \"on-for-timer\" for $duration");
			#create local marker
			$hash->{"ON-FOR-TIMER_$groupCode"} = $duration;
			#place at-command for switching off
			CommandDefine(undef, $name . "_timer_$groupCode at +$duration set $name $targetGadName off");
			#switch on or off...
			if ($cmd =~ m/on/i)
			{
				$value = "on";
			}
			else
			{
				$value = "off";
			}
		} 
		#set on-until / off-until
		elsif ($cmd =~ m/($ONUNTIL)|($OFFUNTIL)/i)
		{
			#get off-time
			my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($arg[0]);
			
			return "Error trying to parse timespec for $arg[0]: $err" if (defined($err));
			
			#build of-time
			my @lt = localtime;
			my $hms_til = sprintf("%02d:%02d:%02d", $hr, $min, $sec);
			my $hms_now = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);
			
			return "Won't switch - now ($hms_now) is later than $hms_til" if($hms_now ge $hms_til);

			Log3 ($name, 5, "set $name: \"on-until\" up to $hms_til");					
			#create local marker
			$hash->{"ON-UNTIL_$groupCode"} = $hms_til;
			#place at-command for switching off
			CommandDefine(undef, $name . "_until_$groupCode at $hms_til set $name $targetGadName off");
			#switch on or off...
			if ($cmd =~ m/on/i)
			{
				$value = "on";
			}
			else
			{
				$value = "off";
			}			
		} 
		#toggle
		elsif ($cmd =~ m/$TOGGLE/i)
		{
			if (ReadingsVal($name, $hash->{GADDETAILS}{$targetGadName}{RDNAMEGET}, "") =~ m/off/i)
			{
				$value = "on";
			}
			else
			{
				$value = "off";
			}
		}
	}
	
	#check and cast value
	my $transval = KNX_checkAndClean($hash, $value, $targetGadName);	

	#if cast not successful
	if (!defined($transval))
	{
		return "invalid value: $value" if (!defined($transval));
	}
	#
	#
	#/process set command
	##############################

		
	#send value
	$transval = KNX_encodeByDpt($hash, $transval, $targetGadName);
	IOWrite($hash, $id, "w" . $groupCode . $transval);
	
	Log3 ($name, 5, "set $name: cmd: $cmd, value: $value, translated: $transval");

	#re-read value, do not modify variable name due to usage in cmdAttr
	$transval = KNX_decodeByDpt($hash, $transval, $targetGadName);	
	#append post-string, if supplied
	my $suffix = AttrVal($name, "format",undef);
	$transval = $transval . " " . $suffix if (defined($suffix));			
	#execute regex, if defined				
	my $regAttr = AttrVal($name, "stateRegex", undef);
	my $state = KNX_replaceByRegex ($regAttr, $rdString . ":", $transval);
	
	Log3 ($name, 5, "set name: $name - replaced $rdString:$transval to $state") if (not ($transval eq $state));					

	if (defined($state))
	{	
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, $rdString, $transval);

		#execute state-command if defined
		#must be placed after first reading, because it may have a reference
		my $cmdAttr = AttrVal($name, "stateCmd", undef);
		if (defined ($cmdAttr) and !($cmdAttr eq ""))
		{
			$state = eval $cmdAttr;
			Log3 ($name, 5, "set name: $name - state replaced via command, result: state:$state");					
		}
		
		readingsBulkUpdate($hash, "state", $state);
		readingsEndUpdate($hash, 1);
	}							
	
	Log3 ($name, 5, "exit set");
	return undef;
}

#In case setstate is executed, a readingsupdate is initiated
#############################
sub
KNX_State($$$$) {
	my ($hash, $time, $reading, $value) = @_;
	my $name = $hash->{NAME};

	my $tempStr = join (", ", @_);
	Log3 ($name, 5, "enter state: hash: $hash name: $name, attributes: $tempStr");
	
	#in some cases state is submitted within value - if found, take only the stuff after state
	#my @strings = split("[sS][tT][aA][tT][eE]", $val);
	#$val = $strings[int(@strings) - 1];
	
	return undef if (not (defined($value)));
	return undef if (not (defined($reading)));
	
	#remove whitespaces
	$value =~ s/^\s+|\s+$//gi;
	$reading =~ s/^\s+|\s+$//gi;

	$reading = $reading if ($reading =~ m/state/i);
	
	Log3 ($name, 5, "state $name: update $reading with value: $value");
	
	#write value and update reading
	readingsSingleUpdate($hash, $reading, $value, 1);

	return undef;
}

#Get the chance to qualify attributes
#############################
sub
KNX_Attr(@) {
	my ($cmd,$name,$aName,$aVal) = @_;
	
	#if($cmd eq "set") 
	#{		
	#	if(($attr_name eq "debug") and (($attr_value eq "1") or ($attr_value eq "true")))
	#	{
	#	}			
	#}
	
	Log3 ($name, 2, "Attribut \"listenonly\" is deprecated. Please supply in definition - see commandref for details.") if ($aName =~ m/listenonly/i);
	Log3 ($name, 2, "Attribut \"readonly\" is deprecated. Please supply \"get\" in definition - see commandref for details.") if ($aName =~ m/readonly/i);
	Log3 ($name, 2, "Attribut \"slider\" is deprecated. Please use widgetOverride in Combination with WebCmd instead. See commandref for details.") if ($aName =~ m/slider/i);
	Log3 ($name, 2, "Attribut \"useSetExtensions\" is deprecated.") if ($aName =~ m/useSetExtensions/i);

	return undef;
}

#Split reading for DBLOG
#############################
sub KNX_DbLog_split($) {
	my ($event) = @_;
	my ($reading, $value, $unit);

	my $tempStr = join (", ", @_);
	Log (5, "splitFn - enter, attributes: $tempStr");
	
	#detect reading - real reading or state?
	my $isReading = "false"; 
	$isReading = "true" if ($event =~ m/: /);
	
	#split input-string
	my @strings = split (" ", $event);
	
	my $startIndex = undef;
	$unit = "";
	
	return undef if (not defined ($strings[0]));

	#real reading?
	if ($isReading =~ m/true/i)
	{
		#first one is always reading
		$reading = $strings[0];
		$reading =~ s/:?$//;
		$startIndex = 1;
	}
	#plain state
	else
	{
		#for reading state nothing is supplied
		$reading = "state";
		$startIndex = 0;	
	}
	
	return undef if (not defined ($strings[$startIndex]));

	#per default join all single pieces
	$value = join(" ", @strings[$startIndex..(int(@strings) - 1)]);
	
	#numeric value?
	#if ($strings[$startIndex] =~ /^[+-]?\d*[.,]?\d+/)
	if ($strings[$startIndex] =~ /^[+-]?\d*[.,]?\d+$/)
	{
		$value = $strings[$startIndex];
		#single numeric value? Assume second par is unit...
		if ((defined ($strings[$startIndex + 1])) && !($strings[$startIndex+1] =~ /^[+-]?\d*[.,]?\d+/)) 
		{
			$unit = $strings[$startIndex + 1] if (defined ($strings[$startIndex + 1]));
		}
	}

	#numeric value?
	#if ($strings[$startIndex] =~ /^[+-]?\d*[.,]?\d+/)
	#{
	#	$value = $strings[$startIndex];
	#	$unit = $strings[$startIndex + 1] if (defined ($strings[$startIndex + 1]));
	#}
	#string or raw
	#else
	#{
	#	$value = join(" ", @strings[$startIndex..(int(@strings) - 1)]);
	#}
		
	Log (5, "splitFn - READING: $reading, VALUE: $value, UNIT: $unit");
	
	return ($reading, $value, $unit);
}

#Handle incoming messages
#############################
sub
KNX_Parse($$) {
	my ($hash, $msg) = @_;
	my $name = $hash->{NAME};
	
	#Msg format: 
	#C(w/r/p)<group><value> i.e. Bw00000101
	#we will also take reply telegrams into account, 
	#as they will be sent if the status is asked from bus 	
	#split message into parts

	#old syntax
	#$msg =~ m/^$id(.{4})(.{1})(.{4})(.*)$/;
	#new syntax for extended adressing
	$msg =~ m/^$id(.{5})(.{1})(.{5})(.*)$/;
	my $src = $1;
	my $cmd = $2;
	my $dest = $3;
	my $val = $4;
	my $gadCode = $dest;
	
	my @foundMsgs;
	
	Log3 ($name, 5, "enter parse: hash: $hash name: $name, dest: $dest, msg: $msg");

	#gad not defined yet, give feedback for autocreate
	if (not (exists $modules{KNX}{defptr}{$gadCode}))
	{
		#format gat
		my $gad = KNX_hexToName($gadCode);	
		#create name
		my ($line, $area, $device) = split ("/", $gad);
		my $newDevName = sprintf("KNX_%.2d%.2d%.3d", $line, $area, $device);
		
		return "UNDEFINED $newDevName KNX $gad:$modelErr";		
	}
	
	#get list from device-hashes using given gadCode (==destination)
	my @deviceList = @{$modules{KNX}{defptr}{$gadCode}};	
	#process message for all affected devices and gad's

	#debug GAD-codes
	if (0)
	{		
		Log3 ($name, 5, "GAD: $gadCode");
		foreach my $dv (@{$modules{KNX}{defptr}{$gadCode}}) 
		{
			Log3 ($name, 5, "DEV: " . $dv->{NAME} . " (GAD: $gadCode)");
		}	
	}	

	foreach my $deviceHash (@deviceList)
	{
		#get details
		my $deviceName = $deviceHash->{NAME};
		my $gadName = $deviceHash->{GADTABLE}{$gadCode};
		my $model = $deviceHash->{GADDETAILS}{$gadName}{MODEL};
		my $option = $deviceHash->{GADDETAILS}{$gadName}{OPTION};			
		my $rdString = $deviceHash->{GADDETAILS}{$gadName}{RDNAMEGET};
		my $putString = $deviceHash->{GADDETAILS}{$gadName}{RDNAMEPUT};
		
		Log3 ($deviceName, 5, "parse: process message, device-name: $deviceName, rd-name: $gadName, gadCode: $gadCode, model: $model");			
		
		#########################
		#process message
		#
		#handle write and reply messages
		if ($cmd =~ /[w|p]/i)
		{
			#decode message
			my $transval = KNX_decodeByDpt ($deviceHash, $val, $gadName);
			#message invalid
			if (not defined($transval) or ($transval eq ""))
			{
				readingsBulkUpdate($deviceHash, "last-sender", KNX_hexToName($src));
				Log3 ($deviceName, 2, "parse device hash (wpi): $deviceHash name: $deviceName, message could not be decoded - see log for details");
				next;
			}

			Log3 ($deviceName, 5, "received hash (wpi): $deviceHash name: $deviceName, STATE: $transval, READING: $gadName, SENDER: $src");				

			#append post-string, if supplied
			my $suffix = AttrVal($deviceName, "format",undef);
			$transval = $transval . " " . $suffix if (defined($suffix));					
			#execute regex, if defined				
			my $regAttr = AttrVal($deviceName, "stateRegex", undef);
			my $state = KNX_replaceByRegex ($regAttr, $rdString . ":", $transval);
			
			Log3 ($deviceName, 5, "parse device hash (wpi): $deviceHash name: $deviceName - replaced $rdString:$transval to $state") if (not ($transval eq $state));					

			if (defined($state))
			{
				readingsBeginUpdate($deviceHash);
				readingsBulkUpdate($deviceHash, $rdString, $transval);
				readingsBulkUpdate($deviceHash, "last-sender", KNX_hexToName($src));
						
				#execute state-command if defined
				#must be placed after first readings, because it may have a reference
				#
				#hack for being backward compatible - serve $name
				$name = $deviceName;
				my $cmdAttr = AttrVal($deviceName, "stateCmd", undef);
				if (defined ($cmdAttr) and !($cmdAttr eq ""))
				{
					$state = eval $cmdAttr;
					Log3 ($deviceName, 5, "parse device hash (wpi): $deviceHash name: $deviceName - state replaced via command $cmdAttr - state: $state");
				}
				#reassign original name...
				$name = $hash->{NAME};
						
				readingsBulkUpdate($deviceHash, "state", $state);						
				readingsEndUpdate($deviceHash, 1);
			}								
		}
		#handle read messages
		elsif ($cmd =~ /[r]/)
		{
			if (defined ($option) and ($option =~ m/listenonly/i))
			{
				Log3 ($deviceName, 5, "received hash (r), ignored request due to option \"listenonly\"");
				next;
			}

			Log3 ($deviceName, 5, "received hash (r): $deviceHash name: $deviceName, GET");
			my $transval = undef;

			#answer "old school"
			my $value = undef;
			if (AttrVal($deviceName, "answerReading", 0) =~ m/1/)
			{
				my $putVal = ReadingsVal($deviceName, "putString", undef);
				
				if (defined ($putVal) and !($putVal eq ""))
				{	
					#medium priority, overwrite $value
					$value = $putVal;
				}
				else
				{
					#lowest priority - use state
					$value = ReadingsVal($deviceName, "state", undef) if (AttrVal($deviceName, "answerReading", 0) =~ m/1/);
				}
			}

			#high priority - eval
			###
			my $cmdAttr = AttrVal($deviceName, "putCmd", undef);
			if (defined ($cmdAttr) and !($cmdAttr eq ""))
			{			
				my $orgValue = $value;
				my $gad = $gadName;	
					
				#backup kontext
				my $orgHash = $hash;
				$hash = $deviceHash;
				
				eval $cmdAttr;
				if ($orgValue ne $value)
				{
					Log3 ($deviceName, 5, "parse device hash (r): $deviceHash name: $deviceName - put replaced via command $cmdAttr - value: $value");
					readingsSingleUpdate($deviceHash, $putString, $value,1);								
				}
				
				#restore kontext
				$hash = $orgHash;
			}
			###/

			#send transval
			if (defined($value))
			{
				$transval = KNX_encodeByDpt($deviceHash, $value, $gadName);
				Log3 ($deviceName, 5, "received, send answer hash: $deviceHash name: $deviceName, GET: $transval, READING: $gadName");				
				IOWrite ($deviceHash, "B", "p" . $gadCode . $transval);
			}
		}
								
		#skip, if this is ignored
		next if (IsIgnored($deviceName));
		#save to list
		push(@foundMsgs, $deviceName);
		#
		#/process message
		#########################
	}
	
	Log3 ($name, 5, "exit parse");
	
	#return values
	return @foundMsgs;
}

#Function is called at every notify
#############################
sub 
KNX_Notify($$)
{
	my ($ownHash, $callHash) = @_;
	#own name / hash
	my $ownName = $ownHash->{NAME};
	#Device that created the events
	my $callName = $callHash->{NAME}; 

	return undef;
}

#Private function to convert GAD from hex to readable version
#############################
sub
KNX_hexToName ($)
{
	my $v = shift;
	
	#old syntax
	#my $p1 = hex(substr($v,0,1));
	#my $p2 = hex(substr($v,1,1));
	#my $p3 = hex(substr($v,2,2));

	#new syntax for extended adressing
	my $p1 = hex(substr($v,0,2));
	my $p2 = hex(substr($v,2,1));
	my $p3 = hex(substr($v,3,2));
  
	my $r = sprintf("%d/%d/%d", $p1,$p2,$p3);
	
	return $r;
}

#Private function to convert GAD from readable version to hex
#############################
sub
KNX_nameToHex ($)
{
	my $v = shift;
	my $r = $v;

	if($v =~ /^([0-9]{1,2})\/([0-9]{1,2})\/([0-9]{1,3})$/) 
	{
		#old syntax
		#$r = sprintf("%01x%01x%02x",$1,$2,$3);
		#new syntax for extended adressing
		$r = sprintf("%02x%01x%02x",$1,$2,$3);
	}
	#elsif($v =~ /^([0-9]{1,2})\.([0-9]{1,2})\.([0-9]{1,3})$/) 
	#{
	#	$r = sprintf("%01x%01x%02x",$1,$2,$3);
	#}  
    
	return $r;
}

#Private function to clean input string according DPT
#############################
sub
KNX_checkAndClean ($$$)
{
	my ($hash, $value, $gadName) = @_;
	my $name = $hash->{NAME};
	my $orgValue = $value;
	
	Log3 ($name, 5, "check value: $value, gadName: $gadName");
	
	#get model
	my $model = $hash->{GADDETAILS}{$gadName}{MODEL};
	
	#return unchecked, if this is a autocreate-device
	return $value if ($model eq $modelErr);
	
	#get pattern
	my $pattern = $dpttypes{$model}{PATTERN};

	#trim whitespaces at the end
	$value =~ s/^\s+|\s+$//gi;

	#match against model pattern
	my @tmp = ($value =~ m/$pattern/gi);
	#loop through results
	my $found = 0;
	foreach my $str (@tmp) 
	{
		#assign first match and exit loop
		if (defined($str))
		{
			$found = 1;
			$value = $str;
			last;
		}
	}
	
	return undef if ($found == 0);

	#get min
	my $min = $dpttypes{"$model"}{MIN};
	#if min is numeric, cast to min
	$value = $min if (defined ($min) and ($min =~ /^[+-]?\d*[.,]?\d+/) and ($value < $min));

	#get max
	my $max = $dpttypes{"$model"}{MAX};
	#if max is numeric, cast to max
	$value = $max if (defined ($max) and ($max =~ /^[+-]?\d*[.,]?\d+/) and ($value > $max));

	Log3 ($name, 3, "check value: input-value $orgValue was casted to $value") if (not($orgValue eq $value));		
	Log3 ($name, 5, "check value: $value, gadName: $gadName, model: $model, pattern: $pattern");
	
	return $value;
}


#Private function to encode KNX-Message according DPT
#############################
sub
KNX_encodeByDpt ($$$) {
	my ($hash, $value, $gadName) = @_;
	my $name = $hash->{NAME};
	
	Log3 ($name, 5, "encode value: $value, gadName: $gadName");
	
	#get model
	my $model = $hash->{GADDETAILS}{$gadName}{MODEL};
	my $code = $dpttypes{$model}{CODE};
	
	#return unchecked, if this is a autocreate-device
	return undef if ($model eq $modelErr);

	#this one stores the translated value (readble)
	my $numval = undef;
	#this one stores the translated hex-value
	my $hexval = undef;
	
	Log3 ($name, 5, "encode model: $model, code: $code, value: $value");
		
	#get correction details
	my $factor = $dpttypes{$model}{FACTOR};
	my $offset = $dpttypes{$model}{OFFSET};
	
	#correct value
	$value /= $factor if (defined ($factor));
	$value -= $offset if (defined ($offset));
	
	Log3 ($name, 5, "encode normalized value: $value");
	
	#Binary value
	if ($code eq "dpt1")
	{
		$numval = "00" if ($value eq 0);
		$numval = "01" if ($value eq 1);
		$numval = "00" if ($value eq $dpttypes{$model}{MIN});
		$numval = "01" if ($value eq $dpttypes{$model}{MAX});
		
		$hexval = $numval;
	}
	#Step value (two-bit) 
	elsif ($code eq "dpt2")
	{
		$numval = "00" if ($value =~ m/off/i);
		$numval = "01" if ($value =~ m/on/i);
		$numval = "02" if ($value =~ m/forceoff/i);		
		$numval = "03" if ($value =~ m/forceon/i);
		
		$hexval = $numval;
	}	
	#Step value (four-bit) 
	elsif ($code eq "dpt3")
	{
		$numval = 0;
		
		#get dim-direction
		my $sign = 0;
		$sign = 1 if ($value >= 0);

		#trim sign
		$value =~ s/^-//g;

		#get dim-value
		$numval = 7 if ($value >= 1);
		$numval = 6 if ($value >= 3);
		$numval = 5 if ($value >= 6);
		$numval = 4 if ($value >= 12);
		$numval = 3 if ($value >= 25);
		$numval = 2 if ($value >= 50);
		$numval = 1 if ($value >= 75);
		
		#assign dim direction
		$numval += 8 if ($sign == 1);
		
		#get hex representation
		$hexval = sprintf("%.2x",$numval);
	}
	#1-Octet unsigned value
	elsif ($code eq "dpt5")
	{
		$numval = $value;
		$hexval = sprintf("00%.2x",($numval));
	}
	#1-Octet signed value
	elsif ($code eq "dpt6")
	{
		#build 2-complement
		$numval = $value;
		$numval += 0x100 if ($numval < 0);
		$numval = 0x00 if ($numval < 0x00);
		$numval = 0xFF if ($numval > 0xFF);
		
		#get hex representation
		$hexval = sprintf("00%.2x",$numval);
	}
	#2-Octet unsigned Value
	elsif ($code eq "dpt7")
	{
		$numval = $value;
		$hexval = sprintf("00%.4x",($numval));	
	}
	#2-Octet signed Value 
	elsif ($code eq "dpt8")
	{
		#build 2-complement
		$numval = $value;
		$numval += 0x10000 if ($numval < 0);
		$numval = 0x00 if ($numval < 0x00);
		$numval = 0xFFFF if ($numval > 0xFFFF);
		
		#get hex representation
		$hexval = sprintf("00%.4x",$numval);	
	}
	#2-Octet Float value
	elsif ($code eq "dpt9")
	{
		my $sign = ($value <0 ? 0x8000 : 0);
		my $exp  = 0;
		my $mant = 0;

		$mant = int($value * 100.0);
		while (abs($mant) > 0x7FF) 
		{
			$mant /= 2;
			$exp++;
		}
		$numval = $sign | ($exp << 11) | ($mant & 0x07ff);
		
		#get hex representation
		$hexval = sprintf("00%.4x",$numval);
	}
	#Time of Day
	elsif ($code eq "dpt10")
	{
		if ($value =~ m/now/i)
		{
			#get actual time
			my ($secs,$mins,$hours,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
			my $hoffset;
			
			#add offsets
			$year+=1900;
			$mon++;	
			# calculate offset for weekday
			$wday = 7 if ($wday eq "0");
			$hoffset = 32*$wday;
			$hours += $hoffset;
			
			$value = "$hours:$mins:$secs";
			$numval = $secs + ($mins<<8) + ($hours<<16);
		} else
		{
			my ($hh, $mm, $ss) = split (":", $value);
			$numval = $ss + ($mm<<8) + (($hh)<<16);
		}
			
		#get hex representation
		$hexval = sprintf("00%.6x",$numval);
	}
	#Date  
	elsif ($code eq "dpt11")
	{
		if ($value =~ m/now/i)
		{	
			#get actual time
			my ($secs,$mins,$hours,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
			my $hoffset;
			
			#add offsets
			$year+=1900;
			$mon++;	
			# calculate offset for weekday
			$wday = 7 if ($wday eq "0");
			
			$value = "$mday.$mon.$year";			
			$numval = ($year - 2000) + ($mon<<8) + ($mday<<16);		
		} else
		{
			my ($dd, $mm, $yyyy) = split (/\./, $value);
			
			if ($yyyy >= 2000)
			{
				$yyyy -= 2000;
			} else
			{
				$yyyy -= 1900;
			}
			
			$numval = ($yyyy) + ($mm<<8) + ($dd<<16);
		}
			
		#get hex representation
		$hexval = sprintf("00%.6x",$numval);
	}
	#4-Octet unsigned value (handled as dpt7)
	elsif ($code eq "dpt12")
	{
		$numval = $value;
		$hexval = sprintf("00%.8x",($numval));	
	}	
	#4-Octet Signed Value
	elsif ($code eq "dpt13")
	{
		#build 2-complement
		$numval = $value;
		$numval += 4294967296 if ($numval < 0);
		$numval = 0x00 if ($numval < 0x00);
		$numval = 0xFFFFFFFF if ($numval > 0xFFFFFFFF);
		
		#get hex representation
		$hexval = sprintf("00%.8x",$numval);		
	}  
	#4-Octet single precision float
	elsif ($code eq "dpt14")
	{
		$numval = unpack("L",  pack("f", $value));
		
		#get hex representation
		$hexval = sprintf("00%.8x",$numval);	
	}	
	#14-Octet String
	elsif ($code eq "dpt16")
	{
		#convert to latin-1
		$value = encode("iso-8859-1", decode("utf8", $value));
		
		#convert to hex-string
		my $dat = unpack "H*", $value;
		#format for 14-byte-length
		$dat = sprintf("%-028s",$dat);
		#append leading zeros
		$dat = "00" . $dat;
		
		$numval = $value;
		$hexval = $dat;
	} 
	#DateTime
	elsif ($code eq "dpt19")
	{
		if ($value =~ m/now/i)
		{
			#get actual time
			my ($secs,$mins,$hours,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
			my $hoffset;
			
			#add offsets
			$mon++;	
			# calculate offset for weekday
			$wday = 7 if ($wday eq "0");
			
			$hexval = 0;
			$hexval = sprintf ("00%.8x", (($secs<<16) + ($mins<<24) + ($hours<<32) + ($wday<<37) + ($mday<<40) + ($mon<<48) + ($year<<56)));
			
		} else
		{
			my ($date, $time) = split ('_', $value);
			my ($dd, $mm, $yyyy) = split (/\./, $date);
			my ($hh, $mi, $ss) = split (':', $time);

			#add offsets
			$yyyy -= 1900;  # year is based on 1900
			my $wday = 0;
			
			$hexval = 0;
			$hexval = sprintf ("00%.8x", (($ss<<16) + ($mi<<24) + ($hh<<32) + ($wday<<37) + ($dd<<40) + ($mm<<48) + ($yyyy<<56)));
		}
		$numval = 0;
	}	
	#RGB-Code
	elsif ($code eq "dpt232")
	{
		$hexval = "00" . $value;
		$numval = $value;
	}
	else
	{
		Log3 ($name, 2, "encode model: $model, no valid model defined");
		return undef;	
	}
	
	Log3 ($name, 5, "encode model: $model, code: $code, value: $value, numval: $numval, hexval: $hexval");
	return $hexval;
}

#Private function to replace state-values
#############################
sub
KNX_replaceByRegex ($$$) {
	my ($regAttr, $prefix, $input) = @_;
	my $retVal = $input;

	#execute regex, if defined
	if (defined($regAttr))
	{
		#get array of given attributes
		my @reg = split(" /", $regAttr);
		
		my $tempVal = $prefix . $input;
		
		#loop over all regex
		foreach my $regex (@reg)
		{
			#trim leading and trailing slashes
			$regex =~ s/^\/|\/$//gi;
			#get pairs
			my @regPair = split("\/", $regex);
						
			#skip if not at least 2 values supplied
			#next if (int(@regPair < 2));
			next if (not defined($regPair[0]));
			
			if (not defined ($regPair[1]))
			{
				#cut value
				$tempVal =~ s/$regPair[0]//gi;
			}
			else
			{
				#replace value
				$tempVal =~ s/$regPair[0]/$regPair[1]/gi;
			}
			
			#restore value
			$retVal = $tempVal;
		}
	}
	
	return $retVal;
}

#Private function to decode KNX-Message according DPT
#############################
sub
KNX_decodeByDpt ($$$) {
	my ($hash, $value, $gadName) = @_;
	my $name = $hash->{NAME};
	
	Log3 ($name, 5, "decode value: $value, gadName: $gadName");
	
	#get model
	my $model = $hash->{GADDETAILS}{$gadName}{MODEL};
	my $code = $dpttypes{$model}{CODE};
	
	#return unchecked, if this is a autocreate-device
	return undef if ($model eq $modelErr);

	#this one stores the translated value (readble)
	my $numval = undef;
	#this one contains the return-value
	my $state = undef;
	
	Log3 ($name, 5, "decode model: $model, code: $code, value: $value");
		
	#get correction details
	my $factor = $dpttypes{$model}{FACTOR};
	my $offset = $dpttypes{$model}{OFFSET};
	
	#Binary value
	if ($code eq "dpt1")
	{
		my $min = $dpttypes{"$model"}{MIN};
		my $max = $dpttypes{"$model"}{MAX};
		
		$numval = $min if ($value =~ m/00/i);
		$numval = $max if ($value =~ m/01/i);
		$state = $numval;
	}
	#Step value (two-bit) 
	elsif ($code eq "dpt2")
	{
		#get numeric value
		$numval = hex ($value);

		$state = "off" if ($numval == 0);
		$state = "on" if ($numval == 1);
		$state = "forceOff" if ($numval == 2);
		$state = "forceOn" if ($numval == 3);
	}	
	#Step value (four-bit) 
	elsif ($code eq "dpt3")
	{
		#get numeric value
		$numval = hex ($value);

		$state = 1 if ($numval & 7);
		$state = 3 if ($numval & 6);
		$state = 6 if ($numval & 5);
		$state = 12 if ($numval & 4);
		$state = 25 if ($numval & 3);
		$state = 50 if ($numval & 2);
		$state = 100 if ($numval & 1);
				
		#get dim-direction
		$state = 0 - $state if (not ($numval & 8));
		
		#correct value
		$state -= $offset if (defined ($offset));
		$state *= $factor if (defined ($factor));

		$state = sprintf ("%.0f", $state);
	}
	#1-Octet unsigned value
	elsif ($code eq "dpt5")
	{
		$numval = hex ($value);
		$state = $numval;
		
		#correct value
		$state -= $offset if (defined ($offset));
		$state *= $factor if (defined ($factor));

		$state = sprintf ("%.0f", $state);
	}
	#1-Octet signed value
	elsif ($code eq "dpt6")
	{
		$numval = hex ($value);
		$numval -= 0x100 if ($numval >= 0x80);
		$state = $numval;
		
		#correct value
		$state -= $offset if (defined ($offset));
		$state *= $factor if (defined ($factor));

		$state = sprintf ("%.0f", $state);		
	}
	#2-Octet unsigned Value
	elsif ($code eq "dpt7")
	{
		$numval = hex ($value);
		$state = $numval;
		
		#correct value
		$state -= $offset if (defined ($offset));
		$state *= $factor if (defined ($factor));

		$state = sprintf ("%.0f", $state);		
	}
	#2-Octet signed Value 
	elsif ($code eq "dpt8")
	{
		$numval = hex ($value);
		$numval -= 0x10000 if ($numval >= 0x8000);
		$state = $numval;
		
		#correct value
		$state -= $offset if (defined ($offset));
		$state *= $factor if (defined ($factor));
		
		$state = sprintf ("%.0f", $state);		
	}
	#2-Octet Float value
	elsif ($code eq "dpt9")
	{
		$numval = hex($value);
		my $sign = 1;
		$sign = -1 if(($numval & 0x8000) > 0);
		my $exp = ($numval & 0x7800) >> 11;
		my $mant = ($numval & 0x07FF);
		$mant = -(~($mant-1) & 0x07FF) if($sign == -1);
		$numval = (1 << $exp) * 0.01 * $mant;

		#correct value
		$state -= $offset if (defined ($offset));
		$state *= $factor if (defined ($factor));
		
		$state = sprintf ("%.2f","$numval");
	}
	#Time of Day
	elsif ($code eq "dpt10")
	{
		$numval = hex($value);
		my $hours = ($numval & 0x1F0000)>>16;
		my $mins  = ($numval & 0x3F00)>>8;
		my $secs  = ($numval & 0x3F);

		$state = sprintf("%02d:%02d:%02d",$hours,$mins,$secs);
	}
	#Date  
	elsif ($code eq "dpt11")
	{
		$numval = hex($value);
		my $day = ($numval & 0x1F0000) >> 16;
		my $month  = ($numval & 0x0F00) >> 8;
		my $year  = ($numval & 0x7F);
		#translate year (21st cent if <90 / else 20th century)
		$year += 1900 if($year >= 90);
		$year += 2000 if($year < 90);

		$state = sprintf("%02d.%02d.%04d",$day,$month,$year);
	}
	#4-Octet unsigned value (handled as dpt7)
	elsif ($code eq "dpt12")
	{
		$numval = hex ($value);
		$state = $numval;	
		
		#correct value
		$state -= $offset if (defined ($offset));
		$state *= $factor if (defined ($factor));

		$state = sprintf ("%.0f", $state);		
	}	
	#4-Octet Signed Value
	elsif ($code eq "dpt13")
	{
		$numval = hex ($value);
		$numval -= 4294967296 if ($numval >= 0x80000000);
		$state = $numval;
		
		#correct value
		$state -= $offset if (defined ($offset));
		$state *= $factor if (defined ($factor));

		$state = sprintf ("%.0f", $state);		
	}  
	#4-Octet single precision float
	elsif ($code eq "dpt14")
	{
		$numval = unpack "f", pack "L", hex ($value);
		
		#correct value
		$state -= $offset if (defined ($offset));
		$state *= $factor if (defined ($factor));
		
		$state = sprintf ("%.3f","$numval");
	}	
	#14-Octet String
	elsif ($code eq "dpt16")
	{
		$numval = 0;
		$state  = "";
		
		for (my $i = 0; $i < 14; $i++) 
		{
			my $c = hex(substr($value, $i * 2, 2));
			
			#exit at string terminator, otherwise append current char
			if (($i != 0) and ($c eq 0))
			{
				$i = 14;
			} 
			else 
			{
				$state .=  sprintf("%c", $c);
			}
		}

		#convert to latin-1
		$state = encode ("utf8", $state) if ($model =~ m/16.001/);		
	}
	#DateTime
	elsif ($code eq "dpt19")
	{
		$numval = $value;
		my $time = hex (substr ($value, 6, 6));
		my $date = hex (substr ($value, 0, 6));
		my $secs  = ($time & 0x3F) >> 0;
		my $mins  = ($time & 0x3F00) >> 8;
		my $hours = ($time & 0x1F0000) >> 16;
		my $day   = ($date & 0x1F) >> 0;
		my $month = ($date & 0x0F00) >> 8;
		my $year  = ($date & 0xFFFF0000) >> 16;		
		
		$year += 1900;
		$state = sprintf("%02d.%02d.%04d_%02d:%02d:%02d", $day, $month, $year, $hours, $mins, $secs);	
	}
	#RGB-Code
	elsif ($code eq "dpt232")
	{
		$numval = hex ($value);
		$state = $numval;

		$state = sprintf ("%.6x", $state);
	} 
	else
	{
		Log3 ($name, 2, "decode model: $model, no valid model defined");
		return undef;	
	}
	
	#append unit, if supplied
	my $unit = $dpttypes{$model}{UNIT};	
	$state = $state . " " . $unit if (defined ($unit) and not($unit eq ""));
		
	Log3 ($name, 5, "decode model: $model, code: $code, value: $value, numval: $numval, state: $state");
	return $state;
}

1;

=pod
=begin html

<p><a name="KNX"></a></p>
<h3>KNX</h3>
<p>KNX is a standard for building automation / home automation. It is mainly based on a twisted pair wiring, but also other mediums (ip, wireless) are specified.</p>
<p>For getting started, please refer to this document: <a href="http://www.knx.org/media/docs/Flyers/KNX-Basics/KNX-Basics_de.pdf">KNX-Basics</a></p>
<p>While the module <a href="#TUL">TUL</a> represents the connection to the KNX network, the KNX modules represent individual KNX devices. <br /> 
This module provides a basic set of operations (on, off, toggle, on-until, on-for-timer) to switch on/off KNX devices and to send values to the bus.&nbsp;</p>
<p>Sophisticated setups can be achieved by combining a number of KNX module instances. Therefore you can define a number of different GAD/DPT combinations per each device.</p>
<p>KNX defines a series of Datapoint Type as standard data types used to allow general interpretation of values of devices manufactured by different companies. These datatypes are used to interpret the status of a device, so the state in FHEM will then show the correct value.</p>
<p>For each received telegram there will be a reading with containing the received value and the sender address.<br /> 
For every set, there will be a reading containing the sent value.<br /> 
The reading &lt;state&gt; will be updated with the last sent or received value.&nbsp;</p>

<p>&nbsp;</p>
<p><strong>Define</strong></p>
<p><code>d</code><code>efine &lt;name&gt; KNX &lt;group&gt;:&lt;DPT&gt;:[gadName]:[set|get|readonly]:[nosuffix] [&lt;group&gt;:&lt;DPT&gt; ..] [IODev]</code></p>
<p><strong>Important:&nbsp;a KNX device needs at least one&nbsp;concrete DPT. Please refer to <a href="#KNXdpt">available DPT</a>. Otherwise the system cannot en- or decode the messages.</strong><br />
<strong> Devices defined by autocreate have to be reworked with the suitable dpt. Otherwise they won't be able to work productively.</strong></p>
<p>Examples:</p>
<pre style="padding-left: 30px;">define lamp1 KNX 0/10/11:dpt1:readonly</pre>
<pre style="padding-left: 30px;">define lamp2 KNX 0/10/12:dpt1:steuern 0/10/13:dpt1.001:status</pre>
<pre style="padding-left: 30px;">define lamp3 KNX 0A0D:dpt1.003 myTul</pre>
<p>The &lt;group&gt; parameters are either a group name notation (0-15/0-15/0-255) or the hex representation of the value (0-f0-f0-ff). All of the defined groups can be used for bus-communication. It is not allowed to have the same group more then once in one device. You can have several devices containing the same adresses.<br /> 
As described above the parameter &lt;DPT&gt; must contain the corresponding DPT.<br /> 
The optional parameteter [gadName] may contain an alias for the GAD.&nbsp;The name must not cotain one of the following strings: on, off, on-for-timer, on-until, off-for-timer, off-until, toggle, raw, rgb, string, value, set, get, readonly.<br />
If you want to restrict the GAD, you can raise the flags "get", "set", or "readonly". The usage should be self-explainable. It is not possible to combine the flags.<br /> 
Furthermore you can supply a IO-Device directly at startup. This can be done later on via attribute as well.</p>
<p>The GAD's are per default named with "g&lt;number&gt;". The correspunding readings are calles getG&lt;number&gt;, setG&lt;number&gt; and putG&lt;number&gt;.<br /> 
If you supply &lt;gadName&gt; this name is used instead. The readings are &lt;gadName&gt;-get, &lt;gadName&gt;-set and &lt;gadName&gt;-put. We will use the synonyms &lt;getName&gt;, &lt;setName&gt; and &lt;putName&gt; in this documentation.
If you add the option "nosuffix", &lt;getName&gt;, &lt;setName&gt; and &lt;putName&gt; have the identical name - only &lt;gadName&gt;.</p>
<p>Per default, the first group is used for sending. If you want to send via a different group, you have to address it it (set &lt;name&gt; &lt;gadName&gt; value).</p>
<p>Without further attributes, all incoming and outgoing messages are translated into reading &lt;state&gt;.</p>
<p>If enabled, the module <a href="#autocreate">autocreate</a> is creating a new definition for any unknown sender. The device itself will be NOT fully available, until you added a DPT to the definition. The name will be KNX_nnmmooo where nn is the line adress, mm the area and ooo the device.</p>

<p>&nbsp;</p>
<p><strong>Set</strong></p>
<p><code>set &lt;deviceName&gt; [gadName] &lt;on|off|toggle&gt;<br />
  set &lt;deviceName&gt; [gadName] &lt;on-for-timer|on-until|off-for-timer|off-until&gt;
&lt;timespec&gt;<br />
  set &lt;deviceName&gt; [gadName] &lt;value&gt;<br /></code></p>
<p>Set sends the given value to the bus.<br /> If &lt;gadName&gt; is omitted, the first listed GAD of the device is used. If the GAD is restricted in the definition with "get" or "readonly", the set-command will be refused.<br /> 
<strong>For dpt1 and dpt1.001 valid values are on, off and toggle. Also the timer-functions can be used. For all other binary DPT (dpt1.xxx) the min- and max-values are used for en- and decoding instead of on/off. This is different to older versions.</strong><br /> 
After successful sending the value, it is stored in the readings &lt;setName&gt;.</p>
<p>Example:</p>
<p><code></code></p>
<pre style="padding-left: 30px;">set lamp2 on</pre>
<pre style="padding-left: 30px;">set lamp2 off</pre>
<pre style="padding-left: 30px;">set lamp2 on-for-timer 10</pre>
<pre style="padding-left: 30px;">set lamp2 on-until 13:15:00</pre>
<pre style="padding-left: 30px;">set lamp2 steuern on-until 13:15:00</pre>
<pre style="padding-left: 30px;">set myThermoDev 23.44</pre>
<pre style="padding-left: 30px;">set my MessageDev Hallo Welt</pre>

<p>&nbsp;</p>
<p><strong>Get</strong></p>
<p>If you execute "get" for a KNX-Element the status will be requested a state from the device. The device has to be able to respond to a read - this is not given for all devices.<br /> 
If the GAD is restricted in the definition with "readonly", the execution will be refused.<br /> 
The answer from the bus-device is not shown in the toolbox, but is treated like a regular telegram.</p>

<p>&nbsp;</p>
<p><strong>Common attributes</strong></p>
<p><a href="#DbLogInclude">DbLogInclude</a><br /> 
<a href="#DbLogExclude">DbLogExclude</a><br /><a href="#IODev">IODev</a><br />
<a href="#alias">alias</a><br /> <a href="#alias">attributesExclude</a><br /> 
<a href="#alias">cmdIcon</a><br /> <a href="#comment">comment</a><br /> 
<a href="#devStateIcon">devStateIcon</a><br /> 
<a href="#devStateStyle">devStateStyle</a><br /> 
<a href="#do_not_notify">do_not_notify</a><br /> 
<a href="#event-aggregator">event-aggregator</a><br /> 
<a href="#event-min-interval">event-min-interval</a><br /> 
<a href="#event-on-change-reading">event-on-change-reading</a><br /> 
<a href="#event-on-update-reading">event-on-update-reading</a><br /> 
<a href="#eventMap">eventMap</a><br /> <a href="#group">group</a><br /> 
<a href="#icon">icon</a><br /> 
<a href="#room">room</a><br /> 
<a href="#showtime">showtime</a><br /> 
<a href="#sortby">sortby</a><br /> 
<a href="#stateCopy">stateCopy</a><br />
<a href="#stateFormat">stateFormat</a><br />
<a href="#supressReading">supressReading</a><br /> 
<a href="#timestamp-on-change-reading">timestamp-on-change-reading</a><br /> 
<a href="#userReadings">userReadings</a><br /> 
<a href="#userattr">userattr</a><br /> <a href="#verbose">verbose</a><br /> 
<a href="#webCmd">webCmd</a><br /> 
<a href="#webCmdLabel">webCmdLabel</a><br /> 
<a href="#widgetOverride">widgetOverride</a></p>

<p>&nbsp;</p>
<p><strong>Special attributes</strong></p>
<p><a name="KNXanswerReading"></a> <strong>answerReading</strong></p>
<ul>If enabled, FHEM answers on read requests. The content of reading &lt;state&gt; is send to the bus as answer. If supplied, the content of the reading &lt;putName&gt; is used to supply the data for the answer.</ul>
<p><a name="KNXstateRegex"></a> <strong>stateRegex</strong></p>
<ul>You can pass n pairs of regex-pattern and string to replace, seperated by a slash. Internally the "new" state is always in the format &lt;getName&gt;:&lt;state-value&gt;. The substitution is done every time, a new object is received. You can use this function for converting, adding units, having more fun with icons, ...</ul>
<ul>This function has only an impact on the content of state - no other functions are disturbed. It is executed directly after replacing the reading-names and setting the formats, but before stateCmd.</ul>
<p><a name="KNXstateCmd"></a> <strong>stateCmd</strong></p>
<ul>You can supply a perl-command for modifying state. This command is executed directly before updating the reading - so after renaming, format and regex. Please supply a valid perl command like using the attribute stateFormat.</ul>
<ul>Unlike stateFormat the stateCmd modifies also the content of the reading, not only the hash-conten for visualization.</ul>
<ul>You can access the device-hash directly in the perl string.</ul>
<p><a name="KNXputCmd"></a> <strong>putCmd</strong></p>
<ul>Every time a KNX-value is requested from the bus to FHEM, the content of putCmd is evaluated before the answer is send. You can supply a perl-command for modifying content. This command is executed directly before sending the data. A copy is stored in the reading &lt;putName&gt;.</ul>
<ul>Each device only knows one putCmd, so you have to take care about the different GAD's in the perl string.</ul>
<ul>Unlike in stateCmd you can not access the device hash in this perl string.</ul>
<p><a name="KNXformat"></a> <strong>format</strong></p>
<ul>The content of this attribute is added to every received value, before this is copied to state.</ul>

<p>&nbsp;</p>
<p><a name="KNXdpt"></a> <strong>DPT - datapoint-types</strong></p>
<p>The following dpt are implemented and have to be assigned within the device definition.</p>
<ul>dpt1 on, off</ul>
<ul>dpt1.000 1, 0</ul>
<ul>dpt1.001 on, off</ul>
<ul>dpt1.002 true, false</ul>
<ul>dpt1.003 enable, disable</ul>
<ul>dpt1.004 no ramp, ramp</ul>
<ul>dpt1.005 no alarm, alarm</ul>
<ul>dpt1.006 low, high</ul>
<ul>dpt1.007 decrease, increase</ul>
<ul>dpt1.008 up, down</ul>
<ul>dpt1.009 open, closed</ul>
<ul>dpt1.010 start, stop</ul>
<ul>dpt1.011 inactive, active</ul>
<ul>dpt1.012 not inverted, inverted</ul>
<ul>dpt1.013 start/stop, ciclically</ul>
<ul>dpt1.014 fixed, calculated</ul>
<ul>dpt1.015 no action, reset</ul>
<ul>dpt1.016 no action, acknowledge</ul>
<ul>dpt1.017 trigger, trigger</ul>
<ul>dpt1.018 not occupied, occupied</ul>
<ul>dpt1.019 closed, open</ul>
<ul>dpt1.021 logical or, logical and</ul>
<ul>dpt1.022 scene A, scene B</ul>
<ul>dpt1.023 move up/down, move and step mode</ul>
<ul>dpt2 on, off, forceOn, forceOff</ul>
<ul>dpt3 -100..+100</ul>
<ul>dpt5 0..255</ul>
<ul>dpt5.001 0..100 %</ul>
<ul>dpt5.003 0..360 &deg;</ul>
<ul>dpt5.004 0..255 %</ul>
<ul>dpt6 -127..+127</ul>
<ul>dpt6.001 0..100 %</ul>
<ul>dpt7 0..65535</ul>
<ul>dpt7.001 0..65535 s</ul>
<ul>dpt7.005 0..65535 s</ul>
<ul>dpt7.006 0..65535 m</ul>
<ul>dpt7.007 0..65535 h</ul>
<ul>dpt7.012 0..65535 mA</ul>
<ul>dpt7.013 0..65535 lux</ul>
<ul>dpt8 -32768..32768</ul>
<ul>dpt8.005 -32768..32768 s</ul>
<ul>dpt8.010 -32768..32768 %</ul>
<ul>dpt8.011 -32768..32768 &deg;</ul>
<ul>dpt9 -670760.0..+670760.0</ul>
<ul>dpt9.001 -670760.0..+670760.0 &deg;</ul>
<ul>dpt9.004 -670760.0..+670760.0 lux</ul>
<ul>dpt9.005 -670760.0..+670760.0 m/s</ul>
<ul>dpt9.006 -670760.0..+670760.0 Pa</ul>
<ul>dpt9.007 -670760.0..+670760.0 %</ul>
<ul>dpt9.008 -670760.0..+670760.0 ppm</ul>
<ul>dpt9.009 -670760.0..+670760.0 m&sup3;/h</ul>
<ul>dpt9.010 -670760.0..+670760.0 s</ul>
<ul>dpt9.021 -670760.0..+670760.0 mA</ul>
<ul>dpt9.024 -670760.0..+670760.0 kW</ul>
<ul>dpt9.025 -670760.0..+670760.0 l/h</ul>
<ul>dpt9.026 -670760.0..+670760.0 l/h</ul>
<ul>dpt9.028 -670760.0..+670760.0 km/h</ul>
<ul>dpt10 01:00:00</ul>
<ul>dpt11 01.01.2000</ul>
<ul>dpt12 0..+Inf</ul>
<ul>dpt13 -Inf..+Inf</ul>
<ul>dpt13.010 -Inf..+Inf Wh</ul>
<ul>dpt13.013 -Inf..+Inf kWh</ul>
<ul>dpt14 -Inf.0..+Inf.0</ul>
<ul>dpt14.019 -Inf.0..+Inf.0 A</ul>
<ul>dpt14.027 -Inf.0..+Inf.0 V</ul>
<ul>dpt14.033 -Inf.0..+Inf.0 Hz</ul>
<ul>dpt14.056 -Inf.0..+Inf.0 W</ul>
<ul>dpt14.057 -Inf.0..+Inf.0 cos&Phi;</ul>
<ul>dpt14.068 -Inf.0..+Inf.0 &deg;C</ul>
<ul>dpt14.076 -Inf.0..+Inf.0 m&sup3;</ul>
<ul>dpt16 String</ul>
<ul>dpt16.000 ASCII-String</ul>
<ul>dpt16.001 ISO-8859-1-String (Latin1)</ul>
<ul>dpt17.001 Scene number: 0..63</ul>
<ul>dpt19 01.12.2010_01:00:00</ul>
<ul>dpt232 RGB-Value RRGGBB</ul>

<p>&nbsp;</p>
<p><strong>More complex examples</strong></p>
<p>&nbsp;</p>
<p><em>Rollo:</em></p>
<pre>define rollo KNX 0/10/12:dpt1.008:wdw1 0/10/13:dpt1</pre>
<p>moves down rollo at window 1:</p>
<pre>set rollo wdw1 down</pre>
<p>moves up rollo at window 2:</p>
<pre>set rollo g2 on</pre>
<p>moves down rollo at window 2 for 5s:</p>
<pre>set rollo g2 off-for-timer 5</pre>
<p>&nbsp;</p>
<p><em>Object with feedback, icon showing transistions:</em></p>
<pre>define sps KNX 0/4/0:dpt1:steuern 0/4/1:dpt1:status</pre>
<pre>attr sps devStateIcon status-on:general_an:Aus status-off:general_aus:Ein steuern.*:hourglass:Aus</pre>
<pre>attr sps eventMap /steuern on:Ein/steuern off:Aus/</pre>
<pre>attr sps stateRegex /steuern-[sg]et:/steuern-/ /status-get:/status-/</pre>
<pre>attr sps webCmd Ein:Aus</pre>
<p>&nbsp;</p>
<p><em>Object with feedback, state is always showing status:</em></p>
<pre>define wasser_status KNX 11/3/0:dpt1.001:status:readonly 11/3/1:dpt1.001:steuern-auf 11/3/2:dpt1.001:steuern-zu</pre>
<pre>attr wasser_status devStateIcon on:general_an off:general_aus</pre>
<pre>attr wasser_status stateCmd {sprintf("%s", ReadingsVal($name,"status-get",""))}</pre>
<pre>attr wasser_status webCmd :</pre>
<p>&nbsp;</p>
<p><em>If requested, fhem answers content of GAD refVal to GAD temp, answer nothing to GAD humidity:</em></p>
<pre>define demo KNX 1/0/30:dpt9.001:temp 1/0/31:dpt9.001:humidity 1/0/32:dpt9:refVal</pre>
<pre>attr demo putCmd {$value= ReadingsNum("demo","temp",0,1) if ($gad =~ /temp/);;}</pre>
<p>&nbsp;</p>
<p><em>Time master:</em></p>
<pre>define timedev KNX 0/0/7:dpt10:time 0/0/8:dpt11:date 0/0/9:dpt19</pre>
<pre>attr timedev eventMap /time now:timeNow/</pre>
<pre>attr timedev webCmd value timeNow</pre>
<p>Sends actual time to the bus:</p>
<pre>set timedev now</pre>
<p>Sends actual date to the bus:</p>
<pre>set timedev date now</pre>
<p>Sends actual date and time to the bus (combinded):</p>
<pre>set timedev g3 now</pre>
<p>&nbsp;</p>
<p><em>Slider:</em></p>
<pre>define newTest KNX 15/2/2:dpt5</pre>
<pre>attr newTest webCmd g1</pre>
<pre>attr newTest widgetOverride g1:slider,0,5,100</pre>
<p>&nbsp;</p>
<p><em>Shows two independent slider and on/off buttons:</em></p>
<pre>define newTest KNX 15/2/9:dpt5 15/2/3:dpt5 15/2/2:dpt1.001:power</pre>
<pre>attr newTest IODev knxd</pre>
<pre>attr newTest eventMap {\</pre>
	<pre>  usr=>{\</pre>
		<pre>    '^getG1 (\d+)'=>'g1 $1',\</pre>
		<pre>    '^getG2 (\d+)'=>'g2 $1',\</pre>
		<pre>    '^An'=>'power on',\</pre>
		<pre>    '^Aus'=>'power off',\</pre>
	<pre>  },\</pre>
	<pre>  fw=>{\</pre>
		<pre>    '^getG1 (\d+)'=>'getG1',\</pre>
		<pre>    '^getG2 (\d+)'=>'getG2',\</pre>
		<pre>    '^power-get'=>'state',\</pre>
	<pre>  }\</pre>
<pre>}</pre>
<pre>attr newTest webCmd An:Aus::Label1:getG1::Label2:getG2</pre>
<pre>attr newTest widgetOverride getG1:slider,0,5,100 getG2:slider,0,5,100</pre>

=end html
=device
=item summary Communicates to KNX via module TUL

=cut
