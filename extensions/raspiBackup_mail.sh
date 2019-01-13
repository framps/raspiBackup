#!/bin/bash
#######################################################################################################################
#
# Sample email plugin for raspiBackup.sh
#
# Function: Send success/failure email
#
# Enable with 'mailext' as parameter to -s
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for additional information
#
#######################################################################################################################
#
#    Copyright (C) 2015-2017 framp at linux-tips-and-tricks dot de
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.#
#
#######################################################################################################################

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
