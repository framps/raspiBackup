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

MSG_EXT_SAMPLE_NOTIFICATION="ext_sample_notification"
MSG_EN[$MSG_EXT_SAMPLE_NOTIFICATION]="RBK1001I: Access %s: %s"
MSG_DE[$MSG_EXT_SAMPLE_NOTIFICATION]="RBK1001I: Zugriff auf %s: %s"

logEntry

# Access log file"
writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_SAMPLE_NOTIFICATION "LOG_FILE" "$LOG_FILE"

head -n 100 $LOG_FILE

# Acces message file"
writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_SAMPLE_NOTIFICATION "MSG_FILE" "$MSG_FILE"

startMsg="$(grep "RBK0009I" $MSG_FILE)"
writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_SAMPLE_NOTIFICATION "Startmessage" "$startMsg"

stopMsg="$(grep "RBK0010I" $MSG_FILE)"
writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_SAMPLE_NOTIFICATION "Stopmessage" "$stopMsg"

# access raspiBackup return code
writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_SAMPLE_NOTIFICATION "RC" "$1"

logExit

