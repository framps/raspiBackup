#######################################################################################################################
#
# 	Makefile for raspiBackup
#
# 	See http://www.linux-tips-and-tricks.de/raspiBackup for additional information
#
#######################################################################################################################
#
#    Copyright (c) 2021-2024 framp at linux-tips-and-tricks dot de
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

PACKAGE_FILES = installation/install.sh installation/raspiBackupInstallUI.sh raspiBackup.sh extensions/raspiBackupSampleExtensions.tgz properties/raspiBackup.properties
PACKAGE_FILE_COLLECTIONS = config/*
PACKAGE_EXTENSION_DIRECTORY = extensions
PACKAGE_EXTENSION_FILES_PREFIX = raspiBackup_*
PACKAGE_EXTENSION_FILES = $(PACKAGE_EXTENSION_DIRECTORY)/$(PACKAGE_EXTENSION_FILES_PREFIX)
FILES_TO_SIGN = raspiBackup.sh raspiBackupInstallUI.sh

include $(CURRENT_DIR)/$(MAKEFILE).env
# Has to define following environment constants:
# 1) GITHUB_REPO - local directoy of github repo
# 2) LOCAL_REPO - local shadow repo
# 3) MASTER_BRANCH - should be master
# 4) BETA_BRANCH - should be beta
# 5) BUILD_LOCATION - local directory the code is built
# 6) DEPLOYMENT_LOCATION - directory the code is deployed

help: ## help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

build: buildFiles

deploy: buildFiles deployFiles

buildFiles: ## Build raspiBackup {BRANCH=<branchName>}

        ifndef BUILD_LOCATION
           $(error BUILD_LOCATION is not set)
        endif

        ifndef BRANCH
           $(error BRANCH is not set)
        endif

	@echo "*** Building $(BRANCH) in $(BUILD_LOCATION) ***"

	@$(foreach file, $(PACKAGE_FILES), rm -f $(file);)
	@$(foreach file, $(wildcard $(PACKAGE_FILE_COLLECTIONS)), rm -f $(file);)
	@$(foreach file, $(wildcard $(PACKAGE_EXTENSION_FILES)), rm -f $(file);)

	@git checkout HEAD
	@git checkout -f $(BRANCH)

	@rm -f $(BUILD_LOCATION)/*
	@$(foreach file, $(wildcard $(PACKAGE_FILE_COLLECTIONS)), cp -a $(file) $(BUILD_LOCATION)/$(notdir $(file));)
	@cd $(PACKAGE_EXTENSION_DIRECTORY) && tar --owner=root --group =root -cvzf raspiBackupSampleExtensions.tgz $(PACKAGE_EXTENSION_FILES_PREFIX)
	@$(foreach file, $(PACKAGE_FILES), cp -a $(file) $(BUILD_LOCATION)/$(notdir $(file));)

	@rm $(PACKAGE_EXTENSION_DIRECTORY)/raspiBackupSampleExtensions.tgz

signFiles: # sign files
	@$(foreach file, $(FILES_TO_SIGN), gpg --sign --default-key $(SIGNER_EMAIL) $(BUILD_LOCATION)/$(file);)

update: buildFiles ## Update one file {FILE=<filename>}
    ifeq ("$(wildcard $(DEPLOYMENT_LOCATION))", "")
		$(error Directory $(DEPLOYMENT_LOCATION) not mounted)
    endif
	@cp $(BUILD_LOCATION)/$(FILE) $(DEPLOYMENT_LOCATION)/$(notdir $(BUILD_LOCATION)/$(FILE)); echo "Updated $(FILE) on $(DEPLOYMENT_LOCATION)";

deployFiles: ## Deploy build {BRANCH=<branchName>}

        ifndef DEPLOYMENT_LOCATION
		$(error DEPLOYMENT_LOCATION is not set)
        endif

        ifndef BRANCH
		$(error BRANCH is not set)
        endif

	@echo "*** Deploying $(BRANCH) in $(DEPLOYMENT_LOCATION) ***"
	@$(foreach file, $(wildcard $(BUILD_LOCATION)/*), echo "Deploy $(file) "; cp $(file) $(DEPLOYMENT_LOCATION)/$(notdir $(file));)

syncLocal: ## Sync github to local shadow git
	@$(foreach file, $(PACKAGE_FILES), echo "Copying $(file) "; cp -a $(GITHUB_REPO)/$(file) $(LOCAL_REPO)/$(file);)
	@$(foreach file, $(wildcard $(PACKAGE_FILE_COLLECTIONS)), echo "Copying $(file) "; cp -a $(GITHUB_REPO)/$(file) $(LOCAL_REPO)/$(file);)
	@$(foreach file, $(wildcard $(PACKAGE_EXTENSION_FILES)), echo "Copying $(file) "; cp -a $(GITHUB_REPO)/$(file) $(LOCAL_REPO)/$(file);)

syncRemote: ## Sync local git to github
	@$(foreach file, $(PACKAGE_FILES), echo "Copying $(file) "; cp -a $(LOCAL_REPO)/$(file) $(GITHUB_REPO)/$(file) ;)
	@$(foreach file, $(wildcard $(PACKAGE_FILE_COLLECTIONS)), echo "Copying $(file) "; cp -a $(LOCAL_REPO)/$(file) $(GITHUB_REPO)/$(file) ;)
	@$(foreach file, $(wildcard $(PACKAGE_EXTENSION_FILES)), echo "Copying $(file) "; cp -a $(LOCAL_REPO)/$(file) $(GITHUB_REPO)/$(file) ;)
