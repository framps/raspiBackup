#!/bin/bash
#
#######################################################################################################################
#
# Send an email using the functions from raspiBackup, based of version 0.6.3.1
# Written by kmbach 2017
#
# Using: raspiImageMail.sh <msgTitle> <msg> [<attach>]
#        The condition is that mail is configured in raspiBackup.conf and works in raspiBackup.
#
# Visit http://www.linux-tips-and-tricks.de/raspiBackup and https://github.com/framps/raspiBackup to get more 
# details about raspiBackup
#
#######################################################################################################################
#
#    Copyright (C) 2017 kmbach 
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

VERSION="0.1"

if [[ ! $(which raspiBackup.sh) ]]; then
	echo "raspiBackup.sh not found"
	exit 1
fi

function usage() {
	echo "Syntax: $MYSELF <msgTitle> <msg> [<attach>]"
}	

# query invocation parms
if [[ $# < 2 ]]; then
	echo "??? Missing Mail parameter"
	usage
	exit 1
fi	

MSG_TITLE="$1"
MSG="$2"
APPEND="${3:-""}"

# defaults for use functions from raspiBackup.sh
EMAIL_EXTENSION_PROGRAM="mailext"
EMAIL_MAILX_PROGRAM="mail"
EMAIL_SSMTP_PROGRAM="ssmtp"
EMAIL_SENDEMAIL_PROGRAM="sendEmail"
NEWS_AVAILABLE=0
NOTIFY_UPDATE=0
LOG_FILE=""
APPEND_LOG=0
MYNAME="raspiBackup"
MYNAME_ABS="$(dirname $0)""/""$MYNAME"".sh"

# other defines
NL=$'\n'

# dummys to use the original features of raspiBackup.sh
function logItem() { : ;} 
function logExit() { : ;} 
function logEntry() { : ;} 
function assertionFailed() { : ;}  

# functions load from raspiBackup.sh. 
# The closing bracket of the function definition must be at the beginning of the line
. /dev/stdin <<EOF
$(sed -n '/^function *readConfigParameters\(\)/,/^}/p' $MYNAME_ABS)
$(sed -n '/^function *findUser\(\)/,/^}/p' $MYNAME_ABS)
$(sed -n '/^function *sendEMail\(\)/,/^}/p' $MYNAME_ABS)
EOF

# include raspiBackup.conf
readConfigParameters

# set parameters from raspiBackup.conf 
EMAIL=$DEFAULT_EMAIL
EMAIL_PROGRAM=$DEFAULT_MAIL_PROGRAM
EMAIL_PARMS=$DEFAULT_EMAIL_PARMS

# check if email includes attachment
if [[ $APPEND != "" ]]; then
    if [[ -f $APPEND ]]; then
        APPEND_LOG=1
	    LOG_FILE="$APPEND"
    else
        MSG="$MSG$NL$NL$APPEND not exist." 
    fi    
fi

# mail parameters are defined in .conf
if [[ -n $EMAIL ]]; then
    sendEMail "$MSG" "$MSG_TITLE" &>/dev/null
    RC=$?
else
    RC=1
fi 

exit $RC

