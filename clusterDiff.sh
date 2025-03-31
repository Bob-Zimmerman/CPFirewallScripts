#!/bin/env bash
########################################################################
## Runs a script you provide on each member of every cluster reporting
## to the management where it is run, then uses diff to find differences
## in the output. You can specify your own script after
## 
### cat << 'EOF' > "${scriptFile}"
## 
## and before the line which has 'EOF' by itself. The script I have
## provided there dumps the clish config and finds differences. It works
## on normal clusters and VSX clusters. NOTE: This does not support
## ElasticXL and does not work on clusters with more than two members.
## 
## If you write your own script, it should write its output to
## /tmp/clusterDiff.output on the firewalls.
########################################################################

scriptFile=$(mktemp)
cat << 'EOF' > "${scriptFile}"
echo "" >/tmp/clusterDiff.output
vsids=$(ip netns list 2>/dev/null | cut -d" " -f3 | cut -d")" -f1 | sort -n;ls /proc/vrf/ 2>/dev/null | sort -n)
for vsid in $vsids;do
echo "set virtual-system $vsid" >/tmp/script.clish
echo "show configuration" >>/tmp/script.clish

clish -if /tmp/script.clish \
| sed -E "s/^Processing .+?\r//g" \
| egrep -v "^NMINST0079" \
| egrep -v "^Done\. *$" \
>/tmp/clishConfig.txt

grep "set interface" /tmp/clishConfig.txt \
| grep ipv4-address \
| sed -E "s/set interface ([^ ]+) ipv4-address ([^ ]+) mask.*$/s@ \2( .*|$)@ \#\1 IPv4\#\\\1@g/" \
>/tmp/sedScript.txt

grep "set interface" /tmp/clishConfig.txt \
| grep ipv6-address \
| sed -E "s/set interface ([^ ]+) ipv6-address ([^ ]+) mask.*$/s@ \2( .*|$)@ \#\1 IPv6\#\\\1@g/" \
>>/tmp/sedScript.txt

grep "type numbered local" /tmp/clishConfig.txt \
| sed -E "s/add vpn tunnel ([^ ]+) type numbered local ([^ ]+) .*$/s@ \2( .*|$)@ \#VTI \1 IPv4\#\\\1@g/" \
>>/tmp/sedScript.txt

sed -Ef /tmp/sedScript.txt /tmp/clishConfig.txt \
| grep -v "set hostname " \
| grep -v "password-hash " \
| grep -v " Configuration of " \
| grep -v " Exported by admin on " \
| grep -v "Config lock is owned by " \
| grep -v "set snmp location " \
| grep -v "set mail-notification username " \
| egrep -v "set interface [^ ]+ comments " \
| grep -v "add ssh hba ipv4-address" \
| sort \
>>/tmp/clusterDiff.output
echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-" \
>>/tmp/clusterDiff.output
done
EOF

. /etc/profile.d/CP.sh

# Check to be sure the management API is running. If not, restart it.
api status >/dev/null 2>/dev/null
[ "${?}" != "0" ] && api start >/dev/null

portNumber=$(api status | grep "APACHE Gaia Port" | awk '{print $NF}')
showAll() {
IFS=$(printf "\377")
sharedArguments=( --port ${portNumber} -f json ${cmaAddress:+-d} ${cmaAddress:+${cmaAddress}} -r true show "${1}" details-level full limit 500 )
firstResult=$(mgmt_cli ${sharedArguments[@]})
if [ "${?}" != "0" ];then return 1;fi
toReturn="$(<<<"${firstResult}" jq -c '.objects[]|.')
";objectCount=$(<<<"${firstResult}" jq -c '.total')
if [ "${objectCount}" -lt 501 ];then <<<"${toReturn}" head -n -1;return 0;fi
for offsetVal in $(seq 500 500 "${objectCount}" 2>/dev/null | tr "\n" "${IFS}");do
toReturn+="$(mgmt_cli ${sharedArguments[@]} offset "${offsetVal}" \
| jq -c '.objects[]|.')
";done;<<<"${toReturn}" head -n -1;}
cmaList=$(showAll domains \
| jq -c '{name:.name,server:.servers[]|{host:."multi-domain-server",ipAddress:."ipv4-address"}}' \
| grep $(hostname) \
| jq -c '[.name,.server.ipAddress]')
if [ "${#cmaList}" == "0" ];then cmaList=("[\"$(hostname)\",\"\"]");fi

for cmaRow in $cmaList; do
	cmaName=$(<<<"${cmaRow}" jq '.[0]' | sed 's#"##g')
	cmaAddress=$(<<<"${cmaRow}" jq '.[1]' | sed 's#"##g')
	mdsenv "${cmaAddress}" 2>/dev/null
	
	nonVsxList=$(showAll gateways-and-servers \
	| grep CpmiGatewayCluster \
	| jq -c '.uid' \
	| xargs -L 1 -r mgmt_cli --port "${portNumber}" -f json -d "${cmaAddress}" -r true show object details-level full uid \
	| jq -c '.object|{clusterName:.name,member:."cluster-members"[]} | {clusterName:.clusterName,memberName:.member.name,address:.member."ip-address"}')
	
	vsxClusterListUuids=$(showAll gateways-and-servers \
	| grep CpmiVsxClusterNetobj \
	| jq -c '.uid' \
	| xargs -L 1 -r mgmt_cli --port "${portNumber}" -f json -d "${cmaAddress}" -r true show generic-object uid \
	| jq -c '{clusterName:.name,member:."clusterMembers"[]}')
	echo "" >/tmp/sedScript
	for line in $(<<<"${vsxClusterListUuids}" tr ' ' '\n'); do
		memberUuid=$(<<<"${line}" jq .member)
		member=$(<<<"${memberUuid}" xargs mgmt_cli --port "${portNumber}" -f json -d "${cmaAddress}" -r true show object details-level full uid | jq -c '.object|{name:.name,address:."ipv4-address"}')
		echo "s#${memberUuid}#${member}#" >>/tmp/sedScript
		done
	vsxList=$(<<<"${vsxClusterListUuids}" sed -f /tmp/sedScript | jq -c '{clusterName:.clusterName,memberName:.member.name,address:.member.address}')
	
	firewallList=$(echo "${nonVsxList[@]}";echo "${vsxList[@]}")
	
	clusterList=($(<<<"${firewallList}" jq -c ".clusterName" | sort | uniq | sed 's#"##g'))
	for clusterName in "${clusterList[@]}"; do
		for firewallLine in $(<<<"${firewallList}" grep "${clusterName}"); do
			memberName="$(<<<"${firewallLine}" jq '.memberName' | sed 's#"##g')"
			firewall="$(<<<"${firewallLine}" jq '.address' | sed 's#"##g')"
			/bin/rm "/tmp/${clusterName}-${memberName}.output" 2>/dev/null
			cprid_util -server "${firewall}" putfile -local_file "${scriptFile}" -remote_file "${scriptFile}" -perms 500
			if [ "${?}" == "0" ]; then
				cprid_util -server "${firewall}" rexec -rcmd sh -c "${scriptFile};/bin/rm ${scriptFile} >/dev/null 2>/dev/null"
				cprid_util -server "${firewall}" getfile -remote_file /tmp/clusterDiff.output -local_file "/tmp/${clusterName}-${memberName}.output"
			else echo >&2 "[Couldn't connect to ${memberName} via CPRID]";fi
			done
		echo "========================================"
		echo -n "${clusterName}: "
		diffOut=$(diff "/tmp/${clusterName}-"* 2>/dev/null)
		diffExit="${?}"
		if [ "${diffExit}" = 0 ]; then
			echo "NO DIFFERENCES"
		elif [ "${diffExit}" = "1" ]; then
			echo ""
			echo "${diffOut}"
		elif [ "${diffExit}" = "2" ]; then
			echo "Files not found - probably CPRID failure"
		else
			echo "ERROR - diff exit code ${diffExit}"
		fi
		done
	done
echo "========================================"
/bin/rm "${scriptFile}"
