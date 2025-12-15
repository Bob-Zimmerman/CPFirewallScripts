#!/usr/bin/env bash
########################################################################
## Takes a list of IPv4 addresses and gives you the names of all host
## objects which represent them. I use this mostly when decommissioning
## systems to find which CMAs have objects for them.
########################################################################
printUsage()
{
	echo "Usage:"
	echo "${0} [-h] <IPv4 address> [IPv4 address] ..."
	echo -e "\t-h\tPrint this usage information."
}

while getopts "h" COMMAND_OPTION; do
	case "${COMMAND_OPTION}" in
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
	esac
done

addressList="${@}"

if [ "${#addressList}" == "0" ];then
	echo >&2 "ERROR: You must provide at least one IPv4 address to find."
	echo ""
	printUsage
	exit 1
fi

# Check to be sure the management API is running. If not, restart it.
api status >/dev/null 2>/dev/null || api start >/dev/null

portNumber=$(api status | grep "APACHE Gaia Port" | awk '{print $NF}')

showAll() {
IFS=$(printf "\377")
sharedArguments=( --port "${portNumber}" -f json ${cmaAddress:+-d "${cmaAddress}"} -r true show "${1}" details-level full limit 500 )
if ! firstResult=$(mgmt_cli "${sharedArguments[@]}");then return 1;fi
toReturn="$(<<<"${firstResult}" jq -c '.objects[]|.')
";objectCount=$(<<<"${firstResult}" jq -c '.total')
if [ "${objectCount}" -lt 501 ];then echo -n "${toReturn}";return 0;fi
for offsetVal in $(seq 500 500 "${objectCount}" 2>/dev/null | tr "\n" "${IFS}");do
toReturn+="$(mgmt_cli "${sharedArguments[@]}" offset "${offsetVal}" \
| jq -c '.objects[]|.')
";done;echo -n "${toReturn}";}

cmaList=$(showAll domains \
| jq -c '{name:.name,server:.servers[]|{host:."multi-domain-server",ipAddress:."ipv4-address"}}' \
| grep "$(hostname)" \
| jq -c '[.name,.server.ipAddress]')
if [ "0" == "${#cmaList}" ];then cmaList=("[\"$(hostname)\",\"\"]");fi

echo "${cmaList[@]}" | while read cmaRow; do
cmaName=$(<<<"${cmaRow}" jq '.[0]' | sed 's#"##g')
cmaAddress=$(<<<"${cmaRow}" jq '.[1]' | sed 's#"##g')
echo "${cmaName}:"
for addressToFind in $addressList; do
mgmt_cli --port "${portNumber}" -f json \
${cmaAddress:+-d ${cmaAddress}} -r true \
show objects ip-only true type host limit 500 \
filter "${addressToFind}" \
| jq -c ".objects[]|.name"
done
echo ""
done
