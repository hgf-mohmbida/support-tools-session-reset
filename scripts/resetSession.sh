#!/bin/bash

# Add manual jq path for local Git Bash (optional)
export PATH=$PATH:/c/Users/mohammed.mbida/Tools

set -euo pipefail

command -v jq >/dev/null || { echo "❌ Missing dependency: jq"; exit 1; }

# Input parameters
environment=$1
serialNumber=$2

# Credentials passed via environment (from GitHub Secrets)
username="${SUPPORT_USERNAME:-}"
password="${SUPPORT_PASSWORD:-}"

# Decide IP and protocol based on environment
case "$environment" in
  pre)
    ip="10.11.52.76"
    protocol="http"
    ;;
  mirror)
    ip="10.231.28.15"
    protocol="http"
    ;;
  prod)
    echo "❌ Production environment not set up yet."
    exit 1
    ;;
  *)
    echo "❌ Invalid environment. Use: pre | mirror | prod"
    exit 1
    ;;
esac

echo "🔐 Authenticating with user '$username' on $ip..."

# Get login token
id_token=$(curl -s -X POST "$protocol://$ip:8080/support_tools_war/api/authenticate" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$username\",\"password\":\"$password\",\"rememberMe\":true}" | jq -r '.id_token')

echo "🔑 ID-Token: $id_token"

if [ -z "$id_token" ] || [ "$id_token" == "null" ]; then
    echo "❌ Could not retrieve login token. Check credentials or server."
    exit 1
fi

# Get account
account=$(curl -s -X GET "$protocol://$ip:8080/support_tools_war/api/customer/find/$serialNumber" \
  -H "Authorization: Bearer $id_token" | jq -r '.administrationUserId')

if [ -z "$account" ] || [ "$account" == "null" ]; then
    echo "❌ No account found for serial: $serialNumber"
    exit 1
fi

echo "👤 Account ID: $account"

# Get active sessions
sessions=$(curl -s -X GET "$protocol://$ip:8080/support_tools_war/api/session/account/$account" \
  -H "Authorization: Bearer $id_token")

if [[ "$sessions" == "[]" ]]; then
    echo "ℹ️ No active sessions found for account: $account"
    exit 0
fi

# Find session for the serial number
specificSession=$(echo "$sessions" | jq -c ".[] | select(.serialNumber == \"$serialNumber\")")

if [ -z "$specificSession" ] || [ "$specificSession" == "null" ]; then
    echo "❌ No session found for serial number: $serialNumber"
    exit 1
fi

sessionId=$(echo "$specificSession" | jq -r '.sessionId')

# Delete session
deleteResponse=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
  "$protocol://$ip:8080/support_tools_war/api/session/$sessionId" \
  -H "Authorization: Bearer $id_token")

if [ "$deleteResponse" -eq 200 ]; then
    echo "✅ Session $sessionId for serial $serialNumber was deleted successfully!"
    exit 0
else
    echo "❌ Failed to delete session. HTTP $deleteResponse"
    exit 1
fi


