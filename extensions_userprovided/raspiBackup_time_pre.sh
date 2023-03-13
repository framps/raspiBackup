#!/bin/bash

# define functions needed
# use local for all variables so the script namespace is not polluted

function getTime() {
	local time=$(date +%s)
	echo "$(echo $time)"
}

# set any variables and prefix all names with ext_ and some unique prefix to use a different namespace than the script
ext_Time_pre=$(getTime)

