##############################################
# $Id$
package main;

=pod
### Usage:
Define the following in your 99_myUtils.pm
sub TestBlocking($){ BlockingCall("DoSleep", shift, "SleepDone", 5, "AbortFn", "AbortArg"); }
sub DoSleep($)     { sleep(shift); return "I'm done"; }
sub SleepDone($)   { Log 1, "SleepDone: " . shift; }
sub AbortFn($)     { Log 1, "Aborted: " . shift; }
Then call from the fhem prompt
{ TestBlocking(3) }
{ TestBlocking(6) }
and watch the fhem log.
=cut


use strict;
use warnings;
use IO::Socket::INET;

sub BlockingCall($$@);
sub BlockingExit();
sub BlockingKill($);
sub BlockingInformParent($;$$);
sub BlockingStart(;$);

use vars qw($BC_telnetDevice);
use vars qw(%BC_hash);
my $telnetClient;
my $bc_pid = 0;

use vars qw($BC_telnet); # set optionally by the user, Forum #68477

sub
BC_searchTelnet($)
{
  my ($blockingFn) = @_;

  if($BC_telnet) {
    $BC_telnetDevice = $BC_telnet;
    return;
  }

  $BC_telnetDevice = undef;
  foreach my $d (sort keys %defs) { # 
    my $h = $defs{$d};
    next if(!$h->{TYPE} || $h->{TYPE} ne "telnet" || $h->{SNAME});
    next if($attr{$d}{SSL} ||
            AttrVal($d, "allowfrom", "127.0.0.1") ne "127.0.0.1");
    next if($h->{DEF} !~ m/^\d+( global)?$/);
    next if($h->{DEF} =~ m/IPV6/);

    my %cDev = ( SNAME=>$d, TYPE=>$h->{TYPE}, NAME=>$d.time() );
    next if(Authenticate(\%cDev, undef) == 2);    # Needs password
    $BC_telnetDevice = $d;
    last;
  }

  # If not suitable telnet device found, create a temporary one
  if(!$BC_telnetDevice) {
    $BC_telnetDevice = "telnetForBlockingFn_".time();
    my $ret = CommandDefine(undef, "-temporary $BC_telnetDevice telnet 0");
    if($ret) {
      $ret = "BlockingCall ($blockingFn): ".
                "No telnet port found and cannot create one: $ret";
      Log 1, $ret;
      return undef;
    }
    $attr{$BC_telnetDevice}{room} = "hidden"; # no red ?, Forum #46640
    $attr{$BC_telnetDevice}{allowfrom} = "127.0.0.1";
  }
}

sub
BlockingCall($$@)
{
  my ($blockingFn, $arg, $finishFn, $timeout, $abortFn, $abortArg) = @_;

  my %h = ( pid=>'WAITING:', fn=>$blockingFn, arg=>$arg, finishFn=>$finishFn,
            timeout=>$timeout, abortFn=>$abortFn, abortArg=>$abortArg );
  $BC_hash{++$bc_pid} = \%h;
  $h{bc_pid} = $bc_pid;
  return BlockingStart(\%h);
}

sub
BlockingStart(;$)
{
  my ($curr) = @_;

  if($curr && $curr =~ m/^\d+$/) {
    $BC_hash{$curr}{terminated} = 1 if($BC_hash{$curr});
    $curr = undef;
  }

  # Look for the telnetport. Must be done before forking to be able to create a
  # temporary device. Do it each time, as the old telnet may got a password
  BC_searchTelnet($curr && $curr->{fn} ? $curr->{fn}: "BlockingStart");

  my $chld_alive = 0;
  my $max = AttrVal('global', 'blockingCallMax', 0);

  for my $bpid (sort { $a <=> $b} keys %BC_hash) {
    my $h = $BC_hash{$bpid};

    if($h->{pid} && $h->{pid} =~ m/^-?\d+$/) { # Windows threads are negative
      if($^O =~ m/Win/) {
        # MaxNr of concurrent forked processes @Win is 64, and must use wait as
        # $SIG{CHLD} = 'IGNORE' does not work.
        wait;
      } else {
        use POSIX ":sys_wait_h";
        waitpid(-1, WNOHANG); # Forum #58867
      }
      if(!kill(0, $h->{pid})) {
        $h->{pid} = "DEAD:$h->{pid}";
        delete($BC_hash{$bpid});
        RemoveInternalTimer($h) if($h->{timeout});
      } else {
        $chld_alive++;
      }
      next;
    }

    if(!$h->{fn}) {     # Deleted by the module in finishFn?
      delete($BC_hash{$bpid});
      RemoveInternalTimer($h) if($h->{timeout});
      next;
    }

    if($max && $chld_alive >= $max) {
      if($curr && $curr->{fn}) {
        Log 4, "BlockingCall ($curr->{fn}) enqueue: ".
                      "limit (blockingCallMax=$max) reached";
      }
      RemoveInternalTimer(\%BC_hash);
      InternalTimer(gettimeofday()+5, "BlockingStart", \%BC_hash, 0);
      return $curr;
    }

    # do fork
    my $pid = fhemFork;
    if(!defined($pid)) {
      Log 1, "Cannot fork: $!";
      return $curr;
    }

    if($pid) {
      Log 4, "BlockingCall ($h->{fn}): created child ($pid), ".
                  "uses $BC_telnetDevice to connect back";
      $h->{pid} = $pid;
      InternalTimer(gettimeofday()+$h->{timeout}, "BlockingKill", $h, 0)
        if($h->{timeout});
      $chld_alive++;
      next;
    }

    # Child here
    no strict "refs";
    my $ret = &{$h->{fn}}($h->{arg});
    use strict "refs";

    BlockingInformParent("BlockingStart", $h->{bc_pid}, 0);
    BlockingExit() if(!$h->{finishFn});

    # Write the data back, calling the function
    BlockingInformParent($h->{finishFn}, $ret, 0);
    BlockingExit();
  }
  return $curr;
}

sub
BlockingInformParent($;$$)
{
  my ($informFn, $param, $waitForRead) = @_;
  my $ret = undef;
  $waitForRead = 1 if (!defined($waitForRead));
	
  # Write the data back, calling the function
  if(!$telnetClient) {
    my $addr = "localhost:$defs{$BC_telnetDevice}{PORT}";
    $telnetClient = IO::Socket::INET->new(PeerAddr => $addr);
    if(!$telnetClient) {
      Log 1, "BlockingInformParent ($informFn): Can't connect to $addr: $@";
      return;
    }
  }

  if(defined($param)) {
    if(ref($param) eq "ARRAY") {
      $param = join(",", map { $_ =~ s/'/\\'/g; "'$_'" } @{$param});

    } else {
      $param =~ s/'/\\'/g;
      $param = "'$param'"
    }
  } else {
    $param = "";
  }
  $param =~ s/;/;;/g;

  syswrite($telnetClient, "{$informFn($param)}\n");

  if ($waitForRead) {
    my $len = sysread($telnetClient, $ret, 4096);
    chop($ret);
    $ret = undef if(!defined($len));
  } else {
    # if data is available read anyway to keep input stream clear
    my $rin = '';
    vec($rin, $telnetClient->fileno(), 1) = 1;
    if (select($rin, undef, undef, 0) > 0) {
      sysread($telnetClient, $ret, 4096);
      $ret = undef;
    }
  }

  return $ret;
}

# Parent
sub
BlockingKill($)
{
  my $h = shift;

  return if($h->{terminated});

  if($^O !~ m/Win/) {
    if($h->{pid} && $h->{pid} !~ m/:/ && kill(9, $h->{pid})) {
      Log 1, "Timeout for $h->{fn} reached, terminated process $h->{pid}";
      if($h->{abortFn}) {
        no strict "refs";
        my $ret = &{$h->{abortFn}}($h->{abortArg});
        use strict "refs";

      } elsif($h->{finishFn}) {
        no strict "refs";
        my $ret = &{$h->{finishFn}}();
        use strict "refs";

      }
      InternalTimer(gettimeofday()+1, "BlockingStart", \%BC_hash, 0)
        if(kill(0, $h->{pid})); # Forum #58867
    }
  }
  BlockingStart();
}

# Child
sub
BlockingExit()
{
  close($telnetClient) if($telnetClient);

  if($^O =~ m/Win/) {
    eval "require threads;";
    threads->exit();

  } else {
    POSIX::_exit(0);

  }
}

1;
