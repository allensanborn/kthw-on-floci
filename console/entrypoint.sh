#!/bin/sh
set -eu
floci=${FLOCI_URL:-http://floci:4566}
# Trust floci's local CA (served over loopback-only HTTP inside the compose network).
curl -fsS "$floci/_floci/ca.pem" -o /etc/pki/ca-trust/source/anchors/floci-local-ca.pem
update-ca-trust
# EC2 Instance Connect Endpoint tunnels: wss://<id>.localhost.floci.io:443 -> floci.
host=${floci#*://}; host=${host%%/*}
socat TCP-LISTEN:443,bind=127.0.0.1,reuseaddr,fork "TCP:$host" &
exec "$@"
