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

package main;

use 5.018;
use feature qw( lexical_subs );

use strict;
use warnings;
use utf8;
use HttpUtils;
use List::Util qw( any );
use Text::Balanced qw ( extract_codeblock extract_delimited extract_bracketed );
use Time::Local qw( timelocal timegm );
use Unicode::Normalize qw( NFD );
# support system://'curl '
use IPC::Open3;
use Symbol 'gensym'; 


#use Memory::Usage;

no warnings qw( experimental::lexical_subs );

sub JsonMod_Initialize {
	my ($hash) = @_;

	my @attrList;
	{
		no warnings qw( qw );
	 	@attrList = qw(
			httpHeader:textField-long
			httpTimeout
			update-on-start:0,1
			readingList:textField-long
			disable:0,1
			interval
		);
	};

	$hash->{'DefFn'}				= 'JsonMod_Define';
	$hash->{'UndefFn'}				= 'JsonMod_Undef';
	$hash->{'DeleteFn'}				= 'JsonMod_Delete';
	$hash->{'SetFn'}				= 'JsonMod_Set';
	$hash->{'AttrFn'}				= 'JsonMod_Attr';
	#$hash->{'NotifyFn'}				= 'JsonMod_Notify';
	$hash->{'AttrList'}				= join(' ', @attrList)." $readingFnAttributes ";

	return undef;
};

sub JsonMod_Define {
	my ($hash, $def) = @_;
	my ($name, $type, $source) = split /\s/, $def, 3;

	my $cvsid = '$Id$';
	$cvsid =~ s/^.*pm\s//;
	$cvsid =~ s/Z\s\S+\s\$$/ UTC/;
	$hash->{'SVN'} = $cvsid;
	$hash->{'CONFIG'}->{'IN_REQUEST'} = 0;
	$hash->{'CONFIG'}->{'CRON'} = \'0 * * * *';
	$hash->{'CRON'} = JsonMod::Cron->new();

	return "no FUUID, is fhem up to date?" if (not $hash->{'FUUID'});
	return "wrong source definition" if ($source !~ m/^(https:|http:|file:|system:)/);

	$hash->{'CONFIG'}->{'SOURCE'} = $source;
	#($hash->{'NOTIFYDEV'}) = devspec2array('TYPE=Global');
	InternalTimer(0, \&JsonMod_Run, $hash);
	return;
};

# reread / temporary remove
sub JsonMod_Undef {
	my ($hash, $name) = @_;
	#RemoveInternalTimer($hash, \&JsonMod_DoTimer);
	JsonMod_StopTimer($hash);
	return;
};

# delete / permanently remove
sub JsonMod_Delete {
	my ($hash, $name) = @_;
	my $error;
	# remove secret
	setKeyValue($hash->{'FUUID'}, undef);
	return $error;
};

sub JsonMod_Run {
	my ($hash) = @_;
	my $name = $hash->{'NAME'};

	JsonMod_ReadPvtConfig($hash);
	return if IsDisabled($name);

	my $cron = AttrVal($name, 'interval', '0 * * * *');
	$hash->{'CONFIG'}->{'CRON'} = \$cron;
	JsonMod_StartTimer($hash);
	JsonMod_ApiRequest($hash) if AttrVal($name, 'update-on-start', 0);
	return;
};

sub JsonMod_Set {
	my ($hash, $name, $cmd, @args) = @_;

	my @cmds = qw( reread secret );
	return sprintf ("Unknown argument $cmd, choose one of %s", join(' ', @cmds)) unless (any {$cmd eq $_} @cmds);

	if ($cmd eq 'secret') {
		if (not $args[1] and (exists($hash->{'CONFIG'}->{'SECRET'}->{$args[0]}))) {
			delete $hash->{'CONFIG'}->{'SECRET'}->{$args[0]};
			JsonMod_WritePvtConfig($hash);
		} elsif ($args[1]) {
			$hash->{'CONFIG'}->{'SECRET'}->{$args[0]} = \$args[1];
			JsonMod_WritePvtConfig($hash);
		};
		return;
	} elsif ($cmd eq 'reread') {
		return 'request already pending' if ($hash->{'CONFIG'}->{'IN_REQUEST'});
		JsonMod_ApiRequest($hash);
		return;
	};

	return;
};

sub JsonMod_Attr {
	my ($cmd, $name, $attrName, $attrValue) = @_;
	my $hash = $defs{$name};
	$attrValue //= '';
	#my $result;

	if ($cmd eq 'set') {
		if ($attrName eq 'disable') {
			if ($attrValue) {
				JsonMod_StopTimer($hash);
			} else {
				JsonMod_StopTimer($hash);
				JsonMod_StartTimer($hash); # unless IsDisabled($name);
			};
		};
		if ($attrName eq 'interval') {
			if (split(/ /, $attrValue) == 5) {
				if ($hash->{'CRON'}->validate($attrValue)) {
					$hash->{'CONFIG'}->{'CRON'} = \$attrValue;
					return if (!$init_done);
					JsonMod_StopTimer($hash);
					JsonMod_StartTimer($hash) unless IsDisabled($name);
					return;
				} else {
					return "wrong interval expression (cron)"
				};
			};
			return "wrong interval expression";
		};
	};
	if ($cmd eq 'del') {
		if ($attrName eq 'interval') {
			$hash->{'CONFIG'}->{'CRON'} = \'0 * * * *';
			JsonMod_StopTimer($hash);
			JsonMod_StartTimer($hash); # unless IsDisabled($name);
			return;
		};
		if ($attrName eq 'disable') {
			JsonMod_StartTimer($hash); # unless IsDisabled($name);
		};
	};
};

# sub JsonMod_Notify {
# 	my ($hash, $dev) = @_;
# 	my $name = $hash->{'NAME'};
# 	return undef if(IsDisabled($name));

# 	my $events = deviceEvents($dev, 1);
# 	return if(!$events);

# 	foreach my $event (@{$events}) {
# 		my @e = split /\s/, $event;
# 		JsonMod_Logger($hash, 5, 'event:[%s], device:[%s]', $event, $dev->{'NAME'});
# 		if ($dev->{'TYPE'} eq 'Global') {
# 			if ($e[0] and $e[0] eq 'INITIALIZED') {
# 				JsonMod_Run($hash);
# 			};
# 		};
# 	};
# 	return;
# };

# retrieve secrets
sub JsonMod_ReadPvtConfig {
	my ($hash) = @_;

	# my sub clean {
	local *clean = sub {
		$hash->{'CONFIG'}->{'SECRET'} = {};
		return;
	};

	my ($error, $data) = getKeyValue($hash->{'FUUID'});
	if ($error or not $data) {
		return clean();
	} else {
		$data = MIME::Base64::decode($data);
		$data = JsonMod::JSON::StreamReader->new()->parse($data) or do {return clean()};
		return clean() if (ref($data) ne 'HASH');
	};

	foreach my $k (keys %{$data->{'SECRET'}}) {
		$hash->{'CONFIG'}->{'SECRET'}->{$k} = \$data->{'SECRET'}->{$k};
	};
	$hash->{'SECRETS'} = join ", ", keys (%{$hash->{'CONFIG'}->{'SECRET'}});
	return;
};

# store secrets
sub JsonMod_WritePvtConfig {
	my ($hash) = @_;

	my $data;
	foreach my $k (keys (%{$hash->{'CONFIG'}->{'SECRET'}})) {
		$data->{'SECRET'}->{$k} = ${$hash->{'CONFIG'}->{'SECRET'}->{$k}};
	};
	$hash->{'SECRETS'} = join ", ", keys (%{$hash->{'CONFIG'}->{'SECRET'}});
	my $key = $hash->{'FUUID'};
	my $val = MIME::Base64::encode(JsonMod::JSON::StreamWriter->new()->parse($data));
	my $error = setKeyValue($key, $val);
	return;
};

sub JsonMod_DoReadings {
	my ($hash, $data) = @_;
	my $name = $hash->{'NAME'};

	JsonMod_Logger($hash, 5, 'start JsonPath');
	my $path = JsonMod::JSON::Path->new($data);

	my $newReadings = {};
	my $oldReadings = {};
	foreach my $key (keys %{$hash->{'READINGS'}}) {
		$oldReadings->{$key} = 0;
	};

	# lexical subs are supected to cause segv under rare conditions, see forum #133135
	# changed to localized globs

	# sanitize reading names to comply with fhem naming conventions
	# (allowed chars: A-Za-z/\d_\.-)
	# my sub sanitizedSetReading {
	local *sanitizedSetReading = sub {
		my ($r, $v) = @_;

		# convert into valid reading
		# special treatment of "umlaute"
		my %umlaute = ("ä" => "ae", "Ä" => "Ae", "ü" => "ue", "Ü" => "Ue", "ö" => "oe", "Ö" => "Oe", "ß" => "ss" );
		my $umlautkeys = join ("|", keys(%umlaute));
		$r =~ s/($umlautkeys)/$umlaute{$1}/g;
		# normalize remaining special chars
		$r = Unicode::Normalize::NFD($r);
		utf8::encode($r) if utf8::is_utf8($r);
		$r =~ s/\s/_/g;	# whitespace 
		$r =~ s/([^A-Za-z0-9\/_\.-])//g;
		# prevent a totally stripped reading name / todo, log it?
		$r = "__CONVERSATION_ERROR__" unless($r);
		$v //='';
		utf8::encode($v) if utf8::is_utf8($v);
		$newReadings->{$r} = $v;
		$oldReadings->{$r} = 1;
		#printf "1 %s %s %s %s\n", $r, length($r), $v, length($v);
	};

	# my sub concat {
	local *concat = sub {
		my @args = @_;
		my $result = '';
		foreach my $arg (@args) {
			$result .= $arg;
		};
		return $result;
	};

	# processing attr readingList
	my $readingList = AttrVal($name, 'readingList', '');
	$readingList =~ s/\s+$//s; # rtrim
	utf8::decode($readingList); # data from "ouside"

	while ($readingList) {

		my ($args, $cmd);

		next if ($readingList =~ s/^\s*#.*\R*//); # remove comments
		$readingList =~ s/\//\\\//g; # escape slash forum 122166
		($args, $readingList, $cmd) = extract_codeblock ($readingList, '()', '(?m)[^(]*');
		$readingList =~ s/\\\//\//g; # revert escaped slash
		$args =~ s/\\\//\//g if defined($args); # revert escaped slash
		# say 'A:'.$args;
		# say 'R:'.$readingList;
		# say 'C:'.$cmd;
		if (not $cmd or $@) {
			JsonMod_Logger($hash, 2, 'syntax error in readingList statement: \'%s%s\' %s', $readingList);
			last;
		};
		$cmd =~ s/^\s+|\s+$//g; # chomp
		$readingList =~ s/\s*;//;

		# control warnings, required in multi()
		my $warnings = 1;
		# my sub logWarnings {
		local *logWarnings = sub {
			return unless ($warnings);
			my ($msg) = @_;
			$msg =~ s/at \(eval.*$//;
			JsonMod_Logger($hash, 3, 'warning: %s in \'%s%s\'', $msg, $cmd, $args);
		};

		if ($cmd eq 'single') {

			# my sub jsonPath {
			local *jsonPath = sub {
				my ($propertyPath) = @_;
				my $presult = $path->get($propertyPath)->getResultValue();
				
				if (defined($presult)) {
					if ((ref($presult) eq 'ARRAY') and (scalar(@{$presult}))) {
						return $presult->[0]; # the first hit if many. be gentle ;)
					} elsif ((ref($presult) eq 'HASH') or (ref($presult) eq '')) {
						return $presult;
					};
				};
				return undef;
			};

			# my sub jsonPathf {
			local *jsonPathf = sub {
				my ($propertyPath, $format) = @_;
				$format //= '%s';
				my $presult = jsonPath($propertyPath);
				if (defined($presult)) {
					return sprintf($format, $presult);
				};
				return undef;
			};

			# my sub s1 {
			local *s1 = sub {
				my ($readingValue, $readingName, $default) = @_;
				$readingValue //= $default;
				die ('missing reading name') unless ($readingName);
				sanitizedSetReading($readingName, $readingValue) if (defined($readingValue));
			};

			{
				local $SIG{__WARN__} = \&logWarnings;
				eval 's1'.$args;
				if ($@) {
					my $msg = $@;
					if ($msg =~ m/^(.*)(?:at.*(?:eval|98_JsonMod).*)line (\d+)?/m) {
						JsonMod_Logger($hash, 2, 'error: %s (#%s) in %s%s', $1, $2, $cmd, $args);
					} else {
						JsonMod_Logger($hash, 2, 'error: %s in %s%s', $msg, $cmd, $args);
					};
				};
			};

		} elsif ($cmd eq 'multi') {

			my $resultSet;
			my $resultNode;
			my $resultObject;
			my $index = 0;

			local *node = sub {
				return $resultNode;
			};

			local *count = sub {
				return $index;
			};

			# my sub index {
			# 	my @args = @_;
			# 	if (scalar @args > 1) {
			# 		return CORE::index($args[0], $args[1], $args[2]);
			# 	} else {
			# 		JsonMod_Logger($hash, 1, 'use of \'index()\' as item counter is depraced in \'%s%s\'. Replace with \'count\'.', $cmd, $args);
			# 		return $index;
			# 	};
			# };

			# my sub property {
			local *property = sub {
				my ($propertyPath, $default) = @_;
				#$default //= '';
				return unless (defined($resultObject));
				
				if (ref($resultObject) eq 'HASH' or ref($resultObject) eq 'ARRAY') {
					my $presult = JsonMod::JSON::Path->new($resultObject)->get($propertyPath)->getResultValue();
					if (defined($presult)) {
						if ((ref($presult) eq 'ARRAY') and (scalar(@{$presult}))) {
							return $presult->[0]; # the first hit if many. be gentle ;)
						} elsif ((ref($presult) eq 'HASH') or (ref($presult) eq '')) {
							return $presult;
						};
					};
				};
				return $default if (defined($default));
				return undef;
			};

			# my sub propertyf {
			local *propertyf = sub {
				my ($propertyPath, $default, $format) = @_;
				$format //= '%s';
				my $presult = property($propertyPath, $default);
				if (defined($presult)) {
					return sprintf($format, $presult);
				};
				return undef;
			};

			# my sub jsonPath {
			local *jsonPath = sub {
				my ($jsonPathExpression) = @_;
				# $resultSet = $path->get($jsonPathExpression)->getResultValue() unless (defined($resultSet));
				$resultSet = $path->get($jsonPathExpression)->getResultList() unless (defined($resultSet));
				return $jsonPathExpression;
			};

			# my sub m2 {
			local *m2 = sub {
				my ($jsonPathExpression, $readingName, $readingValue) = @_;
				# print "in m2 $jsonPathExpression, $readingName, $readingValue\n";
				sanitizedSetReading($readingName, $readingValue);
				# $index++;
			};

			# my sub m1 {
			local *m1 = sub {
				my ($jsonPathExpression, $readingName, $readingValue) = @_;

				$warnings = 1;

				if (ref($resultSet) eq 'ARRAY') {
					foreach my $res (@{$resultSet}) {
						$resultNode = $res->[0];
						$resultObject = $res->[1]; # value
						# print "array: $resultNode $resultObject \n";
						# use Data::Dumper;
						# print Dumper $resultObject;
						eval 'm2'.$args; warn $@ if $@;
						$index++;
					};
				};
			};

			{
				local $SIG{__WARN__} = \&logWarnings;
				$warnings = 0;
				eval 'm1'.$args;
				if ($@) {
					my $msg = $@;
					if ($msg =~ m/^(.*)(?:at.*(?:eval|98_JsonMod).*)line (\d+)?/m) {
						JsonMod_Logger($hash, 2, 'error: %s (#%s) in %s%s', $1, $2, $cmd, $args);
					} else {
						JsonMod_Logger($hash, 2, 'error: %s in %s%s', $msg, $cmd, $args);
					};
				};
			};
		} elsif ($cmd eq 'complete') {

			my $index = 0;

			# my sub c1 {
			local *c1 = sub {
				my ($jsonPathExpression) = @_;
				$jsonPathExpression //= '$..*';

				my $resultSet = $path->get($jsonPathExpression)->getResultList();
				#use Data::Dumper;
				#print Dumper $resultSet;
				if (ref($resultSet) eq 'ARRAY') {
					foreach my $res (@{$resultSet}) {
						my $k = $res->[0];
						my $v = $res->[1];
						# we are only interested in the values, not objects or arrays
						if (ref($v) eq '') {
							my @r;
							$k =~ s/^\$//;
					    	while (my $part = (extract_bracketed($k), '[]')[0]) { push @r, $part };
							my $readingName = join('.', @r);
							sanitizedSetReading($readingName, $v) if length($readingName);
						};
					};
				};
			};

			{
				local $SIG{__WARN__} = \&logWarnings;
				eval 'c1'.$args;
				if ($@) {
					my $msg = $@;
					if ($msg =~ m/^(.*)(?:at.*(?:eval|98_JsonMod).*)line (\d+)?/m) {
						JsonMod_Logger($hash, 2, 'error: %s (#%s) in %s%s', $1, $2, $cmd, $args);
					} else {
						JsonMod_Logger($hash, 2, 'error: %s in %s%s', $msg, $cmd, $args);
					};
				};
			};
		};
	};


	# update readings
	if (keys %{$newReadings}) {
		my @newReadings;
		my @oldReadings = split ',', ReadingsVal($name, '.computedReadings', '');
		readingsBeginUpdate($hash);
		foreach my $k (keys %{$newReadings}) {
			#sanitizedSetReading($reading, $value);
			readingsBulkUpdate($hash, $k, $newReadings->{$k});
			push @newReadings, $k;
		};
		# reading is not used anymore
		foreach my $k (keys %{$oldReadings}) {
			readingsDelete($hash, $k) if ($oldReadings->{$k} == 0 and any { $_ eq $k} @oldReadings);
		};
		readingsBulkUpdate($hash, '.computedReadings', join ',', @newReadings);
		readingsEndUpdate($hash, 1);
	};

};

sub JsonMod_StartTimer {
	my ($hash) = @_;
	my $name = $hash->{'NAME'};

	my $cron = ${$hash->{'CONFIG'}->{'CRON'}};
	my @t = localtime(Time::HiRes::time());
	$t[4] += 1;
	$t[5] += 1900;
	my @r = $hash->{'CRON'}->next($cron, @t);
	my $ts = timelocal(0, $r[0], $r[1], $r[2], $r[3] -1, $r[4] -1900);
	$hash->{'NEXT'} = sprintf('%04d-%02d-%02d %02d:%02d:%02d', $r[4], $r[3], $r[2], $r[1], $r[0], 0);
	JsonMod_Logger($hash, 4, 'next request: %04d.%02d.%02d %02d:%02d:%02d', $r[4], $r[3], $r[2], $r[1], $r[0], 0);
	InternalTimer($ts, \&JsonMod_DoTimer, $hash);
	return;
};

sub JsonMod_StopTimer {
	my ($hash) = @_;
	$hash->{'NEXT'} = 'NEVER';
	RemoveInternalTimer($hash, \&JsonMod_DoTimer);
	RemoveInternalTimer($hash, \&JsonMod_ApiRequest);
	return;
};

sub JsonMod_DoTimer {
	my ($hash) = @_;
	JsonMod_Logger($hash, 4, 'start request');
	JsonMod_StartTimer($hash);
	# request in flight ? cancel
	return if ($hash->{'CONFIG'}->{'IN_REQUEST'});
	JsonMod_ApiRequest($hash);
	return;
};

sub JsonMod_ApiRequest {
	my ($hash) = @_;
	my $name = $hash->{'NAME'};

	# prevent simultaneous request
	return if ($hash->{'CONFIG'}->{'IN_REQUEST'});
	$hash->{'CONFIG'}->{'IN_REQUEST'} = 1;

	my $source = $hash->{'CONFIG'}->{'SOURCE'};

	# abs: file:/// or file:/
	# rel: file:
	# non-comform file:// -> rel file:
	if ($source =~ m/^file:[\/]{2}(.+)|^file:(.+)/) {
		$hash->{'CONFIG'}->{'IN_REQUEST'} = 0;
		$hash->{'API_LAST_RES'} = Time::HiRes::time();
		
		my $filename = $1//$2;
		# say "filename: $filename";
		if (-e $filename) {
			my $data;
			open(my $fh, '<', $filename) or do {
				$hash->{'SOURCE'} = sprintf('%s (%s)', $filename,  (stat $filename)[7]);
				$hash->{'API_LAST_MSG'} = $!;
				return;
			};
			{
				local $/;
				$data = <$fh>;
			};
			close($fh);
			my $json = JsonMod::JSON::StreamReader->new()->parse($data);
			JsonMod_DoReadings($hash, $json);
			$hash->{'SOURCE'} = sprintf('%s (%s)', $filename,  (stat $filename)[7]);
			$hash->{'API_LAST_MSG'} = 200;
			return;
		} else {
			$hash->{'SOURCE'} = sprintf('%s', $filename);
			$hash->{'API_LAST_MSG'} = 404;
			return;
		};
	};

	# system: e.g. system://curl https://www.google.de
	# must return valid json via pipe
	if ($source =~ m/^system:\/\/(.+)/) {
		my $cmd = $1;
		my ($wtr, $rdr);  # pipes r+w
		my $err = gensym();  # err

		my $pid = open3($wtr, $rdr, $err, $cmd);
		my $name = "JsonMod-System-$hash->{NAME}";

		my ($data, $error);

		my $select_rdr = {
			FD => fileno($rdr),
			NAME => $hash->{NAME}, # required in case fhem.pl executes delete
			directReadFn => sub {
				my $r = @_;
				my $res;
        		my $len = sysread $rdr, $res, 8192;
				if ($len == 0) {
					# reap zombie and retrieve exit status
    				waitpid( $pid, 0 );
    				my $child_exit_status = $?;
					# my $child_exit_status = $? >> 8;
					delete $selectlist{$name};
					# delete $selectlist{$name.'-err'};
					my $param = {
						hash => $hash,
						cron =>	$hash->{'CONFIG'}->{'CRON'},
						code => $child_exit_status,
					};
					return JsonMod_ApiResponse($param, $error, $data);
				} else {
					$data .= $res;
				}
			}
		};
		$selectlist{$name} = $select_rdr;

		# my $select_err = {
		# 	FD => fileno($err),
		# 	directReadFn => sub {
		# 		my $r = @_;
		# 		my $res;
        # 		my $len = sysread $err, $res, 8192;
		# 		# EOF
		# 		if ($len == 0) {
		# 			# reap zombie and retrieve exit status
    	# 			waitpid( $pid, 0 );
    	# 			my $child_exit_status = $?;
		# 			# my $child_exit_status = $? >> 8;
		# 			delete $selectlist{$name.'-rdr'};
		# 			delete $selectlist{$name.'-err'};
		# 			my $param = {
		# 				hash => $hash,
		# 				cron =>	$hash->{'CONFIG'}->{'CRON'},
		# 				code => $child_exit_status,
		# 			};
		# 			JsonMod_ApiResponse($param, $e, $data);
		# 		} else {
		# 			$e .= $res;
		# 		}
		# 	}
		# };
		# $selectlist{$name.'-err'} = $select_err;
		return;
	}

	my $param = {
		'hash'		=>		$hash,
		'cron'		=>		$hash->{'CONFIG'}->{'CRON'},
		'callback'	=>		\&JsonMod_ApiResponse
	};

	my @sec;
	# fill in SECRET if available
	$source =~ s/(\[.+?\])/(exists($hash->{'CONFIG'}->{'SECRET'}->{substr($1,1,length($1)-2)}) and push @sec, $hash->{'CONFIG'}->{'SECRET'}->{substr($1,1,length($1)-2)})?${$hash->{'CONFIG'}->{'SECRET'}->{substr($1,1,length($1)-2)}}:$1/eg and 
		$param->{'hideurl'} = 1;
	$param->{'url'} = $source;
	$param->{'sec'} = \@sec;

	my $header = AttrVal($name, 'httpHeader', '');
	if ($header) {
		$header =~ s/(\[.+?\])/(exists($hash->{'CONFIG'}->{'SECRET'}->{substr($1,1,length($1)-2)}))?${$hash->{'CONFIG'}->{'SECRET'}->{substr($1,1,length($1)-2)}}:$1/eg;
	};
	$header .= "\r\nAccept: application/json\r\nAccept-Charset: utf-8, iso-8859-1" unless ($header =~ m'Accept: application/json');
	$param->{'header'} = $header;
	#$param->{'loglevel'} = AttrVal($name, 'verbose', 3);
	$param->{'NAME'} = $name;
	$param->{'timeout'} = AttrVal($name, 'httpTimeout', 30);
	HttpUtils_NonblockingGet($param);
	return;
};

sub JsonMod_ApiResponse {
	my ($param, $err, $data) = @_;
	my $hash = $param->{'hash'};

	# cron settings changed while doing request. discard silently
	return if ($param->{'cron'} ne $hash->{'CONFIG'}->{'CRON'});
	# check for error
	# TODO
	$hash->{'CONFIG'}->{'IN_REQUEST'} = 0;
	$hash->{'API_LAST_RES'} = Time::HiRes::time();

	# delete secrets from the answering url if any
	my $url = $param->{'url'} //= '';
	foreach (@{$param->{'sec'}}) {
		next if (ref($_) ne 'SCALAR');
		$url =~ s/(\Q${$_}\E)/'X' x length($1)/e;
	};

	$hash->{'SOURCE'} = sprintf('%s (%s)', $url, $param->{'code'} //= '');
	$hash->{'API_LAST_MSG'} = $param->{'code'} //= 'failed';

	# my sub doError {
	local *doError = sub {
		my ($msg) = @_;
		$hash->{'API_LAST_MSG'} = $msg;
		my $next = Time::HiRes::time() + 600;
		#$hash->{'API_NEXT_REQ'} = $next;
		return InternalTimer($next, \&JsonMod_ApiRequest, $hash);
	};

	if ($err) {
		JsonMod_Logger($hash, 2, 'http request error: %s', $err);
		return doError($err);
	};

	my ($content, $encoding);
	foreach my $header (split /\r\n/, $param->{'httpheader'} //= '') {
		last if (($content, $encoding) = $header =~ m/^Content-Type:\s([^;]+).*charset=(.+)/);
	};

	# RESPONSE Content-Type:... charset=
	#
	# we need to care only if the result is NOT utf8.
	# if it is utf8 then StreamReader will take care and
	# convert it and set the utf8 flag if, and only if, 
	# non ascii code points are seen for each individual
	# element (keys, values) of the resulting object.
	# As a result all string functions like length and so on
	# are able to operate correct.
	# 
	# at each 'exit' to the outer world we need to check then
	# bool = utf8::is_utf8(string)
	# if true: utf8::encode(string);


	my $enc = Encode::find_encoding($encoding);
	$enc = (defined($enc))?$enc->name():'utf-8-strict'; # precaution required in case of invalid respone
	Encode::from_to($data, $encoding, 'UTF-8') unless ($enc eq 'utf-8-strict');
	JsonMod_Logger($hash, 4, 'api encoding is %s, designated encoder is %s', $encoding, $enc);

	# JsonP handling
	my ($jsonP, $remain, $jsFn) = extract_codeblock($data, '()', '(?s)^[^([{]+');
	if ($jsonP and $jsonP =~ m/^\((.*)\)$/ and $1) {
		$data = $1;
	};

	JsonMod_Logger($hash, 5, 'start json decoding');
	my $rs = JsonMod::JSON::StreamReader->new()->parse($data);
	if (not $rs or ((ref($rs) ne 'HASH') and ref($rs) ne 'ARRAY')) {
		return doError('invalid server response');
	};
	JsonMod_Logger($hash, 5, 'finished json decoding');

	#use Memory::Usage;
	#my $mu = Memory::Usage->new();
	#$mu->record('before');
	JsonMod_Logger($hash, 5, 'start do readings');
	JsonMod_DoReadings($hash, $rs);
	JsonMod_Logger($hash, 5, 'finished do readings');
	#$mu->record('after');
	#$mu->dump();

	return;
};

sub JsonMod_Logger {
	my ($hash, $verbose, $message, @args) = @_;
	my $name = $hash->{'NAME'};
	# Unicode support for log files
	utf8::encode($message) if utf8::is_utf8($message);
	for my $i (0 .. scalar(@args)) {
		utf8::encode($args[$i]) if utf8::is_utf8($args[$i]);
	};
	# https://forum.fhem.de/index.php/topic,109413.msg1034685.html#msg1034685
	no if $] >= 5.022, 'warnings', qw( redundant missing );
	no warnings "uninitialized";
	Log3 ($name, $verbose, sprintf('[%s] '.$message, $name, @args));
	return;
};


###############################################################################
# credits to David Oswald
# http://cpansearch.perl.org/src/DAVIDO/JSON-Tiny-0.58/lib/JSON/Tiny.pm
package JsonMod::JSON::StreamWriter;

use strict;
use warnings;
use utf8;
use B;

my ($escape, $reverse);

BEGIN {
	eval "use Cpanel::JSON::XS;1;" or do {
		if (not $main::_JSON_PP_WARN) {
			main::Log3 (undef, 3, sprintf('json [%s] is pure perl. Consider installing Cpanel::JSON::XS', __PACKAGE__));
			$main::_JSON_PP_WARN = 1;
		};			
	};
};

BEGIN {
	%{$escape} =  (
		'"'     => '"',
		'\\'    => '\\',
		'/'     => '/',
		'b'     => "\x08",
		'f'     => "\x0c",
		'n'     => "\x0a",
		'r'     => "\x0d",
		't'     => "\x09",
		'u2028' => "\x{2028}",
		'u2029' => "\x{2029}"
	);
	%{$reverse} = map { $escape->{$_} => "\\$_" } keys %{$escape};
	for(0x00 .. 0x1f) {
		my $packed = pack 'C', $_;
		$reverse->{$packed} = sprintf '\u%.4X', $_ unless defined $reverse->{$packed};
	};
};

sub new {
	my $class = shift;
	my $self = {};
	bless $self, $class;
	return $self;
};

sub parse {
	my ($self, $data) = @_;
	my $stream;

	# use Cpanel::JSON::XS if available
	my $xs = eval 'Cpanel::JSON::XS::encode_json($data)';
	return $xs if ($xs);

	if (my $ref = ref $data) {
		use Encode;
		return Encode::encode_utf8($self->addValue($data));
	};
};

sub addValue {
	my ($self, $data) = @_;
	if (my $ref = ref $data) {
		return $self->addONode($data) if ($ref eq 'HASH');
		return $self->addANode($data) if ($ref eq 'ARRAY');
	};
	return 'null' unless defined $data;
	return $data
		if B::svref_2object(\$data)->FLAGS & (B::SVp_IOK | B::SVp_NOK)
		# filter out "upgraded" strings whose numeric form doesn't strictly match
		&& 0 + $data eq $data
		# filter out inf and nan
		&& $data * 0 == 0;
	# String
	return $self->addString($data);
};

sub addString {
	my ($self, $str) = @_;
	$str =~ s!([\x00-\x1f\x{2028}\x{2029}\\"/])!$reverse->{$1}!gs;
	return "\"$str\"";
};

sub addONode {
	my ($self, $object) = @_;
	my @pairs = map { $self->addString($_) . ':' . $self->addValue($object->{$_}) }
		sort keys %$object;
	return '{' . join(',', @pairs) . '}';
};

sub addANode {
	my ($self, $array) = @_;
	return '[' . join(',', map { $self->addValue($_) } @{$array}) . ']';
};

# static, sanitize a json message

###############################################################################
# credits to David Oswald
# http://cpansearch.perl.org/src/DAVIDO/JSON-Tiny-0.58/lib/JSON/Tiny.pm
package JsonMod::JSON::StreamReader;

use strict;
use warnings;
use utf8;

BEGIN {
	eval "use Cpanel::JSON::XS;1;" or do {
		if (not $main::_JSON_PP_WARN) {
			main::Log3 (undef, 3, sprintf('json [%s] is pure perl. Consider installing Cpanel::JSON::XS', __PACKAGE__));
			$main::_JSON_PP_WARN = 1;
		};			
	};
};

sub new {
	my $class = shift;
	my $self = {};
	$self->{'ESCAPE'} = {
		'"'     => '"',
		'\\'    => '\\',
		'/'     => '/',
		'b'     => "\x08",
		'f'     => "\x0c",
		'n'     => "\x0a",
		'r'     => "\x0d",
		't'     => "\x09",
		'u2028' => "\x{2028}",
		'u2029' => "\x{2029}"
	};
	bless $self, $class;
	return $self;
};

sub parse {
	my ($self, $in) = @_;
	my $TRUE = 1;
	my $FALSE = 0;

	local *exception = sub {
		my ($e) = @_;
		# Leading whitespace
		m/\G[\x20\x09\x0a\x0d]*/gc;
		# Context
		my $context = 'Malformed JSON: ' . shift;
		if (m/\G\z/gc) { 
		  $context .= ' before end of data';
		} else {
		  my @lines = split "\n", substr($_, 0, pos);
		  $context .= ' at line ' . @lines . ', offset ' . length(pop @lines || '');
		};
		die "$context";
	};

	local *_decode_string = sub {
		my $pos = pos;

		# Extract string with escaped characters
		m!\G((?:(?:[^\x00-\x1f\\"]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4})){0,32766})*)!gc; # segfault on 5.8.x in t/20-mojo-json.t
		my $str = $1;

		# Invalid character
		unless (m/\G"/gc) { #"
			exception('Unexpected character or invalid escape while parsing string')
			if m/\G[\x00-\x1f\\]/;
			exception('Unterminated string');
		};

		# Unescape popular characters
		if (index($str, '\\u') < 0) {
			#no warnings;
			$str =~ s!\\(["\\/bfnrt])!$self->{'ESCAPE'}->{$1}!gs;
			return $str;
		};

		# Unescape everything else
		my $buffer = '';
		while ($str =~ m/\G([^\\]*)\\(?:([^u])|u(.{4}))/gc) {
			$buffer .= $1;
			# Popular character
			if ($2) { 
				$buffer .= $self->{'ESCAPE'}->{$2};
			} else { # Escaped
				my $ord = hex $3;
				# Surrogate pair
				if (($ord & 0xf800) == 0xd800) {
					# High surrogate
					($ord & 0xfc00) == 0xd800
						or pos($_) = $pos + pos($str), exception('Missing high-surrogate');
					# Low surrogate
					$str =~ m/\G\\u([Dd][C-Fc-f]..)/gc
						or pos($_) = $pos + pos($str), exception('Missing low-surrogate');
					$ord = 0x10000 + ($ord - 0xd800) * 0x400 + (hex($1) - 0xdc00);
				};
				# Character
				$buffer .= pack 'U', $ord;
			};
		};
		# The rest
		return $buffer . substr $str, pos $str, length $str;
	};

	local *_decode_object = sub {
		my %hash;
		until (m/\G[\x20\x09\x0a\x0d]*\}/gc) {
			# Quote
			m/\G[\x20\x09\x0a\x0d]*"/gc
			or exception('Expected string while parsing object');
			# Key
			my $key = _decode_string();
			# Colon
			m/\G[\x20\x09\x0a\x0d]*:/gc
			or exception('Expected colon while parsing object');
			# Value
			$hash{$key} = _decode_value();
			# Separator
			redo if m/\G[\x20\x09\x0a\x0d]*,/gc;
			# End
			last if m/\G[\x20\x09\x0a\x0d]*\}/gc;
			# Invalid character
			exception('Expected comma or right curly bracket while parsing object');
		};
		return \%hash;
	};

	local *_decode_array = sub {
		my @array;
		until (m/\G[\x20\x09\x0a\x0d]*\]/gc) {
			# Value
			push @array, _decode_value();
			# Separator
			redo if m/\G[\x20\x09\x0a\x0d]*,/gc;
			# End
			last if m/\G[\x20\x09\x0a\x0d]*\]/gc;
			# Invalid character
			exception('Expected comma or right square bracket while parsing array');
		};
		return \@array;
	};

	local *_decode_value = sub {
		# Leading whitespace
		m/\G[\x20\x09\x0a\x0d]*/gc;
		# String
		return _decode_string() if m/\G"/gc;
		# Object
		return _decode_object() if m/\G\{/gc;
		# Array
		return _decode_array() if m/\G\[/gc;
		# Number 
		# jh: failed with 0123 
		#my ($i) = /\G([-]?(?:0(?!\d)|[1-9][0-9]*)(?:\.[0-9]*)?(?:[eE][+-]?[0-9]+)?)/gc;
		my ($i) = /\G(?=.)([+-]?([0-9]*)(\.([0-9]+))?)([eE][+-]?\d+)?/gc;
		return 0 + $i if defined $i;
		# True
		{ no warnings;
			return $TRUE if m/\Gtrue/gc;
			# False
			return $FALSE if m/\Gfalse/gc;
		};
		# Null
		return undef if m/\Gnull/gc;  ## no critic (return)
		# Invalid character
		exception('Expected string, array, object, number, boolean or null');
	};

	local *_decode = sub {
		my $valueref = shift;
		eval {
			# Missing input
			die "Missing or empty input\n" unless length( local $_ = shift );
			# UTF-8
			$_ = eval { Encode::decode('UTF-8', $_, 1) } unless shift;
			die "Input is not UTF-8 encoded\n" unless defined $_;
			# Value
			$$valueref = _decode_value();
			# Leftover data
			return m/\G[\x20\x09\x0a\x0d]*\z/gc || exception('Unexpected data');
		} ? return undef : chomp $@;
		return $@;
	};

	# use Cpanel::JSON::XS if available
	my $xs = eval 'Cpanel::JSON::XS::decode_json($in)';
	return $xs if ($xs);

	my $err = _decode(\my $value, $in, 0);
	return defined $err ? $err : $value;
};

# https://github.com/json-path/JsonPath
# https://support.smartbear.com/alertsite/docs/monitors/api/endpoint/jsonpath.html#examples

package JsonMod::JSON::Path;

use strict;
use warnings;
use utf8;

sub new {
	my ($class, $o) = @_;
	my $self = bless {}, $class;
	$self->{'root'} = JsonMod::JSON::Path::Node->new($o);
	return $self;
};

# valid:
# $..
# $.
# $[property]
# property
# invalid ubt accepted:
# ..property
sub get {
	my ($self, $path) = @_;
	my $query = JsonMod::JSON::Path::Query->new();
	#print "get $path\n";
	$path =~ s/^\$//;
	$self->{'root'}->get($path, '$', $query);
	return $query;
};

sub DESTROY {
	my ($self) = @_;
	#print "DESTROY $self\n";
	$self->{'root'}->release() if defined($self->{'root'});
	delete $self->{'root'};	
};

package JsonMod::JSON::Path::Node;

use strict;
use warnings;
use utf8;
use Text::Balanced qw ( extract_codeblock extract_delimited );
use Scalar::Util qw( blessed );

sub new {
	my ($class, $o, $root) = @_;

	# special case for JSON 'true' / 'false'
	$o = "$o" if (blessed($o) and blessed($o) eq 'JSON::PP::Boolean');
	my $t = ref($o);
	if ($t eq 'HASH') {
		return JsonMod::JSON::Path::HNode->new($o, $root);
	} elsif ($t eq 'ARRAY') {
		return JsonMod::JSON::Path::ANode->new($o, $root);
	} elsif ($t eq '') {
		return JsonMod::JSON::Path::VNode->new($o, $root);
	};
};

sub getNextProperty {
	my ($self, $path) = @_;
	
	my ($property, $deep);
	$deep = $path =~ s/^\.\.//;
	$path =~ s/^([^\.])/\.$1/;
	($path =~ s/^\.([^\[\.]+)// and $property = $1); # .property
	if (not defined($property)) {
		$property = extract_codeblock($path, '[]', '\.') and 
			$property = substr($property, 1, (length($property)-2));
		if (defined($property) and ord($property) eq ord(qw ( ' ))) {
			$property = extract_delimited($property, qw ( ' )) 
				and $property = substr($property, 1, (length($property)-2));
		};
	};
	return ($path, $property, $deep);
};

sub addRootNode {
	my ($self, $o, $root) = @_;
	if (not $root) {
		$self->{'root'} = $self;
	} else {
		$self->{'root'} = $root;
	};
	return $self;
};

sub release {
	my ($self) = @_;
	if (ref($self->{'child'}) eq 'HASH') {
		foreach my $k (keys %{$self->{'child'}}) {
			$self->{'child'}->{$k}->release() if defined($self->{'child'}->{$k});
			delete $self->{'child'}->{$k};
		};
	};
	delete $self->{'root'};
};

sub DESTROY {
	my ($self) = @_;
	#print "DESTROY $self\n";
};

package JsonMod::JSON::Path::HNode;

use strict;
use warnings;
use utf8;
use parent -norequire, qw( JsonMod::JSON::Path::Node );

sub new {
	my ($class, $o, $root) = @_;

	my $self = bless {}, $class;
	#print "HNode $self\n";
	$self->addRootNode($o, $root);

	foreach my $k (keys %{$o}) {
		$self->{'child'}->{$k} = JsonMod::JSON::Path::Node->new($o->{$k}, $self->{'root'});
	};
	
	return $self;
};

sub get {
	my ($self, $path, $normalized, $query) = @_;
	my ($property, $deep);
	#print "hash1 [$path] [$property] [$normalized]\n";
	($path, $property, $deep) = $self->getNextProperty($path);
	#print "hash2 [$path] [$property] [$normalized]\n";

	if ((ord($property) eq ord('*')) or $deep) {
		my @childList = keys (%{$self->{'child'}});
		foreach my $child (@childList) {
			$self->getSingle($child, $property, $deep, $path, $normalized, $query);
		};
	} else {
		$self->getSingle($property, $property, $deep, $path, $normalized, $query);
	};
};

sub getSingle {
	my ($self, $node, $property, $deep, $path, $normalized, $query) = @_;
	#print "hash single: $node, $property, $deep, $path, $normalized\n";

	#$path = "..$property$path" if $deep;
	if ((ord($property) eq ord('*')) or (($node eq $property) and exists($self->{'child'}->{$node}))) {
		if (not $path) {
			#print "hash result $normalized.[$node]\n";
			$query->addResult($normalized."[$node]", $self->{'child'}->{$node}->getValue());
		};
		#$path = "..$property$path" if $deep;
		if ($path and 
			(not ref($self->{'child'}->{$node}) eq 'JsonMod::JSON::Path::VNode')) {
			$self->{'child'}->{$node}->get($path, $normalized."[$node]", $query); 
		};
	};
	if ($deep) { #and (not ref($self->{'child'}->{$node}) eq 'JsonMod::JSON::Path::VNode')) {
		$path = "..$property$path";
		$self->{'child'}->{$node}->get($path, $normalized."[$node]", $query); 
	};
};

sub getValue {
	my ($self) = @_;
	my $val = {};
	foreach my $c (keys %{$self->{'child'}}) {
		$val->{$c} = $self->{'child'}->{$c}->getValue();
	}
	return $val;
};

package JsonMod::JSON::Path::ANode;

use strict;
use warnings;
use utf8;
use parent -norequire, qw( JsonMod::JSON::Path::Node );

sub new {
	my ($class, $o, $root) = @_;

	my $self = bless {}, $class;
	#print "ANode $self\n";
	$self->addRootNode($o, $root);

	for my $i (0 .. scalar(@{$o}) -1) {
		$self->{'child'}->{$i} = JsonMod::JSON::Path::Node->new($o->[$i], $self->{'root'});
	};

	return $self;
};

sub get {
	my ($self, $path, $normalized, $query) = @_;
	my ($property, $deep);
	#print "array1 [$path] [$property] [$normalized]\n";
	($path, $property, $deep) = $self->getNextProperty($path);
	#print "array2 [$path] [$property] [$normalized]\n";

	if (ord($property) eq ord('?')) {
		my $filter = JsonMod::JSON::Path::Query::Filter->new($self)->get($property);
		foreach my $child (sort { $a <=> $b } @{$filter}) {
			$self->getSingle($child, $child, $deep, $path, $normalized, $query);
			#$self->{'child'}->{$child}->get($path, $normalized, $query);
		};
	} elsif ((ord($property) eq ord('*')) or $deep) {
		my @childList = sort { $a <=> $b } keys (%{$self->{'child'}});
		foreach my $child (@childList) {
			$self->getSingle($child, $property, $deep, $path, $normalized, $query);
		};
	} elsif ($property =~ m/^\d+$/) {
		$self->getSingle($property, $property, $deep, $path, $normalized, $query);
	} elsif ($property =~ m/^\s*\d+\s*,\s*\d+\s*(?:,\s*\d+\s*)*$/) {	# [n,n(,n)]

	} else {
		die ("JsonPath filter property $property failure");
	};
};

sub getSingle {
	my ($self, $node, $property, $deep, $path, $normalized, $query) = @_;
	#print "array single: $node, $property, $deep, $path, $normalized\n";

	#$path = "..$property$path" if $deep;
	if ((ord($property) eq ord('*')) or (($node eq $property) and exists($self->{'child'}->{$node}))) {
		if (not $path) {
			#print "array result $normalized.[$node]\n";
			$query->addResult($normalized."[$node]", $self->{'child'}->{$node}->getValue());
		};
		#$path = "..$property$path" if $deep;
		if ($path and 
			(not ref($self->{'child'}->{$node}) eq 'JsonMod::JSON::Path::VNode')) {
			$self->{'child'}->{$node}->get($path, $normalized."[$node]", $query); 
		};
	};
	if ($deep) { #and (not ref($self->{'child'}->{$node}) eq 'JsonMod::JSON::Path::VNode')) {
		$path = "..$property$path";
		$self->{'child'}->{$node}->get($path, $normalized."[$node]", $query); 
	};
};

sub getValue {
	my ($self) = @_;
	my $val = [];
	my @childList = sort { $a <=> $b } keys (%{$self->{'child'}});
	foreach my $c (@childList) {
		push @{$val}, $self->{'child'}->{$c}->getValue();
	}
	return $val;
};

package JsonMod::JSON::Path::VNode;

use strict;
use warnings;
use utf8;
use parent -norequire, qw( JsonMod::JSON::Path::Node );

sub new {
	my ($class, $o, $root) = @_;

	my $self = bless {}, $class;
	#print "VNode $self\n";
	$self->addRootNode($o, $root);

	if (not $root) {
		$root = $self->{'root'} = $o;
	} else {
		$self->{'root'} = $root;
	};
	$self->{'child'} = $o;
	return $self;
};

sub get {
	my ($self, $path, $normalized) = @_;
	my ($property, $deep);
	($path, $property, $deep) = $self->getNextProperty($path);
};

sub getValue {
	my ($self) = @_;
	return $self->{'child'};
};

package JsonMod::JSON::Path::Query;

use strict;
use warnings;
use utf8;

sub new {
	my ($class) = @_;
	my $self = bless {}, $class;
	$self->{'nList'} = [];
	$self->{'vList'} = [];
	return $self;
};

sub addResult {
	my ($self, $normalized, $value) = @_;
	push @{$self->{'nList'}}, $normalized;
	push @{$self->{'vList'}}, $value;
};

sub getResultNormalized {
	my ($self) = @_;
	foreach my $e (@{$self->{'nList'}}) {
		print "$e\n";
	};
};

sub getResultValue {
	my ($self) = @_;
	return $self->{'vList'};
};

sub getResultNormVal {
	my ($self) = @_;
	for my $i (0 .. scalar(@{$self->{'vList'}}) -1) {
		print "$self->{'nList'}->[$i]\t$self->{'vList'}->[$i]\n";
	};
};

sub getResultList {
	my ($self) = @_;
	my $result = [];
	for my $i (0 .. scalar(@{$self->{'vList'}}) -1) {
		push @{$result}, [$self->{'nList'}->[$i], $self->{'vList'}->[$i]];
	};
	return $result;
};

package JsonMod::JSON::Path::Query::Filter;

use strict;
use warnings;
use utf8;
use List::Util qw( any );
use Text::Balanced qw ( extract_codeblock extract_delimited );

sub new {
	my ($class, $o) = @_;
	my $self = bless {}, $class;
	$self->{'nList'} = [];
	$self->{'vList'} = [];
	$self->{'node'} = $o;
	return $self;
};

sub get {
	my ($self, $filterText) = @_;
	my $filter;
	$filter = extract_codeblock($filterText, '()', '\?') 
		and $filter = substr($filter, 1, (length($filter)-2));
	die('wrong syntax for JsonPath filter: '.$filterText) unless length($filter);

	my ($delim, $list, $idx) = (0, 0, 0);
	my @parts;
	# foreach my $c (split '', $filter) {
	# 	$delim ^= 1 if (ord($c) == ord(q{'}));
	# 	$list += 1 if (ord($c) == ord('[') and $delim == 0);
	# 	$list -= 1 if (ord($c) == ord(']') and $delim == 0);
	# 	die('unbalanced square brackets in JsonPath filter: '.$filterText) if ($list < 0);
	# 	$idx++ if (any {$c eq $_)} (' ', '')) and $delim == 0 and $list == 0);
	# 	$parts[$idx] .= $c if (ord($c) != ord(' ') or $list != 0 or $delim == 1);
	# };

	my @operators = (
		'\s*==\s*',
		'\s*!=\s*',
		'\s*<=\s*',
		'\s*<\s*',
		'\s*>=\s*',
		'\s*>\s*',
		'\s+in\s+',
		'\s*=~\s*',
	);
	my $rex = join('|', @operators);
	$rex = qr/^($rex)/;

	while (defined(my $c = substr($filter, 0, 1))) {
		if ($c eq q{'}) {
			$delim ^= 1;
			#substr($filter, 0, 1, '');
			#$c = '';
		};
		if ($c eq '[' and $delim == 0) {
			$list += 1;
			#substr($filter, 0, 1, '');
			#$c = '';
		};
		if ($c eq ']' and $delim == 0) {
			$list -= 1;
			#substr($filter, 0, 1, '');
			#$c = '';
		};
		die('unbalanced square brackets in JsonPath filter: '.$filterText) if ($list < 0);
		#next unless (length($c));

		if ($delim == 0 and $list == 0 and $filter =~ m/$rex/sip) {
			$parts[2] = substr($filter, length($1));
			$parts[1] = $1;
			$parts[1] =~ s/^\s+|\s+$//g;
			last;
		};

		$parts[0] .= substr($filter, 0, 1, '');

	};
	die('unbalanced square brackets in JsonPath filter: '.$filterText) if ($list != 0);
	die('wrong filter expression in JsonPath filter: '.$filterText) if (scalar(@parts) != 3 
		or not defined($parts[0])
		or not defined($parts[1])
		or not defined($parts[2]));

	return $self->filter($parts[0], $parts[1], $parts[2]);
};

sub filter {
	my ($self, $left, $operater, $right) = @_;

	my $result = [];

	# fn ref as test for: numeric, string, list
	my ($a, $b, @a, @b);
	my $dispatch = {
		'=='		=>	[sub {$a == $b}, sub {$a eq $b}, undef],
		'!='		=>	[sub {$a != $b}, sub {$a ne $b}, undef],
		'<'			=>	[sub {$a < $b}, sub {$a lt $b}, undef],
		'<='		=>	[sub {$a <= $b}, sub {$a le $b}, undef],
		'>'			=>	[sub {$a > $b}, sub {$a gt $b}, undef],
		'>='		=>	[sub {$a >= $b}, sub {$a ge $b}, undef],
		'in'		=>	[undef, undef, sub {any {$_ eq $a} @b}],
		'=~'		=>	[undef, sub {$a =~ m/$b/}, undef],
	};

	# todo: test if right is filter!!!

	# right type == numeric, string, list / operater as string / function pointer
	#printf("l:[%s], o:[%s], r:[%s]\n", $left, $operater, $right);
	my ($fnt, $fn);
	($right =~ m/([+-]?\d+(?:[,.]\d+)?)/ and $fnt = 0) or 	# numeric
		($right =~ m/^(?:['](.*)['])$/ and $fnt = 1) or 						# string
		($right =~ m/^(?:[\[](.*)[\]])$/ and $fnt = 2);							# list
	$right = $1	if (defined($fnt));
	$fn = exists($dispatch->{$operater})?$dispatch->{$operater}->[$fnt]:undef;
	if ($fn) {
		# run query
		my $filterpath = $left;
		my $queryNode;
		if ($filterpath =~ s/^([\$\@])/[*]/) {
			$queryNode = $self->{'node'} if ($1 eq '@');
			$queryNode = $self->{'node'}->{'root'} if ($1 eq '$');
		} else {
			die("JsonPath filter '$left' must start with \@. or \$.");
		};
		my $filter = JsonMod::JSON::Path::Query->new();
		my $fltNormalized = '';  # relative to actual node
		$queryNode->get($filterpath, $fltNormalized, $filter);
		my $list = $filter->getResultList();

		# numeric or string
		if ($fnt == 0 or $fnt == 1) {
			foreach my $e (@{$list}) {
				$a = $e->[1] //= ''; # -> val, undef possible because JSON NULL
				$b = $right;
				if ($fn->()) { # call the test
					my $r = extract_codeblock($e->[0], '[]');
					push @{$result}, substr($r, 1, length($r) - 2); # remove []
				};
			};
		# list
		} elsif ($fnt == 2) {
			foreach (split /,/, $right) {
				s/^\s*'|^\s+|'\s+|'\s*$//g;
				push @b, $_;
			};
			foreach my $e (@{$list}) {
				$a = $e->[1] //= ''; # -> val
				if ($fn->()) { # call the test
					my $r = extract_codeblock($e->[0], '[]');
					push @{$result}, substr($r, 1, length($r) - 2); # remove []
				};
			};
		};
	};

	return $result;
};

sub DESTROY {
	my ($self) = @_;
	delete $self->{'node'};
};

package JsonMod::Cron;

use strict;
use warnings;
use utf8;
use Time::Local qw ( timelocal );

no warnings qw( experimental::lexical_subs );

# static and helper
sub normalizeTime {
	my ($m, $h, $d) = @_;
	$d //= 0;
	if ($m > 59) { $h += int($m / 60); $m %= 60; };
	if ($h > 23) { $d += int($h / 24); $h %= 24; };
	return ($m, $h, $d);
};

sub normalizeDate {
	my ($d, $m, $y, $o) = @_;
	$o //= 0;
	my $time = timelocal(0, 0, 12, $d, $m -1, $y -1900);
	$time += $o * 86400;
	my @t = localtime($time);
	# plus DST, wday (SUN=0..6), yday (0..364|5)
	return ($t[3], $t[4] +1, $t[5] +1900, $t[8], $t[6], $t[7]); 
};

# class
sub new {
	my ($class) = @_;
	my $self = {};
	
	bless $self, $class;
	return $self;
};

sub setCron {
	my ($self, $cron) = @_;
	@{$self->{'CRONLIST'}} = split / /, $cron //= '';
	return if (scalar @{$self->{'CRONLIST'}} != 5);

};

sub parseMinuteEntry {
	my ($self, $in, $now) = @_;
	my ($res, $start, $stop, $step);

	($step) = ($in =~ m/\/([0-9]|[0-5][0-9])$/);
	($start, $stop) = ($in =~ m/^([*]|[0-9]|[0-5][0-9])(?:-([0-9]|[0-5][0-9]))?(?:\/(?:[0-9]|[0-5][0-9]))?$/);
	return if (not defined($start) or ($start eq '*' and defined($stop))); # syntax error

	$stop = (defined($step) or ($start eq '*'))?59:$start if (not defined($stop));
	$start = 0 if $start eq '*';
	return if ($start > $stop); # syntax error
	return $start if ($now  < $start); # literal start

	$res = $step //= 1;
	$res = $res - (((($now - $start) % 60) + $res) % $res);
	$res = $now + $res;
	
	return $start + 60 if ($res > $stop); # carry over
	return $res; # regular next
};

sub parseHourEntry {
	my ($self, $in, $now) = @_;
	my ($res, $start, $stop, $step);

	($step) = ($in =~ m/\/([0-9]|[0,1][0-9]|2[0-3])$/);
	($start, $stop) = ($in =~ m/^([*]|[0-9]|[0,1][0-9]|2[0-3])(?:-([0-9]|[0,1][0-9]|2[0-3]))?(?:\/(?:[*]|[0-9]|[0,1][0-9]|2[0-3]))?$/);
	return if (not defined($start) or ($start eq '*' and defined($stop))); # syntax error

	$stop = (defined($step) or ($start eq '*'))?23:$start if (not defined($stop));
	$start = 0 if $start eq '*';
	return if ($start > $stop); # syntax error
	return $start if ($now  < $start); # literal start
	
	$res = $step //= 1;
	$res = ($now - $start) % $res;
	
	return $now if ($res == 0) and ($now <= $stop); # current hour
	$res = $now + $step - $res;
	return $start + 24 if ($res > $stop); # carry over
	return $res; # regular next
};

sub parseDateEntry {
	my ($self, $in, $now) = @_;
	my ($res, $start, $stop, $step);

	($step) = ($in =~ m/\/([0-9]|[0-2][0-9]|3[0,1])$/);
	($start, $stop) = ($in =~ m/^([*]|[0-9]|[0-2][0-9]|3[0,1])(?:-([0-9]|[0-2][0-9]|3[0,1]))?(?:\/(?:[*]|[0-9]|[0-2][0-9]|3[0,1]))?$/);
	return if (not defined($start) or ($start eq '*' and defined($stop))); # syntax error
	
	$stop = (defined($step) or ($start eq '*'))?31:$start if (not defined($stop));
	$start = 1 if $start eq '*';
	return if ($start > $stop); # syntax error
	return $start if ($now  < $start); # literal start
	
	$res = $step //= 1;
	$res = ($now - $start) % $res;

	return $now if ($res == 0) and ($now <= $stop); # current
	$res = $now + $step - $res;
	return $start + 32 if ($res > $stop); # carry over
	return $res; # regular next
};

sub next {
	my ($self, $cron, @t) = @_;

	my $inDay = sprintf('%04d%02d%02d', $t[5], $t[4], $t[3]);
	my ($cronMin, $cronHour, $cronDay, $cronMonth, $cronWeekDay) = split / /, $cron;
	my ($time, $dst, $weekday);

	# m h d(carry)
	$time = $self->nextTime($t[1], $t[2], $cronMin, $cronHour);
	return if (not $time);
	($t[3], $t[4], $t[5], $dst, $weekday) = normalizeDate($t[3], $t[4], $t[5], $time->[2]);
	my $calcDay = sprintf('%04d%02d%02d', $t[5], $t[4], $t[3]);

	# date unchanged and known
	if ($calcDay eq $inDay) {
		return ($time->[0], $time->[1], $t[3], $t[4], $t[5], $dst);
	};

	# m h d(carry)
	$time = $self->nextTime(0, 0, $cronMin, $cronHour);
	#($t[3], $t[4], $t[5], $dst, $weekday) = normalizeDate($t[3], $t[4], $t[5], $time->[2]);

	# yyyy mm dd
	my $date = $self->nextDate($t[3], $t[4], $t[5], $cronDay, $cronMonth);
	return if (not $date);
	($t[3], $t[4], $t[5], $dst, $weekday) = normalizeDate($date->[2], $date->[1], $date->[0]);

	return ($time->[0], $time->[1], $t[3], $t[4], $t[5], $dst);
};

# test if valid cron expression
sub validate {
	my ($self, $cron) = @_;
	my ($cronMin, $cronHour, $cronDay, $cronMonth, $cronWeekDay) = split / /, $cron;
	my $time = $self->nextTime(0, 0, $cronMin, $cronHour);
	my $date = $self->nextDate(2020, 1, 1, $cronDay, $cronMonth);
	if (defined($time) and defined($date)) {
		return 1;
	} else {
		return;
	};
};

# min = time: actual minute
# hour = time: actual hour
sub nextTime {
	my ($self, $min, $hour, $cronMin, $cronHour) = @_;

	my $calcMin;
	my $calcHour;
	my $calcDay = 0;

	foreach my $cronMinEntry (split /,/, $cronMin) {
		my $e = $self->parseMinuteEntry($cronMinEntry, $min);
		return if not defined($e); # syntax error
		if ((not defined($calcMin) and defined($e)) or ($e < $calcMin)) {
			$calcMin = $e;
		};
	};
	($calcMin, $hour, $calcDay) = normalizeTime($calcMin, $hour, $calcDay);

	foreach my $cronHourEntry (split /,/, $cronHour) {
		my $e = $self->parseHourEntry($cronHourEntry, $hour);
		return if not defined($e); # syntax error
		if ((not defined($calcHour) and defined($e)) or ($e < $calcHour)) {
			$calcHour = $e;
		};
	};
	my (@time) = normalizeTime($calcMin, $calcHour, $calcDay);
	return \@time;

};

sub nextDate {
	my ($self, $day, $month, $year, $cronDay, $cronMonth) = @_;

	my $dates = $self->listDates($day, $month, $year, $cronDay, $cronMonth);
	my $result;
	foreach (@{$dates}) {
		if ((not defined($result) and defined($_)) or ($_ and ($_ < $result))) {
			$result = $_;
		};
	};
	return if (not defined($result));
	my (@date) = ($result =~ m/^(\d{4})(\d{2})(\d{2})$/);
	return \@date;
};

sub listDates {
	my ($self, $day, $month, $year, $cronDay, $cronMonth) = @_;
	my @result;

	#return [] if ($self->{R}++ > 25);

	# my sub daysOfMonth {
	local *daysOfMonth = sub {
		my ($m, $y) = @_;
		my (@d) = (0,31,28,31,30,31,30,31,31,30,31,30,31);
		# leapyear
		$d[2] = 29 if (((($y % 4) == 0) and (($y % 100) != 0)) or (($y % 400) == 0));
		return ($d[$m]);
	};

	foreach my $cronDayEntry (split /,/, $cronDay) {
		foreach my $cronMonthEntry (split /,/, $cronMonth) {
			# impossible cron would recurse forever: [31 2 * * *] / [31 9/2 * * *]
			my $invalid = 1;
			if ((my ($fuseDay) = ($cronDayEntry =~ m/^(\d{1,2})/)) and 
				(my ($fuseMonth, $fuseMonthStep) = ($cronMonthEntry =~ m/^(\d{1,2})(?:\/(\d{1,2}))*/))) {
				#print "FUSE $fuseDay, $fuseMonth, $fuseMonthStep\n";
				for (my $i = $fuseMonth; $i <= 12 and $invalid; $i += $fuseMonthStep //= 12) {
					$invalid = 0 if (daysOfMonth($fuseMonth, 2000) >= $fuseDay); # 2000 is leapyear
				};
				if ($invalid) {
					push @result, ();
					next;
				};
			};
			my $calcDay = $self->parseDateEntry($cronDayEntry, $day);
			my $calcMonth = $self->parseDateEntry($cronMonthEntry, $month);
			my $calcYear = $year;
			#printf "Test: D:%s, M:%s against %s-%s -> %s-%s-%s\n", $cronDayEntry, $cronMonthEntry, $day, $month, $calcDay, $calcMonth, $calcYear;
			if (defined($calcDay) and defined($calcMonth)) {
				#$doy = isValid($testM, $testMd);
				if (($calcDay == $day) and ($calcMonth == $month)) {
					#printf "RETURN: D:%s, M:%s against %s-%s-%s -> %s-%s-%s\n", $cronDayEntry, $cronMonthEntry, $day, $month, $year, $calcDay, $calcMonth, $calcYear;
					push @result, sprintf('%04d%02d%02d', $calcYear, $calcMonth, $calcDay);
				} else {
					if ($calcMonth > 12) {
						$calcMonth -= ($calcMonth == 13)?12:32;
						$calcYear++;
					};
					if ($calcDay > daysOfMonth($calcMonth, $calcYear)) {
						$calcMonth++ if ($calcMonth == $month);
						$calcDay = 1;
					};
					push @result, @{ $self->listDates($calcDay, $calcMonth, $calcYear, $cronDayEntry, $cronMonthEntry) };
				};
			} else {
				return []; # syntax error
			};
		};
	};
	return \@result;
};

1;

=pod
=item device
=item summary 		provides a generic way to parse and display json source
=item summary_DE	JSON Quellen parsen und und verwenden
=begin html

<a name="JsonMod"></a>
<h3>JsonMod</h3>
<ul>
	JsonMod provides a generic way to load and parse json files from HTTP sources periodically. 
	Elements within the json files can be selected and displayed in a targeted manner.
	<br><br>
	JsonMod uses the JsonPath syntax to access elements or lists within the json file.
	The well-known cron syntax is used for the periodic retrieval of the files.
</ul>
<ul>
	<a name="JsonModdefine"></a>
	<b>Define</b>
	<ul>
    	<code>define &lt;name&gt; JsonMod &lt;http[s]:example.com:/somepath/somefile.json&gt;</code>
    	<br><br>
    	defines the device and set the source (file:|http:|https:|system://).<br>
		<br>files example:
		<ul>
		<li>file:[//]/path/file (absolute)</li>
		<li>file:[//]path/file (realtive)</li>
		</ul>
		<br>system example:
		<ul>
		<li>system://curl -X POST "https://httpbin.org/anything" -H "Accept: application/json" -H "Content-Type: application/json" -d '{"login":"my_login","password":"my_password"}'</li>
		</ul>
	</ul>
	<br>

	<a name="JsonModset"></a>
	<b>Set</b>
	<ul>
		<li>reread
			<ul>
				<code>set &lt;name&gt; reread</code>
				<br><br>
				Trigger a load and processing of the json source manually.
			</ul>
		</li>
		<li>secret
			<ul>
				<code>set &lt;name&gt; secret &lt;identifier&gt; &lt;value&gt;</code>
				<br><br>
				To prevent the leakage of sensitive information, like credentials or api keys, 
				they can be stored separate and thus are not shown neither in the config file nor in listings.
				Access to that information is provided by putting square brackets and the identifier <code>[identifier]</code> 
				into the http source within the definition or in a http header (see attribute). 
			</ul>
		</li>
	</ul>
	<br>

	<a name="JsonModget"></a>
	<b>Get</b>
	<ul>
		N/A
	</ul>
	<br>

	<a name="JsonModattr"></a>
	<b>Attributes</b>
	<ul>
		<a name="interval"></a>
		<li>interval<br>
			<code>set &lt;name&gt; interval &lt;*/15 * * * *&gt;</code><br>
			utilize a cron expression to define the interval at which the source file will be loaded.
			Default is one hour. 			
		</li>
		<a name="readingList"></a>
		<li>readingList<br>
			Specifies the access to json elements and their representation as well as formatting as reading.
			In its conventions, the syntax follows normal perl expression but uitlies a special set of instructions.
			This means that an expression must end with a semicolon, parentheses must be equal, and be of the correct type. 
			When using double quotes, the content is interpolated. Since Jsonpath uses the '$' and '@' characters as part of the syntax, 
			they must be escaped in expressions within double quotes. It is therefore preferable to use single quotes wherever possible.
			<br><br>
			Recognized expressions (where '$.' is a placeholder for a valid json path expression):
			<ul>
				<li>
					single(jsonPath('$.'), 'readingname', 'default value');<br>
					creates one reading. The json path expression must translate into a value (not into an array or an object)
				</li>
				<li>
					multi(jsonPath('$.'), &lt;Instructions for creating the reading name&gt;, &lt;property&gt;);<br>
					creates multiple (0..n) readings. Jsonpath expression must translate into an array of objects or values. 
					Because the number of readings is variable, a function is used to generate the reading names. 
					Typically, this is based on the index of the array element and / or a property of the addressed objects.
				</li>
				<li>
					complete();<br>
					Automatically creates readings for the entire JSON source. The readings ​​are named after their JSON path.
				</li>
				<li>
					jsonPath('$.')<br>
					Creates a jsonpath expression as part of a 'single' or 'multi' expression.
				</li>
				<li>
					jsonPathf('$.', 'format')<br>
					Creates a jsonpath expression as part of a 'single' expression and format its result.
					The syntax of the expression 'format' match to the syntax of printf.
				</li>
				<li>
					property('expression')<br>
					Is used to access properties of the json objects within a multi() statement.
				</li>
				<li>
					propertyf('expression', 'format')<br>
					Is used to access properties of the json objects within a multi() statement and format its result.
					The syntax of the expression 'format' match to the syntax of printf.
				</li>
				<li>
					concat('expression', 'expression', ...)<br>
					Concatenates the expressions to one result. 
					Can be used in a 'multi()' statement to create a reading name from one or more object properties or the index.
				</li>
				<li>
					count|count()<br>
					Contains the index number of the current list element. 
					Within 'multi()' instructions for generating reading names, eg by using concat('item_', count) or similar.
				</li>
				<li>
					node|node()<br>
					Contains the normalized path expression of the current node. Required to access the keys of an object when iterating over a keys/value structure of an object. 
					Within 'multi()' instructions eg for generating reading names from object keys.
				</li>
			</ul>
			<br>within the expresiions single() and multi(), additional perl expressions may be used if required.<br><br>
			Since the reading names are typically generated from the content of the JSON, it is the responsibility of the user to ensure that the fhem naming conventions are followed. JsonMod will make the following adjustments to the readings name if necessary and possible:
			<ul>
			<li>All non-ACSII characters are converted to an ASCII equivalent if possible</li>
			<li>All forbidden characters are removed from the name</li>
			<li>if a conversion fails, the name is set as "__CONVERSATION_ERROR__"</li>
			<li>in case of multiple same reading names, the last one overwrites the previous one</li>
			</ul>
		</li>
	</ul>
</ul>
=end html

=cut