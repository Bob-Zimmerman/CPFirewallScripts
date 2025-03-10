# CPFirewallScripts
Scripts for use on Check Point firewalls and management servers.

# For Firewalls
## nukeCons.sh
Dumps connections table entries which match a filter you specify with
the options. It was originally written to delete them, but does not
delete anything by default.

### Usage
```[Expert@MyFirewall]# ./nukeCons.sh -h
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

## scanInts.sh
Iterates through all of the interfaces on a firewall and does an ARP
sweep of each one (using ping to trigger ARP). It then reports which
interfaces' networks are empty. It looks at all interfaces with names
which do not start with 'lo' or 'wrp'. It skips interfaces which don't
have an IP address and logs the skip to STDERR. If you write the output
to a file, you get only the interfaces which have IP addresses in the
file.

### Usage
```
[Expert@MyFirewall-s01-01]# ./scanInts.sh 
Mgmt has no IP address. Skipping.
1 other items in 192.0.2.0/24 on Sync
bond2 has no IP address. Skipping.
0 other items in 172.31.100.0/24 on bond2.100
0 other items in 172.31.101.0/24 on bond2.101
erspan0 has no IP address. Skipping.
eth1-Sync has no IP address. Skipping.
eth2 has no IP address. Skipping.
eth3 has no IP address. Skipping.
eth4 has no IP address. Skipping.
eth5 has no IP address. Skipping.
3 other items in 10.0.1.0/24 on magg1

[Expert@MyFirewall-s01-01:0]# ./scanInts.sh 2>/dev/null
1 other items in 192.0.2.0/24 on Sync
0 other items in 172.31.100.0/24 on bond2.100
0 other items in 172.31.101.0/24 on bond2.101
3 other items in 10.0.1.0/24 on magg1
```

## vsClish.sh
Lets you run commands in clish (like `clish -c "..."`) in VSs other
than 0. Specify a VSID as the first argument to run the commands in
another VS without switching to it. Leave out the VSID to use the VSID
you are currently in.

### Usage
```
[Expert@MyFirewall-01:0]# clish -c "show router-id"

Active Router ID:      10.15.30.45
Configured Router ID:  none

[Expert@MyFirewall-01:0]# ./vsClish.sh 5 show router-id
Context is set to vsid 5

Active Router ID:      10.32.64.1
Configured Router ID:  none

Done.                                                        
[Expert@MyFirewall-01:2]# vsenv 5
Context is set to Virtual Device MyFirewall-01_FifthVS (ID 5).
[Expert@MyFirewall-01:2]# ./vsClish.sh show router-id
Context is set to vsid 5

Active Router ID:      10.32.64.1
Configured Router ID:  none

Done.                                                        
```

# For Management Servers
I store all of these scripts in /var/log/scripts on my management
servers. If you want to put them somewhere else, be sure to check for
static paths in the scripts.

I try to put variables which you need to customize for your environment
towards the top of the scripts, and I try to keep them as simple
assignments at the top level (no indentation).

## autoPush_Dev-QA.sh
An example of a script I use to set up a push window for autoPushWorker.
You will need to change almost everything in this script. I make a copy
of this script for each set of policies I want to push together. If you
want to separate pushes to one datacenter from pushes to another
datacenter, just make a separate window script for each of them. Here's
an example clish cronjob:

`add cron job autoPush_Dev_QA command "/var/log/scripts/autoPush_Dev-QA.sh" recurrence weekly days 1,2,3,4,5 time 13:00`

You can suspend pushes to the whole management (e.g, during a change
freeze) by creating the file `/suspendPushes`, or to a single firewall
(e.g, while upgrading that firewall) by creating the file
`/suspend_<firewall name>`. Note these file names are case-sensitive.

## autoPushWorker.sh
Takes mail information and push window configuration from a script like
autoPush_Dev-QA.sh and executes the pushes. The only customization this
one should need is the documentationUrl. In my environment, I use a
document which explains which policies we push when.

If sends an email when it starts to tell you it is pushing the policies.
Once the pushes have finished, you get a summary of the results. Right
now, the summary includes success or failure, the count of
errors/warnings/etc., and any error messages.

## clusterDiff.sh
Runs a script you provide on each member of every cluster reporting to
the management where it is run, then uses diff to find differences in
the output. You can specify your own script after `cat << 'EOF' > "${scriptFile}"`
and before the line which has `EOF` by itself. The script I have
provided there dumps the clish config and finds differences. It works on
normal clusters and VSX clusters. NOTE: This does not support ElasticXL
and does not work on clusters with more than two members.

If you write your own script, it should write its output to
`/tmp/clusterDiff.output` on the firewalls.

## configDiffEmail.sh
A simple wrapper to email the cluster member differences through the
mail relay defined in `MTA` to the email addresses in `mailRecipients`.

## onEachFirewall.sh
Takes a file you provide, copies it to all firewalls reporting to this
management server, runs it, and shows the output.

### Usage
Here's an example script I use which gets the hostname, model, major
version, jumbo, and uptime.
```
[Expert@MyMDS]# cat <<'EOF' >"${scriptFile}"
> printf "%-25s %6s %-6s %3s %-20s" \
> $(hostname) \
> $(clish -c "show asset system" | egrep -q "^Model";if [ $? -eq 0 ];then clish -c "show asset system" | egrep "^Model" | awk '{print $NF}';else clish -c "show asset system" | egrep "^Platform" | cut -d" " -f2 | cut -c 1-5;fi) \
> $(fw ver | awk '{print $7}') \
> $(jumbo=$(cpinfo -y fw1 2>/dev/null | grep JUMBO | grep Take | awk '{print $NF}');echo "${jumbo:-0}") \
> "$(uptime | cut -d, -f1 | xargs)"
> EOF
[Expert@MyMDS]# /var/log/scripts/onEachFirewall.sh -v "${scriptFile}";/usr/bin/rm "${scriptFile}"
        SomeCMA     10.20.30.28: FirstCluster-01             6900 R81.20  92 14:25:19 up 161 days
        SomeCMA     10.20.30.29: FirstCluster-02             6900 R81.20  92 14:25:22 up 161 days
        SomeCMA     10.12.4.197: SecondCluster-01            6800 R81.20  92 14:25:24 up 27 days 
        SomeCMA     10.12.4.198: SecondCluster-02            6800 R81.20  92 14:25:27 up 27 days 
...
```

The -v switch causes the first two columns (domain name on an MDS, or
management name on a non-multi-domain system, and main IP address of the
system it is working on). Without -v, you only get output from the
remote systems. It makes the onEachFirewall script itself more verbose,
which allows the output to potentially be more concise. When using it,
the output from the remote system *should not* end in a newline. If
every other line is blank, the script you are running probably includes
a newline at the end.

Errors also take a slightly different form with -v. When the script
fails to connect to a remote system via CPRID, -v prints "Couldn't
connect via CPRID", relying on the CMA name and main IP address printed
by the -v to identify which system couldn't be reached. Without -v, a
CPRID connectivity issue prints "\<address>	Couldn't connect via
CPRID".

## verifyAll.sh
Verifies all policy packages on a management server. If you run it on an
MDS, it verifies all policy packages on all CMAs.

My current process for decommissioning old systems involves replacing
the objects for the old systems with "None". This results in empty
groups, and an empty group in a rule fails verification (and since
verification is required before pushing, it also breaks the ability to
push). I wrote this to run at the end of the day after handling all the
decoms to see what policies they broke.

If you have policy packages which are expected to fail verification, you
can make the script ignore them. Just add a `grep -v "<policy name>" \`
after the `| jq -c '.packages[]|.name' \` line.