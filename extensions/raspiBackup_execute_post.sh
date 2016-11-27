#!/bin/bash

#
# extensionpoint for raspiBackup.sh
# called after a backup finished
#
# Function: Call another script
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for additional information 
#
# (C) 2016 - framp at linux-tips-and-tricks dot de
#
# $1 has the return code of raspiBackup. If it equals 0 this signals success and failure otherwise
#

if [[ -n $1 ]]; then											# was there a return code ? Should be :-)
	if [[ "$1" == 0 ]]; then						
		wall <<< "Extension detected ${0##*/} succeeded :-)"
	else
		wall <<< "Extension detected ${0##*/} failed :-("
	fi
else
	wall <<< "Extension detected ${0##*/} didn't receive a return code :-("
fi
	
		
		

