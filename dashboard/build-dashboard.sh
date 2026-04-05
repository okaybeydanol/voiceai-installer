#!/usr/bin/env bash
# ==============================================================================
# build-dashboard.sh — VoiceAI Command Center v2
# Backend truth : bootstrap.sh + voiceai_ctl.sh
# One file = one heredoc block. Sequential. No patches.
# ==============================================================================
set -euo pipefail

APP_NAME="voiceai-dashboard"

command -v node >/dev/null 2>&1 || { echo "ERROR: Node.js not found."; exit 1; }
command -v npm  >/dev/null 2>&1 || { echo "ERROR: npm not found."; exit 1; }

echo
echo "╔══════════════════════════════════════════════════════╗"
echo "║   VoiceAI Command Center — Dashboard Builder v2      ║"
echo "╚══════════════════════════════════════════════════════╝"
echo "  Node: $(node --version)  npm: $(npm --version)"
echo

[ -d "$APP_NAME" ] && { echo "ERROR: '$APP_NAME' already exists. Remove it first."; exit 1; }

# ── Source voiceai env ────────────────────────────────────────────────────────
ENV_SH="$HOME/.config/voiceai/env.sh"
LIVEKIT_URL="ws://127.0.0.1:7880"
LIVEKIT_API_KEY=""
LIVEKIT_API_SECRET=""
VOICEAI_ROOT="$HOME/ai-projects/voiceai"

if [ -f "$ENV_SH" ]; then
  # shellcheck source=/dev/null
  . "$ENV_SH"
  LIVEKIT_URL="${LIVEKIT_URL:-ws://127.0.0.1:7880}"
  echo "  [ENV] Sourced: $ENV_SH"
else
  echo "  [WARN] $ENV_SH not found — using defaults"
fi

# ── Directory scaffold ────────────────────────────────────────────────────────
mkdir -p "$APP_NAME" && cd "$APP_NAME"

mkdir -p \
  app/api/livekit/token \
  app/api/livekit/dispatch \
  app/api/tts/switch \
  app/api/stt/switch \
  app/api/tools/webfetch \
  app/api/personas \
  'app/api/personas/[name]' \
  'app/api/reference-audio/[voice]' \
  components/layout \
  components/overview \
  components/session \
  components/services \
  components/memory \
  components/tools \
  components/shared \
  components/personas \
  hooks \
  lib \
  server

echo "  [DIR] Project tree ready"

# ==============================================================================
# 1 · package.json
# ==============================================================================
cat > package.json << 'EOF'
{
  "name": "voiceai-dashboard",
  "version": "0.2.0",
  "private": true,
  "scripts": {
    "dev":   "next dev",
    "build": "next build",
    "start": "next start",
    "lint":  "next lint"
  },
  "dependencies": {
    "@livekit/components-react": "^2.6.0",
    "@livekit/components-styles": "^1.1.2",
    "@livekit/protocol": "^1.44.1",
    "clsx": "^2.1.1",
    "js-yaml": "^4.1.0",
    "livekit-client": "^2.5.0",
    "livekit-server-sdk": "^2.6.0",
    "lucide-react": "^0.468.0",
    "next": "14.2.18",
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "tailwind-merge": "^2.5.4"
  },
  "devDependencies": {
    "@types/js-yaml": "^4.0.9",
    "@types/node": "^22.5.0",
    "@types/react": "^18.3.3",
    "@types/react-dom": "^18.3.0",
    "autoprefixer": "^10.4.20",
    "eslint": "^8",
    "eslint-config-next": "14.2.18",
    "postcss": "^8.4.41",
    "tailwindcss": "^3.4.10",
    "typescript": "^5.5.4"
  }
}
EOF

# ==============================================================================
# 2 · tsconfig.json
# ==============================================================================
cat > tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "plugins": [{ "name": "next" }],
    "paths": { "@/*": ["./*"] }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}
EOF

# ==============================================================================
# 3 · next.config.js — proxy rewrites to local backend services
# ==============================================================================
cat > next.config.js << 'EOF'
/** @type {import('next').NextConfig} */
const nextConfig = {
  async rewrites() {
    return [
      { source: "/api/proxy/tts/:path*",      destination: "http://127.0.0.1:5200/:path*" },
      { source: "/api/proxy/stt/:path*",       destination: "http://127.0.0.1:5100/:path*" },
      { source: "/api/proxy/llm/:path*",       destination: "http://127.0.0.1:5000/:path*" },
      { source: "/api/proxy/agent/:path*",     destination: "http://127.0.0.1:5800/:path*" },
      { source: "/api/proxy/telemetry/:path*", destination: "http://127.0.0.1:5900/:path*" },
      { source: "/api/proxy/qdrant/:path*",    destination: "http://127.0.0.1:6333/:path*" },
      { source: "/api/proxy/livekit/:path*",   destination: "http://127.0.0.1:7880/:path*" },
    ];
  },
};

module.exports = nextConfig;
EOF

# ==============================================================================
# 4 · tailwind.config.ts
# ==============================================================================
cat > tailwind.config.ts << 'EOF'
import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./app/**/*.{ts,tsx}",
    "./components/**/*.{ts,tsx}",
    "./hooks/**/*.{ts,tsx}",
    "./lib/**/*.{ts,tsx}",
    "./server/**/*.{ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        obsidian: "#080B0F",
      },
      fontFamily: {
        sans: ["Inter Tight", "ui-sans-serif", "sans-serif"],
        mono: ["JetBrains Mono", "ui-monospace", "monospace"],
      },
    },
  },
  plugins: [],
};

export default config;
EOF

# ==============================================================================
# 5 · postcss.config.js
# ==============================================================================
cat > postcss.config.js << 'EOF'
module.exports = {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
};
EOF

# ==============================================================================
# 6 · .eslintrc.json
# ==============================================================================
cat > .eslintrc.json << 'EOF'
{ "extends": "next/core-web-vitals" }
EOF

# ==============================================================================
# 7 · .gitignore
# ==============================================================================
cat > .gitignore << 'EOF'
.next/
node_modules/
.env.local
EOF

# ==============================================================================
# 8 · .env.local  (shell vars expanded intentionally)
# ==============================================================================
cat > .env.local << ENVEOF
# Server-side only. DO NOT commit.
LIVEKIT_URL=${LIVEKIT_URL}
LIVEKIT_API_KEY=${LIVEKIT_API_KEY}
LIVEKIT_API_SECRET=${LIVEKIT_API_SECRET}
VOICEAI_ROOT=${VOICEAI_ROOT}
VOICEAI_AGENT_NAME=${VOICEAI_AGENT_NAME:-voiceai-agent}
ENVEOF

# ==============================================================================
# 9 · app/globals.css
# .meter-fill width is driven by CSS custom property --mw to avoid
# inline presentation style values on the element.
# ==============================================================================
cat > app/globals.css << 'EOF'
@import url('https://fonts.googleapis.com/css2?family=Inter+Tight:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500;600&display=swap');

@tailwind base;
@tailwind components;
@tailwind utilities;

:root {
  color-scheme: dark;
}

*,
*::before,
*::after {
  box-sizing: border-box;
}

html,
body {
  height: 100%;
  background: #080B0F;
  color: #e2e8f0;
  font-family: "Inter Tight", sans-serif;
  -webkit-font-smoothing: antialiased;
}

::-webkit-scrollbar             { width: 4px; height: 4px; }
::-webkit-scrollbar-track       { background: transparent; }
::-webkit-scrollbar-thumb       { background: rgba(255, 255, 255, 0.08); border-radius: 99px; }
::-webkit-scrollbar-thumb:hover { background: rgba(255, 255, 255, 0.16); }

button { font-family: inherit; }

/* ProgressBar: set --mw via style prop; keeps width out of inline style values */
.meter-fill { width: var(--mw, 0%); }
EOF

# ==============================================================================
# 10 · app/layout.tsx
# ==============================================================================
cat > app/layout.tsx << 'EOF'
import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "VoiceAI Command Center",
  description: "Local AI Voice Orchestration Dashboard",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="h-full">
      <body className="h-full bg-[#080B0F] antialiased">{children}</body>
    </html>
  );
}
EOF

# ==============================================================================
# 11 · app/page.tsx
# ==============================================================================
cat > app/page.tsx << 'EOF'
import { AppShell } from "@/components/layout/AppShell";

export default function Home() {
  return <AppShell />;
}
EOF

# ==============================================================================
# 12 · app/api/livekit/token/route.ts
# Server-only. Room is fixed to "voice-room". Identity is unique per request.
# Token grants canPublish=true so MicButton can enable the mic after connect.
# The client connects with audio={false} — listen-only until the user acts.
# ==============================================================================
cat > app/api/livekit/token/route.ts << 'EOF'
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

import { NextResponse } from "next/server";
import { AccessToken } from "livekit-server-sdk";
import { RoomAgentDispatch, RoomConfiguration } from "@livekit/protocol";
import { serverConfig } from "@/server/config";
import { LIVEKIT_ROOM } from "@/lib/constants";

export async function GET(): Promise<NextResponse> {
  const { livekitApiKey, livekitApiSecret, livekitUrl, voiceaiAgentName } = serverConfig;

  if (!livekitApiKey || !livekitApiSecret) {
    return NextResponse.json(
      { error: "LiveKit credentials not configured. Set LIVEKIT_API_KEY and LIVEKIT_API_SECRET in .env.local." },
      { status: 500 },
    );
  }

  const roomName = `${LIVEKIT_ROOM}-${Date.now()}`;
  const identity = `dashboard-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

  const at = new AccessToken(livekitApiKey, livekitApiSecret, { identity, ttl: "4h" });
  at.addGrant({
    roomJoin:       true,
    room:           roomName,
    canPublish:     true,
    canSubscribe:   true,
    canPublishData: true,
  });
  at.roomConfig = new RoomConfiguration({
    agents: [
      new RoomAgentDispatch({
        agentName: voiceaiAgentName,
        metadata: JSON.stringify({ source: "dashboard", identity }),
      }),
    ],
  });

  const token = await at.toJwt();
  return NextResponse.json({ token, url: livekitUrl, roomName, identity });
}
EOF

# ==============================================================================
# ==============================================================================
# 13 · app/api/livekit/dispatch/route.ts — explicit agent dispatch
# Creates a dispatch for the configured agent to join the requested room.
# ==============================================================================
cat > app/api/livekit/dispatch/route.ts << 'EOF'
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

import { NextRequest, NextResponse } from "next/server";
import { AgentDispatchClient } from "livekit-server-sdk";
import { serverConfig } from "@/server/config";

export async function POST(req: NextRequest): Promise<NextResponse> {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ ok: false, message: "Invalid JSON body" }, { status: 400 });
  }

  const { roomName, metadata } = body as { roomName?: string; metadata?: Record<string, unknown> };
  if (!roomName || typeof roomName !== "string") {
    return NextResponse.json({ ok: false, message: "roomName required" }, { status: 400 });
  }

  const { livekitHttpUrl, livekitApiKey, livekitApiSecret, voiceaiAgentName } = serverConfig;
  if (!voiceaiAgentName) {
    return NextResponse.json({ ok: false, message: "VOICEAI_AGENT_NAME is empty" }, { status: 500 });
  }

  try {
    const client = new AgentDispatchClient(livekitHttpUrl, livekitApiKey, livekitApiSecret);
    const created = await client.createDispatch(roomName, voiceaiAgentName, {
      metadata: JSON.stringify(metadata ?? {}),
    });

    return NextResponse.json({
      ok: true,
      message: `Dispatched '${voiceaiAgentName}' to ${roomName}`,
      dispatchId: created.id,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return NextResponse.json({ ok: false, message: `Agent dispatch failed: ${message}` }, { status: 502 });
  }
}
EOF

# 13 · app/api/tts/switch/route.ts — global TTS engine switch
# ==============================================================================
cat > app/api/tts/switch/route.ts << 'EOF'
export const runtime = "nodejs";

import { NextRequest, NextResponse } from "next/server";
import { TTS_MODES, type TtsMode } from "@/lib/types";

const TTS_ROUTER_URL = "http://127.0.0.1:5200";

export async function POST(req: NextRequest): Promise<NextResponse> {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ ok: false, message: "Invalid JSON body" }, { status: 400 });
  }

  const { mode } = body as { mode?: string };
  if (!mode || !(TTS_MODES as readonly string[]).includes(mode)) {
    return NextResponse.json(
      { ok: false, message: `Invalid mode '${mode}'. Valid: ${TTS_MODES.join(", ")}` },
      { status: 400 },
    );
  }

  try {
    const upstream = await fetch(`${TTS_ROUTER_URL}/admin/switch_model`, {
      method:  "POST",
      headers: { "Content-Type": "application/json" },
      body:    JSON.stringify({ mode: mode as TtsMode }),
      signal:  AbortSignal.timeout(10_000),
    });
    const data = await upstream.json().catch(() => ({}));
    return NextResponse.json(data, { status: upstream.status });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return NextResponse.json({ ok: false, message: `TTS router unreachable: ${message}` }, { status: 502 });
  }
}
EOF

# ==============================================================================
# 14 · app/api/stt/switch/route.ts — global STT model switch via backend HTTP
# Mirrors the TTS pattern: Next route validates, backend STT admin endpoint writes config.
# ==============================================================================
cat > app/api/stt/switch/route.ts << 'EOF'
export const runtime = "nodejs";

import { NextRequest, NextResponse } from "next/server";
import { STT_CANONICAL_MODELS } from "@/lib/types";

const STT_ADMIN_URL = "http://127.0.0.1:5100";
const CANONICAL = new Set<string>(STT_CANONICAL_MODELS);

export async function POST(req: NextRequest): Promise<NextResponse> {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ ok: false, message: "Invalid JSON body" }, { status: 400 });
  }

  const { model } = body as { model?: string };
  if (!model || !CANONICAL.has(model)) {
    return NextResponse.json(
      { ok: false, message: `Invalid model. Canonical: ${[...CANONICAL].join(", ")}` },
      { status: 400 },
    );
  }

  try {
    const upstream = await fetch(`${STT_ADMIN_URL}/admin/switch_model`, {
      method:  "POST",
      headers: { "Content-Type": "application/json" },
      body:    JSON.stringify({ model }),
      signal:  AbortSignal.timeout(10_000),
    });
    const data = await upstream.json().catch(() => ({}));
    return NextResponse.json(data, { status: upstream.status });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return NextResponse.json({ ok: false, message: `STT service unreachable: ${message}` }, { status: 502 });
  }
}
EOF

# ==============================================================================
# 15 · app/api/tools/webfetch/route.ts
# Explicit operator-triggered fetch only. Loopback addresses blocked.
# No JS execution. No automatic memory save.
# ==============================================================================
cat > app/api/tools/webfetch/route.ts << 'EOF'
export const runtime = "nodejs";

import { NextRequest, NextResponse } from "next/server";
import { safeUrl } from "@/lib/utils";

const TIMEOUT_MS  = 15_000;
const MAX_BYTES   = 512_000;
const BLOCKED_IPS = new Set(["localhost", "127.0.0.1", "0.0.0.0", "::1", "[::1]"]);

export async function POST(req: NextRequest): Promise<NextResponse> {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ ok: false, error: "Invalid JSON body" }, { status: 400 });
  }

  const { url } = body as { url?: string };
  if (!url) {
    return NextResponse.json({ ok: false, error: "Missing url" }, { status: 400 });
  }

  const parsed = safeUrl(url);
  if (!parsed) {
    return NextResponse.json({ ok: false, error: "Invalid URL (http/https only)" }, { status: 400 });
  }
  if (BLOCKED_IPS.has(parsed.hostname)) {
    return NextResponse.json({ ok: false, error: "Loopback/internal addresses not permitted" }, { status: 400 });
  }

  try {
    const res = await fetch(parsed.toString(), {
      headers: {
        "User-Agent": "VoiceAI-Dashboard/2.0 (operator tool)",
        Accept:       "text/html,text/plain,application/json",
      },
      signal:   AbortSignal.timeout(TIMEOUT_MS),
      redirect: "follow",
    });

    const buf       = new Uint8Array(await res.arrayBuffer());
    const truncated = buf.length > MAX_BYTES;
    const text      = new TextDecoder("utf-8", { fatal: false }).decode(
      truncated ? buf.slice(0, MAX_BYTES) : buf,
    );

    return NextResponse.json({
      ok:           true,
      status:       res.status,
      url:          parsed.toString(),
      content_type: res.headers.get("content-type") ?? "",
      size_bytes:   buf.length,
      truncated,
      text,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return NextResponse.json({ ok: false, error: `Fetch failed: ${message}` }, { status: 502 });
  }
}
EOF

# ==============================================================================
# 16 · app/api/personas/route.ts — list + create persona files
# ==============================================================================
cat > app/api/personas/route.ts << 'EOF'
export const runtime = "nodejs";

import { NextResponse } from "next/server";
import { readdirSync, statSync, writeFileSync, existsSync } from "fs";
import { join, basename } from "path";
import { serverConfig } from "@/server/config";

const PERSONAS_DIR = () => join(serverConfig.voiceaiRoot, "agent", "personas");
const VALID_NAME   = /^[a-zA-Z0-9_-]{1,64}$/;

export async function GET() {
  try {
    const dir   = PERSONAS_DIR();
    const files = existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith(".md")) : [];
    return NextResponse.json({
      personas: files.map((f) => ({
        name:       basename(f, ".md"),
        filename:   f,
        size_bytes: statSync(join(dir, f)).size,
      })),
      count: files.length,
    });
  } catch (err) {
    return NextResponse.json({ personas: [], count: 0, error: String(err) });
  }
}

export async function POST(req: Request) {
  const body = await req.json().catch(() => ({})) as { name?: string };
  const { name } = body;

  if (!name || !VALID_NAME.test(name)) {
    return NextResponse.json(
      { ok: false, message: "Invalid name (alphanumeric/dash/underscore, 1-64 chars)" },
      { status: 400 },
    );
  }

  const fp = join(PERSONAS_DIR(), `${name}.md`);
  if (existsSync(fp)) {
    return NextResponse.json({ ok: false, message: `'${name}' already exists` }, { status: 409 });
  }

  writeFileSync(fp, `---\ndisplay_name: ${name}\n---\n\nYou are a helpful AI assistant.\n`, "utf8");
  return NextResponse.json({ ok: true, message: `Created '${name}.md'` });
}
EOF

# ==============================================================================
# 17 · app/api/personas/[name]/route.ts — get / put / delete
# Name is validated by regex before any filesystem access (no path traversal).
# ==============================================================================
cat > 'app/api/personas/[name]/route.ts' << 'EOF'
export const runtime = "nodejs";

import { NextRequest, NextResponse } from "next/server";
import { readFileSync, writeFileSync, unlinkSync, existsSync } from "fs";
import { join } from "path";
import { serverConfig } from "@/server/config";

type RouteContext = { params: { name: string } };

const VALID_NAME   = /^[a-zA-Z0-9_-]{1,64}$/;
const personasDir  = () => join(serverConfig.voiceaiRoot, "agent", "personas");
const personaPath  = (name: string) => join(personasDir(), `${name}.md`);

function validateName(name: string): NextResponse | null {
  if (!VALID_NAME.test(name)) {
    return NextResponse.json({ ok: false, message: "Invalid name" }, { status: 400 });
  }
  return null;
}

export async function GET(_req: NextRequest, { params }: RouteContext) {
  const err = validateName(params.name);
  if (err) return err;

  const fp = personaPath(params.name);
  if (!existsSync(fp)) {
    return NextResponse.json({ ok: false, message: "Not found" }, { status: 404 });
  }

  return NextResponse.json({ ok: true, name: params.name, content: readFileSync(fp, "utf8") });
}

export async function PUT(req: NextRequest, { params }: RouteContext) {
  const err = validateName(params.name);
  if (err) return err;

  const body = await req.json().catch(() => ({})) as { content?: string };
  if (typeof body.content !== "string") {
    return NextResponse.json({ ok: false, message: "Missing content" }, { status: 400 });
  }
  if (body.content.length > 65536) {
    return NextResponse.json({ ok: false, message: "Exceeds 64KB limit" }, { status: 400 });
  }

  writeFileSync(personaPath(params.name), body.content, "utf8");
  return NextResponse.json({ ok: true, message: `Saved '${params.name}.md'` });
}

export async function DELETE(_req: NextRequest, { params }: RouteContext) {
  const err = validateName(params.name);
  if (err) return err;

  const fp = personaPath(params.name);
  if (!existsSync(fp)) {
    return NextResponse.json({ ok: false, message: "Not found" }, { status: 404 });
  }

  unlinkSync(fp);
  return NextResponse.json({ ok: true, message: `Deleted '${params.name}.md'` });
}
EOF

# ==============================================================================
# 18 · app/api/reference-audio/[voice]/route.ts
# Serves audio only from VOICEAI_ROOT/inputs/. Name regex prevents traversal.
# ==============================================================================
cat > 'app/api/reference-audio/[voice]/route.ts' << 'EOF'
export const runtime = "nodejs";

import { NextRequest, NextResponse } from "next/server";
import { readFileSync, existsSync } from "fs";
import { join } from "path";
import { serverConfig } from "@/server/config";

type RouteContext = { params: { voice: string } };

const VALID_NAME = /^[a-zA-Z0-9_-]{1,64}$/;
const EXTENSIONS: [string, string][] = [
  [".wav",  "audio/wav"],
  [".mp3",  "audio/mpeg"],
  [".flac", "audio/flac"],
  [".ogg",  "audio/ogg"],
];

export async function GET(_req: NextRequest, { params }: RouteContext) {
  if (!VALID_NAME.test(params.voice)) {
    return NextResponse.json({ error: "Invalid voice name" }, { status: 400 });
  }

  const inputsDir = join(serverConfig.voiceaiRoot, "inputs");

  for (const [ext, mime] of EXTENSIONS) {
    const filePath = join(inputsDir, `${params.voice}${ext}`);
    if (existsSync(filePath)) {
      const buf = readFileSync(filePath);
      return new NextResponse(buf, {
        headers: {
          "Content-Type":   mime,
          "Content-Length": String(buf.length),
          "Cache-Control":  "private, max-age=60",
        },
      });
    }
  }

  return NextResponse.json({ error: `'${params.voice}' not found in inputs/` }, { status: 404 });
}
EOF

# ==============================================================================
# 19 · lib/types.ts — shared domain types for the dashboard
# ==============================================================================
cat > lib/types.ts << 'EOF'
// ── Service / health ──────────────────────────────────────────────────────────

export type ServiceStatus = "online" | "offline" | "degraded" | "unknown";

// ── TTS ───────────────────────────────────────────────────────────────────────

export type TtsMode = "customvoice" | "voicedesign" | "chatterbox";

export const TTS_MODES: readonly TtsMode[] = ["customvoice", "voicedesign", "chatterbox"];

export const TTS_MODE_LABELS: Record<TtsMode, string> = {
  customvoice: "CustomVoice",
  voicedesign: "VoiceDesign",
  chatterbox:  "Chatterbox",
};

/** Mirrors Phase enum in tts/router/src/state.py */
export type RouterPhase =
  | "idle"
  | "draining"
  | "terminating"
  | "vram_settling"
  | "spawning"
  | "probing"
  | "error";

export interface TtsHealth {
  active_mode:  TtsMode | null;
  router_phase: RouterPhase;
  switching:    boolean;
  worker_ready: boolean;
  last_error:   string | null;
  inflight?:    number;
  worker?: {
    vram_total_gb?: number;
    vram_free_gb?:  number;
  };
}

// ── Agent ─────────────────────────────────────────────────────────────────────

/** Mirrors agent/src/admin.py _state keys */
export interface AgentHealth {
  status:          string;
  uptime_s:        number;
  session_active:  boolean;
  room_name:       string | null;
  participant_identity?: string | null;
  persona:         string;
  voice_mode:      string;
  voice_speaker:   string;
  voice_language:  string;
  session_tokens:  number | null;
  memory_enabled:  boolean;
  last_checkpoint: number | null;
  last_error:      string | null;
}

// ── LLM ───────────────────────────────────────────────────────────────────────

export interface LlmContext {
  online:      boolean;
  model:       string | null;
  max_seq_len: number | null;
  error?:      string;
}

// ── STT ───────────────────────────────────────────────────────────────────────

/** Canonical STT model names from bootstrap.sh CANONICAL_STT set */
export const STT_CANONICAL_MODELS = [
  "faster-whisper-tiny",    "faster-whisper-tiny.en",
  "faster-whisper-base",    "faster-whisper-base.en",
  "faster-whisper-small",   "faster-whisper-small.en",
  "faster-whisper-medium",  "faster-whisper-medium.en",
] as const;

export type SttModel = typeof STT_CANONICAL_MODELS[number];

export interface SttModelItem {
  name:      string;
  canonical: boolean;
  files:     number;
}

// ── Machine / GPU ─────────────────────────────────────────────────────────────

export interface GpuMetrics {
  util_percent:  number;
  vram_total_gb: number;
  vram_free_gb:  number;
  temp_c:        number;
}

export interface MachineMetrics {
  cpu_percent: number;
  ram_percent: number;
  gpu?:        GpuMetrics;
}

// ── Memory / Qdrant ───────────────────────────────────────────────────────────

export interface QdrantCollectionStat {
  name:          string;
  vectors_count: number;
}

export interface MemoryInventory {
  online:       boolean;
  collections?: QdrantCollectionStat[];
  error?:       string;
}

// ── Inventory ─────────────────────────────────────────────────────────────────

export interface PersonaItem {
  name:         string;
  display_name: string;
  filename:     string;
}

export interface ReferenceAudio {
  voice:    string;
  filename: string;
  size_kb:  number;
}

// ── Generic ───────────────────────────────────────────────────────────────────

export interface SwitchResult {
  ok:      boolean;
  message: string;
}
EOF

# ==============================================================================
# 20 · lib/constants.ts
# ==============================================================================
cat > lib/constants.ts << 'EOF'
export const POLL = {
  FAST:   3_000,
  NORMAL: 5_000,
  SLOW:   10_000,
} as const;

export const LIVEKIT_ROOM = "voice-room" as const;

export const LANGUAGES_OTHER = [
  { value: "Chinese",    label: "Chinese"    },
  { value: "English",    label: "English"    },
  { value: "Japanese",   label: "Japanese"   },
  { value: "Korean",     label: "Korean"     },
  { value: "German",     label: "German"     },
  { value: "French",     label: "French"     },
  { value: "Russian",    label: "Russian"    },
  { value: "Portuguese", label: "Portuguese" },
  { value: "Spanish",    label: "Spanish"    },
  { value: "Italian",    label: "Italian"    },
] as const;

export const LANGUAGES_CHATTERBOX = [
  { value: "ar", label: "Arabic"     },
  { value: "da", label: "Danish"     },
  { value: "de", label: "German"     },
  { value: "el", label: "Greek"      },
  { value: "en", label: "English"    },
  { value: "es", label: "Spanish"    },
  { value: "fi", label: "Finnish"    },
  { value: "fr", label: "French"     },
  { value: "he", label: "Hebrew"     },
  { value: "hi", label: "Hindi"      },
  { value: "it", label: "Italian"    },
  { value: "ja", label: "Japanese"   },
  { value: "ko", label: "Korean"     },
  { value: "ms", label: "Malay"      },
  { value: "nl", label: "Dutch"      },
  { value: "no", label: "Norwegian"  },
  { value: "pl", label: "Polish"     },
  { value: "pt", label: "Portuguese" },
  { value: "ru", label: "Russian"    },
  { value: "sv", label: "Swedish"    },
  { value: "sw", label: "Swahili"    },
  { value: "tr", label: "Turkish"    },
  { value: "zh", label: "Chinese"    },
] as const;

export const INTERRUPTION_MODES = [
  { value: "patient",    label: "Patient"    },
  { value: "normal",     label: "Normal"     },
  { value: "responsive", label: "Responsive" },
] as const;
EOF

# ==============================================================================
# 21 · lib/utils.ts
# ==============================================================================
cat > lib/utils.ts << 'EOF'
import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}

export function formatUptime(seconds: number): string {
  if (!seconds || seconds < 0) return "—";
  const h   = Math.floor(seconds / 3600);
  const m   = Math.floor((seconds % 3600) / 60);
  const sec = Math.floor(seconds % 60);
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${sec}s`;
  return `${sec}s`;
}

export function formatVram(totalGb?: number, freeGb?: number): string {
  if (totalGb == null || freeGb == null) return "—";
  return `${Math.max(0, totalGb - freeGb).toFixed(1)} / ${totalGb.toFixed(1)} GB`;
}

export function safeUrl(raw: string): URL | null {
  try {
    const u = new URL(raw);
    if (u.protocol !== "https:" && u.protocol !== "http:") return null;
    return u;
  } catch {
    return null;
  }
}
EOF

# ==============================================================================
# 22 · server/config.ts — server-only; never import from client components
# ==============================================================================
cat > server/config.ts << 'EOF'
function env(key: string, fallback: string): string {
  return process.env[key] ?? fallback;
}

function toHttpUrl(raw: string): string {
  if (raw.startsWith("ws://")) return `http://${raw.slice(5)}`;
  if (raw.startsWith("wss://")) return `https://${raw.slice(6)}`;
  return raw;
}

const livekitUrl = env("LIVEKIT_URL", "ws://127.0.0.1:7880");

export const serverConfig = {
  livekitUrl,
  livekitHttpUrl:   toHttpUrl(livekitUrl),
  livekitApiKey:    env("LIVEKIT_API_KEY", ""),
  livekitApiSecret: env("LIVEKIT_API_SECRET", ""),
  voiceaiRoot:      env("VOICEAI_ROOT", `${process.env.HOME ?? ""}/ai-projects/voiceai`),
  voiceaiAgentName: env("VOICEAI_AGENT_NAME", "voiceai-agent"),
} as const;
EOF

# ==============================================================================
# 23 · hooks/usePoll.ts
# ==============================================================================
cat > hooks/usePoll.ts << 'EOF'
"use client";

import { useState, useEffect, useCallback, useRef } from "react";

export interface PollState<T> {
  data:    T | null;
  error:   string | null;
  loading: boolean;
  refetch: () => void;
}

export function usePoll<T>(
  fetcher:  () => Promise<T>,
  interval: number,
): PollState<T> {
  const [data,    setData]    = useState<T | null>(null);
  const [error,   setError]   = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  // Keep a stable ref so the interval doesn't re-register when fetcher changes
  const fetcherRef = useRef(fetcher);
  fetcherRef.current = fetcher;

  const run = useCallback(async () => {
    try {
      const result = await fetcherRef.current();
      setData(result);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    run();
    const id = setInterval(run, interval);
    return () => clearInterval(id);
  }, [run, interval]);

  return { data, error, loading, refetch: run };
}
EOF

# ==============================================================================
# 24 · hooks/useLiveClock.ts
# ==============================================================================
cat > hooks/useLiveClock.ts << 'EOF'
"use client";

import { useState, useEffect } from "react";

function formatTime(date: Date): string {
  return date.toLocaleTimeString("en-US", {
    hour12:  false,
    hour:    "2-digit",
    minute:  "2-digit",
    second:  "2-digit",
  });
}

export function useLiveClock(): string {
  const [time, setTime] = useState(() => formatTime(new Date()));

  useEffect(() => {
    const id = setInterval(() => setTime(formatTime(new Date())), 1000);
    return () => clearInterval(id);
  }, []);

  return time;
}
EOF

# ==============================================================================
# 25 · hooks/useAgentState.ts
# ==============================================================================
cat > hooks/useAgentState.ts << 'EOF'
"use client";

import { usePoll } from "./usePoll";
import { POLL } from "@/lib/constants";
import type { AgentHealth } from "@/lib/types";

async function fetchAgentHealth(): Promise<AgentHealth> {
  const res = await fetch("/api/proxy/agent/health", { cache: "no-store" });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

export function useAgentState() {
  return usePoll<AgentHealth>(fetchAgentHealth, POLL.NORMAL);
}
EOF

# ==============================================================================
# 25.1 · hooks/useAgentTarget.ts
# Agent truth comes from backend /agent/health for the current room.
# ==============================================================================
cat > hooks/useAgentTarget.ts << 'EOF'
"use client";

import { useMemo } from "react";
import { useRoomContext } from "@livekit/components-react";
import { useAgentState } from "./useAgentState";

export function useAgentTarget() {
  const room = useRoomContext();
  const health = useAgentState();

  const target = useMemo(() => {
    const h = health.data;
    if (!room || !h) return { ready: false, identity: null as string | null };
    const sameRoom = !!h.session_active && !!h.room_name && h.room_name === room.name;
    const identity = sameRoom ? (h.participant_identity ?? null) : null;
    return { ready: sameRoom && !!identity, identity };
  }, [health.data, room]);

  return { ...target, health };
}
EOF

# ==============================================================================
# 26 · hooks/useTtsState.ts
# ==============================================================================
cat > hooks/useTtsState.ts << 'EOF'
"use client";

import { usePoll } from "./usePoll";
import { POLL } from "@/lib/constants";
import type { TtsHealth } from "@/lib/types";

async function fetchTtsHealth(): Promise<TtsHealth> {
  const res = await fetch("/api/proxy/tts/health", { cache: "no-store" });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

export function useTtsState() {
  return usePoll<TtsHealth>(fetchTtsHealth, POLL.FAST);
}
EOF

# ==============================================================================
# 27 · hooks/useMachineMetrics.ts
# ==============================================================================
cat > hooks/useMachineMetrics.ts << 'EOF'
"use client";

import { usePoll } from "./usePoll";
import { POLL } from "@/lib/constants";
import type { MachineMetrics } from "@/lib/types";

async function fetchMachineMetrics(): Promise<MachineMetrics> {
  const res = await fetch("/api/proxy/telemetry/metrics/machine", { cache: "no-store" });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

export function useMachineMetrics() {
  return usePoll<MachineMetrics>(fetchMachineMetrics, POLL.SLOW);
}
EOF

# ==============================================================================
# 28 · hooks/useLlmContext.ts
# ==============================================================================
cat > hooks/useLlmContext.ts << 'EOF'
"use client";

import { usePoll } from "./usePoll";
import { POLL } from "@/lib/constants";
import type { LlmContext } from "@/lib/types";

async function fetchLlmContext(): Promise<LlmContext> {
  const res = await fetch("/api/proxy/telemetry/inventory/context", { cache: "no-store" });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

export function useLlmContext() {
  return usePoll<LlmContext>(fetchLlmContext, POLL.SLOW);
}
EOF

# ==============================================================================
# 29 · hooks/useInventory.ts — personas + reference audio
# ==============================================================================
cat > hooks/useInventory.ts << 'EOF'
"use client";

import { usePoll } from "./usePoll";
import { POLL } from "@/lib/constants";
import type { PersonaItem, ReferenceAudio } from "@/lib/types";

interface PersonaInventory {
  personas: PersonaItem[];
  count:    number;
}

interface AudioInventory {
  voices: ReferenceAudio[];
  count:  number;
}

async function fetchPersonas(): Promise<PersonaInventory> {
  const res = await fetch("/api/proxy/telemetry/inventory/personas", { cache: "no-store" });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

async function fetchAudio(): Promise<AudioInventory> {
  const res = await fetch("/api/proxy/telemetry/inventory/reference-audio", { cache: "no-store" });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

export function usePersonaInventory() {
  return usePoll<PersonaInventory>(fetchPersonas, POLL.SLOW);
}

export function useAudioInventory() {
  return usePoll<AudioInventory>(fetchAudio, POLL.SLOW);
}
EOF

# ==============================================================================
# 31 · components/shared/GlassCard.tsx
# ==============================================================================
cat > components/shared/GlassCard.tsx << 'EOF'
"use client";

import { cn } from "@/lib/utils";
import type { ReactNode } from "react";

interface GlassCardProps {
  children:   ReactNode;
  className?: string;
}

export function GlassCard({ children, className }: GlassCardProps) {
  return (
    <div className={cn("rounded-xl border border-white/[0.07] bg-black/20 backdrop-blur-sm", className)}>
      {children}
    </div>
  );
}
EOF

# ==============================================================================
# 32 · components/shared/StatusDot.tsx
# ==============================================================================
cat > components/shared/StatusDot.tsx << 'EOF'
"use client";

import { cn } from "@/lib/utils";
import type { ServiceStatus } from "@/lib/types";

const DOT_CLASS: Record<ServiceStatus, string> = {
  online:   "bg-emerald-400 shadow-[0_0_6px_rgba(52,211,153,0.55)]",
  offline:  "bg-rose-400",
  degraded: "bg-amber-400",
  unknown:  "bg-slate-600",
};

const LABEL_CLASS: Record<ServiceStatus, string> = {
  online:   "text-emerald-400",
  offline:  "text-rose-400",
  degraded: "text-amber-400",
  unknown:  "text-slate-500",
};

interface StatusDotProps {
  status:     ServiceStatus;
  showLabel?: boolean;
  size?:      "sm" | "md";
}

export function StatusDot({ status, showLabel = false, size = "sm" }: StatusDotProps) {
  return (
    <span className="flex items-center gap-1.5">
      <span
        className={cn(
          "rounded-full shrink-0",
          size === "sm" ? "h-1.5 w-1.5" : "h-2 w-2",
          DOT_CLASS[status],
        )}
      />
      {showLabel && (
        <span className={cn("font-mono text-xs uppercase tracking-wider", LABEL_CLASS[status])}>
          {status}
        </span>
      )}
    </span>
  );
}
EOF

# ==============================================================================
# 33 · components/shared/Mono.tsx
# ==============================================================================
cat > components/shared/Mono.tsx << 'EOF'
"use client";

import { cn } from "@/lib/utils";
import type { ReactNode } from "react";

interface MonoProps {
  children:   ReactNode;
  className?: string;
  dim?:       boolean;
}

export function Mono({ children, className, dim = false }: MonoProps) {
  return (
    <span
      className={cn(
        "font-mono text-xs tracking-wide",
        dim ? "text-slate-600" : "text-slate-400",
        className,
      )}
    >
      {children}
    </span>
  );
}
EOF

# ==============================================================================
# 34 · components/shared/SectionHeader.tsx
# ==============================================================================
cat > components/shared/SectionHeader.tsx << 'EOF'
"use client";

import { cn } from "@/lib/utils";
import type { ReactNode } from "react";

interface SectionHeaderProps {
  icon?:      ReactNode;
  title:      string;
  subtitle?:  string;
  action?:    ReactNode;
  className?: string;
}

export function SectionHeader({ icon, title, subtitle, action, className }: SectionHeaderProps) {
  return (
    <div className={cn("flex items-center justify-between mb-3", className)}>
      <div className="flex items-center gap-2">
        {icon && <span className="text-cyan-400 shrink-0">{icon}</span>}
        <div>
          <h3 className="text-slate-200 font-semibold text-sm leading-none">{title}</h3>
          {subtitle && (
            <p className="text-slate-600 text-xs mt-0.5 font-mono">{subtitle}</p>
          )}
        </div>
      </div>
      {action && <div className="shrink-0">{action}</div>}
    </div>
  );
}
EOF

# ==============================================================================
# 35 · components/shared/InlineAlert.tsx
# ==============================================================================
cat > components/shared/InlineAlert.tsx << 'EOF'
"use client";

import { AlertCircle, CheckCircle2, Info } from "lucide-react";
import { cn } from "@/lib/utils";

type AlertKind = "error" | "success" | "info" | "warning";

const STYLES: Record<AlertKind, { bar: string; icon: string }> = {
  error:   { bar: "border-rose-400/30 bg-rose-400/10",     icon: "text-rose-400"    },
  success: { bar: "border-emerald-400/30 bg-emerald-400/10", icon: "text-emerald-400" },
  info:    { bar: "border-cyan-400/30 bg-cyan-400/10",     icon: "text-cyan-400"    },
  warning: { bar: "border-amber-400/30 bg-amber-400/10",   icon: "text-amber-400"   },
};

const ICONS: Record<AlertKind, typeof AlertCircle> = {
  error:   AlertCircle,
  success: CheckCircle2,
  info:    Info,
  warning: AlertCircle,
};

interface InlineAlertProps {
  kind:       AlertKind;
  message:    string;
  className?: string;
}

export function InlineAlert({ kind, message, className }: InlineAlertProps) {
  const { bar, icon } = STYLES[kind];
  const Icon           = ICONS[kind];

  return (
    <div className={cn("flex items-start gap-2 rounded-lg border px-3 py-2", bar, className)}>
      <Icon size={13} className={cn("shrink-0 mt-0.5", icon)} />
      <span className="font-mono text-xs text-slate-300 leading-relaxed break-all">{message}</span>
    </div>
  );
}
EOF

# ==============================================================================
# 36 · components/shared/ProgressBar.tsx
# Width set via CSS custom property --mw (style prop) to avoid inline
# presentation style values on the element directly.
# ==============================================================================
cat > components/shared/ProgressBar.tsx << 'EOF'
"use client";

import { cn } from "@/lib/utils";

interface ProgressBarProps {
  value:        number;
  accentClass?: string;
}

export function ProgressBar({ value, accentClass = "bg-cyan-400" }: ProgressBarProps) {
  const clamped = Math.min(100, Math.max(0, value));
  return (
    <div className="h-1 rounded-full bg-white/[0.06] overflow-hidden">
      <div
        className={cn("meter-fill h-full rounded-full transition-all duration-700", accentClass)}
        style={{ "--mw": `${clamped}%` } as React.CSSProperties}
      />
    </div>
  );
}
EOF

# ==============================================================================
# 37 · components/layout/NavBar.tsx — 6 tabs including Personas
# ==============================================================================
cat > components/layout/NavBar.tsx << 'EOF'
"use client";

import { LayoutDashboard, Radio, Users, Layers, Database, Globe } from "lucide-react";
import { cn } from "@/lib/utils";
import type { LucideIcon } from "lucide-react";

export type NavTab = "overview" | "session" | "personas" | "services" | "memory" | "tools";

interface TabDef {
  id:    NavTab;
  label: string;
  Icon:  LucideIcon;
}

const TABS: TabDef[] = [
  { id: "overview",  label: "Overview",  Icon: LayoutDashboard },
  { id: "session",   label: "Session",   Icon: Radio           },
  { id: "personas",  label: "Personas",  Icon: Users           },
  { id: "services",  label: "Services",  Icon: Layers          },
  { id: "memory",    label: "Memory",    Icon: Database        },
  { id: "tools",     label: "Tools",     Icon: Globe           },
];

interface NavProps {
  active:   NavTab;
  onChange: (tab: NavTab) => void;
}

export function NavBar({ active, onChange }: NavProps) {
  return (
    <nav className="flex items-center gap-1 px-2">
      {TABS.map(({ id, label, Icon }) => (
        <button
          key={id}
          onClick={() => onChange(id)}
          className={cn(
            "flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-all",
            active === id
              ? "bg-cyan-400/10 text-cyan-400 border border-cyan-400/20"
              : "text-slate-500 hover:text-slate-300 hover:bg-white/[0.04]",
          )}
        >
          <Icon size={13} />
          <span className="hidden sm:inline">{label}</span>
        </button>
      ))}
    </nav>
  );
}

export function BottomNav({ active, onChange }: NavProps) {
  return (
    <nav className="flex items-stretch border-t border-white/[0.07] bg-black/60 backdrop-blur-md">
      {TABS.map(({ id, label, Icon }) => (
        <button
          key={id}
          onClick={() => onChange(id)}
          className={cn(
            "flex flex-1 flex-col items-center gap-0.5 py-1.5 text-[9px] font-medium transition-colors",
            active === id ? "text-cyan-400" : "text-slate-600",
          )}
        >
          <Icon size={16} />
          {label}
        </button>
      ))}
    </nav>
  );
}
EOF

# ==============================================================================
# 38 · components/layout/AppShell.tsx — top-level shell; wires all six tabs
# ==============================================================================
cat > components/layout/AppShell.tsx << 'EOF'
"use client";

import { useState } from "react";
import { Cpu, Clock } from "lucide-react";
import { NavBar, BottomNav, type NavTab } from "./NavBar";
import { OverviewTab }  from "@/components/overview/OverviewTab";
import { SessionTab }   from "@/components/session/SessionTab";
import { PersonasTab }  from "@/components/personas/PersonasTab";
import { ServicesTab }  from "@/components/services/ServicesTab";
import { MemoryTab }    from "@/components/memory/MemoryPanel";
import { ToolsTab }     from "@/components/tools/WebFetchPanel";
import { Mono }         from "@/components/shared/Mono";
import { useLiveClock } from "@/hooks/useLiveClock";

export function AppShell() {
  const [tab, setTab] = useState<NavTab>("overview");
  const clock         = useLiveClock();

  return (
    <div className="flex h-full flex-col bg-[#080B0F]">
      <header className="flex shrink-0 items-center justify-between border-b border-white/[0.07] bg-black/30 backdrop-blur-md px-4 py-2.5">
        <div className="flex items-center gap-2">
          <Cpu size={16} className="text-cyan-400" />
          <span className="text-sm font-semibold text-slate-200 tracking-tight">VoiceAI</span>
          <Mono dim>Command Center</Mono>
        </div>

        <div className="hidden md:flex">
          <NavBar active={tab} onChange={setTab} />
        </div>

        <div className="hidden sm:flex items-center gap-1.5">
          <Clock size={12} className="text-slate-700" />
          <Mono dim>{clock}</Mono>
        </div>
      </header>

      <main className="flex-1 overflow-hidden">
        {tab === "overview"  && <OverviewTab />}
        {tab === "session"   && <SessionTab  />}
        {tab === "personas"  && <PersonasTab />}
        {tab === "services"  && <ServicesTab />}
        {tab === "memory"    && <MemoryTab   />}
        {tab === "tools"     && <ToolsTab    />}
      </main>

      <div className="flex md:hidden shrink-0">
        <BottomNav active={tab} onChange={setTab} />
      </div>
    </div>
  );
}
EOF

# ==============================================================================
# ==============================================================================
# 39 · components/overview/ServiceHealthRow.tsx
# Uses telemetry /metrics/services as the single source of truth.
# ==============================================================================
cat > components/overview/ServiceHealthRow.tsx << 'EOF'
"use client";

import { usePoll } from "@/hooks/usePoll";
import { StatusDot } from "@/components/shared/StatusDot";
import { Mono } from "@/components/shared/Mono";
import { POLL } from "@/lib/constants";
import type { ServiceStatus } from "@/lib/types";

interface ServiceRowDef {
  key: string;
  label: string;
  port: number;
}

const SERVICES: ServiceRowDef[] = [
  { key: "livekit",   label: "LiveKit",   port: 7880 },
  { key: "llm",       label: "LLM",       port: 5000 },
  { key: "stt",       label: "STT",       port: 5100 },
  { key: "tts_router",label: "TTS",       port: 5200 },
  { key: "qdrant",    label: "Qdrant",    port: 6333 },
  { key: "telemetry", label: "Telemetry", port: 5900 },
  { key: "agent",     label: "Agent",     port: 5800 },
];

interface TelemetryServiceEntry {
  online?: boolean;
  latency_ms?: number;
}

interface ServicesPayload {
  stale?: boolean;
  services?: Record<string, TelemetryServiceEntry>;
}

async function fetchServices(): Promise<ServicesPayload> {
  const res = await fetch("/api/proxy/telemetry/metrics/services", {
    cache: "no-store",
    signal: AbortSignal.timeout(3_000),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

function mapStatus(entry?: TelemetryServiceEntry, stale?: boolean): ServiceStatus {
  if (!entry) return "unknown";
  if (stale) return entry.online ? "degraded" : "offline";
  return entry.online ? "online" : "offline";
}

function ServiceChip({ svc, payload }: { svc: ServiceRowDef; payload: ServicesPayload | null }) {
  const entry = payload?.services?.[svc.key];
  const status = mapStatus(entry, payload?.stale);

  return (
    <div className="flex items-center justify-between rounded-lg border border-white/[0.05] bg-black/15 px-3 py-2.5">
      <div className="flex items-center gap-2">
        <StatusDot status={status} />
        <span className="text-xs font-medium text-slate-300">{svc.label}</span>
      </div>
      <div className="flex items-center gap-2">
        {entry?.latency_ms != null && <Mono dim>{Math.round(entry.latency_ms)}ms</Mono>}
        <Mono dim>{svc.port}</Mono>
      </div>
    </div>
  );
}

export function ServiceGrid() {
  const { data } = usePoll<ServicesPayload>(fetchServices, POLL.NORMAL);

  return (
    <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-1 xl:grid-cols-2">
      {SERVICES.map((svc) => (
        <ServiceChip key={svc.key} svc={svc} payload={data} />
      ))}
    </div>
  );
}
EOF

# ==============================================================================
# 40 · components/overview/MachineCard.tsx
# Single Meter helper uses ProgressBar (CSS-var width, no inline style value).
# ==============================================================================
cat > components/overview/MachineCard.tsx << 'EOF'
"use client";

import { useMachineMetrics } from "@/hooks/useMachineMetrics";
import { GlassCard }     from "@/components/shared/GlassCard";
import { SectionHeader } from "@/components/shared/SectionHeader";
import { ProgressBar }   from "@/components/shared/ProgressBar";
import { Mono }          from "@/components/shared/Mono";
import { Cpu }           from "lucide-react";
import { cn }            from "@/lib/utils";

interface MeterProps {
  label:        string;
  value:        number;
  accentClass?: string;
}

function Meter({ label, value, accentClass = "bg-cyan-400" }: MeterProps) {
  const clamped = Math.min(100, Math.max(0, value));
  const hot     = clamped > 85;

  return (
    <div className="space-y-1">
      <div className="flex items-center justify-between">
        <Mono dim>{label}</Mono>
        <Mono className={hot ? "text-amber-400" : "text-slate-400"}>{clamped.toFixed(0)}%</Mono>
      </div>
      <ProgressBar value={clamped} accentClass={hot ? "bg-amber-400" : accentClass} />
    </div>
  );
}

export function MachineCard() {
  const { data, error, loading } = useMachineMetrics();

  return (
    <GlassCard className="p-4">
      <SectionHeader icon={<Cpu size={14} />} title="Machine" subtitle="10s refresh" />

      {loading && <p className="text-xs text-slate-600 font-mono">Loading…</p>}
      {error   && <p className="text-xs text-rose-400 font-mono">{error}</p>}

      {data && (
        <div className="space-y-3 mt-2">
          <Meter label="CPU" value={data.cpu_percent} />
          <Meter label="RAM" value={data.ram_percent} accentClass="bg-violet-400" />

          {data.gpu && (
            <>
              <Meter label="GPU util" value={data.gpu.util_percent} accentClass="bg-amber-400" />
              <Meter
                label="VRAM"
                accentClass="bg-rose-400"
                value={Math.round(
                  ((data.gpu.vram_total_gb - data.gpu.vram_free_gb) / data.gpu.vram_total_gb) * 100,
                )}
              />
              <div className="flex items-center justify-between pt-0.5">
                <Mono dim>VRAM used</Mono>
                <Mono>
                  {(data.gpu.vram_total_gb - data.gpu.vram_free_gb).toFixed(1)}
                  &nbsp;/&nbsp;
                  {data.gpu.vram_total_gb.toFixed(1)} GB
                </Mono>
              </div>
              <div className="flex items-center justify-between">
                <Mono dim>GPU temp</Mono>
                <Mono className={data.gpu.temp_c > 80 ? "text-rose-400" : "text-slate-400"}>
                  {data.gpu.temp_c}°C
                </Mono>
              </div>
            </>
          )}
        </div>
      )}
    </GlassCard>
  );
}
EOF

# ==============================================================================
# 41 · components/overview/OverviewTab.tsx
# ==============================================================================
cat > components/overview/OverviewTab.tsx << 'EOF'
"use client";

import { ServiceGrid } from "./ServiceHealthRow";
import { MachineCard } from "./MachineCard";
import { GlassCard }     from "@/components/shared/GlassCard";
import { SectionHeader } from "@/components/shared/SectionHeader";
import { Server }        from "lucide-react";

export function OverviewTab() {
  return (
    <div className="h-full overflow-y-auto p-4">
      <div className="mx-auto max-w-5xl">
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <div className="lg:col-span-2">
            <GlassCard className="p-4">
              <SectionHeader icon={<Server size={14} />} title="Services" subtitle="5s refresh" />
              <ServiceGrid />
            </GlassCard>
          </div>
          <MachineCard />
        </div>
      </div>
    </div>
  );
}
EOF

# ==============================================================================
# 42 · components/services/LlmCard.tsx
# ==============================================================================
cat > components/services/LlmCard.tsx << 'EOF'
"use client";

import { useLlmContext } from "@/hooks/useLlmContext";
import { GlassCard }     from "@/components/shared/GlassCard";
import { SectionHeader } from "@/components/shared/SectionHeader";
import { StatusDot }     from "@/components/shared/StatusDot";
import { Mono }          from "@/components/shared/Mono";
import { Brain }         from "lucide-react";

export function LlmCard() {
  const { data, error, loading } = useLlmContext();

  return (
    <GlassCard className="p-4 space-y-3">
      <SectionHeader icon={<Brain size={14} />} title="LLM" subtitle="127.0.0.1:5000 · TabbyAPI" />

      {loading && <p className="text-xs text-slate-600 font-mono">Querying…</p>}
      {error   && <p className="text-xs text-rose-400 font-mono">{error}</p>}

      {data && (
        <>
          <StatusDot status={data.online ? "online" : "offline"} showLabel />

          {data.online && (
            <div className="rounded-lg border border-white/[0.05] bg-black/20 px-3 py-2 space-y-1.5">
              {data.model && (
                <div className="flex justify-between gap-3">
                  <Mono dim>Model</Mono>
                  <Mono className="text-slate-300 text-right break-all">{data.model}</Mono>
                </div>
              )}
              {data.max_seq_len != null && (
                <div className="flex justify-between">
                  <Mono dim>Context ceiling</Mono>
                  <Mono className="text-slate-300">{data.max_seq_len.toLocaleString()} tokens</Mono>
                </div>
              )}
            </div>
          )}

          {!data.online && (
            <p className="text-xs text-slate-600 font-mono">
              {data.error ?? "LLM not responding on port 5000"}
            </p>
          )}
        </>
      )}
    </GlassCard>
  );
}
EOF

# ==============================================================================
# 43 · components/services/SttCard.tsx
# Global model switch is visually isolated in an amber admin section,
# separate from session-level controls (which live in the Session tab).
# ==============================================================================
cat > components/services/SttCard.tsx << 'EOF'
"use client";

import { useState } from "react";
import { usePoll }         from "@/hooks/usePoll";
import { GlassCard }     from "@/components/shared/GlassCard";
import { SectionHeader } from "@/components/shared/SectionHeader";
import { StatusDot }     from "@/components/shared/StatusDot";
import { Mono }          from "@/components/shared/Mono";
import { InlineAlert }   from "@/components/shared/InlineAlert";
import { Mic, RefreshCw } from "lucide-react";
import { STT_CANONICAL_MODELS } from "@/lib/types";
import type { SwitchResult } from "@/lib/types";
import { POLL } from "@/lib/constants";
import { cn } from "@/lib/utils";

interface SttHealth {
  model?: string;
}

async function fetchSttHealth(): Promise<SttHealth> {
  const res = await fetch("/api/proxy/stt/health", { cache: "no-store" });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

export function SttCard() {
  const health    = usePoll<SttHealth>(fetchSttHealth, POLL.NORMAL);

  const [selected,  setSelected]  = useState("");
  const [switching, setSwitching] = useState(false);
  const [result,    setResult]    = useState<SwitchResult | null>(null);

  async function applySwitch() {
    if (!selected || switching) return;
    setSwitching(true);
    setResult(null);
    try {
      const res = await fetch("/api/stt/switch", {
        method:  "POST",
        headers: { "Content-Type": "application/json" },
        body:    JSON.stringify({ model: selected }),
      });
      const data = await res.json() as SwitchResult;
      setResult(data);
      if (data.ok) {
        health.refetch();
        setSelected("");
      }
    } catch (err) {
      setResult({ ok: false, message: err instanceof Error ? err.message : String(err) });
    } finally {
      setSwitching(false);
    }
  }

  return (
    <GlassCard className="p-4 space-y-3">
      <SectionHeader icon={<Mic size={14} />} title="STT" subtitle="127.0.0.1:5100 · Faster-Whisper" />

      {health.loading && <p className="text-xs text-slate-600 font-mono">Checking…</p>}
      {health.error   && <p className="text-xs text-rose-400 font-mono">{health.error}</p>}
      {!health.loading && (
        <StatusDot status={health.error ? "offline" : "online"} showLabel />
      )}

      <div className="rounded-lg border border-white/[0.05] bg-black/20 px-3 py-2 space-y-1.5">
        <div className="flex justify-between">
          <Mono dim>Active model</Mono>
          <Mono className="text-slate-300">{health.data?.model ?? "—"}</Mono>
        </div>
      </div>

      {/* Global model switch — admin-only, isolated in amber section */}
      <div className="rounded-lg border border-amber-400/15 bg-amber-400/[0.03] p-3 space-y-2">
        <Mono className="text-amber-400/80">⚙ Global STT model switch</Mono>
        <p className="text-xs text-slate-700 font-mono leading-relaxed">
          Writes config.yml atomically. watchfiles hot-reloads in &lt;1s. Affects all sessions.
        </p>
        <select
          value={selected}
          onChange={(e) => setSelected(e.target.value)}
          className="w-full rounded-md border border-white/[0.07] bg-black/30 px-2 py-1.5 text-xs text-slate-300 font-mono outline-none focus:border-cyan-400/40"
        >
          <option value="">— select model —</option>
          {STT_CANONICAL_MODELS.map((m) => (
            <option key={m} value={m}>{m}</option>
          ))}
        </select>
        <button
          onClick={applySwitch}
          disabled={!selected || switching}
          className={cn(
            "flex items-center gap-1.5 rounded-md border px-3 py-1.5 text-xs font-medium w-full justify-center transition-colors",
            selected && !switching
              ? "border-cyan-400/30 bg-cyan-400/10 text-cyan-400 hover:bg-cyan-400/15"
              : "border-white/[0.05] text-slate-600 cursor-not-allowed",
          )}
        >
          <RefreshCw size={12} className={switching ? "animate-spin" : ""} />
          {switching ? "Switching…" : "Apply Model"}
        </button>
        {result && <InlineAlert kind={result.ok ? "success" : "error"} message={result.message} />}
      </div>
    </GlassCard>
  );
}
EOF

# ==============================================================================
# 44 · components/services/TtsCard.tsx
# Global engine switch — visually isolated from session voice controls.
# ==============================================================================
cat > components/services/TtsCard.tsx << 'EOF'
"use client";

import { useState } from "react";
import { useTtsState } from "@/hooks/useTtsState";
import { GlassCard }     from "@/components/shared/GlassCard";
import { SectionHeader } from "@/components/shared/SectionHeader";
import { Mono }          from "@/components/shared/Mono";
import { InlineAlert }   from "@/components/shared/InlineAlert";
import { Volume2, ArrowRight } from "lucide-react";
import { TTS_MODES, TTS_MODE_LABELS } from "@/lib/types";
import type { TtsMode, SwitchResult } from "@/lib/types";
import { cn, formatVram } from "@/lib/utils";

const PHASE_COLOR: Record<string, string> = {
  idle:          "text-emerald-400",
  draining:      "text-amber-400",
  terminating:   "text-amber-400",
  vram_settling: "text-violet-400",
  spawning:      "text-violet-400",
  probing:       "text-cyan-400",
  error:         "text-rose-400",
};

export function TtsCard() {
  const { data, error, loading, refetch } = useTtsState();

  const [selected, setSelected] = useState<TtsMode | "">("");
  const [busy,     setBusy]     = useState(false);
  const [result,   setResult]   = useState<SwitchResult | null>(null);

  async function doSwitch() {
    if (!selected || busy) return;

    if (data?.active_mode === selected && !data?.switching) {
      setResult({ ok: false, message: `'${TTS_MODE_LABELS[selected]}' is already active.` });
      return;
    }

    setBusy(true);
    setResult(null);
    try {
      const res = await fetch("/api/tts/switch", {
        method:  "POST",
        headers: { "Content-Type": "application/json" },
        body:    JSON.stringify({ mode: selected }),
      });
      const data = await res.json() as SwitchResult;
      setResult(data);
      if (res.ok) refetch();
    } catch (err) {
      setResult({ ok: false, message: err instanceof Error ? err.message : String(err) });
    } finally {
      setBusy(false);
    }
  }

  return (
    <GlassCard className="p-4 space-y-3">
      <SectionHeader icon={<Volume2 size={14} />} title="TTS Router" subtitle="127.0.0.1:5200" />

      {loading && <p className="text-xs text-slate-600 font-mono">Checking…</p>}
      {error   && <p className="text-xs text-rose-400 font-mono">{error}</p>}

      {data && (
        <>
          <div className="rounded-lg border border-white/[0.05] bg-black/20 px-3 py-2 space-y-1.5">
            <div className="flex justify-between">
              <Mono dim>Engine</Mono>
              <Mono className="text-slate-300">
                {data.active_mode ? TTS_MODE_LABELS[data.active_mode] : "none"}
              </Mono>
            </div>
            <div className="flex justify-between">
              <Mono dim>Phase</Mono>
              <Mono className={PHASE_COLOR[data.router_phase] ?? "text-slate-400"}>
                {data.router_phase}
              </Mono>
            </div>
            <div className="flex justify-between">
              <Mono dim>Worker</Mono>
              <Mono className={data.worker_ready ? "text-emerald-400" : "text-slate-500"}>
                {data.worker_ready ? "ready" : "not ready"}
              </Mono>
            </div>
            {data.switching && (
              <div className="flex justify-between">
                <Mono dim>Switching</Mono>
                <Mono className="text-violet-400 animate-pulse">in progress…</Mono>
              </div>
            )}
            {data.worker?.vram_total_gb != null && (
              <div className="flex justify-between">
                <Mono dim>VRAM</Mono>
                <Mono className="text-slate-300">
                  {formatVram(data.worker.vram_total_gb, data.worker.vram_free_gb)}
                </Mono>
              </div>
            )}
            {data.last_error && (
              <div className="flex justify-between gap-2">
                <Mono dim>Last error</Mono>
                <Mono className="text-rose-400 truncate max-w-[180px]">{data.last_error}</Mono>
              </div>
            )}
          </div>

          {!data.active_mode && !data.switching && (
            <InlineAlert kind="info" message="No engine loaded. Select one below to load it." />
          )}

          {/* Global engine switch — admin-only, isolated in amber section */}
          <div className="rounded-lg border border-amber-400/15 bg-amber-400/[0.03] p-3 space-y-2">
            <Mono className="text-amber-400/80">⚙ Global TTS engine switch</Mono>
            <p className="text-xs text-slate-700 font-mono leading-relaxed">
              Drains VRAM from current engine, spawns the new one. Affects all sessions.
            </p>
            <div className="grid grid-cols-3 gap-1.5">
              {TTS_MODES.map((mode) => (
                <button
                  key={mode}
                  onClick={() => setSelected(mode)}
                  className={cn(
                    "rounded-md border px-2 py-1.5 text-xs font-mono transition-colors",
                    selected === mode
                      ? "border-cyan-400/40 bg-cyan-400/10 text-cyan-400"
                      : "border-white/[0.06] bg-black/20 text-slate-500 hover:text-slate-300",
                  )}
                >
                  {TTS_MODE_LABELS[mode]}
                </button>
              ))}
            </div>
            <button
              onClick={doSwitch}
              disabled={!selected || busy}
              className={cn(
                "flex items-center gap-1.5 justify-center w-full rounded-md border px-3 py-1.5 text-xs font-medium transition-colors",
                selected && !busy
                  ? "border-cyan-400/30 bg-cyan-400/10 text-cyan-400 hover:bg-cyan-400/15"
                  : "border-white/[0.05] text-slate-600 cursor-not-allowed",
              )}
            >
              <ArrowRight size={12} className={busy ? "animate-pulse" : ""} />
              {busy ? "Switching…" : "Switch Engine"}
            </button>
            {result && <InlineAlert kind={result.ok ? "success" : "error"} message={result.message} />}
          </div>
        </>
      )}
    </GlassCard>
  );
}
EOF

# ==============================================================================
# 45 · components/services/AgentCard.tsx
# ==============================================================================
cat > components/services/AgentCard.tsx << 'EOF'
"use client";

import { useAgentState } from "@/hooks/useAgentState";
import { GlassCard }     from "@/components/shared/GlassCard";
import { SectionHeader } from "@/components/shared/SectionHeader";
import { StatusDot }     from "@/components/shared/StatusDot";
import { Mono }          from "@/components/shared/Mono";
import { Radio }         from "lucide-react";
import { formatUptime }  from "@/lib/utils";

interface InfoRowProps {
  label:     string;
  value:     string;
  valueClass?: string;
}

function InfoRow({ label, value, valueClass = "text-slate-300" }: InfoRowProps) {
  return (
    <div className="flex justify-between gap-2">
      <Mono dim>{label}</Mono>
      <Mono className={valueClass}>{value}</Mono>
    </div>
  );
}

export function AgentCard() {
  const { data, error, loading } = useAgentState();

  return (
    <GlassCard className="p-4 space-y-3">
      <SectionHeader icon={<Radio size={14} />} title="Agent" subtitle="127.0.0.1:5800" />

      {loading && <p className="text-xs text-slate-600 font-mono">Checking…</p>}
      {error   && <p className="text-xs text-rose-400 font-mono">{error}</p>}

      {data && (
        <>
          <div className="flex items-center gap-3">
            <StatusDot status={data.status === "ok" ? "online" : "degraded"} showLabel />
            {data.uptime_s > 0 && <Mono dim>up {formatUptime(data.uptime_s)}</Mono>}
          </div>

          <div className="rounded-lg border border-white/[0.05] bg-black/20 px-3 py-2 space-y-1.5">
            <InfoRow
              label="Session"
              value={data.session_active ? `active · room:${data.room_name ?? "?"}` : "inactive"}
              valueClass={data.session_active ? "text-emerald-400" : "text-slate-500"}
            />
            <InfoRow label="Persona"  value={data.persona}        />
            <InfoRow label="TTS mode" value={data.voice_mode}     />
            <InfoRow label="Voice"    value={data.voice_speaker}  />
            <InfoRow label="Language" value={data.voice_language} />
            <InfoRow
              label="Memory"
              value={data.memory_enabled ? "enabled" : "disabled"}
              valueClass={data.memory_enabled ? "text-emerald-400" : "text-slate-500"}
            />
            {data.session_tokens != null && (
              <InfoRow label="Session tokens" value={data.session_tokens.toLocaleString()} />
            )}
          </div>

          {data.last_error && (
            <p className="text-xs text-rose-400 font-mono break-all">{data.last_error}</p>
          )}
        </>
      )}
    </GlassCard>
  );
}
EOF

# ==============================================================================
# 46 · components/services/ServicesTab.tsx
# ==============================================================================
cat > components/services/ServicesTab.tsx << 'EOF'
"use client";

import { LlmCard }   from "./LlmCard";
import { SttCard }   from "./SttCard";
import { TtsCard }   from "./TtsCard";
import { AgentCard } from "./AgentCard";

export function ServicesTab() {
  return (
    <div className="h-full overflow-y-auto p-4">
      <div className="mx-auto max-w-5xl grid grid-cols-1 gap-4 md:grid-cols-2">
        <LlmCard />
        <SttCard />
        <TtsCard />
        <AgentCard />
      </div>
    </div>
  );
}
EOF

# ==============================================================================
# 47 · components/session/MicButton.tsx
# Connects listen-only (audio={false} on LiveKitRoom).
# This button calls setMicrophoneEnabled after connect — explicit user action.
# ==============================================================================
cat > components/session/MicButton.tsx << 'EOF'
"use client";

import { useEffect, useMemo, useState } from "react";
import { useLocalParticipant, useRoomContext } from "@livekit/components-react";
import { Mic, MicOff, RefreshCw } from "lucide-react";
import { cn } from "@/lib/utils";

interface AudioInput {
  deviceId: string;
  label: string;
}

export function MicButton() {
  const room = useRoomContext();
  const { localParticipant } = useLocalParticipant();

  const [enabled, setEnabled] = useState(false);
  const [busy, setBusy] = useState(false);
  const [devices, setDevices] = useState<AudioInput[]>([]);
  const [selectedDeviceId, setSelectedDeviceId] = useState("");

  async function refreshDevices() {
    if (typeof navigator === "undefined" || !navigator.mediaDevices) return;

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      stream.getTracks().forEach((t) => t.stop());
    } catch {
      // Permission may already be denied; still try enumerateDevices.
    }

    const all = await navigator.mediaDevices.enumerateDevices();
    const inputs = all
      .filter((d) => d.kind === "audioinput")
      .map((d, idx) => ({
        deviceId: d.deviceId,
        label: d.label || `Microphone ${idx + 1}`,
      }));

    setDevices(inputs);
    setSelectedDeviceId((prev) => prev || inputs[0]?.deviceId || "");
  }

  useEffect(() => {
    refreshDevices().catch(console.error);

    if (typeof navigator === "undefined" || !navigator.mediaDevices) return;
    const md = navigator.mediaDevices;

    if (!md?.addEventListener) return;
    const onChange = () => { refreshDevices().catch(console.error); };
    md.addEventListener("devicechange", onChange);
    return () => md.removeEventListener("devicechange", onChange);
  }, []);

  const deviceLabel = useMemo(
    () => devices.find((d) => d.deviceId === selectedDeviceId)?.label ?? "Default microphone",
    [devices, selectedDeviceId],
  );

  async function enableWithSelectedDevice() {
    const captureOptions = selectedDeviceId
      ? ({ deviceId: { exact: selectedDeviceId } } as any)
      : undefined;

    if (selectedDeviceId) {
      try {
        await room.switchActiveDevice("audioinput", selectedDeviceId);
      } catch {
        // Ignore and let setMicrophoneEnabled try directly.
      }
    }

    await localParticipant.setMicrophoneEnabled(true, captureOptions);
  }

  async function toggle() {
    if (!localParticipant || busy) return;
    setBusy(true);
    try {
      if (enabled) {
        await localParticipant.setMicrophoneEnabled(false);
        setEnabled(false);
      } else {
        await enableWithSelectedDevice();
        setEnabled(true);
      }
    } catch (err) {
      console.error("[MicButton]", err);
    } finally {
      setBusy(false);
    }
  }

  async function onSelectDevice(deviceId: string) {
    setSelectedDeviceId(deviceId);
    if (!enabled || !localParticipant) return;

    setBusy(true);
    try {
      try {
        await room.switchActiveDevice("audioinput", deviceId);
      } catch {
        await localParticipant.setMicrophoneEnabled(false);
        await localParticipant.setMicrophoneEnabled(true, { deviceId: { exact: deviceId } } as any);
      }
    } catch (err) {
      console.error("[MicButton][device-switch]", err);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-2">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
        <select
          value={selectedDeviceId}
          onChange={(e) => void onSelectDevice(e.target.value)}
          className="min-w-0 flex-1 rounded-lg border border-white/[0.07] bg-black/20 px-3 py-2 text-xs text-slate-300 outline-none focus:border-cyan-400/40"
        >
          {devices.length === 0 ? (
            <option value="">No microphone detected</option>
          ) : (
            devices.map((d) => (
              <option key={d.deviceId} value={d.deviceId}>{d.label}</option>
            ))
          )}
        </select>

        <button
          type="button"
          onClick={() => void refreshDevices()}
          className="inline-flex items-center justify-center rounded-lg border border-white/[0.07] px-3 py-2 text-slate-500 hover:text-cyan-400 hover:border-cyan-400/30 transition-colors"
          title="Refresh microphone list"
        >
          <RefreshCw size={14} />
        </button>
      </div>

      <div className="flex items-center justify-between gap-3">
        <p className="min-w-0 text-xs text-slate-600 font-mono truncate">{deviceLabel}</p>

        <button
          onClick={() => void toggle()}
          disabled={!localParticipant || busy || devices.length === 0}
          className={cn(
            "flex items-center gap-2 rounded-full px-5 py-2.5 text-sm font-semibold transition-all border shrink-0",
            enabled
              ? "bg-rose-400/15 border-rose-400/40 text-rose-400 hover:bg-rose-400/20"
              : "bg-cyan-400/10 border-cyan-400/30 text-cyan-400 hover:bg-cyan-400/15",
          )}
        >
          {enabled ? <MicOff size={16} /> : <Mic size={16} />}
          {busy ? "…" : enabled ? "Mute Mic" : "Start Mic"}
        </button>
      </div>
    </div>
  );
}
EOF

# ==============================================================================
# 48 · components/session/ContextPressureCard.tsx
# Real signals only: max_seq_len from LLM inventory + session_tokens from agent.
# No fake metrics.
# ==============================================================================
cat > components/session/ContextPressureCard.tsx << 'EOF'
"use client";

import { useLlmContext } from "@/hooks/useLlmContext";
import { useAgentState } from "@/hooks/useAgentState";
import { GlassCard }     from "@/components/shared/GlassCard";
import { SectionHeader } from "@/components/shared/SectionHeader";
import { ProgressBar }   from "@/components/shared/ProgressBar";
import { InlineAlert }   from "@/components/shared/InlineAlert";
import { Mono }          from "@/components/shared/Mono";
import { Activity }      from "lucide-react";
import { cn }            from "@/lib/utils";

export function ContextPressureCard() {
  const { data: ctx   } = useLlmContext();
  const { data: agent } = useAgentState();

  const maxTokens  = ctx?.max_seq_len      ?? null;
  const usedTokens = agent?.session_tokens ?? null;

  const fillPct =
    maxTokens != null && usedTokens != null
      ? Math.min(100, Math.round((usedTokens / maxTokens) * 100))
      : null;

  const isDanger  = fillPct != null && fillPct >= 85;
  const isWarning = fillPct != null && fillPct >= 70 && !isDanger;

  return (
    <GlassCard className="p-4 space-y-2">
      <SectionHeader icon={<Activity size={14} />} title="Context Pressure" subtitle="LLM token window" />

      {maxTokens != null ? (
        <>
          <div className="flex items-center justify-between">
            <Mono dim>Token fill</Mono>
            <Mono className={cn(isDanger ? "text-rose-400" : isWarning ? "text-amber-400" : "text-slate-400")}>
              {usedTokens?.toLocaleString() ?? "—"}&nbsp;/&nbsp;{maxTokens.toLocaleString()}
              {fillPct != null && ` · ${fillPct}%`}
            </Mono>
          </div>

          {fillPct != null && (
            <ProgressBar
              value={fillPct}
              accentClass={isDanger ? "bg-rose-400" : isWarning ? "bg-amber-400" : "bg-cyan-400"}
            />
          )}

          {isDanger  && <InlineAlert kind="error"   message="Context nearly full — save a Session Snapshot or Restore Context." />}
          {isWarning && <InlineAlert kind="warning"  message="Context pressure elevated. Consider saving a snapshot soon." />}
          {!isDanger && !isWarning && fillPct != null && fillPct > 0 && (
            <p className="text-xs text-slate-600 font-mono">Context pressure nominal.</p>
          )}
          {fillPct === 0 && (
            <p className="text-xs text-slate-600 font-mono">No tokens used in this session yet.</p>
          )}
        </>
      ) : (
        <p className="text-xs text-slate-600 font-mono">
          {ctx?.online === false
            ? "LLM offline — context ceiling unavailable."
            : "Awaiting LLM context data…"}
        </p>
      )}
    </GlassCard>
  );
}
EOF

# ==============================================================================
# 49 · components/session/ChatPanel.tsx
# Text send/receive via LiveKit DataChannel.
# Agent replies appear only if the backend relays them — none are fabricated.
# Manual review score is operator-entered only; it is NOT backend confidence.
# ==============================================================================
cat > components/session/ChatPanel.tsx << 'EOF'
"use client";

import { useState, useRef, useEffect } from "react";
import { useRoomContext } from "@livekit/components-react";
import { RoomEvent } from "livekit-client";
import { useAgentTarget } from "@/hooks/useAgentTarget";
import { GlassCard }     from "@/components/shared/GlassCard";
import { SectionHeader } from "@/components/shared/SectionHeader";
import { Mono }          from "@/components/shared/Mono";
import { MessageSquare, Send, Tag } from "lucide-react";
import { cn } from "@/lib/utils";

interface ChatMessage {
  id:           string;
  role:         "operator" | "agent";
  text:         string;
  ts:           Date;
  manualScore?: number; // operator-entered ONLY — not backend confidence
}

export function ChatPanel() {
  const room = useRoomContext();
  const { ready: agentReady } = useAgentTarget();

  const [messages,  setMessages]  = useState<ChatMessage[]>([]);
  const [input,     setInput]     = useState("");
  const [scoringId, setScoringId] = useState<string | null>(null);
  const [scoreVal,  setScoreVal]  = useState("");

  const bottomRef = useRef<HTMLDivElement>(null);

  // Listen for chat packets sent back by the agent via DataChannel
  useEffect(() => {
    if (!room) return;
    const handler = (payload: Uint8Array, participant?: { identity: string }) => {
      if (!participant) return;
      try {
        const parsed = JSON.parse(new TextDecoder().decode(payload));
        if (parsed.type === "chat" && typeof parsed.text === "string") {
          setMessages((prev) => [
            ...prev,
            { id: crypto.randomUUID(), role: "agent", text: parsed.text, ts: new Date() },
          ]);
        }
      } catch {
        // Not a chat packet — ignore
      }
    };
    room.on(RoomEvent.DataReceived, handler);
    return () => { room.off(RoomEvent.DataReceived, handler); };
  }, [room]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  async function sendMessage() {
    const text = input.trim();
    if (!text) return;

    setMessages((prev) => [...prev, { id: crypto.randomUUID(), role: "operator", text, ts: new Date() }]);
    setInput("");

    try {
      await room.localParticipant.publishData(
        new TextEncoder().encode(JSON.stringify({ type: "chat", text })),
        { reliable: true },
      );
    } catch (err) {
      console.error("[ChatPanel] publishData failed:", err);
    }
  }

  function applyManualScore(id: string) {
    const n = parseInt(scoreVal, 10);
    if (isNaN(n) || n < 0 || n > 100) return;
    setMessages((prev) => prev.map((m) => (m.id === id ? { ...m, manualScore: n } : m)));
    setScoringId(null);
    setScoreVal("");
  }

  return (
    <GlassCard className="p-4 flex flex-col gap-3">
      <SectionHeader
        icon={<MessageSquare size={14} />}
        title="Session Chat"
        subtitle={agentReady ? "DataChannel · agent reply relay not confirmed" : "waiting for agent startup"}
      />

      <p
        className={cn(
          "text-xs font-mono leading-relaxed rounded-lg border px-3 py-2",
          agentReady
            ? "border-slate-700/40 bg-black/10 text-slate-700"
            : "border-cyan-400/15 bg-cyan-400/[0.04] text-cyan-400/60",
        )}
      >
        {agentReady
          ? "Messages sent via DataChannel. Agent replies appear here only if the backend relays them — no reply is fabricated."
          : "Waiting for agent session to become ready…"}
      </p>

      {/* Message history */}
      <div className="flex-1 min-h-[180px] max-h-[300px] overflow-y-auto space-y-2 pr-0.5">
        {messages.length === 0 && (
          <div className="flex flex-col items-center justify-center h-full py-6 gap-2">
            <MessageSquare size={18} className="text-slate-700" />
            <p className="text-xs text-slate-600 font-mono">No messages yet</p>
          </div>
        )}

        {messages.map((msg) => (
          <div
            key={msg.id}
            className={cn(
              "group rounded-lg border px-3 py-2 text-xs",
              msg.role === "operator"
                ? "border-cyan-400/15 bg-cyan-400/[0.06] ml-4"
                : "border-violet-400/15 bg-violet-400/[0.06] mr-4",
            )}
          >
            <div className="flex items-center justify-between mb-1 gap-2">
              <Mono className={msg.role === "operator" ? "text-cyan-400" : "text-violet-400"}>
                {msg.role === "operator" ? "Operator" : "Agent"}
              </Mono>

              <div className="flex items-center gap-2 shrink-0">
                {msg.manualScore != null && (
                  <span
                    className={cn(
                      "text-[10px] font-mono px-1.5 py-0.5 rounded border",
                      msg.manualScore < 65
                        ? "text-rose-400 border-rose-400/30 bg-rose-400/10"
                        : "text-white/60 border-white/20 bg-white/[0.04]",
                    )}
                  >
                    {msg.manualScore}%&nbsp;<span className="text-slate-700">review</span>
                  </span>
                )}
                <Mono dim className="text-[10px]">
                  {msg.ts.toLocaleTimeString("en-US", { hour12: false, hour: "2-digit", minute: "2-digit" })}
                </Mono>
                <button
                  onClick={() => { setScoringId(msg.id); setScoreVal(String(msg.manualScore ?? "")); }}
                  className="opacity-0 group-hover:opacity-100 transition-opacity text-slate-700 hover:text-slate-400"
                  title="Add manual operator review score"
                >
                  <Tag size={10} />
                </button>
              </div>
            </div>

            <p className="text-slate-300 leading-relaxed whitespace-pre-wrap break-words">{msg.text}</p>

            {/* Manual score input — clearly not backend confidence */}
            {scoringId === msg.id && (
              <div className="flex items-center gap-2 mt-2 flex-wrap">
                <input
                  type="number" min={0} max={100}
                  value={scoreVal}
                  onChange={(e) => setScoreVal(e.target.value)}
                  placeholder="0–100"
                  className="w-16 rounded border border-white/[0.07] bg-black/30 px-1.5 py-0.5 text-xs text-slate-300 font-mono outline-none"
                  autoFocus
                />
                <button
                  onClick={() => applyManualScore(msg.id)}
                  className="rounded border border-white/[0.07] px-2 py-0.5 text-xs text-slate-400 hover:text-cyan-400 font-mono transition-colors"
                >
                  set
                </button>
                <button
                  onClick={() => { setScoringId(null); setScoreVal(""); }}
                  className="text-xs text-slate-700 hover:text-slate-400 font-mono"
                >
                  cancel
                </button>
                <Mono dim className="text-[10px]">operator review · not backend confidence</Mono>
              </div>
            )}
          </div>
        ))}

        <div ref={bottomRef} />
      </div>

      {/* Input row */}
      <div className="flex gap-2">
        <input
          type="text"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && !e.shiftKey && sendMessage()}
          placeholder={agentReady ? "Type a message…" : "Connect session first"}
          disabled={!agentReady}
          className="flex-1 rounded-md border border-white/[0.07] bg-black/30 px-3 py-2 text-xs text-slate-300 font-mono placeholder:text-slate-700 outline-none focus:border-cyan-400/40 disabled:opacity-40"
        />
        <button
          onClick={sendMessage}
          disabled={!input.trim() || !agent}
          className={cn(
            "flex items-center gap-1.5 shrink-0 rounded-md border px-3 py-2 text-xs font-medium transition-colors",
            input.trim() && agentReady
              ? "border-cyan-400/30 bg-cyan-400/10 text-cyan-400 hover:bg-cyan-400/15"
              : "border-white/[0.05] text-slate-600 cursor-not-allowed",
          )}
        >
          <Send size={12} />
          Send
        </button>
      </div>
    </GlassCard>
  );
}
EOF

# ==============================================================================
# 50 · components/session/TranscriptPanel.tsx — honest empty state
# STT runs server-side. No client-visible transcript stream is confirmed.
# ==============================================================================
cat > components/session/TranscriptPanel.tsx << 'EOF'
"use client";

import { GlassCard }     from "@/components/shared/GlassCard";
import { SectionHeader } from "@/components/shared/SectionHeader";
import { MessageSquare } from "lucide-react";

export function TranscriptPanel() {
  return (
    <GlassCard className="p-4 flex flex-col min-h-[110px]">
      <SectionHeader icon={<MessageSquare size={14} />} title="Transcript" />
      <div className="flex flex-1 flex-col items-center justify-center py-2 gap-1.5 text-center">
        <MessageSquare size={18} className="text-slate-700" />
        <p className="text-xs text-slate-500 font-mono">Transcript relay not available</p>
        <p className="text-xs text-slate-700 font-mono max-w-xs leading-relaxed">
          STT and synthesis run server-side. The current backend does not publish a
          client-visible transcript stream. No data is being withheld.
        </p>
      </div>
    </GlassCard>
  );
}
EOF

# ==============================================================================
# 51 · components/session/VoicePreviewList.tsx
# Preview (listen) before selecting a reference voice.
# Audio served from /api/reference-audio/[voice] (inputs/ directory only).
# ==============================================================================
cat > components/session/VoicePreviewList.tsx << 'EOF'
"use client";

import { useState } from "react";
import { useAudioInventory } from "@/hooks/useInventory";
import { Mono } from "@/components/shared/Mono";
import { Play, Square, CheckCircle2 } from "lucide-react";
import { cn } from "@/lib/utils";

interface VoicePreviewListProps {
  selectedVoice: string;
  onSelect:      (voice: string) => void;
}

export function VoicePreviewList({ selectedVoice, onSelect }: VoicePreviewListProps) {
  const { data, error, loading } = useAudioInventory();
  const [playingVoice, setPlayingVoice] = useState<string | null>(null);
  const [audioElement, setAudioElement] = useState<HTMLAudioElement | null>(null);

  function togglePreview(voice: string) {
    // Stop current playback
    if (audioElement) {
      audioElement.pause();
      audioElement.src = "";
    }

    if (playingVoice === voice) {
      setPlayingVoice(null);
      setAudioElement(null);
      return;
    }

    const a = new Audio(`/api/reference-audio/${encodeURIComponent(voice)}`);
    setAudioElement(a);
    setPlayingVoice(voice);

    const cleanup = () => { setPlayingVoice(null); setAudioElement(null); };
    a.onended = cleanup;
    a.onerror = cleanup;
    a.play().catch(cleanup);
  }

  if (loading) return <p className="text-xs text-slate-600 font-mono">Loading voices…</p>;
  if (error)   return <p className="text-xs text-rose-400 font-mono">{error}</p>;

  if (!data || data.voices.length === 0) {
    return (
      <p className="text-xs text-slate-600 font-mono">
        No files in VOICEAI_ROOT/inputs/. Add .wav / .mp3 / .flac reference audio to enable preview.
      </p>
    );
  }

  return (
    <div className="space-y-1.5">
      {data.voices.map((v) => {
        const isPlaying = playingVoice === v.voice;
        const isChosen  = selectedVoice === v.voice;

        return (
          <div
            key={v.voice}
            className={cn(
              "flex items-center gap-2 rounded-lg border px-3 py-2 transition-colors",
              isChosen
                ? "border-cyan-400/30 bg-cyan-400/[0.07]"
                : "border-white/[0.05] bg-black/15 hover:border-white/[0.09]",
            )}
          >
            <button
              onClick={() => togglePreview(v.voice)}
              className={cn(
                "flex items-center justify-center w-6 h-6 rounded-full border shrink-0 transition-colors",
                isPlaying
                  ? "border-violet-400/40 bg-violet-400/15 text-violet-400"
                  : "border-white/[0.10] text-slate-500 hover:text-slate-300",
              )}
            >
              {isPlaying ? <Square size={9} fill="currentColor" /> : <Play size={9} fill="currentColor" />}
            </button>

            <div className="flex-1 min-w-0">
              <p className={cn("text-xs font-medium truncate", isChosen ? "text-cyan-400" : "text-slate-300")}>
                {v.voice}
              </p>
              <Mono dim>{v.size_kb} KB · {v.filename.split(".").pop()?.toUpperCase()}</Mono>
            </div>

            <button
              onClick={() => onSelect(isChosen ? "" : v.voice)}
              className={cn(
                "flex items-center gap-1 shrink-0 rounded border px-2 py-0.5 text-[10px] font-mono transition-colors",
                isChosen
                  ? "border-cyan-400/40 bg-cyan-400/10 text-cyan-400"
                  : "border-white/[0.07] text-slate-500 hover:text-slate-300",
              )}
            >
              <CheckCircle2 size={10} />
              {isChosen ? "Selected" : "Select"}
            </button>
          </div>
        );
      })}
    </div>
  );
}
EOF

# ==============================================================================
# 52 · components/session/VoiceControls.tsx
# Session-scoped RPC only: persona / voice / language / instruct / interruption.
# VoicePreviewList is embedded (collapsed by default) for listen-before-select.
# Global engine/model switches are NOT here — they live in the Services tab.
# ==============================================================================
cat > components/session/VoiceControls.tsx << 'EOF'
"use client";

import { useEffect, useMemo, useState } from "react";
import { useRoomContext } from "@livekit/components-react";
import { useAgentTarget } from "@/hooks/useAgentTarget";
import { usePersonaInventory } from "@/hooks/useInventory";
import { VoicePreviewList }    from "./VoicePreviewList";
import { GlassCard }     from "@/components/shared/GlassCard";
import { SectionHeader } from "@/components/shared/SectionHeader";
import { InlineAlert }   from "@/components/shared/InlineAlert";
import { Mono }          from "@/components/shared/Mono";
import { Users, CheckCircle2, ChevronDown, ChevronUp } from "lucide-react";
import { LANGUAGES_CHATTERBOX, LANGUAGES_OTHER, INTERRUPTION_MODES } from "@/lib/constants";
import { useTtsState } from "@/hooks/useTtsState";
import { cn } from "@/lib/utils";

interface RpcResult {
  ok:      boolean;
  message: string;
}

function useAgentRpc() {
  const room = useRoomContext();
  const { ready, identity } = useAgentTarget();

  async function call(method: string, payload: Record<string, unknown>): Promise<string> {
    if (!ready || !identity) throw new Error("Agent session is not ready yet");
    return room.localParticipant.performRpc({
      destinationIdentity: identity,
      method,
      payload:         JSON.stringify(payload),
      responseTimeout: 8_000,
    });
  }

  return { call, agentReady: ready };
}

interface SelectFieldProps {
  label:    string;
  value:    string;
  onChange: (v: string) => void;
  options:  { value: string; label: string }[];
}

function SelectField({ label, value, onChange, options }: SelectFieldProps) {
  return (
    <div className="space-y-1">
      <Mono dim>{label}</Mono>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="w-full rounded-md border border-white/[0.07] bg-black/30 px-2 py-1.5 text-xs text-slate-300 font-mono outline-none focus:border-cyan-400/40"
      >
        {options.map((o) => (
          <option key={o.value} value={o.value}>{o.label}</option>
        ))}
      </select>
    </div>
  );
}

export function VoiceControls() {
  const { call, agentReady } = useAgentRpc();
  const personas              = usePersonaInventory();
  const tts                   = useTtsState();

  const [persona,     setPersona]     = useState("english_teacher");
  const [voice,       setVoice]       = useState("Aiden");
  const [language,    setLanguage]    = useState("English");
  const [instruct,    setInstruct]    = useState("");
  const [interrupt,   setInterrupt]   = useState("normal");
  const [busy,        setBusy]        = useState(false);
  const [result,      setResult]      = useState<RpcResult | null>(null);
  const [showPreview, setShowPreview] = useState(false);

  const activeTtsMode = tts.data?.active_mode ?? "customvoice";
  const languageOptions = useMemo(
    () => (activeTtsMode === "chatterbox" ? LANGUAGES_CHATTERBOX : LANGUAGES_OTHER),
    [activeTtsMode],
  );

  useEffect(() => {
    if (!languageOptions.some((l) => l.value === language)) {
      setLanguage(languageOptions[0]?.value ?? "");
    }
  }, [language, languageOptions]);

  async function rpc(method: string, payload: Record<string, unknown>) {
    if (busy) return;
    setBusy(true);
    setResult(null);
    try {
      await call(method, payload);
      const confirmations: Record<string, string> = {
        set_persona:               `Persona → ${payload.name}`,
        set_session_voice:         `Voice applied${voice ? `: ${voice}` : ""} · ${language}`,
        set_interruption_behavior: `Interruption → ${payload.mode}`,
      };
      setResult({ ok: true, message: confirmations[method] ?? "OK" });
    } catch (err) {
      setResult({ ok: false, message: err instanceof Error ? err.message : String(err) });
    } finally {
      setBusy(false);
    }
  }

  if (!agentReady) {
    return (
      <GlassCard className="p-4">
        <SectionHeader icon={<Users size={14} />} title="Session Voice Controls" />
        <p className="text-xs text-slate-600 font-mono mt-1">Waiting for agent participant in room…</p>
      </GlassCard>
    );
  }

  const personaOptions = personas.data?.personas.map((p) => ({
    value: p.name,
    label: p.display_name ?? p.name,
  })) ?? [];

  return (
    <GlassCard className="p-4 space-y-3">
      <SectionHeader
        icon={<Users size={14} />}
        title="Session Voice Controls"
        subtitle="RPC · session-scoped only"
      />

      {/* Persona switch */}
      <div className="rounded-lg border border-white/[0.05] p-3 space-y-2">
        <Mono dim>Active persona</Mono>
        <div className="flex gap-2">
          {personaOptions.length > 0 ? (
            <select
              value={persona}
              onChange={(e) => setPersona(e.target.value)}
              className="flex-1 rounded-md border border-white/[0.07] bg-black/30 px-2 py-1.5 text-xs text-slate-300 font-mono outline-none focus:border-cyan-400/40"
            >
              <option value="">— select persona —</option>
              {personaOptions.map((o) => (
                <option key={o.value} value={o.value}>{o.label}</option>
              ))}
            </select>
          ) : (
            <p className="flex-1 text-xs text-slate-600 font-mono py-1.5">
              No personas — telemetry offline?
            </p>
          )}
          <button
            onClick={() => persona && rpc("set_persona", { name: persona })}
            disabled={!persona || busy}
            className={cn(
              "flex items-center gap-1 shrink-0 rounded-md border px-2 py-1.5 text-xs transition-colors",
              persona && !busy
                ? "border-cyan-400/30 bg-cyan-400/10 text-cyan-400 hover:bg-cyan-400/15"
                : "border-white/[0.05] text-slate-600 cursor-not-allowed",
            )}
          >
            <CheckCircle2 size={11} />
            Apply
          </button>
        </div>
      </div>

      {/* Reference voice: preview → select */}
      <div className="rounded-lg border border-white/[0.05] overflow-hidden">
        <button
          onClick={() => setShowPreview((v) => !v)}
          className="flex items-center justify-between w-full px-3 py-2 text-xs text-slate-400 hover:text-slate-200 transition-colors"
        >
          <div className="flex items-center gap-2">
            <Mono dim>Reference voice</Mono>
            {voice ? (
              <span className="text-cyan-400 font-mono text-[10px] px-1.5 py-0.5 rounded border border-cyan-400/25 bg-cyan-400/10">
                {voice}
              </span>
            ) : (
              <Mono dim>none selected</Mono>
            )}
          </div>
          {showPreview ? <ChevronUp size={12} /> : <ChevronDown size={12} />}
        </button>
        {showPreview && (
          <div className="border-t border-white/[0.05] p-3">
            <VoicePreviewList selectedVoice={voice} onSelect={setVoice} />
          </div>
        )}
      </div>

      {/* Language + style instruction */}
      <div className="rounded-lg border border-white/[0.05] p-3 space-y-2">
        <Mono dim>Language · style</Mono>
        <SelectField
          label="Language"
          value={language}
          onChange={setLanguage}
          options={languageOptions.map((l) => ({ value: l.value, label: l.label }))}
        />
        <div className="space-y-1">
          <Mono dim>Style instruction (optional)</Mono>
          <input
            type="text"
            value={instruct}
            onChange={(e) => setInstruct(e.target.value)}
            placeholder="e.g. warm, calm narrator"
            className="w-full rounded-md border border-white/[0.07] bg-black/30 px-2 py-1.5 text-xs text-slate-300 font-mono placeholder:text-slate-700 outline-none focus:border-cyan-400/40"
          />
        </div>
        <button
          onClick={() => rpc("set_session_voice", { voice, language, instruct })}
          disabled={busy}
          className="w-full rounded-md border border-cyan-400/30 bg-cyan-400/10 py-1.5 text-xs font-medium text-cyan-400 hover:bg-cyan-400/15 transition-colors"
        >
          Apply Voice Settings
        </button>
      </div>

      {/* Interruption behavior */}
      <div className="rounded-lg border border-white/[0.05] p-3 space-y-2">
        <SelectField
          label="Interruption behavior"
          value={interrupt}
          onChange={setInterrupt}
          options={INTERRUPTION_MODES.map((m) => ({ value: m.value, label: m.label }))}
        />
        <button
          onClick={() => rpc("set_interruption_behavior", { mode: interrupt })}
          disabled={busy}
          className="w-full rounded-md border border-white/[0.07] bg-black/15 py-1.5 text-xs font-medium text-slate-400 hover:text-slate-200 transition-colors"
        >
          Apply Interruption Mode
        </button>
      </div>

      {result && <InlineAlert kind={result.ok ? "success" : "error"} message={result.message} />}
    </GlassCard>
  );
}
EOF

# ==============================================================================
# 53 · components/session/MemoryControls.tsx
# Explicit control-plane actions only. Requires agent in room (LiveKit RPC).
# Wording: Save Session Snapshot / Restore Context / Search Memory
# ==============================================================================
cat > components/session/MemoryControls.tsx << 'EOF'
"use client";

import { useState } from "react";
import { useRoomContext } from "@livekit/components-react";
import { useAgentTarget } from "@/hooks/useAgentTarget";
import { GlassCard }     from "@/components/shared/GlassCard";
import { SectionHeader } from "@/components/shared/SectionHeader";
import { InlineAlert }   from "@/components/shared/InlineAlert";
import { Mono }          from "@/components/shared/Mono";
import { Database, ToggleLeft, ToggleRight, Save, RotateCcw, Search } from "lucide-react";
import { cn } from "@/lib/utils";

interface ActionResult {
  ok:      boolean;
  message: string;
}

export function MemoryControls() {
  const room = useRoomContext();
  const { ready: agentReady, identity: agentIdentity } = useAgentTarget();

  const [memoryEnabled, setMemoryEnabled] = useState(false);
  const [summary,       setSummary]       = useState("");
  const [query,         setQuery]         = useState("");
  const [busy,          setBusy]          = useState(false);
  const [result,        setResult]        = useState<ActionResult | null>(null);

  async function rpc(method: string, payload: Record<string, unknown>): Promise<string> {
    if (!agentReady || !agentIdentity) throw new Error("Agent session is not ready yet");
    return room.localParticipant.performRpc({
      destinationIdentity: agentIdentity,
      method,
      payload:         JSON.stringify(payload),
      responseTimeout: 10_000,
    });
  }

  async function act(fn: () => Promise<void>) {
    if (busy) return;
    setBusy(true);
    setResult(null);
    try {
      await fn();
    } catch (err) {
      setResult({ ok: false, message: err instanceof Error ? err.message : String(err) });
    } finally {
      setBusy(false);
    }
  }

  if (!agentReady || !agentIdentity) {
    return (
      <GlassCard className="p-4">
        <SectionHeader icon={<Database size={14} />} title="Memory" subtitle="requires active session" />
        <p className="text-xs text-slate-600 font-mono mt-1">Agent session not ready yet — connect and wait a moment.</p>
      </GlassCard>
    );
  }

  return (
    <GlassCard className="p-4 space-y-3">
      <SectionHeader icon={<Database size={14} />} title="Memory" subtitle="explicit control-plane" />

      {/* Enable / disable toggle */}
      <div className="flex items-center justify-between rounded-lg border border-white/[0.05] bg-black/20 px-3 py-2">
        <div>
          <p className="text-xs font-medium text-slate-300">Qdrant memory</p>
          <Mono dim>{memoryEnabled ? "enabled — storing context" : "disabled"}</Mono>
        </div>
        <button
          onClick={() =>
            act(async () => {
              await rpc("set_memory_enabled", { enabled: !memoryEnabled });
              setMemoryEnabled((v) => !v);
              setResult({ ok: true, message: `Memory ${!memoryEnabled ? "enabled" : "disabled"}` });
            })
          }
          disabled={busy}
          className="text-slate-400 hover:text-cyan-400 transition-colors"
        >
          {memoryEnabled
            ? <ToggleRight size={22} className="text-emerald-400" />
            : <ToggleLeft  size={22} />}
        </button>
      </div>

      {/* Save Session Snapshot */}
      <div className="rounded-lg border border-white/[0.05] p-3 space-y-2">
        <div>
          <Mono className="flex items-center gap-1.5">
            <Save size={11} />
            Save Session Snapshot
          </Mono>
          <Mono dim className="mt-0.5 block">Writes a memory checkpoint to Qdrant</Mono>
        </div>
        <textarea
          rows={2}
          value={summary}
          onChange={(e) => setSummary(e.target.value)}
          placeholder="Describe what happened in this session…"
          className="w-full rounded-md border border-white/[0.07] bg-black/30 px-2 py-1.5 text-xs text-slate-300 font-mono placeholder:text-slate-700 outline-none focus:border-cyan-400/40 resize-none"
        />
        <button
          onClick={() =>
            act(async () => {
              await rpc("create_memory_checkpoint", { summary: summary.trim(), session_id: "" });
              setResult({ ok: true, message: "Session snapshot saved to Qdrant" });
              setSummary("");
            })
          }
          disabled={!summary.trim() || busy}
          className={cn(
            "w-full rounded-md border py-1.5 text-xs font-medium transition-colors",
            summary.trim() && !busy
              ? "border-cyan-400/30 bg-cyan-400/10 text-cyan-400 hover:bg-cyan-400/15"
              : "border-white/[0.05] text-slate-600 cursor-not-allowed",
          )}
        >
          Save Snapshot
        </button>
      </div>

      {/* Restore Context + Search Memory */}
      <div className="rounded-lg border border-white/[0.05] p-3 space-y-2">
        <Mono dim>Restore Context / Search Memory</Mono>
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="What to recall? (e.g. user's name, last topic…)"
          className="w-full rounded-md border border-white/[0.07] bg-black/30 px-2 py-1.5 text-xs text-slate-300 font-mono placeholder:text-slate-700 outline-none focus:border-cyan-400/40"
        />
        <div className="grid grid-cols-2 gap-1.5">
          <button
            onClick={() =>
              act(async () => {
                await rpc("restore_previous_context", { query: query.trim(), user_id: "" });
                setResult({ ok: true, message: "Restore Context requested — agent will inject retrieved context." });
              })
            }
            disabled={!query.trim() || busy}
            className={cn(
              "flex items-center justify-center gap-1 rounded-md border py-1.5 text-xs transition-colors",
              query.trim() && !busy
                ? "border-violet-400/30 bg-violet-400/10 text-violet-400 hover:bg-violet-400/15"
                : "border-white/[0.05] text-slate-600 cursor-not-allowed",
            )}
          >
            <RotateCcw size={11} />
            Restore Context
          </button>
          <button
            onClick={() =>
              act(async () => {
                const raw = await rpc("search_memory", { query: query.trim(), limit: 5 });
                setResult({
                  ok:      true,
                  message: raw?.length > 300 ? `${raw.slice(0, 300)}…` : (raw || "No results"),
                });
              })
            }
            disabled={!query.trim() || busy}
            className={cn(
              "flex items-center justify-center gap-1 rounded-md border py-1.5 text-xs transition-colors",
              query.trim() && !busy
                ? "border-cyan-400/30 bg-cyan-400/10 text-cyan-400 hover:bg-cyan-400/15"
                : "border-white/[0.05] text-slate-600 cursor-not-allowed",
            )}
          >
            <Search size={11} />
            Search Memory
          </button>
        </div>
      </div>

      {result && <InlineAlert kind={result.ok ? "success" : "error"} message={result.message} />}
    </GlassCard>
  );
}
EOF

# ==============================================================================
# 54 · components/session/SessionPanel.tsx
# Single connected-session rendering path. Single-column layout (max-w-2xl).
# RoomContent renders: MicButton → ContextPressureCard → ChatPanel →
#   TranscriptPanel → VoiceControls → MemoryControls
# ==============================================================================
cat > components/session/SessionPanel.tsx << 'EOF'
"use client";

import { useState, useCallback } from "react";
import {
  LiveKitRoom,
  RoomAudioRenderer,
  useConnectionState,
} from "@livekit/components-react";
import { ConnectionState } from "livekit-client";
import "@livekit/components-styles";
import { GlassCard }          from "@/components/shared/GlassCard";
import { SectionHeader }      from "@/components/shared/SectionHeader";
import { StatusDot }          from "@/components/shared/StatusDot";
import { InlineAlert }        from "@/components/shared/InlineAlert";
import { Mono }               from "@/components/shared/Mono";
import { MicButton }          from "./MicButton";
import { ContextPressureCard } from "./ContextPressureCard";
import { ChatPanel }          from "./ChatPanel";
import { TranscriptPanel }    from "./TranscriptPanel";
import { VoiceControls }      from "./VoiceControls";
import { MemoryControls }     from "./MemoryControls";
import { Radio, LogOut }      from "lucide-react";
import { cn }                 from "@/lib/utils";

interface TokenData {
  token: string;
  url: string;
  roomName: string;
  identity: string;
}

function ConnectionStatus() {
  const state = useConnectionState();
  const status =
    state === ConnectionState.Connected    ? "online"   :
    state === ConnectionState.Reconnecting ? "degraded" :
    state === ConnectionState.Disconnected ? "offline"  : "unknown";

  return (
    <div className="flex items-center gap-2">
      <StatusDot status={status} />
      <Mono>{state}</Mono>
    </div>
  );
}

function RoomContent({ onDisconnect }: { onDisconnect: () => void }) {
  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <ConnectionStatus />
        <button
          onClick={onDisconnect}
          className="flex items-center gap-1.5 rounded-md border border-white/[0.07] px-3 py-1.5 text-xs text-slate-500 hover:text-rose-400 hover:border-rose-400/30 transition-colors"
        >
          <LogOut size={12} />
          Disconnect
        </button>
      </div>

      <RoomAudioRenderer />

      <MicButton />
      <ContextPressureCard />
      <ChatPanel />
      <TranscriptPanel />
      <VoiceControls />
      <MemoryControls />
    </div>
  );
}

export function SessionPanel() {
  const [tokenData,  setTokenData]  = useState<TokenData | null>(null);
  const [connecting, setConnecting] = useState(false);
  const [error,      setError]      = useState<string | null>(null);

  const connect = useCallback(async () => {
    setConnecting(true);
    setError(null);
    try {
      const res = await fetch("/api/livekit/token", { cache: "no-store" });
      const data = await res.json();

      if (!res.ok) throw new Error(data.error ?? `HTTP ${res.status}`);
      if (!data.token || !data.url || !data.roomName) {
        throw new Error("Invalid token response from server");
      }

      setTokenData(data as TokenData);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setConnecting(false);
    }
  }, []);

  const disconnect = useCallback(() => {
    setTokenData(null);
    setError(null);
  }, []);

  return (
    <GlassCard className="p-4 space-y-3">
      <SectionHeader
        icon={<Radio size={14} />}
        title="Session"
        subtitle={`${tokenData?.roomName ?? "voice-room"} · LiveKit`}
      />

      {!tokenData ? (
        <div className="space-y-3">
          {error && <InlineAlert kind="error" message={error} />}

          <button
            onClick={connect}
            disabled={connecting}
            className={cn(
              "flex items-center gap-2 rounded-lg px-4 py-2.5 text-sm font-semibold transition-all border",
              connecting
                ? "bg-white/[0.04] text-slate-600 cursor-not-allowed border-white/[0.05]"
                : "bg-cyan-400/10 border-cyan-400/30 text-cyan-400 hover:bg-cyan-400/15",
            )}
          >
            <Radio size={16} className={connecting ? "animate-pulse" : ""} />
            {connecting ? "Connecting…" : "Connect Session"}
          </button>

          <p className="text-xs text-slate-700 font-mono leading-relaxed">
            Creates a fresh LiveKit room. The participant token dispatches the configured agent on connect. Choose your microphone and click "Start Mic" after connecting.
          </p>
        </div>
      ) : (
        <LiveKitRoom
          token={tokenData.token}
          serverUrl={tokenData.url}
          connect={true}
          audio={false}
          video={false}
          onDisconnected={disconnect}
          onError={(err) => { setError(err.message); disconnect(); }}
        >
          <RoomContent onDisconnect={disconnect} />
        </LiveKitRoom>
      )}
    </GlassCard>
  );
}
EOF

# ==============================================================================
# 55 · components/session/SessionTab.tsx — single-column, max-w-2xl
# ==============================================================================
cat > components/session/SessionTab.tsx << 'EOF'
"use client";

import { SessionPanel } from "./SessionPanel";

export function SessionTab() {
  return (
    <div className="h-full overflow-y-auto p-4">
      <div className="mx-auto max-w-2xl">
        <SessionPanel />
      </div>
    </div>
  );
}
EOF

# ==============================================================================
# 56 · components/personas/PersonaManager.tsx — full file CRUD
# Separate from session persona switching (set_persona RPC in VoiceControls).
# ==============================================================================
cat > components/personas/PersonaManager.tsx << 'EOF'
"use client";

import { useState, useEffect } from "react";
import { GlassCard }     from "@/components/shared/GlassCard";
import { SectionHeader } from "@/components/shared/SectionHeader";
import { InlineAlert }   from "@/components/shared/InlineAlert";
import { Mono }          from "@/components/shared/Mono";
import { Users, Plus, Save, Trash2, RefreshCw, Copy } from "lucide-react";
import { cn } from "@/lib/utils";

interface PersonaFile {
  name:       string;
  filename:   string;
  size_bytes: number;
}

interface ActionResult {
  ok:      boolean;
  message: string;
}

export function PersonaManager() {
  const [files,    setFiles]    = useState<PersonaFile[]>([]);
  const [loading,  setLoading]  = useState(true);
  const [selected, setSelected] = useState("");
  const [content,  setContent]  = useState("");
  const [dirty,    setDirty]    = useState(false);
  const [newName,  setNewName]  = useState("");
  const [result,   setResult]   = useState<ActionResult | null>(null);
  const [busy,     setBusy]     = useState(false);

  async function refresh() {
    setLoading(true);
    try {
      const res  = await fetch("/api/personas");
      const data = await res.json();
      setFiles(data.personas ?? []);
    } catch {
      setFiles([]);
    } finally {
      setLoading(false);
    }
  }

  async function loadFile(name: string) {
    setResult(null);
    try {
      const res  = await fetch(`/api/personas/${encodeURIComponent(name)}`);
      const data = await res.json();
      if (data.ok) {
        setContent(data.content);
        setSelected(name);
        setDirty(false);
      }
    } catch {
      setResult({ ok: false, message: "Load failed" });
    }
  }

  async function saveFile() {
    if (!selected || busy) return;
    setBusy(true);
    setResult(null);
    try {
      const res  = await fetch(`/api/personas/${encodeURIComponent(selected)}`, {
        method:  "PUT",
        headers: { "Content-Type": "application/json" },
        body:    JSON.stringify({ content }),
      });
      const data = await res.json() as ActionResult;
      setResult(data);
      if (data.ok) {
        setDirty(false);
        await refresh();
      }
    } catch (err) {
      setResult({ ok: false, message: String(err) });
    } finally {
      setBusy(false);
    }
  }

  async function createFile() {
    const name = newName.trim();
    if (!name || busy) return;
    setBusy(true);
    setResult(null);
    try {
      const res  = await fetch("/api/personas", {
        method:  "POST",
        headers: { "Content-Type": "application/json" },
        body:    JSON.stringify({ name }),
      });
      const data = await res.json() as ActionResult;
      setResult(data);
      if (data.ok) {
        setNewName("");
        await refresh();
        loadFile(name);
      }
    } catch (err) {
      setResult({ ok: false, message: String(err) });
    } finally {
      setBusy(false);
    }
  }

  async function duplicateFile() {
    if (!selected || busy) return;
    const copyName = `${selected}_copy`;
    setBusy(true);
    setResult(null);
    try {
      const createRes  = await fetch("/api/personas", {
        method:  "POST",
        headers: { "Content-Type": "application/json" },
        body:    JSON.stringify({ name: copyName }),
      });
      const createData = await createRes.json() as ActionResult;

      if (createData.ok) {
        await fetch(`/api/personas/${encodeURIComponent(copyName)}`, {
          method:  "PUT",
          headers: { "Content-Type": "application/json" },
          body:    JSON.stringify({ content }),
        });
        setResult({ ok: true, message: `Duplicated as '${copyName}'` });
        await refresh();
        loadFile(copyName);
      } else {
        setResult(createData);
      }
    } catch (err) {
      setResult({ ok: false, message: String(err) });
    } finally {
      setBusy(false);
    }
  }

  async function deleteFile() {
    if (!selected || !confirm(`Delete '${selected}'? This is irreversible.`)) return;
    setBusy(true);
    setResult(null);
    try {
      const res  = await fetch(`/api/personas/${encodeURIComponent(selected)}`, { method: "DELETE" });
      const data = await res.json() as ActionResult;
      setResult(data);
      if (data.ok) {
        setSelected("");
        setContent("");
        await refresh();
      }
    } catch (err) {
      setResult({ ok: false, message: String(err) });
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => { refresh(); }, []);

  return (
    <GlassCard className="p-4 space-y-4">
      <SectionHeader
        icon={<Users size={14} />}
        title="Persona File Management"
        subtitle="VOICEAI_ROOT/agent/personas/ · session switch via LiveKit RPC set_persona"
      />

      {/* Create new persona */}
      <div className="flex gap-2">
        <input
          type="text"
          value={newName}
          onChange={(e) => setNewName(e.target.value.replace(/[^a-zA-Z0-9_-]/g, ""))}
          onKeyDown={(e) => e.key === "Enter" && createFile()}
          placeholder="new_persona_name"
          maxLength={64}
          className="flex-1 rounded-md border border-white/[0.07] bg-black/30 px-2 py-1.5 text-xs text-slate-300 font-mono placeholder:text-slate-700 outline-none focus:border-cyan-400/40"
        />
        <button
          onClick={createFile}
          disabled={!newName.trim() || busy}
          className={cn(
            "flex items-center gap-1 shrink-0 rounded-md border px-2 py-1.5 text-xs transition-colors",
            newName.trim() && !busy
              ? "border-emerald-400/30 bg-emerald-400/10 text-emerald-400 hover:bg-emerald-400/15"
              : "border-white/[0.05] text-slate-600 cursor-not-allowed",
          )}
        >
          <Plus size={11} />
          Create
        </button>
        <button
          onClick={refresh}
          disabled={loading}
          className="rounded-md border border-white/[0.07] px-2 py-1.5 text-slate-500 hover:text-slate-300 transition-colors"
        >
          <RefreshCw size={12} className={loading ? "animate-spin" : ""} />
        </button>
      </div>

      {/* File list + editor */}
      <div className="grid grid-cols-1 gap-3 md:grid-cols-[180px_1fr]">
        {/* File list */}
        <div className="rounded-lg border border-white/[0.05] bg-black/15 overflow-hidden min-h-[80px]">
          {files.length === 0 && (
            <p className="px-3 py-3 text-xs text-slate-600 font-mono">
              {loading ? "Loading…" : "No personas found"}
            </p>
          )}
          {files.map((file) => (
            <button
              key={file.name}
              onClick={() => loadFile(file.name)}
              className={cn(
                "w-full text-left px-3 py-2 text-xs font-medium transition-colors border-b border-white/[0.03] last:border-0",
                selected === file.name
                  ? "bg-cyan-400/10 text-cyan-400"
                  : "text-slate-400 hover:text-slate-200 hover:bg-white/[0.03]",
              )}
            >
              {file.name}
              <Mono dim className="block mt-0.5">{(file.size_bytes / 1024).toFixed(1)}KB</Mono>
            </button>
          ))}
        </div>

        {/* Editor */}
        <div className="space-y-2">
          {selected ? (
            <>
              <div className="flex items-center justify-between">
                <Mono className="text-slate-300">{selected}.md</Mono>
                <div className="flex gap-1.5">
                  <button
                    onClick={duplicateFile}
                    disabled={busy}
                    title="Duplicate"
                    className="rounded border border-white/[0.07] p-1 text-slate-500 hover:text-slate-300 transition-colors"
                  >
                    <Copy size={11} />
                  </button>
                  <button
                    onClick={deleteFile}
                    disabled={busy}
                    title="Delete"
                    className="rounded border border-rose-400/20 p-1 text-rose-400/50 hover:text-rose-400 transition-colors"
                  >
                    <Trash2 size={11} />
                  </button>
                </div>
              </div>

              <textarea
                value={content}
                onChange={(e) => { setContent(e.target.value); setDirty(true); }}
                rows={12}
                className="w-full rounded-md border border-white/[0.07] bg-black/30 px-3 py-2 text-xs text-slate-300 font-mono outline-none focus:border-cyan-400/40 resize-y"
              />

              <button
                onClick={saveFile}
                disabled={!dirty || busy}
                className={cn(
                  "flex items-center gap-1.5 w-full justify-center rounded-md border py-1.5 text-xs font-medium transition-colors",
                  dirty && !busy
                    ? "border-cyan-400/30 bg-cyan-400/10 text-cyan-400 hover:bg-cyan-400/15"
                    : "border-white/[0.05] text-slate-600 cursor-not-allowed",
                )}
              >
                <Save size={12} />
                {busy ? "Saving…" : dirty ? "Save Changes" : "No unsaved changes"}
              </button>
            </>
          ) : (
            <div className="flex items-center justify-center min-h-[120px] text-xs text-slate-600 font-mono">
              Select a persona to edit
            </div>
          )}
        </div>
      </div>

      {result && <InlineAlert kind={result.ok ? "success" : "error"} message={result.message} />}

      <div className="rounded-lg border border-amber-400/15 bg-amber-400/[0.03] px-3 py-2">
        <p className="text-xs text-amber-400/70 font-mono leading-relaxed">
          File changes take effect on next session start. To switch persona mid-session use
          Session Voice Controls (LiveKit RPC set_persona).
        </p>
      </div>
    </GlassCard>
  );
}
EOF

# ==============================================================================
# 57 · components/personas/PersonasTab.tsx
# ==============================================================================
cat > components/personas/PersonasTab.tsx << 'EOF'
"use client";

import { PersonaManager } from "./PersonaManager";

export function PersonasTab() {
  return (
    <div className="h-full overflow-y-auto p-4">
      <div className="mx-auto max-w-4xl">
        <PersonaManager />
      </div>
    </div>
  );
}
EOF

# ==============================================================================
# 58 · components/memory/MemoryPanel.tsx
# Qdrant collection stats via telemetry inventory (no session required).
# Control-plane actions (snapshot, restore, search) require session — see SessionTab.
# ==============================================================================
cat > components/memory/MemoryPanel.tsx << 'EOF'
"use client";

import { usePoll }       from "@/hooks/usePoll";
import { GlassCard }     from "@/components/shared/GlassCard";
import { SectionHeader } from "@/components/shared/SectionHeader";
import { StatusDot }     from "@/components/shared/StatusDot";
import { Mono }          from "@/components/shared/Mono";
import { Database, Info } from "lucide-react";
import { POLL }          from "@/lib/constants";
import type { MemoryInventory } from "@/lib/types";

async function fetchMemoryInventory(): Promise<MemoryInventory> {
  const res = await fetch("/api/proxy/telemetry/inventory/memory", { cache: "no-store" });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

function QdrantCard() {
  const { data, error, loading } = usePoll<MemoryInventory>(fetchMemoryInventory, POLL.NORMAL);

  return (
    <GlassCard className="p-4 space-y-3">
      <SectionHeader icon={<Database size={14} />} title="Qdrant" subtitle="127.0.0.1:6333 · memory backbone" />

      {loading && <p className="text-xs text-slate-600 font-mono">Checking…</p>}
      {error   && <p className="text-xs text-rose-400 font-mono">{error}</p>}

      {data && (
        <>
          <StatusDot status={data.online ? "online" : "offline"} showLabel />

          {data.online && data.collections && data.collections.length > 0 && (
            <div className="rounded-lg border border-white/[0.05] bg-black/20 divide-y divide-white/[0.04]">
              {data.collections.map((col) => (
                <div key={col.name} className="flex items-center justify-between px-3 py-2">
                  <Mono className="text-slate-400">{col.name}</Mono>
                  <Mono dim>{col.vectors_count.toLocaleString()} vectors</Mono>
                </div>
              ))}
            </div>
          )}

          {data.online && (!data.collections || data.collections.length === 0) && (
            <p className="text-xs text-slate-600 font-mono">
              No collections. Run bootstrap.sh to initialise memory.
            </p>
          )}

          {data.error && <p className="text-xs text-amber-400 font-mono">{data.error}</p>}
        </>
      )}
    </GlassCard>
  );
}

export function MemoryTab() {
  return (
    <div className="h-full overflow-y-auto p-4">
      <div className="mx-auto max-w-2xl space-y-4">
        <QdrantCard />

        <GlassCard className="p-4">
          <SectionHeader icon={<Info size={14} />} title="Memory Control-Plane" subtitle="session required" />
          <p className="text-xs text-slate-600 font-mono leading-relaxed mt-1">
            Save Session Snapshot, Restore Context, and Search Memory all require an active LiveKit
            session (agent must be in the room). Open the Session tab, connect, then use the
            Memory panel there.
          </p>
        </GlassCard>
      </div>
    </div>
  );
}
EOF

# ==============================================================================
# 59 · components/tools/WebFetchPanel.tsx
# Explicit operator-triggered fetch. Loopback blocked server-side.
# No JS execution. Nothing saved automatically.
# ==============================================================================
cat > components/tools/WebFetchPanel.tsx << 'EOF'
"use client";

import { useState } from "react";
import { GlassCard }     from "@/components/shared/GlassCard";
import { SectionHeader } from "@/components/shared/SectionHeader";
import { InlineAlert }   from "@/components/shared/InlineAlert";
import { Mono }          from "@/components/shared/Mono";
import { Globe, Search, X } from "lucide-react";
import { cn } from "@/lib/utils";

interface FetchResult {
  ok:           boolean;
  status?:      number;
  url?:         string;
  content_type?: string;
  size_bytes?:  number;
  truncated?:   boolean;
  text?:        string;
  error?:       string;
}

export function WebFetchPanel() {
  const [url,     setUrl]     = useState("");
  const [loading, setLoading] = useState(false);
  const [result,  setResult]  = useState<FetchResult | null>(null);

  async function doFetch() {
    const u = url.trim();
    if (!u || loading) return;
    setLoading(true);
    setResult(null);
    try {
      const res  = await fetch("/api/tools/webfetch", {
        method:  "POST",
        headers: { "Content-Type": "application/json" },
        body:    JSON.stringify({ url: u }),
      });
      setResult(await res.json() as FetchResult);
    } catch (err) {
      setResult({ ok: false, error: err instanceof Error ? err.message : String(err) });
    } finally {
      setLoading(false);
    }
  }

  function clear() {
    setResult(null);
    setUrl("");
  }

  return (
    <div className="h-full overflow-y-auto p-4">
      <div className="mx-auto max-w-3xl space-y-4">
        <GlassCard className="p-4 space-y-3">
          <SectionHeader
            icon={<Globe size={14} />}
            title="Safe Web Fetch"
            subtitle="explicit operator action · no autonomous browsing"
          />

          <div className="rounded-lg border border-amber-400/20 bg-amber-400/[0.04] px-3 py-2">
            <p className="text-xs text-amber-400/80 font-mono leading-relaxed">
              HTTP/HTTPS only. No JavaScript execution. Loopback addresses blocked server-side.
              Results shown here only — nothing saved automatically.
            </p>
          </div>

          <div className="flex gap-2">
            <input
              type="url"
              value={url}
              onChange={(e) => setUrl(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && doFetch()}
              placeholder="https://example.com"
              className="flex-1 rounded-md border border-white/[0.07] bg-black/30 px-3 py-2 text-xs text-slate-300 font-mono placeholder:text-slate-700 outline-none focus:border-cyan-400/40"
            />
            <button
              onClick={doFetch}
              disabled={!url.trim() || loading}
              className={cn(
                "flex items-center gap-1.5 shrink-0 rounded-md border px-3 py-2 text-xs font-medium transition-colors",
                url.trim() && !loading
                  ? "border-cyan-400/30 bg-cyan-400/10 text-cyan-400 hover:bg-cyan-400/15"
                  : "border-white/[0.05] text-slate-600 cursor-not-allowed",
              )}
            >
              <Search size={12} className={loading ? "animate-spin" : ""} />
              {loading ? "Fetching…" : "Fetch"}
            </button>
            {result && (
              <button
                onClick={clear}
                className="rounded-md border border-white/[0.07] px-2 py-2 text-slate-600 hover:text-slate-300 transition-colors"
              >
                <X size={12} />
              </button>
            )}
          </div>

          {result && !result.ok && (
            <InlineAlert kind="error" message={result.error ?? "Unknown error"} />
          )}

          {result?.ok && (
            <div className="space-y-2">
              <div className="rounded-lg border border-white/[0.05] bg-black/20 px-3 py-2 space-y-1.5">
                {(
                  [
                    ["URL",          result.url ?? "—",            "text-slate-300"],
                    ["Status",
                      String(result.status ?? "—"),
                      result.status && result.status < 400 ? "text-emerald-400" : "text-rose-400"],
                    ["Content-Type", result.content_type ?? "—",   "text-slate-400"],
                    ["Size",
                      result.size_bytes != null
                        ? `${result.size_bytes.toLocaleString()} bytes${result.truncated ? " (truncated to 512KB)" : ""}`
                        : "—",
                      "text-slate-400"],
                  ] as [string, string, string][]
                ).map(([label, value, valueClass]) => (
                  <div key={label} className="flex justify-between gap-3">
                    <Mono dim>{label}</Mono>
                    <Mono className={`${valueClass} truncate max-w-[280px] text-right`}>{value}</Mono>
                  </div>
                ))}
              </div>

              {result.text && (
                <div className="rounded-lg border border-white/[0.05] bg-black/20">
                  <div className="border-b border-white/[0.04] px-3 py-1.5">
                    <Mono dim>Response body</Mono>
                  </div>
                  <pre className="max-h-96 overflow-y-auto p-3 text-xs text-slate-400 font-mono whitespace-pre-wrap break-all leading-relaxed">
                    {result.text}
                  </pre>
                </div>
              )}
            </div>
          )}
        </GlassCard>
      </div>
    </div>
  );
}

export function ToolsTab() {
  return <WebFetchPanel />;
}
EOF

echo
echo "===== All 59 files written ====="
echo

npm install

echo
echo "╔══════════════════════════════════════════════════════╗"
echo "║   VoiceAI Dashboard v2 — build complete              ║"
echo "╚══════════════════════════════════════════════════════╝"
echo
echo "  ── Before starting ──────────────────────────────────"
echo "  1. Edit .env.local — add LiveKit credentials:"
echo "       LIVEKIT_API_KEY=devkey"
echo "       LIVEKIT_API_SECRET=devsecret"
echo "     (must match livekit.yaml in the voiceai backend)"
echo "  2. voiceai-ctl.sh start all"
echo "     voiceai-ctl.sh health"
echo
echo "  ── Start dev server ─────────────────────────────────"
echo "       cd voiceai-dashboard && npm run dev"
echo "       open http://localhost:3000"
echo
echo "  Tabs: Overview · Session · Personas · Services · Memory · Tools"
echo "  Secrets: server-side only · no NEXT_PUBLIC_* leakage"
echo "  Network: loopback-only · no 0.0.0.0 · no public URLs"
echo