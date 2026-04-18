#!/bin/bash
source ./signInit.sh
sudo apt remove raspibackup
dpkg-deb --build raspiBackup_0.7.2
gpg --detach-sign raspiBackup_0.7.2.deb
gpg --verify raspiBackup_0.7.2.deb.sig raspiBackup_0.7.2.deb
sudo apt install  ./raspiBackup_0.7.2.deb


