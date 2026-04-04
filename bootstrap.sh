#!/usr/bin/env bash
# ==============================================================================
# bootstrap.sh — VoiceAI Canonical Installer (Staged Orchestrator)
# ==============================================================================
# This file is the ONLY root-level entrypoint.
# It defines all globals, then delegates to numbered stage scripts in bootstrap/.
#
# Staged installer layout:
#   bootstrap/00_shared_helpers.sh                  — shared shell helpers
#   bootstrap/01_prepare_layout_and_environment.sh  — §1 dirs  §2 env
#   bootstrap/02_run_preflight_and_shared_tools.sh  — §3 preflight  §4 downloader
#   bootstrap/03_install_livekit_and_network_baseline.sh — §5 livekit
#   bootstrap/04_install_llm_tabbyapi.sh            — §6 llm
#   bootstrap/05_install_stt_service.sh             — §7 stt
#   bootstrap/06_install_tts_stack.sh               — §8 tts
#   bootstrap/07_install_agent_and_session_control.sh — §9 agent
#   bootstrap/08_install_memory_and_qdrant.sh       — §9.5 qdrant
#   bootstrap/09_install_telemetry_and_admin_surfaces.sh — §10+§11 telem+admin
#   bootstrap/10_install_systemd_units_and_operator_runtime.sh — §12 systemd
#   bootstrap/11_download_models_and_finalize.sh    — §13-§18 models+final
#
# Operator lifecycle (after bootstrap):  bin/voiceai-ctl.sh
# ==============================================================================
set -euo pipefail
umask 022

# ─── GLOBALS (exported to all stage scripts via bash env inheritance) ──────────
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BOOTSTRAP_DIR="$SCRIPT_DIR/bootstrap"

export ROOT="${VOICEAI_ROOT:-$HOME/ai-projects/voiceai}"
export ENV_DIR="$HOME/.config/voiceai"
export ENV_SH="$ENV_DIR/env.sh"
export ENV_CONF="$ENV_DIR/env.conf"
export SYSTEMD_USER="$HOME/.config/systemd/user"
export SAFE_JOBS=4

export PORT_LLM=5000
export PORT_STT=5100
export PORT_TTS_ROUTER=5200
export PORT_TTS_WORKER=5201
export PORT_AGENT_ADMIN=5800
export PORT_TELEMETRY=5900
export PORT_LIVEKIT=7880
export PORT_LIVEKIT_RTC=7881
export PORT_QDRANT_REST=6333
export PORT_QDRANT_GRPC=6334

export LK_VERSION="1.9.12"
export QDRANT_VERSION="1.13.4"
export TABBY_REF="${TABBY_REF:-main}"
export TABBY_PYTHON="3.12"
export STT_PYTHON="3.12"
export AGENT_PYTHON="3.12"
export TELEMETRY_PYTHON="3.12"
export STT_DEFAULT_MODEL="faster-whisper-medium"
export EMBEDDING_MODEL="BAAI/bge-small-en-v1.5"
export EMBEDDING_DIM=384

# ─── SHARED HELPERS ────────────────────────────────────────────────────────────
# shellcheck source=/dev/null
. "$BOOTSTRAP_DIR/00_shared_helpers.sh"

# ─── ROOT GUARD ────────────────────────────────────────────────────────────────
[ "$(id -u)" -ne 0 ] || _fail "Do not run as root."

# ─── STARTUP BANNER ────────────────────────────────────────────────────────────
echo
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   VoiceAI bootstrap.sh  v4  — Staged Installer              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo "  ROOT      : $ROOT"
echo "  USER      : $USER"
echo "  DATE      : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  STT model : $STT_DEFAULT_MODEL"
echo "  Embedding : $EMBEDDING_MODEL (dim=$EMBEDDING_DIM)"
echo "  Stages    : $BOOTSTRAP_DIR"
echo

# ─── STAGE RUNNER ──────────────────────────────────────────────────────────────
# Each stage is called as a bash subshell. All exported vars above are inherited.
# Failure in any stage aborts the installer immediately.
_run_stage() {
  local name="$1"
  local script="$BOOTSTRAP_DIR/$name"
  [ -f "$script" ] || _fail "Stage script not found: $script"
  echo
  echo "▶▶▶ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "▶▶▶  STAGE: $name"
  echo "▶▶▶ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  bash "$script" || _fail "Stage failed: $name"
  echo "▶▶▶  STAGE DONE: $name"
}

# ─── ORDERED STAGE EXECUTION ───────────────────────────────────────────────────
_run_stage "01_prepare_layout_and_environment.sh"
_run_stage "02_run_preflight_and_shared_tools.sh"
_run_stage "03_install_livekit_and_network_baseline.sh"
_run_stage "04_install_llm_tabbyapi.sh"
_run_stage "05_install_stt_service.sh"
_run_stage "06_install_tts_stack.sh"
_run_stage "07_install_agent_and_session_control.sh"
_run_stage "08_install_memory_and_qdrant.sh"
_run_stage "09_install_telemetry_and_admin_surfaces.sh"
_run_stage "10_install_systemd_units_and_operator_runtime.sh"
_run_stage "11_download_models_and_finalize.sh"

# ─── ORCHESTRATOR COMPLETE ─────────────────────────────────────────────────────
echo
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   VoiceAI bootstrap.sh  v4  — ALL STAGES COMPLETE           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
