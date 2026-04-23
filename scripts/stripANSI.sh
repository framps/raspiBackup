#!/bin/bash
#
#######################################################################################################################
#
# Tiny script strips VT100/ANSI control sequences from typescript output
#
# Useful to debug raspiBackupInstallUI or any other tool which uses whiptail
#
# 1) Turn on typescript with "script"
# 2) Start raspiBackupInstallUI in debug mode with "sudo bash -x"
# 3) Terminate typescript with "exit"
# 4) Call this script with typescript file. Default is "typescript"
#
#######################################################################################################################
#
#    Copyright (c) 2026 framp at linux-tips-and-tricks dot de
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

typescriptFile="${1:-typescript}"

if [[ ! -f $typeScriptFile ]]; then
	echo "??? $typescriptFile not found"
	exit 1
fi

sed "s,\x1B\[[0-9;]*[a-zA-Z],,g" $typescriptFile
