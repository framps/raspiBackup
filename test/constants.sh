#!/bin/bash
#######################################################################################################################
#
# raspiBackup regression test constants
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

BACKUPTYPE_DD="dd"
BACKUPTYPE_DDZ="ddz"
BACKUPTYPE_TAR="tar"
BACKUPTYPE_TGZ="tgz"
BACKUPTYPE_RSYNC="rsync"

BOOTMODE_DD="-B-"
BOOTMODE_TAR="-B+"

MOUNT_HOST=192.168.0.194	# host used to mount remote backup dir
DEPLOYED_IP=192.168.0.191	# IP of simulated Raspberry
EXPORT_DIR="/backup"		# backup directory on host which holds the backups and is exported
BACKUP_DIR="regression"		# -> /backup/regression_N and /backup/regression_P 

LOG_REGRESSION="raspiBackupRegression.log"
LOG_COMPLETED="raspiBackupRegressionCompleted.log"

EXIT_ON_FAILURE=1		# exit tests on failure
