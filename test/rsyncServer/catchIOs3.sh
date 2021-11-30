#/bin/bash

# Just some code to get familiar with STDIO and STDERR grabbing into variables

# Code grabbed and modified from https://stackoverflow.com/questions/11027679/capture-stdout-and-stderr-into-different-variables


source executeCommand.sh

cmds=("ssh pi@192.168.0.152 ls -q /" \ 
	  "ssh pi@192.168.0.152 ls -b /m" \
  	  "ssh pi@192.168.0.152 sudo lsblk" \
	  "ssh pi@192.168.0.152 cat /etc/fstab" \
	  "ssh pi@192.168.0.152 ls -b /root/.ssh" \
	  "ssh pi@192.168.0.152 sudo ls -b /root/.ssh" \
	  "ssh pi@192.168.0.152 mkdir /dummy" \
	  "ssh pi@192.168.0.152 sudo mkdir /dummy" \
	  "ssh pi@192.168.0.152 ls -b /" \
	  "ssh pi@192.168.0.152 sudo rmdir /dummy")

for cmd in "${cmds[@]}"; do
	echo "CMD: $cmd"
	executeCommand std err "$cmd"
	echo "--- RC: $?"
	echo "--- STDOUT"
	echo "$std"
	echo "--- STDERR"
	echo "$err"
done

