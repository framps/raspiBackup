#!/bin/bash

#
# extensionpoint for raspiBackup.sh
# called after a backup finished
#
# Function: Display memory free and used in MB
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for additional information 
#
# (C) 2015 - framp at linux-tips-and-tricks dot de
#

# set any variables and prefix all names with ext_ and some unique prefix to use a different namespace than the script
ext_freememory_post=( $(getMemoryFree) )

# set any messages and prefix message name with ext_ and some unique prefix to use a different namespace than the script
MSG_EXT_DISK_FREE="ext_freememory_1"
MSG_EN[$MSG_EXT_DISK_FREE]="--- RBK1001I: Memory usage - Pre backup - Used: %1 MB Free: %2 MB - Post backup - Used: %3 MB Free: %4 MB"
MSG_DE[$MSG_EXT_DISK_FREE]="--- RBK1001I: Speicherauslastung - Vor dem Backup - Belegt: %1 MB Frei: %2 MB - Nach dem Backup: Belegt: %3 MB Frei: %4 MB"

# now write message to console and log and email
# $MSG_LEVEL_MINIMAL will write message all the time
# $MSG_LEVEL_DETAILED will write message only if -m 1 parameter was used
writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_DISK_FREE "${ext_freememory_pre[0]}" "${ext_freememory_pre[1]}" "${ext_freememory_post[0]}" "${ext_freememory_post[1]}"



