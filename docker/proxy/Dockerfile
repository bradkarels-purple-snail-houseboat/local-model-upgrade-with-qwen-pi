# Egress gateway for the sandbox: the ONLY container with a route to the
# host or the open internet. The sandbox container itself sits on an
# `--internal` Docker network with no default route at all — it can reach
# nothing except this gateway. Built from Ubuntu's own apt archive rather
# than a third-party Squid image, so the whole egress boundary is auditable
# from source in this repo instead of trusting someone else's published image.
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
      squid socat ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY squid.conf /etc/squid/squid.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3128 11434

ENTRYPOINT ["/entrypoint.sh"]
