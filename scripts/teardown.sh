#!/usr/bin/env bash
# Stop and remove the sandbox container, its gateway, and their networks.
# Add --purge to also drop its Maven cache volume and the built images
# (keeps your target repo and Ollama models untouched either way — those
# live outside the sandbox).
#
# Usage:
#   ./scripts/teardown.sh [container-name] [--purge]

set -euo pipefail

CONTAINER_NAME="${1:-pi-sandbox}"
PURGE="${2:-}"
IMAGE_NAME="pi-sandbox"
GATEWAY_IMAGE_NAME="pi-sandbox-gateway"
GATEWAY_NAME="${CONTAINER_NAME}-gateway"
NET_INTERNAL="${CONTAINER_NAME}-internal"
NET_EGRESS="${CONTAINER_NAME}-egress"

echo "==> Removing containers ($CONTAINER_NAME, $GATEWAY_NAME)"
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || echo "    ($CONTAINER_NAME already gone)"
docker rm -f "$GATEWAY_NAME" >/dev/null 2>&1 || echo "    ($GATEWAY_NAME already gone)"

echo "==> Removing networks ($NET_INTERNAL, $NET_EGRESS)"
docker network rm "$NET_INTERNAL" >/dev/null 2>&1 || true
docker network rm "$NET_EGRESS" >/dev/null 2>&1 || true

if [ "$PURGE" = "--purge" ]; then
  echo "==> Removing Maven cache volume and images"
  docker volume rm "${CONTAINER_NAME}-m2" >/dev/null 2>&1 || true
  docker rmi "$IMAGE_NAME" >/dev/null 2>&1 || true
  docker rmi "$GATEWAY_IMAGE_NAME" >/dev/null 2>&1 || true
fi

echo "Done."
