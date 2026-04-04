#!/usr/bin/env bash
# ==============================================================================
# 04_install_llm_tabbyapi.sh
#
# Responsibility:
#   §6  Clone TabbyAPI repository
#       Create venv (Python 3.12)
#       Install deps (cu12 extras)
#       Write config.yml
#       Write bin/start-llm.sh
# ==============================================================================
set -euo pipefail
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$BOOTSTRAP_DIR/00_shared_helpers.sh"

ROOT="${ROOT:-$HOME/ai-projects/voiceai}"
TABBY_REF="${TABBY_REF:-main}"
TABBY_PYTHON="${TABBY_PYTHON:-3.12}"
PORT_LLM="${PORT_LLM:-5000}"
SAFE_JOBS="${SAFE_JOBS:-4}"

# ==============================================================================
# §6 — TABBYAPI REPO + VENV + DEPS
# ==============================================================================
_banner "04 / LLM — TabbyAPI"

TABBY_DIR="$ROOT/llm/tabbyAPI"

_step "TabbyAPI repo"
[ -d "$TABBY_DIR/.git" ] \
  && _skip "TabbyAPI repo" \
  || { git clone --depth 1 --branch "$TABBY_REF" \
       https://github.com/theroyallab/tabbyAPI.git "$TABBY_DIR"
       _ok "TabbyAPI cloned (ref=$TABBY_REF)"; }

_step "TabbyAPI venv"
_venv_version_ok "$TABBY_DIR/venv" "$TABBY_PYTHON" \
  && _skip "TabbyAPI venv" \
  || uv venv "$TABBY_DIR/venv" -p "$TABBY_PYTHON"

TABBY_MARKER="$TABBY_DIR/.bootstrap_deps_ok"
if [ ! -f "$TABBY_MARKER" ]; then
  _step "TabbyAPI deps (cu12) — this may take several minutes"
  cd "$TABBY_DIR"
  # shellcheck source=/dev/null
  . "./venv/bin/activate"
  CMAKE_BUILD_PARALLEL_LEVEL="$SAFE_JOBS" \
  MAKEFLAGS="-j$SAFE_JOBS" \
  MAX_JOBS="$SAFE_JOBS" \
    uv pip install -U ".[cu12]"
  deactivate
  touch "$TABBY_MARKER"
  _ok "TabbyAPI deps installed"
  cd "$ROOT"
else
  _skip "TabbyAPI deps"
fi

# ==============================================================================
# §6 — TABBYAPI CONFIG + START SCRIPT
# ==============================================================================
_banner "04 / LLM — TabbyAPI config"

python3 - <<PY
from pathlib import Path
import os, stat, tempfile

path = Path(r"$TABBY_DIR/config.yml")
content = f"""network:
  host: 127.0.0.1
  port: {os.environ.get('PORT_LLM', '$PORT_LLM')}
  disable_auth: true
model:
  model_dir: "$ROOT/models/llm"
  model_name: "Qwen3.5-35B-A3B-EXL3"
  cache_size: 16384
  gpu_split_auto: true
logging:
  prompt: false
  generation_params: false
"""
mode = 0o644
if path.exists():
    mode = path.stat().st_mode & 0o777
fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix='.config.', text=True)
try:
    os.fchmod(fd, mode)
    with os.fdopen(fd, 'w', encoding='utf-8') as fh:
        fh.write(content)
    os.replace(tmp, path)
    os.chmod(path, mode)
finally:
    try:
        if os.path.exists(tmp):
            os.unlink(tmp)
    except Exception:
        pass
PY
_ok "TabbyAPI config.yml written"

cat > "$ROOT/bin/start-llm.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
. "$HOME/.config/voiceai/env.sh"
cd "$VOICEAI_ROOT/llm/tabbyAPI"
# shellcheck source=/dev/null
. "./venv/bin/activate"
echo "[LLM] Starting TabbyAPI on 127.0.0.1:5000 …"
exec python main.py
SCRIPT
chmod +x "$ROOT/bin/start-llm.sh"
_ok "bin/start-llm.sh written"
