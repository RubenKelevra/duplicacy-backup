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
# - paccheck (community/pacutils)
# - pacman
# - curl

set -e

HOSTNAME="$(hostname)"
BACKUP_STORAGE="$(cat ./backupstorage)"
GLOBAL_EXCLUDE="./makebackup_global.excludes"
LOCAL_EXCLUDE="./makebackup_local.excludes"

KEEP_WITHIN='1:7' # all snapshots for 7 days; daily afterwards
KEEP_DAILY='7:62' # purge to weekly after two month
KEEP_WEEKLY='30:720' # purge to monthly after 2 years
KEEP_MONTHLY="365:1460" # purge to yearly after 4 years
KEEP_YEARLY="0:3650" # remove backups after 10 years

# directory of the duplicacy cache to add it to the filter
CACHEDIR_USER='-home/*/.duplicacy/cache'
CACHEDIR_ROOT='-root/.duplicacy/cache'

# set capability for reading all files (this avoid that duplicacy/paccheck needs to be run as root)
sudo setcap cap_dac_read_search=+ep /usr/bin/duplicacy
sudo setcap cap_dac_read_search=+ep /usr/bin/paccheck

echo "Generating exclude lists..."

if [ ! -d "./.git" ]; then
	echo -ne "=> fetching latest global excludes filte from github..."
	# fetch latest global excludes list from github
	curl https://raw.githubusercontent.com/RubenKelevra/duplicacy-backup/master/makebackup_global.excludes > "$GLOBAL_EXCLUDE" -q 2>/dev/null || echo $'\nFatal: Could not fetch global excludes'
	echo " done."
else
	git pull -q
fi

echo -ne "=> cleanup..."
# fetch all files currently supplied by packages
rm -f /tmp/duplicacy-backup.pkg_files 2>/dev/null || true
echo " done."

start_time="$(date +%s)"
first=true
while IFS= read -r -d $'\n' filepath; do
	if $first; then
		echo -ne "=> checking all files from pacman's packages for existence in the local system..."
		first=false
	fi
	[ -f "$filepath" ] && echo "$filepath" >> /tmp/duplicacy-backup.pkg_files
done < <(pacman -Ql | cut -f 1 -d ' ' --complement)
end_time="$(date +%s)"
echo " done after $((end_time-start_time)) seconds"
unset start_time end_time

# check all files supplied by packages for changes, and write the changed files to a list
start_time="$(date +%s)"
echo -ne "=> check files managed by pacman for changes..."
paccheck --md5sum --quiet --db-files --noupgrade --backup | awk '{ print $2 }' | sed "s/'//g" > /tmp/duplicacy-backup.changed_files
end_time="$(date +%s)"
echo " done after $((end_time-start_time)) seconds"
unset start_time end_time


# backup the changed files (remove them from the blacklist)
start_time="$(date +%s)"
echo -ne "=> generating pacman supplied files blacklist..."
grep -v -x -f /tmp/duplicacy-backup.changed_files /tmp/duplicacy-backup.pkg_files | sed 's/\[/\\[/g' | sed 's/^\//-/g' > /tmp/duplicacy-backup.blacklist
end_time="$(date +%s)"
echo " done after $((end_time-start_time)) seconds"
unset start_time end_time

rm -f /tmp/duplicacy-backup.pkg_files 2>/dev/null || true
rm -f /tmp/duplicacy-backup.changed_files 2>/dev/null || true

# add the global exclude list to the black list
echo -ne "=> finishing blacklist generation..."
{ cat "$GLOBAL_EXCLUDE"; cat "$LOCAL_EXCLUDE"; echo "$CACHEDIR_USER"; echo "$CACHEDIR_ROOT"; } >> /tmp/duplicacy-backup.blacklist
echo " done."

# generate package-lists for native and foreign packages, to be able to restore the system from a mirror
start_time="$(date +%s)"
echo -ne "=> generating list of installed packages and their versions..."
pacman -Qne | sudo tee /.explicit_packages.list >/dev/null
pacman -Qme | sudo tee /.explicit_foreign_packages.list >/dev/null
end_time="$(date +%s)"
echo " done after $((end_time-start_time)) seconds"
unset start_time end_time

echo -ne "=> move blacklist to duplicacies 'filters' file location..."
if [ -n "$HOME" ]; then
	cat /tmp/duplicacy-backup.blacklist > "$HOME/.duplicacy/filters"
else
	echo "Error, HOME variable was empty"
	exit 1
fi
echo " done."

echo -ne "=> cleanup..."
rm -f /tmp/duplicacy-backup.blacklist 2>/dev/null || true
echo " done."

start_time="$(date +%s)"
echo "=> running duplicacy:
"
duplicacy backup -stats -storage "$BACKUP_STORAGE" -threads 4
end_time="$(date +%s)"
echo "
duplicacy completed it's run after $((end_time-start_time)) seconds"
unset start_time end_time

start_time="$(date +%s)"
echo -ne "=> checking storage..."
duplicacy check -storage "$BACKUP_STORAGE" -id "$HOSTNAME" -fossils -resurrect -threads 4
end_time="$(date +%s)"
echo " done after $((end_time-start_time)) seconds"
unset start_time end_time

start_time="$(date +%s)"
echo -ne "=> pruning storage..."
duplicacy prune -storage "$BACKUP_STORAGE" -id "$HOSTNAME" -keep "$KEEP_WITHIN" -keep "$KEEP_DAILY" -keep "$KEEP_WEEKLY" -keep "$KEEP_MONTHLY" -keep "$KEEP_YEARLY" -threads 4
end_time="$(date +%s)"
echo " done after $((end_time-start_time)) seconds"
unset start_time end_time

sudo setcap cap_dac_read_search=-ep /usr/bin/duplicacy
sudo setcap cap_dac_read_search=-ep /usr/bin/paccheck

echo "Operation completed."
