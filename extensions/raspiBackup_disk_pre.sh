#!/bin/bash
#
# Plugin for raspiBackup.sh
# called before a backup is started
#
# Function: Display disk usage and % of disk usage change before and after backup
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for additional information 
#
#######################################################################################################################
#
#    Copyright (C) 2017 framp at linux-tips-and-tricks dot de
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

# define functions needed 
# use local for all variables used so the script namespace is not poluted

function getDiskUsage() {
	local diskUsage=$(df $BACKUPPATH | grep "/dev")
	echo "$(echo $diskUsage)"
}

# set any variables and prefix all names with ext_ and some unique prefix to use a different namespace than the script
ext_diskUsage_pre=( $(getDiskUsage) )

