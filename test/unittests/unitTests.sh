#!/bin/bash

if [ `id -u` != 0 ]
then
    echo -e "$0 needs to be run as root.\n"
    exit 1
fi

LOGFILE="$PWD/ut.log"
rm $LOGFILE &>/dev/null
error=0

#
for utDir in $(find * -type d); do
	#[[ "$utDir" == "makeFilesystemAndLabel" ]] && continue
	[[ "$utDir" == "makePartition" ]] && continue 
	#if [[ "$utDir" == "resizeLastPartition" ]]; then
    echo "Executing ${utDir}.sh"
	cd $utDir
	./${utDir}.sh >> $LOGFILE 
	e=$?	
	if (( e )); then
		echo "??? Unittest $utDir failed"
	else
		: echo "$utDir succeeded"
	fi
	if (( e )); then
		((error+=1))
	fi 
	cd ..
	#fi
done

if (( error > 0 )); then
	echo "$error UTs failed"
	exit 1
else
	echo "All UTs finished successfully"
	exit 0
fi
