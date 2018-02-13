#!/usr/bin/env bash
## pgsql backup script (incr)
set -e

runuser -l postgres -c 'pgbackrest --stanza=main backup'
duply pgsql bkp_purgeFull_purgeIncr --force
