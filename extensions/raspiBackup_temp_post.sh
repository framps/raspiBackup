#!/bin/bash
#
# Plugin for raspiBackup.sh
# called after a backup finished
#
# Function: Display CPU temperature
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for additional information 
#
#######################################################################################################################
#
#    Copyright (C) 2015-2017 framp at linux-tips-and-tricks dot de
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

# set any variables and prefix all names with ext_ and some unique prefix to use a different namespace than the script
ext_CPUTemp_post=$(getCPUTemp)

# set any messages and prefix message name with ext_ and some unique prefix to use a different namespace than the script
MSG_EXT_CPU_TEMPERATURE="ext_CPUTemp_1"
MSG_EN[$MSG_EXT_CPU_TEMPERATURE]="--- RBK1000I: CPU temperature pre and post backup: %1 - %2"
MSG_DE[$MSG_EXT_CPU_TEMPERATURE]="--- RBK1000I: CPU Temperatur vor und nach dem Backup: %1 - %2"

# now write message to console and log and email
# $MSG_LEVEL_MINIMAL will write message all the time
# $MSG_LEVEL_DETAILED will write message only if -m 1 parameter was used
writeToConsole $MSG_LEVEL_MINIMAL $MSG_EXT_CPU_TEMPERATURE "$ext_CPUTemp_pre" "$ext_CPUTemp_post"


