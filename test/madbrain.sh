#!/bin/bash

LOG="raspiBackup.LOG"
MSG="raspiBackup.MSG"

LOG_FILE="/tmp/$LOG"

BACKUP_DIR=/backup/test
DEVICE="/dev/mmcblk0"
DEVICE_PARTITIONPREFIX="${DEVICE}p"

cleanup() {
	echo "cleaning up"
	if [[ -f $LOG_FILE ]]; then
		mv $LOG_FILE $BACKUP_DIR/$LOG
	fi

	ls -lah $BACKUP_DIR
}

trap 'cleanup' SIGINT SIGTERM EXIT

exec 3>&1 4>&2
exec 1> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE")
exec 2> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE" >&2)

echo "clean up previous test"
rm ${BACKUP_DIR}/*

echo "stopping services"
systemctl stop smokeping && systemctl stop apache2 && systemctl stop cron && systemctl stop cups-browsed && systemctl stop cups && systemctl stop nmbd && systemctl stop smbd

echo "running sfdisk"
sfdisk -d ${DEVICE} > ${BACKUP_DIR}/part.sfdisk

echo "running tar"
tar -cpi --one-file-system -f "${BACKUP_DIR}/pi64.tar" --warning=no-xdev --numeric-owner --exclude="/backup/*" --exclude="/tmp/raspiBackup.log" --exclude="/tmp/raspiBackup.msg" --exclude='.gvfs' --exclude=/proc/* --exclude=/lost+found/* --exclude=/sys/* --exclude=/dev/* --exclude=/tmp/* --exclude=/swapfile --exclude=/run/* --exclude=/media/* --exclude=/root/logs/* /

echo "running dd for backup.mbr"
dd if=${DEVICE} of="${BACKUP_DIR}/backup.mbr" bs=512 count=1

echo "running dd for backup.img"
dd if=${DEVICE_PARTITIONPREFIX}1 of="${BACKUP_DIR}/backup.img" bs=1M

echo "starting services"
systemctl start smbd && systemctl start nmbd && systemctl start cups && systemctl start cups-browsed && systemctl start cron && systemctl start apache2 && systemctl start smokeping

echo "running ls"
ls -al ${BACKUP_DIR}
echo "success"
