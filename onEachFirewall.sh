#!/bin/env bash

printUsage()
{
	echo "Usage:"
	echo "$0 [-h] [-v] <file>"
	echo -e "\t-h\t\t\tPrint this usage information."
	echo -e "\t-v\tPrint the CMA name and firewall object's main address"
	echo -e "\t<file>\tA file containing the script you want to run on each firewall"
}
verboseOut=false

while getopts "vh" COMMAND_OPTION; do
	case $COMMAND_OPTION in
	v)
		verboseOut=true
		;;
	h)
		printUsage
		exit 0
		;;
	\?)
		echo >&2 "ERROR: Invalid option: -$OPTARG"
		echo ""
		printUsage
		exit 1
		;;
	:)
		echo >&2 "ERROR: Option -$OPTARG requires an argument."
		echo ""
		printUsage
		exit 1
		;;
	esac
done

shift $((OPTIND - 1))
scriptFile="$1"
if [ "" == "${scriptFile}" ];then
echo >&2 "ERROR: You must specify a file containing the script you want to send to the firewalls."
echo ""
printUsage
exit 1
fi

if [ ! -s "${scriptFile}" ];then
echo >&2 "ERROR: The script file must exist and must not be empty."
echo ""
printUsage
exit 2
fi

. /etc/profile.d/CP.sh
# Check to be sure the management API is running. If not, restart it.
api status >/dev/null 2>/dev/null
[ "$?" != "0" ] && api start >/dev/null

portNumber=$(api status | grep "APACHE Gaia Port" | awk '{print $NF}')

showAll() {
IFS=$(printf "\377")
sharedArguments=( --port ${portNumber} -f json ${cmaAddress:+-d} ${cmaAddress:+${cmaAddress}} -r true show "$1" details-level full limit 500 )
firstResult=$(mgmt_cli ${sharedArguments[@]})
if [ $? -ne 0 ];then return 1;fi
toReturn="$(echo "${firstResult}" | jq -c '.objects[]|.')
";objectCount=$(echo "${firstResult}" | jq -c '.total')
if [ "$objectCount" -lt 501 ];then echo "${toReturn}" | head -n -1;return 0;fi
for offsetVal in $(seq 500 500 "${objectCount}" 2>/dev/null | tr "\n" "$IFS");do
toReturn+="$(mgmt_cli ${sharedArguments[@]} offset "${offsetVal}" \
| jq -c '.objects[]|.')
";done;echo "${toReturn}" | head -n -1;}

cmaList=$(showAll domains \
| jq -c '{name:.name,server:.servers[]|{host:."multi-domain-server",ipAddress:."ipv4-address"}}' \
| grep $(hostname) \
| jq -c '[.name,.server.ipAddress]')
if [ ${#cmaList} -eq 0 ];then cmaList=("[\"$(hostname)\",\"\"]");fi

for cmaRow in $cmaList;do
cmaName=$(echo "${cmaRow}" | jq '.[0]' | sed 's#"##g')
cmaAddress=$(echo "${cmaRow}" | jq '.[1]' | sed 's#"##g')
mdsenv "${cmaAddress}" 2>/dev/null
firewallList=$(showAll gateways-and-servers \
| jq -c '{type:.type,address:."ipv4-address"}' \
| grep -v CpmiGatewayCluster \
| grep -v CpmiVsClusterNetobj \
| grep -v CpmiVsxClusterNetobj \
| grep -v "checkpoint-host" \
| jq -c '.address' \
| sed 's#"##g')
for firewall in $firewallList;do
if [ "true" = "${verboseOut}" ];then printf "%15s %15s: " "${cmaName}" "${firewall}";fi
cprid_util -server "${firewall}" putfile -local_file "${scriptFile}" -remote_file "${scriptFile}" -perms 500
if [ "$?" = "0" ];then
cprid_util -verbose -server "${firewall}" rexec -rcmd sh -c "${scriptFile};/bin/rm ${scriptFile} >/dev/null 2>/dev/null"
elif [ "true" = "${verboseOut}" ];then printf >&2 "Couldn't connect via CPRID\n"
else printf >&2 "${firewall}\tCouldn't connect via CPRID\n";fi
done;done
