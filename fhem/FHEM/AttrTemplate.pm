##############################################
# $Id$
package main;

# Syntax of the AttrTemplate file:
# - empty lines are ignored
# - lines starting with # are comments (see also desc:)
# - lines starting with the following keywords are special, all others are
#   regular FHEM commands
# - name:<name> name of the template, marks the end of the previous template.
# - filter:<devspec2array-expression>, describing the list of devices this
#   template is applicable for. Well be executed when the set function is
#   executed.
# - prereq:<cond>, where cond is a perl expression, or devspec2array returning
#   exactly one device.  Evaluated at initialization(!).
# - par:<name>:<comment>:<perl>. if there is an additional argument in the set,
#   name in all commands will be replaced with it. Else <perl> will be
#   excuted: if returns a value, name in the commands will be replaced with it,
#   else a dialog will request the user to enter a value for name.
#   For each name starting with RADIO_, a radio select button is offered. Such
#   parameters must defined last.
# - pardefault:<name>:<comment>:<perl>.
#   Same as par, but the dialog is always shown, with the input is prefilled.
# - desc: additional text for the "set attrTemplate help ?". If missing, the
#   last comment before name: will be used for this purpose.
# - farewell:<text> to be shown after the commands are executed.
# - order:<val> sort the templates for help purposes.
# - option:<perl> if perl code return false, skip all commands until next
#   option (or name:)
# - loop:<variable>:1:2:3:...  replicate the commands between this line and
#   loop:END, and replace <variable> in each iteration with the values in the
#   colon separated list


my %templates;
my $initialized;
my %cachedUsage;
use vars qw($FW_addJs);     # Only for helper like AttrTemplate

sub
AttrTemplate_Initialize()
{
  my $me = "AttrTemplate_Initialize";
  my $dir = $attr{global}{modpath}."/FHEM/lib/AttrTemplate";
  if(!opendir(dh, $dir)) {
    Log 1, "$me: cant open $dir: $!";
    return;
  }

  my @files = grep /\.template$/, sort readdir dh;
  closedir(dh);

  %templates = ();
  %cachedUsage = ();
  my %prereqFailed;
  for my $file (@files) {
    if(!open(fh,"$dir/$file")) {
      Log 1, "$me: cant open $dir/$file: $!";
      next;
    }
    my ($name, %h, $lastComment);
    while(my $line = <fh>) {
      chomp($line);
      next if($line =~ m/^$/);

      if($line =~ m/^# *(.*)$/) {       # just a replacement for missing desc
        $lastComment = $1;
        next;

      } elsif($line =~ m/^name:(.*)/) {
        $name = $1;
        my (@p,@c,%t);
        $templates{$name}{ptype} = \%t;
        $templates{$name}{pars} = \@p;
        $templates{$name}{cmds} = \@c;
        $templates{$name}{desc} = $lastComment if($lastComment);
        $lastComment = "";

      } elsif($line =~ m/^filter:(.*)/) {
        $templates{$name}{filter} = $1;

      } elsif($line =~ m/^prereq:(.*)/) {
        my $prereq = $1;
        if($prereq =~ m/^{.*}$/) {
          $prereqFailed{$name} = 1
                if(AnalyzePerlCommand(undef, $prereq) ne "1");

        } else {
          $prereqFailed{$name} = 1
            if(!$defs{devspec2array($prereq)});

        }

      } elsif($line =~ m/^(par|pardefault):(.*)/) {
        push(@{$templates{$name}{pars}}, $2);
        my @v = split(";",$2,2);
        $templates{$name}{ptype}{$v[0]} = $1;

      } elsif($line =~ m/^desc:(.*)/) {
        $templates{$name}{desc} = $1;

      } elsif($line =~ m/^farewell:(.*)/) {
        $templates{$name}{farewell} = $1;

      } elsif($line =~ m/^order:(.*)/) {
        $templates{$name}{order} = $1;

      } else {
        push(@{$templates{$name}{cmds}}, $line);

      }
    }
    close(fh);
  }

  for my $name (keys %prereqFailed) {
    delete($templates{$name});
  }

  @templates = sort {
    my $ao = $templates{$a}{order};
    my $bo = $templates{$b}{order};
    $ao = (defined($ao) ? $ao : $a);
    $bo = (defined($bo) ? $bo : $b);
    return $ao cmp $bo; 
  } keys %templates;

  my $nr = @templates;
  $initialized = 1;
  Log 2, "AttrTemplates: got $nr entries" if($nr);
  $FW_addJs = "" if(!defined($FW_addJs));
  return if($FW_addJs =~ m/attrTemplateHelp/);
  $FW_addJs .= << 'JSEND';
  <script type="text/javascript">
    $(document).ready(function() {
      $("select.set").change(attrAct);
      function
      attrAct(){
        if($("select.set").val() == "attrTemplate") {
          $('<div id="attrTemplateHelp" class="makeTable help"></div>')
                .insertBefore("div.makeTable.internals");
          $("select.select_widget[informid$=attrTemplate]").change(function(){
            var cmd = "{AttrTemplate_Help('"+$(this).val()+"')}";
            FW_cmd(FW_root+"?cmd="+cmd+"&XHR=1", function(ret) {
              $("div#attrTemplateHelp").html(ret);
            });
          });
        } else {
          $("div#attrTemplateHelp").remove();
        }
      }
      attrAct();
    });
  </script>
JSEND
}

sub
AttrTemplate_Help($)
{
  my ($n) = @_;
  return "" if(!$templates{$n});
  my $ret = "";
  $ret = $templates{$n}{desc} if($templates{$n}{desc});
  $ret .= "<br><pre>".join("\n",@{$templates{$n}{cmds}})."</pre>";

  if(AttrVal("global", "showInternalValues", undef)) {
     my @atList = grep /set\s.*\sattrTemplate\s/,@{$templates{$n}{cmds}};
     foreach my $at (@atList) {
       next if($at !~ m/set\s.*\sattrTemplate\s(.*?) /);
       $ret .= "<br><b>attrTemplate $1:</b><br>".AttrTemplate_Help($1);
     }
  }
  return $ret;
}

sub
AttrTemplate_Set($$@)
{
  my ($hash, $list, $name, $cmd, @a) = @_;
  $list = "" if(!defined($list));

  return "Unknown argument $cmd, choose one of $list"
        if(AttrVal("global", "disableFeatures", "") =~ m/\battrTemplate\b/);

  AttrTemplate_Initialize() if(!$initialized);

  my $haveDesc;
  if($cmd ne "attrTemplate") {
    if(!$cachedUsage{$name}) {
      my @list;
      for my $k (@templates) {
        my $h = $templates{$k};
        my $matches;
        $matches = devspec2array($h->{filter}, undef, [$name]) if($h->{filter});
        if(!$h->{filter} || $matches) {
          push @list, $k;
          $haveDesc = 1 if($h->{desc});
        }
      }
      $cachedUsage{$name} = (@list ?
                "attrTemplate:".($haveDesc ? "?,":"").join(",",@list) : "");
    }
    $list .= " " if($list ne "");
    return "Unknown argument $cmd, choose one of $list$cachedUsage{$name}";
  }

  return "Missing template_entry_name parameter for attrTemplate" if(@a < 1);
  my $entry = shift(@a);

  if($entry eq "?") {
    my @hlp;
    for my $k (@templates) {
      my $h = $templates{$k};
      my $matches;
      $matches = devspec2array($h->{filter}, undef, [$name]) if($h->{filter});
      if(!$h->{filter} || $matches) {
        push @hlp, "$k: $h->{desc}" if($h->{desc});
      }
    }
    return "no help available" if(!@hlp);
    if($hash->{CL} && $hash->{CL}{TYPE} eq "FHEMWEB") {
      return "<html><ul><li>".join("</li><br><li>", 
                map { $_=~s/:/<br>/; $_ } @hlp)."</li></ul></html>";
    }
    return join("\n", @hlp);
  }

  if($entry eq "checkPar") {
    my @ret;
    foreach $entry (sort keys %templates) {
      my $h = $templates{$entry};
      for my $k (@{$h->{pars}}) {
        my ($parname, $comment, $perl_code) = split(";",$k,3);
        nex if(!$perl_code);
        $perl_code =~ s/(?<!\\)DEVICE/bla/g;
        $perl_code =~ s/\\DEVICE/DEVICE/g;
        $cmdFromAnalyze = $perl_code;
        my $ret = eval $perl_code;
        push @ret,"$entry:$parname:$@" if($@);
      }
    }
    return "No errors found" if (!@ret);
    return join("\n", @ret);
  }

  my $h = $templates{$entry};
  return "Unknown template_entry_name $entry" if(!$h);

  my (@na, %repl, @mComm, @mList, $missing);
  for(my $i1=0; $i1<@a; $i1++) { # parse parname=value form the command line
    my $fnd;
    for my $k (@{$h->{pars}}) {
      my ($parname, $comment, $perl_code) = split(";",$k,3);
      if($a[$i1] =~ m/$parname=(.*)/) {
        $repl{$parname} = $1;
        return "Empty parameters are not allowed" if($1 eq "");
        $fnd=1;
        last;
      }
    }
    push(@na,$a[$i1]) if(!$fnd);
  }
  @a = @na;

  for my $k (@{$h->{pars}}) {
    my ($parname, $comment, $perl_code) = split(";",$k,3);

    next if(defined($repl{$parname}));

    if(@a) { # old-style, without prefix
      $repl{$parname} = $a[0];
      shift(@a);
      next;
    }

    if($perl_code) {
      $perl_code =~ s/(?<!\\)DEVICE/$name/g;
      $perl_code =~ s/\\DEVICE/DEVICE/g;
      my $ret = eval $perl_code;
      return "ERROR executing perl-code $perl_code for param $parname: $@ "
                if($@);
      if(defined($ret)) {
        $repl{$parname} = $ret;
        next if($h->{ptype}{$parname} ne "pardefault");
      }
    }

    push(@mList, "$parname=...");
    push(@mComm, "$parname= with $comment");
    $missing = 1;
  }

  if($missing) {
    if($hash->{CL} && $hash->{CL}{TYPE} eq "FHEMWEB") {
      return
      "<html>".
         "<input type='hidden' value='set $name attrTemplate $entry'>".
         "<p>Need the following parameters for the attrTemplate $entry</p><br>".
         "<table class='block wide'><tr>".
         join("</tr><tr>", map { 
           my @t=split("= with ",$_,2);
           my $v=defined($repl{$t[0]}) ? $repl{$t[0]} : "";
           "<td>$t[1]</td><td>" .($t[0] =~ m/^RADIO_/ ?
             "<input type='radio' name='$name.s' value='$t[0]'>":
             "<input type='text' name='$t[0]' size='20' value='$v'></td>")
         } @mComm)."</tr></table>".
        '<script>
          setTimeout(function(){
            $("#FW_okDialog input[type=radio]").first().prop("checked",true);
            $("#FW_okDialog").parent().find("button").css("display","block");
            $("#FW_okDialog").parent().find(".ui-dialog-buttonpane button")
            .unbind("click").click(function(){
              var cmd = "";
              $("#FW_okDialog input").each(function(){
                var t=$(this).attr("type");
                if(t=="hidden")cmd +=";"+$(this).val();
                if(t=="text")  cmd +=" "+$(this).attr("name")+"="+$(this).val();
                if(t=="radio") cmd +=" "+$(this).val()+"="+
                                          ($(this).prop("checked") ? 1:0);
              });
              FW_cmd(FW_root+"?cmd="+encodeURIComponent(cmd)+"&XHR=1",
              function(resp){
                if(resp) {
                  if(!resp.match(/^<html>[\s\S]*<\/html>/))
                    resp = "<pre>"+resp+"</pre>";
                  return FW_okDialog(resp);
                }
                location.reload()
              });
              $("#FW_okDialog").remove();
            })}, 100);
         </script>
       </html>';

    } else {
      return "Usage: set $name attrTemplate $entry @mList\n".
             "Replace the ... after\n".join("\n", @mComm);

    }
  }

  # Loop unrolling
  my @cmds;
  for(my $i1 = 0; $i1 < @{$h->{cmds}}; $i1++) {
    my $cmd = $h->{cmds}[$i1];

    if($cmd =~ m/^loop:([^:]*):/) {
      my @loop = split(":", $cmd);
      my $var = $1;
      my $i2;
      for($i2=$i1+1; $i2<@{$h->{cmds}}; $i2++) {
        last if($h->{cmds}[$i2] =~ m/^loop:END/)
      }
      for(my $i3=2; $i3<@loop; $i3++) {
        for(my $i4=$i1+1; $i4<$i2; $i4++) {
          $cmd = $h->{cmds}[$i4];
          $cmd =~ s/$var/$loop[$i3]/g;
          push @cmds, $cmd;
        }
      }
      $i1=$i2;

    } else {
      push @cmds, $cmd;
    }

  }
  my $cmdlist = join("\n",@cmds);

  $repl{DEVICE} = $name;
  Log3 $name, 5, "AttrTemplate replace ".
                        join(",", map { "$_=>$repl{$_}" } sort keys %repl);
  map { $cmdlist =~ s/(?<!\\)$_/$repl{$_}/g; } sort keys %repl;
  map { $cmdlist =~ s/\\$_/$_/g; } sort keys %repl;
  my $cl = $hash->{CL};
  my $cmd = "";
  my @ret;
  my $option = 1;
  my $withHtml;
  map {

    if($_ =~ m/^(.*)\\$/) {
      $cmd .= "$1\n";

    } else {
      $cmd .= $_;
      if($cmd =~ m/^option:(.*)$/s) {
        my $optVal = $1;
        if($optVal =~ m/^\s*{.*}\s*$/) {
          $option = (AnalyzePerlCommand(undef, $optVal) eq "1");

        } else {
          $option = defined($defs{devspec2array($optVal)});

        }

      } elsif($option) {
        $cmd =~ s/##.*//; #114109
        Log3 $name, 5, "AttrTemplate exec $cmd";
        my $r = AnalyzeCommand($cl, $cmd);
        if($r) {
          if($r =~ m,^<html>(.*)</html>$,s) {
            $r = $1;
            $withHtml = 1;
          }
          push(@ret, $r);
        }

      } else {
        Log3 $name, 5, "AttrTemplate skip $cmd";

      }
      $cmd = "";
    }
  } split("\n", $cmdlist);

  if(@ret) {
    my $r = join("\n", @ret);
    $r = "<html>$r</html>" if($withHtml);
    return $r;
  }

  if($h->{farewell}) {
    my $fw = $h->{farewell};
    if(!$cl || $cl->{TYPE} ne "FHEMWEB") {
      $fw =~ s/<br>/\n/gi;
      $fw =~ s/<[^>]+>//g;      # remove html tags
    }
    return $fw if(!$cl);
    InternalTimer(gettimeofday()+1, sub{asyncOutput($cl, $fw)}, undef, 0);
  }
  return undef;

}

1;
