#!/bin/bash
#######################################################################################################################
#
# Sample plugin for raspiBackup.sh
# called before dd, tar or rsync backup is started
#
# Function: Copy /etc/fstab into backupdirectory
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for additional information
#
#######################################################################################################################
#
#    Copyright (c) 2017 framp at linux-tips-and-tricks dot de
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
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.#
#
#######################################################################################################################

GIT_DATE="$Date: 2021-07-21 20:34:13 +0200$"
GIT_COMMIT="$Sha1: 7b4feee$"

# set any messages and prefix message name with ext_ and some unique prefix to use a different namespace than the script
MSG_EXT_FSTAB_COPY="ext_fstab_copy"
MSG_EN[$MSG_EXT_FSTAB_COPY]="RBK1005I: Copy %s to %s"
MSG_DE[$MSG_EXT_FSTAB_COPY]="RBK1005I: Kopiere %s in %s"

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

