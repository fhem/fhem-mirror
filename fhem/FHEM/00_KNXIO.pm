## no critic (Modules::RequireVersionVar) ######################################
# $Id$
# base module for KNX-communication
# idea: merge some functions of TUL- & KNXTUL-module into one and add more connectivity 
# function: M - multicast support (like in KNXTUL) - connect to knxd or KNX-router
#           T - tunnel (like TCP-mode of TUL) - connect to knxd
#           S - Socket mode - connect to unix-socket of knxd on localhost
#           H - unicast udp - connect to knxd or KNX-router
#           X - dummy mode as placeholder for FHEM2FHEM-IO 
# will never be supported: direct USB-connection to a TUL-USB-stick ( use TUL-Modul or use KNXD->USBstick)
# features: use DevIo where possible
#           use TcpServerUtils for multicast
#           FIFO - queing of incoming messages (less latency for fhem-system) read= ~4ms vs ~34ms with KNXTUL/TUL
#           discard duplicate incoming messages
#           more robust parser of incoming messages
################################################################################
### changelog:
# 19/10/2021 01.60 initial beta version
#            enable hostnames for mode H & T
# 05/11/2021 fix 'x' outside of string in unpack at ./FHEM/00_KNXIO.pm line 420 (Connection response)
# 30/11/2021 add long text to errorlist
#            add Log msg on invalid/discarded frames
# 15/12/2021 01.70 changed acpi decoding in cemi
#            add keepalive for mode-H
#            add support for FHEM2FHEM (mode X)
#            fix reopen on knxd crash/restart
# 28/02/2022 change MC support to TcpServerUtils - no need for IO::Socket::Multicast Module!
#            modified phyaddr internal- removed phyaddrnum
#            moved all hidden internals to $hash->{KNXIOhelpers}->{...}
# 31/03/2022 fixed typo on line 1106 (exits -> exists)
# 25/04/2022 changed 'state connected' logic (issue after handshake complete...)
# 25/05/2022 first SVN version
# 07/07/2022 cleanup, no functional changes
# 09/07/2022 fix IOdevice ready check on set-cmd (KNXIO_write)
# 01/09/2022 cleanup, simplify duplicate detection, perf improvements
#            unify Log msgs
# 13/11/2022 modify fifo logic
#            improve cmd-ref
# 05/12/2022 change parameter parsing in define
#            add renameFn - correct reading & attr IODev in KNX-devices after rename of KNXIO-device
#            change disabled handling
#            fix src-addr for Mode M,H
#            change internal PhyAddr to reabable format + range checking on define.
# 19/12/2022 cleanup
# 23/01/2023 cleanup, simplify _openDev
# 13/03/2023 PBP changes
#            replace cascading if..elsif with given
#            replace GP_Import: Devio,Tcpserver,HttpUtils with use stmts   
# 28/03/2023 cleanup
#            rework Logging, duplicate msg detection
# 04/04/2023 limit retries for keepalive timeouts
#            rework Logging
# 15/05/2023 new "<device>:INITIALIZED" event after sucessful start
#            change (shorten) timeout parameters on disconnect
#            cmd-ref: correct wiki links, W3C conformance
# xx/06/2023 move cmd KNX_scan from KNX- to KNXIO-Module
#            extra delay on KNX_scan after each 10th request
#            new attr enableKNXscan - trigger KNX_scan on startup and/or on every connect
#            update cmd-ref


package KNXIO; ## no critic 'package'

use strict;
use warnings;
use IO::Socket;
use English qw(-no_match_vars);
use Time::HiRes qw(gettimeofday);
use DevIo qw(DevIo_OpenDev DevIo_SimpleWrite DevIo_SimpleRead DevIo_CloseDev DevIo_Disconnected DevIo_IsOpen);
use TcpServerUtils qw(TcpServer_Open TcpServer_SetLoopbackMode TcpServer_MCastAdd TcpServer_MCastRemove 
    TcpServer_MCastSend TcpServer_MCastRecv TcpServer_Close);
use HttpUtils qw(HttpUtils_gethostbyname HttpUtils_gethostbyname ip2str);
use feature qw(switch);
no if $] >= 5.017011, warnings => 'experimental';
use GPUtils qw(GP_Import GP_Export); # Package Helper Fn

### perlcritic parameters
# these ones are NOT used! (constants,Policy::Modules::RequireFilenameMatchesPackage,NamingConventions::Capitalization)
# these ones are NOT used! (RegularExpressions::RequireDotMatchAnything,RegularExpressions::RequireLineBoundaryMatching)
# these ones are NOT used! (ControlStructures::ProhibitCascadingIfElse)
### the following percritic items will be ignored global ###
## no critic (ValuesAndExpressions::RequireNumberSeparators,ValuesAndExpressions::ProhibitMagicNumbers)
## no critic (ControlStructures::ProhibitPostfixControls)
## no critic (Documentation::RequirePodSections)

### import FHEM functions / global vars
### run before package compilation
BEGIN {
    # Import from main context
    GP_Import(
        qw(readingsSingleUpdate readingsBulkUpdate readingsBulkUpdateIfChanged readingsBeginUpdate readingsEndUpdate
          Log3
          AttrVal AttrNum ReadingsVal ReadingsNum
          AssignIoPort IOWrite
          CommandDefine CommandDelete CommandModify CommandDefMod
          DoTrigger
          Dispatch
          defs modules attr cmds
          readingFnAttributes
          selectlist readyfnlist 
          InternalTimer RemoveInternalTimer
          init_done
          IsDisabled IsDummy IsDevice
          devspec2array
          AnalyzePerlCommand EvalSpecials
          TimeNow)
    );
}

# export to main context
GP_Export(qw(Initialize ) );

#####################################
# global vars/constants
my $MODELERR = 'MODEL_NOT_DEFINED';
my $PAT_IP   = '[\d]{1,3}(\.[\d]{1,3}){3}';
my $PAT_PORT = '[\d]{4,5}';
my $KNXID    = 'C';
my $reconnectTO = 10; # Waittime after disconnect
my $SVNID    = '$Id$';

#####################################
sub Initialize {
	my $hash = shift;
	$hash->{DefFn}      = \&KNXIO_Define;
	$hash->{AttrFn}     = \&KNXIO_Attr;
	$hash->{ReadFn}     = \&KNXIO_Read;
	$hash->{ReadyFn}    = \&KNXIO_Ready;
	$hash->{WriteFn}    = \&KNXIO_Write;
	$hash->{RenameFn}   = \&KNXIO_Rename;
	$hash->{UndefFn}    = \&KNXIO_Undef;
	$hash->{ShutdownFn} = \&KNXIO_Shutdown;

	$hash->{AttrList}   = 'disable:1 verbose:1,2,3,4,5 enableKNXscan:0,1,2';
	$hash->{Clients}    = 'KNX';
	$hash->{MatchList}  = { '1:KNX' => '^C.*' };

	# register KNX_scan cmd (use from cmd-line)
	$cmds{KNX_scan} = { Fn  => 'KNX_scancmd', Hlp => '[<devspec>] request values from KNX-Hardware. Use "help KNX" for more help'};

	return;
}

#####################################
### syntax: define <name> KNXIO <mode one of: M|S|H|T|X)> <hostip or hostname>:<port> <phy-address>
sub KNXIO_Define {
	my $hash = shift;
	my $def  = shift;

	my @arg = split(/[\s\t\n]+/xms,$def);
	my $name = $arg[0] // return 'KNXIO-define: no name specified';
	$hash->{NAME} = $name;
	$SVNID =~ s/.*\.pm\s([^\s]+\s[^\s]+).*/$1/ixms;
	$hash->{SVN} = $SVNID; # store svn info in dev hash

	return q{KNXIO-define: invalid mode specified, valid modes are one of: H M S T X} if ((scalar(@arg) >= 3) && $arg[2] !~ /[HMSTX]/ixms);

	my $mode = $arg[2];
	$hash->{model} = $mode; # use it also for fheminfo statistics

	# handle mode X for FHEM2FHEM configs
	return InternalTimer(gettimeofday() + 0.2,\&KNXIO_openDev,$hash) if ($mode eq q{X});

	return q{KNXIO-define syntax: "define <name> KNXIO <H|M|T> <ip-address|hostname>:<port> <phy-adress>" } . "\n" . 
               q{         or          "define <name> KNXIO S <pathToUnixSocket> <phy-address>" } if (scalar(@arg) < 5);

	my ($host,$port) = split(/[:]/ixms,$arg[3]);

	return q{KNXIO-define: invalid ip-address or port, correct syntax is: } .
               q{"define <name> KNXIO <H|M|T> <ip-address|name>:<port> <phy-address>"} if ($mode =~ /[MHT]/ixms && $port !~ /$PAT_PORT/ixms);

	if ($mode eq q{M}) { # multicast
		my $host1 = (split(/\./ixms,$host))[0];
		return q{KNXIO-define: Multicast address is not in the range of 224.0.0.0 and 239.255.255.255 } .
                       q{(default is 224.0.23.12:3671) } if ($host1 < 224 || $host1 > 239);
		$hash->{DeviceName} = $host . q{:} . $port;
	}
	elsif ($mode eq q{S}) {
		$hash->{DeviceName} = 'UNIX:STREAM:' . $host; # $host= path to socket 
	}
	elsif ($mode =~ m/[HT]/ixms) {
		if ($host !~ /$PAT_IP/ixms) { # not an ip-address, lookup name
=pod
			# blocking variant !
			my $phost = inet_aton($host);
			return "KNXIO-define: host name $host could not be resolved" if (! defined($phost));
			$host = inet_ntoa($phost);
			return "KNXIO-define: host name could not be resolved" if (! defined($host));
=cut
			# do it non blocking! - use HttpUtils to resolve hostname
			$hash->{PORT} = $port; # save port...
			$hash->{timeout} = 5; # TO for DNS req.
			$hash->{DNSWAIT} = 1;
			my $KNXIO_DnsQ = ::HttpUtils_gethostbyname($hash,$host,1,\&KNXIO_gethostbyname_Cb);
		}

		else {
			$hash->{DeviceName} = $host . q{:} . $port; # for DevIo
		}
	}

	my $phyaddr = (defined($arg[4]))?$arg[4]:'0.0.0'; 
	my $phytemp = KNXIO_hex2addr($phyaddr); 
	$hash->{PhyAddr} = KNXIO_addr2hex($phytemp,2); #convert 2 times for correcting input!

	KNXIO_closeDev($hash) if ($init_done && exists($hash->{OLDDEF})); # modify definition....

	$hash->{devioLoglevel} = 4; #032023
	$hash->{devioNoSTATE}  = 1;

	$hash->{PARTIAL} = q{};
	# define helpers
	$hash->{KNXIOhelper}->{FIFO}      = []; # read fifo array
	$hash->{KNXIOhelper}->{FIFOTIMER} = 0;
	$hash->{KNXIOhelper}->{FIFOMSG}   = q{};

	# Devio-parameters
	$hash->{nextOpenDelay} = $reconnectTO;

	delete $hash->{NEXT_OPEN};
	RemoveInternalTimer($hash);

	KNXIO_Log ($name, 3, qq{opening mode=$mode});

	if (! $init_done) {
		return InternalTimer(gettimeofday() + 0.2,\&KNXIO_openDev,$hash);
	}
	return KNXIO_openDev($hash);
}

#####################################
sub KNXIO_Attr {
	my ($cmd,$name,$aName,$aVal) = @_;
	my $hash = $defs{$name};
	if ($aName eq 'disable') {
		if ($cmd eq 'set' && defined($aVal) && $aVal == 1) {
			KNXIO_closeDev($hash);
		} else {
			InternalTimer(gettimeofday() + 0.2,\&KNXIO_openDev,$hash);
		}
	}
	elsif ($cmd eq 'set' && $aName eq 'enableKNXscan' && defined($aVal) && $aVal !~ /[0-2]/xms) {
		return 'Allowed values: 0-2';
	}
	return;
}

#####################################
sub KNXIO_Read {
	my $hash = shift;
#	my $local = shift; #?

	my $name = $hash->{NAME};
	my $mode = $hash->{model};

	return if IsDisabled($name);

	my $buf = undef;
	if ($mode eq 'M') {
		my ($rhost,$rport) = ::TcpServer_MCastRecv($hash, $buf, 1024);
	} else {
		$buf = ::DevIo_SimpleRead($hash);
	}
	if (!defined($buf) || length($buf) == 0) {
		KNXIO_Log ($name, 1, q{no data - disconnect});
		KNXIO_disconnect($hash);
		return;
	}

	KNXIO_Log ($name, 5, 'buf=' . unpack('H*',$buf));

	### process in indiv. subs
	my $readmodes = {
               H => \&KNXIO_ReadH,
               S => \&KNXIO_ReadST,
               T => \&KNXIO_ReadST,
               M => \&KNXIO_ReadM,
	};

	if (ref $readmodes->{$mode} eq 'CODE') {
		$readmodes->{$mode}->($hash, $buf);
		return;
	}

	KNXIO_Log ($name, 2, qq{failed - invalid mode $mode specified});
	return;
}

### Socket & Tunnel read
sub KNXIO_ReadST {
	my $hash = shift;
	my $buf  = shift;
	my $name = $hash->{NAME};

	$hash->{PARTIAL} .= $buf;
	my $msglen = unpack('n',$hash->{PARTIAL}) + 2;

	return if (length($hash->{PARTIAL}) < $msglen); # not enough data

	# buf complete, continue
	my @que = [];
	@que = @{$hash->{KNXIOhelper}->{FIFO}} if (defined($hash->{KNXIOhelper}->{FIFO}) && ($hash->{KNXIOhelper}->{FIFO} ne q{})); #get que from hash
	while (length($hash->{PARTIAL}) >= $msglen) {
		$buf = substr($hash->{PARTIAL},0,$msglen); # get one msg from partial
		$hash->{PARTIAL} = substr($hash->{PARTIAL}, $msglen); # put rest to partial

		my $outbuf = KNXIO_decodeEMI($hash,$buf);
		if ( defined($outbuf) ) {
			push(@que,$outbuf); # only valid packets!
		}
		if (length($hash->{PARTIAL}) >= 2) {
			$msglen = unpack('n',$hash->{PARTIAL}) + 2;
		}
	} # /while
	@{$hash->{KNXIOhelper}->{FIFO}} = @que; # push que to fifo
	return KNXIO_processFIFO($hash);
}

### multicast read
sub KNXIO_ReadM {
	my $hash = shift;
	my $buf  = shift;
	my $name = $hash->{NAME};

	$buf = $hash->{PARTIAL} . $buf if (defined($hash->{PARTIAL}));
	if (length($buf) < 6) { # min required for first unpack
		$hash->{PARTIAL} = $buf;
		return;
	}

	# header format: 0x06 - header size / 0x10 - KNXNET-IPVersion / 0x0530 - Routing Indicator / 0xYYYY - Header size + size of cEMIFrame
	my ($header, $header_routing, $total_length) = unpack('nnn',$buf);

	KNXIO_Log ($name, 5, 'header=' . sprintf('%04x',$header) . ' routing=' . sprintf('%04x',$header_routing) . 
              qq{ TotalLength= $total_length (dezimal)});

	if ($header != 0x0610 ) {
		KNXIO_Log ($name, 1, 'invalid header size or version');
		$hash->{PARTIAL} = undef; # delete all we have so far
#		KNXIO_disconnect($hash); #?
		return;
	}
	if (length($buf) < $total_length) {  #  6 Byte header + min 11 Byte data
		KNXIO_Log ($name,4, 'still waiting for complete packet (short packet length)');
		$hash->{PARTIAL} = $buf; # still not enough
		return;
	}
	else {
		$hash->{PARTIAL} = substr($buf,$total_length);
		$buf = substr($buf,0,$total_length);
	}

	##### now, the buf is complete check if routing-Frame
	if (($header_routing == 0x0530) && ($total_length >= 17)) {  #  6 Byte header + min 11 Byte data
		# this is the correct frame type, process it now
		$buf = substr($buf,6); # strip off header
		my $cemiRes = KNXIO_decodeCEMI($hash,$buf);
		return KNXIO_dispatch($hash,$cemiRes) if (defined($cemiRes));
		return;
	}
	elsif ($header_routing == 0x0531) { # routing Lost Message
		KNXIO_Log ($name, 3, 'a routing-lost packet was received !!! - Problems with bus or KNX-router ???');
	}
	elsif ($header_routing == 0x0201) { # search request
		KNXIO_Log ($name, 4, 'a search-request packet was received');
	}
	else {
		KNXIO_Log ($name, 4, q{a packet with unsupported service type } .
                      sprintf('%04x',$header_routing) . q{ was received. - discarded});
	}
	return;
} # /multicast

#####################################
### host mode read
# packet 06 10 0206 0014 02 00 08 01 c0a8 0ae8 0e 57 04 04 00f7 - conn response: 0014 - total len / 02 - commchannel / 00 - statusoode / 08 - struc-len / 01 protocol=UDP IPV4 / xxxx xxxx - IP & port /
# packet 06 10 0209 0010 02 01 08 01 c0a8 0ae8 0e 57 - disconn requ!
# header format: 0x06 - header size / 0x10 - KNXNET-IPVersion / 0x0201 - type / 08 - struct length / 01 - protocol=UDP IPV4 / size of cEMIFrame
sub KNXIO_ReadH {
	my $hash = shift;
	my $buf  = shift;

	my $name = $hash->{NAME};

	if ( unpack('n',$buf) != 0x0610) {
		KNXIO_Log ($name, 3, 'invalid Frame Header received - discarded');
		return;
	}

	my $msg = undef; # holds data to send
	my $ccid = 0;
	my $rxseqcntr = 0;
	my $txseqcntr = 0;
	my $errcode = 0;
	my $responseID = unpack('x2n',$buf);

	given ($responseID) {
		# handle most frequent id's first
		when (0x0420) { # Tunnel request
			($ccid,$rxseqcntr) = unpack('x7CC',$buf);

			my $discardFrame = undef;
			if ($rxseqcntr == ($hash->{KNXIOhelper}->{SEQUENCECNTR} - 1)) {
				KNXIO_Log ($name, 3, q{TunnelRequest received: duplicate message received } .
                                      qq{(seqcntr= $rxseqcntr ) - ack it});
				$hash->{KNXIOhelper}->{SEQUENCECNTR}--; # one packet duplicate... we ack it but do not process
				$discardFrame = 1;
			}
			if ($rxseqcntr != $hash->{KNXIOhelper}->{SEQUENCECNTR}) { # really out of sequence
				KNXIO_Log ($name, 3, q{TunnelRequest received: out of sequence, } .
                                      qq{(seqcntrRx= $rxseqcntr seqcntrTx= $hash->{KNXIOhelper}->{SEQUENCECNTR} ) - no ack & discard});
				return;
			}
			KNXIO_Log ($name, 4, q{TunnelRequest received - send Ack and decode. } .
                              qq{seqcntrRx= $hash->{KNXIOhelper}->{SEQUENCECNTR}} ) if (! defined($discardFrame));
			my $tacksend = pack('nnnCCCC',0x0610,0x0421,10,4,$ccid,$hash->{KNXIOhelper}->{SEQUENCECNTR},0); # send ack
			$hash->{KNXIOhelper}->{SEQUENCECNTR}++;
			$hash->{KNXIOhelper}->{SEQUENCECNTR} = 0 if ($hash->{KNXIOhelper}->{SEQUENCECNTR} > 255);
			::DevIo_SimpleWrite($hash,$tacksend,0);
			return if ($discardFrame); # duplicate frame

			#now decode & send to clients 
			$buf = substr($buf,10); # strip off header (10 bytes)
			my $cemiRes = KNXIO_decodeCEMI($hash,$buf);
			return if (! defined($cemiRes));
			return KNXIO_dispatch($hash,$cemiRes);
		}
		when (0x0421) { # Tunneling Ack
			($ccid,$txseqcntr,$errcode) = unpack('x7CCC',$buf);
			if ($errcode > 0) {
				KNXIO_Log ($name, 3, qq{Tunneling Ack received CCID= $ccid txseq= $txseqcntr Status= } . KNXIO_errCodes($errcode));
#what next ?
			}
			$hash->{KNXIOhelper}->{SEQUENCECNTR_W}++;
			$hash->{KNXIOhelper}->{SEQUENCECNTR_W} = 0 if ($hash->{KNXIOhelper}->{SEQUENCECNTR_W} > 255);
			return RemoveInternalTimer($hash,\&KNXIO_TunnelRequestTO); # all ok, stop timer
		}
		when (0x0202) { # Search response
			KNXIO_Log ($name, 4, 'SearchResponse received');
			my (@contolpointIp, $controlpointPort) = unpack('x6CCCn',$buf);
			return;
		}
		when (0x0204) { # Decription response
			KNXIO_Log ($name, 4, 'DescriptionResponse received');
			return;
		}
		when (0x0206) { # Connection response
			($hash->{KNXIOhelper}->{CCID},$errcode) = unpack('x6CC',$buf); # save Comm Channel ID,errcode
			RemoveInternalTimer($hash,\&KNXIO_keepAlive);
			if ($errcode > 0) {
				KNXIO_Log ($name, 3, q{ConnectionResponse received } .
                                      qq{CCID= $hash->{KNXIOhelper}->{CCID} Status=} . KNXIO_errCodes($errcode));
				KNXIO_disconnect($hash,2);
				return;
			}
			my $phyaddr = unpack('x18n',$buf);
			$hash->{PhyAddr} = KNXIO_addr2hex($phyaddr,2); # correct Phyaddr.

			KNXIO_handleConn($hash);
			KNXIO_Log ($name, 3, q{connected});
			$hash->{KNXIOhelper}->{SEQUENCECNTR} = 0;
			return InternalTimer(gettimeofday() + 60, \&KNXIO_keepAlive, $hash); # start keepalive
		}
		when (0x0208) { # ConnectionState response
			($hash->{KNXIOhelper}->{CCID}, $errcode) = unpack('x6CC',$buf); 
			RemoveInternalTimer($hash,\&KNXIO_keepAlive);
			RemoveInternalTimer($hash,\&KNXIO_keepAliveTO); # reset timeout timer
			if ($errcode > 0) {
				KNXIO_Log ($name, 3, q{ConnectionStateResponse received } .
                                      qq{CCID= $hash->{KNXIOhelper}->{CCID} Status= } . KNXIO_errCodes($errcode));
				KNXIO_disconnect($hash,2);
				return;
			}
			return InternalTimer(gettimeofday() + 60, \&KNXIO_keepAlive, $hash);
		}
		when (0x0209) { # Disconnect request
			KNXIO_Log ($name, 4, ' DisconnectRequest received, restarting connection');
			$ccid = unpack('x6C',$buf); 
			$msg = pack('nnnCC',(0x0610,0x020A,8,$ccid,0));
			::DevIo_SimpleWrite($hash,$msg,0); # send disco response 
			$msg = KNXIO_prepareConnRequ($hash);
		}
		when (0x020A) { # Disconnect response
			KNXIO_Log ($name, 4, 'DisconnectResponse received - sending connrequ');
			$msg = KNXIO_prepareConnRequ($hash);
		}
		default {
			KNXIO_Log ($name, 3, 'invalid response received: ' . unpack('H*',$buf));
			return;
		}
	}
	::DevIo_SimpleWrite($hash,$msg,0) if(defined($msg)); # send msg
	return;
}

#####################################
sub KNXIO_Ready {
	my $hash = shift;
	my $name = $hash->{NAME};

	return if (! $init_done || exists($hash->{DNSWAIT}) || IsDisabled($name) == 1);
	return if (exists($hash->{NEXT_OPEN}) && $hash->{NEXT_OPEN} > gettimeofday()); # avoid open loop 
	return KNXIO_openDev($hash) if (ReadingsVal($name, 'state', 'disconnected') ne 'connected');
	return;
}

#####################################
sub KNXIO_Write {
	my $hash = shift;
	my $fn   = shift;
	my $msg  = shift;

	my $name = $hash->{NAME};
	my $mode = $hash->{model};

	KNXIO_Log ($name, 5, 'started');
	return if(!defined($fn) && $fn ne $KNXID);
	if (ReadingsVal($name, 'state', 'disconnected') ne 'connected') {
		KNXIO_Log ($name, 3, qq{called while not connected! Msg: $msg lost});
		return;
	}

	KNXIO_Log ($name, 5, qq{sending $msg});

	my $acpivalues = {r => 0x00, p => 0x01, w => 0x02};

	if ($msg =~ /^([rwp])([0-9a-f]{5})(.*)$/ixms) { # msg format: <rwp><grpaddr><message>
		my $acpi = $acpivalues->{$1}<<6;
#		my $tcf  = ($acpivalues->{$1}>>2 & 0x03); # not needed!
		my $dst = KNXIO_hex2addr($2);
		my $str = $3;
		my $src = KNXIO_hex2addr($hash->{PhyAddr});

		#convert hex-string to array with dezimal values
		my @data =  map {hex()} $str =~ /(..)/xgms; # PBP 9/2021
		$data[0] = 0 if (scalar(@data) == 0); # in case of read !!
		my $datasize = scalar(@data);

		if ($datasize == 1) {
			$data[0] = ($data[0] & 0x3F) | $acpi;
		}
		else {
			$data[0] = $acpi;
		}

		KNXIO_Log ($name, 5, q{data=} . sprintf('%02x' x scalar(@data), @data) . 
                      sprintf(' size=%02x acpi=%02x', $datasize, $acpi) .
                      q{ src=} . KNXIO_addr2hex($src,2) . q{ dst=} . KNXIO_addr2hex($dst,3));
		my $completemsg = q{};
		my $ret = 0;

		if ($mode =~ /^[ST]$/ixms ) {  #format: size | 0x0027 | dst | 0 | data
			$completemsg = pack('nnnCC*',$datasize + 5,0x0027,$dst,0,@data);
		}
		elsif ($mode eq 'M') {
			$completemsg = pack('nnnnnnnCCC*',0x0610,0x0530,$datasize + 16,0x2900,0xBCE0,$src,$dst,$datasize,0,@data); # use src addr
			$ret = ::TcpServer_MCastSend($hash,$completemsg);
		}
		else { # $mode eq 'H'
			# total length= $size+20 - include 2900BCEO,src,dst,size,0
			$completemsg = pack('nnnCC',0x0610,0x0420,$datasize + 20,4,$hash->{KNXIOhelper}->{CCID}) .
                                       pack('CCnnnnCCC*',$hash->{KNXIOhelper}->{SEQUENCECNTR_W},0,0x1100,0xBCE0,$src,$dst,$datasize,0,@data); # send TunnelInd

			# Timeout function - expect TunnelAck within 1 sec! - but if fhem has a delay....
			$hash->{KNXIOhelper}->{LASTSENTMSG} = $completemsg; # save msg for resend in case of TO
			InternalTimer(gettimeofday() + 1.5, \&KNXIO_TunnelRequestTO, $hash);
		}

		$ret = ::DevIo_SimpleWrite($hash,$completemsg,0) if ($mode ne 'M');
		KNXIO_Log ($name, 4, qq{Mode= $mode buf=} . unpack('H*',$completemsg) . qq{ rc= $ret});
		return;
	}
	KNXIO_Log ($name, 2, qq{Could not send message $msg});
	return;
}

#####################################
## a FHEM-rename changes the internal IODev of KNX-dev's,
## but NOT the reading IODev & attr IODev
## both reading and attr will be changed here!
sub KNXIO_Rename {
	my $newname = shift;
	my $oldname = shift;

	if (! IsDevice($newname,'KNXIO')) {
		KNXIO_Log ($oldname, 1, qq{$newname is not a KNXIO device!});
		return;
	}
	KNXIO_Log ($oldname, 3, qq{device $oldname renamed to $newname});

	#check if any reading IODev has still the old KNXIO name...
	my @KNXdevs = devspec2array('TYPE=KNX:FILTER=r:IODev=' . $oldname);
	foreach my $KNXdev (@KNXdevs) {
		next if (! IsDevice($KNXdev)); # devspec error!
		readingsSingleUpdate($defs{$KNXdev},'IODev',$newname,0);
		my $logtxt = qq{reading IODev -> $newname};
		if (AttrVal($KNXdev,'IODev',q{}) eq $oldname) {
			delete ($attr{$KNXdev}->{IODev});
			$logtxt .= qq{, attr IODev -> deleted!};
		}
		KNXIO_Log ($KNXdev, 3, qq{device change: $logtxt});
	}
	return;
}

#####################################
sub KNXIO_Undef {
	my $hash = shift;

	return KNXIO_Shutdown($hash);
}

###################################
sub KNXIO_Shutdown {
	my $hash = shift;

	return KNXIO_closeDev($hash);
}

###################################
### functions called from DevIo ###
###################################

### return from open (sucess/failure)
sub KNXIO_callback {
	my $hash = shift;
	my $err = shift;

	$hash->{nextOpenDelay} = $reconnectTO; 
	if (defined($err)) {
		KNXIO_Log ($hash, 2, qq{device open $hash->{NAME} failed with: $err}) if ($err);
		$hash->{NEXT_OPEN} = gettimeofday() + $hash->{nextOpenDelay};
	}
	return;
}

###################################
######## private functions ########
###################################

### called from define-HttpUtils_gethostbynam when hostname needs to be resolved
### process callback from HttpUtils_gethostbyname
sub KNXIO_gethostbyname_Cb {
	my $hash  = shift;
	my $error = shift;
	my $dhost = shift;

	my $name  = $hash->{NAME};
	delete $hash->{timeout};
	delete $hash->{DNSWAIT};
	if ($error) {
		delete $hash->{DeviceName};
		delete $hash->{PORT};
		KNXIO_Log ($name, 1, qq{hostname could not be resolved: $error});
		return  qq{KNXIO-define: hostname could not be resolved: $error};
	}
	my $host = ::ip2str($dhost);
	KNXIO_Log ($name, 3, qq{DNS query result= $host});
	$hash->{DeviceName} = $host . q{:} . $hash->{PORT};
	delete $hash->{PORT};
	return;
}

### called from define - after init_complete
### return undef on success
sub KNXIO_openDev {
	my $hash = shift;
	my $name = $hash->{NAME};
	my $mode = $hash->{model};

	return if (IsDisabled($name) == 1);

	# handle mode X first
	if ($mode eq 'X') {
		my @f2flist = devspec2array('TYPE=FHEM2FHEM'); # get F2F devices
		foreach my $f2fdev (@f2flist) {
			next if (IsDevice($f2fdev) == 0); # no F2Fdevice found
			my $rawdev = $defs{$f2fdev}->{rawDevice};
			next if (IsDevice($rawdev,'KNXIO') == 0);
			next if ($rawdev ne $name);
			KNXIO_init($hash);
			return;
		}
		readingsSingleUpdate($hash, 'state', 'disconnected', 1);
		return qq{KNXIO_openDev ($name): open failed};
	}

	if (exists $hash->{DNSWAIT}) {
		$hash->{DNSWAIT} += 1;
		if ($hash->{DNSWAIT} > 5) {
			KNXIO_Log ($name, 2, qq{DNS failed, check ip/hostname});
			return;
		} 
		InternalTimer(gettimeofday() + 1,\&KNXIO_openDev,$hash);
		KNXIO_Log ($name, 2, q{waiting for DNS});
		return; # waiting for DNS
	}
	return if (! exists($hash->{DeviceName})); # DNS failed !

	my $reopen = (exists($hash->{NEXT_OPEN}))?1:0;
	my $param = $hash->{DeviceName}; # ip:port or UNIX:STREAM:<socket param>
	my ($host, $port, $spath) = split(/[:]/ixms,$param);
#	my ($host, $port) = split(/[:]/ixms,$param);

	KNXIO_Log ($name, 5, qq{$mode , $host , $port , reopen= $reopen});

	my $ret = undef; # result

	given ($mode) {
		### multicast support via TcpServerUtils ...
		when ('M') {
			delete $hash->{TCPDev}; # devio ?
			$ret = ::TcpServer_Open($hash, $port, $host, 1);
			if (defined($ret)) { # error
				KNXIO_Log ($name, 2, qq{can't connect: $ret}) if(!$reopen); 
				return qq{KNXIO_openDev ($name): can't connect: $ret};
			} 
			$ret = ::TcpServer_MCastAdd($hash,$host);
			if (defined($ret)) { # error
				KNXIO_Log ($name, 2, qq{MC add failed: $ret}) if(!$reopen);
				return qq{KNXIO_openDev ($name):  MC add failed: $ret};
			}

			::TcpServer_SetLoopbackMode($hash,0); # disable loopback

			delete $hash->{NEXT_OPEN};
			delete $readyfnlist{"$name.$param"};
			$ret = KNXIO_init($hash);
		}

		### socket mode
		when ('S') {
#			$host = (split(/[:]/ixms,$param))[2]; # UNIX:STREAM:<socket path>
			if (!(-S -r -w $spath) ) {
#			if (!(-S -r -w $host) && $init_done) {
				KNXIO_Log ($name, 2, q{Socket not available - (knxd running?)});
				return qq{KNXIO_openDev ($name): Socket not available - (knxd running?)};
			}
			$ret = ::DevIo_OpenDev($hash,$reopen,\&KNXIO_init); # no callback
		}

		### host udp
		when ('H') {
			my $conn = 0;
			$conn = IO::Socket::INET->new(PeerAddr => "$host:$port", Type => SOCK_DGRAM, Proto => 'udp', Reuse => 1);
			if (!($conn)) {
				KNXIO_Log ($name, 2, qq{can't connect: $ERRNO}) if(!$reopen);
				$readyfnlist{"$name.$param"} = $hash;
				readingsSingleUpdate($hash, 'state', 'disconnected', 1);
				$hash->{NEXT_OPEN} = gettimeofday() + $reconnectTO;
				return;
			}
			delete $hash->{NEXT_OPEN};
			delete $hash->{DevIoJustClosed}; # DevIo
			$conn->setsockopt(SOL_SOCKET, SO_KEEPALIVE, 1);
			$hash->{TCPDev} = $conn;
			$hash->{FD} = $conn->fileno();
			delete $readyfnlist{"$name.$param"};
			$selectlist{"$name.$param"} = $hash;

#			my $retxt = ($reopen)?'reappeared':'opened';
			KNXIO_Log ($name, 3, ($reopen)?'reappeared':'opened');
#			KNXIO_Log ($name, 3, qq{$retxt});
			$ret = KNXIO_init($hash);
		}

		### tunneling TCP
		when ('T') {
			$ret = ::DevIo_OpenDev($hash,$reopen,\&KNXIO_init,\&KNXIO_callback);
		}
	} # /given

	if(defined($ret) && $ret) {
		KNXIO_Log ($name, 1, q{Cannot open device - ignoring it});
		KNXIO_closeDev($hash);
	}

	return $ret;
}

### called from DevIo_open or KNXIO_openDev after sucessful open
sub KNXIO_init {
	my $hash = shift;
	my $name = $hash->{NAME};
	my $mode = $hash->{model};

	if ($mode =~ m/[ST]/ixms) {
		my $opengrpcon = pack('nnnC',(5,0x26,0,0)); # KNX_OPEN_GROUPCON
		::DevIo_SimpleWrite($hash,$opengrpcon,0); 
	}

	elsif ($mode eq 'H') {
		my $connreq = KNXIO_prepareConnRequ($hash);
		::DevIo_SimpleWrite($hash,$connreq,0);
	}

	# state 'connected' is set in decode_EMI (model ST) or in readH (model H)  
	else {
		KNXIO_handleConn($hash);
		KNXIO_Log ($name, 3, q{connected});
	}

	return;
}

### handle 'connected event' & state: connected
###
sub KNXIO_handleConn {
	my $hash = shift;

	my $name = $hash->{NAME};

	if (exists($hash->{KNXIOhelper}->{startdone})) {
		readingsSingleUpdate($hash, 'state', 'connected', 1);
		main::KNX_scan('TYPE=KNX:FILTER=IODev=' . $name) if (AttrNum($name,'enableKNXscan',0) >= 2); # on every connect
	}
	else { # fhem start
		KNXIO_Log ($name, 3, q{initial-connect});
		readingsSingleUpdate($hash, 'state', 'connected', 0); # no event
		$hash->{KNXIOhelper}->{startdone} = 1;
		InternalTimer(gettimeofday() + 30, \&KNXIO_initcomplete, $hash);
	}
	return;
}

### provide <device> INITIALIZED event
### called for KNXIO_define ONLY on FHEM start!
### by Internaltimer with significant delay
sub KNXIO_initcomplete {
	my $hash = shift;

	RemoveInternalTimer($hash,\&KNXIO_initcomplete);
	my $name = $hash->{NAME};
	if (ReadingsVal($name,'state','disconnected') eq 'connected') {
		main::KNX_scan('TYPE=KNX:FILTER=IODev=' . $name) if (AttrNum($name,'enableKNXscan',0) >= 1); # on 1st connect only
		DoTrigger($name,'INITIALIZED');
	} 
	elsif (AttrVal($name,'disable','disabled') ne 'disabled') {
		 KNXIO_Log ($name, 3, q{failed}); 
	}
	return;
}

### prepare connection request
### called from init, disconn response, disconn request
### returns packed string, ready for sending with DevIo
sub KNXIO_prepareConnRequ {
	my $hash = shift;

	### host protocol address information see 3.8.2 core docu
	###  hdr-size | Host Prococol code (01=udp/02=TCP) | Dest-IPAddr (4bytes) | IP port (2bytes) | hpais (8) | hpaid (8) | ctype (4) 
#	my $hpais = pack('nC4n',(0x0801,@srchost,$srcport)); # source - can be 0 (for NAT translation !
	my $hpais = pack('nCCCCn',(0x0801,0,0,0,0,0)); # source - can be 0 (for NAT translation !
#	my $hpaid = pack('nC4n',(0x0801,@desthost,$destport)); # dest we can use port 3671 for data endpoint too!
	my $hpaid = pack('nCCCCn',(0x0801,0,0,0,0,0)); # dest can be 0,0
	my $ctype = pack('CCCC',(4,4,2,0)); # 04040200 for udp tunnel_connection/Tunnel_linklayer

	my $connreq = pack('nnn',0x0610,0x0205,0x1A) . $hpais . $hpaid . $ctype;
	$hash->{KNXIOhelper}->{SEQUENCECNTR} = 0; # read requests
	$hash->{KNXIOhelper}->{SEQUENCECNTR_W} = 0; # write requests
	RemoveInternalTimer($hash,\&KNXIO_keepAliveTO); # reset timeout timer
	RemoveInternalTimer($hash,\&KNXIO_keepAlive);

	return $connreq;
}

### handle fifo and send to KNX-Module via dispatch
# all decoding already done in decode_CEMI / decode_EMI
sub KNXIO_dispatch {
	my $hash = shift;
	my $buf = shift;

	my @que = [];
	@que = @{$hash->{KNXIOhelper}->{FIFO}} if (defined($hash->{KNXIOhelper}->{FIFO}) && ($hash->{KNXIOhelper}->{FIFO} ne q{}));
	push (@que,$buf);
	@{$hash->{KNXIOhelper}->{FIFO}} = @que;

	return KNXIO_processFIFO($hash);
}

### called from FIFO TIMER
sub KNXIO_dispatch2 { 
#	my ($hash, $outbuf ) = ($_[0]->{h}, $_[0]->{m});
	my $hash = shift;

	my $buf = $hash->{KNXIOhelper}->{FIFOMSG};
	my $name = $hash->{NAME};
	$hash->{KNXIOhelper}->{FIFOTIMER} = 0;

	$hash->{'msg_count'}++;
	$hash->{'msg_time'} = TimeNow();

	Dispatch($hash, $buf);

	RemoveInternalTimer($hash,'KNXIO::KNXIO_dispatch2');
	KNXIO_processFIFO($hash);
	return;
}

### fetch msgs from FIFO and call dispatch
sub KNXIO_processFIFO {
	my $hash = shift;
	my $name = $hash->{NAME};

	RemoveInternalTimer($hash,'KNXIO::KNXIO_processFIFO');

	if ($hash->{KNXIOhelper}->{FIFOTIMER} != 0) { # dispatch still running, do a wait loop
		KNXIO_Log ($name, 5, q{dispatch not complete, waiting});
		InternalTimer(gettimeofday() + 0.1, 'KNXIO::KNXIO_processFIFO', $hash);
		return;
	}

	my @que = @{$hash->{KNXIOhelper}->{FIFO}};
	my $queentries = scalar(@que);
	if ($queentries > 1) { # delete any duplicates
		my $queentriesOld = $queentries;
		@que = KNXIO_deldupes(@que);
		$queentries = scalar(@que);
		KNXIO_Log ($name, 5, q{deleted } . ($queentriesOld - $queentries) .
                      qq{ duplicate msgs from queue, $queentries remain});
	}

	if ($queentries > 0) { # process timer is not running & fifo not empty
		$hash->{KNXIOhelper}->{FIFOMSG} = shift (@que);
		@{$hash->{KNXIOhelper}->{FIFO}} = @que;
		$hash->{KNXIOhelper}->{FIFOTIMER} = 1;
		KNXIO_Log ($name, 4, qq{buf=$hash->{KNXIOhelper}->{FIFOMSG} Nr_msgs=$queentries});
#		InternalTimer(gettimeofday() + 1.0, \&KNXIO_dispatch2, $hash); # testing delay
		InternalTimer(gettimeofday() + 0.05, 'KNXIO::KNXIO_dispatch2', $hash); # allow time for duplicate msgs to be read
		return;
	}
	KNXIO_Log ($name, 5, q{finished});
	return;
}

### delete any duplicates in an array
### ref: https://perlmaven.com/unique-values-in-an-array-in-perl
### input: array, return: array
sub KNXIO_deldupes {
	my @arr = @_;

	my %seen;
#	return grep { !$seen{$_}++ } @arr;
	return grep { !$seen{substr($_,6) }++ } @arr; # ignore C<src-addr>
}

### disconnect and wait for nxt open
## second param specifies optional open delay (sec)
sub KNXIO_disconnect {
	my $hash = shift;
	my $opendelay = shift // $reconnectTO;

	my $name = $hash->{NAME};
	my $param = $hash->{DeviceName};

	::DevIo_Disconnected($hash);

	KNXIO_Log ($name, 1, q{disconnected, waiting to reappear});

	$readyfnlist{"$name.$param"} = $hash; # Start polling
	$hash->{NEXT_OPEN} = gettimeofday() + $opendelay;

	return;
}

###
sub KNXIO_closeDev {
	my $hash = shift;
	my $name = $hash->{NAME};
	my $param = $hash->{DeviceName};

	if ($hash->{model} eq 'M') {
		::TcpServer_Close($hash,0);
	}
	else {
		::DevIo_CloseDev($hash);
		$hash->{TCPDev}->close() if($hash->{FD});
	}

	delete $hash->{nextOpenDelay};
	delete $hash->{'msg_cnt'};
	delete $hash->{'msg_time'};

#NO!	delete $hash->{'.CCID'};
	delete $hash->{KNXIOhelper}->{SEQUENCECNTR};
	delete $hash->{KNXIOhelper}->{SEQUENCECNTR_W};

	RemoveInternalTimer($hash);

	KNXIO_Log ($name, 3, q{closed}) if ($init_done);;

	readingsSingleUpdate($hash, 'state', 'disconnected', 1);

	return;
}


###################################
######## Helper functions  ########
###################################

### format: length(2) | id(2) | srcaddr(2) |  dstaddr(2) | acpi(1) | data(n) |
### input: $hash, $buf(packed)
### ret: buf - format for dispatch / undef on error
sub KNXIO_decodeEMI {
	my $hash = shift;
	my $buf  = shift;

	my $name = $hash->{NAME};

	my ($len, $id, $src, $dst, $acpi, @data) = unpack('nnnnCC*',$buf);
	if (($len + 2) != length($buf)) {
		KNXIO_Log ($name, 4, qq{buffer length mismatch $len } . length($buf) - 2);
		return;
	}
	if ($id != 0x0027) {
		if ($id == 0x0026) {
			KNXIO_Log ($name, 4, 'OpenGrpCon response received');
			KNXIO_handleConn($hash);
			KNXIO_Log ($name, 3, q{connected});
		}
		else {
			KNXIO_Log ($name, 3, 'invalid message code ' . sprintf('%04x',$id));
		}
		return;
	}

	KNXIO_Log ($name, 4, q{src=} . KNXIO_addr2hex($src,2) . q{ - dst=} . KNXIO_addr2hex($dst,3) . q{ - leng=} .
              scalar(@data) . q{ - data=} . sprintf('%02x' x scalar(@data),@data));

	$src = KNXIO_addr2hex($src,0); # always a phy-address
	$dst = KNXIO_addr2hex($dst,1); # always a Group addr

	# acpi ref: KNX System Specs 03.03.07
	$acpi = ((($acpi & 0x03) << 2) | (($data[0] & 0xC0) >> 6));
	my @acpicodes = qw(read preply write invalid);
	my $rwp = $acpicodes[$acpi];
	if (! defined($rwp) || ($rwp eq 'invalid')) {
		KNXIO_Log ($name, 3, 'no valid acpi-code (read/reply/write) received, discard packet');
		KNXIO_Log ($name, 4, qq{discarded packet: src=$src dst=$dst acpi=} . sprintf('%02x',$acpi) . 
                      q{ length=} . scalar(@data) . q{ data=} . sprintf('%02x' x scalar(@data),@data));
		return;
	}

	$data[0] = ($data[0] & 0x3f); # 6 bit data in byte 0
	shift @data if (scalar(@data) > 1 ); # byte 0 is ununsed if length > 1
	
	my $outbuf = $KNXID . $src . substr($rwp,0,1) . $dst . sprintf('%02x' x scalar(@data),@data);
	KNXIO_Log ($name, 5, qq{outbuf=$outbuf});

	return $outbuf;
}

### CEMI decode
# format: message code(1) | AddInfoLen(1) | [Addinfo(x)] | ctrl1(1) | ctrl2[1) | srcaddr(2) |  dstaddr(2) | datalen(1) | tpci(1) | acpi/data(1) | [data(n) |
# input: $hash, $buf(packed) (w.o length) 
# ret: buf - format for dispatch / undef on error
sub KNXIO_decodeCEMI {
	my $hash = shift;
	my $buf  = shift;

	my $name = $hash->{NAME};
	my ($mc, $addlen) = unpack('CC',$buf);
	if ($mc != 0x29 && $mc != 0x2e) {
		KNXIO_Log ($name, 4, 'wrong MessageCode ' . sprintf("%02x",$mc) . ', discard packet');
		return;
	}

	$addlen += 2;
	my ($ctrlbyte1, $ctrlbyte2, $src, $dst, $tcf, $acpi, @data) = unpack('x' . $addlen . 'CCnnCCC*',$buf);

	if (($ctrlbyte1 & 0xF0) != 0xB0) { # standard frame/no repeat/broadcast - see 03_06_03 EMI_IMI specs
		KNXIO_Log ($name, 4, 'wrong ctrlbyte1 ' . sprintf("%02x",$ctrlbyte1) . ', discard packet');
		return;
	}
	my $prio = ($ctrlbyte1 & 0x0C) >>2; # priority
	my $dest_addrType = ($ctrlbyte2 & 0x80) >> 7; # MSB  0 = indiv / 1 = group
	my $hop_count = ($ctrlbyte2 & 0x70) >> 4; # bits 6-4

	if ($tcf != scalar(@data)) { # $tcf: number of NPDU octets, TPCI octet not included!
		KNXIO_Log ($name, 4, 'Datalength not consistent');
		return;
	}

	my $srcd = KNXIO_addr2hex($src,2); # always a phy-address
	my $dstd = KNXIO_addr2hex($dst,$dest_addrType + 2);

	KNXIO_Log ($name, 4, qq{src=$srcd dst=$dstd destaddrType=$dest_addrType prio=$prio hop_count=$hop_count } . 
              q{length=} . scalar(@data) . q{ data=} . sprintf('%02x' x scalar(@data),@data));

	$acpi = ((($acpi & 0x03) << 2) | (($data[0] & 0xC0) >> 6));
	my @acpicodes = qw(read preply write invalid);
	my $rwp = $acpicodes[$acpi];
	if (! defined($rwp) || ($rwp eq 'invalid')) { # not a groupvalue-read/write/reply
		KNXIO_Log ($name, 3, 'no valid acpi-code (read/reply/write) received - discard packet');
		KNXIO_Log ($name, 4, qq{discarded packet: src=$srcd dst=$dstd destaddrType=$dest_addrType prio=$prio hop_count=$hop_count} . 
                      q{ length=} . scalar(@data) . q{ data=} . sprintf('%02x' x scalar(@data),@data));
		return;
	}

	$src = KNXIO_addr2hex($src,0); # always a phy-address
	$dst = KNXIO_addr2hex($dst,$dest_addrType);

	$data[0] = ($data[0] & 0x3f); # 6 bit data in byte 0
	shift @data if (scalar(@data) > 1 ); # byte 0 is ununsed if length > 1

	my $outbuf = $KNXID . $src . substr($rwp,0,1) . $dst . sprintf('%02x' x scalar(@data),@data);
	KNXIO_Log ($name, 5, qq{outbuf=$outbuf});

	return $outbuf;
}

### convert address from number to hex-string or display name ($type=2 & 3) 
sub KNXIO_addr2hex {
	my $adr = shift;
	my $type = shift // 0;  # 1 & 3 if GA-address, else physical address

	return sprintf('%02x%01x%02x', ($adr >> 11) & 0x1f, ($adr >> 8) & 0x7, $adr & 0xff) if ($type == 1);
	return sprintf('%d/%d/%d',($adr >> 11) & 0x1f, ($adr >> 8) & 0x7, $adr & 0xff) if ($type == 3);
	return sprintf('%d.%d.%d', $adr >> 12, ($adr >> 8) & 0xf, $adr & 0xff) if ($type == 2); # for display
	return sprintf('%02x%01x%02x', $adr >> 12, ($adr >> 8) & 0xf, $adr & 0xff);
}

### convert address from hex-string (5 digits) to number
sub KNXIO_hex2addr {
	my $str = shift;
	my $isphy = shift // 0;

	if ($str =~ m/([0-9a-f]{2})([0-9a-f])([0-9a-f]{2})/ixms) {
		return (hex($1) << 12) + (hex($2) << 8) + hex($3) if ($isphy == 1); # Phy addr
		return (hex($1) << 11) | (hex($2) << 8) | hex($3); # GA Addr
	}
	elsif ($str =~ m/([\d]+)\.([\d]+)\.([\d]+)/ixms) {
		return (($1 << 12) & 0x00F000) + (($2 << 8) & 0x0F00) + ($3 & 0x00FF); # phy Addr - limit values!
	}
	return 0;
}

### keep alive for mode H - every minute
# triggered on conn-response & connstate response
# 2nd param is undef unless called from KNXIO_keepAliveTO
sub KNXIO_keepAlive {
	my $hash = shift;
	my $cntrTO = shift // 0; #retry counter

	my $name = $hash->{NAME};
	$hash->{KNXIOhelper}->{CNTRTO} = $cntrTO;

	KNXIO_Log ($name, 4, 'send conn state request - expect connection state response');

	my $msg = pack('nnnCCnnnn',(0x0610,0x0207,16,$hash->{KNXIOhelper}->{CCID},0, 0x0801,0,0,0));
	RemoveInternalTimer($hash,\&KNXIO_keepAlive);
	::DevIo_SimpleWrite($hash,$msg,0); #  send conn state requ
	InternalTimer(gettimeofday() + 2,\&KNXIO_keepAliveTO,$hash); # set timeout timer - reset by ConnectionStateResponse
	return;
}

### keep alive timeout
sub KNXIO_keepAliveTO {
	my $hash = shift;

	my $name = $hash->{NAME};
	my $cntrTO = $hash->{KNXIOhelper}->{CNTRTO};

	return KNXIO_disconnect($hash,3) if ($cntrTO >= 2); # nr of timeouts exceeded

	$cntrTO++;
	KNXIO_Log ($name, 3, qq{timeout - retry $cntrTO});
	KNXIO_keepAlive($hash,$cntrTO);
	return;
}

### TO hit while sending...
sub KNXIO_TunnelRequestTO {
	my $hash = shift;
	my $name = $hash->{NAME};

	RemoveInternalTimer($hash,\&KNXIO_TunnelRequestTO);
	# try resend...but only once
	if (exists($hash->{KNXIOhelper}->{LASTSENTMSG})) {
		KNXIO_Log ($name, 3, 'timeout - attempt resend');
		my $msg = $hash->{KNXIOhelper}->{LASTSENTMSG};
		::DevIo_SimpleWrite($hash,$msg,0);
		delete $hash->{KNXIOhelper}->{LASTSENTMSG};
		InternalTimer(gettimeofday() + 1.5, \&KNXIO_TunnelRequestTO, $hash);
		return;
	}

	KNXIO_Log ($name, 3, 'timeout - sending disconnect request');

	# send disco request
	my $hpai = pack('nCCCCn',(0x0801,0,0,0,0,0));
	my $msg = pack('nnnCC',(0x0610,0x0209,16,$hash->{KNXIOhelper}->{CCID},0)) . $hpai;
	::DevIo_SimpleWrite($hash,$msg,0); #  send disconn requ
	return;
}

### unified Log handling
### calling param: same as Log3: hash/name/undef, loglevel, logtext
### prependes device, subroutine, linenr. to Log msg
### return undef
sub KNXIO_Log {
	my $dev    = shift // 'global';
	my $loglvl = shift // 5;
	my $logtxt = shift;

	my $name = ( ref($dev) eq 'HASH' ) ? $dev->{NAME} : $dev;
	my $dloglvl = AttrVal($name,'verbose',undef) // AttrVal('global','verbose',3);
	return if ($loglvl > $dloglvl); # shortcut performance

	my $sub  = (caller(1))[3] // 'main';
	my $line = (caller(0))[2];
	$sub =~ s/^.+[:]+//xms;

	Log3 ($name, $loglvl, qq{$name [$sub $line]: $logtxt});
	return;
}

### translate Error-codes to text
### copied from 03_08_01 & 03_08_02_Core document
### all i know...
sub KNXIO_errCodes {
	my $errcode = shift;

	my $errlist = {0=>'NO_ERROR',1=>'E_HOST_PROTCOL',2=>'E_VERSION_NOT_SUPPORTED',4=>'E_SEQUENCE_NUMBER',33=>'E_CONNECTION_ID',
            34=>'E_CONNECT_TYPE',35=>'E_CONNECTION_OPTION',36=>'E_NO_MORE_CONNECTIONS',38=>'E_DATA_CONNECTION',39=>'E_KNX_CONNECTION',
            41=>'E_TUNNELLING_LAYER',
        };
	# full text
	my $errlistfull = {0=>'OK',
             1=>'The requested host protocol is not supported by the KNXnet/IP device',
             2=>'The requested protocol version is not supported by the KNXnet/IP device',
             4=>'The received sequence number is out of order',
            33=>'The KNXnet/IP Server device cannot find an active data connection with the specified ID',
            34=>'The requested connection type is not supported by the KNXnet/IP Server device',
            35=>'One or more requested connection options are not supported by the KNXnet/IP Server device',
            36=>'The KNXnet/IP Server device cannot accept the new data connection because its maximum amount of concurrent connections is already occupied',
            38=>'The KNXnet/IP Server device detects an error concerning the data connection with the specified ID',
            39=>'The KNXnet/IP Server device detects an error concerning the KNX subnetwork connection with the specified ID',
            41=>'The KNXnet/IP Server device does not support the requested KNXnet/IP Tunnelling layer',
        };

	my $errtxt = $errlist->{$errcode};
	return 'E_UNDEFINED_ERROR ' . $errcode if (! defined($errtxt));
	$errtxt .= q{: } . $errlistfull->{$errcode}; # concatenate both textsegments
	return $errtxt; 
}

##############################################
########## public utility functions ##########
# when called from FHEM cmd-line
sub main::KNX_scancmd {
	my $cl = shift;
	my $devs = shift;

	$devs = 'TYPE=KNX' if (! defined($devs) || $devs eq q{}); # select all if nothing defined
	main::KNX_scan($devs);
	return;
}

### get state of devices from KNX_Hardware
# called with devspec as argument
# e.g : KNX_scan() / KNX_scan('device1') / KNX_scan('device1,dev2,dev3,...') / KNX_scan('room=Kueche'), ...
# returns number of "gets" executed
sub main::KNX_scan {
	my $devs = shift;

	$devs = 'TYPE=KNX' if (! defined($devs) || $devs eq q{}); # select all if nothing defined

	if (! $init_done) { # avoid scan before init complete
		Log3 (undef, 2,'KNX_scan command rejected during FHEM-startup!');
		return 0;
	}

	my @devlist = devspec2array($devs);

	my $i = 0; #counter devices
	my $j = 0; #counter devices with get
	my $k = 0; #counter total get's
	my $getsarr = q{};

	foreach my $knxdef (@devlist) {
		next unless $knxdef;
		next if($knxdef eq $devs && !$defs{$knxdef});
		my $devhash = $defs{$knxdef};
		next if ((! defined($devhash)) || ($devhash->{TYPE} ne 'KNX'));

		#check if IO-device is ready
		my $iodev = $devhash->{IODev}->{NAME};
		next if (! defined($iodev));
		next if ($defs{$iodev}->{STATE} ne 'connected'); # yes:KNXIO/FHEM2FHEM no:TUL/KNXTUL 

		$i++;
		my $k0 = $k; #save previous number of get's
		foreach my $key (keys %{$devhash->{GADDETAILS}}) {
			last if (! defined($key));
			next if($devhash->{GADDETAILS}->{$key}->{MODEL} eq $MODELERR);
			my $option = $devhash->{GADDETAILS}->{$key}->{OPTION};
			next if (defined($option) && $option =~ /(?:set|listenonly)/ixms);
			$k++;
			$getsarr .= $knxdef . q{ } . $key . q{,};
		}
		$j++ if ($k > $k0);
	}
	Log3 (undef, 3, qq{KNX_scan: $i devices selected (regex= $devs) / $j devices with get / $k "gets" executing...});
	doKNX_scan($getsarr) if ($k > 0);
	return $k;
}

### issue all get cmd's - each one delayed by InternalTimer
sub doKNX_scan {
	my ($devgad, $arr) = split(/,/xms,shift,2);

	my ($name, $gadName) = split(/[\s]/xms,$devgad);
	KNX::KNX_Get ($defs{$name}, $name, $gadName);

	if (defined($arr) && $arr ne q{}) {
		my $count = split(/,/xms,$arr); # number of remainig pairs
		my $delay = ($count % 10 == 0)?2:0.2; # extra delay on each 10th request
		return InternalTimer(gettimeofday() + $delay,\&doKNX_scan,$arr); # does not support array-> use string...
	}
	Log3 (undef, 3, q{KNX_scan: finished});
	return;
}


1;

=pod

=encoding utf8

=item [device]
=item summary IO-module for KNX-devices supporting UDP, TCP & socket connections
=item summary_DE IO-Modul f&uuml;r KNX-devices. Unterst&uuml;tzt UDP, TCP & Socket Verbindungen

=begin html

<a id="KNXIO"></a>
<h3>KNXIO</h3>
<ul>
<li><p>This is a IO-module for KNX-devices. It provides an interface between FHEM and a KNX-Gateway. The Gateway can be either a KNX-Router/KNX-GW or the KNXD-daemon.
   FHEM KNX-devices use this module as IO-Device. This Module does <b>NOT</b> support the deprecated EIB-Module!
</p>
<p>A (german) wiki page is avaliable here&colon; <a href="https://wiki.fhem.de/wiki/KNXIO">FHEM Wiki</a></p>
</li>
<li><a id="KNXIO-define"></a><strong>Define</strong>
<pre><code>define &lt;name&gt; KNXIO (H|M|T) &lt;(ip-address|hostname)&colon;port&gt; &lt;phy-adress&gt;</code>
<code>define &lt;name&gt; KNXIO S &lt;UNIX socket-path&gt; &lt;phy-adress&gt;</code>
<code>define &lt;name&gt; KNXIO X</code></pre>

<b>Connection Types (mode)</b> (first parameter)&colon;
<ul>
<li><b>H</b> Host Mode - connect to a KNX-router with UDP point-point protocol.<br/>
  This is the mode also used by ETS when you specify <b>KNXNET/IP</b> as protocol. You do not need a KNXD installation. The protocol is complex and timing critical! 
  If you have delays in FHEM processing close to 1 sec, the protocol may disconnect. It should recover automatically, 
  however KNX-messages could have been lost! 
  <br>The benefit of this protocol&colon; every sent and received msg has to be acknowledged within 1 second by the communication partner, msg delivery is verified!</li>
<li><b>M</b> Multicast mode - connect to KNXD's or KNX-router's multicast-tree.<br/>
  This is the mode also used by ETS when you specify <b>KNXNET/IP Routing</b> as protocol. 
  If you have a KNX-router that supports multicast, you do not need a KNXD installation. Default address&colon;port is 224.0.23.12&colon;3671<br/>
  Pls. ensure that you have only <b>one</b> GW/KNXD in your LAN that feed the multicast tree!<br/>
  <del>This mode requires the <code>IO&colon;&colon;Socket&colon;&colon;Multicast</code> perl-module to be installed on yr. system. 
  On Debian systems this can be achieved by <code>apt-get install libio-socket-multicast-perl</code>.</del></li>
<li><b>T</b> TCP mode - uses a TCP-connection to KNXD (default port&colon; 6720).<br/>
  This mode is the successor of the TUL-modul, but does not support direct Serial/USB connection to a TPUart-USB Stick.
  If you want to use a TPUart-USB Stick or any other serial KNX-GW, use either the TUL Module, or connect the USB-Stick to KNXD and in turn use modes M,S or T to connect to KNXD.</li>
<li><b>S</b> Socket mode - communicate via KNXD's UNIX-socket on localhost. default Socket-path&colon; <code>/var/run/knx</code><br/> 
  Path might be different, depending on knxd-version or -config specification! This mode is tested ok with KNXD version 0.14.30. It does NOT work with ver. 0.10.0!</li>
<li><b>X</b> Special mode - for details see KNXIO-wiki!</li>
</ul>
<br/>
<b>ip-address&colon;port</b> or <b>hostname&colon;port</b>
<ul>
<li>Hostname is supported for mode H and T. Port definition is mandatory.</li>
</ul>
<br/>
<b>phy-address</b>
<ul>
<li>The physical address is used as the source address of messages sent to KNX network. This address should be one of the defined client pool-addresses of KNXD or Router.</li>
</ul>

<br/>All parameters are mandatory. Pls. ensure that you only have <b>one path</b> between your KNX-Installation and FHEM! 
  Do not define multiple KNXIO- or KNXTUL- or TUL-definitions at the same time.
<pre>Examples&colon;
<code>    define myKNXGW KNXIO H 192.168.1.201&colon;3671 0.0.51
    define myKNXGW KNXIO M 224.0.23.12&colon;3671 0.0.51 
    define myKNXGW KNXIO S /var/run/knx 0.0.51
    define myKNXGW KNXIO T 192.168.1.200&colon;6720 0.0.51

Suggested parameters for KNXD (Version &gt;= 0.14.30), with systemd&colon;
    KNXD_OPTS="-e 0.0.50 -E 0.0.51&colon;8 -D -T -S -b ip&colon;"                 # knxd acts as multicast client - do NOT use -R !
    KNXD_OPTS="-e 0.0.50 -E 0.0.51&colon;8 -D -T -R -S -b ipt&colon;192.168.xx.yy"           # connect to a knx-router with ip-addr
    KNXD_OPTS="-e 0.0.50 -E 0.0.51&colon;8 -D -T -R -S -single -b tpuarts&colon;/dev/ttyxxx" # connect to a serial/USB KNX GW  
  The -e and -E parameters must match the definitions in the KNX-router (set by ETS)!
</code></pre> 
</li>

<li><a id="KNXIO-set"></a><strong>Set</strong> - No Set cmd implemented.
  If you want to restart communication, use Attr disable.<br/><br/></li>
<li><a id="KNXIO-get"></a><strong>Get</strong> - No Get cmd impemented<br/><br/></li>

<li><a id="KNXIO-attr"></a><strong>Attributes</strong><br/>
<ul>
<li><a id="KNXIO-attr-disable"></a><b>disable</b> - 
  Disable the device if set to <b>1</b>. No send/receive from bus possible. Delete this attr to enable device again.</li>
<li><a id="KNXIO-attr-verbose"></a><b>verbose</b> - 
  increase verbosity of Log-Messages, system-wide default is set in "global" device. For a detailed description see&colon; <a href="#verbose">global-attr verbose</a> <br/></li> 
<li><a id="KNXIO-attr-enableKNXscan"></a><b>enableKNXscan</b> -
  trigger a KNX_scan cmd at fhemstart or at every connect event. A detailed description of the <a href="#KNX-utilities">KNX_scan cmd</a> is here!
<pre><code>   0 - never (default if Attr not defined)
   1 - after fhem start (together with INITIALIZED event)
   2 - after fhem start and on every connect event</code></pre></li>  
</ul>
</li>
<li><a id="KNXIO-events"></a><strong>Events</strong><br/>
<ul>
<li><b>&lt;device&gt;&colon;INITIALIZED</b> -
  The first &lt;device&gt;&colon;connected event after fhem start is suppressed and replaced (after 30 sec delay) with this event.
  It can be used (in a notify,doif,...) to syncronize the status of FHEM-KNX-devices with the KNX-Hardware.
  Do not use the <code>global&colon;INITIALIZED</code> event for this purpose, the KNX-GW is not ready for communication at that time!<br/>
  Example&colon;<br/>
  <code>defmod KNXinit_nf notify &lt;device&gt;&colon;INITIALIZED get &lt;KNX-device&gt; &lt;gadName&gt;</code> 
  # or even simpler, just use Attribute&colon; <br/>
  <code>attr &lt;device&gt; enableKNXscan 1</code> # to scan all KNX-devices which have this device defined as their IO-device.</li>
<li><b>&lt;device&gt;&colon;connected</b> -
  triggered if connection to KNX-GW/KNXD is established.</li>
<li><b>&lt;device&gt;&colon;disconnected</b> -
  triggered if connection to KNX-GW/KNXD failed. Recovery is attempted.</li>
</ul>
</li>
</ul>

=end html

=cut
