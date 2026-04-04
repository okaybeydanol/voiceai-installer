#!/usr/bin/env bash
# ==============================================================================
# 01_prepare_layout_and_environment.sh
#
# Responsibility:
#   §1  Create the full project directory tree and .gitignore
#   §2  Write env.sh (600), derive env.conf, inject .bashrc source line
#
# All globals (ROOT, ENV_DIR, ENV_SH, ENV_CONF, SAFE_JOBS, PORT_*, etc.)
# are inherited from the parent bootstrap.sh via exported environment variables.
# ==============================================================================
set -euo pipefail
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$BOOTSTRAP_DIR/00_shared_helpers.sh"

# Apply defaults for standalone execution (normally set by parent orchestrator).
ROOT="${ROOT:-$HOME/ai-projects/voiceai}"
ENV_DIR="${ENV_DIR:-$HOME/.config/voiceai}"
ENV_SH="${ENV_SH:-$ENV_DIR/env.sh}"
ENV_CONF="${ENV_CONF:-$ENV_DIR/env.conf}"
SYSTEMD_USER="${SYSTEMD_USER:-$HOME/.config/systemd/user}"
SAFE_JOBS="${SAFE_JOBS:-4}"
EMBEDDING_MODEL="${EMBEDDING_MODEL:-BAAI/bge-small-en-v1.5}"
EMBEDDING_DIM="${EMBEDDING_DIM:-384}"
STT_DEFAULT_MODEL="${STT_DEFAULT_MODEL:-faster-whisper-medium}"

# ==============================================================================
# §1 — DIRECTORY LAYOUT
# ==============================================================================
_banner "01 / DIRECTORY LAYOUT"

mkdir -p \
  "$ROOT/bin" "$ROOT/shells" "$ROOT/livekit" "$ROOT/llm" \
  "$ROOT/stt/faster-whisper-service/src/routes" \
  "$ROOT/tts/router/src/routes" "$ROOT/tts/worker/src/routes" \
  "$ROOT/tts/worker/src/engines" "$ROOT/tts/repos" \
  "$ROOT/inputs" "$ROOT/memory/qdrant" \
  "$ROOT/models/llm" "$ROOT/models/stt" "$ROOT/models/tts" \
  "$ROOT/agent/src/tools" "$ROOT/agent/personas" \
  "$ROOT/admin" "$ROOT/systemd" "$ROOT/config" \
  "$ROOT/telemetry/src/collectors" "$ROOT/tools/downloaders" \
  "$ROOT/web" "$ROOT/phone" "$ROOT/.bootstrap" \
  "$ROOT/.cache/huggingface/hub" "$ROOT/.cache/huggingface/xet" \
  "$ROOT/.cache/huggingface/datasets" "$ROOT/.cache/huggingface/assets" \
  "$ROOT/.cache/uv" "$ROOT/.cache/tmp" \
  "$ROOT/.cache/fastembed" \
  "$ENV_DIR" "$SYSTEMD_USER"

_write_atomic "$ROOT/.gitignore" 644 <<'GITIGNORE'
models/
.cache/
memory/qdrant/
*.pyc
__pycache__/
*.egg-info/
.venv/
venv/
.env
!.env.example
GITIGNORE

_ok "Directory tree ready: $ROOT"

# ==============================================================================
# §2 — ENVIRONMENT (env.sh, env.conf, .bashrc)
# ==============================================================================
_banner "01 / ENVIRONMENT"

if [ ! -f "$ENV_SH" ]; then
  _write_atomic "$ENV_SH" 600 <<EOF
export VOICEAI_ROOT="$ROOT"
export VOICEAI_MODELS_ROOT="$ROOT/models"
export XDG_CACHE_HOME="$ROOT/.cache"
export HF_HOME="$ROOT/.cache/huggingface"
export HF_HUB_CACHE="$ROOT/.cache/huggingface/hub"
export HF_XET_CACHE="$ROOT/.cache/huggingface/xet"
export HF_DATASETS_CACHE="$ROOT/.cache/huggingface/datasets"
export HF_ASSETS_CACHE="$ROOT/.cache/huggingface/assets"
export HF_TOKEN_PATH="$ENV_DIR/hf_token"
export UV_CACHE_DIR="$ROOT/.cache/uv"
export CMAKE_BUILD_PARALLEL_LEVEL=$SAFE_JOBS
export MAKEFLAGS="-j$SAFE_JOBS"
export MAX_JOBS=$SAFE_JOBS
export OMP_NUM_THREADS=8
export MKL_NUM_THREADS=8
export OPENBLAS_NUM_THREADS=8
export HF_HUB_DISABLE_TELEMETRY=1
export HF_XET_HIGH_PERFORMANCE=1
export CUDA_MODULE_LOADING=LAZY
export TOKENIZERS_PARALLELISM=false
export FASTEMBED_CACHE_PATH="$ROOT/.cache/fastembed"
EOF
fi

# shellcheck source=/dev/null
. "$ENV_SH"

# Derive env.conf (KEY=VALUE without 'export' prefix) for systemd EnvironmentFile=
python3 - "$ENV_SH" "$ENV_CONF" <<'PY'
import sys, re, os, stat
src, dst = sys.argv[1], sys.argv[2]
out = []
with open(src) as f:
    for line in f:
        s = line.rstrip('\n'); stripped = s.strip()
        if not stripped or stripped.startswith('#'):
            out.append(s); continue
        m = re.match(r'^export\s+(\w+=.*)$', s)
        out.append(m.group(1) if m else s)
tmp = dst + '.tmp'
with open(tmp, 'w') as fh:
    fh.write('\n'.join(out) + '\n')
os.chmod(tmp, stat.S_IRUSR | stat.S_IWUSR)
os.replace(tmp, dst)
PY

_harden "$ENV_CONF"

# Inject env.sh source into .bashrc (idempotent)
SOURCE_LINE='. "$HOME/.config/voiceai/env.sh"'
grep -Fqx "$SOURCE_LINE" "$HOME/.bashrc" 2>/dev/null \
  || printf '\n%s\n' "$SOURCE_LINE" >> "$HOME/.bashrc"

_ok "env.sh + env.conf ready"
