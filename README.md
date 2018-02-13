# sysadmin_junk

my (probably low quality) collection of sysadmin stuff

uses duply to manage encrypted duplicity backups to google drive
also uses duply+duplicity to back up pgbackrest (postgresql) repo

quick tips: build latest versions by backporting for best results 
```
sudo nano /etc/apt/sources.list

# add sid (unstable) for backporting newer packages yourself. only add a deb-src line, not deb line.
deb-src http://deb.debian.org/debian/ sid main contrib non-free
```

```
sudo apt-get update
mkdir ~/backup-packages
cd ~/backup-packages

sudo apt-get install build-essential

sudo apt-get build-dep duplicity duply pgbackrest
sudo apt-get -b source duplicity duply pgbackrest
sudo dpkg -i duplicity_0.7.14-2_amd64.deb duply_2.0.3-1_all.deb pgbackrest_1.25-1_amd64.deb
```

gpg setup for duplicity:
```
# if you don't have one already, make a master key. set it to not expire.
# this is the key you'll keep forever and use to inspect encrypted backups remotely
# if you make this on a headless server, you probably need to install haveged first to get 
# enough entropy to gen keys
sudo apt-get install haveged
gpg --full-generate-key

# list keys
gpg --list-key

# export key and keep it somewhere safe
gpg --export -a key_id > public.key
gpg --export-secret-key -a key_id > private.key

# if needed, import the key on the server by pasting it into the prompt and then do ctrl+d
sudo -i gpg --import
```
make an api key for duplicity to use google drive as a backup target
https://console.developers.google.com/
https://stackoverflow.com/questions/31370102/how-do-i-backup-to-google-drive-using-duplicity

install pydrive for duplicity to use google drive:
```
sudo apt-get install python-pip
sudo pip install PyDrive
pip install --upgrade google-auth-oauthlib
```
put that api key in `gdrive` in your duply profiles.

to manage duply backups, i have `duply@.service`.
each duply profile has its own timer.

some notes on pgbackrest:
http://pgbackrest.org/user-guide.html#quickstart
```
# configure postgresql.conf to use WAL archiving so that a running psql cluster can be backed up
sudo nano /etc/postgresql/9.6/main/postgresql.conf

archive_command = 'pgbackrest --stanza=main archive-push %p'
archive_mode = on
max_wal_senders = 3
wal_level = replica

# restart cluster
sudo systemctl restart postgresql

# check that the changes stuck
sudo su - postgres
psql
SHOW archive_mode;
# it's on now, right?

# initialize pgbackrest stanza
sudo -u postgres pgbackrest --stanza=main --log-level-console=info stanza-create
# check that everything's set up right
sudo -u postgres pgbackrest --stanza=main --log-level-console=info check
```

also there's some notification stuff in there for good measure
`systemd_mon` is used for some alerts, but it doesn't work right for oneshot services.
for that, i have `systemd_slack@.service`
for each oneshot service i want to monitor, i add `OnFailure=systemd_slack@%n.service`.
