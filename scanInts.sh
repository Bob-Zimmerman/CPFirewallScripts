#!/bin/env bash
########################################################################
## This script iterates through all of the interfaces on a firewall and
## does an ARP sweep of each one (using ping to trigger ARP). It then
## reports which interfaces' networks are empty. It looks at all
## interfaces with names which do not start with 'lo' or 'wrp'.
## 
## The Linux network kernel has a terrible limitation which necessitates
## the 'sleep 300s' in scanInterfaces. Specifically, there is no good
## way to manually *delete* ARP cache entries. You can only invalidate
## them. They stay around as 'incomplete', cluttering up the table. If
## we don't slow down, they eventually fill the table and prevent new
## entries from being added.
########################################################################
. /etc/profile.d/vsenv.sh

dottedToNumber()
	{
	## Convert an IP in dotted decimal form to a raw number. It's
	## possible to do math with numbers, and nightmarish to do it with
	## dotted decimal IP addresses.
	first=$(<<<"${1}" cut -d. -f1)
	second=$(<<<"${1}" cut -d. -f2)
	third=$(<<<"${1}" cut -d. -f3)
	fourth=$(<<<"${1}" cut -d. -f4)
	echo "$(( (${first}<<24) + (${second}<<16) + (${third}<<8) + ${fourth} ))"
	}

scanNetwork()
	{
	## This function accepts an IP address and prefix length in the form
	## "10.20.30.40/24". It figures out the usable addresses in the
	## block, iterates through it, pings each one, waits briefly, then
	## checks the ARP table to see if something responded. It returns
	## the number of responses it got.
	ipAddr=$(dottedToNumber "$(<<<"${1}" cut -d/ -f1)")
	maskLength=$(<<<"${1}" cut -d/ -f2)
	lowest=$(($ipAddr&0xffffffff<<(32-$maskLength)))
	highest=$(($lowest+(1<<(32-$maskLength))-2))
	itemsInNetwork=0
	for scanAddress in $(seq -f "%.0f" $(($lowest+1)) $highest)
		do
		ping -c 1 -w 1 "${scanAddress}" 2>&1 >/dev/null &
		sleep 0.02s
		if [ "" != "$(arp -n "${scanAddress}" | egrep -v "(incomplete|no entry|HWaddress)")" ];then
			((itemsInNetwork+=1))
		fi
		done
		echo "${itemsInNetwork}"
	}

scanInterfaces()
	{
	## This function accepts no arguments. It runs in the current VRF,
	## finds every interface which doesn't start with 'lo' or 'wrp' and
	## feeds them into 'scanNetwork'.
	vsid="$(sed -E 's/^0$//' /proc/self/nsid)"
	for interfaceToScan in $(ip link show | egrep "^[0-9]" | cut -d" " -f2 | cut -d@ -f1 | sed 's#:##' | egrep -v "^(lo[0-9]*|wrp)" | sort)
		do
		## Get the local interface routes.
		routes=$(ip route show | grep " ${interfaceToScan} " | grep -v "via" | cut -d' ' -f1)
		if [ "" = "${routes[@]}" ];then
			# If there are no local routes for this interface, bail early.
			echo >&2 "${interfaceToScan}${vsid:+ in NSID ${vsid}} has no IP address. Skipping."
			continue
			fi
		for rawAddr in ${routes[@]};do
			items="$(scanNetwork "${rawAddr}")"
			echo "${items} other items in ${rawAddr} on ${interfaceToScan}${vsid:+ in NSID ${vsid}}"
			done
		sleep 300s
		done
	}

for context in $(ip netns list | cut -d' ' -f1 | sort);do
	vsid=$(<<<"${context}" sed -E "s/CTX0+//")
	vsenv "${vsid}" 2>&1 >/dev/null
	scanInterfaces
	done
