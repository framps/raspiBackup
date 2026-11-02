#!/bin/bash
#
# Regressiontest of raspiBackupConfig: functions which don't need a dialog.
# Versions, days of the timer, configuration update and merge, cron and systemd timer update,
# masquerading of the log and the actions of the unattended options -i -U -R -m -u.
# apt-cache, dpkg-query, systemctl and all functions which change the system are replaced by stubs,
# all files are created in a temporary directory, so neither root nor a repository is needed.
#

# the variables set here are used by the functions of raspiBackupConfig, the variables used are set by them
# shellcheck disable=SC2034,SC2154
# shellcheck source=../../../installation/raspiBackupConfig.sh
source ../../../installation/raspiBackupConfig.sh

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
LOG_FILE="$TMP/raspiBackupConfig.log"
TEMPLATE_EN="../../../config/raspiBackup_en.conf"

error=0
checks=0

# --- helpers

assertEquals() { # description expected actual
	(( checks++ ))
	if [[ "$2" != "$3" ]]; then
		echo "Error: $1"
		echo "       expected: $2"
		echo "       actual:   $3"
		error=1
	fi
}

assertRc() { # description expectedRc command... - rc of the command
	local description="$1" expected="$2" rc
	shift 2
	"$@"
	rc=$?
	assertEquals "$description" "$expected" "$rc"
}

configValue() { # option - value of the option in the config
	grep -m1 "^$1=" "$CONFIG_ABS_FILE" | cut -d= -f2-
}

# --- compareVersions: -1 lower, 0 equal, 1 higher, suffixes are ignored

assertEquals "compare lower" "-1" "$(compareVersions 0.7.4 0.7.5)"
assertEquals "compare equal" "0" "$(compareVersions 0.7.5 0.7.5)"
assertEquals "compare numeric, not alphabetic" "1" "$(compareVersions 0.7.10 0.7.9)"
assertEquals "compare missing parts are 0" "0" "$(compareVersions 0.7 0.7.0)"
assertEquals "compare four parts" "-1" "$(compareVersions 0.6.3 0.6.3.1)"
assertEquals "compare ignores suffix" "0" "$(compareVersions 0.7.5-beta1 0.7.5)"

# --- isNewerVersion: 0 update available, 1 current is latest, 2 current is newer

assertRc "update available" 0 isNewerVersion 0.7.4 0.7.5
assertRc "current is latest" 1 isNewerVersion 0.7.5 0.7.5
assertRc "current is newer" 2 isNewerVersion 0.7.6 0.7.5
assertRc "unknown current version" 1 isNewerVersion "" 0.7.5
assertRc "unknown available version" 1 isNewerVersion 0.7.5 ""
assertRc "update of older version with suffix" 0 isNewerVersion 0.7.4-beta 0.7.5
assertRc "beta is replaced by release" 0 isNewerVersion 0.7.5-beta 0.7.5
assertRc "beta with number is replaced by release" 0 isNewerVersion 0.7.5-beta1 0.7.5
assertRc "development version is replaced by release" 0 isNewerVersion 0.7.5-dev 0.7.5
assertRc "hotfix is kept" 2 isNewerVersion 0.7.5-hotfix 0.7.5
assertRc "other suffix is latest" 1 isNewerVersion 0.7.5-m1 0.7.5
assertRc "newer beta is kept" 2 isNewerVersion 0.7.6-beta 0.7.5

# --- versions of the Debian package

assertRc "beta" 0 isBetaVersion 0.7.5~beta1
assertRc "release isn't a beta" 1 isBetaVersion 0.7.5
assertRc "hotfix isn't a beta" 1 isBetaVersion 0.7.5-m1
assertRc "individual fix isn't a beta" 1 isBetaVersion 0.7.5-m2~u972.1

if command -v dpkg > /dev/null; then
	versions="0.7.4 0.7.5~beta1 0.7.5 0.7.5-m2~u972.1 0.7.5-m1 0.7.5-m2"
	assertEquals "highest version" "0.7.5-m2" "$(tr ' ' '\n' <<< "$versions" | highestVersion)"
	assertEquals "highest version lower than release" "0.7.5~beta1" "$(tr ' ' '\n' <<< "$versions" | highestVersion 0.7.5)"
	assertEquals "highest version lower than hotfix" "0.7.5-m2~u972.1" "$(tr ' ' '\n' <<< "$versions" | highestVersion 0.7.5-m2)"
	assertEquals "no lower version" "" "$(tr ' ' '\n' <<< "$versions" | highestVersion 0.7.4)"
	assertEquals "no version" "" "$(highestVersion < /dev/null)"

	# stubs of the package database and the repository
	INSTALLED=""; STABLE=""; BETA=""
	dpkg-query() { echo -n "$INSTALLED"; }
	apt-cache() {
		local v
		[[ "$1" == madison ]] || return 0
		for v in $STABLE; do echo " $PACKAGE_NAME | $v | https://example.invalid/raspiBackup stable/main all Packages"; done
		for v in $BETA; do echo " $PACKAGE_NAME | $v | https://example.invalid/raspiBackup beta/main all Packages"; done
	}

	checkPackageVersions() { # description installed stable previous beta
		parsePackageVersions
		assertEquals "$1: installed" "$2" "$PACKAGE_VERSION_INSTALLED"
		assertEquals "$1: stable" "$3" "$PACKAGE_VERSION_STABLE"
		assertEquals "$1: previous" "$4" "$PACKAGE_VERSION_PREVIOUS"
		assertEquals "$1: beta" "$5" "$PACKAGE_VERSION_BETA"
	}

	STABLE="0.7.4 0.7.5 0.7.5-m1"; BETA="0.7.6~beta1 0.7.6~beta2"
	INSTALLED="0.7.5-m1"
	checkPackageVersions "hotfix installed" "0.7.5-m1" "0.7.5-m1" "0.7.5" "0.7.6~beta2"
	INSTALLED="0.7.5"
	checkPackageVersions "release installed" "0.7.5" "0.7.5-m1" "0.7.4" "0.7.6~beta2"
	INSTALLED="0.7.4"
	checkPackageVersions "oldest release installed" "0.7.4" "0.7.5-m1" "" "0.7.6~beta2"
	INSTALLED="0.7.6~beta1"
	checkPackageVersions "beta installed, previous is the release" "0.7.6~beta1" "0.7.5-m1" "" "0.7.6~beta2"
	INSTALLED="0.7.5-m2~u972.1"
	checkPackageVersions "individual fix installed" "0.7.5-m2~u972.1" "0.7.5-m1" "0.7.5-m1" "0.7.6~beta2"
	STABLE=""; BETA=""; INSTALLED=""
	checkPackageVersions "nothing available" "" "" "" ""

	unset -f dpkg-query apt-cache
else
	echo "Warning: dpkg not found, versions of the Debian package not tested"
fi

# --- days of the timer: 0 daily, 1 Sunday ... 7 Saturday

USE_SYSTEMD=0
assertEquals "cron daily" "*" "$(daynum_to_config_string 0)"
assertEquals "cron Sunday" "0" "$(daynum_to_config_string 1)"
assertEquals "cron Saturday" "6" "$(daynum_to_config_string 7)"
for day in 0 1 2 3 4 5 6 7; do
	assertEquals "cron day $day back and forth" "$day" "$(daynum_from_config_string "$(daynum_to_config_string $day)")"
done
assertEquals "cron empty day is daily" "0" "$(daynum_from_config_string "")"

USE_SYSTEMD=1
assertEquals "systemd daily" "" "$(daynum_to_config_string 0)"
assertEquals "systemd Sunday" "Sun" "$(daynum_to_config_string 1)"
assertEquals "systemd Saturday" "Sat" "$(daynum_to_config_string 7)"
for day in 0 1 2 3 4 5 6 7; do
	assertEquals "systemd day $day back and forth" "$day" "$(daynum_from_config_string "$(daynum_to_config_string $day)")"
done
assertEquals "menu text of Monday" "Mon" "$(daynum_to_menu_string 2)"

# --- start and stop of services

getStartStopCommands "nginx" stop start
assertEquals "stop one service" "systemctl stop 'nginx'" "$stop"
assertEquals "start one service" "systemctl start 'nginx'" "$start"
getStartStopCommands "nginx smbd docker" stop start
assertEquals "stop services in sequence" "systemctl stop 'nginx' && systemctl stop 'smbd' && systemctl stop 'docker'" "$stop"
assertEquals "start services in reverse sequence" "systemctl start 'docker' && systemctl start 'smbd' && systemctl start 'nginx'" "$start"

# --- configuration written by the menus and read again

CONFIG_ABS_FILE="$TMP/raspiBackup.conf"
cp "$TEMPLATE_EN" "$CONFIG_ABS_FILE"

CONFIG_LANGUAGE="DE"
CONFIG_PARTITIONBASED_BACKUP="1"
CONFIG_PARTITIONS_TO_BACKUP="1 2 3"
CONFIG_BACKUPTYPE="tar"
CONFIG_ZIP_BACKUP="1"
CONFIG_TAR_COMPRESSION_TOOL="zstd"
CONFIG_KEEPBACKUPS="5"
CONFIG_SMART_RECYCLE="1"
CONFIG_SMART_RECYCLE_OPTIONS="7 4 12 2"
CONFIG_SMART_RECYCLE_DRYRUN="0"
CONFIG_MSG_LEVEL="1"
CONFIG_EMAIL="someone@example.invalid"
CONFIG_MAIL_PROGRAM="mail"
CONFIG_CLONE_DEVICE="/dev/sda"
CONFIG_CLONE_PARTUUID="1234-5678"
CONFIG_BACKUPPATH="/media/backup/raspi"
CONFIG_STOPSERVICES="nginx smbd"
config_update_execute

assertEquals "config language" '"DE"' "$(configValue DEFAULT_LANGUAGE)"
assertEquals "config partitions" '"1 2 3"' "$(configValue DEFAULT_PARTITIONS_TO_BACKUP)"
assertEquals "config backup path with slashes" '"/media/backup/raspi"' "$(configValue DEFAULT_BACKUPPATH)"
assertEquals "config clone device with slashes" '"/dev/sda"' "$(configValue DEFAULT_CLONE_DEVICE)"
assertEquals "config clone partuuid" '"1234-5678"' "$(configValue DEFAULT_CLONE_PARTUUID)"
assertEquals "config stop services" "\"systemctl stop 'nginx' && systemctl stop 'smbd'\"" "$(configValue DEFAULT_STOPSERVICES)"
assertEquals "config start services" "\"systemctl start 'smbd' && systemctl start 'nginx'\"" "$(configValue DEFAULT_STARTSERVICES)"
assertEquals "config version unchanged" "$(extractVersionFromFile "$TEMPLATE_EN" "$CONFIG_VERSION_VARNAME")" \
	"$(extractVersionFromFile "$CONFIG_ABS_FILE" "$CONFIG_VERSION_VARNAME")"
assertEquals "config template of German config" "raspiBackup_de.conf" "$(configTemplateName)"

declare -A written=()
for option in LANGUAGE PARTITIONBASED_BACKUP PARTITIONS_TO_BACKUP BACKUPTYPE ZIP_BACKUP TAR_COMPRESSION_TOOL KEEPBACKUPS \
	SMART_RECYCLE SMART_RECYCLE_OPTIONS SMART_RECYCLE_DRYRUN MSG_LEVEL EMAIL MAIL_PROGRAM BACKUPPATH STOPSERVICES; do
	v="CONFIG_$option"
	written[$option]="${!v}"
	printf -v "$v" "%s" "changed"
done
CONFIG_PARSED=0
parseConfig
for option in "${!written[@]}"; do
	v="CONFIG_$option"
	assertEquals "config $option read again" "${written[$option]}" "${!v}"
done
assertEquals "config start services read again" "smbd nginx" "$CONFIG_STARTSERVICES"
assertEquals "config parsed once" "1" "$CONFIG_PARSED"

CONFIG_STOPSERVICES=""
config_update_execute
assertEquals "config no services to stop" '":"' "$(configValue DEFAULT_STOPSERVICES)"
assertEquals "config no services to start" '":"' "$(configValue DEFAULT_STARTSERVICES)"
CONFIG_PARSED=0
parseConfig
assertEquals "config no services read again" "" "$CONFIG_STOPSERVICES"
assertRc "no start and stop defined" 1 isStartStopDefined

sed -i -E 's/^DEFAULT_LANGUAGE=.*/DEFAULT_LANGUAGE="EN"/' "$CONFIG_ABS_FILE"
assertEquals "config template of English config" "raspiBackup_en.conf" "$(configTemplateName)"
sed -i -E 's/^DEFAULT_LANGUAGE=.*/DEFAULT_LANGUAGE=""/' "$CONFIG_ABS_FILE"
LANG_SYSTEM="DE"
assertEquals "config template of system language" "raspiBackup_de.conf" "$(configTemplateName)"
LANG_SYSTEM="EN"

# --- merge of a new config template into the config

TEMPLATE="$TMP/template.conf"
writeConfigs() { # configVersion templateVersion
	cat > "$CONFIG_ABS_FILE" <<-EOF
	# config of the user
	VERSION_CONFIG="$1"
	DEFAULT_KEPT="mine"
	DEFAULT_PASSWORD="secret=value"
	DEFAULT_OBSOLETE="old"
	UUID=0815
	EOF
	chmod 600 "$CONFIG_ABS_FILE"
	cat > "$TEMPLATE" <<-EOF
	# template
	VERSION_CONFIG="$2"
	DEFAULT_KEPT="template"
	DEFAULT_PASSWORD=""
	# a new option
	DEFAULT_NEW="new"
	EOF
	rm -f "$CONFIG_ABS_FILE".v*
}

writeConfigs 0.1.10 0.1.11
assertRc "template newer" 0 isConfigTemplateNewer "$TEMPLATE"
MODE_UNATTENDED=1	# messages are written to the console, as with -m
messages="$(config_merge_execute "$TEMPLATE")"
MODE_UNATTENDED=0
assertEquals "merge sets template version" "0.1.11" "$(extractVersionFromFile "$CONFIG_ABS_FILE" "$CONFIG_VERSION_VARNAME")"
assertEquals "merge keeps value" '"mine"' "$(configValue DEFAULT_KEPT)"
assertEquals "merge keeps value with =" '"secret=value"' "$(configValue DEFAULT_PASSWORD)"
assertEquals "merge adds new option" '"new"' "$(configValue DEFAULT_NEW)"
assertEquals "merge marks new option" "1" "$(grep -c "NEW OPTION added in config version 0.1.11" "$CONFIG_ABS_FILE")"
assertEquals "merge comments out deleted option" "1" "$(grep -cx '# DEFAULT_OBSOLETE="old"' "$CONFIG_ABS_FILE")"
assertEquals "merge marks deleted option" "1" "$(grep -c "OPTION DELETED in config version 0.1.11" "$CONFIG_ABS_FILE")"
assertEquals "merge keeps comments of the template" "1" "$(grep -cx "# a new option" "$CONFIG_ABS_FILE")"
assertEquals "merge doesn't keep UUID" "0" "$(grep -c "UUID" "$CONFIG_ABS_FILE")"
assertEquals "merge saves the config" '"mine"' "$(grep "^DEFAULT_KEPT=" "$CONFIG_ABS_FILE.v0.1.10" | cut -d= -f2-)"
assertEquals "merge keeps permissions" "600" "$(stat -c %a "$CONFIG_ABS_FILE")"
assertEquals "merge keeps saved config private" "600" "$(stat -c %a "$CONFIG_ABS_FILE.v0.1.10")"
assertEquals "merge reports added option" "1" "$(grep -c "DEFAULT_NEW" <<< "$messages")"
assertEquals "merge reports deleted option" "1" "$(grep -c "DEFAULT_OBSOLETE" <<< "$messages")"
assertRc "template not newer after merge" 1 isConfigTemplateNewer "$TEMPLATE"

merged="$(cat "$CONFIG_ABS_FILE")"
config_merge_execute "$TEMPLATE" > /dev/null
assertEquals "second merge doesn't change the config" "$merged" "$(cat "$CONFIG_ABS_FILE")"

writeConfigs 0.1.11 0.1.11
config_merge_execute "$TEMPLATE" > /dev/null
assertEquals "same version isn't merged" '"old"' "$(configValue DEFAULT_OBSOLETE)"
assertEquals "same version isn't saved" "0" "$(find "$TMP" -name 'raspiBackup.conf.v*' | wc -l)"

writeConfigs 0.1.12 0.1.11
assertRc "older template isn't newer" 1 isConfigTemplateNewer "$TEMPLATE"
config_merge_execute "$TEMPLATE" > /dev/null
assertEquals "downgrade keeps the newer config" '"old"' "$(configValue DEFAULT_OBSOLETE)"

writeConfigs 0.1.9 0.1.10
assertRc "template with two digit version is newer" 0 isConfigTemplateNewer "$TEMPLATE"

assertRc "missing template isn't newer" 1 isConfigTemplateNewer "$TMP/missing.conf"
config_merge_execute "$TMP/missing.conf" > /dev/null
assertEquals "missing template doesn't change the config" '"old"' "$(configValue DEFAULT_OBSOLETE)"

writeConfigs 0.1.10 0.1.11
sed -i '/^VERSION_CONFIG=/d' "$CONFIG_ABS_FILE"
assertEquals "config without version has version 0.0.0.0" "0.0.0.0" "$(extractVersionFromFile "$CONFIG_ABS_FILE" "$CONFIG_VERSION_VARNAME")"
config_merge_execute "$TEMPLATE" > /dev/null
assertEquals "config without version is merged" "0.1.11" "$(extractVersionFromFile "$CONFIG_ABS_FILE" "$CONFIG_VERSION_VARNAME")"
assertEquals "config without version is saved" "1" "$(find "$TMP" -name 'raspiBackup.conf.v0.0.0.0' | wc -l)"

# --- cron timer

CRON_ABS_FILE="$TMP/cron.d/raspiBackup"
mkdir -p "$(dirname "$CRON_ABS_FILE")"
USE_SYSTEMD=0

cronLine() { tail -n 1 "$CRON_ABS_FILE"; }	# the empty 8th field leaves a space at the end, cron ignores it

echo "$CRON_CONTENTS" > "$CRON_ABS_FILE"
CRONTAB_ENABLED="undefined"
assertRc "cron template is disabled" 1 isCrontabEnabled
CONFIG_CRON_DAY=3; CONFIG_CRON_HOUR=4; CONFIG_CRON_MINUTE=30
cron_update_execute > /dev/null
assertEquals "cron disabled updated" "#30 4 * * 2 root /usr/local/bin/raspiBackup.sh " "$(cronLine)"
assertEquals "cron comments kept" "$(head -n -1 <<< "$CRON_CONTENTS")" "$(head -n -1 "$CRON_ABS_FILE")"

sed -i '$ s/^#//' "$CRON_ABS_FILE"
CRONTAB_ENABLED="undefined"
assertRc "cron enabled" 0 isCrontabEnabled
CONFIG_CRON_DAY=0; CONFIG_CRON_HOUR=23; CONFIG_CRON_MINUTE=5
cron_update_execute > /dev/null
assertEquals "cron enabled updated daily" "5 23 * * * root /usr/local/bin/raspiBackup.sh " "$(cronLine)"
assertEquals "cron updated once" "$(wc -l <<< "$CRON_CONTENTS")" "$(wc -l < "$CRON_ABS_FILE")"

rm "$CRON_ABS_FILE"
CRONTAB_ENABLED="undefined"
assertRc "cron not installed" 1 isCrontabConfigInstalled

# --- systemd timer

SYSTEMD_TIMER_ABS_FILE="$TMP/raspiBackup.timer"
USE_SYSTEMD=1
echo "$SYSTEMD_TIMER" > "$SYSTEMD_TIMER_ABS_FILE"

CONFIG_SYSTEMD_DAY=2; CONFIG_SYSTEMD_HOUR=04; CONFIG_SYSTEMD_MINUTE=30
systemd_update_execute > /dev/null
assertEquals "systemd weekly" "OnCalendar=Mon *-*-* 04:30:42" "$(grep "^OnCalendar" "$SYSTEMD_TIMER_ABS_FILE")"
CONFIG_SYSTEMD_DAY=0; CONFIG_SYSTEMD_HOUR=23; CONFIG_SYSTEMD_MINUTE=05
systemd_update_execute > /dev/null
assertEquals "systemd daily" "OnCalendar=*-*-* 23:05:42" "$(grep "^OnCalendar" "$SYSTEMD_TIMER_ABS_FILE")"
assertEquals "systemd timer otherwise unchanged" "$(grep -v "^OnCalendar" <<< "$SYSTEMD_TIMER")" "$(grep -v "^OnCalendar" "$SYSTEMD_TIMER_ABS_FILE")"

# --- masquerading of the log

assertRc "nothing to masquerade" 1 masquerade ""
assertEquals "masquerade short text" "@@@@3" "$(masquerade abc)"
assertEquals "masquerade medium text" "a@@@@f" "$(masquerade abcdef)"
assertEquals "masquerade long text" 'a@@@@j\(10\)' "$(masquerade abcdefghij)"

CONFIG_EMAIL="someone@example.invalid"
cat > "$LOG_FILE" <<-EOF
eMail: someone@example.invalid
file /home/peter/raspiBackup.sh
host $HOSTNAME
EOF
masqueradeSensitiveInfoInLog
assertEquals "log without eMail" "0" "$(grep -c "someone@example.invalid" "$LOG_FILE")"
assertEquals "log with masqueraded eMail" "1" "$(grep -cF "eMail: s@@@@d(23)" "$LOG_FILE")"
assertEquals "log without user" "1" "$(grep -cx "file /home/@USER@/raspiBackup.sh" "$LOG_FILE")"
assertEquals "log without hostname" "1" "$(grep -cx "host @HOSTNAME@" "$LOG_FILE")"

# --- actions of the unattended options

FILE_TO_INSTALL_ABS_FILE="$TMP/bin/raspiBackup.sh"
ACTIONS=()
for action in check4InternetAvailable repository_add_execute package_install_execute config_update_execute \
	systemd_install_execute cron_install_execute package_revert_execute package_upgrade_execute \
	config_merge_package_execute migrate_execute update_installer_execute extensions_uninstall_execute \
	systemd_uninstall_execute cron_uninstall_execute package_uninstall_execute config_uninstall_execute \
	misc_uninstall_execute uninstall_script_execute uninstall_execute repository_remove_execute; do
	eval "$action() { ACTIONS+=($action); }"
done
dpkg-query() { echo -n "0.7.5"; }

checkUnattended() { # description option packageMode legacy expectedRc expectedActions...
	local description="$1" option="$2" rc
	PACKAGE_MODE="$3"
	if (( $4 )); then
		mkdir -p "$(dirname "$FILE_TO_INSTALL_ABS_FILE")" && touch "$FILE_TO_INSTALL_ABS_FILE"
	else
		rm -f "$FILE_TO_INSTALL_ABS_FILE"
	fi
	isPackageInstalled() { (( PACKAGE_MODE )); }
	MODE_INSTALL=0; MODE_UPDATE=0; MODE_REVERT=0; MODE_MERGE=0; MODE_UNINSTALL=0; MODE_UNATTENDED=1
	case "$option" in
		-i) MODE_INSTALL=1 ;;
		-U) MODE_UPDATE=1 ;;
		-R) MODE_REVERT=1 ;;
		-m) MODE_MERGE=1 ;;
		-u) MODE_UNINSTALL=1 ;;
	esac
	shift 4
	local expectedRc="$1"
	shift
	# unattendedInstall exits on errors, the actions are written to a file by the subshell
	(
		ACTIONS=()
		unattendedInstall > /dev/null
		echo "${ACTIONS[*]}" > "$TMP/actions"
	)
	rc=$?
	[[ -f "$TMP/actions" ]] || echo "" > "$TMP/actions"
	assertEquals "$description: rc" "$expectedRc" "$rc"
	assertEquals "$description: actions" "$*" "$(cat "$TMP/actions")"
	rm -f "$TMP/actions"
}

USE_SYSTEMD=1
checkUnattended "-i installs package with systemd timer" -i 0 0 0 \
	check4InternetAvailable repository_add_execute package_install_execute config_update_execute systemd_install_execute
USE_SYSTEMD=0
checkUnattended "-i installs package with cron timer" -i 0 0 0 \
	check4InternetAvailable repository_add_execute package_install_execute config_update_execute cron_install_execute
USE_SYSTEMD=1
checkUnattended "-i refused if package is installed" -i 1 0 1
checkUnattended "-i migrates installation without apt" -i 0 1 0 check4InternetAvailable migrate_execute
checkUnattended "-U migrates installation without apt" -U 0 1 0 check4InternetAvailable migrate_execute
checkUnattended "-U upgrades package and merges config" -U 1 0 0 \
	check4InternetAvailable package_upgrade_execute config_merge_package_execute
checkUnattended "-U without raspiBackup updates the installer" -U 0 0 0 check4InternetAvailable update_installer_execute
checkUnattended "-R reverts package and merges config" -R 1 0 0 \
	check4InternetAvailable package_revert_execute config_merge_package_execute
checkUnattended "-R refused without package" -R 0 1 1
checkUnattended "-m merges config of package" -m 1 0 0 config_merge_package_execute
checkUnattended "-m does nothing without package" -m 0 1 0
checkUnattended "-u uninstalls everything" -u 1 0 0 \
	extensions_uninstall_execute systemd_uninstall_execute cron_uninstall_execute package_uninstall_execute \
	config_uninstall_execute misc_uninstall_execute uninstall_script_execute uninstall_execute repository_remove_execute

# --- result

if (( error )); then
	echo "raspiBackupConfig regressiontest failed ($checks checks)"
else
	echo "raspiBackupConfig regressiontest passed ($checks checks)"
fi
exit $error
