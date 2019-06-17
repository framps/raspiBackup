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
#    Copyright (C) 2013-2019 framp at linux-tips-and-tricks dot de
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

VERSION="0.6.4.3"	# -beta, -hotfix or -dev suffixes possible

# add pathes if not already set (usually not set in crontab)

DEFAULT_PATHES="/usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin"

if [[ -e /bin/grep ]]; then
	pathElements=(${PATH//:/ })
	for p in $DEFAULT_PATHES; do
		if [[ ! " ${pathElements[@]} " =~ " ${p} " ]]; then
			[[ -z $PATH ]] && PATH=$p || PATH="$p:$PATH"
		fi
	done
	export PATH="$PATH"
fi

grep -iq beta <<< "$VERSION"
IS_BETA=$((! $? ))
grep -iq dev <<< "$VERSION"
IS_DEV=$((! $? ))
grep -iq hotfix <<< "$VERSION"
IS_HOTFIX=$((! $? ))

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}

GIT_DATE="$Date: 2019-06-17 20:10:20 +0200$"
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<< $GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<< $GIT_DATE)
GIT_COMMIT="$Sha1: 2d927a2$"
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<< $GIT_COMMIT | sed 's/\$//')

GIT_CODEVERSION="$MYSELF $VERSION, $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"

# some general constants

MYHOMEURL="https://www.linux-tips-and-tricks.de"
DATE=$(date +%Y%m%d-%H%M%S)
HOSTNAME=$(hostname)
NL=$'\n'
CURRENT_DIR=$(pwd)
SCRIPT_DIR=$( cd $( dirname ${BASH_SOURCE[0]}); pwd | xargs readlink -f)

# Smiley used in eMail subject to notify about news/events
SMILEY_WARNING="O.o"
SMILEY_UPDATE_POSSIBLE=";-)"
SMILEY_BETA_AVAILABLE=":-D"
SMILEY_RESTORETEST_REQUIRED="8-)"
SMILEY_VERSION_DEPRECATED=":-("

# URLs and temp filenames used

DOWNLOAD_URL="$MYHOMEURL/downloads/raspibackup-sh/download"
BETA_DOWNLOAD_URL="$MYHOMEURL/downloads/raspibackup-beta-sh/download"
PROPERTY_URL="$MYHOMEURL/downloads/raspibackup0613-properties/download"
LATEST_TEMP_PROPERTY_FILE="/tmp/$MYNAME.properties"
VAR_LIB_DIRECTORY="/var/lib/$MYNAME"
RESTORE_REMINDER_FILE="restore.reminder"
VARS_FILE="/tmp/$MYNAME.vars"
TEMPORARY_MOUNTPOINT_ROOT="/tmp"
DOWNLOAD_TIMEOUT=60 # seconds
DOWNLOAD_RETRIES=3

# debug option constants

LOG_NONE=0
LOG_DEBUG=1
declare -A LOG_LEVELs=( [$LOG_NONE]="Off" [$LOG_DEBUG]="Debug" )
POSSIBLE_LOG_LEVELs=""
for K in "${!LOG_LEVELs[@]}"; do
	POSSIBLE_LOG_LEVELs="$POSSIBLE_LOG_LEVELs | ${LOG_LEVELs[$K]}"
done
POSSIBLE_LOG_LEVELs=$(cut -c 3- <<< $POSSIBLE_LOG_LEVELs)

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
	POSSIBLE_MSG_LEVELs="$POSSIBLE_MSG_LEVELs | ${MSG_LEVELs[$K]}"
done
POSSIBLE_MSG_LEVELs=$(cut -c 3- <<< $POSSIBLE_MSG_LEVELs)

declare -A MSG_LEVEL_ARGs
for K in "${!MSG_LEVELs[@]}"; do
	k=$(tr '[:lower:]' '[:upper:]' <<< "${MSG_LEVELs[$K]}")
	MSG_LEVEL_ARGs[$k]="$K"
done

# log option constants

LOG_FILE_NAME="${MYNAME}.log"
MSG_FILE_NAME="${MYNAME}.msg"
LOG_FILE="$CURRENT_DIR/${LOG_FILE_NAME}"
rm -f "$LOG_FILE" &>/dev/null
MSG_FILE="$CURRENT_DIR/${MSG_FILE_NAME}"
rm -f "$MSG_FILE" &>/dev/null

LOG_OUTPUT_SYSLOG=0
LOG_OUTPUT_VARLOG=1
LOG_OUTPUT_BACKUPLOC=2
LOG_OUTPUT_HOME=3
LOG_OUTPUT_IS_NO_USERDEFINEDFILE_REGEX="[$LOG_OUTPUT_SYSLOG$LOG_OUTPUT_VARLOG$LOG_OUTPUT_BACKUPLOC$LOG_OUTPUT_HOME]"
declare -A LOG_OUTPUT_LOCs=( [$LOG_OUTPUT_SYSLOG]="/var/log/syslog" [$LOG_OUTPUT_VARLOG]="/var/log/raspiBackup/<hostname>.log" [$LOG_OUTPUT_BACKUPLOC]="<backupPath>" [$LOG_OUTPUT_HOME]="~/raspiBackup.log")

declare -A LOG_OUTPUTs=( [$LOG_OUTPUT_SYSLOG]="Syslog" [$LOG_OUTPUT_VARLOG]="Varlog" [$LOG_OUTPUT_BACKUPLOC]="Backup" [$LOG_OUTPUT_HOME]="Current")
declare -A LOG_OUTPUT_ARGs
for K in "${!LOG_OUTPUTs[@]}"; do
	k=$(tr '[:lower:]' '[:upper:]' <<< "${LOG_OUTPUTs[$K]}")
	LOG_OUTPUT_ARGs[$k]="$K"
done

POSSIBLE_LOG_LOCs=""
for K in "${!LOG_OUTPUT_LOCs[@]}"; do
	[[ -z $POSSIBLE_LOG_LOCs ]] && POSSIBLE_LOG_LOCs="${LOG_OUTPUTs[$K]}: ${LOG_OUTPUT_LOCs[$K]}" || POSSIBLE_LOG_LOCs="$POSSIBLE_LOG_LOCs | ${LOG_OUTPUTs[$K]}: ${LOG_OUTPUT_LOCs[$K]}"
done
POSSIBLE_LOG_LOCs="$POSSIBLE_LOG_LOCs | {logFilename}"

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
POSSIBLE_TYPES_ARRAY=()
for K in "${SORTED[@]}"; do
	POSSIBLE_TYPES_ARRAY+=("$K")
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
READY_BACKUP_EXTENSION="ready"
EMAIL_EXTENSION="mail"

EMAIL_EXTENSION_PROGRAM="mailext"
EMAIL_MAILX_PROGRAM="mail"
EMAIL_SSMTP_PROGRAM="ssmtp"
EMAIL_MSMTP_PROGRAM="msmtp"
EMAIL_SENDEMAIL_PROGRAM="sendEmail"
SUPPORTED_EMAIL_PROGRAM_REGEX="^($EMAIL_MAILX_PROGRAM|$EMAIL_SSMTP_PROGRAM|$EMAIL_MSMTP_PROGRAM|$EMAIL_SENDEMAIL_PROGRAM|$EMAIL_EXTENSION_PROGRAM)$"
SUPPORTED_MAIL_PROGRAMS=$(echo $SUPPORTED_EMAIL_PROGRAM_REGEX | sed 's:^..\(.*\)..$:\1:' | sed 's/|/,/g')

PARTITIONS_TO_BACKUP_ALL="*"

NEWS_AVAILABLE=0
BETA_AVAILABLE=0
LOG_INDENT=0

PROPERTY_REGEX='.*="([^"]*)"'
NOOP_AO_ARG_REGEX="^[[:space:]]*:"

STOPPED_SERVICES=0
SHARED_BOOT_DIRECTORY=0

BOOT_TAR_EXT="tmg"
BOOT_DD_EXT="img"

# Commands used by raspiBackup and which have to be available
# [command]=package
declare -A REQUIRED_COMMANDS=( \
		["parted"]="parted" \
		["fsck.vfat"]="dosfstools" \
		["e2label"]="e2fsprogs" \
		["dosfslabel"]="dosfstools" \
		["fdisk"]="util-linux" \
		["blkid"]="util-linux" \
		["sfdisk"]="util-linux" \
		)
# ["btrfs"]="btrfs-tools"

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
#RC_=113
RC_DD_IMG_FAILED=114
RC_SDCARD_ERROR=115
RC_RESTORE_FAILED=116
RC_NATIVE_RESTORE_FAILED=117
RC_DEVICES_NOTFOUND=118
RC_CREATE_ERROR=119
RC_MISSING_COMMANDS=120
RC_NO_BOOT_FOUND=121
RC_BEFORE_START_SERVICES_ERROR=122
RC_BEFORE_STOP_SERVICES_ERROR=123
RC_EMAILPROG_ERROR=124

tty -s
INTERACTIVE=!$?

#################################################################################
# --- Messages in English and German
#################################################################################

# supported languages

MSG_SUPPORTED_REGEX="EN|DE"
MSG_LANG_FALLBACK="EN"

MSG_EN=1      # english	(default)
MSG_DE=1      # german

declare -A MSG_EN
declare -A MSG_DE

MSG_UNDEFINED=0
MSG_EN[$MSG_UNDEFINED]="RBK0000E: Undefined messageid"
MSG_DE[$MSG_UNDEFINED]="RBK0000E: Unbekannte Meldungsid"
MSG_ASSERTION_FAILED=1
MSG_EN[$MSG_ASSERTION_FAILED]="RBK0001E: Unexpected program error occured. (%s), Linenumber: %s, Error: %s."
MSG_DE[$MSG_ASSERTION_FAILED]="RBK0001E: Unerwarteter Programmfehler trat auf. (%s), Zeile: %s, Fehler: %s."
MSG_RUNASROOT=2
MSG_EN[$MSG_RUNASROOT]="RBK0002E: $MYSELF has to be started as root. Try 'sudo %s%s'."
MSG_DE[$MSG_RUNASROOT]="RBK0002E: $MYSELF muss als root gestartet werden. Benutze 'sudo %s%s'."
MSG_TRUNCATING_TO_USED_PARTITIONS_ONLY=3
MSG_EN[$MSG_TRUNCATING_TO_USED_PARTITIONS_ONLY]="RBK0003I: Backup size will be truncated from %s to %s."
MSG_DE[$MSG_TRUNCATING_TO_USED_PARTITIONS_ONLY]="RBK0003I: Backupgröße wird von %s auf %s reduziert."
MSG_ADJUSTING_SECOND=4
MSG_EN[$MSG_ADJUSTING_SECOND]="RBK0004W: Adjusting second partition from %s to %s."
MSG_DE[$MSG_ADJUSTING_SECOND]="RBK0004W: Zweite Partition wird von %s auf %s angepasst."
MSG_BACKUP_FAILED=5
MSG_EN[$MSG_BACKUP_FAILED]="RBK0005E: Backup failed. Check previous error messages for details."
MSG_DE[$MSG_BACKUP_FAILED]="RBK0005E: Backup fehlerhaft beendet. Siehe vorhergehende Fehlermeldungen."
MSG_ADJUSTING_WARNING=6
MSG_EN[$MSG_ADJUSTING_WARNING]="RBK0006W: Target %s with %s is smaller than backup source with %s. root partition will be truncated accordingly. NOTE: Restore may fail if the root partition will become too small."
MSG_DE[$MSG_ADJUSTING_WARNING]="RBK0006W: Ziel %s mit %s ist kleiner als die Backupquelle mit %s. Die root Partition wird entsprechend verkleinert. HINWEIS: Der Restore kann fehlschlagen wenn sie zu klein wird."
MSG_STARTING_SERVICES=7
MSG_EN[$MSG_STARTING_SERVICES]="RBK0007I: Starting services: '%s'."
MSG_DE[$MSG_STARTING_SERVICES]="RBK0007I: Services werden gestartet: '%s'."
MSG_STOPPING_SERVICES=8
MSG_EN[$MSG_STOPPING_SERVICES]="RBK0008I: Stopping services: '%s'."
MSG_DE[$MSG_STOPPING_SERVICES]="RBK0008I: Services werden gestoppt: '%s'."
MSG_STARTED=9
MSG_EN[$MSG_STARTED]="RBK0009I: %s: %s V%s (%s) started at %s."
MSG_DE[$MSG_STARTED]="RBK0009I: %s: %s V%s (%s) %s gestartet."
MSG_STOPPED=10
MSG_EN[$MSG_STOPPED]="RBK0010I: %s: %s V%s (%s) stopped at %s."
MSG_DE[$MSG_STOPPED]="RBK0010I: %s: %s V%s (%s) %s beendet."
MSG_NO_BOOT_PARTITION=11
MSG_EN[$MSG_NO_BOOT_PARTITION]="RBK0011E: No boot partition ${BOOT_PARTITION_PREFIX}1 found."
MSG_DE[$MSG_NO_BOOT_PARTITION]="RBK0011E: Keine boot Partition ${BOOT_PARTITION_PREFIX}1 gefunden."
MSG_DD_BACKUP_NOT_POSSIBLE_FOR_PARTITIONBASED_BACKUP=12
MSG_EN[$MSG_DD_BACKUP_NOT_POSSIBLE_FOR_PARTITIONBASED_BACKUP]="RBK0012E: DD backup not supported for partition based backup. Use normal mode instead."
MSG_DE[$MSG_DD_BACKUP_NOT_POSSIBLE_FOR_PARTITIONBASED_BACKUP]="RBK0012E: DD Backup nicht unterstützt bei partitionsbasiertem Backup. Benutze den normalen Modus dafür."
MSG_MULTIPLE_PARTITIONS_FOUND=13
MSG_EN[$MSG_MULTIPLE_PARTITIONS_FOUND]="RBK0013E: More than two partitions detected which can be saved only with backuptype DD or DDZ or with option -P."
MSG_DE[$MSG_MULTIPLE_PARTITIONS_FOUND]="RBK0013E: Es existieren mehr als zwei Partitionen, die nur mit dem Backuptype DD oder DDZ oder der Option -P gesichert werden können."
MSG_EMAIL_PROG_NOT_SUPPORTED=14
MSG_EN[$MSG_EMAIL_PROG_NOT_SUPPORTED]="RBK0014E: eMail program %s not supported. Supported are %s"
MSG_DE[$MSG_EMAIL_PROG_NOT_SUPPORTED]="RBK0014E: eMail Programm %s ist nicht unterstützt. Möglich sind %s"
MSG_INSTANCE_ACTIVE=15
MSG_EN[$MSG_INSTANCE_ACTIVE]="RBK0015E: There is already an instance of $MYNAME up and running"
MSG_DE[$MSG_INSTANCE_ACTIVE]="RBK0015E: Es ist schon eine Instanz von $MYNAME aktiv."
MSG_NO_SDCARD_FOUND=16
MSG_EN[$MSG_NO_SDCARD_FOUND]="RBK0016E: No sd card %s found."
MSG_DE[$MSG_NO_SDCARD_FOUND]="RBK0016E: Keine SD Karte %s gefunden."
MSG_BACKUP_OK=17
MSG_EN[$MSG_BACKUP_OK]="RBK0017I: Backup finished successfully."
MSG_DE[$MSG_BACKUP_OK]="RBK0017I: Backup erfolgreich beendet."
MSG_ADJUSTING_WARNING2=18
MSG_EN[$MSG_ADJUSTING_WARNING2]="RBK0018W: Target %s with %s is larger than backup source with %s. root partition will be expanded accordingly to use the whole space."
MSG_DE[$MSG_ADJUSTING_WARNING2]="RBK0018W: Ziel %s mit %s ist größer als die Backupquelle mit %s. Die root Partition wird entsprechend vergrößert um den ganzen Platz zu benutzen."
MSG_MISSING_START_STOP=19
MSG_EN[$MSG_MISSING_START_STOP]="RBK0019E: Missing option -a and -o."
MSG_DE[$MSG_MISSING_START_STOP]="RBK0019E: Option -a und -o nicht angegeben."
MSG_FILESYSTEM_INCORRECT=20
MSG_EN[$MSG_FILESYSTEM_INCORRECT]="RBK0020E: Filesystem of rsync backup directory %s seems not to support %s."
MSG_DE[$MSG_FILESYSTEM_INCORRECT]="RBK0020E: Dateisystem des rsync Backupverzeichnisses %s scheint keine %s zu unterstützen."
MSG_BACKUP_PROGRAM_ERROR=21
MSG_EN[$MSG_BACKUP_PROGRAM_ERROR]="RBK0021E: Backupprogram for type %s failed with RC %s."
MSG_DE[$MSG_BACKUP_PROGRAM_ERROR]="RBK0021E: Backupprogramm des Typs %s beendete sich mit RC %s."
MSG_UNKNOWN_BACKUPTYPE=22
MSG_EN[$MSG_UNKNOWN_BACKUPTYPE]="RBK0022E: Unknown backuptype %s."
MSG_DE[$MSG_UNKNOWN_BACKUPTYPE]="RBK0022E: Unbekannter Backtyp %s."
MSG_KEEPBACKUP_INVALID=23
MSG_EN[$MSG_KEEPBACKUP_INVALID]="RBK0023E: Invalid parameter %s for %s detected."
MSG_DE[$MSG_KEEPBACKUP_INVALID]="RBK0023E: Ungültiger Parameter %s für -k eingegeben."
MSG_TOOL_ERROR=24
MSG_EN[$MSG_TOOL_ERROR]="RBK0024E: Backup tool %s received error %s. Errormessages:$NL%s"
MSG_DE[$MSG_TOOL_ERROR]="RBK0024E: Backupprogramm %s hat einen Fehler %s bekommen. Fehlermeldungen:$NL%s"
MSG_DIR_TO_BACKUP_DOESNOTEXIST=25
MSG_EN[$MSG_DIR_TO_BACKUP_DOESNOTEXIST]="RBK0025E: Backupdirectory %s does not exist."
MSG_DE[$MSG_DIR_TO_BACKUP_DOESNOTEXIST]="RBK0025E: Backupverzeichnis %s existiert nicht."
MSG_SAVED_LOG=26
MSG_EN[$MSG_SAVED_LOG]="RBK0026I: Debug logfile saved in %s."
MSG_DE[$MSG_SAVED_LOG]="RBK0026I: Debug Logdatei wurde in %s gesichert."
MSG_NO_DEVICEMOUNTED=27
MSG_EN[$MSG_NO_DEVICEMOUNTED]="RBK0027E: No external device mounted on %s. SD card would be used for backup."
MSG_DE[$MSG_NO_DEVICEMOUNTED]="RBK0027E: Kein externes Gerät an %s verbunden. Die SD Karte würde für das Backup benutzt werden."
MSG_RESTORE_DIRECTORY_NO_DIRECTORY=28
MSG_EN[$MSG_RESTORE_DIRECTORY_NO_DIRECTORY]="RBK0028E: %s is no backup directory of $MYNAME."
MSG_DE[$MSG_RESTORE_DIRECTORY_NO_DIRECTORY]="RBK0028E: %s ist kein Wiederherstellungsverzeichnis von $MYNAME."
MSG_MPACK_NOT_INSTALLED=29
MSG_EN[$MSG_MPACK_NOT_INSTALLED]="RBK0029E: Mail program mpack not installed to send emails. No log can be attached to the eMail."
MSG_DE[$MSG_MPACK_NOT_INSTALLED]="RBK0029E: Mail Program mpack is nicht installiert. Es kann kein Log an die eMail angehängt werden."
MSG_IMG_DD_FAILED=30
MSG_EN[$MSG_IMG_DD_FAILED]="RBK0030E: %s file creation with dd failed with RC %s."
MSG_DE[$MSG_IMG_DD_FAILED]="RBK0030E: %s Datei Erzeugung mit dd endet fehlerhaft mit RC %s."
MSG_CHECKING_FOR_NEW_VERSION=31
MSG_EN[$MSG_CHECKING_FOR_NEW_VERSION]="RBK0031I: Checking whether a new version of $MYSELF is available."
MSG_DE[$MSG_CHECKING_FOR_NEW_VERSION]="RBK0031I: Prüfe ob eine neue Version von $MYSELF verfügbar ist."
MSG_INVALID_LOG_LEVEL=32
MSG_EN[$MSG_INVALID_LOG_LEVEL]="RBK0032W: Invalid parameter '%s' for option -l detected. Using default parameter '%s'."
MSG_DE[$MSG_INVALID_LOG_LEVEL]="RBK0032W: Ungültiger Parameter '%s' für Option -l eingegeben. Es wird Standardparameter '%s' genommen."
MSG_CLEANING_UP=33
MSG_EN[$MSG_CLEANING_UP]="RBK0033I: Please wait until cleanup has finished."
MSG_DE[$MSG_CLEANING_UP]="RBK0032I: Bitte warten bis aufgeräumt wurde."
MSG_FILE_NOT_FOUND=34
MSG_EN[$MSG_FILE_NOT_FOUND]="RBK0034E: File %s not found."
MSG_DE[$MSG_FILE_NOT_FOUND]="RBK0034E: Datei %s nicht gefunden."
MSG_RESTORE_PROGRAM_ERROR=35
MSG_EN[$MSG_RESTORE_PROGRAM_ERROR]="RBK0035E: Backupprogram %s failed during restore with RC %s."
MSG_DE[$MSG_RESTORE_PROGRAM_ERROR]="RBK0035E: Backupprogramm %s endete beim Restore mit RC %s."
MSG_BACKUP_CREATING_PARTITION_INFO=36
MSG_EN[$MSG_BACKUP_CREATING_PARTITION_INFO]="RBK0036I: Saving partition layout."
MSG_DE[$MSG_BACKUP_CREATING_PARTITION_INFO]="RBK0036I: Partitionslayout wird gesichert."
MSG_ANSWER_CHARS_YES=37
MSG_EN[$MSG_ANSWER_CHARS_YES]="Yy"
MSG_DE[$MSG_ANSWER_CHARS_YES]="Jj"
MSG_ANSWER_YES_NO=38
MSG_EN[$MSG_ANSWER_YES_NO]="RBK0038I: Are you sure? %s "
MSG_DE[$MSG_ANSWER_YES_NO]="RBK0038I: Bist Du sicher? %s "
MSG_MAILPROGRAM_NOT_INSTALLED=39
MSG_EN[$MSG_MAILPROGRAM_NOT_INSTALLED]="RBK0039E: Mail program %s not installed to send emails."
MSG_DE[$MSG_MAILPROGRAM_NOT_INSTALLED]="RBK0039E: Mail Program %s ist nicht installiert um eMail zu senden."
MSG_INCOMPATIBLE_UPDATE=40
MSG_EN[$MSG_INCOMPATIBLE_UPDATE]="RBK0040W: New version %s has some incompatibilities to previous versions. Please read %s and use option -S together with option -U to update script."
MSG_DE[$MSG_INCOMPATIBLE_UPDATE]="RBK0040W: Die neue Version %s hat inkompatible Änderungen zu vorhergehenden Versionen. Bitte %s lesen und dann die Option -S zusammen mit -U benutzen um das Script zu updaten."
MSG_TITLE_OK=41
MSG_EN[$MSG_TITLE_OK]="%s: Backup finished successfully."
MSG_DE[$MSG_TITLE_OK]="%s: Backup erfolgreich beendet."
MSG_TITLE_ERROR=42
MSG_EN[$MSG_TITLE_ERROR]="%s: Backup failed !!!."
MSG_DE[$MSG_TITLE_ERROR]="%s: Backup nicht erfolgreich !!!."
MSG_REMOVING_BACKUP=43
MSG_EN[$MSG_REMOVING_BACKUP]="RBK0043I: Removing incomplete backup in %s. This will take some time. Please be patient."
MSG_DE[$MSG_REMOVING_BACKUP]="RBK0043I: Unvollständiges Backup %s in wird gelöscht. Das wird etwas dauern. Bitte Geduld."
MSG_CREATING_BOOT_BACKUP=44
MSG_EN[$MSG_CREATING_BOOT_BACKUP]="RBK0044I: Creating backup of boot partition in %s."
MSG_DE[$MSG_CREATING_BOOT_BACKUP]="RBK0044I: Backup der Bootpartition wird in %s erstellt."
MSG_CREATING_PARTITION_BACKUP=45
MSG_EN[$MSG_CREATING_PARTITION_BACKUP]="RBK0045I: Creating backup of partition layout in %s."
MSG_DE[$MSG_CREATING_PARTITION_BACKUP]="RBK0044I: Backup des Partitionlayouts wird in %s erstellt."
MSG_CREATING_MBR_BACKUP=46
MSG_EN[$MSG_CREATING_MBR_BACKUP]="RBK0046I: Creating backup of master boot record in %s."
MSG_DE[$MSG_CREATING_MBR_BACKUP]="RBK0046I: Backup des Masterbootrecords wird in %s erstellt."
MSG_START_SERVICES_FAILED=47
MSG_EN[$MSG_START_SERVICES_FAILED]="RBK0047W: Error occured when starting services. RC %s."
MSG_DE[$MSG_START_SERVICES_FAILED]="RBK0047W: Ein Fehler trat beim Starten von Services auf. RC %s."
MSG_STOP_SERVICES_FAILED=48
MSG_EN[$MSG_STOP_SERVICES_FAILED]="RBK0048E: Error occured when stopping services. RC %s."
MSG_DE[$MSG_STOP_SERVICES_FAILED]="RBK0048E: Ein Fehler trat beim Beenden von Services auf. RC %s."
MSG_SAVED_MSG=49
MSG_EN[$MSG_SAVED_MSG]="RBK0049I: Messages saved in %s."
MSG_DE[$MSG_SAVED_MSG]="RBK0049I: Meldungen wurden in %s gesichert."
MSG_RESTORING_FILE=50
MSG_EN[$MSG_RESTORING_FILE]="RBK0050I: Restoring backup from %s."
MSG_DE[$MSG_RESTORING_FILE]="RBK0050I: Backup wird von %s zurückgespielt."
MSG_RESTORING_MBR=51
MSG_EN[$MSG_RESTORING_MBR]="RBK0051I: Restoring mbr from %s to %s."
MSG_DE[$MSG_RESTORING_MBR]="RBK0051I: Master boot backup wird von %s auf %s zurückgespielt."
MSG_CREATING_PARTITIONS=52
MSG_EN[$MSG_CREATING_PARTITIONS]="RBK0052I: Creating partition(s) on %s."
MSG_DE[$MSG_CREATING_PARTITIONS]="RBK0052I: Partition(en) werden auf %s erstellt."
MSG_RESTORING_FIRST_PARTITION=53
MSG_EN[$MSG_RESTORING_FIRST_PARTITION]="RBK0053I: Restoring first partition (boot partition) to %s."
MSG_DE[$MSG_RESTORING_FIRST_PARTITION]="RBK0053I: Erste Partition (Bootpartition) wird auf %s zurückgespielt."
MSG_FORMATTING_SECOND_PARTITION=54
MSG_EN[$MSG_FORMATTING_SECOND_PARTITION]="RBK0054I: Formating second partition (root partition) %s."
MSG_DE[$MSG_FORMATTING_SECOND_PARTITION]="RBK0054I: Zweite Partition (Rootpartition) %s wird formatiert."
MSG_RESTORING_SECOND_PARTITION=55
MSG_EN[$MSG_RESTORING_SECOND_PARTITION]="RBK0055I: Restoring second partition (root partition) to %s."
MSG_DE[$MSG_RESTORING_SECOND_PARTITION]="RBK0055I: Zweite Partition (Rootpartition) wird auf %s zurückgespielt."
MSG_DEPLOYMENT_PARMS_ERROR=56
MSG_EN[$MSG_DEPLOYMENT_PARMS_ERROR]="RBK0056E: Incorrect deployment parameters. Use <hostname>@<username>."
MSG_DE[$MSG_DEPLOYMENT_PARMS_ERROR]="RBK0056E: Ungültige Deploymentparameter. Erforderliches Format: <hostname>@<username>."
MSG_DOWNLOADING=57
MSG_EN[$MSG_DOWNLOADING]="RBK0057I: Downloading file %s from %s."
MSG_DE[$MSG_DOWNLOADING]="RBK0057I: Datei %s wird von %s downloaded."
MSG_INVALID_MSG_LEVEL=58
MSG_EN[$MSG_INVALID_MSG_LEVEL]="RBK0058W: Invalid parameter '%s' for option -m detected. Using default parameter '%s'."
MSG_DE[$MSG_INVALID_MSG_LEVEL]="RBK0058W: Ungültiger Parameter '%s' für Option -m eingegeben. Es wird Standardparameter '%s' benutzt."
MSG_INVALID_LOG_OUTPUT=59
MSG_EN[$MSG_INVALID_LOG_OUTPUT]="RBK0059W: Invalid parameter '%s' for option -L detected. Using default parameter '%s'."
MSG_DE[$MSG_INVALID_LOG_OUTPUT]="RBK0059W: Ungültiger Parameter '%s' für Option -L eingegeben. Es wird Standardparameter '%s' benutzt."
MSG_NO_YES=60
MSG_EN[$MSG_NO_YES]="no yes"
MSG_DE[$MSG_NO_YES]="nein ja"
MSG_BOOTPATITIONFILES_NOT_FOUND=61
MSG_EN[$MSG_BOOTPATITIONFILES_NOT_FOUND]="RBK0061E: Unable to find bootpartition files %s starting with %s."
MSG_DE[$MSG_BOOTPATITIONFILES_NOT_FOUND]="RBK0061E: Keine Bootpartitionsdateien in %s gefunden die mit %s beginnen."
MSG_NO_RESTOREDEVICE_DEFINED=62
MSG_EN[$MSG_NO_RESTOREDEVICE_DEFINED]="RBK0062E: No restoredevice defined (Example: /dev/sda)."
MSG_DE[$MSG_NO_RESTOREDEVICE_DEFINED]="RBK0062E: Kein Zurückspielgerät ist definiert (Beispiel: /dev/sda)."
MSG_NO_RESTOREDEVICE_FOUND=63
MSG_EN[$MSG_NO_RESTOREDEVICE_FOUND]="RBK0063E: Restoredevice %s not found (Example: /dev/sda)."
MSG_DE[$MSG_NO_RESTOREDEVICE_FOUND]="RBK0063E: Zurückspielgerät %s existiert nicht (Beispiel: /dev/sda)."
MSG_ROOT_PARTTITION_NOT_FOUND=64
MSG_EN[$MSG_ROOT_PARTTITION_NOT_FOUND]="RBK0064E: Partition for rootpartition %s not found (Example: /dev/sdb1)."
MSG_DE[$MSG_ROOT_PARTTITION_NOT_FOUND]="RBK0064E: Partition für die Rootpartition %s nicht gefunden (Beispiel: /dev/sda)."
MSG_REPARTITION_WARNING=65
MSG_EN[$MSG_REPARTITION_WARNING]="RBK0065W: Device %s will be repartitioned and all data will be lost."
MSG_DE[$MSG_REPARTITION_WARNING]="RBK0065W: Gerät %s wird repartitioniert und die gesamten Daten werden gelöscht."
MSG_WARN_RESTORE_DEVICE_OVERWRITTEN=66
MSG_EN[$MSG_WARN_RESTORE_DEVICE_OVERWRITTEN]="RBK0066W: Device %s will be overwritten with the saved boot and root partition."
MSG_DE[$MSG_WARN_RESTORE_DEVICE_OVERWRITTEN]="RBK0066W: Gerät %s wird überschrieben mit der gesicherten Boot- und Rootpartition."
MSG_CURRENT_PARTITION_TABLE=67
MSG_EN[$MSG_CURRENT_PARTITION_TABLE]="RBK0067I: Current partitions on %s:$NL%s"
MSG_DE[$MSG_CURRENT_PARTITION_TABLE]="RBK0067I: Momentane Partitionen auf %s:$NL%s"
MSG_BOOTPATITIONFILES_FOUND=68
MSG_EN[$MSG_BOOTPATITIONFILES_FOUND]="RBK0068I: Using bootpartition backup files starting with %s from directory %s."
MSG_DE[$MSG_BOOTPATITIONFILES_FOUND]="RBK0068I: Bootpartitionsdateien des Backups aus dem Verzeichnis %s die mit %s beginnen werden benutzt."
MSG_WARN_BOOT_PARTITION_OVERWRITTEN=69
MSG_EN[$MSG_WARN_BOOT_PARTITION_OVERWRITTEN]="RBK0069W: Bootpartition %s will be formatted and will get the restored Boot partition."
MSG_DE[$MSG_WARN_BOOT_PARTITION_OVERWRITTEN]="RBK0069W: Bootpartition %s wird formatiert und erhält die zurückgespielte Bootpartition."
MSG_WARN_ROOT_PARTITION_OVERWRITTEN=70
MSG_EN[$MSG_WARN_ROOT_PARTITION_OVERWRITTEN]="RBK0070W: Rootpartition %s will be formatted and will get the restored Root partition."
MSG_DE[$MSG_WARN_ROOT_PARTITION_OVERWRITTEN]="RBK0070W: Rootpartition %s wird formatiert und erhält die zurückgespielte Rootpartition."
MSG_QUERY_CHARS_YES_NO=71
MSG_EN[$MSG_QUERY_CHARS_YES_NO]="y/N"
MSG_DE[$MSG_QUERY_CHARS_YES_NO]="j/N"
MSG_SCRIPT_UPDATE_OK=72
MSG_EN[$MSG_SCRIPT_UPDATE_OK]="RBK0072I: %s updated from version %s to version %s. Previous version saved as %s. Don't forget to test backup and restore with the new version now."
MSG_DE[$MSG_SCRIPT_UPDATE_OK]="RBK0072I: %s von Version %s durch die aktuelle Version %s ersetzt. Die vorherige Version wurde als %s gesichert. Nicht vergessen den Backup und Restore mit der neuen Version zu testen."
MSG_SCRIPT_UPDATE_NOT_NEEDED=73
MSG_EN[$MSG_SCRIPT_UPDATE_NOT_NEEDED]="RBK0073I: %s already current with version %s."
MSG_DE[$MSG_SCRIPT_UPDATE_NOT_NEEDED]="RBK0073I: %s bereits auf der aktuellen Version %s."
MSG_SCRIPT_UPDATE_FAILED=74
MSG_EN[$MSG_SCRIPT_UPDATE_FAILED]="RBK0074E: Failed to update %s."
MSG_DE[$MSG_SCRIPT_UPDATE_FAILED]="RBK0074E: %s konnte nicht ersetzt werden."
MSG_LINK_BOOTPARTITIONFILES=75
MSG_EN[$MSG_LINK_BOOTPARTITIONFILES]="RBK0075I: Using hardlinks to reuse bootpartition backups."
MSG_DE[$MSG_LINK_BOOTPARTITIONFILES]="RBK0075I: Hardlinks werden genutzt um Bootpartitionsbackups wiederzuverwenden."
MSG_RESTORE_OK=76
MSG_EN[$MSG_RESTORE_OK]="RBK0076I: Restore finished successfully."
MSG_DE[$MSG_RESTORE_OK]="RBK0076I: Restore erfolgreich beendet."
MSG_RESTORE_FAILED=77
MSG_EN[$MSG_RESTORE_FAILED]="RBK0077E: Restore failed with RC %s. Check previous error messages."
MSG_DE[$MSG_RESTORE_FAILED]="RBK0077E: Restore wurde fehlerhaft mit RC %s beendet. Siehe vorhergehende Fehlermeldungen."
MSG_BACKUP_TIME=78
MSG_EN[$MSG_BACKUP_TIME]="RBK0078I: Backup time: %s:%s:%s."
MSG_DE[$MSG_BACKUP_TIME]="RBK0078I: Backupzeit: %s:%s:%s."
MSG_UNKNOWN_BACKUPTYPE_FOR_ZIP=79
MSG_EN[$MSG_UNKNOWN_BACKUPTYPE_FOR_ZIP]="RBK0079E: Option -z not allowed with backuptype %s."
MSG_DE[$MSG_UNKNOWN_BACKUPTYPE_FOR_ZIP]="RBK0079E: Option -z ist für Backuptyp %s nicht erlaubt."
MSG_NEW_VERSION_AVAILABLE=80
MSG_EN[$MSG_NEW_VERSION_AVAILABLE]="RBK0080I: $SMILEY_UPDATE_POSSIBLE There is a new version %s of $MYNAME available for download. You are running version %s and now can use option -U to upgrade your local version."
MSG_DE[$MSG_NEW_VERSION_AVAILABLE]="RBK0080I: $SMILEY_UPDATE_POSSIBLE Es gibt eine neue Version %s von $MYNAME zum downloaden. Die momentan benutze Version ist %s und es kann mit der Option -U die lokale Version aktualisiert werden."
MSG_BACKUP_TARGET=81
MSG_EN[$MSG_BACKUP_TARGET]="RBK0081I: Creating backup of type %s in %s."
MSG_DE[$MSG_BACKUP_TARGET]="RBK0081I: Backup vom Typ %s wird in %s erstellt."
MSG_EXISTING_BOOT_BACKUP=82
MSG_EN[$MSG_EXISTING_BOOT_BACKUP]="RBK0082I: Backup of boot partition alreday exists in %s."
MSG_DE[$MSG_EXISTING_BOOT_BACKUP]="RBK0082I: Backup der Bootpartition in %s existiert schon."
MSG_EXISTING_PARTITION_BACKUP=83
MSG_EN[$MSG_EXISTING_PARTITION_BACKUP]="RBK0083I: Backup of partition layout already exists in %s."
MSG_DE[$MSG_EXISTING_PARTITION_BACKUP]="RBK0083I: Backup des Partitionlayouts in %s existiert schon."
MSG_EXISTING_MBR_BACKUP=84
MSG_EN[$MSG_EXISTING_MBR_BACKUP]="RBK0084I: Backup of master boot record already exists in %s."
MSG_DE[$MSG_EXISTING_MBR_BACKUP]="RBK0084I: Backup des Masterbootrecords in %s existiert schon."
MSG_BACKUP_STARTED=85
MSG_EN[$MSG_BACKUP_STARTED]="RBK0085I: Backup of type %s started. Please be patient."
MSG_DE[$MSG_BACKUP_STARTED]="RBK0085I: Backuperstellung vom Typ %s gestartet. Bitte Geduld."
MSG_RESTOREDEVICE_IS_PARTITION=86
MSG_EN[$MSG_RESTOREDEVICE_IS_PARTITION]="RBK0086E: Restore device cannot be a partition."
MSG_DE[$MSG_RESTOREDEVICE_IS_PARTITION]="RBK0086E: Wiederherstellungsgerät darf keine Partition sein."
MSG_RESTORE_DIRECTORY_INVALID=87
MSG_EN[$MSG_RESTORE_DIRECTORY_INVALID]="RBK0087E: Restore directory %s was not created by $MYNAME."
MSG_DE[$MSG_RESTORE_DIRECTORY_INVALID]="RBK0087E: Wiederherstellungsverzeichnis %s wurde nicht von $MYNAME erstellt."
MSG_RESTORE_DEVICE_NOT_VALID=88
MSG_EN[$MSG_RESTORE_DEVICE_NOT_VALID]="RBK0088E: -R option not supported for partitionbased backup."
MSG_DE[$MSG_RESTORE_DEVICE_NOT_VALID]="RBK0088E: Option -R wird nicht beim partitionbasierten Backup unterstützt."
MSG_UNKNOWN_OPTION=89
MSG_EN[$MSG_UNKNOWN_OPTION]="RBK0089E: Unknown option %s."
MSG_DE[$MSG_UNKNOWN_OPTION]="RBK0089E: Unbekannte Option %s."
MSG_OPTION_REQUIRES_PARAMETER=90
MSG_EN[$MSG_OPTION_REQUIRES_PARAMETER]="RBK0090E: Option %s requires a parameter. If parameter starts with '-' start with '\-' instead."
MSG_DE[$MSG_OPTION_REQUIRES_PARAMETER]="RBK0090E: Option %s erwartet einen Parameter. Falls der Parameter mit '-' beginnt beginne stattdessen mit '\-'."
MSG_MENTION_HELP=91
MSG_EN[$MSG_MENTION_HELP]="RBK0091I: Invoke '%s -h' to get more detailed information of all script invocation parameters."
MSG_DE[$MSG_MENTION_HELP]="RBK0091I: '%s -h' liefert eine detailierte Beschreibung aller Scriptaufrufoptionen."
MSG_PROCESSING_PARTITION=92
MSG_EN[$MSG_PROCESSING_PARTITION]="RBK0092I: Saving partition %s (%s) ..."
MSG_DE[$MSG_PROCESSING_PARTITION]="RBK0092I: Partition %s (%s) wird gesichert ..."
MSG_PARTITION_NOT_FOUND=93
MSG_EN[$MSG_PARTITION_NOT_FOUND]="RBK0093E: Partition %s specified with option -T not found."
MSG_DE[$MSG_PARTITION_NOT_FOUND]="RBK0093E: Angegebene Partition %s der Option -T existiert nicht."
MSG_PARTITION_NUMBER_INVALID=94
MSG_EN[$MSG_PARTITION_NUMBER_INVALID]="RBK0094E: Parameter '%s' specified in option -T is not a number."
MSG_DE[$MSG_PARTITION_NUMBER_INVALID]="RBK0094E: Angegebener Parameter '%s' der Option -T ist keine Zahl."
MSG_RESTORING_PARTITIONFILE=95
MSG_EN[$MSG_RESTORING_PARTITIONFILE]="RBK0095I: Restoring partition %s."
MSG_DE[$MSG_RESTORING_PARTITIONFILE]="RBK0095I: Backup wird auf Partition %s zurückgespielt."
MSG_LANGUAGE_NOT_SUPPORTED=96
MSG_EN[$MSG_LANGUAGE_NOT_SUPPORTED]="RBK0096E: Language %s not supported."
MSG_DE[$MSG_LANGUAGE_NOT_SUPPORTED]="RBK0096E: Die Sprache %s wird nicht unterstützt."
MSG_PARTITIONING_SDCARD=97
MSG_EN[$MSG_PARTITIONING_SDCARD]="RBK0097I: Partitioning and formating %s."
MSG_DE[$MSG_PARTITIONING_SDCARD]="RBK0097I: Partitioniere und formatiere %s."
MSG_FORMATTING=98
MSG_EN[$MSG_FORMATTING]="RBK0098I: Formatting partition %s with %s (%s)."
MSG_DE[$MSG_FORMATTING]="RBK0098I: Formatiere Partition %s mit %s (%s)."
MSG_RESTORING_FILE_PARTITION_DONE=99
MSG_EN[$MSG_RESTORING_FILE_PARTITION_DONE]="RBK0099I: Restore of partition %s finished."
MSG_DE[$MSG_RESTORING_FILE_PARTITION_DONE]="RBK0099I: Zurückspielen des Backups auf Partition %s beendet."
MSG_WARN_RESTORE_PARTITION_DEVICE_OVERWRITTEN=100
MSG_EN[$MSG_WARN_RESTORE_PARTITION_DEVICE_OVERWRITTEN]="RBK0100W: Device %s will be overwritten with the backup."
MSG_DE[$MSG_WARN_RESTORE_PARTITION_DEVICE_OVERWRITTEN]="RBK0100W: Gerät %s wird mit dem Backup beschrieben."
MSG_VERSION_HISTORY_PAGE=101
MSG_EN[$MSG_VERSION_HISTORY_PAGE]="$MYHOMEURL/en/versionhistory/"
MSG_DE[$MSG_VERSION_HISTORY_PAGE]="$MYHOMEURL/de/versionshistorie/"
MSG_UPDATING_CMDLINE=102
MSG_EN[$MSG_UPDATING_CMDLINE]="RBK0102I: Detected PARTUUID usage in /boot/cmdline.txt. Changing PARTUUID from %s to %s."
MSG_DE[$MSG_UPDATING_CMDLINE]="RBK0102I: Benutzung von PARTUUID in /boot/cmdline.txt erkannt. PARTUUID %s wird auf %s geändert."
MSG_UNABLE_TO_WRITE=103
MSG_EN[$MSG_UNABLE_TO_WRITE]="RBK0103E: Unable to create backup on %s because of missing write permission."
MSG_DE[$MSG_UNABLE_TO_WRITE]="RBK0103E: Ein Backup kann nicht auf %s erstellt werden da die Schreibberechtigung fehlt."
MSG_LABELING=104
MSG_EN[$MSG_LABELING]="RBK0104I: Labeling partition %s with label %s."
MSG_DE[$MSG_LABELING]="RBK0104I: Partition %s erhält das Label %s."
MSG_REMOVING_BACKUP_FAILED=105
MSG_EN[$MSG_REMOVING_BACKUP_FAILED]="RBK0105E: Removing incomplete backup in %s failed with RC %s. Directory has to be cleaned up manually."
MSG_DE[$MSG_REMOVING_BACKUP_FAILED]="RBK0105E: Löschen des unvollständigen Backups in %s schlug fehl mit RC: %s. Das Verzeichnis muss manuell gelöscht werden."
MSG_DEPLOYMENT_FAILED=106
MSG_EN[$MSG_DEPLOYMENT_FAILED]="RBK0106E: Installation of $MYNAME failed on server %s for user %s."
MSG_DE[$MSG_DEPLOYMENT_FAILED]="RBK0106E: Installation von $MYNAME auf Server %s für Benutzer %s fehlgeschlagen."
MSG_EXTENSION_FAILED=107
MSG_EN[$MSG_EXTENSION_FAILED]="RBK0107E: Extension %s failed with RC %s."
MSG_DE[$MSG_EXTENSION_FAILED]="RBK0107E: Erweiterung %s fehlerhaft beendet mit RC %s."
MSG_SKIPPING_UNFORMATTED_PARTITION=108
MSG_EN[$MSG_SKIPPING_UNFORMATTED_PARTITION]="RBK0108W: Unformatted partition %s (%s) not saved."
MSG_DE[$MSG_SKIPPING_UNFORMATTED_PARTITION]="RBK0108W: Unformatierte Partition %s (%s) wird nicht gesichert."
MSG_UNSUPPORTED_FILESYSTEM_FORMAT=109
MSG_EN[$MSG_UNSUPPORTED_FILESYSTEM_FORMAT]="RBK0109E: Unsupported filesystem %s detected on partition %s."
MSG_DE[$MSG_UNSUPPORTED_FILESYSTEM_FORMAT]="RBK0109E: Nicht unterstütztes Filesystem %s auf Partition %s."
MSG_UNABLE_TO_COLLECT_PARTITIONINFO=110
MSG_EN[$MSG_UNABLE_TO_COLLECT_PARTITIONINFO]="RBK0110E: Unable to collect partition data with %s. RC %s."
MSG_DE[$MSG_UNABLE_TO_COLLECT_PARTITIONINFO]="RBK0110E: Partitionsdaten können nicht mit %s gesammelt werden. RC %s."
MSG_UNABLE_TO_CREATE_PARTITIONS=111
MSG_EN[$MSG_UNABLE_TO_CREATE_PARTITIONS]="RBK0111E: Error occured when partitions were created. RC %s${NL}%s."
MSG_DE[$MSG_UNABLE_TO_CREATE_PARTITIONS]="RBK0111E: Fehler beim Erstellen der Partitionen. RC %s ${NL}%s."
MSG_PROCESSED_PARTITION=112
MSG_EN[$MSG_PROCESSED_PARTITION]="RBK0112I: Partition %s was saved."
MSG_DE[$MSG_PROCESSED_PARTITION]="RBK0112I: Partition %s wurde gesichert."
MSG_YES_NO_DEVICE_MISMATCH=113
MSG_EN[$MSG_YES_NO_DEVICE_MISMATCH]="RBK0113E: Restore device %s doesn't match %s."
MSG_DE[$MSG_YES_NO_DEVICE_MISMATCH]="RBK0113E: Wiederherstellungsgerät %s ähnelt nicht %s."
MSG_VISIT_VERSION_HISTORY_PAGE=114
MSG_EN[$MSG_VISIT_VERSION_HISTORY_PAGE]="RBK0114I: Visit %s to read about the changes in the new version."
MSG_DE[$MSG_VISIT_VERSION_HISTORY_PAGE]="RBK0114I: Besuche %s um die Änderungen in der neuen Version kennenzulernen."
MSG_DEPLOYED_HOST=115
MSG_EN[$MSG_DEPLOYED_HOST]="RBK0115I: $MYNAME $VERSION installed on host %s for user %s."
MSG_DE[$MSG_DEPLOYED_HOST]="RBK0115I: $MYNAME $VERSION wurde auf Server %s für Benutzer %s installiert."
MSG_INCLUDED_CONFIG=116
MSG_EN[$MSG_INCLUDED_CONFIG]="RBK0116I: Using config file %s."
MSG_DE[$MSG_INCLUDED_CONFIG]="RBK0116I: Konfigurationsdatei %s wird benutzt."
MSG_CURRENT_SCRIPT_VERSION=117
MSG_EN[$MSG_CURRENT_SCRIPT_VERSION]="RBK0117I: Current script version: %s"
MSG_DE[$MSG_CURRENT_SCRIPT_VERSION]="RBK0117I: Aktuelle Scriptversion: %s"
MSG_AVAILABLE_VERSIONS_HEADER=118
MSG_EN[$MSG_AVAILABLE_VERSIONS_HEADER]="RBK0118I: Available versions:"
MSG_DE[$MSG_AVAILABLE_VERSIONS_HEADER]="RBK0118I: Verfügbare Scriptversionen:"
MSG_AVAILABLE_VERSIONS=119
MSG_EN[$MSG_AVAILABLE_VERSIONS]="RBK0119I: %s: %s"
MSG_DE[$MSG_AVAILABLE_VERSIONS]="RBK0119I: %s: %s"
MSG_SAVING_ACTUAL_VERSION=120
MSG_EN[$MSG_SAVING_ACTUAL_VERSION]="RBK0120I: Saving current version %s to %s."
MSG_DE[$MSG_SAVING_ACTUAL_VERSION]="RBK0120I: Aktuelle Version %s wird in %s gesichert."
MSG_RESTORING_PREVIOUS_VERSION=121
MSG_EN[$MSG_RESTORING_PREVIOUS_VERSION]="RBK0121I: Restoring previous version %s to %s."
MSG_DE[$MSG_RESTORING_PREVIOUS_VERSION]="RBK0121I: Vorherige Version %s wird in %s wiederhergestellt."
MSG_SELECT_VERSION=122
MSG_EN[$MSG_SELECT_VERSION]="RBK0122I: Select version to restore (%s-%s)"
MSG_DE[$MSG_SELECT_VERSION]="RBK0122I: Auswahl der Version die wiederhergestellt werden soll (%s-%s)"
MSG_NO_PREVIOUS_VERSIONS_AVAILABLE=123
MSG_EN[$MSG_NO_PREVIOUS_VERSIONS_AVAILABLE]="RBK0123E: No version to restore available."
MSG_DE[$MSG_NO_PREVIOUS_VERSIONS_AVAILABLE]="RBK0123E: Keine Version zum Restore verfügbar."
MSG_FAKE_MODE_ON=124
MSG_EN[$MSG_FAKE_MODE_ON]="RBK0124W: Fake mode on."
MSG_DE[$MSG_FAKE_MODE_ON]="RBK0124W: Simulationsmodus an."
MSG_UNUSED_PARAMETERS=125
MSG_EN[$MSG_UNUSED_PARAMETERS]="RBK0125W: Unused option(s) \"%s\" detected. There may be quotes missing in option arguments."
MSG_DE[$MSG_UNUSED_PARAMETERS]="RBK0125W: Unbenutzte Option(en) \" %s\" entdeckt. Es scheinen Anführungszeichen bei Optionsargumenten zu fehlen."
MSG_REPLACING_FILE_BY_HARDLINK=126
MSG_EN[$MSG_REPLACING_FILE_BY_HARDLINK]="RBK0126I: Replacing %s with hardlink to %s."
MSG_DE[$MSG_REPLACING_FILE_BY_HARDLINK]="RBK0126I: Datei %s wird durch einem Hardlink auf %s ersetzt."
MSG_DEPLOYING_HOST_OFFLINE=127
MSG_EN[$MSG_DEPLOYING_HOST_OFFLINE]="RBK0127E: Server %s offline."
MSG_DE[$MSG_DEPLOYING_HOST_OFFLINE]="RBK0127E: Server %s ist nicht erreichbar."
MSG_USING_LOGFILE=128
MSG_EN[$MSG_USING_LOGFILE]="RBK0128I: Using logfile %s."
MSG_DE[$MSG_USING_LOGFILE]="RBK0128I: Logdatei ist %s."
MSG_EMAIL_EXTENSION_NOT_FOUND=129
MSG_EN[$MSG_EMAIL_EXTENSION_NOT_FOUND]="RBK0129E: email extension %s not found."
MSG_DE[$MSG_EMAIL_EXTENSION_NOT_FOUND]="RBK0129E: Email Erweiterung %s nicht gefunden."
MSG_MISSING_FILEPARAMETER=130
MSG_EN[$MSG_MISSING_FILEPARAMETER]="RBK0130E: Missing backup- or restorepath parameter."
MSG_DE[$MSG_MISSING_FILEPARAMETER]="RBK0130E: Backup- oder Restorepfadparameter fehlt."
MSG_MISSING_INSTALLED_FILE=131
MSG_EN[$MSG_MISSING_INSTALLED_FILE]="RBK0131E: Program %s not found. Use 'sudo apt-get update; sudo apt-get install %s' to install the missing program."
MSG_DE[$MSG_MISSING_INSTALLED_FILE]="RBK0131E: Programm %s nicht gefunden. Mit 'sudo apt-get update; sudo apt-get install %s' wird das fehlende Programm installiert."
MSG_UPDATING_FSTAB=132
MSG_EN[$MSG_UPDATING_FSTAB]="RBK0132I: Detected PARTUUID usage in /etc/fstab. Changing PARTUUID from %s to %s."
MSG_DE[$MSG_UPDATING_FSTAB]="RBK0132I: Benutzung von PARTUUID in /etc/fstab erkannt. PARTUUID %s wird auf %s geändert."
MSG_HARDLINK_DIRECTORY_USED=133
MSG_EN[$MSG_HARDLINK_DIRECTORY_USED]="RBK0133I: Using directory %s for hardlinks."
MSG_DE[$MSG_HARDLINK_DIRECTORY_USED]="RBK0133I: Verzeichnis %s wird für Hardlinks benutzt."
MSG_UNABLE_TO_USE_HARDLINKS=134
MSG_EN[$MSG_UNABLE_TO_USE_HARDLINKS]="RBK0134E: Unable to use hardlinks on %s for bootpartition files. RC %s."
MSG_DE[$MSG_UNABLE_TO_USE_HARDLINKS]="RBK0134E: Hardlinkslinks können nicht auf %s für Bootpartitionsdateien benutzt werden. RC %s."
MSG_SCRIPT_IS_DEPRECATED=135
MSG_EN[$MSG_SCRIPT_IS_DEPRECATED]="RBK0135W: ==> Current script version %s has a severe bug and should be updated immediately <==="
MSG_DE[$MSG_SCRIPT_IS_DEPRECATED]="RBK0135W: ==> Aktuelle Scriptversion %s enthält einen gravierenden Fehler und sollte sofort aktualisiert werden <==="
MSG_MISSING_START_OR_STOP=136
MSG_EN[$MSG_MISSING_START_OR_STOP]="RBK0136E: Missing mandatory option %s."
MSG_DE[$MSG_MISSING_START_OR_STOP]="RBK0136E: Es fehlt die obligatorische Option %s."
MSG_NO_ROOTBACKUPFILE_FOUND=137
MSG_EN[$MSG_NO_ROOTBACKUPFILE_FOUND]="RBK0137E: Rootbackupfile for type %s not found."
MSG_DE[$MSG_NO_ROOTBACKUPFILE_FOUND]="RBK0137E: Rootbackupdatei für den Typ %s nicht gefunden."
MSG_USING_ROOTBACKUPFILE=138
MSG_EN[$MSG_USING_ROOTBACKUPFILE]="RBK0138I: Using bootbackup %s."
MSG_DE[$MSG_USING_ROOTBACKUPFILE]="RBK0138I: Bootbackup %s wird benutzt."
MSG_FORCING_CREATING_PARTITIONS=139
MSG_EN[$MSG_FORCING_CREATING_PARTITIONS]="RBK0139W: Partition creation ignores errors."
MSG_DE[$MSG_FORCING_CREATING_PARTITIONS]="RBK0139W: Partitionserstellung ignoriert Fehler."
MSG_LABELS_NOT_SUPPORTED=140
MSG_EN[$MSG_LABELS_NOT_SUPPORTED]="RBK0140E: LABEL definitions in /etc/fstab not supported. Use PARTUUID instead."
MSG_DE[$MSG_LABELS_NOT_SUPPORTED]="RBK0140E: LABEL Definitionen sind in /etc/fstab nicht unterstützt. Benutze stattdessen PARTUUID."
MSG_SAVING_USED_PARTITIONS_ONLY=141
MSG_EN[$MSG_SAVING_USED_PARTITIONS_ONLY]="RBK0141I: Saving space of defined partitions only."
MSG_DE[$MSG_SAVING_USED_PARTITIONS_ONLY]="RBK0141I: Nur der von den definierten Partitionen belegte Speicherplatz wird gesichert."
MSG_NO_BOOTDEVICE_FOUND=142
MSG_EN[$MSG_NO_BOOTDEVICE_FOUND]="RBK0142E: Unable to detect boot device. Please report this issue on https://github.com/framps/raspiBackup/issues or https://www.linux-tips-and-tricks.de/en/rmessages"
MSG_DE[$MSG_NO_BOOTDEVICE_FOUND]="RBK0142E: Bootgerät kann nicht erkannt werden. Bitte das Problem auf https://github.com/framps/raspiBackup/issues oder auf https://www.linux-tips-and-tricks.de/de/fehlermeldungen melden."
MSG_FORCE_SFDISK=143
MSG_EN[$MSG_FORCE_SFDISK]="RBK0143W: Target %s does not match with backup. Partitioning forced."
MSG_DE[$MSG_FORCE_SFDISK]="RBK0143W: Ziel %s passt nicht zu dem Backup. Partitionierung wird trotzdem vorgenommen."
MSG_SKIP_SFDISK=144
MSG_EN[$MSG_SKIP_SFDISK]="RBK0144W: Target %s will not be partitioned. Using existing partitions."
MSG_DE[$MSG_SKIP_SFDISK]="RBK0144W: Ziel %s wird nicht partitioniert. Existierende Partitionen werden benutzt."
MSG_SKIP_CREATING_PARTITIONS=145
MSG_EN[$MSG_SKIP_CREATING_PARTITIONS]="RBK0145W: Partition creation skipped. Using existing partitions."
MSG_DE[$MSG_SKIP_CREATING_PARTITIONS]="RBK0145W: Partitionen werden nicht erstellt. Existierende Paritionen werden benutzt."
MSG_NO_PARTITION_TABLE_DEFINED=146
MSG_EN[$MSG_NO_PARTITION_TABLE_DEFINED]="RBK0146I: No partitiontable found on %s."
MSG_DE[$MSG_NO_PARTITION_TABLE_DEFINED]="RBK0146I: Keine Partitionstabelle auf %s gefunden."
MSG_BACKUP_PARTITION_FAILED=147
MSG_EN[$MSG_BACKUP_PARTITION_FAILED]="RBK0147E: Backup of partition %s failed with RC %s."
MSG_DE[$MSG_BACKUP_PARTITION_FAILED]="RBK0147E: Sicherung der Partition %s schlug fehl mit RC %s."
MSG_STACK_TRACE=148
MSG_EN[$MSG_STACK_TRACE]="RBK0148E: @@@@@@@@@@@@@@@@@@@@ Stacktrace @@@@@@@@@@@@@@@@@@@@"
MSG_DE[$MSG_STACK_TRACE]="RBK0148E: @@@@@@@@@@@@@@@@@@@@ Stacktrace @@@@@@@@@@@@@@@@@@@@"
MSG_FILE_ARG_NOT_FOUND=149
MSG_EN[$MSG_FILE_ARG_NOT_FOUND]="RBK0149E: %s not found."
MSG_DE[$MSG_FILE_ARG_NOT_FOUND]="RBK0149E: %s nicht gefunden."
MSG_MAX_4GB_LIMIT=150
MSG_EN[$MSG_MAX_4GB_LIMIT]="RBK0150W: Maximum file size in backup directory %s is limited to 4GB."
MSG_DE[$MSG_MAX_4GB_LIMIT]="RBK0150W: Maximale Dateigröße im Backupverzeichnis %s ist auf 4GB begrenzt."
MSG_USING_BACKUPPATH=151
MSG_EN[$MSG_USING_BACKUPPATH]="RBK0151I: Using backuppath %s."
MSG_DE[$MSG_USING_BACKUPPATH]="RBK0151I: Backuppfad %s wird benutzt."
MSG_MKFS_FAILED=152
MSG_EN[$MSG_MKFS_FAILED]="RBK0152E: Unable to create filesystem: '%s' - RC: %s."
MSG_DE[$MSG_MKFS_FAILED]="RBK0152E: Dateisystem kann nicht erstellt werden: '%s' - RC: %s."
MSG_LABELING_FAILED=153
MSG_EN[$MSG_LABELING_FAILED]="RBK0153E: Unable to label partition: '%s' - RC: %s."
MSG_DE[$MSG_LABELING_FAILED]="RBK0153E: Partition kann nicht mit einem Label versehen werden: '%s' - RC: %s."
MSG_RESTORE_DEVICE_MOUNTED=154
MSG_EN[$MSG_RESTORE_DEVICE_MOUNTED]="RBK0154E: Restore is not possible when a partition of device %s is mounted."
MSG_DE[$MSG_RESTORE_DEVICE_MOUNTED]="RBK0154E: Ein Restore ist nicht möglich wenn eine Partition von %s gemounted ist."
MSG_INVALID_RESTORE_ROOT_PARTITION=155
MSG_EN[$MSG_INVALID_RESTORE_ROOT_PARTITION]="RBK0155E: Restore root partition %s is no partition."
MSG_DE[$MSG_INVALID_RESTORE_ROOT_PARTITION]="RBK0155E: Ziel Rootpartition %s ist keine Partition."
MSG_SKIP_STARTING_SERVICES=156
MSG_EN[$MSG_SKIP_STARTING_SERVICES]="RBK0156W: No services to start."
MSG_DE[$MSG_SKIP_STARTING_SERVICES]="RBK0156W: Keine Systemd Services sind zu starten."
MSG_SKIP_STOPPING_SERVICES=157
MSG_EN[$MSG_SKIP_STOPPING_SERVICES]="RBK0157W: No services to stop."
MSG_DE[$MSG_SKIP_STOPPING_SERVICES]="RBK0157W: Keine Systemd Services sind zu stoppen."
MSG_MAIN_BACKUP_PROGRESSING=158
MSG_EN[$MSG_MAIN_BACKUP_PROGRESSING]="RBK0158I: Creating native %s backup %s."
MSG_DE[$MSG_MAIN_BACKUP_PROGRESSING]="RBK0158I: %s Backup %s wird erstellt."
MSG_BACKUPS_KEPT=159
MSG_EN[$MSG_BACKUPS_KEPT]="RBK0159I: %s backups kept for %s backup type."
MSG_DE[$MSG_BACKUPS_KEPT]="RBK0159I: %s Backups werden für den Backuptyp %s aufbewahrt."
MSG_TARGETSD_SIZE_TOO_SMALL=160
MSG_EN[$MSG_TARGETSD_SIZE_TOO_SMALL]="RBK0160E: Target %s with %s is smaller than backup source with %s."
MSG_DE[$MSG_TARGETSD_SIZE_TOO_SMALL]="RBK0160E: Ziel %s mit %s ist kleiner als die Backupquelle mit %s."
MSG_TARGETSD_SIZE_BIGGER=161
MSG_EN[$MSG_TARGETSD_SIZE_BIGGER]="RBK0161W: Target %s with %s is larger than backup source with %s. You waste %s."
MSG_DE[$MSG_TARGETSD_SIZE_BIGGER]="RBK0161W: Ziel %s mit %s ist größer als die Backupquelle mit %s. %s sind ungenutzt."
MSG_RESTORE_ABORTED=162
MSG_EN[$MSG_RESTORE_ABORTED]="RBK0162I: Restore aborted."
MSG_DE[$MSG_RESTORE_ABORTED]="RBK0162I: Restore abgebrochen."
MSG_CTRLC_DETECTED=163
MSG_EN[$MSG_CTRLC_DETECTED]="RBK0163E: Script execution canceled with CTRL C."
MSG_DE[$MSG_CTRLC_DETECTED]="RBK0163E: Scriptausführung mit CTRL C abgebrochen."
MSG_HARDLINK_ERROR=164
MSG_EN[$MSG_HARDLINK_ERROR]="RBK0164E: Unable to create hardlinks. RC %s."
MSG_DE[$MSG_HARDLINK_ERROR]="RBK0164E: Es können keine Hardlinks erstellt werden. RC %s."
MSG_INTRO_BETA_MESSAGE=165
MSG_EN[$MSG_INTRO_BETA_MESSAGE]="RBK0165W: =========> NOTE  <========= \
${NL}!!! RBK0165W: This is a betaversion and should not be used in production. \
${NL}!!! RBK0165W: =========> NOTE <========="
MSG_DE[$MSG_INTRO_BETA_MESSAGE]="RBK0165W: =========> HINWEIS <========= \
${NL}!!! RBK0165W: Dieses ist eine Betaversion welche nicht in Produktion benutzt werden sollte. \
${NL}!!! RBK0165W: =========> HINWEIS <========="
MSG_UMOUNT_ERROR=166
MSG_EN[$MSG_UMOUNT_ERROR]="RBK0166E: Umount for %s failed. RC %s. Maybe mounted somewhere else?"
MSG_DE[$MSG_UMOUNT_ERROR]="RBK0166E: Umount für %s fehlerhaft. RC %s. Vielleicht noch woanders gemounted?"
MSG_SENDING_EMAIL=167
MSG_EN[$MSG_SENDING_EMAIL]="RBK0167I: Sending email."
MSG_DE[$MSG_SENDING_EMAIL]="RBK0167I: Eine eMail wird versendet."
MSG_BETAVERSION_AVAILABLE=168
MSG_EN[$MSG_BETAVERSION_AVAILABLE]="RBK0168I: $SMILEY_BETA_AVAILABLE $MYSELF beta version %s is available. Any help to test this beta is appreciated. Just upgrade to the new beta version with option -U. Restore to the previous version with option -V"
MSG_DE[$MSG_BETAVERSION_AVAILABLE]="RBK0168I: $SMILEY_BETA_AVAILABLE $MYSELF Beta Version %s ist verfügbar. Hilfe beim Testen dieser Beta ist sehr willkommen. Einfach auf die neue Beta Version mit der Option -U upgraden. Die vorhergehende Version kann mit der Option -V wiederhergestellt werden"
MSG_ROOT_PARTITION_NOT_FOUND=169
MSG_EN[$MSG_ROOT_PARTITION_NOT_FOUND]="RBK0169E: Target root partition %s does not exist."
MSG_DE[$MSG_ROOT_PARTITION_NOT_FOUND]="RBK0169E: Ziel Rootpartition %s existiert nicht."
MSG_MISSING_R_OPTION=170
MSG_EN[$MSG_MISSING_R_OPTION]="RBK0170E: Backup uses an external root partition. -R option missing."
MSG_DE[$MSG_MISSING_R_OPTION]="RBK0170E: Backup benutzt eine externe root Partition. Die Option -R fehlt."
MSG_NOPARTITIONS_TOBACKUP_FOUND=171
MSG_EN[$MSG_NOPARTITIONS_TOBACKUP_FOUND]="RBK0171E: Unable to detect any partitions to backup."
MSG_DE[$MSG_NOPARTITIONS_TOBACKUP_FOUND]="RBK0171E: Es können keine zu sichernde Partitionen gefunden werden."
MSG_UNABLE_TO_CREATE_DIRECTORY=172
MSG_EN[$MSG_UNABLE_TO_CREATE_DIRECTORY]="RBK0172E: Unable to create directory %s."
MSG_DE[$MSG_UNABLE_TO_CREATE_DIRECTORY]="RBK0172E: Verzeichnis %s kann nicht erstellt werden."
MSG_INTRO_HOTFIX_MESSAGE=173
MSG_EN[$MSG_INTRO_HOTFIX_MESSAGE]="RBK0173W: =========> NOTE  <========= \
${NL}!!! RBK0173W: This is a temporary hotfix and has to be upgraded to next available version as soon as one is available. \
${NL}!!! RBK0173W: =========> NOTE <========="
MSG_DE[$MSG_INTRO_HOTFIX_MESSAGE]="RBK0173W: =========> HINWEIS <========= \
${NL}!!! RBK0173W: Dieses ist ein temporärer Hotfix der auf die nächste Version upgraded werden muss sobald eine verfügbar ist. \
${NL}!!! RBK0173W: =========> HINWEIS <========="
MSG_TOOL_ERROR_SKIP=174
MSG_EN[$MSG_TOOL_ERROR_SKIP]="RBK0174I: Backup tool %s error %s ignored. For errormessages see log file."
MSG_DE[$MSG_TOOL_ERROR_SKIP]="RBK0174I: Backupprogramm %s Fehler %s wurde ignoriert. Fehlermeldungen finden sich im Logfile."
MSG_SCRIPT_UPDATE_NOT_REQUIRED=175
MSG_EN[$MSG_SCRIPT_UPDATE_NOT_REQUIRED]="RBK0175I: %s version %s is newer than version %s."
MSG_DE[$MSG_SCRIPT_UPDATE_NOT_REQUIRED]="RBK0175I: %s Version %s ist aktueller als Version %s."
MSG_RSYNC_DOES_NOT_SUPPORT_PROGRESS=176
MSG_EN[$MSG_RSYNC_DOES_NOT_SUPPORT_PROGRESS]="RBK0173E: rsync version %s doesn't support progress information."
MSG_DE[$MSG_RSYNC_DOES_NOT_SUPPORT_PROGRESS]="RBK0173E: rsync Version %s unterstüzt keine Fortschrittsanzeige."
MSG_ALL_BACKUPS_KEPT=177
MSG_EN[$MSG_ALL_BACKUPS_KEPT]="RBK0177W: All backups kept for backup type %s."
MSG_DE[$MSG_ALL_BACKUPS_KEPT]="RBK0177W: Alle Backups werden für den Backuptyp %s aufbewahrt."
MSG_IMG_BOOT_BACKUP_FAILED=178
MSG_EN[$MSG_IMG_BOOT_BACKUP_FAILED]="RBK0178E: Creation of %s failed with RC %s."
MSG_DE[$MSG_IMG_BOOT_BACKUP_FAILED]="RBK0178E: Erzeugung von %s Datei endet fehlerhaft mit RC %s."
MSG_IMG_BOOT_RESTORE_FAILED=179
MSG_EN[$MSG_IMG_BOOT_RESTORE_FAILED]="RBK0179E: Restore of %s file failed with RC %s."
MSG_DE[$MSG_IMG_BOOT_RESTORE_FAILED]="RBK0179E: Wiederherstellung von %s Datei endet fehlerhaft mit RC %s."
MSG_FORMATTING_FIRST_PARTITION=180
MSG_EN[$MSG_FORMATTING_FIRST_PARTITION]="RBK0180I: Formating first partition (boot partition) %s."
MSG_DE[$MSG_FORMATTING_FIRST_PARTITION]="RBK0180I: Erste Partition (Bootpartition) %s wird formatiert."
MSG_AFTER_STARTING_SERVICES=181
MSG_EN[$MSG_AFTER_STARTING_SERVICES]="RBK0181I: Executing commands post backup: '%s'."
MSG_DE[$MSG_AFTER_STARTING_SERVICES]="RBK0181I: Nach dem Backup ausgeführte Befehle: '%s'."
MSG_BEFORE_STOPPING_SERVICES=182
MSG_EN[$MSG_BEFORE_STOPPING_SERVICES]="RBK0182I: Executing commands pre backup: '%s'."
MSG_DE[$MSG_BEFORE_STOPPING_SERVICES]="RBK0182I: Vor dem Backup ausgeführte Befehle: '%s'."
MSG_IMG_ROOT_CHECK_FAILED=183
MSG_EN[$MSG_IMG_ROOT_CHECK_FAILED]="RBK0183E: Rootpartition check failed with RC %s."
MSG_DE[$MSG_IMG_ROOT_CHECK_FAILED]="RBK0183E: Rootpartitionscheck endet fehlerhaft mit RC %s."
MSG_IMG_ROOT_CHECK_STARTED=184
MSG_EN[$MSG_IMG_ROOT_CHECK_STARTED]="RBK0184I: Rootpartition check started."
MSG_DE[$MSG_IMG_ROOT_CHECK_STARTED]="RBK0184I: Rootpartitionscheck gestartet."
MSG_IMG_BOOT_CREATE_PARTITION_FAILED=185
MSG_EN[$MSG_IMG_BOOT_CREATE_PARTITION_FAILED]="RBK0185E: Bootpartition creation failed with RC %s."
MSG_DE[$MSG_IMG_BOOT_CREATE_PARTITION_FAILED]="RBK0185E: Bootpartitionserstellung endet fehlerhaft mit RC %s."
MSG_IMG_ROOT_CREATE_PARTITION_FAILED=186
MSG_EN[$MSG_IMG_ROOT_CREATE_PARTITION_FAILED]="RBK0185E: Rootpartition creation failed with RC %s."
MSG_DE[$MSG_IMG_ROOT_CREATE_PARTITION_FAILED]="RBK0185E: Rootpartitionserstellung endet fehlerhaft mit RC %s."
MSG_DETAILED_ROOT_CHECKING=187
MSG_EN[$MSG_DETAILED_ROOT_CHECKING]="RBK0187W: Rootpartition %s will be checked for bad blocks during formatting. This will take some time. Please be patient."
MSG_DE[$MSG_DETAILED_ROOT_CHECKING]="RBK0187W: Rootpartitionsformatierung für %s prüft auf fehlerhafte Blocks. Das wird länger dauern. Bitte Geduld."
MSG_UPDATE_TO_BETA=188
MSG_EN[$MSG_UPDATE_TO_BETA]="RBK0188I: There is a Beta version of $MYSELF available. Upgrading current version %s to %s."
MSG_DE[$MSG_UPDATE_TO_BETA]="RBK0188I: Es ist eine Betaversion von $MYSELF verfügbar. Die momentane Version %s auf %s upgraden."
MSG_UPDATE_ABORTED=189
MSG_EN[$MSG_UPDATE_ABORTED]="RBK0189I: Version upgrade aborted."
MSG_DE[$MSG_UPDATE_ABORTED]="RBK0189I: Versionsupgrade abgebrochen."
MSG_UPDATE_TO_VERSION=190
MSG_EN[$MSG_UPDATE_TO_VERSION]="RBK0190I: Upgrading $MYSELF from version %s to %s."
MSG_DE[$MSG_UPDATE_TO_VERSION]="RBK0190I: Es wird $MYSELF von Version %s auf Version %s upgraded."
MSG_ADJUSTING_DISABLED=191
MSG_EN[$MSG_ADJUSTING_DISABLED]="RBK0191E: Target %s with %s is smaller than backup source with %s. root partition resizing is disabled."
MSG_DE[$MSG_ADJUSTING_DISABLED]="RBK0191E: Ziel %s mit %s ist kleiner als die Backupquelle mit %s. Verkleinern der root Partition ist ausgeschaltet."
MSG_INTRO_DEV_MESSAGE=192
MSG_EN[$MSG_INTRO_DEV_MESSAGE]="RBK0192W: =========> NOTE  <========= \
${NL}!!! RBK0192W: This is a development version and should not be used in production. \
${NL}!!! RBK0192W: =========> NOTE <========="
MSG_DE[$MSG_INTRO_DEV_MESSAGE]="RBK0192W: =========> HINWEIS <========= \
${NL}!!! RBK0192W: Dieses ist eine Entwicklerversion welcher nicht in Produktion benutzt werden sollte. \
${NL}!!! RBK0192W: =========> HINWEIS <========="
MSG_MISSING_COMMANDS=193
MSG_EN[$MSG_MISSING_COMMANDS]="RBK0193E: Missing required commands '%s'."
MSG_DE[$MSG_MISSING_COMMANDS]="RBK0193E: Erforderliche Befehle '%s' nicht vorhanden."
MSG_MISSING_PACKAGES=194
MSG_EN[$MSG_MISSING_PACKAGES]="RBK0194E: Missing required packages. Install them with 'sudo apt-get install %s'."
MSG_DE[$MSG_MISSING_PACKAGES]="RBK0194E: Erforderliche Pakete nicht installiert. Installiere sie mit 'sudo apt-get install %s'"
MSG_FORCE_UPDATE=195
MSG_EN[$MSG_FORCE_UPDATE]="RBK0192I: Update $MYSELF %s."
MSG_DE[$MSG_FORCE_UPDATE]="RBK0192I: $MYSELF %s aktualisieren."
MSG_NO_HARDLINKS_USED=196
MSG_EN[$MSG_NO_HARDLINKS_USED]="RBK0196W: No hardlinks supported on %s."
MSG_DE[$MSG_NO_HARDLINKS_USED]="RBK0196W: %s unterstützt keine Hardlinks."
MSG_EMAIL_SEND_FAILED=197
MSG_EN[$MSG_EMAIL_SEND_FAILED]="RBK0197W: eMail send command %s failed with RC %s."
MSG_DE[$MSG_EMAIL_SEND_FAILED]="RBK0197W: eMail mit %s versenden endet fehlerhaft mit RC %s."
MSG_BEFORE_START_SERVICES_FAILED=198
MSG_EN[$MSG_BEFORE_START_SERVICES_FAILED]="RBK0198E: Pre backup commands failed with %s."
MSG_DE[$MSG_BEFORE_START_SERVICES_FAILED]="RBK0198E: Fehler in vor dem Backup ausgeführten Befehlen %s."
MSG_MISSING_RESTOREDEVICE_OPTION=199
MSG_EN[$MSG_MISSING_RESTOREDEVICE_OPTION]="RBK0199E: Option -R requires also option -d."
MSG_DE[$MSG_MISSING_RESTOREDEVICE_OPTION]="RBK0199E: Option -r benötigt auch Option -d."
MSG_SHARED_BOOT_DEVICE=200
MSG_EN[$MSG_SHARED_BOOT_DEVICE]="RBK0200I: /boot and / located on same partition %s."
MSG_DE[$MSG_SHARED_BOOT_DEVICE]="RBK0200I: /boot und / befinden sich auf derselben Partition %s."
MSG_BEFORE_STOP_SERVICES_FAILED=201
MSG_EN[$MSG_BEFORE_STOP_SERVICES_FAILED]="RBK0201E: Post backup commands failed with %s."
MSG_DE[$MSG_BEFORE_STOP_SERVICES_FAILED]="RBK0201E: Fehler in nach dem Backup ausgeführten Befehlen %s."
MSG_RESTORETEST_REQUIRED=202
MSG_EN[$MSG_RESTORETEST_REQUIRED]="RBK0202W: $SMILEY_RESTORETEST_REQUIRED Friendly reminder: Execute now a restore test. You will be reminded %s times again."
MSG_DE[$MSG_RESTORETEST_REQUIRED]="RBK0201W: $SMILEY_RESTORETEST_REQUIRED Freundlicher Hinweis: Führe einen Restoretest durch. Du wirst noch %s mal erinnert werden."
MSG_NO_BOOT_DEVICE_DISOVERED=203
MSG_EN[$MSG_NO_BOOT_DEVICE_DISOVERED]="RBK0203E: Unable to discover boot device. Please report this issue with a debug log created with option '-l debug'."
MSG_DE[$MSG_NO_BOOT_DEVICE_DISOVERED]="RBK0203E: Boot device kann nicht erkannt werden. Bitte das Problem mit einem Debuglog welches mit Option '-l debug' erstellt wird berichten."
MSG_TRUNCATING_ERROR=204
MSG_EN[$MSG_TRUNCATING_ERROR]="RBK0204E: Unable to calculate truncation backup size."
MSG_DE[$MSG_TRUNCATING_ERROR]="RBK0204E: Verkleinerte Backupgröße kann nicht berechnet werden."

declare -A MSG_HEADER=( ['I']="---" ['W']="!!!" ['E']="???" )

# Create message and substitute parameters

function getMessageText() {         # languageflag messagenumber parm1 parm2 ...
	local msg p i s

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
				msg="${MSG_EN[$2]}"  	    	    # fallback into english
			fi
		fi
	 else
		 msg="${MSG_EN[$2]}"      	      	        # fallback into english
	 fi

	# backward compatibility: change extension messages with old message format of 0.6.4 using %1, %2 ... to new 0.6.4.1 format using %s only
	if [[ "$msg" =~ ^- ]]; then
		msg=$(sed -e 's/--- //' -e 's/%[0-9]/%s/g' -e 's/\\%/%%/' <<< "$msg")
	fi
	printf -v msg "$msg" "${@:3}"

	local msgPref="${msg:0:3}"
	if [[ $msgPref == "RBK" ]]; then								# RBK0001E
		local severity="${msg:7:1}"
		[[ $severity == "W" ]] && WARNING_MESSAGE_WRITTEN=1
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

	logEntry "$1"

	local extension

	if [[ $1 == $EMAIL_EXTENSION ]]; then
		local extensionFileName="${MYNAME}_${EMAIL_EXTENSION}.sh"
		shift 1
		local args=( "$@" )

		if which $extensionFileName &>/dev/null; then
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

			if which $extensionFileName &>/dev/null; then
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

	logExit

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
  for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
  return 1
}

# --- Helper function to extract the message text in German or English and insert message parameters

function getLocalizedMessage() { # messageNumber parm1 parm2

	local msg
	msg="$(getMessageText $LANGUAGE "$@")"
	echo "$msg"
}

# Write message

function writeToConsole() {  # msglevel messagenumber message
	local msg level timestamp
	(( $noNL )) && noNL="-n"

	level=$1
	shift

	msg="$(getMessageText $LANGUAGE "$@")"

	if [[ ( $level -le $MSG_LEVEL ) ]]; then

# --- RBK0105I: Deleting new backup directory /backup/obelix/obelix-rsync-backup-20180912-215541.
# ??? RBK0005E: Backup failed. Check previous error messages for details.

		local msgNumber=$(cut -f 2 -d ' ' <<< "$msg")
		local msgSev=${msgNumber:7:1}

		if (( $TIMESTAMPS )); then
			timestamp="$(date +'%m-%d-%Y %T') "
		fi

		if (( $INTERACTIVE )); then
			if [[ $msgSev == "E" ]]; then
				echo $noNL -e "$timestamp$msg" >&2
			else
				echo $noNL -e "$timestamp$msg" >&1
			fi
		fi

		echo $noNL -e "$timestamp$msg" >> "$MSG_FILE"
	fi

	local line
	while IFS= read -r line; do
		logIntoOutput $LOG_TYPE_MSG "$line"
	done <<< "$msg"

	unset noNL
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

function exitNormal() {
	saveVars
	rc=0
	exit 0
}

function saveVars() {
	if (( $UID == 0 )); then
		echo "BACKUP_TARGETDIR=\"$BACKUPTARGET_DIR\"" > $VARS_FILE
		echo "BACKUP_TARGETFILE=\"$BACKUPTARGET_FILE\"" >> $VARS_FILE
	fi
}

function exitError() { # {rc}

	logEntry "$1"
	if [[ -n "$1" ]]; then
		rc="$1"
	else
		assertionFailed $LINENO "Unkown exit error"
	fi

	logExit "$rc"
	exit $rc
}

# write stdout and stderr into log
function executeCommand() { # command - rc's to accept
	executeCmd "$1" "&" "$2"
	return $?
}

# gzip writes it's output into stdout thus don't redirect stdout into log, only stderr
function executeCommandNoStdoutRedirect() { # command - rc's to accept
	executeCmd "$1" "2" "$2"
	return $?
}

function executeCmd() { # command - redirects - rc's to accept
	local rc i
	logEntry "Command: $1"
	logItem "Redirect: $2 - Skips: $3"

	if (( $INTERACTIVE )); then
		eval "$1"
	else
		eval "$1 $2>> $LOG_FILE"
	fi
	rc=$?
	if (( $rc != 0 )); then
		local error=1
		for i in ${@:3}; do
			if (( $i == $rc )); then
				writeToConsole $MSG_LEVEL_DETAILED $MSG_TOOL_ERROR_SKIP "$BACKUPTYPE" $rc
				rc=0
				error=0
				break
			fi
		done
	fi
	logExit "$rc"
	return $rc
}

function executeShellCommand() { # command

	logEntry "$@"
	if (( $INTERACTIVE )); then
		eval "$1"
	else
		eval "$1 &>> $LOG_FILE"
	fi
	local rc=$?
	logExit "$rc"
	return $rc
}

function logIntoOutput() { # logtype prefix message

	[[ $LOG_DEBUG != $LOG_LEVEL ]] && return

	local type=${LOG_TYPEs[$1]}
	shift
	local prefix="$1"
	shift
	local lineno=${BASH_LINENO[1]}
	local dte=$(date +%Y%m%d-%H%M%S)
	local indent=$(printf '%*s' "$LOG_INDENT")
	local m

	local line
	while IFS= read -r line; do
		printf -v m "%s %04d: %s %s %s" "$type" "$lineno" "$indent" "$prefix" "$line"
		case $LOG_OUTPUT in
			$LOG_OUTPUT_SYSLOG)
				logger -t $MYSELF -- "$m"
				;;
			$LOG_OUTPUT_VARLOG | $LOG_OUTPUT_BACKUPLOC | $LOG_OUTPUT_HOME)
				echo "$dte $m" >> "$LOG_FILE"
				;;
			*)
				echo "$dte $m" >> "$LOG_FILE"
				;;
		esac
	done <<< "$@"
}

function repeat() { # char num
	local s
	s=$( yes $1 | head -$2 | tr -d "\n" )
	echo $s
}

function logItem() { # message
	logIntoOutput $LOG_TYPE_DEBUG "--" "$1"
}

function logEntry() { # message
	(( LOG_INDENT+=3 ))
	logIntoOutput $LOG_TYPE_DEBUG "->" "${FUNCNAME[1]} $@"
}

function logExit() { # message
	logIntoOutput $LOG_TYPE_DEBUG "<-" "${FUNCNAME[1]} $@"
	(( LOG_INDENT-=3 ))
}

function logSystem() {
	logEntry
	[[ -f /etc/os-release ]] &&	logItem "$(cat /etc/os-release)"
	[[ -f /etc/debian_version ]] &&	logItem "$(cat /etc/debian_version)"
	[[ -f /etc/fstab ]] &&	logItem "$(cat /etc/fstab)"
	logExit
}

function logSystemStatus() {

	logEntry

	if (( $SYSTEMSTATUS )); then
		if ! which lsof &>/dev/null; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "lsof" "lsof"
			else
				logItem "service --status-all$NL$(service --status-all 2>&1)"
				logItem "lsof$NL$(lsof / | awk 'NR==1 || $4~/[0-9][uw]/' 2>&1)"
			fi
	fi

	logExit

}

# calculate time difference, return array with days, hours, minutes and seconds
function duration() { # startTime endTime
	factors=(86400 3600 60 1)
	local diff=$(( $2 - $1 ))
	local d i q
	i=0
	for f in "${factors[@]}"; do
		q=$(( diff / f ))
		diff=$(( diff - q * f ))
		d[i]=$(printf "%02d" $q)
		((i++))
	done
	echo "${d[@]}"
}

function logOptions() {

	logEntry

	logItem "$(uname -a)"

	logItem "Options: $INVOCATIONPARMS"
	logItem "APPEND_LOG=$APPEND_LOG"
	logItem "APPEND_LOG_OPTION=$APPEND_LOG_OPTION"
	logItem "BACKUPPATH=$BACKUPPATH"
	logItem "BACKUPTYPE=$BACKUPTYPE"
	logItem "AFTER_STARTSERVICES=$AFTER_STARTSERVICES"
	logItem "BEFORE_STOPSERVICES=$BEFORE_STOPSERVICES"
	logItem "CHECK_FOR_BAD_BLOCKS=$CHECK_FOR_BAD_BLOCKS"
 	logItem "CONFIG_FILE=$CONFIG_FILE"
 	logItem "DD_BACKUP_SAVE_USED_PARTITIONS_ONLY=$DD_BACKUP_SAVE_USED_PARTITIONS_ONLY"
 	logItem "DD_BLOCKSIZE=$DD_BLOCKSIZE"
 	logItem "DD_PARMS=$DD_PARMS"
	logItem "DEPLOYMENT_HOSTS=$DEPLOYMENT_HOSTS"
	logItem "YES_NO_RESTORE_DEVICE=$YES_NO_RESTORE_DEVICE"
	logItem "EMAIL=$EMAIL"
	logItem "EMAIL_PARMS=$EMAIL_PARMS"
	logItem "EXCLUDE_LIST=$EXCLUDE_LIST"
	logItem "EXTENSIONS=$EXTENSIONS"
	logItem "FAKE=$FAKE"
	logItem "HANDLE_DEPRECATED=$HANDLE_DEPRECATED"
	logItem "KEEPBACKUPS=$KEEPBACKUPS"
	logItem "KEEPBACKUPS_DD=$KEEPBACKUPS_DD"
	logItem "KEEPBACKUPS_DDZ=$KEEPBACKUPS_DDZ"
	logItem "KEEPBACKUPS_TAR=$KEEPBACKUPS_TAR"
	logItem "KEEPBACKUPS_TGZ=$KEEPBACKUPS_TGZ"
	logItem "KEEPBACKUPS_RSYNC=$KEEPBACKUPS_RSYNC"
	logItem "LANGUAGE=$LANGUAGE"
	logItem "LINK_BOOTPARTITIONFILES=$LINK_BOOTPARTITIONFILES"
	logItem "LOG_LEVEL=$LOG_LEVEL"
 	logItem "LOG_OUTPUT=$LOG_OUTPUT"
	logItem "MAIL_ON_ERROR_ONLY=$MAIL_ON_ERROR_ONLY"
	logItem "MAIL_PROGRAM=$EMAIL_PROGRAM"
	logItem "MSG_LEVEL=$MSG_LEVEL"
	logItem "NOTIFY_UPDATE=$NOTIFY_UPDATE"
	logItem "PARTITIONBASED_BACKUP=$PARTITIONBASED_BACKUP"
	logItem "PARTITIONS_TO_BACKUP=$PARTITIONS_TO_BACKUP"
	logItem "RESIZE_ROOTFS=$RESIZE_ROOTFS"
	logItem "RESTORE_DEVICE=$RESTORE_DEVICE"
	logItem "ROOT_PARTITION=$ROOT_PARTITION"
	logItem "RSYNC_BACKUP_ADDITIONAL_OPTIONS=$RSYNC_BACKUP_ADDITIONAL_OPTIONS"
	logItem "RSYNC_BACKUP_OPTIONS=$RSYNC_BACKUP_OPTIONS"
	logItem "RSYNC_IGNORE_ERRORS=$RSYNC_IGNORE_ERRORS"
	logItem "SENDER_EMAIL=$SENDER_EMAIL"
 	logItem "SKIP_DEPRECATED=$SKIP_DEPRECATED"
 	logItem "SKIPLOCALCHECK=$SKIPLOCALCHECK"
	logItem "STARTSERVICES=$STARTSERVICES"
	logItem "STOPSERVICES=$STOPSERVICES"
	logItem "SYSTEMSTATUS=$SYSTEMSTATUS"
	logItem "TAR_BACKUP_ADDITIONAL_OPTIONS=$TAR_BACKUP_ADDITIONAL_OPTIONS"
	logItem "TAR_BACKUP_OPTIONS=$TAR_BACKUP_OPTIONS"
	logItem "TAR_BOOT_PARTITION_ENABLED=$TAR_BOOT_PARTITION_ENABLED"
	logItem "TAR_IGNORE_ERRORS=$TAR_IGNORE_ERRORS"
	logItem "TAR_RESTORE_ADDITIONAL_OPTIONS=$TAR_RESTORE_ADDITIONAL_OPTIONS"
	logItem "TIMESTAMPS=$TIMESTAMPS"
	logItem "USE_HARDLINKS=$USE_HARDLINKS"
	logItem "VERBOSE=$VERBOSE"
	logItem "ZIP_BACKUP=$ZIP_BACKUP"

	logExit

}

LOG_MAIL_FILE="/tmp/${MYNAME}.maillog"
rm -f "$LOG_MAIL_FILE" &>/dev/null
LOG_FILE_NAME="${MYNAME}.log"
LOG_FILE="$CURRENT_DIR/$LOG_FILE_NAME"
rm -f "$LOG_FILE" &>/dev/null

function initializeDefaultConfig() {

	############# Begin default config section #############

	# Part or whole of the following section can be put into
	# /usr/local/etc/raspiBackup.conf, ~/.raspiBackup.conf or $(pwd)/.raspiBackup.conf
	# and will take precedence over the following default definitions

	# path to store the backupfile
	DEFAULT_BACKUPPATH="/backup"
	# how many backups to keep of all backup types
	DEFAULT_KEEPBACKUPS=3
	# how many backups to keep of the specific backup type. If zero DEFAULT_KEEPBACKUPS is used
	DEFAULT_KEEPBACKUPS_DD=0
	DEFAULT_KEEPBACKUPS_DDZ=0
	DEFAULT_KEEPBACKUPS_TAR=0
	DEFAULT_KEEPBACKUPS_TGZ=0
	DEFAULT_KEEPBACKUPS_RSYNC=0
	# type of backup: dd, tar or rsync
	DEFAULT_BACKUPTYPE="dd"
	# zip tar or dd backup (0 = false, 1 = true)
	DEFAULT_ZIP_BACKUP=0
	# dd backup will save space used by partitions only
	DEFAULT_DD_BACKUP_SAVE_USED_PARTITIONS_ONLY=0
	# commands to stop services before backup separated by &&
	DEFAULT_STOPSERVICES=""
	# commands to start services after backup separated by &&
	DEFAULT_STARTSERVICES=""
	# commands to execute before backup stops separated by &&
	DEFAULT_BEFORE_STOPSERVICES=""
	# commands to execute after backup start separated by &&
	DEFAULT_AFTER_STARTSERVICES=""
	# email to send completion status
	DEFAULT_EMAIL=""
	# sender email used with ssmtp
	DEFAULT_SENDER_EMAIL=""
	# Additional parameters for email program (optional)
	DEFAULT_EMAIL_PARMS=""
	# log level  (0 = none, 1 = debug)
	DEFAULT_LOG_LEVEL=1
	# log output ( 0 = syslog, 1 = /var/log, 2 = backuppath, 3 = ./raspiBackup.log, <somefilename>)
	DEFAULT_LOG_OUTPUT=2
	# msg level (0 = minimal, 1 = detailed)
	DEFAULT_MSG_LEVEL=0
	# mailprogram
	DEFAULT_MAIL_PROGRAM="mail"
	# restore device
	DEFAULT_RESTORE_DEVICE=""
	# default append log (0 = false, 1 = true)
	DEFAULT_APPEND_LOG=0
	# option used by mail program to append log (for example -a or -A)
	DEFAULT_APPEND_LOG_OPTION="-a"
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
	# use hardlinks for rsync if possible
	DEFAULT_USE_HARDLINKS=1
	# save boot partition with tar
	DEFAULT_TAR_BOOT_PARTITION_ENABLED=0
	# Change these options only if you know what you are doing !!!
	DEFAULT_RSYNC_BACKUP_OPTIONS="-aHAx"
	DEFAULT_RSYNC_BACKUP_ADDITIONAL_OPTIONS=""
	DEFAULT_TAR_BACKUP_OPTIONS="-cpi --one-file-system"
	DEFAULT_TAR_BACKUP_ADDITIONAL_OPTIONS=""
	DEFAULT_TAR_RESTORE_ADDITIONAL_OPTIONS=""
	# Send email only in case of errors. Use with care !
	DEFAULT_MAIL_ON_ERROR_ONLY=0
	# Version to suppress deprecated message, separated with spaces
	DEFAULT_SKIP_DEPRECATED=""
	# report uuid
	DEFAULT_USE_UUID=1
	# Check for back blocks when formating restore device (Will take a long time)
	DEFAULT_CHECK_FOR_BAD_BLOCKS=0
	# Resize root filesystem during restore
	DEFAULT_RESIZE_ROOTFS=1
	# add timestamps in front of messages
	DEFAULT_TIMESTAMPS=0
	# add system status in debug log (Attention: may expose sensible information)
	DEFAULT_SYSTEMSTATUS=0
	# reminder to test restore (unit: months)
	DEFAULT_RESTORE_REMINDER_INTERVAL=6
	# Number of times restore reminder bothers you
	DEFAULT_RESTORE_REMINDER_REPEAT=3

	############# End default config section #############

}

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

	logEntry

	local ll lla lo loa ml mla
	if [[ ! "$LOG_LEVEL" =~ ^[0-9]$ ]]; then
		ll=$(tr '[:lower:]' '[:upper:]'<<< $LOG_LEVEL)
		lla=$(tr '[:lower:]' '[:upper:]'<<< ${LOG_LEVEL_ARGs[$ll]+abc})
		if [[ $lla == "ABC" ]]; then
			LOG_LEVEL=${LOG_LEVEL_ARGs[$ll]}
		fi
	fi

	if [[ ! "$LOG_OUTPUT" =~ ^[0-9]$ ]]; then
		lo=$(tr '[:lower:]' '[:upper:]'<<< $LOG_OUTPUT)
		loa=$(tr '[:lower:]' '[:upper:]'<<< ${LOG_OUTPUT_ARGs[$lo]+abc})
		if [[ $loa == "ABC" ]]; then
			LOG_OUTPUT=${LOG_OUTPUT_ARGs[$lo]}
		fi
	fi

	if [[ ! "$MSG_LEVEL" =~ ^[0-9]$ ]]; then
		ml=$(tr '[:lower:]' '[:upper:]'<<< $MSG_LEVEL)
		mla=$(tr '[:lower:]' '[:upper:]'<<< ${MSG_LEVEL_ARGs[$ml]+abc})
		if [[ $mla == "ABC" ]]; then
			MSG_LEVEL=${MSG_LEVEL_ARGs[$ml]}
		fi
	fi

	logExit

}

function bootedFromSD() {
	logEntry
	local rc
	logItem "Boot device: $BOOT_DEVICE"
	if [[ $BOOT_DEVICE =~ mmcblk[0-9]+ ]]; then
		rc=0			# yes /dev/mmcblk0p1
	else
		rc=1			# is /dev/sda1 or other
	fi
	logExit "$rc"
	return $rc
}

# Input:
# 	mmcblk0
# 	sda
# Output:
# 	mmcblk0p
# 	sda

function getPartitionPrefix() { # device

	logEntry "$1"
	if [[ $1 =~ ^(mmcblk|loop|sd[a-z]) ]]; then
		local pref="$1"
		[[ $1 =~ ^(mmcblk|loop) ]] && pref="${1}p"
	else
		logItem "device: $1"
		assertionFailed $LINENO "Unable to retrieve partition prefix for device $1"
	fi

	logExit "$pref"
	echo "$pref"

}

# Input:
# 	/dev/mmcblk0p1
#	/dev/sda2
# Output:
# 	1
#	2

function getPartitionNumber() { # deviceName

	logEntry "$1"
	local id
	if [[ $1 =~ ^/dev/(mmcblk|loop)[0-9]+p([0-9]+) || $1 =~ ^/dev/(sd[a-z])([0-9]+) ]]; then
		id=${BASH_REMATCH[2]}
	else
		assertionFailed $LINENO "Unable to retrieve partition number from deviceName $1"
	fi
	echo "$id"
	logExit "$id"

}

function isUpdatePossible() {

	logEntry ""

	versions=( $(isNewVersionAvailable) )
	version_rc=$?
	if [[ $version_rc == 0 ]]; then
		NEWS_AVAILABLE=1
		UPDATE_POSSIBLE=1
		latestVersion="${versions[0]}"
		newVersion="${versions[1]}"
		oldVersion="${versions[2]}"

		writeToConsole $MSG_LEVEL_MINIMAL $MSG_NEW_VERSION_AVAILABLE "$newVersion" "$oldVersion"
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_VISIT_VERSION_HISTORY_PAGE "$(getLocalizedMessage $MSG_VERSION_HISTORY_PAGE)"
	fi

	logExit ""

}

function downloadPropertiesFile() { # FORCE

	logEntry

	NEW_PROPERTIES_FILE=0

	if (( ! $REGRESSION_TEST )); then

		if shouldRenewDownloadPropertiesFile "$1"; then

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

		parsePropertiesFile
	fi

	logExit "$NEW_PROPERTIES_FILE"
	return
}

#VERSION="0.6.3.1"
#INCOMPATIBLE=""
#DEPRECATED=""
#BETA="0.6.3.2"

function parsePropertiesFile() {

	logEntry

	local properties=$(grep "^VERSION=" "$LATEST_TEMP_PROPERTY_FILE" 2>/dev/null)
	[[ $properties =~ $PROPERTY_REGEX ]] && VERSION_PROPERTY=${BASH_REMATCH[1]}

	properties=$(grep "^INCOMPATIBLE=" "$LATEST_TEMP_PROPERTY_FILE" 2>/dev/null)
	[[ $properties =~ $PROPERTY_REGEX ]] && INCOMPATIBLE_PROPERTY=${BASH_REMATCH[1]}

	properties=$(grep "^DEPRECATED=" "$LATEST_TEMP_PROPERTY_FILE" 2>/dev/null)
	[[ $properties =~ $PROPERTY_REGEX ]] && DEPRECATED_PROPERTY=${BASH_REMATCH[1]}

	properties=$(grep "^BETA=" "$LATEST_TEMP_PROPERTY_FILE" 2>/dev/null)
	[[ $properties =~ $PROPERTY_REGEX ]] && BETA_PROPERTY=${BASH_REMATCH[1]}

	logItem "Properties: v: $VERSION_PROPERTY i: $INCOMPATIBLE_PROPERTY d: $DEPRECATED_PROPERTY b: $BETA_PROPERTY"

	logExit

}

function isVersionDeprecated() { # versionNumber

	logEntry

	local rc=1	# no/failure

	local deprecatedVersions=( $DEPRECATED_PROPERTY )
	if containsElement "$1" "${deprecatedVersions[@]}"; then
		rc=0
		logItem "Version $1 is deprecated"
	fi

	local skip=( $SKIP_DEPRECATED )
	if containsElement "$1" "${skip[@]}"; then
		rc=1
		logItem "Version $1 is deprecated but message is disabled"
	fi

	logExit "$rc"
	return $rc
}

function shouldRenewDownloadPropertiesFile() { # FORCE

	logEntry

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

	logExit "$rc"
	return $rc
}

function askYesNo() {

	local yes_no=$(getLocalizedMessage $MSG_QUERY_CHARS_YES_NO)
	local answer

	noNL=1
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_ANSWER_YES_NO "$yes_no"

	if (( $NO_YES_QUESTION )); then
		answer=$(getLocalizedMessage $MSG_ANSWER_CHARS_YES)
	else
		read answer
	fi

	answer=${answer:0:1}	# first char only
	answer=${answer:-"n"}	# set default no

	local yes=$(getLocalizedMessage $MSG_ANSWER_CHARS_YES)
	if [[ ! $yes =~ $answer ]]; then
		return 1
	else
		return 0
	fi
}

function isNewVersionAvailable() {

	logEntry

	local newVersion="0.0"
	local latestVersion="0.0"

	local rc=99			# update not possible

	local version="$VERSION"
	local suffix=""
	if [[ "$VERSION" =~ ^([^-]*)(-(.*))?$ ]]; then
		version=${BASH_REMATCH[1]}
		suffix=${BASH_REMATCH[3]}
	fi

	logItem "Versionsplit: $version - $suffix"

	if (( $NEW_PROPERTIES_FILE )); then
		local newVersion=$VERSION_PROPERTY
		latestVersion=$(echo -e "$newVersion\n$version" | sort -V | tail -1)
		logItem "new: $newVersion runtime: $version latest: $latestVersion"

		if [[ $version < $newVersion ]]; then
			rc=0	# new version available
		elif [[ $version > $newVersion ]]; then
			rc=2	# current version is a newer version
		else	    # versions are identical
			if [[ -z $suffix ]]; then
				rc=1	# no suffix, current version is latest version
			else
				if (( $IS_BETA || $IS_DEV )); then
					rc=0	# current is beta or development version, replace with final version
				elif (( $IS_HOTFIX )); then
					rc=2	# current version is hotfix, keep it until new version is available
				else
					rc=1	# current version is latest version
				fi
			fi
		fi
	fi

	result="$latestVersion $newVersion $VERSION"
	echo "$result"

	logItem "Returning: $result"

	logExit "$rc"

	return $rc

}

function stopServices() {

	logEntry

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
	logSystemStatus
	logExit
}

function executeBeforeStopServices() {
	logEntry
	if [[ -n "$BEFORE_STOPSERVICES" ]]; then
		writeToConsole $MSG_LEVEL_DETAILED $MSG_BEFORE_STOPPING_SERVICES "$BEFORE_STOPSERVICES"
		logItem "$BEFORE_STOPSERVICES"
		if (( ! $FAKE_BACKUPS )); then
			executeShellCommand "$BEFORE_STOPSERVICES"
			local rc=$?
			if [[ $rc != 0 ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_BEFORE_STOP_SERVICES_FAILED "$rc"
				exitError $RC_BEFORE_STOP_SERVICES_ERROR
			fi
			BEFORE_STOPPED_SERVICES=1
		fi
	fi
	logExit
}

function startServices() {

	logEntry

	logSystemStatus

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
	logExit
}

function executeAfterStartServices() {
	logEntry
	if [[ -n "$AFTER_STARTSERVICES" ]]; then
		writeToConsole $MSG_LEVEL_DETAILED $MSG_AFTER_STARTING_SERVICES "$AFTER_STARTSERVICES"
		logItem "$AFTER_STARTSERVICES"
		if (( ! $FAKE_BACKUPS )); then
			executeShellCommand "$AFTER_STARTSERVICES"
			local rc=$?
			if [[ $rc != 0 ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_BEFORE_START_SERVICES_FAILED "$rc"
				if [[ "$1" != "noexit" ]]; then
					exitError $RC_BEFORE_START_SERVICES_ERROR
				fi
			fi
			BEFORE_STOPPED_SERVICES=0
		fi
	fi
	logExit
}

# update script with latest version

function updateScript() {

	logEntry

	local rc versions latestVersion newVersion oldVersion newName
	local updateNow=0

	if (( $NEW_PROPERTIES_FILE )) ; then

		versions=( $(isNewVersionAvailable) )
		rc=$?

		latestVersion=${versions[0]}
		newVersion=${versions[1]}
		oldVersion=${versions[2]}

		logItem "$rc - $latestVersion - $newVersion - $oldVersion"

		if (( ! $FORCE_UPDATE )) ; then
			local incompatibleVersions=( $INCOMPATIBLE_PROPERTY )
			if containsElement "$newVersion" "${incompatibleVersions[@]}"; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_INCOMPATIBLE_UPDATE "$newVersion" "$(getLocalizedMessage $MSG_VERSION_HISTORY_PAGE)"
				exitNormal
			fi
		fi

		local betaVersion=$(isBetaAvailable)

		if [[ -n $betaVersion && "${betaVersion}-beta" > $oldVersion ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_UPDATE_TO_BETA "$oldVersion" "${betaVersion}-beta"
			if askYesNo; then
				DOWNLOAD_URL="$BETA_DOWNLOAD_URL"
				newVersion="${betaVersion}-beta"
				updateNow=1
			fi
		fi

		if [[ $rc == 0 ]] && (( ! $updateNow )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_UPDATE_TO_VERSION "$oldVersion" "$newVersion"
			if ! askYesNo; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_UPDATE_ABORTED
				exitNormal
			fi
			updateNow=1
		fi

		if (( !$updateNow )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FORCE_UPDATE "$oldVersion"
			if askYesNo; then
				updateNow=1
			fi
		fi

		if (( $updateNow )); then
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
			fi
		else
			rm $MYSELF~ &>/dev/null
			if [[ $rc == 1 ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_SCRIPT_UPDATE_NOT_NEEDED "$SCRIPT_DIR/$MYSELF" "$newVersion"
			elif [[ $rc == 2 ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_SCRIPT_UPDATE_NOT_REQUIRED "$SCRIPT_DIR/$MYSELF" "$oldVersion" "$newVersion"
			else
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_SCRIPT_UPDATE_FAILED "$MYSELF"
			fi
		fi
	fi

	logExit

}

# 0 = yes, no otherwise

function supportsHardlinks() {	# directory

	logEntry "$1"

	local links
	local result=1 # no

	touch /$1/$MYNAME.hlinkfile
	cp -l /$1/$MYNAME.hlinkfile /$1/$MYNAME.hlinklink
	links=$(ls -la /$1/$MYNAME.hlinkfile | cut -f 2 -d ' ')
	logItem "Links: $links"
	[[ $links == 2 ]] && result=0
	rm -f /$1/$MYNAME.hlinkfile &>/dev/null
	rm -f /$1/$MYNAME.hlinklink &>/dev/null

	logExit "$result"

	return $result
}

# 0 = yes, no otherwise

function supportsSymlinks() {	# directory

	logEntry "$1"

	local result=1	# no
	touch /$1/$MYNAME.slinkfile
	ln -s /$1/$MYNAME.slinkfile /$1/$MYNAME.slinklink
	[[ -L /$1/$MYNAME.slinklink ]] && result=0
	rm -f /$1/$MYNAME.slinkfile &>/dev/null
	rm -f /$1/$MYNAME.slinklink &>/dev/null

	logExit "$result"

	return $result
}

function isMounted() { # dir
	local rc
	logEntry "$1"
	if [[ -n "$1" ]]; then
		logItem "$(cat /proc/mounts)"
		grep -qs "$1" /proc/mounts
		rc=$?
	else
		rc=1
	fi
	logExit "$rc"
	return $rc
}

function getFsType() { # file or path

	logEntry "$1"

	local fstype=$(df -T "$1" | grep "^/" | awk '{ print $2 }')

	echo $fstype

	logExit "$fstype"

}

function assertCommandAvailable() { # command package

	if ! command -v $1 &> /dev/null; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "$1" "$2"
		exitError $RC_MISSING_COMMANDS
	fi

}

# check if directory is located on a mounted device

function isPathMounted() {

	logEntry "$1"

	local path
	local rc=1
	path=$1

	# backup path has to be mount point of the file system (second field fs_file in /etc/fstab) and NOT fs_spec otherwise test algorithm will create endless loop
	if [[ "${1:0:1}" == "/" ]]; then
		while [[ "$path" != "" ]]; do
			logItem "Path: $path"
			if mountpoint -q "$path"; then
				rc=0
				break
			fi
			path=${path%/*}
		done
	fi
	logExit "$rc"

	return $rc
}

function readConfigParameters() {

	logEntry

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

	if [[ "$HOME_CONFIG_FILE" != "$CURRENTDIR_CONFIG_FILE" ]]; then
		CURRENTDIR_CONFIG_FILE_INCLUDED=0
		if [ -f "$CURRENTDIR_CONFIG_FILE" ]; then
			set -e
			. "$CURRENTDIR_CONFIG_FILE"
			set +e
			CURRENTDIR_CONFIG_FILE_INCLUDED=1
		fi
	fi

	logExit
}

function setupEnvironment() {

	logEntry

	local PREVIOUS_LOG_FILE="$LOG_FILE"
	local PREVIOUS_MSG_FILE="$MSG_FILE"

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

		if [ ! -d "${BACKUPTARGET_DIR}" ] && (( ! $FAKE )); then
			if ! mkdir -p "${BACKUPTARGET_DIR}"; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNABLE_TO_CREATE_DIRECTORY "${BACKUPTARGET_DIR}"
				exitError $RC_CREATE_ERROR
			fi
		fi

		BACKUPPATH="$(sed -E 's@/+$@@g' <<< "$BACKUPPATH")"

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

		logItem "Current logfiles: L: $LOG_FILE M: $MSG_FILE"

		if (( $FAKE )) && [[ "$LOG_OUTPUT" =~ $LOG_OUTPUT_IS_NO_USERDEFINEDFILE_REGEX ]]; then
			LOG_OUTPUT=$LOG_OUTPUT_HOME
		fi

	else # restore
		LOG_OUTPUT="$LOG_OUTPUT_HOME"
	fi

	case $LOG_OUTPUT in
		$LOG_OUTPUT_VARLOG)
			LOG_BASE="/var/log/$MYNAME"
			if [ ! -d ${LOG_BASE} ]; then
				if ! mkdir -p ${LOG_BASE}; then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNABLE_TO_CREATE_DIRECTORY "${LOG_BASE}"
					exitError $RC_CREATE_ERROR
				fi
			fi
			LOG_FILE="$LOG_BASE/$HOSTNAME.log"
			MSG_FILE="$LOG_BASE/$HOSTNAME.msg"
			;;
		$LOG_OUTPUT_HOME)
			LOG_FILE="$CURRENT_DIR/$LOG_FILE_NAME"
			MSG_FILE="$CURRENT_DIR/$MSG_FILE_NAME"
			;;
		$LOG_OUTPUT_SYSLOG)
			LOG_FILE="/var/log/syslog"
			MSG_FILE="/var/log/syslog"
			;;
		$LOG_OUTPUT_BACKUPLOC)
			LOG_FILE="$BACKUPTARGET_DIR/$LOG_FILE_NAME"
			MSG_FILE="$BACKUPTARGET_DIR/$MSG_FILE_NAME"
			;;
		*)
			LOG_FILE="$LOG_OUTPUT"
			MSG_FILE="${LOG_OUTPUT}.msg"
	esac

	if [[ -z "$LOG_FILE" || "$LOG_FILE" == *"*"* ]]; then
		assertionFailed $LINENO "Invalid log file $LOG_FILE"
	fi
	if [[ -z "$MSG_FILE" || "$MSG_FILE" == *"*"* ]]; then
		assertionFailed $LINENO "Invalid msg file $MSG_FILE"
	fi

	if [[ -f $PREVIOUS_LOG_FILE && $PREVIOUS_LOG_FILE != $LOG_FILE ]] || (( $FAKE )) ; then
		cp $PREVIOUS_LOG_FILE $LOG_FILE &>/dev/null
		if [[ $LOG_OUTPUT != $LOG_OUTPUT_SYSLOG ]]; then	# keep syslog :-)
			(( ! $FAKE )) && rm $PREVIOUS_LOG_FILE
		fi
	fi
	if [[ $PREVIOUS_MSG_FILE != $MSG_FILE || (( $FAKE )) ]]; then
		cp $PREVIOUS_MSG_FILE $MSG_FILE &>/dev/null
		(( ! $FAKE )) && rm $PREVIOUS_MSG_FILE
	fi

	logItem "LOG_OUTPUT: $LOG_OUTPUT"
	logItem "Using logfile $LOG_FILE"
	logItem "Using msgfile $MSG_FILE"

	# save file descriptors, see https://unix.stackexchange.com/questions/80988/how-to-stop-redirection-in-bash
	exec 3>&1 4>&2
	# see https://stackoverflow.com/questions/3173131/redirect-copy-of-stdout-to-log-file-from-within-bash-script-itself
	exec 1> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE")
	exec 2> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE" >&2)

	logItem "BACKUPTARGET_DIR: $BACKUPTARGET_DIR"
	logItem "BACKUPTARGET_FILE: $BACKUPTARGET_FILE"

	logExit

}

# deploy script on my local PIs

function deployMyself() {

	logEntry

	for hostLogon in $DEPLOYMENT_HOSTS; do

		host=$(cut -d '@' -f 2 <<< $hostLogon)
		user=$(cut -d '@' -f 1 <<< $hostLogon)

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
			else
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_DEPLOYMENT_FAILED "$host" "$user"
			fi
		else
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_DEPLOYING_HOST_OFFLINE "$host"
		fi
	done

   	logExit

}

## partition table of /dev/sdc
#unit: sectors

#/dev/sdc1 : start=     8192, size=   114688, Id= c
#/dev/sdc2 : start=   122880, size= 30244864, Id=83
#/dev/sdc3 : start=        0, size=        0, Id= 0
#/dev/sdc4 : start=        0, size=        0, Id= 0

function calcSumSizeFromSFDISK() { # sfdisk file name

	logEntry "$1"

	local file="$1"

	logItem "File: $(cat $file)"

# /dev/mmcblk0p1 : start=     8192, size=    83968, Id= c
# or
# /dev/sdb1 : start=          63, size=  1953520002, type=83

	local partitionregex="/dev/.*[p]?([0-9]+)[^=]+=[^0-9]*([0-9]+)[^=]+=[^0-9]*([0-9]+)[^=]+=[^0-9a-z]*([0-9a-z]+)"
	local lineNo=0
	local sumSize=0

	local line
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

	logExit "$sumSize"
}

function sendEMail() { # content subject

	logEntry

	if [[ -n "$EMAIL" && rc != $RC_CTRLC ]]; then
		local attach content subject

		local attach=""
		local subject="$2"

		if (( ! $MAIL_ON_ERROR_ONLY || ( $MAIL_ON_ERROR_ONLY && rc != 0 ) )); then

			if (( $APPEND_LOG )); then
				attach="$DEFAULT_APPEND_LOG_OPTION $LOG_FILE"
				logItem "Appendlog $attach"
			fi

			IFS=" "
			content="$NL$(<"$MSG_FILE")$NL$1$NL"
			unset IFS
		fi

		local smiley=""
		if (( $NOTIFY_UPDATE && $NEWS_AVAILABLE )); then
			if (( $WARNING_MESSAGE_WRITTEN )); then
				smiley="$SMILEY_WARNING ${smiley}"
			fi
			if (( $UPDATE_POSSIBLE )); then
				smiley="$SMILEY_UPDATE_POSSIBLE ${smiley}"
			fi
			if (( $BETA_AVAILABLE )); then
				smiley="$SMILEY_BETA_AVAILABLE ${smiley}"
			fi
			if (( $RESTORETEST_REQUIRED )); then
				smiley="$SMILEY_RESTORETEST_REQUIRED ${smiley}"
			fi
			if (( $VERSION_DEPRECATED )); then
				smiley="$SMILEY_VERSION_DEPRECATED ${smiley}"
			fi
		fi

		subject="$smiley$subject"

		if (( ! $MAIL_ON_ERROR_ONLY || ( $MAIL_ON_ERROR_ONLY && ( rc != 0 || ( $NOTIFY_UPDATE && $NEWS_AVAILABLE ) ) ) )); then

			writeToConsole $MSG_LEVEL_DETAILED $MSG_SENDING_EMAIL

			logItem "Sending eMail with program $EMAIL_PROGRAM and parms '$EMAIL_PARMS'"
			logItem "Parm1:$1 Parm2:$subject"
			logItem "Content: $content"

			local rc
			case $EMAIL_PROGRAM in
				$EMAIL_MAILX_PROGRAM)
					logItem "echo $content | $EMAIL_PROGRAM $EMAIL_PARMS -s $subject $attach $EMAIL"
					echo "$content" | "$EMAIL_PROGRAM" $EMAIL_PARMS -s "$subject" $attach "$EMAIL"
					rc=$?
					logItem "$EMAIL_PROGRAM: RC: $rc"
					;;
				$EMAIL_SENDEMAIL_PROGRAM)
					logItem "echo $content | $EMAIL_PROGRAM $EMAIL_PARMS -u $subject $attach -t $EMAIL"
					echo "$content" | "$EMAIL_PROGRAM" $EMAIL_PARMS -u "$subject" $attach -t "$EMAIL"
					rc=$?
					logItem "$EMAIL_PROGRAM: RC: $rc"
					;;
				$EMAIL_SSMTP_PROGRAM|$EMAIL_MSMTP_PROGRAM)
					local msmtp_default=""
					if [[ $EMAIL_PROGRAM == $EMAIL_MSMTP_PROGRAM ]]; then
						msmtp_default="-a default"
					fi
					if (( $APPEND_LOG )); then
						logItem "Sending email with mpack"
						echo "$content" > /tmp/$$
						mpack -s "$subject" -d /tmp/$$ "$LOG_FILE" "$EMAIL"
						rm /tmp/$$ &>/dev/null
					else
						local sender=${SENDER_EMAIL:-root@$(hostname -f)}
						logItem "Sendig email with s/msmtp"
						logItem "echo -e To: $EMAIL\nFrom: $sender\nSubject: $subject\n$content | $EMAIL_PROGRAM $msmtp_default $EMAIL"
						echo -e "To: $EMAIL\nFrom: $sender\nSubject: $subject\n$content" | "$EMAIL_PROGRAM" $msmtp_default "$EMAIL"
						rc=$?
						logItem "$EMAIL_PROGRAM: RC: $rc"
					fi
					;;
				$EMAIL_EXTENSION_PROGRAM)
					local append=""
					(( $APPEND_LOG )) && append="$LOG_FILE"
					args=( "$EMAIL" "$subject" "$content" "$EMAIL_PARMS" "$append" )
					callExtensions $EMAIL_EXTENSION "${args[@]}"
					rc=$?
					;;
				*) assertionFailed $LINENO  "Unsupported email programm $EMAIL_PROGRAM detected"
					;;
			esac
		fi
		if (( $rc )) ; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_EMAIL_SEND_FAILED $EMAIL_PROGRAM $rc
		fi

	fi
	logExit

}

function noop() {
	:
}

function cleanupBackupDirectory() {

	logEntry

	if [[ $rc != 0 ]] || (( $FAKE_BACKUPS )); then

		if [[ $LOG_OUTPUT == $LOG_OUTPUT_BACKUPLOC ]]; then
			# save log in current directory because backup directory will be deleted
			if [[ -f $LOG_FILE ]]; then
				local user=$(findUser)
				[[ $user == "root" ]] && TARGET_LOG_FILE="/root/$LOG_FILE_NAME" || TARGET_LOG_FILE="/home/$user/$LOG_FILE_NAME"
				cp "$LOG_FILE" "$TARGET_LOG_FILE" &>/dev/null
				LOG_FILE="$TARGET_LOG_FILE"
				if [[ $user != "root" ]]; then
					chown --reference=/home/$user "$TARGET_LOG_FILE"
				fi
			fi
			if [[ -f $MSG_FILE ]]; then
				local user=$(findUser)
				[[ $user == "root" ]] && TARGET_MSG_FILE="/root/$MSG_FILE_NAME" || TARGET_MSG_FILE="/home/$user/$MSG_FILE_NAME"
				cp "$MSG_FILE" "$TARGET_MSG_FILE" &>/dev/null
				MSG_FILE="$TARGET_MSG_FILE"
				if [[ $user != "root" ]]; then
					chown --reference=/home/$user "$TARGET_MSG_FILE"
				fi
			fi
		fi

		if [[ -d "$BACKUPTARGET_DIR" ]]; then
			if [[ -z "$BACKUPPATH" || -z "$BACKUPFILE" || -z "$BACKUPTARGET_DIR" || "$BACKUPFILE" == *"*"* || "$BACKUPPATH" == *"*"* || "$BACKUPTARGET_DIR" == *"*"* ]]; then
				assertionFailed $LINENO "Invalid backup path detected. BP: $BACKUPPATH - BTD: $BACKUPTARGET_DIR - BF: $BACKUPFILE"
			fi
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_REMOVING_BACKUP "$BACKUPTARGET_DIR"
			logItem "$(ls -la $BACKUPTARGET_DIR)"
			exec >&3 2>&4 # free logfile in backup dir
			rm -rf $BACKUPTARGET_DIR # delete incomplete backupdir
			local rmrc=$?
			if (( $rmrc != 0 )); then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_REMOVING_BACKUP_FAILED "$BACKUPTARGET_DIR" "$rmrc"
			fi
			# resume logging of output into log file now residing in home directory
			exec 1>> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE")
			exec 2>> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE" >&2)
		fi
	fi

	writeToConsole $MSG_LEVEL_DETAILED $MSG_SAVED_MSG "$MSG_FILE"
	if (( $LOG_LEVEL == $LOG_DEBUG )); then
		writeToConsole $MSG_LEVEL_DETAILED $MSG_SAVED_LOG "$LOG_FILE"
	fi

	logExit
}

function cleanup() { # trap

	logEntry

	if [[ $1 == "SIGINT" ]]; then
		# ignore CTRL-C now
		trap '' SIGINT SIGTERM EXIT
		rc=$RC_CTRLC
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_CTRLC_DETECTED
	fi

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_CLEANING_UP

	rc=${rc:-42}	# some failure during startup of script (RT error, option validation, ...)

	CLEANUP_RC=$rc

	if (( $RESTORE )); then
		cleanupRestore $1
	else
		cleanupBackup $1
	fi

	cleanupTempFiles

	if (( ! $RESTORE )); then
		_no_more_locking
	fi

	logItem "Terminate now with rc $CLEANUP_RC"
	(( $CLEANUP_RC == 0 )) && saveVars

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_STOPPED "$HOSTNAME" "$MYSELF" "$VERSION" "$GIT_COMMIT_ONLY" "$(date)"

	exit $CLEANUP_RC

	logExit

}

function cleanupRestore() { # trap

	logEntry

	local error=0

	logItem "Got trap $1"
	logItem "rc: $rc"

	rm $$.sfdisk &>/dev/null

	if [[ -n $MNT_POINT ]]; then
		if isMounted $MNT_POINT; then
			logItem "Umount $MNT_POINT"
			umount $MNT_POINT &>>"$LOG_FILE"
		fi

		logItem "Deleting dir $MNT_POINT"
		rmdir $MNT_POINT &>>"$LOG_FILE"
	fi

	if (( ! $PARTITIONBASED_BACKUP )); then
		umount $BOOT_PARTITION &>>"$LOG_FILE"
		umount $ROOT_PARTITION &>>"$LOG_FILE"
	fi

	if (( rc != 0 )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_FAILED $rc
	else
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_OK
	fi

	logExit "$rc"

}

function resizeRootFS() {

	logEntry

	local partitionStart

	logItem "RESTORE_DEVICE: $RESTORE_DEVICE"
	logItem "ROOT_PARTITION: $ROOT_PARTITION"

	logItem "partitionLayout of $RESTORE_DEVICE"
	logItem "$(fdisk -l $RESTORE_DEVICE)"

	partitionStart="$(fdisk -l $RESTORE_DEVICE |  grep -E '/dev/((mmcblk|loop)[0-9]+p|sd[a-z])2(\s+[[:digit:]]+){3}' | awk '{ print $2; }')"

	logItem "PartitionStart: $partitionStart"

	if [[ -z "$partitionStart" ]]; then
		writeToConsole $MSG_LEVEL_DETAILED $MSG_UNABLE_TO_CREATE_PARTITIONS "Partitionstart of second partition of ${RESTORE_DEVICE} not found"
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

	logExit
}

function extractVersionFromFile() { # fileName
	echo $(grep "^VERSION=" "$1" | cut -f 2 -d = | sed  -e "s/\"//g" -e "s/#.*//")
}

function revertScriptVersion() {

	logEntry

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

	logExit

}

function isBetaAvailable() {

	logEntry

	local betaVersion=""

	if (( $NEW_PROPERTIES_FILE )); then
		betaVersion=${BETA_PROPERTY//\"/}
	fi

	echo $betaVersion

	logExit "$betaVersion"

}

function cleanupBackup() { # trap

	logEntry

	logItem "Got trap $1"
	logItem "rc: $rc"

	if (( $PARTITIONBASED_BACKUP )); then
		umountSDPartitions "$TEMPORARY_MOUNTPOINT_ROOT"
	fi

	cleanupBackupDirectory

	if (( $rc != 0 )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_FAILED

		echo "Invocation parms: '$INVOCATIONPARMS'" >> "$LOG_FILE"

		if (( $rc == $RC_STOP_SERVICES_ERROR )) || (( $STOPPED_SERVICES )) || (( $BEFORE_STOPPED_SERVICES )); then
			startServices "noexit"
			executeAfterStartServices "noexit"
		fi

		if [[ $rc != $RC_CTRLC && $rc != $RC_EMAILPROG_ERROR ]]; then
			msg=$(getLocalizedMessage $MSG_BACKUP_FAILED)
			msgTitle=$(getLocalizedMessage $MSG_TITLE_ERROR $HOSTNAME)
			sendEMail "$msg" "$msgTitle"
		fi

	else

		if (( ! $MAIL_ON_ERROR_ONLY )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_OK
		fi

		msg=$(getLocalizedMessage $MSG_TITLE_OK $HOSTNAME)
		sendEMail "" "$msg"
	fi

	logExit

}

function cleanupTempFiles() {

	logEntry

	if [[ -f $MYSELF~ ]]; then
		logItem "Removing new version $MYSELF~"
		rm -f $MYSELF~ &>/dev/null
	fi

	logExit

}

function checkAndCorrectImportantParameters() {

		local invalidOutput=""
		local invalidLanguage=""
		local invalidLogLevel=""
		local invalidMsgLevel=""

		if [[ "$LOG_OUTPUT" =~ ^[0-9]$ ]]; then
			if (( $LOG_OUTPUT < 0 || $LOG_OUTPUT > ${#LOG_OUTPUT_LOCs[@]} )); then
				invalidOutput="$LOG_OUTPUT"
				LOG_OUTPUT=$LOG_OUTPUT_BACKUPLOC
			fi
		else
			if ! touch "$LOG_OUTPUT" &>/dev/null; then
				invalidOutput="$LOG_OUTPUT"
				LOG_OUTPUT=$LOG_OUTPUT_BACKUPLOC
			fi
		fi

		if [[ "$LOG_LEVEL" =~ ^[0-9]$ ]]; then
			if (( $LOG_LEVEL < 0 || $LOG_LEVEL > ${#LOG_LEVELs[@]} )); then
				invalidLogLevel="$LOG_LEVEL"
				LOG_LEVEL=$LOG_DEBUG
			fi
		else
			invalidLogLevel="$LOG_LEVEL"
			LOG_LEVEL=$LOG_DEBUG
		fi

		[[ $LOG_LEVEL == $LOG_TYPE_DEBUG ]] && MSG_LEVEL=$MSG_LEVEL_DETAILED

		if [[ "$MSG_LEVEL" =~ ^[0-9]$ ]]; then
			if (( $MSG_LEVEL < 0 || $MSG_LEVEL > ${#MSG_LEVELs[@]} )); then
				invalidMsgLevel="$MSG_LEVEL"
				MSG_LEVEL=$MSG_LEVEL_DETAILED
			fi
		else
			invalidMsgLevel="$MSG_LEVEL"
			MSG_LEVEL=$MSG_LEVEL_DETAILED
		fi

		if [[ ! $LANGUAGE =~ $MSG_SUPPORTED_REGEX ]]; then
			invalidLanguage="$LANGUAGE"
			LANGUAGE=$MSG_LANG_FALLBACK
		fi

		[[ -n $invalidOutput ]] && writeToConsole $MSG_LEVEL_MINIMAL $MSG_INVALID_LOG_OUTPUT "$invalidOutput" "${LOG_OUTPUTs[$LOG_OUTPUT]}"
		[[ -n $invalidMsgLevel ]] && writeToConsole $MSG_LEVEL_MINIMAL $MSG_INVALID_MSG_LEVEL "$invalidMsgLevel" "${MSG_LEVELs[$MSG_LEVEL]}"
		[[ -n $invalidLanguage ]] && writeToConsole $MSG_LEVEL_MINIMAL $MSG_LANGUAGE_NOT_SUPPORTED "$invalidLanguage" "$LANGUAGE"
		[[ -n $invalidLogLevel ]] &&  writeToConsole $MSG_LEVEL_MINIMAL $MSG_INVALID_LOG_LEVEL "$invalidLogLevel" "${LOG_LEVELs[$LOG_LEVEL]}"

}

function createLinks() { # backuptargetroot extension newfile

	logEntry "$1 $2 $3"
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

	logExit
}

function bootPartitionBackup() {

		logEntry

		local p rc

		logItem "Starting boot partition backup..."

		writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_CREATING_PARTITION_INFO

		if (( ! $FAKE && ! $EXCLUDE_DD && ! $SHARED_BOOT_DIRECTORY )); then
			local ext=$BOOT_DD_EXT
			(( $TAR_BOOT_PARTITION_ENABLED )) && ext=$BOOT_TAR_EXT
			if  [[ ! -e "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.$ext" ]]; then
				writeToConsole $MSG_LEVEL_DETAILED $MSG_CREATING_BOOT_BACKUP "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.$ext"
				if (( $FAKE_BACKUPS )); then
					touch "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.$ext"
				else
					if (( $TAR_BOOT_PARTITION_ENABLED )); then
						cmd="tar $TAR_BACKUP_OPTIONS -f \"$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.$ext\" /boot"
					else
						cmd="dd if=/dev/${BOOT_PARTITION_PREFIX}1 of=\"$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.$ext\" bs=1M"
					fi

					executeCommand "$cmd"
					rc=$?
					if [ $rc != 0 ]; then
						writeToConsole $MSG_LEVEL_MINIMAL $MSG_IMG_BOOT_BACKUP_FAILED "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.$ext" "$rc"
						exitError $RC_DD_IMG_FAILED
					fi
				fi

				if (( $LINK_BOOTPARTITIONFILES )); then
					createLinks "$BACKUPTARGET_ROOT" $ext "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.$ext"
				fi

			else
				logItem "Found existing backup of boot partition $BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.$ext ..."
				writeToConsole $MSG_LEVEL_DETAILED $MSG_EXISTING_BOOT_BACKUP "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.$ext"
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

		logExit

}
function partitionLayoutBackup() {

		logEntry

		local p rc

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

		logExit

}

function ddBackup() {

	logEntry

	local cmd verbose partition fakecmd

	(( $VERBOSE )) && verbose="-v" || verbose=""

	if (( $PARTITIONBASED_BACKUP )); then
		fakecmd="touch \"${BACKUPTARGET_DIR}/$partitionName${FILE_EXTENSION[$BACKUPTYPE]}\""

		partition="${BOOT_DEVICENAME}p$1"
		partitionName="${BOOT_PARTITION_PREFIX}$1"

		if [[ $BACKUPTYPE == $BACKUPTYPE_DDZ ]]; then
			if (( $PARTITION )); then
				cmd="dd if=$partition bs=$DD_BLOCKSIZE $DD_PARMS | pv -fs $(fdisk -l $partition | grep "Disk.*$partition" | cut -d ' ' -f 5) | gzip ${verbose} > \"${BACKUPTARGET_DIR}/$partitionName${FILE_EXTENSION[$BACKUPTYPE]}\""
			else
				cmd="dd if=$partition bs=$DD_BLOCKSIZE $DD_PARMS | gzip ${verbose} > \"${BACKUPTARGET_DIR}/$partitionName${FILE_EXTENSION[$BACKUPTYPE]}\""
			fi
		else
			if (( $PROGRESS )); then
				cmd="dd if=$partition bs=$DD_BLOCKSIZE $DD_PARMS | pv -fs $(fdisk -l $partition | grep "Disk.*$partition" | cut -d ' ' -f 5) | dd of=\"${BACKUPTARGET_DIR}/$partitionName${FILE_EXTENSION[$BACKUPTYPE]}\""
			else
				cmd="dd if=$partition bs=$DD_BLOCKSIZE $DD_PARMS of=\"${BACKUPTARGET_DIR}/$partitionName${FILE_EXTENSION[$BACKUPTYPE]}\""
			fi
		fi

	else
		fakecmd="touch \"$BACKUPTARGET_FILE\""

		if (( ! $DD_BACKUP_SAVE_USED_PARTITIONS_ONLY )); then
			if [[ $BACKUPTYPE == $BACKUPTYPE_DDZ ]]; then
				if (( $PROGRESS )); then
					cmd="dd if=$BOOT_DEVICENAME bs=$DD_BLOCKSIZE $DD_PARMS | pv -fs $(fdisk -l $BOOT_DEVICENAME | grep "Disk.*$BOOT_DEVICENAME" | cut -d ' ' -f 5) | gzip ${verbose} > \"$BACKUPTARGET_FILE\""
				else
					cmd="dd if=$BOOT_DEVICENAME bs=$DD_BLOCKSIZE $DD_PARMS | gzip ${verbose} > \"$BACKUPTARGET_FILE\""
				fi
			else
				if (( $PROGRESS )); then
					cmd="dd if=$BOOT_DEVICENAME bs=$DD_BLOCKSIZE $DD_PARMS | pv -fs $(fdisk -l $BOOT_DEVICENAME | grep "Disk.*$BOOT_DEVICENAME" | cut -d ' ' -f 5) | dd of=\"$BACKUPTARGET_FILE\""
				else
					cmd="dd if=$BOOT_DEVICENAME bs=$DD_BLOCKSIZE $DD_PARMS of=\"$BACKUPTARGET_FILE\""
				fi
			fi
		else
			logItem "fdisk$NL$(fdisk -l $BOOT_DEVICENAME)"
			local lastByte=$(lastUsedPartitionByte $BOOT_DEVICENAME)
			if (( lastByte == 0 )); then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_TRUNCATING_ERROR "$sdcardSizeHuman" "$spaceUsedHuman"
				exitError $RC_MISC_ERROR
			fi
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
			if [[ $BACKUPTYPE == $BACKUPTYPE_DDZ ]]; then
				executeCommandNoStdoutRedirect "$cmd"
			else
				executeCommand "$cmd"
			fi
			rc=$?
		else
			rc=0
		fi
	fi

	logExit  "$rc"

	return $rc
}

function tarBackup() {

	local verbose zip cmd partition source target fakecmd devroot sourceDir

	logEntry

	(( $PROGRESS )) && VERBOSE=1

	(( $VERBOSE )) && verbose="-v" || verbose=""
	[[ $BACKUPTYPE == $BACKUPTYPE_TGZ ]] && zip="-z" || zip=""

	if (( $PARTITIONBASED_BACKUP )); then
		partition="${BOOT_PARTITION_PREFIX}$1"
		source="."
		devroot="."
		sourceDir="$TEMPORARY_MOUNTPOINT_ROOT/$partition"
		target="\"${BACKUPTARGET_DIR}/$partition${FILE_EXTENSION[$BACKUPTYPE]}\""
	else
		bootPartitionBackup
		source="/"
		devroot=""
		target="\"$BACKUPTARGET_FILE\""
	fi

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_MAIN_BACKUP_PROGRESSING $BACKUPTYPE "${target//\\/}"

	local log_file="${LOG_FILE/\//}" # remove leading /
	local msg_file="${MSG_FILE/\//}" # remove leading /

	cmd="tar \
		$TAR_BACKUP_OPTIONS \
		$TAR_BACKUP_ADDITIONAL_OPTIONS \
		${zip} \
		${verbose} \
		-f $target \
		--warning=no-xdev \
		--numeric-owner \
		--exclude=\"$BACKUPPATH_PARAMETER/*\" \
		--exclude=\"$source/$log_file\" \
		--exclude=\"$source/$msg_file\" \
		--exclude='.gvfs' \
		--exclude=$devroot/proc/* \
		--exclude=$devroot/lost+found/* \
		--exclude=$devroot/sys/* \
		--exclude=$devroot/dev/* \
		--exclude=$devroot/tmp/* \
		--exclude=$devroot/boot/* \
		--exclude=$devroot/run/* \
		$EXCLUDE_LIST \
		$source"

	(( $PARTITIONBASED_BACKUP )) && pushd $sourceDir &>>$LOG_FILE

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_STARTED "$BACKUPTYPE"

	if (( $FAKE_BACKUPS )); then
		fakecmd="touch $target"
		executeCommand "$fakecmd"
		rc=0
	elif (( ! $FAKE )); then
		executeCommand "${cmd}" "$TAR_IGNORE_ERRORS"
		rc=$?
	fi

	(( $PARTITIONBASED_BACKUP )) && popd &>>$LOG_FILE

	logExit  "$rc"

	return $rc
}

function rsyncBackup() { # partition number (for partition based backup)

	local verbose partition target source fakecmd faketarget excludeRoot cmd cmdParms

	logEntry

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
		excludeRoot=""
	fi

	logItem "LastBackupDir: $lastBackupDir"

	LINK_DEST=""
	if (( $USE_HARDLINKS && $ROOT_HARDLINKS_SUPPORTED )); then
		[[ -n "$lastBackupDir" ]] && LINK_DEST="--link-dest=\"$lastBackupDir\""
	fi

	logItem "LinkDest: $LINK_DEST"

	if [[ -n $LINK_DEST ]]; then
		writeToConsole $MSG_LEVEL_DETAILED $MSG_HARDLINK_DIRECTORY_USED "$lastBackupDir"
	fi

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_MAIN_BACKUP_PROGRESSING $BACKUPTYPE "${target//\\/}"

	local log_file="${LOG_FILE/\//}" # remove leading /
	local msg_file="${MSG_FILE/\//}" # remove leading /

	cmdParms="--exclude=\"$BACKUPPATH_PARAMETER\" \
			--exclude=\"$excludeRoot/$log_file\" \
			--exclude=\"$excludeRoot/$msg_file\" \
			--exclude='.gvfs' \
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
		rc=0
	elif (( ! $FAKE )); then
		executeCommand "$cmd" "$RSYNC_IGNORE_ERRORS"
		rc=$?
	fi

	logExit  "$rc"

}

function restore() {

	logEntry

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
			mkdir -p $MNT_POINT/boot

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

				if (( ! $ROOT_PARTITION_DEFINED )) && (( $RESIZE_ROOTFS )); then
					local sourceSDSize=$(calcSumSizeFromSFDISK "$SF_FILE")
					local targetSDSize=$(blockdev --getsize64 $RESTORE_DEVICE)
					logItem "sourceSDSize: $sourceSDSize - targetSDSize: $targetSDSize"

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

						if [[ "$(bytesToHuman $oldPartitionSourceSize)" != "$(bytesToHuman $newTargetPartitionSize)" ]]; then
							writeToConsole $MSG_LEVEL_MINIMAL $MSG_ADJUSTING_SECOND "$(bytesToHuman $oldPartitionSourceSize)" "$(bytesToHuman $newTargetPartitionSize)"
						fi

						resizeRootFS
					fi

					logItem "--- partprobe ---"
					partprobe $RESTORE_DEVICE &>>$LOG_FILE
					logItem "--- udevadm ---"
					udevadm settle &>>$LOG_FILE
					rm $$.sfdisk &>/dev/null
				fi

			fi

			if [[ -e $TAR_FILE ]]; then
				writeToConsole $MSG_LEVEL_DETAILED $MSG_FORMATTING_FIRST_PARTITION "$BOOT_PARTITION"
				mkfs.vfat $BOOT_PARTITION &>>$LOG_FILE
				rc=$?
				if [ $rc != 0 ]; then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_IMG_BOOT_CREATE_PARTITION_FAILED "$rc"
					exitError $RC_NATIVE_RESTORE_FAILED
				fi
			fi

			writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORING_FIRST_PARTITION "$BOOT_PARTITION"

			local ext=$BOOT_DD_EXT
			if [[ -e "$DD_FILE" ]]; then
				logItem "Restoring boot partition from $DD_FILE"
				if (( $PROGRESS )); then
					dd if="$DD_FILE" 2>> $LOG_FILE | pv -fs $(stat -c %s "$DD_FILE") | dd of=$BOOT_PARTITION bs=1M &>>"$LOG_FILE"
				else
					dd if="$DD_FILE" of=$BOOT_PARTITION bs=1M &>>"$LOG_FILE"
				fi
				rc=$?
			else
				ext=$BOOT_TAR_EXT
				logItem "Restoring boot partition from $TAR_FILE to $BOOT_PARTITION"
				mount $BOOT_PARTITION "$MNT_POINT/boot"
				pushd "$MNT_POINT" &>>"$LOG_FILE"
				if (( $PROGRESS )); then
					cmd="pv -f $TAR_FILE | tar -xf -"
				else
					cmd="tar -xf  \"$TAR_FILE\""
				fi
				executeCommand "$cmd"
				rc=$?
				popd &>>"$LOG_FILE"
			fi

			if [ $rc != 0 ]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_IMG_BOOT_RESTORE_FAILED ".$ext" "$rc"
				exitError $RC_NATIVE_RESTORE_FAILED
			fi

			writeToConsole $MSG_LEVEL_DETAILED $MSG_FORMATTING_SECOND_PARTITION "$ROOT_PARTITION"
			local check=""
			if (( $CHECK_FOR_BAD_BLOCKS )); then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_DETAILED_ROOT_CHECKING "$ROOT_PARTITION"
				check="-c"
				mkfs.ext4 $check $ROOT_PARTITION
			else
				mkfs.ext4 $check $ROOT_PARTITION &>>$LOG_FILE
			fi
			rc=$?
			if [ $rc != 0 ]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_IMG_ROOT_CREATE_PARTITION_FAILED "$rc"
				exitError $RC_NATIVE_RESTORE_FAILED
			fi

			writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORING_SECOND_PARTITION "$ROOT_PARTITION"
			mount $ROOT_PARTITION "$MNT_POINT"

			case $BACKUPTYPE in

				$BACKUPTYPE_TAR|$BACKUPTYPE_TGZ)
					local archiveFlags="--same-owner --same-permissions --numeric-owner ${TAR_RESTORE_ADDITIONAL_OPTIONS}"

					pushd "$MNT_POINT" &>>"$LOG_FILE"
					[[ $BACKUPTYPE == $BACKUPTYPE_TGZ ]] && zip="z" || zip=""
					if (( $PROGRESS )); then
						cmd="pv -f $ROOT_RESTOREFILE | tar --exclude /boot ${archiveFlags} -x${verbose}${zip}f -"
					else
						cmd="tar --exclude /boot ${archiveFlags} -x${verbose}${zip}f \"$ROOT_RESTOREFILE\""
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

			writeToConsole $MSG_LEVEL_DETAILED $MSG_IMG_ROOT_CHECK_STARTED
			umount $ROOT_PARTITION &>>$LOG_FILE
			fsck -av $ROOT_PARTITION &>>$LOG_FILE
			rc=$?
			if (( $rc > 1 )); then # 1: => Filesystem errors corrected
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_IMG_ROOT_CHECK_FAILED "$rc"
				exitError $RC_NATIVE_RESTORE_FAILED
			fi
			mount $ROOT_PARTITION $MNT_POINT &>>$LOG_FILE

			logItem "Updating hw clock"
			echo $(date -u +"%Y-%m-%d %T") > $MNT_POINT/etc/fake-hwclock.data

			logItem "Force fsck on reboot"
			touch $MNT_POINT/forcefsck

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

	logExit "$rc"

}

function backup() {

	logEntry

	logger -t $MYSELF "Starting backup..."

	executeBeforeStopServices
	stopServices
	callExtensions $PRE_BACKUP_EXTENSION "0"

	BACKUPPATH_PARAMETER="$BACKUPPATH"
	BACKUPPATH="$BACKUPPATH/$HOSTNAME"
	if [[ ! -d "$BACKUPPATH" ]] && (( !$FAKE )); then
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

	if (( ! $REGRESSION_TEST )) ; then
		logItem "mount:$NL$(mount)"
		logItem "df -h:$NL$(df -h)"
		logItem "blkid:$NL$(blkid)"
	fi

	if [[ -f $BOOT_DEVICENAME ]]; then
		logItem "fdisk -l $BOOT_DEVICENAME"
		logItem "$(fdisk -l $BOOT_DEVICENAME)"
	fi

	if [[ -f "/boot/cmdline.txt" ]]; then
		logItem "/boot/cmdline.txt"
		logItem "$(cat /boot/cmdline.txt)"
	fi

	logItem "Starting $BACKUPTYPE backup..."

	rc=0

	callExtensions $READY_BACKUP_EXTENSION $rc

	START_TIME=$(date +%s)

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
	END_TIME=$(date +%s)

	BACKUP_TIME=($(duration $START_TIME $END_TIME))
	logItem "Backuptime: $BACKUP_TIME"
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_TIME "${BACKUP_TIME[1]}" "${BACKUP_TIME[2]}" "${BACKUP_TIME[3]}"

	logItem "Syncing"
	sync
	logItem "Finished $BACKUPTYPE backup"

	logItem "Backup created with return code: $rc"

	logItem "Current directory: $(pwd)"
	if [[ -z $BACKUPPATH || "$BACKUPPATH" == *"*"* ]]; then
		assertionFailed $LINENO "Unexpected backup path $BACKUPPATH"
	fi

	if [[ $rc -eq 0 ]]; then

		local bt="${BACKUPTYPE^^}"
		local v="KEEPBACKUPS_${bt}"
		local keepOverwrite="${!v}"

		local keepBackups=$KEEPBACKUPS
		(( $keepOverwrite != 0 )) && keepBackups=$keepOverwrite

		if (( $keepBackups != -1 )); then
			logItem "Deleting oldest directory in $BACKUPPATH"
			logItem "pre - ls$NL$(ls -d $BACKUPPATH/* 2>/dev/null)"

			writeToConsole $MSG_LEVEL_DETAILED $MSG_BACKUPS_KEPT "$keepBackups" "$BACKUPTYPE"

			if (( ! $FAKE )); then
				pushd "$BACKUPPATH" 1>/dev/null; ls -d *-$BACKUPTYPE-* 2>/dev/null| grep -vE "\.{log|msg}$" | head -n -$KEEPBACKUPS | xargs -I {} rm -rf "{}" 2>>"$LOG_FILE"; popd > /dev/null

				local regex="\-([0-9]{8}\-[0-9]{6})\.(img|mbr|sfdisk|log)$"
				local regexDD="\-dd\-backup\-([0-9]{8}\-[0-9]{6})\.img$"

				pushd "$BACKUPPATH" 1>/dev/null
				for imgFile in $(ls -d *.img *.mbr *.sfdisk *.log *.msg 2>/dev/null); do

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
					local file=$(ls -d *-*-backup-$date* 2>/dev/null| egrep -v "\.(log|msg|img|mbr|sfdisk)$");

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
		else
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_ALL_BACKUPS_KEPT "$BACKUPTYPE"
		fi

	fi

	callExtensions $POST_BACKUP_EXTENSION $rc
	startServices
	executeAfterStartServices

	logger -t $MYSELF "Backup finished"
	logExit

}

function mountSDPartitions() { # sourcePath

	local partition partitionName
	logEntry

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
	logExit
}

function umountSDPartitions() { # sourcePath

	local partitionName partition
	logEntry
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
	logExit
}

function backupPartitions() {

	logEntry

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

	logExit "$rc"

}

function doit() {

	logEntry

	local msg
	logItem "Startingdirectory: $(pwd)"
	logItem "fdisk -l$NL$(fdisk -l | grep -v "^$" 2>/dev/null)"
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

	logExit

}

function collectPartitions() {

	logEntry

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
		PARTITIONS_TO_BACKUP=($PARTITIONS_TO_BACKUP)
		backupAllPartitions=0
	fi

	logItem "backupAllPartitions: $backupAllPartitions"

	local mountLine partition size type
	local line
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

	logExit

}

function checksForPartitionBasedBackup() {

	local partition

	logEntry

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

	logExit

}

function commonChecks() {

	logEntry

	if [[ -n "$EMAIL" ]]; then
		if [[ ! $EMAIL_PROGRAM =~ $SUPPORTED_EMAIL_PROGRAM_REGEX ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_EMAIL_PROG_NOT_SUPPORTED "$EMAIL_PROGRAM" "$SUPPORTED_MAIL_PROGRAMS"
			exitError $RC_EMAILPROG_ERROR
		fi
		if [[ ! $(which $EMAIL_PROGRAM) && ( $EMAIL_PROGRAM != $EMAIL_EXTENSION_PROGRAM ) ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_MAILPROGRAM_NOT_INSTALLED $EMAIL_PROGRAM
			exitError $RC_EMAILPROG_ERROR
		fi
		if [[ (( "$MAIL_PROGRAM" == $EMAIL_SSMTP_PROGRAM || "$MAIL_PROGRAM" == $EMAIL_MSMTP_PROGRAM )) && (( $APPEND_LOG )) ]]; then
			if ! which mpack &>/dev/null; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_MPACK_NOT_INSTALLED
				APPEND_LOG=0
			fi
		fi
	fi

	logExit

}

function getRootPartition() {

	logEntry
#	cat /proc/cmdline
#	dma.dmachans=0x7f35 bcm2708_fb.fbwidth=656 bcm2708_fb.fbheight=416 bcm2708.boardrev=0xf bcm2708.serial=0x3f3c9490 smsc95xx.macaddr=B8:27:EB:3C:94:90 bcm2708_fb.fbswap=1 sdhci-bcm2708.emmc_clock_freq=250000000 vc_mem.mem_base=0x1fa00000 vc_mem.mem_size=0x20000000  dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline rootwait

	local cmdline=$(cat /proc/cmdline)
	logItem "cat /proc/cmdline$NL$(cat /proc/cmdline)"
	if [[ $cmdline =~ .*(imgpart|root)=([^ ]+) ]]; then
		ROOT_PARTITION=${BASH_REMATCH[2]}
		logItem "RootPartition: $ROOT_PARTITION"
	else
		assertionFailed $LINENO "Unable to find root mountpoint in /proc/cmdline"
	fi
	logExit "$ROOT_PARTITION"

}

# retrieve various information for a partition, e.g. /dev/mmcblk0p1 or /dev/sda2
#
# 1: device (mmcblk0 or sda)
# 2: partition number (1 or 2)
#

function deviceInfo() { # device, e.g. /dev/mmcblk1p2 or /dev/sda3, returns 0:device (mmcblk0), 1: partition number

	logEntry "$1"
	local r=""

	if [[ $1 =~ ^/dev/([^0-9]+)([0-9]+)$ || $1 =~ ^/dev/([^0-9]+[0-9]+)p([0-9]+)$ ]]; then
		r="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
	fi

	echo "$r"
	logExit "$r"
}

function inspect4Backup() {

	logEntry

	logItem "ls /dev/mmcblk*:${NL}$(ls -1 /dev/mmcblk* 2>/dev/null)"
	logItem "ls /dev/sd*:${NL}$(ls -1 /dev/sd* 2>/dev/null)"
	logItem "mountpoint /boot: $(mountpoint -d /boot) mountpoint /: $(mountpoint -d /)"

	if (( $REGRESSION_TEST || $RESTORE )); then
		BOOT_DEVICE="mmcblk0"

	else

		logItem "Legacy boot discovery"

		part=$(for d in $(find /dev -type b); do [ "$(mountpoint -d /boot)" = "$(mountpoint -x $d)" ] && echo $d && break; done)
		logItem "part: $part"
		local bootDeviceNumber=$(mountpoint -d /boot)
		local rootDeviceNumber=$(mountpoint -d /)
		logItem "bootDeviceNumber: $bootDeviceNumber"
		logItem "rootDeviceNumber: $rootDeviceNumber"
		if [ "$bootDeviceNumber" == "$rootDeviceNumber" ]; then	# /boot on same partition with root partition /
			local rootDevice=$(for file in $(find /sys/dev/ -name $rootDeviceNumber); do source ${file}/uevent; echo $DEVNAME; done) # mmcblk0p1
			logItem "Rootdevice: $rootDevice"
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_SHARED_BOOT_DEVICE "$rootDevice"
			SHARED_BOOT_DIRECTORY=1
			BOOT_DEVICE=${rootDevice/p*/} # mmcblk0
		elif [[ "$part" =~ /dev/(sd[a-z]) || "$part" =~ /dev/(mmcblk[0-9])p ]]; then
			BOOT_DEVICE=${BASH_REMATCH[1]}
		else

			logItem "Starting alternate boot discovery"

			# test whether boot device is mounted
			local bootMountpoint="/boot"
			local bootPartition=$(findmnt $bootMountpoint -o source -n) # /dev/mmcblk0p1, /dev/loop01p or /dev/sda1
			logItem "$bootMountpoint mounted? $bootPartition"

			# test whether some other /boot path is mounted
			if [[ -z $bootPartition ]]; then
				bootPartition=$(mount | grep "/boot" | cut -f 1 -d ' ')
				bootMountpoint=$(mount | grep "/boot" | cut -f 3 -d ' ')
				logItem "Some path in /boot mounted? $bootPartition on $bootMountpoint"
			fi

			# find root partition
			local rootPartition=$(findmnt / -o source -n) # /dev/root or /dev/sda1 or /dev/mmcblk1p1
			logItem "/ mounted? $rootPartition"
			if [[ $rootPartition == "/dev/root" ]]; then
				local rp=$(grep -E -o "root=[^ ]+" /proc/cmdline)
				rootPartition=${rp#/root=/}
				logItem "/ mounted as /dev/root: $rootPartition"
			fi

			# check for /boot on root partition
			if [[ -z "$bootPartition" ]]; then
				if ! find $bootMountpoint -name cmdline.txt; then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_BOOTDEVICE_FOUND
					exitError $RC_MISC_ERROR
				else
					bootPartition="$rootPartition"
					logItem "Bootpartition is located on rootpartition $bootPartition"
				fi
			fi

			boot=( $(deviceInfo "$bootPartition") )
			root=( $(deviceInfo "$rootPartition") )

			logItem "boot: ${boot[@]}"
			logItem "root: ${root[@]}"

			if [[  -z "$boot" || -z "$root" ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_BOOT_DEVICE_DISOVERED
				exitError $RC_NO_BOOT_FOUND
			fi

			if [[ "${boot[@]}" == "${root[@]}" ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_SHARED_BOOT_DEVICE "$rootDevice"
				SHARED_BOOT_DIRECTORY=1
			fi

			BOOT_DEVICE="${boot[0]}"
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

	logExit
}

function inspect4Restore() {

	logEntry

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

	logExit

}

function reportNews() {

	logEntry

	if (( $NOTIFY_UPDATE )); then

		isUpdatePossible

		if (( ! $IS_BETA )); then
			local betaVersion=$(isBetaAvailable)
			if [[ -n $betaVersion && $VERSION != $betaVersion ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_BETAVERSION_AVAILABLE "$betaVersion"
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_VISIT_VERSION_HISTORY_PAGE "$(getLocalizedMessage $MSG_VERSION_HISTORY_PAGE)"
				NEWS_AVAILABLE=1
				BETA_AVAILABLE=1
			fi
		fi
	fi

	logExit

}

function doitBackup() {

	logEntry "$PARTITIONBASED_BACKUP"

	getRootPartition
	inspect4Backup

	commonChecks

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

	if [[ ! "$KEEPBACKUPS" =~ ^-?[0-9]+$ ]] || (( $KEEPBACKUPS < -1 || $KEEPBACKUPS > 365 || $KEEPBACKUPS == 0 )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_KEEPBACKUP_INVALID "$KEEPBACKUPS" "-k"
			mentionHelp
			exitError $RC_PARAMETER_ERROR
	fi

	local t
	local keepBackups
	for t in "${POSSIBLE_TYPES_ARRAY[@]}"; do
		local bt="${t^^}"
		local v="KEEPBACKUPS_${bt}"
		local keepOverwrite="${!v}"

		if [[ ! $keepOverwrite =~ ^-?[0-9]+$ ]] || (( $keepOverwrite < -1 || $keepOverwrite > 365 )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_KEEPBACKUP_INVALID "$keepOverwrite" "$v"
			mentionHelp
			exitError $RC_PARAMETER_ERROR
		fi
	done

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
		if ! which rsync &>/dev/null; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "rsync" "rsync"
			exitError $RC_MISSING_COMMANDS
		fi
		if (( ! $SKIP_RSYNC_CHECK )); then
			if ! supportsHardlinks "$BACKUPPATH"; then
				ROOT_HARDLINKS_SUPPORTED=0
				if (( $USE_HARDLINKS )); then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_HARDLINKS_USED "$BACKUPPATH"
				fi
			else
				ROOT_HARDLINKS_SUPPORTED=1
			fi
			if ! supportsSymlinks "$BACKUPPATH"; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILESYSTEM_INCORRECT "$BACKUPPATH" "softlinks"
				exitError $RC_PARAMETER_ERROR
			fi
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

	if (( $PROGRESS )) && [[ "$BACKUPTYPE" == "$BACKUPTYPE_DD" || "$BACKUPTYPE" == "$BACKUPTYPE_DDZ" ]] && [[ $(which pv &>/dev/null) ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "pv" "pv"
		exitError $RC_MISSING_COMMANDS
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

	local mps
	mps=$(grep "^LABEL=" /etc/fstab | cut -f 2)
	if grep -E "^/(boot)?[[:space:]]" <<< $mps; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_LABELS_NOT_SUPPORTED
		exitError $RC_MISC_ERROR
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

	logExit

}

function getPartitionTable() { # device

	logEntry "$1"
	logItem "$(IFS='' parted $1 unit MB p 2>>$LOG_FILE)"
	local table="$(IFS='' parted $1 unit MB p 2>>$LOG_FILE | sed -r '/^($|[MSDP])/d')"

	if [[ $(wc -l <<< "$table") < 2 ]]; then
		table=""
	fi
	echo "$table"

	logExit
}

function checkAndSetBootPartitionFiles() { # directory extension

	logEntry "$1 - $2"

	local prefix="$1/$2"

	DD_FILE="$prefix.$BOOT_DD_EXT"
	logItem "DD_FILE: $DD_FILE"
	TAR_FILE="$prefix.$BOOT_TAR_EXT"
	logItem "TAR_FILE: $TAR_FILE"
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
		if [[ ! -e "$DD_FILE" && ! -e "$TAR_FILE" ]]; then
			logItem "$DD_FILE/$TAR_FILE not found"
			(( errorCnt++ ))
		fi
		if [[ ! -e "$MBR_FILE" ]]; then
			logItem "$MBR_FILE not found"
			(( errorCnt++ ))
		fi
	fi

	logExit "$errorCnt"

	return $errorCnt

}

function findNonpartitionBackupBootAndRootpartitionFiles() {

	logEntry

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
			logExit
			return
		fi
	done

	for (( i=0; i<${#bootpartitionDirectory[@]}; i++ )); do
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_BOOTPATITIONFILES_NOT_FOUND "${bootpartitionDirectory[$i]}" "${bootpartitionExtension[$i]}"
	done
	logExit
	exitError $RC_MISC_ERROR

}

function restoreNonPartitionBasedBackup() {

	logEntry

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

	if ! askYesNo; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_ABORTED
		exitError $RC_RESTORE_FAILED
	fi

	restore

	logExit "$rc"

}

function restorePartitionBasedBackup() {

	logEntry

	local partition sourceSDSize targetSDSize

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
		logItem "$(mount | grep $RESTORE_DEVICE)"
		local dev
		while read dev; do echo $dev | cut -d ' ' -f 1; done < <(mount | grep $RESTORE_DEVICE)  | xargs umount
		logItem "$(mount | grep $RESTORE_DEVICE)"
	fi

	if (( ! $SKIP_SFDISK )); then
		local sourceSDSize=$(calcSumSizeFromSFDISK "$SF_FILE")
		local targetSDSize=$(blockdev --getsize64 $RESTORE_DEVICE)
		logItem "SourceSDSize: $sourceSDSize - targetSDSize: $targetSDSize"

		if (( targetSDSize < sourceSDSize )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_TARGETSD_SIZE_TOO_SMALL "$RESTORE_DEVICE" "$(bytesToHuman $targetSDSize)" "$(bytesToHuman $sourceSDSize)"
			exitError $RC_MISC_ERROR
		elif (( targetSDSize > sourceSDSize )); then
			local unusedSpace=$(( targetSDSize - sourceSDSize ))
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_TARGETSD_SIZE_BIGGER "$RESTORE_DEVICE" "$(bytesToHuman $targetSDSize)" "$(bytesToHuman $sourceSDSize)" "$(bytesToHuman $unusedSpace)"
		fi
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_REPARTITION_WARNING $RESTORE_DEVICE
	fi

	current_partition_table="$(getPartitionTable $RESTORE_DEVICE)"
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_CURRENT_PARTITION_TABLE "$RESTORE_DEVICE" "$current_partition_table"
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_WARN_RESTORE_PARTITION_DEVICE_OVERWRITTEN "$RESTORE_DEVICE"

	if ! askYesNo; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_ABORTED
		exitError $RC_RESTORE_FAILED
	fi

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_STARTED "$HOSTNAME" "$MYSELF" "$VERSION" "$GIT_COMMIT_ONLY" "$(date)"

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

	if isMounted "$MNT_POINT"; then
		logItem "$MNT_POINT mounted - unmouting"
		umount -f "$MNT_POINT" &>>$LOG_FILE
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
	logItem "$(fdisk -l $RESTORE_DEVICE)"

	logExit

}

# /dev/mmcblk0p1: LABEL="RECOVERY" UUID="B383-E246" TYPE="vfat"
# /dev/mmcblk0p3: LABEL="SETTINGS" UUID="9b35a9e6-d81f-4eff-9096-633297a5410b" TYPE="ext4"
# /dev/mmcblk0p5: LABEL="boot0" UUID="035A-9F64" TYPE="vfat"
# /dev/mmcblk0p6: LABEL="root" UUID="53df0f2a-3f9c-4b76-afc9-17c60989988d" TYPE="ext4"
# /dev/mmcblk0p7: LABEL="boot" UUID="56A8-F127" TYPE="vfat"
# /dev/mmcblk0p8: LABEL="root0" UUID="aa2fec4f-70ac-49b5-bc59-be0cf74b76d7" TYPE="ext4"

function getBackupPartitionLabel() { # partition

	logEntry "$1"

	local partition=$1
	local blkid label

	blkid=$(grep $partition "$BLKID_FILE")
	logItem "BLKID: $1 - $blkid"

	regexFormatLineLabel="^.*LABEL=\"([^\"]+)\".*$"

	if [[ $blkid =~ $regexFormatLineLabel ]]; then
		label=${BASH_REMATCH[1]}
	else
		label=$(sed -E 's/\/dev\///' <<< $partition)	# strip /dev/
	fi

	echo "$label"

	logExit "$label"

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

	logEntry "$1 $2"

	local partitionNo=$(sed -E "s%${BACKUP_BOOT_PARTITION_PREFIX}%%" <<< "$1")
	logItem "PartitionNo: $partitionNo"
	local parted element
	logItem "PARTED: $1 - $(<"$PARTED_FILE")"

	parted=$(grep "^$partitionNo" "$PARTED_FILE")
	logItem "PARTED: $1 - $parted"

	element=$(cut -d ":" -f $2 <<< $parted)

	echo "$element"

	logExit "$element"
}

function getBackupPartitionFilesystemSize() { # partition

	logEntry "$1"

	local size
	size=$(extractDataFromBackupPartedFile $1 "4")
	echo "$size"

	logExit "$size"

}

function getBackupPartitionFilesystem() { # partition

	logEntry "$1"

	local fileSystem
	fileSystem=$(extractDataFromBackupPartedFile $1 "5")
	echo "$fileSystem"

	logExit "$fileSystem"

}

function getPartitionBootFilesystem() { # partition_no

	logEntry "$1"

	local partitionNo=$1

	logItem "BOOT_DEVICENAME: $BOOT_DEVICENAME"

	local parted format
	logItem "PARTED: $1 - $(parted -m $BOOT_DEVICENAME print 2>/dev/null)"
	parted=$(grep "^${partitionNo}:" <(parted -m $BOOT_DEVICENAME print 2>/dev/null))
	logItem "PARTED: $1 - $parted"

	format=$(cut -d ":" -f 5 <<< $parted)

	echo "$format"

	logExit "$format"

}

function lastUsedPartitionByte() { # device

	logEntry "$1"

	local partitionregex="/dev/.*[p]?([0-9]+).*start=[^0-9]*([0-9]+).*size=[^0-9]*([0-9]+).*(Id|type)=[^0-9a-z]*([0-9a-z]+)"
	local lastUsedPartitionByte=0

	local line
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

			logItem "$p - $start - $size - $id"
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

	logExit "$lastUsedPartitionByte"

}

function restorePartitionBasedPartition() { # restorefile

	logEntry "$1"

	rc=0
	local verbose zip partitionLabel cmd

	local restoreFile="$1"
	local restorePartition="$(basename "$restoreFile")"

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
					if [[ "$BACKUPTYPE" == "$BACKUPTYPE_DD" ]]; then
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

					if [[ -n $fatSize  ]]; then
						local archiveFlags="--same-owner --same-permissions --numeric-owner ${TAR_RESTORE_ADDITIONAL_OPTIONS}"	# fat32 doesn't know about this
					fi

					pushd "$MNT_POINT" &>>"$LOG_FILE"
					[[ "$BACKUPTYPE" == "$BACKUPTYPE_TGZ" ]] && zip="z" || zip=""
					cmd="tar ${archiveFlags} -x${verbose}${zip}f \"$restoreFile\""

					if (( $PROGRESS )); then
						cmd="pv -f $restoreFile | $cmd -"
					fi
					executeCommand "$cmd"
					rc=$?
					popd &>>"$LOG_FILE"
					;;

				$BACKUPTYPE_RSYNC)
					local archiveFlags="aH"						# -a <=> -rlptgoD, H = preserve hardlinks
					[[ -n $fatSize  ]] && archiveFlags="rltD"	# no Hopg flags for fat fs
					cmdParms="--numeric-ids -${archiveFlags}X$verbose \"$restoreFile/\" $MNT_POINT"
					if (( $PROGRESS )); then
						cmd="rsync --info=progress2 $cmdParms"
					else
						cmd="rsync $cmdParms"
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
				umount -f $MNT_POINT &>>$LOG_FILE
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

	logExit

}

function doitRestore() {

	logEntry

	commonChecks

	if [[ ! -d "$RESTOREFILE" ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_DIRECTORY_NO_DIRECTORY "$RESTOREFILE"
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
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_DIRECTORY_INVALID "$RESTOREFILE"
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
	logItem "$(ls -1 "$RESTOREFILE"* 2>/dev/null)"

	if  ls -1 "$RESTOREFILE"* | egrep "^(sd[a-z]([0-9]+)|mmcblk[0-9]+p[0-9]+).*" 2>/dev/null ; then
		PARTITIONBASED_BACKUP=1
	else
		PARTITIONBASED_BACKUP=0
	fi

	logItem "PartitionbasedBackup detected? $PARTITIONBASED_BACKUP"

	if [[ -z $RESTORE_DEVICE ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_RESTOREDEVICE_DEFINED
		exitError $RC_PARAMETER_ERROR
	fi

	if (( $PROGRESS )) && [[ "$BACKUPTYPE" == "$BACKUPTYPE_DD" || "$BACKUPTYPE" == "$BACKUPTYPE_DDZ" ]] && [[ $(which pv &>/dev/null) ]]; then
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
		if ! which rsync &>/dev/null; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "rsync" "rsync"
			exitError $RC_MISSING_COMMANDS
		fi
		local rsyncVersion=$(rsync --version | head -n 1 | awk '{ print $3 }')
		logItem "rsync version: $rsyncVersion"
		if (( $PROGRESS )) && [[ "$rsyncVersion" < "3.1" ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_RSYNC_DOES_NOT_SUPPORT_PROGRESS "$rsyncVersion"
			exitError $RC_PARAMETER_ERROR
		fi
	fi

	if (( $PARTITIONBASED_BACKUP )); then
		if ! which dosfslabel &>/dev/null; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "dosfslabel" "dosfstools"
			exitError $RC_MISSING_COMMANDS
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
					if (( $RESIZE_ROOTFS )); then
						writeToConsole $MSG_LEVEL_MINIMAL $MSG_ADJUSTING_WARNING "$RESTORE_DEVICE" "$(bytesToHuman $targetSDSize)" "$(bytesToHuman $sourceSDSize)"
					else
						writeToConsole $MSG_LEVEL_MINIMAL $MSG_ADJUSTING_DISABLED "$RESTORE_DEVICE" "$(bytesToHuman $targetSDSize)" "$(bytesToHuman $sourceSDSize)"
						exitError RC_PARAMETER_ERROR
					fi
				else
					if (( $RESIZE_ROOTFS )); then
						writeToConsole $MSG_LEVEL_MINIMAL $MSG_ADJUSTING_WARNING2 "$RESTORE_DEVICE" "$(bytesToHuman $targetSDSize)" "$(bytesToHuman $sourceSDSize)"
					fi
				fi
			fi
		fi
	fi

	rc=0

	if ! (( $PARTITIONBASED_BACKUP )); then
		restoreNonPartitionBasedBackup
		if [[ $BACKUPTYPE != $BACKUPTYPE_DD && $BACKUPTYPE != $BACKUPTYPE_DDZ ]] && (( $ROOT_PARTITION_DEFINED )); then
			synchronizeCmdlineAndfstab
		fi
	else
		restorePartitionBasedBackup
	fi

	logExit

}

# calculate diff in months of two dates (yyyymm)
function calculateMonthDiff() { # fromDate toDate

	local y1=${1:0:4}
	local m1=${1:4:2}

	local y2=${2:0:4}
	local m2=${2:4:2}

	m1=${m1/#0}
	m2=${m2/#0}

	local diff=$(( ($y2 - $y1) * 12 + ($m2 - $m1) ))
	echo $diff
}

function updateRestoreReminder() {

	logEntry

	local reminder_file="$VAR_LIB_DIRECTORY/$RESTORE_REMINDER_FILE"

	# create directory to save state
	if [[ ! -d "$VAR_LIB_DIRECTORY" ]]; then
		mkdir -p "$VAR_LIB_DIRECTORY"
	fi

	# initialize reminder state
	if [[ ! -e "$reminder_file" ]]; then
		 echo "$(date +%Y%m) 0" > "$reminder_file"
		 return
	fi

	# retrieve reminder state
	local now
	now=$(date +%Y%m)
	local rf
	rf=( $(<$reminder_file) )
	local diffMonths
	diffMonths=$(calculateMonthDiff $now ${rf[0]} )

	# check if reminder should be send
	if (( $diffMonths >= $RESTORE_REMINDER_INTERVAL )); then
		if (( ${rf[1]} < $RESTORE_REMINDER_REPEAT )); then
			# update reminder state
			local nr=$(( ${rf[1]} + 1 ))
			echo "${rf[0]} $nr" > "$reminder_file"
			local left=$(( $RESTORE_REMINDER_REPEAT - $nr ))
			NEWS_AVAILABLE=1
			RESTORETEST_REQUIRED=1
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORETEST_REQUIRED $left
		else
			logItem "Reset reminder"
			# reset reminder state
			echo "$(date +%Y%m) 0" > "$reminder_file"
		fi
	fi

	logExit

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
	logEntry

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

	logExit
}

function check4RequiredCommands() {

	logEntry

	local missing_commands missing_packages

	for cmd in "${!REQUIRED_COMMANDS[@]}"; do
		if ! command -v $cmd > /dev/null; then
			missing_commands="$cmd $missing_commands "
			missing_packages="${REQUIRED_COMMANDS[$cmd]} $missing_packages "
		fi
	done

	if [[ -n "$missing_commands" ]]; then
		shopt -s extglob
		missing_commands="${missing_commands%%*( )}"
		missing_packages="${missing_packages%%*( )}"
		shopt -u extglob
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_COMMANDS "$missing_commands"
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_PACKAGES "$missing_packages"
		exitError $RC_MISSING_COMMANDS
	fi

	logExit

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
	echo "Usage: $MYSELF [option]* {backupDirectory}"
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
	echo "-f {config filename}"
	echo "-g Display progress bar"
	echo "-G {message language} (EN or DE) (default: $DEFAULT_LANGUAGE)"
	echo "-h display this help text"
	echo "-l {log level} ($POSSIBLE_LOG_LEVELs) (default: ${LOG_LEVELs[$DEFAULT_LOG_LEVEL]})"
	echo "-m {message level} ($POSSIBLE_MSG_LEVELs) (default: ${MSG_LEVELs[$DEFAULT_MSG_LEVEL]})"
	echo "-M {backup description}"
	echo "-n notification if there is a newer scriptversion available for download (default: ${NO_YES[$DEFAULT_NOTIFY_UPDATE]})"
	echo "-s {email program to use} ($SUPPORTED_MAIL_PROGRAMS) (default: $DEFAULT_MAIL_PROGRAM)"
	echo "--timestamps Prefix messages with timestamps (default: ${NO_YES[$DEFAULT_TIMESTAMPS]})"
	echo "-u \"{excludeList}\" List of directories to exclude from tar and rsync backup"
	echo "-U current script version will be replaced by the most recent version. Current version will be saved and can be restored with parameter -V"
	echo "-v verbose output of backup tools (default: ${NO_YES[$DEFAULT_VERBOSE]})"
	echo "-V restore a previous version"
	echo "-z compress backup file with gzip (default: ${NO_YES[$DEFAULT_ZIP_BACKUP]})"
	echo ""
	echo "-Backup options-"
	[ -z "$DEFAULT_STOPSERVICES" ] && DEFAULT_STOPSERVICES="no"
	echo "-a \"{commands to execute after Backup}\" (default: $DEFAULT_STARTSERVICES)"
	echo "-B Save bootpartition in tar file (Default: $DEFAULT_TAR_BOOT_PARTITION_ENABLED)"
	echo "-k {backupsToKeep} (default: $DEFAULT_KEEPBACKUPS)"
	[ -z "$DEFAULT_STARTSERVICES" ] && DEFAULT_STARTSERVICES="no"
	echo "-o \"{commands to execute before Backup}\" (default: $DEFAULT_STOPSERVICES)"
	echo "-P use dedicated partitionbackup mode (default: ${NO_YES[$DEFAULT_PARTITIONBASED_BACKUP]})"
	echo "-t {backupType} ($ALLOWED_TYPES) (default: $DEFAULT_BACKUPTYPE)"
	echo "-T \"{List of partitions to save}\" (Partition numbers, e.g. \"1 2 3\"). Only valid with parameter -P (default: ${DEFAULT_PARTITIONS_TO_BACKUP})"
	echo ""
	echo "-Restore options-"
	[ -z "$DEFAULT_RESTORE_DEVICE" ] && DEFAULT_RESTORE_DEVICE="no"
	echo "-C Formating of the restorepartitions will check for badblocks (Standard: $DEFAULT_CHECK_FOR_BAD_BLOCKS)"
	echo "-d {restoreDevice} (default: $DEFAULT_RESTORE_DEVICE) (Example: /dev/sda)"
	echo "-R {rootPartition} (default: restoreDevice) (Example: /dev/sdb1)"
	echo "--resizeRootFS (Default: ${NO_YES[$DEFAULT_RESIZE_ROOTFS]})"
}

function usageDE() {

	echo "$GIT_CODEVERSION"
	echo "Aufruf: $MYSELF [Option]* {Backupverzeichnis}"
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
	echo "-f {Konfig Dateiname}"
	echo "-g Anzeige des Fortschritts"
	echo "-G {Meldungssprache} (DE oder EN) (Standard: $DEFAULT_LANGUAGE)"
	echo "-h Anzeige dieses Hilfstextes"
	echo "-l {log Genauigkeit} ($POSSIBLE_LOG_LEVELs) (Standard: ${LOG_LEVELs[$DEFAULT_LOG_LEVEL]})"
	echo "-m {Meldungsgenauigkeit} ($POSSIBLE_MSG_LEVELs) (Standard: ${MSG_LEVELs[$DEFAULT_MSG_LEVEL]})"
	echo "-M {Backup Beschreibung}"
	echo "-n Benachrichtigung wenn eine aktuellere Scriptversion zum download verfügbar ist. (Standard: ${NO_YES[$DEFAULT_NOTIFY_UPDATE]})"
	echo "-s {Benutztes eMail Program} ($SUPPORTED_MAIL_PROGRAMS) (Standard: $DEFAULT_MAIL_PROGRAM)"
	echo "--timestamps Meldungen werden mit einen Zeitstempel ausgegeben (Standard: ${NO_YES[$DEFAULT_TIMESTAMPS]})"
	echo "-u \"{excludeList}\" Liste von Verzeichnissen, die vom tar und rsync Backup auszunehmen sind"
	echo "-U Scriptversion wird durch die aktuelle Version ersetzt. Die momentane Version wird gesichert und kann mit dem Parameter -V wiederhergestellt werden"
	echo "-v Detailierte Ausgaben der Backup Tools (Standard: ${NO_YES[$DEFAULT_VERBOSE]})"
	echo "-V Aktivierung einer älteren Skriptversion"
	echo "-z Backup verkleinern mit gzip (Standard: ${NO_YES[$DEFAULT_ZIP_BACKUP]})"
	echo ""
	echo "-Backup Optionen-"
	[ -z "$DEFAULT_STOPSERVICES" ] && DEFAULT_STOPSERVICES="keine"
	echo "-a \"{Befehle die nach dem Backup ausgeführt werden}\" (Standard: $DEFAULT_STARTSERVICES)"
	echo "-B Sicherung der Bootpartition als tar file (Standard: $DEFAULT_TAR_BOOT_PARTITION_ENABLED)"
	echo "-k {Anzahl Backups} (Standard: $DEFAULT_KEEPBACKUPS)"
	[ -z "$DEFAULT_STARTSERVICES" ] && DEFAULT_STARTSERVICES="keine"
	echo "-o \"{Befehle die vor dem Backup ausgeführt werden}\" (Standard: $DEFAULT_STOPSERVICES)"
	echo "-P Speziellen Partitionsbackupmodus benutzen (Standard: ${NO_YES[$DEFAULT_PARTITIONBASED_BACKUP]})"
	echo "-t {Backuptyp} ($ALLOWED_TYPES) (Standard: $DEFAULT_BACKUPTYPE)"
	echo "-T \"Liste der Partitionen die zu Sichern sind}\" (Partitionsnummern, z.B. \"1 2 3\"). Nur gültig zusammen mit Parameter -P (Standard: ${DEFAULT_PARTITIONS_TO_BACKUP})"
	echo ""
	echo "-Restore Optionen-"
	[ -z "$DEFAULT_RESTORE_DEVICE" ] && DEFAULT_RESTORE_DEVICE="keiner"
	echo "-C Beim Formatieren der Restorepartitionen wird auf Badblocks geprüft (Standard: $DEFAULT_CHECK_FOR_BAD_BLOCKS)"
	echo "-d {restoreGerät} (Standard: $DEFAULT_RESTORE_DEVICE) (Beispiel: /dev/sda)"
	echo "-R {rootPartition} (Standard: restoreDevice) (Beispiel: /dev/sdb1)"
	echo "--resizeRootFS (Standard: ${NO_YES[$DEFAULT_RESIZE_ROOTFS]})"
}

function mentionHelp() {
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_MENTION_HELP $MYSELF
}

# there is an issue when a parameter starts with "-" which may a new option
# Workaround1: if parameter contains at least one space it's considered as a parameter and not an option even the string starts with '-'
# Workaround2: prefix parameter with \ (has to be \\ in bash commandline)

function checkOptionParameter() { # option parameter

	local nospaces="${2/ /}"
	if [[ "$nospaces" != "$2" ]]; then
		echo "$2"
		return 0
	fi

	if [[ "${2:0:1}" == "\\" ]]; then
		echo "${2:1}"
		return 0
	elif [[ "$2" =~ ^(\-|\+|\-\-|\+\+) || -z $2 ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_OPTION_REQUIRES_PARAMETER "$1"
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_MENTION_HELP $MYSELF
		echo ""
		return 1
	fi
	echo "$2"
	return 0
}

# -x and -x+ enables, -x- disables flag
# --opt and --opt+ enables, --opt- disables flag
# 0 -> disabled, 1 -> enabled
function getEnableDisableOption() { # option
	case "$1" in
		-*-) echo 0;;
		-*+|-*) echo 1;;
		*) writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNKNOWN_OPTION "$1"
			mentionHelp
			exitError $RC_PARAMETER_ERROR
			;;
	esac
}

##### Now do your job

INVOCATIONPARMS=""			# save passed opts for logging
for (( i=1; i<=$#; i++ )); do
	p=${!i}
	INVOCATIONPARMS="$INVOCATIONPARMS $p"
done

initializeDefaultConfig
readConfigParameters		# overwrite defaults with settings in config files

APPEND_LOG=$DEFAULT_APPEND_LOG
APPEND_LOG_OPTION="$DEFAULT_APPEND_LOG_OPTION"
BACKUPPATH="$DEFAULT_BACKUPPATH"
BACKUPTYPE=$DEFAULT_BACKUPTYPE
CHECK_FOR_BAD_BLOCKS=$DEFAULT_CHECK_FOR_BAD_BLOCKS
CONFIG_FILE="$DEFAULT_CONFIG_FILE"
DD_BACKUP_SAVE_USED_PARTITIONS_ONLY=$DEFAULT_DD_BACKUP_SAVE_USED_PARTITIONS_ONLY
DD_BLOCKSIZE="$DEFAULT_DD_BLOCKSIZE"
DD_PARMS="$DEFAULT_DD_PARMS"
DEPLOYMENT_HOSTS="$DEFAULT_DEPLOYMENT_HOSTS"
EMAIL="$DEFAULT_EMAIL"
EMAIL_PARMS="$DEFAULT_EMAIL_PARMS"
MAIL_PROGRAM="$DEFAULT_MAIL_PROGRAM"
SENDER_EMAIL="$DEFAULT_SENDER_EMAIL"
EXCLUDE_LIST="$DEFAULT_EXCLUDE_LIST"
EXTENSIONS="$DEFAULT_EXTENSIONS"
KEEPBACKUPS=$DEFAULT_KEEPBACKUPS
KEEPBACKUPS_DD=$DEFAULT_KEEPBACKUPS_DD
KEEPBACKUPS_DDZ=$DEFAULT_KEEPBACKUPS_DDZ
KEEPBACKUPS_TAR=$DEFAULT_KEEPBACKUPS_TAR
KEEPBACKUPS_TGZ=$DEFAULT_KEEPBACKUPS_TGZ
KEEPBACKUPS_RSYNC=$DEFAULT_KEEPBACKUPS_RSYNC
LINK_BOOTPARTITIONFILES=$DEFAULT_LINK_BOOTPARTITIONFILES
LOG_LEVEL=$DEFAULT_LOG_LEVEL
LOG_OUTPUT="$DEFAULT_LOG_OUTPUT"
MAIL_ON_ERROR_ONLY=$DEFAULT_MAIL_ON_ERROR_ONLY
MAIL_PROGRAM="$DEFAULT_MAIL_PROGRAM"
MSG_LEVEL=$DEFAULT_MSG_LEVEL
NOTIFY_UPDATE=$DEFAULT_NOTIFY_UPDATE
PARTITIONBASED_BACKUP=$DEFAULT_PARTITIONBASED_BACKUP
PARTITIONS_TO_BACKUP="$DEFAULT_PARTITIONS_TO_BACKUP"
RESIZE_ROOTFS=$DEFAULT_RESIZE_ROOTFS
RESTORE_DEVICE=$DEFAULT_RESTORE_DEVICE
RESTORE_REMINDER_INTERVAL=$DEFAULT_RESTORE_REMINDER_INTERVAL
RESTORE_REMINDER_REPEAT=$DEFAULT_RESTORE_REMINDER_REPEAT
RSYNC_BACKUP_ADDITIONAL_OPTIONS="$DEFAULT_RSYNC_BACKUP_ADDITIONAL_OPTIONS"
RSYNC_BACKUP_OPTIONS="$DEFAULT_RSYNC_BACKUP_OPTIONS"
SENDER_EMAIL="$DEFAULT_SENDER_EMAIL"
SKIPLOCALCHECK=$DEFAULT_SKIPLOCALCHECK
SKIP_DEPRECATED="$DEFAULT_SKIP_DEPRECATED"
STARTSERVICES="$DEFAULT_STARTSERVICES"
STOPSERVICES="$DEFAULT_STOPSERVICES"
SYSTEMSTATUS=$DEFAULT_SYSTEMSTATUS
TAR_BACKUP_ADDITIONAL_OPTIONS="$DEFAULT_TAR_BACKUP_ADDITIONAL_OPTIONS"
TAR_BACKUP_OPTIONS="$DEFAULT_TAR_BACKUP_OPTIONS"
TAR_BOOT_PARTITION_ENABLED=$DEFAULT_TAR_BOOT_PARTITION_ENABLED
TAR_RESTORE_ADDITIONAL_OPTIONS="$DEFAULT_TAR_RESTORE_ADDITIONAL_OPTIONS"
TIMESTAMPS=$DEFAULT_TIMESTAMPS
USE_HARDLINKS=$DEFAULT_USE_HARDLINKS
USE_UUID=$DEFAULT_USE_UUID
VERBOSE=$DEFAULT_VERBOSE
YES_NO_RESTORE_DEVICE=$DEFAULT_YES_NO_RESTORE_DEVICE
ZIP_BACKUP=$DEFAULT_ZIP_BACKUP

if [[ -z $DEFAULT_LANGUAGE ]]; then
	LANG_EXT="${LANG^^*}"
	DEFAULT_LANGUAGE="${LANG_EXT:0:2}"
	if [[ ! $DEFAULT_LANGUAGE =~ $MSG_SUPPORTED_REGEX ]]; then
		DEFAULT_LANGUAGE="$MSG_LANG_FALLBACK"
	fi
else
	DEFAULT_LANGUAGE="${DEFAULT_LANGUAGE^^*}"
fi

LANGUAGE=$DEFAULT_LANGUAGE

# misc other vars

BACKUP_DIRECTORY_NAME=""
BACKUPFILE=""
DEPLOY=0
EXCLUDE_DD=0
FAKE=0
FAKE_BACKUPS=0
FORCE_SFDISK=0
FORCE_UPDATE=0
HELP=0
INCLUDE_ONLY=0
NO_YES_QUESTION=0
PROGRESS=0
REGRESSION_TEST=0
RESTORE=0
RESTOREFILE=""
RESTORETEST_REQUIRED=0
REVERT=0
ROOT_HARDLINKS_SUPPORTED=0
ROOT_PARTITION_DEFINED=0
SHARED_BOOT_DIRECTORY=0
SKIP_RSYNC_CHECK=0
SKIP_SFDISK=0
UPDATE_MYSELF=0
UPDATE_POSSIBLE=0
USE_HARDLINKS=1
VERSION_DEPRECATED=0
WARNING_MESSAGE_WRITTEN=0

PARAMS=""

while (( "$#" )); do

  case "$1" in
	-0|-0[-+])
	  SKIP_SFDISK=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-1|-1[-+])
	  FORCE_SFDISK=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-5|-5[-+])
	  SKIP_RSYNC_CHECK=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-9|-9[-+])
	  FAKE_BACKUPS=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-a)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  STARTSERVICES="$o"; shift 2
	  ;;

	-A|-A[-+])
	  APPEND_LOG=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-b)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  DD_BLOCKSIZE="$o"; shift 2
	  ;;

	-B|-B[-+])
	  TAR_BOOT_PARTITION_ENABLED=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-c|-c[-+])
	  SKIPLOCALCHECK=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-C|-C[-+])
	  CHECK_FOR_BAD_BLOCKS=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-d)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  RESTORE_DEVICE="$o"; RESTORE=1; shift 2
	  ;;

	-D)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  DD_PARMS="$o"; shift 2
	  ;;

	-e)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  EMAIL="$o"; shift 2
	  ;;

	-E)
	  o=$(checkOptionParameter "$1" "$2");
	  (( $? )) && exitError $RC_PARAMETER_ERROR
      EMAIL_PARMS="$o"; shift 2
      ;;

    -f)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  CUSTOM_CONFIG_FILE="$o"; shift 2
	  if [[ ! -f "$CUSTOM_CONFIG_FILE" ]]; then
	      writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_ARG_NOT_FOUND "$CUSTOM_CONFIG_FILE"
          exitError $RC_MISSING_FILES
	  fi
	  CUSTOM_CONFIG_FILE="$(readlink -f "$CUSTOM_CONFIG_FILE")"
	  ;;

    -F|-F[-+])
	  FAKE=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-g|-g[-+])
	  PROGRESS=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-G)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  LANGUAGE="$o"; shift 2
  	  LANGUAGE=${LANGUAGE^^*}
	  msgVar="MSG_${LANGUAGE}"
	  if [[ -z ${!msgVar} ]]; then
		  writeToConsole $MSG_LEVEL_MINIMAL $MSG_LANGUAGE_NOT_SUPPORTED $LANGUAGE
		  exitError $RC_PARAMETER_ERROR
	  fi
	  ;;

	-h|--help)
	  HELP=1; break
	  ;;

	--hardlinks|--hardlinks[+-])
	  USE_HARDLINKS=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-i|-i[-+])
	  USE_UUID=$(getEnableDisableOption "$1"); shift 1
	  ;;

	--include|--include[+-])
	  INCLUDE_ONLY=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-k)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  KEEPBACKUPS="$o"; shift 2
	  ;;

	--keep_dd)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  KEEPBACKUPS_DD="$o"; shift 2
	  ;;

	--keep_ddz)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  KEEPBACKUPS_DDZ="$o"; shift 2
	  ;;

	--keep_tar)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  KEEPBACKUPS_TAR="$o"; shift 2
	  ;;

	--keep_tgz)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  KEEPBACKUPS_TGZ="$o"; shift 2
	  ;;

	--keep_rsync)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  KEEPBACKUPS_RSYNC="$o"; shift 2
	  ;;

	-l)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  LOG_LEVEL="$o"; shift 2
	  ;;

	-L)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  LOG_OUTPUT="$o"; shift 2
	  ;;

	-m)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  MSG_LEVEL="$o"; shift 2
	  ;;

	-M)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  BACKUP_DIRECTORY_NAME="$o"; shift 2
  	  BACKUP_DIRECTORY_NAME=${BACKUP_DIRECTORY_NAME//[ \/\:\.\-]/_}
  	  ;;

	-n|-n[-+])
	  NOTIFY_UPDATE=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-N)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  EXTENSIONS="$o"; shift 2
	  ;;

	-o)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  STOPSERVICES="$o"; shift 2
	  ;;

	-p)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  BACKUPPATH="$o"; shift 2
	  if [[ ! -d "$BACKUPPATH" ]]; then
		  writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_ARG_NOT_FOUND "$BACKUPPATH"
		  exitError $RC_MISSING_FILES
	  fi
	  BACKUPPATH="$(readlink -f "$BACKUPPATH")"
	  ;;

	-P|-P[-+])
	  PARTITIONBASED_BACKUP=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-r)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  RESTOREFILE="$o"; shift 2
	  if [[ ! -d "$RESTOREFILE" && ! -f "$RESTOREFILE" ]]; then
		  writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_ARG_NOT_FOUND "$RESTOREFILE"
		  exitError $RC_MISSING_FILES
	  fi
	  RESTOREFILE="$(readlink -f "$RESTOREFILE")"
	  ;;

	-R)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  ROOT_PARTITION="$o"; shift 2
	  ROOT_PARTITION_DEFINED=1
  	  ;;

	--resizeRootFS|--resizeRootFS[+-])
	  RESIZE_ROOTFS=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-s)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  EMAIL_PROGRAM="$o"; shift 2
	  ;;

	-S|-S[-+])
	  FORCE_UPDATE=$(getEnableDisableOption "$1"); shift 1
	  ;;

	--systemstatus|--systemstatus[+-])
	  SYSTEMSTATUS=$(getEnableDisableOption "$1"); shift 1
	  if ! which lsof &>/dev/null; then
		 writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "lsof" "lsof"
		 exitError $RC_MISSING_COMMANDS
	  fi
	  ;;

	-t)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  BACKUPTYPE="$o"; shift 2
	  ;;

	--timestamps|--timestamps[+-])
	  TIMESTAMPS=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-T)
	  checkOptionParameter "$1" "$2"
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  PARTITIONS_TO_BACKUP="$2"; shift 2
	  ;;

	-u)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  EXCLUDE_LIST="$o"; shift 2
	  ;;

	-U)
	  UPDATE_MYSELF=1; shift 1
	  ;;

	-v|-v[-+])
	  VERBOSE=$(getEnableDisableOption "$1"); shift 1
	  ;;

	 --version)
	  echo "Version: $VERSION CommitSHA: $GIT_COMMIT_ONLY CommitDate: $GIT_DATE_ONLY CommitTime: $GIT_TIME_ONLY"
	  exitNormal
	  ;;

	-V)
	  REVERT=1; shift 1
	  ;;

	-x|-x[-+])
	  EXCLUDE_DD=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-y|-y[-+])
	  DEPLOY=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-Y)
	  NO_YES_QUESTION=1; shift 1
	  ;;

	-z|-z[-+])
	  ZIP_BACKUP=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-Z|-Z[-+])
	  REGRESSION_TEST=$(getEnableDisableOption "$1"); shift 1
	  ;;

	--) # end argument parsing
	  shift
	  break
	  ;;

	-*|--*|+*|++*) # unknown option
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNKNOWN_OPTION "$1"
		mentionHelp
		exitError $RC_PARAMETER_ERROR
	  ;;

	*) # preserve positional arguments
	  [[ -z $PARAMS ]] && PARAMS="$1" || PARAMS="$PARAMS $1"
	  shift
	  ;;
  esac
done

(( $INCLUDE_ONLY )) && exitNormal

# set positional arguments in argument list $@
set -- $PARAMS

# Override default parms with parms in custom config file

if [[ -n "$CUSTOM_CONFIG_FILE" && -f "$CUSTOM_CONFIG_FILE" ]]; then
	CUSTOM_CONFIG_FILE_INCLUDED=0
	set -e
	. "$CUSTOM_CONFIG_FILE"
	set +e
	CUSTOM_CONFIG_FILE_INCLUDED=1
fi

# initialize options with defaults from configs if no command line arg was passed
[[ -z "$APPEND_LOG" ]] && APPEND_LOG="$DEFAULT_APPEND_LOG"
[[ -z "$APPEND_LOG_OPTION" ]] && APPEND_LOG_OPTION="$DEFAULT_APPEND_LOG_OPTION"
[[ -z "$BACKUPPATH" ]] && BACKUPPATH="$DEFAULT_BACKUPPATH"
[[ -z "$BACKUPTYPE" ]] && BACKUPTYPE="$DEFAULT_BACKUPTYPE"
[[ -z "$AFTER_STARTSERVICES" ]] && AFTER_STARTSERVICES="$DEFAULT_AFTER_STARTSERVICES"
[[ -z "$BEFORE_STOPSERVICES" ]] && BEFORE_STOPSERVICES="$DEFAULT_BEFORE_STOPSERVICES"
[[ -z "$CHECK_FOR_BAD_BLOCKS" ]] && CHECK_FOR_BAD_BLOCKS="$DEFAULT_CHECK_FOR_BAD_BLOCKS"
[[ -z "$DD_BACKUP_SAVE_USED_PARTITIONS_ONLY" ]] && DD_BACKUP_SAVE_USED_PARTITIONS_ONLY="$DEFAULT_DD_BACKUP_SAVE_USED_PARTITIONS_ONLY"
[[ -z "$DD_BLOCKSIZE" ]] && DD_BLOCKSIZE="$DEFAULT_DD_BLOCKSIZE"
[[ -z "$DD_PARMS" ]] && DD_PARMS="$DEFAULT_DD_PARMS"
[[ -z "$DEPLOYMENT_HOSTS" ]] && DEPLOYMENT_HOSTS="$DEFAULT_DEPLOYMENT_HOSTS"
[[ -z "$EMAIL" ]] && EMAIL="$DEFAULT_EMAIL"
[[ -z "$EMAIL_PARMS" ]] && EMAIL_PARMS="$DEFAULT_EMAIL_PARMS"
[[ -z "$EMAIL_PROGRAM" ]] && EMAIL_PROGRAM="$DEFAULT_MAIL_PROGRAM"
[[ -z "$EMAIL_SENDER" ]] && EMAIL_SENDER="$DEFAULT_EMAIL_SENDER"
[[ -z "$EXCLUDE_LIST" ]] && EXCLUDE_LIST="$DEFAULT_EXCLUDE_LIST"
[[ -z "$EXTENSIONS" ]] && EXTENSIONS="$DEFAULT_EXTENSIONS"
[[ -z "$KEEPBACKUPS" ]] && KEEPBACKUPS="$DEFAULT_KEEPBACKUPS"
[[ -z "$LINK_BOOTPARTITIONFILES" ]] && LINK_BOOTPARTITIONFILES="$DEFAULT_LINK_BOOTPARTITIONFILES"
[[ -z "$LOG_LEVEL" ]] && LOG_LEVEL="$DEFAULT_LOG_LEVEL"
[[ -z "$LOG_OUTPUT" ]] && LOG_OUTPUT="$DEFAULT_LOG_OUTPUT"
[[ -z "$MAIL_ON_ERROR_ONLY" ]] && MAIL_ON_ERROR_ONLY="$DEFAULT_MAIL_ON_ERROR_ONLY"
[[ -z "$MSG_LEVEL" ]] && MSG_LEVEL="$DEFAULT_MSG_LEVEL"
[[ -z "$NOTIFY_UPDATE" ]] && NOTIFY_UPDATE="$DEFAULT_NOTIFY_UPDATE"
[[ -z "$PARTITIONBASED_BACKUP" ]] && PARTITIONBASED_BACKUP="$DEFAULT_PARTITIONBASED_BACKUP"
[[ -z "$PARTITIONS_TO_BACKUP" ]] && PARTITIONS_TO_BACKUP="$DEFAULT_PARTITIONS_TO_BACKUP"
[[ -z "$RESIZE_ROOTFS" ]] && RESIZE_ROOTFS="$DEFAULT_RESIZE_ROOTFS"
[[ -z "$RESTORE_DEVICE" ]] && RESTORE_DEVICE="$DEFAULT_RESTORE_DEVICE"
[[ -z "$RESTORE_REMINDER_INTERVAL" ]] && RESTORE_REMINDER_INTERVAL="$DEFAULT_RESTORE_REMINDER_INTERVAL"
[[ -z "$RESTORE_REMINDER_REPEAT" ]] && RESTORE_REMINDER_REPEAT="$DEFAULT_RESTORE_REMINDER_REPEAT"
[[ -z "$RSYNC_BACKUP_ADDITIONAL_OPTIONS" ]] && RSYNC_BACKUP_ADDITIONAL_OPTIONS="$DEFAULT_RSYNC_BACKUP_ADDITIONAL_OPTIONS"
[[ -z "$RSYNC_BACKUP_OPTIONS" ]] && RSYNC_BACKUP_OPTIONS="$DEFAULT_RSYNC_BACKUP_OPTIONS"
[[ -z "$SENDER_EMAIL" ]] && SENDER_EMAIL="$DEFAULT_SENDER_EMAIL"
[[ -z "$SKIPLOCALCHECK" ]] && SKIPLOCALCHECK="$DEFAULT_SKIPLOCALCHECK"
[[ -z "$STARTSERVICES" ]] && STARTSERVICES="$DEFAULT_STARTSERVICES"
[[ -z "$STOPSERVICES" ]] && STOPSERVICES="$DEFAULT_STOPSERVICES"
[[ -z "$SYSTEMSTATUS" ]] && SYSTEMSTATUS="$DEFAULT_SYSTEMSTATUS"
[[ -z "$TAR_BACKUP_ADDITIONAL_OPTIONS" ]] && TAR_BACKUP_ADDITIONAL_OPTIONS="$DEFAULT_TAR_BACKUP_ADDITIONAL_OPTIONS"
[[ -z "$TAR_BACKUP_OPTIONS" ]] && TAR_BACKUP_OPTIONS="$DEFAULT_TAR_BACKUP_OPTIONS"
[[ -z "$TAR_BOOT_PARTITION_ENABLED" ]] && TAR_BOOT_PARTITION_ENABLED="$DEFAULT_TAR_BOOT_PARTITION_ENABLED"
[[ -z "$TAR_RESTORE_ADDITIONAL_OPTIONS" ]] && TAR_RESTORE_ADDITIONAL_OPTIONS="$DEFAULT_TAR_RESTORE_ADDITIONAL_OPTIONS"
[[ -z "$TIMESTAMPS" ]] && TIMESTAMPS="$DEFAULT_TIMESTAMPS"
[[ -z "$USE_HARDLINKS" ]] && USE_HARDLINKS="$DEFAULT_USE_HARDLINKS"
[[ -z "$USE_UUID" ]] && USE_UUID="$DEFAULT_USE_UUID"
[[ -z "$VERBOSE" ]] && VERBOSE="$DEFAULT_VERBOSE"
[[ -z "$YES_NO_RESTORE_DEVICE" ]] && YES_NO_RESTORE_DEVICE="$DEFAULT_YES_NO_RESTORE_DEVICE"
[[ -z "$ZIP_BACKUP" ]] && ZIP_BACKUP="$DEFAULT_ZIP_BACKUP"

if (( ! $RESTORE )); then
	lockingFramework
	exlock_now
	if (( $? )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_INSTANCE_ACTIVE
		exitError $RC_MISC_ERROR
	fi
fi

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

writeToConsole $MSG_LEVEL_MINIMAL $MSG_STARTED "$HOSTNAME" "$MYSELF" "$VERSION" "$GIT_COMMIT_ONLY" "$(date)"
(( $IS_BETA )) && writeToConsole $MSG_LEVEL_MINIMAL $MSG_INTRO_BETA_MESSAGE
(( $IS_DEV )) && writeToConsole $MSG_LEVEL_MINIMAL $MSG_INTRO_DEV_MESSAGE
(( $IS_HOTFIX )) && writeToConsole $MSG_LEVEL_MINIMAL $MSG_INTRO_HOTFIX_MESSAGE

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

if (( $UID != 0 )); then
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_RUNASROOT "$0" "$INVOCATIONPARMS"
	exitError $RC_MISC_ERROR
fi

if (( $DEPLOY )); then
	deployMyself
	exitNormal
fi

if (( $REVERT )); then
	revertScriptVersion
	exitNormal
fi

if (( $UPDATE_MYSELF )); then
	downloadPropertiesFile FORCE
	updateScript
	exitNormal
fi

if (( $NO_YES_QUESTION )); then				# WARNING: dangerous option !!!
	if [[ ! $RESTORE_DEVICE =~ $YES_NO_RESTORE_DEVICE ]]; then	# make sure we're not killing a disk by accident
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_YES_NO_DEVICE_MISMATCH $RESTORE_DEVICE $YES_NO_RESTORE_DEVICE
		exitError $RC_MISC_ERROR
	fi
fi

substituteNumberArguments
checkAndCorrectImportantParameters	# no return if errors detected
check4RequiredCommands

logItem "RESTORE: $RESTORE - fileParameter: $fileParameter"
if [[ -n $fileParameter ]]; then
	if (( $RESTORE )); then
		RESTOREFILE="$(readlink -f "$fileParameter")"
	else
		BACKUPPATH="$(readlink -f "$fileParameter")"
	fi
fi
if ( (( $RESTORE )) && [[ -z "$RESTOREFILE" ]] ) || ( (( ! $RESTORE )) && [[ -z "$BACKUPPATH" ]] ); then
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_FILEPARAMETER
	mentionHelp
	exitError $RC_MISSING_FILES
fi

if [[ -z $RESTORE_DEVICE ]] && (( $ROOT_PARTITION_DEFINED )); then
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_RESTOREDEVICE_OPTION
	exitError $RC_PARAMETER_ERROR
fi

logItem "Enabling trap handler"
trapWithArg cleanup SIGINT SIGTERM EXIT

setupEnvironment
logOptions						# config parms already read
logSystem

writeToConsole $MSG_LEVEL_DETAILED $MSG_USING_LOGFILE "$LOG_FILE"

if (( $ETC_CONFIG_FILE_INCLUDED )); then
	logItem "Reading config ${ETC_CONFIG_FILE}$NL$(egrep -v '^\s*$|^#' $ETC_CONFIG_FILE)"
	writeToConsole $MSG_LEVEL_DETAILED $MSG_INCLUDED_CONFIG "$ETC_CONFIG_FILE"
fi
if (( $HOME_CONFIG_FILE_INCLUDED )); then
	logItem "Reading config ${HOME_CONFIG_FILE}$NL$(egrep -v '^\s*$|^#' $HOME_CONFIG_FILE)"
	writeToConsole $MSG_LEVEL_DETAILED $MSG_INCLUDED_CONFIG "$HOME_CONFIG_FILE"
fi
if (( $CURRENTDIR_CONFIG_FILE_INCLUDED )); then
	logItem "REading ${CURRENTDIR_CONFIG_FILE}$NL$(egrep -v '^\s*$|^#' $CURRENTDIR_CONFIG_FILE)"
	writeToConsole $MSG_LEVEL_DETAILED $MSG_INCLUDED_CONFIG "$CURRENTDIR_CONFIG_FILE"
fi
if (( $CUSTOM_CONFIG_FILE_INCLUDED )); then
	logItem "Reading ${CUSTOM_CONFIG_FILE}$NL$(egrep -v '^\s*$|^#' $CUSTOM_CONFIG_FILE)"
	writeToConsole $MSG_LEVEL_DETAILED $MSG_INCLUDED_CONFIG "$CUSTOM_CONFIG_FILE"
fi

downloadPropertiesFile

updateRestoreReminder

reportNews

if isVersionDeprecated "$VERSION"; then
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_SCRIPT_IS_DEPRECATED "$VERSION"
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_SCRIPT_IS_DEPRECATED "$VERSION"
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_SCRIPT_IS_DEPRECATED "$VERSION"
	VERSION_DEPRECATED=1
	NEWS_AVAILABLE=1
fi

doit #	no return for backup
