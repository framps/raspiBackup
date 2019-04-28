#!/bin/bash

#######################################################################################################################
#
# 	Sample script which checks whether a nfsserver is available and exports a specific directory
# 	and then starts raspiBackup
#
#######################################################################################################################
#
#   Copyright # (C) 2017,2018 - framp at linux-tips-and-tricks dot de
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#######################################################################################################################

NFSSERVER="raspifix"
NFSDIRECTORY="/disks/silver/backup"
MOUNTPOINT="/backup"

VERSION="0.0.4"

# add pathes if not already set (usually not set in crontab)

if [[ -e /bin/grep ]]; then
   PATHES="/usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin"
   for p in $PATHES; do
      if ! /bin/grep -E -q "[^:]$p[:$]" <<< $PATH; then
         [[ -z $PATH ]] && export PATH=$p || export PATH="$p:$PATH"
      fi
   done
fi

function cleanup() {
	umount -f $MOUNTPOINT
}

trap cleanup SIGINT SIGTERM EXIT

# nfs server online ?
if ping -c1 -w3 $NFSSERVER &>/dev/null; then
	# does nfs server export directory ?
	if showmount -e $NFSSERVER | grep -q $NFSDIRECTORY; then
		# is directory not mounted already ?
		if ! mount | grep -q $MOUNTPOINT; then
			echo "Mouting $NFSSERVER:$NFSDIRECTORY to $MOUNTPOINT"
			mount $NFSSERVER:$NFSDIRECTORY $MOUNTPOINT
			source raspiBackup.sh
			rc=$?
			if (( $rc > 0 )); then
				echo "raspiBackup failed with rc $rc"
				exit $rc
			fi
			#	now variable $BACKUPTARGET_DIR points to the new backup directory just created and can be used for further backup data processing
		fi
	else
		echo "Server $NFSSERVER does not provide $NFSDIRECTORY"
		exit 1
	fi
else
	echo "Server $NFSSERVER not online"
	exit 1
fi
