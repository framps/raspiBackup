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

	echo "Waiting for ssh to come up ..."
	while ! nc -zv $DEPLOYED_IP 22 &>/dev/null; do
		sleep 3
		echo -n "."
	done
fi

echo "Copy pub key"
ssh-copy-id pi@$DEPLOYED_IP
sudo scp /root/.ssh/id_rsa.pub pi@$DEPLOYED_IP:~
echo "Copy  authorized_keys"
ssh pi@$DEPLOYED_IP "sudo cp /home/pi/.ssh/authorized_keys /root/.ssh/authorized_keys"

