#!/bin/bash

# Check and test version comparison

declare -A m=( [gt]=">" [lt]="<" )

cmp() {
	local result
	echo -n "$1 ${m[$2]} $3 : "
	dpkg --compare-versions "$1" "$2" "$3"
	result=$?
	(( $result )) && echo "no" || echo "yes"
	if [[ -n $4 ]]; then
		if (( $result == 0 )); then
			echo "Error: no expected"
			exit 42
		fi
	elif (( $result ==  1 )); then
			echo "Error yes expected"
			exit 42
	fi
}

echo "Beta replaces current and RC replaces current version and Beta and is replaced by a future version"
cmp 1.0 lt 1.0.1
cmp 1.0.1~beta gt 1.0
cmp 1.0.1~rc1 gt 1.0
cmp 1.0.1~rc1 gt 1.0.1~beta
cmp 1.0.1~rc2 gt 1.0.1~beta
cmp 1.0.1~rc2 gt 1.0.1~rc1
cmp 1.0.1~rc2 lt 1.0.1

echo

echo "Hotfixes are replaced by future versions and betas and and release candidates"
cmp 1.0-m1 gt 1.0
cmp 1.0-m1 lt 1.0.1
cmp 1.0-m2 lt 1.0.1
cmp 1.0-m1 lt 1.0.1~beta1
cmp 1.0-m1 lt 1.0.1~rc1
echo

echo "Hotfixes have no dependency to other hotfixes"
cmp 1.0-m1 lt 1.0-m2
cmp 1.0-m2 lt 1.0-m1 no
