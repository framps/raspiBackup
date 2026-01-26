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

SCRIPT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}")"; pwd | xargs readlink -f)

#source "$SCRIPT_DIR"/raspiBackupServer.bash
source ./raspiBackupServer.bash

readonly DB_FILENAME="raspiBackupServer.sql"
readonly DB_CONFIG_FILENAME=".sqliterc"

declare -r PS4='|${LINENO}> \011${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

function DB_ctor() {
	if [[ ! -f $DB_CONFIG_FILENAME ]]; then
		cat > $DB_CONFIG_FILENAME <<-EOF
.bail ON
.echo OFF
PRAGMA foreign_keys = TRUE;
EOF
	fi
}	

function DB_initialize() {
	
    sqlite3 "$DB_FILENAME" <<-EOF
		CREATE TABLE IF NOT EXISTS clients (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			name TEXT NOT NULL,
			ip TEXT UNIQUE NOT NULL,
			username TEXT NOT NULL,
			password TEXT,
			sshkey BOOLEAN DEFAULT 0
);
EOF
	echo "1) $?"

    sqlite3 "$DB_FILENAME" <<-EOF
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

function DB_ClientAdd { # name, ip, username, password, sshkey
	sqlite3 "$DB_FILENAME" <<-EOF
		INSERT INTO clients (name, ip, username, password, sshkey)
		VALUES ("$1", "$2", "$3", "$4", "$5");
EOF
}

function DB_ClientGet { # name
	
    local result; result=$(sqlite3 "$DB_FILENAME" "SELECT * FROM clients WHERE name = \"$1\";")
	echo "---> $?"
	echo "$result"
}

function DB_ClientDelete { # name 
	local clientid 
	DB_JobDelete "$1"
	IFS="|" read -r clientid <<<"$(DB_JobGet "$1")"
	sqlite3 "$DB_FILENAME" "DELETE FROM clients WHERE id = \"$clientid\";"	
}

function DB_JobAdd { # name, ip, username, password, sshkey
	
    local clientId; clientId=$(sqlite3 "$DB_FILENAME" "SELECT id FROM clients WHERE name = \"$1\";")
	if [[ -z "$clientId" ]]; then
		error "$1 not defined"
	fi

	sqlite3 "$DB_FILENAME" <<-EOF
		INSERT INTO jobs (clientid, device, maxbackups, time, weekdays)
		VALUES ("$clientId", "$2", "$3", "$4", "$5");
EOF
}

function DB_JobGet { # name
	
    local clientId; clientId=$(sqlite3 "$DB_FILENAME" "SELECT id FROM clients WHERE name = \"$1\";")
	if [[ -z "$clientId" ]]; then
		error "$1 not defined"
	fi

	local result; result=$(sqlite3 "$DB_FILENAME" "SELECT * FROM jobs WHERE clientid = \"$clientId\";")

	echo "$result"
}

function DB_JobDelete { # name
	local clientid 
	IFS="|" read -r clientid <<<"$(DB_ClientGet "$1")"
	sqlite3 "$DB_FILENAME" "DELETE FROM jobs WHERE clientid = \"$clientid\";"
}

function DB_drop() {	
    sqlite3 "$DB_FILENAME" <<-EOF
		DROP TABLE IF EXISTS clients;
		DROP TABLE IF EXISTS jobs;
EOF
}

function DB_dtor() {	
	rm $DB_FILENAME
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
    
