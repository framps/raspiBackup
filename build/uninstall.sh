#!/bin/bash
#
# Uninstall raspiBackup
# use -f if the package is totally broken
#

if [[ -f /var/lib/dpkg/info/raspibackup.postrm ]]; then
	sudo mv /var/lib/dpkg/info/raspibackup.postrm /var/lib/dpkg/info/raspibackup.postrm.broken
fi
if dpkg -l raspibackup; then
	if [[ -n $1 && $1 == "-f" ]]; then
		sudo dpkg --remove --force-remove-reinstreq --force-depends raspibackup
	else
		sudo apt remove raspibackup -y; sudo apt purge raspibackup -y
	fi
	echo "raspiBackup uninstalled"
else
	echo "raspiBackup not installed"
fi

