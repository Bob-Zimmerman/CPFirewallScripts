#!/usr/bin/env bash

printUsage()
{
	echo "Note: this script must be run as root."
	echo ""
	echo "Usage:"
	echo "${0} [-l|-x] [-v <VSID>] [-s IP] [-S port] [-d IP] [-D port] [-P protocol]"
	echo -e "\t-l\t\tOnly list matching connections. Do not prompt."
	echo -e "\t-x\t\tDelete matching connections without prompting."
	echo -e "\t\t\tDefault is to list matches and prompt for deletion."
	echo ""
	echo -e "\t-v VSID\t\tRun in a specific VSID."
	echo -e "\t\t\tDefault is to run in current VSID."
	echo ""
	echo -e "\t-s IP\t\tSearch for the specified source IP address."
	echo -e "\t-S port\t\tSearch for the specified source port."
	echo -e "\t-d IP\t\tSearch for the specified destination IP address."
	echo -e "\t-D port\t\tSearch for the specified destination port."
	echo -e "\t-P protocol\tSearch for the specified IP protocol."
	echo -e "\t-h\t\tPrint this usage information."
}

if [ "${#}" == "0" ]; then
	printUsage
	exit 1
fi

if [ "${EUID}" != "0" ]; then
	echo >&2 "ERROR: This script must be run as root."
	echo ""
	printUsage
	exit 1
fi

OUTPUT="interactive"
VSID=0
SOURCE_ADDR="[0-9a-f]+"
SOURCE_PORT="[0-9a-f]+"
DEST_ADDR="[0-9a-f]+"
DEST_PORT="[0-9a-f]+"
PROTOCOL="[0-9a-f]+"

while getopts "lxv:s:S:d:D:P:h" NUKE_OPTION; do
	case "${NUKE_OPTION}" in
	x)
		OUTPUT="delete"
		;;
	l)
		OUTPUT="list"
		;;
	v)
		VSID="${OPTARG}"
		;;
	s)
		SOURCE_ADDR=$(printf '%02x' ${OPTARG//./ })
		;;
	S)
		SOURCE_PORT=$(printf '%08x' ${OPTARG//./ })
		;;
	d)
		DEST_ADDR=$(printf '%02x' ${OPTARG//./ })
		;;
	D)
		DEST_PORT=$(printf '%08x' ${OPTARG//./ })
		;;
	P)
		PROTOCOL=$(printf '%08x' ${OPTARG//./ })
		;;
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
	:)
		echo >&2 "ERROR: Option -${OPTARG} requires an argument."
		echo ""
		printUsage
		exit 1
		;;
	esac
done

if [ $(cpprod_util FwIsVSX) == "0" ]; then
	FW_TAB_CMD="fw tab"
else
	FW_TAB_CMD="ip netns exec $(printf "CTX%05d" ${VSID}) fw tab"
fi

CONNECTIONS=$(\
	${FW_TAB_CMD} -t connections -u \
	| egrep "<[0-9a-f]+, ${SOURCE_ADDR}, ${SOURCE_PORT}, ${DEST_ADDR}, ${DEST_PORT}, ${PROTOCOL};" \
	| sed -r 's#<([0-9a-f, ]+);.+#\1#' \
	| sed -r 's# ##g')

if [ "${OUTPUT}" == "interactive" ]; then
	echo "Matches:"
	echo "${CONNECTIONS}"

	echo ""
	read -p "Clear these connections? (yes/[no]) " YN
	case "${YN}" in
	[Yy][Ee][Ss])
		<<<"${CONNECTIONS}" xargs -n 1 ${FW_TAB_CMD} -t connections -x -e
		exit 0
		;;
	*)
		echo "Not deleting."
		exit 2
		;;
	esac
elif [ "${OUTPUT}" == "list" ]; then
	echo "${CONNECTIONS}"
elif [ "${OUTPUT}" == "delete" ]; then
	<<<"${CONNECTIONS}" xargs -n 1 ${FW_TAB_CMD} -t connections -x -e
fi
