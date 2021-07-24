#!/bin/bash
#######################################################################################################################
#
# Sample plugin for raspiBackup.sh
# called after a backup finished
#
# Function: Call another script
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for additional information
#
# $1 has the return code of raspiBackup. If it equals 0 this signals success and failure otherwise
#
#######################################################################################################################
#
#    Copyright (c) 2016-2018 framp at linux-tips-and-tricks dot de
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

if [[ -n $1 ]]; then											# was there a return code ? Should be :-)
	if [[ "$1" == 0 ]]; then
		wall <<< "Extension detected ${0##*/} succeeded :-)"
	else
		wall <<< "Extension detected ${0##*/} failed :-("
	fi
else
	wall <<< "Extension detected ${0##*/} didn't receive a return code :-("
fi




