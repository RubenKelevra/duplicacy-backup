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

set -e

USER=user
HOSTNAME=hostname
SERVER=server
GLOBAL_EXCLUDE="~/makebackup.excludes"

KEEP_WITHIN='1:2' # all snapshots for 2 days; daily afterwards
KEEP_DAILY='7:62' # purge to weekly after two month
KEEP_WEEKLY='30:1424' # pruge to monthly after 4 years
KEEP_MONTHLY="356:2880" # purge to yearly after 4 years
KEEP_YEARLY="0:35244" # 99 years

# make sure this directory exist and you have write access
CACHEDIR='/var/cache/restic/'

# set capability for reading all files (this avoid that restic needs to be run as root)
sudo setcap cap_dac_read_search=+ep /usr/bin/restic

echo "Generating exclude lists..."

# fetch all files currently supplied by packages
rm -f /tmp/restic-backup.pkg_files
while IFS= read -r -d $'\n' filepath; do
	[ -f "$filepath" ] && echo "$filepath" >> /tmp/restic-backup.pkg_files
done < <(sudo pacman -Ql | cut -f 1 -d ' ' --complement)

# check all files supplied by packages for changes, and write the changed files to a list
sudo paccheck --md5sum --quiet --db-files --noupgrade --backup | awk '{ print $2 }' | sed "s/'//g" > /tmp/restic-backup.changed_files

# backup the changed files (remove them from the blacklist)
grep -v -x -f /tmp/restic-backup.changed_files /tmp/restic-backup.pkg_files | sed 's/\[/\\[/g' > /tmp/restic-backup.blacklist

# add the global exclude list to the black list
cat "$GLOBAL_EXCLUDE" >> /tmp/restic-backup.blacklist
echo "$CACHEDIR" >> /tmp/restic-backup.blacklist

echo "Generating package lists..."

# generate package-lists for native and foreign packages, to be able to restore the system from a mirror
sudo pacman -Qne | sudo tee /.explicit_packages.list >/dev/null
sudo pacman -Qme | sudo tee /.explicit_foreign_packages.list >/dev/null

echo "Backing up..."
restic -r sftp:$server:/home/$user/backups/$hostname --verbose --cache-dir="$cachdir" backup / --exclude-file=/tmp/restic-backup.blacklist

echo "Full system-backup done. Forgetting old snapshots..."
duplicacy prune -storage "$storage_id" -id "$hostname" -collect-only -keep "$KEEP_WITHIN" -keep "$KEEP_DAILY" -keep "$KEEP_WEEKLY" -keep "$KEEP_MONTHLY" -keep "$KEEP_YEARLY"

sudo setcap cap_dac_read_search=-ep /usr/bin/restic

rm -f /tmp/restic-backup.pkg_files 2>/dev/null || true
rm -f /tmp/restic-backup.changed_files 2>/dev/null || true
rm -f /tmp/restic-backup.blacklist 2>/dev/null || true

echo "Operation completed."
