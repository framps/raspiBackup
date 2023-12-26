#!/bin/bash
#######################################################################################################################
#
# 	 Manage raspiBackup docker image
#
####################################################################################################
#
#    Copyright (c) 2023 framp at linux-tips-and-tricks dot de
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
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#######################################################################################################################

CMD="$1"
ME="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
CONTAINER_NAME="Raspberry"
IMAGE_NAME="lukechilds/dockerpi:vm"
#OS_IMAGE_NAME="2022-01-28-raspios-bullseye-arm64-lite.img"
OS_IMAGE_NAME="2020-02-13-raspbian-buster-lite.img"

case $CMD in

portainer) # Install portainer
	docker volume create portainer_data
	docker stop portainer
	docker rm portainer
	docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
   ;;

initialize) ## start vm in detached mode
	docker run -d --name $CONTAINER_NAME -v $(pwd)/$OS_IMAGE_NAME:/sdcard/filesystem.img $IMAGE_NAME
   ;;

interactive) ## start in interactive mode
	docker stop $CONTAINER_NAME 
	docker rm $CONTAINER_NAME 
	# docker run -it --name $CONTAINER_NAME $IMAGE_NAME
	 #docker volume create nfs
	 #docker container rm $CONTAINER_NAME
	 #docker run -it --name $CONTAINER_NAME -v $(pwd)/$OS_IMAGE_NAME:/sdcard/filesystem.img -v nfs:/nfs $IMAGE_NAME
     docker run -it --name $CONTAINER_NAME -v $(pwd)/$OS_IMAGE_NAME:/sdcard/filesystem.img $IMAGE_NAME
    ;;

# exec qemu-system-arm   --machine versatilepb   --cpu arm1176   --m 256m   --drive format=raw,file=/sdcard/filesystem.img   --net nic --net user,hostfwd=tcp::5022-:22   --dtb /root/qemu-rpi-kernel/versatile-pb.dtb   --kernel /root/qemu-rpi-kernel/kernel-qemu-4.19.50-buster   --append rw earlyprintk loglevel=8 console=ttyAMA0,115200 dwc_otg.lpm_enable=0 root=/dev/sda2 rootwait panic=1    --no-reboot   --display none   --serial mon:stdio
buildVM) ## build vm
	cd ~/github.com/lukechilds/dockerpi
	docker build -t $IMAGE_NAME --target dockerpi-vm .
	cd -
   ;;

start) ## start raspberrypi
	echo "Starting $CONTAINER_NAME"
	containerID=$(docker start $CONTAINER_NAME)
	#containerID=$(docker start -v "$(pwd)"/scratch:/mnt $CONTAINER_NAME)
	containerIP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CONTAINER_NAME)
	echo "Raspberrypi ssh access: ssh -p 5022 pi@$containerIP"
    ;;

inspect) ## Open bash shell in container
	docker exec -it Raspberry /bin/sh
	;;

*) ##help
	echo "Possible commands"
	grep -E '^[a-zA-Z_-]+\).*?## .*$$' $ME |sort | awk 'BEGIN {FS = ").*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $1, $2}'
   ;;
esac

