# Block Pact dedicated server (headless Godot, many rooms per process).
#   docker build -t block-pact-server .
#   docker run --rm block-pact-server --name "Block Pact EU" --max-rooms 20 --min-open 2
FROM ubuntu:24.04

ARG GODOT_VERSION=4.7-stable
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
 && rm -rf /var/lib/apt/lists/* \
 && curl -sSL -o /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" \
 && unzip -q /tmp/godot.zip -d /tmp \
 && mv /tmp/Godot_v${GODOT_VERSION}_linux.x86_64 /usr/local/bin/godot \
 && rm /tmp/godot.zip \
 && useradd -m blockpact

WORKDIR /app
COPY --chown=blockpact . .
USER blockpact
# Import once at build time so the server starts fast.
RUN godot --headless --path . --import || true

ENTRYPOINT ["godot", "--headless", "--path", ".", "res://server/server_main.tscn", "--"]
CMD ["--name", "Block Pact", "--max-rooms", "20", "--min-open", "2"]
