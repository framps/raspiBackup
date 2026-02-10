#!/bin/bash
#######################################################################################################################
#
# raspiBackup regression test
#
#######################################################################################################################
#
#    Copyright (c) 2013, 2026 framp at linux-tips-and-tricks dot de
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

SCRIPT_DIR=$( cd $( dirname ${BASH_SOURCE[0]}); pwd | xargs readlink -f)
source $SCRIPT_DIR/constants.sh

SMARTRECYCLE_TEST=0
BACKUP_TEST=1
UNIT_TEST=0
RESTORE_TEST=1
MESSAGE_TEST=0
KEEP_VM=0

EMAIL_NOTIFICATION=1
ATTACH_LOG=1

ENVIRONMENTS_TO_TEST="usb"
TYPES_TO_TEST="dd tar rsync"
TYPES_TO_TEST=(dd tar rsync "tar --tarCompressionTool lz4" "tar --tarCompressionTool zstd" ) 
MODES_TO_TEST="n p"
BOOTMODE_TO_TEST="d t"

if [[ "$1" == "-h" ]]; then
	echo "Environments types modes bootmodes"
	exit 42
elif (( $# > 1 )); then
	ENVIRONMENTS_TO_TEST="${1:-"$ENVIRONMENTS_TO_TEST"}"
	TYPES_TO_TEST="${2:-"$TYPES_TO_TEST"}"
	MODES_TO_TEST="${3:-"$MODES_TO_TEST"}"
	BOOTMODE_TO_TEST="${4:-"$BOOTMODE_TO_TEST"}"
fi

NOTIFY_EMAIL="$(<email.conf)"

if [[ ! -d $EXPORT_DIR/${BACKUP_DIR}_N || ! -d $EXPORT_DIR/${BACKUP_DIR}_P ]]; then
	echo "Creating target backup directies"
	sudo mkdir -p $EXPORT_DIR/${BACKUP_DIR}_N &>/dev/null
	sudo mkdir -p $EXPORT_DIR/${BACKUP_DIR}_P &>/dev/null
fi

if (( BACKUP_TEST )); then
	echo "Cleaning up backup directories"
	sudo rm -rf $EXPORT_DIR/${BACKUP_DIR}_N/* > /dev/null
	sudo rm -rf $EXPORT_DIR/${BACKUP_DIR}_P/* > /dev/null
fi

function d() {
	echo "$(date +%Y%m%d-%H%M%S)"
}

function sshexec() { # cmd
	echo "Executing $@"
	ssh root@$VM_IP "$@"
}

function standardBackupTest() {

	local rc
	echo "$(d) Starting BACKUP $1 $2 $3 $4 $5" >> $LOG_COMPLETED
	./raspiBackupTest.sh "$1" "$2" "$3" "$4" "$5"
	rc=$?
	echo "@@@============================================================" >> $LOG_REGRESSION
	echo "@@@================== BACKUP raspiBackup.log ==================" >> $LOG_REGRESSION
	echo "@@@============================================================" >> $LOG_REGRESSION
	cat raspiBackup.log >> $LOG_REGRESSION
	echo "@@@================================================================" >> $LOG_REGRESSION
	echo "@@@================== BACKUP raspiBackupTest.log ==================" >> $LOG_REGRESSION
	echo "@@@================================================================" >> $LOG_REGRESSION
	cat raspiBackupTest.log >> $LOG_REGRESSION

	if [[ $rc != 0 ]]; then
		echo "$(d) Failed BACKUP $1 $2 $3 $4" >> $LOG_COMPLETED
		echo "??? Backup regression test failed"
		echo "End: $endTime" | mailx -s "??? Backup regression test failed" "$NOTIFY_EMAIL"
		exit 127
	fi

	echo "$(d) Completed BACKUP $1 $2 $3 $4" >> $LOG_COMPLETED
	sudo losetup -D
}

function standardRestoreTest() {

	echo "$(d) Starting RESTORETEST" >> $LOG_COMPLETED
	./raspiRestoreTest.sh
	rc=$?
	echo "@@@=============================================================" >> $LOG_REGRESSION
	echo "@@@================== RESTORE raspiBackup.log ==================" >> $LOG_REGRESSION
	echo "@@@=============================================================" >> $LOG_REGRESSION
	cat raspiBackup.log >> $LOG_REGRESSION
	echo "@@@=================================================================" >> $LOG_REGRESSION
	echo "@@@================== RESTORE raspiBackupTest.log ==================" >> $LOG_REGRESSION
	echo "@@@=================================================================" >> $LOG_REGRESSION
	cat raspiRestoreTest.log >> $LOG_REGRESSION

	if [[ $rc != 0 ]]; then
		echo "$(d) Failed RESTORE $1 $2 $3 $4" >> $LOG_COMPLETED
		echo "??? Restore regression test failed"
		echo "End: $endTime" | mailx -s "??? Restore regression test failed" "$NOTIFY_EMAIL"
		exit 127
	fi
	echo "$(d) Completed RESTORE $1 $2 $3 $4" >> $LOG_COMPLETED
	sudo losetup -D
}

function smartRecycleTest() {

	local rc

	sudo ./raspiBackup7412Test.sh
	rc=$?
	echo "@@@=====================================================================" >> $LOG_REGRESSION
	echo "@@@================== RECYCLE raspiBackup7412Test.log ==================" >> $LOG_REGRESSION
	echo "@@@=====================================================================" >> $LOG_REGRESSION
	cat raspiBackup72412Test.log >> $LOG_REGRESSION

	if [[ $rc != 0 ]]; then
		echo "??? 7412 regression test failed" >> $LOG_COMPLETED
		echo "End: $endTime" | mailx -s "??? 7412 regression test failed" "$NOTIFY_EMAIL"
		exit 127
	fi
}

#if (( $UID != 0 )); then
#	echo "Call me as root"
#	exit 1
#fi

rm *.log >/dev/null

if (( $MESSAGE_TEST )); then
	if ! ./checkMessages.sh; then
		exit
	fi
fi

(( UNIT_TEST )) && sudo ./unitTests.sh

(( $SMARTRECYCLE_TEST )) && smartRecycleTest

startTime=$(date +%Y-%M-%d/%H:%m:%S)
echo "Start: $startTime"
if (( $EMAIL_NOTIFICATION )); then
	echo "Start: $startTime" | mailx -s "--- Backup regression started" "$NOTIFY_EMAIL"
fi

if (( BACKUP_TEST )); then
	for environment in $ENVIRONMENTS_TO_TEST; do
		for mode in $MODES_TO_TEST; do
			for type in "${TYPES_TO_TEST[0]}"; do
				t="$(cut -f 1 -d " " <<< "$type")"
				o="$(cut -f 2- -d " " <<< "$type")"				
				[[ $type =~ dd && $mode == "p" ]] && continue # dd not supported for -P
				for bootmode in $BOOTMODE_TO_TEST; do
					[[ $bootmode == "t" &&  ( $type =~ dd || $mode == "p" ) ]] && continue # -B+ not supported for -P and dd
					standardBackupTest "$environment" "$t" "$mode" "$bootmode" "$o"
				done
			done
		done
	done
fi

if (( ! $KEEP_VM )); then
	echo "Shuting down"
	sshexec "shutdown -h now"
	sudo pkill qemu
fi

if (( RESTORE_TEST )); then
	standardRestoreTest
fi

#(( $ATTACH_LOG )) && attach="-A $LOG_COMPLETED"
echo ":-) Raspibackup regression test finished successfully"
if (( $EMAIL_NOTIFICATION )); then
	echo "" | mailx -s ":-) Raspibackup regression test finished sucessfully" $attach "$NOTIFY_EMAIL"
fi
