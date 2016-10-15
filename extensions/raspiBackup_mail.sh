#!/bin/bash
#
# Sample implementation for email extensionpoint for raspiBackup.sh
#
# Function: Send success/failure email
#
# Enable with 'mailext' as parameter to -s
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for additional information 
#
# (C) 2015 - framp at linux-tips-and-tricks dot de
#

# Parameters received by script: "$EMAIL" "$subject" "$content" "$EMAIL_PARMS" "$append"

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}

DEBUG=0			# 0/1 toggle for debugging

# guard for invalid invocation

if [[ $# != 5 ]]; then
	echo "Missing parameters for $MYNAME. Expected: 5. Received $#"
	exit 127
fi

# just copy the parameters into variable names which express the variable purpose

email="$1"		# target email address
subject="$2"	# email subject
content="$3"	# email contents
parms="$4"		# addtl email parms passed with -E
append="$5"		# file to append

# print received parameters for debugging purposes

if (( $DEBUG )); then
	echo "email: ->$email<-"
	echo "subject: ->$subject<-"
	echo "content: ->$content<-"
	echo "parms: ->$parms<-"
	echo "append: ->$append<-"
fi

[[ -n $append ]] && append="-a $append"

(( $DEBUG )) && set -x

# sample to send mail with mailx client

mailx $parms -s "$subject" $append "$email"	<<< "$content"

exit 0
