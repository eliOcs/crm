#!/bin/bash
# Relay email from Postfix to Rails ActionMailbox via HTTP
#
# This script:
# 1. Reads raw email from stdin (piped from Postfix)
# 2. POSTs it to Rails ActionMailbox relay ingress
# 3. Returns appropriate exit code for Postfix

set -e

RAILS_HOST="${RAILS_INBOUND_HOST:-crm-web:3000}"
RAILS_PASSWORD="${RAILS_INBOUND_EMAIL_PASSWORD:-}"

if [ -z "$RAILS_PASSWORD" ]; then
  echo "ERROR: RAILS_INBOUND_EMAIL_PASSWORD not set" >&2
  exit 75  # Temp failure, retry later
fi

# Read email from stdin
EMAIL_CONTENT=$(cat)

# POST to ActionMailbox relay endpoint
# The relay ingress expects the raw email in the request body
HTTP_CODE=$(echo "$EMAIL_CONTENT" | curl -s -w "%{http_code}" -o /tmp/response.txt \
  --max-time 30 \
  -X POST \
  -u "actionmailbox:${RAILS_PASSWORD}" \
  -H "Content-Type: message/rfc822" \
  --data-binary @- \
  "http://${RAILS_HOST}/rails/action_mailbox/relay/inbound_emails")

# Check response
if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "200" ]; then
  # Success
  exit 0
elif [ "$HTTP_CODE" = "401" ]; then
  echo "ERROR: Authentication failed (401)" >&2
  exit 77  # Permanent failure
elif [ "$HTTP_CODE" = "422" ]; then
  echo "ERROR: Unprocessable email (422)" >&2
  exit 77  # Permanent failure
elif [ "$HTTP_CODE" -ge 500 ]; then
  echo "ERROR: Server error ($HTTP_CODE), will retry" >&2
  cat /tmp/response.txt >&2
  exit 75  # Temp failure, retry later
else
  echo "ERROR: Unexpected response ($HTTP_CODE)" >&2
  cat /tmp/response.txt >&2
  exit 75  # Temp failure, retry later
fi
