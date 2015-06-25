#!/bin/bash

set -e

[ "$DEBUG" == "1" ] && set -x && set +e

### Required variables
if [ "${HAPROXY_PASSWORD}" == "**ChangeMe**" -o -z "${HAPROXY_PASSWORD}" ]; then
   HAPROXY_PASSWORD=`pwgen -s 20 1`
fi

sleep 3
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
for domain_cfg in `cat ${DOMAIN_LIST}`; do
  domain=`echo "${domain_cfg}" | awk -F: '{print $1}'`
  domain_port=`echo "${domain_cfg}" | awk -F: '{print $2}'`

  # Get servers for backend
  # If no servers are found, print a warning and continue
  BACKEND_SERVERS=`dig +short ${domain}`
  if [ `echo "${BACKEND_SERVERS}" | grep . | wc -l` -eq 0 ]; then 
    echo "***** WARNING ***** COULD NOT FIND ANY CONTAINER FOR DOMAIN ${domain} - SKIPPING THIS DOMAIN"
    echo "***** WARNING ***** THIS IS A FATAL ERROR IF WP CONTAINERS ALREADY EXIST FOR DOMAIN ${domain}"
    echo "***** WARNING ***** MAYBE YOU DID NOT CREATE THE SERVICE LINKING WITH NAME \"${domain}\"?"
    continue
  fi

  SERVERS_COUNT=0
  for server in ${BACKEND_SERVERS}; do
    SERVERS="${SERVERS}\n\
    server wp${SERVERS_COUNT} ${server}:${domain_port} port ${domain_port} check inter ${HAPROXY_CHECK_INTERVAL} rise ${HAPROXY_CHECK_RISE} fall ${HAPROXY_CHECK_FALL}" 
    PXC_HOSTS_COUNTER=$((PXC_HOSTS_COUNTER+1))
  done

  # Create ACL rules (domain based LB)
  ACL_RULES="${ACL_RULES}\n\
  acl host_${domain} hdr(host) -i ${domain}\n\
  use_backend ${domain} if host_${domain}\n" 

  # Create backend section
  BACKENDS="${BACKENDS}\n\
backend ${domain}\n\
  balance roundrobin\n\
  option forwardfor\n\
  #option httpclose\n\
  http-check disable-on-404\n\
  http-check expect string ${HAPROXY_CHECK_STRING}\n\
  option httpchk GET ${HAPROXY_CHECK} HTTP/1.0\n"

done

# Remove '/' characters
ACL_RULES=`echo "${ACL_RULES}" | sed "s/\//\\\\\\\\\//g"`
BACKENDS=`echo "${BACKENDS}" | sed "s/\//\\\\\\\\\//g"`

if grep "# NOT CONFIGURED" /etc/haproxy/haproxy.cfg >/dev/null; then
  echo "=> Generating HAProxy configuration..."
  # Insert ACLs and Backends
  perl -p -i -e "s/# ACL RULES HERE.*/${ACL_RULES}/g" /etc/haproxy/haproxy.cfg
  perl -p -i -e "s/# BACKENDS HERE.*/${BACKENDS}\n${SERVERS}/g" /etc/haproxy/haproxy.cfg

  # Mark file as configured
  perl -p -i -e "s/# NOT CONFIGURED/# CONFIGURED/g" /etc/haproxy/haproxy.cfg
fi

echo "=> Starting HAProxy..."
/usr/bin/supervisord
