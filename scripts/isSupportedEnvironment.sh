#!/bin/bash

function isSupportedEnvironment() {

	local MODELPATH=/sys/firmware/devicetree/base/model
	local OSRELEASE=/etc/os-release

	[[ ! -e $MODELPATH ]] && return 1
	! grep -q -i "raspberry" $MODELPATH && return 1

	[[ ! -e $OSRELEASE ]] && return 1

	! grep -q -E -i "NAME=.*raspbian" $OSRELEASE && return 1

	return 0
}

if isSupportedEnvironment; then
	echo "Supported"
else
	echo "NOT supported"
fi

