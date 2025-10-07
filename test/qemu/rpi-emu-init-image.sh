#!/bin/bash
#
source ../env.defs

if ! ping -c 1 $DEPLOYED_IP; then

cd ..
. ./rpi-emu-start.sh bookworm.qcow2 &
fi

echo "Waiting for VM with IP $DEPLOYED_IP to come up"
        while ! ping -c 1 $DEPLOYED_IP &>/dev/null; do
                sleep 3
        done

echo "Copy pub key"
ssh-copy-id pi@$DEPLOYED_IP
sudo scp /root/.ssh/id_rsa.pub pi@$DEPLOYED_IP:~
echo "Copy  authorized_keys"
ssh pi@$DEPLOYED_IP "sudo cp /home/pi/.ssh/authorized_keys /root/.ssh/authorized_keys"

