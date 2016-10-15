#!/bin/bash

#
# extensionpoint for raspiBackup.sh
# called before a backup is started
# 
# Function: Display CPU temperature
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for additional information 
#
# (C) 2015 - framp at linux-tips-and-tricks dot de
#

# define functions needed 
# use local for all variables so the script namespace is not polluted

function getCPUTemp() {
	local temp=$(/opt/vc/bin/vcgencmd measure_temp | cut -d '=' -f 2)
	echo "$(echo $temp)"
}

# set any variables and prefix all names with ext_ and some unique prefix to use a different namespace than the script
ext_CPUTemp_pre=$(getCPUTemp)

