#!/bin/bash

# Simple script to download, install and configure and uninstall raspiBackup.sh
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for details
#
# (C) 2015-2017 - framp at linux-tips-and-tricks dot de

# set -o pipefail -o nounset -o errexit

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}
VERSION="0.3.6"

MYHOMEURL="https://www.linux-tips-and-tricks.de"

MYDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

set +u; GIT_DATE="$Date: 2017-08-27 20:19:43 +0200$"; set -u
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<< $GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<< $GIT_DATE) 
set +u; GIT_COMMIT="$Sha1: 04bb3d9$"; set -u
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<< $GIT_COMMIT | sed 's/\$//')

GIT_CODEVERSION="$MYSELF $VERSION, $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"

FILE_TO_INSTALL="raspiBackup.sh"

RASPIBACKUP_NAME=${FILE_TO_INSTALL%.*}

FILE_TO_INSTALL_BETA="raspiBackup_beta.sh"
LOG_FILE="./$MYNAME.log"
URL="www.linux-tips-and-tricks.de"
declare -A CONFIG_DOWNLOAD_FILE=( ['DE']="raspiBackup_de.conf" ['EN']="raspiBackup_en.conf" )
CONFIG_FILE="raspiBackup.conf"
CONFIG_FILE_ABS_PATH="/usr/local/etc"
CONFIG_FILE_ABS_FILE="$CONFIG_FILE_ABS_PATH/$CONFIG_FILE"
FILE_TO_INSTALL_ABS_PATH="/usr/local/bin"
FILE_TO_INSTALL_ABS_FILE="$FILE_TO_INSTALL_ABS_PATH/$FILE_TO_INSTALL"
SAMPLEEXTENSION_TAR_FILE="raspiBackupSampleExtensions.tgz"

TAIL=0

PROPERTY_URL="/downloads/raspibackup0613-properties/download"
BETA_CODE_URL="/downloads/$FILE_TO_INSTALL_BETA/download"
STABLE_CODE_URL="$FILE_TO_INSTALL"

DOWNLOAD_TIMEOUT=3 # seconds
DOWNLOAD_RETRIES=3 

LANG_EXT=${LANG^^*}
[[ -z $LANG_EXT ]] && LANG_EXT="EN"
MESSAGE_LANGUAGE=${LANG_EXT:0:2}
if [[ $MESSAGE_LANGUAGE != "DE" && $MESSAGE_LANGUAGE != "EN" ]]; then
	MESSAGE_LANGUAGE="EN"
fi	

NL=$'\n'

MSG_EN=1      # english	(default)
MSG_DE=1      # german

MSG_PRF="RBI"

declare -A MSG_EN
declare -A MSG_DE

YES="y|j|Y|J"
NO="n|N"

MSG_UNDEFINED=0
MSG_EN[$MSG_UNDEFINED]="${MSG_PRF}0000E: Undefined messageid."
MSG_DE[$MSG_UNDEFINED]="${MSG_PRF}0000E: Unbekannte Meldungsid."
MSG_VERSION=1
MSG_EN[$MSG_VERSION]="${MSG_PRF}0001I: %1"
MSG_DE[$MSG_VERSION]="${MSG_PRF}0001I: %1"
MSG_ASK_LANGUAGE=2
MSG_EN[$MSG_ASK_LANGUAGE]="${MSG_PRF}0002I: Message language (%1)"
MSG_DE[$MSG_ASK_LANGUAGE]="${MSG_PRF}0002I: Sprache der Meldungen (%1)"
MSG_ASK_MODE=3
MSG_EN[$MSG_ASK_MODE]="${MSG_PRF}0003I: Normal or partition oriented mode (%1)"
MSG_DE[$MSG_ASK_MODE]="${MSG_PRF}0003I: Normaler oder partitionsorientierter Modus (%1)"
MSG_ASK_TYPE1=4
MSG_EN[$MSG_ASK_TYPE1]="${MSG_PRF}0004I: Backuptype (%1)"
MSG_DE[$MSG_ASK_TYPE1]="${MSG_PRF}0004I: Backuptyp (%1)"
MSG_ASK_TYPE2=5
MSG_EN[$MSG_ASK_TYPE2]="${MSG_PRF}0004I: Backuptype (%1)"
MSG_DE[$MSG_ASK_TYPE2]="${MSG_PRF}0004I: Backuptyp (%1)"
MSG_ASK_KEEP=6
MSG_EN[$MSG_ASK_KEEP]="${MSG_PRF}0006I: Number of backups (1-52)"
MSG_DE[$MSG_ASK_KEEP]="${MSG_PRF}0006I: Anzahl der Backups (1-52)"
MSG_ANSWER_CHARS_YES_NO=7
MSG_EN[$MSG_ANSWER_CHARS_YES_NO]="y|n"
MSG_DE[$MSG_ANSWER_CHARS_YES_NO]="j|n"
MSG_ASK_DETAILS=8
MSG_EN[$MSG_ASK_DETAILS]="${MSG_PRF}0008I: Verbose messages (%1)"
MSG_DE[$MSG_ASK_DETAILS]="${MSG_PRF}0008I: Ausführliche Meldungen (%1)"
MSG_CONF_OK=9
MSG_EN[$MSG_CONF_OK]="${MSG_PRF}0009I: Configuration OK (%1)"
MSG_DE[$MSG_CONF_OK]="${MSG_PRF}0009I: Konfiguration OK (%1)"
MSG_INVALID_MESSAGE=10
MSG_EN[$MSG_INVALID_MESSAGE]="${MSG_PRF}0010E: Invalid language %1."
MSG_DE[$MSG_INVALID_MESSAGE]="${MSG_PRF}0010E: Ungültige Sprache %1."
MSG_INVALID_OPTION=11
MSG_EN[$MSG_INVALID_OPTION]="${MSG_PRF}0011E: Invalid option %1."
MSG_DE[$MSG_INVALID_OPTION]="${MSG_PRF}0011E: Ungültige Option %1."
MSG_PARAMETER_EXPECTED=12
MSG_EN[$MSG_PARAMETER_EXPECTED]="${MSG_PRF}0012E: Parameter expected for option %1."
MSG_DE[$MSG_PARAMETER_EXPECTED]="${MSG_PRF}0012E: Parameter erwartet bei Option %1."
MSG_SUDO_REQUIRED=13
MSG_EN[$MSG_SUDO_REQUIRED]="${MSG_PRF}0013E: Installation script needs root access. Try 'sudo %1'."
MSG_DE[$MSG_SUDO_REQUIRED]="${MSG_PRF}0013E: Das Installationsscript benötigt root Rechte. Versuche es mit 'sudo %1'."
MSG_DOWNLOADING=14
MSG_EN[$MSG_DOWNLOADING]="${MSG_PRF}0014I: Downloading %1..."
MSG_DE[$MSG_DOWNLOADING]="${MSG_PRF}0014I: %1 wird aus dem Netz geladen..."
MSG_DOWNLOAD_FAILED=15
MSG_EN[$MSG_DOWNLOAD_FAILED]="${MSG_PRF}0015E: Download of %1 failed. HTTP code: %2."
MSG_DE[$MSG_DOWNLOAD_FAILED]="${MSG_PRF}0015E: %1 kann nicht aus dem Netz geladen werden. HTTP code: %2."
MSG_INSTALLATION_FAILED=16
MSG_EN[$MSG_INSTALLATION_FAILED]="${MSG_PRF}0016E: Installation of %1 failed. Check %2."
MSG_DE[$MSG_INSTALLATION_FAILED]="${MSG_PRF}0016E: Installation von %1 fehlerhaft beendet. Prüfe %2."
MSG_SAVING_FILE=17
MSG_EN[$MSG_SAVING_FILE]="${MSG_PRF}0017I: Existing file %1 saved as %2."
MSG_DE[$MSG_SAVING_FILE]="${MSG_PRF}0017I: Existierende Datei %1 wurde als %2 gesichert."
MSG_CHMOD_FAILED=18
MSG_EN[$MSG_CHMOD_FAILED]="${MSG_PRF}0018E: chmod of %1 failed."
MSG_DE[$MSG_CHMOD_FAILED]="${MSG_PRF}0018E: chmod von %1 nicht möglich."
MSG_MOVE_FAILED=19
MSG_EN[$MSG_MOVE_FAILED]="${MSG_PRF}0019E: mv of %1 failed."
MSG_DE[$MSG_MOVE_FAILED]="${MSG_PRF}0019E: mv von %1 nicht möglich."
MSG_NO_BETA_AVAILABLE=20
MSG_EN[$MSG_NO_BETA_AVAILABLE]="${MSG_PRF}0020I: No beta available right now."
MSG_DE[$MSG_NO_BETA_AVAILABLE]="${MSG_PRF}0020I: Momentan kein Beta verfügbar."
MSG_READ_LOG=21
MSG_EN[$MSG_READ_LOG]="${MSG_PRF}0021I: See logfile %1 for details."
MSG_DE[$MSG_READ_LOG]="${MSG_PRF}0021I: Siehe Logdatei %1 für weitere Details."
MSG_CLEANUP=22
MSG_EN[$MSG_CLEANUP]="${MSG_PRF}0022I: Cleaning up..."
MSG_DE[$MSG_CLEANUP]="${MSG_PRF}0022I: Räume auf..."
MSG_INSTALLATION_FINISHED=23
MSG_EN[$MSG_INSTALLATION_FINISHED]="${MSG_PRF}0023I: Installation of %1 finished successfully."
MSG_DE[$MSG_INSTALLATION_FINISHED]="${MSG_PRF}0023I: Installation von %1 erfolgreich beendet."
MSG_UPDATING_CONFIG=24
MSG_EN[$MSG_UPDATING_CONFIG]="${MSG_PRF}0024I: Updating configuration in %1."
MSG_DE[$MSG_UPDATING_CONFIG]="${MSG_PRF}0024I: Konfigurationsdatei %1 wird angepasst."
MSG_ASK_COMPRESS=25
MSG_EN[$MSG_ASK_COMPRESS]="${MSG_PRF}0025I: Compress backup (%1)"
MSG_DE[$MSG_ASK_COMPRESS]="${MSG_PRF}0025I: Backup komprimieren (%1)"
MSG_NEWLINE=26
MSG_EN[$MSG_NEWLINE]="$NL"
MSG_DE[$MSG_NEWLINE]="$NL"
MSG_ASK_UNINSTALL=27
MSG_EN[$MSG_ASK_UNINSTALL]="${MSG_PRF}0027I: Are you sure to uninstall $RASPIBACKUP_NAME (%1)"
MSG_DE[$MSG_ASK_UNINSTALL]="${MSG_PRF}0027I: Soll $RASPIBACKUP_NAME wirklich deinstalliert werden (%1)"
MSG_DELETE_FILE=28
MSG_EN[$MSG_DELETE_FILE]="${MSG_PRF}0028I: Deleting %1..."
MSG_DE[$MSG_DELETE_FILE]="${MSG_PRF}0028I: Lösche %1..."
MSG_UNINSTALL_FINISHED=29
MSG_EN[$MSG_UNINSTALL_FINISHED]="${MSG_PRF}0029I: Uninstall of %1 finished successfully."
MSG_DE[$MSG_UNINSTALL_FINISHED]="${MSG_PRF}0029I: Deinstallation von %1 erfolgreich beendet."
MSG_UNINSTALL_FAILED=30
MSG_EN[$MSG_UNINSTALL_FAILED]="${MSG_PRF}0030E: Delete of %1 failed."
MSG_DE[$MSG_UNINSTALL_FAILED]="${MSG_PRF}0030E: Löschen von %1 fehlerhaft beendet."
MSG_DOWNLOADING_BETA=31
MSG_EN[$MSG_DOWNLOADING_BETA]="${MSG_PRF}0031I: Downloading %1 beta..."
MSG_DE[$MSG_DOWNLOADING_BETA]="${MSG_PRF}0031I: %1 beta wird aus dem Netz geladen..."
MSG_CHECKING_FOR_BETA=32
MSG_EN[$MSG_CHECKING_FOR_BETA]="${MSG_PRF}0032I: Checking if there is a beta version available."
MSG_DE[$MSG_CHECKING_FOR_BETA]="${MSG_PRF}0032I: Prüfung ob eine Betaversion verfügbar ist."
MSG_BETAVERSION_AVAILABLE=33
MSG_EN[$MSG_BETAVERSION_AVAILABLE]="${MSG_PRF}0033I: Beta version %1 is available."
MSG_DE[$MSG_BETAVERSION_AVAILABLE]="${MSG_PRF}0033I: Beta Version %1 ist verfügbar."
MSG_ASK_INSTALLBETA=34
MSG_EN[$MSG_ASK_INSTALLBETA]="${MSG_PRF}0034I: Install beta version (y|n)"
MSG_DE[$MSG_ASK_INSTALLBETA]="${MSG_PRF}0034I: Soll die Betaversion installiert werden (j|n)"
#MSG_BETA_MESSAGE=35
#MSG_EN[$MSG_BETA_MESSAGE]="!!! RBK0035I: =========> NOTE  <========= "
#MSG_DE[$MSG_BETA_MESSAGE]="!!! RBK0035I: =========> HINWEIS <========="
MSG_BETA_THANKYOU=36
MSG_EN[$MSG_BETA_THANKYOU]="${MSG_PRF}0036I: Thank you very much for helping to test $FILE_TO_INSTALL %1."
MSG_DE[$MSG_BETA_THANKYOU]="${MSG_PRF}0036I: Vielen Dank für die Hilfe beim Testen von $FILE_TO_INSTALL %1."
MSG_CODE_INSTALLED=37
MSG_EN[$MSG_CODE_INSTALLED]="${MSG_PRF}0037I: Created %1."
MSG_DE[$MSG_CODE_INSTALLED]="${MSG_PRF}0037I: %1 wurde erstellt."
MSG_NO_INSTALLATION_FOUND=38
MSG_EN[$MSG_NO_INSTALLATION_FOUND]="${MSG_PRF}0038E: No installation to refresh detected."
MSG_DE[$MSG_NO_INSTALLATION_FOUND]="${MSG_PRF}0038E: Keine Installation für einen Update entdeckt."
MSG_CHOWN_FAILED=39
MSG_EN[$MSG_CHOWN_FAILED]="${MSG_PRF}0039E: chown of %1 failed."
MSG_DE[$MSG_CHOWN_FAILED]="${MSG_PRF}0039E: chown von %1 nicht möglich."
MSG_ANSWER_CHARS_YES=40
MSG_EN[$MSG_ANSWER_CHARS_YES]="y"
MSG_DE[$MSG_ANSWER_CHARS_YES]="j"
MSG_ANSWER_CHARS_NO=41
MSG_EN[$MSG_ANSWER_CHARS_NO]="n"
MSG_DE[$MSG_ANSWER_CHARS_NO]="n"
MSG_CONFIG_INFO=42
MSG_EN[$MSG_CONFIG_INFO]="${MSG_PRF}0041I: Default selection is the option in UPPERCASE."
MSG_DE[$MSG_CONFIG_INFO]="${MSG_PRF}0041I: Bei keiner Eingabe wird die in GROSSBUCHSTABEN geschriebene Option benutzt." 
MSG_SELECTED_CONFIG_PARMS1=43
MSG_EN[$MSG_SELECTED_CONFIG_PARMS1]="${MSG_PRF}0042I: Selected configuration: Message language: %1, Backupmode: %2, Backuptype: %3"
MSG_DE[$MSG_SELECTED_CONFIG_PARMS1]="${MSG_PRF}0042I: Gewählte Konfiguration: Sprache der Meldungen: %1, Backupmodus: %2, Backuptype: %3"
MSG_NORMAL_MODE=44
MSG_EN[$MSG_NORMAL_MODE]="normal"
MSG_DE[$MSG_NORMAL_MODE]="normal"
MSG_PARTITION_MODE=45
MSG_EN[$MSG_PARTITION_MODE]="partition oriented"
MSG_DE[$MSG_PARTITION_MODE]="partitionsorientiert"
MSG_SAMPLEEXTENSION_INSTALL_FAILED=46
MSG_EN[$MSG_SAMPLEEXTENSION_INSTALL_FAILED]="${MSG_PRF}0046E: Sample extension installation failed. %1"
MSG_DE[$MSG_SAMPLEEXTENSION_INSTALL_FAILED]="${MSG_PRF}0046E: Beispielserweiterungsinstallation fehlgeschlagen. %1"
MSG_SAMPLEEXTENSION_INSTALL_SUCCESS=47
MSG_EN[$MSG_SAMPLEEXTENSION_INSTALL_SUCCESS]="${MSG_PRF}0047I: Sample extensions successfully installed and enabled."
MSG_DE[$MSG_SAMPLEEXTENSION_INSTALL_SUCCESS]="${MSG_PRF}0047I: Beispielserweiterungen erfolgreich installiert und eingeschaltet."
MSG_SELECTED_CONFIG_PARMS2=48
MSG_EN[$MSG_SELECTED_CONFIG_PARMS2]="${MSG_PRF}0048I: Selected configuration: Compress backups: %1, Number of backups: %2, Verbose messages: %3"
MSG_DE[$MSG_SELECTED_CONFIG_PARMS2]="${MSG_PRF}0048I: Gewählte Konfiguration: Backup komprimieren: %1, Anzahl Backups: %2, Ausführliche Meldungen: %3"

declare -A MSG_HEADER=( ['I']="---" ['W']="!!!" ['E']="???" )

INSTALLATION_SUCCESSFULL=0
INSTALLATION_STARTED=0
CONFIG_INSTALLED=0
SCRIPT_INSTALLED=0

function trapWithArg() { # function trap1 trap2 ... trapn
    local func="$1" ; shift
    for sig ; do
        trap "$func $sig" "$sig"
    done
}

function extractVersionFromFile() { # fileName
	echo $(grep "^VERSION=" "$1" | cut -f 2 -d = | sed  "s/\"//g" | sed "s/ .*#.*//")
}

function cleanup() {

	trap '' SIGINT SIGTERM EXIT	

	local rc=$?
	
	TAIL=0
	if (( $INSTALLATION_STARTED )); then
		if (( ! $INSTALLATION_SUCCESSFULL )); then
			writeToConsole $MSG_NEWLINE
			writeToConsole $MSG_CLEANUP
			(( $CONFIG_INSTALLED )) && rm $CONFIG_FILE_ABS_FILE &>>$LOG_FILE || true
			(( $SCRIPT_INSTALLED )) && rm $FILE_TO_INSTALL_ABS_FILE &>>$LOG_FILE || true 
			(( $SCRIPT_INSTALLED && ! $KEEP_INSTALL_SCRIPT )) && rm $FILE_TO_INSTALL_ABS_PATH/$MYSELF &>>$LOG_FILE || true 
			writeToConsole $MSG_INSTALLATION_FAILED "$RASPIBACKUP_NAME" "$LOG_FILE"
			rc=127
		else
			rm $MYDIR/$MYSELF &>/dev/null
			writeToConsole $MSG_INSTALLATION_FINISHED "$RASPIBACKUP_NAME"
			rm $LOG_FILE &>/dev/null || true
		fi
	else
		rm -f $LOG_FILE &>/dev/null || true
	fi
	
	(( $INSTALL_EXTENSIONS )) && rm $SAMPLEEXTENSION_TAR_FILE &>>$LOG_FILE || true 
	
	exit $rc
}
	
# Create message and substitute parameters

function getMessageText() {         # languageflag messagenumber parm1 parm2 ...
    
    local msg p i s

	if [[ $1 != "L" ]]; then
		LANG_SUFF=${1^^*}
	else
		LANG_EXT=${LANG^^*}
		LANG_SUFF=${LANG_EXT:0:2}
	fi

    if [[ $LANG_SUFF == "DE" || $LANG_SUFF == "EN" ]]; then
    	msgVar="MSG_${LANG_SUFF}"
		msgVar="$msgVar[$2]"
        msg=${!msgVar}
        if [[ -z $msg ]]; then		       			# no translation found
			msgVar="$2"
			if [[ -z ${!msgVar} ]]; then
				echo "${MSG_EN[$MSG_UNDEFINED]}"	# unknown message id
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
      msg="$( perl -p -e "s@$s@$p@" <<< "$msg" 2>/dev/null)"	  # have to use explicit command name 
    done
   
    msg="$( perl -p -e "s/%[0-9]+//g" <<< "$msg" 2>/dev/null)"     # delete trailing %n definitions
	
	local msgPref=${msg:0:3}
	
	if [[ $msgPref == "${MSG_PRF}" ]]; then
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

function getLocalizedMessage() { # messageNumber parm1 parm2

	local msg
	msg="$(getMessageText $MESSAGE_LANGUAGE "$@")"	
	echo "$msg"
}

function writeToConsole() {  # messagenumber messageparameters
	
	local msg tailer
	
	msg="$(getMessageText $MESSAGE_LANGUAGE "$@")"

	if (( $TAIL )); then
		tailer=" : "
		echo -e -n "$msg$tailer" 2>/dev/null >> "$LOG_FILE"
		echo -e -n "$msg$tailer"
	else
		tailer=""
		echo -e "$msg" 2>/dev/null >> "$LOG_FILE"
		echo -e "$msg"
	fi

}

function parameterError() {
	usage
	exit 127
}

function unrecoverableError() {
	writeToConsole $MSG_READ_LOG "$LOG_FILE"
	exit 127
}

function downloadCode() {

	local oldversion newName

	if [[ -f $FILE_TO_INSTALL_ABS_FILE ]]; then
		oldVersion=$(grep "^VERSION=" $FILE_TO_INSTALL_ABS_FILE | cut -f 2 -d = | sed  "s/\"//g" | sed "s/ .*#.*//")	
		newName="$FILE_TO_INSTALL_ABS_FILE.$oldVersion.sh"
		writeToConsole $MSG_SAVING_FILE "$FILE_TO_INSTALL" "$newName"
		mv $FILE_TO_INSTALL_ABS_FILE $newName
	elif (( $REFRESH_SCRIPT )); then
		writeToConsole $MSG_NO_INSTALLATION_FOUND
		unrecoverableError
	fi

	if (( $BETA_INSTALL )); then
		FILE_TO_INSTALL_URL="$BETA_CODE_URL"
		writeToConsole $MSG_DOWNLOADING_BETA "$FILE_TO_INSTALL"
	else
		FILE_TO_INSTALL_URL="$STABLE_CODE_URL"
		writeToConsole $MSG_DOWNLOADING "$FILE_TO_INSTALL"
	fi
	
	SCRIPT_INSTALLED=1
	
	httpCode=$(curl -s -o $FILE_TO_INSTALL -w %{http_code} -L "$MYHOMEURL/$FILE_TO_INSTALL_URL" 2>>$LOG_FILE)
	if [[ ${httpCode:0:1} != "2" ]]; then
		writeToConsole $MSG_DOWNLOAD_FAILED "$FILE_TO_INSTALL" "$httpCode" 
		unrecoverableError
	fi
			
	if ! mv $FILE_TO_INSTALL $FILE_TO_INSTALL_ABS_FILE &>>$LOG_FILE; then
		writeToConsole $MSG_MOVE_FAILED "$FILE_TO_INSTALL_ABS_FILE"
		unrecoverableError
	fi

	writeToConsole $MSG_CODE_INSTALLED "$FILE_TO_INSTALL_ABS_FILE"

	if ! chmod 755 $FILE_TO_INSTALL_ABS_FILE &>>$LOG_FILE; then
		writeToConsole $MSG_CHMOD_FAILED "$FILE_TO_INSTALL_ABS_FILE"
		unrecoverableError
	fi

	if [[ "$MYDIR/$MYSELF" != "$FILE_TO_INSTALL_ABS_PATH/$MYSELF" ]]; then
		if cp "$MYDIR/$MYSELF" $FILE_TO_INSTALL_ABS_PATH &>>$LOG_FILE; then
			writeToConsole $MSG_MOVE_FAILED "$FILE_TO_INSTALL_ABS_PATH/$MYSELF"
			unrecoverableError
		fi

		writeToConsole $MSG_CODE_INSTALLED "$FILE_TO_INSTALL_ABS_PATH/$MYSELF"

		if ! chmod 755 $FILE_TO_INSTALL_ABS_PATH/$MYSELF &>>$LOG_FILE; then
			writeToConsole $MSG_CHMOD_FAILED "$FILE_TO_INSTALL_ABS_PATH/$MYSELF"
			unrecoverableError
		fi
	
		if ! chown $(stat -c "%U:%G" $FILE_TO_INSTALL_ABS_PATH | sed -z 's/\n//') $FILE_TO_INSTALL_ABS_PATH/$MYSELF &>>$LOG_FILE; then
			writeToConsole $MSG_CHOWN_FAILED "$FILE_TO_INSTALL_ABS_PATH/$MYSELF"
			unrecoverableError
		fi
	fi

}

function downloadConfig() {
	
	local oldversion newName http_code

	if [[ -f $CONFIG_FILE_ABS_FILE ]]; then
		oldVersion=$(grep "^VERSION=" $FILE_TO_INSTALL_ABS_FILE | cut -f 2 -d = | sed  "s/\"//g" | sed "s/ .*#.*//")	
		newName="$CONFIG_FILE_ABS_FILE.$oldVersion"
		writeToConsole $MSG_SAVING_FILE "$CONFIG_FILE" "$newName"
		mv $CONFIG_FILE_ABS_FILE $newName &>>$LOG_FILE
	fi
	
	writeToConsole $MSG_DOWNLOADING "$CONFIG_FILE"
	CONFIG_INSTALLED=1
	
	httpCode=$(curl -s -o $CONFIG_FILE_ABS_FILE -w %{http_code} -L "https://$URL/$confFile" 2>>$LOG_FILE)
	if [[ ${httpCode:0:1} != "2" ]]; then
		writeToConsole $MSG_DOWNLOAD_FAILED "$confFile" "$httpCode" 
		unrecoverableError
	fi

	if ! chmod 644 $CONFIG_FILE_ABS_FILE &>>$LOG_FILE; then
		writeToConsole $MSG_CHMOD_FAILED "$CONFIG_FILE_ABS_FILE"
		unrecoverableError
	fi

	writeToConsole $MSG_CODE_INSTALLED "$CONFIG_FILE_ABS_FILE"

}

function askFor() { # message, options, default
	
	local ok=0
	local reply v

	local up finalMessage

	if [[ $3 != "" ]]; then
		up=${3^^*}
		finalMessage=$(sed "s/$3/$up/" <<< "$2")
	else
		finalMessage=""
	fi
	
	TAIL=1
	while (( ! $ok )); do
		writeToConsole "$1" "$finalMessage" "-n"
		read reply
		if [[ -z $reply ]]; then
			if [[ -n $3 ]]; then
				reply="$3"
				break
			fi
		fi
		reply=${reply,,*}
		for v in "$2"; do
			if [[ $reply =~ $v ]]; then
				ok=1
				break
			fi
		done
	done
	REPLY="$reply"
	TAIL=0
}

function configWizzard() {

	local done=0
	local ml=${MESSAGE_LANGUAGE,,*}

	writeToConsole $MSG_CONFIG_INFO 

	while (( ! $done )); do
		askFor $MSG_ASK_LANGUAGE "de|en" "$ml"
		MESSAGE_LANGUAGE="$REPLY"

		askFor $MSG_ASK_MODE "n|p" "n"
		CONFIG_BACKUPMODE=$REPLY

		if [[ $CONFIG_BACKUPMODE == "n" ]]; then
			askFor $MSG_ASK_TYPE1 "dd|tar|rsync" "rsync"
		else
			askFor $MSG_ASK_TYPE2 "tar|rsync" "rsync"
		fi
		CONFIG_BACKUPTYPE=$REPLY
		
		regex="dd|tar"
		if [[ $CONFIG_BACKUPTYPE =~ $regex ]]; then
			askFor $MSG_ASK_COMPRESS $(getLocalizedMessage $MSG_ANSWER_CHARS_YES_NO) $(getLocalizedMessage $MSG_ANSWER_CHARS_NO)
			CONFIG_COMPRESS=$REPLY
		else
			CONFIG_COMPRESS="n"
		fi
	
		askFor $MSG_ASK_KEEP "[1-9]|[1-4][0-9]|[5][0-2]" ""
		CONFIG_KEEP_BACKUPS=$REPLY
	
		askFor $MSG_ASK_DETAILS $(getLocalizedMessage $MSG_ANSWER_CHARS_YES_NO) $(getLocalizedMessage $MSG_ANSWER_CHARS_YES)
		CONFIG_DETAILED_MESSAGES=$REPLY
		
		local m="$(getLocalizedMessage $MSG_NORMAL_MODE)"
		[[ $CONFIG_BACKUPMODE == "p" ]] && m="$(getLocalizedMessage $MSG_PARTITION_MODE)"
		writeToConsole $MSG_SELECTED_CONFIG_PARMS1 "$MESSAGE_LANGUAGE" "$m" "$CONFIG_BACKUPTYPE" 
		writeToConsole $MSG_SELECTED_CONFIG_PARMS2 "$CONFIG_COMPRESS" "$CONFIG_KEEP_BACKUPS" "$CONFIG_DETAILED_MESSAGES"
		askFor $MSG_CONF_OK $(getLocalizedMessage $MSG_ANSWER_CHARS_YES_NO) $(getLocalizedMessage $MSG_ANSWER_CHARS_NO)
	
		[[ $REPLY =~ $YES ]] && done=1
	done
	
}

function updateConfig() {
	
	local rc msg
	
	writeToConsole $MSG_UPDATING_CONFIG "$CONFIG_FILE_ABS_FILE"
	
	msg=${MESSAGE_LANGUAGE^^*}
	sed -i "s/^DEFAULT_LANGUAGE=.*\$/DEFAULT_LANGUAGE=\"$msg\"/" $CONFIG_FILE_ABS_FILE

	[[ $CONFIG_BACKUPMODE == "n" ]] && CONFIG_BACKUPMODE=0 || CONFIG_BACKUPMODE=1
	sed -i "s/^DEFAULT_PARTITIONBASED_BACKUP=.*\$/DEFAULT_PARTITIONBASED_BACKUP=\"$CONFIG_BACKUPMODE\"/" $CONFIG_FILE_ABS_FILE
	sed -i "s/^DEFAULT_BACKUPTYPE=.*\$/DEFAULT_BACKUPTYPE=\"$CONFIG_BACKUPTYPE\"/" $CONFIG_FILE_ABS_FILE

	[[ $CONFIG_COMPRESS == "j" ]] && CONFIG_COMPRESS=1 || CONFIG_COMPRESS=0
	sed -i "s/^DEFAULT_ZIP_BACKUP=.*\$/DEFAULT_ZIP_BACKUP=\"$CONFIG_COMPRESS\"/" $CONFIG_FILE_ABS_FILE
	
	sed -i "s/^DEFAULT_KEEPBACKUPS=.*\$/DEFAULT_KEEPBACKUPS=\"$CONFIG_KEEP_BACKUPS\"/" $CONFIG_FILE_ABS_FILE
	
	[[ $CONFIG_DETAILED_MESSAGES == "n" ]] && CONFIG_DETAILED_MESSAGES=0 || CONFIG_DETAILED_MESSAGES=1 
	sed -i "s/^DEFAULT_MSG_LEVEL=.*$/DEFAULT_MSG_LEVEL=\"$CONFIG_DETAILED_MESSAGES\"/" $CONFIG_FILE_ABS_FILE
}

function usageEN() {
	echo "$GIT_CODEVERSION"
	echo ""
	echo "Install and configure raspiBackup.sh"
	echo ""
	echo "Usage: sudo $0 [[-c] [-l DE | EN]] | [-u] | [-h]"
	echo ""
	echo "       No options will start a configuration wizzard and prompt for the most important configuration parameters"
	echo ""
	echo "       -U - Updates the local script version with the latest script version available (Current configuration file will not be modified)"
	echo "       -b - Install the beta version if available"
	echo "       -c - Install default config file in $CONFIG_FILE_ABS_FILE"
	echo "       -e - Install and configure sampleextensions"
	echo "       -k - Keep installscript after successful installation" 
	echo "       -l - Install English (EN) or German (DE) version of the config file"
	echo "       If -c is used without -l the current system language is used for the config file"
	echo ""
	echo "       -u - Uninstall raspiBackup.sh with it's configuration file and the installer"
}

function usageDE() {
	echo "$GIT_CODEVERSION"
	echo ""
	echo "Installiere und konfiguriere raspiBackup.sh"
	echo ""
	echo "Aufruf: sudo $0 [[-c] [-l DE | EN]] | [-u] | [-h]"
	echo ""
	echo "       Falls keine Optionen angegeben wurde werden die wichtigsten Konfigurationsparameter abgefragt"
	echo ""
	echo "       -U - Ersetzt die lokale Scriptversion durch die neueste verfügbare Scriptversion (Die aktuelle Configurationsdatei wird nicht geändert)"
	echo "       -b - Installiert eine Betaversion sofern verfügbar"
	echo "       -c - Installiert die Standardkonfigurationsdatei in $CONFIG_FILE_ABS_FILE"
	echo "       -e - Installiert und konfiguriert die Beispielerweiterungen"
	echo "       -k - Installationsscript wird am Ende der Installation nicht gelöscht"
	echo "       -l - Installiert die englische (EN) oder Deutsche (DE) Version der Konfigurationsdatei"
	echo "       Wenn -c ohne -l benutzt wird wird die Systemsprache für die Konfigurationsdatei benutzt"
	echo ""
	echo "       -l - Deinstalliert raspiBackup.sh mit seiner Konfigurationsdatei und dem Installer"
}

# Borrowed from http://stackoverflow.com/questions/85880/determine-if-a-function-exists-in-bash

fn_exists() {
	[ `type -t $1`"" == 'function' ]
}

function checkIfBetaAvailable() {

	local downloadURL="$MYHOMEURL/$PROPERTY_URL"
	local betaVersion=""

	local tmpFile=$(mktemp)
		
	wget $downloadURL -q --tries=$DOWNLOAD_RETRIES --timeout=$DOWNLOAD_TIMEOUT -O $tmpFile
	local rc=$?
	if [[ $rc == 0 ]]; then
		properties=$(grep "^BETA=" "$tmpFile" 2>/dev/null)
		local betaVersion=$(cut -d '=' -f 2 <<< $properties)
		betaVersion=${betaVersion//\"/}			
	fi
	
	rm $tmpFile	
	echo $betaVersion
}

function usage() {
	
	LANG_SUFF=$MESSAGE_LANGUAGE

	local func="usage${LANG_SUFF}"

	if ! fn_exists $func; then     
		func="usageEN"
	fi
	
	$func

}

function install() {
	
	INSTALLATION_STARTED=1

	if (( $REFRESH_SCRIPT )); then
		downloadCode
	elif (( $INSTALL_CONFIG )); then
		downloadCode
		downloadConfig
	else
		configWizzard
		downloadCode
		downloadConfig
		updateConfig
fi

INSTALLATION_SUCCESSFULL=1

}

function installExtensions() {

	local extensions="mem temp disk"

	writeToConsole $MSG_DOWNLOADING "${SAMPLEEXTENSION_TAR_FILE%.*}"
		
	httpCode=$(curl -s -o $SAMPLEEXTENSION_TAR_FILE -w %{http_code} -L "$MYHOMEURL/$SAMPLEEXTENSION_TAR_FILE" 2>>$LOG_FILE)
	if [[ ${httpCode:0:1} != "2" ]]; then
		writeToConsole $MSG_DOWNLOAD_FAILED "$SAMPLEEXTENSION_TAR_FILE" "$httpCode" 
		unrecoverableError
	fi
		
	if ! tar -xzf $SAMPLEEXTENSION_TAR_FILE -C $FILE_TO_INSTALL_ABS_PATH &>>$LOG_FILE; then
		writeToConsole $MSG_SAMPLEEXTENSION_INSTALL_FAILED "tar -x"
		unrecoverableError
	fi

	if ! chmod 755 $FILE_TO_INSTALL_ABS_PATH/${RASPIBACKUP_NAME}_*.sh &>>$LOG_FILE; then
		writeToConsole $MSG_SAMPLEEXTENSION_INSTALL_FAILED "chmod extensions"
		unrecoverableError
	fi

	sed -i "s/^DEFAULT_EXTENSIONS=.*\$/DEFAULT_EXTENSIONS=\"$extensions\"/" $CONFIG_FILE_ABS_FILE

	writeToConsole $MSG_SAMPLEEXTENSION_INSTALL_SUCCESS
	
}

function uninstall() {
	
	askFor $MSG_ASK_UNINSTALL $(getLocalizedMessage $MSG_ANSWER_CHARS_YES_NO) $(getLocalizedMessage $MSG_ANSWER_CHARS_NO)
	[[ ! $REPLY =~ $YES ]] && return

	local pre=${CONFIG_FILE_ABS_FILE%%.*}	
	local post=${CONFIG_FILE_ABS_FILE##*.}

	writeToConsole $MSG_DELETE_FILE "$pre*.$post"
	if ! rm -f $pre*.$post &>>$LOG_FILE; then
		writeToConsole $MSG_UNINSTALL_FAILED "$pre*.$post"
		unrecoverableError
	fi

	pre=${FILE_TO_INSTALL_ABS_FILE%%.*}	
	post=${FILE_TO_INSTALL_ABS_FILE##*.}
	
	writeToConsole $MSG_DELETE_FILE "$pre*.$post"
	if ! rm -f $pre*.$post 2>>$LOG_FILE; then
		writeToConsole $MSG_UNINSTALL_FAILED "$pre*.$post"
		unrecoverableError
	fi

	writeToConsole $MSG_DELETE_FILE "$FILE_TO_INSTALL_ABS_PATH/$MYSELF"
	if ! rm -f "$FILE_TO_INSTALL_ABS_PATH/$MYSELF" 2>>$LOG_FILE; then
		writeToConsole $MSG_UNINSTALL_FAILED "$FILE_TO_INSTALL_ABS_PATH/$MYSELF"
		unrecoverableError
	fi
	
	writeToConsole $MSG_UNINSTALL_FINISHED "$RASPIBACKUP_NAME"

}

passedOpts="$@"

INSTALL_CONFIG=0
UNINSTALL=0
BETA_INSTALL=0
KEEP_INSTALL_SCRIPT=0
REFRESH_SCRIPT=0
INSTALL_EXTENSIONS=0

trapWithArg cleanup SIGINT SIGTERM EXIT

while getopts ":bcekl:huU" opt; do
   case $opt in 
		b) 	BETA_INSTALL=1
			;;
		c)  INSTALL_CONFIG=1
			;;
		e)	INSTALL_EXTENSIONS=1
			;;
		l) 	LANG_PRF=$(tr '[:lower:]' '[:upper:]' <<< "$OPTARG")
			if [[ $LANG_PRF != "DE" && $LANG_PRF != "EN" ]]; then
				writeToConsole $MSG_INVALID_MESSAGE "$LANG_PRF"
				parameterError
			else
				MESSAGE_LANGUAGE=$LANG_PRF
			fi
			;;
		k) 	KEEP_INSTALL_SCRIPT=1
			;;
		h)  	usage
			exit 0
			;;
		u)	UNINSTALL=1
			;;
		U)  	REFRESH_SCRIPT=1
			;;
		\?)	writeToConsole $MSG_INVALID_OPTION "-$OPTARG"
			parameterError
			;;
		:) 	writeToConsole $MSG_PARAMETER_EXPECTED "-$OPTARG"
			parameterError
			;;
    esac
done

writeToConsole $MSG_VERSION "$GIT_CODEVERSION"

if (( $UID != 0 )); then
	writeToConsole $MSG_SUDO_REQUIRED "$0 $passedOpts"
	exit 1
fi

rm $LOG_FILE &>/dev/null || true

case $MESSAGE_LANGUAGE in
	DE) confFile=${CONFIG_DOWNLOAD_FILE["DE"]}
		;;
	*) confFile=${CONFIG_DOWNLOAD_FILE["EN"]}
		;;
esac

if (( $UNINSTALL )); then
	uninstall
	exit 0
fi

if (( $INSTALL_EXTENSIONS )); then
	installExtensions
	exit 0
fi

writeToConsole $MSG_CHECKING_FOR_BETA
beta=$(checkIfBetaAvailable)
if [[ -n "$beta" ]]; then
	writeToConsole $MSG_BETAVERSION_AVAILABLE "$beta"
	if (( ! $BETA_INSTALL )); then
		askFor $MSG_ASK_INSTALLBETA $(getLocalizedMessage $MSG_ANSWER_CHARS_YES_NO) $(getLocalizedMessage $MSG_ANSWER_CHARS_ye)
		[[ $REPLY =~ $YES ]] && BETA_INSTALL=1
	fi
elif (( $BETA_INSTALL )); then
	writeToConsole $MSG_NO_BETA_AVAILABLE
	exit 0
fi

install
(( $BETA_INSTALL && INSTALLATION_SUCCESSFULL )) && writeToConsole $MSG_BETA_THANKYOU "$beta"

# vim: set expandtab tabstop=8 shiftwidth=8 autoindent smartindent
