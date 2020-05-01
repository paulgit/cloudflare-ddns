#!/bin/bash
#
# Cloudflare as a Dynamic DNS provider
#
# Copyright (C) 2020 Paul Git <paulgit@pm.me>
#
# Reference URLs:
#  https://letswp.io/cloudflare-as-dynamic-dns-raspberry-pi/
#  https://gist.github.com/TheFirsh/c9f72970eaae3aec04beb1106cc304bc
#  https://gist.github.com/benkulbertis/fff10759c2391b6618dd/
#  https://phillymesh.net/2016/02/23/setting-up-dynamic-dns-for-your-registered-domain-through-cloudflare/
#  https://www.linuxjournal.com/content/validating-ip-address-bash-script
#
# Credits : 
#  Thanks to https://github.com/teddysun and his great scripts that have inspired me with ideas to 
#  create my own.
#

_red() {
	printf '\033[1;31;31m%b\033[0m' "$1"
}

_error() {
	printf -- "%s" "[$(date)] "
	_red "$1"
	printf "\n"
	exit 2
}

_printargs() {
    printf -- "%s" "[$(date)] "
    printf -- "%s" "$1"
    printf "\n"
}

_info() {
    _printargs "$@"
}

_exists() {
	local cmd="$1"
	if eval type type > /dev/null 2>&1; then
		eval type "$cmd" > /dev/null 2>&1
	elif command > /dev/null 2>&1; then
		command -v "$cmd" > /dev/null 2>&1
	else
		which "$cmd" > /dev/null 2>&1
	fi
	rt="$?"
	return ${rt}
}

# _valid_ip()
#
# Taken from https://www.linuxjournal.com/content/validating-ip-address-bash-script
# Validating an IP Address in a Bash Script by by Mitch Frazier on June 26, 2008
_valid_ip()
{
	local  ip=$1
	local  stat=1

	if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		OIFS=$IFS
		IFS='.'
		ip=($ip)
		IFS=$OIFS
		[[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
			&& ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
		stat=$?
	fi
	return $stat
}

check_prequisites()
{
	if ! _exists "jq" ; then
		_error "jq - commandline JSON processor is not installed"
	fi

	if ! _exists "dig" ; then
		_error "dig - commandline domain information groper is not installed"
	fi
}

load_config()
{
	# Check if the configuration file exists, if not then no need to go any further
	if [[ ! -e "$CONFIG_FILE" ]]; then
		_error "Unable to find $CONFIG_FILE"
	fi

	# Load the config file	
	. ${CONFIG_FILE}

	# Check to see if the ID file exists, if not create it
	if [[ ! -e "$ID_FILE" ]]; then
			# First we must get the Zone Identifier
			CURL_OUTPUT=$(curl --fail -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$ZONE_NAME" -H "X-Auth-Email: $AUTH_EMAIL" -H "X-Auth-Key: $AUTH_KEY" -H "Content-Type: application/json")
			if [ -z "$CURL_OUTPUT" ]; then
				_error "CloudFlare API call to get the Zone Identifier failed. Please check to see ig your AUTH_EMAIL and AUTH_KEY in $CONFIG_FILE are correct"
			else
				# Extract the Zone Identifier 
				ZONE_IDENTIFIER=$(echo $CURL_OUTPUT | jq -r '.result[0].id')
				CURL_OUTPUT=$(curl --fail -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_IDENTIFIER/dns_records?name=$RECORD_NAME" -H "X-Auth-Email: $AUTH_EMAIL" -H "X-Auth-Key: $AUTH_KEY" -H "Content-Type: application/json")
				if [ -z "$CURL_OUTPUT" ]; then
					_error "CloudFlare API call to get the Record Identifier failed. Please check to see if your AUTH_EMAIL and AUTH_KEY in $CONFIG_FILE are correct"
				else
					# Extract the Record Identifier 
					RECORD_IDENTIFIER=$(echo $CURL_OUTPUT | jq -r '.result[0].id')
				fi
				
				# At this point we should have two 32 character identifiers, if we have then write them to id file				
				if [[ ${#ZONE_IDENTIFIER} -eq 32 && ${#RECORD_IDENTIFIER} -eq 32 ]]; then
					echo "ZONE_IDENTIFIER=$ZONE_IDENTIFIER" > $ID_FILE
					echo "RECORD_IDENTIFIER=$RECORD_IDENTIFIER" >> $ID_FILE
				else
					_error "Unable to get valid Zone and Record Identifiers from CloudFlare."
				fi
			fi
	fi
	
	# Load the ID file
	. ${ID_FILE}
}

check_for_ip_change()
{
	# Get the old IP and current IP
	NEW_IP=$(curl --fail -s $IP_CHECK_URL)
	OLD_IP=$(dig +short @1.1.1.1 $RECORD_NAME)
	
	if ! _valid_ip $NEW_IP; then
		_error "Unable to lookup the new IP address"
	fi

	if ! _valid_ip $OLD_IP; then
		_error "Unable to lookup the old IP address"
	fi

	# OK, we have valid IP address lets see if they are different and update the DNS if required
	if [ $NEW_IP != $OLD_IP ]; then
		CURL_OUTPUT=$(curl --fail -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_IDENTIFIER/dns_records/$RECORD_IDENTIFIER" -H "X-Auth-Email: $AUTH_EMAIL" -H "X-Auth-Key: $AUTH_KEY" -H "Content-Type: application/json" --data "{\"id\":\"$ZONE_IDENTIFIER\",\"type\":\"A\",\"name\":\"$RECORD_NAME\",\"content\":\"$NEW_IP\"}")
		if [ -z "$CURL_OUTPUT" ]; then		
			_error "The CloudFlare API call to update the IP address of $RECORD_NAME to $NEW_IP failed"
		else	
			API_SUCCESS=$(echo $CURL_OUTPUT | jq -r '.success')
			if [ $API_SUCCESS != "true" ]; then 
				_error "The CloudFlare API call to update the IP address of $RECORD_NAME to $NEW_IP failed"
			else							
				_info	"IP of $RECORD_NAME has been changed to $NEW_IP (was $OLD_IP)"
			fi
		fi
	fi
}

main()
{
	check_prequisites
	load_config		
	check_for_ip_change
}

# Keep files in the same folder when run from cron
CURRENT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Setup some key variables
CONFIG_FILE="cloudflare-ddns.conf"
IP_FILE="$CURRENT/ip.txt"
ID_FILE="$CURRENT/cloudflare.ids"
LOG_FILE="$CURRENT/cloudflare.log"
ZONE_IDENTIFIER=""
RECORD_IDENTIFIER=""

main "$@"