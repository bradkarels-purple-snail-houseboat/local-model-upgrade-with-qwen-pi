#!/usr/bin/env bash
# Stop and remove the sandbox container. Add --purge to also drop its Maven
# cache volume and the built image (keeps your target repo and Ollama models
# untouched either way — those live outside the sandbox).
#
# Usage:
#   ./scripts/teardown.sh [container-name] [--purge]

set -euo pipefail

CONTAINER_NAME="${1:-pi-sandbox}"
PURGE="${2:-}"
IMAGE_NAME="pi-sandbox"

echo "==> Removing container ($CONTAINER_NAME)"
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || echo "    (already gone)"

if [ "$PURGE" = "--purge" ]; then
  echo "==> Removing Maven cache volume and image"
  docker volume rm "${CONTAINER_NAME}-m2" >/dev/null 2>&1 || true
  docker rmi "$IMAGE_NAME" >/dev/null 2>&1 || true
fi

echo "Done."
