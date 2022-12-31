##############################################
##############################################
# $Id$
package main;
use strict;
use warnings;
use B qw(svref_2object);

sub HMinfo_Initialize($$);
sub HMinfo_Define($$);
sub HMinfo_getParam(@);
sub HMinfo_regCheck(@);
sub HMinfo_peerCheck(@);
sub HMinfo_getEntities(@);
sub HMinfo_SetFn($@);
sub HMinfo_SetFnDly($);
sub HMinfo_noDup(@);
sub HMinfo_register ($);
sub HMinfo_init($);

use Blocking;
use HMConfig;
my $doAli = 0;#display alias names as well (filter option 2)
my $tmplDefChange = 0;
my $tmplUsgChange = 0;

my %chkIds=(
    "idCl00" => {Fkt=> "configChk" ,shtxt=> "clear"       ,txt=> "clear"                                                   ,long=>"" }
   ,"idBc01" => {Fkt=> "burstCheck",shtxt=> "BurstUnknwn" ,txt=> "peerNeedsBurst cannot be determined"                     ,long=>"register-set of sender device likely not read complete" }
   ,"idBc02" => {Fkt=> "burstCheck",shtxt=> "BurstNotSet" ,txt=> "peerNeedsBurst not set"                                  ,long=>"register peerNeedsBurst is required but not set in sender device" }
   ,"idBc03" => {Fkt=> "burstCheck",shtxt=> "CBurstNotSet",txt=> "conditionalBurst not set"                                ,long=>"register peerNeedsBurst is required but not set in sender device" }
   ,"idPc00" => {Fkt=> "paramCheck",shtxt=> "NoIO"        ,txt=> "no IO device assigned"                                   ,long=>"attribut IODev should be set" }
   ,"idPc01" => {Fkt=> "paramCheck",shtxt=> "PairMiss"    ,txt=> "PairedTo missing/unknown"                                ,long=>"register-set not read completely. Register pairedTo cannot be verifid" }
   ,"idPc02" => {Fkt=> "paramCheck",shtxt=> "PairMism"    ,txt=> "PairedTo mismatch to IODev"                              ,long=>"Register PairedTo is not set according to IODev setting" }
   ,"idPc03" => {Fkt=> "paramCheck",shtxt=> "IOgrp"       ,txt=> "IOgrp: CCU not found"                                    ,long=>"vccu as defined in attr IOgrp cannot be found" }
   ,"idPc04" => {Fkt=> "paramCheck",shtxt=> "IOGrpPref"   ,txt=> "IOgrp: prefered IO undefined"                            ,long=>"prefered IO as defined in attr IOgrp cannot be found" }
   ,"idPz00" => {Fkt=> "peerCheck" ,shtxt=> "PeerIncom"   ,txt=> "peer list incomplete. Use getConfig to read it."         ,long=>"peerlist not completely read. getConfig should do" }
   ,"idPz01" => {Fkt=> "peerCheck" ,shtxt=> "PeerUndef"   ,txt=> "peer not defined"                                        ,long=>"a peer in the peerlist cannot be found" }
   ,"idPz02" => {Fkt=> "peerCheck" ,shtxt=> "PeerVerf"    ,txt=> "peer not verified. Check that peer is set on both sides" ,long=>"peer is only set on one side. Check that peering exist on actor and sensor" }
   ,"idPz03" => {Fkt=> "peerCheck" ,shtxt=> "PeerStrange" ,txt=> "peering strange - likely not suitable"                   ,long=>"a peering does not seem to be operational" }
   ,"idPz04" => {Fkt=> "peerCheck" ,shtxt=> "TrigUnkn"    ,txt=> "trigger sent to unpeered device"                         ,long=>"the sensor sent a trigger to an unknown address" }
   ,"idPz05" => {Fkt=> "peerCheck" ,shtxt=> "TrigUndef"   ,txt=> "trigger sent to undefined device"                        ,long=>"the sensor sent a trigger to an undefined address" }
   ,"idPz06" => {Fkt=> "peerCheck" ,shtxt=> "AES"         ,txt=> "aesComReq set but virtual peer is not vccu - won't work" ,long=>"Attr aesComReq wont work" }
   ,"idPz07" => {Fkt=> "peerCheck" ,shtxt=> "Team"        ,txt=> "boost or template differ in team"                        ,long=>"boost time defined is different in team. Check boost time setting for all team members" }
   ,"idRc01" => {Fkt=> "regCheck"  ,shtxt=> "RegMiss"     ,txt=> "missing register list"                                   ,long=>"the registerlist is not complerely read. Try getConfig and wait for completion" }
   ,"idRc02" => {Fkt=> "regCheck"  ,shtxt=> "RegIncom"    ,txt=> "incomplete register list"                                ,long=>"registerlist is incomplete. Try getConfig and wait for completion" }
   ,"idRc03" => {Fkt=> "regCheck"  ,shtxt=> "RegPend"     ,txt=> "Register changes pending"                                ,long=>"issued regiser changes are ongoing" }
   ,"idTp00" => {Fkt=> "template"  ,shtxt=> "TempChk"     ,txt=> "templist mismatch"                                       ,long=>"register settings dont macht template settings" }
   ,"idTp01" => {Fkt=> "template"  ,shtxt=> "TmplChk"     ,txt=> "template mismatch"                                       ,long=>"register settings dont macht template settings" }
);

sub HMinfo_Initialize($$) {####################################################
  my ($hash) = @_;

  $hash->{DefFn}     = "HMinfo_Define";
  $hash->{UndefFn}   = "HMinfo_Undef";
  $hash->{SetFn}     = "HMinfo_SetFn";
  $hash->{GetFn}     = "HMinfo_GetFn";
  $hash->{AttrFn}    = "HMinfo_Attr";
  $hash->{NotifyFn}  = "HMinfo_Notify";
  $hash->{AttrList}  =  "loglevel:0,1,2,3,4,5,6 "
                       ."sumStatus sumERROR "
                       ."autoUpdate autoArchive "
                       ."autoLoadArchive:0_no,1_load "
#                       ."autoLoadArchive:0_no,1_template,2_register,3_templ+reg "
                       ."hmAutoReadScan hmIoMaxDly "
                       ."hmManualOper:0_auto,1_manual "
                       ."configDir configFilename configTempFile "
                       ."hmDefaults "
                       ."verbCULHM:multiple,none,allSet,allGet,allSetVerb,allGetVerb "
                       .$readingFnAttributes;
  $hash->{NOTIFYDEV} = "global";
  $modules{HMinfo}{helper}{initDone} = 0;
  $hash->{NotifyOrderPrefix} = "49-"; #Beta-User: make sure, HMinfo is up and running after CUL_HM but prior to user code e.g. in notify
}
sub HMinfo_Define($$){#########################################################
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my ($n) = devspec2array("TYPE=HMinfo");
  return "only one instance of HMInfo allowed, $n already instantiated"
        if ($n && $hash->{NAME} ne $n);
  my $name = $hash->{NAME};
  $hash->{Version} = "01";
  $attr{$name}{webCmd} = "update:protoEvents short:rssi:peerXref:configCheck:models";
  $attr{$name}{sumStatus} =  "battery"
                            .",sabotageError"
                            .",powerError"
                            .",motor";
  $attr{$name}{sumERROR}  =  "battery:ok"
                            .",sabotageError:off"
                            .",powerError:ok"
                            .",overload:off"
                            .",overheat:off"
                            .",reduced:off"
                            .",motorErr:ok"
                            .",error:none"
                            .",uncertain:[no|yes]"
                            .",smoke_detect:none"
                            .",cover:closed"
                            ;
  $hash->{nb}{cnt} = 0;
  $modules{HMinfo}{helper}{initDone} = 0;
  notifyRegexpChanged($hash,"global",0);
  LoadModule('CUL_HM'); #Beta-User: Make sure, code from CUL_HM is available when attributes are set
  return;
}
sub HMinfo_Undef($$){##########################################################
  my ($hash, $name) = @_;
  RemoveInternalTimer("sUpdt:".$name);
  RemoveInternalTimer($name,"HMinfo_getCfgDefere");
  return undef;
}
sub HMinfo_Attr(@) {###########################################################
  my ($cmd,$name, $attrName,$attrVal) = @_;
  my @hashL;
  my $hash = $defs{$name};

  my @attOptLst = ();# get option list for this attribut
  if ($cmd eq "set"){
    my $attOpts = $modules{HMinfo}{AttrList};
    $attOpts =~ s/.*$attrName:?(.*?) .*/$1/;
    @attOptLst = grep !/multiple/,split(",",$attOpts);
  }

  if   ($attrName eq "autoUpdate"){# 00:00 hh:mm
    delete $hash->{helper}{autoUpdate};
    RemoveInternalTimer("sUpdt:".$name);#frank:
    return if ($cmd eq "del");
    my ($h,$m) = split":",$attrVal;
    return "please enter time [hh:mm]" if (!defined $h||!defined $m);
    my $sec = $h*3600+$m*60;
    return "give at least one minute" if ($sec < 60);
    $hash->{helper}{autoUpdate} = $sec;
    InternalTimer(gettimeofday()+$sec,"HMinfo_autoUpdate","sUpdt:".$name,0);
  }
  elsif($attrName eq "hmAutoReadScan"){# 00:00 hh:mm
    if ($cmd eq "del"){
      $modules{CUL_HM}{hmAutoReadScan} = 4;# return to default
    }
    else{
      return "please add plain integer between 1 and 300"
          if (  $attrVal !~ m/^(\d+)$/
              ||$attrVal<0
              ||$attrVal >300 );
      ## implement new timer to CUL_HM
      $modules{CUL_HM}{hmAutoReadScan}=$attrVal;
      CUL_HM_procQs("");
    }
  }
  elsif($attrName eq "hmIoMaxDly"){#
    if ($cmd eq "del"){
      $modules{CUL_HM}{hmIoMaxDly} = 60;# return to default
    }
    else{
      return "please add plain integer between 0 and 3600"
          if (  $attrVal !~ m/^(\d+)$/
              ||$attrVal<0
              ||$attrVal >3600 );
      ## implement new timer to CUL_HM
      $modules{CUL_HM}{hmIoMaxDly}=$attrVal;
    }
  }
  elsif($attrName eq "hmManualOper"){# 00:00 hh:mm
    if ($cmd eq "del"){
      $modules{CUL_HM}{helper}{hmManualOper} = 0;# default automode
    }
    else{
      return "please set 0 or 1"  if ($attrVal !~ m/^(0|1)/);
      ## implement new timer to CUL_HM
      $modules{CUL_HM}{helper}{hmManualOper} = substr($attrVal,0,1);
    }
  }
  elsif($attrName eq "sumERROR"){
    if ($cmd eq "set"){
      foreach (split ",",$attrVal){    #prepare reading filter for error counts
        my ($p,@a) = split ":",$_;
        return "parameter illegal - " 
              if(!$p || !defined $a[0]);
      }
    }
  }
  elsif($attrName eq "configDir"){
    if ($cmd eq "set"){
      $attr{$name}{configDir}=$attrVal;
    }
    else{
      delete $attr{$name}{configDir};
    }
    HMinfo_listOfTempTemplates();
  }
  elsif($attrName eq "configTempFile"){
    if ($cmd eq "set"){
      $attr{$name}{configTempFile}=$attrVal;
    }
    else{
      delete $attr{$name}{configTempFile};
    }
    HMinfo_listOfTempTemplates();
  }
  elsif($attrName eq "hmDefaults"){
    if ($cmd eq "set"){
      delete $modules{CUL_HM}{AttrListDef};
      my @defpara = ( "hmProtocolEvents"
                     ,"rssiLog"         
                     ,"autoReadReg"
                     ,"msgRepeat"
                     ,"expert"
                     ,"actAutoTry"
                     );
      my %culAH;
      foreach (split" ",$modules{CUL_HM}{AttrList}){
        my ($p,$v) = split(":",$_);
        $culAH{$p} = $v?",$v,":"";
      }
      
      foreach (split(",",$attrVal)){
        my ($para,$val) = split(":",$_,2);
        return "no value defined for $para" if (!defined "val");
        return "param $para not allowed" if (!grep /$para/,@defpara);
        return "param $para :$val not allowed, use $culAH{$para}" if ($culAH{$para} && $culAH{$para} !~ m/,$val,/);
        $modules{CUL_HM}{AttrListDef}{$para} = $val;
      } 
    }
    else{
      delete $modules{CUL_HM}{AttrListDef};
    }
  }
  elsif($attrName eq "verbCULHM"){
    delete $modules{CUL_HM}{helper}{verbose};
    $modules{CUL_HM}{helper}{verbose}{none} = 1; # init hash
    if ($cmd eq "set"){
      my @optSets = ();
      foreach my $optIn (split(",",$attrVal)){
        next if(0 == grep/^$optIn$/,@attOptLst);
        $modules{CUL_HM}{helper}{verbose}{$optIn} = 1;
        push @optSets,$optIn;
      }
      $attr{$name}{$attrName} = join(",",@optSets);
      return "set $attrName to $attr{$name}{$attrName}" if ($attr{$name}{$attrName} ne $attrVal);
    }
  }
  elsif($attrName eq "autoLoadArchive"){
  }
  return;
}

sub HMinfo_Notify(@){##########################################################
  my ($hash, $dev) = @_;
  my $name = $hash->{NAME};
  return "" if ($dev->{NAME} ne "global");

  my $events = deviceEvents($dev, AttrVal($name, "addStateEvent", 0));
  return undef if(!$events); # Some previous notify deleted the array.

  #we need to init the templist if HMInfo is in use
  my $cfgFn  = AttrVal($name,"configTempFile","tempList.cfg");
  HMinfo_listOfTempTemplates() if (grep /(FILEWRITE.*$cfgFn|INITIALIZED)/,@{$events});

  if (grep /(SAVE|SHUTDOWN)/,@{$events}){# also save configuration
    HMinfo_archConfig($hash,$name,"","") if(AttrVal($name,"autoArchive",undef));
  }
  if (grep /(INITIALIZED|REREADCFG)/,@{$events}){
    $modules{HMinfo}{helper}{initDone} = 0;
    HMinfo_init($hash);
  }
  return undef;
}
sub HMinfo_init($){############################################################
  #my ($hash, $dev) = @_;

  RemoveInternalTimer("HMinfo_init");# just to be sure...
  if ($init_done){
    if (!$modules{HMinfo}{helper}{initDone}){ 
      my ($hm) = devspec2array("TYPE=HMinfo");
      Log3($hm,5,"debug: HMinfo_init");
      foreach my $attrName (keys %{$attr{$hm}}){
        HMinfo_Attr("set",$hm, $attrName,$attr{$hm}{$attrName});
      }

      if (substr(AttrVal($hm, "autoLoadArchive", 0),0,1) ne 0){
        HMinfo_SetFn($defs{$hm},$hm,"loadConfig");
        InternalTimer(gettimeofday()+5,"HMinfo_init", "HMinfo_init", 0);
      }
      else{
        $modules{HMinfo}{helper}{initDone} = 1;
      }
      HMinfo_listOfTempTemplates();
    }
  }
  else{
    InternalTimer(gettimeofday()+5,"HMinfo_init", "HMinfo_init", 0);
  }
}
sub HMinfo_status($){##########################################################
  # - count defined HM entities, selected readings, errors on filtered readings
  # - display Assigned IO devices
  # - show ActionDetector status
  # - prot events if error
  # - rssi - eval minimum values

  my $hash = shift;
  my $name = $hash->{NAME};
  my ($nbrE,$nbrD,$nbrC,$nbrV) = (0,0,0,0);# count entities and types
  #--- used for status
  my @info = split ",",$attr{$name}{sumStatus};#prepare event
  my %sum;
  #--- used for error counts
  my @erro = split ",",$attr{$name}{sumERROR};
  
  # clearout internals prior to update
  delete $hash->{helper}{lastList};
  foreach (grep(/^i(ERR|W_|CRI_)/,keys%{$hash})){
    $hash->{helper}{lastList}{$_} = $hash->{$_}; #save old entity list
    delete $hash->{$_};
  }
  delete $hash->{$_} foreach (grep(/^i*(ERR|W_|I_|C_|CRI_)/,keys%{$hash}));

  my %errFlt;
  my %errFltN;
  my %err;

  if(defined $modules{CUL_HM}{defptr}{"000000"}){ #update action detector
    CUL_HM_Set($defs{$modules{CUL_HM}{defptr}{"000000"}{NAME}},
                     $modules{CUL_HM}{defptr}{"000000"}{NAME},"update");
  }
  foreach(devspec2array("TYPE=CUL_HM:FILTER=model=CCU-FHEM:FILTER=DEF=......")){
    CUL_HM_Set($defs{$_}, $_,"update"); #update all ccu devices
  }
  
  foreach (@erro){    #prepare reading filter for error counts
    my ($p,@a) = split ":",$_;
    $errFlt{$p}{x}=1; # add at least one reading
    $errFlt{$p}{$_}=1 foreach (@a);
    my @b;
#    $errFltN{$p} = \@b;# will need an array to collect the relevant names
  }
  #--- used for IO, protocol  and communication (e.g. rssi)
  my @IOdev;
  my %IOccu;

  my %protC = (ErrIoId_ =>0,ErrIoAttack =>0);
  my %protE = (NACK =>0,IOerr =>0,ResndFail =>0,CmdDel =>0);
  my %protW = (Resnd =>0,CmdPend =>0);
  my @protNamesC;    # devices with current protocol Critical
  my @protNamesE;    # devices with current protocol Errors
  my @protNamesW;    # devices with current protocol Warnings
  my @Anames;        # devices with ActionDetector events
  my %rssiMin;
  my %rssiMinCnt = ("99>"=>0,"80>"=>0,"60>"=>0,"59<"=>0);
  my @rssiNames; #entities with ciritcal RSSI
  my @shdwNames; #entites with shadowRegs, i.e. unconfirmed register ->W_unconfRegs

  foreach my $id (keys%{$modules{CUL_HM}{defptr}}){#search/count for parameter
    my $ehash = $modules{CUL_HM}{defptr}{$id};
    my $eName = $ehash->{NAME};
    next if (CUL_HM_getAttrInt($eName,"ignore"));
    $nbrE++;
    $nbrC++ if ($ehash->{helper}{role}{chn});
    $nbrV++ if ($ehash->{helper}{role}{vrt});
    push @shdwNames,$eName if (CUL_HM_cleanShadowReg($eName)); # are shadowRegs active?
    
    
    foreach my $read (grep {$ehash->{READINGS}{$_}} @info){       #---- count critical readings
      my $val = $ehash->{READINGS}{$read}{VAL};
      $sum{$read}{$val} =0 if (!$sum{$read}{$val});
      $sum{$read}{$val}++;
    }
    foreach my $read (grep {$ehash->{READINGS}{$_}} keys %errFlt){#---- count error readings
      my $val = $ehash->{READINGS}{$read}{VAL};
      if($val =~ m/\?/) {#frank: check to avoid crash => https://forum.fhem.de/index.php/topic,129878.0.html
        $val =~ s/\?/x/g;
      }
      next if (grep (/$val/,(keys%{$errFlt{$read}})));# filter non-Error
      $errFltN{$read."_".$val}{$eName} = 1;
      $err{$read}{$val} = 0 if (!$err{$read}{$val});
      $err{$read}{$val}++;
    }
    if ($ehash->{helper}{role}{dev}){#---restrict to devices
      $nbrD++;
      push @IOdev,$ehash->{IODev}{NAME} if($ehash->{IODev} && $ehash->{IODev}{NAME});
      $IOccu{(split ":",AttrVal($eName,"IOgrp","no"))[0]}=1;
      push @Anames,$eName if ($attr{$eName}{actStatus} && $attr{$eName}{actStatus} eq "dead");

      foreach (grep /ErrIoId_/, keys %{$ehash}){# detect addtional critical entries
        my $k = $_;
        $k =~ s/^prot//;
        $protC{$k} = 0 if(!defined $protC{$_});
      }
      foreach (grep {$ehash->{"prot".$_}} keys %protC){ $protC{$_}++; push @protNamesC,$eName;}#protocol critical alarms
      foreach (grep {$ehash->{"prot".$_}} keys %protE){ $protE{$_}++; push @protNamesE,$eName;}#protocol errors
      foreach (grep {$ehash->{"prot".$_}} keys %protW){ $protW{$_}++; push @protNamesW,$eName;}#protocol events reported
      $rssiMin{$eName} = 0;
      foreach (keys %{$ehash->{helper}{rssi}}){
        last if !defined $ehash->{IODev};
        next if($_ !~ m /at_.*$ehash->{IODev}->{NAME}/ );#ignore unused IODev
        $rssiMin{$eName} = $ehash->{helper}{rssi}{$_}{min}
          if ($rssiMin{$eName} > $ehash->{helper}{rssi}{$_}{min});
      }
    }
  }
  #====== collection finished - start data preparation======
  my @updates;
  foreach my $read(grep {defined $sum{$_}} @info){       #--- disp crt count
    my $d;
    $d .= "$_:$sum{$read}{$_},"foreach(sort keys %{$sum{$read}});
    push @updates,"I_sum_$read:".$d;
  }
  foreach my $read(keys %errFlt) {
    if (defined $err{$read}) {
      my $d;
      $d .= "$_:$err{$read}{$_}," foreach(keys %{$err{$read}});
      push @updates,"ERR_$read:".$d;
    } 
    elsif (defined $hash->{READINGS}{"ERR_$read"}) {
      if ($hash->{READINGS}{"ERR_$read"}{VAL} ne '-') {
        # Error condition has been resolved, push empty update
        push @updates,"ERR_$read:";
      } 
      else {
        # Delete reading again if it was already empty
        delete $hash->{READINGS}{"ERR_$read"};	
      }
    }
  }
  foreach(keys %errFltN){
    $hash->{"iERR_".$_} = join(",",sort keys %{$errFltN{$_}});
  }

  push @updates,"C_sumDefined:"."entities:$nbrE,device:$nbrD,channel:$nbrC,virtual:$nbrV";
  # ------- display status of action detector ------
  push @updates,"I_actTotal:".join",",(split" ",$modules{CUL_HM}{defptr}{"000000"}{STATE});
  
  # ------- what about IO devices??? ------
  push @IOdev,split ",",AttrVal($_,"IOList","")foreach (keys %IOccu);

  my %tmp; # remove duplicates
  $hash->{iI_HM_IOdevices} = "";
  
  
  $tmp{InternalVal($_,"owner_CCU","noVccu")}{ReadingsVal($_,"cond",InternalVal($_,"STATE","unknown"))}{$_} = 1 foreach(@IOdev);
  foreach my $vccu (sort keys %tmp){
    $hash->{iI_HM_IOdevices} .= $hash->{iI_HM_IOdevices} eq "" ? "$vccu>": " $vccu>";
    foreach my $IOstat (sort keys %{$tmp{$vccu}}){
      $hash->{iI_HM_IOdevices} .= "$IOstat:".join(",",sort keys %{$tmp{$vccu}{$IOstat}}).";";
    }
  }

  # ------- what about protocol events ------
  # Current Events are Rcv,NACK,IOerr,Resend,ResendFail,Snd
  # additional variables are protCmdDel,protCmdPend,protState,protLastRcv

  push @updates,"CRI__protocol:"  .join(",",sort map {"$_:$protC{$_}"} grep {$protC{$_}} sort keys(%protC));
  push @updates,"ERR__protocol:"  .join(",",sort map {"$_:$protE{$_}"} grep {$protE{$_}} sort keys(%protE));
  push @updates,"W__protocol:"    .join(",",sort map {"$_:$protW{$_}"} grep {$protW{$_}} sort keys(%protW));

  my @tpu = devspec2array("TYPE=CUL_HM:FILTER=DEF=......:FILTER=state=unreachable");
  push @updates,"ERR__unreachable:".scalar(@tpu);
  push @updates,"I_autoReadPend:"  .scalar @{$modules{CUL_HM}{helper}{qReqConf}};
  # ------- what about rssi low readings ------
  foreach (grep {$rssiMin{$_} != 0}keys %rssiMin){
    if    ($rssiMin{$_}> -60) {$rssiMinCnt{"59<"}++;}
    elsif ($rssiMin{$_}> -80) {$rssiMinCnt{"60>"}++;}
    elsif ($rssiMin{$_}< -99) {$rssiMinCnt{"99>"}++;
                               push @rssiNames,$_  ;}
    else                      {$rssiMinCnt{"80>"}++;}
  }

  my @ta;
                                              if(@tpu)      {$hash->{iW__unreachNames} = join(",",sort @tpu)      };
  @ta = grep !/^$/,HMinfo_noDup(@protNamesC); if(@ta)       {$hash->{iCRI__protocol}   = join(",",sort @ta)       };
  @ta = grep !/^$/,HMinfo_noDup(@protNamesE); if(@ta)       {$hash->{iERR__protocol}   = join(",",sort @ta)       };
  @ta = grep !/^$/,HMinfo_noDup(@protNamesW); if(@ta)       {$hash->{iW__protoNames}   = join(",",sort @ta)       };
  @ta = @{$modules{CUL_HM}{helper}{qReqConf}};if(@ta)       {$hash->{iI_autoReadPend}  = join(",",sort @ta)       };
                                              if(@shdwNames){$hash->{iW_unConfRegs}    = join(",",sort @shdwNames)};
                                              if(@rssiNames){$hash->{iERR___rssiCrit}  = join(",",sort @rssiNames)};
                                              if(@Anames)   {$hash->{iERR__actDead}    = join(",",sort @Anames)   };
 
  push @updates,"I_rssiMinLevel:".join(" ",map {"$_:$rssiMinCnt{$_}"} sort keys %rssiMinCnt);
  
  # ------- update own status ------
  $hash->{STATE} = "updated:".TimeNow();
  my $changed = 0;
  if (join(",",sort keys %{$hash->{helper}{lastList}}) ne join(",",sort grep(/^i(ERR|W_|CRI_)/,keys%{$hash}))){
    $changed = 1;    
  }
  else{
    foreach (keys %{$hash->{helper}{lastList}}){
      if ($hash->{$_} ne $hash->{helper}{lastList}{$_}){
        $changed = 1;
        last;
      }
    }
  }
  push @updates,"lastErrChange:".$hash->{STATE} if ($changed);
    
  # ------- update own status ------
  my %curRead;
  $curRead{$_}++ for(grep /^(ERR|W_|I_|C_|CRI_)/,keys%{$hash->{READINGS}});

  readingsBeginUpdate($hash);
  foreach my $rd (@updates){
    next if (!$rd);
    my ($rdName, $rdVal) = split(":",$rd, 2);
    delete $curRead{$rdName};
    next if (defined $hash->{READINGS}{$rdName} &&
                     $hash->{READINGS}{$rdName}{VAL} eq $rdVal);
    readingsBulkUpdate($hash,$rdName,
                             ((defined($rdVal) && $rdVal ne "") ? $rdVal : 0));
  }
  readingsEndUpdate($hash,1);

  delete $hash->{READINGS}{$_} foreach(keys %curRead);
  
  return;
}
sub HMinfo_autoUpdate($){#in:name, send status-request#########################
  my $name = shift;
  (undef,$name)=split":",$name,2;
  HMinfo_SetFn($defs{$name},$name,"update") if ($name);
  if (AttrVal($name,"autoArchive",undef) && 
      scalar(keys%{$modules{CUL_HM}{helper}{confUpdt}})){
    my $fn = HMinfo_getConfigFile($name,"configFilename",undef);
    HMinfo_archConfig($defs{$name},$name,"",$fn);
  }
  InternalTimer(gettimeofday()+$defs{$name}{helper}{autoUpdate},
                "HMinfo_autoUpdate","sUpdt:".$name,0)
        if (defined $defs{$name}{helper}{autoUpdate});
}

sub HMinfo_getParam(@) { ######################################################
  my ($id,@param) = @_;
  my @paramList;
  my $ehash = $modules{CUL_HM}{defptr}{$id};
  my $eName = $ehash->{NAME};
  my $found = 0;
  foreach (@param){
    my $para = CUL_HM_Get($ehash,$eName,"param",$_);
    $para =~ s/,/ ,/g;
    push @paramList,sprintf("%-15s",($para eq "undefined"?" -":$para));
    $found = 1 if ($para ne "undefined") ;
  }
  return $found,sprintf("%-20s\t: %s",$eName,join "\t| ",@paramList);
}
sub HMinfo_regCheck(@) { ######################################################
  my @entities = @_;
  my @regIncompl;
  my @regMissing;
  my @regChPend;

  foreach my $eName (@entities){
    my $ehash = $defs{$eName};
    next if (!$ehash);

    my @lsNo = CUL_HM_reglUsed($eName);
    my @mReg = ();
    my @iReg = ();

    foreach my $rNm (@lsNo){# check non-peer lists
      next if (!$rNm || $rNm eq "");
      if (   !$ehash->{READINGS}{$rNm}
          || !$ehash->{READINGS}{$rNm}{VAL})            {push @mReg, $rNm;}
      elsif ( $ehash->{READINGS}{$rNm}{VAL} !~ m/00:00/){push @iReg, $rNm;}
    }
    if ($ehash->{helper}{shadowReg} && ref($ehash->{helper}{shadowReg}) eq 'HASH'){
      foreach my $rl (keys %{$ehash->{helper}{shadowReg}}){
        my $pre =  (CUL_HM_getAttrInt($eName,"expert") & 0x02)?"":".";#raw register on

        delete $ehash->{helper}{shadowReg}{$rl} 
              if (   ( !$ehash->{helper}{shadowReg}{$rl}) # content is missing
                  ||(   $ehash->{READINGS}{$pre.$rl} 
                     && $ehash->{READINGS}{$pre.$rl}{VAL} eq $ehash->{helper}{shadowReg}{$rl}
                     )                                  # content is already displayed
                   );
      }
      push @regChPend,$eName.":" if (keys %{$ehash->{helper}{shadowReg}});
    }      
                                                      
    push @regMissing,$eName.":\t".join(",",@mReg) if (scalar @mReg);
    push @regIncompl,$eName.":\t".join(",",@iReg) if (scalar @iReg);
  }
  my $ret = "";
  $ret .="\n\n idRc01\n    ".(join "\n    ",sort @regMissing) if(@regMissing);
  $ret .="\n\n idRc02\n    ".(join "\n    ",sort @regIncompl) if(@regIncompl);
  $ret .="\n\n idRc03\n    ".(join "\n    ",sort @regChPend)  if(@regChPend);
  return  $ret;
}
sub HMinfo_peerCheck(@) { #####################################################
  my @entities = @_;
  my @peerIDsFail;
  my @peerIDnotDef;
  my @peerIDsNoPeer;
  my @peerIDsTrigUnp;
  my @peerIDsTrigUnd;
  my @peerIDsTeamRT;
  my @peeringStrange; # devices likely should not be peered 
  my @peerIDsAES;
  foreach my $eName (@entities){
    next if (!$defs{$eName}{helper}{role}{chn});#device has no channels
    my $peersUsed = CUL_HM_getPeers($eName,"Config");#
    next if ($peersUsed == 0);# no peers expected
        
    my $peerIDs = join(",",CUL_HM_getPeers($eName,"IDs"));

    foreach (grep /^......$/, HMinfo_noDup(map {CUL_HM_name2Id(substr($_,8))} 
                                           grep /^trigDst_/,
                                           keys %{$defs{$eName}{READINGS}})){
      push @peerIDsTrigUnp,"$eName:\t".$_ 
            if(  ($peerIDs &&  $peerIDs !~ m/$_/)
               &&("CCU-FHEM" ne AttrVal(CUL_HM_id2Name($_),"model","")));
      push @peerIDsTrigUnd,"$eName:\t".$_ 
            if(!$modules{CUL_HM}{defptr}{$_});
    }
    
    if($peersUsed == 2){#peerList incomplete
      push @peerIDsFail,"$eName:\t".$peerIDs;
    }
    else{# work on a valid list
      my $id = $defs{$eName}{DEF};
      my ($devId,$chn) = unpack 'A6A2',$id;
      my $devN = CUL_HM_id2Name($devId);
      my $st = AttrVal($devN,"subType","");# from Device
      my $md = AttrVal($devN,"model","");
      next if ($st eq "repeater");
      if ($st eq 'smokeDetector'){
        push @peeringStrange,"$eName:\t not peered!! add SD to any team !!" if(!$peerIDs);
      }
      foreach my $pId (CUL_HM_getPeers($eName,"IDsExt")){
        if (length($pId) != 8){
          push @peerIDnotDef,"$eName:\t id:$pId  invalid format";
          next;
        }
        my ($pDid,$pChn) = unpack'A6A2',$pId;
        if (!$modules{CUL_HM}{defptr}{$pId} && 
            (!$pDid || !$modules{CUL_HM}{defptr}{$pDid})){
          next if($pDid && CUL_HM_id2IoId($id) eq $pDid);
          push @peerIDnotDef,"$eName:\t id:$pId";
          next;
        }
        my $pName = CUL_HM_id2Name($pId);
        $pName =~s/_chn-0[10]//;           #chan 01 could be covered by device
        my $pPlist = AttrVal($pName,"peerIDs","");
        my $pDName = CUL_HM_id2Name($pDid);
        my $pSt = AttrVal($pDName,"subType","");
        my $pMd = AttrVal($pDName,"model","");
        if($st =~ m/(pushButton|remote)/){ # type of primary device
          if($pChn eq "00"){
            foreach (CUL_HM_getAssChnNames($pDName)){
              $pPlist .= AttrVal($_,"peerIDs","");
            }
          }
        }
        push @peerIDsNoPeer,"$eName:\t p:$pName"
              if (  (!$pPlist || $pPlist !~ m/$devId/) 
                  && $st ne 'smokeDetector'
                  && $pChn !~ m/0[x0]/
                  );
        if ($pSt eq "virtual"){
          if (AttrVal($devN,"aesCommReq",0) != 0){
            push @peerIDsAES,"$eName:\t p:".$pName     
                  if ($pMd ne "CCU-FHEM");
          }
        }
        elsif ($md eq "HM-CC-RT-DN"){
          if ($chn =~ m/(0[45])$/){ # special RT climate
            my $c = $1 eq "04"?"05":"04";
            push @peerIDsNoPeer,"$eName:\t pID:".$pId if ($pId !~ m/$c$/);
            if ($pMd !~ m/HM-CC-RT-DN/ ||$pChn !~ m/(0[45])$/ ){
              push @peeringStrange,"$eName:\t pID: Model $pMd should be HM-CC-RT-DN ClimatTeam channel";
            }
            elsif($chn eq "04"){
              # compare templist template are identical and boost is same
              my $rtCn = CUL_HM_id2Name(substr($pId,0,6)."04");
              my $ob = CUL_HM_Get($defs{$eName},$eName,"regVal","boostPeriod",0,0);
              my $pb = CUL_HM_Get($defs{$rtCn} ,$rtCn ,"regVal","boostPeriod",0,0);
              my $ot = AttrVal($eName,"tempListTmpl","--");
              my $pt = AttrVal($rtCn ,"tempListTmpl","--");
              push @peerIDsTeamRT,"$eName:\t team:$rtCn  boost differ  $ob / $pb"        if ($ob ne $pb);
              push @peerIDsTeamRT,"$eName:\t team:$rtCn  tempListTmpl differ  $ot / $pt" if ($ot ne $pt);
            }
          }
          elsif($chn eq "02"){
            if($pChn ne "02" ||$pMd ne "HM-TC-IT-WM-W-EU" ){
              push @peeringStrange,"$eName:\t pID: Model $pMd should be HM-TC-IT-WM-W-EU Climate channel";
            }
          }
        }
        elsif ($md eq "HM-TC-IT-WM-W-EU"){
          if($chn eq "02"){
            if($pChn ne "02" ||$pMd ne "HM-CC-RT-DN" ){
              push @peeringStrange,"$eName:\t pID: Model $pMd should be HM-TC-IT-WM-W-EU Climate Channel";
            }
            else{
              # compare templist template are identical and boost is same
              my $rtCn = CUL_HM_id2Name(substr($pId,0,6)."04");
              my $ob = CUL_HM_Get($defs{$eName},$eName,"regVal","boostPeriod",0,0);
              my $pb = CUL_HM_Get($defs{$rtCn} ,$rtCn ,"regVal","boostPeriod",0,0);
              my $ot = AttrVal($eName,"tempListTmpl","--");
              my $pt = AttrVal($rtCn ,"tempListTmpl","--");
              push @peerIDsTeamRT,"$eName:\t team:$rtCn  boost differ $ob / $pb" if ($ob ne $pb);
              # if templates differ AND RT template is not static then notify a difference
              push @peerIDsTeamRT,"$eName:\t team:$rtCn  tempListTmpl differ $ot / $pt" if ($ot ne $pt && $pt ne "defaultWeekplan");
            }
          }
        }
      }
    }
  }
  my $ret = "";
  $ret .="\n\n idPz00\n    ".(join "\n    ",sort @peerIDsFail   )if(@peerIDsFail);
  $ret .="\n\n idPz01\n    ".(join "\n    ",sort @peerIDnotDef  )if(@peerIDnotDef);
  $ret .="\n\n idPz02\n    ".(join "\n    ",sort @peerIDsNoPeer )if(@peerIDsNoPeer);
  $ret .="\n\n idPz03\n    ".(join "\n    ",sort @peeringStrange)if(@peeringStrange);
  $ret .="\n\n idPz04\n    ".(join "\n    ",sort @peerIDsTrigUnp)if(@peerIDsTrigUnp);
  $ret .="\n\n idPz05\n    ".(join "\n    ",sort @peerIDsTrigUnd)if(@peerIDsTrigUnd);
  $ret .="\n\n idPz06\n    ".(join "\n    ",sort @peerIDsAES    )if(@peerIDsAES);
  $ret .="\n\n idPz07\n    ".(join "\n    ",sort @peerIDsTeamRT )if(@peerIDsTeamRT);
  
  return  $ret;
}
sub HMinfo_burstCheck(@) { ####################################################
  my @entities = @_;
  my @needBurstMiss;
  my @needBurstFail;
  my @peerIDsCond;
  foreach my $eName (@entities){
    next if (!$defs{$eName}{helper}{role}{chn}         #entity has no channels
          || CUL_HM_getPeers($eName,"Config") != 1              #entity not peered or list incomplete
          || CUL_HM_Get($defs{$eName},$eName,"regList")#option not supported
             !~ m/peerNeedsBurst/);

    my $devId = substr($defs{$eName}{DEF},0,6);
    my @peers = CUL_HM_getPeers($eName,"NamesExt");
    next if(0 == scalar (@peers));                     # no peers assigned

    foreach my $pn (@peers){
      $pn =~ s/_chn:/_chn-/; 
      my $prxt = CUL_HM_getRxType($defs{$pn});
      
      next if (!($prxt & 0x82)); # not a burst peer
      
      my ($pnb) = map{$defs{$eName}{READINGS}{$_}{VAL}}
                  grep/\.?R-$pn(_chn-..)?-peerNeedsBurst/,
                  keys%{$defs{$eName}{READINGS}};

      if (!$pnb)           {push @needBurstMiss, "$eName:\t$pn";}
      elsif($pnb !~ m /on/){push @needBurstFail, "$eName:\t$pn";}

      if ($prxt & 0x80){# conditional burst - is it on?
        my $pDevN = CUL_HM_getDeviceName($pn);
        push @peerIDsCond," $pDevN:\t for remote $eName" if (ReadingsVal($pDevN,"R-burstRx",ReadingsVal($pDevN,".R-burstRx","")) !~ m /on/);
      }
    }
  }
  my $ret = "";
  $ret .="\n\n idBc01\n    ".(join "\n    ",sort @needBurstMiss) if(@needBurstMiss);
  $ret .="\n\n idBc02\n    ".(join "\n    ",sort @needBurstFail) if(@needBurstFail);
  $ret .="\n\n idBc03\n    ".(join "\n    ",sort @peerIDsCond)   if(@peerIDsCond);
  return  $ret;
}
sub HMinfo_paramCheck(@) { ####################################################
  my @entities = @_;
  my @noIoDev;
  my @noID;
  my @idMismatch;
  my @ccuUndef;
  my @perfIoUndef;
  foreach my $eName (@entities){
    if ($defs{$eName}{helper}{role}{dev}){
      my $ehash = $defs{$eName};
      my $pairId =  ReadingsVal($eName,"R-pairCentral", ReadingsVal($eName,".R-pairCentral","undefined"));
      my $IoDev =  $ehash->{IODev} ? $ehash->{IODev} :undef;
      if (!$IoDev || !$IoDev->{NAME}){push @noIoDev,"$eName:\t";next;}
      my $ioHmId = AttrVal($IoDev->{NAME},"hmId","-");
      my ($ioCCU,$prefIO) = split":",AttrVal($eName,"IOgrp","");
      if ($ioCCU){
        if(   !$defs{$ioCCU}
           || AttrVal($ioCCU,"model","") ne "CCU-FHEM"
           || !$defs{$ioCCU}{helper}{role}{dev}){
          push @ccuUndef,"$eName:\t ->$ioCCU";
        }
        else{
          $ioHmId = $defs{$ioCCU}{DEF};
          if ($prefIO){
            my @pIOa = split(",",$prefIO);
            push @perfIoUndef,"$eName:\t ->$_"  foreach ( grep {!$defs{$_}} grep !/^none$/,@pIOa);
          }            
        }
      }
      if (!$IoDev)                  { push @noIoDev,"$eName:\t";}
                                    
      if (   !$defs{$eName}{helper}{role}{vrt} 
          && AttrVal($eName,"model","") ne "CCU-FHEM"){
        if ($pairId eq "undefined") { push @noID,"$eName:\t";}
        elsif ($pairId !~ m /$ioHmId/
             && $IoDev )            { push @idMismatch,"$eName:\t paired:$pairId IO attr: ${ioHmId}.";}
      }
    }
  }

  my $ret = "";
  $ret .="\n\n idPc00\n    ".(join "\n    ",sort @noIoDev)    if (@noIoDev);
  $ret .="\n\n idPc01\n    ".(join "\n    ",sort @noID)       if (@noID);
  $ret .="\n\n idPc02\n    ".(join "\n    ",sort @idMismatch) if (@idMismatch);
  $ret .="\n\n idPc03\n    ".(join "\n    ",sort @ccuUndef)   if (@ccuUndef);
  $ret .="\n\n idPc04\n    ".(join "\n    ",sort @perfIoUndef)if (@perfIoUndef);
 return  $ret;
}
sub HMinfo_applTxt2Check($) { #################################################
  my $ret = shift;
  $ret =~ s/-ret--ret- idCl00-ret-.*?-ret-/-ret-/;
  $ret =~ s/$_/$chkIds{$_}{txt}/g foreach(keys %chkIds); 
  return $ret;
}
sub HMinfo_getTxt2Check($) { ##################################################
  my $id = shift;
  if(defined $chkIds{$id}){
    return ($chkIds{$id}{Fkt}
           ,$chkIds{$id}{shtxt}
           ,$chkIds{$id}{txt}
           );  
  }
  else{
    return ("unknown");
  }
}


sub HMinfo_tempList(@) { ######################################################
  my ($hiN,$filter,$action,$fName)=@_;
  $filter = "." if (!$filter);
  $action = "" if (!$action);
  my %dl =("Sat"=>0,"Sun"=>1,"Mon"=>2,"Tue"=>3,"Wed"=>4,"Thu"=>5,"Fri"=>6);
  my $ret;
  
  if    ($action eq "save"){
    my @chList;
    my @storeList;
    my @incmpl;
    foreach my $eN(HMinfo_getEntities("d")){#search and select channel
      my $md = AttrVal($eN,"model","");
      my $chN; #tempList channel name
      if ($md =~ m/(HM-CC-RT-DN-BOM|HM-CC-RT-DN)/){
        $chN = $defs{$eN}{channel_04};
      }
      elsif ($md =~ m/(ROTO_ZEL-STG-RM-FWT|HM-CC-TC|HM-TC-IT-WM-W-EU)/){
        $chN = $defs{$eN}{channel_02};
      }
      if ($chN && $defs{$chN} && $chN =~ m/$filter/){
        my @tl = sort grep /tempList(P[123])?[SMFWT]/,keys %{$defs{$chN}{READINGS}};
        if (scalar @tl != 7 && scalar @tl != 21){
          push @incmpl,$chN;
          next;
        }
        else{
          push @chList,$chN;
          push @storeList,"entities:$chN";
          foreach my $rd (@tl){
            #print aSave "\n$rd>$defs{$chN}{READINGS}{$rd}{VAL}";
            push @storeList,"$rd>$defs{$chN}{READINGS}{$rd}{VAL}";
          }
        }
      }
    }
    my  @oldList;
    
    my ($err,@RLines) = FileRead($fName);
    push (@RLines, "#init")  if ($err);
    my $skip = 0;
    foreach(@RLines){
      chomp;
      my $line = $_;
      $line =~ s/\r//g;
      if ($line =~ m/entities:(.*)/){
        my $eFound = $1;
        if (grep /\b$eFound\b/,@chList){
          # renew this entry
          $skip = 1;
        }
        else{
          $skip = 0;
        }
      }
      push @oldList,$line if (!$skip);
    }
    my @WLines = grep !/^$/,(@oldList,@storeList);
    $err = FileWrite($fName,@WLines);
    return "file: $fName error write:$err"  if ($err);

    $ret = "incomplete data for ".join("\n     ",@incmpl) if (scalar@incmpl);
    HMinfo_listOfTempTemplates(); # refresh - maybe there are new entries in the files. 
  }
  elsif ($action =~ m/(verify|restore)/){
    $ret = HMinfo_tempListTmpl($hiN,$filter,"",$action,$fName);
  }
  else{
    $ret = "$action unknown option - please use save, verify or restore";
  }
  return $ret;
}
sub HMinfo_tempListTmpl(@) { ##################################################
  my ($hiN,$filter,$tmpl,$action,$fName)=@_;
  $filter = "." if (!$filter);
  my %dl =("Sat"=>0,"Sun"=>1,"Mon"=>2,"Tue"=>3,"Wed"=>4,"Thu"=>5,"Fri"=>6);
  my $ret = "";
  my @el ;
  foreach my $eN(HMinfo_getEntities("d")){#search for devices and select correct channel
    next if (!$eN);
    my $md = AttrVal($eN,"model","");
    my $chN; #tempList channel name
    if    ($md =~ m/(HM-CC-RT-DN-BOM|HM-CC-RT-DN)/){$chN = $defs{$eN}{channel_04};}
    elsif ($md =~ m/(ROTO_ZEL-STG-RM-FWT|-TC)/)    {$chN = $defs{$eN}{channel_02};}
    next if (!$chN || !$defs{$chN} || $chN !~ m/$filter/);
    push @el,$chN;
  }
  return "no entities selected" if (!scalar @el);
  $fName = HMinfo_tempListDefFn($fName);
  my $cfgDir; ($cfgDir = $fName) =~ s/(.*\/).*/$1/;
  $tmpl =  $fName.":".$tmpl if($tmpl);
  my @rs;
  foreach my $name (@el){
   my $tmplDev = $tmpl ? $tmpl
                        : AttrVal($name,"tempListTmpl",$fName.":$name");

    if   ($tmplDev !~ m/:/) { $tmplDev = $fName.":$tmplDev";}
    elsif($tmplDev !~ m/\//){ $tmplDev = $cfgDir."$tmplDev";}
    my $r = CUL_HM_tempListTmpl($name,$action,$tmplDev);
    HMinfo_regCheck($name);#clean helper data (shadowReg) after restore
    if($action eq "restore"){
      push @rs,  (keys %{$defs{$name}{helper}{shadowReg}}? "restore: $tmplDev for $name"
                                                         : "passed : $tmplDev for $name")
                                                         ."\n";
    }
    else{
      $tmplDev =~ s/$defs{$hiN}{helper}{weekplanListDef}://;
      $tmplDev =~ s/$defs{$hiN}{helper}{weekplanListDir}//;

      push @rs,  ($r ? "fail  : $tmplDev for $name: $r"
                     : "passed: $tmplDev for $name")
                 ."\n";
    }
  }

  $ret .= join "",sort @rs;
  return $ret;
}
sub HMinfo_tempListTmplView() { ###############################################
  my %tlEntitys;
  $tlEntitys{$_}{v} = 1 foreach ((devspec2array("TYPE=CUL_HM:FILTER=model=HM-CC-RT.*:FILTER=chanNo=04")
                                 ,devspec2array("TYPE=CUL_HM:FILTER=model=.*-TC.*:FILTER=chanNo=02")));
  my ($n) = devspec2array("TYPE=HMinfo");
  my $defFn = HMinfo_tempListDefFns();
  my @tlFiles = split('[;,]',$defFn);         # list of tempfiles
  $defFn = $defs{$n}{helper}{weekplanListDef};# default tempfile
  
  my @dWoTmpl;    # Device not using templates
  foreach my $d (keys %tlEntitys){
    my ($tf,$tn) = split(":",AttrVal($d,"tempListTmpl","empty"));
    ($tf,$tn) = ($defFn,$tf) if (!defined $tn); # no file given, switch parameter
    $tf = $defs{$n}{helper}{weekplanListDir}.$tf if($tf !~ m/\//);
    if($tn =~ m/^(none|0) *$/){
      push @dWoTmpl,$d;
    }
    else{
      push @tlFiles,$tf;
    }
  }
  @tlFiles = HMinfo_noDup(@tlFiles);
  
  my @tlFileMiss;
  foreach my $fName (@tlFiles){#################################
    my ($err,@RLines) = FileRead($fName);
    push @tlFileMiss,"$fName - $err"  if ($err);
  }
  
  my @tNfound = ();    # templates found in files
  push @tNfound, @{$defs{$n}{helper}{weekplanList}} if (defined $defs{$n}{helper}{weekplanList} 
                                                 && ref($defs{$n}{helper}{weekplanList}) eq 'ARRAY'
                                                 && 0 < scalar(@{$defs{$n}{helper}{weekplanList}}));

  ####################################################
  my $ret = "";
  $ret .= "\ndefault templatefile: $defFn";
  $ret .= "\ndefault path        : $defs{$n}{helper}{weekplanListDir}\n   ";
  $ret .= "\nfiles referenced but not found:\n   " .join("\n      =>  ",sort @tlFileMiss) if (@tlFileMiss);
  $ret .= "\navailable templates\n   "             .join("\n   "       ,sort @tNfound)    if (@tNfound);
  $ret .= "\n\n ---------components-----------\n";
  $ret .= HMinfo_tempList($n,"","verify","");
  $ret .= "\ndevices not using tempList templates:\n      =>  "   .join("\n      =>  ",@dWoTmpl) if (@dWoTmpl);
  return $ret;
}
sub HMinfo_tempListDefFns(@) { ################################################
  my ($fn) = shift;
  $fn = "" if (!defined $fn);
  
  my ($n) = devspec2array("TYPE=HMinfo");
  return HMinfo_getConfigFile($n,"configTempFile",$fn);
}
sub HMinfo_tempListDefFn(@) { #################################################
  my $fn = HMinfo_tempListDefFns(@_);
  $fn =~ s/;.*//; # only use first file - this is default
  return $fn;
}
sub HMinfo_listOfTempTemplates() { ############################################
  # search all entries in tempListFile
  # provide helper: weekplanList & weekplanListDef
  my ($n) =devspec2array("TYPE=HMinfo");

  my $dir = AttrVal($n,"configDir","$attr{global}{modpath}/")."/"; #no dir?  add defDir
  $dir = "./".$dir if ($dir !~ m/^(\.|\/)/);
  $dir =~ s/\/\//\//g;

  my @tFiles = split('[;,]',AttrVal($n,"configTempFile","tempList.cfg"));
  $defs{$n}{helper}{weekplanListDef} = $dir.$tFiles[0].":";
  $defs{$n}{helper}{weekplanListDef} =~ s/://;
  $defs{$n}{helper}{weekplanListDir} = $dir;

  my $tDefault = $defs{$n}{helper}{weekplanListDef};#short
  my @tmpl;
  
  foreach my $fName (map{$dir.$_}@tFiles){
    my ($err,@RLines) = FileRead($fName);
    next if ($err);
    
    foreach(@RLines){
      chomp;
      my $line = $_;
      $line =~ s/\r//g;
      if($line =~ m/^entities:(.*)/){
        my $l =$1;
        $l =~s/.*://;
        push @tmpl,map{"$fName:$_"}split(",",$l);
      }  
    }
  }
  @tmpl = map{s/$tDefault://;$_} @tmpl;# first default template!
  @tmpl = map{s/$dir//;$_}      @tmpl;# then only the default dir -if avaialble
  
  $defs{$n}{helper}{weekplanList} = \@tmpl;
  if ($modules{CUL_HM}{AttrList}){
    $modules{CUL_HM}{tempListTmplLst} = "none,defaultWeekplan,".join(",",sort @tmpl);
    CUL_HM_AttrInit($modules{CUL_HM}) if (eval "defined(&CUL_HM_AttrInit)");
  }
  return ;
}

sub HMinfo_tempListTmplGenLog($$) { ###########################################
  my ($hiN,$fName) = @_;
  $fName = HMinfo_tempListDefFn($fName);

  my @eNl = ();
  my %wdl = ( tempListSun =>"02"
             ,tempListMon =>"03"
             ,tempListTue =>"04"
             ,tempListWed =>"05"
             ,tempListThu =>"06"
             ,tempListFri =>"07"
             ,tempListSat =>"08");
  my @plotL;
  
  my ($err,@RLines) = FileRead($fName);
  return "file: $fName error:$err"  if ($err);

  foreach(@RLines){
    chomp;
    my $line = $_;

    next if($line =~ m/#/);
    if($line =~ m/^entities:/){
      @eNl = ();
      my $eN = $line;
      $line =~s/.*://;
      foreach my $eN (split(",",$line)){
        $eN =~ s/ //g;
        push @eNl,$eN;
      }
    }
    elsif($line =~ m/(R_)?(P[123])?(_?._)?(tempList[SMFWT]..)(.*)\>/){
      my ($p,$wd,$lst) = ($2,$4,$line);
      $lst =~s/.*>//;
      $lst =~ tr/ +/ /;
      $lst =~ s/^ //;
      $lst =~ s/ $//;
      my @tLst = split(" ","00:00 00.0 ".$lst);
      $p = "" if (!defined $p);
      for (my $cnt = 0;$cnt < scalar(@tLst);$cnt+=2){
        last if ($tLst[$cnt] eq "24:00");
        foreach my $e (@eNl){
          push @plotL,"2000-01-$wdl{$wd}_$tLst[$cnt]:00 $e$p $tLst[$cnt+3]";
        }        
      }
    }
  }
  
  my @WLines;
  my %eNh;
  foreach (sort @plotL){
    push @WLines,$_;
    my (undef,$eN) = split " ",$_;
    $eNh{$eN} = 1;
  }
  $err = FileWrite($fName,@WLines);
  return "file: $fName error write:$err"  if ($err);
  HMinfo_tempListTmplGenGplot($fName,keys %eNh);
}
sub HMinfo_tempListTmplGenGplot(@) { ##########################################
  my ($fName,@eN) = @_;
  my $fNfull = $fName;
  $fName =~ s/.cfg$//; # remove extention
  $fName =~ s/.*\///; # remove directory
      #define weekLogF FileLog ./setup/tempList.cfg.log none
      #define wp SVG weekLogF:tempList:CURRENT
      #attr wp fixedrange week
      #attr wp startDate 2000-01-02
  if (!defined($defs{"${fName}_Log"})){
    CommandDefine(undef,"${fName}_Log FileLog ${fNfull}.log none");
  }
  if (!defined($defs{"${fName}_SVG"})){
    CommandDefine(undef,"${fName}_SVG SVG ${fName}_Log:${fName}:CURRENT");
    CommandAttr(undef, "${fName}_SVG fixedrange week");
    CommandAttr(undef, "${fName}_SVG startDate 2000-01-02");
  }

  $fName = "./www/gplot/$fName.gplot";
  my @WLines;
  push @WLines,"# Created by FHEM/98_HMInfo.pm, ";
  push @WLines,"set terminal png transparent size <SIZE> crop";
  push @WLines,"set output '<OUT>.png'";
  push @WLines,"set xdata time";
  push @WLines,"set timefmt \"%Y-%m-%d_%H:%M:%S\"";
  push @WLines,"set xlabel \" \"";
  push @WLines,"set title 'weekplan'";
  push @WLines,"set ytics ";
  push @WLines,"set grid ytics";
  push @WLines,"set ylabel \"Temperature\"";
  push @WLines,"set y2tics ";
  push @WLines,"set y2label \"invisib\"";
  push @WLines,"set y2range [99:99]";
  push @WLines," ";

  my $cnt = 0;
  my ($func,$plot) = ("","\n\nplot");
  foreach my $e (sort @eN){
    $func .= "\n#FileLog 3:$e\.\*::";
    if ($cnt++ < 8){
      $plot .= (($cnt ==0)?"":",")
               ."\\\n     \"<IN>\" using 1:2 axes x1y1 title '$e' ls l$cnt lw 0.5 with steps";
    }
  }
  
  push @WLines,$func.$plot;
  my $err = FileWrite($fName,@WLines);
  return "file: $fName error write:$err"  if ($err);
}

sub HMinfo_getEntities(@) { ###################################################
  my ($filter,$re) = @_;
  my @names;
  my ($doDev,$doChn,$doEmp)= (1,1,1,1,1,1,1,1);
  my ($doIgn,$noVrt,$noPhy,$noAct,$noSen) = (0,0,0,0,0,0,0,0,0,0);
  $filter .= "dc" if ($filter !~ m/d/ && $filter !~ m/c/); # add default
  $re = '.' if (!$re);
  if ($filter){# options provided
    $doDev=$doChn=$doEmp= 0;#change default
    no warnings;
    my @pl = split undef,$filter;
    use warnings;
    foreach (@pl){
      $doDev = 1 if($_ eq 'd');
      $doChn = 1 if($_ eq 'c');
      $doIgn = 1 if($_ eq 'i');
      $noVrt = 1 if($_ eq 'v');
      $noPhy = 1 if($_ eq 'p');
      $noAct = 1 if($_ eq 'a');
      $noSen = 1 if($_ eq 's');
      $doEmp = 1 if($_ eq 'e');
      $doAli = 1 if($_ eq '2');
    }
  }
  # generate entity list
  foreach my $id (sort(keys%{$modules{CUL_HM}{defptr}})){
    next if ($id eq "000000");
    my $eHash = $modules{CUL_HM}{defptr}{$id};
    my $eName = $eHash->{NAME};
    next if ( !$eName || $eName !~ m/$re/);
    my $eIg   = CUL_HM_getAttr($eName,"ignore","");
    next if (!$doIgn && $eIg);
    next if (!(($doDev && $eHash->{helper}{role}{dev}) ||
               ($doChn && $eHash->{helper}{role}{chn})));
    next if ( $noVrt && $eHash->{helper}{role}{vrt});
    next if ( $noPhy && !$eHash->{helper}{role}{vrt});
    my $eSt = CUL_HM_getAttr($eName,"subType","");

    next if ( $noSen && $eSt =~ m/^(THSensor|remote|pushButton|threeStateSensor|sensor|motionDetector|swi)$/);
    next if ( $noAct && $eSt =~ m/^(switch|blindActuator|dimmer|thermostat|smokeDetector|KFM100|outputUnit)$/);
    push @names,$eName;
  }
  return sort(@names);
}
sub HMinfo_getMsgStat() { #####################################################
  my ($hr,$dr,$hs,$ds,$hrb,$drb,$hsb,$dsb);
  my ($hstr,$dstr) = (" "," ");
  $hstr .= sprintf("| %02d",$_) foreach (0..23);
  $dstr .= sprintf("|%4s",$_)   foreach ("Mon","Tue","Wed","Thu","Fri","Sat","Sun","# 24h");

  $hr      = "\nreceive       " .$hstr;
  $hs      = "\nsend          ";
  $hrb     = "\nreceive burst ";
  $hsb     = "\nsend    burst ";
  $dr      = "\nreceive       " .$dstr;
  $ds      = "\nsend          ";
  $drb     = "\nreceive burst ";
  $dsb     = "\nsend    burst ";
  my $tsts = "\n               |";
  foreach my $ioD(keys %{$modules{CUL_HM}{stat}{r}}){
    next if ($ioD eq "dummy");
    my $ioDs = sprintf("\n    %-10s:",$ioD);
    $hr .=  $ioDs;
    $hs .=  $ioDs;
    $hrb.=  $ioDs;
    $hsb.=  $ioDs;
    $dr .=  $ioDs;
    $ds .=  $ioDs;
    $drb.=  $ioDs;
    $dsb.=  $ioDs;
    $hr .=  sprintf("|%3d",$modules{CUL_HM}{stat}{r}{$ioD}{h}{$_})  foreach (0..23);
    $hs .=  sprintf("|%3d",$modules{CUL_HM}{stat}{s}{$ioD}{h}{$_})  foreach (0..23);
    $hrb.=  sprintf("|%3d",$modules{CUL_HM}{stat}{rb}{$ioD}{h}{$_}) foreach (0..23);
    $hsb.=  sprintf("|%3d",$modules{CUL_HM}{stat}{sb}{$ioD}{h}{$_}) foreach (0..23);
    $dr .=  sprintf("|%4d",$modules{CUL_HM}{stat}{r}{$ioD}{d}{$_})  foreach (0..6);
    $ds .=  sprintf("|%4d",$modules{CUL_HM}{stat}{s}{$ioD}{d}{$_})  foreach (0..6);
    $drb.=  sprintf("|%4d",$modules{CUL_HM}{stat}{rb}{$ioD}{d}{$_}) foreach (0..6);
    $dsb.=  sprintf("|%4d",$modules{CUL_HM}{stat}{sb}{$ioD}{d}{$_}) foreach (0..6);
  
    my ($tdr,$tds,$tdrb,$tdsb);
    $tdr  += $modules{CUL_HM}{stat}{r}{$ioD}{h}{$_}  foreach (0..23);
    $tds  += $modules{CUL_HM}{stat}{s}{$ioD}{h}{$_}  foreach (0..23);
    $tdrb += $modules{CUL_HM}{stat}{rb}{$ioD}{h}{$_} foreach (0..23);
    $tdsb += $modules{CUL_HM}{stat}{sb}{$ioD}{h}{$_} foreach (0..23);
    $dr .=  sprintf("|#%4d",$tdr);
    $ds .=  sprintf("|#%4d",$tds);
    $drb.=  sprintf("|#%4d",$tdrb);
    $dsb.=  sprintf("|#%4d",$tdsb);
  }
  my @l = localtime(gettimeofday());
  $tsts .=  "----" foreach (1..$l[2]);
  $tsts .=  ">*" ;
  return  "msg statistics\n"
           .$tsts
           .$hr.$hs.$hrb.$hsb
           ."\n              ".$hstr
           .$tsts
           .$dr.$ds.$drb.$dsb
           ."\n              ".$dstr
           ;
}

sub HMinfo_getCfgDefere($){####################################################
  my $hm = shift;
  if(  !defined $hm
     ||!defined $defs{$hm}
     ||!defined $defs{$hm}{helper}
     ||!defined $defs{$hm}{helper}{nbPend}
     ){
    return;
   }
  HMinfo_GetFn($defs{$hm},$hm,"configCheck","-f","^(".'\^('.join("|",@{$defs{$hm}{helper}{nbPend}}).')\$'.")\$");  
}

sub HMinfo_startBlocking(@){###################################################
  my ($name,$fkt,$param) = @_;
  my $hash = $defs{$name};
  Log3 $hash,4,"HMinfo $name start blocking:$fkt";
  my $id = ++$hash->{nb}{cnt};
  my $bl = BlockingCall($fkt, "$name;$id;$hash->{CL}{NAME},$param", 
                        "HMinfo_bpPost", 30, 
                        "HMinfo_bpAbort", "$name:0");
  $hash->{nb}{$id}{$_} = $bl->{$_} foreach (keys %{$bl});
}

sub HMinfo_GetFn($@) {#########################################################
  my ($hash,$name,$cmd,@a) = @_;
  my ($opt,$optEmpty,$filter) = ("",1,"");
  my $ret;
  $doAli = 0;#set default
  Log3 $hash,3,"HMinfo $name get:$cmd :".join(",",@a) if ($cmd && $cmd ne "?");
  if (@a && ($a[0] =~ m/^(-[dcivpase2]+)/)){# options provided
    $opt = $1;
    $a[0] =~ s/^(-[dcivpase2]*)//;
    $optEmpty = ($opt =~ m/e/)?1:0;
    shift @a if($a[0] || $a[0] =~ m/^[ ]*$/); #remove
  }
  if (@a && $a[0] =~ m/^-f$/){# options provided
    shift @a; #remove
    if(scalar @a){
      my $a0 = shift @a;
      ($filter,$a0) = split(",",$a0,2);
      if(!defined $a0 || $a0 =~ m/^[ ]*$/){
        shift @a;
      }
      else{
        $a[0] = $a0;
      }
    }
  }

  $cmd = "?" if(!$cmd);# by default print options

  #------------ statistics ---------------
  if   ($cmd eq "protoEvents"){##print protocol-events-------------------------
    my ($type) = @a;
    $type = "all" if(!$type);
    my @paramList2;
    my @IOlist;
    my @plSum; push @plSum,0 for (0..11);#prefill
    my $maxNlen = 3;
    my @hdrA = ("name","protState","protCmdPend","protSnd","protSndB","protRcv","protRcvB"
               ,"protResnd","protCmdDel","protResndFail","protNack","protIOerr");
    foreach my $dName (HMinfo_getEntities($opt."dv",$filter)){
      my $id = $defs{$dName}{DEF};
      my $nl = length($dName); 
      $maxNlen = $nl if($nl > $maxNlen);
      my ($found,$para) = HMinfo_getParam($id,@hdrA[1..11]);
      $para =~ s/( last_at|20..-|\|)//g;
      my @pl = split "\t",$para;
      my $c = 0;
      foreach (@pl){
        $_ =~ s/\s+$|//g ;
        $_ =~ s/CMDs[_ ]//;
        if ($type ne "long"){
          $_ =~ s/:*..-.. ..:..:..//g;# if ($type eq "short");
          $plSum[$c] += $1 if ($_ =~ m/^\s*(\d+)/);
        }
        elsif($_ =~m /^[ ,0-9]{1,5}/){
           my ($cnt,$date) = split(":",$_,2);
           #$_ = sprintf("%-5s>%s",$cnt,$date) if (defined $date);
           $plSum[$c] +=$cnt if ($cnt =~ m/^\d+$/);
        }
        else{
        }
        $c++;
      }

      push @paramList2,[@pl];
      push @IOlist,$defs{$pl[0]}{IODev}->{NAME};
    }
    $maxNlen ++;
    my ($hdr,$ftr);
    my @paramList;
    $_ =~ s/prot// foreach(@hdrA);
    if ($type eq "short"){
      push @paramList, sprintf("%-${maxNlen}s%-17s|%-10s|%-10s|%-10s#%-10s|%-10s|%-10s|%-10s",
                    @{$_}[0..3],@{$_}[7..11]) foreach(@paramList2);
      $hdr = sprintf("%-${maxNlen}s:%-16s|%-10s|%-10s|%-10s#%-10s|%-10s|%-10s|%-10s",@hdrA[0..3],@hdrA[7..11]);
      $ftr = sprintf("%-${maxNlen}s%-17s|%-10s|%-10s|%-10s#%-10s|%-10s|%-10s|%-10s","sum",@plSum[1..3],@plSum[7..11]);
    }
    elsif ($type eq "all"){
      push @paramList, sprintf("%-${maxNlen}s%-17s|%-10s|%-10s|%-10s|%-10s|%-10s|%-10s#%-10s|%-10s|%-10s|%-10s",
                    @{$_}[0..11]) foreach(@paramList2);
      $hdr = sprintf("%-${maxNlen}s:%-16s|%-10s|%-10s|%-10s|%-10s|%-10s|%-10s#%-10s|%-10s|%-10s|%-10s",@hdrA[0..11]);
      $ftr = sprintf("%-${maxNlen}s%-17s|%-10s|%-10s|%-10s|%-10s|%-10s|%-10s#%-10s|%-10s|%-10s|%-10s","sum",@plSum[1..11]);
    }
    else{
      push @paramList, sprintf("%-${maxNlen}s%-17s|%-18s|%-20s|%-20s|%-20s|%-20s|%-20s#%-18s|%-20s|%-20s|%-20s",
                    @{$_}[0..11]) foreach(@paramList2);
      $hdr = sprintf("%-${maxNlen}s:%-16s|%-18s|%-20s|%-20s|%-20s|%-20s|%-20s#%-18s|%-20s|%-20s|%-20s",@hdrA[0..11]);
      $ftr = sprintf("%-${maxNlen}s%-17s|%-18s|%-20s|%-20s|%-20s|%-20s|%-20s#%-18s|%-20s|%-20s|%-20s","sum",@plSum[1..11]);
    }
    $ret = $cmd." send to devices done:" 
           ."\n    ".$hdr  
           ."\n    ".(join "\n    ",sort @paramList)
           ."\n"."=" x (length($hdr)+($type eq "long"? 10 : 0))
           ."\n    ".$ftr 
           ."\n"
           ."\n    CUL_HM queue length:$modules{CUL_HM}{prot}{rspPend}"
           ."\n"
           ."\n    requests pending"
           ."\n    ----------------"
           ."\n    autoReadReg          : ".join(" ",@{$modules{CUL_HM}{helper}{qReqConf}})
           ."\n        recent           : ".($modules{CUL_HM}{helper}{autoRdActive}?$modules{CUL_HM}{helper}{autoRdActive}:"none")
           ."\n    status request       : ".join(" ",@{$modules{CUL_HM}{helper}{qReqStat}}) 
           ."\n    autoReadReg wakeup   : ".join(" ",@{$modules{CUL_HM}{helper}{qReqConfWu}})
           ."\n    status request wakeup: ".join(" ",@{$modules{CUL_HM}{helper}{qReqStatWu}})
           ."\n    autoReadTest         : ".join(" ",map{CUL_HM_id2Name($_)} keys%{$modules{CUL_HM}{helper}{confCheckH}})
           ."\n"
           ;
    @IOlist = HMinfo_noDup(@IOlist);
    foreach(@IOlist){
      $_ .= ":".$defs{$_}{STATE}
            .(defined $defs{$_}{helper}{q}
                     ? " pending=".$defs{$_}{helper}{q}{answerPend}
                     : ""
             )
            ." condition:".ReadingsVal($_,"cond","-")
            .(defined $defs{$_}{msgLoadCurrent}
                     ? "\n            msgLoadCurrent: ".$defs{$_}{msgLoadCurrent}
                     : ""
             )
            ;
    }
    $ret .= "\n    IODevs:".(join"\n           ",HMinfo_noDup(@IOlist));
  }  
  elsif($cmd eq "msgStat")    {##print message statistics----------------------
    $ret = HMinfo_getMsgStat();
  }
  elsif($cmd =~ m/^(rssi|rssiG)$/){##print RSSI protocol-events----------------
    my ($type) = (@a,"full");# ugly way to set "full" as default
    my @rssiList = ();
    my %rssiH;
    my @io;
    foreach my $dName (HMinfo_getEntities($opt."dv",$filter)){
      foreach my $dest (keys %{$defs{$dName}{helper}{rssi}}){
        my $dispName = $dName;
        my $dispDest = $dest;
        if ($dest =~ m/^at_(.*)/){
          $dispName = $1;
          $dispDest = (($dest =~ m/^to_rpt_/)?"rep_":"").$dName;
        }
        if (AttrVal($dName,"subType","") eq "virtual"){
          my $h = InternalVal($dName,"IODev","");
          $dispDest .= "/$h->{NAME}";
        }
        if ($type eq "full"){
          push @rssiList,sprintf("%-15s ",$dName)
                        .($doAli ? sprintf("%-15s  ",AttrVal($dName,"alias","-")):"")
                        .sprintf("%-15s %-15s %6.1f %6.1f %6.1f<%6.1f %5s"
                                ,$dispName,$dispDest
                                ,$defs{$dName}{helper}{rssi}{$dest}{lst}
                                ,$defs{$dName}{helper}{rssi}{$dest}{avg}
                                ,$defs{$dName}{helper}{rssi}{$dest}{min}
                                ,$defs{$dName}{helper}{rssi}{$dest}{max}
                                ,$defs{$dName}{helper}{rssi}{$dest}{cnt}
                                );
        }
        else{
          my $dir = ($dName eq $dispName)?$dispDest." >":$dispName." <";
          push @io,$dir;
          $rssiH{$dName}{$dir}{min} = $defs{$dName}{helper}{rssi}{$dest}{min};
          $rssiH{$dName}{$dir}{avg} = $defs{$dName}{helper}{rssi}{$dest}{avg};
          $rssiH{$dName}{$dir}{max} = $defs{$dName}{helper}{rssi}{$dest}{max};
        }
      }
    }
    if   ($type eq "reduced"){
      @io = HMinfo_noDup(@io);
      my $s = sprintf("    %15s "," ");
      $s .= sprintf(" %12s",$_)foreach (@io);
      push @rssiList, $s;
      
      foreach my $d(keys %rssiH){
        my $str = sprintf("%-15s  ",$d);
        $str .= sprintf("%-15s  ",AttrVal($d,"alias","-"))if ($doAli);
        foreach my $i(@io){
          $str .= sprintf(" %12.1f"
                  #        ,($rssiH{$d}{$i}{min} ? $rssiH{$d}{$i}{min} : 0)
                           ,($rssiH{$d}{$i}{avg} ? $rssiH{$d}{$i}{avg} : 0)
                  #        ,($rssiH{$d}{$i}{max} ? $rssiH{$d}{$i}{max} : 0)
                           );
        }
        push @rssiList, $str;
      }
      $ret = "\n rssi average \n"
             .(join "\n   ",sort @rssiList);
    }
    elsif($type eq "full"){
      $ret = $cmd." done:"."\n    "."Device          ".($doAli?"Alias            ":"")."receive         from             last   avg      min_max    count"
                        ."\n    ".(join "\n    ",sort @rssiList)
                         ;
    }
  }
  #------------ checks ---------------
  elsif($cmd eq "regCheck")   {##check register--------------------------------
    my @entities = HMinfo_getEntities($opt."v",$filter);
    $ret = $cmd." done:" .HMinfo_regCheck(@entities);
    $ret = HMinfo_applTxt2Check($ret);
  }
  elsif($cmd eq "peerCheck")  {##check peers-----------------------------------
    my @entities = HMinfo_getEntities($opt,$filter);
    $ret = $cmd." done:" .HMinfo_peerCheck(@entities);
    $ret = HMinfo_applTxt2Check($ret);
  }
  elsif($cmd eq "configCheck"){##check peers and register----------------------
    if($modules{HMinfo}{helper}{initDone}){
      if ($hash->{CL}){
        if(scalar(keys %{$hash->{nb}}) > 1){
          my @entities = HMinfo_getEntities($opt,$filter);
          push @entities,@{$hash->{helper}{nbPend}} if (defined $hash->{helper}{nbPend});
          @entities = HMinfo_noDup(@entities);
          if(scalar(@entities) > 0){
            $hash->{helper}{nbPend} = \@entities;
            RemoveInternalTimer($name,"HMinfo_getCfgDefere");
            InternalTimer(gettimeofday()+10,"HMinfo_getCfgDefere", $name, 0);
          }
          $ret = "";
        }
        else{
          my @entities = HMinfo_getEntities($opt,$filter);
          push @entities,@{$hash->{helper}{nbPend}} if (defined $hash->{helper}{nbPend});
          @entities = HMinfo_noDup(@entities);
          $filter = '^('.join("|",@entities).')$';
          $defs{$name}{helper}{cfgChkResult} = "";
          HMinfo_startBlocking($name,"HMinfo_configCheck", "$opt,$filter");
          delete $hash->{helper}{nbPend};
          $ret = "";
        }
      }
      else{
        (undef,undef,undef,$ret) = split(";",HMinfo_configCheck (join(",",("$name;;",$opt,$filter))),4);
        $ret = HMinfo_bpPost("$name;;;$ret");
      }
    }
    else{
      $ret = "init not complete. configCheck won't be executed";
    }
  }
  elsif($cmd eq "configChkResult"){##check peers and register------------------
    return $defs{$name}{helper}{cfgChkResult} ? $defs{$name}{helper}{cfgChkResult} :"no results available";
  }
  elsif($cmd eq "templateChk"){##template: see if it applies ------------------
    if ($hash->{CL}){
      HMinfo_startBlocking($name,"HMinfo_templateChk_Get", join(",",($opt,$filter,@a)));
      $ret = "";
    }
    else{
      (undef,undef,undef,$ret) = split(";",HMinfo_templateChk_Get (join(",",("$name;;",$opt,$filter,@a))),4);
      $ret = HMinfo_bpPost("$name;;;$ret");
    }
  }
  elsif($cmd =~ m/^templateUs(g|gG)$/){##template: see if it applies ----------
    return HMinfo_templateUsg($opt,$filter,@a);
  }
  #------------ print tables ---------------
  elsif($cmd eq "peerXref")   {##print cross-references------------------------
    my $sort = "act";
    #sender,actor,receiver,virtual
    my $disp = "";
    if (defined $a[0]){
      foreach (split(",",$a[0])){
        $disp .= "1" if($_ =~ m/^sender$/);
        $disp .= "2" if($_ =~ m/^actor$/);
        $disp .= "3" if($_ =~ m/^receiver$/);
        $disp .= "4" if($_ =~ m/^virtual$/);
      }
    }
    $disp = "1234" if ($disp eq "");
    $disp .= "56";
    
    my %peerFriends;
    my @peerFhem;
#    my @peerUndef;
    my @fheml = ();
    foreach my $dName (HMinfo_getEntities($opt,$filter)){
      # search for irregular trigger
      my $peerIDs = join(",", CUL_HM_getPeers($dName,"IDs"));
      my $pType = substr($defs{$dName}{helper}{peerOpt},0,1);
      $pType = ($pType eq '4' ? '1_sender'
               :$pType eq '3' ? '2_actor'
               :$pType eq '7' ? '3_receive'
               :$pType eq 'p' ? '3_receive'
               :$pType eq 'v' ? '4_virtual'
               :                '5_undef'
               );
      foreach (grep /^......$/, HMinfo_noDup(map {CUL_HM_name2Id(substr($_,8))} 
                                              grep /^trigDst_/,
                                              keys %{$defs{$dName}{READINGS}})){
        $peerFriends{"6_trigger"}{$dName}{$_} = 1
            if(  ($peerIDs && $peerIDs !~ m/$_/)
               &&("CCU-FHEM" ne AttrVal(CUL_HM_id2Name($_),"model","")));
      }

      #--- check regular references
      next if(!$peerIDs);
      my $dId = unpack 'A6',CUL_HM_name2Id($dName);
      foreach (split",",$peerIDs){
        my $pn = CUL_HM_peerChName($_,$dId);
        $pn =~ s/_chn-01//;
        push @fheml,"$_$dName" if ($pn =~ m/^fhem..$/);

        $peerFriends{$pType}{$dName}{$pn} = 1;
      }
    }
    #--- calculate peerings to Central ---
    my %fChn;
    foreach (@fheml){
      my ($fhId,$fhCh,$p)= unpack 'A6A2A*',$_;
      my $fhemCh = "fhem_io_${fhId}_$fhCh";
      $fChn{$fhemCh} = ($fChn{$fhemCh}?$fChn{$fhemCh}.", ":"").$p;
    }
    push @peerFhem,map {"$_ => $fChn{$_}"} keys %fChn;
    
    $ret = $cmd." done:" ."\n x-ref list";
    foreach my $type(sort keys %peerFriends){
      my $typeId = substr($type,0,1);
      next if($disp !~ m/$typeId/);
      $ret .= "\n  ".substr($type,2,20);
      foreach my $Channel(sort keys %{$peerFriends{$type}}){
        $ret .= sprintf("\n       %-20s %s %s",$Channel
               ,($sort eq "act" ? " => " : " <= " )
               ,join (" ",sort keys %{$peerFriends{$type}{$Channel}}))
          ;
      }
    }
    
    
#                                         ."\n    ".(join "\n    ",sort @peerFhem)
#                         ;
#    $ret .=               "\n warning: sensor triggers but no config found"
#                                         ."\n    ".(join "\n    ",sort @peerUndef)
#            if(@peerUndef)
#                         ;
  }
  elsif($cmd eq "peerUsg")    {##print cross-references and usage--------------
    my @peerPairs;
    my @peerFhem;
    my @peerUndef;
    my @fheml = ();
    foreach my $dName (HMinfo_getEntities($opt,$filter)){
      my $tmpRegl = join("",CUL_HM_reglUsed($dName));
      next if($tmpRegl !~ m/RegL_04/);

      # search for irregular trigger
      my $peerIDs = join(",", CUL_HM_getPeers($dName,"IDs"));
      foreach (grep /^......$/, HMinfo_noDup(map {CUL_HM_name2Id(substr($_,8))} 
                                              grep /^trigDst_/,
                                              keys %{$defs{$dName}{READINGS}})){
        push @peerUndef,"$dName triggers $_"
            if(  ($peerIDs && $peerIDs !~ m/$_/)
               &&("CCU-FHEM" ne AttrVal(CUL_HM_id2Name($_),"model","")));
      }

      #--- check regular references
      next if(!$peerIDs);
      my $dId = unpack 'A6',CUL_HM_name2Id($dName);
      my @pl = ();
      my @peers = split(",",$peerIDs); #array of peers
      foreach (split",",$peerIDs){     #add peers that are implicitely added
        my $pDevN = CUL_HM_id2Name(substr($_,0,6));
        foreach (grep (/^channel_/, keys%{$defs{$pDevN}})){
          if(InternalVal($defs{$pDevN}{$_},"peerList","unknown") =~ m/$dName/){
            push @peers,$defs{$pDevN}{$_};
          }
        }
        if(InternalVal($pDevN,"peerList","unknown") =~ m/$dName/){
          push @peers,$pDevN;
        }
      }
      @peers = CUL_HM_noDup(@peers);
     
#      foreach (split",",$peerIDs){
      foreach (@peers){
        my $pn = CUL_HM_peerChName($_,$dId);
        $pn =~ s/_chn-01//;
        my $tmpl = "-";
        if(defined $defs{$pn}){
          if   ( defined $defs{$pn}{helper}{role}{vrt}){
            $tmpl = "virt";
          } 
          elsif(!defined $defs{$pn}{helper}{role}{chn}){
            next;
          }
          elsif( defined $defs{$pn}{helper}{tmpl}){
            $tmpl = join(",", map{$_.":".$defs{$pn}{helper}{tmpl}{$_}} grep /$dName/,keys %{$defs{$pn}{helper}{tmpl}});
            $tmpl =~ s/${dName}://g;
            $tmpl = "-" if($tmpl eq "");
          }
        }
        push @pl,$pn." \t:".$tmpl;
        push @fheml,"$_$dName" if ($pn =~ m/^fhem..$/);
      }
      push @peerPairs,$dName." \t=> $_" foreach(@pl);
    }
    @peerPairs = CUL_HM_noDup(@peerPairs);
    #--- calculate peerings to Central ---
    my %fChn;
    foreach (@fheml){
      my ($fhId,$fhCh,$p)= unpack 'A6A2A*',$_;
      my $fhemCh = "fhem_io_${fhId}_$fhCh";
      $fChn{$fhemCh} = ($fChn{$fhemCh}?$fChn{$fhemCh}.", ":"").$p;
    }
    push @peerFhem,map {"$_ => $fChn{$_}"} keys %fChn;
    $ret = $cmd." done:" ."\n x-ref list"."\n    ".(join "\n    ",sort @peerPairs)
                                         ."\n    ".(join "\n    ",sort @peerFhem)
                         ;
    $ret .=               "\n warning: sensor triggers but no config found"
                                         ."\n    ".(join "\n    ",sort @peerUndef)
            if(@peerUndef)
                         ;
  }
  elsif($cmd eq "templateList"){##template: list templates --------------------
    return HMinfo_templateList($a[0]);
  }
  elsif($cmd eq "register")   {##print register--------------------------------
    HMinfo_startBlocking($name,"HMinfo_register", join(",",($name,$opt,$filter)));
    $ret = "";
  }
  elsif($cmd eq "param")      {##print param ----------------------------------
    my @paramList;
    foreach my $dName (HMinfo_getEntities($opt,$filter)){
      my $id = $defs{$dName}{DEF};
      my ($found,$para) = HMinfo_getParam($id,@a);
      push @paramList,$para if($found || $optEmpty);
    }
    my $prtHdr = "entity              \t: ";
    $prtHdr .= sprintf("%-20s \t| ",$_)foreach (@a);
    $ret = $cmd." done:"
               ."\n param list"  ."\n    "
               .$prtHdr          ."\n    "
               .(join "\n    ",sort @paramList)
           ;
  }

  elsif($cmd eq "models")     {##print capability, models----------------------
    my $th = \%HMConfig::culHmModel;
    my @model;
    foreach (keys %{$th}){
      my $modelId = CUL_HM_getmIdFromModel($th->{$_}{alias});
      my $mode = $th->{$modelId}{rxt};
      $mode =~ s/\bc\b/config/;
      $mode =~ s/\bw\b/wakeup/;
      $mode =~ s/\bb\b/burst/;
      $mode =~ s/\b3\b/3Burst/;
      $mode =~ s/\bl\b/lazyConf/;
      $mode =~ s/\bf\b/burstCond/;
      $mode =~ s/:/,/g;
      $mode = "normal" if (!$mode);
      my $list = $th->{$modelId}{lst};
      $list =~ s/.://g;
      $list =~ s/p//;
      my $chan = "";
      foreach (split",",$th->{$modelId}{chn}){
        my ($n,$s,$e) = split(":",$_);
        $chan .= $s.(($s eq $e)?"":("-".$e))." ".$n.", ";
      }
      push @model,sprintf("%-16s %-24s %4s %-24s %-5s %-5s %s"
                          ,$th->{$modelId}{st}
                          ,$th->{$_}{name}
                          ,$_
                          ,$mode
                          ,$th->{$modelId}{cyc}
                          ,$list
                          ,$chan
                          );
    }
    @model = grep /$filter/,sort @model if($filter);
    $ret = $cmd.($filter?" filtered":"").":$filter\n  "
           .sprintf("%-16s %-24s %4s %-24s %-5s %-5s %s\n  "
                          ,"subType"
                          ,"name"
                          ,"ID"
                          ,"supportedMode"
                          ,"Info"
                          ,"List"
                          ,"channels"
                          )
            .join"\n  ", @model;
  }
#  elsif($cmd eq "overview")       { 
#    my @entities = HMinfo_getEntities($opt."d",$filter);
#    return HMI_overview(\@entities,\@a);
#  }                                

  elsif($cmd eq "showTimer"){
    my ($type) = (@a,"short");# ugly way to set "full" as default
    my %show;
    if($type eq "short"){
       %show =(   NAME        => 4
                 ,TIMESPEC    => 3
                 ,fn          => 1                 
                 ,FW_detailFn => 4
                 ,DeviceName  => 4
                 );
    }
    else{
       %show =(   TYPE        => 1
                 ,NAME        => 4
                 ,TIMESPEC    => 3
                 ,PERIODIC    => 2
                 ,MODIFIER    => 5
                 ,STATE       => 9
                 ,fn          => 1
                 ,finishFn    => 2
                 ,abortFn     => 3
                 ,FW_detailFn => 4
                 ,DeviceName  => 4
                 );
    }
    my $fltr = "(".join("|",keys %show).')' ;
    my @ak;
    my ($tfnm, $cv);
    my $timerarray =  \@intAtA;
    my $now = gettimeofday();
    foreach my $ats (@{$timerarray}){
      $tfnm = $ats->{FN};
      if (ref($tfnm) ne "") {
        $cv = svref_2object($tfnm);
        $tfnm = $cv->GV->NAME if ($cv);
      }
       if (!defined($ats->{TRIGGERTIME})) { #noansi: just for debugging
        Log3 $hash,2,'HMinfo '.$name.' showTimer undefined TRIGGERTIME:'
                     .(defined($ats->{atNr})?' atNr:'.$ats->{atNr}:'')
                     .' FN:'.$tfnm
                     .' ARG:'.$ats->{ARG};
 #       next;
      }
      push @ak,  substr(localtime($ats->{TRIGGERTIME}),0,19)
               .sprintf("%8d: %-30s\t :",int($ats->{TRIGGERTIME}-$now)
                                        ,$tfnm)
               .(ref($ats->{ARG}) eq 'HASH'
                     ? join("\t ",map{"$_ : ".$ats->{ARG}{$_}}
                                  map{$_=~m/^\d/?substr($_,1,99):$_}
                                  sort
                                  map{(my $foo = $_) =~ s/$fltr/$show{$1}$1/g; $foo;}
                                  grep /^$fltr/,
                                  keys %{$ats->{ARG}})
                      :"$ats->{ARG}")};
    $ret = join("\n", @ak);
  }
  elsif($cmd eq "showChilds"){
    my ($type) = @a;
    $type = "all" if(!$type);
    if ($type ne "all"){
      $ret = "BlockingCalls:\n".join("\nnext:----------\n",
              map {(my $foo = $_) =~ s/(Pid:|Fn:|Arg:|Timeout:|ConnectedVia:)/\n   $1/g; $foo;}
              grep /(CUL_HM|HMinfo)/,BlockingInfo(undef,undef));
    }
    else{
      $ret = "BlockingCalls:\n".join("\nnext:----------\n",
              map {(my $foo = $_) =~ s/(Pid:|Fn:|Arg:|Timeout:|ConnectedVia:)/\n   $1/g; $foo;}
              BlockingInfo(undef,undef));
    }
  }
  
  elsif($cmd eq "configInfo") {
    $ret = ""  ;
    foreach(sort keys %chkIds){
      my $sh = substr($chkIds{$_}{shtxt}."             ",0,15);
      $ret .= "\n$sh long: $chkIds{$_}{txt}  \n                $chkIds{$_}{long} "; 
    }  
  }
  elsif($cmd eq "help")       {
    $ret = HMInfo_help();
  }

  else{
    my @cmdLst =     
           ( "help:noArg"
            ,"configInfo:noArg"
            ,"configCheck"
            ,"configChkResult:noArg"
            ,"param"
            ,"peerCheck"
            ,"peerUsg"
            ,"peerXref:multiple"
                              .",sender"
                              .",actor"
                              .",receiver"
                              .",virtual"
            ,"protoEvents:all,short,long"
            ,"msgStat"
            ,"rssi rssiG:full,reduced"
            ,"models"
#            ,"overview"
            ,"regCheck"
            ,"register"
            ,"templateList:".join(",",("all",sort keys%HMConfig::culHmTpl))
            ,"templateChk"
            ,"templateUsg"
            ,"templateUsgG:sortTemplate,sortPeer,noTmpl,all"
            ,"showTimer:short,full"
            ,"showChilds:hm,all"
            );
            
    $ret = "Unknown argument $cmd, choose one of ".join (" ",sort @cmdLst);
  }
  return $ret;
}
sub HMinfo_SetFn($@) {#########################################################
  my ($hash,$name,$cmd,@a) = @_;
  my @in = @a;
  my ($opt,$optEmpty,$filter) = ("",1,"");
  my $ret;
  $doAli = 0;#set default

  if (@a && ($a[0] =~ m/^-/) && ($a[0] !~ m/^-f$/)){# options provided
    $opt = $a[0];
    $optEmpty = ($opt =~ m/e/)?1:0;
    shift @a; #remove
  }
  if (@a && $a[0] =~ m/^-f$/){# options provided
    shift @a; #remove
    $filter = shift @a;
  }

  $cmd = "?" if(!$cmd);# by default print options
  Log3 $hash,3,"HMinfo $name get:$cmd :".join(",",@a) if ($cmd ne "?");
  if   ($cmd =~ m/^clear[G]?/ )     {##actionImmediate: clear parameter--------
    my ($type) = @a;                               
    return "please enter what to clear" if (! $type);
    if ($type eq "msgStat" || $type eq "all" ){
      foreach (keys %{$modules{CUL_HM}{stat}{r}}){
        next if ($_ eq "dummy");
        delete $modules{CUL_HM}{stat}{$_};
        delete $modules{CUL_HM}{stat}{r}{$_};
        delete $modules{CUL_HM}{stat}{s}{$_};
      }
    }
    if ($type eq "msgErrors"){#clear message errors for all devices which has problems
      my @devL = split(",",InternalVal($hash->{NAME},"iW__protoNames"  ,""));
      push @devL,split(",",InternalVal($hash->{NAME},"iCRI__protocol"  ,""));
      push @devL,split(",",InternalVal($hash->{NAME},"iERR__protocol"  ,""));
    
      foreach my $dName (HMinfo_noDup(@devL)){
        CUL_HM_Set($defs{$dName},$dName,"clear","msgErrors");
      }
    }
    elsif ($type ne "msgStat"){
      return "unknown parameter - use msgEvents, msgErrors, msgStat, readings, register, rssi, attack or all"
            if ($type !~ m/^(msgEvents|msgErrors|readings|register|oldRegs|rssi|all|attack|trigger)$/);
      $opt .= "d" if ($type =~ m/(msgE|rssi|oldRegs)/);# readings apply to all, others device only
      my @entities = (HMinfo_getEntities($opt,$filter));
      
      foreach my $dName (@entities){
        CUL_HM_Set($defs{$dName},$dName,"clear",$type);
      }
      $ret = $cmd.$type." done:" 
	                   ."\n cleared"  
					   ."\n    ".(join "\n    ",sort @entities)
             if($filter);#  no return if no filter 
    }
	HMinfo_status($hash);
  }
  elsif($cmd eq "autoReadReg"){##actionImmediate: re-issue register Read-------
    my @entities;
    foreach my $dName (HMinfo_getEntities($opt."dv",$filter)){
      next if (!substr(AttrVal($dName,"autoReadReg","0"),0,1));
      CUL_HM_qAutoRead($dName,1);
      push @entities,$dName;
    }
    return $cmd." done:" ."\n triggered:"  ."\n    ".(join "\n    ",sort @entities)
                         ;
  }
  elsif($cmd eq "cmdRequestG"){##perform statusRequest for all devicesregister Read-------
    my $action = $a[0] ? $a[0]:"status";
    my $st = gettimeofday();
    $action = ($action eq "ping" ? "ping":"status"); #we have status or ping to search devices
    my %h;    
    if($action eq "ping"){
      foreach my $defN (devspec2array("TYPE=CUL_HM:FILTER=DEF=......:FILTER=subType!=virtual")){
        CUL_HM_Ping($defN);
      }
    }
    else{
      $h{$_} = $_  foreach(devspec2array("TYPE=CUL_HM:FILTER=DEF=......:FILTER=subType!=virtual")); # all non-virtual devices. CUL_HM will select statusRequest
      CUL_HM_qStateUpdatIfEnab($_,1)foreach(map{$h{$_}}keys %h);#issue status-request 
    }
    return;
  }

  elsif($cmd eq "templateSet"){##template: set of register --------------------
    return HMinfo_templateSet(@a);
  }
  elsif($cmd eq "templateDel"){##template: set of register --------------------
    return HMinfo_templateDel(@a);
  }
  elsif($cmd eq "templateDef"){##template: define one -------------------------
    return HMinfo_templateDef(@a);
  }
  elsif($cmd eq "cpRegs")     {##copy register             --------------------
    return HMinfo_cpRegs(@a);
  }
  elsif($cmd eq "update")     {##update hm counts -----------------------------
    $ret = HMinfo_status($hash);
  }
  elsif($cmd =~ m/tempList[G]?/)   {##handle thermostat templist from file ----
    my $action = $a[0]?$a[0]:"";
    HMinfo_listOfTempTemplates(); # refresh - maybe there are new entries in the files. 
    if    ($action eq "genPlot"){#generatelog and gplot file 
      $ret = HMinfo_tempListTmplGenLog($name,$a[1]);
    }
    elsif ($action eq "status") {
      $ret = HMinfo_tempListTmplView();
    }
    else{
      my $fn = HMinfo_tempListDefFn($a[1]);
      $ret = HMinfo_tempList($name,$filter,$action,$fn);
    }
  }
  elsif($cmd eq "templateExe")     {##template: see if it applies -------------
    return HMinfo_templateExe($opt,$filter,@a);
  }
  elsif($cmd eq "loadConfig")      {##action: loadConfig-----------------------
    my $fn = HMinfo_getConfigFile($name,"configFilename",$a[0]);
    $ret = HMinfo_loadConfig($hash,$filter,$fn); 
  }
  elsif($cmd eq "verifyConfig")    {##action: verifyConfig---------------------
    my $fn = HMinfo_getConfigFile($name,"configFilename",$a[0]);

    if ($hash->{CL}){
      HMinfo_startBlocking($name,"HMinfo_verifyConfig", "$fn");
      $ret = "";
    }
    else{
      $ret = HMinfo_verifyConfig("$name;0;none,$fn"); 
    }
  }
  elsif($cmd eq "purgeConfig")     {##action: purgeConfig----------------------
    my $id = ++$hash->{nb}{cnt};
    my $fn = HMinfo_getConfigFile($name,"configFilename",$a[0]);
    HMinfo_startBlocking($name,"HMinfo_purgeConfig", "$fn");
    my $bl = BlockingCall("HMinfo_purgeConfig", join(",",("$name;$id;none",$fn)), 
                          "HMinfo_bpPost", 30, 
                          "HMinfo_bpAbort", "$name:$id");
    $hash->{nb}{$id}{$_} = $bl->{$_} foreach (keys %{$bl});
    $ret = ""; 
  }
  elsif($cmd eq "saveConfig")      {##action: saveConfig-----------------------
    my $id = ++$hash->{nb}{cnt};
    my $fn = HMinfo_getConfigFile($name,"configFilename",$a[0]);
    my $bl = BlockingCall("HMinfo_saveConfig", join(",",("$name;$id;none",$fn,$opt,$filter)), 
                          "HMinfo_bpPost", 30, 
                          "HMinfo_bpAbort", "$name:$id");
    $hash->{nb}{$id}{$_} = $bl->{$_} foreach (keys %{$bl});
    $ret = $cmd." done:" ."\n saved";
  }
  elsif($cmd eq "archConfig")      {##action: archiveConfig--------------------
    # save config only if register are complete
    $ret = HMinfo_archConfig($hash,$name,$opt,($a[0]?$a[0]:""));
  }
  elsif($cmd eq "x-deviceReplace") {##action: deviceReplace--------------------
    # replace a device with a new one
    $ret = HMinfo_deviceReplace($name,$a[0],$a[1]);
  }
  elsif($cmd eq "simDev"){
    my ($simName,$hmId) = ("sim_00","D00F00");
    my $i = 0;
    for ($i = 0;$i<0xff;$i++){
      $hmId = sprintf("D00F%02X",$i);
      next if (defined $modules{CUL_HM}{defptr}{$hmId});
      $simName = sprintf("sim_%02X",$i);
      next if (defined $defs{$simName});
      last;
    }
    return "no definition possible - too many simulations?" if($i > 0xfe );

    return "model $a[0] cannot be identified" if(!defined $HMConfig::culHmModel2Id{$a[0]});
    my $model = $a[0];
#    CommandDelete(undef,$simName);
    CommandDefine(undef,"$simName CUL_HM $hmId");
    CUL_HM_assignIO($defs{$simName});
    my $id = $HMConfig::culHmModel2Id{$model};

    Log 4,"testdevice my $id, $model";

    CUL_HM_Parse($defs{ioPCB},"A00018400${hmId}00000010${id}4D592D434F464645453612060100"."::::");
    CUL_HM_Set($defs{$simName},$simName,"clear","msgEvents");
    CUL_HM_protState($defs{$simName},"Info_Cleared");
    my $cmds = "\n================= cmds for $model===\n";
    $attr{$simName}{room} = "simulate";
    $attr{$simName}{dummy} = 1;
    $ret = "defined model:$model id:$id name:$simName RFaddr:$hmId\n";
    $ret  .= CUL_HM_Get($defs{$simName},$simName,"regList");
    $cmds .= CUL_HM_Get($defs{$simName},$simName,"cmdList","short");
    
    foreach (grep (/^channel_/, keys%{$defs{$simName}})){
      next if(!$_);
      $attr{$_}{room} = "simulate";

      $ret  .= "################## $defs{$simName}->{$_}###\n"
              .CUL_HM_Get($defs{$defs{$simName}->{$_}},$defs{$simName}->{$_},"regList");
      $cmds .= "\n================= $defs{$simName}->{$_}===\n"
              .CUL_HM_Get($defs{$defs{$simName}->{$_}},$defs{$simName}->{$_},"cmdList","short");
    }
    $ret .= $cmds;
  }

  
  ### redirect set commands to get - thus the command also work in webCmd
  elsif($cmd ne '?' && HMinfo_GetFn($hash,$name,"?") =~ m/\b$cmd\b/){##--------
    unshift @a,"-f",$filter if ($filter);
    unshift @a,"-".$opt if ($opt);
    $ret = HMinfo_GetFn($hash,$name,$cmd,@a);
 }

  else{
    my $mdList = join(",",sort keys %HMConfig::culHmModel2Id);
 
    my @cmdLst =     
           ( "autoReadReg"
            ,"cmdRequestG:ping,status"
            ,"clear"    #:msgStat,msgEvents,all,rssi,register,trigger,readings"  
            ,"clearG:msgEvents,msgErrors,msgStat,readings,register,oldRegs,rssi,trigger,attack,all"
            ,"archConfig:-0,-a","saveConfig","verifyConfig","loadConfig","purgeConfig"
            ,"update:noArg"
            ,"cpRegs"
            ,"tempList"
            ,"x-deviceReplace"
            ,"tempListG:verify,status,save,restore,genPlot"
            ,"templateDef","templateSet","templateDel","templateExe"
            ,"simDev:$mdList"
            );
    $ret = "Unknown argument $cmd, choose one of ".join (" ",sort @cmdLst);
  }
  return $ret;
}

sub HMInfo_help(){ ############################################################
  return    " Unknown argument choose one of "
           ."\n ---checks---"
           ."\n get configCheck [-typeFilter-]                     # perform regCheck and regCheck"
           ."\n get regCheck [-typeFilter-]                        # find incomplete or inconsistant register readings"
           ."\n get peerCheck [-typeFilter-]                       # find incomplete or inconsistant peer lists"
           ."\n ---actions---"
           ."\n set saveConfig [-typeFilter-] [-file-]             # stores peers and register with saveConfig"
           ."\n set archConfig [-a] [-file-]                       # as saveConfig but only if data of entity is complete"
           ."\n set purgeConfig [-file-]                           # purge content of saved configfile "
           ."\n set loadConfig [-typeFilter-] -file-               # restores register and peer readings if missing"
           ."\n set verifyConfig [-typeFilter-] -file-             # compare curent date with configfile,report differences"
           ."\n set autoReadReg [-typeFilter-]                     # trigger update readings if attr autoReadReg is set"
           ."\n set cmdRequestG [ping|status]                      # trigger a status-request for ping) one channel per device"
           ."\n                                                    #                            status) all channel that support statusRequest"
           ."\n set tempList [-typeFilter-][save|restore|verify|status|genPlot][-filename-]# handle tempList of thermostat devices"
           ."\n set x-deviceReplace <old device> <new device>      # WARNING:replace a device with another"
           ."\n  ---infos---"
           ."\n set update                                         # update HMindfo counts"
           ."\n get register [-typeFilter-]                        # devicefilter parse devicename. Partial strings supported"
           ."\n get peerUsg  [-typeFilter-]                        # peer cross-reference with template information"
           ."\n get peerXref [-typeFilter-]                        # peer cross-reference"
           ."\n get models [-typeFilter-]                          # list of models incl native parameter"
           ."\n get protoEvents [-typeFilter-] [short|all|long]    # protocol status - names can be filtered"
           ."\n get msgStat                                        # view message statistic"
           ."\n get param [-typeFilter-] [-param1-] [-param2-] ... # displays params for all entities as table"
           ."\n get rssi [-typeFilter-]                            # displays receive level of the HM devices"
           ."\n          last: most recent"
           ."\n          avg:  average overall"
           ."\n          range: min to max value"
           ."\n          count: number of events in calculation"
           ."\n  ---clear status---"
           ."\n set clear[G] [-typeFilter-] [msgEvents|readings|msgStat|register|rssi]"
           ."\n                       # delete readings selective"
           ."\n          msgEvents    # delete all protocol-events , msg events"
           ."\n          msgErrors    # delete protoevents for all devices which had errors"
           ."\n          readings     # all readings"
           ."\n          register     # all register-readings"
           ."\n          oldRegs      # outdated register (cleanup) "
           ."\n          rssi         # all rssi data "
           ."\n          msgStat      # message statistics"
           ."\n          trigger      # trigger readings"
           ."\n          attack       # attack related readings"
           ."\n          all          # all of the above"
           ."\n ---help---"
           ."\n get help                            #"
           ."\n ***footnote***"
           ."\n [-nameFilter-]   : only matiching names are processed - partial names are possible"
           ."\n [-modelsFilter-] : any match in the output are searched. "
           ."\n"
           ."\n set cpRegs -src:peer- -dst:peer-"
           ."\n            copy register for a channel or behavior of channel/peer"
           ."\n set templateDef -templateName- -param1[:-param2-...] -description- -reg1-:-val1- [-reg2-:-val2-] ... "
           ."\n                 define a template"
           ."\n set templateSet -entity- -templateName- -peer:[long|short]- [-param1- ...] "
           ."\n                 write register according to a given template"
           ."\n set templateDel -entity- -templateName- -peer:[long|short]-  "
           ."\n                 remove a template set"
           ."\n set templateExe -templateName-"
           ."\n                 write all assigned templates to the file"
           ."\n set simDev      create a device for simualtion purpuse"
           ."\n"
           ."\n get templateUsg -templateName-[sortPeer|sortTemplate]"
           ."\n                 show template usage"
           ."\n get templateChk [-typeFilter-] -templateName- -peer:[long|short]- [-param1- ...] "
           ."\n                 compare whether register match the template values"
           ."\n get templateList [-templateName-]         # gives a list of templates or a description of the named template"
           ."\n                  list all currently defined templates or the structure of a given template"
           ."\n get configInfo  # information to getConfig status"
           ."\n get showTimer   # list all timer running in FHEM currently"
           ."\n get showChilds  [(hm|all)]# list all blocking calls"
           ."\n                 "
           ."\n ======= typeFilter options: supress class of devices  ===="
           ."\n set -name- -cmd- [-dcasev] [-f -filter-] [params]"
           ."\n      entities according to list will be processed"
           ."\n      d - device   :include devices"
           ."\n      c - channels :include channels"
           ."\n      i - ignore   :include devices marked as ignore"
           ."\n      v - virtual  :supress fhem virtual"
           ."\n      p - physical :supress physical"
           ."\n      a - aktor    :supress actor"
           ."\n      s - sensor   :supress sensor"
           ."\n      e - empty    :include results even if requested fields are empty"
           ."\n "
           ."\n     -f - filter   :regexp to filter entity names "
           ."\n "
           ;
}

sub HMinfo_verifyConfig($) {###################################################
  my ($param) = @_;
  my ($id,$fName) = split ",",$param;
  HMinfo_purgeConfig($param);
  open(aSave, "$fName") || return("$id;Can't open $fName: $!");
  my @elPeer = ();
  my @elReg = ();
  my @entryNF = ();
  my @elOk = ();
  my %nh;
  while(<aSave>){
    chomp;
    my $line = $_;
    $line =~ s/\r//g;
    next if (   $line !~ m/set .* (peerBulk|regBulk) .*/);
    $line =~ s/#.*//;
    my ($cmd1,$eN,$cmd,$param) = split(" ",$line,4);
    if (!$eN || !$defs{$eN}){
      push @entryNF,"$eN deleted";
      next;
    }
    $nh{$eN} = 1 if (!defined $nh{$eN});#
    if($cmd eq "peerBulk"){
      my $ePeer = AttrVal($eN,"peerIDs","");
      if ($param ne $ePeer){
        my @fPeers = grep !/00000000/,split(",",$param);#filepeers
        my @ePeers = grep !/00000000/,split(",",$ePeer);#entitypeers
        my %fp = map {$_=>1} @ePeers;
        my @onlyFile = grep { !$fp{$_} } @fPeers; 
        my %ep = map {$_=>1} @fPeers;
        my @onlyEnt  = grep { !$ep{$_} } @ePeers; 
        push @elPeer,"$eN peer deleted: $_" foreach(@onlyFile);
        push @elPeer,"$eN peer added  : $_" foreach(@onlyEnt);
        $nh{$eN} = 0 if(scalar@onlyFile || scalar @onlyEnt);
      }
    }
    elsif($cmd eq "regBulk"){
      next if($param !~ m/RegL_0[0-9][:\.]/);#allow . and : for the time to convert to . only
      $param =~ s/\.RegL/RegL/;
      my ($reg,$data) = split(" ",$param,2);
      my $eReg = ReadingsVal($eN,($defs{$eN}{helper}{expert}{raw}?"":".").$reg,"");
      my ($ensp,$dnsp) = ($eReg,$data);
      $ensp =~ s/ //g;
      $dnsp =~ s/ //g;
      if ($ensp ne $dnsp){

        my %r; # generate struct with changes addresses
        foreach my $rg(grep /..:../, split(" ",$eReg)){
          my ($a,$d) = split(":",$rg);
          $r{$a}{c} = $d;
        }
        foreach my $rg(grep !/00:00/,grep /..:../, split(" ",$data)){
          my ($a,$d) = split(":",$rg);
          next if (!$a || $a eq "00");
          if   (!defined $r{$a}){$r{$a}{f} = $d;$r{$a}{c} = "";}
          elsif($r{$a}{c} ne $d){$r{$a}{f} = $d;}
          else                  {delete $r{$a};}
        }
        $r{$_}{f} = "" foreach (grep {!defined $r{$_}{f}} grep !/00/,keys %r);
        my @aCh = map {hex($_)} keys %r;#list of changed addresses
        
        # search register valid for thie entity
        my $dN = CUL_HM_getDeviceName($eN);
        my $chn = CUL_HM_name2Id($eN);
        my (undef,$listNo,undef,$peer) = unpack('A6A1A1A*',$reg);
        $chn = (length($chn) == 8)?substr($chn,6,2):"";
        my $culHmRegDefine        =\%HMConfig::culHmRegDefine;
        my @regArr = grep{$culHmRegDefine->{$_}->{l} eq $listNo} 
                     CUL_HM_getRegN(AttrVal($dN,"subType","")
                                   ,AttrVal($dN,"model","")
                                   ,$chn);
        # now identify which register belongs to suspect address. 
        foreach my $rgN (@regArr){
          next if ($culHmRegDefine->{$rgN}{l} ne $listNo);
          my $a = $culHmRegDefine->{$rgN}{a};
          next if (!grep {$a == int($_)} @aCh);
          $a = sprintf("%02X",$a);
          push @elReg,"$eN "
                      .($peer?": peer:$peer ":"")
                      ."addr:$a changed from $r{$a}{f} to $r{$a}{c} - effected RegName:$rgN";
          $nh{$eN} = 0;
        }
        
      }
    }
  }
  close(aSave);
  @elReg = HMinfo_noDup(@elReg);
  foreach (sort keys(%nh)){
    push @elOk,"$_" if($nh{$_});
  }
  my $ret;
  $ret .= "\npeer mismatch:\n   "   .join("\n   ",sort(@elPeer))  if (scalar @elPeer);
  $ret .= "\nreg mismatch:\n   "    .join("\n   ",sort(@elReg ))  if (scalar @elReg);
  $ret .= "\nmissing devices:\n   " .join("\n   ",sort(@entryNF)) if (scalar @entryNF);
#  $ret .= "\nverified:\n   "        .join("\n   ",sort(@elOk))    if (scalar @elOk);
  $ret =~ s/\n/-ret-/g;
  return "$id;$ret";
}
sub HMinfo_loadConfig($$@) {###################################################
  my ($hash,$filter,$fName)=@_;
  $filter = "." if (!$filter);
  my $ret;
  open(rFile, "$fName") || return("Can't open $fName: $!");
  my @el = ();
  my @elincmpl = ();
  my @entryNF = ();
  my %changes;
  my @rUpdate;
  my @tmplList = (); #collect template definitions
  $modules{HMinfo}{helper}{initDone} = 0; #supress configCheck while loading
  my ($cntTStart,$cntDef,$cntSet,$cntEWT,$cntPBulk,$cntRBulk) = (0,0,0,0,0,0);
  while(<rFile>){
    chomp;
    my $line = $_;
    $line =~ s/\r//g;
    next if (   $line !~ m/set .* (peerBulk|regBulk) .*/
             && $line !~ m/(setreading|template.e.) .*/);
    my ($command,$timeStamp) = split("#",$line,2);
    $timeStamp = "1900-01-01 00:00:01" if (!$timeStamp || $timeStamp !~ m /^20..-..-.. /);
    my ($cmd1,$eN,$cmd,$param) = split(" ",$command,4);
    next if ($eN !~ m/$filter/);
    if   ($cmd1 !~ m /^template(Def|Set)$/ && (!$eN || !$defs{$eN})){
      push @entryNF,$eN;
      next;
    }
    if   ($cmd1 eq "setreading"){
      if (!$defs{$eN}{READINGS}{$cmd}){
        $changes{$eN}{$cmd}{d}=$param ;
        $changes{$eN}{$cmd}{t}=$timeStamp ;
      }
      $defs{$eN}{READINGS}{$cmd}{VAL} = $param;
      $defs{$eN}{READINGS}{$cmd}{TIME} = "from archivexx";
    }
    elsif($cmd1 eq "templateDef"){
      
      if ($eN eq "templateStart"){#if new block we remove all old templates
        @tmplList = ();
        $cntTStart++;
      }
      else {
        foreach my $read (keys %{$HMConfig::culHmUpdate{regValUpdt}}){# update wrong reg namings and options
          ($line) = map{(my $foo = $_) =~ s/$read/$HMConfig::culHmUpdate{regValUpdt}{$read}/g; $foo;}($line);
        }
        push @tmplList,$line;
      }
    }
    elsif($cmd1 eq "templateSet"){
      my (undef,$eNt,$tpl,$param) = split("=>",$line);
      if (defined($defs{$eNt})){
        if($tpl eq "start"){ # no template defined, or deleted - remove it.
          delete $defs{$eNt}{helper}{tmpl};
        }
        else{
          $defs{$eNt}{helper}{tmpl}{$tpl} = $param;
        }
      }
    }
    elsif($cmd  eq "peerBulk"){
      next if(!$param);
      $param =~ s/ //g;
      if ($param !~ m/00000000/){
        push @elincmpl,"$eN peerList";
        next;
      }
      if (   $timeStamp 
          && $timeStamp gt ReadingsTimestamp($eN,".peerListRDate","1900-01-01 00:00:01")){
        $cntPBulk++;
        CUL_HM_ID2PeerList($eN,$_,1) foreach (grep /[0-9A-F]{8}/,split(",",$param));
        push @el,"$eN peerIDs";
        $defs{$eN}{READINGS}{".peerListRDate"}{VAL} = $defs{$eN}{READINGS}{".peerListRDate"}{TIME} = $timeStamp;
      }
    }
    elsif($cmd  eq "regBulk"){
      next if($param !~ m/RegL_0[0-9][:\.]/);#allow . and : for the time to convert to . only
      $param =~ s/\.RegL/RegL/;
      $param = ".".$param if (!$defs{$eN}{helper}{expert}{raw});
      my ($reg,$data) = split(" ",$param,2);
      my @rla = CUL_HM_reglUsed($eN);
      next if (!$rla[0]);
      my $rl = join",",@rla;
      $reg =~ s/(RegL_0.):/$1\./;# conversion - : not allowed anymore. Update old versions
      $reg =~ s/_chn-00//; # special: 
      my $r2 = $reg;
      $r2 =~ s/^\.//;
      next if ($rl !~ m/$r2/);
      if ($data !~ m/00:00/){
        push @elincmpl,"$eN reg list:$reg";
        next;
      }
      my $ts = ReadingsTimestamp($eN,$reg,"1900-01-01 00:00:01");
      $ts = "1900-01-01 00:00:00" if ($ts !~ m /^20..-..-.. /);
      if (  !$defs{$eN}{READINGS}{$reg} 
          || $defs{$eN}{READINGS}{$reg}{VAL} !~ m/00:00/
          || (   (  $timeStamp gt $ts
                  ||(   $changes{$eN}
                     && $changes{$eN}{$reg}
                     && $timeStamp gt $changes{$eN}{$reg}{t})
              ))){
        $data =~ s/  //g;
        $changes{$eN}{$reg}{d}=$data;
        $changes{$eN}{$reg}{t}=$timeStamp;
      }
    }
  }
  
  close(rFile);
  foreach ( @tmplList){
    my @tmplCmd = split("=>",$_);
    next if (!defined $tmplCmd[4]);
    delete $HMConfig::culHmTpl{$tmplCmd[1]};
    my $r = HMinfo_templateDef($tmplCmd[1],$tmplCmd[2],$tmplCmd[3],split(" ",$tmplCmd[4]));
    $cntDef++;
  }
  $tmplDefChange = 0;# all changes are obsolete
  $tmplUsgChange = 0;# all changes are obsolete
  foreach my $eN (keys %changes){
    foreach my $reg (keys %{$changes{$eN}}){
      $defs{$eN}{READINGS}{$reg}{VAL}  = $changes{$eN}{$reg}{d};
      $defs{$eN}{READINGS}{$reg}{TIME} = $changes{$eN}{$reg}{t};
      my ($list,$pN) = $reg =~ m/RegL_(..)\.(.*)/?($1,$2):("","");
      $cntRBulk++;
      next if (!$list);
      my $pId = CUL_HM_name2Id($pN);# allow devices also as peer. Regfile is korrekt
      # my $pId = CUL_HM_peerChId($pN,substr($defs{$eN}{DEF},0,6));#old - removed
      push @el,"$eN reg list:$reg";    
    }
    CUL_HM_refreshRegs($eN);
  }
  $ret .= "\nadded data:\n     "          .join("\n     ",@el)       if (scalar@el);
  $ret .= "\nfile data incomplete:\n     ".join("\n     ",@elincmpl) if (scalar@elincmpl);
  $ret .= "\nentries not defind:\n     "  .join("\n     ",@entryNF)  if (scalar@entryNF);
  foreach my $tmpN(devspec2array("TYPE=CUL_HM")){
    $defs{$tmpN}{helper}{tmplChg} = 0 if(!$defs{$tmpN}{helper}{role}{vrt});
    CUL_HM_setTmplDisp($defs{$tmpN});#set readings if desired    
    if (defined $defs{$tmpN}{helper}{tmpl}){
      my $TmpCnt = scalar(keys %{$defs{$tmpN}{helper}{tmpl}}) ;
      if ($TmpCnt){
        $cntSet += $TmpCnt;
        $cntEWT++; # entity with template
      }
    }
  }
  Log3 $hash,5,"HMinfo load config file:$fName"
               ."\n     templateReDefinition:$cntTStart"
               ."\n     templateDef:$cntDef"
               ."\n     templateSet:$cntSet"
               ."\n     Entity with template:$cntEWT"
               ."\n     peerListUpdate:$cntPBulk"
               ."\n     regListUpdate:$cntRBulk"
               ;
  $modules{HMinfo}{helper}{initDone} = 1; #enable configCheck again
  HMinfo_GetFn($hash,$hash->{NAME},"configCheck");
  return $ret;
}
sub HMinfo_purgeConfig($) {####################################################
  my ($param) = @_;
  my ($id,$fName) = split ",",$param;
  $fName = "regSave.cfg" if (!$fName);

  open(aSave, "$fName") || return("$id;Can't open $fName: $!");
  my %purgeH;
  while(<aSave>){
    chomp;
    my $line = $_;
    $line =~ s/\r//g;
    if($line =~ m/entity:/){#remove an old entry. Last entry is the final.
      my $name = $line;
      $name =~ s/.*entity://;
      $name =~ s/ .*//;
      delete  $purgeH{$name};
    }
    next if (   $line !~ m/set (.*) (peerBulk|regBulk) (.*)/
             && $line !~ m/(setreading) .*/);
    my ($command,$timeStamp) = split("#",$line,2);
    my ($cmd,$eN,$typ,$p1,$p2) = split(" ",$command,5);
    if ($cmd eq "set" && $typ eq "regBulk"){
      $p1 =~ s/\.RegL_/RegL_/;
      $p1 =~ s/(RegL_0.):/$1\./;#replace old : with .
      $typ .= " $p1";
      $p1 = $p2;
    }
    elsif ($cmd eq "set" && $typ eq "peerBulk"){
      delete $purgeH{$eN}{$cmd}{regBulk};# regBulk needs to be rewritten
    }
    $purgeH{$eN}{$cmd}{$typ} = $p1.($timeStamp?"#$timeStamp":"");
  }
  close(aSave);
  open(aSave, ">$fName") || return("$id;Can't open $fName: $!");
  print aSave "\n\n#============data purged: ".TimeNow();
  foreach my $eN(sort keys %purgeH){
    next if (!defined $defs{$eN}); # remove deleted devices
    print aSave "\n\n#-------------- entity:".$eN." ------------";
    foreach my $cmd (sort keys %{$purgeH{$eN}}){
      my @peers = ();
      foreach my $typ (sort keys %{$purgeH{$eN}{$cmd}}){

        if ($typ eq "peerBulk"){# need peers to identify valid register
          @peers =  map {CUL_HM_id2Name($_)}
                    grep !/(00000000|peerBulk)/,
                    split",",$purgeH{$eN}{$cmd}{$typ};
        }
        elsif($typ =~ m/^regBulk/){#
          if ($typ !~ m/regBulk RegL_..\.(self..)?$/){# only if peer is mentioned
            my $found = 0;
            foreach my $p (@peers){
              if ($typ =~ m/regBulk RegL_..\.$p/){
                $found = 1;
                last;
              }
            }
            next if (!$found);
          }
        }
        print aSave "\n$cmd $eN $typ ".$purgeH{$eN}{$cmd}{$typ};
      }
    }
  }
  print aSave "\n\n";
  print aSave "\n======= finished ===\n";
  close(aSave);
  
  HMinfo_templateWriteDef($fName);
  foreach my $eNt(devspec2array("TYPE=CUL_HM")){
    $defs{$eNt}{helper}{tmplChg} = 1 if(!$defs{$eNt}{helper}{role}{vrt});
  }
  HMinfo_templateWriteUsg($fName);
  
  return "$id;";
}
sub HMinfo_saveConfig($) {#####################################################
  my ($param) = @_;
  my ($id,$fN,$opt,$filter,$strict) = split ",",$param;
  $strict = "" if (!defined $strict);
  foreach my $dName (HMinfo_getEntities($opt."dv",$filter)){
    CUL_HM_Get($defs{$dName},$dName,"saveConfig",$fN,$strict);
  }
  HMinfo_templateWrite($fN); 
  HMinfo_purgeConfig($param) if (-e $fN && 1000000 < -s $fN);# auto purge if file to big
  return $id;
}

sub HMinfo_archConfig($$$$) {##################################################
  # save config only if register are complete
  my ($hash,$name,$opt,$fN) = @_;
  my $fn = HMinfo_getConfigFile($name,"configFilename",$fN);
  my $id = ++$hash->{nb}{cnt};
  my $bl = BlockingCall("HMinfo_archConfigExec", join(",",("$name;$id;none"
                                                       ,$fn
                                                       ,$opt)), 
                        "HMinfo_archConfigPost", 30, 
                        "HMinfo_bpAbort", "$name:$id");
  $hash->{nb}{$id}{$_} = $bl->{$_} foreach (keys %{$bl});
  delete $modules{CUL_HM}{helper}{confUpdt}{$_} foreach (keys %{$modules{CUL_HM}{helper}{confUpdt}});
  return ;
}
sub HMinfo_archConfigExec($)  {################################################
  # save config only if register are complete
  my ($id,$fN,$opt) = split ",",shift;
  my @eN;
  if ($opt eq "-a"){@eN = HMinfo_getEntities("d","");}
  else             {@eN = keys %{$modules{CUL_HM}{helper}{confUpdt}}}
  my @names;
  push @names,(CUL_HM_getAssChnNames($_),$_) foreach(@eN);
  delete $modules{CUL_HM}{helper}{confUpdt}{$_} foreach (keys %{$modules{CUL_HM}{helper}{confUpdt}});
  my @archs;
  @eN = ();
  foreach(HMinfo_noDup(@names)){
    next if (!defined $_ || !defined $defs{$_} || !defined $defs{$_}{DEF});
    if (CUL_HM_getPeers($_,"Config") ==2 ||HMinfo_regCheck($_)){
      push @eN,$_;
    }
    else{
      push @archs,$_;
    }
  }
  HMinfo_saveConfig(join(",",( $id
                              ,$fN
                              ,"c"
                              ,"\^(".join("|",@archs).")\$")
                              ,"strict"));
  return "$id,".(@eN ? join(",",@eN) : "");
}
sub HMinfo_archConfigPost($)  {################################################
  my @arr = split(",",shift);
  my ($name,$id,$cl) = split(";",$arr[0]);
  shift @arr;
  $modules{CUL_HM}{helper}{confUpdt}{$_} = 1 foreach (@arr);
  delete $defs{$name}{nb}{$id};
  return ;
}

sub HMinfo_getConfigFile($$$) {################################################
  my ($name,$configFile,$fnIn) = @_;#HmInfoName, ConfigFiletype
  my %defaultFN = ( configFilename => "regSave.cfg"
                   ,configTempFile => "tempList.cfg"
                  );
  my $fn = $fnIn ? $fnIn
                 : AttrVal($name,$configFile,$defaultFN{$configFile});
  my @fns;# my file names - coud be more
  foreach my $fnt (split('[;,]',$fn)){
    $fnt = AttrVal($name,"configDir",".") ."\/".$fnt  if ($fnt !~ m/\//); 
    $fnt = AttrVal("global","modpath",".")."\/".$fnt  if ($fnt !~ m/^\//);
    push @fns,$fnt;
  }
  $_ =~ s/\.\/\.\//\.\// foreach(@fns);
  return join(";",@fns);
}

sub HMinfo_deviceReplace($$$){
  my ($hmName,$oldDev,$newDev) = @_;
  my $logH = $defs{$hmName};
  
  my $preReply = $defs{$hmName}{helper}{devRepl}?$defs{$hmName}{helper}{devRepl}:"empty";
  $defs{$hmName}{helper}{devRepl} = "empty";# remove task. 
  
  return "only valid for CUL_HM devices" if(  !$defs{$oldDev}{helper}{role}{dev} 
                                            ||!$defs{$newDev}{helper}{role}{dev} );
  return "use 2 different devices" if ($oldDev eq $newDev);
  
  my $execMode     = 0;# replace will be 2 stage: execMode 0 will not execute any action
  my $prepComplete = 0; # if preparation is aboard (prepComplete =0) the attempt will be ignored
  my $ret = "deviceRepleace - actions";
  if ( $preReply eq $oldDev."-".$newDev){
    $execMode = 1;
    $ret .= "\n        ==>EXECUTING: set $hmName x-deviceReplace $oldDev $newDev";
  }
  else{
    $ret .= "\n       --- CAUTION: this command will reprogramm fhem AND the devices incl peers";
    $ret .= "\n           $oldDev will be replaced by $newDev  ";
    $ret .= "\n           $oldDev can be removed after execution.";
    $ret .= "\n           Peers of the device will also be reprogrammed ";
    $ret .= "\n           command execution may be pending in cmdQueue depending on the device types ";
    $ret .= "\n           thoroughly check the protocoll events";
    $ret .= "\n           NOTE: The command is not revertable!";
    $ret .= "\n                 The command can only be executed once!";
    $ret .= "\n        ==>TO EXECUTE THE COMMAND ISSUE AGAIN: set $hmName x-deviceReplace $oldDev $newDev";
    $ret .= "\n";
  }
  
  #create hash to map old and new device
  my %rnHash;
  $rnHash{old}{dev}=$oldDev;
  $rnHash{new}{dev}=$newDev;
  
  my $oldID = $defs{$oldDev}{DEF}; # device ID old
  my $newID = $defs{$newDev}{DEF}; # device ID new
  foreach my $i(grep /channel_../,keys %{$defs{$oldDev}}){
    # each channel of old device needs a pendant in new
    return "channels incompatible for $oldDev: $i" if (!$defs{$oldDev}{$i} || ! defined $defs{$defs{$oldDev}{$i}});
    $rnHash{old}{$i}=$defs{$oldDev}{$i};

    if ($defs{$newDev}{$i} && defined $defs{$defs{$newDev}{$i}}){
      $rnHash{new}{$i}=$defs{$newDev}{$i};
      return "new channel $i:$rnHash{new}{$i} already has peers: $attr{$rnHash{new}{$i}}{peerIDs}" 
                                                if(defined $defs{$rnHash{new}{$i}}{peerList});
    }
    else{
      return "channel list incompatible for $newDev: $i";
    }
  }
  # each old channel has a pendant in new channel
  # lets begin
  #1  --- foreach entity  => rename old>"old_".<name> and new><name>
  #2  --- foreach channel => copy peers (peerBulk)
  #3  --- foreach channel => copy registerlist (regBulk)
  #4  --- foreach channel => copy templates 
  #5  --- foreach peer (search)
  #5a                           => add new peering
  #5b                           => apply reglist for new peer
  #5c                           => remove old peering
  #5d                           => update peer templates
  
  
  my @rename = ();# logging only
  {#1  --- foreach entity  => rename old=>"old_".<name> and new=><name>
    push @rename,"1) rename";
    foreach my $i(sort keys %{$rnHash{old}}){
      my $old = $rnHash{old}{$i};
      if ($execMode){
        AnalyzeCommand("","rename $old old_$old");
        AnalyzeCommand("","rename $rnHash{new}{$i} $old");
      }
      push @rename,"1)- $oldDev - $i: rename $old old_$old";
      push @rename,"1)- $newDev - $i: $rnHash{new}{$i} $old";
    }
    if ($execMode){
      foreach my $name(keys %{$rnHash{old}}){# correct hash internal for further processing
        $rnHash{new}{$name} = $rnHash{old}{$name};
        $rnHash{old}{$name} = "old_".$rnHash{old}{$name};
      }
    }
  }
  {#2  --- foreach channel => copy peers (peerBulk) from old to new
    push @rename,"2) copy peers from old to new ";
    foreach my $ch(sort keys %{$rnHash{old}}){
      my ($nameO,$nameN) = ($rnHash{old}{$ch},$rnHash{new}{$ch});
      next if(!defined $attr{$nameO}{peerIDs});
      my $peerList = join(",",grep !/^$oldID/, CUL_HM_getPeers($nameO,"IDs"));
      if ($execMode){
        CUL_HM_Set($defs{$nameN},$nameN,"peerBulk",$peerList,"set") if($peerList);
      }
      push @rename,"2)-      $ch: set $nameN peerBulk $peerList" if($peerList);
    }
  }
  {#3  --- foreach channel => copy registerlist (regBulk)
    push @rename,"3) copy registerlist from old to new";
    foreach my $ch(sort keys %{$rnHash{old}}){
      my ($nameO,$nameN) = ($rnHash{old}{$ch},$rnHash{new}{$ch});
      foreach my $regL(sort  grep /RegL_..\./,keys %{$defs{$nameO}{READINGS}}){
        my $regLp = $regL; 
        $regLp =~ s/^\.//;#remove leading '.' 
        if ($execMode){
          CUL_HM_Set($defs{$nameN},$nameN,"regBulk",$regLp,$defs{$nameO}{READINGS}{$regL}{VAL});
        }
        push @rename,"3)-      $ch: set $nameN regBulk $regLp ...";
      }
    }
  }
  {#4  --- foreach channel => copy templates 
    push @rename,"4) copy templates from old to new";
    if (eval "defined(&HMinfo_templateDel)"){# check templates
      foreach my $ch(sort keys %{$rnHash{old}}){
        my ($nameO,$nameN) = ($rnHash{old}{$ch},$rnHash{new}{$ch});
        if($defs{$nameO}{helper}{tmpl}){
          foreach(sort keys %{$defs{$nameO}{helper}{tmpl}}){
            my ($pSet,$tmplID) = split(">",$_);
            my @p = split(" ",$defs{$nameO}{helper}{tmpl}{$_});
            if ($execMode){
              HMinfo_templateSet($nameN,$tmplID,$pSet,@p);
            }
            push @rename,"4)-      $ch: templateSet $nameN,$tmplID,$pSet ".join(",",@p);
          }
        }
      }
    }
  }
  {#5  --- foreach peer (search) - remove peers old peer and set new
    push @rename,"5) for peer devices: remove ols peers";
    foreach my $ch(sort keys %{$rnHash{old}}){
      my ($nameO,$nameN) = ($rnHash{old}{$ch},$rnHash{new}{$ch});
      next if (!$attr{$nameO}{peerIDs});
      foreach my $pId(grep !/^$oldID/, CUL_HM_getPeers($nameO,"IDs")){
        my ($oChId,$nChId) = (substr($defs{$nameO}{DEF}."01",0,8)
                             ,substr($defs{$nameN}{DEF}."01",0,8));# obey that device may be channel 01
        my $peerName = CUL_HM_id2Name($pId);

        { #5a) add new peering
          if ($execMode){
            CUL_HM_Set($defs{$peerName},$peerName,"peerBulk",$nChId,"set");  #set new in peer
          }
          push @rename,"5)-5a)-  $ch: set $peerName peerBulk $nChId set";
        }
        { #5b) apply reglist for new peer
          foreach my $regL( grep /RegL_..\.$nameO/,keys %{$defs{$peerName}{READINGS}}){
            my $regLp = $regL; 
            $regLp =~ s/^\.//;#remove leading '.' 
            if ($execMode){
              CUL_HM_Set($defs{$peerName},$peerName,"regBulk",$regLp,$defs{$peerName}{READINGS}{$regL}{VAL});
            }
            push @rename,"5)-5b)-  $ch: set $peerName regBulk $regLp ...";
          }
        }
        { #5c) remove old peering
          if ($execMode){
            CUL_HM_Set($defs{$peerName},$peerName,"peerBulk",$oChId,"unset");#remove old from peer          
          }
          push @rename,"5)-5c)-  $ch: set $peerName peerBulk $oChId unset";
        }
        { #5d) update peer templates
          if (eval "defined(&HMinfo_templateDel)"){# check templates
            if($defs{$peerName}{helper}{tmpl}){
              foreach(keys %{$defs{$peerName}{helper}{tmpl}}){
                my ($pSet,$tmplID) = split(">",$_);
                $pSet =~ s/$nameO/$nameN/;
                my @p = split(" ",$defs{$peerName}{helper}{tmpl}{$_});
                if ($execMode){
                  HMinfo_templateSet($peerName,$tmplID,$pSet,@p);
                }
                push @rename,"5)-5d)-  $ch: templateSet $peerName,$tmplID,$pSet ".join(",",@p);
              }
            }
          }
        }
      }
    }
  }
  push @rename,"5)-5a) add new peering";
  push @rename,"5)-5b) apply reglist for new peer";
  push @rename,"5)-5c) remove old peering";
  push @rename,"5)-5d) update peer templates";
  foreach my $prt(sort @rename){# logging
    $prt =~ s/.\)\-/   /;
    $prt =~ s/   ..\)\-/       /;
    if ($execMode){ Log3 ($logH,3,"Rename: $prt");}
    else          { $ret .= "\n    $prt";         }      
  }
  if (!$execMode){# we passed preparation mode. Remember to execute it next time
    $defs{$hmName}{helper}{devRepl} = $oldDev."-".$newDev;
  }

  return $ret;
}

sub HMinfo_configCheck ($){ ###################################################
  my ($param) = shift;
  my ($id,$opt,$filter) = split ",",$param;
  foreach($id,$opt,$filter){ 
    $_ = "" if(!defined $_);
  }
  my @entities = HMinfo_getEntities($opt,$filter);
  my $ret = "configCheck done:";
  $ret .="\n\n idCl00\n".(join ",",@entities)  if(@entities);
  my @checkFct = (
                   "HMinfo_regCheck"
                  ,"HMinfo_peerCheck"
                  ,"HMinfo_burstCheck"
                  ,"HMinfo_paramCheck"
  );
  my %configRes;
  no strict "refs";
    $ret .=  &{$_}(@entities)foreach (@checkFct);
  use strict "refs";

  my @td = (devspec2array("model=HM-CC-RT-DN.*:FILTER=chanNo=04"),
            devspec2array("model=HM.*-TC.*:FILTER=chanNo=02"));
  my @tlr;
  foreach my $e (@td){
    next if(!grep /$e/,@entities );
    my $tr = CUL_HM_tempListTmpl($e,"verify",AttrVal($e,"tempListTmpl"
                                                       ,HMinfo_tempListDefFn().":$e"));
                                                       
    next if ($tr eq "unused");
    push @tlr,"$e: $tr" if($tr);
    $configRes{$e}{templist} = $tr if($tr);
  }
  $ret .="\n\n idTp00\n    ".(join "\n    ",sort @tlr)  if(@tlr);

  @tlr = ();
  foreach my $dName (HMinfo_getEntities($opt."v",$filter)){
    next if (!defined $defs{$dName}{helper}{tmpl});
    foreach (keys %{$defs{$dName}{helper}{tmpl}}){
      my ($p,$t)=split(">",$_);
      $p = 0 if ($p eq "none");
      my $tck = HMinfo_templateChk($dName,$t,$p,split(" ",$defs{$dName}{helper}{tmpl}{$_}));
      if ($tck){
        push @tlr,"$_" foreach(split("\n",$tck));
        $configRes{$dName}{template} = $tck;
      }
    }
  }
  $ret .="\n\n idTp01\n    ".(join "\n    ",sort @tlr)  if(@tlr);
  $ret .="\n";

  $ret =~ s/\n/-ret-/g; # replace return with a placeholder - we cannot transfere direct

  return "$id;$ret";
}
sub HMinfo_register ($){ ######################################################
  my ($param) = shift;
  my ($id,$name,$opt,$filter) = split ",",$param;
  my $hash = $defs{$name};
  my $RegReply = "";
  my @noReg;
  foreach my $dName (HMinfo_getEntities($opt."v",$filter)){
    my $regs = CUL_HM_Get(CUL_HM_name2Hash($dName),$dName,"reg","all");
    if ($regs !~ m/[0-6]:/){
        push @noReg,$dName;
        next;
    }
    my ($peerOld,$ptOld,$ptLine,$peerLine) = ("","",pack('A23',""),pack('A23',""));
    foreach my $reg (split("\n",$regs)){
      my ($peer,$h1) = split ("\t",$reg);
      $peer =~s/ //g;
      if ($peer !~ m/3:/){
        $RegReply .= $reg."\n";
        next;
      }
      next if (!$h1);
      $peer =~s/3://;
      my ($regN,$h2) = split (":",$h1);
      my ($pt,$rN) = unpack 'A2A*',$regN;
      if (!defined($hash->{helper}{r}{$rN})){
        $hash->{helper}{r}{$rN}{v} = "";
        $hash->{helper}{r}{$rN}{u} = pack('A5',"");
      }
      my ($val,$unit) = split (" ",$h2);
      $hash->{helper}{r}{$rN}{v} .= pack('A16',$val);
      $hash->{helper}{r}{$rN}{u} =  pack('A5',"[".$unit."]") if ($unit);
      if ($pt ne $ptOld){
        $ptLine .= pack('A16',$pt);
        $ptOld = $pt;
      }
      if ($peer ne $peerOld){
        $peerLine .= pack('A32',$peer);
        $peerOld = $peer;
      }
    }
    $RegReply .= $peerLine."\n".$ptLine."\n";
    foreach my $rN (sort keys %{$hash->{helper}{r}}){
      $hash->{helper}{r}{$rN} =~ s/(     o..)/$1                /g
            if($rN =~ m/^MultiExec /); #shift thhis reading since it does not appear for short
      $RegReply .=  pack ('A18',$rN)
                   .$hash->{helper}{r}{$rN}{u}
                   .$hash->{helper}{r}{$rN}{v}
                   ."\n";
    }
    delete $hash->{helper}{r};
  }
  my $ret = "No regs found for:".join(",",sort @noReg)."\n\n".$RegReply;
  $ret =~ s/\n/-ret-/g; # replace return with a placeholder - we cannot transfere direct
  return "$id;$ret";
}

sub HMinfo_bpPost($) {#bp finished ############################################
  my ($rep) = @_;
  my ($name,$id,$cl,$ret) = split(";",$rep,4);
  Log3 $defs{$name},5,"HMinfo $name finish blocking";

  my @entityChk;
  my ($test,$testId,$ent,$issue) = ("","","","");
  return if(!$ret);# nothing to post
  
  foreach my $eLine (split("-ret-",$ret)){
    next if($eLine eq "");
    if($eLine =~m/^ (id....)$/){
      $testId = $1; 
      $test = $chkIds{$testId}{txt};
      next;
    }
    if($test eq "clear"){
      @entityChk = split(",",$eLine);
      foreach(@entityChk){
        delete $defs{$_}{helper}{cfgChk};# pre-clear all entries  
      }
    }
    if($eLine =~m/^\s*(.*?):\s*(.*)$/){
      ($ent,$issue) = ($1,$2);
      next if (!defined $defs{$ent});
      $issue =~ s/\+newline\+/\n/g;
      if(defined $defs{$ent}{helper}{cfgChk}{$testId}){
        $defs{$ent}{helper}{cfgChk}{$testId} .= "\n".($issue ? $issue : "fail");
      }
      else{
        $defs{$ent}{helper}{cfgChk}{$testId} = ($issue ? $issue : "fail");
      }
      
    }  
  }

  foreach my $e(@entityChk){
    my $state;
    my $chn = InternalVal($e,"chanNo","00");
    if(0 < scalar(grep/(00|$chn)/,split(",",$defs{CUL_HM_getDeviceName($e)}{helper}{q}{qReqConf}))){
      $state = "updating";
      CUL_HM_complConfigTest($e);
    }
    elsif(!defined $defs{$e}{helper}{cfgChk}){
      $state = "ok";
    }
    else{
      $state = join(",",sort map{$chkIds{$_}{shtxt}} keys%{$defs{$e}{helper}{cfgChk}});
      CUL_HM_complConfigTest($e);
    }
    CUL_HM_UpdtReadSingle($defs{$e},"cfgState",$state,1);  
  }
  
  $ret = HMinfo_applTxt2Check($ret);
  delete $defs{$name}{nb}{$id};
  $defs{$name}{helper}{cfgChkResult} = $ret;
  if ($ret && defined $defs{$cl}){
    $ret =~s/-ret-/\n/g; # re-insert new-line
    asyncOutput($defs{$cl},$ret);
    return;
  }
  else{
    return $ret;
  }
  
}
sub HMinfo_bpAbort($) {#bp timeout ############################################
  my ($rep) = @_;
  my ($name,$id) = split(":",$rep);
  delete $defs{$name}{nb}{$id};
  return;
}

sub HMinfo_templateChk_Get($){ ################################################
  my ($param) = shift;
  my ($id,$opt,$filter,@a) = split ",",$param;
  $opt = "" if(!defined $opt);
  my $ret;
  if(@a){
    foreach my $dName (HMinfo_getEntities($opt."v",$filter)){
      unshift @a, $dName;
      $ret .= HMinfo_templateChk(@a);
      shift @a;
    }
  }
  else{
    foreach my $dName (HMinfo_getEntities($opt."v",$filter)){
      next if (!defined $defs{$dName}{helper}{tmpl} || ! $defs{$dName}{helper}{tmpl});
      #$ret .= HMinfo_templateChk(@a);
      foreach my $tmpl(keys %{$defs{$dName}{helper}{tmpl}}){
        my ($p,$t)=split(">",$tmpl);
        $ret .= HMinfo_templateChk($dName,$t,($p eq "none"?0:$p),split(" ",$defs{$dName}{helper}{tmpl}{$tmpl}));
      }
    }
  }    
  $ret = $ret ? $ret
               :"templateChk: passed";
  $ret =~ s/\n/-ret-/g; # replace return with a placeholder - we cannot transfere direct
  return "$id;$ret";
}
sub HMinfo_templateDef(@){#####################################################
  my ($name,$param,$desc,@regs) = @_;
  return "insufficient parameter, no param" if(!defined $param);
  CUL_HM_TemplateModify();
  $tmplDefChange = 1;# signal we have a change!
  if ($param eq "del"){
    return "template in use, cannot be deleted" if(HMinfo_templateUsg("","",$name));
    delete $HMConfig::culHmTpl{$name};
    return;
  }
  elsif ($param eq "delForce"){# delete unconditional
    delete $HMConfig::culHmTpl{$name};
    return;
  }
  return "$name : param:$param already defined, delete it first" if($HMConfig::culHmTpl{$name});
  if ($param eq "fromMaster"){#set hm templateDef <tmplName> fromMaster <master> <(peer:long|0)> <descr>
    my ($master,$pl) = ($desc,@regs);
    return "master $master not defined" if(!$defs{$master});
    @regs = ();
    if ($pl eq "0"){
      foreach my $rdN (grep !/^\.?R-.*-(sh|lg)/,grep /^\.?R-/,keys %{$defs{$master}{READINGS}}){
        my $rdP = $rdN;
        $rdP =~ s/^\.?R-//;
        my ($val) = map{s/ .*//;$_;}$defs{$master}{READINGS}{$rdN}{VAL};
        push @regs,"$rdP:$val";
      }
    }
    else{
      my ($peer,$shlg) = split(":",$pl,2);
      return "peersegment not allowed. use <peer>:(both|short|long)" if($shlg != m/(short|long|both)/);
      $shlg = ($shlg eq "short"?"sh"
             :($shlg eq "long" ?"lg"
             :""));
      foreach my $rdN (grep /^\.?R-$peer-$shlg/,keys %{$defs{$master}{READINGS}}){
        my $rdP = $rdN;
        $rdP =~ s/^\.?R-$peer-$shlg//;
        my ($val) = map{s/ .*//;$_;}$defs{$master}{READINGS}{$rdN}{VAL};
        push @regs,"$rdP:$val";
      }
    }
    $param = "0";
    $desc = "from Master $name > $pl";
  }
  # get description if marked wir ""
  if ($desc =~ m/^"/ && $desc !~ m/^".*"/ ){ # parse "" - search for close and remove regs inbetween
    my $cnt = 0;
    foreach (@regs){
      $desc .= " ".$_;
      $cnt++;
      last if ($desc =~ m/"$/);
    }
    splice @regs,0,$cnt;
  }
  $desc =~ s/"//g;#reduce " to a single pair
#  $desc = "\"".$desc."\"";

  return "insufficient parameter, regs missing" if(@regs < 1);
 
  my $paramNo;
  if($param ne "0"){
    my @p = split(":",$param);
    $HMConfig::culHmTpl{$name}{p} = join(" ",@p) ;
    $paramNo = scalar (@p);
  }
  else{ 
    $HMConfig::culHmTpl{$name}{p} = "";
    $paramNo = 0;
  }
  
  $HMConfig::culHmTpl{$name}{t} = $desc;
  
  foreach (@regs){
    my ($r,$v)=split(":",$_,2);
    if (!defined $v){
      delete $HMConfig::culHmTpl{$name};
      return " empty reg value for $r";
    }
    elsif($v =~ m/^p(\d)/){
      if (($1+1)>$paramNo){
        delete $HMConfig::culHmTpl{$name};
        return ($1+1)." params are necessary, only $paramNo given";
      }
    } 
    $HMConfig::culHmTpl{$name}{reg}{$r} = $v;
  }
}
sub HMinfo_templateSet(@){#####################################################
  my ($aName,$tmpl,$pSet,@p) = @_;
  return "aktor $aName unknown"                           if(!$defs{$aName});
  return "template undefined $tmpl"                       if(!$HMConfig::culHmTpl{$tmpl});
  return "exec set $aName getConfig first"                if(!(grep /RegL_/,keys%{$defs{$aName}{READINGS}}));

  my $tmplID = "$pSet>$tmpl";
  $pSet = ":" if (!$pSet || $pSet eq "none");
  my ($pName,$pTyp) = split(":",$pSet);
  return "give <peer>:[short|long|both] with peer, not $pSet $pName,$pTyp"  if($pName && $pTyp !~ m/(short|long|both)/);
  $pSet = $pTyp ? ($pTyp eq "long" ?"lg"
                 :($pTyp eq "short"?"sh"
                 :""))                  # could be "both"
                 :"";
  my $aHash = $defs{$aName};
#blindActuator - confBtnTime range:1 to 255min special:permanent : 255=permanent 
#blindActuator - intKeyVisib literal:visib,invisib : visibility of internal channel 
  my @regCh;
  foreach (keys%{$HMConfig::culHmTpl{$tmpl}{reg}}){
    my $regN = $pSet.$_;
    my $regV = $HMConfig::culHmTpl{$tmpl}{reg}{$_};
    if ($regV =~m /^p(.)$/) {#replace with User parameter
      return "insufficient values - at least ".$HMConfig::culHmTpl{p}." are $1 necessary" if (@p < ($1+1));
      $regV = $p[$1];
    }
    my ($ret,undef) = CUL_HM_Set($aHash,$aName,"regSet",$regN,"?",$pName);
    return "Device doesn't support $regN - template $tmpl not applicable" if ($ret =~ m/failed:/);
    return "peer necessary for template"                                  if ($ret =~ m/peer required/ && !$pName);
    return "Device doesn't support literal $regV for reg $regN"           if ($ret =~ m/literal:/ && $ret !~ m/\b$regV\b/);
    
    if ($ret =~ m/special:/ && $ret !~ m/\b$regV\b/){# if covered by "special" we are good
      my ($min,$max) = $ret =~ m/range:(.*) to (.*) :/ ? ($1,$2) : ("","");
      $max = 0 if (!$max);
      $max =~ s/([0-9\.]+).*/$1/;
      return "$regV out of range: $min to $max"                           if ($regV !~ m /^set_/ && $min && ($regV < $min || ($max && $regV > $max)));
    }
    push @regCh,"$regN,$regV";
  }
  foreach (@regCh){#Finally write to shadow register.
    my ($ret,undef) = CUL_HM_Set($aHash,$aName,"regSet","prep",split(",",$_),$pName);
    return $ret if ($ret);
  }
  my ($ret,undef) = CUL_HM_Set($aHash,$aName,"regSet","exec",split(",",$regCh[0]),$pName);
  HMinfo_templateMark($aHash,$tmplID,@p);
  return $ret;
}
sub HMinfo_templateMark(@){####################################################
  my ($aHash,$tmplID,@p) = @_;
  $aHash->{helper}{tmpl}{$tmplID} = join(" ",@p);
  $tmplUsgChange = 1; # mark change
  $aHash->{helper}{tmplChg} = 1;
  CUL_HM_setTmplDisp($aHash);#set readings if desired
  return;
}
sub HMinfo_templateDel(@){#####################################################
  my ($aName,$tmpl,$pSet) = @_;
  return if (!defined $defs{$aName});
  delete $defs{$aName}{helper}{tmpl}{"$pSet>$tmpl"};
  $tmplUsgChange = 1; # mark change

  $defs{$aName}{helper}{tmplChg} = 1;
  CUL_HM_setTmplDisp($defs{$aName});#set readings if desired
  return;
}
sub HMinfo_templateExe(@){#####################################################
  my ($opt,$filter,$tFilter) = @_;
  foreach my $dName (HMinfo_getEntities($opt."v",$filter)){
    next if(!defined $defs{$dName}{helper}{tmpl});
    foreach my $tid(keys %{$defs{$dName}{helper}{tmpl}}){
      my ($p,$t) = split(">",$tid);
      next if($tFilter && $tFilter ne $t);
      HMinfo_templateSet($dName,$t,$p,split(" ",$defs{$dName}{helper}{tmpl}{$tid}));
    }
  }
  return;
}
sub HMinfo_templateUsg(@){#####################################################
  my ($opt,$filter,$tFilter) = @_;
  $tFilter = "all" if (!$tFilter);
  my @ul;# usageList
  my @nul;# NonUsageList
  my %h;
  foreach my $dName (HMinfo_getEntities($opt."v",$filter)){
    my @regLists = map {(my $foo = $_)=~s/^\.//;$foo}CUL_HM_reglUsed($dName);
    foreach my $rl (@regLists){
      if    ($rl =~ m/^RegL_.*\.$/)    {$h{$dName}{general}     = 1;} # no peer register
      elsif ($rl =~ m/^RegL_03\.(.*)$/){$h{$dName}{$1.":short"} = 1;
                                        $h{$dName}{$1.":long"}  = 1;} # peer short and long register
      elsif ($rl =~ m/^RegL_0.\.(.*)$/){$h{$dName}{$1}          = 1;} # peer register
    }
   #.RegL_00.
   #.RegL_01.
   #.RegL_03.FB2_1
   #.RegL_03.FB2_2
   #.RegL_03.dis_01
   #.RegL_03.dis_02
   #.RegL_03.self01
   #.RegL_03.self02

    foreach my $tid(keys %{$defs{$dName}{helper}{tmpl}}){
      my ($p,$t) = split(">",$tid);             #split Peer > Template
      my ($pn,$ls) = split(":",$p);             #split PeerName : list
      
      if   ($tFilter =~ m/^sort.*/){
        if($tFilter eq "sortTemplate"){
          push @ul,sprintf("%-20s|%-15s|%s|%s",$t,$dName,$p,$defs{$dName}{helper}{tmpl}{$tid});
        }
        elsif($tFilter eq "sortPeer"){
          push @ul,sprintf("%-20s|%-15s|%5s:%-20s|%s",$pn,$t,$ls,$dName,$defs{$dName}{helper}{tmpl}{$tid});
        }
      }
      elsif($tFilter eq $t || $tFilter eq "all"){
        my @param;
        my $para = "";
        if($defs{$dName}{helper}{tmpl}{$tid}){
          @param = split(" ",$HMConfig::culHmTpl{$t}{p});
          my @value = split(" ",$defs{$dName}{helper}{tmpl}{$tid});
          for (my $i = 0; $i<scalar(@value); $i++){
           $param[$i] .= ":".$value[$i];
          }
          $para = join(" ",@param);
        }
        push @ul,sprintf("%-20s|%-15s|%s|%s",$dName,$p,$t,$para);
      }
      elsif($tFilter eq "noTmpl"){
        if    ($p eq "none")         {$h{$dName}{general}      = 0;}
        elsif ($ls && $ls eq "short"){$h{$dName}{$pn.":short"} = 0;}
        elsif ($ls && $ls eq "long") {$h{$dName}{$pn.":long"}  = 0;}
        elsif ($ls && $ls eq "both") {$h{$dName}{$pn.":short"} = 0;
                                      $h{$dName}{$pn.":long"}  = 0;}
        elsif ($pn )                 {$h{$dName}{$pn}          = 0;}
      }
    }
    if ($tFilter eq "noTmpl"){
      foreach my $item (keys %{$h{$dName}}){
        push @nul,sprintf("%-20s|%-15s ",$dName,$item) if($h{$dName}{$item});
      }
    }
  }
  if ($tFilter eq "noTmpl"){return  "\n no template for:\n"
                                   .join("\n",sort(@nul)); }
  else{                     return  join("\n",sort(@ul));  }
}

sub HMinfo_templateChk(@){#####################################################
  my ($aName,$tmpl,$pSet,@p) = @_;
  # pset: 0                = template w/o peers
  #       peer / peer:both = template for peer, not extending Long/short
  #       peer:short|long  = template for peerlong or short

  return "$aName: - $tmpl:template undefined\n"                       if(!$HMConfig::culHmTpl{$tmpl});
  return "$aName: unknown\n"                                          if(!$defs{$aName});
  return "$aName: - $tmpl:give <peer>:[short|long|both] wrong:$pSet\n"if($pSet && $pSet !~ m/:(short|long|both)$/);
  $pSet = "0:0" if (!$pSet);
  my $repl = "";
  my($pName,$pTyp) = split(":",$pSet);
  
  $pName = $1 if($pName =~ m/(.*)_chn-(..)$/);
 
  if($pName && (0 == scalar grep /^$pName$/,split(",",ReadingsVal($aName,"peerList" ,"")))){
    $repl = "$aName: $pSet->no peer:$pName - ".ReadingsVal($aName,"peerList" ,"")."\n";
  }
  else{
    my $pRnm = "";
    if ($pName){
      if (defined $defs{$pName} && $defs{$pName}{helper}{role}{dev}){
        $pRnm = $pName."_chn-01-";
      }
      else{
        $pRnm = $pName."-";
      }
    }
    my $pRnmLS = $pTyp eq "long"?"lg":($pTyp eq "short"?"sh":"");
    foreach my $rn (keys%{$HMConfig::culHmTpl{$tmpl}{reg}}){
      my $regV;
      my $pRnmChk = $pRnm.($rn !~ m/^(lg|sh)/ ? $pRnmLS :"");
      if ($pRnm){
        $regV    = ReadingsVal($aName,"R-$pRnmChk$rn" ,ReadingsVal($aName,".R-$pRnmChk$rn",undef));
      }
      $regV    = ReadingsVal($aName,"R-".$rn     ,ReadingsVal($aName,".R-".$rn    ,undef)) if (!defined $regV);
      if (defined $regV){
        $regV =~s/ .*//;#strip unit
        my $tplV = $HMConfig::culHmTpl{$tmpl}{reg}{$rn};
        if ($tplV =~m /^p(.)$/) {#replace with User parameter
          return "insufficient data - at least ".$HMConfig::culHmTpl{p}." are $1 necessary"
                                                         if (@p < ($1+1));
          $tplV = $p[$1];
        }
        $repl .= "$aName: $pSet->$tmpl - $rn :$regV should $tplV \n" if ($regV ne $tplV);
      }
      else{
        $repl .= "$aName: $pSet->$tmpl - reg not found: $rn :$pRnm\n";
      }
    }
  }

  return $repl;
}
sub HMinfo_templateList($){####################################################
  my $templ = shift;
  my $reply = "defined tempates:\n";
  if(!$templ || $templ eq "all"){# list all templates
    foreach (sort keys%HMConfig::culHmTpl){
      next if ($_ =~ m/^tmpl...Change$/); #ignore control
      $reply .= sprintf("%-16s params:%-24s Info:%s\n"
                             ,$_
                             ,$HMConfig::culHmTpl{$_}{p}
                             ,$HMConfig::culHmTpl{$_}{t}
                       );
    }
  }
  elsif( grep /$templ/,keys%HMConfig::culHmTpl ){#details about one template
    $reply = sprintf("%-16s params:%-24s Info:%s\n",$templ,$HMConfig::culHmTpl{$templ}{p},$HMConfig::culHmTpl{$templ}{t});
    foreach (sort keys %{$HMConfig::culHmTpl{$templ}{reg}}){
      my $val = $HMConfig::culHmTpl{$templ}{reg}{$_};
      if ($val =~m /^p(.)$/){
        my @a = split(" ",$HMConfig::culHmTpl{$templ}{p});
        $val = $a[$1];
      }
      $reply .= sprintf("  %-16s :%s\n",$_,$val);
    }
  }
  return $reply;
}
sub HMinfo_templateWrite($){###################################################
  my $fName = shift;
  HMinfo_templateWriteDef($fName) if ($tmplDefChange);
  HMinfo_templateWriteUsg($fName) if ($tmplUsgChange);
  return;
}
sub HMinfo_templateWriteDef($){################################################
  my $fName = shift;
  $tmplDefChange = 0; # reset changed bits
  my @tmpl =();
  #set templateDef <templateName> <param1[:<param2>...] <description> <reg1>:<val1> [<reg2>:<val2>] ... 
  foreach my $tpl(sort keys%HMConfig::culHmTpl){
    next if ($tpl =~ m/^tmpl...Change$/  ||!defined$HMConfig::culHmTpl{$tpl}{reg}); 
    my @reg =();
    foreach (keys%{$HMConfig::culHmTpl{$tpl}{reg}}){
      push @reg,$_.":".$HMConfig::culHmTpl{$tpl}{reg}{$_};
    }
    push @tmpl,sprintf("templateDef =>%s=>%s=>\"%s\"=>%s"
                           ,$tpl
                           ,($HMConfig::culHmTpl{$tpl}{p}?join(":",split(" ",$HMConfig::culHmTpl{$tpl}{p})):"0")
                           ,$HMConfig::culHmTpl{$tpl}{t}
                           ,join(" ",@reg)
                     );
  }

  open(aSave, ">>$fName") || return("Can't open $fName: $!");
  #important - this is the header - prior entires in the file will be ignored
  print aSave "\n\ntemplateDef templateStart Block stored:".TimeNow()."*******************\n\n";
  print aSave "\n".$_ foreach(sort @tmpl);
  print aSave "\n======= finished templates ===\n";
  close(aSave);

  return;
}
sub HMinfo_templateWriteUsg($){################################################
  my $fName = shift;
  $tmplUsgChange = 0; # reset changed bits
  my @tmpl =();
  foreach my $eN(sort (devspec2array("TYPE=CUL_HM"))){
    next if($defs{$eN}{helper}{role}{vrt} || !$defs{$eN}{helper}{tmplChg});
    push @tmpl,sprintf("templateSet =>%s=>start",$eN);# indicates: all entries before are obsolete
    $defs{$eN}{helper}{tmplChg} = 0;
    if (defined $defs{$eN}{helper}{tmpl}){
      foreach my $tid(keys %{$defs{$eN}{helper}{tmpl}}){
        my ($p,$t) = split(">",$tid);
        next if (!defined$HMConfig::culHmTpl{$t});
        push @tmpl,sprintf("templateSet =>%s=>%s=>%s"
                             ,$eN
                             ,$tid
                             ,$defs{$eN}{helper}{tmpl}{$tid}
                       );
      }
    }
  }
  if (@tmpl){
    open(aSave, ">>$fName") || return("Can't open $fName: $!");
    #important - this is the header - prior entires in the file will be ignored
    print aSave "\n".$_ foreach(@tmpl);
    print aSave "\n======= finished templates ===\n";
    close(aSave);
  }
  return;
}

sub HMinfo_cpRegs(@){##########################################################
  my ($srcCh,$dstCh) = @_;
  my ($srcP,$dstP,$srcPid,$dstPid,$srcRegLn,$dstRegLn);
  ($srcCh,$srcP) = split(":",$srcCh,2);
  ($dstCh,$dstP) = split(":",$dstCh,2);
  return "source channel $srcCh undefined"      if (!$defs{$srcCh});
  return "destination channel $srcCh undefined" if (!$defs{$dstCh});
  #compare source and destination attributes

  if ($srcP){# will be peer related copy
    if   ($srcP =~ m/self(.*)/)      {$srcPid = substr($defs{$srcCh}{DEF},0,6).sprintf("%02X",$1)}
    elsif($srcP =~ m/^[A-F0-9]{8}$/i){$srcPid = $srcP;}
    elsif($srcP =~ m/(.*)_chn-(..)/) {$srcPid = $defs{$1}->{DEF}.$2;}
    elsif($defs{$srcP})              {$srcPid = $defs{$srcP}{DEF}.$2;}

    if   ($dstP =~ m/self(.*)/)      {$dstPid = substr($defs{$dstCh}{DEF},0,6).sprintf("%02X",$1)}
    elsif($dstP =~ m/^[A-F0-9]{8}$/i){$dstPid = $dstP;}
    elsif($dstP =~ m/(.*)_chn-(..)/) {$dstPid = $defs{$1}->{DEF}.$2;}
    elsif($defs{$dstP})              {$dstPid = $defs{$dstP}{DEF}.$2;}

    return "invalid peers src:$srcP dst:$dstP" if(!$srcPid || !$dstPid);
    return "source peer not in peerlist"       if ($attr{$srcCh}{peerIDs} !~ m/$srcPid/);
    return "destination peer not in peerlist"  if ($attr{$dstCh}{peerIDs} !~ m/$dstPid/);

    if   ($defs{$srcCh}{READINGS}{"RegL_03.".$srcP})  {$srcRegLn =  "RegL_03.".$srcP}
    elsif($defs{$srcCh}{READINGS}{".RegL_03.".$srcP}) {$srcRegLn = ".RegL_03.".$srcP}
    elsif($defs{$srcCh}{READINGS}{"RegL_04.".$srcP})  {$srcRegLn =  "RegL_04.".$srcP}
    elsif($defs{$srcCh}{READINGS}{".RegL_04.".$srcP}) {$srcRegLn = ".RegL_04.".$srcP}
    $dstRegLn = $srcRegLn;
    $dstRegLn =~ s/:.*/:/;
    $dstRegLn .= $dstP;
  }
  else{
    if   ($defs{$srcCh}{READINGS}{"RegL_01."})  {$srcRegLn = "RegL_01."}
    elsif($defs{$srcCh}{READINGS}{".RegL_01."}) {$srcRegLn = ".RegL_01."}
    $dstRegLn = $srcRegLn;
  }
  return "source register not available"     if (!$srcRegLn);
  return "regList incomplete"                if ($defs{$srcCh}{READINGS}{$srcRegLn}{VAL} !~ m/00:00/);

  # we habe a reglist with termination, source and destination peer is checked. Go copy
  my $srcData = $defs{$srcCh}{READINGS}{$srcRegLn}{VAL};
  $srcData =~ s/00:00//; # remove termination
  my ($ret,undef) = CUL_HM_Set($defs{$dstCh},$dstCh,"regBulk",$srcRegLn,split(" ",$srcData));
  return $ret;
}
sub HMinfo_noDup(@) {#return list with no duplicates###########################
  my %all;
  return "" if (scalar(@_) == 0);
  $all{$_}=0 foreach (grep {defined($_)} @_);
  delete $all{""}; #remove empties if present
  return (sort keys %all);
}


1;
=pod
=item command
=item summary    support and control instance for wireless homematic devices and IOs
=item summary_DE Unterstützung und Überwachung von Homematic Funk devices und IOs 

=begin html


<a id="HMinfo"></a>
<h3>HMinfo</h3>
<ul>

  HMinfo is a module to support getting an overview  of
  eQ-3 HomeMatic devices as defines in <a href="#CUL_HM">CUL_HM</a>. <br><br>
  <B>Status information and counter</B><br>
  HMinfo gives an overview on the CUL_HM installed base including current conditions.
  Readings and counter will not be updated automatically  due to performance issues. <br>
  Command <a href="#HMinfo-set-update">update</a> must be used to refresh the values. 
  <ul><code><br>
           set hm update<br>
  </code></ul><br>
  Webview of HMinfo providee details, basically counter about how
  many CUL_HM entities experience exceptional conditions. It contains
  <ul>
      <li>Action Detector status</li>
      <li>CUL_HM related IO devices and condition</li>
      <li>Device protocol events which are related to communication errors</li>
      <li>count of certain readings (e.g. battery) and conditions - <a href="#HMinfo-attr">attribut controlled</a></li>
      <li>count of error condition in readings (e.g. overheat, motorErr) - <a href="#HMinfo-attr">attribut controlled</a></li>
  </ul>
  <br>

  It also allows some HM wide commands such
  as store all collected register settings.<br><br>

  Commands are executed on all HM entities.
  If applicable and evident execution is restricted to related entities.
  e.g. rssi is executed on devices only since channels do not support rssi values.<br><br>
  <a id="HMinfo-Filter"></a><b>Filter</b>
  <ul>  can be applied as following:<br><br>
        <code>set &lt;name&gt; &lt;cmd&gt; &lt;filter&gt; [&lt;param&gt;]</code><br>
        whereby filter has two segments, typefilter and name filter<br>
        [-dcasev] [-f &lt;filter&gt;]<br><br>
        filter for <b>types</b> <br>
        <ul>
            <li>d - device   :include devices</li>
            <li>c - channels :include channels</li>
            <li>v - virtual  :supress fhem virtual</li>
            <li>p - physical :supress physical</li>
            <li>a - aktor    :supress actor</li>
            <li>s - sensor   :supress sensor</li>
            <li>e - empty    :include results even if requested fields are empty</li>
            <li>2 - alias    :display second name alias</li>
        </ul>
        and/or filter for <b>names</b>:<br>
        <ul>
            <li>-f &lt;filter&gt;  :regexp to filter entity names </li>
        </ul>
        Example:<br>
        <ul><code>
           set hm param -d -f dim state # display param 'state' for all devices whos name contains dim<br>
           set hm param -c -f ^dimUG$ peerList # display param 'peerList' for all channels whos name is dimUG<br>
           set hm param -dcv expert # get attribut expert for all channels,devices or virtuals<br>
        </code></ul>
  </ul>
  <br>
  <a id="HMinfo-define"><h4>Define</h4></a>
  <ul>
    <code>define &lt;name&gt; HMinfo</code><br>
    Just one entity needs to be defined without any parameter.<br>
  </ul>
  <br>
  <a id="HMinfo-get"></a><h4>Get</h4>
  <ul>
      <li><a id="HMinfo-get-models"></a>models<br>
          list all HM models that are supported in FHEM
      </li>
      <li><a id="HMinfo-get-param"></a>param <a href="#HMinfo-Filter">[filter]</a> &lt;name&gt; &lt;name&gt;...<br>
          returns a table of parameter values (attribute, readings,...)
          for all entities as a table
      </li>
      <li><a id="HMinfo-get-register"></a>register <a href="#HMinfo-Filter">[filter]</a><br>
          provides a tableview of register of an entity
      </li>
      <li><a id="HMinfo-get-regCheck"></a>regCheck <a href="#HMinfo-Filter">[filter]</a><br>
          performs a consistency check on register readings for completeness
      </li>
      <li><a id="HMinfo-get-peerCheck"></a>peerCheck <a href="#HMinfo-Filter">[filter]</a><br>
          performs a consistency check on peers. If a peer is set in a channel
          it will check wether the peer also exist on the opposit side.
      </li>
      <li><a id="HMinfo-get-peerUsg"></a>peerUsg <a href="#HMinfo-Filter">[filter]</a><br>
          provides a cross-reference on peerings and assigned template information
      </li>
      <li><a id="HMinfo-get-peerXref"></a>peerXref <a href="#HMinfo-Filter">[filter]</a><br>
          provides a cross-reference on peerings, a kind of who-with-who summary over HM
      </li>
      <li><a id="HMinfo-get-configCheck"></a>configCheck <a href="#HMinfo-Filter">[filter]</a><br>
          performs a consistency check of HM settings. It includes regCheck and peerCheck
      </li>
      <li><a id="HMinfo-get-configChkResult"></a>configChkResult<br>
          returns the results of a previous executed configCheck
      </li>
      <li><a id="HMinfo-get-templateList"></a>templateList [&lt;name&gt;]<br>
          list defined templates. If no name is given all templates will be listed<br>
      </li>
      <li><a id="HMinfo-get-configInfo"></a>configInfo [&lt;name&gt;]<br>
          information to getConfig results<br>
      </li>
      <li><a id="HMinfo-get-templateUsg" data-pattern="templateUsg.*"></a>templateUsg &lt;template&gt; [sortPeer|sortTemplate]<br>
          templare usage<br>
          template filters the output<br>
          <i>templateUsgG</i> (for all devices)
      </li>
      <li><a id="HMinfo-get-msgStat"></a>msgStat <a href="#HMinfo-Filter">[filter]</a><br>
          statistic about message transferes over a week<br>
      </li>
      <li><a id="HMinfo-get-protoEvents"></a>protoEvents <a href="#HMinfo-Filter">[filter]</a> <br>
          <B>important view</B> about pending commands and failed executions for all devices in a single table.<br>
          Consider to clear this statistic use <a name="#HMinfoclear">clear msgEvents</a>.<br>
      </li>
      <li><a id="HMinfo-get-rssi" data-pattern="rssi.*"></a>rssi <a href="#HMinfo-Filter">[filter]</a><br>
          statistic over rssi data for HM entities.<br>
      </li>

      <li><a id="HMinfo-get-templateChk"></a>templateChk <a href="#HMinfo-Filter">[filter]</a> &lt;template&gt; &lt;peer:[long|short]&gt; [&lt;param1&gt; ...]<br>
         verifies if the register-readings comply to the template <br>
         Parameter are identical to <a href="#HMinfo-set-templateSet">templateSet</a><br>
         The procedure will check if the register values match the ones provided by the template<br>
         If no peer is necessary use <b>none</b> to skip this entry<br>
        Example to verify settings<br>
        <ul><code>
         set hm templateChk -f RolloNord BlStopUpLg none         1 2 # RolloNord, no peer, parameter 1 and 2 given<br>
         set hm templateChk -f RolloNord BlStopUpLg peerName:long    # RolloNord peerName, long only<br>
         set hm templateChk -f RolloNord BlStopUpLg peerName         # RolloNord peerName, long and short<br>
         set hm templateChk -f RolloNord BlStopUpLg peerName:all     # RolloNord peerName, long and short<br>
         set hm templateChk -f RolloNord BlStopUpLg all:long         # RolloNord any peer, long only<br>
         set hm templateChk -f RolloNord BlStopUpLg all              # RolloNord any peer,long and short<br>
         set hm templateChk -f Rollo.*   BlStopUpLg all              # each Rollo* any peer,long and short<br>
         set hm templateChk BlStopUpLg                               # each entities<br>
         set hm templateChk                                          # all assigned templates<br>
         set hm templateChk sortTemplate                             # all assigned templates sortiert nach Template<br>
         set hm templateChk sortPeer                                 # all assigned templates sortiert nach Peer<br>
        </code></ul>
      </li>
      <li><a id="HMinfo-get-showTimer"></a>showTimer <br>
          show all timer currently running at this point in time.<br>
      </li>
  </ul>
  <a id="HMinfo-set"></a><h4>Set</h4>
  <ul>
    Even though the commands are a get funktion they are implemented
    as set to allow simple web interface usage<br>
      <li><a id="HMinfo-set-update"></a>update<br>
          updates HM status counter.
      </li>

      <li><a id="HMinfo-set-autoReadReg"></a>autoReadReg <a href="#HMinfo-Filter">[filter]</a><br>
          schedules a read of the configuration for the CUL_HM devices with attribut autoReadReg set to 1 or higher.
      </li>
      <li><a id="HMinfo-set-cmdRequestG"></a>cmdRequestG <br>
          issues a status request to update the system and performs access check to devices<br>
          ping: for one channel per CUL_HM device<br>
          status: for all channels that suport statusRequest<br>
          Ping will generate a message to the device. If not answered the device is unaccessible. Check protState for errors in case.
      </li>
      <li><a id="HMinfo-set-clear" data-pattern="clear.*"></a>clear <a href="#HMinfo-Filter">[filter]</a> [msgEvents|readings|msgStat|register|rssi]<br>
          executes a set clear ...  on all HM entities<br>
          <ul>
          <li>protocol relates to set clear msgEvents</li>
          <li>set clear msgEvents for all device with protocol errors</li>
          <li>readings relates to set clear readings</li>
          <li>rssi clears all rssi counters </li>
          <li>msgStat clear HM general message statistics</li>
          <li>register clears all register-entries in readings</li>
          </ul>
          <i>clearG</i> (for all devices)
      </li>
      <li><a id="HMinfo-set-saveConfig"></a>saveConfig <a href="#HMinfo-Filter">[filter] [&lt;file&gt;]</a><br>
          performs a save for all HM register setting and peers. See <a href="#CUL_HM-set-saveConfig">CUL_HM saveConfig</a>.<br>
          <a href="#HMinfo-set-purgeConfig"></a>purgeConfig will be executed automatically if the stored filesize exceeds 1MByte.<br>
      </li>
      <li><a id="HMinfo-set-archConfig"></a>archConfig <a href="#HMinfo-Filter">[filter]</a> [&lt;file&gt;]<br>
          performs <a href="#HMinfo-set-saveConfig"></a>saveConfig for entities that appeare to have achanged configuration.
          It is more conservative that saveConfig since incomplete sets are not stored.<br>
          Option -a force an archieve for all devices that have a complete set of data<br>
      </li>
      <li><a id="HMinfo-set-loadConfig"></a>loadConfig <a href="#HMinfo-Filter">[filter]</a> [&lt;file&gt;]<br>
          loads register and peers from a file saved by <a href="#HMinfo-set-saveConfig">saveConfig</a>.<br>
          It should be used carefully since it will add data to FHEM which cannot be verified. No readings will be replaced, only 
          missing readings will be added. The command is mainly meant to be fill in readings and register that are 
          hard to get. Those from devices which only react to config may not easily be read. <br>
          Therefore it is strictly up to the user to fill valid data. User should consider using autoReadReg for devices 
          that can be read.<br>
          The command will update FHEM readings and attributes. It will <B>not</B> reprogramm any device.
      </li>
      <li><a id="HMinfo-set-purgeConfig"></a>purgeConfig <a href="#HMinfo-Filter">[filter]</a> [&lt;file&gt;]<br>
          purge (reduce) the saved config file. Due to the cumulative storage of the register setting
          purge will use the latest stored readings and remove older one. 
          See <a href="#CUL_HM-set-saveConfig">CUL_HM saveConfig</a>.
      </li>
      <li><a id="HMinfo-set-verifyConfig"></a>verifyConfig <a href="#HMinfo-Filter">[filter]</a> [&lt;file&gt;]<br>
          Compare date in config file to the currentactive data and report differences. 
          Possibly usable with a known-good configuration that was saved before. 
          It may make sense to purge the config file before.
          See <a href="#CUL_HM-set-purgeConfig">CUL_HM purgeConfig</a>.
      </li>

      
         <br>
      <li><a id="HMinfo-set-tempList" data-pattern="tempList.*"></a>tempList <a href="#HMinfo-Filter">[filter]</a> [save|restore|verify|status|genPlot] [&lt;file&gt;]<br>
          this function supports handling of tempList for thermstates.
          It allows templists to be saved in a separate file, verify settings against the file
          and write the templist of the file to the devices. <br>
          <ul>
          <li><B>save</B> saves tempList readings of the system to the file. <br>
              Note that templist as available in FHEM is put to the file. It is up to the user to make
              sure the data is actual<br>
              Storage is not cumulative - former content of the file will be removed</li>
          <li><B>restore</B> available templist as defined in the file are written directly 
              to the device</li>
          <li><B>verify</B> file data is compared to readings as present in FHEM. It does not
              verify data in the device - user needs to ensure actuallity of present readings</li>
          <li><B>status</B> gives an overview of templates being used by any CUL_HM thermostat. It alls showes 
            templates being defined in the relevant files.
            <br></li>
          <li><B>genPlot</B> generates a set of records to display templates graphicaly.<br>
            Out of the given template-file it generates a .log extended file which contains log-formated template data. timestamps are 
            set to begin Year 2000.<br>
            A prepared .gplot file will be added to gplot directory.<br>
            Logfile-entity <file>_Log will be added if not already present. It is necessary for plotting.<br>
            SVG-entity <file>_SVG will be generated if not already present. It will display the graph.<br>
            <br></li>
          <li><B>file</B> name of the file to be used. Default: <B>tempList.cfg</B></li>
          <br>
          <li><B>filename</B> is the name of the file to be used. Default ist <B>tempList.cfg</B></li>
          File example<br>
          <ul><code>
               entities:HK1_Climate,HK2_Clima<br>
               tempListFri>07:00 14.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0<br>
               tempListMon>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0<br>
               tempListSat>08:00 14.0 15:00 18.0 21:30 19.0 24:00 14.0<br>
               tempListSun>08:00 14.0 15:00 18.0 21:30 19.0 24:00 14.0<br>
               tempListThu>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0<br>
               tempListTue>07:00 14.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 15.0<br>
               tempListWed>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0<br>
               entities:hk3_Climate<br>
               tempListFri>06:00 17.0 12:00 21.0 23:00 20.0 24:00 19.5<br>
               tempListMon>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
               tempListSat>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
               tempListSun>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
               tempListThu>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
               tempListTue>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
               tempListWed>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
         </code></ul>
         File keywords<br>
         <li><B>entities</B> comma separated list of entities which refers to the temp lists following.
           The actual entity holding the templist must be given - which is channel 04 for RTs or channel 02 for TCs</li>
         <li><B>tempList...</B> time and temp couples as used in the set tempList commands</li>
         <li><a id="HMinfo-simDev"><B>simDev -model-</B></a> simulate a device</li>
         </ul>
         <i>tempListG</i> (for all devices)
         <br>
     </li>
         <br>
      <li><a id="HMinfo-set-cpRegs"></a>cpRegs &lt;src:peer&gt; &lt;dst:peer&gt; <br>
          allows to copy register, setting and behavior of a channel to
          another or for peers from the same or different channels. Copy therefore is allowed
          intra/inter device and intra/inter channel. <br>
         <b>src:peer</b> is the source entity. Peer needs to be given if a peer behabior beeds to be copied <br>
         <b>dst:peer</b> is the destination entity.<br>
         Example<br>
         <ul><code>
          set hm cpRegs blindR blindL  # will copy all general register (list 1)for this channel from the blindR to the blindL entity.
          This includes items like drive times. It does not include peers related register (list 3/4) <br>
          set hm cpRegs blindR:Btn1 blindL:Btn2  # copy behavior of Btn1/blindR relation to Btn2/blindL<br>
          set hm cpRegs blindR:Btn1 blindR:Btn2  # copy behavior of Btn1/blindR relation to Btn2/blindR, i.e. inside the same Actor<br>
         </code></ul>
         <br>
         Restrictions:<br>
         <ul>
           cpRegs will <u>not add any peers</u> or read from the devices. It is up to the user to read register in advance<br>
           cpRegs is only allowed between <u>identical models</u><br>
           cpRegs expets that all <u>readings are up-to-date</u>. It is up to the user to ensure data consistency.<br>
         </ul>
      </li>
      <li><a id="HMinfo-set-templateDef"></a>templateDef &lt;name&gt; &lt;param&gt; &lt;desc&gt; &lt;reg1:val1&gt; [&lt;reg2:val2&gt;] ...<br>
        define a template.<br>
        <b>param</b> gives the names of parameter necesary to execute the template. It is template dependant
                     and may be onTime or brightnesslevel. A list of parameter needs to be separated with colon<br>
                     param1:param2:param3<br>
                     if del is given as parameter the template is removed<br>
        <b>desc</b> shall give a description of the template<br>
        <b>reg:val</b> is the registername to be written and the value it needs to be set to.<br>
        In case the register is from link set and can destinguist between long and short it is necessary to leave the
        leading sh or lg off. <br>
        if parameter are used it is necessary to enter p. as value with p0 first, p1 second parameter
        <br>
        Example<br>
        <ul><code>
          set hm templateDef SwOnCond level:cond "my description" CtValLo:p0 CtDlyOn:p1 CtOn:geLo<br>
          set hm templateDef SwOnCond del # delete a template<br>
          set hm templateDef SwOnCond fromMaster &lt;masterChannel&gt; &lt;peer:[long|short]&gt;# define a template with register as of the example<br>
          set hm templateDef SwOnCond fromMaster myChannel peerChannel:long  # <br>
        </code></ul>
      </li>
      <li><a id="HMinfo-set-templateSet"></a>templateSet &lt;entity&gt; &lt;template&gt; &lt;peer:[long|short]&gt; [&lt;param1&gt; ...]<br>
         sets a bunch of register accroding to a given template. Parameter may be added depending on
         the template setup. <br>
         templateSet will collect and accumulate all changes. Finally the results are written streamlined.<br>
        <b>entity:</b> peer is the source entity. Peer needs to be given if a peer behabior beeds to be copied <br>
        <b>template:</b> one of the programmed template<br>
        <b>peer:</b> [long|short]:if necessary a peer needs to be given. If no peer is used enter '0'.
                 with a peer it should be given whether it is for long or short keypress<br>
        <b>param:</b> number and meaning of parameter depends on the given template<br>
        Example could be (templates not provided, just theoretical)<br>
        <ul><code>
          set hm templateSet Licht1 staircase FB1:short 20  <br>
          set hm templateSet Licht1 staircase FB1:long 100  <br>
        </code></ul>
        Restrictions:<br>
        <ul>
          User must ensure to read configuration prior to execution.<br>
          templateSet may not setup a complete register block but only a part if it. This is up to template design.<br>
          <br>

        </ul>
      </li>
      <li><a id="HMinfo-set-templateDel"></a>templateDel &lt;entity&gt; &lt;template&gt; &lt;peer:[long|short]&gt; ]<br>
         remove a template installed by templateSet
          <br>

      </li>
      <li><a id="HMinfo-set-templateExe"></a>templateExe &lt;template&gt; <br>
          executes the register write once again if necessary (e.g. a device had a reset)<br>
      </li>
      <li><a id="HMinfo-set-deviceReplace">x-deviceReplace</a> &lt;oldDevice&gt; &lt;newDevice&gt; <br>
          replacement of an old or broken device with a replacement. The replacement needs to be compatible - FHEM will check this partly. It is up to the user to use it carefully. <br>
          The command needs to be executed twice for safety reasons. The first call will return with CAUTION remark. Once issued a second time the old device will be renamed, the new one will be named as the old one. Then all peerings, register and templates are corrected as best as posible. <br>
          NOTE: once the command is executed devices will be reconfigured. This cannot be reverted automatically.  <br>
          Replay of teh old confg-files will NOT restore the former configurations since also registers changed! Exception: proper and complete usage of templates!<br>
          In case the device is configured using templates with respect to registers a verification of the procedure is very much secure. Otherwise it is up to the user to supervice message flow for transmission failures. <br>
      </li>
  </ul>
  <br>

  <br><br>
  <a id="HMinfo-attr"></a><h4>Attributes</h4>
   <ul>
     <a id="HMinfo-attr-sumStatus"></a>
     <li>sumStatus<br>
       Warnings: list of readings that shall be screend and counted based on current presence.
       I.e. counter is the number of entities with this reading and the same value.
       Readings to be searched are separated by comma. <br>
       Example:<br>
       <ul><code>
         attr hm sumStatus battery,sabotageError<br>
       </code></ul>
       will cause a reading like<br>
       W_sum_battery ok:5 low:3<br>
       W_sum_sabotageError on:1<br>
       <br>
       Note: counter with '0' value will not be reported. HMinfo will find all present values autonomously<br>
       Setting is meant to give user a fast overview of parameter that are expected to be system critical<br>
     </li>
     <a id="HMinfo-attr-sumERROR"></a>
     <li>sumERROR<br>
       Similar to sumStatus but with a focus on error conditions in the system.
       Here user can add reading<b>values</b> that are <b>not displayed</b>. I.e. the value is the
       good-condition that will not be counted.<br>
       This way user must not know all error values but it is sufficient to supress known non-ciritical ones.
       <br>
       Example:<br>
       <ul><code>
         attr hm sumERROR battery:ok,sabotageError:off,overheat:off,Activity:alive:unknown<br>
       </code></ul>
       will cause a reading like<br>
       <ul><code>
         ERR_battery low:3<br>
         ERR_sabotageError on:1<br>
         ERR_overheat on:3<br>
         ERR_Activity dead:5<br>
       </code></ul>
     </li>
     <a id="HMinfo-attr-autoUpdate"></a>
     <li>autoUpdate<br>
       retriggers the command update periodically.<br>
       Example:<br>
       <ul><code>
         attr hm autoUpdate 00:10<br>
       </code></ul>
       will trigger the update every 10 min<br>
     </li>
     <a id="HMinfo-attr-autoArchive"></a>
     <li>autoArchive<br>
       if set fhem will update the configFile each time the new data is available.
       The update will happen with <a href="#HMinfo-att-autoUpdate">autoUpdate</a>. It will not 
       work it autoUpdate is not used.<br>
       see also <a href="#HMinfo-attr-archConfig">archConfig</a>
       <br>
     </li>
     <a id="HMinfo-attr-hmAutoReadScan"></a>
     <li>hmAutoReadScan<br>
       defines the time in seconds CUL_HM tries to schedule the next autoRead
       from the queue. Despite this timer FHEM will take care that only one device from the queue will be
       handled at one point in time. With this timer user can stretch timing even further - to up to 300sec
       min delay between execution. <br>
       Setting to 1 still obeys the "only one at a time" prinzip.<br>
       Note that compressing will increase message load while stretch will extent waiting time.<br>
     </li>
     <a id="HMinfo-attr-hmIoMaxDly"></a>
     <li>hmIoMaxDly<br>
       max time in seconds CUL_HM stacks messages if the IO device is not ready to send.
       If the IO device will not reappear in time all command will be deleted and IOErr will be reported.<br>
       Note: commands will be executed after the IO device reappears - which could lead to unexpected
       activity long after command issue.<br>
       default is 60sec. max value is 3600sec<br>
     </li>
     <a id="HMinfo-attr-configDir"></a>
     <li>configDir<br>
       default directory where to store and load configuration files from.
       This path is used as long as the path is not given in a filename of 
       a given command.<br>
       It is used by commands like <a href="#HMinfo-set-tempList">tempList</a> or <a href="#HMinfo-set-saveConfig">saveConfig</a><br>
     </li>
     <a id="HMinfo-attr-configFilename"></a>
     <li>configFilename<br>
       default filename used by 
       <a href="#HMinfo-set-saveConfig">saveConfig</a>, 
       <a href="#HMinfo-set-purgeConfig">purgeConfig</a>, 
       <a href="#HMinfo-set-loadConfig">loadConfig</a><br>
       <a href="#HMinfo-set-verifyConfig">verifyConfig</a><br>
     </li>
     <a id="HMinfo-attr-configTempFile"></a>
     <li>configTempFile&lt;;configTempFile2&gt;&lt;;configTempFile3&gt;<br>
        Liste of Templfiles (weekplan) which are considered in HMInfo and CUL_HM<br>
        Files are comma separated. The first file is default. Its name may be skipped when setting a tempalte.<br>
     </li>
     <a id="HMinfo-attr-hmManualOper"></a>
     <li>hmManualOper<br>
       set to 1 will prevent any automatic operation, update or default settings
       in CUL_HM.<br>
     </li>
     <a id="HMinfo-attr-hmDefaults"></a>
     <li>hmDefaults<br>
       set default params for HM devices. Multiple attributes are possible, comma separated.<br>
       example:<br>
       attr hm hmDefaults hmProtocolEvents:0_off,rssiLog:0<br>
     </li>
     <a id="HMinfo-attr-verbCULHM"></a>
     <li>verbCULHM<br>
       set verbose logging for a special action for any CUL_HM entity.<br>
       allSet: all set commands to be executed.<br>
       allGet: all get requests to be executed.<br>
     </li>
     <a id="HMinfo-attr-autoLoadArchive"></a>
     <li>autoLoadArchive<br>
       if set the register config will be loaded after reboot automatically. See <a href="#HMinfo-set-loadConfig">loadConfig</a> for details<br>
     </li>
     

   </ul>
   <br>
  <a id="HMinfo-variables"></a><b>Variables</b>
   <ul>
     <li><b>I_autoReadPend:</b> Info:list of entities which are queued to retrieve config and status.
                             This is typically scheduled thru autoReadReg</li>
     <li><b>ERR___rssiCrit:</b> Error:list of devices with RSSI reading n min level </li>
     <li><b>W_unConfRegs:</b> Warning:list of entities with unconfirmed register changes. Execute getConfig to clear this.</li>
     <li><b>I_rssiMinLevel:</b> Info:counts of rssi min readings per device, clustered in blocks</li>
     

     <li><b>ERR__protocol:</b> Error:count of non-recoverable protocol events per device.
         Those events are NACK, IOerr, ResendFail, CmdDel, CmdPend.<br>
         Counted are the number of device with those events, not the number of events!</li>
     <li><b>ERR__protoNames:</b> Error:name-list of devices with non-recoverable protocol events</li>
     <li><b>I_HM_IOdevices:</b> Info:list of IO devices used by CUL_HM entities</li>
     <li><b>I_actTotal:</b> Info:action detector state, count of devices with ceratin states</li>
     <li><b>ERRactNames:</b> Error:names of devices that are not alive according to ActionDetector</li>
     <li><b>C_sumDefined:</b> Count:defined entities in CUL_HM. Entites might be count as
         device AND channel if channel funtion is covered by the device itself. Similar to virtual</li>
     <li><b>ERR_&lt;reading&gt;:</b> Error:count of readings as defined in attribut
         <a href="#HMinfo-attr-sumERROR">sumERROR</a>
         that do not match the good-content. </li>
     <li><b>ERR_names:</b> Error:name-list of entities that are counted in any ERR_&lt;reading&gt;
         W_sum_&lt;reading&gt;: count of readings as defined in attribut
         <a href="#HMinfo-attr-sumStatus">sumStatus</a>. </li>
     Example:<br>

     <ul><code>
       ERR___rssiCrit LightKittchen,WindowDoor,Remote12<br>
       ERR__protocol NACK:2 ResendFail:5 CmdDel:2 CmdPend:1<br>
       ERR__protoNames LightKittchen,WindowDoor,Remote12,Ligth1,Light5<br>
       ERR_battery: low:2;<br>
       ERR_names: remote1,buttonClara,<br>
       I_rssiMinLevel 99&gt;:3 80&lt;:0 60&lt;:7 59&lt;:4<br>
       W_sum_battery: ok:5;low:2;<br>
       W_sum_overheat: off:7;<br>
       C_sumDefined: entities:23 device:11 channel:16 virtual:5;<br>
     </code></ul>
   </ul>
</ul>
=end html


=begin html_DE

<a id="HMinfo"></a>
<h3>HMinfo</h3>
<ul>

  Das Modul HMinfo erm&ouml;glicht einen &Uuml;berblick &uuml;ber eQ-3 HomeMatic Ger&auml;te, die mittels <a href="#CUL_HM">CUL_HM</a> definiert sind.<br><br>
  <B>Status Informationen und Z&auml;hler</B><br>
  HMinfo gibt einen &Uuml;berlick &uuml;ber CUL_HM Installationen einschliesslich aktueller Zust&auml;nde.
  Readings und Z&auml;hler werden aus Performance Gr&uuml;nden nicht automatisch aktualisiert. <br>
  Mit dem Kommando <a href="#HMinfo-set-update">update</a> k&ouml;nnen die Werte aktualisiert werden.
  <ul><code><br>
           set hm update<br>
  </code></ul><br>
  Die Webansicht von HMinfo stellt Details &uuml;ber CUL_HM Instanzen mit ungew&ouml;hnlichen Zust&auml;nden zur Verf&uuml;gung. Dazu geh&ouml;ren:
  <ul>
      <li>Action Detector Status</li>
      <li>CUL_HM Ger&auml;te und Zust&auml;nde</li>
      <li>Ereignisse im Zusammenhang mit Kommunikationsproblemen</li>
      <li>Z&auml;hler f&uuml;r bestimmte Readings und Zust&auml;nde (z.B. battery) - <a href="#HMinfo-attr">attribut controlled</a></li>
      <li>Z&auml;hler f&uuml;r Readings, die auf Fehler hindeuten (z.B. overheat, motorErr) - <a href="#HMinfo-attr">attribut controlled</a></li>
  </ul>
  <br>

  Weiterhin stehen HM Kommandos zur Verf&uuml;gung, z.B. f&uuml;r das Speichern aller gesammelten Registerwerte.<br><br>

  Ein Kommando wird f&uuml;r alle HM Instanzen der kompletten Installation ausgef&uuml;hrt.
  Die Ausf&uuml;hrung ist jedoch auf die dazugeh&ouml;rigen Instanzen beschr&auml;nkt.
  So wird rssi nur auf Ger&auml;te angewendet, da Kan&auml;le RSSI Werte nicht unterst&uuml;tzen.<br><br>
  <a id="HMinfo-Filter"><b>Filter</b></a>
  <ul> werden wie folgt angewendet:<br><br>
        <code>set &lt;name&gt; &lt;cmd&gt; &lt;filter&gt; [&lt;param&gt;]</code><br>
        wobei sich filter aus Typ und Name zusammensetzt<br>
        [-dcasev] [-f &lt;filter&gt;]<br><br>
        <b>Typ</b> <br>
        <ul>
            <li>d - device   :verwende Ger&auml;t</li>
            <li>c - channels :verwende Kanal</li>
            <li>v - virtual  :unterdr&uuml;cke virtuelle Instanz</li>
            <li>p - physical :unterdr&uuml;cke physikalische Instanz</li>
            <li>a - aktor    :unterdr&uuml;cke Aktor</li>
            <li>s - sensor   :unterdr&uuml;cke Sensor</li>
            <li>e - empty    :verwendet das Resultat auch wenn die Felder leer sind</li>
            <li>2 - alias    :2ter name alias anzeigen</li>
        </ul>
        und/oder <b>Name</b>:<br>
        <ul>
            <li>-f &lt;filter&gt;  :Regul&auml;rer Ausdruck (regexp), um die Instanznamen zu filtern</li>
        </ul>
        Beispiel:<br>
        <ul><code>
           set hm param -d -f dim state # Zeige den Parameter 'state' von allen Ger&auml;ten, die "dim" im Namen enthalten<br>
           set hm param -c -f ^dimUG$ peerList # Zeige den Parameter 'peerList' f&uuml;r alle Kan&auml;le mit dem Namen "dimUG"<br>
           set hm param -dcv expert # Ermittle das Attribut expert f&uuml;r alle Ger&auml;te, Kan&auml;le und virtuelle Instanzen<br>
        </code></ul>
  </ul>
  <br>
  <a id="HMinfo-define"><b>Define</b></a>
  <ul>
    <code>define &lt;name&gt; HMinfo</code><br>
    Es muss nur eine Instanz ohne jegliche Parameter definiert werden.<br>
  </ul>
  <br>
  <a id="HMinfo-get"></a><h4>Get</h4>
  <ul>
      <li><a id="HMinfo-get-models"></a>models<br>
          zeige alle HM Modelle an, die von FHEM unterst&uuml;tzt werden
      </li>
      <li><a id="HMinfo-get-param"></a>param <a href="#HMinfo-Filter">[filter]</a> &lt;name&gt; &lt;name&gt;...<br>
          zeigt Parameterwerte (Attribute, Readings, ...) f&uuml;r alle Instanzen in Tabellenform an 
      </li>
      <li><a id="HMinfo-get-register"></a>register <a href="#HMinfo-Filter">[filter]</a><br>
          zeigt eine Tabelle mit Registern einer Instanz an
      </li>
      <li><a id="HMinfo-get-regCheck"></a>regCheck <a href="#HMinfo-Filter">[filter]</a><br>
          validiert Registerwerte
      </li>
      <li><a id="HMinfo-get-peerCheck"></a>peerCheck <a href="#HMinfo-Filter">[filter]</a><br>
          validiert die Einstellungen der Paarungen (Peers). Hat ein Kanal einen Peer gesetzt, muss dieser auch auf
          der Gegenseite gesetzt sein.
      </li>
      <li><a id="HMinfo-get-peerUsg"></a>peerUsg <a href="#HMinfo-Filter">[filter]</a><br>
          erzeugt eine komplette Querverweisliste aller Paarungen und die Nutzung der Templates
      </li>
      <li><a id="HMinfo-get-peerXref"></a>peerXref <a href="#HMinfo-Filter">[filter]</a><br>
          erzeugt eine komplette Querverweisliste aller Paarungen (Peerings)
      </li>
      <li><a id="HMinfo-get-configCheck"></a>configCheck <a href="#HMinfo-Filter">[filter]</a><br>
          Plausibilit&auml;tstest aller HM Einstellungen inklusive regCheck und peerCheck
      </li>
      <li><a id="HMinfo-get-configChkResult"></a>configChkResult<br>
          gibt das Ergebnis eines vorher ausgeführten configCheck zurück
      </li>
      <li><a id="HMinfo-get-templateList"></a>templateList [&lt;name&gt;]<br>
          zeigt eine Liste von Vorlagen. Ist kein Name angegeben, werden alle Vorlagen angezeigt<br>
      </li>
      <li><a id="HMinfo-get-configInfo"></a>configInfo [&lt;name&gt;]<br>
          Informationen zu getConfig einträgen<br>
      </li>
      <li><a id="HMinfo-get-templateUsg" data-pattern="templateUsg.*"></a>templateUsg &lt;template&gt; [sortPeer|sortTemplate]<br>
          template filtert die Einträge nach diesem template<br>
          <i>templateUsgG</i> (für alle Geräte)
      </li>
      <li><a id="HMinfo-get-msgStat"></a>msgStat <a href="#HMinfo-Filter">[filter]</a><br>
          zeigt eine Statistik aller Meldungen der letzen Woche<br>
      </li>
      <li><a id="HMinfo-get-protoEvents"></a>protoEvents <a href="#HMinfo-Filter">[filter]</a> <br>
          vermutlich die <B>wichtigste Auflistung</B> f&uuml;r Meldungsprobleme.
          Informationen &uuml;ber ausstehende Kommandos und fehlgeschlagene Sendevorg&auml;nge
          f&uuml;r alle Ger&auml;te in Tabellenform.<br>
          Mit <a name="#HMinfoclear">clear msgEvents</a> kann die Statistik gel&ouml;scht werden.<br>
      </li>
      <li><a id="HMinfo-get-rssi" data-pattern="rssi.*"></a>rssi <a href="#HMinfo-Filter">[filter]</a><br>
          Statistik &uuml;ber die RSSI Werte aller HM Instanzen.<br>
      </li>

      <li><a id="HMinfo-get-templateChk"></a>templateChk <a href="#HMinfo-Filter">[filter]</a> &lt;template&gt; &lt;peer:[long|short]&gt; [&lt;param1&gt; ...]<br>
         Verifiziert, ob die Registerwerte mit der Vorlage in Einklang stehen.<br>
         Die Parameter sind identisch mit denen aus <a href="#HMinfo-set-templateSet">templateSet</a>.<br>
         Wenn kein Peer ben&ouml;tigt wird, stattdessen none verwenden.
         Beispiele f&uuml;r die &Uuml;berpr&uuml;fung von Einstellungen<br>
        <ul><code>
         set hm templateChk -f RolloNord BlStopUpLg none         1 2 # RolloNord, no peer, parameter 1 and 2 given<br>
         set hm templateChk -f RolloNord BlStopUpLg peerName:long    # RolloNord peerName, long only<br>
         set hm templateChk -f RolloNord BlStopUpLg peerName         # RolloNord peerName, long and short<br>
         set hm templateChk -f RolloNord BlStopUpLg peerName:all     # RolloNord peerName, long and short<br>
         set hm templateChk -f RolloNord BlStopUpLg all:long         # RolloNord any peer, long only<br>
         set hm templateChk -f RolloNord BlStopUpLg all              # RolloNord any peer,long and short<br>
         set hm templateChk -f Rollo.*   BlStopUpLg all              # each Rollo* any peer,long and short<br>
         set hm templateChk BlStopUpLg                               # each entities<br>
         set hm templateChk                                          # all assigned templates<br>
         set hm templateChk sortTemplate                             # all assigned templates, sort by template<br>
         set hm templateChk sortPeer                                 # all assigned templates, sort by peer<br>
        </code></ul>
      </li>
      <li><a id="HMinfo-get-showTimer"></a>showTimer <br>
          Zeigt alle derzeit laufenden Timer an.<br>
      </li>
  </ul>
  <a id="HMinfo-set"></a><h4>Set</h4>
  <ul>
  Obwohl die Kommandos Einstellungen abrufen (get function), werden sie mittels set ausgef&uuml;hrt, um die 
  Benutzung mittels Web Interface zu erleichtern.<br>
    <ul>
      <li><a id="HMinfo-set-update"></a>update<br>
          Aktualisiert HM Status Z&auml;hler.
      </li>
      <li><a id="HMinfo-set-autoReadReg"></a>autoReadReg <a href="#HMinfo-Filter">[filter]</a><br>
          Aktiviert das automatische Lesen der Konfiguration f&uuml;r ein CUL_HM Ger&auml;t, wenn das Attribut autoReadReg auf 1 oder h&ouml;her steht.
      </li>
      <li><a id="HMinfo-set-cmdRequestG"></a>cmdRequestG <br>
          commando cmdRequestG wird an alle Entites verschickt um einen update zu erzwingen und die Zugriffe zu prüfen.<br>
          Das Kommando geht nur an Entites, welche auch statusRequest unterstützen. <br>
          ping: es wird an einen der kanäle ein status request verschickt<br>
          status: jede entity welche das kommando unterstützt wird angesprochen<br>
      </li>
      <li><a id="HMinfo-set-clear" data-pattern="clear.*"></a>clear <a href="#HMinfo-Filter">[filter]</a> [msgEvents|readings|msgStat|register|rssi]<br>
          F&uuml;hrt ein set clear ... f&uuml;r alle HM Instanzen aus<br>
          <ul>
          <li>Protocol bezieht sich auf set clear msgEvents</li>
          <li>Protocol set clear msgEvents fuer alle devices mit protokoll Fehlern</li>
          <li>readings bezieht sich auf set clear readings</li>
          <li>rssi l&ouml;scht alle rssi Z&auml;hler</li>
          <li>msgStat l&ouml;scht die HM Meldungsstatistik</li>
          <li>register l&ouml;scht alle Eintr&auml;ge in den Readings</li>
          </ul>
      </li>
      <li><a id="HMinfo-set-saveConfig"></a>saveConfig <a href="#HMinfo-Filter">[filter] [&lt;file&gt;]</a><br>
          Sichert alle HM Registerwerte und Peers. Siehe <a href="#CUL_HM-get-saveConfig">CUL_HM saveConfig</a>.<br>
          <a href="#HMinfo-set-purgeConfig">purgeConfig</a> wird automatisch ausgef&uuml;hrt, wenn die Datenmenge 1 MByte &uuml;bersteigt.<br>
      </li>
      <li><a id="HMinfo-set-archConfig"></a>archConfig <a href="#HMinfo-Filter">[filter]</a> [&lt;file&gt;]<br>
          F&uuml;hrt <a href="#HMinfo-set-saveConfig">saveConfig</a> f&uuml;r alle Instanzen aus, sobald sich deren Konfiguration &auml;ndert.
          Es schont gegen&uuml;ber saveConfig die Resourcen, da es nur vollst&auml;ndige Konfigurationen sichert.<br>
          Die Option -a erzwingt das sofortige Archivieren f&uuml;r alle Ger&auml;te, die eine vollst&auml;ndige Konfiguration aufweisen.<br>
      </li>
      <li><a id="HMinfo-set-loadConfig"></a>loadConfig <a href="#HMinfo-Filter">[filter]</a> [&lt;file&gt;]<br>
          L&auml;dt Register und Peers aus einer zuvor mit <a href="#HMinfo-set-saveConfig">saveConfig</a> gesicherten Datei.<br>
          Es sollte mit Vorsicht verwendet werden, da es Daten zu FHEM hinzuf&uuml;gt, die nicht verifiziert sind.
          Readings werden nicht ersetzt, nur fehlende Readings werden hinzugef&uuml;gt. Der Befehl ist dazu geignet, um Readings
          zu erstellen, die schwer zu erhalten sind. Readings von Ger&auml;ten, die nicht dauerhaft empfangen sondern nur auf Tastendruck
          aufwachen (z.B. T&uuml;rsensoren), k&ouml;nnen nicht ohne Weiteres gelesen werden.<br>
          Daher liegt es in der Verantwortung des Benutzers g&uuml;ltige Werte zu verwenden. Es sollte autoReadReg f&uuml;r Ger&auml;te verwendet werden,
          die einfach ausgelesen werden k&ouml;nnen.<br>
          Der Befehl aktualisiert lediglich FHEM Readings und Attribute. Die Programmierung des Ger&auml;tes wird <B>nicht</B> ver&auml;ndert.
      </li>
      <li><a id="HMinfo-set-purgeConfig"></a>purgeConfig <a href="#HMinfo-Filter">[filter]</a> [&lt;file&gt;]<br>
          Bereinigt die gespeicherte Konfigurationsdatei. Durch die kumulative Speicherung der Registerwerte bleiben die
          zuletzt gespeicherten Werte erhalten und alle &auml;lteren werden gel&ouml;scht.
          Siehe <a href="#CUL_HM-get-saveConfig">CUL_HM saveConfig</a>.
      </li>
      <li><a id="HMinfo-set-verifyConfig"></a>verifyConfig <a href="#HMinfo-Filter">[filter]</a> [&lt;file&gt;]<br>
          Vergleicht die aktuellen Daten mit dem configFile und zeigt Unterschiede auf. 
          Es ist hilfreich wenn man eine bekannt gute Konfiguration gespeichert hat und gegen diese vergleichen will.
          Ein purge vorher macht Sinn. 
          Siehe <a href="#CUL_HM-set-purgeConfig">CUL_HM purgeConfig</a>.
      </li>
      <br>
      
      <li><a id="HMinfo-set-tempList" data-pattern="tempList.*"></a>tempList <a href="#HMinfo-Filter">[filter]</a> [save|restore|verify|status|genPlot] [&lt;file&gt;]<br>
          Diese Funktion erm&ouml;glicht die Verarbeitung von tempor&auml;ren Temperaturlisten f&uuml;r Thermostate.
          Die Listen k&ouml;nnen in Dateien abgelegt, mit den aktuellen Werten verglichen und an das Ger&auml;t gesendet werden.<br>
          <li><B>save</B> speichert die aktuellen tempList Werte des Systems in eine Datei. <br>
              Zu beachten ist, dass die aktuell in FHEM vorhandenen Werte benutzt werden. Der Benutzer muss selbst sicher stellen,
              dass diese mit den Werten im Ger&auml;t &uuml;berein stimmen.<br>
              Der Befehl arbeitet nicht kummulativ. Alle evtl. vorher in der Datei vorhandenen Werte werden &uuml;berschrieben.</li>
          <li><B>restore</B> in der Datei gespeicherte Termperaturliste wird direkt an das Ger&auml;t gesendet.</li>
          <li><B>verify</B> vergleicht die Temperaturliste in der Datei mit den aktuellen Werten in FHEM. Der Benutzer muss 
              selbst sicher stellen, dass diese mit den Werten im Ger&auml;t &uuml;berein stimmen.</li>
          <li><B>status</B> gibt einen Ueberblick aller genutzten template files. Ferner werden vorhandene templates in den files gelistst.
            <br></li>
          <li><B>genPlot</B> erzeugt einen Satz Daten um temp-templates graphisch darzustellen<br>
            Aus den gegebenen template-file wird ein .log erweitertes file erzeugt welches log-formatierte daten beinhaltet. 
            Zeitmarken sind auf Beginn 2000 terminiert.<br>
            Ein .gplot file wird in der gplt directory erzeugt.<br>
            Eine Logfile-entity <file>_Log, falls nicht vorhanden, wird erzeugt.<br>
            Eine SVG-entity <file>_SVG, falls nicht vorhanden, wird erzeugt.<br>
            </li>
          <br>
          <li><B>filename</B> Name der Datei. Vorgabe ist <B>tempList.cfg</B></li>
          Beispiel f&uuml;r einen Dateiinhalt:<br>
          <ul><code>
               entities:HK1_Climate,HK2_Clima<br>
               tempListFri>07:00 14.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0<br>
               tempListMon>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0<br>
               tempListSat>08:00 14.0 15:00 18.0 21:30 19.0 24:00 14.0<br>
               tempListSun>08:00 14.0 15:00 18.0 21:30 19.0 24:00 14.0<br>
               tempListThu>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0<br>
               tempListTue>07:00 14.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 15.0<br>
               tempListWed>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0<br>
               entities:hk3_Climate<br>
               tempListFri>06:00 17.0 12:00 21.0 23:00 20.0 24:00 19.5<br>
               tempListMon>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
               tempListSat>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
               tempListSun>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
               tempListThu>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
               tempListTue>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
               tempListWed>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
         </code></ul>
         Datei Schl&uuml;sselw&ouml;rter<br>
         <li><B>entities</B> mittels Komma getrennte Liste der Instanzen f&uuml;r die die nachfolgende Liste bestimmt ist.
         Es muss die tats&auml;chlich f&uuml;r die Temperaturliste zust&auml;ndige Instanz angegeben werden. Bei RTs ist das der Kanal 04,
         bei TCs der Kanal 02.</li>
         <li><B>tempList...</B> Zeiten und Temperaturen sind genau wie im Befehl "set tempList" anzugeben</li>
         <br>
     </li>
         <br>
      <li><a id="HMinfo-set-cpRegs"></a>cpRegs &lt;src:peer&gt; &lt;dst:peer&gt; <br>
          erm&ouml;glicht das Kopieren von Registern, Einstellungen und Verhalten zwischen gleichen Kan&auml;len, bei einem Peer auch
          zwischen unterschiedlichen Kan&auml;len. Das Kopieren kann daher sowohl von Ger&auml;t zu Ger&auml;t, als auch innerhalb eines
          Ger&auml;tes stattfinden.<br>
         <b>src:peer</b> ist die Quell-Instanz. Der Peer muss angegeben werden, wenn dessen Verhalten kopiert werden soll.<br>
         <b>dst:peer</b> ist die Ziel-Instanz.<br>
         Beispiel:<br>
         <ul><code>
          set hm cpRegs blindR blindL  # kopiert alle Register (list 1) des Kanals von blindR nach blindL einschliesslich z.B. der
          Rolladen Fahrzeiten. Register, die den Peer betreffen (list 3/4), werden nicht kopiert.<br>
          set hm cpRegs blindR:Btn1 blindL:Btn2  # kopiert das Verhalten der Beziehung Btn1/blindR nach Btn2/blindL<br>
          set hm cpRegs blindR:Btn1 blindR:Btn2  # kopiert das Verhalten der Beziehung Btn1/blindR nach Btn2/blindR, hier
          innerhalb des Aktors<br>
         </code></ul>
         <br>
         Einschr&auml;nkungen:<br>
         <ul>
         cpRegs <u>ver&auml;ndert keine Peerings</u> oder liest direkt aus den Ger&auml;ten. Die Readings m&uuml;ssen daher aktuell sein.<br>
         cpRegs kann nur auf <u>identische Ger&auml;temodelle</u> angewendet werden<br>
         cpRegs erwartet <u>aktuelle Readings</u>. Dies muss der Benutzer sicher stellen.<br>
         </ul>
      </li>
      <li><a id="HMinfo-set-templateDef"></a>templateDef &lt;name&gt; &lt;param&gt; &lt;desc&gt; &lt;reg1:val1&gt; [&lt;reg2:val2&gt;] ...<br>
          definiert eine Vorlage.<br>
          <b>param</b> definiert die Namen der Parameters, die erforderlich sind, um die Vorlage auszuf&uuml;hren.
                       Diese sind abh&auml;ngig von der Vorlage und k&ouml;nnen onTime oder brightnesslevel sein.
                       Bei einer Liste mehrerer Parameter m&uuml;ssen diese mittels Kommata separiert werden.<br>
                       param1:param2:param3<br>
                       Der Parameter del f&uuml;hrt zur L&ouml;schung der Vorlage.<br>
          <b>desc</b> eine Beschreibung f&uuml;r die Vorlage<br>
          <b>reg:val</b> der Name des Registers und der dazugeh&ouml;rige Zielwert.<br>
          Wenn das Register zwischen long und short unterscheidet, muss das f&uuml;hrende sh oder lg weggelassen werden.<br>
          Parameter m&uuml;ssen mit p angegeben werden, p0 f&uuml;r den ersten, p1 f&uuml;r den zweiten usw.
        <br>
        Beispiel<br>
        <ul><code>
          set hm templateDef SwOnCond level:cond "my description" CtValLo:p0 CtDlyOn:p1 CtOn:geLo<br>
          set hm templateDef SwOnCond del # lösche template SwOnCond<br>
          set hm templateDef SwOnCond fromMaster &lt;masterChannel&gt; &lt;peer:[long|short]&gt;# masterKanal mit peer wird als Vorlage genommen<br>
          set hm templateDef SwOnCond fromMaster myChannel peerChannel:long  <br>
        </code></ul>
      </li>
      <li><a id="HMinfo-set-templateSet"></a>templateSet &lt;entity&gt; &lt;template&gt; &lt;peer:[long|short]&gt; [&lt;param1&gt; ...]<br>
          setzt mehrere Register entsprechend der angegebenen Vorlage. Die Parameter m&uuml;ssen entsprechend der Vorlage angegeben werden.<br>
          templateSet akkumuliert alle &Auml;nderungen und schreibt das Ergebnis gesammelt.<br>
         <b>entity:</b> ist die Quell-Instanz. Der Peer muss angegeben werden, wenn dessen Verhalten kopiert werden soll.<br>
         <b>template:</b> eine der vorhandenen Vorlagen<br>
         <b>peer:</b> [long|short]:falls erforderlich muss der Peer angegeben werden. Wird kein Peer ben&ouml;tigt, '0' verwenden.
                  Bei einem Peer muss f&uuml;r den Tastendruck long oder short angegeben werden.<br>
         <b>param:</b> Nummer und Bedeutung des Parameters h&auml;ngt von der Vorlage ab.<br>
         Ein Beispiel k&ouml;nnte sein (theoretisch, ohne die Vorlage anzugeben)<br>
        <ul><code>
         set hm templateSet Licht1 staircase FB1:short 20  <br>
         set hm templateSet Licht1 staircase FB1:long 100  <br>
        </code></ul>
        Einschr&auml;nkungen:<br>
        <ul>
         Der Benutzer muss aktuelle Register/Konfigurationen sicher stellen.<br>
         templateSet konfiguriert ggf. nur einzelne Register und keinen vollst&auml;ndigen Satz. Dies h&auml;ngt vom Design der Vorlage ab.<br>
         <br>
        </ul>
      </li>
      <li><a id="HMinfo-set-templateDel"></a>templateDel &lt;entity&gt; &lt;template&gt; &lt;peer:[long|short]&gt; ]<br>
          entfernt ein Template das mit templateSet eingetragen wurde
      </li>
      <li><a id="HMinfo-set-templateExe"></a>templateExe &lt;template&gt; <br>
          führt das templateSet erneut aus. Die Register werden nochmals geschrieben, falls sie nicht zum template passen. <br>
      </li>
      <li><a id="#HMinfo-set-deviceReplace">x-deviceReplace</a> &lt;oldDevice&gt; &lt;newDevice&gt; <br>
          Ersetzen eines alten oder defekten Device. Das neue Ersatzdevice muss kompatibel zum Alten sein - FHEM prüft das nur rudimentär. Der Anwender sollt es sorgsam prüfen.<br>
          Das Kommando muss aus Sicherheitsgründen 2-fach ausgeführt werden. Der erste Aufruf wird mit einem CAUTION quittiert. Nach Auslösen den Kommandos ein 2. mal werden die Devices umbenannt und umkonfiguriert. Er werden alle peerings, Register und Templates im neuen Device UND allen peers umgestellt.<br>
          ACHTUNG: Nach dem Auslösen kann die Änderung nicht mehr automatisch rückgängig gemacht werden. Manuell ist das natürlich möglich.<br> 
          Auch ein ückspring auf eine ältere Konfiguration erlaubt KEIN Rückgängigmachen!!!<br>          
          Sollte das Device und seine Kanäle über Templates definiert sein  - also die Registerlisten - kann im Falle von Problemen in der Übertragung - problemlos wieder hergestellt werden. <br>
      </li>

    </ul>
  </ul>
  <br>


  <a id="HMinfo-attr"></a><h4>Attribute</h4>
   <ul>
    <a id="HMinfo-attr-sumStatus"></a>
    <li>sumStatus<br>
        erzeugt eine Liste von Warnungen. Die zu untersuchenden Readings werden mittels Komma separiert angegeben.
        Die Readings werden, so vorhanden, von allen Instanzen ausgewertet, gez&auml;hlt und getrennt nach Readings mit
        gleichem Inhalt ausgegeben.<br>
        Beispiel:<br>
        <ul><code>
           attr hm sumStatus battery,sabotageError<br>
        </code></ul>
        k&ouml;nnte nachfolgende Ausgaben erzeugen<br>
        W_sum_battery ok:5 low:3<br>
        W_sum_sabotageError on:1<br>
        <br>
        Anmerkung: Z&auml;hler mit Werten von '0' werden nicht angezeigt. HMinfo findet alle vorhanden Werte selbstst&auml;ndig.<br>
        Das Setzen des Attributes erm&ouml;glicht einen schnellen &Uuml;berblick &uuml;ber systemkritische Werte.<br>
    </li>
    <a id="HMinfo-attr-sumERROR"></a>
     <li>sumERROR<br>
        &Auml;hnlich sumStatus, jedoch mit dem Fokus auf signifikante Fehler.
        Hier k&ouml;nnen Reading <b>Werte</b> angegeben werden, die dazu f&uuml;hren, dass diese <b>nicht angezeigt</b> werden.
        Damit kann beispielsweise verhindert werden, dass der zu erwartende Normalwert oder ein anderer nicht
        kritischer Wert angezeigt wird.<br>
        Beispiel:<br>
        <ul><code>
           attr hm sumERROR battery:ok,sabotageError:off,overheat:off,Activity:alive:unknown<br>
        </code></ul>
        erzeugt folgende Ausgabe:<br>
        <ul><code>
        ERR_battery low:3<br>
        ERR_sabotageError on:1<br>
        ERR_overheat on:3<br>
        ERR_Activity dead:5<br>
        </code></ul>
    </li>
    <a id="HMinfo-attr-autoUpdate"></a>
     <li>autoUpdate<br>
        f&uuml;hrt den Befehl periodisch aus.<br>
        Beispiel:<br>
        <ul><code>
           attr hm autoUpdate 00:10<br>
        </code></ul>
        f&uuml;hrt den Befehl alle 10 Minuten aus<br>
    </li>
     <a id="HMinfo-attr-autoArchive"></a>
     <li>autoArchive<br>
        Sobald neue Daten verf&uuml;gbar sind, wird das configFile aktualisiert.
        F&uuml;r die Aktualisierung ist <a href="#HMinfo-attr-autoUpdate">autoUpdate</a> zwingend erforderlich.<br>
        siehe auch <a href="#HMinfo-attr-archConfig">archConfig</a>
        <br>
     </li>
     <a id="HMinfo-attr-hmAutoReadScan"></a>
     <li>hmAutoReadScan<br>
        definiert die Zeit in Sekunden bis zum n&auml;chsten autoRead durch CUL_HM. Trotz dieses Zeitwertes stellt
        FHEM sicher, dass zu einem Zeitpunkt immer nur ein Ger&auml;t gelesen wird, auch wenn der Minimalwert von 1
        Sekunde eingestellt ist. Mit dem Timer kann der Zeitabstand
        ausgeweitet werden - bis zu 300 Sekunden zwischen zwei Ausf&uuml;hrungen.<br>
        Das Herabsetzen erh&ouml;ht die Funkbelastung, Heraufsetzen erh&ouml;ht die Wartzezeit.<br>
     </li>
     <a id="HMinfo-attr-hmIoMaxDly"></a>
     <li>hmIoMaxDly<br>
        maximale Zeit in Sekunden f&uuml;r die CUL_HM Meldungen puffert, wenn das Ger&auml;t nicht sendebereit ist.
        Ist das Ger&auml;t nicht wieder rechtzeitig sendebereit, werden die gepufferten Meldungen verworfen und
        IOErr ausgel&ouml;st.<br>
        Hinweis: Durch die Pufferung kann es vorkommen, dass Aktivit&auml;t lange nach dem Absetzen des Befehls stattfindet.<br>
        Standard ist 60 Sekunden, maximaler Wert ist 3600 Sekunden.<br>
     </li>
     <a id="HMinfo-attr-configDir"></a>
     <li>configDir<br>
        Verzeichnis f&uuml;r das Speichern und Lesen der Konfigurationsdateien, sofern in einem Befehl nur ein Dateiname ohne
        Pfad angegen wurde.<br>
        Verwendung beispielsweise bei <a href="#HMinfo-set-tempList">tempList</a> oder <a href="#HMinfo-set-saveConfig">saveConfig</a><br>
     </li>
     <a id="HMinfo-attr-configFilename"></a>
     <li>configFilename<br>
        Standard Dateiname zur Verwendung von 
        <a href="#HMinfo-set-saveConfig">saveConfig</a>, 
       <a href="#HMinfo-set-purgeConfig">purgeConfig</a>, 
       <a href="#HMinfo-set-loadConfig">loadConfig</a><br>
       <a href="#HMinfo-set-verifyConfig">verifyConfig</a><br>
     </li>
     <a id="HMinfo-attr-configTempFile"></a>
     <li>configTempFile&lt;;configTempFile2&gt;&lt;;configTempFile3&gt; </a>
        Liste der Templfiles (weekplan) welche in HM berücksichtigt werden<br>
        Die Files werden kommasepariert eingegeben. Das erste File ist der Default. Dessen Name muss beim Template nicht eingegeben werden.<br>
     </li>
     <a id="HMinfo-attr-hmManualOper"></a>
     <li>hmManualOper<br>
        auf 1 gesetzt, verhindert dieses Attribut jede automatische Aktion oder Aktualisierung seitens CUL_HM.<br>
     </li>
     <a id="HMinfo-attr-hmDefaults"></a>
     <li>hmDefaults<br>
       setzt default Atribute fuer HM devices. Mehrere Attribute sind moeglich, Komma separiert.<br>
       Beispiel:<br>
       attr hm hmDefaults hmProtocolEvents:0_off,rssiLog:0<br>
     </li>
     <a id="HMinfo-attr-verbCULHM"></a>
     <li>verbCULHM<br>
       Setzt das verbose logging für ausgewählte Aktionen von allen CUL_HM entities.<br>
       allSet: alle set Kommandos fertig zur Ausführung.<br>
       allGet: alle get Anfragen fertig zur Ausführung.<br>
     </li>
     <a id="HMinfo-attr-autoLoadArchive"></a>
     <li>autoLoadArchive<br>
       das Register Archive sowie Templates werden nach reboot automatisch geladen.
       Siehe <a href="#HMinfo-set-loadConfig">loadConfig</a> für Details.<br>
     </li>

   </ul>
   <br>
  <a id="HMinfo-variables"><b>Variablen</b></a>
   <ul>
    <li><b>I_autoReadPend:</b> Info: Liste der Instanzen, f&uuml;r die das Lesen von Konfiguration und Status ansteht,
                                     &uuml;blicherweise ausgel&ouml;st durch autoReadReg.</li>
    <li><b>ERR___rssiCrit:</b> Fehler: Liste der Ger&auml;te mit kritischem RSSI Wert </li>
    <li><b>W_unConfRegs:</b> Warnung: Liste von Instanzen mit unbest&auml;tigten &Auml;nderungen von Registern.
                                      Die Ausf&uuml;hrung von getConfig ist f&uuml;r diese Instanzen erforderlich.</li>
    <li><b>I_rssiMinLevel:</b> Info: Anzahl der niedrigen RSSI Werte je Ger&auml;t, in Bl&ouml;cken angeordnet.</li>

    <li><b>ERR__protocol:</b> Fehler: Anzahl nicht behebbarer Protokollfehler je Ger&auml;t.
        Protokollfehler sind NACK, IOerr, ResendFail, CmdDel, CmdPend.<br>
        Gez&auml;hlt wird die Anzahl der Ger&auml;te mit Fehlern, nicht die Anzahl der Fehler!</li>
    <li><b>ERR__protoNames:</b> Fehler: Liste der Namen der Ger&auml;te mit nicht behebbaren Protokollfehlern</li>
    <li><b>I_HM_IOdevices:</b> Info: Liste der IO Ger&auml;te, die von CUL_HM Instanzen verwendet werden</li>
    <li><b>I_actTotal:</b> Info: Status des Actiondetectors, Z&auml;hler f&uuml;r Ger&auml;te mit bestimmten Status</li>
    <li><b>ERRactNames:</b> Fehler: Namen von Ger&auml;ten, die der Actiondetector als ausgefallen meldet</li>
    <li><b>C_sumDefined:</b> Count: In CUL_HM definierte Instanzen. Instanzen k&ouml;nnen als Ger&auml;t UND
                                    als Kanal gez&auml;hlt werden, falls die Funktion des Kanals durch das Ger&auml;t
                                    selbst abgedeckt ist. &Auml;hnlich virtual</li>
    <li><b>ERR_&lt;reading&gt;:</b> Fehler: Anzahl mittels Attribut <a href="#HMinfo-attr-sumERROR">sumERROR</a>
                                           definierter Readings, die nicht den Normalwert beinhalten. </li>
    <li><b>ERR_names:</b> Fehler: Namen von Instanzen, die in einem ERR_&lt;reading&gt; enthalten sind.</li>
    <li><b>W_sum_&lt;reading&gt;</b> Warnung: Anzahl der mit Attribut <a href="#HMinfo-attr-sumStatus">sumStatus</a> definierten Readings.</li>
    Beispiele:<br>
    <ul>
    <code>
      ERR___rssiCrit LightKittchen,WindowDoor,Remote12<br>
      ERR__protocol NACK:2 ResendFail:5 CmdDel:2 CmdPend:1<br>
      ERR__protoNames LightKittchen,WindowDoor,Remote12,Ligth1,Light5<br>
      ERR_battery: low:2;<br>
      ERR_names: remote1,buttonClara,<br>
      I_rssiMinLevel 99&gt;:3 80&lt;:0 60&lt;:7 59&lt;:4<br>
      W_sum_battery: ok:5;low:2;<br>
      W_sum_overheat: off:7;<br>
      C_sumDefined: entities:23 device:11 channel:16 virtual:5;<br>
    </code>
    </ul>
   </ul>
</ul>
=end html_DE
=cut
