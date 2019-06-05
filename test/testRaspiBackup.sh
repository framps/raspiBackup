#!/bin/bash
#######################################################################################################################
#
# raspiBackup backup creation script for backup regression test
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

DEBUG=1

MOUNT_POINT=${1:-"obelix:/disks/bigdata/"}
BACKUP_PATH=${2:-"raspibackupTest"}

BACKUP_PATH="/mnt/$BACKUP_PATH"

BACKUPTYPE_DD="dd"
BACKUPTYPE_DDZ="ddz"
BACKUPTYPE_TAR="tar"
BACKUPTYPE_TGZ="tgz"
BACKUPTYPE_RSYNC="rsync"
declare -A FILE_EXTENSION=( [$BACKUPTYPE_DD]="img" [$BACKUPTYPE_DDZ]="img.gz" [$BACKUPTYPE_RSYNC]="img" [$BACKUPTYPE_TGZ]="tgz" [$BACKUPTYPE_TAR]="tar" )

PARTITIONS_PER_BACKUP=2

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}

PARMS=" -L 2 -l 1 -m 1 -Z"
#PARMS=" -L 2 -l 1 -m 1 -Z -9"

# all backups have 2 backups each

EXECUTE_TESTS=0			# true/false
CREATE_BACKUPS=1		# true/false
CREATE_ANOTHER_BACKUP=0	# true/false
KEEP_BACKUPS=1
NUMBER_OF_BACKUPS=1

USE_V5=0
USE_V6=0
USE_V6N=0

declare -A processedFiles

LOG_FILE="$MYNAME.log"

# use newlines as item separator !!!
TYPES_TO_TEST="dd
ddz
tar
tgz
rsync"

MODES_TO_TEST="N
P"

HOSTNAME=$(hostname)
#HOSTNAME="raspibackup"

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

	for mode in $MODES_TO_TEST; do
		for backupType in $TYPES_TO_TEST; do
			[[ $backupType =~ dd && $mode == "P" ]] && continue
			createBackups $backupType $1 $mode $2
		done
	done
}

function createBackups() { # type (dd, ddz, rsync, ...) count type (N,P) keep

	local i rc parms

	local m=""
	if [[ $3 == "P" ]]; then
		m="-P"
	fi

	for (( i=1; i<=$2; i++)); do
		echo "--- Creating $1 backup number $i of mode $3 in ${BACKUP_PATH}_$3"
		./raspiBackup.sh -t $1 $PARMS $m -k $4 "${BACKUP_PATH}_$3"
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
			N)	bootCnt=$(ls -d "$backup/"* 2>/dev/null| egrep ".(img|mbr|sfdisk)$" | wc -l);
				expectedFiles=3
				;;
			P)	bootCnt=$(ls -d "$backup/"* 2>/dev/null| egrep ".(blkid|mbr|sfdisk|parted)$" | wc -l);
				expectedFiles=4
				;;
			*)	log "error - $1 $2 $3"
				exit 127
				;;
		esac

		if [[ $bootCnt == $expectedFiles ]];  then
			(( buCnt++ ))
		else
			log "??? Missing $HOSTNAME-backup boot files for $backup - bootCnt: $bootCnt - expectedFiles: $expectedFiles"
			IFS=""
			log $(ls -d ${BACKUP_PATH}_$3/$HOSTNAME/$backup/* 2>/dev/null)
			unset IFS
		fi
	done

	if [[ $buCnt != $2 ]]; then
		(( errors++ ))
		log "??? Missing $HOSTNAME-backup boot files: Expected boot backups: $2 - detected boot backups: $buCnt"
		IFS=""
		log $(ls -d ${BACKUP_PATH}_$3/$HOSTNAME/*)
		unset IFS
	else
		(( $DEBUG )) && log "--- Found $buCnt boot backups"
	fi

	return $errors
}

function checkV611BootBackups() { # type (dd, ddz, rsync, ...) count mode (N,P)

	log "--- checkV611BootBackups $1 $2 $3 ---"

	if [[ $3 == "P" ]]; then
		checkV612BootBackups $1 $2 $3
		return $?
	fi

	if [[ $1 == "dd" || $1 == "ddz" ]]; then
		return	0
	fi

	if [[ $3 == "P" ]]; then
		echo "P not possible"
		exit 127
	fi

	local extension=${FILE_EXTENSION[$1]}
	local regex="$1\-backup\-([0-9]{8}\-[0-9]{6})"

	local buCnt=0
	local backup

	if [[ $1 != "rsync" ]]; then
		lsString="${BACKUP_PATH}_$3/$HOSTNAME/$HOSTNAME-$1-backup-*.$extension"
	else
		lsString="-d ${BACKUP_PATH}_$3/$HOSTNAME/$HOSTNAME-$1-backup-*"
	fi

	(( $DEBUG )) && log "lsString: $lsString"

	for backup in $(ls $lsString 2>/dev/null | grep -v ".log"); do

		if [[ ! $backup =~ $regex ]]; then
			(( $DEBUG )) && log "Skipping $backup"
			continue
		fi

		(( $DEBUG )) && log "Processing -> $backup"

		local date=${BASH_REMATCH[1]}
		local bootCnt=4711

		bootCnt=$(ls ${BACKUP_PATH}_$3/$HOSTNAME/$HOSTNAME-backup-$date.{img,mbr,sfdisk} 2>/dev/null | wc -l);

		if [[ $bootCnt != 3 ]];  then
			log "??? Missing $HOSTNAME-backup boot files for $backup - bootCnt: $bootCnt - expectedFiles: 3"
			IFS=""
			log $(ls ${BACKUP_PATH}_$3/$HOSTNAME/$HOSTNAME-$1-backup-* 2>/dev/null)
			unset IFS
		else
			(( buCnt++ ))
		fi
	done

	if [[ $buCnt != $2 ]]; then
		(( errors++ ))
		log "??? Missing $HOSTNAME-backup boot files: Expected boot backups: $2 - detected boot backups: $buCnt"
		IFS=""
		log $(ls ${BACKUP_PATH}_$3/$HOSTNAME/*)
		unset IFS
	else
		(( $DEBUG )) && log "--- Found $buCnt boot backups"
	fi
	return $errors
}

function checkV515BootBackups() { # type (dd, ddz, rsync, ...) count mode (N,P)

	log "--- checkV515BootBackups $1 $2 $3 ---"

	if [[ $1 == "dd" || $1 == "ddz" ]]; then
		return	0
	fi


	local buCnt=0
	local backup

	buCnt=$(ls ${BACKUP_PATH}_$3/$HOSTNAME/$HOSTNAME-backup.{img,mbr,sfdisk} 2>/dev/null | wc -l)

	expected=3

	if [[ $buCnt != $expected ]]; then
		(( errors++ ))
		log "??? Missing $HOSTNAME-backup boot files: Expected boot backups: $expected - detected boot backups: $buCnt"
		IFS=""
		log $(ls ${BACKUP_PATH}_$3/$HOSTNAME/*)
		unset IFS
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
		N)	buCnt=$(ls "${BACKUP_PATH}_$3/$HOSTNAME/"*"-$1-backup"*/*".$extension" 2>/dev/null | wc -l)
			;;
		P)	buCnt=$(ls -d "${BACKUP_PATH}_$3/$HOSTNAME/"*"-$1-backup"*/*"mmcblk"* 2>/dev/null | wc -l)
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
		IFS=""
		log $(ls "${BACKUP_PATH}_$3/$HOSTNAME/"*"-$1-backup"*/*".$extension")
		log $(ls -d "${BACKUP_PATH}_$3/$HOSTNAME/"*"-$1-backup"*/*"mmcblk"*)
		unset IFS
	else
		(( $DEBUG )) && log "--- Found $buCnt root backups"
	fi

	return $errors
}

function checkV611RootBackups() { # type (dd, ddz, rsync, ...) count mode (N,P)

	log "--- checkV611RootBackups $1 $2 $3 ---"

	if [[ $3 == "P" ]]; then
		checkV612RootBackups $1 $2 $3
		return $?
	fi

	(( $DEBUG )) && log "Checking for files of backup $1 and count $2 and type $3"
	local buCnt=0
	local extension

	# check for backup files and img file for rsync

	local extension=${FILE_EXTENSION[$1]}
	local buCntToCheck=$2

	if [[ $1 == "rsync" ]]; then
		buCnt=$(ls -d "${BACKUP_PATH}_$3/$HOSTNAME/"*"-$1-backup-"* 2>/dev/null | grep -v ".log$" | wc -l)
	else
		buCnt=$(ls "${BACKUP_PATH}_$3/$HOSTNAME/"*"-$1-backup-"*".$extension" 2>/dev/null | wc -l)
	fi

	(( $DEBUG )) && log "Checking for $buCntToCheck root backup files"
	if [[ $buCnt != $buCntToCheck ]]; then
		(( errors++ ))
		log "??? Missing raspibackup-$3-backup files for $extension: Backups found: $buCnt - expected: $buCntToCheck"
		IFS=""
		log $(ls "${BACKUP_PATH}_$3/$HOSTNAME/"*"-$1-backup-"*)
		unset IFS
	else
		(( $DEBUG )) && log "--- Found $buCnt root backups"
	fi

	return $errors
}

function checkV515RootBackups() { # type (dd, ddz, rsync, ...) count mode (N,P)

	log "--- checkV515RootBackups $1 $2 $3 ---"

	local extension=${FILE_EXTENSION[$1]}

	(( $DEBUG )) && log "Checking for files of backup $1 and count $2 and type $3 and ext $extension"
	local buCnt=0
	local extension

	# check for backup files and img file for rsync

	local buCntToCheck=$2

	if [[ $1 == "rsync" ]]; then
		buCnt=$(ls -d "${BACKUP_PATH}_$3/$HOSTNAME/"*"-$1-backup-"* 2>/dev/null | grep -v ".log" | wc -l)
	else
		buCnt=$(ls "${BACKUP_PATH}_$3/$HOSTNAME/"*"-$1-backup-"*".$extension" 2>/dev/null | wc -l)
	fi

	if [[ $buCnt != $buCntToCheck ]]; then
		(( errors++ ))
		log "??? Missing raspibackup-$3-backup files for $extension: Backups found: $buCnt - expected: $buCntToCheck"
		IFS=""
		log $(ls -d "${BACKUP_PATH}_$3/$HOSTNAME/"*"-$1-backup"*)
		unset IFS
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

function checkV611Backups() { # type (dd, ddz, rsync, ...) count mode (N,P)

	local e
	log "--- checkV611Backups $1 $2 $3 ---"

	checkV611BootBackups $1 $2 $3
	e=$?
	(( sumErrors += e ))
	checkV611RootBackups $1 $2 $3
	e=$?
	(( sumErrors += e ))

}

function checkV515Backups() { # type (dd, ddz, rsync, ...) count mode (N,P)

	local e
	log "--- checkV515Backups $1 $2 $3 ---"
	checkV515BootBackups $1 $2 $3
	e=$?
	(( sumErrors += e ))
	checkV515RootBackups $1 $2 $3
	e=$?
	(( sumErrors += e ))
}

function checkAllV612Backups() {  # number of backups

	log "--- checkV612AllBackups ---"
	errors=0

	for mode in $MODES_TO_TEST; do
		for backupType in $TYPES_TO_TEST; do
			[[ $backupType =~ "dd" && $mode == "P" ]] && continue
			checkV612Backups $backupType $1 $mode
		done
	done

	[[ $errors > 0 ]] && log "??? Errors: $errors" || log "--- Success"
	(( sumErrors+=errors ))
}

function checkAllV611Backups() {  # backups

	log "--- checkV611AllBackups ---"
	errors=0
	checkV611Backups dd $1 N
	checkV611Backups tar $1 N
	checkV611Backups rsync $1 N

	checkV611Backups tar $1 P
	checkV611Backups rsync $1 P
	[[ $errors > 0 ]] && log "??? Errors: $errors" || log "--- Success"
	(( sumErrors+=errors ))
}

function checkAllV515Backups() {  # backups

	errors=0
	log "--- checkV515AllBackups ---"
	checkV515Backups dd $1 N
	checkV515Backups tar $1 N
	checkV515Backups rsync $1 N
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
		log "Removing ${BACKUP_PATH}_$m"
		rm -rf ${BACKUP_PATH}_$m
		log "Creating ${BACKUP_PATH}_$m"
		mkdir -p ${BACKUP_PATH}_$m
	done
}

function primeBackups() {

	for m in $MODES_TO_TEST; do

		if [[ $m == "N" ]]; then
			if (( $USE_V5 )); then
				log "Copying existing old version backups V5"
				cp -lR ${BACKUP_PATH}_0.5.15.9_N/* ${BACKUP_PATH}_$m &>/dev/null
			fi
			if (( $USE_V6 )); then
				log "Copying existing old version backups V6 N"
				cp -lR ${BACKUP_PATH}_0.6.1.1_N/* ${BACKUP_PATH}_N &>/dev/null
			fi
			if (( $USE_V6N )); then
				log "Copying existing new version N backups V6"
				cp -lR ${BACKUP_PATH}_0.6.1.2_N/* ${BACKUP_PATH}_$m &>/dev/null
			fi
		else
			if (( $USE_V6 )); then
				log "Copying existing old version backups V6 P"
				cp -lR ${BACKUP_PATH}_0.6.1.1_P/* ${BACKUP_PATH}_P &>/dev/null
			fi
			if (( $USE_V6N )); then
				log "Copying existing new version P backups V6"
				cp -lR ${BACKUP_PATH}_0.6.1.2_P/* ${BACKUP_PATH}_$m &>/dev/null
			fi
		fi
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

USE_V5=0
USE_V6=0
USE_V6N=0

log $SEPARATOR

(( $USE_V5 )) && checkAllV515Backups 2
(( $USE_V6 )) && checkAllV611Backups 2
(( $USE_V6N )) && checkAllV612Backups 2

#countBackups "dd" N 51
#countBackups "dd" N 61
#countBackups "dd" P 62

#echo "--- Processedfiles ---"
#for i in "${!processedFiles[@]}"; do
#	echo "key  : $i - value: ${processedFiles[$i]}"
#done

USE_V6N=1
cleanup
#primeBackups
#checkAllV612Backups 1
createV612Backups 1 1	# createNum, keepNum
checkAllV612Backups 1
USE_V6N=0

#USE_V6=1
#cleanup
#primeBackups
#checkAllV611Backups 1
#createV612Backups 1 1	# createNum, keepNum
#checkAllV612Backups 1
#USE_V6=0

#USE_V5=1
#cleanup
#primeBackups
#checkAllV515Backups 1
#createV612Backups 1 1	# createNum, keepNum
#checkAllV612Backups 1
#USE_V5=0

if [[ $sumErrors > 0 ]]; then
	log "??? raspiBackup test Failed: Errors detected: $sumErrors"
	exit 127
else
	log "--- Backup test finished successfully"
	exit 0
fi
