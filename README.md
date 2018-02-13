# sysadmin_junk

my (probably low quality) collection of sysadmin stuff 

## backporting packages
build latest versions by backporting for best results (important for these utils)
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

## duply+duplicity

use `duply` to manage encrypted `duplicity` backups to google drive

### duply setup

http://duply.net/wiki/index.php/Duply-documentation  
http://duplicity.nongnu.org/docs.html

```
# make sure this exists or else duply might try to make profiles in root homedir
sudo mkdir /etc/duply
# make one or more duply profiles
# i have a few because i have different sets of files with different backup rules
sudo duply PROFILE_NAME create
```
then edit `/etc/duply/profilename/conf` and `/etc/duply/profilename/exclude`

### gpg setup
```
# if you don't have one already, make a master key. set it to not expire.
# this is the key you'll keep 'forever' and use to inspect encrypted backups remotely
# if you make this on a headless server, you probably need to install haveged first to get 
# enough entropy to gen keys
# also, if you're making this on your server, use sudo so the keys are associated with root user
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
then put the keyid and password in the duply `conf` files:
```
GPG_KEY=''
GPG_PW=''
```

### duplicity: google drive backup target 
make an api key for duplicity to use google drive as a backup target  
https://console.developers.google.com/  
https://stackoverflow.com/questions/31370102/how-do-i-backup-to-google-drive-using-duplicity

install `pydrive` for duplicity to use google drive:
```
sudo apt-get install python-pip
sudo pip install PyDrive
pip install --upgrade google-auth-oauthlib
```
put that api key in `gdrive` in your duply profiles.

before you automate backups, first you have to do a manual backup to get pydrive authing properly.  
`sudo duply PROFILE_NAME backup`  
it will give you a link you have to visit while logged into your google account.  
then it will cache a refresh token for next time.

### duplicity: systemd integration

to manage duply backups, i have `duply@.service`.  
each duply profile has its own timer.  
start them up like this (e.g. for the `www` profile):
```
sudo systemctl start duply@www.timer
#also enable automatically at startup
sudo systemctl enable duply@www.timer
```

example: for my `etc` duply profile, i have this in the `conf` file:
```
MAX_AGE=24M
MAX_FULLS_WITH_INCRS=6

MAX_FULLBKP_AGE=1M
DUPL_PARAMS="$DUPL_PARAMS --full-if-older-than $MAX_FULLBKP_AGE " 
```
and it gets run daily by `duply@etc.timer`.  
`MAX_FULLBKP_AGE=1M`: this means that an incr backup is made daily, but we start fresh on a full backup monthly.  
`MAX_FULLS_WITH_INCRS=6`: incrementals are retained only for the last 6 full backups  
`MAX_AGE=24M`: two years of backups  
summary: two years of monthly backups, and 6 months of daily (incr) backups

## pgbackrest
`pgbackrest` is a robust postresql backup solution.  
it gives diff/incr backups as well as point-in-time recovery.

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

### pgbackrest: google drive
unfortunately, google drive isn't a supported backup target, so i'm using duply+duplicity to back up its local repo.

### pgbackrest: duply+duplicity & systemd integration
for pgbackrest, i have a different service `pgsql-backup@.service` and a couple of timers to manage full and incremental backups.  
note that these call bash scripts housed in the `pgsql` duply profile dir.  
these scripts do pgbackrest backups and then run duply to push to google drive.

i have duply and pgbackrest set up in a way that isn't *too* dumb:

`/etc/pgbackrest.conf` has `retention-full=1`.  
this means that only ONE full backup (and subsequent incrementals) is retained in the local pgbackrest repo.

`pgsql-backup@incr.timer` does daily incremental backups.
the incr script first does a pgbackrest incr and then a duply incr push to gdrive.  
`pgsql-backup@full.timer` does monthly full backups.
this will do an incr pgbackrest+duply and then a full pgbackrest+duply backup.
the reason for doing an incr first is to make sure that data between the last incr and now is not lost.  
i.e. a duply incr must be done to get the current pgbackrest repo backed up offsite before pgbackrest does a full backup and cleans out its repo.

the duply profile `/etc/duply/pgsql/conf` is set up to keep 6 full backup sets (full+incrs):
```
MAX_FULL_BACKUPS=6
MAX_FULLS_WITH_INCRS=6
```
each duply full+incr backup set will thus contain a pgbackrest repo containing a single pgbackrest full+incr set.
since a full backup is triggered monthly and duply is configured to keep 6 sets, that means i have 6 months of daily incrementals (and can actually do point-in-time recovery between those incrs).

a minor downside of having pgbackrest do only `retention-full=1` means that the local repo is not a rolling backup window.  
i.e. with full backups happening monthly, you have about a month of history in the repo right before a full backup and NO history in the repo right after.
you could do rolling backups with with `retention-full=2`, but if you use duply the same way (full backup every time a pgbackrest full backup happens), you're basically doubling your storage requirements.
to work around that, you'd have to somehow make duply do a full backup on every second pgbackrest full backup or something.

## monitoring and notification

### netdata
https://github.com/firehol/netdata  
i suggest [installing this using their script](https://github.com/firehol/netdata/wiki/Installation) instead of using a package manager.
it keeps itself up-to-date.

also look here: https://github.com/firehol/netdata/wiki/netdata-security  
i'm having netdata listen on a unix socket and then have nginx reverse proxy that on a virtual host.
nginx does the access control.

### systemd_mon
https://github.com/joonty/systemd_mon  
`systemd_mon` is used for some alerts, but it doesn't work right for oneshot services.

### systemd_slack@.service
for oneshot services (e.g. backups on timers), i have `systemd_slack@.service`  
to each service i want to monitor, i add `OnFailure=systemd_slack@%n.service`.  
this uses `slacktee`, so [read here](https://github.com/course-hero/slacktee) about configuring it, and don't forget to [set up a slack api webhook](https://my.slack.com/services/new/incoming-webhook/)
