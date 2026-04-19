#!/bin/bash

source common.sh

cleanup() {
	show "Cleanig up"
	rm -f framps.gpg.asc
	#rm -f raspiBackup_0.7.2.deb
	#rm -f raspiBackup_0.7.2.deb.sig
}

trap 'err $?' ERR
trap 'cleanup $?' SIGINT SIGTERM SIGHUP EXIT

exec 1> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE")
exec 2> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE" >&2)

#show "Cleanup installation"
#sudo apt remove -y raspibackup rsync || true

if ! gpg --list-keys | grep -q framps; then
	show "Retrieve key from github"
	curl https://github.com/framps.gpg | gpg --yes --dearmor -o framps.gpg.asc
	show "Import framps key"
	gpg --import  framps.gpg.asc
fi

show "Downloading package"
curl -fsSL https://raw.githubusercontent.com/framps/raspiBackup/refs/heads/master/build/raspiBackup_0.7.2.deb -o raspiBackup_0.7.2.deb
show "Downloading signature"
curl -fsSL https://raw.githubusercontent.com/framps/raspiBackup/refs/heads/master/build/raspiBackup_0.7.2.deb.sig -o raspiBackup_0.7.2.deb.sig

show "Package verification"
gpg --verbose --verify raspiBackup_0.7.2.deb.sig raspiBackup_0.7.2.deb

show "Install package and all dependencies"
sudo apt install -y ./raspiBackup_0.7.2.deb

show "Show installation result"
apt-cache policy raspibackup



