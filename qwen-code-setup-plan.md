# Plan: Qwen Code + Ollama (qwen3-coder:30b) + Docker Sandbox

Goal: swap Pi for Qwen Code as the harness, reusing the existing Ollama
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

Node isn't needed on the host for this plan — Qwen Code runs inside the
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

## 1. Install Qwen Code inside the container

The container isn't rebuilt with Qwen Code baked in — installed straight
into the running container, same as you'd do on a host:

```bash
docker exec pi-sandbox npm install -g --ignore-scripts @qwen-code/qwen-code@latest
docker exec pi-sandbox qwen --version
```

**Note:** a plain `npm install -g` inside the container does **not**
survive `teardown.sh` / `docker rm`. If you tear the container down and
bring it back up, re-run this step. If you want it to persist across
recreations, add the same `RUN npm install -g ...` line to
`docker/Dockerfile` and rebuild the image instead.

## 2. Point it at the host's Ollama

Qwen Code reads env vars from `~/.qwen/.env` (global) or `.qwen/.env`
(project-local). Inside the container, "the host" is
`host.docker.internal`, not `localhost` — this is the one setting that
actually changes versus running Qwen Code directly on the host.

```bash
docker exec pi-sandbox mkdir -p /root/.qwen
docker exec pi-sandbox bash -c 'cat > /root/.qwen/.env << "EOF"
OPENAI_API_KEY=not-needed-for-local
OPENAI_BASE_URL=http://host.docker.internal:11434/v1
OPENAI_MODEL=qwen3-coder:30b
EOF'
```

**Gotcha:** don't rely on the `modelProviders` block in `settings.json`
for this — there are open reports of it being silently ignored on recent
versions, forcing you back to the OAuth/API-key picker on launch. The
`.env` + `OPENAI_*` var approach above is the reliably-working path as of
mid-2026.

**Gotcha:** on first launch, `qwen` will prompt you to choose an auth
method (Alibaba Model Studio / API Key / Qwen OAuth). Pick **API Key** —
picking OAuth will route you to Alibaba's cloud regardless of your env
vars, and you'll get inexplicable 401s or requests silently leaving your
machine.

Verify the URL has the trailing `/v1` — a very common cause of the CLI
falling back to a picker or throwing opaque errors.

## 3. (Optional) Project system prompt

This lives in the target repo itself, so it's already visible at
`/workspace` inside the container — no container-specific step needed:

```bash
mkdir -p .qwen
cat > .qwen/QWEN.md << 'EOF'
# Project instructions for Qwen Code
(add your house rules / conventions here)
EOF
```

## 4. Launch it inside the sandbox

Qwen Code ships its *own* sandbox mode (`qwen --sandbox`, which runs
tool execution inside a nested Docker/Podman container) — skip it here,
since the outer `pi-sandbox` container is already doing that job; a
container inside a container just adds overhead for no extra isolation.

```bash
docker exec -it -w /workspace pi-sandbox qwen
```

Isolation here comes from the container boundary itself: the process
only sees `/workspace` (your target repo) and whatever else is mounted
in `scripts/setup.sh` — no access to your host filesystem, `~/.ssh`, or
other credentials unless you explicitly bind-mount them in.

## 5. Smoke test

```bash
docker exec pi-sandbox mkdir -p /tmp/qwen-test
docker exec pi-sandbox bash -c 'cd /tmp/qwen-test && git init -q && echo hello > README.md'
docker exec -it -w /tmp/qwen-test pi-sandbox qwen
```

Inside the session, confirm:
1. It can read/edit files inside `/tmp/qwen-test`
2. It **cannot** read anything on your actual host filesystem outside
   what `scripts/setup.sh` bind-mounted (there's no host `/`, `~/.ssh`,
   etc. inside the container at all — ask it to `cat /etc/passwd` from
   the host vs. the container's own if you want to see the boundary)
3. `curl http://host.docker.internal:11434/api/tags` succeeds from
   inside the session (confirms it can still reach Ollama)

## 6. Known rough edges to watch for

- `settings.json` is strict about schema — a malformed edit gets silently
  renamed to `settings.json.corrupted` rather than erroring loudly. Prefer
  editing `.env` over hand-editing `settings.json` where possible.
- If you ever see 401s despite local-only config, check for a stale
  `OPENAI_BASE_URL`/`OPENAI_API_KEY` exported in the container's shell
  profile — exported env vars win over `.env` file values.
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
