#!/bin/env bash
################################################################################
## Verify all policy packages under a given management.
################################################################################
. /etc/profile.d/CP.sh

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

for cmaRow in $cmaList; do
cmaName=$(echo "${cmaRow}" | jq '.[0]' | sed 's#"##g')
cmaAddress=$(echo "${cmaRow}" | jq '.[1]' | sed 's#"##g')
policyList=$(mgmt_cli --port ${portNumber} -f json ${cmaAddress:+-d} ${cmaAddress:+${cmaAddress}} -r true show packages limit 500 \
| jq -c '.packages[]|.name' \
| tr -d '"')
for policy in $policyList; do
echo "=========================================================="
printf "%-16s %30s: " "${cmaName}" "${policy}"
tasks=$(mgmt_cli -f json -d "${cmaAddress}" -r true verify-policy policy-package ${policy} 2>/dev/null \
| jq -c '.tasks[]')
status=$(echo "${tasks}" | jq -c '.status' | tr -d '"')
case "${status}" in
"succeeded") tput setaf 2;echo "succeeded";tput sgr0;;
   "failed") tput setaf 1;echo "failed";tput sgr0;;
          *) echo "${status}";;
esac
echo "${tasks}" | jq -c '."task-details"[].errors[]'
done
done
echo "=========================================================="
