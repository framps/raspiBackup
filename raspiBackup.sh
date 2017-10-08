#!/bin/bash
#
#######################################################################################################################
#
# Create and restore a backup of a Raspberry running raspbian or noobs or other OS
#
# Visit http://www.linux-tips-and-tricks.de/raspiBackup for latest code and other details
#
#######################################################################################################################
#
# Erstellt ein Backup einer Raspberry auf der raspbian oder noobs oder andere OS laufen
#
# Besuche http://www.linux-tips-and-tricks.de/raspiBackup um den aktuellen Code zu erhalten sowie weitere Details zu erfahren
#
#######################################################################################################################
#
#    Copyright (C) 2013-2017 framp at linux-tips-and-tricks dot de
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#######################################################################################################################

if [ ! -n "$BASH" ] ;then
   echo "??? ERROR: Unable to execute script. bash interpreter missing."
   echo "??? DEBUG: $(lsof -a -p $$ -d txt | tail -n 1)"
   exit 127
fi

VERSION="0.6.3"

# add pathes if not already set (usually not set in crontab)

if [[ -e /bin/egrep ]]; then
   PATHES="/bin /sbin /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin"
   for p in $PATHES; do
      if ! echo $PATH | /bin/egrep "^$p|:$p" 2>&1 1>/dev/null; then
         [[ -z $PATH ]] && export PATH=$p || export PATH="$p:$PATH"
      fi
   done
fi

grep -iq beta <<< "$VERSION"
IS_BETA=$((! $? ))
grep -iq hotfix <<< "$VERSION"
IS_HOTFIX=$((! $? ))

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}
MYPID=$$

GIT_DATE="$Date: 2017-10-08 21:49:56 +0200$"
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<< $GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<< $GIT_DATE)
GIT_COMMIT="$Sha1: 7227b9f$"
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<< $GIT_COMMIT | sed 's/\$//')

GIT_CODEVERSION="$MYSELF $VERSION, $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"

# some general constants

MYHOMEURL="https://www.linux-tips-and-tricks.de"

DATE=$(date +%Y%m%d-%H%M%S)
HOSTNAME=$(hostname)
NL=$'\n'
CURRENT_DIR=$(pwd)
SCRIPT_DIR=$( cd $( dirname ${BASH_SOURCE[0]}); pwd | xargs readlink -f)

# URLs and temp filenames used

DOWNLOAD_URL="$MYHOMEURL/downloads/raspibackup-sh/download"
PROPERTY_URL="$MYHOMEURL/downloads/raspibackup0613-properties/download"
VERSION_URL_EN="$MYHOMEURL/en/versionhistory"
VERSION_URL_DE="$MYHOMEURL/de/versionshistorie"
LATEST_TEMP_PROPERTY_FILE="/tmp/$MYNAME.properties"
DOWNLOAD_TIMEOUT=3 # seconds
DOWNLOAD_RETRIES=3

# debug option constants

LOG_NONE=0
LOG_DEBUG=1
declare -A LOG_LEVELs=( [$LOG_NONE]="Off" [$LOG_DEBUG]="Debug" )
POSSIBLE_LOG_LEVELs=""
for K in "${!LOG_LEVELs[@]}"; do
	[[ -z $POSSIBLE_LOG_LEVELs ]] && POSSIBLE_LOG_LEVELs="${LOG_LEVELs[$K]}" || POSSIBLE_LOG_LEVELs="$POSSIBLE_LOG_LEVELs | ${LOG_LEVELs[$K]}"
done
declare -A LOG_LEVEL_ARGs
for K in "${!LOG_LEVELs[@]}"; do
	k=$(tr '[:lower:]' '[:upper:]' <<< "${LOG_LEVELs[$K]}")
	LOG_LEVEL_ARGs[$k]="$K"
done

MSG_LEVEL_MINIMAL=0
MSG_LEVEL_DETAILED=1
declare -A MSG_LEVELs=( [$MSG_LEVEL_MINIMAL]="Minimal" [$MSG_LEVEL_DETAILED]="Detailed")
POSSIBLE_MSG_LEVELs=""
for K in "${!MSG_LEVELs[@]}"; do
	[[ -z $POSSIBLE_MSG_LEVELs ]] && POSSIBLE_MSG_LEVELs="${MSG_LEVELs[$K]}" || POSSIBLE_MSG_LEVELs="$POSSIBLE_MSG_LEVELs | ${MSG_LEVELs[$K]}"
done
declare -A MSG_LEVEL_ARGs
for K in "${!MSG_LEVELs[@]}"; do
	k=$(tr '[:lower:]' '[:upper:]' <<< "${MSG_LEVELs[$K]}")
	MSG_LEVEL_ARGs[$k]="$K"
done

# log option constants

LOG_OUTPUT_SYSLOG=0
LOG_OUTPUT_VARLOG=1
LOG_OUTPUT_BACKUPLOC=2
LOG_OUTPUT_HOME=3
declare -A LOG_OUTPUT_LOCs=( [$LOG_OUTPUT_SYSLOG]="/var/log/syslog" [$LOG_OUTPUT_VARLOG]="/var/log/raspiBackup/<hostname>.log" [$LOG_OUTPUT_BACKUPLOC]="<backupPath>" [$LOG_OUTPUT_HOME]="~/raspiBackup.log")

declare -A LOG_OUTPUTs=( [$LOG_OUTPUT_SYSLOG]="Syslog" [$LOG_OUTPUT_VARLOG]="Varlog" [$LOG_OUTPUT_BACKUPLOC]="Backup" [$LOG_OUTPUT_HOME]="Current")
declare -A LOG_OUTPUT_ARGs
for K in "${!LOG_OUTPUTs[@]}"; do
	k=$(tr '[:lower:]' '[:upper:]' <<< "${LOG_OUTPUTs[$K]}")
	LOG_OUTPUT_ARGs[$k]="$K"
done

declare -A LOG_OUTPUT_ARG_REVERSEs
for K in "${!LOG_OUTPUT_ARGs[@]}"; do
	k="${LOG_OUTPUT_ARGs[$K]}"
	LOG_OUTPUT_ARG_REVERSEs[$k]="$K"
done

POSSIBLE_LOG_LOCs=""
for K in "${!LOG_OUTPUT_LOCs[@]}"; do
	[[ -z $POSSIBLE_LOG_LOCs ]] && POSSIBLE_LOG_LOCs="${LOG_OUTPUTs[$K]}: ${LOG_OUTPUT_LOCs[$K]}" || POSSIBLE_LOG_LOCs="$POSSIBLE_LOG_LOCs | ${LOG_OUTPUTs[$K]}: ${LOG_OUTPUT_LOCs[$K]}"
done

# message option constants

LOG_TYPE_MSG=0
LOG_TYPE_DEBUG=1
declare -A LOG_TYPEs=( [$LOG_TYPE_MSG]="MSG" [$LOG_TYPE_DEBUG]="DBG")

BACKUPTYPE_DD="dd"
BACKUPTYPE_DDZ="ddz"
BACKUPTYPE_TAR="tar"
BACKUPTYPE_TGZ="tgz"
BACKUPTYPE_RSYNC="rsync"
declare -A FILE_EXTENSION=( [$BACKUPTYPE_DD]=".img" [$BACKUPTYPE_DDZ]=".img.gz" [$BACKUPTYPE_RSYNC]="" [$BACKUPTYPE_TGZ]=".tgz" [$BACKUPTYPE_TAR]=".tar" )
# map dd/tar to ddz/tgz extension if -z switch is used
declare -A Z_TYPE_MAPPING=( [$BACKUPTYPE_DD]=$BACKUPTYPE_DDZ [$BACKUPTYPE_TAR]=$BACKUPTYPE_TGZ )

readarray -t SORTED < <(for a in "${!FILE_EXTENSION[@]}"; do echo "$a"; done | sort)
ALLOWED_TYPES=""
POSSIBLE_TYPES=""
for K in "${SORTED[@]}"; do
	[[ -z $POSSIBLE_TYPES ]] && POSSIBLE_TYPES=$K || POSSIBLE_TYPES="$POSSIBLE_TYPES|$K"
	lastChar="${K: -1}"
	if [[ $lastChar == "z" ]]; then         # skip tgz and ddz as allowed types, now handled with -z invocation parameter, still accept old types for backward compatibility
		continue
	fi
	[[ -z $ALLOWED_TYPES ]] && ALLOWED_TYPES=$K || ALLOWED_TYPES="$ALLOWED_TYPES|$K"
done

declare -A mountPoints

# various other constants

PRE_BACKUP_EXTENSION="pre"
POST_BACKUP_EXTENSION="post"
EMAIL_EXTENSION="mail"

EMAIL_EXTENSION_PROGRAM="mailext"
EMAIL_MAILX_PROGRAM="mail"
EMAIL_SSMTP_PROGRAM="ssmtp"
EMAIL_SENDEMAIL_PROGRAM="sendEmail"
SUPPORTED_EMAIL_PROGRAM_REGEX="^($EMAIL_MAILX_PROGRAM|$EMAIL_SSMTP_PROGRAM|$EMAIL_SENDEMAIL_PROGRAM|$EMAIL_EXTENSION_PROGRAM)$"
SUPPORTED_MAIL_PROGRAMS=$(echo $SUPPORTED_EMAIL_PROGRAM_REGEX | sed 's:^..\(.*\)..$:\1:' | sed 's/|/,/g')

PARTITIONS_TO_BACKUP_ALL="*"
TEMPORARY_MOUNTPOINT_ROOT="/tmp"

NEWS_AVAILABLE=0
LOG_INDENT=0

PROPERTY_REGEX='.*="([^"]*)"'
NOOP_AO_ARG_REGEX="^[[:space:]]*:"

STOPPED_SERVICES=0

# possible script exit codes

RC_ASSERTION=101
RC_MISC_ERROR=102
RC_CTRLC=103
RC_EXTENSION_ERROR=104
RC_STOP_SERVICES_ERROR=105
RC_START_SERVICES_ERROR=106
RC_PARAMETER_ERROR=107
RC_MISSING_FILES=108
RC_NATIVE_BACKUP_FAILED=109
RC_LINK_FILE_FAILED=110
RC_COLLECT_PARTITIONS_FAILED=111
RC_CREATE_PARTITIONS_FAILED=112
RC_NATIVE_RESTORE_FAILED=113
RC_DD_IMG_FAILED=114
RC_SDCARD_ERROR=115
RC_RESTORE_FAILED=116
RC_NATIVE_RESTORE_FAILED=117
RC_DEVICES_NOTFOUND=118
RC_CREATE_ERROR=119

LOGGING_ENABLED=0

tty -s
INTERACTIVE=!$?

#################################################################################
# --- Messages in English and German
#################################################################################

# supported languages

MSG_EN=1      # english	(default)
MSG_DE=1      # german

declare -A MSG_EN
declare -A MSG_DE

MSG_UNDEFINED=0
MSG_EN[$MSG_UNDEFINED]="RBK0000E: Undefined messageid"
MSG_DE[$MSG_UNDEFINED]="RBK0000E: Unbekannte Meldungsid"
MSG_ASSERTION_FAILED=1
MSG_EN[$MSG_ASSERTION_FAILED]="RBK0001E: Unexpected program error occured. Git commit: %1, Linenumber: %2, Error: %3."
MSG_DE[$MSG_ASSERTION_FAILED]="RBK0001E: Unerwarteter Programmfehler trat auf. Git commit: %1, Zeile: %1, Fehler: %3."
MSG_RUNASROOT=2
MSG_EN[$MSG_RUNASROOT]="RBK0002E: $MYSELF has to be started as root. Try 'sudo %1 %2'."
MSG_DE[$MSG_RUNASROOT]="RBK0002E: $MYSELF muss als root gestartet werden. Benutze 'sudo %1 %2'."
MSG_TRUNCATING_TO_USED_PARTITIONS_ONLY=3
MSG_EN[$MSG_TRUNCATING_TO_USED_PARTITIONS_ONLY]="RBK0003I: Backup size will be truncated from %1 to %2."
MSG_DE[$MSG_TRUNCATING_TO_USED_PARTITIONS_ONLY]="RBK0003I: Backupgröße wird von %1 auf %2 reduziert."
MSG_ADJUSTING_SECOND=4
MSG_EN[$MSG_ADJUSTING_SECOND]="RBK0004W: Adjusting second partition from %1 to %2."
MSG_DE[$MSG_ADJUSTING_SECOND]="RBK0004W: Zweite Partition wird von %1 auf %2 angepasst."
MSG_BACKUP_FAILED=5
MSG_EN[$MSG_BACKUP_FAILED]="RBK0005E: Backup failed. Check previous error messages for details."
MSG_DE[$MSG_BACKUP_FAILED]="RBK0005E: Backup fehlerhaft beendet. Siehe vorhergehende Fehlermeldungen."
MSG_ADJUSTING_WARNING=6
MSG_EN[$MSG_ADJUSTING_WARNING]="RBK0006W: Target %1 with %2 is smaller than backup source with %3. root partition will be truncated accordingly. NOTE: Restore may fail if the root partition will become too small."
MSG_DE[$MSG_ADJUSTING_WARNING]="RBK0006W: Ziel %1 mit %2 ist kleiner als die Backupquelle mit %3. Die root Partition wird entsprechend verkleinert. HINWEIS: Der Restore kann fehlschlagen wenn sie zu klein wird."
MSG_STARTING_SERVICES=7
MSG_EN[$MSG_STARTING_SERVICES]="RBK0007I: Starting services: '%1'."
MSG_DE[$MSG_STARTING_SERVICES]="RBK0007I: Services werden gestartet: '%1'."
MSG_STOPPING_SERVICES=8
MSG_EN[$MSG_STOPPING_SERVICES]="RBK0008I: Stopping services: '%1'."
MSG_DE[$MSG_STOPPING_SERVICES]="RBK0008I: Services werden gestoppt: '%1'."
MSG_STARTED=9
MSG_EN[$MSG_STARTED]="RBK0009I: %1: %2 V%3 (%5) started at %4."
MSG_DE[$MSG_STARTED]="RBK0009I: %1: %2 V%3 (%5) um %4 gestartet."
MSG_STOPPED=10
MSG_EN[$MSG_STOPPED]="RBK0010I: %1: %2 V%3 (%5) stopped at %4."
MSG_DE[$MSG_STOPPED]="RBK0010I: %1: %2 V%3 (%5) um %4 beendet."
MSG_NO_BOOT_PARTITION=11
MSG_EN[$MSG_NO_BOOT_PARTITION]="RBK0011E: No boot partition ${BOOT_PARTITION_PREFIX}1 found."
MSG_DE[$MSG_NO_BOOT_PARTITION]="RBK0011E: Keine boot Partition ${BOOT_PARTITION_PREFIX}1 gefunden."
MSG_DD_BACKUP_NOT_POSSIBLE_FOR_PARTITIONBASED_BACKUP=12
MSG_EN[$MSG_DD_BACKUP_NOT_POSSIBLE_FOR_PARTITIONBASED_BACKUP]="RBK0012E: DD backup not possible for partition based backup."
MSG_DE[$MSG_DD_BACKUP_NOT_POSSIBLE_FOR_PARTITIONBASED_BACKUP]="RBK0012E: DD Backup nicht möglich bei partitionsbasiertem Backup."
MSG_MULTIPLE_PARTITIONS_FOUND=13
MSG_EN[$MSG_MULTIPLE_PARTITIONS_FOUND]="RBK0013E: More than two partitions detected which can be saved only with backuptype DD or DDZ or with option -P."
MSG_DE[$MSG_MULTIPLE_PARTITIONS_FOUND]="RBK0013E: Es existieren mehr als zwei Partitionen, die nur mit dem Backuptype DD oder DDZ oder der Option -P gesichert werden können."
MSG_EMAIL_PROG_NOT_SUPPORTED=14
MSG_EN[$MSG_EMAIL_PROG_NOT_SUPPORTED]="RBK0014E: eMail program %1 not supported. Supported are %2"
MSG_DE[$MSG_EMAIL_PROG_NOT_SUPPORTED]="RBK0014E: eMail Programm %1 ist nicht unterstützt. Möglich sind %2"
MSG_INSTANCE_ACTIVE=15
MSG_EN[$MSG_INSTANCE_ACTIVE]="RBK0015E: There is already an instance of $MYNAME up and running"
MSG_DE[$MSG_INSTANCE_ACTIVE]="RBK0015E: Es ist schon eine Instanz von $MYNAME aktiv."
MSG_NO_SDCARD_FOUND=16
MSG_EN[$MSG_NO_SDCARD_FOUND]="RBK0016E: No sd card %1 found."
MSG_DE[$MSG_NO_SDCARD_FOUND]="RBK0016E: Keine SD Karte %1 gefunden."
MSG_BACKUP_OK=17
MSG_EN[$MSG_BACKUP_OK]="RBK0017I: Backup finished successfully."
MSG_DE[$MSG_BACKUP_OK]="RBK0017I: Backup erfolgreich beendet."
MSG_ADJUSTING_WARNING2=18
MSG_EN[$MSG_ADJUSTING_WARNING2]="RBK0018W: Target %1 with %2 is larger than backup source with %3. root partition will be expanded accordingly to use the whole space."
MSG_DE[$MSG_ADJUSTING_WARNING2]="RBK0018W: Ziel %1 mit %2 ist größer als die Backupquelle mit %3. Die root Partition wird entsprechend vergrößert um den ganzen Platz zu benutzen."
MSG_MISSING_START_STOP=19
MSG_EN[$MSG_MISSING_START_STOP]="RBK0019E: Missing option -a and -o."
MSG_DE[$MSG_MISSING_START_STOP]="RBK0019E: Option -a und -o nicht angegeben."
MSG_FILESYSTEM_INCORRECT=20
MSG_EN[$MSG_FILESYSTEM_INCORRECT]="??? RBK0020E: Filesystem of rsync backup directory %1 seems not to support hardlinks. Use option -5 to disable this check if you are sure hardlinks are supported."
MSG_DE[$MSG_FILESYSTEM_INCORRECT]="??? RBK0020E: Dateisystem des rsync Backupverzeichnisses %1 scheint keine Hardlinks zu unterstützen. Mit der Option -5 kann diese Prüfung ausgeschaltet werden wenn Hardlinks doch unterstützt sind."
MSG_BACKUP_PROGRAM_ERROR=21
MSG_EN[$MSG_BACKUP_PROGRAM_ERROR]="RBK0021E: Backupprogram for type %1 failed with RC %2."
MSG_DE[$MSG_BACKUP_PROGRAM_ERROR]="RBK0021E: Backupprogramm des Typs %1 beendete sich mit RC %2."
MSG_UNKNOWN_BACKUPTYPE=22
MSG_EN[$MSG_UNKNOWN_BACKUPTYPE]="RBK0022E: Unknown backuptype %1."
MSG_DE[$MSG_UNKNOWN_BACKUPTYPE]="RBK0022E: Unbekannter Backtyp %1."
MSG_KEEPBACKUP_INVALID=23
MSG_EN[$MSG_KEEPBACKUP_INVALID]="RBK0023E: Invalid parameter %1 for -k."
MSG_DE[$MSG_KEEPBACKUP_INVALID]="RBK0023E: Ungültiger Parameter %1 für -k."
MSG_TOOL_ERROR=24
MSG_EN[$MSG_TOOL_ERROR]="RBK0024E: Backup tool %1 received an error. $NL%2."
MSG_DE[$MSG_TOOL_ERROR]="RBK0024E: Backupprogramm %1 hat einen Fehler bekommen. $NL%2."
MSG_DIR_TO_BACKUP_DOESNOTEXIST=25
MSG_EN[$MSG_DIR_TO_BACKUP_DOESNOTEXIST]="RBK0025E: Backupdirectory %1 does not exist."
MSG_DE[$MSG_DIR_TO_BACKUP_DOESNOTEXIST]="RBK0025E: Backupverzeichnis %1 existiert nicht."
MSG_SAVING_LOG=26
MSG_EN[$MSG_SAVING_LOG]="RBK0026I: Saving logfile in %1."
MSG_DE[$MSG_SAVING_LOG]="RBK0026I: Logdatei wird in %1 gesichert."
MSG_NO_DEVICEMOUNTED=27
MSG_EN[$MSG_NO_DEVICEMOUNTED]="RBK0027E: No external device mounted on %1. SD card would be used for backup."
MSG_DE[$MSG_NO_DEVICEMOUNTED]="RBK0027E: Kein externes Gerät an %1 verbunden. Die SD Karte würde für das Backup benutzt werden."
MSG_SHELL_ERROR=28
MSG_EN[$MSG_SHELL_ERROR]="RBK0028E: Command %1 received an error. $NL%2."
MSG_DE[$MSG_SHELL_ERROR]="RBK0028E: Befehl %1 hat einen Fehler bekommen. $NL %2."
MSG_MPACK_NOT_INSTALLED=29
MSG_EN[$MSG_MPACK_NOT_INSTALLED]="RBK0029E: Mail program mpack not installed to send emails. No log can be attached to the eMail."
MSG_DE[$MSG_MPACK_NOT_INSTALLED]="RBK0029E: Mail Program mpack is nicht installiert. Es kann kein Log an die eMail angehängt werden."
MSG_IMG_DD_FAILED=30
MSG_EN[$MSG_IMG_DD_FAILED]="RBK0030E: %1 file creation with dd failed with RC %2."
MSG_DE[$MSG_IMG_DD_FAILED]="RBK0030E: %1 Datei Erzeugung mit dd endet fahlerhaft mit RC %2."
MSG_CHECKING_FOR_NEW_VERSION=31
MSG_EN[$MSG_CHECKING_FOR_NEW_VERSION]="RBK0031I: Checking whether new version is available."
MSG_DE[$MSG_CHECKING_FOR_NEW_VERSION]="RBK0031I: Prüfe ob neue Version verfügbar ist."
MSG_INVALID_LOG_LEVEL=32
MSG_EN[$MSG_INVALID_LOG_LEVEL]="RBK0032W: Invalid parameter %1 for -l detected. Using %2."
MSG_DE[$MSG_INVALID_LOG_LEVEL]="RBK0032W: Ungültiger Parameter %1 für -l eingegeben. Es wird %2 benutzt."
MSG_INVALID_LOG_OUTPUT=33
MSG_EN[$MSG_INVALID_LOG_OUTPUT]="RBK0033W: Invalid parameter %1 for -L detected. Using %2."
MSG_DE[$MSG_INVALID_LOG_OUTPUT]="RBK0032W: Ungültiger Parameter %1 für -L eingegeben. Es wird %2 benutzt."
MSG_FILE_NOT_FOUND=34
MSG_EN[$MSG_FILE_NOT_FOUND]="RBK0034E: File %1 not found."
MSG_DE[$MSG_FILE_NOT_FOUND]="RBK0034E: Datei %1 nicht gefunden."
MSG_RESTORE_PROGRAM_ERROR=35
MSG_EN[$MSG_RESTORE_PROGRAM_ERROR]="RBK0035E: Backupprogram %1 failed during restore with RC %2."
MSG_DE[$MSG_RESTORE_PROGRAM_ERROR]="RBK0035E: Backupprogramm %1 endete beim Restore mit RC %2."
MSG_BACKUP_CREATING_PARTITION_INFO=36
MSG_EN[$MSG_BACKUP_CREATING_PARTITION_INFO]="RBK0036I: Saving partition layout."
MSG_DE[$MSG_BACKUP_CREATING_PARTITION_INFO]="RBK0036I: Partitionslayout wird gesichert."
MSG_ANSWER_CHARS_YES=37
MSG_EN[$MSG_ANSWER_CHARS_YES]="Yy"
MSG_DE[$MSG_ANSWER_CHARS_YES]="Jj"
MSG_ANSWER_YES_NO=38
MSG_EN[$MSG_ANSWER_YES_NO]="RBK0038I: Are you sure? %1."
MSG_DE[$MSG_ANSWER_YES_NO]="RBK0038I: Bist Du sicher? %1."
MSG_MAILPROGRAM_NOT_INSTALLED=39
MSG_EN[$MSG_MAILPROGRAM_NOT_INSTALLED]="RBK0039E: Mail program %1 not installed to send emails."
MSG_DE[$MSG_MAILPROGRAM_NOT_INSTALLED]="RBK0039E: Mail Program %1 ist nicht installiert um eMail szu senden."
MSG_INCOMPATIBLE_UPDATE=40
MSG_EN[$MSG_INCOMPATIBLE_UPDATE]="RBK0040W: New version %1 has some incompatibilities to previous versions. Please read %2 and use option -S together with option -U to update script."
MSG_DE[$MSG_INCOMPATIBLE_UPDATE]="RBK0040W: Die neue Version %1 hat inkompatible Änderungen zu vorhergehenden Versionen. Bitte %2 lesen und dann die Option -S zusammen mit -U benutzen um das Script zu updaten."
MSG_TITLE_OK=41
MSG_EN[$MSG_TITLE_OK]="%1: Backup finished successfully."
MSG_DE[$MSG_TITLE_OK]="%1: Backup erfolgreich beendet."
MSG_TITLE_ERROR=42
MSG_EN[$MSG_TITLE_ERROR]="%1: Backup failed !!!."
MSG_DE[$MSG_TITLE_ERROR]="%1: Backup nicht erfolgreich !!!."
MSG_REMOVING_BACKUP=43
MSG_EN[$MSG_REMOVING_BACKUP]="RBK0043I: Removing incomplete backup in %1 (May take some time. Please be patient)."
MSG_DE[$MSG_REMOVING_BACKUP]="RBK0043I: Unvollständiges Backup %1 in wird gelöscht (Kann etwas dauern. Bitte etwas Geduld)."
MSG_CREATING_BOOT_BACKUP=44
MSG_EN[$MSG_CREATING_BOOT_BACKUP]="RBK0044I: Creating backup of boot partition in %1."
MSG_DE[$MSG_CREATING_BOOT_BACKUP]="RBK0044I: Backup der Bootpartition wird in %1 erstellt."
MSG_CREATING_PARTITION_BACKUP=45
MSG_EN[$MSG_CREATING_PARTITION_BACKUP]="RBK0045I: Creating backup of partition layout in %1."
MSG_DE[$MSG_CREATING_PARTITION_BACKUP]="RBK0044I: Backup des Partitionlayouts wird in %1 erstellt."
MSG_CREATING_MBR_BACKUP=46
MSG_EN[$MSG_CREATING_MBR_BACKUP]="RBK0046I: Creating backup of master boot record in %1."
MSG_DE[$MSG_CREATING_MBR_BACKUP]="RBK0046I: Backup des Masterbootrecords wird in %1 erstellt."
MSG_START_SERVICES_FAILED=47
MSG_EN[$MSG_START_SERVICES_FAILED]="RBK0047E: Error occured when starting services."
MSG_DE[$MSG_START_SERVICES_FAILED]="RBK0047E: Ein Fehler trat beim Starten von Services auf."
MSG_STOP_SERVICES_FAILED=48
MSG_EN[$MSG_STOP_SERVICES_FAILED]="RBK0048E: Error occured when stopping services. RC %1."
MSG_DE[$MSG_STOP_SERVICES_FAILED]="RBK0048E: Ein Fehler trat beim Beenden von Services auf. RC %1."
MSG_FILES_CHANGE_DURING_BACKUP=49
MSG_EN[$MSG_FILES_CHANGE_DURING_BACKUP]="RBK0049W: Some files were changed or vanished during backup. RC %1 - ignoring change."
MSG_DE[$MSG_FILES_CHANGE_DURING_BACKUP]="RBK0049W: Einige Dateien haben sich während des Backups geändert oder sind verschwunden. RC %1 - Änderung wird ignoriert."
MSG_RESTORING_FILE=50
MSG_EN[$MSG_RESTORING_FILE]="RBK0050I: Restoring backup from %1."
MSG_DE[$MSG_RESTORING_FILE]="RBK0050I: Backup wird von %1 zurückgespielt."
MSG_RESTORING_MBR=51
MSG_EN[$MSG_RESTORING_MBR]="RBK0051I: Restoring mbr from %1 to %2."
MSG_DE[$MSG_RESTORING_MBR]="RBK0051I: Master boot backup wird von %1 auf %2 zurückgespielt."
MSG_CREATING_PARTITIONS=52
MSG_EN[$MSG_CREATING_PARTITIONS]="RBK0052I: Creating partition(s) on %1."
MSG_DE[$MSG_CREATING_PARTITIONS]="RBK0052I: Partition(en) werden auf %1 erstellt."
MSG_RESTORING_FIRST_PARTITION=53
MSG_EN[$MSG_RESTORING_FIRST_PARTITION]="RBK0053I: Restoring first partition (boot partition) to %1."
MSG_DE[$MSG_RESTORING_FIRST_PARTITION]="RBK0053I: Erste Partition (Bootpartition) wird auf %1 zurückgespielt."
MSG_FORMATTING_SECOND_PARTITION=54
MSG_EN[$MSG_FORMATTING_SECOND_PARTITION]="RBK0054I: Formating second partition (root partition) %1."
MSG_DE[$MSG_FORMATTING_SECOND_PARTITION]="RBK0054I: Zweite Partition (Rootpartition) %1 wird formatiert."
MSG_RESTORING_SECOND_PARTITION=55
MSG_EN[$MSG_RESTORING_SECOND_PARTITION]="RBK0055I: Restoring second partition (root partition) %1."
MSG_DE[$MSG_RESTORING_SECOND_PARTITION]="RBK0055I: Zweite Partition (Rootpartition) %1 wird zurückgespielt."
MSG_DEPLOYMENT_PARMS_ERROR=56
MSG_EN[$MSG_DEPLOYMENT_PARMS_ERROR]="RBK0056E: Incorrect deployment parameters. Use <hostname>@<username>."
MSG_DE[$MSG_DEPLOYMENT_PARMS_ERROR]="RBK0056E: Ungültige Deploymentparameter. Erforderliches Format: <hostname>@<username>."
MSG_DOWNLOADING=57
MSG_EN[$MSG_DOWNLOADING]="RBK0057I: Downloading file %1 from %2."
MSG_DE[$MSG_DOWNLOADING]="RBK0057I: Datei %1 wird von %2 downloaded."
MSG_INVALID_MSG_LEVEL=58
MSG_EN[$MSG_INVALID_MSG_LEVEL]="RBK0058W: Invalid parameter %1 for -m detected. Using %2."
MSG_DE[$MSG_INVALID_MSG_LEVEL]="RBK0058W: Ungültiger Parameter %1 für -m eingegeben. Es wird %2 benutzt."
MSG_INVALID_LOG_OUTPUT=59
MSG_EN[$MSG_INVALID_LOG_OUTPUT]="RBK0059W: Invalid parameter %1 for -L detected. Using %2."
MSG_DE[$MSG_INVALID_LOG_OUTPUT]="RBK0059W: Ungültiger Parameter %1 für -L eingegeben. Es wird %2 benutzt."
MSG_NO_YES=60
MSG_EN[$MSG_NO_YES]="no yes"
MSG_DE[$MSG_NO_YES]="nein ja"
MSG_BOOTPATITIONFILES_NOT_FOUND=61
MSG_EN[$MSG_BOOTPATITIONFILES_NOT_FOUND]="RBK0061E: Unable to find bootpartition starting with %2 in %1."
MSG_DE[$MSG_BOOTPATITIONFILES_NOT_FOUND]="RBK0061E: Keine Bootpartitionsdateien in %1 gefunden die mit %2 beginnen."
MSG_NO_RESTOREDEVICE_DEFINED=62
MSG_EN[$MSG_NO_RESTOREDEVICE_DEFINED]="RBK0062E: No restoredevice defined (Example: /dev/sda)."
MSG_DE[$MSG_NO_RESTOREDEVICE_DEFINED]="RBK0062E: Kein Zurückspielgerät ist definiert (Beispiel: /dev/sda)."
MSG_NO_RESTOREDEVICE_FOUND=63
MSG_EN[$MSG_NO_RESTOREDEVICE_FOUND]="RBK0063E: Restoredevice %1 not found (Example: /dev/sda)."
MSG_DE[$MSG_NO_RESTOREDEVICE_FOUND]="RBK0063E: Zurückspielgerät %1 existiert nicht (Beispiel: /dev/sda)."
MSG_ROOT_PARTTITION_NOT_FOUND=64
MSG_EN[$MSG_ROOT_PARTTITION_NOT_FOUND]="RBK0064E: Partition for rootpartition %1 not found (Example: /dev/sdb1)."
MSG_DE[$MSG_ROOT_PARTTITION_NOT_FOUND]="RBK0064E: Partition für die Rootpartition %1 nicht gefunden (Beispiel: /dev/sda)."
MSG_REPARTITION_WARNING=65
MSG_EN[$MSG_REPARTITION_WARNING]="RBK0065W: Device %1 will be repartitioned and all data will be lost."
MSG_DE[$MSG_REPARTITION_WARNING]="RBK0065W: Gerät %1 wird repartitioniert und die gesamten Daten werden gelöscht."
MSG_WARN_RESTORE_DEVICE_OVERWRITTEN=66
MSG_EN[$MSG_WARN_RESTORE_DEVICE_OVERWRITTEN]="RBK0066W: Device %1 will be overwritten with the saved boot and root partition."
MSG_DE[$MSG_WARN_RESTORE_DEVICE_OVERWRITTEN]="RBK0066W: Gerät %1 wird überschrieben mit der gesicherten Boot- und Rootpartition."
MSG_CURRENT_PARTITION_TABLE=67
MSG_EN[$MSG_CURRENT_PARTITION_TABLE]="RBK0067I: Current partitions on %1:$NL%2"
MSG_DE[$MSG_CURRENT_PARTITION_TABLE]="RBK0067I: Momentane Partitionen auf %1:$NL%2"
MSG_BOOTPATITIONFILES_FOUND=68
MSG_EN[$MSG_BOOTPATITIONFILES_FOUND]="RBK0068I: Using bootpartition backup files starting with %2 from directory %1."
MSG_DE[$MSG_BOOTPATITIONFILES_FOUND]="RBK0068I: Bootpartitionsdateien des Backups aus dem Verzeichnis %1 die mit %2 beginnen werden benutzt."
MSG_WARN_BOOT_PARTITION_OVERWRITTEN=69
MSG_EN[$MSG_WARN_BOOT_PARTITION_OVERWRITTEN]="RBK0069W: Bootpartition %1 will be formatted and will get the restored Boot partition."
MSG_DE[$MSG_WARN_BOOT_PARTITION_OVERWRITTEN]="RBK0069W: Bootpartition %1 wird formatiert und erhält die zurückgespielte Bootpartition."
MSG_WARN_ROOT_PARTITION_OVERWRITTEN=70
MSG_EN[$MSG_WARN_ROOT_PARTITION_OVERWRITTEN]="RBK0070W: Rootpartition %1 will be formatted and will get the restored Root partition."
MSG_DE[$MSG_WARN_ROOT_PARTITION_OVERWRITTEN]="RBK0070W: Rootpartition %1 wird formatiert und erhält die zurückgespielte Rootpartition."
MSG_QUERY_CHARS_YES_NO=71
MSG_EN[$MSG_QUERY_CHARS_YES_NO]="y/N"
MSG_DE[$MSG_QUERY_CHARS_YES_NO]="j/N"
MSG_SCRIPT_UPDATE_OK=72
MSG_EN[$MSG_SCRIPT_UPDATE_OK]="RBK0072I: %1 updated from version %2 to version %3. Previous version saved as %4."
MSG_DE[$MSG_SCRIPT_UPDATE_OK]="RBK0072I: %1 von Version %2 durch die aktuelle Version %3 ersetzt. Die vorherige Verion wurde als %4 gesichert."
MSG_SCRIPT_UPDATE_NOT_NEEDED=73
MSG_EN[$MSG_SCRIPT_UPDATE_NOT_NEEDED]="RBK0073I: %1 already current with version %2."
MSG_DE[$MSG_SCRIPT_UPDATE_NOT_NEEDED]="RBK0073I: %1 bereits auf der aktuellen Version %2."
MSG_SCRIPT_UPDATE_FAILED=74
MSG_EN[$MSG_SCRIPT_UPDATE_FAILED]="RBK0074E: Failed to update %1."
MSG_DE[$MSG_SCRIPT_UPDATE_FAILED]="RBK0074E: %1 konnte nicht ersetzt werden."
MSG_LINK_BOOTPARTITIONFILES=75
MSG_EN[$MSG_LINK_BOOTPARTITIONFILES]="RBK0075I: Using hardlinks to reuse bootpartition backups."
MSG_DE[$MSG_LINK_BOOTPARTITIONFILES]="RBK0075I: Hardlinks werden genutzt um Bootpartitionsbackups wiederzuverwenden."
MSG_RESTORE_OK=76
MSG_EN[$MSG_RESTORE_OK]="RBK0076I: Restore finished successfully."
MSG_DE[$MSG_RESTORE_OK]="RBK0076I: Restore erfolgreich beendet."
MSG_RESTORE_FAILED=77
MSG_EN[$MSG_RESTORE_FAILED]="RBK0077E: Restore failed with RC %1. Check previous error messages."
MSG_DE[$MSG_RESTORE_FAILED]="RBK0077E: Restore wurde fehlerhaft mit RC %1 beendet. Siehe vorhergehende Fehlermeldungen."
MSG_SCRIPT_UPDATE_NOT_UPLOADED=78
MSG_EN[$MSG_SCRIPT_UPDATE_NOT_UPLOADED]="RBK0078I: %1 with version %2 is newer than uploaded version %3."
MSG_DE[$MSG_SCRIPT_UPDATE_NOT_UPLOADED]="RBK0078I: %1 mit der Version %2 ist neuer als die uploaded Version %3."
MSG_UNKNOWN_BACKUPTYPE_FOR_ZIP=79
MSG_EN[$MSG_UNKNOWN_BACKUPTYPE_FOR_ZIP]="RBK0079E: Option -z not allowed with backuptype %1."
MSG_DE[$MSG_UNKNOWN_BACKUPTYPE_FOR_ZIP]="RBK0079E: Option -z ist für Backuptyp %1 nicht erlaubt."
MSG_NEW_VERSION_AVAILABLE=80
MSG_EN[$MSG_NEW_VERSION_AVAILABLE]="RBK0080I: ;-) There is a new version %1 of $MYNAME available for download. You are running version %2 and now can use option -U to upgrade your local version. Visit $VERSION_URL_EN to read the version changes"
MSG_DE[$MSG_NEW_VERSION_AVAILABLE]="RBK0080I: ;-) Es gibt eine neue Version %1 von $MYNAME zum downloaden. Die momentan benutze Version ist %2 und es kann mit der Option -U die lokale Version aktualisiert werden. Besuche $VERSION_URL_DE um die Änderungen in der Version zu erfahren"
MSG_BACKUP_TARGET=81
MSG_EN[$MSG_BACKUP_TARGET]="RBK0081I: Creating backup of type %1 in %2."
MSG_DE[$MSG_BACKUP_TARGET]="RBK0081I: Backup vom Typ %1 wird in %2 erstellt."
MSG_EXISTING_BOOT_BACKUP=82
MSG_EN[$MSG_EXISTING_BOOT_BACKUP]="RBK0082I: Backup of boot partition alreday exists in %1."
MSG_DE[$MSG_EXISTING_BOOT_BACKUP]="RBK0082I: Backup der Bootpartition in %1 existiert schon."
MSG_EXISTING_PARTITION_BACKUP=83
MSG_EN[$MSG_EXISTING_PARTITION_BACKUP]="RBK0083I: Backup of partition layout already exists in %1."
MSG_DE[$MSG_EXISTING_PARTITION_BACKUP]="RBK0083I: Backup des Partitionlayouts in %1 existiert schon."
MSG_EXISTING_MBR_BACKUP=84
MSG_EN[$MSG_EXISTING_MBR_BACKUP]="RBK0084I: Backup of master boot record already exists in %1."
MSG_DE[$MSG_EXISTING_MBR_BACKUP]="RBK0084I: Backup des Masterbootrecords in %1 existiert schon."
MSG_BACKUP_STARTED=85
MSG_EN[$MSG_BACKUP_STARTED]="RBK0085I: Backup of type %1 started. Please be patient."
MSG_DE[$MSG_BACKUP_STARTED]="RBK0085I: Backuperstellung vom Typ %1 gestartet. Bitte etwas Geduld."
MSG_RESTOREDEVICE_IS_PARTITION=86
MSG_EN[$MSG_RESTOREDEVICE_IS_PARTITION]="RBK0086E: Restore device cannot be a partition."
MSG_DE[$MSG_RESTOREDEVICE_IS_PARTITION]="RBK0086E: Wiederherstellungsgerät darf keine Partition sein."
MSG_RESTORE_FILE_INVALID=87
MSG_EN[$MSG_RESTORE_FILE_INVALID]="RBK0087E: Invalid restore file or directory %1."
MSG_DE[$MSG_RESTORE_FILE_INVALID]="RBK0087E: Wiederherstellungsdatei %1 ist ungültig."
MSG_RESTORE_DEVICE_NOT_VALID=88
MSG_EN[$MSG_RESTORE_DEVICE_NOT_VALID]="RBK0088E: -R option not supported for partitionbased backup."
MSG_DE[$MSG_RESTORE_DEVICE_NOT_VALID]="RBK0088E: Option -R wird nicht beim partitionbasierten Backup unterstützt."
MSG_UNKNOWN_OPTION=89
MSG_EN[$MSG_UNKNOWN_OPTION]="RBK0089E: Unknown option %1."
MSG_DE[$MSG_UNKNOWN_OPTION]="RBK0089E: Unbekannte Option %1."
MSG_OPTION_REQUIRES_PARAMETER=90
MSG_EN[$MSG_OPTION_REQUIRES_PARAMETER]="RBK0090E: Option %1 requires a parameter."
MSG_DE[$MSG_OPTION_REQUIRES_PARAMETER]="RBK0090E: Option %1 erwartet ein Argument."
MSG_MENTION_HELP=91
MSG_EN[$MSG_MENTION_HELP]="RBK0091I: Invoke '%1 -h' to get more detailed information of all script invocation parameters."
MSG_DE[$MSG_MENTION_HELP]="RBK0091I: '%1 -h' liefert eine detailierte Beschreibung aller Scriptaufrufoptionen."
MSG_PROCESSING_PARTITION=92
MSG_EN[$MSG_PROCESSING_PARTITION]="RBK0092I: Saving partition %1 (%2) ..."
MSG_DE[$MSG_PROCESSING_PARTITION]="RBK0092I: Partition %1 (%2) wird gesichert ..."
MSG_PARTITION_NOT_FOUND=93
MSG_EN[$MSG_PARTITION_NOT_FOUND]="RBK0093E: Partition %1 specified with option -T not found."
MSG_DE[$MSG_PARTITION_NOT_FOUND]="RBK0093E: Angegebene Partition %1 der Option -T existiert nicht."
MSG_PARTITION_NUMBER_INVALID=94
MSG_EN[$MSG_PARTITION_NUMBER_INVALID]="RBK0094E: Parameter '%1' specified in option -T is not a number."
MSG_DE[$MSG_PARTITION_NUMBER_INVALID]="RBK0094E: Angegebener Parameter '%1' der Option -T ist keine Zahl."
MSG_RESTORING_PARTITIONFILE=95
MSG_EN[$MSG_RESTORING_PARTITIONFILE]="RBK0095I: Restoring partition %1."
MSG_DE[$MSG_RESTORING_PARTITIONFILE]="RBK0095I: Backup wird auf partition %1 zurückgespielt."
MSG_LANGUAGE_NOT_SUPPORTED=96
MSG_EN[$MSG_LANGUAGE_NOT_SUPPORTED]="RBK0096E: Language %1 not supported."
MSG_DE[$MSG_LANGUAGE_NOT_SUPPORTED]="RBK0096E: Die Sprache %1 wird nicht unterstützt."
MSG_PARTITIONING_SDCARD=97
MSG_EN[$MSG_PARTITIONING_SDCARD]="RBK0097I: Partitioning and formating %1."
MSG_DE[$MSG_PARTITIONING_SDCARD]="RBK0097I: Partitioniere und formatiere %1."
MSG_FORMATTING=98
MSG_EN[$MSG_FORMATTING]="RBK0098I: Formatting partition %1 with %2 (%3)."
MSG_DE[$MSG_FORMATTING]="RBK0098I: Formatiere Partition %1 mit %2 (%3)."
MSG_RESTORING_FILE_PARTITION_DONE=99
MSG_EN[$MSG_RESTORING_FILE_PARTITION_DONE]="RBK0099I: Restore of partition %1 finished."
MSG_DE[$MSG_RESTORING_FILE_PARTITION_DONE]="RBK0099I: Zurückspielen des Backups auf Partition %1 beendet."
MSG_WARN_RESTORE_PARTITION_DEVICE_OVERWRITTEN=100
MSG_EN[$MSG_WARN_RESTORE_PARTITION_DEVICE_OVERWRITTEN]="RBK0100W: Device %1 will be overwritten with the backup."
MSG_DE[$MSG_WARN_RESTORE_PARTITION_DEVICE_OVERWRITTEN]="RBK0100W: Gerät %1 wird mit dem Backup beschrieben."
MSG_VERSION_HISTORY_PAGE=101
MSG_EN[$MSG_VERSION_HISTORY_PAGE]="$MYHOMEURL/en/versionhistory/"
MSG_DE[$MSG_VERSION_HISTORY_PAGE]="$MYHOMEURL/de/versionshistorie/"
MSG_UPDATING_CMDLINE=102
MSG_EN[$MSG_UPDATING_CMDLINE]="RBK0102I: Detected PARTUUID usage in /boot/cmdline.txt. Changing PARTUUID from %1 to %2."
MSG_DE[$MSG_UPDATING_CMDLINE]="RBK0102I: Benutzung von PARTUUID in /boot/cmdline.txt erkannt. PARTUUID %1 wird auf %2 geändert."
MSG_UNABLE_TO_WRITE=103
MSG_EN[$MSG_UNABLE_TO_WRITE]="RBK0103E: Unable to create backup on %1 because of missing write permission."
MSG_DE[$MSG_UNABLE_TO_WRITE]="RBK0103E: Ein Backup kann nicht auf %1 erstellt werden da die Schreibberechtigung fehlt."
MSG_LABELING=104
MSG_EN[$MSG_LABELING]="RBK0104I: Labeling partition %1 with label %2."
MSG_DE[$MSG_LABELING]="RBK0104I: Partition %1 erhält das Label %2."
MSG_CLEANING_BACKUPDIRECTORY=105
MSG_EN[$MSG_CLEANING_BACKUPDIRECTORY]="RBK0105I: Deleting new backup directory %1."
MSG_DE[$MSG_CLEANING_BACKUPDIRECTORY]="RBK0105I: Neues Backupverzeichnis %1 wird gelöscht."
MSG_DEPLOYMENT_FAILED=106
MSG_EN[$MSG_DEPLOYMENT_FAILED]="RBK0106E: Installation of $MYNAME failed on server %1 for user %2."
MSG_DE[$MSG_DEPLOYMENT_FAILED]="RBK0106E: Installation von $MYNAME auf Server %1 für Benutzer %2 fehlgeschlagen."
MSG_EXTENSION_FAILED=107
MSG_EN[$MSG_EXTENSION_FAILED]="RBK0107E: Extension %1 failed with RC %2."
MSG_DE[$MSG_EXTENSION_FAILED]="RBK0107E: Erweiterung %1 fehlerhaft beendet mit RC %2."
MSG_SKIPPING_UNFORMATTED_PARTITION=108
MSG_EN[$MSG_SKIPPING_UNFORMATTED_PARTITION]="RBK0108W: Unformatted partition %1 (%2) not saved."
MSG_DE[$MSG_SKIPPING_UNFORMATTED_PARTITION]="RBK0108W: Unformatierte Partition %1 (%2) wird nicht gesichert."
MSG_UNSUPPORTED_FILESYSTEM_FORMAT=109
MSG_EN[$MSG_UNSUPPORTED_FILESYSTEM_FORMAT]="RBK0109E: Unsupported filesystem %1 detected on partition %2."
MSG_DE[$MSG_UNSUPPORTED_FILESYSTEM_FORMAT]="RBK0109E: Nicht unterstütztes Filesystem %1 auf Partition %2."
MSG_UNABLE_TO_COLLECT_PARTITIONINFO=110
MSG_EN[$MSG_UNABLE_TO_COLLECT_PARTITIONINFO]="RBK0110E: Unable to collect partition data with %1. RC %2."
MSG_DE[$MSG_UNABLE_TO_COLLECT_PARTITIONINFO]="RBK0110E: Partitionsdaten können nicht mit %1 gesammelt werden. RC %2."
MSG_UNABLE_TO_CREATE_PARTITIONS=111
MSG_EN[$MSG_UNABLE_TO_CREATE_PARTITIONS]="RBK0111E: Error occured when partitions were created. RC %1${NL}%2."
MSG_DE[$MSG_UNABLE_TO_CREATE_PARTITIONS]="RBK0111E: Fehler %1 beim Erstellen der Partitionen.RC %1 ${NL}%2."
MSG_PROCESSED_PARTITION=112
MSG_EN[$MSG_PROCESSED_PARTITION]="RBK0112I: Partition %1 was saved."
MSG_DE[$MSG_PROCESSED_PARTITION]="RBK0112I: Partition %1 wurde gesichert."
MSG_YES_NO_DEVICE_MISMATCH=113
MSG_EN[$MSG_YES_NO_DEVICE_MISMATCH]="RBK0113E: Restore device %1 doesn't match %2."
MSG_DE[$MSG_YES_NO_DEVICE_MISMATCH]="RBK0113E: Wiederherstellungsgerät %1 ähnelt nicht %2."
MSG_VISIT_VERSION_HISTORY_PAGE=114
MSG_EN[$MSG_VISIT_VERSION_HISTORY_PAGE]="RBK0114I: Visit %1 to read about the changes in the new version."
MSG_DE[$MSG_VISIT_VERSION_HISTORY_PAGE]="RBK0114I: Besuche %1 um die Änderungen in der neuen Version kennenzulernen."
MSG_DEPLOYED_HOST=115
MSG_EN[$MSG_DEPLOYED_HOST]="RBK0115I: $MYNAME $VERSION installed on host %1 for user %2."
MSG_DE[$MSG_DEPLOYED_HOST]="RBK0115I: $MYNAME $VERSION wurde auf Server %1 für Benutzer %2 installiert."
MSG_INCLUDED_CONFIG=116
MSG_EN[$MSG_INCLUDED_CONFIG]="RBK0116I: Using config file %1."
MSG_DE[$MSG_INCLUDED_CONFIG]="RBK0116I: Konfigurationsdatei %1 wird benutzt."
MSG_CURRENT_SCRIPT_VERSION=117
MSG_EN[$MSG_CURRENT_SCRIPT_VERSION]="RBK0117I: Current script version: %1"
MSG_DE[$MSG_CURRENT_SCRIPT_VERSION]="RBK0117I: Aktuelle Scriptversion: %1"
MSG_AVAILABLE_VERSIONS_HEADER=118
MSG_EN[$MSG_AVAILABLE_VERSIONS_HEADER]="RBK0118I: Available versions:"
MSG_DE[$MSG_AVAILABLE_VERSIONS_HEADER]="RBK0118I: Verfügbare Scriptversionen:"
MSG_AVAILABLE_VERSIONS=119
MSG_EN[$MSG_AVAILABLE_VERSIONS]="RBK0119I: %1: %2"
MSG_DE[$MSG_AVAILABLE_VERSIONS]="RBK0119I: %1: %2"
MSG_SAVING_ACTUAL_VERSION=120
MSG_EN[$MSG_SAVING_ACTUAL_VERSION]="RBK0120I: Saving current version %1 to %2."
MSG_DE[$MSG_SAVING_ACTUAL_VERSION]="RBK0120I: Aktuelle Version %1 wird in %2 gesichert."
MSG_RESTORING_PREVIOUS_VERSION=121
MSG_EN[$MSG_RESTORING_PREVIOUS_VERSION]="RBK0121I: Restoring previous version %1 to %2."
MSG_DE[$MSG_RESTORING_PREVIOUS_VERSION]="RBK0121I: Vorherige Version %1 wird in %2 wiederhergestellt."
MSG_SELECT_VERSION=122
MSG_EN[$MSG_SELECT_VERSION]="RBK0122I: Select version to restore (%1-%2)"
MSG_DE[$MSG_SELECT_VERSION]="RBK0122I: Auswahl der Version die wiederhergestellt werden soll (%1-%2)"
MSG_NO_PREVIOUS_VERSIONS_AVAILABLE=123
MSG_EN[$MSG_NO_PREVIOUS_VERSIONS_AVAILABLE]="RBK0123E: No version to restore available."
MSG_DE[$MSG_NO_PREVIOUS_VERSIONS_AVAILABLE]="RBK0123E: Keine Version zum Restore verfügbar."
MSG_FAKE_MODE_ON=124
MSG_EN[$MSG_FAKE_MODE_ON]="RBK0124W: Fake mode on."
MSG_DE[$MSG_FAKE_MODE_ON]="RBK0124W: Simulationsmodus an."
MSG_UNUSED_PARAMETERS=125
MSG_EN[$MSG_UNUSED_PARAMETERS]="RBK0125W: Unused option(s) \"%1\" detected. There may be quotes missing in option arguments."
MSG_DE[$MSG_UNUSED_PARAMETERS]="RBK0125W: Unbenutzte Option(en) \" %1\" entdeckt. Es scheinen Anführungszeichen bei Optionsargumenten zu fehlen."
MSG_REPLACING_FILE_BY_HARDLINK=126
MSG_EN[$MSG_REPLACING_FILE_BY_HARDLINK]="RBK0126I: Replacing %1 with hardlink to %2."
MSG_DE[$MSG_REPLACING_FILE_BY_HARDLINK]="RBK0126I: Datei %1 wird durch einem Hardlink auf %2 ersetzt."
MSG_DEPLOYING_HOST_OFFLINE=127
MSG_EN[$MSG_DEPLOYING_HOST_OFFLINE]="RBK0127E: Server %1 offline."
MSG_DE[$MSG_DEPLOYING_HOST_OFFLINE]="RBK0127E: Server %1 ist nicht erreichbar."
MSG_USING_LOGFILE=128
MSG_EN[$MSG_USING_LOGFILE]="RBK0128I: Using logfile %1."
MSG_DE[$MSG_USING_LOGFILE]="RBK0128I: Logdatei ist %1."
MSG_EMAIL_EXTENSION_NOT_FOUND=129
MSG_EN[$MSG_EMAIL_EXTENSION_NOT_FOUND]="RBK0129E: email extension %1 not found."
MSG_DE[$MSG_EMAIL_EXTENSION_NOT_FOUND]="RBK0129E: email Erweiterung %1 nicht gefunden."
MSG_MISSING_FILEPARAMETER=130
MSG_EN[$MSG_MISSING_FILEPARAMETER]="RBK0130E: Missing backup- or restorepath parameter."
MSG_DE[$MSG_MISSING_FILEPARAMETER]="RBK0130E: Backup- oder Restorepfadparameter fehlt."
MSG_MISSING_INSTALLED_FILE=131
MSG_EN[$MSG_MISSING_INSTALLED_FILE]="RBK0131E: Program %1 not found. Use 'sudo apt-get update; sudo apt-get install %2' to install missing program."
MSG_DE[$MSG_MISSING_INSTALLED_FILE]="RBK0131E: Programm %1 nicht gefunden. Mit 'sudo apt-get update; sudo apt-get install %2' wird das fehlende Programm installiert."
MSG_UPDATING_FSTAB=132
MSG_EN[$MSG_UPDATING_FSTAB]="RBK0132I: Detected PARTUUID usage in /etc/fstab. Changing PARTUUID from %1 to %2."
MSG_DE[$MSG_UPDATING_FSTAB]="RBK0132I: Benutzung von PARTUUID in /etc/fstab erkannt. PARTUUID %1 wird auf %2 geändert."
MSG_HARDLINK_DIRECTORY_USED=133
MSG_EN[$MSG_HARDLINK_DIRECTORY_USED]="RBK0133I: Using directory %1 for hardlinks."
MSG_DE[$MSG_HARDLINK_DIRECTORY_USED]="RBK0133I: Verzeichnis %1 wird für Hardlinks benutzt."
MSG_UNABLE_TO_USE_HARDLINKS=134
MSG_EN[$MSG_UNABLE_TO_USE_HARDLINKS]="RBK0134E: Unable to use hardlinks on %1 for bootpartition files. RC %2."
MSG_DE[$MSG_UNABLE_TO_USE_HARDLINKS]="RBK0134E: Hardlinkslinks können nicht auf %1 für Bootpartitionsdateien benutzt werden. RC %2."
MSG_SCRIPT_UPDATE_DEPRECATED=135
MSG_EN[$MSG_SCRIPT_UPDATE_DEPRECATED]="RBK0135W: Current script version %1 has a severe bug and will be updated now."
MSG_DE[$MSG_SCRIPT_UPDATE_DEPRECATED]="RBK0135W: Aktuelle Scriptversion %1 enthält einen gravierenden Fehler und wird jetzt aktualisiert."
MSG_MISSING_START_OR_STOP=136
MSG_EN[$MSG_MISSING_START_OR_STOP]="RBK0136E: Missing mandatory option %1."
MSG_DE[$MSG_MISSING_START_OR_STOP]="RBK0136E: Es fehlt die obligatorische Option %1."
MSG_NO_ROOTBACKUPFILE_FOUND=137
MSG_EN[$MSG_NO_ROOTBACKUPFILE_FOUND]="RBK0137E: Rootbackupfile for type %1 not found."
MSG_DE[$MSG_NO_ROOTBACKUPFILE_FOUND]="RBK0137E: Rootbackupdatei für den Typ %1 nicht gefunden."
MSG_USING_ROOTBACKUPFILE=138
MSG_EN[$MSG_USING_ROOTBACKUPFILE]="RBK0138I: Using bootbackup %1."
MSG_DE[$MSG_USING_ROOTBACKUPFILE]="RBK0138I: Bootbackup %1 wird benutzt."
MSG_FORCING_CREATING_PARTITIONS=139
MSG_EN[$MSG_FORCING_CREATING_PARTITIONS]="RBK0139W: Partition creation ignores errors."
MSG_DE[$MSG_FORCING_CREATING_PARTITIONS]="RBK0139W: Partitionserstellung ignoriert Fehler."
MSG_SCRIPT_RESTART=140
MSG_EN[$MSG_SCRIPT_RESTART]="RBK0140I: Restarting with new version %1."
MSG_DE[$MSG_SCRIPT_RESTART]="RBK0140I: Neustart mit neuer Version %1."
MSG_SAVING_USED_PARTITIONS_ONLY=141
MSG_EN[$MSG_SAVING_USED_PARTITIONS_ONLY]="RBK0141I: Saving space of defined partitions only."
MSG_DE[$MSG_SAVING_USED_PARTITIONS_ONLY]="RBK0141I: Nur der von den definierten Partitionen belegte Speicherplatz wird gesichert."
MSG_NO_BOOTDEVICE_FOUND=142
MSG_EN[$MSG_NO_BOOTDEVICE_FOUND]="RBK0142E: Unable to detect boot device."
MSG_DE[$MSG_NO_BOOTDEVICE_FOUND]="RBK0142E: Bootgerät kann nicht erkannt werden."
MSG_FORCE_SFDISK=143
MSG_EN[$MSG_FORCE_SFDISK]="RBK0143W: Target %1 does not match with backup. Partitioning forced."
MSG_DE[$MSG_FORCE_SFDISK]="RBK0143W: Ziel %1 passt nicht zu dem Backup. Partitionierung wird trotzdem vorgenommen."
MSG_SKIP_SFDISK=144
MSG_EN[$MSG_SKIP_SFDISK]="RBK0144W: Target %1 will not be partitioned. Using existing partitions."
MSG_DE[$MSG_SKIP_SFDISK]="RBK0144W: Ziel %1 wird nicht partitioniert. Existierende Partitionen werden benutzt."
MSG_SKIP_CREATING_PARTITIONS=145
MSG_EN[$MSG_SKIP_CREATING_PARTITIONS]="RBK0145W: Partition creation skipped. Using existing partitions."
MSG_DE[$MSG_SKIP_CREATING_PARTITIONS]="RBK0145W: Partitionen werden nicht erstellt. Existierende Paritionen werden benutzt."
MSG_NO_PARTITION_TABLE_DEFINED=146
MSG_EN[$MSG_NO_PARTITION_TABLE_DEFINED]="RBK0146I: No partitiontable found on %1."
MSG_DE[$MSG_NO_PARTITION_TABLE_DEFINED]="RBK0146I: Keine Partitionstabelle auf %1 gefunden."
MSG_BACKUP_PARTITION_FAILED=147
MSG_EN[$MSG_BACKUP_PARTITION_FAILED]="RBK0147E: Backup of partition %1 failed with RC %2."
MSG_DE[$MSG_BACKUP_PARTITION_FAILED]="RBK0147E: Sicherung der Partition %1 schlug fehl mit RC %2."
MSG_STACK_TRACE=148
MSG_EN[$MSG_STACK_TRACE]="RBK0148E: @@@@@@@@@@@@@@@@@@@@ Stacktrace @@@@@@@@@@@@@@@@@@@@"
MSG_DE[$MSG_STACK_TRACE]="RBK0148E: @@@@@@@@@@@@@@@@@@@@ Stacktrace @@@@@@@@@@@@@@@@@@@@"
MSG_FILE_ARG_NOT_FOUND=149
MSG_EN[$MSG_FILE_ARG_NOT_FOUND]="RBK0149E: %1 not found."
MSG_DE[$MSG_FILE_ARG_NOT_FOUND]="RBK0149E: %1 nicht gefunden."
MSG_MAX_4GB_LIMIT=150
MSG_EN[$MSG_MAX_4GB_LIMIT]="RBK0150W: Maximum file size in backup directory %1 is limited to 4GB."
MSG_DE[$MSG_MAX_4GB_LIMIT]="RBK0150W: Maximale Dateigröße im Backupverzeichnis %1 ist auf 4GB begrenzt."
MSG_USING_BACKUPPATH=151
MSG_EN[$MSG_USING_BACKUPPATH]="RBK0151I: Using backuppath %1."
MSG_DE[$MSG_USING_BACKUPPATH]="RBK0151I: Backuppfad %1 wird benutzt."
MSG_MKFS_FAILED=152
MSG_EN[$MSG_MKFS_FAILED]="RBK0152E: Unable to create filesystem: '%1' - RC: %2."
MSG_DE[$MSG_MKFS_FAILED]="RBK0152E: Dateisystem kann nicht erstellt werden: '%1' - RC: %2."
MSG_LABELING_FAILED=153
MSG_EN[$MSG_LABELING_FAILED]="RBK0153E: Unable to label partition: '%1' - RC: %2."
MSG_DE[$MSG_LABELING_FAILED]="RBK0153E: Partition kann nicht mit einem Label versehen werden: '%1' - RC: %2."
MSG_RESTORE_DEVICE_MOUNTED=154
MSG_EN[$MSG_RESTORE_DEVICE_MOUNTED]="RBK0154E: Restore is not possible when a partition of device %1 is mounted."
MSG_DE[$MSG_RESTORE_DEVICE_MOUNTED]="RBK0154E: Ein Restore ist nicht möglich wenn eine Partition von %1 gemounted ist."
MSG_INVALID_RESTORE_ROOT_PARTITION=155
MSG_EN[$MSG_INVALID_RESTORE_ROOT_PARTITION]="RBK0155E: Restore root partition %1 is no partition."
MSG_DE[$MSG_INVALID_RESTORE_ROOT_PARTITION]="RBK0155E: Ziel Rootpartition %1 ist keine Partition."
MSG_SKIP_STARTING_SERVICES=156
MSG_EN[$MSG_SKIP_STARTING_SERVICES]="RBK0156W: No services to start."
MSG_DE[$MSG_SKIP_STARTING_SERVICES]="RBK0156W: Keine Services sind zu starten."
MSG_SKIP_STOPPING_SERVICES=157
MSG_EN[$MSG_SKIP_STOPPING_SERVICES]="RBK0157W: No services to stop."
MSG_DE[$MSG_SKIP_STOPPING_SERVICES]="RBK0157W: Keine Services sind zu stoppen."
MSG_MAIN_BACKUP_PROGRESSING=158
MSG_EN[$MSG_MAIN_BACKUP_PROGRESSING]="RBK0158I: Creating native %1 backup %2."
MSG_DE[$MSG_MAIN_BACKUP_PROGRESSING]="RBK0158I: %1 Backup %2 wird erstellt."
MSG_CHECKING_FOR_BETA=159
MSG_EN[$MSG_CHECKING_FOR_BETA]="RBK0159I: Checking for beta version."
MSG_DE[$MSG_CHECKING_FOR_BETA]="RBK0159I: Prüfe ob eine Beta Version verfügbar ist."
MSG_TARGETSD_SIZE_TOO_SMALL=160
MSG_EN[$MSG_TARGETSD_SIZE_TOO_SMALL]="RBK0160E: Target %1 with %2 is smaller than backup source with %3."
MSG_DE[$MSG_TARGETSD_SIZE_TOO_SMALL]="RBK0160E: Ziel %1 mit %2 ist kleiner als die Backupquelle mit %3."
MSG_TARGETSD_SIZE_BIGGER=161
MSG_EN[$MSG_TARGETSD_SIZE_BIGGER]="RBK0161W: Target %1 with %2 is larger than backup source with %3. You waste %4."
MSG_DE[$MSG_TARGETSD_SIZE_BIGGER]="RBK0161W: Ziel %1 mit %2 ist größer als die Backupquelle mit %3. %4 sind ungenutzt."
MSG_RESTORE_ABORTED=162
MSG_EN[$MSG_RESTORE_ABORTED]="RBK0162I: Restore aborted."
MSG_DE[$MSG_RESTORE_ABORTED]="RBK0162I: Restore abgebrochen."
MSG_CTRLC_DETECTED=163
MSG_EN[$MSG_CTRLC_DETECTED]="RBK0163E: Script execution canceled with CTRL C."
MSG_DE[$MSG_CTRLC_DETECTED]="RBK0163E: Scriptausführung mit CTRL C abgebrochen."
MSG_HARDLINK_ERROR=164
MSG_EN[$MSG_HARDLINK_ERROR]="RBK0164E: Unable to create hardlinks. RC %1."
MSG_DE[$MSG_HARDLINK_ERROR]="RBK0164E: Es können keine Hardlinks erstellt werden. RC %1."
MSG_INTRO_BETA_MESSAGE=165
MSG_EN[$MSG_INTRO_BETA_MESSAGE]="RBK0165W: =========> NOTE  <========= \
${NL}!!! RBK0165W: This is a betaversion and should not be used in production. \
${NL}!!! RBK0165W: =========> NOTE <========="
MSG_DE[$MSG_INTRO_BETA_MESSAGE]="RBK0165W: =========> HINWEIS <========= \
${NL}!!! RBK0165W: Dieses ist eine Betaversion welche nicht in Produktion benutzt werden sollte. \
${NL}!!! RBK0165W: =========> HINWEIS <========="
MSG_UMOUNT_ERROR=166
MSG_EN[$MSG_UMOUNT_ERROR]="RBK0166E: Umount for %1 failed. RC %2. Maybe mounted somewhere else?"
MSG_DE[$MSG_UMOUNT_ERROR]="RBK0166E: Umount für %1 fehlerhaft. RC %2. Vielleicht noch woanders gemounted?"
#MSG_ALREADY_ACTIVE=167
#MSG_EN[$MSG_ALREADY_ACTIVE]="RBK0167E: $MYSELF already up and running"
#MSG_DE[$MSG_ALREADY_ACTIVE]="RBK0167E: $MYSELF ist schon gestartet"
MSG_BETAVERSION_AVAILABLE=168
MSG_EN[$MSG_BETAVERSION_AVAILABLE]="RBK0168I: $MYSELF beta version %1 is available. Any help to test this beta is appreciated."
MSG_DE[$MSG_BETAVERSION_AVAILABLE]="RBK0168I: $MYSELF Beta Version %1 ist verfügbar. Hilfe beim Testen dieser Beta ist sehr willkommen.."
MSG_ROOT_PARTITION_NOT_FOUND=169
MSG_EN[$MSG_ROOT_PARTITION_NOT_FOUND]="RBK0169E: Target root partition %1 does not exist."
MSG_DE[$MSG_ROOT_PARTITION_NOT_FOUND]="RBK0169E: Ziel Rootpartition %1 existiert nicht."
MSG_MISSING_R_OPTION=170
MSG_EN[$MSG_MISSING_R_OPTION]="RBK0170E: Backup uses an external root partition. -R option missing."
MSG_DE[$MSG_MISSING_R_OPTION]="RBK0170E: Backup benutzt eine externe root partition. Die Option -R fehlt."
MSG_NOPARTITIONS_TOBACKUP_FOUND=171
MSG_EN[$MSG_NOPARTITIONS_TOBACKUP_FOUND]="RBK0171E: Unable to detect any partitions to backup."
MSG_DE[$MSG_NOPARTITIONS_TOBACKUP_FOUND]="RBK0171E: Es können keine zu sichernde Partitionen gefunden werden."
MSG_UNABLE_TO_CREATE_DIRECTORY=172
MSG_EN[$MSG_UNABLE_TO_CREATE_DIRECTORY]="RBK0172E: Unable to create directory %1."
MSG_DE[$MSG_UNABLE_TO_CREATE_DIRECTORY]="RBK0172E: Verzeichnis %1 kann nicht erstellt werden."
MSG_RSYNC_DOES_NOT_SUPPORT_PROGRESS=173
MSG_EN[$MSG_RSYNC_DOES_NOT_SUPPORT_PROGRESS]="RBK0173E: rsync version %1 doesn't support progress information."
MSG_DE[$MSG_RSYNC_DOES_NOT_SUPPORT_PROGRESS]="RBK0173E: rsync Version %1 unterstüzt keine Fortschirtsanzeige."
MSG_INTRO_HOTFIX_MESSAGE=173
MSG_EN[$MSG_INTRO_HOTFIX_MESSAGE]="RBK0173W: =========> NOTE  <========= \
${NL}!!! RBK0173W: This is a temporary hotfix and should not be used in production. \
${NL}!!! RBK0173W: =========> NOTE <========="
MSG_DE[$MSG_INTRO_HOTFIX_MESSAGE]="RBK0173W: =========> HINWEIS <========= \
${NL}!!! RBK0173W: Dieses ist ein temporärer Hotfix welcher nicht in Produktion benutzt werden sollte. \
${NL}!!! RBK0173W: =========> HINWEIS <========="

declare -A MSG_HEADER=( ['I']="---" ['W']="!!!" ['E']="???" )

# Create message and substitute parameters

function getMessageText() {         # languageflag messagenumber parm1 parm2 ...
    local msg
    local p
    local i
	local s

	if [[ $1 != "L" ]]; then
		LANG_SUFF=${1^^*}
	else
		LANG_EXT=${LANG^^*}
		LANG_SUFF=${LANG_EXT:0:2}
	fi

	msgVar="MSG_${LANG_SUFF}"

    if [[ -n ${!msgVar} ]]; then
		msgVar="$msgVar[$2]"
        msg=${!msgVar}
        if [[ -z $msg ]]; then		       			# no translation found
			msgVar="$2"
			if [[ -z ${!msgVar} ]]; then
				echo "${MSG_EN[$MSG_UNDEFINED]}"	# unknown message id
				logStack
				return
			else
				msg="${MSG_EN[$2]}";  	    	    # fallback into english
			fi
		fi
     else
		 msg="${MSG_EN[$2]}";      	      	        # fallback into english
     fi

   for (( i=3; $i <= $#; i++ )); do            		# substitute all message parameters
      p=${!i}
      let s=$i-2
      s="%$s"
      msg="$( perl -p -e "s|$s|$p|" <<< "$msg" 2>/dev/null)"	  # have to use explicit command name
   done

   msg="$( perl -p -e "s/%[0-9]+//g" <<< "$msg" 2>/dev/null)"     # delete trailing %n definitions

	local msgPref=${msg:0:3}
	if [[ $msgPref == "RBK" ]]; then								# RBK0001E
		local severity=${msg:7:1}
		if [[ "$severity" =~ [EWI] ]]; then
			local msgHeader=${MSG_HEADER[$severity]}
			echo "$msgHeader $msg"
		else
			echo "$msg"
		fi
	else
		echo "$msg"
	fi
}


# Borrowed from http://stackoverflow.com/questions/85880/determine-if-a-function-exists-in-bash

fn_exists() {
  [ `type -t $1`"" == 'function' ]
}

# Borrowed from http://blog.yjl.im/2012/01/printing-out-call-stack-in-bash.html

function logStack () {
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_STACK_TRACE
	local i=0
	local FRAMES=${#BASH_LINENO[@]}
	# FRAMES-2 skips main, the last one in arrays
	for ((i=FRAMES-2; i>=0; i--)); do
		echo '  File' \"${BASH_SOURCE[i+1]}\", line ${BASH_LINENO[i]}, in ${FUNCNAME[i+1]}
		# Grab the source code of the line
		sed -n "${BASH_LINENO[i]}{s/^/    /;p}" "${BASH_SOURCE[i+1]}"
	done
}

function callExtensions() { # extensionplugpoint rc

	logEntry "callExtensions: $1"

	local extension

	if [[ $1 == $EMAIL_EXTENSION ]]; then
		local extensionFileName="${MYNAME}_${EMAIL_EXTENSION}.sh"
		shift 1
		local args=( "$@" )

		if which $extensionFileName 2>&1 1>/dev/null; then
			logItem "Calling $extensionFileName"
			$extensionFileName "${args[@]}"
			local rc=$?
			logItem "Extension RC: $rc"
			if [[ $rc != 0 ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXTENSION_FAILED "$extensionFileName" "$rc"
				exitError $RC_EXTENSION_ERROR
			fi
		else
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_EMAIL_EXTENSION_NOT_FOUND "$extensionFileName"
			exitError $RC_EXTENSION_ERROR
		fi
	else

		for extension in $EXTENSIONS; do

			local extensionFileName="${MYNAME}_${extension}_$1.sh"

			if which $extensionFileName 2>&1 1>/dev/null; then
				logItem "Calling $extensionFileName $2"
				executeShellCommand ". $extensionFileName $2"
				local rc=$?
				logItem "Extension RC: $rc"
				if [[ $rc != 0 ]]; then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXTENSION_FAILED "$extensionFileName" "$rc"
					exitError $RC_EXTENSION_ERROR
				fi
			else
				logItem "$extensionFileName not found - skipping"
			fi
		done
	fi

	logExit "callExtensions"

}

# usage

function usage() {

	LANG_SUFF=$LANGUAGE

	NO_YES=( $(getLocalizedMessage $MSG_NO_YES) )

	local func="usage${LANG_SUFF}"

	if ! fn_exists $func; then
		func="usageEN"
	fi

	$func

}

# borrowed from http://stackoverflow.com/questions/3685970/check-if-an-array-contains-a-value

function containsElement () {
  local e
  for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 1; done
  return 0
}

# --- Helper function to extract the message text in German or English and insert message parameters

function getLocalizedMessage() { # messageNumber parm1 parm2

	local msg
	msg="$(getMessageText $LANGUAGE "$@")"
	echo "$msg"
}

# Write message

function writeToConsole() {  # msglevel messagenumber message
	local msg level

	level=$1
	shift

	if [[ ( $level -le $MSG_LEVEL ) ]]; then

		msg="$(getMessageText $LANGUAGE "$@")"

		if (( $INTERACTIVE )); then
			echo -e "$msg" > /dev/tty
		else
			echo -e "$msg" >> "$LOG_FILE"
		fi

		echo -e "$msg" >> "$LOG_MAIL_FILE"
		logIntoOutput $LOG_TYPE_MSG "$msg"
	fi
}

# setup trap function
# trap function then will be called with trap as argument
#
# borrowed from # from http://stackoverflow.com/a/2183063/804678

function trapWithArg() { # function trap1 trap2 ... trapn
	logItem "TRAP $*"
    local func="$1" ; shift
    for sig ; do
        trap "$func $sig" "$sig"
    done
}

# Borrowed from http://unix.stackexchange.com/questions/44040/a-standard-tool-to-convert-a-byte-count-into-human-kib-mib-etc-like-du-ls1

function bytesToHuman() {
	local b d s S
	local sign=1
    b=${1:-0}; d=''; s=0; S=(Bytes {K,M,G,T,E,P,Y,Z}iB)
    if (( b < 0 )); then
		sign=-1
		(( b=-b ))
	fi
    while ((b > 1024)); do
        d="$(printf ".%02d" $((b % 1024 * 100 / 1024)))"
        b=$((b / 1024))
        let s++
    done
    if (( sign < 0 )); then
		(( b=-b ))
    fi
    echo "$b$d ${S[$s]}"
}

function assertionFailed() { # lineno message
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_ASSERTION_FAILED "$GIT_COMMIT_ONLY" "$1" "$2"
	rc=$RC_ASSERTION
	logStack
	exit 127
}

function exitNormal() { #
	rc=0
	exit 0
}

function exitError() { # {rc}

	logEntry "exitError $1"
	if [[ -n "$1" ]]; then
		rc="$1"
	else
		assertionFailed $LINENO "Unkown exit error"
	fi

	logExit "exitError $rc"
	exit $rc
}

function executeCommand() { # command - rc's to accept
	local rc i
	logItem "Command executed:$NL$1"
	if (( $VERBOSE )) || (( $PROGRESS )); then
		eval "$1" 2>&1
		rc=$?
	else
		eval "$1" &>"$LOG_TOOL_FILE"
		rc=$?
		cat "$LOG_TOOL_FILE" >> "$LOG_FILE"
	fi
	if (( $rc != 0 )); then
		local error=1
		for ((i=2; i<=$#; i++)); do
			if (( $i == $rc )); then
				error=0
				break
			fi
		done
		if (( $error )) && [[ -f $LOG_TOOL_FILE ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_TOOL_ERROR "$BACKUPTYPE" "$(< $LOG_TOOL_FILE)"
		fi
	fi
	rm -f "$LOG_TOOL_FILE" &>>$LOG_FILE
	logItem "Result $rc"
	return $rc
}

function executeShellCommand() { # command

	logEntry "executeShellCommand: $@"
	eval "$*" 1>/dev/null 2>"$LOG_TOOL_FILE"
    local rc=$?
	cat "$LOG_TOOL_FILE" >> "$LOG_FILE"
	if (( $rc != 0 )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_SHELL_ERROR "$1" "$(< $LOG_TOOL_FILE)"
		rm -f "$LOG_TOOL_FILE"  &>>$LOG_FILE
	fi
	logExit "executeShellCommand: $rc"
	return $rc
}

function logIntoOutput() { # logtype message

	local type dte
	type=$1
	shift

	dte=$(date +%Y%m%d-%H%M%S)

	local indent=$(printf '%*s' $LOG_INDENT)

	if (( $LOGGING_ENABLED )) ; then
		case $LOG_OUTPUT in
			$LOG_OUTPUT_SYSLOG)
				logger -t $MYSELF -- "${LOG_TYPEs[$type]} $indent $@"
				;;
			$LOG_OUTPUT_VARLOG | $LOG_OUTPUT_BACKUPLOC | $LOG_OUTPUT_HOME)
				echo "$dte: ${LOG_TYPEs[$type]} $indent $@" >> "$LOG_FILE"
				;;
			$LOG_OUTPUT_MAIL)
				echo "$dte: ${LOG_TYPEs[$type]} $indent $@" >> "$LOG_MAIL_FILE"
				;;
			*)
				assertionFailed $LINENO "Invalid log destination $LOG_OUTPUT"
				;;
		esac
	fi

}

function repeat() { # char num
	local s
	s=$( yes $1 | head -$2 | tr -d "\n" )
	echo $s
}

function logItem() { # message
	if [[ $LOG_DEBUG == $LOG_LEVEL ]]; then
		logIntoOutput $LOG_TYPE_DEBUG "-- $1"
	fi
}

function logEntry() { # message
	(( LOG_INDENT+=3 ))
	if [[ $LOG_DEBUG == $LOG_LEVEL ]]; then
		logIntoOutput $LOG_TYPE_DEBUG ">> $1"
	fi
}

function logExit() { # message
	(( LOG_INDENT-=3 ))
	if [[ $LOG_DEBUG == $LOG_LEVEL ]]; then
		logIntoOutput $LOG_TYPE_DEBUG "<< $1"
	fi
}

function logOptions() {

	logEntry "logOptions"

	[[ -f /etc/os-release ]] &&	logItem "$(cat /etc/os-release)"
	[[ -f /etc/debian_version ]] &&	logItem "$(cat /etc/debian_version)"
	
	logItem "$(uname -a)"

	logItem "Options: $INVOCATIONPARMS"
	logItem "BACKUPPATH=$BACKUPPATH"
	logItem "KEEPBACKUPS=$KEEPBACKUPS"
	logItem "BACKUPTYPE=$BACKUPTYPE"
	logItem "STOPSERVICES=$STOPSERVICES"
	logItem "STARTSERVICES=$STARTSERVICES"
	logItem "EMAIL=$EMAIL"
	logItem "EMAIL_PARMS=$EMAIL_PARMS"
	logItem "LOG_LEVEL=$LOG_LEVEL"
	logItem "MSG_LEVEL=$MSG_LEVEL"
	logItem "MAIL_PROGRAM=$EMAIL_PROGRAM"
	logItem "APPEND_LOG=$APPEND_LOG"
 	logItem "VERBOSE=$VERBOSE"
 	logItem "CONFIG_FILE=$CONFIG_FILE"
 	logItem "LOG_OUTPUT=$LOG_OUTPUT"
 	logItem "SKIPLOCALCHECK=$SKIPLOCALCHECK"
 	logItem "DD_BLOCKSIZE=$DD_BLOCKSIZE"
 	logItem "DD_PARMS=$DD_PARMS"
 	logItem "DD_BACKUP_SAVE_USED_PARTITIONS_ONLY=$DEFAULT_DD_BACKUP_SAVE_USED_PARTITIONS_ONLY"
	logItem "RESTORE_DEVICE=$RESTORE_DEVICE"
	logItem "ROOT_PARTITION=$ROOT_PARTITION"
	logItem "EXCLUDE_LIST=$EXCLUDE_LIST"
	logItem "ZIP_BACKUP=$ZIP_BACKUP"
	logItem "NOTIFY_UPDATE=$NOTIFY_UPDATE"
	logItem "EXTENSIONS=$EXTENSIONS"
	logItem "PARTITIONBASED_BACKUP=$PARTITIONBASED_BACKUP"
	logItem "PARTITIONS_TO_BACKUP=$PARTITIONS_TO_BACKUP"
	logItem "LANGUAGE=$LANGUAGE"
	logItem "DEFAULT_YES_NO_RESTORE_DEVICE=$DEFAULT_YES_NO_RESTORE_DEVICE"
	logItem "DEFAULT_DEPLOYMENT_HOSTS=$DEFAULT_DEPLOYMENT_HOSTS"
	logItem "FAKE=$FAKE"
	logItem "RSYNC_BACKUP_OPTIONS=$RSYNC_BACKUP_OPTIONS"
	logItem "RSYNC_BACKUP_ADDITIONAL_OPTIONS=$RSYNC_BACKUP_ADDITIONAL_OPTIONS"
	logItem "TAR_BACKUP_OPTIONS=$TAR_BACKUP_OPTIONS"
	logItem "TAR_BACKUP_ADDITIONAL_OPTIONS=$TAR_BACKUP_ADDITIONAL_OPTIONS"
	logItem "MAIL_ON_ERROR_ONLY=$MAIL_ON_ERROR_ONLY"
	logItem "LINK_BOOTPARTITIONFILES=$DEFAULT_LINK_BOOTPARTITIONFILES"
	logItem "HANDLE_DEPRECATED=$HANDLE_DEPRECATED"
	logExit "logOptions"

}

LOG_MAIL_FILE="$CURRENT_DIR/${MYNAME}.maillog"
LOG_TOOL_FILE="/tmp/${MYNAME}_$$.log"
#logItem "Removing maillog file ${LOG_MAIL_FILE}"
rm -f "$LOG_MAIL_FILE" &>/dev/null
LOG_FILE="$CURRENT_DIR/${MYNAME}.log"
#logItem "Removing log file ${LOG_FILE}"
rm -f "$LOG_FILE" &>/dev/null

############# Begin default config section #############

# Part or whole of the following section can be put into
# /usr/local/etc/raspiBackup.conf or ~/.raspiBackup.conf
# and will take precedence over the following default definitions

# path to store the backupfile
DEFAULT_BACKUPPATH="/backup"
# how many backups to keep
DEFAULT_KEEPBACKUPS=3
# type of backup: dd, tar or rsync
DEFAULT_BACKUPTYPE="dd"
# zip tar or dd backup (0 = false, 1 = true)
DEFAULT_ZIP_BACKUP=0
# with dd backup save only space used by partitions
DEFAULT_DD_BACKUP_SAVE_USED_PARTITIONS_ONLY=0
# commands to stop services before backup separated by ;
DEFAULT_STOPSERVICES=""
# commands to start services after backup separated by ;
DEFAULT_STARTSERVICES=""
# email to send completion status
DEFAULT_EMAIL=""
# Additional parameters for email program (optional)
DEFAULT_EMAIL_PARMS=""
# log level  (0 = none, 1 = debug)
DEFAULT_LOG_LEVEL=0
# log output ( 0 = syslog, 1 = /var/log, 2 = backuppath)
DEFAULT_LOG_OUTPUT=1
# msg level (0 = minimal, 1 = detailed)
DEFAULT_MSG_LEVEL=0
# mailprogram
DEFAULT_MAIL_PROGRAM="mail"
# restore device
DEFAULT_RESTORE_DEVICE=""
# default append log (0 = false, 1 = true)
DEFAULT_APPEND_LOG=0
# default verbose log (0 = false, 1 = true)
DEFAULT_VERBOSE=0
# skip check for remote mount of backup path (0 = false, 1 = true)
DEFAULT_SKIPLOCALCHECK=0
# blocksize used for dd
DEFAULT_DD_BLOCKSIZE=1MB
# addition parms used for dd
DEFAULT_DD_PARMS=""
# exclude list
DEFAULT_EXCLUDE_LIST=""
# notify in email if there is an updated script version available  (0 = false, 1 = true)
DEFAULT_NOTIFY_UPDATE=1
# extensions to call
DEFAULT_EXTENSIONS=""
# partition based backup  (0 = false, 1 = true)
DEFAULT_PARTITIONBASED_BACKUP=0
# backup all partitions
DEFAULT_PARTITIONS_TO_BACKUP="*"
# language (DE or EN)
DEFAULT_LANGUAGE=""
# hosts which will get the updated backup script with parm -y - non pwd access with keys has to be enabled
# Example: "root@raspberrypi root@fhem root@openhab root@magicmirror"
DEFAULT_DEPLOYMENT_HOSTS=""
# Use with care !
DEFAULT_YES_NO_RESTORE_DEVICE="loop"
# Use hardlinks for partitionbootfiles
DEFAULT_LINK_BOOTPARTITIONFILES=0

# Change these options only if you know what you are doing !!!
DEFAULT_RSYNC_BACKUP_OPTIONS="-aHAx"
DEFAULT_RSYNC_BACKUP_ADDITIONAL_OPTIONS=""
DEFAULT_TAR_BACKUP_OPTIONS="-cpi"
DEFAULT_TAR_BACKUP_ADDITIONAL_OPTIONS=""

# Use with care !
DEFAULT_MAIL_ON_ERROR_ONLY=0

# If version is marked as deprecated and buggy then update version
DEFAULT_HANDLE_DEPRECATED=1

# report uuid
DEFAULT_USE_UUID=1

############# End default config section #############

# nice function to get user who invoked this script via sudo
# Borrowed from http://stackoverflow.com/questions/4598001/how-do-you-find-the-original-user-through-multiple-sudo-and-su-commands
# adapted to return current user if no sudoers is used

function findUser() {

	if [[ -z "$SUDO_USER" || "$SUDO_USER" == "root" ]]; then
		echo $USER
		return
	fi

    thisPID=$$
    origUser=$(whoami)
    thisUser=$origUser

    while [ "$thisUser" = "$origUser" ]; do
		if [ "$thisPID" = "0" ]; then
			thisUser="root"
			break
		fi
        ARR=($(ps h -p$thisPID -ouser,ppid;))
        thisUser="${ARR[0]}"
        myPPid="${ARR[1]}"
        thisPID=$myPPid
    done

    getent passwd "$thisUser" | cut -d: -f1
}

function substituteNumberArguments() {

	local ll lla lo lloa ml mla
	if [[ $LOG_LEVEL < 0 || $LOG_LEVEL > ${#LOG_LEVELs[@]} ]]; then
		ll=$(tr '[:lower:]' '[:upper:]'<<< $LOG_LEVEL)
		lla=$(tr '[:lower:]' '[:upper:]'<<< ${LOG_LEVEL_ARGs[$ll]+abc})
		if [[ $lla == "ABC" ]]; then
			LOG_LEVEL=${LOG_LEVEL_ARGs[$ll]}
		fi
	fi

	if [[ $LOG_OUTPUT < 0 || $LOG_OUTPUT > ${#LOG_OUTPUT_LOCs[@]} ]]; then
		lo=$(tr '[:lower:]' '[:upper:]'<<< $LOG_OUTPUT)
		loa=$(tr '[:lower:]' '[:upper:]'<<< ${LOG_OUTPUT_ARGs[$lo]+abc})
		if [[ $loa == "ABC" ]]; then
			LOG_OUTPUT=${LOG_OUTPUT_ARGs[$lo]}
		fi
	fi

	if [[ $MSG_LEVEL < 0 || $MSG_LEVEL > ${#MSG_LEVELs[@]} ]]; then
		ml=$(tr '[:lower:]' '[:upper:]'<<< $MSG_LEVEL)
		mla=$(tr '[:lower:]' '[:upper:]'<<< ${MSG_LEVEL_ARGs[$ml]+abc})
		if [[ $mla == "ABC" ]]; then
			MSG_LEVEL=${MSG_LEVEL_ARGs[$ml]}
		fi
	fi
}

function bootedFromSD() {
	logEntry "bootedFromSD"
	local rc
	logItem "Boot device: $BOOT"
	if [[ $BOOT_DEVICE =~ mmcblk[0-9]+ ]]; then
		rc=0			# yes /dev/mmcblk0p1
	else
		rc=1			# is /dev/sda1 or other
	fi
	logExit "bootedFromSD: $rc"
	return $rc
}

# Input:
# 	mmcblk0
# 	sda
# Output:
# 	mmcblk0p
# 	sda

function getPartitionPrefix() { # device

	logEntry "getPartitionPrefix: $1"
	if [[ $1 =~ ^(mmcblk|loop|sd[a-z]) ]]; then
		local pref="$1"
		[[ $1 =~ ^(mmcblk|loop) ]] && pref="${1}p"
	else
		logItem "device: $1"
		assertionFailed $LINENO "Unable to retrieve partition prefix for device $1"
	fi

	logExit "getPartitionPrefix: $pref"
	echo "$pref"

}

# Input:
# 	/dev/mmcblk0p1
#	/dev/sda2
# Output:
# 	1
#	2

function getPartitionNumber() { # deviceName

	logEntry "getPartitionNumber $1"
	local id
	if [[ $1 =~ ^/dev/(?:mmcblk|loop)[0-9]+p([0-9]+) || $1 =~ ^/dev/sd[a-z]([0-9]+) ]]; then
		id=${BASH_REMATCH[1]}
	else
		assertionFailed $LINENO "Unable to retrieve partition number from deviceName $1"
	fi
	echo "$id"
	logExit "getPartitionNumber $id"

}

function isUpdatePossible() {

	logEntry "isUpdatePossible"

	versions=( $(isNewVersionAvailable) )
	version_rc=$?
	if [[ $version_rc == 0 ]]; then
		NEWS_AVAILABLE=1
		latestVersion=${versions[0]}
		newVersion=${versions[1]}
		oldVersion=${versions[2]}

		writeToConsole $MSG_LEVEL_MINIMAL $MSG_NEW_VERSION_AVAILABLE "$newVersion" "$oldVersion"
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_VISIT_VERSION_HISTORY_PAGE "$(getLocalizedMessage $MSG_VERSION_HISTORY_PAGE)"
	fi

	logExit "isUpdatePossible"

}

function downloadPropertiesFile() { # FORCE

	logEntry "downloadPropertiesFile"

	NEW_PROPERTIES_FILE=0

	if (( ! $REGRESSION_TEST )); then

		if shouldDownloadPropertiesFile "$1"; then

			writeToConsole $MSG_LEVEL_MINIMAL $MSG_CHECKING_FOR_NEW_VERSION
			local mode="N"; (( $PARTITIONBASED_BACKUP )) && mode="P"
			local type=$BACKUPTYPE
			local keep=$KEEPBACKUPS
			local func="B"; (( $RESTORE )) && func="R"

			local uuid="?"
			(( $USE_UUID )) && uuid="?uuid=$UUID&"

			local downloadURL="$PROPERTY_URL${uuid}version=$VERSION&type=$type&mode=$mode&keep=$keep&func=$func"

			wget $downloadURL -q --tries=$DOWNLOAD_RETRIES --timeout=$DOWNLOAD_TIMEOUT -O $LATEST_TEMP_PROPERTY_FILE
			local rc=$?
			if [[ $rc == 0 ]]; then
				logItem "Download of $downloadURL successfull"
				NEW_PROPERTIES_FILE=1
			else
				logItem "Download of $downloadURL failed with rc $rc"
			fi
		fi
	fi

	logExit "downloadPropertiesFile - $NEW_PROPERTIES_FILE"
	return
}

function isVersionDeprecated() { # versionNumber

	logEntry "isVersionDeprecated $1"

	local rc=1	# no/failure
	local properties=""
	local deprecated=""

	if (( $NEW_PROPERTIES_FILE && $HANDLE_DEPRECATED )); then
		properties=$(grep "^DEPRECATED=" "$LATEST_TEMP_PROPERTY_FILE" 2>/dev/null)
		logItem "Properties-Deprecated: $properties"
		[[ $properties =~ $PROPERTY_REGEX ]] && deprecated=${BASH_REMATCH[1]}
		local deprecatedVersions=( $deprecated )
		containsElement "$1" "${deprecatedVersions[@]}"
		(( $? )) && rc=0
	fi

	logExit "isVersionDeprecated $rc"
	return $rc
}

function shouldDownloadPropertiesFile() { # FORCE

	logEntry "shouldDownloadPropertiesFile"

	local rc

	local lastCheckTime

	if [[ -e $LATEST_TEMP_PROPERTY_FILE ]]; then
		lastCheckTime=$(stat -c %y $LATEST_TEMP_PROPERTY_FILE | cut -d ' ' -f 1 | sed 's/-//g')
	else
		lastCheckTime="00000000"
	fi

	local currentTime=$(date +%Y%m%d)

	logItem "$currentTime : $lastCheckTime"

	if [[ $currentTime == $lastCheckTime && "$1" != "FORCE" ]]; then
		logItem "Skip download"
		rc=1		#  download already done today
	else
		rc=0
	fi

	logExit "shouldDownloadPropertiesFile - rc: $rc"
	return $rc
}

function isNewVersionAvailable() {

	logEntry "isNewVersionAvailable"

	local oldVersion="0.0"
	local newVersion="0.0"
	local latestVersion="0.0"

	local rc=2			# update not possible

	if (( $NEW_PROPERTIES_FILE )); then
		properties=$(grep "^VERSION=" "$LATEST_TEMP_PROPERTY_FILE" 2>/dev/null)
		logItem "Properties-Version: $properties"
		local newVersion=""
		[[ $properties =~ $PROPERTY_REGEX ]] && newVersion=${BASH_REMATCH[1]}
		latestVersion=$(echo -e "$newVersion\n$VERSION" | sort -V | tail -1)
		logItem "new: $newVersion runtime: $VERSION latest: $latestVersion"

		if [[ $VERSION != $newVersion ]]; then
			if [[ $VERSION != $latestVersion ]]; then
				rc=0	# new version available
			else
				rc=3	# current version is latest version
			fi
		else
			rc=1		# no new version available
		fi
	fi

	result="$latestVersion $newVersion $VERSION"
	echo "$result"

	logItem "Returning: $result"

	logExit "isNewVersionAvailable - RC: $rc"

	return $rc

}

function stopServices() {

	logEntry "stopServices"

	if [[ -n "$STOPSERVICES" ]]; then
		if [[ "$STOPSERVICES" =~ $NOOP_AO_ARG_REGEX ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_SKIP_STOPPING_SERVICES
		else
			writeToConsole $MSG_LEVEL_DETAILED $MSG_STOPPING_SERVICES "$STOPSERVICES"
			logItem "$STOPSERVICES"
			if (( ! $FAKE_BACKUPS )); then
				executeShellCommand "$STOPSERVICES"
				local rc=$?
				if [[ $rc != 0 ]]; then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_STOP_SERVICES_FAILED "$rc"
					exitError $RC_STOP_SERVICES_ERROR
				fi
				STOPPED_SERVICES=1
			fi
		fi
	fi
	logExit "stopServices"
}

function startServices() { # noexit
	
	logEntry "startServices"

	if [[ -n "$STARTSERVICES" ]]; then
		if [[ "$STARTSERVICES" =~ $NOOP_AO_ARG_REGEX ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_SKIP_STARTING_SERVICES
		else
			writeToConsole $MSG_LEVEL_DETAILED $MSG_STARTING_SERVICES "$STARTSERVICES"
			logItem "$STARTSERVICES"
			if (( ! $FAKE_BACKUPS )); then
				executeShellCommand "$STARTSERVICES"
				local rc=$?
				if [[ $rc != 0 ]]; then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_START_SERVICES_FAILED "$rc"
					if [[ "$1" != "noexit" ]]; then 
						exitError $RC_START_SERVICES_ERROR
					fi
				fi
				STOPPED_SERVICES=0
			fi
		fi
	fi
	logExit "startServices"
}

# update script with latest version if needed

function updateScript() { # restart

	logEntry "updateScript"

	local rc
	local versions
	local latestVersion
	local newVersion
	local oldVersion
	local newName

	if (( $NEW_PROPERTIES_FILE )) ; then

		versions=( $(isNewVersionAvailable) )
		rc=$?

		latestVersion=${versions[0]}
		newVersion=${versions[1]}
		oldVersion=${versions[2]}

		if (( ! $FORCE_UPDATE )) ; then

			local incompatible=""
			local properties=$(grep "^INCOMPATIBLE=" "$LATEST_TEMP_PROPERTY_FILE" 2>/dev/null)
			logItem "Properties-Incompatible: $properties"
			if [[ $properties =~ $PROPERTY_REGEX ]]; then
				incompatible=${BASH_REMATCH[1]}
			fi

			local incompatibleVersions=( $incompatible )
			containsElement "$newVersion" "${incompatibleVersions[@]}"
			if (( $? )); then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_INCOMPATIBLE_UPDATE "$newVersion" "$(getLocalizedMessage $MSG_VERSION_HISTORY_PAGE)"
				exitNormal
			fi
		fi

		if [[ $rc == 0 ]]; then
			local file="${MYSELF}"
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_DOWNLOADING "$file" "$MYHOMEURL"
			logItem "Download URL: $DOWNLOAD_URL"
			if wget "$DOWNLOAD_URL" -q --tries=$DOWNLOAD_RETRIES --timeout=$DOWNLOAD_TIMEOUT -O $MYSELF~; then
				newName="$SCRIPT_DIR/$MYNAME.$oldVersion.sh"
				mv $SCRIPT_DIR/$MYSELF $newName
				mv $MYSELF~ $SCRIPT_DIR/$MYSELF
				chown --reference=$newName $SCRIPT_DIR/$MYSELF
				chmod --reference=$newName $SCRIPT_DIR/$MYSELF
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_SCRIPT_UPDATE_OK "$SCRIPT_DIR/$MYSELF" "$oldVersion" "$newVersion" "$newName"

				if [[ "$1" == "RESTART" ]]; then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_SCRIPT_RESTART "$newVersion"
					exec "$(which bash)" --noprofile "$0" "${invocationParms[@]}"
				fi
			fi

		else
			rm $MYSELF~ &>/dev/null
			if [[ $rc == 1 ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_SCRIPT_UPDATE_NOT_NEEDED "$SCRIPT_DIR/$MYSELF" "$newVersion"
			elif [[ $rc == 3 ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_SCRIPT_UPDATE_NOT_UPLOADED "$SCRIPT_DIR/$MYSELF" "$latestVersion" "$newVersion"
			else
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_SCRIPT_UPDATE_FAILED "$MYSELF"
			fi
		fi
	fi

	logExit "updateScript"

}

# 0 = yes, no otherwise

function supportsHardlinks() {	# directory

	logEntry "supportsHardlinks: $1"

	local links
	local result=1

	touch /$1/$MYNAME.hlinkfile
	cp -l /$1/$MYNAME.hlinkfile /$1/$MYNAME.hlinklink
	links=$(ls -la /$1/$MYNAME.hlinkfile | cut -f 2 -d ' ')
	logItem "Links: $links"
	[[ $links == 2 ]] && result=0
	rm -f /$1/$MYNAME.hlinkfile &>/dev/null
	rm -f /$1/$MYNAME.hlinklink &>/dev/null

	logExit "supportsHardlinks: $result"

	return $result
}

function isMounted() { # dir
	local rc
	logEntry "isMounted $1"
	if [[ -n "$1" ]]; then
		logItem $(cat /proc/mounts)
		$(grep -qs "$1" /proc/mounts)
		rc=$?
	else
		rc=1
	fi
	logExit "isMounted $rc"
	return $rc
}

function getFsType() { # file or path

	logEntry "getFsType: $1"

	local fstype=$(df -T "$1" | grep "^/" | awk '{ print $2 }')

    echo $fstype

    logExit "getFsType: $fstype"

}

# check if directory is located on a mounted device

function isPathMounted() {

	logEntry "isPathMounted: $1"

	local path
	local rc=1
	path=$1

	while [[ "$path" != "" ]]; do
		logItem "Path: $path"
		if mountpoint -q "$path"; then
			rc=0
			break
        fi
        path=${path%/*}
	done

	logExit "isPathMounted: $rc"

    return $rc
}

function readConfigParameters() {

	ETC_CONFIG_FILE="/usr/local/etc/${MYNAME}.conf"
	HOME_CONFIG_FILE="/home/$(findUser)/.${MYNAME}.conf"
	CURRENTDIR_CONFIG_FILE="$CURRENT_DIR/.${MYNAME}.conf"

	# Override default parms with parms in global config file

	ETC_CONFIG_FILE_INCLUDED=0
	if [ -f "$ETC_CONFIG_FILE" ]; then
		set -e
		. "$ETC_CONFIG_FILE"
		set +e
		ETC_CONFIG_FILE_INCLUDED=1

	fi

	if [[ -z $UUID && $UID == 0 ]]; then
		UUID="$(</proc/sys/kernel/random/uuid)"
		echo -e "\n# GENERATED - DO NOT DELETE " >> "$ETC_CONFIG_FILE"
		echo "UUID=$UUID" >> "$ETC_CONFIG_FILE"
	fi

	# Override default parms with parms in user config file

	HOME_CONFIG_FILE_INCLUDED=0
	if [ -f "$HOME_CONFIG_FILE" ]; then
		set -e
		. "$HOME_CONFIG_FILE"
		set +e
		HOME_CONFIG_FILE_INCLUDED=1
	fi

	# Override default parms with parms in current directory config file

	if [[ "$HOME_CONFIG_FILE" != "$CURRENTDIR_CONFIG_FILE " ]]; then
		CURRENTDIR_CONFIG_FILE_INCLUDED=0
		if [ -f "$CURRENTDIR_CONFIG_FILE" ]; then
			set -e
			. "$CURRENTDIR_CONFIG_FILE"
			set +e
			CURRENTDIR_CONFIG_FILE_INCLUDED=1
		fi
	fi

}

function setupEnvironment() {

	if (( ! $RESTORE )); then

		ZIP_BACKUP_TYPE_INVALID=0		# logging not enabled right now, invalid backuptype will be handled later
		if (( $ZIP_BACKUP )); then
			if [[ $BACKUPTYPE == $BACKUPTYPE_DD || $BACKUPTYPE == $BACKUPTYPE_TAR ]]; then
				BACKUPTYPE=${Z_TYPE_MAPPING[${BACKUPTYPE}]}	# tar-> tgz and dd -> ddz
			else
				ZIP_BACKUP_TYPE_INVALID=1
			fi
		fi

		BACKUPFILES_PARTITION_DATE="$HOSTNAME-backup"
		BACKUPFILE="${HOSTNAME}-${BACKUPTYPE}-backup-$DATE"

		if [[ -z "$BACKUP_DIRECTORY_NAME" ]]; then
			BACKUPTARGET_ROOT="$BACKUPPATH/$HOSTNAME"
		else
			BACKUPTARGET_ROOT="$BACKUPPATH/$HOSTNAME-${BACKUP_DIRECTORY_NAME}"
		fi

		BACKUPTARGET_DIR="$BACKUPTARGET_ROOT/$BACKUPFILE"
		BACKUPTARGET_FILE="$BACKUPTARGET_DIR/$BACKUPFILE${FILE_EXTENSION[$BACKUPTYPE]}"
		BACKUPTARGET_LOG_FILE="$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE"

		if [ ! -d "${BACKUPTARGET_DIR}" ]; then
			if ! mkdir -p "${BACKUPTARGET_DIR}"; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNABLE_TO_CREATE_DIRECTORY "${BACKUPTARGET_DIR}"
				exitError $RC_CREATE_ERROR
			fi
			
			NEW_BACKUP_DIRECTORY_CREATED=1
		fi

		BACKUPPATH=$(sed -E 's@/+$@@g' <<< "$BACKUPPATH")

		if [[ ! -d "$BACKUPPATH" ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_ARG_NOT_FOUND "$BACKUPPATH"
			exitError $RC_MISSING_FILES
		fi

		if ! touch "$BACKUPPATH/$MYNAME.tmp" &>/dev/null; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNABLE_TO_WRITE "$BACKUPPATH"
			exitError $RC_MISC_ERROR
		else
			rm -f "$BACKUPPATH/$MYNAME.tmp" &>/dev/null
		fi

	else
		LOG_OUTPUT=$LOG_OUTPUT_HOME
	fi

	TMP_LOG_FILE="$HOSTNAME-$MYNAME.log"

	if [[ $LOG_OUTPUT == $LOG_OUTPUT_VARLOG ]]; then
		LOG_BASE="/var/log/$MYNAME"
		if [ ! -d ${LOG_BASE} ]; then
		 if ! mkdir -p ${LOG_BASE}; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNABLE_TO_CREATE_DIRECTORY "${LOG_BASE}"
			exitError $RC_CREATE_ERROR
		 fi
		fi
		LOG_FILE="$LOG_BASE/$HOSTNAME.log"
	elif [[ $LOG_OUTPUT == $LOG_OUTPUT_HOME ]]; then
		LOG_FILE="$CURRENT_DIR/$MYNAME.log"
	else
		LOG_FILE="/var/log/syslog"
	fi

	LOG_FILE_FINAL="$LOG_FILE"

	if [[ $LOG_OUTPUT == $LOG_OUTPUT_BACKUPLOC ]]; then
		local user=$(findUser)
		LOG_FILE="/home/$user/$TMP_LOG_FILE"
		if [[ $user == "root" ]]; then
			LOG_FILE="/root/$TMP_LOG_FILE"
		fi
		TARGET_LOG_FILE="$BACKUPTARGET_LOG_FILE.log"
		LOG_FILE_FINAL="$TARGET_LOG_FILE"
	fi

	if [[ $LOG_OUTPUT != $LOG_OUTPUT_SYSLOG ]]; then	# keep syslog :-)
		rm -rf "$LOG_FILE" &>/dev/null
	fi

	LOGGING_ENABLED=1

	logItem "LOG_OUTPUT: $LOG_OUTPUT"
	logItem "Using logfile $LOG_FILE"

	if [[ -z "$LOG_FILE" || "$LOG_FILE" == *"*"* ]]; then
		assertionFailed $LINENO "Invalid log file $LOG_FILE"
	fi

	exec 1> >(stdbuf -i0 -o0 -e0 tee -a "$LOG_FILE" >&1)
	exec 2> >(stdbuf -i0 -o0 -e0 tee -a "$LOG_FILE" >&2)

	logItem "$GIT_CODEVERSION"

	logItem "BACKUPTARGET_DIR: $BACKUPTARGET_DIR"
	logItem "BACKUPTARGET_FILE: $BACKUPTARGET_FILE"
}

# deploy script on my local PIs

function deployMyself() {

	logEntry "deployMyself"

    for hostLogon in $DEPLOYMENT_HOSTS; do

		host=$(echo $hostLogon | cut -d '@' -f 2)
		user=$(echo $hostLogon | cut -d '@' -f 1)

		if [[ -z "$host" || -z "$user" ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_DEPLOYMENT_PARMS_ERROR
			exitError $RC_PARAMETER_ERROR
		fi

		if ping -c 1 $host &>/dev/null; then
			if [[ $user == "root" ]]; then
				scp -p $MYSELF $hostLogon:/usr/local/bin > /dev/null
			else
				scp -p $MYSELF $hostLogon:/home/$user > /dev/null
			fi
			if [[ $? == 0 ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_DEPLOYED_HOST "$host" "$user"
				exitError $RC_PARAMETER_ERROR
			else
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_DEPLOYMENT_FAILED "$host" "$user"
				exitError $RC_PARAMETER_ERROR
			fi
		else
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_DEPLOYING_HOST_OFFLINE "$host"
			exitError $RC_PARAMETER_ERROR
		fi
    done

   	logExit "deployMyself"

}

## partition table of /dev/sdc
#unit: sectors

#/dev/sdc1 : start=     8192, size=   114688, Id= c
#/dev/sdc2 : start=   122880, size= 30244864, Id=83
#/dev/sdc3 : start=        0, size=        0, Id= 0
#/dev/sdc4 : start=        0, size=        0, Id= 0

function calcSumSizeFromSFDISK() { # sfdisk file name

	logEntry "calcSumSizeFromSFDISK $1"

	local file="$1"

	logItem "File: $(cat $file)"

# /dev/mmcblk0p1 : start=     8192, size=    83968, Id= c
# or
# /dev/sdb1 : start=          63, size=  1953520002, type=83

	local partitionregex="/dev/.*[p]?([0-9]+)[^=]+=[^0-9]*([0-9]+)[^=]+=[^0-9]*([0-9]+)[^=]+=[^0-9a-z]*([0-9a-z]+)"
	local lineNo=0
	local sumSize=0

	while IFS="" read line; do
		(( lineNo++ ))
		if [[ -z $line ]]; then
			continue
		fi

		if [[ $line =~ $partitionregex ]]; then
			local p=${BASH_REMATCH[1]}
			local start=${BASH_REMATCH[2]}
			local size=${BASH_REMATCH[3]}
			local id=${BASH_REMATCH[4]}

			if [[ $id == 85 || $id == 5 ]]; then
				continue
			fi

			if [[ $sumSize == 0 ]]; then
				sumSize=$((start+size))
			else
				(( sumSize+=size ))
			fi
		fi

	done < $file

	(( sumSize *= 512 ))

	echo "$sumSize"

	logExit "calcSumSizeFromSFDISK $sumSize"
}

function sendEMail() { # content subject

	logEntry "sendEMail"

	if [ -n "$EMAIL" ]; then
		local attach
		local content
		local subject
		local rc

		local attach=""
		local subject="$2"

		if (( $APPEND_LOG )); then
			attach="-a $LOG_FILE"
			logItem "Appendlog $attach"
		fi

		if (( $NOTIFY_UPDATE && $NEWS_AVAILABLE )); then
				subject=";-) $subject"
		fi

		IFS=" "
		if [ -e "$LOG_MAIL_FILE" ]; then
			content="$NL$(<"$LOG_MAIL_FILE")$NL$1$NL"
		else
			content="$NL$1$NL"
		fi
		unset IFS

		logItem "Sending eMail with program $EMAIL_PROGRAM and parms '$EMAIL_PARMS'"
		logItem "Parm1:$1 Parm2:$subject"
		logItem "Content: $content"

		case $EMAIL_PROGRAM in
			$EMAIL_MAILX_PROGRAM) logItem "echo $content | $EMAIL_PROGRAM $EMAIL_PARMS -s $subject $attach $EMAIL"
				echo "$content" | "$EMAIL_PROGRAM" $EMAIL_PARMS -s "$subject" $attach "$EMAIL"
				rc=$?
				logItem "$EMAIL_PROGRAM: RC: $rc"
				;;
			$EMAIL_SENDEMAIL_PROGRAM) logItem "echo $content | $EMAIL_PROGRAM $EMAIL_PARMS -u $subject $attach -t $EMAIL"
				echo "$content" | "$EMAIL_PROGRAM" $EMAIL_PARMS -u "$subject" $attach -t "$EMAIL"
				rc=$?
				logItem "$EMAIL_PROGRAM: RC: $rc"
				;;
			$EMAIL_SSMTP_PROGRAM)
				if (( $APPEND_LOG )); then
					logItem "Sending email with mpack"
					echo "$content" > /tmp/$$
					mpack -s "$subject" -d /tmp/$$ "$LOG_FILE" "$EMAIL"
					rm /tmp/$$ &>/dev/null
				else
					logItem "Sendig email with ssmtp"
					logItem "echo -e To: $EMAIL\nFrom: root@$(hostname -f)\nSubject: $subject\n$content | $EMAIL_PROGRAM $EMAIL"
					echo -e "To: $EMAIL\nFrom: root@$(hostname -f)\nSubject: $subject\n$content" | "$EMAIL_PROGRAM" "$EMAIL"
					rc=$?
					logItem "$EMAIL_PROGRAM: RC: $rc"
				fi
				;;
			$EMAIL_EXTENSION_PROGRAM)
				local append=""
				(( $APPEND_LOG )) && append="$LOG_FILE"
				args=( "$EMAIL" "$subject" "$content" "$EMAIL_PARMS" "$append" )
				callExtensions $EMAIL_EXTENSION "${args[@]}"
				;;
			*) assertionFailed $LINENO  "Unsupported email programm $EMAIL_PROGRAM detected"
				;;
		esac
	fi
	logExit "sendEMail"

}

function noop() {
	:
}

function cleanupBackupDirectory() {

	logEntry "cleanupBackupDirectory"

	if [[ $rc != 0 ]] || (( $FAKE_BACKUPS )); then
		logItem "BackupDir created: $NEW_BACKUP_DIRECTORY_CREATED"
		if (( $NEW_BACKUP_DIRECTORY_CREATED )); then

			if [[ -z "$BACKUPPATH" || -z "$BACKUPFILE" || -z "$BACKUPTARGET_DIR" || "$BACKUPFILE" == *"*"* || "$BACKUPPATH" == *"*"* || "$BACKUPTARGET_DIR" == *"*"* ]]; then
				assertionFailed $LINENO "Invalid backup path detected. BP: $BACKUPPATH - BTD: $BACKUPTARGET_DIR - BF: $BACKUPFILE"
			fi

			writeToConsole $MSG_LEVEL_DETAILED $MSG_SAVING_LOG "$LOG_FILE"
			if (( $BACKUP_STARTED )); then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_REMOVING_BACKUP "$BACKUPTARGET_DIR"
			fi
			if [[ -d "$BACKUPTARGET_DIR" ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_CLEANING_BACKUPDIRECTORY "$BACKUPTARGET_DIR"
				rm -fr "$BACKUPTARGET_DIR" # remove incomplete backupdir if it exists
			fi
		fi
	else
		if [[ $LOG_OUTPUT == $LOG_OUTPUT_BACKUPLOC ]]; then
			logItem "Moving $LOG_FILE to $TARGET_LOG_FILE"
			mv "$LOG_FILE" "$TARGET_LOG_FILE"
			local user=$(findUser)
			if [[ $user != "root" ]]; then
				chown --reference=/home/$user "$TARGET_LOG_FILE"
			fi
		fi
	fi


#	logExit "cleanupBackupDirectory" --- doesn't work any more
}

function cleanup() { # trap

	logEntry "cleanup"

	trap noop SIGINT SIGTERM EXIT	# disable all interupts

	# no logging any more

	if (( $RESTORE )); then
		cleanupRestore $1
	else
		cleanupBackup $1
	fi

	cleanupTempFiles

	if (( ! $RESTORE )); then
		_no_more_locking
	fi

# 	borrowed from http://stackoverflow.com/questions/360201/kill-background-process-when-shell-script-exit

	if [[ $rc == $RC_NATIVE_BACKUP_FAILED ]]; then
		logItem "Terminate my subshells and myself $rc"
		trap - SIGINT SIGTERM EXIT	# disable interupts
		kill -s SIGINT 0
#		no return
	else
		logItem "Terminate now with rc $rc"
		exit $rc
	fi

	logExit "cleanup"

}

function cleanupRestore() { # trap

	logEntry "cleanupRestore"

	local error=0

	logItem "Got trap $1"
	logItem "rc: $rc"
	if [[ $1 == "SIGINT" ]]; then
		rc=$RC_CTRLC
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_CTRLC_DETECTED
	fi

	rm $$.sfdisk &>/dev/null

	if [[ -n $MNT_POINT ]]; then
		if isMounted $MNT_POINT; then
			logItem "Umount $MNT_POINT"
			umount $MNT_POINT &>>"$LOG_FILE"
		fi

		logItem "Deleting dir $MNT_POINT"
		rmdir $MNT_POINT &>>"$LOG_FILE"
	fi

	if (( rc != 0 )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_FAILED $rc
	else
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_OK
	fi

	logExit "cleanupRestore - exit with $rc"

}

function resizeRootFS() {

	logEntry "resizeRootFS"

	local partitionStart

	logItem "RESTORE_DEVICE: $RESTORE_DEVICE"
	logItem "ROOT_PARTITION: $ROOT_PARTITION"

	logItem "partitionLayout of $RESTORE_DEVICE"
	logItem "$(fdisk -l $RESTORE_DEVICE)"

	partitionStart="$(fdisk -l $RESTORE_DEVICE |  grep -E '^/dev/((mmcblk|loop)[0-9]+p|sd[a-z]+)2' | awk '{ print $2; }')"

	logItem "PartitionStart: $partitionStart"

	if [[ -z "$partitionStart" ]]; then
		writeToConsole $MSG_LEVEL_DETAILED $MSG_UNABLE_TO_CREATE_PARTITIONS ""
		exitError $RC_CREATE_PARTITIONS_FAILED
	fi

	fdisk $RESTORE_DEVICE &>> $LOG_FILE <<EOF
p
d
2
n
p
2
$partitionStart

p
w
q
EOF

	logExit "resizeRootFS"
}

function extractVersionFromFile() { # fileName
	echo $(grep "^VERSION=" "$1" | cut -f 2 -d = | sed  "s/\"//g" | sed "s/ .*#.*//")
}

function revertScriptVersion() {

	logEntry "revertScriptVersion"

	local existingVersionFiles=( $(ls $SCRIPT_DIR/$MYNAME.*sh) )

	if [[ ! -e "$SCRIPT_DIR/$MYSELF" ]]; then
		assertionFailed $LINENO "$SCRIPT_DIR/$MYSELF not found"
	fi

	local currentVersion=$(extractVersionFromFile "$SCRIPT_DIR/$MYSELF")
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_CURRENT_SCRIPT_VERSION "$currentVersion"

	declare -A versionsOfFiles

	local version
	for versionFile in "${existingVersionFiles[@]}"; do
		version=$(extractVersionFromFile "$versionFile")
		if [[ $version != $currentVersion ]]; then
			versionsOfFiles+=([$version]=$versionFile)
		fi
	done

	for version in "${!versionsOfFiles[@]}"; do
		logItem "$version: ${versionsOfFiles[$version]}"
	done

	local sortedVersions=( $(echo -e "${!versionsOfFiles[@]}" | sed -e 's/ /\n/g' | sort) )

	local min=0
	local max=$(( ${#sortedVersions[@]} - 1))

	if [[ $max == -1 ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_PREVIOUS_VERSIONS_AVAILABLE
		return
	fi

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_AVAILABLE_VERSIONS_HEADER
	for version in "${!sortedVersions[@]}"; do
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_AVAILABLE_VERSIONS "$version" "${sortedVersions[$version]}"
	done

	local selection
	local valid=0
	while (( ! $valid )); do
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_SELECT_VERSION "$min" "$max"
		read selection
		if [[ "$selection" < $min || "$selection" > $max ]]; then
			continue
		fi

		version=${sortedVersions[$selection]}
		valid=1
	done

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_SAVING_ACTUAL_VERSION "$currentVersion" "$MYNAME.$currentVersion.sh"
	logItem "mv $SCRIPT_DIR/$MYNAME.sh $SCRIPT_DIR/$MYNAME.$currentVersion.sh"
	mv "$SCRIPT_DIR/$MYNAME.sh" "$SCRIPT_DIR/$MYNAME.$currentVersion.sh"

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORING_PREVIOUS_VERSION "$version" "$MYNAME.sh"
	logItem "cp -a ${versionsOfFiles[$version]} $SCRIPT_DIR/$MYNAME.sh"
	cp -a "${versionsOfFiles[$version]}" "$SCRIPT_DIR/$MYNAME.sh"

	logExit "revertScriptVersion"

}

function isBetaAvailable() {

	logEntry "isBetaAvailable"

	local downloadURL="$PROPERTY_URL"
	local betaVersion=""

	if (( $NEW_PROPERTIES_FILE )); then
		local tmpFile=$(mktemp)

		writeToConsole $MSG_LEVEL_DETAILED $MSG_CHECKING_FOR_BETA
		wget $downloadURL -q --tries=$DOWNLOAD_RETRIES --timeout=$DOWNLOAD_TIMEOUT -O $tmpFile
		local rc=$?
		if [[ $rc == 0 ]]; then
			properties=$(grep "^BETA=" "$tmpFile" 2>/dev/null)
			local betaVersion=$(cut -d '=' -f 2 <<< $properties)
			betaVersion=${betaVersion//\"/}
		fi

		rm $tmpFile	 &>/dev/null
	fi

	echo $betaVersion

	logExit "isBetaAvailable: $betaVersion"

}

function cleanupBackup() { # trap

	logEntry "cleanupBackup"

	logItem "Got trap $1"
	logItem "rc: $rc"

	if [[ $1 == "SIGINT" ]]; then
		rc=$RC_CTRLC
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_CTRLC_DETECTED
	fi

	if (( $rc !=  0 )); then

		echo "Invocation parms: '$INVOCATIONPARMS'" >> "$LOG_FILE"

		if [[ $rc == $RC_STOP_SERVICES_ERROR ]] || (( $STOPPED_SERVICES )); then
			startServices "noexit"
		fi

		msg=$(getLocalizedMessage $MSG_BACKUP_FAILED)
		msgTitle=$(getLocalizedMessage $MSG_TITLE_ERROR $HOSTNAME)
		logItem "emailTitle: $msgTitle"
		if [ -n "$EMAIL" ]; then
			if [[ $rc != $RC_CTRLC ]]; then
				sendEMail "$msg" "$msgTitle"
			fi
		fi

	else
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_OK

		if (( ! $MAIL_ON_ERROR_ONLY )); then
			msg=$(getLocalizedMessage $MSG_TITLE_OK $HOSTNAME)
			logItem "emailTitle: $msg"
			if [ -n "$EMAIL" ]; then
				if [[ $rc != $RC_CTRLC ]]; then
					sendEMail "" "$msg"
				fi
			fi
		fi
	fi

	if (( $PARTITIONBASED_BACKUP )); then
		umountSDPartitions "$TEMPORARY_MOUNTPOINT_ROOT"
	fi

	cleanupBackupDirectory

	if [[ $rc != 0 ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_FAILED
	fi

	logExit  "cleanupBackup"

}

function cleanupTempFiles() {

	logEntry "cleanupTempFiles"

	if [[ -f "$LOG_MAIL_FILE" ]]; then
		logItem "Removing mailfile $LOG_MAIL_FILE"
		rm -f "$LOG_MAIL_FILE" &>/dev/null
	fi

	if [[ -f $MYSELF~ ]]; then
		logItem "Removing newversion $MYSELF~"
		rm -f $MYSELF~ &>/dev/null
	fi

	if [[ -f $LOG_TOOL_FILE ]]; then
		logItem "Removing $LOG_TOOL_FILE"
		rm -f $LOG_TOOL_FILE &>/dev/null
	fi

	logExit "cleanupTempFiles"

}

function checkAndCorrectImportantParameters() {

		local invalidOutput=""
		local invalidLanguage=""
		local invalidLogLevel=""
		local invalidMsgLevel=""

		if [[ $LOG_OUTPUT < 0 || $LOG_OUTPUT > ${#LOG_OUTPUT_LOCs[@]} ]]; then
			invalidOutput=$LOG_OUTPUT
			LOG_OUTPUT=$LOG_OUTPUT_SYSLOG
		fi

		if [[ $LOG_LEVEL < 0 || $LOG_LEVEL > ${#LOG_LEVELs[@]} ]]; then
			invalidLogLevel=$LOG_LEVEL
			LOG_LEVEL=$LOG_NONE
		fi

		[[ $LOG_LEVEL == $LOG_TYPE_DEBUG ]] && MSG_LEVEL=$MSG_LEVEL_DETAILED

		if [[ $MSG_LEVEL < 0 || $MSG_LEVEL > ${#MSG_LEVELs[@]} ]]; then
			invalidMsgLevel=$MSG_LEVEL
			MSG_LEVEL=$MSG_LEVEL_MINIMAL
		fi

		local msgVar="MSG_${LANGUAGE}"
		if [[ -z ${!msgVar} ]]; then
			invalidLanguage=$LANGUAGE
			LANGUAGE="EN"
		fi

		[[ -n $invalidOutput ]] && writeToConsole $MSG_LEVEL_MINIMAL $MSG_INVALID_LOG_OUTPUT "$invalidOutput" "${LOG_OUTPUTs[$LOG_OUTPUT]}"
		[[ -n $invalidMsgLevel ]] && writeToConsole $MSG_LEVEL_MINIMAL $MSG_INVALID_MSG_LEVEL "$invalidMsgLevel" "${MSG_LEVELs[$MSG_LEVEL]}"
		[[ -n $invalidLanguage ]] && writeToConsole $MSG_LEVEL_MINIMAL $MSG_LANGUAGE_NOT_SUPPORTED "$invalidLanguage" "$LANGUAGE"
		[[ -n $invalidLogLevel ]] &&  writeToConsole $MSG_LEVEL_MINIMAL $MSG_INVALID_LOG_LEVEL "$invalidLogLevel" "${LOG_LEVELs[$LOG_LEVEL]}"

}

function createLinks() { # backuptargetroot extension newfile

	logEntry "createLinks $1 $2 $3"
	local file

	local possibleLinkTargetDirectory=$(ls -d $1/*-$BACKUPTYPE-backup-* 2>/dev/null | tail -2 | head -1)

	if [[ -z $possibleLinkTargetDirectory || $possibleLinkTargetDirectory == $BACKUPTARGET_DIR ]]; then
		logItem "No possible link target directory found"
		return
	fi

	logItem "PossibleLinkTargetDirectory: $possibleLinkTargetDirectory"
	local possibleLinkTarget=$(find $possibleLinkTargetDirectory/* -maxdepth 1 -name $HOSTNAME-backup.$2)
	logItem "Possible link target: $possibleLinkTarget"

	if [[ -z $possibleLinkTarget ]]; then
		logItem "No possible link target found"
		return
	fi

	if cmp -s $3 $possibleLinkTarget; then
		rm $3 &>/dev/null
		writeToConsole $MSG_LEVEL_DETAILED $MSG_REPLACING_FILE_BY_HARDLINK "$3" "$possibleLinkTarget"
		cp -l "$possibleLinkTarget" "$3" &>/dev/null
		rc=$?
		if [[ $rc != 0 ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_HARDLINK_ERROR "$rc"
			exitError $RC_LINK_FILE_FAILED
		fi
		local links="$(stat -c %h -- "$3")"
		if (( links < 2 )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_HARDLINK_ERROR "$rc"
			exitError $RC_LINK_FILE_FAILED
		fi
	fi

	logExit "createLinks"
}

function bootPartitionBackup() {

		logEntry "bootPartitionBackup"

		local p
		local rc

		logItem "Starting boot partition backup..."

		writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_CREATING_PARTITION_INFO

		if (( ! $FAKE && ! $EXCLUDE_DD )); then
			if  [[ ! -e "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.img" ]]; then
				writeToConsole $MSG_LEVEL_DETAILED $MSG_CREATING_BOOT_BACKUP "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.img"
				if (( $FAKE_BACKUPS )); then
					touch "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.img"
				else
					cmd="dd if=/dev/${BOOT_PARTITION_PREFIX}1 of=\"$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.img\" bs=1M &>>$LOG_FILE"
					executeCommand "$cmd"
					rc=$?
					if [ $rc != 0 ]; then
						writeToConsole $MSG_LEVEL_MINIMAL $MSG_IMG_DD_FAILED ".img" "$rc"
						exitError $RC_DD_IMG_FAILED
					fi
				fi

				if (( $LINK_BOOTPARTITIONFILES )); then
					createLinks "$BACKUPTARGET_ROOT" "img" "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.img"
				fi

			else
				logItem "Found existing backup of boot partition $BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.img ..."
				writeToConsole $MSG_LEVEL_DETAILED $MSG_EXISTING_BOOT_BACKUP "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.img"
			fi

			if  [[ ! -e "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.sfdisk" ]]; then
				writeToConsole $MSG_LEVEL_DETAILED $MSG_CREATING_PARTITION_BACKUP "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.sfdisk"
				sfdisk -d $BOOT_DEVICENAME > "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.sfdisk" 2>>$LOG_FILE
				local rc=$?
				if [ $rc != 0 ]; then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNABLE_TO_COLLECT_PARTITIONINFO "sfdisk" "$rc"
					exitError $RC_COLLECT_PARTITIONS_FAILED
				fi
				logItem "sfdisk"
				logItem $(cat "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.sfdisk")

				if (( $LINK_BOOTPARTITIONFILES )); then
					createLinks "$BACKUPTARGET_ROOT" "sfdisk" "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.sfdisk"
				fi

			else
				logItem "Found existing backup of partition layout $BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.sfdisk ..."
				writeToConsole $MSG_LEVEL_DETAILED $MSG_EXISTING_PARTITION_BACKUP "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.sfdisk"
			fi

			if  [[ ! -e "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.mbr" ]]; then
				writeToConsole $MSG_LEVEL_DETAILED $MSG_CREATING_MBR_BACKUP "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.mbr"
				if (( $FAKE_BACKUPS )); then
					touch "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.mbr"
				else
					dd if=$BOOT_DEVICENAME of="$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.mbr" bs=512 count=1 &>>$LOG_FILE
					local rc=$?
					if [ $rc != 0 ]; then
						writeToConsole $MSG_LEVEL_MINIMAL $MSG_IMG_DD_FAILED ".mbr" "$rc"
						exitError $RC_COLLECT_PARTITIONS_FAILED
					fi
				fi

				if (( $LINK_BOOTPARTITIONFILES )); then
					createLinks "$BACKUPTARGET_ROOT" "mbr" "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.mbr"
				fi

			else
				logItem "Found existing backup of master boot record $BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.mbr ..."
				writeToConsole $MSG_LEVEL_DETAILED $MSG_EXISTING_MBR_BACKUP "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.mbr"
			fi
		fi

		logItem "Finished boot partition backup..."

		logExit  "bootPartitionBackup"

}
function partitionLayoutBackup() {

		logEntry "partitionLayoutBackup"

		local p partitionname rc

		writeToConsole $MSG_LEVEL_DETAILED $MSG_BACKUP_CREATING_PARTITION_INFO

		SF_FILE="$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.sfdisk"
		MBR_FILE="$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.mbr"
		BLKID_FILE="$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.blkid"
		PARTED_FILE="$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.parted"
		FDISK_FILE="$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.fdisk"

		writeToConsole $MSG_LEVEL_DETAILED $MSG_CREATING_PARTITION_BACKUP "$SF_FILE"
		sfdisk -d $BOOT_DEVICENAME > "$SF_FILE" 2>>$LOG_FILE
		local rc=$?
		if [ $rc != 0 ]; then
			writeToConsole $MSG_LEVEL_DETAILED $MSG_UNABLE_TO_COLLECT_PARTITIONINFO "sfdisk" "$rc"
			exitError $RC_COLLECT_PARTITIONS_FAILED
		fi
		logItem "sfdisk"
		logItem "$(<"$SF_FILE")"

		writeToConsole $MSG_LEVEL_DETAILED $MSG_CREATING_PARTITION_BACKUP "$BLKID_FILE"
		logItem "Saving blkid"
		blkid > "$BLKID_FILE"
		local rc=$?
		if [ $rc != 0 ]; then
			writeToConsole $MSG_LEVEL_DETAILED $MSG_UNABLE_TO_COLLECT_PARTITIONINFO "blkid" "$rc"
			exitError $RC_COLLECT_PARTITIONS_FAILED
		fi
		logItem "blkid"
		logItem "$(<"$BLKID_FILE")"

		writeToConsole $MSG_LEVEL_DETAILED $MSG_CREATING_PARTITION_BACKUP "$PARTED_FILE"
		logItem "Saving parted"
		parted -m $BOOT_DEVICENAME print > "$PARTED_FILE"
		local rc=$?
		if [ $rc != 0 ]; then
			writeToConsole $MSG_LEVEL_DETAILED $MSG_UNABLE_TO_COLLECT_PARTITIONINFO "parted" "$rc"
			exitError $RC_COLLECT_PARTITIONS_FAILED
		fi
		logItem "parted"
		logItem "$(<"$PARTED_FILE")"

		writeToConsole $MSG_LEVEL_DETAILED $MSG_CREATING_PARTITION_BACKUP "$FDISK_FILE"
		logItem "Saving fdisk"
		fdisk -l $BOOT_DEVICENAME > "$FDISK_FILE"
		local rc=$?
		if [ $rc != 0 ] ; then
			writeToConsole $MSG_LEVEL_DETAILED $MSG_UNABLE_TO_COLLECT_PARTITIONINFO "fdisk" "$rc"
			exitError $RC_COLLECT_PARTITIONS_FAILED
		fi
		logItem "fdisk"
		logItem "$(<"$FDISK_FILE")"

		writeToConsole $MSG_LEVEL_DETAILED $MSG_CREATING_MBR_BACKUP "$MBR_FILE"
		if (( $FAKE_BACKUPS )); then
			touch "$MBR_FILE"
		else
			dd if=$BOOT_DEVICENAME of="$MBR_FILE" bs=512 count=1 &>>$LOG_FILE
			rc=$?
			if [ $rc != 0 ]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_IMG_DD_FAILED ".mbr" "$rc"
				exitError $RC_COLLECT_PARTITIONS_FAILED
			fi
		fi

		logExit  "partitionLayoutBackup"

}

function ddBackup() {

	logEntry  "ddBackup"

	local cmd verbose partition fakecmd cnt

	(( $VERBOSE )) && verbose="-v" || verbose=""

	if (( $PARTITIONBASED_BACKUP )); then
		fakecmd="touch \"${BACKUPTARGET_DIR}/$partitionName${FILE_EXTENSION[$BACKUPTYPE]}\""

		partition="${BOOT_DEVICENAME}p$1"
		partitionName="${BOOT_PARTITION_PREFIX}$1"

		if [[ $BACKUPTYPE == $BACKUPTYPE_DDZ ]]; then
			if (( $PARTITION )); then			
				cmd="dd if=$partition bs=$DD_BLOCKSIZE $DD_PARMS | pv -fs $(fdisk -l $partition | grep Disk.*$partition | cut -d ' ' -f 5) | gzip ${verbose} > \"${BACKUPTARGET_DIR}/$partitionName${FILE_EXTENSION[$BACKUPTYPE]}\""
			else
				cmd="dd if=$partition bs=$DD_BLOCKSIZE $DD_PARMS | gzip ${verbose} > \"${BACKUPTARGET_DIR}/$partitionName${FILE_EXTENSION[$BACKUPTYPE]}\""
			fi
		else
			if (( $PROGRESS )); then
				cmd="dd if=$partition bs=$DD_BLOCKSIZE $DD_PARMS | pv -fs $(fdisk -l $partition | grep Disk.*$partition | cut -d ' ' -f 5) | dd of=\"${BACKUPTARGET_DIR}/$partitionName${FILE_EXTENSION[$BACKUPTYPE]}\""
			else
				cmd="dd if=$partition bs=$DD_BLOCKSIZE $DD_PARMS of=\"${BACKUPTARGET_DIR}/$partitionName${FILE_EXTENSION[$BACKUPTYPE]}\""
			fi				
		fi

	else
		fakecmd="touch \"$BACKUPTARGET_FILE\""

		if (( ! $DD_BACKUP_SAVE_USED_PARTITIONS_ONLY )); then
			if [[ $BACKUPTYPE == $BACKUPTYPE_DDZ ]]; then
				if (( $PROGRESS )); then
					cmd="dd if=$BOOT_DEVICENAME bs=$DD_BLOCKSIZE $DD_PARMS | pv -fs $(fdisk -l $BOOT_DEVICENAME | grep Disk.*$BOOT_DEVICENAME | cut -d ' ' -f 5) | gzip ${verbose} > \"$BACKUPTARGET_FILE\""
				else
					cmd="dd if=$BOOT_DEVICENAME bs=$DD_BLOCKSIZE $DD_PARMS | gzip ${verbose} > \"$BACKUPTARGET_FILE\""
				fi
			else
				if (( $PROGRESS )); then
					cmd="dd if=$BOOT_DEVICENAME bs=$DD_BLOCKSIZE $DD_PARMS | pv -fs $(fdisk -l $BOOT_DEVICENAME | grep Disk.*$BOOT_DEVICENAME | cut -d ' ' -f 5) | dd of=\"$BACKUPTARGET_FILE\""
				else
					cmd="dd if=$BOOT_DEVICENAME bs=$DD_BLOCKSIZE $DD_PARMS of=\"$BACKUPTARGET_FILE\""				
				fi
			fi
		else
			logItem "$(fdisk -l $BOOT_DEVICENAME)"
			local lastByte=$(lastUsedPartitionByte $BOOT_DEVICENAME)
			local spaceUsedHuman=$(bytesToHuman $lastByte)
			local sdcardSize=$(blockdev --getsize64 $BOOT_DEVICENAME)
			local sdcardSizeHuman=$(bytesToHuman $sdcardSize)
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_TRUNCATING_TO_USED_PARTITIONS_ONLY "$sdcardSizeHuman" "$spaceUsedHuman"

			local count blocksize
			(( blocksize=1024*1024 ))		# 1MB hard coded
			(( count = lastByte / blocksize ))
			logItem "Count: $count"
			if (( count * blocksize < lastByte )); then
				(( count++ ))
				logItem "Updated count: $count"
			fi

			if [[ $BACKUPTYPE == $BACKUPTYPE_DDZ ]]; then
				if (( $PROGRESS )); then
					cmd="dd if=$BOOT_DEVICENAME bs=$blocksize count=$count | pv -fs $(fdisk -l $BOOT_DEVICENAME | grep Disk.*$BOOT_DEVICENAME | cut -d ' ' -f 5) | gzip ${verbose} > \"$BACKUPTARGET_FILE\""
				else
					cmd="dd if=$BOOT_DEVICENAME bs=$blocksize count=$count | gzip ${verbose} > \"$BACKUPTARGET_FILE\""
				fi
			else
				if (( $PROGRESS )); then
					cmd="dd if=$BOOT_DEVICENAME bs=$blocksize count=$count | pv -fs $(fdisk -l $BOOT_DEVICENAME | grep Disk.*$BOOT_DEVICENAME | cut -d ' ' -f 5) | dd of=\"$BACKUPTARGET_FILE\""
				else
					cmd="dd if=$BOOT_DEVICENAME bs=$blocksize count=$count of=\"$BACKUPTARGET_FILE\""
				fi
			fi

		fi
	fi

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_STARTED "$BACKUPTYPE"

	if (( ! $EXCLUDE_DD )); then
		if (( $FAKE_BACKUPS )); then
			executeCommand "$fakecmd"
		elif (( ! $FAKE)); then
			executeCommand "$cmd"
			rc=$?
		else
			rc=0
		fi
	fi

	logExit  "ddBackup $rc"

	return $rc
}

function tarBackup() {

	local verbose zip cmd partition source target fakecmd excludeRoot sourceDir partSize

	logEntry  "tarBackup"

	(( $PROGRESS )) && VERBOSE=1

	(( $VERBOSE )) && verbose="-v" || verbose=""
	[[ $BACKUPTYPE == $BACKUPTYPE_TGZ ]] && zip="-z" || zip=""

	if (( $PARTITIONBASED_BACKUP )); then
		partition="${BOOT_PARTITION_PREFIX}$1"

		source="."
		sourceDir="$TEMPORARY_MOUNTPOINT_ROOT/$partition"
		target="\"${BACKUPTARGET_DIR}/$partition${FILE_EXTENSION[$BACKUPTYPE]}\""

	else
		bootPartitionBackup
		source="/"
		target="\"$BACKUPTARGET_FILE\""
	fi

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_MAIN_BACKUP_PROGRESSING $BACKUPTYPE "${target//\\/}"

	cmd="tar \
		$TAR_BACKUP_OPTIONS \
		$TAR_BACKUP_ADDITIONAL_OPTIONS \
		${zip} \
		${verbose} \
		-f $target \
		--one-file-system \
		--warning=no-xdev \
		--numeric-owner \
		--exclude=\"$BACKUPPATH_PARAMETER\" \
		--exclude=proc/* \
		--exclude=lost+found/* \
		--exclude=sys/* \
		--exclude=dev/* \
		--exclude=tmp/* \
		--exclude=boot/* \
		--exclude=run/* \
		$EXCLUDE_LIST \
		$source"

	(( $PARTITIONBASED_BACKUP )) && pushd $sourceDir &>>$LOG_FILE

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_STARTED "$BACKUPTYPE"

	if (( $FAKE_BACKUPS )); then
		fakecmd="touch $target"
		executeCommand "$fakecmd"
	elif (( ! $FAKE )); then
		executeCommand "${pvCmd}${cmd}" 1
		rc=$?
	else
		rc=0
	fi
	(( $PARTITIONBASED_BACKUP )) && popd &>>$LOG_FILE

	if [[ $rc -eq 1 ]]; then		# some files changed during backup or vanished during backup
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILES_CHANGE_DURING_BACKUP $rc
		rc=0
	fi

	logExit  "tarBackup $rc"

	return $rc
}

function rsyncBackup() { # partition number (for partition based backup)

	local verbose partition target source fakecmd faketarget excludeRoot cmd cmdParms

	logEntry  "rsyncBackup"

	(( $PROGRESS )) && VERBOSE=0

	(( $VERBOSE )) && verbose="-v" || verbose=""

	logItem "ls $(ls $BACKUPTARGET_ROOT)"

	if (( $PARTITIONBASED_BACKUP )); then
		partition="${BOOT_PARTITION_PREFIX}$1"
		target="\"${BACKUPTARGET_DIR}\""
		faketarget="\"${BACKUPTARGET_DIR}/$partition\""
		source="$TEMPORARY_MOUNTPOINT_ROOT/$partition"

		lastBackupDir=$(find "$BACKUPTARGET_ROOT" -maxdepth 1 -type d -name "*-$BACKUPTYPE-*" ! -name $BACKUPFILE 2>>/dev/null | sort | tail -n 1)
		excludeRoot="/$partition"

	else
		target="\"${BACKUPTARGET_DIR}\""
		faketarget="\"${BACKUPTARGET_DIR}/boot\""
		source="/"

		bootPartitionBackup
		lastBackupDir=$(find "$BACKUPTARGET_ROOT" -maxdepth 1 -type d -name "*-$BACKUPTYPE-*" ! -name $BACKUPFILE 2>>/dev/null | sort | tail -n 1)
		excludeRoot="/"
	fi

	logItem "LastBackupDir: $lastBackupDir"

	if  [[ -z "$lastBackupDir" ]]; then
		LINK_DEST=""
	else
		LINK_DEST="--link-dest=\"$lastBackupDir\""
	fi

	logItem "LinkDest: $LINK_DEST"

	if [[ -n $LINK_DEST ]]; then
		writeToConsole $MSG_LEVEL_DETAILED $MSG_HARDLINK_DIRECTORY_USED "$lastBackupDir"
	fi

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_MAIN_BACKUP_PROGRESSING $BACKUPTYPE "${target//\\/}"

	cmdParms="--exclude=\"$BACKUPPATH_PARAMETER\" \
			--exclude=$excludeRoot/proc/* \
			--exclude=$excludeRoot/lost+found/* \
			--exclude=$excludeRoot/sys/* \
			--exclude=$excludeRoot/dev/* \
			--exclude=$excludeRoot/boot/* \
			--exclude=$excludeRoot/tmp/* \
			--exclude=$excludeRoot/run/* \
			$EXCLUDE_LIST \
			$LINK_DEST \
			--numeric-ids \
			$RSYNC_BACKUP_OPTIONS \
			$RSYNC_BACKUP_ADDITIONAL_OPTIONS \
			$verbose \
			$source \
			$target \
			"

	if (( $PROGRESS )); then
		cmd="rsync --info=progress2 $cmdParms"
	else
		cmd="rsync $cmdParms"
	fi

	fakecmd="mkdir -p $faketarget"

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_STARTED "$BACKUPTYPE"

	if (( $FAKE_BACKUPS )); then
		executeCommand "$fakecmd"
	elif (( ! $FAKE )); then
		executeCommand "$cmd" 23 24
		rc=$?
	else
		rc=0
	fi

	if [[ $rc -eq 23 || $rc -eq 24 ]]; then		# some files changed during backup or vanished during backup
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILES_CHANGE_DURING_BACKUP $rc
		rc=0
	fi

	logExit  "rsyncBackup $rc"

}

function restore() {

	logEntry "restore"

	rc=0
	local verbose zip

	(( $VERBOSE )) && verbose="v" || verbose=""

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORING_FILE "$RESTOREFILE"
	logItem "$(ls -la $RESTOREFILE)"

	rc=$RC_NATIVE_RESTORE_FAILED

	case $BACKUPTYPE in

		$BACKUPTYPE_DD|$BACKUPTYPE_DDZ)

			if [[ $BACKUPTYPE == $BACKUPTYPE_DD ]]; then
				if (( $PROGRESS )); then
					cmd="dd if=\"$ROOT_RESTOREFILE\" | pv -fs $(stat -c %s "$ROOT_RESTOREFILE") | dd of=$RESTORE_DEVICE bs=$DD_BLOCKSIZE $DD_PARMS"
				else 
					cmd="dd of=$RESTORE_DEVICE bs=$DD_BLOCKSIZE if=\"$ROOT_RESTOREFILE\" $DD_PARMS"
				fi
			else
				if (( $PROGRESS )); then
					cmd="gunzip -c \"$ROOT_RESTOREFILE\" | pv -fs $(stat -c %s "$ROOT_RESTOREFILE") | dd of=$RESTORE_DEVICE bs=$DD_BLOCKSIZE $DD_PARMS"
				else
					cmd="gunzip -c \"$ROOT_RESTOREFILE\" | dd of=$RESTORE_DEVICE bs=$DD_BLOCKSIZE $DD_PARMS"
				fi
			fi

			executeCommand "$cmd"
			rc=$?

			if [[ $rc != 0 ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_PROGRAM_ERROR $BACKUPTYPE $rc
				exitError $RC_NATIVE_RESTORE_FAILED
			fi
			;;

		*)	MNT_POINT="$TEMPORARY_MOUNTPOINT_ROOT/${MYNAME}"

			if ( isMounted "$MNT_POINT" ); then
				logItem "$MNT_POINT mounted - unmouting"
				umount "$MNT_POINT"
			else
				logItem "$MNT_POINT not mounted"
			fi

			logItem "Creating mountpoint $MNT_POINT"
			mkdir -p $MNT_POINT

			logItem "Umounting partitions"
			umount $BOOT_PARTITION &>>"$LOG_FILE"
			rc=$?
			if (( ! $rc )); then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_UMOUNT_ERROR "BOOT_PARTITION" "$rc"
				exitError $RC_MISC_ERROR
			fi
			umount $ROOT_PARTITION &>>"$LOG_FILE"
			rc=$?
			if (( ! $rc )); then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_UMOUNT_ERROR "ROOT_PARTITION" "$rc"
				exitError $RC_MISC_ERROR
			fi

			if (( ! $SKIP_SFDISK || $FORCE_SFDISK )); then

				cp "$SF_FILE" $$.sfdisk
				logItem ".sfdisk: $(cat $$.sfdisk)"

				writeToConsole $MSG_LEVEL_DETAILED $MSG_RESTORING_MBR "$MBR_FILE" "$RESTORE_DEVICE"
				dd of=$RESTORE_DEVICE if="$MBR_FILE" count=1 &>>"$LOG_FILE"
				rc=$?
				if [ $rc != 0 ]; then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_IMG_DD_FAILED ".mbr" "$rc"
					exitError $RC_NATIVE_RESTORE_FAILED
				fi

				sync

				if (( $FORCE_SFDISK )); then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_FORCING_CREATING_PARTITIONS
				elif (( $SKIP_SFDISK )); then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_SKIP_CREATING_PARTITIONS
				else
					writeToConsole $MSG_LEVEL_DETAILED $MSG_CREATING_PARTITIONS "$RESTORE_DEVICE"
				fi

				if (( ! $ROOT_PARTITION_DEFINED )); then
					local sourceSDSize=$(calcSumSizeFromSFDISK "$SF_FILE")
					local targetSDSize=$(blockdev --getsize64 $RESTORE_DEVICE)

					if (( sourceSDSize != targetSDSize )); then

	## partition table of /dev/mmcblk0
	#unit: sectors

	#/dev/mmcblk0p1 : start=     8192, size=   114688, Id= c
	#/dev/mmcblk0p2 : start=   122880, size= 15523840, Id=83
	#/dev/mmcblk0p3 : start=        0, size=        0, Id= 0
	#/dev/mmcblk0p4 : start=        0, size=        0, Id= 0

						local sourceValues=( $(awk '/(1|2) :/ { v=$4 $6; gsub(","," ",v); printf "%s",v }' "$SF_FILE") )
						if [[ ${#sourceValues[@]} != 4 ]]; then
							logItem "$(cat $SF_FILE)"
							assertionFailed $LINENO "Expected 4 partitions in $SF_FILE"
						fi

						# Backup partition has only one partition -> external root partition -> -R has to be specified
						if (( ${sourceValues[2]} == 0 )) || (( ${sourceValues[3]} == 0 )); then
							writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_R_OPTION 
							exitError $RC_MISC_ERROR							
						fi

						local adjustedTargetPartitionBlockSize=$(( $targetSDSize / 512 - ${sourceValues[1]} - ${sourceValues[0]} ))
						logItem "sourceSDSize: $sourceSDSize - targetSDSize: $targetSDSize"
						logItem "sourceBlockSize: ${sourceValues[3]} - adjusted targetBlockSize: $adjustedTargetPartitionBlockSize"

						local newTargetPartitionSize=$(( adjustedTargetPartitionBlockSize * 512 ))
						local oldPartitionSourceSize=$(( ${sourceValues[3]} * 512 ))

						sed -i "/2 :/ s/${sourceValues[3]}/$adjustedTargetPartitionBlockSize/" $$.sfdisk
						writeToConsole $MSG_LEVEL_MINIMAL $MSG_ADJUSTING_SECOND "$(bytesToHuman $oldPartitionSourceSize)" "$(bytesToHuman $newTargetPartitionSize)"

						resizeRootFS
					fi

					logItem "--- partprobe ---"
					partprobe $RESTORE_DEVICE &>>$LOG_FILE
					logItem "--- udevadm ---"
					udevadm settle &>>$LOG_FILE
					rm $$.sfdisk &>/dev/null
				fi

			fi

			writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORING_FIRST_PARTITION "$BOOT_PARTITION"
			if (( $PROGRESS )); then
				dd if="$DD_FILE" 2>> $LOG_FILE | pv -fs $(stat -c %s "$DD_FILE") | dd of=$BOOT_PARTITION bs=1M &>>"$LOG_FILE"
			else
				dd if="$DD_FILE" of=$BOOT_PARTITION bs=1M &>>"$LOG_FILE"
			fi
			rc=$?
			if [ $rc != 0 ]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_IMG_DD_FAILED ".img" "$rc"
				exitError $RC_NATIVE_RESTORE_FAILED
			fi

			writeToConsole $MSG_LEVEL_DETAILED $MSG_FORMATTING_SECOND_PARTITION "$ROOT_PARTITION"
			mkfs.ext4 $ROOT_PARTITION &>>"$LOG_FILE"

			writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORING_SECOND_PARTITION "$ROOT_PARTITION"
			mount $ROOT_PARTITION "$MNT_POINT"

			case $BACKUPTYPE in

				$BACKUPTYPE_TAR|$BACKUPTYPE_TGZ)
					pushd "$MNT_POINT" &>>"$LOG_FILE"
					[[ $BACKUPTYPE == $BACKUPTYPE_TGZ ]] && zip="z" || zip=""
					if (( $PROGRESS )); then
						cmd="pv -f $ROOT_RESTOREFILE | tar -x${verbose}${zip}f -"
					else
						cmd="tar -x${verbose}${zip}f \"$ROOT_RESTOREFILE\""
					fi
					executeCommand "$cmd"
					rc=$?
					popd &>>"$LOG_FILE"
					;;

				$BACKUPTYPE_RSYNC)
					local excludePattern="--exclude=/$HOSTNAME-backup.*"
					logItem "Excluding excludePattern"
					if (( $PROGRESS )); then
						cmd="rsync --info=progress2 --numeric-ids -aHX$verbose $excludePattern \"$ROOT_RESTOREFILE/\" $MNT_POINT"
					else 
						cmd="rsync --numeric-ids -aHX$verbose $excludePattern \"$ROOT_RESTOREFILE/\" $MNT_POINT"
					fi
					executeCommand "$cmd"
					rc=$?
					;;

				*) assertionFailed $LINENO "Invalid backuptype $BACKUPTYPE"
					;;
			esac

			if [[ $rc != 0 ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_PROGRAM_ERROR $BACKUPTYPE $rc
				exitError $RC_NATIVE_RESTORE_FAILED
			fi

			logItem "Updating hw clock"
			echo $(date -u +"%Y-%m-%d %T") > $MNT_POINT/etc/fake-hwclock.data

			logItem "parted $RESTORE_DEVICE print"
			logItem "$(parted -s $RESTORE_DEVICE print 2>>$LOG_FILE)"

			if [[ $RESTORE_DEVICE =~ "/dev/mmcblk0" || $RESTORE_DEVICE =~ "/dev/loop" ]]; then
				ROOT_DEVICE=$(sed -E 's/p[0-9]+$//' <<< $ROOT_PARTITION)
			else
				ROOT_DEVICE=$(sed -E 's/[0-9]+$//' <<< $ROOT_PARTITION)
			fi

			if [[ $ROOT_DEVICE != $RESTORE_DEVICE ]]; then
				logItem "parted $ROOT_DEVICE print"
				logItem "$(parted -s $ROOT_DEVICE print 2>/dev/null)"
			fi

	esac

	logItem "Syncing filesystems"
	sync

	if isMounted $MNT_POINT; then
		logItem "Umount $MNT_POINT"
		umount $MNT_POINT >> "$LOG_FILE"
	fi

	logExit "restore rc: $rc"

}

function backup() {

	logEntry "backup"

	logger -t $MYSELF "Starting backup..."

	stopServices
	callExtensions $PRE_BACKUP_EXTENSION "0"

	BACKUPPATH_PARAMETER="$BACKUPPATH"
	BACKUPPATH="$BACKUPPATH/$HOSTNAME"
	if [[ ! -d "$BACKUPPATH" ]]; then
		 if ! mkdir -p "${BACKUPPATH}"; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNABLE_TO_CREATE_DIRECTORY "$BACKUPPATH"
			exitError $RC_CREATE_ERROR
		 fi
	fi

	if [[ $BACKUPTYPE == $BACKUPTYPE_RSYNC || (( $PARTITIONBASED_BACKUP )) ]]; then
		writeToConsole $MSG_LEVEL_DETAILED $MSG_BACKUP_TARGET "$BACKUPTYPE" "$BACKUPTARGET_DIR"
	else
		writeToConsole $MSG_LEVEL_DETAILED $MSG_BACKUP_TARGET "$BACKUPTYPE" "$BACKUPTARGET_FILE"
	fi

	logItem "Storing backup in backuppath $BACKUPPATH"

	logItem "mount:$NL$(mount)"
	logItem "df -h:$NL$(df -h)"
	logItem "blkid:$NL$(blkid)"

	logItem "fdisk -l $BOOT_DEVICENAME"
	logItem "$(fdisk -l $BOOT_DEVICENAME)"

	logItem "/boot/cmdline.txt"
	logItem "$(cat /boot/cmdline.txt)"

	logItem "/etc/fstab"
	logItem "$(cat /etc/fstab)"

	logItem "Starting $BACKUPTYPE backup..."

	rc=0

	BACKUP_STARTED=1

	if (( ! $PARTITIONBASED_BACKUP )); then

		case "$BACKUPTYPE" in

			$BACKUPTYPE_DD|$BACKUPTYPE_DDZ) ddBackup
				;;

			$BACKUPTYPE_TAR|$BACKUPTYPE_TGZ) tarBackup
				;;

			$BACKUPTYPE_RSYNC) rsyncBackup
				;;

			*) assertionFailed $LINENO "Invalid backuptype $BACKUPTYPE"
				;;
		esac

		if [[ $rc != 0 ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_PROGRAM_ERROR $BACKUPTYPE $rc
			exitError $RC_NATIVE_BACKUP_FAILED
		fi
	else
		backupPartitions
	fi

	logItem "Syncing"
	sync
	logItem "Finished $BACKUPTYPE backup"

	logItem "Backup created with return code: $rc"

	if [[ $rc -eq 0 ]]; then
		logItem "Deleting oldest directory in $BACKUPPATH"
		logItem "Current directory: $(pwd)"
		if [[ -z $BACKUPPATH || "$BACKUPPATH" == *"*"* ]]; then
			assertionFailed $LINENO "Unexpected backup path $BACKUPPATH"
		fi

		if (( ! $FAKE )); then

			logItem "pre - ls$NL$(ls -d $BACKUPPATH/* 2>/dev/null)"
			pushd "$BACKUPPATH" 1>/dev/null; ls -d *-$BACKUPTYPE-* 2>/dev/null| grep -v ".log$" | head -n -$KEEPBACKUPS | xargs -I {} rm -rf "{}" 2>>"$LOG_FILE"; popd > /dev/null

			local regex="\-([0-9]{8}\-[0-9]{6})\.(img|mbr|sfdisk|log)$"
			local regexDD="\-dd\-backup\-([0-9]{8}\-[0-9]{6})\.img$"

			pushd "$BACKUPPATH" 1>/dev/null
			for imgFile in $(ls -d *.img *.mbr *.sfdisk *.log 2>/dev/null); do

				if [[ $imgFile =~ $regexDD ]]; then
					logItem "Skipping DD file $imgFile"
					continue
				fi

				if [[ ! $imgFile =~ $regex ]]; then
					logItem "Skipping $imgFile"
					continue
				else
					logItem "Processing $imgFile"
				fi

				local date=${BASH_REMATCH[1]}
				logItem "Extracted date: $date"

				if [[ -z $date ]]; then
					assert $LINENO "Unable to extract date from backup files"
				fi
				local file=$(ls -d *-*-backup-$date* 2>/dev/null| egrep -v ".(log|img|mbr|sfdisk)$");

				if [[ -n $file ]];  then
					logItem "Found backup for $imgFile"
				else
					logItem "Found NO backup for $imgFile - removing"
					rm -f $imgFile &>>"$LOG_FILE"
				fi
			done
			popd > /dev/null

			logItem "post - ls$NL$(ls -d $BACKUPPATH/* 2>/dev/null)"

		fi

	fi

	callExtensions $POST_BACKUP_EXTENSION $rc
	startServices

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_STOPPED "$HOSTNAME" "$MYSELF" "$VERSION" "$(date)" "$GIT_COMMIT_ONLY"

	logger -t $MYSELF "Backup finished"
	logExit "backup"

}

function mountSDPartitions() { # sourcePath
	local partitition partitionName
	logEntry "mountSDPartitions: $1"

	if (( ! $FAKE )); then
		logItem "BEFORE: mount $(mount)"
		for partition in "${PARTITIONS_TO_BACKUP[@]}"; do
			partitionName="$BOOT_PARTITION_PREFIX$partition"
			logItem "mkdir $1/$partitionName"
			mkdir "$1/$partitionName" &>>"$LOG_FILE"
			logItem "mount /dev/$partitionName to $1/$partitionName"
			mount "/dev/$partitionName" "$1/$partitionName" &>>"$LOG_FILE"
		done
		logItem "AFTER: mount $(mount)"
	fi
	logExit "mountSDPartitions"
}

function umountSDPartitions() { # sourcePath
	local partitition partitionName
	logEntry "umountSDPartitions"
	if (( ! $FAKE )); then
		logItem "BEFORE: mount $(mount)"
		for partition in "${PARTITIONS_TO_BACKUP[@]}"; do
			partitionName="$BOOT_PARTITION_PREFIX$partition"
			if isMounted "$1/$partitionName"; then
				logItem "umount $1/$partitionName"
				umount "$1/$partitionName" &>>"$LOG_FILE"
			fi
			if [[ -d "$1/$partitionName" ]]; then
				logItem "rmdir $1/$partitionName"
				rmdir "$1/$partitionName" &>>"$LOG_FILE"
			fi
		done
		logItem "AFTER: mount $(mount)"
	fi
	logExit "umountSDPartitions"
}

function backupPartitions() {

	logEntry "backupPartitions"

	local partition

	logItem "PARTITIONS_TO_BACKUP: $(echo "${PARTITIONS_TO_BACKUP[@]}")"

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_STARTED "$BACKUPTYPE"

	partitionLayoutBackup

	if [[ $BACKUPTYPE == $BACKUPTYPE_RSYNC || $BACKUPTYPE == $BACKUPTYPE_TAR || $BACKUPTYPE == $BACKUPTYPE_TGZ ]]; then
		mountSDPartitions "$TEMPORARY_MOUNTPOINT_ROOT"
	fi

	for partition in "${PARTITIONS_TO_BACKUP[@]}"; do

		logItem "Processing partition $partition"

		local fileSystem=$(getBackupPartitionFilesystem $partition)
		local fileSystemSize=$(getBackupPartitionFilesystemSize $partition)

		logItem "fileSystem: $fileSystem - fileSystemSize: $fileSystemSize"

		if [[ -z $fileSystem ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_SKIPPING_UNFORMATTED_PARTITION "${BOOT_PARTITION_PREFIX}$partition" $fileSystemSize
		else
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_PROCESSING_PARTITION "${BOOT_PARTITION_PREFIX}$partition" $fileSystemSize

			case "$BACKUPTYPE" in

				$BACKUPTYPE_DD|$BACKUPTYPE_DDZ) ddBackup "$partition"
					;;

				$BACKUPTYPE_TAR|$BACKUPTYPE_TGZ) tarBackup "$partition"
					;;

				$BACKUPTYPE_RSYNC) rsyncBackup "$partition"
					;;

				*) assertionFailed $LINENO "Invalid backuptype $BACKUPTYPE"
					;;
			esac

			if [[ $rc != 0 ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_PARTITION_FAILED "${BOOT_PARTITION_PREFIX}$partition" $rc
				exitError $RC_NATIVE_RESTORE_FAILED
			else
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_PROCESSED_PARTITION "${BOOT_PARTITION_PREFIX}$partition"
			fi
		fi

	done

	if [[ $BACKUPTYPE == $BACKUPTYPE_RSYNC || $BACKUPTYPE == $BACKUPTYPE_TAR || $BACKUPTYPE == $BACKUPTYPE_TGZ ]]; then
		umountSDPartitions "$TEMPORARY_MOUNTPOINT_ROOT"
	fi

	logExit "backupPartitions $rc"

}

function doit() {

	logEntry "doit"

	local msg
	logItem "Startingdirectory: $(pwd)"
	logItem "fdisk -l$NL$(fdisk -l 2>/dev/null)"
	logItem "mount$NL$(mount 2>/dev/null)"

	if (( $RESTORE )); then
		doitRestore
	else
		if (( $FAKE )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FAKE_MODE_ON
		fi

		doitBackup
	fi

	logItem "Enddirectory: $(pwd)"

	logExit "doit"

}

function collectPartitions() {

	logEntry "collectPartitions"

# raspbian:
# /dev/mmcblk0p1 : start=     8192, size=   114688, Id= c
# /dev/mmcblk0p2 : start=   122880, size=  1069056, Id=83

# ubuntu:
#/dev/mmcblk0p1 : start=        2048, size=      131072, type=c, bootable
#/dev/mmcblk0p2 : start=      133120, size=    20971520, type=83
#/dev/mmcblk0p3 : start=    21104640, size=    10485760, type=83
#/dev/mmcblk0p4 : start=    31590400, size=    29161472, type=83

    local regexPartitionLine="($BOOT_DEVICENAME[a-z0-9]+).*start[^0-9]+([0-9]+).*size[^0-9]+([0-9]+).*(Id|type)=[ ]?([^,]+)"

# /dev/mmvblk0p1 on /media/Log1 type ext2 (rw,nosuid,nodev,uhelper=udisks)
	local regexMountLine="($BOOT_DEVICENAME[a-z0-9]+).*on ([^ ]+)"

	logItem "PARTITIONS_TO_BACKUP - 1: $(echo "${PARTITIONS_TO_BACKUP[@]}")"

	local backupAllPartitions
	if [[ "$PARTITIONS_TO_BACKUP" == "$PARTITIONS_TO_BACKUP_ALL" ]]; then
		backupAllPartitions=1
		PARTITIONS_TO_BACKUP=()
	else
		backupAllPartitions=0
	fi

	logItem "backupAllPartitions: $backupAllPartitions"

	local mountline partition size type
	while read line; do
		if [[ $line =~ $regexPartitionLine ]]; then
			partition=${BASH_REMATCH[1]}
			size=${BASH_REMATCH[3]}
			type=${BASH_REMATCH[5]}
			logItem "partition: $partition - size: $size - type: $type"
			if [[ $type != 85 && $size > 0 ]]; then # skip empty and extended partitions
				logItem "mount: $(mount)"
				logItem "Partition: $partition"
				mountLine=$(mount | grep $partition )
				if ! (( $? )); then
					logItem "mountline: $mountLine"
					logItem "regexMountLIne: $regexMountLine"
					if [[ $mountLine =~ $regexMountLine ]]; then
						local mountPoint=${BASH_REMATCH[2]}
						logItem "partition $partition mounted on $mountPoint"
						mountPoints[$partition]=$mountPoint
					else
						assertionFailed $LINENO "Unable to find mountpoint for $partition"
					fi
				else
					if [[ $partition == $ROOT_PARTITION ]]; then
						mountPoints[$partition]="/"
						logItem "partition $partition mounted on /"
					else
						logItem "partition $partition not mounted"
						mountPoints[$partition]=""
					fi
				fi

				if (( $backupAllPartitions )); then
					id=$(getPartitionNumber $partition)
					logItem "Adding partition $id to list of partitions to backup"
					PARTITIONS_TO_BACKUP["$id"]="$id"
				fi
			fi
		fi

	done < <(sfdisk -d $BOOT_DEVICENAME 2>>$LOG_FILE)

	logItem "PARTITIONS_TO_BACKUP - 2: $(echo "${PARTITIONS_TO_BACKUP[@]}")"
	logItem "mountPoints: $(echo "${mountPoints[@]}")"

	if [[ ${#PARTITIONS_TO_BACKUP[@]} == 0 ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_NOPARTITIONS_TOBACKUP_FOUND
		exitError $RC_
	fi

	logExit "collectPartitions"

}

function checksForPartitionBasedBackup() {

	local partition

	logEntry "checksForPartitionBasedBackup"

	collectPartitions

	logItem "PARTITIONS_TO_BACKUP: ${PARTITIONS_TO_BACKUP[@]}"

	SUPPORTED_PARTITIONBACKUP_PARTITIONTYPE_REGEX='^(ext[234]|fat(16|32)|btrfs|.*swap.*)$'

	local error=0
	for partition in "${PARTITIONS_TO_BACKUP[@]}"; do
		local fileSystem=$(getPartitionBootFilesystem $partition)
		if [[ -n $fileSystem && ! $fileSystem =~ $SUPPORTED_PARTITIONBACKUP_PARTITIONTYPE_REGEX ]]; then
			error=1
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNSUPPORTED_FILESYSTEM_FORMAT "$fileSystem" "${BOOT_PARTITION_PREFIX}$partition"
		fi
	done

	if (( error )) ; then
		exitError $RC_PARAMETER_ERROR
	fi

	error=0


	logItem "mountPoints: $(echo "${mountPoints[@]}")"
	logItem "mountPoints - keys: $(echo "${!mountPoints[@]}")"
	for partition in "${PARTITIONS_TO_BACKUP[@]}"; do
		logItem "Checking partition $partition"
		if ! [[ $partition =~ ^[0-9]+ ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_PARTITION_NUMBER_INVALID "$partition"
			error=1
		else
			local key="/dev/${BOOT_PARTITION_PREFIX}${partition}"
			logItem "Checking partition $partition against $key: ${mountPoints[$key]+isset}"
			if [[ ! ${mountPoints[$key]+isset} ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_PARTITION_NOT_FOUND "$partition"
				error=1
			fi
		fi
	done

	if (( $error )); then
		exitError $RC_PARAMETER_ERROR
	fi

	logExit "checksForPartitionBasedBackup"

}

function commonChecks() {

	logEntry "commonChecks"

	if [[ -n "$EMAIL" ]]; then
		if [[ ! $EMAIL_PROGRAM =~ $SUPPORTED_EMAIL_PROGRAM_REGEX ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_EMAIL_PROG_NOT_SUPPORTED "$EMAIL_PROGRAM" "$SUPPORTED_MAIL_PROGRAMS"
			exitError $RC_PARAMETER_ERROR
		fi
		if [[ ! $(which $EMAIL_PROGRAM) && ( $EMAIL_PROGRAM != $EMAIL_EXTENSION_PROGRAM ) ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_MAILPROGRAM_NOT_INSTALLED $EMAIL_PROGRAM
			exitError $RC_MISSING_FILES
		fi
		if [[ "$MAIL_PROGRAM" == $EMAIL_SSMTP_PROGRAM && (( $APPEND_LOG )) ]]; then
			if [[ ! $(which mpack) ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_MPACK_NOT_INSTALLED
				APPEND_LOG=0
			fi
		fi
	fi

	logExit "commonChecks"

}

function getRootPartition() {

	logEntry "getRootPartition"
#	cat /proc/cmdline
#	dma.dmachans=0x7f35 bcm2708_fb.fbwidth=656 bcm2708_fb.fbheight=416 bcm2708.boardrev=0xf bcm2708.serial=0x3f3c9490 smsc95xx.macaddr=B8:27:EB:3C:94:90 bcm2708_fb.fbswap=1 sdhci-bcm2708.emmc_clock_freq=250000000 vc_mem.mem_base=0x1fa00000 vc_mem.mem_size=0x20000000  dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline rootwait

	local cmdline=$(cat /proc/cmdline)
	logItem "cat /proc/cmdline$NL$(cat /proc/cmdline)"
	if [[ $cmdline =~ .*root=([^ ]+) ]]; then
		ROOT_PARTITION=${BASH_REMATCH[1]}
		logItem "RootPartition: $ROOT_PARTITION"
	else
		assertionFailed $LINENO "Unable to find root mountpoint in /proc/cmdline"
	fi
	logExit "getRootPartition: $ROOT_PARTITION"

}

function inspect4Backup() {

	logEntry "inspect4Backup"

	logItem "ls /dev/mmcblk*:${NL}$(ls -1 /dev/mmcblk* 2>/dev/null)"
	logItem "ls /dev/sd*:${NL}$(ls -1 /dev/sd* 2>/dev/null)"
	logItem "mountpoint /boot: $(mountpoint -d /boot) mountpoint /: $(mountpoint -d /)"

	if (( $REGRESSION_TEST || $RESTORE )); then
		BOOT_DEVICE="mmcblk0"
	else
		part=$(for d in $(find /dev -type b); do [ "$(mountpoint -d /boot)" = "$(mountpoint -x $d)" ] && echo $d && break; done)
		logItem "part: $part"
		if [ "$(mountpoint -d /boot)" == "$(mountpoint -d /)" ]; then	# /boot on same partition with root partition /
			if [[ -b /dev/mmcblk0p1 ]]; then
				BOOT_DEVICE="mmcblk0"
			else
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_BOOTDEVICE_FOUND
				exitError $RC_MISC_ERROR
			fi					
		elif [[ "$part" =~ /dev/(sd[a-z]) || "$part" =~ /dev/(mmcblk[0-9])p ]]; then
			BOOT_DEVICE=${BASH_REMATCH[1]}
		else
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_BOOTDEVICE_FOUND
			exitError $RC_MISC_ERROR
		fi
	fi

	logItem "BOOT_DEVICE: $BOOT_DEVICE"
	BACKUP_BOOT_DEVICE="$BOOT_DEVICE"

	BOOT_DEVICENAME="/dev/$BOOT_DEVICE"
	logItem "BOOT_DEVICENAME: $BOOT_DEVICENAME"
	BACKUP_BOOT_DEVICENAME="$BOOT_DEVICENAME"

	BOOT_PARTITION_PREFIX="$(getPartitionPrefix $BOOT_DEVICE)" # mmcblk0p - sda
	logItem "BOOT_PARTITION_PREFIX: $BOOT_PARTITION_PREFIX"
	BACKUP_BOOT_PARTITION_PREFIX="$BOOT_PARTITION_PREFIX"

	logExit "inspect4Backup"
}

function inspect4Restore() {

	logEntry "inspect4Restore"

	if [[ $BACKUPTYPE != $BACKUPTYPE_DD && $BACKUPTYPE != $BACKUPTYPE_DDZ ]]; then
		SF_FILE=$(ls -1 $RESTOREFILE/*.sfdisk)
		if [[ -z $SF_FILE ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_NOT_FOUND "$RESTOREFILE/*.sfdisk"
			exitError $RC_MISSING_FILES
		fi

		MBR_FILE=$(ls -1 $RESTOREFILE/*.mbr)
		if [[ -z $SF_FILE ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_NOT_FOUND "$RESTOREFILE/*.mbr"
			exitError $RC_MISSING_FILES
		fi
	fi

	if (( PARTITIONBASED_BACKUP )); then
		BLKID_FILE=$(ls -1 $RESTOREFILE/*.blkid)
		if [[ -z $SF_FILE ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_NOT_FOUND "$RESTOREFILE/*.blkid"
			exitError $RC_MISSING_FILES
		fi

		PARTED_FILE=$(ls -1 $RESTOREFILE/*.parted)
		if [[ -z $SF_FILE ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_NOT_FOUND "$RESTOREFILE/*.parted"
			exitError $RC_MISSING_FILES
		fi

		FDISK_FILE=$(ls -1 $RESTOREFILE/*.fdisk)
		if [[ -z $SF_FILE ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_NOT_FOUND "$RESTOREFILE/*.fdisk"
			exitError $RC_MISSING_FILES
		fi
	fi

#sfdisk from util-linux 2.25.2
## partition table of /dev/mmcblk0
#unit: sectors
#
#/dev/mmcblk0p1 : start=     8192, size=    83968, Id= c
#/dev/mmcblk0p2 : start=    92160, size= 31330304, Id=83
#/dev/mmcblk0p3 : start=        0, size=        0, Id= 0
#/dev/mmcblk0p4 : start=        0, size=        0, Id= 0

#sfdisk from util-linux 2.27.1
#label: dos
#label-id: 0x6c96114a
#device: /dev/sdb
#unit: sectors
#
#/dev/sdb1 : start=          63, size=  1953520002, type=83

	if [[ $BACKUPTYPE != $BACKUPTYPE_DD && $BACKUPTYPE != $BACKUPTYPE_DDZ ]]; then
	
		BACKUP_BOOT_DEVICE=$(grep "partition table" -m 1 "$SF_FILE" | cut -f 5 -d ' ' | sed 's#/dev/##')
		if [[ -z $BACKUP_BOOT_DEVICE ]]; then
			BACKUP_BOOT_DEVICE=$(grep "^device" -m 1 "$SF_FILE" | cut -f 2 -d ':' | sed 's#[[:space:]]*/dev/##')
		fi

		if [[ -z $BACKUP_BOOT_DEVICE ]]; then
			logItem "$(cat $SF_FILE)"
			assertionFailed $LINENO "Unable to discover boot device from $SF_FILE"
		fi
	
		logItem "BACKUP_BOOT_DEVICE: $BACKUP_BOOT_DEVICE"

		BACKUP_BOOT_DEVICENAME="/dev/$BACKUP_BOOT_DEVICE"
		logItem "BACKUP_BOOT_DEVICENAME: $BACKUP_BOOT_DEVICENAME"

		BACKUP_BOOT_PARTITION_PREFIX="$(getPartitionPrefix $BACKUP_BOOT_DEVICE)"
		logItem "BACKUP_BOOT_PARTITION_PREFIX: $BACKUP_BOOT_PARTITION_PREFIX"
	fi

	logExit "inspect4Restore"

}

function reportNews() {

	logEntry "reportNews"

	if (( $NOTIFY_UPDATE )); then

		isUpdatePossible

		if (( ! $IS_BETA )); then
			local betaVersion=$(isBetaAvailable)
			if [[ -n $betaVersion && $VERSION != $betaVersion ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_BETAVERSION_AVAILABLE "$betaVersion" "oldVersion"
				NEWS_AVAILABLE=1
			fi
		fi
	fi

	logExit "reportNews"

}

function doitBackup() {

	logEntry "doitBackup $PARTITIONBASED_BACKUP"

	reportNews

	getRootPartition
	inspect4Backup

	commonChecks

	trapWithArg cleanup SIGINT SIGTERM EXIT

	if [[ ! -d "$BACKUPPATH" ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_DIR_TO_BACKUP_DOESNOTEXIST "$BACKUPPATH"
		exitError $RC_MISSING_FILES
	fi

	if [[ $(getFsType "$BACKUPPATH") == "vfat" ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_MAX_4GB_LIMIT "$BACKUPPATH"
	fi


	if (( ! $EXCLUDE_DD )); then

		if [[ ! -b $BOOT_DEVICENAME ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_SDCARD_FOUND $BOOT_DEVICENAME
			exitError $RC_PARAMETER_ERROR
		fi

		if ! fdisk -l $BOOT_DEVICENAME | grep "${BOOT_PARTITION_PREFIX}1" > /dev/null; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_BOOT_PARTITION
			exitError $RC_SDCARD_ERROR
		fi

		local partitionsFound=$(fdisk -l $BOOT_DEVICENAME | grep "^/dev/$BOOT_PARTITION_PREFIX" | wc -l)
		logItem "Found partitions on $BOOT_DEVICENAME: $partitionsFound"
		if [[ (( $partitionsFound > 2 )) && ( "$BACKUPTYPE" != "$BACKUPTYPE_DD" && "$BACKUPTYPE" != "$BACKUPTYPE_DDZ" ) ]]; then
			if ! (( $PARTITIONBASED_BACKUP )); then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_MULTIPLE_PARTITIONS_FOUND
				exitError $RC_SDCARD_ERROR
			fi
		fi
	fi

	if (( ! $SKIPLOCALCHECK )) && ! isPathMounted "$BACKUPPATH"; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_DEVICEMOUNTED "$BACKUPPATH"
		exitError $RC_MISC_ERROR
	fi

	if [[ ! $KEEPBACKUPS =~ ^[0-9]+$ || $KEEPBACKUPS -lt 1 || $KEEPBACKUPS -gt 365 ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_KEEPBACKUP_INVALID $KEEPBACKUPS
		mentionHelp
		exitError $RC_PARAMETER_ERROR
	fi

	if (( $ZIP_BACKUP_TYPE_INVALID )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNKNOWN_BACKUPTYPE_FOR_ZIP $BACKUPTYPE
		mentionHelp
		exitError $RC_PARAMETER_ERROR
	fi

	if [[ ! $BACKUPTYPE =~ ^(${POSSIBLE_TYPES})$ ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNKNOWN_BACKUPTYPE $BACKUPTYPE
		mentionHelp
		exitError $RC_PARAMETER_ERROR
	fi

	if [[ "$BACKUPTYPE" == "$BACKUPTYPE_RSYNC" ]]; then
		if [[ ! $(which rsync) ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "rsync" "rsync"
			exitError $RC_PARAMETER_ERROR
		fi
		if (( ! $SKIP_RSYNC_CHECK )) && ! supportsHardlinks "$BACKUPPATH"; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILESYSTEM_INCORRECT "$BACKUPPATH"
			exitError $RC_PARAMETER_ERROR
		fi
		local rsyncVersion=$(rsync --version | head -n 1 | awk '{ print $3 }')
		logItem "rsync version: $rsyncVersion"
		if (( $PROGRESS )) && [[ "$rsyncVersion" < "3.1" ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_RSYNC_DOES_NOT_SUPPORT_PROGRESS "$rsyncVersion"
			exitError $RC_PARAMETER_ERROR
		fi
	fi

	if [[ -z "$STARTSERVICES" && -z "$STOPSERVICES" ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_START_STOP
		exitError $RC_PARAMETER_ERROR
	fi
	if [[ -z "$STARTSERVICES" ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_START_OR_STOP "-a"
		exitError $RC_PARAMETER_ERROR
	fi
	if [[ -z "$STOPSERVICES" ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_START_OR_STOP "-o"
		exitError $RC_PARAMETER_ERROR
	fi

	if [[ ( -n "$STARTSERVICES" || -n "$STOPSERVICES" ) && ! ( -n "$STARTSERVICES" && -n "$STOPSERVICES" ) ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_START_OR_STOP
		exitError $RC_PARAMETER_ERROR
	fi

	if (( $PROGRESS )) && [[ "$BACKUPTYPE" == "$BACKUPTYPE_DD" || "$BACKUPTYPE" == "$BACKUPTYPE_DDZ" ]] && [[ ! $(which pv) ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "pv" "pv"
		exitError $RC_PARAMETER_ERROR
	fi

	if (( $PARTITIONBASED_BACKUP )); then
		if [[ $BACKUPTYPE == $BACKUPTYPE_DD || $BACKUPTYPE == $BACKUPTYPE_DDZ ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_DD_BACKUP_NOT_POSSIBLE_FOR_PARTITIONBASED_BACKUP
			exitError $RC_PARAMETER_ERROR
		fi
		if (( ! $FAKE )); then
			checksForPartitionBasedBackup
		fi
	fi

	if (( $LINK_BOOTPARTITIONFILES )) &&  [[ "$BACKUPTYPE" != "$BACKUPTYPE_DD" ]] && [[ "$BACKUPTYPE" != "$BACKUPTYPE_DDZ" ]]; then
		touch $BACKUPPATH/47.$$
		cp -l $BACKUPPATH/47.$$ $BACKUPPATH/11.$$ &>/dev/null
		rc=$?
		rm $BACKUPPATH/47.$$ &>/dev/null
		rm $BACKUPPATH/11.$$ &>/dev/null
		if [[ $rc != 0 ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNABLE_TO_USE_HARDLINKS "$BACKUPPATH" "$rc"
			exitError $RC_LINK_FILE_FAILED
		fi
	fi

	# just inform about enabled config options

	if  [[ $BACKUPTYPE != $BACKUPTYPE_DD && $BACKUPTYPE != $BACKUPTYPE_DDZ ]]; then
		if (( $LINK_BOOTPARTITIONFILES )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_LINK_BOOTPARTITIONFILES
		fi
	fi

	if  [[ $BACKUPTYPE == $BACKUPTYPE_DD || $BACKUPTYPE == $BACKUPTYPE_DDZ ]]; then
		if (( $DD_BACKUP_SAVE_USED_PARTITIONS_ONLY )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_SAVING_USED_PARTITIONS_ONLY
		fi
	fi

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_USING_BACKUPPATH "$BACKUPPATH"

	backup

	logExit "doitBackup"

}

function getPartitionTable() { # device

	logEntry "getPartitionTable $1"
	logItem "$(IFS='' parted $1 unit MB p 2>>$LOG_FILE)"
	local table="$(IFS='' parted $1 unit MB p 2>>$LOG_FILE | sed -r '/^($|[MSDP])/d')"

	if [[ $(wc -l <<< "$table") < 2 ]]; then
	    table=""
	fi
	echo "$table"

	logExit "getPartitionTable"
}

function checkAndSetBootPartitionFiles() { # directory extension

	logEntry "checkAndSetBootPartitionFiles"

	local prefix="$1/$2"

	DD_FILE="$prefix.img"
	logItem "DD_FILE: $DD_FILE"
	SF_FILE="$prefix.sfdisk"
	logItem "SF_FILE: $SF_FILE"
	MBR_FILE="$prefix.mbr"
	logItem "MBR_FILE: $MBR_FILE"

	local errorCnt=0
	if [[ "$BACKUPTYPE" != $BACKUPTYPE_DD && "$BACKUPTYPE" != $BACKUPTYPE_DDZ ]]; then
		if [[ ! -e "$SF_FILE" ]]; then
			logItem "$SF_FILE not found"
			(( errorCnt++ ))
		else
			logItem "$(<"$SF_FILE")"
		fi
		if [[ ! -e "$DD_FILE" ]]; then
			logItem "$DD_FILE not found"
			(( errorCnt++ ))
		fi
		if [[ ! -e "$MBR_FILE" ]]; then
			logItem "$MBR_FILE not found"
			(( errorCnt++ ))
		fi
	fi

	logExit "checkAndSetBootPartitionFiles $errorCnt"

	return $errorCnt

}

function findNonpartitionBackupBootAndRootpartitionFiles() {

	logEntry "findNonpartitionBackupBootAndRootpartitionFiles"

#	search precedence for root files
#	1) if directory search corresponding file in directory
#	2) if file passed just use this file

	if [[ -f "$RESTOREFILE" || $BACKUPTYPE == $BACKUPTYPE_RSYNC ]]; then
		ROOT_RESTOREFILE="$RESTOREFILE"
	else
		logItem "${RESTOREFILE}/${HOSTNAME}-*-backup*"
		ROOT_RESTOREFILE="$(ls ${RESTOREFILE}/${HOSTNAME}-*-backup*)"
		logItem "ROOT_RESTOREFILE: $ROOT_RESTOREFILE"
		if [[ -z "$ROOT_RESTOREFILE" ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_ROOTBACKUPFILE_FOUND $BACKUPTYPE
			exitError $RC_MISC_ERROR
		fi
	fi

	writeToConsole $MSG_LEVEL_DETAILED $MSG_USING_ROOTBACKUPFILE "$ROOT_RESTOREFILE"

#	search precedence for boot files
#	1) individual backup dir and no date (added in this version)
#	2) backup dir and date (added when boot backup all the time was added in 0.6.1.1)
#	3) backup dir and no date (initial location when ony one single backup was created, pre 0.6.1.1)

	local bootpartitionDirectory=( "$RESTOREFILE" "$BASE_DIR"  "$BASE_DIR" )
	local bootpartitionExtension=( "$HOSTNAME-backup" "$HOSTNAME-backup-$DATE" "$HOSTNAME-backup" )

	local i=0

	for (( i=0; i<${#bootpartitionDirectory[@]}; i++ )); do

		checkAndSetBootPartitionFiles "${bootpartitionDirectory[$i]}" "${bootpartitionExtension[$i]}"
		local errorCnt=$?

		if [[ $errorCnt == 0 ]]; then
			writeToConsole $MSG_LEVEL_DETAILED $MSG_BOOTPATITIONFILES_FOUND "${bootpartitionDirectory[$i]}" "${bootpartitionExtension[$i]}"
			logExit "findNonpartitionBackupBootpartitionFiles"
			return
		fi
	done

	for (( i=0; i<${#bootpartitionDirectory[@]}; i++ )); do
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_BOOTPATITIONFILES_NOT_FOUND "${bootpartitionDirectory[$i]}" "${bootpartitionExtension[$i]}"
	done
	logExit "findNonpartitionBackupBootAndRootpartitionFiles"
	exitError $RC_MISC_ERROR

}

function restoreNonPartitionBasedBackup() {

	logEntry "restoreNonPartitionBasedBackup"

	if [[ -z $(fdisk -l $RESTORE_DEVICE 2>/dev/null) ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_RESTOREDEVICE_FOUND $RESTORE_DEVICE
		exitError $RC_PARAMETER_ERROR
	fi

	if [[ $RESTORE_DEVICE =~ /dev/mmcblk0 || $RESTORE_DEVICE =~ "/dev/loop" ]]; then
		BOOT_PARTITION="${RESTORE_DEVICE}p1"
	else
		BOOT_PARTITION="${RESTORE_DEVICE}1"
	fi
	logItem "BOOT_PARTITION : $BOOT_PARTITION"

	ROOT_PARTITION_DEFINED=1
	if [[ -z $ROOT_PARTITION ]]; then
		if [[ $RESTORE_DEVICE =~ /dev/mmcblk0 || $RESTORE_DEVICE =~ "/dev/loop" ]]; then
			ROOT_PARTITION="${RESTORE_DEVICE}p2"
		else
			ROOT_PARTITION="${RESTORE_DEVICE}2"
		fi
		ROOT_PARTITION_DEFINED=0
	else
		if [[ ! -e "$ROOT_PARTITION" ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_ROOT_PARTTITION_NOT_FOUND $ROOT_PARTITION
			exitError $RC_PARAMETER_ERROR
		fi
	fi

	logItem "ROOT_PARTITION : $ROOT_PARTITION"

	if (( ! $SKIP_SFDISK )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_REPARTITION_WARNING $RESTORE_DEVICE
	fi

	current_partition_table="$(getPartitionTable $RESTORE_DEVICE)"
	if [[ -n $current_partition_table ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_CURRENT_PARTITION_TABLE "$RESTORE_DEVICE" "$current_partition_table"
	else
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_PARTITION_TABLE_DEFINED "$RESTORE_DEVICE"
	fi

	if (( ! $ROOT_PARTITION_DEFINED )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_WARN_RESTORE_DEVICE_OVERWRITTEN $RESTORE_DEVICE
	else
		if [[ $ROOT_DEVICE =~ /dev/mmcblk0 || $ROOT_DEVICE =~ "/dev/loop" ]]; then
			ROOT_DEVICE=$(sed -E 's/p[0-9]+$//' <<< $ROOT_PARTITION)
		else
			ROOT_DEVICE=$(sed -E 's/[0-9]+$//' <<< $ROOT_PARTITION)
		fi

		current_partition_table="$(getPartitionTable $ROOT_DEVICE)"
		if [[ -N $current_partition_table ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_CURRENT_PARTITION_TABLE "$ROOT_DEVICE" "$current_partition_table"
		else
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_PARTITION_TABLE_DEFINED "$ROOT_DEVICE"
		fi
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_WARN_BOOT_PARTITION_OVERWRITTEN $BOOT_PARTITION
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_WARN_ROOT_PARTITION_OVERWRITTEN $ROOT_PARTITION
	fi

    yes_no=$(getLocalizedMessage $MSG_QUERY_CHARS_YES_NO)

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_ANSWER_YES_NO "$yes_no"

	if (( $NO_YES_QUESTION )); then
		answer=$(getLocalizedMessage $MSG_ANSWER_CHARS_YES)
	else
		read answer
	fi
	answer=${answer:0:1}	# first char only
	answer=${answer:-"n"}	# set default no
   	yes=$(getLocalizedMessage $MSG_ANSWER_CHARS_YES)
	if [[ ! $yes =~ $answer ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_ABORTED
		exitError $RC_RESTORE_FAILED
	fi

	restore

	logExit "restoreNonPartitionBasedBackup. rc: $rc"

}

function restorePartitionBasedBackup() {

	logEntry "restorePartitionBasedBackup"

	local partition
	local sourceSize
	local targetSize

	if [[ "$BACKUPTYPE" != $BACKUPTYPE_DD && "$BACKUPTYPE" != $BACKUPTYPE_DDZ ]]; then
		if [[ ! -e "$SF_FILE" ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_NOT_FOUND "$SF_FILE"
			exitError $RC_MISSING_FILES
		fi
		logItem "SF_FILE: $SF_FILE$NL$(<"$SF_FILE")"
		if [[ ! -e "$MBR_FILE" ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_NOT_FOUND "$MBR_FILE"
			exitError $RC_MISSING_FILES
		fi
		if [[ ! -e "$BLKID_FILE" ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_NOT_FOUND "$BLKID_FILE"
			exitError $RC_MISSING_FILES
		fi
		logItem "BLKID_FILE: $BLKID_FILE$NL$(<"$BLKID_FILE")"
		if [[ ! -e "$PARTED_FILE" ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_NOT_FOUND "$PARTED_FILE"
			exitError $RC_MISSING_FILES
		fi
		logItem "PARTED_FILE: $PARTED_FILE$NL$(<"$PARTED_FILE")"
		if [[ -n $ROOT_PARTITION ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_DEVICE_NOT_VALID
			exitError $RC_MISSING_FILES
		fi
	fi

	if mount | grep -q $RESTORE_DEVICE; then
		logItem "Umounting partitions on $RESTORE_DEVICE"
		logItem $(mount | grep $RESTORE_DEVICE)
		while read dev; do echo $dev | cut -d ' ' -f 1; done < <(mount | grep $RESTORE_DEVICE)  | xargs umount
		logItem $(mount | grep $RESTORE_DEVICE)
	fi

	local sourceSDSize=$(grep "^Disk" -m 1 "$FDISK_FILE" | cut -f 5 -d ' ')
	local targetSDSize=$(blockdev --getsize64 $RESTORE_DEVICE)

	logItem "SourceSDSize: $soureSDSize - targetSDSize: $targetSDSize"

	if (( targetSDSize < sourceSDSize )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_TARGETSD_SIZE_TOO_SMALL "$RESTORE_DEVICE" "$(bytesToHuman $targetSDSize)" "$(bytesToHuman $sourceSDSize)"
		exitError $RC_MISC_ERROR
	elif (( targetSDSize > sourceSDSize )); then
		local unusedSpace=$(( targetSDSize - sourceSDSize ))
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_TARGETSD_SIZE_BIGGER "$RESTORE_DEVICE" "$(bytesToHuman $targetSDSize)" "$(bytesToHuman $sourceSDSize)" "$(bytesToHuman $unusedSpace)"
	fi

	current_partition_table="$(getPartitionTable $RESTORE_DEVICE)"

	if (( $SKIP_SFDISK )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_SKIPPING_CREATING_PARTITIONS
	else
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_REPARTITION_WARNING $RESTORE_DEVICE
	fi

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_CURRENT_PARTITION_TABLE "$RESTORE_DEVICE" "$current_partition_table"
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_WARN_RESTORE_PARTITION_DEVICE_OVERWRITTEN "$RESTORE_DEVICE"

    yes_no=$(getLocalizedMessage $MSG_QUERY_CHARS_YES_NO)

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_ANSWER_YES_NO "$yes_no"

	if (( $NO_YES_QUESTION )); then
		answer=$(getLocalizedMessage $MSG_ANSWER_CHARS_YES)
	else
		read answer
	fi
	answer=${answer:0:1}	# first char only
	answer=${answer:-"n"}	# set default no
   	yes=$(getLocalizedMessage $MSG_ANSWER_CHARS_YES)
	if [[ ! $yes =~ $answer ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL$MSG_RESTORE_ABORTED
		exitError $RC_RESTORE_FAILED
	fi

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_STARTED "$HOSTNAME" "$MYSELF" "$VERSION" "$(date)" "$GIT_COMMIT_ONLY"

	if (( ! $SKIP_SFDISK )); then
		writeToConsole $MSG_LEVEL_DETAILED $MSG_PARTITIONING_SDCARD "$RESTORE_DEVICE"
		writeToConsole $MSG_LEVEL_DETAILED $MSG_CREATING_PARTITIONS "$RESTORE_DEVICE"
		logItem "mount: $(mount)"

		local force=""
		(( $FORCE_SFDISK )) && force="--force"

		local tmp=$(mktemp)
		logItem "sfdisk"
		sfdisk $force -uSL $RESTORE_DEVICE < "$SF_FILE" > "$tmp" 2>&1
		rc=$?
		local error=$(<$tmp)
		echo "$error" >> "$LOG_FILE"
		logItem "Error: $error"
		rm "$tmp" &>/dev/null
		if [ $rc != 0 ]; then
			writeToConsole $MSG_LEVEL_DETAILED $MSG_UNABLE_TO_CREATE_PARTITIONS $rc "$error"
			exitError $RC_CREATE_PARTITIONS_FAILED
		fi

		logItem "partprobe"
		partprobe $RESTORE_DEVICE
		udevadm settle
		logItem "Syncing filesystems"
		sync
	else
		writeToConsole $MSG_LEVEL_DETAILED $MSG_SKIPPING_CREATING_PARTITIONS
	fi

	if [[ "${RESTOREFILE: -1}" != "/" ]]; then
		RESTOREFILE="$RESTOREFILE/"
	fi

	MNT_POINT="$TEMPORARY_MOUNTPOINT_ROOT/${MYNAME}"

	if ( isMounted "$MNT_POINT" ); then
		logItem "$MNT_POINT mounted - unmouting"
		umount -f "$MNT_POINT" &>$LOG_FILE
		if [ $? -ne 0 ]; then
			assertionFailed $LINENO "Unable to unmount $MNT_POINT"
		fi
	fi

	logItem "Creating mountpoint $MNT_POINT"
	mkdir -p $MNT_POINT

	logItem "Mount:$NL$(mount)"

	for partitionBackupFile in "${RESTOREFILE}${BACKUP_BOOT_PARTITION_PREFIX}"*; do
		restorePartitionBasedPartition "$partitionBackupFile"
	done

	sync

	logItem "fdisk of $RESTORE_DEVICE"
	logItem $(fdisk -l $RESTORE_DEVICE)

	logExit "restorePartitionBasedBackup"

}

# /dev/mmcblk0p1: LABEL="RECOVERY" UUID="B383-E246" TYPE="vfat"
# /dev/mmcblk0p3: LABEL="SETTINGS" UUID="9b35a9e6-d81f-4eff-9096-633297a5410b" TYPE="ext4"
# /dev/mmcblk0p5: LABEL="boot0" UUID="035A-9F64" TYPE="vfat"
# /dev/mmcblk0p6: LABEL="root" UUID="53df0f2a-3f9c-4b76-afc9-17c60989988d" TYPE="ext4"
# /dev/mmcblk0p7: LABEL="boot" UUID="56A8-F127" TYPE="vfat"
# /dev/mmcblk0p8: LABEL="root0" UUID="aa2fec4f-70ac-49b5-bc59-be0cf74b76d7" TYPE="ext4"

function getBackupPartitionLabel() { # partition

	logEntry "getBackupPartitionLabel $1"

	local partition=$1
	local blkid
	local matches label

	blkid=$(grep $partition "$BLKID_FILE")
	logItem "BLKID: $1 - $blkid"

	regexFormatLineLabel="^.*LABEL=\"([^\"]+)\".*$"

	if [[ $blkid =~ $regexFormatLineLabel ]]; then
		label=${BASH_REMATCH[1]}
	else
		label=$(sed -E 's/\/dev\///' <<< $partition)	# strip /dev/
	fi

	echo "$label"

	logExit "getBackupPartitionLabel $label"

}

# parted -l -m
#BYT;
#/dev/mmcblk0:7969MB:sd/mmc:512:512:msdos:SD SD08G;
#1:1049kB:857MB:856MB:fat32::lba;
#2:860MB:7936MB:7076MB:::;
#5:1845MB:1895MB:49.3MB:fat32::lba;
#6:1896MB:3899MB:2003MB:::;
#7:3901MB:4438MB:537MB:ext4::;
#8:4442MB:4505MB:62.9MB:fat16::lba;
#9:4509MB:7926MB:3417MB:ext4::;
#3:7936MB:7969MB:33.6MB:ext4::;

function extractDataFromBackupPartedFile() { # partition fieldnumber

	logEntry "extractDataFromBackupPartedFile $1 $2"

	local partitionNo=$(sed -E "s%${BACKUP_BOOT_PARTITION_PREFIX}%%" <<< "$1")
	logItem "PartitionNo: $partitionNo"
	local parted element
	logItem "PARTED: $1 - $(<"$PARTED_FILE")"

	parted=$(grep "^$partitionNo" "$PARTED_FILE")
	logItem "PARTED: $1 - $parted"

	element=$(cut -d ":" -f $2 <<< $parted)

	echo "$element"

	logExit "extractDataFromBackupPartedFile $element"
}

function getBackupPartitionFilesystemSize() { # partition

	logEntry "getBackupPartitionFilesystemSize $1"

	local size
	size=$(extractDataFromBackupPartedFile $1 "4")
	echo "$size"

	logExit "getBackupPartitionFilesystemSize $size"

}

function getBackupPartitionFilesystem() { # partition

	logEntry "getBackupPartitionFilesystem $1"

	local fileSystem
	fileSystem=$(extractDataFromBackupPartedFile $1 "5")
	echo "$fileSystem"

	logExit "getBackupPartitionFilesystem $fileSystem"

}

function getPartitionBootFilesystem() { # partition_no

	logEntry "getPartitionBootFilesystem $1"

	local partitionNo=$1

	logItem "BOOT_DEVICENAME: $BOOT_DEVICENAME"

	local parted format
	logItem "PARTED: $1 - $(parted -m $BOOT_DEVICENAME print 2>/dev/null)"
	parted=$(grep "^${partitionNo}:" <(parted -m $BOOT_DEVICENAME print 2>/dev/null))
	logItem "PARTED: $1 - $parted"

	format=$(cut -d ":" -f 5 <<< $parted)

	echo "$format"

	logExit "getPartitionBootFilesystem $format"

}

function lastUsedPartitionByte() { # device

	logEntry "lastUsedPartitionByte $1"

	local partitionregex="/dev/.*[p]?([0-9]+).*start=[^0-9]*([0-9]+).*size=[^0-9]*([0-9]+).*(Id|type)=[^0-9a-z]*([0-9a-z]+)"
	local lastUsedPartitionByte=0

	while read line; do
		if [[ -z $line ]]; then
			continue
		fi

		logItem "$line"

		if [[ $line =~ $partitionregex ]]; then
			local p=${BASH_REMATCH[1]}
			local start=${BASH_REMATCH[2]}
			local size=${BASH_REMATCH[3]}
			local id=${BASH_REMATCH[5]}

			if [[ $id == 85 || $id == 5 ]]; then
				continue
			fi
			if (( $start > 0 )); then
				lastUsedPartitionByte=$((start+size))
			fi
		fi

	done < <(sfdisk -d $1 2>>$LOG_FILE)

	(( lastUsedPartitionByte*=512 ))

	echo "$lastUsedPartitionByte"

	logExit "lastUsedPartitionByte $lastUsedPartitionByte"

}

function restorePartitionBasedPartition() { # restorefile

	logEntry "restorePartitionBasedPartition $1"

	rc=0
	local verbose zip
	local restoreFile="$1"
	local restorePartition="$(basename "$restoreFile")"
	local partitionFormat
	local partitionLabel
	local cmd

	logItem "restorePartition: $restorePartition"
	local partitionNumber
	partitionNumber=$(sed -e "s%${BACKUP_BOOT_PARTITION_PREFIX}%%" -e "s%\..*$%%" <<< $restorePartition)
	logItem "Partitionnumber: $partitionNumber"

	local fileSystemsize
	fileSystemsize=$(getBackupPartitionFilesystemSize $partitionNumber)
	logItem "Filesystemsize: $fileSystemsize"

	restorePartition="${restorePartition%.*}"
	logItem "RestorePartition: $restorePartition"

	partitionLabel=$(getBackupPartitionLabel $restorePartition)
	partitionFilesystem=$(getBackupPartitionFilesystem $restorePartition)

	logItem "Label: $partitionLabel - Filesystem: $partitionFilesystem"

	local restoreDevice
	restoreDevice=${RESTORE_DEVICE%dev%%}
	[[ $restoreDevice =~ mmcblk0 || $restoreDevice =~ "loop" ]] && restoreDevice="${restoreDevice}p"
	logItem "RestoreDevice: $restoreDevice"

	local mappedRestorePartition
	mappedRestorePartition=$(sed "s%${BACKUP_BOOT_PARTITION_PREFIX}%${restoreDevice}%" <<< $restorePartition)

	if [[ ! "$partitionFilesystem" =~ $SUPPORTED_PARTITIONBACKUP_PARTITIONTYPE_REGEX ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNSUPPORTED_FILESYSTEM_FORMAT "$partitionFilesystem" "$mappedRestorePartition"
		exitError $RC_MISC_ERROR

	elif [[ ! -z $partitionFilesystem ]]; then
		logItem "partitionFilesystem: \"$partitionFilesystem\""

		local fs="$partitionFilesystem"
		local fatSize=""
		local fatCmd=""

		local swapDetected=0
		if [[ "$partitionFilesystem" =~ ^fat.* ]]; then
			fs="vfat"
			fatSize=$(sed 's/fat//' <<< $partitionFilesystem)
			fatCmd="-I -F $fatSize"
			logItem "fs: $fs - fatSize: $fatSize - fatCmd: $fatCmd"
			cmd="mkfs -t $fs $fatCmd"
		elif [[ "$partitionFilesystem" =~ swap ]]; then
			cmd="mkswap"
			swapDetected=1
			logItem "Swap partition"
		else
			if [[ $partitionFilesystem == "btrfs" ]]; then
				cmd="mkfs.btrfs -f"
			else
				cmd="mkfs -t $fs"
			fi
			logItem "Normal partition with $partitionFilesystem"
		fi

		writeToConsole $MSG_LEVEL_DETAILED $MSG_FORMATTING "$mappedRestorePartition" "$partitionFilesystem" $fileSystemsize
		logItem "$cmd $mappedRestorePartition"

		$cmd $mappedRestorePartition &>>"$LOG_FILE"

		rc=$?
		if (( $rc )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_MKFS_FAILED "$cmd" "$rc"
			exitError $RC_MISC_ERROR
		fi

		if (( ! $swapDetected )); then
			writeToConsole $MSG_LEVEL_DETAILED $MSG_LABELING "$mappedRestorePartition" "$partitionLabel"

			# Keep SUPPORTED_PARTITIONBACKUP_PARTITIONTYPE_REGEX in sync

			local labelPartition=0
			case $partitionFilesystem in
				ext2|ext3|ext4) cmd="e2label"
					labelPartition=1
					;;
				fat16|fat32) cmd="dosfslabel"
					labelPartition=1
					;;
				btrfs) cmd="btrfs filesystem label"
					labelPartition=1
					;;
			esac

			if (( $labelPartition )); then
				logItem "$cmd $mappedRestorePartition $partitionLabel"
				$cmd $mappedRestorePartition $partitionLabel &>>"$LOG_FILE"
				rc=$?
				if (( $rc )); then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_LABELING_FAILED "$cmd" "$rc"
					exitError $RC_LABEL_ERROR
				fi
			else
				logItem "Partition $mappedRestorePartition not labeled"
			fi

			logItem "mount $mappedRestorePartition $MNT_POINT"
			mount $mappedRestorePartition $MNT_POINT

			logItem "Restoring file $restoreFile"
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORING_PARTITIONFILE "$mappedRestorePartition"

			(( $VERBOSE )) && verbose="v" || verbose=""

			logItem "Backuptype: $BACKUPTYPE"

			rc=$RC_NATIVE_BACKUP_FAILED

			case $BACKUPTYPE in

				$BACKUPTYPE_DD|$BACKUPTYPE_DDZ)
					if [[ $BACKUPTYPE == $BACKUPTYPE_DD ]]; then
						if (( $PROGRESS )); then
							cmd="if=\"$restoreFile\" $DD_PARMS | pv -fs $(stat -c %s "$restoreFile") | dd of=$RESTORE_DEVICE bs=$DD_BLOCKSIZE"
						else
							cmd="if=\"$restoreFile\" $DD_PARMS of=$RESTORE_DEVICE bs=$DD_BLOCKSIZE"
						fi
					else
						if (( $PROGRESS )); then
							cmd="gunzip -c \"$restoreFile\" | pv -fs $(stat -c %s "$restoreFile") | dd of=$RESTORE_DEVICE bs=$DD_BLOCKSIZE $DD_PARMS"
						else
							cmd="gunzip -c \"$restoreFile\" | dd of=$RESTORE_DEVICE bs=$DD_BLOCKSIZE $DD_PARMS"
						fi
					fi

					executeCommand "$cmd"
					rc=$?
					;;

				$BACKUPTYPE_TAR|$BACKUPTYPE_TGZ)
					local archiveFlags=""
					[[ -n $fatSize  ]] && archiveFlags="--no-same-owner --no-same-permissions --numeric-owner"	# fat32 doesn't know about this
					pushd "$MNT_POINT" &>>"$LOG_FILE"
					[[ $BACKUPTYPE == $BACKUPTYPE_TGZ ]] && zip="z" || zip=""					
					cmd="tar ${archiveFlags} -x${verbose}${zip}f \"$restoreFile\""
					if (( $PROGRESS )); then
						cmd="$pv -f $restoreFile | $cmd -"
					fi					
					executeCommand "$cmd"
					rc=$?
					popd &>>"$LOG_FILE"
					;;

				$BACKUPTYPE_RSYNC)
					local archiveFlags="aH"						# -a <=> -rlptgoD, H = preserve hardlinks
					[[ -n $fatSize  ]] && archiveFlags="rltD"	# no Hopg flags for fat fs
					cmd="rsync --numeric-ids -${archiveFlags}X$verbose \"$restoreFile/\" $MNT_POINT"
					if (( $PROGRESS )); then
						cmd="rsync --info=progress2 $cmdParms"
					fi
					executeCommand "$cmd"
					rc=$?
					;;

				*)  logItem "Invalid backupo type $BACKUPTYPE found"
					assertionFailed $LINENO "Invalid backup type $BACKUPTYPE detected"
					;;

			esac

			if [[ $rc != 0 ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_PROGRAM_ERROR $BACKUPTYPE $rc
				exitError $RC_NATIVE_BACKUP_FAILED
			fi

			sleep 1s					# otherwise umount fails

			logItem "umount $mappedRestorePartition"
			umount $mappedRestorePartition

			if isMounted $MNT_POINT; then
				logItem "umount $MNT_POINT"
				umount -f $MNT_POINT &>$LOG_FILE
				if [ $? -ne 0 ]; then
					assertionFailed $LINENO "Unable to umount $MNT_POINT"
				fi
			fi

			writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORING_FILE_PARTITION_DONE "$mappedRestorePartition"

		else
			logItem "Skipping to label and restore partition $mappedRestorePartition"
		fi # ! swapDetected

	else
		assertionFailed $LINENO "This error should not occur"
	fi

	logExit "restorePartitionBasedPartition"

}

function doitRestore() {

	logEntry "doitRestore"

	commonChecks

	trapWithArg cleanup SIGINT SIGTERM EXIT

	if [[ ! -d "$RESTOREFILE" && ! -f "$RESTOREFILE" ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_ARG_NOT_FOUND "$RESTOREFILE"
		exitError $RC_MISSING_FILES
	fi

	logItem "ls $RESTOREFILE$NL$(ls $RESTOREFILE)"

	local regex=""
	for type in $POSSIBLE_TYPES; do
		[[ -z $regex ]] && regex="$type" || regex="$regex|$type"
	done
	regex="\-($regex)\-backup\-"
	logItem "Basename: $(basename "$RESTOREFILE")"
	logItem "regex: $regex"

	if [[ ! $(basename "$RESTOREFILE") =~ $regex ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_FILE_INVALID "$RESTOREFILE"
		exitError $RC_MISSING_FILES
	fi

	if isMounted "$RESTORE_DEVICE"; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_DEVICE_MOUNTED "$RESTORE_DEVICE"
		exitError $RC_MISC_ERROR
	fi

	if (( $ROOT_PARTITION_DEFINED )); then
		if ! [[ "$ROOT_PARTITION" =~ ^/dev/[a-z]+[0-9]$ ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_INVALID_RESTORE_ROOT_PARTITION "$ROOT_PARTITION"
			exitError $RC_DEVICES_NOTFOUND
		fi

		if ! [[ -e "$ROOT_PARTITION" ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_ROOT_PARTITION_NOT_FOUND "$ROOT_PARTITION"
			exitError $RC_DEVICES_NOTFOUND
		fi
	fi

	logItem "Checking for partitionbasedbackup in $RESTOREFILE/*"
	logItem "ls: of $RESTOREFILE"
	logItem $(ls -1 "$RESTOREFILE"* 2>/dev/null)

	if [[ -n $(ls -1 "$RESTOREFILE"* | egrep "^(sd|mmcblk).*" 2>/dev/null) ]]; then
		PARTITIONBASED_BACKUP=1
	else
		PARTITIONBASED_BACKUP=0
	fi

	logItem "PartitionbasedBackup detected? $PARTITIONBASED_BACKUP"

	if [[ -z $RESTORE_DEVICE ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_RESTOREDEVICE_DEFINED
		exitError $RC_PARAMETER_ERROR
	fi

	if (( $PROGRESS )) && [[ "$BACKUPTYPE" == "$BACKUPTYPE_DD" || "$BACKUPTYPE" == "$BACKUPTYPE_DDZ" ]] && [[ ! $(which pv) ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "pv" "pv"
		exitError $RC_PARAMETER_ERROR
	fi

	if ! (( $FAKE )); then
		if [[ ! ( $RESTORE_DEVICE =~ ^/dev/mmcblk[0-9]$ ) && ! ( $RESTORE_DEVICE =~ "/dev/loop" ) ]]; then
			if ! [[ "$RESTORE_DEVICE" =~ ^/dev/[a-zA-Z]+$ ]] ; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTOREDEVICE_IS_PARTITION
				exitError $RC_PARAMETER_ERROR
			fi
		fi

		if [[ -z $(fdisk -l $RESTORE_DEVICE 2>/dev/null) ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_RESTOREDEVICE_FOUND $RESTORE_DEVICE
			exitError $RC_PARAMETER_ERROR
		fi
	fi

	BASE_DIR=$(dirname "$RESTOREFILE")
	logItem "Basedir: $BASE_DIR"
	HOSTNAME=$(basename "$RESTOREFILE" | sed -r 's/(.*)-[A-Za-z]+-backup-[0-9]+-[0-9]+.*/\1/')
	logItem "Hostname: $HOSTNAME"
	BACKUPTYPE=$(basename "$RESTOREFILE" | sed -r 's/.*-([A-Za-z]+)-backup-[0-9]+-[0-9]+.*/\1/')
	logItem "Backuptype: $BACKUPTYPE"
	DATE=$(basename "$RESTOREFILE" | sed -r 's/.*-[A-Za-z]+-backup-([0-9]+-[0-9]+).*/\1/')
	logItem "Date: $DATE"

	if [[ "$BACKUPTYPE" == "$BACKUPTYPE_RSYNC" ]]; then
		if [[ ! $(which rsync) ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "rsync" "rsync"
			exitError $RC_PARAMETER_ERROR
		fi
		local rsyncVersion=$(rsync --version | head -n 1 | awk '{ print $3 }')
		logItem "rsync version: $rsyncVersion"
		if (( $PROGRESS )) && [[ "$rsyncVersion" < "3.1" ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_RSYNC_DOES_NOT_SUPPORT_PROGRESS "$rsyncVersion"
			exitError $RC_PARAMETER_ERROR
		fi
	fi

	if (( $PARTITIONBASED_BACKUP )); then
		if ! $(which dosfslabel &>/dev/null); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "dosfslabel" "dosfstools"
			exitError $RC_MISSING_FILES
		fi
	fi

	if (( ! $PARTITIONBASED_BACKUP	 )); then
		findNonpartitionBackupBootAndRootpartitionFiles
	fi

	inspect4Backup
	inspect4Restore

	if (( $FORCE_SFDISK )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_FORCE_SFDISK "$RESTORE_DEVICE"
	fi

	if (( $SKIP_SFDISK )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_SKIP_SFDISK "$RESTORE_DEVICE"
	fi

	# adjust partition for tar and rsync backup in normal mode

	if (( ! $PARTITIONBASED_BACKUP )) && [[ $BACKUPTYPE != $BACKUPTYPE_DD && $BACKUPTYPE != $BACKUPTYPE_DDZ ]] && (( ! $ROOT_PARTITION_DEFINED )); then

		local sourceSDSize=$(calcSumSizeFromSFDISK "$SF_FILE")
		local targetSDSize=$(blockdev --getsize64 $RESTORE_DEVICE)
		logItem "soureSDSize: $sourceSDSize - targetSDSize: $targetSDSize"

		if (( ! $FORCE_SFDISK && ! $SKIP_SFDISK )); then
			if (( sourceSDSize != targetSDSize )); then
				if (( sourceSDSize > targetSDSize )); then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_ADJUSTING_WARNING "$RESTORE_DEVICE" "$(bytesToHuman $targetSDSize)" "$(bytesToHuman $sourceSDSize)"
				else
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_ADJUSTING_WARNING2 "$RESTORE_DEVICE" "$(bytesToHuman $targetSDSize)" "$(bytesToHuman $sourceSDSize)"
				fi
			fi
		fi
	fi

	reportNews

	rc=0

	if ! (( $PARTITIONBASED_BACKUP )); then
		restoreNonPartitionBasedBackup
		if [[ $BACKUPTYPE != $BACKUPTYPE_DD && $BACKUPTYPE != $BACKUPTYPE_DDZ ]] && (( $ROOT_PARTITION_DEFINED )); then
			synchronizeCmdlineAndfstab
		fi
	else
		restorePartitionBasedBackup
	fi

	logExit "doitRestore (rc=$rc)"

}

function remount() { # device mountpoint

	if ( isMounted "$1" ); then
		logItem "$1 mounted - unmouting"
		umount "$1"
	else
		logItem "$1 not mounted"
	fi

	logItem "Creating mountpoint $2"
	mkdir -p $2
	mount "$1" "$2"

}

function synchronizeCmdlineAndfstab() {
	logEntry "syncronizeCmdlineAndfstab"

	local CMDLINE FSTAB newPartUUID oldPartUUID root_partition BOOT_MP ROOT_MP

	if [[ $RESTORE_DEVICE =~ "/dev/mmcblk0" || $RESTORE_DEVICE =~ "/dev/loop" ]]; then
		root_partition=$(sed -E 's/p[0-9]+$//' <<< $ROOT_PARTITION)
	else
		root_partition=$(sed -E 's/[0-9]+$//' <<< $ROOT_PARTITION)
	fi

	if (( $ROOT_PARTITION_DEFINED )); then
		root_partition="$ROOT_PARTITION"
	fi

	BOOT_PARTITION=${RESTORE_DEVICE}1
	ROOT_MP="$TEMPORARY_MOUNTPOINT_ROOT/root"
	BOOT_MP="$TEMPORARY_MOUNTPOINT_ROOT/boot"
	remount "$BOOT_PARTITION" "$BOOT_MP"
	remount "$ROOT_PARTITION" "$ROOT_MP"

	CMDLINE="$BOOT_MP/cmdline.txt"
	FSTAB="$ROOT_MP/etc/fstab"

	logItem "Org $CMDLINE"
	logItem "$(cat $CMDLINE)"

	logItem "Org $FSTAB"
	logItem "$(cat $FSTAB)"

	if [[ -f "$CMDLINE" && $(cat $CMDLINE) =~ root=PARTUUID=([a-z0-9\-]+) ]]; then
		oldPartUUID=${BASH_REMATCH[1]}
		newPartUUID=$(blkid -o udev $root_partition | grep PARTUUID | cut -d= -f2)
		if [[ $oldPartUUID != $newPartUUID ]]; then
			logItem "CMDLINE - newPartUUID: $newPartUUID, oldPartUUID: $oldPartUUID"
			writeToConsole $MSG_LEVEL_DETAILED $MSG_UPDATING_CMDLINE "$oldPartUUID" "$newPartUUID"
			sed -i "s/$oldPartUUID/$newPartUUID/" $CMDLINE &>> LOG_FILE
		fi
	fi

	if [[ -f "$FSTAB" && $(cat $FSTAB) =~ PARTUUID=([a-z0-9\-]+)[[:space:]]+/[[:space:]] ]]; then
		oldPartUUID=${BASH_REMATCH[1]}
		newPartUUID=$(blkid -o udev $root_partition | grep PARTUUID | cut -d= -f2)
		if [[ $oldPartUUID != $newPartUUID ]]; then
			logItem "FSTAB root - newBootPartUUID: $newPartUUID, oldBootPartUUID: $oldPartUUID"
			writeToConsole $MSG_LEVEL_DETAILED $MSG_UPDATING_FSTAB "$oldPartUUID" "$newPartUUID"
			sed -i "s/$oldPartUUID/$newPartUUID/" $FSTAB &>> LOG_FILE
		fi
	fi

	if [[ -f "$FSTAB" && $(cat $FSTAB) =~ PARTUUID=([a-z0-9\-]+)[[:space:]]+/boot ]]; then
		oldPartUUID=${BASH_REMATCH[1]}
		newPartUUID=$(blkid -o udev $BOOT_PARTITION | grep PARTUUID | cut -d= -f2)
		if [[ $oldPartUUID != $newPartUUID ]]; then
			logItem "FSTAB boot - newPartUUID: $newPartUUID, oldPartUUID: $oldPartUUID"
			writeToConsole $MSG_LEVEL_DETAILED $MSG_UPDATING_FSTAB "$oldPartUUID" "$newPartUUID"
			sed -i "s/$oldPartUUID/$newPartUUID/" $FSTAB &>> LOG_FILE
		fi
	fi

	logItem "Upd $CMDLINE"
	logItem "$(cat $CMDLINE)"

	logItem "Upd $FSTAB"
	logItem "$(cat $FSTAB)"

	umount $BOOT_MP
	umount $ROOT_MP

	logExit "syncronizeCmdlineAndfstab"
}

function lockingFramework() {

	# Copyright (C) 2009 Przemyslaw Pawelczyk <przemoc@gmail.com>
	# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
	# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
	# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

	LOCKFILE="/var/lock/$MYNAME"
	LOCKFD=99

# PRIVATE
	_lock()             { flock -$1 $LOCKFD; }
	_no_more_locking()  { _lock u; _lock xn && rm -f $LOCKFILE ; }
	_prepare_locking()  { eval "exec $LOCKFD>\"$LOCKFILE\""; trap _no_more_locking EXIT; }

# ON START
	_prepare_locking

# PUBLIC
	exlock_now()        { _lock xn; }  # obtain an exclusive lock immediately or fail
	exlock()            { _lock x; }   # obtain an exclusive lock
	shlock()            { _lock s; }   # obtain a shared lock
	unlock()            { _lock u; }   # drop a lock
}

function usageEN() {

    echo "$GIT_CODEVERSION"
    echo "usage: $MYSELF [option]* [backupDirectory | backupFile]"
    echo ""
    echo "-General options-"
    echo "-A append logfile to eMail (default: ${NO_YES[$DEFAULT_APPEND_LOG]})"
    [ -z "$DEFAULT_EMAIL" ] && DEFAULT_EMAIL="no"
    echo "-b {dd block size} (default: $DEFAULT_DD_BLOCKSIZE)"
    [ -z "$DEFAULT_DD_PARMS" ] && DEFAULT_DD_PARMS="no"
    echo "-D \"{additional dd parameters}\" (default: $DEFAULT_DD_PARMS)"
    echo "-e {email address} (default: $DEFAULT_EMAIL)"
    [ -z "$DEFAULT_EMAIL_PARMS" ] && DEFAULT_EMAIL_PARMS="no"
    echo "-E \"{additional email call parameters}\" (default: $DEFAULT_EMAIL_PARMS)"
    echo "-g Display progress bar"
    echo "-G {message language} (EN or DE) (default: $DEFAULT_LANGUAGE)"
    echo "-h display this help text"
    echo "-l {log level} ($POSSIBLE_LOG_LEVELs) (default: ${LOG_LEVELs[$DEFAULT_LOG_LEVEL]})"
    echo "-L {log location} ($POSSIBLE_LOG_LOCs) (default: ${LOG_OUTPUTs[$DEFAULT_LOG_OUTPUT]})"
    echo "-m {message level} ($POSSIBLE_MSG_LEVELs) (default: ${MSG_LEVELs[$DEFAULT_MSG_LEVEL]})"
    echo "-M {backup description}"
    echo "-n notification if there is a newer scriptversion available for download (default: ${NO_YES[$DEFAULT_NOTIFY_UPDATE]})"
    echo "-s {email program to use} ($SUPPORTED_MAIL_PROGRAMS) (default: $DEFAULT_MAIL_PROGRAM)"
    echo "-u \"{excludeList}\" List of directories to exclude from tar and rsync backup"
    echo "-U current script version will be replaced by the actual version. Current version will be saved and can be restored with parameter -V"
    echo "-v verbose output of backup tools (default: ${NO_YES[$DEFAULT_VERBOSE]})"
    echo "-V restore a previous version"
    echo "-z compress backup file with gzip (default: ${NO_YES[$DEFAULT_ZIP_BACKUP]})"
	echo ""
    echo "-Backup options-"
    [ -z "$DEFAULT_STOPSERVICES" ] && DEFAULT_STOPSERVICES="no"
    echo "-a \"{commands to execute after Backup}\" (default: $DEFAULT_STARTSERVICES)"
    echo "-k {backupsToKeep} (default: $DEFAULT_KEEPBACKUPS)"
    [ -z "$DEFAULT_STARTSERVICES" ] && DEFAULT_STARTSERVICES="no"
    echo "-o \"{commands to execute before Backup}\" (default: $DEFAULT_STOPSERVICES)"
    echo "-P use dedicated partitionbackup mode (default: ${NO_YES[$DEFAULT_PARTITIONBASED_BACKUP]})"
    echo "-t {backupType} ($ALLOWED_TYPES) (default: $DEFAULT_BACKUPTYPE)"
    echo "-T \"{List of partitions to save}\" (Partition numbers, e.g. \"1 2 3\"). Only valid with parameter -P (default: ${DEFAULT_PARTITIONS_TO_BACKUP})"
	echo ""
	echo "-Restore options-"
	[ -z "$DEFAULT_RESTORE_DEVICE" ] && DEFAULT_RESTORE_DEVICE="no"
	echo "-d {restoreDevice} (default: $DEFAULT_RESTORE_DEVICE) (Example: /dev/sda)"
	echo "-R {rootPartition} (default: restoreDevice) (Example: /dev/sdb1)"
}

function usageDE() {

    echo "$GIT_CODEVERSION"
    echo "Aufruf: $MYSELF [Option]* [Backupverzeichnis | BackupDatei]"
    echo ""
    echo "-Allgemeine Optionen-"
    echo "-A Logfile wird in eMail angehängt (Standard: ${NO_YES[$DEFAULT_APPEND_LOG]})"
    [ -z "$DEFAULT_EMAIL" ] && DEFAULT_EMAIL="nein"
    echo "-b {dd Blockgröße} (Standard: $DEFAULT_DD_BLOCKSIZE)"
    [ -z "$DEFAULT_DD_PARMS" ] && DEFAULT_DD_PARMS="nein"
    echo "-D \"{Zusätzliche dd Parameter}\" (Standard: $DEFAULT_DD_PARMS)"
    echo "-e {eMail Addresse} (Standard: $DEFAULT_EMAIL)"
    [ -z "$DEFAULT_EMAIL_PARMS" ] && DEFAULT_EMAIL_PARMS="nein"
    echo "-E \"{Zusätzliche eMail Aufrufparameter}\" (Standard: $DEFAULT_EMAIL_PARMS)"
    echo "-g Anzeige des Fortschritts"
    echo "-G {Meldungssprache} (DE oder EN) (Standard: $DEFAULT_LANGUAGE)"
    echo "-h Anzeige dieses Hilfstextes"
    echo "-l {log Genauigkeit} ($POSSIBLE_LOG_LEVELs) (Standard: ${LOG_LEVELs[$DEFAULT_LOG_LEVEL]})"
    echo "-L {log Ausgabeort} ($POSSIBLE_LOG_LOCs) (Standard: ${LOG_OUTPUTs[$DEFAULT_LOG_OUTPUT]})"
    echo "-m {Meldungsgenauigkeit} ($POSSIBLE_MSG_LEVELs) (Standard: ${MSG_LEVELs[$DEFAULT_MSG_LEVEL]})"
    echo "-M {Backup Beschreibung}"
    echo "-n Benachrichtigung wenn eine aktuellere Scriptversion zum download verfügbar ist. (Standard: ${NO_YES[$DEFAULT_NOTIFY_UPDATE]})"
    echo "-s {Benutztes eMail Program} ($SUPPORTED_MAIL_PROGRAMS) (Standard: $DEFAULT_MAIL_PROGRAM)"
    echo "-u \"{excludeList}\" Liste von Verzeichnissen, die vom tar und rsync Backup auszunehmen sind"
    echo "-U Scriptversion wird durch die aktuelle Version ersetzt. Die momentane Version wird gesichert und kann mit dem Parameter -V wiederhergestellt werden"
    echo "-v Detailierte Ausgaben der Backup Tools (Standard: ${NO_YES[$DEFAULT_VERBOSE]})"
    echo "-V Aktivierung einer älteren Skriptversion"
    echo "-z Backup verkleinern mit gzip (Standard: ${NO_YES[$DEFAULT_ZIP_BACKUP]})"
	echo ""
    echo "-Backup Optionen-"
    [ -z "$DEFAULT_STOPSERVICES" ] && DEFAULT_STOPSERVICES="keine"
    echo "-a \"{Befehle die nach dem Backup ausgeführt werden}\" (Standard: $DEFAULT_STARTSERVICES)"
    echo "-k {Anzahl Backups} (Standard: $DEFAULT_KEEPBACKUPS)"
    [ -z "$DEFAULT_STARTSERVICES" ] && DEFAULT_STARTSERVICES="keine"
    echo "-o \"{Befehle die vor dem Backup ausgeführt werden}\" (Standard: $DEFAULT_STOPSERVICES)"
    echo "-P Speziellen Partitionsbackupmodus benutzen (Standard: ${NO_YES[$DEFAULT_PARTITIONBASED_BACKUP]})"
    echo "-t {Backuptyp} ($ALLOWED_TYPES) (Standard: $DEFAULT_BACKUPTYPE)"
    echo "-T \"Liste der Partitionen die zu Sichern sind}\" (Partitionsnummern, z.B. \"1 2 3\"). Nur gültig zusammen mit Parameter -P (Standard: ${DEFAULT_PARTITIONS_TO_BACKUP})"
	echo ""
	echo "-Restore Optionen-"
	[ -z "$DEFAULT_RESTORE_DEVICE" ] && DEFAULT_RESTORE_DEVICE="keiner"
	echo "-d {restoreGerät} (Standard: $DEFAULT_RESTORE_DEVICE) (Beispiel: /dev/sda)"
	echo "-R {rootPartition} (Standard: restoreDevice) (Beispiel: /dev/sdb1)"
}

function mentionHelp() {
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_MENTION_HELP $MYSELF
}

##### Now do your job

INVOCATIONPARMS=""			# save passed opts for logging
invocationParms=()			# and restart
for (( i=1; i<=$#; i++ )); do
	p=${!i}
	INVOCATIONPARMS="$INVOCATIONPARMS $p"
	invocationParms+=("$p")
done

# setup defaults for parameters
# 0 is false, true otherwise

readConfigParameters		# overwrite defaults with settings in config files

BACKUPPATH="$DEFAULT_BACKUPPATH"
KEEPBACKUPS=$DEFAULT_KEEPBACKUPS
BACKUPTYPE=$DEFAULT_BACKUPTYPE
STOPSERVICES=$DEFAULT_STOPSERVICES
STARTSERVICES=$DEFAULT_STARTSERVICES
EMAIL=$DEFAULT_EMAIL
EMAIL_PROGRAM=$DEFAULT_MAIL_PROGRAM
EMAIL_PARMS="$DEFAULT_EMAIL_PARMS"
LOG_LEVEL=$DEFAULT_LOG_LEVEL
MSG_LEVEL=$DEFAULT_MSG_LEVEL
VERBOSE=$DEFAULT_VERBOSE
RESTORE_DEVICE=$DEFAULT_RESTORE_DEVICE
APPEND_LOG=$DEFAULT_APPEND_LOG
LOG_OUTPUT="$DEFAULT_LOG_OUTPUT"
SKIPLOCALCHECK=$DEFAULT_SKIPLOCALCHECK
DD_BLOCKSIZE=$DEFAULT_DD_BLOCKSIZE
DD_PARMS=$DEFAULT_DD_PARMS
DD_BACKUP_SAVE_USED_PARTITIONS_ONLY=$DEFAULT_DD_BACKUP_SAVE_USED_PARTITIONS_ONLY
EXCLUDE_LIST=$DEFAULT_EXCLUDE_LIST
ZIP_BACKUP=$DEFAULT_ZIP_BACKUP
NOTIFY_UPDATE=$DEFAULT_NOTIFY_UPDATE
EXTENSIONS=$DEFAULT_EXTENSIONS
PARTITIONBASED_BACKUP=$DEFAULT_PARTITIONBASED_BACKUP
YES_NO_RESTORE_DEVICE=$DEFAULT_YES_NO_RESTORE_DEVICE
DEPLOYMENT_HOSTS=$DEFAULT_DEPLOYMENT_HOSTS
PARTITIONS_TO_BACKUP=$DEFAULT_PARTITIONS_TO_BACKUP
MAIL_ON_ERROR_ONLY=$DEFAULT_MAIL_ON_ERROR_ONLY
RSYNC_BACKUP_OPTIONS=$DEFAULT_RSYNC_BACKUP_OPTIONS
RSYNC_BACKUP_ADDITIONAL_OPTIONS=$DEFAULT_RSYNC_BACKUP_ADDITIONAL_OPTIONS
TAR_BACKUP_OPTIONS=$DEFAULT_TAR_BACKUP_OPTIONS
TAR_BACKUP_ADDITIONAL_OPTIONS=$DEFAULT_TAR_BACKUP_ADDITIONAL_OPTIONS
LINK_BOOTPARTITIONFILES=$DEFAULT_LINK_BOOTPARTITIONFILES
HANDLE_DEPRECATED=$DEFAULT_HANDLE_DEPRECATED
USE_UUID=$DEFAULT_USE_UUID

if [[ -z $DEFAULT_LANGUAGE ]]; then
	LANG_EXT=${LANG^^*}
	DEFAULT_LANGUAGE=${LANG_EXT:0:2}
fi
LANGUAGE=$DEFAULT_LANGUAGE

# misc other vars

FAKE=0
HELP=0
BACKUPFILE=""
DEPLOY=0
EXCLUDE_DD=0
UPDATE_MYSELF=0
REVERT=0
NO_YES_QUESTION=0
FORCE_SFDISK=0
SKIP_SFDISK=0
REGRESSION_TEST=0
FAKE_BACKUPS=0
SKIP_RSYNC_CHECK=0
FORCE_UPDATE=0
RESTORE=0
RESTOREFILE=""
BACKUP_DIRECTORY_NAME=""
BACKUP_STARTED=0
ROOT_PARTITION_DEFINED=0
NEW_BACKUP_DIRECTORY_CREATED=0
PROGRESS=0

while getopts ":0159a:Ab:cd:D:e:E:FgG:hik:l:L:m:M:nN:o:p:Pr:R:s:St:T:u:UvVxyYzZ" opt; do

   case $opt in
		0)	SKIP_SFDISK=1
			;;
		1)	FORCE_SFDISK=1
			;;
		5)  SKIP_RSYNC_CHECK=1
			;;
		9)	FAKE_BACKUPS=1
			;;
		a) 	STARTSERVICES="$OPTARG"
			;;
		A) 	APPEND_LOG=1
			;;
		b)	DD_BLOCKSIZE="$OPTARG"
			;;
		c)  SKIPLOCALCHECK=1
			;;
		d) 	RESTORE_DEVICE="$OPTARG"
			RESTORE=1
			;;
		D)	DD_PARMS="$OPTARG"
			;;
		e)	EMAIL="$OPTARG"
			;;
		E)	EMAIL_PARMS="$OPTARG"
			;;
		F) 	FAKE=1
			;;
		g)	PROGRESS=1
			;;
		G)	LANGUAGE="$OPTARG"
			LANGUAGE=${LANGUAGE^^*}
			msgVar="MSG_${LANGUAGE}"
			if [[ -z ${!msgVar} ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_LANGUAGE_NOT_SUPPORTED $LANGUAGE
				exitError $RC_PARAMETER_ERROR
			fi
			;;
		i)  if (( ! $IS_BETA )); then
				USE_UUID=$(( ! $USE_UUID ))
			fi
			;;
		k) 	KEEPBACKUPS="$OPTARG"
			;;
		l) 	LOG_LEVEL="$OPTARG"
			;;
		L) 	LOG_OUTPUT="$OPTARG"
			;;
		m) 	MSG_LEVEL="$OPTARG"
			;;
		M)	BACKUP_DIRECTORY_NAME="$OPTARG"
			BACKUP_DIRECTORY_NAME=${BACKUP_DIRECTORY_NAME//[ \/\:\.\-]/_}
			;;
		n)  NOTIFY_UPDATE=$(( ! $NOTIFY_UPDATE ))
			;;
		N)  EXTENSIONS="$OPTARG"
			;;
		o) 	STOPSERVICES="$OPTARG"
			;;
       	p) 	if [[ ! -d "$OPTARG" ]]; then
		        writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_ARG_NOT_FOUND "$OPTARG"
        		exitError $RC_MISSING_FILES
	       	fi
            BACKUPPATH="$(readlink -f "$OPTARG")"
			;;
		P) 	PARTITIONBASED_BACKUP=1
			;;
		r) 	if [[ ! -d "$OPTARG" && ! -f "$OPTARG" ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_ARG_NOT_FOUND "$OPTARG"
				exitError $RC_MISSING_FILES
			fi
			RESTOREFILE="$(readlink -f "$OPTARG")"
			;;
		R) 	ROOT_PARTITION_DEFINED=1
			ROOT_PARTITION="$OPTARG"
			;;
		s)	EMAIL_PROGRAM="$OPTARG"
			;;
		S)	FORCE_UPDATE=1
			;;
		t) 	BACKUPTYPE="$OPTARG"
			;;
		T)	if [[ "$OPTARG" == "$PARTITIONS_TO_BACKUP_ALL" ]]; then
				PARTITIONS_TO_BACKUP=("$OPTARG")
			else
				PARTITIONS_TO_BACKUP=($OPTARG)
			fi
			;;
		u)	EXCLUDE_LIST="$OPTARG"
			;;
		U)	UPDATE_MYSELF=1
			;;
		v)	VERBOSE=1
			;;
		V)	REVERT=1
			;;
		x)	EXCLUDE_DD=1
			;;
		y)	DEPLOY=1
			;;
		Y)	NO_YES_QUESTION=1
			;;
		z)	ZIP_BACKUP=1
			;;
		Z)	REGRESSION_TEST=1
			;;
		h)  HELP=1
			;;
		\?)	writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNKNOWN_OPTION "-$OPTARG"
			mentionHelp
			exitError $RC_PARAMETER_ERROR
			;;
		:) 	writeToConsole $MSG_LEVEL_MINIMAL $MSG_OPTION_REQUIRES_PARAMETER "-$OPTARG"
			mentionHelp
			exitError $RC_PARAMETER_ERROR
			;;
    esac
done
shift $((OPTIND-1))

writeToConsole $MSG_LEVEL_MINIMAL $MSG_STARTED "$HOSTNAME" "$MYSELF" "$VERSION" "$(date)" "$GIT_COMMIT_ONLY"
(( $IS_BETA )) && writeToConsole $MSG_LEVEL_MINIMAL $MSG_INTRO_BETA_MESSAGE
(( $IS_HOTFIX )) && writeToConsole $MSG_LEVEL_MINIMAL $MSG_INTRO_HOTFIX_MESSAGE

fileParameter="$1"
if [[ -n "$1" ]]; then
	shift 1
	if [[ ! -d "$fileParameter" && ! -f "$fileParameter" ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_ARG_NOT_FOUND "$fileParameter"
		exitError $RC_MISSING_FILES
	else
		fileParameter="$(readlink -f "$fileParameter")"
	fi
fi

unusedParms="$@"

if (( $HELP )); then
	usage
	exitNormal
fi

if [[ -n "$unusedParms" ]]; then
	usage
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNUSED_PARAMETERS "$unusedParms"
	exitError $RC_PARAMETER_ERROR
fi

if (( $DEPLOY )); then
    deployMyself
    exitNormal

elif (( $REVERT )); then
	revertScriptVersion
	exitNormal
else

	if (( $NO_YES_QUESTION )); then				# dangerous option
		if [[ ! $RESTORE_DEVICE =~ "$YES_NO_RESTORE_DEVICE" ]]; then	# make sure we're not killing a disk by accident
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_YES_NO_DEVICE_MISMATCH $RESTORE_DEVICE $YES_NO_RESTORE_DEVICE
			exitError $RC_MISC_ERROR
		fi
	fi

	substituteNumberArguments
	checkAndCorrectImportantParameters	# no return if errors detected

	if (( $RESTORE )) && [[ -n $fileParameter ]]; then
		RESTOREFILE="$fileParameter"
	elif (( ! $RESTORE )) && [[ -n $fileParameter ]]; then
		BACKUPPATH="$fileParameter"
	elif [[ -z "$RESTOREFILE" && -z "$BACKUPPATH" ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_FILEPARAMETER
		mentionHelp
		exitError $RC_MISSING_FILES
	fi

	if (( $UID != 0 )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_RUNASROOT "$0" "$INVOCATIONPARMS"
		exitError $RC_MISC_ERROR
	fi

	setupEnvironment
	logOptions						# config parms already read

	if (( ! $RESTORE )); then
		lockingFramework
		exlock_now
		if (( $? )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_INSTANCE_ACTIVE
			exitError $RC_MISC_ERROR
		fi
	fi		

	writeToConsole $MSG_LEVEL_DETAILED $MSG_USING_LOGFILE "$LOG_FILE_FINAL"

	if (( $ETC_CONFIG_FILE_INCLUDED )); then
		logItem "/etc/config$NL$(cat $ETC_CONFIG_FILE)"
		writeToConsole $MSG_LEVEL_DETAILED $MSG_INCLUDED_CONFIG "$ETC_CONFIG_FILE"
	fi

	if (( $HOME_CONFIG_FILE_INCLUDED )); then
		logItem "/home/config$NL$(cat $HOME_CONFIG_FILE)"
		writeToConsole $MSG_LEVEL_DETAILED $MSG_INCLUDED_CONFIG "$HOME_CONFIG_FILE"
	fi
	if (( $CURRENTDIR_CONFIG_FILE_INCLUDED )); then
		logItem "./config$NL$(cat $CURRENTDIR_CONFIG_FILE)"
		writeToConsole $MSG_LEVEL_DETAILED $MSG_INCLUDED_CONFIG "$CURRENTDIR_CONFIG_FILE"
	fi

	if (( $UPDATE_MYSELF )); then
		downloadPropertiesFile FORCE
		updateScript
		exitNormal
	else
		downloadPropertiesFile
	fi

	if isVersionDeprecated "$VERSION"; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_SCRIPT_UPDATE_DEPRECATED "$VERSION"
		updateScript "RESTART"
	fi

	doit #	no return for backup
	exit $rc
fi

# vim: set expandtab tabstop=8 shiftwidth=8 autoindent smartindent
