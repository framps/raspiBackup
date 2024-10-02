#!/bin/bash

LOGFILE="$PWD/ut.log"
rm $LOGFILE &>/dev/null
error=0

if [ `id -u` != 0 ]
then
    echo -e "$PGM needs to be run as root.\n"
    exit 1
fi

#
for utDir in $(find * -type d); do
	#if [[ "$utDir" == "makeFilesystemAndLabel" ]]; then
	#if [[ "$utDir" == "makePartition" ]]; then
	if [[ "$utDir" == "resizeLastPartition" ]]; then
    echo "Executing ${utDir}.sh"
	cd $utDir
	./${utDir}.sh >> $LOGFILE 
	e=$?	
	mv /tmp/${utDir}.log . # move debug into UT dir
	if (( e )); then
		echo "??? Unittest $utDir failed"
	else
		: echo "$utDir succeeded"
	fi
	if (( e )); then
		((error+=1))
	fi 
	cd ..
	fi
done

if (( error > 0 )); then
	echo "$error UTs failed"
else
	echo "All UTs finished successfully"
fi
