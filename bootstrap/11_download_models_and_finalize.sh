#!/usr/bin/env bash
# ==============================================================================
# 11_download_models_and_finalize.sh
#
# Responsibility:
#   §13  Model downloads (skip-if-present via download_hf.py)
#          Qwen3.5-35B-A3B-EXL3   (LLM)
#          faster-whisper-medium  (STT)
#          Qwen3-TTS-Tokenizer-12Hz
#          Qwen3-TTS-12Hz-1.7B-CustomVoice
#          Qwen3-TTS-12Hz-1.7B-VoiceDesign
#          Chatterbox             (TTS)
#   §14  Firewall (ufw loopback-only rules, all AI ports + Qdrant 6333/6334)
#   §15  Permission hardening (env.sh, env.conf, livekit.yaml, agent/.env, hf_token)
#          Archive legacy phase scripts (filesystem-truthful glob scan)
#          Deploy voiceai-ctl.sh to bin/
#   §16  (already done in stage 10 — guarded skip if already installed)
#   §17  Validation + smoke tests (validate.py, LiveKit smoke, venv import tests,
#          Qdrant smoke)
#   §18  Final summary banner
# ==============================================================================
set -euo pipefail
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$BOOTSTRAP_DIR/00_shared_helpers.sh"

ROOT="${ROOT:-$HOME/ai-projects/voiceai}"
ENV_DIR="${ENV_DIR:-$HOME/.config/voiceai}"
ENV_SH="${ENV_SH:-$ENV_DIR/env.sh}"
ENV_CONF="${ENV_CONF:-$ENV_DIR/env.conf}"
STT_DEFAULT_MODEL="${STT_DEFAULT_MODEL:-faster-whisper-medium}"
EMBEDDING_MODEL="${EMBEDDING_MODEL:-BAAI/bge-small-en-v1.5}"
EMBEDDING_DIM="${EMBEDDING_DIM:-384}"
PORT_LLM="${PORT_LLM:-5000}"; PORT_STT="${PORT_STT:-5100}"
PORT_TTS_ROUTER="${PORT_TTS_ROUTER:-5200}"; PORT_LIVEKIT="${PORT_LIVEKIT:-7880}"
PORT_LIVEKIT_RTC="${PORT_LIVEKIT_RTC:-7881}"; PORT_AGENT_ADMIN="${PORT_AGENT_ADMIN:-5800}"
PORT_TELEMETRY="${PORT_TELEMETRY:-5900}"; PORT_QDRANT_REST="${PORT_QDRANT_REST:-6333}"
PORT_QDRANT_GRPC="${PORT_QDRANT_GRPC:-6334}"; PORT_TTS_WORKER="${PORT_TTS_WORKER:-5201}"

# Paths resolved once; used by multiple sections below.
LK_DIR="$ROOT/livekit"; LK_BIN="$LK_DIR/livekit-server"
DOWNLOADER="$ROOT/tools/downloaders/download_hf.py"

# shellcheck source=/dev/null
[ -f "$ENV_SH" ] && . "$ENV_SH"

# ==============================================================================
# §13 — MODEL DOWNLOADS
# ==============================================================================
_banner "11 / MODEL DOWNLOADS"

_download_model() {
  local label="$1" repo="$2" target="$3" revision="${4:-}"
  _dir_has_files "$target" && { _skip "Model '$label'"; return 0; }
  _step "Downloading: $label"
  HF_XET_HIGH_PERFORMANCE=1 \
  uv run --with "huggingface_hub>=1.0.0" --with hf_xet \
    python "$DOWNLOADER" "$repo" "$target" $revision
  _ok "$label downloaded"
}

_download_model \
  "Qwen3.5-35B-A3B-EXL3" \
  "turboderp/Qwen3.5-35B-A3B-exl3" \
  "$ROOT/models/llm/Qwen3.5-35B-A3B-EXL3"

_download_model \
  "$STT_DEFAULT_MODEL" \
  "Systran/${STT_DEFAULT_MODEL}" \
  "$ROOT/models/stt/${STT_DEFAULT_MODEL}"

_download_model \
  "Qwen3-TTS-Tokenizer-12Hz" \
  "Qwen/Qwen3-TTS-Tokenizer-12Hz" \
  "$ROOT/models/tts/Qwen3-TTS-Tokenizer-12Hz"

_download_model \
  "Qwen3-TTS-12Hz-1.7B-CustomVoice" \
  "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice" \
  "$ROOT/models/tts/Qwen3-TTS-12Hz-1.7B-CustomVoice"

_download_model \
  "Qwen3-TTS-12Hz-1.7B-VoiceDesign" \
  "Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign" \
  "$ROOT/models/tts/Qwen3-TTS-12Hz-1.7B-VoiceDesign"

_download_model \
  "Chatterbox" \
  "ResembleAI/chatterbox" \
  "$ROOT/models/tts/chatterbox"

# ==============================================================================
# §14 — FIREWALL (loopback-only, all AI service ports + Qdrant)
# ==============================================================================
_banner "11 / FIREWALL"

if command -v ufw >/dev/null 2>&1; then
  # All AI services: loopback allow, then deny from any
  for port in \
      $PORT_LLM $PORT_STT $PORT_TTS_ROUTER $PORT_TTS_WORKER \
      $PORT_AGENT_ADMIN $PORT_TELEMETRY \
      $PORT_QDRANT_REST $PORT_QDRANT_GRPC; do
    sudo ufw allow in on lo to any port "$port" 2>/dev/null || true
    sudo ufw deny  in        to any port "$port" 2>/dev/null || true
  done
  # LiveKit: loopback by default (admin/lan_mode.py opens LAN when requested)
  sudo ufw allow in on lo to any port "$PORT_LIVEKIT" 2>/dev/null || true
  sudo ufw deny  in        to any port "$PORT_LIVEKIT" 2>/dev/null || true
  _ok "ufw loopback-only rules applied (Qdrant 6333/6334 included)"
else
  _warn "ufw not found — firewall rules skipped"
fi

# ==============================================================================
# §15 — PERMISSION HARDENING
# ==============================================================================
_banner "11 / PERMISSION HARDENING"

_harden "$ENV_SH"
_harden "$ENV_CONF"
_harden "$ROOT/livekit/livekit.yaml"
_harden "$ROOT/agent/.env"
[ -f "$ENV_DIR/hf_token" ] && _harden "$ENV_DIR/hf_token"

# Deploy voiceai-ctl.sh to bin/ (from same directory as bootstrap.sh root).
# SCRIPT_DIR is the project root (set by bootstrap.sh orchestrator).
# We resolve it safely here as a fallback.
_PROJ_ROOT="${SCRIPT_DIR:-$(cd "$BOOTSTRAP_DIR/.." && pwd)}"
CTL_SRC="$_PROJ_ROOT/voiceai-ctl.sh"
if [ -f "$CTL_SRC" ]; then
  cp "$CTL_SRC" "$ROOT/bin/voiceai-ctl.sh"
  chmod 755 "$ROOT/bin/voiceai-ctl.sh"
  _ok "voiceai-ctl.sh deployed to bin/"
else
  _warn "voiceai-ctl.sh not found at $_PROJ_ROOT — skipping deploy"
fi

# Archive legacy phase scripts (filesystem-truthful glob scan).
# Only moves files that actually exist on disk.
# Never archives the running bootstrap.sh or any bootstrap/ stage file.
ARCHIVE_DIR="$ROOT/shells/archive"
mkdir -p "$ARCHIVE_DIR"
ARCHIVED=0
shopt -s nullglob
for f in \
    "$_PROJ_ROOT"/*phase*.sh \
    "$ROOT"/*phase*.sh \
    "$ROOT/shells"/*phase*.sh \
    "$_PROJ_ROOT/bootstrap-corrections.sh" \
    "$ROOT/bootstrap-corrections.sh" \
    "$ROOT/shells/bootstrap-corrections.sh" \
    "$_PROJ_ROOT/voiceai-backbone-remediation.sh" \
    "$ROOT/voiceai-backbone-remediation.sh"; do
  [ -e "$f" ] || continue
  FABS="$(realpath "$f" 2>/dev/null)" || continue
  # Never archive bootstrap/ stage scripts themselves
  [[ "$FABS" == "$BOOTSTRAP_DIR"/* ]] && continue
  # Never archive the root bootstrap.sh
  [ "$FABS" = "$(realpath "$_PROJ_ROOT/bootstrap.sh" 2>/dev/null)" ] && continue
  BASE="$(basename "$f")"; DEST="$ARCHIVE_DIR/$BASE"
  [ -f "$DEST" ] && [ "$(realpath "$DEST")" = "$FABS" ] && continue  # already archived
  mv "$f" "$DEST"
  _ok "Quarantined: $BASE"
  ARCHIVED=$(( ARCHIVED + 1 ))
done
shopt -u nullglob
[ "$ARCHIVED" -gt 0 ] || _skip "No legacy phase scripts found on disk to archive"

cat > "$ARCHIVE_DIR/README.txt" <<'README'
Archived — NOT canonical operator entrypoints.
Use: bootstrap.sh (one-time) + voiceai-ctl.sh (daily lifecycle).
README

# ==============================================================================
# §16 — SYSTEMD INSTALLATION GUARD
# (Stage 10 already ran install-units.sh if systemd was available.
#  This section emits guidance only if systemd was not available at that time.)
# ==============================================================================
_banner "11 / SYSTEMD CHECK"

if systemctl --user status >/dev/null 2>&1; then
  if systemctl --user is-enabled voiceai-livekit.service >/dev/null 2>&1; then
    _ok "systemd units already installed (done by stage 10)"
  else
    _warn "systemd available but units not installed — running install-units.sh now"
    bash "$ROOT/bin/install-units.sh"
  fi
else
  _warn "systemd --user not available."
  echo "  Headless: sudo loginctl enable-linger $USER"
  echo "  Then:     bash $ROOT/bin/install-units.sh"
fi

# ==============================================================================
# §17 — VALIDATION + SMOKE TESTS
# ==============================================================================
_banner "11 / VALIDATION + SMOKE TESTS"

_step "Python validation"
python3 "$ROOT/admin/validate.py" || _warn "Validation had failures — review output above."

_step "LiveKit smoke test"
LK_LOG="$ROOT/.cache/tmp/livekit_smoke.log"
LK_PGID=""

_lk_cleanup() {
  [ -n "$LK_PGID" ] && {
    kill -TERM "-$LK_PGID" 2>/dev/null || true
    sleep 1
    kill -KILL "-$LK_PGID" 2>/dev/null || true
  }
  rm -f "$LK_LOG"
}
trap _lk_cleanup EXIT INT TERM

if ss -ltn | grep -q ":${PORT_LIVEKIT}"; then
  _skip "LiveKit already running"
  trap - EXIT INT TERM
else
  setsid "$LK_BIN" --config "$LK_DIR/livekit.yaml" > "$LK_LOG" 2>&1 &
  LK_PID=$!
  LK_PGID="$(ps -o pgid= -p "$LK_PID" 2>/dev/null | tr -d ' ')" || LK_PGID=""
  sleep 6
  if kill -0 "$LK_PID" 2>/dev/null && ss -ltn | grep -q ":${PORT_LIVEKIT}"; then
    _ok "LiveKit smoke test PASSED"
  else
    _warn "LiveKit smoke test FAILED — check $LK_LOG"
  fi
  _lk_cleanup
  trap - EXIT INT TERM
fi

_step "Venv import tests"
( . "$ROOT/llm/tabbyAPI/venv/bin/activate"
  python -c "import torch,fastapi,uvicorn; print('  LLM OK  cuda=%s' % torch.cuda.is_available())"
) || _warn "LLM venv test failed"

( . "$ROOT/stt/faster-whisper-service/venv/bin/activate"
  python -c "import faster_whisper,fastapi,watchfiles; print('  STT OK (holder.py Ph-1)')"
) || _warn "STT venv test failed"

( . "$ROOT/tts/repos/router/.venv/bin/activate"
  python -c "import fastapi,uvicorn,httpx; print('  TTS Router OK')"
) || _warn "TTS Router venv test failed"

( . "$ROOT/agent/venv/bin/activate"
  python -c "
from livekit.agents import Agent
import livekit.rtc
try:
    from qdrant_client import QdrantClient; print('  Agent OK (qdrant-client present)')
except ImportError: print('  Agent OK (qdrant-client absent — memory disabled)')
"
) || _warn "Agent venv test failed"

( "$ROOT/telemetry/.venv/bin/python" -c \
    "import fastapi,uvicorn,psutil; import pynvml; print('  Telemetry OK (pynvml)')" \
  2>/dev/null \
  || "$ROOT/telemetry/.venv/bin/python" -c \
    "import fastapi,uvicorn,psutil; print('  Telemetry OK')"
) || _warn "Telemetry venv test failed"

_step "Qdrant smoke test"
if "$ROOT/bin/qdrant" --version >/dev/null 2>&1; then
  _ok "qdrant binary responds to --version"
  if curl -fsS --max-time 3 "http://127.0.0.1:${PORT_QDRANT_REST}/" >/dev/null 2>&1; then
    _ok "Qdrant REST API responding (already running)"
  else
    _warn "Qdrant not running — will start via systemd unit."
    _warn "Manual: voiceai-ctl.sh start qdrant"
  fi
else
  _warn "qdrant binary not responding to --version"
fi

_mark_done "bootstrap"

# ==============================================================================
# §18 — FINAL SUMMARY
# ==============================================================================
_banner "BOOTSTRAP v4 COMPLETE"

echo
echo "  Project root : $ROOT"
echo "  STT model    : $STT_DEFAULT_MODEL (tiny,base,small,medium + .en)"
echo "  STT tuning   : num_workers=2  cpu_threads=8 (24C/192GB)"
echo "  Qdrant       : 127.0.0.1:${PORT_QDRANT_REST} (memory backbone)"
echo "  Embedding    : $EMBEDDING_MODEL (dim=$EMBEDDING_DIM, CPU, cached)"
echo
echo "  Service ports (all loopback by default):"
printf "    %-14s 127.0.0.1:%d\n" "LLM"         "$PORT_LLM"
printf "    %-14s 127.0.0.1:%d\n" "STT"         "$PORT_STT"
printf "    %-14s 127.0.0.1:%d\n" "TTS"         "$PORT_TTS_ROUTER"
printf "    %-14s 127.0.0.1:%d\n" "LiveKit"     "$PORT_LIVEKIT"
printf "    %-14s 127.0.0.1:%d\n" "Qdrant"      "$PORT_QDRANT_REST"
printf "    %-14s 127.0.0.1:%d\n" "AgentAdmin"  "$PORT_AGENT_ADMIN"
printf "    %-14s 127.0.0.1:%d\n" "Telemetry"   "$PORT_TELEMETRY"
echo

echo "════════════════════════════════════════════════════"
echo "  NEXT STEPS"
echo "════════════════════════════════════════════════════"
REF_COUNT="$(find "$ROOT/inputs" -maxdepth 1 \
  \( -name '*.wav' -o -name '*.mp3' -o -name '*.flac' \) 2>/dev/null | wc -l)"
[ "$REF_COUNT" -eq 0 ] && \
  echo "  ① Add reference voice WAV: cp your_voice.wav $ROOT/inputs/myvoice.wav"
echo "  ② (Headless) sudo loginctl enable-linger $USER"
echo "  ③ bash $ROOT/bin/install-units.sh  (if not done above)"
echo "  ④ voiceai-ctl.sh start"
echo "  ⑤ voiceai-ctl.sh status"
echo "  ⑥ (optional) python $ROOT/admin/lan_mode.py lan"
echo
echo "  Admin (backend-only, NOT session-voice accessible):"
echo "    python $ROOT/admin/tts_switch.py voicedesign"
echo "    python $ROOT/admin/context.py"
echo "    python $ROOT/admin/memory_admin.py init"
echo "    python $ROOT/admin/memory_admin.py list"
echo "    python $ROOT/admin/web_fetch.py <url>"
echo "    python $ROOT/admin/validate.py"
echo "    bash   $ROOT/bin/download-stt-models.sh"
echo
echo "  Telemetry API (127.0.0.1:$PORT_TELEMETRY, read-only):"
printf "    GET %-44s machine CPU/RAM/GPU\n"               "/metrics/machine"
printf "    GET %-44s service health\n"                    "/metrics/services"
printf "    GET %-44s PID-attributed CPU/RAM/VRAM\n"       "/metrics/processes"
printf "    GET %-44s persona .md inventory\n"             "/inventory/personas"
printf "    GET %-44s Chatterbox reference-audio files\n"  "/inventory/reference-audio"
printf "    GET %-44s LLM model + context ceiling\n"       "/inventory/context"
printf "    GET %-44s Qdrant collection stats\n"           "/inventory/memory"
echo
echo "  TTS engine field truth table:"
echo "    CustomVoice : voice=named-speaker  language=YES  instruct=accepted (optional)"
echo "    VoiceDesign : voice=ignored        language=YES  instruct=meaningful"
echo "    Chatterbox  : voice→inputs/<stem>.wav  language_id=YES  ref-audio=cloning"
echo
echo "  Session control — VOICE-DRIVEN (narrow policy, 3 RPCs only):"
echo "    RPC set_persona               {\"name\": \"english_teacher\"}"
echo "    RPC set_session_voice         {\"voice\": \"Aiden\", \"language\": \"English\", \"instruct\": \"\"}"
echo "    RPC set_interruption_behavior {\"mode\": \"patient\"}"
echo
echo "  Memory control — EXPLICIT CONTROL-PLANE ONLY (frontend button / admin):"
echo "    NOT accessible via natural-language voice interaction."
echo "    RPC set_memory_enabled        {\"enabled\": true}"
echo "    RPC create_memory_checkpoint  {\"summary\": \"...\", \"session_id\": \"...\"}"
echo "    RPC restore_previous_context  {\"query\": \"...\", \"user_id\": \"...\"}"
echo "    RPC search_memory             {\"query\": \"...\", \"limit\": 5}"
echo
echo "BOOTSTRAP_OK=1"
