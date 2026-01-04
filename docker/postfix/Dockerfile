FROM alpine:3.20

RUN apk add --no-cache postfix curl bash

# Copy configuration
COPY main.cf /etc/postfix/main.cf
COPY master.cf /etc/postfix/master.cf
COPY relay-to-rails.sh /usr/local/bin/relay-to-rails.sh

# Ensure script is executable by all users (postfix runs as nobody)
RUN chmod 755 /usr/local/bin/relay-to-rails.sh && \
    chown root:root /usr/local/bin/relay-to-rails.sh && \
    postconf -e "maillog_file=/dev/stdout" && \
    newaliases

EXPOSE 25

CMD ["postfix", "start-fg"]
