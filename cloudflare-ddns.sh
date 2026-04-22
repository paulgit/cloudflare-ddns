#!/usr/bin/env bash
# ============================================================
# cloudflare-ddns.sh
#
# Uses Cloudflare as a Dynamic DNS provider to keep DNS records
# automatically updated with the current public IP address.
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
# Disclaimer: No warranties are given for correct function.
# Written by: Paul Git and Claude AI
#
# Variable names are uppercased if the variable is read-only
# or if it is an external variable.
# ============================================================

set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes

IFS=$'\n\t'

# ------------------------------------------------------------
# Global read-only variables
# ------------------------------------------------------------
# shellcheck disable=SC2155  # SCRIPT_DIR is computed once at startup
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME
SCRIPT_NAME="$(basename "$0")"

# ------------------------------------------------------------
# Global variables
# ------------------------------------------------------------
CONFIG_FILE="cloudflare-ddns.conf"
# shellcheck disable=SC2034  # IP_FILE may be used by external scripts
IP_FILE="$SCRIPT_DIR/ip.txt"
ID_FILE="$SCRIPT_DIR/cloudflare.ids"
# shellcheck disable=SC2034  # LOG_FILE may be used by external scripts
LOG_FILE="$SCRIPT_DIR/cloudflare.log"

ZONE_IDENTIFIER=""
RECORD_IDENTIFIER=""

# ============================================================
# _red
#   Returns a string formatted in red for terminal output.
#   Input:  $1 - string to format
#   Output: red formatted string to stdout
# ============================================================
function _red() {
  local message="$1"
  printf '\033[1;31;31m%b\033[0m' "$message"
}

# ============================================================
# _yellow
#   Returns a string formatted in yellow for terminal output.
#   Input:  $1 - string to format
#   Output: yellow formatted string to stdout
# ============================================================
function _yellow() {
  local message="$1"
  printf '\033[1;31;33m%b\033[0m' "$message"
}

# ============================================================
# _warn
#   Prints a warning message with timestamp to stderr.
#   Input:  $1 - warning message
#   Output: warning message to stderr
#   Called by: load_config
# ============================================================
function _warn() {
  local message="$1"
  printf -- "%s" "[$(date)] "
  _yellow "$message"
  printf "\n"
}

# ============================================================
# _error
#   Prints an error message with timestamp to stderr and exits.
#   Input:  $1 - error message
#   Output: error message to stderr, exits with code 2
# ============================================================
function _error() {
  local message="$1"
  printf -- "%s" "[$(date)] "
  _red "$message"
  printf "\n"
  exit 2
}

# ============================================================
# _printargs
#   Prints a message with timestamp to stdout.
#   Input:  $1 - message to print
#   Output: formatted message to stdout
#   Called by: _info
# ============================================================
function _printargs() {
  local message="$1"
  printf -- "%s" "[$(date)] "
  printf -- "%s" "$message"
  printf "\n"
}

# ============================================================
# _info
#   Prints an informational message to stdout.
#   Input:  $1 - informational message
#   Output: informational message to stdout
#   Called by: check_for_ip_change
# ============================================================
function _info() {
  _printargs "$@"
}

# ============================================================
# _exit
#   Prints termination message and exits.
#   Input:  none
#   Output: termination message to stdout, exits with code 1
#   Called by: load_config
# ============================================================
function _exit() {
  printf "\n"
  _red "$SCRIPT_NAME has been terminated."
  printf "\n"
  exit 1
}

# ============================================================
# check_dependencies
#   Verifies that required tools are installed.
#   Input:  none
#   Output: error message to stderr if missing, exits with code 1
#   Called by: main
# ============================================================
function check_dependencies() {
  local tool
  for tool in jq dig; do
    if ! command -v "${tool}" &>/dev/null; then
      _error "${tool} - commandline JSON processor is not installed"
    fi
  done
}

# ============================================================
# _valid_ip
#   Validates whether the given string is a valid IPv4 address.
#   Input:  $1 - IP address to validate
#   Output: returns 0 if valid, 1 if invalid
#   Called by: check_for_ip_change
# ============================================================
function _valid_ip() {
  local ip="$1"
  local stat=1

  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    local old_ifs="$IFS"
    IFS='.'
    local -a ip_parts
    read -ra ip_parts <<< "$ip"
    IFS=$old_ifs
    [[ ${ip_parts[0]} -le 255 && ${ip_parts[1]} -le 255 \
      && ${ip_parts[2]} -le 255 && ${ip_parts[3]} -le 255 ]]
    stat=$?
  fi
  return $stat
}

# ============================================================
# load_config
#   Loads configuration and retrieves Cloudflare identifiers.
#   Input:  none
#   Output: sets global variables, creates config/ID files
#   Called by: main
# ============================================================
function load_config() {
  if [[ ! -e "$CONFIG_FILE" ]]; then
    cat > "$CONFIG_FILE" <<'EOF'
# Cloudflare as a Dynamic DNS Provider

# Update these with your values
AUTH_EMAIL="YOUR_CLOUDFLARE_AUTH_EMAIL"
AUTH_KEY="YOUR_CLOUDFLARE_AUTH_KEY"
ZONE_NAME="example.com"
RECORD_NAME="site.example.com"

# This can be any IP checking site that returns the IP as plain text
IP_CHECK_URL="http://ipv4.icanhazip.com"
EOF
    _warn "A configuration file was not found, $CONFIG_FILE has been created."
    _warn "This file contains template information. Please update it with your values."
    _exit
  fi

  # shellcheck disable=SC1090  # Can't follow non-constant source
  . "${CONFIG_FILE}"

  if [[ ! -e "$ID_FILE" ]]; then
    local curl_output
    curl_output=$(curl --fail -s -X GET \
      "https://api.cloudflare.com/client/v4/zones?name=$ZONE_NAME" \
      -H "X-Auth-Email: $AUTH_EMAIL" -H "X-Auth-Key: $AUTH_KEY" \
      -H "Content-Type: application/json")

    if [[ -z "$curl_output" ]]; then
      _error "CloudFlare API call to get the Zone Identifier failed. " \
        "Please check to see if your AUTH_EMAIL and AUTH_KEY in $CONFIG_FILE are correct"
    fi

    local zone_identifier
    zone_identifier=$(echo "$curl_output" | jq -r '.result[0].id')

    curl_output=$(curl --fail -s -X GET \
      "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?name=$RECORD_NAME" \
      -H "X-Auth-Email: $AUTH_EMAIL" -H "X-Auth-Key: $AUTH_KEY" \
      -H "Content-Type: application/json")

    if [[ -z "$curl_output" ]]; then
      _error "CloudFlare API call to get the Record Identifier failed. " \
        "Please check to see if your AUTH_EMAIL and AUTH_KEY in $CONFIG_FILE are correct"
    fi

    local record_identifier
    record_identifier=$(echo "$curl_output" | jq -r '.result[0].id')

    if [[ ${#zone_identifier} -eq 32 && ${#record_identifier} -eq 32 ]]; then
      echo "ZONE_IDENTIFIER=$zone_identifier" > "$ID_FILE"
      echo "RECORD_IDENTIFIER=$record_identifier" >> "$ID_FILE"
    else
      _error "Unable to get valid Zone and Record Identifiers from CloudFlare."
    fi
  fi

  # shellcheck disable=SC1090  # Can't follow non-constant source
  . "${ID_FILE}"
}

# ============================================================
# check_for_ip_change
#   Checks if IP has changed and updates Cloudflare DNS record.
#   Input:  none
#   Output: updates DNS record if needed, logs to stdout
#   Called by: main
# ============================================================
function check_for_ip_change() {
  local new_ip
  local old_ip
  local curl_output
  local api_success

  new_ip=$(curl --fail -s --connect-timeout 5 --max-time 10 \
    --retry 3 --retry-all-errors "$IP_CHECK_URL")
  old_ip=$(dig +short +https @1.1.1.1 "$RECORD_NAME" | tail -1)

  if ! _valid_ip "$new_ip"; then
    _error "Unable to lookup the new IP address [$new_ip]"
  fi

  if ! _valid_ip "$old_ip"; then
    _error "Unable to lookup the old IP address [$old_ip]"
  fi

  if [[ "$new_ip" != "$old_ip" ]]; then
    curl_output=$(curl --fail -s -X PUT \
      "https://api.cloudflare.com/client/v4/zones/$ZONE_IDENTIFIER/dns_records/$RECORD_IDENTIFIER" \
      -H "X-Auth-Email: $AUTH_EMAIL" -H "X-Auth-Key: $AUTH_KEY" \
      -H "Content-Type: application/json" \
      --data "{\"id\":\"$ZONE_IDENTIFIER\",\"type\":\"A\",\"name\":\"$RECORD_NAME\",\"content\":\"$new_ip\"}")

    if [[ -z "$curl_output" ]]; then
      _error "The CloudFlare API call to update the IP address " \
        "of $RECORD_NAME to $new_ip failed"
    fi

    api_success=$(echo "$curl_output" | jq -r '.success')
    if [[ "$api_success" != "true" ]]; then
      _error "The CloudFlare API call to update the IP address " \
        "of $RECORD_NAME to $new_ip failed"
    fi

    _info "IP of $RECORD_NAME has been changed to $new_ip (was $old_ip)"
  fi
}

# ============================================================
# show_usage
#   Prints usage information to stdout.
#   Input:  none
#   Output: usage text to stdout
#   Called by: main
# ============================================================
function show_usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [-h|--help]

Uses Cloudflare as a Dynamic DNS provider to keep DNS records
automatically updated with the current public IP address.

Options:
  -h, --help    Show this help message and exit.
EOF
}

# ============================================================
# main
#   Entry point for the script.
#   Input:  $@ - command line arguments
#   Output: varies based on operations performed
# ============================================================
function main() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_usage
    exit 0
  fi

  check_dependencies
  load_config
  check_for_ip_change
}

# Keep files in the same folder when run from cron
cd "$SCRIPT_DIR"

main "$@"
