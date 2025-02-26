#!/bin/env bash
########################################################################
## This script pushes a set of policies to a set of firewalls, one at a
## time. It can be run manually, but is commonly run using cron. 
## 
## Pushes using this script can be suspended. To suspend all pushes, run:
## 
### touch /suspendPushes
## 
## To suspend just one firewall, run this instead:
## 
### touch /suspend_<firewall name>
## 
## Replace "<firewall name>" with the name of the firewall. It is case-
## sensitive. For example, this would suspend scripted pushes to
## MyFirewall:
## 
### touch /suspend_MyFirewall
## 
## To resume scripted pushes, delete the suspend file.
## 
## For an MDS, you must specify the CMA's name in the "mdsDomain"
## variable. For a SmartCenter, the variable should be an empty string.
## 
## The policies and firewalls must be added to the firewallPolicyPairs
## variable in the form "Policy@Firewall". Each pair should be in quotes
## and on its own line.
########################################################################

windowName="Dev/QA"
mailRecipients="FirewallAlerts@mycompany.example; ApplicationDevelopers@mycompany.example"
mdsDomain="Development"
firewallPolicyPairs=(
"Lab-Policy@StandingLabFw"
"Dev-Web-Policy@DevWebFw"
"QA-Web-Policy@QaWebFw"
"Dev-App-Policy@DevAppFw"
"QA-App-Policy@QaAppFw"
)

MTA="mail.mycompany.example"



if [[ ! "$1" = "" ]]; then
echo "ERROR: This script does not accept any arguments."
exit 1
fi

/var/log/scripts/autoPushWorker.sh -m "${MTA}" -M "${mailRecipients}" -w "${windowName}" -d "${mdsDomain}" "${firewallPolicyPairs[@]}"
