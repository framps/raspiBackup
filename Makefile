#######################################################################################################################
#
# 	Makefile for raspiBackup
#
# 	See http://www.linux-tips-and-tricks.de/raspiBackup for additional information
#
#######################################################################################################################
#
#    Copyright (c) 2021 framp at linux-tips-and-tricks dot de
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

CURRENT_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
MAKEFILE := $(word $(words $(MAKEFILE_LIST)),$(MAKEFILE_LIST))

PACKAGE_FILES = installation/raspiBackupInstallUI.sh raspiBackup.sh extensions/raspiBackupSampleExtensions.tgz properties/raspiBackup0613.properties
PACKAGE_FILE_COLLECTIONS = config/*
PACKAGE_EXTENSION_DIRECTORY = extensions
PACKAGE_EXTENSION_FILES = $(PACKAGE_EXTENSION_DIRECTORY)/raspiBackup_*

include $(CURRENT_DIR)/$(MAKEFILE).env

help: ## help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

deploy: ## Deploy raspiBackup
	@$(foreach file, $(PACKAGE_FILES), echo "Deleting $(file) "; rm $(file);)
	@$(foreach file, $(wildcard $(PACKAGE_FILE_COLLECTIONS)), echo "Deleting $(file) "; rm $(file);)
	@$(foreach file, $(wildcard $(PACKAGE_EXTENSION_FILES)), echo "Deleting $(file) "; rm $(file);)

	@git checkout -f $(LOCAL_MASTER_BRANCH)

	@$(foreach file, $(wildcard $(PACKAGE_FILE_COLLECTIONS)), echo "Deploying $(file) "; cp -a $(file) $(DEPLOYMENT_LOCATION)/$(notdir $(file));)
	@tar --exclude raspiBackup.sh -cvzf $(PACKAGE_EXTENSION_DIRECTORY)/raspiBackupSampleExtensions.tgz $(PACKAGE_EXTENSION_DIRECTORY)/*.sh
	@$(foreach file, $(PACKAGE_FILES), echo "Deploying $(file) "; cp -a $(file) $(DEPLOYMENT_LOCATION)/$(notdir $(file));)

	@rm $(PACKAGE_EXTENSION_DIRECTORY)/raspiBackupSampleExtensions.tgz

syncLocal: ## Sync github with local git
	@$(foreach file, $(PACKAGE_FILES), echo "Copying $(file) "; cp -a $(GITHUB_REPO)/$(file) $(LOCAL_REPO)/$(file);)
	@$(foreach file, $(wildcard $(PACKAGE_FILE_COLLECTIONS)), echo "Copying $(file) "; cp -a $(GITHUB_REPO)/$(file) $(LOCAL_REPO)/$(file);)
	@$(foreach file, $(wildcard $(PACKAGE_EXTENSION_FILES)), echo "Copying $(file) "; cp -a $(GITHUB_REPO)/$(file) $(LOCAL_REPO)/$(file);)

syncRemote: ## Sync local git with github
	@$(foreach file, $(PACKAGE_FILES), echo "Copying $(file) "; cp -a $(LOCAL_REPO)/$(file) $(GITHUB_REPO)/$(file) ;)
	@$(foreach file, $(wildcard $(PACKAGE_FILE_COLLECTIONS)), echo "Copying $(file) "; cp -a $(LOCAL_REPO)/$(file) $(GITHUB_REPO)/$(file) ;)
	@$(foreach file, $(wildcard $(PACKAGE_EXTENSION_FILES)), echo "Copying $(file) "; cp -a $(LOCAL_REPO)/$(file) $(GITHUB_REPO)/$(file) ;)
