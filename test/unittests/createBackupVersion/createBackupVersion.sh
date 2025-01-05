#!/bin/bash
#

error=0

source ../../../raspiBackup.sh

touch "one.conf"
newFile=$(createBackupVersion "one.conf")
rc=$?

if (( rc != 0 )) || [[ "$newFile" != "one.conf.bak" ]]; then
	echo "Error rc: $rc - file: $newFile"
	error=1
fi

newFile=$(createBackupVersion "one.conf")
rc=$?

if (( rc != 0 )) || [[ "$newFile" != "one.conf.bak" ]]; then
	echo "Error rc: $rc - file: $newFile"
	error=1
fi

rm "one.conf.1.bak"
rm "one.conf.bak"
rm "one.conf"

echo
if (( error )); then
	echo "Test failed"
	exit 1
else
	echo  "Test OK"
	exit 0 
fi	
