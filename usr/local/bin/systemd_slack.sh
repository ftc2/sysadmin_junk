#!/usr/bin/env bash
## slack notifier for systemd service failure

SLACK_USERNAME='systemd-notifier'
SLACK_CHANNEL='#server-status'
UNIT="$1"
HOST=`hostname`
TITLE="$UNIT failed on $HOST"
MESSAGE=`systemctl status --full "$UNIT"`
echo "$TITLE: $MESSAGE" | /usr/local/bin/slacktee.sh --username "$SLACK_USERNAME" --channel "$SLACK_CHANNEL" --icon warning --attachment danger
