#!/bin/bash

#
# extensionpoint for raspiBackup.sh
# called before dd, tar or rsync backup is started
#
# Function: Copy /etc/fstab into backupdirectory
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for additional information
#
# (C) 201i7 - framp at linux-tips-and-tricks dot de
#

# set any messages and prefix message name with ext_ and some unique prefix to use a different namespace than the script
MSG_EXT_FSTAB_COPY="ext_fstab_copy"
MSG_EN[$MSG_EXT_FSTAB_COPY]="--- RBK1005I: Copy %s to %s"
MSG_DE[$MSG_EXT_FSTAB_COPY]="--- RBK1005I: Kopiere %s in %s"

FSTAB_FILENAME="/etc/fstab"
FSTAB_TARGET_DIR="raspiBackup/extensionSaveArea"
TARGET_DIR="$BACKUPTARGET_DIR/$FSTAB_TARGET_DIR"

# write message to console
writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_FSTAB_COPY "$FSTAB_FILENAME" "$TARGET_DIR"

if [[ -f "$FSTAB_FILENAME" ]]; then
	mkdir -p "$TARGET_DIR"
	extrc=$?
	[[ $extrc != 0 ]] && return $extrc
	cp "$FSTAB_FILENAME" "$TARGET_DIR"
	ls -la "$TARGET_DIR"
	return $?
else
	return 1	// terminate raspiBackup
fi

