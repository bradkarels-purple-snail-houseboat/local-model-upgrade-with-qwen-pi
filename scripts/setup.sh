#!/usr/bin/env bash
# Build the sandbox image, pull the local models via Ollama, and start the container.
#
# Prerequisites:
#   - Docker Desktop (or another engine that provides host.docker.internal)
#   - Ollama installed and running on the HOST (https://ollama.com) — the container
#     never touches the model weights directly, it calls the host's Ollama API.
#   - A clone of the project you want to migrate, on the branch/commit you want to
#     start from.
#
# Usage:
#   ./scripts/setup.sh /path/to/target-repo [container-name]

set -euo pipefail

TARGET_REPO="${1:?Usage: setup.sh /path/to/target-repo [container-name]}"
CONTAINER_NAME="${2:-pi-sandbox}"
IMAGE_NAME="pi-sandbox"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Pulling models via Ollama (skips any already present)"
for model in qwen3-coder:30b-a3b-q4_K_M qwen3.6:27b-q4_K_M devstral:24b; do
  ollama pull "$model"
done

echo "==> Building sandbox image ($IMAGE_NAME)"
docker build -t "$IMAGE_NAME" "$SCRIPT_DIR/../docker"

echo "==> Starting container ($CONTAINER_NAME), bind-mounting $TARGET_REPO at /workspace"
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
docker run -d \
  --name "$CONTAINER_NAME" \
  -v "$TARGET_REPO":/workspace \
  -v "${CONTAINER_NAME}-m2":/root/.m2 \
  -v "$SCRIPT_DIR/../docker/models.json":/root/.pi/agent/models.json:ro \
  "$IMAGE_NAME" \
  sleep infinity

echo "==> Verifying the container can reach the host's Ollama"
docker exec "$CONTAINER_NAME" curl -fsS http://host.docker.internal:11434/api/tags >/dev/null \
  && echo "    OK" \
  || echo "    FAILED — is Ollama running on the host?"

cat <<EOF

Ready. Start a session with, e.g.:

  docker exec -it -w /workspace $CONTAINER_NAME \\
    pi --provider ollama --model qwen3.6:27b-q4_K_M --approve

Remember: if you edit docker/models.json after this point, you must recreate the
container (this script again, or 'docker rm -f $CONTAINER_NAME' + rerun) — Docker
bind-mounts a single file by inode, and most editors save by write-new-plus-rename,
which silently orphans the mount.
EOF
