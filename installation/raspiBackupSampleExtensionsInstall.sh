#!/bin/bash

# Simple script to download and install raspiBackup.sh sample extensions
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for details about the script
#
# (C) 2015 - framp at linux-tips-and-tricks dot de

file="raspiBackupSampleExtensions.tgz"
logfile="./$file.log"
url="www.linux-tips-and-tricks.de"
extractDir="/usr/local/bin"

echo "Downloading $file ..."
if ! wget "http://$url/$file" -O $file 2>$logfile; then
	echo "??? Download of $file failed"
	exit 127
fi
echo "Extracting $file ..."
if ! sudo tar -xzf $file -C $extractDir; then
	echo "??? Extract of $file failed"
	exit 127
fi

rm $file
rm $logfile
echo "$file installed successfully in $extractDir" 
