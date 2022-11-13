# $Id$
########################################################################################################################
#
#     73_ElectricityCalculator.pm
#     Observes a reading of a device which represents the actual counter (e.g. OW_devive) 
#     acting as electricity meter, calculates the corresponding values and writes them back to 
#     the counter device.
#     Written and best viewed with Notepad++ v.6.8.6; Language Markup: Perl
#
#
#     Author                     : Matthias Deeke 
#     e-mail                     : matthias.deeke(AT)deeke(PUNKT)eu
#     Fhem Forum                 : https://forum.fhem.de/index.php/topic,57106.msg485195.html
#     Fhem Wiki                  : Not yet implemented
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
#     fhem.cfg: define <devicename> ElectricityCalculator <regexp>
#
#     Example 1:
#     define myElectricityCalculator ElectricityCalculator myElectricityCounter:CounterA.*
#
#
#
#
########################################################################################################################

########################################################################################################################
# List of open Problems / Issues:
#
#
#
#
#
#
#
########################################################################################################################

package main;
use strict;
use warnings;
use Time::Local;
use FHEM::Meta;
use Data::Dumper;
my %ElectricityCalculator_gets;
my %EolectricityCalculator_sets;

###START###### Initialize module ##############################################################################START####
sub ElectricityCalculator_Initialize($)
{
    my ($hash)  = @_;
	
    $hash->{STATE}				= "Init";
    $hash->{DefFn}				= "ElectricityCalculator_Define";
    $hash->{UndefFn}			= "ElectricityCalculator_Undefine";
    $hash->{GetFn}           	= "ElectricityCalculator_Get";
	$hash->{SetFn}           	= "ElectricityCalculator_Set";
    $hash->{AttrFn}				= "ElectricityCalculator_Attr";
	$hash->{NotifyFn}			= "ElectricityCalculator_Notify";
	$hash->{DbLog_splitFn}   	= "ElectricityCalculator_DbLog_splitFn";
	$hash->{NotifyOrderPrefix}	= "10-";   							# Want to be called before the rest

	$hash->{AttrList}       	= "disable:0,1 " .
								  "header " .
								  "ElectricityCounterOffset " .
								  "ElectricityKwhPerCounts " .
								  "BasicPricePerAnnum " .
								  "ElectricityPricePerKWh " .
								  "MonthlyPayment " .
								  "MonthOfAnnualReading " .
								  "ReadingDestination:CalculatorDevice,CounterDevice " .
								  "SiPrefixPower:W,kW,MW,GW " .
								  "Currency:&#8364;,&#163;,&#36; " .
								  "DecimalPlace:3,4,5,6,7 " .
								  $readingFnAttributes;
								  
								  
								  
	return FHEM::Meta::InitMod( __FILE__, $hash );
}
####END####### Initialize module ###############################################################################END#####

###START###### Activate module after module has been used via fhem command "define" ##########################START####
sub ElectricityCalculator_Define($$$)
{
	my ($hash, $def)              = @_;
	my ($name, $type, $RegEx, $RegExst) = split("[ \t]+", $def, 4);

	### Check whether regular expression has correct syntax
	if(!$RegEx || $RegExst) 
	{
		my $msg = "Wrong syntax: define <name> ElectricityCalculator device[:event]";
		return $msg;
	}

	### Check whether regular expression is misleading
	eval { "Hallo" =~ m/^$RegEx$/ };
	return "Bad regexp: $@" if($@);
	$hash->{REGEXP} = $RegEx;	

	### Writing values to global hash
	notifyRegexpChanged($hash, $RegEx);
	$hash->{NAME}							= $name;
	$hash->{STATE}              			= "active";
	$hash->{REGEXP}             			= $RegEx;
    
	### Convert SiPrefixPowerFactor 
	if(defined($attr{$hash}{SiPrefixPower})) 
	{
		if    ($attr{$hash}{SiPrefixPower} eq "W" ) {$hash->{system}{SiPrefixPowerFactor} = 1          ;}
		elsif ($attr{$hash}{SiPrefixPower} eq "kW") {$hash->{system}{SiPrefixPowerFactor} = 1000       ;}
		elsif ($attr{$hash}{SiPrefixPower} eq "MW") {$hash->{system}{SiPrefixPowerFactor} = 1000000    ;}
		elsif ($attr{$hash}{SiPrefixPower} eq "GW") {$hash->{system}{SiPrefixPowerFactor} = 1000000000 ;}
		else                                        {$hash->{system}{SiPrefixPowerFactor} = 1          ;}
	}
	else 
	{
                                                     $hash->{system}{SiPrefixPowerFactor} = 1;
	}

	### Convert Decimal Places 
	if(defined($attr{$hash}{DecimalPlace})) 
	{
		$hash->{system}{DecimalPlace} = "%." . $attr{$hash}{DecimalPlace} . "f";
	
	}
	else {
		$hash->{system}{DecimalPlace} = "%.3f";
	}
	
	### For debugging purpose only
	Log3 $name, 5, $name. " : ElectricityCalculator - RegEx                     : " . $RegEx;
	
	### Defining notify trigger
	notifyRegexpChanged($hash, $RegEx);
		
	### Writing log entry
	Log3 $name, 5, $name. " : ElectricityCalculator - Starting to define module";

	### Start timer for execution around midnight
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $EpochThisMidnight 			= Time::Local::timelocal_nocheck(0,0,0,$mday  ,$mon,$year);
	my $EpochNextMidnight 			= Time::Local::timelocal_nocheck(0,0,0,$mday+1,$mon,$year);
	my $SecondsToday 				= $EpochNextMidnight - $EpochThisMidnight;
	$hash->{system}{SecondsToday} 	= $SecondsToday;
	InternalTimer($EpochNextMidnight, "ElectricityCalculator_MidnightTimer", $hash, 0);

	### For debugging purpose only
	Log3 $name, 5, $name. " : ElectricityCalculator_MidnightTimer - time              : " . time();
	Log3 $name, 5, $name. " : ElectricityCalculator_MidnightTimer - year              : " . $year;
	Log3 $name, 5, $name. " : ElectricityCalculator_MidnightTimer - mon               : " . $mon;
	Log3 $name, 5, $name. " : ElectricityCalculator_MidnightTimer - day               : " . $mday;
	Log3 $name, 5, $name. " : ElectricityCalculator_MidnightTimer - nextMidnight      : " . $EpochNextMidnight;
	Log3 $name, 5, $name. " : ElectricityCalculator_MidnightTimer - SecondsToday      : " . $SecondsToday;

	return undef;
}
####END####### Activate module after module has been used via fhem command "define" ############################END#####


###START###### Deactivate module module after "undefine" command by fhem ######################################START####
sub ElectricityCalculator_Undefine($$)
{
	my ($hash, $def)  = @_;
	my $name = $hash->{NAME};	

	### Stop internal timer
	RemoveInternalTimer($hash);
	
	### Write log information
	Log3 $name, 3, $name. " ElectricityCalculator- The Electricity calculator has been undefined. Values corresponding to electricity meter will no longer calculated";
	
	return undef;
}
####END####### Deactivate module module after "undefine" command by fhem #######################################END#####


###START###### Handle attributes after changes via fhem GUI ###################################################START####
sub ElectricityCalculator_Attr(@)
{
	my @a                      = @_;
	my $name                   = $a[1];
	my $hash                   = $defs{$name};
	
	### Check whether "disable" attribute has been provided
	if ($a[2] eq "disable") 
	{
		if    ($a[3] eq 0)
		{	
			$hash->{STATE} = "active";
		}
		elsif ($a[3] eq 1)		
		{	
			$hash->{STATE} = "disabled";
		}
	}
	
	### Check whether "SiPrefixPower" attribute has been provided
	elsif ($a[2] eq "SiPrefixPower") 
	{
		if    ($a[3] eq "W" ) {$hash->{system}{SiPrefixPowerFactor} = 1          ;}
		elsif ($a[3] eq "kW") {$hash->{system}{SiPrefixPowerFactor} = 1000       ;}
		elsif ($a[3] eq "MW") {$hash->{system}{SiPrefixPowerFactor} = 1000000    ;}
		elsif ($a[3] eq "GW") {$hash->{system}{SiPrefixPowerFactor} = 1000000000 ;}
		else                  {$hash->{system}{SiPrefixPowerFactor} = 1          ;}
	}
	
	### Convert Decimal Places 
	elsif ($a[2] eq "DecimalPlace") 
	{
		if (($a[3] >= 3) && ($a[3] <= 8)) 
		{
			$hash->{system}{DecimalPlace} = "%." . $a[3] . "f";
		}
		else 
		{
			$hash->{system}{DecimalPlace} = "%.3f";
		}
	}

	return undef;
}
####END####### Handle attributes after changes via fhem GUI ####################################################END#####


###START###### Provide units for DbLog database via DbLog_splitFn #############################################START####
sub ElectricityCalculator_DbLog_splitFn($$)
{
	my ($event, $name)	= @_;
	my ($reading, $value, $unit);
    my $hash 			= $defs{$name};
	my @argument		= split("[ \t][ \t]*", $event);
	
	### Delete ":" and everything behind in readings name
	$argument[0] =~ s/:.*//;
 
	### Log entries for debugging
	#Log3 $name, 5, $name. " : ElectricityCalculator_DbLog_splitFn - Content of event                   : " . $event;
	#Log3 $name, 5, $name. " : ElectricityCalculator_splitFn - Content of argument[0]                   : " . $argument[0];
	#Log3 $name, 5, $name. " : ElectricityCalculator_splitFn - Content of argument[1]                   : " . $argument[1];

	### If the reading contains "_EnergyCost" or "_FinanceReserve"
	if (($argument[0] =~ /_EnergyCost/) || ($argument[0] =~ /_FinanceReserve/))
	{
		### Log entries for debugging
		#Log3 $name, 5, $name. " : ElectricityCalculator - DbLog_splitFn - EnergyCost-Reading detected      : " . $argument[0];
		
		### Get values being changed from hash
		$reading = $argument[0];
		$value   = $argument[1];
		$unit    = $attr{$hash}{Currency};
	}
	### If the reading contains "_Power"
	elsif ($argument[0] =~ /_Power/)
	{
		### Log entries for debugging
		#Log3 $name, 5, $name. " : ElectricityCalculator - DbLog_splitFn - Power-Reading detected           : " . $argument[0];
		
		### Get values being changed from hash
 		$reading = $argument[0];
		$value   = $argument[1];
		$unit    = $attr{$hash}{SiPrefixPower};
	}
	### If the reading contains "_Counter" or "_Last" or ("_Energy" but not "_EnergyCost") or "_PrevRead"
	elsif (($argument[0] =~ /_Counter/) || ($argument[0] =~ /_Last/) || (($argument[0] =~ /_Energy/) && ($argument[0] !~ /_EnergyCost/)) || ($argument[0] =~ /_PrevRead/))
	{
		### Log entries for debugging
		#Log3 $name, 5, $name. " : ElectricityCalculator - DbLog_splitFn - Counter/Energy-Reading detected  : " . $argument[0];
		
		### Get values being changed from hash
		$reading = $argument[0];
		$value   = $argument[1];
		$unit    = "kWh";
	}
	### If the reading is unknown
	else
	{
		### Log entries for debugging
		#Log3 $name, 5, $name. " : ElectricityCalculator - DbLog_splitFn - unspecified-Reading detected     : " . $argument[0];
		
		### Get values being changed from hash
		$reading = $argument[0];
		$value   = $argument[1];
		$unit    = "";
	}
	return ($reading, $value, $unit);
}
####END####### Provide units for DbLog database via DbLog_splitFn ##############################################END#####


###START###### Manipulate reading after "get" command by fhem #################################################START####
sub ElectricityCalculator_Get($@)
{
	my ( $hash, @a ) = @_;
	
	### If not enough arguments have been provided
	if ( @a < 2 )
	{
		return "\"set ElectricityCalculator\" needs at least one argument";
	}
		
	my $ElectricityCalcName = shift @a;
	my $reading  = shift @a;
	my $value = join(" ", @a);
	my $ReturnMessage;
	my @cList;

	### Create Log entries for debugging
	#Log3 $ElectricityCalcName, 5, $ElectricityCalcName. "_Get - reading         : " . $reading;
	#Log3 $ElectricityCalcName, 5, $ElectricityCalcName. "_Get - value           : " . $value;

	
	if(defined($hash->{READINGS})) {
		push(@cList, " "); 
		push(@cList, keys(%{$hash->{READINGS}}));
	}
	else {
		push(@cList, " "); 
	}

	### Create Log entries for debugging
	#Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - set list: " . join(" ", @cList);

	return "Unknown argument $reading, choose one of " . join(" ", @cList) if $reading eq '?';	
	
	if ( $reading ne "?")
	{
		### Write current value
		$value = ReadingsVal($ElectricityCalcName,  $reading, undef);
		
		### Create Log entries for debugging
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - get " . $reading . " with value: " . $value;

		### Create ReturnMessage
		$ReturnMessage = $value;
	}
	
	return($ReturnMessage);
}
####END####### Manipulate reading after "get" command by fhem ##################################################END#####

###START###### Manipulate reading after "set" command by fhem #################################################START####
sub ElectricityCalculator_Set($@)
{
	my ( $hash, @a ) = @_;
	
	### If not enough arguments have been provided
	if ( @a < 2 )
	{
		return "\"set ElectricityCalculator\" needs at least one argument";
	}
		
	my $ElectricityCalcName = shift @a;
	my $reading  = shift @a;
	my $value = join(" ", @a);
	my $ReturnMessage;
	my @cList;

	### Create Log entries for debugging
	#Log3 $ElectricityCalcName, 5, $ElectricityCalcName. "_Set - reading         : " . $reading;
	#Log3 $ElectricityCalcName, 5, $ElectricityCalcName. "_Set - value           : " . $value;

	### For Test purpose only
	#push(@cList, "Test"); 

	### Create set-List
	if(defined($hash->{READINGS})) {
		push(@cList, "SyncCounter"); 
		push(@cList, keys(%{$hash->{READINGS}}));
	}
	else {
		push(@cList, "SyncCounter"); 
	}

	### Create Log entries for debugging
	#Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - set list: " . join(" ", @cList);

	return "Unknown argument $reading, choose one of " . join(" ", @cList) if $reading eq '?';

	### If the command supposed to synchronize the CounterValues between CounterModule and CalculatorModule
	if ($reading eq "SyncCounter") {
		### Create Log entries for debugging
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " - Syncing Counter with :" . $value;
		
		### Serach for the ReadingsName of the Current CounterValue
		my @SearchResult = grep(/_CounterCurrent/, @cList);

		### Get current CalculatorValue
		my $CalculaterValueCurrent = ReadingsVal($ElectricityCalcName, $SearchResult[0], 0); 
		
		### Get current Offset from Attribute
		my $CounterOffsetCurrent =  AttrVal($ElectricityCalcName, "ElectricityCounterOffset", 0);

		### Calculate CounterValue
		my $CounterValueCurrent = $CalculaterValueCurrent - $CounterOffsetCurrent;
		
		### Calculate new Offset
		my $CounterOffsetNew = $value - $CounterValueCurrent;

		### Calculate Ceck
#		my $CounterValueNew = $CounterValueCurrent + $CounterOffsetNew;
		
		### Create Log entries for debugging
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " - Search Result               : " . Dumper(@SearchResult);
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " - CounterValueNew      Given  : " . $value;
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " - CounterValueCurrent  Result : " . $CalculaterValueCurrent;
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " - CounterOffsetCurrent Result : " . $CounterOffsetCurrent;
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " - CounterValueCurrent  Result : " . $CounterValueCurrent;
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " - CounterOffsetNew     Result : " . $CounterOffsetNew;
#		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " - CounterValueNew      Check  : " . $CounterValueNew;

		### Set new Offset in Attributes
		$attr{$ElectricityCalcName}{ElectricityCounterOffset} = $CounterOffsetNew;

		### Create ReturnMessage
		$ReturnMessage = $ElectricityCalcName . " - Successfully synchronized Counter and Calculator with : " . $value . " " . $attr{$hash}{SiPrefixPower};
	}
	### For Test purpose only
	# elsif ($reading eq "Test") 
	# {
		# ElectricityCalculator_MidnightTimer($hash);
	# }
	elsif ($reading ne "?")
	{
		### Create Log entries for debugging
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - set " . $reading . " with value: " . $value;
		
		### Write current value
		readingsSingleUpdate($hash, $reading, $value, 1);
		
		### Create ReturnMessage
		$ReturnMessage = $ElectricityCalcName . " - Successfully set " . $reading . " with value: " . $value;
	}
	
	return($ReturnMessage);
}
####END####### Manipulate reading after "set" command by fhem ##################################################END#####

###START###### Midnight Routine ###############################################################################START####
sub ElectricityCalculator_MidnightTimer($)
{
	### Define variables
	my ($ElectricityCalcDev)									= @_;
	my $ElectricityCalcName 									= $ElectricityCalcDev->{NAME};
 	my $RegEx													= $ElectricityCalcDev->{REGEXP};
	my ($ElectricityCountName, $ElectricityCountReadingRegEx)	= split(":", $RegEx, 2);
	my $ElectricityCountDev							  			= $defs{$ElectricityCountName};
	$ElectricityCountReadingRegEx						  		=~ s/[\.\*]+$//;
	$ElectricityCountReadingRegEx						  		=~ s/[:]+$//;
	my $ElectricityCountReadingRegExNeg							= $ElectricityCountReadingRegEx . "_";
	
	my @ElectricityCountReadingNameListComplete = keys(%{$ElectricityCountDev->{READINGS}});
	my @ElectricityCountReadingNameListFiltered;

	### Create Log entries for debugging purpose
	Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer ElectricityCountName: " . $ElectricityCountName;
	Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer RegEx               : " . $RegEx;
	Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer ReadingRegEx        : " . $ElectricityCountReadingRegEx;
	Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer ReadingRegExNeg     : " . $ElectricityCountReadingRegExNeg;

	### If no RegEx is available, leave routine
	if (($ElectricityCountReadingRegEx eq "") || ($ElectricityCountReadingRegExNeg eq "")) { 
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer                     : ERROR! No RegEx has been previously stored! Beaking midnight routine.";
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer ReadingRegEx        : " . $ElectricityCountReadingRegEx;
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer ReadingRegExNeg     : " . $ElectricityCountReadingRegExNeg;
		return;
	}
	
	### Check whether system failure threat is given or log error message
	eval {
		### For each valid RegEx entry given in the list of existing devices
		foreach my $ElectricityCountReadingName (@ElectricityCountReadingNameListComplete) {
			if (($ElectricityCountReadingName =~ m[$ElectricityCountReadingRegEx]) && ($ElectricityCountReadingName !~ m[$ElectricityCountReadingRegExNeg])) {
				push(@ElectricityCountReadingNameListFiltered, $ElectricityCountReadingName);
			}
		}
		1;
	} or do {
		my $ErrorMessage = $@;
		Log3 $ElectricityCalcName, 2, $ElectricityCalcName. " : Something went wrong with the RegEx : " . $ErrorMessage;
		return;
	};

	### Create Log entries for debugging purpose
	Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer__________________________________________________________";
	Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer                            : MidnightTimer initiated";
	Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - RegEx                    : " . $RegEx;
	Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - ReadingRegEx             : " . $ElectricityCountReadingRegEx;
	Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - ElectricityCountName     : " . $ElectricityCountName;
	Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - ElectricityCountReadComp : " . Dumper(@ElectricityCountReadingNameListComplete);
	Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - ElectricityCountReadList : " . Dumper(@ElectricityCountReadingNameListFiltered);
	

	### Remove internal timer for ElectricityCalculator_MidnightTimer
	RemoveInternalTimer($ElectricityCalcDev, "ElectricityCalculator_MidnightTimer");

	### Create Log entries for debugging purpose
	Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - Looping through every Counter defined by RegEx";
	
	foreach my $ElectricityCountReadingName (@ElectricityCountReadingNameListFiltered) {
		### Create Readings 
		my $ElectricityCalcReadingDestinationDeviceName;
		my $ElectricityCalcReadingPrefix;
		my $ElectricityCalcReadingDestinationDevice;

		if ($attr{$ElectricityCalcName}{ReadingDestination} eq "CalculatorDevice")
		{
			$ElectricityCalcReadingDestinationDeviceName	=  $ElectricityCalcName;
			$ElectricityCalcReadingPrefix					= ($ElectricityCountName . "_" . $ElectricityCountReadingName);
			$ElectricityCalcReadingDestinationDevice		=  $ElectricityCalcDev;

		}
		elsif ($attr{$ElectricityCalcName}{ReadingDestination} eq "CounterDevice")
		{
			$ElectricityCalcReadingPrefix 					=  $ElectricityCountReadingName;
			$ElectricityCalcReadingDestinationDevice		=  $ElectricityCountDev;
			$ElectricityCalcReadingDestinationDeviceName	=  $ElectricityCountName;
		}
		else
		{
			### Create Log entries for debugging
			Log3 $ElectricityCalcName, 3, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - Attribut ReadingDestination has not been set up correctly. Skipping event.";
			
			### Skipping event
			next;
		}
		
		my $ElectricityCounterReadingValue 					= ReadingsVal($ElectricityCountName,                              $ElectricityCountReadingName                              , "error");
		my $LastUpdateTimestampUnix                   		= ReadingsVal($ElectricityCalcReadingDestinationDeviceName, "." . $ElectricityCalcReadingPrefix . "_LastUpdateTimestampUnix", 0      );
	
		### Calculate time difference since last update
		my $DeltaTimeSinceLastUpdate = time() - $LastUpdateTimestampUnix ;

		### Create Log entries for debugging purpose
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer ___________Looping________________";
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - ReadingPrefix     : " . $ElectricityCalcReadingPrefix;
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - DeviceName        : " . $ElectricityCalcReadingDestinationDeviceName;
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - Timestamp now     : " . time();
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - Timestamp update  : " . $LastUpdateTimestampUnix;
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - Timestamp Delta   : " . $DeltaTimeSinceLastUpdate;


		### If the Readings for midnight settings have been provided
		if (($ElectricityCalcReadingPrefix ne "error") && ($ElectricityCalcReadingDestinationDeviceName ne "error") && ($LastUpdateTimestampUnix > 0)){

			### If there was no update in the last 24h
			if ( $DeltaTimeSinceLastUpdate >= $ElectricityCalcDev->{system}{SecondsToday}) {
				### Create Log entries for debugging purpose
				Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - Last Update       : No Update in the last day!";

			}
			else {
				### Create Log entries for debugging purpose
				Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - Last Update       : There was an Update in the last day!";
			}

			### Create Log entries for debugging purpose			
			#Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - ElectricityCalcRDD      : \n" . Dumper($ElectricityCalcReadingDestinationDevice);
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - ElectricityCounter: " . $ElectricityCounterReadingValue;
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - Pre PowerDaySum   : " . ReadingsVal($ElectricityCalcReadingDestinationDeviceName, "."  . 	$ElectricityCalcReadingPrefix . "_PowerDaySum",     	"error");
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - Pre PowerDayCount : " . ReadingsVal($ElectricityCalcReadingDestinationDeviceName, "."  . 	$ElectricityCalcReadingPrefix . "_PowerDayCount",     	"error");
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - Pre PowerCurrent  : " . ReadingsVal($ElectricityCalcReadingDestinationDeviceName, 		$ElectricityCalcReadingPrefix . "_PowerCurrent",     	"error");
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - Pre PowerDayAver  : " . ReadingsVal($ElectricityCalcReadingDestinationDeviceName, 		$ElectricityCalcReadingPrefix . "_PowerDayAver",     	"error");
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - Pre PowerDayMax   : " . ReadingsVal($ElectricityCalcReadingDestinationDeviceName, 		$ElectricityCalcReadingPrefix . "_PowerDayMax",    		"error");
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - Pre PowerDayMin   : " . ReadingsVal($ElectricityCalcReadingDestinationDeviceName, 		$ElectricityCalcReadingPrefix . "_PowerDayMin",     	"error");
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - Pre ConsumDay     : " . ReadingsVal($ElectricityCalcReadingDestinationDeviceName, 		$ElectricityCalcReadingPrefix . "_EnergyDay",     		"error");
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - Pre ConsumDayLast : " . ReadingsVal($ElectricityCalcReadingDestinationDeviceName, 		$ElectricityCalcReadingPrefix . "_EnergyDayLast",		"error");
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - Pre ConsumCstDay  : " . ReadingsVal($ElectricityCalcReadingDestinationDeviceName, 		$ElectricityCalcReadingPrefix . "_EnergyCostDay",		"error");
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - Pre ConsumCstDayL : " . ReadingsVal($ElectricityCalcReadingDestinationDeviceName, 		$ElectricityCalcReadingPrefix . "_EnergyCostDayLast",	"error");


			if ($ElectricityCounterReadingValue ne "error") {
				### Create Log entries for debugging purpose
				Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - Writing Device    : " . $ElectricityCountDev->{NAME};
				Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - Writing Reading   : " . $ElectricityCountReadingName;
				Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - Writing Value     : " . $ElectricityCounterReadingValue;
				
				### Writing Counter Value
				readingsSingleUpdate($ElectricityCountDev, $ElectricityCountReadingName, $ElectricityCounterReadingValue, 1);
			}
			else {
		
				Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - Writing Counter   : Error!";
			}
		}
		### If the Readings for midnight settings have not been provided
		else {
			### Warning Log entry
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - ERROR - There have no information stored about previous readings. Make sure the counter has been delivering at least 2 values to the Calculator device before next midnight!";
		}
	}

	### Start timer for execution around midnight
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) 	= localtime(time);
	my $EpochThisMidnight 										= Time::Local::timelocal_nocheck(0,0,0,$mday  ,$mon,$year);
	my $EpochNextMidnight 										= Time::Local::timelocal_nocheck(0,0,0,$mday+1,$mon,$year);
	my $SecondsToday 											= $EpochNextMidnight - $EpochThisMidnight;
	$ElectricityCalcDev->{system}{SecondsToday} 				= $SecondsToday;
	InternalTimer($EpochNextMidnight, "ElectricityCalculator_MidnightTimer", $ElectricityCalcDev, 0);
	
	### For debugging purpose only
	Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer _______Looping finished___________";
	Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator_MidnightTimer - nextMidnight      : " . $EpochNextMidnight;
}
####END####### Midnight Routine ########################################################################################END#####


###START###### Calculate Electricity meter values on changed events ###################################################START####
sub ElectricityCalculator_Notify($$)
{
	### Define variables
	my ($ElectricityCalcDev, $ElectricityCountDev)	= @_;
	my $ElectricityCalcName 						= $ElectricityCalcDev->{NAME};
	my $ElectricityCountName						= $ElectricityCountDev->{NAME};
	my $ElectricityCountNameEvents					= deviceEvents($ElectricityCountDev, 1);
	my $NumberOfChangedEvents						= int(@{$ElectricityCountNameEvents});
 	my $RegEx										= $ElectricityCalcDev->{REGEXP};

	### For debugging purpose only
	Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator Begin_________________________________________________________________________________________________________________________";
	Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - Notify - Trigger Dev Name                        : " . $ElectricityCountDev->{NAME};

	### Check whether the Electricity calculator has been disabled
	if(IsDisabled($ElectricityCalcName))
	{
		return undef;
	}
	
	### Check whether all required attributes has been provided and if not, create them with standard values
	if(!defined($attr{$ElectricityCalcName}{BasicPricePerAnnum}))
	{
		### Set attribute with standard value since it is not available
		$attr{$ElectricityCalcName}{BasicPricePerAnnum} 	= 0;

		### Writing log entry
		Log3 $ElectricityCalcName, 3, $ElectricityCalcName. " : ElectricityCalculator - The attribute BasicPricePerAnnum was missing and has been set to 0";
	}
	if(!defined($attr{$ElectricityCalcName}{ElectricityCounterOffset}))
	{
		### Set attribute with standard value since it is not available
		$attr{$ElectricityCalcName}{ElectricityCounterOffset} 		= 0;

		### Writing log entry
		Log3 $ElectricityCalcName, 3, $ElectricityCalcName. " : ElectricityCalculator - The attribute ElectricityCounterOffset was missing and has been set to 0";
	}
	if(!defined($attr{$ElectricityCalcName}{ElectricityKwhPerCounts}))
	{
		### Set attribute with standard value since it is not available
		$attr{$ElectricityCalcName}{ElectricityKwhPerCounts} 		= 1;

		### Writing log entry
		Log3 $ElectricityCalcName, 3, $ElectricityCalcName. " : ElectricityCalculator - The attribute ElectricityKwhPerCounts was missing and has been set to 1 counts/kWh";

	}
	if(!defined($attr{$ElectricityCalcName}{ElectricityPricePerKWh}))
	{
		### Set attribute with standard value since it is not available
		$attr{$ElectricityCalcName}{ElectricityPricePerKWh} 		= 0.2567;

		### Writing log entry
		Log3 $ElectricityCalcName, 3, $ElectricityCalcName. " : ElectricityCalculator - The attribute ElectricityPricePerKWh was missing and has been set to 0.2567 currency-unit/electric Energy-unit";
	}
	if(!defined($attr{$ElectricityCalcName}{MonthlyPayment}))
	{
		### Set attribute with standard value since it is not available
		$attr{$ElectricityCalcName}{MonthlyPayment} 		= 0;

		### Writing log entry
		Log3 $ElectricityCalcName, 3, $ElectricityCalcName. " : ElectricityCalculator - The attribute MonthlyPayment was missing and has been set to 0 currency-units";
	}
	if(!defined($attr{$ElectricityCalcName}{MonthOfAnnualReading}))
	{
		### Set attribute with standard value since it is not available
		$attr{$ElectricityCalcName}{MonthOfAnnualReading} 	= 5;

		### Writing log entry
		Log3 $ElectricityCalcName, 3, $ElectricityCalcName. " : ElectricityCalculator - The attribute MonthOfAnnualReading was missing and has been set to 5 which is the month May";
	}
	if(!defined($attr{$ElectricityCalcName}{Currency}))
	{
		### Set attribute with standard value since it is not available
		$attr{$ElectricityCalcName}{Currency} 	            = "&#8364;";

		### Writing log entry
		Log3 $ElectricityCalcName, 3, $ElectricityCalcName. " : ElectricityCalculator - The attribute Currency was missing and has been set to &#8364;";
	}
	if(!defined($attr{$ElectricityCalcName}{SiPrefixPower}))
	{
		### Set attribute with standard value since it is not available
		$attr{$ElectricityCalcName}{SiPrefixPower}         = "W";
		$ElectricityCalcDev->{system}{SiPrefixPowerFactor} = 1;
		
		### Writing log entry
		Log3 $ElectricityCalcName, 3, $ElectricityCalcName. " : ElectricityCalculator - The attribute SiPrefixPower was missing and has been set to W";
	}
	if(!defined($attr{$ElectricityCalcName}{ReadingDestination}))
	{
		### Set attribute with standard value since it is not available
		$attr{$ElectricityCalcName}{ReadingDestination}     = "CalculatorDevice";
		
		### Writing log entry
		Log3 $ElectricityCalcName, 3, $ElectricityCalcName. " : ElectricityCalculator - The attribute ReadingDestination was missing and has been set to CalculatorDevice";
	}
























	if(!defined($attr{$ElectricityCalcName}{room}))
	{
		if(defined($attr{$ElectricityCountName}{room}))
		{
			### Set attribute with standard value since it is not available
			$attr{$ElectricityCalcName}{room} 				= $attr{$ElectricityCountName}{room};

			### Writing log entry
			Log3 $ElectricityCalcName, 3, $ElectricityCalcName. " : ElectricityCalculator - The attribute room was missing and has been set to the same room of the electricity meter: " . $attr{$ElectricityCountName}{room};
		}
		else
		{
			### Set attribute with standard value since it is not available
			$attr{$ElectricityCalcName}{room} 				= "Electric Energy Counter";

			### Writing log entry
			Log3 $ElectricityCalcName, 3, $ElectricityCalcName. " : ElectricityCalculator - The attribute room was missing and has been set to Electric Energy Counter";
		}
	}
	if(!defined($attr{$ElectricityCalcName}{DecimalPlace}))
	{
		### Set attribute with standard value since it is not available
		$attr{$ElectricityCalcName}{DecimalPlace}         = 3;
		$ElectricityCalcDev->{system}{DecimalPlace} = "%.3f";
		
		### Writing log entry
		Log3 $ElectricityCalcName, 3, $ElectricityCalcName. " : ElectricityCalculator - The attribute DecimalPlace was missing and has been set to 3";
	}

	### For each feedback on in the array of defined regexpression which has been changed
	for (my $i = 0; $i < $NumberOfChangedEvents; $i++) 
	{
		### Extract event
		my $s = $ElectricityCountNameEvents->[$i];

		### Filtering all events which do not match the defined regex
		if(!defined($s))
		{
			next;
		}
		my ($ElectricityCountReadingName, $ElectricityCountReadingValueCurrent) = split(": ", $s, 2); # resets $1
		if("$ElectricityCountName:$s" !~ m/^$RegEx$/)
		{
			next;
		}
		
		### Extracting value
		if(defined($1)) 
		{
			my $RegExArg = $1;

			if(defined($2)) 
			{
				$ElectricityCountReadingName = $1;
				$RegExArg = $2;
			}

			$ElectricityCountReadingValueCurrent = $RegExArg if(defined($RegExArg) && $RegExArg =~ m/^(-?\d+\.?\d*)/);
		}
		if(!defined($ElectricityCountReadingValueCurrent) || $ElectricityCountReadingValueCurrent !~ m/^(-?\d+\.?\d*)/)
		{
			next;
		}
		
		###Get current Counter and transform in electric Energy (kWh) as read on mechanic Electricity meter
		   $ElectricityCountReadingValueCurrent      = $1 * $attr{$ElectricityCalcName}{ElectricityKwhPerCounts} + $attr{$ElectricityCalcName}{ElectricityCounterOffset};
		my $ElectricityCountReadingTimestampCurrent  = ReadingsTimestamp($ElectricityCountName,$ElectricityCountReadingName,0);		

		### Create Log entries for debugging
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator Begin_______________________________________________________________________________________________________________________________";

		### Create name and destination device for general reading prefix
		my $ElectricityCalcReadingPrefix;
		my $ElectricityCalcReadingDestinationDevice;
		my $ElectricityCalcReadingDestinationDeviceName;
		if ($attr{$ElectricityCalcName}{ReadingDestination} eq "CalculatorDevice")
		{
			$ElectricityCalcReadingPrefix					= ($ElectricityCountName . "_" . $ElectricityCountReadingName);
			$ElectricityCalcReadingDestinationDevice		=  $ElectricityCalcDev;
			$ElectricityCalcReadingDestinationDeviceName	=  $ElectricityCalcName;

			### Create Log entries for debugging
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - Attribut ReadingDestination has been set to CalculatorDevice";			
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCalcReadingPrefix                     : " . $ElectricityCalcReadingPrefix;
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCalcReadingDestinationDevice          : " . $ElectricityCalcReadingDestinationDevice;
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCalcReadingDestinationDeviceName      : " . $ElectricityCalcReadingDestinationDeviceName;

		}
		elsif ($attr{$ElectricityCalcName}{ReadingDestination} eq "CounterDevice")
		{
			$ElectricityCalcReadingPrefix 					=  $ElectricityCountReadingName;
			$ElectricityCalcReadingDestinationDevice		=  $ElectricityCountDev;
			$ElectricityCalcReadingDestinationDeviceName	=  $ElectricityCountName;

			### Create Log entries for debugging
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - Attribut ReadingDestination has been set to CounterDevice";
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCalcReadingPrefix                     : " . $ElectricityCalcReadingPrefix;
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCalcReadingDestinationDevice          : " . $ElectricityCalcReadingDestinationDevice;
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCalcReadingDestinationDeviceName      : " . $ElectricityCalcReadingDestinationDeviceName;
		}
		else
		{
			### Create Log entries for debugging
			Log3 $ElectricityCalcName, 3, $ElectricityCalcName. " : ElectricityCalculator - Attribut ReadingDestination has not been set up correctly. Skipping event.";
			
			### Skipping event
			next;
		}
		
		### Save Destination of readings into hidden readings
		readingsSingleUpdate($ElectricityCalcDev, ".ReadingDestinationDeviceName",	$ElectricityCalcReadingDestinationDeviceName,	0);
		
		### Restore previous Counter and if not available define it with "undef"
		my $ElectricityCountReadingTimestampPrevious =    ReadingsTimestamp($ElectricityCalcReadingDestinationDeviceName,  "." . $ElectricityCalcReadingPrefix . "_PrevRead", undef);
		my $ElectricityCountReadingValuePrevious     =          ReadingsVal($ElectricityCalcReadingDestinationDeviceName,  "." . $ElectricityCalcReadingPrefix . "_PrevRead", undef);
		my $ElectricityCountReadingLastChangeDelta   = time() - ReadingsVal($ElectricityCalcReadingDestinationDeviceName,  "." . $ElectricityCalcReadingPrefix . "_LastUpdateTimestampUnix", undef);

		### Create Log entries for debugging
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - LastUpdateTimestampUnix                          : " . ReadingsVal($ElectricityCalcReadingDestinationDeviceName,  "." . $ElectricityCalcReadingPrefix . "_LastUpdateTimestampUnix", "No Value provided");
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCountReadingLastChangeDeltaSeconds    : " . $ElectricityCountReadingLastChangeDelta;
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCountReadingValuePrevious             : " . $ElectricityCountReadingValuePrevious;
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCalcReadingPrefix                     : " . $ElectricityCalcReadingPrefix;

		### Find out whether there has been a previous value being stored
		if(defined($ElectricityCountReadingValuePrevious))
		{
			### Write current electric Energy as previous Electric Energy for future use in the ElectricityCalc-Device
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, "." . $ElectricityCalcReadingPrefix. "_PrevRead", sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCountReadingValueCurrent)),1);

			### Create Log entries for debugging
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - Previous value found. Continuing with calculations";
		}
		### If not: save value and quit loop
		else
		{
			### Write current electric Energy as previous Value for future use in the ElectricityCalc-Device
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, "." . $ElectricityCalcReadingPrefix. "_PrevRead", sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCountReadingValueCurrent)),1);

			### Save current Electricity Consumption as first reading of day = first after midnight and reset min, max value, value counter and value sum
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice,       $ElectricityCalcReadingPrefix . "_CounterDay1st",        sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCountReadingValueCurrent)),1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice,       $ElectricityCalcReadingPrefix . "_CounterDayLast",       sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCountReadingValueCurrent)),1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice,       $ElectricityCalcReadingPrefix . "_CounterMonth1st",      sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCountReadingValueCurrent)),1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice,       $ElectricityCalcReadingPrefix . "_CounterMonthLast",     sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCountReadingValueCurrent)),1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice,       $ElectricityCalcReadingPrefix . "_CounterMeter1st",      sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCountReadingValueCurrent)),1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice,       $ElectricityCalcReadingPrefix . "_CounterMeterLast",     sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCountReadingValueCurrent)),1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice,       $ElectricityCalcReadingPrefix . "_CounterYear1st",       sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCountReadingValueCurrent)),1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice,       $ElectricityCalcReadingPrefix . "_CounterYearLast",      sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCountReadingValueCurrent)),1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, "." . $ElectricityCalcReadingPrefix . "_PowerDaySum",          0, 1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, "." . $ElectricityCalcReadingPrefix . "_PowerDayCount",        0, 1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice,       $ElectricityCalcReadingPrefix . "_PowerDayMin",          0, 1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice,       $ElectricityCalcReadingPrefix . "_PowerDayMax",          0, 1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, "." . $ElectricityCalcReadingPrefix . "_LastUpdateTimestampUnix", time(), 0);

			### Create Log entries for debugging
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - Previous value NOT found. Skipping Loop";
			
			### Jump out of loop since there is nothing to do anymore than to wait for the next value
			next;
		}

		###### Find out whether the device has been freshly defined and certain readings have never been set up yet or certain readings have been deleted
		### Find out whether the reading for the daily start value has not been written yet 
		if(!defined(ReadingsVal($ElectricityCalcReadingDestinationDeviceName,  $ElectricityCalcReadingPrefix . "_CounterDay1st", undef)))
		{
			### Create Log entries for debugging
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - _CounterDay1st value NOT found!";			
	
			### Save current electric Energy as first reading of day = first after midnight and reset min, max value, value counter and value sum
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice,       $ElectricityCalcReadingPrefix . "_CounterDay1st",  $ElectricityCountReadingValueCurrent,  1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice,       $ElectricityCalcReadingPrefix . "_CounterDayLast", $ElectricityCountReadingValuePrevious, 1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, "." . $ElectricityCalcReadingPrefix . "_PowerDaySum",   0, 1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, "." . $ElectricityCalcReadingPrefix . "_PowerDayCount", 0, 1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice,       $ElectricityCalcReadingPrefix . "_PowerDayMin",   0, 1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice,       $ElectricityCalcReadingPrefix . "_PowerDayMax",   0, 1);

			### Create Log entries for debugging
			Log3 $ElectricityCalcName, 3, $ElectricityCalcName. " : ElectricityCalculator - Reading for the first daily value was not available and therfore reading and statistics have been written";
		}
		### Find out whether the reading for the monthly start value has not been written yet 
		if(!defined(ReadingsVal($ElectricityCalcReadingDestinationDeviceName,  $ElectricityCalcReadingPrefix . "_CounterMonth1st", undef)))
		{
			### Save current electric Energy as first reading of month
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_CounterMonth1st",  $ElectricityCountReadingValueCurrent,  1);	
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_CounterMonthLast", $ElectricityCountReadingValuePrevious, 1);

			### Create Log entries for debugging
			Log3 $ElectricityCalcName, 3, $ElectricityCalcName. " : ElectricityCalculator - Reading for the first monthly value was not available and therfore reading has been written";
			}
		### Find out whether the reading for the meter reading year value has not been written yet 
		if(!defined(ReadingsVal($ElectricityCalcReadingDestinationDeviceName,  $ElectricityCalcReadingPrefix . "_CounterMeter1st", undef)))
		{	
			### Save current electric Energy as first reading of month where Electricity-meter is read
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_CounterMeter1st",  $ElectricityCountReadingValueCurrent,  1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_CounterMeterLast", $ElectricityCountReadingValuePrevious, 1);

			### Create Log entries for debugging
			Log3 $ElectricityCalcName, 3, $ElectricityCalcName. " : ElectricityCalculator - Reading for the first value of Electricity meter year was not available and therfore reading has been written";
		}
		### Find out whether the reading for the yearly value has not been written yet 
		if(!defined(ReadingsVal($ElectricityCalcReadingDestinationDeviceName,  $ElectricityCalcReadingPrefix . "_CounterYear1st", undef)))
		{	
			### Save current electric Energy as first reading of the calendar year
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_CounterYear1st",  $ElectricityCountReadingValueCurrent,  1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_CounterYearLast", $ElectricityCountReadingValuePrevious, 1);

			### Create Log entries for debugging
			Log3 $ElectricityCalcName, 3, $ElectricityCalcName. " : ElectricityCalculator - Reading for the first yearly value was not available and therfore reading has been written";
		}
		
		### Extracting year, month and day as numbers
		my $ElectricityCountReadingTimestampPreviousRelative = time_str2num($ElectricityCountReadingTimestampPrevious);
		my($ElectricityCountReadingTimestampPreviousSec,$ElectricityCountReadingTimestampPreviousMin,$ElectricityCountReadingTimestampPreviousHour,$ElectricityCountReadingTimestampPreviousMday,$ElectricityCountReadingTimestampPreviousMon,$ElectricityCountReadingTimestampPreviousYear,$ElectricityCountReadingTimestampPreviousWday,$ElectricityCountReadingTimestampPreviousYday,$ElectricityCountReadingTimestampPreviousIsdst)	= localtime($ElectricityCountReadingTimestampPreviousRelative);
		my $ElectricityCountReadingTimestampCurrentRelative  = time_str2num($ElectricityCountReadingTimestampCurrent);
		my($ElectricityCountReadingTimestampCurrentSec,$ElectricityCountReadingTimestampCurrentMin,$ElectricityCountReadingTimestampCurrentHour,$ElectricityCountReadingTimestampCurrentMday,$ElectricityCountReadingTimestampCurrentMon,$ElectricityCountReadingTimestampCurrentYear,$ElectricityCountReadingTimestampCurrentWday,$ElectricityCountReadingTimestampCurrentYday,$ElectricityCountReadingTimestampCurrentIsdst)			= localtime($ElectricityCountReadingTimestampCurrentRelative);
		
		### Correct current month by one month since Unix/Linux start January with 0 instead of 1
		$ElectricityCountReadingTimestampCurrentMon = $ElectricityCountReadingTimestampCurrentMon + 1;
		
		### Create Log entries for debugging
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - Reading Name                                     : " . $ElectricityCountReadingName;
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - Previous Reading Value                           : " . $ElectricityCountReadingTimestampPrevious;
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - Current Reading Value                            : " . $ElectricityCountReadingTimestampCurrent;
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - Previous Reading Value                           : " . $ElectricityCountReadingValuePrevious;
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - Current Reading Value                            : " . $ElectricityCountReadingValueCurrent;
		
		####### Check whether Initial readings needs to be written
		### Check whether the current value is the first one after change of day = First one after midnight or if last update is older than 1 day
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCountReadTimeCurHour                  : " . $ElectricityCountReadingTimestampCurrentHour;
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCountReadTimePrevHour                 : " . $ElectricityCountReadingTimestampPreviousHour;
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - LastUpdateTimestampUnix                          : " . ReadingsVal($ElectricityCalcReadingDestinationDeviceName,  "." . $ElectricityCalcReadingPrefix . "_LastUpdateTimestampUnix", undef);
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCountReadTimeRelDelta                 : " . $ElectricityCountReadingLastChangeDelta;

		if (($ElectricityCountReadingTimestampCurrentHour < $ElectricityCountReadingTimestampPreviousHour) || ($ElectricityCountReadingLastChangeDelta > $ElectricityCalcDev->{system}{SecondsToday}))
		{
			### Create Log entries for debugging
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - First reading of day detected OR last reading is older than 1 day!";

			### Recalculate new dayspan in seconds
			my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) 	= localtime(time);
			my $EpochThisMidnight 										= Time::Local::timelocal_nocheck(0,0,0,$mday  ,$mon,$year);
			my $EpochNextMidnight 										= Time::Local::timelocal_nocheck(0,0,0,$mday+1,$mon,$year);
			my $SecondsToday 											= $EpochNextMidnight - $EpochThisMidnight;
			$ElectricityCalcDev->{system}{SecondsToday} 				= $SecondsToday;

			### Calculate Electricity energy of previous day � = (Wprevious[kWh] - WcurrentDay[kWh]) 
			my $ElectricityCalcEnergyDayLast      = ($ElectricityCountReadingValuePrevious - ReadingsVal($ElectricityCalcReadingDestinationDeviceName, $ElectricityCalcReadingPrefix . "_CounterDay1st", "0"));
			### Calculate pure Electricity cost of previous day ElectricityCalcEnergyDayLast * Price per kWh
			my $ElectricityCalcEnergyCostDayLast  = $ElectricityCalcEnergyDayLast * $attr{$ElectricityCalcName}{ElectricityPricePerKWh};
			### Reload last Power Value
			my $ElectricityCalcPowerCurrent = ReadingsVal($ElectricityCalcReadingDestinationDeviceName, $ElectricityCalcReadingPrefix . "_PowerCurrent", "0");
			
			### Save Electricity pure cost of previous day, current electric Energy as first reading of day = first after midnight and reset min, max value, value counter and value sum
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice,        $ElectricityCalcReadingPrefix . "_EnergyCostDayLast",  (sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcEnergyCostDayLast     ))), 1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice,        $ElectricityCalcReadingPrefix . "_EnergyDayLast",      (sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcEnergyDayLast         ))), 1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice,        $ElectricityCalcReadingPrefix . "_CounterDay1st",      (sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCountReadingValueCurrent  ))), 1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice,        $ElectricityCalcReadingPrefix . "_CounterDayLast",     (sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCountReadingValuePrevious ))), 1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice,  "." . $ElectricityCalcReadingPrefix . "_PowerDaySum",        0                                                          , 1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice,  "." . $ElectricityCalcReadingPrefix . "_PowerDayCount",      0                                                          , 1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice,        $ElectricityCalcReadingPrefix . "_PowerDayMin",        (sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcPowerCurrent          ))), 1);
			readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice,        $ElectricityCalcReadingPrefix . "_PowerDayMax",        0                                                          , 1);
			
			### Check whether the current value is the first one after change of month
			if ($ElectricityCountReadingTimestampCurrentMday < $ElectricityCountReadingTimestampPreviousMday)
			{
				### Create Log entries for debugging
				Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - First reading of month detected";

				### Calculate Electricity energy of previous month � = (Wprevious[kWh] - W1stReadMonth[kWh]) 
				my $ElectricityCalcEnergyMonthLast     = ($ElectricityCountReadingValuePrevious - ReadingsVal($ElectricityCalcReadingDestinationDeviceName, $ElectricityCalcReadingPrefix . "_CounterMonth1st", "0"));
				### Calculate pure Electricity cost of previous month ElectricityCalcEnergyMonthLast * Price per kWh
				my $ElectricityCalcEnergyCostMonthLast = $ElectricityCalcEnergyMonthLast * $attr{$ElectricityCalcName}{ElectricityPricePerKWh};
				### Save Electricity energy and pure cost of previous month
				readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_EnergyCostMonthLast",   (sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcEnergyCostMonthLast   ))), 1);
				readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_EnergyMonthLast", (sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcEnergyMonthLast       ))), 1);
				readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_CounterMonth1st", (sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCountReadingValueCurrent  ))), 1);
				readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_CounterMonthLast", (sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCountReadingValuePrevious ))), 1);

				
				### Check whether the current value is the first one of the meter-reading month
				if ($ElectricityCountReadingTimestampCurrentMon eq $attr{$ElectricityCalcName}{MonthOfAnnualReading})
				{
					### Create Log entries for debugging
					Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - First reading of month for meter reading detected";
					Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - Current month is                  : " . $ElectricityCountReadingTimestampCurrentMon;
					Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - Attribute MonthOfAnnualReading is : " . $attr{$ElectricityCalcName}{MonthOfAnnualReading};
					Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - Counter1stMeter  is               : " . $ElectricityCountReadingValueCurrent;
					Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - CounterLastMeter is               : " . $ElectricityCountReadingValuePrevious;
					
					### Calculate Electricity energy of previous meter reading year � = (Wprevious[kWh] - WcurrentMeter[kWh])
					my $ElectricityCalcEnergyMeterLast = ($ElectricityCountReadingValuePrevious - ReadingsVal($ElectricityCalcReadingDestinationDeviceName, $ElectricityCalcReadingPrefix . "_CounterMeter1st", "0"));
					### Calculate pure Electricity cost of previous meter reading year � = ElectricityCalcEnergyMeterLast * Price per kWh
					my $ElectricityCalcEnergyCostMeterLast = $ElectricityCalcEnergyMeterLast * $attr{$ElectricityCalcName}{ElectricityPricePerKWh};
					
					### Save Electricity energy and pure cost of previous meter year
					readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_EnergyCostMeterLast", (sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcEnergyCostMeterLast   ))), 1);
					readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_EnergyMeterLast",     (sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcEnergyMeterLast       ))), 1);
					readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_CounterMeter1st",     (sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCountReadingValueCurrent  ))), 1);
					readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_CounterMeterLast",    (sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCountReadingValuePrevious ))), 1);
				}

				### Check whether the current value is the first one of the calendar year
				if ($ElectricityCountReadingTimestampCurrentYear > $ElectricityCountReadingTimestampPreviousYear)
				{
					### Create Log entries for debugging
					Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - First reading of calendar year detected";

					### Calculate Electricity energy of previous calendar year � = (Wcurrent[kWh] - WcurrentYear[kWh])
					my $ElectricityCalcEnergyYearLast = ($ElectricityCountReadingValuePrevious - ReadingsVal($ElectricityCalcReadingDestinationDeviceName, $ElectricityCalcReadingPrefix . "_CounterYear1st", "0"));
					### Calculate pure Electricity cost of previous calendar year � = ElectricityCalcEnergyYearLast * Price per kWh
					my $ElectricityCalcEnergyCostYearLast = $ElectricityCalcEnergyYearLast * $attr{$ElectricityCalcName}{ElectricityPricePerKWh};

					### Save Electricity energy and pure cost of previous calendar year
					readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_EnergyCostYearLast", (sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcEnergyCostYearLast    ))), 1);
					readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_EnergyYearLast",     (sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcEnergyYearLast        ))), 1);
					readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_CounterYear1st",     (sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCountReadingValueCurrent  ))), 1);
					readingsSingleUpdate( $ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_CounterYearLast",    (sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCountReadingValuePrevious ))), 1);
				}
			}
		}
		
		###### Do calculations
		### Calculate DtCurrent (time difference) of previous and current timestamp / [s]
		my $ElectricityCountReadingTimestampDelta = $ElectricityCountReadingTimestampCurrentRelative - $ElectricityCountReadingTimestampPreviousRelative;
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCountReadingTimestampDelta            : " . $ElectricityCountReadingTimestampDelta . " s";

		### Continue with calculations only if time difference is larger than 1 seconds to avoid "Illegal division by zero" and erroneous due to small values for divisor
		if ($ElectricityCountReadingTimestampDelta > 0)
		{
			### Calculate DW (electric Energy difference) of previous and current value / [kWh]
			my $ElectricityCountReadingValueDelta = sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCountReadingValueCurrent)) - sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCountReadingValuePrevious));
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCountReadingValueDelta                : " . $ElectricityCountReadingValueDelta;

			### If the value has been changed since the last one
			if ($ElectricityCountReadingValueDelta > 0) {
				### Save current Timestamp as UNIX epoch into hash if the 
				readingsSingleUpdate($ElectricityCalcReadingDestinationDevice, "." . $ElectricityCalcReadingPrefix . "_LastUpdateTimestampUnix", $ElectricityCountReadingTimestampCurrentRelative, 0);
			}

			### Calculate Current Power P = DW/Dt[kWh/s] * 3600[s/h] * 1000 [1/k] / SiPrefixPowerFactor
			my $ElectricityCalcPowerCurrent    = ($ElectricityCountReadingValueDelta / $ElectricityCountReadingTimestampDelta) * 3600 * 1000 / $ElectricityCalcDev->{system}{SiPrefixPowerFactor};
			
			### Calculate daily sum of power measurements "SP" and measurement counts "n" and then calculate average Power "Paverage = SP/n"
			my $ElectricityCalcPowerDaySum     = ReadingsVal($ElectricityCalcReadingDestinationDeviceName, "." . $ElectricityCalcReadingPrefix . "_PowerDaySum",   "0") + $ElectricityCalcPowerCurrent;
			my $ElectricityCalcPowerDayCount   = ReadingsVal($ElectricityCalcReadingDestinationDeviceName, "." . $ElectricityCalcReadingPrefix . "_PowerDayCount", "0") + 1;
			my $ElectricityCalcPowerDayAverage = $ElectricityCalcPowerDaySum / $ElectricityCalcPowerDayCount;
			
			### Calculate consumed Energy of current  day   W = (Wcurrent[kWh] - W1stReadDay[kWh])   
			my $ElectricityCalcEnergyDay       = ($ElectricityCountReadingValueCurrent - ReadingsVal($ElectricityCalcReadingDestinationDeviceName, $ElectricityCalcReadingPrefix . "_CounterDay1st", "0"));

			### Calculate consumed Energy of current  month W = (Wcurrent[kWh] - W1stReadMonth[kWh]) 
			my $ElectricityCalcEnergyMonth     = ($ElectricityCountReadingValueCurrent - ReadingsVal($ElectricityCalcReadingDestinationDeviceName, $ElectricityCalcReadingPrefix . "_CounterMonth1st", "0"));

			### Calculate consumed Energy of current   year W = (Wcurrent[kWh] - W1stReadYear[kWh])  
			my $ElectricityCalcEnergyYear      = ($ElectricityCountReadingValueCurrent - ReadingsVal($ElectricityCalcReadingDestinationDeviceName, $ElectricityCalcReadingPrefix . "_CounterYear1st", "0"));

			### Calculate consumed Energy of Electricity-meter year W = (Wcurrent[kWh] - W1stReadMeter[kWh]) 
			my $ElectricityCalcEnergyMeter     = ($ElectricityCountReadingValueCurrent - ReadingsVal($ElectricityCalcReadingDestinationDeviceName, $ElectricityCalcReadingPrefix . "_CounterMeter1st", "0"));

			### Calculate pure Electricity cost since midnight
			my $ElectricityCalcEnergyCostDay = $ElectricityCalcEnergyDay * $attr{$ElectricityCalcName}{ElectricityPricePerKWh};

			### Calculate pure Electricity cost since first day of month
			my $ElectricityCalcEnergyCostMonth = $ElectricityCalcEnergyMonth * $attr{$ElectricityCalcName}{ElectricityPricePerKWh};
			
			### Calculate pure Electricity cost since first day of calendar year
			my $ElectricityCalcEnergyCostYear  = $ElectricityCalcEnergyYear * $attr{$ElectricityCalcName}{ElectricityPricePerKWh};
			
			### Calculate pure Electricity cost since first day of Electricity meter reading year
			my $ElectricityCalcEnergyCostMeter = $ElectricityCalcEnergyMeter * $attr{$ElectricityCalcName}{ElectricityPricePerKWh};
			
			### Calculate the payment month since the year of Electricity meter reading started
			my $ElectricityCalcMeterYearMonth=0;
			if (($ElectricityCountReadingTimestampCurrentMon - $attr{$ElectricityCalcName}{MonthOfAnnualReading} + 1) < 1)
			{
				$ElectricityCalcMeterYearMonth  = 13 + $ElectricityCountReadingTimestampCurrentMon  - $attr{$ElectricityCalcName}{MonthOfAnnualReading};
			}
			else
			{
				$ElectricityCalcMeterYearMonth  =  1 + $ElectricityCountReadingTimestampCurrentMon  - $attr{$ElectricityCalcName}{MonthOfAnnualReading};
			}
			
			### Calculate reserves at electricity supplier based on monthly advance payments within year of Electricity meter reading 
			my $ElectricityCalcReserves        = ($ElectricityCalcMeterYearMonth * $attr{$ElectricityCalcName}{MonthlyPayment}) - ($attr{$ElectricityCalcName}{BasicPricePerAnnum} / 12 * $ElectricityCalcMeterYearMonth) - $ElectricityCalcEnergyCostMeter;

			### Create Log entries for debugging		
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - _______Finance________________________________________";
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - Monthly Payment                                  : " . $attr{$ElectricityCalcName}{MonthlyPayment}        . " " . $attr{$ElectricityCalcName}{Currency};
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - Basic price per annum                            : " . $attr{$ElectricityCalcName}{BasicPricePerAnnum}    . " " . $attr{$ElectricityCalcName}{Currency};
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCalcEnergyCostMeter                   : " . sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcEnergyCostMeter)) . " " . $attr{$ElectricityCalcName}{Currency};
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCalcReserves                          : " . sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcReserves))        . " " . $attr{$ElectricityCalcName}{Currency};

			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - _______Times__________________________________________";
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCalcMeterYearMonth                    : " . $ElectricityCalcMeterYearMonth;
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - Current Month                                    : " . $ElectricityCountReadingTimestampCurrentMon;

			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - _______Energy_________________________________________";
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCalcEnergyDay                         : " . sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcEnergyDay))       . " kWh";
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCalcEnergyMonth                       : " . sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcEnergyMonth))     . " kWh";
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCalcEnergyYear                        : " . sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcEnergyYear))      . " kWh";
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCalcEnergyMeter                       : " . sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcEnergyMeter))     . " kWh";

			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - _______Power___________________________________________";
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCalcPowerCurrent                      : " . sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcPowerCurrent))    . " W";
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCalcPowerDayMin                       : " . ReadingsVal( $ElectricityCalcReadingDestinationDeviceName, $ElectricityCalcReadingPrefix . "_PowerDayMin", 0) . " W";
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCalcPowerDayAverage                   : " . sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcPowerDayAverage)) . " W";
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCalcPowerDayMax                       : " . ReadingsVal( $ElectricityCalcReadingDestinationDeviceName, $ElectricityCalcReadingPrefix . "_PowerDayMax", 0) . " W";

			###### Write readings to ElectricityCalc device
			### Initialize Bulkupdate
			readingsBeginUpdate($ElectricityCalcReadingDestinationDevice);

			### Write consumed electric Energy (DV) since last measurement
			readingsBulkUpdate($ElectricityCalcReadingDestinationDevice, "." . $ElectricityCalcReadingPrefix . "_LastDV",      sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCountReadingValueDelta)));

			### Write timelap (Dt) since last measurement
			readingsBulkUpdate($ElectricityCalcReadingDestinationDevice, "." . $ElectricityCalcReadingPrefix . "_LastDt",            sprintf('%.0f', ($ElectricityCountReadingTimestampDelta)));
		
			### Write current Power = average Power over last measurement period
			readingsBulkUpdate($ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_PowerCurrent",      sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcPowerCurrent)));
			
			### Write daily   Power = average Power since midnight
			readingsBulkUpdate($ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_PowerDayAver",      sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcPowerDayAverage)));
			
			### Write Power measurement sum    since midnight for average calculation
			readingsBulkUpdate($ElectricityCalcReadingDestinationDevice, "." . $ElectricityCalcReadingPrefix . "_PowerDaySum",       sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcPowerDaySum)));
			
			### Write Power measurement counts since midnight for average calculation
			readingsBulkUpdate($ElectricityCalcReadingDestinationDevice, "." . $ElectricityCalcReadingPrefix . "_PowerDayCount",     sprintf('%.0f', ($ElectricityCalcPowerDayCount)));
			
			### Detect new daily minimum power value and write to reading
			if (ReadingsVal($ElectricityCalcReadingDestinationDeviceName, $ElectricityCalcReadingPrefix . "_PowerDayMin", 0) > $ElectricityCalcPowerCurrent)
			{
				### Write new minimum Power value
				readingsBulkUpdate($ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_PowerDayMin",   sprintf('%.0f', ($ElectricityCalcPowerCurrent)));
				
				### Create Log entries for debugging
				Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - New daily minimum power value detected   : " . sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcPowerCurrent));
			}
			
			### Detect new daily maximum power value and write to reading
			if (ReadingsVal($ElectricityCalcReadingDestinationDeviceName, $ElectricityCalcReadingPrefix . "_PowerDayMax", 0) < $ElectricityCalcPowerCurrent)
			{
				### Write new maximum Power value
				readingsBulkUpdate($ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_PowerDayMax",   sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcPowerCurrent)));
				
				### Create Log entries for debugging
				Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - New daily maximum power value detected   : " . sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcPowerCurrent));
			}
			
			### Write energy consumption since midnight
			readingsBulkUpdate($ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_EnergyDay",         sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcEnergyDay)));
			
			### Write energy consumption since beginning of month
			readingsBulkUpdate($ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_EnergyMonth",       sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcEnergyMonth)));

			### Write energy consumption since beginning of year
			readingsBulkUpdate($ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_EnergyYear",        sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcEnergyYear)));
			
			### Write energy consumption since last meter reading
			readingsBulkUpdate($ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_EnergyMeter",       sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcEnergyMeter)));
			
			### Write pure energy costs since midnight
			readingsBulkUpdate($ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_EnergyCostDay",     sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcEnergyCostDay)));
			
			### Write pure energy costs since beginning of month
			readingsBulkUpdate($ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_EnergyCostMonth",   sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcEnergyCostMonth)));
			
			### Write pure energy costs since beginning of calendar year
			readingsBulkUpdate($ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_EnergyCostYear",    sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcEnergyCostYear)));
			
			### Write pure energy costs since beginning of year of Electricity meter reading
			readingsBulkUpdate($ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_EnergyCostMeter",   sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcEnergyCostMeter)));

			### Write reserves at electricity supplier based on monthly advance payments within year of Electricity meter reading
			readingsBulkUpdate($ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_FinanceReserve",    sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCalcReserves)));

			### Write current meter reading as shown on the mechanical meter
			readingsBulkUpdate($ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_CounterCurrent",    sprintf($ElectricityCalcDev->{system}{DecimalPlace}, ($ElectricityCountReadingValueCurrent)));
			
			### Write months since last meter reading
			readingsBulkUpdate($ElectricityCalcReadingDestinationDevice, $ElectricityCalcReadingPrefix . "_MonthMeterReading", sprintf('%.0f', ($ElectricityCalcMeterYearMonth)));

			### Finish and execute Bulkupdate
			readingsEndUpdate($ElectricityCalcReadingDestinationDevice, 1);
		}
		else
		{
			### Create Log entries for debugging
			Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - ElectricityCountReadingTimestampDelta = $ElectricityCountReadingTimestampDelta. Calculations skipped!";
		}
		
		### Create Log entries for debugging
		Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator End___________________________________________________________________________________________________________________________";
	}
		
	### If readings exist, update list of available readings
	if($ElectricityCalcDev->{READINGS}) 
	{
		### Copy readings in list of available "gets" and "sets"
		%{$ElectricityCalcDev->{helper}{gets}} = %{$ElectricityCalcDev->{READINGS}};
		%{$ElectricityCalcDev->{helper}{sets}} = %{$ElectricityCalcDev->{READINGS}};

		### Create Log entries for debugging
		#Log3 $ElectricityCalcName, 5, $ElectricityCalcName. " : ElectricityCalculator - notify x_sets list: " . join(" ", (keys %{$ElectricityCalcDev->{helper}{sets}}));
	}
	
	return undef;
}
####END####### Calculate Electricity meter values on changed events ####################################################END#####
1;


###START###### Description for fhem commandref ################################################################START####
=pod

=item helper
=item summary    Calculates the electrical energy consumption and costs
=item summary_DE Berechnet den Energieverbrauch und verbundene Kosten

=begin html

<a name="ElectricityCalculator"></a>
<h3>ElectricityCalculator</h3>
<ul>
	<table>
		<tr>
			<td>
				The ElectricityCalculator Module calculates the electrical energy consumption and costs of one ore more electricity meters.<BR>
				It is not a counter module itself but it requires a regular expression (regex or regexp) in order to know where to retrieve the continously increasing counter value of one or more mechanical or electronic electricity meter.<BR>
				<BR>
				As soon the module has been defined within the fhem.cfg, the module reacts on every event of the specified counter like myOWDEVICE:counter.* etc.<BR>
				<BR>
				The ElectricityCalculator module provides several current, historical, statistical values around with respect to one or more electricity meter and creates respective readings.<BR>
				<BR>
				To avoid waiting for max. 12 months to have realistic values, the readings <BR>
				<code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterDay1st</code>,<BR>
				<code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMonth1st</code>,<BR>
				<code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterYear1st</code> and<BR>
				<code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMeter1st</code><BR>
				must be corrected with real values by using the <code>setreading</code> - command.<BR>
				These real values may be found on the last electricity bill. Otherwise it will take 24h for the daily, 30days for the monthly and up to 12 month for the yearly values to become realistic.<BR>
				<BR>
				Intervalls smaller than 10s will be discarded to avoid peaks due to fhem blockages (e.g. DbLog - reducelog).
				<BR>
			</td>
		</tr>
	</table>





	<BR>
	<table>
		<tr><td><a name="ElectricityCalculatorDefine"></a><b>Define</b></td></tr>
		<tr><td><ul><code>define &lt;name&gt; ElectricityCalculator &lt;regex&gt;</code></ul></td></tr>
		<tr><td><ul><ul><code>&lt;name&gt;</code> : </td><td>The name of the calculation device. (E.g.: "myElectricityCalculator")</ul></ul></td></tr>
		<tr><td><ul><ul><code>&lt;regex&gt;</code> : </td><td>A valid regular expression (also known as regex or regexp) of the event where the counter can be found</ul></ul></td></tr>
		<tr><td><ul>Example: <code>define myElectricityCalculator ElectricityCalculator myElectricityCounter:countersA.*</code></ul></td></tr>
	</table>
	<BR>
	<table>
		<tr><td><a name="ElectricityCalculatorSet"></a><b>Set</b></td></tr>
		<tr><td><ul>The set - function sets individual values for example to correct values after power loss etc.<BR>The set - function works for readings which have been stored in the CalculatorDevice and to update the Offset.<BR>The Readings being stored in the Counter - Device need to be changed individially with the <code>set</code> - command.<BR>The command "SyncCounter" will calculate and update the Offset. Just enter the value of your mechanical Reader.<BR></ul></td></tr>
	</table>
	<BR>
	<table>
		<tr><td><a name="ElectricityCalculatorGet"></a><b>Get</b></td></tr>
		<tr><td><ul>The get - function just returns the individual value of the reading.<BR>The get - function works only for readings which have been stored in the CalculatorDevice.<BR>The Readings being stored in the Counter - Device need to be read individially with  <code>get</code> - command.<BR></ul></td></tr>
	</table>
	<BR>
	<table>
		<tr><td><a name="ElectricityCalculatorAttr"></a><b>Attributes</b></td></tr>
		<tr><td><ul>If the below mentioned attributes have not been pre-defined completly beforehand, the program will create the ElectricityCalculator specific attributes with default values.<BR>In addition the global attributes e.g. <a href="#room">room</a> can be used.<BR></ul></td></tr>
	</table>
	<table>
		<tr><td><ul><ul><a name="BasicPricePerAnnum"       ></a><li><b><u><code>BasicPricePerAnnum       </code></u></b> :  A valid float number for basic annual fee in the chosen currency for the electricity supply to the home.<BR>																			The value is provided by your local electricity supplier and is shown on your electricity bill.<BR>																			For UK and US users it may known under "standing charge". Please make sure it is based on one year!<BR>The default value is 0.00       <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a name="Currency"                 ></a><li><b><u><code>Currency                 </code></u></b> :  One of the pre-defined list of currency symbols [&#8364;,&#163;,&#36;].<BR>																The default value is &#8364;                                                                                                                                                                                                                                                                                                                                       <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a name="disable"                  ></a><li><b><u><code>disable                  </code></u></b> :  Disables the current module. The module will not react on any events described in the regular expression.<BR>																		The default value is 0 = enabled.                                                                                                                                                                                                                                                                                      <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a name="ElectricityCounterOffset" ></a><li><b><u><code>ElectricityCounterOffset </code></u></b> :  A valid float number of the electric Energy difference = offset (not the difference of the counter ticks!) between the value shown on the mechanic meter for the electric energy and the calculated electric energy of the counting device.<BR>The value for this offset will be calculated as follows W<sub>Offset</sub> = W<sub>Mechanical</sub> - W<sub>Module</sub><BR>The default value is 0.00                                                                                                       <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a name="ElectricityKwhPerCounts"  ></a><li><b><u><code>ElectricityKwhPerCounts  </code></u></b> :  A valid float number of electric energy in kWh per counting ticks.<BR>The value is given by the mechanical trigger of the mechanical electricity meter. E.g. ElectricityKwhPerCounts = 0.001 means each count is a thousandth of one kWh (=Wh).<BR>Some electronic counter (E.g. HomeMatic HM-ES-TX-WM) providing the counted electric energy as Wh. Therfore  this attribute must be 0.001 in order to transform it correctly to kWh.<BR>The default value is 1 (= the counter is already providing kWh)  <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a name="ElectricityPricePerKWh"   ></a><li><b><u><code>ElectricityPricePerKWh   </code></u></b> :  A valid float number for electric energy price in the chosen currency per kWh.<BR>The value is provided by your local electricity supplier and is shown on your electricity bill.<BR>The default value is 0.2567                                                                                                                                                                                                                                                                                           <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a name="MonthlyPayment"           ></a><li><b><u><code>MonthlyPayment           </code></u></b> :  A valid float number for monthly advance payments in the chosen currency towards the electricity supplier.<BR>The default value is 0.00                                                                                                                                                                                                                                                                                                                                                                    <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a name="MonthOfAnnualReading"     ></a><li><b><u><code>MonthOfAnnualReading     </code></u></b> :  A valid integer number for the month when the mechanical electricity meter reading is performed every year.<BR>The default value is 5 (May)                                                                                                                                                                                                                                                                                                                                                                <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a name="ReadingDestination"       ></a><li><b><u><code>ReadingDestination       </code></u></b> :  One of the pre-defined list for the destination of the calculated readings: [CalculatorDevice,CounterDevice].<BR>The CalculatorDevice is the device which has been created with this module.<BR>The CounterDevice is the Device which is reading the mechanical Electricity-meter.<BR>The default value is CalculatorDevice - Therefore the readings will be written into this device.                                                                                                                     <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a name="SiPrefixPower"            ></a><li><b><u><code>SiPrefixPower            </code></u></b> :  One value of the pre-defined list: W (Watt), kW (Kilowatt), MW (Megawatt) or GW (Gigawatt).<BR>It defines which SI-prefix for the power value shall be used. The power value will be divided accordingly by multiples of 1000.<BR>The default value is W (Watt).                                                                                                                                                                                                                                           <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a name="DecimalPlace"             ></a><li><b><u><code>DecimalPlace             </code></u></b> :  One value of the pre-defined list 3 to 7.<BR>It defines to which accuracy in decimal places all results shall be calculated.<BR>The default value is 3 = 0.001.                                                                                                                                                                                                                                                                                                                                            <BR></li></ul></ul></td></tr>
	</table>
	
	<BR>
	<table>
		<tr><td><a name="ElectricityCalculatorReadings"></a><b>Readings</b></td></tr>
		<tr><td><ul>As soon the device has been able to read at least 2 times the counter, it automatically will create a set of readings:<BR>The placeholder <code>&lt;DestinationDevice&gt;</code> is the device which has been chosen in the attribute <code>ReadingDestination</code> above. <BR> This will not appear if CalculatorDevice has been chosen.<BR>The placeholder <code>&lt;SourceCounterReading&gt;</code> is the reading based on the defined regular expression where the counting ticks are coming from.<BR></ul></td></tr>
	</table>
	<table>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterCurrent      </code></li></td><td>: Current indicated total electric energy consumption as shown on mechanical electricity meter. Correct Offset-attribute if not identical.                                                                                                                                                                                                                                                                                                                                                           <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterDay1st       </code></li></td><td>: The first meter reading after midnight.                                                                                                                                                                                                                                                                                                                                                                                                                                                            <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterDayLast      </code></li></td><td>: The last meter reading of the previous day.                                                                                                                                                                                                                                                                                                                                                                                                                                                        <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMonth1st     </code></li></td><td>: The first meter reading after midnight of the first day of the month.                                                                                                                                                                                                                                                                                                                                                                                                                              <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMonthLast    </code></li></td><td>: The last meter reading of the previous month.                                                                                                                                                                                                                                                                                                                                                                                                                                                      <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMeter1st     </code></li></td><td>: The first meter reading after midnight of the first day of the month where the mechanical meter is read by the electricity supplier.                                                                                                                                                                                                                                                                                                                                                               <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMeterLast    </code></li></td><td>: The last meter reading of the previous meter reading year.                                                                                                                                                                                                                                                                                                                                                                                                                                         <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterYear1st      </code></li></td><td>: The first meter reading after midnight of the first day of the year.                                                                                                                                                                                                                                                                                                                                                                                                                               <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterYearLast     </code></li></td><td>: The last meter reading of the previous year.                                                                                                                                                                                                                                                                                                                                                                                                                                                       <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostDayLast   </code></li></td><td>: Energy costs of the last day.                                                                                                                                                                                                                                                                                                                                                                                                                                                                      <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostMeterLast </code></li></td><td>: Energy costs in the chosen currency of the last electricity meter period.                                                                                                                                                                                                                                                                                                                                                                                                                          <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostMonthLast </code></li></td><td>: Energy costs in the chosen currency of the last month.                                                                                                                                                                                                                                                                                                                                                                                                                                             <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostYearLast  </code></li></td><td>: Energy costs of the last calendar year.                                                                                                                                                                                                                                                                                                                                                                                                                                                            <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostDay       </code></li></td><td>: Energy consumption in kWh since the beginning of the current day (midnight).                                                                                                                                                                                                                                                                                                                                                                                                                       <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostMeter     </code></li></td><td>: Energy costs in the chosen currency since the beginning of the month of where the last electricity meter reading has been performed by the electricity supplier.                                                                                                                                                                                                                                                                                                                                   <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostMonth     </code></li></td><td>: Energy costs in the chosen currency since the beginning of the current month.                                                                                                                                                                                                                                                                                                                                                                                                                      <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostYear      </code></li></td><td>: Energy costs in the chosen currency since the beginning of the current year.                                                                                                                                                                                                                                                                                                                                                                                                                       <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyDay           </code></li></td><td>: Energy consumption in kWh since the beginning of the current day (midnight).                                                                                                                                                                                                                                                                                                                                                                                                                       <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyDayLast       </code></li></td><td>: Total Energy consumption in kWh of the last day.                                                                                                                                                                                                                                                                                                                                                                                                                                                   <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyMeter         </code></li></td><td>: Energy consumption in kWh since the beginning of the month of where the last electricity-meter reading has been performed by the Electricity supplier.                                                                                                                                                                                                                                                                                                                                             <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyMeterLast     </code></li></td><td>: Total Energy consumption in kWh of the last electricity-meter reading period.                                                                                                                                                                                                                                                                                                                                                                                                                      <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyMonth         </code></li></td><td>: Energy consumption in kWh since the beginning of the current month (midnight of the first).                                                                                                                                                                                                                                                                                                                                                                                                        <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyMonthLast     </code></li></td><td>: Total Energy consumption in kWh of the last month.                                                                                                                                                                                                                                                                                                                                                                                                                                                 <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyYear          </code></li></td><td>: Energy consumption in kWh since the beginning of the current year (midnight of the first).                                                                                                                                                                                                                                                                                                                                                                                                         <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyYearLast      </code></li></td><td>: Total Energy consumption in kWh of the last calendar year.                                                                                                                                                                                                                                                                                                                                                                                                                                         <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_FinanceReserve      </code></li></td><td>: Financial Reserve based on the advanced payments done on the first of every month towards the Electricity supplier. With negative values, an additional payment is to be expected.                                                                                                                                                                                                                                                                                                                 <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_MonthMeterReading   </code></li></td><td>: Number of month since last meter reading. The month when the reading occured is the first month = 1.                                                                                                                                                                                                                                                                                                                                                                                               <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_PowerCurrent        </code></li></td><td>: Current electric Power. (Average Power between current and previous measurement.)                                                                                                                                                                                                                                                                                                                                                                                                                  <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_PowerDayAver        </code></li></td><td>: Average electric Power since midnight.                                                                                                                                                                                                                                                                                                                                                                                                                                                             <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_PowerDayMax         </code></li></td><td>: Maximum Power peak since midnight.                                                                                                                                                                                                                                                                                                                                                                                                                                                                 <BR>    </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_PowerDayMin         </code></li></td><td>: Minimum Power peak since midnight.                                                                                                                                                                                                                                                                                                                                                                                                                                                                 <BR>    </ul></ul></td></tr>
	</table>
</ul>

=end html

=begin html_DE

<a name="ElectricityCalculator"></a>
<h3>ElectricityCalculator</h3>
<ul>
	<table>
		<tr>
			<td>
				Das ElectricityCalculator Modul berechnet den Verbrauch an elektrischer Energie (Stromverbrauch) und den verbundenen Kosten von einem oder mehreren Elektrizit&auml;tsz&auml;hlern.<BR>
				Es ist kein eigenes Z&auml;hlermodul sondern ben&ouml;tigt eine Regular Expression (regex or regexp) um das Reading mit dem kontinuierlich wachsenden Z&auml;hlerstand von einem oder mehreren Electrizit&auml;tsz&auml;hlern zu finden.<BR>
				<BR>
				Sobald das Modul in der fhem.cfg definiert wurde, reagiert das Modul auf jedes durch das regex definierte event wie beispielsweise ein myOWDEVICE:counter.* etc.<BR>
				<BR>
				Das ElectricityCalculator Modul berechnet augenblickliche, historische statistische und vorhersehbare Werte von einem oder mehreren Elektrizit&auml;tsz&auml;hlern und erstellt die entsprechenden Readings.<BR>
				<BR>
				Um zu verhindern, dass man bis zu 12 Monate warten muss, bis alle Werte der Realit&auml;t entsprechen, m&uuml;ssen die Readings<BR>
				<code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterDay1st</code>,<BR>
				<code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMonth1st</code>,<BR>
				<code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterYear1st</code> und<BR>
				<code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMeter1st</code><BR>
				entsprechend mit dem <code>setreading</code> - Befehl korrigiert werden.<BR>
				Diese Werte findet man unter Umst&auml;nden auf der letzten Abrechnung des Elektrizit&auml;tsversorgers. Andernfalls dauert es bis zu 24h f&uuml;r die t&auml;glichen, 30 Tage f&uuml;r die monatlichen und bis zu 12 Monate f&uuml;r die j&auml;hrlichen Werte bis diese der Realit&auml;t entsprechen.<BR>
				<BR>
				<BR>
				Intervalle kleienr als 10s werden ignoriert um Spitzen zu verhindern die von Blockaden des fhem Systems hervorgerufen werden (z.B. DbLog - reducelog).
			</td>
		</tr>
	</table>



	<BR>
	<table>
		<tr><td><a name="ElectricityCalculatorDefine"></a><b>Define</b></td></tr>
		<tr><td><ul><code>define &lt;name&gt; ElectricityCalculator &lt;regex&gt;</code></ul></td></tr>
		<tr><td><ul><ul><code>&lt;name&gt;</code> : </td><td>Der Name dieses Berechnungs-Device. Empfehlung: "myElectricityCalculator".                                          </ul></ul></td></tr>
		<tr><td><ul><ul><code>&lt;regex&gt;</code> : </td><td>Eine g&uuml;ltige Regular Expression (regex or regexp) von dem Event wo der Z&auml;hlerstand gefunden werden kann. </ul></ul></td></tr>
		<tr><td><ul>Beispiel: <code>define myElectricityCalculator ElectricityCalculator myElectricityCounter:countersA.*</code></ul></td></tr>
	</table>
	<BR>
	<table>
		<tr><td><a name="ElectricityCalculatorSet"></a><b>Set</b></td></tr>
		<tr><td><ul>Die set - Funktion erlaubt individuelle Readings zu ver&auml;ndern um beispielsweise nach einem Stromausfall Werte zu korrigieren.<BR>Die set - Funktion funktioniert f&uumlr Readings welche im CalculatorDevice gespeichert wurden und zum update des Offsets zwischen den Z&aumlhlern.<BR>Die Readings welche im Counter - Device gespeichert wurden, m&uumlssen individuell mit <code>set</code> - Befehl gesetzt werden.<BR>Der Befehl "SyncCounter" errechnet und update den Offset. Hierbei einfach den Wert des mechanischen Z&aumlhlers eingeben.<BR></ul></td></tr>
	</table>
	<BR>
	<table>
		<tr><td><a name="ElectricityCalculatorGet"></a><b>Get</b></td></tr>
		<tr><td><ul>Die get - Funktion liefert nur den Wert des jeweiligen Readings zur&uuml;ck.<BR>Die get - Funktion funktioniert nur f&uumlr Readings welche im CalculatorDevice gespeichert wurden.<BR>Die Readings welche im Counter - Device gespeichert wurden, m&uumlssen individuell mit <code>get</code> - Befehl ausgelesen werden.<BR></ul></td></tr>
	</table>
	<BR>
	<table>
		<tr><td><a name="ElectricityCalculatorAttr"></a><b>Attributes</b></td></tr>
		<tr><td><ul>Sollten die unten ausfeg&auuml;hrten Attribute bei der Definition eines entsprechenden Ger&auml;tes nicht gesetzt sein, so werden sie vom Modul mit Standard Werten automatisch gesetzt<BR>Zus&auml;tzlich k&ouml;nnen die globalen Attribute wie <a href="#room">room</a> verwendet werden.<BR></ul></td></tr>
	</table>
	<table>
		<tr><td><ul><ul><a name="BasicPricePerAnnum"  ></a><li><b><u><code>BasicPricePerAnnum       </code></u></b> : Eine g&uuml;ltige float Zahl f&uuml;r die j&auml;hrliche Grundgeb&uuml;hr in der gew&auml;hlten W&auml;hrung f&uuml;r die Elektrizit&auml;ts-Versorgung zum Endverbraucher.<BR>Dieser Wert stammt vom Elektrizit&auml;tsversorger und steht auf der Abrechnung.<BR>Der Standard Wert ist 0.00.                                                                                                                                                                                                                                                                                        <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a name="Currency"            ></a><li><b><u><code>Currency                 </code></u></b> : Eines der vordefinerten W&auml;hrungssymbole: [&#8364;,&#163;,&#36;].<BR>Der Standard Wert ist &#8364;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a name="disable"             ></a><li><b><u><code>disable                  </code></u></b> : Deaktiviert das device. Das Modul wird nicht mehr auf die Events reagieren die durch die Regular Expression definiert wurde.<BR>Der Standard Wert ist 0 = aktiviert.                                                                                                                                                                                                                                                                                                                                                                                                                  <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a name="WaterCounterOffset"  ></a><li><b><u><code>ElectricityCounterOffset </code></u></b> : Eine g&uuml;ltige float-Zahl f&uuml;r den Unterschied = Offset (Nicht der Unterschied zwischen Z&auml;hlimpulsen) zwischen dem am mechanischen Elektrizit&auml;tsz&auml;hlern und dem angezeigten Wert im Reading dieses Device.<BR>Der Offset-Wert wird wie folgt ermittelt: W<sub>Offset</sub> = W<sub>Mechanisch</sub> - W<sub>Module</sub><BR>Der Standard-Wert ist 0.00.                                                                                                                                                                                                         <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a name="WaterCubicPerCounts" ></a><li><b><u><code>ElectricityKwhPerCounts  </code></u></b> : Eine g&uuml;ltige float-Zahl f&uuml;r die Menge kWh pro Z&auml;hlimpulsen.<BR>Der Wert ist durch das mechanische Z&auml;hlwerk des Elektrizit&auml;tsz&auml;hlern vorgegeben. ElectricityKwhPerCounts = 0.001 bedeutet, dass jeder Z&auml;hlimpuls ein Tausendstel einer kWh ist (=Wh).<BR>Einige elektronische Z&auml;hler (Bsp.: HomeMatic HM-ES-TX-WM) stellen die gez&auml;hlte Menge an elektrischer Energie als Wh bereit.<BR>Aus diesem Grund muss dieses Attribut auf 0.001 gesetzt werden um eine korrekte Transformation in kWh zu erm&ouml;glichen.<BR>Der Standard-Wert ist 1. <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a name="WaterPricePerCubic"  ></a><li><b><u><code>ElectricityPricePerKWh   </code></u></b> : Eine g&uuml;ltige float-Zahl f&uuml;r den Preis pro kWh.<BR>Dieser Wert stammt vom Elektrizit&auml;tsversorger und steht auf der Abrechnung.<BR>Der Standard-Wert ist 0.2567.                                                                                                                                                                                                                                                                                                                                                                                                         <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a name="MonthlyPayment"      ></a><li><b><u><code>MonthlyPayment           </code></u></b> : Eine g&uuml;ltige float-Zahl f&uuml;r die monatlichen Abschlagszahlungen in der gew&auml;hlten W&auml;hrung an den Elektrizit&auml;tsversorger.<BR>Der Standard-Wert ist 0.00.                                                                                                                                                                                                                                                                                                                                                                                                        <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a name="MonthOfAnnualReading"></a><li><b><u><code>MonthOfAnnualReading     </code></u></b> : Eine g&uuml;ltige Ganz-Zahl f&uuml;r den Monat wenn der mechanische Elektrizit&auml;tsz&auml;hler jedes Jahr durch den Elektrizit&auml;tsversorger abgelesen wird.<BR>Der Standard-Wert ist 5 (Mai)                                                                                                                                                                                                                                                                                                                                                                                   <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a name="ReadingDestination"  ></a><li><b><u><code>ReadingDestination       </code></u></b> : Eines der vordefinerten Device als Ziel der errechneten Readings: [CalculatorDevice,CounterDevice].<BR>Das CalculatorDevice ist das mit diesem Modul erstellte Device.<BR>Das CounterDevice    ist das Device von welchem der mechanische Z&auml;hler ausgelesen wird.<BR>Der Standard-Wert ist CalculatorDevice.                                                                                                                                                                                                                                                                     <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a name="WFRUnit"             ></a><li><b><u><code>SiPrefixPower            </code></u></b> : Ein Wert der vorgegebenen Auswahlliste: W (Watt), kW (Kilowatt), MW (Megawatt) or GW (Gigawatt).<BR>Es definiert welcher SI-Prefix verwendet werden soll und teilt die Leistung entsprechend durch ein Vielfaches von 1000.<BR>Der Standard-Wert ist W (Watt).                                                                                                                                                                                                                                                                                                                        <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a name="DecimalPlace"        ></a><li><b><u><code>DecimalPlace             </code></u></b> : Ein Wert der vorgegebenen Auswahlliste von 3 bis 7.<BR>Es definiert die Genauigkeit in Nachkommastellen mit welcher die Ergebnisse berechnet werden.Der Standard-Wert ist 3 = 0,001.                                                                                                                                                                                                                                                                                                                                                                                                  <BR></li></ul></ul></td></tr>
	</table>

	<BR>
	<table>
		<tr><td><a name="ElectricityCalculatorReadings"></a><b>Readings</b></td></tr>
		<tr><td><ul>Sobald das Device in der Lage war mindestens 2 Werte des Z&auml;hlers einzulesen, werden automatisch die entsprechenden Readings erzeugt:<BR>Der Platzhalter <code>&lt;DestinationDevice&gt;</code> steht f&uuml;r das Device, welches man in dem Attribut <code>ReadingDestination</code> oben festgelegt hat. Dieser Platzhalter bleibt leer, sobald man dort CalculatorDevice ausgew&auml;hlt hat.<BR>Der Platzhalter <code>&lt;SourceCounterReading&gt;</code> steht f&uuml;r das Reading welches mit der Regular Expression definiert wurde.<BR></ul></td></tr>
	</table>
	<table>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterCurrent      </code></li></td><td>: Aktueller Z&auml;hlerstand am mechanischen Z&auml;hler. Bei Unterschied muss das Offset-Attribut entspechend korrigiert werden.                                                                                                                                                                                                                                                                                                                                                                                                                                         <BR>     </ul></ul></td></tr>                    
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterDay1st       </code></li></td><td>: Der erste Z&auml;hlerstand des laufenden Tages seit Mitternacht.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterDayLast      </code></li></td><td>: Der letzte Z&auml;hlerstand des vorherigen Tages.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMeter1st     </code></li></td><td>: Der erste Z&auml;hlerstand seit Mitternacht des ersten Tages der laufenden Ableseperiode.                                                                                                                                                                                                                                                                                                                                                                                                                                                                               <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMeterLast    </code></li></td><td>: Der letzte Z&auml;hlerstand seit Mitternacht des ersten Tages der vorherigen Ableseperiode.                                                                                                                                                                                                                                                                                                                                                                                                                                                                             <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMonth1st     </code></li></td><td>: Der erste Z&auml;hlerstand seit Mitternacht des ersten Tages des laufenden Monats.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMonthLast    </code></li></td><td>: Der letzte Z&auml;hlerstand des vorherigen Monats.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterYear1st      </code></li></td><td>: Der erste Z&auml;hlerstand seit Mitternacht des ersten Tages des laufenden Jahres.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterYearLast     </code></li></td><td>: Der letzte Z&auml;hlerstand des letzten Jahres.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostDayLast   </code></li></td><td>: Elektrische Energiekosten des letzten Tages.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostMeterLast </code></li></td><td>: Elektrische Energiekosten der letzten Ableseperiode.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostMonthLast </code></li></td><td>: Elektrische Energiekosten des letzten Monats.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostYearLast  </code></li></td><td>: Elektrische Energiekosten des letzten Kalenderjahres.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostDay       </code></li></td><td>: Energiekosten in gew&auml;hlter W&auml;hrung seit Mitternacht des laufenden Tages.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostMeter     </code></li></td><td>: Energiekosten in gew&auml;hlter W&auml;hrung seit Beginn der laufenden Ableseperiode.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostMonth     </code></li></td><td>: Energiekosten in gew&auml;hlter W&auml;hrung seit Beginn des laufenden Monats.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostYear      </code></li></td><td>: Energiekosten in gew&auml;hlter W&auml;hrung seit Beginn des laufenden Kalenderjahres.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyDay           </code></li></td><td>: Energieverbrauch seit Beginn der aktuellen Tages (Mitternacht).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyDayLast       </code></li></td><td>: Energieverbrauch in kWh des vorherigen Tages.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyMeter         </code></li></td><td>: Energieverbrauch seit Beginn der aktuellen Ableseperiode.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyMeterLast     </code></li></td><td>: Energieverbrauch in kWh der vorherigen Ableseperiode.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyMonth         </code></li></td><td>: Energieverbrauch seit Beginn des aktuellen Monats.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyMonthLast     </code></li></td><td>: Energieverbrauch in kWh des vorherigen Monats.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyYear          </code></li></td><td>: Energieverbrauch seit Beginn des aktuellen Kalenderjahres.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyYearLast      </code></li></td><td>: Energieverbrauch in kWh des vorherigen Kalenderjahres.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_FinanceReserve      </code></li></td><td>: Finanzielle Reserve basierend auf den Abschlagszahlungen die jeden Monat an den Elektrizit&auml;tsversorger gezahlt werden. Bei negativen Werten ist von einer Nachzahlung auszugehen.                                                                                                                                                                                                                                                                                                                                                                                  <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_MonthMeterReading   </code></li></td><td>: Anzahl der Monate seit der letzten Z&auml;hlerablesung. Der Monat der Z&auml;hlerablesung ist der erste Monat = 1.                                                                                                                                                                                                                                                                                                                                                                                                                                                                <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_PowerCurrent        </code></li></td><td>: Aktuelle elektrische Leistung. (Mittelwert zwischen aktueller und letzter Messung)<BR>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_PowerDayAver        </code></li></td><td>: Mittlere elektrische Leistung seit Mitternacht.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_PowerDayMax         </code></li></td><td>: Maximale elektrische Leistungsaufnahme seit Mitternacht.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                <BR>     </ul></ul></td></tr>
		<tr><td><ul><ul><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_PowerDayMin         </code></li></td><td>: Minimale elektrische Leistungsaufnahme seit Mitternacht.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                <BR>     </ul></ul></td></tr>
	</table>
</ul>
=end html_DE

=for :application/json;q=META.json 73_ElectricityCalculator.pm
{
  "abstract": "Calculates the electrical energy consumption and costs.",
  "description": "The ElectricityCalculator Module calculates the electrical energy consumption and costs of one ore more electricity meters.<BR>Tt is not a counter module itself but it requires a regular expression (regex or regexp) in order to know where to retrieve the continously increasing counter value of one or more mechanical or electronic electricity meter.<BR>As soon the module has been defined within the fhem.cfg, the module reacts on every event of the specified counter like myOWDEVICE:counter.* etc.<BR>The ElectricityCalculator module provides several current, historical, statistical values around with respect to one or more electricity meter and creates respective readings.<BR>",
  "x_lang": {
    "de": {
      "abstract": "Berechnet den Energieverbrauch und verbundene Kosten",
      "description": "Das ElectricityCalculator Modul berechnet den Verbrauch an elektrischer Energie (Stromverbrauch) und den verbundenen Kosten von einem oder mehreren Elektrizit&auml;tsz&auml;hlern.<BR>Es ist kein eigenes Z&auml;hlermodul sondern ben&ouml;tigt eine Regular Expression (regex or regexp) um das Reading mit dem kontinuierlich wachsenden Z&auml;hlerstand von einem oder mehreren Electrizit&auml;tsz&auml;hlern zu finden.<BR>Sobald das Modul in der fhem.cfg definiert wurde, reagiert das Modul auf jedes durch das regex definierte event wie beispielsweise ein myOWDEVICE:counter.* etc.<BR>Das ElectricityCalculator Modul berechnet augenblickliche, historische statistische und vorhersehbare Werte von einem oder mehreren Elektrizit&auml;tsz&auml;hlern und erstellt die entsprechenden Readings.<BR>"
    }
  },
  "author": [
    "I am the maintainer matthias.deeke@deeke.eu"
  ],
  "x_fhem_maintainer": [
    "Sailor"
  ],
  "keywords": [
    "electricity",
	"current",
    "calculation",
    "consumption",
    "cost",
    "counter"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918623,
        "FHEM::Meta": 0.001006,
        "HttpUtils": 0,
        "JSON": 0,
        "perl": 5.014
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  },
  "resources": {
    "x_support_community": {
      "rss": "https://forum.fhem.de/index.php/topic,57106.msg",
      "web": "https://forum.fhem.de/index.php/topic,57106.msg",
      "subCommunity" : {
          "rss" : "https://forum.fhem.de/index.php/topic,57106.msg",
          "title" : "This sub-board will be first contact point",
          "web" : "https://forum.fhem.de/index.php/topic,57106.msg"
       }
    }
  },
  "x_support_status": "supported"
}
=end :application/json;q=META.json

=cut