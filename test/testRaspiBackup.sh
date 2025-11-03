#!/bin/bash
#######################################################################################################################
#
# raspiBackup backup creation script for backup regression test
#
#######################################################################################################################
#
#    Copyright (c) 2013, 2025 framp at linux-tips-and-tricks dot de
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

DEBUG=1

declare -A FILE_EXTENSION=( [$BACKUPTYPE_DD]="img" [$BACKUPTYPE_DDZ]="img.gz" [$BACKUPTYPE_RSYNC]="[it]mg" [$BACKUPTYPE_TGZ]="tgz" [$BACKUPTYPE_TAR]="tar" )

PARTITIONS_PER_BACKUP=2

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}

PARMS=" -L 2 -l 1 -m 1 -Z"

# all backups have 2 backups each

EXECUTE_TESTS=0
CREATE_BACKUPS=1
CREATE_ANOTHER_BACKUP=0
KEEP_BACKUPS=1
NUMBER_OF_BACKUPS=1

MOUNT_POINT=${1:-"$MOUNT_HOST:/disks/VMware/"}
BACKUP_PATH=${2:-"raspiBackupTest"}
BACKUP_PATH="/mnt/$BACKUP_PATH"
ENVIRONMENT=${3:-"SD USB SDBOOTONLY"}
TYPES_TO_TEST=${4:-"dd ddz tar tgz rsync"}
MODES_TO_TEST=${5:-"n p"}
BOOT_MODES=${6:-"d t"}

declare -A processedFiles

LOG_FILE="$MYNAME.log"

HOSTNAME=$(hostname)

errors=0
sumErrors=0

exec 1> >(tee -a "$LOG_FILE" >&1)
exec 2> >(tee -a "$LOG_FILE" >&2)

function repeat() { # char num
	local s
	s=$( yes $1 | head -$2 | tr -d "\n" )
	echo $s
}

SEPARATOR=$(repeat = 60)

function log() { # text

	echo "@@@ $(date +%Y%m%d-%H%M%S): $@"
	echo "@@@ $(date +%Y%m%d-%H%M%S): $@" >> "$LOG_FILE"

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

createV612Backups() { # number of backups, keep backups

	local mode backupType bootMode bM

	for mode in $MODES_TO_TEST; do
		for backupType in $TYPES_TO_TEST; do
			[[ $backupType =~ dd && $mode == "p" ]] && continue # dd not supported for -P
			for bootMode in $BOOT_MODES; do
				[[ $bootMode == "t" &&  ( $backupType =~ dd || $mode == "p" ) ]] && continue # -B+ not supported for -P and dd
				[[ $bootMode == "t" ]] && bM="$BOOTMODE_TAR" || bM="$BOOTMODE_DD"
				createBackups $backupType $1 $mode $2 $bM
			done
		done
	done
}

function createBackups() { # type (dd, ddz, rsync, ...) count type (N,P) keep ... other parms

	local i rc parms

	local m=""
	if [[ $3 == "p" ]]; then
		m="-P"
	fi

	for (( i=1; i<=$2; i++)); do
		echo "--- Creating $1 backup number $i of mode $3 and option $5 in ${BACKUP_PATH}_${3^^}"
		log "sudo ~/raspiBackup.sh -t $1 $PARMS $m -k $4 $5 "${BACKUP_PATH}_${3^^}""
		sudo ~/raspiBackup.sh -t $1 $PARMS $m -k $4 $5 "${BACKUP_PATH}_${3^^}"
		rc=$?

		local logFile=$(getLogName $1 $3)
		cat "$logFile" >> "$LOG_FILE"

		if [[ $rc != 0 ]]; then
			echo "??? raspiBackup failed with rc $rc"
			exit 127
		fi

	done
}

function rememberProcessedFile() { # fileName type mode version

	if [[ ${processedFiles[$backup]+abc} ]]; then
		echo "??? $backup already set by ${processedFiles[$backup]}"
		return 1
	fi

	processedFiles[$backup]="$2 $3 $4"
	(( $DEBUG )) && echo "!!! $backup set with ${processedFiles[$backup]}"
	return 0
}

function countBackups() { # type mode version (51, 61, 62)

	log "--- countBackups type=$1 mode=$2 version=$3---"

	local regex="$1\-backup\-([0-9]{8}\-[0-9]{6})"
	local match_backuptype="\-$1\-"
	local backup_ext=".(img|tar|dd)$"

	declare -A root_cnt=( ['dd']=0 ['tar']=0 ['rsync']=0 )

	(( $DEBUG )) && ls -d "${BACKUP_PATH}_$2/$HOSTNAME/"*"-$1-backup-"* 2>/dev/null | egrep -v ".(img|mbr|sfdisk|blkid|parted|log)$"

	for backup in $(ls -d "${BACKUP_PATH}_$2/$HOSTNAME/"*"-$1-backup-"* 2>/dev/null | egrep -v ".(mbr|sfdisk|blkid|parted|log)$" ); do

		log "Processing $backup"

		if [[ $backup =~ $match_backuptype ]]; then
			if [[ -d $backup ]]; then
				mmcblk=$(ls -d "${BACKUP_PATH}_$2/$HOSTNAME/"*"-$1-backup-"*/mmcblk* 2>/dev/null | wc -l)
				(( $DEBUG )) && log "r=$r"
				if [[ $mmcblk > 0 && $2 == "P" && $3 == "62" ]]; then
					echo "Dir and mmcblks"
					rememberProcessedFile $backup $1 $2 $3			# 62
					if [[ $? == 0 ]]; then
						(( root_cnt[$1]+=1 ))
					fi
				elif [[ $mmcblk == 0 && $2 == "N" && type == "rsync" ]]; then			# rsync
					echo "Dir and no mmcblks"
					rememberProcessedFile $backup $1 $2 $3
					if [[ $? == 0 ]]; then
						(( root_cnt[$1]+=1 ))
					fi
				fi
			elif [[ $backup =~ $backup_ext ]]; then
				if [[ $backup =~ $regex ]]; then
					echo "No dir and backupext and regex"
					rememberProcessedFile $backup $1 $2 $3			# 61
					if [[ $? == 0 ]]; then
						(( root_cnt[$1]+=1 ))
					fi
				else
					echo "No dir and backupext and no regex"
					rememberProcessedFile $backup $1 $2 $3			# 51
					if [[ $? == 0 ]]; then
						(( root_cnt[$1]+=1 ))
					fi
				fi
			else
				echo "No dir and no backupext"
				rememberProcessedFile $backup $1 $2 $3				# 51
				if [[ $? == 0 ]]; then
					(( root_cnt[$1]+=1 ))
				fi
			fi
		fi
	done

	(( $DEBUG )) && echo "--- root_cnt ---"
	for i in "${!root_cnt[@]}"; do
		if [[ ${root_cnt[$i]} != 0 && $i == $1 ]]; then
			echo "key  : $i - value: ${root_cnt[$i]}"
		fi
	done

}

function checkV612BootBackups() { # type (dd, ddz, rsync, ...) count mode (N,P)

	log "--- checkV612BootBackups $1 $2 $3 ---"

	if [[ $1 == "dd" || $1 == "ddz" ]]; then
		return	0
	fi

	local regex="$1\-backup\-([0-9]{8}\-[0-9]{6})"

	local buCnt=0
	local backup

	for backup in $(ls -d "${BACKUP_PATH}_$3/$HOSTNAME/"*"-$1-backup-"* 2>/dev/null | grep -v ".log$" ); do

		if [[ ! $backup =~ $regex ]]; then
			(( $DEBUG )) && log "Skipping $backup"
			continue
		fi

		(( $DEBUG )) && log "Processing -> $backup"

		local date=${BASH_REMATCH[1]}
		local bootCnt=4711
		local expectedFiles=4711

		case $3 in
			N)	bootCnt=$(ls -d "$backup/"* 2>/dev/null| egrep ".(tmg|img|mbr|sfdisk)$" | wc -l);
				expectedFiles=3
				;;
			P)	bootCnt=$(ls -d "$backup/"* 2>/dev/null| egrep ".(blkid|mbr|sfdisk|parted)$" | wc -l);
				expectedFiles=4
				;;
			*)	log "error invalid mode - $1 $2 $3"
				exit 127
				;;
		esac

		if [[ $bootCnt == $expectedFiles ]];  then
			(( buCnt++ ))
		else
			log "??? Missing $HOSTNAME-backup boot files for $backup - bootCnt: $bootCnt - expectedFiles: $expectedFiles"
			log "$(ls -d ${BACKUP_PATH}_$3/$HOSTNAME/$backup/* 2>/dev/null)"
		fi
	done

	if [[ $buCnt != $2 ]]; then
		(( errors++ ))
		log "??? Missing $HOSTNAME-backup boot files: Expected boot backups: $2 - detected boot backups: $buCnt"
		log "$(ls -d ${BACKUP_PATH}_$3/$HOSTNAME/*)"
	else
		(( $DEBUG )) && log "--- Found $buCnt boot backups"
	fi

	return $errors
}

function checkV612RootBackups() { # type (dd, ddz, rsync, ...) count mode (N,P)

	log "--- checkV612RootBackups $1 $2 $3 ---"

	(( $DEBUG )) && log "Checking for files of backup $1 and count $2 and type $3"
	local buCnt=0
	local extension

	# check for backup files and img file for rsync

	local extension=${FILE_EXTENSION[$1]}
	local buCntToCheck=$2

	case $3 in
		N)	buCnt=$(ls ${BACKUP_PATH}_$3/$HOSTNAME/*-$1-backup*/*.$extension 2>/dev/null | wc -l)
			buCnt2=$(ls -d ${BACKUP_PATH}_$3/$HOSTNAME/*-$1-backup*/*sda* 2>/dev/null | wc -l)
			buCnt3=$(ls -d ${BACKUP_PATH}_$3/$HOSTNAME/*-$1-backup*/*nvme* 2>/dev/null | wc -l)
			buCnt4=$(ls -d ${BACKUP_PATH}_$3/$HOSTNAME/*-$1-backup*/*vda* 2>/dev/null | wc -l)
			(( buCnt+=buCnt2 ))
			(( buCnt+=buCnt3 ))
			(( buCnt+=buCnt4 ))
			;;
		P)	buCnt=$(ls -d ${BACKUP_PATH}_$3/$HOSTNAME/*-$1-backup*/*mmcblk* 2>/dev/null | wc -l)
			buCnt2=$(ls -d ${BACKUP_PATH}_$3/$HOSTNAME/*-$1-backup*/*sda* 2>/dev/null | wc -l)
			buCnt3=$(ls -d ${BACKUP_PATH}_$3/$HOSTNAME/*-$1-backup*/*nvme* 2>/dev/null | wc -l)
			buCnt4=$(ls -d ${BACKUP_PATH}_$3/$HOSTNAME/*-$1-backup*/*vda* 2>/dev/null | wc -l)
			(( buCnt+=buCnt2 ))
			(( buCnt+=buCnt3 ))
			(( buCnt+=buCnt4 ))
			(( buCntToCheck=buCntToCheck*$PARTITIONS_PER_BACKUP ))
			;;
		*)	log "error - $1 $2 $3"
			exit 127
			;;
	esac

	(( $DEBUG )) && log "Checking for $buCntToCheck root backup files"
	if [[ $buCnt != $buCntToCheck ]]; then
		(( errors++ ))
		log "??? Missing raspibackup-$3-backup files for $extension: Backups found: $buCnt - expected: $buCntToCheck"
		log "$(ls "${BACKUP_PATH}_$3/$HOSTNAME/"*"-$1-backup"*/*".$extension")"
		log "$(ls -d "${BACKUP_PATH}_$3/$HOSTNAME/"*"-$1-backup"*/*"mmcblk"*)"
		log "$(ls -d "${BACKUP_PATH}_$3/$HOSTNAME/"*"-$1-backup"*/*"nvme"*)"
		log "$(ls -d "${BACKUP_PATH}_$3/$HOSTNAME/"*"-$1-backup"*/*"vda"*)"
	else
		(( $DEBUG )) && log "--- Found $buCnt root backups"
	fi

	return $errors
}

function checkV612Backups() { # type (dd, ddz, rsync, ...) count mode (N,P)

	local e
	log "--- checkV612Backups $1 $2 $3 ---"
	checkV612BootBackups $1 $2 $3
	e=$?
	(( sumErrors += e ))
	checkV612RootBackups $1 $2 $3
	e=$?
	(( sumErrors += e ))
}

function checkAllV612Backups() {  # number of backups

	log "--- checkV612AllBackups ---"
	errors=0

	for mode in $MODES_TO_TEST; do
		for backupType in $TYPES_TO_TEST; do
			[[ $backupType =~ "dd" && $mode == "p" ]] && continue
			checkV612Backups $backupType $1 ${mode^^}
		done
	done

	[[ $errors > 0 ]] && log "??? Errors: $errors" || log "--- Success"
	(( sumErrors+=errors ))
}

function getLogName() { # type (dd, ddz, rsync, ...) mode (N,P)

	local logFile=$(ls -r "${BACKUP_PATH}_$2/$HOSTNAME/"*"-$1-"*"/"*.log 2>/dev/null | tail -1 )
	echo "$logFile"
}

function getLastBackup() { # type (dd, ddz, rsync, ...) mode (N,P)

	local backupFile=$(ls -d "${BACKUP_PATH}_$2/$HOSTNAME/"*"-$1-"* 2>/dev/null | tail -1 )
	echo "$backupFile"
}

function collectBackups() { # type (dd, ddz, rsync, ...) mode (N,P)
	log "--- Collecting backups $1 for $2"

	backups=( $(ls -d "${BACKUP_PATH}_$2/$HOSTNAME/"*"-$1-backup"* 2>/dev/null) )
	log "$backups"
}

function cleanup() {

	for m in $MODES_TO_TEST; do
		local mm=${m^^}
		log "Removing ${BACKUP_PATH}_$mm"
		rm -rf ${BACKUP_PATH}_$mm
		log "Creating ${BACKUP_PATH}_$mm"
		mkdir -p ${BACKUP_PATH}_$mm
	done
}

function standardTest() {

	log "--- Standardtests ---"

	for backupMode in $MODES_TO_TEST; do

		log "--- Processing mode $backupMode ---"

		for backupType in $TYPES_TO_TEST; do

	# create initial backups

			if (( $CREATE_BACKUPS )); then
				(( $DEBUG )) && log "--- Creating initial $backupType ..."
				createBackups $backupType $NUMBER_OF_BACKUPS $backupMode $KEEP_BACKUPS

				if (( $EXECUTE_TESTS )); then
					(( sumErrors+=errors ))
					(( $DEBUG )) && log "--- Initial $backupType errors: $errors"
					errors=0
					log $SEPARATOR
				fi
			fi

			if (( $EXECUTE_TESTS )); then
				(( $DEBUG )) && log "--- Testing initial backups for $backupType of number $KEEP_BACKUPS ..."
				checkBackups $backupType $KEEP_BACKUPS $backupMode
				checkBootBackups $backupType $KEEP_BACKUPS $backupMode
				(( sumErrors+=errors ))
				(( $DEBUG )) && log "--- Initial $backupType test errors: $errors"
				errors=0
				log $SEPARATOR

	# create another backup and check that there is no additional backup version

				if (( $CREATE_ANOTHER_BACKUP )); then
					ls -d "${BACKUP_PATH}_$backupMode/$HOSTNAME/"*"-$backupType-"*
					lastBackup=$(getLastBackup $backupType $backupMode)

					(( $DEBUG )) && log "--- Creating additional backup $backupType ..."
					createBackups $backupType 1 $backupMode

					(( sumErrors+=errors ))
					(( $DEBUG )) && log "--- Creating additional backup $backupType test errors: $errors"
					errors=0

					(( $DEBUG )) && log $SEPARATOR

					ls -d "${BACKUP_PATH}_$backupMode/$HOSTNAME/"*"-$backupType-"*
					lastBackup2=$(getLastBackup $backupType $backupMode)

					if [[ $lastBackup == $lastBackup2 ]]; then
						(( $DEBUG )) && log "--- Failed to create new backup - last: $lastBackup - last2: $lastBackup2"
						(( sumErrors++ ))
					else

						(( $DEBUG )) && log "--- Testing additional backups for $backupType of number $KEEP_BACKUPS ..."
						checkBackups $backupType $KEEP_BACKUPS $backupMode
						checkBootBackups $backupType $KEEP_BACKUPS $backupMode
						(( sumErrors+=errors ))
						(( $DEBUG )) && log "--- Testing additional backup $backupType test errors: $errors"
						errors=0
						log $SEPARATOR
					fi
				fi

				log "--- Test of $backupType finished - Errors: $sumErrors"
				(( sumErrors > 0 )) && break
			fi

		done

		log "--- Processing mode $backupMode ... done ---"

		if (( $EXECUTE_TESTS )); then
			(( sumErrors > 0 )) && break
		fi

	done
}

if ! isMounted "/mnt"; then
	echo "Mounting $MOUNT_POINT"
	mount $MOUNT_POINT /mnt -o nolock -o rsize=32768 -o wsize=32768 -o noatime
fi

rm "$LOG_FILE"

mkdir -p ${BACKUP_PATH} 2>/dev/null

createV612Backups 1 1	# createNum, keepNum
checkAllV612Backups 1

if [[ $sumErrors > 0 ]]; then
	log "??? raspiBackup test Failed: Errors detected: $sumErrors"
	exit 127
else
	log "--- Backup test finished successfully"
	ln=$(getLogName)
	cp $ln ./raspiBackup.log
	exit 0
fi
