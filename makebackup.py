
import os
import subprocess
import sys
import time

BACKUP_ID = subprocess.check_output(["hostname"]).decode("utf-8").strip()
BACKUP_STORAGE = open("./backupstorage").read().strip()
GLOBAL_EXCLUDE = "./makebackup_global.excludes"
LOCAL_EXCLUDE = "./makebackup_local.excludes"

KEEP_WITHIN = "1:7" # all snapshots for 7 days; daily afterwards
KEEP_DAILY = "7:62" # purge to weekly after two month
KEEP_WEEKLY = "30:720" # purge to monthly after 2 years
KEEP_MONTHLY = "365:1460" # purge to yearly after 4 years
KEEP_YEARLY = "0:3650" # remove backups after 10 years

# directory of the duplicacy cache to add it to the filter
CACHEDIR_USER = "-home/*/.duplicacy/cache"
CACHEDIR_ROOT = "-root/.duplicacy/cache"

# set capability for reading all files (this avoids that duplicacy/paccheck needs to be run as root)
subprocess.check_call(["sudo", "setcap", "cap_dac_read_search=+ep", "/usr/bin/duplicacy"])
subprocess.check_call(["sudo", "setcap", "cap_dac_read_search=+ep", "/usr/bin/paccheck"])

print("Generating exclude lists...")

if not os.path.isdir("./.git"):
    print("=> fetching latest global excludes filte from github...")
    # fetch latest global excludes list from github
    subprocess.check_call(["curl", "https://raw.githubusercontent.com/RubenKelevra/duplicacy-backup/master/makebackup_global.excludes", ">", GLOBAL_EXCLUDE, "-q", "2>/dev/null"])
    print(" done.")
else:
    subprocess.check_call(["git", "pull", "-q"])

print("=> cleanup...")
# fetch all files currently supplied by packages
try:
    os.remove("/tmp/duplicacy-backup.pkg_files")
except FileNotFoundError:
    pass
print(" done.")

start_time = time.time()
first = True
for filepath in subprocess.check_output(["pacman", "-Ql"]).decode("utf-8").split("\n"):
    if first:
        print("=> checking all files from pacman's packages for existence in the local system...")
        first = False
    if os.path.isfile(filepath):
        with open("/tmp/duplicacy-backup.pkg_files", "a") as f:
            f.write(filepath + "\n")
end_time = time.time()
print(" done after {} seconds".format(end_time-start_time))

# check all files supplied by packages for changes, and write the changed files to a list
start_time = time.time()
print("=> check files managed by pacman for changes...")
with open("/tmp/duplicacy-backup.changed_files", "w") as f:
    subprocess.check_call(["paccheck", "--md5sum", "--quiet", "--db-files", "--noupgrade", "--backup", "2>/dev/null"], stdout=f)
end_time = time.time()
print(" done after {} seconds".format(end_time-start_time))

# backup the changed files (remove them from the blacklist)
start_time = time.time()
print("=> generating pacman supplied files blacklist...")
with open("/tmp/duplicacy-backup.blacklist", "w") as f:
    subprocess.check_call(["grep", "-v", "-x", "-f", "/tmp/duplicacy-backup.changed_files", "/tmp/duplicacy-backup.pkg_files"], stdout=f)
    subprocess.check_call(["sed", "s/\[/\\[/g", "/tmp/duplicacy-backup.blacklist"], stdout=f)
    subprocess.check_call(["sed", "s/^\//-/g", "/tmp/duplicacy-backup.blacklist"], stdout=f)
end_time = time.time()
print(" done after {} seconds".format(end_time-start_time))

try:
    os.remove("/tmp/duplicacy-backup.pkg_files")
except FileNotFoundError:
    pass
try:
    os.remove("/tmp/duplicacy-backup.changed_files")
except FileNotFoundError:
    pass

# add the global exclude list to the black list
print("=> finishing blacklist generation...")
with open("/tmp/duplicacy-backup.blacklist", "a") as f:
    with open(GLOBAL_EXCLUDE, "r") as g:
        f.write(g.read())
    with open(LOCAL_EXCLUDE, "r") as g:
        f.write(g.read())
    f.write(CACHEDIR_USER + "\n")
    f.write(CACHEDIR_ROOT + "\n")
print(" done.")

# generate package-lists for native and foreign packages, to be able to restore the system from a mirror
start_time = time.time()
print("=> generating list of installed packages and their versions...")
with open("/.explicit_packages.list", "w") as f:
    subprocess.check_call(["pacman", "-Qne"], stdout=f)
with open("/.explicit_foreign_packages.list", "w") as f:
    subprocess.check_call(["pacman", "-Qme"], stdout=f)
end_time = time.time()
print(" done after {} seconds".format(end_time-start_time))

print("=> move blacklist to duplicacies 'filters' file location...")
if os.environ["HOME"]:
    with open(os.environ["HOME"] + "/.duplicacy/filters", "w") as f:
        with open("/tmp/duplicacy-backup.blacklist", "r") as g:
            f.write(g.read())
else:
    print("Error, HOME variable was empty")
    sys.exit(1)
print(" done.")

print("=> cleanup...")
try:
    os.remove("/tmp/duplicacy-backup.blacklist")
except FileNotFoundError:
    pass
print(" done.")

start_time = time.time()
print("=> running duplicacy:")
subprocess.check_call(["duplicacy", "backup", "-stats", "-storage", BACKUP_STORAGE, "-threads", "1"])
end_time = time.time()
print("\nduplicacy completed it's run after {} seconds".format(end_time-start_time))

start_time = time.time()
print("=> checking storage...")
subprocess.check_call(["duplicacy", "check", "-storage", BACKUP_STORAGE, "-id", BACKUP_ID, "-fossils", "-resurrect", "-threads", "2"])
end_time = time.time()
print(" done after {} seconds".format(end_time-start_time))

start_time = time.time()
print("=> pruning storage...")
subprocess.check_call(["duplicacy", "prune", "-storage", BACKUP_STORAGE, "-id", BACKUP_ID, "-keep", KEEP_YEARLY, "-keep", KEEP_MONTHLY, "-keep", KEEP_WEEKLY, "-keep", KEEP_DAILY, "-keep", KEEP_WITHIN, "-threads", "2"])
end_time = time.time()
print(" done after {} seconds".format(end_time-start_time))

subprocess.check_call(["sudo", "setcap", "cap_dac_read_search=-ep", "/usr/bin/duplicacy"])
subprocess.check_call(["sudo", "setcap", "cap_dac_read_search=-ep", "/usr/bin/paccheck"])

print("Operation completed.")
