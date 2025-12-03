#!/bin/bash
#######################################################################################################################
#
#    Startup a qemu Raspberry image
#
#	 Code based on code and qemu setup descriptions from https://crycode.de/raspberry-pi-4-emulieren-mit-qemu/
#	 and updated to meet special raspiBackup requirements
#
#######################################################################################################################
#
#    Copyright (c) 2025 framp at linux-tips-and-tricks dot de
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

IMAGE=$1	  # Image
CPU_CORES=4       # CPU-Kerne (bis zu 8)
RAM_SIZE=4G       # Größe des Arbeitsspeichers
SSH_PORT=2222     # Lokaler Port für den SSH-Zugriff
MONITOR_PORT=5555 # Lokaler Port für die QEMU Monitor Konsole
ARGS=$2           # Zusätzliche Argument (-nographic um ohne grafisches Fenster zu starten)
ENV_FILE="$(dirname "$0")/../env.defs"

if [[ ! -f $ENV_FILE ]]; then
	echo "Missing $ENV_FILE"
	exit 1
fi

source $ENV_FILE

EXTENSION="${IMAGE##*.}"
FILENAME="${IMAGE%.*}"


[[ $EXTENSION == "img" || $IMAGE == $EXTENSION ]] && { FORMAT="raw"; EXT="img"; } || { FORMAT="qcow2"; EXT="qcow2"; }

if [[ ! -f ${QEMU_IMAGES}/${FILENAME}.$EXT ]]; then
	echo "${QEMU_IMAGES}/${FILENAME}.$EXT not found"
	exit 1
fi

sudo qemu-system-aarch64 -machine virt -cpu cortex-a72 \
  -smp ${CPU_CORES} -m ${RAM_SIZE} \
  -kernel ${KERNEL_DIR}/kernel \
  -append "root=/dev/vda2 rootfstype=ext4 rw panic=0 console=ttyAMA0" \
  -drive format=$FORMAT,file=${QEMU_IMAGES}/$FILENAME.$EXT,if=none,id=hd0,cache=writeback \
  -net nic,macaddr=DE:AD:BE:EF:44:DC \
  -net tap \
   -device virtio-blk,drive=hd0,bootindex=0 \
 -monitor telnet:127.0.0.1:${MONITOR_PORT},server,nowait \
  $ARGS

# -netdev user,id=mynet,hostfwd=tcp::${SSH_PORT}-:22 \


