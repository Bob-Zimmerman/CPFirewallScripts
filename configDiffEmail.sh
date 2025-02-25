#!/bin/env bash
MTA=<name or IP>
mailRecipients=<addresses>

configDiffs=""
printf "From: diff@$(hostname)
To: ${mailRecipients}
Subject: $(hostname) Cluster Config Differences
The clusters managed by $(hostname) have been checked for configuration differences. The results:

$(/var/log/scripts/clusterDiff.sh)
========================================
" \
| /sbin/sendmail --host="${MTA}" --read-envelope-from -t
