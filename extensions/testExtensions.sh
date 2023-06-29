#!/bin/bash
########################################################################################################################
#
# Function: Invoke all sample plugins. Helps to debug and develop plugins
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for additional information
#
########################################################################################################################
#
#    Copyright (c) 2018 framp at linux-tips-and-tricks dot de
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

GIT_DATE="$Date$"
GIT_COMMIT="$Sha1$"

if [[ -f ../raspiBackup.sh ]]; then
	. ../raspiBackup.sh --include
else
	. raspiBackup.sh --include
fi

<< 'SKIP'
. ./raspiBackup_disk_pre.sh
. ./raspiBackup_disk_post.sh

. ./raspiBackup_mem_pre.sh
. ./raspiBackup_mem_post.sh

. ./raspiBackup_temp_pre.sh
. ./raspiBackup_temp_post.sh
SKIP

. ./raspiBackup_sample_notify.sh 42
