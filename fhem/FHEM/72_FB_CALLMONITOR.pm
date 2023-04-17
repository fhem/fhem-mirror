###############################################################
# $Id$
###############################################################
#
#     72_FB_CALLMONITOR.pm
#     Connects to a FritzBox Fon via network.
#     When a call is received or takes place it creates an event with further call informations.
#     This module has no sets or gets as it is only used for event triggering.
#
#     Additional Rating-Search from tellows.de (experimental) https://forum.fhem.de/index.php/topic,49603.0.html ### tellows
#
#     Copyright by Markus Bloch
#     e-mail: Notausstieg0309@googlemail.com
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
###############################################################

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use Encode qw(encode);
use Digest::MD5;
use HttpUtils;
use DevIo;
use FritzBoxUtils;

my $ModulVersion = "07.50.3b";
my %tellows = ();
my %connection_type = (
     0 => "FON1",
     1 => "FON2",
     2 => "FON3",
     3 => "Callthrough",
     4 => "ISDN",
     5 => "FAX",
     6 => "Answering_Machine",

     10 => "DECT_1",
     11 => "DECT_2",
     12 => "DECT_3",
     13 => "DECT_4",
     14 => "DECT_5",
     15 => "DECT_6",

     20 => "VoIP_1",
     21 => "VoIP_2",
     22 => "VoIP_3",
     23 => "VoIP_4",
     24 => "VoIP_5",
     25 => "VoIP_6",
     26 => "VoIP_7",
     27 => "VoIP_8",
     28 => "VoIP_9",
     29 => "VoIP_10",

     36 => "ISDN_data",
     37 => "FAX_data",

     40 => "Answering_Machine_1",
     41 => "Answering_Machine_2",
     42 => "Answering_Machine_3",
     43 => "Answering_Machine_4",
     44 => "Answering_Machine_5"
);


#######################################################################
sub FB_CALLMONITOR_Log($$$)
{
   my ( $hash, $loglevel, $text ) = @_;
   my $xline       = ( caller(0) )[2];

   my $xsubroutine = ( caller(1) )[3];
   my $sub         = ( split( ':', $xsubroutine ) )[2];
   $sub =~ s/FB_CALLMONITOR_//;

   if ($loglevel <= 2) {
      $text = "ERROR: " . $text;
   } elsif ($loglevel >= 5) {
       $text = "DEBUG: " . $text;
   } else {
       $text = "INFO: " . $text;
   }

   my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
   Log3 $hash, $loglevel, "FB_CALLMONITOR [$instName: $sub.$xline] - " . $text;
}
# End FB_CALLMONITOR_Log

#######################################################################
sub FB_CALLMONITOR_Initialize($)
{
    my ($hash) = @_;

    # Provider
    $hash->{ReadFn}    = "FB_CALLMONITOR_Read";
    $hash->{ReadyFn}   = "FB_CALLMONITOR_Ready";
    $hash->{GetFn}     = "FB_CALLMONITOR_Get";
    $hash->{SetFn}     = "FB_CALLMONITOR_Set";
    $hash->{DefFn}     = "FB_CALLMONITOR_Define";
    $hash->{RenameFn}  = "FB_CALLMONITOR_Rename";
    $hash->{DeleteFn}  = "FB_CALLMONITOR_Delete";
    $hash->{UndefFn}   = "FB_CALLMONITOR_Undef";
    $hash->{AttrFn}    = "FB_CALLMONITOR_Attr";
    $hash->{NotifyFn}  = "FB_CALLMONITOR_Notify";
    $hash->{AttrList}  = "do_not_notify:0,1 ".
                         "disable:0,1 ".
                         "disabledForIntervals ".
                         "unique-call-ids:0,1 ".
                         "local-area-code ".
                         "country-code ".
                         "remove-leading-zero:0,1 ".
                         "internal-number-filter ".
                         "answMachine-is-missed-call:0,1 ".
                         "check-deflections:0,1 ".
                         "reverse-search-cache-file ".
                         "reverse-search:sortable-strict,phonebook,textfile,tellows.de,dasoertliche.de,11880.com,search.ch,dasschnelle.at,herold.at ".
                         "reverse-search-cache:0,1 ".
                         "reverse-search-phonebook-file ".
                         "reverse-search-text-file ".
                         "reverse-search-tellows-api-key ".
                         "reverse-search-tellows-api-partner ".
                         "fritzbox-remote-phonebook:0,1 ".
                         "fritzbox-remote-phonebook-via:web,tr064,telnet ".
                         "fritzbox-remote-phonebook-exclude ".
                         "fritzbox-remote-timeout ".
                         "fritzbox-user ".
                         "apiKeySearchCh ".
                         "sendKeepAlives:none,5m,10m,15m,30m,1h ".
                         "contactImageViaTR064:0,1 ".
                         "contactImageDirectory ".
                         "contactDefaultImage ".
                         $readingFnAttributes;
}

#######################################################################
sub FB_CALLMONITOR_Define($$)
{
   my ($hash, $def) = @_;
   my @a = split("[ \t][ \t]*", $def);

   if(@a != 3)
   {
       my $msg = "wrong syntax: define <name> FB_CALLMONITOR ip[:port]";
       Log 2, $msg;
       return $msg;
   }

   my $name = $a[0];

   $hash->{NAME}    = $name;
   $hash->{VERSION} = $ModulVersion;

   $hash->{NOTIFYDEV} = "global";

   DevIo_CloseDev($hash);
   delete($hash->{NEXT_OPEN});

   my $dev = $a[2];

   $dev .= ":1012" if($dev !~ m/:/ && $dev ne "none" && $dev !~ m/\@/);

   $hash->{DeviceName} = $dev;

   return DevIo_OpenDev($hash, 0, undef, \&FB_CALLMONITOR_DevIoCallback)
}


#######################################################################
# closing the connection on undefinition (shutdown/delete)
sub FB_CALLMONITOR_Undef($$)
{
    my ($hash, $arg) = @_;

    RemoveInternalTimer($hash, "FB_CALLMONITOR_sendKeepAlive");
    DevIo_CloseDev($hash);

    return undef;
}

#######################################################################
# If Device is deleted, delete the password dataIf Device is renamed, copy the password data
sub FB_CALLMONITOR_Delete($$)
{
    my ($hash, $name) = @_;

    my $index = "FB_CALLMONITOR_".$name."_passwd";

    setKeyValue($index, undef);

    return undef;
}

#######################################################################
# If Device is renamed, copy the password data
sub FB_CALLMONITOR_Rename($$)
{
    my ($new, $old) = @_;

    my $old_index = "FB_CALLMONITOR_" . $old . "_passwd";
    my $new_index = "FB_CALLMONITOR_" . $new . "_passwd";

    my $old_key =getUniqueId() . $old_index;
    my $new_key =getUniqueId() . $new_index;

    my ($err, $old_pwd) = getKeyValue($old_index);

    return undef unless(defined($old_pwd));

    setKeyValue($new_index, FB_CALLMONITOR_encrypt(FB_CALLMONITOR_decrypt($old_pwd,$old_key), $new_key));
    setKeyValue($old_index, undef);
}

#######################################################################
# Get function for returning a reverse search name
sub FB_CALLMONITOR_Get($@)
{
    my ($hash, @arguments) = @_;

    return "argument missing" if(int(@arguments) < 2);

    if($arguments[1] eq "search" and int(@arguments) >= 3)
    {
        my $number = FB_CALLMONITOR_normalizePhoneNumber($hash, join '', @arguments[2..$#arguments]);
        my $result = FB_CALLMONITOR_reverseSearch($hash, $number, 1);

        return $result if(defined($result));
        return "no reverse search result found for $number";
    }
    elsif($arguments[1] eq "showPhonebookIds" and exists($hash->{helper}{PHONEBOOK_NAMES}))
    {
        my $table = "";
        my $head = "Id    Name";
        my $width = 10;

        foreach my $phonebookId (sort keys %{$hash->{helper}{PHONEBOOK_NAMES}})
        {
            my $string = sprintf("%-3s", $phonebookId)." - ".$hash->{helper}{PHONEBOOK_NAMES}{$phonebookId};
            $width = length($string) if(length($string) > $width);
            $table .= $string."\n";
        }

        return $head."\n".("-" x $width)."\n".$table;
    }
    elsif($arguments[1] eq "showPhonebookEntries" and (exists($hash->{helper}{PHONEBOOK}) or exists($hash->{helper}{PHONEBOOKS})) and int(@arguments) <= 3)
    {
        return "given argument is not a valid phonebook id: ".$arguments[2] if(int(@arguments) == 3 and ($arguments[2] !~ /^\d+$/ or !exists($hash->{helper}{PHONEBOOKS}{$arguments[2]}) ) );

        my $return = "";

        if(exists($hash->{helper}{PHONEBOOKS}))
        {
            foreach my $pb_id (sort keys %{$hash->{helper}{PHONEBOOKS}})
            {
                next if(int(@arguments) == 3 and int($arguments[2]) != $pb_id);

                my $number_width = 0;
                my $name_width = 0;
                my $table = "";

                if(defined($hash->{helper}{PHONEBOOKS}{$pb_id}) and scalar(keys(%{$hash->{helper}{PHONEBOOKS}{$pb_id}})) > 0)
                {
                    foreach my $number (keys %{$hash->{helper}{PHONEBOOKS}{$pb_id}})
                    {
                        $number_width = length($number) if($number_width < length($number));
                        $name_width = length($hash->{helper}{PHONEBOOKS}{$pb_id}{$number}) if($name_width < length($hash->{helper}{PHONEBOOKS}{$pb_id}{$number}));
                    }

                    my $head = "Phonebook: ".$hash->{helper}{PHONEBOOK_NAMES}{$pb_id}." / Id: $pb_id\n\n   ".sprintf("%-".$number_width."s   %s" ,"Number", "Name");

                    foreach my $number (sort { lc($hash->{helper}{PHONEBOOKS}{$pb_id}{$a}) cmp lc($hash->{helper}{PHONEBOOKS}{$pb_id}{$b}) } keys %{$hash->{helper}{PHONEBOOKS}{$pb_id}})
                    {
                        my $string = sprintf("   %-".$number_width."s - %s" , $number,$hash->{helper}{PHONEBOOKS}{$pb_id}{$number});
                        $table .= $string."\n";
                    }

                    $return .= $head."\n   ".("-" x ($number_width + $name_width + 3))."\n".$table."\n";
                }
            }
       }

       if(exists($hash->{helper}{PHONEBOOK}) and int(@arguments) == 2)
       {
            my $number_width = 0;
            my $name_width = 0;
            my $table = "";

            foreach my $number (keys %{$hash->{helper}{PHONEBOOK}})
            {
                $number_width = length($number) if($number_width < length($number));
                $name_width = length($hash->{helper}{PHONEBOOK}{$number}) if($name_width < length($hash->{helper}{PHONEBOOK}{$number}));
            }

            my $head = sprintf("Phonebook file\n\n   %-".$number_width."s   %s" ,"Number", "Name");

            foreach my $number (sort { lc($hash->{helper}{PHONEBOOK}{$a}) cmp lc($hash->{helper}{PHONEBOOK}{$b}) } keys %{$hash->{helper}{PHONEBOOK}})
            {
                my $string = sprintf("   %-".$number_width."s - %s" , $number,$hash->{helper}{PHONEBOOK}{$number});
                $table .= $string."\n";
            }

            $return .= $head."\n   ".("-" x ($number_width + $name_width + 3))."\n".$table
        }

        return $return;
    }
    elsif($arguments[1] eq "showCacheEntries" and exists($hash->{helper}{CACHE}))
    {
        my $table = "";

        my $number_width = 0;
        my $name_width = 0;

        foreach my $number (keys %{$hash->{helper}{CACHE}})
        {
            $number_width = length($number) if($number_width < length($number));
            $name_width = length($hash->{helper}{CACHE}{$number}) if($name_width < length($hash->{helper}{CACHE}{$number}));
        }

        my $head = sprintf("%-".$number_width."s   %s" ,"Number", "Name");

        foreach my $number (sort { lc($hash->{helper}{CACHE}{$a}) cmp lc($hash->{helper}{CACHE}{$b}) } keys %{$hash->{helper}{CACHE}})
        {
            my $string = sprintf("%-".$number_width."s - %s" , $number,$hash->{helper}{CACHE}{$number});
            $table .= $string."\n";
        }

        return $head."\n".("-" x ($number_width + $name_width + 3))."\n".$table;
    }
    elsif($arguments[1] eq "showTextfileEntries" and exists($hash->{helper}{TEXTFILE}))
    {
        my $table = "";

        my $number_width = 0;
        my $name_width = 0;

        foreach my $number (keys %{$hash->{helper}{TEXTFILE}})
        {
            $number_width = length($number) if($number_width < length($number));
            $name_width = length($hash->{helper}{TEXTFILE}{$number}) if($name_width < length($hash->{helper}{TEXTFILE}{$number}));
        }

        my $head = sprintf("%-".$number_width."s   %s" ,"Number", "Name");

        foreach my $number (sort { lc($hash->{helper}{TEXTFILE}{$a}) cmp lc($hash->{helper}{TEXTFILE}{$b}) } keys %{$hash->{helper}{TEXTFILE}})
        {
            my $string = sprintf("%-".$number_width."s - %s" , $number,$hash->{helper}{TEXTFILE}{$number});
            $table .= $string."\n";
        }

        return $head."\n".("-" x ($number_width + $name_width + 3))."\n".$table;
    }
    else
    {
        return "unknown argument ".$arguments[1].", choose one of search".(exists($hash->{helper}{PHONEBOOK_NAMES}) ? " showPhonebookIds:noArg" : "").
                                                                          ((exists($hash->{helper}{PHONEBOOK}) or exists($hash->{helper}{PHONEBOOKS})) ? " showPhonebookEntries" : "").
                                                                          (exists($hash->{helper}{CACHE}) ? " showCacheEntries:noArg" : "").
                                                                          (exists($hash->{helper}{TEXTFILE}) ? " showTextfileEntries:noArg" : "");
    }
}

#######################################################################
# Set function for executing a reread of the internal phonebook
sub FB_CALLMONITOR_Set($@)
{
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};
    my $usage;
    my @sets = ();

    push @sets, "rereadPhonebook:noArg" if(defined($hash->{helper}{PHONEBOOK}) or AttrVal($name, "reverse-search" , "") =~ /(all|phonebook|internal)/);
    push @sets, "rereadCache:noArg" if(defined(AttrVal($name, "reverse-search-cache-file" , undef)));
    push @sets, "rereadTextfile:noArg" if(defined(AttrVal($name, "reverse-search-text-file" , undef)));
    push @sets, "password" if($hash->{helper}{PWD_NEEDED});
    push @sets, "reopen:noArg" if($hash->{FD});

    $usage = "Unknown argument ".$a[1].", choose one of ".join(" ", @sets) if(scalar @sets > 0);

    if($a[1] eq "rereadPhonebook")
    {
        FB_CALLMONITOR_readPhonebook($hash);
        return undef;
    }
    elsif($a[1] eq "rereadCache")
    {
        FB_CALLMONITOR_loadCacheFile($hash);
        return undef;
    }
    elsif($a[1] eq "rereadTextfile")
    {
        FB_CALLMONITOR_loadTextFile($hash);
        return undef;
    }
    elsif($a[1] eq "password")
    {
        return FB_CALLMONITOR_storePassword($hash, $a[2]) if($hash->{helper}{PWD_NEEDED});
        FB_CALLMONITOR_Log $name, 2, "SOMEONE UNWANTED TRIED TO SET A NEW FRITZBOX PASSWORD!!!";
        return "I didn't ask for a password, so go away!!!"
    }
    elsif($a[1] eq "reopen")
    {
        DevIo_CloseDev($hash);
        DevIo_OpenDev($hash, 0, undef, \&FB_CALLMONITOR_DevIoCallback);
        return undef;
    }
    else
    {
        return $usage;
    }
}


#######################################################################
# Receives an event and creates several readings for event triggering
sub FB_CALLMONITOR_Read($)
{
    my ($hash) = @_;

    my $received = DevIo_SimpleRead($hash);
    my $buffer = $hash->{PARTIAL};

    return "" if(!defined($received) or IsDisabled($hash->{NAME}));

    my $name = $hash->{NAME};
    my @array;

    my $area_code = AttrVal($name, "local-area-code", "");
    my $country_code = AttrVal($name, "country-code", "0049");

    $buffer .= $received;

    while($buffer =~ m/\n/)
    {
        my $data;

        ($data, $buffer) = split("\n", $buffer, 2);

        chomp $data;

        my $external_number = undef;
        my $reverse_search = undef;

        FB_CALLMONITOR_Log $name, 5, "received data: $data";

        @array = split(";", $data);

        $external_number = $array[3] if(not $array[3] eq "0" and $array[1] eq "RING" and $array[3] ne "");
        $external_number = $array[5] if($array[1] eq "CALL" and $array[3] ne "");

        FB_CALLMONITOR_Log $name, 4, "received event ".$array[1]." for call id ".$array[2].(defined($external_number) ? " (external number: $external_number)" : "");

        if(defined($external_number))
        {
            $external_number =~ s/^0// if(AttrVal($name, "remove-leading-zero", "0") eq "1");

            if($array[1] eq "CALL")
            {
                # Remove Call-By-Call number (Germany)
                $external_number =~ s/^(010[1-9]\d|0100[1-9]\d)//g if($country_code eq "0049");

                # Remove Call-By-Call number (Austria)
                $external_number =~ s/^10\d\d//g if($country_code eq "0043");

                # Remove Call-By-Call number (Swiss)
                $external_number =~ s/^(107\d\d|108\d\d)//g if($country_code eq "0041");
            }

            if($external_number =~ /^\d/ and $external_number !~ /^0/ and $external_number !~ /^11/ and $area_code ne "")
            {
                if($area_code =~ /^0[1-9]\d+$/ and $external_number =~ /^[1-9].+$/)
                {
                    $external_number = $area_code.$external_number;
                }
                elsif($area_code !~ /^0[1-9]\d+$/)
                {
                    FB_CALLMONITOR_Log $name, 2, "given local area code '$area_code' is not an area code. therefore will be ignored";
                }
            }

            # Remove trailing hash sign and everything afterwards
            $external_number =~ s/#.*$// if($external_number !~ /^\*/); # Forum #85761

            $reverse_search = FB_CALLMONITOR_reverseSearch($hash, $external_number, ($array[1] eq "RING")) if(AttrVal($name, "reverse-search", "none") ne "none");

            FB_CALLMONITOR_Log $name, 4, "reverse search returned: $reverse_search" if(defined($reverse_search));

        }

        if($array[1] =~ /^CALL|RING$/)
        {
            delete($hash->{helper}{TEMP}{$array[2]});

            if(AttrVal($name, "unique-call-ids", "0") eq "1")
            {
                $hash->{helper}{TEMP}{$array[2]}{call_id} = Digest::MD5::md5_hex($data);
            }
            else
            {
                $hash->{helper}{TEMP}{$array[2]}{call_id} = $array[2];
            }

            $hash->{helper}{TEMP}{$array[2]}{external_number} = (defined($external_number) ? $external_number : "unknown");
            $hash->{helper}{TEMP}{$array[2]}{external_name} = (defined($reverse_search) ? $reverse_search : "unknown");
            $hash->{helper}{TEMP}{$array[2]}{internal_number} = $array[4];

            if(my $contact_image = FB_CALLMONITOR_getContactImage($hash, $hash->{helper}{TEMP}{$array[2]}{external_number}))
            {
                $hash->{helper}{TEMP}{$array[2]}{contact_image} = $contact_image;
            }

            if(FB_CALLMONITOR_checkNumberIsFiltered($hash, $hash->{helper}{TEMP}{$array[2]}{internal_number}))
            {
                $hash->{helper}{TEMP}{$array[2]}{".filtered"} = 1
            }
        }

        if($array[1] eq "CALL")
        {
            $hash->{helper}{TEMP}{$array[2]}{external_connection} = $array[6];
            $hash->{helper}{TEMP}{$array[2]}{internal_connection} = $connection_type{$array[3]} if(defined($connection_type{$array[3]}));
            $hash->{helper}{TEMP}{$array[2]}{direction} = "outgoing";
        }

        if($array[1] eq "RING")
        {
            $hash->{helper}{TEMP}{$array[2]}{external_connection} = $array[5];
            $hash->{helper}{TEMP}{$array[2]}{direction} = "incoming";
            $hash->{helper}{TEMP}{$array[2]}{".deflected"} = FB_CALLMONITOR_checkNumberForDeflection($hash, $external_number);

            my @attr_list = split(/,|\|/, AttrVal($name, "reverse-search", ""));

            ### tellows only if enabled
            if (grep { /^(tellows\.de)$/ } @attr_list) {
               $hash->{helper}{TEMP}{$array[2]}{tellows_score} = (defined($tellows{score}) ? $tellows{score} : "unknown");	### tellows
               $hash->{helper}{TEMP}{$array[2]}{tellows_searches} = (defined($tellows{searches}) ? $tellows{searches} : "unknown");	### tellows
               $hash->{helper}{TEMP}{$array[2]}{tellows_comments} = (defined($tellows{comments}) ? $tellows{comments} : "unknown");	### tellows
               $hash->{helper}{TEMP}{$array[2]}{tellows_scoreColor} = (defined($tellows{scoreColor}) ? $tellows{scoreColor} : "unknown");	### tellows
               $hash->{helper}{TEMP}{$array[2]}{tellows_scorePath} = (defined($tellows{scorePath}) ? $tellows{scorePath} : "unknown");	### tellows
               $hash->{helper}{TEMP}{$array[2]}{tellows_location} = (defined($tellows{location}) ? $tellows{location} : "unknown");	### tellows
               $hash->{helper}{TEMP}{$array[2]}{tellows_country} = (defined($tellows{country}) ? $tellows{country} : "unknown");	### tellows
               $hash->{helper}{TEMP}{$array[2]}{tellows_mostCritic} = (defined($tellows{mostCritic}) ? $tellows{mostCritic} : "unknown");	### tellows
               $hash->{helper}{TEMP}{$array[2]}{tellows_mostCriticCount} = (defined($tellows{mostCriticCount}) ? $tellows{mostCriticCount} : "unknown");	### tellows
               $hash->{helper}{TEMP}{$array[2]}{tellows_text} = (defined($tellows{text}) ? $tellows{text} : "unknown");	### tellows
            }
        }

        if($array[1] eq "CONNECT" and not exists($hash->{helper}{TEMP}{$array[2]}{internal_connection}))
        {
            $hash->{helper}{TEMP}{$array[2]}{internal_connection} = $connection_type{$array[3]} if(defined($connection_type{$array[3]}));
            $hash->{helper}{TEMP}{$array[2]}{".internal_connection_id"} = $array[3] if(defined($connection_type{$array[3]}));
        }

        if($array[1] eq "DISCONNECT")
        {
            $hash->{helper}{TEMP}{$array[2]}{call_duration} = $array[3];

            if(exists($hash->{helper}{TEMP}{$array[2]}{direction}) and $hash->{helper}{TEMP}{$array[2]}{direction} eq "incoming")
            {
                if(($hash->{helper}{TEMP}{$array[2]}{".last-event"} eq "RING") or (AttrVal($name, "answMachine-is-missed-call", "0") eq "1" and exists($hash->{helper}{TEMP}{$array[2]}{internal_connection}) and $hash->{helper}{TEMP}{$array[2]}{".internal_connection_id"} =~/^4[0-4]$/))
                {
                    $hash->{helper}{TEMP}{$array[2]}{missed_call} = $hash->{helper}{TEMP}{$array[2]}{external_number}.(exists($hash->{helper}{TEMP}{$array[2]}{external_name}) and $hash->{helper}{TEMP}{$array[2]}{external_name} ne "unknown" ? " (".$hash->{helper}{TEMP}{$array[2]}{external_name}.")" : "");
                }
            }
        }

        $hash->{helper}{TEMP}{$array[2]}{".last-event"} = $array[1];

        # skip readings/event generation if call does not matched a configured internal number filter
        if($hash->{helper}{TEMP}{$array[2]}{".filtered"})
        {
            FB_CALLMONITOR_Log $name, 4, "skipped creating readings/events because number does not match configured attribute internal-number-filter";

            if($array[1] eq "DISCONNECT")
            {
                delete($hash->{helper}{TEMP}{$array[2]});
            }

            next;
        }

        # skip readings/event generation if call is deflected
        if($hash->{helper}{TEMP}{$array[2]}{".deflected"})
        {
            FB_CALLMONITOR_Log $name, 4, "skipped creating readings/events due to deflection match";

            if($array[1] eq "DISCONNECT")
            {
                delete($hash->{helper}{TEMP}{$array[2]});
            }

            next;
        }

        # create readings/events
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "event", lc($array[1]));

        foreach my $key (keys %{$hash->{helper}{TEMP}{$array[2]}})
        {
            readingsBulkUpdate($hash, $key, $hash->{helper}{TEMP}{$array[2]}{$key}) unless($key =~ /^\./);
        }

        if($array[1] eq "DISCONNECT")
        {
            delete($hash->{helper}{TEMP}{$array[2]});
        }

        readingsBulkUpdate($hash, "calls_count", scalar grep { not ($hash->{helper}{TEMP}{$_}{".filtered"} or $hash->{helper}{TEMP}{$_}{".deflected"}) } keys %{$hash->{helper}{TEMP}});
        readingsEndUpdate($hash, 1);
    }

    $hash->{PARTIAL} = $buffer;
}

#######################################################################
# catches error message during connection setup
sub FB_CALLMONITOR_DevIoCallback($$)
{
    my ($hash, $err) = @_;
    my $name = $hash->{NAME};

    if($err)
    {
        FB_CALLMONITOR_Log $name, 4, "unable to connect to Fritz!Box: $err";
    }
}


#######################################################################
# Reconnects to FritzBox in case of disconnects
sub FB_CALLMONITOR_Ready($)
{
    my ($hash) = @_;

    return DevIo_OpenDev($hash, 1, undef, \&FB_CALLMONITOR_DevIoCallback);
}

#######################################################################
# Handles Attribute Changes
sub FB_CALLMONITOR_Attr($@)
{
    my ($cmd, $name, $attrib, $value) = @_;
    my $hash = $defs{$name};

    if($cmd eq "set")
    {
        if((($attrib eq "reverse-search" and $value =~ /phonebook|tellows/) or $attrib eq "reverse-search-phonebook-file" or $attrib eq "fritzbox-remote-phonebook") and $init_done)
        {
           if($value =~ /tellows/) {
              if ($attr{$name}{"reverse-search-tellows-api-key"} && $attr{$name}{"reverse-search-tellows-api-partner"}) {
                 my $result = GetFileFromURL("http://www.tellows.de/basic/num/0221?xml=1&partner=".AttrVal($name, "reverse-search-tellows-api-partner","")."&apikey=".AttrVal($name,"reverse-search-tellows-api-key",""), 5);

                 if($result =~ /ERROR(.*?)/) {
                    return "tellows: $1";
                 }
                 if(not defined($result)){
                    return "tellows api and/or api-partner not valid";
                 }
              } else {
                 return "tellows api-key and/or api-partner not defined.";
              }
           } else {
              foreach (keys %{ $hash->{READINGS} }) {
                 readingsDelete($hash, $_) if $_ =~ /^tellows_/ && defined $hash->{READINGS}{$_}{VAL};
              }
           }

           if($value =~ /phonebook/) {
             $attr{$name}{$attrib} = $value;
             return FB_CALLMONITOR_readPhonebook($hash);
           }
        }

        if($attrib eq "reverse-search-cache-file")
        {
            return FB_CALLMONITOR_loadCacheFile($hash, $value);
        }

        if($attrib eq "reverse-search-text-file")
        {
            return FB_CALLMONITOR_loadTextFile($hash, $value);
        }

        if($attrib eq "disable" and $value eq "1")
        {
            DevIo_CloseDev($hash);
            delete($hash->{NEXT_OPEN});
            $hash->{STATE} = "disabled";
        }
        elsif($attrib eq "disable" and $value eq "0")
        {
            DevIo_OpenDev($hash, 0, undef, \&FB_CALLMONITOR_DevIoCallback);
        }

        if($attrib eq "sendKeepAlives" and $value !~ /^none|(?:5|10|15|30)m|1h$/)
        {
            return "invalid value $value for $attrib. Allowed values are: none,5m,10m,15m,30m,1h";
        }

        if($attrib eq "internal-number-filter")
        {
            if($value !~ /^\d+(?:,\d+)*$/)
            {
                return 'invalid value $value for $attrib. It should contain a single internal number or a comma separated list of multiple internal numbers. (e.g. "12345" or "12345,56789")';
            }

            delete($hash->{helper}{INTERNAL_FILTER});

            foreach my $item (split("[ \t,][ \t,]*",$value))
            {
                $hash->{helper}{INTERNAL_FILTER}{$item} = 1;
            }
        }
    }
    elsif($cmd eq "del")
    {
        if($attrib eq "reverse-search" or $attrib eq "reverse-search-phonebook-file")
        {
           delete($hash->{helper}{PHONEBOOK});

           foreach (keys %{ $hash->{READINGS} }) {
              readingsDelete($hash, $_) if $_ =~ /^tellows_/ && defined $hash->{READINGS}{$_}{VAL};
           }
        }

        if($attrib eq "reverse-search-cache")
        {
            delete($hash->{helper}{CACHE});
        }

        if($attrib eq "reverse-search-text-file")
        {
            delete($hash->{helper}{TEXTFILE});
        }

        if($attrib eq "internal-number-filter")
        {
           delete($hash->{helper}{INTERNAL_FILTER});
        }

        if($attrib eq "disable")
        {
            DevIo_OpenDev($hash, 0, undef, \&FB_CALLMONITOR_DevIoCallback);
        }
    }

    return undef;
}

#######################################################################
# receives events, waits for global INITIALIZED or REREADCFG
# to initiate the phonebook initialization
sub
FB_CALLMONITOR_Notify($$)
{
    my ($hash, $device) = @_;
    my $name = $hash->{NAME};

    my $events = deviceEvents($device, undef);

    return if($device->{NAME} ne "global");

    FB_CALLMONITOR_sendKeepAlive($hash)  if(grep(m/(?:DELETE)?ATTR $name sendKeepAlives/, @{$events}));

    return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$events}));

    FB_CALLMONITOR_readPhonebook($hash);

    return undef;
}

#######################################################################
#
#   Begin of helper functions
#
#######################################################################


#######################################################################
# Performs a reverse search of a phone number
sub FB_CALLMONITOR_reverseSearch($$$) {
   my ($hash, $number, $ring) = @_;
   my $name = $hash->{NAME};
   my $result;
   my $status;
   my $invert_match = undef;
   my $country_code = AttrVal($name, "country-code", "0049");
   my @attr_list = split(/,|\|/, AttrVal($name, "reverse-search", ""));

   foreach my $method (@attr_list) {

      FB_CALLMONITOR_Log $name, 4, "methode: $method";

      # Ask tellows.de at first
      if($method eq "tellows.de" and $ring == 1) {

         FB_CALLMONITOR_Log $name, 4, "reverse search for $number at tellows.de.";
         unless (AttrVal($name, "reverse-search-tellows-api-key", undef) || AttrVal($name, "reverse-search-tellows-api-partner", undef)) {
            FB_CALLMONITOR_Log $name, 4, "reverse search cancled for $number at tellows.de.";
            $status = "tellows.de -> login missing";
         } else {
            $result = FB_CALLMONITOR_tellowsRating($hash, $number);	### tellows	!!! $external_number --> $number !!!

            if(not defined($result)) {
               $status = "tellows.de -> timeout";
               undef($result);
            } else {
               if( $result =~ /<name>([^"].*?)</ ) {
                  $invert_match = $1;
                  $invert_match = FB_CALLMONITOR_html2txt($invert_match);
                  FB_CALLMONITOR_writeToCache($hash, $number, $invert_match);
#                  $status = $invert_match;
#                  undef($result);
               } elsif ( $result =~ /ERROR(.*?)/ ) {
                  FB_CALLMONITOR_Log $name, 4, "reverse search name $number not available from tellows.de. $1.";
#                  $status = "error";
#                  undef($result);
               } else {
                  FB_CALLMONITOR_Log $name, 4, "unknown error for $number at tellows.de. $1.";
#                  $status = "unknown error";
#                  undef($result);
               }
            }
            undef($result);
         }
      }

      # Using internal phonebook if available and enabled
      if($method eq "phonebook")
      {
         if(exists($hash->{helper}{PHONEBOOK})) {
            if(defined($hash->{helper}{PHONEBOOK}{$number})) {
               FB_CALLMONITOR_Log $name, 4, "using internal phonebook for reverse search of $number";
               return $hash->{helper}{PHONEBOOK}{$number};
            } elsif(my $result = FB_CALLMONITOR_searchPhonebookWildcards($hash->{helper}{PHONEBOOK}, $number)) {
               FB_CALLMONITOR_Log $name, 4, "using internal phonebook for reverse search of $number";
               return $result;
            }
         }

         if(exists($hash->{helper}{PHONEBOOKS})) {
            foreach my $pb_id (keys %{$hash->{helper}{PHONEBOOKS}}) {
               if(defined($hash->{helper}{PHONEBOOKS}{$pb_id}{$number})) {
                  FB_CALLMONITOR_Log $name, 4, "using internal phonebook for reverse search of $number";
                  return $hash->{helper}{PHONEBOOKS}{$pb_id}{$number};
               } elsif(my $result = FB_CALLMONITOR_searchPhonebookWildcards($hash->{helper}{PHONEBOOKS}{$pb_id}, $number)) {
                  FB_CALLMONITOR_Log $name, 4, "using internal phonebook for reverse search of $number";
                  return $result;
               }
            }
         }
      }

      # Using user defined textfile
      elsif($method eq "textfile")
      {
         if(exists($hash->{helper}{TEXTFILE}) and defined($hash->{helper}{TEXTFILE}{$number}))
         {
            FB_CALLMONITOR_Log $name, 4, "using textfile for reverse search of $number";
            return $hash->{helper}{TEXTFILE}{$number};
         }
      }

      else {

         # Using Cache if enabled
         if(AttrVal($name, "reverse-search-cache", "0") eq "1" and defined($hash->{helper}{CACHE}{$number}))
         {
            if($hash->{helper}{CACHE}{$number} ne "timeout" && $hash->{helper}{CACHE}{$number} ne "unknown")
            {
               return $hash->{helper}{CACHE}{$number};
            }
         }

         # Ask dasoertliche.de
         if($method eq "dasoertliche.de")
         {
            unless(($number =~ /^0?[1-9]/ and $country_code eq "0049") or $number =~ /^0049/)
            {
               FB_CALLMONITOR_Log $name, 4, "skip using dasoertliche.de for reverse search of $number because of non-german number";
            }
            else
            {
               $number =~ s/^0049/0/; # remove country code
               FB_CALLMONITOR_Log $name, 4, "using dasoertliche.de for reverse search of $number";

               $result = GetFileFromURL("https://www1.dasoertliche.de/?form_name=search_inv&ph=".$number, 5, undef, 1);
               if(not defined($result))
               {
                  $status = "timeout";
                  undef($result);
               }
               else
               {
                  FB_CALLMONITOR_Log $name, 5, "result(dasOertliche) -> " . $result;
                  if($result =~ m,<a href="[^"]*form_name=detail[^"]*".+?class="hitlnk_name".+?target="_self">(.+?)</a>,sg)
                  {
                     $invert_match = $1;
                     $invert_match = FB_CALLMONITOR_html2txt($invert_match);
                     FB_CALLMONITOR_writeToCache($hash, $number, $invert_match);
                     undef($result);
                     return $invert_match;
                  }
                  elsif(not $result =~ /wir konnten keine Treffer finden/)
                  {
                     FB_CALLMONITOR_Log $name, 3, "the reverse search result for $number could not be extracted from dasoertliche.de. Please contact the FHEM community.";
                  } 
                  
                  $status = "unknown";
               }
            }
         }

         # Ask 11880.com
         elsif($method eq "11880.com")
         {
            unless(($number =~ /^0?[1-9]/ and $country_code eq "0049") or $number =~ /^0049/)
            {
               FB_CALLMONITOR_Log $name, 4, "skip using 11880.com for reverse search of $number because of non-german number";
            }
            else
            {
               $number =~ s/^0049/0/; # remove country code
               FB_CALLMONITOR_Log $name, 4, "using 11880.com for reverse search of $number";

               $result = GetFileFromURL("https://www.11880.com/suche/".$number."/deutschland", 5, undef, 1);

               if(not defined($result))
               {
                  FB_CALLMONITOR_Log $name, 4, "unable to retrieve result for reverse search of $number via $method";
                  $status = "timeout";
                  undef($result);
               }
               else
               {
                  FB_CALLMONITOR_Log $name, 5, "result(11880) -> " . $result;
                  if($result =~ m,<li\s+[^>]*class="search-result-list-item"\s+[^>]*data-name="([^"]+)",s or $result =~ m,<h\d [^>]*itemprop="name"[^>]*>([^<]+)</h\d>,)
                  {
                     $invert_match = $1;
                     $invert_match = FB_CALLMONITOR_html2txt($invert_match);
                     FB_CALLMONITOR_writeToCache($hash, $number, $invert_match);
                     undef($result);
                     return $invert_match;
                  }
                  elsif(not $result =~ /Leider nichts gefunden/i)
                  {
                     FB_CALLMONITOR_Log $name, 3, "the reverse search result for $number could not be extracted from 11880.com. Please contact the FHEM community.";
                  }

                  $status = "unknown";
               }
            }
         }

         # SWITZERLAND ONLY!!! Ask search.ch
         elsif($method eq  "search.ch")
         {
            unless(($number =~ /^0?[1-9]/ and $country_code eq "0041") or $number =~ /^0041/)
            {
               FB_CALLMONITOR_Log $name, 4, "skip using search.ch for reverse search of $number because of non-swiss number";
            } else {

               my $api_key = AttrVal($name, "apiKeySearchCh", undef);

               unless(defined($api_key)) {
                  FB_CALLMONITOR_Log $name, 1, "WARNING! no API key for swiss.ch configured. Please obtain an API key from https://tel.search.ch/api/getkey and set attribute apiKeySearchCh with your key";

                  # use old key
                  FB_CALLMONITOR_Log $name, 1, "using generic API key for reverse search via search.ch. WILL BE REMOVED IN A FUTURE RELEASE";
                  $api_key = "b0b1207cb7c9d0048867de887aa9a4fd";
               }

               $number =~ s/^0041/0/; # remove country code

               FB_CALLMONITOR_Log $name, 4, "using search.ch for reverse search of $number";

               $result = GetFileFromURL("http://tel.search.ch/api/?key=".urlEncode($api_key)."&maxnum=1&was=".$number, 5, undef, 1);
               if(not defined($result)) {
                  $status = "timeout";
                  undef($result);
               } else {
                  FB_CALLMONITOR_Log $name, 5, "result(search.ch) -> " . $result;
                  if($result =~ m,<entry>(.+?)</entry>,s) {
                     my $xml = $1;

                     $invert_match = "";
                     if($xml =~ m,<tel:firstname>(.+?)</tel:firstname>,) {
                        $invert_match .= $1;
                     }

                     if($xml =~ m,<tel:name>(.+?)</tel:name>,) {
                        $invert_match .= " $1";
                     }

                     if($xml =~ m,<tel:occupation>(.+?)</tel:occupation>,) {
                        $invert_match .= ", $1";
                     }

                     $invert_match = FB_CALLMONITOR_html2txt($invert_match);
                     FB_CALLMONITOR_writeToCache($hash, $number, $invert_match);
                     undef($result);
                     return $invert_match;
                  }
                  $status = "unknown";
               }
            }
         }

         # Austria ONLY!!! Ask dasschnelle.at
         elsif($method eq "dasschnelle.at")
         {
            unless(($number =~ /^0?[1-9]/ and $country_code eq "0043") or $number =~ /^0043/)
            {
               FB_CALLMONITOR_Log $name, 4, "skip using dasschnelle.at for reverse search of $number because of non-austrian number";
            }
            else
            {
               $number =~ s/^0043/0/; # remove country code
               FB_CALLMONITOR_Log $name, 4, "using dasschnelle.at for reverse search of $number";

               $result = GetFileFromURL("http://www.dasschnelle.at/ergebnisse?what=".$number."&where=&rubrik=0&bezirk=0&orderBy=Standard&mapsearch=false", 5, undef, 1);
               if(not defined($result))
               {
                  $status = "timeout";
                  undef($result);
               } else {
                  #Log 2, $result;
                  FB_CALLMONITOR_Log $name, 5, "result(dasschnelle.at) -> " . $result;
                  if($result =~ /"name"\s*:\s*"([^"]+)",/)
                  {
                     $invert_match = "";

                     while($result =~ /"name"\s*:\s*"([^"]+)",/g) {
                        $invert_match = $1 if(length($1) > length($invert_match));
                     }

                     $invert_match = FB_CALLMONITOR_html2txt($invert_match);
                     FB_CALLMONITOR_writeToCache($hash, $number, $invert_match);
                     undef($result);
                     return $invert_match;
                  }
                  elsif(not $result =~ /Ihre Suche nach .* war erfolglos/)
                  {
                     FB_CALLMONITOR_Log $name, 3, "the reverse search result for $number could not be extracted from dasschnelle.at. Please contact the FHEM community.";
                  }
                  $status = "unknown";
               }
            }
         }

         # Austria ONLY!!! Ask herold.at
         elsif($method eq "herold.at")
         {
            unless(($number =~ /^0?[1-9]/ and $country_code eq "0043") or $number =~ /^0043/)
            {
               FB_CALLMONITOR_Log $name, 4, "skip using herold.at for reverse search of $number because of non-austrian number";
            } else {
               $number =~ s/^0043/0/; # remove country code
               FB_CALLMONITOR_Log $name, 4, "using herold.at for reverse search of $number";

               $result = GetFileFromURL("https://www.herold.at/gelbe-seiten/telefon_".$number."/", 5, undef, 1);

               if(not defined($result)) {
                  FB_CALLMONITOR_Log $name, 4, "unable to retrieve result for reverse search of $number via $method";
                  $status = "timeout";
                  undef($result);
               } else {
                  #Debug($result);
                  FB_CALLMONITOR_Log $name, 5, "result(herold.at) -> " . $result;
                  if($result =~ m,data-clickpos="name"><span itemprop="name">([^<]+)</span>,)
                  {
                     $invert_match = $1;
                     $invert_match = FB_CALLMONITOR_html2txt($invert_match);
                     FB_CALLMONITOR_writeToCache($hash, $number, $invert_match);
                     undef($result);
                     return $invert_match;
                  }
                  elsif($result !~ /Wir konnten zu den eingegebenen Suchkriterien keine Ergebnisse finden/)
                  {
                     FB_CALLMONITOR_Log $name, 3, "the reverse search result for $number could not be extracted from herold.at. Please contact the FHEM community.";
                  }
                  $status = "unknown";
               }
            }
         }
         else
         {
            FB_CALLMONITOR_Log $name, 3, "unknown reverse search method $method" if ($method ne "tellows.de");
         }
      }
    }

    if(AttrVal($name, "reverse-search-cache", "0") eq "1" and defined($status))
    {
        # If no result is available set cache result and return undefined
        $hash->{helper}{CACHE}{$number} = $status;
    }

    return undef;
}

#######################################################################
# calls tellows api
#<tellows>
#  <number>0781968053101</number>
#  <normalizedNumber>0781-968053101</normalizedNumber>
#  <score>7</score>
#  <searches>1077</searches>
#  <comments>5</comments>
#  <scoreColor>#f79a01</scoreColor>
#  <scorePath>https://www.tellows.de/images/score/score7.png</scorePath>
#  <location>Offenburg</location>
#  <country>Deutschland</country>
#  <callerTypes>
#    <caller>
#      <name>Unbekannt</name>
#      <count>2</count>
#    </caller>
#    <caller>
#      <name>Gewinnspiel</name>
#      <count>1</count>
#    </caller>
#    <caller>
#      <name>Meinungsforschung</name>
#      <count>1</count>
#    </caller>
#    <caller>
#      <name>Vermarkter Hotline</name>
#      <count>1</count>
#    </caller>
#  </callerTypes>
#</tellows>
#http://www.tellows.de/basic/num/0781968053101?xml=1&partner=test&apikey=test123
#
sub FB_CALLMONITOR_tellowsRating($$){
   my ($hash, $number) = @_;
   my $name = $hash->{NAME};
   my $result = GetFileFromURL("http://www.tellows.de/basic/num/".$number."?xml=1&partner=".AttrVal($name, "reverse-search-tellows-api-partner","")."&apikey=".AttrVal($name,"reverse-search-tellows-api-key",""), 5);

   FB_CALLMONITOR_Log $name, 5, "reverse search tellows: $number";

   %tellows = ();

   if(not defined($result)){
      return undef;
   } else {
      $result =~ /<score>(\d)/;
      $tellows{'score'} = $1;

      $result =~ /<searches>([\d]+)/;
      $tellows{'searches'} = $1;

      $result =~ /<comments>([\d]+)/;
      $tellows{'comments'} = $1;

      $result =~ /<scoreColor>([^"]*?)</;
      $tellows{'scoreColor'} = $1;

      $result =~ /<scorePath>([^"]*?)</;
      $tellows{'scorePath'} = $1;

      $result =~ /<location>([^"]*?)</;
      $tellows{'location'} = $1;

      $result =~ /<country>([^"]*?)</;
      $tellows{'country'} = $1;

      if($result =~ /<name>([^"]*?)</){
         $tellows{'mostCritic'} = $1;
         $result =~ /<count>([\d]+)/;
         $tellows{'mostCriticCount'} = $1;
      }	else {
         $tellows{'mostCritic'} = 0;
         $tellows{'mostCriticCount'} = 0;
      }

      $tellows{'location'} = $tellows{'location'} . ", " . $tellows{'country'} if ($tellows{'country'} ne "Deutschland");

      if($tellows{'score'} == 5){
         $tellows{'text'} = "aus ".$tellows{'location'}.", Tellows-Score: neutral";
      } elsif($tellows{'score'} < 5) {
         $tellows{'text'} = "aus ".$tellows{'location'}.", Tellows-Score: positiv (".$tellows{'score'}."), h�ufigster Lob: ".$tellows{'mostCritic'}." (".$tellows{'mostCriticCount'}." x)";
      }	else {
         $tellows{'text'} = "aus ".$tellows{'location'}.", Tellows-Score: negativ (".$tellows{'score'}."), h�ufigster Reklamegrund: ".$tellows{'mostCritic'}." (".$tellows{'mostCriticCount'}." x)";
      }

      return $result;
   }

} ### tellows


############################################################################################################
# check a number against wildcard entries in a given phonebook list
sub FB_CALLMONITOR_searchPhonebookWildcards($$)
{
    my ($list, $number) = @_;

    foreach my $key (keys %{$list})
    {
        next if($key !~ /^\+?\d+\*$/);

        if(defined($list->{$key}))
        {
            my $test = $key;
            $test =~ s/\*$//;

            if(index($number,$test) == 0)
            {
                return $list->{$key}.substr($number,length($test));
            }
        }
    }

    return undef;
}

#######################################################################
# replaces all HTML entities to their utf-8 counter parts.
sub FB_CALLMONITOR_html2txt($)
{
    my ($string) = @_;

    $string =~ s/&nbsp;/ /g;
    $string =~ s/&amp;/&/g;
    $string =~ s/&pos;/'/g;


    $string =~ s/(\xe4|&auml;)/�/g;
    $string =~ s/(\xc4|&Auml;)/�/g;
    $string =~ s/(\xf6|&ouml;)/�/g;
    $string =~ s/(\xd6|&Ouml;)/�/g;
    $string =~ s/(\xfc|&uuml;)/�/g;
    $string =~ s/(\xdc|&Uuml;)/�/g;
    $string =~ s/(\xdf|&szlig;)/�/g;
    $string =~ s/(\xdf|&szlig;)/�/g;
    $string =~ s/(\xe1|&aacute;)/�/g;
    $string =~ s/(\xe9|&eacute;)/�/g;
    $string =~ s/(\xc1|&Aacute;)/�/g;
    $string =~ s/(\xc9|&Eacute;)/�/g;
    $string =~ s/\\u([a-f\d]{4})/encode('UTF-8',chr(hex($1)))/eig;
    $string =~ s/<[^>]+>//g;
    $string =~ s/&lt;/</g;
    $string =~ s/&gt;/>/g;
    $string =~ s/(?:^\s+|\s+$)//g;

    return $string;
}


#######################################################################
# writes reverse search result to the cache and if enabled to the cache file
sub FB_CALLMONITOR_writeToCache($$$)
{
    my ($hash, $number, $txt) = @_;
    my $name = $hash->{NAME};
    my $file = AttrVal($name, "reverse-search-cache-file", "");
    my $err;
    my @cachefile;
    my $phonebook_file;

    if(AttrVal($name, "reverse-search-cache", "0") eq "1")
    {
        $file =~ s/(^\s+|\s+$)//g;

        $hash->{helper}{CACHE}{$number} = $txt;

        if($file ne "")
        {
            FB_CALLMONITOR_Log $name, 4, "opening cache file $file for writing $number ($txt)";

            foreach my $key (keys %{$hash->{helper}{CACHE}})
            {
                push @cachefile, "$key|".$hash->{helper}{CACHE}{$key};
            }

            $err = FileWrite($file, @cachefile);

            if(defined($err) && $err)
            {
                FB_CALLMONITOR_Log $name, 2, "could not write cache file: $err";
            }
        }
    }
}

#######################################################################
# get and reads a FritzBox phonebook
sub FB_CALLMONITOR_readPhonebook($;$)
{
    my ($hash, $testPassword) = @_;

    my $name = $hash->{NAME};
    my ($err, $count_contacts, @lines, $phonebook, $pb_hash);

    delete($hash->{helper}{PHONEBOOK});
    delete($hash->{helper}{PHONEBOOKS});
    delete($hash->{helper}{IMAGE_URLS});

	if(AttrVal($name, "fritzbox-remote-phonebook", "0") eq "1")
    {
        if(AttrVal($name, "fritzbox-remote-phonebook-via", "tr064") eq "telnet")
        {
            ($err, $phonebook) = FB_CALLMONITOR_readRemotePhonebookViaTelnet($hash, $testPassword);

            if(defined($err))
            {
                FB_CALLMONITOR_Log $name, 2, "could not read remote FritzBox phonebook file - $err";
                return "Could not read remote FritzBox phonebook file - $err";
            }

            FB_CALLMONITOR_Log $name, 3, "found remote FritzBox phonebook via telnet";

            ($err, $count_contacts, $pb_hash) = FB_CALLMONITOR_parsePhonebook($hash, $phonebook);

            $hash->{helper}{PHONEBOOK} = $pb_hash;
            if(defined($err))
            {
                FB_CALLMONITOR_Log $name, 2, "could not parse remote phonebook - $err";
                return "Could not parse remote phonebook - $err";
            }
            else
            {
                FB_CALLMONITOR_Log $name, 3, "read $count_contacts contact".($count_contacts == 1 ? "" : "s")." from remote phonebook via telnet";
            }
        }
        elsif(AttrVal($name, "fritzbox-remote-phonebook-via", "tr064") =~ /^(web|tr064)$/)
        {
            my $do_with = $1;
            $err = FB_CALLMONITOR_identifyPhoneBooksViaWeb($hash, $testPassword) if($do_with eq "web");
            $err = FB_CALLMONITOR_identifyPhoneBooksViaTR064($hash, $testPassword) if($do_with eq "tr064");

            if(defined($err))
            {
                FB_CALLMONITOR_Log $name, 2, "could not identify remote phonebooks - $err";
                return "could not identify remote phonebooks - $err";
            }

            unless(exists($hash->{helper}{PHONEBOOK_NAMES}))
            {
                FB_CALLMONITOR_Log $name, 2, "no phonebooks could be found";
                return "no phonebooks could be found";
            }

            my %excludedIds = map { trim($_) => 1 } split(",",AttrVal($name, "fritzbox-remote-phonebook-exclude", ""));

            foreach my $phonebookId (sort keys %{$hash->{helper}{PHONEBOOK_NAMES}})
            {
                if(exists($excludedIds{$phonebookId}) or exists($excludedIds{$hash->{helper}{PHONEBOOK_NAMES}{$phonebookId}}))
                {
                    FB_CALLMONITOR_Log $name, 4, "skipping excluded phonebook id $phonebookId (".$hash->{helper}{PHONEBOOK_NAMES}{$phonebookId}.")";
                    next;
                }

                FB_CALLMONITOR_Log $name, 4, "requesting phonebook id $phonebookId (".$hash->{helper}{PHONEBOOK_NAMES}{$phonebookId}.")";

                ($err, $phonebook) = FB_CALLMONITOR_readRemotePhonebookViaWeb($hash, $phonebookId, $testPassword) if($do_with eq "web");
                ($err, $phonebook) = FB_CALLMONITOR_readRemotePhonebookViaTR064($hash, $phonebookId, $testPassword) if($do_with eq "tr064");

                if(defined($err))
                {
                    FB_CALLMONITOR_Log $name, 2, 'unable to retrieve phonebook "'.$hash->{helper}{PHONEBOOK_NAMES}{$phonebookId}.'" from FritzBox - '.$err;
                }
                else
                {
                    ($err, $count_contacts, $pb_hash) = FB_CALLMONITOR_parsePhonebook($hash, $phonebook);

                    $hash->{helper}{PHONEBOOKS}{$phonebookId} = $pb_hash;

                    if(defined($err))
                    {
                        FB_CALLMONITOR_Log $name, 2, "could not parse remote phonebook ".$hash->{helper}{PHONEBOOK_NAMES}{$phonebookId}." - $err";
                    }
                    else
                    {
                        FB_CALLMONITOR_Log $name, 3, "read $count_contacts contact".($count_contacts == 1 ? "" : "s").' from remote phonebook "'.$hash->{helper}{PHONEBOOK_NAMES}{$phonebookId}.'"';
                    }
                }
            }

            delete($hash->{helper}{PHONEBOOK_URL});

            FB_CALLMONITOR_downloadImageURLs($hash, $testPassword);
        }
    }
    else
    {
        FB_CALLMONITOR_Log $name, 4, "skipping remote phonebook";
    }

    if(-e "/usr/bin/ctlmgr_ctl" or ((not -e "/usr/bin/ctlmgr_ctl") and defined(AttrVal($name, "reverse-search-phonebook-file", undef))))
    {
		my $phonebook_file = AttrVal($name, "reverse-search-phonebook-file", "/var/flash/phonebook");

        ($err, @lines) = FileRead({FileName => $phonebook_file, ForceType => "file"});

        if(defined($err) && $err)
        {
            FB_CALLMONITOR_Log $name, 2, "could not read FritzBox phonebook file - $err";
            return "Could not read FritzBox phonebook file - $err";
        }

        $phonebook = join("", @lines);

        FB_CALLMONITOR_Log $name, 2, "found FritzBox phonebook $phonebook_file";

        ($err, $count_contacts, $pb_hash) = FB_CALLMONITOR_parsePhonebook($hash, $phonebook);

        if(defined($err))
        {
            FB_CALLMONITOR_Log $name, 2, "could not parse $phonebook_file  - $err";
            return "Could not parse $phonebook_file - $err";
        }
        else
        {
            $hash->{helper}{PHONEBOOK} = $pb_hash;
            FB_CALLMONITOR_Log $name, 2, "read $count_contacts contact".($count_contacts == 1 ? "" : "s")." from $phonebook_file";
        }
	}
    else
    {
        FB_CALLMONITOR_Log $name, 4, "skipping local phonebook file";
    }
}


#######################################################################
# reads the FritzBox phonebook file and parses the entries
sub FB_CALLMONITOR_parsePhonebook($$)
{
    my ($hash, $phonebook) = @_;
    my $name = $hash->{NAME};
    my $contact;
    my $contact_name;
    my $number;
    my $count_contacts = 0;

    my $out;

    if($phonebook =~ /<phonebook/ and $phonebook =~ m,</phonebook>,)
    {
        if($phonebook =~ /<contact/ and $phonebook =~ /<realName>/ and $phonebook =~ /<number/)
        {
            while($phonebook =~ m,<contact[^>]*>(.+?)</contact>,gcs)
            {
                $contact = $1;

                my $imageURL;

                if($contact =~ m,<imageURL>([^<>]+)</imageURL>,)
                {
                    $imageURL = $1;

                    $hash->{helper}{IMAGE_URLS}{$imageURL} = [] unless(exists($hash->{helper}{IMAGE_URLS}{$imageURL}));
                }

                if($contact =~ m,<realName>(.+?)</realName>,)
                {
                    $contact_name = $1;

                    while($contact =~ m,<number[^>]*?type="([^<>"]+?)"[^<>]*?>([^<>"]+?)</number>,gs)
                    {
                        if($1 ne "intern" and $1 ne "memo")
                        {
                            $number = FB_CALLMONITOR_normalizePhoneNumber($hash, $2);

                            $count_contacts++;
                            FB_CALLMONITOR_Log $name, 4, "found $contact_name with number $number";
                            $out->{$number} = FB_CALLMONITOR_html2txt($contact_name);

                            if($imageURL)
                            {
                                FB_CALLMONITOR_Log $name, 5, "found image for $contact_name with number $number";
                                push @{$hash->{helper}{IMAGE_URLS}{$imageURL}}, $number;
                            }

                            undef $number;
                        }
                    }
                    undef $contact_name;
                }


            }
        }

        return (undef, $count_contacts, $out);
    }
    else
    {
        return "this is not a FritzBox phonebook";
    }
}

#######################################################################
# loads the reverse search cache from file
sub FB_CALLMONITOR_loadCacheFile($;$)
{
    my ($hash, $file) = @_;

    my @cachefile;
    my @tmpline;
    my $count_contacts;
    my $name = $hash->{NAME};
    my $err;
    $file = AttrVal($hash->{NAME}, "reverse-search-cache-file", "") unless(defined($file));

    if($file ne "" and -r $file)
    {
        delete($hash->{helper}{CACHE});

        FB_CALLMONITOR_Log $hash->{NAME}, 3, "loading cache file $file";

        ($err, @cachefile) = FileRead($file);

        unless(defined($err) and $err)
        {
            foreach my $line (@cachefile)
            {
                if(not $line =~ /^\s*$/)
                {
                    chomp $line;
                    @tmpline = split("\\|", $line, 2);

                    if(@tmpline == 2)
                    {
                        $hash->{helper}{CACHE}{$tmpline[0]} = $tmpline[1];
                    }
                }
            }

            $count_contacts = scalar keys %{$hash->{helper}{CACHE}};
            FB_CALLMONITOR_Log $name, 3, "read ".($count_contacts > 0 ? $count_contacts : "no")." contact".($count_contacts == 1 ? "" : "s")." from Cache";
        }
        else
        {
            FB_CALLMONITOR_Log $name, 2, "could not open cache file: $err";
        }
    }
    else
    {
        FB_CALLMONITOR_Log $name, 2, "unable to access cache file: $file";
    }
}

#######################################################################
# loads the reverse search cache from file
sub FB_CALLMONITOR_loadTextFile($;$)
{
    my ($hash, $file) = @_;

    my @file;
    my @tmpline;
    my $count_contacts;
    my $name = $hash->{NAME};
    my $err;
    $file = AttrVal($hash->{NAME}, "reverse-search-text-file", "") unless(defined($file));

    if($file ne "" and -r $file)
    {
        delete($hash->{helper}{TEXTFILE});

        FB_CALLMONITOR_Log $hash->{NAME}, 3, "loading textfile $file";

        ($err, @file) = FileRead({FileName => $file, ForceType => "file"});

        unless(defined($err) and $err)
        {
            foreach my $line (@file)
            {
                $line =~ s/(,.*?)#.*$/$1/g;
                $line =~ s,//.*$,,g;

                if((not $line =~ /^\s*$/) and $line =~ /,/)
                {
                    chomp $line;
                    @tmpline = split(/,/, $line,2);
                    if(@tmpline == 2)
                    {
                        $hash->{helper}{TEXTFILE}{FB_CALLMONITOR_normalizePhoneNumber($hash, $tmpline[0])} = trim($tmpline[1]);
                    }
                }
            }

            $count_contacts = scalar keys %{$hash->{helper}{TEXTFILE}};
            FB_CALLMONITOR_Log $name, 3, "read ".($count_contacts > 0 ? $count_contacts : "no")." contact".($count_contacts == 1 ? "" : "s")." from textfile";
        }
        else
        {
            FB_CALLMONITOR_Log $name, 2, "could not open textfile: $err";
        }
    }
    else
    {
        @tmpline = ("###########################################################################################",
                    "# This file was created by FHEM and contains user defined reverse search entries          #",
                    "# Please insert your number entries in the following format:                              #",
                    "#                                                                                         #",
                    "#     <number>,<name>                                                                     #",
                    "#     <number>,<name>                                                                     #",
                    "#                                                                                         #",
                    "###########################################################################################",
                    "# e.g.",
                    "# 0123/456789,Mum",
                    "# +49 123 45 67 8,Dad",
                    "# 45678,Boss",
                    "####"
                    );
        $err = FileWrite({FileName => $file, ForceType => "file"},@tmpline);

        FB_CALLMONITOR_Log $name, 2, "unable to create textfile $file: $err" if(defined($err) and $err ne "");
    }
}

#######################################################################
# loads phonebook from extern FritzBox
sub FB_CALLMONITOR_readRemotePhonebookViaTelnet($;$)
{
    my ($hash, $testPassword) = @_;

    my $name = $hash->{NAME};

    my $rc = eval {
        require Net::Telnet;
        Net::Telnet->import();
        1;
    };

    unless($rc)
    {
        return "Error loading Net::Telnet. Maybe this module is not installed?";
    }

    my $phonebook_file = "/var/flash/phonebook";

    my ($fb_ip,undef) = split(/:/, ($hash->{DeviceName}), 2);

    $hash->{helper}{READ_PWD} = 1;

    my $fb_user = AttrVal($name, "fritzbox-user", undef);
    my $fb_pw = FB_CALLMONITOR_readPassword($hash, $testPassword);

    delete($hash->{helper}{READ_PWD});
    return "no password available to access FritzBox. Please set your FRITZ!Box password via 'set ".$hash->{NAME}." password <your password>'" unless(defined($fb_pw));

    my $telnet = Net::Telnet->new(Timeout => 10, Errmode => 'return');

    unless($telnet->open($fb_ip))
    {
        return "Error Connecting to FritzBox: ".$telnet->errmsg;
    }

    FB_CALLMONITOR_Log $name, 4, "connected to FritzBox via telnet";

    my ($prematch, $match) = $telnet->waitfor('/(?:login|user|password):\s*$/i');

    unless(defined($prematch) and defined($match))
    {
        $telnet->close;
        return "Couldn't recognize login prompt: ".$telnet->errmsg;
    }

    if($match =~ /(login|user):/i and defined($fb_user))
    {
        FB_CALLMONITOR_Log $name, 4, "setting user to FritzBox: $fb_user";
        $telnet->print($fb_user);

        unless($telnet->waitfor('/password:\s*$/i'))
        {
            $telnet->close;
            return "Error giving password to FritzBox: ".$telnet->errmsg;
        }

        FB_CALLMONITOR_Log $name, 4, "giving password to FritzBox";
        $telnet->print($fb_pw);
    }
    elsif($match =~ /(login|user):/i and not defined($fb_user))
    {
        $telnet->close;
        return "FritzBox needs a username to login via telnet. Please provide a valid username/password combination";
    }
    elsif($match =~ /password:/i)
    {
        FB_CALLMONITOR_Log $name, 4, "giving password to FritzBox";
        $telnet->print($fb_pw);
    }

    unless($telnet->waitfor('/#\s*$/'))
    {
        $telnet->close;
        my $err = $telnet->errmsg;
        $hash->{helper}{PWD_NEEDED} = 1;
        return "wrong password, please provide the right password" if($err =~ /\s*eof/i);
        return "Could'nt recognize shell prompt: $err";
    }

    FB_CALLMONITOR_Log $name, 4, "requesting $phonebook_file via telnet";

    my $command = "cat ".$phonebook_file;

    my @FBPhoneBook = $telnet->cmd($command);

    unless(@FBPhoneBook)
    {
        $telnet->close;
    	return "Error getting phonebook FritzBox: ".$telnet->errmsg;
    }
    else
    {
    	FB_CALLMONITOR_Log $name, 3, "Getting phonebook from FritzBox: $phonebook_file";
    }

    $telnet->print('exit');
    $telnet->close;

    delete($hash->{helper}{PWD_NEEDED});

    return (undef, join('', @FBPhoneBook));
}

#######################################################################
# performs a HTTP based request via TR-064 port with authentication
sub FB_CALLMONITOR_requestHTTPviaTR064($$$$;$$)
{
    my ($hash, $url, $data, $header, $auth, $testPassword) = @_;
    my $name = $hash->{NAME};

    my ($fb_ip,undef) = split(/:/, ($hash->{DeviceName}), 2);

    my ($fb_user, $fb_pw);
    my $param;
    my ($err, $response);

    if($auth)
    {
        $fb_user = AttrVal($name, "fritzbox-user", "admin");

        $hash->{helper}{READ_PWD} = 1;
        $fb_pw = FB_CALLMONITOR_readPassword($hash, $testPassword);
        delete($hash->{helper}{READ_PWD});

        unless(defined($fb_pw))
        {
            $hash->{helper}{PWD_NEEDED} = 1;
            return "no password available to access FritzBox. Please set your FRITZ!Box password via 'set ".$hash->{NAME}." password <your password>'";
        }
    }
    my $tr064_base_url = "http://".($auth ? urlEncode($fb_user).":".urlEncode($fb_pw)."\@" : "") ."$fb_ip:49000";

    $param->{noshutdown} = 1;
    $param->{timeout}    = AttrVal($name, "fritzbox-remote-timeout", 5);
    $param->{loglevel}   = 4;
    $param->{digest}     = 1;
    $param->{hideurl}    = 1;
    $param->{sslargs}    = { SSL_verify_mode => 0,  SSL_cipher_list => 'DEFAULT:!DH' }; # workaround for newer OpenSSL-Libraries who do not allow weak DH based ciphers (Forum: #80281)

    unless($hash->{helper}{TR064}{SECURITY_PORT})
    {
        my $get_security_port = '<?xml version="1.0" encoding="utf-8"?>'.
                                '<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'.
                                  '<s:Body>'.
                                   '<u:GetSecurityPort xmlns:u="urn:dslforum-org:service:DeviceInfo:1" />'.
                                  '</s:Body>'.
                                '</s:Envelope>';

        $param->{url}    = "$tr064_base_url/upnp/control/deviceinfo";
        $param->{header} = "SOAPACTION: urn:dslforum-org:service:DeviceInfo:1#GetSecurityPort\r\nContent-Type: text/xml; charset=utf-8";
        $param->{data}   = $get_security_port;

        FB_CALLMONITOR_Log $name, 4, "request SSL port for TR-064 access via method GetSecurityPort:\n$get_security_port";
        my ($err, $response)    = HttpUtils_BlockingGet($param);

        if($err ne "")
        {
            FB_CALLMONITOR_Log $name, 3, "error while requesting security port: $err";
            return "error while requesting phonebooks: $err";
        }

        if($response eq "" and exists($param->{code}))
        {
            FB_CALLMONITOR_Log $name, 3, "received http code ".$param->{code}." without any data after requesting security port via TR-064";
            return  "received no data after requesting security port via TR-064";
        }

        FB_CALLMONITOR_Log $name, 5, "received TR-064 method GetSecurityPort response:\n$response";

        if($response =~ /<NewSecurityPort>(\d+)<\/NewSecurityPort>/)
        {
            $tr064_base_url = "https://".($auth ? urlEncode($fb_user).":".urlEncode($fb_pw)."\@" : "")."$fb_ip:$1";
            $hash->{helper}{TR064}{SECURITY_PORT} = $1;
        }
    }
    else
    {
        $tr064_base_url = "https://".($auth ? urlEncode($fb_user).":".urlEncode($fb_pw)."\@" : "")."$fb_ip:".$hash->{helper}{TR064}{SECURITY_PORT};
    }

    $param->{url}    = "$tr064_base_url$url";
    $param->{header} = $header if($header);


    if($data)
    {
        $param->{data}   = $data if($data);
        FB_CALLMONITOR_Log $name, 4, "sending TR-064 request:\n$data";
    }
    else
    {
        FB_CALLMONITOR_Log $name, 4, "requesting TR-064 URL: $url";
    }

    ($err, $response) = HttpUtils_BlockingGet($param);

    if($err ne "")
    {
        if(exists($param->{code}) and $param->{code} eq "401")
        {
            $hash->{helper}{PWD_NEEDED} = 1;
            FB_CALLMONITOR_Log $name, 3, "unable to login via TR-064, wrong user/password";
            return "unable to login via TR-064, wrong user/password";
        }
        else
        {
            FB_CALLMONITOR_Log $name, 3, "error while requesting TR-064 URL $url: $err";
            return "error while requesting TR-064 URL $url: $err";
        }
    }

    if($response eq "" and exists($param->{code}))
    {
        FB_CALLMONITOR_Log $name, 3, "received http code ".$param->{code}." without any data after requesting TR-064 URL $url";
        return  "received no data after requesting TR-064 URL $url";
    }

    if($param->{httpheader} =~ m,^Content-Type:\s*text,mi)
    {
        FB_CALLMONITOR_Log $name, 5, "received TR-064 response for URL $url:\n$response";
    }
    else
    {
        FB_CALLMONITOR_Log $name, 5, "received TR-064 response for URL $url";
    }

    return (undef, $response, $param);

}

#######################################################################
# execute TR-064 methods via HTTP/SOAP request
sub FB_CALLMONITOR_requestTR064($$$$;$$)
{
    my ($hash, $path, $command, $type, $command_arg, $testPassword) = @_;

    my $name = $hash->{NAME};

       # �xecute the TR-064 request
    my $soap_request = '<?xml version="1.0" encoding="utf-8"?>'.
                       '<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" >'.
                         '<s:Body>'.
                           "<u:$command xmlns:u=\"$type\">".($command_arg ? $command_arg : "")."</u:$command>".
                         '</s:Body>'.
                       '</s:Envelope>';


    my $header = "SOAPACTION: $type#$command\r\nContent-Type: text/xml; charset=utf-8";

    return FB_CALLMONITOR_requestHTTPviaTR064($hash, $path, $soap_request, $header, 1,  $testPassword);
}

#####################################
# identifys the phonebooks defined on the FritzBox via TR064 interface (SOAP) and generate download url
sub FB_CALLMONITOR_identifyPhoneBooksViaTR064($;$)
{
    my ($hash, $testPassword) = @_;
    my $name = $hash->{NAME};

    my ($err, $data) = FB_CALLMONITOR_requestTR064($hash, "/upnp/control/x_contact", "GetPhonebookList", "urn:dslforum-org:service:X_AVM-DE_OnTel:1", undef, $testPassword);

    return "unable to identify phonebooks via TR-064: $err" if($err);

    my @phonebooks;

    # read list response (TR-064 id's: "0,1,2,...")
    if($data =~ m,<NewPhonebookList>(.+?)</NewPhonebookList>,si)
    {
        @phonebooks = split(",",$1);
        FB_CALLMONITOR_Log $name, 3, "found ".scalar @phonebooks." phonebooks";
    }
    else
    {
        FB_CALLMONITOR_Log $name, 3, "no phonebooks found";
        return  "no phonebooks could be found";
    }

    delete($hash->{helper}{PHONEBOOK_NAMES});
    delete($hash->{helper}{PHONEBOOK_URL});

    # request name and FritzBox phone id for each list item
    foreach (@phonebooks)
    {
        my $item_id = $_;

        my $phb_id;

        FB_CALLMONITOR_Log $name, 5, "requesting phonebook description for id $item_id";

        ($err, $data) = FB_CALLMONITOR_requestTR064($hash, "/upnp/control/x_contact", "GetPhonebook", "urn:dslforum-org:service:X_AVM-DE_OnTel:1", "<NewPhonebookID>$item_id</NewPhonebookID>", $testPassword);

        if ($err)
        {
            FB_CALLMONITOR_Log $name, 3, "error while requesting phonebook description for id $item_id: $err";
            return "error while requesting phonebook description for id $item_id: $err";
        }

        FB_CALLMONITOR_Log $name, 5, "received response with phonebook description for id $item_id:\n$data";

        if($data =~ m,<NewPhonebookName>(.+?)</NewPhonebookName>.*?<NewPhonebookURL>.*?pbid=(\d+)\D*?</NewPhonebookURL>,si)
        {
            $phb_id = $2;
            $hash->{helper}{PHONEBOOK_NAMES}{$phb_id} = $1;
            FB_CALLMONITOR_Log $name, 4, "found phonebook: $1 - $2";
        }

        if($data =~ m,<NewPhonebookURL>(.*?)</NewPhonebookURL>,i)
        {
            $hash->{helper}{PHONEBOOK_URL}{$phb_id} = $1;
            $hash->{helper}{PHONEBOOK_URL}{$phb_id} =~ s/&amp;/&/g;
            FB_CALLMONITOR_Log $name, 4, "found phonebook url for id $phb_id: ".$hash->{helper}{PHONEBOOK_URL}{$phb_id};
        }
    }

    FB_CALLMONITOR_Log $name, 4, "phonebooks found: ".join(", ", map { $hash->{helper}{PHONEBOOK_NAMES}{$_}." (id: $_)" } sort keys %{$hash->{helper}{PHONEBOOK_NAMES}}) if(exists($hash->{helper}{PHONEBOOK_NAMES}));

	# get deflections

    delete($hash->{helper}{DEFLECTIONS});

    FB_CALLMONITOR_Log $name, 5, "requesting deflection list";
    ($err, $data) = FB_CALLMONITOR_requestTR064($hash, "/upnp/control/x_contact", "GetDeflections", "urn:dslforum-org:service:X_AVM-DE_OnTel:1",undef, $testPassword);

    if ($err)
    {
        FB_CALLMONITOR_Log $name, 3, "error while requesting deflection list: $err";
        return "error while requesting deflection list: $err";
    }

    $data =~ s/&lt;/</g;
    $data =~ s/&gt;/>/g;

    # extract deflection list
    while($data =~ /<Item>(.*?)<\/Item>/gcs)
    {
        my $deflection_item = $1;
        my %values;

        while($deflection_item =~ m,<(?:\w+:)?(\w+)>([^<]+)</(?:\w+:)?(\w+)>,gcs)
        {
            $values{$1} = $2;
        }

        $hash->{helper}{DEFLECTIONS}{$values{DeflectionId}} = \%values;
    }

	FB_CALLMONITOR_Log $name, 3, "found ".(scalar keys %{$hash->{helper}{DEFLECTIONS}})." blocking rules (deflections)" if(exists($hash->{helper}{DEFLECTIONS}));

    delete($hash->{helper}{PWD_NEEDED});

    return undef;
}

#######################################################################
# loads internal and online phonebooks from extern FritzBox via web interface (http)
sub FB_CALLMONITOR_readRemotePhonebookViaTR064($$;$)
{
    my ($hash, $phonebookId, $testPassword) = @_;
    my $name = $hash->{NAME};

    my ($fb_ip,undef) = split(/:/, ($hash->{DeviceName}), 2);

    return "unknown phonebook id: $phonebookId" unless(exists($hash->{helper}{PHONEBOOK_NAMES}{$phonebookId}));
    return "unknown phonebook url:" unless(exists($hash->{helper}{PHONEBOOK_URL}{$phonebookId}));

    my $phb_url = $hash->{helper}{PHONEBOOK_URL}{$phonebookId};

    my $param;
    $param->{url}        = $phb_url;
    $param->{noshutdown} = 1;
    $param->{timeout}    = AttrVal($name, "fritzbox-remote-timeout", 5);
    $param->{loglevel}   = 4;

    FB_CALLMONITOR_Log $name, 4, "get export for phonebook: $phonebookId";

    my ($err, $phonebook) = HttpUtils_BlockingGet($param);

    FB_CALLMONITOR_Log $name, 5, "received http response code ".$param->{code} if(exists($param->{code}));

    if ($err ne "")
    {
        FB_CALLMONITOR_Log $name, 3, "got error while requesting phonebook: $err";
        return "got error while requesting phonebook: $err";
    }

    if($phonebook eq "" and exists($param->{code}))
    {
        FB_CALLMONITOR_Log $name, 3, "received http code ".$param->{code}." without any data";
        return  "received http code ".$param->{code}." without any data";
    }

    return (undef, $phonebook);
}

#######################################################################
# retrieves a session id to download files via TR-064 (phonebook contact images)
sub FB_CALLMONITOR_getSIDviaTR064($)
{


    my ($hash, $testPassword) = @_;
    my $name = $hash->{NAME};

    my ($err, $response) = FB_CALLMONITOR_requestTR064($hash, "/upnp/control/deviceconfig", "X_AVM-DE_CreateUrlSID", "urn:dslforum-org:service:DeviceConfig:1", undef, $testPassword);

    if($err)
    {
        FB_CALLMONITOR_Log $name, 3, "error while requesting session id via TR064: $err";
        return undef;
    }

    if($response =~ m,<NewX_AVM-DE_UrlSID>(.+?)</NewX_AVM-DE_UrlSID>,)
    {
        return $1;
    }

    return undef;
}

#######################################################################
# downloads all available image URL's via TR-064
sub FB_CALLMONITOR_downloadImageURLs($$)
{
    my ($hash, $testPassword) = @_;
    my $name = $hash->{NAME};

    if($hash->{helper}{IMAGE_URLS} and AttrVal($name,"contactImageViaTR064", "1") eq "1")
    {
        my $sid = FB_CALLMONITOR_getSIDviaTR064($hash);
        my $local_path = AttrVal($name,"contactImageDirectory", undef);

        return unless(defined($sid) and defined($local_path));

        if(! -d $local_path)
        {
            eval { use File::Path };
            if($@)
            {
                FB_CALLMONITOR_Log $name, 3, "unable to load File::Path perl module to create contact images directory '$local_path'. Please create it by yourself";
                return undef;
            }

            eval {File::Path::make_path($local_path) };
            if($@)
            {
                FB_CALLMONITOR_Log $name, 3, "unable to create contact images directory '$local_path': $@";
                return undef;
            }
        }

        foreach my $url (keys %{$hash->{helper}{IMAGE_URLS}})
        {
            my ($err, $file, $param) = FB_CALLMONITOR_requestHTTPviaTR064($hash, $url."&".$sid, undef, undef, 0,  $testPassword);

            if($err)
            {
                FB_CALLMONITOR_Log $name, 3, "error while requesting image URL $url via TR064: $err";
                next;
            }

            if($param->{httpheader} =~ /Content-Disposition: attachment; filename="[^"\s]+(\.\w+)"$/m)
            {
                my $suffix = $1;

                foreach my $number (@{$hash->{helper}{IMAGE_URLS}{$url}})
                {

                    my $filename = $local_path."/".$number.$suffix;
                    my $result = FileWrite({FileName => $local_path."/".$number.$suffix, ForceType=> "file", NoNL=> 1}, $file);

                    if($result)
                    {
                        FB_CALLMONITOR_Log $name, 3, "error while writing image $filename: $result";
                    }
                }
            }
        }

        FB_CALLMONITOR_Log $name, 2, "downloaded ".(scalar keys %{$hash->{helper}{IMAGE_URLS}})." contact images from all phonebooks";

    }
}

#######################################################################
# returns the filename of a corresponding contact image if exist.
sub FB_CALLMONITOR_getContactImage($$)
{

    my ($hash, $number) = @_;

    my $name = $hash->{NAME};

    my $local_path = AttrVal($name,"contactImageDirectory", undef);

    return undef unless(defined($local_path));

    $local_path =~ s,/+$,,;

    opendir(DIR, $local_path) or return undef;

    while (my $file = readdir(DIR)) {

        next if($file =~ /^\./);
        next if(-d "$local_path/$file");
        next unless($file =~ /^$number\./);

        return $file;
    }

    return AttrVal($name,"contactDefaultImage", "none");
}

#######################################################################
# identifys the phonebooks defined on the FritzBox via web interface (http)
sub FB_CALLMONITOR_identifyPhoneBooksViaWeb($;$)
{
    my ($hash, $testPassword) = @_;
    my $name = $hash->{NAME};

    my ($fb_ip,undef) = split(/:/, ($hash->{DeviceName}), 2);
    my $fb_user = AttrVal($name, "fritzbox-user", undef);
    my $fb_pw;
    my $fb_sid;

    $hash->{helper}{READ_PWD} = 1;
    $fb_pw = FB_CALLMONITOR_readPassword($hash, $testPassword);
    delete($hash->{helper}{READ_PWD});

    return "no password available to access FritzBox. Please set your FRITZ!Box password via 'set ".$hash->{NAME}." password <your password>'" unless(defined($fb_pw));

    $fb_sid = FB_doCheckPW($fb_ip, $fb_user, $fb_pw);

    unless(defined($fb_sid))
    {
        $hash->{helper}{PWD_NEEDED} = 1;
        return "unable to login via webinterface, maybe wrong user/password?"
    }

    FB_CALLMONITOR_Log $name, 4, "identifying available phonebooks";

    my $param;
    $param->{url}        = "http://$fb_ip/fon_num/fonbook_select.lua?sid=$fb_sid";
    $param->{noshutdown} = 1;
    $param->{timeout}    = AttrVal($name, "fritzbox-remote-timeout", 5);
    $param->{loglevel}   = 4;

    my ($err, $data)    = HttpUtils_BlockingGet($param);

    if ($err ne "")
    {
        FB_CALLMONITOR_Log $name, 3, "error while requesting phonebooks: $err";
        return "error while requesting phonebooks: $err";
    }

    if($data eq "" and exists($param->{code}))
    {
        FB_CALLMONITOR_Log $name, 3, "received http code ".$param->{code}." without any data after requesting available phonebooks";
        return  "received no data after requesting available phonebooks";
    }

    FB_CALLMONITOR_Log $name, 4, "phonebooks successfully identified";

    if($data =~ m,<form[^>]*name="mainform"[^>]*>(.+?)</form>,s)
    {
        $data = $1;
    }

    delete($hash->{helper}{PHONEBOOK_NAMES});

    while($data =~ m,<label[^>]*for="uiBookid:(\d+)"[^>]*>\s*(.+?)\s*</label>,gcs)
    {
        $hash->{helper}{PHONEBOOK_NAMES}{$1} = $2;
        FB_CALLMONITOR_Log $name, 4, "found phonebook: $2";
    }

    FB_CALLMONITOR_Log $name, 3, "phonebooks found: ".join(", ", map { $hash->{helper}{PHONEBOOK_NAMES}{$_}." (id: $_)" } sort keys %{$hash->{helper}{PHONEBOOK_NAMES}}) if(exists($hash->{helper}{PHONEBOOK_NAMES}));

    delete($hash->{helper}{PWD_NEEDED});

    return undef;
}

#######################################################################
# loads internal and online phonebooks from extern FritzBox via web interface (http)
sub FB_CALLMONITOR_readRemotePhonebookViaWeb($$;$)
{
    my ($hash, $phonebookId, $testPassword) = @_;
    my $name = $hash->{NAME};

    my ($fb_ip,undef) = split(/:/, ($hash->{DeviceName}), 2);
    my $fb_user = AttrVal($name, "fritzbox-user", '');
    my $fb_pw;
    my $fb_sid;

    return "unknown phonebook id: $phonebookId" unless(exists($hash->{helper}{PHONEBOOK_NAMES}{$phonebookId}));

    $hash->{helper}{READ_PWD} = 1;

    $fb_pw = FB_CALLMONITOR_readPassword($hash, $testPassword);
    delete($hash->{helper}{READ_PWD});

    return "no password available to access FritzBox. Please set your FRITZ!Box password via 'set ".$hash->{NAME}." password <your password>'" unless(defined($fb_pw));

    $fb_sid = FB_doCheckPW($fb_ip, $fb_user, $fb_pw);

    unless(defined($fb_sid))
    {
        $hash->{helper}{PWD_NEEDED} = 1;
        return "no session id available to access FritzBox. Maybe wrong user/password?"
    }

    my $param;
    $param->{url}        = "http://$fb_ip/cgi-bin/firmwarecfg";
    $param->{noshutdown} = 1;
    $param->{timeout}    = AttrVal($name, "fritzbox-remote-timeout", 5);
    $param->{loglevel}   = 4;
    $param->{method}     = "POST";
    $param->{header}     = "Content-Type: multipart/form-data; boundary=boundary";

    $param->{data} = "--boundary\r\n".
                     "Content-Disposition: form-data; name=\"sid\"\r\n".
                     "\r\n".
                     "$fb_sid\r\n".
                     "--boundary\r\n".
                     "Content-Disposition: form-data; name=\"PhonebookId\"\r\n".
                     "\r\n".
                     "$phonebookId\r\n".
                     "--boundary\r\n".
                     "Content-Disposition: form-data; name=\"PhonebookExportName\"\r\n".
                     "\r\n".
                     $hash->{helper}{PHONEBOOK_NAMES}{$phonebookId}."\r\n".
                     "--boundary\r\n".
                     "Content-Disposition: form-data; name=\"PhonebookExport\"\r\n".
                     "\r\n".
                     "\r\n".
                     "--boundary--";

    FB_CALLMONITOR_Log $name, 4, "get export for phonebook: $phonebookId";

    my ($err, $phonebook) = HttpUtils_BlockingGet($param);

    FB_CALLMONITOR_Log $name, 5, "received http response code ".$param->{code} if(exists($param->{code}));

    if ($err ne "")
    {
        FB_CALLMONITOR_Log $name, 3, "got error while requesting phonebook: $err";
        return "got error while requesting phonebook: $err";
    }

    if($phonebook eq "" and exists($param->{code}))
    {
        FB_CALLMONITOR_Log $name, 3, "received http code ".$param->{code}." without any data";
        return  "received http code ".$param->{code}." without any data";
    }

    delete($hash->{helper}{PWD_NEEDED});

    return (undef, $phonebook);
}

#######################################################################
# checks and store FritzBox password used for telnet connection
sub FB_CALLMONITOR_storePassword($$)
{
    my ($hash, $password) = @_;

    my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
    my $key = getUniqueId().$index;

    my (undef, $enc_pwd) = FB_CALLMONITOR_encrypt($password, $key);

    my $err = FB_CALLMONITOR_readPhonebook($hash, $enc_pwd);

    return "unable to check password - $err" if(defined($err));

    $err = setKeyValue($index, $enc_pwd);

    return "error while saving the password - $err" if(defined($err));

    return "password successfully saved";
}

#######################################################################
# reads the FritzBox password
sub FB_CALLMONITOR_readPassword($;$)
{
    my ($hash, $testPassword) = @_;
    my $name = $hash->{NAME};

   my $xline       = ( caller(0) )[2];
   my $xsubroutine = ( caller(1) )[3];
   my $sub         = ( split( ':', $xsubroutine ) )[2];
   $sub =~ s/FB_CALLMONITOR_//       if ( defined $sub );
   $sub ||= 'no-subroutine-specified';

   if ($sub !~ /readRemotePhonebookViaTelnet|requestHTTPviaTR064|identifyPhoneBooksViaWeb|readRemotePhonebookViaWeb/) {
     FB_CALLMONITOR_Log $hash, 2, "EMERGENCY: unauthorized call for reading password from: $sub";
     return undef;
   }

    my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
    my $key = getUniqueId().$index;

    my ($password, $err);

    if(defined($testPassword))
    {
        $password = $testPassword;
    }
    else
    {
        ($err, $password) = getKeyValue($index);

        if(defined($err))
        {
           $hash->{helper}{PWD_NEEDED} = 1;
           FB_CALLMONITOR_Log $name, 4, "unable to read FritzBox password from file: $err";
           return undef;
        }
    }

    if(defined($password))
    {
        my (undef, $dec_pwd) = FB_CALLMONITOR_decrypt($password, $key);

        return $dec_pwd if($hash->{helper}{READ_PWD});
    }
    else
    {
        $hash->{helper}{PWD_NEEDED} = 1;

        return undef;
    }
}

#######################################################################
# normalizes a formated phone number
sub FB_CALLMONITOR_normalizePhoneNumber($$)
{
    my ($hash, $number) = @_;
    my $name = $hash->{NAME};

    my $area_code = AttrVal($name, "local-area-code", "");
    my $country_code = AttrVal($name, "country-code", "0049");

    $number =~ s/\s//g;                         # Remove spaces
    $number =~ s/^(\#[0-9]{1,10}\#)//g;         # Remove phone control codes
    $number =~ s/^\+/00/g;                      # Convert leading + to 00 country extension
    $number =~ s/[^\d\*#]//g if(not $number =~ /@/);  # Remove anything else isn't a number if it is no VoIP number
    $number =~ s/^$country_code/0/g;            # Replace own country code with leading 0

    if($number =~ /^\d/ and $number !~ /^0/ and $number !~ /^11/ and $number !~ /@/ and $area_code =~ /^0[1-9]\d+$/)
    {
       $number = $area_code.$number;
    }

    return $number;
}

#######################################################################
# decrypt an encrypted password
sub FB_CALLMONITOR_decrypt($$)
{
    my ($password, $key) = @_;

    return undef unless(defined($password));

    if(eval "use Digest::MD5;1")
    {
        $key = Digest::MD5::md5_hex(unpack "H*", $key);
        $key .= Digest::MD5::md5_hex($key);
    }

    my $dec_pwd = '';

    for my $char (map { pack('C', hex($_)) } ($password =~ /(..)/g))
    {
        my $decode=chop($key);
        $dec_pwd.=chr(ord($char)^ord($decode));
        $key=$decode.$key;
    }

    return (undef, $dec_pwd);
}

#######################################################################
# encrypts a password
sub FB_CALLMONITOR_encrypt($$)
{
    my ($password, $key) = @_;

    return undef unless(defined($password));

    if(eval "use Digest::MD5;1")
    {
        $key = Digest::MD5::md5_hex(unpack "H*", $key);
        $key .= Digest::MD5::md5_hex($key);
    }

    my $enc_pwd = '';

    for my $char (split //, $password)
    {
        my $encode=chop($key);
        $enc_pwd.=sprintf("%.2x",ord($char)^ord($encode));
        $key=$encode.$key;
    }

    return (undef, $enc_pwd);
}

#######################################################################
sub FB_CALLMONITOR_checkNumberForDeflection($$)
{
    my ($hash, $number) = @_;
    my $name = $hash->{NAME};

    my $ret = 0;

    if(exists($hash->{helper}{DEFLECTIONS}) and AttrVal($name,"check-deflections",0))
    {
        my $deflection_count = scalar keys %{$hash->{helper}{DEFLECTIONS}};

        FB_CALLMONITOR_Log $name, 4, "check ".(defined($number) ? $number : "unknown number")." against deflection rules (".$deflection_count." rule".($deflection_count ==1 ? "" : "s").")";

        foreach my $item (values %{$hash->{helper}{DEFLECTIONS}})
        {
            next unless($item->{Enable}); # next if rule not enabled
            next if(!$item->{Type});

            if($item->{Type} eq "fromNumber" and $item->{Number} and $number)
            {
                my $tmp = $item->{Number};
                $ret = 1 if($number =~ /^0?$tmp/);
            }
            elsif($item->{Type} eq "fromPB" and $item->{PhonebookID} and $number)
            {
                $ret = 1 if(exists($hash->{helper}{PHONEBOOKS}) and exists($hash->{helper}{PHONEBOOKS}{$item->{PhonebookID}}) and exists($hash->{helper}{PHONEBOOKS}{$item->{PhonebookID}}{$number}));
            }
            elsif($item->{Type} eq "fromAnonymous")
            {
                $ret = 1 unless(defined($number));
            }
        }
    }

    FB_CALLMONITOR_Log $name, 4, "found matching deflection. call will be ignored" if($ret);
    return $ret;
}

#######################################################################
sub FB_CALLMONITOR_checkNumberIsFiltered($$)
{
    my ($hash, $number) = @_;
    my $name = $hash->{NAME};

    if(exists($hash->{helper}{INTERNAL_FILTER}) and not exists($hash->{helper}{INTERNAL_FILTER}{$number}))
    {
        return 1;
    }

    return 0;
}

#######################################################################
sub FB_CALLMONITOR_sendKeepAlive($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $sendKeepAlives = AttrVal($name, "sendKeepAlives", "none");
    my $values = {
                    "5m" => 300,
                    "10m" => 600,
                    "15m" => 900,
                    "30m" => 1800,
                    "1h" => 3600
                 };

    if($sendKeepAlives ne "none" and DevIo_IsOpen($hash))
    {
        FB_CALLMONITOR_Log $name, 5, "sending keep-alive";
        DevIo_SimpleWrite($hash, "\n", 2);

        if($values->{$sendKeepAlives})
        {
            InternalTimer(gettimeofday()+$values->{$sendKeepAlives}, "FB_CALLMONITOR_sendKeepAlive", $hash);
        }
        else
        {
            FB_CALLMONITOR_Log $name, 3, "unsupported value for attribute sendKeepAlives: $sendKeepAlives. discard sending keep-alive";
        }
    }
    else
    {
        RemoveInternalTimer($hash, "FB_CALLMONITOR_sendKeepAlive");
    }

    return undef;
}

1;

=pod
=item helper
=item summary    provides realtime telephone events of a AVM FRITZ!Box via LAN connection
=item summary_DE stellt Telefonereignisse einer AVM FRITZ!Box via LAN zur Verf&uuml;gung
=begin html

<div>
<a name="FB_CALLMONITOR"></a>
<h3>FB_CALLMONITOR</h3>
<ul>
  The FB_CALLMONITOR module connects to a AVM FritzBox Fon and listens for telephone
  <a href="#FB_CALLMONITOR_events">events</a> (Receiving incoming call, Making a call)
  <br><br>
  In order to use this module with fhem you <b>must</b> enable the Callmonitor feature via
  telephone shortcode.<br><br>
  <ul>
      <code>#96*5* - for activating<br>#96*4* - for deactivating</code>
  </ul>

  <br>
  Just dial the shortcode for activating on one of your phones, after 3 seconds just hang up. The feature is now activated.
  <br><br>
  After activating the Callmonitor-Support in your FritzBox, this module is able to
  generate an event for each external call. Internal calls were not be detected by the Callmonitor.
  <br><br>
  This module work with any FritzBox Fon model.
  <br><br>

  <a name="FB_CALLMONITORdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FB_CALLMONITOR &lt;ip-address&gt;[:port]</code><br>
    <br>
    port is 1012 by default.
    <br>
  </ul>
  <br>

  <a name="FB_CALLMONITORset"></a>
  <b>Set</b>
  <ul>
    <li><a name="reopen"></a>
      <dt><code>set &lt;name&gt; reopen</code></dt>
      close and reopen the connection
    </li>
    <li><a name="rereadCache"></a>
      <dt><code>set &lt;name&gt; rereadCache</code></dt>
      Reloads the cache file if configured (see attribute: <a href="#FB_CALLMONITOR_reverse-search-cache-file">reverse-search-cache-file</a>)
    </li>
    <li><a name="rereadPhonebook"></a>
      <dt><code>set &lt;name&gt; rereadPhonebook</code></dt>
      Reloads the FritzBox phonebook (from given file, via telnet or directly if available)
    </li>
    <li><a name="rereadTextfile"></a>
      <dt><code>set &lt;name&gt; rereadTextfile</code></dt>
      Reloads the user given textfile if configured (see attribute: <a href="#FB_CALLMONITOR_reverse-search-text-file">reverse-search-text-file</a>)
    </li>
    <li><a name="password"></a>
      <dt><code>set &lt;name&gt; password &lt;password&gt;</code></dt>
      set the FritzBox password (only available when password is really needed for network access to FritzBox phonebook, see attribute <a href="#FB_CALLMONITOR_fritzbox-remote-phonebook">fritzbox-remote-phonebook</a>)
    </li>
  </ul>
  <br>

  <a name="FB_CALLMONITORget"></a>
  <b>Get</b>
  <ul>
    <li><a name="search"></a>
      <dt><code>get &lt;name&gt; search &lt;phone-number&gt;</code></dt>
      returns the name of the given number via reverse-search (internal phonebook, cache or internet lookup)
    </li>
    <li><a name="showPhonebookIds"></a>
      <dt><code>get &lt;name&gt; showPhonebookIds</code></dt>
      returns a list of all available phonebooks on the FritzBox (not available when using telnet to retrieve remote phonebook)
    </li>
    <li><a name="showPhonebookEntries"></a>
      <dt><code>get &lt;name&gt; [phonebook-id]</code></dt>
      returns a list of all currently known phonebook entries, or just for a spefific phonebook id (only available when using phonebook funktionality)
    </li>
    <li><a name="showCacheEntries"></a>
      <dt><code>get &lt;name&gt; showCacheEntries</code></dt>
      returns a list of all currently known cache entries (only available when using reverse search caching funktionality)
    </li>
    <li><a name="showTextfileEntries"></a>
      <dt><code>get &lt;name&gt; showTextfileEntries</code></dt>
      returns a list of all known entries from user given textfile (only available when using reverse search caching funktionality)
    </li>
  </ul>
  <br>

  <a name="FB_CALLMONITORattr"></a>
  <b>Attributes</b><br><br>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>

    <li><a href="#readingFnAttributes">readingFnAttributes</a> 0,1</li><br>

    <li><a name="disable">disable</a> 0,1</li>
	Optional attribute to disable the Callmonitor. When disabled, no phone events can be detected.
	<br><br>
	Possible values: 0 =&gt; Callmonitor is activated, 1 =&gt; Callmonitor is deactivated.<br>
    Default Value is 0 (activated)<br><br>

    <li><a name="disabledForIntervals">disabledForIntervals</a> HH:MM-HH:MM HH:MM-HH-MM...</li>
    Optional attribute to disable FB_CALLMONITOR during specific time intervals. The attribute contains a space separated list of HH:MM tupels.
    If the current time is between any of these time specifications, no phone events will be processed.
    Instead of HH:MM you can also specify HH or HH:MM:SS.
    <br><br>To specify an interval spawning midnight, you have to specify two intervals, e.g.:
    <pre>23:00-24:00 00:00-01:00</pre>
    Default Value is <i>empty</i> (no intervals defined, FB_CALLMONITOR is always active)<br><br>

    <li><a name="answMachine-is-missed-call">answMachine-is-missed-call</a> 0,1</li>
    If activated, a incoming call, which is answered by an answering machine, will be treated as missed call (see <a href="#events">Generated Events</a>).
    <br><br>
    Possible values: 0 =&gt; disabled, 1 =&gt; enabled (answering machine calls will be treated as "missed call").<br>
    Default Value is 0 (disabled)<br><br>

    <li><a name="internal-number-filter">internal-number-filter</a> &lt;number&gt;[,&lt;number&gt;,...]</li>
    If set, only calls for the configured internal number (according to reading "internal_number") will be processed.
    Valid values are one particular internal number or a comma separated list of multiple internal numbers.
    Calls internal numbers, which are not listed here, will be ignored and not processed.
    If this attribute is not set, all calls will be processed (no filtering).
    <br><br>per default, internal number filtering is disabled.<br><br>

    <li><a name="reverse-search">reverse-search</a> (phonebook,textfile,tellows.de,dasoertliche.de,11880.com,search.ch,dasschnelle.at,herold.at)</li>
    Enables the reverse searching of the external number (at dial and call receiving).
    This attribute contains a comma separated list of providers which should be used to reverse search a name to a specific phone number.
    The reverse search process will try to lookup the name according to the order of providers given in this attribute (from left to right). The first valid result from the given provider order will be used as reverse search result.
    <br><br>per default, reverse search is disabled.<br><br>

    <li><a name="reverse-search-cache">reverse-search-cache</a> 0,1</li>
    If this attribute is activated each reverse-search result from an internet provider is saved in an internal cache
    and will be used instead of requesting each internet provider every time with the same number. The cache only contains reverse-search results from internet providers.<br><br>
    Possible values: 0 =&gt; off , 1 =&gt; on<br>
    Default Value is 0 (off)<br><br>

    <li><a name="reverse-search-cache-file">reverse-search-cache-file</a> &lt;file&gt;</li>
    Write the internal reverse-search-cache to the given file and use it next time FHEM starts.
    So all reverse search results are persistent written to disk and will be used instantly after FHEM starts.<br><br>

    <li><a name="reverse-search-text-file">reverse-search-text-file</a> &lt;file&gt;</li>
    Define a custom list of numbers and their according names in a textfile. This file uses comma separated values per line in form of:
    <pre>
    &lt;number1&gt;,&lt;name1&gt;
    &lt;number2&gt;,&lt;name2&gt;
    ...
    &lt;numberN&gt;,&lt;nameN&gt;
    </pre>
    You can use the hash sign to comment entries in this file. If the specified file does not exists, it will be created by FHEM.
    <br><br>

    <li><a name="reverse-search-phonebook-file">reverse-search-phonebook-file</a> &lt;file&gt;</li>
    This attribute can be used to specify the (full) path to a phonebook file in FritzBox format (XML structure). Using this option it is possible to use the phonebook of a FritzBox even without FHEM running on a Fritzbox.
    The phonebook file can be obtained by an export via FritzBox web UI<br><br>
    Default value is /var/flash/phonebook (phonebook filepath on FritzBox)<br><br>

    <li><a name="reverse-search-tellows-api-key">reverse-search-tellows-api-key</a> &lt;api-key&gt</li>
    tellows api-key. For test cases you can use the api-key -test123- <br><br>

    <li><a name="reverse-search-tellows-api-partner">reverse-search-tellows-api-partner</a> &lt;api-partner&gt</li>
    tellows api-partner. For test cases you can use the api-partner -test-<br><br>

    <li><a name="remove-leading-zero">remove-leading-zero</a> 0,1</li>
    If this attribute is activated, a leading zero will be removed from the external number (e.g. in telefon systems).<br><br>
    Possible values: 0 =&gt; off , 1 =&gt; on<br>
    Default Value is 0 (off)<br><br>

    <li><a name="unique-call-ids">unique-call-ids</a> 0,1</li>
    If this attribute is activated, each call will use a biunique call id. So each call can be separated from previous calls in the past.<br><br>
    Possible values: 0 =&gt; off , 1 =&gt; on<br>
    Default Value is 0 (off)<br><br>

    <li><a name="local-area-code">local-area-code</a> &lt;number&gt;</li>
    Use the given local area code for reverse search in case of a local call (e.g. 0228 for Bonn, Germany)<br><br>

    <li><a name="country-code">country-code</a> &lt;number&gt;</li>
    Your local country code. This is needed to identify phonenumbers in your phonebook with your local country code as a national phone number instead of an international one as well as handling Call-By-Call numbers in german speaking countries (e.g. 0049 for Germany, 0043 for Austria or 001 for USA)<br><br>
    Default Value is 0049 (Germany)<br><br>

    <li><a name="check-deflection">check-deflections</a> 0,1</li>
    If this attribute is activated, each incoming call is checked against the configured blocking rules (deflections) of the FritzBox. If an incoming call matches any of these rules, the call will be blocked and no reading/revent will be created for this call. This is only possible, if the phonebook is obtained via TR-064 from the FritzBox (see attributes <a href="#fritzbox-remote-phonebook">fritzbox-remote-phonebook</a> and <a href="#fritzbox-remote-phonebook-via">fritzbox-remote-phonebook-via</a><br><br>
    Possible values: 0 =&gt; off , 1 =&gt; on<br>
    Default Value is 0 (off)<br><br>

    <li><a name="fritzbox-remote-phonebook">fritzbox-remote-phonebook</a> 0,1</li>
    If this attribute is activated, the phonebook should be obtained direct from the FritzBox via remote network connection (in case FHEM is not running on a FritzBox). This is only possible if a password (and depending on configuration a username as well) is configured.<br><br>
    Possible values: 0 =&gt; off , 1 =&gt; on (use remote connection to obtain FritzBox phonebook)<br>
    Default Value is 0 (off)<br><br>

    <li><a name="fritzbox-remote-phonebook-via">fritzbox-remote-phonebook-via</a> tr064,web,telnet</li>
    Set the method how the phonebook should be requested via network. When set to "web", the phonebook is obtained from the web interface via HTTP. When set to "telnet", it uses a telnet connection to login and retrieve the phonebook (telnet must be activated via dial shortcode #96*7*). When set to "tr064" the phonebook is obtained via TR-064 SOAP request.<br><br>
    Possible values: tr064,web,telnet<br>
    Default Value is tr064 (retrieve phonebooks via TR-064 interface)<br><br>

    <li><a name="fritzbox-remote-phonebook-exclude">fritzbox-remote-phonebook-exclude</a> &lt;list&gt;</li>
    A comma separated list of phonebook id's or names which should be excluded when retrieving all possible phonebooks via web or tr064 method (see attribute <a href="#fritzbox-remote-phonebook-via">fritzbox-remote-phonebook-via</a>). All list possible values is provided by <a href="#get">get command</a> <i>showPhonebookIds</i>. This attribute is not applicable when using telnet method to obtain remote phonebook.<br><br>
    Default Value: <i>empty</i> (all phonebooks should be used, no exclusions)<br><br>

    <li><a name="fritzbox-user">fritzbox-user</a> &lt;username&gt;</li>
    Use the given username to obtain the phonebook via network connection (see <a href="#fritzbox-remote-phonebook">fritzbox-remote-phonebook</a>). This attribute is only needed, if you use multiple users on your FritzBox.<br><br>

    <li><a name="apiKeySearchCh">apiKeySearchCh</a> &lt;API-Key&gt;</li>
    A private API key from <a href="https://tel.search.ch/api/getkey" target="_new">tel.search.ch</a> to perform a reverse search via search.ch (see attribute <a href=#reverse-search">reverse-search</a>). Without an API key, no reverse search via search.ch is not possible<br><br>

    <li><a name="sendKeepAlives">sendKeepAlives</a> (none,5m,10m,15m,30m,1h)</li>
    If activated, FB_CALLMONITOR sends a keep-alive on a regularly basis depending on the configured value. This ensures a working connection when the connected FritzBox is operating behind another NAT-based router (e.g. another FritzBox) so the connection will not be detected as "dead" and therefore blocked.<br><br>
    Possible values: none,5m,10m,15m,30m,1h<br>
    Default value: none (no keep-alives will be sent)<br><br>

    <li><a name="contactImageDirectory">contactImageDirectory</a> &lt;directory&gt;</li>
    If set, FB_CALLMONITOR generates the reading "contact_image" if a file with the external number as filename is found in this directory (e.g. "0123456567.jpg").
    If no matching file exist in this directory or the external number is unknown, the reading "contact_image" is set to "none" (can be override by attribute <a href="#contactDefaultImage">contactDefaultImage</a>).
    <br><br>

    <li><a name="contactDefaultImage">contactDefaultImage</a> &lt;filename&gt;</li>
    If set, FB_CALLMONITOR uses the given filename instead of "none" in case no image exists in the configured contact image directory or the external number is unknown.
    <br><br>

    <li><a name="contactImageViaTR064">contactImageViaTR064</a> 0,1</li>
    If this attribute is activated, FB_CALLMONITOR will download all available contact images from the FritzBox phonebook(s) via TR-064 (if attribute <a href="#fritzbox-remote-phonebook-via">fritzbox-remote-phonebook-via</a> is set to <code>tr064</code>) and will store them in the directory configured by attribute <a href="#contactImageDirectory">contactImageDirectory</a>.
    The downloaded images will then be used as contact images for the reading "contact_image".
    <br><br>
    Possible values: 0 =&gt; off , 1 =&gt; on<br>
    Default value is 1 (contact images will be downloaded via TR-064 from FritzBox)
 </ul>
  <br>
  <br>
  <a name="FB_CALLMONITORevents"></a>
  <b>Generated Events:</b><br><br>
  <ul>
  <li><b>event</b> (call|ring|connect|disconnect) - which event in detail was triggerd</li>
  <li><b>direction</b> (incoming|outgoing) - the call direction in general (incoming or outgoing call)</li>
  <li><b>external_number</b> - The participants number which is calling (event: ring) or beeing called (event: call)</li>
  <li><b>external_name</b> - The result of the reverse lookup of the external_number via internet. Is only available if reverse-search is activated. Special values are "unknown" (no search results found) and "timeout" (got timeout while search request). In case of an timeout and activated caching, the number will be searched again next time a call occurs with the same number</li>
  <li><b>internal_number</b> - The internal number (fixed line, VoIP number, ...) on which the participant is calling (event: ring) or is used for calling (event: call)</li>
  <li><b>internal_connection</b> - The internal connection (FON1, FON2, ISDN, DECT, ...) which is used to take or perform the call</li>
  <li><b>external_connection</b> - The external connection ("POTS" =&gt; fixed line, "SIPx" =&gt; VoIP account, "ISDN", "GSM" =&gt; mobile call via GSM/UMTS stick) which is used to take or perform the call</li>
  <li><b>calls_count</b> - The number of active calls in parallel. The value 0 means, there is no active call currently.</li>
  <li><b>call_duration</b> - The call duration in seconds. Is only generated at a disconnect event. The value 0 means, the call was not taken by anybody.</li>
  <li><b>call_id</b> - The call identification number to separate events of two or more different calls at the same time. This id number is equal for all events relating to one specific call.</li>
  <li><b>missed_call</b> - This event will be raised in case of a incoming call, which is not answered. If available, also the name of the calling number will be displayed.</li>
  <li><b>contact_image</b> - This event will be raised if attribute <a href="#contactImageDirectory">contactImageDirectory</a> is configured. It contains the filename of the corresponding contact image filename or "none" if no file exist or external number is unknown.</li>
  </ul>
</ul>
</div>
=end html

=begin html_DE

<div>
<a name="FB_CALLMONITOR"></a>
<h3>FB_CALLMONITOR</h3>
<ul>
  Das Modul FB_CALLMONITOR verbindet sich zu einer AVM FritzBox Fon und verarbeitet
  Telefonie-<a href="#events">Ereignisse</a>.(eingehende &amp; ausgehende Telefonate)
  <br><br>
  Um dieses Modul nutzen zu k&ouml;nnen, muss der Callmonitor via Kurzwahl mit einem Telefon aktiviert werden.
  <br><br>
  <ul>
      <code>#96*5* - Callmonitor aktivieren<br>#96*4* - Callmonitor deaktivieren</code>
  </ul>
  <br>
  Einfach die entsprechende Kurzwahl auf irgend einem Telefon eingeben, welches an die Fritz!Box angeschlossen ist.
  Nach ca. 3 Sekunden kann man einfach wieder auflegen. Nun ist der Callmonitor aktiviert.
  <br><br>
  Sobald der Callmonitor auf der Fritz!Box aktiviert wurde erzeugt das Modul entsprechende Events (s.u.) f&uuml;r alle externen Anrufe. Interne Anrufe werden nicht durch den Callmonitor erfasst.
  <br><br>
  Dieses Modul funktioniert mit allen Fritz!Box Modellen, welche Telefonie unterst&uuml;tzen (Namenszusatz: Fon).
  <br><br>

  <a name="FB_CALLMONITORdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FB_CALLMONITOR &lt;IP-Addresse&gt;[:Port]</code><br>
    <br>
    Port 1012 ist der Standardport und muss daher nicht explizit angegeben werden.
    <br>
  </ul>
  <br>

  <a name="FB_CALLMONITORset"></a>
  <b>Set</b>
  <ul>
    <li><a name="reopen"></a>
      <dt><code>set &lt;name&gt; reopen</code></dt>
      schliesst die Verbindung zur FritzBox und &ouml;ffnet sie erneut
    </li>
    <li><a name="rereadCache"></a>
      <dt><code>set &lt;name&gt; rereadCache</code></dt>
      Liest den Cache aus der Datei neu ein (sofern konfiguriert, siehe dazu Attribut <a href="#reverse-search-cache-file">reverse-search-cache-file</a>)
    </li>
    <li><a name="rereadPhonebook"></a>
      <dt><code>set &lt;name&gt; rereadPhonebook</code></dt>
      Liest das Telefonbuch der FritzBox neu ein (per Datei, Telnet oder direkt lokal)
    </li>
    <li><a name="rereadTextfile"></a>
      <dt><code>set &lt;name&gt; rereadTextfile</code></dt>
      Liest die nutzereigene Textdatei neu ein (sofern konfiguriert, siehe dazu Attribut <a href="#reverse-search-text-file">reverse-search-text-file</a>)
    </li>
    <li><a name="password"></a>
      <dt><code>set &lt;name&gt; password &lt;Passwort&gt;</code></dt>
      speichert das FritzBox Passwort, welches f&uuml;r das Einlesen aller Telefonb&uuml;cher direkt von der FritzBox ben&ouml;tigt wird. Dieses Kommando ist nur verf&uuml;gbar, wenn ein Passwort ben&ouml;tigt wird um das Telefonbuch via Netzwerk einzulesen, siehe dazu Attribut <a href="#fritzbox-remote-phonebook">fritzbox-remote-phonebook</a>.
    </li>
  </ul>
  <br>

  <a name="FB_CALLMONITORget"></a>
  <b>Get</b>
  <ul>
    <li><a name="search"></a>
      <dt><code>get &lt;name&gt; search &lt;phone-number&gt;</code></dt>
      gibt den Namen der Telefonnummer zur&uuml;ck (aus Cache, Telefonbuch oder R&uuml;ckw&auml;rtssuche)
    </li>
    <li><a name="showPhonebookIds"></a>
      <dt><code>get &lt;name&gt; showPhonebookIds</code></dt>
      gibt eine Liste aller verf&uuml;gbaren Telefonb&uuml;cher auf der FritzBox zur&uuml;ck (nicht verf&uuml;gbar wenn das Telefonbuch via Telnet-Verbindung eingelesen wird)
    </li>
    <li><a name="showPhonebookEntries"></a>
      <dt><code>get &lt;name&gt; showPhonebookEntries [Phonebook-ID]</code></dt>
      gibt eine Liste aller bekannten Telefonbucheintr&auml;ge, oder nur eines bestimmten Telefonbuchs, zur&uuml;ck (nur verf&uuml;gbar, wenn eine R&uuml;ckw&auml;rtssuche via Telefonbuch aktiviert ist)</li>
    <li><a name="showCacheEntries"></a>
      <dt><code>get &lt;name&gt; showCacheEntries</code></dt>
      gibt eine Liste aller bekannten Cacheeintr&auml;ge zur&uuml;ck (nur verf&uuml;gbar, wenn die Cache-Funktionalit&auml;t der R&uuml;ckw&auml;rtssuche aktiviert ist))
    </li>
    <li><a name="showTextEntries"></a>
      <dt><code>get &lt;name&gt; showTextEntries</code></dt>
      gibt eine Liste aller Eintr&auml;ge aus der nutzereigenen Textdatei zur&uuml;ck (nur verf&uuml;gbar, wenn eine Textdatei als Attribut definiert ist))
    </li>
  </ul>
  <br>

  <a name="FB_CALLMONITORattr"></a>
  <b>Attribute</b><br><br>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>

    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>

    <li><a name="disable">disable</a> 0,1</li>
      Optionales Attribut zur Deaktivierung des Callmonitors. Es k&ouml;nnen dann keine Anruf-Events mehr erkannt und erzeugt werden.
      <br><br>
      M&ouml;gliche Werte: 0 =&gt; Callmonitor ist aktiv, 1 =&gt; Callmonitor ist deaktiviert.<br>
      Standardwert ist 0 (aktiv)<br><br>

    <li><a name="disabledForIntervals">disabledForIntervals</a> HH:MM-HH:MM HH:MM-HH-MM...</li>
    Optionales Attribut zur Deaktivierung des Callmonitors innerhalb von bestimmten Zeitintervallen.
    Das Argument ist eine Leerzeichen-getrennte Liste von Minuszeichen-getrennten HH:MM P&auml;rchen (Stunde : Minute).
    Falls die aktuelle Uhrzeit zwischen diese Werte f&auml;llt, dann wird die Verarbeitung, wie bei <a href="#disable">disable</a>, ausgesetzt.
    Statt HH:MM kann man auch HH oder HH:MM:SS angeben.<br><br>
    Um einen Intervall um Mitternacht zu spezifizieren, muss man zwei einzelne Intervalle angeben, z.Bsp.:
    <pre>23:00-24:00 00:00-01:00</pre>
    Standardwert ist <i>nicht gesetzt</i> (dauerhaft aktiv)<br><br>

    <li><a name="answMachine-is-missed-call">answMachine-is-missed-call</a> 0,1</li>
    Sofern aktiviert, werden Anrufe, welche durch einen internen Anrufbeantworter beantwortet werden, als "unbeantworteter Anruf" gewertet (siehe Reading "missed_call" unter <a href="#events">Generated Events</a>).
    <br><br>
    M&ouml;gliche Werte: 0 =&gt; deaktiviert, 1 =&gt; aktiviert (Anrufbeantworter gilt als "unbeantworteter Anruf").<br><br>
    Standardwert ist 0 (deaktiviert)<br><br>

    <li><a name="internal-number-filter">internal-number-filter</a> &lt;Nummer&gt;[&lt;Nummer&gt;,...]</li>
    Sofern gesetzt, werden nur Gespr&auml;che f�r die konfigurierten internen Rufnummern verarbeitet.
    G&uuml;ltige Werte sind eine einzelne interne Rufnummer oder eine komma-separierte Liste von mehreren internen Rufnummern.
    Gespr&auml;che f�r interne Rufnummern, welche nicht in dieser Liste enthalten sind, werden ignoriert und nicht verarbeitet.
    Wenn dieses Attribut nicht konfiguriert ist, werden alle Gespr&auml;che regul&auml;r verarbeitet.<br><br>
    Standardm&auml;&szlig;ig ist diese Funktion deaktiviert (nicht gesetzt)<br><br>

    <li><a name="reverse-search">reverse-search</a> (phonebook,textfile,tellows.de,dasoertliche.de,11880.com,search.ch,dasschnelle.at,herold.at)</li>
    Aktiviert die R&uuml;ckw&auml;rtssuche der externen Rufnummer (bei eingehenden/ausgehenden Anrufen).
    Dieses Attribut enth&auml;lt eine komma-separierte Liste mit allen Anbietern die f&uuml;r eine R&uuml;ckw&auml;rtssuche benutzt werden sollen.
    Die R&uuml;ckw&auml;rtssuche pr&uuml;ft in der gegebenen Reihenfolge (von links nach rechts) ob der entsprechende Anbieter (Telefonbuch, Textdatei oder Internetanbieter) die Rufnummer aufl&ouml;sen k&ouml;nnen.
    Das erste Resultat was dabei gefunden wird, wird als Ergebnis f&uuml;r die R&uuml;ckw&auml;rtssuche verwendet.
    Es ist m&ouml;glich einen bestimmten Suchanbieter zu verwenden, welcher f&uuml;r die R&uuml;ckw&auml;rtssuche verwendet werden soll.
    Der Anbieter "textfile" verwendet die nutzereigene Textdatei, sofern definiert (siehe Attribut reverse-search-text-file).
    Der Anbieter "phonebook" verwendet das Telefonbuch der FritzBox (siehe Attribut reverse-search-phonebook-file oder fritzbox-remote-phonebook).<br><br>
    Standardm&auml;&szlig;ig ist diese Funktion deaktiviert (nicht gesetzt)<br><br>

    <li><a name="reverse-search-cache">reverse-search-cache</a> 0,1</li>
    Wenn dieses Attribut gesetzt ist, werden alle Ergebisse von Internetanbietern in einem modul-internen Cache gespeichert
    und alle existierenden Ergebnisse aus dem Cache genutzt anstatt eine erneute Anfrage bei einem Internet-Anbieter durchzuf&uuml;hren.
    Der Cache ist immer an die Internetanbieter gekoppelt und speichert nur Ergebnisse von Internetanbietern.<br><br>
    M&ouml;gliche Werte: 0 =&gt; deaktiviert , 1 =&gt; aktiviert<br>
    Standardwert ist 0 (deaktiviert)<br><br>

    <li><a name="reverse-search-cache-file">reverse-search-cache-file</a> &lt;Dateipfad&gt;</li>
    Da der Cache nur im Arbeitsspeicher existiert, ist er nicht persistent und geht beim stoppen von FHEM verloren.
    Mit diesem Parameter werden alle Cache-Ergebnisse in eine Textdatei geschrieben (z.B. /usr/share/fhem/telefonbuch.txt)
    und beim n&auml;chsten Start von FHEM wieder in den Cache geladen und genutzt.
    <br><br>

    <li><a name="reverse-search-cache-file">reverse-search-text-file</a> &lt;Dateipfad&gt;</li>
    L&auml;dt eine nutzereigene Textdatei welche eine eigene Namenszuordnungen f&uuml;r Rufnummern enth&auml;lt. Diese Datei enth&auml;lt zeilenweise komma-separierte Werte nach folgendem Schema:
    <pre>
    &lt;Nummer1&gt;,&lt;Name1&gt;
    &lt;Nummer2&gt;,&lt;Name2&gt;
    ...
    &lt;NummerN&gt;,&lt;NameN&gt;
    </pre>
    Die Datei kann dabei auch Kommentar-Zeilen enthalten mit # vorangestellt. Sollte die Datei nicht existieren, wird sie durch FHEM erstellt.
    <br><br>

    <li><a name="reverse-search-phonebook-file">reverse-search-phonebook-file</a> &lt;Dateipfad&gt</li>
    Mit diesem Attribut kann man optional den Pfad zu einer Datei angeben, welche ein Telefonbuch im FritzBox-Format (XML-Struktur) enth&auml;lt.
    Dadurch ist es m&ouml;glich ein FritzBox-Telefonbuch zu verwenden, ohne das FHEM auf einer FritzBox laufen muss.
    Sofern FHEM auf einer FritzBox l&auml;uft (und nichts abweichendes angegeben wurde), wird das interne File /var/flash/phonebook verwendet. Alternativ kann man das Telefonbuch in der FritzBox-Weboberfl&auml;che exportieren und dieses verwenden<br><br>
    Standardwert ist /var/flash/phonebook (entspricht dem Pfad auf einer FritzBox)<br><br>

    <li><a name="reverse-search-tellows-api-key">reverse-search-tellows-api-key</a> &lt;api-key&gt</li>
    tellows api-key. F�r Tests kann der api-key -test123- eingetragen werden<br><br>

    <li><a name="reverse-search-tellows-api-partner">reverse-search-tellows-api-partner</a> &lt;api-partner&gt</li>
    tellows api-partner. F�r Tests kann der api-partner -test- eingetragen werden<br><br>

    <li><a name="remove-leading-zero">remove-leading-zero</a> 0,1</li>
    Wenn dieses Attribut aktiviert ist, wird die f&uuml;hrende Null aus der externen Rufnummer (bei eingehenden &amp; abgehenden Anrufen) entfernt. Dies ist z.B. notwendig bei Telefonanlagen.<br><br>
    M&ouml;gliche Werte: 0 =&gt; deaktiviert , 1 =&gt; aktiviert<br>
    Standardwert ist 0 (deaktiviert)<br><br>

    <li><a name="unique-call-ids">unique-call-ids</a> 0,1</li>
    Wenn dieses Attribut aktiviert ist, wird f&uuml;r jedes Gespr&auml;ch eine eineindeutige Identifizierungsnummer verwendet. Dadurch lassen sich auch bereits beendete Gespr&auml;che voneinander unterscheiden. Dies ist z.B. notwendig bei der Verarbeitung der Events durch eine Datenbank.<br><br>
    M&ouml;gliche Werte: 0 =&gt; deaktiviert , 1 =&gt; aktiviert<br>
    Standardwert ist 0 (deaktiviert)<br><br>

    <li><a name="local-area-code">local-area-code</a> &lt;Ortsvorwahl&gt;</li>
    Verwendet die gesetze Vorwahlnummer bei R&uuml;ckw&auml;rtssuchen von Ortsgespr&auml;chen (z.B. 0228 f&uuml;r Bonn)<br><br>

    <li><a name="country-code">country-code</a> &lt;Landesvorwahl&gt;</li>
    Die Landesvorwahl wird ben&ouml;tigt um Telefonbucheintr&auml;ge mit lokaler Landesvorwahl als Inlands-Rufnummern, als auch um Call-By-Call-Vorwahlen richtig zu erkennen (z.B. 0049 f&uuml;r Deutschland, 0043 f&uuml;r &Ouml;sterreich oder 001 f&uuml;r USA).<br><br>
    Standardwert ist 0049 (Deutschland)<br><br>

    <li><a name="check-deflection">check-deflections</a> 0,1</li>
    Wenn dieses Attribut aktiviert ist, werden eingehende Anrufe gegen die konfigurierten Rufsperren-Regeln aus der FritzBox gepr&uuml;ft. Wenn ein Anruf auf eine dieser Regeln passt, wird der Anruf ignoriert und es werden keinerlei Readings/Events f&uuml;r diesen Anruf generiert. Dies funktioniert nur, wenn man das Telefonbuch aus der FritzBox via TR-064 einliest (siehe Attribute <a href="#fritzbox-remote-phonebook">fritzbox-remote-phonebook</a> und <a href="#fritzbox-remote-phonebook-via">fritzbox-remote-phonebook-via</a>).<br><br>
    M&ouml;gliche Werte: 0 =&gt; deaktiviert , 1 =&gt; aktiviert<br>
    Standardwert ist 0 (deaktiviert)<br><br>

    <li><a name="fritzbox-remote-phonebook">fritzbox-remote-phonebook</a> 0,1</li>
    Wenn dieses Attribut aktiviert ist, wird das FritzBox Telefonbuch direkt von der FritzBox gelesen. Dazu ist das FritzBox Passwort und je nach FritzBox Konfiguration auch ein Username notwendig, der in den entsprechenden Attributen konfiguriert sein muss.<br><br>
    M&ouml;gliche Werte: 0 =&gt; deaktiviert , 1 =&gt; aktiviert<br>
    Standardwert ist 0 (deaktiviert)<br><br>

    <li><a name="fritzbox-remote-phonebook-via">fritzbox-remote-phonebook-via</a> tr064,web,telnet</li>
    Setzt die Methode mit der das Telefonbuch von der FritzBox abgefragt werden soll. Bei der Methode "web", werden alle verf&uuml;gbaren Telefonb&uuml;cher (lokales sowie alle konfigurierten Online-Telefonb&uuml;cher) &uuml;ber die Web-Oberfl&auml;che eingelesen. Bei der Methode "telnet" wird eine Telnet-Verbindung zur FritzBox aufgebaut um das lokale Telefonbuch abzufragen (keine Online-Telefonb&uuml;cher). Dazu muss die Telnet-Funktion aktiviert sein (Telefon Kurzwahl: #96*7*). Bei der Methode "tr064" werden alle verf&uuml;gbaren Telefonb&uuml;cher &uuml;ber die TR-064 SOAP Schnittstelle ausgelesen. <br><br>
    M&ouml;gliche Werte: tr064,web,telnet<br>
    Standardwert ist "tr064" (Abfrage aller verf&uuml;gbaren Telefonb&uuml;cher &uuml;ber die TR-064-Schnittstelle)<br><br>

    <li><a name="fritzbox-remote-phonebook-exclude">fritzbox-remote-phonebook-exclude</a> &lt;Liste&gt;</li>
    Eine komma-separierte Liste von Telefonbuch-ID's oder Namen welche beim einlesen &uuml;bersprungen werden sollen. Dieses Attribut greift nur beim einlesen der Telefonb&uuml;cher via "web"- oder "tr064"-Methode (siehe Attribut <i>fritzbox-remote-phonebook-via</i>). Eine Liste aller m&ouml;glichen Werte kann &uuml;ber das <a href="#get">Get-Kommando</a> <i>showPhonebookIds</i> angezeigt werden.<br><br>
    Standardm&auml;&szlig;ig ist diese Funktion deaktiviert (alle Telefonb&uuml;cher werden eingelesen)<br><br>

    <li><a name="fritzbox-user">fritzbox-user</a> &lt;Username&gt;</li>
    Der Username, sofern das Telefonbuch direkt von der FritzBox via Netzwerk geladen werden soll (siehe Attribut: <a href="#fritzbox-remote-phonebook">fritzbox-remote-phonebook</a>). Dieses Attribut ist nur notwendig, wenn verschiedene Benutzernamen auf der FritzBox konfiguriert sind.<br><br>
    <li><a name="apiKeySearchCh">apiKeySearchCh</a> &lt;API-Key&gt;</li>
    Der private API-Key von <a href="https://tel.search.ch/api/getkey" target="_new">tel.search.ch</a> um eine R&uuml;ckw&auml;rtssuche via search.ch durchzuf&uuml;hren (siehe Attribut <a href=#reverse-search">reverse-search</a>). Ohne einen solchen API-Key ist eine R&uuml;ckw&auml;rtssuche via search.ch nicht m&ouml;glich<br><br>

    <li><a name="sendKeepAlives">sendKeepAlives</a> (none,5m,10m,15m,30m,1h)</li>
    Wenn dieses Attribut gesetzt ist, wird ein zyklisches Keep-Alive im konfigurierten Zeitabstand an die FritzBox gesendet um die Verbindung aktiv zu halten. Dadurch bleibt die Verbindung bestehen, insbesondere wenn die verbundene FritzBox sich hinter einem weiteren NAT-Router befindet (z.B. einer weiteren FritzBox). Dadurch wird die Verbindung in so einem Fall nicht f&auml;lschlicherweise als "tot" erkannt und geblockt.<br><br>
    M&ouml;gliche Werte: none,5m,10m,15m,30m,1h<br>
    Standardwert ist "none" (es werden keine Keep-Alives gesendet)<br><br>

    <li><a name="contactImageDirectory">contactImageDirectory</a> &lt;Verzeichnis&gt;</li>
    Sofern gesetzt, generiert FB_CALLMONITOR das Reading "contact_image" sofern eine Datei mit der externen Rufnummer als Dateinamen (z.B. "012323456.jpg") in diesem Verzeichnis existiert.
    Wenn keine passende Datei in dem Verzeichnis existiert oder die externe Rufnummer unterdr&uuml;ckt ist, wird das Reading "contact_image" auf den Wert "none" gesetzt (kann mit dem Attribut <a href="#contactDefaultImage">contactDefaultImage</a> ge&auml;ndert werden)
    <br><br>

    <li><a name="contactDefaultImage">contactDefaultImage</a> &lt;Dateiname&gt;</li>
    Sofern gesetzt, verwendet FB_CALLMONITOR den gesetzten Dateinamen anstelle von "none", sollte keine passende Datei zu einer Rufnummer existieren oder die Rufnummer unterdr&uuml;ckt sein.
    <br><br>

    <li><a name="contactImageViaTR064">contactImageViaTR064</a> 0,1</li>
    Wenn dieses Attribut aktiviert ist, l&auml;dt FB_CALLMONITOR alle verf&uuml;gbaren Kontaktbilder aus dem FritzBox Telefonb&uuml;chern via TR-064 (if attribute <a href="#fritzbox-remote-phonebook-via">fritzbox-remote-phonebook-via</a> is set to <code>tr064</code>) und speichert diese in dem Verzeichnis <a href="#contactImageDirectory">contactImageDirectory</a>.
    Die heruntergeladenen Kontaktbilder werden dann automatisch f&uuml;r das Reading "contact_image" verwendet.
    <br><br>
    M&ouml;gliche Werte: 0 =&gt; deaktiviert , 1 =&gt; aktiviert<br>
    Standardwert ist 1 (aktiviert)<br><br>
  </ul>

  <br>
  <br>

  <a name="FB_CALLMONITORevents"></a>
  <b>Generierte Events:</b><br><br>
  <ul>
    <li><b>event</b> (call|ring|connect|disconnect) - Welches Event wurde genau ausgel&ouml;st. ("call" =&gt; ausgehender Rufversuch, "ring" =&gt; eingehender Rufversuch, "connect" =&gt; Gespr&auml;ch ist zustande gekommen, "disconnect" =&gt; es wurde aufgelegt)</li>
    <li><b>direction</b> (incoming|outgoing) - Die Anruf-Richtung ("incoming" =&gt; eingehender Anruf, "outgoing" =&gt; ausgehender Anruf)</li>
    <li><b>external_number</b> - Die Rufnummer des Gegen&uuml;bers, welcher anruft (event: ring) oder angerufen wird (event: call)</li>
    <li><b>external_name</b> - Das Ergebniss der R&uuml;ckw&auml;rtssuche (sofern aktiviert). Im Fehlerfall kann diese Reading auch den Inhalt "unknown" (keinen Eintrag gefunden) enthalten. Im Falle einer Zeit&uuml;berschreitung bei der R&uuml;ckw&auml;rtssuche und aktiviertem Caching, wird die Rufnummer beim n&auml;chsten Mal erneut gesucht.</li>
    <li><b>internal_number</b> - Die interne Rufnummer (Festnetz, VoIP-Nummer, ...) auf welcher man angerufen wird (event: ring) oder die man gerade nutzt um jemanden anzurufen (event: call)</li>
    <li><b>internal_connection</b> - Der interne Anschluss an der Fritz!Box welcher genutzt wird um das Gespr&auml;ch durchzuf&uuml;hren (FON1, FON2, ISDN, DECT, ...)</li>
    <li><b>external_connection</b> - Der externe Anschluss welcher genutzt wird um das Gespr&auml;ch durchzuf&uuml;hren  ("POTS" =&gt; analoges Festnetz, "SIPx" =&gt; VoIP Nummer, "ISDN", "GSM" =&gt; Mobilfunk via GSM/UMTS-Stick)</li>
    <li><b>calls_count</b> - Die Anzahl aller aktiven Verbindungen (gleichzeitig). Ist der Wert 0, so wird gerade kein Gespr&auml;ch gef&uuml;hrt.</li>
    <li><b>call_duration</b> - Die Gespr&auml;chsdauer in Sekunden. Dieser Wert wird nur bei einem disconnect-Event erzeugt. Ist der Wert 0, so wurde das Gespr&auml;ch von niemandem angenommen.</li>
    <li><b>call_id</b> - Die Identifizierungsnummer eines einzelnen Gespr&auml;chs. Dient der Zuordnung bei zwei oder mehr parallelen Gespr&auml;chen, damit alle Events eindeutig einem Gespr&auml;ch zugeordnet werden k&ouml;nnen</li>
    <li><b>missed_call</b> - Dieses Event wird nur generiert, wenn ein eingehender Anruf nicht beantwortet wird. Sofern der Name dazu bekannt ist, wird dieser ebenfalls mit angezeigt.</li>
    <li><b>contact_image</b> - Dieses Event wird nur generiert, wenn das Attribut <a href="#contactImageDirectory">contactImageDirectory</a> gesetzt ist. Es enth&auml;lt das zugeh&ouml;rige Kontaktfoto als Dateiname oder "none", falls kein entsprechendes Kontaktfoto existiert, oder die Rufnummer unterdr&uuml;ckt ist.</li>
  </ul>
</ul>

</div>
=end html_DE
=cut
