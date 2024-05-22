###############################################################################
#
# Developed with VSCodium and richterger perl plugin.
#
#  (c) 2017-2024 Copyright: Marko Oldenburg (fhemdevelopment at cooltux dot net)
#  All rights reserved
#
#   Special thanks goes to comitters:
#       - Michael (mbrak)       Thanks for Commandref
#       - Matthias (Kenneth)    Thanks for Wiki entry
#       - BioS                  Thanks for predefined start points Code
#       - fettgu                Thanks for Debugging Irrigation Control data flow
#       - Sebastian (BOFH)      Thanks for new Auth Code after API Change
#
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
# $Id$
#
###############################################################################
##
##
## Das JSON Modul immer in einem eval aufrufen
# $data = eval{decode_json($data)};
#
# if($@){
#   Log3($SELF, 2, "$TYPE ($SELF) - error while request: $@");
#
#   readingsSingleUpdate($hash, "state", "error", 1);
#
#   return;
# }
#
#
###### Wichtige Notizen
#
#   apt-get install libio-socket-ssl-perl
#   http://www.dxsdata.com/de/2016/07/php-class-for-gardena-smart-system-api/
#
##
##

package FHEM::GardenaSmartBridge;
use GPUtils qw(GP_Import GP_Export);

use strict;
use warnings;
use POSIX;
use FHEM::Meta;

use HttpUtils;

my $missingModul = '';
eval { use Encode qw /encode_utf8 decode_utf8/; 1 }
  or $missingModul .= "Encode ";

# eval "use JSON;1" || $missingModul .= 'JSON ';
eval { use IO::Socket::SSL; 1 }
  or $missingModul .= 'IO::Socket::SSL ';

# try to use JSON::MaybeXS wrapper
#   for chance of better performance + open code
eval {
    require JSON::MaybeXS;
    import JSON::MaybeXS qw( decode_json encode_json );
    1;
} or do {

    # try to use JSON wrapper
    #   for chance of better performance
    eval {
        # JSON preference order
        local $ENV{PERL_JSON_BACKEND} =
          'Cpanel::JSON::XS,JSON::XS,JSON::PP,JSON::backportPP'
          unless ( defined( $ENV{PERL_JSON_BACKEND} ) );

        require JSON;
        import JSON qw( decode_json encode_json );
        1;
    } or do {

        # In rare cases, Cpanel::JSON::XS may
        #   be installed but JSON|JSON::MaybeXS not ...
        eval {
            require Cpanel::JSON::XS;
            import Cpanel::JSON::XS qw(decode_json encode_json);
            1;
        } or do {

            # In rare cases, JSON::XS may
            #   be installed but JSON not ...
            eval {
                require JSON::XS;
                import JSON::XS qw(decode_json encode_json);
                1;
            } or do {

                # Fallback to built-in JSON which SHOULD
                #   be available since 5.014 ...
                eval {
                    require JSON::PP;
                    import JSON::PP qw(decode_json encode_json);
                    1;
                } or do {

                    # Fallback to JSON::backportPP in really rare cases
                    require JSON::backportPP;
                    import JSON::backportPP qw(decode_json encode_json);
                    1;
                };
            };
        };
    };
};

## Import der FHEM Funktionen
#-- Run before package compilation
BEGIN {
    # Import from main context
    GP_Import(
        qw(readingsSingleUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsBeginUpdate
          readingsEndUpdate
          Log3
          devspec2array
          asyncOutput
          CommandAttr
          AttrVal
          InternalVal
          ReadingsVal
          CommandDefMod
          modules
          setKeyValue
          getKeyValue
          getUniqueId
          RemoveInternalTimer
          readingFnAttributes
          InternalTimer
          defs
          init_done
          IsDisabled
          deviceEvents
          HttpUtils_NonblockingGet
          gettimeofday
          Dispatch)
    );
}

#-- Export to main context with different name
GP_Export(
    qw(
      Initialize
    )
);

sub Initialize {
    my $hash = shift;

    # Provider
    $hash->{WriteFn}   = \&Write;
    $hash->{Clients}   = ':GardenaSmartDevice:';
    $hash->{MatchList} = { '1:GardenaSmartDevice' => '^{"id":".*' };

    # Consumer
    $hash->{SetFn}    = \&Set;
    $hash->{GetFn}    = \&Get;
    $hash->{DefFn}    = \&Define;
    $hash->{UndefFn}  = \&Undef;
    $hash->{DeleteFn} = \&Delete;
    $hash->{RenameFn} = \&Rename;
    $hash->{NotifyFn} = \&Notify;

    $hash->{AttrFn} = \&Attr;
    $hash->{AttrList} =
        'debugJSON:0,1 '
      . 'debugDEVICE:0,1 '
      . 'disable:1 '
      . 'interval '
      . 'disabledForIntervals '
      . 'gardenaAccountEmail '
      . 'gardenaBaseURL '
      . $readingFnAttributes;
    $hash->{parseParams} = 1;

    return FHEM::Meta::InitMod( __FILE__, $hash );
}

sub Define {
    my $hash = shift // return;
    my $aArg = shift // return;


    return $@ unless ( FHEM::Meta::SetInternals($hash) );
    use version 0.60; our $VERSION = FHEM::Meta::Get( $hash, 'version' );

    return 'too few parameters: define <NAME> GardenaSmartBridge'
      if ( scalar( @{$aArg} ) != 2 );
    return
        'Cannot define Gardena Bridge device. Perl modul '
      . ${missingModul}
      . ' is missing.'
      if ($missingModul);

    my $name = shift @$aArg;
    $hash->{BRIDGE} = 1;
    $hash->{URL} =
      AttrVal( $name, 'gardenaBaseURL', 'https://smart.gardena.com' ) . '/v1';
    $hash->{VERSION}   = version->parse($VERSION)->normal;
    $hash->{INTERVAL}  = 180;
    $hash->{NOTIFYDEV} = "global,$name";
    $hash->{helper}{gettoken_count} = 0;

    CommandAttr( undef, $name . ' room GardenaSmart' )
      if ( AttrVal( $name, 'room', 'none' ) eq 'none' );

    readingsSingleUpdate( $hash, 'token', 'none',        1 );
    readingsSingleUpdate( $hash, 'state', 'initialized', 1 );

    Log3 $name, 3, "GardenaSmartBridge ($name) - defined GardenaSmartBridge";

    $modules{GardenaSmartBridge}{defptr}{BRIDGE} = $hash;

    return;
}

sub Undef {
    my $hash = shift;
    my $name = shift;

    RemoveInternalTimer( $hash, "FHEM::GardenaSmartBridge::getDevices" );
    delete $modules{GardenaSmartBridge}{defptr}{BRIDGE}
      if ( defined( $modules{GardenaSmartBridge}{defptr}{BRIDGE} ) );

    return;
}

sub Delete {
    my $hash = shift;
    my $name = shift;

    setKeyValue( $hash->{TYPE} . '_' . $name . '_passwd', undef );
    return;
}

sub Attr {
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    if ( $attrName eq 'disable' ) {
        if ( $cmd eq 'set' && $attrVal eq '1' ) {
            RemoveInternalTimer( $hash,
                "FHEM::GardenaSmartBridge::getDevices" );
            RemoveInternalTimer( $hash,
                "FHEM::GardenaSmartBridge::getToken" );
            readingsSingleUpdate( $hash, 'state', 'inactive', 1 );
            Log3 $name, 3, "GardenaSmartBridge ($name) - disabled";
        }
        elsif ( $cmd eq 'del' ) {
            readingsSingleUpdate( $hash, 'state', 'active', 1 );
            Log3 $name, 3, "GardenaSmartBridge ($name) - enabled";
        }
    }
    elsif ( $attrName eq 'disabledForIntervals' ) {
        if ( $cmd eq 'set' ) {
            return
"check disabledForIntervals Syntax HH:MM-HH:MM or 'HH:MM-HH:MM HH:MM-HH:MM ...'"
              if ( $attrVal !~ /^((\d{2}:\d{2})-(\d{2}:\d{2})\s?)+$/ );
            Log3 $name, 3, "GardenaSmartBridge ($name) - disabledForIntervals";
        }
        elsif ( $cmd eq 'del' ) {
            readingsSingleUpdate( $hash, 'state', 'active', 1 );
            Log3 $name, 3, "GardenaSmartBridge ($name) - enabled";
        }
    }
    elsif ( $attrName eq 'interval' ) {
        if ( $cmd eq 'set' ) {
            return 'Interval must be greater than 0'
              if ( $attrVal == 0 );
            RemoveInternalTimer( $hash,
                "FHEM::GardenaSmartBridge::getDevices" );
            $hash->{INTERVAL} = $attrVal if $attrVal >= 180;
            Log3 $name, 3,
              "GardenaSmartBridge ($name) - set interval: $attrVal";
        }
        elsif ( $cmd eq 'del' ) {
            RemoveInternalTimer( $hash,
                "FHEM::GardenaSmartBridge::getDevices" );
            $hash->{INTERVAL} = 180;
            Log3 $name, 3,
"GardenaSmartBridge ($name) - delete User interval and set default: 60";
        }
    }
    elsif ( $attrName eq 'gardenaBaseURL' ) {
        if ( $cmd eq 'set' ) {
            $hash->{URL} = $attrVal;
            Log3 $name, 3,
              "GardenaSmartBridge ($name) - set gardenaBaseURL to: $attrVal";
        }
        elsif ( $cmd eq 'del' ) {
            $hash->{URL} = 'https://smart.gardena.com/v1';
        }
    }

    return;
}

sub Notify {
    my $hash = shift // return;
    my $dev  = shift // return;

    my $name = $hash->{NAME};
    return if ( IsDisabled($name) );

    my $devname = $dev->{NAME};
    my $devtype = $dev->{TYPE};
    my $events  = deviceEvents( $dev, 1 );
    return if ( !$events );

    getToken($hash)
      if (
        (
            $devtype eq 'Global'
            && (
                grep /^INITIALIZED$/,
                @{$events} or grep /^REREADCFG$/,
                @{$events} or grep /^DEFINED.$name$/,
                @{$events} or grep /^MODIFIED.$name$/,
                @{$events} or grep /^ATTR.$name.gardenaAccountEmail.+/,
                @{$events} or grep /^DELETEATTR.$name.disable$/,
                @{$events}
            )
        )

        || ( $devtype eq 'GardenaSmartBridge'
            && ( grep /^gardenaAccountPassword.+/, @{$events} ) )
        && $init_done
      );

    getDevices($hash)
      if (
        $devtype eq 'Global'
        && (
            grep /^ATTR.$name.disable.0$/,
            @{$events} or grep /^DELETEATTR.$name.interval$/,
            @{$events} or grep /^ATTR.$name.interval.[0-9]+/,
            @{$events}
        )
        && $init_done
      );

    if (
        $devtype eq 'GardenaSmartBridge'
        && (
            grep /^state:.Connected$/,
            @{$events} or grep /^lastRequestState:.request_error$/,
            @{$events}
        )
      )
    {
        InternalTimer( gettimeofday() + $hash->{INTERVAL},
            "FHEM::GardenaSmartBridge::getDevices", $hash );
        Log3 $name, 4,
"GardenaSmartBridge ($name) - set internal timer function for recall getDevices sub";
    }

    return;
}

sub Get {
    my $hash = shift // return;
    my $aArg = shift // return;

    my $name = shift @$aArg // return;
    my $cmd  = shift @$aArg
      // return qq{"get $name" needs at least one argument};

    if ( lc $cmd eq 'debug_devices_list' ) {
        my $device = shift @$aArg;
        $hash->{helper}{debug_device} = $device;
        Write( $hash, undef, undef, undef, undef );
        return;
    }
    else {
        my $list = "";
        $list .=
          " debug_devices_list:" . join( ',', @{ $hash->{helper}{deviceList} } )
          if ( AttrVal( $name, "debugDEVICE", "none" ) ne "none"
            && exists( $hash->{helper}{deviceList} ) );
        return "Unknown argument $cmd,choose one of $list";
    }
}

sub Set {
    my $hash = shift // return;
    my $aArg = shift // return;

    my $name = shift @$aArg // return;
    my $cmd  = shift @$aArg
      // return qq{"set $name" needs at least one argument};

#     Das Argument für das Passwort, also das Passwort an sich darf keine = enthalten!!!

    if ( lc $cmd eq 'getdevicesstate' ) {
        getDevices($hash);
    }
    elsif ( lc $cmd eq 'gettoken' ) {
        return "please set Attribut gardenaAccountEmail first"
          if ( AttrVal( $name, 'gardenaAccountEmail', 'none' ) eq 'none' );
        return "please set gardenaAccountPassword first"
          if ( not defined( ReadPassword( $hash, $name ) ) );
        return "token is up to date"
          if ( defined( $hash->{helper}{session_id} ) );

        getToken($hash);
    }
    elsif ( lc $cmd eq 'gardenaaccountpassword' ) {
        return "please set Attribut gardenaAccountEmail first"
          if ( AttrVal( $name, 'gardenaAccountEmail', 'none' ) eq 'none' );
        return "usage: $cmd <password>" if ( scalar( @{$aArg} ) != 1 );

        StorePassword( $hash, $name, $aArg->[0] );
    }
    elsif ( lc $cmd eq 'deleteaccountpassword' ) {
        return "usage: $cmd" if ( scalar( @{$aArg} ) != 0 );

        DeletePassword($hash);
    }
    elsif ( lc $cmd eq 'debughelper' ) {
        return "usage: $cmd" if ( scalar( @{$aArg} ) != 2 );
        my $new_helper       = $aArg->[0];
        my $new_helper_value = $aArg->[1];
        Log3( $name, 5,
"[DEBUG] - GardenaSmartBridge ($name) - override helper $new_helper with $new_helper_value"
        );
        $hash->{helper}{$new_helper} = $new_helper_value;
    }
    else {

        my $list = "getDevicesState:noArg getToken:noArg"
          if ( defined( ReadPassword( $hash, $name ) ) );
        $list .= " gardenaAccountPassword"
          if ( not defined( ReadPassword( $hash, $name ) ) );
        $list .= " deleteAccountPassword:noArg"
          if ( defined( ReadPassword( $hash, $name ) ) );
        return "Unknown argument $cmd, choose one of $list";
    }

    return;
}

sub Write {
    my ( $hash, $payload, $deviceId, $abilities, $service_id ) = @_;
    my $name = $hash->{NAME};

    my ( $session_id, $header, $uri, $method );

    ( $payload, $session_id, $header, $uri, $method, $deviceId, $service_id ) =
      createHttpValueStrings( $hash, $payload, $deviceId, $abilities,
        $service_id );

    HttpUtils_NonblockingGet(
        {
            url                => $hash->{URL} . $uri,
            timeout            => 15,
            incrementalTimeout => 1,
            hash               => $hash,
            device_id          => $deviceId,
            data               => $payload,
            method             => $method,
            header             => $header,
            doTrigger          => 1,
            cl                 => $hash->{CL},
            callback           => \&ErrorHandling
        }
    );

    Log3( $name, 4,
"GardenaSmartBridge ($name) - Send with URL: $hash->{URL}$uri, HEADER: secret!, DATA: secret!, METHOD: $method"
    );

# Log3($name, 3,
#     "GardenaSmartBridge ($name) - Send with URL: $hash->{URL}$uri, HEADER: $header, DATA: $payload, METHOD: $method");

    return;
}

sub ErrorHandling {
    my $param = shift;
    my $err   = shift;
    my $data  = shift;

    my $hash  = $param->{hash};
    my $name  = $hash->{NAME};
    my $dhash = $hash;

    $dhash = $modules{GardenaSmartDevice}{defptr}{ $param->{'device_id'} }
      if ( defined( $param->{'device_id'} ) );

    my $dname = $dhash->{NAME};

    Log3 $name, 4, "GardenaSmartBridge ($name) - Request: $data";

    my $decode_json = eval { decode_json($data) } if ( length($data) > 0 );
    if ($@) {
        Log3 $name, 3, "GardenaSmartBridge ($name) - JSON error while request";
    }

    if ( defined($err) ) {
        if ( $err ne "" ) {

            readingsBeginUpdate($dhash);
            readingsBulkUpdate( $dhash, "state", "$err" )
              if ( ReadingsVal( $dname, "state", 1 ) ne "initialized" );

            readingsBulkUpdate( $dhash, "lastRequestState", "request_error",
                1 );

            if ( $err =~ /timed out/ ) {
                Log3 $dname, 5,
"GardenaSmartBridge ($dname) - RequestERROR: connect to gardena cloud is timed out. check network";
            }

            elsif ($err =~ /Keine Route zum Zielrechner/
                || $err =~ /no route to target/ )
            {

                Log3 $dname, 5,
"GardenaSmartBridge ($dname) - RequestERROR: no route to target. bad network configuration or network is down";

            }
            else {

                Log3 $dname, 5,
                  "GardenaSmartBridge ($dname) - RequestERROR: $err";
            }

            readingsEndUpdate( $dhash, 1 );

            Log3 $dname, 5,
"GardenaSmartBridge ($dname) - RequestERROR: GardenaSmartBridge RequestErrorHandling: error while requesting gardena cloud: $err";

            delete $dhash->{helper}{deviceAction}
              if ( defined( $dhash->{helper}{deviceAction} ) );

            return;
        }
    }

    if ( $data eq "" && exists( $param->{code} ) && $param->{code} != 200 ) {

        readingsBeginUpdate($dhash);
        readingsBulkUpdate( $dhash, "state", $param->{code}, 1 )
          if ( ReadingsVal( $dname, "state", 1 ) ne "initialized" );

        readingsBulkUpdateIfChanged( $dhash, "lastRequestState",
            "request_error", 1 );

        if ( $param->{code} == 401 && $hash eq $dhash ) {

            if ( ReadingsVal( $dname, 'token', 'none' ) eq 'none' ) {
                readingsBulkUpdate( $dhash, "state", "no token available", 1 );
                readingsBulkUpdateIfChanged( $dhash, "lastRequestState",
                    "no token available", 1 );
            }

            Log3 $dname, 5,
              "GardenaSmartBridge ($dname) - RequestERROR: " . $param->{code};

        }
        elsif ($param->{code} == 204
            && $dhash ne $hash
            && defined( $dhash->{helper}{deviceAction} ) )
        {

            readingsBulkUpdate( $dhash, "state", "the command is processed",
                1 );
            InternalTimer(
                gettimeofday() + 5,
                "FHEM::GardenaSmartBridge::getDevices",
                $hash, 1
            );

        }
        elsif ( $param->{code} != 200 ) {

            Log3 $dname, 5,
              "GardenaSmartBridge ($dname) - RequestERROR: " . $param->{code};
        }

        readingsEndUpdate( $dhash, 1 );

        Log3 $dname, 5,
            "GardenaSmartBridge ($dname) - RequestERROR: received http code "
          . $param->{code}
          . " without any data after requesting gardena cloud";

        delete $dhash->{helper}{deviceAction}
          if ( defined( $dhash->{helper}{deviceAction} ) );

        return;
    }

    if (
        $data =~ /Error/ && $data !~ /lastLonaErrorCode/
        || (   defined($decode_json)
            && ref($decode_json) eq 'HASH'
            && defined( $decode_json->{errors} ) )
      )
    {
        readingsBeginUpdate($dhash);
        readingsBulkUpdate( $dhash, "state", $param->{code}, 1 )
          if ( ReadingsVal( $dname, "state", 0 ) ne "initialized" );

        readingsBulkUpdate( $dhash, "lastRequestState", "request_error", 1 );

        if ( $param->{code} == 400 ) {
            if ($decode_json) {
                if ( ref( $decode_json->{errors} ) eq "ARRAY"
                    && exists( $decode_json->{errors} ) )

                  # replace defined with exists
                  # && defined( $decode_json->{errors} ) )
                {
                    # $decode_json->{errors} -> ARRAY
                    # $decode_json->{errors}[0] -> HASH
                    if ( exists( $decode_json->{errors}[0]{error} ) ) {
                        readingsBulkUpdate(
                            $dhash,
                            "state",
                            $decode_json->{errors}[0]{error} . ' '
                              . $decode_json->{errors}[0]{attribute},
                            1
                        );
                        readingsBulkUpdate(
                            $dhash,
                            "lastRequestState",
                            $decode_json->{errors}[0]{error} . ' '
                              . $decode_json->{errors}[0]{attribute},
                            1
                        );
                        Log3 $dname, 5,
                            "GardenaSmartBridge ($dname) - RequestERROR: "
                          . $decode_json->{errors}[0]{error} . " "
                          . $decode_json->{errors}[0]{attribute};
                    }    # fi exists error
                }
            }
            else {
                readingsBulkUpdate( $dhash, "lastRequestState",
                    "Error 400 Bad Request", 1 );
                Log3 $dname, 5,
"GardenaSmartBridge ($dname) - RequestERROR: Error 400 Bad Request";
            }
        }
        elsif ( $param->{code} == 503 ) {

            Log3 $dname, 5,
"GardenaSmartBridge ($dname) - RequestERROR: Error 503 Service Unavailable";
            readingsBulkUpdate( $dhash, "state", "Service Unavailable", 1 );
            readingsBulkUpdate( $dhash, "lastRequestState",
                "Error 503 Service Unavailable", 1 );

        }
        elsif ( $param->{code} == 404 ) {
            if ( defined( $dhash->{helper}{deviceAction} ) && $dhash ne $hash )
            {
                readingsBulkUpdate( $dhash, "state", "device Id not found", 1 );
                readingsBulkUpdate( $dhash, "lastRequestState",
                    "device id not found", 1 );
            }

            Log3 $dname, 5,
              "GardenaSmartBridge ($dname) - RequestERROR: Error 404 Not Found";

        }
        elsif ( $param->{code} == 500 ) {

            Log3 $dname, 5,
              "GardenaSmartBridge ($dname) - RequestERROR: check the ???";

        }
        elsif ( $decode_json->{errors}[0]{code} eq "ratelimit.exceeded"  ) {
          Log3 $name, 5,
            "GardenaSmartBridge ($name) - RequestERROR: error ratelimit.exceeded";
          readingsBulkUpdate( $hash, "lastRequestState", "too many requests", 1 );
          readingsBulkUpdate( $hash, "state", "inactive", 1 );
          # remove all timer and disable bridge
          RemoveInternalTimer( $hash );

          return; # post request max.
        }
        else {

            Log3 $dname, 5,
              "GardenaSmartBridge ($dname) - RequestERROR: http error "
              . $param->{code};
        }

        if ( !defined( $hash->{helper}{session_id} ) ) {
            readingsSingleUpdate( $hash, 'token', 'none', 1 );
            Log3 $name, 3,
              "GardenaSmartBridge ($name) - getToken limit: " 
              . $hash->{helper}{gettoken_count} ;

            if ($hash->{helper}{gettoken_count} < 6) {
              $hash->{helper}{gettoken_count}++;
              InternalTimer( gettimeofday() + 5,
                "FHEM::GardenaSmartBridge::getToken", $hash )
            } else {
              RemoveInternalTimer ($hash);
              $hash->{helper}{gettoken_count} = 0;
            }
        }
        readingsEndUpdate( $dhash, 1 );

        Log3 $dname, 5,
            "GardenaSmartBridge ($dname) - RequestERROR: received http code "
          . $param->{code}
          . " receive Error after requesting gardena cloud";

        delete $dhash->{helper}{deviceAction}
          if ( defined( $dhash->{helper}{deviceAction} ) );

        return;
    }
    elsif ( defined( $decode_json->{message} )
        && $decode_json->{message} eq 'Unauthorized' )
    {
        Log3 $name, 3,
          "GardenaSmartBridge ($name) - Unauthorized -> fetch new token ";

        getToken($hash);

        return;
    }

    if ( defined( $hash->{helper}{debug_device} )
        && $hash->{helper}{debug_device} ne 'none' )
    {
        Log3 $name, 4, "GardenaSmartBridge DEBUG Device";
        delete $hash->{helper}{debug_device};

        my @device_spec = ( "name", "id", "category" );
        my $devJson     = $decode_json->{devices};
        my $output = '.:{ DEBUG OUTPUT for ' . $devJson->{name} . ' }:. \n';

        for my $spec (@device_spec) {
            $output .= "$spec : $devJson->{$spec} \n";
        }

        #settings
        $output .= '\n=== Settings \n';
        my $i = 0;
        for my $dev_settings ( @{ $devJson->{settings} } ) {
            $output .= "[" . $i++ . "]id: $dev_settings->{id} \n";
            $output .= "name: $dev_settings->{name} \n";
            if (   ref( $dev_settings->{value} ) eq 'ARRAY'
                || ref( $dev_settings->{value} ) eq 'HASH' )
            {
                $output .= 'N/A \n';
            }
            else {
                $output .= "value: $dev_settings->{value} \n";
            }
        }

        $output .= '\n=== Abilities \n';
        $i = 0;

        for my $dev_settings ( @{ $devJson->{abilities} } ) {
            $output .= "[" . $i++ . "]id: $dev_settings->{id} \n";
            $output .= "name: $dev_settings->{name} \n";
        }

        $hash->{helper}{debug_device_output} = $output;
        asyncOutput( $param->{cl}, $hash->{helper}{debug_device_output} );

        return;
    }
    readingsSingleUpdate( $hash, 'state', 'Connected', 1 )
      if ( defined( $hash->{helper}{locations_id} ) );
    ResponseProcessing( $hash, $data )
      if ( ref($decode_json) eq 'HASH' );

    return;
}

sub ResponseProcessing {
    my $hash = shift;
    my $json = shift;

    my $name = $hash->{NAME};

    my $decode_json = eval { decode_json($json) };
    if ($@) {
        Log3 $name, 3,
          "GardenaSmartBridge ($name) - JSON error while request: $@";

        if ( AttrVal( $name, 'debugJSON', 0 ) == 1 ) {
            readingsBeginUpdate($hash);
            readingsBulkUpdate( $hash, 'JSON_ERROR',        $@,    1 );
            readingsBulkUpdate( $hash, 'JSON_ERROR_STRING', $json, 1 );
            readingsEndUpdate( $hash, 1 );
        }
    }

    if (   defined( $decode_json->{data} )
        && $decode_json->{data}
        && ref( $decode_json->{data} ) eq 'HASH'
        && !defined( $hash->{helper}->{user_id} ) )
    {

        $hash->{helper}{session_id} = $decode_json->{data}{id};
        $hash->{helper}{user_id} = $decode_json->{data}{attributes}->{user_id};
        $hash->{helper}{refresh_token} =
          $decode_json->{data}{attributes}->{refresh_token};
        $hash->{helper}{token_expired} =
          gettimeofday() + $decode_json->{data}{attributes}->{expires_in};

        InternalTimer( $hash->{helper}{token_expired},
            "FHEM::GardenaSmartBridge::getToken", $hash );

        Write( $hash, undef, undef, undef );
        Log3 $name, 3, "GardenaSmartBridge ($name) - fetch locations id";
        readingsSingleUpdate( $hash, 'token', $hash->{helper}{session_id}, 1 );

        return;

    }
    elsif ( !defined( $hash->{helper}{locations_id} )
        && defined( $decode_json->{locations} )
        && ref( $decode_json->{locations} ) eq 'ARRAY'
        && scalar( @{ $decode_json->{locations} } ) > 0 )
    {
        for my $location ( @{ $decode_json->{locations} } ) {

            $hash->{helper}{locations_id} = $location->{id};

            WriteReadings( $hash, $location );
        }

        Log3 $name, 3,
          "GardenaSmartBridge ($name) - processed locations id. ID is "
          . $hash->{helper}{locations_id};
        Write( $hash, undef, undef, undef );

        return;
    }
    elsif (defined( $decode_json->{devices} )
        && ref( $decode_json->{devices} ) eq 'ARRAY'
        && scalar( @{ $decode_json->{devices} } ) > 0 )
    {
        my @buffer = split( '"devices":\[', $json );

        require SubProcess;

        my $subprocess =
          SubProcess->new( { onRun => \&ResponseSubprocessing } );
        $subprocess->{buffer} = $buffer[1];

        my $pid = $subprocess->run();

        if ( !defined($pid) ) {
            Log3( $name, 1,
qq{GardenaSmartBridge ($name) - Cannot execute parse json asynchronously}
            );

            CleanSubprocess($hash);
            readingsSingleUpdate( $hash, 'state',
                'Cannot execute parse json asynchronously', 1 );
            return;
        }

        Log3( $name, 4,
qq{GardenaSmartBridge ($name) - execute parse json asynchronously (PID="$pid")}
        );

        $hash->{".fhem"}{subprocess} = $subprocess;

        InternalTimer( gettimeofday() + 1,
            "FHEM::GardenaSmartBridge::PollChild", $hash );

        return;
    }

    Log3 $name, 3, "GardenaSmartBridge ($name) - no Match for processing data";

    return;
}

sub ResponseProcessingFinalFromSubProcessing {
    my $hash     = shift;
    my $response = shift;

    my $name = $hash->{NAME};

    my @response = split '\|,', $response;

    Log3( $name, 4,
        qq{GardenaSmartBridge ($name) - got result from asynchronous parsing} );

    my $decode_json;

    Log3( $name, 4, qq{GardenaSmartBridge ($name) - asynchronous finished.} );

    if ( scalar(@response) > 0 ) {
        for my $json (@response) {

            #################
            $decode_json = eval { decode_json($json) };
            if ($@) {
                Log3 $name, 5,
                  "GardenaSmartBridge ($name) - JSON error while request: $@";
            }

            Dispatch( $hash, $json, undef )
              if ( $decode_json->{category} ne 'gateway' );
            WriteReadings( $hash, $decode_json )
              if ( defined( $decode_json->{category} )
                && $decode_json->{category} eq 'gateway' );
        }
    }

    return;
}

sub PollChild {
    my $hash = shift;

    my $name = $hash->{NAME};

    if ( defined( $hash->{".fhem"}{subprocess} ) ) {
        my $subprocess = $hash->{".fhem"}{subprocess};
        my $response   = $subprocess->readFromChild();

        if ( defined($response) ) {
            ResponseProcessingFinalFromSubProcessing( $hash, $response );
            $subprocess->wait();
            CleanSubprocess($hash);
        }

        Log3( $name, 4,
qq{GardenaSmartBridge ($name) - still waiting ($subprocess->{lasterror}).}
        );

        InternalTimer( gettimeofday() + 1,
            "FHEM::GardenaSmartBridge::PollChild", $hash );
        return;
    }

    return;
}

# ResponseSubprocessin muss in eine async ausgelagert werden
######################################
# Begin Childprozess
######################################
sub ResponseSubprocessing {
    my $subprocess = shift;
    my $buffer     = $subprocess->{buffer};
    my @response   = ();

    my ( $json, $tail ) = ParseJSON($buffer);

    while ($json) {
        if ( defined($tail) and $tail ) {
            push @response, $json;
        }

        ( $json, $tail ) = ParseJSON($tail);
    }

    $subprocess->writeToParent( join '|', @response );

    return;
}

sub ParseJSON {
    my $buffer = shift;

    my $open  = 0;
    my $close = 0;
    my $msg   = '';
    my $tail  = '';

    if ($buffer) {
        for my $c ( split //, $buffer ) {
            if ( $open == $close && $open > 0 ) {
                $tail .= $c;
            }
            else {

                if ( $c eq '{' ) {

                    $open++;

                }
                elsif ( $c eq '}' ) {

                    $close++;
                }

                $msg .= $c;
            }
        }

        if ( $open != $close ) {

            $tail = $msg;
            $msg  = '';
        }
    }

    return ( $msg, $tail );
}
######################################
# End Childprozess
######################################

sub CleanSubprocess {
    my $hash = shift;

    my $name = $hash->{NAME};

    delete( $hash->{".fhem"}{subprocess} );
    Log3( $name, 4, qq{GardenaSmartBridge ($name) - clean Subprocess} );
}

sub WriteReadings {
    my $hash        = shift;
    my $decode_json = shift;

    my $name = $hash->{NAME};

    if (   defined( $decode_json->{id} )
        && $decode_json->{id}
        && defined( $decode_json->{name} )
        && $decode_json->{name} )
    {
        readingsBeginUpdate($hash);
        if ( $decode_json->{id} eq $hash->{helper}{locations_id} ) {

            readingsBulkUpdateIfChanged( $hash, 'name', $decode_json->{name} );
            readingsBulkUpdateIfChanged( $hash, 'authorized_user_ids',
                scalar( @{ $decode_json->{authorized_user_ids} } ) );
            readingsBulkUpdateIfChanged( $hash, 'devices',
                scalar( @{ $decode_json->{devices} } ) );

            while ( ( my ( $t, $v ) ) = each %{ $decode_json->{geo_position} } )
            {
                $v = encode_utf8($v);
                readingsBulkUpdateIfChanged( $hash, $t, $v );
            }
        }
        elsif ($decode_json->{id} ne $hash->{helper}{locations_id}
            && ref( $decode_json->{abilities} ) eq 'ARRAY'
            && ref( $decode_json->{abilities}[0]{properties} ) eq 'ARRAY' )
        {
            my $properties =
              scalar( @{ $decode_json->{abilities}[0]{properties} } );

            do {
                while ( ( my ( $t, $v ) ) =
                    each
                    %{ $decode_json->{abilities}[0]{properties}[$properties] } )
                {
                    next
                      if ( ref($v) eq 'ARRAY' );

                    #$v = encode_utf8($v);
                    $v = ' ' if ( !defined $v );
                    Log3 $name, 4,
                      "Gardena DEBUG DEBUG DEBUG stage 1 "
                      . $decode_json->{abilities}[0]{properties}[$properties]
                      {name}
                      if ( $decode_json->{abilities}[0]{properties}[$properties]
                        {name} !~ /ethernet_status|wifi_status/ );
                    Log3 $name, 4, "Gardena DEBUG DEBUG DEBUG stage 2" . $t
                      if ( $decode_json->{abilities}[0]{properties}[$properties]
                        {name} !~ /ethernet_status|wifi_status/ );
                    Log3 $name, 4, "Gardena DEBUG DEBUG DEBUG stage 3" . $v
                      if ( $decode_json->{abilities}[0]{properties}[$properties]
                        {name} !~ /ethernet_status|wifi_status/ );

                    readingsBulkUpdateIfChanged(
                        $hash,
                        $decode_json->{abilities}[0]{properties}[$properties]
                          {name} . '-' . $t,
                        $v
                      )
                      if ( $decode_json->{abilities}[0]{properties}[$properties]
                        {name} !~ /ethernet_status|wifi_status/ );
                    if (
                        (
                            $decode_json->{abilities}[0]{properties}
                            [$properties]{name} eq 'ethernet_status'
                            || $decode_json->{abilities}[0]{properties}
                            [$properties]{name} eq 'wifi_status'
                        )
                        && ref($v) eq 'HASH'
                      )
                    {
                        if ( $v->{is_connected} ) {
                            readingsBulkUpdateIfChanged(
                                $hash,
                                $decode_json->{abilities}[0]{properties}
                                  [$properties]{name} . '-ip',
                                $v->{ip}
                            ) if ( ref( $v->{ip} ) ne 'HASH' );
                            readingsBulkUpdateIfChanged(
                                $hash,
                                $decode_json->{abilities}[0]{properties}
                                  [$properties]{name} . '-isconnected',
                                $v->{is_connected}
                            ) if ( $v->{is_connected} );
                        }
                    }    # fi ethernet and wifi
                }
                $properties--;

            } while ( $properties >= 0 );
        }
        readingsEndUpdate( $hash, 1 );
    }

    Log3 $name, 4, "GardenaSmartBridge ($name) - readings would be written";

    return;
}

####################################
####################################
#### my little helpers Sub's #######

sub getDevices {
    my $hash = shift;

    my $name = $hash->{NAME};
    RemoveInternalTimer( $hash, "FHEM::GardenaSmartBridge::getDevices" );

    if ( not IsDisabled($name) ) {

        delete $hash->{helper}{deviceList};
        my @list;
        @list = devspec2array('TYPE=GardenaSmartDevice');
        for my $gardenaDev (@list) {
            push( @{ $hash->{helper}{deviceList} }, $gardenaDev );
        }
        if ( AttrVal( $name, 'gardenaAccountEmail', 'none' ) ne 'none'
            && ( defined( ReadPassword( $hash, $name ) ) ) )
        {
            Write( $hash, undef, undef, undef );
            Log3 $name, 4,
"GardenaSmartBridge ($name) - fetch device list and device states";
        }    # fi gardenaAccountEmail
    }
    else {
        readingsSingleUpdate( $hash, 'state', 'disabled', 1 );
        Log3 $name, 3, "GardenaSmartBridge ($name) - device is disabled";
    }

    return;
}

sub getToken {
    my $hash = shift;

    my $name = $hash->{NAME};

    return readingsSingleUpdate( $hash, 'state',
        'please set Attribut gardenaAccountEmail first', 1 )
      if ( AttrVal( $name, 'gardenaAccountEmail', 'none' ) eq 'none' );
    return readingsSingleUpdate( $hash, 'state',
        'please set gardena account password first', 1 )
      if ( !defined( ReadPassword( $hash, $name ) ) );
    readingsSingleUpdate( $hash, 'state', 'get token', 1 );

    delete $hash->{helper}{session_id}
      if ( exists( $hash->{helper}{session_id} ) );
    delete $hash->{helper}{user_id}
      if ( exists( $hash->{helper}{user_id} ) );
    delete $hash->{helper}{locations_id}
      if ( exists( $hash->{helper}{locations_id} ) );

    Write(
        $hash,
        '"data":{"type":"token","attributes":{"username":"'
          . AttrVal( $name, 'gardenaAccountEmail', 'none' )
          . '","password":"'
          . ReadPassword( $hash, $name )
          . '","client_id":"smartgarden-jwt-client"}}',
        undef,
        undef
    );

    Log3 $name, 4,
        '"data": {"type":"token", "attributes":{"username":"'
      . AttrVal( $name, 'gardenaAccountEmail', 'none' )
      . '","password":"'
      . ReadPassword( $hash, $name )
      . '","client_id":"smartgarden-jwt-client"}}';
    Log3 $name, 3,
"GardenaSmartBridge ($name) - send credentials to fetch Token and locationId";

    return;
}

sub StorePassword {
    my $hash     = shift;
    my $name     = shift;
    my $password = shift;

    my $index   = $hash->{TYPE} . "_" . $name . "_passwd";
    my $key     = getUniqueId() . $index;
    my $enc_pwd = "";

    if ( eval "use Digest::MD5;1" ) {

        $key = Digest::MD5::md5_hex( unpack "H*", $key );
        $key .= Digest::MD5::md5_hex($key);
    }

    for my $char ( split //, $password ) {

        my $encode = chop($key);
        $enc_pwd .= sprintf( "%.2x", ord($char) ^ ord($encode) );
        $key = $encode . $key;
    }

    my $err = setKeyValue( $index, $enc_pwd );
    return "error while saving the password - $err" if ( defined($err) );

    return "password successfully saved";
}

sub ReadPassword {
    my $hash = shift;
    my $name = shift;

    my $index = $hash->{TYPE} . "_" . $name . "_passwd";
    my $key   = getUniqueId() . $index;
    my ( $password, $err );

    Log3 $name, 4, "GardenaSmartBridge ($name) - Read password from file";

    ( $err, $password ) = getKeyValue($index);

    if ( defined($err) ) {

        Log3 $name, 3,
"GardenaSmartBridge ($name) - unable to read password from file: $err";
        return;

    }

    if ( defined($password) ) {
        if ( eval "use Digest::MD5;1" ) {

            $key = Digest::MD5::md5_hex( unpack "H*", $key );
            $key .= Digest::MD5::md5_hex($key);
        }

        my $dec_pwd = '';

        for my $char ( map { pack( 'C', hex($_) ) } ( $password =~ /(..)/g ) ) {

            my $decode = chop($key);
            $dec_pwd .= chr( ord($char) ^ ord($decode) );
            $key = $decode . $key;
        }

        return $dec_pwd;

    }
    else {

        Log3 $name, 3, "GardenaSmartBridge ($name) - No password in file";
        return;
    }

    return;
}

sub Rename {
    my $new = shift;
    my $old = shift;

    my $hash = $defs{$new};

    StorePassword( $hash, $new, ReadPassword( $hash, $old ) );
    setKeyValue( $hash->{TYPE} . "_" . $old . "_passwd", undef );

    return;
}

sub createHttpValueStrings {
    my ( $hash, $payload, $deviceId, $abilities, $service_id ) = @_;

    my $session_id = $hash->{helper}{session_id};
    my $header = 'Content-Type: application/json';
    $header .= "\r\norigin: https://smart.gardena.com";
    $header .= "\r\nuser-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
    #my $header     = "Content-Type: application/json; origin: https://smart.gardena.com";
    my $uri        = '';
    my $method     = 'POST';
    $header .= "\r\nAuthorization: Bearer $session_id"
      if ( defined( $hash->{helper}{session_id} ) );
    $header .= "\r\nAuthorization-Provider: husqvarna"
      if ( defined( $hash->{helper}{session_id} ) );

    #  $header .= "\r\nx-api-key: $session_id"
    #    if ( defined( $hash->{helper}{session_id} ) );
    $payload = '{' . $payload . '}' if ( defined($payload) );
    $payload = '{}'                 if ( !defined($payload) );

    if ( $payload eq '{}' ) {
        $method  = 'GET' if ( defined( $hash->{helper}{session_id} ) );
        $payload = '';
        $uri .= '/locations?locatioId=null&user_id=' . $hash->{helper}{user_id}
          if ( exists( $hash->{helper}{user_id} )
            && !defined( $hash->{helper}{locations_id} ) );
        readingsSingleUpdate( $hash, 'state', 'fetch locationId', 1 )
          if ( exists( $hash->{helper}{user_id} )
            && !defined( $hash->{helper}{locations_id} ) );
        $uri .= '/devices'
          if (!defined($abilities)
            && defined( $hash->{helper}{locations_id} ) );
    }

    $uri =
      '/devices/' . InternalVal( $hash->{helper}{debug_device}, 'DEVICEID', 0 )
      if ( defined( $hash->{helper}{debug_device} )
        && defined( $hash->{helper}{locations_id} ) );
    $uri = '/auth/token' if ( !defined( $hash->{helper}{session_id} ) );

    if ( defined( $hash->{helper}{locations_id} ) ) {
        if ( defined($abilities) && $abilities =~ /.*_settings/ ) {

            $method = 'PUT';
            my $dhash = $modules{GardenaSmartDevice}{defptr}{$deviceId};

            $uri .= '/devices/' . $deviceId . '/settings/' . $service_id
              if ( defined($abilities)
                && defined($payload)
                && $abilities =~ /.*_settings/ );

        }    # park until next schedules or override
        elsif (defined($abilities)
            && defined($payload)
            && $abilities eq 'mower' )
        {
            my $valve_id;

            $uri .=
                '/devices/'
              . $deviceId
              . '/abilities/'
              . $abilities
              . '/commands/manual_start';

        }
        elsif (defined($abilities)
            && defined($payload)
            && $abilities eq 'watering' )
        {
            my $valve_id;

            if ( $payload =~ m#watering_timer_(\d)# ) {
                $method   = 'PUT';
                $valve_id = $1;
            }
            $uri .=
                '/devices/'
              . $deviceId
              . '/abilities/'
              . $abilities
              . (
                defined($valve_id)
                ? '/properties/watering_timer_' . $valve_id
                : '/command'
              );

        }
        elsif (defined($abilities)
            && defined($payload)
            && $abilities eq 'manual_watering' )
        {
            my $valve_id;
            $method = 'PUT';

            $uri .=
                '/devices/'
              . $deviceId
              . '/abilities/'
              . $abilities
              . '/properties/manual_watering_timer';

        }
        elsif (defined($abilities)
            && defined($payload)
            && $abilities eq 'watering_button_config' )
        {
            $method = 'PUT';

            $uri .=
                '/devices/'
              . $deviceId
              . '/abilities/watering'
              . '/properties/button_config_time';

        }
        elsif (defined($abilities)
            && defined($payload)
            && $abilities eq 'power' )
        {
            my $valve_id;
            $method = 'PUT';

            $uri .=
                '/devices/'
              . $deviceId
              . '/abilities/'
              . $abilities
              . '/properties/power_timer';

        }
        else {
            $uri .=
              '/devices/' . $deviceId . '/abilities/' . $abilities . '/command'
              if ( defined($abilities) && defined($payload) );
        }

        $uri .= '?locationId=' . $hash->{helper}{locations_id};
    }

    return ( $payload, $session_id, $header, $uri, $method, $deviceId,
        $abilities );
}

sub DeletePassword {
    my $hash = shift;

    setKeyValue( $hash->{TYPE} . "_" . $hash->{NAME} . "_passwd", undef );

    return;
}

1;

=pod

=item device
=item summary       Modul to communicate with the GardenaCloud
=item summary_DE    Modul zur Datenübertragung zur GardenaCloud

=begin html

<a name="GardenaSmartBridge"></a>
<h3>GardenaSmartBridge</h3>
<ul>
  <u><b>Prerequisite</b></u>
  <br><br>
  <li>In combination with GardenaSmartDevice this FHEM Module controls the communication between the GardenaCloud and connected Devices like Mover, Watering_Computer, Temperature_Sensors</li>
  <li>Installation of the following packages: apt-get install libio-socket-ssl-perl</li>
  <li>The Gardena-Gateway and all connected Devices must be correctly installed in the GardenaAPP</li>
</ul>
<br>
<a name="GardenaSmartBridgedefine"></a>
<b>Define</b>
<ul><br>
  <code>define &lt;name&gt; GardenaSmartBridge</code>
  <br><br>
  Beispiel:
  <ul><br>
    <code>define Gardena_Bridge GardenaSmartBridge</code><br>
  </ul>
  <br>
  The GardenaSmartBridge device is created in the room GardenaSmart, then the devices of Your system are recognized automatically and created in FHEM. From now on the devices can be controlled and changes in the GardenaAPP are synchronized with the state and readings of the devices.
  <br><br>
  <a name="GardenaSmartBridgereadings"></a>
  <br><br>
  <b>Readings</b>
  <ul>
    <li>address - your Adress (Longversion)</li>
    <li>authorized_user_ids - </li>
    <li>city - Zip, City</li>
    <li>devices - Number of Devices in the Cloud (Gateway included)</li>
    <li>lastRequestState - Last Status Result</li>
    <li>latitude - Breitengrad des Grundstücks</li>
    <li>longitude - Längengrad des Grundstücks</li>
    <li>name - Name of your Garden – Default „My Garden“</li>
    <li>state - State of the Bridge</li>
    <li>token - SessionID</li>
  </ul>
  <br><br>
  <a name="GardenaSmartBridgeset"></a>
  <b>set</b>
  <ul>
    <li>getDeviceState - Starts a Datarequest</li>
    <li>getToken - Gets a new Session-ID</li>
    <li>gardenaAccountPassword - Passwort which was used in the GardenaAPP</li>
    <li>deleteAccountPassword - delete the password from store</li>
  </ul>
  <br><br>
  <a name="GardenaSmartBridgeattributes"></a>
  <b>Attributes</b>
  <ul>
    <li>debugJSON - </li>
    <li>disable - Disables the Bridge</li>
    <li>interval - Interval in seconds (Default=180)</li>
    <li>gardenaAccountEmail - Email Adresse which was used in the GardenaAPP</li>
  </ul>
</ul>

=end html
=begin html_DE

<a name="GardenaSmartBridge"></a>
<h3>GardenaSmartBridge</h3>
<ul>
  <u><b>Voraussetzungen</b></u>
  <br><br>
  <li>Zusammen mit dem Device GardenaSmartDevice stellt dieses FHEM Modul die Kommunikation zwischen der GardenaCloud und Fhem her. Es k&ouml;nnen damit Rasenm&auml;her, Bew&auml;sserungscomputer und Bodensensoren überwacht und gesteuert werden</li>
  <li>Das Perl-Modul "SSL Packet" wird ben&ouml;tigt.</li>
  <li>Unter Debian (basierten) System, kann dies mittels "apt-get install libio-socket-ssl-perl" installiert werden.</li>
  <li>Das Gardena-Gateway und alle damit verbundenen Ger&auml;te und Sensoren m&uuml;ssen vorab in der GardenaApp eingerichtet sein.</li>
</ul>
<br>
<a name="GardenaSmartBridgedefine"></a>
<b>Define</b>
<ul><br>
  <code>define &lt;name&gt; GardenaSmartBridge</code>
  <br><br>
  Beispiel:
  <ul><br>
    <code>define Gardena_Bridge GardenaSmartBridge</code><br>
  </ul>
  <br>
  Das Bridge Device wird im Raum GardenaSmart angelegt und danach erfolgt das Einlesen und automatische Anlegen der Ger&auml;te. Von nun an k&ouml;nnen die eingebundenen Ger&auml;te gesteuert werden. &Auml;nderungen in der APP werden mit den Readings und dem Status syncronisiert.
  <br><br>
  <a name="GardenaSmartBridgereadings"></a>
  <br><br>
  <b>Readings</b>
  <ul>
    <li>address - Adresse, welche in der App eingetragen wurde (Langversion)</li>
    <li>authorized_user_ids - </li>
    <li>city - PLZ, Stadt</li>
    <li>devices - Anzahl der Ger&auml;te, welche in der GardenaCloud angemeldet sind (Gateway z&auml;hlt mit)</li>
    <li>lastRequestState - Letzter abgefragter Status der Bridge</li>
    <li>latitude - Breitengrad des Grundst&uuml;cks</li>
    <li>longitude - Längengrad des Grundst&uuml;cks</li>
    <li>name - Name für das Grundst&uuml;ck – Default „My Garden“</li>
    <li>state - Status der Bridge</li>
    <li>token - SessionID</li> 
  </ul>
  <br><br>
  <a name="GardenaSmartBridgeset"></a>
  <b>set</b>
  <ul>
    <li>getDeviceState - Startet eine Abfrage der Daten.</li>
    <li>getToken - Holt eine neue Session-ID</li>
    <li>gardenaAccountPassword - Passwort, welches in der GardenaApp verwendet wurde</li>
    <li>deleteAccountPassword - l&oml;scht das Passwort aus dem Passwortstore</li>
  </ul>
  <br><br>
  <a name="GardenaSmartBridgeattributes"></a>
  <b>Attribute</b>
  <ul>
    <li>debugJSON - JSON Fehlermeldungen</li>
    <li>disable - Schaltet die Datenübertragung der Bridge ab</li>
    <li>interval - Abfrageinterval in Sekunden (default: 180)</li>
    <li>gardenaAccountEmail - Email Adresse, die auch in der GardenaApp verwendet wurde</li>
  </ul>
</ul>

=end html_DE

=for :application/json;q=META.json 73_GardenaSmartBridge.pm
{
  "abstract": "Modul to communicate with the GardenaCloud",
  "x_lang": {
    "de": {
      "abstract": "Modul zur Datenübertragung zur GardenaCloud"
    }
  },
  "keywords": [
    "fhem-mod-device",
    "fhem-core",
    "Garden",
    "Gardena",
    "Smart"
  ],
  "release_status": "stable",
  "license": "GPL_2",
  "version": "v2.6.3",
  "author": [
    "Marko Oldenburg <fhemdevelopment@cooltux.net>"
  ],
  "x_fhem_maintainer": [
    "CoolTux"
  ],
  "x_fhem_maintainer_github": [
    "LeonGaultier"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.016, 
        "Meta": 0,
        "IO::Socket::SSL": 0,
        "JSON": 0,
        "HttpUtils": 0,
        "Encode": 0
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  }
}
=end :application/json;q=META.json

=cut
