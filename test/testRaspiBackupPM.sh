#!/bin/bash
#######################################################################################################################
#
# raspiBackup backu PM test
#
#######################################################################################################################
#
#    Copyright (C) 2013-2019 framp at linux-tips-and-tricks dot de
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#######################################################################################################################

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}

fake=0
testDD=0
testTAR=1
testRSYNC=1

PARMS=" -L 3 -l 1 -v -m 1 -P"

LOG_FILE="$MYNAME.log"
BACKUP_PATH="/mnt/raspibackup Test"
#BACKUP_PATH="/mnt/raspibackupTest"
HOSTNAME=$(hostname)

exec 1> >(tee -a "$LOG_FILE" >&1)
exec 2> >(tee -a "$LOG_FILE" >&2)

function repeat() { # char num
	local s
	s=$( yes $1 | head -$2 | tr -d "\n" )
	echo $s
}

SEPARATOR=$(repeat = 60)

function log() { # text

	echo "$@"
	echo "$@" >> "$LOG_FILE"

}

function isMounted() {

	local path
	path="$1"

	while [[ "$path" != "" ]]; do
		if mountpoint -q "$path"; then
			return 0
        fi
        path=${path%/*}
	done
    return 1
}

if ! isMounted "/mnt"; then
	mount obelix:/disks/bigdata /mnt -o nolock
fi

errors=0

rm "$LOG_FILE"

log $SEPARATOR

if (( ! $fake  && $testDD )); then
	log "--- Creating dd backup"
	~/raspiBackup.sh -t dd -p "$BACKUP_PATH" $PARMS
	cat ~/raspiBackup.log >> "$LOG_FILE"
#	log "--- Creating ddz backup (old)"
#	~/raspiBackup.sh -t ddz -p "$BACKUP_PATH" $PARMS
#	cat ~/raspiBackup.log >> "$LOG_FILE"
#	log "--- Creating ddz backup (new)"
#	~/raspiBackup.sh -t dd -z -p "$BACKUP_PATH" $PARMS
#	cat ~/raspiBackup.log >> "$LOG_FILE"

#	log "--- Checking for files"
#	if [[ -z $(ls -l "$BACKUP_PATH/$HOSTNAME/"*"-dd-backup"*) ]]; then
#		(( errors++ ))
#		log "??? Missing raspibackup-dd-backup"
#	fi
#	if [[ -z "$(ls -l $BACKUP_PATH/$HOSTNAME/*-ddz-backup*)" ]]; then
#		(( errors++ ))
#		log "??? Missing raspibackup-ddz-backup"
#	fi
	log $SEPARATOR
fi

if (( ! $fake && $testTAR )); then
	echo "--- Creating tar backup"
	~/raspiBackup.sh -t tar -p "$BACKUP_PATH" $PARMS
	cat ~/raspiBackup.log >> "$LOG_FILE"
#	echo "--- Creating 2nd tar backup"
#	~/raspiBackup.sh -t tar -p "$BACKUP_PATH" $PARMS
#	echo "--- Creating tgz backup (old)"
#	~/raspiBackup.sh -t tgz -p "$BACKUP_PATH" $PARMS
#	cat ~/raspiBackup.log >> "$LOG_FILE"
#	echo "--- Creating tgz backup (new)"
#	~/raspiBackup.sh -t tar -z -p "$BACKUP_PATH" $PARMS
#	cat ~/raspiBackup.log >> "$LOG_FILE"

#	log "--- Checking for files"
#	if [[ ! -f "$BACKUP_PATH/$HOSTNAME/raspibackup-backup.img" ]]; then
#		(( errors++ ))
#		log "??? Missing raspibackup-backup.img"
#	fi
#	if [[ ! -f "$BACKUP_PATH/$HOSTNAME/raspibackup-backup.mbr" ]]; then
#		(( errors++ ))
#		log "??? Missing raspibackup-backup.mbr"
#	fi
#	if [[ ! -f "$BACKUP_PATH/$HOSTNAME/raspibackup-backup.sfdisk" ]]; then
#		(( errors++ ))
#		log "??? Missing raspibackup-backup.sfdisk"
#	fi
#	if [[ -z $(ls -l "$BACKUP_PATH/$HOSTNAME/"*"-tar-backup"*) ]]; then
#		(( errors++ ))
#		log "??? Missing raspibackup-tar-backup"
#	fi
#	if [[ -z $(ls -l "$BACKUP_PATH/$HOSTNAME/"*"-tgz-backup"*) ]]; then
#		(( errors++ ))
#		log "??? Missing raspibackup-tgz-backup"
#	fi

	log $SEPARATOR
fi

if (( ! $fake && $testRSYNC )); then
	echo "--- Creating 1st rsync backup"
	~/raspiBackup.sh -t rsync -p "$BACKUP_PATH" $PARMS
	cat ~/raspiBackup.log >> "$LOG_FILE"
#	echo "--- Creating 2nd rsync backup"
#	~/raspiBackup.sh -t rsync -p "$BACKUP_PATH" $PARMS
# 	cat ~/raspiBackup.log >> "$LOG_FILE"
#
#	log "--- Checking for files"
#	if [[ -z $(ls -l "$BACKUP_PATH/$HOSTNAME/"*"-rsync-backup"*) ]]; then
#		(( errors++ ))
#		log "??? Missing raspibackup-rsync-backup"
#	fi
#
#	if [[ $errors > 0 ]]; then
#		log "??? Test failed. $errors errors occured"
#	else
#		log "--- Test finished successfully"
#	fi

	log $SEPARATOR
fi
