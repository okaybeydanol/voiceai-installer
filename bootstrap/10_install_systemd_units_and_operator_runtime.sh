#!/usr/bin/env bash
# ==============================================================================
# 10_install_systemd_units_and_operator_runtime.sh
#
# Responsibility:
#   §12  Write all systemd unit files to $ROOT/systemd/
#          voiceai-livekit.service
#          voiceai-llm.service
#          voiceai-stt.service
#          voiceai-tts.service
#          voiceai-qdrant.service   (v4)
#          voiceai-agent.service    (waits for Qdrant)
#          voiceai-telemetry.service
#        Write bin/wait-healthy.sh
#        Write bin/install-units.sh
#        Invoke install-units.sh if systemd --user is available
# ==============================================================================
set -euo pipefail
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$BOOTSTRAP_DIR/00_shared_helpers.sh"

ROOT="${ROOT:-$HOME/ai-projects/voiceai}"
PORT_LIVEKIT="${PORT_LIVEKIT:-7880}"; PORT_LLM="${PORT_LLM:-5000}"
PORT_STT="${PORT_STT:-5100}"; PORT_TTS_ROUTER="${PORT_TTS_ROUTER:-5200}"
PORT_QDRANT_REST="${PORT_QDRANT_REST:-6333}"; PORT_AGENT_ADMIN="${PORT_AGENT_ADMIN:-5800}"

# ==============================================================================
# §12 — SYSTEMD UNIT HELPER
# ==============================================================================
_banner "10 / SYSTEMD UNITS"

# _write_unit <name> <desc> <after> <exec_start> [stop_sec] [limit_interval] [limit_burst]
_write_unit() {
  local name="$1" desc="$2" after="$3" exec_start="$4"
  local stop="${5:-30}" sli="${6:-120}" slb="${7:-5}"
  cat > "$ROOT/systemd/${name}.service" <<UNIT
[Unit]
Description=${desc}
After=${after}
StartLimitIntervalSec=${sli}
StartLimitBurst=${slb}

[Service]
Type=simple
EnvironmentFile=%h/.config/voiceai/env.conf
ExecStart=${exec_start}
Restart=on-failure
RestartSec=5
KillMode=control-group
KillSignal=SIGTERM
TimeoutStopSec=${stop}
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${name}

[Install]
WantedBy=default.target
UNIT
  _ok "${name}.service"
}

# ==============================================================================
# §12 — SERVICE UNITS
# ==============================================================================

_write_unit "voiceai-livekit" \
  "VoiceAI LiveKit Server" \
  "network.target" \
  "%h/ai-projects/voiceai/livekit/livekit-server --config %h/ai-projects/voiceai/livekit/livekit.yaml"

# LLM gets a longer stop timeout (model unload) and tighter restart limit
_write_unit "voiceai-llm" \
  "VoiceAI LLM (TabbyAPI)" \
  "network.target" \
  "%h/ai-projects/voiceai/bin/start-llm.sh" \
  "60" "300" "3"

_write_unit "voiceai-stt" \
  "VoiceAI STT (Faster-Whisper)" \
  "network.target" \
  "%h/ai-projects/voiceai/bin/start-stt.sh"

_write_unit "voiceai-tts" \
  "VoiceAI TTS Router + Worker" \
  "network.target" \
  "%h/ai-projects/voiceai/bin/start-tts.sh" \
  "45"

# Qdrant: simple binary, loopback-only, must start before agent
_write_unit "voiceai-qdrant" \
  "VoiceAI Qdrant Memory Backend (port 6333)" \
  "network.target" \
  "%h/ai-projects/voiceai/bin/start-qdrant.sh" \
  "15"

# Agent: waits for all 5 upstream services before starting
cat > "$ROOT/systemd/voiceai-agent.service" <<UNIT
[Unit]
Description=VoiceAI LiveKit Agent
After=network.target voiceai-livekit.service voiceai-llm.service voiceai-stt.service voiceai-tts.service voiceai-qdrant.service
StartLimitIntervalSec=600
StartLimitBurst=10

[Service]
Type=simple
EnvironmentFile=%h/.config/voiceai/env.conf
ExecStartPre=/bin/bash %h/ai-projects/voiceai/bin/wait-healthy.sh \
  http://127.0.0.1:${PORT_LIVEKIT}/health \
  http://127.0.0.1:${PORT_LLM}/v1/models \
  http://127.0.0.1:${PORT_STT}/health \
  http://127.0.0.1:${PORT_TTS_ROUTER}/health \
  http://127.0.0.1:${PORT_QDRANT_REST}/ \
  --timeout 600
ExecStart=%h/ai-projects/voiceai/bin/start-agent.sh
Restart=on-failure
RestartSec=15
KillMode=control-group
KillSignal=SIGTERM
TimeoutStopSec=30
StandardOutput=journal
StandardError=journal
SyslogIdentifier=voiceai-agent

[Install]
WantedBy=default.target
UNIT
_ok "voiceai-agent.service (After includes voiceai-qdrant; ExecStartPre waits for Qdrant)"

_write_unit "voiceai-telemetry" \
  "VoiceAI Telemetry Sidecar (port 5900)" \
  "network.target" \
  "%h/ai-projects/voiceai/bin/start-telemetry.sh"

# ==============================================================================
# §12 — bin/wait-healthy.sh
# ==============================================================================
_banner "10 / OPERATOR RUNTIME — wait-healthy.sh"

cat > "$ROOT/bin/wait-healthy.sh" <<'SCRIPT'
#!/usr/bin/env bash
# wait-healthy.sh — poll a list of HTTP health URLs until all respond 200.
# Usage: wait-healthy.sh <url> [<url> ...] [--timeout <seconds>]
set -euo pipefail
TIMEOUT=600; URLS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *)         URLS+=("$1"); shift   ;;
  esac
done
[ "${#URLS[@]}" -eq 0 ] && exit 0
DEADLINE=$(( $(date +%s) + TIMEOUT ))
echo "[WAIT] ${#URLS[@]} service(s)  timeout=${TIMEOUT}s"
while true; do
  ALL=1
  for u in "${URLS[@]}"; do
    curl -fsS --max-time 3 "$u" >/dev/null 2>&1 || { ALL=0; break; }
  done
  [ "$ALL" -eq 1 ] && { echo "[WAIT] All healthy."; exit 0; }
  [ "$(date +%s)" -ge "$DEADLINE" ] && { echo "[WAIT] TIMEOUT" >&2; exit 1; }
  sleep 5
done
SCRIPT
chmod +x "$ROOT/bin/wait-healthy.sh"
_ok "bin/wait-healthy.sh written"

# ==============================================================================
# §12 — bin/install-units.sh
# ==============================================================================
_banner "10 / OPERATOR RUNTIME — install-units.sh"

cat > "$ROOT/bin/install-units.sh" <<'SCRIPT'
#!/usr/bin/env bash
# install-units.sh — copy systemd units to ~/.config/systemd/user/, enable them.
set -euo pipefail
# shellcheck source=/dev/null
. "$HOME/.config/voiceai/env.sh"
SRC="$VOICEAI_ROOT/systemd"
DST="$HOME/.config/systemd/user"
[ -d "$SRC" ] || { echo "ERROR: run bootstrap.sh first"; exit 1; }
systemctl --user status >/dev/null 2>&1 || {
  echo "ERROR: systemd --user not responding."
  echo "  sudo loginctl enable-linger $USER"
  exit 1
}
mkdir -p "$DST"
for u in voiceai-livekit voiceai-llm voiceai-stt voiceai-tts \
          voiceai-qdrant voiceai-agent voiceai-telemetry; do
  cp "$SRC/${u}.service" "$DST/${u}.service"
  echo "  [INSTALLED] ${u}.service"
done
systemctl --user daemon-reload
for u in voiceai-livekit voiceai-llm voiceai-stt voiceai-tts \
          voiceai-qdrant voiceai-agent voiceai-telemetry; do
  systemctl --user enable "${u}.service"
  echo "  [ENABLED] ${u}.service"
done
loginctl show-user "$USER" 2>/dev/null | grep -q "Linger=yes" \
  && echo "  Linger: OK" \
  || echo "  WARNING: sudo loginctl enable-linger $USER"
echo
echo "INSTALL_UNITS_OK=1"
SCRIPT
chmod +x "$ROOT/bin/install-units.sh"
_ok "bin/install-units.sh written"

# ==============================================================================
# §12 — INVOKE install-units.sh (if systemd --user is available)
# ==============================================================================
_banner "10 / SYSTEMD INSTALLATION"

if systemctl --user status >/dev/null 2>&1; then
  bash "$ROOT/bin/install-units.sh"
else
  _warn "systemd --user not available."
  echo "  Headless: sudo loginctl enable-linger $USER"
  echo "  Then:     bash $ROOT/bin/install-units.sh"
fi
