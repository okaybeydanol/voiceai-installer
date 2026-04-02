#!/usr/bin/env bash
# ==============================================================================
# 03_install_livekit_and_network_baseline.sh
#
# Responsibility:
#   §5  LiveKit server binary (pinned version)
#       LiveKit credential generation (idempotent)
#       LiveKit config templates (loopback + LAN)
#       Render livekit.yaml (loopback by default)
# ==============================================================================
set -euo pipefail
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$BOOTSTRAP_DIR/00_shared_helpers.sh"

ROOT="${ROOT:-$HOME/ai-projects/voiceai}"
ENV_DIR="${ENV_DIR:-$HOME/.config/voiceai}"
ENV_SH="${ENV_SH:-$ENV_DIR/env.sh}"
ENV_CONF="${ENV_CONF:-$ENV_DIR/env.conf}"
LK_VERSION="${LK_VERSION:-1.9.12}"
PORT_LIVEKIT="${PORT_LIVEKIT:-7880}"
PORT_LIVEKIT_RTC="${PORT_LIVEKIT_RTC:-7881}"

# ==============================================================================
# §5 — LIVEKIT BINARY
# ==============================================================================
_banner "03 / LIVEKIT BINARY"

LK_DIR="$ROOT/livekit"
LK_BIN="$LK_DIR/livekit-server"

NEEDS_DL=true
if [ -f "$LK_BIN" ]; then
  CUR="$("$LK_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo '0')"
  [ "$CUR" = "$LK_VERSION" ] && { NEEDS_DL=false; _skip "livekit-server v$LK_VERSION"; }
fi

if [ "$NEEDS_DL" = true ]; then
  ARCHIVE="livekit_${LK_VERSION}_linux_amd64.tar.gz"
  wget -q --show-progress \
    "https://github.com/livekit/livekit/releases/download/v${LK_VERSION}/${ARCHIVE}" \
    -O "$LK_DIR/livekit.tar.gz"
  tar -xzf "$LK_DIR/livekit.tar.gz" -C "$LK_DIR" livekit-server
  rm -f "$LK_DIR/livekit.tar.gz"
  _ok "livekit-server v$LK_VERSION downloaded"
fi
chmod +x "$LK_BIN"

# ==============================================================================
# §5 — LIVEKIT CREDENTIALS
# ==============================================================================
_banner "03 / LIVEKIT CREDENTIALS"

if grep -q "LIVEKIT_API_KEY" "$ENV_SH" 2>/dev/null; then
  _skip "LiveKit credentials already in env.sh"
  # shellcheck source=/dev/null
  . "$ENV_SH"
  LK_API_KEY="$LIVEKIT_API_KEY"
  LK_API_SECRET="$LIVEKIT_API_SECRET"
else
  LK_API_KEY="devkey_$(openssl rand -hex 4)"
  LK_API_SECRET="$(openssl rand -hex 16)"
  {
    printf '\nexport LIVEKIT_API_KEY="%s"\n'    "$LK_API_KEY"
    printf 'export LIVEKIT_API_SECRET="%s"\n'   "$LK_API_SECRET"
    printf 'export LIVEKIT_URL="ws://127.0.0.1:%d"\n' "$PORT_LIVEKIT"
  } >> "$ENV_SH"
  # Regenerate env.conf to include new credentials
  python3 - "$ENV_SH" "$ENV_CONF" <<'PY'
import sys, re, os, stat
src, dst = sys.argv[1], sys.argv[2]; out = []
with open(src) as f:
    for line in f:
        s = line.rstrip('\n'); stripped = s.strip()
        if not stripped or stripped.startswith('#'): out.append(s); continue
        m = re.match(r'^export\s+(\w+=.*)$', s)
        out.append(m.group(1) if m else s)
tmp = dst + '.tmp'
with open(tmp, 'w') as fh: fh.write('\n'.join(out) + '\n')
os.chmod(tmp, stat.S_IRUSR | stat.S_IWUSR); os.replace(tmp, dst)
PY
  _harden "$ENV_CONF"
  _ok "LiveKit credentials generated"
fi

# shellcheck source=/dev/null
. "$ENV_SH"

# ==============================================================================
# §5 — LIVEKIT CONFIG TEMPLATES
# ==============================================================================
_banner "03 / LIVEKIT CONFIG TEMPLATES"

cat > "$ROOT/config/livekit-loopback.yaml.template" <<TMPL
port: \${PORT_LIVEKIT}
bind_addresses:
  - "127.0.0.1"
rtc:
  tcp_port: \${PORT_LIVEKIT_RTC}
  port_range_start: 50000
  port_range_end: 60000
  use_external_ip: false
  enable_loopback_candidate: true
  stun_servers: []
logging:
  json: false
  level: info
TMPL

cat > "$ROOT/config/livekit-lan.yaml.template" <<'TMPL'
port: __PORT_LIVEKIT__
bind_addresses:
  - "0.0.0.0"
rtc:
  tcp_port: __PORT_LIVEKIT_RTC__
  port_range_start: 50000
  port_range_end: 60000
  node_ip: "__LAN_IP__"
  use_external_ip: false
  enable_loopback_candidate: true
  stun_servers: []
logging:
  json: false
  level: info
TMPL

_ok "Config templates written"

# ==============================================================================
# §5 — RENDER livekit.yaml (loopback default)
# ==============================================================================
_banner "03 / LIVEKIT YAML RENDER"

_render_livekit_loopback() {
  python3 - "$ROOT/config/livekit-loopback.yaml.template" \
    "$LK_DIR/livekit.yaml" \
    "${LK_API_KEY}" "${LK_API_SECRET}" \
    "$PORT_LIVEKIT" "$PORT_LIVEKIT_RTC" <<'PY'
import sys, os, stat, tempfile
tmpl, dst, key, sec, port, rpc = sys.argv[1:]
with open(tmpl) as f: content = f.read()
content = content.replace("${PORT_LIVEKIT}", port).replace("${PORT_LIVEKIT_RTC}", rpc)
content += f'\nkeys:\n  "{key}": "{sec}"\n'
tmp = dst + ".tmp"
with open(tmp, "w") as fh: fh.write(content)
os.chmod(tmp, stat.S_IRUSR | stat.S_IWUSR)
os.replace(tmp, dst)
PY
  _harden "$LK_DIR/livekit.yaml"
}

if [ -f "$LK_DIR/livekit.yaml" ]; then
  _skip "livekit.yaml exists"
  _harden "$LK_DIR/livekit.yaml"
else
  _render_livekit_loopback
  _ok "livekit.yaml rendered (loopback)"
fi
