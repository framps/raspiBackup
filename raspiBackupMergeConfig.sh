#!/bin/bash

#######################################################################################################################
#
#   Merge raspiBackup config files
#
#   Helper to create a new config file based on a new config file version and merge with the current local config file
#   The generated config file has to be updated manually and finally copied to /usr/local/etc/raspiBackup.conf.
#
#   For detailed instructions how to use the script see https://www.linux-tips-and-tricks.de/en/configuration-update/
#
#######################################################################################################################
#
#   Copyright (c) 2020 framp at linux-tips-and-tricks dot de
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

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}
VERSION="0.1.2"

set +u;GIT_DATE="$Date: 2020-04-24 19:16:27 +0200$"; set -u
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<< $GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<< $GIT_DATE)
set +u;GIT_COMMIT="$Sha1: 15922e8$";set -u
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<< $GIT_COMMIT | sed 's/\$//')

GIT_CODEVERSION="$MYSELF $VERSION, $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"

ORIG_CONFIG="/usr/local/etc/raspiBackup.conf"
BACKUP_CONFIG="/usr/local/etc/raspiBackup.conf.bak"
NEW_CONFIG="/usr/local/etc/raspiBackup.conf.new"
MERGED_CONFIG="/usr/local/etc/raspiBackup.conf.merged"
localNewConfig=0

DOWNLOAD_TIMEOUT=60 # seconds

MSG_LEVEL_MINIMAL=0

MSG_SUPPORTED_REGEX="EN|DE"
MSG_LANG_FALLBACK="EN"

NEW_OPTION_TRAILER="# >>>>> NEW OPTION added in config version %s <<<<< "
DELETED_OPTION_TRAILER="# >>>>> OPTION DELETED in config version %s <<<<< "

CONFIG_VERSION="N/A"

MSG_EN=1      # english	(default)
MSG_DE=1      # german

declare -A MSG_EN
declare -A MSG_DE

declare -A MSG_HEADER=( ['I']="---" ['W']="!!!" ['E']="???" )

MSG_CNT=500

MSG_UNDEFINED=$((MSG_CNT++))
MSG_EN[$MSG_UNDEFINED]="RBK0500E: Undefined messageid"
MSG_DE[$MSG_UNDEFINED]="RBK0500E: Unbekannte Meldungsid"
MSG_STARTING=$((MSG_CNT++))
MSG_EN[$MSG_STARTING]="RBK0501I: $MYSELF v$VERSION, $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"
MSG_DE[$MSG_STARTING]="RBK0501I: $MYSELF v$VERSION, GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"
MSG_RUNASROOT=$((MSG_CNT++))
MSG_EN[$MSG_RUNASROOT]="RBK0502E: $MYSELF has to be started as root. Try 'sudo %s%s'."
MSG_DE[$MSG_RUNASROOT]="RBK0502E: $MYSELF muss als root gestartet werden. Benutze 'sudo %s%s'."
MSG_DOWNLOADING=$((MSG_CNT++))
MSG_EN[$MSG_DOWNLOADING]="RBK0503I: Downloading file %s from %s."
MSG_DE[$MSG_DOWNLOADING]="RBK0503I: Datei %s wird von %s downloaded."
MSG_SAVING_ACTUAL_VERSION=$((MSG_CNT++))
MSG_EN[$MSG_SAVING_ACTUAL_VERSION]="RBK0504I: Saving current version %s to %s."
MSG_DE[$MSG_SAVING_ACTUAL_VERSION]="RBK0504I: Aktuelle Version %s wird in %s gesichert."
MSG_MERGING_VERSION=$((MSG_CNT++))
MSG_EN[$MSG_MERGING_VERSION]="RBK0505I: Merging current version %s with %s."
MSG_DE[$MSG_MERGING_VERSION]="RBK0505I: Aktuelle Version %s wird mit %s zusammengefügt."
MSG_MERGED_FILE=$((MSG_CNT++))
MSG_EN[$MSG_MERGED_FILE]="RBK0507W: Now resolve %s conflicts and %s deletions in %s and copy it to %s."
MSG_DE[$MSG_MERGED_FILE]="RBK0507W: Nun %s Konflikte und %s Löschungen manuell in %s lösen und nach %s kopieren."
MSG_UNMERGED_FILE=$((MSG_CNT++))
MSG_EN[$MSG_UNMERGED_FILE]="RBK0507I: No conflicts detected in %s. Now review and copy it to %s."
MSG_DE[$MSG_UNMERGED_FILE]="RBK0507I: Keine Konflikte in %s entdeckt. Noch einmal kontrollieren und dann nach %s kopieren."
MSG_DOWNLOAD_FAILED=$((MSG_CNT++))
MSG_EN[$MSG_DOWNLOAD_FAILED]="RBK0508E: Download of %s failed. HTTP code: %s."
MSG_DE[$MSG_DOWNLOAD_FAILED]="RBK0508E: %s kann nicht aus dem Netz geladen werden. HTTP code: %s."

function writeToConsole() {  # msglevel messagenumber message
	local msg level timestamp

	level=$1
	shift

	msg="$(getMessageText "L" "$@")"

	local msgNumber=$(cut -f 2 -d ' ' <<< "$msg")
	local msgSev=${msgNumber:7:1}

	if [[ $msgSev == "E" ]]; then
		echo -e "$msg" >&2
	else
		echo -e "$msg" >&1
	fi

	unset noNL
}

function getMessageText() {         # languageflag messagenumber parm1 parm2 ...
	local msg p i s msgVar

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

	printf -v msg "$msg" "${@:3}"

	local msgPref="${msg:0:3}"
	if [[ $msgPref == "RBK" ]]; then								# RBK0001E
		local severity="${msg:7:1}"
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

writeToConsole $MSG_LEVEL_MINIMAL $MSG_STARTING

if (( $UID != 0 )); then
   writeToConsole $MSG_LEVEL_MINIMAL $MSG_RUNASROOT "$0" "$@"
   exit 1
fi

rm -f $MERGED_CONFIG &>/dev/null

# use a local new config file
if (( $# == 1 )); then
   if [[ -f "$1" ]]; then
      NEW_CONFIG="$1"
      localNewConfig=1
   else
      echo "??? $1 not found"
      exit 42
   fi
fi

# detect language the config file is in
lang="en"
l=$(grep -e ^VERSION_.*CONF "$ORIG_CONFIG")
if [[ "$l" =~ _DE ]]; then
   lang="de"
fi

DL_URL="https://www.linux-tips-and-tricks.de/downloads/raspibackup-$lang-conf/download"

if (( ! $localNewConfig )); then
	# download new config file
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_DOWNLOADING "$NEW_CONFIG" "$DL_URL"
	httpCode=$(curl -sSL -o "$NEW_CONFIG" -m $DOWNLOAD_TIMEOUT -w %{http_code} -L "$DL_URL")
	if [[ ${httpCode:0:1} != "2" ]]; then
      writeToConsole $MSG_LEVEL_MINIMAL $MSG_DOWNLOAD_FAILED "$NEW_CONFIG" "$httpCode"
      exit 42
   fi
fi

# save old config
writeToConsole $MSG_LEVEL_MINIMAL $MSG_SAVING_ACTUAL_VERSION  "$ORIG_CONFIG" "$BACKUP_CONFIG"
cp $ORIG_CONFIG $BACKUP_CONFIG

# process NEW CONFIG FILE
writeToConsole $MSG_LEVEL_MINIMAL $MSG_MERGING_VERSION  "$ORIG_CONFIG" "$NEW_CONFIG"
merges=0
deleted=0

# process new config file and merge old options

while read line; do
   if [[ -n "$line" && ! "$line" =~ ^.*# ]]; then	# skip comment or empty lines
      KW="$(cut -d= -f1 <<< "$line")"				# retrieve keyword
      VAL="$(cut -d= -f2 <<< "$line" | sed 's/"//g')"	# retrieve value

      if [[ "$KW" =~ VERSION_.*CONF ]]; then		# add new version number
		echo "$line" >> $MERGED_CONFIG
		CONFIG_VERSION="$VAL"
		continue
	  fi

      OC_line="$(grep "^$KW=" $ORIG_CONFIG)"		# retrieve old option line
      if (( ! $? )); then							# new option found
		OW="$(cut -d= -f2- <<< "$OC_line" )"		# retrieve old option value
        echo "$KW=$OW" >> $MERGED_CONFIG			# use old option value
      else
		printf "$NEW_OPTION_TRAILER\n" "$CONFIG_VERSION" >> $MERGED_CONFIG
		echo "$line" >> $MERGED_CONFIG				# add new option
	  fi
   else
      echo "$line" >> $MERGED_CONFIG				# copy comment  or empty line
   fi
done < "$NEW_CONFIG"

# check in old config file which options were deleted in new config file

while read line; do
   if [[ -n "$line" && ! "$line" =~ ^.*# ]]; then	# skip comment or empty lines
      KW="$(cut -d= -f1 <<< "$line")"				# retrieve keyword

      if [[ "$KW" =~ VERSION_.*CONF ]]; then		# skip version number
		continue
	  fi

      NC_line="$(grep "^$KW=" $NEW_CONFIG)"			# check if it's still the new config file
      if (( $? )) && [[ $KW != "UUID" ]]; then		# option not found, it was deleted
		echo "" >> $MERGED_CONFIG
		printf "$DELETED_OPTION_TRAILER\n" "$CONFIG_VERSION" >> $MERGED_CONFIG
		echo "# $line" >> $MERGED_CONFIG			# insert deleted config line as comment
        (( deleted ++ ))
      fi
   fi
done < "$ORIG_CONFIG"

UUID="$(grep "^UUID=" $ORIG_CONFIG)"
echo "" >> $MERGED_CONFIG
echo "# GENERATED - DO NOT DELETE" >> $MERGED_CONFIG
echo "$UUID" >> $MERGED_CONFIG

if (( $merges > 0 || $deleted > 0 )); then
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_MERGED_FILE  "$merges" "$deleted" "$MERGED_CONFIG" "$ORIG_CONFIG"
else
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_UNMERGED_FILE  "$MERGED_CONFIG" "$ORIG_CONFIG"
fi
