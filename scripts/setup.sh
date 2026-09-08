#!/usr/bin/env bash
# Build the sandbox image, pull the local models via Ollama, and start the
# container behind a network-allowlisted gateway.
#
# Network shape:
#   pi-sandbox        -- on an --internal Docker network only. No default
#                         route at all: it cannot reach the host or the
#                         internet directly, only the gateway below.
#   <name>-gateway     -- the only container attached to BOTH the internal
#                         network and a normal (egress-capable) network.
#                         Forwards the host's Ollama port in, and proxies
#                         HTTP(S) out through a Squid allowlist (see
#                         docker/proxy/squid.conf) -- everything not on that
#                         list gets a 403, not a silent hang.
#
# Prerequisites:
#   - Docker Desktop (or another engine that provides host.docker.internal)
#   - Ollama installed and running on the HOST (https://ollama.com) — the
#     container never touches the model weights directly, it calls the
#     host's Ollama API through the gateway.
#   - A clone of the project you want to migrate, on the branch/commit you
#     want to start from.
#
# Usage:
#   ./scripts/setup.sh /path/to/target-repo [container-name]

set -euo pipefail

TARGET_REPO="${1:?Usage: setup.sh /path/to/target-repo [container-name]}"
CONTAINER_NAME="${2:-pi-sandbox}"
IMAGE_NAME="pi-sandbox"
GATEWAY_IMAGE_NAME="pi-sandbox-gateway"
GATEWAY_NAME="${CONTAINER_NAME}-gateway"
GATEWAY_ALIAS="sandbox-gateway"
NET_INTERNAL="${CONTAINER_NAME}-internal"
NET_EGRESS="${CONTAINER_NAME}-egress"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Pulling models via Ollama (skips any already present)"
for model in qwen3-coder:30b-a3b-q4_K_M qwen3.6:27b-q4_K_M devstral:24b; do
  ollama pull "$model"
done

echo "==> Building sandbox image ($IMAGE_NAME)"
docker build -t "$IMAGE_NAME" "$SCRIPT_DIR/../docker"

echo "==> Building gateway image ($GATEWAY_IMAGE_NAME)"
docker build -t "$GATEWAY_IMAGE_NAME" "$SCRIPT_DIR/../docker/proxy"

echo "==> Creating networks ($NET_EGRESS, $NET_INTERNAL)"
docker network inspect "$NET_EGRESS" >/dev/null 2>&1 || docker network create "$NET_EGRESS" >/dev/null
docker network inspect "$NET_INTERNAL" >/dev/null 2>&1 || docker network create --internal "$NET_INTERNAL" >/dev/null

echo "==> Starting gateway ($GATEWAY_NAME)"
docker rm -f "$GATEWAY_NAME" >/dev/null 2>&1 || true
docker run -d \
  --name "$GATEWAY_NAME" \
  --network "$NET_EGRESS" \
  --add-host=host.docker.internal:host-gateway \
  "$GATEWAY_IMAGE_NAME" >/dev/null
docker network connect --alias "$GATEWAY_ALIAS" "$NET_INTERNAL" "$GATEWAY_NAME"
GATEWAY_INTERNAL_IP="$(docker inspect -f "{{(index .NetworkSettings.Networks \"$NET_INTERNAL\").IPAddress}}" "$GATEWAY_NAME")"

echo "==> Starting sandbox container ($CONTAINER_NAME), bind-mounting $TARGET_REPO at /workspace"
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
docker run -d \
  --name "$CONTAINER_NAME" \
  --network "$NET_INTERNAL" \
  --add-host="host.docker.internal:${GATEWAY_INTERNAL_IP}" \
  -e http_proxy="http://${GATEWAY_ALIAS}:3128" -e https_proxy="http://${GATEWAY_ALIAS}:3128" \
  -e HTTP_PROXY="http://${GATEWAY_ALIAS}:3128" -e HTTPS_PROXY="http://${GATEWAY_ALIAS}:3128" \
  -e no_proxy="${GATEWAY_ALIAS},host.docker.internal" -e NO_PROXY="${GATEWAY_ALIAS},host.docker.internal" \
  -v "$TARGET_REPO":/workspace \
  -v "${CONTAINER_NAME}-m2":/root/.m2 \
  -v "$SCRIPT_DIR/../docker/models.json":/root/.pi/agent/models.json:ro \
  -v "$SCRIPT_DIR/../docker/maven-settings.xml":/root/.m2/settings.xml:ro \
  "$IMAGE_NAME" \
  sleep infinity

echo "==> Verifying the sandbox can reach Ollama through the gateway"
docker exec "$CONTAINER_NAME" curl -fsS "http://host.docker.internal:11434/api/tags" >/dev/null \
  && echo "    OK" \
  || echo "    FAILED — is Ollama running on the host?"

echo "==> Verifying the allowlist: Maven Central reachable, an arbitrary domain is NOT"
docker exec "$CONTAINER_NAME" curl -fsS -m 5 https://repo.maven.apache.org/maven2/ >/dev/null \
  && echo "    Maven Central: OK (allowed)" \
  || echo "    Maven Central: FAILED — check docker/proxy/squid.conf and gateway logs (docker logs $GATEWAY_NAME)"
if docker exec "$CONTAINER_NAME" curl -fsS -m 5 https://example.com >/dev/null 2>&1; then
  echo "    Arbitrary domain (example.com): REACHABLE — allowlist is NOT enforcing, investigate before trusting this boundary"
else
  echo "    Arbitrary domain (example.com): blocked (expected)"
fi

cat <<EOF

Ready. Start a session with, e.g.:

  docker exec -it -w /workspace $CONTAINER_NAME \\
    pi --provider ollama --model qwen3.6:27b-q4_K_M --approve

Remember: if you edit docker/models.json or docker/maven-settings.xml after
this point, you must recreate the container (this script again, or
'docker rm -f $CONTAINER_NAME' + rerun) — Docker bind-mounts a single file by
inode, and most editors save by write-new-plus-rename, which silently
orphans the mount.

To allow another destination (e.g. your org's own Artifactory/Nexus instead
of public Maven Central/npm), add it to docker/proxy/squid.conf and rerun
this script — it rebuilds the gateway image each time.
EOF
