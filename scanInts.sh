#!/usr/bin/env bash
################################################################################
## This script iterates through all of the interfaces on a firewall and does an
## ARP sweep of each one (using ping to trigger ARP). It then reports which
## interfaces' networks are empty. It looks at all interfaces with names which
## do not start with 'lo' or 'wrp'.
## 
## The Linux network kernel has a terrible limitation which necessitates the
## 'sleep 300s' in scanInterfaces. Specifically, there is no good way to
## manually *delete* ARP cache entries. You can only invalidate them. They stay
## around as 'incomplete', cluttering up the table. If we don't slow down, they
## eventually fill the table and prevent new entries from being added.
################################################################################

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
	## This function accepts an IP in dotted decimal form and returns a raw
	## number. It's possible to do math with numbers, and nightmarish to do it
	## with dotted decimal IP addresses.
	first=$(echo $1 | cut -d. -f1)
	second=$(echo $1 | cut -d. -f2)
	third=$(echo $1 | cut -d. -f3)
	fourth=$(echo $1 | cut -d. -f4)
	echo "$(( $first*2**24 + $second*2**16 + $third*2**8 + $fourth ))"
	}

scanNetwork()
	{
	## This function accepts an IP address and prefix length in the form
	## "10.20.30.40/24". It figures out the usable addresses in the block, then
	## iterates through it, pinging them, waiting briefly, then checking the
	## ARP table to see if something responded. It then prints the number of
	## addresses which responded to ARP within the network along with the
	## interface's name, IP/prefix, and (if the system has more than one VRF),
	## the VRF the interface belongs to.
	ipAddr=$(dottedToNumber "$(echo $1 | cut -d/ -f1)")
	maskLength=$(echo $1 | cut -d/ -f2)
	lowest=$(((ipAddr&${maskFromLength[$maskLength]})))
	highest=$(($lowest+${addressCountFromLength[$maskLength]}))
	itemsInNetwork=0
	for scanAddress in $(seq -f "%.0f" $(($lowest+1)) $highest)
		do
		ping -c 1 -w 1 $scanAddress 2>&1 >/dev/null &
		sleep 0.02s
		if [ $(arp -n $scanAddress | tail -n 1 | awk '{print $2}') != "(incomplete)" ]; then
			((itemsInNetwork+=1))
		fi
		done
	echo -n "$itemsInNetwork items in $interfaceToScan $1"
	if [ -d /proc/vrf ] && [ $(ls /proc/vrf/ | wc -l) -gt 1 ]; then
		echo -n " in VRF $(cat /proc/self/vrf)"
	fi
	echo ""
	}

scanInterfaces()
	{
	## This function accepts no arguments. It runs in the current VRF, finds
	## every interface which doesn't start with 'lo' or 'wrp', and feeds them
	## into 'scanNetwork'. The 'sleep 300s' after the 'scanNetwork' call is to
	## work around the Linux network stack's desire to hold on to ARP cache
	## entries, even if the admin says to delete them.
	for interfaceToScan in $(ip link show | egrep "^[0-9]" | cut -d" " -f2 | cut -d@ -f1 | sed 's#:##' | egrep -v "^(lo[0-9]*|wrp)" | sort)
		do
		rawAddr=$(/bin/cpip addr show $interfaceToScan | grep inet | awk '{print $2}')
		if [ "$rawAddr" != "" ]; then
			scanNetwork "$rawAddr"
			sleep 600s
		else
			echo -n "$interfaceToScan"
			if [ -d /proc/vrf ] && [ $(ls /proc/vrf/ | wc -l) -gt 1 ]; then
				echo -n " in VRF $(cat /proc/self/vrf)"
			fi
			echo " has no IP address. Skipping."
		fi
		done
	}

scanVRFs()
	{
	## This function accepts no arguments. It lists all of the VRFs, switches
	## into them, and calls 'scanInterfaces'. This can be skipped if there is
	## only the one routing table.
	for vrfToScan in $(ls /proc/vrf/ | sort -n)
		do
		vsx set $vrfToScan>/dev/null
		scanInterfaces
		sleep 10s
		done
	}

## If this system is VRF-aware and we're running more than one VRF, scan the
## VRFs. Otherwise, just scan the interfaces for the current VRF.
if [ -d /proc/vrf ] && [ $(ls /proc/vrf/ | wc -l) -gt 1 ]; then
	scanVRFs
else
	scanInterfaces
fi
