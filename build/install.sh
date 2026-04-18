#!/bin/bash
#
function show() {
	echo "==============================="
	echo "@@@ $@ ..."
	echo "==============================="
}
show "Cleanup installation"
sudo apt remove -y raspibackup rsync
# Retrieve key from github
curl https://github.com/framps.gpg > framps.sig
#
show "Package verification"
gpg --verify raspiBackup_0.7.2.deb.sig raspiBackup_0.7.2.deb
# Doesn't work :-(( Why???
# gpg --verify framps.sig raspiBackup_0.7.2.deb
if (( $? )); then
	echo "Package verification failed !!!"
	exit 42
fi
show "Install package"
sudo apt install -y ./raspiBackup_0.7.2.deb
show "Show installation result"
apt-cache policy raspibackup



