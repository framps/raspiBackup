#!/bin/bash

# define functions needed
# use local for all variables so the script namespace is not polluted

function getTimeElapsed() {
	local time=$(($ext_Time_post-$ext_Time_pre))
        hours=$((time/ 3600));
        minutes=$(( (time% 3600) / 60 )); 
        seconds=$(( (time% 3600) % 60 )); 
        runtimeString=$(printf "%02d:%02d:%02d (hh:mm:ss)" $hours $minutes $seconds)
        echo $runtimeString
}


# set any variables and prefix all names with ext_ and some unique prefix to use a different namespace than the script
ext_Time_post=$(getTime)
ext_TimeElapsed_post=$(getTimeElapsed)

# set any messages and prefix message name with ext_ and some unique prefix to use a different namespace than the script
MSG_EXT_TIME="ext_Time_1"
MSG_EN[$MSG_EXT_TIME]="RBK2000I: Total runtime:: %s"
MSG_DE[$MSG_EXT_TIME]="RBK2000I: Gesamtlaufzeit: %s"

# now write message to console and log and email
# $MSG_LEVEL_MINIMAL will write message all the time
# $MSG_LEVEL_DETAILED will write message only if -m 1 parameter was used
writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_TIME "$ext_TimeElapsed_post"
