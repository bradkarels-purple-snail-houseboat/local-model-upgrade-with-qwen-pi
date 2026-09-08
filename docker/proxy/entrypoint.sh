#!/bin/sh
# Runs two things in this one gateway container:
#   1. A raw TCP forward of the host's Ollama port onto this container's
#      internal-network address, so the sandbox (which has no route to the
#      host at all) can still reach Ollama without needing host.docker.internal
#      itself to be exposed to it.
#   2. Squid, providing the domain-allowlisted HTTP(S) proxy for everything
#      else (Maven, npm).
# This container is the only thing attached to both the internal (sandbox)
# network and the egress (host + internet) network — it's the sole gateway.
set -eu

OLLAMA_PORT="${OLLAMA_PORT:-11434}"

socat "TCP-LISTEN:${OLLAMA_PORT},fork,reuseaddr" "TCP:host.docker.internal:${OLLAMA_PORT}" &

# Squid drops privileges to its unprivileged cache_effective_user, which
# can't write to /dev/stdout directly — so it logs to a real file and we
# tail that onto this container's stdout, which also gives `docker logs`
# a live record of every request the sandbox made (allowed or denied).
mkdir -p /var/log/squid && chown proxy:proxy /var/log/squid
touch /var/log/squid/access.log && chown proxy:proxy /var/log/squid/access.log
tail -F /var/log/squid/access.log &

exec squid -N -d 1
