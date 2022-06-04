#!/bin/bash

#######################################################################################################################
#
# Check if environment is supported by raspiBackup
#
#######################################################################################################################
#
#    Copyright (c) 2022 framp at linux-tips-and-tricks dot de
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


function isSupportedEnvironment() {

	local MODELPATH=/sys/firmware/devicetree/base/model
	local OSRELEASE=/etc/os-release
	local RPI_ISSUE=/etc/rpi-issue

#	Check it's Raspberry HW
	[[ ! -e $MODELPATH ]] && return 1
	logItem "Modelpath: $(cat "$MODELPATH" | sed 's/\x0/\n/g')"
	! grep -q -i "raspberry" $MODELPATH && return 1

#	OS was built for a Raspberry
	[[ ! -e $RPI_ISSUE ]] && return 1
	logItem "$RPI_ISSUE: $(cat $RPI_ISSUE)"

	return 0
}


if ! isSupportedEnvironment; then
	echo ":-( Environment for raspiBackup not supported :-("
	exit
else
	echo ":-) Environment for raspibackup supported :-)"
fi
