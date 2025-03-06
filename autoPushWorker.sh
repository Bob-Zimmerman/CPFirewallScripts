#!/bin/env bash
########################################################################
## This script pushes a set of policies to a set of firewalls, one at a
## time. It is typically called by a separate script for the window,
## which passes in variables like which mail relay to use, and the list
## of which policy to push to which firewall.
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
## For an MDS, you must specify the domain's name using the '-d <CMA>'
## switch. For a SmartCenter, you can leave it out.
## 
## The policies and firewalls must be added to the firewallPolicyPairs
## variable in the form "Policy@Firewall". Each pair should be separated
## by a space.
########################################################################
documentationUrl="https://github.com/Bob-Zimmerman/CPFirewallScripts"

printUsage()
{
	echo "Usage:"
	echo "$0 -m <MTA> -M <emails> -w <name> [-d <CMA>] <policy@firewall> ... <policy@firewall>"
	echo -e "\t-m <MTA>\t\tSMTP relay to use to send mail"
	echo -e "\t-M <emails>\t\tList of email recipients"
	echo -e "\t-w <name>\t\tWindow name to be used in the email messages"
	echo -e "\t-d <CMA>\t\tName of the CMA to push from"
	echo -e "\t<policy@firewall>\tA policy to push and the firewall to push it to"
	echo -e "\t-h\t\t\tPrint this usage information."
}

MTA=""
mailRecipients=""
windowName=""
mdsDomain=""
pushOutput=""

while getopts "m:M:w:d:h" COMMAND_OPTION; do
	case $COMMAND_OPTION in
	m)
		MTA="${OPTARG}"
		;;
	M)
		mailRecipients="${OPTARG}"
		;;
	w)
		windowName="${OPTARG}"
		;;
	d)
		mdsDomain="${OPTARG}"
		;;
	h)
		printUsage
		exit 0
		;;
	\?)
		echo "ERROR: Invalid option: -$OPTARG" >&2
		echo ""
		printUsage
		exit 1
		;;
	:)
		echo "ERROR: Option -$OPTARG requires an argument." >&2
		echo ""
		printUsage
		exit 1
		;;
	esac
done

shift $((OPTIND - 1))
firewallPolicyPairs=($@)

############################################################
# Check for the mandatory arguments.
if [ "${MTA}" == "" ];then
	echo "ERROR: -m <MTA> is mandatory." >&2
	echo ""
	printUsage
	exit 1
elif [ "${mailRecipients}" == "" ];then
	echo "ERROR: -M <emails> is mandatory." >&2
	echo ""
	printUsage
	exit 1
elif [ "${windowName}" == "" ];then
	echo "ERROR: -w <name> is mandatory." >&2
	echo ""
	printUsage
	exit 1
elif [ "${#firewallPolicyPairs}" == "0" ];then
	echo "ERROR: You must provide at least one <policy@firewall> item to push." >&2
	echo ""
	printUsage
	exit 1
fi

. /etc/profile.d/CP.sh

# Check to be sure the management API is running. If not, restart it.
api status >/dev/null 2>/dev/null
[ "$?" != "0" ] && api start >/dev/null

portNumber=$(api status | grep "APACHE Gaia Port" | awk '{print $NF}')

pushPolicy() {
pushJson=$( mgmt_cli --port "${portNumber}" -r true -f json -d "${mdsDomain}" install-policy policy-package "$1" targets "$2" threat-prevention false 2>/dev/null )
pushStatus=$( jq -c '.tasks[0]|.status' <<<"$pushJson" | sed 's#"##g' )
pushWarnings=$( jq -c '[[.tasks[]."task-details"[].stagesInfo[].messages[]]|group_by(.type)[]|[.[0].type,length]]' <<<"$pushJson" | sed -E 's/^\[\]$//' )
pushErrors=$( jq '.tasks[]."task-details"[]?.stagesInfo[]?|select(.type == "err").messages[]?.message' <<<"$pushJson" )
echo "$pushStatus: ${1} -> ${2}${pushWarnings:+, $pushWarnings}"
if [ "" != "${pushErrors}" ];then
echo "${pushErrors}\n"
fi
}

############################################################
## Test for management-wide suspension and notify if present.
if [ -e /suspendPushes ]; then
printf "From: root@$(hostname)
To: ${mailRecipients}
Subject: Automatic pushes suspended on $(hostname)
The file /suspendPushes exists on the management server. All automated pushes from this management server are suspended.

To resume automated policy pushes, remove /suspendPushes from the filesystem on $(hostname).

This email was sent by a script on $(hostname). Documentation of the script may be found here:

${documentationUrl}" \
| /sbin/sendmail --host="${MTA}" --read-envelope-from -t
exit
fi

############################################################
## Send a notice the push is starting.
printf "From: root@$(hostname)
To: ${mailRecipients}
Subject: Pushing \"${windowName}\"
Beginning policy pushes for the window \"${windowName}\". Another email will be sent when the pushes are complete.

This email was sent by a script on $(hostname). Documentation of the script may be found here:

${documentationUrl}" \
| /sbin/sendmail --host="${MTA}" --read-envelope-from -t

############################################################
## Push the policies.
for fwPolicyPair in "${firewallPolicyPairs[@]}"; do
policyName=$(cut -d'@' -f1 <<< $fwPolicyPair)
firewallName=$(cut -d'@' -f2 <<< $fwPolicyPair)
if [ -e "/suspend_${firewallName}" ]; then
pushOutput+="SUSPENDED: $policyName -> $firewallName"
else
pushOutput+="$(pushPolicy "$policyName" "$firewallName")"
fi
pushOutput+="\n"
done

############################################################
## Report push status to the admins.
printf "From: root@$(hostname)
To: ${mailRecipients}
Subject: Pushing \"${windowName}\"
Policy pushes for the window \"${windowName}\" are complete. The results:

${pushOutput}" \
| /sbin/sendmail --host="${MTA}" --read-envelope-from -t
