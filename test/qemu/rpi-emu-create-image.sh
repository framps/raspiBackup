#!/bin/bash
#
#cp 2024-11-19-raspios-bookworm-arm64-lite.img disk.img
#truncate -s +3G disk.img
sudo virt-resize --expand /dev/sda2 2024-11-19-raspios-bookworm-arm64-lite.img disk.img 
sudo losetup -P /dev/loop0 disk.img
sudo mount /dev/loop0p1 /mnt
PW=$(openssl passwd -6)
echo "pi:$PW" | sudo tee /mnt/userconf.txt
sudo touch /mnt/ssh
sudo umount /mnt
sudo losetup -d /dev/loop0
