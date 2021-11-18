#!/bin/bash

# Read our variables on different Healthcheck.io checks
source /usr/local/etc/healthcheck.conf

if [ ! -z  "${raspiBackupPing}"] ; then
    curl -s -m 5 --retry 10 --data-raw "Starting raspiBackup" ${raspiBackupPing}/start
else
    wall <<< "Extension detected ${0##*/} failed, undefined variable raspiBackupPing"
    return 1
fi
