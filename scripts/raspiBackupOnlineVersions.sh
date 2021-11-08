#!/bin/bash

#######################################################################################################################
#
# 	  Retrieve version and commit sha/revision of scripts of raspiBackup
#	  - raspiBackup.sh
#    - raspiBackupInstallUI.sh
#    - raspiBackup.sh (Beta)
#
# 	  Visit http://www.linux-tips-and-tricks.de/raspiBackup for latest code and other details
#
#######################################################################################################################
#
#    Copyright (c) 2020 framp at linux-tips-and-tricks dot de
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

GIT_DATE="$Date$"
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<< $GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<< $GIT_DATE)
GIT_COMMIT="$Sha1$"
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<< $GIT_COMMIT | sed 's/\$//')

MYHOMEDOMAIN="www.linux-tips-and-tricks.de"
MYHOMEURL="https://$MYHOMEDOMAIN"
DOWNLOAD_URL="$MYHOMEURL/downloads/raspibackup-sh/download"
BETA_DOWNLOAD_URL="$MYHOMEURL/downloads/raspibackup-beta-sh/download"
INSTALLER_DOWNLOAD_URL="$MYHOMEURL/downloads/raspibackupinstallui-sh/download"
INSTALLER_BETA_DOWNLOAD_URL="$MYHOMEURL/downloads/raspibackupinstallui-beta-sh/download"
PROPERTIES_DOWNLOAD_URL="$MYHOMEURL/downloads/raspibackup0613-properties/download"
CONF_DE_DOWNLOAD_URL="$MYHOMEURL/downloads/raspibackup-de-conf/download"
CONF_EN_DOWNLOAD_URL="$MYHOMEURL/downloads/raspibackup-en-conf/download"

DOWNLOAD_TIMEOUT=60 # seconds
DOWNLOAD_RETRIES=3

function analyze() { # fileName url
	tmp=$(mktemp)
	wget $2 -q --tries=$DOWNLOAD_RETRIES --timeout=$DOWNLOAD_TIMEOUT -O $tmp

	# GIT_COMMIT="$Sha1$"
	sha="$(grep "^GIT_COMMIT=" "$tmp" | cut -f 2 -d ' '| sed  -e "s/[\$\"]//g")"
	if [[ -z "$sha" ]]; then
		sha="$(grep "GIT_COMMIT=" "$tmp" | cut -f 3-4 -d ' ' )"
	fi
	if [[ -z "$sha" ]]; then
		sha="$(grep 'Sha1: ' $tmp | cut -f 3-4 -d ' ' )"
	fi
	
	sha="$(sed  -e "s/[\$\"]//g" <<< "$sha")"

	# VERSION="0.6.5-beta"	# -beta, -hotfix or -dev suffixes possible
	version="$(grep -e "^VERSION=" "$tmp" | cut -f 2 -d = | sed  -e "s/\"//g" -e "s/[[:space:]]*#.*//")"
	if [[ -z "$version" ]]; then
		version="$(grep -e "^VERSION_CONFIG=" "$tmp" | cut -f 2 -d = | sed  -e "s/\"//g" -e "s/[[:space:]]*#.*//")"
	fi

	# GIT_DATE="$Date$"
	date="$(grep "^GIT_DATE=" "$tmp" | cut -f 2-3 -d ' ' )"
	if [[ -z "$date" ]]; then
		date="$(grep "GIT_DATE=" "$tmp" | cut -f 3-4 -d ' ' )"
	fi
	if [[ -z "$date" ]]; then
		date="$(grep '$Date: ' $tmp | cut -f 3-4 -d ' ' )"
	fi

	printf "%-30s: Version: %-10s Date: %-20s Sha: %-10s\n" "$1" "$version" "$date" "$sha"
	rm $tmp
}	

analyze "raspiBackup" $DOWNLOAD_URL 
analyze "raspiBackup_beta" $BETA_DOWNLOAD_URL
analyze "raspiBackupInstallUI" $INSTALLER_DOWNLOAD_URL
analyze "raspiBackupInstallUI_beta" $INSTALLER_BETA_DOWNLOAD_URL
analyze "raspiBackup0613.properties" $PROPERTIES_DOWNLOAD_URL
analyze "raspiBackup_de.conf" $CONF_DE_DOWNLOAD_URL
analyze "raspiBackup_en.conf" $CONF_EN_DOWNLOAD_URL
