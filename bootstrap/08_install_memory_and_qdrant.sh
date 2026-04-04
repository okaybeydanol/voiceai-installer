#!/usr/bin/env bash
# ==============================================================================
# 08_install_memory_and_qdrant.sh
#
# Responsibility:
#   §9.5  Qdrant binary (pinned version, musl static build)
#         Qdrant config.yaml (loopback-only: 127.0.0.1)
#         bin/start-qdrant.sh
#         Qdrant health check (non-fatal, systemd manages lifecycle)
#
# Qdrant is the memory backbone (v4).
# All ports loopback-only. gRPC 6334 also loopback-only.
# Collections (voiceai_episodic, voiceai_facts, voiceai_chunks)
# are created by agent/src/memory.py on first agent start.
# ==============================================================================
set -euo pipefail
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$BOOTSTRAP_DIR/00_shared_helpers.sh"

ROOT="${ROOT:-$HOME/ai-projects/voiceai}"
QDRANT_VERSION="${QDRANT_VERSION:-1.13.4}"
PORT_QDRANT_REST="${PORT_QDRANT_REST:-6333}"
PORT_QDRANT_GRPC="${PORT_QDRANT_GRPC:-6334}"

QDRANT_DIR="$ROOT/memory"
QDRANT_BIN="$ROOT/bin/qdrant"
QDRANT_DATA="$ROOT/memory/qdrant"
QDRANT_CFG="$QDRANT_DIR/config.yaml"

# ==============================================================================
# §9.5 — QDRANT BINARY
# ==============================================================================
_banner "08 / QDRANT — Binary"

_step "Qdrant binary"
NEEDS_QDRANT_DL=true
if [ -f "$QDRANT_BIN" ]; then
  QD_VER="$("$QDRANT_BIN" --version 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo '0')"
  [ "$QD_VER" = "$QDRANT_VERSION" ] \
    && { NEEDS_QDRANT_DL=false; _skip "qdrant v$QDRANT_VERSION already present"; }
fi

if [ "$NEEDS_QDRANT_DL" = true ]; then
  QD_ARCHIVE="qdrant-x86_64-unknown-linux-musl.tar.gz"
  QD_URL="https://github.com/qdrant/qdrant/releases/download/v${QDRANT_VERSION}/${QD_ARCHIVE}"
  wget -q --show-progress "$QD_URL" -O "$QDRANT_DIR/qdrant.tar.gz"
  tar -xzf "$QDRANT_DIR/qdrant.tar.gz" -C "$QDRANT_DIR" qdrant
  rm -f "$QDRANT_DIR/qdrant.tar.gz"
  mv "$QDRANT_DIR/qdrant" "$QDRANT_BIN"
  chmod +x "$QDRANT_BIN"
  _ok "qdrant v$QDRANT_VERSION downloaded"
fi

# ==============================================================================
# §9.5 — QDRANT CONFIG (loopback-only)
# ==============================================================================
_banner "08 / QDRANT — config.yaml"

mkdir -p "$QDRANT_DATA"
cat > "$QDRANT_CFG" <<CFG
storage:
  storage_path: ${QDRANT_DATA}

service:
  host: 127.0.0.1
  http_port: ${PORT_QDRANT_REST}
  grpc_port: ${PORT_QDRANT_GRPC}
  enable_static_content: false

log_level: INFO
CFG
_ok "Qdrant config.yaml written (loopback: 127.0.0.1:${PORT_QDRANT_REST})"

# ==============================================================================
# §9.5 — START SCRIPT
# ==============================================================================
_banner "08 / QDRANT — start script"

cat > "$ROOT/bin/start-qdrant.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
. "$HOME/.config/voiceai/env.sh"
cd "$VOICEAI_ROOT/memory"
echo "[QDRANT] Starting on 127.0.0.1:6333 …"
exec "$VOICEAI_ROOT/bin/qdrant" --config-path ./config.yaml
SCRIPT
chmod +x "$ROOT/bin/start-qdrant.sh"
_ok "bin/start-qdrant.sh written"

# ==============================================================================
# §9.5 — HEALTH CHECK (informational, non-fatal)
# ==============================================================================
_step "Qdrant health check (informational)"
if curl -fsS --max-time 3 "http://127.0.0.1:${PORT_QDRANT_REST}/" >/dev/null 2>&1; then
  _ok "Qdrant already running"
else
  _warn "Qdrant not running yet — will be managed by voiceai-qdrant.service after systemd install."
  _warn "Manual start: voiceai-ctl.sh start qdrant"
fi
