#!/bin/bash
#######################################################################################################################
#
# raspiBackup backup creation on a linux system (no Raspbian and Raspberry)
#
#######################################################################################################################
#
#    Copyright (C) 2013-2019 framp at linux-tips-and-tricks dot de
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
#sudo ../raspiBackup.sh -x -c -e $(<email.conf) -Z -m 1 -l 1 -L 3
sudo ../raspiBackup.sh -t rsync -x -c -Z -m 1 -l 1 -L 3 -a : -o : $@
