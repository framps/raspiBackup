#!/bin/bash

CMD="$1"
ME="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
CONTAINER_NAME="Raspberry"
IMAGE_NAME="lukechilds/dockerpi"

case $CMD in

portainer) # Install portainer
	docker volume create portainer_data
	docker stop portainer
	docker rm portainer
	docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
   ;;

initialize) ## start vm in detached mode
	docker run -d --name $CONTAINER_NAME $IMAGE_NAME
   ;;

interactive) ## start in interactive mode
containerID=$(docker run -it $IMAGE_NAME)
    ;;

buildVM) ## build vm
	cd ~/github.com/lukechilds/dockerpi
	docker build -t lukechilds/dockerpi:vm --target dockerpi-vm .
	cd -
   ;;

start) ## start raspberrypi
	echo "Starting $CONTAINER_NAME"
	containerID=$(docker start $CONTAINER_NAME)
	#containerID=$(docker start -v "$(pwd)"/scratch:/mnt $CONTAINER_NAME)
	containerIP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CONTAINER_NAME)
	echo "Raspberrypi ssh access: ssh -p 5022 pi@$containerIP"
    ;;

*) ##help
	echo "Possible commands"
	grep -E '^[a-zA-Z_-]+\).*?## .*$$' $ME |sort | awk 'BEGIN {FS = ").*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $1, $2}'
   ;;
esac

