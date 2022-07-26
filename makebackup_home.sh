#!/bin/bash
#
########
#
# Copyright © 2022 @RubenKelevra
#
# LICENSE contains the licensing informations
#
########

# simple script to backup arch linux systems, while avoiding to store any file
# supplied by the package manager (and not changed on disk) - for space efficient backups
#
# requires: 
# - duplicacy
# - pacman
# - curl

set -e

BACKUP_ID="home@$(HOSTNAME)"
BACKUP_STORAGE="$(cat ./backupstorage)"
GLOBAL_EXCLUDE="./makebackup_global_home.excludes"
LOCAL_EXCLUDE="./makebackup_local_home.excludes"

KEEP_WITHIN='1:7' # all snapshots for 7 days; daily afterwards
KEEP_DAILY='7:62' # purge to weekly after two month
KEEP_WEEKLY='30:720' # purge to monthly after 2 years
KEEP_MONTHLY="365:1460" # purge to yearly after 4 years
KEEP_YEARLY="0:3650" # remove backups after 10 years

# directory of the duplicacy cache to add it to the filter
CACHEDIR_USER='-*/.duplicacy/cache'

# set capability for reading all files (this avoids that duplicacy needs to be run as root)
sudo setcap cap_dac_read_search=+ep /usr/bin/duplicacy

echo "Generating exclude lists..."

if [ ! -d "./.git" ]; then
	echo -ne "=> fetching latest global excludes filte from github..."
	# fetch latest global excludes list from github
	curl https://raw.githubusercontent.com/RubenKelevra/duplicacy-backup/master/makebackup_global.excludes > "$GLOBAL_EXCLUDE" -q 2>/dev/null || echo $'\nFatal: Could not fetch global excludes'
	echo " done."
else
	git pull -q
fi

# add the global exclude list to the black list
echo -ne "=> finishing blacklist generation..."
{ cat "$GLOBAL_EXCLUDE"; cat "$LOCAL_EXCLUDE"; echo "$CACHEDIR_USER"; } > /tmp/duplicacy-backup_home.blacklist
echo " done."

# generate package-lists for native and foreign packages, to be able to restore the system from a mirror
start_time="$(date +%s)"
echo -ne "=> generating list of installed packages and their versions..."
pacman -Qne > "$HOME/.explicit_packages.list"
pacman -Qme > "$HOME/.explicit_foreign_packages.list" 
end_time="$(date +%s)"
echo " done after $((end_time-start_time)) seconds"
unset start_time end_time

echo -ne "=> move blacklist to duplicacy's 'filters' file location..."
if [ -n "$HOME" ]; then
	cat /tmp/duplicacy-backup.blacklist > "$HOME/.duplicacy/filters"
else
	echo "Error, HOME variable was empty"
	exit 1
fi
echo " done."

echo -ne "=> cleanup..."
rm -f /tmp/duplicacy-backup_home.blacklist  2>/dev/null || true
echo " done."

start_time="$(date +%s)"
echo "=> running duplicacy:
"
duplicacy backup -stats -storage "$BACKUP_STORAGE" -threads 1
end_time="$(date +%s)"
echo "
duplicacy completed it's run after $((end_time-start_time)) seconds"
unset start_time end_time

start_time="$(date +%s)"
echo -ne "=> checking storage..."
duplicacy check -storage "$BACKUP_STORAGE" -id "$BACKUP_ID" -fossils -resurrect -threads 2
end_time="$(date +%s)"
echo " done after $((end_time-start_time)) seconds"
unset start_time end_time

start_time="$(date +%s)"
echo -ne "=> pruning storage..."
duplicacy prune -storage "$BACKUP_STORAGE" -id "$BACKUP_ID" -keep "$KEEP_YEARLY" -keep "$KEEP_MONTHLY" -keep "$KEEP_WEEKLY" -keep "$KEEP_DAILY" -keep "$KEEP_WITHIN" -threads 2
end_time="$(date +%s)"
echo " done after $((end_time-start_time)) seconds"
unset start_time end_time

sudo setcap cap_dac_read_search=-ep /usr/bin/duplicacy

echo "Operation completed."
