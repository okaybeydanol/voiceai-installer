#!/usr/bin/env bash
# ==============================================================================
# voiceai-ctl.sh — VoiceAI Lifecycle Controller
# ==============================================================================
# Responsibilities (lifecycle-only):
#   start | stop | restart | status | logs | health | validate
#
# NOT in this script — use the admin/ layer instead:
#   LAN switching         → python admin/lan_mode.py
#   TTS engine switching  → python admin/tts_switch.py   (global backend-admin)
#   STT model switching   → backend STT HTTP admin endpoint (/admin/switch_model)
#   LLM context info      → python admin/context.py
#   Memory admin          → python admin/memory_admin.py
#   Safe web fetch        → python admin/web_fetch.py
#   Telemetry             → GET http://127.0.0.1:5900/metrics
#   Session voice control → LiveKit RPC set_persona / set_session_voice / set_interruption_behavior
#   Memory control-plane  → explicit LiveKit control-plane RPCs: set_memory_enabled / checkpoint / restore / search
#                           (frontend/admin initiated only; NOT normal session voice commands)
# ==============================================================================
set -uo pipefail

ENV_SH="$HOME/.config/voiceai/env.sh"
# shellcheck source=/dev/null
[ -f "$ENV_SH" ] && . "$ENV_SH"
ROOT="${VOICEAI_ROOT:-$HOME/ai-projects/voiceai}"

# ─── Service definitions ──────────────────────────────────────────────────────
declare -A UNIT=(
  [livekit]="voiceai-livekit.service"
  [llm]="voiceai-llm.service"
  [stt]="voiceai-stt.service"
  [tts]="voiceai-tts.service"
  [qdrant]="voiceai-qdrant.service"
  [telemetry]="voiceai-telemetry.service"
  [agent]="voiceai-agent.service"
)

# Qdrant REST endpoint returns 200 on its root path.
declare -A HEALTH_URL=(
  [livekit]="tcp://127.0.0.1:7880"
  [llm]="http://127.0.0.1:5000/v1/models"
  [stt]="http://127.0.0.1:5100/health"
  [tts]="http://127.0.0.1:5200/health"
  [qdrant]="http://127.0.0.1:6333/"
  [telemetry]="http://127.0.0.1:5900/health"
  [agent]="http://127.0.0.1:5800/health"
)

# Start order: qdrant before agent (agent memory depends on Qdrant).
START_ORDER=(livekit llm stt tts qdrant telemetry agent)
# Stop order: reverse dependency.
STOP_ORDER=(agent telemetry qdrant tts stt llm livekit)

# ─── Helpers ──────────────────────────────────────────────────────────────────
_require_systemd() {
  systemctl --user status >/dev/null 2>&1 && return 0
  echo "ERROR: systemd --user is not available." >&2
  echo >&2
  echo "  For headless servers: sudo loginctl enable-linger $USER" >&2
  echo "  Then install units:   bash $ROOT/bin/install-units.sh" >&2
  exit 1
}

_resolve_names() {
  local target="$1" cmd="${2:-start}"
  if [ "$target" = "all" ]; then
    [ "$cmd" = "stop" ] && printf '%s\n' "${STOP_ORDER[@]}" \
                        || printf '%s\n' "${START_ORDER[@]}"
    return
  fi
  [ "${UNIT[$target]+set}" ] && { echo "$target"; return; }
  echo "ERROR: Unknown service '$target'." >&2
  echo "  Valid: ${!UNIT[*]}" >&2
  exit 1
}

_unit()       { echo "${UNIT[$1]}"; }
_health_url() { echo "${HEALTH_URL[$1]:-}"; }

_tcp_open() {
  local host="$1" port="$2"
  python3 - "$host" "$port" <<'PY' >/dev/null 2>&1
import socket, sys
host = sys.argv[1]
port = int(sys.argv[2])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(2.0)
try:
    s.connect((host, port))
    raise SystemExit(0)
except Exception:
    raise SystemExit(1)
finally:
    try:
        s.close()
    except Exception:
        pass
PY
}

_http_health() {
  local svc="$1" url="$2"
  [ -z "$url" ] && echo "—" && return

  if [[ "$url" == tcp://* ]]; then
    local hp host port
    hp="${url#tcp://}"
    host="${hp%%:*}"
    port="${hp##*:}"
    _tcp_open "$host" "$port" && echo "ONLINE" || echo "offline"
    return
  fi

  if [ "$svc" = "llm" ]; then
    curl -fsS --max-time 2 \
      -H 'Authorization: Bearer local' \
      "$url" >/dev/null 2>&1 && echo "ONLINE" || echo "offline"
    return
  fi

  curl -fsS --max-time 2 "$url" >/dev/null 2>&1 && echo "ONLINE" || echo "offline"
}

_tts_detail() {
  python3 -c "
import json, urllib.request
try:
    with urllib.request.urlopen('http://127.0.0.1:5200/health', timeout=2) as r:
        d = json.loads(r.read())
    mode  = d.get('active_mode') or 'none'
    phase = d.get('router_phase', '?')
    sw    = ' [SWITCHING]' if d.get('switching') else ''
    w     = d.get('worker', {})
    try:
        vu = round(float(w.get('vram_total_gb',0)) - float(w.get('vram_free_gb',0)), 1)
    except Exception:
        vu = '?'
    print(f'mode={mode} phase={phase} VRAM:{vu}GB{sw}', end='')
except Exception:
    pass
" 2>/dev/null
}

_agent_detail() {
  python3 -c "
import json, urllib.request
try:
    with urllib.request.urlopen('http://127.0.0.1:5800/health', timeout=2) as r:
        d = json.loads(r.read())
    active   = d.get('session_active', False)
    persona  = d.get('persona', '?')
    mode     = d.get('voice_mode', '?')
    room     = d.get('room_name') or 'idle'
    mem      = 'mem=on' if d.get('memory_enabled') else 'mem=off'
    tok      = d.get('session_tokens')
    tok_s    = f' tokens={tok}' if tok is not None else ''
    print(f'session={str(active).lower()} persona={persona} voice={mode} room={room} {mem}{tok_s}', end='')
except Exception:
    pass
" 2>/dev/null
}

_stt_detail() {
  python3 -c "
import json, urllib.request
try:
    with urllib.request.urlopen('http://127.0.0.1:5100/health', timeout=2) as r:
        d = json.loads(r.read())
    print(f'model={d.get(\"model\",\"?\")}', end='')
except Exception:
    pass
" 2>/dev/null
}

_qdrant_detail() {
  python3 -c "
import json, urllib.request
try:
    with urllib.request.urlopen('http://127.0.0.1:6333/collections', timeout=2) as r:
        d = json.loads(r.read())
    colls = d.get('result',{}).get('collections',[])
    counts = {c['name'].replace('voiceai_',''): c.get('vectors_count',0) for c in colls}
    if counts: print('collections: ' + '  '.join(f'{k}={v}' for k,v in counts.items()), end='')
except Exception:
    pass
" 2>/dev/null
}

# ─── COMMANDS ─────────────────────────────────────────────────────────────────

cmd_start() {
  local target="${1:-all}"
  _require_systemd
  echo "Starting: $target"
  while IFS= read -r svc; do
    unit="$(_unit "$svc")"
    printf "  %-12s " "$svc"
    if systemctl --user start "$unit" 2>/dev/null; then echo "started"
    else echo "FAILED — run: voiceai-ctl.sh logs $svc"; fi
  done < <(_resolve_names "$target" start)
}

cmd_stop() {
  local target="${1:-all}"
  _require_systemd
  echo "Stopping: $target"
  while IFS= read -r svc; do
    unit="$(_unit "$svc")"
    printf "  %-12s " "$svc"
    if systemctl --user stop "$unit" 2>/dev/null; then echo "stopped"
    else echo "FAILED"; fi
  done < <(_resolve_names "$target" stop)
}

cmd_restart() {
  local target="${1:-all}"
  _require_systemd
  echo "Restarting: $target"
  while IFS= read -r svc; do
    unit="$(_unit "$svc")"
    printf "  %-12s " "$svc"
    if systemctl --user restart "$unit" 2>/dev/null; then echo "restarted"
    else echo "FAILED — run: voiceai-ctl.sh logs $svc"; fi
  done < <(_resolve_names "$target" restart)
}

cmd_status() {
  local target="${1:-all}"
  _require_systemd
  echo
  echo "══════════════════════════════════════════════════════════════"
  echo "  VoiceAI Status  [$(date '+%Y-%m-%d %H:%M:%S')]"
  echo "══════════════════════════════════════════════════════════════"
  echo
  printf "  %-12s  %-9s  %-9s  %s\n" "SERVICE" "SYSTEMD" "HTTP" "DETAIL"
  printf "  %-12s  %-9s  %-9s  %s\n" "-------" "-------" "----" "------"

  local names
  if [ "$target" = "all" ]; then
    names=("${START_ORDER[@]}")
  else
    names=("$target")
  fi

  for svc in "${names[@]}"; do
    unit="$(_unit "$svc")"
    active="$(systemctl --user is-active "$unit" 2>/dev/null || echo "inactive")"
    url="$(_health_url "$svc")"
    http_st="$(_http_health "$svc" "$url")"
    detail=""
    case "$svc" in
      tts)    [ "$http_st" = "ONLINE" ] && detail="$(_tts_detail)"    ;;
      agent)  [ "$http_st" = "ONLINE" ] && detail="$(_agent_detail)"  ;;
      stt)    [ "$http_st" = "ONLINE" ] && detail="$(_stt_detail)"    ;;
      qdrant) [ "$http_st" = "ONLINE" ] && detail="$(_qdrant_detail)" ;;
    esac
    printf "  %-12s  %-9s  %-9s  %s\n" "$svc" "$active" "$http_st" "$detail"
  done

  echo

  # LAN mode indicator
  LAN_IP_F="$ROOT/config/lan_ip.txt"
  if [ -f "$LAN_IP_F" ]; then
    LAN_IP="$(cat "$LAN_IP_F" 2>/dev/null)"
    echo "  LAN mode : ACTIVE  (LiveKit LAN IP: $LAN_IP)"
    echo "  Phone URL: ws://${LAN_IP}:7880"
  else
    echo "  LAN mode : INACTIVE (loopback-only)"
  fi

  # Machine summary from telemetry if available
  if curl -fsS --max-time 2 "http://127.0.0.1:5900/metrics/machine" >/dev/null 2>&1; then
    python3 -c "
import json, urllib.request
try:
    with urllib.request.urlopen('http://127.0.0.1:5900/metrics/machine', timeout=2) as r:
        m = json.loads(r.read())
    cpu = m.get('cpu_percent','?'); ram = m.get('ram_percent','?')
    g   = m.get('gpu')
    print(f'  Machine  : CPU {cpu}%  RAM {ram}%', end='')
    if g:
        vu = round(float(g.get('vram_total_gb',0)) - float(g.get('vram_free_gb',0)), 1)
        print(f'  GPU {g.get(\"util_percent\",\"?\")}%  VRAM {vu}/{g.get(\"vram_total_gb\",\"?\")}GB  {g.get(\"temp_c\",\"?\")}°C', end='')
    print()
except Exception:
    pass
" 2>/dev/null
  fi
  echo
}

cmd_logs() {
  local target="${1:-}"
  if [ -z "$target" ] || [ "$target" = "all" ]; then
    echo "Usage: voiceai-ctl.sh logs <service> [journalctl args]" >&2
    echo "  Services: ${!UNIT[*]}" >&2
    exit 1
  fi
  _require_systemd
  shift 2 || true
  unit="$(_unit "$target")"
  exec journalctl --user-unit "$unit" --no-hostname -o short-monotonic "$@"
}

cmd_health() {
  # HTTP-only check — no systemd required.
  echo
  echo "  VoiceAI HTTP Health  [$(date '+%H:%M:%S')]"
  echo
  for svc in "${START_ORDER[@]}"; do
    url="$(_health_url "$svc")"
    printf "  %-12s  " "$svc"
    if [ -z "$url" ]; then
      echo "— (no endpoint)"
    else
      st="$(_http_health "$svc" "$url")"
      [ "$st" = "ONLINE" ] && echo "ONLINE" || echo "offline  ($url)"
    fi
  done
  echo
}

cmd_validate() {
  ADMIN_PY="$ROOT/admin/validate.py"
  [ -f "$ADMIN_PY" ] || {
    echo "ERROR: admin/validate.py not found. Run bootstrap.sh first." >&2; exit 1
  }
  exec python3 "$ADMIN_PY"
}

# ─── DISPATCH ─────────────────────────────────────────────────────────────────
CMD="${1:-status}"
shift || true

case "$CMD" in
  start)    cmd_start   "${1:-all}" ;;
  stop)     cmd_stop    "${1:-all}" ;;
  restart)  cmd_restart "${1:-all}" ;;
  status)   cmd_status  "${1:-all}" ;;
  logs)     cmd_logs    "${1:-}" "$@" ;;
  health)   cmd_health ;;
  validate) cmd_validate ;;
  help|--help|-h)
    cat <<'HELP'
voiceai-ctl.sh — VoiceAI lifecycle controller  v4 final

Usage:
  voiceai-ctl.sh start   [SERVICE|all]
  voiceai-ctl.sh stop    [SERVICE|all]
  voiceai-ctl.sh restart [SERVICE|all]
  voiceai-ctl.sh status  [SERVICE|all]
  voiceai-ctl.sh logs    SERVICE [journalctl args]
  voiceai-ctl.sh health              — HTTP-only, no systemd required
  voiceai-ctl.sh validate            — full installation check

Services:  livekit | llm | stt | tts | qdrant | telemetry | agent

Start order:  livekit → llm → stt → tts → qdrant → telemetry → agent
Stop order:   agent → telemetry → qdrant → tts → stt → llm → livekit

Note: qdrant (memory backbone) must start before agent.

Status detail (inline per service):
  stt    — active model name (reflects hot-reload)
  tts    — engine mode / router phase / VRAM
  qdrant — collection names + vector counts
  agent  — session_active / persona / voice_mode / room / mem=on|off / token_count

═══════════════════════════════════════════════════════════
  WHAT LIVES HERE vs ELSEWHERE
═══════════════════════════════════════════════════════════

This script: lifecycle only (start/stop/restart/status/logs)

Admin ops (use admin/ layer — backend-global):
  python admin/lan_mode.py lan|local|status    — LAN switching
  python admin/tts_switch.py <engine>           — global TTS engine switch
  STT model switch                              — backend HTTP only (/admin/switch_model)
  python admin/context.py                       — LLM context ceiling
  python admin/memory_admin.py init|list|search — Qdrant collection admin
  python admin/web_fetch.py <url>               — safe operator web fetch
  python admin/validate.py                      — full backbone check

Telemetry API (read-only, 127.0.0.1:5900):
  GET /metrics/machine                          — CPU/RAM/GPU
  GET /metrics/services                         — service health
  GET /metrics/processes                        — PID-attributed CPU/RAM/VRAM
  GET /inventory/personas                       — available persona files
  GET /inventory/reference-audio                — Chatterbox voice reference files
  GET /inventory/context                        — LLM model + context ceiling
  GET /inventory/memory                         — Qdrant collection stats

Session voice control (LiveKit RPC — narrow policy):
  set_persona              {"name": "english_teacher"}
  set_session_voice        {"voice": "Aiden", "language": "English", "instruct": ""}
  set_interruption_behavior {"mode": "patient"}

  Policy: ONLY persona / voice+language+instruct / interruption are voice-accessible.
  Do NOT use these for engine params, LLM tuning, or backend switches.

Memory control-plane (explicit LiveKit control-plane RPC — frontend/admin only, not normal session voice control):
  set_memory_enabled       {"enabled": true}
  create_memory_checkpoint {"summary": "...", "session_id": "..."}
  restore_previous_context {"query": "...", "user_id": "..."}
  search_memory            {"query": "...", "limit": 5}

TTS engine field truth table:
  CustomVoice : voice=named-speaker  language=YES  instruct=accepted (optional)
  VoiceDesign : voice=ignored        language=YES  instruct=meaningful
  Chatterbox  : voice→inputs/<stem>.wav  language=passthrough  ref-audio=cloning
  (No engine has 'speed'. response_format is locked to 'wav'.)
HELP
    ;;
  *)
    echo "ERROR: Unknown command '$CMD'" >&2
    echo "  Run: voiceai-ctl.sh help" >&2
    exit 1
    ;;
esac
