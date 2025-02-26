#!/bin/env bash
########################################################################
## A simple wrapper to email the cluster member differences through the
## mail relay defined in MTA to the email addresses in mailRecipients.
########################################################################

MTA="mail.mycompany.example"
mailRecipients="FirewallAlerts@mycompany.example; SecondAddress@mycompany.example"

configDiffs=""
printf "From: diff@$(hostname)
To: ${mailRecipients}
Subject: $(hostname) Cluster Config Differences
The clusters managed by $(hostname) have been checked for configuration differences. The results:

$(/var/log/scripts/clusterDiff.sh)
========================================
" \
| /sbin/sendmail --host="${MTA}" --read-envelope-from -t
