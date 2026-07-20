#!/bin/bash

check() { # interactive proc_time
	if (( ! $1 )); then
	        if (( $(cut -d' ' -f1 <<< "$2" | cut -d'.' -f1) < 180 )); then
               		return 0
	        fi
	fi
	return 1
}

# Not interactive and inside boot slot
check 0 "10 78563.15"
(( $? )) && { echo "Fail1"; exit; }
# Interactive and inside boot slot
check 1 "10 78563.15"
(( ! $? )) && { echo "Fail2"; exit; }
# Not interactive and outside boot slot
check 0 "10000 78563.15"
(( ! $? )) && { echo "Fail3"; exit; }
# Interactive and outside boot slot
check 1 "10000 78563.15"
(( ! $? )) && { echo "Fail4"; exit; }

