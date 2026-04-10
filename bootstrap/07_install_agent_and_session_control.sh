#!/usr/bin/env bash
# ==============================================================================
# 07_install_agent_and_session_control.sh
#
# Responsibility:
#   §9  Agent venv (Python 3.12) + deps (incl. qdrant-client[fastembed])
#       Pre-download fastembed embedding model (BAAI/bge-small-en-v1.5)
#       Generate all Agent Python source files:
#         __init__.py, config.py, state.py, admin.py, memory.py,
#         session_control.py, main.py
#       Generate default personas (default, english_teacher, best_friend, chill_assistant)
#       Write agent/.env (600)
#       Write bin/start-agent.sh
#
# Policy locks enforced here:
#   Session-voice-mutable: persona, voice, language, instruct, interruption behavior
#   NOT session-voice: engine switches, LLM tuning, memory admin, Qdrant ops, web autonomy
# ==============================================================================
set -euo pipefail
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$BOOTSTRAP_DIR/00_shared_helpers.sh"

ROOT="${ROOT:-$HOME/ai-projects/voiceai}"
ENV_DIR="${ENV_DIR:-$HOME/.config/voiceai}"
ENV_SH="${ENV_SH:-$ENV_DIR/env.sh}"
# shellcheck source=/dev/null
[ -f "$ENV_SH" ] && . "$ENV_SH"
AGENT_PYTHON="${AGENT_PYTHON:-3.12}"
PORT_LLM="${PORT_LLM:-5000}"; PORT_STT="${PORT_STT:-5100}"
PORT_TTS_ROUTER="${PORT_TTS_ROUTER:-5200}"; PORT_AGENT_ADMIN="${PORT_AGENT_ADMIN:-5800}"
PORT_QDRANT_REST="${PORT_QDRANT_REST:-6333}"
STT_DEFAULT_MODEL="${STT_DEFAULT_MODEL:-faster-whisper-medium}"
EMBEDDING_MODEL="${EMBEDDING_MODEL:-BAAI/bge-small-en-v1.5}"
EMBEDDING_DIM="${EMBEDDING_DIM:-384}"

AGENT_DIR="$ROOT/agent"
AGENT_SRC="$AGENT_DIR/src"
AGENT_TOOLS="$AGENT_SRC/tools"
PERSONAS_DIR="$AGENT_DIR/personas"
mkdir -p "$AGENT_SRC" "$AGENT_TOOLS" "$PERSONAS_DIR"

# ==============================================================================
# §9 — AGENT VENV + DEPS
# ==============================================================================
_banner "07 / AGENT — venv + deps"

_venv_version_ok "$AGENT_DIR/venv" "$AGENT_PYTHON" \
  && _skip "Agent venv" \
  || uv venv "$AGENT_DIR/venv" -p "$AGENT_PYTHON"

AGENT_DEPS_MARKER="$AGENT_DIR/.bootstrap_deps_ok"
if [ ! -f "$AGENT_DEPS_MARKER" ]; then
  # shellcheck source=/dev/null
  . "$AGENT_DIR/venv/bin/activate"
  # v4: added qdrant-client[fastembed] for memory + beautifulsoup4 for safe web fetch
  uv pip install -U \
    "livekit-agents==1.5.1" "livekit-plugins-openai==1.5.1" "livekit-plugins-silero==1.5.1" \
    httpx numpy soundfile pyyaml python-dotenv \
    "qdrant-client[fastembed]>=1.9.0" "beautifulsoup4>=4.12"
  deactivate
  touch "$AGENT_DEPS_MARKER"
  _ok "Agent deps installed (incl. qdrant-client[fastembed])"
else
  _skip "Agent deps"
fi

# ==============================================================================
# §9 — PRE-DOWNLOAD FASTEMBED EMBEDDING MODEL
# ==============================================================================
_banner "07 / AGENT — fastembed model cache"

FASTEMBED_MARKER="$ROOT/.bootstrap/fastembed_model.done"
if [ ! -f "$FASTEMBED_MARKER" ]; then
  _step "Pre-downloading fastembed: $EMBEDDING_MODEL"
  "$AGENT_DIR/venv/bin/python" -c "
import os
os.environ['FASTEMBED_CACHE_PATH'] = '${ROOT}/.cache/fastembed'
from fastembed import TextEmbedding
print('Downloading ${EMBEDDING_MODEL} …')
m = TextEmbedding(model_name='${EMBEDDING_MODEL}')
list(m.embed(['warm-up']))
print('FASTEMBED_MODEL_OK=1')
" && touch "$FASTEMBED_MARKER" && _ok "Embedding model cached" \
  || _warn "fastembed download failed — will retry on first agent start"
else
  _skip "Embedding model already cached"
fi

# ==============================================================================
# §9 — AGENT PYTHON SOURCE
# ==============================================================================
_banner "07 / AGENT — Python source"

cat > "$AGENT_SRC/__init__.py" <<'PYEOF'
PYEOF

cat > "$AGENT_SRC/config.py" <<'PYEOF'
"""VoiceAI Agent config. v4: memory + web tool config added."""
from __future__ import annotations
import os
from pathlib import Path
from dotenv import load_dotenv

_ENV = Path(__file__).parent.parent / ".env"
if _ENV.is_file(): load_dotenv(str(_ENV), override=False)

LIVEKIT_URL        = os.environ["LIVEKIT_URL"]
LIVEKIT_API_KEY    = os.environ["LIVEKIT_API_KEY"]
LIVEKIT_API_SECRET = os.environ["LIVEKIT_API_SECRET"]

LLM_BASE_URL  = os.environ.get("LLM_BASE_URL",    "http://127.0.0.1:5000/v1")
STT_BASE_URL  = os.environ.get("STT_BASE_URL",    "http://127.0.0.1:5100/v1")
TTS_ROUTER_URL= os.environ.get("TTS_ROUTER_URL",  "http://127.0.0.1:5200")

LLM_MODEL     = os.environ.get("LLM_MODEL",       "Qwen3.5-35B-A3B-EXL3")
STT_MODEL     = os.environ.get("STT_MODEL",        "faster-whisper-medium")
STT_LANGUAGE  = os.environ.get("STT_LANGUAGE",    "")

DEFAULT_PERSONA    = os.environ.get("DEFAULT_PERSONA",    "english_teacher")
AGENT_ADMIN_PORT   = int(os.environ.get("AGENT_ADMIN_PORT", "5800"))
AGENT_DISPATCH_NAME = os.environ.get("AGENT_DISPATCH_NAME", "voiceai-agent")

# Memory (v4)
QDRANT_URL         = os.environ.get("QDRANT_URL",             "http://127.0.0.1:6333")
VOICEAI_MEMORY     = os.environ.get("VOICEAI_MEMORY",         "true").lower() == "true"
VOICEAI_EMBEDDING  = os.environ.get("VOICEAI_EMBEDDING",      "BAAI/bge-small-en-v1.5")
VOICEAI_EMBEDDING_DIM = int(os.environ.get("VOICEAI_EMBEDDING_DIM", "384"))
FASTEMBED_CACHE_PATH  = os.environ.get("FASTEMBED_CACHE_PATH", "")
PYEOF

cat > "$AGENT_SRC/state.py" <<'PYEOF'
"""Agent runtime state containers."""
from __future__ import annotations
import dataclasses
from typing import Optional

@dataclasses.dataclass
class VoiceState:
    persona:    str = "english_teacher"
    voice:      str = "Aiden"
    language:   str = "English"
    instruct:   str = ""
    interruption_mode: str = "balanced"

@dataclasses.dataclass
class MemoryState:
    enabled:          bool = True
    session_id:       str  = ""
    last_checkpoint:  Optional[float] = None
PYEOF

# ── admin.py — lightweight health endpoint (stdlib, no deps) ─────────────────
cat > "$AGENT_SRC/admin.py" <<'PYEOF'
"""Agent health server. Port 5800, stdlib daemon thread."""
from __future__ import annotations
import json, os, threading, time, urllib.error, urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Any

_HOST = "127.0.0.1"
_PORT = int(os.environ.get("AGENT_ADMIN_PORT", "5800"))
_TTS_ROUTER_URL = os.environ.get("TTS_ROUTER_URL", "http://127.0.0.1:5200")
_state: dict[str, Any] = {
    "start_time": time.time(), "session_active": False, "room_name": None,
    "participant_identity": None,
    "persona": "english_teacher", "voice_mode": "customvoice", "voice_speaker": "Aiden",
    "voice_language": "English", "session_tokens": None,
    "memory_enabled": True, "last_checkpoint": None, "last_error": None,
}

def update(**kwargs: Any) -> None: _state.update(kwargs)

def _refresh_voice_mode() -> None:
    try:
        with urllib.request.urlopen(f"{_TTS_ROUTER_URL}/health", timeout=1.5) as resp:
            data = json.loads(resp.read())
        mode = data.get("active_mode")
        if isinstance(mode, str) and mode:
            _state["voice_mode"] = mode
    except (urllib.error.URLError, TimeoutError, ValueError, json.JSONDecodeError):
        pass

class _Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_GET(self):
        if self.path in ("/health", "/status"):
            _refresh_voice_mode()
            snap = {"status": "ok", "uptime_s": round(time.time() - _state["start_time"], 1),
                    **{k: v for k, v in _state.items() if k != "start_time"}}
            body = json.dumps(snap).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers(); self.wfile.write(body)
        else: self.send_response(404); self.end_headers()

def start() -> None:
    import logging; log = logging.getLogger("voiceai.agent.admin")
    try:
        server = HTTPServer((_HOST, _PORT), _Handler)
        threading.Thread(target=server.serve_forever, name="agent-admin", daemon=True).start()
        log.info("[ADMIN] Agent health bound on %s:%d", _HOST, _PORT)
    except OSError as exc:
        log.warning("[ADMIN] Cannot bind %s:%d — %s", _HOST, _PORT, exc)
PYEOF

# ── memory.py — Qdrant-backed 3-tier memory (Ph-8) ───────────────────────────
cat > "$AGENT_SRC/memory.py" <<'PYEOF'
"""
VoiceAI Agent Memory — Qdrant-backed 3-tier backbone.

Collections:
  voiceai_episodic  — session summaries (created at checkpoint)
  voiceai_facts     — durable user facts/preferences
  voiceai_chunks    — searchable conversation history

Embedding: fastembed BAAI/bge-small-en-v1.5 (384-dim, CPU, ~130MB, cached)

Payload schema (all collections):
  memory_type  str   — episodic | facts | chunks
  user_id      str
  room_id      str
  session_id   str
  persona      str
  speaker      str   — user | agent
  created_at   float — UNIX timestamp
  text         str
  tags         list[str]
  confidence   float — 0.0–1.0
  source_turn  int | None

Truthful guarantees:
  - All metrics derive from real Qdrant responses.
  - No fake retrieval magic.
  - Context is only injected when explicitly requested.
"""
from __future__ import annotations
import asyncio, logging, os, time, uuid
from typing import Any, Optional
log = logging.getLogger("voiceai.agent.memory")

QDRANT_URL      = os.environ.get("QDRANT_URL",           "http://127.0.0.1:6333")
EMBEDDING_MODEL = os.environ.get("VOICEAI_EMBEDDING",    "BAAI/bge-small-en-v1.5")
EMBEDDING_DIM   = int(os.environ.get("VOICEAI_EMBEDDING_DIM", "384"))
FASTEMBED_CACHE = os.environ.get("FASTEMBED_CACHE_PATH", "")

_COLLECTIONS = {
    "episodic": "voiceai_episodic",
    "facts":    "voiceai_facts",
    "chunks":   "voiceai_chunks",
}
_client = None; _embedder = None

def _get_client():
    global _client
    if _client is None:
        from qdrant_client import QdrantClient
        _client = QdrantClient(url=QDRANT_URL)
    return _client

def _get_embedder():
    global _embedder
    if _embedder is None:
        if FASTEMBED_CACHE: os.environ["FASTEMBED_CACHE_PATH"] = FASTEMBED_CACHE
        from fastembed import TextEmbedding
        _embedder = TextEmbedding(model_name=EMBEDDING_MODEL)
    return _embedder

def _embed(text: str) -> list[float]:
    return list(list(_get_embedder().embed([text]))[0])

async def init_collections() -> None:
    from qdrant_client.models import Distance, VectorParams
    client = _get_client()
    existing = {c.name for c in client.get_collections().collections}
    for coll_name in _COLLECTIONS.values():
        if coll_name not in existing:
            client.create_collection(
                collection_name=coll_name,
                vectors_config=VectorParams(size=EMBEDDING_DIM, distance=Distance.COSINE))
            log.info("[MEMORY] Created collection: %s", coll_name)
        else:
            log.debug("[MEMORY] Collection exists: %s", coll_name)

async def upsert(*, memory_type: str, text: str, user_id: str = "default",
                 room_id: str = "", session_id: str = "", persona: str = "default",
                 speaker: str = "agent", tags: Optional[list[str]] = None,
                 confidence: float = 1.0, source_turn: Optional[int] = None) -> str:
    if memory_type not in _COLLECTIONS:
        raise ValueError(f"Unknown memory_type '{memory_type}'")
    from qdrant_client.models import PointStruct
    point_id = str(uuid.uuid4())
    payload = {"memory_type": memory_type, "user_id": user_id, "room_id": room_id,
               "session_id": session_id, "persona": persona, "speaker": speaker,
               "created_at": time.time(), "text": text, "tags": tags or [],
               "confidence": confidence, "source_turn": source_turn}
    def _do():
        vector = _embed(text)
        _get_client().upsert(collection_name=_COLLECTIONS[memory_type],
                             points=[PointStruct(id=point_id, vector=vector, payload=payload)])
    await asyncio.to_thread(_do)
    return point_id

async def search(*, query: str, user_id: str = "", session_id: str = "",
                 memory_types: Optional[list[str]] = None, limit: int = 5,
                 score_threshold: float = 0.5) -> list[dict[str, Any]]:
    types = memory_types or list(_COLLECTIONS)
    for t in types:
        if t not in _COLLECTIONS: raise ValueError(f"Unknown memory_type '{t}'")
    def _do_search() -> list[dict]:
        from qdrant_client.models import Filter, FieldCondition, MatchValue
        vector = _embed(query); client = _get_client(); results = []
        for t in types:
            conditions = []
            if user_id:    conditions.append(FieldCondition(key="user_id",   match=MatchValue(value=user_id)))
            if session_id: conditions.append(FieldCondition(key="session_id",match=MatchValue(value=session_id)))
            qf = Filter(must=conditions) if conditions else None
            hits = client.search(collection_name=_COLLECTIONS[t], query_vector=vector,
                                 limit=limit, score_threshold=score_threshold,
                                 query_filter=qf, with_payload=True)
            for h in hits: results.append({"score": h.score, "payload": h.payload, "id": h.id})
        return sorted(results, key=lambda x: x["score"], reverse=True)[:limit]
    return await asyncio.to_thread(_do_search)

async def checkpoint_session(*, session_id: str, room_id: str, user_id: str,
                              persona: str, summary: str,
                              facts: Optional[list[str]] = None) -> dict[str, Any]:
    ep_id = await upsert(memory_type="episodic", text=summary, user_id=user_id,
                         room_id=room_id, session_id=session_id, persona=persona,
                         speaker="agent", confidence=1.0)
    fact_ids: list[str] = []
    for fact in (facts or []):
        fid = await upsert(memory_type="facts", text=fact, user_id=user_id,
                           room_id=room_id, session_id=session_id, persona=persona,
                           speaker="agent", confidence=0.9)
        fact_ids.append(fid)
    log.info("[MEMORY] Checkpoint  episodic=%s  facts=%d", ep_id[:8], len(fact_ids))
    return {"episodic_id": ep_id, "fact_ids": fact_ids, "ts": time.time()}

async def restore_context(*, user_id: str, query: str, limit: int = 3) -> list[dict[str, Any]]:
    return await search(query=query, user_id=user_id, limit=limit)

def health() -> dict[str, Any]:
    try:
        client = _get_client()
        info   = client.get_collections()
        colls  = {c.name: c.vectors_count for c in info.collections}
        return {"online": True, "collections": colls}
    except Exception as exc:
        return {"online": False, "error": str(exc)}
PYEOF

# ── session_control.py v4 — narrowed + memory RPC ────────────────────────────
cat > "$AGENT_SRC/session_control.py" <<'PYEOF'
"""
VoiceAI Agent — LiveKit RPC Session Control  v4.

Ph-5 narrowing: session voice commands are ONLY:
  set_persona              — LLM character
  set_session_voice        — voice, language, instruct ONLY
  set_interruption_behavior — VAD hint

Ph-9 explicit memory control-plane RPC (frontend/admin initiated, NOT voice-driven):
  set_memory_enabled        — toggle memory on/off for this session
  create_memory_checkpoint  — summarize + persist current session
  restore_previous_context  — search + retrieve prior context
  search_memory             — explicit memory search

MUST-NOT-EXPOSE as session commands:
  temperature / cfg_weight / exaggeration (engine internals → admin only)
  global TTS engine switch (backend-admin only)
  global STT model switch  (backend-admin only)
  LLM sampler tuning       (not a session voice concern)
"""
from __future__ import annotations
import json, logging
from typing import Optional
from . import admin as agent_admin
from .state import MemoryState, VoiceState
log = logging.getLogger("voiceai.agent.session_control")

async def _set_attrs(room, attrs: dict[str, str]) -> None:
    try: await room.local_participant.set_attributes(attrs)
    except Exception as exc: log.warning("[RPC] set_attributes failed: %s", exc)

def register_rpc_methods(room, agent, voice_state: VoiceState,
                         memory_state: MemoryState, memory_module) -> None:
    """Register all session-control RPC methods. Called once after room.connect()."""

    @room.local_participant.register_rpc_method("set_persona")
    async def _set_persona(data):
        payload = json.loads(data.payload)
        name = payload.get("name", "").strip()
        if not name: return json.dumps({"error": "name required"})
        voice_state.persona = name
        agent_admin.update(persona=name)
        await _set_attrs(room, {"va.persona": name})
        log.info("[SESSION] persona → %s", name)
        return json.dumps({"ok": True, "persona": name})

    @room.local_participant.register_rpc_method("set_session_voice")
    async def _set_session_voice(data):
        payload = json.loads(data.payload)
        if "voice"    in payload: voice_state.voice    = payload["voice"]
        if "language" in payload: voice_state.language = payload["language"]
        if "instruct" in payload: voice_state.instruct = payload["instruct"]
        agent_admin.update(voice_speaker=voice_state.voice,
                           voice_language=voice_state.language)
        await _set_attrs(room, {
            "va.voice":    voice_state.voice,
            "va.language": voice_state.language,
            "va.instruct": voice_state.instruct,
        })
        log.info("[SESSION] voice=%s lang=%s instruct=%s",
                 voice_state.voice, voice_state.language, voice_state.instruct)
        return json.dumps({"ok": True, "voice": voice_state.voice,
                           "language": voice_state.language, "instruct": voice_state.instruct})

    @room.local_participant.register_rpc_method("set_interruption_behavior")
    async def _set_interruption(data):
        payload = json.loads(data.payload)
        mode = payload.get("mode", "balanced")
        voice_state.interruption_mode = mode
        await _set_attrs(room, {"va.interruption_mode": mode})
        log.info("[SESSION] interruption_mode → %s", mode)
        return json.dumps({"ok": True, "mode": mode})

    # ── Memory control-plane RPCs (Ph-9) — NOT voice-session-driven ───────────

    @room.local_participant.register_rpc_method("set_memory_enabled")
    async def _set_memory_enabled(data):
        payload = json.loads(data.payload)
        enabled = bool(payload.get("enabled", True))
        memory_state.enabled = enabled
        agent_admin.update(memory_enabled=enabled)
        await _set_attrs(room, {"va.memory_enabled": str(enabled).lower()})
        log.info("[MEMORY_RPC] memory_enabled → %s", enabled)
        return json.dumps({"ok": True, "memory_enabled": enabled})

    @room.local_participant.register_rpc_method("create_memory_checkpoint")
    async def _create_checkpoint(data):
        if memory_module is None:
            return json.dumps({"error": "memory module not available"})
        payload = json.loads(data.payload)
        summary    = payload.get("summary", "")
        session_id = payload.get("session_id", memory_state.session_id)
        if not summary: return json.dumps({"error": "summary required"})
        try:
            result = await memory_module.checkpoint_session(
                session_id=session_id, room_id=room.name,
                user_id="default", persona=voice_state.persona,
                summary=summary, facts=payload.get("facts"),
            )
            agent_admin.update(last_checkpoint=result["ts"])
            return json.dumps({"ok": True, **result})
        except Exception as exc:
            log.warning("[MEMORY_RPC] checkpoint failed: %s", exc)
            return json.dumps({"error": str(exc)})

    @room.local_participant.register_rpc_method("restore_previous_context")
    async def _restore_context(data):
        if memory_module is None:
            return json.dumps({"error": "memory module not available"})
        payload = json.loads(data.payload)
        query   = payload.get("query", "")
        user_id = payload.get("user_id", "default")
        if not query: return json.dumps({"error": "query required"})
        try:
            results = await memory_module.restore_context(user_id=user_id, query=query)
            return json.dumps({"ok": True, "results": results})
        except Exception as exc:
            return json.dumps({"error": str(exc)})

    @room.local_participant.register_rpc_method("search_memory")
    async def _search_memory(data):
        if memory_module is None:
            return json.dumps({"error": "memory module not available"})
        payload = json.loads(data.payload)
        query   = payload.get("query", "")
        limit   = int(payload.get("limit", 5))
        if not query: return json.dumps({"error": "query required"})
        try:
            results = await memory_module.search(query=query, limit=limit)
            return json.dumps({"ok": True, "results": results})
        except Exception as exc:
            return json.dumps({"error": str(exc)})
PYEOF

cat > "$AGENT_SRC/main.py" <<'PYEOF'
#!/usr/bin/env python3
"""VoiceAI Agent entry-point. v4: memory + narrowed session control."""
from __future__ import annotations
import asyncio, logging, logging.config, uuid
from pathlib import Path
from livekit.agents import Agent, AgentSession, JobContext, WorkerOptions, cli, room_io
from livekit.agents.llm import ChatContext
from livekit.plugins import openai as lk_openai, silero
from . import admin as agent_admin
from . import config as cfg
from . import memory as mem_module
from .session_control import register_rpc_methods
from .state import MemoryState, VoiceState

_LOG = {
    "version": 1, "disable_existing_loggers": False,
    "formatters": {"plain": {"format": "%(asctime)s  %(levelname)-8s  %(name)-35s  %(message)s",
                             "datefmt": "%H:%M:%S"}},
    "handlers":  {"stdout": {"class": "logging.StreamHandler", "stream": "ext://sys.stdout",
                             "formatter": "plain"}},
    "root": {"level": "INFO", "handlers": ["stdout"]},
}
logging.config.dictConfig(_LOG)
log = logging.getLogger("voiceai.agent.main")

def _load_persona(name: str) -> str:
    pdir = Path(cfg.__file__).parent.parent / "personas"
    for p in (pdir / f"{name}.md", pdir / "default.md"):
        if p.is_file():
            txt = p.read_text(encoding="utf-8")
            # Strip YAML front-matter
            if txt.startswith("---"):
                parts = txt.split("---", 2)
                if len(parts) >= 3: return parts[2].strip()
            return txt.strip()
    return "You are a helpful AI assistant."


def _normalized_stt_language(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = str(value).strip()
    return normalized or None

async def entrypoint(ctx: JobContext):
    await ctx.connect()
    participant = await ctx.wait_for_participant()
    voice_state  = VoiceState(persona=cfg.DEFAULT_PERSONA)
    memory_state = MemoryState(enabled=cfg.VOICEAI_MEMORY,
                               session_id=str(uuid.uuid4()))
    shutdown_event = asyncio.Event()

    async def _on_shutdown(*_args):
        shutdown_event.set()

    ctx.add_shutdown_callback(_on_shutdown)

    # Memory init (non-fatal)
    memory_mod = None
    if cfg.VOICEAI_MEMORY:
        try:
            await mem_module.init_collections()
            memory_mod = mem_module
            log.info("[MAIN] Qdrant memory ready")
        except Exception as exc:
            log.warning("[MAIN] Memory unavailable: %s — continuing without memory", exc)

    system_prompt = _load_persona(voice_state.persona)
    llm = lk_openai.LLM(
        model=cfg.LLM_MODEL,
        base_url=cfg.LLM_BASE_URL,
        api_key="local",
    )
    stt_language = _normalized_stt_language(cfg.STT_LANGUAGE)
    stt_kwargs = {
        "model": cfg.STT_MODEL,
        "base_url": cfg.STT_BASE_URL,
        "api_key": "local",
    }
    if stt_language is not None:
        stt_kwargs["language"] = stt_language
    stt = lk_openai.STT(**stt_kwargs)
    tts = lk_openai.TTS(
        model="tts-1",
        base_url=cfg.TTS_ROUTER_URL + "/v1",
        api_key="local",
        voice=voice_state.voice,
        response_format="wav",
    )
    vad = silero.VAD.load()
    session = AgentSession(llm=llm, stt=stt, tts=tts, vad=vad)
    agent = Agent(instructions=system_prompt)

    register_rpc_methods(ctx.room, agent, voice_state, memory_state, memory_mod)

    participant_identity = getattr(ctx.room.local_participant, "identity", None)
    linked_identity = getattr(participant, "identity", None)
    agent_admin.update(session_active=True,
                       room_name=ctx.room.name,
                       participant_identity=participant_identity,
                       persona=voice_state.persona,
                       memory_enabled=cfg.VOICEAI_MEMORY,
                       voice_speaker=voice_state.voice,
                       voice_language=voice_state.language)
    log.info("[MAIN] Session started  room=%s  participant=%s  linked_user=%s  persona=%s  memory=%s",
             ctx.room.name, participant_identity, linked_identity, voice_state.persona, cfg.VOICEAI_MEMORY)
    try:
        await session.start(
            agent=agent,
            room=ctx.room,
            room_options=room_io.RoomOptions(
                participant_identity=linked_identity,
                close_on_disconnect=True,
            ),
        )
        await shutdown_event.wait()
    finally:
        agent_admin.update(session_active=False,
                           room_name=None,
                           participant_identity=None,
                           memory_enabled=memory_state.enabled)
        log.info("[MAIN] Session ended  room=%s", ctx.room.name)

if __name__ == "__main__":
    agent_admin.start()
    cli.run_app(WorkerOptions(entrypoint_fnc=entrypoint,
                              api_key=cfg.LIVEKIT_API_KEY,
                              api_secret=cfg.LIVEKIT_API_SECRET,
                              ws_url=cfg.LIVEKIT_URL,
                              agent_name=cfg.AGENT_DISPATCH_NAME))
PYEOF

# ==============================================================================
# §9 — PERSONAS
# ==============================================================================
_banner "07 / AGENT — Personas"

for pf_name in default english_teacher best_friend chill_assistant; do
  pf_body=""
  case "$pf_name" in
    default)
      pf_body="You are a helpful, concise AI voice assistant. Respond naturally in spoken language. Keep answers brief and clear — the user is listening, not reading." ;;
    english_teacher)
      pf_body="You are a warm, encouraging English teacher. Help the user practice English naturally. When they make a grammar or vocabulary mistake, acknowledge what they said and gently include the correct form in your reply without stopping the conversation." ;;
    best_friend)
      pf_body="You are the user's close, casual best friend. Talk naturally and warmly. Use relaxed language, show genuine interest, keep conversation light and supportive." ;;
    chill_assistant)
      pf_body="You are a calm, minimal assistant. Give clear, direct answers without filler. Relaxed and efficient. Don't over-explain. Short and useful." ;;
  esac
  cat > "$PERSONAS_DIR/${pf_name}.md" <<MDEOF
---
name: ${pf_name}
version: 1
---
${pf_body}
MDEOF
done
_ok "Personas written: default, english_teacher, best_friend, chill_assistant"

# ==============================================================================
# §9 — AGENT .ENV + START SCRIPT
# ==============================================================================
_banner "07 / AGENT — .env + start script"

AGENT_ENV="$AGENT_DIR/.env"
( umask 177
  {
    printf '# Auto-generated by bootstrap.sh v4
'
    printf 'LIVEKIT_URL=%s
'             "${LIVEKIT_URL:-ws://127.0.0.1:7880}"
    printf 'LIVEKIT_API_KEY=%s
'         "${LIVEKIT_API_KEY:?LIVEKIT_API_KEY missing}"
    printf 'LIVEKIT_API_SECRET=%s
'      "${LIVEKIT_API_SECRET:?LIVEKIT_API_SECRET missing}"
    printf 'LLM_BASE_URL=http://127.0.0.1:%d/v1
' "$PORT_LLM"
    printf 'STT_BASE_URL=http://127.0.0.1:%d/v1
' "$PORT_STT"
    printf 'TTS_ROUTER_URL=http://127.0.0.1:%d
'  "$PORT_TTS_ROUTER"
    printf 'LLM_MODEL=Qwen3.5-35B-A3B-EXL3
'
    printf 'STT_MODEL=%s
'               "$STT_DEFAULT_MODEL"
    printf 'STT_LANGUAGE=en
'
    printf 'DEFAULT_PERSONA=english_teacher
'
    printf 'AGENT_ADMIN_PORT=%d
'        "$PORT_AGENT_ADMIN"
    printf 'AGENT_DISPATCH_NAME=voiceai-agent
'
    printf 'QDRANT_URL=http://127.0.0.1:%d
' "$PORT_QDRANT_REST"
    printf 'VOICEAI_MEMORY=true
'
    printf 'VOICEAI_EMBEDDING=%s
'       "$EMBEDDING_MODEL"
    printf 'VOICEAI_EMBEDDING_DIM=%d
'   "$EMBEDDING_DIM"
    printf 'FASTEMBED_CACHE_PATH=%s/.cache/fastembed
' "$ROOT"
  } > "$AGENT_ENV"
)
_ok "agent/.env written (600)"
_harden "$AGENT_ENV"

cat > "$ROOT/bin/start-agent.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
. "$HOME/.config/voiceai/env.sh"
AGENT_DIR="$VOICEAI_ROOT/agent"
set -a
# shellcheck source=/dev/null
. "$AGENT_DIR/.env"
set +a
cd "$AGENT_DIR"
echo "[AGENT] Starting  persona=${DEFAULT_PERSONA:-english_teacher}  memory=${VOICEAI_MEMORY:-true}"
exec "$AGENT_DIR/venv/bin/python" -m src.main start
SCRIPT
chmod +x "$ROOT/bin/start-agent.sh"
_ok "Agent source written (v4: memory + narrowed session control)"
