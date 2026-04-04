#!/usr/bin/env bash
# ==============================================================================
# 05_install_stt_service.sh
#
# Responsibility:
#   §7  STT venv (Python 3.12)
#       STT deps (faster-whisper, fastapi, watchfiles, …)
#       Generate all STT Python source files
#       Write config.yml
#       Write bin/start-stt.sh and bin/download-stt-models.sh
# ==============================================================================
set -euo pipefail
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$BOOTSTRAP_DIR/00_shared_helpers.sh"

ROOT="${ROOT:-$HOME/ai-projects/voiceai}"
STT_PYTHON="${STT_PYTHON:-3.12}"
PORT_STT="${PORT_STT:-5100}"
STT_DEFAULT_MODEL="${STT_DEFAULT_MODEL:-faster-whisper-medium}"

STT_DIR="$ROOT/stt/faster-whisper-service"
STT_SRC="$STT_DIR/src"
STT_ROUTES="$STT_SRC/routes"
mkdir -p "$STT_SRC" "$STT_ROUTES"

# ==============================================================================
# §7 — STT VENV + DEPS
# ==============================================================================
_banner "05 / STT — Faster-Whisper"

_step "STT venv"
_venv_version_ok "$STT_DIR/venv" "$STT_PYTHON" \
  && _skip "STT venv" \
  || uv venv "$STT_DIR/venv" -p "$STT_PYTHON"

STT_DEPS_MARKER="$STT_DIR/.bootstrap_deps_ok"
if [ ! -f "$STT_DEPS_MARKER" ]; then
  _step "STT deps"
  # shellcheck source=/dev/null
  . "$STT_DIR/venv/bin/activate"
  uv pip install -U faster-whisper fastapi "uvicorn[standard]" \
    python-multipart pyyaml av numpy soundfile watchfiles
  deactivate
  touch "$STT_DEPS_MARKER"
  _ok "STT deps installed"
else
  _skip "STT deps"
fi

# ==============================================================================
# §7 — STT PYTHON SOURCE
# ==============================================================================
_banner "05 / STT — Python source"

cat > "$STT_SRC/__init__.py" <<'PYEOF'
PYEOF

# ── config.py — watchfiles-driven hot reload ──────────────────────────────────
cat > "$STT_SRC/config.py" <<'PYEOF'
"""VoiceAI STT config. Ph-1: real reload via TranscriberHolder callback."""
from __future__ import annotations
import asyncio, logging
from pathlib import Path
from typing import Any, Callable, Awaitable
import yaml

log = logging.getLogger("voiceai.stt.config")
_CONFIG_PATH = Path(__file__).parent.parent / "config.yml"
_current: dict[str, Any] = {}
_reload_cbs: list[Callable[[dict], Awaitable[None]]] = []

def get() -> dict[str, Any]: return _current
def register_reload_callback(cb): _reload_cbs.append(cb)

def _load_raw():
    with _CONFIG_PATH.open(encoding="utf-8") as fh: return yaml.safe_load(fh)

def _validate(cfg):
    d = cfg.get("model", {}).get("device", "")
    c = cfg.get("model", {}).get("compute_type", "")
    if d != "cpu":  raise RuntimeError(f"STT device must be 'cpu', got '{d}'")
    if c != "int8": raise RuntimeError(f"STT compute_type must be 'int8', got '{c}'")

def load_initial():
    global _current
    _current = _load_raw(); _validate(_current)
    log.info("[CONFIG] Loaded from %s", _CONFIG_PATH)
    return _current

async def watch_and_reload():
    try:
        from watchfiles import awatch
    except ImportError:
        log.warning("[CONFIG] watchfiles not installed. Hot-reload disabled.")
        return
    async for _ in awatch(str(_CONFIG_PATH)):
        try:
            new = _load_raw(); _validate(new)
        except Exception as exc:
            log.warning("[CONFIG] Reload skipped — invalid config: %s", exc); continue
        global _current; _current = new
        log.info("[CONFIG] Hot-reloaded → %s", new["model"]["model_name"])
        for cb in _reload_cbs:
            try: await cb(new)
            except Exception as e: log.warning("[CONFIG] Callback error: %s", e)
PYEOF

# ── transcriber.py ────────────────────────────────────────────────────────────
cat > "$STT_SRC/transcriber.py" <<'PYEOF'
"""Ph-2: Single canonical transcriber. Verbose opt-in. CPU/int8 enforced."""
from __future__ import annotations
import dataclasses, logging
from typing import Any, Optional
import numpy as np
log = logging.getLogger("voiceai.stt.transcriber")

@dataclasses.dataclass
class TranscriptionResult:
    text: str; language: str; language_probability: float
    duration: Optional[float]; duration_after_vad: Optional[float]
    segments: list[dict]; pronunciation_warnings: list[str]

MODEL_ALIASES = {
    "faster-whisper-tiny": "tiny",
    "faster-whisper-tiny.en": "tiny.en",
    "faster-whisper-base": "base",
    "faster-whisper-base.en": "base.en",
    "faster-whisper-small": "small",
    "faster-whisper-small.en": "small.en",
    "faster-whisper-medium": "medium",
    "faster-whisper-medium.en": "medium.en",
}

class Transcriber:
    def __init__(self, model, cfg: dict):
        self._model = model; self._cfg = cfg

    @classmethod
    def from_config(cls, cfg: dict) -> "Transcriber":
        from faster_whisper import WhisperModel
        mc = cfg["model"]
        native_model = MODEL_ALIASES.get(mc["model_name"], mc["model_name"])
        m = WhisperModel(
            native_model,
            device=mc.get("device", "cpu"),
            compute_type=mc.get("compute_type", "int8"),
            num_workers=mc.get("num_workers", 2),
            cpu_threads=mc.get("cpu_threads", 8),
            download_root=mc.get("model_dir"),
        )
        log.info("[TRANSCRIBER] Built: %s  workers=%s  threads=%s",
                 native_model, mc.get("num_workers", 2), mc.get("cpu_threads", 8))
        return cls(m, cfg)

    def transcribe(self, audio: np.ndarray, language: Optional[str] = None,
                   temperature: Optional[float] = None,
                   verbose: bool = False) -> TranscriptionResult:
        tc = self._cfg.get("transcription", {})
        kw: dict[str, Any] = {
            "beam_size":                  tc.get("beam_size", 5),
            "vad_filter":                 tc.get("vad_filter", True),
            "condition_on_previous_text": tc.get("condition_on_previous_text", True),
            "temperature":                temperature if temperature is not None else tc.get("temperature", 0.0),
        }
        lang = language or tc.get("language")
        if lang: kw["language"] = lang
        segments_raw, info = self._model.transcribe(audio, **kw)
        segs_out = []; warnings = []; final_parts = []
        for seg in segments_raw:
            segs_out.append({"start": round(seg.start, 3), "end": round(seg.end, 3), "text": seg.text})
            final_parts.append(seg.text)
            if verbose and hasattr(seg, "words") and seg.words:
                for w in seg.words:
                    if hasattr(w, "probability") and w.probability < 0.6:
                        warnings.append(f"low-prob word: '{w.word}' ({w.probability:.2f})")
        final = "".join(final_parts).strip()
        return TranscriptionResult(
            text=final, language=info.language,
            language_probability=round(info.language_probability, 2),
            duration=getattr(info, "duration", None),
            duration_after_vad=getattr(info, "duration_after_vad", None),
            segments=segs_out, pronunciation_warnings=warnings,
        )
PYEOF

# ── holder.py — async lock for real model reload ─────────────────────────────
cat > "$STT_SRC/holder.py" <<'PYEOF'
"""Ph-1: TranscriberHolder — async lock for real model reload."""
from __future__ import annotations
import asyncio, gc, logging
from typing import TYPE_CHECKING
if TYPE_CHECKING: from .transcriber import Transcriber
log = logging.getLogger("voiceai.stt.holder")

class TranscriberHolder:
    def __init__(self) -> None:
        self._lock = asyncio.Lock(); self._t: "Transcriber | None" = None

    def get(self) -> "Transcriber | None": return self._t
    def is_reloading(self) -> bool: return self._lock.locked()

    async def build(self, cfg: dict) -> None:
        from .transcriber import Transcriber
        self._t = Transcriber.from_config(cfg)
        log.info("[HOLDER] Initial transcriber built: %s", cfg["model"]["model_name"])

    async def rebuild(self, cfg: dict) -> None:
        async with self._lock:
            log.info("[HOLDER] Reload started → %s", cfg["model"]["model_name"])
            old = self._t; self._t = None
            if old is not None: del old; gc.collect()
            from .transcriber import Transcriber
            self._t = Transcriber.from_config(cfg)
            log.info("[HOLDER] Reload complete.")
PYEOF

# ── audio.py ──────────────────────────────────────────────────────────────────
cat > "$STT_SRC/audio.py" <<'PYEOF'
"""Audio decoding helpers."""
from __future__ import annotations
import io
import numpy as np

def decode_audio_bytes(data: bytes, target_sr: int = 16000) -> np.ndarray:
    import av
    with av.open(io.BytesIO(data)) as container:
        stream = next(s for s in container.streams if s.type == "audio")
        resampler = av.AudioResampler(format="s16", layout="mono", rate=target_sr)
        chunks = []
        for frame in container.decode(stream):
            for rf in resampler.resample(frame):
                chunks.append(rf.to_ndarray())
        if not chunks:
            return np.zeros(0, dtype=np.float32)
        raw = np.concatenate(chunks, axis=1).squeeze()
    return raw.astype(np.float32) / 32768.0
PYEOF

# ── routes/ ───────────────────────────────────────────────────────────────────
cat > "$STT_ROUTES/__init__.py" <<'PYEOF'
PYEOF

cat > "$STT_ROUTES/health.py" <<'PYEOF'
from fastapi import APIRouter
from .. import config
router = APIRouter()

@router.get("/health")
async def health() -> dict:
    cfg = config.get()
    return {
        "status": "ok",
        "model":        cfg["model"]["model_name"],
        "device":       cfg["model"]["device"],
        "compute_type": cfg["model"]["compute_type"],
    }

@router.get("/v1/models")
async def list_models() -> dict:
    cfg = config.get()
    return {"object": "list", "data": [
        {"id": cfg["model"]["model_name"], "object": "model", "owned_by": "local"}
    ]}
PYEOF

cat > "$STT_ROUTES/transcribe.py" <<'PYEOF'
"""Ph-2: Single canonical route + verbose opt-in. Ph-1: 503 during reload."""
from __future__ import annotations
import logging
from typing import Optional
from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from ..audio import decode_audio_bytes
from ..holder import TranscriberHolder
log = logging.getLogger("voiceai.stt.routes.transcribe")
router = APIRouter()
_holder: "TranscriberHolder | None" = None

def set_holder(h: "TranscriberHolder") -> None:
    global _holder; _holder = h

@router.post("/v1/audio/transcriptions")
async def transcribe(
    file:        UploadFile      = File(...),
    language:    Optional[str]   = Form(default=None),
    temperature: Optional[float] = Form(default=None),
    verbose:     bool            = Form(default=False),
) -> dict:
    if _holder is None or _holder.is_reloading():
        raise HTTPException(503, detail="STT model is reloading. Retry in a few seconds.")
    t = _holder.get()
    if t is None:
        raise HTTPException(503, detail="STT model not loaded.")
    audio_bytes = await file.read()
    try:
        audio = decode_audio_bytes(audio_bytes)
    except Exception as exc:
        raise HTTPException(400, detail=f"Audio decode failed: {exc}")
    import asyncio
    result = await asyncio.to_thread(t.transcribe, audio, language, temperature, verbose)
    out: dict = {
        "text":                 result.text,
        "language":             result.language,
        "language_probability": result.language_probability,
    }
    if verbose:
        out["segments"]  = result.segments
        out["duration"]  = result.duration
        out["duration_after_vad"] = result.duration_after_vad
        if result.pronunciation_warnings:
            out["pronunciation_warnings"] = result.pronunciation_warnings
    return out
PYEOF

cat > "$STT_ROUTES/admin.py" <<'PYEOF'
"""STT admin routes. Global model switch via atomic config write."""
from __future__ import annotations
import asyncio, os, tempfile
from pathlib import Path
import yaml
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter(prefix="/admin")
CANONICAL = frozenset({
    "faster-whisper-tiny", "faster-whisper-tiny.en",
    "faster-whisper-base", "faster-whisper-base.en",
    "faster-whisper-small", "faster-whisper-small.en",
    "faster-whisper-medium", "faster-whisper-medium.en",
})
_lock: "asyncio.Lock | None" = None

class SwitchReq(BaseModel):
    model: str


def _switch_lock() -> asyncio.Lock:
    global _lock
    if _lock is None:
        _lock = asyncio.Lock()
    return _lock


def _cfg_path() -> Path:
    return Path(__file__).resolve().parents[2] / "config.yml"


@router.post("/switch_model")
async def switch_model(req: SwitchReq) -> dict:
    name = req.model.strip()
    if not name:
        raise HTTPException(400, "model required")
    if name not in CANONICAL:
        raise HTTPException(400, f"Invalid model '{name}'. Canonical: {sorted(CANONICAL)}")

    cfg_path = _cfg_path()
    if not cfg_path.is_file():
        raise HTTPException(500, f"STT config not found: {cfg_path}")

    async with _switch_lock():
        with cfg_path.open(encoding="utf-8") as fh:
            cfg = yaml.safe_load(fh)
        if not isinstance(cfg, dict) or "model" not in cfg:
            raise HTTPException(500, "Unexpected config.yml shape")

        prev = cfg.get("model", {}).get("model_name")
        cfg["model"]["model_name"] = name

        content = yaml.dump(cfg, default_flow_style=False, allow_unicode=True, sort_keys=False)
        orig_mode = cfg_path.stat().st_mode & 0o777 if cfg_path.exists() else 0o644
        fd, tmp = tempfile.mkstemp(dir=cfg_path.parent, prefix=".config.yml.")
        try:
            os.fchmod(fd, orig_mode)
            with os.fdopen(fd, "w", encoding="utf-8") as out:
                out.write(content)
            os.replace(tmp, cfg_path)
            os.chmod(cfg_path, orig_mode)
        except Exception:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise

    return {
        "ok": True,
        "message": f"STT model: {prev} → {name}. watchfiles hot-reload in <1s.",
        "previous_model": prev,
        "target_model": name,
    }
PYEOF

# ── main.py ───────────────────────────────────────────────────────────────────
cat > "$STT_SRC/main.py" <<'PYEOF'
#!/usr/bin/env python3
import asyncio, logging, logging.config
import uvicorn
from contextlib import asynccontextmanager
from pathlib import Path
from fastapi import FastAPI
from . import config as cfg_module
from .holder import TranscriberHolder
from .routes import admin as admin_routes, health as health_routes, transcribe as transcribe_routes

_LOG = {
    "version": 1, "disable_existing_loggers": False,
    "formatters": {"plain": {"format": "%(asctime)s  %(levelname)-8s  %(name)-30s  %(message)s",
                             "datefmt": "%H:%M:%S"}},
    "handlers": {"stdout": {"class": "logging.StreamHandler", "stream": "ext://sys.stdout",
                            "formatter": "plain"}},
    "root": {"level": "INFO", "handlers": ["stdout"]},
    "loggers": {"uvicorn.access": {"level": "WARNING"}},
}
logging.config.dictConfig(_LOG)
log = logging.getLogger("voiceai.stt.main")

@asynccontextmanager
async def lifespan(app: FastAPI):
    cfg = cfg_module.load_initial()
    holder = TranscriberHolder()
    await holder.build(cfg)
    cfg_module.register_reload_callback(holder.rebuild)
    transcribe_routes.set_holder(holder)
    reload_task = asyncio.create_task(cfg_module.watch_and_reload(), name="stt-config-reload")
    log.info("[LIFESPAN] STT ready  model=%s  workers=%s  threads=%s",
             cfg["model"]["model_name"],
             cfg["model"].get("num_workers", 2),
             cfg["model"].get("cpu_threads", 8))
    yield
    reload_task.cancel()
    try: await reload_task
    except asyncio.CancelledError: pass

def create_app():
    app = FastAPI(title="VoiceAI STT", version="3.1.0", lifespan=lifespan)
    app.include_router(health_routes.router)
    app.include_router(admin_routes.router)
    app.include_router(transcribe_routes.router)
    return app

app = create_app()
if __name__ == "__main__":
    import yaml
    boot = yaml.safe_load((Path(__file__).parent.parent / "config.yml").read_text())
    svc  = boot.get("service", {})
    uvicorn.run("src.main:app",
                host=svc.get("host", "127.0.0.1"),
                port=int(svc.get("port", 5100)),
                reload=False, log_config=None, access_log=False)
PYEOF

# ==============================================================================
# §7 — STT CONFIG + START SCRIPTS
# ==============================================================================
_banner "05 / STT — config + start scripts"

cat > "$STT_DIR/config.yml" <<CFG
service:
  host: 127.0.0.1
  port: ${PORT_STT}
model:
  model_dir: ${ROOT}/models/stt
  model_name: ${STT_DEFAULT_MODEL}
  device: cpu
  compute_type: int8
  num_workers: 2
  cpu_threads: 8
transcription:
  task: transcribe
  language: en
  beam_size: 5
  vad_filter: true
  condition_on_previous_text: true
  temperature: 0.0
CFG

cat > "$ROOT/bin/start-stt.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
. "$HOME/.config/voiceai/env.sh"
cd "$VOICEAI_ROOT/stt/faster-whisper-service"
# shellcheck source=/dev/null
. "./venv/bin/activate"
echo "[STT] Starting on 127.0.0.1:5100 (cpu/int8) …"
exec python -m src.main
SCRIPT
chmod +x "$ROOT/bin/start-stt.sh"

cat > "$ROOT/bin/download-stt-models.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
. "$HOME/.config/voiceai/env.sh"
for m in tiny tiny.en base base.en small small.en medium medium.en; do
  TARGET="$VOICEAI_ROOT/models/stt/faster-whisper-${m}"
  [ -d "$TARGET" ] && [ -n "$(ls -A "$TARGET" 2>/dev/null)" ] && { echo "  [SKIP] $m"; continue; }
  uv run --with huggingface_hub \
    python "$VOICEAI_ROOT/tools/downloaders/download_hf.py" \
    "Systran/faster-whisper-${m}" "$TARGET"
done
echo "ALL_STT_DOWNLOADS_OK=1"
SCRIPT
chmod +x "$ROOT/bin/download-stt-models.sh"

_ok "STT source written"
