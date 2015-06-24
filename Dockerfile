FROM ubuntu:14.04

MAINTAINER Manel Martinez <manel@nixelsolutions.com>

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y supervisor haproxy dnsutils pwgen

ENV HAPROXY_PASSWORD **ChangeMe**
ENV HAPROXY_MAXCONN 60000
ENV HAPROXY_TIMEOUT_CONNECT 5000
ENV HAPROXY_TIMEOUT_SERVER 50000
ENV HAPROXY_TIMEOUT_CLIENT 50000
ENV HAPROXY_HTTP_PORT 80
ENV HAPROXY_STATS_PORT 1936
ENV HAPROXY_CHECK_STRING OK
ENV HAPROXY_CHECK /healthcheck.txt
ENV DOMAIN_LIST /etc/domain_list.txt
ENV DEBUG 0

EXPOSE ${HAPROXY_HTTP_PORT}
EXPOSE ${HAPROXY_STATS_PORT}

RUN mkdir -p /var/log/supervisor

RUN mkdir -p /usr/local/bin
ADD ./bin /usr/local/bin
RUN chmod +x /usr/local/bin/*.sh
ADD ./etc/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
ADD ./etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg
ADD ./etc/domain_list.txt ${DOMAIN_LIST}

CMD ["/usr/local/bin/run.sh"]
