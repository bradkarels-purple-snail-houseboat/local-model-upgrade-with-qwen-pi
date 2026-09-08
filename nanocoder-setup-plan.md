# Plan: Nanocoder + Ollama (qwen3-coder:30b) + Docker Sandbox

Goal: swap Pi for Nanocoder as the harness, reusing the existing Ollama
server and `qwen3-coder:30b` model, and reusing this repo's own Docker
sandbox (`pi-sandbox`, built by `scripts/setup.sh`) instead of a
third-party Seatbelt wrapper. No new trust dependency, no second
isolation mechanism to reason about — same container, different agent.

## 0. Prerequisites (should already be true)

- [ ] Ollama running on the **host** and serving the model:
  ```bash
  ollama list | grep qwen3-coder
  curl -s http://localhost:11434/api/tags | grep qwen3-coder
  ```
- [ ] Docker running

Node isn't needed on the host for this plan — Nanocoder runs inside the
sandbox container, which already has Node 22 (see `docker/Dockerfile`).

### 0.1 Make sure the sandbox container is up

If you haven't already started it for this target repo:

```bash
./scripts/setup.sh /path/to/your/target-repo
```

Otherwise just confirm it's running:

```bash
docker ps --filter name=pi-sandbox
```

Everything below assumes a running container named `pi-sandbox` with
your target repo bind-mounted at `/workspace`.

## 1. Install Nanocoder inside the container

The container isn't rebuilt with Nanocoder baked in — installed straight
into the running container, same as you'd do on a host:

```bash
docker exec pi-sandbox npm install -g --ignore-scripts @nanocollective/nanocoder
docker exec pi-sandbox nanocoder --version
```

**Gotcha:** there are several unofficial forks/clones floating around
under similar names (`@motesoftware/nanocoder` and plain GitHub forks).
Make sure it's `@nanocollective/nanocoder` specifically — that's the
Nano Collective's own package.

**Note:** a plain `npm install -g` inside the container does **not**
survive `teardown.sh` / `docker rm`. If you tear the container down and
bring it back up, re-run this step. If you want it to persist across
recreations, add the same `RUN npm install -g ...` line to
`docker/Dockerfile` and rebuild the image instead.

## 2. Point it at the host's Ollama

Nanocoder auto-detects local Ollama models with no config file needed —
you can just launch it against the model directly. Inside the container,
"the host" is `host.docker.internal`, not `localhost`:

```bash
docker exec -it -w /workspace pi-sandbox \
  nanocoder --provider ollama --base-url http://host.docker.internal:11434 --model qwen3-coder:30b
```

For a persistent default so you don't have to pass flags every time,
drop a config in the target repo (visible at `/workspace` in the
container automatically):

```bash
cat > agents.config.json << 'EOF'
{
  "nanocoder": {
    "openAICompatible": {
      "baseUrl": "http://host.docker.internal:11434",
      "apiKey": "not-needed-for-local",
      "models": ["qwen3-coder:30b"]
    }
  }
}
EOF
```

## 3. Use Nanocoder's built-in permission modes

Unlike Pi, Nanocoder ships **native** permission gating via `--mode`:

| Mode | Behavior |
|---|---|
| `plan` | read-only, no writes/execution |
| `normal` (default) | prompts per tool call |
| `auto-accept` | accepts tool calls without prompting |
| `yolo` | allows everything except hard-denied actions |

```bash
# Safe first run — read-only
docker exec -it -w /workspace pi-sandbox \
  nanocoder --provider ollama --model qwen3-coder:30b --mode plan

# Normal day-to-day use — still gated
docker exec -it -w /workspace pi-sandbox \
  nanocoder --provider ollama --model qwen3-coder:30b --mode normal
```

This is a real gate on top of the harness itself, not just the sandbox —
worth using `normal` or `plan` even inside the container below, and
reserving `yolo` for cases where you're doubly sure the container
boundary is doing its job (since the container is what actually
enforces the boundary if the harness's own gate is bypassed or
misconfigured).

## 4. Launch it inside the sandbox

```bash
docker exec -it -w /workspace pi-sandbox \
  nanocoder --provider ollama --model qwen3-coder:30b --mode normal
```

Isolation here comes from the container boundary itself: the process
only sees `/workspace` (your target repo) and whatever else is mounted
in `scripts/setup.sh` — no access to your host filesystem, `~/.ssh`, or
other credentials unless you explicitly bind-mount them in.

## 5. Smoke test

```bash
docker exec pi-sandbox mkdir -p /tmp/nanocoder-test
docker exec pi-sandbox bash -c 'cd /tmp/nanocoder-test && git init -q && echo hello > README.md'
docker exec -it -w /tmp/nanocoder-test pi-sandbox \
  nanocoder --provider ollama --model qwen3-coder:30b --mode normal
```

Inside the session, confirm:
1. It can read/edit files inside `/tmp/nanocoder-test`
2. It **cannot** read anything on your actual host filesystem outside
   what `scripts/setup.sh` bind-mounted (there's no host `/`, `~/.ssh`,
   etc. inside the container at all)
3. `--mode normal` actually prompts you before it runs a bash command or
   writes a file (this is the harness-level gate working, separate from
   the container-level boundary)
4. `curl http://host.docker.internal:11434/api/tags` succeeds from
   inside the session (confirms it can still reach Ollama)

## 6. Known rough edges to watch for

- Some tutorials online still reference the config format from an older
  fork (`gmh5225/nanocoder`, `@motesoftware/nanocoder`) — their config
  schema is similar but not guaranteed identical to the official
  Nano Collective package. If a config example doesn't work, check which
  repo it came from.
- Documentation is at `docs.nanocollective.org` — check there over
  README snippets you find elsewhere, since this project moves fast and
  README copies get stale quickly.
- **Network egress is allowlisted**, closing the gap noted in an earlier
  draft of this plan. `pi-sandbox` now sits on an `--internal` Docker
  network with no default route at all — it can only reach
  `pi-sandbox-gateway`, the sole container bridged to the host and the
  internet. That gateway forwards Ollama's port straight through, and
  proxies all other HTTP(S) through Squid against an explicit domain
  allowlist (`docker/proxy/squid.conf`) — anything not on it gets a 403.
  `registry.npmjs.org` is already on the list (needed for step 1 above);
  add your org's own package mirror there too if you use one instead of
  the public registry.
- `docker exec pi-sandbox npm install -g ...` doesn't survive
  `teardown.sh` / container recreation — see the note in step 1.
