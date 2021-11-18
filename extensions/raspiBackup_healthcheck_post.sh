#!/bin/bash

# Read our variables on different Healthcheck.io checks
source /usr/local/etc/healthcheck.conf

if [[ -n $1 ]]; then    # was there a return code ? Should be :-)
    if [[ "$1" == 0 ]]; then
        if [ ! -z  "${raspiBackupPing}"] ; then
            curl -s -m 5 --retry 10 --data-raw "raspiBackup OK" ${raspiBackupPing}
        else
            wall <<< "Extension detected ${0##*/} failed, undefined variable raspiBackupPing"
			return 1
        fi
    else
        wall <<< "Extension detected ${0##*/} failed :-("
    fi
else
    wall <<< "Extension detected ${0##*/} didn't receive a return code :-("
fi
