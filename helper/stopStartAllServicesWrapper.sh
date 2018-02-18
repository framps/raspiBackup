#!/bin/bash

# Sample script to wrap raspiBackup.sh in order
# to stop all running services before backup and restart them after backup
#
# Visit http://www.linux-tips-and-tricks.de/raspiBackup for details about raspiBackup
#
# (C) 2018 - framp at linux-tips-and-tricks dot de

trap startAllServices EXIT ERR

function shutdownAllServices () {
	[[ -z $SERVICE ]] && retrieveAllActiveServices
	for (( idx=${#SERVICES[@]}-1 ; idx>=0 ; idx-- )); do
		echo "service ${SERVICES[idx]} stop &>/dev/null"
	done
}

function startAllServices () {
	[[ -z $SERVICE ]] && retrieveAllActiveServices
	for SERVICE in ${SERVICES[@]}; do
		echo "service $SERVICE start &>/dev/null"
	done
}

function retrieveAllActiveServices() {
	RUNLEVEL=$(/sbin/runlevel | cut -d' ' -f2)
	for script in $(ls /etc/rc${RUNLEVEL}.d/S*); do
		SERVICES+=($(basename $script | sed 's~^S[0-9]*~~g'))
	done
}

declare -a SERVICES

shutdownAllServices
raspiBackup.sh -a : -o :
trap
startAllServices


