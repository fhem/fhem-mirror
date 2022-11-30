############################################################################################################################################
# $Id: 93_DbLog.pm 26750 2022-11-29 16:38:54Z DS_Starter $
#
# 93_DbLog.pm
# written by Dr. Boris Neubert 2007-12-30
# e-mail: omega at online dot de
#
# modified and maintained by Tobias Faust since 2012-06-26 until 2016
# e-mail: tobias dot faust at online dot de
#
# redesigned and maintained 2016-2022 by DS_Starter with credits by: JoeAllb, DeeSpe
# e-mail: heiko dot maaz at t-online dot de
#
# reduceLog() created by Claudiu Schuster (rapster)
#
############################################################################################################################################
#
#  Leerzeichen entfernen: sed -i 's/[[:space:]]*$//' 93_DbLog.pm
#
#########################################################################################################################

package main;
use strict;
use warnings;
eval "use DBI;1"                         or my $DbLogMMDBI    = "DBI";
eval "use FHEM::Meta;1"                  or my $modMetaAbsent = 1;
eval "use FHEM::Utility::CTZ qw(:all);1" or my $ctzAbsent     = 1;
eval "use JSON;1;"                       or my $jsonabs       = "JSON";              ## no critic 'eval' # Debian: apt-get install libjson-perl

use Data::Dumper;
use Blocking;
use Time::HiRes qw(gettimeofday tv_interval);
use Time::Local;
use Encode qw(encode_utf8);
use HttpUtils;
use SubProcess;

no if $] >= 5.017011, warnings => 'experimental::smartmatch';

# Version History intern by DS_Starter:
my %DbLog_vNotesIntern = (
  "5.0.0"   => "29.11.2022 Test subprocess ",
  "4.13.3"  => "26.11.2022 revise commandref ",
  "4.13.2"  => "06.11.2022 Patch Delta calculation (delta-d,delta-h) https://forum.fhem.de/index.php/topic,129975.msg1242272.html#msg1242272 ",
  "4.13.1"  => "16.10.2022 edit commandref ",
  "4.13.0"  => "15.04.2022 new Attr convertTimezone, minor fixes in reduceLog(NbL) ",
  "4.12.7"  => "08.03.2022 \$data{firstvalX} doesn't work, forum: https://forum.fhem.de/index.php/topic,126631.0.html ",
  "4.12.6"  => "17.01.2022 change log message deprecated to outdated, forum:#topic,41089.msg1201261.html#msg1201261 ",
  "4.12.5"  => "31.12.2021 standard unit assignment for readings beginning with 'temperature' and removed, forum:#125087 ",
  "4.12.4"  => "27.12.2021 change ParseEvent for FBDECT, warning messages for deprecated commands added ",
  "4.12.3"  => "20.04.2021 change sub _DbLog_ConnectNewDBH for SQLITE, change error Logging in DbLog_writeFileIfCacheOverflow ",
  "4.12.2"  => "08.04.2021 change standard splitting ",
  "4.12.1"  => "07.04.2021 improve escaping the pipe ",
  "4.12.0"  => "29.03.2021 new attributes SQLiteCacheSize, SQLiteJournalMode ",
  "4.11.0"  => "20.02.2021 new attr cacheOverflowThreshold, reading CacheOverflowLastNum/CacheOverflowLastState, ".
                           "remove prototypes, new subs DbLog_writeFileIfCacheOverflow, DbLog_setReadingstate ",
  "4.10.2"  => "23.06.2020 configCheck changed for SQLite again ",
  "4.10.1"  => "22.06.2020 configCheck changed for SQLite ",
  "4.10.0"  => "22.05.2020 improve configCheck, new vars \$LASTTIMESTAMP and \$LASTVALUE in valueFn / DbLogValueFn, Forum:#111423 ",
  "4.9.13"  => "12.05.2020 commandRef changed, AutoInactiveDestroy => 1 for dbh ",
  "4.9.12"  => "28.04.2020 fix line breaks in set function, Forum: #110673 ",
  "4.9.11"  => "22.03.2020 logfile entry if DBI module not installed, Forum: #109382 ",
  "4.9.10"  => "31.01.2020 fix warning, Forum: #107950 ",
  "4.9.9"   => "21.01.2020 default ParseEvent changed again, Forum: #106769 ",
  "4.9.8"   => "17.01.2020 adjust configCheck with plotEmbed check. Forum: #107383 ",
  "4.9.7"   => "13.01.2020 change datetime pattern in valueFn of DbLog_addCacheLine. Forum: #107285 ",
  "4.9.6"   => "04.01.2020 fix change off 4.9.4 in default splitting. Forum: #106992 ",
  "4.9.5"   => "01.01.2020 do not reopen database connection if device is disabled (fix) ",
  "4.9.4"   => "29.12.2019 correct behavior if value is empty and attribute addStateEvent is set (default), Forum: #106769 ",
  "4.9.3"   => "28.12.2019 check date/time format got from SVG, Forum: #101005 ",
  "4.9.2"   => "16.12.2019 add \$DEVICE to attr DbLogValueFn for readonly access to the device name ",
  "4.9.1"   => "13.11.2019 escape \ with \\ in DbLog_Push and DbLog_PushAsync ",
  "4.9.0"   => "11.11.2019 new attribute defaultMinInterval to set a default minInterval central in dblog for all events ".
                           "Forum: https://forum.fhem.de/index.php/topic,65860.msg972352.html#msg972352 ",
  "4.8.0"   => "14.10.2019 change SQL-Statement for delta-h, delta-d (SVG getter) ",
  "4.7.5"   => "07.10.2019 fix warning \"error valueFn: Global symbol \$CN requires ...\" in DbLog_addCacheLine ".
                           "enhanced configCheck by insert mode check ",
  "4.7.4"   => "03.10.2019 bugfix test of TIMESTAMP got from DbLogValueFn or valueFn in DbLog_Log and DbLog_AddLog ",
  "4.7.3"   => "02.10.2019 improved log out entries of DbLog_Get for SVG ",
  "4.7.2"   => "28.09.2019 change cache from %defs to %data ",
  "4.7.1"   => "10.09.2019 release the memcache memory: https://www.effectiveperlprogramming.com/2018/09/undef-a-scalar-to-release-its-memory/ in asynchron mode: https://www.effectiveperlprogramming.com/2018/09/undef-a-scalar-to-release-its-memory/ ",
  "4.7.0"   => "04.09.2019 attribute traceHandles, extract db driver versions in configCheck ",
  "4.6.0"   => "03.09.2019 add-on parameter \"force\" for MinInterval, Forum: #97148 ",
  "4.5.0"   => "28.08.2019 consider attr global logdir in set exportCache ",
  "4.4.0"   => "21.08.2019 configCheck changed: check if new DbLog version is available or the local one is modified ",
  "4.3.0"   => "14.08.2019 new attribute dbSchema, add database schema to subroutines ",
  "4.2.0"   => "25.07.2019 DbLogValueFn as device specific function propagated in devices if dblog is used ",
  "4.1.1"   => "25.05.2019 fix ignore MinInterval if value is \"0\", Forum: #100344 ",
  "4.1.0"   => "17.04.2019 DbLog_Get: change reconnect for MySQL (Forum: #99719), change index suggestion in DbLog_configcheck ",
  "4.0.0"   => "14.04.2019 rewrite DbLog_PushAsync / DbLog_Push / DbLog_Connectxx, new attribute \"bulkInsert\" ",
  "3.14.1"  => "12.04.2019 DbLog_Get: change select of MySQL Forum: https://forum.fhem.de/index.php/topic,99280.0.html ",
  "3.14.0"  => "05.04.2019 add support for Meta.pm and X_DelayedShutdownFn, attribute shutdownWait removed, ".
                           "direct attribute help in FHEMWEB ",
  "3.13.3"  => "04.03.2019 addLog better Log3 Outputs ",
  "3.13.2"  => "09.02.2019 Commandref revised ",
  "3.13.1"  => "27.11.2018 DbLog_ExecSQL log output changed ",
  "3.13.0"  => "12.11.2018 adding attributes traceFlag, traceLevel ",
  "3.12.7"  => "10.11.2018 addLog considers DbLogInclude (Forum:#92854) ",
  "3.12.6"  => "22.10.2018 fix timer not deleted if reopen after reopen xxx (Forum: https://forum.fhem.de/index.php/topic,91869.msg848433.html#msg848433) ",
  "3.12.5"  => "12.10.2018 charFilter: \"\\xB0C\" substitution by \"°C\" added and usage in DbLog_Log changed ",
  "3.12.4"  => "10.10.2018 return non-saved datasets back in asynch mode only if transaction is used ",
  "3.12.3"  => "08.10.2018 Log output of recuceLogNbl enhanced, some functions renamed ",
  "3.12.2"  => "07.10.2018 \$hash->{HELPER}{REOPEN_RUNS_UNTIL} contains the time the DB is closed  ",
  "3.12.1"  => "19.09.2018 use Time::Local (forum:#91285) ",
  "3.12.0"  => "04.09.2018 corrected SVG-select (https://forum.fhem.de/index.php/topic,65860.msg815640.html#msg815640) ",
  "3.11.0"  => "02.09.2018 reduceLog, reduceLogNbl - optional \"days newer than\" part added ",
  "3.10.10" => "05.08.2018 commandref revised reducelogNbl ",
  "3.10.9"  => "23.06.2018 commandref added hint about special characters in passwords ",
  "3.10.8"  => "21.04.2018 addLog - not available reading can be added as new one (forum:#86966) ",
  "3.10.7"  => "16.04.2018 fix generate addLog-event if device or reading was not found by addLog ",
  "3.10.6"  => "13.04.2018 verbose level in addlog changed if reading not found ",
  "3.10.5"  => "12.04.2018 fix warnings ",
  "3.10.4"  => "11.04.2018 fix addLog if no valueFn is used ",
  "3.10.3"  => "10.04.2018 minor fixes in addLog ",
  "3.10.2"  => "09.04.2018 add qualifier CN=<caller name> to addlog ",
  "3.10.1"  => "04.04.2018 changed event parsing of Weather ",
  "3.10.0"  => "02.04.2018 addLog consider DbLogExclude in Devices, keyword \"!useExcludes\" to switch off considering ".
                           "DbLogExclude in addLog, DbLogExclude & DbLogInclude can handle \"/\" in Readingname ".
                           "commandref (reduceLog) revised ",
  "3.9.0"   => "17.03.2018 _DbLog_ConnectPush state-handling changed, attribute excludeDevs enhanced in DbLog_Log ",
  "3.8.9"   => "10.03.2018 commandref revised ",
  "3.8.8"   => "05.03.2018 fix device doesn't exit if configuration couldn't be read ",
  "3.8.7"   => "28.02.2018 changed DbLog_sampleDataFn - no change limits got fron SVG, commandref revised ",
  "3.8.6"   => "25.02.2018 commandref revised (forum:#84953) ",
  "3.8.5"   => "16.02.2018 changed ParseEvent for Zwave ",
  "3.8.4"   => "07.02.2018 minor fixes of \"\$\@\", code review, eval for userCommand, DbLog_ExecSQL1 (forum:#83973) ",
  "3.8.3"   => "03.02.2018 call execmemcache only syncInterval/2 if cacheLimit reached and DB is not reachable, fix handling of ".
                           "\"\$\@\" in DbLog_PushAsync ",
  "3.8.2"   => "31.01.2018 RaiseError => 1 in _DbLog_ConnectPush, _DbLog_ConnectNewDBH, configCheck improved ",
  "3.8.1"   => "29.01.2018 Use of uninitialized value \$txt if addlog has no value ",
  "3.8.0"   => "26.01.2018 escape \"\|\" in events to log events containing it ",
  "3.7.1"   => "25.01.2018 fix typo in commandref ",
  "3.7.0"   => "21.01.2018 parsed event with Log 5 added, configCheck enhanced by configuration read check ",
  "3.6.5"   => "19.01.2018 fix lot of logentries if disabled and db not available ",
  "3.6.4"   => "17.01.2018 improve DbLog_Shutdown, extend configCheck by shutdown preparation check ",
  "3.6.3"   => "14.01.2018 change verbose level of addlog \"no Reading of device ...\" message from 2 to 4  ",
  "3.6.2"   => "07.01.2018 new attribute \"exportCacheAppend\", change function exportCache to respect attr exportCacheAppend, ".
                           "fix DbLog_execmemcache verbose 5 message ",
  "3.6.1"   => "04.01.2018 change SQLite PRAGMA from NORMAL to FULL (Default Value of SQLite) ",
  "3.6.0"   => "20.12.2017 check global blockingCallMax in configCheck, configCheck now available for SQLITE ",
  "3.5.0"   => "18.12.2017 importCacheFile, addCacheLine uses useCharfilter option, filter only \$event by charfilter  ",
  "3.4.0"   => "10.12.2017 avoid print out {RUNNING_PID} by \"list device\" ",
  "3.3.0"   => "07.12.2017 avoid print out the content of cache by \"list device\" ",
  "3.2.0"   => "06.12.2017 change attribute \"autocommit\" to \"commitMode\", activate choice of autocommit/transaction in logging ".
                           "Addlog/addCacheLine change \$TIMESTAMP check ".
                           "rebuild DbLog_Push/DbLog_PushAsync due to bugfix in update current (Forum:#80519) ".
                           "new attribute \"useCharfilter\" for Characterfilter usage ",
  "3.1.1"   => "05.12.2017 Characterfilter added to avoid unwanted characters what may destroy transaction  ",
  "3.1.0"   => "05.12.2017 new set command addCacheLine ",
  "3.0.0"   => "03.12.2017 set begin_work depending of AutoCommit value, new attribute \"autocommit\", some minor corrections, ".
                           "report working progress of reduceLog,reduceLogNbl in logfile (verbose 3), enhanced log output ".
                           "(e.g. of execute_array) ",
  "2.22.15" => "28.11.2017 some Log3 verbose level adapted ",
  "2.22.14" => "18.11.2017 create state-events if state has been changed (Forum:#78867) ",
  "2.22.13" => "20.10.2017 output of reopen command improved ",
  "2.22.12" => "19.10.2017 avoid illegible messages in \"state\" ",
  "2.22.11" => "13.10.2017 DbLogType expanded by SampleFill, DbLog_sampleDataFn adapted to sort case insensitive, commandref revised ",
  "2.22.10" => "04.10.2017 Encode::encode_utf8 of \$error, DbLog_PushAsyncAborted adapted to use abortArg (Forum:77472) ",
  "2.22.9"  => "04.10.2017 added hint to SVG/DbRep in commandref ",
  "2.22.8"  => "29.09.2017 avoid multiple entries in Dopdown-list when creating SVG by group Device:Reading in DbLog_sampleDataFn ",
  "2.22.7"  => "24.09.2017 minor fixes in configcheck ",
  "2.22.6"  => "22.09.2017 commandref revised ",
  "2.22.5"  => "05.09.2017 fix Internal MODE isn't set correctly after DEF is edited, nextsynch is not renewed if reopen is ".
                           "set manually after reopen was set with a delay Forum:#76213, Link to 98_FileLogConvert.pm added ",
  "2.22.4"  => "27.08.2017 fhem chrashes if database DBD driver is not installed (Forum:#75894) ",
  "2.22.1"  => "07.08.2017 attribute \"suppressAddLogV3\" to suppress verbose3-logentries created by DbLog_AddLog  ",
  "2.22.0"  => "25.07.2017 attribute \"addStateEvent\" added ",
  "2.21.3"  => "24.07.2017 commandref revised ",
  "2.21.2"  => "19.07.2017 changed readCfg to report more error-messages ",
  "2.21.1"  => "18.07.2017 change configCheck for DbRep Report_Idx ",
  "2.21.0"  => "17.07.2017 standard timeout increased to 86400, enhanced explaination in configCheck  ",
  "2.20.0"  => "15.07.2017 state-Events complemented with state by using \$events = deviceEvents(\$dev_hash,1) ",
  "2.19.0"  => "11.07.2017 replace {DBMODEL} by {MODEL} completely ",
  "2.18.3"  => "04.07.2017 bugfix (links with \$FW_ME deleted), MODEL as Internal (for statistic) ",
  "2.18.2"  => "29.06.2017 check of index for DbRep added ",
  "2.18.1"  => "25.06.2017 DbLog_configCheck/ DbLog_sqlget some changes, commandref revised ",
  "2.18.0"  => "24.06.2017 configCheck added (MySQL, PostgreSQL) ",
  "2.17.1"  => "17.06.2017 fix log-entries \"utf8 enabled\" if SVG's called, commandref revised, enable UTF8 for DbLog_get ",
  "2.17.0"  => "15.06.2017 enable UTF8 for MySQL (entry in configuration file necessary) ",
  "2.16.11" => "03.06.2017 execmemcache changed for SQLite avoid logging if deleteOldDaysNbl or reduceLogNbL is running  ",
  "2.16.10" => "15.05.2017 commandref revised ",
  "2.16.9.1"=> "11.05.2017 set userCommand changed - Forum: https://forum.fhem.de/index.php/topic,71808.msg633607.html#msg633607 ",
  "2.16.9"  => "07.05.2017 addlog syntax changed to \"addLog devspec:Reading [Value]\" ",
  "2.16.8"  => "06.05.2017 in valueFN \$VALUE and \$UNIT can now be set to '' or 0 ",
  "2.16.7"  => "20.04.2017 fix \$now at addLog ",
  "2.16.6"  => "18.04.2017 AddLog set lasttime, lastvalue of dev_name, dev_reading ",
  "2.16.5"  => "16.04.2017 DbLog_checkUsePK changed again, new attribute noSupportPK ",
  "2.16.4"  => "15.04.2017 commandref completed, DbLog_checkUsePK changed (\@usepkh = \"\", \@usepkc = \"\") ",
  "2.16.3"  => "07.04.2017 evaluate reading in DbLog_AddLog as regular expression ",
  "2.16.0"  => "03.04.2017 new set-command addLog ",
  "2.15.0"  => "03.04.2017 new attr valueFn using for perl expression which may change variables and skip logging ".
                           "unwanted datasets, change DbLog_ParseEvent for ZWAVE, ".
                           "change DbLogExclude / DbLogInclude in DbLog_Log to \"\$lv = \"\" if(!defined(\$lv));\" ",
  "2.14.4"  => "28.03.2017 pre-connection check in DbLog_execmemcache deleted (avoid possible blocking), attr excludeDevs ".
                           "can be specified as devspec ",
  "2.14.3"  => "24.03.2017 DbLog_Get, DbLog_Push changed for better plotfork-support ",
  "2.14.2"  => "23.03.2017 new reading \"lastCachefile\" ",
  "2.14.1"  => "22.03.2017 cacheFile will be renamed after successful import by set importCachefile                  ",
  "2.14.0"  => "19.03.2017 new set-commands exportCache, importCachefile, new attr expimpdir, all cache relevant set-commands ".
                           "only in drop-down list when asynch mode is used, minor fixes ",
  "2.13.6"  => "13.03.2017 plausibility check in set reduceLog(Nbl) enhanced, minor fixes ",
  "2.13.5"  => "20.02.2017 check presence of table current in DbLog_sampleDataFn ",
  "2.13.3"  => "18.02.2017 default timeout of DbLog_PushAsync increased to 1800, ".
                           "delete {HELPER}{xx_PID} in reopen function ",
  "2.13.2"  => "16.02.2017 deleteOldDaysNbl added (non-blocking implementation of deleteOldDays) ",
  "2.13.1"  => "15.02.2017 clearReadings limited to readings which won't be recreated periodicly in asynch mode and set readings only blank, ".
                           "eraseReadings added to delete readings except reading \"state\", ".
                           "countNbl non-blocking by DeeSPe, ".
                           "rename reduceLog non-blocking to reduceLogNbl and implement the old reduceLog too ",
  "2.13.0"  => "13.02.2017 made reduceLog non-blocking by DeeSPe ",
  "2.12.5"  => "11.02.2017 add support for primary key of PostgreSQL DB (Rel. 9.5) in both modes for current table ",
  "2.12.4"  => "09.02.2017 support for primary key of PostgreSQL DB (Rel. 9.5) in both modes only history table ",
  "2.12.3"  => "07.02.2017 set command clearReadings added ",
  "2.12.2"  => "07.02.2017 support for primary key of SQLITE DB in both modes ",
  "2.12.1"  => "05.02.2017 support for primary key of MySQL DB in synch mode ",
  "2.12"    => "04.02.2017 support for primary key of MySQL DB in asynch mode ",
  "2.11.4"  => "03.02.2017 check of missing modules added ",
  "2.11.3"  => "01.02.2017 make errorlogging of DbLog_PushAsync more identical to DbLog_Push ",
  "2.11.2"  => "31.01.2017 if attr colEvent, colReading, colValue is set, the limitation of fieldlength is also valid ".
                           "for SQLite databases ",
  "2.11.1"  => "30.01.2017 output to central logfile enhanced for DbLog_Push ",
  "2.11"    => "28.01.2017 DbLog_connect substituted by DbLog_connectPush completely ",
  "2.10.8"  => "27.01.2017 DbLog_setinternalcols delayed at fhem start ",
  "2.10.7"  => "25.01.2017 \$hash->{HELPER}{COLSET} in DbLog_setinternalcols, DbLog_Push changed due to ".
                           "issue Turning on AutoCommit failed ",
  "2.10.6"  => "24.01.2017 DbLog_connect changed \"connect_cashed\" to \"connect\", DbLog_Get, DbLog_chartQuery now uses ".
                           "_DbLog_ConnectNewDBH, Attr asyncMode changed -> delete reading cacheusage reliable if mode was switched ",
  "2.10.5"  => "23.01.2017 count, userCommand, deleteOldDays now uses _DbLog_ConnectNewDBH ".
                           "DbLog_Push line 1107 changed ",
  "2.10.4"  => "22.01.2017 new sub DbLog_setinternalcols, new attributes colEvent, colReading, colValue ",
  "2.10.3"  => "21.01.2017 query of cacheEvents changed, attr timeout adjustable ",
  "2.10.2"  => "19.01.2017 ReduceLog now uses _DbLog_ConnectNewDBH -> makes start of ReduceLog stable ",
  "2.10.1"  => "19.01.2017 commandref edited, cache events don't get lost even if other errors than \"db not available\" occure ",
  "2.10"    => "18.10.2017 new attribute cacheLimit, showNotifyTime ",
  "2.9.3"   => "17.01.2017 new sub _DbLog_ConnectNewDBH (own new dbh for separate use in functions except logging functions), ".
                           "DbLog_sampleDataFn, DbLog_dbReadings now use _DbLog_ConnectNewDBH ",
  "2.9.2"   => "16.01.2017 new bugfix for SQLite issue SVGs, DbLog_Log changed to \$dev_hash->{CHANGETIME}, DbLog_Push ".
                           "changed (db handle new separated) ",
  "2.9.1"   => "14.01.2017 changed DbLog_ParseEvent to CallInstanceFn, renamed flushCache to purgeCache, ".
                           "renamed syncCache to commitCache, attr cacheEvents changed to 0,1,2 ",
  "2.8.9"   => "11.01.2017 own \$dbhp (new _DbLog_ConnectPush) for synchronous logging, delete \$hash->{HELPER}{RUNNING_PID} ".
                           "if DEAD, add func flushCache, syncCache ",
  "2.8.8"   => "10.01.2017 connection check in Get added, avoid warning \"commit/rollback ineffective with AutoCommit enabled\" ",
  "2.8.7"   => "10.01.2017 bugfix no dropdown list in SVG if asynchronous mode activated (func DbLog_sampleDataFn) ",
  "2.8.6"   => "09.01.2017 Workaround for Warning begin_work failed: Turning off AutoCommit failed, start new timer of ".
                           "DbLog_execmemcache after reducelog ",
  "2.8.5"   => "08.01.2017 attr syncEvents, cacheEvents added to minimize events ",
  "2.8.4"   => "08.01.2017 \$readingFnAttributes added ",
  "2.8.3"   => "08.01.2017 set NOTIFYDEV changed to use notifyRegexpChanged (Forum msg555619), attr noNotifyDev added ",
  "2.8.2"   => "06.01.2017 commandref maintained to cover new functions ",
  "2.8.1"   => "05.01.2017 use Time::HiRes qw(gettimeofday tv_interval), bugfix \$hash->{HELPER}{RUNNING_PID} ",
  "2.4.4"   => "28.12.2016 Attribut \"excludeDevs\" to exclude devices from db-logging (only if \$hash->{NOTIFYDEV} eq \"\.\*\") ",
  "2.4.3"   => "28.12.2016 function DbLog_Log: changed separators of \@row_array -> better splitting ",
  "2.4.2"   => "28.12.2016 Attribut \"verbose4Devs\" to restrict verbose4 loggings of specific devices  ",
  "2.4.1"   => "27.12.2016 DbLog_Push: improved update/insert into current, analyze execute_array -> ArrayTupleStatus ",
  "2.3.1"   => "23.12.2016 fix due to https://forum.fhem.de/index.php/topic,62998.msg545541.html#msg545541 ",
  "1.9.3"   => "17.12.2016 \$hash->{NOTIFYDEV} added to process only events from devices are in Regex ",
  "1.9.2"   => "17.12.2016 some improvemnts DbLog_Log, DbLog_Push ",
  "1.9.1"   => "16.12.2016 DbLog_Log no using encode_base64 ",
  "1.8.1"   => "16.12.2016 DbLog_Push changed ",
  "1.7.1"   => "15.12.2016 attr procedure of \"disabled\" changed"
);

# Defaultwerte
my %DbLog_columns = ("DEVICE"  => 64,
                     "TYPE"    => 64,
                     "EVENT"   => 512,
                     "READING" => 64,
                     "VALUE"   => 128,
                     "UNIT"    => 32
                    );

my $dblog_cachedef = 500;                       # default Größe cacheLimit bei asynchronen Betrieb

################################################################
sub DbLog_Initialize {
  my $hash = shift;

  $hash->{DefFn}             = "DbLog_Define";
  $hash->{UndefFn}           = "DbLog_Undef";
  $hash->{NotifyFn}          = "DbLog_Log";
  $hash->{SetFn}             = "DbLog_Set";
  $hash->{GetFn}             = "DbLog_Get";
  $hash->{AttrFn}            = "DbLog_Attr";
  $hash->{ReadFn}            = "DbLog_SBP_Read";
  $hash->{SVG_regexpFn}      = "DbLog_regexpFn";
  $hash->{DelayedShutdownFn} = "DbLog_DelayedShutdown";
  $hash->{AttrList}          = "addStateEvent:0,1 ".
                               "asyncMode:1,0 ".
                               "bulkInsert:1,0 ".
                               "commitMode:basic_ta:on,basic_ta:off,ac:on_ta:on,ac:on_ta:off,ac:off_ta:on ".
                               "cacheEvents:2,1,0 ".
                               "cacheLimit ".
                               "cacheOverflowThreshold ".
                               "colEvent ".
                               "colReading ".
                               "colValue ".
                               "convertTimezone:UTC,none ".
                               "DbLogSelectionMode:Exclude,Include,Exclude/Include ".
                               "DbLogType:Current,History,Current/History,SampleFill/History ".
                               "SQLiteJournalMode:WAL,off ".
                               "SQLiteCacheSize ".
                               "dbSchema ".
                               "defaultMinInterval:textField-long ".
                               "disable:1,0 ".
                               "excludeDevs ".
                               "expimpdir ".
                               "exportCacheAppend:1,0 ".
                               "noSupportPK:1,0 ".
                               "noNotifyDev:1,0 ".
                               "showproctime:1,0 ".
                               "suppressAddLogV3:1,0 ".
                               "suppressUndef:0,1 ".
                               "syncEvents:1,0 ".
                               "syncInterval ".
                               "showNotifyTime:1,0 ".
                               "traceFlag:SQL,CON,ENC,DBD,TXN,ALL ".
                               "traceLevel:0,1,2,3,4,5,6,7 ".
                               "traceHandles ".
                               "timeout ".
                               "useCharfilter:0,1 ".
                               "valueFn:textField-long ".
                               "verbose4Devs ".
                               $readingFnAttributes;

  addToAttrList("DbLogInclude");
  addToAttrList("DbLogExclude");
  addToAttrList("DbLogValueFn:textField-long");

  $hash->{FW_detailFn}      = "DbLog_fhemwebFn";
  $hash->{SVG_sampleDataFn} = "DbLog_sampleDataFn";

  eval { FHEM::Meta::InitMod( __FILE__, $hash ) };           # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)

return;
}

###############################################################
sub DbLog_Define {
  my ($hash, $def) = @_;
  my $name         = $hash->{NAME};
  my @a            = split "[ \t][ \t]*", $def;

  if($DbLogMMDBI) {
      Log3($name, 1, "DbLog $name - ERROR - Perl module ".$DbLogMMDBI." is missing. DbLog module is not loaded ! On Debian systems you can install it with \"sudo apt-get install libdbi-perl\" ");
      return "Error: Perl module ".$DbLogMMDBI." is missing. Install it on Debian with: sudo apt-get install libdbi-perl";
  }
  
  if($jsonabs) {
      Log3($name, 1, "DbLog $name - ERROR - Perl module ".$jsonabs." is missing. Install it on Debian with: sudo apt-get install libjson-perl");
      return "Error: Perl module ".$jsonabs." is missing. Install it on Debian with: sudo apt-get install libjson-perl";
  }

  return "wrong syntax: define <name> DbLog configuration regexp" if(int(@a) != 4);

  $hash->{CONFIGURATION} = $a[2];
  my $regexp             = $a[3];

  eval { "Hallo" =~ m/^$regexp$/ };
  return "Bad regexp: $@" if($@);

  $hash->{REGEXP}                = $regexp;
  $hash->{MODE}                  = AttrVal($name, "asyncMode", undef) ? "asynchronous" : "synchronous";       # Mode setzen Forum:#76213
  $hash->{HELPER}{OLDSTATE}      = "initialized";
  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                                                      # Modul Meta.pm nicht vorhanden
  $hash->{HELPER}{TH}            = "history";                                                                 # Tabelle history (wird ggf. durch Datenbankschema ergänzt)
  $hash->{HELPER}{TC}            = "current";                                                                 # Tabelle current (wird ggf. durch Datenbankschema ergänzt)

  DbLog_setVersionInfo ($hash);                                                                               # Versionsinformationen setzen
  notifyRegexpChanged  ($hash, $regexp);                                                                      # nur Events dieser Devices an NotifyFn weiterleiten, NOTIFYDEV wird gesetzt wenn möglich
  
  $hash->{PID}                      = $$;                                                                     # remember PID for plotfork
  $data{DbLog}{$name}{cache}{index} = 0;                                                                      # CacheIndex für Events zum asynchronen Schreiben in DB

  my $ret = DbLog_readCfg($hash);                                                                             # read configuration data
  
  if ($ret) {                                                                                                 # return on error while reading configuration
      Log3($name, 1, "DbLog $name - Error while reading $hash->{CONFIGURATION}: '$ret' ");
      return $ret;
  }

  InternalTimer(gettimeofday()+2, "DbLog_setinternalcols", $hash, 0);                                         # set used COLUMNS

  readingsSingleUpdate ($hash, 'state', 'waiting for connection', 1);
  _DbLog_ConnectPush   ($hash);
  DbLog_execmemcache   ($hash);                                                                               # initial execution of DbLog_execmemcache

return;
}

################################################################
# Die Undef-Funktion wird aufgerufen wenn ein Gerät mit delete
# gelöscht wird oder bei der Abarbeitung des Befehls rereadcfg,
# der ebenfalls alle Geräte löscht und danach das
# Konfigurationsfile neu einliest. Entsprechend müssen in der
# Funktion typische Aufräumarbeiten durchgeführt werden wie das
# saubere Schließen von Verbindungen oder das Entfernen von
# internen Timern.
################################################################
sub DbLog_Undef {
  my $hash = shift;
  my $name = shift;
  my $dbh  = $hash->{DBHP};

  BlockingKill($hash->{HELPER}{".RUNNING_PID"}) if($hash->{HELPER}{".RUNNING_PID"});
  BlockingKill($hash->{HELPER}{REDUCELOG_PID})  if($hash->{HELPER}{REDUCELOG_PID});
  BlockingKill($hash->{HELPER}{COUNT_PID})      if($hash->{HELPER}{COUNT_PID});
  BlockingKill($hash->{HELPER}{DELDAYS_PID})    if($hash->{HELPER}{DELDAYS_PID});

  $dbh->disconnect() if(defined($dbh));

  RemoveInternalTimer($hash);
  delete $data{DbLog}{$name};
  
  DbLog_SBP_CleanUp ($hash);
  
return;
}

#######################################################################################################
# Mit der X_DelayedShutdown Funktion kann eine Definition das Stoppen von FHEM verzögern um asynchron
# hinter sich aufzuräumen.
# Je nach Rückgabewert $delay_needed wird der Stopp von FHEM verzögert (0 | 1).
# Sobald alle nötigen Maßnahmen erledigt sind, muss der Abschluss mit CancelDelayedShutdown($name) an
# FHEM zurückgemeldet werden.
#######################################################################################################
sub DbLog_DelayedShutdown {
  my $hash   = shift;
  my $name   = $hash->{NAME};
  my $async  = AttrVal($name, "asyncMode", "");

  return 0 if(IsDisabled($name));

  $hash->{HELPER}{SHUTDOWNSEQ} = 1;
  
  Log3 ($name, 2, "DbLog $name - Last database write cycle due to shutdown ...");
  DbLog_execmemcache($hash);

return 1;
}

#####################################################
#   DelayedShutdown abschließen
#   letzte Aktivitäten vor Freigabe des Shutdowns   
#####################################################
sub _DbLog_finishDelayedShutdown {
  my $hash = shift;
  my $name = $hash->{NAME};
  
  DbLog_SBP_CleanUp ($hash);
  delete $hash->{HELPER}{SHUTDOWNSEQ};
  CancelDelayedShutdown ($name);

return;
}

################################################################
#
# Wird bei jeder Aenderung eines Attributes dieser
# DbLog-Instanz aufgerufen
#
################################################################
sub DbLog_Attr {
  my($cmd,$name,$aName,$aVal) = @_;
  my $hash                    = $defs{$name};
  my $dbh                     = $hash->{DBHP};
  my $do                      = 0;

  if($cmd eq "set") {
      if ($aName eq "syncInterval"           ||
          $aName eq "cacheLimit"             ||
          $aName eq "cacheOverflowThreshold" ||
          $aName eq "SQLiteCacheSize"        ||
          $aName eq "timeout") {
          if ($aVal !~ /^[0-9]+$/) { return "The Value of $aName is not valid. Use only figures 0-9 !";}
      }

      if ($hash->{MODEL} !~ /MYSQL|POSTGRESQL/ && $aName =~ /dbSchema/) {
           return "\"$aName\" is not valid for database model \"$hash->{MODEL}\"";
      }

      if( $aName eq 'valueFn' ) {
          my %specials= (
             "%TIMESTAMP"     => $name,
             "%LASTTIMESTAMP" => $name,
             "%DEVICE"        => $name,
             "%DEVICETYPE"    => $name,
             "%EVENT"         => $name,
             "%READING"       => $name,
             "%VALUE"         => $name,
             "%LASTVALUE"     => $name,
             "%UNIT"          => $name,
             "%IGNORE"        => $name,
             "%CN"            => $name
          );
          my $err = perlSyntaxCheck($aVal, %specials);
          return $err if($err);
      }

      if ($aName eq "shutdownWait") {
         return "DbLog $name - The attribute $aName is deprecated and has been removed !";
      }

      if ($aName eq "SQLiteCacheSize" || $aName eq "SQLiteJournalMode") {
          InternalTimer(gettimeofday()+1.0, "DbLog_attrForSQLite", $hash, 0);
          InternalTimer(gettimeofday()+1.5, "DbLog_attrForSQLite", $hash, 0);               # muß zweimal ausgeführt werden - Grund unbekannt :-(
      }

      if ($aName eq "convertTimezone") {
          return "The library FHEM::Utility::CTZ is missed. Please update FHEM completely." if($ctzAbsent);

          my $rmf = reqModFail();
          return "You have to install the required perl module: ".$rmf if($rmf);
      }
  }

  if($aName eq "colEvent" || $aName eq "colReading" || $aName eq "colValue") {
      if ($cmd eq "set" && $aVal) {
          unless ($aVal =~ /^[0-9]+$/) { return " The Value of $aName is not valid. Use only figures 0-9 !";}
      }
      InternalTimer(gettimeofday()+0.5, "DbLog_setinternalcols", $hash, 0);
  }

  if($aName eq "asyncMode") {
      if ($cmd eq "set" && $aVal) {
          $hash->{MODE} = "asynchronous";
          InternalTimer(gettimeofday()+2, "DbLog_execmemcache", $hash, 0);
      }
      else {
          $hash->{MODE} = "synchronous";
          delete($defs{$name}{READINGS}{NextSync});
          delete($defs{$name}{READINGS}{CacheUsage});
          delete($defs{$name}{READINGS}{CacheOverflowLastNum});
          delete($defs{$name}{READINGS}{CacheOverflowLastState});
          delete($defs{$name}{READINGS}{background_processing_time});
          InternalTimer(gettimeofday()+5, "DbLog_execmemcache", $hash, 0);
      }
  }

  if($aName eq "commitMode") {
      if ($dbh) {
          $dbh->commit() if(!$dbh->{AutoCommit});
          $dbh->disconnect();
        }
  }

  if($aName eq "showproctime") {
      if ($cmd ne "set" || !$aVal) {
          delete($defs{$name}{READINGS}{background_processing_time});
          delete($defs{$name}{READINGS}{sql_processing_time});
      }
  }

  if($aName eq "showNotifyTime") {
      if ($cmd ne "set" || !$aVal) {
          delete($defs{$name}{READINGS}{notify_processing_time});
      }
  }

  if($aName eq "noNotifyDev") {
      my $regexp = $hash->{REGEXP};
      if ($cmd eq "set" && $aVal) {
          delete($hash->{NOTIFYDEV});
      }
      else {
          notifyRegexpChanged($hash, $regexp);
      }
  }

  if ($aName eq "disable") {
      my $async = AttrVal($name, "asyncMode", 0);
      if($cmd eq "set") {
          $do = ($aVal) ? 1 : 0;
      }
      $do = 0 if($cmd eq "del");
      my $val   = ($do == 1 ?  "disabled" : "active");

      # letzter CacheSync vor disablen
      DbLog_execmemcache($hash) if($do == 1);

      DbLog_setReadingstate ($hash, $val);

      if ($do == 0) {
          InternalTimer(gettimeofday()+2, "DbLog_execmemcache", $hash, 0) if($async);
          InternalTimer(gettimeofday()+2, "_DbLog_ConnectPush", $hash, 0) if(!$async);
      }
  }

  if ($aName eq "traceHandles") {
      if($cmd eq "set") {
          unless ($aVal =~ /^[0-9]+$/) {return " The Value of $aName is not valid. Use only figures 0-9 without decimal places !";}
      }
      RemoveInternalTimer($hash, "DbLog_startShowChildhandles");
      if($cmd eq "set") {
          $do = ($aVal) ? 1 : 0;
      }
      $do = 0 if($cmd eq "del");
      if($do) {
          InternalTimer(gettimeofday()+5, "DbLog_startShowChildhandles", "$name:Main", 0);
      }
  }

  if ($aName eq "dbSchema") {
      if($cmd eq "set") {
          $do = ($aVal) ? 1 : 0;
      }
      $do = 0 if($cmd eq "del");

      if ($do == 1) {
          $hash->{HELPER}{TH}       = $aVal.".history";
          $hash->{HELPER}{TC}       = $aVal.".current";
      }
      else {
          $hash->{HELPER}{TH}       = "history";
          $hash->{HELPER}{TC}       = "current";
      }
  }

return;
}

################################################################
#   reopen DB beim Setzen bestimmter Attribute
################################################################
sub DbLog_attrForSQLite {
  my $hash = shift;

  return if($hash->{MODEL} ne "SQLITE");

  my $name = $hash->{NAME};

  my $dbh = $hash->{DBHP};
  if ($dbh) {
      my $history = $hash->{HELPER}{TH};
      if(!$dbh->{AutoCommit}) {
          eval {$dbh->commit()} or Log3($name, 2, "DbLog $name -> Error commit $history - $@");
      }
      $dbh->disconnect();
  }
  _DbLog_ConnectPush ($hash,1);

return;
}

################################################################
sub DbLog_Set {
    my ($hash, @a) = @_;
    my $name       = $hash->{NAME};
    my $async      = AttrVal($name, "asyncMode", undef);

    my $usage      = "Unknown argument, choose one of ".
                     "reduceLog ".
                     "reduceLogNbl ".
                     "reopen ".
                     "rereadcfg:noArg ".
                     "count:noArg ".
                     "configCheck:noArg ".
                     "countNbl:noArg ".
                     "deleteOldDays ".
                     "deleteOldDaysNbl ".
                     "userCommand ".
                     "clearReadings:noArg ".
                     "eraseReadings:noArg ".
                     "addLog "
                     ;

    if (AttrVal($name, "asyncMode", undef)) {
        $usage    .= "listCache:noArg ".
                     "addCacheLine ".
                     "purgeCache:noArg ".
                     "commitCache:noArg ".
                     "exportCache:nopurge,purgecache "
                     ;
    }

    my $history = $hash->{HELPER}{TH};
    my $current = $hash->{HELPER}{TC};
    my (@logs,$dir);

    my $dirdef = AttrVal("global", "logdir", $attr{global}{modpath}."/log/");
    $dir       = AttrVal($name, "expimpdir", $dirdef);
    $dir       = $dir."/" if($dir !~ /.*\/$/);

    opendir(DIR,$dir);
    my $sd = "cache_".$name."_";
    while (my $file = readdir(DIR)) {
        next unless (-f "$dir/$file");
        next unless ($file =~ /^$sd/);
        push @logs,$file;
    }
    closedir(DIR);
    my $cj = "";
    $cj    = join(",",reverse(sort @logs)) if (@logs);

    if (@logs) {
        $usage .= "importCachefile:".$cj." ";
    }
    else {
        $usage .= "importCachefile ";
    }

    return $usage if(int(@a) < 2);
    my $dbh  = $hash->{DBHP};
    my $db   = (split(/;|=/, $hash->{dbconn}))[1];
    my $ret;

    if ($a[1] eq 'reduceLog') {
        Log3($name, 2, qq{DbLog $name - WARNING - "$a[1]" is outdated. Please consider use of DbRep "set <Name> reduceLog" instead.});
        my ($od,$nd) = split(":",$a[2]);         # $od - Tage älter als , $nd - Tage neuer als
        if ($nd && $nd <= $od) {return "The second day value must be greater than the first one ! ";}
        if (defined($a[3]) && $a[3] !~ /^average$|^average=.+|^EXCLUDE=.+$|^INCLUDE=.+$/i) {
            return "ReduceLog syntax error in set command. Please see commandref for help.";
        }
        if (defined $a[2] && $a[2] =~ /(^\d+$)|(^\d+:\d+$)/) {
            $ret = DbLog_reduceLog($hash,@a);
            InternalTimer(gettimeofday()+5, "DbLog_execmemcache", $hash, 0);
        }
        else {
            Log3($name, 1, "DbLog $name: reduceLog error, no <days> given.");
            $ret = "reduceLog error, no <days> given.";
        }
    }
    elsif ($a[1] eq 'reduceLogNbl') {
        Log3($name, 2, qq{DbLog $name - WARNING - "$a[1]" is outdated. Please consider use of DbRep "set <Name> reduceLog" instead.});
        my ($od,$nd) = split(":",$a[2]);         # $od - Tage älter als , $nd - Tage neuer als
        if ($nd && $nd <= $od) {return "The second day value must be greater than the first one ! ";}
        if (defined($a[3]) && $a[3] !~ /^average$|^average=.+|^EXCLUDE=.+$|^INCLUDE=.+$/i) {
            return "ReduceLogNbl syntax error in set command. Please see commandref for help.";
        }
        if (defined $a[2] && $a[2] =~ /(^\d+$)|(^\d+:\d+$)/) {
            if ($hash->{HELPER}{REDUCELOG_PID} && $hash->{HELPER}{REDUCELOG_PID}{pid} !~ m/DEAD/) {
                $ret = "reduceLogNbl already in progress. Please wait until the running process is finished.";
            }
            else {
                delete $hash->{HELPER}{REDUCELOG_PID};
                my @b = @a;
                shift(@b);
                readingsSingleUpdate($hash,"reduceLogState","@b started",1);
                $hash->{HELPER}{REDUCELOG} = \@a;
                $hash->{HELPER}{REDUCELOG_PID} = BlockingCall("DbLog_reduceLogNbl","$name","DbLog_reduceLogNbl_finished");
                return;
            }
        }
        else {
            Log3($name, 1, "DbLog $name: reduceLogNbl syntax error, no <days>[:<days>] given.");
            $ret = "reduceLogNbl error, no <days> given.";
        }
    }
    elsif ($a[1] eq 'clearReadings') {
        my @allrds = keys%{$defs{$name}{READINGS}};
        
        for my $key(@allrds) {
            next if($key =~ m/state/ || $key =~ m/CacheUsage/ || $key =~ m/NextSync/);
            readingsSingleUpdate($hash,$key," ",0);
        }
    }
    elsif ($a[1] eq 'eraseReadings') {
        my @allrds = keys%{$defs{$name}{READINGS}};
        
        for my $key(@allrds) {
            delete($defs{$name}{READINGS}{$key}) if($key !~ m/^state$/);
        }
    }
    elsif ($a[1] eq 'addLog') {
        unless ($a[2]) { return "The argument of $a[1] is not valid. Please check commandref.";}
        my $nce = ("\!useExcludes" ~~ @a)?1:0;
        map(s/\!useExcludes//g, @a);
        my $cn;
        if(/CN=/ ~~ @a) {
            my $t = join(" ",@a);
            ($cn) = ($t =~ /^.*CN=(\w+).*$/);
            map(s/CN=$cn//g, @a);
        }
        DbLog_AddLog($hash,$a[2],$a[3],$nce,$cn);
        my $skip_trigger = 1;   # kein Event erzeugen falls addLog device/reading not found aber Abarbeitung erfolgreich
        return undef,$skip_trigger;
    }
    elsif ($a[1] eq 'reopen') {
        return if(IsDisabled($name));
        if ($dbh) {
            eval {$dbh->commit() if(!$dbh->{AutoCommit});};
             if ($@) {
                 Log3($name, 2, "DbLog $name -> Error commit $history - $@");
             }
            $dbh->disconnect();
        }
        if (!$a[2]) {
            Log3($name, 3, "DbLog $name: Reopen requested.");
            _DbLog_ConnectPush($hash);
            if($hash->{HELPER}{REOPEN_RUNS}) {
                delete $hash->{HELPER}{REOPEN_RUNS};
                delete $hash->{HELPER}{REOPEN_RUNS_UNTIL};
                RemoveInternalTimer($hash, "DbLog_reopen");
            }
            DbLog_execmemcache($hash) if($async);
            $ret = "Reopen executed.";
        }
        else {
            unless ($a[2] =~ /^[0-9]+$/) { return " The Value of $a[1]-time is not valid. Use only figures 0-9 !";}
            # Statusbit "Kein Schreiben in DB erlauben" wenn reopen mit Zeitangabe
            $hash->{HELPER}{REOPEN_RUNS} = $a[2];

            # falls ein hängender Prozess vorhanden ist -> löschen
            BlockingKill($hash->{HELPER}{".RUNNING_PID"}) if($hash->{HELPER}{".RUNNING_PID"});
            BlockingKill($hash->{HELPER}{REDUCELOG_PID}) if($hash->{HELPER}{REDUCELOG_PID});
            BlockingKill($hash->{HELPER}{COUNT_PID}) if($hash->{HELPER}{COUNT_PID});
            BlockingKill($hash->{HELPER}{DELDAYS_PID}) if($hash->{HELPER}{DELDAYS_PID});
            delete $hash->{HELPER}{".RUNNING_PID"};
            delete $hash->{HELPER}{COUNT_PID};
            delete $hash->{HELPER}{DELDAYS_PID};
            delete $hash->{HELPER}{REDUCELOG_PID};

            my $ts = (split(" ",FmtDateTime(gettimeofday()+$a[2])))[1];
            Log3($name, 2, "DbLog $name: Connection closed until $ts ($a[2] seconds).");
            readingsSingleUpdate($hash, "state", "closed until $ts ($a[2] seconds)", 1);
            InternalTimer(gettimeofday()+$a[2], "DbLog_reopen", $hash, 0);
            $hash->{HELPER}{REOPEN_RUNS_UNTIL} = $ts;
        }
    }
    elsif ($a[1] eq 'rereadcfg') {
        Log3($name, 3, "DbLog $name: Rereadcfg requested.");

        if ($dbh) {
            $dbh->commit() if(!$dbh->{AutoCommit});
            $dbh->disconnect();
        }
        $ret = DbLog_readCfg($hash);
        return $ret if $ret;
        _DbLog_ConnectPush($hash);
        $ret = "Rereadcfg executed.";
    }
    elsif ($a[1] eq 'purgeCache') {
        delete $data{DbLog}{$name}{cache};
        readingsSingleUpdate($hash, 'CacheUsage', 0, 1);
    }
    elsif ($a[1] eq 'commitCache') {
        DbLog_execmemcache($hash);
    }
    elsif ($a[1] eq 'listCache') {
        my $cache;
        
        for my $key (sort{$a <=>$b}keys %{$data{DbLog}{$name}{cache}{memcache}}) {
            $cache .= $key." => ".$data{DbLog}{$name}{cache}{memcache}{$key}."\n";
        }
        return $cache;
    }
    elsif ($a[1] eq 'addCacheLine') {
        if(!$a[2]) {
            return "Syntax error in set $a[1] command. Use this line format: YYYY-MM-DD HH:MM:SS|<device>|<type>|<event>|<reading>|<value>|[<unit>] ";
        }
        my @b = @a;
        shift @b;
        shift @b;
        my $aa;
        
        for my $k (@b) {
            $aa .= "$k ";
        }
        chop($aa); #letztes Leerzeichen entfernen
        $aa = DbLog_charfilter($aa) if(AttrVal($name, "useCharfilter",0));

        my ($i_timestamp, $i_dev, $i_type, $i_evt, $i_reading, $i_val, $i_unit) = split("\\|",$aa);
        if($i_timestamp !~ /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/ || !$i_dev || !$i_reading) {
            return "Syntax error in set $a[1] command. Use this line format: YYYY-MM-DD HH:MM:SS|<device>|<type>|<event>|<reading>|<value>|[<unit>] ";
        }
        my ($yyyy, $mm, $dd, $hh, $min, $sec) = ($i_timestamp =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
        eval { my $ts = timelocal($sec, $min, $hh, $dd, $mm-1, $yyyy-1900); };

        if ($@) {
            my @l = split (/at/, $@);
           return " Timestamp is out of range - $l[0]";
        }
        DbLog_addCacheLine($hash,$i_timestamp,$i_dev,$i_type,$i_evt,$i_reading,$i_val,$i_unit);

    }
    elsif ($a[1] eq 'configCheck') {
        my $check = DbLog_configcheck($hash);
        return $check;
    }
    elsif ($a[1] eq 'exportCache') {
        my $cln;
        my $crows = 0;
        my $now   = strftime('%Y-%m-%d_%H-%M-%S',localtime);

        my ($out,$outfile,$error);

        return "device is disabled"                if(IsDisabled($name));
        return "device not in asynch working mode" if(!AttrVal($name, "asyncMode", undef));

        if(@logs && AttrVal($name, "exportCacheAppend", 0)) {            # exportiertes Cachefile existiert und es soll an das neueste angehängt werden
            $outfile = $dir.pop(@logs);
            $out     = ">>$outfile";
        }
        else {
            $outfile = $dir."cache_".$name."_".$now;
            $out     = ">$outfile";
        }

        if(open(FH, $out)) {
            binmode (FH);
        }
        else {
            readingsSingleUpdate($hash, "lastCachefile", $outfile." - Error - ".$!, 1);
            $error = "could not open ".$outfile.": ".$!;
        }

        if(!$error) {
            for my $key (sort(keys %{$data{DbLog}{$name}{cache}{memcache}})) {
                $cln = $data{DbLog}{$name}{cache}{memcache}{$key}."\n";
                print FH $cln ;
                $crows++;
            }
            close(FH);
            readingsSingleUpdate($hash, "lastCachefile", $outfile." (".$crows." cache rows exported)", 1);
        }

        my $state  = $error // $hash->{HELPER}{OLDSTATE};
        DbLog_setReadingstate ($hash, $state);

        return $error if($error);

        Log3($name, 3, "DbLog $name: $crows cache rows exported to $outfile.");

        if (lc($a[-1]) =~ m/^purgecache/i) {
            delete $data{DbLog}{$name}{cache};
            readingsSingleUpdate($hash, 'CacheUsage', 0, 1);
            Log3($name, 3, "DbLog $name: Cache purged after exporting rows to $outfile.");
        }
        return;
    }
    elsif ($a[1] eq 'importCachefile') {
        my $cln;
        my $crows = 0;
        my $infile;
        my @row_array;
        readingsSingleUpdate($hash, "lastCachefile", "", 0);

        return if(IsDisabled($name) || $hash->{HELPER}{REOPEN_RUNS});                   # return wenn "reopen" mit Ablaufzeit gestartet ist oder disabled

        if (!$a[2]) {
            return "Wrong function-call. Use set <name> importCachefile <file> without directory (see attr expimpdir)." ;
        }
        else {
            $infile = $dir.$a[2];
        }

        if (open(FH, "$infile")) {
            binmode (FH);
        }
        else {
            return "could not open ".$infile.": ".$!;
        }

        while (<FH>) {
            my $row = $_;
            $row = DbLog_charfilter($row) if(AttrVal($name, "useCharfilter",0));
            push(@row_array, $row);
            $crows++;
        }
        close(FH);

        if(@row_array) {
            my $error = DbLog_Push($hash, 1, @row_array);
            if($error) {
                readingsSingleUpdate  ($hash, "lastCachefile", $infile." - Error - ".$!, 1);
                DbLog_setReadingstate ($hash, $error);
                Log3 $name, 5, "DbLog $name -> DbLog_Push Returncode: $error";
            }
            else {
                unless(rename($dir.$a[2], $dir."impdone_".$a[2])) {
                    Log3($name, 2, "DbLog $name: cachefile $infile couldn't be renamed after import !");
                }
                readingsSingleUpdate  ($hash, "lastCachefile", $infile." import successful", 1);
                DbLog_setReadingstate ($hash, $crows." cache rows processed from ".$infile);
                Log3($name, 3, "DbLog $name: $crows cache rows processed from $infile.");
            }
        }
        else {
            DbLog_setReadingstate ($hash, "no rows in ".$infile);
            Log3($name, 3, "DbLog $name: $infile doesn't contain any rows - no imports done.");
        }

        return;
    }
    elsif ($a[1] eq 'count') {
        Log3($name, 2, qq{DbLog $name - WARNING - "$a[1]" is outdated. Please consider use of DbRep "set <Name> countEntries" instead.});
        $dbh = _DbLog_ConnectNewDBH($hash);

        if(!$dbh) {
            Log3($name, 1, "DbLog $name: DBLog_Set - count - DB connect not possible");
            return;
        }
        else {
            Log3($name, 4, "DbLog $name: Records count requested.");
            my $c = $dbh->selectrow_array("SELECT count(*) FROM $history");
            readingsSingleUpdate($hash, 'countHistory', $c ,1);
            $c = $dbh->selectrow_array("SELECT count(*) FROM $current");
            readingsSingleUpdate($hash, 'countCurrent', $c ,1);
            $dbh->disconnect();

            InternalTimer(gettimeofday()+5, "DbLog_execmemcache", $hash, 0);
        }
    }
    elsif ($a[1] eq 'countNbl') {
        Log3($name, 2, qq{DbLog $name - WARNING - "$a[1]" is outdated. Please consider use of DbRep "set <Name> countEntries" instead.});
        if ($hash->{HELPER}{COUNT_PID} && $hash->{HELPER}{COUNT_PID}{pid} !~ m/DEAD/){
            $ret = "DbLog count already in progress. Please wait until the running process is finished.";
        }
        else {
            delete $hash->{HELPER}{COUNT_PID};
            $hash->{HELPER}{COUNT_PID} = BlockingCall("DbLog_countNbl","$name","DbLog_countNbl_finished");
            return;
        }
    }
    elsif ($a[1] eq 'deleteOldDays') {
        Log3($name, 2, qq{DbLog $name - WARNING - "$a[1]" is outdated. Please consider use of DbRep "set <Name> delEntries" instead.});
        Log3 ($name, 3, "DbLog $name -> Deletion of records older than $a[2] days in database $db requested");
        my ($c, $cmd);

        $dbh = _DbLog_ConnectNewDBH($hash);
        if(!$dbh) {
            Log3($name, 1, "DbLog $name: DBLog_Set - deleteOldDays - DB connect not possible");
            return;
        }
        else {
            $cmd = "delete from $history where TIMESTAMP < ";

            if ($hash->{MODEL} eq 'SQLITE')        { $cmd .= "datetime('now', '-$a[2] days')"; }
            elsif ($hash->{MODEL} eq 'MYSQL')      { $cmd .= "DATE_SUB(CURDATE(),INTERVAL $a[2] DAY)"; }
            elsif ($hash->{MODEL} eq 'POSTGRESQL') { $cmd .= "NOW() - INTERVAL '$a[2]' DAY"; }
            else  { $cmd = undef; $ret = 'Unknown database type. Maybe you can try userCommand anyway.'; }

            if(defined($cmd)) {
                $c = $dbh->do($cmd);
                $c = 0 if($c == 0E0);
                eval {$dbh->commit() if(!$dbh->{AutoCommit});};
                $dbh->disconnect();
                Log3 ($name, 3, "DbLog $name -> deleteOldDays finished. $c entries of database $db deleted.");
                readingsSingleUpdate($hash, 'lastRowsDeleted', $c ,1);
            }

            InternalTimer(gettimeofday()+5, "DbLog_execmemcache", $hash, 0);
        }
    }
    elsif ($a[1] eq 'deleteOldDaysNbl') {
        Log3($name, 2, qq{DbLog $name - WARNING - "$a[1]" is outdated. Please consider use of DbRep "set <Name> delEntries" instead.});
        if (defined $a[2] && $a[2] =~ /^\d+$/) {
            if ($hash->{HELPER}{DELDAYS_PID} && $hash->{HELPER}{DELDAYS_PID}{pid} !~ m/DEAD/) {
                $ret = "deleteOldDaysNbl already in progress. Please wait until the running process is finished.";
            } else {
                delete $hash->{HELPER}{DELDAYS_PID};
                $hash->{HELPER}{DELDAYS} = $a[2];
                Log3 ($name, 3, "DbLog $name -> Deletion of records older than $a[2] days in database $db requested");
                $hash->{HELPER}{DELDAYS_PID} = BlockingCall("DbLog_deldaysNbl","$name","DbLog_deldaysNbl_done");
                return;
            }
        }
        else {
            Log3($name, 1, "DbLog $name: deleteOldDaysNbl error, no <days> given.");
            $ret = "deleteOldDaysNbl error, no <days> given.";
        }
    }
    elsif ($a[1] eq 'userCommand') {
        Log3($name, 2, qq{DbLog $name - WARNING - "$a[1]" is outdated. Please consider use of DbRep "set <Name> sqlCmd" instead.});
        $dbh = _DbLog_ConnectNewDBH($hash);
        if(!$dbh) {
            Log3($name, 1, "DbLog $name: DBLog_Set - userCommand - DB connect not possible");
            return;
        }
        else {
            Log3($name, 4, "DbLog $name: userCommand execution requested.");
            my ($c, @cmd, $sql);
            @cmd = @a;
            shift(@cmd); shift(@cmd);
            $sql = join(" ",@cmd);
            readingsSingleUpdate($hash, 'userCommand', $sql, 1);
            $dbh->{RaiseError} = 1;
            $dbh->{PrintError} = 0;
            my $error;
            eval { $c = $dbh->selectrow_array($sql); };
            if($@) {
                $error = $@;
                Log3($name, 1, "DbLog $name: DBLog_Set - $error");
            }

            my $res = $error?$error:(defined($c))?$c:"no result";
            Log3($name, 4, "DbLog $name: DBLog_Set - userCommand - result: $res");
            readingsSingleUpdate($hash, 'userCommandResult', $res ,1);
            $dbh->disconnect();

            InternalTimer(gettimeofday()+5, "DbLog_execmemcache", $hash, 0);
        }
    }
    else { $ret = $usage; }

return $ret;
}

###############################################################################################
#
# Exrahieren des Filters aus der ColumnsSpec (gplot-Datei)
#
# Die grundlegend idee ist das jeder svg plot einen filter hat der angibt
# welches device und reading dargestellt wird so das der plot sich neu
# lädt wenn es ein entsprechendes event gibt.
#
# Parameter: Quell-Instanz-Name, und alle FileLog-Parameter, die diese Instanz betreffen.
# Quelle: http://forum.fhem.de/index.php/topic,40176.msg325200.html#msg325200
###############################################################################################
sub DbLog_regexpFn {
  my ($name, $filter) = @_;
  my $ret;

  my @a = split( ' ', $filter );
  for(my $i = 0; $i < int(@a); $i++) {
    my @fld = split(":", $a[$i]);

    $ret .= '|' if( $ret );
    no warnings 'uninitialized';            # Forum:74690, bug unitialized
    $ret .=  $fld[0] .'.'. $fld[1];
    use warnings;
  }

return $ret;
}

################################################################
# Parsefunktion, abhaengig vom Devicetyp
################################################################
sub DbLog_ParseEvent {
  my ($name,$device, $type, $event)= @_;
  my (@result,$reading,$value,$unit);

  # Splitfunktion der Eventquelle aufrufen (ab 2.9.1)
  ($reading, $value, $unit) = CallInstanceFn($device, "DbLog_splitFn", $event, $device);
  # undef bedeutet, Modul stellt keine DbLog_splitFn bereit
  if($reading) {
      return ($reading, $value, $unit);
  }

  # split the event into reading, value and unit
  # "day-temp: 22.0 (Celsius)" -> "day-temp", "22.0 (Celsius)"
  my @parts = split(/: /,$event, 2);
  $reading  = shift @parts;
  if(@parts == 2) {
    $value = $parts[0];
    $unit  = $parts[1];
  }
  else {
    $value = join(": ", @parts);
    $unit  = "";
  }

  # Log3 $name, 2, "DbLog $name -> ParseEvent - Event: $event, Reading: $reading, Value: $value, Unit: $unit";

  #default
  if(!defined($reading)) { $reading = ""; }
  if(!defined($value))   { $value   = ""; }
  if($value eq "") {                                                     # Default Splitting geändert 04.01.20 Forum: #106992
      if($event =~ /^.*:\s$/) {                                          # und 21.01.20 Forum: #106769
          $reading = (split(":", $event))[0];
      }
      else {
          $reading = "state";
          $value   = $event;
      }
  }

  #globales Abfangen von                                                  # changed in Version 4.12.5
  # - temperature
  # - humidity
  #if   ($reading =~ m(^temperature)) { $unit = "°C"; }                   # wenn reading mit temperature beginnt
  #elsif($reading =~ m(^humidity))    { $unit = "%"; }                    # wenn reading mit humidity beginnt
  if($reading =~ m(^humidity))    { $unit = "%"; }                        # wenn reading mit humidity beginnt


  # the interpretation of the argument depends on the device type
  # EMEM, M232Counter, M232Voltage return plain numbers
  if(($type eq "M232Voltage") ||
     ($type eq "M232Counter") ||
     ($type eq "EMEM")) {
  }
  #OneWire
  elsif(($type eq "OWMULTI")) {
      if(int(@parts) > 1) {
          $reading = "data";
          $value   = $event;
      }
      else {
          @parts = split(/\|/, AttrVal($device, $reading."VUnit", ""));
          $unit  = $parts[1] if($parts[1]);
          if(lc($reading) =~ m/temp/) {
              $value =~ s/ \(Celsius\)//;
              $value =~ s/([-\.\d]+).*/$1/;
              $unit  = "°C";
          } elsif (lc($reading) =~ m/(humidity|vwc)/) {
              $value =~ s/ \(\%\)//;
             $unit  = "%";
          }
      }
  }
  # Onewire
  elsif(($type eq "OWAD") || ($type eq "OWSWITCH")) {
      if(int(@parts)>1) {
        $reading = "data";
        $value   = $event;
      }
      else {
        @parts = split(/\|/, AttrVal($device, $reading."Unit", ""));
        $unit  = $parts[1] if($parts[1]);
      }
  }

  # ZWAVE
  elsif ($type eq "ZWAVE") {
      if ( $value =~/([-\.\d]+)\s([a-z].*)/i ) {
          $value = $1;
          $unit  = $2;
      }
  }

  # FBDECT
  elsif ($type eq "FBDECT") {
      if ( $value =~/([-\.\d]+)\s([a-z].*)/i ) {
          $value = $1;
          $unit  = $2;
      }
  }

  # MAX
  elsif(($type eq "MAX")) {
      $unit = "°C" if(lc($reading) =~ m/temp/);
      $unit = "%"   if(lc($reading) eq "valveposition");
  }

  # FS20
  elsif(($type eq "FS20") || ($type eq "X10")) {
      if($reading =~ m/^dim(\d+).*/o) {
          $value   = $1;
          $reading = "dim";
          $unit    = "%";
      } elsif(!defined($value) || $value eq "") {
          $value   = $reading;
          $reading = "data";
      }
  }

  # FHT
  elsif($type eq "FHT") {
      if($reading =~ m(-from[12]\ ) || $reading =~ m(-to[12]\ )) {
          @parts   = split(/ /,$event);
          $reading = $parts[0];
          $value   = $parts[1];
          $unit    = "";
      } elsif($reading =~ m(-temp)) {
          $value =~ s/ \(Celsius\)//; $unit= "°C";
      } elsif($reading =~ m(temp-offset)) {
          $value =~ s/ \(Celsius\)//; $unit= "°C";
      } elsif($reading =~ m(^actuator[0-9]*)) {
          if($value eq "lime-protection") {
              $reading = "actuator-lime-protection";
              undef $value;
          } elsif($value =~ m(^offset:)) {
              $reading = "actuator-offset";
              @parts   = split(/: /,$value);
              $value   = $parts[1];
              if(defined $value) {
                  $value =~ s/%//; $value = $value*1.; $unit = "%";
              }
          } elsif($value =~ m(^unknown_)) {
              @parts   = split(/: /,$value);
              $reading = "actuator-" . $parts[0];
              $value   = $parts[1];
              if(defined $value) {
                  $value =~ s/%//; $value = $value*1.; $unit = "%";
              }
          } elsif($value =~ m(^synctime)) {
              $reading = "actuator-synctime";
              undef $value;
          } elsif($value eq "test") {
              $reading = "actuator-test";
              undef $value;
          } elsif($value eq "pair") {
              $reading = "actuator-pair";
              undef $value;
          }
          else {
              $value =~ s/%//; $value = $value*1.; $unit = "%";
          }
      }
  }
  # KS300
  elsif($type eq "KS300") {
      if($event =~ m(T:.*))            { $reading = "data"; $value = $event; }
      elsif($event =~ m(avg_day))      { $reading = "data"; $value = $event; }
      elsif($event =~ m(avg_month))    { $reading = "data"; $value = $event; }
      elsif($reading eq "temperature") { $value   =~ s/ \(Celsius\)//; $unit = "°C"; }
      elsif($reading eq "wind")        { $value   =~ s/ \(km\/h\)//; $unit = "km/h"; }
      elsif($reading eq "rain")        { $value   =~ s/ \(l\/m2\)//; $unit = "l/m2"; }
      elsif($reading eq "rain_raw")    { $value   =~ s/ \(counter\)//; $unit = ""; }
      elsif($reading eq "humidity")    { $value   =~ s/ \(\%\)//; $unit = "%"; }
      elsif($reading eq "israining") {
        $value =~ s/ \(yes\/no\)//;
        $value =~ s/no/0/;
        $value =~ s/yes/1/;
      }
  }
  # HMS
  elsif($type eq "HMS" || $type eq "CUL_WS" || $type eq "OWTHERM") {
      if($event =~ m(T:.*)) {
          $reading = "data"; $value= $event;
      } elsif($reading eq "temperature") {
          $value =~ s/ \(Celsius\)//;
          $value =~ s/([-\.\d]+).*/$1/; #OWTHERM
          $unit  = "°C";
      } elsif($reading eq "humidity") {
          $value =~ s/ \(\%\)//; $unit= "%";
      } elsif($reading eq "battery") {
          $value =~ s/ok/1/;
          $value =~ s/replaced/1/;
          $value =~ s/empty/0/;
      }
  }
  # CUL_HM
  elsif ($type eq "CUL_HM") {
      $value =~ s/ \%$//;                           # remove trailing %
  }

  # BS
  elsif($type eq "BS") {
      if($event =~ m(brightness:.*)) {
          @parts   = split(/ /,$event);
          $reading = "lux";
          $value   = $parts[4]*1.;
          $unit    = "lux";
      }
  }

  # RFXTRX Lighting
  elsif($type eq "TRX_LIGHT") {
      if($reading =~ m/^level (\d+)/) {
          $value   = $1;
          $reading = "level";
      }
  }

  # RFXTRX Sensors
  elsif($type eq "TRX_WEATHER") {
      if($reading eq "energy_current") {
          $value =~ s/ W//;
      } elsif($reading eq "energy_total") {
          $value =~ s/ kWh//;
      } elsif($reading eq "battery") {
          if ($value =~ m/(\d+)\%/) {
              $value = $1;
          }
          else {
              $value = ($value eq "ok");
          }
      }
  }

  # Weather
  elsif($type eq "WEATHER") {
      if($event =~ m(^wind_condition)) {
          @parts = split(/ /,$event); # extract wind direction from event
          if(defined $parts[0]) {
              $reading = "wind_condition";
              $value   = "$parts[1] $parts[2] $parts[3]";
          }
      }
      if($reading eq "wind_condition")      { $unit = "km/h"; }
      elsif($reading eq "wind_chill")       { $unit = "°C"; }
      elsif($reading eq "wind_direction")   { $unit = ""; }
      elsif($reading =~ m(^wind))           { $unit = "km/h"; }      # wind, wind_speed
      elsif($reading =~ m(^temperature))    { $unit = "°C"; }        # wenn reading mit temperature beginnt
      elsif($reading =~ m(^humidity))       { $unit = "%"; }
      elsif($reading =~ m(^pressure))       { $unit = "hPa"; }
      elsif($reading =~ m(^pressure_trend)) { $unit = ""; }
  }

  # FHT8V
  elsif($type eq "FHT8V") {
      if($reading =~ m(valve)) {
          @parts   = split(/ /,$event);
          $reading = $parts[0];
          $value   = $parts[1];
          $unit    = "%";
      }
  }

  # Dummy
  elsif($type eq "DUMMY")  {
      if( $value eq "" ) {
          $reading = "data";
          $value   = $event;
      }
      $unit = "";
  }

  @result = ($reading,$value,$unit);

return @result;
}

##################################################################################################################
#
# Hauptroutine zum Loggen. Wird bei jedem Eventchange
# aufgerufen
#
##################################################################################################################
# Es werden nur die Events von Geräten verarbeitet die im Hash $hash->{NOTIFYDEV} gelistet sind (wenn definiert).
# Dadurch kann die Menge der Events verringert werden. In sub DbRep_Define angeben.
# Beispiele:
# $hash->{NOTIFYDEV} = "global";
# $hash->{NOTIFYDEV} = "global,Definition_A,Definition_B";

sub DbLog_Log {
  # $hash is my entry, $dev_hash is the entry of the changed device
  my ($hash, $dev_hash) = @_;
  my $name              = $hash->{NAME};
  my $dev_name          = $dev_hash->{NAME};
  my $dev_type          = uc($dev_hash->{TYPE});
  my $async             = AttrVal ($name, "asyncMode",                 0);
  my $clim              = AttrVal ($name, "cacheLimit",  $dblog_cachedef);
  my $ce                = AttrVal ($name, "cacheEvents",               0);
  
  return if(IsDisabled($name) || !$hash->{HELPER}{COLSET} || $init_done != 1);
  
  my ($net,$force);

  my $nst = [gettimeofday];                                                     # Notify-Routine Startzeit

  my $events = deviceEvents($dev_hash, AttrVal($name, "addStateEvent", 1));
  return if(!$events);

  my $max = int(@{$events});

  my $vb4show  = 0;
  my @vb4devs  = split(",", AttrVal ($name, 'verbose4Devs', ''));               # verbose4 Logs nur für Devices in Attr "verbose4Devs"
  if (!@vb4devs) {
      $vb4show = 1;
  }
  else {
      for (@vb4devs) {
          if($dev_name =~ m/$_/i) {
              $vb4show = 1;
              last;
          }
      }
  }

  if($vb4show && !$hash->{HELPER}{".RUNNING_PID"}) {
      Log3 $name, 4, "DbLog $name -> ################################################################";
      Log3 $name, 4, "DbLog $name -> ###              start of new Logcycle                       ###";
      Log3 $name, 4, "DbLog $name -> ################################################################";
      Log3 $name, 4, "DbLog $name -> number of events received: $max of device: $dev_name";
  }

  my $re                 = $hash->{REGEXP};
  my @row_array;
  my ($event,$reading,$value,$unit);
  my $ts_0               = TimeNow();                                            # timestamp in SQL format YYYY-MM-DD hh:mm:ss
  my $now                = gettimeofday();                                       # get timestamp in seconds since epoch
  my $DbLogExclude       = AttrVal($dev_name, "DbLogExclude",          undef);
  my $DbLogInclude       = AttrVal($dev_name, "DbLogInclude",          undef);
  my $DbLogValueFn       = AttrVal($dev_name, "DbLogValueFn",             "");
  my $DbLogSelectionMode = AttrVal($name,     "DbLogSelectionMode","Exclude");
  my $value_fn           = AttrVal($name,     "valueFn",                  "");

  if( $DbLogValueFn =~ m/^\s*(\{.*\})\s*$/s ) {                                  # Funktion aus Device spezifischer DbLogValueFn validieren
      $DbLogValueFn = $1;
  }
  else {
      $DbLogValueFn = '';
  }

  if( $value_fn =~ m/^\s*(\{.*\})\s*$/s ) {                                      # Funktion aus Attr valueFn validieren
      $value_fn = $1;
  }
  else {
      $value_fn = '';
  }

  eval {                                                                         # one Transaction
      for (my $i = 0; $i < $max; $i++) {
          my $next  = 0;
          my $event = $events->[$i];
          $event    = "" if(!defined($event));
          $event    = DbLog_charfilter($event) if(AttrVal($name, "useCharfilter",0));
          
          Log3 ($name, 4, "DbLog $name -> check Device: $dev_name , Event: $event") if($vb4show && !$hash->{HELPER}{".RUNNING_PID"});

          if($dev_name =~ m/^$re$/ || "$dev_name:$event" =~ m/^$re$/ || $DbLogSelectionMode eq 'Include') {
              my $timestamp = $ts_0;
              $timestamp    = $dev_hash->{CHANGETIME}[$i] if(defined($dev_hash->{CHANGETIME}[$i]));
              my $ctz       = AttrVal($name, 'convertTimezone', 'none');                                           # convert time zone
              
              if($ctz ne 'none') {
                  my $err;
                  
                  my $params = {
                      name      => $name,
                      dtstring  => $timestamp,
                      tzcurrent => 'local',
                      tzconv    => $ctz,
                      writelog  => 0
                  };

                  ($err, $timestamp) = convertTimeZone ($params);

                  if ($err) {
                      Log3 ($name, 1, "DbLog $name - ERROR while converting time zone: $err - exit log loop !");
                      last;
                  }
              }

              $event =~ s/\|/_ESC_/gxs;                                                                # escape Pipe "|"

              my @r = DbLog_ParseEvent($name,$dev_name, $dev_type, $event);
              $reading = $r[0];
              $value   = $r[1];
              $unit    = $r[2];
              if(!defined $reading)             {$reading = "";}
              if(!defined $value)               {$value = "";}
              if(!defined $unit || $unit eq "") {$unit = AttrVal("$dev_name", "unit", "");}

              $unit = DbLog_charfilter($unit) if(AttrVal($name, "useCharfilter",0));

              # Devices / Readings ausschließen durch Attribut "excludeDevs"
              # attr <device> excludeDevs [<devspec>#]<Reading1>,[<devspec>#]<Reading2>,[<devspec>#]<Reading..>
              my ($exc,@excldr,$ds,$rd,@exdvs);
              $exc = AttrVal($name, "excludeDevs", "");
              if($exc) {
                  $exc    =~ s/[\s\n]/,/g;
                  @excldr = split(",",$exc);

                  for my $excl (@excldr) {
                      ($ds,$rd) = split("#",$excl);
                      @exdvs    = devspec2array($ds);
                      
                      if(@exdvs) {
                          for my $ed (@exdvs) {
                              if($rd) {
                                  if("$dev_name:$reading" =~ m/^$ed:$rd$/) {
                                      Log3 $name, 4, "DbLog $name -> Device:Reading \"$dev_name:$reading\" global excluded from logging by attribute \"excludeDevs\" " if($vb4show && !$hash->{HELPER}{".RUNNING_PID"});
                                      $next = 1;
                                  }
                              }
                              else {
                                  if($dev_name =~ m/^$ed$/) {
                                      Log3 $name, 4, "DbLog $name -> Device \"$dev_name\" global excluded from logging by attribute \"excludeDevs\" " if($vb4show && !$hash->{HELPER}{".RUNNING_PID"});
                                      $next = 1;
                                  }
                              }
                          }
                      }
                  }
                  
                  next if($next);
              }

              Log3 $name, 5, "DbLog $name -> parsed Event: $dev_name , Event: $event" if($vb4show && !$hash->{HELPER}{".RUNNING_PID"});
              Log3 $name, 5, "DbLog $name -> DbLogExclude of \"$dev_name\": $DbLogExclude" if($vb4show && !$hash->{HELPER}{".RUNNING_PID"} && $DbLogExclude);
              Log3 $name, 5, "DbLog $name -> DbLogInclude of \"$dev_name\": $DbLogInclude" if($vb4show && !$hash->{HELPER}{".RUNNING_PID"} && $DbLogInclude);

              # Je nach DBLogSelectionMode muss das vorgegebene Ergebnis der Include-, bzw. Exclude-Pruefung
              # entsprechend unterschiedlich vorbelegt sein.
              # keine Readings loggen die in DbLogExclude explizit ausgeschlossen sind
              my $DoIt = 0;

              $DoIt = 1 if($DbLogSelectionMode =~ m/Exclude/ );

              if($DbLogExclude && $DbLogSelectionMode =~ m/Exclude/) {                                        # Bsp: "(temperature|humidity):300,battery:3600:force"
                  my @v1 = split(/,/, $DbLogExclude);

                  for (my $i=0; $i<int(@v1); $i++) {
                      my @v2 = split(/:/, $v1[$i]);
                      $DoIt  = 0 if(!$v2[1] && $reading =~ m,^$v2[0]$,);                                      # Reading matcht auf Regexp, kein MinIntervall angegeben

                      if(($v2[1] && $reading =~ m,^$v2[0]$,) && ($v2[1] =~ m/^(\d+)$/)) {                     # Regexp matcht und MinIntervall ist angegeben
                          my $lt = $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{TIME};
                          my $lv = $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{VALUE};
                          $lt    = 0  if(!$lt);
                          $lv    = "" if(!defined $lv);                                                       # Forum: #100344
                          $force = ($v2[2] && $v2[2] =~ /force/i) ? 1 : 0;                                    # Forum: #97148

                          if(($now-$lt < $v2[1]) && ($lv eq $value || $force)) {                              # innerhalb MinIntervall und LastValue=Value
                              $DoIt = 0;
                          }
                      }
                  }
              }

              # Hier ggf. zusätzlich noch dbLogInclude pruefen, falls bereits durch DbLogExclude ausgeschlossen
              # Im Endeffekt genau die gleiche Pruefung, wie fuer DBLogExclude, lediglich mit umgegkehrtem Ergebnis.
              if($DoIt == 0) {
                  if($DbLogInclude && ($DbLogSelectionMode =~ m/Include/)) {
                      my @v1 = split(/,/, $DbLogInclude);

                      for (my $i=0; $i<int(@v1); $i++) {
                          my @v2 = split(/:/, $v1[$i]);
                          $DoIt  = 1 if($reading =~ m,^$v2[0]$,);                                               # Reading matcht auf Regexp

                          if(($v2[1] && $reading =~ m,^$v2[0]$,) && ($v2[1] =~ m/^(\d+)$/)) {                   # Regexp matcht und MinIntervall ist angegeben
                              my $lt = $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{TIME};
                              my $lv = $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{VALUE};
                              $lt    = 0  if(!$lt);
                              $lv    = "" if(!defined $lv);                                                     # Forum: #100344
                              $force = ($v2[2] && $v2[2] =~ /force/i)?1:0;                                      # Forum: #97148

                              if(($now-$lt < $v2[1]) && ($lv eq $value || $force)) {                            # innerhalb MinIntervall und LastValue=Value
                                  $DoIt = 0;
                              }
                          }
                      }
                  }
              }
              
              next if($DoIt == 0);

              $DoIt = DbLog_checkDefMinInt($name,$dev_name,$now,$reading,$value);                              # check auf defaultMinInterval

              if ($DoIt) {
                  my $lastt = $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{TIME};                          # patch Forum:#111423
                  my $lastv = $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{VALUE};
                  
                  $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{TIME}  = $now;
                  $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{VALUE} = $value;

                  if($DbLogValueFn ne '') {                                                                    # Device spezifische DbLogValueFn-Funktion anwenden
                      my $TIMESTAMP     = $timestamp;
                      my $LASTTIMESTAMP = $lastt // 0;                                                         # patch Forum:#111423
                      my $DEVICE        = $dev_name;
                      my $EVENT         = $event;
                      my $READING       = $reading;
                      my $VALUE         = $value;
                      my $LASTVALUE     = $lastv // "";                                                        # patch Forum:#111423
                      my $UNIT          = $unit;
                      my $IGNORE        = 0;
                      my $CN            = " ";

                      eval $DbLogValueFn;
                      Log3 $name, 2, "DbLog $name -> error device \"$dev_name\" specific DbLogValueFn: ".$@ if($@);

                      if($IGNORE) {                                                                                        # aktueller Event wird nicht geloggt wenn $IGNORE=1 gesetzt
                          $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{TIME}  = $lastt if($lastt);                     # patch Forum:#111423
                          $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{VALUE} = $lastv if(defined $lastv);

                          if($vb4show && !$hash->{HELPER}{".RUNNING_PID"}) {
                              Log3 $name, 4, "DbLog $name -> Event ignored by device \"$dev_name\" specific DbLogValueFn - TS: $timestamp, Device: $dev_name, Type: $dev_type, Event: $event, Reading: $reading, Value: $value, Unit: $unit";
                          }

                          next;
                      }

                      my ($yyyy, $mm, $dd, $hh, $min, $sec) = ($TIMESTAMP =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
                      eval { my $epoch_seconds_begin = timelocal($sec, $min, $hh, $dd, $mm-1, $yyyy-1900); };

                      if (!$@) {
                          $timestamp = $TIMESTAMP;
                      }
                      else {
                          Log3 ($name, 2, "DbLog $name -> TIMESTAMP got from DbLogValueFn in $dev_name is invalid: $TIMESTAMP");
                      }

                      $reading   = $READING  if($READING ne '');
                      $value     = $VALUE    if(defined $VALUE);
                      $unit      = $UNIT     if(defined $UNIT);
                  }

                  if($value_fn ne '') {                                                                       # zentrale valueFn im DbLog-Device abarbeiten
                      my $TIMESTAMP     = $timestamp;
                      my $LASTTIMESTAMP = $lastt // 0;                                                        # patch Forum:#111423
                      my $DEVICE        = $dev_name;
                      my $DEVICETYPE    = $dev_type;
                      my $EVENT         = $event;
                      my $READING       = $reading;
                      my $VALUE         = $value;
                      my $LASTVALUE     = $lastv // "";                                                       # patch Forum:#111423
                      my $UNIT          = $unit;
                      my $IGNORE        = 0;
                      my $CN            = " ";

                      eval $value_fn;
                      Log3 $name, 2, "DbLog $name -> error valueFn: ".$@ if($@);

                      if($IGNORE) {                                                                                     # aktueller Event wird nicht geloggt wenn $IGNORE=1 gesetzt
                          $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{TIME}  = $lastt if($lastt);                  # patch Forum:#111423
                          $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{VALUE} = $lastv if(defined $lastv);

                          if($vb4show && !$hash->{HELPER}{".RUNNING_PID"}) {
                              Log3 $name, 4, "DbLog $name -> Event ignored by valueFn - TS: $timestamp, Device: $dev_name, Type: $dev_type, Event: $event, Reading: $reading, Value: $value, Unit: $unit";
                          }

                          next;
                      }

                      my ($yyyy, $mm, $dd, $hh, $min, $sec) = ($TIMESTAMP =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
                      eval { my $epoch_seconds_begin = timelocal($sec, $min, $hh, $dd, $mm-1, $yyyy-1900); };

                      if (!$@) {
                          $timestamp = $TIMESTAMP;
                      }
                      else {
                          Log3 ($name, 2, "DbLog $name -> Parameter TIMESTAMP got from valueFn is invalid: $TIMESTAMP");
                      }

                      $dev_name  = $DEVICE     if($DEVICE ne '');
                      $dev_type  = $DEVICETYPE if($DEVICETYPE ne '');
                      $reading   = $READING    if($READING ne '');
                      $value     = $VALUE      if(defined $VALUE);
                      $unit      = $UNIT       if(defined $UNIT);
                  }

                  # Daten auf maximale Länge beschneiden
                  ($dev_name,$dev_type,$event,$reading,$value,$unit) = DbLog_cutCol($hash,$dev_name,$dev_type,$event,$reading,$value,$unit);

                  my $row = ($timestamp."|".$dev_name."|".$dev_type."|".$event."|".$reading."|".$value."|".$unit);
                  Log3 $name, 4, "DbLog $name -> added event - Timestamp: $timestamp, Device: $dev_name, Type: $dev_type, Event: $event, Reading: $reading, Value: $value, Unit: $unit"
                                          if($vb4show && !$hash->{HELPER}{".RUNNING_PID"});

                  if($async) {                                                               # asynchoner non-blocking Mode
                      $data{DbLog}{$name}{cache}{index}++;                                   # Cache & CacheIndex für Events zum asynchronen Schreiben in DB
                      my $index = $data{DbLog}{$name}{cache}{index};
                      $data{DbLog}{$name}{cache}{memcache}{$index} = $row;

                      my $memcount = $data{DbLog}{$name}{cache}{memcache} ? scalar(keys %{$data{DbLog}{$name}{cache}{memcache}}) : 0;
                      my $mce      = $ce == 1 ? 1 : 0;

                      readingsSingleUpdate($hash, "CacheUsage", $memcount, $mce);

                      if($memcount >= $clim) {                                               # asynchrone Schreibroutine aufrufen wenn Füllstand des Cache erreicht ist
                          my $lmlr     = $hash->{HELPER}{LASTLIMITRUNTIME};
                          my $syncival = AttrVal($name, "syncInterval", 30);
                          if(!$lmlr || gettimeofday() > $lmlr+($syncival/2)) {
                              
                              Log3 ($name, 4, "DbLog $name -> Number of cache entries reached cachelimit $clim - start database sync.");
                              
                              DbLog_execmemcache ($hash);
                              $hash->{HELPER}{LASTLIMITRUNTIME} = gettimeofday();
                          }
                      }
                      $net = tv_interval($nst);                                              # Notify-Routine Laufzeit ermitteln
                  }
                  else {                                                                     # synchoner Mode
                      push(@row_array, $row);
                  }
              }
          }
      }
  };
  
  if(!$async) {
      if(@row_array) {                                                                       # synchoner Mode
          return if($hash->{HELPER}{REOPEN_RUNS});                                           # return wenn "reopen" mit Ablaufzeit gestartet ist

          my $error = DbLog_Push($hash, $vb4show, @row_array);
          Log3 ($name, 5, "DbLog $name -> DbLog_Push Returncode: $error") if($error && $vb4show);

          my $state = $error            ? $error     : 
                      IsDisabled($name) ? 'disabled' : 
                      'connected';
                      
          DbLog_setReadingstate ($hash, $state);

          $net = tv_interval($nst);                                                          # Notify-Routine Laufzeit ermitteln
      }
      else {
          if($hash->{HELPER}{SHUTDOWNSEQ}) {
              Log3 ($name, 2, "DbLog $name - no data for last database write cycle");
              _DbLog_finishDelayedShutdown ($hash);
          }
      }
  }

  if($net && AttrVal($name, 'showNotifyTime', 0)) {
      readingsSingleUpdate($hash, "notify_processing_time", sprintf("%.4f",$net), 1);
  }

return;
}

#################################################################################################
#
# check zentrale Angabe von defaultMinInterval für alle Devices/Readings
# (kein Überschreiben spezifischer Angaben von DbLogExclude / DbLogInclude in den Quelldevices)
#
#################################################################################################
sub DbLog_checkDefMinInt {
  my ($name,$dev_name,$now,$reading,$value) = @_;
  my $force;
  my $DoIt = 1;

  my $defminint = AttrVal($name, "defaultMinInterval", undef);
  return $DoIt if(!$defminint);                                           # Attribut "defaultMinInterval" nicht im DbLog gesetzt -> kein ToDo

  my $DbLogExclude = AttrVal($dev_name, "DbLogExclude", undef);
  my $DbLogInclude = AttrVal($dev_name, "DbLogInclude", undef);
  $defminint =~ s/[\s\n]/,/g;
  my @adef   = split(/,/, $defminint);

  my $inex = ($DbLogExclude?$DbLogExclude.",":"").($DbLogInclude?$DbLogInclude:"");

  if($inex) {                                                             # Quelldevice hat DbLogExclude und/oder DbLogInclude gesetzt
      my @ie = split(/,/, $inex);
      for (my $k=0; $k<int(@ie); $k++) {
          # Bsp. für das auszuwertende Element
          # "(temperature|humidity):300:force"
          my @rif = split(/:/, $ie[$k]);

          if($reading =~ m,^$rif[0]$, && $rif[1]) {                       # aktuelles Reading matcht auf Regexp und minInterval ist angegeben
              return $DoIt;                                               # Reading wurde bereits geprüft -> kein Überschreiben durch $defminint
          }
      }
  }

  for (my $l=0; $l<int(@adef); $l++) {
      my @adefelem = split("::", $adef[$l]);
      # Bsp. für ein defaulMInInterval Element:
      # device::interval[::force]
      my @dvs = devspec2array($adefelem[0]);
      if(@dvs) {
          for (@dvs) {
              if($dev_name =~ m,^$_$,) {                                               # aktuelles Device matcht auf Regexp
                  # device,reading wird gegen "defaultMinInterval" geprüft
                  # "defaultMinInterval" gilt für alle Readings des devices
                  my $lt = $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{TIME};
                  my $lv = $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{VALUE};
                  $lt    = 0  if(!$lt);
                  $lv    = "" if(!defined $lv);                                        # Forum: #100344
                  $force = ($adefelem[2] && $adefelem[2] =~ /force/i) ? 1 : 0;         # Forum: #97148

                  if(($now-$lt < $adefelem[1]) && ($lv eq $value || $force)) {
                      # innerhalb defaultMinInterval und LastValue=Value oder force-Option
                      # Log3 ($name, 1, "DbLog $name - defaulMInInterval - device \"$dev_name\", reading \"$reading\" inside of $adefelem[1] seconds (force: $force) -> don't log it !");
                      $DoIt = 0;
                      return $DoIt;
                  }
              }
          }
      }
  }
  # Log3 ($name, 1, "DbLog $name - defaulMInInterval - compare of \"$dev_name\", reading \"$reading\" successful -> log it !");

return $DoIt;
}

#################################################################################################
# Schreibroutine Einfügen Werte in DB im Synchronmode
#################################################################################################
sub DbLog_Push {
  my ($hash, $vb4show, @row_array) = @_;
  my $name      = $hash->{NAME};
  my $DbLogType = AttrVal($name, "DbLogType", "History");
  my $nsupk     = AttrVal($name, "noSupportPK", 0);
  my $tl        = AttrVal($name, "traceLevel", 0);
  my $tf        = AttrVal($name, "traceFlag", "SQL");
  my $bi        = AttrVal($name, "bulkInsert", 0);
  my $history   = $hash->{HELPER}{TH};
  my $current   = $hash->{HELPER}{TC};
  my $errorh    = "";
  my $error     = "";
  my $doins     = 0;                                                                  # Hilfsvariable, wenn "1" sollen inserts in Tabelle current erfolgen (updates schlugen fehl)
  my $dbh;

  my $nh = ($hash->{MODEL} ne 'SQLITE') ? 1 : 0;
  # Unterscheidung $dbh um Abbrüche in Plots (SQLite) zu vermeiden und
  # andererseite kein "MySQL-Server has gone away" Fehler
  if ($nh) {
      $dbh = _DbLog_ConnectNewDBH($hash);
      return if(!$dbh);
  }
  else {
      $dbh = $hash->{DBHP};
      eval {
          if ( !$dbh || not $dbh->ping ) {                                           # DB Session dead, try to reopen now !
              _DbLog_ConnectPush($hash,1);
          }
      };
      if ($@) {
          Log3($name, 1, "DbLog $name: DBLog_Push - DB Session dead! - $@");
          return $@;
      }
      else {
          $dbh = $hash->{DBHP};
      }
  }

  $dbh->{RaiseError} = 1;
  $dbh->{PrintError} = 0;

  if($tl) {                                                                         # Tracelevel setzen
      $dbh->{TraceLevel} = "$tl|$tf";
  }

  my ($useac,$useta) = DbLog_commitMode ($name, AttrVal($name, 'commitMode', 'basic_ta:on'));
  
  my $ac = $dbh->{AutoCommit} ? "ON" : "OFF";
  my $tm = $useta             ? "ON" : "OFF";

  Log3 $name, 4, "DbLog $name -> ################################################################";
  Log3 $name, 4, "DbLog $name -> ###         New database processing cycle - synchronous      ###";
  Log3 $name, 4, "DbLog $name -> ################################################################";
  Log3 $name, 4, "DbLog $name -> DbLogType is: $DbLogType";
  Log3 $name, 4, "DbLog $name -> AutoCommit mode: $ac, Transaction mode: $tm";
  Log3 $name, 4, "DbLog $name -> Insert mode: ".($bi?"Bulk":"Array");

  # check ob PK verwendet wird, @usepkx?Anzahl der Felder im PK:0 wenn kein PK, $pkx?Namen der Felder:none wenn kein PK
  my ($usepkh,$usepkc,$pkh,$pkc);
  
  if (!$nsupk) {
      my $params = {
          name     => $name,
          dbh      => $dbh,
          dbconn   => $hash->{dbconn},
          history  => $hash->{HELPER}{TH},
          current  => $hash->{HELPER}{TC}
      };
              
      ($usepkh,$usepkc,$pkh,$pkc) = DbLog_checkUsePK ($params);
  }
  else {
      Log3 ($name, 5, "DbLog $name -> Primary Key usage suppressed by attribute noSupportPK");
  }

  my (@timestamp,@device,@type,@event,@reading,@value,@unit);
  my (@timestamp_cur,@device_cur,@type_cur,@event_cur,@reading_cur,@value_cur,@unit_cur);
  my ($st,$sth_ih,$sth_ic,$sth_uc,$sqlins);
  my ($tuples, $rows);

  no warnings 'uninitialized';

  my $ceti = $#row_array+1;

  for my $row (@row_array) {
      my @a = split("\\|",$row);
      s/_ESC_/\|/gxs for @a;                                                              # escaped Pipe return to "|"
      push(@timestamp, "$a[0]");
      push(@device, "$a[1]");
      push(@type, "$a[2]");
      push(@event, "$a[3]");
      push(@reading, "$a[4]");
      push(@value, "$a[5]");
      push(@unit, "$a[6]");
      Log3 ($name, 4, "DbLog $name -> processing event Timestamp: $a[0], Device: $a[1], Type: $a[2], Event: $a[3], Reading: $a[4], Value: $a[5], Unit: $a[6]")
                             if($vb4show);
  }
  use warnings;

  if($bi) {
      #######################
      # Bulk-Insert
      #######################
      $st = [gettimeofday];               # SQL-Startzeit

      if (lc($DbLogType) =~ m(history)) {
          ########################################
          # insert history mit/ohne primary key
          if ($usepkh && $hash->{MODEL} eq 'MYSQL') {
              $sqlins = "INSERT IGNORE INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES ";
          }
          elsif ($usepkh && $hash->{MODEL} eq 'SQLITE') {
              $sqlins = "INSERT OR IGNORE INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES ";
          }
          elsif ($usepkh && $hash->{MODEL} eq 'POSTGRESQL') {
              $sqlins = "INSERT INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES ";
          }
          else {
              # ohne PK
              $sqlins = "INSERT INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES ";
          }

          no warnings 'uninitialized';
          for my $row (@row_array) {
              my @a = split("\\|",$row);
              s/_ESC_/\|/gxs for @a;                  # escaped Pipe return to "|"
              Log3 ($name, 5, "DbLog $name -> processing event Timestamp: $a[0], Device: $a[1], Type: $a[2], Event: $a[3], Reading: $a[4], Value: $a[5], Unit: $a[6]");
              $a[3] =~ s/'/''/g;                      # escape ' with ''
              $a[5] =~ s/'/''/g;                      # escape ' with ''
              $a[6] =~ s/'/''/g;                      # escape ' with ''
              $a[3] =~ s/\\/\\\\/g;                   # escape \ with \\
              $a[5] =~ s/\\/\\\\/g;                   # escape \ with \\
              $a[6] =~ s/\\/\\\\/g;                   # escape \ with \\
              $sqlins .= "('$a[0]','$a[1]','$a[2]','$a[3]','$a[4]','$a[5]','$a[6]'),";
          }
          use warnings;

          chop($sqlins);

          if ($usepkh && $hash->{MODEL} eq 'POSTGRESQL') {
              $sqlins .= " ON CONFLICT DO NOTHING";
          }

          eval { $dbh->begin_work() if($useta && $dbh->{AutoCommit}); };   # Transaktion wenn gewünscht und autocommit ein
          if ($@) {
              Log3($name, 2, "DbLog $name -> Error start transaction for $history - $@");
          }
          eval { $sth_ih = $dbh->prepare($sqlins);
                 if($tl) {
                     # Tracelevel setzen
                     $sth_ih->{TraceLevel} = "$tl|$tf";
                 }
                 my $ins_hist = $sth_ih->execute();
                 $ins_hist = 0 if($ins_hist eq "0E0");

                 if($ins_hist == $ceti) {
                     Log3 $name, 4, "DbLog $name -> $ins_hist of $ceti events inserted into table $history".($usepkh?" using PK on columns $pkh":"");
                 }
                 else {
                     if($usepkh) {
                         Log3 $name, 3, "DbLog $name -> INFO - ".$ins_hist." of $ceti events inserted into table $history due to PK on columns $pkh";
                     }
                     else {
                         Log3 $name, 2, "DbLog $name -> WARNING - only ".$ins_hist." of $ceti events inserted into table $history";
                     }
                 }
                 eval {$dbh->commit() if(!$dbh->{AutoCommit});};          # Data commit
                 if ($@) {
                     Log3($name, 2, "DbLog $name -> Error commit $history - $@");
                 }
                 else {
                     if(!$dbh->{AutoCommit}) {
                         Log3($name, 4, "DbLog $name -> insert table $history committed");
                     }
                     else {
                         Log3($name, 4, "DbLog $name -> insert table $history committed by autocommit");
                     }
                 }
          };

          if ($@) {
              $errorh = $@;
              Log3 $name, 2, "DbLog $name -> Error table $history - $errorh";
              eval {$dbh->rollback() if(!$dbh->{AutoCommit});};  # issue Turning on AutoCommit failed
              if ($@) {
                  Log3($name, 2, "DbLog $name -> Error rollback $history - $@");
              }
              else {
                  Log3($name, 4, "DbLog $name -> insert $history rolled back");
              }
          }
      }

      if (lc($DbLogType) =~ m(current)) {
          #################################################################
          # insert current mit/ohne primary key
          # Array-Insert wird auch bei Bulk verwendet weil im Bulk-Mode
          # die nicht upgedateten Sätze nicht identifiziert werden können
          if ($usepkc && $hash->{MODEL} eq 'MYSQL') {
              eval { $sth_ic = $dbh->prepare("INSERT IGNORE INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          }
          elsif ($usepkc && $hash->{MODEL} eq 'SQLITE') {
              eval { $sth_ic = $dbh->prepare("INSERT OR IGNORE INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          }
          elsif ($usepkc && $hash->{MODEL} eq 'POSTGRESQL') {
              eval { $sth_ic = $dbh->prepare("INSERT INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING"); };
          }
          else {
              # ohne PK
              eval { $sth_ic = $dbh->prepare("INSERT INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          }
          if ($@) {
              return $@;
          }

          if ($usepkc && $hash->{MODEL} eq 'MYSQL') {
              $sth_uc = $dbh->prepare("REPLACE INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?)");
          } elsif ($usepkc && $hash->{MODEL} eq 'SQLITE') {
              $sth_uc = $dbh->prepare("INSERT OR REPLACE INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?)");
          } elsif ($usepkc && $hash->{MODEL} eq 'POSTGRESQL') {
              $sth_uc = $dbh->prepare("INSERT INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?) ON CONFLICT ($pkc)
                                       DO UPDATE SET TIMESTAMP=EXCLUDED.TIMESTAMP, DEVICE=EXCLUDED.DEVICE, TYPE=EXCLUDED.TYPE, EVENT=EXCLUDED.EVENT, READING=EXCLUDED.READING,
                                       VALUE=EXCLUDED.VALUE, UNIT=EXCLUDED.UNIT");
          }
          else {
              $sth_uc = $dbh->prepare("UPDATE $current SET TIMESTAMP=?, TYPE=?, EVENT=?, VALUE=?, UNIT=? WHERE (DEVICE=?) AND (READING=?)");
          }

          if($tl) {
              # Tracelevel setzen
              $sth_uc->{TraceLevel} = "$tl|$tf";
              $sth_ic->{TraceLevel} = "$tl|$tf";
          }

          $sth_uc->bind_param_array(1, [@timestamp]);
          $sth_uc->bind_param_array(2, [@type]);
          $sth_uc->bind_param_array(3, [@event]);
          $sth_uc->bind_param_array(4, [@value]);
          $sth_uc->bind_param_array(5, [@unit]);
          $sth_uc->bind_param_array(6, [@device]);
          $sth_uc->bind_param_array(7, [@reading]);

          eval { $dbh->begin_work() if($useta && $dbh->{AutoCommit}); };   # Transaktion wenn gewünscht und autocommit ein
          if ($@) {
              Log3($name, 2, "DbLog $name -> Error start transaction for $current - $@");
          }
          eval {
              ($tuples, $rows) = $sth_uc->execute_array( { ArrayTupleStatus => \my @tuple_status } );
              my $nupd_cur = 0;
              for my $tuple (0..$#row_array) {
                  my $status = $tuple_status[$tuple];
                  $status = 0 if($status eq "0E0");
                  next if($status);         # $status ist "1" wenn update ok
                  Log3 $name, 4, "DbLog $name -> Failed to update in $current, try to insert - TS: $timestamp[$tuple], Device: $device[$tuple], Reading: $reading[$tuple], Status = $status";
                  push(@timestamp_cur, "$timestamp[$tuple]");
                  push(@device_cur, "$device[$tuple]");
                  push(@type_cur, "$type[$tuple]");
                  push(@event_cur, "$event[$tuple]");
                  push(@reading_cur, "$reading[$tuple]");
                  push(@value_cur, "$value[$tuple]");
                  push(@unit_cur, "$unit[$tuple]");
                  $nupd_cur++;
              }
              if(!$nupd_cur) {
                  Log3 $name, 4, "DbLog $name -> $ceti of $ceti events updated in table $current".($usepkc?" using PK on columns $pkc":"");
              }
              else {
                  Log3 $name, 4, "DbLog $name -> $nupd_cur of $ceti events not updated and try to insert into table $current".($usepkc?" using PK on columns $pkc":"");
                  $doins = 1;
              }

              if ($doins) {
                  # events die nicht in Tabelle current updated wurden, werden in current neu eingefügt
                  $sth_ic->bind_param_array(1, [@timestamp_cur]);
                  $sth_ic->bind_param_array(2, [@device_cur]);
                  $sth_ic->bind_param_array(3, [@type_cur]);
                  $sth_ic->bind_param_array(4, [@event_cur]);
                  $sth_ic->bind_param_array(5, [@reading_cur]);
                  $sth_ic->bind_param_array(6, [@value_cur]);
                  $sth_ic->bind_param_array(7, [@unit_cur]);

                  ($tuples, $rows) = $sth_ic->execute_array( { ArrayTupleStatus => \my @tuple_status } );
                  my $nins_cur = 0;
                  for my $tuple (0..$#device_cur) {
                      my $status = $tuple_status[$tuple];
                      $status = 0 if($status eq "0E0");
                      next if($status);         # $status ist "1" wenn insert ok
                      Log3 $name, 3, "DbLog $name -> Insert into $current rejected - TS: $timestamp[$tuple], Device: $device_cur[$tuple], Reading: $reading_cur[$tuple], Status = $status";
                      $nins_cur++;
                  }
                  if(!$nins_cur) {
                      Log3 $name, 4, "DbLog $name -> ".($#device_cur+1)." of ".($#device_cur+1)." events inserted into table $current ".($usepkc?" using PK on columns $pkc":"");
                  }
                  else {
                      Log3 $name, 4, "DbLog $name -> ".($#device_cur+1-$nins_cur)." of ".($#device_cur+1)." events inserted into table $current".($usepkc?" using PK on columns $pkc":"");
                  }
              }
              eval {$dbh->commit() if(!$dbh->{AutoCommit});};    # issue Turning on AutoCommit failed
              if ($@) {
                  Log3($name, 2, "DbLog $name -> Error commit table $current - $@");
              }
              else {
                  if(!$dbh->{AutoCommit}) {
                      Log3($name, 4, "DbLog $name -> insert / update table $current committed");
                  }
                  else {
                      Log3($name, 4, "DbLog $name -> insert / update table $current committed by autocommit");
                  }
              }
          };
      }
  }
  else {
      #######################
      # Array-Insert
      #######################

      $st = [gettimeofday];               # SQL-Startzeit

      if (lc($DbLogType) =~ m(history)) {
          ########################################
          # insert history mit/ohne primary key
          if ($usepkh && $hash->{MODEL} eq 'MYSQL') {
              eval { $sth_ih = $dbh->prepare("INSERT IGNORE INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          }
          elsif ($usepkh && $hash->{MODEL} eq 'SQLITE') {
              eval { $sth_ih = $dbh->prepare("INSERT OR IGNORE INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          }
          elsif ($usepkh && $hash->{MODEL} eq 'POSTGRESQL') {
              eval { $sth_ih = $dbh->prepare("INSERT INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING"); };
          }
          else {
              # ohne PK
              eval { $sth_ih = $dbh->prepare("INSERT INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          }
          if ($@) {
              return $@;
          }

          if($tl) {
              # Tracelevel setzen
              $sth_ih->{TraceLevel} = "$tl|$tf";
          }

          $sth_ih->bind_param_array(1, [@timestamp]);
          $sth_ih->bind_param_array(2, [@device]);
          $sth_ih->bind_param_array(3, [@type]);
          $sth_ih->bind_param_array(4, [@event]);
          $sth_ih->bind_param_array(5, [@reading]);
          $sth_ih->bind_param_array(6, [@value]);
          $sth_ih->bind_param_array(7, [@unit]);

          eval { $dbh->begin_work() if($useta && $dbh->{AutoCommit}); };   # Transaktion wenn gewünscht und autocommit ein
          if ($@) {
              Log3($name, 2, "DbLog $name -> Error start transaction for $history - $@");
          }
          eval {
              ($tuples, $rows) = $sth_ih->execute_array( { ArrayTupleStatus => \my @tuple_status } );
              my $nins_hist = 0;
              for my $tuple (0..$#row_array) {
                  my $status = $tuple_status[$tuple];
                  $status = 0 if($status eq "0E0");
                  next if($status);         # $status ist "1" wenn insert ok
                  Log3 $name, 3, "DbLog $name -> Insert into $history rejected".($usepkh?" (possible PK violation) ":" ")."- TS: $timestamp[$tuple], Device: $device[$tuple], Event: $event[$tuple]";
                  my $nlh = ($timestamp[$tuple]."|".$device[$tuple]."|".$type[$tuple]."|".$event[$tuple]."|".$reading[$tuple]."|".$value[$tuple]."|".$unit[$tuple]);
                  $nins_hist++;
              }
              if(!$nins_hist) {
                  Log3 $name, 4, "DbLog $name -> $ceti of $ceti events inserted into table $history".($usepkh?" using PK on columns $pkh":"");
              }
              else {
                  if($usepkh) {
                      Log3 $name, 3, "DbLog $name -> INFO - ".($ceti-$nins_hist)." of $ceti events inserted into table $history due to PK on columns $pkh";
                  }
                  else {
                      Log3 $name, 2, "DbLog $name -> WARNING - only ".($ceti-$nins_hist)." of $ceti events inserted into table $history";
                  }
              }
              eval {$dbh->commit() if(!$dbh->{AutoCommit});};          # Data commit
              if ($@) {
                  Log3($name, 2, "DbLog $name -> Error commit $history - $@");
              }
              else {
                  if(!$dbh->{AutoCommit}) {
                      Log3($name, 4, "DbLog $name -> insert table $history committed");
                  }
                  else {
                      Log3($name, 4, "DbLog $name -> insert table $history committed by autocommit");
                  }
              }
          };

          if ($@) {
              $errorh = $@;
              Log3 $name, 2, "DbLog $name -> Error table $history - $errorh";
              eval {$dbh->rollback() if(!$dbh->{AutoCommit});};  # issue Turning on AutoCommit failed
              if ($@) {
                  Log3($name, 2, "DbLog $name -> Error rollback $history - $@");
              }
              else {
                  Log3($name, 4, "DbLog $name -> insert $history rolled back");
              }
          }
      }

      if (lc($DbLogType) =~ m(current)) {
          ########################################
          # insert current mit/ohne primary key
          if ($usepkc && $hash->{MODEL} eq 'MYSQL') {
              eval { $sth_ic = $dbh->prepare("INSERT IGNORE INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          }
          elsif ($usepkc && $hash->{MODEL} eq 'SQLITE') {
              eval { $sth_ic = $dbh->prepare("INSERT OR IGNORE INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          }
          elsif ($usepkc && $hash->{MODEL} eq 'POSTGRESQL') {
              eval { $sth_ic = $dbh->prepare("INSERT INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING"); };
          }
          else {
              # ohne PK
              eval { $sth_ic = $dbh->prepare("INSERT INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          }
          if ($@) {
              return $@;
          }

          if ($usepkc && $hash->{MODEL} eq 'MYSQL') {
              $sth_uc = $dbh->prepare("REPLACE INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?)");
          }
          elsif ($usepkc && $hash->{MODEL} eq 'SQLITE') {
              $sth_uc = $dbh->prepare("INSERT OR REPLACE INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?)");
          }
          elsif ($usepkc && $hash->{MODEL} eq 'POSTGRESQL') {
              $sth_uc = $dbh->prepare("INSERT INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?) ON CONFLICT ($pkc)
                                       DO UPDATE SET TIMESTAMP=EXCLUDED.TIMESTAMP, DEVICE=EXCLUDED.DEVICE, TYPE=EXCLUDED.TYPE, EVENT=EXCLUDED.EVENT, READING=EXCLUDED.READING,
                                       VALUE=EXCLUDED.VALUE, UNIT=EXCLUDED.UNIT");
          }
          else {
              $sth_uc = $dbh->prepare("UPDATE $current SET TIMESTAMP=?, TYPE=?, EVENT=?, VALUE=?, UNIT=? WHERE (DEVICE=?) AND (READING=?)");
          }

          if($tl) {
              # Tracelevel setzen
              $sth_uc->{TraceLevel} = "$tl|$tf";
              $sth_ic->{TraceLevel} = "$tl|$tf";
          }

          $sth_uc->bind_param_array(1, [@timestamp]);
          $sth_uc->bind_param_array(2, [@type]);
          $sth_uc->bind_param_array(3, [@event]);
          $sth_uc->bind_param_array(4, [@value]);
          $sth_uc->bind_param_array(5, [@unit]);
          $sth_uc->bind_param_array(6, [@device]);
          $sth_uc->bind_param_array(7, [@reading]);

          eval { $dbh->begin_work() if($useta && $dbh->{AutoCommit}); };   # Transaktion wenn gewünscht und autocommit ein
          if ($@) {
              Log3($name, 2, "DbLog $name -> Error start transaction for $current - $@");
          }
          eval {
              ($tuples, $rows) = $sth_uc->execute_array( { ArrayTupleStatus => \my @tuple_status } );
              my $nupd_cur = 0;
              for my $tuple (0..$#row_array) {
                  my $status = $tuple_status[$tuple];
                  $status = 0 if($status eq "0E0");
                  next if($status);         # $status ist "1" wenn update ok
                  Log3 $name, 4, "DbLog $name -> Failed to update in $current, try to insert - TS: $timestamp[$tuple], Device: $device[$tuple], Reading: $reading[$tuple], Status = $status";
                  push(@timestamp_cur, "$timestamp[$tuple]");
                  push(@device_cur, "$device[$tuple]");
                  push(@type_cur, "$type[$tuple]");
                  push(@event_cur, "$event[$tuple]");
                  push(@reading_cur, "$reading[$tuple]");
                  push(@value_cur, "$value[$tuple]");
                  push(@unit_cur, "$unit[$tuple]");
                  $nupd_cur++;
              }
              if(!$nupd_cur) {
                  Log3 $name, 4, "DbLog $name -> $ceti of $ceti events updated in table $current".($usepkc?" using PK on columns $pkc":"");
              }
              else {
                  Log3 $name, 4, "DbLog $name -> $nupd_cur of $ceti events not updated and try to insert into table $current".($usepkc?" using PK on columns $pkc":"");
                  $doins = 1;
              }

              if ($doins) {
                  # events die nicht in Tabelle current updated wurden, werden in current neu eingefügt
                  $sth_ic->bind_param_array(1, [@timestamp_cur]);
                  $sth_ic->bind_param_array(2, [@device_cur]);
                  $sth_ic->bind_param_array(3, [@type_cur]);
                  $sth_ic->bind_param_array(4, [@event_cur]);
                  $sth_ic->bind_param_array(5, [@reading_cur]);
                  $sth_ic->bind_param_array(6, [@value_cur]);
                  $sth_ic->bind_param_array(7, [@unit_cur]);

                  ($tuples, $rows) = $sth_ic->execute_array( { ArrayTupleStatus => \my @tuple_status } );
                  my $nins_cur = 0;
                  for my $tuple (0..$#device_cur) {
                      my $status = $tuple_status[$tuple];
                      $status = 0 if($status eq "0E0");
                      next if($status);         # $status ist "1" wenn insert ok
                      Log3 $name, 3, "DbLog $name -> Insert into $current rejected - TS: $timestamp[$tuple], Device: $device_cur[$tuple], Reading: $reading_cur[$tuple], Status = $status";
                      $nins_cur++;
                  }
                  if(!$nins_cur) {
                      Log3 $name, 4, "DbLog $name -> ".($#device_cur+1)." of ".($#device_cur+1)." events inserted into table $current ".($usepkc?" using PK on columns $pkc":"");
                  }
                  else {
                      Log3 $name, 4, "DbLog $name -> ".($#device_cur+1-$nins_cur)." of ".($#device_cur+1)." events inserted into table $current".($usepkc?" using PK on columns $pkc":"");
                  }
              }
              eval {$dbh->commit() if(!$dbh->{AutoCommit});};    # issue Turning on AutoCommit failed
              if ($@) {
                  Log3($name, 2, "DbLog $name -> Error commit table $current - $@");
              }
              else {
                  if(!$dbh->{AutoCommit}) {
                      Log3($name, 4, "DbLog $name -> insert / update table $current committed");
                  }
                  else {
                      Log3($name, 4, "DbLog $name -> insert / update table $current committed by autocommit");
                  }
              }
          };
      }
  }

  # SQL-Laufzeit ermitteln
  my $rt = tv_interval($st);

  if(AttrVal($name, "showproctime", 0)) {
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt));
      readingsEndUpdate($hash, 0);
  }

  if ($errorh) {
      $error = $errorh;
  }
  if(!$tl) {
      # Trace ausschalten
      $dbh->{TraceLevel} = "0";
      $sth_ih->{TraceLevel} = "0";
  }

  $dbh->{RaiseError} = 0;
  $dbh->{PrintError} = 1;
  $dbh->disconnect if ($nh);

return Encode::encode_utf8($error);
}

#################################################################
# SubProcess - Hauptprozess gestartet durch DbLog_SBP_Init
# liest Daten vom Parentprozess mit
# $subprocess->readFromParent()
#
# my $parent = $subprocess->parent();
#################################################################
sub DbLog_SBP_onRun {
  my $subprocess = shift;
  my $name       = $subprocess->{name};
  
  while (1) {
      my $json = $subprocess->readFromParent();
    
      if(defined($json)) {
          my $memc        = eval { decode_json($json) };
          
          my $dbconn      = $memc->{dbconn};
          my $dbuser      = $memc->{dbuser};
          my $dbpassword  = $memc->{dbpassword};
          my $DbLogType   = $memc->{DbLogType};
          my $nsupk       = $memc->{nsupk};
          my $tl          = $memc->{tl};
          my $tf          = $memc->{tf};
          my $bi          = $memc->{bi};
          my $utf8        = $memc->{utf8};
          my $verbose     = $memc->{verbose};
          my $history     = $memc->{history};
          my $current     = $memc->{current};
          my $model       = $memc->{model};
          my $cm          = $memc->{cm};
          my $cdata       = $memc->{cdata};                                 # Log Daten, z.B.: 3399 => 2022-11-29 09:33:32|SolCast|SOLARFORECAST||nextCycletime|09:33:47|
   
          my $errorh      = 0;
          my $error       = q{};
          my $doins       = 0;                                              # Hilfsvariable, wenn "1" sollen inserts in Tabelle current erfolgen (updates schlugen fehl)
          my $rowlback    = 0;                                              # Eventliste für Rückgabe wenn Fehler
          my $dbh;
          my $params;
          
          my @row_array;
          my $ret;
          my $retjson;
          my $rowhref; 
          
          $attr{$name}{verbose} = $verbose;                                 # verbose Level übergeben

          ######################################################################################################
          
          Log3 ($name, 5, "DbLog $name -> DbLogType is: $DbLogType");

          my $bst = [gettimeofday];                                                         # Background-Startzeit

          my ($useac,$useta) = DbLog_commitMode ($name, $cm);
          
          $params = {
              name       => $name,
              dbconn     => $dbconn,
              dbuser     => $dbuser,
              dbpassword => $dbpassword,
              utf8       => $utf8,
              useac      => $useac,
              model      => $model
          };
          
          ($error, $dbh) = _DbLog_SBP_onRun_connectDB ($params);
          
          if ($error) {
              Log3 ($name, 2, "DbLog $name - Error: $error");
              
              $ret = {
                  name     => $name,
                  error    => $error,
                  ot       => 0,
                  rowlback => $cdata                                                        # Rückgabe alle übergebenen Log-Daten 
              };
              
              $retjson = eval { encode_json($ret) };
              $subprocess->writeToParent($retjson);
              next;
          }

          if($tl) {                                                                         # Tracelevel setzen
              $dbh->{TraceLevel} = "$tl|$tf";
          }

          my $ac = $dbh->{AutoCommit} ? "ON" : "OFF";
          my $tm = $useta             ? "ON" : "OFF";
          
          Log3 ($name, 4, "DbLog $name -> AutoCommit mode: $ac, Transaction mode: $tm");
          Log3 ($name, 4, "DbLog $name -> Insert mode: ".($bi ? "Bulk" : "Array"));

          # check ob PK verwendet wird, @usepkx?Anzahl der Felder im PK:0 wenn kein PK, $pkx?Namen der Felder:none wenn kein PK
          my ($usepkh,$usepkc,$pkh,$pkc);
          
          if (!$nsupk) {
              $params = {
                  name     => $name,
                  dbh      => $dbh,
                  dbconn   => $dbconn,
                  history  => $history,
                  current  => $current
              };
              
              ($usepkh,$usepkc,$pkh,$pkc) = DbLog_checkUsePK ($params);
          }
          else {
              Log3 ($name, 5, "DbLog $name -> Primary Key usage suppressed by attribute noSupportPK");
          }
          
          my $ceti = scalar keys %{$cdata};

          my (@timestamp,@device,@type,@event,@reading,@value,@unit);
          my (@timestamp_cur,@device_cur,@type_cur,@event_cur,@reading_cur,@value_cur,@unit_cur);
          my ($st,$sth_ih,$sth_ic,$sth_uc,$sqlins);
          my ($tuples, $rows);

          no warnings 'uninitialized';
          
          for my $key (sort {$a<=>$b} keys %{$cdata}) {
              my $row = $cdata->{$key};
              my @a   = split("\\|",$row);
              s/_ESC_/\|/gxs for @a;                    # escaped Pipe back to "|"
              
              push(@timestamp, "$a[0]");
              push(@device, "$a[1]");
              push(@type, "$a[2]");
              push(@event, "$a[3]");
              push(@reading, "$a[4]");
              push(@value, "$a[5]");
              push(@unit, "$a[6]");
              
              Log3 ($name, 5, "DbLog $name -> processing event Timestamp: $a[0], Device: $a[1], Type: $a[2], Event: $a[3], Reading: $a[4], Value: $a[5], Unit: $a[6]");
          }
          
          use warnings;

          if($bi) {
              #######################
              # Bulk-Insert
              #######################
              $st = [gettimeofday];               # SQL-Startzeit

              if (lc($DbLogType) =~ m(history)) {
                  ########################################
                  # insert history mit/ohne primary key
                  if ($usepkh && $model eq 'MYSQL') {
                      $sqlins = "INSERT IGNORE INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES ";
                  }
                  elsif ($usepkh && $model eq 'SQLITE') {
                      $sqlins = "INSERT OR IGNORE INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES ";
                  }
                  elsif ($usepkh && $model eq 'POSTGRESQL') {
                      $sqlins = "INSERT INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES ";
                  }
                  else {                           # ohne PK
                      $sqlins = "INSERT INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES ";
                  }
                  
                  no warnings 'uninitialized';

                  for my $key (sort {$a<=>$b} keys %{$cdata}) {
                      my $row = $cdata->{$key};
                      my @a   = split("\\|",$row);
                      s/_ESC_/\|/gxs for @a;                  # escaped Pipe back to "|"
                      
                      Log3 ($name, 5, "DbLog $name -> processing event Timestamp: $a[0], Device: $a[1], Type: $a[2], Event: $a[3], Reading: $a[4], Value: $a[5], Unit: $a[6]");
                      
                      $a[3] =~ s/'/''/g;                      # escape ' with ''
                      $a[5] =~ s/'/''/g;                      # escape ' with ''
                      $a[6] =~ s/'/''/g;                      # escape ' with ''
                      $a[3] =~ s/\\/\\\\/g;                   # escape \ with \\
                      $a[5] =~ s/\\/\\\\/g;                   # escape \ with \\
                      $a[6] =~ s/\\/\\\\/g;                   # escape \ with \\
                      
                      $sqlins .= "('$a[0]','$a[1]','$a[2]','$a[3]','$a[4]','$a[5]','$a[6]'),";
                  }

                  use warnings;

                  chop($sqlins);

                  if ($usepkh && $model eq 'POSTGRESQL') {
                      $sqlins .= " ON CONFLICT DO NOTHING";
                  }

                  eval { $dbh->begin_work() if($useta && $dbh->{AutoCommit}); };   # Transaktion wenn gewünscht und autocommit ein
                  if ($@) {
                      Log3 ($name, 2, "DbLog $name -> Error start transaction for $history - $@");
                  }

                  eval { $sth_ih = $dbh->prepare($sqlins);
                         
                         if($tl) {                                                 # Tracelevel setzen
                             $sth_ih->{TraceLevel} = "$tl|$tf";
                         }
                         
                         my $ins_hist = $sth_ih->execute();
                         $ins_hist    = 0 if($ins_hist eq "0E0");

                         if($ins_hist == $ceti) {
                             Log3 ($name, 4, "DbLog $name -> $ins_hist of $ceti events inserted into table $history".($usepkh ? " using PK on columns $pkh" : ""));
                         }
                         else {
                             if($usepkh) {
                                 Log3 ($name, 3, "DbLog $name -> INFO - ".$ins_hist." of $ceti events inserted into table $history due to PK on columns $pkh");
                             }
                             else {
                                 Log3 ($name, 2, "DbLog $name -> WARNING - only ".$ins_hist." of $ceti events inserted into table $history");
                             }
                         }
                         
                         eval {$dbh->commit() if(!$dbh->{AutoCommit});};          # Data commit
                         if ($@) {
                             Log3 ($name, 2, "DbLog $name -> Error commit $history - $@");
                         }
                         else {
                             if(!$dbh->{AutoCommit}) {
                                 Log3 ($name, 4, "DbLog $name -> insert table $history committed");
                             }
                             else {
                                 Log3 ($name, 4, "DbLog $name -> insert table $history committed by autocommit");
                             }
                         }
                  };

                  if ($@) {
                      $errorh = $@;
                      
                      Log3 ($name, 2, "DbLog $name -> Error table $history - $errorh");
                      
                      $dbh->disconnect();
                      
                      $rowlback = $cdata if($useta);                        # nicht gespeicherte Datensätze nur zurück geben wenn Transaktion ein
                  
                      $ret = {
                          name     => $name,
                          error    => $@,
                          ot       => 0,
                          rowlback => $rowlback                                             
                      };
                      
                      $retjson = eval { encode_json($ret) };
                      $subprocess->writeToParent($retjson);
                      next;
                  }
              }

              if (lc($DbLogType) =~ m(current)) {
                  #################################################################
                  # insert current mit/ohne primary key
                  # Array-Insert wird auch bei Bulk verwendet weil im Bulk-Mode
                  # die nicht upgedateten Sätze nicht identifiziert werden können
                  if ($usepkc && $model eq 'MYSQL') {
                      eval { $sth_ic = $dbh->prepare("INSERT IGNORE INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
                  }
                  elsif ($usepkc && $model eq 'SQLITE') {
                      eval { $sth_ic = $dbh->prepare("INSERT OR IGNORE INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
                  }
                  elsif ($usepkc && $model eq 'POSTGRESQL') {
                      eval { $sth_ic = $dbh->prepare("INSERT INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING"); };
                  }
                  else {                              # ohne PK
                      eval { $sth_ic = $dbh->prepare("INSERT INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
                  }
                  if ($@) {
                      Log3 ($name, 2, "DbLog $name - Error: $@");
                      
                      $dbh->disconnect();

                      $ret = {
                          name     => $name,
                          error    => $@,
                          ot       => 0,
                          rowlback => $rowlback
                      };
                      
                      $retjson = eval { encode_json($ret) };
                      $subprocess->writeToParent($retjson);
                      next;
                  }

                  if ($usepkc && $model eq 'MYSQL') {
                      $sth_uc = $dbh->prepare("REPLACE INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?)");
                  }
                  elsif ($usepkc && $model eq 'SQLITE') {
                      $sth_uc = $dbh->prepare("INSERT OR REPLACE INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?)");
                  }
                  elsif ($usepkc && $model eq 'POSTGRESQL') {
                      $sth_uc = $dbh->prepare("INSERT INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?) ON CONFLICT ($pkc)
                                               DO UPDATE SET TIMESTAMP=EXCLUDED.TIMESTAMP, DEVICE=EXCLUDED.DEVICE, TYPE=EXCLUDED.TYPE, EVENT=EXCLUDED.EVENT, READING=EXCLUDED.READING,
                                               VALUE=EXCLUDED.VALUE, UNIT=EXCLUDED.UNIT");
                  }
                  else {
                      $sth_uc = $dbh->prepare("UPDATE $current SET TIMESTAMP=?, TYPE=?, EVENT=?, VALUE=?, UNIT=? WHERE (DEVICE=?) AND (READING=?)");
                  }

                  if($tl) {                                                                  # Tracelevel setzen
                      $sth_uc->{TraceLevel} = "$tl|$tf";
                      $sth_ic->{TraceLevel} = "$tl|$tf";
                  }

                  $sth_uc->bind_param_array(1, [@timestamp]);
                  $sth_uc->bind_param_array(2, [@type]);
                  $sth_uc->bind_param_array(3, [@event]);
                  $sth_uc->bind_param_array(4, [@value]);
                  $sth_uc->bind_param_array(5, [@unit]);
                  $sth_uc->bind_param_array(6, [@device]);
                  $sth_uc->bind_param_array(7, [@reading]);

                  eval { $dbh->begin_work() if($useta && $dbh->{AutoCommit}); };             # Transaktion wenn gewünscht und autocommit ein
                  if ($@) {
                      Log3 ($name, 2, "DbLog $name -> Error start transaction for $current - $@");
                  }
                  
                  eval {
                      ($tuples, $rows) = $sth_uc->execute_array( { ArrayTupleStatus => \my @tuple_status } );
                      my $nupd_cur = 0;
                      
                      for my $tuple (0..$ceti-1) {
                          my $status = $tuple_status[$tuple];
                          $status    = 0 if($status eq "0E0");
                          next if($status);                                                  # $status ist "1" wenn update ok
                          
                          Log3 ($name, 4, "DbLog $name -> Failed to update in $current, try to insert - TS: $timestamp[$tuple], Device: $device[$tuple], Reading: $reading[$tuple], Status = $status");
                          
                          push(@timestamp_cur, "$timestamp[$tuple]");
                          push(@device_cur, "$device[$tuple]");
                          push(@type_cur, "$type[$tuple]");
                          push(@event_cur, "$event[$tuple]");
                          push(@reading_cur, "$reading[$tuple]");
                          push(@value_cur, "$value[$tuple]");
                          push(@unit_cur, "$unit[$tuple]");
                          
                          $nupd_cur++;
                      }
                      if(!$nupd_cur) {
                          Log3 ($name, 4, "DbLog $name -> $ceti of $ceti events updated in table $current".($usepkc ? " using PK on columns $pkc" : ""));
                      }
                      else {
                          Log3 ($name, 4, "DbLog $name -> $nupd_cur of $ceti events not updated and try to insert into table $current".($usepkc ? " using PK on columns $pkc" : ""));
                          $doins = 1;
                      }

                      if ($doins) {                                            # events die nicht in Tabelle current updated wurden, werden in current neu eingefügt
                          $sth_ic->bind_param_array(1, [@timestamp_cur]);
                          $sth_ic->bind_param_array(2, [@device_cur]);
                          $sth_ic->bind_param_array(3, [@type_cur]);
                          $sth_ic->bind_param_array(4, [@event_cur]);
                          $sth_ic->bind_param_array(5, [@reading_cur]);
                          $sth_ic->bind_param_array(6, [@value_cur]);
                          $sth_ic->bind_param_array(7, [@unit_cur]);

                          ($tuples, $rows) = $sth_ic->execute_array( { ArrayTupleStatus => \my @tuple_status } );
                          my $nins_cur = 0;
                          
                          for my $tuple (0..$#device_cur) {
                              my $status = $tuple_status[$tuple];
                              $status    = 0 if($status eq "0E0");
                              next if($status);                                # $status ist "1" wenn insert ok
                              
                              Log3 ($name, 3, "DbLog $name -> Insert into $current rejected - TS: $timestamp[$tuple], Device: $device_cur[$tuple], Reading: $reading_cur[$tuple], Status = $status");
                              
                              $nins_cur++;
                          }
                          if(!$nins_cur) {
                              Log3 ($name, 4, "DbLog $name -> ".($#device_cur+1)." of ".($#device_cur+1)." events inserted into table $current ".($usepkc ? " using PK on columns $pkc" : ""));
                          }
                          else {
                              Log3 ($name, 4, "DbLog $name -> ".($#device_cur+1-$nins_cur)." of ".($#device_cur+1)." events inserted into table $current".($usepkc ? " using PK on columns $pkc" : ""));
                          }
                      }
                      eval {$dbh->commit() if(!$dbh->{AutoCommit});};    # issue Turning on AutoCommit failed
                      if ($@) {
                          Log3 ($name, 2, "DbLog $name -> Error commit table $current - $@");
                      }
                      else {
                          if(!$dbh->{AutoCommit}) {
                              Log3 ($name, 4, "DbLog $name -> insert / update table $current committed");
                          }
                          else {
                              Log3 ($name, 4, "DbLog $name -> insert / update table $current committed by autocommit");
                          }
                      }
                  };
              }
          }
          else {
              #######################
              # Array-Insert
              #######################

              $st = [gettimeofday];               # SQL-Startzeit

              if (lc($DbLogType) =~ m(history)) {
                  ########################################
                  # insert history mit/ohne primary key
                  if ($usepkh && $model eq 'MYSQL') {
                      eval { $sth_ih = $dbh->prepare("INSERT IGNORE INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
                  }
                  elsif ($usepkh && $model eq 'SQLITE') {
                      eval { $sth_ih = $dbh->prepare("INSERT OR IGNORE INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
                  }
                  elsif ($usepkh && $model eq 'POSTGRESQL') {
                      eval { $sth_ih = $dbh->prepare("INSERT INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING"); };
                  }
                  else {                                       # ohne PK
                      eval { $sth_ih = $dbh->prepare("INSERT INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
                  }
                  if ($@) {                                    # Eventliste zurückgeben wenn z.B. Disk I/O Error bei SQLITE
                      Log3 ($name, 2, "DbLog $name - Error: $@");
                      
                      $dbh->disconnect();
                      
                      $ret = {
                          name     => $name,
                          error    => $@,
                          ot       => 0,
                          rowlback => $cdata
                      };
                      
                      $retjson = eval { encode_json($ret) };
                      $subprocess->writeToParent($retjson);
                      next;
                  }

                  if($tl) {                                                        # Tracelevel setzen
                      $sth_ih->{TraceLevel} = "$tl|$tf";
                  }

                  $sth_ih->bind_param_array (1, [@timestamp]);
                  $sth_ih->bind_param_array (2, [@device]);
                  $sth_ih->bind_param_array (3, [@type]);
                  $sth_ih->bind_param_array (4, [@event]);
                  $sth_ih->bind_param_array (5, [@reading]);
                  $sth_ih->bind_param_array (6, [@value]);
                  $sth_ih->bind_param_array (7, [@unit]);

                  eval { $dbh->begin_work() if($useta && $dbh->{AutoCommit}); };   # Transaktion wenn gewünscht und autocommit ein
                  if ($@) {
                      Log3 ($name, 2, "DbLog $name -> Error start transaction for $history - $@");
                  }
                  
                  eval {
                      ($tuples, $rows) = $sth_ih->execute_array( { ArrayTupleStatus => \my @tuple_status } );
                      my $nins_hist = 0;
                      my @n2hist;
                      
                      for my $tuple (0..$ceti-1) {
                          my $status = $tuple_status[$tuple];
                          $status    = 0 if($status eq "0E0");
                          next if($status);                                            # $status ist "1" wenn insert ok
                          
                          Log3 ($name, 3, "DbLog $name -> Insert into $history rejected".($usepkh?" (possible PK violation) ":" ")."- TS: $timestamp[$tuple], Device: $device[$tuple], Event: $event[$tuple]");
                          
                          my $nlh = ($timestamp[$tuple]."|".$device[$tuple]."|".$type[$tuple]."|".$event[$tuple]."|".$reading[$tuple]."|".$value[$tuple]."|".$unit[$tuple]);
                          push(@n2hist, "$nlh");
                          $nins_hist++;
                      }
                      
                      if(!$nins_hist) {
                          Log3 ($name, 4, "DbLog $name -> $ceti of $ceti events inserted into table $history".($usepkh ? " using PK on columns $pkh" : ""));
                      }
                      else {
                          if($usepkh) {
                              Log3 ($name, 3, "DbLog $name -> INFO - ".($ceti-$nins_hist)." of $ceti events inserted into table history due to PK on columns $pkh");
                          }
                          else {
                              Log3 ($name, 2, "DbLog $name -> WARNING - only ".($ceti-$nins_hist)." of $ceti events inserted into table $history");
                          }
                          
                          my $bkey = 1;
                          
                          for my $line (@n2hist) {
                              $line =~ s/\|/_ESC_/gxs;                                                       # escape Pipe "|"
                              $rowhref->{$bkey} = $line;
                              $bkey++;
                          }
                      }
                      eval {$dbh->commit() if(!$dbh->{AutoCommit});};                                        # Data commit
                      if ($@) {
                          Log3 ($name, 2, "DbLog $name -> Error commit $history - $@");
                      }
                      else {
                          if(!$dbh->{AutoCommit}) {
                              Log3 ($name, 4, "DbLog $name -> insert table $history committed");
                          }
                          else {
                              Log3 ($name, 4, "DbLog $name -> insert table $history committed by autocommit");
                          }
                      }
                  };

                  if ($@) {
                      $errorh = $@;
                      
                      Log3 ($name, 2, "DbLog $name -> Error table $history - $errorh");
                      
                      $error    = $errorh;
                      $rowlback = $rowhref if($useta);              # nicht gespeicherte Datensätze nur zurück geben wenn Transaktion ein
                  }
              }

              if (lc($DbLogType) =~ m(current)) {
                  ########################################
                  # insert current mit/ohne primary key
                  if ($usepkc && $model eq 'MYSQL') {
                      eval { $sth_ic = $dbh->prepare("INSERT IGNORE INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
                  }
                  elsif ($usepkc && $model eq 'SQLITE') {
                      eval { $sth_ic = $dbh->prepare("INSERT OR IGNORE INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
                  }
                  elsif ($usepkc && $model eq 'POSTGRESQL') {
                      eval { $sth_ic = $dbh->prepare("INSERT INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING"); };
                  }
                  else {                         # ohne PK
                      eval { $sth_ic = $dbh->prepare("INSERT INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
                  }
                  if ($@) {                      # Eventliste zurückgeben wenn z.B. Disk I/O error bei SQLITE
                      Log3 ($name, 2, "DbLog $name - Error: $@");

                      $dbh->disconnect();
                      
                      $ret = {
                          name     => $name,
                          error    => $@,
                          ot       => 0,
                          rowlback => $rowlback
                      };
                      
                      $retjson = eval { encode_json($ret) };
                      $subprocess->writeToParent($retjson);
                      next;
                  }

                  if ($usepkc && $model eq 'MYSQL') {
                      $sth_uc = $dbh->prepare("REPLACE INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?)");
                  } 
                  elsif ($usepkc && $model eq 'SQLITE') {
                      $sth_uc = $dbh->prepare("INSERT OR REPLACE INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?)");
                  } 
                  elsif ($usepkc && $model eq 'POSTGRESQL') {
                      $sth_uc = $dbh->prepare("INSERT INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?) ON CONFLICT ($pkc)
                                               DO UPDATE SET TIMESTAMP=EXCLUDED.TIMESTAMP, DEVICE=EXCLUDED.DEVICE, TYPE=EXCLUDED.TYPE, EVENT=EXCLUDED.EVENT, READING=EXCLUDED.READING,
                                               VALUE=EXCLUDED.VALUE, UNIT=EXCLUDED.UNIT");
                  }
                  else {
                      $sth_uc = $dbh->prepare("UPDATE $current SET TIMESTAMP=?, TYPE=?, EVENT=?, VALUE=?, UNIT=? WHERE (DEVICE=?) AND (READING=?)");
                  }

                  if($tl) {                                         # Tracelevel setzen
                      $sth_uc->{TraceLevel} = "$tl|$tf";
                      $sth_ic->{TraceLevel} = "$tl|$tf";
                  }

                  $sth_uc->bind_param_array(1, [@timestamp]);
                  $sth_uc->bind_param_array(2, [@type]);
                  $sth_uc->bind_param_array(3, [@event]);
                  $sth_uc->bind_param_array(4, [@value]);
                  $sth_uc->bind_param_array(5, [@unit]);
                  $sth_uc->bind_param_array(6, [@device]);
                  $sth_uc->bind_param_array(7, [@reading]);

                  eval { $dbh->begin_work() if($useta && $dbh->{AutoCommit}); };   # Transaktion wenn gewünscht und autocommit ein
                  if ($@) {
                      Log3 ($name, 2, "DbLog $name -> Error start transaction for $current - $@");
                  }
                  
                  eval {
                      ($tuples, $rows) = $sth_uc->execute_array( { ArrayTupleStatus => \my @tuple_status } );
                      my $nupd_cur = 0;
                      
                      for my $tuple (0..$ceti-1) {
                          my $status = $tuple_status[$tuple];
                          $status    = 0 if($status eq "0E0");
                          next if($status);                                          # $status ist "1" wenn update ok
                          
                          Log3 ($name, 4, "DbLog $name -> Failed to update in $current, try to insert - TS: $timestamp[$tuple], Device: $device[$tuple], Reading: $reading[$tuple], Status = $status");
                          
                          push(@timestamp_cur, "$timestamp[$tuple]");
                          push(@device_cur, "$device[$tuple]");
                          push(@type_cur, "$type[$tuple]");
                          push(@event_cur, "$event[$tuple]");
                          push(@reading_cur, "$reading[$tuple]");
                          push(@value_cur, "$value[$tuple]");
                          push(@unit_cur, "$unit[$tuple]");
                          $nupd_cur++;
                      }
                      
                      if(!$nupd_cur) {
                          Log3 ($name, 4, "DbLog $name -> $ceti of $ceti events updated in table $current".($usepkc ? " using PK on columns $pkc" : ""));
                      }
                      else {
                          Log3 ($name, 4, "DbLog $name -> $nupd_cur of $ceti events not updated and try to insert into table $current".($usepkc ? " using PK on columns $pkc" : ""));
                          $doins = 1;
                      }

                      if ($doins) {                                   # events die nicht in Tabelle current updated wurden, werden in current neu eingefügt
                          $sth_ic->bind_param_array(1, [@timestamp_cur]);
                          $sth_ic->bind_param_array(2, [@device_cur]);
                          $sth_ic->bind_param_array(3, [@type_cur]);
                          $sth_ic->bind_param_array(4, [@event_cur]);
                          $sth_ic->bind_param_array(5, [@reading_cur]);
                          $sth_ic->bind_param_array(6, [@value_cur]);
                          $sth_ic->bind_param_array(7, [@unit_cur]);

                          ($tuples, $rows) = $sth_ic->execute_array( { ArrayTupleStatus => \my @tuple_status } );
                          my $nins_cur     = 0;
                          
                          for my $tuple (0..$#device_cur) {
                              my $status = $tuple_status[$tuple];
                              $status    = 0 if($status eq "0E0");
                              next if($status);                                 # $status ist "1" wenn insert ok
                              
                              Log3 ($name, 3, "DbLog $name -> Insert into $current rejected - TS: $timestamp[$tuple], Device: $device_cur[$tuple], Reading: $reading_cur[$tuple], Status = $status");
                              
                              $nins_cur++;
                          }
                          
                          if(!$nins_cur) {
                              Log3 ($name, 4, "DbLog $name -> ".($#device_cur+1)." of ".($#device_cur+1)." events inserted into table $current ".($usepkc ? " using PK on columns $pkc" : ""));
                          }
                          else {
                              Log3 ($name, 4, "DbLog $name -> ".($#device_cur+1-$nins_cur)." of ".($#device_cur+1)." events inserted into table $current".($usepkc ? " using PK on columns $pkc" : ""));
                          }
                      }
                      
                      eval {$dbh->commit() if(!$dbh->{AutoCommit});};    # issue Turning on AutoCommit failed
                      if ($@) {
                          Log3 ($name, 2, "DbLog $name -> Error commit table $current - $@");
                      }
                      else {
                          if(!$dbh->{AutoCommit}) {
                              Log3 ($name, 4, "DbLog $name -> insert / update table $current committed");
                          }
                          else {
                              Log3 ($name, 4, "DbLog $name -> insert / update table $current committed by autocommit");
                          }
                      }
                  };
              }
          }

          $dbh->disconnect();

          my $rt  = tv_interval($st);                                     # SQL-Laufzeit ermitteln
          my $brt = tv_interval($bst);                                    # Background-Laufzeit ermitteln
          my $ot  = $rt.",".$brt;

          $ret = {
              name     => $name,
              error    => $error,
              ot       => $ot,
              rowlback => $rowlback
          };
          
          $retjson = eval { encode_json($ret) };
          $subprocess->writeToParent($retjson);          
        
          # hier schreiben wir etwas an den übergeordneten Prozess
          # dies wird über die globale Select-Schleife empfangen
          # und in der ReadFn ausgewertet.
          # $subprocess->writeToParent($json);
      }
  }
  
return;
}

###################################################################################
#               neue Datenbankverbindung im SubProcess
###################################################################################
sub _DbLog_SBP_onRun_connectDB {                                                  
  my $paref      = shift;
  
  my $name       = $paref->{name};
  my $dbconn     = $paref->{dbconn};
  my $dbuser     = $paref->{dbuser};
  my $dbpassword = $paref->{dbpassword};
  my $utf8       = $paref->{utf8};
  my $useac      = $paref->{useac};
  my $model      = $paref->{model};
  
  my $dbh = '';
  my $err = '';
  
  eval { if (!$useac) {
             $dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError          => 0, 
                                                                        RaiseError          => 1, 
                                                                        AutoCommit          => 0, 
                                                                        AutoInactiveDestroy => 1
                                                                      }
                                ); 1;
         }
         elsif ($useac == 1) {
             $dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError          => 0, 
                                                                        RaiseError          => 1, 
                                                                        AutoCommit          => 1, 
                                                                        AutoInactiveDestroy => 1
                                                                      }
                                ); 1;
         }
         else {                                                                                          # Server default
             $dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, 
                                                                        RaiseError => 1, 
                                                                        AutoInactiveDestroy => 1
                                                                      }
                                ); 1;
         }
      }
      or do { $err = $@;
              Log3 ($name, 2, "DbLog $name - Error: $err");
              return $err;
            };
            
  if($utf8) {
      if($model eq "MYSQL") {
          $dbh->{mysql_enable_utf8} = 1;
          $dbh->do('set names "UTF8"');
      }
      
      if($model eq "SQLITE") {
        $dbh->do('PRAGMA encoding="UTF-8"');
      }
  }

return ($err, $dbh);
}

#####################################################
##   Subprocess wird beendet
#####################################################
sub DbLog_SBP_onExit {
    my $subprocess = shift;
    my $name       = $subprocess->{name};
    
    Log3 ($name, 1, "DbLog $name - SubProcess EXITED!");
    
return;
}

#####################################################
##   Subprocess initialisieren
#####################################################
sub DbLog_SBP_Init {          
  my $hash = shift;
  my $name = $hash->{NAME};
  
  return if($hash->{SBP_PID});

  $hash->{".fhem"}{subprocess} = undef;
  
  my $subprocess = SubProcess->new( { onRun  => \&DbLog_SBP_onRun, 
                                      onExit => \&DbLog_SBP_onExit 
                                    } 
                                  );
  
  # Hier eigenen Variablen wie folgt festlegen:
  $subprocess->{name} = $name;
  
  # Sobald der Unterprozess gestartet ist, leben Eltern- und Kindprozess
  # in getrennten Prozessen und können keine Daten mehr gemeinsam nutzen - die Änderung von Variablen im
  # Elternprozess haben keine Auswirkungen auf die Variablen im Kindprozess und umgekehrt.
  
  my $pid = $subprocess->run();
  
  if (!defined $pid) {
      Log3 ($name, 1, "DbLog $name - Cannot create subprocess for asynchronous operation");
      DbLog_SBP_CleanUp     ($hash);
      DbLog_setReadingstate ($hash, "Cannot create subprocess for asynchronous operation");
      return;
  }
  
  Log3 ($name, 2, qq{DbLog $name - Subprocess "$pid" initialized ... ready for non-blocking operation});

  $hash->{".fhem"}{subprocess} = $subprocess;
  $hash->{FD}                  = fileno $subprocess->child();
  
  delete($readyfnlist{"$name.$pid"});   
  
  $selectlist{"$name.$pid"} = $hash;
  $hash->{SBP_PID}          = $pid;
  $hash->{SBP_STATE}        = 'running';

return;
}

#####################################################
##   Subprocess beenden
#####################################################
sub DbLog_SBP_CleanUp {
  my $hash = shift;
  my $name = $hash->{NAME};
  
  my $subprocess = $hash->{".fhem"}{subprocess};
  return if(!defined $subprocess);
  
  my $pid = $subprocess->pid();
  return if(!$pid);
  
  Log3 ($name, 2, qq{DbLog $name - stopping Subprocess "$pid" ...});
  
  #$subprocess->terminate();
  #$subprocess->wait();
  
  kill 'SIGKILL', $pid;
  waitpid($pid, 0);
  
  Log3 ($name, 2, qq{DbLog $name - Subprocess "$pid" stopped});

  delete($selectlist{"$name.$pid"});
  delete $hash->{FD};
  delete $hash->{SBP_PID};

  $hash->{SBP_STATE} = "Cleaned";

return;
}

################################################################################
# called from the global loop, when the select for hash->{FD} reports data
# geschrieben durch "onRun" Funktion
################################################################################
sub DbLog_SBP_Read {
  my $hash = shift;
  #my $name = $hash->{NAME};
  
  my $subprocess = $hash->{".fhem"}{subprocess};
  
  # hier lesen wir aus der globalen Select-Schleife, was
  # in der onRun-Funktion geschrieben wurde
  my $retjson = $subprocess->readFromChild();
  
  if(defined($retjson)) {
      my $ret = eval { decode_json($retjson) };
      
      return if(defined($ret) && ref($ret) ne "HASH");
      
      my $name     = $ret->{name};
      my $error    = $ret->{error};
      my $ot       = $ret->{ot};
      my $rowlback = $ret->{rowlback};
      
      # Log3 ($name, 1, "DbLog $name - DbLog_SBP_Read: name: $name, error: $error, ot: $ot, rowlback: ".Dumper $rowlback);
      
      my $asyncmode  = AttrVal($name, "asyncMode", undef);
      my $memcount;
      
      if($rowlback) {                                                                         # one Transaction
          eval {
              for my $key (sort {$a <=>$b} keys %{$rowlback}) {                               # Cache & CacheIndex für Events zum asynchronen Schreiben in DB
                  $data{DbLog}{$name}{cache}{index}++;
                  my $index = $data{DbLog}{$name}{cache}{index};
                  $data{DbLog}{$name}{cache}{memcache}{$index} = $rowlback->{$key};
              }
              
              $memcount = scalar(keys %{$data{DbLog}{$name}{cache}{memcache}});
          };
      }
      
      if($asyncmode) {
          $memcount = $data{DbLog}{$name}{cache}{memcache} ? scalar(keys %{$data{DbLog}{$name}{cache}{memcache}}) : 0;
          readingsSingleUpdate($hash, 'CacheUsage', $memcount, 0);
      }
      
      if(AttrVal($name, 'showproctime', 0) && $ot) {
          my ($rt,$brt) = split(",", $ot);
          readingsBeginUpdate ($hash);
          readingsBulkUpdate  ($hash, 'background_processing_time', sprintf("%.4f",$brt));
          readingsBulkUpdate  ($hash, 'sql_processing_time',        sprintf("%.4f",$rt));
          readingsEndUpdate   ($hash, 1);
      }

      my $state = $error            ? $error     : 
                  IsDisabled($name) ? 'disabled' : 
                  'connected';
                  
      DbLog_setReadingstate ($hash, $state);      
      
      delete $hash->{HELPER}{".RUNNING_PID"};
      delete $hash->{HELPER}{LASTLIMITRUNTIME} if(!$error);
      
      if ($hash->{HELPER}{SHUTDOWNSEQ}) {
          Log3 ($name, 2, "DbLog $name - Last database write cycle done");
          _DbLog_finishDelayedShutdown ($hash);
      }
  }
  
return;
}

#################################################################################################
# MemCache auswerten und Schreibroutine asynchron und non-blocking aufrufen
#################################################################################################
sub DbLog_execmemcache {
  my $hash       = shift;
  my $name       = $hash->{NAME};
  my $syncival   = AttrVal($name, "syncInterval", 30              );
  my $clim       = AttrVal($name, "cacheLimit",   $dblog_cachedef );
  my $async      = AttrVal($name, "asyncMode",    0               );
  my $ce         = AttrVal($name, "cacheEvents",  0               );
  my $timeout    = AttrVal($name, "timeout",      86400           );
  my $DbLogType  = AttrVal($name, "DbLogType",    "History"       );

  my $dbconn     = $hash->{dbconn};
  my $dbuser     = $hash->{dbuser};
  my $dbpassword = $attr{"sec$name"}{secret};
  my $dolog      = 1;

  my ($dbh,$error);

  RemoveInternalTimer($hash, "DbLog_execmemcache");

  if($init_done != 1) {
      InternalTimer(gettimeofday()+5, "DbLog_execmemcache", $hash, 0);
      return;
  }
  
  ## Subprocess initialisieren
  ###############################################
  DbLog_SBP_Init ($hash);
  
  if ($hash->{SBP_PID}) {
      my $pid     = $hash->{SBP_PID};
      my $alive   = 0;
      
      if (kill 0, $pid) {
          $alive = 1;
          $hash->{SBP_STATE} = 'running';
      }
      else {
          $hash->{SBP_STATE} = "dead (".$hash->{SBP_PID}.")";
          delete $hash->{SBP_PID};
      }
      
      if (!$alive) {
          DbLog_SBP_Init ($hash);
          return if (!$hash->{SBP_PID});
      }
  }
  else {
      return;
  }
  
  my $subprocess = $hash->{".fhem"}{subprocess};
  ################################################

  my $memcount = $data{DbLog}{$name}{cache}{memcache} ? scalar(keys %{$data{DbLog}{$name}{cache}{memcache}}) : 0;
  
  my $params   = {
      hash          => $hash,
      clim          => $clim,
      memcount      => $memcount
  };

  if(!$async || IsDisabled($name) || $hash->{HELPER}{REOPEN_RUNS}) {                         # return wenn "reopen" mit Zeitangabe läuft, oder kein asynchroner Mode oder wenn disabled
      DbLog_writeFileIfCacheOverflow ($params);                                              # Cache exportieren bei Overflow
      return;
  }

  if($hash->{HELPER}{".RUNNING_PID"}) {   
      if ($hash->{HELPER}{".RUNNING_PID"}{pid} =~ m/DEAD/) {
          delete $hash->{HELPER}{".RUNNING_PID"};                                            # tote PID's löschen
      }
      else {
          $dolog = 0;          
      }
  }
  if($hash->{HELPER}{REDUCELOG_PID} && $hash->{HELPER}{REDUCELOG_PID}{pid} =~ m/DEAD/) {
      delete $hash->{HELPER}{REDUCELOG_PID};
  }
  if($hash->{HELPER}{DELDAYS_PID} && $hash->{HELPER}{DELDAYS_PID}{pid} =~ m/DEAD/) {
      delete $hash->{HELPER}{DELDAYS_PID};
  }

  if($hash->{MODEL} eq "SQLITE") {                                                           # bei SQLite Sperrverwaltung Logging wenn andere schreibende Zugriffe laufen
      if($hash->{HELPER}{DELDAYS_PID}) {
          $error = "deleteOldDaysNbl is running - resync at NextSync";
          $dolog = 0;
      }
      if($hash->{HELPER}{REDUCELOG_PID}) {
          $error = "reduceLogNbl is running - resync at NextSync";
          $dolog = 0;
      }
      if($hash->{HELPER}{".RUNNING_PID"}) {
          $error = "Commit already running - resync at NextSync";
          $dolog = 0;
      }
  }

  my $mce = $ce == 2 ? 1 : 0;

  readingsSingleUpdate($hash, "CacheUsage", $memcount, $mce);

  if($memcount && $dolog) {
      Log3 ($name, 4, "DbLog $name -> ################################################################");
      Log3 ($name, 4, "DbLog $name -> ###      New database processing cycle - asynchronous        ###");
      Log3 ($name, 4, "DbLog $name -> ################################################################");
      Log3 ($name, 4, "DbLog $name -> MemCache contains $memcount entries to process");
      Log3 ($name, 4, "DbLog $name -> DbLogType is: $DbLogType");

      my $wrotefile = DbLog_writeFileIfCacheOverflow ($params);                             # Cache exportieren bei Overflow
      return if($wrotefile);
      
      my $memc;
      for my $key (sort(keys %{$data{DbLog}{$name}{cache}{memcache}})) {
          Log3 ($name, 5, "DbLog $name -> MemCache contains: ".$data{DbLog}{$name}{cache}{memcache}{$key});

          $memc->{cdata}{$key} = delete $data{DbLog}{$name}{cache}{memcache}{$key};        # Subprocess Daten, z.B.:  2022-11-29 09:33:32|SolCast|SOLARFORECAST||nextCycletime|09:33:47|
      }

      undef $data{DbLog}{$name}{cache}{memcache};                                          # sicherheitshalber Memory freigeben: https://perlmaven.com/undef-on-perl-arrays-and-hashes , bzw. https://www.effectiveperlprogramming.com/2018/09/undef-a-scalar-to-release-its-memory/

      ## Subprocess
      ##################################################################### 
      $memc->{dbconn}     = $hash->{dbconn};
      $memc->{dbuser}     = $hash->{dbuser};
      $memc->{dbpassword} = $attr{"sec$name"}{secret};
      $memc->{DbLogType}  = AttrVal($name, "DbLogType",      'History');
      $memc->{nsupk}      = AttrVal($name, "noSupportPK",            0);
      $memc->{tl}         = AttrVal($name, "traceLevel",             0);
      $memc->{tf}         = AttrVal($name, "traceFlag",          'SQL');
      $memc->{bi}         = AttrVal($name, "bulkInsert",             0);
      $memc->{cm}         = AttrVal($name, 'commitMode', 'basic_ta:on');
      $memc->{verbose}    = AttrVal($name, 'verbose',                3);
      $memc->{utf8}       = defined ($hash->{UTF8}) ? $hash->{UTF8} : 0;
      $memc->{history}    = $hash->{HELPER}{TH};
      $memc->{current}    = $hash->{HELPER}{TC};
      $memc->{model}      = $hash->{MODEL};
      
      my $json = eval { encode_json($memc) };
      
      if ($@) {
          Log3 ($name, 1, "DbLog $name -> JSON error: $@");
          return;
      }
      else {
          $subprocess->writeToChild($json);
      }
  }
  else {
      if($hash->{HELPER}{".RUNNING_PID"}) {
          $error = "Commit already running - resync at NextSync";
          DbLog_writeFileIfCacheOverflow ($params);                                        # Cache exportieren bei Overflow
      }
      else {
          if($hash->{HELPER}{SHUTDOWNSEQ}) {
              Log3 ($name, 2, "DbLog $name - no data for last database write cycle");
              _DbLog_finishDelayedShutdown ($hash);
          }
      }
  }

  my $nextsync = gettimeofday()+$syncival;
  my $nsdt     = FmtDateTime($nextsync);
  my $se       = AttrVal($name, "syncEvents", undef) ? 1 : 0;

  readingsSingleUpdate($hash, "NextSync", $nsdt. " or when CacheUsage ".$clim." is reached", $se);

  DbLog_setReadingstate ($hash, $error);

  InternalTimer($nextsync, "DbLog_execmemcache", $hash, 0);

return;
}

################################################################
#     wenn Cache Overflow vorhanden ist und die Behandlung mit
#     dem Attr "cacheOverflowThreshold" eingeschaltet ist,
#     wirde der Cache in ein File weggeschrieben
#     Gibt "1" zurück wenn File geschrieben wurde
################################################################
sub DbLog_writeFileIfCacheOverflow {
  my $paref    = shift;
  my $hash     = $paref->{hash};
  my $clim     = $paref->{clim};
  my $memcount = $paref->{memcount};

  my $name    = $hash->{NAME};
  my $success = 0;
  my $coft    = AttrVal($name, "cacheOverflowThreshold", 0);                                 # Steuerung exportCache statt schreiben in DB
  $coft       = ($coft && $coft < $clim) ? $clim : $coft;                                    # cacheOverflowThreshold auf cacheLimit setzen wenn kleiner als cacheLimit

  my $overflowstate = "normal";
  my $overflownum;

  if($coft) {
      $overflownum = $memcount >= $coft ? $memcount-$coft : 0;
  }
  else {
      $overflownum = $memcount >= $clim ? $memcount-$clim : 0;
  }

  $overflowstate = "exceeded" if($overflownum);

  readingsBeginUpdate($hash);
  readingsBulkUpdate          ($hash, "CacheOverflowLastNum",   $overflownum     );
  readingsBulkUpdateIfChanged ($hash, "CacheOverflowLastState", $overflowstate, 1);
  readingsEndUpdate($hash, 1);

  if($coft && $memcount >= $coft) {
      Log3 ($name, 2, "DbLog $name -> WARNING - Cache is exported to file instead of logging it to database");
      my $error = CommandSet (undef, qq{$name exportCache purgecache});

      if($error) {                                                                          # Fehler beim Export Cachefile
          Log3 ($name, 1, "DbLog $name -> ERROR - while exporting Cache file: $error");
          DbLog_setReadingstate ($hash, $error);
          return $success;
      }

      DbLog_setReadingstate ($hash, qq{Cache exported to "lastCachefile" due to Cache overflow});
      delete $hash->{HELPER}{LASTLIMITRUNTIME};
      $success = 1;
  }

return $success;
}

################################################################
#             Reading state setzen
################################################################
sub DbLog_setReadingstate {
  my $hash = shift;
  my $val  = shift // $hash->{HELPER}{OLDSTATE};

  my $evt   = ($val eq $hash->{HELPER}{OLDSTATE}) ? 0 : 1;
  readingsSingleUpdate($hash, "state", $val, $evt);
  $hash->{HELPER}{OLDSTATE} = $val;

return;
}

################################################################
#
# zerlegt uebergebenes FHEM-Datum in die einzelnen Bestandteile
# und fuegt noch Defaultwerte ein
# uebergebenes SQL-Format: YYYY-MM-DD HH24:MI:SS
#
################################################################
sub DbLog_explode_datetime {
  my ($t, %def) = @_;
  my %retv;

  my (@datetime, @date, @time);
  @datetime = split(" ", $t); #Datum und Zeit auftrennen
  @date     = split("-", $datetime[0]);
  @time     = split(":", $datetime[1]) if ($datetime[1]);

  if ($date[0]) {$retv{year}   = $date[0];} else {$retv{year}   = $def{year};}
  if ($date[1]) {$retv{month}  = $date[1];} else {$retv{month}  = $def{month};}
  if ($date[2]) {$retv{day}    = $date[2];} else {$retv{day}    = $def{day};}
  if ($time[0]) {$retv{hour}   = $time[0];} else {$retv{hour}   = $def{hour};}
  if ($time[1]) {$retv{minute} = $time[1];} else {$retv{minute} = $def{minute};}
  if ($time[2]) {$retv{second} = $time[2];} else {$retv{second} = $def{second};}

  $retv{datetime} = DbLog_implode_datetime($retv{year}, $retv{month}, $retv{day}, $retv{hour}, $retv{minute}, $retv{second});

  # Log 1, Dumper(%retv);
  return %retv
}

sub DbLog_implode_datetime($$$$$$) {
  my ($year, $month, $day, $hour, $minute, $second) = @_;
  my $retv = $year."-".$month."-".$day." ".$hour.":".$minute.":".$second;

return $retv;
}

###################################################################################
#                            Verbindungen zur DB aufbauen
###################################################################################
sub DbLog_readCfg {
  my $hash = shift;
  my $name = $hash->{NAME};

  my $configfilename= $hash->{CONFIGURATION};
  my %dbconfig;

  # use generic fileRead to get configuration data
  my ($err, @config) = FileRead($configfilename);
  return $err if($err);

  eval join("\n", @config);

  return "could not read connection" if (!defined $dbconfig{connection});
  $hash->{dbconn} = $dbconfig{connection};
  return "could not read user" if (!defined $dbconfig{user});
  $hash->{dbuser} = $dbconfig{user};
  return "could not read password" if (!defined $dbconfig{password});
  $attr{"sec$name"}{secret} = $dbconfig{password};

  #check the database model
  if($hash->{dbconn} =~ m/pg:/i) {
    $hash->{MODEL}="POSTGRESQL";
  }
  elsif ($hash->{dbconn} =~ m/mysql:/i) {
    $hash->{MODEL}="MYSQL";
  }
  elsif ($hash->{dbconn} =~ m/oracle:/i) {
    $hash->{MODEL}="ORACLE";
  }
  elsif ($hash->{dbconn} =~ m/sqlite:/i) {
    $hash->{MODEL}="SQLITE";
  }
  else {
    $hash->{MODEL}="unknown";
    
    Log3 $name, 1, "Unknown database model found in configuration file $configfilename.";
    Log3 $name, 1, "Only MySQL/MariaDB, PostgreSQL, Oracle, SQLite are fully supported.";
    
    return "unknown database type";
  }

  if($hash->{MODEL} eq "MYSQL") {
    $hash->{UTF8} = defined($dbconfig{utf8}) ? $dbconfig{utf8} : 0;
  }

return;
}


###################################################################################
#   own $dbhp for synchronous logging and dblog_get
###################################################################################
sub _DbLog_ConnectPush {                                                 
  my ($hash,$get) = @_;
  my $name        = $hash->{NAME};
  my $dbconn      = $hash->{dbconn};
  my $dbuser      = $hash->{dbuser};
  my $dbpassword  = $attr{"sec$name"}{secret};
  my $utf8        = defined($hash->{UTF8})?$hash->{UTF8}:0;

  my ($dbhp,$state,$evt,$err);

  return 0 if(IsDisabled($name));

  if($init_done != 1) {
      InternalTimer(gettimeofday()+5, "_DbLog_ConnectPush", $hash, 0);
      return;
  }

  Log3 ($name, 3, "DbLog $name - Creating Push-Handle to database $dbconn with user $dbuser") if(!$get);

  my ($useac,$useta) = DbLog_commitMode ($name, AttrVal($name, 'commitMode', 'basic_ta:on'));
  
  eval {
      if(!$useac) {
          $dbhp = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError          => 0, 
                                                                      RaiseError          => 1, 
                                                                      AutoCommit          => 0, 
                                                                      AutoInactiveDestroy => 1, 
                                                                      mysql_enable_utf8   => $utf8 
                                                                    });
      }
      elsif($useac == 1) {
          $dbhp = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError          => 0, 
                                                                      RaiseError          => 1, 
                                                                      AutoCommit          => 1, 
                                                                      AutoInactiveDestroy => 1, 
                                                                      mysql_enable_utf8   => $utf8 
                                                                    });
      }
      else {           # Server default
          $dbhp = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError          => 0, 
                                                                      RaiseError          => 1, 
                                                                      AutoInactiveDestroy => 1, 
                                                                      mysql_enable_utf8   => $utf8 
                                                                    });
      }
  };

  if($@) {
      $err = $@;
      Log3 $name, 2, "DbLog $name - Error: $@";
  }

  if(!$dbhp) {
    RemoveInternalTimer($hash, "_DbLog_ConnectPush");
    Log3 ($name, 4, "DbLog $name - Trying to connect to database");

    $state = $err              ? $err       : 
             IsDisabled($name) ? "disabled" : 
             "disconnected";
             
    DbLog_setReadingstate ($hash, $state);

    InternalTimer(gettimeofday()+5, '_DbLog_ConnectPush', $hash, 0);
    Log3 ($name, 4, "DbLog $name - Waiting for database connection");
    
    return 0;
  }

  $dbhp->{RaiseError} = 0;
  $dbhp->{PrintError} = 1;

  Log3 ($name, 3, "DbLog $name - Push-Handle to db $dbconn created") if(!$get);
  Log3 ($name, 3, "DbLog $name - UTF8 support enabled")              if($utf8 && $hash->{MODEL} eq "MYSQL" && !$get);
  
  if(!$get) {
      $state = "connected";
      DbLog_setReadingstate ($hash, $state);
  }

  $hash->{DBHP} = $dbhp;

  if ($hash->{MODEL} eq "SQLITE") {
    $dbhp->do("PRAGMA temp_store=MEMORY");
    $dbhp->do("PRAGMA synchronous=FULL");    # For maximum reliability and for robustness against database corruption,
                                             # SQLite should always be run with its default synchronous setting of FULL.
                                             # https://sqlite.org/howtocorrupt.html

    if (AttrVal($name, "SQLiteJournalMode", "WAL") eq "off") {
        $dbhp->do("PRAGMA journal_mode=off");
        $hash->{SQLITEWALMODE} = "off";
    }
    else {
        $dbhp->do("PRAGMA journal_mode=WAL");
        $hash->{SQLITEWALMODE} = "on";
    }

    my $cs = AttrVal($name, "SQLiteCacheSize", "4000");
    $dbhp->do("PRAGMA cache_size=$cs");
    $hash->{SQLITECACHESIZE} = $cs;
  }

return 1;
}

###################################################################################
# new dbh for common use (except DbLog_Push and get-function)
###################################################################################
sub _DbLog_ConnectNewDBH {                                                  
  my ($hash)     = @_;
  my $name       = $hash->{NAME};
  my $dbconn     = $hash->{dbconn};
  my $dbuser     = $hash->{dbuser};
  my $dbpassword = $attr{"sec$name"}{secret};
  my $utf8       = defined($hash->{UTF8}) ? $hash->{UTF8} : 0;
  my $dbh;

  my ($useac,$useta) = DbLog_commitMode ($name, AttrVal($name, 'commitMode', 'basic_ta:on'));
  
  eval {
      if(!$useac) {
          $dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError          => 0, 
                                                                     RaiseError          => 1, 
                                                                     AutoCommit          => 0, 
                                                                     AutoInactiveDestroy => 1, 
                                                                     mysql_enable_utf8   => $utf8 
                                                                   });
      }
      elsif($useac == 1) {
          $dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError          => 0, 
                                                                     RaiseError          => 1, 
                                                                     AutoCommit          => 1, 
                                                                     AutoInactiveDestroy => 1, 
                                                                     mysql_enable_utf8   => $utf8 
                                                                   });
      }
      else {                        # Server default
          $dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError          => 0, 
                                                                     RaiseError          => 1, 
                                                                     AutoInactiveDestroy => 1, 
                                                                     mysql_enable_utf8   => $utf8 
                                                                   });
      }
  };

  if($@) {
    Log3 ($name, 2, "DbLog $name - $@");
    my $state = $@                ? $@         : 
                IsDisabled($name) ? "disabled" : 
                "disconnected";
    
    DbLog_setReadingstate ($hash, $state);
  }

  if($dbh) {
      $dbh->{RaiseError} = 0;
      $dbh->{PrintError} = 1;

      if ($hash->{MODEL} eq "SQLITE") {         # Forum: https://forum.fhem.de/index.php/topic,120237.0.html
        $dbh->do("PRAGMA temp_store=MEMORY");
        $dbh->do("PRAGMA synchronous=FULL");    # For maximum reliability and for robustness against database corruption,
                                                # SQLite should always be run with its default synchronous setting of FULL.
                                                # https://sqlite.org/howtocorrupt.html

        if (AttrVal($name, "SQLiteJournalMode", "WAL") eq "off") {
            $dbh->do("PRAGMA journal_mode=off");
        }
        else {
            $dbh->do("PRAGMA journal_mode=WAL");
        }

        my $cs = AttrVal($name, "SQLiteCacheSize", "4000");
        $dbh->do("PRAGMA cache_size=$cs");
      }

      return $dbh;
  }
  else {
      return 0;
  }
}

##########################################################################
#
# Prozedur zum Ausfuehren von SQL-Statements durch externe Module
#
# param1: DbLog-hash
# param2: SQL-Statement
#
##########################################################################
sub DbLog_ExecSQL {
  my ($hash,$sql) = @_;
  my $name        = $hash->{NAME};
  my $dbh         = _DbLog_ConnectNewDBH($hash);

  Log3($name, 4, "DbLog $name - Backdoor executing: $sql");

  return if(!$dbh);
  my $sth = DbLog_ExecSQL1($hash,$dbh,$sql);
  if(!$sth) {
    #retry
    $dbh->disconnect();
    $dbh = _DbLog_ConnectNewDBH($hash);
    return if(!$dbh);

    Log3($name, 2, "DbLog $name - Backdoor retry: $sql");
    $sth = DbLog_ExecSQL1($hash,$dbh,$sql);
    if(!$sth) {
      Log3($name, 2, "DbLog $name - Backdoor retry failed");
      $dbh->disconnect();
      return 0;
    }
    Log3($name, 2, "DbLog $name - Backdoor retry ok");
  }
  eval {$dbh->commit() if(!$dbh->{AutoCommit});};
  $dbh->disconnect();

return $sth;
}

sub DbLog_ExecSQL1 {
  my ($hash,$dbh,$sql)= @_;
  my $name = $hash->{NAME};

  $dbh->{RaiseError} = 1;
  $dbh->{PrintError} = 0;

  my $sth;
  eval { $sth = $dbh->do($sql); };
  if($@) {
    Log3 ($name, 2, "DbLog $name - ERROR: $@");
    return 0;
  }

return $sth;
}

################################################################
#
# GET Funktion
# wird zb. zur Generierung der Plots implizit aufgerufen
# infile : [-|current|history]
# outfile: [-|ALL|INT|WEBCHART]
#
################################################################
sub DbLog_Get {
  my ($hash, @a) = @_;
  my $name       = $hash->{NAME};
  my $utf8       = defined($hash->{UTF8})?$hash->{UTF8}:0;
  my $history    = $hash->{HELPER}{TH};
  my $current    = $hash->{HELPER}{TC};
  my ($dbh,$err);

  return DbLog_dbReadings($hash,@a) if $a[1] =~ m/^Readings/;

  return "Usage: get $a[0] <in> <out> <from> <to> <column_spec>...\n".
     "  where column_spec is <device>:<reading>:<default>:<fn>\n" .
     "  see the #DbLog entries in the .gplot files\n" .
     "  <in> is not used, only for compatibility for FileLog, please use - \n" .
     "  <out> is a prefix, - means stdout\n"
     if(int(@a) < 5);

  shift @a;
  my $inf  = lc(shift @a);
  my $outf = lc(shift @a);               # Wert ALL: get all colums from table, including a header
                                         # Wert Array: get the columns as array of hashes
                                         # Wert INT: internally used by generating plots
  my $from = shift @a;
  my $to   = shift @a;                   # Now @a contains the list of column_specs
  my ($internal, @fld);

  if($inf eq "-") {
      $inf = "history";
  }

  if($outf eq "int" && $inf eq "current") {
      $inf = "history";
      Log3 $name, 3, "Defining DbLog SVG-Plots with :CURRENT is deprecated. Please define DbLog SVG-Plots with :HISTORY instead of :CURRENT. (define <mySVG> SVG <DbLogDev>:<gplotfile>:HISTORY)";
  }

  if($outf eq "int") {
      $outf = "-";
      $internal = 1;
  } elsif($outf eq "array") {

  } elsif(lc($outf) eq "webchart") {
      # redirect the get request to the DbLog_chartQuery function
      return DbLog_chartQuery($hash, @_);
  }

  ########################
  # getter für SVG
  ########################
  my @readings = ();
  my (%sqlspec, %from_datetime, %to_datetime);

  # uebergebenen Timestamp anpassen
  # moegliche Formate: YYYY | YYYY-MM | YYYY-MM-DD | YYYY-MM-DD_HH24
  $from          =~ s/_/\ /g;
  $to            =~ s/_/\ /g;
  %from_datetime = DbLog_explode_datetime($from, DbLog_explode_datetime("2000-01-01 00:00:00", ()));
  %to_datetime   = DbLog_explode_datetime($to, DbLog_explode_datetime("2099-01-01 00:00:00", ()));
  $from          = $from_datetime{datetime};
  $to            = $to_datetime{datetime};

  $err = DbLog_checkTimeformat($from);                                     # Forum: https://forum.fhem.de/index.php/topic,101005.0.html
  if($err) {
      Log3($name, 1, "DbLog $name - wrong date/time format (from: $from) requested by SVG: $err");
      return;
  }

  $err = DbLog_checkTimeformat($to);                                       # Forum: https://forum.fhem.de/index.php/topic,101005.0.html
  if($err) {
      Log3($name, 1, "DbLog $name - wrong date/time format (to: $to) requested by SVG: $err");
      return;
  }

  if($to =~ /(\d{4})-(\d{2})-(\d{2}) 23:59:59/) {
     # 03.09.2018 : https://forum.fhem.de/index.php/topic,65860.msg815640.html#msg815640
     $to =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/;
     my $tc = timelocal($6, $5, $4, $3, $2-1, $1-1900);
     $tc++;
     $to = strftime "%Y-%m-%d %H:%M:%S", localtime($tc);
  }

  my ($retval,$retvaldummy,$hour,$sql_timestamp, $sql_device, $sql_reading, $sql_value, $type, $event, $unit) = "";
  my @ReturnArray;
  my $writeout = 0;
  my (@min, @max, @sum, @cnt, @firstv, @firstd, @lastv, @lastd, @mind, @maxd);
  my (%tstamp, %lasttstamp, $out_tstamp, $out_value, $minval, $maxval, $deltacalc);   # fuer delta-h/d Berechnung

  # extract the Device:Reading arguments into @readings array
  # Ausgangspunkt ist z.B.: KS300:temperature KS300:rain::delta-h KS300:rain::delta-d
  for(my $i = 0; $i < int(@a); $i++) {
      @fld = split(":", $a[$i], 5);
      $readings[$i][0] = $fld[0];         # Device
      $readings[$i][1] = $fld[1];         # Reading
      $readings[$i][2] = $fld[2];         # Default
      $readings[$i][3] = $fld[3];         # function
      $readings[$i][4] = $fld[4];         # regexp

      $readings[$i][1] = "%" if(!$readings[$i][1] || length($readings[$i][1])==0);   # falls Reading nicht gefuellt setze Joker
  }

  Log3 $name, 4, "DbLog $name -> ################################################################";
  Log3 $name, 4, "DbLog $name -> ###                  new get data for SVG                    ###";
  Log3 $name, 4, "DbLog $name -> ################################################################";
  Log3($name, 4, "DbLog $name -> main PID: $hash->{PID}, secondary PID: $$");

  my $nh = ($hash->{MODEL} ne 'SQLITE') ? 1 : 0;
  if ($nh || $hash->{PID} != $$) {                                # 17.04.2019 Forum: https://forum.fhem.de/index.php/topic,99719.0.html
      $dbh = _DbLog_ConnectNewDBH($hash);
      return "Can't connect to database." if(!$dbh);
  }
  else {
      $dbh = $hash->{DBHP};
      eval {
          if ( !$dbh || not $dbh->ping ) {
              # DB Session dead, try to reopen now !
              _DbLog_ConnectPush($hash,1);
          }
      };
      if ($@) {
          Log3($name, 1, "DbLog $name: DBLog_Push - DB Session dead! - $@");
          return $@;
      }
      else {
          $dbh = $hash->{DBHP};
      }
  }

  # vorbereiten der DB-Abfrage, DB-Modell-abhaengig
  if ($hash->{MODEL} eq "POSTGRESQL") {
      $sqlspec{get_timestamp}  = "TO_CHAR(TIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')";
      $sqlspec{from_timestamp} = "TO_TIMESTAMP('$from', 'YYYY-MM-DD HH24:MI:SS')";
      $sqlspec{to_timestamp}   = "TO_TIMESTAMP('$to', 'YYYY-MM-DD HH24:MI:SS')";
      #$sqlspec{reading_clause} = "(DEVICE || '|' || READING)";
      $sqlspec{order_by_hour}  = "TO_CHAR(TIMESTAMP, 'YYYY-MM-DD HH24')";
      $sqlspec{max_value}      = "MAX(VALUE)";
      $sqlspec{day_before}     = "($sqlspec{from_timestamp} - INTERVAL '1 DAY')";
  }
  elsif ($hash->{MODEL} eq "ORACLE") {
      $sqlspec{get_timestamp}  = "TO_CHAR(TIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')";
      $sqlspec{from_timestamp} = "TO_TIMESTAMP('$from', 'YYYY-MM-DD HH24:MI:SS')";
      $sqlspec{to_timestamp}   = "TO_TIMESTAMP('$to', 'YYYY-MM-DD HH24:MI:SS')";
      $sqlspec{order_by_hour}  = "TO_CHAR(TIMESTAMP, 'YYYY-MM-DD HH24')";
      $sqlspec{max_value}      = "MAX(VALUE)";
      $sqlspec{day_before}     = "DATE_SUB($sqlspec{from_timestamp},INTERVAL 1 DAY)";
  }
  elsif ($hash->{MODEL} eq "MYSQL") {
      $sqlspec{get_timestamp}  = "DATE_FORMAT(TIMESTAMP, '%Y-%m-%d %H:%i:%s')";
      $sqlspec{from_timestamp} = "STR_TO_DATE('$from', '%Y-%m-%d %H:%i:%s')";
      $sqlspec{to_timestamp}   = "STR_TO_DATE('$to', '%Y-%m-%d %H:%i:%s')";
      $sqlspec{order_by_hour}  = "DATE_FORMAT(TIMESTAMP, '%Y-%m-%d %H')";
      $sqlspec{max_value}      = "MAX(VALUE)";                                           # 12.04.2019 Forum: https://forum.fhem.de/index.php/topic,99280.0.html
      $sqlspec{day_before}     = "DATE_SUB($sqlspec{from_timestamp},INTERVAL 1 DAY)";
  }
  elsif ($hash->{MODEL} eq "SQLITE") {
      $sqlspec{get_timestamp}  = "TIMESTAMP";
      $sqlspec{from_timestamp} = "'$from'";
      $sqlspec{to_timestamp}   = "'$to'";
      $sqlspec{order_by_hour}  = "strftime('%Y-%m-%d %H', TIMESTAMP)";
      $sqlspec{max_value}      = "MAX(VALUE)";
      $sqlspec{day_before}     = "date($sqlspec{from_timestamp},'-1 day')";
  }
  else {
      $sqlspec{get_timestamp}  = "TIMESTAMP";
      $sqlspec{from_timestamp} = "'$from'";
      $sqlspec{to_timestamp}   = "'$to'";
      $sqlspec{order_by_hour}  = "strftime('%Y-%m-%d %H', TIMESTAMP)";
      $sqlspec{max_value}      = "MAX(VALUE)";
      $sqlspec{day_before}     = "date($sqlspec{from_timestamp},'-1 day')";
  }

  if($outf =~ m/(all|array)/) {
      $sqlspec{all}      = ",TYPE,EVENT,UNIT";
      $sqlspec{all_max}  = ",MAX(TYPE) AS TYPE,MAX(EVENT) AS EVENT,MAX(UNIT) AS UNIT";
  }
  else {
      $sqlspec{all}      = "";
      $sqlspec{all_max}  = "";
  }

  for(my $i=0; $i<int(@readings); $i++) {
      # ueber alle Readings
      # Variablen initialisieren
      $min[$i]    =  (~0 >> 1);
      $max[$i]    = -(~0 >> 1);
      $sum[$i]    = 0;
      $cnt[$i]    = 0;
      $firstv[$i] = 0;
      $firstd[$i] = "undef";
      $lastv[$i]  = 0;
      $lastd[$i]  = "undef";
      $mind[$i]   = "undef";
      $maxd[$i]   = "undef";
      $minval     =  (~0 >> 1);                               # ist "9223372036854775807"
      $maxval     = -(~0 >> 1);                               # ist "-9223372036854775807"
      $deltacalc  = 0;

      if($readings[$i]->[3] && ($readings[$i]->[3] eq "delta-h" || $readings[$i]->[3] eq "delta-d")) {
          $deltacalc = 1;
          Log3($name, 4, "DbLog $name -> deltacalc: hour") if($readings[$i]->[3] eq "delta-h");   # geändert V4.8.0 / 14.10.2019
          Log3($name, 4, "DbLog $name -> deltacalc: day")  if($readings[$i]->[3] eq "delta-d");   # geändert V4.8.0 / 14.10.2019
      }

      my ($stm);
      if($deltacalc) {
          # delta-h und delta-d , geändert V4.8.0 / 14.10.2019
          $stm  = "SELECT Z.TIMESTAMP, Z.DEVICE, Z.READING, Z.VALUE from ";

          $stm .= "(SELECT $sqlspec{get_timestamp} AS TIMESTAMP,
                    DEVICE AS DEVICE,
                    READING AS READING,
                    VALUE AS VALUE ";

          $stm .= "FROM $current " if($inf eq "current");
          $stm .= "FROM $history " if($inf eq "history");

          $stm .= "WHERE 1=1 ";

          $stm .= "AND DEVICE  = '".$readings[$i]->[0]."' "   if ($readings[$i]->[0] !~ m(\%));
          $stm .= "AND DEVICE LIKE '".$readings[$i]->[0]."' " if(($readings[$i]->[0] !~ m(^\%$)) && ($readings[$i]->[0] =~ m(\%)));

          $stm .= "AND READING = '".$readings[$i]->[1]."' "    if ($readings[$i]->[1] !~ m(\%));
          $stm .= "AND READING LIKE '".$readings[$i]->[1]."' " if(($readings[$i]->[1] !~ m(^%$)) && ($readings[$i]->[1] =~ m(\%)));

          $stm .= "AND TIMESTAMP < $sqlspec{from_timestamp} ";
          $stm .= "AND TIMESTAMP > $sqlspec{day_before} ";

          $stm .= "ORDER BY TIMESTAMP DESC LIMIT 1 ) AS Z
                   UNION ALL " if($readings[$i]->[3] eq "delta-h");

          $stm .= "ORDER BY TIMESTAMP) AS Z
                   UNION ALL " if($readings[$i]->[3] eq "delta-d");

          $stm .= "SELECT
                   MAX($sqlspec{get_timestamp}) AS TIMESTAMP,
                   MAX(DEVICE) AS DEVICE,
                   MAX(READING) AS READING,
                   $sqlspec{max_value}
                   $sqlspec{all_max} ";

          $stm .= "FROM $current " if($inf eq "current");
          $stm .= "FROM $history " if($inf eq "history");

          $stm .= "WHERE 1=1 ";

          $stm .= "AND DEVICE  = '".$readings[$i]->[0]."' "    if ($readings[$i]->[0] !~ m(\%));
          $stm .= "AND DEVICE LIKE '".$readings[$i]->[0]."' "  if(($readings[$i]->[0] !~ m(^\%$)) && ($readings[$i]->[0] =~ m(\%)));

          $stm .= "AND READING = '".$readings[$i]->[1]."' "    if ($readings[$i]->[1] !~ m(\%));
          $stm .= "AND READING LIKE '".$readings[$i]->[1]."' " if(($readings[$i]->[1] !~ m(^%$)) && ($readings[$i]->[1] =~ m(\%)));

          $stm .= "AND TIMESTAMP >= $sqlspec{from_timestamp} ";
          $stm .= "AND TIMESTAMP <= $sqlspec{to_timestamp} ";           # 03.09.2018 : https://forum.fhem.de/index.php/topic,65860.msg815640.html#msg815640

          $stm .= "GROUP BY $sqlspec{order_by_hour} " if($deltacalc);
          $stm .= "ORDER BY TIMESTAMP";
      }
      else {
          # kein deltacalc
          $stm =  "SELECT
                      $sqlspec{get_timestamp},
                      DEVICE,
                      READING,
                      VALUE
                      $sqlspec{all} ";

          $stm .= "FROM $current " if($inf eq "current");
          $stm .= "FROM $history " if($inf eq "history");

          $stm .= "WHERE 1=1 ";

          $stm .= "AND DEVICE = '".$readings[$i]->[0]."' "     if ($readings[$i]->[0] !~ m(\%));
          $stm .= "AND DEVICE LIKE '".$readings[$i]->[0]."' "  if(($readings[$i]->[0] !~ m(^\%$)) && ($readings[$i]->[0] =~ m(\%)));

          $stm .= "AND READING = '".$readings[$i]->[1]."' "    if ($readings[$i]->[1] !~ m(\%));
          $stm .= "AND READING LIKE '".$readings[$i]->[1]."' " if(($readings[$i]->[1] !~ m(^%$)) && ($readings[$i]->[1] =~ m(\%)));

          $stm .= "AND TIMESTAMP >= $sqlspec{from_timestamp} ";
          $stm .= "AND TIMESTAMP <= $sqlspec{to_timestamp} ";           # 03.09.2018 : https://forum.fhem.de/index.php/topic,65860.msg815640.html#msg815640
          $stm .= "ORDER BY TIMESTAMP";
      }

      Log3 ($name, 4, "$name - PID: $$, Processing Statement:\n$stm");

      my $sth = $dbh->prepare($stm) || return "Cannot prepare statement $stm: $DBI::errstr";
      my $rc  = $sth->execute()     || return "Cannot execute statement $stm: $DBI::errstr";

      if($outf =~ m/(all|array)/) {
          $sth->bind_columns(undef, \$sql_timestamp, \$sql_device, \$sql_reading, \$sql_value, \$type, \$event, \$unit);
      }
      else {
          $sth->bind_columns(undef, \$sql_timestamp, \$sql_device, \$sql_reading, \$sql_value);
      }

      if ($outf =~ m/(all)/) {
          $retval .= "Timestamp: Device, Type, Event, Reading, Value, Unit\n";
          $retval .= "=====================================================\n";
      }

      ####################################################################################
      #                              Select Auswertung
      ####################################################################################
      my $rv = 0;
      while($sth->fetch()) {
          $rv++;
          no warnings 'uninitialized';                                                                     # geändert V4.8.0 / 14.10.2019
          my $ds = "PID: $$, TS: $sql_timestamp, DEV: $sql_device, RD: $sql_reading, VAL: $sql_value";     # geändert V4.8.0 / 14.10.2019
          Log3 ($name, 5, "$name - SQL-result -> $ds");                                                    # geändert V4.8.0 / 14.10.2019
          use warnings;                                                                                    # geändert V4.8.0 / 14.10.2019
          $writeout = 0;                                                                                   # eingefügt V4.8.0 / 14.10.2019

          ############ Auswerten des 5. Parameters: Regexp ###################
          # die Regexep wird vor der Function ausgewertet und der Wert im Feld
          # Value angepasst.
          # z.B.: KS300:temperature KS300:rain::delta-h KS300:rain::delta-d
          #                            0    1  2  3
          # $readings[$i][0] = Device
          # $readings[$i][1] = Reading
          # $readings[$i][2] = Default
          # $readings[$i][3] = function
          # $readings[$i][4] = regexp
          ####################################################################
          if($readings[$i]->[4]) {
              #evaluate
              my $val = $sql_value;
              my $ts  = $sql_timestamp;
              eval("$readings[$i]->[4]");
              $sql_value     = $val;
              $sql_timestamp = $ts;
              if($@) {
                  Log3 ($name, 3, "DbLog: Error in inline function: <".$readings[$i]->[4].">, Error: $@");
              }
          }

          if($sql_timestamp lt $from && $deltacalc) {
              if(Scalar::Util::looks_like_number($sql_value)) {
                  # nur setzen wenn numerisch
                  $minval    = $sql_value if($sql_value < $minval || ($minval =  (~0 >> 1)) );   # geändert V4.8.0 / 14.10.2019
                  $maxval    = $sql_value if($sql_value > $maxval || ($maxval = -(~0 >> 1)) );   # geändert V4.8.0 / 14.10.2019
                  $lastv[$i] = $sql_value;
              }
          }
          else {
              $writeout    = 0;
              $out_value   = "";
              $out_tstamp  = "";
              $retvaldummy = "";

              if($readings[$i]->[4]) {
                  $out_tstamp = $sql_timestamp;
                  $writeout   = 1 if(!$deltacalc);
              }

              ############ Auswerten des 4. Parameters: function ###################
              if($readings[$i]->[3] && $readings[$i]->[3] eq "int") {                  # nur den integerwert uebernehmen falls zb value=15°C
                  $out_value  = $1 if($sql_value =~ m/^(\d+).*/o);
                  $out_tstamp = $sql_timestamp;
                  $writeout   = 1;
              }
              elsif ($readings[$i]->[3] && $readings[$i]->[3] =~ m/^int(\d+).*/o) {  # Uebernehme den Dezimalwert mit den angegebenen Stellen an Nachkommastellen
                  $out_value  = $1 if($sql_value =~ m/^([-\.\d]+).*/o);
                  $out_tstamp = $sql_timestamp;
                  $writeout   = 1;
              }
              elsif ($readings[$i]->[3] && $readings[$i]->[3] eq "delta-ts" && lc($sql_value) !~ m(ignore)) {
                  # Berechung der vergangen Sekunden seit dem letzten Logeintrag
                  # zb. die Zeit zwischen on/off
                  my @a = split("[- :]", $sql_timestamp);
                  my $akt_ts = mktime($a[5],$a[4],$a[3],$a[2],$a[1]-1,$a[0]-1900,0,0,-1);

                  if($lastd[$i] ne "undef") {
                      @a = split("[- :]", $lastd[$i]);
                  }

                  my $last_ts = mktime($a[5],$a[4],$a[3],$a[2],$a[1]-1,$a[0]-1900,0,0,-1);
                  $out_tstamp = $sql_timestamp;
                  $out_value  = sprintf("%02d", $akt_ts - $last_ts);

                  if(lc($sql_value) =~ m(hide)) {
                      $writeout = 0;
                  }
                  else {
                      $writeout = 1;
                  }
              }
              elsif ($readings[$i]->[3] && $readings[$i]->[3] eq "delta-h") {       # Berechnung eines Delta-Stundenwertes
                  %tstamp = DbLog_explode_datetime($sql_timestamp, ());
                  if($lastd[$i] eq "undef") {
                      %lasttstamp = DbLog_explode_datetime($sql_timestamp, ());
                      $lasttstamp{hour} = "00";
                  }
                  else {
                      %lasttstamp = DbLog_explode_datetime($lastd[$i], ());
                  }
                  #    04                   01
                  #    06                   23
                  if("$tstamp{hour}" ne "$lasttstamp{hour}") {
                      # Aenderung der Stunde, Berechne Delta
                      # wenn die Stundendifferenz größer 1 ist muss ein Dummyeintrag erstellt werden
                      $retvaldummy = "";

                      if(($tstamp{hour}-$lasttstamp{hour}) > 1) {
                          for (my $j = $lasttstamp{hour}+1; $j < $tstamp{hour}; $j++) {
                              $out_value  = "0";
                              $hour       = $j;
                              $hour       = '0'.$j if $j<10;
                              $cnt[$i]++;
                              $out_tstamp = DbLog_implode_datetime($tstamp{year}, $tstamp{month}, $tstamp{day}, $hour, "30", "00");
                              if ($outf =~ m/(all)/) {
                                  # Timestamp: Device, Type, Event, Reading, Value, Unit
                                  $retvaldummy .= sprintf("%s: %s, %s, %s, %s, %s, %s\n", $out_tstamp, $sql_device, $type, $event, $sql_reading, $out_value, $unit);

                              } elsif ($outf =~ m/(array)/) {
                                  push(@ReturnArray, {"tstamp" => $out_tstamp, "device" => $sql_device, "type" => $type, "event" => $event, "reading" => $sql_reading, "value" => $out_value, "unit" => $unit});
                              }
                              else {
                                  $out_tstamp   =~ s/\ /_/g; #needed by generating plots
                                  $retvaldummy .= "$out_tstamp $out_value\n";
                              }
                          }
                      }

                      if(($tstamp{hour}-$lasttstamp{hour}) < 0) {
                          for (my $j=0; $j < $tstamp{hour}; $j++) {
                              $out_value  = "0";
                              $hour       = $j;
                              $hour       = '0'.$j if $j<10;
                              $cnt[$i]++;
                              $out_tstamp = DbLog_implode_datetime($tstamp{year}, $tstamp{month}, $tstamp{day}, $hour, "30", "00");

                              if ($outf =~ m/(all)/) {
                                  # Timestamp: Device, Type, Event, Reading, Value, Unit
                                  $retvaldummy .= sprintf("%s: %s, %s, %s, %s, %s, %s\n", $out_tstamp, $sql_device, $type, $event, $sql_reading, $out_value, $unit);
                              }
                              elsif ($outf =~ m/(array)/) {
                                  push(@ReturnArray, {"tstamp" => $out_tstamp, "device" => $sql_device, "type" => $type, "event" => $event, "reading" => $sql_reading, "value" => $out_value, "unit" => $unit});
                              }
                              else {
                                  $out_tstamp =~ s/\ /_/g;                                    # needed by generating plots
                                  $retvaldummy .= "$out_tstamp $out_value\n";
                              }
                          }
                      }

                      $writeout   = 1 if($minval != (~0 >> 1) && $maxval != -(~0 >> 1));      # geändert V4.8.0 / 14.10.2019
                      $out_value  = ($writeout == 1) ? sprintf("%g", $maxval - $minval) : 0;  # if there was no previous reading in the selected time range, produce a null delta, %g - a floating-point number

                      $sum[$i]   += $out_value;
                      $cnt[$i]++;
                      $out_tstamp = DbLog_implode_datetime($lasttstamp{year}, $lasttstamp{month}, $lasttstamp{day}, $lasttstamp{hour}, "30", "00");

                      $minval     = $maxval if($maxval != -(~0 >> 1));                        # only use the current range's maximum as the new minimum if a proper value was found

                      Log3 ($name, 5, "$name - Output delta-h -> TS: $tstamp{hour}, LASTTS: $lasttstamp{hour}, OUTTS: $out_tstamp, OUTVAL: $out_value, WRITEOUT: $writeout");
                  }
              }
              elsif ($readings[$i]->[3] && $readings[$i]->[3] eq "delta-d") {                 # Berechnung eines Tages-Deltas
                  %tstamp = DbLog_explode_datetime($sql_timestamp, ());

                  if($lastd[$i] eq "undef") {
                      %lasttstamp = DbLog_explode_datetime($sql_timestamp, ());
                  }
                  else {
                      %lasttstamp = DbLog_explode_datetime($lastd[$i], ());
                  }

                  if("$tstamp{day}" ne "$lasttstamp{day}") {                                 # Aenderung des Tages, berechne Delta
                      $writeout  = 1 if($minval != (~0 >> 1) && $maxval != -(~0 >> 1));      # geändert V4.8.0 / 14.10.2019
                      $out_value = ($writeout == 1) ? sprintf("%g", $maxval - $minval) : 0;  # if there was no previous reading in the selected time range, produce a null delta, %g - a floating-point number
                      $sum[$i]  += $out_value;
                      $cnt[$i]++;

                      $out_tstamp = DbLog_implode_datetime($lasttstamp{year}, $lasttstamp{month}, $lasttstamp{day}, "12", "00", "00");
                      $minval     = $maxval if($maxval != -(~0 >> 1));                       # only use the current range's maximum as the new minimum if a proper value was found

                      Log3 ($name, 5, "$name - Output delta-d -> TS: $tstamp{day}, LASTTS: $lasttstamp{day}, OUTTS: $out_tstamp, OUTVAL: $out_value, WRITEOUT: $writeout");
                  }
              }
              else {
                  $out_value  = $sql_value;
                  $out_tstamp = $sql_timestamp;
                  $writeout   = 1;
              }

              # Wenn Attr SuppressUndef gesetzt ist, dann ausfiltern aller undef-Werte
              $writeout = 0 if (!defined($sql_value) && AttrVal($name, 'suppressUndef', 0));

              ###################### Ausgabe ###########################
              if($writeout) {
                  if ($outf =~ m/(all)/) {
                      # Timestamp: Device, Type, Event, Reading, Value, Unit
                      $retval .= sprintf("%s: %s, %s, %s, %s, %s, %s\n", $out_tstamp, $sql_device, $type, $event, $sql_reading, $out_value, $unit);
                      $retval .= $retvaldummy;

                  }
                  elsif ($outf =~ m/(array)/) {
                      push(@ReturnArray, {"tstamp" => $out_tstamp, "device" => $sql_device, "type" => $type, "event" => $event, "reading" => $sql_reading, "value" => $out_value, "unit" => $unit});
                  }
                  else {                                                         # generating plots
                      $out_tstamp =~ s/\ /_/g;                                   # needed by generating plots
                      $retval .= "$out_tstamp $out_value\n";
                      $retval .= $retvaldummy;
                  }
              }

              if(Scalar::Util::looks_like_number($sql_value)) {
                  # nur setzen wenn numerisch
                  if($deltacalc) {
                      if(Scalar::Util::looks_like_number($out_value)) {
                          if($out_value < $min[$i]) {
                              $min[$i]  = $out_value;
                              $mind[$i] = $out_tstamp;
                          }
                          if($out_value > $max[$i]) {
                              $max[$i]  = $out_value;
                              $maxd[$i] = $out_tstamp;
                          }
                      }
                      $maxval = $sql_value;
                  }
                  else {
                      if($firstd[$i] eq "undef") {
                          $firstv[$i] = $sql_value;
                          $firstd[$i] = $sql_timestamp;
                      }

                      if($sql_value < $min[$i]) {
                          $min[$i] = $sql_value;
                          $mind[$i] = $sql_timestamp;
                      }

                      if($sql_value > $max[$i]) {
                          $max[$i] = $sql_value;
                          $maxd[$i] = $sql_timestamp;
                      }

                      $sum[$i] += $sql_value;
                      $minval = $sql_value if($sql_value < $minval);
                      $maxval = $sql_value if($sql_value > $maxval);
                  }
              }
              else {
                  $min[$i] = 0;
                  $max[$i] = 0;
                  $sum[$i] = 0;
                  $minval  = 0;
                  $maxval  = 0;
              }

              if(!$deltacalc) {
                  $cnt[$i]++;
                  $lastv[$i] = $sql_value;
              }
              else {
                  $lastv[$i] = $out_value if($out_value);
              }

              $lastd[$i] = $sql_timestamp;
          }
      }
                                                                  ##### while fetchrow Ende #####
      Log3 ($name, 4, "$name - PID: $$, rows count: $rv");

      ######## den letzten Abschlusssatz rausschreiben ##########

      if($readings[$i]->[3] && ($readings[$i]->[3] eq "delta-h" || $readings[$i]->[3] eq "delta-d")) {
          if($lastd[$i] eq "undef") {
              $out_value  = "0";
              $out_tstamp = DbLog_implode_datetime($from_datetime{year}, $from_datetime{month}, $from_datetime{day}, $from_datetime{hour}, "30", "00") if($readings[$i]->[3] eq "delta-h");
              $out_tstamp = DbLog_implode_datetime($from_datetime{year}, $from_datetime{month}, $from_datetime{day}, "12", "00", "00") if($readings[$i]->[3] eq "delta-d");
          }
          else {
              %lasttstamp = DbLog_explode_datetime($lastd[$i], ());

              $out_value  = ($minval != (~0 >> 1) && $maxval != -(~0 >> 1)) ? sprintf("%g", $maxval - $minval) : 0;       # if there was no previous reading in the selected time range, produce a null delta

              $out_tstamp = DbLog_implode_datetime($lasttstamp{year}, $lasttstamp{month}, $lasttstamp{day}, $lasttstamp{hour}, "30", "00") if($readings[$i]->[3] eq "delta-h");
              $out_tstamp = DbLog_implode_datetime($lasttstamp{year}, $lasttstamp{month}, $lasttstamp{day}, "12", "00", "00") if($readings[$i]->[3] eq "delta-d");
          }
          $sum[$i] += $out_value;
          $cnt[$i]++;

          if($outf =~ m/(all)/) {
              $retval .= sprintf("%s: %s %s %s %s %s %s\n", $out_tstamp, $sql_device, $type, $event, $sql_reading, $out_value, $unit);
          }
          elsif ($outf =~ m/(array)/) {
              push(@ReturnArray, {"tstamp" => $out_tstamp, "device" => $sql_device, "type" => $type, "event" => $event, "reading" => $sql_reading, "value" => $out_value, "unit" => $unit});
          }
          else {
             $out_tstamp =~ s/\ /_/g;                                                      #needed by generating plots
             $retval    .= "$out_tstamp $out_value\n";
          }

          Log3 ($name, 5, "$name - Output last DS -> OUTTS: $out_tstamp, OUTVAL: $out_value, WRITEOUT: implicit ");
      }

      # Datentrenner setzen
      $retval .= "#$readings[$i]->[0]";
      $retval .= ":";
      $retval .= "$readings[$i]->[1]" if($readings[$i]->[1]);
      $retval .= ":";
      $retval .= "$readings[$i]->[2]" if($readings[$i]->[2]);
      $retval .= ":";
      $retval .= "$readings[$i]->[3]" if($readings[$i]->[3]);
      $retval .= ":";
      $retval .= "$readings[$i]->[4]" if($readings[$i]->[4]);
      $retval .= "\n";

  }                                                                # Ende for @readings-Schleife über alle Readinggs im get

  # Ueberfuehren der gesammelten Werte in die globale Variable %data
  for(my $j=0; $j<int(@readings); $j++) {
      $min[$j] = 0 if ($min[$j] == (~0 >> 1));                     # if min/max values could not be calculated due to the lack of query results, set them to 0
      $max[$j] = 0 if ($max[$j] == -(~0 >> 1));

      my $k = $j+1;
      $data{"min$k"}       = $min[$j];
      $data{"max$k"}       = $max[$j];
      $data{"avg$k"}       = $cnt[$j] ? sprintf("%0.2f", $sum[$j]/$cnt[$j]) : 0;
      $data{"sum$k"}       = $sum[$j];
      $data{"cnt$k"}       = $cnt[$j];
      $data{"firstval$k"}  = $firstv[$j];
      $data{"firstdate$k"} = $firstd[$j];
      $data{"currval$k"}   = $lastv[$j];
      $data{"currdate$k"}  = $lastd[$j];
      $data{"mindate$k"}   = $mind[$j];
      $data{"maxdate$k"}   = $maxd[$j];
  }

  # cleanup (plotfork) connection
  # $dbh->disconnect() if( $hash->{PID} != $$ );

  $dbh->disconnect() if($nh || $hash->{PID} != $$);

  if($internal) {
      $internal_data = \$retval;
      return undef;
  }
  elsif($outf =~ m/(array)/) {
      return @ReturnArray;
  }
  else {
      $retval = Encode::encode_utf8($retval) if($utf8);
      # Log3 $name, 5, "DbLog $name -> Result of get:\n$retval";
      return $retval;
  }
}

##########################################################################
#
#        Konfigurationscheck DbLog <-> Datenbank
#
##########################################################################
sub DbLog_configcheck {
  my $hash    = shift;
  my $name    = $hash->{NAME};
  my $dbmodel = $hash->{MODEL};
  my $dbconn  = $hash->{dbconn};
  my $dbname  = (split(/;|=/, $dbconn))[1];
  my $history = $hash->{HELPER}{TH};
  my $current = $hash->{HELPER}{TC};

  my ($check, $rec,%dbconfig);

  ### Version check
  #######################################################################
  my $pv      = sprintf("%vd",$^V);                                              # Perl Version
  my $dbi     = $DBI::VERSION;                                                   # DBI Version
  my %drivers = DBI->installed_drivers();
  my $dv      = "";

  if($dbmodel =~ /MYSQL/xi) {
      for (keys %drivers) {
          $dv = $_ if($_ =~ /mysql|mariadb/x);
      }
  }
  my $dbd = ($dbmodel =~ /POSTGRESQL/xi)   ? "Pg: ".$DBD::Pg::VERSION:           # DBD Version
            ($dbmodel =~ /MYSQL/xi && $dv) ? "$dv: ".$DBD::mysql::VERSION:
            ($dbmodel =~ /SQLITE/xi)       ? "SQLite: ".$DBD::SQLite::VERSION:"Undefined";

  my $dbdhint = "";
  my $dbdupd  = 0;

  if($dbmodel =~ /MYSQL/xi && $dv) {                                             # check DBD Mindest- und empfohlene Version
      my $dbdver = $DBD::mysql::VERSION * 1;                                     # String to Zahl Konversion
      if($dbdver < 4.032) {
          $dbdhint = "<b>Caution:</b> Your DBD version doesn't support UTF8. ";
          $dbdupd  = 1;
      }
      elsif ($dbdver < 4.042) {
          $dbdhint = "<b>Caution:</b> Full UTF-8 support exists from DBD version 4.032, but installing DBD version 4.042 is highly suggested. ";
          $dbdupd  = 1;
      }
      else {
          $dbdhint = "Your DBD version fulfills UTF8 support, no need to update DBD.";
      }
  }

  my ($errcm,$supd,$uptb) = DbLog_checkModVer($name);                            # DbLog Version

  $check  = "<html>";
  $check .= "<u><b>Result of version check</u></b><br><br>";
  $check .= "Used Perl version: $pv <br>";
  $check .= "Used DBI (Database independent interface) version: $dbi <br>";
  $check .= "Used DBD (Database driver) version $dbd <br>";

  if($errcm) {
      $check .= "<b>Recommendation:</b> ERROR - $errcm. $dbdhint <br><br>";
  }

  if($supd) {
      $check .= "Used DbLog version: $hash->{HELPER}{VERSION}.<br>$uptb <br>";
      $check .= "<b>Recommendation:</b> You should update FHEM to get the recent DbLog version from repository ! $dbdhint <br><br>";
  }
  else {
      $check .= "Used DbLog version: $hash->{HELPER}{VERSION}.<br>$uptb <br>";
      $check .= "<b>Recommendation:</b> No update of DbLog is needed. $dbdhint <br><br>";
  }

  ### Configuration read check
  #######################################################################
  $check .= "<u><b>Result of configuration read check</u></b><br><br>";
  my $st  = configDBUsed() ? "configDB (don't forget upload configuration file if changed. Use \"configdb filelist\" and look for your configuration file.)" : "file";
  $check .= "Connection parameter store type: $st <br>";

  my ($err, @config) = FileRead($hash->{CONFIGURATION});

  if (!$err) {
      eval join("\n", @config);
      $rec  = "parameter: ";
      $rec .= "Connection -> could not read, "            if (!defined $dbconfig{connection});
      $rec .= "Connection -> ".$dbconfig{connection}.", " if (defined $dbconfig{connection});
      $rec .= "User -> could not read, "                  if (!defined $dbconfig{user});
      $rec .= "User -> ".$dbconfig{user}.", "             if (defined $dbconfig{user});
      $rec .= "Password -> could not read "               if (!defined $dbconfig{password});
      $rec .= "Password -> read o.k. "                    if (defined $dbconfig{password});
  }
  else {
      $rec = $err;
  }
  $check .= "Connection $rec <br><br>";

  ### Connection und Encoding check
  #######################################################################
  my (@ce,@se);
  my ($chutf8mod,$chutf8dat);

  if($dbmodel =~ /MYSQL/) {
      @ce        = DbLog_sqlget($hash,"SHOW VARIABLES LIKE 'character_set_connection'");
      $chutf8mod = @ce ? uc($ce[1]) : "no result";
      @se        = DbLog_sqlget($hash,"SHOW VARIABLES LIKE 'character_set_database'");
      $chutf8dat = @se ? uc($se[1]) : "no result";

      if($chutf8mod eq $chutf8dat) {
          $rec = "settings o.k.";
      }
      else {
          $rec = "Both encodings should be identical. You can adjust the usage of UTF8 connection by setting the UTF8 parameter in file '$hash->{CONFIGURATION}' to the right value. ";
      }

      if(uc($chutf8mod) ne "UTF8" && uc($chutf8dat) ne "UTF8") {
          $dbdhint = "";
      }
      else {
          $dbdhint .= " If you want use UTF8 database option, you must update DBD (Database driver) to at least version 4.032. " if($dbdupd);
      }

  }
  if($dbmodel =~ /POSTGRESQL/) {
      @ce        = DbLog_sqlget($hash,"SHOW CLIENT_ENCODING");
      $chutf8mod = @ce ? uc($ce[0]) : "no result";
      @se        = DbLog_sqlget($hash,"select character_set_name from information_schema.character_sets");
      $chutf8dat = @se ? uc($se[0]) : "no result";

      if($chutf8mod eq $chutf8dat) {
          $rec = "settings o.k.";
      }
      else {
          $rec = "This is only an information. PostgreSQL supports automatic character set conversion between server and client for certain character set combinations. The conversion information is stored in the pg_conversion system catalog. PostgreSQL comes with some predefined conversions.";
      }
  }
  if($dbmodel =~ /SQLITE/) {
      @ce        = DbLog_sqlget($hash,"PRAGMA encoding");
      $chutf8dat = @ce ? uc($ce[0]) : "no result";
      @se        = DbLog_sqlget($hash,"PRAGMA table_info($history)");
      $rec       = "This is only an information about text encoding used by the main database.";
  }

  $check .= "<u><b>Result of connection check</u></b><br><br>";

  if(@ce && @se) {
      $check .= "Connection to database $dbname successfully done. <br>";
      $check .= "<b>Recommendation:</b> settings o.k. <br><br>";
  }

  if(!@ce || !@se) {
      $check .= "Connection to database was not successful. <br>";
      $check .= "<b>Recommendation:</b> Plese check logfile for further information. <br><br>";
      $check .= "</html>";
      return $check;
  }
  $check .= "<u><b>Result of encoding check</u></b><br><br>";
  $check .= "Encoding used by Client (connection): $chutf8mod <br>" if($dbmodel !~ /SQLITE/);
  $check .= "Encoding used by DB $dbname: $chutf8dat <br>";
  $check .= "<b>Recommendation:</b> $rec $dbdhint <br><br>";

  ### Check Betriebsmodus
  #######################################################################
  my $mode = $hash->{MODE};
  my $bi   = AttrVal($name, "bulkInsert", 0);
  my $sfx  = AttrVal("global", "language", "EN");
  $sfx     = ($sfx eq "EN" ? "" : "_$sfx");

  $check .= "<u><b>Result of logmode check</u></b><br><br>";
  $check .= "Logmode of DbLog-device $name is: $mode <br>";
  if($mode =~ /asynchronous/) {
      my $max = AttrVal("global", "blockingCallMax", 0);

      if(!$max || $max >= 6) {
          $rec = "settings o.k.";
      }
      else {
          $rec = "WARNING - you are running asynchronous mode that is recommended, but the value of global device attribute \"blockingCallMax\" is set quite small. <br>";
          $rec .= "This may cause problems in operation. It is recommended to <b>increase</b> the <b>global blockingCallMax</b> attribute.";
      }
  }
  else {
      $rec  = "Switch $name to the asynchronous logmode by setting the 'asyncMode' attribute. The advantage of this mode is to log events non-blocking. <br>";
      $rec .= "There are attributes 'syncInterval' and 'cacheLimit' relevant for this working mode. <br>";
      $rec .= "Please refer to commandref for further information about these attributes.";
  }
  $check .= "<b>Recommendation:</b> $rec <br><br>";

  $check .= "<u><b>Result of insert mode check</u></b><br><br>";
  if(!$bi) {
      $bi     = "Array";
      $check .= "Insert mode of DbLog-device $name is: $bi <br>";
      $rec    = "Setting attribute \"bulkInsert\" to \"1\" may result a higher write performance in most cases. ";
      $rec   .= "Feel free to try this mode.";
  }
  else {
      $bi     = "Bulk";
      $check .= "Insert mode of DbLog-device $name is: $bi <br>";
      $rec    = "settings o.k.";
  }
  $check .= "<b>Recommendation:</b> $rec <br><br>";

  ### Check Plot Erstellungsmodus
  #######################################################################
      $check          .= "<u><b>Result of plot generation method check</u></b><br><br>";
      my @webdvs       = devspec2array("TYPE=FHEMWEB:FILTER=STATE=Initialized");
      my ($forks,$emb) = (1,1);
      my $wall         = "";

      for my $web (@webdvs) {
          my $pf  = AttrVal($web,"plotfork",0);
          my $pe  = AttrVal($web,"plotEmbed",0);
          $forks  = 0 if(!$pf);
          $emb    = 0 if($pe =~ /[01]/);

          if(!$pf || $pe =~ /[01]/) {
              $wall  .= "<b>".$web.": plotfork=".$pf." / plotEmbed=".$pe."</b><br>";
          }
          else {
              $wall  .= $web.": plotfork=".$pf." / plotEmbed=".$pe."<br>";
          }
      }
      if(!$forks || !$emb) {
          $check .= "WARNING - at least one of your FHEMWEB devices has attribute \"plotfork = 1\" and/or attribute \"plotEmbed = 2\" not set. <br><br>";
          $check .= $wall;
          $rec    = "You should set attribute \"plotfork = 1\" and \"plotEmbed = 2\" in relevant devices. ".
                    "If these attributes are not set, blocking situations may occure when creating plots. ".
                    "<b>Note:</b> Your system must have sufficient memory to handle parallel running Perl processes. See also global attribute \"blockingCallMax\". <br>"
      }
      else {
          $check .= $wall;
          $rec    = "settings o.k.";
      }
      $check .= "<br>";
      $check .= "<b>Recommendation:</b> $rec <br><br>";

  ### Check Spaltenbreite history
  #######################################################################
  my (@sr_dev,@sr_typ,@sr_evt,@sr_rdg,@sr_val,@sr_unt);
  my ($cdat_dev,$cdat_typ,$cdat_evt,$cdat_rdg,$cdat_val,$cdat_unt);
  my ($cmod_dev,$cmod_typ,$cmod_evt,$cmod_rdg,$cmod_val,$cmod_unt);

  if($dbmodel =~ /MYSQL/) {
      @sr_dev = DbLog_sqlget($hash,"SHOW FIELDS FROM $history where FIELD='DEVICE'");
      @sr_typ = DbLog_sqlget($hash,"SHOW FIELDS FROM $history where FIELD='TYPE'");
      @sr_evt = DbLog_sqlget($hash,"SHOW FIELDS FROM $history where FIELD='EVENT'");
      @sr_rdg = DbLog_sqlget($hash,"SHOW FIELDS FROM $history where FIELD='READING'");
      @sr_val = DbLog_sqlget($hash,"SHOW FIELDS FROM $history where FIELD='VALUE'");
      @sr_unt = DbLog_sqlget($hash,"SHOW FIELDS FROM $history where FIELD='UNIT'");
  }
  if($dbmodel =~ /POSTGRESQL/) {
      my $sch = AttrVal($name, "dbSchema", "");
      my $h   = "history";
      if($sch) {
          @sr_dev = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and table_schema='$sch' and column_name='device'");
          @sr_typ = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and table_schema='$sch' and column_name='type'");
          @sr_evt = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and table_schema='$sch' and column_name='event'");
          @sr_rdg = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and table_schema='$sch' and column_name='reading'");
          @sr_val = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and table_schema='$sch' and column_name='value'");
          @sr_unt = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and table_schema='$sch' and column_name='unit'");
      }
      else {
          @sr_dev = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and column_name='device'");
          @sr_typ = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and column_name='type'");
          @sr_evt = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and column_name='event'");
          @sr_rdg = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and column_name='reading'");
          @sr_val = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and column_name='value'");
          @sr_unt = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and column_name='unit'");

      }
  }
  if($dbmodel =~ /SQLITE/) {
      my $dev     = (DbLog_sqlget($hash,"SELECT sql FROM sqlite_master WHERE name = '$history'"))[0];
      $cdat_dev   = $dev // "no result";
      $cdat_typ   = $cdat_evt = $cdat_rdg = $cdat_val = $cdat_unt = $cdat_dev;
      ($cdat_dev) = $cdat_dev =~ /DEVICE.varchar\(([\d]+)\)/x;
      ($cdat_typ) = $cdat_typ =~ /TYPE.varchar\(([\d]+)\)/x;
      ($cdat_evt) = $cdat_evt =~ /EVENT.varchar\(([\d]+)\)/x;
      ($cdat_rdg) = $cdat_rdg =~ /READING.varchar\(([\d]+)\)/x;
      ($cdat_val) = $cdat_val =~ /VALUE.varchar\(([\d]+)\)/x;
      ($cdat_unt) = $cdat_unt =~ /UNIT.varchar\(([\d]+)\)/x;
  }
  if ($dbmodel !~ /SQLITE/)  {
      $cdat_dev = @sr_dev ? ($sr_dev[1]) : "no result";
      $cdat_dev =~ tr/varchar\(|\)//d if($cdat_dev ne "no result");
      $cdat_typ = @sr_typ ? ($sr_typ[1]) : "no result";
      $cdat_typ =~ tr/varchar\(|\)//d if($cdat_typ ne "no result");
      $cdat_evt = @sr_evt ? ($sr_evt[1]) : "no result";
      $cdat_evt =~ tr/varchar\(|\)//d if($cdat_evt ne "no result");
      $cdat_rdg = @sr_rdg ? ($sr_rdg[1]) : "no result";
      $cdat_rdg =~ tr/varchar\(|\)//d if($cdat_rdg ne "no result");
      $cdat_val = @sr_val ? ($sr_val[1]) : "no result";
      $cdat_val =~ tr/varchar\(|\)//d if($cdat_val ne "no result");
      $cdat_unt = @sr_unt ? ($sr_unt[1]) : "no result";
      $cdat_unt =~ tr/varchar\(|\)//d if($cdat_unt ne "no result");
  }
  $cmod_dev = $hash->{HELPER}{DEVICECOL};
  $cmod_typ = $hash->{HELPER}{TYPECOL};
  $cmod_evt = $hash->{HELPER}{EVENTCOL};
  $cmod_rdg = $hash->{HELPER}{READINGCOL};
  $cmod_val = $hash->{HELPER}{VALUECOL};
  $cmod_unt = $hash->{HELPER}{UNITCOL};

  if($cdat_dev >= $cmod_dev && $cdat_typ >= $cmod_typ && $cdat_evt >= $cmod_evt && $cdat_rdg >= $cmod_rdg && $cdat_val >= $cmod_val && $cdat_unt >= $cmod_unt) {
      $rec = "settings o.k.";
  }
  else {
      if ($dbmodel !~ /SQLITE/)  {
          $rec  = "The relation between column width in table $history and the field width used in device $name don't meet the requirements. ";
          $rec .= "Please make sure that the width of database field definition is equal or larger than the field width used by the module. Compare the given results.<br>";
          $rec .= "Currently the default values for field width are: <br><br>";
          $rec .= "DEVICE: $DbLog_columns{DEVICE} <br>";
          $rec .= "TYPE: $DbLog_columns{TYPE} <br>";
          $rec .= "EVENT: $DbLog_columns{EVENT} <br>";
          $rec .= "READING: $DbLog_columns{READING} <br>";
          $rec .= "VALUE: $DbLog_columns{VALUE} <br>";
          $rec .= "UNIT: $DbLog_columns{UNIT} <br><br>";
          $rec .= "You can change the column width in database by a statement like <b>'alter table $history modify VALUE varchar(128);</b>' (example for changing field 'VALUE'). ";
          $rec .= "You can do it for example by executing 'sqlCmd' in DbRep or in a SQL-Editor of your choice. (switch $name to asynchron mode for non-blocking). <br>";
          $rec .= "Alternatively the field width used by $name can be adjusted by setting attributes 'colEvent', 'colReading', 'colValue'. (pls. refer to commandref)";
      }
      else {
          $rec  = "WARNING - The relation between column width in table $history and the field width used by device $name should be equal but it differs.";
          $rec .= "The field width used by $name can be adjusted by setting attributes 'colEvent', 'colReading', 'colValue'. (pls. refer to commandref)";
          $rec .= "Because you use SQLite this is only a warning. Normally the database can handle these differences. ";
      }
  }

  $check .= "<u><b>Result of table '$history' check</u></b><br><br>";
  $check .= "Column width set in DB $history: 'DEVICE' = $cdat_dev, 'TYPE' = $cdat_typ, 'EVENT' = $cdat_evt, 'READING' = $cdat_rdg, 'VALUE' = $cdat_val, 'UNIT' = $cdat_unt <br>";
  $check .= "Column width used by $name: 'DEVICE' = $cmod_dev, 'TYPE' = $cmod_typ, 'EVENT' = $cmod_evt, 'READING' = $cmod_rdg, 'VALUE' = $cmod_val, 'UNIT' = $cmod_unt <br>";
  $check .= "<b>Recommendation:</b> $rec <br><br>";

  ### Check Spaltenbreite current
  #######################################################################
  if($dbmodel =~ /MYSQL/) {
      @sr_dev = DbLog_sqlget($hash,"SHOW FIELDS FROM $current where FIELD='DEVICE'");
      @sr_typ = DbLog_sqlget($hash,"SHOW FIELDS FROM $current where FIELD='TYPE'");
      @sr_evt = DbLog_sqlget($hash,"SHOW FIELDS FROM $current where FIELD='EVENT'");
      @sr_rdg = DbLog_sqlget($hash,"SHOW FIELDS FROM $current where FIELD='READING'");
      @sr_val = DbLog_sqlget($hash,"SHOW FIELDS FROM $current where FIELD='VALUE'");
      @sr_unt = DbLog_sqlget($hash,"SHOW FIELDS FROM $current where FIELD='UNIT'");
  }

  if($dbmodel =~ /POSTGRESQL/) {
      my $sch = AttrVal($name, "dbSchema", "");
      my $c   = "current";
      if($sch) {
          @sr_dev = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and table_schema='$sch' and column_name='device'");
          @sr_typ = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and table_schema='$sch' and column_name='type'");
          @sr_evt = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and table_schema='$sch' and column_name='event'");
          @sr_rdg = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and table_schema='$sch' and column_name='reading'");
          @sr_val = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and table_schema='$sch' and column_name='value'");
          @sr_unt = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and table_schema='$sch' and column_name='unit'");
      }
      else {
          @sr_dev = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and column_name='device'");
          @sr_typ = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and column_name='type'");
          @sr_evt = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and column_name='event'");
          @sr_rdg = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and column_name='reading'");
          @sr_val = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and column_name='value'");
          @sr_unt = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and column_name='unit'");

      }
  }
  if($dbmodel =~ /SQLITE/) {
      my $dev     = (DbLog_sqlget($hash,"SELECT sql FROM sqlite_master WHERE name = '$current'"))[0];
      $cdat_dev   = $dev // "no result";
      $cdat_typ   = $cdat_evt = $cdat_rdg = $cdat_val = $cdat_unt = $cdat_dev;
      ($cdat_dev) = $cdat_dev =~ /DEVICE.varchar\(([\d]+)\)/x;
      ($cdat_typ) = $cdat_typ =~ /TYPE.varchar\(([\d]+)\)/x;
      ($cdat_evt) = $cdat_evt =~ /EVENT.varchar\(([\d]+)\)/x;
      ($cdat_rdg) = $cdat_rdg =~ /READING.varchar\(([\d]+)\)/x;
      ($cdat_val) = $cdat_val =~ /VALUE.varchar\(([\d]+)\)/x;
      ($cdat_unt) = $cdat_unt =~ /UNIT.varchar\(([\d]+)\)/x;
  }
  if ($dbmodel !~ /SQLITE/)  {
      $cdat_dev = @sr_dev ? ($sr_dev[1]) : "no result";
      $cdat_dev =~ tr/varchar\(|\)//d if($cdat_dev ne "no result");
      $cdat_typ = @sr_typ ? ($sr_typ[1]) : "no result";
      $cdat_typ =~ tr/varchar\(|\)//d if($cdat_typ ne "no result");
      $cdat_evt = @sr_evt ? ($sr_evt[1]) : "no result";
      $cdat_evt =~ tr/varchar\(|\)//d if($cdat_evt ne "no result");
      $cdat_rdg = @sr_rdg ? ($sr_rdg[1]) : "no result";
      $cdat_rdg =~ tr/varchar\(|\)//d if($cdat_rdg ne "no result");
      $cdat_val = @sr_val ? ($sr_val[1]) : "no result";
      $cdat_val =~ tr/varchar\(|\)//d if($cdat_val ne "no result");
      $cdat_unt = @sr_unt ? ($sr_unt[1]) : "no result";
      $cdat_unt =~ tr/varchar\(|\)//d if($cdat_unt ne "no result");
  }
      $cmod_dev = $hash->{HELPER}{DEVICECOL};
      $cmod_typ = $hash->{HELPER}{TYPECOL};
      $cmod_evt = $hash->{HELPER}{EVENTCOL};
      $cmod_rdg = $hash->{HELPER}{READINGCOL};
      $cmod_val = $hash->{HELPER}{VALUECOL};
      $cmod_unt = $hash->{HELPER}{UNITCOL};

      if($cdat_dev >= $cmod_dev && $cdat_typ >= $cmod_typ && $cdat_evt >= $cmod_evt && $cdat_rdg >= $cmod_rdg && $cdat_val >= $cmod_val && $cdat_unt >= $cmod_unt) {
          $rec = "settings o.k.";
      }
      else {
          if ($dbmodel !~ /SQLITE/)  {
              $rec  = "The relation between column width in table $current and the field width used in device $name don't meet the requirements. ";
              $rec .= "Please make sure that the width of database field definition is equal or larger than the field width used by the module. Compare the given results.<br>";
              $rec .= "Currently the default values for field width are: <br><br>";
              $rec .= "DEVICE: $DbLog_columns{DEVICE} <br>";
              $rec .= "TYPE: $DbLog_columns{TYPE} <br>";
              $rec .= "EVENT: $DbLog_columns{EVENT} <br>";
              $rec .= "READING: $DbLog_columns{READING} <br>";
              $rec .= "VALUE: $DbLog_columns{VALUE} <br>";
              $rec .= "UNIT: $DbLog_columns{UNIT} <br><br>";
              $rec .= "You can change the column width in database by a statement like <b>'alter table $current modify VALUE varchar(128);</b>' (example for changing field 'VALUE'). ";
              $rec .= "You can do it for example by executing 'sqlCmd' in DbRep or in a SQL-Editor of your choice. (switch $name to asynchron mode for non-blocking). <br>";
              $rec .= "Alternatively the field width used by $name can be adjusted by setting attributes 'colEvent', 'colReading', 'colValue'. (pls. refer to commandref)";
          }
          else {
              $rec  = "WARNING - The relation between column width in table $current and the field width used by device $name should be equal but it differs. ";
              $rec .= "The field width used by $name can be adjusted by setting attributes 'colEvent', 'colReading', 'colValue'. (pls. refer to commandref)";
              $rec .= "Because you use SQLite this is only a warning. Normally the database can handle these differences. ";
          }
      }

      $check .= "<u><b>Result of table '$current' check</u></b><br><br>";
      $check .= "Column width set in DB $current: 'DEVICE' = $cdat_dev, 'TYPE' = $cdat_typ, 'EVENT' = $cdat_evt, 'READING' = $cdat_rdg, 'VALUE' = $cdat_val, 'UNIT' = $cdat_unt <br>";
      $check .= "Column width used by $name: 'DEVICE' = $cmod_dev, 'TYPE' = $cmod_typ, 'EVENT' = $cmod_evt, 'READING' = $cmod_rdg, 'VALUE' = $cmod_val, 'UNIT' = $cmod_unt <br>";
      $check .= "<b>Recommendation:</b> $rec <br><br>";
#}

  ### Check Vorhandensein Search_Idx mit den empfohlenen Spalten
  #######################################################################
  my (@six,@six_dev,@six_rdg,@six_tsp);
  my ($idef,$idef_dev,$idef_rdg,$idef_tsp);
  $check .= "<u><b>Result of check 'Search_Idx' availability</u></b><br><br>";

  if($dbmodel =~ /MYSQL/) {
      @six = DbLog_sqlget($hash,"SHOW INDEX FROM $history where Key_name='Search_Idx'");
      if (!@six) {
          $check .= "The index 'Search_Idx' is missing. <br>";
          $rec    = "You can create the index by executing statement <b>'CREATE INDEX Search_Idx ON `$history` (DEVICE, READING, TIMESTAMP) USING BTREE;'</b> <br>";
          $rec   .= "Depending on your database size this command may running a long time. <br>";
          $rec   .= "Please make sure the device '$name' is operating in asynchronous mode to avoid FHEM from blocking when creating the index. <br>";
          $rec   .= "<b>Note:</b> If you have just created another index which covers the same fields and order as suggested (e.g. a primary key) you don't need to create the 'Search_Idx' as well ! <br>";
      }
      else {
          @six_dev = DbLog_sqlget($hash,"SHOW INDEX FROM $history where Key_name='Search_Idx' and Column_name='DEVICE'");
          @six_rdg = DbLog_sqlget($hash,"SHOW INDEX FROM $history where Key_name='Search_Idx' and Column_name='READING'");
          @six_tsp = DbLog_sqlget($hash,"SHOW INDEX FROM $history where Key_name='Search_Idx' and Column_name='TIMESTAMP'");

          if (@six_dev && @six_rdg && @six_tsp) {
              $check .= "Index 'Search_Idx' exists and contains recommended fields 'DEVICE', 'TIMESTAMP', 'READING'. <br>";
              $rec    = "settings o.k.";
          }
          else {
              $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'DEVICE'. <br>" if (!@six_dev);
              $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'READING'. <br>" if (!@six_rdg);
              $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'TIMESTAMP'. <br>" if (!@six_tsp);
              $rec    = "The index should contain the fields 'DEVICE', 'TIMESTAMP', 'READING'. ";
              $rec   .= "You can change the index by executing e.g. <br>";
              $rec   .= "<b>'ALTER TABLE `$history` DROP INDEX `Search_Idx`, ADD INDEX `Search_Idx` (`DEVICE`, `READING`, `TIMESTAMP`) USING BTREE;'</b> <br>";
              $rec   .= "Depending on your database size this command may running a long time. <br>";
          }
      }
  }
  if($dbmodel =~ /POSTGRESQL/) {
      @six = DbLog_sqlget($hash,"SELECT * FROM pg_indexes WHERE tablename='$history' and indexname ='Search_Idx'");

      if (!@six) {
          $check .= "The index 'Search_Idx' is missing. <br>";
          $rec    = "You can create the index by executing statement <b>'CREATE INDEX \"Search_Idx\" ON $history USING btree (device, reading, \"timestamp\")'</b> <br>";
          $rec   .= "Depending on your database size this command may running a long time. <br>";
          $rec   .= "Please make sure the device '$name' is operating in asynchronous mode to avoid FHEM from blocking when creating the index. <br>";
          $rec   .= "<b>Note:</b> If you have just created another index which covers the same fields and order as suggested (e.g. a primary key) you don't need to create the 'Search_Idx' as well ! <br>";
      }
      else {
          $idef     = $six[4];
          $idef_dev = 1 if($idef =~ /device/);
          $idef_rdg = 1 if($idef =~ /reading/);
          $idef_tsp = 1 if($idef =~ /timestamp/);

          if ($idef_dev && $idef_rdg && $idef_tsp) {
              $check .= "Index 'Search_Idx' exists and contains recommended fields 'DEVICE', 'READING', 'TIMESTAMP'. <br>";
              $rec    = "settings o.k.";
          }
          else {
              $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'DEVICE'. <br>"    if (!$idef_dev);
              $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'READING'. <br>"   if (!$idef_rdg);
              $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'TIMESTAMP'. <br>" if (!$idef_tsp);
              $rec    = "The index should contain the fields 'DEVICE', 'READING', 'TIMESTAMP'. ";
              $rec   .= "You can change the index by executing e.g. <br>";
              $rec   .= "<b>'DROP INDEX \"Search_Idx\"; CREATE INDEX \"Search_Idx\" ON $history USING btree (device, reading, \"timestamp\")'</b> <br>";
              $rec   .= "Depending on your database size this command may running a long time. <br>";
          }
      }
  }
  if($dbmodel =~ /SQLITE/) {
      @six = DbLog_sqlget($hash,"SELECT name,sql FROM sqlite_master WHERE type='index' AND name='Search_Idx'");

      if (!$six[0]) {
          $check .= "The index 'Search_Idx' is missing. <br>";
          $rec    = "You can create the index by executing statement <b>'CREATE INDEX Search_Idx ON `$history` (DEVICE, READING, TIMESTAMP)'</b> <br>";
          $rec   .= "Depending on your database size this command may running a long time. <br>";
          $rec   .= "Please make sure the device '$name' is operating in asynchronous mode to avoid FHEM from blocking when creating the index. <br>";
          $rec   .= "<b>Note:</b> If you have just created another index which covers the same fields and order as suggested (e.g. a primary key) you don't need to create the 'Search_Idx' as well ! <br>";
      }
      else {
          $idef     = $six[1];
          $idef_dev = 1 if(lc($idef) =~ /device/);
          $idef_rdg = 1 if(lc($idef) =~ /reading/);
          $idef_tsp = 1 if(lc($idef) =~ /timestamp/);

          if ($idef_dev && $idef_rdg && $idef_tsp) {
              $check .= "Index 'Search_Idx' exists and contains recommended fields 'DEVICE', 'READING', 'TIMESTAMP'. <br>";
              $rec    = "settings o.k.";
          }
          else {
              $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'DEVICE'. <br>"    if (!$idef_dev);
              $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'READING'. <br>"   if (!$idef_rdg);
              $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'TIMESTAMP'. <br>" if (!$idef_tsp);
              $rec    = "The index should contain the fields 'DEVICE', 'READING', 'TIMESTAMP'. ";
              $rec   .= "You can change the index by executing e.g. <br>";
              $rec   .= "<b>'DROP INDEX \"Search_Idx\"; CREATE INDEX Search_Idx ON `$history` (DEVICE, READING, TIMESTAMP)'</b> <br>";
              $rec   .= "Depending on your database size this command may running a long time. <br>";
          }
      }
  }

  $check .= "<b>Recommendation:</b> $rec <br><br>";

  ### Check Index Report_Idx für DbRep-Device falls DbRep verwendet wird
  #######################################################################
  my (@dix,@dix_rdg,@dix_tsp,$irep_rdg,$irep_tsp,$irep);
  my $isused = 0;
  my @repdvs = devspec2array("TYPE=DbRep");
  $check    .= "<u><b>Result of check 'Report_Idx' availability for DbRep-devices</u></b><br><br>";

  for my $dbrp (@repdvs) {
      if(!$defs{$dbrp}) {
          Log3 ($name, 2, "DbLog $name -> Device '$dbrp' found by configCheck doesn't exist !");
          next;
      }
      if ($defs{$dbrp}->{DEF} eq $name) {
          # DbRep Device verwendet aktuelles DbLog-Device
          Log3 ($name, 5, "DbLog $name -> DbRep-Device '$dbrp' uses $name.");
          $isused = 1;
      }
  }
  if ($isused) {
      if($dbmodel =~ /MYSQL/) {
          @dix = DbLog_sqlget($hash,"SHOW INDEX FROM $history where Key_name='Report_Idx'");

          if (!@dix) {
              $check .= "At least one DbRep-device assigned to $name is used, but the recommended index 'Report_Idx' is missing. <br>";
              $rec    = "You can create the index by executing statement <b>'CREATE INDEX Report_Idx ON `$history` (TIMESTAMP,READING) USING BTREE;'</b> <br>";
              $rec   .= "Depending on your database size this command may running a long time. <br>";
              $rec   .= "Please make sure the device '$name' is operating in asynchronous mode to avoid FHEM from blocking when creating the index. <br>";
              $rec   .= "<b>Note:</b> If you have just created another index which covers the same fields and order as suggested (e.g. a primary key) you don't need to create the 'Report_Idx' as well ! <br>";
          }
          else {
              @dix_rdg = DbLog_sqlget($hash,"SHOW INDEX FROM $history where Key_name='Report_Idx' and Column_name='READING'");
              @dix_tsp = DbLog_sqlget($hash,"SHOW INDEX FROM $history where Key_name='Report_Idx' and Column_name='TIMESTAMP'");

              if (@dix_rdg && @dix_tsp) {
                  $check .= "At least one DbRep-device assigned to $name is used. ";
                  $check .= "Index 'Report_Idx' exists and contains recommended fields 'TIMESTAMP', 'READING'. <br>";
                  $rec    = "settings o.k.";
              }
              else {
                  $check .= "You use at least one DbRep-device assigned to $name. ";
                  $check .= "Index 'Report_Idx' exists but doesn't contain recommended field 'READING'. <br>" if (!@dix_rdg);
                  $check .= "Index 'Report_Idx' exists but doesn't contain recommended field 'TIMESTAMP'. <br>" if (!@dix_tsp);
                  $rec    = "The index should contain the fields 'TIMESTAMP', 'READING'. ";
                  $rec   .= "You can change the index by executing e.g. <br>";
                  $rec   .= "<b>'ALTER TABLE `$history` DROP INDEX `Report_Idx`, ADD INDEX `Report_Idx` (`TIMESTAMP`, `READING`) USING BTREE'</b> <br>";
                  $rec   .= "Depending on your database size this command may running a long time. <br>";
              }
          }
      }
      if($dbmodel =~ /POSTGRESQL/) {
          @dix = DbLog_sqlget($hash,"SELECT * FROM pg_indexes WHERE tablename='$history' and indexname ='Report_Idx'");

          if (!@dix) {
              $check .= "You use at least one DbRep-device assigned to $name, but the recommended index 'Report_Idx' is missing. <br>";
              $rec    = "You can create the index by executing statement <b>'CREATE INDEX \"Report_Idx\" ON $history USING btree (\"timestamp\", reading)'</b> <br>";
              $rec   .= "Depending on your database size this command may running a long time. <br>";
              $rec   .= "Please make sure the device '$name' is operating in asynchronous mode to avoid FHEM from blocking when creating the index. <br>";
              $rec   .= "<b>Note:</b> If you have just created another index which covers the same fields and order as suggested (e.g. a primary key) you don't need to create the 'Report_Idx' as well ! <br>";
          }
          else {
              $irep     = $dix[4];
              $irep_rdg = 1 if($irep =~ /reading/);
              $irep_tsp = 1 if($irep =~ /timestamp/);

              if ($irep_rdg && $irep_tsp) {
                  $check .= "Index 'Report_Idx' exists and contains recommended fields 'TIMESTAMP', 'READING'. <br>";
                  $rec    = "settings o.k.";
              }
              else {
                  $check .= "Index 'Report_Idx' exists but doesn't contain recommended field 'READING'. <br>" if (!$irep_rdg);
                  $check .= "Index 'Report_Idx' exists but doesn't contain recommended field 'TIMESTAMP'. <br>" if (!$irep_tsp);
                  $rec    = "The index should contain the fields 'TIMESTAMP', 'READING'. ";
                  $rec   .= "You can change the index by executing e.g. <br>";
                  $rec   .= "<b>'DROP INDEX \"Report_Idx\"; CREATE INDEX \"Report_Idx\" ON $history USING btree (\"timestamp\", reading)'</b> <br>";
                  $rec   .= "Depending on your database size this command may running a long time. <br>";
              }
          }
      }
      if($dbmodel =~ /SQLITE/) {
          @dix = DbLog_sqlget($hash,"SELECT name,sql FROM sqlite_master WHERE type='index' AND name='Report_Idx'");

          if (!$dix[0]) {
              $check .= "The index 'Report_Idx' is missing. <br>";
              $rec    = "You can create the index by executing statement <b>'CREATE INDEX Report_Idx ON `$history` (TIMESTAMP,READING)'</b> <br>";
              $rec   .= "Depending on your database size this command may running a long time. <br>";
              $rec   .= "Please make sure the device '$name' is operating in asynchronous mode to avoid FHEM from blocking when creating the index. <br>";
              $rec   .= "<b>Note:</b> If you have just created another index which covers the same fields and order as suggested (e.g. a primary key) you don't need to create the 'Search_Idx' as well ! <br>";
          }
          else {
              $irep     = $dix[1];
              $irep_rdg = 1 if(lc($irep) =~ /reading/);
              $irep_tsp = 1 if(lc($irep) =~ /timestamp/);

              if ($irep_rdg && $irep_tsp) {
                  $check .= "Index 'Report_Idx' exists and contains recommended fields 'TIMESTAMP', 'READING'. <br>";
                  $rec    = "settings o.k.";
              }
              else {
                  $check .= "Index 'Report_Idx' exists but doesn't contain recommended field 'READING'. <br>" if (!$irep_rdg);
                  $check .= "Index 'Report_Idx' exists but doesn't contain recommended field 'TIMESTAMP'. <br>" if (!$irep_tsp);
                  $rec    = "The index should contain the fields 'TIMESTAMP', 'READING'. ";
                  $rec   .= "You can change the index by executing e.g. <br>";
                  $rec   .= "<b>'DROP INDEX \"Report_Idx\"; CREATE INDEX Report_Idx ON `$history` (TIMESTAMP,READING)'</b> <br>";
                  $rec   .= "Depending on your database size this command may running a long time. <br>";
              }
          }
      }

  }
  else {
      $check .= "No DbRep-device assigned to $name is used. Hence an index for DbRep isn't needed. <br>";
      $rec    = "settings o.k.";
  }
  $check .= "<b>Recommendation:</b> $rec <br><br>";

  $check .= "</html>";

return $check;
}

#########################################################################################
#                  check Modul Aktualität fhem.de <-> local
#########################################################################################
sub DbLog_checkModVer {
  my $name = shift;
  my $src  = "http://fhem.de/fhemupdate/controls_fhem.txt";

  if($src !~ m,^(.*)/([^/]*)$,) {
    Log3 $name, 1, "DbLog $name -> configCheck: Cannot parse $src, probably not a valid http control file";
    return ("check of new DbLog version not possible, see logfile.");
  }

  my $basePath     = $1;
  my $ctrlFileName = $2;

  my ($remCtrlFile, $err) = DbLog_updGetUrl($name,$src);
  return ("check of new DbLog version not possible: $err") if($err);

  if(!$remCtrlFile) {
      Log3 $name, 1, "DbLog $name -> configCheck: No valid remote control file";
      return ("check of new DbLog version not possible, see logfile.");
  }

  my @remList = split(/\R/, $remCtrlFile);
  Log3 $name, 4, "DbLog $name -> configCheck: Got remote $ctrlFileName with ".int(@remList)." entries.";

  my $root = $attr{global}{modpath};

  my @locList;
  if(open(FD, "$root/FHEM/$ctrlFileName")) {
      @locList = map { $_ =~ s/[\r\n]//; $_ } <FD>;
      close(FD);
      Log3 $name, 4, "DbLog $name -> configCheck: Got local $ctrlFileName with ".int(@locList)." entries.";
  }
  else {
      Log3 $name, 1, "DbLog $name -> configCheck: can't open $root/FHEM/$ctrlFileName: $!";
      return ("check of new DbLog version not possible, see logfile.");
  }

  my %lh;
  
  for my $l (@locList) {
      my @l = split(" ", $l, 4);
      next if($l[0] ne "UPD" || $l[3] !~ /93_DbLog/);
      $lh{$l[3]}{TS} = $l[1];
      $lh{$l[3]}{LEN} = $l[2];
      Log3 $name, 4, "DbLog $name -> configCheck: local version from last update - creation time: ".$lh{$l[3]}{TS}." - bytes: ".$lh{$l[3]}{LEN};
  }

  my $noSzCheck = AttrVal("global", "updateNoFileCheck", configDBUsed());

  for my $rem (@remList) {
      my @r = split(" ", $rem, 4);
      next if($r[0] ne "UPD" || $r[3] !~ /93_DbLog/);
      my $fName  = $r[3];
      my $fPath  = "$root/$fName";
      my $fileOk = ($lh{$fName} && $lh{$fName}{TS} eq $r[1] && $lh{$fName}{LEN} eq $r[2]);
      if(!$fileOk) {
          Log3 $name, 4, "DbLog $name -> configCheck: New remote version of $fName found - creation time: ".$r[1]." - bytes: ".$r[2];
          return ("",1,"A new DbLog version is available (creation time: $r[1], size: $r[2] bytes)");
      }
      if(!$noSzCheck) {
          my $sz = -s $fPath;
          if($fileOk && defined($sz) && $sz ne $r[2]) {
              Log3 $name, 4, "DbLog $name -> configCheck: remote version of $fName (creation time: $r[1], bytes: $r[2]) differs from local one (bytes: $sz)";
              return ("",1,"Your local DbLog module is modified.");
          }
      }
      last;
  }

return ("",0,"Your local DbLog module is up to date.");
}

###################################
sub DbLog_updGetUrl {
  my ($name,$url) = @_;

  my %upd_connecthash;

  $url                        =~ s/%/%25/g;
  $upd_connecthash{url}       = $url;
  $upd_connecthash{keepalive} = ($url =~ m/localUpdate/ ? 0 : 1); # Forum #49798

  my ($err, $data) = HttpUtils_BlockingGet(\%upd_connecthash);
  if($err) {
      Log3 $name, 1, "DbLog $name -> configCheck: ERROR while connecting to fhem.de:  $err";
      return ("",$err);
  }
  if(!$data) {
      Log3 $name, 1, "DbLog $name -> configCheck: ERROR $url: empty file received";
      $err = 1;
      return ("",$err);
  }

return ($data,"");
}

#########################################################################################
#                  Einen (einfachen) Datensatz aus DB lesen
#########################################################################################
sub DbLog_sqlget {
  my ($hash,$sql) = @_;
  my $name        = $hash->{NAME};

  my ($dbh,$sth,@sr);

  Log3 ($name, 4, "DbLog $name - Executing SQL: $sql");

  $dbh = _DbLog_ConnectNewDBH($hash);
  return if(!$dbh);

  eval { $sth = $dbh->prepare("$sql");
         $sth->execute;
       };
  if($@) {
      $dbh->disconnect if($dbh);
      Log3 ($name, 2, "DbLog $name - $@");
      return @sr;
  }

  @sr = $sth->fetchrow;

  $sth->finish;
  $dbh->disconnect;
  no warnings 'uninitialized';
  Log3 ($name, 4, "DbLog $name - SQL result: @sr");
  use warnings;

return @sr;
}

#########################################################################################
#
# Addlog - einfügen des Readingwertes eines gegebenen Devices
#
#########################################################################################
sub DbLog_AddLog {
  my ($hash,$devrdspec,$value,$nce,$cn) = @_;
  my $name                              = $hash->{NAME};
  my $async                             = AttrVal($name, "asyncMode", undef);
  my $value_fn                          = AttrVal( $name, "valueFn", "" );
  my $ce                                = AttrVal($name, "cacheEvents", 0);

  my ($dev_type,$dev_name,$dev_reading,$read_val,$event,$ut);
  my @row_array;
  my $ts;

  return if(IsDisabled($name) || !$hash->{HELPER}{COLSET} || $init_done != 1);

  # Funktion aus Attr valueFn validieren
  if( $value_fn =~ m/^\s*(\{.*\})\s*$/s ) {
      $value_fn = $1;
  }
  else {
      $value_fn = '';
  }

  my $now    = gettimeofday();
  my $rdspec = (split ":",$devrdspec)[-1];
  my @dc     = split(":",$devrdspec);
  pop @dc;
  my $devspec = join(':',@dc);

  my @exdvs = devspec2array($devspec);

  Log3 $name, 4, "DbLog $name -> Addlog known devices by devspec: @exdvs";

  for (@exdvs) {
      $dev_name = $_;
      if(!$defs{$dev_name}) {
          Log3 $name, 2, "DbLog $name -> Device '$dev_name' used by addLog doesn't exist !";
          next;
      }

      my $r            = $defs{$dev_name}{READINGS};
      my $DbLogExclude = AttrVal($dev_name, "DbLogExclude", undef);
      my $DbLogInclude = AttrVal($dev_name, "DbLogInclude", undef);
      my @exrds;
      my $found = 0;

      for my $rd (sort keys %{$r}) {                                          # jedes Reading des Devices auswerten
           my $do = 1;
           $found = 1 if($rd =~ m/^$rdspec$/);                                # Reading gefunden
           if($DbLogExclude && !$nce) {
               my @v1 = split(/,/, $DbLogExclude);
               for (my $i=0; $i<int(@v1); $i++) {
                   my @v2 = split(/:/, $v1[$i]);                              # MinInterval wegschneiden, Bsp: "(temperature|humidity):600,battery:3600"
                   if($rd =~ m,^$v2[0]$,) {                                   # Reading matcht $DbLogExclude -> ausschließen vom addLog
                       $do = 0;
                       if($DbLogInclude) {
                           my @v3 = split(/,/, $DbLogInclude);
                           for (my $i=0; $i<int(@v3); $i++) {
                               my @v4 = split(/:/, $v3[$i]);
                               $do = 1 if($rd =~ m,^$v4[0]$,);                # Reading matcht $DbLogInclude -> wieder in addLog einschließen
                           }
                       }
                       Log3 $name, 2, "DbLog $name -> Device: \"$dev_name\", reading: \"$v2[0]\" excluded by attribute DbLogExclude from addLog !" if($do == 0 && $rd =~ m/^$rdspec$/);
                   }
               }
           }
           next if(!$do);
           push @exrds,$rd if($rd =~ m/^$rdspec$/);
      }

      Log3 $name, 4, "DbLog $name -> Readings extracted from Regex: @exrds";

      if(!$found) {
          if(goodReadingName($rdspec) && defined($value)) {
              Log3 $name, 3, "DbLog $name -> addLog WARNING - Device: '$dev_name' -> Reading '$rdspec' not found - add it as new reading.";
              push @exrds,$rdspec;
          }
          elsif (goodReadingName($rdspec) && !defined($value)) {
              Log3 $name, 2, "DbLog $name -> addLog WARNING - Device: '$dev_name' -> new Reading '$rdspec' has no value - can't add it !";
          }
          else {
              Log3 $name, 2, "DbLog $name -> addLog WARNING - Device: '$dev_name' -> Readingname '$rdspec' is no valid or regexp - can't add regexp as new reading !";
          }
      }

      no warnings 'uninitialized';
      
      for (@exrds) {
          $dev_reading = $_;
          $read_val = $value ne "" ? $value : ReadingsVal($dev_name,$dev_reading,"");
          $dev_type = uc($defs{$dev_name}{TYPE});

          # dummy-Event zusammenstellen
          $event = $dev_reading.": ".$read_val;

          # den zusammengestellten Event parsen lassen (evtl. Unit zuweisen)
          my @r = DbLog_ParseEvent($name,$dev_name, $dev_type, $event);
          $dev_reading = $r[0];
          $read_val    = $r[1];
          $ut          = $r[2];
          if(!defined $dev_reading)     {$dev_reading = "";}
          if(!defined $read_val)        {$read_val = "";}
          if(!defined $ut || $ut eq "") {$ut = AttrVal("$dev_name", "unit", "");}

          $event       = "addLog";

          $defs{$dev_name}{Helper}{DBLOG}{$dev_reading}{$name}{TIME}  = $now;
          $defs{$dev_name}{Helper}{DBLOG}{$dev_reading}{$name}{VALUE} = $read_val;

          $ts = TimeNow();

          my $ctz = AttrVal($name, 'convertTimezone', 'none');                                               # convert time zone
          if($ctz ne 'none') {
              my $err;
              my $params = {
                  name      => $name,
                  dtstring  => $ts,
                  tzcurrent => 'local',
                  tzconv    => $ctz,
                  writelog  => 0
              };

              ($err, $ts) = convertTimeZone ($params);

              if ($err) {
                  Log3 ($name, 1, "DbLog $name - ERROR while converting time zone: $err - exit log loop !");
                  last;
              }
          }

          # Anwender spezifische Funktion anwenden
          if($value_fn ne '') {
              my $lastt = $defs{$dev_name}{Helper}{DBLOG}{$dev_reading}{$name}{TIME};            # patch Forum:#111423
              my $lastv = $defs{$dev_name}{Helper}{DBLOG}{$dev_reading}{$name}{VALUE};

              my $TIMESTAMP     = $ts;
              my $LASTTIMESTAMP = $lastt // 0;                                                   # patch Forum:#111423
              my $DEVICE        = $dev_name;
              my $DEVICETYPE    = $dev_type;
              my $EVENT         = $event;
              my $READING       = $dev_reading;
              my $VALUE         = $read_val;
              my $LASTVALUE     = $lastv // "";                                                  # patch Forum:#111423
              my $UNIT          = $ut;
              my $IGNORE        = 0;
              my $CN            = $cn ? $cn : "";

              eval $value_fn;
              Log3 $name, 2, "DbLog $name -> error valueFn: ".$@ if($@);

              if($IGNORE) {                                                                                # aktueller Event wird nicht geloggt wenn $IGNORE=1 gesetzt
                 $defs{$dev_name}{Helper}{DBLOG}{$dev_reading}{$name}{TIME}  = $lastt if($lastt);  # patch Forum:#111423
                 $defs{$dev_name}{Helper}{DBLOG}{$dev_reading}{$name}{VALUE} = $lastv if(defined $lastv);
                 next;
              }

              my ($yyyy, $mm, $dd, $hh, $min, $sec) = ($TIMESTAMP =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
              eval { my $epoch_seconds_begin = timelocal($sec, $min, $hh, $dd, $mm-1, $yyyy-1900); };
              if (!$@) {
                  $ts = $TIMESTAMP;
              }
              else {
                  Log3 ($name, 2, "DbLog $name -> Parameter TIMESTAMP got from valueFn is invalid: $TIMESTAMP");
              }

              $dev_name     = $DEVICE     if($DEVICE ne '');
              $dev_type     = $DEVICETYPE if($DEVICETYPE ne '');
              $dev_reading  = $READING    if($READING ne '');
              $read_val     = $VALUE      if(defined $VALUE);
              $ut           = $UNIT       if(defined $UNIT);
          }

          # Daten auf maximale Länge beschneiden
          ($dev_name,$dev_type,$event,$dev_reading,$read_val,$ut) = DbLog_cutCol($hash,$dev_name,$dev_type,$event,$dev_reading,$read_val,$ut);

          if(AttrVal($name, "useCharfilter",0)) {
              $dev_reading = DbLog_charfilter($dev_reading);
              $read_val    = DbLog_charfilter($read_val);
          }

          my $row = ($ts."|".$dev_name."|".$dev_type."|".$event."|".$dev_reading."|".$read_val."|".$ut);
          Log3 $name, 3, "DbLog $name -> addLog created - TS: $ts, Device: $dev_name, Type: $dev_type, Event: $event, Reading: $dev_reading, Value: $read_val, Unit: $ut"
              if(!AttrVal($name, "suppressAddLogV3",0));

          if($async) {
              # asynchoner non-blocking Mode
              # Cache & CacheIndex für Events zum asynchronen Schreiben in DB
              $data{DbLog}{$name}{cache}{index}++;
              my $index = $data{DbLog}{$name}{cache}{index};
              $data{DbLog}{$name}{cache}{memcache}{$index} = $row;

              my $memcount = $data{DbLog}{$name}{cache}{memcache} ?
                             scalar(keys %{$data{DbLog}{$name}{cache}{memcache}}) :
                             0;

              if($ce == 1) {
                  readingsSingleUpdate($hash, "CacheUsage", $memcount, 1);
              }
              else {
                  readingsSingleUpdate($hash, 'CacheUsage', $memcount, 0);
              }
          }
          else {
              # synchoner Mode
              push(@row_array, $row);
          }
      }
      use warnings;
  }

  if(!$async) {
      if(@row_array) {
          # synchoner Mode
          # return wenn "reopen" mit Ablaufzeit gestartet ist
          return if($hash->{HELPER}{REOPEN_RUNS});
          my $error = DbLog_Push($hash, 1, @row_array);

          my $state = $error ? $error : (IsDisabled($name)) ? "disabled" : "connected";
          DbLog_setReadingstate ($hash, $state);

          Log3 $name, 5, "DbLog $name -> DbLog_Push Returncode: $error";
      }
  }
return;
}

#########################################################################################
#
# Subroutine addCacheLine - einen Datensatz zum Cache hinzufügen
#
#########################################################################################
sub DbLog_addCacheLine {
  my ($hash,$i_timestamp,$i_dev,$i_type,$i_evt,$i_reading,$i_val,$i_unit) = @_;
  my $name     = $hash->{NAME};
  my $ce       = AttrVal($name, "cacheEvents", 0);
  my $value_fn = AttrVal( $name, "valueFn", "" );

  # Funktion aus Attr valueFn validieren
  if( $value_fn =~ m/^\s*(\{.*\})\s*$/s ) {
      $value_fn = $1;
  }
  else {
      $value_fn = '';
  }

  if($value_fn ne '') {
      my $lastt;
      my $lastv;
      if($defs{$i_dev}) {
          $lastt = $defs{$i_dev}{Helper}{DBLOG}{$i_reading}{$name}{TIME};
          $lastv = $defs{$i_dev}{Helper}{DBLOG}{$i_reading}{$name}{VALUE};
      }

      my $TIMESTAMP     = $i_timestamp;
      my $LASTTIMESTAMP = $lastt // 0;                       # patch Forum:#111423
      my $DEVICE        = $i_dev;
      my $DEVICETYPE    = $i_type;
      my $EVENT         = $i_evt;
      my $READING       = $i_reading;
      my $VALUE         = $i_val;
      my $LASTVALUE     = $lastv // "";                      # patch Forum:#111423
      my $UNIT          = $i_unit;
      my $IGNORE        = 0;
      my $CN            = " ";

      eval $value_fn;
      Log3 $name, 2, "DbLog $name -> error valueFn: ".$@ if($@);

      if($IGNORE) {                                                                                               # kein add wenn $IGNORE=1 gesetzt
          $defs{$i_dev}{Helper}{DBLOG}{$i_reading}{$name}{TIME}  = $lastt if($defs{$i_dev} && $lastt);            # patch Forum:#111423
          $defs{$i_dev}{Helper}{DBLOG}{$i_reading}{$name}{VALUE} = $lastv if($defs{$i_dev} && defined $lastv);
          
          Log3 $name, 4, "DbLog $name -> Event ignored by valueFn - TS: $i_timestamp, Device: $i_dev, Type: $i_type, Event: $i_evt, Reading: $i_reading, Value: $i_val, Unit: $i_unit";
          
          next;
      }

      my ($yyyy, $mm, $dd, $hh, $min, $sec) = ($TIMESTAMP =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
      eval { my $epoch_seconds_begin = timelocal($sec, $min, $hh, $dd, $mm-1, $yyyy-1900); };
      if (!$@) {
          $i_timestamp = $TIMESTAMP;
      }
      else {
          Log3 ($name, 2, "DbLog $name -> Parameter TIMESTAMP got from valueFn is invalid: $TIMESTAMP");
      }

      $i_dev       = $DEVICE     if($DEVICE ne '');
      $i_type      = $DEVICETYPE if($DEVICETYPE ne '');
      $i_reading   = $READING    if($READING ne '');
      $i_val       = $VALUE      if(defined $VALUE);
      $i_unit      = $UNIT       if(defined $UNIT);
  }

  no warnings 'uninitialized';
  # Daten auf maximale Länge beschneiden
  ($i_dev,$i_type,$i_evt,$i_reading,$i_val,$i_unit) = DbLog_cutCol($hash,$i_dev,$i_type,$i_evt,$i_reading,$i_val,$i_unit);

  my $row = ($i_timestamp."|".$i_dev."|".$i_type."|".$i_evt."|".$i_reading."|".$i_val."|".$i_unit);
  $row    = DbLog_charfilter($row) if(AttrVal($name, "useCharfilter",0));
  
  Log3 $name, 3, "DbLog $name -> added by addCacheLine - TS: $i_timestamp, Device: $i_dev, Type: $i_type, Event: $i_evt, Reading: $i_reading, Value: $i_val, Unit: $i_unit";
  
  use warnings;

  eval {                                                                            # one transaction
      $data{DbLog}{$name}{cache}{index}++;
      my $index = $data{DbLog}{$name}{cache}{index};
      $data{DbLog}{$name}{cache}{memcache}{$index} = $row;

      my $memcount = $data{DbLog}{$name}{cache}{memcache}?scalar(keys %{$data{DbLog}{$name}{cache}{memcache}}):0;
      if($ce == 1) {
          readingsSingleUpdate($hash, "CacheUsage", $memcount, 1);
      }
      else {
          readingsSingleUpdate($hash, 'CacheUsage', $memcount, 0);
      }
  };

return;
}

#########################################################################################
#
# Subroutine cutCol - Daten auf maximale Länge beschneiden
#
#########################################################################################
sub DbLog_cutCol {
  my ($hash,$dn,$dt,$evt,$rd,$val,$unit) = @_;
  my $name       = $hash->{NAME};
  my $colevent   = AttrVal($name, 'colEvent', undef);
  my $colreading = AttrVal($name, 'colReading', undef);
  my $colvalue   = AttrVal($name, 'colValue', undef);

  if ($hash->{MODEL} ne 'SQLITE' || defined($colevent) || defined($colreading) || defined($colvalue) ) {
      $dn   = substr($dn,0, $hash->{HELPER}{DEVICECOL});
      $dt   = substr($dt,0, $hash->{HELPER}{TYPECOL});
      $evt  = substr($evt,0, $hash->{HELPER}{EVENTCOL});
      $rd   = substr($rd,0, $hash->{HELPER}{READINGCOL});
      $val  = substr($val,0, $hash->{HELPER}{VALUECOL});
      $unit = substr($unit,0, $hash->{HELPER}{UNITCOL}) if($unit);
  }
return ($dn,$dt,$evt,$rd,$val,$unit);
}

###############################################################################
#   liefert zurück ob Autocommit ($useac) bzw. Transaktion ($useta)
#   verwendet werden soll
#
#   basic_ta:on   - Autocommit Servereinstellung / Transaktion ein
#   basic_ta:off  - Autocommit Servereinstellung / Transaktion aus
#   ac:on_ta:on   - Autocommit ein / Transaktion ein
#   ac:on_ta:off  - Autocommit ein / Transaktion aus
#   ac:off_ta:on  - Autocommit aus / Transaktion ein (AC aus impliziert TA ein)
#
#   Autocommit:   0/1/2 = aus/ein/Servereinstellung
#   Transaktion:  0/1   = aus/ein
###############################################################################
sub DbLog_commitMode {
  my $name = shift;
  my $cm   = shift;
  
  my $useac  = 2;      # default Servereinstellung
  my $useta  = 1;      # default Transaktion ein

  my ($ac,$ta) = split "_", $cm;
  
  $useac = ($ac =~ /off/) ? 0 :
           ($ac =~ /on/)  ? 1 : 
           2;
                
  $useta = 0 if($ta =~ /off/);

return ($useac,$useta);
}

###############################################################################
#              Zeichen von Feldevents filtern
###############################################################################
sub DbLog_charfilter {
  my $txt = shift;

  my ($p,$a);

  # nur erwünschte Zeichen ASCII %d32-126 und Sonderzeichen
  $txt =~ s/ß/ss/g;
  $txt =~ s/ä/ae/g;
  $txt =~ s/ö/oe/g;
  $txt =~ s/ü/ue/g;
  $txt =~ s/Ä/Ae/g;
  $txt =~ s/Ö/Oe/g;
  $txt =~ s/Ü/Ue/g;
  $txt =~ s/€/EUR/g;
  $txt =~ s/\xb0/1degree1/g;

  $txt =~ tr/ A-Za-z0-9!"#$%&'()*+,-.\/:;<=>?@[\\]^_`{|}~//cd;

  $txt =~ s/1degree1/°/g;

return($txt);
}

#########################################################################################
### DBLog - Historische Werte ausduennen (alte blockiernde Variante) > Forum #41089
#########################################################################################
sub DbLog_reduceLog {
    my ($hash,@a) = @_;
    my $history   = $hash->{HELPER}{TH};
    my $current   = $hash->{HELPER}{TC};
    my ($ret,$row,$err,$filter,$exclude,$c,$day,$hour,$lastHour,$updDate,$updHour,$average,$processingDay,$lastUpdH,%hourlyKnown,%averageHash,@excludeRegex,@dayRows,@averageUpd,@averageUpdD);
    my ($name,$startTime,$currentHour,$currentDay,$deletedCount,$updateCount,$sum,$rowCount,$excludeCount) = ($hash->{NAME},time(),99,0,0,0,0,0,0);
    my $dbh = _DbLog_ConnectNewDBH($hash);
    return if(!$dbh);

    if ($a[-1] =~ /^EXCLUDE=(.+:.+)+/i) {
        ($filter) = $a[-1] =~ /^EXCLUDE=(.+)/i;
        @excludeRegex = split(',',$filter);
    } elsif ($a[-1] =~ /^INCLUDE=.+:.+$/i) {
        $filter = 1;
    }
    if (defined($a[3])) {
        $average = ($a[3] =~ /average=day/i) ? "AVERAGE=DAY" : ($a[3] =~ /average/i) ? "AVERAGE=HOUR" : 0;
    }
    Log3($name, 3, "DbLog $name: reduceLog requested with DAYS=$a[2]"
        .(($average || $filter) ? ', ' : '').(($average) ? "$average" : '')
        .(($average && $filter) ? ", " : '').(($filter) ? uc((split('=',$a[-1]))[0]).'='.(split('=',$a[-1]))[1] : ''));

    my ($useac,$useta) = DbLog_commitMode ($name, AttrVal($name, 'commitMode', 'basic_ta:on'));
    my $ac             = ($dbh->{AutoCommit}) ? "ON" : "OFF";
    my $tm             = ($useta)             ? "ON" : "OFF";

    Log3 ($name, 4, "DbLog $name -> AutoCommit mode: $ac, Transaction mode: $tm");

    my ($od,$nd) = split(":",$a[2]);         # $od - Tage älter als , $nd - Tage neuer als
    my ($ots,$nts);

    if ($hash->{MODEL} eq 'SQLITE') {
        $ots = "datetime('now', '-$od days')";
        $nts = "datetime('now', '-$nd days')" if($nd);
    }
    elsif ($hash->{MODEL} eq 'MYSQL') {
        $ots = "DATE_SUB(CURDATE(),INTERVAL $od DAY)";
        $nts = "DATE_SUB(CURDATE(),INTERVAL $nd DAY)" if($nd);
    }
    elsif ($hash->{MODEL} eq 'POSTGRESQL') {
        $ots = "NOW() - INTERVAL '$od' DAY";
        $nts = "NOW() - INTERVAL '$nd' DAY" if($nd);
    }
    else {
        $ret = 'Unknown database type.';
    }

    if ($ots) {
        my ($sth_del, $sth_upd, $sth_delD, $sth_updD, $sth_get);
        eval { $sth_del  = $dbh->prepare_cached("DELETE FROM $history WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?) AND (VALUE=?)");
               $sth_upd  = $dbh->prepare_cached("UPDATE $history SET TIMESTAMP=?, EVENT=?, VALUE=? WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?) AND (VALUE=?)");
               $sth_delD = $dbh->prepare_cached("DELETE FROM $history WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?)");
               $sth_updD = $dbh->prepare_cached("UPDATE $history SET TIMESTAMP=?, EVENT=?, VALUE=? WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?)");
               $sth_get  = $dbh->prepare("SELECT TIMESTAMP,DEVICE,'',READING,VALUE FROM $history WHERE "
                           .($a[-1] =~ /^INCLUDE=(.+):(.+)$/i ? "DEVICE like '$1' AND READING like '$2' AND " : '')
                           ."TIMESTAMP < $ots".($nts?" AND TIMESTAMP >= $nts ":" ")."ORDER BY TIMESTAMP ASC");  # '' was EVENT, no longer in use
             };

        $sth_get->execute();

        do {
            $row = $sth_get->fetchrow_arrayref || ['0000-00-00 00:00:00','D','','R','V'];  # || execute last-day dummy
            $ret = 1;
            ($day,$hour) = $row->[0] =~ /-(\d{2})\s(\d{2}):/;
            $rowCount++ if($day != 00);
            if ($day != $currentDay) {
                if ($currentDay) { # false on first executed day
                    if (scalar @dayRows) {
                        ($lastHour) = $dayRows[-1]->[0] =~ /(.*\d+\s\d{2}):/;
                        $c = 0;
                        for my $delRow (@dayRows) {
                            $c++ if($day != 00 || $delRow->[0] !~ /$lastHour/);
                        }
                        if($c) {
                            $deletedCount += $c;
                            Log3($name, 3, "DbLog $name: reduceLog deleting $c records of day: $processingDay");
                            $dbh->{RaiseError} = 1;
                            $dbh->{PrintError} = 0;
                            eval {$dbh->begin_work() if($dbh->{AutoCommit});};
                            eval {
                                my $i = 0;
                                my $k = 1;
                                my $th = ($#dayRows <= 2000)  ? 100  :
                                         ($#dayRows <= 30000) ? 1000 :
                                         10000;

                                for my $delRow (@dayRows) {
                                    if($day != 00 || $delRow->[0] !~ /$lastHour/) {
                                        Log3($name, 5, "DbLog $name: DELETE FROM $history WHERE (DEVICE=$delRow->[1]) AND (READING=$delRow->[3]) AND (TIMESTAMP=$delRow->[0]) AND (VALUE=$delRow->[4])");
                                        $sth_del->execute(($delRow->[1], $delRow->[3], $delRow->[0], $delRow->[4]));
                                        $i++;

                                        if($i == $th) {
                                            my $prog = $k * $i;
                                            Log3($name, 3, "DbLog $name: reduceLog deletion progress of day: $processingDay is: $prog");
                                            $i = 0;
                                            $k++;
                                        }
                                    }
                                }
                            };

                            if ($@) {
                                Log3($name, 3, "DbLog $name: reduceLog ! FAILED ! for day $processingDay");
                                
                                eval {$dbh->rollback() if(!$dbh->{AutoCommit});};
                                $ret = 0;
                            }
                            else {
                                eval {$dbh->commit() if(!$dbh->{AutoCommit});};
                            }
                            $dbh->{RaiseError} = 0;
                            $dbh->{PrintError} = 1;
                        }

                        @dayRows = ();
                    }

                    if ($ret && defined($a[3]) && $a[3] =~ /average/i) {
                        $dbh->{RaiseError} = 1;
                        $dbh->{PrintError} = 0;
                        eval {$dbh->begin_work() if($dbh->{AutoCommit});};
                        eval {
                            push(@averageUpd, {%hourlyKnown}) if($day != 00);

                            $c = 0;
                            for my $hourHash (@averageUpd) {                                     # Only count for logging...
                                for my $hourKey (keys %$hourHash) {
                                    $c++ if ($hourHash->{$hourKey}->[0] && scalar(@{$hourHash->{$hourKey}->[4]}) > 1);
                                }
                            }
                            $updateCount += $c;
                            Log3($name, 3, "DbLog $name: reduceLog (hourly-average) updating $c records of day: $processingDay") if($c); # else only push to @averageUpdD

                            my $i  = 0;
                            my $k  = 1;
                            my $th = ($c <= 2000)?100:($c <= 30000)?1000:10000;

                            for my $hourHash (@averageUpd) {
                                for my $hourKey (keys %$hourHash) {
                                    if ($hourHash->{$hourKey}->[0]) { # true if reading is a number
                                        ($updDate,$updHour) = $hourHash->{$hourKey}->[0] =~ /(.*\d+)\s(\d{2}):/;
                                        if (scalar(@{$hourHash->{$hourKey}->[4]}) > 1) {  # true if reading has multiple records this hour
                                            for (@{$hourHash->{$hourKey}->[4]}) { $sum += $_; }
                                            $average = sprintf('%.3f', $sum/scalar(@{$hourHash->{$hourKey}->[4]}) );
                                            $sum = 0;
                                            Log3($name, 5, "DbLog $name: UPDATE $history SET TIMESTAMP=$updDate $updHour:30:00, EVENT='rl_av_h', VALUE=$average WHERE DEVICE=$hourHash->{$hourKey}->[1] AND READING=$hourHash->{$hourKey}->[3] AND TIMESTAMP=$hourHash->{$hourKey}->[0] AND VALUE=$hourHash->{$hourKey}->[4]->[0]");
                                            $sth_upd->execute(("$updDate $updHour:30:00", 'rl_av_h', $average, $hourHash->{$hourKey}->[1], $hourHash->{$hourKey}->[3], $hourHash->{$hourKey}->[0], $hourHash->{$hourKey}->[4]->[0]));

                                            $i++;
                                            if($i == $th) {
                                                my $prog = $k * $i;
                                                Log3($name, 3, "DbLog $name: reduceLog (hourly-average) updating progress of day: $processingDay is: $prog");
                                                $i = 0;
                                                $k++;
                                            }
                                            push(@averageUpdD, ["$updDate $updHour:30:00", 'rl_av_h', $average, $hourHash->{$hourKey}->[1], $hourHash->{$hourKey}->[3], $updDate]) if (defined($a[3]) && $a[3] =~ /average=day/i);
                                        }
                                        else {
                                            push(@averageUpdD, [$hourHash->{$hourKey}->[0], $hourHash->{$hourKey}->[2], $hourHash->{$hourKey}->[4]->[0], $hourHash->{$hourKey}->[1], $hourHash->{$hourKey}->[3], $updDate]) if (defined($a[3]) && $a[3] =~ /average=day/i);
                                        }
                                    }
                                }
                            }
                        };
                        if ($@) {
                            $err = $@;
                            Log3($name, 2, "DbLog $name - reduceLogNbl ! FAILED ! for day $processingDay: $err");
                            eval {$dbh->rollback() if(!$dbh->{AutoCommit});};
                            @averageUpdD = ();
                        }
                        else {
                            eval {$dbh->commit() if(!$dbh->{AutoCommit});};
                        }

                        $dbh->{RaiseError} = 0;
                        $dbh->{PrintError} = 1;
                        @averageUpd        = ();
                    }

                    if (defined($a[3]) && $a[3] =~ /average=day/i && scalar(@averageUpdD) && $day != 00) {
                        $dbh->{RaiseError} = 1;
                        $dbh->{PrintError} = 0;
                        eval {$dbh->begin_work() if($dbh->{AutoCommit});};
                        eval {
                            for (@averageUpdD) {
                                push(@{$averageHash{$_->[3].$_->[4]}->{tedr}}, [$_->[0], $_->[1], $_->[3], $_->[4]]);
                                $averageHash{$_->[3].$_->[4]}->{sum} += $_->[2];
                                $averageHash{$_->[3].$_->[4]}->{date} = $_->[5];
                            }

                            $c = 0;
                            for (keys %averageHash) {
                                if(scalar @{$averageHash{$_}->{tedr}} == 1) {
                                    delete $averageHash{$_};
                                }
                                else {
                                    $c += (scalar(@{$averageHash{$_}->{tedr}}) - 1);
                                }
                            }
                            $deletedCount += $c;
                            $updateCount += keys(%averageHash);

                            my ($id,$iu) = (0,0);
                            my ($kd,$ku) = (1,1);
                            my $thd      = ($c <= 2000)?100:($c <= 30000) ? 1000 : 10000;
                            my $thu      = ((keys %averageHash) <= 2000)  ? 100  :
                                           ((keys %averageHash) <= 30000) ? 1000 :
                                           10000;

                            Log3($name, 3, "DbLog $name: reduceLog (daily-average) updating ".(keys %averageHash).", deleting $c records of day: $processingDay") if(keys %averageHash);

                            for my $reading (keys %averageHash) {
                                $average = sprintf('%.3f', $averageHash{$reading}->{sum}/scalar(@{$averageHash{$reading}->{tedr}}));
                                $lastUpdH = pop @{$averageHash{$reading}->{tedr}};

                                for (@{$averageHash{$reading}->{tedr}}) {
                                    Log3($name, 5, "DbLog $name: DELETE FROM $history WHERE DEVICE='$_->[2]' AND READING='$_->[3]' AND TIMESTAMP='$_->[0]'");
                                    $sth_delD->execute(($_->[2], $_->[3], $_->[0]));

                                    $id++;
                                    if($id == $thd) {
                                        my $prog = $kd * $id;
                                        Log3($name, 3, "DbLog $name: reduceLog (daily-average) deleting progress of day: $processingDay is: $prog");
                                        $id = 0;
                                        $kd++;
                                    }
                                }

                                Log3($name, 5, "DbLog $name: UPDATE $history SET TIMESTAMP=$averageHash{$reading}->{date} 12:00:00, EVENT='rl_av_d', VALUE=$average WHERE (DEVICE=$lastUpdH->[2]) AND (READING=$lastUpdH->[3]) AND (TIMESTAMP=$lastUpdH->[0])");

                                $sth_updD->execute(($averageHash{$reading}->{date}." 12:00:00", 'rl_av_d', $average, $lastUpdH->[2], $lastUpdH->[3], $lastUpdH->[0]));

                                $iu++;
                                if($iu == $thu) {
                                    my $prog = $ku * $id;
                                    Log3($name, 3, "DbLog $name: reduceLog (daily-average) updating progress of day: $processingDay is: $prog");
                                    $iu = 0;
                                    $ku++;
                                }
                            }
                        };
                        if ($@) {
                            $err = $@;
                            Log3 ($name, 2, "DbLog $name - reduceLogNbl ! FAILED ! for day $processingDay: $err");
                            eval {$dbh->rollback() if(!$dbh->{AutoCommit});};
                        }
                        else {
                            eval {$dbh->commit() if(!$dbh->{AutoCommit});};
                        }

                        $dbh->{RaiseError} = 0;
                        $dbh->{PrintError} = 1;
                    }

                    %averageHash = ();
                    %hourlyKnown = ();
                    @averageUpd  = ();
                    @averageUpdD = ();
                    $currentHour = 99;
                }
                $currentDay = $day;
            }

            if ($hour != $currentHour) { # forget records from last hour, but remember these for average
                if (defined($a[3]) && $a[3] =~ /average/i && keys(%hourlyKnown)) {
                    push(@averageUpd, {%hourlyKnown});
                }

                %hourlyKnown = ();
                $currentHour = $hour;
            }

            if (defined $hourlyKnown{$row->[1].$row->[3]}) { # remember first readings for device per h, other can be deleted
                push(@dayRows, [@$row]);
                if (defined($a[3]) && $a[3] =~ /average/i && defined($row->[4]) && $row->[4] =~ /^-?(?:\d+(?:\.\d*)?|\.\d+)$/ && $hourlyKnown{$row->[1].$row->[3]}->[0]) {
                    if ($hourlyKnown{$row->[1].$row->[3]}->[0]) {
                        push(@{$hourlyKnown{$row->[1].$row->[3]}->[4]}, $row->[4]);
                    }
                }
            }
            else {
                $exclude = 0;
                for (@excludeRegex) {
                    $exclude = 1 if("$row->[1]:$row->[3]" =~ /^$_$/);
                }

                if ($exclude) {
                    $excludeCount++ if($day != 00);
                }
                else {
                    $hourlyKnown{$row->[1].$row->[3]} = (defined($row->[4]) && $row->[4] =~ /^-?(?:\d+(?:\.\d*)?|\.\d+)$/) ? [$row->[0],$row->[1],$row->[2],$row->[3],[$row->[4]]] : [0];
                }
            }

            $processingDay = (split(' ',$row->[0]))[0];

        } while ($day != 00);

        my $result = "Rows processed: $rowCount, deleted: $deletedCount"
                   .((defined($a[3]) && $a[3] =~ /average/i)? ", updated: $updateCount" : '')
                   .(($excludeCount)? ", excluded: $excludeCount" : '')
                   .", time: ".sprintf('%.2f',time() - $startTime)."sec";

        Log3($name, 3, "DbLog $name: reduceLog executed. $result");

        readingsSingleUpdate($hash,"reduceLogState",$result,1);
        $ret = "reduceLog executed. $result";
    }
    $dbh->disconnect();
    return $ret;
}

#########################################################################################
### DBLog - Historische Werte ausduennen non-blocking > Forum #41089
#########################################################################################
sub DbLog_reduceLogNbl {
    my ($name)     = @_;
    my $hash       = $defs{$name};
    my $dbconn     = $hash->{dbconn};
    my $dbuser     = $hash->{dbuser};
    my $dbpassword = $attr{"sec$name"}{secret};
    my @a          = @{$hash->{HELPER}{REDUCELOG}};
    my $utf8       = defined($hash->{UTF8})?$hash->{UTF8}:0;
    my $history    = $hash->{HELPER}{TH};
    my $current    = $hash->{HELPER}{TC};

    delete $hash->{HELPER}{REDUCELOG};

    my ($ret,$row,$filter,$exclude,$c,$day,$hour,$lastHour,$updDate,$updHour,$average,$processingDay,$lastUpdH,%hourlyKnown,%averageHash,@excludeRegex,@dayRows,@averageUpd,@averageUpdD);
    my ($startTime,$currentHour,$currentDay,$deletedCount,$updateCount,$sum,$rowCount,$excludeCount) = (time(),99,0,0,0,0,0,0);
    my ($dbh,$err);

    Log3 ($name, 5, "DbLog $name -> Start DbLog_reduceLogNbl");

    my ($useac,$useta) = DbLog_commitMode ($name, AttrVal($name, 'commitMode', 'basic_ta:on'));
    
    if (!$useac) {
        eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1, AutoCommit => 0 });};
    }
    elsif ($useac == 1) {
        eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1, AutoCommit => 1 });};
    }
    else {
        # Server default
        eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
    }
    if ($@) {
        $err = encode_base64($@,"");
        Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
        Log3 ($name, 5, "DbLog $name -> DbLog_reduceLogNbl finished");
        return "$name|''|$err";
    }

    if ($a[-1] =~ /^EXCLUDE=(.+:.+)+/i) {
        ($filter) = $a[-1] =~ /^EXCLUDE=(.+)/i;
        @excludeRegex = split(',',$filter);
    }
    elsif ($a[-1] =~ /^INCLUDE=.+:.+$/i) {
        $filter = 1;
    }

    if (defined($a[3])) {
        $average = ($a[3] =~ /average=day/i) ? "AVERAGE=DAY" : ($a[3] =~ /average/i) ? "AVERAGE=HOUR" : 0;
    }

    Log3($name, 3, "DbLog $name: reduceLogNbl requested with DAYS=$a[2]"
        .(($average || $filter) ? ', ' : '').(($average) ? "$average" : '')
        .(($average && $filter) ? ", " : '').(($filter) ? uc((split('=',$a[-1]))[0]).'='.(split('=',$a[-1]))[1] : ''));

    my $ac = ($dbh->{AutoCommit}) ? "ON" : "OFF";
    my $tm = ($useta)             ? "ON" : "OFF";

    Log3 $name, 4, "DbLog $name -> AutoCommit mode: $ac, Transaction mode: $tm";

    my ($od,$nd) = split(":",$a[2]);                                             # $od - Tage älter als , $nd - Tage neuer als
    my ($ots,$nts);

    if ($hash->{MODEL} eq 'SQLITE') {
        $ots = "datetime('now', '-$od days')";
        $nts = "datetime('now', '-$nd days')" if($nd);
    }
    elsif ($hash->{MODEL} eq 'MYSQL') {
        $ots = "DATE_SUB(CURDATE(),INTERVAL $od DAY)";
        $nts = "DATE_SUB(CURDATE(),INTERVAL $nd DAY)" if($nd);
    }
    elsif ($hash->{MODEL} eq 'POSTGRESQL') {
        $ots = "NOW() - INTERVAL '$od' DAY";
        $nts = "NOW() - INTERVAL '$nd' DAY" if($nd);
    }
    else {
        $ret = 'Unknown database type.';
    }

    if ($ots) {
        my ($sth_del, $sth_upd, $sth_delD, $sth_updD, $sth_get);
        eval { $sth_del  = $dbh->prepare_cached("DELETE FROM $history WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?) AND (VALUE=?)");
               $sth_upd  = $dbh->prepare_cached("UPDATE $history SET TIMESTAMP=?, EVENT=?, VALUE=? WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?) AND (VALUE=?)");
               $sth_delD = $dbh->prepare_cached("DELETE FROM $history WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?)");
               $sth_updD = $dbh->prepare_cached("UPDATE $history SET TIMESTAMP=?, EVENT=?, VALUE=? WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?)");
               $sth_get  = $dbh->prepare("SELECT TIMESTAMP,DEVICE,'',READING,VALUE FROM $history WHERE "
                           .($a[-1] =~ /^INCLUDE=(.+):(.+)$/i ? "DEVICE like '$1' AND READING like '$2' AND " : '')
                           ."TIMESTAMP < $ots".($nts?" AND TIMESTAMP >= $nts ":" ")."ORDER BY TIMESTAMP ASC");  # '' was EVENT, no longer in use
             };
        if ($@) {
            $err = encode_base64($@,"");
            Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
            Log3 ($name, 5, "DbLog $name -> DbLog_reduceLogNbl finished");
            return "$name|''|$err";
        }

        eval { $sth_get->execute(); };
        if ($@) {
            $err = encode_base64($@,"");
            Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
            Log3 ($name, 5, "DbLog $name -> DbLog_reduceLogNbl finished");
            return "$name|''|$err";
        }

        do {
            $row = $sth_get->fetchrow_arrayref || ['0000-00-00 00:00:00','D','','R','V'];  # || execute last-day dummy
            $ret = 1;
            ($day,$hour) = $row->[0] =~ /-(\d{2})\s(\d{2}):/;
            $rowCount++ if($day != 00);

            if ($day != $currentDay) {
                if ($currentDay) { # false on first executed day
                    if (scalar @dayRows) {
                        ($lastHour) = $dayRows[-1]->[0] =~ /(.*\d+\s\d{2}):/;
                        $c = 0;

                        for my $delRow (@dayRows) {
                            $c++ if($day != 00 || $delRow->[0] !~ /$lastHour/);
                        }

                        if($c) {
                            $deletedCount += $c;

                            Log3($name, 3, "DbLog $name: reduceLogNbl deleting $c records of day: $processingDay");

                            $dbh->{RaiseError} = 1;
                            $dbh->{PrintError} = 0;
                            eval {$dbh->begin_work() if($dbh->{AutoCommit});};

                            if ($@) {
                                Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
                            }

                            eval {
                                my $i  = 0;
                                my $k  = 1;
                                my $th = ($#dayRows <= 2000)?100:($#dayRows <= 30000)?1000:10000;

                                for my $delRow (@dayRows) {
                                    if($day != 00 || $delRow->[0] !~ /$lastHour/) {
                                        Log3($name, 4, "DbLog $name: DELETE FROM $history WHERE (DEVICE=$delRow->[1]) AND (READING=$delRow->[3]) AND (TIMESTAMP=$delRow->[0]) AND (VALUE=$delRow->[4])");
                                        $sth_del->execute(($delRow->[1], $delRow->[3], $delRow->[0], $delRow->[4]));
                                        $i++;
                                        if($i == $th) {
                                            my $prog = $k * $i;
                                            Log3($name, 3, "DbLog $name: reduceLogNbl deletion progress of day: $processingDay is: $prog");
                                            $i = 0;
                                            $k++;
                                        }
                                    }
                                }
                            };
                            if ($@) {
                                $err = $@;
                                Log3 ($name, 2, "DbLog $name - reduceLogNbl ! FAILED ! for day $processingDay: $err");
                                eval {$dbh->rollback() if(!$dbh->{AutoCommit});};
                                if ($@) {
                                    Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
                                }
                                $ret = 0;
                            }
                            else {
                                eval {$dbh->commit() if(!$dbh->{AutoCommit});};
                                if ($@) {
                                    Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
                                }
                            }

                            $dbh->{RaiseError} = 0;
                            $dbh->{PrintError} = 1;
                        }

                        @dayRows = ();
                    }

                    if ($ret && defined($a[3]) && $a[3] =~ /average/i) {
                        $dbh->{RaiseError} = 1;
                        $dbh->{PrintError} = 0;
                        eval {$dbh->begin_work() if($dbh->{AutoCommit});};
                        if ($@) {
                            Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
                        }

                        eval {
                            push(@averageUpd, {%hourlyKnown}) if($day != 00);

                            $c = 0;
                            for my $hourHash (@averageUpd) {  # Only count for logging...
                                for my $hourKey (keys %$hourHash) {
                                    $c++ if ($hourHash->{$hourKey}->[0] && scalar(@{$hourHash->{$hourKey}->[4]}) > 1);
                                }
                            }

                            $updateCount += $c;
                            Log3($name, 3, "DbLog $name: reduceLogNbl (hourly-average) updating $c records of day: $processingDay") if($c); # else only push to @averageUpdD

                            my $i  = 0;
                            my $k  = 1;
                            my $th = ($c <= 2000)?100:($c <= 30000)?1000:10000;

                            for my $hourHash (@averageUpd) {
                                for my $hourKey (keys %$hourHash) {
                                    if ($hourHash->{$hourKey}->[0]) { # true if reading is a number
                                        ($updDate,$updHour) = $hourHash->{$hourKey}->[0] =~ /(.*\d+)\s(\d{2}):/;
                                        if (scalar(@{$hourHash->{$hourKey}->[4]}) > 1) {  # true if reading has multiple records this hour
                                            for (@{$hourHash->{$hourKey}->[4]}) { $sum += $_; }
                                            $average = sprintf('%.3f', $sum/scalar(@{$hourHash->{$hourKey}->[4]}) );
                                            $sum     = 0;

                                            Log3($name, 4, "DbLog $name: UPDATE $history SET TIMESTAMP=$updDate $updHour:30:00, EVENT='rl_av_h', VALUE=$average WHERE DEVICE=$hourHash->{$hourKey}->[1] AND READING=$hourHash->{$hourKey}->[3] AND TIMESTAMP=$hourHash->{$hourKey}->[0] AND VALUE=$hourHash->{$hourKey}->[4]->[0]");

                                            $sth_upd->execute(("$updDate $updHour:30:00", 'rl_av_h', $average, $hourHash->{$hourKey}->[1], $hourHash->{$hourKey}->[3], $hourHash->{$hourKey}->[0], $hourHash->{$hourKey}->[4]->[0]));

                                            $i++;
                                            if($i == $th) {
                                                my $prog = $k * $i;
                                                Log3($name, 3, "DbLog $name: reduceLogNbl (hourly-average) updating progress of day: $processingDay is: $prog");
                                                $i = 0;
                                                $k++;
                                            }
                                            push(@averageUpdD, ["$updDate $updHour:30:00", 'rl_av_h', $average, $hourHash->{$hourKey}->[1], $hourHash->{$hourKey}->[3], $updDate]) if (defined($a[3]) && $a[3] =~ /average=day/i);
                                        }
                                        else {
                                            push(@averageUpdD, [$hourHash->{$hourKey}->[0], $hourHash->{$hourKey}->[2], $hourHash->{$hourKey}->[4]->[0], $hourHash->{$hourKey}->[1], $hourHash->{$hourKey}->[3], $updDate]) if (defined($a[3]) && $a[3] =~ /average=day/i);
                                        }
                                    }
                                }
                            }
                        };

                        if ($@) {
                            $err = $@;
                            Log3 ($name, 2, "DbLog $name - reduceLogNbl average=hour ! FAILED ! for day $processingDay: $err");
                            eval {$dbh->rollback() if(!$dbh->{AutoCommit});};
                            if ($@) {
                                Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
                            }
                            @averageUpdD = ();
                        }
                        else {
                            eval {$dbh->commit() if(!$dbh->{AutoCommit});};
                            if ($@) {
                                Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
                            }
                        }

                        $dbh->{RaiseError} = 0;
                        $dbh->{PrintError} = 1;
                        @averageUpd = ();
                    }

                    if (defined($a[3]) && $a[3] =~ /average=day/i && scalar(@averageUpdD) && $day != 00) {
                        $dbh->{RaiseError} = 1;
                        $dbh->{PrintError} = 0;
                        eval {$dbh->begin_work() if($dbh->{AutoCommit});};
                        if ($@) {
                            Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
                        }

                        eval {
                            for (@averageUpdD) {
                                push(@{$averageHash{$_->[3].$_->[4]}->{tedr}}, [$_->[0], $_->[1], $_->[3], $_->[4]]);
                                $averageHash{$_->[3].$_->[4]}->{sum} += $_->[2];
                                $averageHash{$_->[3].$_->[4]}->{date} = $_->[5];
                            }

                            $c = 0;
                            for (keys %averageHash) {
                                if(scalar @{$averageHash{$_}->{tedr}} == 1) {
                                    delete $averageHash{$_};
                                }
                                else {
                                    $c += (scalar(@{$averageHash{$_}->{tedr}}) - 1);
                                }
                            }
                            $deletedCount += $c;
                            $updateCount += keys(%averageHash);

                            my ($id,$iu) = (0,0);
                            my ($kd,$ku) = (1,1);
                            my $thd      = ($c <= 2000)  ? 100  :
                                           ($c <= 30000) ? 1000 :
                                           10000;
                            my $thu      = ((keys %averageHash) <= 2000)  ? 100  :
                                           ((keys %averageHash) <= 30000) ? 1000 :
                                           10000;

                            Log3($name, 3, "DbLog $name: reduceLogNbl (daily-average) updating ".(keys %averageHash).", deleting $c records of day: $processingDay") if(keys %averageHash);

                            for my $reading (keys %averageHash) {
                                $average  = sprintf('%.3f', $averageHash{$reading}->{sum}/scalar(@{$averageHash{$reading}->{tedr}}));
                                $lastUpdH = pop @{$averageHash{$reading}->{tedr}};

                                for (@{$averageHash{$reading}->{tedr}}) {
                                    Log3($name, 5, "DbLog $name: DELETE FROM $history WHERE DEVICE='$_->[2]' AND READING='$_->[3]' AND TIMESTAMP='$_->[0]'");
                                    $sth_delD->execute(($_->[2], $_->[3], $_->[0]));

                                    $id++;
                                    if($id == $thd) {
                                        my $prog = $kd * $id;
                                        Log3($name, 3, "DbLog $name: reduceLogNbl (daily-average) deleting progress of day: $processingDay is: $prog");
                                        $id = 0;
                                        $kd++;
                                    }
                                }

                                Log3($name, 4, "DbLog $name: UPDATE $history SET TIMESTAMP=$averageHash{$reading}->{date} 12:00:00, EVENT='rl_av_d', VALUE=$average WHERE (DEVICE=$lastUpdH->[2]) AND (READING=$lastUpdH->[3]) AND (TIMESTAMP=$lastUpdH->[0])");

                                $sth_updD->execute(($averageHash{$reading}->{date}." 12:00:00", 'rl_av_d', $average, $lastUpdH->[2], $lastUpdH->[3], $lastUpdH->[0]));

                                $iu++;
                                if($iu == $thu) {
                                    my $prog = $ku * $id;
                                    Log3($name, 3, "DbLog $name: reduceLogNbl (daily-average) updating progress of day: $processingDay is: $prog");
                                    $iu = 0;
                                    $ku++;
                                }
                            }
                        };
                        if ($@) {
                            Log3 ($name, 3, "DbLog $name: reduceLogNbl average=day ! FAILED ! for day $processingDay");
                            eval {$dbh->rollback() if(!$dbh->{AutoCommit});};
                            if ($@) {
                                Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
                            }
                        }
                        else {
                            eval {$dbh->commit() if(!$dbh->{AutoCommit});};
                            if ($@) {
                                Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
                            }
                        }

                        $dbh->{RaiseError} = 0;
                        $dbh->{PrintError} = 1;
                    }

                    %averageHash = ();
                    %hourlyKnown = ();
                    @averageUpd  = ();
                    @averageUpdD = ();
                    $currentHour = 99;
                }

                $currentDay = $day;
            }

            if ($hour != $currentHour) { # forget records from last hour, but remember these for average
                if (defined($a[3]) && $a[3] =~ /average/i && keys(%hourlyKnown)) {
                    push(@averageUpd, {%hourlyKnown});
                }
                %hourlyKnown = ();
                $currentHour = $hour;
            }
            if (defined $hourlyKnown{$row->[1].$row->[3]}) { # remember first readings for device per h, other can be deleted
                push(@dayRows, [@$row]);
                if (defined($a[3]) && $a[3] =~ /average/i && defined($row->[4]) && $row->[4] =~ /^-?(?:\d+(?:\.\d*)?|\.\d+)$/ && $hourlyKnown{$row->[1].$row->[3]}->[0]) {
                    if ($hourlyKnown{$row->[1].$row->[3]}->[0]) {
                        push(@{$hourlyKnown{$row->[1].$row->[3]}->[4]}, $row->[4]);
                    }
                }
            }
            else {
                $exclude = 0;
                for (@excludeRegex) {
                    $exclude = 1 if("$row->[1]:$row->[3]" =~ /^$_$/);
                }

                if ($exclude) {
                    $excludeCount++ if($day != 00);
                }
                else {
                    $hourlyKnown{$row->[1].$row->[3]} = (defined($row->[4]) && $row->[4] =~ /^-?(?:\d+(?:\.\d*)?|\.\d+)$/) ? [$row->[0],$row->[1],$row->[2],$row->[3],[$row->[4]]] : [0];
                }
            }
            $processingDay = (split(' ',$row->[0]))[0];

        } while( $day != 00 );

        my $result = "Rows processed: $rowCount, deleted: $deletedCount"
                   .((defined($a[3]) && $a[3] =~ /average/i)? ", updated: $updateCount" : '')
                   .(($excludeCount)? ", excluded: $excludeCount" : '')
                   .", time: ".sprintf('%.2f',time() - $startTime)."sec";

        Log3($name, 3, "DbLog $name: reduceLogNbl finished. $result");

        $ret = $result;
        $ret = "reduceLogNbl finished. $result";
    }

    $dbh->disconnect();
    $ret = encode_base64($ret,"");
    Log3 ($name, 5, "DbLog $name -> DbLog_reduceLogNbl finished");

return "$name|$ret|0";
}

#########################################################################################
# DBLog - reduceLogNbl non-blocking Rückkehrfunktion
#########################################################################################
sub DbLog_reduceLogNbl_finished {
  my $string = shift;
  my @a      = split("\\|",$string);
  my $name   = $a[0];
  my $hash   = $defs{$name};
  my $ret    = decode_base64($a[1]);
  my $err;
  $err       = decode_base64($a[2]) if ($a[2]);

  readingsSingleUpdate($hash,"reduceLogState", $err // $ret, 1);

  delete $hash->{HELPER}{REDUCELOG_PID};

return;
}

#########################################################################################
# DBLog - count non-blocking
#########################################################################################
sub DbLog_countNbl {
  my ($name)  = @_;
  my $hash    = $defs{$name};
  my $history = $hash->{HELPER}{TH};
  my $current = $hash->{HELPER}{TC};
  my ($cc,$hc,$bst,$st,$rt);

  # Background-Startzeit
  $bst = [gettimeofday];

  my $dbh = _DbLog_ConnectNewDBH($hash);
  if (!$dbh) {
    my $err = encode_base64("DbLog $name: DBLog_Set - count - DB connect not possible","");
    return "$name|0|0|$err|0";
  }
  else {
    Log3 $name,4,"DbLog $name: Records count requested.";
    # SQL-Startzeit
    $st = [gettimeofday];
    $hc = $dbh->selectrow_array("SELECT count(*) FROM $history");
    $cc = $dbh->selectrow_array("SELECT count(*) FROM $current");
    $dbh->disconnect();
    # SQL-Laufzeit ermitteln
    $rt = tv_interval($st);
  }

  # Background-Laufzeit ermitteln
  my $brt = tv_interval($bst);
  $rt = $rt.",".$brt;
return "$name|$cc|$hc|0|$rt";
}

#########################################################################################
# DBLog - count non-blocking Rückkehrfunktion
#########################################################################################
sub DbLog_countNbl_finished {
  my $string = shift;
  my @a      = split("\\|",$string);
  my $name   = $a[0];
  my $hash   = $defs{$name};
  my $cc     = $a[1];
  my $hc     = $a[2];
  my ($err,$bt);
  $err       = decode_base64($a[3]) if($a[3]);
  $bt        = $a[4]                if($a[4]);

  DbLog_setReadingstate ($hash, $err) if($err);
  readingsSingleUpdate  ($hash,"countHistory",$hc,1) if ($hc);
  readingsSingleUpdate  ($hash,"countCurrent",$cc,1) if ($cc);

  if(AttrVal($name, "showproctime", undef) && $bt) {
      my ($rt,$brt)  = split(",", $bt);
      readingsBeginUpdate ($hash);
      readingsBulkUpdate  ($hash, "background_processing_time", sprintf("%.4f",$brt));
      readingsBulkUpdate  ($hash, "sql_processing_time",        sprintf("%.4f",$rt) );
      readingsEndUpdate   ($hash, 1);
  }

  delete $hash->{HELPER}{COUNT_PID};

return;
}

#########################################################################################
# DBLog - deleteOldDays non-blocking
#########################################################################################
sub DbLog_deldaysNbl {
  my ($name)     = @_;
  my $hash       = $defs{$name};
  my $dbconn     = $hash->{dbconn};
  my $dbuser     = $hash->{dbuser};
  my $dbpassword = $attr{"sec$name"}{secret};
  my $days       = delete($hash->{HELPER}{DELDAYS});
  my $history    = $hash->{HELPER}{TH};
  my $current    = $hash->{HELPER}{TC};
  my ($cmd,$dbh,$rows,$error,$sth,$ret,$bst,$brt,$st,$rt);

  Log3 ($name, 5, "DbLog $name -> Start DbLog_deldaysNbl $days");

  # Background-Startzeit
  $bst = [gettimeofday];

  my ($useac,$useta) = DbLog_commitMode ($name, AttrVal($name, 'commitMode', 'basic_ta:on'));
  
  if(!$useac) {
      eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 0, AutoInactiveDestroy => 1 });};
  }
  elsif($useac == 1) {
      eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 1, AutoInactiveDestroy => 1 });};
  }
  else {
      # Server default
      eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
  }
  if ($@) {
      $error = encode_base64($@,"");
      Log3 ($name, 2, "DbLog $name - Error: $@");
      Log3 ($name, 5, "DbLog $name -> DbLog_deldaysNbl finished");
      return "$name|0|0|$error";
  }

  my $ac = ($dbh->{AutoCommit})?"ON":"OFF";
  my $tm = ($useta)?"ON":"OFF";
  Log3 $name, 4, "DbLog $name -> AutoCommit mode: $ac, Transaction mode: $tm";

  $cmd = "delete from $history where TIMESTAMP < ";
  if ($hash->{MODEL} eq 'SQLITE') {
      $cmd .= "datetime('now', '-$days days')";
  }
  elsif ($hash->{MODEL} eq 'MYSQL') {
      $cmd .= "DATE_SUB(CURDATE(),INTERVAL $days DAY)";
  }
  elsif ($hash->{MODEL} eq 'POSTGRESQL') {
      $cmd .= "NOW() - INTERVAL '$days' DAY";
  }
  else {
      $ret = 'Unknown database type. Maybe you can try userCommand anyway.';
      $error = encode_base64($ret,"");
      Log3 ($name, 2, "DbLog $name - Error: $ret");
      Log3 ($name, 5, "DbLog $name -> DbLog_deldaysNbl finished");
      return "$name|0|0|$error";
  }

  # SQL-Startzeit
  $st = [gettimeofday];

  eval {
      $sth = $dbh->prepare($cmd);
      $sth->execute();
  };

  if ($@) {
      $error = encode_base64($@,"");
      Log3 ($name, 2, "DbLog $name - $@");
      $dbh->disconnect;
      Log3 ($name, 4, "DbLog $name -> BlockingCall DbLog_deldaysNbl finished");
      return "$name|0|0|$error";
 }
 else {
     $rows = $sth->rows;
     $dbh->commit() if(!$dbh->{AutoCommit});
     $dbh->disconnect;
 }

 $rt = tv_interval($st);                                # SQL-Laufzeit ermitteln

 $brt = tv_interval($bst);                              # Background-Laufzeit ermitteln
 $rt = $rt.",".$brt;

  Log3 ($name, 5, "DbLog $name -> DbLog_deldaysNbl finished");
return "$name|$rows|$rt|0";
}

#########################################################################################
# DBLog - deleteOldDays non-blocking Rückkehrfunktion
#########################################################################################
sub DbLog_deldaysNbl_done {
  my $string = shift;
  my @a      = split("\\|",$string);
  my $name   = $a[0];
  my $hash   = $defs{$name};
  my $rows   = $a[1];
  my($bt,$err);
  $bt        = $a[2]                if ($a[2]);
  $err       = decode_base64($a[3]) if ($a[3]);

  Log3 ($name, 5, "DbLog $name -> Start DbLog_deldaysNbl_done");

  if ($err) {
      DbLog_setReadingstate ($hash, $err);
      delete $hash->{HELPER}{DELDAYS_PID};
      Log3 ($name, 5, "DbLog $name -> DbLog_deldaysNbl_done finished");
      return;
  }
  else {
      if(AttrVal($name, "showproctime", undef) && $bt) {
          my ($rt,$brt)  = split(",", $bt);
          readingsBeginUpdate($hash);
          readingsBulkUpdate ($hash, "background_processing_time", sprintf("%.4f",$brt));
          readingsBulkUpdate ($hash, "sql_processing_time", sprintf("%.4f",$rt));
          readingsEndUpdate  ($hash, 1);
      }
      readingsSingleUpdate($hash, "lastRowsDeleted", $rows ,1);
  }
  my $db = (split(/;|=/, $hash->{dbconn}))[1];
  Log3 ($name, 3, "DbLog $name -> deleteOldDaysNbl finished. $rows entries of database $db deleted.");
  delete $hash->{HELPER}{DELDAYS_PID};
  Log3 ($name, 5, "DbLog $name -> DbLog_deldaysNbl_done finished");

return;
}

################################################################
# benutzte DB-Feldlängen in Helper und Internals setzen
################################################################
sub DbLog_setinternalcols {
  my $hash = shift;
  my $name = $hash->{NAME};

  $hash->{HELPER}{DEVICECOL}   = $DbLog_columns{DEVICE};
  $hash->{HELPER}{TYPECOL}     = $DbLog_columns{TYPE};
  $hash->{HELPER}{EVENTCOL}    = AttrVal($name, "colEvent",   $DbLog_columns{EVENT}  );
  $hash->{HELPER}{READINGCOL}  = AttrVal($name, "colReading", $DbLog_columns{READING});
  $hash->{HELPER}{VALUECOL}    = AttrVal($name, "colValue",   $DbLog_columns{VALUE}  );
  $hash->{HELPER}{UNITCOL}     = $DbLog_columns{UNIT};

  $hash->{COLUMNS} = "field length used for Device: $hash->{HELPER}{DEVICECOL}, Type: $hash->{HELPER}{TYPECOL}, Event: $hash->{HELPER}{EVENTCOL}, Reading: $hash->{HELPER}{READINGCOL}, Value: $hash->{HELPER}{VALUECOL}, Unit: $hash->{HELPER}{UNITCOL} ";

  # Statusbit "Columns sind gesetzt"
  $hash->{HELPER}{COLSET} = 1;

return;
}

################################################################
# reopen DB-Connection nach Ablauf set ... reopen [n] seconds
################################################################
sub DbLog_reopen {
  my $hash  = shift;
  my $name  = $hash->{NAME};
  my $async = AttrVal($name, "asyncMode", undef);

  RemoveInternalTimer($hash, "DbLog_reopen");

  if (_DbLog_ConnectPush($hash)) {
      my $delay = delete $hash->{HELPER}{REOPEN_RUNS};                           # Statusbit "Kein Schreiben in DB erlauben" löschen
      delete $hash->{HELPER}{REOPEN_RUNS_UNTIL};
      
      Log3 ($name, 2, "DbLog $name: Database connection reopened (it was $delay seconds closed).") if($delay);

      DbLog_setReadingstate ($hash, "reopened");
      DbLog_execmemcache    ($hash) if($async);
  }
  else {
      InternalTimer(gettimeofday()+30, "DbLog_reopen", $hash, 0);
  }

return;
}

################################################################
# check ob primary key genutzt wird
################################################################
sub DbLog_checkUsePK {
  my $paref   = shift;
  
  my $name    = $paref->{name};
  my $dbh     = $paref->{dbh};
  my $dbconn  = $paref->{dbconn};
  my $history = $paref->{history};
  my $current = $paref->{current};
  
  my $upkh    = 0;
  my $upkc    = 0;
  
  my (@pkh,@pkc);

  my $db = (split("=",(split(";",$dbconn))[0]))[1];
  
  eval {@pkh = $dbh->primary_key( undef, undef, 'history' );};
  eval {@pkc = $dbh->primary_key( undef, undef, 'current' );};
  
  my $pkh = (!@pkh || @pkh eq "") ? "none" : join(",",@pkh);
  my $pkc = (!@pkc || @pkc eq "") ? "none" : join(",",@pkc);
  $pkh    =~ tr/"//d;
  $pkc    =~ tr/"//d;
  $upkh   = 1 if(@pkh && @pkh ne "none");
  $upkc   = 1 if(@pkc && @pkc ne "none");
  
  Log3 ($name, 4, "DbLog $name -> Primary Key used in $history: $pkh");
  Log3 ($name, 4, "DbLog $name -> Primary Key used in $current: $pkc");

return ($upkh,$upkc,$pkh,$pkc);
}

################################################################
#  Routine für FHEMWEB Detailanzeige
################################################################
sub DbLog_fhemwebFn {
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.

  my $ret;
  my $newIdx=1;
  while($defs{"SVG_${d}_$newIdx"}) {
      $newIdx++;
  }
  my $name = "SVG_${d}_$newIdx";
  $ret .= FW_pH("cmd=define $name SVG $d:templateDB:HISTORY;".
                 "set $name copyGplotFile&detail=$name",
                 "<div class=\"dval\">Create SVG plot from DbLog</div>", 0, "dval", 1);
return $ret;
}

################################################################
#  Dropdown-Menü current-Tabelle SVG-Editor
################################################################
sub DbLog_sampleDataFn {
  my ($dlName, $dlog, $max, $conf, $wName) = @_;
  my $desc    = "Device:Reading";
  my $hash    = $defs{$dlName};
  my $current = $hash->{HELPER}{TC};

  my @htmlArr;
  my @example;
  my @colregs;
  my $counter;

  my $currentPresent = AttrVal($dlName,'DbLogType','History');

  my $dbhf = _DbLog_ConnectNewDBH($defs{$dlName});
  return if(!$dbhf);

  # check presence of table current
  # avoids fhem from crash if table 'current' is not present and attr DbLogType is set to /Current/
  my $prescurr = eval {$dbhf->selectrow_array("select count(*) from $current");} || 0;
  Log3($dlName, 5, "DbLog $dlName: Table $current present : $prescurr (0 = not present or no content)");

  if($currentPresent =~ m/Current|SampleFill/ && $prescurr) {
    # Table Current present, use it for sample data
    my $query = "select device,reading from $current where device <> '' group by device,reading";
    my $sth = $dbhf->prepare( $query );
    $sth->execute();
    while (my @line = $sth->fetchrow_array()) {
      $counter++;
      push (@example, join (" ",@line)) if($counter <= 8);   # show max 8 examples
      push (@colregs, "$line[0]:$line[1]");                  # push all eventTypes to selection list
    }
    $dbhf->disconnect();
    my $cols = join(",", sort { "\L$a" cmp "\L$b" } @colregs);

    # $max = 8 if($max > 8);                                 # auskommentiert 27.02.2018, Notwendigkeit unklar (forum:#76008)
    for(my $r=0; $r < $max; $r++) {
      my @f = split(":", ($dlog->[$r] ? $dlog->[$r] : ":::"), 4);
      my $ret = "";
      $ret .= SVG_sel("par_${r}_0", $cols, "$f[0]:$f[1]");
#      $ret .= SVG_txt("par_${r}_2", "", $f[2], 1); # Default not yet implemented
#      $ret .= SVG_txt("par_${r}_3", "", $f[3], 3); # Function
#      $ret .= SVG_txt("par_${r}_4", "", $f[4], 3); # RegExp
      push @htmlArr, $ret;
    }

  }
  else {
  # Table Current not present, so create an empty input field
    push @example, "No sample data due to missing table '$current'";

    # $max = 8 if($max > 8);                                 # auskommentiert 27.02.2018, Notwendigkeit unklar (forum:#76008)
    for(my $r=0; $r < $max; $r++) {
      my @f = split(":", ($dlog->[$r] ? $dlog->[$r] : ":::"), 4);
      my $ret = "";
      no warnings 'uninitialized';                           # Forum:74690, bug unitialized
      $ret .= SVG_txt("par_${r}_0", "", "$f[0]:$f[1]:$f[2]:$f[3]", 20);
      use warnings;
#      $ret .= SVG_txt("par_${r}_2", "", $f[2], 1); # Default not yet implemented
#      $ret .= SVG_txt("par_${r}_3", "", $f[3], 3); # Function
#      $ret .= SVG_txt("par_${r}_4", "", $f[4], 3); # RegExp
      push @htmlArr, $ret;
    }

  }

return ($desc, \@htmlArr, join("<br>", @example));
}

################################################################
#           Error handling, returns a JSON String
################################################################
sub DbLog_jsonError {
  my $errormsg = $_[0];
  my $json = '{"success": "false", "msg":"'.$errormsg.'"}';

return $json;
}

################################################################
#              Check Zeitformat
#              Zeitformat: YYYY-MM-DD HH:MI:SS
################################################################
sub DbLog_checkTimeformat {
  my ($t) = @_;

  my (@datetime, @date, @time);
  @datetime = split(" ", $t);                                   # Datum und Zeit auftrennen
  @date     = split("-", $datetime[0]);
  @time     = split(":", $datetime[1]);

  eval { timelocal($time[2], $time[1], $time[0], $date[2], $date[1]-1, $date[0]-1900); };

  if ($@) {
      my $err = (split(" at ", $@))[0];
      return $err;
  }

return;
}

################################################################
#                Prepare the SQL String
################################################################
sub DbLog_prepareSql {
    my ($hash, @a) = @_;
    my $starttime       = $_[5];
    $starttime          =~ s/_/ /;
    my $endtime         = $_[6];
    $endtime            =~ s/_/ /;
    my $device          = $_[7];
    my $userquery       = $_[8];
    my $xaxis           = $_[9];
    my $yaxis           = $_[10];
    my $savename        = $_[11];
    my $jsonChartConfig = $_[12];
    my $pagingstart     = $_[13];
    my $paginglimit     = $_[14];
    my $dbmodel         = $hash->{MODEL};
    my $history         = $hash->{HELPER}{TH};
    my $current         = $hash->{HELPER}{TC};
    my ($sql, $jsonstring, $countsql, $hourstats, $daystats, $weekstats, $monthstats, $yearstats);

    if ($dbmodel eq "POSTGRESQL") {
        ### POSTGRESQL Queries for Statistics ###
        ### hour:
        $hourstats = "SELECT to_char(timestamp, 'YYYY-MM-DD HH24:00:00') AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
        $hourstats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
        $hourstats .= "COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $hourstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### day:
        $daystats = "SELECT to_char(timestamp, 'YYYY-MM-DD 00:00:00') AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
        $daystats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
        $daystats .= "COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $daystats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### week:
        $weekstats = "SELECT date_trunc('week',timestamp) AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
        $weekstats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
        $weekstats .= "COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $weekstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### month:
        $monthstats = "SELECT to_char(timestamp, 'YYYY-MM-01 00:00:00') AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
        $monthstats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
        $monthstats .= "COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $monthstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### year:
        $yearstats = "SELECT to_char(timestamp, 'YYYY-01-01 00:00:00') AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
        $yearstats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
        $yearstats .= "COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $yearstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

    } elsif ($dbmodel eq "MYSQL") {
        ### MYSQL Queries for Statistics ###
        ### hour:
        $hourstats = "SELECT date_format(timestamp, '%Y-%m-%d %H:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
        $hourstats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
        $hourstats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$yaxis' ";
        $hourstats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### day:
        $daystats = "SELECT date_format(timestamp, '%Y-%m-%d 00:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
        $daystats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
        $daystats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$yaxis' ";
        $daystats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### week:
        $weekstats = "SELECT date_format(timestamp, '%Y-%m-%d 00:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
        $weekstats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
        $weekstats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$yaxis' ";
        $weekstats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' ";
        $weekstats .= "GROUP BY date_format(timestamp, '%Y-%u 00:00:00') ORDER BY 1;";

        ### month:
        $monthstats = "SELECT date_format(timestamp, '%Y-%m-01 00:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
        $monthstats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
        $monthstats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$yaxis' ";
        $monthstats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### year:
        $yearstats = "SELECT date_format(timestamp, '%Y-01-01 00:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
        $yearstats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
        $yearstats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$yaxis' ";
        $yearstats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

    } elsif ($dbmodel eq "SQLITE") {
        ### SQLITE Queries for Statistics ###
        ### hour:
        $hourstats = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
        $hourstats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
        $hourstats .= "FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $hourstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y-%m-%d %H:00:00', TIMESTAMP);";

        ### day:
        $daystats = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
        $daystats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
        $daystats .= "FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $daystats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y-%m-%d 00:00:00', TIMESTAMP);";

        ### week:
        $weekstats = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
        $weekstats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
        $weekstats .= "FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $weekstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y-%W 00:00:00', TIMESTAMP);";

        ### month:
        $monthstats = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
        $monthstats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
        $monthstats .= "FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $monthstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y-%m 00:00:00', TIMESTAMP);";

        ### year:
        $yearstats = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
        $yearstats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
        $yearstats .= "FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $yearstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y 00:00:00', TIMESTAMP);";

    }
    else {
        $sql = "errordb";
    }

    if($userquery eq "getreadings") {
        $sql = "SELECT distinct(reading) FROM $history WHERE device = '".$device."'";
    }
    elsif($userquery eq "getdevices") {
        $sql = "SELECT distinct(device) FROM $history";
    }
    elsif($userquery eq "timerange") {
        $sql = "SELECT ".$xaxis.", VALUE FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' ORDER BY TIMESTAMP;";
    }
    elsif($userquery eq "hourstats") {
        $sql = $hourstats;
    }
    elsif($userquery eq "daystats") {
        $sql = $daystats;
    }
    elsif($userquery eq "weekstats") {
        $sql = $weekstats;
    }
    elsif($userquery eq "monthstats") {
        $sql = $monthstats;
    }
    elsif($userquery eq "yearstats") {
        $sql = $yearstats;
    }
    elsif($userquery eq "savechart") {
        $sql = "INSERT INTO frontend (TYPE, NAME, VALUE) VALUES ('savedchart', '$savename', '$jsonChartConfig')";
    }
    elsif($userquery eq "renamechart") {
        $sql = "UPDATE frontend SET NAME = '$savename' WHERE ID = '$jsonChartConfig'";
    }
    elsif($userquery eq "deletechart") {
        $sql = "DELETE FROM frontend WHERE TYPE = 'savedchart' AND ID = '".$savename."'";
    }
    elsif($userquery eq "updatechart") {
        $sql = "UPDATE frontend SET VALUE = '$jsonChartConfig' WHERE ID = '".$savename."'";
    }
    elsif($userquery eq "getcharts") {
        $sql = "SELECT * FROM frontend WHERE TYPE = 'savedchart'";
    }
    elsif($userquery eq "getTableData") {
        if ($device ne '""' && $yaxis ne '""') {
            $sql = "SELECT * FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
            $sql .= "AND TIMESTAMP Between '$starttime' AND '$endtime'";
            $sql .= " LIMIT '$paginglimit' OFFSET '$pagingstart'";
            $countsql = "SELECT count(*) FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
            $countsql .= "AND TIMESTAMP Between '$starttime' AND '$endtime'";
        }
        elsif($device ne '""' && $yaxis eq '""') {
            $sql = "SELECT * FROM $history WHERE DEVICE = '$device' ";
            $sql .= "AND TIMESTAMP Between '$starttime' AND '$endtime'";
            $sql .= " LIMIT '$paginglimit' OFFSET '$pagingstart'";
            $countsql = "SELECT count(*) FROM $history WHERE DEVICE = '$device' ";
            $countsql .= "AND TIMESTAMP Between '$starttime' AND '$endtime'";
        }
        else {
            $sql = "SELECT * FROM $history";
            $sql .= " WHERE TIMESTAMP Between '$starttime' AND '$endtime'";
            $sql .= " LIMIT '$paginglimit' OFFSET '$pagingstart'";
            $countsql = "SELECT count(*) FROM $history";
            $countsql .= " WHERE TIMESTAMP Between '$starttime' AND '$endtime'";
        }
        return ($sql, $countsql);
    }
    else {
        $sql = "error";
    }

return $sql;
}

################################################################
#
# Do the query
#
################################################################
sub DbLog_chartQuery {

    my ($sql, $countsql) = DbLog_prepareSql(@_);

    if ($sql eq "error") {
       return DbLog_jsonError("Could not setup SQL String. Maybe the Database is busy, please try again!");
    } elsif ($sql eq "errordb") {
       return DbLog_jsonError("The Database Type is not supported!");
    }

    my ($hash, @a) = @_;
    my $dbhf = _DbLog_ConnectNewDBH($hash);
    return if(!$dbhf);

    my $totalcount;

    if (defined $countsql && $countsql ne "") {
        my $query_handle = $dbhf->prepare($countsql)
        or return DbLog_jsonError("Could not prepare statement: " . $dbhf->errstr . ", SQL was: " .$countsql);

        $query_handle->execute()
        or return DbLog_jsonError("Could not execute statement: " . $query_handle->errstr);

        my @data = $query_handle->fetchrow_array();
        $totalcount = join(", ", @data);

    }

    # prepare the query
    my $query_handle = $dbhf->prepare($sql)
        or return DbLog_jsonError("Could not prepare statement: " . $dbhf->errstr . ", SQL was: " .$sql);

    # execute the query
    $query_handle->execute()
        or return DbLog_jsonError("Could not execute statement: " . $query_handle->errstr);

    my $columns = $query_handle->{'NAME'};
    my $columncnt;

    # When columns are empty but execution was successful, we have done a successful INSERT, UPDATE or DELETE
    if($columns) {
        $columncnt = scalar @$columns;
    }
    else {
        return '{"success": "true", "msg":"All ok"}';
    }

    my $i = 0;
    my $jsonstring = '{"data":[';

    while ( my @data = $query_handle->fetchrow_array()) {

        if($i == 0) {
            $jsonstring .= '{';
        }
        else {
            $jsonstring .= ',{';
        }

        for ($i = 0; $i < $columncnt; $i++) {
            $jsonstring .= '"';
            $jsonstring .= uc($query_handle->{NAME}->[$i]);
            $jsonstring .= '":';

            if (defined $data[$i]) {
                my $fragment =  substr($data[$i],0,1);
                if ($fragment eq "{") {
                    $jsonstring .= $data[$i];
                }
                else {
                    $jsonstring .= '"'.$data[$i].'"';
                }
            }
            else {
                $jsonstring .= '""'
            }

            if($i != ($columncnt -1)) {
               $jsonstring .= ',';
            }
        }
        $jsonstring .= '}';
    }
    $dbhf->disconnect();
    $jsonstring .= ']';
    if (defined $totalcount && $totalcount ne "") {
        $jsonstring .= ',"totalCount": '.$totalcount.'}';
    }
    else {
        $jsonstring .= '}';
    }

return $jsonstring;
}

################################################################
# get <dbLog> ReadingsVal       <device> <reading> <default>
# get <dbLog> ReadingsTimestamp <device> <reading> <default>
################################################################
sub DbLog_dbReadings {
  my($hash,@a) = @_;
  my $history  = $hash->{HELPER}{TH};
  my $current  = $hash->{HELPER}{TC};

  my $dbhf = _DbLog_ConnectNewDBH($hash);
  return if(!$dbhf);

  return 'Wrong Syntax for ReadingsVal!' unless defined($a[4]);
  my $DbLogType = AttrVal($a[0],'DbLogType','current');
  my $query;
  if (lc($DbLogType) =~ m(current) ) {
    $query = "select VALUE,TIMESTAMP from $current where DEVICE= '$a[2]' and READING= '$a[3]'";
  }
  else {
    $query = "select VALUE,TIMESTAMP from $history where DEVICE= '$a[2]' and READING= '$a[3]' order by TIMESTAMP desc limit 1";
  }
  my ($reading,$timestamp) = $dbhf->selectrow_array($query);
  $dbhf->disconnect();

  $reading   = (defined($reading)) ? $reading : $a[4];
  $timestamp = (defined($timestamp)) ? $timestamp : $a[4];

  return $reading   if $a[1] eq 'ReadingsVal';
  return $timestamp if $a[1] eq 'ReadingsTimestamp';
  return "Syntax error: $a[1]";
}

################################################################
#               Versionierungen des Moduls setzen
#  Die Verwendung von Meta.pm und Packages wird berücksichtigt
################################################################
sub DbLog_setVersionInfo {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my $v                    = (sortTopicNum("desc",keys %DbLog_vNotesIntern))[0];
  my $type                 = $hash->{TYPE};
  $hash->{HELPER}{PACKAGE} = __PACKAGE__;
  $hash->{HELPER}{VERSION} = $v;

  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {       # META-Daten sind vorhanden
      $modules{$type}{META}{version} = "v".$v;                                        # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{DbLog}{META}}
      if($modules{$type}{META}{x_version}) {                                          # {x_version} ( nur gesetzt wenn $Id: 93_DbLog.pm 26750 2022-11-26 16:38:54Z DS_Starter $ im Kopf komplett! vorhanden )
          $modules{$type}{META}{x_version} =~ s/1\.1\.1/$v/xsg;
      }
      else {
          $modules{$type}{META}{x_version} = $v;
      }
      return $@ unless (FHEM::Meta::SetInternals($hash));                             # FVERSION wird gesetzt ( nur gesetzt wenn $Id: 93_DbLog.pm 26750 2022-11-26 16:38:54Z DS_Starter $ im Kopf komplett! vorhanden )
      if(__PACKAGE__ eq "FHEM::$type" || __PACKAGE__ eq $type) {
          # es wird mit Packages gearbeitet -> Perl übliche Modulversion setzen
          # mit {<Modul>->VERSION()} im FHEMWEB kann Modulversion abgefragt werden
          use version 0.77; our $VERSION = FHEM::Meta::Get( $hash, 'version' );
      }
  }
  else {
      # herkömmliche Modulstruktur
      $hash->{VERSION} = $v;
  }

return;
}

#########################################################################
#               Trace of Childhandles
# dbh    Database handle object
# sth    Statement handle object
# drh    Driver handle object (rarely seen or used in applications)
# h      Any of the handle types above ($dbh, $sth, or $drh)
#########################################################################
sub DbLog_startShowChildhandles {
    my ($str)       = @_;
    my ($name,$sub) = split(":",$str);
    my $hash        = $defs{$name};

    RemoveInternalTimer($hash, "DbLog_startShowChildhandles");
    my $iv = AttrVal($name, "traceHandles", 0);
    return if(!$iv);

    my %drivers = DBI->installed_drivers();
    DbLog_showChildHandles($name,$drivers{$_}, 0, $_) for (keys %drivers);

    InternalTimer(gettimeofday()+$iv, "DbLog_startShowChildhandles", "$name:$sub", 0) if($iv);
return;
}

sub DbLog_showChildHandles {
    my ($name,$h, $level, $key) = @_;

    my $t = $h->{Type}."h";
    $t = ($t=~/drh/)?"DriverHandle   ":($t=~/dbh/)?"DatabaseHandle ":($t=~/sth/)?"StatementHandle":"Undefined";
    Log3($name, 1, "DbLog $name - traceHandles (system wide) - Driver: ".$key.", ".$t.": ".("\t" x $level).$h);
    DbLog_showChildHandles($name, $_, $level + 1, $key)
        for (grep { defined } @{$h->{ChildHandles}});
}

1;

=pod
=item helper
=item summary    logs events into a database
=item summary_DE loggt Events in eine Datenbank
=begin html

<a id="DbLog"></a>
<h3>DbLog</h3>
<br>

<ul>
  With DbLog events can be stored in a database. SQLite, MySQL/MariaDB and PostgreSQL are supported databases. <br><br>

  <b>Prereqisites</b> <br><br>

    The Perl-modules <code>DBI</code> and <code>DBD::&lt;dbtype&gt;</code> are needed to be installed (use <code>cpan -i &lt;module&gt;</code>
    if your distribution does not have it).
    <br><br>

    On a debian based system you may install these modules for instance by: <br><br>

    <ul>
    <table>
    <colgroup> <col width=5%> <col width=95%> </colgroup>
      <tr><td> <b>DBI</b>         </td><td>: <code> sudo apt-get install libdbi-perl </code> </td></tr>
      <tr><td> <b>MySQL</b>       </td><td>: <code> sudo apt-get install [mysql-server] mysql-client libdbd-mysql libdbd-mysql-perl </code> (mysql-server only if you use a local MySQL-server installation) </td></tr>
      <tr><td> <b>SQLite</b>      </td><td>: <code> sudo apt-get install sqlite3 libdbi-perl libdbd-sqlite3-perl </code> </td></tr>
      <tr><td> <b>PostgreSQL</b>  </td><td>: <code> sudo apt-get install libdbd-pg-perl </code> </td></tr>
    </table>
    </ul>
    <br>
    <br>

  <b>Preparations</b> <br><br>

  At first you need to install and setup the database.
  The installation of database system itself is not described here, please refer to the installation instructions of your
  database. <br><br>

  <b>Note:</b> <br>
  In case of fresh installed MySQL/MariaDB system don't forget deleting the anonymous "Everyone"-User with an admin-tool if
  existing !
  <br><br>

  Sample code and Scripts to prepare a MySQL/PostgreSQL/SQLite database you can find in
  <a href="https://svn.fhem.de/trac/browser/trunk/fhem/contrib/dblog">SVN -&gt; contrib/dblog/db_create_&lt;DBType&gt;.sql</a>. <br>
  (<b>Caution:</b> The local FHEM-Installation subdirectory ./contrib/dblog doesn't contain the freshest scripts !!)
  <br><br>

  The database contains two tables: <code>current</code> and <code>history</code>. <br>
  The latter contains all events whereas the former only contains the last event for any given reading and device.
  Please consider the <a href="#DbLog-attr-DbLogType">DbLogType</a> implicitly to determine the usage of tables
  <code>current</code> and <code>history</code>.
  <br><br>

  The columns have the following meaning: <br><br>

    <ul>
    <table>
    <colgroup> <col width=5%> <col width=95%> </colgroup>
      <tr><td> TIMESTAMP </td><td>: timestamp of event, e.g. <code>2007-12-30 21:45:22</code> </td></tr>
      <tr><td> DEVICE    </td><td>: device name, e.g. <code>Wetterstation</code> </td></tr>
      <tr><td> TYPE      </td><td>: device type, e.g. <code>KS300</code> </td></tr>
      <tr><td> EVENT     </td><td>: event specification as full string, e.g. <code>humidity: 71 (%)</code> </td></tr>
      <tr><td> READING   </td><td>: name of reading extracted from event, e.g. <code>humidity</code> </td></tr>
      <tr><td> VALUE     </td><td>: actual reading extracted from event, e.g. <code>71</code> </td></tr>
      <tr><td> UNIT      </td><td>: unit extracted from event, e.g. <code>%</code> </td></tr>
    </table>
    </ul>
    <br>
    <br>

  <b>create index</b> <br>
  Due to reading performance, e.g. on creation of SVG-plots, it is very important that the <b>index "Search_Idx"</b>
  or a comparable index (e.g. a primary key) is applied.
  A sample code for creation of that index is also available in mentioned scripts of
  <a href="https://svn.fhem.de/trac/browser/trunk/fhem/contrib/dblog">SVN -&gt; contrib/dblog/db_create_&lt;DBType&gt;.sql</a>.
  <br><br>

  The index "Search_Idx" can be created, e.g. in database 'fhem', by these statements (also subsequently): <br><br>

    <ul>
    <table>
    <colgroup> <col width=5%> <col width=95%> </colgroup>
      <tr><td> <b>MySQL</b>       </td><td>: <code> CREATE INDEX Search_Idx ON `fhem`.`history` (DEVICE, READING, TIMESTAMP); </code> </td></tr>
      <tr><td> <b>SQLite</b>      </td><td>: <code> CREATE INDEX Search_Idx ON `history` (DEVICE, READING, TIMESTAMP); </code> </td></tr>
      <tr><td> <b>PostgreSQL</b>  </td><td>: <code> CREATE INDEX "Search_Idx" ON history USING btree (device, reading, "timestamp"); </code> </td></tr>
    </table>
    </ul>
    <br>

  For the connection to the database a <b>configuration file</b> is used.
  The configuration is stored in a separate file to avoid storing the password in the main configuration file and to have it
  visible in the output of the <a href="https://fhem.de/commandref.html#list">list</a> command.
  <br><br>

  The <b>configuration file</b> should be copied e.g. to /opt/fhem and has the following structure you have to customize
  suitable to your conditions (decomment the appropriate raws and adjust it): <br><br>

    <pre>
    ####################################################################################
    # database configuration file
    #
    # NOTE:
    # If you don't use a value for user / password please delete the leading hash mark
    # and write 'user => ""' respectively 'password => ""' instead !
    #
    #
    ## for MySQL
    ####################################################################################
    #%dbconfig= (
    #    connection => "mysql:database=fhem;host=&lt;database host&gt;;port=3306",
    #    user => "fhemuser",
    #    password => "fhempassword",
    #    # optional enable(1) / disable(0) UTF-8 support
    #    # (full UTF-8 support exists from DBD::mysql version 4.032, but installing
    #    # 4.042 is highly suggested)
    #    utf8 => 1
    #);
    ####################################################################################
    #
    ## for PostgreSQL
    ####################################################################################
    #%dbconfig= (
    #    connection => "Pg:database=fhem;host=&lt;database host&gt;",
    #    user => "fhemuser",
    #    password => "fhempassword"
    #);
    ####################################################################################
    #
    ## for SQLite (username and password stay empty for SQLite)
    ####################################################################################
    #%dbconfig= (
    #    connection => "SQLite:dbname=/opt/fhem/fhem.db",
    #    user => "",
    #    password => ""
    #);
    ####################################################################################
    </pre>
    If configDB is used, the configuration file has to be uploaded into the configDB ! <br><br>

    <b>Note about special characters:</b><br>
    If special characters, e.g. @,$ or % which have a meaning in the perl programming
    language are used in a password, these special characters have to be escaped.
    That means in this example you have to use: \@,\$ respectively \%.
    <br>
    <br>
    <br>


  <a id="DbLog-define"></a>
  <b>Define</b>
  <br>
  <br>

  <ul>

    <b>define &lt;name&gt; DbLog &lt;configfilename&gt; &lt;regexp&gt; </b> <br><br>

    <code>&lt;configfilename&gt;</code> is the prepared <b>configuration file</b>. <br>
    <code>&lt;regexp&gt;</code> is identical to the specification of regex in the <a href="https://fhem.de/commandref.html#FileLog">FileLog</a> definition.
    <br><br>

    <b>Example:</b>
    <ul>
        <code>define myDbLog DbLog /etc/fhem/db.conf .*:.*</code><br>
        all events will stored into the database
    </ul>
    <br>

    After you have defined your DbLog-device it is recommended to run the <b>configuration check</b> <br><br>
    <ul>
        <code>set &lt;name&gt; configCheck</code> <br>
    </ul>
    <br>

    This check reports some important settings and gives recommendations back to you if proposals are indentified.
    <br><br>

    DbLog distinguishes between the synchronous (default) and asynchronous logmode. The logmode is adjustable by the
    <a href="#DbLog-attr-asyncMode">asyncMode</a>. Since version 2.13.5 DbLog is supporting primary key (PK) set in table
    current or history. If you want use PostgreSQL with PK it has to be at lest version 9.5.
    <br><br>

    The content of VALUE will be optimized for automated post-processing, e.g. <code>yes</code> is translated to <code>1</code>
    <br><br>

    The stored values can be retrieved by the following code like FileLog:<br>
    <ul>
      <code>get myDbLog - - 2012-11-10 2012-11-10 KS300:temperature::</code>
    </ul>
    <br>

    <b>transfer FileLog-data to DbLog </b> <br><br>
    There is the special module 98_FileLogConvert.pm available to transfer filelog-data to the DbLog-database. <br>
    The module can be downloaded <a href="https://svn.fhem.de/trac/browser/trunk/fhem/contrib/98_FileLogConvert.pm"> here</a>
    or from directory ./contrib instead.
    Further information and help you can find in the corresponding <a href="https://forum.fhem.de/index.php/topic,66383.0.html">
    Forumthread </a>. <br><br><br>

    <b>Reporting and Management of DbLog database content</b> <br><br>
    By using <a href="https://fhem.de/commandref.html#SVG">SVG</a> database content can be visualized. <br>
    Beyond that the module <a href="https://fhem.de/commandref.html#DbRep">DbRep</a> can be used to prepare tabular
    database reports or you can manage the database content with available functions of that module.
    <br><br><br>

    <b>Troubleshooting</b> <br><br>
    If after successful definition the DbLog-device doesn't work as expected, the following notes may help:
    <br><br>

    <ul>
    <li> Have the preparatory steps as described in commandref been done ? (install software components, create tables and index) </li>
    <li> Was "set &lt;name&gt; configCheck" executed after definition and potential errors fixed or rather the hints implemented ? </li>
    <li> If configDB is used ... has the database configuration file been imported into configDB (e.g. by "configDB fileimport ./db.conf") ? </li>
    <li> When creating a SVG-plot and no drop-down list with proposed values appear -> set attribute "DbLogType" to "Current/History". </li>
    </ul>
    <br>

    If the notes don't lead to success, please increase verbose level of the DbLog-device to 4 or 5 and observe entries in
    logfile relating to the DbLog-device.

    For problem analysis please post the output of "list &lt;name&gt;", the result of "set &lt;name&gt; configCheck" and the
    logfile entries of DbLog-device to the forum thread.
    <br><br>

  </ul>
  <br>

  <a id="DbLog-set"></a>
  <b>Set</b>
  <br>
  <br>

  <ul>
    <li><b>set &lt;name&gt; addCacheLine YYYY-MM-DD HH:MM:SS|&lt;device&gt;|&lt;type&gt;|&lt;event&gt;|&lt;reading&gt;|&lt;value&gt;|[&lt;unit&gt;]  </b> <br><br>

    <ul>
    In asynchronous mode a new dataset is inserted to the Cache and will be processed at the next database sync cycle.
    <br><br>

      <b>Example:</b> <br>
      set &lt;name&gt; addCacheLine 2017-12-05 17:03:59|MaxBathRoom|MAX|valveposition: 95|valveposition|95|% <br>

    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; addLog &lt;devspec&gt;:&lt;Reading&gt; [Value] [CN=&lt;caller name&gt;] [!useExcludes] </b> <br><br>

    <ul>
    Inserts an additional log entry of a device/reading combination into the database. Readings which are possibly specified
    in attribute "DbLogExclude" (in source device) are not logged, unless they are enclosed in attribute "DbLogInclude"
    or addLog was called with option "!useExcludes". <br><br>

      <ul>
      <li> <b>&lt;devspec&gt;:&lt;Reading&gt;</b> - The device can be declared by a <a href="#devspec">device specification
                                                    (devspec)</a>. "Reading" will be evaluated as regular expression. If
                                                    The reading isn't available and the value "Value" is specified, the
                                                    reading will be added to database as new one if it isn't a regular
                                                    expression and the readingname is valid.  </li>
      <li> <b>Value</b> - Optionally you can enter a "Value" that is used as reading value in the dataset. If the value isn't
                          specified (default), the current value of the specified reading will be inserted into the database. </li>
      <li> <b>CN=&lt;caller name&gt;</b> - By the key "CN=" (<b>C</b>aller <b>N</b>ame) you can specify an additional string,
                                           e.g. the name of a calling device (for example an at- or notify-device).
                                           Via the function defined in <a href="#DbLog-attr-valueFn">valueFn</a> this key can be analyzed
                                           by the variable $CN. Thereby it is possible to control the behavior of the addLog dependend from
                                           the calling source. </li>
      <li> <b>!useExcludes</b> - The function considers attribute "DbLogExclude" in the source device if it is set. If the optional
                                 keyword "!useExcludes" is set, the attribute "DbLogExclude" isn't considered. </li>
      </ul>
      <br>

      The database field "EVENT" will be filled with the string "addLog" automatically. <br>
      The addLog-command dosn't create an additional event in your system !<br><br>

      <b>Examples:</b> <br>
      set &lt;name&gt; addLog SMA_Energymeter:Bezug_Wirkleistung <br>
      set &lt;name&gt; addLog TYPE=SSCam:state <br>
      set &lt;name&gt; addLog MyWetter:(fc10.*|fc8.*) <br>
      set &lt;name&gt; addLog MyWetter:(wind|wind_ch.*) 20 !useExcludes <br>
      set &lt;name&gt; addLog TYPE=CUL_HM:FILTER=model=HM-CC-RT-DN:FILTER=subType!=(virtual|):(measured-temp|desired-temp|actuator) <br><br>

      set &lt;name&gt; addLog USV:state CN=di.cronjob <br>
      In the valueFn-function the caller "di.cronjob" is evaluated via the variable $CN and the timestamp is corrected: <br><br>
      valueFn = if($CN eq "di.cronjob" and $TIMESTAMP =~ m/\s00:00:[\d:]+/) { $TIMESTAMP =~ s/\s([^\s]+)/ 23:59:59/ }

    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; clearReadings </b> <br><br>
    <ul>
      This function clears readings which were created by different DbLog-functions.
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; commitCache </b> <br><br>
    <ul>
      In asynchronous mode (<a href="#DbLog-attr-asyncMode">asyncMode=1</a>), the cached data in memory will be written into the database
      and subsequently the cache will be cleared. Thereby the internal timer for the asynchronous mode Modus will be set new.
      The command can be usefull in case of you want to write the cached data manually or e.g. by an AT-device on a defined
      point of time into the database.
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; configCheck </b> <br><br>
    <ul>
      This command checks some important settings and give recommendations back to you if proposals are identified.
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; count </b> <br><br>
     <ul>
      Count records in tables current and history and write results into readings countCurrent and countHistory.
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; countNbl </b> <br><br>
    <ul>
      The non-blocking execution of "set &lt;name&gt; count".
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; deleteOldDays &lt;n&gt; </b> <br><br>
    <ul>
      Delete records from history older than &lt;n&gt; days. Number of deleted records will be written into reading
      lastRowsDeleted.
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; deleteOldDaysNbl &lt;n&gt; </b> <br><br>
    <ul>
      Is identical to function "deleteOldDays"  whereupon deleteOldDaysNbl will be executed non-blocking.
      <br><br>

      <b>Note:</b> <br>
      Even though the function itself is non-blocking, you have to set DbLog into the asynchronous mode (attr asyncMode = 1) to
      avoid a blocking situation of FHEM !

    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; eraseReadings </b> <br><br>
    <ul>
      This function deletes all readings except reading "state".
    </li>
    </ul>
    <br>

    <a id="DbLog-set-exportCache"></a>
    <li><b>set &lt;name&gt; exportCache [nopurge | purgecache]  </b> <br><br>
    <ul>
      If DbLog is operating in asynchronous mode, it's possible to exoprt the cache content into a textfile.
      The file will be written to the directory (global->modpath)/log/ by default setting. The detination directory can be
      changed by the <a href="#DbLog-attr-expimpdir">expimpdir</a>. <br>
      The filename will be generated automatically and is built by a prefix "cache_", followed by DbLog-devicename and the
      present timestmp, e.g. "cache_LogDB_2017-03-23_22-13-55". <br>
      There are two options possible, "nopurge" respectively "purgecache". The option determines whether the cache content
      will be deleted after export or not.
      Using option "nopurge" (default) the cache content will be preserved. <br>
      The <a href="#DbLog-attr-exportCacheAppend">exportCacheAppend</a> defines, whether every export process creates a new export file
      (default) or the cache content is appended to an existing (newest) export file.
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; importCachefile &lt;file&gt;  </b> <br><br>
    <ul>
      Imports an textfile into the database which has been written by the "exportCache" function.
      The allocatable files will be searched in directory (global->modpath)/log/ by default and a drop-down list will be
      generated from the files which are found in the directory.
      The source directory can be changed by the <a href="#DbLog-attr-expimpdir">expimpdir</a>. <br>
      Only that files will be shown which are correlate on pattern starting with "cache_", followed by the DbLog-devicename. <br>
      For example a file with the name "cache_LogDB_2017-03-23_22-13-55", will match if Dblog-device has name "LogDB". <br>
      After the import has been successfully done, a prefix "impdone_" will be added at begin of the filename and this file
      ddoesn't appear on the drop-down list anymore. <br>
      If you want to import a cachefile from another source database, you may adapt the filename so it fits the search criteria
      "DbLog-Device" in its name. After renaming the file appeares again on the drop-down list.
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; listCache </b> <br><br>
    <ul>
      If DbLog is set to asynchronous mode (attribute asyncMode=1), you can use that command to list the events are
      cached in memory.
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; purgeCache </b> <br><br>
    <ul>
      In asynchronous mode (<a href="#DbLog-attr-asyncMode">asyncMode=1</a>), the in memory cached data will be deleted.
      With this command data won't be written from cache into the database.
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; reduceLog &lt;no&gt;[:&lt;nn&gt;] [average[=day]] [exclude=device1:reading1,device2:reading2,...] </b> <br><br>
      <ul>
      Reduces records older than &lt;no&gt; days and (optional) newer than &lt;nn&gt; days to one record (the 1st) each hour per device & reading. <br>
      Within the device/reading name <b>SQL-Wildcards "%" and "_"</b> can be used. <br><br>

      With the optional argument 'average' not only the records will be reduced, but all numerical values of an hour
      will be reduced to a single average. <br>
      With the optional argument 'average=day' not only the records will be reduced, but all numerical values of a
      day will be reduced to a single average. (implies 'average') <br><br>

      You can optional set the last argument to "exclude=device1:reading1,device2:reading2,..." to exclude
      device/readings from reduceLog. <br>
      Also you can optional set the last argument to "include=device:reading" to delimit the SELECT statement which
      is executed on the database. This may reduce the system RAM load and increases the performance. <br><br>

      <ul>
        <b>Example: </b> <br>
        set &lt;name&gt; reduceLog 270 average include=Luftdaten_remote:% <br>
        </ul>
        <br>

        <b>CAUTION:</b> It is strongly recommended to check if the default INDEX 'Search_Idx' exists on the table 'history'! <br>
        The execution of this command may take (without INDEX) extremely long. FHEM will be <b>blocked completely</b> after issuing the command to completion ! <br><br>

    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; reduceLogNbl &lt;no&gt;[:&lt;nn&gt;] [average[=day]] [exclude=device1:reading1,device2:reading2,...] </b> <br><br>
    <ul>
      Same function as "set &lt;name&gt; reduceLog" but FHEM won't be blocked due to this function is implemented
      non-blocking ! <br><br>

      <b>Note:</b> <br>
      Even though the function itself is non-blocking, you have to set DbLog into the asynchronous mode (attr asyncMode = 1) to
      avoid a blocking situation of FHEM !

    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; reopen [n] </b> <br><br>
      <ul>
      Perform a database disconnect and immediate reconnect to clear cache and flush journal file if no time [n] was set. <br>
      If optionally a delay time of [n] seconds was set, the database connection will be disconnect immediately but it was only reopened
      after [n] seconds. In synchronous mode the events won't saved during that time. In asynchronous mode the events will be
      stored in the memory cache and saved into database after the reconnect was done.
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; rereadcfg </b> <br><br>
    <ul>
      Perform a database disconnect and immediate reconnect to clear cache and flush journal file.<br/>
      Probably same behavior als reopen, but rereadcfg will read the configuration data before reconnect.
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; userCommand &lt;validSqlStatement&gt; </b> <br><br>
    <ul>
      Performs simple sql select statements on the connected database. Usercommand and result will be written into
      corresponding readings.</br>
      The result can only be a single line.
      The execution of SQL-Statements in DbLog is outdated. Therefore the analysis module
      <a href=https://fhem.de/commandref.html#DbRep>DbRep</a> should be used.</br>
    </li>
    </ul>
    <br>

  </ul>
  <br>

  <a id="DbLog-get"></a>
  <b>Get</b>
  <br>
  <br>

    <ul>
      <li><b>get &lt;name&gt; ReadingsVal &lt;device&gt; &lt;reading&gt; &lt;default&gt; </b> <br> </li>
      <li><b>get &lt;name&gt; ReadingsTimestamp &lt;device&gt; &lt;reading&gt; &lt;default&gt; </b> <br><br>

      Retrieve one single value, use and syntax are similar to ReadingsVal() and ReadingsTimestamp() functions.

    </li>
    </ul>
    <br>

  <ul>
    <li><b>get &lt;name&gt; &lt;infile&gt; &lt;outfile&gt; &lt;from&gt;
          &lt;to&gt; &lt;column_spec&gt; </b> <br><br>

    Read data from the Database, used by frontends to plot data without direct
    access to the Database.<br>

    <ul>
      <li>&lt;in&gt;<br>
        A dummy parameter for FileLog compatibility. Sessing by defaultto <code>-</code><br>
        <ul>
          <li>current: reading actual readings from table "current"</li>
          <li>history: reading history readings from table "history"</li>
          <li>-: identical to "history"</li>
        </ul>
      </li>
      <li>&lt;out&gt;<br>
        A dummy parameter for FileLog compatibility. Setting by default to <code>-</code>
        to check the output for plot-computing.<br>
        Set it to the special keyword
        <code>all</code> to get all columns from Database.
        <ul>
          <li>ALL: get all colums from table, including a header</li>
          <li>Array: get the columns as array of hashes</li>
          <li>INT: internally used by generating plots</li>
          <li>-: default</li>
        </ul>
      </li>
      <li>&lt;from&gt; / &lt;to&gt;<br>
        Used to select the data. Please use the following timeformat or
        an initial substring of it:<br>
        <ul><code>YYYY-MM-DD_HH24:MI:SS</code></ul></li>
      <li>&lt;column_spec&gt;<br>
        For each column_spec return a set of data separated by
        a comment line on the current connection.<br>
        Syntax: &lt;device&gt;:&lt;reading&gt;:&lt;default&gt;:&lt;fn&gt;:&lt;regexp&gt;<br>
        <ul>
          <li>&lt;device&gt;<br>
            The name of the device. Case sensitive. Using a the joker "%" is supported.</li>
          <li>&lt;reading&gt;<br>
            The reading of the given device to select. Case sensitive. Using a the joker "%" is supported.
            </li>
          <li>&lt;default&gt;<br>
            no implemented yet
            </li>
          <li>&lt;fn&gt;
            One of the following:
            <ul>
              <li>int<br>
                Extract the integer at the beginning of the string. Used e.g.
                for constructs like 10%</li>
              <li>int&lt;digit&gt;<br>
                Extract the decimal digits including negative character and
                decimal point at the beginning og the string. Used e.g.
                for constructs like 15.7&deg;C</li>
              <li>delta-h / delta-d<br>
                Return the delta of the values for a given hour or a given day.
                Used if the column contains a counter, as is the case for the
                KS300 rain column.</li>
              <li>delta-ts<br>
                Replaced the original value with a measured value of seconds since
                the last and the actual logentry.
              </li>
            </ul></li>
            <li>&lt;regexp&gt;<br>
              The string is evaluated as a perl expression.  The regexp is executed
              before &lt;fn&gt; parameter.<br>
              Note: The string/perl expression cannot contain spaces,
              as the part after the space will be considered as the
              next column_spec.<br>
              <b>Keywords</b>
              <li>$val is the current value returned from the Database.</li>
              <li>$ts is the current timestamp returned from the Database.</li>
              <li>This Logentry will not print out if $val contains th keyword "hide".</li>
              <li>This Logentry will not print out and not used in the following processing
                  if $val contains th keyword "ignore".</li>
            </li>
        </ul></li>
      </ul>
    <br><br>
    Examples:
      <ul>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 KS300:temperature</code></li>
        <li><code>get myDbLog current ALL - - %:temperature</code></li><br>
            you will get all actual readings "temperature" from all logged devices.
            Be careful by using "history" as inputfile because a long execution time will be expected!
        <li><code>get myDbLog - - 2012-11-10_10 2012-11-10_20 KS300:temperature::int1</code><br>
           like from 10am until 08pm at 10.11.2012</li>
        <li><code>get myDbLog - all 2012-11-10 2012-11-20 KS300:temperature</code></li>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 KS300:temperature KS300:rain::delta-h KS300:rain::delta-d</code></li>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 MyFS20:data:::$val=~s/(on|off).*/$1eq"on"?1:0/eg</code><br>
           return 1 for all occurance of on* (on|on-for-timer etc) and 0 for all off*</li>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 Bodenfeuchte:data:::$val=~s/.*B:\s([-\.\d]+).*/$1/eg</code><br>
           Example of OWAD: value like this: <code>"A: 49.527 % B: 66.647 % C: 9.797 % D: 0.097 V"</code><br>
           and output for port B is like this: <code>2012-11-20_10:23:54 66.647</code></li>
        <li><code>get DbLog - - 2013-05-26 2013-05-28 Pumpe:data::delta-ts:$val=~s/on/hide/</code><br>
           Setting up a "Counter of Uptime". The function delta-ts gets the seconds between the last and the
           actual logentry. The keyword "hide" will hide the logentry of "on" because this time
           is a "counter of Downtime"</li>

      </ul>
    </li>
    </ul>
    <br>

  <b>Get</b> when used for webcharts
  <ul>
    <li><b>get &lt;name&gt; &lt;infile&gt; &lt;outfile&gt; &lt;from&gt;
          &lt;to&gt; &lt;device&gt; &lt;querytype&gt; &lt;xaxis&gt; &lt;yaxis&gt; &lt;savename&gt; </b> <br><br>

    Query the Database to retrieve JSON-Formatted Data, which is used by the charting frontend.
    <br>

    <ul>
      <li>&lt;name&gt;<br>
        The name of the defined DbLog, like it is given in fhem.cfg.</li>
      <li>&lt;in&gt;<br>
        A dummy parameter for FileLog compatibility. Always set to <code>-</code></li>
      <li>&lt;out&gt;<br>
        A dummy parameter for FileLog compatibility. Set it to <code>webchart</code>
        to use the charting related get function.
      </li>
      <li>&lt;from&gt; / &lt;to&gt;<br>
        Used to select the data. Please use the following timeformat:<br>
        <ul><code>YYYY-MM-DD_HH24:MI:SS</code></ul></li>
      <li>&lt;device&gt;<br>
        A string which represents the device to query.</li>
      <li>&lt;querytype&gt;<br>
        A string which represents the method the query should use. Actually supported values are: <br>
          <code>getreadings</code> to retrieve the possible readings for a given device<br>
          <code>getdevices</code> to retrieve all available devices<br>
          <code>timerange</code> to retrieve charting data, which requires a given xaxis, yaxis, device, to and from<br>
          <code>savechart</code> to save a chart configuration in the database. Requires a given xaxis, yaxis, device, to and from, and a 'savename' used to save the chart<br>
          <code>deletechart</code> to delete a saved chart. Requires a given id which was set on save of the chart<br>
          <code>getcharts</code> to get a list of all saved charts.<br>
          <code>getTableData</code> to get jsonformatted data from the database. Uses paging Parameters like start and limit.<br>
          <code>hourstats</code> to get statistics for a given value (yaxis) for an hour.<br>
          <code>daystats</code> to get statistics for a given value (yaxis) for a day.<br>
          <code>weekstats</code> to get statistics for a given value (yaxis) for a week.<br>
          <code>monthstats</code> to get statistics for a given value (yaxis) for a month.<br>
          <code>yearstats</code> to get statistics for a given value (yaxis) for a year.<br>
      </li>
      <li>&lt;xaxis&gt;<br>
        A string which represents the xaxis</li>
      <li>&lt;yaxis&gt;<br>
         A string which represents the yaxis</li>
      <li>&lt;savename&gt;<br>
         A string which represents the name a chart will be saved with</li>
      <li>&lt;chartconfig&gt;<br>
         A jsonstring which represents the chart to save</li>
      <li>&lt;pagingstart&gt;<br>
         An integer used to determine the start for the sql used for query 'getTableData'</li>
      <li>&lt;paginglimit&gt;<br>
         An integer used to set the limit for the sql used for query 'getTableData'</li>
      </ul>
    <br><br>
    <b>Examples:</b>
      <ul>
        <li><code>get logdb - webchart "" "" "" getcharts</code><br>
            Retrieves all saved charts from the Database</li>
        <li><code>get logdb - webchart "" "" "" getdevices</code><br>
            Retrieves all available devices from the Database</li>
        <li><code>get logdb - webchart "" "" ESA2000_LED_011e getreadings</code><br>
            Retrieves all available Readings for a given device from the Database</li>
        <li><code>get logdb - webchart 2013-02-11_00:00:00 2013-02-12_00:00:00 ESA2000_LED_011e timerange TIMESTAMP day_kwh</code><br>
            Retrieves charting data, which requires a given xaxis, yaxis, device, to and from<br>
            Will ouput a JSON like this: <code>[{'TIMESTAMP':'2013-02-11 00:10:10','VALUE':'0.22431388090756'},{'TIMESTAMP'.....}]</code></li>
        <li><code>get logdb - webchart 2013-02-11_00:00:00 2013-02-12_00:00:00 ESA2000_LED_011e savechart TIMESTAMP day_kwh tageskwh</code><br>
            Will save a chart in the database with the given name and the chart configuration parameters</li>
        <li><code>get logdb - webchart "" "" "" deletechart "" "" 7</code><br>
            Will delete a chart from the database with the given id</li>
      </ul>
    </li>
    </ul>
    <br>

  <a id="DbLog-attr"></a>
  <b>Attributes</b>
  <br>
  <br>

  <ul>
    <a id="DbLog-attr-addStateEvent"></a>
    <li><b>addStateEvent</b>
    <ul>
      <code>attr &lt;device&gt; addStateEvent [0|1]
      </code><br><br>

      As you probably know the event associated with the state Reading is special, as the "state: "
      string is stripped, i.e event is not "state: on" but just "on". <br>
      Mostly it is desireable to get the complete event without "state: " stripped, so it is the default behavior of DbLog.
      That means you will get state-event complete as "state: xxx". <br>
      In some circumstances, e.g. older or special modules, it is a good idea to set addStateEvent to "0".
      Try it if you have trouble with the default adjustment.
      <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-asyncMode"></a>
    <li><b>asyncMode</b>
    <ul>
      <code>attr &lt;device&gt; asyncMode [1|0]
      </code><br><br>

      This attribute determines the operation mode of DbLog. If asynchronous mode is active (asyncMode=1), the events which should be saved
      at first will be cached in memory. After synchronisation time cycle (attribute syncInterval), or if the count limit of datasets in cache
      is reached (attribute cacheLimit), the cached events get saved into the database using bulk insert.
      If the database isn't available, the events will be cached in memeory furthermore, and tried to save into database again after
      the next synchronisation time cycle if the database is available. <br>
      In asynchronous mode the data insert into database will be executed non-blocking by a background process.
      You can adjust the timeout value for this background process by attribute "timeout" (default 86400s). <br>
      In synchronous mode (normal mode) the events won't be cached im memory and get saved into database immediately. If the database isn't
      available the events are get lost. <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-bulkInsert"></a>
    <li><b>bulkInsert</b>
    <ul>
      <code>attr &lt;device&gt; bulkInsert [1|0]
      </code><br><br>

      Toggles the Insert mode between Array (default) and Bulk. This Bulk insert mode increase the write performance
      into the history table significant in case of plenty of data to insert, especially if asynchronous mode is
      used.
      To get the whole improved performance, the attribute "DbLogType" should <b>not</b> contain the current table
      in this use case. <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-commitMode"></a>
    <li><b>commitMode</b>
    <ul>
      <code>attr &lt;device&gt; commitMode [basic_ta:on | basic_ta:off | ac:on_ta:on | ac:on_ta:off | ac:off_ta:on]
      </code><br><br>

      Change the usage of database autocommit- and/or transaction- behavior. <br>
      If transaction "off" is used, not saved datasets are not returned to cache in asynchronous mode. <br>
      This attribute is an advanced feature and should only be used in a concrete situation or support case. <br><br>

      <ul>
      <li>basic_ta:on   - autocommit server basic setting / transaktion on (default) </li>
      <li>basic_ta:off  - autocommit server basic setting / transaktion off </li>
      <li>ac:on_ta:on   - autocommit on / transaktion on </li>
      <li>ac:on_ta:off  - autocommit on / transaktion off </li>
      <li>ac:off_ta:on  - autocommit off / transaktion on (autocommit "off" set transaktion "on" implicitly) </li>
      </ul>

    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-cacheEvents"></a>
    <li><b>cacheEvents</b>
    <ul>
      <code>attr &lt;device&gt; cacheEvents [2|1|0]
      </code><br><br>

      <ul>
      <li>cacheEvents=1: creates events of reading CacheUsage at point of time when a new dataset has been added to the cache. </li>
      <li>cacheEvents=2: creates events of reading CacheUsage at point of time when in aychronous mode a new write cycle to the
                         database starts. In that moment CacheUsage contains the number of datasets which will be written to
                         the database. </li><br>
      </ul>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-cacheLimit"></a>
     <li><b>cacheLimit</b>
     <ul>
       <code>
       attr &lt;device&gt; cacheLimit &lt;n&gt;
       </code><br><br>

       In asynchronous logging mode the content of cache will be written into the database and cleared if the number &lt;n&gt; datasets
       in cache has reached (default: 500). Thereby the timer of asynchronous logging mode will be set new to the value of
       attribute "syncInterval". In case of error the next write attempt will be started at the earliest after syncInterval/2. <br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-cacheOverflowThreshold"></a>
     <li><b>cacheOverflowThreshold</b>
     <ul>
       <code>
       attr &lt;device&gt; cacheOverflowThreshold &lt;n&gt;
       </code><br><br>

       In asynchronous log mode, sets the threshold of &lt;n&gt; records above which the cache contents are exported to a file
       instead of writing the data to the database. <br>
       The function corresponds to the "exportCache purgecache" set command and uses its settings. <br>
       With this attribute an overload of the server memory can be prevented if the database is not available for a longer period of time.
       time (e.g. in case of error or maintenance). If the attribute value is smaller or equal to the value of the
       attribute "cacheLimit", the value of "cacheLimit" is used for "cacheOverflowThreshold". <br>
       In this case, the cache will <b>always</b> be written to a file instead of to the database if the threshold value
       has been reached. <br>
       Thus, the data can be specifically written to one or more files with this setting, in order to import them into the
       database at a later time with the set command "importCachefile".
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-colEvent"></a>
     <li><b>colEvent</b>
     <ul>
       <code>
       attr &lt;device&gt; colEvent &lt;n&gt;
       </code><br><br>

       The field length of database field EVENT will be adjusted. By this attribute the default value in the DbLog-device can be
       adjusted if the field length in the databse was changed nanually. If colEvent=0 is set, the database field
       EVENT won't be filled . <br>
       <b>Note:</b> <br>
       If the attribute is set, all of the field length limits are valid also for SQLite databases as noticed in Internal COLUMNS !  <br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-colReading"></a>
     <li><b>colReading</b>
     <ul>
       <code>
       attr &lt;device&gt; colReading &lt;n&gt;
       </code><br><br>

       The field length of database field READING will be adjusted. By this attribute the default value in the DbLog-device can be
       adjusted if the field length in the databse was changed nanually. If colReading=0 is set, the database field
       READING won't be filled . <br>
       <b>Note:</b> <br>
       If the attribute is set, all of the field length limits are valid also for SQLite databases as noticed in Internal COLUMNS !  <br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-colValue"></a>
     <li><b>colValue</b>
     <ul>
       <code>
       attr &lt;device&gt; colValue &lt;n&gt;
       </code><br><br>

       The field length of database field VALUE will be adjusted. By this attribute the default value in the DbLog-device can be
       adjusted if the field length in the databse was changed nanually. If colEvent=0 is set, the database field
       VALUE won't be filled . <br>
       <b>Note:</b> <br>
       If the attribute is set, all of the field length limits are valid also for SQLite databases as noticed in Internal COLUMNS !  <br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-DbLogType"></a>
     <li><b>DbLogType</b>
     <ul>
       <code>
       attr &lt;device&gt; DbLogType [Current|History|Current/History]
       </code><br><br>

       This attribute determines which table or which tables in the database are wanted to use. If the attribute isn't set,
       the adjustment <i>history</i> will be used as default. <br>


       The meaning of the adjustments in detail are: <br><br>

       <ul>
       <table>
       <colgroup> <col width=10%> <col width=90%> </colgroup>
       <tr><td> <b>Current</b>            </td><td>Events are only logged into the current-table.
                                                   The entries of current-table will evaluated with SVG-creation.  </td></tr>
       <tr><td> <b>History</b>            </td><td>Events are only logged into the history-table. No dropdown list with proposals will created with the
                                                   SVG-creation.   </td></tr>
       <tr><td> <b>Current/History</b>    </td><td>Events will be logged both the current- and the history-table.
                                                   The entries of current-table will evaluated with SVG-creation.  </td></tr>
       <tr><td> <b>SampleFill/History</b> </td><td>Events are only logged into the history-table. The entries of current-table will evaluated with SVG-creation
                                                   and can be filled up with a customizable extract of the history-table by using a
                                                   <a href="http://fhem.de/commandref.html#DbRep">DbRep-device</a> command
                                                   "set &lt;DbRep-name&gt; tableCurrentFillup"  (advanced feature).  </td></tr>
       </table>
       </ul>
       <br>
       <br>

       <b>Note:</b> <br>
       The current-table has to be used to get a Device:Reading-DropDown list when a SVG-Plot will be created. <br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-DbLogSelectionMode"></a>
    <li><b>DbLogSelectionMode</b>
    <ul>
      <code>
      attr &lt;device&gt; DbLogSelectionMode [Exclude|Include|Exclude/Include]
      </code><br><br>

      This attribute, specific to DbLog devices, influences how the device-specific attributes
      <a href="#DbLog-attr-DbLogExclude">DbLogExclude</a> and <a href="#DbLog-attr-DbLogInclude">DbLogInclude</a>
      are evaluated. DbLogExclude and DbLogInclude are set in the source devices. <br>
      If the DbLogSelectionMode attribute is not set, "Exclude" is the default.
      <br><br>

      <ul>
        <li><b>Exclude:</b> Readings are logged if they match the regex specified in the DEF. Excluded are
                            the readings that match the regex in the DbLogExclude attribute. <br>
                            The DbLogInclude attribute is not considered in this case.
                            </li>
                            <br>
        <li><b>Include:</b> Only readings are logged which are included via the regex in the attribute DbLogInclude
                            are included. <br>
                            The DbLogExclude attribute is not considered in this case, nor is the regex in DEF.
                            </li>
                            <br>
        <li><b>Exclude/Include:</b> Works basically like "Exclude", except that both the attribute DbLogExclude
                                    attribute and the DbLogInclude attribute are checked.
                                    Readings that were excluded by DbLogExclude, but are included by DbLogInclude
                                    are therefore still included in the logging.
                                    </li>
         </ul>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-DbLogInclude"></a>
    <li><b>DbLogInclude</b>
    <ul>
      <code>
      attr <device> DbLogInclude Regex[:MinInterval][:force],[Regex[:MinInterval][:force]], ...
      </code><br><br>

      The DbLogInclude attribute defines the readings to be stored in the database. <br>
      The definition of the readings to be stored is done by a regular expression and all readings that match the regular
      expression are stored in the database. <br>

      The optional &lt;MinInterval&gt; addition specifies that a value is saved when at least &lt;MinInterval&gt;
      seconds have passed since the last save. <br>

      Regardless of the expiration of the interval, the reading is saved if the value of the reading has changed. <br>
      With the optional modifier "force" the specified interval &lt;MinInterval&gt; can be forced to be kept even
      if the value of the reading has changed since the last storage.
      <br><br>

      <ul>
      <pre>
        | <b>Modifier</b> |            <b>within interval</b>           | <b>outside interval</b> |
        |          | Value equal        | Value changed   |                  |
        |----------+--------------------+-----------------+------------------|
        | &lt;none&gt;   | ignore             | store           | store            |
        | force    | ignore             | ignore          | store            |
      </pre>
      </ul>

      <br>
      <b>Notes: </b> <br>
      The DbLogInclude attribute is propagated in all devices when DbLog is used. <br>
      The <a href="#DbLog-attr-DbLogSelectionMode">DbLogSelectionMode</a> attribute must be set accordingly
      to enable DbLogInclude. <br>
      With the <a href="#DbLog-attr-defaultMinInterval">defaultMinInterval</a> attribute a default for
	  &lt;MinInterval&gt; can be specified.
      <br><br>

      <b>Example</b> <br>
      <code>attr MyDevice1 DbLogInclude .*</code> <br>
      <code>attr MyDevice2 DbLogInclude state,(floorplantext|MyUserReading):300,battery:3600</code> <br>
      <code>attr MyDevice2 DbLogInclude state,(floorplantext|MyUserReading):300:force,battery:3600:force</code>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-DbLogExclude"></a>
    <li><b>DbLogExclude</b>
    <ul>
      <code>
      attr &lt;device&gt; DbLogExclude regex[:MinInterval][:force],[regex[:MinInterval][:force]] ...
      </code><br><br>

      The DbLogExclude attribute defines the readings that <b>should not</b> be stored in the database. <br>

      The definition of the readings to be excluded is done via a regular expression and all readings matching the
      regular expression are excluded from logging to the database. <br>

      Readings that have not been excluded via the regex are logged in the database. The behavior of the
	  storage is controlled with the following optional specifications. <br>
      The optional &lt;MinInterval&gt; addition specifies that a value is saved when at least &lt;MinInterval&gt;
      seconds have passed since the last storage. <br>

      Regardless of the expiration of the interval, the reading is saved if the value of the reading has changed. <br>
      With the optional modifier "force" the specified interval &lt;MinInterval&gt; can be forced to be kept even
      if the value of the reading has changed since the last storage.
      <br><br>

      <ul>
      <pre>
        | <b>Modifier</b> |            <b>within interval</b>           | <b>outside interval</b> |
        |          | Value equal        | Value changed   |                  |
        |----------+--------------------+-----------------+------------------|
        | &lt;none&gt;   | ignore             | store           | store            |
        | force    | ignore             | ignore          | store            |
      </pre>
      </ul>

      <br>
      <b>Notes: </b> <br>
      The DbLogExclude attribute is propagated in all devices when DbLog is used. <br>
      The <a href="#DbLog-attr-DbLogSelectionMode">DbLogSelectionMode</a> attribute can be set appropriately
      to disable DbLogExclude. <br>
      With the <a href="#DbLog-attr-defaultMinInterval">defaultMinInterval</a> attribute a default for
	  &lt;MinInterval&gt; can be specified.
      <br><br>

      <b>Example</b> <br>
      <code>attr MyDevice1 DbLogExclude .*</code> <br>
      <code>attr MyDevice2 DbLogExclude state,(floorplantext|MyUserReading):300,battery:3600</code> <br>
      <code>attr MyDevice2 DbLogExclude state,(floorplantext|MyUserReading):300:force,battery:3600:force</code>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-DbLogValueFn"></a>
     <li><b>DbLogValueFn</b>
     <ul>
       <code>
       attr &lt;device&gt; DbLogValueFn {}
       </code><br><br>

       The attribute <i>DbLogValueFn</i> will be propagated to all devices if DbLog is used.
       This attribute contains a Perl expression that can use and change values of $TIMESTAMP, $READING, $VALUE (value of
       reading) and $UNIT (unit of reading value). That means the changed values are logged. <br>
       Furthermore you have readonly access to $DEVICE (the source device name), $EVENT, $LASTTIMESTAMP and $LASTVALUE
       for evaluation in your expression.
       The variables $LASTTIMESTAMP and $LASTVALUE contain time and value of the last logged dataset of $DEVICE / $READING. <br>
       If the $TIMESTAMP is to be changed, it must meet the condition "yyyy-mm-dd hh:mm:ss", otherwise the $timestamp wouldn't
       be changed.
       In addition you can set the variable $IGNORE=1 if you want skip a dataset from logging. <br>

       The device specific function in "DbLogValueFn" is applied to the dataset before the potential existing attribute
       "valueFn" in the DbLog device.
       <br><br>

       <b>Example</b> <br>
       <pre>
attr SMA_Energymeter DbLogValueFn
{
  if ($READING eq "Bezug_WirkP_Kosten_Diff"){
    $UNIT="Diff-W";
  }
  if ($READING =~ /Einspeisung_Wirkleistung_Zaehler/ && $VALUE < 2){
    $IGNORE=1;
  }
}
       </pre>
     </ul>
     </li>
  </ul>

  <ul>
    <a id="DbLog-attr-dbSchema"></a>
    <li><b>dbSchema</b>
    <ul>
      <code>
      attr &lt;device&gt; dbSchema &lt;schema&gt;
      </code><br><br>

      This attribute is available for database types MySQL/MariaDB and PostgreSQL. The table names (current/history) are
      extended by its database schema. It is an advanced feature and normally not necessary to set.
      <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-defaultMinInterval"></a>
    <li><b>defaultMinInterval</b>
    <ul>
      <code>
      attr &lt;device&gt; defaultMinInterval &lt;devspec&gt;::&lt;MinInterval&gt;[::force],[&lt;devspec&gt;::&lt;MinInterval&gt;[::force]] ...
      </code><br><br>

      With this attribute a default minimum interval for <a href="http://fhem.de/commandref.html#devspec">devspec</a> is defined.
      If a defaultMinInterval is set, the logentry is dropped if the defined interval is not reached <b>and</b> the value vs.
      lastvalue is equal. <br>
      If the optional parameter "force" is set, the logentry is also dropped even though the value is not
      equal the last one and the defined interval is not reached. <br>
      Potential set DbLogExclude / DbLogInclude specifications in source devices are having priority over defaultMinInterval
      and are <b>not</b> overwritten by this attribute. <br>
      This attribute can be specified as multiline input. <br><br>

      <b>Examples</b> <br>
      <code>attr dblog defaultMinInterval .*::120::force </code> <br>
      # Events of all devices are logged only in case of 120 seconds are elapsed to the last log entry (reading specific) independent of a possible value change. <br>
      <code>attr dblog defaultMinInterval (Weather|SMA)::300 </code> <br>
      # Events of devices "Weather" and "SMA" are logged only in case of 300 seconds are elapsed to the last log entry (reading specific) and the value is equal to the last logged value. <br>
      <code>attr dblog defaultMinInterval TYPE=CUL_HM::600::force </code> <br>
      # Events of all devices of Type "CUL_HM" are logged only in case of 600 seconds are elapsed to the last log entry (reading specific) independent of a possible value change.
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-disable"></a>
    <li><b>disable</b>
    <ul>
      <code>
      attr &lt;device&gt; disable [0|1]
      </code><br><br>

      Disables the DbLog device (1) or enables it (0).
      <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-excludeDevs"></a>
     <li><b>excludeDevs</b>
     <ul>
       <code>
       attr &lt;device&gt; excludeDevs &lt;devspec1&gt;[#Reading],&lt;devspec2&gt;[#Reading],&lt;devspec...&gt;
       </code><br><br>

       The device/reading-combinations "devspec1#Reading", "devspec2#Reading" up to "devspec.." are globally excluded from
       logging into the database. <br>
       The specification of a reading is optional. <br>
       Thereby devices are explicit and consequently excluded from logging without consideration of another excludes or
       includes (e.g. in DEF).
       The devices to exclude can be specified as <a href="#devspec">device-specification</a>.
       <br><br>

       <b>Examples</b> <br>
       <code>
       attr &lt;device&gt; excludeDevs global,Log.*,Cam.*,TYPE=DbLog
       </code><br>
       # The devices global respectively devices starting with "Log" or "Cam" and devices with Type=DbLog are excluded from database logging. <br>
       <code>
       attr &lt;device&gt; excludeDevs .*#.*Wirkleistung.*
       </code><br>
       # All device/reading-combinations which contain "Wirkleistung" in reading are excluded from logging. <br>
       <code>
       attr &lt;device&gt; excludeDevs SMA_Energymeter#Bezug_WirkP_Zaehler_Diff
       </code><br>
       # The event containing device "SMA_Energymeter" and reading "Bezug_WirkP_Zaehler_Diff" are excluded from logging. <br>
       </ul>
  </ul>
  </li>
  <br>

  <ul>
     <a id="DbLog-attr-expimpdir"></a>
     <li><b>expimpdir</b>
     <ul>
       <code>
       attr &lt;device&gt; expimpdir &lt;directory&gt;
       </code><br><br>

       If the cache content will be exported by <a href="#DbLog-set-exportCache">exportCache</a> command,
       the file will be written into or read from that directory. The default directory is
       "(global->modpath)/log/".
       Make sure the specified directory is existing and writable.
       <br><br>

      <b>Example</b> <br>
      <code>
      attr &lt;device&gt; expimpdir /opt/fhem/cache/
      </code><br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-exportCacheAppend"></a>
     <li><b>exportCacheAppend</b>
     <ul>
       <code>
       attr &lt;device&gt; exportCacheAppend [1|0]
       </code><br><br>

       If set, the export of cache ("set &lt;device&gt; exportCache") appends the content to the newest available
       export file. If there is no exististing export file, it will be new created. <br>
       If the attribute not set, every export process creates a new export file . (default)<br/>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-noNotifyDev"></a>
     <li><b>noNotifyDev</b>
     <ul>
       <code>
       attr &lt;device&gt; noNotifyDev [1|0]
       </code><br><br>

       Enforces that NOTIFYDEV won't set and hence won't used. <br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-noSupportPK"></a>
     <li><b>noSupportPK</b>
     <ul>
       <code>
       attr &lt;device&gt; noSupportPK [1|0]
       </code><br><br>

       Deactivates the support of a set primary key by the module.<br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-SQLiteCacheSize"></a>
     <li><b>SQLiteCacheSize</b>
     <ul>
       <code>
       attr &lt;device&gt; SQLiteCacheSize &lt;number of memory pages used for caching&gt;
       </code><br><br>

       The default is about 4MB of RAM to use for caching (page_size=1024bytes, cache_size=4000).<br>
       Embedded devices with scarce amount of RAM can go with 1000 pages or less. This will impact
       the overall performance of SQLite. <br>
       (default: 4000)
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-SQLiteJournalMode"></a>
     <li><b>SQLiteJournalMode</b>
     <ul>
       <code>
       attr &lt;device&gt; SQLiteJournalMode [WAL|off]
       </code><br><br>

       Determines how SQLite databases are opened. Generally the Write-Ahead-Log (<b>WAL</b>) is the best choice for robustness
       and data integrity.<br>
       Since WAL about doubles the spaces requirements on disk it might not be the best fit for embedded devices
       using a RAM backed disk. <b>off</b> will turn the journaling off. In case of corruption, the database probably
       won't be possible to repair and has to be recreated! <br>
       (default: WAL)
     </ul>
     </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-syncEvents"></a>
    <li><b>syncEvents</b>
    <ul>
      <code>attr &lt;device&gt; syncEvents [1|0]
      </code><br><br>

      events of reading syncEvents will be created. <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-showproctime"></a>
    <li><b>showproctime</b>
    <ul>
      <code>attr &lt;device&gt; [1|0]
      </code><br><br>

      If set, the reading "sql_processing_time" shows the required execution time (in seconds) for the sql-requests. This is not calculated
      for a single sql-statement, but the summary of all sql-statements necessary for within an executed DbLog-function in background.
      The reading "background_processing_time" shows the total time used in background.  <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-showNotifyTime"></a>
    <li><b>showNotifyTime</b>
    <ul>
      <code>attr &lt;device&gt; showNotifyTime [1|0]
      </code><br><br>

      If set, the reading "notify_processing_time" shows the required execution time (in seconds) in the DbLog
      Notify-function. This attribute is practical for performance analyses and helps to determine the differences of time
      required when the operation mode was switched from synchronous to the asynchronous mode. <br>

    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-syncInterval"></a>
    <li><b>syncInterval</b>
    <ul>
      <code>attr &lt;device&gt; syncInterval &lt;n&gt;
      </code><br><br>

      If DbLog is set to asynchronous operation mode (attribute asyncMode=1), with this attribute you can setup the interval in seconds
      used for storage the in memory cached events into the database. THe default value is 30 seconds. <br>

    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-suppressAddLogV3"></a>
    <li><b>suppressAddLogV3</b>
    <ul>
      <code>attr &lt;device&gt; suppressAddLogV3 [1|0]
      </code><br><br>

      If set, verbose 3 Logfileentries done by the addLog-function will be suppressed.  <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-suppressUndef"></a>
    <li><b>suppressUndef</b>
    <ul>
      <code>
      attr &lt;device&gt; suppressUndef <n>
      </code><br><br>

      Suppresses all undef values when returning data from the DB via get. 
      
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-timeout"></a>
    <li><b>timeout</b>
    <ul>
      <code>
      attr &lt;device&gt; timeout &lt;n&gt;
      </code><br><br>

      setup timeout of the write cycle into database in asynchronous mode (default 86400s) <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-traceFlag"></a>
    <li><b>traceFlag</b>
    <ul>
      <code>
      attr &lt;device&gt; traceFlag &lt;ALL|SQL|CON|ENC|DBD|TXN&gt;
      </code><br><br>

      Trace flags are used to enable tracing of specific activities within the DBI and drivers. The attribute is only used for
      tracing of errors in case of support. <br><br>

       <ul>
       <table>
       <colgroup> <col width=10%> <col width=90%> </colgroup>
       <tr><td> <b>ALL</b>            </td><td>turn on all DBI and driver flags  </td></tr>
       <tr><td> <b>SQL</b>            </td><td>trace SQL statements executed (Default) </td></tr>
       <tr><td> <b>CON</b>            </td><td>trace connection process  </td></tr>
       <tr><td> <b>ENC</b>            </td><td>trace encoding (unicode translations etc)  </td></tr>
       <tr><td> <b>DBD</b>            </td><td>trace only DBD messages  </td></tr>
       <tr><td> <b>TXN</b>            </td><td>trace transactions  </td></tr>

       </table>
       </ul>
       <br>

    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-traceHandles"></a>
    <li><b>traceHandles</b>
    <ul>
      <code>attr &lt;device&gt; traceHandles &lt;n&gt;
      </code><br><br>

      If set, every &lt;n&gt; seconds the system wide existing database handles are printed out into the logfile.
      This attribute is only relevant in case of support. (default: 0 = switch off) <br>

    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-traceLevel"></a>
    <li><b>traceLevel</b>
    <ul>
      <code>
      attr &lt;device&gt; traceLevel &lt;0|1|2|3|4|5|6|7&gt;
      </code><br><br>

      Switch on the tracing function of the module. <br>
      <b>Caution !</b> The attribute is only used for tracing errors or in case of support. If switched on <b>very much entries</b>
                       will be written into the FHEM Logfile ! <br><br>

       <ul>
       <table>
       <colgroup> <col width=5%> <col width=95%> </colgroup>
       <tr><td> <b>0</b>            </td><td>Trace disabled. (Default)  </td></tr>
       <tr><td> <b>1</b>            </td><td>Trace top-level DBI method calls returning with results or errors. </td></tr>
       <tr><td> <b>2</b>            </td><td>As above, adding tracing of top-level method entry with parameters.  </td></tr>
       <tr><td> <b>3</b>            </td><td>As above, adding some high-level information from the driver
                                             and some internal information from the DBI.  </td></tr>
       <tr><td> <b>4</b>            </td><td>As above, adding more detailed information from the driver. </td></tr>
       <tr><td> <b>5-7</b>          </td><td>As above but with more and more internal information.  </td></tr>

       </table>
       </ul>
       <br>

    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-useCharfilter"></a>
    <li><b>useCharfilter</b>
    <ul>
      <code>
      attr &lt;device&gt; useCharfilter [0|1] <n>
      </code><br><br>

      If set, only ASCII characters from 32 to 126 are accepted in event.
      That are the characters " A-Za-z0-9!"#$%&'()*+,-.\/:;<=>?@[\\]^_`{|}~" .<br>
      Mutated vowel and "€" are transcribed (e.g. ä to ae). (default: 0). <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-valueFn"></a>
     <li><b>valueFn</b>
     <ul>
       <code>
       attr &lt;device&gt; valueFn {}
       </code><br><br>

       The attribute contains a Perl expression that can use and change values of $TIMESTAMP, $DEVICE, $DEVICETYPE, $READING,
       $VALUE (value of reading) and $UNIT (unit of reading value). <br>
       Furthermore you have readonly access to $EVENT, $LASTTIMESTAMP and $LASTVALUE for evaluation in your expression.
       The variables $LASTTIMESTAMP and $LASTVALUE contain time and value of the last logged dataset of $DEVICE / $READING. <br>
       If $TIMESTAMP is to be changed, it must meet the condition "yyyy-mm-dd hh:mm:ss", otherwise the $timestamp wouldn't
       be changed.
       In addition you can set the variable $IGNORE=1 if you want skip a dataset from logging. <br><br>

      <b>Examples</b> <br>
      <code>
      attr &lt;device&gt; valueFn {if ($DEVICE eq "living_Clima" && $VALUE eq "off" ){$VALUE=0;} elsif ($DEVICE eq "e-power"){$VALUE= sprintf "%.1f", $VALUE;}}
      </code> <br>
      # change value "off" to "0" of device "living_Clima" and rounds value of e-power to 1f <br><br>
      <code>
      attr &lt;device&gt; valueFn {if ($DEVICE eq "SMA_Energymeter" && $READING eq "state"){$IGNORE=1;}}
      </code><br>
      # don't log the dataset of device "SMA_Energymeter" if the reading is "state"  <br><br>
      <code>
      attr &lt;device&gt; valueFn {if ($DEVICE eq "Dum.Energy" && $READING eq "TotalConsumption"){$UNIT="W";}}
      </code><br>
      # set the unit of device "Dum.Energy" to "W" if reading is "TotalConsumption" <br><br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-verbose4Devs"></a>
     <li><b>verbose4Devs</b>
     <ul>
       <code>
       attr &lt;device&gt; verbose4Devs &lt;device1&gt;,&lt;device2&gt;,&lt;device..&gt;
       </code><br><br>

       If verbose level 4 is used, only output of devices set in this attribute will be reported in FHEM central logfile. If this attribute
       isn't set, output of all relevant devices will be reported if using verbose level 4.
       The given devices are evaluated as Regex. <br><br>

      <b>Example</b> <br>
      <code>
      attr &lt;device&gt; verbose4Devs sys.*,.*5000.*,Cam.*,global
      </code><br>
      # The devices starting with "sys", "Cam" respectively devices are containing "5000" in its name and the device "global" will be reported in FHEM
      central Logfile if verbose=4 is set. <br>
     </ul>
     </li>
  </ul>
  <br>

</ul>

=end html
=begin html_DE

<a id="DbLog"></a>
<h3>DbLog</h3>
<br>

<ul>
  Mit DbLog werden Events in einer Datenbank gespeichert. Es wird SQLite, MySQL/MariaDB und PostgreSQL unterstützt. <br><br>

  <b>Voraussetzungen</b> <br><br>

    Die Perl-Module <code>DBI</code> und <code>DBD::&lt;dbtype&gt;</code> müssen installiert werden (use <code>cpan -i &lt;module&gt;</code>
    falls die eigene Distribution diese nicht schon mitbringt).
    <br><br>

    Auf einem Debian-System können diese Module z.Bsp. installiert werden mit: <br><br>

    <ul>
    <table>
    <colgroup> <col width=5%> <col width=95%> </colgroup>
      <tr><td> <b>DBI</b>         </td><td>: <code> sudo apt-get install libdbi-perl </code> </td></tr>
      <tr><td> <b>MySQL</b>       </td><td>: <code> sudo apt-get install [mysql-server] mysql-client libdbd-mysql libdbd-mysql-perl </code> (mysql-server nur bei lokaler MySQL-Server-Installation) </td></tr>
      <tr><td> <b>SQLite</b>      </td><td>: <code> sudo apt-get install sqlite3 libdbi-perl libdbd-sqlite3-perl </code> </td></tr>
      <tr><td> <b>PostgreSQL</b>  </td><td>: <code> sudo apt-get install libdbd-pg-perl </code> </td></tr>
    </table>
    </ul>
    <br>
    <br>

  <b>Vorbereitungen</b> <br><br>

  Zunächst muss die Datenbank installiert und angelegt werden.
  Die Installation des Datenbanksystems selbst wird hier nicht beschrieben. Dazu bitte nach den Installationsvorgaben des
  verwendeten Datenbanksystems verfahren. <br><br>

  <b>Hinweis:</b> <br>
  Im Falle eines frisch installierten MySQL/MariaDB Systems bitte nicht vergessen die anonymen "Jeder"-Nutzer mit einem
  Admin-Tool (z.B. phpMyAdmin) zu löschen falls sie existieren !
  <br><br>

  Beispielcode bzw. Scripts zum Erstellen einer MySQL/PostgreSQL/SQLite Datenbank ist im
  <a href="https://svn.fhem.de/trac/browser/trunk/fhem/contrib/dblog">SVN -&gt; contrib/dblog/db_create_&lt;DBType&gt;.sql</a>
  enthalten. <br>
  (<b>Achtung:</b> Die lokale FHEM-Installation enthält im Unterverzeichnis ./contrib/dblog nicht die aktuellsten
  Scripte !!) <br><br>

  Die Datenbank beinhaltet 2 Tabellen: <code>current</code> und <code>history</code>. <br>
  Die Tabelle <code>current</code> enthält den letzten Stand pro Device und Reading. <br>
  In der Tabelle <code>history</code> sind alle Events historisch gespeichert. <br>
  Beachten sie bitte unbedingt das <a href="#DbLog-attr-DbLogType">DbLogType</a> um die Benutzung der Tabellen
  <code>current</code> und <code>history</code> festzulegen.
  <br><br>

  Die Tabellenspalten haben folgende Bedeutung: <br><br>

    <ul>
    <table>
    <colgroup> <col width=5%> <col width=95%> </colgroup>
      <tr><td> TIMESTAMP </td><td>: Zeitpunkt des Events, z.B. <code>2007-12-30 21:45:22</code> </td></tr>
      <tr><td> DEVICE    </td><td>: Name des Devices, z.B. <code>Wetterstation</code> </td></tr>
      <tr><td> TYPE      </td><td>: Type des Devices, z.B. <code>KS300</code> </td></tr>
      <tr><td> EVENT     </td><td>: das auftretende Event als volle Zeichenkette, z.B. <code>humidity: 71 (%)</code> </td></tr>
      <tr><td> READING   </td><td>: Name des Readings, ermittelt aus dem Event, z.B. <code>humidity</code> </td></tr>
      <tr><td> VALUE     </td><td>: aktueller Wert des Readings, ermittelt aus dem Event, z.B. <code>71</code> </td></tr>
      <tr><td> UNIT      </td><td>: Einheit, ermittelt aus dem Event, z.B. <code>%</code> </td></tr>
    </table>
    </ul>
    <br>
    <br>

  <b>Index anlegen</b> <br>
  Für die Leseperformance, z.B. bei der Erstellung von SVG-PLots, ist es von besonderer Bedeutung dass der <b>Index "Search_Idx"</b>
  oder ein vergleichbarer Index (z.B. ein Primary Key) angelegt ist. <br><br>

  Der Index "Search_Idx" kann mit diesen Statements, z.B. in der Datenbank 'fhem', angelegt werden (auch nachträglich): <br><br>

    <ul>
    <table>
    <colgroup> <col width=5%> <col width=95%> </colgroup>
      <tr><td> <b>MySQL</b>       </td><td>: <code> CREATE INDEX Search_Idx ON `fhem`.`history` (DEVICE, READING, TIMESTAMP); </code> </td></tr>
      <tr><td> <b>SQLite</b>      </td><td>: <code> CREATE INDEX Search_Idx ON `history` (DEVICE, READING, TIMESTAMP); </code> </td></tr>
      <tr><td> <b>PostgreSQL</b>  </td><td>: <code> CREATE INDEX "Search_Idx" ON history USING btree (device, reading, "timestamp"); </code> </td></tr>
    </table>
    </ul>
    <br>

  Der Code zur Anlage ist ebenfalls in den Scripten
  <a href="https://svn.fhem.de/trac/browser/trunk/fhem/contrib/dblog">SVN -&gt; contrib/dblog/db_create_&lt;DBType&gt;.sql</a>
  enthalten. <br><br>

  Für die Verbindung zur Datenbank wird eine <b>Konfigurationsdatei</b> verwendet.
  Die Konfiguration ist in einer sparaten Datei abgelegt um das Datenbankpasswort nicht in Klartext in der
  FHEM-Haupt-Konfigurationsdatei speichern zu müssen.
  Ansonsten wäre es mittels des <a href="https://fhem.de/commandref_DE.html#list">list</a> Befehls einfach auslesbar.
  <br><br>

  Die <b>Konfigurationsdatei</b> wird z.B. nach /opt/fhem kopiert und hat folgenden Aufbau, den man an seine Umgebung
  anpassen muß (entsprechende Zeilen entkommentieren und anpassen): <br><br>

    <pre>
    ####################################################################################
    # database configuration file
    #
    # NOTE:
    # If you don't use a value for user / password please delete the leading hash mark
    # and write 'user => ""' respectively 'password => ""' instead !
    #
    #
    ## for MySQL
    ####################################################################################
    #%dbconfig= (
    #    connection => "mysql:database=fhem;host=&lt;database host&gt;;port=3306",
    #    user => "fhemuser",
    #    password => "fhempassword",
    #    # optional enable(1) / disable(0) UTF-8 support
    #    # (full UTF-8 support exists from DBD::mysql version 4.032, but installing
    #    # 4.042 is highly suggested)
    #    utf8 => 1
    #);
    ####################################################################################
    #
    ## for PostgreSQL
    ####################################################################################
    #%dbconfig= (
    #    connection => "Pg:database=fhem;host=&lt;database host&gt;",
    #    user => "fhemuser",
    #    password => "fhempassword"
    #);
    ####################################################################################
    #
    ## for SQLite (username and password stay empty for SQLite)
    ####################################################################################
    #%dbconfig= (
    #    connection => "SQLite:dbname=/opt/fhem/fhem.db",
    #    user => "",
    #    password => ""
    #);
    ####################################################################################
    </pre>
    Wird configDB genutzt, ist das Konfigurationsfile in die configDB hochzuladen ! <br><br>

    <b>Hinweis zu Sonderzeichen:</b><br>
    Werden Sonderzeichen, wie z.B. @, $ oder %, welche eine programmtechnische Bedeutung in Perl haben im Passwort verwendet,
    sind diese Zeichen zu escapen.
    Das heißt in diesem Beispiel wäre zu verwenden: \@,\$ bzw. \%.
    <br>
    <br>
    <br>

  <a id="DbLog-define"></a>
  <b>Define</b>
  <br><br>

  <ul>
    <code>define &lt;name&gt; DbLog &lt;configfilename&gt; &lt;regexp&gt;</code>
    <br><br>

    <code>&lt;configfilename&gt;</code> ist die vorbereitete <b>Konfigurationsdatei</b>. <br>
    <code>&lt;regexp&gt;</code> ist identisch <a href="https://fhem.de/commandref_DE.html#FileLog">FileLog</a> der Filelog-Definition.
    <br><br>

    <b>Beispiel:</b>
    <ul>
        <code>define myDbLog DbLog /etc/fhem/db.conf .*:.*</code><br>
        speichert alles in der Datenbank
    </ul>
    <br>

    Nachdem das DbLog-Device definiert wurde, ist empfohlen einen <b>Konfigurationscheck</b> auszuführen: <br><br>
    <ul>
        <code>set &lt;name&gt; configCheck</code> <br>
    </ul>
    <br>
    Dieser Check prüft einige wichtige Einstellungen des DbLog-Devices und gibt Empfehlungen für potentielle Verbesserungen.
    <br><br>
    <br>

    DbLog unterscheidet den synchronen (Default) und asynchronen Logmodus. Der Logmodus ist über das
    <a href="#DbLog-attr-asyncMode">asyncMode</a> einstellbar. Ab Version 2.13.5 unterstützt DbLog einen gesetzten
    Primary Key (PK) in den Tabellen Current und History. Soll PostgreSQL mit PK genutzt werden, muss PostgreSQL mindestens
    Version 9.5 sein.
    <br><br>

    Der gespeicherte Wert des Readings wird optimiert für eine automatisierte Nachverarbeitung, z.B. <code>yes</code> wird transformiert
    nach <code>1</code>. <br><br>

    Die gespeicherten Werte können mittels GET Funktion angezeigt werden:
    <ul>
      <code>get myDbLog - - 2012-11-10 2012-11-10 KS300:temperature</code>
    </ul>
    <br>

    <b>FileLog-Dateien nach DbLog übertragen</b> <br><br>
    Zur Übertragung von vorhandenen Filelog-Daten in die DbLog-Datenbank steht das spezielle Modul 98_FileLogConvert.pm
    zur Verfügung. <br>
    Dieses Modul kann <a href="https://svn.fhem.de/trac/browser/trunk/fhem/contrib/98_FileLogConvert.pm"> hier</a>
    bzw. aus dem Verzeichnis ./contrib geladen werden.
    Weitere Informationen und Hilfestellung gibt es im entsprechenden <a href="https://forum.fhem.de/index.php/topic,66383.0.html">
    Forumthread </a>. <br><br><br>

    <b>Reporting und Management von DbLog-Datenbankinhalten</b> <br><br>
    Mit Hilfe <a href="https://fhem.de/commandref_DE.html#SVG">SVG</a> können Datenbankinhalte visualisiert werden. <br>
    Darüber hinaus kann das Modul <a href="https://fhem.de/commandref_DE.html#DbRep">DbRep</a> genutzt werden um tabellarische
    Datenbankauswertungen anzufertigen oder den Datenbankinhalt mit den zur Verfügung stehenden Funktionen zu verwalten.
    <br><br><br>

    <b>Troubleshooting</b> <br><br>
    Wenn nach der erfolgreichen Definition das DbLog-Device nicht wie erwartet arbeitet,
    können folgende Hinweise hilfreich sein: <br><br>

    <ul>
    <li> Wurden die vorbereitenden Schritte gemacht, die in der commandref beschrieben sind ? (Softwarekomponenten installieren, Tabellen, Index anlegen) </li>
    <li> Wurde ein "set &lt;name&gt; configCheck" nach dem Define durchgeführt und eventuelle Fehler beseitigt bzw. Empfehlungen umgesetzt ? </li>
    <li> Falls configDB in Benutzung ... wurde das DB-Konfigurationsfile in configDB importiert (z.B. mit "configDB fileimport ./db.conf") ? </li>
    <li> Beim Anlegen eines SVG-Plots erscheint keine Drop-Down Liste mit Vorschlagswerten -> Attribut "DbLogType" auf "Current/History" setzen. </li>
    </ul>
    <br>

    Sollten diese Hinweise nicht zum Erfolg führen, bitte den verbose-Level im DbLog Device auf 4 oder 5 hochsetzen und
    die Einträge bezüglich des DbLog-Device im Logfile beachten.

    Zur Problemanalyse bitte die Ausgabe von "list &lt;name&gt;", das Ergebnis von "set &lt;name&gt; configCheck" und die
    Ausgaben des DbLog-Device im Logfile im Forumthread posten.
    <br><br>

  </ul>
  <br>
  <br>

  <a id="DbLog-set"></a>
  <b>Set</b>
  <br>
  <br>

  <ul>
    <li><b>set &lt;name&gt; addCacheLine YYYY-MM-DD HH:MM:SS|&lt;device&gt;|&lt;type&gt;|&lt;event&gt;|&lt;reading&gt;|&lt;value&gt;|[&lt;unit&gt;]  </b> <br><br>

    <ul>
    Im asynchronen Modus wird ein neuer Datensatz in den Cache eingefügt und beim nächsten Synclauf mit abgearbeitet.
    <br><br>

      <b>Beispiel:</b> <br>
      set &lt;name&gt; addCacheLine 2017-12-05 17:03:59|MaxBathRoom|MAX|valveposition: 95|valveposition|95|% <br>
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; addLog &lt;devspec&gt;:&lt;Reading&gt; [Value] [CN=&lt;caller name&gt;] [!useExcludes] </b> <br><br>

    <ul>
    Fügt einen zusätzlichen Logeintrag einer Device/Reading-Kombination in die Datenbank ein. Die eventuell im Attribut
    "DbLogExclude" spezifizierten Readings (im Quelldevice) werden nicht geloggt, es sei denn sie sind im Attribut
    "DbLogInclude"  enthalten bzw. der addLog-Aufruf erfolgte mit der Option "!useExcludes".  <br><br>

      <ul>
      <li> <b>&lt;devspec&gt;:&lt;Reading&gt;</b> - Das Device kann als <a href="#devspec">Geräte-Spezifikation</a> angegeben werden. <br>
                                                    Die Angabe von "Reading" wird als regulärer Ausdruck ausgewertet. Ist
                                                    das Reading nicht vorhanden und der Wert "Value" angegeben, wird das Reading
                                                    in die DB eingefügt wenn es kein regulärer Ausdruck und ein valider
                                                    Readingname ist. </li>
      <li> <b>Value</b> - Optional kann "Value" für den Readingwert angegeben werden. Ist Value nicht angegeben, wird der aktuelle
                          Wert des Readings in die DB eingefügt. </li>
      <li> <b>CN=&lt;caller name&gt;</b> - Mit dem Schlüssel "CN=" (<b>C</b>aller <b>N</b>ame) kann dem addLog-Aufruf ein String,
                                           z.B. der Name des aufrufenden Devices (z.B. eines at- oder notify-Devices), mitgegeben
                                           werden. Mit Hilfe der im <a href="#DbLog-attr-valueFn">valueFn</a> hinterlegten
                                           Funktion kann dieser Schlüssel über die Variable $CN ausgewertet werden. Dadurch ist es
                                           möglich, das Verhalten des addLogs abhängig von der aufrufenden Quelle zu beeinflussen.
                                           </li>
      <li> <b>!useExcludes</b> - Ein eventuell im Quell-Device gesetztes Attribut "DbLogExclude" wird von der Funktion berücksichtigt. Soll dieses
                                 Attribut nicht berücksichtigt werden, kann das Schüsselwort "!useExcludes" verwendet werden. </li>
      </ul>
      <br>

      Das Datenbankfeld "EVENT" wird automatisch mit "addLog" belegt. <br>
      Es wird KEIN zusätzlicher Event im System erzeugt !<br><br>

      <b>Beispiele:</b> <br>
      set &lt;name&gt; addLog SMA_Energymeter:Bezug_Wirkleistung <br>
      set &lt;name&gt; addLog TYPE=SSCam:state <br>
      set &lt;name&gt; addLog MyWetter:(fc10.*|fc8.*) <br>
      set &lt;name&gt; addLog MyWetter:(wind|wind_ch.*) 20 !useExcludes <br>
      set &lt;name&gt; addLog TYPE=CUL_HM:FILTER=model=HM-CC-RT-DN:FILTER=subType!=(virtual|):(measured-temp|desired-temp|actuator) <br><br>

      set &lt;name&gt; addLog USV:state CN=di.cronjob <br>
      In der valueFn-Funktion wird der Aufrufer "di.cronjob" über die Variable $CN ausgewertet und davon abhängig der
      Timestamp dieses addLog korrigiert: <br><br>
      valueFn = if($CN eq "di.cronjob" and $TIMESTAMP =~ m/\s00:00:[\d:]+/) { $TIMESTAMP =~ s/\s([^\s]+)/ 23:59:59/ }

    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; clearReadings </b> <br><br>
      <ul>
      Leert Readings die von verschiedenen DbLog-Funktionen angelegt wurden.

    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; eraseReadings </b> <br><br>
      <ul>
      Löscht alle Readings außer dem Reading "state".
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; commitCache </b> <br><br>
      <ul>
      Im asynchronen Modus (<a href="#DbLog-attr-asyncMode">asyncMode=1</a>), werden die im Speicher gecachten Daten in die Datenbank geschrieben
      und danach der Cache geleert. Der interne Timer des asynchronen Modus wird dabei neu gesetzt.
      Der Befehl kann nützlich sein um manuell oder z.B. über ein AT den Cacheinhalt zu einem definierten Zeitpunkt in die
      Datenbank zu schreiben.
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; configCheck </b> <br><br>
      <ul>Es werden einige wichtige Einstellungen geprüft und Empfehlungen gegeben falls potentielle Verbesserungen
      identifiziert wurden.
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; count </b> <br><br>
      <ul>Zählt die Datensätze in den Tabellen current und history und schreibt die Ergebnisse in die Readings
      countCurrent und countHistory.
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; countNbl </b> <br><br>
      <ul>
      Die non-blocking Ausführung von "set &lt;name&gt; count".
      <br><br>

      <b>Hinweis:</b> <br>
      Obwohl die Funktion selbst non-blocking ist, muß das DbLog-Device im asynchronen Modus betrieben werden (asyncMode = 1)
      um FHEM nicht zu blockieren !
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; deleteOldDays &lt;n&gt; </b> <br><br>
      <ul>Löscht Datensätze in Tabelle history, die älter sind als &lt;n&gt; Tage sind.
      Die Anzahl der gelöschten Datens&auml;tze wird in das Reading lastRowsDeleted geschrieben.
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; deleteOldDaysNbl &lt;n&gt; </b> <br><br>
      <ul>
      Identisch zu Funktion "deleteOldDays" wobei deleteOldDaysNbl nicht blockierend ausgeführt wird.
      <br><br>

      <b>Hinweis:</b> <br>
      Obwohl die Funktion selbst non-blocking ist, muß das DbLog-Device im asynchronen Modus betrieben werden (asyncMode = 1)
      um FHEM nicht zu blockieren !
    </li>
    </ul>
    <br>

    <a id="DbLog-set-exportCache"></a>
    <li><b>set &lt;name&gt; exportCache [nopurge | purgecache] </b> <br><br>
      <ul>
      Wenn DbLog im asynchronen Modus betrieben wird, kann der Cache mit diesem Befehl in ein Textfile geschrieben
      werden. Das File wird per Default in dem Verzeichnis (global->modpath)/log/ erstellt. Das Zielverzeichnis kann mit
      dem <a href="#DbLog-attr-expimpdir">expimpdir</a> geändert werden. <br>

      Der Name des Files wird automatisch generiert und enthält den Präfix "cache_", gefolgt von dem DbLog-Devicenamen und
      dem aktuellen Zeitstempel, z.B. "cache_LogDB_2017-03-23_22-13-55". <br>
      Mit den Optionen "nopurge" bzw. "purgecache" wird festgelegt, ob der Cacheinhalt nach dem Export gelöscht werden
      soll oder nicht. Mit "nopurge" (default) bleibt der Cacheinhalt erhalten. <br>
      Das <a href="#DbLog-attr-exportCacheAppend">exportCacheAppend</a> bestimmt dabei, ob mit jedem Exportvorgang ein neues Exportfile
      angelegt wird (default) oder der Cacheinhalt an das bestehende (neueste) Exportfile angehängt wird.
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; importCachefile &lt;file&gt; </b> <br><br>
      <ul>
      Importiert ein mit "exportCache" geschriebenes File in die Datenbank.
      Die verfügbaren Dateien werden per Default im Verzeichnis (global->modpath)/log/ gesucht und eine Drop-Down Liste
      erzeugt sofern Dateien gefunden werden. Das Quellverzeichnis kann mit dem <a href="#DbLog-attr-expimpdir">expimpdir</a>
      geändert werden. <br>
      Es werden nur die Dateien angezeigt, die dem Muster "cache_", gefolgt von dem DbLog-Devicenamen entsprechen. <br>
      Zum Beispiel "cache_LogDB_2017-03-23_22-13-55", falls das Log-Device "LogDB" heißt. <br>

      Nach einem erfolgreichen Import wird das File mit dem Präfix "impdone_" versehen und erscheint dann nicht mehr
      in der Drop-Down Liste. Soll ein Cachefile in eine andere als der Quelldatenbank importiert werden, kann das
      DbLog-Device im Filenamen angepasst werden damit dieses File den Suchktiterien entspricht und in der Drop-Down Liste
      erscheint.
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; listCache </b> <br><br>
      <ul>Wenn DbLog im asynchronen Modus betrieben wird (Attribut asyncMode=1), können mit diesem Befehl die im Speicher gecachten Events
      angezeigt werden.
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; purgeCache </b> <br><br>
      <ul>
      Im asynchronen Modus (<a href="#DbLog-attr-asyncMode">asyncMode=1</a>), werden die im Speicher gecachten Daten gelöscht.
      Es werden keine Daten aus dem Cache in die Datenbank geschrieben.
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; reduceLog &lt;no&gt;[:&lt;nn&gt;] [average[=day]] [exclude=device1:reading1,device2:reading2,...] </b> <br><br>
      <ul>
      Reduziert historische Datensätze, die älter sind als &lt;no&gt; Tage und (optional) neuer sind als &lt;nn&gt; Tage
      auf einen Eintrag (den ersten) pro Stunde je Device & Reading.<br>
      Innerhalb von device/reading können <b>SQL-Wildcards "%" und "_"</b> verwendet werden. <br><br>

      Das Reading "reduceLogState" zeigt den Ausführungsstatus des letzten reduceLog-Befehls. <br><br>
      Durch die optionale Angabe von 'average' wird nicht nur die Datenbank bereinigt, sondern alle numerischen Werte
      einer Stunde werden auf einen einzigen Mittelwert reduziert. <br>
      Durch die optionale Angabe von 'average=day' wird nicht nur die Datenbank bereinigt, sondern alle numerischen
      Werte eines Tages auf einen einzigen Mittelwert reduziert. (impliziert 'average') <br><br>

      Optional kann als letzer Parameter "exclude=device1:reading1,device2:reading2,...."
      angegeben werden um device/reading Kombinationen von reduceLog auszuschließen. <br><br>

      Optional kann als letzer Parameter "include=device:reading" angegeben werden um
      die auf die Datenbank ausgeführte SELECT-Abfrage einzugrenzen, was die RAM-Belastung verringert und die
      Performance erhöht. <br><br>

      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; reduceLog 270 average include=Luftdaten_remote:% <br>

      </ul>
      <br>

      <b>ACHTUNG:</b> Es wird dringend empfohlen zu überprüfen ob der standard INDEX 'Search_Idx' in der Tabelle 'history' existiert! <br>
      Die Abarbeitung dieses Befehls dauert unter Umständen (ohne INDEX) extrem lange. FHEM wird durch den Befehl bis
      zur Fertigstellung <b>komplett blockiert !</b>
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; reduceLogNbl &lt;no&gt;[:&lt;nn&gt;] [average[=day]] [exclude=device1:reading1,device2:reading2,...] </b> <br><br>
      <ul>
      Führt die gleiche Funktion wie "set &lt;name&gt; reduceLog" aus. Im Gegensatz zu reduceLog wird mit FHEM wird durch den Befehl reduceLogNbl nicht
      mehr blockiert da diese Funktion non-blocking implementiert ist !
      <br><br>

      <b>Hinweis:</b> <br>
      Obwohl die Funktion selbst non-blocking ist, muß das DbLog-Device im asynchronen Modus betrieben werden (asyncMode = 1)
      um FHEM nicht zu blockieren !
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; reopen [n] </b> <br><br>
      <ul>
      Schließt die Datenbank und öffnet sie danach sofort wieder wenn keine Zeit [n] in Sekunden angegeben wurde.
      Dabei wird die Journaldatei geleert und neu angelegt.<br/>
      Verbessert den Datendurchsatz und vermeidet Speicherplatzprobleme. <br>
      Wurde eine optionale Verzögerungszeit [n] in Sekunden angegeben, wird die Verbindung zur Datenbank geschlossen und erst
      nach Ablauf von [n] Sekunden wieder neu verbunden.
      Im synchronen Modus werden die Events in dieser Zeit nicht gespeichert.
      Im asynchronen Modus werden die Events im Cache gespeichert und nach dem Reconnect in die Datenbank geschrieben.
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; rereadcfg </b> <br><br>
      <ul>Schließt die Datenbank und öffnet sie danach sofort wieder. Dabei wird die Journaldatei geleert und neu angelegt.<br/>
      Verbessert den Datendurchsatz und vermeidet Speicherplatzprobleme.<br/>
      Zwischen dem Schließen der Verbindung und dem Neuverbinden werden die Konfigurationsdaten neu gelesen
    </li>
    </ul>
    <br>

    <li><b>set &lt;name&gt; userCommand &lt;validSqlStatement&gt; </b> <br><br>
      <ul>
        Führt einfache sql select Befehle auf der Datenbank aus. Der Befehl und ein zurückgeliefertes
        Ergebnis wird in das Reading "userCommand" bzw. "userCommandResult" geschrieben. Das Ergebnis kann nur
        einzeilig sein.
        Die Ausführung von SQL-Befehlen in DbLog ist veraltet. Dafür sollte das Auswertungsmodul
        <a href=https://fhem.de/commandref_DE.html#DbRep>DbRep</a> genutzt werden.</br>
    </li>
    </ul>
    <br>

  </ul>
  <br>

  <a id="DbLog-get"></a>
  <b>Get</b>
  <br>
  <br>

  <ul>
    <li><b>get &lt;name&gt; ReadingsVal &lt;device&gt; &lt;reading&gt; &lt;default&gt; </b> <br>
    </li>
    <li><b>get &lt;name&gt; ReadingsTimestamp &lt;device&gt; &lt;reading&gt; &lt;default&gt; </b> <br><br>

    Liest einen einzelnen Wert aus der Datenbank. Die Syntax ist weitgehend identisch zu ReadingsVal() und ReadingsTimestamp().
    <br/>
  </li>
  </ul>
  <br>

  <ul>
    <li><b>get &lt;name&gt; &lt;infile&gt; &lt;outfile&gt; &lt;from&gt;
          &lt;to&gt; &lt;column_spec&gt; </b> <br><br>

    Liesst Daten aus der Datenbank. Wird durch die Frontends benutzt um Plots
    zu generieren ohne selbst auf die Datenank zugreifen zu müssen.
    <br>

    <ul>
      <li>&lt;in&gt;<br>
        Ein Parameter um eine Kompatibilität zum Filelog herzustellen.
        Dieser Parameter ist per default immer auf <code>-</code> zu setzen.<br>
        Folgende Ausprägungen sind zugelassen:<br>
        <ul>
          <li>current: die aktuellen Werte aus der Tabelle "current" werden gelesen.</li>
          <li>history: die historischen Werte aus der Tabelle "history" werden gelesen.</li>
          <li>-: identisch wie "history"</li>
        </ul>
      </li>

      <li>&lt;out&gt;<br>
        Ein Parameter um eine Kompatibilität zum Filelog herzustellen.
        Dieser Parameter ist per default immer auf <code>-</code> zu setzen um die
        Ermittlung der Daten aus der Datenbank für die Plotgenerierung zu prüfen.<br>
        Folgende Ausprägungen sind zugelassen:<br>
        <ul>
          <li>ALL: Es werden alle Spalten der Datenbank ausgegeben. Inclusive einer Überschrift.</li>
          <li>Array: Es werden alle Spalten der Datenbank als Hash ausgegeben. Alle Datensätze als Array zusammengefasst.</li>
          <li>INT: intern zur Plotgenerierung verwendet</li>
          <li>-: default</li>
        </ul>
      </li>

      <li>&lt;from&gt; / &lt;to&gt;<br>
        Wird benutzt um den Zeitraum der Daten einzugrenzen. Es ist das folgende
        Zeitformat oder ein Teilstring davon zu benutzen:<br>
        <ul><code>YYYY-MM-DD_HH24:MI:SS</code></ul></li>

      <li>&lt;column_spec&gt;<br>
        Für jede column_spec Gruppe wird ein Datenset zurückgegeben welches
        durch einen Kommentar getrennt wird. Dieser Kommentar repräsentiert
        die column_spec.<br>
        Syntax: &lt;device&gt;:&lt;reading&gt;:&lt;default&gt;:&lt;fn&gt;:&lt;regexp&gt;<br>
        <ul>
          <li>&lt;device&gt;<br>
            Der Name des Devices. Achtung: Gross/Kleinschreibung beachten!<br>
            Es kann ein % als Jokerzeichen angegeben werden.</li>
          <li>&lt;reading&gt;<br>
            Das Reading des angegebenen Devices zur Datenselektion.<br>
            Es kann ein % als Jokerzeichen angegeben werden.<br>
            Achtung: Gross/Kleinschreibung beachten!
          </li>
          <li>&lt;default&gt;<br>
            Zur Zeit noch nicht implementiert.
          </li>
          <li>&lt;fn&gt;
            Angabe einer speziellen Funktion:
            <ul>
              <li>int<br>
                Ermittelt den Zahlenwert ab dem Anfang der Zeichenkette aus der
                Spalte "VALUE". Benutzt z.B. für Ausprägungen wie 10%.
              </li>
              <li>int&lt;digit&gt;<br>
                Ermittelt den Zahlenwert ab dem Anfang der Zeichenkette aus der
                Spalte "VALUE", inclusive negativen Vorzeichen und Dezimaltrenner.
                Benutzt z.B. für Auspägungen wie -5.7&deg;C.
              </li>
              <li>delta-h / delta-d<br>
                Ermittelt die relative Veränderung eines Zahlenwertes pro Stunde
                oder pro Tag. Wird benutzt z.B. für Spalten die einen
                hochlaufenden Zähler enthalten wie im Falle für ein KS300 Regenzähler
                oder dem 1-wire Modul OWCOUNT.
              </li>
              <li>delta-ts<br>
                Ermittelt die vergangene Zeit zwischen dem letzten und dem aktuellen Logeintrag
                in Sekunden und ersetzt damit den originalen Wert.
              </li>
            </ul></li>
            <li>&lt;regexp&gt;<br>
              Diese Zeichenkette wird als Perl Befehl ausgewertet.
              Die regexp wird vor dem angegebenen &lt;fn&gt; Parameter ausgeführt.
              <br>
              Bitte zur Beachtung: Diese Zeichenkette darf keine Leerzeichen
              enthalten da diese sonst als &lt;column_spec&gt; Trennung
              interpretiert werden und alles nach dem Leerzeichen als neue
              &lt;column_spec&gt; gesehen wird.<br>

              <b>Schlüsselwörter</b>
              <li>$val ist der aktuelle Wert die die Datenbank für ein Device/Reading ausgibt.</li>
              <li>$ts ist der aktuelle Timestamp des Logeintrages.</li>
              <li>Wird als $val das Schlüsselwort "hide" zurückgegeben, so wird dieser Logeintrag nicht
                  ausgegeben, trotzdem aber für die Zeitraumberechnung verwendet.</li>
              <li>Wird als $val das Schlüsselwort "ignore" zurückgegeben, so wird dieser Logeintrag
                  nicht für eine Folgeberechnung verwendet.</li>
            </li>
        </ul></li>

      </ul>
    <br><br>
    <b>Beispiele:</b>
      <ul>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 KS300:temperature</code></li>

        <li><code>get myDbLog current ALL - - %:temperature</code></li><br>
            Damit erhält man alle aktuellen Readings "temperature" von allen in der DB geloggten Devices.
            Achtung: bei Nutzung von Jokerzeichen auf die history-Tabelle kann man sein FHEM aufgrund langer Laufzeit lahmlegen!

        <li><code>get myDbLog - - 2012-11-10_10 2012-11-10_20 KS300:temperature::int1</code><br>
           gibt Daten aus von 10Uhr bis 20Uhr am 10.11.2012</li>

        <li><code>get myDbLog - all 2012-11-10 2012-11-20 KS300:temperature</code></li>

        <li><code>get myDbLog - - 2012-11-10 2012-11-20 KS300:temperature KS300:rain::delta-h KS300:rain::delta-d</code></li>

        <li><code>get myDbLog - - 2012-11-10 2012-11-20 MyFS20:data:::$val=~s/(on|off).*/$1eq"on"?1:0/eg</code><br>
           gibt 1 zurück für alle Ausprägungen von on* (on|on-for-timer etc) und 0 für alle off*</li>

        <li><code>get myDbLog - - 2012-11-10 2012-11-20 Bodenfeuchte:data:::$val=~s/.*B:\s([-\.\d]+).*/$1/eg</code><br>
           Beispiel von OWAD: Ein Wert wie z.B.: <code>"A: 49.527 % B: 66.647 % C: 9.797 % D: 0.097 V"</code><br>
           und die Ausgabe ist für das Reading B folgende: <code>2012-11-20_10:23:54 66.647</code></li>

        <li><code>get DbLog - - 2013-05-26 2013-05-28 Pumpe:data::delta-ts:$val=~s/on/hide/</code><br>
           Realisierung eines Betriebsstundenzählers. Durch delta-ts wird die Zeit in Sek zwischen den Log-
           Einträgen ermittelt. Die Zeiten werden bei den on-Meldungen nicht ausgegeben welche einer Abschaltzeit
           entsprechen würden.</li>
      </ul>
  </li>
  </ul>
  <br>

  <b>Get</b> für die Nutzung von webcharts
  <ul>
    <li><b>get &lt;name&gt; &lt;infile&gt; &lt;outfile&gt; &lt;from&gt;
          &lt;to&gt; &lt;device&gt; &lt;querytype&gt; &lt;xaxis&gt; &lt;yaxis&gt; &lt;savename&gt; </li></b>
    <br>

    Liest Daten aus der Datenbank aus und gibt diese in JSON formatiert aus. Wird für das Charting Frontend genutzt
    <br>

    <ul>
      <li>&lt;name&gt;<br>
        Der Name des definierten DbLogs, so wie er in der fhem.cfg angegeben wurde.</li>

      <li>&lt;in&gt;<br>
        Ein Dummy Parameter um eine Kompatibilität zum Filelog herzustellen.
        Dieser Parameter ist immer auf <code>-</code> zu setzen.</li>

      <li>&lt;out&gt;<br>
        Ein Dummy Parameter um eine Kompatibilität zum Filelog herzustellen.
        Dieser Parameter ist auf <code>webchart</code> zu setzen um die Charting Get Funktion zu nutzen.
      </li>

      <li>&lt;from&gt; / &lt;to&gt;<br>
        Wird benutzt um den Zeitraum der Daten einzugrenzen. Es ist das folgende
        Zeitformat zu benutzen:<br>
        <ul><code>YYYY-MM-DD_HH24:MI:SS</code></ul></li>

      <li>&lt;device&gt;<br>
        Ein String, der das abzufragende Device darstellt.</li>

      <li>&lt;querytype&gt;<br>
        Ein String, der die zu verwendende Abfragemethode darstellt. Zur Zeit unterstützte Werte sind: <br>
          <code>getreadings</code> um für ein bestimmtes device alle Readings zu erhalten<br>
          <code>getdevices</code> um alle verfügbaren devices zu erhalten<br>
          <code>timerange</code> um Chart-Daten abzufragen. Es werden die Parameter 'xaxis', 'yaxis', 'device', 'to' und 'from' benötigt<br>
          <code>savechart</code> um einen Chart unter Angabe eines 'savename' und seiner zugehörigen Konfiguration abzuspeichern<br>
          <code>deletechart</code> um einen zuvor gespeicherten Chart unter Angabe einer id zu löschen<br>
          <code>getcharts</code> um eine Liste aller gespeicherten Charts zu bekommen.<br>
          <code>getTableData</code> um Daten aus der Datenbank abzufragen und in einer Tabelle darzustellen. Benötigt paging Parameter wie start und limit.<br>
          <code>hourstats</code> um Statistiken für einen Wert (yaxis) für eine Stunde abzufragen.<br>
          <code>daystats</code> um Statistiken für einen Wert (yaxis) für einen Tag abzufragen.<br>
          <code>weekstats</code> um Statistiken für einen Wert (yaxis) für eine Woche abzufragen.<br>
          <code>monthstats</code> um Statistiken für einen Wert (yaxis) für einen Monat abzufragen.<br>
          <code>yearstats</code> um Statistiken für einen Wert (yaxis) für ein Jahr abzufragen.<br>
      </li>

      <li>&lt;xaxis&gt;<br>
        Ein String, der die X-Achse repräsentiert</li>

      <li>&lt;yaxis&gt;<br>
         Ein String, der die Y-Achse repräsentiert</li>

      <li>&lt;savename&gt;<br>
         Ein String, unter dem ein Chart in der Datenbank gespeichert werden soll</li>

      <li>&lt;chartconfig&gt;<br>
         Ein jsonstring der den zu speichernden Chart repräsentiert</li>

      <li>&lt;pagingstart&gt;<br>
         Ein Integer um den Startwert für die Abfrage 'getTableData' festzulegen</li>

      <li>&lt;paginglimit&gt;<br>
         Ein Integer um den Limitwert für die Abfrage 'getTableData' festzulegen</li>
      </ul>
    <br><br>

    <b>Beispiele:</b>
      <ul>
        <li><code>get logdb - webchart "" "" "" getcharts</code><br>
            Liefert alle gespeicherten Charts aus der Datenbank</li>

        <li><code>get logdb - webchart "" "" "" getdevices</code><br>
            Liefert alle verfügbaren Devices aus der Datenbank</li>

        <li><code>get logdb - webchart "" "" ESA2000_LED_011e getreadings</code><br>
            Liefert alle verfügbaren Readings aus der Datenbank unter Angabe eines Gerätes</li>

        <li><code>get logdb - webchart 2013-02-11_00:00:00 2013-02-12_00:00:00 ESA2000_LED_011e timerange TIMESTAMP day_kwh</code><br>
            Liefert Chart-Daten, die auf folgenden Parametern basieren: 'xaxis', 'yaxis', 'device', 'to' und 'from'<br>
            Die Ausgabe erfolgt als JSON, z.B.: <code>[{'TIMESTAMP':'2013-02-11 00:10:10','VALUE':'0.22431388090756'},{'TIMESTAMP'.....}]</code></li>

        <li><code>get logdb - webchart 2013-02-11_00:00:00 2013-02-12_00:00:00 ESA2000_LED_011e savechart TIMESTAMP day_kwh tageskwh</code><br>
            Speichert einen Chart unter Angabe eines 'savename' und seiner zugehörigen Konfiguration</li>

        <li><code>get logdb - webchart "" "" "" deletechart "" "" 7</code><br>
            Löscht einen zuvor gespeicherten Chart unter Angabe einer id</li>
      </ul>
    <br><br>
  </ul>


  <a id="DbLog-attr"></a>
  <b>Attribute</b>
  <br>
  <br>

  <ul>
    <a id="DbLog-attr-addStateEvent"></a>
    <li><b>addStateEvent</b>
    <ul>
      <code>attr &lt;device&gt; addStateEvent [0|1]
      </code><br><br>

      Bekanntlich wird normalerweise bei einem Event mit dem Reading "state" der state-String entfernt, d.h.
      der Event ist nicht zum Beispiel "state: on" sondern nur "on". <br>
      Meistens ist es aber hilfreich in DbLog den kompletten Event verarbeiten zu können. Deswegen übernimmt DbLog per Default
      den Event inklusive dem Reading-String "state". <br>
      In einigen Fällen, z.B. alten oder speziellen Modulen, ist es allerdings wünschenswert den state-String wie gewöhnlich
      zu entfernen. In diesen Fällen bitte addStateEvent = "0" setzen.
      Versuchen sie bitte diese Einstellung, falls es mit dem Standard Probleme geben sollte.
      <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-asyncMode"></a>
    <li><b>asyncMode</b>
    <ul>
      <code>attr &lt;device&gt; asyncMode [1|0]
      </code><br><br>

      Dieses Attribut stellt den Arbeitsmodus von DbLog ein. Im asynchronen Modus (asyncMode=1), werden die zu speichernden Events zunächst in Speicher
      gecacht. Nach Ablauf der Synchronisationszeit (Attribut syncInterval) oder bei Erreichen der maximalen Anzahl der Datensätze im Cache
      (Attribut cacheLimit) werden die gecachten Events im Block in die Datenbank geschrieben.
      Ist die Datenbank nicht verfügbar, werden die Events weiterhin im Speicher gehalten und nach Ablauf des Syncintervalls in die Datenbank
      geschrieben falls sie dann verfügbar ist. <br>
      Im asynchronen Mode werden die Daten nicht blockierend mit einem separaten Hintergrundprozess in die Datenbank geschrieben.
      Det Timeout-Wert für diesen Hintergrundprozess kann mit dem Attribut "timeout" (Default 86400s) eingestellt werden.
      Im synchronen Modus (Normalmodus) werden die Events nicht gecacht und sofort in die Datenbank geschrieben. Ist die Datenbank nicht
      verfügbar, gehen sie verloren.<br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-bulkInsert"></a>
    <li><b>bulkInsert</b>
    <ul>
      <code>attr &lt;device&gt; bulkInsert [1|0]
      </code><br><br>

      Schaltet den Insert-Modus zwischen "Array" (default) und "Bulk" um. Der Bulk Modus führt beim Insert von sehr
      vielen Datensätzen in die history-Tabelle zu einer erheblichen Performancesteigerung vor allem im asynchronen
      Mode. Um die volle Performancesteigerung zu erhalten, sollte in diesem Fall das Attribut "DbLogType"
      <b>nicht</b> die current-Tabelle enthalten. <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-cacheEvents"></a>
    <li><b>cacheEvents</b>
    <ul>
      <code>attr &lt;device&gt; cacheEvents [2|1|0]
      </code><br><br>

      <ul>
      <li>cacheEvents=1: es werden Events für das Reading CacheUsage erzeugt wenn ein Event zum Cache hinzugefügt wurde. </li>
      <li>cacheEvents=2: es werden Events für das Reading CacheUsage erzeugt wenn im asynchronen Mode der Schreibzyklus in die
                         Datenbank beginnt. CacheUsage enthält zu diesem Zeitpunkt die Anzahl der in die Datenbank zu schreibenden
                         Datensätze. </li><br>
      </ul>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-cacheLimit"></a>
     <li><b>cacheLimit</b>
     <ul>
       <code>
       attr &lt;device&gt; cacheLimit &lt;n&gt;
       </code><br><br>

       Im asynchronen Logmodus wird der Cache in die Datenbank weggeschrieben und geleert wenn die Anzahl &lt;n&gt; Datensätze
       im Cache erreicht ist (default: 500). <br>
       Der Timer des asynchronen Logmodus wird dabei neu auf den Wert des Attributs "syncInterval"
       gesetzt. Im Fehlerfall wird ein erneuter Schreibversuch frühestens nach syncInterval/2 gestartet. <br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-cacheOverflowThreshold"></a>
     <li><b>cacheOverflowThreshold</b>
     <ul>
       <code>
       attr &lt;device&gt; cacheOverflowThreshold &lt;n&gt;
       </code><br><br>

       Legt im asynchronen Logmodus den Schwellenwert von &lt;n&gt; Datensätzen fest, ab dem der Cacheinhalt in ein File
       exportiert wird anstatt die Daten in die Datenbank zu schreiben. <br>
       Die Funktion entspricht dem Set-Kommando "exportCache purgecache" und verwendet dessen Einstellungen. <br>
       Mit diesem Attribut kann eine Überlastung des Serverspeichers verhindert werden falls die Datenbank für eine längere
       Zeit nicht verfügbar ist (z.B. im Fehler- oder Wartungsfall). Ist der Attributwert kleiner oder gleich dem Wert des
       Attributs "cacheLimit", wird der Wert von "cacheLimit" für "cacheOverflowThreshold" verwendet. <br>
       In diesem Fall wird der Cache <b>immer</b> in ein File geschrieben anstatt in die Datenbank sofern der Schwellenwert
       erreicht wurde. <br>
       So können die Daten mit dieser Einstellung gezielt in ein oder mehrere Dateien geschreiben werden, um sie zu einem
       späteren Zeitpunkt mit dem Set-Befehl "importCachefile" in die Datenbank zu importieren.
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-colEvent"></a>
     <li><b>colEvent</b>
     <ul>
       <code>
       attr &lt;device&gt; colEvent &lt;n&gt;
       </code><br><br>

       Die Feldlänge für das DB-Feld EVENT wird userspezifisch angepasst. Mit dem Attribut kann der Default-Wert im Modul
       verändert werden wenn die Feldlänge in der Datenbank manuell geändert wurde. Mit colEvent=0 wird das Datenbankfeld
       EVENT nicht gefüllt. <br>
       <b>Hinweis:</b> <br>
       Mit gesetztem Attribut gelten alle Feldlängenbegrenzungen auch für SQLite DB wie im Internal COLUMNS angezeigt !  <br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-colReading"></a>
     <li><b>colReading</b>
     <ul>
       <code>
       attr &lt;device&gt; colReading &lt;n&gt;
       </code><br><br>

       Die Feldlänge für das DB-Feld READING wird userspezifisch angepasst. Mit dem Attribut kann der Default-Wert im Modul
       verändert werden wenn die Feldlänge in der Datenbank manuell geändert wurde. Mit colReading=0 wird das Datenbankfeld
       READING nicht gefüllt. <br>
       <b>Hinweis:</b> <br>
       Mit gesetztem Attribut gelten alle Feldlängenbegrenzungen auch für SQLite DB wie im Internal COLUMNS angezeigt !  <br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-colValue"></a>
     <li><b>colValue</b>
     <ul>
       <code>
       attr &lt;device&gt; colValue &lt;n&gt;
       </code><br><br>

       Die Feldlänge für das DB-Feld VALUE wird userspezifisch angepasst. Mit dem Attribut kann der Default-Wert im Modul
       verändert werden wenn die Feldlänge in der Datenbank manuell geändert wurde. Mit colValue=0 wird das Datenbankfeld
       VALUE nicht gefüllt. <br>
       <b>Hinweis:</b> <br>
       Mit gesetztem Attribut gelten alle Feldlängenbegrenzungen auch für SQLite DB wie im Internal COLUMNS angezeigt !  <br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-commitMode"></a>
    <li><b>commitMode</b>
    <ul>
      <code>attr &lt;device&gt; commitMode [basic_ta:on | basic_ta:off | ac:on_ta:on | ac:on_ta:off | ac:off_ta:on]
      </code><br><br>

      Ändert die Verwendung der Datenbank Autocommit- und/oder Transaktionsfunktionen.
      Wird Transaktion "aus" verwendet, werden im asynchronen Modus nicht gespeicherte Datensätze nicht an den Cache zurück
      gegeben.
      Dieses Attribut ist ein advanced feature und sollte nur im konkreten Bedarfs- bzw. Supportfall geändert werden.<br><br>

      <ul>
      <li>basic_ta:on   - Autocommit Servereinstellung / Transaktion ein (default) </li>
      <li>basic_ta:off  - Autocommit Servereinstellung / Transaktion aus </li>
      <li>ac:on_ta:on   - Autocommit ein / Transaktion ein </li>
      <li>ac:on_ta:off  - Autocommit ein / Transaktion aus </li>
      <li>ac:off_ta:on  - Autocommit aus / Transaktion ein (Autocommit "aus" impliziert Transaktion "ein") </li>
      </ul>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-convertTimezone"></a>
     <li><b>convertTimezone</b>
     <ul>
       <code>
       attr &lt;device&gt; convertTimezone [UTC | none]
       </code><br><br>

       UTC - der lokale Timestamp des Events wird nach UTC konvertiert. <br>
       (default: none) <br><br>

       <b>Hinweis:</b> <br>
       Die Perl-Module 'DateTime' und 'DateTime::Format::Strptime' müssen installiert sein !
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-DbLogType"></a>
     <li><b>DbLogType</b>
     <ul>
       <code>
       attr &lt;device&gt; DbLogType [Current|History|Current/History|SampleFill/History]
       </code><br><br>

       Dieses Attribut legt fest, welche Tabelle oder Tabellen in der Datenbank genutzt werden sollen. Ist dieses Attribut nicht gesetzt, wird
       per default die Einstellung <i>history</i> verwendet. <br><br>

       Bedeutung der Einstellungen sind: <br><br>

       <ul>
       <table>
       <colgroup> <col width=10%> <col width=90%> </colgroup>
       <tr><td> <b>Current</b>            </td><td>Events werden nur in die current-Tabelle geloggt.
                                                   Die current-Tabelle wird bei der SVG-Erstellung ausgewertet.  </td></tr>
       <tr><td> <b>History</b>            </td><td>Events werden nur in die history-Tabelle geloggt. Es wird keine DropDown-Liste mit Vorschlägen bei der SVG-Erstellung
                                                   erzeugt.   </td></tr>
       <tr><td> <b>Current/History</b>    </td><td>Events werden sowohl in die current- also auch in die hitory Tabelle geloggt.
                                                   Die current-Tabelle wird bei der SVG-Erstellung ausgewertet.</td></tr>
       <tr><td> <b>SampleFill/History</b> </td><td>Events werden nur in die history-Tabelle geloggt. Die current-Tabelle wird bei der SVG-Erstellung ausgewertet und
                                                   kann zur Erzeugung einer DropDown-Liste mittels einem
                                                   <a href="#DbRep">DbRep-Device</a> <br> "set &lt;DbRep-Name&gt; tableCurrentFillup" mit
                                                   einem einstellbaren Extract der history-Tabelle gefüllt werden (advanced Feature).  </td></tr>
       </table>
       </ul>
       <br>
       <br>

       <b>Hinweis:</b> <br>
       Die Current-Tabelle muß genutzt werden um eine Device:Reading-DropDownliste zur Erstellung eines
       SVG-Plots zu erhalten.   <br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-DbLogSelectionMode"></a>
    <li><b>DbLogSelectionMode</b>
    <ul>
      <code>
      attr &lt;device&gt; DbLogSelectionMode [Exclude|Include|Exclude/Include]
      </code><br><br>

      Dieses für DbLog-Devices spezifische Attribut beeinflußt, wie die Device-spezifischen Attribute
      <a href="#DbLog-attr-DbLogExclude">DbLogExclude</a> und <a href="#DbLog-attr-DbLogInclude">DbLogInclude</a>
      ausgewertet werden. DbLogExclude und DbLogInclude werden in den Quellen-Devices gesetzt. <br>
      Ist das Attribut DbLogSelectionMode nicht gesetzt, ist "Exclude" der Default.
      <br><br>

      <ul>
        <li><b>Exclude:</b> Readings werden geloggt wenn sie auf den im DEF angegebenen Regex matchen. Ausgeschlossen werden
                            die Readings, die auf den Regex im Attribut DbLogExclude matchen. <br>
                            Das Attribut DbLogInclude wird in diesem Fall nicht berücksichtigt.
                            </li>
                            <br>
        <li><b>Include:</b> Es werden nur Readings geloggt welche über den Regex im Attribut DbLogInclude
                            eingeschlossen werden. <br>
                            Das Attribut DbLogExclude wird in diesem Fall ebenso wenig berücksichtigt wie der Regex im DEF.
                            </li>
                            <br>
        <li><b>Exclude/Include:</b> Funktioniert im Wesentlichen wie "Exclude", nur dass sowohl das Attribut DbLogExclude
                                    als auch das Attribut DbLogInclude geprüft wird.
                                    Readings die durch DbLogExclude zwar ausgeschlossen wurden, mit DbLogInclude aber
                                    wiederum eingeschlossen werden, werden somit dennoch beim Logging berücksichtigt.
                                    </li>
      </ul>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-DbLogInclude"></a>
    <li><b>DbLogInclude</b>
    <ul>
      <code>
      attr <device> DbLogInclude Regex[:MinInterval][:force],[Regex[:MinInterval][:force]], ...
      </code><br><br>

      Mit dem Attribut DbLogInclude werden die Readings definiert, die in der Datenbank gespeichert werden sollen. <br>
      Die Definition der zu speichernden Readings erfolgt über einen regulären Ausdruck und alle Readings, die mit dem
      regulären Ausdruck matchen, werden in der Datenbank gespeichert. <br>

      Der optionale Zusatz &lt;MinInterval&gt; gibt an, dass ein Wert dann gespeichert wird wenn mindestens &lt;MinInterval&gt;
      Sekunden seit der letzten Speicherung vergangen sind. <br>

      Unabhängig vom Ablauf des Intervalls wird das Reading gespeichert wenn sich der Wert des Readings verändert hat. <br>
      Mit dem optionalen Modifier "force" kann erzwungen werden das angegebene Intervall &lt;MinInterval&gt; einzuhalten auch
      wenn sich der Wert des Readings seit der letzten Speicherung verändert hat.
      <br><br>

      <ul>
      <pre>
        | <b>Modifier</b> |         <b>innerhalb Intervall</b>          | <b>außerhalb Intervall</b> |
        |          | Wert gleich        | Wert geändert   |                     |
        |----------+--------------------+-----------------+---------------------|
        | &lt;none&gt;   | ignorieren         | speichern       | speichern           |
        | force    | ignorieren         | ignorieren      | speichern           |
      </pre>
      </ul>

      <br>
      <b>Hinweise: </b> <br>
      Das Attribut DbLogInclude wird in allen Devices propagiert wenn DbLog verwendet wird. <br>
      Das Attribut <a href="#DbLog-attr-DbLogSelectionMode">DbLogSelectionMode</a> muss entsprechend gesetzt sein
      um DbLogInclude zu aktivieren. <br>
      Mit dem Attribut <a href="#DbLog-attr-defaultMinInterval">defaultMinInterval</a> kann ein Default für
      &lt;MinInterval&gt; vorgegeben werden.
      <br><br>

      <b>Beispiele: </b> <br>
      <code>attr MyDevice1 DbLogInclude .*</code> <br>
      <code>attr MyDevice2 DbLogInclude state,(floorplantext|MyUserReading):300,battery:3600</code> <br>
      <code>attr MyDevice2 DbLogInclude state,(floorplantext|MyUserReading):300:force,battery:3600:force</code>
    </ul>

  </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-DbLogExclude"></a>
    <li><b>DbLogExclude</b>
    <ul>
      <code>
      attr &lt;device&gt; DbLogExclude regex[:MinInterval][:force],[regex[:MinInterval][:force]] ...
      </code><br><br>

      Mit dem Attribut DbLogExclude werden die Readings definiert, die <b>nicht</b> in der Datenbank gespeichert werden
	  sollen. <br>
      Die Definition der auszuschließenden Readings erfolgt über einen regulären Ausdruck und alle Readings, die mit dem
      regulären Ausdruck matchen, werden vom Logging in die Datenbank ausgeschlossen. <br>

      Readings, die nicht über den Regex ausgeschlossen wurden, werden in der Datenbank geloggt. Das Verhalten der
	  Speicherung wird mit den nachfolgenden optionalen Angaben gesteuert. <br>
      Der optionale Zusatz &lt;MinInterval&gt; gibt an, dass ein Wert dann gespeichert wird wenn mindestens &lt;MinInterval&gt;
      Sekunden seit der letzten Speicherung vergangen sind. <br>

      Unabhängig vom Ablauf des Intervalls wird das Reading gespeichert wenn sich der Wert des Readings verändert hat. <br>
      Mit dem optionalen Modifier "force" kann erzwungen werden das angegebene Intervall &lt;MinInterval&gt; einzuhalten auch
      wenn sich der Wert des Readings seit der letzten Speicherung verändert hat.
      <br><br>

      <ul>
      <pre>
        | <b>Modifier</b> |         <b>innerhalb Intervall</b>          | <b>außerhalb Intervall</b> |
        |          | Wert gleich        | Wert geändert   |                     |
        |----------+--------------------+-----------------+---------------------|
        | &lt;none&gt;   | ignorieren         | speichern       | speichern           |
        | force    | ignorieren         | ignorieren      | speichern           |
      </pre>
      </ul>

      <br>
      <b>Hinweise: </b> <br>
      Das Attribut DbLogExclude wird in allen Devices propagiert wenn DbLog verwendet wird. <br>
      Das Attribut <a href="#DbLog-attr-DbLogSelectionMode">DbLogSelectionMode</a> kann entsprechend gesetzt werden
      um DbLogExclude zu deaktivieren. <br>
      Mit dem Attribut <a href="#DbLog-attr-defaultMinInterval">defaultMinInterval</a> kann ein Default für
	  &lt;MinInterval&gt; vorgegeben werden.
      <br><br>

      <b>Beispiel</b> <br>
      <code>attr MyDevice1 DbLogExclude .*</code> <br>
      <code>attr MyDevice2 DbLogExclude state,(floorplantext|MyUserReading):300,battery:3600</code> <br>
      <code>attr MyDevice2 DbLogExclude state,(floorplantext|MyUserReading):300:force,battery:3600:force</code>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-DbLogValueFn"></a>
     <li><b>DbLogValueFn</b>
     <ul>
       <code>
       attr &lt;device&gt; DbLogValueFn {}
       </code><br><br>

       Wird DbLog genutzt, wird in allen Devices das Attribut <i>DbLogValueFn</i> propagiert.
       Es kann über einen Perl-Ausdruck auf die Variablen $TIMESTAMP, $READING, $VALUE (Wert des Readings) und
       $UNIT (Einheit des Readingswert) zugegriffen werden und diese verändern, d.h. die veränderten Werte werden geloggt. <br>
       Außerdem hat man Lesezugriff auf $DEVICE (den Namen des Quellgeräts), $EVENT, $LASTTIMESTAMP und $LASTVALUE
       zur Bewertung in Ihrem Ausdruck. <br>
       Die Variablen $LASTTIMESTAMP und $LASTVALUE enthalten Zeit und Wert des zuletzt protokollierten Datensatzes von $DEVICE / $READING. <br>
       Soll $TIMESTAMP verändert werden, muss die Form "yyyy-mm-dd hh:mm:ss" eingehalten werden, ansonsten wird der
       geänderte $timestamp nicht übernommen.
       Zusätzlich kann durch Setzen der Variable "$IGNORE=1" der Datensatz vom Logging ausgeschlossen werden. <br>
       Die devicespezifische Funktion in "DbLogValueFn" wird vor der eventuell im DbLog-Device vorhandenen Funktion im Attribut
       "valueFn" auf den Datensatz angewendet.
       <br><br>

       <b>Beispiel</b> <br>
       <pre>
attr SMA_Energymeter DbLogValueFn
{
  if ($READING eq "Bezug_WirkP_Kosten_Diff"){
    $UNIT="Diff-W";
  }
  if ($READING =~ /Einspeisung_Wirkleistung_Zaehler/ && $VALUE < 2){
    $IGNORE=1;
  }
}
       </pre>
     </ul>
     </li>
  </ul>

  <ul>
    <a id="DbLog-attr-dbSchema"></a>
    <li><b>dbSchema</b>
    <ul>
      <code>
      attr &lt;device&gt; dbSchema &lt;schema&gt;
      </code><br><br>

      Dieses Attribut ist setzbar für die Datenbanken MySQL/MariaDB und PostgreSQL. Die Tabellennamen (current/history) werden
      durch das angegebene Datenbankschema ergänzt. Das Attribut ist ein advanced Feature und nomalerweise nicht nötig zu setzen.
      <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-defaultMinInterval"></a>
    <li><b>defaultMinInterval</b>
    <ul>
      <code>
      attr &lt;device&gt; defaultMinInterval &lt;devspec&gt;::&lt;MinInterval&gt;[::force],[&lt;devspec&gt;::&lt;MinInterval&gt;[::force]] ...
      </code><br><br>

      Mit diesem Attribut wird ein Standard Minimum Intervall für <a href="http://fhem.de/commandref_DE.html#devspec">devspec</a> festgelegt.
      Ist defaultMinInterval angegeben, wird der Logeintrag nicht geloggt, wenn das Intervall noch nicht erreicht <b>und</b> der
      Wert des Readings sich <b>nicht</b> verändert hat. <br>
      Ist der optionale Parameter "force" hinzugefügt, wird der Logeintrag auch dann nicht geloggt, wenn sich der
      Wert des Readings verändert hat. <br>
      Eventuell im Quelldevice angegebene Spezifikationen DbLogExclude / DbLogInclude haben Vorrag und werden durch
      defaultMinInterval <b>nicht</b> überschrieben. <br>
      Die Eingabe kann mehrzeilig erfolgen. <br><br>

      <b>Beispiele</b> <br>
      <code>attr dblog defaultMinInterval .*::120::force </code> <br>
      # Events aller Devices werden nur geloggt, wenn 120 Sekunden zum letzten Logeintrag vergangen sind ist (Reading spezifisch) unabhängig von einer eventuellen Änderung des Wertes. <br>
      <code>attr dblog defaultMinInterval (Weather|SMA)::300 </code> <br>
      # Events der Devices "Weather" und "SMA" werden nur geloggt wenn 300 Sekunden zum letzten Logeintrag vergangen sind (Reading spezifisch) und sich der Wert nicht geändert hat. <br>
      <code>attr dblog defaultMinInterval TYPE=CUL_HM::600::force </code> <br>
      # Events aller Devices des Typs "CUL_HM" werden nur geloggt, wenn 600 Sekunden zum letzten Logeintrag vergangen sind (Reading spezifisch) unabhängig von einer eventuellen Änderung des Wertes.
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-disable"></a>
    <li><b>disable</b>
    <ul>
      <code>
      attr &lt;device&gt; disable [0|1]
      </code><br><br>

      Das DbLog Device wird disabled (1) bzw. enabled (0).
      <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-excludeDevs"></a>
     <li><b>excludeDevs</b>
     <ul>
       <code>
       attr &lt;device&gt; excludeDevs &lt;devspec1&gt;[#Reading],&lt;devspec2&gt;[#Reading],&lt;devspec...&gt;
       </code><br><br>

       Die Device/Reading-Kombinationen "devspec1#Reading", "devspec2#Reading" bis "devspec..." werden vom Logging in die
       Datenbank global ausgeschlossen. <br>
       Die Angabe eines auszuschließenden Readings ist optional. <br>
       Somit können Device/Readings explizit bzw. konsequent vom Logging ausgeschlossen werden ohne Berücksichtigung anderer
       Excludes oder Includes (z.B. im DEF).
       Die auszuschließenden Devices können als <a href="#devspec">Geräte-Spezifikation</a> angegeben werden.
       Für weitere Details bezüglich devspec siehe <a href="#devspec">Geräte-Spezifikation</a>.  <br><br>

      <b>Beispiel</b> <br>
      <code>
      attr &lt;device&gt; excludeDevs global,Log.*,Cam.*,TYPE=DbLog
      </code><br>
      # Es werden die Devices global bzw. Devices beginnend mit "Log" oder "Cam" bzw. Devices vom Typ "DbLog" vom Logging ausgeschlossen. <br>
      <code>
      attr &lt;device&gt; excludeDevs .*#.*Wirkleistung.*
      </code><br>
      # Es werden alle Device/Reading-Kombinationen mit "Wirkleistung" im Reading vom Logging ausgeschlossen. <br>
      <code>
      attr &lt;device&gt; excludeDevs SMA_Energymeter#Bezug_WirkP_Zaehler_Diff
      </code><br>
      # Es wird der Event mit Device "SMA_Energymeter" und Reading "Bezug_WirkP_Zaehler_Diff" vom Logging ausgeschlossen. <br>

      </ul>
      </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-expimpdir"></a>
     <li><b>expimpdir</b>
     <ul>
       <code>
       attr &lt;device&gt; expimpdir &lt;directory&gt;
       </code><br><br>

       In diesem Verzeichnis wird das Cachefile beim Export angelegt bzw. beim Import gesucht. Siehe set-Kommandos
       <a href="#DbLog-set-exportCache">exportCache</a> bzw. <a href="#DbLog-set-importCachefile">importCachefile</a>.
       Das Default-Verzeichnis ist "(global->modpath)/log/".
       Das im Attribut angegebene Verzeichnis muss vorhanden und beschreibbar sein. <br><br>

      <b>Beispiel</b> <br>
      <code>
      attr &lt;device&gt; expimpdir /opt/fhem/cache/
      </code><br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-exportCacheAppend"></a>
     <li><b>exportCacheAppend</b>
     <ul>
       <code>
       attr &lt;device&gt; exportCacheAppend [1|0]
       </code><br><br>

       Wenn gesetzt, wird beim Export des Cache ("set &lt;device&gt; exportCache") der Cacheinhalt an das neueste bereits vorhandene
       Exportfile angehängt. Ist noch kein Exportfile vorhanden, wird es neu angelegt. <br>
       Ist das Attribut nicht gesetzt, wird bei jedem Exportvorgang ein neues Exportfile angelegt. (default)<br/>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-noNotifyDev"></a>
     <li><b>noNotifyDev</b>
     <ul>
       <code>
       attr &lt;device&gt; noNotifyDev [1|0]
       </code><br><br>

       Erzwingt dass NOTIFYDEV nicht gesetzt und somit nicht verwendet wird.<br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-noSupportPK"></a>
     <li><b>noSupportPK</b>
     <ul>
       <code>
       attr &lt;device&gt; noSupportPK [1|0]
       </code><br><br>

       Deaktiviert die programmtechnische Unterstützung eines gesetzten Primary Key durch das Modul.<br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-showproctime"></a>
    <li><b>showproctime</b>
    <ul>
      <code>attr &lt;device&gt; showproctime [1|0]
      </code><br><br>

      Wenn gesetzt, zeigt das Reading "sql_processing_time" die benötigte Abarbeitungszeit (in Sekunden) für die SQL-Ausführung der
      durchgeführten Funktion. Dabei wird nicht ein einzelnes SQL-Statement, sondern die Summe aller notwendigen SQL-Abfragen innerhalb der
      jeweiligen Funktion betrachtet. Das Reading "background_processing_time" zeigt die im Kindprozess BlockingCall verbrauchte Zeit.<br>

    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-showNotifyTime"></a>
    <li><b>showNotifyTime</b>
    <ul>
      <code>attr &lt;device&gt; showNotifyTime [1|0]
      </code><br><br>

      Wenn gesetzt, zeigt das Reading "notify_processing_time" die benötigte Abarbeitungszeit (in Sekunden) für die
      Abarbeitung der DbLog Notify-Funktion. Das Attribut ist für Performance Analysen geeignet und hilft auch die Unterschiede
      im Zeitbedarf bei der Umschaltung des synchronen in den asynchronen Modus festzustellen. <br>

    </ul>
    </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-SQLiteCacheSize"></a>
     <li><b>SQLiteCacheSize</b>
     <ul>
       <code>
       attr &lt;device&gt; SQLiteCacheSize &lt;Anzahl Memory Pages für Cache&gt;
       </code><br>

       Standardmäßig werden ca. 4MB RAM für Caching verwendet (page_size=1024bytes, cache_size=4000).<br>
       Bei Embedded Devices mit wenig RAM genügen auch 1000 Pages - zu Lasten der Performance. <br>
       (default: 4000)
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-SQLiteJournalMode"></a>
     <li><b>SQLiteJournalMode</b>
     <ul>
       <code>
       attr &lt;device&gt; SQLiteJournalMode [WAL|off]
       </code><br><br>

       Moderne SQLite Datenbanken werden mit einem Write-Ahead-Log (<b>WAL</b>) geöffnet, was optimale Datenintegrität
       und gute Performance gewährleistet.<br>
       Allerdings benötigt WAL zusätzlich ungefähr den gleichen Festplattenplatz wie die eigentliche Datenbank. Bei knappem
       Festplattenplatz (z.B. eine RAM Disk in Embedded Devices) kann das Journal deaktiviert werden (<b>off</b>).
       Im Falle eines Datenfehlers kann die Datenbank aber wahrscheinlich nicht repariert werden, und muss neu erstellt
       werden! <br>
       (default: WAL)
     </ul>
     </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-syncEvents"></a>
    <li><b>syncEvents</b>
    <ul>
      <code>attr &lt;device&gt; syncEvents [1|0]
      </code><br><br>

      es werden Events für Reading NextSync erzeugt. <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-syncInterval"></a>
    <li><b>syncInterval</b>
    <ul>
      <code>attr &lt;device&gt; syncInterval &lt;n&gt;
      </code><br><br>

      Wenn DbLog im asynchronen Modus betrieben wird (Attribut asyncMode=1), wird mit diesem Attribut das Intervall in Sekunden zur Speicherung
      der im Speicher gecachten Events in die Datenbank eingestellt. Der Defaultwert ist 30 Sekunden. <br>

    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-suppressAddLogV3"></a>
    <li><b>suppressAddLogV3</b>
    <ul>
      <code>attr &lt;device&gt; suppressAddLogV3 [1|0]
      </code><br><br>

      Wenn gesetzt werden verbose 3 Logeinträge durch die addLog-Funktion unterdrückt.  <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-suppressUndef"></a>
    <li><b>suppressUndef</b>
    <ul>
      <code>attr &lt;device&gt; suppressUndef <n>
      </code><br><br>

      Unterdrückt alle undef Werte die durch eine Get-Anfrage, z.B. Plot, aus der Datenbank selektiert werden.

    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-timeout"></a>
    <li><b>timeout</b>
    <ul>
      <code>
      attr &lt;device&gt; timeout &lt;n&gt;
      </code><br><br>

      Setzt den Timeout-Wert für den Schreibzyklus in die Datenbank im asynchronen Modus (default 86400s). <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-traceFlag"></a>
    <li><b>traceFlag</b>
    <ul>
      <code>
      attr &lt;device&gt; traceFlag &lt;ALL|SQL|CON|ENC|DBD|TXN&gt;
      </code><br><br>

      Bestimmt das Tracing von bestimmten Aktivitäten innerhalb des Datenbankinterfaces und Treibers. Das Attribut ist nur
      für den Fehler- bzw. Supportfall gedacht. <br><br>

       <ul>
       <table>
       <colgroup> <col width=10%> <col width=90%> </colgroup>
       <tr><td> <b>ALL</b>            </td><td>schaltet alle DBI- und Treiberflags an.  </td></tr>
       <tr><td> <b>SQL</b>            </td><td>verfolgt die SQL Statement Ausführung. (Default) </td></tr>
       <tr><td> <b>CON</b>            </td><td>verfolgt den Verbindungsprozess.  </td></tr>
       <tr><td> <b>ENC</b>            </td><td>verfolgt die Kodierung (Unicode Übersetzung etc).  </td></tr>
       <tr><td> <b>DBD</b>            </td><td>verfolgt nur DBD Nachrichten.  </td></tr>
       <tr><td> <b>TXN</b>            </td><td>verfolgt Transaktionen.  </td></tr>

       </table>
       </ul>
       <br>

    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-traceHandles"></a>
    <li><b>traceHandles</b>
    <ul>
      <code>attr &lt;device&gt; traceHandles &lt;n&gt;
      </code><br><br>

      Wenn gesetzt, werden alle &lt;n&gt; Sekunden die systemweit vorhandenen Datenbank-Handles im Logfile ausgegeben.
      Dieses Attribut ist nur für Supportzwecke relevant. (Default: 0 = ausgeschaltet) <br>

    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-traceLevel"></a>
    <li><b>traceLevel</b>
    <ul>
      <code>
      attr &lt;device&gt; traceLevel &lt;0|1|2|3|4|5|6|7&gt;
      </code><br><br>

      Schaltet die Trace-Funktion des Moduls ein. <br>
      <b>Achtung !</b> Das Attribut ist nur für den Fehler- bzw. Supportfall gedacht. Es werden <b>sehr viele Einträge</b> in
      das FHEM Logfile vorgenommen ! <br><br>

       <ul>
       <table>
       <colgroup> <col width=5%> <col width=95%> </colgroup>
       <tr><td> <b>0</b>            </td><td>Tracing ist disabled. (Default)  </td></tr>
       <tr><td> <b>1</b>            </td><td>Tracing von DBI Top-Level Methoden mit deren Ergebnissen und Fehlern </td></tr>
       <tr><td> <b>2</b>            </td><td>Wie oben. Zusätzlich Top-Level Methodeneintäge mit Parametern.  </td></tr>
       <tr><td> <b>3</b>            </td><td>Wie oben. Zusätzliche werden einige High-Level Informationen des Treibers und
                                             einige interne Informationen des DBI hinzugefügt.  </td></tr>
       <tr><td> <b>4</b>            </td><td>Wie oben. Zusätzlich werden mehr detaillierte Informationen des Treibers
                                             eingefügt. </td></tr>
       <tr><td> <b>5-7</b>          </td><td>Wie oben, aber mit mehr und mehr internen Informationen.  </td></tr>

       </table>
       </ul>
       <br>

    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-useCharfilter"></a>
    <li><b>useCharfilter</b>
    <ul>
      <code>
      attr &lt;device&gt; useCharfilter [0|1] <n>
      </code><br><br>

      wenn gesetzt, werden nur ASCII Zeichen von 32 bis 126 im Event akzeptiert. (default: 0) <br>
      Das sind die Zeichen " A-Za-z0-9!"#$%&'()*+,-.\/:;<=>?@[\\]^_`{|}~". <br>
      Umlaute und "€" werden umgesetzt (z.B. ä nach ae, € nach EUR).  <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-valueFn"></a>
     <li><b>valueFn</b>
     <ul>
       <code>
       attr &lt;device&gt; valueFn {}
       </code><br><br>

       Es kann über einen Perl-Ausdruck auf die Variablen $TIMESTAMP, $DEVICE, $DEVICETYPE, $READING, $VALUE (Wert des Readings) und
       $UNIT (Einheit des Readingswert) zugegriffen werden und diese verändern, d.h. die veränderten Werte werden geloggt. <br>
       Außerdem hat man Lesezugriff auf $EVENT, $LASTTIMESTAMP und $LASTVALUE zur Bewertung im Ausdruck. <br>
       Die Variablen $LASTTIMESTAMP und $LASTVALUE enthalten Zeit und Wert des zuletzt protokollierten Datensatzes von $DEVICE / $READING. <br>
       Soll $TIMESTAMP verändert werden, muss die Form "yyyy-mm-dd hh:mm:ss" eingehalten werden. Anderenfalls wird der
       geänderte $timestamp nicht übernommen.
       Zusätzlich kann durch Setzen der Variable "$IGNORE=1" ein Datensatz vom Logging ausgeschlossen werden. <br><br>

      <b>Beispiele</b> <br>
      <code>
      attr &lt;device&gt; valueFn {if ($DEVICE eq "living_Clima" && $VALUE eq "off" ){$VALUE=0;} elsif ($DEVICE eq "e-power"){$VALUE= sprintf "%.1f", $VALUE;}}
      </code> <br>
      # ändert den Reading-Wert des Gerätes "living_Clima" von "off" zu "0" und rundet den Wert vom Gerät "e-power" <br><br>
      <code>
      attr &lt;device&gt; valueFn {if ($DEVICE eq "SMA_Energymeter" && $READING eq "state"){$IGNORE=1;}}
      </code><br>
      # der Datensatz wird nicht geloggt wenn Device = "SMA_Energymeter" und das Reading = "state" ist  <br><br>
      <code>
      attr &lt;device&gt; valueFn {if ($DEVICE eq "Dum.Energy" && $READING eq "TotalConsumption"){$UNIT="W";}}
      </code><br>
      # setzt die Einheit des Devices "Dum.Energy" auf "W" wenn das Reading = "TotalConsumption" ist <br><br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-verbose4Devs"></a>
     <li><b>verbose4Devs</b>
     <ul>
       <code>
       attr &lt;device&gt; verbose4Devs &lt;device1&gt;,&lt;device2&gt;,&lt;device..&gt;
       </code><br><br>

       Mit verbose Level 4 werden nur Ausgaben bezüglich der in diesem Attribut aufgeführten Devices im Logfile protokolliert. Ohne dieses
       Attribut werden mit verbose 4 Ausgaben aller relevanten Devices im Logfile protokolliert.
       Die angegebenen Devices werden als Regex ausgewertet. <br><br>

      <b>Beispiel</b> <br>
      <code>
      attr &lt;device&gt; verbose4Devs sys.*,.*5000.*,Cam.*,global
      </code><br>
      # Es werden Devices beginnend mit "sys", "Cam" bzw. Devices die "5000" enthalten und das Device "global" protokolliert falls verbose=4
      eingestellt ist. <br>
     </ul>
     </li>
  </ul>
  <br>

</ul>

=end html_DE

=for :application/json;q=META.json 93_DbLog.pm
{
  "abstract": "logs events into a database",
  "x_lang": {
    "de": {
      "abstract": "loggt Events in eine Datenbank"
    }
  },
  "keywords": [
    "dblog",
    "database",
    "events",
    "logging",
    "asynchronous"
  ],
  "version": "v1.1.1",
  "release_status": "stable",
  "author": [
    "Heiko Maaz <heiko.maaz@t-online.de>"
  ],
  "x_fhem_maintainer": [
    "DS_Starter"
  ],
  "x_fhem_maintainer_github": [
    "nasseeder1"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.014,
        "Data::Dumper": 0,
        "DBI": 0,
        "Blocking": 0,
        "Time::HiRes": 0,
        "Time::Local": 0,
        "HttpUtils": 0,
        "Encode": 0,
        "SubProcess": 0,
        "JSON": 0
      },
      "recommends": {
        "FHEM::Meta": 0,
        "DateTime": 0,
        "DateTime::Format::Strptime": 0,
        "FHEM::Utility::CTZ": 0
      },
      "suggests": {
        "DBD::Pg" :0,
        "DBD::mysql" :0,
        "DBD::SQLite" :0
      }
    }
  },
  "resources": {
    "x_wiki": {
      "web": "https://wiki.fhem.de/wiki/DbLog",
      "title": "DbLog"
    },
    "repository": {
      "x_dev": {
        "type": "svn",
        "url": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter",
        "web": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter/93_DbLog.pm",
        "x_branch": "dev",
        "x_filepath": "fhem/contrib/",
        "x_raw": "https://svn.fhem.de/fhem/trunk/fhem/contrib/DS_Starter/93_DbLog.pm"
      }
    }
  }
}
=end :application/json;q=META.json

=cut


