#!/bin/sh
# Wait until first boot has finished: the jumpbox holds verified host keys for every
# machine and can SSH to each as root (KTHW lab 3's starting point). Up to 10 minutes.
here=$(dirname "$0")
echo "waiting for the machines to finish first boot..."
i=0
until "$here/on-jumpbox.sh" '
  test -s /root/.ssh/known_hosts || exit 1
  while read -r ip fqdn host _; do ssh -n -o BatchMode=yes -o ConnectTimeout=5 root@$ip true || exit 1; done < /root/machines.txt
' >/dev/null 2>&1; do
  i=$((i + 1)); [ $i -lt 40 ] || { echo "machines not ready after 10 minutes; see /var/log/kthw-user-data.log on each" >&2; exit 1; }
  sleep 15
done
echo "ready: mise run connect, then start KTHW at lab 2"
