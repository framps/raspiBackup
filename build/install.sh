#!/bin/bash
#
function show() {
	echo "==============================="
	echo "@@@ $@ ..."
	echo "==============================="
}
show "Package verification"
gpg --verify raspiBackup_0.7.2.deb.sig raspiBackup_0.7.2.deb
show "Install package"
sudo apt install -y ./raspiBackup_0.7.2.deb
show "Show installation result"
apt-cache policy raspibackup



