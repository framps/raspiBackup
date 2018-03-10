#!/bin/bash
#
# Plugin for raspiBackup.sh
# called after a backup finished
#
# Function: Display disk usage and % of disk usage change before and after backup
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for additional information
#
########################################################################################################################
#
#    Copyright (C) 2017-2018 framp at linux-tips-and-tricks dot de
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

# set any variables and prefix all names with ext_ and some unique prefix to use a different namespace than the script
ext_diskUsage_post=( $(getDiskUsage) )

# set any messages and prefix message name with ext_ and some unique prefix to use a different namespace than the script
MSG_EXT_DISK_USAGE="ext_diskusage_2"
MSG_EN[$MSG_EXT_DISK_USAGE]="--- RBK1002I: Disk usage pre backup: Used: %1 Free: %2"
MSG_DE[$MSG_EXT_DISK_USAGE]="--- RBK1002I: Partitionsauslastung vor dem Backup: Belegt: %1 Frei: %2"
MSG_EXT_DISK_USAGE2="ext_diskusage_3"
MSG_EN[$MSG_EXT_DISK_USAGE2]="--- RBK1003I: Disk usage post backup: Used: %1 Free: %2"
MSG_DE[$MSG_EXT_DISK_USAGE2]="--- RBK1003I: Partitionsauslastung nach dem Backup: Belegt: %1 Frei: %2"
MSG_EXT_DISK_USAGE3="ext_diskusage_4"
MSG_EN[$MSG_EXT_DISK_USAGE3]="--- RBK1004I: Free change: %1 (%2 %)"
MSG_DE[$MSG_EXT_DISK_USAGE3]="--- RBK1004I: Änderung freier Platz: %1 (%2 %)"
MSG_EXT_DISK_USAGE4="ext_diskusage_5"
MSG_EN[$MSG_EXT_DISK_USAGE4]="--- RBK1005E: bc not found. Please install bc first."
MSG_DE[$MSG_EXT_DISK_USAGE4]="--- RBK1004E: bc nicht gefunden. bc muss installiert werden."
MSG_EXT_DISK_USAGE5="ext_diskusage_6"
MSG_EN[$MSG_EXT_DISK_USAGE4]="--- RBK1006E: Error retrieving data."
MSG_DE[$MSG_EXT_DISK_USAGE4]="--- RBK1006E: Fehler beim Datensammeln."

# now write message to console and log and email
# $MSG_LEVEL_MINIMAL will write message all the time
# $MSG_LEVEL_DETAILED will write message only if -m 1 parameter was used

if ! which bc &>/dev/null; then
	writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_DISK_USAGE4
else

	[[ -n ${ext_diskUsage_pre[2]} ]] && usagePre=$( bc <<< "${ext_diskUsage_pre[2]} * 1024" ) || usagePre=0
	[[ -n ${ext_diskUsage_post[2]} ]] && usagePost=$( bc <<< "${ext_diskUsage_post[2]} * 1024" ) || usagePost=0
	[[ -n ${ext_diskUsage_pre[3]} ]] && freePre=$( bc <<< "${ext_diskUsage_pre[3]} * 1024" ) || freePre=0
	[[ -n ${ext_diskUsage_post[3]} ]] && freePost=$( bc <<< "${ext_diskUsage_post[3]} * 1024" ) || freePost=0
	[[ -n ${ext_diskUsage_pre[4]} ]] && percentUsedPre=${ext_diskUsage_pre[4]} || percentUsedPre=0
	[[ -n ${ext_diskUsage_post[4]} ]] && percentUsedPost=${ext_diskUsage_post[4]} || percentUsedPost=0

	freeChange=$( bc <<< "$freePost - $freePre" )

	if (( $freePre == 0 )); then
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_DISK_USAGE4
	else

		freeChangePercent=$( printf "%3.2f" $(bc <<<"( $freePost - $freePre ) * 100 / $freePre") )

		# Use bytesToHuman from raspiBackup which displays a number in a human readable form
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_DISK_USAGE "$(bytesToHuman $usagePre)" "$(bytesToHuman $freePre)"
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_DISK_USAGE2 "$(bytesToHuman $usagePost)" "$(bytesToHuman $freePost)"
		writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_DISK_USAGE3 "$(bytesToHuman $freeChange)" "$freeChangePercent"
	fi
fi
