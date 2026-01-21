#!/bin/bash
set -e

# Fix permissions on spool directory (needed when mounted as volume)
echo "Fixing Postfix spool permissions..."
postfix set-permissions 2>/dev/null || true
chown -R postfix:postfix /var/spool/postfix/defer /var/spool/postfix/deferred /var/spool/postfix/active /var/spool/postfix/incoming /var/spool/postfix/bounce /var/spool/postfix/corrupt /var/spool/postfix/flush /var/spool/postfix/hold /var/spool/postfix/trace /var/spool/postfix/saved 2>/dev/null || true

# Fix DKIM key permissions
chown opendkim:opendkim /etc/opendkim/keys/dkim-private.pem 2>/dev/null || true
chmod 600 /etc/opendkim/keys/dkim-private.pem 2>/dev/null || true

# Start OpenDKIM
echo "Starting OpenDKIM..."
opendkim -x /etc/opendkim/opendkim.conf

# Wait for OpenDKIM socket
sleep 1

# Start Postfix in foreground
echo "Starting Postfix..."
exec postfix start-fg
