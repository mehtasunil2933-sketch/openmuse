#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

CERTS=/opt/omcerts
mkdir -p "$CERTS/server" "$CERTS/client"
dec() { printf '%s' "$1" | base64 -d > "$2"; }
dec "$DOCKER_CA_B64"          "$CERTS/server/ca.pem"
dec "$DOCKER_SERVER_CERT_B64" "$CERTS/server/server-cert.pem"
dec "$DOCKER_SERVER_KEY_B64"  "$CERTS/server/server-key.pem"
cp "$CERTS/server/ca.pem"     "$CERTS/client/ca.pem"
dec "$DOCKER_CLIENT_CERT_B64" "$CERTS/client/cert.pem"
dec "$DOCKER_CLIENT_KEY_B64"  "$CERTS/client/key.pem"
chmod 600 "$CERTS"/*/*.pem

# 1) Build the computer image on the VM's own engine (has internet)
docker build -t openmuse-computer:local ./apps/computer

# 2) Inner Docker engine that only accepts clients with your certificate
docker rm -f omdind >/dev/null 2>&1 || true
docker run -d --name omdind --privileged --network=host --restart unless-stopped \
  -e DOCKER_TLS_CERTDIR= \
  -v omdind-data:/var/lib/docker \
  -v "$CERTS/server":/certs:ro \
  docker:27.5.1-dind \
  --host=tcp://0.0.0.0:2376 --tlsverify \
  --tlscacert=/certs/ca.pem --tlscert=/certs/server-cert.pem --tlskey=/certs/server-key.pem \
  --bridge=none --iptables=false

# 3) Wait, then copy the image into the inner engine
export DOCKER_HOST=tcp://127.0.0.1:2376 DOCKER_TLS_VERIFY=1 DOCKER_CERT_PATH="$CERTS/client"
i=0; until docker version >/dev/null 2>&1; do i=$((i+1)); [ "$i" -ge 60 ] && exit 1; sleep 2; done
docker save openmuse-computer:local | docker load
unset DOCKER_HOST DOCKER_TLS_VERIFY DOCKER_CERT_PATH

exec docker logs -f omdind
