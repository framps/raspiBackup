#!/bin/bash
#

source $(dirname "$0")/../env.defs

if ! ping -c 1 $DEPLOYED_IP; then

	rpi-emu-start.sh bookworm.img &

	echo "Waiting for VM with IP $DEPLOYED_IP to come up"
       	while ! ping -c 1 $DEPLOYED_IP &>/dev/null; do
               	sleep 3
		echo -n "."
        done
	echo
	echo "Waiting for ssh to come up ..."
	while ! nc -zv $DEPLOYED_IP 22 &>/dev/null; do
		sleep 3
		echo -n "."
	done
	echo
fi

sudo ssh-keygen -f '/root/.ssh/known_hosts' -R '192.168.0.191'
echo "Copy my pub key to pi"
ssh-copy-id pi@$DEPLOYED_IP
echo "Copy my root pub key to pi"
sudo cp /root/.ssh/id_rsa.pub .
scp id_rsa.pub pi@$DEPLOYED_IP:~
echo "Updating authorized_keys of pi"
ssh pi@$DEPLOYED_IP "cat /home/pi/id_rsa.pub >> authorized_keys"
ssh pi@$DEPLOYED_IP "rm /home/pi/id_rsa.pub"
echo "Updating authorized_keys of root on pi"
ssh pi@$DEPLOYED_IP "sudo cp /home/pi/.ssh/authorized_keys /root/.ssh/authorized_keys"
sudo rm id_rsa.pub
echo "Shutting down $DEPLOYED_IP
ssh pi@$DEPLOYED_IP "sudo shutdown -h now"
