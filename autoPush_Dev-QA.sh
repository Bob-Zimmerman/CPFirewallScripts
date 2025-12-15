#!/usr/bin/env bash
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
## The policies, firewalls, and CMAs (if applicable) must be added to
## the firewallPolicyPairs variable in the form "Policy@Firewall[@CMA]".
## CMA is optional. If you are using a normal security management, leave
## it off. Each set should be in quotes and on its own line.
########################################################################

windowName="Dev/QA"
mailRecipients="FirewallAlerts@mycompany.example; ApplicationDevelopers@mycompany.example"
firewallPolicyPairs=(
"Lab-Policy@StandingLabFw@Development"
"Dev-Web-Policy@DevWebFw@Development"
"QA-Web-Policy@QaWebFw@Development"
"Dev-App-Policy@DevAppFw@Development"
"QA-App-Policy@QaAppFw@Development"
)

MTA="mail.mycompany.example"



if [[ "${#}" != "0" ]]; then
echo "ERROR: This script does not accept any arguments."
exit 1
fi

/var/log/scripts/autoPushWorker.sh -m "${MTA}" -M "${mailRecipients}" -w "${windowName}" "${firewallPolicyPairs[@]}"
