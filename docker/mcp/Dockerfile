# MCP bridge for the headless Craft apps.
#   Craft CLIs      storytold/<app> Linux releases, pinned by checksum in apps.lock.json
#   command bridge  xiewg1987/artcraft-command-bridge (MIT): 5 MCP tools in front of every CLI
#   supergateway    supercorp-ai/supergateway (MIT): stdio MCP -> Streamable HTTP
ARG NODE_IMAGE=node:22.23.3-bookworm-slim
FROM ${NODE_IMAGE}

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git fontconfig fonts-dejavu-core fonts-liberation2 \
 && rm -rf /var/lib/apt/lists/*

ARG BRIDGE_REPO=https://github.com/xiewg1987/artcraft-command-bridge.git
ARG BRIDGE_SHA=02a72c07a047a74e02565cca1b6822f0998e866c
RUN git clone "${BRIDGE_REPO}" /opt/bridge \
 && git -C /opt/bridge checkout --detach "${BRIDGE_SHA}" \
 && test "$(git -C /opt/bridge rev-parse HEAD)" = "${BRIDGE_SHA}" \
 && rm -rf /opt/bridge/.git

ARG SUPERGATEWAY_VERSION=4.2.2
RUN npm install -g --no-fund --no-audit "supergateway@${SUPERGATEWAY_VERSION}" && npm cache clean --force

# Space-separated app ids from apps.lock.json.
ARG MCP_APPS="photocraft vectorcraft designcraft deckcraft pdfcraft"
COPY apps.lock.json install-apps.js /opt/install/
RUN node /opt/install/install-apps.js ${MCP_APPS}

# Unprivileged, with nothing writable except what compose mounts.
RUN useradd --uid 10001 --user-group --no-create-home --home-dir /tmp craft
USER 10001:10001
WORKDIR /work
ENV HOME=/tmp \
    ARTCRAFT_CACHE_DIR=/tmp/artcraft-cache \
    NODE_ENV=production
EXPOSE 8000
CMD ["supergateway", "--stdio", "node /opt/bridge/server.js", "--outputTransport", "streamableHttp", "--stateful", "--sessionTimeout", "900000", "--port", "8000", "--healthEndpoint", "/healthz", "--logLevel", "info"]
