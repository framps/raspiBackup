#!/bin/bash

source ../../../raspiBackup.sh

error=0

if (( ! $( compareVersions "1.2.3-beta" "1.2.3" ) == 0 )); then
	echo "Error 1"
	error=1
fi

if (( ! $( compareVersions "1.2.3" "1.2.3" ) == 0 )); then
	echo "Error 2"
	error=1
fi

if (( ! $( compareVersions "0.6.9" "0.6.9.1" ) < 0 )); then
	echo "Error 3"
	error=1
fi

if (( ! $( compareVersions "0.6.9.10" "0.6.9.1" ) > 0 )); then
	echo "Error 4"
	error=1
fi

if (( ! $( compareVersions "0.6.9.1" "0.60.9.1" ) > 0 )); then
	echo "Error 5"
	error=1
fi

if (( ! $( compareVersions "0.6.9.1" "0.6.90.1" ) > 0 )); then
	echo "Error 6"
	error=1
fi

if (( ! $( compareVersions "1.6.9.1" "10.6.9.1" ) > 0 )); then
	echo "Error 7"
	error=1
fi

if (( ! $( compareVersions "1" "0.1.2.3" ) < 0 )); then
	echo "Error 8"
	error=1
fi

if (( ! $( compareVersions "1" "1.0.0.0" ) == 0 )); then
	echo "Error 9"
	error=1
fi

if (( ! $( compareVersions "1" "0.0.0.0" ) < 0 )); then
	echo "Error 9"
	error=1
fi

echo
if (( error )); then
	echo "Test failed"
	exit 1 
else
	echo  "Test OK"
	exit 0 
fi	
