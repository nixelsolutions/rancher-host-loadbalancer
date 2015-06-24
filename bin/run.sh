#!/bin/bash

set -e

[ "$DEBUG" == "1" ] && set -x && set +e

### Required variables
if [ "${HAPROXY_PASSWORD}" == "**ChangeMe**" -o -z "${HAPROXY_PASSWORD}" ]; then
   HAPROXY_PASSWORD=`pwgen -s 20 1`
fi

MY_PUBLIC_IP=`dig -4 @ns1.google.com -t txt o-o.myaddr.l.google.com +short | sed "s/\"//g"`

echo "=> You can access HAProxy stats by browsing to http://${MY_PUBLIC_IP}:${HAPROXY_STATS_PORT}"
echo "=> And authenticating with user \"haproxy\" and password \"${HAPROXY_PASSWORD}\"" 

### Replace haproxy env vars
perl -p -i -e "s/HAPROXY_MAXCONN/${HAPROXY_MAXCONN}/g" /etc/haproxy/haproxy.cfg
perl -p -i -e "s/HAPROXY_TIMEOUT_CONNECT/${HAPROXY_TIMEOUT_CONNECT}/g" /etc/haproxy/haproxy.cfg
perl -p -i -e "s/HAPROXY_TIMEOUT_SERVER/${HAPROXY_TIMEOUT_SERVER}/g" /etc/haproxy/haproxy.cfg
perl -p -i -e "s/HAPROXY_TIMEOUT_CLIENT/${HAPROXY_TIMEOUT_CLIENT}/g" /etc/haproxy/haproxy.cfg
perl -p -i -e "s/HAPROXY_HTTP_PORT/${HAPROXY_HTTP_PORT}/g" /etc/haproxy/haproxy.cfg
perl -p -i -e "s/HAPROXY_STATS_PORT/${HAPROXY_STATS_PORT}/g" /etc/haproxy/haproxy.cfg
perl -p -i -e "s/HAPROXY_PASSWORD/${HAPROXY_PASSWORD}/g" /etc/haproxy/haproxy.cfg

### Configure haproxy
perl -p -i -e "s/ENABLED=0/ENABLED=1/g" /etc/default/haproxy 

# Configure all domains
ACL_RULES="# ACL RULES HERE"
BACKENDS="# BACKENDS HERE"
for domain in `cat ${DOMAIN_LIST}`; do

   ACL_RULES="${ACL_RULES}\n\
  acl host_${domain} hdr(host) -i ${domain}\n\
  use_backend ${domain} if host_${domain}\n" 

   BACKENDS="${BACKENDS}\n\
backend ${domain}\n\
  balance roundrobin\n\
  option forwardfor\n\
  #option httpclose\n\
  http-check disable-on-404\n\
  http-check expect string ${HAPROXY_CHECK_STRING}\n\
  option httpchk GET ${HAPROXY_CHECK} HTTP/1.0\n\
  \n\
  server prodfbk06 10.110.4.135:18021 port 18021 check inter 2000 rise 2 fall 3\n"

done

# Remove '/' characters
ACL_RULES=`echo "${ACL_RULES}" | sed "s/\//\\\\\\\\\//g"`
BACKENDS=`echo "${BACKENDS}" | sed "s/\//\\\\\\\\\//g"`

if grep "# NOT CONFIGURED" /etc/haproxy/haproxy.cfg >/dev/null; then
  echo "=> Generating HAProxy configuration..."
  # Insert ACLs and Backends
  perl -p -i -e "s/# ACL RULES HERE.*/${ACL_RULES}/g" /etc/haproxy/haproxy.cfg
  perl -p -i -e "s/# BACKENDS HERE.*/${BACKENDS}/g" /etc/haproxy/haproxy.cfg

  # Mark file as configured
  perl -p -i -e "s/# NOT CONFIGURED/# CONFIGURED/g" /etc/haproxy/haproxy.cfg
fi

echo "=> Starting HAProxy..."
/usr/bin/supervisord
