FROM alpine:3.20

RUN apk add --no-cache postfix curl bash opendkim opendkim-utils

# Copy Postfix configuration
COPY main.cf /etc/postfix/main.cf
COPY master.cf /etc/postfix/master.cf
COPY relay-to-rails.sh /usr/local/bin/relay-to-rails.sh

# Copy OpenDKIM configuration (key mounted at runtime)
COPY dkim/opendkim.conf /etc/opendkim/opendkim.conf
COPY dkim/SigningTable /etc/opendkim/SigningTable
COPY dkim/KeyTable /etc/opendkim/KeyTable
COPY dkim/TrustedHosts /etc/opendkim/TrustedHosts

# Set permissions (key directory will be mounted)
RUN chmod 755 /usr/local/bin/relay-to-rails.sh && \
    chown root:root /usr/local/bin/relay-to-rails.sh && \
    chown -R opendkim:opendkim /etc/opendkim && \
    mkdir -p /etc/opendkim/keys /run/opendkim && \
    chown opendkim:opendkim /etc/opendkim/keys /run/opendkim && \
    postconf -e "maillog_file=/dev/stdout" && \
    newaliases

EXPOSE 25

# Start both OpenDKIM and Postfix
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

CMD ["/usr/local/bin/start.sh"]
