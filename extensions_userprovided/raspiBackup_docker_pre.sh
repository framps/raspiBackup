#!/bin/bash
#######################################################################################################################
#
# Docker plugin for raspiBackup.sh
# called before a backup is started
#
# Function: Stops all running docker-container gracefull.
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for additional information
#
#######################################################################################################################
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

MSG_EXT_DOCKER3="ext_docker_3"
MSG_EN[$MSG_EXT_DOCKER3]="RBK2003I: Stopping Docker-Container: %s "
MSG_DE[$MSG_EXT_DOCKER3]="RBK2003I: Beende Docker-Container: %s"


# gets a list of all running Docker container in one line sperated with blanks
function getRunningContainer () {
  if [[ -x  "$(which docker)"  ]] ; then
    local docker_bin=$(which docker)
    local count_running_container=$($docker_bin container ls -q | wc -l)
    if [[ $count_running_container -gt 0 ]] ; then
     echo "$($docker_bin container ls --format '{{.Names}}'|tr '\n' ' ')"
    else
     echo ""
    fi
 fi 
}

# stops all given docker container
function stopRunningContainer () { 
  local running_container=$1	
  if [[ -n "${running_container}" ]] ; then
    writeToConsole  $MSG_LEVEL_MINIMAL $MSG_EXT_DOCKER3 "$running_container"
    local docker_bin=$(which docker)
    $docker_bin container stop $running_container 2>&1>/dev/null
  fi
}

# ext_dockerContainer_pre is used in raspiBackup_docker_post.sh to start all 
# stopped container
ext_dockerContainer_pre="$(getRunningContainer)" 
stopRunningContainer "$ext_dockerContainer_pre"
