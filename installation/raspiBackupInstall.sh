#!/bin/bash

# Simple script to download, install and configure raspiBackup.sh
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for details
#
# (C) 2015-2016 - framp at linux-tips-and-tricks dot de

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}
VERSION="0.3.1"

GIT_DATE="$Date: 2016-04-14 23:46:02 +0200$"
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<< $GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<< $GIT_DATE) 
GIT_COMMIT="$Sha1: 04875c3$"
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<< $GIT_COMMIT | sed 's/\$//')

GIT_CODEVERSION="$MYSELF $VERSION, $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"

FILE_TO_INSTALL="raspiBackup.sh"
LOG_FILE="./$MYNAME.log"
URL="www.linux-tips-and-tricks.de"
declare -A CONFIG_DOWNLOAD_FILE=( ['DE']="raspiBackup_de.conf" ['EN']="raspiBackup_en.conf" )
CONFIG_FILE="raspiBackup.conf"
CONFIG_FILE_ABS_PATH="/usr/local/etc/$CONFIG_FILE"
FILE_TO_INSTALL_ABS_PATH="/usr/local/bin/$FILE_TO_INSTALL"

LANG_EXT=${LANG^^*}
[[ -z $LANG_EXT ]] && LANG_EXT="EN"
SYSTEM_LANGUAGE=${LANG_EXT:0:2}
MESSAGE_LANGUAGE=$SYSTEM_LANGUAGE

NL=$'\n'

MSG_EN=1      # english	(default)
MSG_DE=1      # german

MSG_PRF="RBI"

declare -A MSG_EN
declare -A MSG_DE

MSG_UNDEFINED=0
MSG_EN[$MSG_UNDEFINED]="${MSG_PRF}0000E: Undefined messageid"
MSG_DE[$MSG_UNDEFINED]="${MSG_PRF}0000E: Unbekannte Meldungsid"
MSG_VERSION=1
MSG_EN[$MSG_VERSION]="${MSG_PRF}0001I: %1"
MSG_DE[$MSG_VERSION]="${MSG_PRF}0001I: %1"
MSG_ASK_LANGUAGE=2
MSG_EN[$MSG_ASK_LANGUAGE]="${MSG_PRF}0002I: Message language (en|de)"
MSG_DE[$MSG_ASK_LANGUAGE]="${MSG_PRF}0002I: Sprache der Meldungen (de|en)"
MSG_ASK_MODE=3
MSG_EN[$MSG_ASK_MODE]="${MSG_PRF}0003I: Normal or partitionorientierted mode (n|p)"
MSG_DE[$MSG_ASK_MODE]="${MSG_PRF}0003I: Normaler oder partitionsorientierter Modus (n|p)"
MSG_ASK_TYPE1=4
MSG_EN[$MSG_ASK_TYPE1]="${MSG_PRF}0004I: Backuptype (dd|tar|rsync)"
MSG_DE[$MSG_ASK_TYPE1]="${MSG_PRF}0004I: Backuptyp (dd|tar|rsync)"
MSG_ASK_TYPE2=5
MSG_EN[$MSG_ASK_TYPE2]="${MSG_PRF}0004I: Backuptype (tar|rsync)"
MSG_DE[$MSG_ASK_TYPE2]="${MSG_PRF}0004I: Backuptyp (tar|rsync)"
MSG_ASK_KEEP=6
MSG_EN[$MSG_ASK_KEEP]="${MSG_PRF}0006I: Number of backups (1-52)"
MSG_DE[$MSG_ASK_KEEP]="${MSG_PRF}0006I: Anzahl der Backups (1-52)"
MSG_ANSWER_CHARS_YES_NO=7
MSG_EN[$MSG_ANSWER_CHARS_YES_NO]="y|n"
MSG_DE[$MSG_ANSWER_CHARS_YES_NO]="j|n"
MSG_ASK_DETAILS=8
MSG_EN[$MSG_ASK_DETAILS]="${MSG_PRF}0008I: Verbose messages (y|n)"
MSG_DE[$MSG_ASK_DETAILS]="${MSG_PRF}0008I: Ausführliche Meldungen (j|n)"
MSG_CONF_OK=9
MSG_EN[$MSG_CONF_OK]="${MSG_PRF}0009I: Configuration OK (y|n)"
MSG_DE[$MSG_CONF_OK]="${MSG_PRF}0009I: Konfiguration OK (j|n)"
MSG_INVALID_MESSAGE=10
MSG_EN[$MSG_INVALID_MESSAGE]="${MSG_PRF}0010E: Invalid language %1"
MSG_DE[$MSG_INVALID_MESSAGE]="${MSG_PRF}0010E: Ungültige Sprache %1"
MSG_INVALID_OPTION=11
MSG_EN[$MSG_INVALID_OPTION]="${MSG_PRF}0011E: Invalid option %1"
MSG_DE[$MSG_INVALID_OPTION]="${MSG_PRF}0011E: Ungültige Option %1"
MSG_PARAMETER_EXPECTED=12
MSG_EN[$MSG_PARAMETER_EXPECTED]="${MSG_PRF}0012E: Parameter expected for option %1"
MSG_DE[$MSG_PARAMETER_EXPECTED]="${MSG_PRF}0012E: Parameter erwartet bei Option %1"
MSG_SUDO_REQUIRED=13
MSG_EN[$MSG_SUDO_REQUIRED]="${MSG_PRF}0013E: Script has to be invoked as root. Use 'sudo %1'"
MSG_DE[$MSG_SUDO_REQUIRED]="${MSG_PRF}0013E: Das Script muss als root aufgerufen werden. Z.B. 'sudo %1'"
MSG_DOWNLOADING=14
MSG_EN[$MSG_DOWNLOADING]="${MSG_PRF}0014I: Downloading %1"
MSG_DE[$MSG_DOWNLOADING]="${MSG_PRF}0014I: %1 wird aus dem Netz geladen"
MSG_DOWNLOAD_FAILED=15
MSG_EN[$MSG_DOWNLOAD_FAILED]="${MSG_PRF}0015E: Download of %1 failed. HTTP code: %2"
MSG_DE[$MSG_DOWNLOAD_FAILED]="${MSG_PRF}0015E: %1 kann nicht aus dem Netz geladen werden. HTTP code: %2"
MSG_INSTALLATION_FAILED=16
MSG_EN[$MSG_INSTALLATION_FAILED]="${MSG_PRF}0016E: Installation of %1 failed"
MSG_DE[$MSG_INSTALLATION_FAILED]="${MSG_PRF}0016E: Installation von %1 fehlerhaft beendet"
MSG_SAVING_FILE=17
MSG_EN[$MSG_SAVING_FILE]="${MSG_PRF}0017I: Existing file %1 saved as %2"
MSG_DE[$MSG_SAVING_FILE]="${MSG_PRF}0017I: Existierende Datei %1 wurde als %2 gesichert"
MSG_CHMOD_FAILED=18
MSG_EN[$MSG_CHMOD_FAILED]="${MSG_PRF}0018E: chmod of %1 failed"
MSG_DE[$MSG_CHMOD_FAILED]="${MSG_PRF}0018E: chmod von %1 nicht möglich"
MSG_MOVE_FAILED=19
MSG_EN[$MSG_MOVE_FAILED]="${MSG_PRF}0019E: mv of %1 failed"
MSG_DE[$MSG_MOVE_FAILED]="${MSG_PRF}0019E: mv von %1 nicht möglich"
#MSG_USE_HELP=20
#MSG_EN[$MSG_USE_HELP]="${MSG_PRF}0020I: Use option -h for help"
#MSG_DE[$MSG_USE_HELP]="${MSG_PRF}0020I: Option -h benutzen um Hilfe zu bekommen"
MSG_READ_LOG=21
MSG_EN[$MSG_READ_LOG]="${MSG_PRF}0021I: See logfile %1 for details"
MSG_DE[$MSG_READ_LOG]="${MSG_PRF}0021I: Siehe Logdatei %1 für weitere Details"
MSG_CLEANUP=22
MSG_EN[$MSG_CLEANUP]="${MSG_PRF}0022I: Cleaning up"
MSG_DE[$MSG_CLEANUP]="${MSG_PRF}0022I: Räume auf"
MSG_INSTALLATION_FINISHED=23
MSG_EN[$MSG_INSTALLATION_FINISHED]="${MSG_PRF}0023I: Installation of %1 finished successfully"
MSG_DE[$MSG_INSTALLATION_FINISHED]="${MSG_PRF}0023I: Installation von %1 erfolgreich beendet"
MSG_UPDATING_CONFIG=24
MSG_EN[$MSG_UPDATING_CONFIG]="${MSG_PRF}0024I: Updating configuration in %1"
MSG_DE[$MSG_UPDATING_CONFIG]="${MSG_PRF}0024I: Konfigurationsdatei %1 wird angepasst"
MSG_ASK_COMPRESS=25
MSG_EN[$MSG_ASK_COMPRESS]="${MSG_PRF}0025I: Compress backup (y|n)"
MSG_DE[$MSG_ASK_COMPRESS]="${MSG_PRF}0025I: Backup komprimieren (j|n)"
MSG_NEWLINE=26
MSG_EN[$MSG_NEWLINE]="$NL"
MSG_DE[$MSG_NEWLINE]="$NL"

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

function cleanup() {

	trap '' SIGINT SIGTERM EXIT	

	local rc=$?
	
	TAIL=0
	if (( $INSTALLATION_STARTED )); then
		if (( ! $INSTALLATION_SUCCESSFULL )); then
			writeToConsole $MSG_NEWLINE
			writeToConsole $MSG_CLEANUP
			(( $CONFIG_INSTALLED )) && rm $CONFIG_FILE_ABS_PATH &>>$LOG_FILE
			(( $SCRIPT_INSTALLED )) && rm $FILE_TO_INSTALL_ABS_PATH &>>$LOG_FILE
			writeToConsole $MSG_INSTALLATION_FAILED "$FILE_TO_INSTALL"
			rc=127
		else
			writeToConsole $MSG_INSTALLATION_FINISHED "$FILE_TO_INSTALL"
			rm $LOG_FILE &>/dev/null
		fi
	else
		rm -f $LOG_FILE &>/dev/null
	fi
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

	msgVar="MSG_${LANG_SUFF}"

    if [[ -n ${!msgVar} ]]; then
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
      msg="$( perl -p -e "s|$s|$p|" <<< "$msg" 2>/dev/null)"	  # have to use explicit command name 
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

	if [[ -f $FILE_TO_INSTALL_ABS_PATH ]]; then
		oldVersion=$(grep "^VERSION=" $FILE_TO_INSTALL_ABS_PATH | cut -f 2 -d = | sed  "s/\"//g" | sed "s/ .*#.*//")	
		newName="$FILE_TO_INSTALL_ABS_PATH.$oldVersion.sh"
		writeToConsole $MSG_SAVING_FILE "$FILE_TO_INSTALL" "$newName"
		mv $FILE_TO_INSTALL_ABS_PATH $newName
	fi

	writeToConsole $MSG_DOWNLOADING "$FILE_TO_INSTALL"
	SCRIPT_INSTALLED=1
	
	httpCode=$(curl -s -o $FILE_TO_INSTALL -w %{http_code} -L "https://$URL/$FILE_TO_INSTALL" 2>>$LOG_FILE)
	if [[ ${httpCode:0:1} != "2" ]]; then
		writeToConsole $MSG_DOWNLOAD_FAILED "$FILE_TO_INSTALL" "$httpCode" 
		unrecoverableError
	fi
			
	if ! mv $FILE_TO_INSTALL $FILE_TO_INSTALL_ABS_PATH 2>>$LOG_FILE; then
		writeToConsole $MSG_MOVE_FAILED "$FILE_TO_INSTALL_ABS_PATH"
		unrecoverableError
	fi

	if ! chmod 755 $FILE_TO_INSTALL_ABS_PATH &>>$LOG_FILE; then
		writeToConsole $MSG_CHMOD_FAILED "$FILE_TO_INSTALL_ABS_PATH"
		unrecoverableError
	fi

}

function downloadConfig() {
	
	local oldversion newName http_code

	if [[ -f $CONFIG_FILE_ABS_PATH ]]; then
		oldVersion=$(grep "^VERSION=" $FILE_TO_INSTALL_ABS_PATH | cut -f 2 -d = | sed  "s/\"//g" | sed "s/ .*#.*//")	
		newName="$CONFIG_FILE_ABS_PATH.$oldVersion"
		writeToConsole $MSG_SAVING_FILE "$CONFIG_FILE" "$newName"
		mv $CONFIG_FILE_ABS_PATH $newName &>>$LOG_FILE
	fi
	
	writeToConsole $MSG_DOWNLOADING "$CONFIG_FILE"
	CONFIG_INSTALLED=1
	
	httpCode=$(curl -s -o $CONFIG_FILE_ABS_PATH -w %{http_code} -L "https://$URL/$confFile" 2>>$LOG_FILE)
	if [[ ${httpCode:0:1} != "2" ]]; then
		writeToConsole $MSG_DOWNLOAD_FAILED "$confFile" "$httpCode" 
		unrecoverableError
	fi

	if ! chmod 644 $CONFIG_FILE_ABS_PATH 2>>$LOG_FILE; then
		writeToConsole $MSG_CHMOD_FAILED "$CONFIG_FILE_ABS_PATH"
		unrecoverableError
	fi

}

function askFor() { # message, options
	
	local ok=0
	local reply v
	
	TAIL=1
	while (( ! $ok )); do
		writeToConsole "$1" "" "-n"
		read reply
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
	local YES="y|j|Y|J"
	
	while (( ! $done )); do
		askFor $MSG_ASK_LANGUAGE "de|en"
		MESSAGE_LANGUAGE="$REPLY"

		askFor $MSG_ASK_MODE "n|p"
		CONFIG_BACKUPMODE=$REPLY

		if [[ $CONFIG_BACKUPMODE == "n" ]]; then
			askFor $MSG_ASK_TYPE1 "dd|tar|rsync"
		else
			askFor $MSG_ASK_TYPE2 "tar|rsync"
		fi
		CONFIG_BACKUPTYPE=$REPLY
		
		regex="dd|tar"
		if [[ $CONFIG_BACKUPTYPE =~ $regex ]]; then
			askFor $MSG_ASK_COMPRESS $(getLocalizedMessage $MSG_ANSWER_CHARS_YES_NO)
			CONFIG_COMPRESS=$REPLY
		fi
	
		askFor $MSG_ASK_KEEP "[1-9]|[1-4][0-9]|[5][0-2]"
		CONFIG_KEEP_BACKUPS=$REPLY
	
		askFor $MSG_ASK_DETAILS $(getLocalizedMessage $MSG_ANSWER_CHARS_YES_NO)
		CONFIG_DETAILED_MESSAGES=$REPLY
		
		askFor $MSG_CONF_OK $(getLocalizedMessage $MSG_ANSWER_CHARS_YES_NO)
	
		[[ $REPLY =~ $YES ]] && done=1
	done
	
}

function updateConfig() {
	
	local rc msg
	
	writeToConsole $MSG_UPDATING_CONFIG "$CONFIG_FILE_ABS_PATH"
	
	msg=${MESSAGE_LANGUAGE^^*}
	sed -i "s/^DEFAULT_LANGUAGE=.*\$/DEFAULT_LANGUAGE=\"$msg\"/" $CONFIG_FILE_ABS_PATH

	[[ $CONFIG_BACKUPMODE == "n" ]] && CONFIG_BACKUPMODE=0 || CONFIG_BACKUPMODE=1
	sed -i "s/^DEFAULT_PARTITIONBASED_BACKUP=.*\$/DEFAULT_PARTITIONBASED_BACKUP=\"$CONFIG_BACKUPMODE\"/" $CONFIG_FILE_ABS_PATH
	sed -i "s/^DEFAULT_BACKUPTYPE=.*\$/DEFAULT_BACKUPTYPE=\"$CONFIG_BACKUPTYPE\"/" $CONFIG_FILE_ABS_PATH

	[[ $CONFIG_COMPRESS == "j" ]] && CONFIG_COMPRESS=1 || CONFIG_COMPRESS=0
	sed -i "s/^DEFAULT_ZIP_BACKUP=.*\$/DEFAULT_ZIP_BACKUP=\"$CONFIG_COMPRESS\"/" $CONFIG_FILE_ABS_PATH
	
	sed -i "s/^DEFAULT_KEEPBACKUPS=.*\$/DEFAULT_KEEPBACKUPS=\"$CONFIG_KEEP_BACKUPS\"/" $CONFIG_FILE_ABS_PATH
	
	[[ $CONFIG_DETAILED_MESSAGES == "n" ]] && CONFIG_DETAILED_MESSAGES=0 || CONFIG_DETAILED_MESSAGES=1 
	sed -i "s/^DEFAULT_MSG_LEVEL=.*$/DEFAULT_MSG_LEVEL=\"$CONFIG_DETAILED_MESSAGES\"/" $CONFIG_FILE_ABS_PATH
}

function usageEN() {
    echo "$GIT_CODEVERSION"
    echo ""
    echo "Install and configure raspiBackup.sh"
    echo ""
    echo "Usage: sudo $0 [-c] [-l DE | EN] [-h]"
	echo ""
	echo "       No options will start a configuration wizzard and prompt for the most important configuration parameters"
	echo ""
    echo "       -c - Install default config file in $CONFIG_FILE_ABS_PATH"
    echo "       -l - Install English (EN) or German (DE) version of the config file"
	echo "       If -c is used without -l the current system language is used for the config file"
}

function usageDE() {
    echo "$GIT_CODEVERSION"
    echo ""
    echo "Installiere und konfiguriere raspiBackup.sh"
    echo ""
    echo "Aufruf: sudo $0 [-c] [-l DE | EN] [-h]"
	echo ""
	echo "       Falls keine Optionen angegeben wurde werden die wichtigsten Konfigurationsparameter abgefragt"
	echo ""
    echo "       -c - Installiert die Standardkonfigurationsdatei in $CONFIG_FILE_ABS_PATH"
    echo "       -l - Installiert die englische (EN) oder Deutsche (DE) Version der Konfigurationsdatei"
	echo "       Wenn -c ohne -l benutzt wird wird die Systemsprache für die Konfigurationsdatei benutzt"
}

# Borrowed from http://stackoverflow.com/questions/85880/determine-if-a-function-exists-in-bash

fn_exists() {
  [ `type -t $1`"" == 'function' ]
}

function usage() {
	
	LANG_SUFF=$MESSAGE_LANGUAGE

	local func="usage${LANG_SUFF}"

	if ! fn_exists $func; then     
		func="usageEN"
	fi
	
	$func

}

passedOpts="$@"

INSTALL_CONFIG=0

trapWithArg cleanup SIGINT SIGTERM EXIT

while getopts ":cl:h" opt; do
   case $opt in   
		c)  INSTALL_CONFIG=1
			;;
		l) 	LANG_PRF=$(tr '[:lower:]' '[:upper:]' <<< "$OPTARG")
			if [[ $LANG_PRF != "DE" && $LANG_PRF != "EN" ]]; then
				writeToConsole $MSG_INVALID_MESSAGE "$LANG_PRF"
				parameterError
			else
				MESSAGE_LANGUAGE=$LANG_PRF
			fi
			INSTALL_CONFIG=1
			;;
		h)  usage
			exit 0
			;;
		\?)	writeToConsole $MSG_INVALID_OPTION "-$OPTARG"
			parameterError
			;;
		:) 	writeToConsole $MSG_PARAMETER_EXPECTED "-$OPTARG"
			parameterError
			;;
    esac
done

if (( $UID != 0 )); then
	writeToConsole $MSG_SUDO_REQUIRED "$0 $passedOpts"
	parameterError
fi

rm $LOG_FILE &>/dev/null

case $MESSAGE_LANGUAGE in
	DE) confFile=${CONFIG_DOWNLOAD_FILE["DE"]}
		;;
	*) confFile=${CONFIG_DOWNLOAD_FILE["EN"]}
		;;
esac

writeToConsole $MSG_VERSION "$GIT_CODEVERSION"

INSTALLATION_STARTED=1

if (( $INSTALL_CONFIG )); then
	downloadCode
	downloadConfig
else
	configWizzard
	downloadCode
	downloadConfig
	updateConfig
fi

INSTALLATION_SUCCESSFULL=1
