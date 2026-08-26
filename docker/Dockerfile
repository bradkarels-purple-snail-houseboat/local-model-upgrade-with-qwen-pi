# Sandbox for driving a coding agent against a real build, isolated from the host.
#
# Swap the base image for whatever your target project actually needs (JDK version,
# build tool). This one matches a Maven + JDK 17 Spring Boot project. Pi (the coding
# agent) talks to models running on the HOST's Ollama via host.docker.internal — the
# container itself has no model, no GPU access, and no credentials beyond what your
# target project's own test suite needs to run.
FROM maven:3.9-eclipse-temurin-17

RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates git && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent

COPY models.json /root/.pi/agent/models.json

WORKDIR /workspace
