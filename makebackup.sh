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

set -e

HOSTNAME="$(hostname)"
BACKUP_STORAGE=store1
GLOBAL_EXCLUDE="$HOME/makebackup_global.excludes"
LOCAL_EXCLUDE="$HOME/makebackup_local.excludes"

KEEP_WITHIN='1:2' # all snapshots for 2 days; daily afterwards
KEEP_DAILY='7:62' # purge to weekly after two month
KEEP_WEEKLY='30:1424' # purge to monthly after 4 years
KEEP_MONTHLY="365:2880" # purge to yearly after 4 years
KEEP_YEARLY="0:35244" # 99 years

# directory of the duplicacy cache to add it to the filter
CACHEDIR_USER='-home/*/.duplicacy/cache'
CACHEDIR_ROOT='-root/.duplicacy/cache'

# set capability for reading all files (this avoid that duplicacy needs to be run as root)
sudo setcap cap_dac_read_search=+ep /usr/bin/duplicacy

echo "Generating exclude lists..."

# fetch all files currently supplied by packages
rm -f /tmp/duplicacy-backup.pkg_files
while IFS= read -r -d $'\n' filepath; do
	[ -f "$filepath" ] && echo "$filepath" >> /tmp/duplicacy-backup.pkg_files
done < <(sudo pacman -Ql | cut -f 1 -d ' ' --complement)

# check all files supplied by packages for changes, and write the changed files to a list
sudo paccheck --md5sum --quiet --db-files --noupgrade --backup | awk '{ print $2 }' | sed "s/'//g" > /tmp/duplicacy-backup.changed_files

# backup the changed files (remove them from the blacklist)
grep -v -x -f /tmp/duplicacy-backup.changed_files /tmp/duplicacy-backup.pkg_files | sed 's/\[/\\[/g' | sed 's/^\//-/g' > /tmp/duplicacy-backup.blacklist

rm -f /tmp/duplicacy-backup.pkg_files 2>/dev/null || true
rm -f /tmp/duplicacy-backup.changed_files 2>/dev/null || true

# add the global exclude list to the black list
cat "$GLOBAL_EXCLUDE" >> /tmp/duplicacy-backup.blacklist
cat "$LOCAL_EXCLUDE" >> /tmp/duplicacy-backup.blacklist
echo "$CACHEDIR_USER" >> /tmp/duplicacy-backup.blacklist
echo "$CACHEDIR_ROOT" >> /tmp/duplicacy-backup.blacklist

echo "Generating package lists..."

# generate package-lists for native and foreign packages, to be able to restore the system from a mirror
sudo pacman -Qne | sudo tee /.explicit_packages.list >/dev/null
sudo pacman -Qme | sudo tee /.explicit_foreign_packages.list >/dev/null

echo "Move blacklist to duplicacies 'filters' file location..."
[ ! -z "$HOME" ] && cat /tmp/duplicacy-backup.blacklist > "$HOME/.duplicacy/filters" || echo "Error, HOME variable was empty"; exit 1

rm -f /tmp/duplicacy-backup.blacklist 2>/dev/null || true

echo "Backing up..."
duplicacy backup -storage "$BACKUP_STORAGE" -threads 4 # FIXME: needs to be checked

echo "Full system-backup done. Forgetting old snapshots..."
duplicacy check -storage "$BACKUP_STORAGE" -id "$HOSTNAME" -fossils -resurrect -threads 4 # FIXME: needs to be check
duplicacy prune -storage "$BACKUP_STORAGE" -id "$HOSTNAME" -keep "$KEEP_WITHIN" -keep "$KEEP_DAILY" -keep "$KEEP_WEEKLY" -keep "$KEEP_MONTHLY" -keep "$KEEP_YEARLY" -threads 4 # FIXME: needs to be checked

sudo setcap cap_dac_read_search=-ep /usr/bin/duplicacy

echo "Operation completed."
