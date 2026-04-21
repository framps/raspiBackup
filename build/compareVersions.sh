#!/bin/bash

declare -A m=( [gt]=">" [lt]="<" )

cmp() {

	echo -n "$1 ${m[$2]} $3 "
	dpkg --compare-versions "$1" "$2" "$3" && echo yes || echo no
}

echo "Nasty feature of ~"
cmp 1.0~beta lt 1.0
cmp 1.0~1 lt 1.0
cmp 1.0~2 gt 1.0~1echo
echo

echo "Beta replaces a normal version and is replaced by a future version"
cmp 1.0 lt 1.0.1
cmp 1.0-beta gt 1.0
cmp 1.0-beta lt 1.0.1
echo

echo "Hotfixes are replaced by future versions"
cmp 1.0-m-1 gt 1.0
cmp 1.0-m-1 lt 1.0.1
cmp 1.0-m-2 lt 1.0.1
echo

echo "Hotfixes have no dependency to other hotfixes"
cmp 1.0-m-1 lt 1.0-m-2
cmp 1.0-m-2 lt 1.0-m-1
