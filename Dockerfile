FROM debian:trixie
LABEL org.opencontainers.image.source=https://github.com/mamama1/mail-gateway
ENV PATH="/container/scripts:${PATH}"
ENV DEBIAN_FRONTEND=noninteractive

# 1. PRE-CREATE USERS WITH SPECIFIC IDs
# This ensures consistency with old Bullseye volumes (UID 101) 
# and Trixie requirements (GID 103 for postdrop).
RUN groupadd -g 103 postdrop && \
    groupadd -g 101 postfix && \
    useradd -u 101 -g postfix -G postdrop -s /bin/false -d /var/spool/postfix postfix && \
    groupadd -g 102 opendkim && \
    useradd -u 102 -g opendkim -s /bin/false -d /var/lib/opendkim opendkim

RUN apt-get -q -y update \
 && apt-get -q -y install --no-install-recommends runit \
                          telnet \
                          net-tools \
                          postfix \
                          libsasl2-modules \
                          rsyslog \
                          clamav clamav-daemon amavisd-new spamassassin razor pyzor \
                          arj bzip2 cabextract cpio file gzip nomarch pax unzip zip \
                          \
                          opendkim \
                          opendkim-tools \
 && apt-get -q -y clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
 \
 && mkdir -p /var/run/clamav \
 && chown clamav.clamav -R /var/run/clamav \
 \
 && head -n $(grep -n RULES /etc/rsyslog.conf | cut -d':' -f1) /etc/rsyslog.conf > /etc/rsyslog.conf.new \
 && mv /etc/rsyslog.conf.new /etc/rsyslog.conf \
 && echo '*.*        /dev/stdout' >> /etc/rsyslog.conf \
 && sed -i '/imklog/d' /etc/rsyslog.conf \
 \
 && adduser clamav amavis

#
# ClamAV
#

RUN timeout 500 freshclam || true

#
# razor & pyzor
#

RUN su - amavis -s /bin/bash -c 'razor-admin -create; razor-admin -register; pyzor discover'

# 2. ADD A PERMISSION FIX TO THE BUILD
RUN mkdir -p /etc/postfix/additional/opendkim/keys && \
    chown -R root:root /etc/postfix && \
    chown -R postfix:postdrop /var/spool/postfix

#
# Relay Configuration
#

RUN postconf -e 'mydestination=localhost, localhost.localdomain, localhost' \
 && postconf -e 'smtpd_relay_restrictions=' \
 && postconf -e 'smtpd_recipient_restrictions=permit_mynetworks reject_unauth_destination' \
 \
 && postconf -e 'mydestination=' \
 && postconf -e 'local_recipient_maps=' \
 && postconf -e 'local_transport = error:local mail delivery is disabled'

COPY . /container/

VOLUME ["/etc/postfix/tls", "/etc/postfix/additional"]
HEALTHCHECK CMD ["/container/scripts/docker-healthcheck.sh"]
ENTRYPOINT ["entrypoint.sh"]

CMD [ "runsvdir","-P", "/etc/service" ]
