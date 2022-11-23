#########################################################################
# $Id$
# fhem Modul für Viessmann API. Based on investigation of "thetrueavatar"
# (https://github.com/thetrueavatar/Viessmann-Api)
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
##############################################################################
#   Changelog:
#
#   2018-11-24		initial version
#	 2018-12-11		non-blocking
#                 Reading "status" in "state" umbenannt
#   2018-12-23    Neue Werte in der API werden unter ihrem JSON Name als Reading eingetragen
#                 Neue Readings:
#  					heating.boiler.sensors.temperature.commonSupply.status error
#  					heating.boiler.temperature.value	                      48.1
#  					heating.burner.modulation.value                        11
#  					heating.burner.statistics.hours                        933.336666666667
#  					heating.burner.statistics.starts                       2717
#  					heating.circuits.0.circulation.pump.status             on
#  					heating.dhw.charging.active                            0
#  					heating.dhw.pumps.circulation.schedule.active          1
#  					heating.dhw.pumps.circulation.schedule.entries         sun mode:on end:22:30 start:04:30 position:0, fri end:22:30 mode:on position:0 start:04:30,
#  					                                                       mon mode:on end:22:30 start:04:30 position:0,
#  					                                                       wed start:04:30 position:0 end:22:30 mode:on, thu mode:on end:22:30 position:0 start:04:30, sat end:22:30 mode:on position:0 start:04:30,
#  					                                                       tue position:0 start:04:30 end:22:30 mode:on,
#  					heating.dhw.pumps.circulation.status                   on
#  					heating.dhw.pumps.primary.status                       off
#  					heating.dhw.sensors.temperature.outlet.status          error
#  					heating.dhw.temperature.main.value                     53
#  2018-12-30     initial offical release
#                 remove special characters from readings
#                 some internal improvements suggested by CoolTux
#  2019-01-01     "disabled" implemented
#                 "set update implemented
#						renamed "WW-onTimeCharge_aktiv" into "WW-einmaliges_Aufladen_aktiv"
#						Attribute vitoconnect_raw_readings:0,1 " and  ."vitoconnect_actions_active:0,1 " implemented
#						"set clearReadings" implemented
#  2019-01-05		Passwort wird im KeyValue gespeichert statt im Klartext
#                 Action "oneTimeCharge" implemented
#  2019-01-14		installation, code and gw in den Internals unsichtbar gemacht
#                 Reading "counter" entfernt (ist weiterhin in Internals sichtbar)
#						Reading WW-einmaliges_Aufladen_active umbenannt in WW-einmaliges_Aufladen
#                 Befehle zum setzen von
#                 		HK1-Betriebsart
#                 		HK2-Betriebsart
#                 		HK1-Solltemperatur_normal
#                 		HK2-Solltemperatur_normal
#                 		HK1-Solltemperatur_reduziert
#                 		HK2-Solltemperatur_reduziert
#                 		WW-einmaliges_Aufladen
#                 Bedienfehler (z.B. Ausführung einer Befehls für HK2, wenn die Hezung nur einen Heizkreis hat)
#						führen zu einem "Bad Gateway" Fehlermeldung in Logfile
#						Achtung: Keine Prüfung ob Befehle sinnvoll und oder erlaubt sind! Nutzung auf eigene Gefahr!
# 2019-01-15	   Fehler bei der Befehlsausführung gefixt
# 2019-01-22      Klartext für Readings für HK3 und heating.dhw.charging.level.* hinzugefügt
#						set's für HK2 implementiert
#					   set für Slope und Shift implementiert
#						set WW-Haupttemperatur und WW-Solltemperatur implementiert
#						set HK1-Solltemperatur_comfort_aktiv HK1-Solltemperatur_comfort implementiert
#						set  HK1-Solltemperatur_eco implementiert (set HK1-Solltemperatur_eco_aktiv scheint es nicht zu geben?!)
#						vor einem set vitoconnect update den alten Timer löschen
#						set vitoconnect logResponseOnce implementiert (eventuell werden zusätzliche perl Pakete benötigt?)
# 2019-01-26		Fehler, dass HK3 Readings auf HK2 gemappt wurden gefixt
# 2019-02-17		Readings für den Stromverbrauch (heating.power.consumption.*) und
#						  Raumtemperatur (heating.circuits.?.sensors.temperature.room.value) ergänzt
#						set-Befehle für HKs werden nur noch angezeigt, wenn der HK auch aktiv ist
#						Wiki aktualisiert
# 2019-02-27		stacktrace-Fehler (hoffentlich) behoben
#						Betriebsarten "heating" und "active" ergänzt
# 2019-03-02		Readings für heating.boiler.sensors.temperature.commonSupply.value und
#							heating.circuits.1.operating.modes.heating.active hinzugefügt
#						Typo fixed ("Brenner_Be-t-riebsstunden")
# 2019-03-29		neue Readings:
#							heating.circuits.1.operating.modes.dhwAndHeatingCooling.active 1
#							heating.circuits.1.operating.modes.normalStandby.active 0
#							heating.circuits.1.operating.programs.fixed.active 0
#							heating.compressor.active 0
#							heating.dhw.temperature.hysteresis.value 5
#							heating.dhw.temperature.temp2.value 60
#						Passwort wird bei "define" nur noch gesetzt, wenn noch kein Passwort gespeichert war
#                 Attribut "model" implementiert
# 2019-04-26		neue Readings für
#						heating.gas.consumption.dhw.unit kilowattHour
#						heating.gas.consumption.heating.unit kilowattHour
#						heating.power.consumption.unit kilowattHour
#						Typo in WW-Zirkulationspumpe_Zeitsteuerung_aktiv fixt
# 2019-06-01		neue Readings für
#          			    heating.solar.power.production.day	3.984,3.797,5.8,5.5,6.771,5.77,5.441,9.477
#          			    heating.solar.power.production.month
#          			    heating.solar.power.production.unit	kilowattHour
#          			    heating.solar.power.production.week
#          			    heating.solar.power.production.year
#                     heating.circuits.X.name (wird im Moment noch nicht von der API gefüllt!)
#                 Format der "Schedule" Readings in JSON geändert
#						das Format von HKx-Urlaub_Start und _Ende ist jetzt YYYY-MM-TT.
#                 	Wenn noch kein Urlaub aktiviert wurde, wird bei
#                    HKx-Urlaub_Start das Datum für _Ende auf den Folgetag gesetzt
#                    Dafür werden die Perl Module DateTime, Time:Piece und Time::Seconds
#                    benötigt (installieren mit apt install libdatetime-perl!)
#
# 2019-08-11		Dokumentation aktualisiert
#						Das Reading 'stat' zeigt jetzt den "aggregatedStatus" an, der von der API geliefert wird
#									Bsp: "Offline", "WorksProperly"
#                 Readings werden nur noch aktualisiert (und ein entsprechendes Event erzeugt),
#                          wenn sich ihr Wert geändert hat. "state" wird immer aktualisiert.
#						Reading für Solarunterstützung hinzugefügt:
#                          "heating.solar.active" 											=> "Solar_aktiv",
#                          "heating.solar.pumps.circuit.status" 						=> "Solar_Pumpe_Status",
#                          "heating.solar.rechargeSuppression.status" 				=> "Solar_Aufladeunterdrueckung_Status",
#                          "heating.solar.sensors.power.status" 						=> "Solar_Sensor_Power_Status",
#                          "heating.solar.sensors.power.value" 						=> "Solar_Sensor_Power",
#                          "heating.solar.sensors.temperature.collector.status" 	=> "Solar_Sensor_Temperatur_Kollektor_Status",
#                          "heating.solar.sensors.temperature.collector.value" 	=> "Solar_Sensor_Temperatur_Kollektor",
#                          "heating.solar.sensors.temperature.dhw.status" 			=> "Solar_Sensor_Temperatur_WW_Status",
#                          "heating.solar.sensors.temperature.dhw.value" 			=> "Solar_Sensor_Temperatur_WW",
#                          "heating.solar.statistics.hours" 						   => "Solar_Sensor_Statistik_Stunden"
#						ErrorListChanges (Fehlereintraege_Historie und Fehlereintraege_aktive) werden jetzt im JSON
#                          JSON Format ausgegeben (z.B.: "{"new":[],"current":[],"gone":[]}")
#
# 2019-09-07		Readings werden wieder erzeugt auch wenn sich der Wert nicht ändert
#
# 2019-11-23		Readings für "heating.power.consumption.total.*" hinzugefügt. Scheint identisch mit "heating.power.consumption.*"
#					Behoben: Readings wurden nicht mehr aktualisiert, wenn in getResourceCallback die Resource nicht als JSON interpretiert werden konnte (Forum: #390)
#					Behoben: vitoconnect bringt FHEM zum Absturz in Zeile 1376 (Forum: #391)
#					Überwachung der Aktualität: Zeitpunkt des letzten Updates wird in State angezeigt (Forum #397)
#
# 2019-12-25		heating.solar.power.cumulativeProduced.value, heating.circuits.X.geofencing.active, heating.circuits.X.geofencing.status hinzugefügt
#                   Behoben: Readings wurden nicht mehr aktualisiert, wenn Resource an weiteren Stellen nicht als JSON interpretiert werden konnte(Forum: #390)
#
# 2020-03-02      Bei Aktionen wird nicht mehr auf defined($data) sondern auf ne "" getestet.
# 2020-04-05      s.o. 2. Versuch
#
# 2020-04-09      my $dir = path(AttrVal("global","logdir","log"));
#
# 2020-04-17      "Viessmann" Tippfehler gefixt
#                 Prototypen und "undef"s entfernt
#
# 2020-04-22      Reading heating.boiler.temperature.unit heating.operating.programs.holiday.active
#                            heating.operating.programs.holiday.end heating.operating.programs.holiday.start
#                 set Befehle hinzugefügt: Urlaub_Start, Urlaub_Ende, Urlaub_unschedule
#                            HKx-Name, HKx-Zeitsteuerung_Heizung, WW-Zeitplan, WW-Zirkulationspumpe_Zeitplan
#
# 2020-04-23	  Refactoring (kein Einloggen mehr beim Ausführen einer Aktion)
# 2020-05-20      Neue Readings:
#					heating.boiler.sensors.temperature.main.unit celsius
#					heating.circuits.0.sensors.temperature.supply.unit celsius
#					heating.dhw.sensors.temperature.hotWaterStorage.unit celsius
#					heating.dhw.sensors.temperature.outlet.unit celsius
#					heating.sensors.temperature.outside.unit celsius
#				  Fehlerbehandlung verbessert
#				  nur noch einloggen, wenn nötig (Token läuft nach 1h aus.)
#
# 2020-06-25      Fehlerbehandlung für API (statusCode 401 (UNAUTHORIZED), 404 (DEVICE_NOT_FOUND)
#                    und 429 (RATE_LIMIT_EXCEEDED) und 502 (DEVICE_COMMUNICATION_ERROR)
#                 Neue Readings für Vitodens 200-W B2HF-19 und Brennstoffzelle von Viessmann (PA2)
#                 Information aus dem GW auslesen (Attribut "vitoconnect_gw_readings" auf "1" setzen;
#                    noch unvollständig!)
#
# 2020-07-06      readings for heating.power.production.demandCoverage.* fixed
#                 bei logResponseOnce wird bei getCode angefangen damit auch gw.json neu erzeugt wird
#
# 2020-11-26      Bugfix für einige "set"-Kommandos für HK2 und HK3
#
# 2020-12-21	  Neue Readings "heating.power.production.current.status" => "Stromproduktion_aktueller_Status",
#					"heating.power.production.current.value" => "Stromproduktion",
#					"heating.sensors.power.output.status" => "Sensor_Stromproduktion_Status",
#					"heating.sensors.power.output.value" => "Sensor_Stromproduktion" und
#                 	"heating.circuits.X.operating.programs.Y.demand" =>
#				      "HK(X+1)-Solltemperatur_Y_Anforderung" (X=0,1,2 und Y=normal,reduced,comfort)
# 2021-02-21      Umstieg auf Endpoint v2 zur Authorization
#                 *experimentell* Attribut vitoconnect_device
#                 Workaround für Forum #561
#                 Neue Readings für "*ValueReadAt"
#
# 2021-07-19      Anpassungen für privaten apiKey. Redirect URIs muss "http://localhost:4200/" sein.
#                 Nutzung des refresh_token
#
# 2021-07-19      neue Readings für heating.burners.0.*
#
#   ToDo:         timeout, intervall konfigurierbar machen
#				  Attribute implementieren und dokumentieren
#                 Mehrsprachigkeit
#                 Auswerten der Readings in getCode usw.
#				  devices/0 ? Was, wenn es mehrere Devices gibt?
#				  nach einem set Befehl Readings aktualisieren, vorher alten Timer löschen
#				  heating.circuits.0.operating.programs.holiday.changeEndDate action: end implementieren?
#

package main;
use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use JSON;
use HttpUtils;
use Encode qw(decode encode);
use Data::Dumper;
use Path::Tiny;
use DateTime;
use Time::Piece;
use Time::Seconds;

my $client_secret = "2e21faa1-db2c-4d0b-a10f-575fd372bc8c-575fd372bc8c";
my $callback_uri  = "http://localhost:4200/";
my $apiURLBase    = "https://api.viessmann-platform.io/iot/v1/equipment/";
my $apiURL        = "https://api.viessmann.com/iot/v1/equipment/";

my $RequestList = {
    "heating.boiler.serial.value"      => "Kessel_Seriennummer",
    "heating.boiler.temperature.value" => "Kessel_Solltemperatur",
    "heating.boiler.sensors.temperature.commonSupply.status" =>
      "Kessel_Common_Supply",
    "heating.boiler.sensors.temperature.commonSupply.unit" =>
      "Kessel_Common_Supply_Temperatur/Einheit",
    "heating.boiler.sensors.temperature.commonSupply.value" =>
      "Kessel_Common_Supply_Temperatur",
    "heating.boiler.sensors.temperature.main.status" => "Kessel_Status",
    "heating.boiler.sensors.temperature.main.unit" =>
      "Kesseltemperatur/Einheit",
    "heating.boiler.sensors.temperature.main.value" => "Kesseltemperatur",
    "heating.boiler.temperature.unit" => "Kesseltemperatur/Einheit",

    "heating.burner.active"              => "Brenner_aktiv",
    "heating.burner.automatic.status"    => "Brenner_Status",
    "heating.burner.automatic.errorCode" => "Brenner_Fehlercode",
    "heating.burner.current.power.value" => "Brenner_Leistung",
    "heating.burner.modulation.value"    => "Brenner_Modulation",
    "heating.burner.statistics.hours"    => "Brenner_Betriebsstunden",
    "heating.burner.statistics.starts"   => "Brenner_Starts",

    "heating.burners.0.active"            => "Brenner_1_aktiv",
    "heating.burners.0.modulation.unit"   => "Brenner_1_Modulation/Einheit",
    "heating.burners.0.modulation.value"  => "Brenner_1_Modulation",
    "heating.burners.0.statistics.hours"  => "Brenner_1_Betriebsstunden",
    "heating.burners.0.statistics.starts" => "Brenner_1_Starts",

    "heating.circuits.enabled"                   => "Aktive_Heizkreise",
    "heating.circuits.0.active"                  => "HK1-aktiv",
    "heating.circuits.0.type"                    => "HK1-Typ",
    "heating.circuits.0.circulation.pump.status" => "HK1-Zirkulationspumpe",
    "heating.circuits.0.circulation.schedule.active" =>
      "HK1-Zeitsteuerung_Zirkulation_aktiv",
    "heating.circuits.0.circulation.schedule.entries" =>
      "HK1-Zeitsteuerung_Zirkulation",
    "heating.circuits.0.frostprotection.status" => "HK1-Frostschutz_Status",
    "heating.circuits.0.geofencing.active"      => "HK1-Geofencing",
    "heating.circuits.0.geofencing.status"      => "HK1-Geofencing_Status",
    "heating.circuits.0.heating.curve.shift"    => "HK1-Heizkurve-Niveau",
    "heating.circuits.0.heating.curve.slope"    => "HK1-Heizkurve-Steigung",
    "heating.circuits.0.heating.schedule.active" =>
      "HK1-Zeitsteuerung_Heizung_aktiv",
    "heating.circuits.0.heating.schedule.entries" =>
      "HK1-Zeitsteuerung_Heizung",
    "heating.circuits.0.name"                         => "HK1-Name",
    "heating.circuits.0.operating.modes.active.value" => "HK1-Betriebsart",
    "heating.circuits.0.operating.modes.dhw.active"   => "HK1-WW_aktiv",
    "heating.circuits.0.operating.modes.dhwAndHeating.active" =>
      "HK1-WW_und_Heizen_aktiv",
    "heating.circuits.0.operating.modes.dhwAndHeatingCooling.active" =>
      "HK1-WW_und_Heizen_Kuehlen_aktiv",
    "heating.circuits.0.operating.modes.forcedNormal.active" =>
      "HK1-Solltemperatur_erzwungen",
    "heating.circuits.0.operating.modes.forcedReduced.active" =>
      "HK1-Reduzierte_Temperatur_erzwungen",
    "heating.circuits.0.operating.modes.heating.active" => "HK1-heizen_aktiv",
    "heating.circuits.0.operating.modes.normalStandby.active" =>
      "HK1-Normal_Standby_aktiv",
    "heating.circuits.0.operating.modes.standby.active" => "HK1-Standby_aktiv",
    "heating.circuits.0.operating.programs.active.value" =>
      "HK1-Programmstatus",
    "heating.circuits.0.operating.programs.comfort.active" =>
      "HK1-Solltemperatur_comfort_aktiv",
    "heating.circuits.0.operating.programs.comfort.demand" =>
      "HK1-Solltemperatur_comfort_Anforderung",
    "heating.circuits.0.operating.programs.comfort.temperature" =>
      "HK1-Solltemperatur_comfort",
    "heating.circuits.0.operating.programs.eco.active" =>
      "HK1-Solltemperatur_eco_aktiv",
    "heating.circuits.0.operating.programs.eco.temperature" =>
      "HK1-Solltemperatur_eco",
    "heating.circuits.0.operating.programs.external.active" =>
      "HK1-External_aktiv",
    "heating.circuits.0.operating.programs.external.temperature" =>
      "HK1-External_Temperatur",
    "heating.circuits.0.operating.programs.fixed.active" => "HK1-Fixed_aktiv",
    "heating.circuits.0.operating.programs.forcedLastFromSchedule.active" =>
      "HK1-forcedLastFromSchedule_aktiv",
    "heating.circuits.0.operating.programs.holidayAtHome.active" =>
      "HK1-HolidayAtHome_aktiv",
    "heating.circuits.0.operating.programs.holidayAtHome.end" =>
      "HK1-HolidayAtHome_Ende",
    "heating.circuits.0.operating.programs.holidayAtHome.start" =>
      "HK1-HolidayAtHome_Start",
    "heating.circuits.0.operating.programs.holiday.active" =>
      "HK1-Urlaub_aktiv",
    "heating.circuits.0.operating.programs.holiday.start" => "HK1-Urlaub_Start",
    "heating.circuits.0.operating.programs.holiday.end"   => "HK1-Urlaub_Ende",
    "heating.circuits.0.operating.programs.normal.active" =>
      "HK1-Solltemperatur_aktiv",
    "heating.circuits.0.operating.programs.normal.demand" =>
      "HK1-Solltemperatur_Anforderung",
    "heating.circuits.0.operating.programs.normal.temperature" =>
      "HK1-Solltemperatur_normal",
    "heating.circuits.0.operating.programs.reduced.active" =>
      "HK1-Solltemperatur_reduziert_aktiv",
    "heating.circuits.0.operating.programs.reduced.demand" =>
      "HK1-Solltemperatur_reduziert_Anforderung",
    "heating.circuits.0.operating.programs.reduced.temperature" =>
      "HK1-Solltemperatur_reduziert",
    "heating.circuits.0.operating.programs.summerEco.active" =>
      "HK1-Solltemperatur_SummerEco_aktiv",
    "heating.circuits.0.operating.programs.standby.active" =>
      "HK1-Standby_aktiv",
    "heating.circuits.0.zone.mode.active" => "HK1-ZoneMode_aktive",
    "heating.circuits.0.sensors.temperature.room.status" => "HK1-Raum_Status",
    "heating.circuits.0.sensors.temperature.room.value" =>
      "HK1-Raum_Temperatur",
    "heating.circuits.0.sensors.temperature.supply.status" =>
      "HK1-Vorlauftemperatur_aktiv",
    "heating.circuits.0.sensors.temperature.supply.unit" =>
      "HK1-Vorlauftemperatur/Einheit",
    "heating.circuits.0.sensors.temperature.supply.value" =>
      "HK1-Vorlauftemperatur",
    "heating.circuits.0.zone.mode.active" => "HK1-ZoneMode_aktive",

    "heating.circuits.1.active"                  => "HK2-aktiv",
    "heating.circuits.1.type"                    => "HK2-Typ",
    "heating.circuits.1.circulation.pump.status" => "HK2-Zirkulationspumpe",
    "heating.circuits.1.circulation.schedule.active" =>
      "HK2-Zeitsteuerung_Zirkulation_aktiv",
    "heating.circuits.1.circulation.schedule.entries" =>
      "HK2-Zeitsteuerung_Zirkulation",
    "heating.circuits.1.frostprotection.status" => "HK2-Frostschutz_Status",
    "heating.circuits.1.geofencing.active"      => "HK2-Geofencing",
    "heating.circuits.1.geofencing.status"      => "HK2-Geofencing_Status",
    "heating.circuits.1.heating.curve.shift"    => "HK2-Heizkurve-Niveau",
    "heating.circuits.1.heating.curve.slope"    => "HK2-Heizkurve-Steigung",
    "heating.circuits.1.heating.schedule.active" =>
      "HK2-Zeitsteuerung_Heizung_aktiv",
    "heating.circuits.1.heating.schedule.entries" =>
      "HK2-Zeitsteuerung_Heizung",
    "heating.circuits.1.name"                         => "HK2-Name",
    "heating.circuits.1.operating.modes.active.value" => "HK2-Betriebsart",
    "heating.circuits.1.operating.modes.dhw.active"   => "HK2-WW_aktiv",
    "heating.circuits.1.operating.modes.dhwAndHeating.active" =>
      "HK2-WW_und_Heizen_aktiv",
    "heating.circuits.1.operating.modes.dhwAndHeatingCooling.active" =>
      "HK2-WW_und_Heizen_Kuehlen_aktiv",
    "heating.circuits.1.operating.modes.forcedNormal.active" =>
      "HK2-Solltemperatur_erzwungen",
    "heating.circuits.1.operating.modes.forcedReduced.active" =>
      "HK2-Reduzierte_Temperatur_erzwungen",
    "heating.circuits.1.operating.modes.heating.active" => "HK2-heizen_aktiv",
    "heating.circuits.1.operating.modes.normalStandby.active" =>
      "HK2-Normal_Standby_aktiv",
    "heating.circuits.1.operating.modes.standby.active" => "HK2-Standby_aktiv",
    "heating.circuits.1.operating.programs.active.value" =>
      "HK2-Programmstatus",
    "heating.circuits.1.operating.programs.comfort.active" =>
      "HK2-Solltemperatur_comfort_aktiv",
    "heating.circuits.1.operating.programs.comfort.demand" =>
      "HK2-Solltemperatur_comfort_Anforderung",
    "heating.circuits.1.operating.programs.comfort.temperature" =>
      "HK2-Solltemperatur_comfort",
    "heating.circuits.1.operating.programs.eco.active" =>
      "HK2-Solltemperatur_eco_aktiv",
    "heating.circuits.1.operating.programs.eco.temperature" =>
      "HK2-Solltemperatur_eco",
    "heating.circuits.1.operating.programs.external.active" =>
      "HK2-External_aktiv",
    "heating.circuits.1.operating.programs.external.temperature" =>
      "HK2-External_Temperatur",
    "heating.circuits.1.operating.programs.fixed.active" => "HK2-Fixed_aktiv",
    "heating.circuits.1.operating.programs.forcedLastFromSchedule.active" =>
      "HK2-forcedLastFromSchedule_aktiv",
    "heating.circuits.1.operating.programs.holidayAtHome.active" =>
      "HK2-HolidayAtHome_aktiv",
    "heating.circuits.1.operating.programs.holidayAtHome.end" =>
      "HK2-HolidayAtHome_Ende",
    "heating.circuits.1.operating.programs.holidayAtHome.start" =>
      "HK2-HolidayAtHome_Start",
    "heating.circuits.1.operating.programs.holiday.active" =>
      "HK2-Urlaub_aktiv",
    "heating.circuits.1.operating.programs.holiday.start" => "HK2-Urlaub_Start",
    "heating.circuits.1.operating.programs.holiday.end"   => "HK2-Urlaub_Ende",
    "heating.circuits.1.operating.programs.normal.active" =>
      "HK2-Solltemperatur_aktiv",
    "heating.circuits.1.operating.programs.normal.demand" =>
      "HK2-Solltemperatur_Anforderung",
    "heating.circuits.1.operating.programs.normal.temperature" =>
      "HK2-Solltemperatur_normal",
    "heating.circuits.1.operating.programs.reduced.active" =>
      "HK2-Solltemperatur_reduziert_aktiv",
    "heating.circuits.1.operating.programs.reduced.demand" =>
      "HK2-Solltemperatur_reduziert_Anforderung",
    "heating.circuits.1.operating.programs.reduced.temperature" =>
      "HK2-Solltemperatur_reduziert",
    "heating.circuits.1.operating.programs.summerEco.active" =>
      "HK2-Solltemperatur_SummerEco_aktiv",
    "heating.circuits.1.operating.programs.standby.active" =>
      "HK2-Standby_aktiv",
    "heating.circuits.1.sensors.temperature.room.status" => "HK2-Raum_Status",
    "heating.circuits.1.sensors.temperature.room.value" =>
      "HK2-Raum_Temperatur",
    "heating.circuits.1.sensors.temperature.supply.status" =>
      "HK2-Vorlauftemperatur_aktiv",
    "heating.circuits.1.sensors.temperature.supply.unit" =>
      "HK2-Vorlauftemperatur/Einheit",
    "heating.circuits.1.sensors.temperature.supply.value" =>
      "HK2-Vorlauftemperatur",
    "heating.circuits.1.zone.mode.active" => "HK2-ZoneMode_aktive",

    "heating.circuits.2.active"                  => "HK3-aktiv",
    "heating.circuits.2.type"                    => "HK3-Typ",
    "heating.circuits.2.circulation.pump.status" => "HK3-Zirkulationspumpe",
    "heating.circuits.2.circulation.schedule.active" =>
      "HK3-Zeitsteuerung_Zirkulation_aktiv",
    "heating.circuits.2.circulation.schedule.entries" =>
      "HK3-Zeitsteuerung_Zirkulation",
    "heating.circuits.2.frostprotection.status" => "HK3-Frostschutz_Status",
    "heating.circuits.2.geofencing.active"      => "HK3-Geofencing",
    "heating.circuits.2.geofencing.status"      => "HK3-Geofencing_Status",
    "heating.circuits.2.heating.curve.shift"    => "HK3-Heizkurve-Niveau",
    "heating.circuits.2.heating.curve.slope"    => "HK3-Heizkurve-Steigung",
    "heating.circuits.2.heating.schedule.active" =>
      "HK3-Zeitsteuerung_Heizung_aktiv",
    "heating.circuits.2.heating.schedule.entries" =>
      "HK3-Zeitsteuerung_Heizung",
    "heating.circuits.2.name"                         => "HK3-Name",
    "heating.circuits.2.operating.modes.active.value" => "HK3-Betriebsart",
    "heating.circuits.2.operating.modes.dhw.active"   => "HK3-WW_aktiv",
    "heating.circuits.2.operating.modes.dhwAndHeating.active" =>
      "HK3-WW_und_Heizen_aktiv",
    "heating.circuits.2.operating.modes.dhwAndHeatingCooling.active" =>
      "HK3-WW_und_Heizen_Kuehlen_aktiv",
    "heating.circuits.2.operating.modes.forcedNormal.active" =>
      "HK3-Solltemperatur_erzwungen",
    "heating.circuits.2.operating.modes.forcedReduced.active" =>
      "HK3-Reduzierte_Temperatur_erzwungen",
    "heating.circuits.2.operating.modes.heating.active" => "HK3-heizen_aktiv",
    "heating.circuits.2.operating.modes.normalStandby.active" =>
      "HK3-Normal_Standby_aktiv",
    "heating.circuits.2.operating.modes.standby.active" => "HK3-Standby_aktiv",
    "heating.circuits.2.operating.programs.active.value" =>
      "HK3-Programmstatus",
    "heating.circuits.2.operating.programs.comfort.active" =>
      "HK3-Solltemperatur_comfort_aktiv",
    "heating.circuits.2.operating.programs.comfort.demand" =>
      "HK3-Solltemperatur_comfort_Anforderung",
    "heating.circuits.2.operating.programs.comfort.temperature" =>
      "HK3-Solltemperatur_comfort",
    "heating.circuits.2.operating.programs.eco.active" =>
      "HK3-Solltemperatur_eco_aktiv",
    "heating.circuits.2.operating.programs.eco.temperature" =>
      "HK3-Solltemperatur_eco",
    "heating.circuits.2.operating.programs.external.active" =>
      "HK3-External_aktiv",
    "heating.circuits.2.operating.programs.external.temperature" =>
      "HK3-External_Temperatur",
    "heating.circuits.2.operating.programs.fixed.active" => "HK3-Fixed_aktiv",
    "heating.circuits.2.operating.programs.forcedLastFromSchedule.active" =>
      "HK3-forcedLastFromSchedule_aktiv",
    "heating.circuits.2.operating.programs.holidayAtHome.active" =>
      "HK3-HolidayAtHome_aktiv",
    "heating.circuits.2.operating.programs.holidayAtHome.end" =>
      "HK3-HolidayAtHome_Ende",
    "heating.circuits.2.operating.programs.holidayAtHome.start" =>
      "HK3-HolidayAtHome_Start",
    "heating.circuits.2.operating.programs.holiday.active" =>
      "HK3-Urlaub_aktiv",
    "heating.circuits.2.operating.programs.holiday.start" => "HK3-Urlaub_Start",
    "heating.circuits.2.operating.programs.holiday.end"   => "HK3-Urlaub_Ende",
    "heating.circuits.2.operating.programs.normal.active" =>
      "HK3-Solltemperatur_aktiv",
    "heating.circuits.2.operating.programs.normal.demand" =>
      "HK3-Solltemperatur_Anforderung",
    "heating.circuits.2.operating.programs.normal.temperature" =>
      "HK3-Solltemperatur_normal",
    "heating.circuits.2.operating.programs.reduced.active" =>
      "HK3-Solltemperatur_reduziert_aktiv",
    "heating.circuits.2.operating.programs.reduced.demand" =>
      "HK3-Solltemperatur_reduziert_Anforderung",
    "heating.circuits.2.operating.programs.reduced.temperature" =>
      "HK3-Solltemperatur_reduziert",
    "heating.circuits.2.operating.programs.summerEco.active" =>
      "HK3-Solltemperatur_SummerEco_aktiv",
    "heating.circuits.2.operating.programs.standby.active" =>
      "HK3-Standby_aktiv",
    "heating.circuits.2.sensors.temperature.room.status" => "HK3-Raum_Status",
    "heating.circuits.2.sensors.temperature.room.value" =>
      "HK3-Raum_Temperatur",
    "heating.circuits.2.sensors.temperature.supply.status" =>
      "HK3-Vorlauftemperatur_aktiv",
    "heating.circuits.2.sensors.temperature.supply.unit" =>
      "HK3-Vorlauftemperatur/Einheit",
    "heating.circuits.2.sensors.temperature.supply.value" =>
      "HK3-Vorlauftemperatur",
    "heating.circuits.2.zone.mode.active" => "HK2-ZoneMode_aktive",

    "heating.circuits.3.geofencing.active" => "HK4-Geofencing",
    "heating.circuits.3.geofencing.status" => "HK4-Geofencing_Status",
    "heating.circuits.3.operating.programs.summerEco.active" =>
      "HK4-Solltemperatur_SummerEco_aktiv",
    "heating.circuits.3.zone.mode.active" => "HK4-ZoneMode_aktive",

    "heating.compressor.active"                     => "Kompressor_aktiv",
    "heating.configuration.multiFamilyHouse.active" => "Mehrfamilenhaus_aktiv",
    "heating.configuration.regulation.mode"         => "Regulationmode",
    "heating.controller.serial.value"  => "Controller_Seriennummer",
    "heating.device.time.offset.value" => "Device_Time_Offset",
    "heating.dhw.active"               => "WW-aktiv",
    "heating.dhw.status"               => "WW-Status",
    "heating.dhw.charging.active"      => "WW-Aufladung",

    "heating.dhw.charging.level.bottom" => "WW-Speichertemperatur_unten",
    "heating.dhw.charging.level.middle" => "WW-Speichertemperatur_mitte",
    "heating.dhw.charging.level.top"    => "WW-Speichertemperatur_oben",
    "heating.dhw.charging.level.value"  => "WW-Speicherladung",

    "heating.dhw.oneTimeCharge.active" => "WW-einmaliges_Aufladen",
    "heating.dhw.pumps.circulation.schedule.active" =>
      "WW-Zirkulationspumpe_Zeitsteuerung_aktiv",
    "heating.dhw.pumps.circulation.schedule.entries" =>
      "WW-Zirkulationspumpe_Zeitplan",
    "heating.dhw.pumps.circulation.status" => "WW-Zirkulationspumpe_Status",
    "heating.dhw.pumps.primary.status"     => "WW-Zirkulationspumpe_primaer",
    "heating.dhw.sensors.temperature.outlet.status" =>
      "WW-Sensoren_Auslauf_Status",
    "heating.dhw.sensors.temperature.outlet.unit" =>
      "WW-Sensoren_Auslauf_Wert/Einheit",
    "heating.dhw.sensors.temperature.outlet.value" =>
      "WW-Sensoren_Auslauf_Wert",
    "heating.dhw.temperature.main.value"       => "WW-Haupttemperatur",
    "heating.dhw.temperature.hysteresis.value" => "WW-Hysterese",
    "heating.dhw.temperature.temp2.value"      => "WW-Temperatur_2",
    "heating.dhw.sensors.temperature.hotWaterStorage.status" =>
      "WW-Temperatur_aktiv",
    "heating.dhw.sensors.temperature.hotWaterStorage.unit" =>
      "WW-Isttemperatur/Einheit",
    "heating.dhw.sensors.temperature.hotWaterStorage.value" =>
      "WW-Isttemperatur",
    "heating.dhw.temperature.value" => "WW-Solltemperatur",
    "heating.dhw.schedule.active"   => "WW-zeitgesteuert_aktiv",
    "heating.dhw.schedule.entries"  => "WW-Zeitplan",

    "heating.errors.active.entries"  => "Fehlereintraege_aktive",
    "heating.errors.history.entries" => "Fehlereintraege_Historie",

    "heating.flue.sensors.temperature.main.status" => "Abgassensor_Status",
    "heating.flue.sensors.temperature.main.unit" =>
      "Abgassensor_Temperatur/Einheit",
    "heating.flue.sensors.temperature.main.value" => "Abgassensor_Temperatur",

    "heating.fuelCell.operating.modes.active.value" => "Brennstoffzelle_Mode",
    "heating.fuelCell.operating.modes.ecological.active" =>
      "Brennstoffzelle_Mode_Ecological",
    "heating.fuelCell.operating.modes.economical.active" =>
      "Brennstoffzelle_Mode_Economical",
    "heating.fuelCell.operating.modes.heatControlled.active" =>
      "Brennstoffzelle_wärmegesteuert",
    "heating.fuelCell.operating.modes.maintenance.active" =>
      "Brennstoffzelle_Wartung",
    "heating.fuelCell.operating.modes.standby.active" =>
      "Brennstoffzelle_Standby",
    "heating.fuelCell.operating.phase.value" => "Brennstoffzelle_Phase",
    "heating.fuelCell.power.production.day" =>
      "Brennstoffzelle_Stromproduktion/Tag",
    "heating.fuelCell.power.production.month" =>
      "Brennstoffzelle_Stromproduktion/Monat",
    "heating.fuelCell.power.production.unit" =>
      "Brennstoffzelle_Stromproduktion/Einheit",
    "heating.fuelCell.power.production.week" =>
      "Brennstoffzelle_Stromproduktion/Woche",
    "heating.fuelCell.power.production.year" =>
      "Brennstoffzelle_Stromproduktion/Jahr",
    "heating.fuelCell.sensors.temperature.return.status" =>
      "Brennstoffzelle_Temperatur_Ruecklauf_Status",
    "heating.fuelCell.sensors.temperature.return.unit" =>
      "Brennstoffzelle_Temperatur_Ruecklauf/Einheit",
    "heating.fuelCell.sensors.temperature.return.value" =>
      "Brennstoffzelle_Temperatur_Ruecklauf",
    "heating.fuelCell.sensors.temperature.supply.status" =>
      "Brennstoffzelle_Temperatur_Vorlauf_Status",
    "heating.fuelCell.sensors.temperature.supply.unit" =>
      "Brennstoffzelle_Temperatur_Vorlauf/Einheit",
    "heating.fuelCell.sensors.temperature.supply.value" =>
      "Brennstoffzelle_Temperatur_Vorlauf",
    "heating.fuelCell.statistics.availabilityRate" =>
      "Brennstoffzelle_Statistic_Verfügbarkeit",
    "heating.fuelCell.statistics.insertions" =>
      "Brennstoffzelle_Statistic_Einschub",
    "heating.fuelCell.statistics.operationHours" =>
      "Brennstoffzelle_Statistic_Bestriebsstunden",
    "heating.fuelCell.statistics.productionHours" =>
      "Brennstoffzelle_Statistic_Produktionsstunden",
    "heating.fuelCell.statistics.productionStarts" =>
      "Brennstoffzelle_Statistic_Produktionsstarts",

    "heating.gas.consumption.dhw.day"   => "Gasverbrauch_WW/Tag",
    "heating.gas.consumption.dhw.week"  => "Gasverbrauch_WW/Woche",
    "heating.gas.consumption.dhw.month" => "Gasverbrauch_WW/Monat",
    "heating.gas.consumption.dhw.year"  => "Gasverbrauch_WW/Jahr",
    "heating.gas.consumption.dhw.dayValueReadAt" =>
      "Gasverbrauch_WW/Tag_gelesen_am",
    "heating.gas.consumption.dhw.weekValueReadAt" =>
      "Gasverbrauch_WW/Woche_gelesen_am",
    "heating.gas.consumption.dhw.monthValueReadAt" =>
      "Gasverbrauch_WW/Monat_gelesen_am",
    "heating.gas.consumption.dhw.yearValueReadAt" =>
      "Gasverbrauch_WW/Jahr_gelesen_am",
    "heating.gas.consumption.dhw.unit" => "Gasverbrauch_WW/Einheit",

    "heating.gas.consumption.heating.day"   => "Gasverbrauch_Heizung/Tag",
    "heating.gas.consumption.heating.week"  => "Gasverbrauch_Heizung/Woche",
    "heating.gas.consumption.heating.month" => "Gasverbrauch_Heizung/Monat",
    "heating.gas.consumption.heating.year"  => "Gasverbrauch_Heizung/Jahr",
    "heating.gas.consumption.heating.dayValueReadAt" =>
      "Gasverbrauch_Heizung/Tag_gelesen_am",
    "heating.gas.consumption.heating.weekValueReadAt" =>
      "Gasverbrauch_Heizung/Woche_gelesen_am",
    "heating.gas.consumption.heating.monthValueReadAt" =>
      "Gasverbrauch_Heizung/Monat_gelesen_am",
    "heating.gas.consumption.heating.yearValueReadAt" =>
      "Gasverbrauch_Heizung/Jahr_gelesen_am",
    "heating.gas.consumption.heating.unit" => "Gasverbrauch_Heizung/Einheit",
    "heating.gas.consumption.total.day"    => "Gasverbrauch_Total/Tag",
    "heating.gas.consumption.total.month"  => "Gasverbrauch_Total/Monat",
    "heating.gas.consumption.total.unit"   => "Gasverbrauch_Total/Einheit",
    "heating.gas.consumption.total.week"   => "Gasverbrauch_Total/Woche",
    "heating.gas.consumption.total.year"   => "Gasverbrauch_Total/Jahr",
    "heating.gas.consumption.total.dayValueReadAt" =>
      "Gasverbrauch_Total/Tag_gelesen_am",
    "heating.gas.consumption.total.monthValueReadAt" =>
      "Gasverbrauch_Total/Woche_gelesen_am",
    "heating.gas.consumption.total.weekValueReadAt" =>
      "Gasverbrauch_Total/Woche_gelesen_am",
    "heating.gas.consumption.total.yearValueReadAt" =>
      "Gasverbrauch_Total/Jahr_gelesen_am",

    "heating.gas.consumption.fuelCell.day" =>
      "Gasverbrauch_Brennstoffzelle/Tag",
    "heating.gas.consumption.fuelCell.week" =>
      "Gasverbrauch_Brennstoffzelle/Woche",
    "heating.gas.consumption.fuelCell.month" =>
      "Gasverbrauch_Brennstoffzelle/Monat",
    "heating.gas.consumption.fuelCell.year" =>
      "Gasverbrauch_Brennstoffzelle/Jahr",
    "heating.gas.consumption.fuelCell.unit" =>
      "Gasverbrauch_Brennstoffzelle/Einheit",

    "heating.heat.production.day"   => "Wärmeproduktion/Tag",
    "heating.heat.production.month" => "Wärmeproduktion/Woche",
    "heating.heat.production.unit"  => "Wärmeproduktion/Einheit",
    "heating.heat.production.week"  => "Wärmeproduktion/Woche",
    "heating.heat.production.year"  => "Wärmeproduktion/Jahr",

    "heating.operating.programs.holiday.active" => "Urlaub_aktiv",
    "heating.operating.programs.holiday.end"    => "Urlaub_Ende",
    "heating.operating.programs.holiday.start"  => "Urlaub_Start",

    "heating.operating.programs.holidayAtHome.active" => "holidayAtHome_aktiv",
    "heating.operating.programs.holidayAtHome.end"    => "holidayAtHome_Ende",
    "heating.operating.programs.holidayAtHome.start"  => "holidayAtHome_Start",

    "heating.power.consumption.day"   => "Stromverbrauch/Tag",
    "heating.power.consumption.month" => "Stromverbrauch/Monat",
    "heating.power.consumption.week"  => "Stromverbrauch/Woche",
    "heating.power.consumption.year"  => "Stromverbrauch/Jahr",
    "heating.power.consumption.unit"  => "Stromverbrauch/Einheit",

    "heating.power.consumption.dhw.day"   => "Stromverbrauch_WW/Tag",
    "heating.power.consumption.dhw.month" => "Stromverbrauch_WW/Monat",
    "heating.power.consumption.dhw.week"  => "Stromverbrauch_WW/Woche",
    "heating.power.consumption.dhw.year"  => "Stromverbrauch_WW/Jahr",
    "heating.power.consumption.dhw.unit"  => "Stromverbrauch_WW/Einheit",

    "heating.power.consumption.heating.day"   => "Stromverbrauch_Heizung/Tag",
    "heating.power.consumption.heating.month" => "Stromverbrauch_Heizung/Monat",
    "heating.power.consumption.heating.week"  => "Stromverbrauch_Heizung/Woche",
    "heating.power.consumption.heating.year"  => "Stromverbrauch_Heizung/Jahr",
    "heating.power.consumption.heating.unit" =>
      "Stromverbrauch_Heizung/Einheit",

    "heating.power.consumption.total.day"   => "Stromverbrauch_Total/Tag",
    "heating.power.consumption.total.month" => "Stromverbrauch_Total/Monat",
    "heating.power.consumption.total.week"  => "Stromverbrauch_Total/Woche",
    "heating.power.consumption.total.year"  => "Stromverbrauch_Total/Jahr",
    "heating.power.consumption.total.dayValueReadAt" =>
      "Stromverbrauch_Total/Tag_gelesen_am",
    "heating.power.consumption.total.monthValueReadAt" =>
      "Stromverbrauch_Total/Monat_gelesen_am",
    "heating.power.consumption.total.weekValueReadAt" =>
      "Stromverbrauch_Total/Woche_gelesen_am",
    "heating.power.consumption.total.yearValueReadAt" =>
      "Stromverbrauch_Total/Jahr_gelesen_am",
    "heating.power.consumption.total.unit" => "Stromverbrauch_Total/Einheit",

    "heating.power.production.current.status" =>
      "Stromproduktion_aktueller_Status",
    "heating.power.production.current.value" => "Stromproduktion",

    "heating.power.production.demandCoverage.current.unit" =>
      "Stromproduktion_Bedarfsabdeckung/Einheit",
    "heating.power.production.demandCoverage.current.value" =>
      "Stromproduktion_Bedarfsabdeckung",
    "heating.power.production.demandCoverage.total.day" =>
      "Stromproduktion_Bedarfsabdeckung_total/Tag",
    "heating.power.production.demandCoverage.total.month" =>
      "Stromproduktion_Bedarfsabdeckung_total/Monat",
    "heating.power.production.demandCoverage.total.unit" =>
      "Stromproduktion_Bedarfsabdeckung_total/Einheit",
    "heating.power.production.demandCoverage.total.week" =>
      "Stromproduktion_Bedarfsabdeckung_total/Woche",
    "heating.power.production.demandCoverage.total.year" =>
      "Stromproduktion_Bedarfsabdeckung_total/Jahr",

    "heating.power.production.day"   => "Stromproduktion_Total/Tag",
    "heating.power.production.month" => "Stromproduktion_Total/Monat",
    "heating.power.production.productionCoverage.current.unit" =>
      "Stromproduktion_Produktionsabdeckung/Einheit",
    "heating.power.production.productionCoverage.current.value" =>
      "Stromproduktion_Produktionsabdeckung",
    "heating.power.production.productionCoverage.total.day" =>
      "Stromproduktion_Produktionsabdeckung_Total/Tag",
    "heating.power.production.productionCoverage.total.month" =>
      "Stromproduktion_Produktionsabdeckung_Total/Monat",
    "heating.power.production.productionCoverage.total.unit" =>
      "Stromproduktion_Produktionsabdeckung_Total/Einheit",
    "heating.power.production.productionCoverage.total.week" =>
      "Stromproduktion_Produktionsabdeckung_Total/Woche",
    "heating.power.production.productionCoverage.total.year" =>
      "Stromproduktion_Produktionsabdeckung_Total/Jahr",
    "heating.power.production.unit" => "Stromproduktion_Total/Einheit",
    "heating.power.production.week" => "Stromproduktion_Total/Woche",
    "heating.power.production.year" => "Stromproduktion_Total/Jahr",

    "heating.power.purchase.current.unit"  => "Stromkauf/Einheit",
    "heating.power.purchase.current.value" => "Stromkauf",
    "heating.power.sold.current.unit"      => "Stromverkauf/Einheit",
    "heating.power.sold.current.value"     => "Stromverkauf",
    "heating.power.sold.day"               => "Stromverkauf/Tag",
    "heating.power.sold.month"             => "Stromverkauf/Monat",
    "heating.power.sold.unit"              => "Stromverkauf/Einheit",
    "heating.power.sold.week"              => "Stromverkauf/Woche",
    "heating.power.sold.year"              => "Stromverkauf/Jahr",

    "heating.sensors.pressure.supply.status" => "Drucksensor_Vorlauf_Status",
    "heating.sensors.pressure.supply.unit"   => "Drucksensor_Vorlauf/Einheit",
    "heating.sensors.pressure.supply.value"  => "Drucksensor_Vorlauf",

    "heating.sensors.power.output.status" => "Sensor_Stromproduktion_Status",
    "heating.sensors.power.output.value"  => "Sensor_Stromproduktion",

    "heating.sensors.temperature.outside.status"      => "Aussen_Status",
    "heating.sensors.temperature.outside.statusWired" => "Aussen_StatusWired",
    "heating.sensors.temperature.outside.statusWireless" =>
      "Aussen_StatusWireless",
    "heating.sensors.temperature.outside.unit"  => "Aussentemperatur/Einheit",
    "heating.sensors.temperature.outside.value" => "Aussentemperatur",

    "heating.service.timeBased.serviceDue" => "Service_faellig",
    "heating.service.timeBased.serviceIntervalMonths" =>
      "Service_Intervall_Monate",
    "heating.service.timeBased.activeMonthSinceLastService" =>
      "Service_Monate_aktiv_seit_letzten_Service",
    "heating.service.timeBased.lastService" => "Service_Letzter",
    "heating.service.burnerBased.serviceDue" =>
      "Service_fällig_brennerbasiert",
    "heating.service.burnerBased.serviceIntervalBurnerHours" =>
      "Service_Intervall_Betriebsstunden",
    "heating.service.burnerBased.activeBurnerHoursSinceLastService" =>
      "Service_Betriebsstunden_seit_letzten",
    "heating.service.burnerBased.lastService" =>
      "Service_Letzter_brennerbasiert",

    "heating.solar.active"               => "Solar_aktiv",
    "heating.solar.pumps.circuit.status" => "Solar_Pumpe_Status",
    "heating.solar.rechargeSuppression.status" =>
      "Solar_Aufladeunterdrueckung_Status",
    "heating.solar.sensors.power.status" => "Solar_Sensor_Power_Status",
    "heating.solar.sensors.power.value"  => "Solar_Sensor_Power",
    "heating.solar.sensors.temperature.collector.status" =>
      "Solar_Sensor_Temperatur_Kollektor_Status",
    "heating.solar.sensors.temperature.collector.value" =>
      "Solar_Sensor_Temperatur_Kollektor",
    "heating.solar.sensors.temperature.dhw.status" =>
      "Solar_Sensor_Temperatur_WW_Status",
    "heating.solar.sensors.temperature.dhw.value" =>
      "Solar_Sensor_Temperatur_WW",
    "heating.solar.statistics.hours" => "Solar_Sensor_Statistik_Stunden",

    "heating.solar.power.cumulativeProduced.value" =>
      "Solarproduktion_Gesamtertrag",
    "heating.solar.power.production.month" => "Solarproduktion/Monat",
    "heating.solar.power.production.day"   => "Solarproduktion/Tag",
    "heating.solar.power.production.unit"  => "Solarproduktion/Einheit",
    "heating.solar.power.production.week"  => "Solarproduktion/Woche",
    "heating.solar.power.production.year"  => "Solarproduktion/Jahr"
};

sub vitoconnect_Initialize {
    my ($hash) = @_;
    $hash->{DefFn}   = \&vitoconnect_Define;
    $hash->{UndefFn} = \&vitoconnect_Undef;
    $hash->{SetFn}   = \&vitoconnect_Set;
    $hash->{GetFn}   = \&vitoconnect_Get;
    $hash->{AttrFn}  = \&vitoconnect_Attr;
    $hash->{ReadFn}  = \&vitoconnect_Read;
    $hash->{AttrList} =
        "disable:0,1 "
      . "mapping:textField-long "
      . "model:Vitodens_200-W_(B2HB),Vitodens_200-W_(B2KB),"
      . "Vitotronic_200_(HO1),Vitotronic_200_(HO1A),Vitotronic_200_(HO1B),Vitotronic_200_(HO1D),"
      . "Vitotronic_200_(HO2B),"
      . "Vitotronic_200_RF_(HO1C),Vitotronic_200_RF_(HO1E),"
      . "Vitotronic_200_(KO1B),Vitotronic_200_(KO2B),Vitotronic_200_(KW6),Vitotronic_200_(KW6A),"
      . "Vitotronic_200_(KW6B),Vitotronic_200_(KW1),Vitotronic_200_(KW2),Vitotronic_200_(KW4),"
      . "Vitotronic_200_(KW5),"
      . "Vitotronic_300_(KW3),Vitotronic_200_(WO1A),Vitotronic_200_(WO1B),Vitotronic_200_(WO1C),"
      . "Vitoligno_300-C,Vitoligno_200-S,Vitoligno_300-P_mit_Vitotronic_200_(FO1),Vitoligno_250-S,"
      . "Vitoligno_300-S "
      . "vitoconnect_raw_readings:0,1 "
      . "vitoconnect_gw_readings:0,1 "
      . "vitoconnect_actions_active:0,1 "
      . "vitoconnect_device:0,1 "
      . "vitoconnect_timeout:selectnumbers,10,1.0,30,0,lin "
      . $readingFnAttributes;
    return;
}

sub vitoconnect_Define {
    my ( $hash, $def ) = @_;
    my $name  = $hash->{NAME};
    my @param = split( '[ \t]+', $def );

    if ( int(@param) < 5 ) {
        return "too few parameters: "
          . "define <name> vitoconnect <user> <passwd> <intervall>";
    }

    $hash->{user}            = $param[2];
    $hash->{intervall}       = $param[4];
    $hash->{counter}         = 0;
    $hash->{timeout}         = 15;
    $hash->{".access_token"} = "";
    $hash->{".installation"} = "";
    $hash->{".gw"}           = "";
    $hash->{"Redirect_URI"}  = $callback_uri;

    my $isiwebpasswd = vitoconnect_ReadKeyValue( $hash, "passwd" );
    if ( $isiwebpasswd eq "" ) {
        my $err = vitoconnect_StoreKeyValue( $hash, "passwd", $param[3] );
        return $err if ($err);
    }
    else {
        Log3 $name, 3, "$name - Passwort war bereits gespeichert";
    }
    $hash->{apiKey} = vitoconnect_ReadKeyValue( $hash, "apiKey" );
    InternalTimer( gettimeofday() + 10, "vitoconnect_GetUpdate", $hash );
    return;
}

sub vitoconnect_Undef {
    my ( $hash, $arg ) = @_;
    RemoveInternalTimer($hash);
    return;
}

sub vitoconnect_Get {
    my ( $hash, $name, $opt, @args ) = @_;
    return "get $name needs at least one argument" unless ( defined($opt) );
    return;
}

sub vitoconnect_Set {
    my ( $hash, $name, $opt, @args ) = @_;
    return "set $name needs at least one argument" unless ( defined($opt) );
    if ( $opt eq "update" ) {
        RemoveInternalTimer($hash);
        vitoconnect_GetUpdate($hash);
        return;
    }
    elsif ( $opt eq "logResponseOnce" ) {
        $hash->{".logResponseOnce"} = 1;
        RemoveInternalTimer($hash);
        vitoconnect_getCode($hash);
        return;
    }
    elsif ( $opt eq "clearReadings" ) {
        AnalyzeCommand( $hash, "deletereading $name .*" );
        return;
    }
    elsif ( $opt eq "password" ) {
        my $err = vitoconnect_StoreKeyValue( $hash, "passwd", $args[0] );
        return $err if ($err);
        vitoconnect_getCode($hash);
        return;
    }
    elsif ( $opt eq "apiKey" ) {
        $hash->{apiKey} = $args[0];
        my $err = vitoconnect_StoreKeyValue( $hash, "apiKey", $args[0] );
        RemoveInternalTimer($hash);
        vitoconnect_getCode($hash);
        return;
    }
    elsif ( $opt eq "HK1-Heizkurve-Niveau" ) {
        my $slope = ReadingsVal( $name, "HK1-Heizkurve-Steigung", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.0.heating.curve/commands/setCurve",
            "{\"shift\":$args[0],\"slope\":$slope}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Heizkurve-Niveau" ) {
        my $slope = ReadingsVal( $name, "HK2-Heizkurve-Steigung", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.1.heating.curve/commands/setCurve",
            "{\"shift\":$args[0],\"slope\":$slope}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Heizkurve-Niveau" ) {
        my $slope = ReadingsVal( $name, "HK3-Heizkurve-Steigung", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.2.heating.curve/commands/setCurve",
            "{\"shift\":$args[0],\"slope\":$slope}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Heizkurve-Steigung" ) {
        my $shift = ReadingsVal( $name, "HK1-Heizkurve-Niveau", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.0.heating.curve/commands/setCurve",
            "{\"shift\":$shift,\"slope\":$args[0]}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Heizkurve-Steigung" ) {
        my $shift = ReadingsVal( $name, "HK2-Heizkurve-Niveau", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.1.heating.curve/commands/setCurve",
            "{\"shift\":$shift,\"slope\":$args[0]}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Heizkurve-Steigung" ) {
        my $shift = ReadingsVal( $name, "HK3-Heizkurve-Niveau", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.2.heating.curve/commands/setCurve",
            "{\"shift\":$shift,\"slope\":$args[0]}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Urlaub_Start" ) {
        my $end = ReadingsVal( $name, "HK1-Urlaub_Ende", "" );
        if ( $end eq "" ) {
            my $t = Time::Piece->strptime( $args[0], "%Y-%m-%d" );
            $t += ONE_DAY;
            $end = $t->strftime("%Y-%m-%d");
        }
        vitoconnect_action(
            $hash,
            "heating.circuits.0.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Urlaub_Start" ) {
        my $end = ReadingsVal( $name, "HK2-Urlaub_Ende", "" );
        if ( $end eq "" ) {
            my $t = Time::Piece->strptime( $args[0], "%Y-%m-%d" );
            $t += ONE_DAY;
            $end = $t->strftime("%Y-%m-%d");
        }
        vitoconnect_action(
            $hash,
            "heating.circuits.1.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Urlaub_Start" ) {
        my $end = ReadingsVal( $name, "HK3-Urlaub_Ende", "" );
        if ( $end eq "" ) {
            my $t = Time::Piece->strptime( $args[0], "%Y-%m-%d" );
            $t += ONE_DAY;
            $end = $t->strftime("%Y-%m-%d");
        }
        vitoconnect_action(
            $hash,
            "heating.circuits.2.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Urlaub_Ende" ) {
        my $start = ReadingsVal( $name, "HK1-Urlaub_Start", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.0.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Urlaub_Ende" ) {
        my $start = ReadingsVal( $name, "HK2-Urlaub_Start", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.1.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Urlaub_Ende" ) {
        my $start = ReadingsVal( $name, "HK3-Urlaub_Start", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.2.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Urlaub_unschedule" ) {
        vitoconnect_action(
            $hash,
            "heating.circuits.0.operating.programs.holiday/commands/unschedule",
            "{}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Urlaub_unschedule" ) {
        vitoconnect_action(
            $hash,
            "heating.circuits.1.operating.programs.holiday/commands/unschedule",
            "{}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Urlaub_unschedule" ) {
        vitoconnect_action(
            $hash,
            "heating.circuits.2.operating.programs.holiday/commands/unschedule",
            "{}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Zeitsteuerung_Heizung" ) {
        vitoconnect_action( $hash,
            "heating.circuits.0.heating.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK2-Zeitsteuerung_Heizung" ) {
        vitoconnect_action( $hash,
            "heating.circuits.1.heating.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK3-Zeitsteuerung_Heizung" ) {
        vitoconnect_action( $hash,
            "heating.circuits.2.heating.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK1-Betriebsart" ) {
        vitoconnect_action( $hash,
            "heating.circuits.0.operating.modes.active/commands/setMode",
            "{\"mode\":\"$args[0]\"}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK2-Betriebsart" ) {
        vitoconnect_action( $hash,
            "heating.circuits.1.operating.modes.active/commands/setMode",
            "{\"mode\":\"$args[0]\"}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK3-Betriebsart" ) {
        vitoconnect_action( $hash,
            "heating.circuits.2.operating.modes.active/commands/setMode",
            "{\"mode\":\"$args[0]\"}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK1-Solltemperatur_comfort_aktiv" ) {
        vitoconnect_action( $hash,
            "heating.circuits.0.operating.programs.comfort/commands/$args[0]",
            "{}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK2-Solltemperatur_comfort_aktiv" ) {
        vitoconnect_action( $hash,
            "heating.circuits.1.operating.programs.comfort/commands/$args[0]",
            "{}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK3-Solltemperatur_comfort_aktiv" ) {
        vitoconnect_action( $hash,
            "heating.circuits.2.operating.programs.comfort/commands/$args[0]",
            "{}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK1-Solltemperatur_comfort" ) {
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.comfort/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Solltemperatur_comfort" ) {
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.comfort/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Solltemperatur_comfort" ) {
        vitoconnect_action($hash,
            "heating.circuits.2.operating.programs.comfort/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Solltemperatur_eco_aktiv" ) {
        vitoconnect_action( $hash,
            "heating.circuits.0.operating.programs.eco/commands/$args[0]",
            "{}", $name, $opt, @args );
        return;

    }
    elsif ( $opt eq "HK2-Solltemperatur_eco_aktiv" ) {
        vitoconnect_action( $hash,
            "heating.circuits.1.operating.programs.eco/commands/$args[0]",
            "{}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK3-Solltemperatur_eco_aktiv" ) {
        vitoconnect_action( $hash,
            "heating.circuits.2.operating.programs.eco/commands/$args[0]",
            "{}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK1-Solltemperatur_normal" ) {
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.normal/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Solltemperatur_normal" ) {
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.normal/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Solltemperatur_normal" ) {
        vitoconnect_action($hash,
            "heating.circuits.2.operating.programs.normal/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Solltemperatur_reduziert" ) {
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.reduced/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Solltemperatur_reduziert" ) {
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.reduced/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Solltemperatur_reduziert" ) {
        vitoconnect_action($hash,
               "heating.circuits.2.operating.programs.reduced/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Name" ) {
        vitoconnect_action( $hash, "heating.circuits.0/commands/setName",
            "{\"name\":\"@args\"}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK2-Name" ) {
        vitoconnect_action( $hash, "heating.circuits.1/commands/setName",
            "{\"name\":\"@args\"}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK3-Name" ) {
        vitoconnect_action( $hash, "heating.circuits.2/commands/setName",
            "{\"name\":\"@args\"}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "WW-einmaliges_Aufladen" ) {
        vitoconnect_action( $hash,
            "heating.dhw.oneTimeCharge/commands/$args[0]",
            "{}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "WW-Zirkulationspumpe_Zeitplan" ) {
        vitoconnect_action( $hash,
            "heating.dhw.pumps.circulation.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "WW-Zeitplan" ) {
        vitoconnect_action( $hash, "heating.dhw.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "WW-Haupttemperatur" ) {
        vitoconnect_action( $hash,
            "heating.dhw.temperature.main/commands/setTargetTemperature",
            "{\"temperature\":$args[0]}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "WW-Solltemperatur" ) {
        vitoconnect_action( $hash,
            "heating.dhw.temperature/commands/commands/setTargetTemperature",
            "{\"temperature\":$args[0]}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "WW-Temperatur_2" ) {
        vitoconnect_action( $hash,
            "heating.dhw.temperature.temp2/commands/setTargetTemperature",
            "{\"temperature\":$args[0]}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "Urlaub_Start" ) {
        my $end = ReadingsVal( $name, "Urlaub_Ende", "" );
        if ( $end eq "" ) {
            my $t = Time::Piece->strptime( $args[0], "%Y-%m-%d" );
            $t += ONE_DAY;
            $end = $t->strftime("%Y-%m-%d");
        }
        vitoconnect_action(
            $hash,
            "heating.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "Urlaub_Ende" ) {
        my $start = ReadingsVal( $name, "Urlaub_Start", "" );
        vitoconnect_action(
            $hash,
            "heating.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "Urlaub_unschedule" ) {
        vitoconnect_action( $hash,
            "heating.operating.programs.holiday/commands/unschedule",
            "{}", $name, $opt, @args );
        return;
    }

    my $val =
        "unknown value $opt, choose one of update:noArg clearReadings:noArg "
      . "password apiKey logResponseOnce:noArg "
      . "WW-einmaliges_Aufladen:activate,deactivate "
      . "WW-Zirkulationspumpe_Zeitplan:textField-long "
      . "WW-Zeitplan:textField-long "
      . "WW-Haupttemperatur:slider,10,1,60 "
      . "WW-Solltemperatur:slider,10,1,60 "
      . "WW-Temperatur_2:slider,10,1,60 "
      . "Urlaub_Start "
      . "Urlaub_Ende "
      . "Urlaub_unschedule:noArg ";

    if ( ReadingsVal( $name, "HK1-aktiv", "0" ) eq "1" ) {
        $val .=
            "HK1-Heizkurve-Niveau:slider,-13,1,40 "
          . "HK1-Heizkurve-Steigung:slider,0.2,0.1,3.5,1 "
          . "HK1-Zeitsteuerung_Heizung:textField-long "
          . "HK1-Urlaub_Start "
          . "HK1-Urlaub_Ende "
          . "HK1-Urlaub_unschedule:noArg "
          . "HK1-Betriebsart:active,standby,heating,dhw,dhwAndHeating,forcedReduced,forcedNormal "
          . "HK1-Solltemperatur_comfort_aktiv:activate,deactivate "
          . "HK1-Solltemperatur_comfort:slider,4,1,37 "
          . "HK1-Solltemperatur_eco_aktiv:activate,deactivate "
          . "HK1-Solltemperatur_normal:slider,3,1,37 "
          . "HK1-Solltemperatur_reduziert:slider,3,1,37 "
          . "HK1-Name ";
    }
    if ( ReadingsVal( $name, "HK2-aktiv", "0" ) eq "1" ) {
        $val .=
            "HK2-Heizkurve-Niveau:slider,-13,1,40 "
          . "HK2-Heizkurve-Steigung:slider,0.2,0.1,3.5,1 "
          . "HK2-Zeitsteuerung_Heizung:textField-long "
          . "HK2-Urlaub_Start "
          . "HK2-Urlaub_Ende "
          . "HK2-Urlaub_unschedule:noArg "
          . "HK2-Betriebsart:active,standby,heating,dhw,dhwAndHeating,forcedReduced,forcedNormal "
          . "HK2-Solltemperatur_comfort_aktiv:activate,deactivate "
          . "HK2-Solltemperatur_comfort:slider,4,1,37 "
          . "HK2-Solltemperatur_eco_aktiv:activate,deactivate "
          . "HK2-Solltemperatur_normal:slider,3,1,37 "
          . "HK2-Solltemperatur_reduziert:slider,3,1,37 "
          . "HK2-Name ";
    }
    if ( ReadingsVal( $name, "HK3-aktiv", "0" ) eq "1" ) {
        $val .=
            "HK3-Heizkurve-Niveau:slider,-13,1,40 "
          . "HK3-Heizkurve-Steigung:slider,0.2,0.1,3.5,1 "
          . "HK3-Zeitsteuerung_Heizung:textField-long "
          . "HK3-Urlaub_Start "
          . "HK3-Urlaub_Ende "
          . "HK3-Urlaub_unschedule:noArg "
          . "HK3-Betriebsart:active,standby,heating,dhw,dhwAndHeating,forcedReduced,forcedNormal "
          . "HK3-Solltemperatur_comfort_aktiv:activate,deactivate "
          . "HK3-Solltemperatur_comfort:slider,4,1,37 "
          . "HK3-Solltemperatur_eco_aktiv:activate,deactivate "
          . "HK3-Solltemperatur_normal:slider,3,1,37 "
          . "HK3-Solltemperatur_reduziert:slider,3,1,37 "
          . "HK3-Name ";
    }
    return $val;
}

sub vitoconnect_Attr {
    my ( $cmd, $name, $attr_name, $attr_value ) = @_;
    if ( $cmd eq "set" ) {
        if ( $attr_name eq "vitoconnect_raw_readings" ) {
            if ( $attr_value !~ /^0|1$/ ) {
                my $err =
                  "Invalid argument $attr_value to $attr_name. Must be 0 or 1.";
                Log 1, "$name - " . $err;
                return $err;
            }
        }
        elsif ( $attr_name eq "vitoconnect_gw_readings" ) {
            if ( $attr_value !~ /^0|1$/ ) {
                my $err =
                  "Invalid argument $attr_value to $attr_name. Must be 0 or 1.";
                Log 1, "$name - " . $err;
                return $err;
            }
        }
        elsif ( $attr_name eq "vitoconnect_actions_active" ) {
            if ( $attr_value !~ /^0|1$/ ) {
                my $err =
                  "Invalid argument $attr_value to $attr_name. Must be 0 or 1.";
                Log 1, "$name - " . $err;
                return $err;
            }
        }
        elsif ( $attr_name eq "mapping" ) {

            # $RequestList2 = "$attr_value";
        }
        elsif ( $attr_name eq "disable" ) {
        }
        elsif ( $attr_name eq "verbose" ) {
        }
        else {
            # return "Unknown attr $attr_name";
        }
    }
    return;
}

# Subs
sub vitoconnect_GetUpdate {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 4, "$name - GetUpdate called ...";
    if ( IsDisabled($name) ) {
        Log3 $name, 4, "$name - device disabled";
        InternalTimer( gettimeofday() + $hash->{intervall},
            "vitoconnect_GetUpdate", $hash );
    }
    else {
        vitoconnect_getResource($hash);
    }
    return;
}

sub vitoconnect_getCode {
    my ($hash)       = @_;
    my $name         = $hash->{NAME};
    my $isiwebpasswd = vitoconnect_ReadKeyValue( $hash, "passwd" );
    my $client_id    = $hash->{apiKey};
    if ( !defined($client_id) ) {
        Log3 $name, 1, "$name - set apiKey first";
        readingsSingleUpdate( $hash, "state", "Set apiKey to continue", 1 );
        return;
    }
    my $authorizeURL = 'https://iam.viessmann.com/idp/v2/authorize';

    my $param = {
        url => "$authorizeURL?client_id=$client_id"
          . "&redirect_uri=$callback_uri&"
          . "code_challenge=2e21faa1-db2c-4d0b-a10f-575fd372bc8c-575fd372bc8c&"
          . "&scope=IoT%20User%20offline_access"
          . "&response_type=code",
        hash            => $hash,
        header          => "Content-Type: application/x-www-form-urlencoded",
        ignoreredirects => 1,
        user            => $hash->{user},
        pwd             => $isiwebpasswd,
        sslargs         => { SSL_verify_mode => 0 },
        timeout         => $hash->{timeout},
        method          => "POST",
        callback        => \&vitoconnect_getCodeCallback
    };

    #Log3 $name, 4, "$name - user=$param->{user} passwd=$param->{pwd}";
    #Log3 $name, 5, Dumper($hash);
    HttpUtils_NonblockingGet($param);
    return;
}

sub vitoconnect_getCodeCallback {
    my ( $param, $err, $response_body ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ( $err eq "" ) {
        Log3 $name, 4, "$name - getCodeCallback went ok";
        Log3 $name, 5, "$name - Received response: $response_body";
        $response_body =~ /code=(.*)"/;
        $hash->{".code"} = $1;
        Log3 $name, 4, "$name - code: " . $hash->{".code"};
        if ( $hash->{".code"} && $hash->{".code"} ne "4" ) {
            $hash->{login} = "ok";
        }
        else {
            $hash->{login} = "failure";
        }
    }
    else {
        Log3 $name, 1, "$name - An error occured: $err";
        $hash->{login} = "failure";
    }
    if ( $hash->{login} eq "ok" ) {
        readingsSingleUpdate( $hash, "state", "login ok", 1 );
        vitoconnect_getAccessToken($hash);
    }
    else {
        readingsSingleUpdate( $hash, "state",
            "Login failure. Check password and apiKey", 1 );
        Log3 $name, 1, "$name - Login failure. Check password and apiKey";
        InternalTimer( gettimeofday() + $hash->{intervall},
            "vitoconnect_GetUpdate", $hash );	# Forum: #880
    }
    return;
}

sub vitoconnect_getAccessToken {
    my ($hash)    = @_;
    my $name      = $hash->{NAME};
    my $client_id = $hash->{apiKey};
    my $param     = {
        url    => "https://iam.viessmann.com/idp/v2/token",
        hash   => $hash,
        header => "Content-Type: application/x-www-form-urlencoded",
        data   => "grant_type=authorization_code"
          . "&code_verifier="
          . $client_secret
          . "&client_id=$client_id"
          . "&redirect_uri=$callback_uri"
          . "&code="
          . $hash->{".code"},
        sslargs  => { SSL_verify_mode => 0 },
        method   => "POST",
        timeout  => $hash->{timeout},
        callback => \&vitoconnect_getAccessTokenCallback
    };

    #Log3 $name, 1, "$name - " . $param->{"data"};
    HttpUtils_NonblockingGet($param);
    return;
}

sub vitoconnect_getAccessTokenCallback {
    my ( $param, $err, $response_body ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ( $err eq "" ) {
        Log3 $name, 4, "$name - getAccessTokenCallback went ok";
        Log3 $name, 5, "$name - Received response: $response_body\n";
        my $decode_json = eval { decode_json($response_body) };
        if ($@) {
            Log3 $name, 1, "$name - JSON error while request: $@";
            InternalTimer( gettimeofday() + $hash->{intervall},
                "vitoconnect_GetUpdate", $hash );
            return;
        }
        my $access_token = $decode_json->{"access_token"};
        if ( $access_token ne "" ) {
            $hash->{".access_token"} = $access_token;
            $hash->{"refresh_token"} = $decode_json->{"refresh_token"};

            Log3 $name, 4,
              "$name - Access Token: " . substr( $access_token, 0, 20 ) . "...";
            vitoconnect_getGw($hash);
        }
        else {
            Log3 $name, 1, "$name - Access Token: nicht definiert";
            Log3 $name, 5, "$name - Received response: $response_body\n";
            InternalTimer( gettimeofday() + $hash->{intervall},
                "vitoconnect_GetUpdate", $hash );
        }
    }
    else {
        Log3 $name, 1, "$name - getAccessToken: An error occured: $err";
        InternalTimer( gettimeofday() + $hash->{intervall},
            "vitoconnect_GetUpdate", $hash );
    }
    return;
}

sub vitoconnect_getRefresh {
    my ($hash)    = @_;
    my $name      = $hash->{NAME};
    my $client_id = $hash->{apiKey};
    my $param     = {
        url    => "https://iam.viessmann.com/idp/v2/token",
        hash   => $hash,
        header => "Content-Type: application/x-www-form-urlencoded",
        data   => "grant_type=refresh_token"
          . "&client_id=$client_id"
          . "&refresh_token="
          . $hash->{"refresh_token"},
        sslargs  => { SSL_verify_mode => 0 },
        method   => "POST",
        timeout  => $hash->{timeout},
        callback => \&vitoconnect_getRefreshCallback
    };

    #Log3 $name, 1, "$name - " . $param->{"data"};
    HttpUtils_NonblockingGet($param);
    return;
}

sub vitoconnect_getRefreshCallback {
    my ( $param, $err, $response_body ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ( $err eq "" ) {
        Log3 $name, 4, "$name - getRefreshCallback went ok";
        Log3 $name, 5, "$name - Received response: $response_body\n";
        my $decode_json = eval { decode_json($response_body) };
        if ($@) {
            Log3 $name, 1, "$name - JSON error while request: $@";
            InternalTimer( gettimeofday() + $hash->{intervall},
                "vitoconnect_GetUpdate", $hash );
            return;
        }
        my $access_token = $decode_json->{"access_token"};
        if ( $access_token ne "" ) {
            $hash->{".access_token"} = $access_token;

            #$hash->{"refresh_token"} =  $decode_json->{"refresh_token"};

            Log3 $name, 4,
              "$name - Access Token: " . substr( $access_token, 0, 20 ) . "...";
            vitoconnect_getGw($hash);
        }
        else {
            Log3 $name, 1, "$name - Access Token: nicht definiert";
            Log3 $name, 5, "$name - Received response: $response_body\n";
            InternalTimer( gettimeofday() + $hash->{intervall},
                "vitoconnect_GetUpdate", $hash );    # zurück zu getCode?
        }
    }
    else {
        Log3 $name, 1, "$name - getRefresh: An error occured: $err";
        InternalTimer( gettimeofday() + $hash->{intervall},
            "vitoconnect_GetUpdate", $hash );
    }
    return;
}

sub vitoconnect_getGw {
    my ($hash)       = @_;
    my $name         = $hash->{NAME};
    my $access_token = $hash->{".access_token"};
    my $param        = {
        url      => $apiURL . "gateways",
        hash     => $hash,
        header   => "Authorization: Bearer $access_token",
        timeout  => $hash->{timeout},
        sslargs  => { SSL_verify_mode => 0 },
        callback => \&vitoconnect_getGwCallback
    };
    HttpUtils_NonblockingGet($param);
    return;
}

sub vitoconnect_getGwCallback {
    my ( $param, $err, $response_body ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ( $err eq "" ) {
        Log3 $name, 4, "$name - getGwCallback went ok";
        Log3 $name, 5, "$name - Received response: $response_body\n";
        my $items = eval { decode_json($response_body) };
        if ($@) {
            readingsSingleUpdate( $hash, "state",
                "JSON error while request: $@", 1 );
            Log3 $name, 1, "$name - JSON error while request: $@";
            InternalTimer( gettimeofday() + $hash->{intervall},
                "vitoconnect_GetUpdate", $hash );
            return;
        }
        if ( $hash->{".logResponseOnce"} ) {
            my $dir         = path( AttrVal( "global", "logdir", "log" ) );
            my $file        = $dir->child("gw.json");
            my $file_handle = $file->openw_utf8();
            $file_handle->print( Dumper($items) );
        }
        $hash->{".gw"} = $items->{data}[0]->{serial};
        readingsSingleUpdate( $hash, "gw", $response_body, 1 );
        vitoconnect_getInstallation($hash);
    }
    else {
        Log3 $name, 1, "$name - An error occured: $err";
        InternalTimer( gettimeofday() + $hash->{intervall},
            "vitoconnect_GetUpdate", $hash );
    }
    return;
}

sub vitoconnect_getInstallation {
    my ($hash)       = @_;
    my $name         = $hash->{NAME};
    my $access_token = $hash->{".access_token"};
    my $param        = {
        url      => $apiURL . "installations",
        hash     => $hash,
        header   => "Authorization: Bearer $access_token",
        timeout  => $hash->{timeout},
        sslargs  => { SSL_verify_mode => 0 },
        callback => \&vitoconnect_getInstallationCallback
    };
    HttpUtils_NonblockingGet($param);
    return;
}

sub vitoconnect_getInstallationCallback {
    my ( $param, $err, $response_body ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ( $err eq "" ) {
        Log3 $name, 4, "$name - getInstallationCallback went ok";
        Log3 $name, 5, "$name - Received response: $response_body";
        my $items = eval { decode_json($response_body) };
        if ($@) {
            readingsSingleUpdate( $hash, "state",
                "JSON error while request: $@", 1 );
            Log3 $name, 1, "$name - JSON error while request: $@";
            InternalTimer( gettimeofday() + $hash->{intervall},
                "vitoconnect_GetUpdate", $hash );
            return;
        }
        if ( $hash->{".logResponseOnce"} ) {
            my $dir         = path( AttrVal( "global", "logdir", "log" ) );
            my $file        = $dir->child("installation.json");
            my $file_handle = $file->openw_utf8();
            $file_handle->print( Dumper($items) );
        }
        my $id = $items->{data}[0]->{id};
        if ( $id == "" ) {
            Log3 $name, 1, "$name - Something went wrong. Will retry";
            InternalTimer( gettimeofday() + $hash->{intervall},
                "vitoconnect_GetUpdate", $hash );
        }
        else {
            $hash->{".installation"} = $items->{data}[0]->{id};
            readingsSingleUpdate( $hash, "installation", $response_body, 1 );
            vitoconnect_getDevice($hash);
        }
    }
    else {
        Log3 $name, 1, "$name - An error occured: $err";
        InternalTimer( gettimeofday() + $hash->{intervall},
            "vitoconnect_GetUpdate", $hash );
    }
    return;
}

sub vitoconnect_getDevice {
    my ($hash)       = @_;
    my $name         = $hash->{NAME};
    my $access_token = $hash->{".access_token"};
    my $installation = $hash->{".installation"};
    my $gw           = $hash->{".gw"};
    my $param        = {
        url     => $apiURL . "installations/$installation/gateways/$gw/devices",
        hash    => $hash,
        header  => "Authorization: Bearer $access_token",
        timeout => $hash->{timeout},
        sslargs => { SSL_verify_mode => 0 },
        callback => \&vitoconnect_getDeviceCallback
    };
    HttpUtils_NonblockingGet($param);
    return;
}

sub vitoconnect_getDeviceCallback {
    my ( $param, $err, $response_body ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ( $err eq "" ) {
        Log3 $name, 4, "$name - getDeviceCallback went ok";
        Log3 $name, 5, "$name - Received response: $response_body\n";
        my $items = eval { decode_json($response_body) };
        if ($@) {
            readingsSingleUpdate( $hash, "state",
                "JSON error while request: $@", 1 );
            Log3 $name, 1, "$name - JSON error while request: $@";
            InternalTimer( gettimeofday() + $hash->{intervall},
                "vitoconnect_GetUpdate", $hash );
            return;
        }
        if ( $hash->{".logResponseOnce"} ) {
            my $dir         = path( AttrVal( "global", "logdir", "log" ) );
            my $file        = $dir->child("device.json");
            my $file_handle = $file->openw_utf8();
            $file_handle->print( Dumper($items) );
        }
        readingsSingleUpdate( $hash, "device", $response_body, 1 );
        vitoconnect_getFeatures($hash);
        vitoconnect_getResource($hash);
    }
    else {
        Log3 $name, 1, "$name - An error occured: $err";
        InternalTimer( gettimeofday() + $hash->{intervall},
            "vitoconnect_GetUpdate", $hash );
    }
    return;
}

sub vitoconnect_getFeatures {
    my ($hash)       = @_;
    my $name         = $hash->{NAME};
    my $access_token = $hash->{".access_token"};
    my $installation = $hash->{".installation"};
    my $gw           = $hash->{".gw"};
    my $dev          = AttrVal( $name, 'vitoconnect_device', 0 );

    Log3 $name, 4, "$name - getFeatures went ok";

    # Service Documents -ToDo

    # Gateway features
    my $param = {
        url    => $apiURL . "installations/$installation/gateways/$gw/features",
        hash   => $hash,
        header => "Authorization: Bearer $access_token",
        timeout => $hash->{timeout},
        sslargs => { SSL_verify_mode => 0 },
    };
    ( my $err, my $msg ) = HttpUtils_BlockingGet($param);
    my $decode_json = eval { decode_json($msg) };
    if ( $err ne "" || $decode_json->{statusCode} ne "" ) {
        Log3 $name, 1,
          "$name - Fehler während " . "Gateway features: $err :: $msg";
    }
    else {
        readingsSingleUpdate( $hash, "gw_features", $msg, 1 );
    }

    # installation features
    my $param = {
        url     => $apiURL . "installations/$installation/features",
        hash    => $hash,
        header  => "Authorization: Bearer $access_token",
        timeout => $hash->{timeout},
        sslargs => { SSL_verify_mode => 0 },
    };
    ( my $err, my $msg ) = HttpUtils_BlockingGet($param);
    my $decode_json = eval { decode_json($msg) };
    if ( $err ne "" || $decode_json->{statusCode} ne "" ) {
        Log3 $name, 1,
          "$name - Fehler während " . "installation features: $err :: $msg";
    }
    else {
        readingsSingleUpdate( $hash, "installation_features", $msg, 1 );
    }

  #Events
  #    my $param        = {
  #        url      => "https://api.viessmann.com/iot/v1/events-history/events",
  #        hash     => $hash,
  #        header   => "Authorization: Bearer $access_token",
  #        data => "gatewaySerial=$gw",
  #        method   => "POST",
  #        timeout  => $hash->{timeout} ,
  #        sslargs  => { SSL_verify_mode => 0 },
  #    };
  #    ( my $err, my $msg ) = HttpUtils_BlockingGet($param);
  #    my $decode_json = eval { decode_json($msg) };
  #	if ( $err ne "" || $decode_json->{statusCode} ne "" ) {
  #			Log3 $name, 1, "$name - Fehler während "
  #				. "events: $err :: $msg";
  #    }
  #    else {
  #        readingsSingleUpdate ( $hash, "events", $msg, 1);
  #    }

    return;
}

sub vitoconnect_getResource {
    my ($hash)       = @_;
    my $name         = $hash->{NAME};
    my $access_token = $hash->{".access_token"};
    my $installation = $hash->{".installation"};
    my $gw           = $hash->{".gw"};
    my $dev          = AttrVal( $name, 'vitoconnect_device', 0 );

    Log3 $name, 4, "$name - enter getResource";
    Log3 $name, 4,
      "$name - access_token: " . substr( $access_token, 0, 20 ) . "...";
    Log3 $name, 4, "$name - installation: $installation";
    Log3 $name, 4, "$name - gw: $gw";
    if ( $access_token eq "" || $installation eq "" || $gw eq "" ) {
        vitoconnect_getCode($hash);
        return;
    }
    my $param = {
        url => $apiURL
          . "installations/$installation/gateways/$gw/devices/$dev/features",
        hash     => $hash,
        header   => "Authorization: Bearer $access_token",
        timeout  => $hash->{timeout},
        sslargs  => { SSL_verify_mode => 0 },
        callback => \&vitoconnect_getResourceCallback
    };
    HttpUtils_NonblockingGet($param);
    return;
}

sub vitoconnect_getResourceCallback {
    my ( $param, $err, $response_body ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ( $err eq "" ) {
        Log3 $name, 4, "$name - getResourceCallback went ok";
        Log3 $name, 5, "$name - Received response: "
          . substr( $response_body, 0, 100 ) . "...";
        my $items = eval { decode_json($response_body) };
        if ($@) {
            readingsSingleUpdate( $hash, "state",
                "JSON error while request: $@", 1 );
            Log3 $name, 1, "$name - JSON error while request: $@";
            InternalTimer( gettimeofday() + $hash->{intervall},
                "vitoconnect_GetUpdate", $hash );
            return;
        }

        if ( !$items->{statusCode} eq "" ) {
            Log3 $name, 4,
                "$name - statusCode: $items->{statusCode} "
              . "errorType: $items->{errorType} "
              . "message: $items->{message} "
              . "error: $items->{error}";
            readingsSingleUpdate(
                $hash,
                "state",
                "statusCode: $items->{statusCode} "
                  . "errorType: $items->{errorType} "
                  . "message: $items->{message} "
                  . "error: $items->{error}",
                1
            );
            if ( $items->{statusCode} eq "401" ) {

                #  EXPIRED TOKEN
                vitoconnect_getRefresh($hash);
                return;
            }
            elsif ( $items->{statusCode} eq "404" ) {

                # DEVICE_NOT_FOUND
                Log3 $name, 1, "$name - Device not found: Optolink prüfen!";
                InternalTimer( gettimeofday() + $hash->{intervall},
                    "vitoconnect_GetUpdate", $hash );
                return;
            }
            elsif ( $items->{statusCode} eq "429" ) {

                # RATE_LIMIT_EXCEEDED
                Log3 $name, 1,
                  "$name - Anzahl der möglichen API Calls in überschritten!";
                InternalTimer( gettimeofday() + $hash->{intervall},
                    "vitoconnect_GetUpdate", $hash );
                return;
            }
            elsif ( $items->{statusCode} eq "502" ) {

                # DEVICE_COMMUNICATION_ERROR error: Bad Gateway
                Log3 $name, 1, "$name - temporärer API Fehler";
                InternalTimer( gettimeofday() + $hash->{intervall},
                    "vitoconnect_GetUpdate", $hash );
                return;
            }
            else {
                Log3 $name, 1, "$name - unbekannter Fehler: "
                  . "Bitte den Entwickler informieren!";
                Log3 $name, 1,
                    "$name - statusCode: $items->{statusCode} "
                  . "errorType: $items->{errorType} "
                  . "message: $items->{message} "
                  . "error: $items->{error}";
                InternalTimer( gettimeofday() + $hash->{intervall},
                    "vitoconnect_GetUpdate", $hash );
                return;
            }
        }

        if ( $hash->{".logResponseOnce"} ) {
            my $dir         = path( AttrVal( "global", "logdir", "log" ) );
            my $file        = $dir->child("resource.json");
            my $file_handle = $file->openw_utf8();
            $file_handle->print( Dumper($items) );
        }

        readingsBeginUpdate($hash);
        foreach ( @{ $items->{data} } ) {
            my $feature    = $_;
            my $properties = $feature->{properties};
            foreach my $key ( keys %$properties ) {
                my $Reading =
                  $RequestList->{ $feature->{feature} . "." . $key };
                if ( !defined($Reading)
                    || AttrVal( $name, 'vitoconnect_raw_readings', 0 ) eq "1" )
                {
                    $Reading = $feature->{feature} . "." . $key;
                }
                my $Type  = $properties->{$key}->{type};
                my $Value = $properties->{$key}->{value};
                if ( $Type eq "array" ) {
                    if ( defined($Value) ) {
                        if ( ref($Value) eq 'ARRAY' ) {
                            my $Array = ( join( ",", @$Value ) );
                            readingsBulkUpdate( $hash, $Reading, $Array );
                            Log3 $name, 5, "$name - $Reading $Array ($Type)";
                        }
                        else {
                            Log3 $name, 4,
                              "$name - Array Workaround for Property: $Reading";
                        }
                    }
                }
                elsif ( $Type eq "Schedule" ) {
                    my $Result = encode_json($Value);
                    readingsBulkUpdate( $hash, $Reading, $Result );
                    Log3 $name, 5, "$name - $Reading: $Result ($Type)";
                }
                else {
                    readingsBulkUpdate( $hash, $Reading, $Value );
                    Log3 $name, 5, "$name - $Reading: $Value ($Type)";
                }
            }
        }
        readingsBulkUpdate( $hash, "state", "last update: " . TimeNow() . "" );
        readingsEndUpdate( $hash, 1 );
    }
    else {
        Log3 $name, 1, "$name - An error occured: $err";
    }
    InternalTimer( gettimeofday() + $hash->{intervall},
        "vitoconnect_GetUpdate", $hash );
    return;
}

sub vitoconnect_action {
    my ( $hash, $feature, $data, $name, $opt, @args ) = @_;
    my $access_token = $hash->{".access_token"};
    my $installation = $hash->{".installation"};
    my $gw           = $hash->{".gw"};
    my $dev          = AttrVal( $name, 'vitoconnect_device', 0 );
    my $param        = {
        url => $apiURLBase
          . "installations/$installation/gateways/$gw/"
          . "devices/$dev/features/$feature",
        hash   => $hash,
        header => "Authorization: Bearer $access_token\r\n"
          . "Content-Type: application/json",
        data    => $data,
        timeout => $hash->{timeout},
        method  => "POST",
        sslargs => { SSL_verify_mode => 0 },
    };
    Log3 $name, 4, "$name - url=$param->{url}";
    Log3 $name, 4, "$name - data=$param->{data}";
    ( my $err, my $msg ) = HttpUtils_BlockingGet($param);
    my $decode_json = eval { decode_json($msg) };

    if ( $err ne "" || $decode_json->{statusCode} ne "" ) {
        Log3 $name, 1, "$name - set $name $opt @args: Fehler während der "
          . "Befehlsausführung: $err :: $msg";
    }
    else { Log3 $name, 3, "$name - set $name $opt @args"; }
    return;
}

sub vitoconnect_StoreKeyValue {
###################################################
    # checks and stores obfuscated keys like passwords
    # based on / copied from FRITZBOX_storePassword
    my ( $hash, $kName, $value ) = @_;
    my $index = $hash->{TYPE} . "_" . $hash->{NAME} . "_" . $kName;
    my $key   = getUniqueId() . $index;
    my $enc   = "";

    if ( eval "use Digest::MD5;1" ) {
        $key = Digest::MD5::md5_hex( unpack "H*", $key );
        $key .= Digest::MD5::md5_hex($key);
    }
    for my $char ( split //, $value ) {
        my $encode = chop($key);
        $enc .= sprintf( "%.2x", ord($char) ^ ord($encode) );
        $key = $encode . $key;
    }
    my $err = setKeyValue( $index, $enc );
    return "error while saving the value - $err" if ( defined($err) );
    return;
}

sub vitoconnect_ReadKeyValue {
#####################################################
    # reads obfuscated value

    my ( $hash, $kName ) = @_;
    my $name = $hash->{NAME};

    my $index = $hash->{TYPE} . "_" . $hash->{NAME} . "_" . $kName;
    my $key   = getUniqueId() . $index;

    my ( $value, $err );

    Log3 $name, 5,
      "$name - ReadKeyValue tries to read value for $kName from file";
    ( $err, $value ) = getKeyValue($index);

    if ( defined($err) ) {
        Log3 $name, 1,
          "$name - ReadKeyValue is unable to read value from file: $err";
        return;
    }

    if ( defined($value) ) {
        if ( eval "use Digest::MD5;1" ) {
            $key = Digest::MD5::md5_hex( unpack "H*", $key );
            $key .= Digest::MD5::md5_hex($key);
        }
        my $dec = '';
        for my $char ( map { pack( 'C', hex($_) ) } ( $value =~ /(..)/g ) ) {
            my $decode = chop($key);
            $dec .= chr( ord($char) ^ ord($decode) );
            $key = $decode . $key;
        }
        return $dec;
    }
    else {
        Log3 $name, 1, "$name - ReadKeyValue could not find key $kName in file";
        return;
    }
    return;
}

1;

=pod
=item device
=item summary support for Viessmann API
=item summary_DE Unterstützung für die Viessmann API
=begin html

<a name="vitoconnect"></a>
<h3>vitoconnect</h3>
<ul>
    <i>vitoconnect</i> implements a device for the Viessmann API
	<a href="https://www.viessmann.de/de/viessmann-apps/vitoconnect.html">Vitoconnect100</a>
    based on investigation of
	<a href="https://github.com/thetrueavatar/Viessmann-Api">thetrueavatar</a><br>
    
	 You need the user and password from the ViCare App account.<br>
	 Attention: This module is limited to one 'installation' per account. If you have two or more heaters use one viessmann account and device for each heater.<br>
	 
	 For details see: <a href="https://wiki.fhem.de/wiki/Vitoconnect">FHEM Wiki (german)</a><br><br>
	 
	 vitoconnect needs the following libraries:
	 <ul>
	 <li>Path::Tiny</li>
	 <li>JSON</li>
	 <li>DateTime</li>
	 </ul>	 
	 	 
	 Use <code>sudo apt install libtypes-path-tiny-perl libjson-perl libdatetime-perl</code> or 
	 install the libraries via cpan. 
	 Otherwise you will get an error message "cannot load module vitoconnect".
	 
	<br><br>
    <a name="vitoconnectdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; vitoconnect &lt;user&gt; &lt;password&gt; &lt;interval&gt;</code><br>
        It is a good idea to use a fake password here an set the correct one later because it is
		readable in the detail view of the device
        <br><br>
        Example:<br>
        <code>define vitoconnect vitoconnect user@mail.xx fakePassword 60</code><br>
        <code>set vitoconnect password correctPassword 60</code>
        <br><br>
                
    </ul>
    <br>
    
    <a name="vitoconnectset"></a>
    <b>Set</b><br>
    <ul>
		<li><code>update</code><br>
			update readings immeadiatlely</li>
		<li><code>clearReadings</code><br>
			clear all readings immeadiatlely</li> 
		<li><code>password passwd</code><br>
			store password in key store</li>
    	<li><code>logResponseOnce</code><br>
			dumps the json response of Viessmann server to entities.json,
			gw.json, actions.json in FHEM log directory</li>
        
		<li><code>HK1-Heizkurve-Niveau shift</code><br>
			set shift of heating curve</li>
		<li><code>HK1-Heizkurve-Steigung slope</code><br>
			set slope of heating curve</li>
      
		<li><code>HK1-Urlaub_Start start</code><br>
			set holiday start time <br>
			start has to look like this: 2019-02-02</li>
		<li><code>HK1-Urlaub_Ende end</code><br>
			set holiday end time <br>
			end has to look like this: 2019-02-16</li>
		<li><code>HK1-Urlaub_unschedule</code> <br>
			remove holiday start and end time </li>
			
		<li><code>HK1-Zeitsteuerung_Heizung schedule</code><br>
			sets the heating schedule in JSON format <br>
			e.g. {"mon":[],"tue":[],"wed":[],"thu":[],"fri":[],"sat":[],"sun":[]} is completly off
			and {"mon":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
			"tue":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
			"wed":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
			"thu":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
			"fri":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
			"sat":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
			"sun":[{"mode":"on","start":"00:00","end":"24:00","position":0}]} is on 24/7</li>
	  
		<li><code>HK1-Betriebsart standby,dhw,dhwAndHeating,forcedReduced,forcedNormal</code> <br>
			sets HK1-Betriebsart to standby,dhw,dhwAndHeating,forcedReduced or forcedNormal</li>
		
		<li><code>HK1-Solltemperatur_comfort_aktiv activate,deactivate</code> <br>
			activate/deactivate comfort temperature</li>
		<li><code>HK1-Solltemperatur_comfort targetTemperature</code><br>
			set comfort target temperatur </li>
		<li><code>HK1-Solltemperatur_eco_aktiv activate,deactivate </code><br>
			activate/deactivate eco temperature</li>
			
		<li><code>HK1-Solltemperatur_normal targetTemperature</code><br>
			sets the normale target temperature where targetTemperature is an
			integer between 3 and 37</li>
		<li><code>HK1-Solltemperatur_reduziert targetTemperature</code><br>
			sets the reduced target temperature where targetTemperature is an
			integer between 3 and 37 </li>
		
		<li><code>HK1-Name name</code><br>
			sets the name of the circuit </li>		
		
		<li><code>WW-einmaliges_Aufladen activate,deactivate</code><br>
			activate or deactivate one time charge for hot water </li>
       
		<li><code>WW-Zirkulationspumpe_Zeitplan  schedule</code><br>
			sets the schedule in JSON format for hot water circulation pump </li>
		<li><code>WW-Zeitplan schedule</code> <br>
			sets the schedule in JSON format for hot water </li>
			
		<li><code>WW-Haupttemperatur targetTemperature</code><br>
			targetTemperature is an integer between 10 and 60<br>
			sets hot water main temperature to targetTemperature </li>
		<li><code>WW-Solltemperatur targetTemperature</code><br>
			targetTemperature is an integer between 10 and 60<br>
			sets hot water temperature to targetTemperature </li>    

		<li><code>Urlaub_Start start</code><br>
			set holiday start time <br>
			start has to look like this: 2019-02-02</li>
		<li><code>Urlaub_Ende end</code><br>
			set holiday end time <br>
			end has to look like this: 2019-02-16</li>
		<li><code>Urlaub_unschedule</code> <br>
			remove holiday start and end time </li>
	   
    </ul>
    <br>

    <a name="vitoconnectget"></a>
    <b>Get</b><br>
    <ul>
        nothing to get here 
    </ul>
    <br>
    
    <a name="vitoconnectattr"></a>
    <b>Attributes</b>
    <ul>
        <code>attr &lt;name&gt; &lt;attribute&gt; &lt;value&gt;</code>
        <br><br>
        See <a href="http://fhem.de/commandref.html#attr">commandref#attr</a> for more info about 
        the attr command.
        <br><br>
        Attributes:
        <ul>
			<li><i>disable</i>:<br>         
                stop communication with Viessmann server  
            </li>
            <li><i>verbose</i>:<br>         
                set the verbosity level  
            </li>
            <li><i>vitoconnect_raw_readings</i>:<br>         
                create readings with plain JSON names like 'heating.circuits.0.heating.curve.slope'
				instead of german identifiers  
            </li>
            <li><i>vitoconnect_gw_readings</i>:<br>         
                create readings from the gateway  
            </li>

            <li><i>vitoconnect_actions_active</i>:<br>
            	create readings for actions e.g. 'heating.circuits.0.heating.curve.setCurve'
            </li>
        </ul>
    </ul>
    
    <a name="vitoconnectreadings"></a>
    <b>Readings</b>
    <br><br>
	 <i>vitoconnect</i> sets one reading for every value delivered by 
	 the API (depends on the type and the settings of your heater and the version of the API!).
	 Already known values will be mapped to clear names. Unknown values will added with their JSON path
	 (e.g. "heating.burner.modulation.value").
	 Please report new readings to the module maintainer. A description of the known reading
	 could be found <a href="https://wiki.fhem.de/wiki/Vitoconnect">here (german)</a>	    
    
</ul>

=end html

=cut

=cut
