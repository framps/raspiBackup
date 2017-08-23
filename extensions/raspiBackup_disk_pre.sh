#!/bin/bash

#
# extensionpoint for raspiBackup.sh
# called before a backup is started
#
# Function: Display disk usage and % of disk usage change before and after backup
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for additional information 
#
# (C) 2017 - framp at linux-tips-and-tricks dot de
#

# define functions needed 
# use local for all variables used so the script namespace is not poluted

function getDiskUsage() {
	local diskUsage=$(df $BACKUPPATH | grep "/dev")
	echo "$(echo $diskUsage)"
}

# set any variables and prefix all names with ext_ and some unique prefix to use a different namespace than the script
ext_diskUsage_pre=( $(getDiskUsage) )

