#!/bin/bash
#######################################################################################################################
#
# Script to download, install, configure and uninstall raspiBackup.sh using windows.
# Commandline installation is also possible. Use option -h to get a list of all options.
#
# Visit http://www.linux-tips-and-tricks.de/raspiBackup for latest code and other details
#
# Credits to following people for their translation work
#	  FI - teemue
#	  ZH - GoogleBeEvil
#	  FR - mgrafr
#
#######################################################################################################################
#
#    Copyright (c) 2015-2023 framp at linux-tips-and-tricks dot de
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

if [ -z "$BASH_VERSION" ] ;then
	echo "??? ERROR: Unable to execute script. bash interpreter missing."
	echo "??? DEBUG: $(lsof -a -p $$ -d txt | tail -n 1)"
	exit 127
fi

[[ "$(ps --no-headers -o comm 1)" != "systemd" ]]
: "${SYSTEMD_DETECTED:=$?}" # just disable some code for debugging

: "${RASPIBACKUP_INSTALL_DEBUG:=0}" # just disable some code for debugging

MYSELF="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"					# use linked script name if the link is used
MYNAME=${MYSELF%.*}
VERSION="0.4.8.1"							 	# -beta, -hotfix or -dev suffixes possible

if [[ (( ${BASH_VERSINFO[0]} < 4 )) || ( (( ${BASH_VERSINFO[0]} == 4 )) && (( ${BASH_VERSINFO[1]} < 3 )) ) ]]; then
	echo "bash version 0.4.3 or beyond is required by $MYSELF" # nameref feature, declare -n var=$v
	exit 1
fi

# Commands used by raspiBackup and which have to be available
# [command]=package
declare -A REQUIRED_COMMANDS=( \
		["parted"]="parted" \
		["fsck.vfat"]="dosfstools" \
		["e2label"]="e2fsprogs" \
		["rsync"]="rsync" \
		["whiptail"]="whiptail" \
		["dosfslabel"]="dosfstools" \
		["fdisk"]="fdisk" \
		["blkid"]="util-linux" \
		["sfdisk"]="fdisk" \
		)

requiredCmds=()
for cmd in ${!REQUIRED_COMMANDS[@]}; do
	if ! hash $cmd 2>/dev/null; then
		requiredCmds+=($cmd)
	fi
done

if (( ${#requiredCmds[@]} > 0 )); then
	for cmd in ${requiredCmds[@]}; do
			echo "$MYSELF depends on $cmd which is available in ${REQUIRED_COMMANDS[$cmd]}"
	done

	echo -n "Install all the missing package(s)? (Y/n) "
	read answer
	answer=${answer:0:1}		# first char only
	answer=${answer:-"y"}	# set default yes
	answer=${answer,,*}		# to lower
	if [[ ! "yj" =~ $answer ]]; then
		echo "Please install the required package(s) manually first and then invoke ./$MYSELF again."
		exit 1
	fi

	apt -y install ${requiredCmds[@]}
	if (( $? )); then
		echo "Installation of missing package(s) failed. Please install them manually and then invoke ./$MYSELF again."
		exit 1
	fi
fi

MYHOMEDOMAIN="www.linux-tips-and-tricks.de"
MYHOMEURL="https://$MYHOMEDOMAIN"

MYDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GIT_DATE="$Date$"
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<<$GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<<$GIT_DATE)
GIT_COMMIT="$Sha1$"
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<<$GIT_COMMIT | sed 's/\$//')

GIT_CODEVERSION="$MYSELF $VERSION, $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"

FILE_TO_INSTALL="raspiBackup.sh"

RASPIBACKUP_NAME=${FILE_TO_INSTALL%.*}

CURRENT_DIR=$(pwd)
NL=$'\n'
IGNORE_START_STOP_CHAR=":"
declare -A CONFIG_DOWNLOAD_FILE=(['DE']="raspiBackup_de.conf" ['EN']="raspiBackup_en.conf")
CONFIG_FILE="raspiBackup.conf"
SAMPLEEXTENSION_TAR_FILE="raspiBackupSampleExtensions.tgz"
DEFAULT_IFS="$IFS"
MASQUERADE_STRING="@@@@"

[[ -n $URLTARGET ]] && URLTARGET="/$URLTARGET"

PROPERTY_URL="$MYHOMEURL/raspiBackup${URLTARGET}/raspiBackup.properties"
BETA_DOWNLOAD_URL="$MYHOMEURL/raspiBackup${URLTARGET}/beta/raspiBackup.sh"
PROPERTY_FILE_NAME="$MYNAME.properties"
LATEST_TEMP_PROPERTY_FILE="/tmp/$PROPERTY_FILE_NAME"
LOCAL_PROPERTY_FILE="$CURRENT_DIR/.$PROPERTY_FILE_NAME"
INSTALLER_DOWNLOAD_URL="$MYHOMEURL/raspiBackup${URLTARGET}/raspiBackupInstallUI.sh"
STABLE_CODE_URL="$FILE_TO_INSTALL"
INCLUDE_SERVICES_REGEX_FILE="/usr/local/etc/raspiBackup.iservices"
EXCLUDE_SERVICES_REGEX_FILE="/usr/local/etc/raspiBackup.eservices"

read -r -d '' CRON_CONTENTS <<-'EOF'
#
# Crontab entry for raspiBackup.sh
#
# (C) 2017-2019 framp at linux-tips-and-tricks dot de
#
# Create a backup once a week on Sunday morning at 5 am (default)
#
#0 5 * * 0	root	/usr/local/bin/raspiBackup.sh
EOF

read -r -d '' SYSTEMD_SERVICE <<-'EOF'
[Unit]
Description=Creation of a Raspberry backup with raspiBackup

[Service]
Type=simple
ExecStart=/usr/local/bin/raspiBackup.sh
# For Use with Wrapper Script: ExecStart=/usr/local/bin/raspiBackupWrapper.sh
[Install]
WantedBy=multi-user.target
EOF

read -r -d '' SYSTEMD_TIMER <<-'EOF'
[Unit]
Description=Timer for raspiBackup.service to start backup

[Timer]
OnCalendar=Sun *-*-* 05:00:42
# Create a backup once a week on Sunday morning at 5 am (default)
Unit=raspiBackup.service

[Install]
WantedBy=multi-user.target
EOF

if [[ -f $EXCLUDE_SERVICES_REGEX_FILE ]]; then
	EXCLUDE_SERVICES_REGEX="$(<$EXCLUDE_SERVICES_REGEX_FILE)"
else
read -r -d '' EXCLUDE_SERVICES_REGEX <<-'EOF'
acpid
alsa-state
avahi.*
argononed
bluetooth
colord
dbus
dhcpcd
hciuart
kernel.*
LightDM
lvm.*
ModemManager
nfs-
ntp
rng-tools
rpcbind
rsyslog
ssh
smartd
smartmontools
systemd-.*
thermald
triggerhappy
udisks.*
unattended.*
upower
wpa_supplicant
.*@.*
EOF
fi

if [[ -f $INCLUDE_SERVICES_REGEX_FILE ]]; then
	INCLUDE_SERVICES_REGEX="$(<$INCLUDE_SERVICES_REGEX_FILE)"
else
read -r -d '' INCLUDE_SERVICES_REGEX <<-'EOF'
apache.*
containerd
cron
cups
fhem
influxd
iobroker
lighttpd
minidlna
mysql
mariadb
nfs-kernel-server
nmbd
nginx
smbd
snapd
wordpress
EOF
fi

DOWNLOAD_TIMEOUT=60 # seconds
DOWNLOAD_RETRIES=3

BIN_DIR="/usr/local/bin"
ETC_DIR="/usr/local/etc"
CRON_DIR="/etc/cron.d"
LOG_FILE="$MYNAME.log"
SYSTEMD_DIR="/etc/systemd/system"

CONFIG_FILE_ABS_PATH="$ETC_DIR"
CONFIG_ABS_FILE="$CONFIG_FILE_ABS_PATH/$CONFIG_FILE"
FILE_TO_INSTALL_ABS_PATH="$BIN_DIR"
FILE_TO_INSTALL_ABS_FILE="$FILE_TO_INSTALL_ABS_PATH/$FILE_TO_INSTALL"
CRON_ABS_FILE="$CRON_DIR/$RASPIBACKUP_NAME"

SYSTEMD_SERVICE_FILE_NAME="${RASPIBACKUP_NAME}.service"
SYSTEMD_SERVICE_ABS_FILE="$SYSTEMD_DIR/$SYSTEMD_SERVICE_FILE_NAME"
SYSTEMD_TIMER_FILE_NAME="${RASPIBACKUP_NAME}.timer"
SYSTEMD_TIMER_ABS_FILE="$SYSTEMD_DIR/$SYSTEMD_TIMER_FILE_NAME"

INSTALLER_ABS_PATH="$BIN_DIR"
INSTALLER_ABS_FILE="$INSTALLER_ABS_PATH/$MYSELF"
VAR_LIB_DIRECTORY="/var/lib/$RASPIBACKUP_NAME"

PROPERTY_REGEX='.*="([^"]*)"'

# borrowed from http://stackoverflow.com/questions/3685970/check-if-an-array-contains-a-value

function containsElement () {
  local e
  for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
  return 1
}

#
# NLS: Either use system language if language is supported and use English otherwise
#

SUPPORTED_LANGUAGES=("EN" "DE" "FI" "FR" "ZH")

[[ -z "${LANG}" ]] && LANG="en_US.UTF-8"
LANG_EXT="${LANG^^*}"
LANG_SYSTEM="${LANG_EXT:0:2}"
if ! containsElement "${LANG_SYSTEM^^*}" "${SUPPORTED_LANGUAGES[@]}"; then
	LANG_SYSTEM="EN"
fi

# default configs

CONFIG_LANGUAGE=$LANG_SYSTEM
# CONFIG_LANGUAGE= will become the configured language later on

CONFIG_MSG_LEVEL="0"
CONFIG_BACKUPTYPE="rsync"
CONFIG_KEEPBACKUPS="3"
DEFAULT_CONFIG_SMART_RECYCLE="0"
CONFIG_SMART_RECYCLE="$DEFAULT_CONFIG_SMART_RECYCLE"
DEFAULT_CONFIG_SMART_RECYCLE_OPTIONS="7 4 12 1"
CONFIG_SMART_RECYCLE_OPTIONS="$DEFAULT_CONFIG_SMART_RECYCLE_OPTIONS"
DEFAULT_CONFIG_SMART_RECYCLE_DRYRUN="1"
CONFIG_SMART_RECYCLE_DRYRUN="$DEFAULT_CONFIG_SMART_RECYCLE_DRYRUN"
CONFIG_BACKUPPATH="/backup"
CONFIG_PARTITIONBASED_BACKUP="0"
DEFAULT_CONFIG_PARTITIONS_TO_BACKUP="1 2"
CONFIG_PARTITIONS_TO_BACKUP="$DEFAULT_CONFIG_PARTITIONS_TO_BACKUP"
CONFIG_ZIP_BACKUP="0"
CONFIG_CRON_HOUR="5"
CONFIG_CRON_MINUTE="0"
CONFIG_CRON_DAY="1" # Sun
CONFIG_SYSTEMD_HOUR=$CONFIG_CRON_HOUR
CONFIG_SYSTEMD_MINUTE=$CONFIG_CRON_MINUTE
CONFIG_SYSTEMD_DAY="1" # Sun
CONFIG_MAIL_PROGRAM="mail"
CONFIG_EMAIL=""
CONFIG_RESIZE_ROOTFS="1"

# Whiptail box sizes

ROWS_MSGBOX=20
ROWS_ABOUT=20
ROWS_MENU=20
WINDOW_COLS=60

#
# Messages
#
# To add a new language just execute following steps:
# 1) Add new language id LL (e.g. FI for Finnish) in variable SUPPORTED_LANGUAGES (see above)
# 2) For every MSG_ add a new message MSG_LL
#

MSG_PRF="RBI"

SCNT=0
MSG_UNDEFINED=$((SCNT++))
MSG_EN[$MSG_UNDEFINED]="${MSG_PRF}0000E: Undefined messageid."
MSG_DE[$MSG_UNDEFINED]="${MSG_PRF}0000E: Unbekannte Meldungsid."
MSG_FI[$MSG_UNDEFINED]="${MSG_PRF}0000E: Viestitunnus puuttuu."
MSG_FR[$MSG_UNDEFINED]="${MSG_PRF}0000E: ID de message non défini."
MSG_ZH[$MSG_UNDEFINED]="${MSG_PRF}0000E: 未定义的错误ID."

MSG_VERSION=$((SCNT++))
MSG_EN[$MSG_VERSION]="${MSG_PRF}0001I: %1"
MSG_DE[$MSG_VERSION]="${MSG_PRF}0001I: %1"
MSG_FI[$MSG_VERSION]="${MSG_PRF}0001I: %1"
MSG_FR[$MSG_VERSION]="${MSG_PRF}0001I: %1"
MSG_ZH[$MSG_VERSION]="${MSG_PRF}0001I: %1"

MSG_DOWNLOADING=$((SCNT++))
MSG_EN[$MSG_DOWNLOADING]="${MSG_PRF}0002I: Downloading %1..."
MSG_DE[$MSG_DOWNLOADING]="${MSG_PRF}0002I: %1 wird aus dem Netz geladen..."
MSG_FI[$MSG_DOWNLOADING]="${MSG_PRF}0002I: Ladataan %1..."
MSG_FR[$MSG_DOWNLOADING]="${MSG_PRF}0002I: Téléchargement %1..."
MSG_ZH[$MSG_DOWNLOADING]="${MSG_PRF}0002I: 下载中 %1..."

MSG_DOWNLOAD_FAILED=$((SCNT++))
MSG_EN[$MSG_DOWNLOAD_FAILED]="${MSG_PRF}0003E: Download of %1 failed. HTTP code: %2."
MSG_DE[$MSG_DOWNLOAD_FAILED]="${MSG_PRF}0003E: %1 kann nicht aus dem Netz geladen werden. HTTP code: %2."
MSG_FI[$MSG_DOWNLOAD_FAILED]="${MSG_PRF}0003E: Kohteen %1 lataus epäonnistui. HTTP-koodi: %2."
MSG_FR[$MSG_DOWNLOAD_FAILED]="${MSG_PRF}0003E: Le téléchargement de %1 a échoué. Code HTTP : %2."
MSG_ZH[$MSG_DOWNLOAD_FAILED]="${MSG_PRF}0003E: 下载 %1 失败. HTTP-代码: %2."

MSG_INSTALLATION_FAILED=$((SCNT++))
MSG_EN[$MSG_INSTALLATION_FAILED]="${MSG_PRF}0004E: Installation of %1 failed. Check %2."
MSG_DE[$MSG_INSTALLATION_FAILED]="${MSG_PRF}0004E: Installation von %1 fehlerhaft beendet. Prüfe %2."
MSG_FI[$MSG_INSTALLATION_FAILED]="${MSG_PRF}0004E: Kohteen %1 asennus epäonnistui. Tarkista %2."
MSG_FR[$MSG_INSTALLATION_FAILED]="${MSG_PRF}0004E: L'installation de %1 a échoué. Vérifiez %2."
MSG_ZH[$MSG_INSTALLATION_FAILED]="${MSG_PRF}0004E: 安装 %1 失败. 检查 %2."

MSG_SAVING_FILE=$((SCNT++))
MSG_EN[$MSG_SAVING_FILE]="${MSG_PRF}0005I: Existing file %1 saved as %2."
MSG_DE[$MSG_SAVING_FILE]="${MSG_PRF}0005I: Existierende Datei %1 wurde als %2 gesichert."
MSG_FI[$MSG_SAVING_FILE]="${MSG_PRF}0005I: Tiedosto %1 tallennettiin nimellä %2."
MSG_FR[$MSG_SAVING_FILE]="${MSG_PRF}0005I: Fichier existant %1 enregistré en tant que %2."
MSG_ZH[$MSG_SAVING_FILE]="${MSG_PRF}0005I:  %1 已存在,另存为 %2."

MSG_CHMOD_FAILED=$((SCNT++))
MSG_EN[$MSG_CHMOD_FAILED]="${MSG_PRF}0006E: chmod of %1 failed."
MSG_DE[$MSG_CHMOD_FAILED]="${MSG_PRF}0006E: chmod von %1 nicht möglich."
MSG_FI[$MSG_CHMOD_FAILED]="${MSG_PRF}0006E: chmod %1 epäonnistui."
MSG_FR[$MSG_CHMOD_FAILED]="${MSG_PRF}0006E: chmod de %1 a échoué."
MSG_ZH[$MSG_CHMOD_FAILED]="${MSG_PRF}0006E: chmod %1 失败."

MSG_MOVE_FAILED=$((SCNT++))
MSG_EN[$MSG_MOVE_FAILED]="${MSG_PRF}0007E: mv of %1 failed."
MSG_DE[$MSG_MOVE_FAILED]="${MSG_PRF}0007E: mv von %1 nicht möglich."
MSG_FI[$MSG_MOVE_FAILED]="${MSG_PRF}0007E: mv %1 epäonnistui."
MSG_FR[$MSG_MOVE_FAILED]="${MSG_PRF}0007E: Impossible de faire mv à partir de %1."
MSG_ZH[$MSG_MOVE_FAILED]="${MSG_PRF}0007E: mv %1 失败."

MSG_CLEANUP=$((SCNT++))
MSG_EN[$MSG_CLEANUP]="${MSG_PRF}0008I: Cleaning up..."
MSG_DE[$MSG_CLEANUP]="${MSG_PRF}0008I: Räume auf..."
MSG_FI[$MSG_CLEANUP]="${MSG_PRF}0008I: Puhdistetaan..."
MSG_FR[$MSG_CLEANUP]="${MSG_PRF}0008I: Nettoyer..."
MSG_ZH[$MSG_CLEANUP]="${MSG_PRF}0008I: 正在清理..."

MSG_INSTALLATION_FINISHED=$((SCNT++))
MSG_EN[$MSG_INSTALLATION_FINISHED]="${MSG_PRF}0009I: Installation of %1 finished successfully."
MSG_DE[$MSG_INSTALLATION_FINISHED]="${MSG_PRF}0009I: Installation von %1 erfolgreich beendet."
MSG_FI[$MSG_INSTALLATION_FINISHED]="${MSG_PRF}0009I: Kohde %1 asennettu onnistuneesti."
MSG_FR[$MSG_INSTALLATION_FINISHED]="${MSG_PRF}0009I: L'installation de %1 s'est terminée avec succès."
MSG_ZH[$MSG_INSTALLATION_FINISHED]="${MSG_PRF}0009I: 安装 %1 成功."

MSG_UPDATING_CONFIG=$((SCNT++))
MSG_EN[$MSG_UPDATING_CONFIG]="${MSG_PRF}0010I: Updating configuration in %1."
MSG_DE[$MSG_UPDATING_CONFIG]="${MSG_PRF}0010I: Konfigurationsdatei %1 wird angepasst."
MSG_FI[$MSG_UPDATING_CONFIG]="${MSG_PRF}0010I: Päivitetään asetukset tiedostossa %1."
MSG_FR[$MSG_UPDATING_CONFIG]="${MSG_PRF}0010I: Mise à jour de la configuration dans %1."
MSG_ZH[$MSG_UPDATING_CONFIG]="${MSG_PRF}0010I: 更新设置 %1."

MSG_DELETE_FILE=$((SCNT++))
MSG_EN[$MSG_DELETE_FILE]="${MSG_PRF}0011I: Deleting %1..."
MSG_DE[$MSG_DELETE_FILE]="${MSG_PRF}0011I: Lösche %1..."
MSG_FI[$MSG_DELETE_FILE]="${MSG_PRF}0011I: Poistetaan %1..."
MSG_FR[$MSG_DELETE_FILE]="${MSG_PRF}0011I: Suppression de %1..."
MSG_ZH[$MSG_DELETE_FILE]="${MSG_PRF}0011I: 删除 %1..."

MSG_UNINSTALL_FINISHED=$((SCNT++))
MSG_EN[$MSG_UNINSTALL_FINISHED]="${MSG_PRF}0012I: Uninstall of %1 finished successfully."
MSG_DE[$MSG_UNINSTALL_FINISHED]="${MSG_PRF}0012I: Deinstallation von %1 erfolgreich beendet."
MSG_FI[$MSG_UNINSTALL_FINISHED]="${MSG_PRF}0012I: Kohteen %1 asennus poistettu onnistuneesti."
MSG_FR[$MSG_UNINSTALL_FINISHED]="${MSG_PRF}0012I: La désinstallation de %1 s'est terminée avec succès."
MSG_ZH[$MSG_UNINSTALL_FINISHED]="${MSG_PRF}0012I: 卸载 %1 成功."

MSG_UNINSTALL_FAILED=$((SCNT++))
MSG_EN[$MSG_UNINSTALL_FAILED]="${MSG_PRF}0013E: Delete of %1 failed."
MSG_DE[$MSG_UNINSTALL_FAILED]="${MSG_PRF}0013E: Löschen von %1 fehlerhaft beendet."
MSG_FI[$MSG_UNINSTALL_FAILED]="${MSG_PRF}0013E: Kohteen %1 poisto epäonnistui."
MSG_FR[$MSG_UNINSTALL_FAILED]="${MSG_PRF}0013E: Échec de la suppression de %1."
MSG_ZH[$MSG_UNINSTALL_FAILED]="${MSG_PRF}0013E: 删除 %1 失败."

MSG_DOWNLOADING_BETA=$((SCNT++))
MSG_EN[$MSG_DOWNLOADING_BETA]="${MSG_PRF}0014I: Downloading %1 beta..."
MSG_DE[$MSG_DOWNLOADING_BETA]="${MSG_PRF}0014I: %1 beta wird aus dem Netz geladen..."
MSG_FI[$MSG_DOWNLOADING_BETA]="${MSG_PRF}0014I: Ladataan kohteen %1 beta-versiota..."
MSG_FR[$MSG_DOWNLOADING_BETA]="${MSG_PRF}0014I: Téléchargement de %1 bêta..."
MSG_ZH[$MSG_DOWNLOADING_BETA]="${MSG_PRF}0014I: 下载 %1 beta版本..."

MSG_CODE_INSTALLED=$((SCNT++))
MSG_EN[$MSG_CODE_INSTALLED]="${MSG_PRF}0015I: Created %1."
MSG_DE[$MSG_CODE_INSTALLED]="${MSG_PRF}0015I: %1 wurde erstellt."
MSG_FI[$MSG_CODE_INSTALLED]="${MSG_PRF}0015I: Kohde %1 luotu."
MSG_FR[$MSG_CODE_INSTALLED]="${MSG_PRF}0015I: %1 a été créé."
MSG_ZH[$MSG_CODE_INSTALLED]="${MSG_PRF}0015I: 创建 %1."

MSG_NOT_INSTALLED=$((SCNT++))
MSG_EN[$MSG_NOT_INSTALLED]="${MSG_PRF}0016I: %1 not installed."
MSG_DE[$MSG_NOT_INSTALLED]="${MSG_PRF}0016I: %1 nicht installiert."
MSG_FI[$MSG_NOT_INSTALLED]="${MSG_PRF}0016I: %1 ei ole asennettu."
MSG_FR[$MSG_NOT_INSTALLED]="${MSG_PRF}0016I: %1 non installé."
MSG_ZH[$MSG_NOT_INSTALLED]="${MSG_PRF}0016I: %1 未安装."

MSG_CHOWN_FAILED=$((SCNT++))
MSG_EN[$MSG_CHOWN_FAILED]="${MSG_PRF}0017E: chown of %1 failed."
MSG_DE[$MSG_CHOWN_FAILED]="${MSG_PRF}0017E: chown von %1 nicht möglich."
MSG_FI[$MSG_CHOWN_FAILED]="${MSG_PRF}0017E: chown %1 epäonnistui."
MSG_FR[$MSG_CHOWN_FAILED]="${MSG_PRF}0017E: Impossible d'exécuter chown %1."
MSG_ZH[$MSG_CHOWN_FAILED]="${MSG_PRF}0017E: chown of %1 失败."

MSG_SAMPLEEXTENSION_INSTALL_FAILED=$((SCNT++))
MSG_EN[$MSG_SAMPLEEXTENSION_INSTALL_FAILED]="${MSG_PRF}0018E: Sample extension installation failed. %1"
MSG_DE[$MSG_SAMPLEEXTENSION_INSTALL_FAILED]="${MSG_PRF}0018E: Beispielserweiterungsinstallation fehlgeschlagen. %1"
MSG_FI[$MSG_SAMPLEEXTENSION_INSTALL_FAILED]="${MSG_PRF}0018E: Näytelisäosien asennus epäonnistui. %1"
MSG_FR[$MSG_SAMPLEEXTENSION_INSTALL_FAILED]="${MSG_PRF}0018E: L'installation de l'exemple d'extension a échoué. %1"
MSG_ZH[$MSG_SAMPLEEXTENSION_INSTALL_FAILED]="${MSG_PRF}0018E: 扩展安装失败. %1"

MSG_SAMPLEEXTENSION_INSTALL_SUCCESS=$((SCNT++))
MSG_EN[$MSG_SAMPLEEXTENSION_INSTALL_SUCCESS]="${MSG_PRF}0019I: Sample extensions successfully installed and enabled."
MSG_DE[$MSG_SAMPLEEXTENSION_INSTALL_SUCCESS]="${MSG_PRF}0019I: Beispielserweiterungen erfolgreich installiert und eingeschaltet."
MSG_FI[$MSG_SAMPLEEXTENSION_INSTALL_SUCCESS]="${MSG_PRF}0019I: Näytelisäosat asennettu ja otettu käyttöön onnistuneesti."
MSG_FR[$MSG_SAMPLEEXTENSION_INSTALL_SUCCESS]="${MSG_PRF}0019I: Les exemples d'extensions ont été installés et activés avec succès."
MSG_ZH[$MSG_SAMPLEEXTENSION_INSTALL_SUCCESS]="${MSG_PRF}0019I: 扩展安装成功并激活."

MSG_INSTALLING_CRON_TEMPLATE=$((SCNT++))
MSG_EN[$MSG_INSTALLING_CRON_TEMPLATE]="${MSG_PRF}0020I: Creating cron file %1."
MSG_DE[$MSG_INSTALLING_CRON_TEMPLATE]="${MSG_PRF}0020I: Crondatei %1 wird erstellt."
MSG_FI[$MSG_INSTALLING_CRON_TEMPLATE]="${MSG_PRF}0020I: Luodaan cron-tiedosto %1."
MSG_FR[$MSG_INSTALLING_CRON_TEMPLATE]="${MSG_PRF}0020I: Création du fichier cron %1."
MSG_ZH[$MSG_INSTALLING_CRON_TEMPLATE]="${MSG_PRF}0020I: 创建cron文件 %1."

MSG_NO_INTERNET_CONNECTION_FOUND=$((SCNT++))
MSG_EN[$MSG_NO_INTERNET_CONNECTION_FOUND]="${MSG_PRF}0021E: Unable to connect to $MYHOMEDOMAIN. wget RC: %1"
MSG_DE[$MSG_NO_INTERNET_CONNECTION_FOUND]="${MSG_PRF}0021E: Es kann nicht auf $MYHOMEDOMAIN zugegriffen werden. wget RC: %1"
MSG_FI[$MSG_NO_INTERNET_CONNECTION_FOUND]="${MSG_PRF}0021E: Yhdistäminen kohteeseen $MYHOMEDOMAIN epäonnistui. wget RC: %1"
MSG_FR[$MSG_NO_INTERNET_CONNECTION_FOUND]="${MSG_PRF}0021E: Impossible de se connecter à $MYHOMEDOMAIN. Code erreur wget : %1"
MSG_ZH[$MSG_NO_INTERNET_CONNECTION_FOUND]="${MSG_PRF}0021E: 连接 $MYHOMEDOMAIN 失败. wget RC: %1"

MSG_CHECK_INTERNET_CONNECTION=$((SCNT++))
MSG_EN[$MSG_CHECK_INTERNET_CONNECTION]="${MSG_PRF}0022I: Checking internet connection."
MSG_DE[$MSG_CHECK_INTERNET_CONNECTION]="${MSG_PRF}0022I: Teste Internetverbindung."
MSG_FI[$MSG_CHECK_INTERNET_CONNECTION]="${MSG_PRF}0022I: Tarkistetaan verkkoyhteyttä."
MSG_FR[$MSG_CHECK_INTERNET_CONNECTION]="${MSG_PRF}0022I: Vérification de la connexion Internet."
MSG_ZH[$MSG_CHECK_INTERNET_CONNECTION]="${MSG_PRF}0022I: 检查网络连接."

MSG_SAMPLEEXTENSION_UNINSTALL_FAILED=$((SCNT++))
MSG_EN[$MSG_SAMPLEEXTENSION_UNINSTALL_FAILED]="${MSG_PRF}0023E: Sample extension uninstall failed. %1"
MSG_DE[$MSG_SAMPLEEXTENSION_UNINSTALL_FAILED]="${MSG_PRF}0023E: Beispielserweiterungsdeinstallation fehlgeschlagen. %1"
MSG_FI[$MSG_SAMPLEEXTENSION_UNINSTALL_FAILED]="${MSG_PRF}0023E: Näytelisäosien asennuksen poisto epäonnistui. %1"
MSG_FR[$MSG_SAMPLEEXTENSION_UNINSTALL_FAILED]="${MSG_PRF}0023E: Échec de la désinstallation de l'extension de l'exemple. %1"
MSG_ZH[$MSG_SAMPLEEXTENSION_UNINSTALL_FAILED]="${MSG_PRF}0023E: 扩展卸载失败. %1"

MSG_SAMPLEEXTENSION_UNINSTALL_SUCCESS=$((SCNT++))
MSG_EN[$MSG_SAMPLEEXTENSION_UNINSTALL_SUCCESS]="${MSG_PRF}0024I: Sample extensions successfully deleted."
MSG_DE[$MSG_SAMPLEEXTENSION_UNINSTALL_SUCCESS]="${MSG_PRF}0024I: Beispielserweiterungen erfolgreich gelöscht."
MSG_FI[$MSG_SAMPLEEXTENSION_UNINSTALL_SUCCESS]="${MSG_PRF}0024I: Näytelisäosat poistettiin onnistuneesti."
MSG_FR[$MSG_SAMPLEEXTENSION_UNINSTALL_SUCCESS]="${MSG_PRF}0024I: Exemples d'extensions supprimés avec succès."
MSG_ZH[$MSG_SAMPLEEXTENSION_UNINSTALL_SUCCESS]="${MSG_PRF}0024I: 扩展已被删除."

MSG_UNINSTALLING_CRON_TEMPLATE=$((SCNT++))
MSG_EN[$MSG_UNINSTALLING_CRON_TEMPLATE]="${MSG_PRF}0025I: Deleting cron file %1."
MSG_DE[$MSG_UNINSTALLING_CRON_TEMPLATE]="${MSG_PRF}0025I: Crondatei %1 wird gelöscht."
MSG_FI[$MSG_UNINSTALLING_CRON_TEMPLATE]="${MSG_PRF}0025I: Poistetaan cron-tiedosto %1."
MSG_FR[$MSG_UNINSTALLING_CRON_TEMPLATE]="${MSG_PRF}0025I: Suppression du fichier cron %1."
MSG_ZH[$MSG_UNINSTALLING_CRON_TEMPLATE]="${MSG_PRF}0025I: 删除cron文件 %1."

MSG_UPDATING_CRON=$((SCNT++))
MSG_EN[$MSG_UPDATING_CRON]="${MSG_PRF}0026I: Updating cron configuration in %1."
MSG_DE[$MSG_UPDATING_CRON]="${MSG_PRF}0026I: Cron Konfigurationsdatei %1 wird angepasst."
MSG_FI[$MSG_UPDATING_CRON]="${MSG_PRF}0026I: Päivitetään cron-asetukset kohteessa %1."
MSG_FR[$MSG_UPDATING_CRON]="${MSG_PRF}0026I: Le fichier de configuration Cron %1 a été mis à jour."
MSG_ZH[$MSG_UPDATING_CRON]="${MSG_PRF}0026I: 更新cron文件 %1."

MSG_MISSING_DIRECTORY=$((SCNT++))
MSG_EN[$MSG_MISSING_DIRECTORY]="${MSG_PRF}0027E: Missing required directory %1."
MSG_DE[$MSG_MISSING_DIRECTORY]="${MSG_PRF}0027E: Erforderliches Verzeichnis %1 existiert nicht."
MSG_FI[$MSG_MISSING_DIRECTORY]="${MSG_PRF}0027E: Vaadittu hakemisto %1 puuttuu."
MSG_FR[$MSG_MISSING_DIRECTORY]="${MSG_PRF}0027E: Le répertoire requis %1 n'existe pas."
MSG_ZH[$MSG_MISSING_DIRECTORY]="${MSG_PRF}0027E: 缺少必要的路径 %1."

MSG_CODE_UPDATED=$((SCNT++))
MSG_EN[$MSG_CODE_UPDATED]="${MSG_PRF}0028I: Updated %1 with latest available release."
MSG_DE[$MSG_CODE_UPDATED]="${MSG_PRF}0028I: %1 wurde mit dem letzen aktuellen Release erneuert."
MSG_FI[$MSG_CODE_UPDATED]="${MSG_PRF}0028I: %1 päivitetty viimeisimpään julkaisuun."
MSG_FR[$MSG_CODE_UPDATED]="${MSG_PRF}0028I: %1 a été remplacé par la version la plus récente."
MSG_ZH[$MSG_CODE_UPDATED]="${MSG_PRF}0028I: 更新 %1 到最新版本."

MSG_INSTALLING_SYSTEMD_TEMPLATE=$((SCNT++))
MSG_EN[$MSG_INSTALLING_SYSTEMD_TEMPLATE]="${MSG_PRF}0029I: Creating systemd file %1."
MSG_DE[$MSG_INSTALLING_SYSTEMD_TEMPLATE]="${MSG_PRF}0029I: Systemddatei %1 wird erstellt."

MSG_UNINSTALLING_SYSTEMD_TEMPLATE=$((SCNT++))
MSG_EN[$MSG_UNINSTALLING_SYSTEMD_TEMPLATE]="${MSG_PRF}0030I: Deleting systemd file %1."
MSG_DE[$MSG_UNINSTALLING_SYSTEMD_TEMPLATE]="${MSG_PRF}0030I: Systemddatei %1 wird gelöscht."

MSG_UPDATING_SYSTEMD=$((SCNT++))
MSG_EN[$MSG_UPDATING_SYSTEMD]="${MSG_PRF}0031I: Updating systemd configuration in %1."
MSG_DE[$MSG_UPDATING_SYSTEMD]="${MSG_PRF}0031I: Systemd Konfigurationsdatei %1 wird angepasst."

MSG_SYSTEMD_ENABLED=$((SCNT++))
MSG_EN[$MSG_SYSTEMD_ENABLED]="${MSG_PRF}0032I: Systemd enabled."
MSG_DE[$MSG_SYSTEMD_ENABLED]="${MSG_PRF}0032I: Systemd eingeschaltet."

MSG_SYSTEMD_DISABLED=$((SCNT++))
MSG_EN[$MSG_SYSTEMD_DISABLED]="${MSG_PRF}0033I: $RASPIBACKUP_NAME systemd timer disabled."
MSG_DE[$MSG_SYSTEMD_DISABLED]="${MSG_PRF}0033I: $RASPIBACKUP_NAME systemd timer ausgeschaltet."

MSG_TITLE=$((SCNT++))
MSG_EN[$MSG_TITLE]="$RASPIBACKUP_NAME Installation and Configuration Tool V${VERSION}"
MSG_DE[$MSG_TITLE]="$RASPIBACKUP_NAME Installations- und Konfigurations Tool V${VERSION}"
MSG_FI[$MSG_TITLE]="$RASPIBACKUP_NAME Asennus- ja määritystyökalu V${VERSION}"
MSG_FR[$MSG_TITLE]="$RASPIBACKUP_NAME Outil d'installation et de configuration V${VERSION}"
MSG_ZH[$MSG_TITLE]="$RASPIBACKUP_NAME 安装和设置工具 版本V${VERSION}"

BUTTON_FINISH=$((SCNT++))
MSG_EN[$BUTTON_FINISH]="Finish"
MSG_DE[$BUTTON_FINISH]="Beenden"
MSG_FI[$BUTTON_FINISH]="Lopeta"
MSG_FR[$BUTTON_FINISH]="Terminer"
MSG_ZH[$BUTTON_FINISH]="完成"

BUTTON_SELECT=$((SCNT++))
MSG_EN[$BUTTON_SELECT]="Select"
MSG_DE[$BUTTON_SELECT]="Auswahl"
MSG_FI[$BUTTON_SELECT]="Valitse"
MSG_FR[$BUTTON_SELECT]="Valider"
MSG_ZH[$BUTTON_SELECT]="选择"

BUTTON_BACK=$((SCNT++))
MSG_EN[$BUTTON_BACK]="Back"
MSG_DE[$BUTTON_BACK]="Zurück"
MSG_FI[$BUTTON_BACK]="Takaisin"
MSG_FR[$BUTTON_BACK]="Retour"
MSG_ZH[$BUTTON_BACK]="返回"

SELECT_TIME=$((SCNT++))
MSG_EN[$SELECT_TIME]="Enter time of backup in format hh:mm"
MSG_DE[$SELECT_TIME]="Die Backupzeit im Format hh:mm eingeben"
MSG_FI[$SELECT_TIME]="Syötä varmuuskopioinnin kellonaika muodossa hh:mm"
MSG_FR[$SELECT_TIME]="Saisissez l'heure de la sauvegarde au format hh:mm"
MSG_ZH[$SELECT_TIME]="输入以时间命名备份的格式 hh:mm"

BUTTON_CANCEL=$((SCNT++))
MSG_EN[$BUTTON_CANCEL]="Cancel"
MSG_DE[$BUTTON_CANCEL]="Abbruch"
MSG_FI[$BUTTON_CANCEL]="Peruuta"
MSG_FR[$BUTTON_CANCEL]="Annuler"
MSG_ZH[$BUTTON_CANCEL]="取消"

BUTTON_OK=$((SCNT++))
MSG_EN[$BUTTON_OK]="Ok"
MSG_DE[$BUTTON_OK]="Bestätigen"
MSG_FI[$BUTTON_OK]="OK"
MSG_FR[$BUTTON_OK]="Confirmer"
MSG_ZH[$BUTTON_OK]="确认"

MSG_QUESTION_UPDATE_CONFIG=$((SCNT++))
MSG_EN[$MSG_QUESTION_UPDATE_CONFIG]="Do you want to save the updated $RASPIBACKUP_NAME configuration now?"
MSG_DE[$MSG_QUESTION_UPDATE_CONFIG]="Soll die geänderte Konfiguration von $RASPIBACKUP_NAME jetzt gespeichert werden?"
MSG_FI[$MSG_QUESTION_UPDATE_CONFIG]="Haluatko tallentaa päivitetyt $RASPIBACKUP_NAME-asetukset nyt?"
MSG_FR[$MSG_QUESTION_UPDATE_CONFIG]="La configuration de $RASPIBACKUP_NAME a été modifiée, Enregistrer maintenant?"
MSG_ZH[$MSG_QUESTION_UPDATE_CONFIG]="是否立刻更新 $RASPIBACKUP_NAME 设置?"

MSG_QUESTION_IGNORE_MISSING_STARTSTOP=$((SCNT++))
MSG_EN[$MSG_QUESTION_IGNORE_MISSING_STARTSTOP]="There are no services stopped before starting the backup.${NL}WARNING${NL}Inconsistent backups may be created with $RASPIBACKUP_NAME.${NL}Are you sure?"
MSG_DE[$MSG_QUESTION_IGNORE_MISSING_STARTSTOP]="Es werden keine Services vor dem Start des Backups gestoppt.${NL}WARNUNG${NL}Dadurch können inkonsistente Backups mit $RASPIBACKUP_NAME entstehen.${NL}Ist das beabsichtigt?"
MSG_FI[$MSG_QUESTION_IGNORE_MISSING_STARTSTOP]="Palveluita ei ole valittu pysäytettäväksi ennen varmuuskopiointia.${NL}VAROITUS${NL}Tämä voi johtaa $RASPIBACKUP_NAME-varmuuskopioiden epäyhtenäisyyteen.${NL}Oletko varma?"
MSG_FR[$MSG_QUESTION_IGNORE_MISSING_STARTSTOP]="Aucun service ne sera arrêté avant le démarrage de la sauvegarde.${NL}VAROITUS${NL}Cela peut entraîner des incohérences avec $RASPIBACKUP_NAME.${NL}Etes-vous sûre?"
MSG_ZH[$MSG_QUESTION_IGNORE_MISSING_STARTSTOP]="备份前没有停止任何服务.${NL}警告${NL}可能会创建一个与$RASPIBACKUP_NAME名称不一致的备份.${NL}是否继续?"

MSG_QUESTION_UPDATE_CRON=$((SCNT++))
MSG_EN[$MSG_QUESTION_UPDATE_CRON]="Do you want to save the updated cron settings for $RASPIBACKUP_NAME now?"
MSG_DE[$MSG_QUESTION_UPDATE_CRON]="Soll die geänderte cron Konfiguration für $RASPIBACKUP_NAME jetzt gespeichert werden?"
MSG_FI[$MSG_QUESTION_UPDATE_CRON]="Haluatko tallentaa nyt päivitetyt cron-asetukset kohteelle $RASPIBACKUP_NAME?"
MSG_FR[$MSG_QUESTION_UPDATE_CRON]="Voulez-vous enregistrer les paramètres cron mis à jour pour $RASPIBACKUP_NAME maintenant ?"
MSG_ZH[$MSG_QUESTION_UPDATE_CRON]="是否保存$RASPIBACKUP_NAME 更新的cron设置?"

MSG_QUESTION_UPDATE_SYSTEMD=$((SCNT++))
MSG_EN[$MSG_QUESTION_UPDATE_SYSTEMD]="Do you want to save the updated systemd settings for $RASPIBACKUP_NAME now?"
MSG_DE[$MSG_QUESTION_UPDATE_SYSTEMD]="Soll die geänderte systemd Konfiguration für $RASPIBACKUP_NAME jetzt gespeichert werden?"

MSG_SEQUENCE_OK=$((SCNT++))
MSG_EN[$MSG_SEQUENCE_OK]="Stopcommands for services will be executed in following sequence. Startcommands will be executed in reverse sequence. Sequence OK?"
MSG_DE[$MSG_SEQUENCE_OK]="Stopbefehle für die Services werden in folgender Reihenfolge ausgeführt. Startbefehle werden umgekehrt ausgeführt. Ist die Reihenfolge richtig?"
MSG_FI[$MSG_SEQUENCE_OK]="Palvelut pysäytetään seuraavassa järjestyksessä ja ne käynnistetään uudelleen käänteisessä järjestyksessä. Onko järjestys OK?"
MSG_FR[$MSG_SEQUENCE_OK]="Les commandes d'arrêt pour les services seront exécutées dans l'ordre suivant. Les commandes de démarrage seront exécutées dans l'ordre inverse. d'accord?"
MSG_ZH[$MSG_SEQUENCE_OK]="停止服务命令将按以下顺序停止，启动服务命令按反序执行 OK?"

BUTTON_YES=$((SCNT++))
MSG_EN[$BUTTON_YES]="Yes"
MSG_DE[$BUTTON_YES]="Ja"
MSG_FI[$BUTTON_YES]="Kyllä"
MSG_FR[$BUTTON_YES]="Oui"
MSG_ZH[$BUTTON_YES]="Yes"

BUTTON_NO=$((SCNT++))
MSG_EN[$BUTTON_NO]="No"
MSG_DE[$BUTTON_NO]="Nein"
MSG_FI[$BUTTON_NO]="Ei"
MSG_FR[$BUTTON_NO]="Non"
MSG_ZH[$BUTTON_NO]="No"

MSG_QUESTION_UNINSTALL=$((SCNT++))
MSG_EN[$MSG_QUESTION_UNINSTALL]="Are you sure to uninstall $RASPIBACKUP_NAME ?"
MSG_DE[$MSG_QUESTION_UNINSTALL]="Soll $RASPIBACKUP_NAME wirklich deinstalliert werden ?"
MSG_FI[$MSG_QUESTION_UNINSTALL]="Haluatko varmasti poistaa koko kohteen $RASPIBACKUP_NAME ?"
MSG_FR[$MSG_QUESTION_UNINSTALL]="Êtes-vous sûr de vouloir désinstaller $RASPIBACKUP_NAME ?"
MSG_ZH[$MSG_QUESTION_UNINSTALL]="确认卸载 $RASPIBACKUP_NAME 么?"

MSG_SCRIPT_NOT_INSTALLED=$((SCNT++))
MSG_EN[$MSG_SCRIPT_NOT_INSTALLED]="$RASPIBACKUP_NAME not installed."
MSG_DE[$MSG_SCRIPT_NOT_INSTALLED]="$RASPIBACKUP_NAME ist nicht installiert"
MSG_FI[$MSG_SCRIPT_NOT_INSTALLED]="$RASPIBACKUP_NAME ei ole asennettuna."
MSG_FR[$MSG_SCRIPT_NOT_INSTALLED]="$RASPIBACKUP_NAME n'est pas installé."
MSG_ZH[$MSG_SCRIPT_NOT_INSTALLED]="$RASPIBACKUP_NAME 尚未安装."

MSG_TIMER_NA=$((SCNT++))
MSG_EN[$MSG_TIMER_NA]="Weekly backup disabled."
MSG_DE[$MSG_TIMER_NA]="Wöchentliches Backup ist ausgeschaltet."
MSG_FI[$MSG_TIMER_NA]="Viikoittainen varmuuskopiointi ei ole käytössä."
MSG_FR[$MSG_TIMER_NA]="La sauvegarde hebdomadaire est désactivée."
MSG_ZH[$MSG_TIMER_NA]="每周备份已禁用."

MSG_CONFIG_NOT_INSTALLED=$((SCNT++))
MSG_EN[$MSG_CONFIG_NOT_INSTALLED]="No configuration found."
MSG_DE[$MSG_CONFIG_NOT_INSTALLED]="Keine Konfiguration gefunden."
MSG_FI[$MSG_CONFIG_NOT_INSTALLED]="Asetuksia ei löytynyt."
MSG_FR[$MSG_CONFIG_NOT_INSTALLED]="Aucune configuration trouvée."
MSG_ZH[$MSG_CONFIG_NOT_INSTALLED]="未找到配置文件."

MSG_CRON_NOT_INSTALLED=$((SCNT++))
MSG_EN[$MSG_CRON_NOT_INSTALLED]="No cron configuration found."
MSG_DE[$MSG_CRON_NOT_INSTALLED]="Keine cron Konfiguration gefunden."
MSG_FI[$MSG_CRON_NOT_INSTALLED]="Cron-asetuksia ei löytynyt."
MSG_FR[$MSG_CRON_NOT_INSTALLED]="Aucune configuration cron trouvée.."
MSG_ZH[$MSG_CRON_NOT_INSTALLED]="Cron未找到."

MSG_NO_UPDATE_AVAILABLE=$((SCNT++))
MSG_EN[$MSG_NO_UPDATE_AVAILABLE]="(No update available)"
MSG_DE[$MSG_NO_UPDATE_AVAILABLE]="(Kein Update verfügbar)"
MSG_FI[$MSG_NO_UPDATE_AVAILABLE]="(Päivitystä ei ole saatavilla)"
MSG_FR[$MSG_NO_UPDATE_AVAILABLE]="(Pas de mise a jour disponible)"
MSG_ZH[$MSG_NO_UPDATE_AVAILABLE]="(没有可用更新)"

MSG_NO_EXTENSIONS_FOUND=$((SCNT++))
MSG_EN[$MSG_NO_EXTENSIONS_FOUND]="No extensions installed."
MSG_DE[$MSG_NO_EXTENSIONS_FOUND]="Keine Erweiterungen installiert."
MSG_FI[$MSG_NO_EXTENSIONS_FOUND]="Lisäosia ei ole asennettu."
MSG_FR[$MSG_NO_EXTENSIONS_FOUND]="Aucune extension installée."
MSG_ZH[$MSG_NO_EXTENSIONS_FOUND]="尚未安装扩展."

MSG_EXTENSIONS_ALREADY_INSTALLED=$((SCNT++))
MSG_EN[$MSG_EXTENSIONS_ALREADY_INSTALLED]="Extensions already installed."
MSG_DE[$MSG_EXTENSIONS_ALREADY_INSTALLED]="Extensions sind bereits installiert."
MSG_FI[$MSG_EXTENSIONS_ALREADY_INSTALLED]="Lisäosat ovat jo asennettuna."
MSG_FR[$MSG_EXTENSIONS_ALREADY_INSTALLED]="Les extensions sont déjà installées."
MSG_ZH[$MSG_EXTENSIONS_ALREADY_INSTALLED]="扩展已安装."

MSG_SCRIPT_ALREADY_INSTALLED=$((SCNT++))
MSG_EN[$MSG_SCRIPT_ALREADY_INSTALLED]="$RASPIBACKUP_NAME already installed.${NL}Do you want to reinstall $RASPIBACKUP_NAME ?"
MSG_DE[$MSG_SCRIPT_ALREADY_INSTALLED]="$RASPIBACKUP_NAME ist bereits installiert.${NL}Soll die bestehende Installation überschrieben werden ?"
MSG_FI[$MSG_SCRIPT_ALREADY_INSTALLED]="$RASPIBACKUP_NAME on jo asennettu.${NL} Haluatko uudelleenasentaa kohteen $RASPIBACKUP_NAME ?"
MSG_FR[$MSG_SCRIPT_ALREADY_INSTALLED]="$RASPIBACKUP_NAME est déjà installé.${NL}Voulez-vous écraser l'installation existante ?"

MSG_DOWNLOADING_PROPERTYFILE=$((SCNT++))
MSG_EN[$MSG_DOWNLOADING_PROPERTYFILE]="Downloading version information."
MSG_DE[$MSG_DOWNLOADING_PROPERTYFILE]="Versionsinformationen werden runtergeladen."
MSG_FI[$MSG_DOWNLOADING_PROPERTYFILE]="Ladataan version tietoja."
MSG_FR[$MSG_DOWNLOADING_PROPERTYFILE]="Les informations de version seront téléchargées."
MSG_ZH[$MSG_DOWNLOADING_PROPERTYFILE]="下载版本信息."

MSG_INVALID_KEEP=$((SCNT++))
MSG_EN[$MSG_INVALID_KEEP]="Invalid number %1 entered. Number has to be between 1 and 52."
MSG_DE[$MSG_INVALID_KEEP]="Ungültige Zahl %1 eingegeben. Sie muss zwischen 1 und 52 liegen."
MSG_FI[$MSG_INVALID_KEEP]="Epäkelpo numero %1 syötetty. Numeron tulee olla 1:n ja 52:n väliltä."
MSG_FR[$MSG_INVALID_KEEP]="Nombre non valide %1 saisi. Il doit être compris entre 1 et 52."
MSG_ZH[$MSG_INVALID_KEEP]="输入的 %1 无效. 数字必须在1和52之间."

MSG_INVALID_KEEP_NUMBER_COUNT=$((SCNT++))
MSG_EN[$MSG_INVALID_KEEP_NUMBER_COUNT]="Insert one number only."
MSG_DE[$MSG_INVALID_KEEP_NUMBER_COUNT]="Nur eine Zahl eingeben."
MSG_FI[$MSG_INVALID_KEEP_NUMBER_COUNT]="Syötä vain yksi numero."
MSG_FR[$MSG_INVALID_KEEP_NUMBER_COUNT]="Entrez un seul numéro."
MSG_ZH[$MSG_INVALID_KEEP_NUMBER_COUNT]="请仅插入一个数字."

MSG_INVALID_SMART=$((SCNT++))
MSG_EN[$MSG_INVALID_SMART]="Invalid number %1 entered. Number has to be >= 0."
MSG_DE[$MSG_INVALID_SMART]="Ungültige Zahl %1 eingegeben. Sie muss >= 0 sein."
MSG_FI[$MSG_INVALID_SMART]="Epäkelpo numero %1 syötetty. Numeron tulee olla >= 0."
MSG_FR[$MSG_INVALID_SMART]="Nombre non valide %1 saisi. Il doit être >= 0."
MSG_ZH[$MSG_INVALID_SMART]="输入的 %1 无效. 数字必须>= 0."

MSG_INVALID_SMART_NUMBER_COUNT=$((SCNT++))
MSG_EN[$MSG_INVALID_SMART_NUMBER_COUNT]="Expect four numbers separated by spaces: daily, weekly, monthly and yearly backups."
MSG_DE[$MSG_INVALID_SMART_NUMBER_COUNT]="Vier durch Leerzeichen getrennte Zahlen werden erwartet: Tägliche, wöchentliche, monatliche und jährliche Backups."
MSG_FI[$MSG_INVALID_SMART_NUMBER_COUNT]="Vaaditaan neljä välilyönnein erotettua numeroa: päivittäinen, viikoittainen, kuukausittainen ja vuosittainen varmuuskopiointien lukumäärä"
MSG_FR[$MSG_INVALID_SMART_NUMBER_COUNT]="Quatre nombres séparés par des espaces sont attendus : sauvegardes quotidiennes, hebdomadaires, mensuelles et annuelles."
MSG_ZH[$MSG_INVALID_SMART_NUMBER_COUNT]="四个分隔数字分别代表：按日、按周、按月、按年的备份"

MSG_INVALID_KEEP_NUMBER_COUNT=$((SCNT++))
MSG_EN[$MSG_INVALID_KEEP_NUMBER_COUNT]="Enter one single number only."
MSG_DE[$MSG_INVALID_KEEP_NUMBER_COUNT]="Nur eine einzige Zahl eingeben."
MSG_FI[$MSG_INVALID_KEEP_NUMBER_COUNT]="Syötä vain yksi numero."
MSG_FR[$MSG_INVALID_KEEP_NUMBER_COUNT]="Entrez un seul numéro."
MSG_ZH[$MSG_INVALID_KEEP_NUMBER_COUNT]="请仅输入一个数字."

MSG_INVALID_TIME=$((SCNT++))
MSG_EN[$MSG_INVALID_TIME]="Invalid time '%1'. Input has to be in format hh:mm and 0<=hh<24 and 0<=mm<60."
MSG_DE[$MSG_INVALID_TIME]="Ungültige Zeit '%1'. Die Eingabe muss im Format hh:mm sein und 0<=hh<24 und 0<=mm<60."
MSG_FI[$MSG_INVALID_TIME]="Epäkelpo kellonaika '%1'. Ajan tulee olla muodossa hh:mm ja 0<=hh<24 sekä 0<=mm<60."
MSG_FR[$MSG_INVALID_TIME]="Heure non valide '%1'. L'entrée doit être au format hh:mm et 0<=hh<24 et 0<=mm<60."
MSG_ZH[$MSG_INVALID_TIME]="无效的时间 '%1'. 输入的格式必须为 hh:mm  0<=hh<24 且 0<=mm<60."

MSG_RUNASROOT=$((SCNT++))
MSG_EN[$MSG_RUNASROOT]="$MYSELF has to be started as root. Try 'sudo %1%2'."
MSG_DE[$MSG_RUNASROOT]="$MYSELF muss als root gestartet werden. Benutze 'sudo %1%2'."
MSG_FI[$MSG_RUNASROOT]="$MYSELF tulee käynnistää root-oikeuksin. Käynnistä 'sudo %1%2'."
MSG_FR[$MSG_RUNASROOT]="$MYSELF doit être démarré en tant que root. Utilisez 'sudo %1%2'."
MSG_ZH[$MSG_RUNASROOT]="$MYSELF 必须以root身份开启. 请尝试 'sudo %1%2'."

MSG_SYSTEMD_NOT_INSTALLED=$((SCNT++))
MSG_EN[$MSG_SYSTEMD_NOT_INSTALLED]="No systemd configuration found."
MSG_DE[$MSG_SYSTEMD_NOT_INSTALLED]="Keine systemd Konfiguration gefunden."

DESCRIPTION_INSTALLATION=$((SCNT++))
MSG_EN[$DESCRIPTION_INSTALLATION]="${NL}$RASPIBACKUP_NAME allows to plug in custom extensions which are called before and after the backup process. \
There exist sample extensions which report the memory usage, CPU temperature and disk usage of the backup partition. \
For details see${NL}https://www.linux-tips-and-tricks.de/en/raspibackupcategoryy/443-raspibackup-extensions."
MSG_DE[$DESCRIPTION_INSTALLATION]="${NL}$RASPIBACKUP_NAME erlaubt selbstgeschriebene Erweiterungen vor und nach dem Backupprozess aufzurufen. \
Es gibt Beispielerweiterungen die die Speicherauslastung, die CPU Temperatur sowie die Speicherplatzbenutzung der Backuppartition anzeigen. \
Für weitere Details siehe${NL}https://www.linux-tips-and-tricks.de/de/13-raspberry/442-raspibackup-erweiterungen."
MSG_FI[$DESCRIPTION_INSTALLATION]="${NL}$RASPIBACKUP_NAME tukee lisäosia, joiden toimintoja voidaan suorittaa ennen ja jälkeen varmuuskopioinnin. \
Mukana tulevat näytelisäosat esittävät prosessorin lämpötilan sekä tietoja muistin ja varmuuskopiointilevyn käytöstä. \
${NL}Lue lisätietoja osoitteesta https://www.linux-tips-and-tricks.de/en/raspibackupcategoryy/443-raspibackup-extensions."
MSG_FR[$DESCRIPTION_INSTALLATION]="${NL}$RASPIBACKUP_NAME vous permet d'appeler des extensions auto-écrites avant et après le processus de sauvegarde. \
Il existe des exemples d'extensions qui montrent l'utilisation de la mémoire, la température du processeur et l'utilisation de l'espace de stockage de la partition de sauvegarde. \
${NL}Pour plus de détails voir https://www.linux-tips-and-tricks.de/en/raspibackupcategoryy/443-raspibackup-extensions."
MSG_ZH[$DESCRIPTION_INSTALLATION]="${NL}$RASPIBACKUP_NAME 允许插入自定义扩展，备份前后均可插入. \
已有示例扩展报告内存占用,CPU温度和备份硬盘占用. \
${NL}详情请 https://www.linux-tips-and-tricks.de/en/raspibackupcategoryy/443-raspibackup-extensions."

DESCRIPTION_COMPRESS=$((SCNT++))
MSG_EN[$DESCRIPTION_COMPRESS]="${NL}$RASPIBACKUP_NAME can compress dd and tar backups to reduce the size of the backup. Please note this will increase backup time and will heaten the CPU. \
Please note an option of $FILE_TO_INSTALL which will reduce the size of a dd backup also. \
For details see https://www.linux-tips-and-tricks.de/en/faq#a16."
MSG_DE[$DESCRIPTION_COMPRESS]="${NL}$RASPIBACKUP_NAME kann dd und tar Backups kompressen um die Backupgröße zu reduzieren. Das bedeutet aber dass die Backupzeit steigt und die CPU erwärmen wird. \
$FILE_TO_INSTALL bietet auch eine Option an mit der ein dd Backup verkleinert werden kann. Siehe dazu \
https://www.linux-tips-and-tricks.de/de/faq#a16."
MSG_FI[$DESCRIPTION_COMPRESS]="${NL}$RASPIBACKUP_NAME voi pakata dd- ja tar-varmuuskopiot, jotta ne veisivät vähemmän tilaa. Huomioithan, että tämä pidentää varmuuskopioinnin aikaa ja nostaa CPU:n lämpötilaa. \
Huomioi myös vaihtoehto $FILE_TO_INSTALL, joka vähentää dd-varmuuskopioiden käyttämää tilaa. \
Lisätietoja löydät osoitteesta https://www.linux-tips-and-tricks.de/en/faq#a16."
MSG_FR[$DESCRIPTION_COMPRESS]="${NL}$RASPIBACKUP_NAME peut compresser les sauvegardes dd et tar pour réduire leurs tailles . Cependant, cela signifie que le temps de sauvegarde augmentera et que le cpu se réchauffera. \
$FILE_TO_INSTALL, offre également une option avec laquelle une sauvegarde dd peut être réduite. Voir. \
https://www.linux-tips-and-tricks.de/en/faq#a16."
MSG_ZH[$DESCRIPTION_COMPRESS]="${NL}$RASPIBACKUP_NAME 可以压缩 dd和tar备份文件. 但是这会在备份期间增加备份时间和使CPU升温. \
勾选 $FILE_TO_INSTALL, 开启压缩. \
详情见 https://www.linux-tips-and-tricks.de/en/faq#a16."

DESCRIPTION_CRON=$((SCNT++))
MSG_EN[$DESCRIPTION_CRON]="${NL}$RASPIBACKUP_NAME should be started on a regular base when the initial configuration and backup and restore testing was done. \
Configure the backup to be created daily or weekly. For other backup intervals you have to modify /etc/cron.d/raspiBackup manually."
MSG_DE[$DESCRIPTION_CRON]="${NL}$RASPIBACKUP_NAME sollte regelmäßig gestartet werden wenn die initiale Konfiguration sowie Backup und Restore Tests beendet sind. \
Konfiguriere den Backup täglich oder wöchentlich zu erstellen. Für andere Intervalle muss die Datei /etc/cron.d/raspiBackup manuell geändert werden."
MSG_FI[$DESCRIPTION_CRON]="${NL}$RASPIBACKUP_NAME tulisi ajaa äännöllisesti se jälkeen, kun asetusten määritysten jälkeen ensimmäinen varmuuskopio on suoritettu ja varmuuskopion palautus on testattu. \
Ajasta varmuuskopiointi päivittäiseksi tai viikottaiseksi. Muita varmuuskopioinnin aikavälejä varten tulee muokata tiedostoa /etc/cron.d/raspiBackup manuaalisesti."
MSG_FR[$DESCRIPTION_CRON]="${NL}$RASPIBACKUP_NAME doit être démarré régulièrement lorsque les premiers tests de configuration ,de sauvegarde et de restauration sont terminés. \
Configurez la sauvegarde à exécuter quotidiennement ou hebdomadairement. Pour d'autres intervalles de sauvegardes vous devez modifier manuellement le fichier /etc/cron.d/raspiBackup ."
MSG_ZH[$DESCRIPTION_CRON]="${NL}$RASPIBACKUP_NAME 会在完成初始配置以及备份和恢复测试后定期启动. \
配置每天或每周创建备份。对于其他备份间隔，您必须手动修改/etc/cron.d/raspiBackup."

DESCRIPTION_SYSTEMD=$((SCNT++))
MSG_EN[$DESCRIPTION_SYSTEMD]="${NL}$RASPIBACKUP_NAME should be started on a regular base when the initial configuration and backup and restore testing was done. \
Configure the backup to be created daily or weekly. For other backup intervals you have to modify /etc/systemd/system/raspiBackup.timer manually."
MSG_DE[$DESCRIPTION_SYSTEMD]="${NL}$RASPIBACKUP_NAME sollte regelmäßig gestartet werden wenn die initiale Konfiguration sowie Backup und Restore Tests beendet sind. \
Konfiguriere den Backup täglich oder wöchentlich zu erstellen. Für andere Intervalle muss die Datei /etc/systemd/system/raspiBackup.timer manuell geändert werden."

DESCRIPTION_SMARTMODE=$((SCNT++))
MSG_EN[$DESCRIPTION_SMARTMODE]="${NL}There exist two different ways to define the number of backups. Just by defining the maximum number of backups to keep or \
by using the smart backup strategy. See https://www.linux-tips-and-tricks.de/en/smart-recycle/ for details about the strategy."
MSG_DE[$DESCRIPTION_SMARTMODE]="${NL}Es gibt grundsätzlich zwei Methoden, die Anzahl der vorzuhaltenden Backups festzulegen. Dies erfolgt entweder durch die Definition der maximalen Anzahl oder durch Verwendung der intelligenten Backupstrategie. \
Eine Detailbeschreibung der Strategie befindet sich auf https://www.linux-tips-and-tricks.de/de/rotationsstrategie/."
MSG_FI[$DESCRIPTION_SMARTMODE]="${NL}Voit määrittää säilytettävien varmuuskopioiden lukumäärän joko määrittämällä säilytettävien varmuuskopioiden maksimimäärän tai \
käyttämällä älykästä varmuuskopiointia.${NL}Katso lisätietoa osoitteesta https://www.linux-tips-and-tricks.de/en/smart-recycle/."
MSG_FR[$DESCRIPTION_SMARTMODE]="${NL}Il existe deux méthodes pour définir le nombre de sauvegardes à conserver : SIMPLE ou INTELLIGENTE. Cela se fait soit en définissant un nombre maximum, soit en utilisant la stratégie de sauvegarde intelligente. \
Une description détaillée de la stratégie est disponible sur https://www.linux-tips-and-tricks.de/en/smart-recycle/."
MSG_ZH[$DESCRIPTION_SMARTMODE]="${NL}当前有两种方法定义备份数量:定义最大备份数或者用只能备份策略,策略详情: \
${NL} https://www.linux-tips-and-tricks.de/en/smart-recycle/."

DESCRIPTION_MESSAGEDETAIL=$((SCNT++))
MSG_EN[$DESCRIPTION_MESSAGEDETAIL]="${NL}$RASPIBACKUP_NAME can either be very verbose or just write important messages. \
Usually it makes sense to turn all on when installing $RASPIBACKUP_NAME the first time. Later on you can change it to write important messages only."
MSG_DE[$DESCRIPTION_MESSAGEDETAIL]="${NL}$RASPIBACKUP_NAME kann viele Meldungen schreiben oder nur die Wichtigsten. \
Es macht Sinn alle beim ersten Installieren von $RASPIBACKUP_NAME anzuschalten. Später können sie auf die Wichtigsten reduziert werden."
MSG_FI[$DESCRIPTION_MESSAGEDETAIL]="${NL}$RASPIBACKUP_NAME voi joko kirjoittaa yksityiskohtaiset tai vain tärkeät viestit. \
Yleensä ensimmäisen $RASPIBACKUP_NAME-asennuksen jälkeen yksityiskohtaiset viestit on hyvä näyttää. Voit myöhemmin valita kirjoitettavaksi vain tärkeät viestit."
MSG_FR[$DESCRIPTION_MESSAGEDETAIL]="${NL}$RASPIBACKUP_NAME peut écrire de nombreux messages ou seulement les plus importants. \
Il est logique de les activer tous lors de la première installation de $RASPIBACKUP_NAME Plus tard, ils peuvent être réduits aux plus importants."
MSG_ZH[$DESCRIPTION_MESSAGEDETAIL]="${NL}$RASPIBACKUP_NAME 可以非常详细或者只显示重要信息. \
通常第一次安装$RASPIBACKUP_NAME后打开所有选项是有意义的，随后你可切换至只写入重要信息."

DESCRIPTION_STARTSTOP=$((SCNT++))
MSG_EN[$DESCRIPTION_STARTSTOP]="${NL}Before and after creating a backup important services should be stopped and started. Add the required services separated by a space which should be stopped in the correct order. \
The services will be started in reverse order when backup finished. For further details see https://www.linux-tips-and-tricks.de/en/faq#a18."
MSG_DE[$DESCRIPTION_STARTSTOP]="${NL}Vor und nach einem Backup sollten immer alle wichtigen Services gestoppt und gestartet werden. Dazu müssen die notwendigen Services die gestoppt werden sollen getrennt durch Leerzeichen in der richtigen Reihenfolge eingegeben werden. \
In umgekehrter Reihenfolge werden die Services nach dem Backup wieder gestartet. Weitere Details finden sich auf https://www.linux-tips-and-tricks.de/de/faq#a18."
MSG_FI[$DESCRIPTION_STARTSTOP]="${NL}Tärkeät palvelut tulisi pysäyttää varmuuskopioinnin ajaksi. Lisää pysäytettävät palvelut välilyönnillä erotettuna pysäytysjärjestyksessä. \
Palvelut käynnistetään käänteisessä järjestyksessä varmuuskopioinnin päättyessä. Lisätietoa löydät osoitteesta https://www.linux-tips-and-tricks.de/en/faq#a18."
MSG_FR[$DESCRIPTION_STARTSTOP]="${NL}Avant et après une sauvegarde, tous les services importants doivent toujours être arrêtés et démarrés. Pour ce faire, les services nécessaires qui doivent être arrêtés doivent être saisis dans le bon ordre, séparés par des espaces. \
Les services sont redémarrés dans l'ordre inverse après la sauvegarde. Vous trouverez plus de détails sur https://www.linux-tips-and-tricks.de/de/faq#a18."
MSG_ZH[$DESCRIPTION_STARTSTOP]="${NL}备份前，重要服务会被停止，备份后自动重启服务.按顺序添加需要停止的服务，多个服务用空格分割 \
服务会在备份完成后按反序重启，详情见 https://www.linux-tips-and-tricks.de/en/faq#a18."

DESCRIPTION_STARTSTOP_SEQUENCE=$((SCNT++))
MSG_EN[$DESCRIPTION_STARTSTOP_SEQUENCE]="${NL}Select step by step every service which should be stopped first, second, third and so on and confirm every single service with <Ok> until there is no service any more. \
Actual sequence is displayed top down. \
For further details see https://www.linux-tips-and-tricks.de/en/faq#a18."
MSG_DE[$DESCRIPTION_STARTSTOP_SEQUENCE]="${NL}Wähle der Reihe nach die Services aus wie sie vor dem Backup gestoppt werden sollen und bestätige jeden einzelnen Service mit <Bestätigen> bis keine Services mehr angezeigt werden. \
Die aktuelle Reihenfolge wird von oben nach unten angezeigt. \
Weitere Details finden sich auf https://www.linux-tips-and-tricks.de/de/faq#a18."
MSG_FI[$DESCRIPTION_STARTSTOP_SEQUENCE]="${NL}Valitse pysäytettävät palvelut yksi kerrallaan painaen <OK>, kunnes listalla ei ole palveluita. \
Toteutuva järjestys näytetään ylhäältä alas. \
${NL}Lisätietoja näet osoitteesta https://www.linux-tips-and-tricks.de/en/faq#a18."
MSG_FR[$DESCRIPTION_STARTSTOP_SEQUENCE]="${NL}Sélectionnez les services les uns après les autres car ils doivent être arrêtés avant la sauvegarde et confirmez chaque service individuel avec <Confirmer> jusqu'à ce qu'aucun autre service ne s'affiche. \
L'ordre en cours est affiché de haut en bas. \
Vous trouverez plus de détails sur https://www.linux-tips-and-tricks.de/de/faq#a18."
MSG_ZH[$DESCRIPTION_STARTSTOP_SEQUENCE]="${NL}一个一个的选择需要停止的服务,按<Ok>确定. \
停止顺序自上而下. \
${NL}详情见 https://www.linux-tips-and-tricks.de/en/faq#a18."

DESCRIPTION_STARTSTOP_SERVICES=$((SCNT++))
MSG_EN[$DESCRIPTION_STARTSTOP_SERVICES]="${NL}Select all services in sequence how they should be stopped before the backup starts. \
Current sequence is displayed.\
They will be started in reverse sequence again when the backup finished."
MSG_DE[$DESCRIPTION_STARTSTOP_SERVICES]="${NL}Wähle alle wichtigen Services aus die vor dem Backup gestoppt werden sollen. \
Sie werden wieder in umgekehrter Reihenfolge gestartet wenn der Backup beendet wurde."
MSG_FI[$DESCRIPTION_STARTSTOP_SERVICES]="${NL}Palvelut pysäytetään ennen varmuuskopiointia siinä järjestyksessä, kun valitset ne. \
Listalla näytetään nykyinen järjestys. \
Palvelut käynnistetään käänteisessä järjestyksessä varmuuskopioinnin päättyessä."
MSG_FR[$DESCRIPTION_STARTSTOP_SERVICES]="${NL}Sélectionnez tous les services importants qui doivent être arrêtés avant la sauvegarde. \
La séquence en cours est affichée. \
Ils sont redémarrés dans l'ordre inverse lorsque la sauvegarde est terminée."
MSG_ZH[$DESCRIPTION_STARTSTOP_SERVICES]="${NL}按顺序选择备份开始前应停止的所有服务. \
当前序列已显示. \
备份完成后会按反序重启."

DESCRIPTION_PARTITIONS=$((SCNT++))
MSG_EN[$DESCRIPTION_PARTITIONS]="${NL}Select all partitions which should be included in the backup. \
${NL}${NL}Note: The first two partitions have to be selected all the time."
MSG_DE[$DESCRIPTION_PARTITIONS]="${NL}Wähle alle Partitionen aus die im Backup enthalten sein sollen. \
${NL}${NL}Hinweis: Die ersten beiden Partitionen müssen immer ausgewählt werden."
MSG_FI[$DESCRIPTION_PARTITIONS]="${NL}Valitse kaikki varmuuskopioitavat osiot. \
${NL}${NL}Huom: Kaksi ensimmäistä osiota tulee olla aina valittuna."
MSG_FR[$DESCRIPTION_PARTITIONS]="${NL}Sélectionnez toutes les partitions qui doivent être incluses dans la sauvegarde. \
${NL}${NL}Remarque : les deux premières partitions doivent toujours être sélectionnées."
MSG_ZH[$DESCRIPTION_PARTITIONS]="${NL}选择所有需要备份的分区. \
${NL}${NL}注意:前两个分区总会默认被选中."

DESCRIPTION_LANGUAGE=$((SCNT++))
MSG_EN[$DESCRIPTION_LANGUAGE]="${NL}$RASPIBACKUP_NAME and this installer support following languages as of now. Default language is the system language.\
${NL}${NL}Any help to add another language is welcome."
MSG_DE[$DESCRIPTION_LANGUAGE]="${NL}$RASPIBACKUP_NAME und dieser Installer unterstützen momentan folgende Sprachen. Standardsprache ist die Systemsprache.\
${NL}${NL}Jede Hilfe eine weitere Sprache dazuzubringen ist herzlich willkommen."
MSG_FI[$DESCRIPTION_LANGUAGE]="${NL}$RASPIBACKUP_NAME ja tämä asennustyökalu tukevat tällä hetkellä ${NL}alla lueteltuja kieliä. Oletuksena on järjestelmän kieli.\
${NL}${NL}Apu muiden kielien lisäämiseen on tervetullut."
MSG_FR[$DESCRIPTION_LANGUAGE]="${NL}$RASPIBACKUP_NAME et ce programme d'installation prend actuellement en charge les langues suivantes. La langue du système est la langue standard.\
${NL}${NL}Toute aide pour ajouter une autre langue est la bienvenue."
MSG_ZH[$DESCRIPTION_LANGUAGE]="${NL}$RASPIBACKUP_NAME 目前支持下列语言，默认使用系统语言.\
${NL}${NL}欢迎翻译其他语言！."

DESCRIPTION_KEEP=$((SCNT++))
MSG_EN[$DESCRIPTION_KEEP]="${NL}Enter number of backups to keep. Number hast to be between 1 and 52."
MSG_DE[$DESCRIPTION_KEEP]="${NL}Gib die Anzahl der Beackups die vorzuhalten sind. Die Zahl muss zwischen 1 und 52 liegen."
MSG_FI[$DESCRIPTION_KEEP]="${NL}Syötä säilytettävien varmuuskopioiden lukumäärä. Numeron tulee olla 1:n ja 52:n väliltä."
MSG_FR[$DESCRIPTION_KEEP]="${NL}Entrez le nombre de sauvegardes à conserver. Le nombre doit être compris entre 1 et 52."
MSG_ZH[$DESCRIPTION_KEEP]="${NL}输入保存的备份数,在1和52之间."

DESCRIPTION_SMART=$((SCNT++))
MSG_EN[$DESCRIPTION_SMART]="${NL}Enter four numbers separated by spaces to define the smart recycle backup strategy parameters. The numbers define how many daily, weekly, monthly and yearly backups are kept. \
For details about the backup strategy see https://www.linux-tips-and-tricks.de/en/smart-recycle/."
MSG_DE[$DESCRIPTION_SMART]="${NL}Gib mit vier durch Leerzeichen getrennten Zahlen die Parameter für die intelligente Rotationsstrategie ein. Die Zahlen definieren wie viele tägliche, wöchentliche, monatliche und jährliche Backups vorgehalten werden. \
Details zur Backupstrategie können auf https://www.linux-tips-and-tricks.de/de/rotationsstrategie/ nachgelesen werden."
MSG_FI[$DESCRIPTION_SMART]="${NL}Syötä neljä välilyönnein erotettua numeroa määrittääksesi älykkään varmuuskopioinnin parametrit. Numerot määrittävät kuinka monta päivittäistä, viikoittaista, kuukausittaista ja vuosittaista varmuuskopiota säilytetään. \
Lisätietoa löydät osoitteesta https://www.linux-tips-and-tricks.de/en/smart-recycle/."
MSG_FR[$DESCRIPTION_SMART]="${NL}Saisissez les paramètres de la stratégie intelligente avec quatre nombres séparés par des espaces. Les nombres définissent combien de sauvegardes quotidiennes, hebdomadaires, mensuelles et annuelles sont conservées. \
Des détails sur la stratégie de sauvegarde sont disponibles sur https://www.linux-tips-and-tricks.de/de/rotationsstrategy/."
MSG_ZH[$DESCRIPTION_SMART]="${NL}输入四个数字定义备份策略. 这决定备份周期. \
详情见 https://www.linux-tips-and-tricks.de/en/smart-recycle/."

DESCRIPTION_ERROR=$((SCNT++))
MSG_EN[$DESCRIPTION_ERROR]="Unrecoverable error occurred. Check logfile $LOG_FILE."
MSG_DE[$DESCRIPTION_ERROR]="Ein nicht behebbarer Fehler ist aufgetreten. Siehe Logdatei $LOG_FILE."
MSG_FI[$DESCRIPTION_ERROR]="Tapahtui peruuttamaton virhe. Tarkista lokitiedosto $LOG_FILE."
MSG_FR[$DESCRIPTION_ERROR]="Une erreur irrécupérable s'est produite. Voir le fichier journal $LOG_FILE."
MSG_ZH[$DESCRIPTION_ERROR]="发生了无法恢复的错误。检查日志文件$LOG_FILE."

DESCRIPTION_BACKUPPATH=$((SCNT++))
MSG_EN[$DESCRIPTION_BACKUPPATH]="${NL}On the backup path a partition has to be be mounted which is used by $FILE_TO_INSTALL to store the backups. \
This can be a local partition or a mounted remote partition."
MSG_DE[$DESCRIPTION_BACKUPPATH]="${NL}Am Backuppfad muss eine Partition gemounted sein auf welcher $FILE_TO_INSTALL die Backups ablegt. \
Das kann eine lokale Partition oder eine remote gemountete Partition."
MSG_FI[$DESCRIPTION_BACKUPPATH]="${NL}Sijainti, johon $FILE_TO_INSTALL:n varmuuskopiot tallennetaan, tulee olla otettuna käyttöön. \
Sijainti voi olla otettu käyttöön joko paikallisesti tai etänä."
MSG_FR[$DESCRIPTION_BACKUPPATH]="${NL}Vous devez indiquer le chemin de sauvegarde: la partition utilisée $FILE_TO_INSTALL doit être montée. \
Cela peut être une partition locale ou une partition distante(ex:samba)."
MSG_ZH[$DESCRIPTION_BACKUPPATH]="${NL}在备份路径必须挂载一个分区，用来为$FILE_TO_INSTALL存储备份文件. \
可以是本地磁盘或者云端磁盘."

DESCRIPTION_BACKUPMODE=$((SCNT++))
MSG_EN[$DESCRIPTION_BACKUPMODE]="${NL}Preferred mode is the normal backup mode. If you need to save more than two partitions with tar or rsync use the partition oriented mode. \
Use normal mode and dd backup if you need a dd backup. Default is to backup the first two partitions only but it's possible to add any additional partition."
MSG_DE[$DESCRIPTION_BACKUPMODE]="${NL}Empfohlener Modus ist der normale Backup Modus. Wenn allerdings mehr als zwei Partitionen gesichert werden sollen mit tar oder rsync ist der paritionsorientiert Modus zu wählen. \
Den normalen Modus muss man aber wählen wenn man ein dd Backup haben möchte. Standard ist nur die ersten beiden Partitionen zu sichern aber es kann jede weitere Partition dazugefügt werden."
MSG_FI[$DESCRIPTION_BACKUPMODE]="${NL}Oletuksena on suositeltu normaali varmuuskopiointitila, jolloin kaksi ensimmäistä osiota varmuuskopioidaan. Jos haluat varmuuskopioida useamman kuin kaksi osiota käyttäen tar:ia tai rsync:iä, käytä jälkimmäistä, osio-orientoitua tilaa. \
Käytä normaalia tilaa ja dd-varmuuskopiointia, jos haluat dd-varmuuskopion."
MSG_FR[$DESCRIPTION_BACKUPMODE]="${NL}Le mode recommandé est le mode de sauvegarde normal. Cependant, si plus de deux partitions doivent être sauvegardées avec tar ou rsync, le mode orienté partition doit être sélectionné. \
Vous devez choisir le mode normal si vous souhaitez une sauvegarde dd. La norme est de ne sauvegarder que les deux premières partitions, mais toute partition supplémentaire peut être ajoutée."
MSG_ZH[$DESCRIPTION_BACKUPMODE]="${NL}预设的是常规备份模式, 若想用tar 或rsync备份2个以上分区，请选择分区导向模式. \
默认只备份前两个分区，但是其他分区也可以自定义."

DESCRIPTION_BACKUPTYPE=$((SCNT++))
MSG_EN[$DESCRIPTION_BACKUPTYPE]="${NL}rsync is the suggested backuptype because when using hardlinks from EXT3/4 filesystem it's fast because only changed or new files will be saved. \
tar should be used if the backup filesystem is no EXT3/4, e.g a remote mounted samba share. Don't use a FAT32 filesystem because the maximum filesize is 4GB. \
dd should be used if you want to restore the backup on a Windows OS. \
dd and tar backups can be compressed. \
For further details about backup type see${NL}https://www.linux-tips-and-tricks.de/en/backup#butypes. \
For further details about the option for dd see${NL}https://www.linux-tips-and-tricks.de/en/faq#a16"
MSG_DE[$DESCRIPTION_BACKUPTYPE]="${NL}rsync ist der empfohlene Backuptyp da durch Hardlinks vom ETX3/4 Dateisystem der Backup schnell ist da nur neue oder geänderte Dateien gesichert werden. \
tar sollte man benutzen wenn das Backupdateisystem kein EXT3/4 ist, z.B. ein remotes Samba Laufwerk. Ein FAT32 Dateisystem ist ungeeignet da die maximale Dateigröße nur 4GB ist. \
dd ist die richtige Wahl wenn man den Backup auf einem Windows OS wiederherstellen will. \
dd und tar Backups können noch zusätzlich komprimiert werden. \
Weiter Details zum Backuptyp finden sich${NL}https://www.linux-tips-and-tricks.de/de/raspibackup#vornach. \
Weitere Details zu der Option für dd siehe${NL}https://www.linux-tips-and-tricks.de/de/faq#a16"
MSG_FI[$DESCRIPTION_BACKUPTYPE]="${NL}EXT3/4-tiedostojärjetelmässä on suositeltavaa valita rsync, sillä hardlinkit nopeuttavat varmuuskopiointia: vain uudet ja muuttuneet tiedostot kopioidaan. \
Valitse tar, jos varmuuskopioitava tiedostojärjestelmä ei ole EXT3/4 tai se on esim. etänä käyttöönotettu samba-jako. Älä käytä FAT32-tiedostojärjestelmää, koska sen maksimitiedostokoko on 4Gt. \
Valitse dd, jos haluat palauttaa varmuuskopion Windows-järjestelmässä. dd- ja tar-varmuuskopiot voidaan pakata tilan säästämiseksi. \
${NL}${NL}Lisätietoja varmuuskopiotyypeistä löydät osoitteestahttps://www.linux-tips-and-tricks.de/en/backup#butypes. \
${NL}Lisätietoja dd:n valinnoista löydät osoitteesta https://www.linux-tips-and-tricks.de/en/faq#a16"
MSG_FR[$DESCRIPTION_BACKUPTYPE]="${NL}rsync est le type de sauvegarde recommandé car le système de fichiers ETX3/4 rend la sauvegarde rapide, seuls les fichiers nouveaux ou modifiés sont enregistrés. \
tar doit être utilisé si le système de fichiers de sauvegarde n'est pas un EXT3/4, par exemple un lecteur Samba distant. Un système de fichiers FAT32 ne convient pas car la taille maximale du fichier n'est que de 4 Go. \
dd est le bon choix si vous souhaitez restaurer la sauvegarde sur un système d'exploitation Windows. \
les sauvegardes dd et tar peuvent également être compressées. \
Vous trouverez plus de détails sur le type de sauvegarde sur${NL}https://www.linux-tips-and-tricks.de/de/raspibackup#vornach. \
Pour dd voir : ${NL}https://www.linux-tips-and-tricks.de/de/faq#a16 "
MSG_ZH[$DESCRIPTION_BACKUPTYPE]="${NL}rsync是建议的备份方法.因为ETX3/4文件系统的硬链接只有在改变时才会被保存\
建议tar在非EXT3/4文件系统上使用，比如云端samba设备 \
建议dd模式在有在windows系统上恢复备份需求时使用. \
dd和tar模式下生成的备份可以被压缩. \
${NL}${NL}更多备份模式类型见:https://www.linux-tips-and-tricks.de/en/backup#butypes. \
${NL}更多dd模式详情见 https://www.linux-tips-and-tricks.de/en/faq#a16"

DESCRIPTION_MAIL_PROGRAM=$((SCNT++))
MSG_EN[$DESCRIPTION_MAIL_PROGRAM]="Select the mail program to use to send notification eMails."
MSG_DE[$DESCRIPTION_MAIL_PROGRAM]="Wähle das Mailprogramm aus welches zum Versenden von Benachrichtigungen benutzt werden soll."
MSG_FI[$DESCRIPTION_MAIL_PROGRAM]="Valitse sähköpostisovellus ilmoitussähköpostien lähettämiseen."
MSG_FR[$DESCRIPTION_MAIL_PROGRAM]="Sélectionnez le programme de messagerie qui doit être utilisé pour envoyer des notifications."
MSG_ZH[$DESCRIPTION_MAIL_PROGRAM]="选择发送邮件的程序."

DESCRIPTION_EMAIL=$((SCNT++))
MSG_EN[$DESCRIPTION_EMAIL]="Enter the eMail address to send notifications to. Enter no eMail address to disable notifications."
MSG_DE[$DESCRIPTION_EMAIL]="Gibt die eMail Adresse ein die Benachrichtigungen erhalten soll. Keine eMail Adresse schaltet Benachrichtigungen aus."
MSG_FI[$DESCRIPTION_EMAIL]="Syötä sähköpostiosoite, johon ilmoitukset lähetetään. Jos et halua ilmoituksia, älä syötä lainkaan sähköpostiosoitetta."
MSG_FR[$DESCRIPTION_EMAIL]="Saisissez l'adresse e-mail pour recevoir les notifications. Aucune adresse e-mail désactive les notifications."
MSG_ZH[$DESCRIPTION_EMAIL]="输入邮件地址，留空则禁用邮件通知."

TITLE_ERROR=$((SCNT++))
MSG_EN[$TITLE_ERROR]="Error"
MSG_DE[$TITLE_ERROR]="Fehler"
MSG_FI[$TITLE_ERROR]="Virhe"
MSG_FR[$TITLE_ERROR]="Erreur"
MSG_ZH[$TITLE_ERROR]="错误"

TITLE_FIRST_STEPS=$((SCNT++))
MSG_EN[$TITLE_FIRST_STEPS]="First steps"
MSG_DE[$TITLE_FIRST_STEPS]="Erste Schritte"
MSG_FI[$TITLE_FIRST_STEPS]="Ensiaskeleet"
MSG_FR[$TITLE_FIRST_STEPS]="En premier"
MSG_ZH[$TITLE_FIRST_STEPS]="第一步"

TITLE_HELP=$((SCNT++))
MSG_EN[$TITLE_HELP]="Help"
MSG_DE[$TITLE_HELP]="Hilfe"
MSG_FI[$TITLE_HELP]="Ohje"
MSG_FR[$TITLE_HELP]="Aide"
MSG_ZH[$TITLE_HELP]="帮助"

TITLE_WARNING=$((SCNT++))
MSG_EN[$TITLE_WARNING]="Warning"
MSG_DE[$TITLE_WARNING]="Warnung"
MSG_FI[$TITLE_WARNING]="Varoitus"
MSG_FR[$TITLE_WARNING]="Attention"
MSG_ZH[$TITLE_WARNING]="警告"

TITLE_INFORMATION=$((SCNT++))
MSG_EN[$TITLE_INFORMATION]="Information"
MSG_DE[$TITLE_INFORMATION]="Information"
MSG_FI[$TITLE_INFORMATION]="Tietoa"
MSG_FR[$TITLE_INFORMATION]="Information"
MSG_ZH[$TITLE_INFORMATION]="信息"

TITLE_VALIDATIONERROR=$((SCNT++))
MSG_EN[$TITLE_VALIDATIONERROR]="Invalid input"
MSG_DE[$TITLE_VALIDATIONERROR]="Ungültige Eingabe"
MSG_FI[$TITLE_VALIDATIONERROR]="Virheellinen syöte"
MSG_FR[$TITLE_VALIDATIONERROR]="Entrée invalide"
MSG_ZH[$TITLE_VALIDATIONERROR]="无效输入"

TITLE_CONFIRM=$((SCNT++))
MSG_EN[$TITLE_CONFIRM]="Please confirm"
MSG_DE[$TITLE_CONFIRM]="Bitte bestätigen"
MSG_FI[$TITLE_CONFIRM]="Ole hyvä ja varmista"
MSG_FR[$TITLE_CONFIRM]="SVP Confirmez"
MSG_ZH[$TITLE_CONFIRM]="请确认"

MSG_INVALID_BACKUPPATH=$((SCNT++))
MSG_EN[$MSG_INVALID_BACKUPPATH]="Backup path %1 does not exist"
MSG_DE[$MSG_INVALID_BACKUPPATH]="Sicherungsverzeichnis %1 existiert nicht"
MSG_FI[$MSG_INVALID_BACKUPPATH]="Polkua %1 ei ole"
MSG_FR[$MSG_INVALID_BACKUPPATH]="Le répertoire de sauvegarde %1 n'existe pas"
MSG_ZH[$MSG_INVALID_BACKUPPATH]="备份路径 %1 不存在"

MSG_INVALID_EMAIL=$((SCNT++))
MSG_EN[$MSG_INVALID_EMAIL]="Invalid eMail address %1"
MSG_DE[$MSG_INVALID_EMAIL]="Ungültige eMail Adresse %1"
MSG_FI[$MSG_INVALID_EMAIL]="Virheellinen sähköpostiosoite %1"
MSG_FR[$MSG_INVALID_EMAIL]="Adresse e-mail invalide %1"
MSG_ZH[$MSG_INVALID_EMAIL]="邮箱地址无效 %1"

MSG_LOCAL_BACKUPPATH=$((SCNT++))
MSG_EN[$MSG_LOCAL_BACKUPPATH]="Backup would be stored on SD card"
MSG_DE[$MSG_LOCAL_BACKUPPATH]="Backup würde auf der SD Karte gespeichert werden"
MSG_FI[$MSG_LOCAL_BACKUPPATH]="Varmuuskopio säilytetään SD-kortilla"
MSG_FR[$MSG_LOCAL_BACKUPPATH]="La sauvegarde sera enregistrée sur la carte SD"
MSG_ZH[$MSG_LOCAL_BACKUPPATH]="备份文件将被存储在SD卡"

MSG_NAVIGATION=$((SCNT++))
MSG_EN[$MSG_NAVIGATION]="Cursor keys: Move cursor to next menu item, list item or button${NL}\
Space key: Select/unselect items in a selection list${NL}\
Tab key: Jump to buttons at the bottom${NL}\
${NL}\
Pfeiltasten: Bewege Schreibmarke zum nächsten Menueintrag, Listeneintrag oder Auswahlknopf${NL}\
Leertaste: Selektiere/Deselektieren Einträge in einer Auswahliste${NL}\
Tab Taste: Springe zu den unteren Auswahlknöpfen"
MSG_DE[$MSG_NAVIGATION]="Pfeiltasten: Bewege Schreibmarke zum nächsten Menueintrag, Listeneintrag oder Auswahlknopf${NL}\
Leertaste: Selektiere/Deselektieren Einträge in einer Auswahliste${NL}\
Tab Taste: Springe zu den unteren Auswahlknöpfen${NL}\
${NL}\
Cursor keys: Move cursor to next menu or list item${NL}\
Space key: Select/unselect items in a selection list${NL}\
Tab key: Jump to buttons at the bottom"
MSG_FI[$MSG_NAVIGATION]="Nuolinäppäimet: Siirrä kursori seuraavaan valikon tai listan kohteeseen${NL}\
Välilyönti: Valitse/poista valinta${NL}\
Sarkain: Kohdista alarivin painikkeisiin${NL}\
${NL}\
Cursor keys: Move cursor to next menu or list item${NL}\
Space key: Select/unselect items in a selection list${NL}\
Tab key: Jump to buttons at the bottom"
MSG_FR[$MSG_NAVIGATION]="Les flèches du clavier, déplacent le curseur du menu, des listes ou du bouton de sélection ${NL}\
Barre d'espace : pour sélectionner/désélectionner des entrées dans une liste ${NL}\
Touche de tabulation : pour accéder aux boutons de sélection du bas ${NL}\
${NL}\
Curseur : déplacez le curseur vers le menu ou un élément d'une liste ${NL}\
Touche d'espace : pour sélectionner/désélectionner des éléments dans une liste"
MSG_ZH[$MSG_NAVIGATION]="箭头方向键:上下移动菜单选项、列表选项或者按钮${NL}\
空格键: 选中或取消勾选${NL}\
Tab: 跳至菜单底部按钮${NL}\
${NL}\
Cursor keys: Move cursor to next menu or list item${NL}\
Space key: Select/unselect items in a selection list${NL}\
Tab key: Jump to buttons at the bottom"


MSG_ABOUT=$((SCNT++))
MSG_EN[$MSG_ABOUT]="$GIT_CODEVERSION${NL}\
%1${NL}${NL}\
This tool provides a straight-forward way of doing installation,${NL} updating and configuration of $RASPIBACKUP_NAME.${NL}${NL}\
Visit https://www.linux-tips-and-tricks.de/en/raspibackup#parameters${NL}for details about all configuration options of $RASPIBACKUP_NAME.${NL}${NL}\
Visit https://www.linux-tips-and-tricks.de/en/raspibackup${NL}for details about $RASPIBACKUP_NAME."
MSG_DE[$MSG_ABOUT]="$GIT_CODEVERSION${NL}\
%1${NL}${NL}\
Dieses Tool ermöglicht es möglichst einfach $RASPIBACKUP_NAME zu installieren,${NL} zu updaten und die Konfiguration anzupassen.${NL}${NL}\
Besuche https://www.linux-tips-and-tricks.de/de/raspibackup#parameter${NL}um alle Konfigurationsoptionen von $RASPIBACKUP_NAME kennenzulernen.${NL}${NL}\
Besuche https://www.linux-tips-and-tricks.de/de/raspibackup${NL}um Weiteres zu $RASPIBACKUP_NAME zu erfahren."
MSG_FI[$MSG_ABOUT]="$GIT_CODEVERSION${NL}\
%1${NL}${NL}\
Tämä työkalu tarjoaa $RASPIBACKUP_NAME:n suoraviivaisen asennuksen,${NL} päivittämisen ja asetusten määrittämisen.${NL}${NL}\
Kaikista $RASPIBACKUP_NAME:n asetuksista löydät tietoa osoitteesta${NL}https://www.linux-tips-and-tricks.de/en/raspibackup#parameters${NL}${NL}\
Löydät lisätietoa $RASPIBACKUP_NAME:sta osoitteesta${NL}https://www.linux-tips-and-tricks.de/en/raspibackup"
MSG_FR[$MSG_ABOUT]="$GIT_CODEVERSION${NL}\
%1${NL}${NL}\
Cet outil facilite au maximum la mise en place de $RASPIBACKUP_NAME ,la mise à jour ,${NL} et la configuration.${NL}${NL}\
Visitez https://www.linux-tips-and-tricks.de/en/raspibackup#parameters${NL}pour plus de détails sur toutes les options de configuration de $RASPIBACKUP_NAME.${NL}${NL}\
Visitez https://www.linux-tips-and-tricks.de/en/raspibackup${NL}pour plus de détails sur $RASPIBACKUP_NAME."
MSG_ZH[$MSG_ABOUT]="$GIT_CODEVERSION${NL}\
%1${NL}${NL}\
此界面提供一个$RASPIBACKUP_NAME的安装引导,${NL}更新和设置页面.${NL}${NL}\
$RASPIBACKUP_NAME的的详情设置请访问${NL}https://www.linux-tips-and-tricks.de/en/raspibackup#parameters${NL}${NL}\
获取$RASPIBACKUP_NAME详情请访问:{NL}https://www.linux-tips-and-tricks.de/en/raspibackup "

MSG_FIRST_STEPS=$((SCNT++))
MSG_EN[$MSG_FIRST_STEPS]="Congratulations! $RASPIBACKUP_NAME installed successfully.${NL}${NL}\
Next steps:${NL}
1) Start $RASPIBACKUP_NAME in the commandline and create a backup${NL}\
2) Start $RASPIBACKUP_NAME to restore the backup on a different SD card${NL}\
3) Verify the restored backup works fine.${NL}\
4) Read the FAQ page https://www.linux-tips-and-tricks.de/en/faq${NL}\
5) Visit the options page and fine tune $RASPIBACKUP_NAME${NL}\
   https://www.linux-tips-and-tricks.de/en/raspibackup#parameters${NL}\
6) Enable regular backup with the installer${NL}\
7) Visit https://www.linux-tips-and-tricks.de/en/backup for a lot more information about $RASPIBACKUP_NAME"
MSG_DE[$MSG_FIRST_STEPS]="Herzlichen Glückwunsch! $RASPIBACKUP_NAME wurde erfolgreich installiert.${NL}${NL}\
Nächsten Schritte:${NL}
1) Starte $RASPIBACKUP_NAME in der Befehlszeile und erzeuge ein Backup${NL}\
2) Starte $RASPIBACKUP_NAME um das erzeugte Backup auf einer andere SD Karte wiederherzustellen.${NL}\
3) Verifiziere dass das System ohne Probleme läuft.${NL}\
4) Lies die FAQ Seite https://www.linux-tips-and-tricks.de/de/faq${NL}\
5) Besuche die Optionsseite und konfiguriere $RASPIBACKUP_NAME genau nach Deinen Vorstellungen${NL}\
   https://www.linux-tips-and-tricks.de/de/raspibackup#parameters${NL}\
6) Schalte den regelmäßigen Backup mit dem Installer ein${NL}\
7) Besuche https://www.linux-tips-and-tricks.de/en/backup um noch wesentlich detailiertere Informationen zu $RASPIBACKUP_NAME zu erhalten"
MSG_FI[$MSG_FIRST_STEPS]="Onnittelut! $RASPIBACKUP_NAME on asennettu onnistuneesti.${NL}${NL}\
Seuraavat vaiheet:${NL}
1) Käynnistä $RASPIBACKUP_NAME komentoriviltä ja luo varmuuskopio${NL}\
2) Käynnistä $RASPIBACKUP_NAME palauttaaksesi varmuuskopion toiselle SD-kortille${NL}\
3) Varmista, että palautettu varmuuskopio toimii oikein.${NL}\
4) Lue FAQ-sivu osoitteessa https://www.linux-tips-and-tricks.de/en/faq${NL}\
5) Käy valintasivulla ja tee $RASPIBACKUP_NAME$-hienosäädöt{NL}\
   https://www.linux-tips-and-tricks.de/en/raspibackup#parameters${NL}\
6) Ota käyttöön säännölliset varmuuskopiot asennusohjelmalla${NL}\
7) Käy osoitteessa https://www.linux-tips-and-tricks.de/en/backup ja lue paljon lisää $RASPIBACKUP_NAME-tietoa"
MSG_FR[$MSG_FIRST_STEPS]="Toutes nos félicitations! $RASPIBACKUP_NAME est installé avec succès.${NL}${NL}\
Prochaines étapes :${NL}
1) Démarrez $RASPIBACKUP_NAME dans la ligne de commande et créez une sauvegarde${NL}\
2) Démarrez $RASPIBACKUP_NAME pour restaurer la sauvegarde sur une autre carte SD${NL}\
3) Vérifiez que la sauvegarde restaurée fonctionne correctement.${NL}\
4) Lisez la page FAQ https://www.linux-tips-and-tricks.de/en/faq${NL}\
5) Visitez la page des options et améliorez $RASPIBACKUP_NAME${NL}\
   https://www.linux-tips-and-tricks.de/en/raspibackup#parameters${NL}\
6) Activez la sauvegarde régulière avec le programme raspiBackupInstallUI.sh${NL}\
7) Visitez https://www.linux-tips-and-tricks.de/en/backup pour avoir des informations sur $RASPIBACKUP_NAME"
MSG_ZH[$MSG_FIRST_STEPS]="恭喜! $RASPIBACKUP_NAME 安装成功.${NL}${NL}\
接下来你可以:${NL}
1) 在终端输入 $RASPIBACKUP_NAME开始备份 ${NL}\
2) 在终端输入 $RASPIBACKUP_NAME 还原备份到SD卡${NL}\
3) 校验备份文件.${NL}\
4) 参考FAQ页面 https://www.linux-tips-and-tricks.de/en/faq${NL}\
5) 进行设置和微调项 $RASPIBACKUP_NAME${NL}\
   https://www.linux-tips-and-tricks.de/en/raspibackup#parameters${NL}\
6) 开启定期备份${NL}\
7) 访问https://www.linux-tips-and-tricks.de/en/backup 获取更多$RASPIBACKUP_NAME信息"

MSG_HELP=$((SCNT++))
MSG_EN[$MSG_HELP]="In case you have any issue or question about $RASPIBACKUP_NAME just use one of the following paths to get help${NL}
1) Read the FAQ page https://www.linux-tips-and-tricks.de/en/faq${NL}\
2) Visit https://www.linux-tips-and-tricks.de/en/backup for a lot more information about $RASPIBACKUP_NAME${NL}\
3) Create an issue on github https://github.com/framps/raspiBackup/issues. That's my preference${NL}\
4) Add comments on any webpage dealing with $RASPIBACKUP_NAME on $MYHOMEDOMAIN${NL}\
5) Visit $RASPIBACKUP_NAME on Facebook"
MSG_DE[$MSG_HELP]="Falls es irgendwelche Fragen oder Probleme zu $RASPIBACKUP_NAME gibt bestehen folgende Möglichkeiten Hilfe zu bekommen${NL}
1) Lies die FAQ Seite https://www.linux-tips-and-tricks.de/de/faq${NL}\
2) Besuche https://www.linux-tips-and-tricks.de/en/backup um noch wesentlich detailiertere Informationen zu $RASPIBACKUP_NAME zu erhalten${NL}\
3) Erstelle einen Fehlerbericht auf github https://github.com/framps/raspiBackup/issues. Gerne auch in Deutsch. Das ist meine Präferenz.${NL} \
4) Erstelle einen Kommentar auf jeder Webseite zu $RASPIBACKUP_NAME auf $MYHOMEDOMAIN${NL}\
5) Besuche $RASPIBACKUP_NAME auf Facebook"
MSG_FI[$MSG_HELP]="Jos sinulla on kysymyksiä tai ongelmia $RASPIBACKUP_NAME:n kanssa, käytä jotain seuraavista tavoista saadaksesi apua${NL}
1) Lue FAQ-sivu osoitteessa https://www.linux-tips-and-tricks.de/en/faq${NL}\
2) Käy osoitteessa https://www.linux-tips-and-tricks.de/en/backup ja lue paljon lisää $RASPIBACKUP_NAME-tietoa${NL}\
3) Luo issue githubissa https://github.com/framps/raspiBackup/issues. Tätä suosin.${NL}\
4) Lisää kommentti $RASPIBACKUP_NAME-verkkosivuilla osoitteessa $MYHOMEDOMAIN${NL}\
5) Käy $RASPIBACKUP_NAME:n Facebook-sivulla"
MSG_FR[$MSG_HELP]="Si vous avez un problème ou une question concernant $RASPIBACKUP_NAME, utilisez simplement un des liens suivants pour obtenir une aide :${NL}
1) Lisez la page FAQ https://www.linux-tips-and-tricks.de/en/faq${NL}\
2) Visitez https://www.linux-tips-and-tricks.de/en/backup pour plus d'informations sur $RASPIBACKUP_NAME${NL}\
3) Exposez le problème sur github https://github.com/framps/raspiBackup/issues. C'est ma préférence${NL}\
4) Ajoutez des commentaires sur toute page Web traitant de $RASPIBACKUP_NAME sur $MYHOMEDOMAIN${NL}\
5) Visitez $RASPIBACKUP_NAME sur Facebook"
MSG_ZH[$MSG_HELP]="如果你有任何关于 $RASPIBACKUP_NAME 的问题，请用以下方式联系${NL}
1) 参考FAQ页面 https://www.linux-tips-and-tricks.de/en/faq${NL}\
2) 访问 https://www.linux-tips-and-tricks.de/en/backup 获取更多$RASPIBACKUP_NAME$信息{NL}\
3) 在github上创建issues https://github.com/framps/raspiBackup/issues. 通常选这项!${NL}\
4) 在 $MYHOMEDOMAIN$上关于$RASPIBACKUP_NAME的页面留言评论{NL}\
5) 访问$RASPIBACKUP_NAME 的Facebook页面"

MSG_FIRST_PARTITIONS_NOT_SELECTED=$((SCNT++))
MSG_EN[$MSG_FIRST_PARTITIONS_NOT_SELECTED]="At least the first two partitions have to be selected."
MSG_DE[$MSG_FIRST_PARTITIONS_NOT_SELECTED]="Wenigstens die beiden ersten Partitionen müssen ausgewählt sein."

MSG_SENSITIVE_WARNING=$((SCNT++))
MSG_EN[$MSG_SENSITIVE_WARNING]="| ===> A lot of sensitive information is masqueraded in this log file. Nevertheless please check the log carefully before you distribute it <=== |"
MSG_DE[$MSG_SENSITIVE_WARNING]="| ===>  Viele sensitive Informationen werden in dieser Logdatei maskiert. Vor dem Verteilen des Logs sollte es trotzdem ueberprueft werden  <=== |"
MSG_FI[$MSG_SENSITIVE_WARNING]="| ===>            Sensitiivisiä tietoja on piilotettu tästä lokitiedostosta. Tarkista lisäksi loki huolellisesti ennen sen jakoa            <=== |"
MSG_FR[$MSG_SENSITIVE_WARNING]="| ===>De nombreuses informations sensibles sont masquées dans ce fichier journal. Avant de distribuer le log, il faut quand même le vérifier<=== |"

MSG_SENSITIVE_SEPARATOR=$((SCNT++))
MSG_EN[$MSG_SENSITIVE_SEPARATOR]="+================================================================================================================================================+"

declare -A MENU_EN
declare -A MENU_DE
declare -A MENU_FI
declare -A MENU_FR
declare -A MENU_ZH

MCNT=0
MENU_UNDEFINED=$((MCNT++))
MENU_EN[$MENU_UNDEFINED]="Undefined menuid."
MENU_DE[$MENU_UNDEFINED]="Unbekannte menuid."
MENU_FI[$MENU_UNDEFINED]="Määrittämätön valikon id."
MENU_FR[$MENU_UNDEFINED]="Id du menu inconnu."
MENU_ZH[$MENU_UNDEFINED]="未定义的菜单id."

MENU_LANGUAGE=$((MCNT++))
MENU_EN[$MENU_LANGUAGE]='"M1" "Language"'
MENU_DE[$MENU_LANGUAGE]='"M1" "Sprache"'
MENU_FI[$MENU_LANGUAGE]='"M1" "Kieli"'
MENU_FR[$MENU_LANGUAGE]='"M1" "Choisir la langue"'
MENU_ZH[$MENU_LANGUAGE]='"M1" "语言"'

MENU_INSTALL=$((MCNT++))
MENU_EN[$MENU_INSTALL]='"M2" "Install components"'
MENU_DE[$MENU_INSTALL]='"M2" "Installiere Komponenten"'
MENU_FI[$MENU_INSTALL]='"M2" "Asenna komponentteja"'
MENU_FR[$MENU_INSTALL]='"M2" "Installation des composants"'
MENU_ZH[$MENU_INSTALL]='"M2" "安装组件"'

MENU_CONFIGURE=$((MCNT++))
MENU_EN[$MENU_CONFIGURE]='"M3" "Configure major options"'
MENU_DE[$MENU_CONFIGURE]='"M3" "Konfiguriere die wichtigsten Optionen"'
MENU_FI[$MENU_CONFIGURE]='"M3" "Määritä pääasetukset"'
MENU_FR[$MENU_CONFIGURE]='"M3" "Configurer les options importantes"'
MENU_ZH[$MENU_CONFIGURE]='"M3" "设置主要选项"'

MENU_UNINSTALL=$((MCNT++))
MENU_EN[$MENU_UNINSTALL]='"M4" "Delete components"'
MENU_DE[$MENU_UNINSTALL]='"M4" "Lösche Komponenten"'
MENU_FI[$MENU_UNINSTALL]='"M4" "Poista komponentteja"'
MENU_FR[$MENU_UNINSTALL]='"M4" "Supprimer des composants"'
MENU_ZH[$MENU_UNINSTALL]='"M4" "删除组件"'

MENU_UPDATE=$((MCNT++))
MENU_EN[$MENU_UPDATE]='"M5" "Update components"'
MENU_DE[$MENU_UPDATE]='"M5" "Aktualisiere Komponenten"'
MENU_FI[$MENU_UPDATE]='"M5" "Päivitä komponentteja"'
MENU_FR[$MENU_UPDATE]='"M5" "Mettre à jour des composants"'
MENU_ZH[$MENU_UPDATE]='"M5" "更新组件"'

MENU_ABOUT=$((MCNT++))
MENU_EN[$MENU_ABOUT]='"M9" "About and useful links"'
MENU_DE[$MENU_ABOUT]='"M9" "About und hilfreiche Links"'
MENU_FI[$MENU_ABOUT]='"M9" "Tietoja ja hyödyllisiä linkkejä"'
MENU_FR[$MENU_ABOUT]='"M9" "A propos et liens utiles"'
MENU_ZH[$MENU_ABOUT]='"M9" "关于&链接"'

MENU_REGULARBACKUP_ENABLE=$((MCNT++))
MENU_EN[$MENU_REGULARBACKUP_ENABLE]='"R1" "Enable regular backup"'
MENU_DE[$MENU_REGULARBACKUP_ENABLE]='"R1" "Regelmäßiges Backup einschalten"'
MENU_FI[$MENU_REGULARBACKUP_ENABLE]='"R1" "Ota käyttöön säännöllinen varmuuskopiointi"'
MENU_FR[$MENU_REGULARBACKUP_ENABLE]='"R1" "Activer une sauvegarde régulière"'
MENU_ZH[$MENU_REGULARBACKUP_ENABLE]='"R1" "开启定期备份"'

MENU_REGULARBACKUP_DISABLE=$((MCNT++))
MENU_EN[$MENU_REGULARBACKUP_DISABLE]='"R1" "Disable regular backup"'
MENU_DE[$MENU_REGULARBACKUP_DISABLE]='"R1" "Regelmäßiges Backup auschalten"'
MENU_FI[$MENU_REGULARBACKUP_DISABLE]='"R1" "Poista säännöllinen varmuuskopiointi käytöstä"'
MENU_FR[$MENU_REGULARBACKUP_DISABLE]='"R1" "Désactiver la sauvegarde régulière"'
MENU_ZH[$MENU_REGULARBACKUP_DISABLE]='"R1" "禁用定期备份"'

MENU_CONFIG_DAY=$((MCNT++))
MENU_EN[$MENU_CONFIG_DAY]='"R2" "Weekday of regular backup"'
MENU_DE[$MENU_CONFIG_DAY]='"R2" "Wochentag des regelmäßigen Backups"'
MENU_FI[$MENU_CONFIG_DAY]='"R2" "Säännöllisen varmuuskopioinnin viikonpäivä"'
MENU_FR[$MENU_CONFIG_DAY]='"R2" "Choisir le jour de la semaine de la sauvegarde"'
MENU_ZH[$MENU_CONFIG_DAY]='"R2" "每日备份"'

MENU_CONFIG_TIME=$((MCNT++))
MENU_EN[$MENU_CONFIG_TIME]='"R3" "Time of regular backup"'
MENU_DE[$MENU_CONFIG_TIME]='"R3" "Zeit des regelmäßigen Backups"'
MENU_FI[$MENU_CONFIG_TIME]='"R3" "Säännöllisen varmuuskopioinnin kellonaika"'
MENU_FR[$MENU_CONFIG_TIME]='"R3" "Choisir une heure pour la sauvegarde "'
MENU_ZH[$MENU_CONFIG_TIME]='"R3" "定期备份间隔"'

MENU_CONFIG_LANGUAGE_EN=$((MCNT++))
MENU_EN[$MENU_CONFIG_LANGUAGE_EN]='"EN" "English"'
MENU_DE[$MENU_CONFIG_LANGUAGE_EN]='"EN" "Englisch"'
MENU_FI[$MENU_CONFIG_LANGUAGE_EN]='"EN" "englanti"'
MENU_FR[$MENU_CONFIG_LANGUAGE_EN]='"EN" "Anglais"'
MENU_ZH[$MENU_CONFIG_LANGUAGE_EN]='"EN" "英语"'

MENU_CONFIG_LANGUAGE_DE=$((MCNT++))
MENU_EN[$MENU_CONFIG_LANGUAGE_DE]='"DE" "German"'
MENU_DE[$MENU_CONFIG_LANGUAGE_DE]='"DE" "Deutsch"'
MENU_FI[$MENU_CONFIG_LANGUAGE_DE]='"DE" "saksa"'
MENU_FR[$MENU_CONFIG_LANGUAGE_DE]='"DE" "Allemand"'
MENU_ZH[$MENU_CONFIG_LANGUAGE_DE]='"DE" "德语"'

MENU_CONFIG_LANGUAGE_FI=$((MCNT++))
MENU_EN[$MENU_CONFIG_LANGUAGE_FI]='"FI" "Finnish"'
MENU_DE[$MENU_CONFIG_LANGUAGE_FI]='"FI" "Finnisch"'
MENU_FI[$MENU_CONFIG_LANGUAGE_FI]='"FI" "suomi"'
MENU_FR[$MENU_CONFIG_LANGUAGE_FI]='"FI" "Finlandais"'
MENU_ZH[$MENU_CONFIG_LANGUAGE_FI]='"FI" "芬兰语"'

MENU_CONFIG_LANGUAGE_FR=$((MCNT++))
MENU_EN[$MENU_CONFIG_LANGUAGE_FR]='"FR" "French"'
MENU_DE[$MENU_CONFIG_LANGUAGE_FR]='"FR" "Französisch"'
MENU_FI[$MENU_CONFIG_LANGUAGE_FR]='"FR" "Ranskan kieli"'
MENU_FR[$MENU_CONFIG_LANGUAGE_FR]='"FR" "Français"'
MENU_ZH[$MENU_CONFIG_LANGUAGE_FR]='"FR" "法語"'

MENU_CONFIG_LANGUAGE_ZH=$((MCNT++))
MENU_EN[$MENU_CONFIG_LANGUAGE_ZH]='"ZH" "Chinese"'
MENU_DE[$MENU_CONFIG_LANGUAGE_ZH]='"ZH" "Chinesisch"'
MENU_FI[$MENU_CONFIG_LANGUAGE_ZH]='"ZH" "Kiina"'
MENU_FR[$MENU_CONFIG_LANGUAGE_ZH]='"ZH" "Chinois"'
MENU_ZH[$MENU_CONFIG_LANGUAGE_ZH]='"ZH" "中文"'

MENU_CONFIG_MESSAGE_N=$((MCNT++))
MENU_EN[$MENU_CONFIG_MESSAGE_N]='"Normal" "Display important messages only"'
MENU_DE[$MENU_CONFIG_MESSAGE_N]='"Normal" "Nur wichtige Meldungen anzeigen"'
MENU_FI[$MENU_CONFIG_MESSAGE_N]='"Normaali" "Näytä vain tärkeät viestit"'
MENU_FR[$MENU_CONFIG_MESSAGE_N]='"Normal" "Afficher uniquement les messages importants"'
MENU_ZH[$MENU_CONFIG_MESSAGE_N]='"一般" "仅显示重要信息"'

MENU_CONFIG_MESSAGE_V=$((MCNT++))
MENU_EN[$MENU_CONFIG_MESSAGE_V]='"Verbose" "Display all messages"'
MENU_DE[$MENU_CONFIG_MESSAGE_V]='"Detailiert" "Alle Meldungen anzeigen"'
MENU_FI[$MENU_CONFIG_MESSAGE_V]='"Tarkka" "Näytä kaikki viestit"'
MENU_FR[$MENU_CONFIG_MESSAGE_V]='"Complet" "Afficher tous les messages"'
MENU_ZH[$MENU_CONFIG_MESSAGE_V]='"详细" "显示所有信息"'

MENU_CONFIG_BACKUPPATH=$((MCNT++))
MENU_EN[$MENU_CONFIG_BACKUPPATH]='"C2" "Backup path"'
MENU_DE[$MENU_CONFIG_BACKUPPATH]='"C2" "Backupverzeichnispfad"'
MENU_FI[$MENU_CONFIG_BACKUPPATH]='"C2" "Varmuuskopioiden sijainti"'
MENU_FR[$MENU_CONFIG_BACKUPPATH]='"C2" "Choisir le répertoire de sauvegarde"'
MENU_ZH[$MENU_CONFIG_BACKUPPATH]='"C2" "备份路径"'

MENU_CONFIG_BACKUPS=$((MCNT++))
MENU_EN[$MENU_CONFIG_BACKUPS]='"C3" "Backup versions"'
MENU_DE[$MENU_CONFIG_BACKUPS]='"C3" "Backupversionen"'
MENU_FI[$MENU_CONFIG_BACKUPS]='"C3" "Varmuuskopioiden versioiden säilytys"'
MENU_FR[$MENU_CONFIG_BACKUPS]='"C3" "Versions de sauvegarde"'
MENU_ZH[$MENU_CONFIG_BACKUPS]='"C3" "备份版本"'

MENU_CONFIG_TYPE=$((MCNT++))
MENU_EN[$MENU_CONFIG_TYPE]='"C4" "Backup type"'
MENU_DE[$MENU_CONFIG_TYPE]='"C4" "Backup Typ"'
MENU_FI[$MENU_CONFIG_TYPE]='"C4" "Varmuuskopiontien tyyppi"'
MENU_FR[$MENU_CONFIG_TYPE]='"C4" "Type de sauvegarde"'
MENU_ZH[$MENU_CONFIG_TYPE]='"C4" "备份类型"'

MENU_CONFIG_MODE=$((MCNT++))
MENU_EN[$MENU_CONFIG_MODE]='"C5" "Backup mode"'
MENU_DE[$MENU_CONFIG_MODE]='"C5" "Backup Modus"'
MENU_FI[$MENU_CONFIG_MODE]='"C5" "Varmuuskopiointitila"'
MENU_FR[$MENU_CONFIG_MODE]='"C5" "Mode de sauvegarde"'
MENU_ZH[$MENU_CONFIG_MODE]='"C5" "备份模式"'

MENU_CONFIG_SERVICES=$((MCNT++))
MENU_EN[$MENU_CONFIG_SERVICES]='"C6" "Services to stop and start"'
MENU_DE[$MENU_CONFIG_SERVICES]='"C6" "Zu stoppende und startende Services"'
MENU_FI[$MENU_CONFIG_SERVICES]='"C6" "Palveluiden pysäyttäminen ja uudelleenkäynnistäminen"'
MENU_FR[$MENU_CONFIG_SERVICES]='"C6" "Services à arrêter ou à démarrer"'
MENU_ZH[$MENU_CONFIG_SERVICES]='"C6" "需要处理的系统服务"'

MENU_CONFIG_MESSAGE=$((MCNT++))
MENU_EN[$MENU_CONFIG_MESSAGE]='"C7" "Message verbosity"'
MENU_DE[$MENU_CONFIG_MESSAGE]='"C7" "Meldungsgenauigkeit"'
MENU_FI[$MENU_CONFIG_MESSAGE]='"C7" "Viestien yksityiskohtaisuus"'
MENU_FR[$MENU_CONFIG_MESSAGE]='"C7" "Affichage des messages"'
MENU_ZH[$MENU_CONFIG_MESSAGE]='"C7" "信息设置"'

MENU_CONFIG_EMAIL=$((MCNT++))
MENU_EN[$MENU_CONFIG_EMAIL]='"C8" "eMail notification"'
MENU_DE[$MENU_CONFIG_EMAIL]='"C8" "eMail Benachrichtigung"'
MENU_FI[$MENU_CONFIG_EMAIL]='"C8" "Sähköposti-ilmoitus"'
MENU_FR[$MENU_CONFIG_EMAIL]='"C8" "Notification par courrier électronique"'
MENU_ZH[$MENU_CONFIG_EMAIL]='"C8" "邮件通知"'

MENU_CONFIG_REGULAR=$((MCNT++))
MENU_EN[$MENU_CONFIG_REGULAR]='"C9" "Regular backup"'
MENU_DE[$MENU_CONFIG_REGULAR]='"C9" "Regelmäßiges Backup"'
MENU_FI[$MENU_CONFIG_REGULAR]='"C9" "Säännöllinen varmuuskopiointi"'
MENU_FR[$MENU_CONFIG_REGULAR]='"C9" "Sauvegardes Régulières"'
MENU_ZH[$MENU_CONFIG_REGULAR]='"C9" "定期备份"'

MENU_CONFIG_ZIP=$((MCNT++))
MENU_EN[$MENU_CONFIG_ZIP]='"C10" "Compression"'
MENU_DE[$MENU_CONFIG_ZIP]='"C10" "Komprimierung"'
MENU_FI[$MENU_CONFIG_ZIP]='"C10" "Pakkaaminen"'
MENU_FR[$MENU_CONFIG_ZIP]='"C10" "Compression"'
MENU_ZH[$MENU_CONFIG_ZIP]='"C10" "压缩"'

MENU_CONFIG_ZIP_NA=$((MCNT++))
MENU_EN[$MENU_CONFIG_ZIP_NA]='" " " "'
MENU_DE[$MENU_CONFIG_ZIP_NA]='" " " "'
MENU_FI[$MENU_CONFIG_ZIP_NA]='" " " "'
MENU_FR[$MENU_CONFIG_ZIP_NA]='" " " "'
MENU_ZH[$MENU_CONFIG_ZIP_NA]='" " " "'

MENU_CONFIG_MODE_KEEP=$((MCNT++))
MENU_EN[$MENU_CONFIG_MODE_KEEP]='"Simple" "Keep a maximum number of backups"'
MENU_DE[$MENU_CONFIG_MODE_KEEP]='"Einfach" "Eine maximale Anzahl von Backups vorhalten"'
MENU_FI[$MENU_CONFIG_MODE_KEEP]='"Yksinkertainen" "Säilytä valitsemasi lukumäärän verran varmuuskopioita"'
MENU_FR[$MENU_CONFIG_MODE_KEEP]='"Simple" "En choisissant un nombre maximum de sauvegardes"'
MENU_ZH[$MENU_CONFIG_MODE_KEEP]='"简单" "保留最大数量的备份文件"'

MENU_CONFIG_MODE_SMART=$((MCNT++))
MENU_EN[$MENU_CONFIG_MODE_SMART]='"Smart" "Smart backup strategy"'
MENU_DE[$MENU_CONFIG_MODE_SMART]='"Intelligent" "Intelligente Backupstrategie "'
MENU_FI[$MENU_CONFIG_MODE_SMART]='"Älykäs" "Älykäs varmuuskopiointistrategia"'
MENU_FR[$MENU_CONFIG_MODE_SMART]='"Intelligente" "Avec la stratégie ntelligente"'
MENU_ZH[$MENU_CONFIG_MODE_SMART]='"智能" "智能备份策略"'

MENU_CONFIG_MODE_NORMAL=$((MCNT++))
MENU_EN[$MENU_CONFIG_MODE_NORMAL]='"Standard" "Backup the two standard partitions"'
MENU_DE[$MENU_CONFIG_MODE_NORMAL]='"Standard" "Sichere die zwei Standardpartitionen "'
MENU_FI[$MENU_CONFIG_MODE_NORMAL]='"Standardi" "Varmuuskopioi kaksi standardiosiota"'
MENU_FR[$MENU_CONFIG_MODE_NORMAL]='"Standard" "Sauvegarde des deux partitions standards"'
MENU_ZH[$MENU_CONFIG_MODE_NORMAL]='"标准" "备份2个标准分区"'

MENU_CONFIG_MODE_PARTITION=$((MCNT++))
MENU_EN[$MENU_CONFIG_MODE_PARTITION]='"Extended" "Backup more than two partitions"'
MENU_DE[$MENU_CONFIG_MODE_PARTITION]='"Erweitert" "Sichere mehr als zwei Partitionen"'
MENU_FI[$MENU_CONFIG_MODE_PARTITION]='"Laajennettu" "Varmuuskopioi enemmän kuin kaksi osiota"'
MENU_FR[$MENU_CONFIG_MODE_PARTITION]='"Elargi" "Sauvegarde de plus de deux partitions"'
MENU_ZH[$MENU_CONFIG_MODE_PARTITION]='"扩展" "备份多于2个分区"'

MENU_INSTALL_INSTALL=$((MCNT++))
MENU_EN[$MENU_INSTALL_INSTALL]='"I1" "Install $RASPIBACKUP_NAME using a default configuration"'
MENU_DE[$MENU_INSTALL_INSTALL]='"I1" "Installiere $RASPIBACKUP_NAME mit einer Standardkonfiguration"'
MENU_FI[$MENU_INSTALL_INSTALL]='"I1" "Asenna $RASPIBACKUP_NAME oletusasetuksilla"'
MENU_FR[$MENU_INSTALL_INSTALL]='"I1" "Installer $RASPIBACKUP_NAME en utilisant une configuration par défaut"'
MENU_ZH[$MENU_INSTALL_INSTALL]='"I1" "使用默认设置安装 $RASPIBACKUP_NAME "'

MENU_INSTALL_EXTENSIONS=$((MCNT++))
MENU_EN[$MENU_INSTALL_EXTENSIONS]='"I2" "Install and enable sample extension"'
MENU_DE[$MENU_INSTALL_EXTENSIONS]='"I2" "Installiere Beispielerweiterungen"'
MENU_FI[$MENU_INSTALL_EXTENSIONS]='"I2" "Asenna ja ota käyttöön näytelisäosat"'
MENU_FR[$MENU_INSTALL_EXTENSIONS]='"I2" "Installer et activer l'\''exemple d'\''extension"'
MENU_ZH[$MENU_INSTALL_EXTENSIONS]='"I2" "安装并开启示例扩展"'

MENU_CONFIG_MAIL_MAIL=$((MCNT++))
MENU_EN[$MENU_CONFIG_MAIL_MAIL]='"mail" ""'
MENU_DE[$MENU_CONFIG_MAIL_MAIL]='"mail" ""'
MENU_FI[$MENU_CONFIG_MAIL_MAIL]='"mail" ""'
MENU_FR[$MENU_CONFIG_MAIL_MAIL]='"mail" ""'
MENU_ZH[$MENU_CONFIG_MAIL_MAIL]='"mail" ""'

MENU_CONFIG_MAIL_SSMTP=$((MCNT++))
MENU_EN[$MENU_CONFIG_MAIL_SSMTP]='"ssmtp" ""'
MENU_DE[$MENU_CONFIG_MAIL_SSMTP]='"ssmtp" ""'
MENU_FI[$MENU_CONFIG_MAIL_SSMTP]='"ssmtp" ""'
MENU_FR[$MENU_CONFIG_MAIL_SSMTP]='"ssmtp" ""'
MENU_ZH[$MENU_CONFIG_MAIL_SSMTP]='"ssmtp" ""'

MENU_CONFIG_MAIL_MSMTP=$((MCNT++))
MENU_EN[$MENU_CONFIG_MAIL_MSMTP]='"msmtp" ""'
MENU_DE[$MENU_CONFIG_MAIL_MSMTP]='"msmtp" ""'
MENU_FI[$MENU_CONFIG_MAIL_MSMTP]='"msmtp" ""'
MENU_FR[$MENU_CONFIG_MAIL_MSMTP]='"msmtp" ""'
MENU_ZH[$MENU_CONFIG_MAIL_MSMTP]='"msmtp" ""'

MENU_CONFIG_TYPE_DD=$((MCNT++))
MENU_EN[$MENU_CONFIG_TYPE_DD]='"dd" "Backup with dd and restore on Windows"'
MENU_DE[$MENU_CONFIG_TYPE_DD]='"dd" "Sichere mit dd und stelle unter Windows wieder her"'
MENU_FI[$MENU_CONFIG_TYPE_DD]='"dd" "dd-varmuuskopio, mahdollistaa palautuksen Windowsissa"'
MENU_FR[$MENU_CONFIG_TYPE_DD]='"dd" "Sauvegarder avec dd et restaurer sous Windows"'
MENU_ZH[$MENU_CONFIG_TYPE_DD]='"dd" "使用dd备份并且在Windows上恢复"'

MENU_CONFIG_TYPE_TAR=$((MCNT++))
MENU_EN[$MENU_CONFIG_TYPE_TAR]='"tar" "Backup with tar"'
MENU_DE[$MENU_CONFIG_TYPE_TAR]='"tar" "Sichere mit tar"'
MENU_FI[$MENU_CONFIG_TYPE_TAR]='"tar" "tar-varmuuskopio"'
MENU_FR[$MENU_CONFIG_TYPE_TAR]='"tar" "Sauvegarde avec tar"'
MENU_ZH[$MENU_CONFIG_TYPE_TAR]='"tar" "使用tar备份"'

MENU_CONFIG_TYPE_RSYNC=$((MCNT++))
MENU_EN[$MENU_CONFIG_TYPE_RSYNC]='"rsync" "Backup with rsync and use hardlinks if possible"'
MENU_DE[$MENU_CONFIG_TYPE_RSYNC]='"rsync" "Sichere mit rsync und benutze Hardlinks wenn möglich"'
MENU_FI[$MENU_CONFIG_TYPE_RSYNC]='"rsync" "rsync-varmuuskopio ja hardlinkkien käyttö"'
MENU_FR[$MENU_CONFIG_TYPE_RSYNC]='"rsync" "Sécuriser avec rsync en utilisant si possible des liens physiques"'
MENU_ZH[$MENU_CONFIG_TYPE_RSYNC]='"rsync" "使用rsync备份,如果可能,使用硬链接"'

MENU_UNINSTALL_UNINSTALL=$((MCNT++))
MENU_EN[$MENU_UNINSTALL_UNINSTALL]='"U1" "Uninstall $RASPIBACKUP_NAME"'
MENU_DE[$MENU_UNINSTALL_UNINSTALL]='"U1" "Lösche $RASPIBACKUP_NAME"'
MENU_FI[$MENU_UNINSTALL_UNINSTALL]='"U1" "Poista $RASPIBACKUP_NAME -asennus"'
MENU_FR[$MENU_UNINSTALL_UNINSTALL]='"U1" "Supprimer $RASPIBACKUP_NAME -asennus"'
MENU_ZH[$MENU_UNINSTALL_UNINSTALL]='"U1" "卸载 $RASPIBACKUP_NAME"'

MENU_UNINSTALL_EXTENSION=$((MCNT++))
MENU_EN[$MENU_UNINSTALL_EXTENSION]='"U2" "Uninstall and disable sample extensions"'
MENU_DE[$MENU_UNINSTALL_EXTENSION]='"U2" "Lösche Extensions"'
MENU_FI[$MENU_UNINSTALL_EXTENSION]='"U2" "Poista käytöstä ja pura näytelisäosien asennukset"'
MENU_FR[$MENU_UNINSTALL_EXTENSION]='"U2" "Supprimer les Extensions"'
MENU_ZH[$MENU_UNINSTALL_EXTENSION]='"U2" "卸载并禁用示例扩展"'

MENU_CONFIG_TYPE_DD_NA=$((MCNT++))
MENU_EN[$MENU_CONFIG_TYPE_DD_NA]='"" "Backup with dd not possible with this mode"'
MENU_DE[$MENU_CONFIG_TYPE_DD_NA]='"" "Sichern mit dd nicht möglich bei diesem Modus"'
MENU_FI[$MENU_CONFIG_TYPE_DD_NA]='"" "DD-varmuuskopio ei ole mahdollista tässä tilassa"'
MENU_FR[$MENU_CONFIG_TYPE_DD_NA]='"" "Un enregistrement avec dd ne peut se faire dans ce mode"'
MENU_ZH[$MENU_CONFIG_TYPE_DD_NA]='"" "此模式不可使用dd备份"'

MENU_CONFIG_COMPRESS_OFF=$((MCNT++))
MENU_EN[$MENU_CONFIG_COMPRESS_OFF]='"off" "No backup compression"'
MENU_DE[$MENU_CONFIG_COMPRESS_OFF]='"aus" "Keine Backup Komprimierung"'
MENU_FI[$MENU_CONFIG_COMPRESS_OFF]='"off" "Ei varmuuskopion pakkausta"'
MENU_FR[$MENU_CONFIG_COMPRESS_OFF]='"off" "Pas de compression de sauvegarde"'
MENU_ZH[$MENU_CONFIG_COMPRESS_OFF]='"off" "不压缩"'

MENU_CONFIG_COMPRESS_ON=$((MCNT++))
MENU_EN[$MENU_CONFIG_COMPRESS_ON]='"on" "Compress $CONFIG_BACKUPTYPE backup"'
MENU_DE[$MENU_CONFIG_COMPRESS_ON]='"an" "Komprimiere den $CONFIG_BACKUPTYPE Backup"'
MENU_FI[$MENU_CONFIG_COMPRESS_ON]='"on" "Pakkaa $CONFIG_BACKUPTYPE -varmuuskopio"'
MENU_FR[$MENU_CONFIG_COMPRESS_ON]='"on" "Compresser la sauvegarde $CONFIG_BACKUPTYPE"'
MENU_ZH[$MENU_CONFIG_COMPRESS_ON]='"on" "压缩 $CONFIG_BACKUPTYPE 备份"'

MENU_DAYS_SHORT=$((MCNT++))
MENU_EN[$MENU_DAYS_SHORT]='"Daily" "Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat"'
MENU_DE[$MENU_DAYS_SHORT]='"Täglich" "So" "Mo" "Di" "Mi" "Do" "Fr" "Sa"'
MENU_FI[$MENU_DAYS_SHORT]='"Päivittäin" "Su" "Ma" "Ti" "Ke" "To" "Pe" "La"'
MENU_FR[$MENU_DAYS_SHORT]='"Journalier" "Di" "Lu" "Ma" "Me" "Je" "Ve" "Sa"'
MENU_ZH[$MENU_DAYS_SHORT]='"Daily" "Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat"'

MENU_DAYS_LONG=$((MCNT++))
MENU_EN[$MENU_DAYS_LONG]='"Daily" "Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday"'
MENU_DE[$MENU_DAYS_LONG]='"Täglich" "Sonntag" "Montag" "Dienstag" "Mittwoch" "Donnerstag" "Freitag" "Samstag"'
MENU_FI[$MENU_DAYS_LONG]='"Päivittäin" "Sunnuntai" "Maanantai" "Tiistai" "Keskiviikko" "Torstai" "Perjantai" "Lauantai"'
MENU_FR[$MENU_DAYS_LONG]='"Journalier" "Dimanche" "Lundi" "Mardi" "Mercredi" "Jeudi" "Vendredi" "Samedi"'
MENU_ZH[$MENU_DAYS_LONG]='"Daily" "Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday"'

MENU_UPDATE_SCRIPT=$((MCNT++))
MENU_EN[$MENU_UPDATE_SCRIPT]='"P1" "Update $FILE_TO_INSTALL"'
MENU_DE[$MENU_UPDATE_SCRIPT]='"P1" "Aktualisiere $FILE_TO_INSTALL"'
MENU_FI[$MENU_UPDATE_SCRIPT]='"P1" "Päivitä $FILE_TO_INSTALL"'
MENU_FR[$MENU_UPDATE_SCRIPT]='"P1" "Mettre à jour $FILE_TO_INSTALL"'
MENU_ZH[$MENU_UPDATE_SCRIPT]='"P1" "更新 $FILE_TO_INSTALL"'

MENU_UPDATE_INSTALLER=$((MCNT++))
MENU_EN[$MENU_UPDATE_INSTALLER]='"P2" "Update $MYSELF"'
MENU_DE[$MENU_UPDATE_INSTALLER]='"P2" "Aktualisiere $MYSELF"'
MENU_FI[$MENU_UPDATE_INSTALLER]='"P2" "Päivitä $MYSELF"'
MENU_FR[$MENU_UPDATE_INSTALLER]='"P2" "Mettre à jour $MYSELF"'
MENU_ZH[$MENU_UPDATE_INSTALLER]='"P2" "更新 $MYSELF"'

declare -A MSG_HEADER=(['I']="---" ['W']="!!!" ['E']="???")

INSTALLATION_SUCCESSFULL=0
INSTALLATION_STARTED=0
CONFIG_INSTALLED=0
SCRIPT_INSTALLED=0
EXTENSIONS_INSTALLED=0
CRON_INSTALLED=0
SYSTEMD_INSTALLED=0
PROGRESSBAR_DO=0

INSTALL_EXTENSIONS=0
BETA_INSTALL=0
CRONTAB_ENABLED="undefined"
SYSTEMD_ENABLED="undefined"

function findUser() {

	local u

	if [[ -n "$SUDO_USER" ]]; then
		u="$SUDO_USER"
	else
		u="$USER"
	fi

	echo "$u"

}

function existsLocalPropertiesFile() {
	[[ -e "$LOCAL_PROPERTY_FILE" ]]
}

function checkRequiredDirectories() {

	local dirs=( "$BIN_DIR" "$ETC_DIR" "$CRON_DIR")

	for d in "${dirs[@]}"; do
		logItem "Checking for $d"
		if [[ ! -d $d ]]; then
			unrecoverableError $MSG_MISSING_DIRECTORY "$d"
			return
		fi
	done
}

# Create message and substitute parameters

function getMessageText() { # messagenumber parm1 parm2 ...

	local msg p i s

	msgVar="MSG_${CONFIG_LANGUAGE}"

	if [[ -n ${SUPPORTED_LANGUAGES[$CONFIG_LANGUAGE]} ]]; then
		msgVar="$msgVar[$1]"
		msg=${!msgVar}
		if [[ -z $msg ]]; then # no translation found
			msg="${MSG_EN[$1]}" # fallback into english
		fi
	else
		msg="${MSG_EN[$1]}" # fallback into english
	fi

	shift

	for ((i = 1; $i <= $#; i++)); do # substitute all message parameters
		p=${!i}
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

function getMenuText() { # menutextnumber varname

	local menu varname

	local menuVar="MENU_${CONFIG_LANGUAGE}"
	declare -n varname=$2

	if [[ -n ${SUPPORTED_LANGUAGES[$CONFIG_LANGUAGE]} ]]; then
		menuVar="$menuVar[$1]"
		menu="${!menuVar}"
		if [[ -z $menu ]]; then # no translation found
			menu="${MENU_EN[$1]}" # fallback into english
		fi
	else
		menu="${MENU_EN[$1]}" # fallback into english
	fi

   eval "varname=( ${menu[@]} )"

}

function writeToConsole() {
	local msg="$(getMessageText "$@")"
	echo "MSG: $msg" >>"$LOG_FILE"
	if (( $MODE_UNATTENDED )); then
		echo "$msg"
	fi
}

function log() { # logtype message

	local lineno=${BASH_LINENO[1]}
	local dte=$(date +%Y%m%d-%H%M%S)
	local indent=$(printf '%*s' "$LOG_INDENT")
	printf "%s: DBG: %04d - %s %s\n" "$dte" "$lineno" "$indent" "$@" >> "$LOG_FILE"

}

function logItem() { # message
	log "$@"
}

function downloadURL() { # fileName
	logEntry "$1"
	local u="$MYHOMEURL/raspiBackup$URLTARGET/$1"
	echo "$u"
	logExit "$u"
}

function check4InternetAvailable() {
	if (( ! RASPIBACKUP_INSTALL_DEBUG )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_CHECK_INTERNET_CONNECTION
		isInternetAvailable
		if (( $? != 0 )); then
			writeToConsole $MSG_LEVEL_MINIMAL $MSG_NO_INTERNET_CONNECTION_FOUND
			exit
		fi
	fi
}

function isInternetAvailable() {

	logEntry

	wget -q --spider -t 1 -T 3 $MYHOMEDOMAIN
    local rc=$?
	logExit $rc
    return $rc
}

function logEntry() {
	log "-> ${FUNCNAME[1]} $@"
	(( LOG_INDENT+=3 ))
}

function logExit() {
	(( LOG_INDENT-=3 ))
	log "<- ${FUNCNAME[1]} $@"
}

function finished() {
	:
}

function center() { # <cols> <text>
	local columns="$1"
	shift 1
	while IFS= read -r line; do
		printf "%*s\n" $(((${#line} + columns) / 2)) "$line"
	done <<<"$@"
}

function isTimerEnabled() {
	logEntry
	local rc
	if (( $USE_SYSTEMD )); then
		isSystemdEnabled
	else
		isCrontabEnabled
	fi
	rc=$?
	logExit $rc
	return $rc
}

function isCrontabEnabled() {
	logEntry $CRONTAB_ENABLED
	if [[ "$CRONTAB_ENABLED" == "undefined" ]]; then
		if isCrontabConfigInstalled; then
			local l="$(tail -n 1 < $CRON_ABS_FILE)"
			logItem "$l"
			[[ ${l:0:1} != "#" ]]
			CRONTAB_ENABLED=$?
		else
			CRONTAB_ENABLED=0
		fi
	fi
	logExit $CRONTAB_ENABLED
	return $CRONTAB_ENABLED
}

function isSystemdEnabled() {
	logEntry $SYSTEMD_ENABLED
	if [[ "$SYSTEMD_ENABLED" == "undefined" ]]; then
		if isSystemdConfigInstalled; then
			local state="$(systemctl show --no-pager $SYSTEMD_TIMER_FILE_NAME | grep -i "ActiveState" | cut -f 2 -d '=')"
			logItem "Current systemd state: $state"
			[[ $state == "active" ]]
			SYSTEMD_ENABLED=$?
		else
			SYSTEMD_ENABLED=0
		fi
	fi
	logExit $SYSTEMD_ENABLED
	return $SYSTEMD_ENABLED
}

function isCrontabConfigInstalled() {
	logEntry
	local rc
	[[ -f $CRON_ABS_FILE ]]
	rc=$?
	logExit $rc
	return $rc
}

function isSystemdConfigInstalled() {
	logEntry
	local rc
	[[ -f $SYSTEMD_SERVICE_ABS_FILE && -f $SYSTEMD_TIMER_ABS_FILE ]]
	rc=$?
	logExit $rc
	return $rc
}

function isConfigInstalled() {
	[[ -f $CONFIG_ABS_FILE ]]
	return
}

function isExtensionInstalled() {
	ls $FILE_TO_INSTALL_ABS_PATH/${RASPIBACKUP_NAME}_*.sh 2>/dev/null &>>"$LOG_FILE"
	return
}

function isRaspiBackupInstalled() {
	[[ -f $FILE_TO_INSTALL_ABS_FILE ]]
	return
}

function isStartStopDefined() {
	[[ ! -z $CONFIG_STOPSERVICES  ]] && [[ "$CONFIG_STOPSERVICES" != "$IGNORE_START_STOP_CHAR" ]]
	return
}

function createSymLink() { # create link from /usr/local/bin/<filename> to /usr/local/bin/<filename>.sh
	local fileName="$1"
	local linkName="${fileName%.*}"
	rm -f $linkName &>/dev/null
	if ! ln -s $fileName $linkName; then
		unrecoverableError $MSG_MOVE_FAILED "$linkName"
		return 1
	fi
}

function deleteSymLink() { # delete link from /usr/local/bin/<filename> to /usr/local/bin/<filename>.sh
	local fileName="$1"
	local linkName="${fileName%.*}"
	rm -f $linkName &>/dev/null
}

function code_download_execute() {

	logEntry

	local newName

	if [[ -f "$FILE_TO_INSTALL_ABS_FILE" ]]; then
		oldVersion=$(grep -o -E "^VERSION=\".+\"" "$FILE_TO_INSTALL_ABS_FILE" | sed -e "s/VERSION=//" -e "s/\"//g")
		newName="$FILE_TO_INSTALL_ABS_FILE.$oldVersion.sh"
		writeToConsole $MSG_SAVING_FILE "$FILE_TO_INSTALL" "$newName"
		mv "$FILE_TO_INSTALL_ABS_FILE" "$newName" &>>"$LOG_FILE"
	fi

	if (($BETA_INSTALL)); then
		FILE_TO_INSTALL_URL="$BETA_CODE_URL"
		writeToConsole $MSG_DOWNLOADING_BETA "$FILE_TO_INSTALL"
	else
		FILE_TO_INSTALL_URL="$STABLE_CODE_URL"
		writeToConsole $MSG_DOWNLOADING "$FILE_TO_INSTALL"
	fi

	local httpCode="$(downloadFile "$(downloadURL "$FILE_TO_INSTALL")" "/tmp/$FILE_TO_INSTALL")"
	if (( $? )); then
		unrecoverableError $MSG_DOWNLOAD_FAILED "$(downloadURL "$FILE_TO_INSTALL")" "$httpCode"
		logExit
		return
	fi

	if ! mv "/tmp/$FILE_TO_INSTALL" "$FILE_TO_INSTALL_ABS_FILE" &>>"$LOG_FILE"; then
		unrecoverableError $MSG_MOVE_FAILED "$FILE_TO_INSTALL_ABS_FILE"
		logExit
		return
	fi

	SCRIPT_INSTALLED=1

	writeToConsole $MSG_CODE_INSTALLED "$FILE_TO_INSTALL_ABS_FILE"

	if ! chmod 755 $FILE_TO_INSTALL_ABS_FILE &>>$LOG_FILE; then
		unrecoverableError $MSG_CHMOD_FAILED "$FILE_TO_INSTALL_ABS_FILE"
		logExit
		return
	fi

	if ! createSymLink "$FILE_TO_INSTALL_ABS_FILE"; then
		logExit
		return
	fi

	if [[ -e "$MYDIR/$MYSELF" && "$MYDIR/$MYSELF" != "$FILE_TO_INSTALL_ABS_PATH/$MYSELF" ]]; then
		if (( ! $RASPIBACKUP_INSTALL_DEBUG )); then
			if ! mv -f "$MYDIR/$MYSELF" "$FILE_TO_INSTALL_ABS_PATH" &>>"$LOG_FILE"; then
				unrecoverableError $MSG_MOVE_FAILED "$FILE_TO_INSTALL_ABS_PATH/$MYSELF"
				logExit
				return
			fi
		else
			cp "$MYDIR/$MYSELF" "$FILE_TO_INSTALL_ABS_PATH" &>>"$LOG_FILE"
		fi
	fi

	writeToConsole $MSG_CODE_INSTALLED "$FILE_TO_INSTALL_ABS_PATH/$MYSELF"

	if ! chmod 755 $FILE_TO_INSTALL_ABS_PATH/$MYSELF &>>"$LOG_FILE"; then
		unrecoverableError $MSG_CHMOD_FAILED "$FILE_TO_INSTALL_ABS_PATH/$MYSELF"
		logExit
		return
	fi

	local chownArgs=$(stat -c "%U:%G" $FILE_TO_INSTALL_ABS_PATH | sed 's/\n//')
	if ! chown $chownArgs "$FILE_TO_INSTALL_ABS_PATH/$MYSELF" &>>"$LOG_FILE"; then
		unrecoverableError $MSG_CHOWN_FAILED "$FILE_TO_INSTALL_ABS_PATH/$MYSELF"
		logExit
		return
	fi

	if ! createSymLink "$FILE_TO_INSTALL_ABS_PATH/$MYSELF"; then
		logExit
		return
	fi

	logExit

}

function update_script_execute() {

	logEntry

	local newName

	if [[ -f "$FILE_TO_INSTALL_ABS_FILE" ]]; then
		oldVersion=$(grep -o -E "^VERSION=\".+\"" "$FILE_TO_INSTALL_ABS_FILE" | sed -e "s/VERSION=//" -e "s/\"//g")
		newName="$FILE_TO_INSTALL_ABS_PATH/${RASPIBACKUP_NAME}.${oldVersion}.sh"
		writeToConsole $MSG_SAVING_FILE "$FILE_TO_INSTALL" "$newName"
		mv "$FILE_TO_INSTALL_ABS_FILE" "$newName" &>>"$LOG_FILE"
	fi

	local httpCode="$(downloadFile "$(downloadURL "$FILE_TO_INSTALL")"  "/tmp/$FILE_TO_INSTALL" )"
	if (( $? )); then
		unrecoverableError $MSG_DOWNLOAD_FAILED "$(downloadURL "$FILE_TO_INSTALL")" "$httpCode"
		logExit
		return
	fi

	if ! mv "/tmp/$FILE_TO_INSTALL" "$FILE_TO_INSTALL_ABS_FILE" &>>"$LOG_FILE"; then
		unrecoverableError $MSG_MOVE_FAILED "$FILE_TO_INSTALL_ABS_FILE"
		return
	fi

	writeToConsole $MSG_CODE_INSTALLED "$FILE_TO_INSTALL_ABS_FILE"

	if ! chmod 755 $FILE_TO_INSTALL_ABS_FILE &>>$LOG_FILE; then
		unrecoverableError $MSG_CHMOD_FAILED "$FILE_TO_INSTALL_ABS_FILE"
		return
	fi

	logExit

}

function downloadFile() { # url, targetFileName
		logEntry "URL: $1, file: $2"
		local url="$1"
		local file="$2"
		local f=$(mktemp)
		local httpCode=$(curl -sSL -o "$f" -m $DOWNLOAD_TIMEOUT -w %{http_code} -L "$url" 2>>$LOG_FILE)
		local rc=$?
		logItem "httpCode: $httpCode RC: $rc"
		if [[ $rc != 0 || ${httpCode:0:1} != "2" ]]; then
			rm $f &>>$LOG_FILE
			logExit $httpCode
			return $httpCode
		fi

		if head -n 1 "$f" | grep -q "^<!DOCTYPE html>"; then						# Download plugin doesn't return 404 if file not found but a HTML doc
			rm $f &>>$LOG_FILE
			logExit 404
			return 404
		fi
		mv $f $file &>>$LOG_FILE
		logExit 0
		return 0
}

function update_installer_execute() {

	logEntry

	local newName

	local httpCode="$(downloadFile "$(downloadURL "$MYSELF")" "/tmp/$MYSELF")"
	if (( $? )); then
		unrecoverableError $MSG_DOWNLOAD_FAILED "$(downloadURL "$MYSELF")" "$httpCode"
		return
	fi

	if ! mv "/tmp/$MYSELF" "$INSTALLER_ABS_FILE" &>>"$LOG_FILE"; then
		unrecoverableError $MSG_MOVE_FAILED "$INSTALLER_ABS_FILE"
		return
	fi

	if (( MODE_UPDATE )); then
		writeToConsole $MSG_CODE_UPDATED "$INSTALLER_ABS_FILE"
	else
		writeToConsole $MSG_CODE_INSTALLED "$INSTALLER_ABS_FILE"
	fi

	if ! chmod 755 $INSTALLER_ABS_FILE &>>$LOG_FILE; then
		unrecoverableError $MSG_CHMOD_FAILED "$INSTALLER_ABS_FILE"
		return
	fi

	logExit

}

function config_download_execute() {

	logEntry

	local newName http_code

	if [[ -f "$CONFIG_ABS_FILE" && -f "$FILE_TO_INSTALL_ABS_FILE" ]]; then
		oldVersion=$(grep -o -E "^VERSION=\".+\"" "$FILE_TO_INSTALL_ABS_FILE" | sed -e "s/VERSION=//" -e "s/\"//g")
		local m=${CONFIG_ABS_FILE##*/}
		n=${m%.*}
		newName="$n.$oldVersion.conf"
		writeToConsole $MSG_SAVING_FILE "$CONFIG_FILE" "$CONFIG_FILE_ABS_PATH/$newName"
		[[ "$FILE_TO_INSTALL_ABS_FILE" != "$newName" ]] && mv "$CONFIG_ABS_FILE" "$CONFIG_FILE_ABS_PATH/$newName" &>>"$LOG_FILE"
	fi

	writeToConsole $MSG_DOWNLOADING "$CONFIG_FILE"
	CONFIG_INSTALLED=1

	case $CONFIG_LANGUAGE in
	DE)
		local confFile=${CONFIG_DOWNLOAD_FILE["DE"]}
		;;
	*)
		local confFile=${CONFIG_DOWNLOAD_FILE["EN"]}
		;;
	esac

	httpCode="$(downloadFile "$(downloadURL "$confFile")" "$CONFIG_ABS_FILE")"
	if (( $? )); then
		unrecoverableError $MSG_DOWNLOAD_FAILED "$(downloadURL "$confFile")" "$httpCode"
		return
	fi

	if ! chmod 600 $CONFIG_ABS_FILE &>>$LOG_FILE; then
		unrecoverableError $MSG_CHMOD_FAILED "$CONFIG_ABS_FILE"
		return
	fi

	writeToConsole $MSG_CODE_INSTALLED "$CONFIG_ABS_FILE"

	logExit

}

function extensions_install_do() {

	logEntry

	if ! isRaspiBackupInstalled; then
		local m="$(getMessageText $MSG_SCRIPT_NOT_INSTALLED)"
		local t=$(center $WINDOW_COLS "$m")
		local tt="$(getMessageText $TITLE_INFORMATION)"
		whiptail --msgbox "$t" --title "$tt" $ROWS_MSGBOX $WINDOW_COLS 2
		logExit
		return
	fi

	if isExtensionInstalled; then
		local m="$(getMessageText $MSG_EXTENSIONS_ALREADY_INSTALLED)"
		local t=$(center $WINDOW_COLS "$m")
		local tt="$(getMessageText $TITLE_INFORMATION)"
		whiptail --msgbox "$t" --title "$tt" $ROWS_MSGBOX $WINDOW_COLS 2
		logExit
		return
	fi

	INSTALL_DESCRIPTION=("Installing extensions ...")
	progressbar_do "INSTALL_DESCRIPTION" "Installing extensions" extensions_install_execute

	logExit

}

function extensions_install_execute() {

	logEntry

	local extensions="mem temp disk"

	writeToConsole $MSG_DOWNLOADING "${SAMPLEEXTENSION_TAR_FILE%.*}"

	local httpCode="$(downloadFile "$(downloadURL "$SAMPLEEXTENSION_TAR_FILE")" "$SAMPLEEXTENSION_TAR_FILE")"
	if (( $? )); then
		unrecoverableError $MSG_DOWNLOAD_FAILED "$(downloadURL "$SAMPLEEXTENSION_TAR_FILE")" "$httpCode"
		return
	fi

	if ! tar -xzf "$SAMPLEEXTENSION_TAR_FILE" -C "$FILE_TO_INSTALL_ABS_PATH" &>>"$LOG_FILE"; then
		unrecoverableError $MSG_SAMPLEEXTENSION_INSTALL_FAILED "tar -x"
		return
	fi

	if ! chmod 755 $FILE_TO_INSTALL_ABS_PATH/${RASPIBACKUP_NAME}_*.sh &>>"$LOG_FILE"; then
		unrecoverableError $MSG_SAMPLEEXTENSION_INSTALL_FAILED "chmod extensions"
		return
	fi

	if ! chown root.root $FILE_TO_INSTALL_ABS_PATH/${RASPIBACKUP_NAME}_*.sh &>>"$LOG_FILE"; then
		unrecoverableError $MSG_SAMPLEEXTENSION_INSTALL_FAILED "chmod extensions"
		return
	fi

	if ! rm -f "$SAMPLEEXTENSION_TAR_FILE" 2>>"$LOG_FILE"; then
		unrecoverableError $MSG_UNINSTALL_FAILED "$SAMPLEEXTENSION_TAR_FILE"
		return
	fi

	sed -i -E "s/^(#?\s?)?DEFAULT_EXTENSIONS=.*\$/DEFAULT_EXTENSIONS=\"$extensions\"/" $CONFIG_ABS_FILE

	EXTENSIONS_INSTALLED=1

	writeToConsole $MSG_SAMPLEEXTENSION_INSTALL_SUCCESS

	logExit

}

function extensions_uninstall_do() {

	logEntry

	if ! isExtensionInstalled; then
		local a="$(getMessageText $MSG_NO_EXTENSIONS_FOUND)"
		local t=$(center $WINDOW_COLS "$a")
		local tt="$(getMessageText $TITLE_INFORMATION)"
		whiptail --msgbox "$t" --title "$tt" $ROWS_MSGBOX $WINDOW_COLS 2
		logExit
		return
	fi

	UNINSTALL_DESCRIPTION=("Uninstalling extensions ...")
	progressbar_do "UNINSTALL_DESCRIPTION" "Uninstalling extensions" extensions_uninstall_execute

	logExit

}

function extensions_uninstall_execute() {

	logEntry

	local extensions="mem temp disk"

	if ls $FILE_TO_INSTALL_ABS_PATH/${RASPIBACKUP_NAME}_*.sh >&/dev/null; then
		if ! rm -f $FILE_TO_INSTALL_ABS_PATH/${RASPIBACKUP_NAME}_*.sh &>>"$LOG_FILE"; then
			unrecoverableError $MSG_SAMPLEEXTENSION_UNINSTALL_FAILED "rm extensions"
			return
		fi
		writeToConsole $MSG_SAMPLEEXTENSION_UNINSTALL_SUCCESS
	fi

	if [[ -f CONFIG_ABS_FILE ]]; then
		sed -i -E "s/DEFAULT_EXTENSIONS=.*\$/DEFAULT_EXTENSIONS=\"\"/" $CONFIG_ABS_FILE
	fi

	EXTENSIONS_INSTALLED=0

	logExit

}

function getActiveServices() {
	logEntry

	logItem "$EXCLUDE_SERVICES_REGEX"
	local as=""
	IFS=" "
	while read s r; do
		if [[ $s == *".service" ]]; then
			as+=" $(sed 's/.service//' <<< "$s")"
		fi
	done < <(systemctl list-units --type=service --state=active | grep "active running" | grep -v "$EXCLUDE_SERVICES_REGEX" | awk '{print $1}' )
	echo "$as"
	logExit "$as"
}

function getPartitionNumbers() { # device, e.g. /dev/mmcblk0

#	/dev/sda1 256M c W95
#	/dev/sda2 14.3G 83 Linux
#	/dev/sda5 265G 83 Linux

	logEntry $1
	local ap=""
	ap="$(LANG=C fdisk -l $1 | grep ^/dev | awk '{ print $1,$5,$6,$7,$8,$9,$10}' | grep -v -E " 8?5 " | sed -E "s@${1}p?@@" )"
#	"1 256M c W95"
#	"2 14.3G 83 Linux"
#	"5 265G 83 Linux"
	logItem "Partitions: $ap"
# now remove partition type info
	local apr="$(cut -d ' ' -f 1-2,4- <<< "$ap")"
#	"1 256M W95"
#	"2 14.3G Linux"
#	"5 265G Linux"
	echo "$apr"
	logExit "$apr"

}

function isPathMounted() { # dir

	logEntry "$1"

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

	logExit "$rc"

	return $rc
}

function getStartStopCommands() { # listOfServicesToStop pcommandvarname scommandvarname
	logEntry "$1"
	IFS=" "
	local startServices=( $1 )
	logItem "Number of entries: ${#startServices[@]}"

	local sc="" pc="" and=""

	for s in "${startServices[@]}"; do
		logItem "Processing $s"
		pc="$pc $and systemctl stop $s"
		sc="systemctl start $s $and $sc"
		[[ -z $and ]] && and="&&"
	done

	#pc="systemctl stop $1"
	#sc="systemctl start $1"

	pc=$(sed -e 's/ \+/ /g' <<< $pc | xargs)
	sc=$(sed -e 's/ \+/ /g' <<< $sc | xargs)

	printf -v "${2}" "%s" "$pc"
	printf -v "${3}" "%s" "$sc"

	logItem "$2: $pc"
	logItem "$3: $sc"

	logExit
}

function parseConfig() {
	logEntry

	IFS="" matches=$(grep -E "DEFAULT_(MSG_LEVEL|KEEPBACKUPS|BACKUPPATH|BACKUPTYPE|ZIP_BACKUP|PARTITIONBASED_BACKUP|PARTITIONS_TO_BACKUP|LANGUAGE|STARTSERVICES|STOPSERVICES|EMAIL|MAIL_PROGRAM|SMART_RECYCLE|SMART_RECYCLE_DRYRUN|SMART_RECYCLE_OPTIONS|RESIZE_FS)=" "$CONFIG_ABS_FILE")
	while IFS="=" read key value; do
		key=${key//\"/}
		key=${key/DEFAULT/CONFIG}
		value=${value//\"/}
		if [[ $key =~ .*SERVICES.* ]]; then
			if [[ "$value" == "$IGNORE_START_STOP_CHAR" ]]; then
				value=""
			else
				value=$(sed -e 's/start//g' -e 's/stop//g' -e 's/systemctl//g' -e 's/\&\&//g' -e 's/ \+/ /g' <<< "$value"  | xargs )
			fi
		fi
		logItem "$key=$value"
		eval "$key=\"$value\""
		if [[ $key == "CONFIG_LANGUAGE" ]]; then
			[[ -z "$value"  ]] && CONFIG_LANGUAGE="${LANG_SYSTEM^^}"
		fi

	done <<< "$matches"
	logExit
}

function config_update_execute() {

	logEntry

	writeToConsole $MSG_UPDATING_CONFIG "$CONFIG_ABS_FILE"

	logItem "Language: $CONFIG_LANGUAGE"
	logItem "Mode: $CONFIG_PARTITIONBASED_BACKUP"
	logItem "Partitions: $CONFIG_PARTITIONS_TO_BACKUP"
	logItem "Type: $CONFIG_BACKUPTYPE"
	logItem "Zip: $CONFIG_ZIP_BACKUP"
	logItem "Keep: $CONFIG_KEEPBACKUPS"
	logItem "Recycle: $CONFIG_SMART_RECYCLE"
	logItem "Recycleoptions: $CONFIG_SMART_RECYCLE_OPTIONS"
	logItem "Dryrun: $CONFIG_SMART_RECYCLE_DRYRUN"
	logItem "Msglevel: $CONFIG_MSG_LEVEL"
	logItem "Backuppath: $CONFIG_BACKUPPATH"
	logItem "Stop: $CONFIG_STOPSERVICES"
	logItem "Start: $CONFIG_STARTSERVICES"
	logItem "eMail: $CONFIG_EMAIL"
	logItem "mailProgram: $CONFIG_MAIL_PROGRAM"
	logItem "Resize: $CONFIG_RESIZE_ROOTFS"

	sed -i -E "s/^(#?\s?)?DEFAULT_LANGUAGE=.*\$/DEFAULT_LANGUAGE=\"$CONFIG_LANGUAGE\"/" "$CONFIG_ABS_FILE"
	sed -i -E "s/^(#?\s?)?DEFAULT_PARTITIONBASED_BACKUP=.*\$/DEFAULT_PARTITIONBASED_BACKUP=\"$CONFIG_PARTITIONBASED_BACKUP\"/" "$CONFIG_ABS_FILE"
	sed -i -E "s/^(#?\s?)?DEFAULT_PARTITIONS_TO_BACKUP=.*\$/DEFAULT_PARTITIONS_TO_BACKUP=\"$CONFIG_PARTITIONS_TO_BACKUP\"/" "$CONFIG_ABS_FILE"
	sed -i -E "s/^(#?\s?)?DEFAULT_BACKUPTYPE=.*\$/DEFAULT_BACKUPTYPE=\"$CONFIG_BACKUPTYPE\"/" "$CONFIG_ABS_FILE"
	sed -i -E "s/^(#?\s?)?DEFAULT_ZIP_BACKUP=.*\$/DEFAULT_ZIP_BACKUP=\"$CONFIG_ZIP_BACKUP\"/" "$CONFIG_ABS_FILE"
	sed -i -E "s/^(#?\s?)?DEFAULT_KEEPBACKUPS=.*$/DEFAULT_KEEPBACKUPS=\"$CONFIG_KEEPBACKUPS\"/" "$CONFIG_ABS_FILE"
	sed -i -E "s/^(#?\s?)?DEFAULT_SMART_RECYCLE=.*$/DEFAULT_SMART_RECYCLE=\"$CONFIG_SMART_RECYCLE\"/" "$CONFIG_ABS_FILE"
	sed -i -E "s/^(#?\s?)?DEFAULT_SMART_RECYCLE_OPTIONS=.*$/DEFAULT_SMART_RECYCLE_OPTIONS=\"$CONFIG_SMART_RECYCLE_OPTIONS\"/" "$CONFIG_ABS_FILE"
	sed -i -E "s/^(#?\s?)?DEFAULT_SMART_RECYCLE_DRYRUN=.*$/DEFAULT_SMART_RECYCLE_DRYRUN=\"$CONFIG_SMART_RECYCLE_DRYRUN\"/" "$CONFIG_ABS_FILE"
	sed -i -E "s/^(#?\s?)?DEFAULT_MSG_LEVEL=.*$/DEFAULT_MSG_LEVEL=\"$CONFIG_MSG_LEVEL\"/" "$CONFIG_ABS_FILE"
	sed -i -E "s/^(#?\s?)?DEFAULT_EMAIL=.*$/DEFAULT_EMAIL=\"$CONFIG_EMAIL\"/" "$CONFIG_ABS_FILE"
	sed -i -E "s/^(#?\s?)?DEFAULT_MAIL_PROGRAM=.*$/DEFAULT_MAIL_PROGRAM=\"$CONFIG_MAIL_PROGRAM\"/" "$CONFIG_ABS_FILE"
	local f=$(sed 's_/_\\/_g' <<< "$CONFIG_BACKUPPATH")
	sed -i -E "s/^(#?\s?)?DEFAULT_BACKUPPATH=.*$/DEFAULT_BACKUPPATH=\"$f\"/" "$CONFIG_ABS_FILE"

	local pline sline
	if [[ "$CONFIG_STOPSERVICES" != "$IGNORE_START_STOP_CHAR" && -n "$CONFIG_STOPSERVICES" ]]; then
		getStartStopCommands "$CONFIG_STOPSERVICES" "pline" "sline"
		pline=$(sed 's/\&/\\\&/g' <<< "$pline")
		sline=$(sed 's/\&/\\\&/g' <<< "$sline")
	else
		pline="$IGNORE_START_STOP_CHAR"
		sline="$IGNORE_START_STOP_CHAR"
	fi

	logItem "pline: $pline"
	logItem "sline: $sline"

	sed -i -E "s/^(#?\s?)?DEFAULT_STOPSERVICES=.*$/DEFAULT_STOPSERVICES=\"$pline\"/" "$CONFIG_ABS_FILE"
	sed -i -E "s/^(#?\s?)?DEFAULT_STARTSERVICES=.*$/DEFAULT_STARTSERVICES=\"$sline\"/" "$CONFIG_ABS_FILE"

	logExit

}

function cron_update_execute() {

	logEntry

	writeToConsole $MSG_UPDATING_CRON "$CRON_ABS_FILE"

	logItem "cron: $CONFIG_CRON_DAY $CONFIG_CRON_HOUR $CONFIG_CRON_MINUTE"

	local l="$(tail -n 1 < $CRON_ABS_FILE)"
	local disabled=""
	if ! isCrontabEnabled; then
		disabled="#"
	fi
	local cron_day="$(daynum_to_config_string "$CONFIG_CRON_DAY")"
	local v=$(awk -v disabled=$disabled -v minute=$CONFIG_CRON_MINUTE -v hour=$CONFIG_CRON_HOUR -v day=$cron_day ' {print disabled minute, hour, $3, $4, day, $6, $7, $8}' <<< "$l")
	logItem "cron update: $v"
	local t=$(mktemp)
	head -n -1 "$CRON_ABS_FILE" > $t
	echo "$v" >> $t
	mv $t $CRON_ABS_FILE
	rm $t 2>/dev/null

	logExit
}

function systemd_timer_execute() {
	logEntry

	logItem "Reload systemd daemon"
	systemctl daemon-reload &>>$LOG_FILE

	local enable=""
	if isSystemdEnabled; then
		enable="enable"
		logItem "Starting $SYSTEMD_TIMER_FILE_NAME"
		systemctl start $SYSTEMD_TIMER_FILE_NAME &>>$LOG_FILE
		writeToConsole $MSG_SYSTEMD_ENABLED
	else
		enable="disable"
		logItem "Stoping $SYSTEMD_TIMER_FILE_NAME"
		systemctl stop $SYSTEMD_TIMER_FILE_NAME &>>$LOG_FILE
		writeToConsole $MSG_SYSTEMD_DISABLED
	fi

	logItem "$enable $SYSTEMD_TIMER_FILE_NAME"
	systemctl $enable $SYSTEMD_TIMER_FILE_NAME &>>$LOG_FILE

	systemctl status $SYSTEMD_TIMER_FILE_NAME &>>$LOG_FILE

	logExit
}

function systemd_update_execute() {

	logEntry

	writeToConsole $MSG_UPDATING_SYSTEMD "$SYSTEMD_TIMER_ABS_FILE"

	logItem "systemd: $CONFIG_SYSTEMD_DAY $CONFIG_SYSTEMD_HOUR $CONFIG_SYSTEMD_MINUTE"

#	OnCalendar=Sun *-*-* 05:00:42 # on sunday
#	OnCalendar=*-*-* 05:00:42     # daily
	local l="$(grep "^OnCalendar" $SYSTEMD_TIMER_ABS_FILE)"

	local systemd_day="$(daynum_to_config_string "$CONFIG_SYSTEMD_DAY")"

	logItem "Day: $systemd_day"
	local v=$(awk -v minute=$CONFIG_SYSTEMD_MINUTE -v hour=$CONFIG_SYSTEMD_HOUR -v day=$systemd_day ' { print "OnCalendar="day "*-*-*", hour":"minute":42" }' <<< "$l")
	logItem "systemd update: $v"
	sed -i "/^OnCalendar/c$v" "$SYSTEMD_TIMER_ABS_FILE"

	logItem "$(cat $SYSTEMD_TIMER_ABS_FILE)"

	logExit
}

function cron_install_execute() {

	logEntry

	writeToConsole $MSG_INSTALLING_CRON_TEMPLATE "$CRON_ABS_FILE"
	echo "$CRON_CONTENTS" >"$CRON_ABS_FILE"
	if ! chmod 644 $CRON_ABS_FILE &>>$LOG_FILE; then
		unrecoverableError $MSG_CHMOD_FAILED "$CRON_ABS_FILE"
		logExit
		return
	fi

	CRON_INSTALLED=1

	if (( $MODE_FORCE_TIMER )); then
		systemd_uninstall_execute
	fi

	logExit

}

function systemd_install_execute() {

	logEntry

	writeToConsole $MSG_INSTALLING_SYSTEMD_TEMPLATE "$SYSTEMD_SERVICE_ABS_FILE"
	echo "$SYSTEMD_SERVICE" >"$SYSTEMD_SERVICE_ABS_FILE"
	if ! chmod 755 $SYSTEMD_SERVICE_ABS_FILE &>>$LOG_FILE; then
		unrecoverableError $MSG_CHMOD_FAILED "$SYSTEMD_SERVICE_ABS_FILE"
		logExit
		return
	fi
	writeToConsole $MSG_INSTALLING_SYSTEMD_TEMPLATE "$SYSTEMD_TIMER_ABS_FILE"
	echo "$SYSTEMD_TIMER" >"$SYSTEMD_TIMER_ABS_FILE"
	if ! chmod 755 $SYSTEMD_TIMER_ABS_FILE &>>$LOG_FILE; then
		unrecoverableError $MSG_CHMOD_FAILED "$SYSTEMD_TIMER_ABS_FILE"
		logExit
		return
	fi
	SYSTEMD_INSTALLED=1

	systemctl disable $SYSTEMD_TIMER_FILE_NAME &>>$LOG_FILE

	systemctl status $SYSTEMD_TIMER_FILE_NAME &>>$LOG_FILE

	if (( $MODE_FORCE_TIMER )); then
		cron_uninstall_execute
	fi

	logExit

}

function timer_uninstall_execute() {

	logEntry

	cron_uninstall_execute
	systemd_uninstall_execute

	logExit

}

function cron_uninstall_execute() {

	logEntry

	if [[ -e "$CRON_ABS_FILE" ]]; then
		writeToConsole $MSG_UNINSTALLING_CRON_TEMPLATE "$CRON_ABS_FILE"
		if ! rm -f "$CRON_ABS_FILE" 2>>"$LOG_FILE"; then
			unrecoverableError $MSG_UNINSTALL_FAILED "$CRON_ABS_FILE"
			return
		fi
	fi
	CRON_INSTALLED=0
	logExit

}

function systemd_uninstall_execute() {

	logEntry

	local foundConfig
	if [[ -e "$SYSTEMD_SERVICE_ABS_FILE" ]]; then
		foundConfig=1
		writeToConsole $MSG_UNINSTALLING_SYSTEMD_TEMPLATE "$SYSTEMD_SERVICE_ABS_FILE"
		if ! rm -f "$SYSTEMD_SERVICE_ABS_FILE" 2>>"$LOG_FILE"; then
			unrecoverableError $MSG_UNINSTALL_FAILED "$SYSTEMD_SERVICE_ABS_FILE"
			return
		fi
	fi
	if [[ -e "$SYSTEMD_TIMER_ABS_FILE" ]]; then
		foundConfig=1
		writeToConsole $MSG_UNINSTALLING_SYSTEMD_TEMPLATE "$SYSTEMD_TIMER_ABS_FILE"
		if ! rm -f "$SYSTEMD_TIMER_ABS_FILE" 2>>"$LOG_FILE"; then
			unrecoverableError $MSG_UNINSTALL_FAILED "$SYSTEMD_TIMER_ABS_FILE"
			return
		fi
	fi

	if (( $foundConfig )); then
		if isSystemdEnabled; then
			writeToConsole $MSG_SYSTEMD_DISABLED
			logItem "Stopping $FILE_TO_INSTALL"
			systemctl stop $FILE_TO_INSTALL &>>$LOG_FILE
			logItem "Disable $FILE_TO_INSTALL"
			systemctl disable $FILE_TO_INSTALL &>>$LOG_FILE
			logItem "Relaod systemd daemon"
			systemctl daemon-reload &>>$LOG_FILE
		fi
	fi

	SYSTEMD_INSTALLED_INSTALLED=0

	logExit

}

function config_uninstall_execute() {

	logEntry

	# all config files starting with raspiBackup

	local pre=${CONFIG_ABS_FILE%%.*}
	if ls $pre* &>/dev/null; then
		writeToConsole $MSG_DELETE_FILE "$pre*"
		if ! rm -f $pre* &>>"$LOG_FILE"; then
			unrecoverableError $MSG_UNINSTALL_FAILED "$pre*"
			return
		fi
	fi
	logExit
}

function misc_uninstall_execute() {

	logEntry

	# tmp files
	if ls /tmp/$RASPIBACKUP_NAME* &>/dev/null; then
		writeToConsole $MSG_DELETE_FILE "/tmp/$RASPIBACKUP_NAME*"
		if ! rm -f /tmp/$RASPIBACKUP_NAME* &>>"$LOG_FILE"; then
			unrecoverableError $MSG_UNINSTALL_FAILED "/tmp/$RASPIBACKUP_NAME*"
			return
		fi
	fi

	# reminder status file
	if ls $VAR_LIB_DIRECTORY/* &>/dev/null; then
		writeToConsole $MSG_DELETE_FILE "$VAR_LIB_DIRECTORY/*"
		if ! rm -f $VAR_LIB_DIRECTORY/* &>>"$LOG_FILE"; then
			unrecoverableError $MSG_UNINSTALL_FAILED "$VAR_LIB_DIRECTORY/*"
			return
		fi
		if [[ -d $VAR_LIB_DIRECTORY ]]; then
			writeToConsole $MSG_DELETE_FILE "$VAR_LIB_DIRECTORY"
			if ! rmdir $VAR_LIB_DIRECTORY &>>"$LOG_FILE"; then
				unrecoverableError $MSG_UNINSTALL_FAILED "$VAR_LIB_DIRECTORY"
				return
			fi
		fi
	fi
	logExit
}

function uninstall_script_execute() {

	logEntry

	pre=${FILE_TO_INSTALL_ABS_FILE%%.*}
	post=${FILE_TO_INSTALL_ABS_FILE##*.}

	if ls $pre.$post* &>/dev/null; then
		writeToConsole $MSG_DELETE_FILE "$pre.$post*"
		if ! rm -f $pre.$post* 2>>"$LOG_FILE"; then
			unrecoverableError $MSG_UNINSTALL_FAILED "$pre.$post*"
			return
		fi
	fi
	if [[ -e "$FILE_TO_INSTALL_ABS_FILE" ]]; then
		writeToConsole $MSG_DELETE_FILE "$FILE_TO_INSTALL_ABS_FILE"
		if ! rm -f "$FILE_TO_INSTALL_ABS_FILE" 2>>$LOG_FILE; then
			unrecoverableError $MSG_UNINSTALL_FAILED "$FILE_TO_INSTALL_ABS_FILE"
			return
		fi
	fi

	deleteSymLink "$FILE_TO_INSTALL_ABS_FILE"

	INSTALLATION_SUCCESSFULL=0
	logExit
}

function uninstall_execute() {

	logEntry

	if [[ -e "$FILE_TO_INSTALL_ABS_PATH/$MYSELF" ]]; then
		writeToConsole $MSG_DELETE_FILE "$FILE_TO_INSTALL_ABS_PATH/$MYSELF"
		if ! rm -f "$FILE_TO_INSTALL_ABS_PATH/$MYSELF" 2>>$LOG_FILE; then
			unrecoverableError $MSG_UNINSTALL_FAILED "$FILE_TO_INSTALL_ABS_PATH/$MYSELF"
			return
		fi
		deleteSymLink "$FILE_TO_INSTALL_ABS_PATH/$MYSELF"

		if [[ -f "$LATEST_TEMP_PROPERTY_FILE" ]]; then
			writeToConsole $MSG_DELETE_FILE "$LATEST_TEMP_PROPERTY_FILE"
			rm -f "$LATEST_TEMP_PROPERTY_FILE" 2>>$LOG_FILE
		fi

		rm /tmp/${RASPIBACKUP_NAME}*.* 2>>$LOG_FILE
		rm /${FILE_TO_INSTALL_ABS_PATH}/${RASPIBACKUP_NAME}*.* 2>>$LOG_FILE

		writeToConsole $MSG_UNINSTALL_FINISHED "$RASPIBACKUP_NAME"
	else
		writeToConsole $MSG_NOT_INSTALLED "$RASPIBACKUP_NAME"
	fi

	INSTALLATION_SUCCESSFULL=0
	logExit

}

# NOTE: make sure to return just after calling this function in order to terminate when first error occurs
function unrecoverableError() { # messagenumber messageparms

	logEntry "$@"

	if (( $PROGRESSBAR_DO )); then
		logItem "Progressbar error occured $@"
		echo "$@"
		return
	fi

	clear
	calc_wt_size

	logStack
	local tt="$(getMessageText $TITLE_ERROR)"
	local d="$(getMessageText $DESCRIPTION_ERROR)"

	local id="$1"
	shift

	logItem "Id: $id"
	logItem "Msg: $@"

	if (( $MODE_UNATTENDED )); then
		echo
		d="$(getMessageText $id $@ )${NL}${NL}$d"
		logItem "$d"
		echo "$d"
	else
		local m="$(getMessageText $id $@ )${NL}${NL}$d"
		logItem "$m"
		local t=$(center $(($WINDOW_COLS * 2)) "$m")
		whiptail --msgbox "$t" --title "$tt" $ROWS_MSGBOX $(($WINDOW_COLS * 2)) 1
	fi
	logExit

	exit 1
}

function calc_wt_size() {

	# NOTE: it's tempting to redirect stderr to /dev/null, so supress error
	# output from tput. However in this case, tput detects neither stdout or
	# stderr is a tty and so only gives default 80, 24 values
	WT_HEIGHT=20
	WT_WIDTH=$(tput cols)

	if [ -z "$WT_WIDTH" ] || [ "$WT_WIDTH" -lt 60 ]; then
		WT_WIDTH=80
	fi
	if [ "$WT_WIDTH" -gt 178 ]; then
		WT_WIDTH=120
	fi

	#WT_HEIGHT=0
	#WT_WIDTH=0
	WT_MENU_HEIGHT=$(($WT_HEIGHT - 7))
	#WT_MENU_HEIGHT=13
}

function testIfServicesExist() { # list of services
	logEntry "$1"
	IFS=" "
	local services=( $1 )
	local fails=""
	for s in ${services[@]}; do
		if ! systemd-analyze verify $s.service &>/dev/null; then
			[[ -n "$fails" ]] && fails+=","
			fails+="$s"
		fi
	done
	echo "$fails"
	logExit "$fails"
}

function extractVersionFromFile() { # fileName type (VERSION|VERSION_CONFIG)
	local v="$(grep -E "^$2=" "$1" | cut -f 2 -d = | sed  -e 's/[[:space:]]*#.*$//g' -e 's/\"//g')"
	[[ -z "$v" ]] && v="0.0.0.0"
	echo "$v"
}

function about_do() {

	logEntry

	if [[ -f $FILE_TO_INSTALL_ABS_FILE ]]; then
		local RASPI_GIT_DATE="$(grep "^GIT_DATE=" $FILE_TO_INSTALL_ABS_FILE)"
		local RASPI_GIT_DATE_ONLY="${RASPI_GIT_DATE/: /}"
		local RASPI_GIT_DATE_ONLY="$(cut -f 2 -d ' ' <<< "$RASPI_GIT_DATE")"
		local RASPI_GIT_TIME_ONLY="$(cut -f 3 -d ' ' <<< "$RASPI_GIT_DATE")"
		local RASPI_GIT_COMMIT="$(grep "^GIT_COMMIT=" $FILE_TO_INSTALL_ABS_FILE)"
		local RASPI_GIT_COMMIT_ONLY="$(cut -f 2 -d ' ' <<< "$RASPI_GIT_COMMIT" | sed 's/\$//' | sed "s/'//" )"
		local RASPI_VERSION="$(extractVersionFromFile $FILE_TO_INSTALL_ABS_FILE VERSION)"
		local RASPI_GIT_CODEVERSION="$FILE_TO_INSTALL $RASPI_VERSION, $RASPI_GIT_DATE_ONLY/$RASPI_GIT_TIME_ONLY - $RASPI_GIT_COMMIT_ONLY"
	fi

	local a="$(getMessageText $MSG_ABOUT "$RASPI_GIT_CODEVERSION")"
	local t=$(center $(($WINDOW_COLS * 2)) "$a")
	whiptail --msgbox "$t" --title "About" $ROWS_ABOUT $(($WINDOW_COLS * 2)) 1
	logExit
}

function navigation_do() {

	local a="$(getMessageText $MSG_NAVIGATION)"
	local t=$(center $(($WINDOW_COLS * 2)) "$a")
	whiptail --msgbox "$t" --title "Navigation" $ROWS_ABOUT $(($WINDOW_COLS * 2)) 1
}

function do_finish() {

	logEntry

	(( RASPIBACKUP_INSTALL_DEBUG )) && exit 0

	if isRaspiBackupInstalled ; then
		if ! isStartStopDefined; then
			local m="$(getMessageText $MSG_QUESTION_IGNORE_MISSING_STARTSTOP)"
			local y="$(getMessageText $BUTTON_YES)"
			local n="$(getMessageText $BUTTON_NO)"
			local t=$(center $WINDOW_COLS "$m")
			local tt="$(getMessageText $TITLE_WARNING)"
			if ! whiptail --yesno "$t" --title "$tt" --yes-button "$y" --no-button "$n" --defaultno $ROWS_MSGBOX $WINDOW_COLS 1 3>&1 1>&2 2>&3; then
				return
			fi
		fi

		if (( $INSTALLATION_SUCCESSFULL )); then
			first_steps
		fi

		help

		reset
	fi
	logExit

	exit 0
}

function help() {
	local a="$(getMessageText $MSG_HELP)"
	local t=$(center $(($WINDOW_COLS * 2)) "$a")
	local tt="$(getMessageText $TITLE_HELP)"
	whiptail --msgbox "$t" --title "$tt" $ROWS_ABOUT $(($WINDOW_COLS * 2)) 1
}

function trapWithArg() { # function trap1 trap2 ... trapn
	local func="$1"
	shift
	for sig; do
		trap "$func $sig" "$sig"
	done
}

function cleanup() {

	logEntry

	trap '' SIGINT SIGTERM EXIT

	local rc=$?

	local signal="$1"

	logItem "Signal: $signal"
	logItem "rc: $rc"

	TAIL=0

	if (($INSTALLATION_STARTED)); then
		if ((!$INSTALLATION_SUCCESSFULL)); then
			writeToConsole $MSG_CLEANUP
			(($CONFIG_INSTALLED)) && rm $CONFIG_ABS_FILE &>>"$LOG_FILE" || true
			(($SCRIPT_INSTALLED)) && rm $FILE_TO_INSTALL_ABS_FILE &>>"$LOG_FILE" || true
			(($CRON_INSTALLED)) && rm $CRON_ABS_FILE &>>"$LOG_FILE" || true
			if (($SYSTEMD_INSTALLED)); then
				rm $SYSTEMD_SERVICE_ABS_FILE &>>"$LOG_FILE" || true
				rm $SYSTEMD_TIMER_ABS_FILE &>>"$LOG_FILE" || true
			fi
			(($EXTENSIONS_INSTALLED)) && rm -f $FILE_TO_INSTALL_ABS_PATH/${RASPIBACKUP_NAME}_*.sh &>>"$LOG_FILE" || true
		fi
	fi

	(($EXTENSIONS_INSTALLED)) && rm $SAMPLEEXTENSION_TAR_FILE &>>$LOG_FILE || true

	masqueradeSensitiveInfoInLog # and masquerade sensitive details in log file

	if [[ "$signal" != "EXIT" ]]; then
		writeToConsole $MSG_INSTALLATION_FAILED "$RASPIBACKUP_NAME" "$LOG_FILE"
		logExit
		rc=127
	fi

	chown "$CALLING_USER:$CALLING_USER" "$LOG_FILE" &> $LOG_FILE

	exit $rc
}

function config_menu() {

	logEntry

	if ! isConfigInstalled; then
		local t=$(center $WINDOW_COLS "No $RASPIBACKUP_NAME configuration found.")
		local tt="$(getMessageText $TITLE_INFORMATION)"
		whiptail --msgbox "$t" --title "$tt" $ROWS_MSGBOX $WINDOW_COLS 2
		logExit
		return
	fi

	CONFIG_UPDATED=0
	TIMER_UPDATED=0

	if isConfigInstalled; then
		parseConfig
	fi

	if isCrontabConfigInstalled; then
		local l="$(tail -n 1 < $CRON_ABS_FILE)"
		logItem "last line: $l"
		local v=$(awk ' {print $1, $2, $5}' <<< "$l")
		logItem "parsed $v"
		CONFIG_CRON_MINUTE="$(cut -f 1 -d ' ' <<< $v)"
		[[ ${CONFIG_CRON_MINUTE:0:1} == "#" ]] && CONFIG_CRON_MINUTE="${CONFIG_CRON_MINUTE:1}"
		CONFIG_CRON_HOUR="$(cut -f 2 -d ' ' <<< $v)"
		local day=$(cut -f 3 -d ' ' <<< $v)
		CONFIG_CRON_DAY=$(daynum_from_config_string "$day")
		logItem "parsed hour: $CONFIG_CRON_HOUR"
		logItem "parsed minute: $CONFIG_CRON_MINUTE"
		logItem "parsed day: $CONFIG_CRON_DAY"
	elif isSystemdConfigInstalled; then
		#	OnCalendar=Sun *-*-* 05:00:00
		#	OnCalendar= *-*-* 05:00:00
		local l="$(grep "^OnCalendar" $SYSTEMD_TIMER_ABS_FILE | cut -f 2 -d "=")" # Sun *-*-* 05:00:00 or *-*-* 05:00:00
		logItem "parsed $l"
		local day="$(cut -f 1 -d ' ' <<< $l)" # Sun or *-*-*
		logItem "day: $day"
		local t="$(cut -f 3 -d " " <<< $l)" # 05:00:00 or empty
		logItem "parsed time $t"
		if [[ -z "$t" ]]; then
			t="$(cut -f 2 -d " " <<< $l)" # 05:00:00
			day=""
		fi
		logItem "parsed time $t"

		CONFIG_SYSTEMD_DAY="$(daynum_from_config_string "$day")"
		CONFIG_SYSTEMD_HOUR="$(cut -f 1 -d ':' <<< $t)" # 05
		CONFIG_SYSTEMD_MINUTE="$(cut -f 2 -d ':' <<< $t)" # 00
		logItem "parsed hour: $CONFIG_SYSTEMD_HOUR"
		logItem "parsed minute: $CONFIG_SYSTEMD_MINUTE"
		logItem "parsed day: $CONFIG_SYSTEMD_DAY"
	fi

	while :; do

		local b1="$(getMessageText $BUTTON_BACK)"
		local sel1="$(getMessageText $BUTTON_SELECT)"
		local y="$(getMessageText $BUTTON_YES)"
		local n="$(getMessageText $BUTTON_NO)"

		getMenuText $MENU_LANGUAGE m1
		getMenuText $MENU_CONFIG_BACKUPPATH m2
		getMenuText $MENU_CONFIG_BACKUPS m3
		getMenuText $MENU_CONFIG_TYPE m4
		getMenuText $MENU_CONFIG_MODE m5
		getMenuText $MENU_CONFIG_SERVICES m6
		getMenuText $MENU_CONFIG_MESSAGE m7
		getMenuText $MENU_CONFIG_EMAIL m8
		getMenuText $MENU_CONFIG_REGULAR m9

		local p="${m1[0]}"
		m1[0]="C${p:1}"

		local s1="${m1[0]}"
		local s2="${m2[0]}"
		local s3="${m3[0]}"
		local s4="${m4[0]}"
		local s5="${m5[0]}"
		local s6="${m6[0]}"
		local s7="${m7[0]}"
		local s8="${m8[0]}"
		local s9="${m9[0]}"

		local mx=( 	\
			"${m1[@]}" \
			"${m2[@]}" \
			"${m3[@]}" \
			"${m4[@]}" \
			"${m5[@]}" \
			"${m6[@]}" \
			"${m7[@]}" \
			"${m8[@]}" \
			"${m9[@]}" \
			)

		if [[ $CONFIG_BACKUPTYPE == "dd" || $CONFIG_BACKUPTYPE == "tar" ]]; then
			getMenuText $MENU_CONFIG_ZIP mcp
			local scp="${mcp[0]}"
			mx+=("${mcp[@]}")
		else
			local scp=""
		fi

		getMenuText $MENU_CONFIGURE tt

		FUN=$(whiptail --title "${tt[1]}" --menu "" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button "$b1" --ok-button "$sel1" \
			"${mx[@]}" \
			3>&1 1>&2 2>&3)
		RET=$?
		if [ $RET -eq 1 ]; then
			if (($CONFIG_UPDATED)); then
				local m="$(getMessageText $MSG_QUESTION_UPDATE_CONFIG)"
				local t=$(center $WINDOW_COLS "$m")
				local ttm="$(getMessageText $TITLE_CONFIRM)"
				if whiptail --yesno "$t" --title "$ttm" --yes-button "$y" --no-button "$n" --defaultno $ROWS_MSGBOX $WINDOW_COLS 1 3>&1 1>&2 2>&3; then
					config_update_do
				fi
			fi
			if (($TIMER_UPDATED)); then
				local m
				if isCrontabConfigInstalled; then
					m="$(getMessageText $MSG_QUESTION_UPDATE_CRON)"
				else
					m="$(getMessageText $MSG_QUESTION_UPDATE_SYSTEMD)"
				fi
				local t=$(center $WINDOW_COLS "$m")
				local ttm="$(getMessageText $TITLE_CONFIRM)"
				if whiptail --yesno "$t" --title "$ttm" --yes-button "$y" --no-button "$n" --defaultno $ROWS_MSGBOX $WINDOW_COLS 1 3>&1 1>&2 2>&3; then
					timer_update_do
				fi
			fi
			logExit
			return 0
		elif [ $RET -eq 0 ]; then
			logItem "$FUN"
			case "$FUN" in
				$s1) config_language_do; CONFIG_UPDATED=$(( CONFIG_UPDATED|$? )) ;;
				$s2) config_backuppath_do; CONFIG_UPDATED=$(( CONFIG_UPDATED|$? )) ;;
				$s3) config_keep_selection_do; CONFIG_UPDATED=$(( CONFIG_UPDATED|$? )) ;;
				$s4) config_backuptype_do; CONFIG_UPDATED=$(( CONFIG_UPDATED|$? )) ;;
				$s5) config_backupmode_do; CONFIG_UPDATED=$(( CONFIG_UPDATED|$? )) ;;
				$s6) config_services_do; CONFIG_UPDATED=$(( CONFIG_UPDATED|$? )) ;;
				$s7) config_message_detail_do; CONFIG_UPDATED=$(( CONFIG_UPDATED|$? )) ;;
				$s8) config_email_do; CONFIG_UPDATED=$(( CONFIG_UPDATED|$? )) ;;
				$s9) config_timer_menu; TIMER_UPDATED=$? ;;
				$scp) config_compress_do; CONFIG_UPDATED=$(( CONFIG_UPDATED|$? )) ;;
				\ *) : ;;
				*) whiptail --msgbox "Programm error: unrecognized option $FUN" $ROWS_MENU $WINDOW_COLS 1 ;;
			esac || whiptail --msgbox "There was an error running option $FUN" $ROWS_MENU $WINDOW_COLS 1
		fi
	done
	logExit

}
function config_keep_selection_do() {

	logEntry "$CONFIG_SMART_RECYCLE"

	local smart_mode=off
	local keep_mode=off
	local old="$CONFIG_SMART_RECYCLE"
	local rc

	case "$CONFIG_SMART_RECYCLE" in
		0) keep_mode=on ;;
		1) smart_mode=on ;;
		*) whiptail --msgbox "Programm error, unrecognized smart mode $CONFIG_SMART_RECYCLE" $ROWS_MENU $WINDOW_COLS 2
			logExit
			return 1
			;;
	esac

	getMenuText $MENU_CONFIG_MODE_KEEP m1
	getMenuText $MENU_CONFIG_MODE_SMART m2
	local s1="${m1[0]}"
	local s2="${m2[0]}"

	getMenuText $MENU_CONFIG_BACKUPS tt
	local o1="$(getMessageText $BUTTON_OK)"
	local c1="$(getMessageText $BUTTON_CANCEL)"
	local d="$(getMessageText $DESCRIPTION_SMARTMODE)"

	local updated=0

	ANSWER=$(whiptail --notags --radiolist "$d" --title "${tt[1]}" --ok-button "$o1" --cancel-button "$c1" $ROWS_MENU $WINDOW_COLS 2 \
		"${m1[@]}" $keep_mode \
		"${m2[@]}" $smart_mode \
		3>&1 1>&2 2>&3)
	if [ $? -eq 0 ]; then
		logItem "Answer: $ANSWER"
		case "$ANSWER" in
		$s1)	logItem "$s1"
				config_keep_do 0
				updated=$?
				;;
		$s2)	logItem "$s2"
				config_keep_do 1
				updated=$?
				;;
		*) whiptail --msgbox "Programm error, unrecognized smart mode $ANSWER" $ROWS_MENU $WINDOW_COLS 2
			logExit 1
			return 1
			;;
		esac
	fi

	[[ "$old" == "$CONFIG_SMART_RECYCLE" ]] && (( $updated == 0 ))
	rc=$?
	logExit $rc
	return $rc
}

function config_keep_do() { # smartRecycle

	logEntry $1

	local isSmartRecycle=$1
	local current

	while :; do

		local error=0

		if (( $isSmartRecycle )); then
			current="$CONFIG_SMART_RECYCLE_OPTIONS"
		else
			current="$CONFIG_KEEPBACKUPS"
		fi

		getMenuText $MENU_CONFIG_BACKUPS tt
		local c1="$(getMessageText $BUTTON_CANCEL)"
		local o1="$(getMessageText $BUTTON_OK)"

		local d
		if (( $isSmartRecycle )); then
			d="$(getMessageText $DESCRIPTION_SMART)"
		else
			d="$(getMessageText $DESCRIPTION_KEEP)"
		fi

		ANSWER=$(whiptail --inputbox "$d" --title "${tt[1]}" $ROWS_MENU $WINDOW_COLS "$current" --ok-button "$o1" --cancel-button "$c1" 3>&1 1>&2 2>&3)
		if [ $? -eq 0 ]; then
			logItem "Answer: $ANSWER"

			IFS=$DEFAULT_IFS
			local srNumbers=( $ANSWER )
			local srNumberCount=${#srNumbers[@]}
			local n

			if (( $srNumberCount == 4 || $srNumberCount == 1 )); then
				for n in ${srNumbers[@]}; do
					if [[ ! "$n" =~ ^[0-9]+$ ]]; then
						local m
						if (( $isSmartRecycle )); then
							m="$(getMessageText $MSG_INVALID_SMART "$n")"
						else
							m="$(getMessageText $MSG_INVALID_KEEP "$n")"
						fi
						local t=$(center $WINDOW_COLS "$m")
						local ttm="$(getMessageText $TITLE_VALIDATIONERROR)"
						whiptail --msgbox "$t" --title "$ttm" $ROWS_MENU $WINDOW_COLS 2
						error=1
						break
					fi
				done
			else
				local m
				if (( $isSmartRecycle )); then
					m="$(getMessageText $MSG_INVALID_SMART_NUMBER_COUNT)"
				else
					m="$(getMessageText $MSG_INVALID_KEEP_NUMBER_COUNT)"
				fi
				local t=$(center $WINDOW_COLS "$m")
				local ttm="$(getMessageText $TITLE_VALIDATIONERROR)"
				whiptail --msgbox "$t" --title "$ttm" $ROWS_MENU $WINDOW_COLS 2
				error=1
			fi

			if (( ! $error )); then
				if (( $isSmartRecycle )); then # smart recycle
					local old="$CONFIG_SMART_RECYCLE_OPTIONS"
					CONFIG_SMART_RECYCLE_OPTIONS="$ANSWER"
					CONFIG_SMART_RECYCLE_DRYRUN="0"
					CONFIG_SMART_RECYCLE="1"
					isSmartRecycle=1
				else	# normal keep
					local old="$CONFIG_KEEPBACKUPS"
					CONFIG_KEEPBACKUPS="$ANSWER"
					CONFIG_SMART_RECYCLE_OPTIONS="$DEFAULT_CONFIG_SMART_RECYCLE_OPTIONS"
					CONFIG_SMART_RECYCLE_DRYRUN="$DEFAULT_CONFIG_SMART_RECYCLE_DRYRUN"
					CONFIG_SMART_RECYCLE="$DEFAULT_CONFIG_SMART_RECYCLE"
					isSmartRecycle=0
				fi
				break
			fi
		else
			logExit "aborted"
			return 0
		fi
	done

	logItem "isSmartRecycle: $isSmartRecycle"
	logItem "CONFIG_KEEPBACKUPS: $CONFIG_KEEPBACKUPS"
	logItem "CONFIG_SMART_RECYCLE_OPTIONS: $CONFIG_SMART_RECYCLE_OPTIONS"
	logItem "CONFIG_SMART_RECYCLE: $CONFIG_SMART_RECYCLE"
	logItem "CONFIG_SMART_RECYCLE_DRYRUN: $CONFIG_SMART_RECYCLE_DRYRUN"

	( (( ! $isSmartRecycle )) && [[ "$old" == "$CONFIG_KEEPBACKUPS" ]] ) || ( (( $isSmartRecycle )) && [[ "$old" == "$CONFIG_SMART_RECYCLE_OPTIONS" ]] )
	local rc=$?
	if (( $isSmartRecycle )); then
		logExit "$rc - $CONFIG_SMART_RECYCLE"
	else
		logExit "$rc - $CONFIG_KEEPBACKUPS"
	fi

	return $rc

}

function config_backuppath_do() {

	logEntry

	local current="$CONFIG_BACKUPPATH"
	local old="$current"

	while :; do

		getMenuText $MENU_CONFIG_BACKUPPATH tt
		local c1="$(getMessageText $BUTTON_CANCEL)"
		local o1="$(getMessageText $BUTTON_OK)"
		local d="$(getMessageText $DESCRIPTION_BACKUPPATH)"

		ANSWER=$(whiptail --inputbox "$d" --title "${tt[1]}" $ROWS_MENU $WINDOW_COLS "$current" --ok-button "$o1" --cancel-button "$c1" 3>&1 1>&2 2>&3)
		if [ $? -eq 0 ]; then
			logItem "Answer: $ANSWER"
			current="$ANSWER"
			if [[ -z "$ANSWER" || ! -d "$ANSWER" ]]; then
				local m="$(getMessageText $MSG_INVALID_BACKUPPATH "$ANSWER")"
				local t=$(center $WINDOW_COLS "$m")
				local ttm="$(getMessageText $TITLE_VALIDATIONERROR)"
				whiptail --msgbox "$t" --title "$ttm" $ROWS_MENU $WINDOW_COLS 2
			elif ! isPathMounted "$ANSWER"; then
				local m="$(getMessageText $MSG_LOCAL_BACKUPPATH "$ANSWER")"
				local t=$(center $WINDOW_COLS "$m")
				local ttm="$(getMessageText $TITLE_VALIDATIONERROR)"
				whiptail --msgbox "$t" --title "$ttm" $ROWS_MENU $WINDOW_COLS 2
			else
				CONFIG_BACKUPPATH="$ANSWER"
				break
			fi
		else
			break
		fi
	done

	[[ "$old" == "$CONFIG_BACKUPPATH" ]]
	local rc=$?
	logExit "$rc -$CONFIG_BACKUPPATH"
	return $rc

}

function config_time_do() {

	logEntry
	local rc

	if (( $USE_SYSTEMD )); then
		config_systemdtime_do
	else
		config_crontime_do
	fi
	rc=$?

	logExit $rc
	return $rc

}

function config_crontime_do() {

	local old=$(printf "%02d:%02d" "$((10#$CONFIG_CRON_HOUR))" "$((10#$CONFIG_CRON_MINUTE))" )
	current="$old"

	logEntry "$old"

	local b1="$(getMessageText $SELECT_TIME)"
	local c1="$(getMessageText $BUTTON_CANCEL)"
	local o1="$(getMessageText $BUTTON_OK)"
	getMenuText $MENU_CONFIG_TIME tt

	while :; do
		ANSWER=$(whiptail --inputbox "$b" --title "${tt[1]}" $ROWS_MENU $WINDOW_COLS --ok-button "$o1" --cancel-button "$c1" "$current" $ROWS_MENU $WINDOW_COLS 2 3>&1 1>&2 2>&3)
		if [ $? -eq 0 ]; then
			logItem "Answer: $ANSWER"
			current="$ANSWER"
			if [[ ! "$ANSWER" =~ ^[0-9]{1,2}:[0-9]{1,2}$ ]]; then
				local m="$(getMessageText $MSG_INVALID_TIME "$ANSWER")"
				local t=$(center $WINDOW_COLS "$m")
				local ttm="$(getMessageText $TITLE_VALIDATIONERROR)"
				whiptail --msgbox "$t" --title "$ttm" $ROWS_MENU $WINDOW_COLS 2
			else
				CONFIG_CRON_HOUR=$(cut -f1 -d: <<< "$ANSWER")
				CONFIG_CRON_MINUTE=$(cut -f2 -d: <<< "$ANSWER")
				if (( 10#$CONFIG_CRON_HOUR > 23 || 10#$CONFIG_CRON_MINUTE > 59 )); then
					local m="$(getMessageText $MSG_INVALID_TIME "$ANSWER")"
					local t=$(center $WINDOW_COLS "$m")
					local ttm="$(getMessageText $TITLE_VALIDATIONERROR)"
					whiptail --msgbox "$t" --title "$ttm" $ROWS_MENU $WINDOW_COLS 2
				else
					logItem "hour: $CONFIG_CRON_HOUR minute: $CONFIG_CRON_MINUTE"
					break
				fi
			fi
		else
			break
		fi
	done

	[[ "$old" == "$CONFIG_CRON_HOUR:$CONFIG_CRON_MINUTE" ]]
	local rc=$?
	logExit "$rc - $CONFIG_CRON_HOUR:$CONFIG_CRON_MINUTE"
	return $rc

}

function config_systemdtime_do() {

	local old=$(printf "%02d:%02d" "$((10#$CONFIG_SYSTEMD_HOUR))" "$((10#$CONFIG_SYSTEMD_MINUTE))")
	current="$old"
	logEntry "$old"

	local b1="$(getMessageText $SELECT_TIME)"
	local c1="$(getMessageText $BUTTON_CANCEL)"
	local o1="$(getMessageText $BUTTON_OK)"
	getMenuText $MENU_CONFIG_TIME tt

	while :; do
		ANSWER=$(whiptail --inputbox "$b" --title "${tt[1]}" $ROWS_MENU $WINDOW_COLS --ok-button "$o1" --cancel-button "$c1" "$current" $ROWS_MENU $WINDOW_COLS 2 3>&1 1>&2 2>&3)
		if [ $? -eq 0 ]; then
			logItem "Answer: $ANSWER"
			current="$ANSWER"
			if [[ ! "$ANSWER" =~ ^[0-9]{1,2}:[0-9]{1,2}$ ]]; then
				local m="$(getMessageText $MSG_INVALID_TIME "$ANSWER")"
				local t=$(center $WINDOW_COLS "$m")
				local ttm="$(getMessageText $TITLE_VALIDATIONERROR)"
				whiptail --msgbox "$t" --title "$ttm" $ROWS_MENU $WINDOW_COLS 2
			else
				CONFIG_SYSTEMD_HOUR=$(cut -f1 -d: <<< "$ANSWER")
				CONFIG_SYSTEMD_MINUTE=$(cut -f2 -d: <<< "$ANSWER")
				if (( 10#$CONFIG_SYSTEMD_HOUR > 23 || 10#$CONFIG_SYSTEMD_MINUTE > 59 )); then
					local m="$(getMessageText $MSG_INVALID_TIME "$ANSWER")"
					local t=$(center $WINDOW_COLS "$m")
					local ttm="$(getMessageText $TITLE_VALIDATIONERROR)"
					whiptail --msgbox "$t" --title "$ttm" $ROWS_MENU $WINDOW_COLS 2
				else
					logItem "hour: $CONFIG_SYSTEMD_HOUR minute: $CONFIG_SYSTEMD_MINUTE"
					break
				fi
			fi
		else
			break
		fi
	done

	[[ "$old" == "$CONFIG_SYSTEMD_HOUR:$CONFIG_SYSTEMD_MINUTE" ]]
	local rc=$?
	logExit "$rc - $CONFIG_SYSTEMD_HOUR:$CONFIG_SYSTEMD_MINUTE"
	return $rc

}

function config_email_do() {

	getMenuText $MENU_CONFIG_EMAIL tt
	c1="$(getMessageText $BUTTON_CANCEL)"
	o1="$(getMessageText $BUTTON_OK)"

	local current="$CONFIG_EMAIL"
	local oldeMail="$current"

	local d="$(getMessageText $DESCRIPTION_EMAIL)"

	while :; do
		ANSWER=$(whiptail --inputbox "$d" --title "${tt[1]}" $ROWS_MENU $WINDOW_COLS "$current" --ok-button "$o1" --cancel-button "$c1" 3>&1 1>&2 2>&3)
		if [ $? -eq 0 ]; then
			logItem "Answer: $ANSWER"
			current="$ANSWER"
			if [[ -n "$current" ]]; then
				if ! [[ "$current" =~ ^[a-zA-Z0-9_.+-]+\@[a-zA-Z0-9-]+\.[a-zA-Z0-9.-]+$ ]]; then
					local m="$(getMessageText $MSG_INVALID_EMAIL "$current")"
					local t=$(center $WINDOW_COLS "$m")
					local ttm="$(getMessageText $TITLE_VALIDATIONERROR)"
					whiptail --msgbox "$t" --title "$ttm" $ROWS_MENU $WINDOW_COLS 2
				else
					CONFIG_EMAIL="$ANSWER"
					break
				fi
			else
				CONFIG_EMAIL="$ANSWER"
				break
			fi
		else
			logExit
			return 0
		fi
	done

	logItem "eMail: $CONFIG_EMAIL"

	if [[ -z $CONFIG_EMAIL ]]; then
		[[ "$oldeMail" == "$CONFIG_EMAIL" ]]
		local rc=$?
		logExit "$rc"
		return $rc
	fi

	local mail_=off
	local ssmtp_=off
	local msmtp_=off
	local old="$CONFIG_MAIL_PROGRAM"

	logEntry "$old"

	getMenuText $MENU_CONFIG_MAIL_MAIL m1
	getMenuText $MENU_CONFIG_MAIL_SSMTP m2
	getMenuText $MENU_CONFIG_MAIL_MSMTP m3
	local s1="${m1[0]}"
	local s2="${m2[0]}"
	local s3="${m3[0]}"

	local o1="$(getMessageText $BUTTON_OK)"
	local c1="$(getMessageText $BUTTON_CANCEL)"

	case "$CONFIG_MAIL_PROGRAM" in
		mail) mail_=on ;;
		ssmtp) ssmtp_=on ;;
		msmtp) msmtp_=on ;;
	esac

	local d="$(getMessageText $DESCRIPTION_MAIL_PROGRAM)"

	ANSWER=$(whiptail --radiolist "$d" --title "${tt[1]}" --ok-button "$o1" --cancel-button "$c1" $WT_HEIGHT $WT_WIDTH 3 \
		"${m1[@]}" "$mail_" \
		"${m2[@]}" "$ssmtp_" \
		"${m3[@]}" "$msmtp_" \
		3>&1 1>&2 2>&3)
	if [ $? -eq 0 ]; then
		logItem "Answer: $ANSWER"
		case "$ANSWER" in
			$s3) CONFIG_MAIL_PROGRAM="msmtp" ;;
			$s2) CONFIG_MAIL_PROGRAM="ssmtp" ;;
			$s1) CONFIG_MAIL_PROGRAM="mail" ;;
			*) whiptail --msgbox "Programm error, unrecognized backup type" $ROWS_MENU $WINDOW_COLS 2
				logExit
				return 1 ;;
		esac
	fi

	[[ "$old" == "$CONFIG_MAIL_PROGRAM" ]] && [[ "$oldeMail" == "$CONFIG_EMAIL" ]]

	local rc=$?
	logExit "$rc - $old:$CONFIG_MAIL_PROGRAM $oldeMail:$CONFIG_EMAIL"

	return $rc
}

function config_backuptype_do() {

	local dd_=off
	local tar_=off
	local rsync_=off
	local old="$CONFIG_BACKUPTYPE"

	logEntry "$old"

	getMenuText $MENU_CONFIG_TYPE_RSYNC m1
	getMenuText $MENU_CONFIG_TYPE_TAR m2
	getMenuText $MENU_CONFIG_TYPE_DD m3

	local s1="${m1[0]}"
	local s2="${m2[0]}"
	local s3="${m3[0]}"

	local o1="$(getMessageText $BUTTON_OK)"
	local c1="$(getMessageText $BUTTON_CANCEL)"

	case "$CONFIG_BACKUPTYPE" in
		dd) dd_=on ;;
		tar) tar_=on ;;
		rsync) rsync_=on ;;
	esac

	getMenuText $MENU_CONFIG_TYPE tt

	logItem "$b1"
	logItem "$t"

	local c1="$(getMessageText $BUTTON_CANCEL)"
	local o1="$(getMessageText $BUTTON_OK)"
	local d="$(getMessageText $DESCRIPTION_BACKUPTYPE)"

	ANSWER=$(whiptail --notags --radiolist "$d" --title "${tt[1]}" --ok-button "$o1" --cancel-button "$c1" $WT_HEIGHT $WT_WIDTH 3 \
		"${m1[@]}" "$rsync_" \
		"${m2[@]}" "$tar_" \
		"${m3[@]}" "$dd_" \
		3>&1 1>&2 2>&3)
	if [ $? -eq 0 ]; then
		logItem "Answer: $ANSWER"
		case "$ANSWER" in
			$s3) CONFIG_BACKUPTYPE="dd" ;;
			$s2) CONFIG_BACKUPTYPE="tar" ;;
			$s1) CONFIG_BACKUPTYPE="rsync"
				 CONFIG_ZIP_BACKUP=0 ;;
			"") : ;;
			*) whiptail --msgbox "Programm error, unrecognized backup type" $ROWS_MENU $WINDOW_COLS 2
				logExit
				return 1 ;;
		esac
	fi

	[[ "$old" == "$CONFIG_BACKUPTYPE" ]]
	local rc=$?
	logExit "$rc - $CONFIG_BACKUPTYPE"
	return $rc
}

function config_services_do() {

	local current="$CONFIG_STOPSERVICES"
	local old="$current"

	logEntry "$current"

	wtv=$(whiptail -v | cut -d " " -f 3)

	IFS=" "
	local as=( $(getActiveServices) )												# sorted alphabetically
	local state

	logItem "Active services: ${as[*]}"

	getMenuText $MENU_CONFIG_SERVICES tt

	logItem "INCLUDE_SERVICES_REGEX: "${INCLUDE_SERVICES_REGEX[@]}""
	local ci=() 					# list of included servcices
	local cu=()						# unselected services
	local css=( ${CONFIG_STOPSERVICES[*]} )										# already configured services
	local srvc
	for srvc in ${as[@]}; do
		if grep -q -i "$INCLUDE_SERVICES_REGEX" <<< "$srvc"; then			# service should be included
			ci+=( "$srvc" )
		elif containsElement "$srvc" "${css[@]}"; then
			ci+=( "$srvc" )																# service was already configured to be included
		else
			cu+=( "$srvc" )																# service was not included
		fi
	done

	local oldIFS="$IFS"
	IFS=$'\n' sorted=($(sort <<<"${ci[*]}"))										# sort list of included services
	IFS="$oldIFS"

	ci+=( ${cu[@]} ) 													  					# append unselected sevices (already sorted)

	# now build whiptail list, selected services first followed by unselected services

	local c=()
	for s in ${ci[@]}; do
		if containsElement "$s" "${cu[@]}"; then
			if [[ "$wtv" < "0.52.19" ]]; then	# workaround for whiptail issue in 0.52.19
				c+=("$s" "" "off")
			else
				c+=("$s" "$s" "off")
			fi
		else
			if [[ "$wtv" < "0.52.19" ]]; then	# workaround for whiptail issue in 0.52.19
				c+=("$s" "" "on")
			else
				c+=("$s" "$s" "on")
			fi
		fi
	done

	local d="$(getMessageText $DESCRIPTION_STARTSTOP_SERVICES)"
	local c1="$(getMessageText $BUTTON_CANCEL)"
	local o1="$(getMessageText $BUTTON_OK)"

	ANSWER=$(whiptail --notags --checklist "$d" --title "${tt[1]}" --ok-button "$o1" --cancel-button "$c1" $WT_HEIGHT $(($WT_WIDTH/2)) 7 \
		"${c[@]}" \
		3>&1 1>&2 2>&3)
	if [ $? -eq 0 ]; then
		logItem "Answer: $ANSWER"
		local current=${ANSWER//\"}
		CONFIG_STOPSERVICES="$current"
		if [[ -n $CONFIG_STOPSERVICES ]]; then
			config_service_sequence_do
			[ $? -ne 0 ] && CONFIG_STOPSERVICES="$old"
		else
			CONFIG_STOPSERVICES="$IGNORE_START_STOP_CHAR"
		fi
	fi

	logExit "$CONFIG_STOPSERVICES"

	[[ "$old" == "$CONFIG_STOPSERVICES" ]]
	return
}

function config_service_sequence_do() {

	local current="$CONFIG_STOPSERVICES"

	logEntry "$current"

	while :; do

		IFS=" "
		local src=( $current )
		local tgt=()
		local aborted=0

		while :; do

			local sl=()

			for s in ${src[@]}; do
				if [[ "$wtv" < "0.52.19" ]]; then	# workaround for whiptail issue in 0.52.19
					sl+=("$s" "" "")
				else
					sl+=("$s" "$s" "$s")
				fi
			done

			local d="$(getMessageText $DESCRIPTION_STARTSTOP_SEQUENCE)"
			local tt="$(getMessageText $TITLE_INFORMATION)"
			local c1="$(getMessageText $BUTTON_CANCEL)"
			local o1="$(getMessageText $BUTTON_OK)"

			ANSWER=$(whiptail --notags --radiolist "$d" --title "$tt" --ok-button "$o1" --cancel-button "$c1" $WT_HEIGHT $(($WT_WIDTH/2)) 5 \
				"${sl[@]}" \
				3>&1 1>&2 2>&3)
			if [ $? -eq 0 ]; then
				logItem "Answer: $ANSWER"
				local a=${ANSWER//\"}
				tgt+=( $a )
				local del=( $a )
				src=( ${src[@]/$del} )
				(( ${#src[@]} <= 0 )) && break
			else
				aborted=1
				break
			fi
		done

		if (( $aborted )); then
			logExit "aborted"
			return 1
		fi

		local pline sline t
		sel="${tgt[@]}"
		getStartStopCommands "$sel" "pline" "sline"
		pline=$(sed 's/\&/\\\&/g' <<< "$pline")
		sline=$(sed 's/\&/\\\&/g' <<< "$sline")

		logItem "Commands: $pline"

		local tl=()
		local i=1
		for t in ${tgt[@]}; do
			if [[ "$wtv" < "0.52.19" ]]; then	# workaround for whiptail issue in 0.52.19
				tl+=("$i: $t" "" on)
			else
				tl+=("$i: $t" "$i: $t" on)
			fi
			(( i++ ))
		done

		local m="$(getMessageText $MSG_SEQUENCE_OK)"
		local t=$(center $(( $WINDOW_COLS*2 )) "$m")
		local y="$(getMessageText $BUTTON_YES)"
		local n="$(getMessageText $BUTTON_NO)"
		local tt="$(getMessageText $TITLE_CONFIRM)"

		ANSWER=$(whiptail --notags --checklist "$m" --title "$tt" --ok-button "$o1" --cancel-button "$c1" $WT_HEIGHT $(($WT_WIDTH/2)) 7 \
			"${tl[@]}" \
			3>&1 1>&2 2>&3)
		if [ $? -eq 0 ]; then
			logItem "Answer: $ANSWER"
			CONFIG_STOPSERVICES="${tgt[@]}"
			break
		fi

	done

	logExit "$CONFIG_STOPSERVICES"
}

function config_partitions_do() {

	local old="$CONFIG_PARTITIONS_TO_BACKUP"

	logEntry "$old"

	IFS="$DEFAULT_IFS"

	wtv=$(whiptail -v | cut -d " " -f 3)

	local rootPartition=$(findmnt / -o source -n | sed -E 's/p?[0-9]+$//') # /dev/sda or /dev/mmcblk0
	logItem "Rootpartition: $rootPartition"

	local done=0

	while ((! $done)); do

		local current="$CONFIG_PARTITIONS_TO_BACKUP"

		logItem "Current: $current"
		local c=($current)

#	1 256M c W95
#	2 14.3G 83 Linux
#	5 265G 83 Linux

		local ps=()
		local line
		while IFS= read -r line; do
			ps+=("$line")
		done <<< "$(getPartitionNumbers $rootPartition)"

		local numberOfPartitions=${#ps[@]}
		logItem "Partitions: $numberOfPartitions"

		local pn=()
		local -A pn_desc
		local state s
		IFS="$DEFAULT_IFS"

		for s in "${ps[@]}"; do
			local n="$(cut -f1 -d " " <<< "$s")"
			pn+=($n)
			pn_desc[$n]="$(cut -f2- -d " " <<< "$s")"
		done

		getMenuText $MENU_CONFIG_MODE_PARTITION tt

		local cl=()
		# add all partitions in list
		for s in ${pn[@]}; do
			if containsElement "$s" "${c[@]}"; then
				state=on
			else
				state=off
			fi
			if [[ "$wtv" < "0.52.19" ]]; then	# workaround for whiptail issue in 0.52.19
				cl+=("$s" "" "$state")
			else
				local desc="$(printf "%6s %s" $(cut -d ' ' -f 1 <<< "${pn_desc[$s]}") $(cut -d ' ' -f 2- <<< "${pn_desc[$s]}"))"
				cl+=("$s" "$s: ${desc}" "$state")
			fi
		done

		local d="$(getMessageText $DESCRIPTION_PARTITIONS)"
		local c1="$(getMessageText $BUTTON_CANCEL)"
		local o1="$(getMessageText $BUTTON_OK)"

		ANSWER=$(whiptail --notags --checklist "$d" --title "${tt[1]}" --ok-button "$o1" --cancel-button "$c1" $WT_HEIGHT $(($WT_WIDTH/2)) 7 \
			"${cl[@]}" \
			3>&1 1>&2 2>&3)
		if [ $? -eq 0 ]; then
			logItem "Answer: $ANSWER"
			local current=${ANSWER//\"}
			# make sure the first two partitions are included
			local orgCurrent="$current"
			current="1 2 $current" # add first two partitions
			current="$(tr ' ' '\n' <<< "$current" | sort -u | tr '\n' ' ' | sed 's/^[ \t]*//;s/[ \t]*$//')" # remove duplicates
			CONFIG_PARTITIONS_TO_BACKUP="$current"
			[[ "$orgCurrent" == "$current" ]] # check the first partitions were not deselected
			done=$(( ! $? ))

			if (( ! $done )); then
				local m="$(getMessageText $MSG_FIRST_PARTITIONS_NOT_SELECTED)"
				local t=$(center $WINDOW_COLS "$m")
				local tt="$(getMessageText $TITLE_INFORMATION)"
				whiptail --msgbox "$t" --title "$tt" $ROWS_MSGBOX $WINDOW_COLS 2
			fi
		else
			CONFIG_PARTITIONS_TO_BACKUP="$old"
			done=1
		fi
	done

	[[ "$old" == "$CONFIG_PARTITIONS_TO_BACKUP" ]]
	local rc=$?
	logExit "$rc - $CONFIG_PARTITIONS_TO_BACKUP"
	return $rc
}

function config_cronday_do() {

	local old="$CONFIG_CRON_DAY"

	logEntry "$old"

	local days_=(off off off off off off off off)
	local i

	getMenuText $MENU_DAYS_SHORT s
	getMenuText $MENU_DAYS_LONG l
	getMenuText $MENU_CONFIG_DAY tt

	days_[$CONFIG_CRON_DAY]=on # 0 = Daily, 1 = Sun, 2 = Mon ...

	ANSWER=$(whiptail --notags --radiolist "" --title "${tt[1]}" $WT_HEIGHT $(($WT_WIDTH/2)) 5 \
		"${s[0]}" "${l[0]}" "${days_[0]}" \
		"${s[1]}" "${l[1]}" "${days_[1]}" \
		"${s[2]}" "${l[2]}" "${days_[2]}" \
		"${s[3]}" "${l[3]}" "${days_[3]}" \
		"${s[4]}" "${l[4]}" "${days_[4]}" \
		"${s[5]}" "${l[5]}" "${days_[5]}" \
		"${s[6]}" "${l[6]}" "${days_[6]}" \
		"${s[7]}" "${l[7]}" "${days_[7]}" \
		3>&1 1>&2 2>&3)
	if [ $? -eq 0 ]; then
		logItem "Answer: $ANSWER"
		for (( i=0; i< ${#s[@]}; i++ )); do
			if [[ "${s[$i]}" == "$ANSWER" ]]; then
				CONFIG_SYSTEMD_DAY=$i
				break;
			fi
		done
		CONFIG_CRON_DAY="$i"
	fi

	[[ "$old" == "$CONFIG_CRON_DAY" ]]
	rc=$?
	logExit "$rc - $CONFIG_CRON_DAY"
	return $rc
}

function config_systemday_do() {

	local old="$CONFIG_SYSTEMD_DAY"

	logEntry "$old"

	local days_=(off off off off off off off off)
	local i

	getMenuText $MENU_DAYS_SHORT s
	getMenuText $MENU_DAYS_LONG l
	getMenuText $MENU_CONFIG_DAY tt

	days_[$CONFIG_SYSTEMD_DAY]=on # 0 = Daily, 1 = Sun, 2 = Mon ...

	ANSWER=$(whiptail --notags --radiolist "" --title "${tt[1]}" $WT_HEIGHT $(($WT_WIDTH/2)) 5 \
		"${s[0]}" "${l[0]}" "${days_[0]}" \
		"${s[1]}" "${l[1]}" "${days_[1]}" \
		"${s[2]}" "${l[2]}" "${days_[2]}" \
		"${s[3]}" "${l[3]}" "${days_[3]}" \
		"${s[4]}" "${l[4]}" "${days_[4]}" \
		"${s[5]}" "${l[5]}" "${days_[5]}" \
		"${s[6]}" "${l[6]}" "${days_[6]}" \
		"${s[7]}" "${l[7]}" "${days_[7]}" \
		3>&1 1>&2 2>&3)
	if [ $? -eq 0 ]; then
		logItem "Answer: $ANSWER"
		for (( i=0; i< ${#s[@]}; i++ )); do
			if [[ "${s[$i]}" == "$ANSWER" ]]; then
				CONFIG_SYSTEMD_DAY=$i
				break;
			fi
		done
	fi

	[[ "$old" == "$CONFIG_SYSTEMD_DAY" ]]
	rc=$?
	logExit "$rc - $CONFIG_SYSTEMD_DAY"
	return $rc
}

function config_compress_do() {

	logEntry "$CONFIG_ZIP_BACKUP"
	local old="$CONFIG_ZIP_BACKUP"

	if [ $CONFIG_BACKUPTYPE == "rsync" ]; then
		local t=$(center $WINDOW_COLS "rsync backups cannot be compressed.")
		local tt="$(getMessageText $TITLE_INFORMATION)"
		whiptail --msgbox "$t" --title "$tt" $ROWS_MENU $WINDOW_COLS 2
	else
		local yes_=off
		local no_=off

		case "$CONFIG_ZIP_BACKUP" in
			"1") yes_=on ;;
			"0") no_=on ;;
			*) whiptail --msgbox "Programm error, unrecognized compress mode $CONFIG_ZIP_BACKUP" $ROWS_MENU $WINDOW_COLS 2
				logExit
				return 1
				;;
		esac

		local o1="$(getMessageText $BUTTON_OK)"
		local c1="$(getMessageText $BUTTON_CANCEL)"

		getMenuText $MENU_CONFIG_COMPRESS_ON m1
		getMenuText $MENU_CONFIG_COMPRESS_OFF m2
		local s1="${m1[0]}"
		local s2="${m2[0]}"

		local d="$(getMessageText $DESCRIPTION_COMPRESS)"
		getMenuText $MENU_CONFIG_ZIP tt

		ANSWER=$(whiptail --notags --radiolist "$d" --title "${tt[1]}" --ok-button "$o1" --cancel-button  "$c1" $WT_HEIGHT $(($WT_WIDTH/2)) 2 \
			"${m1[@]}" "$yes_" \
			"${m2[@]}" "$no_" \
			3>&1 1>&2 2>&3)
		if [ $? -eq 0 ]; then
			logItem "Answer: $ANSWER"
			case "$ANSWER" in
			$s1) CONFIG_ZIP_BACKUP="1" ;;
			$s2) CONFIG_ZIP_BACKUP="0" ;;
			*) whiptail --msgbox "Programm error, unrecognized compress mode $ANSWER" $ROWS_MENU $WINDOW_COLS 2
				logExit
				return 1
				;;
			esac
		fi
	fi

	[[ "$old" == "$CONFIG_ZIP_BACKUP" ]]
	local rc=$?
	logExit "$rc - $CONFIG_ZIP_BACKUP"
	return $rc

}

function progressbar_do() { # <name of description array> <menu title> <funcs to execute>

	logEntry

	local descArrayName="$1"
	eval "$descArrayName+=(\"Done\")"
	shift
	local title="$1"
	shift
	declare todo=("${@}")
	todo+=("finished")
	num_todo=${#todo[*]}
	local step=$((100 / (num_todo - 1 )))
	local idx=0
	local counter=0
	local desc
	PROGRESSBAR_DO=1
	rm /tmp/$MYSELF.err &>/dev/null
	local ERROR_FILE="/tmp/$MYSELF.err"
	(
		while
			:
			eval "desc=\${$descArrayName[\$idx]}"
		do
			desc=$(center $WINDOW_COLS "$desc")

			cat <<EOF
XXX
$counter
$desc
XXX
EOF
			if ((idx < num_todo)); then
				e="$(${todo[$idx]})"
				if [[ -n "$e" ]]; then
					logItem "Progressbar detected error $e"
					echo "$e" > $ERROR_FILE
					break
				fi
			else
				break
			fi
			((idx += 1))
			((counter += step))
			sleep 1
		done
	) |
		whiptail --title "$title" --gauge "Please wait" 6 70 0
	logExit

	PROGRESSBAR_DO=0
	if [[ -f /tmp/$MYSELF.err ]]; then
		m="$(<$ERROR_FILE)"
		logItem "Detected error $m"
		rm $ERROR_FILE &>/dev/null
		local id="$(cut -f1 -d' ' <<< $m)"
		local msg="$(cut -f2- -d' ' <<< $m)"
		logItem "Rethrowing error from progressbar id: $id - msg: $msg"
		unrecoverableError "$id" "$msg"
	fi
}

function uninstall_menu() {

	logEntry

	while :; do

		getMenuText $MENU_UNINSTALL_UNINSTALL m1
		getMenuText $MENU_UNINSTALL_EXTENSION m2

		local b1="$(getMessageText $BUTTON_BACK)"
		local o1="$(getMessageText $BUTTON_SELECT)"
		getMenuText $MENU_UNINSTALL tt

		local s1="${m1[0]}"
		local s2="${m2[0]}"

		FUN=$(whiptail --title "${tt[1]}" --menu "" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button "$b1" --ok-button "$o1" \
			"${m1[@]}" \
			"${m2[@]}" \
			3>&1 1>&2 2>&3)
		RET=$?
		if [ $RET -eq 1 ]; then
			logExit
			return 0
		elif [ $RET -eq 0 ]; then
			logItem "$FUN"
			case "$FUN" in
				$s1) uninstall_do ;;
				$s2) extensions_uninstall_do ;;
			*) whiptail --msgbox "Programm error: unrecognized option $FUN" $ROWS_MENU $WINDOW_COLS 1 ;;
			esac || whiptail --msgbox "There was an error running option $FUN" $ROWS_MENU $WINDOW_COLS 1
		fi
	done
	logExit

}

function isUpdatePossible() {
		logEntry
		logItem "script: c:$VERSION_CURRENT p:$VERSION_PROPERTY"
		if isNewerVersion "$VERSION_CURRENT" "$VERSION_PROPERTY"; then
			logExit 0
			return 0
		fi
		logItem "installer: c:$VERSION_CURRENT_INSTALLER p:$VERSION_PROPERTY_INSTALLER"
		if isNewerVersion "$VERSION_CURRENT_INSTALLER" "$VERSION_PROPERTY_INSTALLER"; then
			logExit 0
			return 0
		fi
		logExit 1
		return 1
}

function uninstall_do() {

	logEntry

	if ! isRaspiBackupInstalled; then
		local m="$(getMessageText $MSG_SCRIPT_NOT_INSTALLED)"
		local t=$(center $WINDOW_COLS "$m")
		local tt="$(getMessageText $TITLE_INFORMATION)"
		whiptail --msgbox "$t" --title "$tt" $ROWS_MSGBOX $WINDOW_COLS 2
		logExit
		return
	fi

	help

	local m="$(getMessageText $MSG_QUESTION_UNINSTALL)"
	local t=$(center $WINDOW_COLS "$m")
	local y="$(getMessageText $BUTTON_YES)"
	local n="$(getMessageText $BUTTON_NO)"
	local tt="$(getMessageText $TITLE_CONFIRM)"

	if ! whiptail --yesno "$t" --title "$tt" --yes-button "$y" --no-button "$n" --defaultno $ROWS_MSGBOX $WINDOW_COLS 2 3>&1 1>&2 2>&3; then
		logExit
		return
	fi

	UNINSTALL_DESCRIPTION=("Deleting $RASPIBACKUP_NAME extensions ..." "Deleting $RASPIBACKUP_NAME timer configuration ..." "Deleting $RASPIBACKUP_NAME configurations ..."  "Deleting misc files ..." "Deleting $FILE_TO_INSTALL ..." "Deleting $RASPIBACKUP_NAME installer ...")
	progressbar_do "UNINSTALL_DESCRIPTION" "Uninstalling $RASPIBACKUP_NAME" extensions_uninstall_execute timer_uninstall_execute config_uninstall_execute misc_uninstall_execute uninstall_script_execute uninstall_execute

	logExit

}

function config_timer_menu() {

	logEntry
	local rc

	if (( $USE_SYSTEMD )); then
		systemd_timer_menu
	else
		cron_timer_menu
	fi
	rc=$?

	logExit $rc
	return $rc
}


function cron_timer_menu() {

	logEntry

	if ! isCrontabConfigInstalled; then
		INSTALL_DESCRIPTION=("Installing $RASPIBACKUP_NAME crond configurations ..."  )
		progressbar_do "INSTALL_DESCRIPTION" "Installing $RASPIBACKUP_NAME crond configuration" cron_install_execute
	fi
	if ! isCrontabConfigInstalled; then
		local m="$(getMessageText $MSG_CRON_NOT_INSTALLED)"
		local t=$(center $WINDOW_COLS "$m")
		local tt="$(getMessageText $TITLE_INFORMATION)"
		whiptail --msgbox "$t" --title "$tt" $ROWS_MSGBOX $WINDOW_COLS 2
		logExit
		return 1
	fi

	local enabled
	isTimerEnabled
	enabled=$(( !$? ))

	local old=$enabled
	local cron_updated=0

	while :; do

		local b1="$(getMessageText $BUTTON_BACK)"
		local o1="$(getMessageText $BUTTON_SELECT)"
		local m="$(getMessageText $MSG_TIMER_NA)"
		local t=$(center $WINDOW_COLS "$m")
		local d="$(getMessageText $DESCRIPTION_CRON)"

		getMenuText $MENU_REGULARBACKUP_ENABLE ct
		getMenuText $MENU_CONFIG_DAY m1
		getMenuText $MENU_CONFIG_TIME m2
		getMenuText $MENU_CONFIG_TIME tt

		if (( $enabled )); then
			getMenuText $MENU_REGULARBACKUP_DISABLE ct
			local s1="${m1[0]}"
			local s2="${m2[0]}"
		else
			getMenuText $MENU_REGULARBACKUP_ENABLE ct
			m1=(" " " ")
			m2=(" " " ")
		fi

		FUN=$(whiptail --title "${tt[1]}" --menu "$d" $WT_HEIGHT $WT_WIDTH $((WT_MENU_HEIGHT-5)) --cancel-button "$b1" --ok-button "$o1" \
			"${ct[@]}" \
			"${m1[@]}" \
			"${m2[@]}" \
			3>&1 1>&2 2>&3)
		RET=$?
		if [ $RET -eq 1 ]; then
			break
		elif [ $RET -eq 0 ]; then
			logItem "$FUN"
			case "$FUN" in
				$s1) config_cronday_do; cron_updated=$(( $cron_updated|$? )) ;;
				$s2) config_crontime_do; cron_updated=$(( $cron_updated|$? )) ;;
				$ct) CRONTAB_ENABLED=$((!$CRONTAB_ENABLED)); enabled=$((!$enabled)); cron_updated=$(( $old != $enabled || $cron_updated )) ;;
				\ *) whiptail --msgbox "$t" $ROWS_MENU $WINDOW_COLS 1 ;;
				*) whiptail --msgbox "Programm error: unrecognized option $FUN" $ROWS_MENU $WINDOW_COLS 1 ;;
			esac || whiptail --msgbox "There was an error running option $FUN" $ROWS_MENU $WINDOW_COLS 1
		fi
	done

	logExit $cron_updated

	return $cron_updated

}

function systemd_timer_menu() {

	logEntry

	if ! isSystemdConfigInstalled; then
		INSTALL_DESCRIPTION=("Installing $RASPIBACKUP_NAME systemd configurations ..."  )
		progressbar_do "INSTALL_DESCRIPTION" "Installing $RASPIBACKUP_NAME" systemd_install_execute
	fi
	if ! isSystemdConfigInstalled; then
		local m="$(getMessageText $MSG_SYSTEMD_NOT_INSTALLED)"
		local t=$(center $WINDOW_COLS "$m")
		local tt="$(getMessageText $TITLE_INFORMATION)"
		whiptail --msgbox "$t" --title "$tt" $ROWS_MSGBOX $WINDOW_COLS 2
		logExit
		return 1
	fi

	local enabled
	isSystemdEnabled
	enabled=$(( !$? ))

	local old=$enabled
	local systemd_updated=0

	while :; do

		local b1="$(getMessageText $BUTTON_BACK)"
		local o1="$(getMessageText $BUTTON_SELECT)"
		local m="$(getMessageText $MSG_TIMER_NA)"
		local t=$(center $WINDOW_COLS "$m")
		local d="$(getMessageText $DESCRIPTION_SYSTEMD)"

		getMenuText $MENU_REGULARBACKUP_ENABLE ct
		getMenuText $MENU_CONFIG_DAY m1
		getMenuText $MENU_CONFIG_TIME m2
		getMenuText $MENU_CONFIG_REGULAR tt

		if (( $enabled )); then
			getMenuText $MENU_REGULARBACKUP_DISABLE ct
			local s1="${m1[0]}"
			local s2="${m2[0]}"
		else
			getMenuText $MENU_REGULARBACKUP_ENABLE ct
			m1=(" " " ")
			m2=(" " " ")
		fi

		FUN=$(whiptail --title "${tt[1]}" --menu "$d" $WT_HEIGHT $WT_WIDTH $((WT_MENU_HEIGHT-5)) --cancel-button "$b1" --ok-button "$o1" \
			"${ct[@]}" \
			"${m1[@]}" \
			"${m2[@]}" \
			3>&1 1>&2 2>&3)
		RET=$?
		if [ $RET -eq 1 ]; then
			break
		elif [ $RET -eq 0 ]; then
			logItem "$FUN"
			case "$FUN" in
				$s1) config_systemday_do; systemd_updated=$(( $systemd_updated|$? )) ;;
				$s2) config_systemdtime_do; systemd_updated=$(( $systemd_updated|$? )) ;;
				$ct) SYSTEMD_ENABLED=$((!$SYSTEMD_ENABLED)); enabled=$((!$enabled)); systemd_updated=$(( $old != $enabled || $systemd_updated )) ;;
				\ *) whiptail --msgbox "$t" $ROWS_MENU $WINDOW_COLS 1 ;;
				*) whiptail --msgbox "Programm error: unrecognized option $FUN" $ROWS_MENU $WINDOW_COLS 1 ;;
			esac || whiptail --msgbox "There was an error running option $FUN" $ROWS_MENU $WINDOW_COLS 1
		fi
	done

	logExit $systemd_updated

	return $systemd_updated

}

function install_menu() {

	logEntry

	isInternetAvailable
	local rc=$?
	if (( $rc )); then
		local a="$(getMessageText $MSG_NO_INTERNET_CONNECTION_FOUND $rc)"
		whiptail --msgbox "$a" --title "Error" $ROWS_MSGBOX $WINDOW_COLS 2
		logExit
		return 0
	fi

	while :; do

		local b1="$(getMessageText $BUTTON_BACK)"
		local o1="$(getMessageText $BUTTON_SELECT)"

		local d="$(getMessageText $DESCRIPTION_INSTALLATION)"

		getMenuText $MENU_INSTALL_INSTALL m1
		getMenuText $MENU_INSTALL_EXTENSIONS m2
		local s1="${m1[0]}"
		local s2="${m2[0]}"
		getMenuText $MENU_INSTALL tt

		FUN=$(whiptail --title "${tt[1]}" --menu "$d" $WT_HEIGHT $WT_WIDTH $((WT_MENU_HEIGHT-5)) --cancel-button "$b1" --ok-button "$o1" \
			"${m1[@]}" \
			"${m2[@]}" \
			3>&1 1>&2 2>&3)
		RET=$?
		if [ $RET -eq 1 ]; then
			logExit
			return 0
		elif [ $RET -eq 0 ]; then
			logItem "$FUN"
			case "$FUN" in
				$s1) install_do ;;
				$s2) extensions_install_do ;;
				*) whiptail --msgbox "Programm error: unrecognized option $FUN" $ROWS_MENU $WINDOW_COLS 1 ;;
			esac || whiptail --msgbox "There was an error running option $FUN" $ROWS_MENU $WINDOW_COLS 1
		fi
	done
	logExit

}

function update_menu() {

	logEntry

	isInternetAvailable
	local rc=$?
	if (( $rc )); then
		local a="$(getMessageText $MSG_NO_INTERNET_CONNECTION_FOUND $rc)"
		whiptail --msgbox "$a" --title "$TITLE_ERROR" $ROWS_MSGBOX $WINDOW_COLS 2
		logExit
		retrun 0
	fi

	while :; do

		local b1=$(getMessageText $BUTTON_BACK)
		local o1=$(getMessageText $BUTTON_SELECT)

		getMenuText $MENU_UPDATE_SCRIPT m1
		getMenuText $MENU_UPDATE_INSTALLER m2
		getMenuText $MENU_UPDATE tt
		local nua="$(getMessageText $MSG_NO_UPDATE_AVAILABLE)"

		local s1="${m1[0]}"
		local s2="${m2[0]}"

		if isNewerVersion "$VERSION_CURRENT" "$VERSION_PROPERTY"; then
			m1[1]="${m1[1]} ($VERSION_CURRENT -> $VERSION_PROPERTY)"
		else
			m1[1]="${m1[1]} $nua"
		fi

		if isNewerVersion "$VERSION_CURRENT_INSTALLER" "$VERSION_PROPERTY_INSTALLER"; then
			m2[1]="${m2[1]} ($VERSION_CURRENT_INSTALLER -> $VERSION_PROPERTY_INSTALLER)"
		else
			m2[1]="${m2[1]} $nua"
		fi

		FUN=$(whiptail --title "${tt[1]}" --menu "" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button "$b1" --ok-button "$o1" \
			"${m1[@]}" \
			"${m2[@]}" \
			3>&1 1>&2 2>&3)
		RET=$?
		if [ $RET -eq 1 ]; then
			logExit
			return 0
		elif [ $RET -eq 0 ]; then
			logItem "$FUN"
			case "$FUN" in
				$s1) update_script_do ;;
				$s2) update_installer_do ;;
				*) whiptail --msgbox "Programm error: unrecognized option $FUN" $ROWS_MENU $WINDOW_COLS 1 ;;
			esac || whiptail --msgbox "There was an error running option $FUN" $ROWS_MENU $WINDOW_COLS 1
			parseCurrentVersions
		fi
	done
	logExit

}

function update_script_do() {

	logEntry

	if ! isRaspiBackupInstalled; then
		local m="$(getMessageText $MSG_SCRIPT_NOT_INSTALLED)"
		local t=$(center $WINDOW_COLS "$m")
		local y="$(getMessageText $BUTTON_YES)"
		local n="$(getMessageText $BUTTON_NO)"
		local tt="$(getMessageText $TITLE_CONFIRM)"

		if ! whiptail --yesno "$t" --title "$tt" --yes-button "$y" --no-button "$n" $ROWS_MSGBOX $WINDOW_COLS 2; then
			logExit
			return
		fi
	fi

	INSTALL_DESCRIPTION=("Downloading $FILE_TO_INSTALL ...")
	progressbar_do "INSTALL_DESCRIPTION" "Updating $FILE_TO_INSTALL" update_script_execute

	logExit

}

function update_installer_do() {

	logEntry

	INSTALL_DESCRIPTION=("Downloading $MYSELF ...")
	progressbar_do "INSTALL_DESCRIPTION" "Updating $MYSELF" update_installer_execute

	exec $INSTALLER_ABS_PATH/$MYSELF # restart installer, no return

	logExit

}

function install_do() {

	logEntry

	if isRaspiBackupInstalled; then
		local m="$(getMessageText $MSG_SCRIPT_ALREADY_INSTALLED)"
		local t=$(center $WINDOW_COLS "$m")
		local y="$(getMessageText $BUTTON_YES)"
		local n="$(getMessageText $BUTTON_NO)"
		local tt="$(getMessageText $TITLE_CONFIRM)"

		if ! whiptail --yesno "$t" --title "$tt" --yes-button "$y" --no-button "$n" $ROWS_MSGBOX $WINDOW_COLS 2; then
			logExit
			return
		fi
	fi
	INSTALLATION_STARTED=1

	if (( $USE_SYSTEMD )); then
		INSTALL_DESCRIPTION=("Downloading $FILE_TO_INSTALL ..." "Downloading $RASPIBACKUP_NAME configuration template ..." "Creating default $RASPIBACKUP_NAME configuration ..." "Installing $RASPIBACKUP_NAME systemd config ...")
		progressbar_do "INSTALL_DESCRIPTION" "Installing $RASPIBACKUP_NAME" code_download_execute config_download_execute config_update_execute systemd_install_execute
	else
		INSTALL_DESCRIPTION=("Downloading $FILE_TO_INSTALL ..." "Downloading $RASPIBACKUP_NAME configuration template ..." "Creating default $RASPIBACKUP_NAME configuration ..." "Installing $RASPIBACKUP_NAME cron config ...")
		progressbar_do "INSTALL_DESCRIPTION" "Installing $RASPIBACKUP_NAME" code_download_execute config_download_execute config_update_execute cron_install_execute
	fi
	INSTALLATION_SUCCESSFULL=1

	logExit

}

function config_download_do() {

	logEntry

	DOWNLOAD_DESCRIPTION=("Downloading $RASPIBACKUP_NAME configuration ...")
	progressbar_do "DOWNLOAD_DESCRIPTION" "Downloading $FILE_TO_INSTALL configuration template" config_download_execute

	logExit

}

function config_update_do() {

	logEntry

	if ! isConfigInstalled; then
		local m="$(getMessageText $MSG_CONFIG_NOT_INSTALLED)"
		local t=$(center $WINDOW_COLS "$m")
		local tt="$(getMessageText $TITLE_INFORMATION)"
		whiptail --msgbox "$t" --title "$tt" $ROWS_MSGBOX $WINDOW_COLS 2
		logExit
		return
	fi

	UPDATE_DESCRIPTION=("Updating $RASPIBACKUP_NAME configuration ...")
	progressbar_do "UPDATE_DESCRIPTION" "Updating $RASPIBACKUP_NAME configuration" config_update_execute

	logExit

}

function timer_update_do() {

	logEntry
	local rc

	if (( $USE_SYSTEMD )); then
		systemd_update_do
	else
		cron_update_do
	fi
	rc=$?

	logExit $rc
	return $rc
}

function cron_update_do() {

	logEntry

	if ! isCrontabConfigInstalled; then
		local m="$(getMessageText $MSG_CRON_NOT_INSTALLED)"
		local t=$(center $WINDOW_COLS "$m")
		local tt="$(getMessageText $TITLE_INFORMATION)"
		whiptail --msgbox "$t" --title "$tt" $ROWS_MSGBOX $WINDOW_COLS 2
		logExit
		return
	fi

	UPDATE_DESCRIPTION=("Updating $RASPIBACKUP_NAME crontab configuration ...")
	progressbar_do "UPDATE_DESCRIPTION" "Updating $RASPIBACKUP_NAME crontab configuration" cron_update_execute
	logExit

}

function systemd_update_do() {

	logEntry

	if ! isSystemdConfigInstalled; then
		local m="$(getMessageText $MSG_SYSTEMD_NOT_INSTALLED)"
		local t=$(center $WINDOW_COLS "$m")
		local tt="$(getMessageText $TITLE_INFORMATION)"
		whiptail --msgbox "$t" --title "$tt" $ROWS_MSGBOX $WINDOW_COLS 2
		logExit
		return
	fi

	UPDATE_DESCRIPTION=("Updating $RASPIBACKUP_NAME systemd configuration ..." "Configure systemd timer")
	progressbar_do "UPDATE_DESCRIPTION" "Updating $RASPIBACKUP_NAME systemd configuration" systemd_update_execute systemd_timer_execute
	logExit

}

function config_backupmode_do() {

	local normal_mode=off
	local partition_mode=off
	local old="$CONFIG_PARTITIONBASED_BACKUP"
	local rc

	logEntry "$old"

	case "$CONFIG_PARTITIONBASED_BACKUP" in
		0) normal_mode=on ;;
		1) partition_mode=on ;;
		*) whiptail --msgbox "Programm error, unrecognized backup mode $CONFIG_PARTITIONBASED_BACKUP" $ROWS_MENU $WINDOW_COLS 2
			logExit
			return 1
			;;
	esac

	getMenuText $MENU_CONFIG_MODE_NORMAL m1
	getMenuText $MENU_CONFIG_MODE_PARTITION m2
	local s1="${m1[0]}"
	local s2="${m2[0]}"

	getMenuText $MENU_CONFIG_MODE tt
	local o1="$(getMessageText $BUTTON_OK)"
	local c1="$(getMessageText $BUTTON_CANCEL)"
	local d="$(getMessageText $DESCRIPTION_BACKUPMODE)"

	local partitionsUpdated=0

	ANSWER=$(whiptail --notags --radiolist "$d" --title "${tt[1]}" --ok-button "$o1" --cancel-button "$c1" $ROWS_MENU $WINDOW_COLS 2 \
		"${m1[@]}" $normal_mode \
		"${m2[@]}" $partition_mode \
		3>&1 1>&2 2>&3)
	if [ $? -eq 0 ]; then
		logItem "Answer: $ANSWER"
		case "$ANSWER" in
		$s1) CONFIG_PARTITIONBASED_BACKUP="0"
			CONFIG_PARTITIONS_TO_BACKUP="$DEFAULT_CONFIG_PARTITIONS_TO_BACKUP" # reset default
			;;
		$s2) CONFIG_PARTITIONBASED_BACKUP="1"
			config_partitions_do
			if [ $? -eq 1 ]; then
				partitionsUpdated=1
			fi
			;;
		*) whiptail --msgbox "Programm error, unrecognized backup mode $ANSWER" $ROWS_MENU $WINDOW_COLS 2
			logExit 1
			return 1
			;;
		esac
	fi

	[[ "$old" == "$CONFIG_PARTITIONBASED_BACKUP" ]] && (( $partitionsUpdated == 0 ))
	rc=$?
	logExit $rc
	return $rc
}

function config_message_detail_do() {

	local detailed_=off
	local normal_=off
	local old="$CONFIG_MSG_LEVEL"

	logEntry "$old"

	case $CONFIG_MSG_LEVEL in
		"1") detailed_=on ;;
		"0") normal_=on ;;
		*)
			whiptail --msgbox "Programm error, unrecognized message level $CONFIG_MSG_LEVEL" $ROWS_MENU $WINDOW_COLS 2
			logExit
			return 1
			;;
	esac

	getMenuText $MENU_CONFIG_MESSAGE_N m1
	getMenuText $MENU_CONFIG_MESSAGE_V m2

	local d="$(getMessageText $DESCRIPTION_MESSAGEDETAIL)"
	getMenuText $MENU_CONFIG_MESSAGE tt

	local s1="${m1[0]}"
	local s2="${m2[0]}"

	ANSWER=$(whiptail --notags --radiolist "$d" --title "${tt[1]}" $ROWS_MENU $WINDOW_COLS 2 \
		"${m1[@]}" $normal_ \
		"${m2[@]}" $detailed_ \
		3>&1 1>&2 2>&3)
	if [ $? -eq 0 ]; then
		logItem "Answer: $ANSWER"
		case "$ANSWER" in
			$s1) CONFIG_MSG_LEVEL="0";;
			$s2) CONFIG_MSG_LEVEL="1" ;;
			*) whiptail --msgbox "Programm error, unrecognized message level $ANSWER" $ROWS_MENU $WINDOW_COLS 2
				logExit
				return 1
				;;
		esac
	fi

	[[ "$old" == "$CONFIG_MSG_LEVEL" ]]
	local rc=$?
	logExit "$rc - $CONFIG_MSG_LEVEL"
	return $rc

}

function config_language_do() {

	local old="$CONFIG_LANGUAGE"

	logEntry "$old"

	[[ -z "$CONFIG_LANGUAGE" ]] && CONFIG_LANGUAGE="$LANG_SYSTEM"

	if ! containsElement "$CONFIG_LANGUAGE" "${SUPPORTED_LANGUAGES[@]}"; then
		whiptail --msgbox "Unsupported language \"$CONFIG_LANGUAGE\". Falling back to EN (English)" $ROWS_MENU $WINDOW_COLS 2
		CONFIG_LANGUAGE="EN"
	fi

	local lng=()
	local l m state

	for l in "${SUPPORTED_LANGUAGES[@]}"; do
		local menuLang="MENU_CONFIG_LANGUAGE_$l"
		getMenuText ${!menuLang} m
		[[ "$l" == "$CONFIG_LANGUAGE" ]] && state=on || state=off
		lng+=(${m[@]} $state)
	done

	getMenuText $MENU_LANGUAGE tt
	local o1="$(getMessageText $BUTTON_OK)"
	local c1="$(getMessageText $BUTTON_CANCEL)"
	local d="$(getMessageText $DESCRIPTION_LANGUAGE)"

	local listSize=${#SUPPORTED_LANGUAGES[@]}
	(( $listSize > 7 )) && listSize=7

	ANSWER=$(whiptail --notags --radiolist "$d" --title "${tt[1]}" --ok-button "$o1" --cancel-button "$c1" $ROWS_MENU $WINDOW_COLS $listSize \
		"${lng[@]}" \
		3>&1 1>&2 2>&3)
	if [ $? -eq 0 ]; then
		logItem "Answer: $ANSWER"
 		CONFIG_LANGUAGE="${ANSWER^^*}"
	fi

	[[ "$old" == "$CONFIG_LANGUAGE" ]]
	local rc=$?
	logExit "$rc - $CONFIG_LANGUAGE"
	return $rc

}

# Borrowed from http://blog.yjl.im/2012/01/printing-out-call-stack-in-bash.html

function logStack() {
	local i=0
	local FRAMES=${#BASH_LINENO[@]}
	# FRAMES-2 skips main, the last one in arrays
	echo >>"$LOG_FILE"
	for ((i = FRAMES - 2; i >= 0; i--)); do
		echo '  File' \"${BASH_SOURCE[i + 1]}\", line ${BASH_LINENO[i]}, in ${FUNCNAME[i + 1]} >>"$LOG_FILE"
		# Grab the source code of the line
		sed -n "${BASH_LINENO[i]}{s/^/    /;p}" "${BASH_SOURCE[i + 1]}" >> "$LOG_FILE"
	done
}

# 0 -> yes (current is older than actual)
# 1 -> no (current is actual)
# 2 -> no (current is newer)
function isNewerVersion() { # current actual

	logEntry "$1 $2"

	local version="$1"
	local newVersion="$2"
	local suffix=""
	local rc=99

	if [[ -z "$1" || -z "$2" ]]; then
		rc=1
		logExit "isNewVersion $1 <-> $2 - RC: $rc"
		return $rc
	fi

	local suffix=""
	if [[ "$version" =~ ^([^-]*)(-(.*))?$ ]]; then
		version=${BASH_REMATCH[1]}
		suffix=${BASH_REMATCH[3]}
	fi

	grep -iq beta <<< "$version"
	local IS_BETA=$((! $? ))
	grep -iq dev <<< "$version"
	local IS_DEV=$((! $? ))
	grep -iq hotfix <<< "$version"
	local IS_HOTFIX=$((! $? ))

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

	logExit "isNewVersion $1 <-> $2 - RC: $rc"

	return $rc

}

#VERSION="0.6.3.1"
#INCOMPATIBLE=""
#BETA="0.6.3.2"
#VERSION_INSTALLER="0.4"
#INCOMPATIBLE_INSTALLER=""
#BETA_INSTALLER=""

function parsePropertiesFile() { # propertyFileName

	logEntry

	local properties=$(grep "^VERSION=" "$1" 2>/dev/null)
	[[ $properties =~ $PROPERTY_REGEX ]] && VERSION_PROPERTY=${BASH_REMATCH[1]}
	properties=$(grep "^INCOMPATIBLE=" "$1" 2>/dev/null)
	[[ $properties =~ $PROPERTY_REGEX ]] && INCOMPATIBLE_PROPERTY=${BASH_REMATCH[1]}
	properties=$(grep "^BETA=" "$1" 2>/dev/null)
	[[ $properties =~ $PROPERTY_REGEX ]] && BETA_PROPERTY=${BASH_REMATCH[1]}
	logItem "Script properties: v: $VERSION_PROPERTY i: $INCOMPATIBLE_PROPERTY b: $BETA_PROPERTY"

	local properties=$(grep "^VERSION_INSTALLER=" "$1" 2>/dev/null)
	[[ $properties =~ $PROPERTY_REGEX ]] && VERSION_PROPERTY_INSTALLER=${BASH_REMATCH[1]}
	properties=$(grep "^INCOMPATIBLE_INSTALLER=" "$1" 2>/dev/null)
	[[ $properties =~ $PROPERTY_REGEX ]] && INCOMPATIBLE_PROPERTY_INSTALLER=${BASH_REMATCH[1]}
	properties=$(grep "^BETA_INSTALLER=" "$1" 2>/dev/null)
	[[ $properties =~ $PROPERTY_REGEX ]] && BETA_PROPERTY_INSTALLER=${BASH_REMATCH[1]}
	logItem "Installer properties: v: $VERSION_PROPERTY_INSTALLER i: $INCOMPATIBLE_PROPERTY_INSTALLER b: $BETA_PROPERTY_INSTALLER"

	logExit

}

function parseCurrentVersions() {
	logEntry
	[[ -f $FILE_TO_INSTALL_ABS_FILE ]] && VERSION_CURRENT=$(grep -o -E "^VERSION=\".+\"" "$FILE_TO_INSTALL_ABS_FILE" | sed -e "s/VERSION=//" -e "s/\"//g")
	[[ -f $INSTALLER_ABS_FILE ]] && VERSION_CURRENT_INSTALLER=$(grep -o -E "^VERSION=\".+\"" "$INSTALLER_ABS_FILE" | sed -e "s/VERSION=//" -e "s/\"//g")
	logItem "Current script version: $VERSION_CURRENT"
	logItem "Current installer version: $VERSION_CURRENT_INSTALLER"
	logExit
}

function downloadPropertiesFile_do() {

	logEntry
	if shouldRenewDownloadPropertiesFile; then
		DOWNLOAD_DESCRIPTION=("Updating latest version information ...")
		progressbar_do "DOWNLOAD_DESCRIPTION" "Downloading version information" downloadPropertiesFile_execute
	fi
	logExit

}

function downloadPropertiesFile_execute() {

	logEntry

	NEW_PROPERTIES_FILE=0

	if (( ! $RASPIBACKUP_INSTALL_DEBUG )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_DOWNLOADING_PROPERTYFILE
		local httpCode="$(downloadFile "$PROPERTY_URL" "$LATEST_TEMP_PROPERTY_FILE")"
		if (( ! $? )); then
			NEW_PROPERTIES_FILE=1
		else
			unrecoverableError $MSG_DOWNLOAD_FAILED "$(downloadURL "$PROPERTY_URL")" "$httpCode"
			logExit
		fi
	fi

	logExit "$NEW_PROPERTIES_FILE"
	return
}

function shouldRenewDownloadPropertiesFile() {

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

function error() {
	logStack
	cat "$LOG_FILE"
}

DAYNUM_TO_MENU=("Daily" "Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat")
declare -A DAYNUM_FROM_MENU
for ((i=0; i<${#DAYNUM_TO_MENU[@]}; i++)); do
	DAYNUM_FROM_MENU[${DAYNUM_TO_MENU[$i]}]=$i
done

function daynum_to_config_string() {

	logEntry "$1"
	local ret

	if (( $USE_SYSTEMD )); then
		if (( $1 == 0 )); then
			ret=""
		else
			ret="${DAYNUM_TO_MENU[$1]} " # addtl space to separate day
		fi
	else
		if (( $1 == 0 )); then
			ret="*"
		else
			(( ret = $1 - 1 ))
		fi
	fi

	logExit "$ret"
	echo "$ret"
}

function daynum_from_config_string() {

	logEntry "$1"
	local ret

	if [[ -z $1 || "$1" == "*" ]]; then
		ret="0"
	else
		if (( $USE_SYSTEMD )); then
			ret=${DAYNUM_FROM_MENU[$1]}
		else
			(( ret = $1 + 1 ))
		fi
	fi

	logExit "$ret"
	echo "$ret"

}

function daynum_to_menu_string() {

	logEntry "$1"
	local ret=${DAYNUM_TO_MENU[$1]}

	logExit "$ret"
	echo "$ret"
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

	if (( $l < 4 )); then
		echo "$MASQUERADE_STRING$l"
		return 0
	fi

	local s=${t:0:1}
	local e=${t: -1}

	if (( $l < 8 )); then
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

	# email

	if [[ -n "$CONFIG_EMAIL" ]]; then
		logItem "Masquerading eMail"
		m="$(masquerade "$CONFIG_EMAIL")"
		sed -i -E "s/$CONFIG_EMAIL/${m}/g" $LOG_FILE
	fi

	# In home directories usually first names are used

	logItem "Masquerading home directory name"
	sed -i -E "s/\/home\/([^\\/])+\/(.)/\/home\/@USER@\/\2/g" $LOG_FILE

	# hostname may expose domain names

	logItem "Masquerading hostname"
	sed -i -E "s/$HOSTNAME/@HOSTNAME@/g" $LOG_FILE

	if (( $xEnabled )); then	# enable xtrace again
        	set -x
	fi

}

#
# Interactive use loop
#

function uiInstall() {

	logEntry
	clear

	calc_wt_size

	local configFound=0
	if isConfigInstalled; then
		parseConfig
		configFound=1
	fi

	if isInternetAvailable; then
		if existsLocalPropertiesFile; then
			parsePropertiesFile "$LOCAL_PROPERTY_FILE"
		else
			downloadPropertiesFile_do
			parsePropertiesFile "$LATEST_TEMP_PROPERTY_FILE"
		fi
	fi

	parseCurrentVersions

	if (( ! $configFound )); then
		navigation_do
	fi

	while :; do

		getMenuText $MENU_LANGUAGE m1
		getMenuText $MENU_INSTALL m2
		getMenuText $MENU_CONFIGURE m3
		getMenuText $MENU_UNINSTALL m4
		getMenuText $MENU_UPDATE m5
		getMenuText $MENU_ABOUT m9

		local f1="$(getMessageText $BUTTON_FINISH)"
		local sel1="$(getMessageText $BUTTON_SELECT)"

		local s1="${m1[0]}"
		local s2="${m2[0]}"
		local s3="${m3[0]}"
		local s4="${m4[0]}"
		local s5="${m5[0]}"
		local s9="${m9[0]}"

		local mx=( 	\
			"${m1[@]}" \
			"${m2[@]}" \
			)

		if isRaspiBackupInstalled; then
			mx+=("${m3[@]}" "${m4[@]}")
		fi

		if isUpdatePossible; then
			mx+=("${m5[@]}")
		fi

		mx+=("${m9[@]}")

		TITLE="$(getMessageText $MSG_TITLE)"
		FUN=$(whiptail --title "$TITLE" --menu "" $WT_HEIGHT $WT_WIDTH $((WT_MENU_HEIGHT-3)) --cancel-button "$f1" --ok-button "$sel1"\
			"${mx[@]}" \
			3>&1 1>&2 2>&3)
		RET=$?
		if [ $RET -eq 1 ]; then
			do_finish
		elif [ $RET -eq 0 ]; then
			logItem "$FUN"
			case "$FUN" in
				$s1) config_language_do
					local r=$?
					logItem "rc: $r"
					if (( $r )); then
						if isConfigInstalled; then
							config_update_do
							parseConfig
						fi
					fi
					;;
				$s2) install_menu ;;
				$s3) config_menu ;;
				$s4) uninstall_menu ;;
				$s5) update_menu ;;
				$s9) about_do ;;
				\ *) : ;;
				*) whiptail --msgbox "Programm error: unrecognized option $FUN" $ROWS_MENU $WINDOW_COLS 1 ;;
			esac || whiptail --msgbox "There was an error running option $FUN" $ROWS_MENU $WINDOW_COLS 1
		else
			logExit
			exit 1
		fi
	done
	logExit
}

function unattendedInstall() {

	logEntry

	if (( MODE_INSTALL )); then
		check4InternetAvailable
		code_download_execute
		config_download_execute
		config_update_execute
		if (( $USE_SYSTEMD )); then
			systemd_install_execute
		else
			cron_install_execute
		fi
		if (( MODE_EXTENSIONS )); then
			extensions_install_execute
		fi
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_INSTALLATION_FINISHED $RASPIBACKUP_NAME
	elif (( MODE_UPDATE )); then
		check4InternetAvailable
		update_installer_execute
	elif (( MODE_EXTENSIONS )); then
		check4InternetAvailable
		extensions_install_execute
	else # uninstall
		extensions_uninstall_execute
		systemd_uninstall_execute
		cron_uninstall_execute
		config_uninstall_execute
		uninstall_script_execute
		uninstall_execute
	fi
	logExit

}

function first_steps() {
	logEntry
	local a="$(getMessageText $MSG_FIRST_STEPS)"
	local t=$(center $(($WINDOW_COLS * 2)) "$a")
	local tt="$(getMessageText $TITLE_FIRST_STEPS)"
	whiptail --msgbox "$t" --title "$tt" $ROWS_ABOUT $(($WINDOW_COLS * 2)) 1
	logExit
}

function show_help() {
	echo $GIT_CODEVERSION
	echo "$MYSELF ( -i [-e]? | -u | -U | -t [crond|systemd] )"
	echo "-e: unattended (re)install of $RASPIBACKUP_NAME extensions"
	echo "-i: unattended (re)install of $RASPIBACKUP_NAME"
	echo "-h: display this help"
	echo "-U: unattended update of $MYSELF"
	echo "-u: unattended uninstall of $RASPIBACKUP_NAME"
	echo "-t: use either crond or systemd for backup timer"
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

CALLING_USER="$(findUser)"

INVOCATIONPARMS=""			# save passed opts for logging
invocationParms=()			# and restart
for (( i=1; i<=$#; i++ )); do
	p=${!i}
	INVOCATIONPARMS="$INVOCATIONPARMS $p"
done

CLEANUP_LOG=0

MODE_UNATTENDED=0
MODE_UNINSTALL=0
MODE_INSTALL=0
MODE_UPDATE=0 # force install
MODE_EXTENSIONS=0
MODE_FORCE_TIMER=0 # flag that option -t was used to override default behavior

USE_SYSTEMD=$SYSTEMD_DETECTED # use SYTEMD if detected
if isCrontabConfigInstalled; then # use cron if already installed
	USE_SYSTEMD=0
fi

if [[ $1 == "--version" ]]; then
	echo $GIT_CODEVERSION
	exit
fi

while getopts "t:h?uUei" opt; do
    case "$opt" in
	 h|\?)
       show_help
       exit 0
       ;;
    i) MODE_INSTALL=1
		 MODE_UNATTENDED=1
       ;;
    e) MODE_EXTENSIONS=1
		 MODE_UNATTENDED=1
		 ;;
    U) MODE_UPDATE=1
		 MODE_UNATTENDED=1
		 ;;
    u) MODE_UNINSTALL=1
		 MODE_UNATTENDED=1
		 ;;

	 t) case $OPTARG in
			crond) USE_SYSTEMD=0
					MODE_FORCE_TIMER=1
				;;
			systemd) USE_SYSTEMD=1
					MODE_FORCE_TIMER=1
				;;
			*) echo "Invalid parameter$OPTARG for option -t"
				show_help
				exit 1
				;;
		 esac
		 ;;
	*)  echo "Unknown option $op"
		 show_help
		 exit 1
		 ;;
    esac
done

shift $((OPTIND-1))

if (( $UID != 0 )); then
	t=$(getMessageText $MSG_LEVEL_MINIMAL $MSG_RUNASROOT "$0" "$INVOCATIONPARMS")
	echo "$t"
	exit 1
fi

trapWithArg cleanup SIGINT SIGTERM EXIT

writeToConsole $MSG_VERSION "$GIT_CODEVERSION"

rm $LOG_FILE &>/dev/null
logItem "$GIT_CODEVERSION"
sep="$(getMessageText $MSG_SENSITIVE_SEPARATOR)"
warn="$(getMessageText $MSG_SENSITIVE_WARNING)"
logItem "$sep"
logItem "$warn"
logItem "$sep"

logItem "whiptail version: $(whiptail -v)"
logItem "SYSTEMD_DETECTED: $SYSTEMD_DETECTED"

checkRequiredDirectories

if (( $MODE_UNATTENDED )); then
	unattendedInstall
else
	uiInstall
fi

