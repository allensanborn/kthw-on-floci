# Debian 12 with systemd as PID 1: the minimum a floci "systemd guest" AMI needs.
FROM debian:12
RUN apt-get update && apt-get install -y --no-install-recommends systemd systemd-sysv dbus iproute2 curl ca-certificates kmod procps \
 && rm -rf /var/lib/apt/lists/*
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
