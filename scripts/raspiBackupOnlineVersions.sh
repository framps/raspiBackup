#!/bin/bash

#######################################################################################################################
#
# 	  Retrieve version and commit sha/revision of files offered by raspiBackup for download
#
# 	  Visit http://www.linux-tips-and-tricks.de/raspiBackup for latest code and other details
#
#######################################################################################################################
#
#    Copyright (c) 2021-2026 framp at linux-tips-and-tricks dot de
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
GIT_DATE="$Date: 2026-08-04 18:52:24 +0200$"
#shellcheck disable=SC2034,SC2154
# (warning): Sha1 is referenced but not assigned (did you mean 'DATE'?).
# (warning): GIT_COMMIT appears unused. Verify use (or export if used externally).
GIT_COMMIT="$Sha1: 527812d$"

MYHOMEURL="https://raw.githubusercontent.com/framps/raspiBackup/master/published"
DOWNLOAD_URL="$MYHOMEURL/raspiBackup.sh"
BETA_DOWNLOAD_URL="$MYHOMEURL//beta/raspiBackup.sh"
INSTALLER_DOWNLOAD_URL="$MYHOMEURL//raspiBackupInstallUI.sh"
INSTALLER_BETA_DOWNLOAD_URL="$MYHOMEURL/beta/raspiBackupInstallUI.sh"
PROPERTIES_DOWNLOAD_URL="$MYHOMEURL/raspiBackup.properties"
CONF_DE_DOWNLOAD_URL="$MYHOMEURL/raspiBackup_de.conf"
CONF_EN_DOWNLOAD_URL="$MYHOMEURL/raspiBackup_en.conf"

DOWNLOAD_TIMEOUT=60 # seconds
DOWNLOAD_RETRIES=3

SHA="JFNoYTE6Cg=="
DATE="JERhdGU6Cg=="

SHA="$(base64 -d <<< "$SHA")"
DATE="$(base64 -d <<< "$DATE")"

function analyze() { # fileName url
	tmp=$(mktemp)
	wget "$2" -q --tries="$DOWNLOAD_RETRIES" --timeout="$DOWNLOAD_TIMEOUT" -O "$tmp"

	# GIT_COMMIT='527812d'

	local pattern="GIT_COMMIT=['\"]([^\"]+)['\"]"
	sha="$(grep "GIT_COMMIT=" "$tmp")"
	if [[ "$sha" =~ $pattern ]]; then
		sha=${BASH_REMATCH[1]}
	else
		sha="ukn"
	fi
	
	# VERSION="0.6.5-beta"	# -beta, -hotfix or -dev suffixes possible
	local pattern="(VERSION|VERSION_CONFIG)=['\"]([^ ]+)['\"]"
	version="$(grep -E "(VERSION|VERSION_CONFIG)=" "$tmp")"
	if [[ "$version" =~ $pattern ]]; then
		version="${BASH_REMATCH[2]}"
	else 
		version="ukn"
	fi

	# GIT_DATE="2026-08-29 12:59:01 +0200"
	local pattern="GIT_DATE=['\"]([^\"']+)['\"]"
	date="$(grep -e "GIT_DATE=" "$tmp")"
	if [[ "$date" =~ $pattern ]]; then
		date="${BASH_REMATCH[1]}"
	else 
		date="ukn"
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
