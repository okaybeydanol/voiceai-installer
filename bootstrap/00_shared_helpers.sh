#!/usr/bin/env bash
# ==============================================================================
# 00_shared_helpers.sh — Generic shell helper functions.
#
# Sourced by bootstrap.sh (root orchestrator) and by each stage script at top
# of execution. Must NOT contain business logic, service-specific code, or any
# side effects. Functions only.
# ==============================================================================

_banner() { echo; echo "════════════════════════════════════════════"; echo "  $*"; echo "════════════════════════════════════════════"; }
_step()   { echo; echo "── $*"; }
_ok()     { echo "  [OK]   $*"; }
_skip()   { echo "  [SKIP] $*"; }
_warn()   { echo "  [WARN] $*" >&2; }
_fail()   { echo "  [FAIL] $*" >&2; exit 1; }

# Atomic file write from stdin. Safe against watcher races.
_write_atomic() {
  local dst="$1" mode="${2:-644}"
  local tmp; tmp="$(mktemp "${dst}.XXXXXX")"
  chmod "$mode" "$tmp"
  cat > "$tmp"
  mv "$tmp" "$dst"
  chmod "$mode" "$dst"
}

# True if directory exists and is non-empty.
_dir_has_files() { [ -d "$1" ] && [ -n "$(ls -A "$1" 2>/dev/null)" ]; }

# True if venv has a usable python binary.
_venv_ok() { [ -x "${1}/bin/python" ]; }

# True if venv python matches expected X.Y version string.
_venv_version_ok() {
  local venv="$1" exp="$2"
  _venv_ok "$venv" || return 1
  local got
  got="$("${venv}/bin/python" -c 'import sys;print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo '0.0')"
  [ "$got" = "$exp" ]
}

# Stage idempotency marker helpers.
_section_done_file() { echo "${ROOT}/.bootstrap/${1}.done"; }
_section_done()      { [ -f "$(_section_done_file "$1")" ]; }
_mark_done()         { mkdir -p "${ROOT}/.bootstrap"; touch "$(_section_done_file "$1")"; }

# chmod 600 a file. Skips silently if file does not exist.
_harden() {
  local f="$1"
  [ -f "$f" ] || return 0
  chmod 600 "$f"
  _ok "chmod 600 $f"
}
