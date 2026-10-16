# Debian 12 guest image for floci: stands in for the official Debian 12 AMI.
# Only emulation fixes live here. Everything KTHW needs is installed by the
# workload's user_data, so the same script runs on real AWS and on floci.
FROM debian:12
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus openssh-server sudo curl ca-certificates \
      iproute2 kmod procps e2fsprogs util-linux unzip less \
 && rm -rf /var/lib/apt/lists/* \
 # Baked host keys would be identical on every instance; regenerate per boot.
 && rm -f /etc/ssh/ssh_host_* \
 # The official AMI's default user (cloud-init creates it there).
 && useradd -m -s /bin/bash -G sudo admin \
 && echo 'admin ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-admin && chmod 0440 /etc/sudoers.d/90-admin \
 && passwd -l root
COPY floci-guest-init.sh /usr/local/sbin/floci-guest-init
COPY floci-guest-init.service /etc/systemd/system/
RUN chmod 0755 /usr/local/sbin/floci-guest-init \
 && systemctl enable floci-guest-init.service ssh.service
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
