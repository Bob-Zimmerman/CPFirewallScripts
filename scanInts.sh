#!/bin/env bash
########################################################################
## This script iterates through all of the interfaces on a firewall and
## does an ARP sweep of each one (using ping to trigger ARP). It then
## reports which interfaces' networks are empty. It looks at all
## interfaces with names which do not start with 'lo', 'wrp', 'gre0' or
## 'gretap0'.
## 
## The Linux network kernel has a terrible limitation which necessitates
## the 'sleep 300s' in scanInterfaces. Specifically, there is no good
## way to manually *delete* ARP cache entries. You can only invalidate
## them. They stay around as 'incomplete', cluttering up the table. If
## we don't slow down, they eventually fill the table and prevent new
## entries from being added.
################################################################################
. /etc/profile.d/vsenv.sh

## First, we build some tables. No reason to compute this at runtime.
maskFromLength=(0x0
0x80000000
0xc0000000
0xe0000000
0xf0000000
0xf8000000
0xfc000000
0xfe000000
0xff000000
0xff800000
0xffc00000
0xffe00000
0xfff00000
0xfff80000
0xfffc0000
0xfffe0000
0xffff0000
0xffff8000
0xffffc000
0xffffe000
0xfffff000
0xfffff800
0xfffffc00
0xfffffe00
0xffffff00
0xffffff80
0xffffffc0
0xffffffe0
0xfffffff0
0xfffffff8
0xfffffffc
0xfffffffe
0xffffffff)

addressCountFromLength=(4294967294
2147483646
1073741822
536870910
268435454
134217726
67108862
33554430
16777214
8388606
4194302
2097150
1048574
524286
262142
131070
65534
32766
16382
8190
4094
2046
1022
510
254
126
62
30
14
6
2
2
0)

dottedToNumber()
	{
	## Convert an IP in dotted decimal form to a raw number. It's
	## possible to do math with numbers, and nightmarish to do it with
	## dotted decimal IP addresses.
	first=$(echo $1 | cut -d. -f1)
	second=$(echo $1 | cut -d. -f2)
	third=$(echo $1 | cut -d. -f3)
	fourth=$(echo $1 | cut -d. -f4)
	echo "$(( (${first}<<24) + (${second}<<16) + (${third}<<8) + ${fourth} ))"
	}

scanNetwork()
	{
	## This function accepts an IP address and prefix length in the form
	## "10.20.30.40/24". It figures out the usable addresses in the
	## block, iterates through it, pings each one, waits briefly, then
	## checks the ARP table to see if something responded. It returns
	## the number of responses it got.
	ipAddr=$(dottedToNumber "$(echo $1 | cut -d/ -f1)")
	maskLength=$(echo $1 | cut -d/ -f2)
	lowest=$((($ipAddr&${maskFromLength[$maskLength]})))
	highest=$(($lowest+${addressCountFromLength[$maskLength]}))
	itemsInNetwork=0
	for scanAddress in $(seq -f "%.0f" $(($lowest+1)) $highest)
		do
		ping -c 1 -w 1 $scanAddress 2>&1 >/dev/null &
		sleep 0.02s
		if [ "" != "$(arp -n $scanAddress | egrep -v "(incomplete|no entry|HWaddress)")" ];then
			((itemsInNetwork+=1))
		fi
		done
		echo "${itemsInNetwork}"
	}

scanInterfaces()
	{
	## This function accepts no arguments. It runs in the current VRF,
	## finds every interface which doesn't start with 'lo', 'wrp',
	## 'gre0', or 'gretap0', and feeds them into 'scanNetwork'. The
	## 'sleep 300s' is to work around the Linux network stack's desire
	## to hold on to ARP cache entries, even if the admin says to delete
	## them.
	vsid="$(sed -E 's/^0$//' /proc/self/nsid)"
	for interfaceToScan in $(ip link show | egrep "^[0-9]" | cut -d" " -f2 | cut -d@ -f1 | sed 's#:##' | egrep -v "^(lo[0-9]*|wrp|gre0|gretap0)" | sort)
		do
		## Get the local interface routes.
		routes=$(ip route show | grep " ${interfaceToScan} " | grep -v "via" | cut -d' ' -f1)
		if [ "" = "${routes[@]}" ];then
			# If there are no local routes for this interface, bail early.
			echo >&2 "${interfaceToScan}${vsid:+ in NSID $vsid} has no IP address. Skipping."
			continue
			fi
		for rawAddr in ${routes[@]};do
			items="$(scanNetwork "${rawAddr}")"
			echo "$items other items in ${rawAddr} on ${interfaceToScan}${vsid:+ in NSID $vsid}"
			done
		sleep 300s
		done
	}

for context in $(ip netns list | cut -d' ' -f1 | sort);do
	vsid=$(echo "${context}" | sed -E "s/CTX0+//")
	vsenv "${vsid}" 2>&1 >/dev/null
	scanInterfaces
	done
