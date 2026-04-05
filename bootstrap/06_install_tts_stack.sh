#!/usr/bin/env bash
# ==============================================================================
# 06_install_tts_stack.sh
#
# Responsibility:
#   §8  TTS Router venv + deps
#       Qwen3-TTS repo + venv + deps (flash-attn build, ~20-40 min first time)
#       Chatterbox repo + venv + deps
#       Generate all Router Python source (config, state, lifecycle, routes, main)
#       Generate all Worker Python source (config, vram, engines, routes, main)
#       Write bin/start-tts.sh
# ==============================================================================
set -euo pipefail
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$BOOTSTRAP_DIR/00_shared_helpers.sh"

ROOT="${ROOT:-$HOME/ai-projects/voiceai}"
SAFE_JOBS="${SAFE_JOBS:-4}"

TTS_DIR="$ROOT/tts"
ROUTER_SRC="$TTS_DIR/router/src";   ROUTER_ROUTES="$ROUTER_SRC/routes"
WORKER_SRC="$TTS_DIR/worker/src";   WORKER_ENGINES="$WORKER_SRC/engines"
WORKER_ROUTES="$WORKER_SRC/routes"
REPOS_DIR="$TTS_DIR/repos"
mkdir -p "$ROUTER_SRC" "$ROUTER_ROUTES" "$WORKER_SRC" "$WORKER_ENGINES" "$WORKER_ROUTES" \
         "$REPOS_DIR/router"

# ==============================================================================
# §8 — VENVS + REPOS
# ==============================================================================
_banner "06 / TTS — Router venv"
_venv_version_ok "$REPOS_DIR/router/.venv" "3.12" \
  && _skip "Router .venv" \
  || uv venv "$REPOS_DIR/router/.venv" -p 3.12

ROUTER_DEPS_MARKER="$REPOS_DIR/router/.bootstrap_deps_ok"
if [ ! -f "$ROUTER_DEPS_MARKER" ]; then
  # shellcheck source=/dev/null
  . "$REPOS_DIR/router/.venv/bin/activate"
  uv pip install -U fastapi "uvicorn[standard]" httpx pyyaml
  deactivate; touch "$ROUTER_DEPS_MARKER"; _ok "Router deps installed"
else _skip "Router deps"; fi

_banner "06 / TTS — Qwen3-TTS repo + venv"
[ -d "$REPOS_DIR/qwen3-17b/.git" ] \
  && _skip "Qwen3-TTS repo" \
  || git clone --depth 1 https://github.com/QwenLM/Qwen3-TTS.git "$REPOS_DIR/qwen3-17b"

QWEN_DEPS_MARKER="$REPOS_DIR/qwen3-17b/.bootstrap_deps_ok"
if [ ! -f "$QWEN_DEPS_MARKER" ]; then
  _step "Qwen3-TTS venv (flash-attn build ~20-40 min — be patient)"
  uv venv "$REPOS_DIR/qwen3-17b/.venv" -p 3.12
  # shellcheck source=/dev/null
  . "$REPOS_DIR/qwen3-17b/.venv/bin/activate"
  uv pip install --upgrade pip setuptools wheel
  uv pip install packaging psutil ninja soundfile
  uv pip install "torch==2.7.0" "torchvision==0.22.0" "torchaudio==2.7.0" \
    --index-url https://download.pytorch.org/whl/cu128
  MAX_JOBS="$SAFE_JOBS" uv pip install flash-attn --no-build-isolation
  uv pip install -e "$REPOS_DIR/qwen3-17b" --no-deps
  uv pip install "transformers==4.57.3" "accelerate==1.12.0" \
    librosa soundfile sox onnxruntime einops fastapi "uvicorn[standard]"
  deactivate; touch "$QWEN_DEPS_MARKER"; _ok "Qwen3-TTS deps installed"
else _skip "Qwen3-TTS deps"; fi

_banner "06 / TTS — Chatterbox repo + venv"
[ -d "$REPOS_DIR/chatterbox/.git" ] \
  && _skip "Chatterbox repo" \
  || git clone --depth 1 --branch master \
       https://github.com/resemble-ai/chatterbox.git "$REPOS_DIR/chatterbox"

CHATTERBOX_DEPS_MARKER="$REPOS_DIR/chatterbox/.bootstrap_deps_ok"
if [ ! -f "$CHATTERBOX_DEPS_MARKER" ]; then
  uv venv "$REPOS_DIR/chatterbox/.venv" -p 3.11
  # shellcheck source=/dev/null
  . "$REPOS_DIR/chatterbox/.venv/bin/activate"
  uv pip install "torch==2.7.0" "torchvision==0.22.0" "torchaudio==2.7.0" \
    --index-url https://download.pytorch.org/whl/cu128
  uv pip install -e "$REPOS_DIR/chatterbox"
  uv pip install soundfile fastapi "uvicorn[standard]"
  deactivate; touch "$CHATTERBOX_DEPS_MARKER"; _ok "Chatterbox deps installed"
else _skip "Chatterbox deps"; fi

# ==============================================================================
# §8 — ROUTER PYTHON SOURCE
# ==============================================================================
_banner "06 / TTS — Router source"

cat > "$ROUTER_SRC/__init__.py" <<'PYEOF'
PYEOF

cat > "$ROUTER_SRC/config.py" <<'PYEOF'
from __future__ import annotations
import os
from pathlib import Path

VOICEAI_ROOT = Path(os.environ.get("VOICEAI_ROOT", str(Path.home() / "ai-projects" / "voiceai")))
MODELS_ROOT  = Path(os.environ.get("VOICEAI_MODELS_ROOT", str(VOICEAI_ROOT / "models")))
_REPOS = VOICEAI_ROOT / "tts" / "repos"

ROUTER_HOST = os.environ.get("TTS_HOST", "127.0.0.1")
ROUTER_PORT = int(os.environ.get("TTS_PORT", "5200"))
WORKER_HOST = "127.0.0.1"
WORKER_PORT = int(os.environ.get("TTS_WORKER_PORT", "5201"))
WORKER_URL  = f"http://{WORKER_HOST}:{WORKER_PORT}"
WORKER_APP_DIR = VOICEAI_ROOT / "tts" / "worker"

INITIAL_MODE     = os.environ.get("TTS_MODE", "").strip().lower()
DRAIN_TIMEOUT_S  = float(os.environ.get("TTS_DRAIN_TIMEOUT", "30"))
TERM_TIMEOUT_S   = float(os.environ.get("TTS_TERM_TIMEOUT", "30"))
SETTLE_DELAY_S   = float(os.environ.get("TTS_SETTLE_DELAY", "2.0"))
PROBE_TIMEOUT_S  = float(os.environ.get("TTS_PROBE_TIMEOUT", "180"))
PROBE_INTERVAL_S = float(os.environ.get("TTS_PROBE_INTERVAL", "2.0"))

ENGINE_REGISTRY: dict[str, Path] = {
    "customvoice": _REPOS / "qwen3-17b"  / ".venv" / "bin" / "python",
    "voicedesign": _REPOS / "qwen3-17b"  / ".venv" / "bin" / "python",
    "chatterbox":  _REPOS / "chatterbox" / ".venv" / "bin" / "python",
}
VALID_MODES = frozenset(ENGINE_REGISTRY)
PYEOF

cat > "$ROUTER_SRC/state.py" <<'PYEOF'
from __future__ import annotations
import asyncio, enum
from dataclasses import dataclass, field

class Phase(str, enum.Enum):
    IDLE        = "idle"
    DRAINING    = "draining"
    TERMINATING = "terminating"
    SETTLING    = "vram_settling"
    SPAWNING    = "spawning"
    PROBING     = "probing"
    ERROR       = "error"

@dataclass
class RouterState:
    phase:           Phase = Phase.IDLE
    active_mode:     "str | None" = None
    target_mode:     "str | None" = None
    child_proc:      "asyncio.subprocess.Process | None" = field(default=None, repr=False)
    switch_start_ts: "float | None" = None
    last_error:      "str | None" = None
    inflight:        int = 0
    total_requests:  int = 0
    total_switches:  int = 0
PYEOF

cat > "$ROUTER_SRC/lifecycle.py" <<'PYEOF'
from __future__ import annotations
import asyncio, logging, os, time
import httpx
from . import config as cfg
from .state import Phase, RouterState
log = logging.getLogger("voiceai.tts.router.lifecycle")
_SEP = "=" * 66

def _log_phase(phase: Phase, detail: str = "") -> None:
    log.info(_SEP); log.info("  ► PHASE: %-20s  %s", phase.value.upper(), detail); log.info(_SEP)

def validate_engine(mode: str):
    p = cfg.ENGINE_REGISTRY[mode]
    if not p.is_file(): raise RuntimeError(f"Python for mode '{mode}' not found: {p}")
    return p

async def drain_inflight(state: RouterState) -> None:
    if state.inflight == 0: return
    state.phase = Phase.DRAINING; _log_phase(Phase.DRAINING)
    deadline = time.monotonic() + cfg.DRAIN_TIMEOUT_S
    while state.inflight > 0 and time.monotonic() < deadline: await asyncio.sleep(0.2)

async def terminate_child(state: RouterState) -> None:
    if state.child_proc is None: return
    state.phase = Phase.TERMINATING; _log_phase(Phase.TERMINATING)
    try:
        state.child_proc.send_signal(15)
        await asyncio.wait_for(state.child_proc.wait(), timeout=cfg.TERM_TIMEOUT_S)
    except asyncio.TimeoutError:
        try: state.child_proc.kill()
        except Exception: pass
        await state.child_proc.wait()
    except Exception as exc: log.warning("[TERM] %s", exc)
    state.child_proc = None

async def spawn_worker(state: RouterState, mode: str) -> None:
    python = validate_engine(mode)
    env = {**os.environ, "TTS_MODE": mode,
           "TTS_HOST": cfg.WORKER_HOST, "TTS_PORT": str(cfg.WORKER_PORT)}
    state.phase = Phase.SPAWNING; _log_phase(Phase.SPAWNING, mode)
    state.child_proc = await asyncio.create_subprocess_exec(
        str(python), "-m", "src.main",
        cwd=str(cfg.WORKER_APP_DIR), env=env,
    )

async def probe_worker(state: RouterState, client: httpx.AsyncClient) -> None:
    state.phase = Phase.PROBING; _log_phase(Phase.PROBING)
    deadline = time.monotonic() + cfg.PROBE_TIMEOUT_S
    while time.monotonic() < deadline:
        try:
            r = await client.get(f"{cfg.WORKER_URL}/health", timeout=cfg.PROBE_INTERVAL_S)
            if r.status_code == 200 and r.json().get("model_loaded"):
                return
        except Exception: pass
        await asyncio.sleep(cfg.PROBE_INTERVAL_S)
    raise RuntimeError(f"Worker probe timeout after {cfg.PROBE_TIMEOUT_S}s")

async def execute_switch(state: RouterState, mode: str, client: httpx.AsyncClient) -> None:
    state.switch_start_ts = time.monotonic(); state.target_mode = mode
    try:
        await drain_inflight(state)
        await terminate_child(state)
        state.phase = Phase.SETTLING; _log_phase(Phase.SETTLING)
        await asyncio.sleep(cfg.SETTLE_DELAY_S)
        await spawn_worker(state, mode)
        await probe_worker(state, client)
        state.phase = Phase.IDLE; state.active_mode = mode
        state.target_mode = None; state.total_switches += 1
        log.info(_SEP); log.info("  ✓ mode=%s  %.1fs", mode,
                                  time.monotonic() - (state.switch_start_ts or 0)); log.info(_SEP)
    except Exception as exc:
        state.phase = Phase.ERROR; state.last_error = str(exc); raise
PYEOF

cat > "$ROUTER_ROUTES/__init__.py" <<'PYEOF'
PYEOF

cat > "$ROUTER_ROUTES/health.py" <<'PYEOF'
from __future__ import annotations
import httpx
from fastapi import APIRouter
from ..state import Phase
router = APIRouter()
_state = None; _http: "httpx.AsyncClient | None" = None

def init(state, http): global _state, _http; _state, _http = state, http

@router.get("/health")
async def health() -> dict:
    w: dict = {}; wr = False
    if _state.phase == Phase.IDLE and _state.child_proc is not None:
        try:
            from .. import config as cfg
            r = await _http.get(f"{cfg.WORKER_URL}/health", timeout=3.0)
            if r.status_code == 200: w = r.json(); wr = w.get("model_loaded", False)
        except Exception: pass
    return {
        "status":       "ok" if _state.phase == Phase.IDLE else _state.phase.value,
        "router_phase": _state.phase.value,
        "active_mode":  _state.active_mode,
        "target_mode":  _state.target_mode,
        "switching":    _state.phase not in (Phase.IDLE, Phase.ERROR),
        "worker_ready": wr, "worker": w, "last_error": _state.last_error,
    }

@router.get("/v1/models")
async def list_models() -> dict:
    return {"object": "list", "data": [
        {"id": f"tts-{_state.active_mode or 'none'}", "object": "model", "owned_by": "local"}
    ]}
PYEOF

cat > "$ROUTER_ROUTES/admin.py" <<'PYEOF'
"""TTS Router admin. Single-active-switch: Phase-gate + Task-gate + Lock."""
from __future__ import annotations
import asyncio, time
from typing import Optional
import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from ..lifecycle import execute_switch
from ..state import Phase, RouterState
router = APIRouter(prefix="/admin")
_state: "Optional[RouterState]" = None
_lock:  "Optional[asyncio.Lock]"  = None
_http:  "Optional[httpx.AsyncClient]" = None
_switch_task: "Optional[asyncio.Task[None]]" = None

def init(state, lock, http): global _state, _lock, _http; _state, _lock, _http = state, lock, http

class SwitchReq(BaseModel): mode: str

async def _locked_switch(mode: str) -> None:
    global _switch_task
    try:
        async with _lock: await execute_switch(_state, mode, _http)  # type: ignore
    finally: _switch_task = None

@router.post("/switch_model", status_code=202)
async def switch_model(req: SwitchReq) -> dict:
    global _switch_task
    from .. import config as cfg
    mode = req.mode.strip().lower()
    if mode not in cfg.VALID_MODES:
        raise HTTPException(400, f"Invalid mode '{mode}'")
    if _state.phase not in (Phase.IDLE, Phase.ERROR):  # type: ignore
        raise HTTPException(409, f"Phase '{_state.phase.value}'")  # type: ignore
    if _switch_task is not None and not _switch_task.done():
        raise HTTPException(409, "Switch pending.")
    if _state.phase == Phase.IDLE and _state.active_mode == mode:  # type: ignore
        return {"status": "already_active", "mode": mode}
    _switch_task = asyncio.create_task(_locked_switch(mode), name=f"tts-switch-to-{mode}")
    return {"status": "accepted", "target_mode": mode,
            "current_mode": _state.active_mode, "poll_url": "/health"}  # type: ignore

@router.post("/restart", status_code=202)
async def restart_worker() -> dict:
    global _switch_task
    mode = _state.active_mode or _state.target_mode  # type: ignore
    if mode is None: raise HTTPException(400, "No mode.")
    if _state.phase not in (Phase.IDLE, Phase.ERROR):  # type: ignore
        raise HTTPException(409, f"Phase: {_state.phase.value}")  # type: ignore
    if _switch_task is not None and not _switch_task.done():
        raise HTTPException(409, "Switch pending.")
    _switch_task = asyncio.create_task(_locked_switch(mode), name=f"tts-restart-{mode}")
    return {"status": "restarting", "mode": mode}

@router.get("/status")
async def status() -> dict:
    from .. import config as cfg
    return {
        "router_phase":    _state.phase.value,  # type: ignore
        "active_mode":     _state.active_mode,   # type: ignore
        "switching":       _state.phase not in (Phase.IDLE, Phase.ERROR),  # type: ignore
        "switch_pending":  (_switch_task is not None and not _switch_task.done()),
        "total_switches":  _state.total_switches,  # type: ignore
        "last_error":      _state.last_error,       # type: ignore
        "valid_modes":     sorted(cfg.VALID_MODES),
    }
PYEOF

cat > "$ROUTER_ROUTES/proxy.py" <<'PYEOF'
from __future__ import annotations
import httpx
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import Response
from ..state import Phase
router = APIRouter()
_state = None; _http: "httpx.AsyncClient | None" = None

def init(state, http): global _state, _http; _state, _http = state, http

@router.post("/v1/audio/speech")
async def proxy_speech(request: Request) -> Response:
    if _state.phase != Phase.IDLE or _state.child_proc is None:
        raise HTTPException(503, "TTS worker not ready.")
    from .. import config as cfg
    _state.inflight += 1
    try:
        body = await request.body()
        r = await _http.post(f"{cfg.WORKER_URL}/v1/audio/speech",
                             content=body, headers=dict(request.headers), timeout=120.0)
        _state.total_requests += 1
        return Response(content=r.content, status_code=r.status_code,
                        media_type=r.headers.get("content-type", "audio/wav"))
    finally:
        _state.inflight -= 1
PYEOF

cat > "$ROUTER_SRC/main.py" <<'PYEOF'
#!/usr/bin/env python3
from __future__ import annotations
import asyncio, logging, logging.config
import httpx, uvicorn
from contextlib import asynccontextmanager
from fastapi import FastAPI
from . import config as cfg
from .lifecycle import execute_switch
from .routes import health as hr, admin as ar, proxy as pr
from .state import Phase, RouterState

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
log = logging.getLogger("voiceai.tts.router.main")

@asynccontextmanager
async def lifespan(app: FastAPI):
    state = RouterState(); lock = asyncio.Lock()
    client = httpx.AsyncClient(timeout=180.0)
    hr.init(state, client); ar.init(state, lock, client); pr.init(state, client)
    if cfg.INITIAL_MODE:
        if cfg.INITIAL_MODE not in cfg.VALID_MODES:
            raise RuntimeError(f"Invalid TTS_MODE='{cfg.INITIAL_MODE}'")
        async with lock: await execute_switch(state, cfg.INITIAL_MODE, client)
    yield
    if state.child_proc:
        state.phase = Phase.TERMINATING
        from .lifecycle import terminate_child; await terminate_child(state)
    await client.aclose()

def create_app():
    app = FastAPI(title="VoiceAI TTS Router", version="3.0.0", lifespan=lifespan)
    app.include_router(hr.router); app.include_router(ar.router); app.include_router(pr.router)
    return app

app = create_app()
if __name__ == "__main__":
    uvicorn.run("src.main:app", host=cfg.ROUTER_HOST, port=cfg.ROUTER_PORT,
                reload=False, log_config=None, access_log=False)
PYEOF

# ==============================================================================
# §8 — WORKER PYTHON SOURCE
# ==============================================================================
_banner "06 / TTS — Worker source"

cat > "$WORKER_SRC/__init__.py" <<'PYEOF'
PYEOF

cat > "$WORKER_SRC/config.py" <<'PYEOF'
from __future__ import annotations
import os
from pathlib import Path

VOICEAI_ROOT = Path(os.environ.get("VOICEAI_ROOT", str(Path.home() / "ai-projects" / "voiceai")))
MODELS_TTS   = Path(os.environ.get("VOICEAI_MODELS_ROOT",
                                   str(VOICEAI_ROOT / "models"))) / "tts"
TTS_MODE = os.environ.get("TTS_MODE", "").strip().lower()
TTS_HOST = os.environ.get("TTS_HOST", "127.0.0.1")
TTS_PORT = int(os.environ.get("TTS_PORT", "5201"))

CUSTOMVOICE_DIR = MODELS_TTS / "Qwen3-TTS-12Hz-1.7B-CustomVoice"
VOICEDESIGN_DIR = MODELS_TTS / "Qwen3-TTS-12Hz-1.7B-VoiceDesign"
CHATTERBOX_DIR  = MODELS_TTS / "chatterbox"
REFERENCE_AUDIO_DIR = VOICEAI_ROOT / "inputs"
VALID_MODES = frozenset({"customvoice", "voicedesign", "chatterbox"})
PYEOF

cat > "$WORKER_SRC/vram.py" <<'PYEOF'
from __future__ import annotations
import gc, logging
log = logging.getLogger("voiceai.tts.worker.vram")

def release(model_ref: object) -> None:
    log.info("[VRAM] 6-step release …")
    try:
        import torch
        if torch.cuda.is_available(): torch.cuda.synchronize()
    except Exception as e: log.warning("[VRAM] synchronize: %s", e)
    del model_ref; gc.collect()
    try:
        import torch
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
            getattr(torch.cuda, "ipc_collect", lambda: None)()
            free, total = torch.cuda.mem_get_info(0)
            log.info("[VRAM] post-release: %.2f GB free / %.2f GB total",
                     free / 1e9, total / 1e9)
    except Exception as e: log.warning("[VRAM] empty_cache: %s", e)
    gc.collect(); log.info("[VRAM] complete.")
PYEOF

cat > "$WORKER_ENGINES/__init__.py" <<'PYEOF'
from .base import SynthesisRequest, TTSEngine
from .chatterbox  import ChatterboxEngine
from .customvoice import CustomVoiceEngine
from .voicedesign import VoiceDesignEngine

_R = {
    "customvoice": CustomVoiceEngine,
    "voicedesign": VoiceDesignEngine,
    "chatterbox":  ChatterboxEngine,
}

def build_engine(mode: str) -> TTSEngine:
    cls = _R.get(mode)
    if cls is None: raise ValueError(f"Unknown TTS mode '{mode}'")
    return cls()
PYEOF

cat > "$WORKER_ENGINES/base.py" <<'PYEOF'
"""Ph-5: Truthful request contract. speed removed. response_format locked to wav."""
from __future__ import annotations
import dataclasses
from abc import ABC, abstractmethod
from typing import Literal

@dataclasses.dataclass
class SynthesisRequest:
    input:           str
    voice:           str     = "Ryan"
    language:        str     = "en"
    language_id:     str     = ""
    instruct:        str     = ""
    response_format: Literal["wav"] = "wav"
    temperature:     float   = 0.4
    cfg_weight:      float   = 0.3
    exaggeration:    float   = 0.7

class TTSEngine(ABC):
    @abstractmethod
    def load(self) -> None: ...
    @abstractmethod
    def synthesize(self, req: SynthesisRequest) -> bytes: ...
    @property
    @abstractmethod
    def model(self) -> object: ...
    def health_extras(self) -> dict: return {}
PYEOF

cat > "$WORKER_ENGINES/customvoice.py" <<'PYEOF'
"""Qwen3-TTS CustomVoice. voice=named speaker, instruct optional."""
from __future__ import annotations
import importlib.util, io, logging
import numpy as np, soundfile as sf
from ..config import CUSTOMVOICE_DIR
from .base import SynthesisRequest, TTSEngine
log = logging.getLogger("voiceai.tts.worker.engines.customvoice")

class CustomVoiceEngine(TTSEngine):
    def __init__(self): self._model = None
    @property
    def model(self): return self._model

    def load(self):
        import torch; from qwen_tts import Qwen3TTSModel
        if not CUSTOMVOICE_DIR.is_dir():
            raise RuntimeError(f"CustomVoice dir not found: {CUSTOMVOICE_DIR}")
        attn = "flash_attention_2" if importlib.util.find_spec("flash_attn") else "sdpa"
        dtype = (torch.bfloat16
                 if torch.cuda.is_available() and torch.cuda.is_bf16_supported()
                 else torch.float16)
        self._model = Qwen3TTSModel.from_pretrained(
            str(CUSTOMVOICE_DIR), device_map="cuda:0", dtype=dtype, attn_implementation=attn)
        log.info("[CUSTOMVOICE] Ready.")

    def synthesize(self, req: SynthesisRequest) -> bytes:
        kw = {"text": req.input, "language": req.language, "speaker": req.voice}
        if req.instruct and req.instruct.strip(): kw["instruct"] = req.instruct
        wavs, sr = self._model.generate_custom_voice(**kw)
        a = wavs[0] if isinstance(wavs[0], np.ndarray) else wavs[0].cpu().numpy()
        buf = io.BytesIO(); sf.write(buf, a, sr, format="WAV"); return buf.getvalue()
PYEOF

cat > "$WORKER_ENGINES/voicedesign.py" <<'PYEOF'
"""Qwen3-TTS VoiceDesign. instruct shapes voice."""
from __future__ import annotations
import importlib.util, io, logging
import numpy as np, soundfile as sf
from ..config import VOICEDESIGN_DIR
from .base import SynthesisRequest, TTSEngine
log = logging.getLogger("voiceai.tts.worker.engines.voicedesign")

class VoiceDesignEngine(TTSEngine):
    def __init__(self): self._model = None
    @property
    def model(self): return self._model

    def load(self):
        import torch; from qwen_tts import Qwen3TTSModel
        if not VOICEDESIGN_DIR.is_dir():
            raise RuntimeError(f"VoiceDesign dir not found: {VOICEDESIGN_DIR}")
        attn = "flash_attention_2" if importlib.util.find_spec("flash_attn") else "sdpa"
        dtype = (torch.bfloat16
                 if torch.cuda.is_available() and torch.cuda.is_bf16_supported()
                 else torch.float16)
        self._model = Qwen3TTSModel.from_pretrained(
            str(VOICEDESIGN_DIR), device_map="cuda:0", dtype=dtype, attn_implementation=attn)
        log.info("[VOICEDESIGN] Ready.")

    def synthesize(self, req: SynthesisRequest) -> bytes:
        kw = {"text": req.input, "language": req.language}
        if req.instruct and req.instruct.strip(): kw["instruct"] = req.instruct
        wavs, sr = self._model.generate_voice_design(**kw)
        a = wavs[0] if isinstance(wavs[0], np.ndarray) else wavs[0].cpu().numpy()
        buf = io.BytesIO(); sf.write(buf, a, sr, format="WAV"); return buf.getvalue()
PYEOF

cat > "$WORKER_ENGINES/chatterbox.py" <<'PYEOF'
"""
Ph-6: Chatterbox engine with voice→reference-file mapping.
voice → REFERENCE_AUDIO_DIR/<voice>.<ext>  (wav/mp3/flac/ogg)
Ph-1: directory-driven discovery. No hardcoded prompt.wav.
"""
from __future__ import annotations
import io, logging
from pathlib import Path
from typing import Optional
import numpy as np, soundfile as sf
from ..config import CHATTERBOX_DIR, REFERENCE_AUDIO_DIR
from .base import SynthesisRequest, TTSEngine
log = logging.getLogger("voiceai.tts.worker.engines.chatterbox")
_AUDIO_EXTS = {".wav", ".mp3", ".flac", ".ogg"}

def list_available_voices() -> list[str]:
    if not REFERENCE_AUDIO_DIR.is_dir(): return []
    return [f.stem for f in sorted(REFERENCE_AUDIO_DIR.iterdir())
            if f.suffix.lower() in _AUDIO_EXTS and f.is_file()]

def _find_ref(voice: str) -> Optional[Path]:
    if not REFERENCE_AUDIO_DIR.is_dir(): return None
    for ext in _AUDIO_EXTS:
        p = REFERENCE_AUDIO_DIR / f"{voice}{ext}"
        if p.is_file(): return p
    return None

class ChatterboxEngine(TTSEngine):
    def __init__(self): self._model = None; self._sr = 24000
    @property
    def model(self): return self._model

    def load(self):
        import torch
        if not CHATTERBOX_DIR.is_dir():
            raise RuntimeError(f"Chatterbox model dir not found: {CHATTERBOX_DIR}")
        from chatterbox.mtl_tts import ChatterboxMultilingualTTS
        device = "cuda" if torch.cuda.is_available() else "cpu"
        self._model = ChatterboxMultilingualTTS.from_local(CHATTERBOX_DIR, device=device)
        self._sr = getattr(self._model, "sr", 24000)
        log.info("[CHATTERBOX] Ready. device=%s  voices=%d", device, len(list_available_voices()))

    def synthesize(self, req: SynthesisRequest) -> bytes:
        ref = _find_ref(req.voice)
        if req.voice and not ref:
            log.warning("[CHATTERBOX] No reference audio for voice '%s'", req.voice)
        language_id = (req.language_id or req.language or "en").strip().lower()
        wav = self._model.generate(
            req.input,
            language_id=language_id,
            audio_prompt_path=str(ref) if ref else None,
            temperature=req.temperature,
            cfg_weight=req.cfg_weight,
            exaggeration=req.exaggeration,
        )
        audio = wav.squeeze().cpu().numpy() if hasattr(wav, "cpu") else np.array(wav).squeeze()
        buf = io.BytesIO(); sf.write(buf, audio, self._sr, format="WAV"); return buf.getvalue()

    def health_extras(self) -> dict:
        return {"reference_audio_dir": str(REFERENCE_AUDIO_DIR),
                "available_voices": len(list_available_voices())}
PYEOF

cat > "$WORKER_ROUTES/__init__.py" <<'PYEOF'
PYEOF

cat > "$WORKER_ROUTES/health.py" <<'PYEOF'
from fastapi import APIRouter
from ..config import TTS_MODE, TTS_PORT
router = APIRouter()
_engine = None

def set_engine(e) -> None: global _engine; _engine = e

@router.get("/health")
async def health() -> dict:
    vf = vt = gn = None; cuda = False
    try:
        import torch; cuda = torch.cuda.is_available()
        gn = torch.cuda.get_device_name(0) if cuda else None
        if cuda: free, total = torch.cuda.mem_get_info(0); vf = round(free/1e9, 2); vt = round(total/1e9, 2)
    except Exception: pass
    extras = _engine.health_extras() if _engine else {}
    return {"status": "ok", "tts_mode": TTS_MODE,
            "model_loaded": _engine is not None and _engine.model is not None,
            "cuda": cuda, "gpu": gn, "vram_free_gb": vf, "vram_total_gb": vt,
            "worker_port": TTS_PORT, **extras}

@router.get("/v1/models")
async def list_models() -> dict:
    return {"object": "list", "data": [{"id": f"tts-{TTS_MODE}", "object": "model", "owned_by": "local"}]}
PYEOF

cat > "$WORKER_ROUTES/synthesize.py" <<'PYEOF'
"""Ph-5: Truthful request contract. speed removed."""
from __future__ import annotations
import asyncio, logging
from typing import Literal
from fastapi import APIRouter, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, Field
from ..engines.base import SynthesisRequest
log = logging.getLogger("voiceai.tts.worker.routes.synthesize")
router = APIRouter()
_engine = None

def set_engine(e) -> None: global _engine; _engine = e

class SpeechReq(BaseModel):
    input:           str
    voice:           str   = "Aiden"
    language:        str   = "English"
    language_id:     str   = ""
    instruct:        str   = ""
    response_format: Literal["wav"] = "wav"
    temperature:     float = Field(default=0.4, ge=0.0, le=2.0)
    cfg_weight:      float = Field(default=0.3, ge=0.0, le=1.0)
    exaggeration:    float = Field(default=0.7, ge=0.0, le=2.0)

@router.post("/v1/audio/speech")
async def synthesize(req: SpeechReq) -> Response:
    if _engine is None or _engine.model is None:
        raise HTTPException(503, "Model not loaded.")
    sr = SynthesisRequest(input=req.input, voice=req.voice, language=req.language,
                          language_id=req.language_id, instruct=req.instruct,
                          response_format=req.response_format, temperature=req.temperature,
                          cfg_weight=req.cfg_weight, exaggeration=req.exaggeration)
    try: wav = await asyncio.to_thread(_engine.synthesize, sr)
    except Exception as e: log.exception("[SYNTHESIZE] Failed"); raise HTTPException(500, str(e))
    return Response(content=wav, media_type="audio/wav")
PYEOF

cat > "$WORKER_SRC/main.py" <<'PYEOF'
#!/usr/bin/env python3
from __future__ import annotations
import asyncio, logging, logging.config, signal, sys
import uvicorn
from contextlib import asynccontextmanager
from fastapi import FastAPI
from . import config as cfg
from .engines import build_engine
from .routes import health as hr, synthesize as sr
from .vram import release

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
log = logging.getLogger("voiceai.tts.worker.main")
_engine_ref = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global _engine_ref
    if not cfg.TTS_MODE: raise RuntimeError("TTS_MODE not set.")
    if cfg.TTS_MODE not in cfg.VALID_MODES:
        raise RuntimeError(f"Invalid TTS_MODE='{cfg.TTS_MODE}'")
    engine = build_engine(cfg.TTS_MODE); engine.load(); _engine_ref = engine
    hr.set_engine(engine); sr.set_engine(engine)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    log.info("[WORKER] Engine ready: %s", cfg.TTS_MODE)
    yield
    if _engine_ref is not None: release(_engine_ref.model); _engine_ref = None

def create_app():
    app = FastAPI(title="VoiceAI TTS Worker", version="3.0.0", lifespan=lifespan)
    app.include_router(hr.router); app.include_router(sr.router)
    return app

app = create_app()
if __name__ == "__main__":
    uvicorn.run("src.main:app", host=cfg.TTS_HOST, port=cfg.TTS_PORT,
                reload=False, log_config=None, access_log=False)
PYEOF

# ==============================================================================
# §8 — START SCRIPT
# ==============================================================================
_banner "06 / TTS — start script"

cat > "$ROOT/bin/start-tts.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
. "$HOME/.config/voiceai/env.sh"
MODE="${1:-customvoice}"; export TTS_MODE="$MODE"
cd "$VOICEAI_ROOT/tts/router"
# shellcheck source=/dev/null
. "$VOICEAI_ROOT/tts/repos/router/.venv/bin/activate"
echo "[TTS] Router on 127.0.0.1:5200  initial_mode=$MODE"
exec python -m src.main
SCRIPT
chmod +x "$ROOT/bin/start-tts.sh"
_ok "TTS Router + Worker source written"
