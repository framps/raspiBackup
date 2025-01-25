#!/bin/bash

#######################################################################################################################
#
# 	  Retrieve version and commit sha/revision of files offered by raspiBackup for download
#
# 	  Visit http://www.linux-tips-and-tricks.de/raspiBackup for latest code and other details
#
#######################################################################################################################
#
#    Copyright (c) 2021-2025 framp at linux-tips-and-tricks dot de
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

#shellcheck disable=SC2034,SC2154
# (warning): Date is referenced but not assigned (did you mean 'DATE'?).
# (warning): GIT_DATE appears unused. Verify use (or export if used externally).
GIT_DATE="$Date$"
#shellcheck disable=SC2034,SC2154
# (warning): Sha1 is referenced but not assigned (did you mean 'DATE'?).
# (warning): GIT_COMMIT appears unused. Verify use (or export if used externally).
GIT_COMMIT="$Sha1$"

MYHOMEDOMAIN="www.linux-tips-and-tricks.de"
MYHOMEURL="https://$MYHOMEDOMAIN"
DOWNLOAD_URL="$MYHOMEURL/raspiBackup/raspiBackup.sh"
BETA_DOWNLOAD_URL="$MYHOMEURL/raspiBackup/beta/raspiBackup.sh"
INSTALLER_DOWNLOAD_URL="$MYHOMEURL/raspiBackup/raspiBackupInstallUI.sh"
INSTALLER_BETA_DOWNLOAD_URL="$MYHOMEURL/raspiBackup/beta/raspiBackupInstallUI.sh"
PROPERTIES_DOWNLOAD_URL="$MYHOMEURL/raspiBackup/raspiBackup.properties"
CONF_DE_DOWNLOAD_URL="$MYHOMEURL/raspiBackup/raspiBackup_de.conf"
CONF_EN_DOWNLOAD_URL="$MYHOMEURL/raspiBackup/raspiBackup_en.conf"

DOWNLOAD_TIMEOUT=60 # seconds
DOWNLOAD_RETRIES=3

SHA="JFNoYTE6Cg=="
DATE="JERhdGU6Cg=="

SHA="$(base64 -d <<< "$SHA")"
DATE="$(base64 -d <<< "$DATE")"

function analyze() { # fileName url
	tmp=$(mktemp)
	wget "$2" -q --tries="$DOWNLOAD_RETRIES" --timeout="$DOWNLOAD_TIMEOUT" -O "$tmp"

	# GIT_COMMIT="$Sha1$"
	sha="$(grep "^GIT_COMMIT=" "$tmp" | cut -f 2 -d ' '| sed  -e "s/[\$\"\']//g")"
	if [[ -z "$sha" ]]; then
		sha="$(grep "GIT_COMMIT=" "$tmp" | cut -f 3-4 -d ' ' )"
	fi
	if [[ -z "$sha" ]]; then
		sha="$(grep "$SHA" "$tmp" | cut -f 3-4 -d ' ' )"
	fi

	#shellcheck disable=SC2001
	#(style): See if you can use ${variable//search/replace} instead.
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
		date="$(grep "$DATE" "$tmp" | cut -f 3-4 -d ' ' )"
	fi

	[[ -z "$version" ]] && version="N/A"
	[[ -z "$sha" ]] && sha="N/A"
	[[ -z "$date" ]] && date="N/A"
		

	printf "%-30s: Version: %-10s Date: %-20s Sha: %-10s\n" "$1" "$version" "$date" "$sha"
	rm "$tmp"
}

analyze "raspiBackup" $DOWNLOAD_URL
analyze "raspiBackup_beta" $BETA_DOWNLOAD_URL
analyze "raspiBackupInstallUI" $INSTALLER_DOWNLOAD_URL
analyze "raspiBackupInstallUI_beta" $INSTALLER_BETA_DOWNLOAD_URL
analyze "raspiBackup.properties" $PROPERTIES_DOWNLOAD_URL
analyze "raspiBackup_de.conf" $CONF_DE_DOWNLOAD_URL
analyze "raspiBackup_en.conf" $CONF_EN_DOWNLOAD_URL
