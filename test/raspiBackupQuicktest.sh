#######################################################################################################################
#
# raspiBackup quicktest using fake option
#
#######################################################################################################################
#
#    Copyright (C) 2019 framp at linux-tips-and-tricks dot de
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

#sudo ./raspiBackup.sh -F -x -c -e $(<email.conf) -m 1 -l 1 -t tar -L 3 -p "/tmp/ra test"
sudo ../raspiBackup.sh -F -x -c -e $(<email.conf) -Z -m 1 -l 1 -L 3 -o : -a : $@
#sudo ../raspiBackup.sh -F -x -c -e $(<email.conf) -z -m 1 -l 1 -L 3 -N "temp mem" $@
#sudo ../raspiBackup.sh -F -x -c -e $(<email.conf) -z -m 1 -l 1 -L 3 -o "service smbd stop" -a "service smbd start" $@
#sudo ../raspiBackup.sh -F -x -c -e $(<email.conf) -z -m 1 -l 1 -L 3 -o "service ssh stop" -a "service ssh start" $@
