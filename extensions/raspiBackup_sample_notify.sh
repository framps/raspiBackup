#!/bin/bash
########################################################################################################################
#
# Function: Sample notification extension
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for additional information
#
########################################################################################################################
#
#    Copyright (c) 2023 framp at linux-tips-and-tricks dot de
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
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.#
#
#######################################################################################################################

NOTIFICATION_EXTENSION_MYSELF="$(basename "${BASH_SOURCE}")"
NOTIFICATION_EXTENSION_MYNAME=${NOTIFICATION_EXTENSION_MYSELF%.*}
NOTIFICATION_EXTENSION_CONFIG_FILE="$CONFIG_DIR/${NOTIFICATION_EXTENSION_MYNAME}.conf"

MSG_EXT_SAMPLE_NOTIFICATION="${NOTIFICATION_EXTENSION_MYNAME}1"
MSG_EN[$MSG_EXT_SAMPLE_NOTIFICATION]="RBK1001I: %s: %s"
MSG_DE[$MSG_EXT_SAMPLE_NOTIFICATION]="RBK1001I: %s: %s"
MSG_EXT_SAMPLE_NOTIFICATION_UNPROTECTED_PROPERTYFILE="${NOTIFICATION_EXTENSION_MYNAME}2"
MSG_EN[$MSG_EXT_SAMPLE_NOTIFICATION_UNPROTECTED_PROPERTYFILE]="RBK1002W: Unprotected file: %s"
MSG_DE[$MSG_EXT_SAMPLE_NOTIFICATION_UNPROTECTED_PROPERTYFILE]="RBK1002iW: Ungeschützte Datei: %s"

# ################################################################################################
# ################################################################################################
# ################################################################################################
# NOTE : Don't log any sensitive information like access credentials to the notification service !
# ################################################################################################
# ################################################################################################
# ################################################################################################

logEntry

# access raspiBackup return code
rc="$1"
writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_SAMPLE_NOTIFICATION "RC" "$rc"

# Access log file"
writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_SAMPLE_NOTIFICATION "LOG_FILE" "========== $LOG_FILE BEGIN =========="
head -n 3 $LOG_FILE
writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_SAMPLE_NOTIFICATION "LOG_FILE" "========== $LOG_FILE END =========="

# Acces message file"
startMsg="$(grep "RBK0009I" $MSG_FILE)"
writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_SAMPLE_NOTIFICATION "Startmessage" "$startMsg"

stopMsg="$(grep "RBK0010I" $MSG_FILE)"
writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_SAMPLE_NOTIFICATION "Stopmessage" "$stopMsg"

# access raspiBackup return code
writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_SAMPLE_NOTIFICATION "RC" "$1"

# source any configuration definitions
# They have to be in bash assignment syntax
# Example SAMPLE_NOTIFICATION_PWD="mySecretPassword"
writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_SAMPLE_NOTIFICATION "Config file:" "$NOTIFICATION_EXTENSION_CONFIG_FILE"

writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_SAMPLE_NOTIFICATION "Config file:" "$NOTIFICATION_EXTENSION_CONFIG_FILE"

if [[ -f $NOTIFICATION_EXTENSION_CONFIG_FILE ]]; then
# access an extension specific config file which may contain sensitive data
# therefore test if it has not any 077 bit set
	attrs="$(stat -c %a $NOTIFICATION_EXTENSION_CONFIG_FILE)"
	
	if (( ( 0$attrs & 077 ) != 0 )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_SAMPLE_NOTIFICATION_UNPROTECTED_PROPERTYFILE "$NOTIFICATION_EXTENSION_CONFIG_FILE"
		exitError $RC_EXTENSION_ERROR		 
	fi
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_SAMPLE_NOTIFICATION "Sourcing config file" "$NOTIFICATION_EXTENSION_CONFIG_FILE"

	source "$NOTIFICATION_EXTENSION_CONFIG_FILE"
	echo "UID: $DEFAULT_SAMPLE_NOTIFY_USERID"
	echo "PWD: $DEFAULT_SAMPLE_NOTIFY_PASSWORD"
fi
logExit
