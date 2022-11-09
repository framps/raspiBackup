#!/bin/bash
#######################################################################################################################
#
# Sample plugin for raspiBackup.sh
# called after a backup finished
#
# Function: starts all stopped docker container
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for additional information
#
########################################################################################################################
#
#    Copyright (c) 2022 Springjunky (https://github.com/Springjunky)
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
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.#
#
#######################################################################################################################

GIT_DATE="$Date$"
GIT_COMMIT="$Sha1$"

# set any variables and prefix all names with ext_ and some unique prefix to use a different namespace than the script
# list of docker container stored in ext_dockerContainer_pre

MSG_EXT_DOCKER1="ext_docker_1"
MSG_EN[$MSG_EXT_DOCKER1]="RBK2001I: Starting before stopped docker-container: %s "
MSG_DE[$MSG_EXT_DOCKER1]="RBK2001I: Starte zuvor gestoppte Docker-Container: %s"

MSG_EXT_DOCKER2="ext_docker_2"
MSG_EN[$MSG_EXT_DOCKER2]="RBK2002I: Error with docker-container please check status: %s"
MSG_DE[$MSG_EXT_DOCKER2]="RBK2002I: Fehler bei Docker-Container bitte Status prüfen: %s"


# $MSG_LEVEL_MINIMAL will write message all the time
# $MSG_LEVEL_DETAILED will write message only if -m 1 parameter was used
if [[ -n "${ext_dockerContainer_pre}" ]]; then
     writeToConsole  $MSG_LEVEL_MINIMAL $MSG_EXT_DOCKER1 "$ext_dockerContainer_pre"
     for container_to_start in $ext_dockerContainer_pre ; do 
       # the pre script checks, if docker was available at  /usr/bin/docker
       /usr/bin/docker start $container_to_start 2>&1>/dev/null
      if [[ $? -ne 0 ]] ; then
        writeToConsole  $MSG_LEVEL_MINIMAL $MSG_EXT_DOCKER2 ${container_to_start}
      fi
     done
fi
