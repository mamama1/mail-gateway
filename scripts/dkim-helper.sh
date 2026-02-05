#!/bin/bash

echo ">> DKIM - Domains ($DKIM_DOMAINS)"
echo ">> DKIM - Selector ($DKIM_SELECTOR)"

# --- NEW: PERMISSION PEACE TREATY ---
# Ensure the directory structure exists before setting permissions
mkdir -p /etc/postfix/additional/opendkim/keys

echo ">> DKIM - Applying Trixie-compliant permissions"
# Satisfy Postfix: Directories must be owned by root
find /etc/postfix/additional/opendkim -type d -exec chown root:root {} +
find /etc/postfix/additional/opendkim -type d -exec chmod 755 {} +

# Satisfy OpenDKIM: Private keys must be secure (640) and group-readable
# We use the group 'opendkim' (which we ensured is GID 102 or matches the user)
# Or simply use the UID/GID numbers if preferred.
# ------------------------------------

echo ">> DKIM - updating opendkim config"

touch /etc/postfix/additional/opendkim/KeyTable \
      /etc/postfix/additional/opendkim/SigningTable \
      /etc/postfix/additional/opendkim/TrustedHosts

echo ">> DKIM - trust all hosts (0.0.0.0/0)"
echo "0.0.0.0/0" > /etc/postfix/additional/opendkim/TrustedHosts

cat <<EOF >> /etc/opendkim.conf

Mode			              sv
SubDomains              yes

LogWhy                  yes

KeyTable                /etc/postfix/additional/opendkim/KeyTable
SigningTable            /etc/postfix/additional/opendkim/SigningTable
InternalHosts           /etc/postfix/additional/opendkim/TrustedHosts
EOF

echo ">> DKIM - updating Postfix config"
cat <<EOF >> /etc/postfix/main.cf
### DKIM signing ###
milter_default_action = accept
milter_protocol = 6
smtpd_milters = inet:localhost:8891
non_smtpd_milters = inet:localhost:8891
EOF

for domain in $(echo $DKIM_DOMAINS); do
  echo ">> DKIM - enable domain: $domain"

  keydir="/etc/postfix/additional/opendkim/keys/$domain"
  if [ ! -d "$keydir" ]; then
    mkdir -p $keydir
    chown root:root "$keydir"
    chmod 755 "$keydir"
  fi
  cd $keydir

  if [ ! -f $DKIM_SELECTOR.private ]; then
    echo ">> generate key for domain $domain"
    opendkim-genkey -s "$DKIM_SELECTOR" -d "$domain"
    #chown opendkim:opendkim $DKIM_SELECTOR.private

    echo "$DKIM_SELECTOR._domainkey.$domain $domain:$DKIM_SELECTOR:$keydir/$DKIM_SELECTOR.private" >> /etc/postfix/additional/opendkim/KeyTable
    echo "$domain $DKIM_SELECTOR._domainkey.$domain" >> /etc/postfix/additional/opendkim/SigningTable
    echo ">> key for domain $domain created"
  else
    echo ">> key for domain $domain exists already"
  fi

  # MANDATORY FIX FOR EVERY BOOT:
  # This solves the "key data is not secure" vs "not owned by root" loop
  chown root:opendkim "$DKIM_SELECTOR.private"
  chmod 640 "$DKIM_SELECTOR.private"
  chown root:root "$DKIM_SELECTOR.txt"
  chmod 644 "$DKIM_SELECTOR.txt"
  
  echo ">> DKIM - fix owner of directory /etc/postfix/additional/opendkim/keys (set to opendkim:opendkim)"
  #chown -R root:root /etc/postfix/additional/opendkim/keys

  echo "---------------------------------------------------------------------"
  cat $keydir/$DKIM_SELECTOR.txt
  echo "---------------------------------------------------------------------"

  chown root:root /etc/postfix/additional/opendkim/KeyTable /etc/postfix/additional/opendkim/SigningTable

done
