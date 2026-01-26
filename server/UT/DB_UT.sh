#!/usr/bin/env bash
# shellcheck disable=SC2004
# SC2004: $ not required in arithmentic expressions
#
#######################################################################################################################
#
# 	Visit http://www.linux-tips-and-tricks.de/raspiBackup for latest code and other details
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

set -euo pipefail

SCRIPT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}")"; pwd | xargs readlink -f)

source $SCRIPT_DIR/../raspiBackupServer.bash
source $SCRIPT_DIR/../raspiBackupServer.sh

trap 'cleanup $?' SIGINT SIGTERM SIGHUP EXIT
trap 'err $?' ERR

DB_ctor "TestDB"
DB_drop
DB_initialize

DB_tables

DB_ClientAdd "CM4" "192.168.0.158" "pi" "password" "key"
DB_JobAdd "CM4" "/dev/mmcblk0" "3" "13:00" "Mon"

echo "Inserted CM4"
DB_dump

client="CM4"
echo "Get $client client"
IFS="|" read -r id name ip username password sshkey <<<"$(DB_ClientGet "$client")"
echo "$client => $id $name $ip $username $password $sshkey"

echo "Reading CM4 jobs"
IFS="|" read -r clientid device maxbackups time weekdays <<<"$(DB_JobGet "CM4")"
echo "CM4 => $device $maxbackups $time $weekdays"

echo "Deleting CM4"
DB_ClientDelete "CM4"
DB_dump

#DB_dtor
