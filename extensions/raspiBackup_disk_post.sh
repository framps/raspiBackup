#!/bin/bash

#
# extensionpoint for raspiBackup.sh
# called after a backup finished
#
# Function: Display disk usage and % of disk usage change before and after backup
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for additional information 
#
# (C) 2017 - framp at linux-tips-and-tricks dot de
#

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

# now write message to console and log and email
# $MSG_LEVEL_MINIMAL will write message all the time
# $MSG_LEVEL_DETAILED will write message only if -m 1 parameter was used
usagePre=$(( ${ext_diskUsage_pre[2]} * 1024 ))
usagePost=$(( ${ext_diskUsage_post[2]} * 1024 ))
freePre=$(( ${ext_diskUsage_pre[3]} * 1024 ))
freePost=$(( ${ext_diskUsage_post[3]} * 1024 ))
percentUsedPre=${ext_diskUsage_pre[4]}
percentUsedPost=${ext_diskUsage_post[4]}
freeChange=$(( $freePost - $freePre ))
freeChangePercent=$( printf "%3.2f" $(bc <<<"( $freePost - $freePre ) * 100 / $freePre") )

# Use bytesToHuman from raspiBackup which displays a number in a human readable form
writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_DISK_USAGE "$(bytesToHuman $usagePre)" "$(bytesToHuman $freePre)"
writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_DISK_USAGE2 "$(bytesToHuman $usagePost)" "$(bytesToHuman $freePost)" 
writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_DISK_USAGE3 "$(bytesToHuman $freeChange)" "$freeChangePercent"
