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

trap 'cleanup $?' SIGINT SIGTERM SIGHUP EXIT
trap 'err $?' ERR

source ./raspiBackupFuncs.sh

readonly DB_FILENAME="raspiBackupServer.sql"

function DB_ctor() { 
	readonly DB_filename="DB_FILENAME"
}	

function DB_initialize() {
	
    sqlite3 "$DB_FILENAME" <<EOF
		CREATE TABLE IF NOT EXISTS clients (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			name TEXT NOT NULL,
			ip TEXT UNIQUE NOT NULL,
			username TEXT NOT NULL,
			password TEXT,
			sshkey BOOLEAN DEFAULT 0
);
EOF

    sqlite3 "$DB_FILENAME" <<EOF
		CREATE TABLE IF NOT EXISTS jobs (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			clientid INTEGER NOT NULL,
			device TEXT NOT NULL,
			maxbackups INTEGER NOT NULL,
			time TEXT NOT NULL, -- 'HH:MM' or auto-generated
			weekdays TEXT DEFAULT 'Sat',
			FOREIGN KEY (clientid) REFERENCES clients(id)
);
EOF
}

function DB_addClient { # name, ip, username, password, sshkey
	sqlite3 "$DB_FILENAME" <<EOF
		INSERT INTO clients (name, ip, username, password, sshkey)
		VALUES ("$1", "$2", "$3", "$4", "$5");
EOF
}

function DB_addJob { # name, ip, username, password, sshkey
	
    local clientId=$(sqlite3 "$DB_FILENAME" "SELECT id FROM clients WHERE name = \"$1\";")
	if [[ -z "$clientId" ]]; then
		error "$1 not defined"
	fi

	sqlite3 "$DB_FILENAME" <<EOF
		INSERT INTO jobs (clientid, device, maxbackups, time, weekdays)
		VALUES ("$clientId", "$2", "$3", "$4", "$5");
EOF
}

function DB_getJob { # name
	
    local clientId=$(sqlite3 "$DB_FILENAME" "SELECT id FROM clients WHERE name = \"$1\";")
	if [[ -z "$clientId" ]]; then
		error "$1 not defined"
	fi

	local result=$(sqlite3 "$DB_FILENAME" "SELECT clientid, device, maxbackups, time, weekdays FROM jobs WHERE clientid = \"$clientId\";")

	echo "$result"

}

function DB_drop() {	
    sqlite3 "$DB_FILENAME" <<EOF
		DROP TABLE IF EXISTS clients;
		DROP TABLE IF EXISTS jobs;
EOF
}

function DB_tables() {	
	sqlite3 "$DB_FILENAME" <<-EOF
		.tables
		.schema clients;
		.schema jobs;
EOF
}

function DB_dump() {	
	sqlite3 "$DB_FILENAME" <<-EOF
		.headers on	
		SELECT * FROM clients;
		SELECT * FROM jobs;
EOF
}	
    
DB_ctor
DB_drop
DB_initialize

DB_tables

DB_addClient "CM4" "192.168.0.158" "pi" "password" "key"
DB_addJob "CM4" "/dev/mmcblk0" "3" "13:00" "Mon"

IFS="|" read -r clientid device maxbackups time weekdays <<<"$(DB_getJob "CM4")"
echo "CM4 => $device $maxbackups $time $weekdays"

DB_dump
