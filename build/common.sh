#!/bin/bash
#

LOG_FILE="build.log"

function err() {
    local rc="$1"
    echo "??? Unexpected error occured with RC $rc"
    local i=0
    local FRAMES=${#BASH_LINENO[@]}
    for ((i = FRAMES - 2; i >= 0; i--)); do
        echo '  File' \"${BASH_SOURCE[i + 1]}\", line ${BASH_LINENO[i]}, in ${FUNCNAME[i + 1]}
        sed -n "${BASH_LINENO[i]}{s/^/    /;p}" "${BASH_SOURCE[i + 1]}"
    done
    exit 42
}

function show() {
	echo "==============================="
	echo "===> $@ ..."
	echo "==============================="
}
