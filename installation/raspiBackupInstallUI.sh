#!/usr/bin/env bash
#######################################################################################################################
#
# Script to download, install, configure and uninstall raspiBackup.sh using windows.
# Commandline installation is also possible. Use option -h to get a list of all options.
#
# Visit http://www.linux-tips-and-tricks.de/raspiBackup for latest code and other details
#
#######################################################################################################################
#
#    Copyright (c) 2015-2020 framp at linux-tips-and-tricks dot de
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

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}
VERSION="0.4.3.4" 	# -beta, -hotfix or -dev suffixes possible

if [[ (( ${BASH_VERSINFO[0]} < 4 )) || ( (( ${BASH_VERSINFO[0]} == 4 )) && (( ${BASH_VERSINFO[1]} < 3 )) ) ]]; then
	echo "bash version 0.4.3 or beyond is required by $MYSELF" # nameref feature, declare -n var=$v
	exit 1
fi

if ! which whiptail &>/dev/null; then
	echo "$MYSELF depends on whiptail. Please install whiptail first."
	exit 1
fi

MYHOMEDOMAIN="www.linux-tips-and-tricks.de"
MYHOMEURL="https://$MYHOMEDOMAIN"

MYDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GIT_DATE="$Date: 2020-11-24 20:02:50 +0100$"
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<<$GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<<$GIT_DATE)
GIT_COMMIT="$Sha1: 4ca22ad$"
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<<$GIT_COMMIT | sed 's/\$//')

GIT_CODEVERSION="$MYSELF $VERSION, $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"

FILE_TO_INSTALL="raspiBackup.sh"

RASPIBACKUP_NAME=${FILE_TO_INSTALL%.*}
RASPIBACKUP_INSTALL_DEBUG=0 # just disable some code for debugging

CURRENT_DIR=$(pwd)
NL=$'\n'
IGNORE_START_STOP_CHAR=":"
FILE_TO_INSTALL_BETA="raspiBackup_beta.sh"
declare -A CONFIG_DOWNLOAD_FILE=(['DE']="raspiBackup_de.conf" ['EN']="raspiBackup_en.conf")
CONFIG_FILE="raspiBackup.conf"
SAMPLEEXTENSION_TAR_FILE="raspiBackupSampleExtensions.tgz"
DEFAULT_IFS="$IFS"

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

PROPERTY_URL="$MYHOMEURL/downloads/raspibackup0613-properties/download"
BETA_DOWNLOAD_URL="$MYHOMEURL/downloads/raspibackup-beta-sh/download"
PROPERTY_FILE_NAME="$MYNAME.properties"
LATEST_TEMP_PROPERTY_FILE="/tmp/$PROPERTY_FILE_NAME"
LOCAL_PROPERTY_FILE="$CURRENT_DIR/.$PROPERTY_FILE_NAME"
INSTALLER_DOWNLOAD_URL="$MYHOMEURL/downloads/raspibackupinstallui-sh/download"
STABLE_CODE_URL="$FILE_TO_INSTALL"

DOWNLOAD_TIMEOUT=60 # seconds
DOWNLOAD_RETRIES=3

BIN_DIR="/usr/local/bin"
ETC_DIR="/usr/local/etc"
CRON_DIR="/etc/cron.d"
LOG_FILE="$MYNAME.log"

CONFIG_FILE_ABS_PATH="$ETC_DIR"
CONFIG_ABS_FILE="$CONFIG_FILE_ABS_PATH/$CONFIG_FILE"
FILE_TO_INSTALL_ABS_PATH="$BIN_DIR"
FILE_TO_INSTALL_ABS_FILE="$FILE_TO_INSTALL_ABS_PATH/$FILE_TO_INSTALL"
CRON_ABS_FILE="$CRON_DIR/$RASPIBACKUP_NAME"
INSTALLER_ABS_PATH="$BIN_DIR"
INSTALLER_ABS_FILE="$INSTALLER_ABS_PATH/$MYSELF"
VAR_LIB_DIRECTORY="/var/lib/$RASPIBACKUP_NAME"

PROPERTY_REGEX='.*="([^"]*)"'

[[ -z "${LANG}" ]] && LANG="en_US.UTF-8"
LANG_EXT="${LANG,,*}"
LANG_SYSTEM="${LANG_EXT:0:2}"
if [[ $LANG_SYSTEM != "de" && $LANG_SYSTEM != "en" ]]; then
	LANG_SYSTEM="en"
fi
MESSAGE_LANGUAGE="${LANG_SYSTEM^^*}"

# default configs
CONFIG_LANGUAGE="${LANG_SYSTEM^^*}"
CONFIG_MSG_LEVEL="0"
CONFIG_BACKUPTYPE="rsync"
CONFIG_KEEPBACKUPS="3"
CONFIG_BACKUPPATH="/backup"
CONFIG_ZIP_BACKUP="0"
CONFIG_CRON_HOUR="5"
CONFIG_CRON_MINUTE="0"
CONFIG_CRON_DAY="1" # Sun
CONFIG_MAIL_PROGRAM="mail"
CONFIG_EMAIL=""

ROWS_MSGBOX=10
ROWS_ABOUT=16
ROWS_MENU=20
WINDOW_COLS=70

MSG_EN=1 # english	(default)
MSG_DE=1 # german

MSG_PRF="RBI"

declare -A MSG_EN
declare -A MSG_DE

SCNT=0
MSG_UNDEFINED=$((SCNT++))
MSG_EN[$MSG_UNDEFINED]="${MSG_PRF}0000E: Undefined messageid."
MSG_DE[$MSG_UNDEFINED]="${MSG_PRF}0000E: Unbekannte Meldungsid."
MSG_VERSION=$((SCNT++))
MSG_EN[$MSG_VERSION]="${MSG_PRF}0001I: %1"
MSG_DE[$MSG_VERSION]="${MSG_PRF}0001I: %1"
MSG_DOWNLOADING=$((SCNT++))
MSG_EN[$MSG_DOWNLOADING]="${MSG_PRF}0002I: Downloading %1..."
MSG_DE[$MSG_DOWNLOADING]="${MSG_PRF}0002I: %1 wird aus dem Netz geladen..."
MSG_DOWNLOAD_FAILED=$((SCNT++))
MSG_EN[$MSG_DOWNLOAD_FAILED]="${MSG_PRF}0003E: Download of %1 failed. HTTP code: %2."
MSG_DE[$MSG_DOWNLOAD_FAILED]="${MSG_PRF}0003E: %1 kann nicht aus dem Netz geladen werden. HTTP code: %2."
MSG_INSTALLATION_FAILED=$((SCNT++))
MSG_EN[$MSG_INSTALLATION_FAILED]="${MSG_PRF}0004E: Installation of %1 failed. Check %2."
MSG_DE[$MSG_INSTALLATION_FAILED]="${MSG_PRF}0004E: Installation von %1 fehlerhaft beendet. Prüfe %2."
MSG_SAVING_FILE=$((SCNT++))
MSG_EN[$MSG_SAVING_FILE]="${MSG_PRF}0005I: Existing file %1 saved as %2."
MSG_DE[$MSG_SAVING_FILE]="${MSG_PRF}0005I: Existierende Datei %1 wurde als %2 gesichert."
MSG_CHMOD_FAILED=$((SCNT++))
MSG_EN[$MSG_CHMOD_FAILED]="${MSG_PRF}0006E: chmod of %1 failed."
MSG_DE[$MSG_CHMOD_FAILED]="${MSG_PRF}0006E: chmod von %1 nicht möglich."
MSG_MOVE_FAILED=$((SCNT++))
MSG_EN[$MSG_MOVE_FAILED]="${MSG_PRF}0007E: mv of %1 failed."
MSG_DE[$MSG_MOVE_FAILED]="${MSG_PRF}0007E: mv von %1 nicht möglich."
MSG_CLEANUP=$((SCNT++))
MSG_EN[$MSG_CLEANUP]="${MSG_PRF}0008I: Cleaning up..."
MSG_DE[$MSG_CLEANUP]="${MSG_PRF}0008I: Räume auf..."
MSG_INSTALLATION_FINISHED=$((SCNT++))
MSG_EN[$MSG_INSTALLATION_FINISHED]="${MSG_PRF}0009I: Installation of %1 finished successfully."
MSG_DE[$MSG_INSTALLATION_FINISHED]="${MSG_PRF}0009I: Installation von %1 erfolgreich beendet."
MSG_UPDATING_CONFIG=$((SCNT++))
MSG_EN[$MSG_UPDATING_CONFIG]="${MSG_PRF}0010I: Updating configuration in %1."
MSG_DE[$MSG_UPDATING_CONFIG]="${MSG_PRF}0010I: Konfigurationsdatei %1 wird angepasst."
MSG_DELETE_FILE=$((SCNT++))
MSG_EN[$MSG_DELETE_FILE]="${MSG_PRF}0011I: Deleting %1..."
MSG_DE[$MSG_DELETE_FILE]="${MSG_PRF}0011I: Lösche %1..."
MSG_UNINSTALL_FINISHED=$((SCNT++))
MSG_EN[$MSG_UNINSTALL_FINISHED]="${MSG_PRF}0012I: Uninstall of %1 finished successfully."
MSG_DE[$MSG_UNINSTALL_FINISHED]="${MSG_PRF}0012I: Deinstallation von %1 erfolgreich beendet."
MSG_UNINSTALL_FAILED=$((SCNT++))
MSG_EN[$MSG_UNINSTALL_FAILED]="${MSG_PRF}0013E: Delete of %1 failed."
MSG_DE[$MSG_UNINSTALL_FAILED]="${MSG_PRF}0013E: Löschen von %1 fehlerhaft beendet."
MSG_DOWNLOADING_BETA=$((SCNT++))
MSG_EN[$MSG_DOWNLOADING_BETA]="${MSG_PRF}0014I: Downloading %1 beta..."
MSG_DE[$MSG_DOWNLOADING_BETA]="${MSG_PRF}0014I: %1 beta wird aus dem Netz geladen..."
MSG_CODE_INSTALLED=$((SCNT++))
MSG_EN[$MSG_CODE_INSTALLED]="${MSG_PRF}0015I: Created %1."
MSG_DE[$MSG_CODE_INSTALLED]="${MSG_PRF}0015I: %1 wurde erstellt."
MSG_NOT_INSTALLED=$((SCNT++))
MSG_EN[$MSG_NOT_INSTALLED]="${MSG_PRF}0016I: %1 not installed."
MSG_DE[$MSG_NOT_INSTALLED]="${MSG_PRF}0016I: %1 nicht installiert."
MSG_CHOWN_FAILED=$((SCNT++))
MSG_EN[$MSG_CHOWN_FAILED]="${MSG_PRF}0017E: chown of %1 failed."
MSG_DE[$MSG_CHOWN_FAILED]="${MSG_PRF}0017E: chown von %1 nicht möglich."
MSG_SAMPLEEXTENSION_INSTALL_FAILED=$((SCNT++))
MSG_EN[$MSG_SAMPLEEXTENSION_INSTALL_FAILED]="${MSG_PRF}0018E: Sample extension installation failed. %1"
MSG_DE[$MSG_SAMPLEEXTENSION_INSTALL_FAILED]="${MSG_PRF}0018E: Beispielserweiterungsinstallation fehlgeschlagen. %1"
MSG_SAMPLEEXTENSION_INSTALL_SUCCESS=$((SCNT++))
MSG_EN[$MSG_SAMPLEEXTENSION_INSTALL_SUCCESS]="${MSG_PRF}0019I: Sample extensions successfully installed and enabled."
MSG_DE[$MSG_SAMPLEEXTENSION_INSTALL_SUCCESS]="${MSG_PRF}0019I: Beispielserweiterungen erfolgreich installiert und eingeschaltet."
MSG_INSTALLING_CRON_TEMPLATE=$((SCNT++))
MSG_EN[$MSG_INSTALLING_CRON_TEMPLATE]="${MSG_PRF}0020I: Creating cron file %1."
MSG_DE[$MSG_INSTALLING_CRON_TEMPLATE]="${MSG_PRF}0020I: Crondatei %1 wird erstellt."
MSG_NO_INTERNET_CONNECTION_FOUND=$((SCNT++))
MSG_EN[$MSG_NO_INTERNET_CONNECTION_FOUND]="${MSG_PRF}0021E: Unable to connect to $MYHOMEDOMAIN. wget RC: %1"
MSG_DE[$MSG_NO_INTERNET_CONNECTION_FOUND]="${MSG_PRF}0021E: Es kann nicht auf $MYHOMEDOMAIN zugegriffen werden. wget RC: %1"
MSG_CHECK_INTERNET_CONNECTION=$((SCNT++))
MSG_EN[$MSG_CHECK_INTERNET_CONNECTION]="${MSG_PRF}0022I: Checking internet connection."
MSG_DE[$MSG_CHECK_INTERNET_CONNECTION]="${MSG_PRF}0022I: Teste Internetverbindung."
MSG_SAMPLEEXTENSION_UNINSTALL_FAILED=$((SCNT++))
MSG_EN[$MSG_SAMPLEEXTENSION_UNINSTALL_FAILED]="${MSG_PRF}0023E: Sample extension uninstall failed. %1"
MSG_DE[$MSG_SAMPLEEXTENSION_UNINSTALL_FAILED]="${MSG_PRF}0023E: Beispielserweiterungsdeinstallation fehlgeschlagen. %1"
MSG_SAMPLEEXTENSION_UNINSTALL_SUCCESS=$((SCNT++))
MSG_EN[$MSG_SAMPLEEXTENSION_UNINSTALL_SUCCESS]="${MSG_PRF}0024I: Sample extensions successfully deleted."
MSG_DE[$MSG_SAMPLEEXTENSION_UNINSTALL_SUCCESS]="${MSG_PRF}0024I: Beispielserweiterungen erfolgreich gelöscht."
MSG_UNINSTALLING_CRON_TEMPLATE=$((SCNT++))
MSG_EN[$MSG_UNINSTALLING_CRON_TEMPLATE]="${MSG_PRF}0025I: Deleting cron file %1."
MSG_DE[$MSG_UNINSTALLING_CRON_TEMPLATE]="${MSG_PRF}0025I: Crondatei %1 wird gelöscht."
MSG_UPDATING_CRON=$((SCNT++))
MSG_EN[$MSG_UPDATING_CRON]="${MSG_PRF}0026I: Updating cron configuration in %1."
MSG_DE[$MSG_UPDATING_CRON]="${MSG_PRF}0026I: Cron Konfigurationsdatei %1 wird angepasst."
MSG_MISSING_DIRECTORY=$((SCNT++))
MSG_EN[$MSG_MISSING_DIRECTORY]="${MSG_PRF}0027E: Missing required directory %1."
MSG_DE[$MSG_MISSING_DIRECTORY]="${MSG_PRF}0027E: Erforderliches Verzeichnis %1 existiert nicht."
MSG_CODE_UPDATED=$((SCNT++))
MSG_EN[$MSG_CODE_UPDATED]="${MSG_PRF}0028I: Updated %1 with latest available release."
MSG_DE[$MSG_CODE_UPDATED]="${MSG_PRF}0028I: %1 wurde mit dem letzen aktuellen Release erneuert."
MSG_TITLE=$((SCNT++))
MSG_EN[$MSG_TITLE]="$RASPIBACKUP_NAME Installation and Configuration Tool V${VERSION}"
MSG_DE[$MSG_TITLE]="$RASPIBACKUP_NAME Installations- und Konfigurations Tool V${VERSION}"
BUTTON_FINISH=$((SCNT++))
MSG_EN[$BUTTON_FINISH]="Finish"
MSG_DE[$BUTTON_FINISH]="Beenden"
BUTTON_SELECT=$((SCNT++))
MSG_EN[$BUTTON_SELECT]="Select"
MSG_DE[$BUTTON_SELECT]="Auswahl"
BUTTON_BACK=$((SCNT++))
MSG_EN[$BUTTON_BACK]="Back"
MSG_DE[$BUTTON_BACK]="Zurück"
SELECT_TIME=$((SCNT++))
MSG_EN[$SELECT_TIME]="Enter time of backup in format hh:mm"
MSG_DE[$SELECT_TIME]="Die Backupzeit im Format hh:mm eingeben"
BUTTON_CANCEL=$((SCNT++))
MSG_EN[$BUTTON_CANCEL]="Cancel"
MSG_DE[$BUTTON_CANCEL]="Abbruch"
BUTTON_OK=$((SCNT++))
MSG_EN[$BUTTON_OK]="Ok"
MSG_DE[$BUTTON_OK]="Bestätigen"
MSG_QUESTION_UPDATE_CONFIG=$((SCNT++))
MSG_EN[$MSG_QUESTION_UPDATE_CONFIG]="Do you want to save the updated $RASPIBACKUP_NAME configuration now?"
MSG_DE[$MSG_QUESTION_UPDATE_CONFIG]="Soll die geänderte Konfiguration von $RASPIBACKUP_NAME jetzt gespeichert werden?"
MSG_QUESTION_IGNORE_MISSING_STARTSTOP=$((SCNT++))
MSG_EN[$MSG_QUESTION_IGNORE_MISSING_STARTSTOP]="There are no services stopped before starting the backup.${NL}WARNING${NL}Inconsistent backups may be created with $RASPIBACKUP_NAME.${NL}Are you sure?"
MSG_DE[$MSG_QUESTION_IGNORE_MISSING_STARTSTOP]="Es werden keine Services vor dem Start des Backups gestoppt.${NL}WARNUNG${NL}Dadurch können inkonsistente Backups mit $RASPIBACKUP_NAME entstehen.${NL}Ist das beabsichtigt?"
MSG_QUESTION_UPDATE_CRON=$((SCNT++))
MSG_EN[$MSG_QUESTION_UPDATE_CRON]="Do you want to save the updated cron settings for $RASPIBACKUP_NAME now?"
MSG_DE[$MSG_QUESTION_UPDATE_CRON]="Soll die geänderte cron Konfiguration für $RASPIBACKUP_NAME jetzt gespeichert werden?"
MSG_SEQUENCE_OK=$((SCNT++))
MSG_EN[$MSG_SEQUENCE_OK]="Stopcommands for services will be executed in following sequence. Startcommands will be executed in reverse sequence. Sequence OK?"
MSG_DE[$MSG_SEQUENCE_OK]="Stopbefehle für die Services werden in folgender Reihenfolge ausgeführt. Startbefehle werden umgekehrt ausgeführt. Ist die Reihenfolge richtig?"
BUTTON_YES=$((SCNT++))
MSG_EN[$BUTTON_YES]="Yes"
MSG_DE[$BUTTON_YES]="Ja"
BUTTON_NO=$((SCNT++))
MSG_EN[$BUTTON_NO]="No"
MSG_DE[$BUTTON_NO]="Nein"
MSG_QUESTION_UNINSTALL=$((SCNT++))
MSG_EN[$MSG_QUESTION_UNINSTALL]="Are you sure to uninstall $RASPIBACKUP_NAME ?"
MSG_DE[$MSG_QUESTION_UNINSTALL]="Soll $RASPIBACKUP_NAME wirklich deinstalliert werden ?"
MSG_SCRIPT_NOT_INSTALLED=$((SCNT++))
MSG_EN[$MSG_SCRIPT_NOT_INSTALLED]="$RASPIBACKUP_NAME not installed."
MSG_DE[$MSG_SCRIPT_NOT_INSTALLED]="$RASPIBACKUP_NAME ist nicht installiert"
MSG_CRON_NA=$((SCNT++))
MSG_EN[$MSG_CRON_NA]="Weekly backup disabled."
MSG_DE[$MSG_CRON_NA]="Wöchentliches Backup ist ausgeschaltet."
MSG_CONFIG_NOT_INSTALLED=$((SCNT++))
MSG_EN[$MSG_CONFIG_NOT_INSTALLED]="No configuration found."
MSG_DE[$MSG_CONFIG_NOT_INSTALLED]="Keine Konfiguration gefunden."
MSG_CRON_NOT_INSTALLED=$((SCNT++))
MSG_EN[$MSG_CRON_NOT_INSTALLED]="No cron configuration found."
MSG_DE[$MSG_CRON_NOT_INSTALLED]="Keine cron Konfiguration gefunden."
MSG_NO_UPDATE_AVAILABLE=$((SCNT++))
MSG_EN[$MSG_NO_UPDATE_AVAILABLE]="(No update available)"
MSG_DE[$MSG_NO_UPDATE_AVAILABLE]="(Kein Update verfügbar)"
MSG_NO_EXTENSIONS_FOUND=$((SCNT++))
MSG_EN[$MSG_NO_EXTENSIONS_FOUND]="No extensions installed."
MSG_DE[$MSG_NO_EXTENSIONS_FOUND]="Keine Erweiterungen installiert."
MSG_EXTENSIONS_ALREADY_INSTALLED=$((SCNT++))
MSG_EN[$MSG_EXTENSIONS_ALREADY_INSTALLED]="Extensions already installed."
MSG_DE[$MSG_EXTENSIONS_ALREADY_INSTALLED]="Extensions sind bereits installiert."
MSG_SCRIPT_ALREADY_INSTALLED=$((SCNT++))
MSG_EN[$MSG_SCRIPT_ALREADY_INSTALLED]="$RASPIBACKUP_NAME already installed.${NL}Do you want to reinstall $RASPIBACKUP_NAME ?"
MSG_DE[$MSG_SCRIPT_ALREADY_INSTALLED]="$RASPIBACKUP_NAME ist bereits installiert.${NL}Soll die bestehende Installation überschrieben werden ?"
MSG_DOWNLOADING_PROPERTYFILE=$((SCNT++))
MSG_EN[$MSG_DOWNLOADING_PROPERTYFILE]="Downloading version information."
MSG_DE[$MSG_DOWNLOADING_PROPERTYFILE]="Versionsinformationen werden runtergeladen."
MSG_INVALID_KEEP=$((SCNT++))
MSG_EN[$MSG_INVALID_KEEP]="Invalid number '%1'. Number has to be between 1 and 52."
MSG_DE[$MSG_INVALID_KEEP]="Ungültige Zahl '%1'. Die Zahl muss zwischen 1 und 52 sein."
MSG_INVALID_TIME=$((SCNT++))
MSG_EN[$MSG_INVALID_TIME]="Invalid time '%1'. Input has to be in format hh:mm and 0<=hh<24 and 0<=mm<60."
MSG_DE[$MSG_INVALID_TIME]="Ungültige Zeit '%1'. Die Eingabe muss im Format hh:mm sein und 0<=hh<24 und 0<=mm<60."
MSG_RUNASROOT=$((SCNT++))
MSG_EN[$MSG_RUNASROOT]="$MYSELF has to be started as root. Try 'sudo %1%2'."
MSG_DE[$MSG_RUNASROOT]="$MYSELF muss als root gestartet werden. Benutze 'sudo %1%2'."

DESCRIPTION_INSTALLATION=$((SCNT++))
MSG_EN[$DESCRIPTION_INSTALLATION]="${NL}$RASPIBACKUP_NAME allows to plug in custom extensions which are called before and after the backup process. \
There exist sample extensions which report the memory usage, CPU temperature and disk usage of the backup partition. \
For details see${NL}https://www.linux-tips-and-tricks.de/en/raspibackupcategoryy/443-raspibackup-extensions."
MSG_DE[$DESCRIPTION_INSTALLATION]="${NL}$RASPIBACKUP_NAME erlaubt selbstgeschriebene Erweiterungen vor und nach dem Backupprozess aufzurufen. \
Es gibt Beispielerweiterungen die die Speicherauslastung, die CPU Temperatur sowie die Speicherplatzbenutzung der Backuppartition anzeigen. \
Für weitere Details siehe${NL}https://www.linux-tips-and-tricks.de/de/13-raspberry/442-raspibackup-erweiterungen."
DESCRIPTION_COMPRESS=$((SCNT++))
MSG_EN[$DESCRIPTION_COMPRESS]="${NL}$RASPIBACKUP_NAME can compress dd and tar backups to reduce the size of the backup. Please note this will increase backup time and will heaten the CPU. \
Please note an option of $FILE_TO_INSTALL which will reduce the size of a dd backup also. \
For details see https://www.linux-tips-and-tricks.de/en/faq#a16."
MSG_DE[$DESCRIPTION_COMPRESS]="${NL}$RASPIBACKUP_NAME kann dd und tar Backups kompressen um die Backupgröße zu reduzieren. Das bedeutet aber dass die Backupzeit steigt und die CPU erwärmen wird. \
$FILE_TO_INSTALL bietet auch eine Option an mit der ein dd Backup verkleinert werden kann. Siehe dazu \
https://www.linux-tips-and-tricks.de/de/faq#a16."
DESCRIPTION_CRON=$((SCNT++))
MSG_EN[$DESCRIPTION_CRON]="${NL}$RASPIBACKUP_NAME should be started on a regular base when the initial configuration and backup and restore testing was done. \
Configure the backup to be created daily or weekly. For other backup intervals you have to modify /etc/cron.d/raspiBackup manually."
MSG_DE[$DESCRIPTION_CRON]="${NL}$RASPIBACKUP_NAME sollte regelmäßig gestartet werden wenn die initiale Konfiguration sowie Backup und Restore Tests beendet sind. \
Konfiguriere den Backup täglich oder wöchentlich zu erstellen. Für andere Intervalle muss die Datei /etc/cron.d/raspiBackup manuell geändert werden."
DESCRIPTION_MESSAGEDETAIL=$((SCNT++))
MSG_EN[$DESCRIPTION_MESSAGEDETAIL]="${NL}$RASPIBACKUP_NAME can either be very verbose with messages or just write the most important. \
Usually it makes sense to turn it on when installing $RASPIBACKUP_NAME the first time to get additional messages which may help to isolate configuration issue. \
Later on turn it off."
MSG_DE[$DESCRIPTION_MESSAGEDETAIL]="${NL}$RASPIBACKUP_NAME kann ziemlich viele Meldungen schreiben oder einfach nur die Wichtigsten. \
Es macht Sinn sie beim ersten Installieren von $RASPIBACKUP_NAME anzuschalten um u.U. Hinweise auf mögliche Fehlkonfigurationen zu bekommen. \
Später können sie ausgeschaltet werden."
DESCRIPTION_STARTSTOP=$((SCNT++))
MSG_EN[$DESCRIPTION_STARTSTOP]="${NL}Before and after creating a backup important services should be stopped and started. Add the required services separated by a space which should be stopped in the correct order. \
The services will be started in reverse order when backup finished. For further details see https://www.linux-tips-and-tricks.de/en/faq#a18."
MSG_DE[$DESCRIPTION_STARTSTOP]="${NL}Vor und nach einem Backup sollten immer alle wichtigen Services gestoppt und gestartet werden. Dazu müssen die notwendigen Services die gestoppt werden sollen getrennt durch Leerzeichen in der richtigen Reihenfolge eingegeben werden. \
In umgekehrter Reihenfolge werden die Services nach dem Backup wieder gestartet. Weitere Details finden sich auf https://www.linux-tips-and-tricks.de/de/faq#a18."
DESCRIPTION_STARTSTOP_SEQUENCE=$((SCNT++))
MSG_EN[$DESCRIPTION_STARTSTOP_SEQUENCE]="${NL}Select step by step every service which should be stopped first, second, third and so on and confirm every single service with <Ok> until there is no service any more. \
Actual sequence is displayed top down. \
For further details see https://www.linux-tips-and-tricks.de/en/faq#a18."
MSG_DE[$DESCRIPTION_STARTSTOP_SEQUENCE]="${NL}Wähle der Reihe nach die Services aus wie sie vor dem Backup gestoppt werden sollen und bestätige jeden einzelnen Service mit <Bestätigen> bis keine Services mehr angezeigt werden. \
Die aktuelle Reihenfolge wird von oben nach unten angezeigt. \
Weitere Details finden sich auf https://www.linux-tips-and-tricks.de/de/faq#a18."
DESCRIPTION_STARTSTOP_SERVICES=$((SCNT++))
MSG_EN[$DESCRIPTION_STARTSTOP_SERVICES]="${NL}Select all services in sequence how they should be stopped before the backup starts. \
Current sequence is displayed.\
They will be started in reverse sequence again when the backup finished."
MSG_DE[$DESCRIPTION_STARTSTOP_SERVICES]="${NL}Wähle alle wichtigen Services aus die vor dem Backup gestoppt werden sollen. \
Sie werden wieder in umgekehrter Reihenfolge gestartet wenn der Backup beendet wurde."
DESCRIPTION_LANGUAGE=$((SCNT++))
MSG_EN[$DESCRIPTION_LANGUAGE]="${NL}$RASPIBACKUP_NAME und dieser Installer unterstützen Englisch und Deutsch. Standard ist die Systemsprache.${NL}\
${NL}$RASPIBACKUP_NAME and this installer support English and German. The default language is set by the system language."
MSG_DE[$DESCRIPTION_LANGUAGE]="${NL}$RASPIBACKUP_NAME and this installer support English and German. The default language is set by the system language.${NL}\
${NL}$RASPIBACKUP_NAME und dieser Installer unterstützen Englisch und Deutsch. Standard ist die Systemsprache."
DESCRIPTION_KEEP=$((SCNT++))
MSG_EN[$DESCRIPTION_KEEP]="${NL}This number defines how many backups will be kept on the backup partition. If more backups are created the oldest backups will be deleted."
MSG_DE[$DESCRIPTION_KEEP]="${NL}Diese Zahl bestimmt wie viele Backups auf der Backupartition gehalten werden. Sobald diese Zahl überschritten wird werden die ältesten Backups automatisch gelöscht."
DESCRIPTION_ERROR=$((SCNT++))
MSG_EN[$DESCRIPTION_ERROR]="Unrecoverable error occurred. Check logfile $LOG_FILE."
MSG_DE[$DESCRIPTION_ERROR]="Ein nicht behebbarer Fehler ist aufgetreten. Siehe Logdatei $LOG_FILE."
DESCRIPTION_BACKUPPATH=$((SCNT++))
MSG_EN[$DESCRIPTION_BACKUPPATH]="${NL}On the backup path a partition has to be be mounted which is used by $FILE_TO_INSTALL to store the backups. \
This can be a local partition or a mounted remote partition."
MSG_DE[$DESCRIPTION_BACKUPPATH]="${NL}Am Backuppfad muss eine Partition gemounted sein auf welcher $FILE_TO_INSTALL die Backups ablegt. \
Das kann eine lokale Partition oder eine remote gemountete Partition."
DESCRIPTION_BACKUPTYPE=$((SCNT++))
MSG_EN[$DESCRIPTION_BACKUPTYPE]="${NL}rsync is the suggested backuptype because when using hardlinks from EXT3/4 filesystem it's fast because only changed or new files will be saved. \
tar should be used if the backup filesystem is no EXT3/4, e.g a remote mounted samba share. Don't used a FAT32 filesystem because the maximum filesize is 4GB. \
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
DESCRIPTION_MAIL_PROGRAM=$((SCNT++))
MSG_EN[$DESCRIPTION_MAIL_PROGRAM]="Select the mail program to use to send notification eMails."
MSG_DE[$DESCRIPTION_MAIL_PROGRAM]="Wähle das Mailprogramm aus welches zum Versenden von Benachrichtigungen benutzt werden soll."
DESCRIPTION_EMAIL=$((SCNT++))
MSG_EN[$DESCRIPTION_EMAIL]="Enter the eMail address to send notifications to. Enter no eMail address to disable notifications."
MSG_DE[$DESCRIPTION_EMAIL]="Gibt die eMail Adresse ein die Benachrichtigungen erhalten soll. Keine eMail Adresse schaltet Benachrichtigungen aus."

TITLE_ERROR=$((SCNT++))
MSG_EN[$TITLE_ERROR]="Error"
MSG_DE[$TITLE_ERROR]="Fehler"
TITLE_FIRST_STEPS=$((SCNT++))
MSG_EN[$TITLE_FIRST_STEPS]="First steps"
MSG_DE[$TITLE_FIRST_STEPS]="Erste Schritte"
TITLE_HELP=$((SCNT++))
MSG_EN[$TITLE_HELP]="Help"
MSG_DE[$TITLE_HELP]="Hilfe"
TITLE_WARNING=$((SCNT++))
MSG_EN[$TITLE_WARNING]="Warning"
MSG_DE[$TITLE_WARNING]="Warnung"
TITLE_INFORMATION=$((SCNT++))
MSG_EN[$TITLE_INFORMATION]="Information"
MSG_DE[$TITLE_INFORMATION]="Information"
TITLE_VALIDATIONERROR=$((SCNT++))
MSG_EN[$TITLE_VALIDATIONERROR]="Invalid input"
MSG_DE[$TITLE_VALIDATIONERROR]="Ungültige Eingabe"
TITLE_CONFIRM=$((SCNT++))
MSG_EN[$TITLE_CONFIRM]="Please confirm"
MSG_DE[$TITLE_CONFIRM]="Bitte bestätigen"
MSG_INVALID_BACKUPPATH=$((SCNT++))
MSG_EN[$MSG_INVALID_BACKUPPATH]="Backup path %1 does not exist"
MSG_DE[$MSG_INVALID_BACKUPPATH]="Sicherungsverzeichnis %1 existiert nicht"
MSG_INVALID_EMAIL=$((SCNT++))
MSG_EN[$MSG_INVALID_EMAIL]="Invalid eMail address %1"
MSG_DE[$MSG_INVALID_EMAIL]="Ungültige eMail Adresse %1"
MSG_LOCAL_BACKUPPATH=$((SCNT++))
MSG_EN[$MSG_LOCAL_BACKUPPATH]="Backup would be stored on SD card"
MSG_DE[$MSG_LOCAL_BACKUPPATH]="Backup würde auf der SD Karte gespeichert werden"
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
MSG_ABOUT=$((SCNT++))
MSG_EN[$MSG_ABOUT]="$GIT_CODEVERSION${NL}${NL}\
This tool provides a straight-forward way of doing installation,${NL} updating and configuration of $RASPIBACKUP_NAME.${NL}${NL}\
Visit https://www.linux-tips-and-tricks.de/en/raspibackup#parameters${NL}for details about all configuration options of $RASPIBACKUP_NAME.${NL}${NL}\
Visit https://www.linux-tips-and-tricks.de/de/raspibackup${NL}for details about $RASPIBACKUP_NAME."
MSG_DE[$MSG_ABOUT]="$GIT_CODEVERSION${NL}${NL}\
Dieses Tool ermöglicht es möglichst einfach $RASPIBACKUP_NAME zu installieren,${NL} zu updaten und die Konfiguration anzupassen.${NL}${NL}\
Besuche https://www.linux-tips-and-tricks.de/de/raspibackup#parameter${NL}um alle Konfigurationsoptionen von $RASPIBACKUP_NAME kennenzulernen.${NL}${NL}\
Besuche https://www.linux-tips-and-tricks.de/en/backup${NL}um Weiteres zu $RASPIBACKUP_NAME zu erfahren."
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
MSG_HELP=$((SCNT++))
MSG_EN[$MSG_HELP]="In case you have any issue or question about $RASPIBACKUP_NAME just use one of the following pathes to get help${NL}
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

declare -A MENU_EN
declare -A MENU_DE

MCNT=0
MENU_UNDEFINED=$((MCNT++))
MENU_EN[$MENU_UNDEFINED]="Undefined menuid."
MENU_DE[$MENU_UNDEFINED]="Unbekannte menuid."
MENU_LANGUAGE=$((MCNT++))
MENU_EN[$MENU_LANGUAGE]='"M1" "Language/Sprache"'
MENU_DE[$MENU_LANGUAGE]='"M1" "Sprache/Language"'
MENU_INSTALL=$((MCNT++))
MENU_EN[$MENU_INSTALL]='"M2" "Install components"'
MENU_DE[$MENU_INSTALL]='"M2" "Installiere Komponenten"'
MENU_CONFIGURE=$((MCNT++))
MENU_EN[$MENU_CONFIGURE]='"M3" "Configure major options"'
MENU_DE[$MENU_CONFIGURE]='"M3" "Konfiguriere die wichtigsten Optionen"'
MENU_UNINSTALL=$((MCNT++))
MENU_EN[$MENU_UNINSTALL]='"M4" "Delete components"'
MENU_DE[$MENU_UNINSTALL]='"M4" "Lösche Komponenten"'
MENU_UPDATE=$((MCNT++))
MENU_EN[$MENU_UPDATE]='"M5" "Update components"'
MENU_DE[$MENU_UPDATE]='"M5" "Aktualisiere Komponenten"'
MENU_ABOUT=$((MCNT++))
MENU_EN[$MENU_ABOUT]='"M9" "About and useful links"'
MENU_DE[$MENU_ABOUT]='"M9" "About und hilfreiche Links"'
MENU_REGULARBACKUP_ENABLE=$((MCNT++))
MENU_EN[$MENU_REGULARBACKUP_ENABLE]='"R1" "Enable regular backup"'
MENU_DE[$MENU_REGULARBACKUP_ENABLE]='"R1" "Regelmäßiges Backup einschalten"'
MENU_REGULARBACKUP_DISABLE=$((MCNT++))
MENU_EN[$MENU_REGULARBACKUP_DISABLE]='"R1" "Disable regular backup"'
MENU_DE[$MENU_REGULARBACKUP_DISABLE]='"R1" "Regelmäßiges Backup auschalten"'
MENU_CONFIG_DAY=$((MCNT++))
MENU_EN[$MENU_CONFIG_DAY]='"R2" "Weekday of regular backup"'
MENU_DE[$MENU_CONFIG_DAY]='"R2" "Wochentag des regelmäßigen Backups"'
MENU_CONFIG_TIME=$((MCNT++))
MENU_EN[$MENU_CONFIG_TIME]='"R3" "Time of regular backup"'
MENU_DE[$MENU_CONFIG_TIME]='"R3" "Zeit des regelmäßigen Backups"'
MENU_CONFIG_LANGUAGE_EN=$((MCNT++))
MENU_EN[$MENU_CONFIG_LANGUAGE_EN]='"en" "English"'
MENU_DE[$MENU_CONFIG_LANGUAGE_EN]='"en" "Englisch"'
MENU_CONFIG_LANGUAGE_DE=$((MCNT++))
MENU_EN[$MENU_CONFIG_LANGUAGE_DE]='"de" "German"'
MENU_DE[$MENU_CONFIG_LANGUAGE_DE]='"de" "Deutsch"'
MENU_CONFIG_MESSAGE_N=$((MCNT++))
MENU_EN[$MENU_CONFIG_MESSAGE_N]='"Normal" "Display important messages only"'
MENU_DE[$MENU_CONFIG_MESSAGE_N]='"Normal" "Nur wichtige Meldungen anzeigen"'
MENU_CONFIG_MESSAGE_V=$((MCNT++))
MENU_EN[$MENU_CONFIG_MESSAGE_V]='"Verbose" "Display all messages"'
MENU_DE[$MENU_CONFIG_MESSAGE_V]='"Detailiert" "Alle Meldungen anzeigen"'
MENU_CONFIG_BACKUPPATH=$((MCNT++))
MENU_EN[$MENU_CONFIG_BACKUPPATH]='"C2" "Backup path for backups"'
MENU_DE[$MENU_CONFIG_BACKUPPATH]='"C2" "Verzeichnispfad für die Backups"'
MENU_CONFIG_BACKUPS=$((MCNT++))
MENU_EN[$MENU_CONFIG_BACKUPS]='"C3" "Number of backups to save"'
MENU_DE[$MENU_CONFIG_BACKUPS]='"C3" "Anzahl vorzuhaltender Backups"'
MENU_CONFIG_TYPE=$((MCNT++))
MENU_EN[$MENU_CONFIG_TYPE]='"C4" "Backup type"'
MENU_DE[$MENU_CONFIG_TYPE]='"C4" "Backup Typ"'
MENU_CONFIG_SERVICES=$((MCNT++))
MENU_EN[$MENU_CONFIG_SERVICES]='"C5" "Services to stop and start"'
MENU_DE[$MENU_CONFIG_SERVICES]='"C5" "Zu stoppende und startende Services"'
MENU_CONFIG_MESSAGE=$((MCNT++))
MENU_EN[$MENU_CONFIG_MESSAGE]='"C6" "Message verbosity"'
MENU_DE[$MENU_CONFIG_MESSAGE]='"C6" "Meldungsgenauigkeit"'
MENU_CONFIG_EMAIL=$((MCNT++))
MENU_EN[$MENU_CONFIG_EMAIL]='"C7" "eMail notification"'
MENU_DE[$MENU_CONFIG_EMAIL]='"C7" "eMail Benachrichtigung"'
MENU_CONFIG_CRON=$((MCNT++))
MENU_EN[$MENU_CONFIG_CRON]='"C8" "Regular backup"'
MENU_DE[$MENU_CONFIG_CRON]='"C8" "Regelmäßiges Backup"'
MENU_CONFIG_ZIP=$((MCNT++))
MENU_EN[$MENU_CONFIG_ZIP]='"C9" "Compression"'
MENU_DE[$MENU_CONFIG_ZIP]='"C9" "Komprimierung"'
MENU_CONFIG_ZIP_NA=$((MCNT++))
MENU_EN[$MENU_CONFIG_ZIP_NA]='" " " "'
MENU_DE[$MENU_CONFIG_ZIP_NA]='" " " "'
MENU_INSTALL_INSTALL=$((MCNT++))
MENU_EN[$MENU_INSTALL_INSTALL]='"I1" "Install $RASPIBACKUP_NAME using a default configuration"'
MENU_DE[$MENU_INSTALL_INSTALL]='"I1" "Installiere $RASPIBACKUP_NAME mit einer Standardkonfiguration"'
MENU_INSTALL_EXTENSIONS=$((MCNT++))
MENU_EN[$MENU_INSTALL_EXTENSIONS]='"I2" "Install and enable sample extension"'
MENU_DE[$MENU_INSTALL_EXTENSIONS]='"I2" "Installiere Beispielerweiterungen"'
MENU_CONFIG_MAIL_MAIL=$((MCNT++))
MENU_EN[$MENU_CONFIG_MAIL_MAIL]='"mail" ""'
MENU_DE[$MENU_CONFIG_MAIL_MAIL]='"mail" ""'
MENU_CONFIG_MAIL_SSMTP=$((MCNT++))
MENU_EN[$MENU_CONFIG_MAIL_SSMTP]='"ssmtp" ""'
MENU_DE[$MENU_CONFIG_MAIL_SSMTP]='"ssmtp" ""'
MENU_CONFIG_MAIL_MSMTP=$((MCNT++))
MENU_EN[$MENU_CONFIG_MAIL_MSMTP]='"msmtp" ""'
MENU_DE[$MENU_CONFIG_MAIL_MSMTP]='"msmtp" ""'
MENU_CONFIG_TYPE_DD=$((MCNT++))
MENU_EN[$MENU_CONFIG_TYPE_DD]='"dd" "Backup with dd and restore on Windows"'
MENU_DE[$MENU_CONFIG_TYPE_DD]='"dd" "Sichere mit dd und stelle unter Windows wieder her"'
MENU_CONFIG_TYPE_TAR=$((MCNT++))
MENU_EN[$MENU_CONFIG_TYPE_TAR]='"tar" "Backup with tar"'
MENU_DE[$MENU_CONFIG_TYPE_TAR]='"tar" "Sichere mit tar"'
MENU_CONFIG_TYPE_RSYNC=$((MCNT++))
MENU_EN[$MENU_CONFIG_TYPE_RSYNC]='"rsync" "Backup with rsync and use hardlinks if possible"'
MENU_DE[$MENU_CONFIG_TYPE_RSYNC]='"rsync" "Sichere mit rsync und benutze Hardlinks wenn möglich"'
MENU_UNINSTALL_UNINSTALL=$((MCNT++))
MENU_EN[$MENU_UNINSTALL_UNINSTALL]='"U1" "Uninstall $RASPIBACKUP_NAME"'
MENU_DE[$MENU_UNINSTALL_UNINSTALL]='"U1" "Lösche $RASPIBACKUP_NAME"'
MENU_UNINSTALL_EXTENSION=$((MCNT++))
MENU_EN[$MENU_UNINSTALL_EXTENSION]='"U2" "Uninstall and disable sample extensions"'
MENU_DE[$MENU_UNINSTALL_EXTENSION]='"U2" "Lösche Extensions"'
MENU_CONFIG_TYPE_DD_NA=$((MCNT++))
MENU_EN[$MENU_CONFIG_TYPE_DD_NA]='"" "Backup with dd not possible with this mode"'
MENU_DE[$MENU_CONFIG_TYPE_DD_NA]='"" "Sichern mit dd nicht möglich bei diesem Modus"'
MENU_CONFIG_COMPRESS_OFF=$((MCNT++))
MENU_EN[$MENU_CONFIG_COMPRESS_OFF]='"off" "No backup compression"'
MENU_DE[$MENU_CONFIG_COMPRESS_OFF]='"aus" "Keine Backup Komprimierung"'
MENU_CONFIG_COMPRESS_ON=$((MCNT++))
MENU_EN[$MENU_CONFIG_COMPRESS_ON]='"on" "Compress $CONFIG_BACKUPTYPE backup"'
MENU_DE[$MENU_CONFIG_COMPRESS_ON]='"an" "Komprimiere den $CONFIG_BACKUPTYPE Backup"'
MENU_DAYS_SHORT=$((MCNT++))
MENU_EN[$MENU_DAYS_SHORT]='"Daily" "Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat"'
MENU_DE[$MENU_DAYS_SHORT]='"Täglich" "So" "Mo" "Di" "Mi" "Do" "Fr" "Sa"'
MENU_DAYS_LONG=$((MCNT++))
MENU_EN[$MENU_DAYS_LONG]='"Daily" "Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday"'
MENU_DE[$MENU_DAYS_LONG]=' "Täglich" "Sonntag" "Montag" "Dienstag" "Mittwoch" "Donnerstag" "Freitag" "Samstag"'
MENU_UPDATE_SCRIPT=$((MCNT++))
MENU_EN[$MENU_UPDATE_SCRIPT]='"P1" "Update $FILE_TO_INSTALL"'
MENU_DE[$MENU_UPDATE_SCRIPT]='"P1" "Aktualisiere $FILE_TO_INSTALL"'
MENU_UPDATE_INSTALLER=$((MCNT++))
MENU_EN[$MENU_UPDATE_INSTALLER]='"P2" "Update $MYSELF"'
MENU_DE[$MENU_UPDATE_INSTALLER]='"P2" "Aktualisiere $MYSELF"'

declare -A MSG_HEADER=(['I']="---" ['W']="!!!" ['E']="???")

INSTALLATION_SUCCESSFULL=0
INSTALLATION_STARTED=0
CONFIG_INSTALLED=0
SCRIPT_INSTALLED=0
EXTENSIONS_INSTALLED=0
CRON_INSTALLED=0
PROGRESSBAR_DO=0

INSTALL_EXTENSIONS=0
BETA_INSTALL=0
CRONTAB_ENABLED="undefined"

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

	local msg
	local p
	local i
	local s

	msgVar="MSG_${CONFIG_LANGUAGE}"

	if [[ -n ${!msgVar} ]]; then
		msgVar="$msgVar[$1]"
		msg=${!msgVar}
		if [[ -z $msg ]]; then # no translation found
			msgVar="$1"
			if [[ -z ${!msgVar} ]]; then
				echo "${MSG_EN[$MSG_UNDEFINED]}" # unknown message id
				logStack
				logExit "$1"
				return
			else
				msg="${MSG_EN[$1]}" # fallback into english
			fi
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

	if [[ -n ${!menuVar} ]]; then
		menuVar="$menuVar[$1]"
		menu="${!menuVar}"
		if [[ -z $menu ]]; then # no translation found
			menuVar="$1"
			if [[ -z ${!menuVar} ]]; then
				echo "${MENU_EN[$MENU_UNDEFINED]}" # unknown menu id
				logStack
				logExit
				return
			else
				menu="${MENU_EN[$1]}" # fallback into english
			fi
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

function isInternetAvailable() {

	logEntry

	wget -q --spider $MYHOMEDOMAIN
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

function isCrontabEnabled() {
	logEntry $CRONTAB_ENABLED
	if [[ "$CRONTAB_ENABLED" == "undefined" ]]; then
		if isCrontabInstalled; then
			local l="$(tail -n 1 < $CRON_ABS_FILE)"
			logItem "$l"
			[[ ${l:0:1} != "#" ]]
			CRONTAB_ENABLED=$?
		else
			CRONTAB_ENABLED=1
		fi
	fi
	logExit $CRONTAB_ENABLED
	return $CRONTAB_ENABLED
}

function isCrontabInstalled() {
	[[ -f $CRON_ABS_FILE ]]
	return
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

	httpCode=$(curl -s -o "/tmp/$FILE_TO_INSTALL" -m $DOWNLOAD_TIMEOUT -w %{http_code} -L "$MYHOMEURL/$FILE_TO_INSTALL" 2>>"$LOG_FILE")
	local rc=$?
	if (( $rc )); then
		unrecoverableError $MSG_NO_INTERNET_CONNECTION_FOUND "$rc"
		logExit
		return
	fi
	if [[ ${httpCode:0:1} != "2" ]]; then
		unrecoverableError $MSG_DOWNLOAD_FAILED "$FILE_TO_INSTALL" "$httpCode"
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

	httpCode=$(curl -s -o "/tmp/$FILE_TO_INSTALL" -m $DOWNLOAD_TIMEOUT -w %{http_code} -L "$MYHOMEURL/$FILE_TO_INSTALL" 2>>"$LOG_FILE")
	if [[ ${httpCode:0:1} != "2" ]]; then
		unrecoverableError $MSG_DOWNLOAD_FAILED "$FILE_TO_INSTALL" "$httpCode"
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

function update_installer_execute() {

	logEntry

	local newName

	httpCode=$(curl -s -o "/tmp/$MYSELF" -m $DOWNLOAD_TIMEOUT -w %{http_code} -L "$MYHOMEURL/$INSTALLER_DOWNLOAD_URL" 2>>"$LOG_FILE")
	if [[ ${httpCode:0:1} != "2" ]]; then
		unrecoverableError $MSG_DOWNLOAD_FAILED "$MYSELF" "$httpCode"
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

	logItem "Downloading $confFile"

	httpCode=$(curl -s -o $CONFIG_ABS_FILE -m $DOWNLOAD_TIMEOUT -w %{http_code} -L "$MYHOMEURL/$confFile" 2>>$LOG_FILE)
	if [[ ${httpCode:0:1} != "2" ]]; then
		unrecoverableError $MSG_DOWNLOAD_FAILED "$confFile" "$httpCode"
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

	httpCode=$(curl -s -o $SAMPLEEXTENSION_TAR_FILE -m $DOWNLOAD_TIMEOUT -w %{http_code} -L "$MYHOMEURL/$SAMPLEEXTENSION_TAR_FILE" 2>>$LOG_FILE)
	if [[ ${httpCode:0:1} != "2" ]]; then
		unrecoverableError $MSG_DOWNLOAD_FAILED "$SAMPLEEXTENSION_TAR_FILE" "$httpCode"
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
	local as=""
	IFS=" "
	while read s r; do
		if [[ $s == *".service" ]]; then
			if [[ $s != "systemd"* ]]; then
				as+=" $(sed 's/.service//' <<< "$s")"
			fi
		fi
	done < <(systemctl list-units --type=service --state=active | grep -v "@")
	echo "$as"
	logExit "$as"
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
	IFS="" matches=$(grep -E "MSG_LEVEL|KEEPBACKUPS|BACKUPPATH|BACKUPTYPE|ZIP_BACKUP|PARTITIONBASED_BACKUP|LANGUAGE|STARTSERVICES|STOPSERVICES|EMAIL|MAIL_PROGRAM" "$CONFIG_ABS_FILE")
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
	done <<< "$matches"
	logExit
}

function config_update_execute() {

	logEntry

	writeToConsole $MSG_UPDATING_CONFIG "$CONFIG_ABS_FILE"

	logItem "Language: $CONFIG_LANGUAGE"
	logItem "Type: $CONFIG_BACKUPTYPE"
	logItem "Zip: $CONFIG_ZIP_BACKUP"
	logItem "Keep: $CONFIG_KEEPBACKUPS"
	logItem "Msglevel: $CONFIG_MSG_LEVEL"
	logItem "Backuppath: $CONFIG_BACKUPPATH"
	logItem "Stop: $CONFIG_STOPSERVICES"
	logItem "Start: $CONFIG_STARTSERVICES"
	logItem "eMail: $CONFIG_EMAIL"
	logItem "mailProgram: $CONFIG_MAIL_PROGRAM"

	sed -i -E "s/^(#?\s?)?DEFAULT_LANGUAGE=.*\$/DEFAULT_LANGUAGE=\"$CONFIG_LANGUAGE\"/" "$CONFIG_ABS_FILE"
	sed -i -E "s/^(#?\s?)?DEFAULT_BACKUPTYPE=.*\$/DEFAULT_BACKUPTYPE=\"$CONFIG_BACKUPTYPE\"/" "$CONFIG_ABS_FILE"
	sed -i -E "s/^(#?\s?)?DEFAULT_ZIP_BACKUP=.*\$/DEFAULT_ZIP_BACKUP=\"$CONFIG_ZIP_BACKUP\"/" "$CONFIG_ABS_FILE"
	sed -i -E "s/^(#?\s?)?DEFAULT_KEEPBACKUPS=.*$/DEFAULT_KEEPBACKUPS=\"$CONFIG_KEEPBACKUPS\"/" "$CONFIG_ABS_FILE"
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
	local cron_day=$(( $CONFIG_CRON_DAY - 1 ))
	(( $cron_day < 0 )) && cron_day="*"
	local v=$(awk -v disabled=$disabled -v minute=$CONFIG_CRON_MINUTE -v hour=$CONFIG_CRON_HOUR -v day=$cron_day ' {print disabled minute, hour, $3, $4, day, $6, $7, $8}' <<< "$l")
	logItem "cron update: $v"
	local t=$(mktemp)
	head -n -1 "$CRON_ABS_FILE" > $t
	echo "$v" >> $t
	mv $t $CRON_ABS_FILE
	rm $t 2>/dev/null

	logExit
}

function cron_activate_execute() {

	logEntry

	local l="$(tail -n 1 < $CRON_ABS_FILE)"
	local disabled
	if isCrontabEnabled; then
		disabled=""
		logItem "Enabled cron"
	else
		disabled="#"
		logItem "Disabled cron"
	fi
	local cron_day=$(( $CONFIG_CRON_DAY - 1 ))
	(( $cron_day < 0 )) && cron_day="*"
	local v=$(awk -v disabled=$disabled -v minute=$CONFIG_CRON_MINUTE -v hour=$CONFIG_CRON_HOUR -v day=$cron_day ' {print disabled minute, hour, $3, $4, day, $6, $7, $8}' <<< "$l")
	local t=$(mktemp)
	head -n -1 "$CRON_ABS_FILE" > $t
	echo "$v" >> $t
	mv $t $CRON_ABS_FILE
	rm $t 2>/dev/null
	logExit
}

function cron_install_execute() {

	logEntry

	writeToConsole $MSG_INSTALLING_CRON_TEMPLATE "$CRON_ABS_FILE"
	echo "$CRON_CONTENTS" >"$CRON_ABS_FILE"
	CRON_INSTALLED=1
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

function about_do() {

	logEntry
	local a="$(getMessageText $MSG_ABOUT)"
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
	fi

	help

	reset

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
			(($EXTENSIONS_INSTALLED)) && rm -f $FILE_TO_INSTALL_ABS_PATH/${RASPIBACKUP_NAME}_*.sh &>>"$LOG_FILE" || true
		fi
	fi

	(($EXTENSIONS_INSTALLED)) && rm $SAMPLEEXTENSION_TAR_FILE &>>$LOG_FILE || true

	if [[ "$signal" == "EXIT" ]]; then
		(( ! $RASPIBACKUP_INSTALL_DEBUG )) && rm -f $LOG_FILE &>/dev/null
	else
		writeToConsole $MSG_INSTALLATION_FAILED "$RASPIBACKUP_NAME" "$LOG_FILE"
		logExit
		rc=127
	fi

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
	CRON_UPDATED=0

	if isConfigInstalled; then
		parseConfig
	fi

	if isCrontabInstalled; then
		local l="$(tail -n 1 < $CRON_ABS_FILE)"
		logItem "last line: $l"
		local v=$(awk ' {print $1, $2, $5}' <<< "$l")
		logItem "parsed $v"
		CONFIG_CRON_MINUTE="$(cut -f 1 -d ' ' <<< $v)"
		[[ ${CONFIG_CRON_MINUTE:0:1} == "#" ]] && CONFIG_CRON_MINUTE="${CONFIG_CRON_MINUTE:1}"
		CONFIG_CRON_HOUR="$(cut -f 2 -d ' ' <<< $v)"
		CONFIG_CRON_DAY=$(cut -f 3 -d ' ' <<< $v)
		[[ "$CONFIG_CRON_DAY" == "*" ]] && CONFIG_CRON_DAY=0 || (( CONFIG_CRON_DAY ++ )) # 0 = Daily, 1 = Sun, 2 = Mon, ...
		logItem "parsed hour: $CONFIG_CRON_HOUR"
		logItem "parsed minute: $CONFIG_CRON_MINUTE"
		logItem "parsed day: $CONFIG_CRON_DAY"
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
		getMenuText $MENU_CONFIG_SERVICES m6
		getMenuText $MENU_CONFIG_MESSAGE m7
		getMenuText $MENU_CONFIG_EMAIL m8
		getMenuText $MENU_CONFIG_CRON m9

		local p="${m1[0]}"
		m1[0]="C${p:1}"

		if [[ $CONFIG_BACKUPTYPE == "dd" || $CONFIG_BACKUPTYPE == "tar" ]]; then
			getMenuText $MENU_CONFIG_ZIP mcp
			local scp="${mcp[0]}"
		else
			mcp=(" " " ")
			local scp=""
		fi

		local s1="${m1[0]}"
		local s2="${m2[0]}"
		local s3="${m3[0]}"
		local s4="${m4[0]}"
		local s6="${m6[0]}"
		local s7="${m7[0]}"
		local s8="${m8[0]}"
		local s9="${m9[0]}"

		getMenuText $MENU_CONFIGURE tt

		FUN=$(whiptail --title "${tt[1]}" --menu "" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button "$b1" --ok-button "$sel1" \
			"${m1[@]}" \
			"${m2[@]}" \
			"${m3[@]}" \
			"${m4[@]}" \
			"${m6[@]}" \
			"${m7[@]}" \
			"${m8[@]}" \
			"${m9[@]}" \
			"${mcp[@]}" \
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
			if (($CRON_UPDATED)); then
				local m="$(getMessageText $MSG_QUESTION_UPDATE_CRON)"
				local t=$(center $WINDOW_COLS "$m")
				local ttm="$(getMessageText $TITLE_CONFIRM)"
				if whiptail --yesno "$t" --title "$ttm" --yes-button "$y" --no-button "$n" --defaultno $ROWS_MSGBOX $WINDOW_COLS 1 3>&1 1>&2 2>&3; then
					cron_update_do
				fi
			fi
			logExit
			return 0
		elif [ $RET -eq 0 ]; then
			logItem "$FUN"
			case "$FUN" in
				$s1) config_language_do; CONFIG_UPDATED=$(( CONFIG_UPDATED|$? )) ;;
				$s2) config_backuppath_do; CONFIG_UPDATED=$(( CONFIG_UPDATED|$? )) ;;
				$s3) config_keep_do; CONFIG_UPDATED=$(( CONFIG_UPDATED|$? )) ;;
				$s4) config_backuptype_do; CONFIG_UPDATED=$(( CONFIG_UPDATED|$? )) ;;
				$s6) config_services_do; CONFIG_UPDATED=$(( CONFIG_UPDATED|$? )) ;;
				$s7) config_message_detail_do; CONFIG_UPDATED=$(( CONFIG_UPDATED|$? )) ;;
				$s8) config_email_do; CONFIG_UPDATED=$(( CONFIG_UPDATED|$? )) ;;
				$s9) cron_menu; CRON_UPDATED=$? ;;
				$scp) config_compress_do; CONFIG_UPDATED=$(( CONFIG_UPDATED|$? )) ;;
				\ *) : ;;
				*) whiptail --msgbox "Programm error: unrecognized option $FUN" $ROWS_MENU $WINDOW_COLS 1 ;;
			esac || whiptail --msgbox "There was an error running option $FUN" $ROWS_MENU $WINDOW_COLS 1
		fi
	done
	logExit

}

function config_keep_do() {

	logEntry

	local current="$CONFIG_KEEPBACKUPS"
	local old="$current"

	while :; do

		getMenuText $MENU_CONFIG_BACKUPS tt
		local c1="$(getMessageText $BUTTON_CANCEL)"
		local o1="$(getMessageText $BUTTON_OK)"
		local d="$(getMessageText $DESCRIPTION_KEEP)"

		ANSWER=$(whiptail --inputbox "$d" --title "${tt[1]}" $ROWS_MENU $WINDOW_COLS "$current" --ok-button "$o1" --cancel-button "$c1" 3>&1 1>&2 2>&3)
		if [ $? -eq 0 ]; then
			logItem "Answer: $ANSWER"
			current="$ANSWER"
			if [[ ! "$ANSWER" =~ ^[0-9]+$ ]] || (( "$ANSWER" >  52 )); then
				local m="$(getMessageText $MSG_INVALID_KEEP "$ANSWER")"
				local t=$(center $WINDOW_COLS "$m")
				local ttm="$(getMessageText $TITLE_VALIDATIONERROR)"
				whiptail --msgbox "$t" --title "$ttm" $ROWS_MENU $WINDOW_COLS 2
			else
				CONFIG_KEEPBACKUPS="$ANSWER"
				break
			fi
		else
			break
		fi
	done

	logExit "$CONFIG_KEEPBACKUPS"

	[[ "$old" == "$CONFIG_KEEPBACKUPS" ]]
	return

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

	logExit "$CONFIG_BACKUPPATH"

	[[ "$old" == "$CONFIG_BACKUPPATH" ]]
	return

}

function config_crontime_do() {

	local old=$(printf "%02d:%02d" $CONFIG_CRON_HOUR $CONFIG_CRON_MINUTE)
	current="$old"

	logEntry "$old"

	local b1="$(getMessageText $SELECT_TIME)"
	local c1="$(getMessageText $BUTTON_CANCEL)"
	local o1="$(getMessageText $BUTTON_OK)"
	getMenuText $MENU_CONFIG_TIME tt

	while :; do
		ANSWER=$(whiptail --inputbox "$b" --title "${tt[1]}" $ROWS_MENU $WINDOW_COLS --ok-button "$o1" --cancel-button "$c1" "$current" 3>&1 1>&2 2>&3)
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
				if (( CONFIG_CRON_HOUR > 23 || CONFIG_CRON_MINUTE > 59 )); then
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

	logExit "$CONFIG_CRON_HOUR:$CONFIG_CRON_MINUTE"

	[[ "$old" == "$CONFIG_CRON_HOUR:$CONFIG_CRON_MINUTE" ]]
	return

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

# borrowed from http://stackoverflow.com/questions/3685970/check-if-an-array-contains-a-value

function containsElement () {
  local e
  for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
  return 1
}

function config_services_do() {

	local current="$CONFIG_STOPSERVICES"
	local old="$current"

	logEntry "$current"

	wtv=$(whiptail -v | cut -d " " -f 3)

	IFS=" "
	local as=($(getActiveServices))
	local state

	getMenuText $MENU_CONFIG_SERVICES tt

	[[ "$current" == "$IGNORE_START_STOP_CHAR" ]] && current=""
	local c=( $current )
	local cl=()

	# insert selected services in front of list
	for s in ${c[@]}; do
		state="on"
		if [[ "$wtv" < "0.52.19" ]]; then	# workaround for whiptail issue in 0.52.19
			cl+=("$s" "" "$state")
		else
			cl+=("$s" "$s" "$state")
		fi
	done

	# add other active services in list
	for s in ${as[@]}; do
		if containsElement "$s" "${c[@]}"; then
			continue
		fi
		state="off"
		if [[ "$wtv" < "0.52.19" ]]; then	# workaround for whiptail issue in 0.52.19
			cl+=("$s" "" "$state")
		else
			cl+=("$s" "$s" "$state")
		fi
	done

	local d="$(getMessageText $DESCRIPTION_STARTSTOP_SERVICES)"
	local c1="$(getMessageText $BUTTON_CANCEL)"
	local o1="$(getMessageText $BUTTON_OK)"

	ANSWER=$(whiptail --notags --checklist "$d" --title "${tt[1]}" --ok-button "$o1" --cancel-button "$c1" $WT_HEIGHT $(($WT_WIDTH/2)) 7 \
		"${cl[@]}" \
		3>&1 1>&2 2>&3)
	if [ $? -eq 0 ]; then
		logItem "Answer: $ANSWER"
		local current=${ANSWER//\"}
		CONFIG_STOPSERVICES="$current"
		if [[ -n $CONFIG_STOPSERVICES ]]; then
			config_service_sequence_do
			[ $? -ne 0 ] &&	CONFIG_STOPSERVICES="$old"
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
				tl+=("$i: $t" "" "on")
			else
				tl+=("$i: $t" "$i: $t" "on")
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

function config_cronday_do() {

	local old="$CONFIG_CRON_DAY"

	logEntry "$old"

	local days_=(off off off off off off off off)

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
		CONFIG_CRON_DAY=$(cut -d/ -f1 <<< ${s[@]/$ANSWER//} | wc -w | tr -d ' ')
	fi

	logExit "$CONFIG_CRON_DAY"

	[[ "$old" == "$CONFIG_CRON_DAY" ]]
	return
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

	logExit "$CONFIG_ZIP_BACKUP"

	[[ "$old" == "$CONFIG_ZIP_BACKUP" ]]
	return

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
	local step=$((100 / (num_todo - 1)))
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

	UNINSTALL_DESCRIPTION=("Deleting $RASPIBACKUP_NAME extensions ..." "Deleting $RASPIBACKUP_NAME cron configuration ..." "Deleting $RASPIBACKUP_NAME configurations ..."  "Deleting misc files ..." "Deleting $FILE_TO_INSTALL ..." "Deleting $RASPIBACKUP_NAME installer ...")
	progressbar_do "UNINSTALL_DESCRIPTION" "Uninstalling $RASPIBACKUP_NAME" extensions_uninstall_execute cron_uninstall_execute config_uninstall_execute misc_uninstall_execute uninstall_script_execute uninstall_execute

	logExit

}

function cron_menu() {

	logEntry

	if ! isCrontabInstalled; then
		local m="$(getMessageText $MSG_CRON_NOT_INSTALLED)"
		local t=$(center $WINDOW_COLS "$m")
		local tt="$(getMessageText $TITLE_INFORMATION)"
		whiptail --msgbox "$t" --title "$tt" $ROWS_MSGBOX $WINDOW_COLS 2
		logExit
		return 1
	fi

	local toggled=0
	local cron_updated=0

	while :; do

		local b1="$(getMessageText $BUTTON_BACK)"
		local o1="$(getMessageText $BUTTON_SELECT)"
		local m="$(getMessageText $MSG_CRON_NA)"
		local t=$(center $WINDOW_COLS "$m")
		local d="$(getMessageText $DESCRIPTION_CRON)"

		getMenuText $MENU_REGULARBACKUP_ENABLE ct
		getMenuText $MENU_CONFIG_DAY m1
		getMenuText $MENU_CONFIG_TIME m2
		getMenuText $MENU_CONFIG_CRON tt

		if isCrontabEnabled; then
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
			local r=$((toggled|cron_updated))
			logExit $r
			return $r
		elif [ $RET -eq 0 ]; then
			logItem "$FUN"
			case "$FUN" in
				$s1) config_cronday_do; cron_updated=$(( cron_updated|$? )) ;;
				$s2) config_crontime_do; cron_updated=$(( cron_updated|$? )) ;;
				$ct) CRONTAB_ENABLED=$((!$CRONTAB_ENABLED)); toggled=$((!toggled)) ;;
				\ *) whiptail --msgbox "$t" $ROWS_MENU $WINDOW_COLS 1 ;;
				*) whiptail --msgbox "Programm error: unrecognized option $FUN" $ROWS_MENU $WINDOW_COLS 1 ;;
			esac || whiptail --msgbox "There was an error running option $FUN" $ROWS_MENU $WINDOW_COLS 1
		fi
	done

	logExit $CRONTAB_ENABLED

	return $$CRONTAB_ENABLED

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
	INSTALL_DESCRIPTION=("Downloading $FILE_TO_INSTALL ..." "Downloading $RASPIBACKUP_NAME configuration template ..." "Creating default $RASPIBACKUP_NAME configuration ..." "Installing $RASPIBACKUP_NAME cron config ...")
	progressbar_do "INSTALL_DESCRIPTION" "Installing $RASPIBACKUP_NAME" code_download_execute config_download_execute config_update_execute cron_install_execute
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

function cron_update_do() {

	logEntry

	if ! isCrontabInstalled; then
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

function cron_activate_do() {

	logEntry

	if ! isCrontabInstalled; then
		local m="$(getMessageText $MSG_CRON_NOT_INSTALLED)"
		local t=$(center $WINDOW_COLS "$m")
		local tt="$(getMessageText $TITLE_INFORMATION)"
		whiptail --msgbox "$t" --title "$tt" $ROWS_MSGBOX $WINDOW_COLS 2
		logExit
		return 1
	fi

	if isCrontabEnabled; then
		UPDATE_DESCRIPTION=("Enabling $RASPIBACKUP_NAME regular backup ...")
	else
		UPDATE_DESCRIPTION=("Disabling $RASPIBACKUP_NAME regular backup ...")
	fi

	progressbar_do "UPDATE_DESCRIPTION" "Updating cron configuration" cron_activate_execute
	logExit

	return 0

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

	logExit "$CONFIG_MSG_LEVEL"

	[[ "$old" == "$CONFIG_MSG_LEVEL" ]]
	return

}

function config_language_do() {

	local old="$CONFIG_LANGUAGE"

	logEntry "$old"

	local en_=off
	local de_=off

	[[ -z "$CONFIG_LANGUAGE" ]] && CONFIG_LANGUAGE="$MESSAGE_LANGUAGE"

	case "$CONFIG_LANGUAGE" in
		DE) de_=on ;;
		EN) en_=on ;;
		*)
			whiptail --msgbox "Programm error, unrecognized language $CONFIG_LANGUAGE" $ROWS_MENU $WINDOW_COLS 2
			logExit
			return 1
			;;
	esac

	getMenuText $MENU_CONFIG_LANGUAGE_EN m1
	getMenuText $MENU_CONFIG_LANGUAGE_DE m2

	local s1="${m1[0]}"
	local s2="${m2[0]}"

	getMenuText $MENU_LANGUAGE tt
	local o1="$(getMessageText $BUTTON_OK)"
	local c1="$(getMessageText $BUTTON_CANCEL)"
	local d="$(getMessageText $DESCRIPTION_LANGUAGE)"

	ANSWER=$(whiptail --notags --radiolist "$d" --title "${tt[1]}" --ok-button "$o1" --cancel-button "$c1" $ROWS_MENU $WINDOW_COLS 2 \
		"${m1[@]}" $en_ \
		"${m2[@]}" $de_ \
		3>&1 1>&2 2>&3)
	if [ $? -eq 0 ]; then
		logItem "Answer: $ANSWER"
		case "$ANSWER" in
		$s1) CONFIG_LANGUAGE="EN" ;;
		$s2) CONFIG_LANGUAGE="DE" ;;
		*)	whiptail --msgbox "Programm error, unrecognized language $ANSWER" $ROWS_MENU $WINDOW_COLS 2
			logExit
			return 1
			;;
		esac
	fi

	logExit "$CONFIG_LANGUAGE"

	[[ "$old" == "$CONFIG_LANGUAGE" ]]
	return

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

	writeToConsole $MSG_LEVEL_MINIMAL $MSG_DOWNLOADING_PROPERTYFILE
	wget $PROPERTY_URL -q --tries=$DOWNLOAD_RETRIES --timeout=$DOWNLOAD_TIMEOUT -O $LATEST_TEMP_PROPERTY_FILE
	local rc=$?
	if [[ $rc == 0 ]]; then
		logItem "Download of $downloadURL successfull"
		NEW_PROPERTIES_FILE=1
	else
		logItem "Download of $downloadURL failed with rc $rc"
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

	while true; do

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

		if ! isRaspiBackupInstalled; then
			m3=(" " " ")
			m4=(" " " ")
		fi

		if ! isUpdatePossible; then
			m5[0]=" "
			m5[1]=" "
		fi

		TITLE="$(getMessageText $MSG_TITLE)"
		FUN=$(whiptail --title "$TITLE" --menu "" $WT_HEIGHT $WT_WIDTH $((WT_MENU_HEIGHT-3)) --cancel-button "$f1" --ok-button "$sel1"\
			"${m1[@]}" \
			"${m2[@]}" \
			"${m3[@]}" \
			"${m4[@]}" \
			"${m5[@]}" \
			"${m9[@]}" \
			3>&1 1>&2 2>&3)
		RET=$?
		if [ $RET -eq 1 ]; then
			do_finish
		elif [ $RET -eq 0 ]; then
			logItem "$FUN"
			case "$FUN" in
				$s1) config_language_do
					if (( $? )); then
						if isConfigInstalled; then
							config_update_do
							parseConfig
						fi
					fi ;;
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
		code_download_execute
		config_download_execute
		config_update_execute
		if (( MODE_EXTENSIONS )); then
			extensions_install_execute
		fi
	elif (( MODE_UPDATE )); then
		update_installer_execute
	elif (( MODE_EXTENSIONS )); then
		extensions_install_execute
	else # uninstall
		extensions_uninstall_execute
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
	echo "$MYSELF ( -i [-e]? | -u | -U ) [-d]? "
	echo "-d: enable debug mode"
	echo "-e: unattended (re)install of $RASPIBACKUP_NAME extensions"
	echo "-i: unattended (re)install of $RASPIBACKUP_NAME"
	echo "-U: unattended update of $MYSELF"
	echo "-u: unattended uninstall of $RASPIBACKUP_NAME"
}

INVOCATIONPARMS=""			# save passed opts for logging
invocationParms=()			# and restart
for (( i=1; i<=$#; i++ )); do
	p=${!i}
	INVOCATIONPARMS="$INVOCATIONPARMS $p"
done

CLEANUP_LOG=0

MODE_UNATTENDED=0
# MODE_UNINSTALL=0 is default
MODE_INSTALL=0
MODE_UPDATE=0 # force install
MODE_EXTENSIONS=0

while getopts "dh?uUei" opt; do
    case "$opt" in
	 d) RASPIBACKUP_INSTALL_DEBUG=1
		 ;;
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
logItem "whiptail version: $(whiptail -v)"

checkRequiredDirectories

if (( $MODE_UNATTENDED )); then
	unattendedInstall
else
	uiInstall
fi
