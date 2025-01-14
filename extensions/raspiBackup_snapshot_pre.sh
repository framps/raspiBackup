#!/bin/bash
#######################################################################################################################
#
# Sample plugin for raspiBackup.sh
# called before a backup is started
#
# Function: stop services, create snapshot, start services again, unset the variables for STOP- and STARTSERVICES.
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for additional information
#
#######################################################################################################################
#
#    Copyright (c) 2015-2021 framp at linux-tips-and-tricks dot de
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

# we have STARTSERVICES and STOPSERVICES

export SNAPDEST="/.snapshot-raspiBackup-$BACKUPFILE"

# create the snapshot
btrfs subvolume snapshot / $SNAPDEST

# start services again
eval $STARTSERVICES

# Now the funny part: since we already took the snapshot, we don't need to start/stop the services during the actual backup (assumption: boot partition is stable)
# However, we want to remove the snapshot afterwards
export STOPSERVICES=""
export STARTSERVICES="btrfs subvolume delete $SNAPDEST"



