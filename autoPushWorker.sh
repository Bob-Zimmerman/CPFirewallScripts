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
## The policies, firewalls, and CMAs (if applicable) must be passed to
## the script in the form "Policy@Firewall[@CMA]". CMA is optional. If
## you are using a normal security management, leave it off. Each item
## should be separated by a space.
########################################################################
documentationUrl="https://github.com/Bob-Zimmerman/CPFirewallScripts"

printUsage()
{
	echo "Usage:"
	echo "${0} -m <MTA> -M <emails> -w <name> <policy@firewall[@mgmt]> [... <policy@firewall[@mgmt]>]"
	echo -e "\t-m <MTA>\t\tSMTP relay to use to send mail"
	echo -e "\t-M <emails>\t\tList of email recipients"
	echo -e "\t-w <name>\t\tWindow name to be used in the email messages"
	echo -e "\t<policy@fw[@mgmt]>\tA policy to push and the firewall to push it to."
	echo -e "\t\t\t\tThis may optionally include a CMA name in a"
	echo -e "\t\t\t\tmulti-domain environment."
	echo -e "\t-h\t\t\tPrint this usage information."
}

MTA=""
mailRecipients=""
windowName=""
mdsDomain=""
pushOutput=""
runningOnMds=false
recordSeparator=$(awk 'BEGIN {print "\036"}')

while getopts "m:M:w:h" COMMAND_OPTION; do
	case "${COMMAND_OPTION}" in
	m)
		MTA="${OPTARG}"
		;;
	M)
		mailRecipients="${OPTARG}"
		;;
	w)
		windowName="${OPTARG}"
		;;
	h)
		printUsage
		exit 0
		;;
	\?)
		echo >&2 "ERROR: Invalid option: -${OPTARG}"
		echo ""
		printUsage
		exit 1
		;;
	:)
		echo >&2 "ERROR: Option -${OPTARG} requires an argument."
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
	echo >&2 "ERROR: -m <MTA> is mandatory."
	echo ""
	printUsage
	exit 1
elif [ "${mailRecipients}" == "" ];then
	echo >&2 "ERROR: -M <emails> is mandatory."
	echo ""
	printUsage
	exit 1
elif [ "${windowName}" == "" ];then
	echo >&2 "ERROR: -w <name> is mandatory."
	echo ""
	printUsage
	exit 1
elif [ "${#firewallPolicyPairs}" == "0" ];then
	echo >&2 "ERROR: You must provide at least one <policy@firewall> item to push."
	echo ""
	printUsage
	exit 1
fi

for offset in $(seq 0 $(("${#firewallPolicyPairs[@]}" - 1)));do
if [ "" != "$(<<<"${firewallPolicyPairs[${offset}]}" cut -d'@' -f3)" ];then
runningOnMds=true
fi
done

. /etc/profile.d/CP.sh

# Check to be sure the management API is running. If not, restart it.
api status >/dev/null 2>/dev/null
[ "${?}" != "0" ] && api start >/dev/null

portNumber=$(api status | grep "APACHE Gaia Port" | awk '{print $NF}')

pushPolicy() {
policyName="$(<<<"${1}" cut -d'@' -f1 )"
firewallName="$(<<<"${1}" cut -d'@' -f2)"
mdsDomain="$(<<<"${1}" cut -d'@' -f3)"
if [ -e "/suspend_${firewallName}" ]; then
pushJson="{}"
pushStatus="SUSPENDED"
else
pushJson=$(mgmt_cli --port "${portNumber}" -r true -f json -d "${mdsDomain}" install-policy policy-package "${policyName}" targets "${firewallName}" threat-prevention false 2>/dev/null)
echo "${pushJson}" >/tmp/"push_${policyName}_${firewallName}.json"
pushStatus=$(<<<"${pushJson}" jq -c '.tasks[0]|.status' | sed 's#"##g')
fi
pushWarnings=$(<<<"${pushJson}" jq -c '[[.tasks[]."task-details"[].stagesInfo[].messages[]]|group_by(.type)[]|[.[0].type,length]]' | sed -E 's/^\[\]$//')
pushErrors=$(<<<"${pushJson}" jq '.tasks[]."task-details"[]?.stagesInfo[]?.messages[]?|select(.type == "err").message' | tr '\n' "${recordSeparator}" | sed "s@${recordSeparator}@<br />@g" | sed 's@<br />$@@')
echo -n "<tr>"
$runningOnMds && echo -n "<td>${mdsDomain}</td>"
echo -n "<td>${policyName}</td>"
echo -n "<td>${firewallName}</td>"
echo -n "<td>${pushStatus}</td>"
echo -n "<td>"
echo -n "${pushWarnings:+${pushWarnings}}"
echo -n "${pushErrors:+<br /><br />${pushErrors}}"
echo "</td></tr>"
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
for fwPolicyLine in "${firewallPolicyPairs[@]}"; do
pushOutput+="$(pushPolicy "${fwPolicyLine}")\n"
done
pushOutput=$(echo -e "${pushOutput}" | egrep -v "^$")
pushFailures=$(<<<"${pushOutput}" sed -E 's#.+<td>(.*?)</td><td>.*?</td></tr>$#\1#' | egrep -cv "^(succeeded|SUSPENDED)$")

############################################################
## Report push status to the admins.
printf "From: root@$(hostname)
To: ${mailRecipients}
Subject: Pushing \"${windowName}\"
Content-Type: text/html; charset=\"UTF-8\"
Content-Transfer-Encoding: quoted-printable
$([ "0" != "${pushFailures}" ] && printf "Importance: high\nX-Priority: 1\n\n")
<html><head><style>
table, th, td {
	border: 1px solid black;
	border-collapse: collapse;
	padding: 4px;
}
th {
	font-weight: bold;
}
</style></head><body>
<p>Policy pushes for the window \"${windowName}\" are complete. The results:</p>
<table>
<thead><tr>$($runningOnMds && echo -n "<th>Domain</th>")<th>Policy</th><th>Firewall</th><th>Status</th><th>Notes</th></tr></thead>
<tbody>
${pushOutput}
</tbody>
</table>
<p>For detailed push results, look on $(hostname) at the contents of the file /tmp/push_&lt;Policy&gt;_&lt;Firewall&gt;.json</p>
</body></html>
" \
| /sbin/sendmail --host="${MTA}" --read-envelope-from -t
