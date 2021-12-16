#!/bin/bash

# Check on (remote) host whether ACLs were transferred correctly

DEBUG=1

function verifyTestData() { # directory

	(( $DEBUG )) && echo "Testing  $1/acl.txt"
	(( $DEBUG )) && getfacl $1/acl.txt
	if [[ ! -f $1/acl.txt ]]; then
		echo "??? acl.txt not found ???"
	else
		getfacl $1/acl.txt | grep -q "user:root"
		if (( $? )); then
			echo "??? ACL not found ???"
		else
			: echo "!!! ACL found !!!"
		fi
	fi

	(( $DEBUG )) && echo "Testing  $1/noacl.txt"
	(( $DEBUG )) && getfacl $1/noacl.txt
	if [[ ! -f $1/noacl.txt ]]; then
		echo "??? noacl.txt not found ???"
	else
		getfacl $1/noacl.txt | grep -q "user:root"
		if (( ! $? )); then
			echo "??? ACL found ???"
		else
			: echo "!!! ACL not found !!!"
		fi
	fi
}

#echo "Testing $1"

verifyTestData "$1"
