#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
APP_DIR=$(pwd)

# Start command runs as the "zerops" user (not root) -> keep certs in a folder we own
CERTS="$APP_DIR/.omcerts"
mkdir -p "$CERTS/server" "$CERTS/client"
chmod 700 "$CERTS"
dec() { printf '%s' "$1" | base64 -d > "$2"; }
dec "$DOCKER_CA_B64"          "$CERTS/server/ca.pem"
dec "$DOCKER_SERVER_CERT_B64" "$CERTS/server/server-cert.pem"
dec "$DOCKER_SERVER_KEY_B64"  "$CERTS/server/server-key.pem"
cp "$CERTS/server/ca.pem"     "$CERTS/client/ca.pem"
dec "$DOCKER_CLIENT_CERT_B64" "$CERTS/client/cert.pem"
dec "$DOCKER_CLIENT_KEY_B64"  "$CERTS/client/key.pem"
chmod 600 "$CERTS"/*/*.pem
echo "[computer] certs written to $CERTS"

# Helper: run docker against the INNER engine (TLS). Plain `docker` = outer VM engine.
inner() {
  DOCKER_HOST=tcp://127.0.0.1:2376 DOCKER_TLS_VERIFY=1 DOCKER_CERT_PATH="$CERTS/client" docker "$@"
}

# 1) Build the computer image on the OUTER engine (has internet)
docker build -t openmuse-computer:local ./apps/computer
echo "[computer] image built on outer engine"

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
echo "[computer] inner engine started"

# 3) Wait for the inner engine
i=0
until inner version >/dev/null 2>&1; do
  i=$((i+1))
  if [ "$i" -ge 60 ]; then
    echo "[computer] inner engine not reachable"; docker logs --tail 50 omdind || true; exit 1
  fi
  sleep 2
done
echo "[computer] inner engine reachable"

# 4) Copy image: save from OUTER, load into INNER
docker save openmuse-computer:local | inner load
inner image inspect openmuse-computer:local >/dev/null
echo "[computer] ready on :2376 (image loaded)"

exec docker logs -f omdind
