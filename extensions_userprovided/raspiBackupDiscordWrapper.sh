#!/bin/bash

#######################################################################################################################
#
# 	Sample script to wrap raspiBackup.sh in order to send Discord notification message once raspiBackup is finished
#	Tested with raspiBackup.sh version: 0.6.8 CommitSHA: 120287b CommitDate: 2022-12-15 CommitTime: 16:48:38
#	relies on raspiBackup variables:
#	  # BACKUP_TARGETDIR refers to the backupdirectory just created. Used when raspiBackup succeeded to read the raspiBackup.msg file content
#	In case raspiBakup failed, the file raspiBackup.msg file under HOME folder of calling user is used
#
# 	Visit http://www.linux-tips-and-tricks.de/raspiBackup for details about raspiBackup
#
#	NOTE: This is sample code how to extend functionality of raspiBackup and is provided as is with no support.
#
#	--> Requires:
#		curl (https://curl.se):
#			for sending POST command to Discord WebHook
#			Tested with version: curl 7.64.0
#		jq (https://stedolan.github.io/jq/):
#			For JSON manipulation in shell
#			Tested with version jq-1.5-1-a5b5cbe
#
#	--> Configuration:
# 		-> file: /usr/local/etc/discordWrapper.conf
#		-> Content of the config file:
#	 	# URL of the Discord WebHook where to send the message. Adapt to your case
#		CONFIG_DISCORD_URL="https://discord.com/api/webhooks/1234567890.../abcdef...."
#
#		# Possible Colors to be used for Discord Embed message. Must be integer value in base 10 for RGB clolor coding. Refer to Discord documentation (https://discord.com/developers/docs/intro)
# 		COLOR_BLUE=255
#		COLOR_RED=16711680
#		COLOR_GREEN=65280
#
# 		# Color to be used depending on the raspiBackup execution result: success or failure
#	        # each line shall refer to one of the color defined here upper
# 		CONFIG_COLOR_DEFAULT=$COLOR_BLUE
# 		CONFIG_COLOR_SUCCESS=$COLOR_GREEN
# 		CONFIG_COLOR_FAILURE=$COLOR_RED
#
#
#######################################################################################################################
#
#   Copyright (c) 2013-2022 framp at linux-tips-and-tricks dot de
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#######################################################################################################################

set -euf -o pipefail

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}
VERSION="0.0.1"

set +u;GIT_DATE="$Date$"; set -u
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<< $GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<< $GIT_DATE)
set +u;GIT_COMMIT="$Sha1$";set -u
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<< $GIT_COMMIT | sed 's/\$//')

GIT_CODEVERSION="$MYSELF $VERSION, $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"


# add pathes if not already set (usually not set in crontab)

if [[ -e /bin/grep ]]; then
   PATHES="/bin /sbin /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin"
   for p in $PATHES; do
      if ! /bin/grep -E -q "[\^:]$p[:$]" <<< $PATH; then
         [[ -z $PATH ]] && export PATH=$p || export PATH="$p:$PATH"
      fi
   done
fi


function readVars() {
	if [[ -f /tmp/raspiBackup.vars ]]; then
		source /tmp/raspiBackup.vars						# retrieve some variables from raspiBackup for further processing
# now following variables are available for further backup processing
# BACKUP_TARGETDIR refers to the backupdirectory just created
# BACKUP_TARGETFILE refers to the dd backup file just created
	else
		echo "/tmp/raspiBackup.vars not found"
		exit 42
	fi
}



#### DISCORD SECTION

# read config file
source /usr/local/etc/discordWrapper.conf

###########################################
### EXPECTED CONFIG FILE CONTENT
#
# URL of the Discord WebHook where to send the message. Adapt to your case
# CONFIG_DISCORD_URL="https://discord.com/api/webhooks/1234567890.../abcdef...."
#
# Possible Colors to be used for Discord Embed message.
# COLOR_BLUE=255
# COLOR_RED=16711680
# COLOR_GREEN=65280
#
#
# Color to be used depending on the raspiBackup execution result: success or failure
# CONFIG_COLOR_DEFAULT=$COLOR_BLUE
# CONFIG_COLOR_SUCCESS=$COLOR_GREEN
# CONFIG_COLOR_FAILURE=$COLOR_RED
#
#
##########################################

DISC_CONTENT=""
DISC_TITLE=""
DISC_DESC=""
DISC_COLOR=$CONFIG_COLOR_DEFAULT

###########################################
### Default JSON message for Discord notification with a colored embed
###########################################
DEFAULTJSON=$(cat<<EOS
{"content": "DISC CONTENT",
  "embeds": [{
    "title": "DISC TITLE",
    "description": "DISC DESC",
    "color": "255"
  }]
}
EOS
)


# holds the JSON data to post
DISCORD_JSON=""
###########################################
### Function to construct the JSON data to be posted
# It requires jq to be installed
# there is not parameter
# it uses the following script variable:
# DISC_CONTENT
# DISC_TITLE
# DISC_DESC
# DISC_COLOR
#
# these variables are set in function send_discord
###########################################
function build_json() {
        DISCORD_JSON=$(jq \
                        --arg cont "$DISC_CONTENT" \
                        --arg title "$DISC_TITLE" \
                        --arg color "$DISC_COLOR" \
                        --arg desc "$DISC_DESC" \
                       '.content=$cont | .embeds[0].title=$title | .embeds[0].description=$desc | .embeds[0].color=$color' <<< "$DEFAULTJSON")
}
###########################################
### Function to set variables for JSON message, and calls JSON construction function: build_json
# it then send the message to discord using CURL
# $1 contains the raspiBackup return code in order to adapt the message embed's color
###########################################
function send_discord() { # $1:status of the operation, 0=) success, not 0 is failure
        local discord_color=$CONFIG_COLOR_DEFAULT
        if [[ $1 -ne  0 ]]; then
                discord_color=$CONFIG_COLOR_FAILURE
                STATUS="FAILURE. Error code is: $1"
                TITLE_SUFFIX="failed !!!"
        else
                discord_color=$CONFIG_COLOR_SUCCESS
                STATUS="SUCCESS."
                TITLE_SUFFIX="finished successfully."
        fi
        DISC_CONTENT="Raspi Backup Status: $(date)"
        DISC_TITLE="Raspi Backup $TITLE_SUFFIX"
	# just to ensure not to fail in case the message file is not found and send a minimal status message without details
	[ -z "$MSG_CONTENT_FILE" ] && DISC_DESC="The raspiBackup operation just finished with the status: $STATUS" || DISC_DESC="The raspiBackup operation just finished with the status: $STATUS $(<"$MSG_CONTENT_FILE")"

        DISC_COLOR=$discord_color

        build_json

        DISCORD_URL=$CONFIG_DISCORD_URL

        curl -s -H "Content-Type: application/json" -X POST -d "$DISCORD_JSON" $DISCORD_URL > /dev/null
        return $?
}

#### END of DISCORD SECTION

# main program

if [[ -z $CONFIG_DISCORD_URL ]]; then
	echo "$CONFIG_DISCORD_URL:No Valid Discord WebHook URL configured. Check configuration in /usr/local/etc/rpibackup_dcwrap.conf"
	exit 1
fi

###############################################
# call raspiBackup with the parameters you want
# add -m detailed for detailed messages
# add -F parameter for testing
raspiBackup.sh
rc=$?

# retrieve variables from last raspiBackup execution
readVars

MSG_FILENAME="raspiBackup"
MSG_FILENAME_SUFFIX=".msg"
# user currently calling the script, if called with sudo it gives the sudoer user name
USER=$(logname)
# home folder of the user
MSG_FILE_DIR="$(eval echo "~$USER")"

MSG_CONTENT_FILE=""

if (( $rc == 0 )); then # SUCCESS
#	echo "Backup succeeded :-)"
	# in case of success the Message file is under BACKUP_TARGETDIR/raspiBackup/msg
	[ -f "$BACKUP_TARGETDIR/$MSG_FILENAME$MSG_FILENAME_SUFFIX" ] &&	MSG_CONTENT_FILE=$BACKUP_TARGETDIR/$MSG_FILENAME$MSG_FILENAME_SUFFIX || MSG_CONTENT_FILE=""
else                    # FAILURE
#	echo "Backup failed with rc $rc :-("
	# in case of error, the Message file is under /USER_HOME/
        [ -f "$MSG_FILE_DIR/$MSG_FILENAME$MSG_FILENAME_SUFFIX" ] &&  MSG_CONTENT_FILE=$MSG_FILE_DIR/$MSG_FILENAME$MSG_FILENAME_SUFFIX || MSG_CONTENT_FILE=""
fi

#echo "status: $rc --> file in $MSG_CONTENT_FILE"

send_discord $rc

