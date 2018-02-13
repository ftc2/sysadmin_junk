#!/usr/bin/env bash
## pgsql backup script (full)
set -e

# i think i confirmed that pgbackrest and duply will error if you force an incr backup if
# a full backup does not exist, so we can ignore that error.
runuser -l postgres -c 'pgbackrest --stanza-main --type=incr backup' && :
# but actually don't ignore error from this duply incr because we NEED the pgbackrest repo
# backed up offsite or else we'll lose info if pgbackrest is configured to keep only one
# full backup.
duply pgsql incr
runuser -l postgres -c 'pgbackrest --stanza=main --type=full backup'
duply pgsql full_purgeFull_purgeIncr --force
