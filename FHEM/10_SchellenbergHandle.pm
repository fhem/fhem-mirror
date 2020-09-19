# $Id$
###############################################################################
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
#
###############################################################################

# Thanks to hypfer for doing the basic research 

package main;

use 5.018;
use feature qw( lexical_subs );

use strict;
use warnings;
use utf8;
use Fcntl qw( :DEFAULT );

no warnings qw( experimental::lexical_subs );

sub SchellenbergHandle_Initialize {
	my ($hash) = @_;

	$hash->{'DefFn'}				= 'SchellenbergHandle_Define';
	$hash->{'UndefFn'}				= 'SchellenbergHandle_Undef';
	#$hash->{'DeleteFn'}				= 'Schellenberg_Delete';
	#$hash->{'SetFn'}				= 'SchellenbergHandle_Set';
	#$hash->{'ReadFn'}				= "Schellenberg_Read";
	#$hash->{'ReadyFn'}				= "Schellenberg_Ready";
	$hash->{'ParseFn'}				= "SchellenbergHandle_Parse";
	$hash->{'Match'}				= '^ss[[:xdigit:]]{1}4[[:xdigit:]]{16}';
	$hash->{'AttrList'} 			= $readingFnAttributes;

	return;
};

sub SchellenbergHandle_Define {
	my ($hash, $def) = @_;
	my ($name, $type, $id) = split /\s/, $def, 3;

	my $cvsid = '$Id$';
	$cvsid =~ s/^.*pm\s//;
	$cvsid =~ s/Z\s\S+\s\$$/ UTC/;
	$hash->{'SVN'} = $cvsid;

	# id valid?
	return 'invalid id' if ($id !~ m/^([[:xdigit:]]{6})$/);

	# id exists AND device exists?
	return 'handle already defined' if (exists($modules{'SchellenbergHandle'}{'defptr'}{$id}));

	# set id to defptr
	$hash->{'ID'} = $id;
	$modules{'SchellenbergHandle'}{'defptr'}{$id} = $hash;
	InternalTimer(0, \&SchellenbergHandle_Run, $hash);	
	return;
};

sub SchellenbergHandle_Undef {                     
	my ($hash, $name) = @_;

	# remove watchdog
	RemoveInternalTimer($hash, \&SchellenbergHandle_Watchdog);
	# remove defptr
	delete $modules{'SchellenbergHandle'}{'defptr'}{$hash->{'ID'}};
	return;
};

# modul, all readings and attribute are loaded
sub SchellenbergHandle_Run {
	my ($hash) = @_;

	# enable watchdog
	InternalTimer(Time::HiRes::time() + 86400, \&SchellenbergHandle_Watchdog, $hash);
	
	return;
};

sub SchellenbergHandle_Set {
	my ($hash, $name, $cmd, @args) = @_;

	return "Unknown argument $cmd, choose one of none" if ($cmd eq '?');
};

sub SchellenbergHandle_Watchdog {
	my ($hash) = @_;

	readingsBeginUpdate($hash);
	readingsBulkUpdateIfChanged($hash, 'state', 'dead');
	readingsBulkUpdateIfChanged($hash, 'alive', 'dead');
	readingsEndUpdate($hash, 1);

	return;
};

# not used atm, rolling-code is synchronized after each startup
sub SchellenbergHandle_SetPersistentData {
	my ($hash, $mc, $close) = @_;

	my $filename = File::Spec->catfile(Logdir(), "$hash->{'FUUID'}.data");	
	if (sysopen(my $fh, $filename, O_WRONLY|O_CREAT|O_TRUNC|O_SYNC)) {
		binmode $fh, ':encoding(UTF-8):crlf';
		say $fh sprintf('# This file is automatically generated by %s; do not modify.', $hash->{'NAME'});
		# SBWH, version, gmt-timestamp, rolling-code, 0: intermediate, 1: clean shutdown LINE-END
		say $fh sprintf('SBWH,1,%s,%s,%s', time(), 1234, 0);
		close($fh);
	} else {
		say "error $!";
	};
};

# not used atm, rolling-code is synchronized after each startup
sub SchellenbergHandle_GetPersistentData {
	my ($hash) = @_;

	my $filename = File::Spec->catfile(Logdir(), "$hash->{'FUUID'}.data");
	if (sysopen(my $fh, $filename, O_RDONLY)) {
		binmode $fh, ':encoding(UTF-8):crlf';
		my @lines = readline $fh;
		say @lines;
		close($fh);
	} else {
		say "error $!";
	};
};

sub SchellenbergHandle_ProcessMsg {
	my ($hash, $mt, $fn, $mc, $lc, $rssi) = @_;

	my $unknown1 = hex($lc) & 3; # 2 lsb in message repetition. Only seen as zero
	$lc = hex($lc) >> 2; # right shift 2 bit / message repetition
	$rssi = hex($rssi) - 256;
	Log3 ($hash, 4, sprintf('type: %s, fn: %s, mc: %s, lc: %s, rssi: %s dBm, unkown: %s', $mt, $fn, $mc, $lc, $rssi, $unknown1));

	my sub statefn {
		my ($fncode) = shift;
		my $table = {
			'3B'	=>	'tilted',
			'1B'	=>	'open',
			'1A'	=>	'closed',
			'18'	=>	'alarm',
			'19'	=>	'alarm-end',
		};
		return exists($table->{$fncode})?$table->{$fncode}:$fncode;
	};

	if ($mt eq '1') {
		# message counter > last known ?
		$mc = hex($mc);
		my $lastmc = $hash->{'.MC'} // hex($mc) -1;
		my $diff;
		{	
			use integer; 
			$diff = (0x10000 +$mc -$lastmc) & 0xFFFF;
		};
		if ($diff == 0) {
			return;
		} elsif ($diff < 256) {
			#$hash->{'MISSED_PACKET'} += $lc;
			readingsBeginUpdate($hash);
			#readingsBulkUpdate($hash, '.mc', hex($mc));
			$hash->{'.MC'} = hex($mc);
			readingsBulkUpdateIfChanged($hash, 'state', statefn($fn));
			readingsBulkUpdateIfChanged($hash, 'alive', 'ok');
			readingsBulkUpdate($hash, 'rssi', $rssi);
			readingsEndUpdate($hash, 1);
			SchellenbergHandle_SetPersistentData($hash, $mc, 0) if ($mc % 8 == 0);
		} else {
			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash, 'state', 'out-of-sync');
			readingsBulkUpdateIfChanged($hash, 'alive', 'ok');
			readingsBulkUpdate($hash, 'rssi', $rssi);
			readingsEndUpdate($hash, 1);
		};
	} elsif ($mt eq '0') {
		my $f = hex($mc) >> 8;
		if ($f == 0x84) {
			RemoveInternalTimer($hash, \&SchellenbergHandle_Watchdog);
			readingsBeginUpdate($hash);
			my $battery = sprintf('%.1f', (hex($mc) & 0xFF) / 10);
			readingsBulkUpdateIfChanged($hash, 'state', 'alive') if ($hash->{'STATE'} eq 'dead');
			readingsBulkUpdateIfChanged($hash, 'voltage', $battery);
			readingsBulkUpdateIfChanged($hash, 'battery', ($battery > 2.0)?'ok':'low');
			readingsBulkUpdateIfChanged($hash, 'alive', 'ok');
			readingsBulkUpdate($hash, 'rssi', $rssi);
			readingsEndUpdate($hash, 1);
			InternalTimer(Time::HiRes::time() + 86400, \&SchellenbergHandle_Watchdog, $hash);
			#InternalTimer(Time::HiRes::time() + 5, \&watchdog, $hash);
		};
	};
};

sub SchellenbergHandle_Parse {
	my ($io_hash, $msg) = @_;

	if (my ($mt, $id, $fn, $mc, $lc, $rssi) = ($msg =~ m/^ss
		([[:xdigit:]]{1})
		4
		([[:xdigit:]]{6})
		([[:xdigit:]]{2})
		([[:xdigit:]]{4})
		([[:xdigit:]]{2})
		([[:xdigit:]]{2})/x)) {

		my $hash = $modules{'SchellenbergHandle'}{'defptr'}{$id};

		if (defined($hash) and exists($hash->{'NAME'}) and exists($defs{$hash->{'NAME'}})) {
			SchellenbergHandle_ProcessMsg($hash, $mt, $fn, $mc, $lc, $rssi);
			return $hash->{'NAME'};
		} else {
			# pair cmd
			if (1 or exists($io_hash->{'PAIRING'}) and $io_hash->{'PAIRING'} and $mt eq '1' and $fn eq '40') {
				return "UNDEFINED SchellenbergHandle_$id SchellenbergHandle $id";
			} else {
				Log3 ($io_hash, 3, sprintf('SchellenbergHandle: unpaired handle %s', $id)) if (lc eq '00');
				return (undef);
			};
		};
	};
	#	print POSIX::strftime '%Y.%m.%d %H:%M:%S: ', localtime();
	#	print "incoming SOME -----> msg $msg -> $mt $id $fn $mc $lc\r";
	return;	
};

1;

=pod
=item device
=item summary 		Schellenberg RF Alarm Door Handle
=item summary_DE	Schellenberg Funk-Sicherheits-Alarmgriff
=begin html

<a name="SchellenbergHandle"></a>
<h3>SchellenbergHandle</h3>
<ul>
	Schellenberg RF Alarm Door Handle.
</ul>
<ul>
	<a name="SchellenbergHandledefine"></a>
	<b>Define</b>
	<ul>
    	<code>define &lt;name&gt; SchellenbergHandle &lt;ID&gt;</code>
    	<br><br>
    	The device should be installed via autocreate. 
    	<ul>
    		<li>Install a Schellenberg USB dongle and the associated device (Schellenberg)</li>
			<li>Activate pair seconds there</li>
			<li>Pair the door handle as described in the manual (handle up, left switch)</li>
		</ul>
	</ul>
	<br>

	<a name="SchellenbergHandleget"></a>
	<b>Get</b>
	<ul>
		<li>readingFnAttributes</li>
	</ul>
	<br>
</ul>
=end html

=cut