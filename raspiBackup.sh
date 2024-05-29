#!/bin/bash
#
#######################################################################################################################
#
# Create and restore a backup of a Raspberry running Raspbian
#
# Visit http://www.linux-tips-and-tricks.de/raspiBackup for latest code and other details
#
# Smart recycle backup strategy inspired by https://opensource.com/article/18/8/automate-backups-raspberry-pi and
# enhanced to support multiple backups in a given timeframe of days, weeks, months and years
#
# Credits to following people for their translation work
#	  FI - teemue
#	  FR - mgrafr
#
#######################################################################################################################
#
#    Copyright (c) 2013-2024 framp at linux-tips-and-tricks dot de
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

set -o pipefail

if [ -z "$BASH" ] ;then
	echo "??? ERROR: Unable to execute script. bash interpreter missing."
	echo "??? DEBUG: $(lsof -a -p $$ -d txt | tail -n 1)"
	exit 127
fi

MYSELF="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"					# use linked script name if the link is used
MYNAME=${MYSELF%.*}
VERSION="0.6.9.1"                								# -beta, -hotfix or -dev suffixes possible
VERSION_SCRIPT_CONFIG="0.1.7"								# required config version for script

VERSION_VARNAME="VERSION"									# has to match above var names
VERSION_CONFIG_VARNAME="VERSION_.*CONF.*"					# used to lookup VERSION_CONFIG in config files

[ $(kill -l | grep -c SIG) -eq 0 ] && printf "\n\033[1;35m Don't call script with leading \"sh\"! \033[m\n\n"  >&2 && exit 255
[ -z "${BASH_VERSINFO[0]}" ] && printf "\n\033[1;35m Make sure you're using \"bash\"! \033[m\n\n" >&2 && exit 255
[ ${BASH_VERSINFO[0]} -lt 3 ] && printf "\n\033[1;35m Minimum requirement is bash 3.2. You have $BASH_VERSION \033[m\n\n"  >&2 && exit 255
[ ${BASH_VERSINFO[0]} -le 3 ] && [ ${BASH_VERSINFO[1]} -le 1 ] && printf "\n\033[1;35m Minimum requirement is bash 3.2. You have $BASH_VERSION \033[m\n\n"  >&2 && exit 255

declare -r PS4='|${LINENO}> \011${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

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

IS_BETA=$(( ! $(grep -iqE "alpha|beta" <<< "$VERSION"; echo $?) ))
IS_DEV=$(( ! $(grep -iq dev <<< "$VERSION"; echo $?) ))
IS_HOTFIX=$(( ! $(grep -iq hotfix <<< "$VERSION"; echo $?) ))

GIT_DATE='$Date$'
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<< $GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<< $GIT_DATE | sed 's/\$//')
GIT_COMMIT='$Sha1$'
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<< $GIT_COMMIT | sed 's/\$//')

GIT_CODEVERSION="$MYSELF $VERSION, $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"

function findUser() {

	local u

	if [[ -n "$SUDO_USER" ]]; then
		u="$SUDO_USER"
	else
		u="$USER"
	fi

	echo "$u"

}

# some general constants

readonly MYHOMEURL="https://www.linux-tips-and-tricks.de"
DATE=$(date +%Y%m%d-%H%M%S)
HOSTNAME=$(hostname)
NL=$'\n'
CURRENT_DIR=$(pwd)
SCRIPT_DIR=$( cd $( dirname ${BASH_SOURCE[0]}); pwd | xargs readlink -f)

# Smileys used in eMail subject to notify about news/events

SMILEY_WARNING="O.o"
SMILEY_UPDATE_POSSIBLE=";-)"
SMILEY_BETA_AVAILABLE=":-D"
SMILEY_RESTORETEST_REQUIRED="8-)"
SMILEY_VERSION_DEPRECATED=":-("

# URLs and temp filenames used

# URLTARGET allows to use deployment of new code versions, example: use "beta" to test beta code as if it was published just before it's published

if [[ -n $URLTARGET ]]; then
	echo "===> URLTARGET: $URLTARGET"
	URLTARGET="/$URLTARGET"
fi

DOWNLOAD_URL="$MYHOMEURL/raspiBackup${URLTARGET}/raspiBackup.sh"
BETA_DOWNLOAD_URL="$MYHOMEURL/raspiBackup${URLTARGET}/beta/raspiBackup.sh"
CONFIG_URL="$MYHOMEURL/raspiBackup${URLTARGET}/raspiBackup_\$lang\.conf" # used in eval for late binding of URLTAGRET
INSTALLER_DOWNLOAD_URL="$MYHOMEURL/raspiBackup${URLTARGET}/raspiBackupInstallUI.sh"
INSTALLER_BETA_DOWNLOAD_URL="$MYHOMEURL/raspiBackup${URLTARGET}/beta/raspiBackupInstallUI.sh"
PROPERTIES_DOWNLOAD_URL="$MYHOMEURL/raspiBackup${URLTARGET}/raspiBackup.properties"

# dd warning website
DD_WARNING_URL_DE="$MYHOMEURL/de/raspibackupcategorie/579-raspibackup-warum-sollte-man-dd-als-backupmethode-besser-nicht-benutzen/"
DD_WARNING_URL_EN="$MYHOMEURL/en/all-pages-about-raspibackup/581-raspibackup-why-shouldn-t-you-use-dd-as-backup-method/"

CALLING_USER="$(findUser)"
CALLING_HOME="$(eval echo "~${CALLING_USER}")"

PROPERTY_FILE="$MYNAME.properties"
LATEST_TEMP_PROPERTY_FILE="/tmp/$PROPERTY_FILE"
VAR_LIB_DIRECTORY="/var/lib/$MYNAME"
RESTORE_REMINDER_FILE="restore.reminder"
VARS_FILE="/tmp/$MYNAME.vars"
TEMPORARY_MOUNTPOINT_ROOT="/tmp"
LOGFILE_EXT=".log"
LOGFILE_NAME="${MYNAME}${LOGFILE_EXT}"
LOGFILE_RESTORE_EXT=".logr"
MSGFILE_EXT=".msg"
MSGFILE_RESTORE_EXT=".msgr"
MSGFILE_NAME="${MYNAME}${MSGFILE_EXT}"
TEMP_LOG_FILE="/tmp/$LOGFILE_NAME"
TEMP_MSG_FILE="/tmp/$MSGFILE_NAME"
FINISH_LOG_FILE="/tmp/${MYNAME}.logf"
MODIFIED_SFDISK="/tmp/$$.sfdisk"

# timeouts

DOWNLOAD_TIMEOUT=30 # seconds
DOWNLOAD_RETRIES=3

# debug option constants

LOG_NONE=0
LOG_DEBUG=1
POSSIBLE_LOG_LEVEL_NUMBERs="[$LOG_NONE$LOG_DEBUG]"

declare -A LOG_LEVELs=( [$LOG_NONE]="Off" [$LOG_DEBUG]="Debug" )
POSSIBLE_LOG_LEVELs=""
for K in "${!LOG_LEVELs[@]}"; do
	POSSIBLE_LOG_LEVELs="$POSSIBLE_LOG_LEVELs|${LOG_LEVELs[$K]}"
done
POSSIBLE_LOG_LEVELs="$(cut -c 2- <<< $POSSIBLE_LOG_LEVELs)"

declare -A LOG_LEVEL_ARGs
for K in "${!LOG_LEVELs[@]}"; do
	k=$(tr '[:lower:]' '[:upper:]' <<< "${LOG_LEVELs[$K]}")
	LOG_LEVEL_ARGs[$k]="$K"
done

MSG_LEVEL_MINIMAL=0
MSG_LEVEL_DETAILED=1
POSSIBLE_MSG_LEVEL_NUMBERs="[$MSG_LEVEL_MINIMAL$MSG_LEVEL_DETAILED]"

declare -A MSG_LEVELs=( [$MSG_LEVEL_MINIMAL]="Minimal" [$MSG_LEVEL_DETAILED]="Detailed" )
POSSIBLE_MSG_LEVELs=""
for K in "${!MSG_LEVELs[@]}"; do
	POSSIBLE_MSG_LEVELs="$POSSIBLE_MSG_LEVELs|${MSG_LEVELs[$K]}"
done
POSSIBLE_MSG_LEVELs="$(cut -c 2- <<< $POSSIBLE_MSG_LEVELs)"

declare -A MSG_LEVEL_ARGs
for K in "${!MSG_LEVELs[@]}"; do
	k=$(tr '[:lower:]' '[:upper:]' <<< "${MSG_LEVELs[$K]}")
	MSG_LEVEL_ARGs[$k]="$K"
done

LOG_OUTPUT_VARLOG=1
LOG_OUTPUT_BACKUPLOC=2
LOG_OUTPUT_HOME=3
POSSIBLE_LOG_OUTPUT_NUMBERs="^[$LOG_OUTPUT_BACKUPLOC|$LOG_OUTPUT_HOME|$LOG_OUTPUT_VARLOG]\$"

LOG_OUTPUT_IS_NO_USERDEFINEDFILE_REGEX="[$LOG_OUTPUT_VARLOG$LOG_OUTPUT_BACKUPLOC$LOG_OUTPUT_HOME]"
declare -A LOG_OUTPUT_LOCs=( [$LOG_OUTPUT_VARLOG]="/var/log/raspiBackup/<hostname>.log" [$LOG_OUTPUT_BACKUPLOC]="<backupPath>" [$LOG_OUTPUT_HOME]="~/raspiBackup.log")

declare -A LOG_OUTPUTs=( [$LOG_OUTPUT_VARLOG]="Varlog" [$LOG_OUTPUT_BACKUPLOC]="Backup" [$LOG_OUTPUT_HOME]="Current")
declare -A LOG_OUTPUT_ARGs
for K in "${!LOG_OUTPUTs[@]}"; do
	k=$(tr '[:lower:]' '[:upper:]' <<< "${LOG_OUTPUTs[$K]}")
	LOG_OUTPUT_ARGs[$k]="$K"
done

POSSIBLE_LOG_OUTPUTs=""
for K in "${!LOG_OUTPUTs[@]}"; do
	POSSIBLE_LOG_OUTPUTs="$POSSIBLE_LOG_OUTPUTs|${LOG_OUTPUTs[$K]}"
done
POSSIBLE_LOG_OUTPUTs="$(cut -c 2- <<< $POSSIBLE_LOG_OUTPUTs)"

# message option constants

LOG_TYPE_MSG=0
LOG_TYPE_DEBUG=1
declare -A LOG_TYPEs=( [$LOG_TYPE_MSG]="MSG" [$LOG_TYPE_DEBUG]="DBG")

BACKUPTYPE_DD="dd"
BACKUPTYPE_DDZ="ddz"
BACKUPTYPE_TAR="tar"
BACKUPTYPE_TGZ="tgz"
BACKUPTYPE_RSYNC="rsync"
POSSIBLE_BACKUP_TYPES_REGEX="$BACKUPTYPE_DD|$BACKUPTYPE_DDZ|$BACKUPTYPE_RSYNC|$BACKUPTYPE_TAR|$BACKUPTYPE_TGZ"
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

# variables exported to pass on to extensions

export BACKUP_TARGETDIR
export BACKUP_TARGETFILE
export MSG_FILE
export LOG_FILE

# Telegram options

TELEGRAM_NOTIFY_SUCCESS="S"
TELEGRAM_NOTIFY_FAILURE="F"
TELEGRAM_NOTIFY_MESSAGES="M"
TELEGRAM_NOTIFY_MESSAGES2="m"
TELEGRAM_POSSIBLE_NOTIFICATIONS="$TELEGRAM_NOTIFY_SUCCESS$TELEGRAM_NOTIFY_FAILURE$TELEGRAM_NOTIFY_MESSAGES$TELEGRAM_NOTIFY_MESSAGES2"
TELEGRAM_URL="https://api.telegram.org/bot"

EMOJI_OK="$(echo -ne "\xe2\x9c\x94\xef\xb8\x8f\x0a")"  # ✔️
EMOJI_WARNING="$(echo -ne "\xe2\x9a\xa0\xef\xb8\x8f\x0a")"  # ⚠️
EMOJI_FAILED="$(echo -ne "\xe2\x9d\x8c\x0a")" # ❌
EMOJI_UPDATE_POSSIBLE="$(echo -ne "\xf0\x9f\x98\x89\x0a")" # 😉
EMOJI_BETA_AVAILABLE="$(echo -ne "\xf0\x9f\x98\x83\x0a")" # 😃
EMOJI_RESTORETEST_REQUIRED="$(echo -ne "\xf0\x9f\x94\x94\x0a")" # 🔔
EMOJI_VERSION_DEPRECATED="$(echo -ne "\xf0\x9f\x92\x80\x0a")" # 💀

# convert emoji into hex
#printf "%s" "$EMOJI_WARNING"
#echo $(xxd -pu <<< "$EMOJI_WARNING")
#exit

# Pushover options

PUSHOVER_NOTIFY_SUCCESS="S"
PUSHOVER_NOTIFY_FAILURE="F"
PUSHOVER_NOTIFY_MESSAGES="M"
PUSHOVER_POSSIBLE_NOTIFICATIONS="$PUSHOVER_NOTIFY_SUCCESS$PUSHOVER_NOTIFY_FAILURE$PUSHOVER_NOTIFY_MESSAGES"
PUSHOVER_URL="https://api.pushover.net/1/messages.json"

# Slack options

SLACK_NOTIFY_SUCCESS="S"
SLACK_NOTIFY_FAILURE="F"
SLACK_NOTIFY_MESSAGES="M"
SLACK_POSSIBLE_NOTIFICATIONS="$SLACK_NOTIFY_SUCCESS$SLACK_NOTIFY_FAILURE$SLACK_NOTIFY_MESSAGES"

SLACK_EMOJI_OK=":white_check_mark:"  # ✔️
SLACK_EMOJI_WARNING=":warning:"  # ⚠️
SLACK_EMOJI_FAILED=":x:" # ❌
SLACK_EMOJI_UPDATE_POSSIBLE=":smirk:" # 😉
SLACK_EMOJI_BETA_AVAILABLE=":laughing:" # 😃
SLACK_EMOJI_RESTORETEST_REQUIRED=":bell:" # 🔔
SLACK_EMOJI_VERSION_DEPRECATED=":skull:" # 💀

# various other constants

PRE_BACKUP_EXTENSION="pre"
POST_BACKUP_EXTENSION="post"
READY_BACKUP_EXTENSION="ready"
NOTIFICATION_BACKUP_EXTENSION="notify"
EMAIL_EXTENSION="mail"
PRE_RESTORE_EXTENSION="$PRE_BACKUP_EXTENSION"
POST_RESTORE_EXTENSION="$POST_BACKUP_EXTENSION"

PRE_BACKUP_EXTENSION_CALLED=0
PRE_RESTORE_EXTENSION_CALLED=0

EMAIL_EXTENSION_PROGRAM="mailext"
EMAIL_MAILX_PROGRAM="mail"
EMAIL_SSMTP_PROGRAM="ssmtp"
EMAIL_MSMTP_PROGRAM="msmtp"
EMAIL_SENDEMAIL_PROGRAM="sendEmail"
SUPPORTED_EMAIL_PROGRAM_REGEX="^($EMAIL_MAILX_PROGRAM|$EMAIL_SSMTP_PROGRAM|$EMAIL_MSMTP_PROGRAM|$EMAIL_SENDEMAIL_PROGRAM|$EMAIL_EXTENSION_PROGRAM)$"
SUPPORTED_MAIL_PROGRAMS=$(echo $SUPPORTED_EMAIL_PROGRAM_REGEX | sed 's:^..\(.*\)..$:\1:' | sed 's/|/,/g')

EMAIL_COLORING_SUBJECT="SUBJECT"
EMAIL_COLORING_OPTION="OPTION"
SUPPORTED_EMAIL_COLORING_REGEX="^($EMAIL_COLORING_OPTION|$EMAIL_COLORING_SUBJECT)$"
SUPPORTED_EMAIL_COLORING=$(echo $SUPPORTED_EMAIL_COLORING_REGEX | sed 's:^..\(.*\)..$:\1:' | sed 's/|/,/g')

PARTITIONS_TO_BACKUP_ALL="*"
MASQUERADE_STRING="@@@@"

COLORING_OFF=""
COLORING_CONSOLE="C"
COLORING_MAIL="M"
COLORING_VALID_OPTIONS="$COLORING_CONSOLE$COLORING_MAIL"

NEWS_AVAILABLE=0
BETA_AVAILABLE=0
LOG_INDENT=0
WARNING_MESSAGE_WRITTEN=0

PROPERTY_REGEX='.*="([^"]*)"'
NOOP_AO_ARG_REGEX="^[[:space:]]*:"

STOPPED_SERVICES=0
SHARED_BOOT_DIRECTORY=0

BOOT_TAR_EXT="tmg"
BOOT_DD_EXT="img"

CONFIG_DIR="/usr/local/etc"
ORIG_CONFIG="$CONFIG_DIR/raspiBackup.conf"
NEW_CONFIG="$CONFIG_DIR/raspiBackup.conf.new"
MERGED_CONFIG="$CONFIG_DIR/raspiBackup.conf.merged"
BACKUP_CONFIG="$CONFIG_DIR/raspiBackup.conf.bak"

PERSISTENT_JOURNAL="/var/log/journal"
PERSISTENT_JOURNAL_LOG2RAM="/var/hdd.log/journal"

NEW_OPTION_TRAILER="# >>>>> NEW OPTION added in config version %s <<<<< "
DELETED_OPTION_TRAILER="# >>>>> OPTION DELETED in config version %s <<<<< "

TWO_TB=$((1024*1024*1024*1024*2))			# disks > 2TB reuquire gpt instead of mbr

SHA_PLACEHOLDER="$(base64 -d <<< "JFNoYTEkCg==")"
DATE_PLACEHOLDER="$(base64 -d <<< "JERhdGUkCg==")"

# Commands used by raspiBackup and which have to be available
# [command]=package
declare -A REQUIRED_COMMANDS=( \
		["parted"]="parted" \
		["fsck.vfat"]="dosfstools" \
		["e2label"]="e2fsprogs" \
		["dosfslabel"]="dosfstools" \
		["fdisk"]="fdisk" \
		["blkid"]="util-linux" \
		["curl"]="curl" \
		["sfdisk"]="fdisk" \
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
RC_MISSING_PARTITION=125
RC_UUIDS_NOT_UNIQUE=126
RC_INCOMPLETE_PARMS=127
RC_CONFIGVERSION_MISMATCH=128
RC_TELEGRAM_ERROR=129
RC_FILE_OPERATION_ERROR=130
RC_MOUNT_FAILED=131
RC_UNSUPPORTED_ENVIRONMENT=132
RC_RESTORE_EXTENSION_FAILS=133
RC_BACKUP_EXTENSION_FAILS=134
RC_DOWNLOAD_FAILED=135
RC_BACKUP_DIRNAME_ERROR=136
RC_RESTORE_IMPOSSIBLE=137
RC_INVALID_BOOTDEVICE=138
RC_ENVIRONMENT_ERROR=139
RC_CLEANUP_ERROR=140
RC_EXTENSION_ERROR=141
RC_UNPROTECTED_CONFIG=142
RC_NOT_SUPPORTED=143

tty -s
INTERACTIVE=$((!$?))

# defaults
MSG_LEVEL="$MSG_LEVEL_DETAILED"
LOG_LEVEL="$LOG_DEBUG"
LOG_OUTPUT="$LOG_OUTPUT_BACKUPLOC"

# borrowed from http://stackoverflow.com/questions/3685970/check-if-an-array-contains-a-value

function containsElement () {
  local e
  for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
  return 1
}

#
# NLS: Either use system language if language is supported and use fallback language English otherwise
#

SUPPORTED_LANGUAGES=("EN" "DE" "FI" "FR")
FALLBACK_LANGUAGE="EN"

# use LANG variable to determine language

[[ -z "${LANG}" ]] && LANG="en_US.UTF-8"		# if no LANG set use English
LANG_EXT="${LANG,,*}"
LANG_SYSTEM="${LANG_EXT:0:2}"						# extract language id
if ! containsElement "${LANG_SYSTEM^^*}" "${SUPPORTED_LANGUAGES[@]}"; then	# if language is not supported use English
	LANG_SYSTEM=$FALLBACK_LANGUAGE
fi

#
# Messages
#
# To add a new language just execute following steps:
# 1) Add new language id LL (e.g. FI for Finnish) in variable SUPPORTED_LANGUAGES (see above)
# 2) For every MSG_ add a new message MSG_LL, e.g. MSG_FI for Finnish
# 3) For every MSG_ add a new declare -A in following line, e.g. MSG_FI for Finnish
# 4) Optionally add a help function usageLL, e.g. usageFI
# 5) Note: If a message definition or help function (MSG_LL or usageLL) is missing in a supported language the fallback language English will be selected by the code (MSG_EN or usageEN)
#

declare -A MSG_EN MSG_DE MSG_FI MSG_FR

LANGUAGE="${LANG_SYSTEM^^*}"    # that's the language until it's overwritten with an option or config entry

MSG_UNDEFINED=0
MSG_EN[$MSG_UNDEFINED]="RBK0000E: Undefined messageid"
MSG_DE[$MSG_UNDEFINED]="RBK0000E: Unbekannte Meldungsid"
MSG_FI[$MSG_UNDEFINED]="RBK0000E: Määrittämätön viestitunnus"
MSG_FR[$MSG_UNDEFINED]="RBK0000E: Id du message non défini"
MSG_ASSERTION_FAILED=1
MSG_EN[$MSG_ASSERTION_FAILED]="RBK0001E: Unexpected program error occured. (%s), Linenumber: %s, Error: %s."
MSG_DE[$MSG_ASSERTION_FAILED]="RBK0001E: Unerwarteter Programmfehler trat auf. (%s), Zeile: %s, Fehler: %s."
MSG_FI[$MSG_ASSERTION_FAILED]="RBK0001E: Tapahtui odottamaton virhe. (%s), Rivinumero: %s, Virhe: %s"
MSG_FR[$MSG_ASSERTION_FAILED]="RBK0001E: Une erreur inattendue s'est produite. (%s), à la ligne n°: %s, Erreur: %s"
MSG_RUNASROOT=2
MSG_EN[$MSG_RUNASROOT]="RBK0002E: $MYSELF has to be started as root. Try 'sudo %s%s'."
MSG_DE[$MSG_RUNASROOT]="RBK0002E: $MYSELF muss als root gestartet werden. Benutze 'sudo %s%s'."
MSG_FI[$MSG_RUNASROOT]="RBK0002E: $MYSELF tulee käynnistää root-oikeuksin. Suorita 'sudo %s%s'."
MSG_FR[$MSG_RUNASROOT]="RBK0002E: $MYSELF doit être démarré en tant que root.Essayez 'sudo %s%s'."
MSG_TRUNCATING_TO_USED_PARTITIONS_ONLY=3
MSG_EN[$MSG_TRUNCATING_TO_USED_PARTITIONS_ONLY]="RBK0003I: Backup size will be truncated from %s to %s."
MSG_DE[$MSG_TRUNCATING_TO_USED_PARTITIONS_ONLY]="RBK0003I: Backupgröße wird von %s auf %s reduziert."
MSG_FI[$MSG_TRUNCATING_TO_USED_PARTITIONS_ONLY]="RBK0003I: Varmuuskopion koko typistetään koosta %s kokoon %s."
MSG_FR[$MSG_TRUNCATING_TO_USED_PARTITIONS_ONLY]="RBK0003I: La taille de la sauvegarde sera diminuée de %s à %s."
MSG_ADJUSTING_SECOND=4
MSG_EN[$MSG_ADJUSTING_SECOND]="RBK0004I: Adjusting second partition from %s to %s."
MSG_DE[$MSG_ADJUSTING_SECOND]="RBK0004I: Zweite Partition wird von %s auf %s angepasst."
MSG_FI[$MSG_ADJUSTING_SECOND]="RBK0004I: Säädetään toinen osio %s osioksi %s."
MSG_FR[$MSG_ADJUSTING_SECOND]="RBK0004I: Redimensionnement de la deuxième partition de %s à %s."
MSG_BACKUP_FAILED=5
MSG_EN[$MSG_BACKUP_FAILED]="RBK0005E: Backup failed. Check previous error messages for details."
MSG_DE[$MSG_BACKUP_FAILED]="RBK0005E: Backup fehlerhaft beendet. Siehe vorhergehende Fehlermeldungen."
MSG_FI[$MSG_BACKUP_FAILED]="RBK0005E: Varmuuskopiointi epäonnistui. Katso lisätiedot edellisistä virheilmoituksista"
MSG_FR[$MSG_BACKUP_FAILED]="RBK0005E: La sauvegarde a echoué. Consultez les messages d'erreur pour plus d'information"
MSG_ADJUSTING_WARNING=6
MSG_EN[$MSG_ADJUSTING_WARNING]="RBK0006W: Target %s with %s is smaller than backup source with %s. root partition will be truncated accordingly. NOTE: Restore may fail if the root partition will become too small."
MSG_DE[$MSG_ADJUSTING_WARNING]="RBK0006W: Ziel %s mit %s ist kleiner als die Backupquelle mit %s. Die root Partition wird entsprechend verkleinert. HINWEIS: Der Restore kann fehlschlagen wenn sie zu klein wird."
MSG_FI[$MSG_ADJUSTING_WARNING]="RBK0006W: Kohde %s kooltaan %s on pienempi kuin varmuuskopion lähde kooltaan %s. Juuriosio typistetään sen mukaiseksi. HUOM: Palautus saattaa epäonnistua, jos juuriosiosta tulee liian pieni."
MSG_FR[$MSG_ADJUSTING_WARNING]="RBK0006W: La cible %s avec %s est plus petite que la source avec  %s. la partition racine sera diminuée en proportion. REMARQUE : La restauration peut échouer si la partition root devient trop petite."
MSG_STARTING_SERVICES=7
MSG_EN[$MSG_STARTING_SERVICES]="RBK0007I: Starting services: '%s'."
MSG_DE[$MSG_STARTING_SERVICES]="RBK0007I: Services werden gestartet: '%s'."
MSG_FI[$MSG_STARTING_SERVICES]="RBK0007I: Käynnistetään palvelut: '%s'."
MSG_FR[$MSG_STARTING_SERVICES]="RBK0007I: Démarrage des services: '%s'."
MSG_STOPPING_SERVICES=8
MSG_EN[$MSG_STOPPING_SERVICES]="RBK0008I: Stopping services: '%s'."
MSG_DE[$MSG_STOPPING_SERVICES]="RBK0008I: Services werden gestoppt: '%s'."
MSG_FI[$MSG_STOPPING_SERVICES]="RBK0008I: Pysäytetään palvelut: '%s'."
MSG_FR[$MSG_STOPPING_SERVICES]="RBK0008I: Arrêt des services: '%s'."
MSG_STARTED=9
MSG_EN[$MSG_STARTED]="RBK0009I: %s: %s V%s - %s (%s) started at %s."
MSG_DE[$MSG_STARTED]="RBK0009I: %s: %s V%s - %s (%s) %s gestartet."
MSG_FI[$MSG_STARTED]="RBK0009I: %s: %s V%s - %s (%s) käynnistyi %s."
MSG_FR[$MSG_STARTED]="RBK0009I: %s: %s V%s - %s (%s) Début à %s."
MSG_STOPPED=10
MSG_EN[$MSG_STOPPED]="RBK0010I: %s: %s V%s - %s (%s) stopped at %s with rc %s."
MSG_DE[$MSG_STOPPED]="RBK0010I: %s: %s V%s - %s (%s) %s beendet mit Returncode %s."
MSG_FI[$MSG_STOPPED]="RBK0010I: %s: %s V%s - %s (%s) pysäytettiin %s, vastauskoodi %s."
MSG_FR[$MSG_STOPPED]="RBK0010I: %s: %s V%s - %s (%s) terminé avec le code de retour %s."
MSG_NO_BOOT_PARTITION=11
MSG_EN[$MSG_NO_BOOT_PARTITION]="RBK0011E: No boot partition ${BOOT_PARTITION_PREFIX}1 found."
MSG_DE[$MSG_NO_BOOT_PARTITION]="RBK0011E: Keine boot Partition ${BOOT_PARTITION_PREFIX}1 gefunden."
MSG_FI[$MSG_NO_BOOT_PARTITION]="RBK0011E: Käynnistysosiota ${BOOT_PARTITION_PREFIX}1 ei löytynyt."
MSG_FR[$MSG_NO_BOOT_PARTITION]="RBK0011E: Pas de partition boot ${BOOT_PARTITION_PREFIX}1 ei löytynyt."
MSG_DD_BACKUP_NOT_POSSIBLE_FOR_PARTITIONBASED_BACKUP=12
MSG_EN[$MSG_DD_BACKUP_NOT_POSSIBLE_FOR_PARTITIONBASED_BACKUP]="RBK0012E: DD backup not supported for partition based backup. Use normal mode instead."
MSG_DE[$MSG_DD_BACKUP_NOT_POSSIBLE_FOR_PARTITIONBASED_BACKUP]="RBK0012E: DD Backup nicht unterstützt bei partitionsbasiertem Backup. Benutze den normalen Modus dafür."
MSG_FI[$MSG_DD_BACKUP_NOT_POSSIBLE_FOR_PARTITIONBASED_BACKUP]="RBK0012E: DD-varmuuskopiota ei tueta osioperustaiselle varmuuskopiolle. Käytä normaalimoodia."
MSG_FR[$MSG_DD_BACKUP_NOT_POSSIBLE_FOR_PARTITIONBASED_BACKUP]="RBK0012E: DD Sauvegarde non prise en charge avec le mode basée sur les partitions. Utilisez le mode normal."
MSG_MULTIPLE_PARTITIONS_FOUND=13
MSG_EN[$MSG_MULTIPLE_PARTITIONS_FOUND]="RBK0013E: More than two partitions detected which can be saved only with backuptype DD or DDZ, with option -P or with option --ignoreAdditionalPartitions."
MSG_DE[$MSG_MULTIPLE_PARTITIONS_FOUND]="RBK0013E: Es existieren mehr als zwei Partitionen, die nur mit dem Backuptype DD oder DDZ, mit der Option -P oder der Option --ignoreAdditionalPartitions gesichert werden können."
MSG_FI[$MSG_MULTIPLE_PARTITIONS_FOUND]="RBK0013E: Enemmän kuin kansi osiota löytyi, jotka voidaan tallentaa vain DD- tai DDZ-varmuuskopiona. Käytä valintaa -P tai --ignoreAdditionalPartitions."
MSG_FR[$MSG_MULTIPLE_PARTITIONS_FOUND]="RBK0013E: Il y a plus de deux partitions elles ne peuvent être sauvegardées qu'avec le type de sauvegarde DD ou DDZ, avec l'option -P ou l'option --ignoreAdditionalPartitions."
MSG_EMAIL_PROG_NOT_SUPPORTED=14
MSG_EN[$MSG_EMAIL_PROG_NOT_SUPPORTED]="RBK0014E: eMail program %s not supported. Supported are %s"
MSG_DE[$MSG_EMAIL_PROG_NOT_SUPPORTED]="RBK0014E: eMail Programm %s ist nicht unterstützt. Möglich sind %s"
MSG_FI[$MSG_EMAIL_PROG_NOT_SUPPORTED]="RBK0014E: Sähköpostisovellusta %s ei tueta. Tuettuja ovat %s"
MSG_FR[$MSG_EMAIL_PROG_NOT_SUPPORTED]="RBK0014E: Le programme de messagerie %s n'est pas pris en charge. Sont pris en charge %s"
MSG_INSTANCE_ACTIVE=15
MSG_EN[$MSG_INSTANCE_ACTIVE]="RBK0015E: There is already an instance of $MYNAME up and running"
MSG_DE[$MSG_INSTANCE_ACTIVE]="RBK0015E: Es ist schon eine Instanz von $MYNAME aktiv."
MSG_FI[$MSG_INSTANCE_ACTIVE]="RBK0015E: $MYNAME on jo tällä hetkellä käynnissä"
MSG_FR[$MSG_INSTANCE_ACTIVE]="RBK0015E: Une instance de $MYNAME est déjà active"
MSG_NO_SDCARD_FOUND=16
MSG_EN[$MSG_NO_SDCARD_FOUND]="RBK0016E: No sd card %s found."
MSG_DE[$MSG_NO_SDCARD_FOUND]="RBK0016E: Keine SD Karte %s gefunden."
MSG_FI[$MSG_NO_SDCARD_FOUND]="RBK0016E: SD-korttia %s ei löytynyt."
MSG_FR[$MSG_NO_SDCARD_FOUND]="RBK0016E: Aucune carte SD %s trouvée."
MSG_BACKUP_OK=17
MSG_EN[$MSG_BACKUP_OK]="RBK0017I: Backup finished successfully."
MSG_DE[$MSG_BACKUP_OK]="RBK0017I: Backup erfolgreich beendet."
MSG_FI[$MSG_BACKUP_OK]="RBK0017I: Varmuuskopiointi suoritettu onnistuneesti."
MSG_FR[$MSG_BACKUP_OK]="RBK0017I: Sauvegarde terminée avec succès."
MSG_ADJUSTING_WARNING2=18
MSG_EN[$MSG_ADJUSTING_WARNING2]="RBK0018W: Target %s with %s is larger than backup source with %s. root partition will be expanded accordingly to use the whole space."
MSG_DE[$MSG_ADJUSTING_WARNING2]="RBK0018W: Ziel %s mit %s ist größer als die Backupquelle mit %s. Die root Partition wird entsprechend vergrößert um den ganzen Platz zu benutzen."
MSG_FI[$MSG_ADJUSTING_WARNING2]="RBK0018W: Kohde %s kooltaan %s, on suurempi kuin varmuuskopion lähde kooltaan %s. Juuriosio laajennetaan sen mukaisesti käyttämään koko tila."
MSG_FR[$MSG_ADJUSTING_WARNING2]="RBK0018W: La cible %s avec %s, est plus grande que la source avec %s. la partition rootfs sera étendue pour utiliser tout l'espace."
MSG_MISSING_START_STOP=19
MSG_EN[$MSG_MISSING_START_STOP]="RBK0019E: Missing option -a and -o."
MSG_DE[$MSG_MISSING_START_STOP]="RBK0019E: Option -a und -o nicht angegeben."
MSG_FI[$MSG_MISSING_START_STOP]="RBK0019E: Valinnat -a ja -o puuttuvat"
MSG_FR[$MSG_MISSING_START_STOP]="RBK0019E: Options -a et -o non spécifiées"
MSG_FILESYSTEM_INCORRECT=20
MSG_EN[$MSG_FILESYSTEM_INCORRECT]="RBK0020E: Filesystem of rsync backup directory %s does not support %s."
MSG_DE[$MSG_FILESYSTEM_INCORRECT]="RBK0020E: Dateisystem des rsync Backupverzeichnisses %s unterstützt keine %s."
MSG_FI[$MSG_FILESYSTEM_INCORRECT]="RBK0020E: Rsync-varmuuskopiohakemiston %s tiedostojärjestelmä ei tue %s."
MSG_FR[$MSG_FILESYSTEM_INCORRECT]="RBK0020E: Le système des fichiers utilisés avec rsync %s n'est pas pris en charge %s."
MSG_BACKUP_PROGRAM_ERROR=21
MSG_EN[$MSG_BACKUP_PROGRAM_ERROR]="RBK0021E: Backupprogram for type %s failed with RC %s."
MSG_DE[$MSG_BACKUP_PROGRAM_ERROR]="RBK0021E: Backupprogramm des Typs %s beendete sich mit RC %s."
MSG_FI[$MSG_BACKUP_PROGRAM_ERROR]="RBK0021E: Tyypin %s varmuuskopiointisovellus epäonnistui, RC %s."
MSG_FR[$MSG_BACKUP_PROGRAM_ERROR]="RBK0021E: Sauvegarde de type %s terminé avec un Code Retour %s."
MSG_UNKNOWN_BACKUPTYPE=22
MSG_EN[$MSG_UNKNOWN_BACKUPTYPE]="RBK0022E: Unknown backuptype %s."
MSG_DE[$MSG_UNKNOWN_BACKUPTYPE]="RBK0022E: Unbekannter Backtyp %s."
MSG_FI[$MSG_UNKNOWN_BACKUPTYPE]="RBK0022E: Tuntematon varmuuskopiotyyppi %s."
MSG_FR[$MSG_UNKNOWN_BACKUPTYPE]="RBK0022E: Type de sauvegarde inconnu %s."
MSG_KEEPBACKUP_INVALID=23
MSG_EN[$MSG_KEEPBACKUP_INVALID]="RBK0023E: Invalid parameter %s for %s detected."
MSG_DE[$MSG_KEEPBACKUP_INVALID]="RBK0023E: Ungültiger Parameter %s für -k eingegeben."
MSG_FI[$MSG_KEEPBACKUP_INVALID]="RBK0023E: Havaittu epäkelpo parametri %s kohteelle %s."
MSG_FR[$MSG_KEEPBACKUP_INVALID]="RBK0023E: Paramètre %s non valide pour -k %s."
MSG_TOOL_ERROR=24
MSG_EN[$MSG_TOOL_ERROR]="RBK0024E: Backup tool %s received error %s. Errormessages:$NL%s"
MSG_DE[$MSG_TOOL_ERROR]="RBK0024E: Backupprogramm %s hat einen Fehler %s bekommen. Fehlermeldungen:$NL%s"
MSG_FI[$MSG_TOOL_ERROR]="RBK0024E: Varmuuskopiointityökalu %s vastaanotti virheen %s. Virheviestit:$NL%s"
MSG_FR[$MSG_TOOL_ERROR]="RBK0024E: Une erreur lors de la sauvegarde %s s'est produite %s. Message:$NL%s"
MSG_DIR_TO_BACKUP_DOESNOTEXIST=25
MSG_EN[$MSG_DIR_TO_BACKUP_DOESNOTEXIST]="RBK0025E: Backupdirectory %s does not exist."
MSG_DE[$MSG_DIR_TO_BACKUP_DOESNOTEXIST]="RBK0025E: Backupverzeichnis %s existiert nicht."
MSG_FI[$MSG_DIR_TO_BACKUP_DOESNOTEXIST]="RBK0025E: Varmuuskopiohakemistoa %s ei ole."
MSG_FR[$MSG_DIR_TO_BACKUP_DOESNOTEXIST]="RBK0025E: Le répertoire de sauvegarde %s n'existe pas."
MSG_SAVED_LOG=26
MSG_EN[$MSG_SAVED_LOG]="RBK0026I: Debug logfile saved in %s."
MSG_DE[$MSG_SAVED_LOG]="RBK0026I: Debug Logdatei wurde in %s gesichert."
MSG_FI[$MSG_SAVED_LOG]="RBK0026I: Vianmäärityksen lokitiedosto tallennettu kohteeseen %s."
MSG_FR[$MSG_SAVED_LOG]="RBK0026I: Le fichier journal de débogage a été enregistré sous %s."
MSG_NO_DEVICEMOUNTED=27
MSG_EN[$MSG_NO_DEVICEMOUNTED]="RBK0027E: No external device mounted on %s. root partition would be used for the backup."
MSG_DE[$MSG_NO_DEVICEMOUNTED]="RBK0027E: Kein externes Gerät an %s verbunden. Die root Partition würde für das Backup benutzt werden."
MSG_FI[$MSG_NO_DEVICEMOUNTED]="RBK0027E: Ulkoista laitetta ei ole otettu käyttöön kohteessa %s. Juuriosiota käytetään varmuuskopiointiin."
MSG_FR[$MSG_NO_DEVICEMOUNTED]="RBK0027E: Aucun périphérique externe monté sur %s. la partition racine sera utilisée pour la sauvegarde."
MSG_RESTORE_DIRECTORY_NO_DIRECTORY=28
MSG_EN[$MSG_RESTORE_DIRECTORY_NO_DIRECTORY]="RBK0028E: %s is no backup directory of $MYNAME."
MSG_DE[$MSG_RESTORE_DIRECTORY_NO_DIRECTORY]="RBK0028E: %s ist kein Wiederherstellungsverzeichnis von $MYNAME."
MSG_FI[$MSG_RESTORE_DIRECTORY_NO_DIRECTORY]="RBK0028E: %s ei ole kohteen $MYNAME varmuuskopiohakemisto"
MSG_FR[$MSG_RESTORE_DIRECTORY_NO_DIRECTORY]="RBK0028E: %s n'est pas un répertoire de restauration pour $MYNAME."
MSG_MPACK_NOT_INSTALLED=29
MSG_EN[$MSG_MPACK_NOT_INSTALLED]="RBK0029E: Mail program mpack not installed to send emails. No log can be attached to the eMail."
MSG_DE[$MSG_MPACK_NOT_INSTALLED]="RBK0029E: Mail Program mpack is nicht installiert. Es kann kein Log an die eMail angehängt werden."
MSG_FI[$MSG_MPACK_NOT_INSTALLED]="RBK0029E: Sähköpostisovellusta mpack ei ole asennettu sähköpostien lähetykseen. Lokitiedostoa ei voitu liittää sähköpostiin."
MSG_FR[$MSG_MPACK_NOT_INSTALLED]="RBK0029E: Le programme de messagerie mpack n'est pas installé. Aucune pièce jointe ne peut être ajoutée à l'e-mail."
MSG_IMG_DD_FAILED=30
MSG_EN[$MSG_IMG_DD_FAILED]="RBK0030E: %s file creation with dd failed with RC %s."
MSG_DE[$MSG_IMG_DD_FAILED]="RBK0030E: %s Datei Erzeugung mit dd endet fehlerhaft mit RC %s."
MSG_FI[$MSG_IMG_DD_FAILED]="RBK0030E: Tiedoston %s luonti dd:llä epäonnistui, RC %s."
MSG_FR[$MSG_IMG_DD_FAILED]="RBK0030E: La création du fichier %s avec dd s'est terminé avec un code d'erreur: %s."
MSG_CHECKING_FOR_NEW_VERSION=31
MSG_EN[$MSG_CHECKING_FOR_NEW_VERSION]="RBK0031I: Checking whether a new version of $MYSELF is available."
MSG_DE[$MSG_CHECKING_FOR_NEW_VERSION]="RBK0031I: Prüfe ob eine neue Version von $MYSELF verfügbar ist."
MSG_FI[$MSG_CHECKING_FOR_NEW_VERSION]="RBK0031I: Tarkistetaan, onko $MYSELF uusia versioita saatavilla."
MSG_FR[$MSG_CHECKING_FOR_NEW_VERSION]="RBK0031I: Vérifiez si une nouvelle version de $MYSELF est disponible."
MSG_INVALID_LOG_LEVEL=32
MSG_EN[$MSG_INVALID_LOG_LEVEL]="RBK0032E: Invalid parameter '%s' for option -l detected."
MSG_DE[$MSG_INVALID_LOG_LEVEL]="RBK0032E: Ungültiger Parameter '%s' für Option -l eingegeben."
MSG_FI[$MSG_INVALID_LOG_LEVEL]="RBK0032E: Havaittu epäkelpo parametri '%s' valinnalle -l."
MSG_FR[$MSG_INVALID_LOG_LEVEL]="RBK0032E: Paramètre non valide '%s' pour l'option -l."
MSG_CLEANING_UP=33
MSG_EN[$MSG_CLEANING_UP]="RBK0033I: Please wait until cleanup has finished."
MSG_DE[$MSG_CLEANING_UP]="RBK0033I: Bitte warten bis aufgeräumt wurde."
MSG_FI[$MSG_CLEANING_UP]="RBK0033I: Ole hyvä ja odota, kunnes puhdistus on valmistunut."
MSG_FR[$MSG_CLEANING_UP]="RBK0033I: Veuillez patienter jusqu'à la fin du nettoyage."
MSG_FILE_NOT_FOUND=34
MSG_EN[$MSG_FILE_NOT_FOUND]="RBK0034E: File %s not found."
MSG_DE[$MSG_FILE_NOT_FOUND]="RBK0034E: Datei %s nicht gefunden."
MSG_FI[$MSG_FILE_NOT_FOUND]="RBK0034E: Tiedostoa %s ei löytynyt."
MSG_FR[$MSG_FILE_NOT_FOUND]="RBK0034E: Fichier %s introuvable."
MSG_RESTORE_PROGRAM_ERROR=35
MSG_EN[$MSG_RESTORE_PROGRAM_ERROR]="RBK0035E: Backupprogram %s failed during restore with RC %s."
MSG_DE[$MSG_RESTORE_PROGRAM_ERROR]="RBK0035E: Backupprogramm %s endete beim Restore mit RC %s."
MSG_FI[$MSG_RESTORE_PROGRAM_ERROR]="RBK0035E: Varmuuskopiointisovellus %s epäonnistui palautuksen aikana, RC %s."
MSG_FR[$MSG_RESTORE_PROGRAM_ERROR]="RBK0035E: La sauvegarde %s a été interrompue avec le code erreur %s."
MSG_BACKUP_CREATING_PARTITION_INFO=36
MSG_EN[$MSG_BACKUP_CREATING_PARTITION_INFO]="RBK0036I: Saving partition layout."
MSG_DE[$MSG_BACKUP_CREATING_PARTITION_INFO]="RBK0036I: Partitionslayout wird gesichert."
MSG_FI[$MSG_BACKUP_CREATING_PARTITION_INFO]="RBK0036I: Tallennetaan osioasettelua."
MSG_FR[$MSG_BACKUP_CREATING_PARTITION_INFO]="RBK0036I: Sauvegarde de la disposition de la partition."
MSG_ANSWER_CHARS_YES=37
MSG_EN[$MSG_ANSWER_CHARS_YES]="Yy"
MSG_DE[$MSG_ANSWER_CHARS_YES]="Jj"
MSG_FI[$MSG_ANSWER_CHARS_YES]="Kk"
MSG_FR[$MSG_ANSWER_CHARS_YES]="Oo"
MSG_ARE_YOU_SURE=38
MSG_EN[$MSG_ARE_YOU_SURE]="RBK0038I: Are you sure? %s "
MSG_DE[$MSG_ARE_YOU_SURE]="RBK0038I: Bist Du sicher? %s "
MSG_FI[$MSG_ARE_YOU_SURE]="RBK0038I: Oletko varma? %s "
MSG_FR[$MSG_ARE_YOU_SURE]="RBK0038I: Etes vous sûre? %s "
MSG_MAILPROGRAM_NOT_INSTALLED=39
MSG_EN[$MSG_MAILPROGRAM_NOT_INSTALLED]="RBK0039E: Mail program %s not installed to send emails."
MSG_DE[$MSG_MAILPROGRAM_NOT_INSTALLED]="RBK0039E: Mail Program %s ist nicht installiert um eMail zu senden."
MSG_FI[$MSG_MAILPROGRAM_NOT_INSTALLED]="RBK0039E: Sähköpostisovellusta %s ei ole asennettu sähkökpostien lähettämiseen."
MSG_FR[$MSG_MAILPROGRAM_NOT_INSTALLED]="RBK0039E: Le programme de messagerie %s n'est pas installé pour envoyer des e-mails."
MSG_INCOMPATIBLE_UPDATE=40
MSG_EN[$MSG_INCOMPATIBLE_UPDATE]="RBK0040W: New version %s has some incompatibilities to previous versions. Please read %s and use option -S together with option -U to update script."
MSG_DE[$MSG_INCOMPATIBLE_UPDATE]="RBK0040W: Die neue Version %s hat inkompatible Änderungen zu vorhergehenden Versionen. Bitte %s lesen und dann die Option -S zusammen mit -U benutzen um das Script zu updaten."
MSG_FI[$MSG_INCOMPATIBLE_UPDATE]="RBK0040W: Uusi versio %s ei ole täysin yhteensopiva edellisen version kanssa. Ole hyvä ja lue %s ja käytä valintaa -S yhdessä valinnan -U kanssa päivittääksesi skriptin."
MSG_FR[$MSG_INCOMPATIBLE_UPDATE]="RBK0040W: La nouvelle version %s présente des incompatibilités avec les versions précédentes. Veuillez lire %s et utilisez les options -S et -U pour mettre à jour le script."
MSG_TITLE_OK=41
MSG_EN[$MSG_TITLE_OK]="%s: Backup finished successfully."
MSG_DE[$MSG_TITLE_OK]="%s: Backup erfolgreich beendet."
MSG_FI[$MSG_TITLE_OK]="%s: Varmuuskopiointi suoritettu onnistuneesti."
MSG_FR[$MSG_TITLE_OK]="%s: Sauvegarde terminée avec succès."
MSG_TITLE_ERROR=42
MSG_EN[$MSG_TITLE_ERROR]="%s: Backup failed !!!."
MSG_DE[$MSG_TITLE_ERROR]="%s: Backup nicht erfolgreich !!!."
MSG_FI[$MSG_TITLE_ERROR]="%s: Varmuuskopiointi epäonnistui !!!."
MSG_FR[$MSG_TITLE_ERROR]="%s: Échec de la sauvegarde !!!."
MSG_REMOVING_BACKUP=43
MSG_EN[$MSG_REMOVING_BACKUP]="RBK0043I: Removing incomplete backup in %s. This may take some time. Please be patient."
MSG_DE[$MSG_REMOVING_BACKUP]="RBK0043I: Unvollständiges Backup in %s wird gelöscht. Das kann etwas dauern. Bitte Geduld."
MSG_FI[$MSG_REMOVING_BACKUP]="RBK0043I: Poistetaan keskeneräinen varmuuskopio kohteessa %s. Tämä saattaa kestää jonkin aikaa. Ole hyvä ja odota."
MSG_FR[$MSG_REMOVING_BACKUP]="RBK0043I: Suppression en cours des sauvegardes incomplètes %s. Cela peut prendre du temps, SVP soyez patient."
MSG_CREATING_BOOT_BACKUP=44
MSG_EN[$MSG_CREATING_BOOT_BACKUP]="RBK0044I: Creating backup of boot partition in %s."
MSG_DE[$MSG_CREATING_BOOT_BACKUP]="RBK0044I: Backup der Bootpartition wird in %s erstellt."
MSG_FI[$MSG_CREATING_BOOT_BACKUP]="RBK0044I: Luodaan varmuuskopiota kohteeseen %s."
MSG_FR[$MSG_CREATING_BOOT_BACKUP]="RBK0044I: La partition de boot sera sauvegardée en %s."
MSG_CREATING_PARTITION_BACKUP=45
MSG_EN[$MSG_CREATING_PARTITION_BACKUP]="RBK0045I: Creating backup of partition layout in %s."
MSG_DE[$MSG_CREATING_PARTITION_BACKUP]="RBK0044I: Backup des Partitionlayouts wird in %s erstellt."
MSG_FI[$MSG_CREATING_PARTITION_BACKUP]="RBK0045I: Luodaan varmuuskopiota osioasettelusta kohteeseen %s"
MSG_FR[$MSG_CREATING_PARTITION_BACKUP]="RBK0045I: La disposition de la partition sera sauvegardée sous %s"
MSG_CREATING_MBR_BACKUP=46
MSG_EN[$MSG_CREATING_MBR_BACKUP]="RBK0046I: Creating backup of master boot record in %s."
MSG_DE[$MSG_CREATING_MBR_BACKUP]="RBK0046I: Backup des Masterbootrecords wird in %s erstellt."
MSG_FI[$MSG_CREATING_MBR_BACKUP]="RBK0046I: Luodaan varmuuskopiota Master Boot Recordista kohteeseen %s."
MSG_FR[$MSG_CREATING_MBR_BACKUP]="RBK0046I: Le MBR, Master Boot Record, est sauvegardé sous %s."
MSG_START_SERVICES_FAILED=47
MSG_EN[$MSG_START_SERVICES_FAILED]="RBK0047W: Error occured when starting services. RC %s."
MSG_DE[$MSG_START_SERVICES_FAILED]="RBK0047W: Ein Fehler trat beim Starten von Services auf. RC %s."
MSG_FI[$MSG_START_SERVICES_FAILED]="RBK0047W: Virhe palveluita käynnistäessä. RC %s."
MSG_FR[$MSG_START_SERVICES_FAILED]="RBK0047W: Une erreur avec le code %s s'est produite lors du démarrage des services."
MSG_STOP_SERVICES_FAILED=48
MSG_EN[$MSG_STOP_SERVICES_FAILED]="RBK0048E: Error occured when stopping services. RC %s."
MSG_DE[$MSG_STOP_SERVICES_FAILED]="RBK0048E: Ein Fehler trat beim Beenden von Services auf. RC %s."
MSG_FI[$MSG_STOP_SERVICES_FAILED]="RBK0048E: Virhe palveluita pysäytettäessä. RC %s."
MSG_FR[$MSG_STOP_SERVICES_FAILED]="RBK0048E: Une erreur code %s s'est produite lors de l'arrêt des services."
#MSG_SAVED_LOG_SYSLOG=49
#MSG_EN[$MSG_SAVED_LOG_SYSLOG]="RBK0049I: Messages saved in %s."
#MSG_DE[$MSG_SAVED_LOG_SYSLOG]="RBK0049I: Meldungen wurden in %s gesichert."
#MSG_FI[$MSG_SAVED_LOG_SYSLOG]="RBK0049I: Viestit tallennettu kohteeseen %s."
#MSG_FR[$MSG_SAVED_LOG_SYSLOG]="RBK0049I: Les messages ont été enregistrés sous %s."
MSG_RESTORING_FILE=50
MSG_EN[$MSG_RESTORING_FILE]="RBK0050I: Restoring backup from %s."
MSG_DE[$MSG_RESTORING_FILE]="RBK0050I: Backup wird von %s zurückgespielt."
MSG_FI[$MSG_RESTORING_FILE]="RBK0050I: Palautetaan varmuuskopiota kohteesta %s."
MSG_FR[$MSG_RESTORING_FILE]="RBK0050I: Restauration en cours à partir de %s."
MSG_TARGET_REQUIRES_GPT=51
MSG_EN[$MSG_TARGET_REQUIRES_GPT]="RBK0051W: Target %s with %s is larger than 2TB and requires gpt instead of mbr. Otherwise only 2TB will be used."
MSG_DE[$MSG_TARGET_REQUIRES_GPT]="RBK0051W: Ziel %s mit %s ist größer als 2TB und erfordert gpt statt mbr. Ansonsten werden nur 2TB genutzt."
MSG_FI[$MSG_TARGET_REQUIRES_GPT]="RBK0051W: Kohde %s kooltaan %s, on suurempi kuin 2Tt ja vaatii mbr:n sijasta gpt:n. Muutoin vain 2Tt voidaan käyttää."
MSG_FR[$MSG_TARGET_REQUIRES_GPT]="RBK0051W: La cible %s avec %s, est supérieure à 2 To et nécessite GPT au lieu de MBR. Sinon, seuls 2 To seront utilisés."
MSG_CREATING_PARTITIONS=52
MSG_EN[$MSG_CREATING_PARTITIONS]="RBK0052I: Creating partitions on %s."
MSG_DE[$MSG_CREATING_PARTITIONS]="RBK0052I: Partitionen werden auf %s erstellt."
MSG_FI[$MSG_CREATING_PARTITIONS]="RBK0052I: Luodaan osioita kohteelle %s."
MSG_FR[$MSG_CREATING_PARTITIONS]="RBK0052I: Les partitions seront créées sur %s."
MSG_RESTORING_FIRST_PARTITION=53
MSG_EN[$MSG_RESTORING_FIRST_PARTITION]="RBK0053I: Restoring first partition (boot partition) to %s."
MSG_DE[$MSG_RESTORING_FIRST_PARTITION]="RBK0053I: Erste Partition (Bootpartition) wird auf %s zurückgespielt."
MSG_FI[$MSG_RESTORING_FIRST_PARTITION]="RBK0053I: Palautetaan ensimmäistä osoita (käynnistysosio) kohteesen %s."
MSG_FR[$MSG_RESTORING_FIRST_PARTITION]="RBK0053I: La première partition (boot) sera restaurée vers %s."
MSG_FORMATTING_SECOND_PARTITION=54
MSG_EN[$MSG_FORMATTING_SECOND_PARTITION]="RBK0054I: Formating second partition (root partition) %s."
MSG_DE[$MSG_FORMATTING_SECOND_PARTITION]="RBK0054I: Zweite Partition (Rootpartition) %s wird formatiert."
MSG_FI[$MSG_FORMATTING_SECOND_PARTITION]="RBK0054I: Alustetaan toista osiota (juuriosio) %s."
MSG_FR[$MSG_FORMATTING_SECOND_PARTITION]="RBK0054I: La deuxième partition (partition root) %s sera formatée."
MSG_RESTORING_SECOND_PARTITION=55
MSG_EN[$MSG_RESTORING_SECOND_PARTITION]="RBK0055I: Restoring second partition (root partition) to %s."
MSG_DE[$MSG_RESTORING_SECOND_PARTITION]="RBK0055I: Zweite Partition (Rootpartition) wird auf %s zurückgespielt."
MSG_FI[$MSG_RESTORING_SECOND_PARTITION]="RBK0055I: Palautetaan toista osiota (juuriosio) kohteeseen %s."
MSG_FR[$MSG_RESTORING_SECOND_PARTITION]="RBK0055I: La deuxième partition (partition root) sera restaurée sur %s."
MSG_DEPLOYMENT_PARMS_ERROR=56
MSG_EN[$MSG_DEPLOYMENT_PARMS_ERROR]="RBK0056E: Incorrect deployment parameters. Use <hostname>@<username>."
MSG_DE[$MSG_DEPLOYMENT_PARMS_ERROR]="RBK0056E: Ungültige Deploymentparameter. Erforderliches Format: <hostname>@<username>."
MSG_FI[$MSG_DEPLOYMENT_PARMS_ERROR]="RBK0056E: Virheelliset käyttöönottoparametrit. Käytä <hostname>@<username>."
MSG_FR[$MSG_DEPLOYMENT_PARMS_ERROR]="RBK0056E: Paramètres de déploiement invalides. Format requis : <hostname>@<username>."
MSG_DOWNLOADING=57
MSG_EN[$MSG_DOWNLOADING]="RBK0057I: Downloading file %s from %s."
MSG_DE[$MSG_DOWNLOADING]="RBK0057I: Datei %s wird von %s downloaded."
MSG_FI[$MSG_DOWNLOADING]="RBK0057I: Ladataan tiedosta %s kohteesta %s."
MSG_FR[$MSG_DOWNLOADING]="RBK0057I: Téléchargement du fichier %s depuis %s."
MSG_INVALID_MSG_LEVEL=58
MSG_EN[$MSG_INVALID_MSG_LEVEL]="RBK0058E: Invalid parameter '%s' for option -m detected."
MSG_DE[$MSG_INVALID_MSG_LEVEL]="RBK0058E: Ungültiger Parameter '%s' für Option -m eingegeben."
MSG_FI[$MSG_INVALID_MSG_LEVEL]="RBK0058E: Havaittu epäkelpo parametri '%s' valinnalle -m."
MSG_FR[$MSG_INVALID_MSG_LEVEL]="RBK0058E: Paramètre invalide '%s' entré pour l'option -m."
#MSG_INVALID_LOG_OUTPUT=59
#MSG_EN[$MSG_INVALID_LOG_OUTPUT]="RBK0059W: Invalid parameter '%s' for option -L detected."
#MSG_DE[$MSG_INVALID_LOG_OUTPUT]="RBK0059W: Ungültiger Parameter '%s' für Option -L eingegeben."
#MSG_FI[$MSG_INVALID_LOG_OUTPUT]="RBK0059W: Havaittu epäkelpo parametri '%s' valinnalle -L."
#MSG_FR[$MSG_INVALID_LOG_OUTPUT]="RBK0059W: Paramètre invalide '%s' entré pour l'option -L."
MSG_NO_YES=60
MSG_EN[$MSG_NO_YES]="no yes"
MSG_DE[$MSG_NO_YES]="nein ja"
MSG_FI[$MSG_NO_YES]="ei kyllä"
MSG_FR[$MSG_NO_YES]="non oui"
MSG_BOOTPATITIONFILES_NOT_FOUND=61
MSG_EN[$MSG_BOOTPATITIONFILES_NOT_FOUND]="RBK0061E: Unable to find bootpartition files %s starting with %s."
MSG_DE[$MSG_BOOTPATITIONFILES_NOT_FOUND]="RBK0061E: Keine Bootpartitionsdateien in %s gefunden die mit %s beginnen."
MSG_FI[$MSG_BOOTPATITIONFILES_NOT_FOUND]="RBK0061E: Ei voida löytää käynnsitysosion tiedostoja %s, jotka alkavat %s"
MSG_FR[$MSG_BOOTPATITIONFILES_NOT_FOUND]="RBK0061E: Fichiers de partition de boot %s , commençant par %s introuvables."
MSG_NO_RESTOREDEVICE_DEFINED=62
MSG_EN[$MSG_NO_RESTOREDEVICE_DEFINED]="RBK0062E: No restoredevice defined (Example: /dev/sda)."
MSG_DE[$MSG_NO_RESTOREDEVICE_DEFINED]="RBK0062E: Kein Zurückspielgerät ist definiert (Beispiel: /dev/sda)."
MSG_FI[$MSG_NO_RESTOREDEVICE_DEFINED]="RBK0062E: Palautuslaitetta ei ole määritetty (Esimerkki: /dev/sda)."
MSG_FR[$MSG_NO_RESTOREDEVICE_DEFINED]="RBK0062E: Aucun périphérique de lecture défini (exemple:/dev/sda)."
MSG_NO_RESTOREDEVICE_FOUND=63
MSG_EN[$MSG_NO_RESTOREDEVICE_FOUND]="RBK0063E: Restoredevice %s not found (Example: /dev/sda)."
MSG_DE[$MSG_NO_RESTOREDEVICE_FOUND]="RBK0063E: Zurückspielgerät %s existiert nicht (Beispiel: /dev/sda)."
MSG_FI[$MSG_NO_RESTOREDEVICE_FOUND]="RBK0063E: Palautuslaitetta %s ei löytynyt (Esimerkki: /dev/sda)."
MSG_FR[$MSG_NO_RESTOREDEVICE_FOUND]="RBK0063E: Périphérique de restauration %s introuvable (ex:/dev/sda)."
MSG_ROOT_PARTTITION_NOT_FOUND=64
MSG_EN[$MSG_ROOT_PARTTITION_NOT_FOUND]="RBK0064E: Partition for rootpartition %s not found (Example: /dev/sdb1)."
MSG_DE[$MSG_ROOT_PARTTITION_NOT_FOUND]="RBK0064E: Partition für die Rootpartition %s nicht gefunden (Beispiel: /dev/sda)."
MSG_FI[$MSG_ROOT_PARTTITION_NOT_FOUND]="RBK0064E: Osiota juuriosiolle %s ei löytynyt (Esimerkki: /dev/sdb1)."
MSG_FR[$MSG_ROOT_PARTTITION_NOT_FOUND]="RBK0064E: La partition Root %s est introuvable (exemple:/dev/sdb1)."
MSG_REPARTITION_WARNING=65
MSG_EN[$MSG_REPARTITION_WARNING]="RBK0065W: Device %s will be repartitioned and all data will be lost."
MSG_DE[$MSG_REPARTITION_WARNING]="RBK0065W: Gerät %s wird repartitioniert und die gesamten Daten werden gelöscht."
MSG_FI[$MSG_REPARTITION_WARNING]="RBK0065W: Laite %s osioidaan uudelleen ja kaikki tieto hävitetään."
MSG_FR[$MSG_REPARTITION_WARNING]="RBK0065W: Le périphérique %s sera repartitionné, toutes les données seront perdues."
MSG_WARN_RESTORE_DEVICE_OVERWRITTEN=66
MSG_EN[$MSG_WARN_RESTORE_DEVICE_OVERWRITTEN]="RBK0066I: Device %s will be overwritten with the saved boot and root partition."
MSG_DE[$MSG_WARN_RESTORE_DEVICE_OVERWRITTEN]="RBK0066I: Gerät %s wird überschrieben mit der gesicherten Boot- und Rootpartition."
MSG_FI[$MSG_WARN_RESTORE_DEVICE_OVERWRITTEN]="RBK0066I: Laite %s ylikirjoitetaan tallennetuilla käynnistys- ja juuriosioilla."
MSG_FR[$MSG_WARN_RESTORE_DEVICE_OVERWRITTEN]="RBK0066I: Le périphérique %s sera écrasé par la procédure de boot et la partition Root."
MSG_CURRENT_PARTITION_TABLE=67
MSG_EN[$MSG_CURRENT_PARTITION_TABLE]="RBK0067I: Current partitions on %s:"
MSG_DE[$MSG_CURRENT_PARTITION_TABLE]="RBK0067I: Momentane Partitionen auf %s:"
MSG_FI[$MSG_CURRENT_PARTITION_TABLE]="RBK0067I: Nykyiset osiot kohteella %s:"
MSG_FR[$MSG_CURRENT_PARTITION_TABLE]="RBK0067I: Partitions actuelles sur %s:"
MSG_BOOTPATITIONFILES_FOUND=68
MSG_EN[$MSG_BOOTPATITIONFILES_FOUND]="RBK0068I: Using bootpartition backup files starting with %s from directory %s."
MSG_DE[$MSG_BOOTPATITIONFILES_FOUND]="RBK0068I: Bootpartitionsdateien des Backups aus dem Verzeichnis %s die mit %s beginnen werden benutzt."
MSG_FI[$MSG_BOOTPATITIONFILES_FOUND]="RBK0068I: Käytetään käynnistysosion %s alkavia varmuuskopiointitiedostoja hakemistosta %s."
MSG_FR[$MSG_BOOTPATITIONFILES_FOUND]="RBK0068I: Les fichiers sauvegardés pour le boot commençant par %s dans le répertoire %s sont utilisés."
MSG_WARN_BOOT_PARTITION_OVERWRITTEN=69
MSG_EN[$MSG_WARN_BOOT_PARTITION_OVERWRITTEN]="RBK0069I: Bootpartition %s will be formatted and will get the restored Boot partition."
MSG_DE[$MSG_WARN_BOOT_PARTITION_OVERWRITTEN]="RBK0069I: Bootpartition %s wird formatiert und erhält die zurückgespielte Bootpartition."
MSG_FI[$MSG_WARN_BOOT_PARTITION_OVERWRITTEN]="RBK0069I: Käynnistysosio %s alustetaan ja sille palautetaan varmuuskopioitu käynnistysosio"
MSG_FR[$MSG_WARN_BOOT_PARTITION_OVERWRITTEN]="RBK0069I: La partition de boot %s sera formatée pour recevoir la partition de boot restaurée"
MSG_WARN_ROOT_PARTITION_OVERWRITTEN=70
MSG_EN[$MSG_WARN_ROOT_PARTITION_OVERWRITTEN]="RBK0070I: Rootpartition %s will be formatted and will get the restored Root partition."
MSG_DE[$MSG_WARN_ROOT_PARTITION_OVERWRITTEN]="RBK0070I: Rootpartition %s wird formatiert und erhält die zurückgespielte Rootpartition."
MSG_FI[$MSG_WARN_ROOT_PARTITION_OVERWRITTEN]="RBK0070I: Juuriosio %s alustetaan ja sille palautetaan varmuuskopioitu juuriosio"
MSG_FR[$MSG_WARN_ROOT_PARTITION_OVERWRITTEN]="RBK0070I: La partition Root %s sera formatée et restaurée avec la partition sauvegardée"
MSG_QUERY_CHARS_YES_NO=71
MSG_EN[$MSG_QUERY_CHARS_YES_NO]="y/N"
MSG_DE[$MSG_QUERY_CHARS_YES_NO]="j/N"
MSG_FI[$MSG_QUERY_CHARS_YES_NO]="k/E"
MSG_FR[$MSG_QUERY_CHARS_YES_NO]="o/N"
MSG_SCRIPT_UPDATE_OK=72
MSG_EN[$MSG_SCRIPT_UPDATE_OK]="RBK0072I: %s updated from version %s to version %s. Previous version saved as %s. Don't forget to test backup and restore with the new version now."
MSG_DE[$MSG_SCRIPT_UPDATE_OK]="RBK0072I: %s von Version %s durch die aktuelle Version %s ersetzt. Die vorherige Version wurde als %s gesichert. Nicht vergessen den Backup und Restore mit der neuen Version zu testen."
MSG_FI[$MSG_SCRIPT_UPDATE_OK]="RBK0072I: %s on päivitetty versiosta %s versioon %s. Edellinen versio on tallennettu nimellä %s. Muista testata varmuuskopiointi ja palautus uudella versiolla."
MSG_FR[$MSG_SCRIPT_UPDATE_OK]="RBK0072I: %s mis à jour de la version %s à la version %s La version précédente a été sauvée sous %s. N'oubliez pas de tester une sauvegarde suivi d'une restauration avec cette version."
MSG_SCRIPT_UPDATE_NOT_NEEDED=73
MSG_EN[$MSG_SCRIPT_UPDATE_NOT_NEEDED]="RBK0073I: %s already current with version %s."
MSG_DE[$MSG_SCRIPT_UPDATE_NOT_NEEDED]="RBK0073I: %s bereits auf der aktuellen Version %s."
MSG_FI[$MSG_SCRIPT_UPDATE_NOT_NEEDED]="RBK0073I: %s on jo ajantasalla version %s kanssa."
MSG_FR[$MSG_SCRIPT_UPDATE_NOT_NEEDED]="RBK0073I: %s est déjà à jour avec la version %s."
MSG_SCRIPT_UPDATE_FAILED=74
MSG_EN[$MSG_SCRIPT_UPDATE_FAILED]="RBK0074E: Failed to update %s."
MSG_DE[$MSG_SCRIPT_UPDATE_FAILED]="RBK0074E: %s konnte nicht ersetzt werden."
MSG_FI[$MSG_SCRIPT_UPDATE_FAILED]="RBK0074E: %s päivitys epäonnistui."
MSG_FR[$MSG_SCRIPT_UPDATE_FAILED]="RBK0074E: Échec de la mise à jour de %s."
MSG_LINK_BOOTPARTITIONFILES=75
MSG_EN[$MSG_LINK_BOOTPARTITIONFILES]="RBK0075I: Using hardlinks to reuse bootpartition backups."
MSG_DE[$MSG_LINK_BOOTPARTITIONFILES]="RBK0075I: Hardlinks werden genutzt um Bootpartitionsbackups wiederzuverwenden."
MSG_FI[$MSG_LINK_BOOTPARTITIONFILES]="RBK0075I: Käytetään hardlink-tietoja käynnistysosion varmuuskopioihin. "
MSG_FR[$MSG_LINK_BOOTPARTITIONFILES]="RBK0075I: Les liens physiques sont utilisés pour réutiliser les sauvegardes de la partition de Boot."
MSG_RESTORE_OK=76
MSG_EN[$MSG_RESTORE_OK]="RBK0076I: Restore finished successfully."
MSG_DE[$MSG_RESTORE_OK]="RBK0076I: Restore erfolgreich beendet."
MSG_FI[$MSG_RESTORE_OK]="RBK0076I: Palautus suoritettu onnistuneesti."
MSG_FR[$MSG_RESTORE_OK]="RBK0076I: Restauration terminée avec succès."
MSG_RESTORE_FAILED=77
MSG_EN[$MSG_RESTORE_FAILED]="RBK0077E: Restore failed. Check previous error messages."
MSG_DE[$MSG_RESTORE_FAILED]="RBK0077E: Restore wurde fehlerhaft beendet. Siehe vorhergehende Fehlermeldungen."
MSG_FI[$MSG_RESTORE_FAILED]="RBK0077E: Palautus epäonnistui. Katso edelliest virheilmoitukset."
MSG_FR[$MSG_RESTORE_FAILED]="RBK0077E: La restauration a échoué. Vérifier les messages d'erreur."
MSG_BACKUP_TIME=78
MSG_EN[$MSG_BACKUP_TIME]="RBK0078I: Backup time: %s:%s:%s."
MSG_DE[$MSG_BACKUP_TIME]="RBK0078I: Backupzeit: %s:%s:%s."
MSG_FI[$MSG_BACKUP_TIME]="RBK0078I: Varmuuskopiointiin kulunut aika: %s:%s:%s."
MSG_FR[$MSG_BACKUP_TIME]="RBK0078I: Temps de sauvegarde: %s:%s:%s."
MSG_UNKNOWN_BACKUPTYPE_FOR_ZIP=79
MSG_EN[$MSG_UNKNOWN_BACKUPTYPE_FOR_ZIP]="RBK0079E: Option -z not allowed with backuptype %s."
MSG_DE[$MSG_UNKNOWN_BACKUPTYPE_FOR_ZIP]="RBK0079E: Option -z ist für Backuptyp %s nicht erlaubt."
MSG_FI[$MSG_UNKNOWN_BACKUPTYPE_FOR_ZIP]="RBK0079E: Valintaa -z ei voi käyttää varmuuskopiointityyppi %s:n kanssa"
MSG_FR[$MSG_UNKNOWN_BACKUPTYPE_FOR_ZIP]="RBK0079E: Option -z non autorisée avec ce type de sauvegarde %s."
MSG_NEW_VERSION_AVAILABLE=80
MSG_EN[$MSG_NEW_VERSION_AVAILABLE]="RBK0080I: $SMILEY_UPDATE_POSSIBLE There is a new version %s of $MYNAME available for download. You are running version %s and now can use option -U to upgrade your local version."
MSG_DE[$MSG_NEW_VERSION_AVAILABLE]="RBK0080I: $SMILEY_UPDATE_POSSIBLE Es gibt eine neue Version %s von $MYNAME zum downloaden. Die momentan benutze Version ist %s und es kann mit der Option -U die lokale Version aktualisiert werden."
MSG_FI[$MSG_NEW_VERSION_AVAILABLE]="RBK0080I: $SMILEY_UPDATE_POSSIBLE Uusi versio %s kohteesta $MYNAME on saatavilla. Käytät versiota %s ja voit käyttää valintaa -U päivittääksesi paikallisen version."
MSG_FR[$MSG_NEW_VERSION_AVAILABLE]="RBK0080I: $SMILEY_UPDATE_POSSIBLE Une nouvelle version %s de $MYNAME est disponible en téléchargement. vous exécutez la version %s et pouvez maintenant utiliser l'option -U pour la mettre à niveau."
MSG_BACKUP_TARGET=81
MSG_EN[$MSG_BACKUP_TARGET]="RBK0081I: Creating backup of type %s in %s."
MSG_DE[$MSG_BACKUP_TARGET]="RBK0081I: Backup vom Typ %s wird in %s erstellt."
MSG_FI[$MSG_BACKUP_TARGET]="RBK0081I: Luodaan %s-tyypin varmuuskopio kohteeseen %s."
MSG_FR[$MSG_BACKUP_TARGET]="RBK0081I: Création d'une sauvegarde de type %s dans %s."
MSG_EXISTING_BOOT_BACKUP=82
MSG_EN[$MSG_EXISTING_BOOT_BACKUP]="RBK0082I: Backup of boot partition alreday exists in %s."
MSG_DE[$MSG_EXISTING_BOOT_BACKUP]="RBK0082I: Backup der Bootpartition in %s existiert schon."
MSG_FI[$MSG_EXISTING_BOOT_BACKUP]="RBK0082I: Käynnistysosion varmuuskopio on jo olemassa kohteessa %s"
MSG_FR[$MSG_EXISTING_BOOT_BACKUP]="RBK0082I: La sauvegarde de la partition de Boot existe déjà dans %s"
MSG_EXISTING_PARTITION_BACKUP=83
MSG_EN[$MSG_EXISTING_PARTITION_BACKUP]="RBK0083I: Backup of partition layout already exists in %s."
MSG_DE[$MSG_EXISTING_PARTITION_BACKUP]="RBK0083I: Backup des Partitionlayouts in %s existiert schon."
MSG_FI[$MSG_EXISTING_PARTITION_BACKUP]="RBK0083I: Osioasettelun varmuuskopio on jo olemassa kohteessa %s."
MSG_FR[$MSG_EXISTING_PARTITION_BACKUP]="RBK0083I: La sauvegarde de la disposition de la partition existe déjà dans %s."
MSG_EXISTING_MBR_BACKUP=84
MSG_EN[$MSG_EXISTING_MBR_BACKUP]="RBK0084I: Backup of master boot record already exists in %s."
MSG_DE[$MSG_EXISTING_MBR_BACKUP]="RBK0084I: Backup des Masterbootrecords in %s existiert schon."
MSG_FI[$MSG_EXISTING_MBR_BACKUP]="RBK0084I: Master Boot Record-varmuuskopio on jo olemassa kohteessa %s."
MSG_FR[$MSG_EXISTING_MBR_BACKUP]="RBK0084I: La sauvegarde du MBR ,master boot record, existe déjà dans %s."
MSG_BACKUP_STARTED=85
MSG_EN[$MSG_BACKUP_STARTED]="RBK0085I: Backup of type %s started. Please be patient."
MSG_DE[$MSG_BACKUP_STARTED]="RBK0085I: Backuperstellung vom Typ %s gestartet. Bitte Geduld."
MSG_FI[$MSG_BACKUP_STARTED]="RBK0085I: %s-tyypin varmuuskopiointi on aloitettu. Ole hyvä ja odota."
MSG_FR[$MSG_BACKUP_STARTED]="RBK0085I: Démarrage de la sauvegarde de type %s SVP soyez patient."
MSG_RESTOREDEVICE_IS_PARTITION=86
MSG_EN[$MSG_RESTOREDEVICE_IS_PARTITION]="RBK0086E: Restore device has trailing partition number but cannot be a partition."
MSG_DE[$MSG_RESTOREDEVICE_IS_PARTITION]="RBK0086E: Wiederherstellungsgerät hat eine Partitionsnummer am Ende aber darf keine Partition sein."
MSG_FI[$MSG_RESTOREDEVICE_IS_PARTITION]="RBK0086E: Palautuslaitteella on osionumero, palautusta ei voida tehdä osiolle. "
MSG_FR[$MSG_RESTOREDEVICE_IS_PARTITION]="RBK0086E: Le périphérique de restauration a un numéro de partition la restauration ne peut pas être effectuée."
MSG_RESTORE_DIRECTORY_INVALID=87
MSG_EN[$MSG_RESTORE_DIRECTORY_INVALID]="RBK0087E: Restore directory %s was not created by $MYNAME."
MSG_DE[$MSG_RESTORE_DIRECTORY_INVALID]="RBK0087E: Wiederherstellungsverzeichnis %s wurde nicht von $MYNAME erstellt."
MSG_FI[$MSG_RESTORE_DIRECTORY_INVALID]="RBK0087E: $MYNAME ei luonut palautushakemistoa %s."
MSG_FR[$MSG_RESTORE_DIRECTORY_INVALID]="RBK0087E: Le répertoire de restauration %s n'a pas été créé par.$MYNAME."
MSG_RESTORE_DEVICE_NOT_ALLOWED=88
MSG_EN[$MSG_RESTORE_DEVICE_NOT_ALLOWED]="RBK0088E: -R option not supported for partitionbased backup."
MSG_DE[$MSG_RESTORE_DEVICE_NOT_ALLOWED]="RBK0088E: Option -R wird nicht beim partitionbasierten Backup unterstützt."
MSG_FI[$MSG_RESTORE_DEVICE_NOT_ALLOWED]="RBK0088E: Valintaa -R ei tueta osiopohjaisille varmuuskopioille."
MSG_FR[$MSG_RESTORE_DEVICE_NOT_ALLOWED]="RBK0088E: L'option -R n'est pas prise en charge pour une sauvegarde basée sur une partition."
MSG_UNKNOWN_OPTION=89
MSG_EN[$MSG_UNKNOWN_OPTION]="RBK0089E: Unknown option %s."
MSG_DE[$MSG_UNKNOWN_OPTION]="RBK0089E: Unbekannte Option %s."
MSG_FI[$MSG_UNKNOWN_OPTION]="RBK0089E: Tuntematon valinta %s."
MSG_FR[$MSG_UNKNOWN_OPTION]="RBK0089E: Option inconnue %s."
MSG_OPTION_REQUIRES_PARAMETER=90
MSG_EN[$MSG_OPTION_REQUIRES_PARAMETER]="RBK0090E: Option %s requires a parameter. If parameter starts with '-' start with '\-' instead."
MSG_DE[$MSG_OPTION_REQUIRES_PARAMETER]="RBK0090E: Option %s erwartet einen Parameter. Falls der Parameter mit '-' beginnt beginne stattdessen mit '\-'."
MSG_FI[$MSG_OPTION_REQUIRES_PARAMETER]="RBK0090E: Valinta %s vaatii parametrin. Jos parametri alkaa merkillä '-', korvaa se merkeillä '\-'."
MSG_FR[$MSG_OPTION_REQUIRES_PARAMETER]="RBK0090E: L'option %s requiert un paramètre. Si le paramètre commence par '-', commencez par '\-' à la place."
MSG_MENTION_HELP=91
MSG_EN[$MSG_MENTION_HELP]="RBK0091I: Invoke '%s -h' to get more detailed information of all script invocation parameters."
MSG_DE[$MSG_MENTION_HELP]="RBK0091I: '%s -h' liefert eine detailierte Beschreibung aller Scriptaufrufoptionen."
MSG_FI[$MSG_MENTION_HELP]="RBK0091I: Suorita '%s -h' saadaksesi lisätietoa skriptin parametreista."
MSG_FR[$MSG_MENTION_HELP]="RBK0091I: '%s -h' fournit une description détaillée de toutes les options du script"
MSG_PROCESSING_PARTITION=92
MSG_EN[$MSG_PROCESSING_PARTITION]="RBK0092I: Saving partition %s (%s) ..."
MSG_DE[$MSG_PROCESSING_PARTITION]="RBK0092I: Partition %s (%s) wird gesichert ..."
MSG_FI[$MSG_PROCESSING_PARTITION]="RBK0092I: Tallennetaan osiota %s (%s) ...."
MSG_FR[$MSG_PROCESSING_PARTITION]="RBK0092I: Sauvegarde de la partition %s (%s) ...."
MSG_PARTITION_NOT_FOUND=93
MSG_EN[$MSG_PARTITION_NOT_FOUND]="RBK0093E: Partition %s specified with option -T not found."
MSG_DE[$MSG_PARTITION_NOT_FOUND]="RBK0093E: Angegebene Partition %s der Option -T existiert nicht."
MSG_FI[$MSG_PARTITION_NOT_FOUND]="RBK0093E: Valinnalla -T tarkennettua osiota %s ei löytynyt."
MSG_FR[$MSG_PARTITION_NOT_FOUND]="RBK0093E: La partition %s spécifiée avec l'option -T est introuvable."
MSG_PARTITION_NUMBER_INVALID=94
MSG_EN[$MSG_PARTITION_NUMBER_INVALID]="RBK0094E: Parameter '%s' specified in option -T is not a number."
MSG_DE[$MSG_PARTITION_NUMBER_INVALID]="RBK0094E: Angegebener Parameter '%s' der Option -T ist keine Zahl."
MSG_FI[$MSG_PARTITION_NUMBER_INVALID]="RBK0094E: Valinnan -T parametri '%s' ei ole numero."
MSG_FR[$MSG_PARTITION_NUMBER_INVALID]="RBK0094E: Le paramètre '%s' spécifié pour l'option -T n'est pas un nombre."
MSG_RESTORING_PARTITIONFILE=95
MSG_EN[$MSG_RESTORING_PARTITIONFILE]="RBK0095I: Restoring partition %s."
MSG_DE[$MSG_RESTORING_PARTITIONFILE]="RBK0095I: Backup wird auf Partition %s zurückgespielt."
MSG_FI[$MSG_RESTORING_PARTITIONFILE]="RBK0095I: Palautetaan osiota %s."
MSG_FR[$MSG_RESTORING_PARTITIONFILE]="RBK0095I: Restauration de la partition %s."
MSG_LANGUAGE_NOT_SUPPORTED=96
MSG_EN[$MSG_LANGUAGE_NOT_SUPPORTED]="RBK0096I: Language %s not supported."
MSG_DE[$MSG_LANGUAGE_NOT_SUPPORTED]="RBK0096I: Die Sprache %s wird nicht unterstützt."
MSG_FI[$MSG_LANGUAGE_NOT_SUPPORTED]="RBK0096I: Kieli %s ei ole tuettu."
MSG_FR[$MSG_LANGUAGE_NOT_SUPPORTED]="RBK0096I: Langue %s non prise en charge."
MSG_PARTITIONING_SDCARD=97
MSG_EN[$MSG_PARTITIONING_SDCARD]="RBK0097I: Partitioning and formating %s."
MSG_DE[$MSG_PARTITIONING_SDCARD]="RBK0097I: Partitioniere und formatiere %s."
MSG_FI[$MSG_PARTITIONING_SDCARD]="RBK0097I: Osioidaan ja alustetaan %s."
MSG_FR[$MSG_PARTITIONING_SDCARD]="RBK0097I: Partitionnement et formatage %s."
MSG_FORMATTING=98
MSG_EN[$MSG_FORMATTING]="RBK0098I: Formatting partition %s with %s (%s)."
MSG_DE[$MSG_FORMATTING]="RBK0098I: Formatiere Partition %s mit %s (%s)."
MSG_FI[$MSG_FORMATTING]="RBK0098I: Alustetaan osio %s tiedostojärjestelmälle %s (%s)"
MSG_FR[$MSG_FORMATTING]="RBK0098I: Formatage de la partition %s avec %s (%s)"
MSG_RESTORING_FILE_PARTITION_DONE=99
MSG_EN[$MSG_RESTORING_FILE_PARTITION_DONE]="RBK0099I: Restore of partition %s finished."
MSG_DE[$MSG_RESTORING_FILE_PARTITION_DONE]="RBK0099I: Zurückspielen des Backups auf Partition %s beendet."
MSG_FI[$MSG_RESTORING_FILE_PARTITION_DONE]="RBK0099I: Osio %s palautettu."
MSG_FR[$MSG_RESTORING_FILE_PARTITION_DONE]="RBK0099I: Restauration de la partition %s terminée."
MSG_WARN_RESTORE_PARTITION_DEVICE_OVERWRITTEN=100
MSG_EN[$MSG_WARN_RESTORE_PARTITION_DEVICE_OVERWRITTEN]="RBK0100W: Device %s will be overwritten with the backup."
MSG_DE[$MSG_WARN_RESTORE_PARTITION_DEVICE_OVERWRITTEN]="RBK0100W: Gerät %s wird mit dem Backup beschrieben."
MSG_FI[$MSG_WARN_RESTORE_PARTITION_DEVICE_OVERWRITTEN]="RBK0100W: Palautus ylikirjoittaa laitteen %s."
MSG_FR[$MSG_WARN_RESTORE_PARTITION_DEVICE_OVERWRITTEN]="RBK0100W: Le périphérique %s sera écrasé par la sauvegarde"
MSG_VERSION_HISTORY_PAGE=101
MSG_EN[$MSG_VERSION_HISTORY_PAGE]="$MYHOMEURL/en/versionhistory/"
MSG_DE[$MSG_VERSION_HISTORY_PAGE]="$MYHOMEURL/de/versionshistorie/"
MSG_FI[$MSG_VERSION_HISTORY_PAGE]="$MYHOMEURL/en/versionhistory/" #  Defaults to en
MSG_FR[$MSG_VERSION_HISTORY_PAGE]="$MYHOMEURL/en/versionhistory/" #  Defaults to en
MSG_UPDATING_UUID=102
MSG_EN[$MSG_UPDATING_UUID]="RBK0102I: Updating %s from %s to %s in %s."
MSG_DE[$MSG_UPDATING_UUID]="RBK0102I: %s wird von %s auf %s in %s geändert."
MSG_FI[$MSG_UPDATING_UUID]="RBK0102I: Päivitetään %s arvosta %s arvoon %s kohteessa %s."
MSG_FR[$MSG_UPDATING_UUID]="RBK0102I: mise à jour %s de %s à %s en %s."
MSG_UNABLE_TO_WRITE=103
MSG_EN[$MSG_UNABLE_TO_WRITE]="RBK0103E: Unable to create backup on %s because of missing write permission."
MSG_DE[$MSG_UNABLE_TO_WRITE]="RBK0103E: Ein Backup kann nicht auf %s erstellt werden da die Schreibberechtigung fehlt."
MSG_FI[$MSG_UNABLE_TO_WRITE]="RBK0103E: Varmuuskopion luominen kohteeseen %s ei onnistu puuttuvien kirjoitusoikeuksien vuoksi."
MSG_FR[$MSG_UNABLE_TO_WRITE]="RBK0103E: Impossible de créer une sauvegarde sur %s en raison d'un manque d'autorisation en écriture."
MSG_LABELING=104
MSG_EN[$MSG_LABELING]="RBK0104I: Labeling partition %s with label %s."
MSG_DE[$MSG_LABELING]="RBK0104I: Partition %s erhält das Label %s."
MSG_FI[$MSG_LABELING]="RBK0104I: Nimetään osio %s nimikkeellä %s."
MSG_FR[$MSG_LABELING]="RBK0104I: L'étiquette de la partition est %s."
MSG_REMOVING_BACKUP_FAILED=105
MSG_EN[$MSG_REMOVING_BACKUP_FAILED]="RBK0105E: Removing incomplete backup in %s failed with RC %s. Directory has to be cleaned up manually."
MSG_DE[$MSG_REMOVING_BACKUP_FAILED]="RBK0105E: Löschen des unvollständigen Backups in %s schlug fehl mit RC: %s. Das Verzeichnis muss manuell gelöscht werden."
MSG_FI[$MSG_REMOVING_BACKUP_FAILED]="RBK0105E: Keskeneräisen varmuuskopion poistaminen kohteesta %s epäonnistui, RC %s. Hakemisto tulee tyhjentää manuaalisesti."
MSG_FR[$MSG_REMOVING_BACKUP_FAILED]="RBK0105E: Échec de la suppression de la sauvegarde incomplète dans %s , code erreur %s. Supprimez manuellement le répertoire."
MSG_DEPLOYMENT_FAILED=106
MSG_EN[$MSG_DEPLOYMENT_FAILED]="RBK0106E: Installation of $MYNAME failed on server %s for user %s."
MSG_DE[$MSG_DEPLOYMENT_FAILED]="RBK0106E: Installation von $MYNAME auf Server %s für Benutzer %s fehlgeschlagen."
MSG_FI[$MSG_DEPLOYMENT_FAILED]="RBK0106E: $MYNAME asennus epäonnistui palvelimella %s käyttäjälle %s."
MSG_FR[$MSG_DEPLOYMENT_FAILED]="RBK0106E: L'installation de $MYNAME a échoué sur le serveur %s pour l'utilisateur %s."
MSG_EXTENSION_FAILED=107
MSG_EN[$MSG_EXTENSION_FAILED]="RBK0107W: Extension %s failed with RC %s."
MSG_DE[$MSG_EXTENSION_FAILED]="RBK0107W: Erweiterung %s fehlerhaft beendet mit RC %s."
MSG_FI[$MSG_EXTENSION_FAILED]="RBK0107W: Lisäosa %s epäonnistui, RC %s."
MSG_FR[$MSG_EXTENSION_FAILED]="RBK0107W: Échec de l'extension , code erreur %s."
MSG_SKIPPING_UNFORMATTED_PARTITION=108
MSG_EN[$MSG_SKIPPING_UNFORMATTED_PARTITION]="RBK0108W: Unformatted partition %s (%s) not saved."
MSG_DE[$MSG_SKIPPING_UNFORMATTED_PARTITION]="RBK0108W: Unformatierte Partition %s (%s) wird nicht gesichert."
MSG_FI[$MSG_SKIPPING_UNFORMATTED_PARTITION]="RBK0108W: Alustamatonta osiota %s (%s) ei tallennettu."
MSG_FR[$MSG_SKIPPING_UNFORMATTED_PARTITION]="RBK0108W: Partition non formatée %s (%s) non enregistrée."
MSG_UNSUPPORTED_FILESYSTEM_FORMAT=109
MSG_EN[$MSG_UNSUPPORTED_FILESYSTEM_FORMAT]="RBK0109E: Unsupported filesystem %s detected on partition %s."
MSG_DE[$MSG_UNSUPPORTED_FILESYSTEM_FORMAT]="RBK0109E: Nicht unterstütztes Filesystem %s auf Partition %s."
MSG_FI[$MSG_UNSUPPORTED_FILESYSTEM_FORMAT]="RBK0109E: Tiedostojärjestelmää %s joka havaittiin osiolla %s, ei tueta."
MSG_FR[$MSG_UNSUPPORTED_FILESYSTEM_FORMAT]="RBK0109E: Système de fichiers non pris en charge %s sur la partition %s."
MSG_UNABLE_TO_COLLECT_PARTITIONINFO=110
MSG_EN[$MSG_UNABLE_TO_COLLECT_PARTITIONINFO]="RBK0110E: Unable to collect partition data with %s. RC %s."
MSG_DE[$MSG_UNABLE_TO_COLLECT_PARTITIONINFO]="RBK0110E: Partitionsdaten können nicht mit %s gesammelt werden. RC %s."
MSG_FI[$MSG_UNABLE_TO_COLLECT_PARTITIONINFO]="RBK0110E: Osiotietojen kerääminen epäonnistui käyttämällä komentoa %s. RC %s."
MSG_FR[$MSG_UNABLE_TO_COLLECT_PARTITIONINFO]="RBK0110E: Impossible de collecter les données de la partition  %s. Code erreur %s."
MSG_UNABLE_TO_CREATE_PARTITIONS=111
MSG_EN[$MSG_UNABLE_TO_CREATE_PARTITIONS]="RBK0111E: Error occured when partitions were created. RC %s - %s."
MSG_DE[$MSG_UNABLE_TO_CREATE_PARTITIONS]="RBK0111E: Fehler beim Erstellen der Partitionen. RC %s - %s."
MSG_FI[$MSG_UNABLE_TO_CREATE_PARTITIONS]="RBK0111E: Virhe osioiden luomisen yhteydessä. RC %s - %s."
MSG_FR[$MSG_UNABLE_TO_CREATE_PARTITIONS]="RBK0111E: Erreur pendant la création des partitions. code erreur %s - %s."
MSG_PROCESSED_PARTITION=112
MSG_EN[$MSG_PROCESSED_PARTITION]="RBK0112I: Partition %s was saved."
MSG_DE[$MSG_PROCESSED_PARTITION]="RBK0112I: Partition %s wurde gesichert."
MSG_FI[$MSG_PROCESSED_PARTITION]="RBK0112I: Osio % tallennettiin."
MSG_FR[$MSG_PROCESSED_PARTITION]="RBK0112I: La partition %s a été enregistrée."
MSG_YES_NO_DEVICE_MISMATCH=113
MSG_EN[$MSG_YES_NO_DEVICE_MISMATCH]="RBK0113E: Restore device %s doesn't match %s."
MSG_DE[$MSG_YES_NO_DEVICE_MISMATCH]="RBK0113E: Wiederherstellungsgerät %s ähnelt nicht %s."
MSG_FI[$MSG_YES_NO_DEVICE_MISMATCH]="RBK0113E: Palautuslaite %s ja %s eivät täsmää."
MSG_FR[$MSG_YES_NO_DEVICE_MISMATCH]="RBK0113E: Le périphérique de restauration %s ne correspond pas à %s."
MSG_VISIT_VERSION_HISTORY_PAGE=114
MSG_EN[$MSG_VISIT_VERSION_HISTORY_PAGE]="RBK0114I: Visit %s to read about the changes in the new version."
MSG_DE[$MSG_VISIT_VERSION_HISTORY_PAGE]="RBK0114I: Besuche %s um die Änderungen in der neuen Version kennenzulernen."
MSG_FI[$MSG_VISIT_VERSION_HISTORY_PAGE]="RBK0114I: Käy sivulla %s lukeaksesi uuden version muutoksista."
MSG_FR[$MSG_VISIT_VERSION_HISTORY_PAGE]="RBK0114I: Visitez %s pour être informé des changements dans la nouvelle version."
MSG_DEPLOYED_HOST=115
MSG_EN[$MSG_DEPLOYED_HOST]="RBK0115I: $MYNAME $VERSION ($GIT_COMMIT_ONLY) installed on host %s for user %s."
MSG_DE[$MSG_DEPLOYED_HOST]="RBK0115I: $MYNAME $VERSION ($GIT_COMMIT_ONLY) wurde auf Server %s für Benutzer %s installiert."
MSG_FI[$MSG_DEPLOYED_HOST]="RBK0115I: $MYNAME $VERSION ($GIT_COMMIT_ONLY) asennettu isäntälaitteen %s käyttäjälle %s."
MSG_FR[$MSG_DEPLOYED_HOST]="RBK0115I: $MYNAME $VERSION ($GIT_COMMIT_ONLY) a été installé sur le serveur %s pour l'utilisateur %s."
MSG_INCLUDED_CONFIG=116
MSG_EN[$MSG_INCLUDED_CONFIG]="RBK0116I: Using config file %s."
MSG_DE[$MSG_INCLUDED_CONFIG]="RBK0116I: Konfigurationsdatei %s wird benutzt."
MSG_FI[$MSG_INCLUDED_CONFIG]="RBK0116I: Käytetään asetustiedostoa %s."
MSG_FR[$MSG_INCLUDED_CONFIG]="RBK0116I: Utilisation en cours du fichier de configuration %s."
MSG_CURRENT_SCRIPT_VERSION=117
MSG_EN[$MSG_CURRENT_SCRIPT_VERSION]="RBK0117I: Current script version: %s"
MSG_DE[$MSG_CURRENT_SCRIPT_VERSION]="RBK0117I: Aktuelle Scriptversion: %s"
MSG_FI[$MSG_CURRENT_SCRIPT_VERSION]="RBK0117I: Nykyisen skriptin vesio: %s"
MSG_FR[$MSG_CURRENT_SCRIPT_VERSION]="RBK0117I: Version actuelle du script: %s"
MSG_AVAILABLE_VERSIONS_HEADER=118
MSG_EN[$MSG_AVAILABLE_VERSIONS_HEADER]="RBK0118I: Available versions:"
MSG_DE[$MSG_AVAILABLE_VERSIONS_HEADER]="RBK0118I: Verfügbare Scriptversionen:"
MSG_FI[$MSG_AVAILABLE_VERSIONS_HEADER]="RBK0118I: Saatavilla olevat versiot:"
MSG_FR[$MSG_AVAILABLE_VERSIONS_HEADER]="RBK0118I: Versions disponibles:"
MSG_AVAILABLE_VERSIONS=119
MSG_EN[$MSG_AVAILABLE_VERSIONS]="RBK0119I: %s: %s"
MSG_DE[$MSG_AVAILABLE_VERSIONS]="RBK0119I: %s: %s"
MSG_FI[$MSG_AVAILABLE_VERSIONS]="RBK0119I: %s: %s"
MSG_FR[$MSG_AVAILABLE_VERSIONS]="RBK0119I: %s: %s"
MSG_SAVING_ACTUAL_VERSION=120
MSG_EN[$MSG_SAVING_ACTUAL_VERSION]="RBK0120I: Saving current version %s to %s."
MSG_DE[$MSG_SAVING_ACTUAL_VERSION]="RBK0120I: Aktuelle Version %s wird in %s gesichert."
MSG_FI[$MSG_SAVING_ACTUAL_VERSION]="RBK0120I: Tallennetaan nykyinen versio %s nimellä %s."
MSG_FR[$MSG_SAVING_ACTUAL_VERSION]="RBK0120I: Enregistrement de la version actuelle %s dans %s."
MSG_RESTORING_PREVIOUS_VERSION=121
MSG_EN[$MSG_RESTORING_PREVIOUS_VERSION]="RBK0121I: Restoring previous version %s to %s."
MSG_DE[$MSG_RESTORING_PREVIOUS_VERSION]="RBK0121I: Vorherige Version %s wird in %s wiederhergestellt."
MSG_FI[$MSG_RESTORING_PREVIOUS_VERSION]="RBK0121I: Palautetaan edellinen versio %s nimellä %s."
MSG_FR[$MSG_RESTORING_PREVIOUS_VERSION]="RBK0121I: Restauration de la version précédente %s vers %s."
MSG_SELECT_VERSION=122
MSG_EN[$MSG_SELECT_VERSION]="RBK0122I: Select version to restore (%s-%s)"
MSG_DE[$MSG_SELECT_VERSION]="RBK0122I: Auswahl der Version die wiederhergestellt werden soll (%s-%s)"
MSG_FI[$MSG_SELECT_VERSION]="RBK0122I: Valitse palautettava versio (%s-%s)"
MSG_FR[$MSG_SELECT_VERSION]="RBK0122I: Sélectionnez la version à restaurer (%s-%s)"
MSG_NO_PREVIOUS_VERSIONS_AVAILABLE=123
MSG_EN[$MSG_NO_PREVIOUS_VERSIONS_AVAILABLE]="RBK0123E: No version to restore available."
MSG_DE[$MSG_NO_PREVIOUS_VERSIONS_AVAILABLE]="RBK0123E: Keine Version zum Restore verfügbar."
MSG_FI[$MSG_NO_PREVIOUS_VERSIONS_AVAILABLE]="RBK0123E: Ei aiempia versioita palautettavaksi."
MSG_FR[$MSG_NO_PREVIOUS_VERSIONS_AVAILABLE]="RBK0123E: Aucune version à restaurer disponible."
MSG_FAKE_MODE_ON=124
MSG_EN[$MSG_FAKE_MODE_ON]="RBK0124W: Fake mode on."
MSG_DE[$MSG_FAKE_MODE_ON]="RBK0124W: Simulationsmodus an."
MSG_FI[$MSG_FAKE_MODE_ON]="RBK0124W: Simulaatiotila päällä"
MSG_FR[$MSG_FAKE_MODE_ON]="RBK0124W: Mode simulation activé"
MSG_UNUSED_PARAMETERS=125
MSG_EN[$MSG_UNUSED_PARAMETERS]="RBK0125W: Unused option(s) \"%s\" detected. There may be quotes missing in option arguments."
MSG_DE[$MSG_UNUSED_PARAMETERS]="RBK0125W: Unbenutzte Option(en) \" %s\" entdeckt. Es scheinen Anführungszeichen bei Optionsargumenten zu fehlen."
MSG_FI[$MSG_UNUSED_PARAMETERS]="RBK0125W: Havaittu käyttämättömiä valintoja \"%s\". Lainausmerkkejä saattaa puuttua valintojen argumenteista."
MSG_FR[$MSG_UNUSED_PARAMETERS]="RBK0125W: Option(s) non utilisable(s) \"%s\" . Les guillemets semblent manquer dans les arguments d'option.."
MSG_REPLACING_FILE_BY_HARDLINK=126
MSG_EN[$MSG_REPLACING_FILE_BY_HARDLINK]="RBK0126I: Replacing %s with hardlink to %s."
MSG_DE[$MSG_REPLACING_FILE_BY_HARDLINK]="RBK0126I: Datei %s wird durch einem Hardlink auf %s ersetzt."
MSG_FI[$MSG_REPLACING_FILE_BY_HARDLINK]="RBK0126I: Korvataan %s hardlink-tiedolla kohteeseen %s."
MSG_FR[$MSG_REPLACING_FILE_BY_HARDLINK]="RBK0126I: Remplacement de %s par un lien physique vers %s."
MSG_DEPLOYING_HOST_OFFLINE=127
MSG_EN[$MSG_DEPLOYING_HOST_OFFLINE]="RBK0127E: Server %s offline."
MSG_DE[$MSG_DEPLOYING_HOST_OFFLINE]="RBK0127E: Server %s ist nicht erreichbar."
MSG_FI[$MSG_DEPLOYING_HOST_OFFLINE]="RBK0127E: Palvelin %s on offline-tilassa"
MSG_FR[$MSG_DEPLOYING_HOST_OFFLINE]="RBK0127E: Serveur %s hors ligne."
#MSG_USING_LOGFILE=128
#MSG_EN[$MSG_USING_LOGFILE]="RBK0128I: Using logfile %s."
#MSG_DE[$MSG_USING_LOGFILE]="RBK0128I: Logdatei ist %s."
#MSG_FI[$MSG_USING_LOGFILE]="RBK0128I: Käytetään lokitiedostoa %s."
#MSG_FR[$MSG_USING_LOGFILE]="RBK0128I: Le fichier journal : %s."
MSG_EMAIL_EXTENSION_NOT_FOUND=129
MSG_EN[$MSG_EMAIL_EXTENSION_NOT_FOUND]="RBK0129W: email extension %s not found."
MSG_DE[$MSG_EMAIL_EXTENSION_NOT_FOUND]="RBK0129W: Email Erweiterung %s nicht gefunden."
MSG_FI[$MSG_EMAIL_EXTENSION_NOT_FOUND]="RBK0129W: Sähköpostilisäosaa %s ei löytynyt."
MSG_FR[$MSG_EMAIL_EXTENSION_NOT_FOUND]="RBK0129W: Extension de l'e-mail %s absente."
MSG_MISSING_FILEPARAMETER=130
MSG_EN[$MSG_MISSING_FILEPARAMETER]="RBK0130E: Missing backup- or restorepath parameter."
MSG_DE[$MSG_MISSING_FILEPARAMETER]="RBK0130E: Backup- oder Restorepfadparameter fehlt."
MSG_FI[$MSG_MISSING_FILEPARAMETER]="RBK0130E: Varmuuskopiointi- tai palautushakemistoparametri puuttuu."
MSG_FR[$MSG_MISSING_FILEPARAMETER]="RBK0130E: Paramêtre manquant: chemin de sauvegarde ou de restauration."
MSG_MISSING_INSTALLED_FILE=131
MSG_EN[$MSG_MISSING_INSTALLED_FILE]="RBK0131E: Program %s not found. Use 'sudo apt-get update; sudo apt-get install %s' to install the missing program."
MSG_DE[$MSG_MISSING_INSTALLED_FILE]="RBK0131E: Programm %s nicht gefunden. Mit 'sudo apt-get update; sudo apt-get install %s' wird das fehlende Programm installiert."
MSG_FI[$MSG_MISSING_INSTALLED_FILE]="RBK0131E: Sovellusta %s ei löytynyt. Suorita 'sudo apt-get update; sudo apt-get install %s' asentaaksesi puuttuvan sovelluksen."
MSG_FR[$MSG_MISSING_INSTALLED_FILE]="RBK0131E: Programme %s introuvable. Utilisez 'sudo apt-get update ; sudo apt-get install %s' pour installer le programme manquant."
MSG_SKIPPING_CREATING_PARTITIONS=132
MSG_EN[$MSG_SKIPPING_CREATING_PARTITIONS]="RBK0132W: No partitions are created. Reusing existing partitions."
MSG_DE[$MSG_SKIPPING_CREATING_PARTITIONS]="RBK0132W: Es werden keine Partitionen erstellt sondern die existierenden Partitionen benutzt."
MSG_FI[$MSG_SKIPPING_CREATING_PARTITIONS]="RBK0132W: Osioita ei luotu. Käytetään olemassaolevia osioita."
MSG_FR[$MSG_SKIPPING_CREATING_PARTITIONS]="RBK0132W: Aucune partition n'est créée. Réutiliser des partitions existantes."
MSG_HARDLINK_DIRECTORY_USED=133
MSG_EN[$MSG_HARDLINK_DIRECTORY_USED]="RBK0133I: Using directory %s for hardlinks."
MSG_DE[$MSG_HARDLINK_DIRECTORY_USED]="RBK0133I: Verzeichnis %s wird für Hardlinks benutzt."
MSG_FI[$MSG_HARDLINK_DIRECTORY_USED]="RBK0133I: Käytetään hakemistoa %s hardlink-tiedoille."
MSG_FR[$MSG_HARDLINK_DIRECTORY_USED]="RBK0133I: Le répertoire %s est utilisé pour les liens physiques."
MSG_UNABLE_TO_USE_HARDLINKS=134
MSG_EN[$MSG_UNABLE_TO_USE_HARDLINKS]="RBK0134E: Unable to use hardlinks on %s for bootpartition files. RC %s."
MSG_DE[$MSG_UNABLE_TO_USE_HARDLINKS]="RBK0134E: Hardlinkslinks können nicht auf %s für Bootpartitionsdateien benutzt werden. RC %s."
MSG_FI[$MSG_UNABLE_TO_USE_HARDLINKS]="RBK0134E: Hardlink-tietoja kohteessa %s ei voitu käyttäää käynnistysosion tiedostoille. RC %s."
MSG_FR[$MSG_UNABLE_TO_USE_HARDLINKS]="RBK0134E: Les liens physiques non utilisables sur %s pour les fichiers de partition de Boot. Code erreur %s."
MSG_SCRIPT_IS_DEPRECATED=135
MSG_EN[$MSG_SCRIPT_IS_DEPRECATED]="RBK0135W: ==> Current script version %s has a severe bug and should be updated immediately <==="
MSG_DE[$MSG_SCRIPT_IS_DEPRECATED]="RBK0135W: ==> Aktuelle Scriptversion %s enthält einen gravierenden Fehler und sollte sofort aktualisiert werden <==="
MSG_FI[$MSG_SCRIPT_IS_DEPRECATED]="RBK0135W: ==> Nykyisessä skriptiversiossa %s on vakava bugi ja se tulee päivittää välittömästi <==="
MSG_FR[$MSG_SCRIPT_IS_DEPRECATED]="RBK0135W: ==> La version actuelle du script %s a un bogue grave qui impose une mise à jour immédiatement <==="
MSG_MISSING_START_OR_STOP=136
MSG_EN[$MSG_MISSING_START_OR_STOP]="RBK0136E: Missing mandatory option %s."
MSG_DE[$MSG_MISSING_START_OR_STOP]="RBK0136E: Es fehlt die obligatorische Option %s."
MSG_FI[$MSG_MISSING_START_OR_STOP]="RBK0136E: Pakollinen valinta %s puuttuu."
MSG_FR[$MSG_MISSING_START_OR_STOP]="RBK0136E: Option obligatoire manquante %s."
MSG_NO_ROOTBACKUPFILE_FOUND=137
MSG_EN[$MSG_NO_ROOTBACKUPFILE_FOUND]="RBK0137E: Rootbackupfile for type %s not found."
MSG_DE[$MSG_NO_ROOTBACKUPFILE_FOUND]="RBK0137E: Rootbackupdatei für den Typ %s nicht gefunden."
MSG_FI[$MSG_NO_ROOTBACKUPFILE_FOUND]="RBK0137E: Juurivarmuuskopiota ei löytynyt tyypille %s."
MSG_FR[$MSG_NO_ROOTBACKUPFILE_FOUND]="RBK0137E: Fichier de sauvegarde Root pour le type %s introuvable."
MSG_USING_ROOTBACKUPFILE=138
MSG_EN[$MSG_USING_ROOTBACKUPFILE]="RBK0138I: Using rootbackup %s."
MSG_DE[$MSG_USING_ROOTBACKUPFILE]="RBK0138I: Rootbackup %s wird benutzt."
MSG_FI[$MSG_USING_ROOTBACKUPFILE]="RBK0138I: Käytetään käynnistysvarmuuskopiota %s."
MSG_FR[$MSG_USING_ROOTBACKUPFILE]="RBK0138I: La sauvegarde Root %s est en cours d'utilisation."
MSG_FORCING_CREATING_PARTITIONS=139
MSG_EN[$MSG_FORCING_CREATING_PARTITIONS]="RBK0139W: Partition creation ignores errors."
MSG_DE[$MSG_FORCING_CREATING_PARTITIONS]="RBK0139W: Partitionserstellung ignoriert Fehler."
MSG_FI[$MSG_FORCING_CREATING_PARTITIONS]="RBK0139W: Osion luonti ohittaa virheet."
MSG_FR[$MSG_FORCING_CREATING_PARTITIONS]="RBK0139W: Les erreurs sont ignorées lors de la création de partition."
#MSG_LABELS_NOT_SUPPORTED=140
#MSG_EN[$MSG_LABELS_NOT_SUPPORTED]="RBK0140E: LABEL definitions in /etc/fstab not supported. Use PARTUUID instead."
#MSG_DE[$MSG_LABELS_NOT_SUPPORTED]="RBK0140E: LABEL Definitionen sind in /etc/fstab nicht unterstützt. Benutze stattdessen PARTUUID."
#MSG_FI[$MSG_LABELS_NOT_SUPPORTED]="RBK0140E: LABEL määrityksiä tiedostossa /etc/fstab ei tueta. Käytä PARTUUID-määrityksiä."
#MSG_FR[$MSG_LABELS_NOT_SUPPORTED]="RBK0140E: LABEL Les définitions dans /etc/fstab ne sont pas prises en charge. Utilisez PARTUUID."
MSG_SAVING_USED_PARTITIONS_ONLY=141
MSG_EN[$MSG_SAVING_USED_PARTITIONS_ONLY]="RBK0141I: Saving space of defined partitions only."
MSG_DE[$MSG_SAVING_USED_PARTITIONS_ONLY]="RBK0141I: Nur der von den definierten Partitionen belegte Speicherplatz wird gesichert."
MSG_FI[$MSG_SAVING_USED_PARTITIONS_ONLY]="RBK0141I: Tilaa säästetään vain määritellyillä osioilla."
MSG_FR[$MSG_SAVING_USED_PARTITIONS_ONLY]="RBK0141I: Seul l'espace occupé par les partitions définies est sauvegardé."
MSG_NO_BOOTDEVICE_FOUND=142
MSG_EN[$MSG_NO_BOOTDEVICE_FOUND]="RBK0142E: Unable to detect boot device. Please report this issue on https://github.com/framps/raspiBackup/issues or https://www.linux-tips-and-tricks.de/en/rmessages"
MSG_DE[$MSG_NO_BOOTDEVICE_FOUND]="RBK0142E: Bootgerät kann nicht erkannt werden. Bitte das Problem auf https://github.com/framps/raspiBackup/issues oder auf https://www.linux-tips-and-tricks.de/de/fehlermeldungen melden."
MSG_FI[$MSG_NO_BOOTDEVICE_FOUND]="RBK0142E: Käynnistyslaitetta ei havaittu. Ole hyvä ja raportoi ongelmasta osoitteessa https://github.com/framps/raspiBackup/issues tai https://www.linux-tips-and-tricks.de/en/rmessages" #The 2nd link refers defaults to to en-vesion
MSG_FR[$MSG_NO_BOOTDEVICE_FOUND]="RBK0142E: Le périphérique de Boot n'est pas reconnu. Veuillez signaler le problème sur https://github.com/framps/raspiBackup/issues ou sur  https://www.linux-tips-and-tricks.de/en/rmessages" #Le 2eme lien renvoie vers la version anglaise
MSG_FORCE_SFDISK=143
MSG_EN[$MSG_FORCE_SFDISK]="RBK0143W: Target %s does not match with backup. Partitioning forced."
MSG_DE[$MSG_FORCE_SFDISK]="RBK0143W: Ziel %s passt nicht zu dem Backup. Partitionierung wird trotzdem vorgenommen."
MSG_FI[$MSG_FORCE_SFDISK]="RBK0143W: Kohde %s ei täsmää varmuuskopion kanssa. Pakotetaan osiointi."
MSG_FR[$MSG_FORCE_SFDISK]="RBK0143W: La cible %s ne correspond pas à la sauvegarde. Partitionnement forcé."
MSG_SKIP_SFDISK=144
MSG_EN[$MSG_SKIP_SFDISK]="RBK0144W: Target %s will not be partitioned. Using existing partitions."
MSG_DE[$MSG_SKIP_SFDISK]="RBK0144W: Ziel %s wird nicht partitioniert. Existierende Partitionen werden benutzt."
MSG_FI[$MSG_SKIP_SFDISK]="RBK0144W: Kohdetta %s ei osioida. Käytetään olemassaolevia osioita."
MSG_FR[$MSG_SKIP_SFDISK]="RBK0144W: La cible %s ne sera pas partitionné. Les partitions existantes sont utilisées."
MSG_SKIP_CREATING_PARTITIONS=145
MSG_EN[$MSG_SKIP_CREATING_PARTITIONS]="RBK0145W: Partition creation skipped. Using existing partitions."
MSG_DE[$MSG_SKIP_CREATING_PARTITIONS]="RBK0145W: Partitionen werden nicht erstellt. Existierende Paritionen werden benutzt."
MSG_FI[$MSG_SKIP_CREATING_PARTITIONS]="RBK0145W: Osion luonti ohitettu. Käytetään olemassaolevia osioita."
MSG_FR[$MSG_SKIP_CREATING_PARTITIONS]="RBK0145W: Création de partition ignorée. Les partitions existantes sont utilisées."
MSG_NO_PARTITION_TABLE_DEFINED=146
MSG_EN[$MSG_NO_PARTITION_TABLE_DEFINED]="RBK0146I: No partitiontable found on %s."
MSG_DE[$MSG_NO_PARTITION_TABLE_DEFINED]="RBK0146I: Keine Partitionstabelle auf %s gefunden."
MSG_FI[$MSG_NO_PARTITION_TABLE_DEFINED]="RBK0146I: Osiotaulukkoa ei löytynyt laitteella %s."
MSG_FR[$MSG_NO_PARTITION_TABLE_DEFINED]="RBK0146I: Aucune table de partition trouvée sur %s."
MSG_BACKUP_PARTITION_FAILED=147
MSG_EN[$MSG_BACKUP_PARTITION_FAILED]="RBK0147E: Backup of partition %s failed with RC %s."
MSG_DE[$MSG_BACKUP_PARTITION_FAILED]="RBK0147E: Sicherung der Partition %s schlug fehl mit RC %s."
MSG_FI[$MSG_BACKUP_PARTITION_FAILED]="RBK0147E: Osion %s varmuuskopiointi epäonnistui, RC %s."
MSG_FR[$MSG_BACKUP_PARTITION_FAILED]="RBK0147E: La sauvegarde de la partition %s a échoué, code erreur %s."
MSG_STACK_TRACE=148
MSG_EN[$MSG_STACK_TRACE]="RBK0148E: @@@@@@@@@@@@@@@@@@@@ Stacktrace @@@@@@@@@@@@@@@@@@@@"
MSG_DE[$MSG_STACK_TRACE]="RBK0148E: @@@@@@@@@@@@@@@@@@@@ Stacktrace @@@@@@@@@@@@@@@@@@@@"
MSG_FI[$MSG_STACK_TRACE]="RBK0148E: @@@@@@@@@@@@@@@@@@@@ Stacktrace @@@@@@@@@@@@@@@@@@@@"
MSG_FR[$MSG_STACK_TRACE]="RBK0148E: @@@@@@@@@@@@@@@@@@@@ Stacktrace @@@@@@@@@@@@@@@@@@@@"
MSG_FILE_ARG_NOT_FOUND=149
MSG_EN[$MSG_FILE_ARG_NOT_FOUND]="RBK0149E: File %s does not exist."
MSG_DE[$MSG_FILE_ARG_NOT_FOUND]="RBK0149E: Datei %s existiert nicht."
MSG_FI[$MSG_FILE_ARG_NOT_FOUND]="RBK0149E: Tiedostoa %s ei ole."
MSG_FR[$MSG_FILE_ARG_NOT_FOUND]="RBK0149E: Le fichier %s n'existe pas."
MSG_MAX_4GB_LIMIT=150
MSG_EN[$MSG_MAX_4GB_LIMIT]="RBK0150W: Maximum file size in backup directory %s is limited to 4GB."
MSG_DE[$MSG_MAX_4GB_LIMIT]="RBK0150W: Maximale Dateigröße im Backupverzeichnis %s ist auf 4GB begrenzt."
MSG_FI[$MSG_MAX_4GB_LIMIT]="RBK0150W: Suurin tiedoston koko varmuuskopion hakemistossa %s on 4Gt."
MSG_FR[$MSG_MAX_4GB_LIMIT]="RBK0150W: La taille maximale du fichier dans le répertoire de sauvegarde %s est limitée à 4 Go."
MSG_USING_BACKUPPATH=151
MSG_EN[$MSG_USING_BACKUPPATH]="RBK0151I: Using backuppath %s with partition type %s."
MSG_DE[$MSG_USING_BACKUPPATH]="RBK0151I: Backuppfad %s mit Partitionstyp %s wird benutzt."
MSG_FI[$MSG_USING_BACKUPPATH]="RBK0151I: Käytetään varmuuskopiointihakemistoa %s osiotyypin %s kanssa."
MSG_FR[$MSG_USING_BACKUPPATH]="RBK0151I: Le chemin de sauvegarde %s du type de partition %s est utilisé."
MSG_MKFS_FAILED=152
MSG_EN[$MSG_MKFS_FAILED]="RBK0152E: Unable to create filesystem: '%s' - RC: %s."
MSG_DE[$MSG_MKFS_FAILED]="RBK0152E: Dateisystem kann nicht erstellt werden: '%s' - RC: %s."
MSG_FI[$MSG_MKFS_FAILED]="RBK0152E: Ei voitu luoda tiedostojärjestelmää: '%s' - RC: %s."
MSG_FR[$MSG_MKFS_FAILED]="RBK0152E: Création du fichiers système '%s' impossible - Code erreur: %s."
MSG_LABELING_FAILED=153
MSG_EN[$MSG_LABELING_FAILED]="RBK0153E: Unable to label partition: '%s' - RC: %s."
MSG_DE[$MSG_LABELING_FAILED]="RBK0153E: Partition kann nicht mit einem Label versehen werden: '%s' - RC: %s."
MSG_FI[$MSG_LABELING_FAILED]="RBK0153E: Ei voitu nimetä osiota: '%s' - RC: %s."
MSG_FR[$MSG_LABELING_FAILED]="RBK0153E: Impossible d'étiqueter la partition : '%s' - Code erreur: %s."
MSG_RESTORE_DEVICE_MOUNTED=154
MSG_EN[$MSG_RESTORE_DEVICE_MOUNTED]="RBK0154E: Restore is not possible when a partition of device %s is mounted."
MSG_DE[$MSG_RESTORE_DEVICE_MOUNTED]="RBK0154E: Ein Restore ist nicht möglich wenn eine Partition von %s gemounted ist."
MSG_FI[$MSG_RESTORE_DEVICE_MOUNTED]="RBK0154E: Palautus ei ole mahdollista laitteen %s osion ollessa käyttöönotettuna."
MSG_FR[$MSG_RESTORE_DEVICE_MOUNTED]="RBK0154E: Restauration impossible si une partition du périphérique %s est montée."
MSG_INVALID_RESTORE_ROOT_PARTITION=155
MSG_EN[$MSG_INVALID_RESTORE_ROOT_PARTITION]="RBK0155E: Restore root partition %s is no partition."
MSG_DE[$MSG_INVALID_RESTORE_ROOT_PARTITION]="RBK0155E: Ziel Rootpartition %s ist keine Partition."
MSG_FI[$MSG_INVALID_RESTORE_ROOT_PARTITION]="RBK0155E: Palautettava juuriosio %s ei ole osio."
MSG_FR[$MSG_INVALID_RESTORE_ROOT_PARTITION]="RBK0155E: La partition Root cible %s n'est pas une partition."
MSG_SKIP_STARTING_SERVICES=156
MSG_EN[$MSG_SKIP_STARTING_SERVICES]="RBK0156W: No services to start."
MSG_DE[$MSG_SKIP_STARTING_SERVICES]="RBK0156W: Keine Systemd Services sind zu starten."
MSG_FI[$MSG_SKIP_STARTING_SERVICES]="RBK0156W: Ei käynnistettäviä palveluita."
MSG_FR[$MSG_SKIP_STARTING_SERVICES]="RBK0156W: Pas de service système à démarrer."
MSG_SKIP_STOPPING_SERVICES=157
MSG_EN[$MSG_SKIP_STOPPING_SERVICES]="RBK0157W: No services to stop."
MSG_DE[$MSG_SKIP_STOPPING_SERVICES]="RBK0157W: Keine Systemd Services sind zu stoppen."
MSG_FI[$MSG_SKIP_STOPPING_SERVICES]="RBK0157W: Ei pysäytettäviä palveluita."
MSG_FR[$MSG_SKIP_STOPPING_SERVICES]="RBK0157W: Aucun service système à arrêter."
MSG_MAIN_BACKUP_PROGRESSING=158
MSG_EN[$MSG_MAIN_BACKUP_PROGRESSING]="RBK0158I: Creating native %s backup %s."
MSG_DE[$MSG_MAIN_BACKUP_PROGRESSING]="RBK0158I: %s Backup %s wird erstellt."
MSG_FI[$MSG_MAIN_BACKUP_PROGRESSING]="RBK0158I: Luodaan natiivi %s-varmuuskopio kohteeseen %s."
MSG_FR[$MSG_MAIN_BACKUP_PROGRESSING]="RBK0158I: Création en cours de la sauvegarde %s."
MSG_BACKUPS_KEPT=159
MSG_EN[$MSG_BACKUPS_KEPT]="RBK0159I: %s backups kept for %s backup type. Please be patient."
MSG_DE[$MSG_BACKUPS_KEPT]="RBK0159I: %s Backups werden für den Backuptyp %s aufbewahrt. Bitte Geduld."
MSG_FI[$MSG_BACKUPS_KEPT]="RBK0159I: %s varmuuskopiota pidetään %s-varmuuskopiotyypille. Ole hyvä ja odota."
MSG_FR[$MSG_BACKUPS_KEPT]="RBK0159I: %s sauvegardes sont conservées pour le type de sauvegarde %s SVP patientez."
MSG_TARGETSD_SIZE_TOO_SMALL=160
MSG_EN[$MSG_TARGETSD_SIZE_TOO_SMALL]="RBK0160E: Target %s with %s is smaller than backup source with %s."
MSG_DE[$MSG_TARGETSD_SIZE_TOO_SMALL]="RBK0160E: Ziel %s mit %s ist kleiner als die Backupquelle mit %s."
MSG_FI[$MSG_TARGETSD_SIZE_TOO_SMALL]="RBK0160E: Kohde %s koollaan %s on pienempi kuin varmuuskopion lähde kooltaan %s."
MSG_FR[$MSG_TARGETSD_SIZE_TOO_SMALL]="RBK0160E: La cible %s avec %s est plus petite que la source de sauvegarde avec %s."
MSG_TARGETSD_SIZE_BIGGER=161
MSG_EN[$MSG_TARGETSD_SIZE_BIGGER]="RBK0161W: Target %s with %s is larger than backup source with %s. You waste %s."
MSG_DE[$MSG_TARGETSD_SIZE_BIGGER]="RBK0161W: Ziel %s mit %s ist größer als die Backupquelle mit %s. %s sind ungenutzt."
MSG_FI[$MSG_TARGETSD_SIZE_BIGGER]="RBK0161W: Kohde %s koollaan %s on suurempi kuin varmuuskopion lähde kooltaan %s. %s jää hyödyntämättä."
MSG_FR[$MSG_TARGETSD_SIZE_BIGGER]="RBK0161W: La cible %s avec %s est plus grande que la source de sauvegarde avec %s. %s sont inutilisés."
MSG_RESTORE_ABORTED=162
MSG_EN[$MSG_RESTORE_ABORTED]="RBK0162I: Restore aborted."
MSG_DE[$MSG_RESTORE_ABORTED]="RBK0162I: Restore abgebrochen."
MSG_FI[$MSG_RESTORE_ABORTED]="RBK0162I: Palautus keskeytetty."
MSG_FR[$MSG_RESTORE_ABORTED]="RBK0162I: Restauration annulée."
MSG_CTRLC_DETECTED=163
MSG_EN[$MSG_CTRLC_DETECTED]="RBK0163E: Script execution canceled with CTRL C."
MSG_DE[$MSG_CTRLC_DETECTED]="RBK0163E: Scriptausführung mit CTRL C abgebrochen."
MSG_FI[$MSG_CTRLC_DETECTED]="RBK0163E: Skriptin suoritus peruutettu CTRL C-näppäinyhdistelmällä."
MSG_FR[$MSG_CTRLC_DETECTED]="RBK0163E: Exécution du script interrompue avec CTRL C."
MSG_HARDLINK_ERROR=164
MSG_EN[$MSG_HARDLINK_ERROR]="RBK0164E: Unable to create hardlinks on %s. RC %s."
MSG_DE[$MSG_HARDLINK_ERROR]="RBK0164E: Es können keine Hardlinks auf %s erstellt werden. RC %s."
MSG_FI[$MSG_HARDLINK_ERROR]="RBK0164E: Hardlink-tietojen luonti epäonnistui %s. RC %s."
MSG_FR[$MSG_HARDLINK_ERROR]="RBK0164E: Les liens physiques ne peuvent pas être créés %s. Code erreur %s."
MSG_INTRO_BETA_MESSAGE=165
MSG_EN[$MSG_INTRO_BETA_MESSAGE]="RBK0165W: =========> NOTE  <========= \
${NL}!!! RBK0165W: This is a betaversion and should not be used in production. \
${NL}!!! RBK0165W: =========> NOTE <========="
MSG_DE[$MSG_INTRO_BETA_MESSAGE]="RBK0165W: =========> HINWEIS <========= \
${NL}!!! RBK0165W: Dieses ist eine Betaversion welche nicht in Produktion benutzt werden sollte. \
${NL}!!! RBK0165W: =========> HINWEIS <========="
MSG_FI[$MSG_INTRO_BETA_MESSAGE]="RBK0165W: =========> HUOM <========= \
${NL}!!! RBK0165W: Tämä on betaversio, jota ei tule käyttää tuotannossa. \
${NL}!!! RBK0165W: =========> HUOM <========= (FI)"
MSG_FR[$MSG_INTRO_BETA_MESSAGE]="RBK0165W: =========> REMARQUE <========= \
${NL}!!! RBK0165W: Ceci est une version bêta qui ne doit pas être utilisée en production. \
${NL}!!! RBK0165W: =========> REMARQUE <========= (FI)"
MSG_UMOUNT_ERROR=166
MSG_EN[$MSG_UMOUNT_ERROR]="RBK0166E: Umount for %s failed. RC %s. Maybe mounted somewhere else?"
MSG_DE[$MSG_UMOUNT_ERROR]="RBK0166E: Umount für %s fehlerhaft. RC %s. Vielleicht noch woanders gemounted?"
MSG_FI[$MSG_UMOUNT_ERROR]="RBK0166E: Osion %s käytöstä poisto (umount) epäonnistui. RC %s. Jokin muu käyttää sitä mahdollisesti?"
MSG_FR[$MSG_UMOUNT_ERROR]="RBK0166E: Umount incorrect pour %s Code erreur %s. Peut-elle être montée ailleurs ?"
MSG_SENDING_EMAIL=167
MSG_EN[$MSG_SENDING_EMAIL]="RBK0167I: Sending email."
MSG_DE[$MSG_SENDING_EMAIL]="RBK0167I: Eine eMail wird versendet."
MSG_FI[$MSG_SENDING_EMAIL]="RBK0167I: Lähetetään sähköposti."
MSG_FR[$MSG_SENDING_EMAIL]="RBK0167I: Envoi d'un e-mail."
MSG_BETAVERSION_AVAILABLE=168
MSG_EN[$MSG_BETAVERSION_AVAILABLE]="RBK0168I: $SMILEY_BETA_AVAILABLE $MYSELF beta version %s is available. Any help to test this beta is appreciated. Just upgrade to the new beta version with option -U. Restore to the previous version with option -V"
MSG_DE[$MSG_BETAVERSION_AVAILABLE]="RBK0168I: $SMILEY_BETA_AVAILABLE $MYSELF Beta Version %s ist verfügbar. Hilfe beim Testen dieser Beta ist sehr willkommen. Einfach auf die neue Beta Version mit der Option -U upgraden. Die vorhergehende Version kann mit der Option -V wiederhergestellt werden"
MSG_FI[$MSG_BETAVERSION_AVAILABLE]="RBK0168I: $SMILEY_BETA_AVAILABLE $MYSELF betaversio %s on saatavilla. Betatestaajien apua arvostetaan. Päivitä uuteen betaversioon valinnalla -U. Palaa edelliseen versioon valinnalla -V"
MSG_FR[$MSG_BETAVERSION_AVAILABLE]="RBK0168I: $SMILEY_BETA_AVAILABLE $MYSELF La version bêta %s est disponible. Une aide pour tester cette version bêta est la bienvenue. Passez simplement à la nouvelle version bêta avec l'option -U. La version précédente peut être restaurée avec l'option -V "
MSG_ROOT_PARTITION_NOT_FOUND=169
MSG_EN[$MSG_ROOT_PARTITION_NOT_FOUND]="RBK0169E: Target root partition %s does not exist."
MSG_DE[$MSG_ROOT_PARTITION_NOT_FOUND]="RBK0169E: Ziel Rootpartition %s existiert nicht."
MSG_FI[$MSG_ROOT_PARTITION_NOT_FOUND]="RBK0169E: Kohdejuuriosiota %s ei ole."
MSG_FR[$MSG_ROOT_PARTITION_NOT_FOUND]="RBK0169E: La partition Root cible %s n'existe pas."
MSG_MISSING_R_OPTION=170
MSG_EN[$MSG_MISSING_R_OPTION]="RBK0170E: Backup uses an external root partition. -R option missing."
MSG_DE[$MSG_MISSING_R_OPTION]="RBK0170E: Backup benutzt eine externe root Partition. Die Option -R fehlt."
MSG_FI[$MSG_MISSING_R_OPTION]="RBK0170E: Varmuuskopiointi käyttää ulkoista juurihakemistoa. Valinta -R puuttuu-"
MSG_FR[$MSG_MISSING_R_OPTION]="RBK0170E: La sauvegarde utilise une partition Root externe. L'option -R est manquante"
MSG_NOPARTITIONS_TOBACKUP_FOUND=171
MSG_EN[$MSG_NOPARTITIONS_TOBACKUP_FOUND]="RBK0171E: Unable to detect any partitions to backup."
MSG_DE[$MSG_NOPARTITIONS_TOBACKUP_FOUND]="RBK0171E: Es können keine zu sichernde Partitionen gefunden werden."
MSG_FI[$MSG_NOPARTITIONS_TOBACKUP_FOUND]="RBK0171E: Varmuuskopioitavia osioita ei havaittu."
MSG_FR[$MSG_NOPARTITIONS_TOBACKUP_FOUND]="RBK0171E: Aucune partition à sauvegarder n'a été trouvée"
MSG_UNABLE_TO_CREATE_DIRECTORY=172
MSG_EN[$MSG_UNABLE_TO_CREATE_DIRECTORY]="RBK0172E: Unable to create directory %s."
MSG_DE[$MSG_UNABLE_TO_CREATE_DIRECTORY]="RBK0172E: Verzeichnis %s kann nicht erstellt werden."
MSG_FI[$MSG_UNABLE_TO_CREATE_DIRECTORY]="RBK0172E: Hakemistoa %s ei voida luoda."
MSG_FR[$MSG_UNABLE_TO_CREATE_DIRECTORY]="RBK0172E: Impossible de créer le répertoire %s."
MSG_INTRO_HOTFIX_MESSAGE=173
MSG_EN[$MSG_INTRO_HOTFIX_MESSAGE]="RBK0173W: =========> NOTE  <========= \
${NL}!!! RBK0173W: This is a temporary hotfix and has to be upgraded to next available version as soon as one is available. \
${NL}!!! RBK0173W: =========> NOTE <========="
MSG_DE[$MSG_INTRO_HOTFIX_MESSAGE]="RBK0173W: =========> HINWEIS <========= \
${NL}!!! RBK0173W: Dieses ist ein temporärer Hotfix der auf die nächste Version upgraded werden muss sobald eine verfügbar ist. \
${NL}!!! RBK0173W: =========> HINWEIS <========="
MSG_FI[$MSG_INTRO_HOTFIX_MESSAGE]="RBK0173W: =========> HUOM  <========= \
${NL}!!! RBK0173W: Tämä on väliaikainen pikakorjaus ja tulee päivittää heti, kun uudempi versio on saatavilla. \
${NL}!!! RBK0173W: =========> HUOM <========="
MSG_FR[$MSG_INTRO_HOTFIX_MESSAGE]="RBK0173W: =========> REMARQUE  <========= \
${NL}!!! RBK0173W: Il s'agit d'un correctif temporaire qui doit être mis à niveau dans la prochaine version dès qu'elle sera disponible. \
${NL}!!! RBK0173W: =========> REMARQUE <========="
MSG_TOOL_ERROR_SKIP=174
MSG_EN[$MSG_TOOL_ERROR_SKIP]="RBK0174I: Backup tool %s error %s ignored. For errormessages see log file."
MSG_DE[$MSG_TOOL_ERROR_SKIP]="RBK0174I: Backupprogramm %s Fehler %s wurde ignoriert. Fehlermeldungen finden sich im Logfile."
MSG_FI[$MSG_TOOL_ERROR_SKIP]="RBK0174I: Varmuuskopiotyökalun %s virhe %s ohitettiin. Lue virheviestit lokitiedostosta."
MSG_FR[$MSG_TOOL_ERROR_SKIP]="RBK0174I: L'erreur %s lors de la sauvegarde a été ignorée. Les messages peuvent être consultés dans le fichier journal."
MSG_SCRIPT_UPDATE_NOT_REQUIRED=175
MSG_EN[$MSG_SCRIPT_UPDATE_NOT_REQUIRED]="RBK0175I: %s version %s is newer than version %s."
MSG_DE[$MSG_SCRIPT_UPDATE_NOT_REQUIRED]="RBK0175I: %s Version %s ist aktueller als Version %s."
MSG_FI[$MSG_SCRIPT_UPDATE_NOT_REQUIRED]="RBK0175I: %s:n versio %s on uudempi kuin versio %s."
MSG_FR[$MSG_SCRIPT_UPDATE_NOT_REQUIRED]="RBK0175I: %s version %s est plus récent que cette version %s."
MSG_RSYNC_DOES_NOT_SUPPORT_PROGRESS=176
MSG_EN[$MSG_RSYNC_DOES_NOT_SUPPORT_PROGRESS]="RBK0173E: rsync version %s doesn't support progress information."
MSG_DE[$MSG_RSYNC_DOES_NOT_SUPPORT_PROGRESS]="RBK0173E: rsync Version %s unterstüzt keine Fortschrittsanzeige."
MSG_FI[$MSG_RSYNC_DOES_NOT_SUPPORT_PROGRESS]="RBK0173E: rsyncin versio %s ei tue edistymisen seurantaa."
MSG_FR[$MSG_RSYNC_DOES_NOT_SUPPORT_PROGRESS]="RBK0173E: rsync version %s ne prend pas en charge l'affichage de la progression."
MSG_ALL_BACKUPS_KEPT=177
MSG_EN[$MSG_ALL_BACKUPS_KEPT]="RBK0177W: All backups kept for backup type %s."
MSG_DE[$MSG_ALL_BACKUPS_KEPT]="RBK0177W: Alle Backups werden für den Backuptyp %s aufbewahrt."
MSG_FI[$MSG_ALL_BACKUPS_KEPT]="RBK0177W: Kaikki varmuuskopiot pidetään varmuuskopiointityypille %s."
MSG_FR[$MSG_ALL_BACKUPS_KEPT]="RBK0177W: Toutes les sauvegardes sont conservées pour le type %s."
MSG_IMG_BOOT_BACKUP_FAILED=178
MSG_EN[$MSG_IMG_BOOT_BACKUP_FAILED]="RBK0178E: Creation of %s failed with RC %s. Usually the SD card is buggy. Option -B may help."
MSG_DE[$MSG_IMG_BOOT_BACKUP_FAILED]="RBK0178E: Erzeugung von %s Datei endet fehlerhaft mit RC %s. Normalerweise ist die SD Karte fehlerhaft. Option -B kann helfen."
MSG_FI[$MSG_IMG_BOOT_BACKUP_FAILED]="RBK0178E: %s:n luominen epäonnistui, RC %s."
MSG_FR[$MSG_IMG_BOOT_BACKUP_FAILED]="RBK0178E: La création de %s a échoué avec le code erreur %s."
MSG_IMG_BOOT_RESTORE_FAILED=179
MSG_EN[$MSG_IMG_BOOT_RESTORE_FAILED]="RBK0179E: Restore of %s file failed with RC %s."
MSG_DE[$MSG_IMG_BOOT_RESTORE_FAILED]="RBK0179E: Wiederherstellung von %s Datei endet fehlerhaft mit RC %s."
MSG_FI[$MSG_IMG_BOOT_RESTORE_FAILED]="RBK0179E: %s-tiedoston palautus epäonnistui, RC %s."
MSG_FR[$MSG_IMG_BOOT_RESTORE_FAILED]="RBK0179E: La restauration du fichier %s a échoué acec le code erreur %s."
MSG_FORMATTING_FIRST_PARTITION=180
MSG_EN[$MSG_FORMATTING_FIRST_PARTITION]="RBK0180I: Formating first partition (boot partition) %s."
MSG_DE[$MSG_FORMATTING_FIRST_PARTITION]="RBK0180I: Erste Partition (Bootpartition) %s wird formatiert."
MSG_FI[$MSG_FORMATTING_FIRST_PARTITION]="RBK0180I: Alustetaan ensimmäinen osio (käynnistysosio) %s."
MSG_FR[$MSG_FORMATTING_FIRST_PARTITION]="RBK0180I: Formatage de la première partition (partition de Boot) %s."
MSG_AFTER_STARTING_SERVICES=181
MSG_EN[$MSG_AFTER_STARTING_SERVICES]="RBK0181I: Executing commands post backup: '%s'."
MSG_DE[$MSG_AFTER_STARTING_SERVICES]="RBK0181I: Nach dem Backup ausgeführte Befehle: '%s'."
MSG_FI[$MSG_AFTER_STARTING_SERVICES]="RBK0181I: Suoritetaan varmuuskopioinnin jälkeiset komennot: '%s'."
MSG_FR[$MSG_AFTER_STARTING_SERVICES]="RBK0181I: Commandes exécutées après la sauvegarde: '%s'."
MSG_BEFORE_STOPPING_SERVICES=182
MSG_EN[$MSG_BEFORE_STOPPING_SERVICES]="RBK0182I: Executing commands pre backup: '%s'."
MSG_DE[$MSG_BEFORE_STOPPING_SERVICES]="RBK0182I: Vor dem Backup ausgeführte Befehle: '%s'."
MSG_FI[$MSG_BEFORE_STOPPING_SERVICES]="RBK0182I: Suoritetaan varmuuskopiointia edeltävät komennot: '%s'."
MSG_FR[$MSG_BEFORE_STOPPING_SERVICES]="RBK0182I: Commandes exécutées avant la sauvegarde: '%s'."
MSG_IMG_ROOT_CHECK_FAILED=183
MSG_EN[$MSG_IMG_ROOT_CHECK_FAILED]="RBK0183E: Rootpartition check failed with RC %s."
MSG_DE[$MSG_IMG_ROOT_CHECK_FAILED]="RBK0183E: Rootpartitionscheck endet fehlerhaft mit RC %s."
MSG_FI[$MSG_IMG_ROOT_CHECK_FAILED]="RBK0183E: Juuriosion tarkistus epäonnistui, RC %s."
MSG_FR[$MSG_IMG_ROOT_CHECK_FAILED]="RBK0183E: La vérification de la partition Root a échoué ,code erreur %s."
MSG_IMG_ROOT_CHECK_STARTED=184
MSG_EN[$MSG_IMG_ROOT_CHECK_STARTED]="RBK0184I: Rootpartition check started."
MSG_DE[$MSG_IMG_ROOT_CHECK_STARTED]="RBK0184I: Rootpartitionscheck gestartet."
MSG_FI[$MSG_IMG_ROOT_CHECK_STARTED]="RBK0184I: Juuriosion tarkistus aloitettu."
MSG_FR[$MSG_IMG_ROOT_CHECK_STARTED]="RBK0184I: Début de la vérification de la partition Root."
MSG_IMG_BOOT_CREATE_PARTITION_FAILED=185
MSG_EN[$MSG_IMG_BOOT_CREATE_PARTITION_FAILED]="RBK0185E: Bootpartition creation failed with RC %s."
MSG_DE[$MSG_IMG_BOOT_CREATE_PARTITION_FAILED]="RBK0185E: Bootpartitionserstellung endet fehlerhaft mit RC %s."
MSG_FI[$MSG_IMG_BOOT_CREATE_PARTITION_FAILED]="RBK0185E: Käynnistysosion luonti epäonnistui, RC %s."
MSG_FR[$MSG_IMG_BOOT_CREATE_PARTITION_FAILED]="RBK0185E: La création de la partition Boot a échoué , code erreur %s."
MSG_IMG_ROOT_CREATE_PARTITION_FAILED=186
MSG_EN[$MSG_IMG_ROOT_CREATE_PARTITION_FAILED]="RBK0185E: Rootpartition creation failed with RC %s."
MSG_DE[$MSG_IMG_ROOT_CREATE_PARTITION_FAILED]="RBK0185E: Rootpartitionserstellung endet fehlerhaft mit RC %s."
MSG_FI[$MSG_IMG_ROOT_CREATE_PARTITION_FAILED]="RBK0185E: Juuriosion luonti epäonnistui, RC %s."
MSG_FR[$MSG_IMG_ROOT_CREATE_PARTITION_FAILED]="RBK0185E: La création de la partition Root a échoué , code erreur %s."
MSG_DETAILED_ROOT_CHECKING=187
MSG_EN[$MSG_DETAILED_ROOT_CHECKING]="RBK0187W: Rootpartition %s will be checked for bad blocks during formatting. This will take some time. Please be patient."
MSG_DE[$MSG_DETAILED_ROOT_CHECKING]="RBK0187W: Rootpartitionsformatierung für %s prüft auf fehlerhafte Blocks. Das wird länger dauern. Bitte Geduld."
MSG_FI[$MSG_DETAILED_ROOT_CHECKING]="RBK0187W: Juuriosio %s tarkistetaan viallisten lohkojen varalta alustuksen aikana. Tämä vie jonkin aikaa. Ole hyvä ja odota."
MSG_FR[$MSG_DETAILED_ROOT_CHECKING]="RBK0187W: La partition Root %s sera vérifiée pour détecter les blocs lors du formatage. SVP  soyez patient..."
MSG_UPDATE_TO_BETA=188
MSG_EN[$MSG_UPDATE_TO_BETA]="RBK0188I: There is a Beta version of $MYSELF available. Upgrading current version %s to %s."
MSG_DE[$MSG_UPDATE_TO_BETA]="RBK0188I: Es ist eine Betaversion von $MYSELF verfügbar. Die momentane Version %s auf %s upgraden."
MSG_FI[$MSG_UPDATE_TO_BETA]="RBK0188I: $MYSELF betaversio on saatavilla. Päivitä nykyinen versio %s versioon %s."
MSG_FR[$MSG_UPDATE_TO_BETA]="RBK0188I: Une version bêta de $MYSELF est disponible. Mettez à niveau la version actuelle %s vers %s."
MSG_UPDATE_ABORTED=189
MSG_EN[$MSG_UPDATE_ABORTED]="RBK0189I: Version upgrade aborted."
MSG_DE[$MSG_UPDATE_ABORTED]="RBK0189I: Versionsupgrade abgebrochen."
MSG_FI[$MSG_UPDATE_ABORTED]="RBK0189I: Versiopäivitys keskeytetty."
MSG_FR[$MSG_UPDATE_ABORTED]="RBK0189I: Mise à niveau de version annulée."
MSG_UPDATE_TO_VERSION=190
MSG_EN[$MSG_UPDATE_TO_VERSION]="RBK0190I: Upgrading $MYSELF from version %s to %s."
MSG_DE[$MSG_UPDATE_TO_VERSION]="RBK0190I: Es wird $MYSELF von Version %s auf Version %s upgraded."
MSG_FI[$MSG_UPDATE_TO_VERSION]="RBK0190I: Päivitetään $MYSELF versiosta %s versioon %s."
MSG_FR[$MSG_UPDATE_TO_VERSION]="RBK0190I: Mise à niveau de $MYSELF de la version %s à la version %s."
MSG_ADJUSTING_DISABLED=191
MSG_EN[$MSG_ADJUSTING_DISABLED]="RBK0191E: Target %s with %s is smaller than backup source with %s. root partition resizing is disabled."
MSG_DE[$MSG_ADJUSTING_DISABLED]="RBK0191E: Ziel %s mit %s ist kleiner als die Backupquelle mit %s. Verkleinern der root Partition ist ausgeschaltet."
MSG_FI[$MSG_ADJUSTING_DISABLED]="RBK0191E: Kohde %s kooltaan %s on pienempi kuin varmuuskopion lähde kooltaan %s. Juuriosion pienentäminen on pois käytöstä."
MSG_FR[$MSG_ADJUSTING_DISABLED]="RBK0191E: La cible %s avec %s est plus petite que la source sauvegardée avec %s. La réduction de la partition Root est désactivée."
MSG_INTRO_DEV_MESSAGE=192
MSG_EN[$MSG_INTRO_DEV_MESSAGE]="RBK0192W: =========> NOTE  <========= \
${NL}!!! RBK0192W: This is a development version and should not be used in production. \
${NL}!!! RBK0192W: =========> NOTE <========="
MSG_DE[$MSG_INTRO_DEV_MESSAGE]="RBK0192W: =========> HINWEIS <========= \
${NL}!!! RBK0192W: Dieses ist eine Entwicklerversion welcher nicht in Produktion benutzt werden sollte. \
${NL}!!! RBK0192W: =========> HINWEIS <========="
MSG_FI[$MSG_INTRO_DEV_MESSAGE]="RBK0192W: =========> HUOM  <========= \
${NL}!!! RBK0192W: Tämä on kehitysversio, jota ei tule käyttää tuotannossa. \
${NL}!!! RBK0192W: =========> HUOM <========="
MSG_FR[$MSG_INTRO_DEV_MESSAGE]="RBK0192W: =========> MESSAGE  <========= \
${NL}!!! RBK0192W: Il s'agit d'une version de développement qui ne doit pas être utilisée en production. \
${NL}!!! RBK0192W: =========> MESSAGE <========="
MSG_MISSING_COMMANDS=193
MSG_EN[$MSG_MISSING_COMMANDS]="RBK0193E: Missing required commands '%s'."
MSG_DE[$MSG_MISSING_COMMANDS]="RBK0193E: Erforderliche Befehle '%s' nicht vorhanden."
MSG_FI[$MSG_MISSING_COMMANDS]="RBK0193E: Vaadittavia komentoja puuttuu '%s'."
MSG_FR[$MSG_MISSING_COMMANDS]="RBK0193E: Commandes requises '%s' absentes."
MSG_MISSING_PACKAGES=194
MSG_EN[$MSG_MISSING_PACKAGES]="RBK0194E: Missing required packages. Install them with 'sudo apt-get install %s'."
MSG_DE[$MSG_MISSING_PACKAGES]="RBK0194E: Erforderliche Pakete nicht installiert. Installiere sie mit 'sudo apt-get install %s'"
MSG_FI[$MSG_MISSING_PACKAGES]="RBK0194E: Vaadittavia paketteja puuttuu. Asenna ne suorittamalla 'sudo apt-get install %s'."
MSG_FR[$MSG_MISSING_PACKAGES]="RBK0194E: Package requis non installés. Installez-le avec 'sudo apt-get install %s'."
MSG_FORCE_UPDATE=195
MSG_EN[$MSG_FORCE_UPDATE]="RBK0195I: Update $MYSELF to version %s."
MSG_DE[$MSG_FORCE_UPDATE]="RBK0195I: $MYSELF auf %s aktualisieren."
MSG_FI[$MSG_FORCE_UPDATE]="RBK0195I: Päivitä $MYSELF versioon %s."
MSG_FR[$MSG_FORCE_UPDATE]="RBK0195I: Mettez à jour $MYSELF vers la version %s."
#MSG_NO_HARDLINKS_USED=196
#MSG_EN[$MSG_NO_HARDLINKS_USED]="RBK0196W: No hardlinks supported on %s."
#MSG_DE[$MSG_NO_HARDLINKS_USED]="RBK0196W: %s unterstützt keine Hardlinks."
#MSG_FI[$MSG_NO_HARDLINKS_USED]="RBK0196W: Hardlink-tietoja ei tueta kohteella %s."
#MSG_FR[$MSG_NO_HARDLINKS_USED]="RBK0196W: Aucun lien physique pris en charge sur %s."
MSG_EMAIL_SEND_FAILED=197
MSG_EN[$MSG_EMAIL_SEND_FAILED]="RBK0197W: eMail send command %s failed with RC %s."
MSG_DE[$MSG_EMAIL_SEND_FAILED]="RBK0197W: eMail mit %s versenden endet fehlerhaft mit RC %s."
MSG_FI[$MSG_EMAIL_SEND_FAILED]="RBK0197W: Sähköpostin lähettäminen komennolla %s epäonnistui, RC %s."
MSG_FR[$MSG_EMAIL_SEND_FAILED]="RBK0197W: L'envoi d'un e-mail avec %s a échoué ,code erreur %s."
MSG_BEFORE_START_SERVICES_FAILED=198
MSG_EN[$MSG_BEFORE_START_SERVICES_FAILED]="RBK0198E: Pre backup commands failed with %s."
MSG_DE[$MSG_BEFORE_START_SERVICES_FAILED]="RBK0198E: Fehler in vor dem Backup ausgeführten Befehlen %s."
MSG_FI[$MSG_BEFORE_START_SERVICES_FAILED]="RBK0198E: Varmuuskopiota edeltävät komennot epäonnistuivat, RC %s."
MSG_FR[$MSG_BEFORE_START_SERVICES_FAILED]="RBK0198E: Les commandes de pré-sauvegarde ont échoué ,Code erreur %s."
MSG_MISSING_RESTOREDEVICE_OPTION=199
MSG_EN[$MSG_MISSING_RESTOREDEVICE_OPTION]="RBK0199E: Option -R requires also option -d."
MSG_DE[$MSG_MISSING_RESTOREDEVICE_OPTION]="RBK0199E: Option -r benötigt auch Option -d."
MSG_FI[$MSG_MISSING_RESTOREDEVICE_OPTION]="RBK0199E: Valinta -R vaatii myös valinnan -d"
MSG_FR[$MSG_MISSING_RESTOREDEVICE_OPTION]="RBK0199E: L'option -r requiert également l'option -d"
MSG_SHARED_BOOT_DEVICE=200
MSG_EN[$MSG_SHARED_BOOT_DEVICE]="RBK0200I: /boot and / located on same partition %s."
MSG_DE[$MSG_SHARED_BOOT_DEVICE]="RBK0200I: /boot und / befinden sich auf derselben Partition %s."
MSG_FI[$MSG_SHARED_BOOT_DEVICE]="RBK0200I: /boot ja / ovat samalla osiolla %s."
MSG_FR[$MSG_SHARED_BOOT_DEVICE]="RBK0200I: /boot et / sont sur la même partition %s."
MSG_BEFORE_STOP_SERVICES_FAILED=201
MSG_EN[$MSG_BEFORE_STOP_SERVICES_FAILED]="RBK0201E: Post backup commands failed with %s."
MSG_DE[$MSG_BEFORE_STOP_SERVICES_FAILED]="RBK0201E: Fehler in nach dem Backup ausgeführten Befehlen %s."
MSG_FI[$MSG_BEFORE_STOP_SERVICES_FAILED]="RBK0201E: Varmuuskopion jälkeiset komennot epäonnistuivat, RC %s."
MSG_FR[$MSG_BEFORE_STOP_SERVICES_FAILED]="RBK0201E: Echec des commandes après la sauvegarde, code erreur %s."
MSG_RESTORETEST_REQUIRED=202
MSG_EN[$MSG_RESTORETEST_REQUIRED]="RBK0202W: $SMILEY_RESTORETEST_REQUIRED Friendly reminder: Execute now a restore test. You will be reminded %s times again."
MSG_DE[$MSG_RESTORETEST_REQUIRED]="RBK0201W: $SMILEY_RESTORETEST_REQUIRED Freundlicher Hinweis: Führe einen Restoretest durch. Du wirst noch %s mal erinnert werden."
MSG_FI[$MSG_RESTORETEST_REQUIRED]="RBK0202W: $SMILEY_RESTORETEST_REQUIRED Ystävällinen muistutus: Suorita palautustestaus nyt. Sinua muistutetaan vielä %s kertaa."
MSG_FR[$MSG_RESTORETEST_REQUIRED]="RBK0202W: $SMILEY_RESTORETEST_REQUIRED Rappel amical: effectuez un test de restauration. Vous serez à nouveau rappelé %s fois."
MSG_NO_BOOT_DEVICE_DISOVERED=203
MSG_EN[$MSG_NO_BOOT_DEVICE_DISOVERED]="RBK0203E: Unable to discover boot device. Please report this issue with a debug log created with option '-l debug'."
MSG_DE[$MSG_NO_BOOT_DEVICE_DISOVERED]="RBK0203E: Boot device kann nicht erkannt werden. Bitte das Problem mit einem Debuglog welches mit Option '-l debug' erstellt wird berichten."
MSG_FI[$MSG_NO_BOOT_DEVICE_DISOVERED]="RBK0203E: Käynnistyslaitetta ei löydetty. Ole hyvä ja raportoi ongelmasta valinnalla '-l debug' luodun vianmäärityslokin kanssa."
MSG_FR[$MSG_NO_BOOT_DEVICE_DISOVERED]="RBK0203E: Le périphérique de boot n'est pas reconnu. Veuillez signaler le problème avec un journal de débogage créé avec l'option '-l debug'."
MSG_TRUNCATING_ERROR=204
MSG_EN[$MSG_TRUNCATING_ERROR]="RBK0204E: Unable to calculate truncation backup size."
MSG_DE[$MSG_TRUNCATING_ERROR]="RBK0204E: Verkleinerte Backupgröße kann nicht berechnet werden."
MSG_FI[$MSG_TRUNCATING_ERROR]="RBK0204E: Typistetyn varmuuskopion kokoa ei voitu laskea."
MSG_FR[$MSG_TRUNCATING_ERROR]="RBK0204E: Impossible de calculer la taille réduite de la sauvegarde."
MSG_CLEANUP_BACKUP_VERSION=205
MSG_EN[$MSG_CLEANUP_BACKUP_VERSION]="RBK0205I: Deleting oldest backup in %s. This may take some time. Please be patient."
MSG_DE[$MSG_CLEANUP_BACKUP_VERSION]="RBK0205I: Älteste Backup %s in wird gelöscht. Das kann etwas dauern. Bitte Geduld."
MSG_FI[$MSG_CLEANUP_BACKUP_VERSION]="RBK0205I: Poistetaan vanhin varmuuskopio hakemistosta %s. Tämä saattaa kestää jonkin aikaa. Ole hyvä ja odota."
MSG_FR[$MSG_CLEANUP_BACKUP_VERSION]="RBK0205I: Suppression de la sauvegarde la plus ancienne dans %s. Cela peut prendre du temps. SVP soyez patient."
MSG_CREATING_UUID=206
MSG_EN[$MSG_CREATING_UUID]="RBK0206I: Creating new %s %s on %s."
MSG_DE[$MSG_CREATING_UUID]="RBK0206I: Erzeuge neue %s %s auf %s."
MSG_FI[$MSG_CREATING_UUID]="RBK0206I: Luodaan uusi %s %s kohteelle %s"
MSG_FR[$MSG_CREATING_UUID]="RBK0206I: Création nouvelle %s %s pour %s"
MSG_MISSING_PARTITION=207
MSG_EN[$MSG_MISSING_PARTITION]="RBK0207E: Missing partitions on %s."
MSG_DE[$MSG_MISSING_PARTITION]="RBK0207E: Keine Partitionen auf %s gefunden."
MSG_FI[$MSG_MISSING_PARTITION]="RBK0207E: Osioita puuttuu laitteelta %s."
MSG_FR[$MSG_MISSING_PARTITION]="RBK0207E: Aucune partition trouvée sur %s."
MSG_NO_UUID_SYNCHRONIZED=208
MSG_EN[$MSG_NO_UUID_SYNCHRONIZED]="RBK0208W: No UUID updated in %s for %s. Backup may not boot correctly."
MSG_DE[$MSG_NO_UUID_SYNCHRONIZED]="RBK0208W: Es konnte keine UUID in %s für %s erneuert werden. Das Backup könnte nicht starten."
MSG_FI[$MSG_NO_UUID_SYNCHRONIZED]="RBK0208W: %s ei päivittänyt UUID-tunnusta kohteelle %s. Varmuuskopio ei välttämättä käynnisty oikein."
MSG_FR[$MSG_NO_UUID_SYNCHRONIZED]="RBK0208W: Un UUID dans %s pour %s n'a pas pu être renouvelé. La sauvegarde n'a pas pu démarrer."
#MSG_UUIDS_NOT_UNIQUE=209
#MSG_EN[$MSG_UUIDS_NOT_UNIQUE]="RBK0209W: UUIDs are not unique on devices and/or partitions and may cause issues. In case of error messages check them with 'sudo blkid' and make them unique."
#MSG_DE[$MSG_UUIDS_NOT_UNIQUE]="RBK0209W: UUIDs sind nicht eindeutig auf den Geräten und/oder Partitionen und kann Probleme bereiten. Falls Fehlermeldungen auftreten sollten sie mit 'sudo blkid' überprüft und dann eindeutig gemacht werden."
#MSG_FI[$MSG_UUIDS_NOT_UNIQUE]="RBK0209W: UUID:t eivot ole uniikkeja laittella ja/tai osioilla ja saattavat aiheuttaa ongelmia. Virheiden ilmaantuessa tarkista ne komennolla 'sudo blkid' ja muuta ne yksilöllisiksi."
#MSG_FR[$MSG_UUIDS_NOT_UNIQUE]="RBK0209W: Les UUID ne sont pas uniques sur les appareils et/ou les partitions et peuvent causer des problèmes. Lors de messages d'erreurs vérifiez les UUID avec 'sudo blkid' et rendez-les uniques."
MSG_MULTIPLE_PARTITIONS_FOUND_BUT_2_PARTITIONS_SAVED_ONLY=210
MSG_EN[$MSG_MULTIPLE_PARTITIONS_FOUND_BUT_2_PARTITIONS_SAVED_ONLY]="RBK0210W: More than two partitions detected. Only first two partitions are saved."
MSG_DE[$MSG_MULTIPLE_PARTITIONS_FOUND_BUT_2_PARTITIONS_SAVED_ONLY]="RBK0210W: Es existieren mehr als zwei Partitionen. Nur die ersten beiden Partitionen werden gesichert."
MSG_FI[$MSG_MULTIPLE_PARTITIONS_FOUND_BUT_2_PARTITIONS_SAVED_ONLY]="RBK0210W: Havaittu enemmän kuin kaksi osiota. Vain kaksi ensimmäistä osiota tallennetaan."
MSG_FR[$MSG_MULTIPLE_PARTITIONS_FOUND_BUT_2_PARTITIONS_SAVED_ONLY]="RBK0210W: Il y a plus de deux partitions. Seules les deux premières partitions sont sauvegardées."
MSG_EXTERNAL_PARTITION_NOT_SAVED=211
MSG_EN[$MSG_EXTERNAL_PARTITION_NOT_SAVED]="RBK0211E: External partition %s mounted on %s will not be saved with option -P."
MSG_DE[$MSG_EXTERNAL_PARTITION_NOT_SAVED]="RBK0211E: Externe Partition %s die an %s gemounted ist wird mit Option -P nicht gesichert."
MSG_FI[$MSG_EXTERNAL_PARTITION_NOT_SAVED]="RBK0211E: Ulkoinsta osiota %s, joka on otettu käyttöön kohteessa %s, ei tallenneta valinnalla -P."
MSG_FR[$MSG_EXTERNAL_PARTITION_NOT_SAVED]="RBK0211E:La partition externe %s montée sur %s n'est pas sauvegardée avec l'option -P."
MSG_BACKUP_WARNING=212
MSG_EN[$MSG_BACKUP_WARNING]="RBK0212W: Backup finished with warnings. Check previous warning messages for details."
MSG_DE[$MSG_BACKUP_WARNING]="RBK0212W: Backup endete mit Warnungen. Siehe vorhergehende Warnmeldungen."
MSG_FI[$MSG_BACKUP_WARNING]="RBK0212W: Varmuuskopiointi valmistui sisältäen varoituksia. Katso lisätiedot edellisistä varoitusviesteistä."
MSG_FR[$MSG_BACKUP_WARNING]="RBK0212W: La sauvegarde s'est terminée avec des avertissements. Consultez ces messages pour plus de détails."
MSG_MOUNT_CHECK_ERROR=213
MSG_EN[$MSG_MOUNT_CHECK_ERROR]="RBK0213E: Mount %s to %s failed. RC %s."
MSG_DE[$MSG_MOUNT_CHECK_ERROR]="RBK0213E: Mount von %s an %s ist fehlerhaft."
MSG_FI[$MSG_MOUNT_CHECK_ERROR]="RBK0213E: Kohteen %s käyttöönotto kohteeseen %s epäonnistui. RC %s."
MSG_FR[$MSG_MOUNT_CHECK_ERROR]="RBK0213E: Échec du montage de %s sur %s. Code d'erreur %s."
#MSG_MISSING_SMART_RECYCLE_PARMS=214
#MSG_EN[$MSG_MISSING_SMART_RECYCLE_PARMS]="RBK0214E: Missing smart recycle parms in %s. Have to be four:Daily Weekly Monthly Yearly."
#MSG_DE[$MSG_MISSING_SMART_RECYCLE_PARMS]="RBK0214E: Missing smart recycle parms in %s. Es müssen vier sein: Täglich Wöchentlich Monatlich Jährlich"
#MSG_FI[$MSG_MISSING_SMART_RECYCLE_PARMS]="RBK0214E: Älykkään varmuuskopion parametrejä puuttuu parametreistä %s. Niitä tulee olla neljä: Päivittäinen Viikoittainen Kuukausittainen Vuosittainen."
#MSG_FR[$MSG_MISSING_SMART_RECYCLE_PARMS]="RBK0214E: Paramètres du cycle de statégie des sauvegardes manquants en %s. Il doit y en avoir quatre : Quotidien Hebdomadaire Mensuel Annuel."
MSG_SMART_RECYCLE_PARM_INVALID=215
MSG_EN[$MSG_SMART_RECYCLE_PARM_INVALID]="RBK0215E: Invalid smart recycle parameter %s in option '%s'."
MSG_DE[$MSG_SMART_RECYCLE_PARM_INVALID]="RBK0215E: Ungültiger smart recycle Parameter %s in Option '%s'."
MSG_FI[$MSG_SMART_RECYCLE_PARM_INVALID]="RBK0215E: Virheellinen älykkään varmuuskopion parametri %s valinnassa '%s'."
MSG_FR[$MSG_SMART_RECYCLE_PARM_INVALID]="RBK0215E: Paramètre du cycle intelligent des sauvegardes %s non valide dans l'option '%s'. "
MSG_APPLYING_BACKUP_STRATEGY_ONLY=216
MSG_EN[$MSG_APPLYING_BACKUP_STRATEGY_ONLY]="RBK0216W: Applying backup strategy in %s only."
MSG_DE[$MSG_APPLYING_BACKUP_STRATEGY_ONLY]="RBK0216W: Wende nur Backupstrategie in %s an."
MSG_FI[$MSG_APPLYING_BACKUP_STRATEGY_ONLY]="RBK0216W: Sovelletaan varmuuskopiointistrategiaa vain kohteeseen %s."
MSG_FR[$MSG_APPLYING_BACKUP_STRATEGY_ONLY]="RBK0216W: Utilisez uniquement la stratégie de sauvegarde en %s."
MSG_SMART_RECYCLE_FILES=217
MSG_EN[$MSG_SMART_RECYCLE_FILES]="RBK0217I: %s backups will be smart recycled. %s backups will be kept. Please be patient."
MSG_DE[$MSG_SMART_RECYCLE_FILES]="RBK0217I: %s Backups werden smart recycled. %s Backups werden aufgehoben. Bitte Geduld."
MSG_FI[$MSG_SMART_RECYCLE_FILES]="RBK0217I: %s varmuuskopiota käsitellään älykkäästi. %s varmuuskopiota säilytetään. Ole hyvä ja odota."
MSG_FR[$MSG_SMART_RECYCLE_FILES]="RBK0217I: %s sauvegardes de %s sont intelligemment recyclées. %s sauvegardes seront annulées. SVP soyez patient."
MSG_SMART_APPLYING_BACKUP_STRATEGY=218
MSG_EN[$MSG_SMART_APPLYING_BACKUP_STRATEGY]="RBK0218I: Applying smart backup strategy. Daily:%s Weekly:%s Monthly:%s Yearly:%s."
MSG_DE[$MSG_SMART_APPLYING_BACKUP_STRATEGY]="RBK0218I: Wende smarte Backupstrategie an. Täglich:%s Wöchentlich:%s Monatlich:%s Jährlich:%s"
MSG_FI[$MSG_SMART_APPLYING_BACKUP_STRATEGY]="RBK0218I: Sovelletaan älykästä varmuuskopiointistrategiaa. Päivittäinen:%s Viikoittainen:%s Kuukausittainen:%s Vuosittainen:%s."
MSG_FR[$MSG_SMART_APPLYING_BACKUP_STRATEGY]="RBK0218I: Appliquez une stratégie de sauvegarde intelligente: Quotidiennement : %s Hebdomadaire : %s Mensuellement : %s Annuellement : %s"
MSG_SMART_RECYCLE_NO_FILES=219
MSG_EN[$MSG_SMART_RECYCLE_NO_FILES]="RBK0219I: No backups will be smart recycled."
MSG_DE[$MSG_SMART_RECYCLE_NO_FILES]="RBK0219I: Keine Backups werden smart recycled."
MSG_FI[$MSG_SMART_RECYCLE_NO_FILES]="RBK0219I: Ei älykkään varmuuskopiolla käsiteltäviä varmuuskopioita."
MSG_FR[$MSG_SMART_RECYCLE_NO_FILES]="RBK0219I: Aucune sauvegarde dans le cycle intelligent des sauvegardes."
MSG_SMART_RECYCLE_FILE_WOULD_BE_DELETED=220
MSG_EN[$MSG_SMART_RECYCLE_FILE_WOULD_BE_DELETED]="RBK0220W: Smart backup strategy would delete %s."
MSG_DE[$MSG_SMART_RECYCLE_FILE_WOULD_BE_DELETED]="RBK0220W: Smart Backup Strategie würde %s Backup löschen."
MSG_FI[$MSG_SMART_RECYCLE_FILE_WOULD_BE_DELETED]="RBK0220W: Älykäs varmuuskopiointistrategia poistaisi kohteen %s."
MSG_FR[$MSG_SMART_RECYCLE_FILE_WOULD_BE_DELETED]="RBK0220W: La stratégie de sauvegarde intelligente supprimerait %s."
MSG_SMART_RECYCLE_FILE_DELETE=221
MSG_EN[$MSG_SMART_RECYCLE_FILE_DELETE]="RBK0221I: Smart backup strategy deletes %s."
MSG_DE[$MSG_SMART_RECYCLE_FILE_DELETE]="RBK0220I: Smart Backup Strategie löscht Backup %s."
MSG_FI[$MSG_SMART_RECYCLE_FILE_DELETE]="RBK0221I: Älykäs varmuuskopiointistrategia poistaa kohteen %s."
MSG_FR[$MSG_SMART_RECYCLE_FILE_DELETE]="RBK0221I: La stratégie de sauvegarde intelligente supprime %s."
MSG_SMART_RECYCLE_FILE_WOULD_BE_KEPT=222
MSG_EN[$MSG_SMART_RECYCLE_FILE_WOULD_BE_KEPT]="RBK0222W: Smart backup strategy would keep %s."
MSG_DE[$MSG_SMART_RECYCLE_FILE_WOULD_BE_KEPT]="RBK0222W: Smart Backup Strategie würde %s Backup behalten."
MSG_FI[$MSG_SMART_RECYCLE_FILE_WOULD_BE_KEPT]="RBK0222W: Älykäs varmuuskopiointistrategia pitäisi kohteen %s."
MSG_FR[$MSG_SMART_RECYCLE_FILE_WOULD_BE_KEPT]="RBK0222W: La stratégie de sauvegarde intelligente conserverait %s."
MSG_UMOUNT_CHECK_ERROR=223
MSG_EN[$MSG_UMOUNT_CHECK_ERROR]="RBK0223E: Umount %s to %s failed. RC %s."
MSG_DE[$MSG_UMOUNT_CHECK_ERROR]="RBK0223E: Umount von %s an %s ist fehlerhaft."
MSG_FI[$MSG_UMOUNT_CHECK_ERROR]="RBK0223E: %s käytöstä poisto %s (umount) epäonnistui. RC %s. "
MSG_FR[$MSG_UMOUNT_CHECK_ERROR]="RBK0223E: Échec du démontage de %s sur %s , Code Erreur %s."
MSG_FILE_CONTAINS_SPACES=224
MSG_EN[$MSG_FILE_CONTAINS_SPACES]="RBK0224E: Spaces are not allowed in \"%s\"."
MSG_DE[$MSG_FILE_CONTAINS_SPACES]="RBK0224E: Leerzeichen sind nicht in \"%s\" erlaubt."
MSG_FI[$MSG_FILE_CONTAINS_SPACES]="RBK0224E: Välilyönnit eivät ole sallittuja nimessä \"%s\"."
MSG_FR[$MSG_FILE_CONTAINS_SPACES]="RBK0224E: Les espaces ne sont pas autorisés dans \"%s\"."
MSG_UNABLE_TO_CREATE_FILE=225
MSG_EN[$MSG_UNABLE_TO_CREATE_FILE]="RBK0225E: Unable to create file %s."
MSG_DE[$MSG_UNABLE_TO_CREATE_FILE]="RBK0225E: Datei %s kann nicht erstellt werden."
MSG_FI[$MSG_UNABLE_TO_CREATE_FILE]="RBK0225E: Tiedoston %s luonti epäonnistui"
MSG_FR[$MSG_UNABLE_TO_CREATE_FILE]="RBK0225E: Impossible de créer le fichier %s."
#MSG_CONFIG_VERSION_DOES_NOT_MATCH=226
#MSG_EN[$MSG_CONFIG_VERSION_DOES_NOT_MATCH]="RBK0226W: Found unexpected config version %s in %s. Expected version %s."
#MSG_DE[$MSG_CONFIG_VERSION_DOES_NOT_MATCH]="RBK0226W: Unerwartete Konfigurationsversion %s in %s gefunden. %s wird erwartet."
#MSG_FI[$MSG_CONFIG_VERSION_DOES_NOT_MATCH]="RBK0226W: Odottamaton asetustiedoston versio %s löytyi kohteessa %s. Oletettiin versiota %s."
#MSG_FR[$MSG_CONFIG_VERSION_DOES_NOT_MATCH]="RBK0226W: Version de configuration inattendue %s trouvée dans %s. Version attendue %s."
MSG_TITLE_STARTED=227
MSG_EN[$MSG_TITLE_STARTED]="%s: Backup started."
MSG_DE[$MSG_TITLE_STARTED]="%s: Backup gestarted."
MSG_FI[$MSG_TITLE_STARTED]="%s: Varmuuskopiointi aloitettu."
MSG_FR[$MSG_TITLE_STARTED]="%s: Sauvegarde démarrée."
MSG_TELEGRAM_SEND_FAILED=228
MSG_EN[$MSG_TELEGRAM_SEND_FAILED]="RBK0228W: Sent to telegram failed. curl RC: %s - HTTP CODE: %s - Error description: %s."
MSG_DE[$MSG_TELEGRAM_SEND_FAILED]="RBK0228W: Senden an Telegram fehlerhaft. curl RC: %s - HTTP CODE: %s - Fehlerbeschreibung: %s."
MSG_FI[$MSG_TELEGRAM_SEND_FAILED]="RBK0228W: Yhteys Telegramiin epäonnistui. curl RC: %s - HTTP-koodi: %s - Virheen kuvaus: %s."
MSG_FR[$MSG_TELEGRAM_SEND_FAILED]="RBK0228W: Échec de l'envoi à Telegram. erreur curl: %s - CODE HTTP : %s - Description de l'erreur : %s."
MSG_TELEGRAM_SEND_OK=229
MSG_EN[$MSG_TELEGRAM_SEND_OK]="RBK0229I: Telegram notified."
MSG_DE[$MSG_TELEGRAM_SEND_OK]="RBK0229I: Telegram benachrichtigt."
MSG_FI[$MSG_TELEGRAM_SEND_OK]="RBK0229I: Telegram-ilmoitus lähetetty."
MSG_FR[$MSG_TELEGRAM_SEND_OK]="RBK0229I: Telegram notifié."
MSG_TELEGRAM_OPTIONS_INCOMPLETE=230
MSG_EN[$MSG_TELEGRAM_OPTIONS_INCOMPLETE]="RBK0230E: Telegram options not complete."
MSG_DE[$MSG_TELEGRAM_OPTIONS_INCOMPLETE]="RBK0230E: Telegramoptionen nicht vollständig"
MSG_FI[$MSG_TELEGRAM_OPTIONS_INCOMPLETE]="RBK0230E: Telegramin asetukset ovat puutteellliset."
MSG_FR[$MSG_TELEGRAM_OPTIONS_INCOMPLETE]="RBK0230E: Options de Telegram incomplètes."
MSG_TELEGRAM_SEND_LOG_FAILED=231
MSG_EN[$MSG_TELEGRAM_SEND_LOG_FAILED]="RBK0231W: Unable to send messages to Telegram. curl RC: %s."
MSG_DE[$MSG_TELEGRAM_SEND_LOG_FAILED]="RBK0231W: Meldungen an Telegram konnten nicht gesendet werden. curl RC: %s."
MSG_FI[$MSG_TELEGRAM_SEND_LOG_FAILED]="RBK0231W: Viestien lähettäminen Telegramiin ei onnistunut. curl RC: %s."
MSG_FR[$MSG_TELEGRAM_SEND_LOG_FAILED]="RBK0231W: Impossible d'envoyer des messages à Telegram. Erreur curl: %s."
MSG_TELEGRAM_SEND_LOG_OK=232
MSG_EN[$MSG_TELEGRAM_SEND_LOG_OK]="RBK0232I: Messages sent to Telegram."
MSG_DE[$MSG_TELEGRAM_SEND_LOG_OK]="RBK0232I: Meldungen an Telegram gesendet."
MSG_FI[$MSG_TELEGRAM_SEND_LOG_OK]="RBK0232I: Viestit lähetetty Telegramiin."
MSG_FR[$MSG_TELEGRAM_SEND_LOG_OK]="RBK0232I: Messages envoyés à Telegram."
MSG_TELEGRAM_INVALID_NOTIFICATION=233
MSG_EN[$MSG_TELEGRAM_INVALID_NOTIFICATION]="RBK0233E: Invalid Telegram notification %s detected. Valid notifications are %s."
MSG_DE[$MSG_TELEGRAM_INVALID_NOTIFICATION]="RBK0233E: Ungültige Telegram Notification %s eingegeben. Mögliche Notifikationen sind %s."
MSG_FI[$MSG_TELEGRAM_INVALID_NOTIFICATION]="RBK0233E: Epäkelpo Telegram-ilmoitus %s havaittu. Kelvollisia ilmoituksia ovat %s."
MSG_FR[$MSG_TELEGRAM_INVALID_NOTIFICATION]="RBK0233E: Notification de Telegram non valide %s . Les notifications valides sont %s."
MSG_INVALID_COLORING_OPTION=234
MSG_EN[$MSG_INVALID_COLORING_OPTION]="RBK0234E: Invalid coloring option %s detected."
MSG_DE[$MSG_INVALID_COLORING_OPTION]="RBK0234E: Ungültige Färbungsoption %s entdeckt."
MSG_FI[$MSG_INVALID_COLORING_OPTION]="RBK0234E: Epäkelpo väriasetus %s havaittu."
MSG_FR[$MSG_INVALID_COLORING_OPTION]="RBK0234E: Option de coloration non valide %s détectée."
MSG_INVALID_TRUE_FALSE_OPTION=235
MSG_EN[$MSG_INVALID_TRUE_FALSE_OPTION]="RBK0235E: Invalid true/false option %s for %s detected. Should be on, off, 0 or 1."
MSG_DE[$MSG_INVALID_TRUE_FALSE_OPTION]="RBK0235E: Ungültige an/aus Option %s für %s entdeckt. Es sollte an, aus, 0 oder 1 sein."
MSG_FI[$MSG_INVALID_TRUE_FALSE_OPTION]="RBK0235E: Virheellinen päälle/pois-valinta %s havaittu kohteelle %s. Valinnan tulee olla on, off, 0 tai 1."  #on and off are OK for finnish language
MSG_FR[$MSG_INVALID_TRUE_FALSE_OPTION]="RBK0235E: Option on/off non valide %s détectée pour %s. Il doit être activé, désactivé, 0 ou 1."
#MSG_PARTITION_MODE_NO_LONGER_SUPPORTED=236
#MSG_EN[$MSG_PARTITION_MODE_NO_LONGER_SUPPORTED]="RBK0236W: Partition oriented backup will not be maintained any more and disable somewhere in the future."
#MSG_DE[$MSG_PARTITION_MODE_NO_LONGER_SUPPORTED]="RBK0236W: Partitionsorientierter Modus wird nicht mehr weiter gewartet und irgendwann in Zukunft nicht mehr verfügbar sein."
#MSG_FI[$MSG_PARTITION_MODE_NO_LONGER_SUPPORTED]="RBK0236W: Osio-orientoitua varmuuskopiota ei enää tueta ja poistetaan kokonaan käytöstä tulevaisuudessa."
#MSG_FR[$MSG_PARTITION_MODE_NO_LONGER_SUPPORTED]="RBK0236W: La sauvegarde orientée partition ne sera plus maintenue et sera désactivée quelque part dans le futur."."
MSG_UPDATE_TO_LATEST_BETA=237
MSG_EN[$MSG_UPDATE_TO_LATEST_BETA]="RBK0237I: Upgrading current version %s to latest version."
MSG_DE[$MSG_UPDATE_TO_LATEST_BETA]="RBK0237I: Die momentane Version %s auf die aktuellste Version upgraden."
MSG_FI[$MSG_UPDATE_TO_LATEST_BETA]="RBK0237I: Päivitetään nykyinen versio %s viimeisimpään versioon."
MSG_FR[$MSG_UPDATE_TO_LATEST_BETA]="RBK0237I: Mise à niveau de la version actuelle %s vers la dernière version."
#MSG_JUST_TEXT=238
#MSG_EN[$MSG_JUST_TEXT]="%s"
#MSG_DE[$MSG_JUST_TEXT]="%s"
#MSG_FI[$MSG_JUST_TEXT]="%s"
#MSG_FR[$MSG_JUST_TEXT]="%s"
MSG_DOWNLOAD_FAILED=239
MSG_EN[$MSG_DOWNLOAD_FAILED]="RBK0239E: Download of %s failed. HTTP code: %s. RC: %s"
MSG_DE[$MSG_DOWNLOAD_FAILED]="RBK0239E: %s kann nicht aus dem Netz geladen werden. HTTP code: %s. RC: %s"
MSG_FI[$MSG_DOWNLOAD_FAILED]="RBK0239E: Kohteen %s lataus epäonnistui. HTTP-koodi: %s. RC: %s"
MSG_FR[$MSG_DOWNLOAD_FAILED]="RBK0239E: Le téléchargement de %s a échoué. Code HTTP : %s. RC:%s"
MSG_SAVING_CURRENT_CONFIGURATION=240
MSG_EN[$MSG_SAVING_CURRENT_CONFIGURATION]="RBK0240I: Saving current configuration %s to %s."
MSG_DE[$MSG_SAVING_CURRENT_CONFIGURATION]="RBK0240I: Aktuelle Konfiguration %s wird in %s gesichert."
MSG_FI[$MSG_SAVING_CURRENT_CONFIGURATION]="RBK0240I: Tallennetaan nykyiset asetukset %s kohteeseen %s."
MSG_FR[$MSG_SAVING_CURRENT_CONFIGURATION]="RBK0240I: Enregistrement de la configuration actuelle %s dans %s."
MSG_MERGING_VERSION=241
MSG_EN[$MSG_MERGING_VERSION]="RBK0241I: Merging current configuration %s with new configuration %s into %s."
MSG_DE[$MSG_MERGING_VERSION]="RBK0241I: Aktuelle Konfiguration %s wird mit der neuen Konfiguration %s in %s zusammengefügt."
MSG_FI[$MSG_MERGING_VERSION]="RBK0241I: Yhdistetään nykyiset asetukset %s uusiin asetuksiin %s kohteeksi %s."
MSG_FR[$MSG_MERGING_VERSION]="RBK0241I: La configuration actuelle %s sera fusionnée avec la nouvelle configuration %s dans %s."
MSG_MERGE_SUCCESSFULL=242
MSG_EN[$MSG_MERGE_SUCCESSFULL]="RBK0243I: Configuration merge finished successfully but not activated."
MSG_DE[$MSG_MERGE_SUCCESSFULL]="RBK0243I: Konfigurationszusammenfügung wurde erfolgreich beendet aber nicht aktiviert."
MSG_FI[$MSG_MERGE_SUCCESSFULL]="RBK0243I: Asetukset yhdistetty onnistuneesti, mutta niitä ei ole aktivoitu."
MSG_FR[$MSG_MERGE_SUCCESSFULL]="RBK0243I: La fusion de la configuration s'est terminée avec succès mais n'a pas été activée."
MSG_COPIED_FILE=243
MSG_EN[$MSG_COPIED_FILE]="RBK0244I: Merged configuration %s copied to %s and activated."
MSG_DE[$MSG_COPIED_FILE]="RBK0244I: Zusammengefügte Konfiguration %s nach %s kopiert und aktiviert."
MSG_FI[$MSG_COPIED_FILE]="RBK0244I: Yhdistetyt asetukset %s kopioitiin kohteeseen %s ja ne aktivoitiin."
MSG_FR[$MSG_COPIED_FILE]="RBK0244I: Configuration fusionnée %s copiée dans %s et activée."
MSG_UPDATE_CONFIG=244
MSG_EN[$MSG_UPDATE_CONFIG]="RBK0245W: Backup current configuration in %s and activate updated configuration? %s "
MSG_DE[$MSG_UPDATE_CONFIG]="RBK0245W: Soll die aktuelle Konfiguration in %s gesichert werden und die aktualisierte Konfiguration aktiviert werden? %s "
MSG_FI[$MSG_UPDATE_CONFIG]="RBK0245W: Varmuuskopioidaanko nykyiset asetukset kohteeseen %s ja aktivoidaan päivitetyt asetukset? %s "
MSG_FR[$MSG_UPDATE_CONFIG]="RBK0245W: Sauvegarder la configuration actuelle dans %s et activer la configuration mise à jour ? %s "
MSG_NO_CONFIGUPDATE_REQUIRED=245
MSG_EN[$MSG_NO_CONFIGUPDATE_REQUIRED]="RBK0246I: Local configuration version v%s does not require an update."
MSG_DE[$MSG_NO_CONFIGUPDATE_REQUIRED]="RBK0246I: Die lokale Konfigurationsversion v%s benötigt keine Aktualisierung."
MSG_FI[$MSG_NO_CONFIGUPDATE_REQUIRED]="RBK0246I: Paikallinen asetustiedoston versio v%s ei vaadi päivitystä."
MSG_FR[$MSG_NO_CONFIGUPDATE_REQUIRED]="RBK0246I: La version de configuration locale v%s ne nécessite pas de mise à jour."
#MSG_CONFIG_VERSIONS=246
#MSG_EN[$MSG_CONFIG_VERSIONS]="RBK0246I: Current configuration version: v%s. Required configuration version: v%s."
#MSG_DE[$MSG_CONFIG_VERSIONS]="RBK0246I: Lokale Konfigurationsversion: v%s. Erforderliche Konfigurationsversion: v%s."
#MSG_FI[$MSG_CONFIG_VERSIONS]="RBK0246I: Nykyisten asetusten versio: v%s. Vaaditaan versio v%s."
#MSG_FR[$MSG_CONFIG_VERSIONS]="RBK0246I: Version de configuration actuelle : v%s. Version de configuration requise : v%s."
MSG_ACTIVATE_CONFIG=247
MSG_EN[$MSG_ACTIVATE_CONFIG]="RBK0247I: Now review %s and copy the configuration file to %s to finish the configuration update."
MSG_DE[$MSG_ACTIVATE_CONFIG]="RBK0247I: Nun die zusammengefügte Konfigurationsdatei %s überprüfen und nach %s kopieren um den Konfigurationsupdate zu beenden."
MSG_FI[$MSG_ACTIVATE_CONFIG]="RBK0247I: Tarkista %s ja kopioi asetustiedosto kohteeseen %s viimeistelläksesi asetusten päivitykset."
MSG_FR[$MSG_ACTIVATE_CONFIG]="RBK0247I: Vérifiez maintenant le fichier de configuration fusionné %s et copiez-le dans %s pour terminer la mise à jour de la configuration."
MSG_ADDED_CONFIG_OPTION=248
MSG_EN[$MSG_ADDED_CONFIG_OPTION]="RBK0248I: Added option %s=%s."
MSG_DE[$MSG_ADDED_CONFIG_OPTION]="RBK0248I: Option %s=%s wurde zugefügt."
MSG_FI[$MSG_ADDED_CONFIG_OPTION]="RBK0248I: Lisättiin valinta %s=%s."
MSG_FR[$MSG_ADDED_CONFIG_OPTION]="RBK0248I: Ajout de l'option %s=%s."
MSG_DELETED_CONFIG_OPTION=249
MSG_EN[$MSG_DELETED_CONFIG_OPTION]="RBK0249I: Deleted option %s=%s."
MSG_DE[$MSG_DELETED_CONFIG_OPTION]="RBK0249I: Option %s=%s wurde gelöscht."
MSG_FI[$MSG_DELETED_CONFIG_OPTION]="RBK0249I: Poistettiin valinta %s=%s."
MSG_FR[$MSG_DELETED_CONFIG_OPTION]="RBK0249I: Option supprimée %s=%s."
MSG_CONFIG_BACKUP_FAILED=250
MSG_EN[$MSG_CONFIG_BACKUP_FAILED]="RBK0250E: Backup creation of %s failed."
MSG_DE[$MSG_CONFIG_BACKUP_FAILED]="RBK0250E: Backuperstellung von %s fehlerhaft."
MSG_FI[$MSG_CONFIG_BACKUP_FAILED]="RBK0250E: Varmuuskopion luonti kohteesta %s epäonnistui."
MSG_FR[$MSG_CONFIG_BACKUP_FAILED]="RBK0250E: La création de la sauvegarde de %s a échoué."
MSG_CHMOD_FAILED=251
MSG_EN[$MSG_CHMOD_FAILED]="RBK0251E: chmod of %s failed."
MSG_DE[$MSG_CHMOD_FAILED]="RBK0251E: chmod von %s nicht möglich."
MSG_FI[$MSG_CHMOD_FAILED]="RBK0251E: Kohteen %s chmod epäonnistui."
MSG_FR[$MSG_CHMOD_FAILED]="RBK0251E: chmod pour %s a échoué."
MSG_EMAIL_COLORING_NOT_SUPPORTED=252
MSG_EN[$MSG_EMAIL_COLORING_NOT_SUPPORTED]="RBK0252E: Invalid eMail coloring %s. Using $EMAIL_COLORING_SUBJECT. Supported are %s."
MSG_DE[$MSG_EMAIL_COLORING_NOT_SUPPORTED]="RBK0252E: Ungültige eMailKolorierung %s. Benutze $EMAIL_COLORING_SUBJECT. Unterstützt sind %s."
MSG_FI[$MSG_EMAIL_COLORING_NOT_SUPPORTED]="RBK0252E: Epäkelpo sähköpostin väritys %s. Käytetään $EMAIL_COLORING_SUBJECT. Tuettuja ovat %s."
MSG_FR[$MSG_EMAIL_COLORING_NOT_SUPPORTED]="RBK0252E: Coloration de l'e-mail %s non valide. Utiliser $EMAIL_COLORING_SUBJECT. %s qui est pris en charge."
MSG_SD_TOO_SMALL=253
MSG_EN[$MSG_SD_TOO_SMALL]="RBK0253E: Target device %s too small. Available bytes: %s. Required bytes: %s."
MSG_DE[$MSG_SD_TOO_SMALL]="RBK0253E: Zielgerät %s ist zu klein. Verfügbare Bytes: %s. Erforderliche Bytes: %s."
MSG_FI[$MSG_SD_TOO_SMALL]="RBK0253E: Kohdelaite %s on liian pieni. Käytetävissä %s tavua. Vaaditaan %s tavua."
MSG_FR[$MSG_SD_TOO_SMALL]="RBK0253E: Périphérique cible %s trop petit. Octets disponibles : %s. Octets requis : %s."
MSG_SENSITIVE_SEPARATOR=254
MSG_EN[$MSG_SENSITIVE_SEPARATOR]="+================================================================================================================================================+"
MSG_DE[$MSG_SENSITIVE_SEPARATOR]="+================================================================================================================================================+"
MSG_FI[$MSG_SENSITIVE_SEPARATOR]="+================================================================================================================================================+"
MSG_FR[$MSG_SENSITIVE_SEPARATOR]="+================================================================================================================================================+"
MSG_SENSITIVE_WARNING=255
MSG_EN[$MSG_SENSITIVE_WARNING]="| ===> A lot of sensitive information is masqueraded in this log file. Nevertheless please check the log carefully before you distribute it <=== |"
MSG_DE[$MSG_SENSITIVE_WARNING]="| ===>  Viele sensitive Informationen werden in dieser Logdatei maskiert. Vor dem Verteilen des Logs sollte es trotzdem ueberprueft werden  <=== |"
MSG_FI[$MSG_SENSITIVE_WARNING]="| ===>            Sensitiivisiä tietoja on piilotettu tästä lokitiedostosta. Tarkista lisäksi loki huolellisesti ennen sen jakoa            <=== |"
MSG_FR[$MSG_SENSITIVE_WARNING]="| ===>De nombreuses informations sensibles sont masquées dans ce fichier journal. Avant de distribuer le log, il faut quand même le vérifier<=== |"
MSG_RESTORE_WARNING=256
MSG_EN[$MSG_RESTORE_WARNING]="RBK0256W: Restore finished with warnings. Check previous warning messages for details."
MSG_DE[$MSG_RESTORE_WARNING]="RBK0256W: Restore endete mit Warnungen. Siehe vorhergehende Warnmeldungen."
MSG_FI[$MSG_RESTORE_WARNING]="RBK0256W: Palautus onnistui sisältäen vaoituksia. Katso lisätiedot edellisistä varoitusviesteistä."
MSG_FR[$MSG_RESTORE_WARNING]="RBK0256W: Restauration terminée avec des avertissements. Consultez les messages pour plus de détails."
MSG_DEPRECATED_OPTION=257
MSG_EN[$MSG_DEPRECATED_OPTION]="RBK0257W: Option %s is deprecated and will be removed in a future release."
MSG_DE[$MSG_DEPRECATED_OPTION]="RBK0257W: Option %s ist veraltet und wird in einer zukünftigen Release entfernt werden."
MSG_FI[$MSG_DEPRECATED_OPTION]="RBK0257W: Valintaa %s ei enää tueta ja se poistetaan kokonaan tulevissa julkaisuissa."
MSG_FR[$MSG_DEPRECATED_OPTION]="RBK0257W: L'option %s est obsolète et sera supprimée dans une prochaine version."
MSG_DYNAMIC_MOUNT_FAILED=258
MSG_EN[$MSG_DYNAMIC_MOUNT_FAILED]="RBK0258E: Dynamic mount of %s failed with rc %s."
MSG_DE[$MSG_DYNAMIC_MOUNT_FAILED]="RBK0258E: Dynamischer mount von %s bekommt Fehler %s"
MSG_FI[$MSG_DYNAMIC_MOUNT_FAILED]="RBK0258E: Kohteen %s dynaaminen käyttöönotto epäonnistui, RC %s."
MSG_FR[$MSG_DYNAMIC_MOUNT_FAILED]="RBK0258E: Le montage dynamique de %s a échoué avec le Code erreur %s."
MSG_DYNAMIC_MOUNT_OK=259
MSG_EN[$MSG_DYNAMIC_MOUNT_OK]="RBK0259I: Dynamic mount of %s successfull."
MSG_DE[$MSG_DYNAMIC_MOUNT_OK]="RBK0259I: Dynamischer mount von %s erfolgreich."
MSG_FI[$MSG_DYNAMIC_MOUNT_OK]="RBK0259I: Kohteen %s dynaaminen käyttöönotto onnistui."
MSG_FR[$MSG_DYNAMIC_MOUNT_OK]="RBK0259I: Montage dynamique de %s réussi."
MSG_DYNAMIC_UMOUNT_SCHEDULED=260
MSG_EN[$MSG_DYNAMIC_UMOUNT_SCHEDULED]="RBK0260I: Dynamic umount of %s will be executed."
MSG_DE[$MSG_DYNAMIC_UMOUNT_SCHEDULED]="RBK0260I: Dynamischer umount von %s wird vorgenommen."
MSG_FI[$MSG_DYNAMIC_UMOUNT_SCHEDULED]="RBK0260I: Suoritetaan kohteen %s dynaaminen käytöstäpoista."
MSG_FR[$MSG_DYNAMIC_UMOUNT_SCHEDULED]="RBK0260I: Le démontage dynamique de %s est exécuté."
#MSG_NO_SKIP_OR_FORCE_ALLOWED=261
#MSG_EN[$MSG_NO_SKIP_OR_FORCE_ALLOWED]="RBK0261E: Option -0 and -1 are not supported with option -P."
#MSG_DE[$MSG_NO_SKIP_OR_FORCE_ALLOWED]="RBK0261E: Option -0 und -1 sind nicht mit der Option -P unterstützt."
#MSG_FI[$MSG_NO_SKIP_OR_FORCE_ALLOWED]="RBK0261E: Valintaa -0 ja -1 ei tueta valinnan -P kanssa."
#MSG_FR[$MSG_NO_SKIP_OR_FORCE_ALLOWED]="RBK0261E: Les options -0 et -1 ne sont pas prises en charge avec l'option -P."
MSG_DYNAMIC_MOUNT_NOT_REQUIRED=262
MSG_EN[$MSG_DYNAMIC_MOUNT_NOT_REQUIRED]="RBK0262I: Dynamic mount of %s skipped because it's already mounted."
MSG_DE[$MSG_DYNAMIC_MOUNT_NOT_REQUIRED]="RBK0262I: Dynamischer mount von %s nicht ausgeführt da es schon gemounted ist."
MSG_FI[$MSG_DYNAMIC_MOUNT_NOT_REQUIRED]="RBK0262I: Kohteen %s dynaaminen käyttöönotto ohitettiin, koska kohde on jo käytössä."
MSG_FR[$MSG_DYNAMIC_MOUNT_NOT_REQUIRED]="RBK0262I: Le montage dynamique de %s a été ignoré car il est déjà monté."
MSG_NO_FILEATTRIBUTESUPPORT=263
MSG_EN[$MSG_NO_FILEATTRIBUTESUPPORT]="RBK0263E: Filesystem %s on %s does not support Linux fileattributes."
MSG_DE[$MSG_NO_FILEATTRIBUTESUPPORT]="RBK0263E: Dateisystem %s auf %s unterstützt keine Linux Dateiattribute."
MSG_FI[$MSG_NO_FILEATTRIBUTESUPPORT]="RBK0263E: Tiedostojärjestelmä %s kohteessa %s ei tue Linuxin tiedostoattribuutteja."
MSG_FR[$MSG_NO_FILEATTRIBUTESUPPORT]="RBK0263E: Le système de fichiers %s sur %s ne prend pas en charge les attributs de fichiers Linux."
MSG_ROOT_PARTITION_NOT_DIFFERENT=264
MSG_EN[$MSG_ROOT_PARTITION_NOT_DIFFERENT]="RBK0264E: Partition used with option -R cannot be located on same device %s used with option -d."
MSG_DE[$MSG_ROOT_PARTITION_NOT_DIFFERENT]="RBK0264E: Die mit Option -R genutzte Partition darf nicht auf demselben Gerät %s welches mit Option -d angegeben wurde liegen."
MSG_FI[$MSG_ROOT_PARTITION_NOT_DIFFERENT]="RBK0264E: Valinnalla -R määritelty osio ei voi sijaita samalla laitteella %s, joka on määritelty valinnalla -d."
MSG_FR[$MSG_ROOT_PARTITION_NOT_DIFFERENT]="RBK0264E: La partition utilisée avec l'option -R ne doit pas être sur le même périphérique %s que celui spécifié avec l'option-d."
MSG_DD_WARNING=265
MSG_EN[$MSG_DD_WARNING]="RBK0265W: It's not recommended to use the dd backup method. For details read $DD_WARNING_URL_EN."
MSG_DE[$MSG_DD_WARNING]="RBK0265W: dd als Backupmethode wird nicht empfohlen. Details dazu finden sich auf $DD_WARNING_URL_DE."
MSG_FI[$MSG_DD_WARNING]="RBK0265W: DD-varmuuskopiota ei suositella. Lue lisätietoja osoitteesta $DD_WARNING_URL_EN." #Defaults to EN link.
MSG_FR[$MSG_DD_WARNING]="RBK0265W: Il n'est pas recommandé d'utiliser la méthode de sauvegarde dd. Pour plus de détails, lisez $DD_WARNING_URL_EN." #Defaults to EN link.
MSG_NO_FILEATTRIBUTE_RIGHTS=266
MSG_EN[$MSG_NO_FILEATTRIBUTE_RIGHTS]="RBK0266E: Access rights missing to create fileattributes on %s (Filesystem: %s)."
MSG_DE[$MSG_NO_FILEATTRIBUTE_RIGHTS]="RBK0266E: Es fehlt die Berechtigung um Linux Dateiattribute auf %s zu erstellen (Dateisystem: %s)."
MSG_FI[$MSG_NO_FILEATTRIBUTE_RIGHTS]="RBK0266E: Käyttöoikeudet tiedostoattribuuttien luomiseen puuttuvat kohteesta %s (Tiedostojärjestelmä: %s)."
MSG_FR[$MSG_NO_FILEATTRIBUTE_RIGHTS]="RBK0266E: Droits d'accès manquants pour créer des attributs de fichier sur %s (système de fichiers : %s)."

#
# Non NLS messages
#

MSG_EXTENSION_CALLED=267
MSG_EN[$MSG_EXTENSION_CALLED]="RBK0267I: Extension %s called."
MSG_DE[$MSG_EXTENSION_CALLED]="RBK0267I: Erweiterung %s wird aufgerufen."
MSG_UNSUPPORTED_ENVIRONMENT=268
MSG_EN[$MSG_UNSUPPORTED_ENVIRONMENT]="RBK0268E: Only Raspberries running Raspberry PI OS are supported. Use option --unsupportedEnvironment to invoke $MYNAME WITHOUT ANY SUPPORT."
MSG_DE[$MSG_UNSUPPORTED_ENVIRONMENT]="RBK0268E: Es werden nur Raspberries mit Raspberry PI OS unterstützt. Mit der Option --unsupportedEnvironment kann man $MYNAME OHNE JEGLICHE UNTERSTÜTZUNG aufrufen."
MSG_UNSUPPORTED_ENVIRONMENT_CONFIRMED=269
MSG_EN[$MSG_UNSUPPORTED_ENVIRONMENT_CONFIRMED]="\
RBK0269W: @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@${NL}\
!!! RBK0268W: @@@ Unsupported environment @@@${NL}\
!!! RBK0269W: @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@${NL}"
MSG_DE[$MSG_UNSUPPORTED_ENVIRONMENT_CONFIRMED]="\
RBK0269W: @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@${NL}\
!!! RBK0268W: @@@ Nicht unterstützte Umgebung @@@${NL}\
!!! RBK0269W: @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@${NL}"
MSG_REBOOT_SYSTEM=270
MSG_EN[$MSG_REBOOT_SYSTEM]="RBK0270I: System will be rebooted at the end of the backup run."
MSG_DE[$MSG_REBOOT_SYSTEM]="RBK0270I: Das System wird am Ende des Backuplaufes neu gestartet."
MSG_SMART_RECYCLE_WILL_BE_APPLIED=271
MSG_EN[$MSG_SMART_RECYCLE_WILL_BE_APPLIED]="RBK0271I: Smart recycle strategy will be applied."
MSG_DE[$MSG_SMART_RECYCLE_WILL_BE_APPLIED]="RBK0271I: Wende smarte Backupstrategie an."
MSG_REBOOT_SYSTEM=272
MSG_EN[$MSG_REBOOT_SYSTEM]="RBK0272I: System will be rebooted at the end of the backup run."
MSG_DE[$MSG_REBOOT_SYSTEM]="RBK0272I: Das System wird am Ende des Backuplaufes neu gestartet."
MSG_INVALID_BACKUPNAMES_DETECTED=273
MSG_EN[$MSG_INVALID_BACKUPNAMES_DETECTED]="RBK0273E: %s invalid backup directorie(s) or files found in %s."
MSG_DE[$MSG_INVALID_BACKUPNAMES_DETECTED]="RBK0273E: %s ungültige Backupverzeichnis(se) oder Dateien in %s gefunden."
MSG_RESTORE_PARTITION_MOUNTED=274
MSG_EN[$MSG_RESTORE_PARTITION_MOUNTED]="RBK0274E: Restore device %s has mounted partitions. Note: Restore to the active system is not possible."
MSG_DE[$MSG_RESTORE_PARTITION_MOUNTED]="RBK0274E: Das Restoregerät %s hat gemountete Partitionen. Hinweis: Ein Restore auf das aktive System ist nicht möglich."
MSG_RESTORE_DEVICE_NOT_VALID=275
MSG_EN[$MSG_RESTORE_DEVICE_NOT_VALID]="RBK0275E: Restore device %s is no valid device."
MSG_DE[$MSG_RESTORE_DEVICE_NOT_VALID]="RBK0275E: Das Restoregerät %s ist kein gültiges Gerät."
MSG_INVALID_BOOT_DEVICE=276
MSG_EN[$MSG_INVALID_BOOT_DEVICE]="RBK0276E: Boot device %s is not supported."
MSG_DE[$MSG_INVALID_BOOT_DEVICE]="RBK0276E: Das Bootgerät %s ist nicht unterstützt."
MSG_USBMOUNT_INSTALLED=277
MSG_EN[$MSG_USBMOUNT_INSTALLED]="RBK0277E: Restore not possible when 'usbmount' is installed."
MSG_DE[$MSG_USBMOUNT_INSTALLED]="RBK0277E: Restore ist nicht möglich wenn 'usbmount' installiert ist."
MSG_BACKUP_CLEANUP_FAILED=278
MSG_EN[$MSG_BACKUP_CLEANUP_FAILED]="RBK0278E: Cleanup of backupdirectories failed. Manual deletion of the last backup directory is strongly recommended !"
MSG_DE[$MSG_BACKUP_CLEANUP_FAILED]="RBK0278E: Fehler bei den Aufräumarbeiten am Backupverzeichnis. Das letzte Backupverzeichnis sollte dringend manuell gelöscht werden !"
MSG_FINAL_COMMAND_FAILED=279
MSG_EN[$MSG_FINAL_COMMAND_FAILED]="RBK0279W: Error occured executing final command. RC %s."
MSG_DE[$MSG_FINAL_COMMAND_FAILED]="RBK0279W: Ein Fehler trat beim Ausführen der finalen Befehle auf. RC %s."
MSG_FINAL_COMMAND_EXECUTED=280
MSG_EN[$MSG_FINAL_COMMAND_EXECUTED]="RBK0280I: Executing final command: '%s'."
MSG_DE[$MSG_FINAL_COMMAND_EXECUTED]="RBK0280I: Finaler Befehl wird ausgeführt: '%s'."
MSG_UNSUPPORTED_VERSION=281
MSG_EN[$MSG_UNSUPPORTED_VERSION]="RBK0281W: Unsupported version of $MYSELF."
MSG_DE[$MSG_UNSUPPORTED_VERSION]="RBK0281W: Nicht unterstützte Version von $MYSELF."
MSG_PUSHOVER_SEND_FAILED=282
MSG_EN[$MSG_PUSHOVER_SEND_FAILED]="RBK0282W: Sent to pushover failed. curl RC: %s - HTTP CODE: %s - Error description: %s."
MSG_DE[$MSG_PUSHOVER_SEND_FAILED]="RBK0282W: Senden an Pushover fehlerhaft. curl RC: %s - HTTP CODE: %s - Fehlerbeschreibung: %s."
MSG_PUSHOVER_SEND_OK=283
MSG_EN[$MSG_PUSHOVER_SEND_OK]="RBK0283I: Pushover notified."
MSG_DE[$MSG_PUSHOVER_SEND_OK]="RBK0283I: Pushover benachrichtigt."
MSG_PUSHOVER_OPTIONS_INCOMPLETE=284
MSG_EN[$MSG_PUSHOVER_OPTIONS_INCOMPLETE]="RBK0284E: Pushover options not complete."
MSG_DE[$MSG_PUSHOVER_OPTIONS_INCOMPLETE]="RBK0284E: Pushoveroptionen nicht vollständig"
MSG_PUSHOVER_INVALID_NOTIFICATION=285
MSG_EN[$MSG_PUSHOVER_INVALID_NOTIFICATION]="RBK0285E: Invalid Pushover notification %s detected. Valid notifications are %s."
MSG_DE[$MSG_PUSHOVER_INVALID_NOTIFICATION]="RBK0285E: Ungültige Pushover Notification %s eingegeben. Mögliche Notifikationen sind %s."
MSG_SLACK_SEND_FAILED=286
MSG_EN[$MSG_SLACK_SEND_FAILED]="RBK0286W: Sent to Slack failed. curl RC: %s - HTTP CODE: %s - Error description: %s."
MSG_DE[$MSG_SLACK_SEND_FAILED]="RBK0286W: Senden an Slack fehlerhaft. curl RC: %s - HTTP CODE: %s - Fehlerbeschreibung: %s."
MSG_SLACK_SEND_OK=287
MSG_EN[$MSG_SLACK_SEND_OK]="RBK0287I: Slack notified."
MSG_DE[$MSG_SLACK_SEND_OK]="RBK0287I: Slack benachrichtigt."
#MSG_SLACK_OPTIONS_INCOMPLETE=288
#MSG_EN[$MSG_SLACK_OPTIONS_INCOMPLETE]="RBK0288E: Slack options not complete."
#MSG_DE[$MSG_SLACK_OPTIONS_INCOMPLETE]="RBK0288E: Slackoptionen nicht vollständig."
MSG_SLACK_INVALID_NOTIFICATION=289
MSG_EN[$MSG_SLACK_INVALID_NOTIFICATION]="RBK0289E: Invalid Slack notification %s detected. Valid notifications are %s."
MSG_DE[$MSG_SLACK_INVALID_NOTIFICATION]="RBK0289E: Ungültige Slack Notification %s eingegeben. Mögliche Notifikationen sind %s."
MSG_UNPROTECTED_PROPERTIESFILE=290
MSG_EN[$MSG_UNPROTECTED_PROPERTIESFILE]="RBK0290W: Configuration file %s is unprotected."
MSG_DE[$MSG_UNPROTECTED_PROPERTIESFILE]="RBK0290W: Konfigurationsdatei %s ist nicht geschützt."
MSG_IMG_BOOT_FSCHECK_FAILED=291
MSG_EN[$MSG_IMG_BOOT_FSCHECK_FAILED]="RBK0291E: Bootpartition check failed with RC %s."
MSG_DE[$MSG_IMG_BOOT_FSCHECK_FAILED]="RBK0291E: Bootpartitioncheck endet fehlerhaft mit RC %s."
MSG_IMG_BOOT_CHECK_STARTED=292
MSG_EN[$MSG_IMG_BOOT_CHECK_STARTED]="RBK0292I: Bootpartition check started."
MSG_DE[$MSG_IMG_BOOT_CHECK_STARTED]="RBK0292I: Bootpartitionscheck gestartet."
MSG_NO_PARTUUID_SYNCHRONIZED=293
MSG_EN[$MSG_NO_PARTUUID_SYNCHRONIZED]="RBK0293W: No PARTUUID updated in %s for %s. Backup may not boot correctly."
MSG_DE[$MSG_NO_PARTUUID_SYNCHRONIZED]="RBK0293W: Es konnte keine PARTUUID in %s für %s erneuert werden. Das Backup könnte nicht starten."
MSG_CURRENT_CONFIGURATION_UPDATE_REQUIRED=294
MSG_EN[$MSG_CURRENT_CONFIGURATION_UPDATE_REQUIRED]="RBK0294I: Current configuration version %s has to be be updated to %s."
MSG_DE[$MSG_CURRENT_CONFIGURATION_UPDATE_REQUIRED]="RBK0294I: Aktuelle Konfigurationsversion %s muss auf Version %s upgraded werden."
MSG_SYNC_CMDLINE_FSTAB=295
MSG_EN[$MSG_SYNC_CMDLINE_FSTAB]="RBK0295I: Synchonizing %s and %s."
MSG_DE[$MSG_SYNC_CMDLINE_FSTAB]="RBK0295I: %s und %s werden synchronisiert."
OVERLAY_FILESYSTEM_NOT_SUPPORTED=296
MSG_EN[$OVERLAY_FILESYSTEM_NOT_SUPPORTED]="RBK0296E: Overlay filesystem is not supported."
MSG_DE[$OVERLAY_FILESYSTEM_NOT_SUPPORTED]="RBK0296E: Overlayfilesystem wird nicht unterstützt."

declare -A MSG_HEADER=( ['I']="---" ['W']="!!!" ['E']="???" )

# setup trap function
# trap function then will be called with trap as argument
#
# borrowed from # from http://stackoverflow.com/a/2183063/804678

function trapWithArg() { # function trap1 trap2 ... trapn
	logEntry "$*"
	local func="$1" ; shift
	for sig ; do
		trap "$func $sig" "$sig"
	done
	logExit
}

LOG_INDENT_INC=4

# Create message and substitute parameters

function getMessageText() { # messagenumber parm1 parm2 ...

	local msg p i s

	msgVar="MSG_${LANGUAGE}"

	if [[ -n ${SUPPORTED_LANGUAGES[$LANGUAGE]} ]]; then
		msgVar="$msgVar[$1]"
		msg=${!msgVar}
		if [[ -z $msg ]]; then # no translation found
			msg="${MSG_EN[$1]}" # fallback into english
		fi
	else
		msg="${MSG_EN[$1]}" # fallback into english
	fi

	if [[ -z $msg ]]; then
		msg="${MSG_EN[$MSG_UNDEFINED]} $1"
	fi

	shift

	# Change messages with old message format using %s, %s ... to new format using %1, %2 ...
	i=1
	while [[ "$msg" =~ %s ]]; do
		msg="$(sed "s|%s|%$i|" <<<"$msg" 2>/dev/null)" # have to use explicit command name
		(( i++ ))
	done

	for ((i = 1; $i <= $#; i++)); do # substitute all message parameters
		p=${!i}
		p="$(sed 's/\&/\\\&/g' <<< "$p")" # escape &
		let s=$i
		s="%$s"
		msg="$(sed "s|$s|$p|" <<<"$msg" 2>/dev/null)" # have to use explicit command name
	done

	msg="$(sed "s/%[0-9]+//g" <<<"$msg" 2>/dev/null)" # delete trailing %n definitions

	local msgPref=${msg:0:3}
	if [[ $msgPref == "RBK" ]]; then # RBK0001E
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

# --- Helper function to extract the message text in German or English and insert message parameters

function getMessage() { # messageNumber parm1 parm2

	local msg
	msg="$(getMessageText "$@")"
	echo "$msg"
}

function logItem() { # message
	logIntoOutput $LOG_TYPE_DEBUG "---" "" "$@"
}

function logEntry() { # message
	logIntoOutput $LOG_TYPE_DEBUG "-->" "" "${FUNCNAME[1]} $@"
	(( LOG_INDENT+=LOG_INDENT_INC ))
}

function logExit() { # message
	(( LOG_INDENT-=LOG_INDENT_INC ))
	logIntoOutput $LOG_TYPE_DEBUG "<--" "" "${FUNCNAME[1]} $@"
}

function logSystem() {
	logEntry
	logCommand "uname -a"
	[[ -f /etc/os-release ]] &&	logCommand "cat /etc/os-release"
	[[ -f /etc/debian_version ]] &&	logCommand "cat /etc/debian_version"
	[[ -f /etc/fstab ]] &&	logCommand "cat /etc/fstab"
	logCommand "locale"
	logExit
}

function logCommand() { # command
	(( LOG_INDENT+=LOG_INDENT_INC ))
	local callerLineNo=${BASH_LINENO[0]}
	logIntoOutput $LOG_TYPE_DEBUG "***" $callerLineNo "$1"
	local r="$($1 2>&1)"
	logIntoOutput $LOG_TYPE_DEBUG "   " $callerLineNo "$r"
	(( LOG_INDENT-=LOG_INDENT_INC ))
}

function logSystemServices() {
	logEntry
	if (( $SYSTEMSTATUS )); then
		if ! which lsof &>/dev/null; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "lsof" "lsof"
			else
				logCommand "service --status-all 2>&1"
				logCommand "lsof / | awk 'NR==1 || $4~/[0-9][uw]/' 2>&1"
			fi
	fi
	logExit
}

function logIntoOutput() { # logtype prefix lineno message

	[[ $LOG_DEBUG != $LOG_LEVEL ]] && return

	local type="${LOG_TYPEs[$1]}"
	shift
	local prefix="$1"
	shift
	local lineno="$1"
	shift
	[[ -z $lineno ]] && lineno=${BASH_LINENO[1]}
	local dte=$(date +%Y%m%d-%H%M%S)
	local indent=$(printf '%*s' "$LOG_INDENT")
	local m

	local line
	while IFS= read -r line; do
		printf -v m "%s %04d: %s %s %s" "$type" "$lineno" "$indent" "$prefix" "$line"
		case $LOG_OUTPUT in
			$LOG_OUTPUT_VARLOG | $LOG_OUTPUT_BACKUPLOC | $LOG_OUTPUT_HOME)
				echo "$dte $m" >> "$LOG_FILE"
				;;
			*)
				echo "$dte $m" >> "$LOG_FILE"
				;;
		esac
	done <<< "$@"
}

# log everything written to stdout or stderr into log file
function logEnable() {

	LOG_FILE="$TEMP_LOG_FILE"
	MSG_FILE="$TEMP_MSG_FILE"
	rm -f "$LOG_FILE" &>/dev/null
	rm -f "$MSG_FILE" &>/dev/null

	logItem "Logfiles used: $LOG_FILE and $MSG_FILE"

	touch "$LOG_FILE"
	touch "$MSG_FILE"

	# save file descriptors, see https://unix.stackexchange.com/questions/80988/how-to-stop-redirection-in-bash
	exec 3>&1 4>&2
	# see https://stackoverflow.com/questions/3173131/redirect-copy-of-stdout-to-log-file-from-within-bash-script-itself
	exec 1> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE")
	exec 2> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE" >&2)

	logItem "$GIT_CODEVERSION"
	local sep="$(getMessage $MSG_SENSITIVE_SEPARATOR)"
	local warn="$(getMessage $MSG_SENSITIVE_WARNING)"
	logItem "$sep"
	logItem "$warn"
	logItem "$sep"
}

# move temporary log file to it's destination
function logFinish() {

	logEntry

	local DEST_LOGFILE DEST_MSGFILE

	rm -f "$FINISH_LOG_FILE"

	if [[ $LOG_LEVEL != $LOG_NONE ]]; then
		# 1) error occured and logoutput is backup location which was deleted or fake mode
		# 2) fake
		# 3) backup location was already deleted by SR
		if [[ "$LOG_OUTPUT" =~ $LOG_OUTPUT_IS_NO_USERDEFINEDFILE_REGEX ]]; then			# no -L used
			logItem "$rc $LOG_OUTPUT $FAKE"
			if [[ (( $rc != 0 )) && (( $LOG_OUTPUT == $LOG_OUTPUT_BACKUPLOC )) ]] \
				|| (( $FAKE )) \
				|| [[ ! -e $BACKUPTARGET_DIR ]]; then
				LOG_OUTPUT=$LOG_OUTPUT_HOME 			# save log in home directory
				logItem "LOG_OUTPUT=$LOG_OUTPUT"
			fi
		fi

		logItem "LOG_OUTPUT: $LOG_OUTPUT"

		case $LOG_OUTPUT in
			$LOG_OUTPUT_VARLOG)
				LOG_BASE="/var/log/$MYNAME"
				if [ ! -d ${LOG_BASE} ]; then
					if ! mkdir -p ${LOG_BASE} &>> "$FINISH_LOG_FILE"; then
						writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNABLE_TO_CREATE_DIRECTORY "${LOG_BASE}"
						exitError $RC_CREATE_ERROR
					fi
				fi
				DEST_LOGFILE="$LOG_BASE/$HOSTNAME$LOGFILE_EXT"
				cat "$LOG_FILE" &>> "$DEST_LOGFILE"		# don't move, just append
				;;
			$LOG_OUTPUT_HOME)
				DEST_LOGFILE="$CALLING_HOME/${MYNAME}$LOGFILE_EXT"
				DEST_MSGFILE="$CALLING_HOME/${MYNAME}$MSGFILE_EXT"
				;;
			$LOG_OUTPUT_BACKUPLOC)
				DEST_LOGFILE="$BACKUPTARGET_DIR/${MYNAME}$LOGFILE_EXT"
				DEST_MSGFILE="$BACKUPTARGET_DIR/${MYNAME}$MSGFILE_EXT"
				;;
			*) # option -L <filename>
				DEST_LOGFILE="$LOG_OUTPUT$LOGFILE_EXT"
				DEST_MSGFILE="$LOG_OUTPUT$MSGFILE_EXT"
		esac

		logItem "DEST_LOGFILE: $DEST_LOGFILE"
		logItem "DEST_MSGFILE: $DEST_MSGFILE"

		if [[ "$LOG_FILE" != "$DEST_LOGFILE" ]]; then
			logItem "Moving Logfile: $LOG_FILE"
			mv "$LOG_FILE" "$DEST_LOGFILE" &>>"$FINISH_LOG_FILE"
			LOG_FILE="$DEST_LOGFILE"		# now final log location was established. log anything else in final log file
			logItem "Logfiles used: $LOG_FILE and $MSG_FILE"
		fi
		if [[ "$MSG_FILE" != "$DEST_MSGFILE" ]]; then
			logItem "Moving Msgfile: $MSG_FILE"
			mv "$MSG_FILE" "$DEST_MSGFILE" &>>"$FINISH_LOG_FILE"
			MSG_FILE="$DEST_MSGFILE"		# now final msg location was established. log anything else in final log file
			logItem "Logfiles used: $LOG_FILE and $MSG_FILE"
		fi

		chown "$CALLING_USER:$CALLING_USER" "$DEST_LOGFILE" &>>$FINISH_LOG_FILE # make sure logfile is owned by caller
		chown "$CALLING_USER:$CALLING_USER" "$DEST_MSGFILE" &>>$FINISH_LOG_FILE # make sure msgfile is owned by caller

		if [[ -e $FINISH_LOG_FILE ]]; then					# append optional final messages
			logCommand "cat $FINISH_LOG_FILE"
			cat "$FINISH_LOG_FILE" &>> "$DEST_LOGFILE"
			rm -f "$FINISH_LOG_FILE" &>> "$DEST_LOGFILE"
		fi

		if (( !$INCLUDE_ONLY )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_SAVED_LOG "$LOG_FILE"
		fi

		if [[ $TEMP_LOG_FILE != $DEST_LOGFILE ]]; then		# logfile was copied somewhere, delete temp logfile
			rm -f "$TEMP_LOG_FILE" &>> "$LOG_FILE"
		fi

	fi

	logExit
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

	local extension rc=0

	if [[ $1 == $EMAIL_EXTENSION ]]; then
		local extensionFileName="${MYNAME}_${EMAIL_EXTENSION}.sh"
		shift 1
		local args=( "$@" )

		if which $extensionFileName &>/dev/null; then
			writeToConsole $MSG_LEVEL_DETAILED $MSG_EXTENSION_CALLED "$extensionFileName"
			$extensionFileName "${args[@]}"
			rc=$?
			logItem "Extension RC: $rc"
			if (( $rc != 0 )); then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXTENSION_FAILED "$extensionFileName" "$rc"
			fi
		else
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_EMAIL_EXTENSION_NOT_FOUND "$extensionFileName"
		fi
	else

		local extensions="$EXTENSIONS"
		local xEnabled

		(( $RESTORE )) && extensions="$RESTORE_EXTENSIONS"

		for extension in $extensions; do

			if [[ $1 == $NOTIFICATION_BACKUP_EXTENSION ]]; then
				local extensionFileName="${MYNAME}_${extension}.sh" # notification has no pre, post and ready
			else
				local extensionFileName="${MYNAME}_${extension}_$1.sh"
			fi

			if which $extensionFileName &>/dev/null; then
				logItem "Calling $extensionFileName $2"

				local extension_call=0

				writeToConsole $MSG_LEVEL_DETAILED $MSG_EXTENSION_CALLED "$extensionFileName"

				if [[ ${extension} == $NOTIFICATION_BACKUP_EXTENSION  ]]; then
					extensionCall=1
				fi

				if (( extension_call )); then
					xEnabled=0
					if [ -o xtrace ]; then	# disable xtrace
						xEnabled=1
						set +x
					fi
				fi

				executeShellCommand ". $extensionFileName $2"
				rc=$?
				if (( extension_call )); then
					if (( $xEnabled )); then	# enable xtrace again
						set -x
					fi
				fi

				logItem "Extension RC: $rc"
				if (( $rc != 0 )); then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXTENSION_FAILED "$extensionFileName" "$rc"
				fi
			else
				logItem "$extensionFileName not found - skipping"
			fi
		done
	fi

	logExit

	return $rc
}

# usage

function usage() {

	[[ -z "${LANG}" ]] && LANG="en_US.UTF-8"
	LANG_EXT="${LANG^^*}"
	LANG_SUFF="${LANG_EXT:0:2}"

	NO_YES=( $(getMessage $MSG_NO_YES) )

	local func="usage${LANG_SUFF}"

	if ! fn_exists $func; then
		func="usageEN"
	fi

	$func

}

# Write message

function writeToConsole() {  # msglevel messagenumber message
	local msg level timestamp
	(( $noNL )) && noNL="-n"

	level=$1
	shift

	msg="$(getMessageText "$@")"

	if (( $level <= $MSG_LEVEL )); then

# --- RBK0105I: Deleting new backup directory /backup/obelix/obelix-rsync-backup-20180912-215541.
# ??? RBK0005E: Backup failed. Check previous error messages for details.

		local msgNumber=$(cut -f 2 -d ' ' <<< "$msg")
		local msgSev=${msgNumber:7:1}

		if (( $TIMESTAMPS )); then
			timestamp="$(date +'%m-%d-%Y %T') "
		fi

		if (( $INTERACTIVE )); then
			local consoleMsg="$timestamp$msg"
			if [[ "$COLORING" =~ $COLORING_CONSOLE ]]; then
				consoleMsg="$(colorAnnotation $COLOR_TYPE_VT100 "$consoleMsg")"
			fi
			if [[ $msgSev == "E" ]]; then
				echo $noNL -e "$consoleMsg" >&2
			else
				echo $noNL -e "$consoleMsg" >&1
			fi
		fi

		if (( $LOG_LEVEL != $LOG_NONE )); then
			echo $noNL -e "$timestamp$msg" >> "$MSG_FILE"
		fi
	fi

	if (( ! $INTERACTIVE || $RESTORE )); then # don't write message twice into log for backup but once for restore
		local line
		while IFS= read -r line; do
			logIntoOutput $LOG_TYPE_MSG "$line"
		done <<< "$msg"
	fi

	unset noNL
}

function isUnsupportedVersion() {

	logEntry
	local rc=0
	[[ "$GIT_COMMIT" != "$SHA_PLACEHOLDER"  && "$GIT_DATE" != "$DATE_PLACEHOLDER" ]] && rc=1
	logExit $rc
	return $rc
}

function isSupportedEnvironment() {

	logEntry

	if (( $REGRESSION_TEST )); then
		logExit 0
		return 0
	fi

	local MODELPATH=/sys/firmware/devicetree/base/model
	local OSRELEASE=/etc/os-release
	local RPI_ISSUE=/etc/rpi-issue

	if [[ ! -e $OSRELEASE ]]; then
		logItem "$OSRELEASE not found"
		logExit 1
		return 1
	fi

	logItem $(<$OSRELEASE)
	grep -q -E -i "^(NAME|ID)=.*ubuntu" $OSRELEASE
	local rc=$?

	IS_UBUNTU=$(( ! $rc ))
	logItem "IS_UBUNTU: $IS_UBUNTU"

#	Check it's Raspberry HW
	if [[ ! -e $MODELPATH ]]; then
		logItem "$MODELPATH not found"
		logExit 1
		return 1
	fi
	logItem "Modelpath: $(cat "$MODELPATH" | sed 's/\x0/\n/g')"
	! grep -q -i "raspberry" $MODELPATH && return 1

#	OS was built for a Raspberry (RaspbainOS only)
	if [[ -e $RPI_ISSUE ]]; then
		logItem "$RPI_ISSUE: $(< $RPI_ISSUE)"
		logExit 0
		return 0
	fi
	logItem "$RPI_ISSUE not found"

	logExit $rc
	return $rc

: <<SKIP
	[[ ! -e $OSRELEASE ]] && return 1
	logCommand "cat $OSRELEASE"

	local ARCH=$(dpkg --print-architecture)
	logItem "Architecture: $ARCH"

	if [[ "$ARCH" == "armhf" ]]; then
		grep -q -E -i "^(NAME|ID)=.*(raspbian|debian)" $OSRELEASE
		return
	elif [[ "$ARCH" == "arm64" ]]; then
		grep -q -E -i "^(NAME|ID)=.*debian" $OSRELEASE
		return
	fi
SKIP
}

# Create a backupfile FILE.bak from FILE. If this file already exists rename this file to FILE.n.bak when n is next backup number
# return filename created and error if a backup file cannot be created
function createBackupVersion() { # file

	local file="$1"

	if [[ ! -f "$file" ]]; then
		return 1
	fi

	DIR=$(dirname "${file}")

	if [[ -f "$file.bak" ]]; then														# .bak exists already
		local versions="$(ls $file\.*\.* -1 2>/dev/null)"

		if [[ -z $versions ]]; then												# no backup version detected
			versionNumber=1															# start with version 1
		else
			local last="$basename $(tail -n 1 <<< "$versions")" 			# extract highest version number
			local lastFile="$(basename "$last")"
			local lastVersionNumber="$(sed -E 's/.*([0-9]+)\.bak$/\1/' <<< $lastFile )"
			(( versionNumber = lastVersionNumber+1 ))							# use next version number
		fi

		local backupFile="$file.${versionNumber}.bak"
		mv "$file.bak" "$backupFile"
		(( $? )) && return 1
	fi

	cp -a "$file" "$file.bak"

	echo "$file.bak"
	return $?	# return status of cp command
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
		echo "MSG_FILE=\"$MSG_FILE\"" >> $VARS_FILE
		echo "LOG_FILE=\"$LOG_FILE\"" >> $VARS_FILE
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

# ignore tool error if configured
function ignoreErrorRC() { # rc errors_to_ignore
	logEntry
	local rc="$1"
	if (( $rc != 0 )); then
		for i in ${@:2}; do
			if (( $i == $rc )); then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_TOOL_ERROR_SKIP "$BACKUPTYPE" $rc
				rc=0
				break
			fi
		done
	fi
	logExit $rc
	return $rc
}

function executeDD() { # cmd silent
	logEntry
	local rc cmd
	cmd="LC_ALL=C $1"
	logItem "$cmd"
	( eval "$cmd" 2>&1 1>&5 | grep -viE "records [in|out]| copied," | tee -a $MSG_FILE; exit ${PIPESTATUS[0]} ) 5>&1
	ignoreErrorRC $? "$2"
	rc=$?
	logExit $rc
	return $rc
}

# ((sh test.sh 2>&1 1>&3 | tee errors.log) 3>&1 | tee output.log) > /dev/null 2>&1

function executeRsync() { # cmd flagsToIgnore
	logEntry
	local rc cmd
	cmd="$1"
	logItem "$cmd"
	( eval "$cmd" 2>&1 1>&5 | tee -a $MSG_FILE $LOG_FILE) 5>&1
	ignoreErrorRC $? "$2"
	rc=$?
	logExit $rc
	return $rc
}

# Removing leading `/' from member names message is annoying. Use grep -v "Removing" to remove the message
# and use $PIPESTATUS and catch and return the tar RC

function executeTar() { # cmd flagsToIgnore
	logEntry
	local rc cmd
	cmd="LC_ALL=C $1"
	logItem "$cmd"
	( eval "$cmd" 2>&1 1>&5 | grep -iv " Removing" | tee -a $MSG_FILE $LOG_FILE; exit ${PIPESTATUS[0]} ) 5>&1
	ignoreErrorRC $? "$2"
	rc=$?
	logExit $rc
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

# return 0 for ==, 1 for <, and 2 for >
# version format 0.1.2.3-ext, -ext will be discarded
function compareVersions() { # v1 v2

	logEntry "$1 $2"
	local v1="$(sed 's/-.*$//' <<< $1)"
	local v2="$(sed 's/-.*$//' <<< $2)"

	local v1e v2e IFS rc
	IFS="." v1e=( $v1 0 0 0 0)
	IFS="." v2e=( $v2 0 0 0 0)

	local rc=0
	for (( i=0; i<=3; i++ )); do
		if (( ${v1e[$i]} < ${v2e[$i]} )); then
			rc=1
			break
		fi
		if (( ${v1e[$i]} > ${v2e[$i]} )); then
			rc=2
			break
		fi
	done
	logExit $rc
	return $rc
}

function repeat() { # char num
	local s
	s=$( yes $1 | head -$2 | tr -d "\n" )
	echo $s
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

function logOptions() { # option state

	logEntry "$1"

	logItem "Options: $INVOCATIONPARMS"
	logItem "AFTER_STARTSERVICES=$AFTER_STARTSERVICES"
	logItem "APPEND_LOG=$APPEND_LOG"
	logItem "APPEND_LOG_OPTION=$APPEND_LOG_OPTION"
	logItem "BACKUPPATH=$BACKUPPATH"
	logItem "BACKUPTYPE=$BACKUPTYPE"
	logItem "BEFORE_STOPSERVICES=$BEFORE_STOPSERVICES"
	logItem "BOOT_DEVICE=$BOOT_DEVICE"
	logItem "CHECK_FOR_BAD_BLOCKS=$CHECK_FOR_BAD_BLOCKS"
	logItem "COLOR_CODES="${COLOR_CODES[@]}""
 	logItem "COLORING=$COLORING"
 	logItem "CONFIG_FILE=$CONFIG_FILE"
 	logItem "DD_BACKUP_SAVE_USED_PARTITIONS_ONLY=$DD_BACKUP_SAVE_USED_PARTITIONS_ONLY"
 	logItem "DD_BLOCKSIZE=$DD_BLOCKSIZE"
 	logItem "DD_PARMS=$DD_PARMS"
 	logItem "DD_WARNING=$DD_WARNING"
	logItem "DEPLOYMENT_HOSTS=$DEPLOYMENT_HOSTS"
	logItem "DYNAMIC_MOUNT=$DYNAMIC_MOUNT"
	logItem "EMAIL=$EMAIL"
	logItem "EMAIL_COLORING=$EMAIL_COLORING"
	logItem "EMAIL_PARMS=$EMAIL_PARMS"
	logItem "EXCLUDE_LIST=$EXCLUDE_LIST"
	logItem "EXTENSIONS=$EXTENSIONS"
	logItem "FAKE=$FAKE"
	logItem "FINAL_COMMAND=$FINAL_COMMAND"
	logItem "HANDLE_DEPRECATED=$HANDLE_DEPRECATED"
	logItem "IGNORE_ADDITIONAL_PARTITIONS=$IGNORE_ADDITIONAL_PARTITIONS"
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
	logItem "NOTIFY_START=$NOTIFY_START"
	logItem "NOTIFY_UPDATE=$NOTIFY_UPDATE"
	logItem "PARTITIONBASED_BACKUP=$PARTITIONBASED_BACKUP"
	logItem "PARTITIONS_TO_BACKUP=$PARTITIONS_TO_BACKUP"
	logItem "PUSHOVER_TOKEN=$PUSHOVER_TOKEN"
	logItem "PUSHOVER_USER=$PUSHOVER_USER"
	logItem "PUSHOVER_NOTIFICATIONS=$PUSHOVER_NOTIFICATIONS"
	logItem "PUSHOVER_SOUND_SUCCESS=$PUSHOVER_SOUND_SUCCESS"
	logItem "PUSHOVER_SOUND_FAILURE=$PUSHOVER_SOUND_FAILURE"
	logItem "PUSHOVER_PRIORITY_SUCCESS=$PUSHOVER_PRIORITY_SUCCESS"
	logItem "PUSHOVER_PRIORITY_FAILURE=$PUSHOVER_PRIORITY_FAILURE"
	logItem "REBOOT_SYSTEM=$REBOOT_SYSTEM"
	logItem "RESIZE_ROOTFS=$RESIZE_ROOTFS"
	logItem "RESTORE_DEVICE=$RESTORE_DEVICE"
	logItem "RESTORE_EXTENSIONS=$RESTORE_EXTENSIONS"
	logItem "ROOT_PARTITION=$ROOT_PARTITION"
	logItem "RSYNC_BACKUP_ADDITIONAL_OPTIONS=$RSYNC_BACKUP_ADDITIONAL_OPTIONS"
	logItem "RSYNC_BACKUP_OPTIONS=$RSYNC_BACKUP_OPTIONS"
	logItem "RSYNC_IGNORE_ERRORS=$RSYNC_IGNORE_ERRORS"
	logItem "SENDER_EMAIL=$SENDER_EMAIL"
 	logItem "SKIP_DEPRECATED=$SKIP_DEPRECATED"
 	logItem "SKIPLOCALCHECK=$SKIPLOCALCHECK"
	logItem "SLACK_WEBHOOK_URL=$SLACK_WEBHOOK_URL"
	logItem "SLACK_NOTIFICATIONS=$SLACK_NOTIFICATIONS"
 	logItem "SMART_RECYCLE=$SMART_RECYCLE"
 	logItem "SMART_RECYCLE_DRYRUN=$SMART_RECYCLE_DRYRUN"
 	logItem "SMART_RECYCLE_OPTIONS=$SMART_RECYCLE_OPTIONS"
	logItem "STARTSERVICES=$STARTSERVICES"
	logItem "STOPSERVICES=$STOPSERVICES"
	logItem "SYSTEMSTATUS=$SYSTEMSTATUS"
	logItem "TAR_BACKUP_ADDITIONAL_OPTIONS=$TAR_BACKUP_ADDITIONAL_OPTIONS"
	logItem "TAR_BACKUP_OPTIONS=$TAR_BACKUP_OPTIONS"
	logItem "TAR_BOOT_PARTITION_ENABLED=$TAR_BOOT_PARTITION_ENABLED"
	logItem "TAR_IGNORE_ERRORS=$TAR_IGNORE_ERRORS"
	logItem "TAR_RESTORE_ADDITIONAL_OPTIONS=$TAR_RESTORE_ADDITIONAL_OPTIONS"
	logItem "TELEGRAM_TOKEN=$TELEGRAM_TOKEN"
	logItem "TELEGRAM_CHATID=$TELEGRAM_CHATID"
	logItem "TELEGRAM_NOTIFICATIONS=$TELEGRAM_NOTIFICATIONS"
	logItem "TIMESTAMPS=$TIMESTAMPS"
	logItem "UPDATE_UUIDS=$UPDATE_UUIDS"
	logItem "VERBOSE=$VERBOSE"
	logItem "YES_NO_RESTORE_DEVICE=$YES_NO_RESTORE_DEVICE"
	logItem "ZIP_BACKUP=$ZIP_BACKUP"

	logExit

}

function initializeDefaultConfigVariables() {

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
	# commands to execute just before terminating
	DEFAULT_FINAL_COMMAND=""
	# HTML color and VT100 color for warning and error, yellow red
	DEFAULT_COLOR_CODES=("#FF8000 33" "#FF0000 31")
	# email to send completion status
	DEFAULT_EMAIL=""
	# sender email used with ssmtp
	DEFAULT_SENDER_EMAIL=""
	# Additional parameters for email program (optional)
	DEFAULT_EMAIL_PARMS=""
	# log level  (0 = none, 1 = debug)
	DEFAULT_LOG_LEVEL=1
	# log output ( 1 = /var/log, 2 = backuppath, 3 = ./raspiBackup.log, <somefilename>)
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
	# dd warning
	DEFAULT_DD_WARNING=0
	# exclude list
	DEFAULT_EXCLUDE_LIST=""
	# notify in email if there is an updated script version available  (0 = false, 1 = true)
	DEFAULT_NOTIFY_UPDATE=1
	# backup extensions to call
	DEFAULT_EXTENSIONS=""
	# restore extensions to call
	DEFAULT_RESTORE_EXTENSIONS=""
	# partition based backup  (0 = false, 1 = true)
	DEFAULT_PARTITIONBASED_BACKUP=0
	# backup first two partitions only
	DEFAULT_PARTITIONS_TO_BACKUP="1 2"
	# language (DE or EN)
	DEFAULT_LANGUAGE=""
	# hosts which will get the updated backup script with parm -y - non pwd access with keys has to be enabled
	# Example: "root@raspberrypi root@fhem root@openhab root@magicmirror"
	DEFAULT_DEPLOYMENT_HOSTS=""
	# Use with care !
	DEFAULT_YES_NO_RESTORE_DEVICE="loop"
	# Use hardlinks for partitionbootfiles
	DEFAULT_LINK_BOOTPARTITIONFILES=0
	# save boot partition with tar
	DEFAULT_TAR_BOOT_PARTITION_ENABLED=0
	# reboot system at end of backup
	DEFAULT_REBOOT_SYSTEM=0
	# Change these options only if you know what you are doing !!!
	DEFAULT_RSYNC_BACKUP_OPTIONS="-aHAx --delete"
	DEFAULT_RSYNC_BACKUP_ADDITIONAL_OPTIONS=""
	DEFAULT_TAR_BACKUP_OPTIONS="-cpi --one-file-system"
	DEFAULT_TAR_BACKUP_ADDITIONAL_OPTIONS=""
	DEFAULT_TAR_RESTORE_ADDITIONAL_OPTIONS=""
	# Send email only in case of errors. Use with care !
	DEFAULT_MAIL_ON_ERROR_ONLY=0
	# Version to suppress deprecated message, separated with spaces
	DEFAULT_SKIP_DEPRECATED=""
	# Smart recycle
	DEFAULT_SMART_RECYCLE=0
	# Smart recycle dryrun
	DEFAULT_SMART_RECYCLE_DRYRUN=1
	# Smart recycle parameters (daily, weekly, monthly and yearly)
	DEFAULT_SMART_RECYCLE_OPTIONS="7 4 12 1"
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
	# update device UUIDs
	DEFAULT_UPDATE_UUIDS=1
	# send stats
	DEFAULT_SEND_STATS=1
	# ignore partitions > 2 in normal mode
	DEFAULT_IGNORE_ADDITIONAL_PARTITIONS=0
	# notify in email and telegram when backup starts
	DEFAULT_NOTIFY_START=0
	# Telegram token
	DEFAULT_TELEGRAM_TOKEN=""
	# Telegram target chatid
	DEFAULT_TELEGRAM_CHATID=""
	# Telegram notifications to send. S(uccess), F(ailure), M(messages as file), m(essages as text)
	DEFAULT_TELEGRAM_NOTIFICATIONS="F"
	# Pushover token
	DEFAULT_PUSHOVER_TOKEN=""
	# Pushover user
	DEFAULT_PUSHOVER_USER=""
	# Pushover notifications to send. S(uccess), F(ailure), M(essages)
	DEFAULT_PUSHOVER_NOTIFICATIONS="F"
	# Pushover sound for success
	DEFAULT_PUSHOVER_SOUND_SUCCESS=""
	# Pushover sound for failure
	DEFAULT_PUSHOVER_SOUND_FAILURE=""
	# Pushover priorities
	DEFAULT_PUSHOVER_PRIORITY_SUCCESS="0"
	DEFAULT_PUSHOVER_PRIORITY_FAILURE="1"
	# Slack
	DEFAULT_SLACK_WEBHOOK_URL=""
	DEFAULT_SLACK_NOTIFICATIONS=""
	# Colorize console output (C) and/or email (E)
	DEFAULT_COLORING="CM"
	# mail coloring scheme (SUBJECT or OPTION)
	DEFAULT_EMAIL_COLORING="$EMAIL_COLORING_SUBJECT"
	# Name of backup partition to dynamically mount (e.g. /dev/sda1 or /backup)
	DEFAULT_DYNAMIC_MOUNT=""
	# Define bootdevice (e.g. /dev/mmcblk0, /dev/nvme0n1 or /dev/sda) and turn off boot device autodiscovery
	DEFAULT_BOOT_DEVICE=""
	############# End default config section #############
}

function copyDefaultConfigVariables() {

	APPEND_LOG="$DEFAULT_APPEND_LOG"
	APPEND_LOG_OPTION="$DEFAULT_APPEND_LOG_OPTION"
	BACKUPPATH="$DEFAULT_BACKUPPATH"
	BACKUPTYPE="$DEFAULT_BACKUPTYPE"
	BOOT_DEVICE="$DEFAULT_BOOT_DEVICE"
	AFTER_STARTSERVICES="$DEFAULT_AFTER_STARTSERVICES"
	BEFORE_STOPSERVICES="$DEFAULT_BEFORE_STOPSERVICES"
	CHECK_FOR_BAD_BLOCKS="$DEFAULT_CHECK_FOR_BAD_BLOCKS"
	COLOR_CODES=("${DEFAULT_COLOR_CODES[0]}" "${DEFAULT_COLOR_CODES[1]}")
	COLORING="$DEFAULT_COLORING"
	DD_BACKUP_SAVE_USED_PARTITIONS_ONLY="$DEFAULT_DD_BACKUP_SAVE_USED_PARTITIONS_ONLY"
	DD_BLOCKSIZE="$DEFAULT_DD_BLOCKSIZE"
	DD_PARMS="$DEFAULT_DD_PARMS"
	DD_WARNING="$DEFAULT_DD_WARNING"
	DEPLOYMENT_HOSTS="$DEFAULT_DEPLOYMENT_HOSTS"
	EMAIL="$DEFAULT_EMAIL"
	EMAIL_COLORING="$DEFAULT_EMAIL_COLORING"
	EMAIL_PARMS="$DEFAULT_EMAIL_PARMS"
	EMAIL_PROGRAM="$DEFAULT_MAIL_PROGRAM"
	EMAIL_SENDER="$DEFAULT_EMAIL_SENDER"
	EXCLUDE_LIST="$DEFAULT_EXCLUDE_LIST"
	EXTENSIONS="$DEFAULT_EXTENSIONS"
	FINAL_COMMAND="$DEFAULT_FINAL_COMMAND"
	IGNORE_ADDITIONAL_PARTITIONS="$DEFAULT_IGNORE_ADDITIONAL_PARTITIONS"
	KEEPBACKUPS="$DEFAULT_KEEPBACKUPS"
	KEEPBACKUPS_DD="$DEFAULT_KEEPBACKUPS_DD"
	KEEPBACKUPS_DDZ="$DEFAULT_KEEPBACKUPS_DDZ"
	KEEPBACKUPS_TAR="$DEFAULT_KEEPBACKUPS_TAR"
	KEEPBACKUPS_TGZ="$DEFAULT_KEEPBACKUPS_TGZ"
	KEEPBACKUPS_RSYNC="$DEFAULT_KEEPBACKUPS_RSYNC"
	LINK_BOOTPARTITIONFILES="$DEFAULT_LINK_BOOTPARTITIONFILES"
	LOG_LEVEL="$DEFAULT_LOG_LEVEL"
	LOG_OUTPUT="$DEFAULT_LOG_OUTPUT"
	MAIL_ON_ERROR_ONLY="$DEFAULT_MAIL_ON_ERROR_ONLY"
	MSG_LEVEL="$DEFAULT_MSG_LEVEL"
	NOTIFY_START="$DEFAULT_NOTIFY_START"
	NOTIFY_UPDATE="$DEFAULT_NOTIFY_UPDATE"
	PARTITIONBASED_BACKUP="$DEFAULT_PARTITIONBASED_BACKUP"
	PARTITIONS_TO_BACKUP="$DEFAULT_PARTITIONS_TO_BACKUP"
	PUSHOVER_TOKEN="$DEFAULT_PUSHOVER_TOKEN"
	PUSHOVER_USER="$DEFAULT_PUSHOVER_USER"
	PUSHOVER_NOTIFICATIONS="$DEFAULT_PUSHOVER_NOTIFICATIONS"
	PUSHOVER_SOUND_SUCCESS="$DEFAULT_PUSHOVER_SOUND_SUCCESS"
	PUSHOVER_SOUND_FAILURE="$DEFAULT_PUSHOVER_SOUND_FAILURE"
	PUSHOVER_PRIORITY_SUCCESS="$DEFAULT_PUSHOVER_PRIORITY_SUCCESS"
	PUSHOVER_PRIORITY_FAILURE="$DEFAULT_PUSHOVER_PRIORITY_FAILURE"
	REBOOT_SYSTEM="$DEFAULT_REBOOT_SYSTEM"
	RESIZE_ROOTFS="$DEFAULT_RESIZE_ROOTFS"
	RESTORE_DEVICE="$DEFAULT_RESTORE_DEVICE"
	RESTORE_REMINDER_INTERVAL="$DEFAULT_RESTORE_REMINDER_INTERVAL"
	RESTORE_REMINDER_REPEAT="$DEFAULT_RESTORE_REMINDER_REPEAT"
	RESTORE_EXTENSIONS="$DEFAULT_RESTORE_EXTENSIONS"
	RSYNC_BACKUP_ADDITIONAL_OPTIONS="$DEFAULT_RSYNC_BACKUP_ADDITIONAL_OPTIONS"
	RSYNC_BACKUP_OPTIONS="$DEFAULT_RSYNC_BACKUP_OPTIONS"
	SENDER_EMAIL="$DEFAULT_SENDER_EMAIL"
	SKIPLOCALCHECK="$DEFAULT_SKIPLOCALCHECK"
	SLACK_WEBHOOK_URL="$DEFAULT_SLACK_WEBHOOK_URL"
	SLACK_NOTIFICATIONS="$DEFAULT_SLACK_NOTIFICATIONS"
	SMART_RECYCLE="$DEFAULT_SMART_RECYCLE"
	SMART_RECYCLE_DRYRUN="$DEFAULT_SMART_RECYCLE_DRYRUN"
	SMART_RECYCLE_OPTIONS="$DEFAULT_SMART_RECYCLE_OPTIONS"
	STARTSERVICES="$DEFAULT_STARTSERVICES"
	SEND_STATS="$DEFAULT_SEND_STATS"
	STOPSERVICES="$DEFAULT_STOPSERVICES"
	SYSTEMSTATUS="$DEFAULT_SYSTEMSTATUS"
	TAR_BACKUP_ADDITIONAL_OPTIONS="$DEFAULT_TAR_BACKUP_ADDITIONAL_OPTIONS"
	TAR_BACKUP_OPTIONS="$DEFAULT_TAR_BACKUP_OPTIONS"
	TAR_BOOT_PARTITION_ENABLED="$DEFAULT_TAR_BOOT_PARTITION_ENABLED"
	TAR_RESTORE_ADDITIONAL_OPTIONS="$DEFAULT_TAR_RESTORE_ADDITIONAL_OPTIONS"
	TELEGRAM_CHATID="$DEFAULT_TELEGRAM_CHATID"
	TELEGRAM_NOTIFICATIONS="$DEFAULT_TELEGRAM_NOTIFICATIONS"
	TELEGRAM_TOKEN="$DEFAULT_TELEGRAM_TOKEN"
	TIMESTAMPS="$DEFAULT_TIMESTAMPS"
	UPDATE_UUIDS="$DEFAULT_UPDATE_UUIDS"
	VERBOSE="$DEFAULT_VERBOSE"
	YES_NO_RESTORE_DEVICE="$DEFAULT_YES_NO_RESTORE_DEVICE"
	ZIP_BACKUP="$DEFAULT_ZIP_BACKUP"
	DYNAMIC_MOUNT="$DEFAULT_DYNAMIC_MOUNT"

	checkImportantParameters

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
#       nvme0n1
# Output:
# 	mmcblk0p
# 	sda
#       nvme0n1p

function getPartitionPrefix() { # device

	logEntry "$1"
	if [[ $1 =~ ^(mmcblk|loop|nvme|sd[a-z]) ]]; then
		local pref="$1"
		[[ $1 =~ ^(mmcblk|loop|nvme) ]] && pref="${1}p"
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
#       /dev/nvme0n1p1
# Output:
# 	1
#	2

function getPartitionNumber() { # deviceName

	logEntry "$1"
	local id
	if [[ $1 =~ ^/dev/(mmcblk|loop)[0-9]+p([0-9]+) || $1 =~ ^/dev/(sd[a-z])([0-9]+) || $1 =~ ^/dev/(nvme)[0-9]+n[0-9]+p([0-9]+) ]]; then
		id=${BASH_REMATCH[2]}
	else
		assertionFailed $LINENO "Unable to retrieve partition number from deviceName $1"
	fi
	echo "$id"
	logExit "$id"

}

function hasSpaces() { # file- or directory name
	[[ $1 = *" "* ]]
	return
}

# borrowed from https://gist.github.com/cdown/1163649#file-gistfile1-sh
function urlencode() {

    local ld_lc_collate=$LC_COLLATE
    LC_COLLATE=C

    local length="${#1}"
    local i
    for (( i = 0; i < length; i++ )); do
        local c="${1:$i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf '%s' "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done

    LC_COLLATE=$old_lc_collate
}

# borrowed from https://gist.github.com/cdown/1163649#file-gistfile1-sh
function urldecode() {

    local url_encoded="${1//+/ }"
    printf '%b' "${url_encoded//%/\\x}"
}

function dynamic_mount() { # mountpoint

	logEntry "$1"

	local rc=0
	if ! isMounted $1; then
		mount "$1" &>> $LOG_FILE
		rc=$?
		if (( $rc != 0 )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_DYNAMIC_MOUNT_FAILED "$1" "$rc"
			exitError "$RC_MOUNT_FAILED"
		else
			DYNAMIC_MOUNT_EXECUTED=1
			writeToConsole $MSG_LEVEL_DETAILED $MSG_DYNAMIC_MOUNT_OK "$1"
		fi
	else
		writeToConsole $MSG_LEVEL_DETAILED $MSG_DYNAMIC_MOUNT_NOT_REQUIRED "$1"
	fi

	logCommand "mount"

	logExit

}

function isUpdatePossible() {

	logEntry

	versions=( $(isNewVersionAvailable) )
	version_rc=$?
	if [[ $version_rc == 0 ]]; then
		NEWS_AVAILABLE=1
		UPDATE_POSSIBLE=1
		latestVersion="${versions[0]}"
		newVersion="${versions[1]}"
		oldVersion="${versions[2]}"

		writeToConsole $MSG_LEVEL_MINIMAL $MSG_NEW_VERSION_AVAILABLE "$newVersion" "$oldVersion"
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_VISIT_VERSION_HISTORY_PAGE "$(getMessage $MSG_VERSION_HISTORY_PAGE)"
	fi

	logExit

}

function downloadPropertiesFile() { # FORCE

	logEntry "$1"

	NEW_PROPERTIES_FILE=0

	if shouldRenewDownloadPropertiesFile "$1"  && (( ! $REGRESSION_TEST )); then # don't execute any update checks in regression test

		writeToConsole $MSG_LEVEL_MINIMAL $MSG_CHECKING_FOR_NEW_VERSION

		if (( $DEFAULT_SEND_STATS )); then
			local mode="N"; (( $PARTITIONBASED_BACKUP )) && mode="P"
			local type=$BACKUPTYPE
			local keep=$KEEPBACKUPS
			local func="B"; (( $RESTORE )) && func="R"
			local srOptions="$(urlencode "$SMART_RECYCLE_OPTIONS")"
			local srs=""; [[ -n $SMART_RECYCLE_DRYRUN ]] && (( ! $SMART_RECYCLE_DRYRUN )) && srs="$srOptions"
			local os="rsp"; (( $IS_UBUNTU )) && os="ubu"
			local downloadURL="${PROPERTIES_DOWNLOAD_URL}?version=$VERSION&type=$type&mode=$mode&keep=$keep&func=$func&srs=$srs&os=$os"
		else
			local downloadURL="$PROPERTIES_DOWNLOAD_URL"
		fi

		local dlHttpCode dlRC
		dlHttpCode=$(downloadFile "$downloadURL" "$LATEST_TEMP_PROPERTY_FILE")
		dlRC=$?
		if (( $dlRC != 0 )); then
			if [[ $1 == "FORCE" ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_DOWNLOAD_FAILED "$(sed "s/\?.*$//" <<< "$downloadURL")" "$dlHttpCode" $dlRC
				exitError $RC_DOWNLOAD_FAILED
			else
				: # silently ignore download error or property file
			fi
		else
			NEW_PROPERTIES_FILE=1
			parsePropertiesFile "$LATEST_TEMP_PROPERTY_FILE"
		fi
	fi

	logExit "$NEW_PROPERTIES_FILE"
	return
}

#VERSION="0.6.3.1"
#INCOMPATIBLE=""
#DEPRECATED=""
#BETA="0.6.3.2"

function parsePropertiesFile() { # propertyFileName

	logEntry

	local properties="$(grep "^VERSION=" "$1" 2>/dev/null)"
	[[ $properties =~ $PROPERTY_REGEX ]] && VERSION_PROPERTY=${BASH_REMATCH[1]}

	properties="$(grep "^INCOMPATIBLE=" "$1" 2>/dev/null)"
	[[ $properties =~ $PROPERTY_REGEX ]] && INCOMPATIBLE_PROPERTY=${BASH_REMATCH[1]}

	properties="$(grep "^DEPRECATED=" "$1" 2>/dev/null)"
	[[ $properties =~ $PROPERTY_REGEX ]] && DEPRECATED_PROPERTY=${BASH_REMATCH[1]}

	properties="$(grep "^BETA=" "$1" 2>/dev/null)"
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

function verifyIsOnOff() { # arg

	local v=${!1}
	local uc="${v^^}"

	case "$uc" in
		ON|TRUE|AN|1) : echo "1"
			return
			;;
		OFF|FALSE|AUS|0) : echo "0"
			return
			;;
	esac

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_INVALID_TRUE_FALSE_OPTION "$v" "$1"
	exitError $RC_PARAMETER_ERROR
}

function downloadFile() { # url, targetFileName

		logEntry "URL: "$(sed -E "s/\?.*$//" <<<"$1")", file: $2"

		local httpCode rc

		local url="$1"
		local file="$2"
		local f=$(mktemp)
		local httpCode rc
		httpCode=$(curl -sSL -o "$f" -m $DOWNLOAD_TIMEOUT -w %{http_code} -L "$url" 2>>$LOG_FILE)
		rc=$?
		logItem "httpCode: $httpCode RC: $rc"

		# Some nasty code required because download plugin doesn't return 404 if file not found but a HTML doc

		if (( $rc == 0 )); then
			if [[ ! -f "$f" ]]; then
					httpCode="404"
					rc=101
			elif [[ ${httpCode:0:1} == "2" ]]; then
				if head -n 1 "$f" | grep -q "^<!DOCTYPE html>"; then
					httpCode="404"
					rc=101
				fi
			else
				rc=101
			fi
		fi

		if (( $rc != 0 )); then
			[[ -f $f ]] && rm $f &>>$LOG_FILE
			echo "$httpCode"
			logExit "$rc $httpCode"
			return $rc
		fi

		[[ -f $f ]] && mv $f $file &>>$LOG_FILE
		echo "200"
		logExit 0
		return 0
}

function askYesNo() { # message message_parms

	local yes_no=$(getMessage $MSG_QUERY_CHARS_YES_NO)
	local addtlMsg=0

	if [[ $# > 1 ]]; then
		local m="$1"
		shift
		addtlMsg=1
		local args="$@"
	fi

	local answer

	if (( $addtlMsg )); then
		noNL=1
		writeToConsole $MSG_LEVEL_MINIMAL $m "$args" "$yes_no"
	else
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_ARE_YOU_SURE "$yes_no"
	fi

	if (( $NO_YES_QUESTION )); then
		answer=$(getMessage $MSG_ANSWER_CHARS_YES)
	else
		read answer
	fi

	answer=${answer:0:1}	# first char only
	answer=${answer:-"n"}	# set default no

	local yes=$(getMessage $MSG_ANSWER_CHARS_YES)
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
			executeShellCommand "$STOPSERVICES"
			local rc=$?
			if [[ $rc != 0 ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_STOP_SERVICES_FAILED "$rc"
				exitError $RC_STOP_SERVICES_ERROR
			fi
			STOPPED_SERVICES=1
		fi
	fi
	logSystemServices
	logExit
}

function executeBeforeStopServices() {
	logEntry
	if [[ -n "$BEFORE_STOPSERVICES" ]]; then
		writeToConsole $MSG_LEVEL_DETAILED $MSG_BEFORE_STOPPING_SERVICES "$BEFORE_STOPSERVICES"
		logItem "$BEFORE_STOPSERVICES"
		executeShellCommand "$BEFORE_STOPSERVICES"
		local rc=$?
		if [[ $rc != 0 ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_BEFORE_STOP_SERVICES_FAILED "$rc"
			exitError $RC_BEFORE_STOP_SERVICES_ERROR
		fi
		BEFORE_STOPPED_SERVICES=1
	fi
	logExit
}

function finalCommand() {

	logEntry

	if [[ -n "$FINAL_COMMAND" ]]; then
		writeToConsole $MSG_LEVEL_DETAILED $MSG_FINAL_COMMAND_EXECUTED "$FINAL_COMMAND"
		logItem "$FINAL_COMMAND"
		executeShellCommand "$FINAL_COMMAND"
		local rc=$?
		if [[ $rc != 0 ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FINAL_COMMAND_FAILED "$rc"
		fi
	fi

	logExit
}

function startServices() {

	logEntry

	logSystemServices

	if (( $STOPPED_SERVICES )); then
		if [[ -n "$STARTSERVICES" ]]; then
			if (( ! $RESTORE && $REBOOT_SYSTEM && ! $FAKE )); then
				:	# just ignore STARTSERVICES
			elif [[ "$STARTSERVICES" =~ $NOOP_AO_ARG_REGEX ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_SKIP_STARTING_SERVICES
			else
				writeToConsole $MSG_LEVEL_DETAILED $MSG_STARTING_SERVICES "$STARTSERVICES"
				logItem "$STARTSERVICES"
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
	logExit
}

function extractVersionFromFile() { # fileName type (VERSION|VERSION_CONFIG)
	logEntry "$@"
	local v="$(grep -E "^$2=" "$1" | cut -f 2 -d = | sed  -e 's/[[:space:]]*#.*$//g' -e 's/\"//g')"
	[[ -z "$v" ]] && v="0.0.0.0"
	echo "$v"
	logExit "$v"
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
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_INCOMPATIBLE_UPDATE "$newVersion" "$(getMessage $MSG_VERSION_HISTORY_PAGE)"
				exitNormal
			fi
		fi

		local betaVersion=$(isBetaAvailable)

		if [[ -n $betaVersion ]]; then
			if (( ! $FORCE_UPDATE )) && [[ "${betaVersion}-beta" > $oldVersion ]]; then 			# beta version available
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_UPDATE_TO_BETA "$oldVersion" "${betaVersion}-beta"
				if askYesNo; then
					DOWNLOAD_URL="$BETA_DOWNLOAD_URL"
					newVersion="${betaVersion}-beta"
					updateNow=1
				fi
			elif (( $FORCE_UPDATE )) && [[ "${betaVersion}-beta" == "$oldVersion" ]]; then		# refresh current beta with latest version
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_UPDATE_TO_LATEST_BETA "${betaVersion}-beta"
				if askYesNo; then
					DOWNLOAD_URL="$BETA_DOWNLOAD_URL"
					newVersion="${betaVersion}-beta"
					updateNow=1
				fi
			fi
		fi

		if [[ $rc == 0 ]] && (( ! $updateNow )); then							# new version available
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_UPDATE_TO_VERSION "$oldVersion" "$newVersion"
			if ! askYesNo; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_UPDATE_ABORTED
				exitNormal
			fi
			updateNow=1
		elif [[ $rc == 1 || $rc == 2 ]] && (( ! $IS_BETA )) && (( ! $updateNow && $FORCE_UPDATE )); then		# no beta version, same or upper version (maybe development version) but force update
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FORCE_UPDATE "$newVersion"
			if askYesNo; then
				updateNow=1
			fi
		fi

		if (( $updateNow )); then
			local tmpFile="/tmp/${MYSELF}~"
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_DOWNLOADING "$file" "$MYHOMEURL"

			local dlHttpCode dlRC
			dlHttpCode="$(downloadFile "$DOWNLOAD_URL" "${tmpFile}")"
			dlRC=$?
			if (( $dlRC != 0 )); then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_DOWNLOAD_FAILED "$$DOWNLOAD_URL" "$dlHttpCode" $dlRC
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_SCRIPT_UPDATE_FAILED "$MYSELF"
				exitError $RC_DOWNLOAD_FAILED
			fi
			newName="$SCRIPT_DIR/$MYNAME.$oldVersion.sh"
			mv $SCRIPT_DIR/$MYSELF $newName
			mv $tmpFile $SCRIPT_DIR/$MYSELF
			chown --reference=$newName $SCRIPT_DIR/$MYSELF
			chmod --reference=$newName $SCRIPT_DIR/$MYSELF
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_SCRIPT_UPDATE_OK "$SCRIPT_DIR/$MYSELF" "$oldVersion" "$newVersion" "$newName"
			# refresh version information from updated script
			local properties="$(grep "^VERSION=" "$SCRIPT_DIR/$MYSELF" 2>/dev/null)"
			[[ $properties =~ $PROPERTY_REGEX ]] && VERSION=${BASH_REMATCH[1]}
			logItem "Updating VERSION from updated script to $VERSION"
			local properties="$(grep "^VERSION_SCRIPT_CONFIG=" "$SCRIPT_DIR/$MYSELF" 2>/dev/null)"
			[[ $properties =~ $PROPERTY_REGEX ]] && VERSION_SCRIPT_CONFIG=${BASH_REMATCH[1]}
			logItem "Updating VERSION_SCRIPT_CONFIG from updated script to $VERSION_SCRIPT_CONFIG"
		else
			rm $MYSELF~ &>/dev/null
			if (( $updateNow )); then
				if [[ $rc == 1 ]]; then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_SCRIPT_UPDATE_NOT_NEEDED "$SCRIPT_DIR/$MYSELF" "$newVersion"
				elif [[ $rc == 2 ]]; then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_SCRIPT_UPDATE_NOT_REQUIRED "$SCRIPT_DIR/$MYSELF" "$oldVersion" "$newVersion"
				else
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_SCRIPT_UPDATE_FAILED "$MYSELF"
				fi
			fi
		fi
	fi

	logExit $updateNow

	return $updateNow

}

# 0 = yes, no otherwise

function supportsFileAttributes() {	# directory

	logEntry "$1"

	local attrs owner group r x
	local attrsT ownerT groupT
	local result=1	# no

	local MAXRETRY=3						# retries
	local retryCount=$(( MAXRETRY + 1 ))

	touch /tmp/$MYNAME.fileattributes &>>$LOG_FILE
	chown 65534:65534 /tmp/$MYNAME.fileattributes &>>$LOG_FILE
	chmod 057 /tmp/$MYNAME.fileattributes &>>$LOG_FILE

	# ls -la output
	# ----r-xrwx 1 nobody nogroup 0 Oct 30 19:06 /tmp/supportsFileattributes.fileattributes

	read -r attrs x owner group r <<< "$(ls -la "/tmp/$MYNAME.fileattributes")"
	logItem "$attrs # $owner # $group"

	while (( retryCount-- > 0 && result == 1 )); do
		# following command will return an error and message
		# cp: failed to preserve ownership for '/mnt/supportsFileattributes.fileattributes': Operation not permitted
		cp -a "/tmp/$MYNAME.fileattributes" "/$1" &>>"$LOG_FILE"
		local rc=$?
		if (( $rc )); then
			logItem "cp failed with rc $rc - retryCount"
		else
			# SC2034: x appears unused. Verify it or export it.
			# shellcheck disable=SC2034
			read -r attrsT x ownerT groupT r <<< "$(ls -la "/$1/$MYNAME.fileattributes")"
			# attrsT="$(sed 's/+$//' <<< $attrsT)" # delete + sign present for extended security attributes
			# Don't delete ACL mark. Target backup directory should not have any ACLs. Otherwise all files in the backup dircetory will inherit ACLs
			# and a restored backup will populate these ACLs on the restored system which is wrong!
			logItem "Remote: $attrsT # $ownerT # $groupT"

			# check fileattributes and ownerships are identical
			if [[ "$attrs" == "$attrsT" && "$owner" == "$ownerT" && "$group" == "$groupT" ]]; then
				result=0
				break
			fi
		fi
		sleep 3s
	done

	rm /tmp/$MYNAME.fileattributes &>>$LOG_FILE
	rm /$1/$MYNAME.fileattributes &>>$LOG_FILE

	logExit $result

	return $result
}

# 0 = yes, no otherwise

function supportsHardlinks() {	# directory

	logEntry "$1"

	local links
	local result=1 # no

	touch /$1/$MYNAME.hlinkfile &>>$LOG_FILE

	local MAXRETRY=3						# retries
	local retryCount=$(( MAXRETRY + 1 ))

	while (( retryCount-- > 0 && result == 1 )); do
		cp -l /$1/$MYNAME.hlinkfile /$1/$MYNAME.hlinklink &>>$LOG_FILE
		links=$(ls -la /$1/$MYNAME.hlinkfile | cut -f 2 -d ' ')
		logItem "Links: $links"
		if (( $links == 2 )); then
			result=0
			break
		fi
	done

	rm -f /$1/$MYNAME.hlinkfile &>/dev/null
	rm -f /$1/$MYNAME.hlinklink &>/dev/null

	logExit "$result"

	return $result
}

# 0 = yes, no otherwise

function supportsSymlinks() {	# directory

	logEntry "$1"

	local result=1	# no
	touch /$1/$MYNAME.slinkfile &>>$LOG_FILE
	ln -s /$1/$MYNAME.slinkfile /$1/$MYNAME.slinklink &>>$LOG_FILE
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
		#logCommand "cat /proc/mounts"
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

	local mp="$(findMountPath "$1")"
	logItem "Mountpoint: $mp"

	local df="$(LC_ALL=C df --output=fstype,target | grep -E " ${mp}$" | cut -f 1 -d " ")"
	logItem "df -T: $df"
	echo $df

	logExit "$df"

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

# find path of mount of file or directory

function findMountPath() {

	logEntry "$1"

	local path
	path="$1"

	# path has to be mount point of the file system (second field fs_file in /etc/fstab) and NOT fs_spec otherwise test algorithm will create endless loop
	if [[ "${1:0:1}" == "/" ]]; then
		while [[ "$path" != "" ]]; do
			logItem "Path: $path"
			if mountpoint -q "$path"; then
				break
			fi
			path=${path%/*}
		done
	fi
	echo "$path"
	logExit "$path"

	return
}

function readConfigParameters() {

	logEntry

	ETC_CONFIG_FILE="/usr/local/etc/${MYNAME}.conf"
	HOME_CONFIG_FILE="$CALLING_HOME/.${MYNAME}.conf"
	CURRENTDIR_CONFIG_FILE="$CURRENT_DIR/.${MYNAME}.conf"

	local file
	local files=($ETC_CONFIG_FILE $HOME_CONFIG_FILE $CURRENTDIR_CONFIG_FILE)

	for file in ${files[@]}; do
		if [[ -e $file ]]; then
			local attrs="$(stat -c %a $file)"
			if (( ( 0$attrs & 077 ) != 0 )); then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNPROTECTED_PROPERTIESFILE $file
			fi
		fi
	done

	# Override default parms with parms in global config file

	ETC_CONFIG_FILE_INCLUDED=0
	if [ -f "$ETC_CONFIG_FILE" ]; then
		set -e
		. "$ETC_CONFIG_FILE"
		set +e
		ETC_CONFIG_FILE_INCLUDED=1
		ETC_CONFIG_FILE_VERSION="$(extractVersionFromFile "$ETC_CONFIG_FILE" "$VERSION_CONFIG_VARNAME" )"
		logItem "Read config ${ETC_CONFIG_FILE} : ${ETC_CONFIG_FILE_VERSION}$NL$(egrep -v '^\s*$|^#' $ETC_CONFIG_FILE)"
	fi

	# Override default parms with parms in user config file

	HOME_CONFIG_FILE_INCLUDED=0
	if [ -f "$HOME_CONFIG_FILE" ]; then
		set -e
		. "$HOME_CONFIG_FILE"
		set +e
		HOME_CONFIG_FILE_INCLUDED=1
		HOME_CONFIG_FILE_VERSION="$(extractVersionFromFile "$HOME_CONFIG_FILE" "$VERSION_CONFIG_VARNAME" )"
		logItem "Read config ${HOME_CONFIG_FILE} : ${HOME_CONFIG_FILE_VERSION}$NL$(egrep -v '^\s*$|^#' $HOME_CONFIG_FILE)"

	fi

	# Override default parms with parms in current directory config file

	CURRENTDIR_CONFIG_FILE_INCLUDED=0
	if [[ "$HOME_CONFIG_FILE" != "$CURRENTDIR_CONFIG_FILE" ]]; then
		if [ -f "$CURRENTDIR_CONFIG_FILE" ]; then
			set -e
			. "$CURRENTDIR_CONFIG_FILE"
			set +e
			CURRENTDIR_CONFIG_FILE_INCLUDED=1
			CURRENTDIR_CONFIG_FILE_VERSION="$(extractVersionFromFile "$CURRENTDIR_CONFIG_FILE" "$VERSION_CONFIG_VARNAME" )"
			logItem "Read config ${CURRENTDIR_CONFIG_FILE} : ${HOME_CONFIG_FILE_VERSION}$NL$(egrep -v '^\s*$|^#' $CURRENTDIR_CONFIG_FILE)"
		fi
	fi

	logExit
}

function setupEnvironment() {

	logEntry

	if (( ! $RESTORE )); then
		ZIP_BACKUP_TYPE_INVALID=0		# logging not enabled right now, invalid backuptype will be handled later
		if (( $ZIP_BACKUP )); then
			if [[ $BACKUPTYPE == $BACKUPTYPE_DD || $BACKUPTYPE == $BACKUPTYPE_TAR ]]; then
				BACKUPTYPE=${Z_TYPE_MAPPING[${BACKUPTYPE}]}	# tar-> tgz and dd -> ddz
			else
				ZIP_BACKUP_TYPE_INVALID=1
			fi
		fi

		if [[ -n "$DYNAMIC_MOUNT" ]]; then
			dynamic_mount "$DYNAMIC_MOUNT"
		fi

		BACKUPFILES_PARTITION_DATE="$HOSTNAME-backup"

		if [[ -z "$BACKUP_DIRECTORY_NAME" ]]; then
			BACKUPFILE="${HOSTNAME}-${BACKUPTYPE}-backup-$DATE"
		else
			BACKUPFILE="${HOSTNAME}-${BACKUPTYPE}-backup-${DATE}_${BACKUP_DIRECTORY_NAME}"
		fi

		BACKUPTARGET_ROOT="$BACKUPPATH/$HOSTNAME"
		BACKUPTARGET_DIR="$BACKUPTARGET_ROOT/$BACKUPFILE"

		BACKUPTARGET_FILE="$BACKUPTARGET_DIR/$BACKUPFILE${FILE_EXTENSION[$BACKUPTYPE]}"

		if [[ ! -d "${BACKUPTARGET_DIR}" ]]; then
			if (( $FAKE || ( $SMART_RECYCLE && $SMART_RECYCLE_DRYRUN ) )); then
				: # don't create backupdirectory
			else
				if ! mkdir -p "${BACKUPTARGET_DIR}"; then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNABLE_TO_CREATE_DIRECTORY "${BACKUPTARGET_DIR}"
					exitError $RC_CREATE_ERROR
				fi
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

		if (( $FAKE )) && [[ "$LOG_OUTPUT" =~ $LOG_OUTPUT_IS_NO_USERDEFINEDFILE_REGEX ]]; then
			LOG_OUTPUT=$LOG_OUTPUT_HOME
			logItem "LOG_OUTPUT=$LOG_OUTPUT"
		fi
	fi

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

	logCommand "cat $file"

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

# colorAnnotation

# html vt100
COLOR_WARNING=0
COLOR_ERROR=1
COLOR_TYPE_HTML=0
COLOR_TYPE_VT100=1

COLOR_ON=("<span style="color:\%s">" "\e[1;%sm")
COLOR_OFF=("</span><br/>" "\e[0m")

function colorOn() { # colortype color
	local on="${COLOR_ON[$1]}"
	local color="${COLOR_CODES[$2]}"
	color=($color)
	printf -v r "$on" "${color[$1]}"
	echo -e -n "$r"
}

function colorOff() { # colortype color
	local off="${COLOR_OFF[$1]}"
	echo -e -n "$off"
}

# add color annotations for console and/or email

function colorAnnotation() { # colortype text

	# logEntry "$1"

	colorType="$1"
	shift
	local line
	while IFS= read -r line; do
	  if [[ "$line" =~ RBK....W ]]; then
			colorOn $colorType $COLOR_WARNING
			echo -n "$line"
			colorOff $colorType
			echo
		elif [[ "$line" =~ RBK....E ]]; then
			colorOn $colorType $COLOR_ERROR
			echo -n "$line"
			colorOff $colorType
			echo
		else
			if [[ $colorType == "$COLOR_TYPE_HTML" ]]; then
				echo "$line<br/>"
			else
				echo "$line"
			fi
		fi
	done <<< "$@"

	#logExit
}

function sendTelegramDocument() { # filename

		logEntry "$1"

		logItem "Telegram curl call: curl -s -X GET $TELEGRAM_URL$TELEGRAM_TOKEN/sendDocument -F chat_id=$TELEGRAM_CHATID -F document=@$MSG_FILE"
		local rsp="$(curl -s -X GET $TELEGRAM_URL$TELEGRAM_TOKEN/sendDocument -F chat_id=$TELEGRAM_CHATID -F document=@$MSG_FILE)"
		local curlRC=$?

		if (( $curlRC )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_TELEGRAM_SEND_LOG_FAILED $curlRC "N/A" "N/A"
		else
			logItem "Telegram response:${NL}${rsp}"
			ok=$(jq .ok <<< "$rsp")
			if [[ $ok == "true" ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_TELEGRAM_SEND_LOG_OK
			else
				local error_code="$(jq .error_code  <<< "$rsp")"
				local error_description="$(jq .description <<< "$rsp")"
				logItem "Error sending msg: $rsp"
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_TELEGRAM_SEND_FAILED "$curlRC" "$error_code" "$error_description"
			fi
		fi

		logExit
}

# Send message, exit

function sendTelegramMessage() { # message html(yes/no)

		logEntry "$1"

		if [[ -z $2 ]]; then
			logItem "Telegram curl call: curl -s -X POST $TELEGRAM_URL$TELEGRAM_TOKEN/sendMessage --data-urlencode "chat_id=$TELEGRAM_CHATID" --data-urlencode "text=$1""
			local rsp="$(curl -s -X POST $TELEGRAM_URL$TELEGRAM_TOKEN/sendMessage --data-urlencode "chat_id=$TELEGRAM_CHATID" --data-urlencode "text=$1")"
		else
			logItem "Telegram curl call: curl -s -X POST $TELEGRAM_URL$TELEGRAM_TOKEN/sendMessage --data-urlencode "chat_id=$TELEGRAM_CHATID" --data-urlencode "text=$1" -d parse_mode=html)"
			local rsp="$(curl -s -X POST $TELEGRAM_URL$TELEGRAM_TOKEN/sendMessage --data-urlencode "chat_id=$TELEGRAM_CHATID" --data-urlencode "text=$1" -d parse_mode=html)"
		fi
		local curlRC=$?

		if (( $curlRC )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_TELEGRAM_SEND_FAILED "$curlRC" "N/A" "N/A"
		else
			#logItem "Telegram response:${NL}${rsp}"
			local ok=$(jq .ok <<< "$rsp")
			if [[ $ok == "true" ]]; then
				logItem "Message sent"
				if [[ -n $2 ]]; then	# write message only for html, not for messages
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_TELEGRAM_SEND_OK
				fi
			else
				error_code="$(jq .error_code  <<< "$rsp")"
				error_description="$(jq .description <<< "$rsp")"
				logItem "Error sending msg: $rsp"
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_TELEGRAM_SEND_FAILED "$curlRC" "$error_code" "$error_description"
			fi
		fi

		logExit
}

function sendTelegramm() { # subject

	logEntry "$1"

	if [[ -n "$TELEGRAM_TOKEN" ]] ; then
		if ! which jq &>/dev/null; then # suppress error message when jq is not installed
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "jq" "jq"
		else
			local smiley
			if (( $WARNING_MESSAGE_WRITTEN )); then
				smiley="$EMOJI_WARNING ${smiley}"
			fi
			if (( $UPDATE_POSSIBLE )); then
				smiley="$EMOJI_UPDATE_POSSIBLE ${smiley}"
			fi
			if (( $BETA_AVAILABLE )); then
				smiley="$EMOJI_BETA_AVAILABLE ${smiley}"
			fi
			if (( $RESTORETEST_REQUIRED )); then
				smiley="$EMOJI_RESTORETEST_REQUIRED ${smiley}"
			fi
			if (( $VERSION_DEPRECATED )); then
				smiley="$EMOJI_VERSION_DEPRECATED ${smiley}"
			fi

			sendTelegramMessage "${smiley}$1" 1 # html
		fi
	fi

	logExit

}

# M -> add messages inline, m -> attach messages in a file
function sendTelegrammLogMessages() {

	logEntry

	if [[ -n "$TELEGRAM_TOKEN" ]] ; then
		if ! which jq &>/dev/null; then # suppress error message when jq is not installed
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "jq" "jq"
		else
			if [[ "$TELEGRAM_NOTIFICATIONS" =~ $TELEGRAM_NOTIFY_MESSAGES ]]; then
				sendTelegramDocument "$MSG_FILE"
			elif [[ "$TELEGRAM_NOTIFICATIONS" =~ $TELEGRAM_NOTIFY_MESSAGES2 ]]; then
				sendTelegramMessage "$(<$MSG_FILE)" # no html
			fi
		fi
	fi

	logExit

}

function sendPushover() { # subject sucess/failure

	logEntry "$1"

	if [[ -n "$PUSHOVER_TOKEN" ]] ; then
		if ! which jq &>/dev/null; then # suppress error message when jq is not installed
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "jq" "jq"
		else
			sendPushoverMessage "$1" "$2"
		fi
	fi

	logExit

}

# Send message, exit

function sendPushoverMessage() { # message 0/1->success/failure sound

		logEntry "$1"

		local sound prio
		if [[ -n $2 && "$2" == "1" ]]; then
			sound="$PUSHOVER_SOUND_FAILURE"
			prio="$PUSHOVER_PRIORITY_FAILURE"
		else
			sound="$PUSHOVER_SOUND_SUCCESS"
			prio="$PUSHOVER_PRIORITY_SUCCESS"
		fi

		local o=$(mktemp)

		local msg="$(grep -o "RBK0009.\+" $MSG_FILE)" # assume NOTIFY_START is set
		local msgEnd="$(grep -o "RBK0010.\+" $MSG_FILE)" # no, script finished

		[[ -n "$msgEnd" ]] && msg="$msgEnd"

		if [[ "$PUSHOVER_NOTIFICATIONS" =~ $PUSHOVER_NOTIFY_MESSAGES ]]; then
			msg="$(tail -c 1024 $MSG_FILE)"
		fi

		local cmd=(--form-string message="$1")
		cmd+=(--form-string "token=$PUSHOVER_TOKEN" \
				--form-string "user=$PUSHOVER_USER"\
				--form-string "priority=$prio"\
				--form-string "html=1"\
				--form-string "message=$msg"\
				--form-string "title=$1"\
				--form-string "sound=$sound")

		logItem "Pushover curl call: ${cmd[@]}"
		local httpCode
		httpCode="$(curl -s -w %{http_code} -o $o "${cmd[@]}" $PUSHOVER_URL)"
		local curlRC=$?
		logItem "Pushover response:${NL}$(<$o)"

		if (( $curlRC )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_PUSHOVER_SEND_FAILED "$curlRC" "$httpCode" "$rsp"
		else
			local ok=$(jq .status "$o")
			if [[ $ok == "1" ]]; then
				logItem "Message sent"
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_PUSHOVER_SEND_OK
			else
				error_description="$(jq .errors "$o" | tr -d '\n[]')"
				logItem "Error sending msg: $rsp"
				logItem "ErrorDescription: $error_description"
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_PUSHOVER_SEND_FAILED "$curlRC" "$httpCode" "$error_description"
			fi
		fi

		[[ -n $o ]] && rm $o

		logExit
}

function sendSlack() { # subject sucess/failure

	logEntry "$1"

	if [[ -n "$SLACK_WEBHOOK_URL" ]] ; then
		local smiley
		if (( $WARNING_MESSAGE_WRITTEN )); then
			smiley="$SLACK_EMOJI_WARNING ${smiley}"
		fi
		if (( $UPDATE_POSSIBLE )); then
			smiley="$SLACK_EMOJI_UPDATE_POSSIBLE ${smiley}"
		fi
		if (( $BETA_AVAILABLE )); then
			smiley="$SLACK_EMOJI_BETA_AVAILABLE ${smiley}"
		fi
		if (( $RESTORETEST_REQUIRED )); then
			smiley="$SLACK_EMOJI_RESTORETEST_REQUIRED ${smiley}"
		fi
		if (( $VERSION_DEPRECATED )); then
			smiley="$SLACK_EMOJI_VERSION_DEPRECATED ${smiley}"
		fi

		sendSlackMessage "${smiley}$1" "$2"
	fi

	logExit

}

# Send message, exit

function sendSlackMessage() { # message 0/1->success/failure

		logEntry "$1"

		local msg_json statusMsg

		local o=$(mktemp)

		if [[ -n $2 && "$2" == "1" ]]; then
			statusMsg="${SLACK_EMOJI_FAILED}$1"
		else
			statusMsg="${SLACK_EMOJI_OK}$1"
		fi

		local msg="$(grep -o "RBK0009.\+" $MSG_FILE)" # assume NOTIFY_START is set
		local msgEnd="$(grep -o "RBK0010.\+" $MSG_FILE)" # no, script finished

		[[ -n "$msgEnd" ]] && msg="$msgEnd"

		if [[ "$SLACK_NOTIFICATIONS" =~ $SLACK_NOTIFY_MESSAGES ]]; then
			msg="$(tail -n 32 $MSG_FILE)"
		fi

		read -r -d '' msg_json <<EOF
{
	"blocks": [
		{
			"type": "section",
			"text": {
				"type": "mrkdwn",
				"text": "*$statusMsg*\n$msg"
			}
		}
	]
}
EOF

		local cmd=(-X POST)
		cmd+=(-H 'Content-type: application/json')
		cmd+=(--data "$msg_json")

		logItem "Slack curl call: ${cmd[@]}"
		local httpCode
		httpCode="$(curl -s -w %{http_code} -o $o "${cmd[@]}" $SLACK_WEBHOOK_URL)"
		local curlRC=$?
		logItem "Slack response:${NL}$(<$o)"

		if (( $curlRC )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_SLACK_SEND_FAILED "$curlRC" "$httpCode" "$rsp"
		else
			if [[ "ok" == $(<$o) ]]; then
				logItem "Message sent"
				if [[ -n $2 ]]; then	# write message only for html, not for messages
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_SLACK_SEND_OK
				fi
			else
				logItem "Error sending msg: $rsp"
				local error_description="$(<$o)"
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_SLACK_SEND_FAILED "$curlRC" "$httpCode" "$error_description"
			fi
		fi

		[[ -n $o ]] && rm $o

		logExit
}

function sendEMail() { # content subject

	logEntry

	if [[ -n "$EMAIL" && rc != $RC_CTRLC ]]; then
		local attach content subject

		local attach=""
		local subject="$2"
		local coloringOption=""
		local contentType=""

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

		if [[ "$COLORING" =~ $COLORING_MAIL ]]; then
			if [[ ! $EMAIL_COLORING =~ $SUPPORTED_EMAIL_COLORING_REGEX ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_EMAIL_COLORING_NOT_SUPPORTED "$EMAIL_COLORING" "$SUPPORTED_EMAIL_COLORING"
				EMAIL_COLORING="$EMAIL_COLORING_SUBJECT"
			else
				if [[ "$EMAIL_COLORING" == "$EMAIL_COLORING_SUBJECT" ]]; then
					contentType="${NL}MIME-Version: 1.0${NL}Content-Type: text/html; charset=utf-8"
				elif [[ "$EMAIL_COLORING" == "$EMAIL_COLORING_OPTION" ]]; then
					coloringOption=("-a" "Content-Type: text/html;")
				else
					assertionFailed $LINENO "Unexpected email coloring $EMAIL_COLORING"
				fi
				logItem "Coloring option: $COLORING${NL}eMailColoring: $EMAIL_COLORING${NL}subject: "$subject"${NL}coloring: ${coloringOption[@]}"
			fi
		fi

		if (( ! $MAIL_ON_ERROR_ONLY || ( $MAIL_ON_ERROR_ONLY && ( rc != 0 || ( $NOTIFY_UPDATE && $NEWS_AVAILABLE ) ) ) )); then

			writeToConsole $MSG_LEVEL_DETAILED $MSG_SENDING_EMAIL

			if (( $APPEND_LOG )); then
				attach="$DEFAULT_APPEND_LOG_OPTION $LOG_FILE"
				logItem "Appendlog $attach"
			fi

			IFS=" "
			content="$NL$(<"$MSG_FILE")$NL$1$NL"
			unset IFS

			if [[ "$COLORING" =~ $COLORING_MAIL ]]; then
				content="$(colorAnnotation $COLOR_TYPE_HTML "$content")"
			fi

			subject="$subject$contentType"

			logItem "eMail: $EMAIL"
			logItem "eMail Program: $EMAIL_PROGRAM"
			logItem "Subject: ${subject[0]}"
			logItem "ColoringOption: ${coloringOption[@]}"
			logItem "ContentType: $contentType"
			logItem "Parms: $EMAIL_PARMS"

			local rc
			case $EMAIL_PROGRAM in
				$EMAIL_MAILX_PROGRAM)
					logItem "$EMAIL_PROGRAM" "${coloringOption[@]}" $EMAIL_PARMS -s "\"$subject\"" $attach $EMAIL <<< "\"$content\""
					"$EMAIL_PROGRAM" "${coloringOption[@]}" $EMAIL_PARMS -s "$subject" $attach "$EMAIL" <<< "$content"
					rc=$?
					logItem "$EMAIL_PROGRAM: RC: $rc"
					;;
				$EMAIL_SENDEMAIL_PROGRAM)
					logItem "echo $content | $EMAIL_PROGRAM $EMAIL_PARMS -u "$subject" $attach -t $EMAIL"
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
						logItem "echo -e To: $EMAIL${NL}From: $sender${NL}Subject: $subject${NL}${NL}$content | $EMAIL_PROGRAM $msmtp_default $EMAIL"
						echo -e "To: $EMAIL${NL}From: $sender${NL}Subject: $subject${NL}${NL}$content" | "$EMAIL_PROGRAM" $msmtp_default "$EMAIL"
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

function cleanupBackupDirectory() {

	logEntry

	if (( $rc != 0 )); then

		if [[ -d "$BACKUPTARGET_DIR" ]]; then
			if [[ -z "$BACKUPPATH" || -z "$BACKUPFILE" || -z "$BACKUPTARGET_DIR" || "$BACKUPFILE" == *"*"* || "$BACKUPPATH" == *"*"* || "$BACKUPTARGET_DIR" == *"*"* ]]; then
				assertionFailed $LINENO "Invalid backup path detected. BP: $BACKUPPATH - BTD: $BACKUPTARGET_DIR - BF: $BACKUPFILE"
			fi
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_REMOVING_BACKUP "$BACKUPTARGET_DIR"
			rm -rfd $BACKUPTARGET_DIR # delete incomplete backupdir
			local rmrc=$?
			if (( $rmrc != 0 )); then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_REMOVING_BACKUP_FAILED "$BACKUPTARGET_DIR" "$rmrc"
			fi
		fi
	fi

	logExit
}

# return text masqueraded
#
# Algorithm:
#
# if string lenght < 8 return @@@@(<string length>)
# if string lenght < 16 return first char followed by @*<string length-2> followed by last char
# otherwise return first char followed by @@@@ followed by last char and (<string length>)

function masquerade() { # text

	[[ -z "$1" ]] && return 1

	local t="$1"
	local l="${#t}"
	local lm="\($l\)"

	if (( $l < 8 )); then
		echo "$MASQUERADE_STRING$l"
		return 0
	fi

	local s=${t:0:1}
	local e=${t: -1}

	if (( $l < 16 )); then
		local m="$(yes ${MASQUERADE_STRING:0:1} | head -n $(($l-2)) | tr -d "\n" )"
		echo "$s$m$e"
	else
		echo "$s$MASQUERADE_STRING$e$lm"
	fi
	return 0
}

function masqueradeSensitiveInfoInLog() {

	local xEnabled=0
	if [ -o xtrace ]; then	# disable xtrace
		xEnabled=1
        set +x
	fi

	# no logging any more

	local m

	# receiver email

	if [[ -n "$EMAIL" ]]; then
		logItem "Masquerading eMail"
		m="$(masquerade "$EMAIL")"
		sed -i -E "s/$EMAIL/${m}/g" $LOG_FILE
	fi

	# sender email

	if [[ -n "$SENDER_EMAIL" ]]; then
		logItem "Masquerading sender eMail"
		m="$(masquerade "$SENDER_EMAIL")"
		sed -i -E "s/$SENDER_EMAIL/${m}/g" $LOG_FILE
	fi

	# email parms usually also contain eMails and passwords

	if [[ -n "$EMAIL_PARMS" ]]; then
		logItem "Masquerading eMail parameters"
		m="$(masquerade "$EMAIL_PARMS")"
		sed -i -E "s/$EMAIL_PARMS/${m}/" $LOG_FILE # may contain passwords
	fi

	# some mount options

	logItem "Masquerading some mount options"
	sed -i -E "s/username=[^,]+\,/username=${MASQUERADE_STRING},/" $LOG_FILE # used in cifs mount options
	sed -i -E "s/password=[^,]+\,/password=${MASQUERADE_STRING},/" $LOG_FILE
	sed -i -E "s/domain=[^,]+\,/domain=${MASQUERADE_STRING},/" $LOG_FILE

	# telegram token and chatid

	if	m="$(masquerade $TELEGRAM_TOKEN)"; then
		logItem "Masquerading telegram token"
		sed -i -E "s/${TELEGRAM_TOKEN}/${m}/g" $LOG_FILE
	fi

	if m="$(masquerade $TELEGRAM_CHATID)"; then
		logItem "Masquerading telegram chatid"
		sed -i -E "s/${TELEGRAM_CHATID}/${m}/g" $LOG_FILE
	fi

	# pushover token and user

	if	m="$(masquerade $PUSHOVER_USER)"; then
		logItem "Masquerading pushover user"
		sed -i -E "s/${PUSHOVER_USER}/${m}/g" $LOG_FILE
	fi

	if m="$(masquerade $PUSHOVER_TOKEN)"; then
		logItem "Masquerading pushover token"
		sed -i -E "s/${PUSHOVER_TOKEN}/${m}/g" $LOG_FILE
	fi

	# In home directories usually first names are used

	logItem "Masquerading home directory name"
	sed -i -E "s/\/home\/([^\\/])+\/(.)/\/home\/@USER@\/\2/g" $LOG_FILE

	# hostname may expose domain names

	logItem "Masquerading hostname"
	sed -i -E "s/$HOSTNAME/@HOSTNAME@/g" $LOG_FILE

	# any non local IPs used somewhere (mounts et al)

	logItem "Masquerading sensitive non local IPs"
	masqueradeNonlocalIPs $LOG_FILE

	# now delete console color annotation ESC sequences

	sed -i 's/\x1b\[1;33m//g' $LOG_FILE
	sed -i 's/\x1b\[1;31m//g' $LOG_FILE
	sed -i 's/\x1b\[0m//g' $LOG_FILE

	if (( $xEnabled )); then	# enable xtrace again
        	set -x
	fi

}

function masqueradeNonlocalIPs() {

	local masq=1
	local f=$(mktemp)

	cp $1 $f

	while (( $masq )); do

		masq=0

		cat $f | while read line; do
				if [[ $line =~ ([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3}) ]]; then
					local n1=${BASH_REMATCH[1]}
					local n2=${BASH_REMATCH[2]}
					local n3=${BASH_REMATCH[3]}
					local n4=${BASH_REMATCH[4]}
					local matchedIP="$n1.$n2.$n3.$n4"

#					strip leading 0s which will create errors in following == comparison
#					because numbers will be interpreted as octal values by bash and 8s and 9s are invalid octal numbers
					n1="$(sed -E 's/^0+([0-9])+/\1/' <<< "$n1")"
					n2="$(sed -E 's/^0+([0-9])+/\1/' <<< "$n2")"
					n3="$(sed -E 's/^0+([0-9])+/\1/' <<< "$n3")"
					n4="$(sed -E 's/^0+([0-9])+/\1/' <<< "$n4")"

					local ip="$n1.$n2.$n3.$n4"
					local masquip="%%%.%%%.$n3.$n4"

					(( $n1 == 192 && $n2 == 168 )) \
						|| (( $n1 == 10 )) \
						|| (( $n1 == 127 )) \
						|| (( $n1 == 0 )) \
						|| (( $n1 == 255 )) \
						|| ( (( $n1 == 172 )) && [[ $line =~ 172\.(1[6-9]|2[1-9]|3[0-1]) ]] ) && continue

					sed -i "s/$matchedIP/$masquip/g" "$1"
					masq=1
				fi
		done
	done
	rm $f
}

function callNotificationExtension() { # rc
		logEntry "$1"

		local xEnabled=0
		if [ -o xtrace ]; then	# disable xtrace
			xEnabled=1
			set +x
		fi
		callExtensions $NOTIFICATION_BACKUP_EXTENSION $1
		local rc=$?
		logItem "NotificationExtension rc: $rc"
		if (( $xEnabled )); then	# enable xtrace again
			set -x
		fi

		logExit $rc
		return $rc
}

function cleanupStartup() { # trap

	logEntry

	rc=${rc:-42}	# some failure during startup of script (RT error, option validation, ...)

	if [[ $1 == "SIGINT" ]]; then
		# ignore CTRL-C now
		trap '' SIGINT SIGTERM SIGHUP
		rc=$RC_CTRLC
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_CTRLC_DETECTED
	fi

	cleanupTempFiles

	logFinish

	if (( $LOG_LEVEL == $LOG_DEBUG )); then
		masqueradeSensitiveInfoInLog # and now masquerade sensitive details in log file
	fi

	logExit

	if [[ -n "$DYNAMIC_MOUNT" ]] && (( $DYNAMIC_MOUNT_EXECUTED )); then
		writeToConsole $MSG_LEVEL_DETAILED $MSG_DYNAMIC_UMOUNT_SCHEDULED "$DYNAMIC_MOUNT"
		umount -l $DYNAMIC_MOUNT &>>$LOG_FILE
	fi

	exit $rc
}

function lockMe() {
	logEntry
	exlock_now
	logExit
}

function unLockMe() {
	logEntry
	unlock
	logExit
}

function cleanup() { # trap

	logEntry

	rc=${rc:-42}	# some failure during startup of script (RT error, option validation, ...)

	if [[ $1 == "SIGINT" ]]; then
		# ignore CTRL-C now
		trap '' SIGINT SIGTERM EXIT
		rc=$RC_CTRLC
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_CTRLC_DETECTED
	fi

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_CLEANING_UP

	CLEANUP_RC=$rc

	if (( $RESTORE )); then
		cleanupRestore $1
	else
		cleanupBackup $1
		if [[ $rc -eq 0 ]]; then # don't apply BS if SR dryrun a second time, BS was done already previously
			if (( \
				( $SMART_RECYCLE && ! $SMART_RECYCLE_DRYRUN ) \
				|| ! $SMART_RECYCLE \
				)); then
				applyBackupStrategy
			fi
		fi
	fi

	cleanupTempFiles

	finalCommand "$rc"

	logItem "Terminate now with rc $CLEANUP_RC"

	if (( $rc != 0 )); then
		if (( ! $MAIL_ON_ERROR_ONLY )); then
			if (( $WARNING_MESSAGE_WRITTEN )); then
				if (( $RESTORE )); then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_WARNING
				else
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_WARNING
				fi
			fi
		fi

		if (( $rc != $RC_CTRLC )); then
			if (( $RESTORE )); then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_FAILED
			else
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_FAILED
			fi

			writeToConsole $MSG_LEVEL_MINIMAL $MSG_STOPPED "$HOSTNAME" "$MYSELF" "$VERSION" "$GIT_DATE_ONLY" "$GIT_COMMIT_ONLY" "$(date)" "$rc"
			logger -t $MYNAME "Stopped $VERSION ($GIT_COMMIT_ONLY). rc $rc"

			if (( ! $RESTORE )); then
				if (( $rc != $RC_EMAILPROG_ERROR )); then
					msgTitle=$(getMessage $MSG_TITLE_ERROR $HOSTNAME)
					sendEMail "$msg" "$msgTitle"
				fi
				if [[ -n "$TELEGRAM_TOKEN" ]]; then
					msg=$(getMessage $MSG_TITLE_ERROR $HOSTNAME)
					if [[ "$TELEGRAM_NOTIFICATIONS" =~ $TELEGRAM_NOTIFY_FAILURE ]]; then
						sendTelegramm "${EMOJI_FAILED} <b><u> $msg </u></b>"		# add warning icon to message
						sendTelegrammLogMessages
					fi
				fi
				if [[ -n "$PUSHOVER_TOKEN" ]]; then
					msg=$(getMessage $MSG_TITLE_ERROR $HOSTNAME)
					if [[ "$PUSHOVER_NOTIFICATIONS" =~ $PUSHOVER_NOTIFY_FAILURE_NOTIFY_FAILURE ]]; then
						sendPushover "${EMOJI_FAILED} $msg" 1		# add warning icon to message
					fi
				fi
				if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
					msg=$(getMessage $MSG_TITLE_ERROR $HOSTNAME)
					if [[ "$SLACK_NOTIFICATIONS" =~ $SLACK_NOTIFY_FAILURE_NOTIFY_FAILURE ]]; then
						sendSlack "$msg" 1		# add warning icon to message
					fi
				fi
			fi #  ! RESTORE
		fi

	else 	# success

		if (( $RESTORE )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_OK
		else
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_OK
		fi

		writeToConsole $MSG_LEVEL_MINIMAL $MSG_STOPPED "$HOSTNAME" "$MYSELF" "$VERSION" "$GIT_DATE_ONLY" "$GIT_COMMIT_ONLY" "$(date)" "$rc"
		logger -t $MYNAME "Stopped $VERSION ($GIT_COMMIT_ONLY). rc $rc"

		if (( ! $RESTORE )); then
			if [[ -n "$TELEGRAM_TOKEN"  ]]; then
				msg=$(getMessage $MSG_TITLE_OK $HOSTNAME)
				if [[ "$TELEGRAM_NOTIFICATIONS" =~ $TELEGRAM_NOTIFY_SUCCESS ]]; then
					sendTelegramm "${EMOJI_OK} $msg"
					sendTelegrammLogMessages
				fi
			fi
			if [[ -n "$PUSHOVER_TOKEN"  ]]; then
				msg=$(getMessage $MSG_TITLE_OK $HOSTNAME)
				if [[ "$PUSHOVER_NOTIFICATIONS" =~ $PUSHOVER_NOTIFY_SUCCESS ]]; then
					sendPushover "${EMOJI_OK} $msg" 0
				fi
			fi
			if [[ -n "$SLACK_WEBHOOK_URL"  ]]; then
				msg=$(getMessage $MSG_TITLE_OK $HOSTNAME)
				if [[ "$SLACK_NOTIFICATIONS" =~ $SLACK_NOTIFY_SUCCESS ]]; then
					sendSlack "${EMOJI_OK} $msg" 0
				fi
			fi

			msg=$(getMessage $MSG_TITLE_OK $HOSTNAME)
			sendEMail "" "$msg"

		fi # ! $RESTORE
	fi

	if (( $LOG_LEVEL == $LOG_DEBUG )); then
		masqueradeSensitiveInfoInLog # and now masquerade sensitive details in log file
	fi

	logFinish

	saveVars

	callNotificationExtension $rc

	logExit

	unLockMe

	if [[ -n "$DYNAMIC_MOUNT" ]] && (( $DYNAMIC_MOUNT_EXECUTED )); then
		writeToConsole $MSG_LEVEL_DETAILED $MSG_DYNAMIC_UMOUNT_SCHEDULED "$DYNAMIC_MOUNT"
		umount -l $DYNAMIC_MOUNT &>>$LOG_FILE
	fi

	if (( ! $RESTORE && $REBOOT_SYSTEM )); then
		shutdown -r +3						# wait some time to allow eMail to be sent
	fi

	exit $rc
}

function cleanupRestore() { # trap

	logEntry

	local error=0

	logItem "Got trap $1"
	logItem "rc: $rc"

	rm $MODIFIED_SFDISK &>/dev/null

	if (( $PRE_RESTORE_EXTENSION_CALLED )); then
		callExtensions $POST_RESTORE_EXTENSION $rc
	fi

	if [[ -n $MNT_POINT ]]; then
		if isMounted $MNT_POINT; then
			logItem "Umount $MNT_POINT"
			umount $MNT_POINT &>>"$LOG_FILE"
		fi

		logItem "Deleting dir $MNT_POINT"
		rmdir $MNT_POINT &>>"$LOG_FILE"
	fi

	if (( ! $PARTITIONBASED_BACKUP )); then
		if isMounted $BOOT_PARTITION; then
			umount $BOOT_PARTITION &>>"$LOG_FILE"
		fi
		if isMounted $ROOT_PARTITION; then
			umount $ROOT_PARTITION &>>"$LOG_FILE"
		fi
	fi

	logExit "$rc"

}

function revertScriptVersion() {

	logEntry

	local existingVersionFiles=( $(ls $SCRIPT_DIR/$MYNAME.*sh) )

	if [[ ! -e "$SCRIPT_DIR/$MYSELF" ]]; then
		assertionFailed $LINENO "$SCRIPT_DIR/$MYSELF not found"
	fi

	local currentVersion="$(extractVersionFromFile "$SCRIPT_DIR/$MYSELF" "$VERSION_VARNAME")"
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_CURRENT_SCRIPT_VERSION "$currentVersion"

	declare -A versionsOfFiles

	local version
	for versionFile in "${existingVersionFiles[@]}"; do
		version="$(extractVersionFromFile "$versionFile" "$VERSION_VARNAME" )"
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

	if (( $PRE_BACKUP_EXTENSION_CALLED )); then
		callExtensions $POST_BACKUP_EXTENSION $rc
	fi

	startServices "noexit"
	executeAfterStartServices "noexit"

	cleanupBackupDirectory

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

function checkImportantParameters() {

	local ll lla pll org

	org="$LOG_LEVEL"
	ll="${LOG_LEVEL^^}"
	pll="^${POSSIBLE_LOG_LEVELs^^}\$"
	if [[ "$ll" =~ $pll ]]; then
		lla="$(tr '[:lower:]' '[:upper:]'<<< ${LOG_LEVEL_ARGs[$ll]+abc})"
		if [[ "$lla" == "ABC" ]]; then
			LOG_LEVEL=${LOG_LEVEL_ARGs[$ll]}
		else
			LOG_LEVEL=$LOG_DEBUG
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_INVALID_LOG_LEVEL "$org"
			exitError $RC_PARAMETER_ERROR
		fi
	fi
	if [[ ! "$LOG_LEVEL" =~ $POSSIBLE_LOG_LEVEL_NUMBERs ]]; then
		LOG_LEVEL=$LOG_DEBUG
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_INVALID_LOG_LEVEL "$org"
		exitError $RC_PARAMETER_ERROR
	fi

	local ml mla mll

	org="$MSG_LEVEL"
	ml="${MSG_LEVEL^^}"
	mll="^${POSSIBLE_MSG_LEVELs^^}\$"
	if [[ "$ml" =~ $mll ]]; then
		mla="$(tr '[:lower:]' '[:upper:]'<<< ${MSG_LEVEL_ARGs[$ml]+abc})"
		if [[ "$mla" == "ABC" ]]; then
			MSG_LEVEL=${MSG_LEVEL_ARGs[$ml]}
		else
			MSG_LEVEL=$MSG_LEVEL_DETAILED
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_INVALID_MSG_LEVEL "$org"
			exitError $RC_PARAMETER_ERROR
		fi
	fi
	if [[ ! "$MSG_LEVEL" =~ $POSSIBLE_MSG_LEVEL_NUMBERs ]]; then
		MSG_LEVEL=$MSG_LEVEL_DETAILED
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_INVALID_MSG_LEVEL "$org"
		exitError $RC_PARAMETER_ERROR
	fi

	local lo loa plo

	lo="${LOG_OUTPUT^^}"
	plo="^${POSSIBLE_LOG_OUTPUTs^^}\$"
	if [[ "$lo" =~ $plo ]]; then
		loa="$(tr '[:lower:]' '[:upper:]'<<< ${LOG_OUTPUT_ARGs[$lo]+abc})"
		if [[ "$loa" == "ABC" ]]; then
			LOG_OUTPUT=${LOG_OUTPUT_ARGs[$lo]}
			logItem "LOG_OUTPUT=$LOG_OUTPUT"
		fi
	fi

	if [[ ! "$LOG_OUTPUT" =~ $POSSIBLE_LOG_OUTPUT_NUMBERs ]]; then
		if [[ ${LOG_OUTPUT:0:1} != "/" ]]; then
			LOG_OUTPUT="$CURRENT_DIR/$LOG_OUTPUT"
			logItem "LOG_OUTPUT=$LOG_OUTPUT"
		fi

		if ! touch "$LOG_OUTPUT" &>/dev/null; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNABLE_TO_CREATE_FILE "$LOG_OUTPUT"
			LOG_OUTPUT=$LOG_OUTPUT_HOME
			logItem "LOG_OUTPUT=$LOG_OUTPUT"
			exitError $RC_PARAMETER_ERROR
		fi
	fi

	if ! containsElement "${LANGUAGE}" "${SUPPORTED_LANGUAGES[@]}"; then
		local l=$LANGUAGE
		LANGUAGE=$FALLBACK_LANGUAGE
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_LANGUAGE_NOT_SUPPORTED "$l"
	fi

}

function createLinks() { # backuptargetroot extension newfile

	logEntry "$1 $2 $3"
	local file rc

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
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_HARDLINK_ERROR "$1" "$rc"
			exitError $RC_LINK_FILE_FAILED
		fi
		local links="$(stat -c %h -- "$3")"
		if (( links < 2 )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_HARDLINK_ERROR "$1" "$rc"
			exitError $RC_LINK_FILE_FAILED
		fi
	fi

	logExit
}

function bootPartitionBackup() {

		logEntry

		local p rc

		logItem "Starting boot partition backup..."

		if (( ! $FAKE && ! $EXCLUDE_DD && ! $SHARED_BOOT_DIRECTORY )); then
			local ext=$BOOT_DD_EXT
			(( $TAR_BOOT_PARTITION_ENABLED )) && ext=$BOOT_TAR_EXT
			if  [[ ! -e "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.$ext" ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_CREATING_BOOT_BACKUP "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.$ext"
				if (( $TAR_BOOT_PARTITION_ENABLED )); then
					local bootMountpoint
					[[ -d /boot/firmware ]] && bootMountpoint="/boot/firmware" || bootMountpoint="/boot"
					local cmd="cd $bootMountpoint; tar $TAR_BACKUP_OPTIONS -f \"$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.$ext\" ."
					executeTar "$cmd"
				else
					local cmd="dd if=/dev/${BOOT_PARTITION_PREFIX}1 of=\"$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.$ext\" bs=$DD_BLOCKSIZE"
					executeDD "$cmd"
				fi
				rc=$?
				if [ $rc != 0 ]; then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_IMG_BOOT_BACKUP_FAILED "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.$ext" "$rc"
					exitError $RC_DD_IMG_FAILED
				fi

				if (( ! $TAR_BOOT_PARTITION_ENABLED )); then
					local loopDev
					loopDev="$(losetup -f)"
					logItem "Loop device: $loopDev"
					losetup -P $loopDev $BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.$ext &>>$LOG_FILE
					rc=$?
					logItem "losetup rc: $rc"
					if (( $rc != 0 )); then
						losetup -d $loopDev &>>$LOG_FILE
						logItem "Mount of boot partition backup file failed with rc $rc" # silently ignore losetup error
					else
						writeToConsole $MSG_LEVEL_DETAILED $MSG_IMG_BOOT_CHECK_STARTED
						fsck -fp $loopDev &>>$LOG_FILE
						rc=$?
						logItem "fsck rc: $rc"
						losetup -d $loopDev &>>$LOG_FILE
						if (( $rc > 1 )); then
							writeToConsole $MSG_LEVEL_MINIMAL $MSG_IMG_BOOT_FSCHECK_FAILED "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.$ext" "$rc"
							exitError $RC_DD_IMG_FAILED
						fi
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
				local stripMultiple
				if (( $IGNORE_ADDITIONAL_PARTITIONS )); then
					logItem "Stripping partitions > 2"
					stripMultiple='| grep -v -E "[3-9] :"'
				fi
				eval "sfdisk -d $BOOT_DEVICENAME $stripMultiple" > "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.sfdisk" 2>>$LOG_FILE
				local rc=$?
				if [ $rc != 0 ]; then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNABLE_TO_COLLECT_PARTITIONINFO "sfdisk" "$rc"
					exitError $RC_COLLECT_PARTITIONS_FAILED
				fi
				logCommand "cat $BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.sfdisk"

				if (( $LINK_BOOTPARTITIONFILES )); then
					createLinks "$BACKUPTARGET_ROOT" "sfdisk" "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.sfdisk"
				fi
			else
				logItem "Found existing backup of partition layout $BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.sfdisk ..."
				writeToConsole $MSG_LEVEL_DETAILED $MSG_EXISTING_PARTITION_BACKUP "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.sfdisk"
			fi

			if  [[ ! -e "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.mbr" ]]; then
				writeToConsole $MSG_LEVEL_DETAILED $MSG_CREATING_MBR_BACKUP "$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.mbr"
				cmd="dd if=$BOOT_DEVICENAME of=\"$BACKUPTARGET_DIR/$BACKUPFILES_PARTITION_DATE.mbr\" bs=512 count=1"
				executeDD "$cmd"
				local rc=$?
				if [ $rc != 0 ]; then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_IMG_DD_FAILED ".mbr" "$rc"
					exitError $RC_COLLECT_PARTITIONS_FAILED
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
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNABLE_TO_COLLECT_PARTITIONINFO "sfdisk" "$rc"
			exitError $RC_COLLECT_PARTITIONS_FAILED
		fi
		logItem "sfdisk"
		logItem "$(<"$SF_FILE")"

		writeToConsole $MSG_LEVEL_DETAILED $MSG_CREATING_PARTITION_BACKUP "$BLKID_FILE"
		logItem "Saving blkid"
		blkid > "$BLKID_FILE"
		local rc=$?
		if [ $rc != 0 ]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNABLE_TO_COLLECT_PARTITIONINFO "blkid" "$rc"
			exitError $RC_COLLECT_PARTITIONS_FAILED
		fi
		logItem "blkid"
		logItem "$(<"$BLKID_FILE")"

		writeToConsole $MSG_LEVEL_DETAILED $MSG_CREATING_PARTITION_BACKUP "$PARTED_FILE"
		logItem "Saving parted"
		parted -m $BOOT_DEVICENAME print > "$PARTED_FILE"
		local rc=$?
		if [ $rc != 0 ]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNABLE_TO_COLLECT_PARTITIONINFO "parted" "$rc"
			exitError $RC_COLLECT_PARTITIONS_FAILED
		fi
		logItem "parted"
		logItem "$(<"$PARTED_FILE")"

		writeToConsole $MSG_LEVEL_DETAILED $MSG_CREATING_PARTITION_BACKUP "$FDISK_FILE"
		logItem "Saving fdisk"
		fdisk -l $BOOT_DEVICENAME > "$FDISK_FILE"
		local rc=$?
		if [ $rc != 0 ] ; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNABLE_TO_COLLECT_PARTITIONINFO "fdisk" "$rc"
			exitError $RC_COLLECT_PARTITIONS_FAILED
		fi
		logItem "fdisk"
		logItem "$(<"$FDISK_FILE")"

		writeToConsole $MSG_LEVEL_DETAILED $MSG_CREATING_MBR_BACKUP "$MBR_FILE"
		cmd="dd if=$BOOT_DEVICENAME of="$MBR_FILE" bs=512 count=1"
		executeDD "$cmd"
		rc=$?
		if [ $rc != 0 ]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_IMG_DD_FAILED ".mbr" "$rc"
			exitError $RC_COLLECT_PARTITIONS_FAILED
		fi

		logExit

}

function backupDD() {

	logEntry

	local cmd verbose partition

	(( $VERBOSE )) && verbose="-v" || verbose=""

	local progressFlag=""
	(( $PROGRESS && $INTERACTIVE )) && progressFlag="status=progress"

	if (( $PARTITIONBASED_BACKUP )); then

		partition="${BOOT_DEVICENAME}p$1"
		partitionName="${BOOT_PARTITION_PREFIX}$1"

		if [[ $BACKUPTYPE == $BACKUPTYPE_DDZ ]]; then
			cmd="dd if=$partition bs=$DD_BLOCKSIZE $progressFlag $DD_PARMS | gzip ${verbose} > \"${BACKUPTARGET_DIR}/$partitionName${FILE_EXTENSION[$BACKUPTYPE]}\""
		else
			cmd="dd if=$partition bs=$DD_BLOCKSIZE $progressFlag $DD_PARMS of=\"${BACKUPTARGET_DIR}/$partitionName${FILE_EXTENSION[$BACKUPTYPE]}\""
		fi

	else

		if (( ! $DD_BACKUP_SAVE_USED_PARTITIONS_ONLY )); then
			if [[ $BACKUPTYPE == $BACKUPTYPE_DDZ ]]; then
				cmd="dd if=$BOOT_DEVICENAME bs=$DD_BLOCKSIZE $progressFlag $DD_PARMS | gzip ${verbose} > \"$BACKUPTARGET_FILE\""
			else
				cmd="dd if=$BOOT_DEVICENAME bs=$DD_BLOCKSIZE $progressFlag $DD_PARMS of=\"$BACKUPTARGET_FILE\""
			fi
		else
			logCommand "fdisk -l $BOOT_DEVICENAME"
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
				if (( $PROGRESS && $INTERACTIVE )); then
					cmd="dd if=$BOOT_DEVICENAME bs=$blocksize count=$count | pv -fs $(fdisk -l $BOOT_DEVICENAME | grep Disk.*$BOOT_DEVICENAME | cut -d ' ' -f 5) | gzip ${verbose} > \"$BACKUPTARGET_FILE\""
				else
					cmd="dd if=$BOOT_DEVICENAME bs=$blocksize count=$count | gzip ${verbose} > \"$BACKUPTARGET_FILE\""
				fi
			else
				if (( $PROGRESS && $INTERACTIVE )); then
					cmd="dd if=$BOOT_DEVICENAME bs=$blocksize count=$count | pv -fs $(fdisk -l $BOOT_DEVICENAME | grep Disk.*$BOOT_DEVICENAME | cut -d ' ' -f 5) | dd of=\"$BACKUPTARGET_FILE\""
				else
					cmd="dd if=$BOOT_DEVICENAME bs=$blocksize count=$count of=\"$BACKUPTARGET_FILE\""
				fi
			fi

		fi
	fi

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_STARTED "$BACKUPTYPE"

	if (( ! $EXCLUDE_DD )); then
		if (( ! $FAKE)); then
			executeDD "$cmd"
			rc=$?
		else
			rc=0
		fi
	fi

	logExit  "$rc"

	return $rc
}

function backupTar() {

	local verbose zip cmd partition source target devroot sourceDir

	logEntry

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
		--exclude=\"$devroot/$log_file\" \
		--exclude=\"$devroot/$msg_file\" \
		--exclude='.gvfs' \
		--exclude=$devroot/proc/* \
		--exclude=$devroot/lost+found/* \
		--exclude=$devroot/sys/* \
		--exclude=$devroot/dev/* \
		--exclude=$devroot/tmp/* \
		--exclude=$devroot/swapfile \
		--exclude=$devroot/run/* \
		--exclude=$devroot/media/* \
		$EXCLUDE_LIST \
		$source"

	if (( $PARTITIONBASED_BACKUP )); then
		if ! pushd $sourceDir &>>$LOG_FILE; then
				assertionFailed $LINENO "push to $sourceDir failed"
		fi
	fi

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_STARTED "$BACKUPTYPE"

	if (( ! $FAKE )); then
		executeTar "${cmd}" "$TAR_IGNORE_ERRORS"
		rc=$?
	fi

	if (( $PARTITIONBASED_BACKUP )); then
		if ! popd &>>$LOG_FILE; then
			assertionFailed $LINENO "pop failed"
		fi
	fi

	logExit  "$rc"

	return $rc
}


function waitForPartitionDefsChanged {
	logEntry
	sync
	sleep 3
	logItem "--- partprobe ---"
	partprobe -s &>>$LOG_FILE
	sleep 3
	logItem "--- udevadm ---"
	udevadm settle &>>$LOG_FILE
	logExit
}

function updateUUIDs() {
	logEntry
	if (( $UPDATE_UUIDS )); then
		logItem "Old blkid"
		logCommand "blkid"
		updatePartUUID
		updateUUID
		logItem "blkid after UUID update${NL}$(blkid)"
	fi
	logExit
}

function updatePartUUID() {
	logEntry
	if (( $UPDATE_UUIDS )); then
		local newUUID=$(od -A n -t x -N 4 /dev/urandom | tr -d " ")
		writeToConsole $MSG_LEVEL_DETAILED $MSG_CREATING_UUID "PARTUUID" "$newUUID" "$RESTORE_DEVICE"
		echo -ne "x\ni\n0x$newUUID\nr\nw\nq\n" | fdisk "$RESTORE_DEVICE" &>> "$LOG_FILE"
		waitForPartitionDefsChanged
	fi
	logExit
}

function updateUUID() {
	logEntry
	if (( $UPDATE_UUIDS )); then
		local newUUID
		if (( ! $SHARED_BOOT_DIRECTORY )); then
			newUUID="$(od -A n -t x -N 4 /dev/urandom | tr -d " " | sed -r 's/(.{4})/\1-/')"
			newUUID="${newUUID^^*}"
			writeToConsole $MSG_LEVEL_DETAILED $MSG_CREATING_UUID "UUID" "$newUUID" "$BOOT_PARTITION"
			printf "\x${newUUID:7:2}\x${newUUID:5:2}\x${newUUID:2:2}\x${newUUID:0:2}" \
				| dd bs=1 seek=67 count=4 conv=notrunc of=$BOOT_PARTITION &>>"$LOG_FILE" # 39 for fat16, 67 for fat32
			waitForPartitionDefsChanged
		fi
		newUUID="$(</proc/sys/kernel/random/uuid)"
		writeToConsole $MSG_LEVEL_DETAILED $MSG_CREATING_UUID "UUID" "$newUUID" "$ROOT_PARTITION"
		e2fsck -y -f $ROOT_PARTITION &>> "$LOG_FILE"
		tune2fs -U "$newUUID" $ROOT_PARTITION &>>"$LOG_FILE"
		waitForPartitionDefsChanged
	fi
	logExit
}

function backupRsync() { # partition number (for partition based backup)

	local verbose partition target source excludeRoot cmd cmdParms excludeMeta

	logEntry

	(( $PROGRESS )) && VERBOSE=0

	verbose="--info=NAME0"
	(( $VERBOSE )) && verbose="-v"

	logCommand "ls $BACKUPTARGET_ROOT"

	if (( $PARTITIONBASED_BACKUP )); then
		partition="${BOOT_PARTITION_PREFIX}$1"
		target="\"${BACKUPTARGET_DIR}\""
		source="$TEMPORARY_MOUNTPOINT_ROOT/$partition"

		lastBackupDir=$(find "$BACKUPTARGET_ROOT" -maxdepth 1 -type d -name "*-$BACKUPTYPE-*" ! -name $BACKUPFILE 2>>/dev/null | sort | tail -n 1)
		excludeRoot="/$partition"

	else
		target="\"${BACKUPTARGET_DIR}\""
		source="/"

		bootPartitionBackup
		lastBackupDir=$(find "$BACKUPTARGET_ROOT" -maxdepth 1 -type d -name "*-$BACKUPTYPE-*" ! -name $BACKUPFILE 2>>/dev/null | sort | tail -n 1)
		excludeRoot=""
		excludeMeta="--exclude=/$BACKUPFILES_PARTITION_DATE.img --exclude=/$BACKUPFILES_PARTITION_DATE.tmg --exclude=/$BACKUPFILES_PARTITION_DATE.sfdisk --exclude=/$BACKUPFILES_PARTITION_DATE.blkid --exclude=/$BACKUPFILES_PARTITION_DATE.fdisk --exclude=/$BACKUPFILES_PARTITION_DATE.parted --exclude=/$BACKUPFILES_PARTITION_DATE.mbr --exclude=/$MYNAME.log --exclude=/$MYNAME.msg"
	fi

	logItem "LastBackupDir: $lastBackupDir"

	LINK_DEST=""
	[[ -n "$lastBackupDir" ]] && LINK_DEST="--link-dest=\"$lastBackupDir\""

	logItem "LinkDest: $LINK_DEST"

	if [[ -n $LINK_DEST ]]; then
		writeToConsole $MSG_LEVEL_DETAILED $MSG_HARDLINK_DIRECTORY_USED "$lastBackupDir"
	fi

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_MAIN_BACKUP_PROGRESSING $BACKUPTYPE "${target//\\/}"

	local log_file="${LOG_FILE/\//}" # remove leading /
	local msg_file="${MSG_FILE/\//}" # remove leading /

	# bullseye enabled persistent journaling which has ACLs and are not supported via nfs
	local fs="$(getFsType "$BACKUPPATH")"
	if [[ ( -e $PERSISTENT_JOURNAL || -e $PERSISTENT_JOURNAL_LOG2RAM ) && $fs =~ ^nfs* ]]; then
		logItem "Excluding $PERSISTENT_JOURNAL and $PERSISTENT_JOURNAL_LOG2RAM for nfs"
		EXCLUDE_LIST+=" --exclude ${excludeRoot}${PERSISTENT_JOURNAL} --exclude ${excludeRoot}${PERSISTENT_JOURNAL_LOG2RAM}"
	fi

	cmdParms="--exclude=\"$BACKUPPATH_PARAMETER/*\" \
			--exclude=\"$excludeRoot/$log_file\" \
			--exclude=\"$excludeRoot/$msg_file\" \
			--exclude='.gvfs' \
			--exclude=$excludeRoot/proc/* \
			--exclude=$excludeRoot/lost+found/* \
			--exclude=$excludeRoot/sys/* \
			--exclude=$excludeRoot/dev/* \
			--exclude=$excludeRoot/swapfile \
			--exclude=$excludeRoot/tmp/* \
			--exclude=$excludeRoot/run/* \
			--exclude=$excludeRoot/media/* \
			$excludeMeta \
			$EXCLUDE_LIST \
			$LINK_DEST \
			--numeric-ids \
			$RSYNC_BACKUP_OPTIONS \
			$RSYNC_BACKUP_ADDITIONAL_OPTIONS \
			$verbose \
			$source \
			$target \
			"

	if (( $PROGRESS && $INTERACTIVE )); then
		cmd="rsync --info=progress2 $cmdParms"
	else
		cmd="rsync $cmdParms"
	fi

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_STARTED "$BACKUPTYPE"

	if (( ! $FAKE )); then
		executeRsync "$cmd" "$RSYNC_IGNORE_ERRORS"
		rc=$?
	fi

	logExit  "$rc"

}

function areDevicesUnique() {

	logEntry

	local -A UUID
	local -A PARTUUID
	local line
	local unique=0

	local uuid uuidsub partuuid

	logCommand "blkid -o udev"

	while read line; do

		if grep -q ID_FS_UUID= <<< "$line"; then
			uuid="$(cut -f2 -d= <<< "$line")"
		fi
		if grep -q ID_FS_UUID_SUB= <<< "$line"; then
			uuidsub="$(cut -f2 -d= <<< "$line")"
			uuid="${uuid}_${uuidsub}"
		fi
		if grep -q ID_FS_PARTUUID= <<< "$line"; then
			partuuid="$(cut -f2 -d= <<< "$line")"
			if [[ ${PARTUUID[$partuuid]}+abc != "+abc" ]]; then
				logItem "PARTUUID $partuuid is not unique"
				unique=1
			else
				PARTUUID[$partuuid]=1
			fi
		fi

		if [[ -z "$line" ]]; then								# groups are separated by empty lines thus one group parsed now
			if [[ -n $uuid ]]; then
				if [[ ${UUID[$uuid]}+abc != "+abc" ]]; then
					logItem "UUID $uuid is not unique"
					unique=1
				else
					UUID[$uuid]=1
				fi
			fi
			uuid=""
			uuidsub=""
		fi

	done < <(blkid -o udev)

	if [[ -n $uuid && ${UUID[$uuid]}+abc != "+abc" ]]; then # check last group in output with no trailing empty line
		logItem "UUID $uuid is not unique"
		unique=1
	fi

	logExit $unique
	return $unique

}

function logSystemDiskState() {
	logEntry
	logCommand "blkid"
	logCommand "fdisk -l"
	logCommand "mount"
	logCommand "df -h -l"
	logExit
}

function restore() {

	logEntry

	rc=0
	local verbose zip

	(( $VERBOSE )) && verbose="-v" || verbose=""

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORING_FILE "$RESTOREFILE"
	logCommand "ls -la $RESTOREFILE"

	rc=$RC_NATIVE_RESTORE_FAILED

	logSystemDiskState

	callExtensions $PRE_RESTORE_EXTENSION "0"
	rc=$?
	PRE_RESTORE_EXTENSION_CALLED=1
	if (( $rc )); then
		exitError $RC_RESTORE_EXTENSION_FAILS
	fi

	case $BACKUPTYPE in

		$BACKUPTYPE_DD|$BACKUPTYPE_DDZ)

			local progressFlag=""
			(( $PROGRESS && $INTERACTIVE )) && progressFlag="status=progress"

			if [[ $BACKUPTYPE == $BACKUPTYPE_DD ]]; then
				cmd="dd if=\"$ROOT_RESTOREFILE\" $progressFlag of=$RESTORE_DEVICE bs=$DD_BLOCKSIZE $DD_PARMS"
			else
				cmd="gunzip -c \"$ROOT_RESTOREFILE\" | dd of=$RESTORE_DEVICE $progressFlag bs=$DD_BLOCKSIZE $DD_PARMS"
			fi

			executeDD "$cmd"
			rc=$?

			if [[ $rc != 0 ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_PROGRAM_ERROR $BACKUPTYPE $rc
				exitError $RC_NATIVE_RESTORE_FAILED
			fi
			;;

		*)	MNT_POINT="$TEMPORARY_MOUNTPOINT_ROOT/${MYNAME}"

			if ( isMounted "$MNT_POINT" ); then
				logItem "$MNT_POINT mounted - unmouting"
				umount "$MNT_POINT" &>> "$LOG_FILE"
			else
				logItem "$MNT_POINT not mounted"
			fi

			logItem "Creating mountpoint $MNT_POINT"
			mkdir -p $MNT_POINT

			logItem "Umounting boot partition $BOOT_PARTITION"
			umount $BOOT_PARTITION &>>"$LOG_FILE"
			rc=$?
			if (( ! $rc )); then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_UMOUNT_ERROR "BOOT_PARTITION" "$rc"
				exitError $RC_MISC_ERROR
			fi
			logItem "Umounting root partition $ROOT_PARTITION"
			umount $ROOT_PARTITION &>>"$LOG_FILE"
			rc=$?
			if (( ! $rc )); then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_UMOUNT_ERROR "ROOT_PARTITION" "$rc"
				exitError $RC_MISC_ERROR
			fi

			if (( $FORCE_SFDISK )); then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_FORCING_CREATING_PARTITIONS
				sfdisk -f "$RESTORE_DEVICE" < "$SF_FILE" &>>"$LOG_FILE"
				rc=$?
				if (( $rc )); then
					if (( $rc == 1 )); then
						local tmpSF="$(basename $SF_FILE)"
						cp "$SF_FILE" "/tmp/$tmpSF"
						sed -i 's/sector-size/d' "/tmp/$tmpSF"
						sfdisk -f "$RESTORE_DEVICE" < "/tmp/$tmpSF" &>>"$LOG_FILE"
						rc=$?
						rm "/tmp/$tmpSF"
					fi
				fi
				if (( $rc )); then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNABLE_TO_CREATE_PARTITIONS $rc "sfdisk error"
					exitError $RC_CREATE_PARTITIONS_FAILED
				fi

				waitForPartitionDefsChanged

			elif (( $SKIP_SFDISK )); then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_SKIP_CREATING_PARTITIONS

			else
				writeToConsole $MSG_LEVEL_DETAILED $MSG_CREATING_PARTITIONS "$RESTORE_DEVICE"

				cp "$SF_FILE" $MODIFIED_SFDISK
				logItem "Current sfdisk file"
				logCommand "cat $MODIFIED_SFDISK"

				if (( ! $ROOT_PARTITION_DEFINED )) && (( $RESIZE_ROOTFS )) && (( ! $PARTITIONBASED_BACKUP )); then
					local sourceSDSize=$(calcSumSizeFromSFDISK "$SF_FILE")
					local targetSDSize=$(blockdev --getsize64 $RESTORE_DEVICE)
					logItem "sourceSDSize: $sourceSDSize - targetSDSize: $targetSDSize"

					if (( sourceSDSize != targetSDSize )); then

#						label: dos
#						label-id: 0x3c3f4bdb
#						device: /dev/mmcblk0
#						unit: sectors
#						sector-size: 512
#
#						/dev/mmcblk0p1 : start=        8192, size=      524288, type=c
#						/dev/mmcblk0p2 : start=      532480, size=    15196160, type=83

						local sourceValues=( $(awk '/(1|2) :/ { v=$4 $6; gsub(","," ",v); printf "%s",v }' "$SF_FILE") )
						if [[ ${#sourceValues[@]} != 4 ]]; then
							logCommand "cat $SF_FILE"
							assertionFailed $LINENO "Expected at least 2 partitions in $SF_FILE"
						fi

						# Backup partition has only one partition -> external root partition -> -R has to be specified
						if (( ${sourceValues[2]} == 0 )) || (( ${sourceValues[3]} == 0 )); then
							writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_R_OPTION
							exitError $RC_MISC_ERROR
						fi

						local adjustedTargetPartitionBlockSize=$(( $targetSDSize / 512 - ${sourceValues[1]} - ${sourceValues[0]} - ( ${sourceValues[2]} - ${sourceValues[1]} ) ))
						logItem "sourceSDSize: $sourceSDSize - targetSDSize: $targetSDSize"
						logItem "sourceBlockSize: ${sourceValues[3]} - adjusted targetBlockSize: $adjustedTargetPartitionBlockSize"

						local newTargetPartitionSize=$(( adjustedTargetPartitionBlockSize * 512 ))
						local oldPartitionSourceSize=$(( ${sourceValues[3]} * 512 ))

						sed -i "/2 :/ s/${sourceValues[3]}/$adjustedTargetPartitionBlockSize/" $MODIFIED_SFDISK

						logItem "Updated sfdisk file"
						logCommand "cat $MODIFIED_SFDISK"

						if [[ "$(bytesToHuman $oldPartitionSourceSize)" != "$(bytesToHuman $newTargetPartitionSize)" ]]; then
							writeToConsole $MSG_LEVEL_MINIMAL $MSG_ADJUSTING_SECOND "$(bytesToHuman $oldPartitionSourceSize)" "$(bytesToHuman $newTargetPartitionSize)"
						fi

					fi
				fi

				sfdisk -f $RESTORE_DEVICE < "$MODIFIED_SFDISK" &>>"$LOG_FILE"
				rc=$?
				if (( $rc )); then
					logItem "sfdisk first attempt fails with rc $rc"
					if (( $rc == 1 )); then								# sector-size is new in bullseye and breaks restore with older OS
						sed -i '/sector-size/d' "$MODIFIED_SFDISK"		# remove sector-size
						logCommand "cat $MODIFIED_SFDISK"
						sfdisk -f $RESTORE_DEVICE < "$MODIFIED_SFDISK" &>>"$LOG_FILE"
						rc=$?
					fi
				fi
				rm $MODIFIED_SFDISK &>/dev/null

				if (( $rc )); then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNABLE_TO_CREATE_PARTITIONS $rc "sfdisk error"
					exitError $RC_CREATE_PARTITIONS_FAILED
				fi

				waitForPartitionDefsChanged

			fi

			logItem "Targetpartitionlayout$NL$(fdisk -l $RESTORE_DEVICE)"

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
				local progressFlag=""
				(( $PROGRESS && $INTERACTIVE )) && progressFlag="status=progress"
				local cmd="dd if="$DD_FILE" $progressFlag of=$BOOT_PARTITION bs=$DD_BLOCKSIZE"
				executeDD "$cmd"
				rc=$?
			else
				ext=$BOOT_TAR_EXT
				logItem "Restoring boot partition from $TAR_FILE to $BOOT_PARTITION"
				mountAndCheck $BOOT_PARTITION "$MNT_POINT"
				if ! pushd "$MNT_POINT" &>>"$LOG_FILE"; then
					assertionFailed $LINENO "push to $MNT_POINT failed"
				fi
				if (( $PROGRESS && $INTERACTIVE )); then
					local cmd="pv -f $TAR_FILE | tar -xf -"
				else
					local cmd="tar -xf  \"$TAR_FILE\""
				fi
				executeTar "$cmd"
				rc=$?
				popd &>>"$LOG_FILE"
			fi

			if [ $rc != 0 ]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_IMG_BOOT_RESTORE_FAILED ".$ext" "$rc"
				exitError $RC_NATIVE_RESTORE_FAILED
			fi

			writeToConsole $MSG_LEVEL_DETAILED $MSG_FORMATTING_SECOND_PARTITION "$ROOT_PARTITION"
			local check=""
			(( $REGRESSION_TEST )) && check="-F "
			if (( $CHECK_FOR_BAD_BLOCKS )); then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_DETAILED_ROOT_CHECKING "$ROOT_PARTITION"
				check="-c"
				mkfs.ext4 $check $ROOT_PARTITION
			else
				mkfs.ext4 $check $ROOT_PARTITION &>>$LOG_FILE
			fi
			rc=$?
			if (( $rc != 0 )); then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_IMG_ROOT_CREATE_PARTITION_FAILED "$rc"
				exitError $RC_NATIVE_RESTORE_FAILED
			fi

			waitForPartitionDefsChanged

			writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORING_SECOND_PARTITION "$ROOT_PARTITION"
			mountAndCheck $ROOT_PARTITION "$MNT_POINT"

			case $BACKUPTYPE in

				$BACKUPTYPE_TAR|$BACKUPTYPE_TGZ)
					local archiveFlags="--same-owner --same-permissions --numeric-owner ${TAR_RESTORE_ADDITIONAL_OPTIONS}"

					if ! pushd "$MNT_POINT" &>>"$LOG_FILE"; then
						assertionFailed $LINENO "push to $MNT_POINT failed"
					fi
					[[ $BACKUPTYPE == $BACKUPTYPE_TGZ ]] && zip="-z" || zip=""
					if (( $PROGRESS && $INTERACTIVE )); then
						local cmd="pv -f $ROOT_RESTOREFILE | tar ${archiveFlags} -x ${verbose} ${zip} -f -"
					else
						local cmd="tar ${archiveFlags} -x ${verbose} ${zip} -f \"$ROOT_RESTOREFILE\""
					fi
					executeTar "$cmd"
					rc=$?
					popd &>>"$LOG_FILE"
					;;

				$BACKUPTYPE_RSYNC)
					local excludePattern="--exclude=/$HOSTNAME-backup.*"
					logItem "Excluding excludePattern"
					local progressFlag=""
					(( $PROGRESS && $INTERACTIVE )) && progressFlag="--info=progress2"
					local cmd="rsync $progressFlag --numeric-ids ${RSYNC_BACKUP_OPTIONS}${verbose} ${RSYNC_BACKUP_ADDITIONAL_OPTIONS} $excludePattern \"$ROOT_RESTOREFILE/\" $MNT_POINT"
					executeRsync "$cmd"
					rc=$?
					;;

				*) assertionFailed $LINENO "Invalid backuptype $BACKUPTYPE"
					;;
			esac

			if [[ $rc != 0 ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_PROGRAM_ERROR $BACKUPTYPE $rc
				exitError $RC_NATIVE_RESTORE_FAILED
			fi

			umount $ROOT_PARTITION &>> "$LOG_FILE"

			updateUUIDs

			writeToConsole $MSG_LEVEL_DETAILED $MSG_IMG_ROOT_CHECK_STARTED
			fsck -fpv $ROOT_PARTITION &>>$LOG_FILE
			rc_fsck=$?
			logItem "fsck rc: $rc_fsck"
			if (( $rc_fsck > 1 )); then # 1: => Filesystem errors corrected
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_IMG_ROOT_CHECK_FAILED "$rc_fsck"
				exitError $RC_NATIVE_RESTORE_FAILED
			fi
			mountAndCheck $ROOT_PARTITION $MNT_POINT

			logItem "Updating hw clock"
			echo $(date -u +"%Y-%m-%d %T") > $MNT_POINT/etc/fake-hwclock.data

			#logItem "Force fsck on reboot"
			#touch $MNT_POINT/forcefsck

			logCommand "parted -s $RESTORE_DEVICE print"

			if [[ $RESTORE_DEVICE =~ "/dev/mmcblk[0-9]+" || $RESTORE_DEVICE =~ "/dev/loop[0-9]+" || $RESTORE_DEVICE =~ "/dev/nvme[0-9]+n[0-9]+" ]]; then
				ROOT_DEVICE=$(sed -E 's/p[0-9]+$//' <<< $ROOT_PARTITION)
			else
				ROOT_DEVICE=$(sed -E 's/[0-9]+$//' <<< $ROOT_PARTITION)
			fi

			if [[ $ROOT_DEVICE != $RESTORE_DEVICE ]]; then
				logCommand "parted -s $ROOT_DEVICE print"
			fi

	esac

	logItem "Syncing filesystems"
	sync

	if isMounted $MNT_POINT; then
		logItem "Umount $MNT_POINT"
		umount $MNT_POINT &>> "$LOG_FILE"
	fi

	logSystemDiskState

	logExit "$rc"

}

function applyBackupStrategy() {

	logEntry "$BACKUP_TARGETDIR"

	if (( $SMART_RECYCLE )); then

		local dir_to_delete dir_to_keep

		local p="${SMART_RECYCLE_PARMS[@]}"
		logItem "SR Parms: $p"
		SR_DAILY="${SMART_RECYCLE_PARMS[0]}"
		SR_WEEKLY="${SMART_RECYCLE_PARMS[1]}"
		SR_MONTHLY="${SMART_RECYCLE_PARMS[2]}"
		SR_YEARLY="${SMART_RECYCLE_PARMS[3]}"
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_SMART_APPLYING_BACKUP_STRATEGY $SR_DAILY $SR_WEEKLY $SR_MONTHLY $SR_YEARLY

		logCommand "ls -d $BACKUPPATH/*"

		local keptBackups="$(SR_listUniqueBackups $BACKUPTARGET_ROOT)"
		local numKeptBackups="$(countLines "$keptBackups")"
		logItem "Keptbackups $numKeptBackups: $keptBackups"

		local tobeDeletedBackups="$(SR_listBackupsToDelete "$BACKUPTARGET_ROOT")"
		local numTobeDeletedBackups="$(countLines "$tobeDeletedBackups")"
		logItem "TobeDeletedBackups $numTobeDeletedBackups: $tobeDeletedBackups"

		if [[ -n "$tobeDeletedBackups" ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_SMART_RECYCLE_FILES "$numTobeDeletedBackups" "$numKeptBackups"
			echo "$tobeDeletedBackups" | while read dir_to_delete; do
				logItem "Recycling $BACKUPTARGET_ROOT/${dir_to_delete}"
				if (( ! $SMART_RECYCLE_DRYRUN && ( ! $FAKE || $REGRESSION_TEST ) )); then
					writeToConsole $MSG_LEVEL_DETAILED $MSG_SMART_RECYCLE_FILE_DELETE "$BACKUPTARGET_ROOT/${dir_to_delete}"
					[[ -n $dir_to_delete ]] && rm -rf $BACKUPTARGET_ROOT/${dir_to_delete} # guard against whole backup dir deletion
				else
					[[ -n $dir_to_delete ]] && writeToConsole $MSG_LEVEL_MINIMAL $MSG_SMART_RECYCLE_FILE_WOULD_BE_DELETED "$BACKUPTARGET_ROOT/${dir_to_delete}"
				fi
			done
		else
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_SMART_RECYCLE_NO_FILES
		fi

		if (( $SMART_RECYCLE_DRYRUN || $FAKE )); then
			echo "$keptBackups" | while read dir_to_keep; do
				[[ -n $dir_to_keep ]] && writeToConsole $MSG_LEVEL_MINIMAL $MSG_SMART_RECYCLE_FILE_WOULD_BE_KEPT "$BACKUPTARGET_ROOT/${dir_to_keep}"
			done
		fi

	else

		local bt="${BACKUPTYPE^^}"
		local v="KEEPBACKUPS_${bt}"
		local keepOverwrite="${!v}"

		local keepBackups=$KEEPBACKUPS
		(( $keepOverwrite != 0 )) && keepBackups=$keepOverwrite

		if (( $keepBackups != -1 )); then
			logItem "Deleting oldest directory in $BACKUPPATH"
			logCommand "ls -d $BACKUPPATH/*"

			writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUPS_KEPT "$keepBackups" "$BACKUPTYPE"

			if (( ! $FAKE )); then
				writeToConsole $MSG_LEVEL_DETAILED $MSG_CLEANUP_BACKUP_VERSION "$BACKUPPATH"
				if ! pushd "$BACKUPPATH" &>>$LOG_FILE; then
					assertionFailed $LINENO "push to $BACKUPPATH failed"
				fi
				ls -d ${HOSTNAME}-${BACKUPTYPE}-backup-* 2>>$LOG_FILE| grep -vE "_" | head -n -$keepBackups | xargs -I {} rm -rf "{}" &>>"$LOG_FILE";
				if ! popd &>>$LOG_FILE; then
					assertionFailed $LINENO "pop failed"
				fi

				local rmRC=$?
				if (( $rmRC != 0 )); then
					logItem "rmRC: $rmRC"
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_CLEANUP_FAILED
					exitError $RC_CLEANUP_ERROR
				fi

				local regex="\-([0-9]{8}\-[0-9]{6})\.(img|mbr|sfdisk|log)$"
				local regexDD="\-dd\-backup\-([0-9]{8}\-[0-9]{6})\.img$"

				if ! pushd "$BACKUPPATH" 1>/dev/null; then
					assertionFailed $LINENO "push to $BACKUPPATH failed"
				fi

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
	logExit
}

function backup() {

	logEntry

	logSystemDiskState

	executeBeforeStopServices
	stopServices
	callExtensions $PRE_BACKUP_EXTENSION "0"
	rc=$?
	PRE_BACKUP_EXTENSION_CALLED=1
	if (( $rc )); then
		exitError $RC_BACKUP_EXTENSION_FAILS
	fi

	if [[ $BACKUPTYPE == $BACKUPTYPE_RSYNC || (( $PARTITIONBASED_BACKUP )) ]]; then
		writeToConsole $MSG_LEVEL_DETAILED $MSG_BACKUP_TARGET "$BACKUPTYPE" "$BACKUPTARGET_DIR"
	else
		writeToConsole $MSG_LEVEL_DETAILED $MSG_BACKUP_TARGET "$BACKUPTYPE" "$BACKUPTARGET_FILE"
	fi

	logItem "Storing backup in backuppath $BACKUPPATH"

	if [[ -f $BOOT_DEVICENAME ]]; then
		logCommand "fdisk -l $BOOT_DEVICENAME"
	fi

	logItem "Starting $BACKUPTYPE backup..."

	rc=0

	callExtensions $READY_BACKUP_EXTENSION $rc

	START_TIME=$(date +%s)

	if [[ -z ${FAKE_BACKUP+x} ]]; then
		if (( ! $FAKE )); then
			if (( ! $PARTITIONBASED_BACKUP )); then

				case "$BACKUPTYPE" in

					$BACKUPTYPE_DD|$BACKUPTYPE_DDZ) backupDD
						;;

					$BACKUPTYPE_TAR|$BACKUPTYPE_TGZ) backupTar
						;;

					$BACKUPTYPE_RSYNC) backupRsync
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
		fi
	fi
	END_TIME=$(date +%s)

	BACKUP_TIME=($(duration $START_TIME $END_TIME))
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_BACKUP_TIME "${BACKUP_TIME[1]}" "${BACKUP_TIME[2]}" "${BACKUP_TIME[3]}"

	logItem "Syncing"
	sync
	logItem "Finished $BACKUPTYPE backup"

	logItem "Backup created with return code: $rc"

	logItem "Current directory: $(pwd)"
	if [[ -z $BACKUPPATH || "$BACKUPPATH" == *"*"* ]]; then
		assertionFailed $LINENO "Unexpected backup path $BACKUPPATH"
	fi

	logSystemDiskState

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
			mountAndCheck "/dev/$partitionName" "$1/$partitionName"
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

	if (( ! $FAKE )); then
		partitionLayoutBackup
	fi

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

				$BACKUPTYPE_DD|$BACKUPTYPE_DDZ) backupDD "$partition"
					;;

				$BACKUPTYPE_TAR|$BACKUPTYPE_TGZ) backupTar "$partition"
					;;

				$BACKUPTYPE_RSYNC) backupRsync "$partition"
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
	logCommand "fdisk -l | grep -v "^$""
	logCommand "mount"

	if isUnsupportedVersion; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNSUPPORTED_VERSION
	fi

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

# blkid
# /dev/mmcblk0p2: UUID="ea98d3bf-9345-4bd7-b365-5cc7c543079f" TYPE="ext4" PARTUUID="d888a167-02"

# Args: /dev/mmcblk0p2, /PARTUUID=xxxxx, LABEL=xxxxx or UUID=xxxxxx
# Result: $1, /dev/sda1, /dev/mmcblk0p1, /dev/sdb1 or "" if not found in blkid

function getPartitionName() { # /etc/fstab first col

	logEntry "$1"

	local prfx="$(cut -f 1 -d '=' <<< $1)"
	local id="$(cut -f 2 -d '=' <<< $1)"

	local b="$(blkid)"

	local match="$(grep "$prfx=\"$id\"" <<< "$b")"
	local result="$1"

	if [[ -n "$match" ]]; then
		result="$(cut -f 1 -d ":" <<< $match)"
	fi

	echo "$result"

	logExit "$result"

}

# check there is no external root partition used if it's a standard raspbian

# /etc/fstab
# PARTUUID=d888a167-02  /           vfat    defaults          0       2

function extractBootAndRootPartitionNames() {

	logEntry

	local pre="$(grep -E "^[^#]+\s(/|/boot)\s.*" /etc/fstab | xargs -I {} bash -c "echo {} | cut -f 1 -d ' '")"
	logItem "$pre"
	local p part
	local result
	for p in ${pre[@]}; do
		part="$(getPartitionName $p)"
		result="$result $p $part"
	done
	echo "$result"

	logExit "$result"
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
			if [[ $type != 5 && $type != 85 && $size > 0 ]]; then # skip empty and extended partitions
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

	if (( ! $REGRESSION_TEST )); then # skip test in regressiontest because in qemu /dev/mmcblk0 is a symlink to /dev/sda
		local pn=( $(extractBootAndRootPartitionNames) )
		local i
		for ((i=0;i<${#pn[@]};i+=2)); do
			local p=${pn[i]}
			local d=${pn[$((i+1))]}
			if [[ $d =~ /dev/sd && ! $BOOT_DEVICENAME =~ /dev/sd  ]]; then # allow -P for USB boot (all partitions are external but write error of SD card is used
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXTERNAL_PARTITION_NOT_SAVED "$p" "$d"
				error=1
			fi
		done
	fi

	if (( $error )); then
		exitError $RC_PARAMETER_ERROR
	fi

	logExit

}

function commonChecks() {

	logEntry

	if hasSpaces "$CUSTOM_CONFIG_FILE"; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_CONTAINS_SPACES "$CUSTOM_CONFIG_FILE"
		exitError $RC_MISC_ERROR
	fi

	if [[ -n "$EMAIL" ]]; then
		if [[ ! $EMAIL_PROGRAM =~ $SUPPORTED_EMAIL_PROGRAM_REGEX ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_EMAIL_PROG_NOT_SUPPORTED "$EMAIL_PROGRAM" "$SUPPORTED_MAIL_PROGRAMS"
			exitError $RC_EMAILPROG_ERROR
		fi
		if [[ ! $(which $EMAIL_PROGRAM) && ( $EMAIL_PROGRAM != $EMAIL_EXTENSION_PROGRAM ) ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_MAILPROGRAM_NOT_INSTALLED $EMAIL_PROGRAM
			exitError $RC_EMAILPROG_ERROR
		fi
		if [[ "$EMAIL_PROGRAM" == "$EMAIL_SSMTP_PROGRAM" || "$EMAIL_PROGRAM" == "$EMAIL_MSMTP_PROGRAM" ]] && (( $APPEND_LOG )); then
			if ! which mpack &>/dev/null; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_MPACK_NOT_INSTALLED
				APPEND_LOG=0
			fi
		fi
	fi

	local co="$(tr -d "$COLORING_VALID_OPTIONS" <<< $COLORING)"
	if [[ -n "$COLORING" && -n "$co" ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_INVALID_COLORING_OPTION "$co"
			exitError $RC_PARAMETER_ERROR
	fi

	logExit

}

function getRootPartition() {

	logEntry
#	cat /proc/cmdline
#	dma.dmachans=0x7f35 bcm2708_fb.fbwidth=656 bcm2708_fb.fbheight=416 bcm2708.boardrev=0xf bcm2708.serial=0x3f3c9490 smsc95xx.macaddr=B8:27:EB:3C:94:90 bcm2708_fb.fbswap=1 sdhci-bcm2708.emmc_clock_freq=250000000 vc_mem.mem_base=0x1fa00000 vc_mem.mem_size=0x20000000  dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline rootwait

	local cmdline=$(cat /proc/cmdline)
	logCommand "cat /proc/cmdline"
	if [[ $cmdline =~ .*(imgpart|root|datadev)=([^ ]+) ]]; then # berryboot and volumio
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

function deviceInfo() { # device, e.g. /dev/mmcblk1p2 or /dev/sda3 or /dev/nvme0n1p1 or /dev/nvme0n1p1, returns 0:device (mmcblk0), 1: partition number

	logEntry "$1"
	local r=""

	if [[ $1 =~ ^/dev/([^0-9]+)([0-9]+)$ || $1 =~ ^/dev/([^0-9]+[0-9]+)p([0-9]+)$ || $1 =~ ^/dev/([^0-9]+[0-9]+n[0-9])+p([0-9]+)$ ]]; then
		r="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
	fi

	echo "$r"
	logExit "$r"
}

function inspect4Backup() {

	logEntry

	logCommand "ls -1 /dev/mmcblk*"
	logCommand "ls -1 /dev/sd*"
	logCommand "ls -1 /dev/nvme*"

	if mount | grep -q "^overlay.* on / type"; then
		writeToConsole $MSG_LEVEL_MINIMAL $OVERLAY_FILESYSTEM_NOT_SUPPORTED
		exitError $RC_NOT_SUPPORTED
	fi

	if [[ -n "$BOOT_DEVICE" ]]; then
		local updatedBootdeviceName=${BOOT_DEVICE#"/dev/"}
		BOOT_DEVICE="$updatedBootdeviceName"
		logItem "Using configured bootdevice $BOOT_DEVICE"
	elif (( $REGRESSION_TEST )); then
		[[ -e /dev/sda ]] && BOOT_DEVICE="sda"
		[[ -e /dev/mmcblk0 ]] && BOOT_DEVICE="mmcblk0"
		[[ -e /dev/nvme0n1 ]] && BOOT_DEVICE="nvme0n1"
		logItem "Force BOOT_DEVICE to $BOOT_DEVICE"
	elif (( $RESTORE )); then
		BOOT_DEVICE="mmcblk0"
		logItem "Force BOOT_DEVICE to $BOOT_DEVICE"
	elif [[ -z $BOOT_DEVICE ]]; then

		logItem "Starting boot discovery"

		# test whether boot device is mounted
		local bootMountpoint="/boot"
		local bootPartition=$(findmnt $bootMountpoint -o source -n) # /dev/mmcblk0p1, /dev/loop01p or /dev/sda1 or /dev/nvme0n1p1
		logItem "bootMountpoint1: $bootMountpoint mounted? $bootPartition"

		if [[ -z $bootPartition ]]; then
			bootMountpoint="/boot/firmware"
			local bootPartition=$(findmnt $bootMountpoint -o source -n) # /dev/mmcblk0p1, /dev/loop01p or /dev/sda1 or /dev/nvme0n1p1
			logItem "bootMountpoint2: $bootMountpoint mounted? $bootPartition"
		fi

		# test whether some other /boot path is mounted
		if [[ -z $bootPartition ]]; then
			bootPartition=$(mount | grep "\s/boot" | cut -f 1 -d ' ')
			bootMountpoint=$(mount | grep "\s/boot" | cut -f 3 -d ' ')
			logItem "Some path in /boot mounted? $bootPartition on $bootMountpoint"
		fi

		logItem "bootMountpoint: $bootMountpoint, bootPartition: $bootPartition"
		
		logItem "Starting root discovery"

		# find root partition
		local rootPartition=$(findmnt / -o source -n) # /dev/root or /dev/sda1 or /dev/mmcblk1p2 or /dev/nvme0n1p2
		logItem "rootPartition: / mounted? $rootPartition"
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

		BOOT_DEVICE="${boot[0]}"

		if [[ "${boot[@]}" == "${root[@]}" ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_SHARED_BOOT_DEVICE "/dev/$BOOT_DEVICE"
			SHARED_BOOT_DIRECTORY=1
		fi
	fi

	if [[ ! "$BOOT_DEVICE" =~ ^mmcblk[0-9]+$|^sd[a-z]$|^loop[0-9]+|^nvme[0-9]+n[0-9]+$ ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_INVALID_BOOT_DEVICE "$BOOT_DEVICE"
		exitError $RC_INVALID_BOOTDEVICE
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
		SF_FILE=$(ls -1 $RESTOREFILE/${HOSTNAME}-backup.sfdisk)
		if [[ -z $SF_FILE ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_NOT_FOUND "$RESTOREFILE/${HOSTNAME}-backup.sfdisk"
			exitError $RC_MISSING_FILES
		fi

		MBR_FILE=$(ls -1 $RESTOREFILE/${HOSTNAME}-backup.mbr)
		if [[ -z $MBR_FILE ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_NOT_FOUND "$RESTOREFILE/${HOSTNAME}-backup.mbr"
			exitError $RC_MISSING_FILES
		fi
	fi

	if (( $PARTITIONBASED_BACKUP )); then
		BLKID_FILE=$(ls -1 $RESTOREFILE/${HOSTNAME}-backup.blkid)
		if [[ -z $BLKID_FILE ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_NOT_FOUND "$RESTOREFILE/${HOSTNAME}-backup.blkid"
			exitError $RC_MISSING_FILES
		fi

		PARTED_FILE=$(ls -1 $RESTOREFILE/${HOSTNAME}-backup.parted)
		if [[ -z $PARTED_FILE ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_NOT_FOUND "$RESTOREFILE/${HOSTNAME}-backup.parted"
			exitError $RC_MISSING_FILES
		fi

		FDISK_FILE=$(ls -1 $RESTOREFILE/${HOSTNAME}-backup.fdisk)
		if [[ -z $FDISK_FILE ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_NOT_FOUND "$RESTOREFILE/${HOSTNAME}-backup.fdisk"
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
			logCommand"cat $SF_FILE"
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
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_VISIT_VERSION_HISTORY_PAGE "$(getMessage $MSG_VERSION_HISTORY_PAGE)"
				NEWS_AVAILABLE=1
				BETA_AVAILABLE=1
			fi
		fi
	fi

	logExit

}

function doitBackup() {

	logEntry "$PARTITIONBASED_BACKUP"

	checkImportantParameters

	getRootPartition
	inspect4Backup

	commonChecks

	if hasSpaces "$BACKUPPATH"; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_CONTAINS_SPACES "$BACKUPPATH"
		exitError $RC_MISC_ERROR
	fi

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
			if ! (( $PARTITIONBASED_BACKUP || $IGNORE_ADDITIONAL_PARTITIONS )); then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_MULTIPLE_PARTITIONS_FOUND
				exitError $RC_SDCARD_ERROR
			fi
			if (( $IGNORE_ADDITIONAL_PARTITIONS && ! $PARTITIONBASED_BACKUP )); then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_MULTIPLE_PARTITIONS_FOUND_BUT_2_PARTITIONS_SAVED_ONLY
			fi
		fi
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

	if (( $SMART_RECYCLE )); then
		if [[ ! "$SMART_RECYCLE_OPTIONS" =~ ^[0-9]+[[:space:]]*+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+$ ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_SMART_RECYCLE_PARM_INVALID "" "$SMART_RECYCLE_OPTIONS"
			mentionHelp
			exitError $RC_PARAMETER_ERROR
		fi

		eval "SMART_RECYCLE_PARMS=( $SMART_RECYCLE_OPTIONS )"
		local p="${SMART_RECYCLE_PARMS[@]}"
		logItem "SMART_RECYCLE_PARMS: $p"
		logItem "smart recycle parms: ${#SMART_RECYCLE_PARMS[@]}"

		local sb
		if (( $SMART_RECYCLE )); then
			for sb in "${SMART_RECYCLE_PARMS[@]}"; do
				if (( $sb > 365 )); then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_SMART_RECYCLE_PARM_INVALID "$sb" "$SMART_RECYCLE_OPTIONS"
					mentionHelp
					exitError $RC_PARAMETER_ERROR
				fi
			done
		fi
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

	if [[ -n "$TELEGRAM_CHATID" && -z "$TELEGRAM_TOKEN" ]] || [[ -z "$TELEGRAM_CHATID" && -n "$TELEGRAM_TOKEN" ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_TELEGRAM_OPTIONS_INCOMPLETE
		exitError $RC_PARAMETER_ERROR
	fi

	if [[ -n "$TELEGRAM_CHATID" && -n "$TELEGRAM_TOKEN" ]]; then
		if ! which jq &>/dev/null; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "jq" "jq"
			exitError $RC_MISSING_COMMANDS
		fi
		local invalidNotification="$(tr -d "$TELEGRAM_POSSIBLE_NOTIFICATIONS" <<< "$TELEGRAM_NOTIFICATIONS")"
		if [[ -n "$invalidNotification" ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_TELEGRAM_INVALID_NOTIFICATION "$invalidNotification" "$TELEGRAM_POSSIBLE_NOTIFICATIONS"
			exitError $RC_PARAMETER_ERROR
		fi
	fi

	if [[ -n "$PUSHOVER_USER" && -z "PUSHOVER_TOKEN" ]] || [[ -z "$PUSHOVER_USER" && -n "$PUSHOVER_TOKEN" ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_PUSHOVER_OPTIONS_INCOMPLETE
		exitError $RC_PARAMETER_ERROR
	fi

	if [[ -n "$PUSHOVER_USER" && -n "$PUSHOVER_TOKEN" ]]; then
		if ! which jq &>/dev/null; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "jq" "jq"
			exitError $RC_MISSING_COMMANDS
		fi
		local invalidNotification="$(tr -d "$PUSHOVER_POSSIBLE_NOTIFICATIONS" <<< "$PUSHOVER_NOTIFICATIONS")"
		if [[ -n "$invalidNotification" ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_PUSHOVER_INVALID_NOTIFICATION "$invalidNotification" "$PUSHOVER_POSSIBLE_NOTIFICATIONS"
			exitError $RC_PARAMETER_ERROR
		fi
	fi

	if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
		local invalidNotification="$(tr -d "$SLACK_POSSIBLE_NOTIFICATIONS" <<< "$SLACK_NOTIFICATIONS")"
		if [[ -n "$invalidNotification" ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_SLACK_INVALID_NOTIFICATION "$invalidNotification" "$SLACK_POSSIBLE_NOTIFICATIONS"
			exitError $RC_PARAMETER_ERROR
		fi
	fi

	if [[ "$BACKUPTYPE" == "$BACKUPTYPE_DD" || "$BACKUPTYPE" == "$BACKUPTYPE_DDZ" ]]; then
		(( $DD_WARNING )) && writeToConsole $MSG_LEVEL_MINIMAL $MSG_DD_WARNING
	fi

	if [[ "$BACKUPTYPE" == "$BACKUPTYPE_RSYNC" ]]; then
		if ! which rsync &>/dev/null; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "rsync" "rsync"
			exitError $RC_MISSING_COMMANDS
		fi

		if ! supportsHardlinks "$BACKUPPATH"; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_HARDLINK_ERROR "$BACKUPPATH" "$RC_MISC_ERROR"
			exitError $RC_MISC_ERROR
		else
			local fs="$(getFsType "$BACKUPPATH")"
			logItem "Filesystem: $fs"
			if ! supportsFileAttributes $BACKUPPATH; then
				if [[ $fs =~ ^nfs* ]]; then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_FILEATTRIBUTE_RIGHTS "$(findMountPath "$BACKUPPATH")" "$fs"
				else
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_FILEATTRIBUTESUPPORT "$fs" "$(findMountPath "$BACKUPPATH")"
				fi
				exitError $RC_MISC_ERROR
			fi
		fi
		if ! supportsSymlinks "$BACKUPPATH"; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILESYSTEM_INCORRECT "$BACKUPPATH" "softlinks"
			exitError $RC_PARAMETER_ERROR
		fi

		local rsyncVersion=$(rsync --version | head -n 1 | awk '{ print $3 }')
		logItem "rsync version: $rsyncVersion"
		if (( $PROGRESS && $INTERACTIVE )) && [[ "$rsyncVersion" < "3.1" ]]; then
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

	if (( $PROGRESS && $INTERACTIVE )); then
		if ! which pv &>/dev/null; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "pv" "pv"
			exitError $RC_MISSING_COMMANDS
		fi
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
		local rc=$?
		rm $BACKUPPATH/47.$$ &>/dev/null
		rm $BACKUPPATH/11.$$ &>/dev/null
		if [[ $rc != 0 ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNABLE_TO_USE_HARDLINKS "$BACKUPPATH" "$rc"
			exitError $RC_LINK_FILE_FAILED
		fi
	fi

	if (( $SYSTEMSTATUS )) && ! which lsof &>/dev/null; then
		 writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "lsof" "lsof"
		 exitError $RC_MISSING_COMMANDS
	fi

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_USING_BACKUPPATH "$BACKUPPATH" "$(getFsType "$BACKUPPATH")"

	if (( ! $SKIPLOCALCHECK )); then
		if ! isPathMounted $BACKUPPATH; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_DEVICEMOUNTED "$BACKUPPATH"
			exitError $RC_MISC_ERROR
		fi
		# check if a mount to any partition on boot device exists
		logItem "BOOT_DEVICE: $BOOT_DEVICE"
		local lsblkResult="$(lsblk -l -o name,mountpoint | grep "${BACKUPPATH}" | grep $BOOT_DEVICE)"
		logItem "lsblkResult: $lsblkResult"
		local di=($(deviceInfo /dev/$lsblkResult))
		logItem "di: $di"
		if [[ "$BOOT_DEVICE" == "${di[0]}" ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_DEVICEMOUNTED "$BACKUPPATH"
			exitError $RC_MISC_ERROR
		fi
	fi

	BACKUPPATH_PARAMETER="$BACKUPPATH"
	BACKUPPATH="$BACKUPPATH/$HOSTNAME"
	if [[ ! -d "$BACKUPPATH" ]]; then
		 if ! mkdir -p "${BACKUPPATH}"; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNABLE_TO_CREATE_DIRECTORY "$BACKUPPATH"
			exitError $RC_CREATE_ERROR
		 fi
	fi

	logCommand "ls -1 ${BACKUPPATH}"
	local nonRaspiGeneratedDirs=$(ls -1 ${BACKUPPATH} | egrep -Ev "$HOSTNAME\-($POSSIBLE_BACKUP_TYPES_REGEX)\-backup\-([0-9]){8}.([0-9]){6}" | egrep -E "\-backup\-" | wc -l)
	logItem "nonRaspiGeneratedDirs: $nonRaspiGeneratedDirs"

	if (( $nonRaspiGeneratedDirs > 0 )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_INVALID_BACKUPNAMES_DETECTED $nonRaspiGeneratedDirs $BACKUPPATH
		exitError $RC_BACKUP_DIRNAME_ERROR
	fi

	# just inform about options enabled

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

	if (( ! $RESTORE && $REBOOT_SYSTEM && ! $FAKE )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_REBOOT_SYSTEM
	fi

	# now either execute a SR dryrun or start backup

	if (( $SMART_RECYCLE_DRYRUN && $SMART_RECYCLE )); then # just apply backup strategy to test smart recycle
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_APPLYING_BACKUP_STRATEGY_ONLY "$BACKUPPATH/$(hostname)"
		applyBackupStrategy
		rc=0
	else
		if (( $SMART_RECYCLE && !$SMART_RECYCLE_DRYRUN )); then
			writeToConsole $MSG_LEVEL_DETAILED $MSG_SMART_RECYCLE_WILL_BE_APPLIED
		fi
		backup
	fi

	logExit

}

function getPartitionTable() { # device

	logEntry "$1"
	local result

	# Possible results of partprobe
	# See https://stackoverflow.com/questions/26873289/how-to-check-a-disk-for-partitions-for-use-in-a-script-in-linux
	# /dev/sdb: gpt partitions 1 -> partition table exists and one partition
	# /dev/sdb: gpt partitions -> partition table exists but no partition
	# <empty> -> no partition table

	if [[ -n "$(partprobe -d -s $1 | cut -f 4 -d ' ')" ]]; then
		local table="$(IFS='' parted $1 unit MB p 2>>$LOG_FILE | sed -r '/^($|[MSDP])/d')"
		if [[ $(wc -l <<< "$table") < 2 ]]; then
			result=""
		else
			result="$table"
		fi
	else
		result=""
	fi
	echo "$result"

	logExit "$result"
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

	if [[ $RESTORE_DEVICE =~ /dev/mmcblk[0-9] || $RESTORE_DEVICE =~ "/dev/loop" || $RESTORE_DEVICE =~ /dev/nvme[0-9]n[0-9] ]]; then
		BOOT_PARTITION="${RESTORE_DEVICE}p1"
	else
		BOOT_PARTITION="${RESTORE_DEVICE}1"
	fi
	logItem "BOOT_PARTITION : $BOOT_PARTITION"

	ROOT_PARTITION_DEFINED=1
	if [[ -z $ROOT_PARTITION ]]; then
		if [[ $RESTORE_DEVICE =~ /dev/mmcblk[0-9] || $RESTORE_DEVICE =~ "/dev/loop" || $RESTORE_DEVICE =~ /dev/nvme[0-9]n[0-9] ]]; then
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
	else
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_SKIP_CREATING_PARTITIONS
	fi

	current_partition_table="$(getPartitionTable $RESTORE_DEVICE)"
	if [[ -n "$current_partition_table" ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_CURRENT_PARTITION_TABLE "$RESTORE_DEVICE"
		echo "$current_partition_table"
	else
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_PARTITION_TABLE_DEFINED "$RESTORE_DEVICE"
		if (( $SKIP_SFDISK )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_PARTITION "$RESTORE_DEVICE"
			exitError $RC_MISSING_PARTITION
		fi
	fi

	if (( ! $ROOT_PARTITION_DEFINED )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_WARN_RESTORE_DEVICE_OVERWRITTEN $RESTORE_DEVICE
	else
		if [[ $ROOT_DEVICE =~ /dev/mmcblk0 || $ROOT_DEVICE =~ "/dev/loop" || $ROOT_DEVICE =~ /dev/nvme0n1 ]]; then
			ROOT_DEVICE=$(sed -E 's/p[0-9]+$//' <<< $ROOT_PARTITION)
		else
			ROOT_DEVICE=$(sed -E 's/[0-9]+$//' <<< $ROOT_PARTITION)
		fi

		if [[ $ROOT_DEVICE != $RESTORE_DEVICE ]]; then
			current_partition_table="$(getPartitionTable $ROOT_DEVICE)"
			if [[ -n $current_partition_table ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_CURRENT_PARTITION_TABLE "$ROOT_DEVICE" "$current_partition_table"
			else
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_PARTITION_TABLE_DEFINED "$ROOT_DEVICE"
				if (( $SKIP_SFDISK )); then
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_PARTITION "$ROOT_DEVICE"
					exitError $RC_MISSING_PARTITION
				fi
			fi
		fi
	fi
	if (( ! $SKIP_SFDISK )); then
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
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_DEVICE_NOT_ALLOWED
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

	if (( ! $SKIP_SFDISK && ! $FORCE_SFDISK )); then
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

	if (( $NO_YES_QUESTION )); then
		echo "Y${NL}"
	fi

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
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNABLE_TO_CREATE_PARTITIONS $rc "$error"
			exitError $RC_CREATE_PARTITIONS_FAILED
		fi

		waitForPartitionDefsChanged

	else
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_SKIPPING_CREATING_PARTITIONS
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

	updateUUIDs

	logCommand "fdisk -l $RESTORE_DEVICE"

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
	[[ $restoreDevice =~ mmcblk0 || $restoreDevice =~ "loop" || $restoreDevice =~ nvme0n1 ]] && restoreDevice="${restoreDevice}p"
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

				$BACKUPTYPE_TAR|$BACKUPTYPE_TGZ)
					local archiveFlags=""

					if [[ -n $fatSize  ]]; then
						local archiveFlags="--same-owner --same-permissions --numeric-owner ${TAR_RESTORE_ADDITIONAL_OPTIONS}"	# fat32 doesn't know about this
					fi

					if ! pushd "$MNT_POINT" &>>"$LOG_FILE"; then
						assertionFailed $LINENO "push to $MNT_POINT failed"
					fi
					[[ "$BACKUPTYPE" == "$BACKUPTYPE_TGZ" ]] && zip="z" || zip=""
					cmd="tar ${archiveFlags} -x${verbose}${zip}f \"$restoreFile\""

					if (( $PROGRESS && $INTERACTIVE )); then
						cmd="pv -f $restoreFile | $cmd -"
					fi
					executeTar "$cmd"
					rc=$?
					popd &>>"$LOG_FILE"
					;;

				$BACKUPTYPE_RSYNC)
					local archiveFlags="aH"						# -a <=> -rlptgoD, H = preserve hardlinks
					[[ -n $fatSize  ]] && archiveFlags="rltD"	# no Hopg flags for fat fs
					cmdParms="--numeric-ids -${archiveFlags}X$verbose \"$restoreFile/\" $MNT_POINT"
					if (( $PROGRESS && $INTERACTIVE )); then
						cmd="rsync --info=progress2 $cmdParms"
					else
						cmd="rsync $cmdParms"
					fi
					executeRsync "$cmd"
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

	logCommand "blkid"

	commonChecks

	if hasSpaces "$RESTOREFILE"; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_CONTAINS_SPACES "$RESTOREFILE"
		exitError $RC_MISC_ERROR
	fi

	if [[ ! -d "$RESTOREFILE" ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_DIRECTORY_NO_DIRECTORY "$RESTOREFILE"
		exitError $RC_MISSING_FILES
	fi

	if mount | grep "^${RESTORE_DEVICE%/}"; then # delete trailing / if it's present
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_PARTITION_MOUNTED "$RESTORE_DEVICE"
		exitError $RC_RESTORE_IMPOSSIBLE
	fi

	if [[ ! -b "$RESTORE_DEVICE" ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_DEVICE_NOT_VALID "$RESTORE_DEVICE"
		exitError $RC_RESTORE_IMPOSSIBLE
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

	if (( ! $SKIP_SFDISK )); then
		if isMounted "$RESTORE_DEVICE"; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTORE_DEVICE_MOUNTED "$RESTORE_DEVICE"
			exitError $RC_MISC_ERROR
		fi
	fi

	logItem "Checking for partitionbasedbackup in $RESTOREFILE/*"
	logCommand "ls -1 $RESTOREFILE*"

	if  ls -1 "$RESTOREFILE"* | egrep "^(sd[a-z]([0-9]+)|mmcblk[0-9]+p[0-9]+|nvme[0-9]+n[0-9]+p[0-9]+)$" &>>"$LOG_FILE" ; then
		PARTITIONBASED_BACKUP=1
	else
		PARTITIONBASED_BACKUP=0
	fi

	logItem "PartitionbasedBackup detected? $PARTITIONBASED_BACKUP"

	if [[ -z $RESTORE_DEVICE ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_RESTOREDEVICE_DEFINED
		exitError $RC_PARAMETER_ERROR
	fi

	if (( $PROGRESS && $INTERACTIVE )); then
		if ! which pv &>/dev/null; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "pv" "pv"
			exitError $RC_PARAMETER_ERROR
		fi
	fi

	if ! (( $FAKE )); then
		RESTORE_DEVICE=${RESTORE_DEVICE%/} # delete trailing /
		if [[ ! ( $RESTORE_DEVICE =~ ^/dev/mmcblk[0-9]+$ ) && ! ( $RESTORE_DEVICE =~ /dev/loop[0-9]+ ) && ! ( $RESTORE_DEVICE =~ /dev/nvme[0-9]+n[0-9]+ )]]; then
			if ! [[ "$RESTORE_DEVICE" =~ ^/dev/[a-zA-Z]+$ ]] ; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_RESTOREDEVICE_IS_PARTITION "$RESTORE_DEVICE"
				exitError $RC_PARAMETER_ERROR
			fi
		fi

		if [[ -z $(fdisk -l $RESTORE_DEVICE 2>/dev/null) ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_RESTOREDEVICE_FOUND $RESTORE_DEVICE
			exitError $RC_PARAMETER_ERROR
		fi
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

		local rd=$(sed -E 's#/dev/([a-z]+)(.+)?#\1#' <<< "$RESTORE_DEVICE")
		local rr=$(sed -E 's#/dev/([a-z]+)(.+)?#\1#' <<< "$ROOT_PARTITION")

		logItem "Restore devices: -d: $rd - -R: $rr"

		if [[ "$rd" == "$rr" ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_ROOT_PARTITION_NOT_DIFFERENT "$RESTORE_DEVICE"
			exitError $RC_DEVICES_NOTFOUND
		fi
	fi

	local usbMount="$(LC_ALL=C dpkg-query -W --showformat='${Status}\n' usbmount 2>&1)"
	if grep -q "install ok installed" <<< "$usbMount" &>>$LOG_FILE; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_USBMOUNT_INSTALLED
		exitError $RC_ENVIRONMENT_ERROR
	fi

	BASE_DIR=$(dirname "$RESTOREFILE")
	logItem "Basedir: $BASE_DIR"
	HOSTNAME=$(basename "$RESTOREFILE" | sed -r 's/(.*)-[A-Za-z]+-backup-[0-9]+-[0-9]+.*/\1/')
	logItem "Hostname: $HOSTNAME"
	BACKUPTYPE=$(basename "$RESTOREFILE" | sed -r 's/.*-([A-Za-z]+)-backup-[0-9]+-[0-9]+.*/\1/')
	logItem "Backuptype: $BACKUPTYPE"
	DATE=$(basename "$RESTOREFILE" | sed -r 's/.*-[A-Za-z]+-backup-([0-9]+-[0-9]+).*/\1/')
	logItem "Date: $DATE"

	if (( $PROGRESS && $INTERACTIVE )); then
		if ! which pv &>/dev/null; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "pv" "pv"
			exitError $RC_MISSING_COMMANDS
		fi
	fi

	if [[ "$BACKUPTYPE" == "$BACKUPTYPE_RSYNC" ]]; then
		if ! which rsync &>/dev/null; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "rsync" "rsync"
			exitError $RC_MISSING_COMMANDS
		fi
		local rsyncVersion=$(rsync --version | head -n 1 | awk '{ print $3 }')
		logItem "rsync version: $rsyncVersion"
		if (( $PROGRESS && $INTERACTIVE )) && [[ "$rsyncVersion" < "3.1" ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_RSYNC_DOES_NOT_SUPPORT_PROGRESS "$rsyncVersion"
			exitError $RC_PARAMETER_ERROR
		fi
	fi

	if ! which dosfslabel &>/dev/null; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_MISSING_INSTALLED_FILE "dosfslabel" "dosfstools"
		exitError $RC_MISSING_COMMANDS
	fi

	if (( ! $PARTITIONBASED_BACKUP	 )); then
		findNonpartitionBackupBootAndRootpartitionFiles
	fi

	inspect4Restore

	if (( $FORCE_SFDISK )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_FORCE_SFDISK "$RESTORE_DEVICE"
	fi

	if (( $SKIP_SFDISK )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_SKIP_SFDISK "$RESTORE_DEVICE"
	fi

	#if [[ "$BACKUPTYPE" == "$BACKUPTYPE_DD" ]]; then
	#	local sdSize="$(fdisk -l "$RESTORE_DEVICE" | grep "Disk.*${RESTORE_DEVICE}" | cut -d ' ' -f 5)"
	#	local imgSize="$(stat -c "%s" "$ROOT_RESTOREFILE")"
	#	if [[ $sdSize < $imgSize ]]; then
	#		writeToConsole $MSG_LEVEL_MINIMAL $MSG_SD_TOO_SMALL "$RESTORE_DEVICE" "$sdSize" "$imgSize"
	#		exitError $RC_RESTORE_FAILED
	#	fi
	#elif [[ "$BACKUPTYPE" == "$BACKUPTYPE_DDZ" ]]; then
	#	local c
	#	read c sdSize r < <(gzip -l "$RESTOREFILE" | tail -n 1)
	#	imgSize="$(stat -c "%s" "$ROOT_RESTOREFILE")"
	#	if [[ $sdSize < $imgSize ]]; then
	#		writeToConsole $MSG_LEVEL_MINIMAL $MSG_SD_TOO_SMALL "$RESTORE_DEVICE" "$sdSize" "$imgSize"
	#		exitError $RC_RESTORE_FAILED
	#	fi
	#fi

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
						exitError $RC_PARAMETER_ERROR
					fi
				else
					if (( $RESIZE_ROOTFS )); then
						if (( $targetSDSize >= $TWO_TB )); then		# target should have gpt in order to use space > 2TB during expansion
							writeToConsole $MSG_LEVEL_MINIMAL $MSG_TARGET_REQUIRES_GPT "$RESTORE_DEVICE" "$(bytesToHuman $targetSDSize)"
						fi
						writeToConsole $MSG_LEVEL_MINIMAL $MSG_ADJUSTING_WARNING2 "$RESTORE_DEVICE" "$(bytesToHuman $targetSDSize)" "$(bytesToHuman $sourceSDSize)"
					fi
				fi
			fi
		fi
	fi

	rc=0

	if ! (( $PARTITIONBASED_BACKUP )); then
		restoreNonPartitionBasedBackup
		if [[ $BACKUPTYPE != $BACKUPTYPE_DD && $BACKUPTYPE != $BACKUPTYPE_DDZ ]]; then
			synchronizeCmdlineAndfstab
		fi
	else
		restorePartitionBasedBackup
		synchronizeCmdlineAndfstab
	fi

	logCommand "blkid"

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

	if (( $RESTORE_REMINDER_INTERVAL > 0 )); then

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
		rf="$(<$reminder_file)"
		if [[ -z "${rf}" ]]; then												# issue #316: reminder file exists but is empty
			echo "$(date +%Y%m) 0" > "$reminder_file"
			return
		fi
		rf=( $(<$reminder_file) )
		local diffMonths
		diffMonths=$(calculateMonthDiff $now ${rf[0]} )

		# check if reminder should be send
		if (( $diffMonths <= -$RESTORE_REMINDER_INTERVAL )); then
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
	fi

	logExit

}

function mountAndCheck() { # device mountpoint
	logEntry "$1 - $2"
	if ( isMounted "$2" ); then
		logItem "$2 mounted - unmouting"
		umount "$2" &>>"$LOG_FILE"
		if (( $rc )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_UMOUNT_CHECK_ERROR "$1" "$2" "$rc"
			logExit $rc
			exitError $RC_MISC_ERROR
		fi
	fi
	mount "$1" "$2" &>>"$LOG_FILE"
	local rc=$?
	if (( $rc )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_MOUNT_CHECK_ERROR "$1" "$2" "$rc"
		logExit $rc
		exitError $RC_MISC_ERROR
	fi
	logCommand "findmnt $2"
	logExit $rc
}

function remount() { # device mountpoint

	logEntry "$1 - $2"

	if ( isMounted "$1" ); then
		logItem "$1 mounted - unmouting"
		umount "$1" &>>"$LOG_FILE"
	else
		logItem "$1 not mounted"
	fi

	logItem "Creating mountpoint $2"
	mkdir -p $2
	mountAndCheck "$1" "$2" &>>"$LOG_FILE"
	logExit $rc

}

function updateConfig() {

	logEntry "$CUSTOM_CONFIG_FILE"

	local customFile="$CUSTOM_CONFIG_FILE"
	local etcConfigFileVersion="$ETC_CONFIG_FILE_VERSION"

	# use fileparameter as new config file
	if [[ -n $customFile ]]; then
		if [[ -f $customFile ]]; then
			logItem "Using config file $customFile"
			NEW_CONFIG="$(sed -e "s@$ORIG_CONFIG@$customFile@" <<< "$NEW_CONFIG")"
			MERGED_CONFIG="$(sed -e "s@$ORIG_CONFIG@$customFile@" <<< "$MERGED_CONFIG")"
			BACKUP_CONFIG="$(sed -e "s@$ORIG_CONFIG@$customFile@" <<< "$BACKUP_CONFIG")"
			etcConfigFileVersion="$CUSTOM_CONFIG_FILE_VERSION"
			ORIG_CONFIG="$(sed -e "s@$ORIG_CONFIG@$customFile@" <<< "$ORIG_CONFIG")"
		else
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_NOT_FOUND "$NEW_CONFIG"
			exitError $RC_MISSING_FILES
		fi
	fi

	if [[ ! -e $ORIG_CONFIG ]]; then
		logItem "$ORIG_CONFIG does not exist"
		logExit
		return
	fi

	logItem "Current config version: $etcConfigFileVersion - Required config version: $VERSION_SCRIPT_CONFIG"

	local cr
	compareVersions "$etcConfigFileVersion" "$VERSION_SCRIPT_CONFIG"
	cr=$?

	if (( $cr != 1 )) ; then 						# ETC_CONFIG >= SCRIPT_CONFIG
		logExit "Config version ok"
		if (( $UPDATE_CONFIG )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_CONFIGUPDATE_REQUIRED "$VERSION_SCRIPT_CONFIG"
		fi
		logExit
		return
	fi

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_CURRENT_CONFIGURATION_UPDATE_REQUIRED "$etcConfigFileVersion" "$VERSION_SCRIPT_CONFIG"

	local lang=${LANGUAGE,,}
	eval "DL_URL=$CONFIG_URL"

	# download new config file
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_DOWNLOADING "$NEW_CONFIG" "$DL_URL"

	local dlHttpCode dlRC
	dlHttpCode="$(downloadFile "$DL_URL" "$NEW_CONFIG")"
	dlRC=$?
	if (( $dlRC != 0 )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_DOWNLOAD_FAILED "$DL_URL" "$dlHttpCode" $dlRC
		exitError $RC_DOWNLOAD_FAILED
	fi

	# make sure new config file is readable by owner only
	if ! chmod 600 "$NEW_CONFIG" &>>$LOG_FILE; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_CHMOD_FAILED "$NEW_CONFIG"
		exitError $RC_FILE_OPERATION_ERROR
	fi

	local newConfigVersion="$(extractVersionFromFile "$NEW_CONFIG" "$VERSION_CONFIG_VARNAME")"

	logItem "New config version of downloaded file: $newConfigVersion"

	compareVersions "$etcConfigFileVersion" "$VERSION_SCRIPT_CONFIG"
	cr=$?

	if (( $cr == 1 )); then							# ETC_CONFIG_FILE_VERSION < SCRIPT_CONFIG
		logItem "Config update version in script: $VERSION_SCRIPT_CONFIG - Current config version : $etcConfigFileVersion"

		compareVersions "$newConfigVersion" "$VERSION_SCRIPT_CONFIG"
		cr=$?
		if (( $cr == 1 )); then							# newConfigVersion < SCRIPT_CONFIG
			logItem "No config update possible: $VERSION_SCRIPT_CONFIG - Available: $newConfigVersion"
			logExit
			return
		fi
	fi

	rm -f $MERGED_CONFIG &>/dev/null

	# process NEW CONFIG FILE
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_MERGING_VERSION  "v$etcConfigFileVersion" "v$VERSION_SCRIPT_CONFIG" "$MERGED_CONFIG"
	local merged=0
	local deleted=0

	# make sure config file is readable by owner only
	if ! chmod 600 $ORIG_CONFIG &>>$LOG_FILE; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_CHMOD_FAILED "$ORIG_CONFIG"
		exitError $RC_FILE_OPERATION_ERROR
	fi

	# process new config file and merge old options

	logItem "Merging $NEW_CONFIG and $ORIG_CONFIG"
	while read -r line; do
		if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then			# skip comment or empty lines
			local KW="$(cut -d= -f1 <<< "$line")"					# retrieve keyword
			local VAL="$(cut -d= -f2 <<< "$line" )"	# retrieve value

			logItem "KW: $KW - VAL: $VAL"
			if [[ "$KW" =~ VERSION_.*CONF ]]; then					# add new version number
				echo "$line" >> $MERGED_CONFIG
				local CONFIG_VERSION="$VAL"
				continue
			fi

			local OC_line r
			OC_line="$(grep "^$KW=" $ORIG_CONFIG)"					# retrieve old option line
			r=$?
			logItem "grep old file rc:$s - contents: $OC_line"
			if (( ! $r )); then											# new option found
				local OW="$(cut -d= -f2- <<< "$OC_line" )"				# retrieve old option value
				echo "$KW=$OW" >> $MERGED_CONFIG						# use old option value
			else
				printf "$NEW_OPTION_TRAILER\n" "$CONFIG_VERSION" >> $MERGED_CONFIG
				echo "$line" >> $MERGED_CONFIG						# add new option
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_ADDED_CONFIG_OPTION "$KW" "$VAL"
				(( merged ++ ))
			fi
		else
			echo "$line" >> $MERGED_CONFIG							# copy comment  or empty line
		fi
	done < "$NEW_CONFIG"

	# check in old config file which options were deleted in new config file

	logItem "Checking for deleted options"
	while read -r line; do
		if [[ -n "$line" && ! "$line" =~ ^.*# ]]; then			# skip comment or empty lines
			local KW="$(cut -d= -f1 <<< "$line")"							# retrieve keyword
			local VAL="$(cut -d= -f2 <<< "$line" )"	# retrieve value

			if [[ "$KW" =~ VERSION_.*CONF ]]; then					# skip version number
				continue
			fi

			local r
			grep -q "^$KW=" "$NEW_CONFIG"					# check if it's still the new config file
			r=$?
			logItem "grep old file for deleted $KW rc:$r - contents: $OC_line"
			if (( $r )) && [[ $KW != "UUID" ]]; then				# option not found, it was deleted
				echo "" >> $MERGED_CONFIG
				printf "$DELETED_OPTION_TRAILER\n" "$CONFIG_VERSION" >> $MERGED_CONFIG
				echo "# $line" >> $MERGED_CONFIG						# insert deleted config line as comment
				(( deleted ++ ))
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_DELETED_CONFIG_OPTION "$KW" "$VAL"
			fi
		fi
	done < "$ORIG_CONFIG"

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_MERGE_SUCCESSFULL

	if ! chmod 600 $MERGED_CONFIG &>>$LOG_FILE; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_CHMOD_FAILED "$MERGED_CONFIG"
		exitError $RC_FILE_OPERATION_ERROR
	fi

	logItem "Merged: $merged - deleted: $deleted"

	if askYesNo "$MSG_UPDATE_CONFIG" "$BACKUP_CONFIG"; then
		# save old config
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_SAVING_CURRENT_CONFIGURATION  "$ORIG_CONFIG" "$BACKUP_CONFIG"
		local new_file=$(createBackupVersion "$ORIG_CONFIG")
		local r=$?
		if (( $rc )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_CONFIG_BACKUP_FAILED "$ORIG_CONFIG"
			exitError $RC_FILE_OPERATION_ERROR
		fi

		if ! chmod 600 "$new_file" &>>$LOG_FILE; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_CHMOD_FAILED "$new_file"
			exitError $RC_FILE_OPERATION_ERROR
		fi

		mv "$MERGED_CONFIG" "$ORIG_CONFIG"
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_COPIED_FILE "$MERGED_CONFIG" "$ORIG_CONFIG"
	else
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_ACTIVATE_CONFIG "$MERGED_CONFIG" "$ORIG_CONFIG"
	fi

	logExit

}

function synchronizeCmdlineAndfstab() {

	logEntry

	local CMDLINE FSTAB newPartUUID oldPartUUID BOOT_MP ROOT_MP newUUID oldUUID BOOT_PARTITION oldLABEL newLABEL

	if [[ $RESTORE_DEVICE =~ /dev/mmcblk0 || $RESTORE_DEVICE =~ /dev/nvme0n1 || $RESTORE_DEVICE =~ "/dev/loop" ]]; then
		BOOT_PARTITION="${RESTORE_DEVICE}p1"
	else
		BOOT_PARTITION="${RESTORE_DEVICE}1"
	fi

	if (( $PARTITIONBASED_BACKUP )); then
		ROOT_PARTITION="$(sed 's/1$/2/' <<< "$BOOT_PARTITION")"
	fi

	logEntry "BOOT_PARTITION: $BOOT_PARTITION - ROOT_PARTITION: $ROOT_PARTITION"

	ROOT_MP="$TEMPORARY_MOUNTPOINT_ROOT/root"
	BOOT_MP="$TEMPORARY_MOUNTPOINT_ROOT/boot"
	logEntry "ROOT_MP: $ROOT_MP - BOOT_MP: $BOOT_MP"
	remount "$BOOT_PARTITION" "$BOOT_MP"
	remount "$ROOT_PARTITION" "$ROOT_MP"

	CMDLINE="$BOOT_MP/cmdline.txt" 	# absolute path in mount, don't use firmware subdir for Ubuntu, boot partition is mounted there at ubuntu startup
	FSTAB="$ROOT_MP/etc/fstab" 		# absolute path in mount

	local cmdline # path for message
	[[ -d $TEMPORARY_MOUNTPOINT_ROOT/root/boot/firmware ]] && cmdline="/boot/firmware/cmdline.txt"  || cmdline="/boot/cmdline.txt"

	local fstab="/etc/fstab" # path for message

	logEntry "CMDLINE: $CMDLINE - FSTAB: $FSTAB"

	partprobe $BOOT_PARTITION		# reload partition table
	partprobe $ROOT_PARTITION		# reload partition table

	logCommand "blkid -o udev $ROOT_PARTITION"

	local rootLabelCreated=0

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_SYNC_CMDLINE_FSTAB "$cmdline" "$fstab"

	if [[ -f "$CMDLINE" ]]; then

		logItem "Org $CMDLINE"
		logCommand "cat $CMDLINE"

		if [[ $(cat $CMDLINE) =~ root=PARTUUID=([a-z0-9\-]+) ]]; then
			local oldPartUUID=${BASH_REMATCH[1]}
			local newPartUUID=$(blkid -o udev $ROOT_PARTITION | grep ID_FS_PARTUUID= | cut -d= -f2)
			logItem "CMDLINE - newPartUUID: $newPartUUID, oldPartUUID: $oldPartUUID"
			if [[ -z $newPartUUID ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_UUID_SYNCHRONIZED "$cmdline" "root="
			elif [[ $oldPartUUID != $newPartUUID ]]; then
				writeToConsole $MSG_LEVEL_DETAILED $MSG_UPDATING_UUID "PARTUUID" "$oldPartUUID" "$newPartUUID" "$cmdline"
				sed -i "s/$oldPartUUID/$newPartUUID/" $(realpath $CMDLINE) &>> "$LOG_FILE"
			fi
		elif [[ $(cat $CMDLINE) =~ root=UUID=([a-z0-9\-]+) ]]; then
			local oldUUID=${BASH_REMATCH[1]}
			local newUUID=$(blkid -o udev $ROOT_PARTITION | grep ID_FS_UUID= | cut -d= -f2)
			logItem "CMDLINE - newUUID: $newUUID, oldUUID: $oldUUID"
			if [[ -z $newUUID ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_UUID_SYNCHRONIZED "$cmdline" "root="
			elif [[ $oldUUID != $newUUID ]]; then
				writeToConsole $MSG_LEVEL_DETAILED $MSG_UPDATING_UUID "UUID" "$oldUUID" "$newUUID" "$cmdline"
				sed -i "s/$oldUUID/$newUUID/" $(realpath $CMDLINE) &>> "$LOG_FILE"
			fi
		elif [[ $(cat $CMDLINE) =~ root=LABEL=([a-z0-9\-]+) ]]; then
			local oldLABEL=${BASH_REMATCH[1]}
			logItem "Writing label $oldLABEL on $ROOT_PARTITION"
			writeToConsole $MSG_LEVEL_DETAILED $MSG_LABELING "$ROOT_PARTITION" "$oldLABEL"
			e2label "$ROOT_PARTITION" "$oldLABEL" &>> $LOG_FILE
			local rc=$?
			if (( $rc )); then
				local cmd="e2label $ROOT_PARTITION $oldLABEL"
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_LABELING_FAILED "$cmd" "$rc"
			else
				rootLabelCreated=1
			fi
		elif grep "root=/dev/" $CMDLINE; then
			logItem "/dev detected in $CMDLINE"
		else
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_UUID_SYNCHRONIZED "$cmdline" "root="
		fi
	else
		logCommand "ls -la $BOOT_MP"
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_NOT_FOUND "$cmdline"
	fi

	if [[ -f "$FSTAB" ]]; then
		logItem "Org $FSTAB"
		logItem "$(cat $FSTAB)"

		if [[ $(cat $FSTAB) =~ PARTUUID=([a-z0-9\-]+)[[:space:]]+/[[:space:]] ]]; then
			local oldPartUUID=${BASH_REMATCH[1]}
			local newPartUUID=$(blkid -o udev $ROOT_PARTITION | grep ID_FS_PARTUUID= | cut -d= -f2)
			logItem "FSTAB root - newRootPartUUID: $newPartUUID, oldRootPartUUID: $oldPartUUID"
			if [[ -z $newPartUUID ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_PARTUUID_SYNCHRONIZED "$fstab" "/"
			elif [[ $oldPartUUID != $newPartUUID ]]; then
				local oldpartuuidID="$(sed -E 's/-[0-9]+//' <<< "$oldPartUUID")"
				local newpartuuidID="$(sed -E 's/-[0-9]+//' <<< "$newPartUUID")"
				writeToConsole $MSG_LEVEL_DETAILED $MSG_UPDATING_UUID "PARTUUID" "$oldPartUUID" "$newPartUUID" "$fstab"
				sed -i "s/$oldpartuuidID/$newpartuuidID/g" $FSTAB &>> "$LOG_FILE"
			fi
		elif [[ $(cat $FSTAB) =~ UUID=([a-z0-9\-]+)[[:space:]]+/[[:space:]] ]]; then
			local oldUUID=${BASH_REMATCH[1]}
			local newUUID=$(blkid -o udev $ROOT_PARTITION | grep ID_FS_UUID= | cut -d= -f2)
			logItem "FSTAB root - newRootUUID: $newUUID, oldRootUUID: $oldUUID"
			if [[ -z $newUUID ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_UUID_SYNCHRONIZED "$fstab" "/"
			elif [[ $oldUUID != $newUUID ]]; then
				local olduuidID="$(sed -E 's/-[0-9]+//' <<< "$oldUUID")"
				local newuuidID="$(sed -E 's/-[0-9]+//' <<< "$newUUID")"
				writeToConsole $MSG_LEVEL_DETAILED $MSG_UPDATING_UUID "PARTUUID" "$olduuidID" "$newuuidID" "$fstab"
				sed -i "s/$olduuidID/$newuuidID/g" $FSTAB &>> "$LOG_FILE"
			fi
		elif [[ $(cat $FSTAB) =~ LABEL=([a-z0-9\-]+)[[:space:]]+/[[:space:]] ]]; then
			if (( ! $rootLabelCreated )) ; then
				local oldLABEL=${BASH_REMATCH[1]}
				logItem "Writing label $oldLABEL on $ROOT_PARTITION"
				writeToConsole $MSG_LEVEL_DETAILED $MSG_LABELING "$ROOT_PARTITION" "$oldLABEL"
				e2label "$ROOT_PARTITION" "$oldLABEL" &>> $LOG_FILE
				local rc=$?
				if (( $rc )); then
					local cmd="e2label $ROOT_PARTITION $oldLABEL"
					writeToConsole $MSG_LEVEL_MINIMAL $MSG_LABELING_FAILED "$cmd" "$rc"
				else
					rootLabelCreated=1
				fi
			fi
		elif grep "^/dev/" $FSTAB; then
			logItem "/dev detected in $FSTAB"
		else
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_UUID_SYNCHRONIZED "$fstab" "/"
		fi
	else
		logCommand "ls -la $ROOT_MP"
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_NOT_FOUND "$fstab"
	fi

	if [[ -f "$FSTAB" ]]; then
		logItem "Org $FSTAB"
		logItem "$(cat $FSTAB)"

		if [[ $(cat $FSTAB) =~ PARTUUID=([a-z0-9\-]+)[[:space:]]+/boot ]]; then
			local oldPartUUID=${BASH_REMATCH[1]}
			local newPartUUID=$(blkid -o udev $BOOT_PARTITION | egrep ID_FS_PARTUUID= | cut -d= -f2)
			logItem "FSTAB boot - newPartUUID: $newPartUUID, oldPartUUID: $oldPartUUID"
			if [[ -z $newPartUUID ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_UUID_SYNCHRONIZED "$fstab" "/boot"
			elif [[ $oldPartUUID != $newPartUUID ]]; then
				writeToConsole $MSG_LEVEL_DETAILED $MSG_UPDATING_UUID "PARTUUID" "$oldPartUUID" "$newPartUUID" "$fstab"
				sed -i "s/$oldPartUUID/$newPartUUID/" $FSTAB &>> "$LOG_FILE"
			fi
		elif [[ $(cat $FSTAB) =~ UUID=([a-z0-9\-]+)[[:space:]]+/boot ]]; then
			local oldUUID=${BASH_REMATCH[1]}
			local newUUID=$(blkid -o udev $BOOT_PARTITION | grep ID_FS_UUID= | cut -d= -f2)
			logItem "FSTAB boot - newBootUUID: $newUUID, oldBootUUID: $oldUUID"
			if [[ -z $newUUID ]]; then
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_UUID_SYNCHRONIZED "$fstab" "/boot"
			elif [[ $oldUUID != $newUUID ]]; then
				writeToConsole $MSG_LEVEL_DETAILED $MSG_UPDATING_UUID "PARTUUID" "$oldUUID" "$newUUID" "$fstab"
				sed -i "s/$oldUUID/$newUUID/" $FSTAB &>> "$LOG_FILE"
			fi
		elif [[ $(cat $FSTAB) =~ LABEL=([a-z0-9\-]+)[[:space:]]+/boot ]]; then
			local oldLABEL=${BASH_REMATCH[1]}
			logItem "Writing label $oldLABEL on $BOOT_PARTITION"
			writeToConsole $MSG_LEVEL_DETAILED $MSG_LABELING "$BOOT_PARTITION" "$oldLABEL"
			dosfslabel "$BOOT_PARTITION" "$oldLABEL" &>> $LOG_FILE
			local rc=$?
			if (( $rc )); then
				local cmd="dosfslabel $BOOT_PARTITION $oldLABEL"
				writeToConsole $MSG_LEVEL_MINIMAL $MSG_LABELING_FAILED "$cmd" "$rc"
			fi
		elif grep "^/dev/" $FSTAB; then
			logItem "/dev detected in $FSTAB"
		else
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_UUID_SYNCHRONIZED "$fstab" "/boot"
		fi
	else
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_UUID_SYNCHRONIZED "$fstab" "/boot"
	fi

	if [[ -f "$CMDLINE" ]]; then
		logItem "Upd $CMDLINE"
		logCommand "cat $CMDLINE"
	fi

	if [[ -f "$FSTAB" ]]; then
		logItem "Upd $FSTAB"
		logCommand "cat $FSTAB"
	fi

	umount $BOOT_MP &>>"$LOG_FILE"
	umount $ROOT_MP &>>"$LOG_FILE"

	logExit
}

# count number of lines in string and return 0 if line is empty (wc -l will return 1 :-( )
function countLines() { # string
	logEntry "$1"
	local c
	if [[ -z "$1" ]]; then
		c=0
	else
		c=$(wc -l <<< "$1")
	fi
	echo "$c"
	logExit "$c"
}

# Smart recycle strategy was inspired by Manuel Dewalds excelent article "Automating backups on a Raspberry Pi NAS"
# on https://opensource.com/article/18/8/automate-backups-raspberry-pi

function SR_listYearlyBackups() { # directory
	logEntry $SR_YEARLY $1
	if (( $SR_YEARLY > 0 )); then
		local i
		for ((i=0;i<=$(( $SR_YEARLY-1 ));i++)); do
			# today is 20191117
			# date +%Y -d "0 year ago" -> 2019
			local d=$(date +%Y -d "${i} year ago")
			ls -1 $1 | egrep "\-${BACKUPTYPE}\-backup\-$d[0-9]{2}[0-9]{2}" | grep -Ev "_" | sort -ur | tail -n 1 # find earliest yearly backup
		done
	fi
	logExit
}

function SR_listMonthlyBackups() { # directory
	logEntry $SR_MONTHLY $1
	if (( $SR_MONTHLY > 0 )); then
		local i
		for ((i=0;i<=$(( $SR_MONTHLY-1 ));i++)); do
			# ... error in date ... see http://bashworkz.com/linux-date-problem-1-month-ago-date-bug/
			# ls ${BACKUPPATH} | egrep "\-backup\-$(date +%Y%m -d "${i} month ago")[0-9]{2}" | sort -u | head -n 1
			# today is 20191117
			# date -d "$(date +%Y%m15) -0 month" +%Y%m -> 201911
			local d=$(date -d "$(date +%Y%m15) -${i} month" +%Y%m) # get month
			ls -1 $1 | egrep "\-${BACKUPTYPE}\-backup\-$d[0-9]{2}" | grep -Ev "_" | sort -ur | tail -n 1 # find earlies monthly backup
		done
	fi
	logExit
}

function SR_listWeeklyBackups() { # directory
	logEntry $SR_WEEKLY $1
	local d
	if (( $SR_WEEKLY > 0 )); then
		local i
		for ((i=0;i<=$(( $SR_WEEKLY-1));i++)); do
			# assume today is 20191119 (tue) or wed-sun
			# last monday is date +%Y%m%d -d "last monday -1...n-1 weeks" -> 20191111
			local last="last"
			# assume today is 20191118 (mon)
			# last monday is date +%Y%m%d -d "monday -1...n-1 weeks" -> 20191111
			if (( $(date +"%u") == 1 )); then
				last=""
			fi
			local mon=$(date +%Y%m%d -d "$last monday -${i} weeks") # calculate monday of week
			local dl=""
			for ((d=0;d<=6;d++)); do	# now build list of week days of week (mon-sun)
				dl="\-${BACKUPTYPE}\-backup\-$(date +%Y%m%d -d "$mon + $d day") $dl"
			done
			ls -1 $1 | grep -e "$(echo -n $dl | sed "s/ /\\\|/g")" | grep -Ev "_" | sort -ur | tail -n 1 # use earliest backup of this week
		done
	fi
	logExit
}

function SR_listDailyBackups() { # directory
	logEntry $SR_DAILY $1
	if (( $SR_DAILY > 0 )); then
		local i
		for ((i=0;i<=$(( $SR_DAILY-1));i++)); do
			# today is 20191117
			# date +%Y%m%d -d "-1 day" -> 20191116
			local d=$(date +%Y%m%d -d "-${i} day") # get day
			ls -1 $1 | grep "\-${BACKUPTYPE}\-backup\-$d" | grep -Ev "_" | sort -ur | head -n 1 # find most current backup of this day
		done
	fi
	logExit
}

function SR_getAllBackups() { # directory
	logEntry $1
	local yb="$(SR_listYearlyBackups $1)"
	logItem "$yb"
	local ybc="$(countLines "$yb")"
	[[ -n "$yb" ]] && echo "$yb"

	local mb="$(SR_listMonthlyBackups $1)"
	logItem "$mb"
	local mbc="$(countLines "$mb")"
	[[ -n "$mb" ]] && echo "$mb"

	local wb="$(SR_listWeeklyBackups $1)"
	logItem "$wb"
	local wbc="$(countLines "$wb")"
	[[ -n "$wb" ]] && echo "$wb"

	local db="$(SR_listDailyBackups $1)"
	logItem "$db"
	local dbc="$(countLines "$db")"
	[[ -n "$db" ]] && echo "$db"

	logExit
}

function SR_listUniqueBackups() { #directory
	logEntry $1
	local r="$(SR_getAllBackups "$1" | grep -Ev "_" | sort -u )"
	local rc="$(countLines "$r")"
	logItem "$r"
	echo "$r"
	logExit "$rc"
}

function SR_listBackupsToDelete() { # directory
	logEntry $1
	local r="$(ls -1 $1 | grep -v -e "$(echo -n $(SR_listUniqueBackups "$1") -e "_" | sed "s/ /\\\|/g")" | grep "\-${BACKUPTYPE}\-backup\-" )" # make sure to delete only backup type files
	local rc="$(countLines "$r")"
	logItem "$r"
	echo "$r"
	logExit "$rc"
}

function check4RequiredCommands() {

	logEntry

	local missing_commands missing_packages

	for cmd in "${!REQUIRED_COMMANDS[@]}"; do
		if ! hash $cmd 2>/dev/null; then
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
#	_prepare_locking()  { eval "exec $LOCKFD>\"$LOCKFILE\""; trap _no_more_locking EXIT; }
	_prepare_locking()  { eval "exec $LOCKFD>\"$LOCKFILE\"" ; }

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
	[ -z "$DEFAULT_EMAIL" ] && DEFAULT_EMAIL="no"
	echo "-b {dd block size} (default: $DEFAULT_DD_BLOCKSIZE)"
	[ -z "$DEFAULT_DD_PARMS" ] && DEFAULT_DD_PARMS="no"
	echo "-D \"{additional dd parameters}\" (default: $DEFAULT_DD_PARMS)"
	echo "-e {email address} (default: $DEFAULT_EMAIL)"
	[ -z "$DEFAULT_EMAIL_PARMS" ] && DEFAULT_EMAIL_PARMS="no"
	echo "-E \"{additional email call parameters}\" (default: $DEFAULT_EMAIL_PARMS)"
	echo "-f {config filename}"
	echo "-g Display progress bar"
	echo "-G {message language} (${SUPPORTED_LANGUAGES[@]}) (default: $LANGUAGE)"
	echo "-h display this help text"
	echo "-l {log level} ($POSSIBLE_LOG_LEVELs) (default: ${LOG_LEVELs[$DEFAULT_LOG_LEVEL]})"
	echo "-L {log targetdirectory} ($POSSIBLE_LOG_OUTPUTs) (default: ${LOG_OUTPUTs[$DEFAULT_LOG_OUTPUT]})"
	echo "-m {message level} ($POSSIBLE_MSG_LEVELs) (default: ${MSG_LEVELs[$DEFAULT_MSG_LEVEL]})"
	echo "-M {backup description of snapshot}"
	echo "-n notification if there is a newer scriptversion available for download (default: ${NO_YES[$DEFAULT_NOTIFY_UPDATE]})"
	echo "-s {email program to use} ($SUPPORTED_MAIL_PROGRAMS) (default: $DEFAULT_MAIL_PROGRAM)"
	echo "--timestamps Prefix messages with timestamps (default: ${NO_YES[$DEFAULT_TIMESTAMPS]})"
	echo "-u \"{excludeList}\" List of directories to exclude from tar and rsync backup"
	echo "-U current script version will be replaced by the most recent version. Current version will be saved and can be restored with parameter -V"
	echo "-v verbose output of backup tools (default: ${NO_YES[$DEFAULT_VERBOSE]})"
	echo "-V restore a previous version"
	echo "-z compress DD and TAR backup file with gzip (default: ${NO_YES[$DEFAULT_ZIP_BACKUP]})"
	echo ""
	echo "-Backup options-"
	[ -z "$DEFAULT_STOPSERVICES" ] && DEFAULT_STOPSERVICES="no"
	echo "-a \"{commands to execute after Backup}\" (default: $DEFAULT_STARTSERVICES)"
	echo "-B Save bootpartition in tar file (Default: $DEFAULT_TAR_BOOT_PARTITION_ENABLED)"
 	echo "-F Backup is simulated"
	echo "-k {backupsToKeep} (default: $DEFAULT_KEEPBACKUPS)"
	[ -z "$DEFAULT_STARTSERVICES" ] && DEFAULT_STARTSERVICES="no"
	echo "-o \"{commands to execute before Backup}\" (default: $DEFAULT_STOPSERVICES)"
	echo "-t {backupType} ($ALLOWED_TYPES) (default: $DEFAULT_BACKUPTYPE)"
	echo "-T \"{List of partitions to save}\" (Partition numbers, e.g. \"1 2 3\"). Only valid with parameter -P (default: ${DEFAULT_PARTITIONS_TO_BACKUP})"
	echo ""
	echo "-Restore options-"
	echo "-0 SD card will not be formatted"
	echo "-1 Formatting errors on SD card will be ignored"
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
	[ -z "$DEFAULT_EMAIL" ] && DEFAULT_EMAIL="nein"
	echo "-b {dd Blockgröße} (Standard: $DEFAULT_DD_BLOCKSIZE)"
	[ -z "$DEFAULT_DD_PARMS" ] && DEFAULT_DD_PARMS="nein"
	echo "-D \"{Zusätzliche dd Parameter}\" (Standard: $DEFAULT_DD_PARMS)"
	echo "-e {eMail Addresse} (Standard: $DEFAULT_EMAIL)"
	[ -z "$DEFAULT_EMAIL_PARMS" ] && DEFAULT_EMAIL_PARMS="nein"
	echo "-E \"{Zusätzliche eMail Aufrufparameter}\" (Standard: $DEFAULT_EMAIL_PARMS)"
	echo "-f {Konfig Dateiname}"
	echo "-g Anzeige des Fortschritts"
	echo "-G {Meldungssprache} (${SUPPORTED_LANGUAGES[@]}) (Standard: $LANGUAGE)"
	echo "-h Anzeige dieses Hilfstextes"
	echo "-l {log Genauigkeit} ($POSSIBLE_LOG_LEVELs) (Standard: ${LOG_LEVELs[$DEFAULT_LOG_LEVEL]})"
	echo "-L {log Zielverzeichnis} ($POSSIBLE_LOG_OUTPUTs) (default: ${LOG_OUTPUTs[$DEFAULT_LOG_OUTPUT]})"
	echo "-m {Meldungsgenauigkeit} ($POSSIBLE_MSG_LEVELs) (Standard: ${MSG_LEVELs[$DEFAULT_MSG_LEVEL]})"
	echo "-M {Backup Beschreibung des Snapshots}"
	echo "-n Benachrichtigung wenn eine aktuellere Scriptversion zum download verfügbar ist. (Standard: ${NO_YES[$DEFAULT_NOTIFY_UPDATE]})"
	echo "-s {Benutztes eMail Program} ($SUPPORTED_MAIL_PROGRAMS) (Standard: $DEFAULT_MAIL_PROGRAM)"
	echo "--timestamps Meldungen werden mit einen Zeitstempel ausgegeben (Standard: ${NO_YES[$DEFAULT_TIMESTAMPS]})"
	echo "-u \"{excludeList}\" Liste von Verzeichnissen, die vom tar und rsync Backup auszunehmen sind"
	echo "-U Scriptversion wird durch die aktuelle Version ersetzt. Die momentane Version wird gesichert und kann mit dem Parameter -V wiederhergestellt werden"
	echo "-v Detailierte Ausgaben der Backup Tools (Standard: ${NO_YES[$DEFAULT_VERBOSE]})"
	echo "-V Aktivierung einer älteren Skriptversion"
	echo "-z DD und TAR Backup verkleinern mit gzip (Standard: ${NO_YES[$DEFAULT_ZIP_BACKUP]})"
	echo ""
	echo "-Backup Optionen-"
	[ -z "$DEFAULT_STOPSERVICES" ] && DEFAULT_STOPSERVICES="keine"
	echo "-a \"{Befehle die nach dem Backup ausgeführt werden}\" (Standard: $DEFAULT_STARTSERVICES)"
	echo "-B Sicherung der Bootpartition als tar file (Standard: $DEFAULT_TAR_BOOT_PARTITION_ENABLED)"
  	echo "-F Backup wird nur simuliert"
	echo "-k {Anzahl Backups} (Standard: $DEFAULT_KEEPBACKUPS)"
	[ -z "$DEFAULT_STARTSERVICES" ] && DEFAULT_STARTSERVICES="keine"
	echo "-o \"{Befehle die vor dem Backup ausgeführt werden}\" (Standard: $DEFAULT_STOPSERVICES)"
	echo "-t {Backuptyp} ($ALLOWED_TYPES) (Standard: $DEFAULT_BACKUPTYPE)"
	echo "-T \"Liste der Partitionen die zu Sichern sind}\" (Partitionsnummern, z.B. \"1 2 3\"). Nur gültig zusammen mit Parameter -P (Standard: ${DEFAULT_PARTITIONS_TO_BACKUP})"
	echo ""
	echo "-Restore Optionen-"
	echo "-0 Keine Formatierung der SD Karte"
	echo "-1 Fehler bei der Formatierung der SD Karte werden ignoriert"
	[ -z "$DEFAULT_RESTORE_DEVICE" ] && DEFAULT_RESTORE_DEVICE="keiner"
	echo "-C Beim Formatieren der Restorepartitionen wird auf Badblocks geprüft (Standard: $DEFAULT_CHECK_FOR_BAD_BLOCKS)"
	echo "-d {restoreGerät} (Standard: $DEFAULT_RESTORE_DEVICE) (Beispiel: /dev/sda)"
	echo "-R {rootPartition} (Standard: restoreDevice) (Beispiel: /dev/sdb1)"
	echo "--resizeRootFS (Standard: ${NO_YES[$DEFAULT_RESIZE_ROOTFS]})"
}

function usageFI() {
	echo "$GIT_CODEVERSION"
	echo "Käyttö: $MYSELF [valinta]* {varmuuskopionPolku}"
	echo ""
	echo "-Yleiset asetukset-"
	[ -z "$DEFAULT_EMAIL" ] && DEFAULT_EMAIL="ei"
	echo "-b {dd lohkon koko} (oletus: $DEFAULT_DD_BLOCKSIZE)"
	[ -z "$DEFAULT_DD_PARMS" ] && DEFAULT_DD_PARMS="ei"
	echo "-D \"{dd lisäparametrit}\" (oletus: $DEFAULT_DD_PARMS)"
	echo "-e {sähköpostiosoite} (oletus: $DEFAULT_EMAIL)"
	[ -z "$DEFAULT_EMAIL_PARMS" ] && DEFAULT_EMAIL_PARMS="ei"
	echo "-E \"{sähköpostitoiminnon lisäparametrit}\" (oletus: $DEFAULT_EMAIL_PARMS)"
	echo "-f {asetustiedoston tiedostonimi}"
	echo "-g Näytä edistymispalkki"
	echo "-G {viestien kieli} (${SUPPORTED_LANGUAGES[@]}) (oletus: $LANGUAGE)"
	echo "-h Näytä tämä ohje"
	echo "-l {lokitaso} ($POSSIBLE_LOG_LEVELs_) (oletus: ${LOG_LEVELs[$DEFAULT_LOG_LEVEL]})"
	echo "-m {viestitaso} ($POSSIBLE_MSG_LEVELs) (oletus: ${MSG_LEVELs[$DEFAULT_MSG_LEVEL]})"
	echo "-M {varmuuskopion selite}"
	echo "-n Ilmoita, jos skriptistä on uusi versio ladattavissa (oletus: ${NO_YES[$DEFAULT_NOTIFY_UPDATE]})"
	echo "-s {käytettävä sähköpostiohjelma} ($SUPPORTED_MAIL_PROGRAMS) (oletus: $DEFAULT_MAIL_PROGRAM)"
	echo "--timestamps Lisää aikaleima viestien alkuun (oletus: ${NO_YES[$DEFAULT_TIMESTAMPS]})"
	echo "-u \"{excludeList}\" Lista hakemistoista, jotka ohitetaan tar- ja rsync-varmuuskopioissa"
	echo "-U Nykyinen skriptin versio korvataan uusimmalla versiolla. Nykyinen versio varmuuskopioidaan ja sen voi palauttaa parametrillä -V"
	echo "-v Sanallista varmuuskopiotyökalujen tilatiedot (oletus: ${NO_YES[$DEFAULT_VERBOSE]})"
	echo "-V Palauta skriptin edellinen versio"
	echo "-z Pakkaa varmuuskopiotiedosto käyttäen gzip:iä (oletus: ${NO_YES[$DEFAULT_ZIP_BACKUP]})"
	echo ""
	echo "-Varmuuskopioinnin valinnat-"
	[ -z "$DEFAULT_STOPSERVICES" ] && DEFAULT_STOPSERVICES="ei"
	echo "-a \"{varmuuskopion jläkeen suoritettavat komennot}\" (oletus: $DEFAULT_STARTSERVICES)"
	echo "-B Tee käynnistysosiosta kopio tar tiedostoon (oletus: $DEFAULT_TAR_BOOT_PARTITION_ENABLED)"
 	echo "-F Varmuuskopioinnin simulointi"
	echo "-k {säilytettävien varmuuskopioiden lkm} (oletus: $DEFAULT_KEEPBACKUPS)"
	[ -z "$DEFAULT_STARTSERVICES" ] && DEFAULT_STARTSERVICES="ei"
	echo "-o \"{ennen varmuuskopiointia suoritettavat komennot}\" (oletus: $DEFAULT_STOPSERVICES)"
	echo "-t {varmuuskopion tyyppi} ($ALLOWED_TYPES) (oletus: $DEFAULT_BACKUPTYPE)"
	echo "-T \"{Lista kopioitavista osioista}\" (Osionumerot, esim. \"1 2 3\"). Valinta käytettävissä vain parametrin -P kanssa (oletus: ${DEFAULT_PARTITIONS_TO_BACKUP})"
	echo ""
	echo "-Palautuksen valinnat-"
	echo "-0 SD-korttia ei alusteta"
	echo "-1 SD-kortin alustuksen virheet ohitetaan"
	[ -z "$DEFAULT_RESTORE_DEVICE" ] && DEFAULT_RESTORE_DEVICE="ei"
	echo "-C Tarkistetaan palautettavien osioiden epäkelvot lohkot (oletus: $DEFAULT_CHECK_FOR_BAD_BLOCKS)"
	echo "-d {palautuslaite} (oletus: $DEFAULT_RESTORE_DEVICE) (Esimerkki: /dev/sda)"
	echo "-R {juuriosio} (oletus: restoreDevice) (Esimerkki: /dev/sdb1)"
	echo "--resizeRootFS (oletus: ${NO_YES[$DEFAULT_RESIZE_ROOTFS]})"
}

function mentionHelp() {
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_MENTION_HELP $MYSELF
}

# there is an issue when a parameter starts with "-" which may a new option
# Workaround1: if parameter contains at least one space it's considered as a parameter and not an option even the string starts with '-'
# Workaround2: prefix parameter with \ (has to be \\ in bash commandline)

function checkOptionParameter() { # option parameter

	logEntry "$@"

	local nospaces="${2/ /}"
	if [[ "$nospaces" != "$2" ]]; then
		echo "$2"
		logExit "$2"
		return 0
	fi

	if [[ "${2:0:1}" == "\\" ]]; then
		echo "${2:1}"
		logExit "${2:1}"
		return 0
	elif [[ "$2" =~ ^(\-|\+|\-\-|\+\+) || -z "$2" ]]; then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_OPTION_REQUIRES_PARAMETER "$1"
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_MENTION_HELP $MYSELF
		echo ""
		logExit ""
		return 1
	fi
	echo "$2"
	logExit "$2"
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

# misc other vars

BACKUP_DIRECTORY_NAME=""
BACKUPFILE=""
CUSTOM_CONFIG_FILE_INCLUDED=0
DEPLOY=0
DYNAMIC_MOUNT_EXECUTED=0
EXCLUDE_DD=0
FAKE=0
FORCE_SFDISK=0
FORCE_UPDATE=0
HELP=0
[[ "${BASH_SOURCE[0]}" -ef "$0" ]]
INCLUDE_ONLY=$?
IS_UBUNTU=0
NO_YES_QUESTION=0
PROGRESS=0
REGRESSION_TEST=0
RESTORE=0
RESTOREFILE=""
RESTORETEST_REQUIRED=0
REVERT=0
ROOT_PARTITION_DEFINED=0
SHARED_BOOT_DIRECTORY=0
SKIP_SFDISK=0
UPDATE_MYSELF=0
UPDATE_POSSIBLE=0
VERSION_DEPRECATED=0
WARNING_MESSAGE_WRITTEN=0
CLEANUP_RC=0
UPDATE_CONFIG=0
UNSUPPORTED_ENVIRONMENT="${UNSUPPORTED_ENVIRONMENT:=0}"
rc=0

PARAMS=""

# initialize default config
initializeDefaultConfigVariables
# assign default config to variables
copyDefaultConfigVariables

##### Now do your job

# handle options which don't require root access
if (( $# == 1 )); then
	if [[ $1 == "-h" || $1 == "--help" || $1 == "--version" || $1 == "-?" ]]; then
		LOG_LEVEL=$LOG_NONE
		case "$1" in
			--version)
				echo "Version: $VERSION CommitSHA: $GIT_COMMIT_ONLY CommitDate: $GIT_DATE_ONLY CommitTime: $GIT_TIME_ONLY"
				exitNormal
				;;
		*)	usage
			exitNormal
			;;
		esac
	fi
fi

if (( $UID != 0 && ! INCLUDE_ONLY )); then
	LOG_LEVEL=$LOG_NONE
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_RUNASROOT "$0" "$INVOCATIONPARMS"
	exitError $RC_MISC_ERROR
fi

logEnable
lockingFramework

trapWithArg cleanupStartup SIGINT SIGTERM EXIT

INVOCATIONPARMS=""			# save passed opts for logging
for (( i=1; i<=$#; i++ )); do
	p=${!i}
	INVOCATIONPARMS="$INVOCATIONPARMS $p"
done

readConfigParameters				# overwrite defaults with settings in config files
copyDefaultConfigVariables			# and update variables with config file contents

logOptions "Standard option files"

# check if language was overwritten by config option
if [[ -n $DEFAULT_LANGUAGE ]]; then
	if ! containsElement "${DEFAULT_LANGUAGE}" "${SUPPORTED_LANGUAGES[@]}"; then
		DEFAULT_LANGUAGE="$MSG_LANG_FALLBACK"	# unsupported language, fall back to English
	else
		DEFAULT_LANGUAGE="${DEFAULT_LANGUAGE^^*}"
	fi
	LANGUAGE=$DEFAULT_LANGUAGE			# redefine language now
fi

ARG_BAK=("$@")				# save invocation options

while (( "$#" )); do		# check if option -f was used
  case "$1" in
	-f)
		o=$(checkOptionParameter "$1" "$2")
		(( $? )) && exitError $RC_PARAMETER_ERROR
		CUSTOM_CONFIG_FILE="$o"; shift 2
		if [[ ! -f "$CUSTOM_CONFIG_FILE" ]]; then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_ARG_NOT_FOUND "$CUSTOM_CONFIG_FILE"
			exitError $RC_MISSING_FILES
		fi
		CUSTOM_CONFIG_FILE="$(readlink -f "$CUSTOM_CONFIG_FILE")"
		set -e
		. "$CUSTOM_CONFIG_FILE"
		set +e
		CUSTOM_CONFIG_FILE_INCLUDED=1
		CUSTOM_CONFIG_FILE_VERSION="$(extractVersionFromFile "$CUSTOM_CONFIG_FILE" "$VERSION_CONFIG_VARNAME" )"
		logItem "Read config ${CUSTOM_CONFIG_FILE} : ${CUSTOM_CONFIG_FILE_VERSION}$NL$(egrep -v '^\s*$|^#' $CUSTOM_CONFIG_FILE)"

		copyDefaultConfigVariables		# update variables with custom file contents
		logOptions "Custome option file"
		;;
	*)	shift									# skip option
		;;
	esac
done

set -- "${ARG_BAK[@]}"		# restore all options for second options pass

while (( "$#" )); do

  case "$1" in
	-0|-0[-+])
	  SKIP_SFDISK=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-1|-1[-+])
	  FORCE_SFDISK=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-a)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  STARTSERVICES="$o"; shift 2
	  ;;

	-A|-A[-+])
	  APPEND_LOG=$(getEnableDisableOption "$1"); shift 1
	  writeToConsole $MSG_LEVEL_MINIMAL $MSG_DEPRECATED_OPTION "-A"
	  ;;

	-b)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  DD_BLOCKSIZE="$o"; shift 2
	  ;;

	-B|-B[-+])
	  TAR_BOOT_PARTITION_ENABLED=$(getEnableDisableOption "$1"); shift 1
	  ;;

	--bootDevice)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  BOOT_DEVICE="$o"; shift 2
	  ;;

	-c|-c[-+])
	  SKIPLOCALCHECK=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-C|-C[-+])
	  CHECK_FOR_BAD_BLOCKS=$(getEnableDisableOption "$1"); shift 1
	  ;;

	--coloring)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  COLORING="$o"; shift 2
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

	--dynamicMount)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  DYNAMIC_MOUNT="$o"; shift 2
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

	--eMailColoring)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  EMAIL_COLORING="${o^^}"; shift 2
	  ;;

	-f) shift 2
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
	  if ! containsElement "${LANGUAGE^^*}" "${SUPPORTED_LANGUAGES[@]}"; then
		  writeToConsole $MSG_LEVEL_MINIMAL $MSG_LANGUAGE_NOT_SUPPORTED $LANGUAGE
		  exitError $RC_PARAMETER_ERROR
	  fi
	  ;;

	-h|--help)
	  HELP=1; break
	  ;;

	--ignoreAdditionalPartitions|--ignoreAdditionalPartitions[+-])
	  IGNORE_ADDITIONAL_PARTITIONS=$(getEnableDisableOption "$1"); shift 1
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
	  checkImportantParameters
	  ;;

	-L)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  LOG_OUTPUT="$o"; shift 2
	  checkImportantParameters
	  ;;

	-m)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  MSG_LEVEL="$o"; shift 2
	  checkImportantParameters
	  ;;

	-M)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  BACKUP_DIRECTORY_NAME="$o"; shift 2
  	  BACKUP_DIRECTORY_NAME=${BACKUP_DIRECTORY_NAME//[ \/\\\:\.\-]/_}
  	  ;;

	-n|-n[-+])
	  NOTIFY_UPDATE=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-N)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  EXTENSIONS="$o"; shift 2
	  ;;

	--notifyStart|--notifyStart[-+])
	  NOTIFY_START=$(getEnableDisableOption "$1"); shift 1
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

	--rebootSystem|--rebootSystem[+-])
	  REBOOT_SYSTEM=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-s)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  EMAIL_PROGRAM="$o"; shift 2
	  ;;

	-S|-S[-+])
	  FORCE_UPDATE=$(getEnableDisableOption "$1"); shift 1
	  ;;

	--smartRecycle|--smartRecycle[+-])
	  SMART_RECYCLE=$(getEnableDisableOption "$1"); shift 1
	  ;;

	--smartRecycleDryrun|--smartRecycleDryrun[+-])
	  SMART_RECYCLE_DRYRUN=$(getEnableDisableOption "$1"); shift 1
	  ;;

	--smartRecycleOptions)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  SMART_RECYCLE_OPTIONS="$o"; shift 2
	  ;;

	--systemstatus|--systemstatus[+-])
	  SYSTEMSTATUS=$(getEnableDisableOption "$1"); shift 1
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
	  o="$(checkOptionParameter "$1" "$2")"
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  PARTITIONS_TO_BACKUP="$o"; shift 2
	  ;;

	--telegramToken)
	  o="$(checkOptionParameter "$1" "$2")"
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  TELEGRAM_TOKEN="$o"; shift 2
	  ;;

	--telegramChatID)
	  o="$(checkOptionParameter "$1" "$2")"
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  TELEGRAM_CHATID="$o"; shift 2
	  ;;

	--telegramNotifications)
	  o="$(checkOptionParameter "$1" "$2")"
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  TELEGRAM_NOTIFICATIONS="$o"; shift 2
	  ;;

	-u)
	  o=$(checkOptionParameter "$1" "$2")
	  (( $? )) && exitError $RC_PARAMETER_ERROR
	  EXCLUDE_LIST="$o"; shift 2
	  ;;

	-U)
	  UPDATE_MYSELF=1; shift 1
	  ;;

	--unsupportedEnvironment|--use)
	  UNSUPPORTED_ENVIRONMENT=$(getEnableDisableOption "$1"); shift 1
	  ;;

	--updateConfig|--updateConfig[+-])
	  UPDATE_CONFIG=$(getEnableDisableOption "$1"); shift 1
	  ;;

	--updateUUIDs|--updateUUIDs[+-])
	  UPDATE_UUIDS=$(getEnableDisableOption "$1"); shift 1
	  ;;

	-v|-v[-+])
	  VERBOSE=$(getEnableDisableOption "$1"); shift 1
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

	-Z|-Z[-+]) # flag to enable regession test pathes
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
	  [[ -z "$PARAMS" ]] && PARAMS="$1" || PARAMS="$PARAMS $1"
	  shift
	  ;;
  esac
done

if (( ! $INCLUDE_ONLY )); then

# set positional arguments in argument list $@
set -- "$PARAMS"

if (( $RESTORE )); then
	rstFileName="${LOG_FILE/$LOGFILE_EXT/$LOGFILE_RESTORE_EXT}"
	LOG_FILE="$rstFileName"
	LOGFILE_EXT="$LOGFILE_RESTORE_EXT"
	rstFileName="${MSG_FILE/$MSGFILE_EXT/$MSGFILE_RESTORE_EXT}"
	MSG_FILE="$rstFileName"
	MSGFILE_EXT="$MSGFILE_RESTORE_EXT"
fi

if (( ! $RESTORE )); then
	exlock_now
	if (( $? )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_INSTANCE_ACTIVE
		exitError $RC_MISC_ERROR
	fi
fi

fileParameter="$1"
if hasSpaces "$fileParameter"; then
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_FILE_CONTAINS_SPACES "$fileParameter"
	exitError $RC_MISC_ERROR
fi

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

if [[ -n "$unusedParms" ]]; then
	usage
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNUSED_PARAMETERS "$unusedParms"
	exitError $RC_PARAMETER_ERROR
fi

if ! isSupportedEnvironment; then
	if (( $UNSUPPORTED_ENVIRONMENT )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNSUPPORTED_ENVIRONMENT_CONFIRMED
	else
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNSUPPORTED_ENVIRONMENT
		exitError $RC_UNSUPPORTED_ENVIRONMENT
	fi
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
	if (( $? )); then
		updateConfig
	fi
	exitNormal
fi

if (( $NO_YES_QUESTION )); then				# WARNING: dangerous option !!!
	if [[ ! $RESTORE_DEVICE =~ $YES_NO_RESTORE_DEVICE ]]; then	# make sure we're not killing a disk by accident
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_YES_NO_DEVICE_MISMATCH $RESTORE_DEVICE $YES_NO_RESTORE_DEVICE
		exitError $RC_MISC_ERROR
	fi
fi

check4RequiredCommands

if (( $UPDATE_CONFIG )); then
	updateConfig
	exitNormal
fi

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

_prepare_locking
logItem "Enabling trap handler"
trapWithArg cleanup SIGINT SIGTERM EXIT
lockMe

writeToConsole $MSG_LEVEL_MINIMAL $MSG_STARTED "$HOSTNAME" "$MYSELF" "$VERSION" "$GIT_DATE_ONLY" "$GIT_COMMIT_ONLY" "$(date)"
logger -t $MYSELF "Started $VERSION ($GIT_COMMIT_ONLY)"

(( $IS_BETA )) && writeToConsole $MSG_LEVEL_MINIMAL $MSG_INTRO_BETA_MESSAGE
(( $IS_DEV )) && writeToConsole $MSG_LEVEL_MINIMAL $MSG_INTRO_DEV_MESSAGE
(( $IS_HOTFIX )) && writeToConsole $MSG_LEVEL_MINIMAL $MSG_INTRO_HOTFIX_MESSAGE

setupEnvironment

if (( $NOTIFY_START )); then
	if (( ! $RESTORE )); then
		msg="$(getMessage $MSG_TITLE_STARTED "$HOSTNAME")"
		if [[ -n "$EMAIL"  ]]; then
			sendEMail "" "$msg"
		fi
		if [[ -n "$TELEGRAM_TOKEN"  ]]; then
			sendTelegramm "$msg"
		fi
		if [[ -n "$PUSHOVER_USER"  ]]; then
			sendPushover "$msg"
		fi
		if [[ -n "$SLACK_WEBHOOK_URL"  ]]; then
			sendSlack "$msg"
		fi

		callNotificationExtension $rc

	fi
fi


if (( $ETC_CONFIG_FILE_INCLUDED )); then
	writeToConsole $MSG_LEVEL_DETAILED $MSG_INCLUDED_CONFIG "$ETC_CONFIG_FILE" # "$ETC_CONFIG_FILE_VERSION"
	logItem "Read config ${ETC_CONFIG_FILE} : ${ETC_CONFIG_FILE_VERSION}$NL$(egrep -v '^\s*$|^#' $ETC_CONFIG_FILE)"
fi
if (( $HOME_CONFIG_FILE_INCLUDED )); then
	writeToConsole $MSG_LEVEL_DETAILED $MSG_INCLUDED_CONFIG "$HOME_CONFIG_FILE" # "$HOME_CONFIG_FILE_VERSION"
	logItem "Read config ${HOME_CONFIG_FILE} : ${HOME_CONFIG_FILE_VERSION}$NL$(egrep -v '^\s*$|^#' $HOME_CONFIG_FILE)"
fi
if (( $CURRENTDIR_CONFIG_FILE_INCLUDED )); then
	writeToConsole $MSG_LEVEL_DETAILED $MSG_INCLUDED_CONFIG "$CURRENTDIR_CONFIG_FILE" # "$CURRENTDIR_CONFIG_FILE_VERSION"
	logItem "Read ${CURRENTDIR_CONFIG_FILE} : ${CURRENTDIR_CONFIG_FILE_VERSION}$NL$(egrep -v '^\s*$|^#' $CURRENTDIR_CONFIG_FILE)"
fi

if (( $CUSTOM_CONFIG_FILE_INCLUDED )); then
	writeToConsole $MSG_LEVEL_DETAILED $MSG_INCLUDED_CONFIG "$CUSTOM_CONFIG_FILE" # "$CUSTOM_CONFIG_FILE_VERSION"
	logItem "Read ${CUSTOM_CONFIG_FILE} : ${CUSTOM_CONFIG_FILE_VERSION}$NL$(egrep -v '^\s*$|^#' $CUSTOM_CONFIG_FILE)"
fi

logOptions "Invocation options"
logSystem

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

doit # no return

fi # ! INCLUDE_ONLY
