#!/bin/env bash
################################################################################
## Run a given clish command for a particular VS. You can specify the VSID as
## the first argument. If you don't specify a VSID, it runs in the current VS.
################################################################################
clishScript=$(mktemp)
vsid="${1}"
if [[ "${vsid}" =~ '^[0-9]*$' ]];then shift;else vsid=$(cat /proc/self/nsid);fi
echo "set virtual-system ${vsid}" >${clishScript}
echo "${@}" >>${clishScript}
clish -f "${clishScript}" | sed -E 's/^Processing .+?\r//g'
rm "${clishScript}"
