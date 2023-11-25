#!/bin/bash

CONTAINER_NAME="Raspberry"

case $1 in

    portainer) 
# Install portainer
docker volume create portainer_data
docker stop portainer
docker rm portainer
docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
    ;;

interactive)

# Start Raspberry in interactive mode to initialize image (systemctl enable ssh) and reboot
# docker run --name $CONTAINER_NAME -it lukechilds/dockerpi

containerID=$(docker run -d lukechilds/dockerpi)
    ;;

*)

echo "Starting $CONTAINER_NAME"
containerID=$(docker start $CONTAINER_NAME)
#containerID=$(docker start -v "$(pwd)"/scratch:/mnt $CONTAINER_NAME)
containerIP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CONTAINER_NAME)
echo "Raspberrypi ssh access: ssh -p 5022 pi@$containerIP"
    ;;
esac
