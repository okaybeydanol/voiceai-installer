#!/usr/bin/env bash
# ==============================================================================
# 02_run_preflight_and_shared_tools.sh
#
# Responsibility:
#   §3  System preflight: required binaries, GPU check, HF token, reference audio
#   §4  Write the shared HF model downloader script (download_hf.py)
# ==============================================================================
set -euo pipefail
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$BOOTSTRAP_DIR/00_shared_helpers.sh"

ROOT="${ROOT:-$HOME/ai-projects/voiceai}"
ENV_DIR="${ENV_DIR:-$HOME/.config/voiceai}"

# ==============================================================================
# §3 — SYSTEM PREFLIGHT
# ==============================================================================
_banner "02 / SYSTEM PREFLIGHT"

ALL_OK=1
_require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 && { _ok "$cmd"; return; }
  _warn "MISSING: $cmd"; ALL_OK=0
}

for c in python3 gcc g++ make git curl nvcc nvidia-smi; do _require_cmd "$c"; done
for c in uv cmake ninja; do _require_cmd "$c"; done
[ "$ALL_OK" -eq 0 ] && _fail "Install missing tools before running bootstrap."

_step "GPU info"
nvidia-smi --query-gpu=name,driver_version,memory.total,compute_cap \
  --format=csv,noheader 2>/dev/null || _warn "nvidia-smi query failed"

_step "HF token"
HF_TOKEN_FILE="$ENV_DIR/hf_token"
[ -f "$HF_TOKEN_FILE" ] && { _harden "$HF_TOKEN_FILE"; _ok "HF token present"; } \
  || _warn "No HF token at $HF_TOKEN_FILE — gated models will fail to download"

# Ph-1: reference audio is directory-driven, not hardcoded filename.
_step "Reference audio"
if _dir_has_files "$ROOT/inputs"; then
  REF_COUNT=$(find "$ROOT/inputs" -maxdepth 1 \
    \( -name "*.wav" -o -name "*.mp3" -o -name "*.flac" \) | wc -l)
  _ok "inputs/ present ($REF_COUNT reference audio file(s))"
else
  _warn "inputs/ is empty — Chatterbox will synthesize without voice cloning."
  _warn "Add reference audio: cp your_voice.wav $ROOT/inputs/myvoice.wav"
fi

# ==============================================================================
# §4 — SHARED HF DOWNLOADER
# ==============================================================================
_banner "02 / SHARED HF DOWNLOADER"

DOWNLOADER="$ROOT/tools/downloaders/download_hf.py"

cat > "$DOWNLOADER" <<'PYEOF'
#!/usr/bin/env python3
"""VoiceAI HF Downloader. local_dir_use_symlinks NOT passed (deprecated >=0.22)."""
from __future__ import annotations
import os, sys
from pathlib import Path

def _token():
    for v in ("HF_TOKEN", "HUGGING_FACE_HUB_TOKEN", "HUGGINGFACE_HUB_TOKEN"):
        t = os.getenv(v, "").strip()
        if t: return t
    p = os.getenv("HF_TOKEN_PATH", "")
    if p:
        fp = Path(p).expanduser()
        if fp.is_file():
            m = fp.stat().st_mode & 0o777
            if m & 0o044:
                print(f"WARNING: {fp} world/group-readable. chmod 600", file=sys.stderr)
            t = fp.read_text(encoding="utf-8").strip()
            if t: return t
    return None

def _resolve_rev(api, repo_id, token, requested):
    if requested: return requested
    refs = api.list_repo_refs(repo_id=repo_id, repo_type="model", token=token)
    names = {r.name for r in getattr(refs, "branches", [])} | \
            {r.name for r in getattr(refs, "tags", [])}
    for c in ("4.00bpw", "4.0bpw", "4bpw"):
        if c in names: return c
    return None

def main():
    if len(sys.argv) < 3:
        raise SystemExit("Usage: download_hf.py <repo_id> <target_dir> [revision]")
    repo_id = sys.argv[1]
    target  = Path(sys.argv[2])
    requested = sys.argv[3].strip() if len(sys.argv) > 3 else ""
    if target.exists() and any(target.iterdir()):
        print(f"SKIP: {target} already populated."); return
    from huggingface_hub import HfApi, snapshot_download
    token = _token()
    rev   = _resolve_rev(HfApi(), repo_id, token, requested or None)
    print(f"Downloading {repo_id}  rev={rev or 'default'}  →  {target}")
    target.mkdir(parents=True, exist_ok=True)
    snapshot_download(repo_id=repo_id, revision=rev, local_dir=str(target),
                      token=token, ignore_patterns=["*.bin.index.json"])
    print(f"DOWNLOAD_OK: {target}")

main()
PYEOF

chmod +x "$DOWNLOADER"
_ok "download_hf.py written"
