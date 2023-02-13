#!/bin/bash
########################################################################################################################
#
# Function: Sample notification extension
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for additional information
#
########################################################################################################################
#
#    Copyright (c) 2023 framp at linux-tips-and-tricks dot de
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

echo "-> Sample notification extension called"

# Access log file"
echo "-> LOG_FILE: $LOG_FILE"
head -n 100 $LOG_FILE

# Acces message file"
echo "-> MSG_FILE: $MSG_FILE"
cat $MSG_FILE

# access raspiBackup return code
echo "-> RC: $rc"

echo "-> Sample notification extension finished"

