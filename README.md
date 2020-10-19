# CPFirewallScripts
Scripts for use on Check Point firewalls.

Check Point's OS, GAiA, is based on Redhat Enterprise Linux, or RHEL. They use two versions currently: RHEL 5.2 and RHEL 7.6. You can tell which you are using by looking at the kernel version returned when you run `uname -a`. If it says 2.6.18-92cp, you are running RHEL 5.2. If it says 3.10.0-957, you are on RHEL 7.6.

Unfortunately, this difference matters, and I can't paper over it in code. The first line of a shell script has to be a path to the interpreter. RHEL 5.2 has the interpreters in /bin, and RHEL 7.6 has them in /usr/bin. Scripts committed to this repository will target 7.6.

Versions known to use RHEL 7.6:
* R81
* R80.40
* R80.30 management

Versions known to use RHEL 5.2:
* R80.30 firewall
* R80.20
* R80.10
* R80
* R77.30
* R77.20
* R77.10
* R77

## Important!
To run these scripts on RHEL 5.2, you will need to change the first line from `#!/usr/bin/env bash` to `#!/bin/env bash`

# nukeCons.sh
## Usage
This script dumps connections table entries which match a filter you specify with the options.

```[Bob_Zimmerman@MyFirewall]# ./nukeCons.sh -h
Note: this script must be run as root.

Usage:
./nukeCons.sh [-l|-x] [-v <VSID>] [-s IP] [-S port] [-d IP] [-D port] [-P protocol]
	-l		Only list matching connections. Do not prompt.
	-x		Delete matching connections without prompting.
			Default is to list matches and prompt for deletion.

	-v VSID		Run in a specific VSID.
			Default is to run in current VSID.

	-s IP		Search for the specified source IP address.
	-S port		Search for the specified source port.
	-d IP		Search for the specified destination IP address.
	-D port		Search for the specified destination port.
	-P protocol	Search for the specified IP protocol.
	-h		Print this usage information.
```
