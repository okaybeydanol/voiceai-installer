#!/usr/bin/env bash
# ==============================================================================
# 09_install_telemetry_and_admin_surfaces.sh
#
# Responsibility:
#   §10  Telemetry sidecar:
#          venv (Python 3.12), deps (fastapi, uvicorn, psutil, pynvml, httpx)
#          Python source: collectors/machine.py, collectors/processes.py,
#                         collectors/services.py, src/main.py
#          bin/start-telemetry.sh
#   §11  Admin layer (operator-only, loopback, NOT session-voice accessible):
#          admin/__init__.py
#          admin/lan_mode.py
#          admin/tts_switch.py
#          STT switch now lives in the STT service backend HTTP admin endpoint
#          admin/context.py
#          admin/memory_admin.py
#          admin/web_fetch.py
#          admin/validate.py  (updated v4: Qdrant + Ph-1 + hot_swap check)
# ==============================================================================
set -euo pipefail
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$BOOTSTRAP_DIR/00_shared_helpers.sh"

ROOT="${ROOT:-$HOME/ai-projects/voiceai}"
TELEMETRY_PYTHON="${TELEMETRY_PYTHON:-3.12}"
PORT_QDRANT_REST="${PORT_QDRANT_REST:-6333}"
PORT_LIVEKIT="${PORT_LIVEKIT:-7880}"; PORT_LLM="${PORT_LLM:-5000}"
PORT_STT="${PORT_STT:-5100}"; PORT_TTS_ROUTER="${PORT_TTS_ROUTER:-5200}"
PORT_AGENT_ADMIN="${PORT_AGENT_ADMIN:-5800}"; PORT_TELEMETRY="${PORT_TELEMETRY:-5900}"
PORT_LIVEKIT_RTC="${PORT_LIVEKIT_RTC:-7881}"

TELEM_DIR="$ROOT/telemetry"
TELEM_SRC="$TELEM_DIR/src"
TELEM_COL="$TELEM_SRC/collectors"
mkdir -p "$TELEM_SRC" "$TELEM_COL"

# ==============================================================================
# §10 — TELEMETRY VENV + DEPS
# ==============================================================================
_banner "09 / TELEMETRY SIDECAR — venv + deps"

_venv_version_ok "$TELEM_DIR/.venv" "$TELEMETRY_PYTHON" \
  && _skip "Telemetry .venv" \
  || uv venv "$TELEM_DIR/.venv" -p "$TELEMETRY_PYTHON"

TELEM_DEPS_MARKER="$TELEM_DIR/.bootstrap_deps_ok"
if [ ! -f "$TELEM_DEPS_MARKER" ]; then
  # shellcheck source=/dev/null
  . "$TELEM_DIR/.venv/bin/activate"
  uv pip install -U "fastapi>=0.115" "uvicorn[standard]>=0.30" \
    "psutil>=5.9" "pynvml>=11.5" "httpx>=0.27" pyyaml
  deactivate; touch "$TELEM_DEPS_MARKER"; _ok "Telemetry deps installed"
else _skip "Telemetry deps"; fi

# ==============================================================================
# §10 — TELEMETRY PYTHON SOURCE
# ==============================================================================
_banner "09 / TELEMETRY SIDECAR — Python source"

cat > "$TELEM_SRC/__init__.py" <<'PYEOF'
PYEOF
cat > "$TELEM_COL/__init__.py" <<'PYEOF'
PYEOF

# ── collectors/machine.py ─────────────────────────────────────────────────────
cat > "$TELEM_COL/machine.py" <<'PYEOF'
"""Machine metrics: CPU/RAM via psutil, GPU via pynvml (optional)."""
from __future__ import annotations
import logging, time
from typing import Any
import psutil
log = logging.getLogger("voiceai.telemetry.machine")
_nvml_ok = False; _nvml_handle = None

def _init_nvml() -> None:
    global _nvml_ok, _nvml_handle
    try:
        import pynvml; pynvml.nvmlInit()
        _nvml_handle = pynvml.nvmlDeviceGetHandleByIndex(0); _nvml_ok = True
        log.info("[MACHINE] pynvml OK — GPU: %s", pynvml.nvmlDeviceGetName(_nvml_handle))
    except Exception as e: log.info("[MACHINE] pynvml unavailable: %s", e)

def init() -> None: psutil.cpu_percent(interval=None); _init_nvml()

def collect() -> dict[str, Any]:
    cpu = psutil.cpu_percent(interval=None)
    try: load = round(psutil.getloadavg()[0], 2)
    except: load = None
    vm = psutil.virtual_memory(); gpu = None
    if _nvml_ok and _nvml_handle:
        try:
            import pynvml
            mem  = pynvml.nvmlDeviceGetMemoryInfo(_nvml_handle)
            util = pynvml.nvmlDeviceGetUtilizationRates(_nvml_handle)
            name = pynvml.nvmlDeviceGetName(_nvml_handle)
            try: temp = pynvml.nvmlDeviceGetTemperature(_nvml_handle, pynvml.NVML_TEMPERATURE_GPU)
            except: temp = None
            gpu = {"name": name, "util_percent": util.gpu,
                   "vram_used_gb":  round(mem.used  / 1e9, 2),
                   "vram_free_gb":  round(mem.free  / 1e9, 2),
                   "vram_total_gb": round(mem.total / 1e9, 2),
                   "temp_c": temp}
        except Exception as e: log.warning("[MACHINE] GPU collect failed: %s", e)
    return {"ts": time.time(), "cpu_percent": cpu, "load_avg_1m": load,
            "ram_used_gb":  round(vm.used  / 1e9, 2),
            "ram_total_gb": round(vm.total / 1e9, 2),
            "ram_percent": vm.percent, "gpu": gpu}
PYEOF

# ── collectors/processes.py — v4: Qdrant ports included ──────────────────────
cat > "$TELEM_COL/processes.py" <<'PYEOF'
"""Ph-8: PID-attributed per-process CPU/RAM/VRAM. Graceful on AccessDenied/NoSuchProcess."""
from __future__ import annotations
import logging
from typing import Any, Optional
import psutil
log = logging.getLogger("voiceai.telemetry.processes")

_PORT_SERVICE: dict[int, str] = {
    5000: "llm",       5100: "stt",
    5200: "tts_router",5201: "tts_worker",
    5800: "agent",     5900: "telemetry",
    6333: "qdrant",    6334: "qdrant_grpc",   # v4: Qdrant
    7880: "livekit",
}

_nvml_handle = None
def _init_nvml() -> None:
    global _nvml_handle
    try:
        import pynvml; pynvml.nvmlInit()
        _nvml_handle = pynvml.nvmlDeviceGetHandleByIndex(0)
    except Exception: _nvml_handle = None
_init_nvml()

def _find_port_pids() -> dict[int, int]:
    port_pid: dict[int, int] = {}
    try:
        for conn in psutil.net_connections(kind="inet"):
            if conn.status == "LISTEN" and conn.laddr.port in _PORT_SERVICE and conn.pid:
                port_pid[conn.laddr.port] = conn.pid
    except (psutil.AccessDenied, OSError) as exc:
        log.debug("[PROCESSES] net_connections: %s", exc)
    return port_pid

def _per_process_vram(pid: int) -> Optional[int]:
    if _nvml_handle is None: return None
    try:
        import pynvml
        for p in pynvml.nvmlDeviceGetComputeRunningProcesses(_nvml_handle):
            if p.pid == pid: return int(p.usedGpuMemory)
        return None
    except Exception: return None

def _process_info(pid: int) -> dict[str, Any]:
    try:
        proc = psutil.Process(pid)
        cpu  = proc.cpu_percent(interval=None); mem = proc.memory_info()
        vram = _per_process_vram(pid)
        return {"pid": pid, "cpu_percent": cpu,
                "rss_mb": round(mem.rss / 1e6, 1), "vms_mb": round(mem.vms / 1e6, 1),
                "vram_mb": round(vram / 1e6, 1) if vram is not None else None}
    except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess): return {}
    except Exception as exc: log.debug("[PROCESSES] PID %d: %s", pid, exc); return {}

def seed_cpu_baseline() -> None:
    for pid in set(_find_port_pids().values()):
        try: psutil.Process(pid).cpu_percent(interval=None)
        except Exception: pass

def collect() -> dict[str, Any]:
    port_pid = _find_port_pids(); result: dict[str, Any] = {}; seen: set[str] = set()
    for port, service in _PORT_SERVICE.items():
        if service in seen: continue   # skip grpc alias
        pid = port_pid.get(port)
        result[service] = _process_info(pid) if pid else None
        seen.add(service)
    return result
PYEOF

# ── collectors/services.py ────────────────────────────────────────────────────
cat > "$TELEM_COL/services.py" <<'PYEOF'
"""Service health polling. Truthful pass-through only."""
from __future__ import annotations
import asyncio, logging, time, socket
from typing import Any
import httpx
log = logging.getLogger("voiceai.telemetry.services")

_SERVICES: dict[str, "str | None"] = {
    "livekit":    "tcp://127.0.0.1:7880",
    "llm":        "http://127.0.0.1:5000/v1/models",
    "stt":        "http://127.0.0.1:5100/health",
    "tts_router": "http://127.0.0.1:5200/health",
    "agent":      "http://127.0.0.1:5800/health",
    "qdrant":     "http://127.0.0.1:6333/",
    "telemetry":  "http://127.0.0.1:5900/health",
}
_T = httpx.Timeout(connect=1.5, read=2.0, write=2.0, pool=2.0)

def _tcp_open(host: str, port: int, timeout: float = 2.0) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False

async def collect_all(client: httpx.AsyncClient) -> dict[str, Any]:
    tasks = {n: asyncio.create_task(_poll(n, u, client)) for n, u in _SERVICES.items()}
    return {n: await t for n, t in tasks.items()}

async def _poll(name: str, url: "str | None", client: httpx.AsyncClient) -> dict[str, Any]:
    if url is None: return {"online": False, "note": "No HTTP health endpoint."}
    t0 = time.perf_counter()
    try:
        if url.startswith("tcp://"):
            hp = url[len("tcp://"): ]
            host, port = hp.rsplit(":", 1)
            ok = _tcp_open(host, int(port), timeout=2.0)
            return {"online": ok, "latency_ms": round((time.perf_counter() - t0) * 1000, 1)}

        r = await client.get(url, timeout=_T)
        ms = round((time.perf_counter() - t0) * 1000, 1)
        try: body = r.json()
        except: body = {}
        res: dict = {"online": r.status_code in (200, 204), "latency_ms": ms}
        if res["online"] and body: res["data"] = body
        return res
    except (httpx.ConnectError, httpx.TimeoutException):
        return {"online": False, "latency_ms": round((time.perf_counter() - t0) * 1000, 1)}
    except Exception as e: return {"online": False, "error": str(e)}
PYEOF

# ── src/main.py ───────────────────────────────────────────────────────────────
cat > "$TELEM_SRC/main.py" <<'PYEOF'
#!/usr/bin/env python3
"""VoiceAI Telemetry Sidecar v4. Port 5900, 127.0.0.1 only."""
from __future__ import annotations
import asyncio, logging, logging.config, os, re, time
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any
import httpx, uvicorn
from fastapi import FastAPI
from .collectors import machine as mc, processes as procs_col, services as sc

_LOG = {
    "version": 1, "disable_existing_loggers": False,
    "formatters": {"plain": {"format": "%(asctime)s  %(levelname)-8s  %(name)-35s  %(message)s",
                             "datefmt": "%H:%M:%S"}},
    "handlers":  {"stdout": {"class": "logging.StreamHandler", "stream": "ext://sys.stdout",
                             "formatter": "plain"}},
    "root": {"level": "INFO", "handlers": ["stdout"]},
    "loggers": {"uvicorn.access": {"level": "WARNING"}},
}
logging.config.dictConfig(_LOG)
log = logging.getLogger("voiceai.telemetry.main")

HOST   = os.environ.get("TELEMETRY_HOST",           "127.0.0.1")
PORT   = int(os.environ.get("TELEMETRY_PORT",       "5900"))
POLL_S = float(os.environ.get("TELEMETRY_POLL_INTERVAL", "5.0"))
STALE  = float(os.environ.get("TELEMETRY_STALE_THRESHOLD", "15.0"))
VOICEAI_ROOT = Path(os.environ.get("VOICEAI_ROOT", str(Path.home() / "ai-projects" / "voiceai")))

_snap: dict[str, Any] = {}; _t0: float = 0.0

async def _poll_loop(client: httpx.AsyncClient) -> None:
    global _snap
    while True:
        try:
            _snap = {"ts": time.time(), "stale": False,
                     "machine":   mc.collect(),
                     "services":  await sc.collect_all(client),
                     "processes": procs_col.collect()}
        except Exception as exc:
            log.warning("[POLL] %s", exc)
            if _snap: _snap["stale"] = True
        await asyncio.sleep(POLL_S)

@asynccontextmanager
async def lifespan(app: FastAPI):
    global _t0; _t0 = time.time(); mc.init(); procs_col.seed_cpu_baseline()
    client = httpx.AsyncClient(timeout=httpx.Timeout(3.0))
    task = asyncio.create_task(_poll_loop(client), name="telemetry-poll")
    log.info("Telemetry v4  bind=%s:%d  poll=%.1fs", HOST, PORT, POLL_S)
    yield
    task.cancel()
    try: await task
    except asyncio.CancelledError: pass
    await client.aclose()

def create_app() -> FastAPI:
    app = FastAPI(title="VoiceAI Telemetry", version="4.0.0", lifespan=lifespan)

    @app.get("/health")
    async def health(): return {"status": "ok", "uptime_s": round(time.time() - _t0, 1)}

    @app.get("/metrics")
    async def metrics():
        if not _snap: return {"status": "initializing", "stale": True}
        s = dict(_snap); s["stale"] = (time.time() - s.get("ts", 0)) > STALE
        s["uptime_s"] = round(time.time() - _t0, 1); return s

    @app.get("/metrics/machine")
    async def metrics_machine(): return _snap.get("machine", {"status": "initializing"})

    @app.get("/metrics/services")
    async def metrics_services():
        if not _snap: return {"status": "initializing"}
        return {"stale": (time.time() - _snap.get("ts", 0)) > STALE, "services": _snap.get("services", {})}

    @app.get("/metrics/processes")
    async def metrics_processes():
        if not _snap: return {"status": "initializing"}
        return {"stale": (time.time() - _snap.get("ts", 0)) > STALE, "processes": _snap.get("processes", {})}

    # ── Inventory endpoints ───────────────────────────────────────────────────

    @app.get("/inventory/personas")
    async def inventory_personas():
        pdir = VOICEAI_ROOT / "agent" / "personas"
        if not pdir.is_dir(): return {"personas": [], "error": f"Not found: {pdir}"}
        result = []
        for f in sorted(pdir.glob("*.md")):
            try:
                content = f.read_text(encoding="utf-8")
                m = re.match(r'^---\s*\n.*?name:\s*(\S+).*?\n---', content, re.DOTALL)
                result.append({"name": f.stem,
                                "display_name": m.group(1) if m else f.stem,
                                "filename": f.name})
            except Exception: result.append({"name": f.stem, "filename": f.name})
        return {"personas": result, "count": len(result)}

    @app.get("/inventory/reference-audio")
    async def inventory_reference_audio():
        idir = VOICEAI_ROOT / "inputs"
        if not idir.is_dir(): return {"voices": [], "error": f"Not found: {idir}"}
        exts = {".wav", ".mp3", ".flac", ".ogg"}
        result = [{"voice": f.stem, "filename": f.name, "size_kb": round(f.stat().st_size / 1024, 1)}
                  for f in sorted(idir.iterdir()) if f.suffix.lower() in exts and f.is_file()]
        return {"voices": result, "count": len(result), "directory": str(idir)}

    @app.get("/inventory/context")
    async def inventory_context():
        """Ph-9: LLM model info + context ceiling from TabbyAPI."""
        try:
            async with httpx.AsyncClient(timeout=3.0) as client:
                r = await client.get("http://127.0.0.1:5000/v1/model")
                if r.status_code != 200: return {"online": False, "model": None, "max_seq_len": None}
                data = r.json()
                model_id = data.get("id") or data.get("name") or data.get("model_name")
                params   = data.get("parameters") or data.get("properties") or {}
                max_seq  = params.get("max_seq_len") or params.get("context_length")
                return {"online": True, "model": model_id, "max_seq_len": max_seq, "raw": data}
        except Exception as exc:
            return {"online": False, "model": None, "max_seq_len": None, "error": str(exc)}

    @app.get("/inventory/memory")
    async def inventory_memory():
        """Qdrant health + collection stats."""
        try:
            async with httpx.AsyncClient(timeout=3.0) as client:
                r = await client.get("http://127.0.0.1:6333/collections")
                if r.status_code != 200: return {"online": False}
                colls = r.json().get("result", {}).get("collections", [])
                return {"online": True,
                        "collections": {c["name"]: c.get("vectors_count", 0) for c in colls}}
        except Exception as exc:
            return {"online": False, "error": str(exc)}

    return app

app = create_app()
if __name__ == "__main__":
    uvicorn.run("src.main:app", host=HOST, port=PORT,
                reload=False, log_config=None, access_log=False)
PYEOF

cat > "$ROOT/bin/start-telemetry.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
. "$HOME/.config/voiceai/env.sh"
cd "$VOICEAI_ROOT/telemetry"
echo "[TELEMETRY] Starting on 127.0.0.1:5900 …"
exec "$VOICEAI_ROOT/telemetry/.venv/bin/python" -m src.main
SCRIPT
chmod +x "$ROOT/bin/start-telemetry.sh"
_ok "Telemetry sidecar written (v4: Qdrant + memory inventory)"

# ==============================================================================
# §11 — ADMIN LAYER
# ==============================================================================
_banner "09 / ADMIN LAYER"

cat > "$ROOT/admin/__init__.py" <<'PYEOF'
PYEOF

# ── admin/lan_mode.py ─────────────────────────────────────────────────────────
cat > "$ROOT/admin/lan_mode.py" <<'PYEOF'
#!/usr/bin/env python3
"""VoiceAI Admin — LAN mode control. Template-based. No 0.0.0.0/0 fallback."""
from __future__ import annotations
import argparse, os, re, stat, subprocess, sys, tempfile
from pathlib import Path

ROOT    = Path(os.environ.get("VOICEAI_ROOT", str(Path.home() / "ai-projects" / "voiceai")))
CFG_DIR = ROOT / "config"; LK_DIR = ROOT / "livekit"; LK_YAML = LK_DIR / "livekit.yaml"
LAN_TMPL = CFG_DIR / "livekit-lan.yaml.template"
LO_TMPL  = CFG_DIR / "livekit-loopback.yaml.template"
LAN_IP_F = CFG_DIR / "lan_ip.txt"
ENV_SH   = Path.home() / ".config" / "voiceai" / "env.sh"
PORT_LK     = int(os.environ.get("PORT_LIVEKIT",     "7880"))
PORT_LK_RTC = int(os.environ.get("PORT_LIVEKIT_RTC", "7881"))

def _creds():
    text = ENV_SH.read_text(encoding="utf-8")
    k = re.search(r'LIVEKIT_API_KEY="([^"]+)"',    text)
    s = re.search(r'LIVEKIT_API_SECRET="([^"]+)"',  text)
    if not k or not s: raise SystemExit("ERROR: LIVEKIT credentials not found in env.sh.")
    return k.group(1), s.group(1)

def _write_atomic(content, dst):
    fd, tmp = tempfile.mkstemp(dir=dst.parent, prefix=".livekit.yaml.")
    try:
        os.fchmod(fd, stat.S_IRUSR | stat.S_IWUSR)
        with os.fdopen(fd, "w", encoding="utf-8") as fh: fh.write(content)
        os.replace(tmp, dst); os.chmod(dst, stat.S_IRUSR | stat.S_IWUSR)
    except Exception:
        try: os.unlink(tmp)
        except: pass
        raise

def _detect_lan_ip():
    try:
        out = subprocess.check_output(["ip", "route", "get", "8.8.8.8"],
                                      stderr=subprocess.DEVNULL, text=True)
        m = re.search(r'\bsrc\s+(\d+\.\d+\.\d+\.\d+)', out)
        if m and not m.group(1).startswith("127."): return m.group(1)
    except Exception: pass
    raise SystemExit("Cannot auto-detect LAN IP. Use --ip <ip>")

def _detect_subnet(ip):
    try:
        out = subprocess.check_output(["ip", "route"], stderr=subprocess.DEVNULL, text=True)
        for line in out.splitlines():
            if "/" in line and ip.rsplit(".", 1)[0] in line:
                return line.split()[0]
    except Exception: pass
    return ip.rsplit(".", 1)[0] + ".0/24"

def _render_lan(ip):
    key, sec = _creds()
    return (LAN_TMPL.read_text()
            .replace("__PORT_LIVEKIT__",     str(PORT_LK))
            .replace("__PORT_LIVEKIT_RTC__", str(PORT_LK_RTC))
            .replace("__LAN_IP__", ip)
            + f'\nkeys:\n  "{key}": "{sec}"\n')

def _render_loopback():
    key, sec = _creds()
    return (LO_TMPL.read_text()
            .replace("${PORT_LIVEKIT}",     str(PORT_LK))
            .replace("${PORT_LIVEKIT_RTC}", str(PORT_LK_RTC))
            + f'\nkeys:\n  "{key}": "{sec}"\n')

def _ufw_lan(subnet):
    try: subprocess.run(["sudo", "ufw", "allow", "in", "from", subnet,
                          "to", "any", "port", str(PORT_LK)], check=False)
    except Exception: pass

def _ufw_revert():
    try:
        subprocess.run(["sudo", "ufw", "deny", "in", "to", "any", "port", str(PORT_LK)], check=False)
        subprocess.run(["sudo", "ufw", "allow", "in", "on", "lo", "to", "any", "port", str(PORT_LK)], check=False)
    except Exception: pass

def _restart_livekit():
    try: subprocess.run(["systemctl", "--user", "restart", "voiceai-livekit.service"], check=False)
    except Exception: pass

def main():
    p = argparse.ArgumentParser(); p.add_argument("command", choices=["lan", "local", "status", "detect"])
    p.add_argument("--ip")
    args = p.parse_args()
    if args.command == "lan":
        ip = args.ip or _detect_lan_ip(); subnet = _detect_subnet(ip)
        _write_atomic(_render_lan(ip), LK_YAML); LAN_IP_F.write_text(ip, encoding="utf-8")
        _ufw_lan(subnet); _restart_livekit()
        print(f"\n  LAN MODE ACTIVE  LAN IP={ip}  Phone URL: ws://{ip}:{PORT_LK}")
        print("  IMPORTANT: LLM/STT/TTS/Qdrant remain loopback-only.")
    elif args.command == "local":
        _write_atomic(_render_loopback(), LK_YAML); LAN_IP_F.unlink(missing_ok=True)
        _ufw_revert(); _restart_livekit(); print("  LOCAL MODE — LiveKit loopback only.")
    elif args.command == "status":
        if LAN_IP_F.is_file(): print(f"  ACTIVE  IP={LAN_IP_F.read_text().strip()}")
        else: print("  INACTIVE (loopback-only)")
    elif args.command == "detect": print(_detect_lan_ip())

if __name__ == "__main__": main()
PYEOF

# ── admin/tts_switch.py ───────────────────────────────────────────────────────
cat > "$ROOT/admin/tts_switch.py" <<'PYEOF'
#!/usr/bin/env python3
"""VoiceAI Admin — Global TTS engine switch. Backend-admin only. NOT session-voice accessible."""
import json, os, sys, urllib.request, urllib.error
ROUTER = os.environ.get("TTS_ROUTER_URL", "http://127.0.0.1:5200")
VALID  = frozenset({"customvoice", "voicedesign", "chatterbox"})

def switch(mode):
    if mode not in VALID: raise SystemExit(f"Invalid mode '{mode}'. Valid: {sorted(VALID)}")
    req = urllib.request.Request(f"{ROUTER}/admin/switch_model",
                                 data=json.dumps({"mode": mode}).encode(),
                                 headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=10) as r: return json.loads(r.read())
    except urllib.error.HTTPError as e: raise SystemExit(f"HTTP {e.code}: {e.read().decode()}")
    except urllib.error.URLError  as e: raise SystemExit(f"Router unreachable: {e.reason}")

def status():
    try:
        with urllib.request.urlopen(f"{ROUTER}/health", timeout=5) as r: return json.loads(r.read())
    except Exception as e: return {"online": False, "error": str(e)}

if __name__ == "__main__":
    if len(sys.argv) < 2: print(f"Usage: tts_switch.py <mode|status>"); sys.exit(1)
    cmd = sys.argv[1].strip().lower()
    if cmd == "status": print(json.dumps(status(), indent=2))
    else:               print(json.dumps(switch(cmd), indent=2))
PYEOF

# ── admin/context.py ──────────────────────────────────────────────────────────
cat > "$ROOT/admin/context.py" <<'PYEOF'
#!/usr/bin/env python3
"""Ph-9: LLM context ceiling + token usage from TabbyAPI."""
import json, sys, urllib.request, urllib.error
LLM_BASE = "http://127.0.0.1:5000"

def get_model_info() -> dict:
    try:
        with urllib.request.urlopen(f"{LLM_BASE}/v1/model", timeout=5) as r:
            data = json.loads(r.read())
        params  = data.get("parameters") or data.get("properties") or {}
        max_seq = params.get("max_seq_len") or params.get("context_length")
        model_id= data.get("id") or data.get("name") or data.get("model_name")
        return {"online": True, "model": model_id, "max_seq_len": max_seq, "raw": data}
    except urllib.error.URLError as e: return {"online": False, "error": str(e)}
    except Exception as e:             return {"online": False, "error": str(e)}

if __name__ == "__main__":
    print(json.dumps(get_model_info(), indent=2))
PYEOF

# ── admin/memory_admin.py ─────────────────────────────────────────────────────
cat > "$ROOT/admin/memory_admin.py" <<'PYEOF'
#!/usr/bin/env python3
"""
VoiceAI Admin — Qdrant memory admin operations.

Usage:
  python memory_admin.py status          — collections health
  python memory_admin.py list            — list collections + counts
  python memory_admin.py delete <type>   — delete a collection (episodic|facts|chunks)
  python memory_admin.py init            — create/verify all collections
  python memory_admin.py search <query>  — search across all collections

Does NOT auto-ingest web content.
Does NOT perform autonomous summarization.
All ops are explicit operator-driven.
"""
import json, os, sys, urllib.request, urllib.error
from pathlib import Path

QDRANT_URL  = os.environ.get("QDRANT_URL", "http://127.0.0.1:6333")
COLLECTIONS = {"episodic": "voiceai_episodic", "facts": "voiceai_facts", "chunks": "voiceai_chunks"}

def _get(path):
    try:
        with urllib.request.urlopen(f"{QDRANT_URL}{path}", timeout=5) as r: return json.loads(r.read())
    except urllib.error.URLError as e: raise SystemExit(f"Qdrant unreachable: {e.reason}")

def _post(path, body):
    data = json.dumps(body).encode()
    req  = urllib.request.Request(f"{QDRANT_URL}{path}", data=data,
                                   headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=10) as r: return json.loads(r.read())
    except urllib.error.HTTPError as e: raise SystemExit(f"HTTP {e.code}: {e.read().decode()}")
    except urllib.error.URLError  as e: raise SystemExit(f"Qdrant unreachable: {e.reason}")

def cmd_status():  print(json.dumps(_get("/"), indent=2))

def cmd_list():
    colls = _get("/collections").get("result", {}).get("collections", [])
    if not colls: print("  No collections found."); return
    for c in colls:
        name = c.get("name", "?")
        cnt  = _get(f"/collections/{name}").get("result", {}).get("vectors_count", "?")
        print(f"  {name:30s}  vectors: {cnt}")

def cmd_delete(memory_type):
    if memory_type not in COLLECTIONS:
        raise SystemExit(f"Unknown type '{memory_type}'. Valid: {list(COLLECTIONS)}")
    coll    = COLLECTIONS[memory_type]
    confirm = input(f"DELETE collection '{coll}'? This is IRREVERSIBLE. Type 'yes' to confirm: ")
    if confirm.strip().lower() != "yes": print("Aborted."); return
    req = urllib.request.Request(f"{QDRANT_URL}/collections/{coll}", method="DELETE")
    try:
        with urllib.request.urlopen(req, timeout=10) as r: print(json.dumps(json.loads(r.read()), indent=2))
    except urllib.error.HTTPError as e: raise SystemExit(f"HTTP {e.code}: {e.read().decode()}")

def cmd_init():
    """Create collections if not present (same logic as agent/src/memory.py)."""
    EMBEDDING_DIM = int(os.environ.get("VOICEAI_EMBEDDING_DIM", "384"))
    for mtype, coll in COLLECTIONS.items():
        existing = [c["name"] for c in _get("/collections").get("result", {}).get("collections", [])]
        if coll in existing: print(f"  EXISTS: {coll}"); continue
        body = {"vectors": {"size": EMBEDDING_DIM, "distance": "Cosine"}}
        _post(f"/collections/{coll}", body); print(f"  CREATED: {coll}")

def cmd_search(query):
    if not query: raise SystemExit("query required")
    # stdlib-only search — no fastembed available here
    print("NOTE: Full search requires agent venv. This prints collection stats only.")
    cmd_list()

def main():
    if len(sys.argv) < 2: print(__doc__); sys.exit(1)
    cmd = sys.argv[1].strip().lower()
    dispatch = {
        "status": cmd_status, "list": cmd_list, "init": cmd_init,
        "delete": lambda: cmd_delete(sys.argv[2] if len(sys.argv) > 2 else ""),
        "search": lambda: cmd_search(" ".join(sys.argv[2:]) if len(sys.argv) > 2 else ""),
    }
    if cmd not in dispatch: print(f"Unknown command '{cmd}'."); print(__doc__); sys.exit(1)
    dispatch[cmd]()

if __name__ == "__main__": main()
PYEOF

# ── admin/web_fetch.py ────────────────────────────────────────────────────────
cat > "$ROOT/admin/web_fetch.py" <<'PYEOF'
#!/usr/bin/env python3
"""
VoiceAI Admin — Safe operator-triggered web fetch.

Safety model (Ph-10):
  - Plain text only — no JS, no browser automation, no script execution.
  - No auto-write to Qdrant. Operator must explicitly save if desired.
  - Content is shown to stdout for inspection.
  - Size-limited. http/https only.

Usage:
  python web_fetch.py <url> [--max-chars 8000]
  python web_fetch.py <url> --save-memory episodic  # explicit operator opt-in
"""
import argparse, os, re, sys, urllib.request, urllib.error
from html.parser import HTMLParser

MAX_CHARS_DEFAULT = int(os.environ.get("WEB_FETCH_MAX_CHARS", "8000"))
TIMEOUT           = float(os.environ.get("WEB_FETCH_TIMEOUT_S", "10.0"))

class _TextExtractor(HTMLParser):
    _SKIP = {"script", "style", "noscript", "head", "meta", "link", "nav", "footer"}
    def __init__(self): super().__init__(); self._skip = 0; self._parts: list[str] = []
    def handle_starttag(self, tag, attrs):
        if tag.lower() in self._SKIP: self._skip += 1
    def handle_endtag(self, tag):
        if tag.lower() in self._SKIP and self._skip > 0: self._skip -= 1
    def handle_data(self, data):
        if self._skip == 0:
            s = data.strip()
            if s: self._parts.append(s)
    def get_text(self) -> str:
        return re.sub(r'\s+', ' ', ' '.join(self._parts)).strip()

def _fetch(url: str, max_chars: int) -> str:
    if not re.match(r'^https?://', url.strip(), re.IGNORECASE):
        raise ValueError(f"Only http/https supported, got: {url!r}")
    headers = {"User-Agent": "VoiceAI-SafeFetch/1.0 (plain-text-only; no-js)",
               "Accept":     "text/html,text/plain;q=0.9,*/*;q=0.8"}
    req = urllib.request.Request(url.strip(), headers=headers)
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        ct  = r.headers.get("content-type", "")
        raw = r.read().decode(r.headers.get_content_charset("utf-8"), errors="replace")
    if "html" in ct:
        parser = _TextExtractor(); parser.feed(raw); text = parser.get_text()
    else:
        text = raw.strip()
    text = text[:max_chars]
    if len(text) == max_chars: text += f"\n[… truncated at {max_chars} chars]"
    return text

def main():
    p = argparse.ArgumentParser(description="Safe web fetch (plain text only)")
    p.add_argument("url"); p.add_argument("--max-chars", type=int, default=MAX_CHARS_DEFAULT)
    p.add_argument("--save-memory", choices=["episodic", "facts", "chunks"],
                   help="Explicitly save fetched text to this memory tier (operator opt-in).")
    p.add_argument("--user-id", default="operator")
    args = p.parse_args()
    try: text = _fetch(args.url, args.max_chars)
    except Exception as exc: print(f"ERROR: {exc}", file=sys.stderr); sys.exit(1)
    print(f"=== Web content from {args.url} ({len(text)} chars) ==="); print(text)
    if args.save_memory:
        print(f"\n[Saving to memory tier: {args.save_memory}]")
        try:
            sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "agent"))
            import asyncio; from src import memory as mem
            point_id = asyncio.run(mem.upsert(
                memory_type=args.save_memory, text=text, user_id=args.user_id,
                speaker="operator", tags=["web-fetch"]))
            print(f"  Saved to '{args.save_memory}' collection. ID: {point_id}")
        except Exception as exc:
            print(f"  Save failed: {exc}")
            print("  (Activate agent venv: . agent/venv/bin/activate)")

if __name__ == "__main__": main()
PYEOF

# ── admin/validate.py — v4: Qdrant + Ph-1 + hot_swap check ───────────────────
cat > "$ROOT/admin/validate.py" <<'PYEOF'
#!/usr/bin/env python3
"""VoiceAI Admin — Backbone validation v4. Exit 0 = no critical failures."""
from __future__ import annotations
import os, stat, sys, urllib.request, urllib.error
from pathlib import Path

ROOT = Path(os.environ.get("VOICEAI_ROOT", str(Path.home() / "ai-projects" / "voiceai")))
PASS = WARN = FAIL = 0

def _p(msg): global PASS; PASS += 1; print(f"  [PASS] {msg}")
def _w(msg): global WARN; WARN += 1; print(f"  [WARN] {msg}", file=sys.stderr)
def _f(msg): global FAIL; FAIL += 1; print(f"  [FAIL] {msg}", file=sys.stderr)
def _s(section): print(f"\n── {section}")

def _venv(path, label):
    if (path / "bin" / "python").is_file(): _p(f"{label} venv present")
    else: _f(f"{label} venv missing: {path}")

def _perm600(path, label):
    m = path.stat().st_mode & 0o777
    if m == 0o600: _p(f"{label} permissions 600")
    else: _w(f"{label} permissions {oct(m)} (expected 600)")

def _health(url, label):
    try:
        with urllib.request.urlopen(url, timeout=3) as r:
            _p(f"{label} responding ({r.status})")
    except Exception: _w(f"{label} not responding ({url})")

CANONICAL_STT = {"faster-whisper-tiny", "faster-whisper-tiny.en", "faster-whisper-base",
                 "faster-whisper-base.en", "faster-whisper-small", "faster-whisper-small.en",
                 "faster-whisper-medium", "faster-whisper-medium.en"}
NON_CANONICAL_STT = {"faster-whisper-large-v3", "faster-whisper-large-v2"}

print("=" * 56); print("  VoiceAI Backbone Validation  v4"); print("=" * 56)

_s("Directory tree")
for d in ["bin", "livekit", "llm", "stt", "tts", "agent", "admin",
          "systemd", "config", "telemetry", "tools/downloaders", "memory"]:
    if (ROOT / d).is_dir(): _p(d)
    else: _f(f"Missing directory: {d}")

_s("Environment")
env_sh = Path.home() / ".config" / "voiceai" / "env.sh"
if env_sh.is_file():
    _perm600(env_sh, "env.sh")
    text = env_sh.read_text()
    for var in ("VOICEAI_ROOT", "LIVEKIT_API_KEY", "LIVEKIT_API_SECRET"):
        if var in text: _p(f"env.sh has {var}")
        else: _f(f"env.sh missing {var}")
else: _f("env.sh not found")

_s("LiveKit")
lk_bin = ROOT / "livekit" / "livekit-server"
if lk_bin.is_file(): _p(f"livekit-server present")
else: _f("livekit-server missing")
lk_yaml = ROOT / "livekit" / "livekit.yaml"
if lk_yaml.is_file(): _perm600(lk_yaml, "livekit.yaml")
else: _f("livekit.yaml missing")

_s("Qdrant (v4 memory backbone)")
qdrant_bin = ROOT / "bin" / "qdrant"
if qdrant_bin.is_file(): _p("qdrant binary present")
else: _f("qdrant binary missing")
qdrant_cfg = ROOT / "memory" / "config.yaml"
if qdrant_cfg.is_file(): _p("Qdrant config.yaml present")
else: _f("Qdrant config.yaml missing")

_s("LLM (TabbyAPI)")
_venv(ROOT / "llm" / "tabbyAPI" / "venv", "TabbyAPI")
llm_m = ROOT / "models" / "llm"
if llm_m.is_dir() and any(llm_m.iterdir()): _p("LLM models present")
else: _w("LLM models empty")

_s("STT (Faster-Whisper)")
_venv(ROOT / "stt" / "faster-whisper-service" / "venv", "STT")
if (ROOT / "stt" / "faster-whisper-service" / "src" / "holder.py").is_file():
    _p("holder.py present (Ph-1 reload)")
else: _f("holder.py missing")
stt_cfg_path = ROOT / "stt" / "faster-whisper-service" / "config.yml"
if stt_cfg_path.is_file():
    try:
        import yaml
        with stt_cfg_path.open() as f: sc = yaml.safe_load(f)
        mn = sc.get("model", {}).get("model_name", "")
        nw = sc.get("model", {}).get("num_workers", 0)
        ct = sc.get("model", {}).get("cpu_threads", 0)
        if mn in CANONICAL_STT:       _p(f"STT model: {mn} (canonical)")
        elif mn in NON_CANONICAL_STT: _f(f"STT model: {mn} — non-canonical")
        else:                         _w(f"STT model: {mn}")
        if nw == 2 and ct == 8: _p(f"STT CPU tuning: workers={nw} threads={ct}")
        else:                   _w(f"STT CPU tuning: workers={nw} threads={ct} (expected 2/8)")
    except Exception as e: _w(f"STT config parse: {e}")
else: _f("STT config.yml not found")
stt_m = ROOT / "models" / "stt"
if stt_m.is_dir() and any(stt_m.iterdir()): _p("STT models present")
else: _w("STT models empty")

_s("TTS")
_venv(ROOT / "tts" / "repos" / "router" / ".venv", "TTS Router")
_venv(ROOT / "tts" / "repos" / "qwen3-17b" / ".venv", "TTS Qwen3")
_venv(ROOT / "tts" / "repos" / "chatterbox" / ".venv", "TTS Chatterbox")
tts_m = ROOT / "models" / "tts"
if tts_m.is_dir() and any(tts_m.iterdir()): _p("TTS models present")
else: _w("TTS models empty")

_s("Reference Audio (Chatterbox)")
# Ph-1: no hardcoded prompt.wav check — discover from inputs/ directory
idir = ROOT / "inputs"
if idir.is_dir():
    exts = {".wav", ".mp3", ".flac", ".ogg"}
    refs = [f for f in idir.iterdir() if f.suffix.lower() in exts and f.is_file()]
    if refs: _p(f"Reference audio files present: {[f.name for f in refs[:5]]}{'...' if len(refs)>5 else ''}")
    else:    _w("No audio files in inputs/ — Chatterbox will synthesize without cloning")
else: _w("inputs/ directory not found")

_s("Agent")
_venv(ROOT / "agent" / "venv", "Agent")
ae = ROOT / "agent" / ".env"
if ae.is_file(): _perm600(ae, "agent/.env")
else: _f("agent/.env not found")
if (ROOT / "agent" / "src" / "admin.py").is_file():        _p("agent/src/admin.py (health port 5800)")
else: _f("agent/src/admin.py missing")
if (ROOT / "agent" / "src" / "session_control.py").is_file(): _p("agent/src/session_control.py (Ph-5 RPC)")
else: _f("agent/src/session_control.py missing")
if (ROOT / "agent" / "src" / "memory.py").is_file():       _p("agent/src/memory.py (Ph-8 Qdrant memory)")
else: _f("agent/src/memory.py missing")
# Ph-3: hot_swap tool MUST NOT exist
if (ROOT / "agent" / "src" / "tools" / "hot_swap.py").is_file():
    _f("agent/src/tools/hot_swap.py EXISTS (Ph-3 violation — global TTS switch not a session tool)")
else: _p("hot_swap.py absent (Ph-3: correct)")

_s("Fastembed Model Cache")
fc = ROOT / ".cache" / "fastembed"
if fc.is_dir() and any(fc.iterdir()): _p(f"fastembed cache present: {fc}")
else: _w("fastembed cache empty — will download on first agent start")

_s("Telemetry")
_venv(ROOT / "telemetry" / ".venv", "Telemetry")
if (ROOT / "telemetry" / "src" / "collectors" / "processes.py").is_file(): _p("processes.py present (Ph-8)")
else: _f("processes.py missing")

_s("Admin Layer")
for f in ["lan_mode.py", "tts_switch.py", "validate.py",
          "context.py", "memory_admin.py", "web_fetch.py"]:
    if (ROOT / "admin" / f).is_file(): _p(f"admin/{f}")
    else: _f(f"admin/{f} missing")

_s("Systemd Units")
su = Path.home() / ".config" / "systemd" / "user"
for u in ["voiceai-livekit", "voiceai-llm", "voiceai-stt", "voiceai-tts",
          "voiceai-qdrant", "voiceai-agent", "voiceai-telemetry"]:
    if (su / f"{u}.service").is_file(): _p(f"{u}.service installed")
    else: _f(f"{u}.service not installed")

_s("Live Service Health  (WARN = not running)")
for label, url in [
    ("LiveKit",     "tcp://127.0.0.1:7880"),
    ("LLM",         "http://127.0.0.1:5000/v1/models"),
    ("STT",         "http://127.0.0.1:5100/health"),
    ("TTS Router",  "http://127.0.0.1:5200/health"),
    ("Qdrant",      "http://127.0.0.1:6333/"),
    ("Agent Admin", "http://127.0.0.1:5800/health"),
    ("Telemetry",   "http://127.0.0.1:5900/health"),
]: _health(url, label)

_s("LAN Mode")
lan_f = ROOT / "config" / "lan_ip.txt"
if lan_f.is_file(): ip = lan_f.read_text().strip(); _p(f"LAN ACTIVE  IP={ip}")
else: _p("LAN INACTIVE (loopback-only)")

print(); print("=" * 56); print(f"  PASS:{PASS}  WARN:{WARN}  FAIL:{FAIL}"); print("=" * 56)
sys.exit(1 if FAIL > 0 else 0)
PYEOF

chmod +x "$ROOT/admin/lan_mode.py" "$ROOT/admin/tts_switch.py" \
         "$ROOT/admin/validate.py" \
         "$ROOT/admin/context.py" "$ROOT/admin/memory_admin.py" \
         "$ROOT/admin/web_fetch.py"
_ok "Admin layer written (v4: memory_admin + web_fetch + Qdrant in validate; STT switch lives in STT backend HTTP admin)"
