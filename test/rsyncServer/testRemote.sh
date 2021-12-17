#!/bin/bash

# Check on (remote) host whether ACLs were transferred correctly

DEBUG=0

function verifyTestData() { # directory

	local rc=0

	(( $DEBUG )) && echo "Testing  $1/acl.txt"
	(( $DEBUG )) && getfacl $1/acl.txt
	if [[ ! -f $1/acl.txt ]]; then
		echo "??? acl.txt not found ???"
		rc=1
	else
		getfacl $1/acl.txt | grep -q "user:root"
		if (( $? )); then
			echo "??? ACL not found ???"
			rc=1
		else
			: echo "!!! ACL found !!!"
		fi
	fi

	(( $DEBUG )) && echo "Testing  $1/noacl.txt"
	(( $DEBUG )) && getfacl $1/noacl.txt
	if [[ ! -f $1/noacl.txt ]]; then
		echo "??? noacl.txt not found ???"
		rc=1
	else
		getfacl $1/noacl.txt | grep -q "user:root"
		if (( ! $? )); then
			echo "??? ACL found ???"
			rc=1
		else
			: echo "!!! ACL not found !!!"
		fi
	fi

	return $rc
}

#echo "Testing $1"

verifyTestData "$1"
