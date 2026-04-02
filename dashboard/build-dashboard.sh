#!/usr/bin/env bash
# ==============================================================================
# build-dashboard.sh — VoiceAI Command Center v2
# Backend truth: bootstrap.sh + voiceai_ctl.sh
# One file = one block. No patches. No history. Final canonical state.
# ==============================================================================
set -euo pipefail

APP_NAME="voiceai-dashboard"
command -v node >/dev/null 2>&1 || { echo "ERROR: Node.js not found."; exit 1; }
command -v npm  >/dev/null 2>&1 || { echo "ERROR: npm not found.";     exit 1; }

echo
echo "╔══════════════════════════════════════════════════════╗"
echo "║   VoiceAI Command Center — Dashboard Builder v2      ║"
echo "╚══════════════════════════════════════════════════════╝"
echo "  Node: $(node --version)  npm: $(npm --version)"
echo

[ -d "$APP_NAME" ] && { echo "ERROR: '$APP_NAME' already exists. Remove it first."; exit 1; }

# ── Source env ────────────────────────────────────────────────────────────────
ENV_SH="$HOME/.config/voiceai/env.sh"
LIVEKIT_URL="ws://127.0.0.1:7880"; LIVEKIT_API_KEY=""; LIVEKIT_API_SECRET=""
VOICEAI_ROOT="$HOME/ai-projects/voiceai"
if [ -f "$ENV_SH" ]; then
  # shellcheck source=/dev/null
  . "$ENV_SH"; LIVEKIT_URL="${LIVEKIT_URL:-ws://127.0.0.1:7880}"
  echo "  [ENV] Sourced: $ENV_SH"
else
  echo "  [WARN] $ENV_SH not found — using defaults"
fi

mkdir -p "$APP_NAME" && cd "$APP_NAME"
mkdir -p \
  app/api/livekit/token app/api/tts/switch app/api/stt/switch \
  app/api/tools/webfetch app/api/personas 'app/api/personas/[name]' \
  'app/api/reference-audio/[voice]' \
  components/layout components/overview components/session \
  components/services components/memory components/tools \
  components/shared components/personas \
  hooks lib server
echo "  [DIR] Project tree ready"

# ==============================================================================
# 1 · package.json
# ==============================================================================
cat > package.json << 'EOF'
{
  "name": "voiceai-dashboard",
  "version": "0.2.0",
  "private": true,
  "scripts": { "dev":"next dev", "build":"next build", "start":"next start", "lint":"next lint" },
  "dependencies": {
    "@livekit/components-react": "^2.6.0",
    "@livekit/components-styles": "^1.1.2",
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
    "lib":["dom","dom.iterable","esnext"], "allowJs":true, "skipLibCheck":true,
    "strict":true, "noEmit":true, "esModuleInterop":true, "module":"esnext",
    "moduleResolution":"bundler", "resolveJsonModule":true, "isolatedModules":true,
    "jsx":"preserve", "incremental":true, "plugins":[{"name":"next"}],
    "paths":{"@/*":["./*"]}
  },
  "include":["next-env.d.ts","**/*.ts","**/*.tsx",".next/types/**/*.ts"],
  "exclude":["node_modules"]
}
EOF

# ==============================================================================
# 3 · next.config.js — proxy rewrites for all backend surfaces
# ==============================================================================
cat > next.config.js << 'EOF'
/** @type {import('next').NextConfig} */
const nextConfig = {
  async rewrites() {
    return [
      { source:"/api/proxy/tts/:path*",      destination:"http://127.0.0.1:5200/:path*" },
      { source:"/api/proxy/stt/:path*",       destination:"http://127.0.0.1:5100/:path*" },
      { source:"/api/proxy/llm/:path*",       destination:"http://127.0.0.1:5000/:path*" },
      { source:"/api/proxy/agent/:path*",     destination:"http://127.0.0.1:5800/:path*" },
      { source:"/api/proxy/telemetry/:path*", destination:"http://127.0.0.1:5900/:path*" },
      { source:"/api/proxy/qdrant/:path*",    destination:"http://127.0.0.1:6333/:path*" },
      { source:"/api/proxy/livekit/:path*",   destination:"http://127.0.0.1:7880/:path*" },
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
  content: ["./app/**/*.{ts,tsx}","./components/**/*.{ts,tsx}","./hooks/**/*.{ts,tsx}","./lib/**/*.{ts,tsx}","./server/**/*.{ts,tsx}"],
  theme: { extend: { colors:{ obsidian:"#080B0F" }, fontFamily:{ sans:["Inter Tight","ui-sans-serif","sans-serif"], mono:["JetBrains Mono","ui-monospace","monospace"] } } },
  plugins: [],
};
export default config;
EOF

# ==============================================================================
# 5 · postcss.config.js
# ==============================================================================
cat > postcss.config.js << 'EOF'
module.exports = { plugins: { tailwindcss:{}, autoprefixer:{} } };
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
# 8 · .env.local  (shell vars intentionally expanded)
# ==============================================================================
cat > .env.local << ENVEOF
# Server-side only. DO NOT commit.
LIVEKIT_URL=${LIVEKIT_URL}
LIVEKIT_API_KEY=${LIVEKIT_API_KEY}
LIVEKIT_API_SECRET=${LIVEKIT_API_SECRET}
VOICEAI_ROOT=${VOICEAI_ROOT}
ENVEOF

# ==============================================================================
# 9 · app/globals.css
# .meter-fill width driven by CSS custom property --mw (no inline width value)
# ==============================================================================
cat > app/globals.css << 'EOF'
@import url('https://fonts.googleapis.com/css2?family=Inter+Tight:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500;600&display=swap');

@tailwind base;
@tailwind components;
@tailwind utilities;

:root { color-scheme: dark; }
*, *::before, *::after { box-sizing: border-box; }
html, body { height:100%; background:#080B0F; color:#e2e8f0; font-family:'Inter Tight',sans-serif; -webkit-font-smoothing:antialiased; }
::-webkit-scrollbar { width:4px; height:4px; }
::-webkit-scrollbar-track { background:transparent; }
::-webkit-scrollbar-thumb { background:rgba(255,255,255,0.08); border-radius:99px; }
::-webkit-scrollbar-thumb:hover { background:rgba(255,255,255,0.16); }
button { font-family:inherit; }

/* ProgressBar: width set via CSS custom property, keeping inline style free of presentation values */
.meter-fill { width: var(--mw, 0%); }
EOF

# ==============================================================================
# 10 · app/layout.tsx
# ==============================================================================
cat > app/layout.tsx << 'EOF'
import type { Metadata } from "next";
import "./globals.css";
export const metadata: Metadata = { title:"VoiceAI Command Center", description:"Local AI Voice Orchestration Dashboard" };
export default function RootLayout({ children }: { children:React.ReactNode }) {
  return <html lang="en" className="h-full"><body className="h-full bg-[#080B0F] antialiased">{children}</body></html>;
}
EOF

# ==============================================================================
# 11 · app/page.tsx
# ==============================================================================
cat > app/page.tsx << 'EOF'
import { AppShell } from "@/components/layout/AppShell";
export default function Home() { return <AppShell />; }
EOF

# ==============================================================================
# 12 · app/api/livekit/token/route.ts
# Server-only. Fixed room=voice-room. Unique identity per request.
# canPublish=true so mic can be enabled later via explicit MicButton click.
# ==============================================================================
cat > app/api/livekit/token/route.ts << 'EOF'
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import { AccessToken }  from "livekit-server-sdk";
import { serverConfig } from "@/server/config";
import { LIVEKIT_ROOM } from "@/lib/constants";

export async function GET(): Promise<NextResponse> {
  const { livekitApiKey, livekitApiSecret, livekitUrl } = serverConfig;
  if (!livekitApiKey || !livekitApiSecret)
    return NextResponse.json({ error:"LiveKit credentials not configured. Set LIVEKIT_API_KEY and LIVEKIT_API_SECRET in .env.local." }, { status:500 });
  const identity = `dashboard-${Date.now()}-${Math.random().toString(36).slice(2,8)}`;
  const at = new AccessToken(livekitApiKey, livekitApiSecret, { identity, ttl:"4h" });
  at.addGrant({ roomJoin:true, room:LIVEKIT_ROOM, canPublish:true, canSubscribe:true, canPublishData:true });
  return NextResponse.json({ token: await at.toJwt(), url: livekitUrl });
}
EOF

# ==============================================================================
# 13 · app/api/tts/switch/route.ts
# ==============================================================================
cat > app/api/tts/switch/route.ts << 'EOF'
export const runtime = "nodejs";
import { NextRequest, NextResponse } from "next/server";
import { TTS_MODES, type TtsMode }   from "@/lib/types";

export async function POST(req: NextRequest): Promise<NextResponse> {
  let body: unknown;
  try { body = await req.json(); } catch { return NextResponse.json({ ok:false, message:"Invalid JSON" },{status:400}); }
  const { mode } = body as { mode?:string };
  if (!mode || !(TTS_MODES as readonly string[]).includes(mode))
    return NextResponse.json({ ok:false, message:`Invalid mode '${mode}'. Valid: ${TTS_MODES.join(", ")}` },{status:400});
  try {
    const up = await fetch("http://127.0.0.1:5200/admin/switch_model", {
      method:"POST", headers:{"Content-Type":"application/json"},
      body:JSON.stringify({ mode: mode as TtsMode }), signal:AbortSignal.timeout(10_000),
    });
    return NextResponse.json(await up.json().catch(()=>({})), { status:up.status });
  } catch (e) {
    return NextResponse.json({ ok:false, message:`TTS router unreachable: ${e instanceof Error?e.message:String(e)}` },{status:502});
  }
}
EOF

# ==============================================================================
# 14 · app/api/stt/switch/route.ts — atomic config.yml write
# ==============================================================================
cat > app/api/stt/switch/route.ts << 'EOF'
export const runtime = "nodejs";
import { NextRequest, NextResponse }                                    from "next/server";
import { readFileSync, writeFileSync, renameSync, existsSync, statSync, chmodSync } from "fs";
import { join }              from "path";
import yaml                  from "js-yaml";
import { STT_CANONICAL_MODELS } from "@/lib/types";
import { serverConfig }      from "@/server/config";

const CANONICAL = new Set<string>(STT_CANONICAL_MODELS);

export async function POST(req: NextRequest): Promise<NextResponse> {
  let body: unknown;
  try { body = await req.json(); } catch { return NextResponse.json({ ok:false, message:"Invalid JSON" },{status:400}); }
  const { model } = body as { model?:string };
  if (!model || !CANONICAL.has(model))
    return NextResponse.json({ ok:false, message:`Invalid model. Canonical: ${[...CANONICAL].join(", ")}` },{status:400});
  const cfgPath = join(serverConfig.voiceaiRoot, "stt","faster-whisper-service","config.yml");
  if (!existsSync(cfgPath))
    return NextResponse.json({ ok:false, message:`STT config.yml not found: ${cfgPath}` },{status:500});
  try {
    const cfg = yaml.load(readFileSync(cfgPath,"utf8")) as { model:{ model_name:string;[k:string]:unknown };[k:string]:unknown };
    if (!cfg?.model) return NextResponse.json({ ok:false, message:"Unexpected config.yml shape" },{status:500});
    const prev = cfg.model.model_name;
    cfg.model.model_name = model;
    const tmp = cfgPath+".tmp"; const mode = statSync(cfgPath).mode & 0o777;
    writeFileSync(tmp, yaml.dump(cfg,{lineWidth:-1}), {encoding:"utf8",mode});
    renameSync(tmp, cfgPath); chmodSync(cfgPath, mode);
    return NextResponse.json({ ok:true, message:`STT model: ${prev} → ${model}. watchfiles hot-reload in <1s.` });
  } catch (e) {
    return NextResponse.json({ ok:false, message:`Write failed: ${e instanceof Error?e.message:String(e)}` },{status:500});
  }
}
EOF

# ==============================================================================
# 15 · app/api/tools/webfetch/route.ts — loopback blocked server-side
# ==============================================================================
cat > app/api/tools/webfetch/route.ts << 'EOF'
export const runtime = "nodejs";
import { NextRequest, NextResponse } from "next/server";
import { safeUrl } from "@/lib/utils";

const BLOCKED = new Set(["localhost","127.0.0.1","0.0.0.0","::1","[::1]"]);

export async function POST(req: NextRequest): Promise<NextResponse> {
  let body: unknown;
  try { body = await req.json(); } catch { return NextResponse.json({ ok:false, error:"Invalid JSON" },{status:400}); }
  const { url } = body as { url?:string };
  if (!url) return NextResponse.json({ ok:false, error:"Missing url" },{status:400});
  const parsed = safeUrl(url);
  if (!parsed) return NextResponse.json({ ok:false, error:"Invalid URL (http/https only)" },{status:400});
  if (BLOCKED.has(parsed.hostname))
    return NextResponse.json({ ok:false, error:"Loopback/internal addresses not permitted" },{status:400});
  try {
    const res = await fetch(parsed.toString(), {
      headers:{"User-Agent":"VoiceAI-Dashboard/2.0 (operator tool)","Accept":"text/html,text/plain,application/json"},
      signal:AbortSignal.timeout(15_000), redirect:"follow",
    });
    const buf = new Uint8Array(await res.arrayBuffer());
    const truncated = buf.length > 512_000;
    const text = new TextDecoder("utf-8",{fatal:false}).decode(truncated ? buf.slice(0,512_000) : buf);
    return NextResponse.json({ ok:true, status:res.status, url:parsed.toString(),
      content_type:res.headers.get("content-type")??"", size_bytes:buf.length, truncated, text });
  } catch (e) {
    return NextResponse.json({ ok:false, error:`Fetch failed: ${e instanceof Error?e.message:String(e)}` },{status:502});
  }
}
EOF

# ==============================================================================
# 16 · app/api/personas/route.ts — list + create
# ==============================================================================
cat > app/api/personas/route.ts << 'EOF'
export const runtime = "nodejs";
import { NextResponse }                        from "next/server";
import { readdirSync, statSync, writeFileSync, existsSync } from "fs";
import { join, basename }                      from "path";
import { serverConfig }                        from "@/server/config";

const DIR = () => join(serverConfig.voiceaiRoot,"agent","personas");
const RE  = /^[a-zA-Z0-9_-]{1,64}$/;

export async function GET() {
  try {
    const dir = DIR();
    const files = existsSync(dir) ? readdirSync(dir).filter(f=>f.endsWith(".md")) : [];
    return NextResponse.json({ personas:files.map(f=>({ name:basename(f,".md"), filename:f, size_bytes:statSync(join(dir,f)).size })), count:files.length });
  } catch (e) { return NextResponse.json({ personas:[], count:0, error:String(e) }); }
}

export async function POST(req: Request) {
  const { name } = await req.json().catch(()=>({})) as { name?:string };
  if (!name || !RE.test(name))
    return NextResponse.json({ ok:false, message:"Invalid name (alphanumeric/dash/underscore, 1-64 chars)" },{status:400});
  const fp = join(DIR(),`${name}.md`);
  if (existsSync(fp)) return NextResponse.json({ ok:false, message:`'${name}' already exists` },{status:409});
  writeFileSync(fp,`---\ndisplay_name: ${name}\n---\n\nYou are a helpful AI assistant.\n`,"utf8");
  return NextResponse.json({ ok:true, message:`Created '${name}.md'` });
}
EOF

# ==============================================================================
# 17 · app/api/personas/[name]/route.ts — get / put / delete  (path-safe)
# ==============================================================================
cat > 'app/api/personas/[name]/route.ts' << 'EOF'
export const runtime = "nodejs";
import { NextRequest, NextResponse }                           from "next/server";
import { readFileSync, writeFileSync, unlinkSync, existsSync } from "fs";
import { join }         from "path";
import { serverConfig } from "@/server/config";

const RE = /^[a-zA-Z0-9_-]{1,64}$/;
const dir = () => join(serverConfig.voiceaiRoot,"agent","personas");
const fp  = (n:string) => join(dir(),`${n}.md`);
type Ctx  = { params:{ name:string } };

export async function GET(_:NextRequest, { params }:Ctx) {
  if (!RE.test(params.name)) return NextResponse.json({ ok:false, message:"Invalid name" },{status:400});
  if (!existsSync(fp(params.name))) return NextResponse.json({ ok:false, message:"Not found" },{status:404});
  return NextResponse.json({ ok:true, name:params.name, content:readFileSync(fp(params.name),"utf8") });
}

export async function PUT(req:NextRequest, { params }:Ctx) {
  if (!RE.test(params.name)) return NextResponse.json({ ok:false, message:"Invalid name" },{status:400});
  const { content } = await req.json().catch(()=>({})) as { content?:string };
  if (typeof content !== "string") return NextResponse.json({ ok:false, message:"Missing content" },{status:400});
  if (content.length > 65536)      return NextResponse.json({ ok:false, message:"Exceeds 64KB" },{status:400});
  writeFileSync(fp(params.name), content, "utf8");
  return NextResponse.json({ ok:true, message:`Saved '${params.name}.md'` });
}

export async function DELETE(_:NextRequest, { params }:Ctx) {
  if (!RE.test(params.name)) return NextResponse.json({ ok:false, message:"Invalid name" },{status:400});
  if (!existsSync(fp(params.name))) return NextResponse.json({ ok:false, message:"Not found" },{status:404});
  unlinkSync(fp(params.name));
  return NextResponse.json({ ok:true, message:`Deleted '${params.name}.md'` });
}
EOF

# ==============================================================================
# 18 · app/api/reference-audio/[voice]/route.ts
# Serves only from VOICEAI_ROOT/inputs/. Name regex prevents path traversal.
# ==============================================================================
cat > 'app/api/reference-audio/[voice]/route.ts' << 'EOF'
export const runtime = "nodejs";
import { NextRequest, NextResponse } from "next/server";
import { readFileSync, existsSync }  from "fs";
import { join }                      from "path";
import { serverConfig }              from "@/server/config";

const RE:RegExp = /^[a-zA-Z0-9_-]{1,64}$/;
const EXT:[string,string][] = [[".wav","audio/wav"],[".mp3","audio/mpeg"],[".flac","audio/flac"],[".ogg","audio/ogg"]];
type Ctx = { params:{ voice:string } };

export async function GET(_:NextRequest, { params }:Ctx) {
  if (!RE.test(params.voice)) return NextResponse.json({ error:"Invalid voice name" },{status:400});
  const base = join(serverConfig.voiceaiRoot,"inputs");
  for (const [ext,mime] of EXT) {
    const file = join(base,`${params.voice}${ext}`);
    if (existsSync(file)) {
      const buf = readFileSync(file);
      return new NextResponse(buf, { headers:{ "Content-Type":mime, "Content-Length":String(buf.length), "Cache-Control":"private, max-age=60" } });
    }
  }
  return NextResponse.json({ error:`'${params.voice}' not found in inputs/` },{status:404});
}
EOF

# ==============================================================================
# 19 · lib/types.ts
# ==============================================================================
cat > lib/types.ts << 'EOF'
export type ServiceStatus = "online"|"offline"|"degraded"|"unknown";

export type TtsMode = "customvoice"|"voicedesign"|"chatterbox";
export const TTS_MODES: readonly TtsMode[] = ["customvoice","voicedesign","chatterbox"];
export const TTS_MODE_LABELS: Record<TtsMode,string> = { customvoice:"CustomVoice", voicedesign:"VoiceDesign", chatterbox:"Chatterbox" };

export type RouterPhase = "idle"|"draining"|"terminating"|"vram_settling"|"spawning"|"probing"|"error";

export interface TtsHealth {
  active_mode:TtsMode|null; router_phase:RouterPhase; switching:boolean;
  worker_ready:boolean; last_error:string|null; inflight?:number;
  worker?:{ vram_total_gb?:number; vram_free_gb?:number };
}
export interface AgentHealth {
  status:string; uptime_s:number; session_active:boolean; room_name:string|null;
  persona:string; voice_mode:string; voice_speaker:string; voice_language:string;
  session_tokens:number|null; memory_enabled:boolean; last_checkpoint:number|null; last_error:string|null;
}
export interface LlmContext { online:boolean; model:string|null; max_seq_len:number|null; error?:string }

export const STT_CANONICAL_MODELS = [
  "faster-whisper-tiny","faster-whisper-tiny.en","faster-whisper-base","faster-whisper-base.en",
  "faster-whisper-small","faster-whisper-small.en","faster-whisper-medium","faster-whisper-medium.en",
] as const;
export type SttModel = typeof STT_CANONICAL_MODELS[number];

export interface GpuMetrics { util_percent:number; vram_total_gb:number; vram_free_gb:number; temp_c:number }
export interface MachineMetrics { cpu_percent:number; ram_percent:number; gpu?:GpuMetrics }
export interface QdrantCollectionStat { name:string; vectors_count:number }
export interface MemoryInventory { online:boolean; collections?:QdrantCollectionStat[]; error?:string }
export interface PersonaItem    { name:string; display_name:string; filename:string }
export interface ReferenceAudio { voice:string; filename:string; size_kb:number }
export interface SttModelItem   { name:string; canonical:boolean; files:number }
export interface SwitchResult   { ok:boolean; message:string }
EOF

# ==============================================================================
# 20 · lib/constants.ts
# ==============================================================================
cat > lib/constants.ts << 'EOF'
export const POLL = { FAST:3_000, NORMAL:5_000, SLOW:10_000 } as const;
export const LIVEKIT_ROOM = "voice-room" as const;
export const LANGUAGES = [
  { value:"en",label:"English" },{ value:"tr",label:"Turkish" },
  { value:"de",label:"German"  },{ value:"fr",label:"French"  },
  { value:"es",label:"Spanish" },{ value:"ja",label:"Japanese"},
  { value:"zh",label:"Chinese" },{ value:"ko",label:"Korean"  },
] as const;
export const INTERRUPTION_MODES = [
  { value:"patient",label:"Patient" },{ value:"normal",label:"Normal" },{ value:"responsive",label:"Responsive" },
] as const;
EOF

# ==============================================================================
# 21 · lib/utils.ts
# ==============================================================================
cat > lib/utils.ts << 'EOF'
import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) { return twMerge(clsx(inputs)); }

export function formatUptime(s:number): string {
  if (!s||s<0) return "—";
  const h=Math.floor(s/3600),m=Math.floor((s%3600)/60),sec=Math.floor(s%60);
  if (h>0) return `${h}h ${m}m`; if (m>0) return `${m}m ${sec}s`; return `${sec}s`;
}

export function formatVram(total?:number, free?:number): string {
  if (total==null||free==null) return "—";
  return `${Math.max(0,total-free).toFixed(1)} / ${total.toFixed(1)} GB`;
}

export function safeUrl(raw:string): URL|null {
  try { const u=new URL(raw); if (u.protocol!=="https:"&&u.protocol!=="http:") return null; return u; }
  catch { return null; }
}
EOF

# ==============================================================================
# 22 · server/config.ts — server-only; never import from client components
# ==============================================================================
cat > server/config.ts << 'EOF'
function opt(k:string, fb:string) { return process.env[k]??fb; }
export const serverConfig = {
  livekitUrl:       opt("LIVEKIT_URL",       "ws://127.0.0.1:7880"),
  livekitApiKey:    opt("LIVEKIT_API_KEY",    ""),
  livekitApiSecret: opt("LIVEKIT_API_SECRET", ""),
  voiceaiRoot:      opt("VOICEAI_ROOT", `${process.env.HOME??""}/ai-projects/voiceai`),
} as const;
EOF

# ==============================================================================
# 23 · hooks/usePoll.ts
# ==============================================================================
cat > hooks/usePoll.ts << 'EOF'
"use client";
import { useState, useEffect, useCallback, useRef } from "react";
export interface PollState<T> { data:T|null; error:string|null; loading:boolean; refetch:()=>void }
export function usePoll<T>(fetcher:()=>Promise<T>, interval:number): PollState<T> {
  const [data,setData]=useState<T|null>(null);
  const [error,setError]=useState<string|null>(null);
  const [loading,setLoading]=useState(true);
  const ref=useRef(fetcher); ref.current=fetcher;
  const run=useCallback(async()=>{
    try { const r=await ref.current(); setData(r); setError(null); }
    catch(e) { setError(e instanceof Error?e.message:String(e)); }
    finally  { setLoading(false); }
  },[]);
  useEffect(()=>{ run(); const id=setInterval(run,interval); return ()=>clearInterval(id); },[run,interval]);
  return { data, error, loading, refetch:run };
}
EOF

# ==============================================================================
# 24 · hooks/useLiveClock.ts
# ==============================================================================
cat > hooks/useLiveClock.ts << 'EOF'
"use client";
import { useState, useEffect } from "react";
const fmt=(d:Date)=>d.toLocaleTimeString("en-US",{hour12:false,hour:"2-digit",minute:"2-digit",second:"2-digit"});
export function useLiveClock():string {
  const [t,setT]=useState(()=>fmt(new Date()));
  useEffect(()=>{ const id=setInterval(()=>setT(fmt(new Date())),1000); return ()=>clearInterval(id); },[]);
  return t;
}
EOF

# ==============================================================================
# 25–30 · Data hooks
# ==============================================================================
cat > hooks/useAgentState.ts << 'EOF'
"use client";
import { usePoll } from "./usePoll"; import { POLL } from "@/lib/constants"; import type { AgentHealth } from "@/lib/types";
const fetch_ = ()=>fetch("/api/proxy/agent/health",{cache:"no-store"}).then(r=>{ if(!r.ok)throw new Error(`HTTP ${r.status}`); return r.json() as Promise<AgentHealth>; });
export function useAgentState() { return usePoll<AgentHealth>(fetch_, POLL.NORMAL); }
EOF

cat > hooks/useTtsState.ts << 'EOF'
"use client";
import { usePoll } from "./usePoll"; import { POLL } from "@/lib/constants"; import type { TtsHealth } from "@/lib/types";
const fetch_ = ()=>fetch("/api/proxy/tts/health",{cache:"no-store"}).then(r=>{ if(!r.ok)throw new Error(`HTTP ${r.status}`); return r.json() as Promise<TtsHealth>; });
export function useTtsState() { return usePoll<TtsHealth>(fetch_, POLL.FAST); }
EOF

cat > hooks/useMachineMetrics.ts << 'EOF'
"use client";
import { usePoll } from "./usePoll"; import { POLL } from "@/lib/constants"; import type { MachineMetrics } from "@/lib/types";
const fetch_ = ()=>fetch("/api/proxy/telemetry/metrics/machine",{cache:"no-store"}).then(r=>{ if(!r.ok)throw new Error(`HTTP ${r.status}`); return r.json() as Promise<MachineMetrics>; });
export function useMachineMetrics() { return usePoll<MachineMetrics>(fetch_, POLL.SLOW); }
EOF

cat > hooks/useLlmContext.ts << 'EOF'
"use client";
import { usePoll } from "./usePoll"; import { POLL } from "@/lib/constants"; import type { LlmContext } from "@/lib/types";
const fetch_ = ()=>fetch("/api/proxy/telemetry/inventory/context",{cache:"no-store"}).then(r=>{ if(!r.ok)throw new Error(`HTTP ${r.status}`); return r.json() as Promise<LlmContext>; });
export function useLlmContext() { return usePoll<LlmContext>(fetch_, POLL.SLOW); }
EOF

cat > hooks/useSttInventory.ts << 'EOF'
"use client";
import { usePoll } from "./usePoll"; import { POLL } from "@/lib/constants"; import type { SttModelItem } from "@/lib/types";
interface SttInv { models:SttModelItem[]; count:number }
const fetch_ = ()=>fetch("/api/proxy/telemetry/inventory/models/stt",{cache:"no-store"}).then(r=>{ if(!r.ok)throw new Error(`HTTP ${r.status}`); return r.json() as Promise<SttInv>; });
export function useSttInventory() { return usePoll<SttInv>(fetch_, POLL.SLOW); }
EOF

cat > hooks/useInventory.ts << 'EOF'
"use client";
import { usePoll } from "./usePoll"; import { POLL } from "@/lib/constants";
import type { PersonaItem, ReferenceAudio } from "@/lib/types";
interface PersonaInv { personas:PersonaItem[]; count:number }
interface AudioInv   { voices:ReferenceAudio[];  count:number }
const fp = ()=>fetch("/api/proxy/telemetry/inventory/personas",{cache:"no-store"}).then(r=>{ if(!r.ok)throw new Error(`HTTP ${r.status}`); return r.json() as Promise<PersonaInv>; });
const fa = ()=>fetch("/api/proxy/telemetry/inventory/reference-audio",{cache:"no-store"}).then(r=>{ if(!r.ok)throw new Error(`HTTP ${r.status}`); return r.json() as Promise<AudioInv>; });
export function usePersonaInventory() { return usePoll<PersonaInv>(fp, POLL.SLOW); }
export function useAudioInventory()   { return usePoll<AudioInv>(fa,   POLL.SLOW); }
EOF

# ==============================================================================
# 31 · components/shared/GlassCard.tsx
# ==============================================================================
cat > components/shared/GlassCard.tsx << 'EOF'
"use client";
import { cn } from "@/lib/utils"; import type { ReactNode } from "react";
export function GlassCard({ children, className }:{ children:ReactNode; className?:string }) {
  return <div className={cn("rounded-xl border border-white/[0.07] bg-black/20 backdrop-blur-sm",className)}>{children}</div>;
}
EOF

# ==============================================================================
# 32 · components/shared/StatusDot.tsx
# ==============================================================================
cat > components/shared/StatusDot.tsx << 'EOF'
"use client";
import { cn } from "@/lib/utils"; import type { ServiceStatus } from "@/lib/types";
const DOT:Record<ServiceStatus,string> = { online:"bg-emerald-400 shadow-[0_0_6px_rgba(52,211,153,0.55)]", offline:"bg-rose-400", degraded:"bg-amber-400", unknown:"bg-slate-600" };
const LBL:Record<ServiceStatus,string> = { online:"text-emerald-400", offline:"text-rose-400", degraded:"text-amber-400", unknown:"text-slate-500" };
export function StatusDot({ status, showLabel=false, size="sm" }:{ status:ServiceStatus; showLabel?:boolean; size?:"sm"|"md" }) {
  return (
    <span className="flex items-center gap-1.5">
      <span className={cn("rounded-full shrink-0",size==="sm"?"h-1.5 w-1.5":"h-2 w-2",DOT[status])}/>
      {showLabel && <span className={cn("font-mono text-xs uppercase tracking-wider",LBL[status])}>{status}</span>}
    </span>
  );
}
EOF

# ==============================================================================
# 33 · components/shared/Mono.tsx
# ==============================================================================
cat > components/shared/Mono.tsx << 'EOF'
"use client";
import { cn } from "@/lib/utils"; import type { ReactNode } from "react";
export function Mono({ children, className, dim=false }:{ children:ReactNode; className?:string; dim?:boolean }) {
  return <span className={cn("font-mono text-xs tracking-wide",dim?"text-slate-600":"text-slate-400",className)}>{children}</span>;
}
EOF

# ==============================================================================
# 34 · components/shared/SectionHeader.tsx
# ==============================================================================
cat > components/shared/SectionHeader.tsx << 'EOF'
"use client";
import { cn } from "@/lib/utils"; import type { ReactNode } from "react";
interface Props { icon?:ReactNode; title:string; subtitle?:string; action?:ReactNode; className?:string }
export function SectionHeader({ icon, title, subtitle, action, className }:Props) {
  return (
    <div className={cn("flex items-center justify-between mb-3",className)}>
      <div className="flex items-center gap-2">
        {icon && <span className="text-cyan-400 shrink-0">{icon}</span>}
        <div>
          <h3 className="text-slate-200 font-semibold text-sm leading-none">{title}</h3>
          {subtitle && <p className="text-slate-600 text-xs mt-0.5 font-mono">{subtitle}</p>}
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
import { AlertCircle, CheckCircle2, Info } from "lucide-react"; import { cn } from "@/lib/utils";
type Kind="error"|"success"|"info"|"warning";
const S:Record<Kind,{bar:string;icon:string}> = {
  error:  {bar:"border-rose-400/30 bg-rose-400/10",    icon:"text-rose-400"    },
  success:{bar:"border-emerald-400/30 bg-emerald-400/10",icon:"text-emerald-400"},
  info:   {bar:"border-cyan-400/30 bg-cyan-400/10",    icon:"text-cyan-400"    },
  warning:{bar:"border-amber-400/30 bg-amber-400/10",  icon:"text-amber-400"   },
};
const ICO:Record<Kind,typeof AlertCircle> = { error:AlertCircle, success:CheckCircle2, info:Info, warning:AlertCircle };
export function InlineAlert({ kind, message, className }:{ kind:Kind; message:string; className?:string }) {
  const {bar,icon}=S[kind]; const Icon=ICO[kind];
  return (
    <div className={cn("flex items-start gap-2 rounded-lg border px-3 py-2",bar,className)}>
      <Icon size={13} className={cn("shrink-0 mt-0.5",icon)}/>
      <span className="font-mono text-xs text-slate-300 leading-relaxed break-all">{message}</span>
    </div>
  );
}
EOF

# ==============================================================================
# 36 · components/shared/ProgressBar.tsx
# Width via CSS custom property --mw. No inline width value.
# ==============================================================================
cat > components/shared/ProgressBar.tsx << 'EOF'
"use client";
import { cn } from "@/lib/utils";
export function ProgressBar({ value, accentClass="bg-cyan-400" }:{ value:number; accentClass?:string }) {
  return (
    <div className="h-1 rounded-full bg-white/[0.06] overflow-hidden">
      <div className={cn("meter-fill h-full rounded-full transition-all duration-700",accentClass)}
           style={{"--mw":`${Math.min(100,Math.max(0,value))}%`} as React.CSSProperties}/>
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

export type NavTab = "overview"|"session"|"personas"|"services"|"memory"|"tools";

const TABS = [
  { id:"overview"  as NavTab, label:"Overview",  Icon:LayoutDashboard },
  { id:"session"   as NavTab, label:"Session",   Icon:Radio           },
  { id:"personas"  as NavTab, label:"Personas",  Icon:Users           },
  { id:"services"  as NavTab, label:"Services",  Icon:Layers          },
  { id:"memory"    as NavTab, label:"Memory",    Icon:Database        },
  { id:"tools"     as NavTab, label:"Tools",     Icon:Globe           },
];

interface Props { active:NavTab; onChange:(t:NavTab)=>void }

export function NavBar({ active, onChange }:Props) {
  return (
    <nav className="flex items-center gap-1 px-2">
      {TABS.map(({id,label,Icon})=>{
        const on=active===id;
        return (
          <button key={id} onClick={()=>onChange(id)}
            className={cn("flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-all",
              on?"bg-cyan-400/10 text-cyan-400 border border-cyan-400/20":"text-slate-500 hover:text-slate-300 hover:bg-white/[0.04]")}>
            <Icon size={13}/><span className="hidden sm:inline">{label}</span>
          </button>
        );
      })}
    </nav>
  );
}

export function BottomNav({ active, onChange }:Props) {
  return (
    <nav className="flex items-stretch border-t border-white/[0.07] bg-black/60 backdrop-blur-md">
      {TABS.map(({id,label,Icon})=>{
        const on=active===id;
        return (
          <button key={id} onClick={()=>onChange(id)}
            className={cn("flex flex-1 flex-col items-center gap-0.5 py-1.5 text-[9px] font-medium transition-colors",on?"text-cyan-400":"text-slate-600")}>
            <Icon size={16}/>{label}
          </button>
        );
      })}
    </nav>
  );
}
EOF

# ==============================================================================
# 38 · components/layout/AppShell.tsx — all 6 tabs wired
# ==============================================================================
cat > components/layout/AppShell.tsx << 'EOF'
"use client";
import { useState }     from "react";
import { Cpu, Clock }   from "lucide-react";
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
  const [tab,setTab]=useState<NavTab>("overview");
  const clock=useLiveClock();
  return (
    <div className="flex h-full flex-col bg-[#080B0F]">
      <header className="flex shrink-0 items-center justify-between border-b border-white/[0.07] bg-black/30 backdrop-blur-md px-4 py-2.5">
        <div className="flex items-center gap-2">
          <Cpu size={16} className="text-cyan-400"/>
          <span className="text-sm font-semibold text-slate-200 tracking-tight">VoiceAI</span>
          <Mono dim>Command Center</Mono>
        </div>
        <div className="hidden md:flex"><NavBar active={tab} onChange={setTab}/></div>
        <div className="hidden sm:flex items-center gap-1.5"><Clock size={12} className="text-slate-700"/><Mono dim>{clock}</Mono></div>
      </header>
      <main className="flex-1 overflow-hidden">
        {tab==="overview"  && <OverviewTab />}
        {tab==="session"   && <SessionTab  />}
        {tab==="personas"  && <PersonasTab />}
        {tab==="services"  && <ServicesTab />}
        {tab==="memory"    && <MemoryTab   />}
        {tab==="tools"     && <ToolsTab    />}
      </main>
      <div className="flex md:hidden shrink-0"><BottomNav active={tab} onChange={setTab}/></div>
    </div>
  );
}
EOF

# ==============================================================================
# 39 · components/overview/ServiceHealthRow.tsx — independent poll per service
# ==============================================================================
cat > components/overview/ServiceHealthRow.tsx << 'EOF'
"use client";
import { usePoll } from "@/hooks/usePoll"; import { StatusDot } from "@/components/shared/StatusDot";
import { Mono } from "@/components/shared/Mono"; import { POLL } from "@/lib/constants";
import type { ServiceStatus } from "@/lib/types";

const SVCS=[
  { label:"LiveKit",   url:"/api/proxy/livekit/health",            port:7880 },
  { label:"LLM",       url:"/api/proxy/llm/v1/models",             port:5000 },
  { label:"STT",       url:"/api/proxy/stt/health",                port:5100 },
  { label:"TTS",       url:"/api/proxy/tts/health",                port:5200 },
  { label:"Qdrant",    url:"/api/proxy/qdrant/",                   port:6333 },
  { label:"Telemetry", url:"/api/proxy/telemetry/health",          port:5900 },
  { label:"Agent",     url:"/api/proxy/agent/health",              port:5800 },
] as const;

interface Row { status:ServiceStatus; latency:number }
function chip(url:string) {
  return async():Promise<Row>=>{
    const t0=performance.now(); const res=await fetch(url,{cache:"no-store",signal:AbortSignal.timeout(3_000)});
    return { status:res.ok?"online":"degraded", latency:Math.round(performance.now()-t0) };
  };
}

function ServiceChip({ svc }:{ svc:typeof SVCS[number] }) {
  const { data, loading }=usePoll<Row>(chip(svc.url), POLL.NORMAL);
  const status:ServiceStatus=loading?"unknown":(data?.status??"offline");
  return (
    <div className="flex items-center justify-between rounded-lg border border-white/[0.05] bg-black/15 px-3 py-2.5">
      <div className="flex items-center gap-2"><StatusDot status={status}/><span className="text-xs font-medium text-slate-300">{svc.label}</span></div>
      <div className="flex items-center gap-2">{data?.latency!=null&&<Mono dim>{data.latency}ms</Mono>}<Mono dim>{svc.port}</Mono></div>
    </div>
  );
}

export function ServiceGrid() {
  return (
    <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-1 xl:grid-cols-2">
      {SVCS.map(s=><ServiceChip key={s.label} svc={s}/>)}
    </div>
  );
}
EOF

# ==============================================================================
# 40 · components/overview/MachineCard.tsx
# Single Meter function using ProgressBar (CSS custom property width).
# No inline width values remain anywhere in this file.
# ==============================================================================
cat > components/overview/MachineCard.tsx << 'EOF'
"use client";
import { useMachineMetrics } from "@/hooks/useMachineMetrics";
import { GlassCard }         from "@/components/shared/GlassCard";
import { SectionHeader }     from "@/components/shared/SectionHeader";
import { ProgressBar }       from "@/components/shared/ProgressBar";
import { Mono }              from "@/components/shared/Mono";
import { Cpu }               from "lucide-react";
import { cn }                from "@/lib/utils";

function Meter({ label, value, accentClass="bg-cyan-400" }:{ label:string; value:number; accentClass?:string }) {
  const c=Math.min(100,Math.max(0,value)); const hot=c>85;
  return (
    <div className="space-y-1">
      <div className="flex items-center justify-between">
        <Mono dim>{label}</Mono>
        <Mono className={hot?"text-amber-400":"text-slate-400"}>{c.toFixed(0)}%</Mono>
      </div>
      <ProgressBar value={c} accentClass={hot?"bg-amber-400":accentClass}/>
    </div>
  );
}

export function MachineCard() {
  const { data, error, loading }=useMachineMetrics();
  return (
    <GlassCard className="p-4">
      <SectionHeader icon={<Cpu size={14}/>} title="Machine" subtitle="10s refresh"/>
      {loading && <p className="text-xs text-slate-600 font-mono">Loading…</p>}
      {error   && <p className="text-xs text-rose-400 font-mono">{error}</p>}
      {data && (
        <div className="space-y-3 mt-2">
          <Meter label="CPU" value={data.cpu_percent}/>
          <Meter label="RAM" value={data.ram_percent} accentClass="bg-violet-400"/>
          {data.gpu && (
            <>
              <Meter label="GPU util" value={data.gpu.util_percent} accentClass="bg-amber-400"/>
              <Meter label="VRAM" accentClass="bg-rose-400"
                value={Math.round(((data.gpu.vram_total_gb-data.gpu.vram_free_gb)/data.gpu.vram_total_gb)*100)}/>
              <div className="flex items-center justify-between pt-0.5">
                <Mono dim>VRAM used</Mono>
                <Mono>{(data.gpu.vram_total_gb-data.gpu.vram_free_gb).toFixed(1)}&nbsp;/&nbsp;{data.gpu.vram_total_gb.toFixed(1)} GB</Mono>
              </div>
              <div className="flex items-center justify-between">
                <Mono dim>GPU temp</Mono>
                <Mono className={data.gpu.temp_c>80?"text-rose-400":"text-slate-400"}>{data.gpu.temp_c}°C</Mono>
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
import { ServiceGrid } from "./ServiceHealthRow"; import { MachineCard } from "./MachineCard";
import { GlassCard } from "@/components/shared/GlassCard"; import { SectionHeader } from "@/components/shared/SectionHeader";
import { Server } from "lucide-react";
export function OverviewTab() {
  return (
    <div className="h-full overflow-y-auto p-4">
      <div className="mx-auto max-w-5xl">
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <div className="lg:col-span-2">
            <GlassCard className="p-4"><SectionHeader icon={<Server size={14}/>} title="Services" subtitle="5s refresh"/><ServiceGrid/></GlassCard>
          </div>
          <MachineCard/>
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
import { GlassCard } from "@/components/shared/GlassCard"; import { SectionHeader } from "@/components/shared/SectionHeader";
import { StatusDot } from "@/components/shared/StatusDot"; import { Mono } from "@/components/shared/Mono";
import { Brain } from "lucide-react";
export function LlmCard() {
  const { data, error, loading }=useLlmContext();
  return (
    <GlassCard className="p-4 space-y-3">
      <SectionHeader icon={<Brain size={14}/>} title="LLM" subtitle="127.0.0.1:5000 · TabbyAPI"/>
      {loading && <p className="text-xs text-slate-600 font-mono">Querying…</p>}
      {error   && <p className="text-xs text-rose-400 font-mono">{error}</p>}
      {data && (
        <>
          <StatusDot status={data.online?"online":"offline"} showLabel/>
          {data.online && (
            <div className="rounded-lg border border-white/[0.05] bg-black/20 px-3 py-2 space-y-1.5">
              {data.model && <div className="flex justify-between gap-3"><Mono dim>Model</Mono><Mono className="text-slate-300 text-right break-all">{data.model}</Mono></div>}
              {data.max_seq_len!=null && <div className="flex justify-between"><Mono dim>Context ceiling</Mono><Mono className="text-slate-300">{data.max_seq_len.toLocaleString()} tokens</Mono></div>}
            </div>
          )}
          {!data.online && <p className="text-xs text-slate-600 font-mono">{data.error??"LLM not responding on port 5000"}</p>}
        </>
      )}
    </GlassCard>
  );
}
EOF

# ==============================================================================
# 43 · components/services/SttCard.tsx — global switch, amber admin section
# ==============================================================================
cat > components/services/SttCard.tsx << 'EOF'
"use client";
import { useState } from "react";
import { usePoll } from "@/hooks/usePoll"; import { useSttInventory } from "@/hooks/useSttInventory";
import { GlassCard } from "@/components/shared/GlassCard"; import { SectionHeader } from "@/components/shared/SectionHeader";
import { StatusDot } from "@/components/shared/StatusDot"; import { Mono } from "@/components/shared/Mono";
import { InlineAlert } from "@/components/shared/InlineAlert";
import { Mic, RefreshCw } from "lucide-react";
import { STT_CANONICAL_MODELS } from "@/lib/types"; import type { SwitchResult } from "@/lib/types";
import { POLL } from "@/lib/constants"; import { cn } from "@/lib/utils";

interface SttHealth { model?:string }
const fetchHealth=()=>fetch("/api/proxy/stt/health",{cache:"no-store"}).then(r=>{ if(!r.ok)throw new Error(`HTTP ${r.status}`); return r.json() as Promise<SttHealth>; });

export function SttCard() {
  const health=usePoll<SttHealth>(fetchHealth, POLL.NORMAL);
  const inv=useSttInventory();
  const [sel,setSel]=useState(""); const [busy,setBusy]=useState(false); const [res,setRes]=useState<SwitchResult|null>(null);

  async function apply() {
    if (!sel||busy) return; setBusy(true); setRes(null);
    try {
      const r=await fetch("/api/stt/switch",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({model:sel})});
      const d=await r.json() as SwitchResult; setRes(d); if(d.ok){ health.refetch(); setSel(""); }
    } catch(e){ setRes({ok:false,message:e instanceof Error?e.message:String(e)}); }
    finally { setBusy(false); }
  }

  return (
    <GlassCard className="p-4 space-y-3">
      <SectionHeader icon={<Mic size={14}/>} title="STT" subtitle="127.0.0.1:5100 · Faster-Whisper"/>
      {health.loading && <p className="text-xs text-slate-600 font-mono">Checking…</p>}
      {health.error   && <p className="text-xs text-rose-400 font-mono">{health.error}</p>}
      {!health.loading && <StatusDot status={health.error?"offline":"online"} showLabel/>}
      <div className="rounded-lg border border-white/[0.05] bg-black/20 px-3 py-2 space-y-1.5">
        <div className="flex justify-between"><Mono dim>Active model</Mono><Mono className="text-slate-300">{health.data?.model??"—"}</Mono></div>
        {inv.data && <div className="flex justify-between"><Mono dim>Models on disk</Mono><Mono className="text-slate-300">{inv.data.count}</Mono></div>}
      </div>
      <div className="rounded-lg border border-amber-400/15 bg-amber-400/[0.03] p-3 space-y-2">
        <Mono className="text-amber-400/80">⚙ Global STT model switch</Mono>
        <p className="text-xs text-slate-700 font-mono">Writes config.yml atomically. watchfiles hot-reloads in &lt;1s. Affects all sessions.</p>
        <select value={sel} onChange={e=>setSel(e.target.value)}
          className="w-full rounded-md border border-white/[0.07] bg-black/30 px-2 py-1.5 text-xs text-slate-300 font-mono outline-none focus:border-cyan-400/40">
          <option value="">— select model —</option>
          {STT_CANONICAL_MODELS.map(m=><option key={m} value={m}>{m}</option>)}
        </select>
        <button onClick={apply} disabled={!sel||busy}
          className={cn("flex items-center gap-1.5 rounded-md border px-3 py-1.5 text-xs font-medium w-full justify-center transition-colors",
            sel&&!busy?"border-cyan-400/30 bg-cyan-400/10 text-cyan-400 hover:bg-cyan-400/15":"border-white/[0.05] text-slate-600 cursor-not-allowed")}>
          <RefreshCw size={12} className={busy?"animate-spin":""}/>{busy?"Switching…":"Apply Model"}
        </button>
        {res && <InlineAlert kind={res.ok?"success":"error"} message={res.message}/>}
      </div>
    </GlassCard>
  );
}
EOF

# ==============================================================================
# 44 · components/services/TtsCard.tsx — global switch, amber admin section
# ==============================================================================
cat > components/services/TtsCard.tsx << 'EOF'
"use client";
import { useState } from "react";
import { useTtsState } from "@/hooks/useTtsState";
import { GlassCard } from "@/components/shared/GlassCard"; import { SectionHeader } from "@/components/shared/SectionHeader";
import { Mono } from "@/components/shared/Mono"; import { InlineAlert } from "@/components/shared/InlineAlert";
import { Volume2, ArrowRight } from "lucide-react";
import { TTS_MODES, TTS_MODE_LABELS } from "@/lib/types"; import type { TtsMode, SwitchResult } from "@/lib/types";
import { cn, formatVram } from "@/lib/utils";

const PHASE_CLR:Record<string,string>={ idle:"text-emerald-400",draining:"text-amber-400",terminating:"text-amber-400",vram_settling:"text-violet-400",spawning:"text-violet-400",probing:"text-cyan-400",error:"text-rose-400" };

export function TtsCard() {
  const { data,error,loading,refetch }=useTtsState();
  const [sel,setSel]=useState<TtsMode|"">("");
  const [busy,setBusy]=useState(false); const [res,setRes]=useState<SwitchResult|null>(null);

  async function doSwitch() {
    if (!sel||busy) return;
    if (data?.active_mode===sel&&!data?.switching){ setRes({ok:false,message:`'${TTS_MODE_LABELS[sel]}' is already active.`}); return; }
    setBusy(true); setRes(null);
    try {
      const r=await fetch("/api/tts/switch",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({mode:sel})});
      const d=await r.json() as SwitchResult; setRes(d); if(r.ok) refetch();
    } catch(e){ setRes({ok:false,message:e instanceof Error?e.message:String(e)}); }
    finally { setBusy(false); }
  }

  return (
    <GlassCard className="p-4 space-y-3">
      <SectionHeader icon={<Volume2 size={14}/>} title="TTS Router" subtitle="127.0.0.1:5200"/>
      {loading && <p className="text-xs text-slate-600 font-mono">Checking…</p>}
      {error   && <p className="text-xs text-rose-400 font-mono">{error}</p>}
      {data && (
        <>
          <div className="rounded-lg border border-white/[0.05] bg-black/20 px-3 py-2 space-y-1.5">
            <div className="flex justify-between"><Mono dim>Engine</Mono><Mono className="text-slate-300">{data.active_mode?TTS_MODE_LABELS[data.active_mode]:"none"}</Mono></div>
            <div className="flex justify-between"><Mono dim>Phase</Mono><Mono className={PHASE_CLR[data.router_phase]??"text-slate-400"}>{data.router_phase}</Mono></div>
            <div className="flex justify-between"><Mono dim>Worker</Mono><Mono className={data.worker_ready?"text-emerald-400":"text-slate-500"}>{data.worker_ready?"ready":"not ready"}</Mono></div>
            {data.switching && <div className="flex justify-between"><Mono dim>Switching</Mono><Mono className="text-violet-400 animate-pulse">in progress…</Mono></div>}
            {data.worker?.vram_total_gb!=null && <div className="flex justify-between"><Mono dim>VRAM</Mono><Mono className="text-slate-300">{formatVram(data.worker.vram_total_gb,data.worker.vram_free_gb)}</Mono></div>}
            {data.last_error && <div className="flex justify-between gap-2"><Mono dim>Last error</Mono><Mono className="text-rose-400 truncate max-w-[180px]">{data.last_error}</Mono></div>}
          </div>
          {!data.active_mode&&!data.switching && <InlineAlert kind="info" message="No engine loaded. Select one below to load it."/>}
          <div className="rounded-lg border border-amber-400/15 bg-amber-400/[0.03] p-3 space-y-2">
            <Mono className="text-amber-400/80">⚙ Global TTS engine switch</Mono>
            <p className="text-xs text-slate-700 font-mono">Drains VRAM from current engine, spawns the new one. Affects all sessions.</p>
            <div className="grid grid-cols-3 gap-1.5">
              {TTS_MODES.map(m=>(
                <button key={m} onClick={()=>setSel(m)}
                  className={cn("rounded-md border px-2 py-1.5 text-xs font-mono transition-colors",
                    sel===m?"border-cyan-400/40 bg-cyan-400/10 text-cyan-400":"border-white/[0.06] bg-black/20 text-slate-500 hover:text-slate-300")}>
                  {TTS_MODE_LABELS[m]}
                </button>
              ))}
            </div>
            <button onClick={doSwitch} disabled={!sel||busy}
              className={cn("flex items-center gap-1.5 justify-center w-full rounded-md border px-3 py-1.5 text-xs font-medium transition-colors",
                sel&&!busy?"border-cyan-400/30 bg-cyan-400/10 text-cyan-400 hover:bg-cyan-400/15":"border-white/[0.05] text-slate-600 cursor-not-allowed")}>
              <ArrowRight size={12} className={busy?"animate-pulse":""}/>{busy?"Switching…":"Switch Engine"}
            </button>
            {res && <InlineAlert kind={res.ok?"success":"error"} message={res.message}/>}
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
import { GlassCard } from "@/components/shared/GlassCard"; import { SectionHeader } from "@/components/shared/SectionHeader";
import { StatusDot } from "@/components/shared/StatusDot"; import { Mono } from "@/components/shared/Mono";
import { Radio } from "lucide-react"; import { formatUptime } from "@/lib/utils";
export function AgentCard() {
  const { data,error,loading }=useAgentState();
  return (
    <GlassCard className="p-4 space-y-3">
      <SectionHeader icon={<Radio size={14}/>} title="Agent" subtitle="127.0.0.1:5800"/>
      {loading && <p className="text-xs text-slate-600 font-mono">Checking…</p>}
      {error   && <p className="text-xs text-rose-400 font-mono">{error}</p>}
      {data && (
        <>
          <div className="flex items-center gap-3">
            <StatusDot status={data.status==="ok"?"online":"degraded"} showLabel/>
            {data.uptime_s>0 && <Mono dim>up {formatUptime(data.uptime_s)}</Mono>}
          </div>
          <div className="rounded-lg border border-white/[0.05] bg-black/20 px-3 py-2 space-y-1.5">
            {([
              ["Session",  data.session_active?`active · room:${data.room_name??"?"}`:"inactive", data.session_active?"text-emerald-400":"text-slate-500"],
              ["Persona",  data.persona,       "text-slate-300"],
              ["TTS mode", data.voice_mode,    "text-slate-300"],
              ["Voice",    data.voice_speaker, "text-slate-300"],
              ["Language", data.voice_language,"text-slate-300"],
              ["Memory",   data.memory_enabled?"enabled":"disabled", data.memory_enabled?"text-emerald-400":"text-slate-500"],
            ] as [string,string,string][]).map(([k,v,cls])=>(
              <div key={k} className="flex justify-between gap-2"><Mono dim>{k}</Mono><Mono className={cls}>{v}</Mono></div>
            ))}
            {data.session_tokens!=null && <div className="flex justify-between"><Mono dim>Session tokens</Mono><Mono className="text-slate-300">{data.session_tokens.toLocaleString()}</Mono></div>}
          </div>
          {data.last_error && <p className="text-xs text-rose-400 font-mono break-all">{data.last_error}</p>}
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
import { LlmCard } from "./LlmCard"; import { SttCard } from "./SttCard";
import { TtsCard } from "./TtsCard"; import { AgentCard } from "./AgentCard";
export function ServicesTab() {
  return (
    <div className="h-full overflow-y-auto p-4">
      <div className="mx-auto max-w-5xl grid grid-cols-1 gap-4 md:grid-cols-2">
        <LlmCard/><SttCard/><TtsCard/><AgentCard/>
      </div>
    </div>
  );
}
EOF

# ==============================================================================
# 47 · components/session/MicButton.tsx
# Listen-only on connect. Token has canPublish=true so this button can enable.
# ==============================================================================
cat > components/session/MicButton.tsx << 'EOF'
"use client";
import { useState } from "react";
import { useLocalParticipant } from "@livekit/components-react";
import { Mic, MicOff } from "lucide-react"; import { cn } from "@/lib/utils";
export function MicButton() {
  const { localParticipant }=useLocalParticipant();
  const [on,setOn]=useState(false); const [busy,setBusy]=useState(false);
  async function toggle() {
    if (!localParticipant||busy) return; setBusy(true);
    try { await localParticipant.setMicrophoneEnabled(!on); setOn(v=>!v); }
    catch(e){ console.error("[MIC]",e); }
    finally { setBusy(false); }
  }
  return (
    <button onClick={toggle} disabled={!localParticipant||busy}
      className={cn("flex items-center gap-2 rounded-full px-5 py-2.5 text-sm font-semibold transition-all border",
        on?"bg-rose-400/15 border-rose-400/40 text-rose-400 hover:bg-rose-400/20":"bg-cyan-400/10 border-cyan-400/30 text-cyan-400 hover:bg-cyan-400/15")}>
      {on?<MicOff size={16}/>:<Mic size={16}/>}
      {busy?"…":on?"Mute Mic":"Start Mic"}
    </button>
  );
}
EOF

# ==============================================================================
# 48 · components/session/ContextPressureCard.tsx
# Real signals only: max_seq_len + session_tokens. No fake metrics.
# ==============================================================================
cat > components/session/ContextPressureCard.tsx << 'EOF'
"use client";
import { useLlmContext } from "@/hooks/useLlmContext"; import { useAgentState } from "@/hooks/useAgentState";
import { GlassCard } from "@/components/shared/GlassCard"; import { SectionHeader } from "@/components/shared/SectionHeader";
import { ProgressBar } from "@/components/shared/ProgressBar"; import { InlineAlert } from "@/components/shared/InlineAlert";
import { Mono } from "@/components/shared/Mono"; import { Activity } from "lucide-react"; import { cn } from "@/lib/utils";

export function ContextPressureCard() {
  const { data:ctx }  =useLlmContext();
  const { data:agent }=useAgentState();
  const max=ctx?.max_seq_len??null, used=agent?.session_tokens??null;
  const pct=(max&&used!=null)?Math.min(100,Math.round((used/max)*100)):null;
  const danger=pct!=null&&pct>=85, warn=pct!=null&&pct>=70&&!danger;
  return (
    <GlassCard className="p-4 space-y-2">
      <SectionHeader icon={<Activity size={14}/>} title="Context Pressure" subtitle="LLM token window"/>
      {max!=null ? (
        <>
          <div className="flex items-center justify-between">
            <Mono dim>Token fill</Mono>
            <Mono className={cn(danger?"text-rose-400":warn?"text-amber-400":"text-slate-400")}>
              {used?.toLocaleString()??"—"}&nbsp;/&nbsp;{max.toLocaleString()}{pct!=null&&` · ${pct}%`}
            </Mono>
          </div>
          {pct!=null && <ProgressBar value={pct} accentClass={danger?"bg-rose-400":warn?"bg-amber-400":"bg-cyan-400"}/>}
          {danger && <InlineAlert kind="error"   message="Context nearly full — save a Session Snapshot or Restore Context."/>}
          {warn   && <InlineAlert kind="warning"  message="Context pressure elevated. Consider saving a snapshot soon."/>}
          {!danger&&!warn&&pct!=null&&pct>0 && <p className="text-xs text-slate-600 font-mono">Context pressure nominal.</p>}
          {pct===0 && <p className="text-xs text-slate-600 font-mono">No tokens used in this session yet.</p>}
        </>
      ) : (
        <p className="text-xs text-slate-600 font-mono">
          {ctx?.online===false?"LLM offline — context ceiling unavailable.":"Awaiting LLM context data…"}
        </p>
      )}
    </GlassCard>
  );
}
EOF

# ==============================================================================
# 49 · components/session/ChatPanel.tsx
# DataChannel send/receive. Honest about agent reply availability.
# Manual review score: operator-entered only, clearly labeled.
# ==============================================================================
cat > components/session/ChatPanel.tsx << 'EOF'
"use client";
import { useState, useRef, useEffect } from "react";
import { useRoomContext, useRemoteParticipants } from "@livekit/components-react";
import { ParticipantKind, RoomEvent } from "livekit-client";
import { GlassCard } from "@/components/shared/GlassCard"; import { SectionHeader } from "@/components/shared/SectionHeader";
import { Mono } from "@/components/shared/Mono";
import { MessageSquare, Send, Tag } from "lucide-react"; import { cn } from "@/lib/utils";

interface Msg { id:string; role:"operator"|"agent"; text:string; ts:Date; manualScore?:number }

export function ChatPanel() {
  const room   =useRoomContext();
  const remotes=useRemoteParticipants();
  const agent  =remotes.find(p=>p.kind===ParticipantKind.AGENT||p.identity.startsWith("agent"));
  const [msgs,    setMsgs]    =useState<Msg[]>([]);
  const [input,   setInput]   =useState("");
  const [scoring, setScoring] =useState<string|null>(null);
  const [scoreVal,setScoreVal]=useState("");
  const bottom=useRef<HTMLDivElement>(null);

  useEffect(()=>{
    if (!room) return;
    const h=(payload:Uint8Array,participant?:{identity:string})=>{
      if (!participant) return;
      try { const p=JSON.parse(new TextDecoder().decode(payload)); if(p.type==="chat"&&typeof p.text==="string") setMsgs(prev=>[...prev,{id:crypto.randomUUID(),role:"agent",text:p.text,ts:new Date()}]); }
      catch { /* not a chat packet */ }
    };
    room.on(RoomEvent.DataReceived,h); return ()=>{ room.off(RoomEvent.DataReceived,h); };
  },[room]);
  useEffect(()=>{ bottom.current?.scrollIntoView({behavior:"smooth"}); },[msgs]);

  async function send() {
    const text=input.trim(); if(!text) return;
    setMsgs(prev=>[...prev,{id:crypto.randomUUID(),role:"operator",text,ts:new Date()}]); setInput("");
    try { await room.localParticipant.publishData(new TextEncoder().encode(JSON.stringify({type:"chat",text})),{reliable:true}); }
    catch(e){ console.error("[CHAT]",e); }
  }

  function applyScore(id:string) {
    const n=parseInt(scoreVal,10); if(isNaN(n)||n<0||n>100) return;
    setMsgs(prev=>prev.map(m=>m.id===id?{...m,manualScore:n}:m)); setScoring(null); setScoreVal("");
  }

  return (
    <GlassCard className="p-4 flex flex-col gap-3">
      <SectionHeader icon={<MessageSquare size={14}/>} title="Session Chat"
        subtitle={agent?"DataChannel · agent reply relay not confirmed":"no agent in room"}/>
      <p className={cn("text-xs font-mono leading-relaxed rounded-lg border px-3 py-2",
        agent?"border-slate-700/40 bg-black/10 text-slate-700":"border-cyan-400/15 bg-cyan-400/[0.04] text-cyan-400/60")}>
        {agent?"Messages sent via DataChannel. Agent replies appear here only if the backend relays them — no reply is fabricated.":"Connect a session to enable text messaging."}
      </p>
      <div className="flex-1 min-h-[180px] max-h-[300px] overflow-y-auto space-y-2 pr-0.5">
        {msgs.length===0 && <div className="flex flex-col items-center justify-center h-full py-6 gap-2"><MessageSquare size={18} className="text-slate-700"/><p className="text-xs text-slate-600 font-mono">No messages yet</p></div>}
        {msgs.map(m=>(
          <div key={m.id} className={cn("group rounded-lg border px-3 py-2 text-xs",m.role==="operator"?"border-cyan-400/15 bg-cyan-400/[0.06] ml-4":"border-violet-400/15 bg-violet-400/[0.06] mr-4")}>
            <div className="flex items-center justify-between mb-1 gap-2">
              <Mono className={m.role==="operator"?"text-cyan-400":"text-violet-400"}>{m.role==="operator"?"Operator":"Agent"}</Mono>
              <div className="flex items-center gap-2 shrink-0">
                {m.manualScore!=null && <span className={cn("text-[10px] font-mono px-1.5 py-0.5 rounded border",m.manualScore<65?"text-rose-400 border-rose-400/30 bg-rose-400/10":"text-white/60 border-white/20 bg-white/[0.04]")}>{m.manualScore}%&nbsp;<span className="text-slate-700">review</span></span>}
                <Mono dim className="text-[10px]">{m.ts.toLocaleTimeString("en-US",{hour12:false,hour:"2-digit",minute:"2-digit"})}</Mono>
                <button onClick={()=>{ setScoring(m.id); setScoreVal(String(m.manualScore??"")); }} className="opacity-0 group-hover:opacity-100 transition-opacity text-slate-700 hover:text-slate-400" title="Add manual operator review score"><Tag size={10}/></button>
              </div>
            </div>
            <p className="text-slate-300 leading-relaxed whitespace-pre-wrap break-words">{m.text}</p>
            {scoring===m.id && (
              <div className="flex items-center gap-2 mt-2 flex-wrap">
                <input type="number" min={0} max={100} value={scoreVal} onChange={e=>setScoreVal(e.target.value)} placeholder="0–100" className="w-16 rounded border border-white/[0.07] bg-black/30 px-1.5 py-0.5 text-xs text-slate-300 font-mono outline-none" autoFocus/>
                <button onClick={()=>applyScore(m.id)} className="rounded border border-white/[0.07] px-2 py-0.5 text-xs text-slate-400 hover:text-cyan-400 font-mono transition-colors">set</button>
                <button onClick={()=>{ setScoring(null); setScoreVal(""); }} className="text-xs text-slate-700 hover:text-slate-400 font-mono">cancel</button>
                <Mono dim className="text-[10px]">operator review · not backend confidence</Mono>
              </div>
            )}
          </div>
        ))}
        <div ref={bottom}/>
      </div>
      <div className="flex gap-2">
        <input type="text" value={input} onChange={e=>setInput(e.target.value)} onKeyDown={e=>e.key==="Enter"&&!e.shiftKey&&send()}
          placeholder={agent?"Type a message…":"Connect session first"} disabled={!agent}
          className="flex-1 rounded-md border border-white/[0.07] bg-black/30 px-3 py-2 text-xs text-slate-300 font-mono placeholder:text-slate-700 outline-none focus:border-cyan-400/40 disabled:opacity-40"/>
        <button onClick={send} disabled={!input.trim()||!agent}
          className={cn("flex items-center gap-1.5 shrink-0 rounded-md border px-3 py-2 text-xs font-medium transition-colors",
            input.trim()&&agent?"border-cyan-400/30 bg-cyan-400/10 text-cyan-400 hover:bg-cyan-400/15":"border-white/[0.05] text-slate-600 cursor-not-allowed")}>
          <Send size={12}/>Send
        </button>
      </div>
    </GlassCard>
  );
}
EOF

# ==============================================================================
# 50 · components/session/TranscriptPanel.tsx — honest empty state
# ==============================================================================
cat > components/session/TranscriptPanel.tsx << 'EOF'
"use client";
import { GlassCard } from "@/components/shared/GlassCard"; import { SectionHeader } from "@/components/shared/SectionHeader";
import { MessageSquare } from "lucide-react";
export function TranscriptPanel() {
  return (
    <GlassCard className="p-4 flex flex-col min-h-[110px]">
      <SectionHeader icon={<MessageSquare size={14}/>} title="Transcript"/>
      <div className="flex flex-1 flex-col items-center justify-center py-2 gap-1.5 text-center">
        <MessageSquare size={18} className="text-slate-700"/>
        <p className="text-xs text-slate-500 font-mono">Transcript relay not available</p>
        <p className="text-xs text-slate-700 font-mono max-w-xs leading-relaxed">
          STT and synthesis run server-side. The current backend does not publish a client-visible transcript stream. No data is being withheld.
        </p>
      </div>
    </GlassCard>
  );
}
EOF

# ==============================================================================
# 51 · components/session/VoicePreviewList.tsx
# Preview before select. Audio via /api/reference-audio/[voice].
# ==============================================================================
cat > components/session/VoicePreviewList.tsx << 'EOF'
"use client";
import { useState } from "react";
import { useAudioInventory } from "@/hooks/useInventory";
import { Mono } from "@/components/shared/Mono";
import { Play, Square, CheckCircle2 } from "lucide-react"; import { cn } from "@/lib/utils";

interface Props { selectedVoice:string; onSelect:(v:string)=>void }
export function VoicePreviewList({ selectedVoice, onSelect }:Props) {
  const { data,error,loading }=useAudioInventory();
  const [playing,setPlaying]=useState<string|null>(null);
  const [audio,  setAudio  ]=useState<HTMLAudioElement|null>(null);

  function preview(voice:string) {
    if (audio){ audio.pause(); audio.src=""; }
    if (playing===voice){ setPlaying(null); setAudio(null); return; }
    const a=new Audio(`/api/reference-audio/${encodeURIComponent(voice)}`);
    setAudio(a); setPlaying(voice);
    a.onended=a.onerror=()=>{ setPlaying(null); setAudio(null); };
    a.play().catch(()=>{ setPlaying(null); setAudio(null); });
  }

  if (loading) return <p className="text-xs text-slate-600 font-mono">Loading voices…</p>;
  if (error)   return <p className="text-xs text-rose-400 font-mono">{error}</p>;
  if (!data||data.voices.length===0) return <p className="text-xs text-slate-600 font-mono">No files in VOICEAI_ROOT/inputs/. Add .wav/.mp3/.flac reference audio to enable preview.</p>;

  return (
    <div className="space-y-1.5">
      {data.voices.map(v=>{
        const isPlaying=playing===v.voice, isChosen=selectedVoice===v.voice;
        return (
          <div key={v.voice} className={cn("flex items-center gap-2 rounded-lg border px-3 py-2 transition-colors",
            isChosen?"border-cyan-400/30 bg-cyan-400/[0.07]":"border-white/[0.05] bg-black/15 hover:border-white/[0.09]")}>
            <button onClick={()=>preview(v.voice)}
              className={cn("flex items-center justify-center w-6 h-6 rounded-full border shrink-0 transition-colors",
                isPlaying?"border-violet-400/40 bg-violet-400/15 text-violet-400":"border-white/[0.10] text-slate-500 hover:text-slate-300")}>
              {isPlaying?<Square size={9} fill="currentColor"/>:<Play size={9} fill="currentColor"/>}
            </button>
            <div className="flex-1 min-w-0">
              <p className={cn("text-xs font-medium truncate",isChosen?"text-cyan-400":"text-slate-300")}>{v.voice}</p>
              <Mono dim>{v.size_kb} KB · {v.filename.split(".").pop()?.toUpperCase()}</Mono>
            </div>
            <button onClick={()=>onSelect(isChosen?"":v.voice)}
              className={cn("flex items-center gap-1 shrink-0 rounded border px-2 py-0.5 text-[10px] font-mono transition-colors",
                isChosen?"border-cyan-400/40 bg-cyan-400/10 text-cyan-400":"border-white/[0.07] text-slate-500 hover:text-slate-300")}>
              <CheckCircle2 size={10}/>{isChosen?"Selected":"Select"}
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
# VoicePreviewList integrated for listen-before-select.
# ==============================================================================
cat > components/session/VoiceControls.tsx << 'EOF'
"use client";
import { useState } from "react";
import { useRoomContext, useRemoteParticipants } from "@livekit/components-react";
import { ParticipantKind } from "livekit-client";
import { usePersonaInventory } from "@/hooks/useInventory";
import { VoicePreviewList }    from "./VoicePreviewList";
import { GlassCard } from "@/components/shared/GlassCard"; import { SectionHeader } from "@/components/shared/SectionHeader";
import { InlineAlert } from "@/components/shared/InlineAlert"; import { Mono } from "@/components/shared/Mono";
import { Users, CheckCircle2, ChevronDown, ChevronUp } from "lucide-react";
import { LANGUAGES, INTERRUPTION_MODES } from "@/lib/constants"; import { cn } from "@/lib/utils";

type RpcResult={ ok:boolean; message:string };

function useAgentRpc() {
  const room=useRoomContext(); const remotes=useRemoteParticipants();
  const agent=remotes.find(p=>p.kind===ParticipantKind.AGENT||p.identity.startsWith("agent"));
  async function call(method:string,payload:Record<string,unknown>):Promise<string> {
    if (!agent) throw new Error("No agent in room");
    return room.localParticipant.performRpc({destinationIdentity:agent.identity,method,payload:JSON.stringify(payload),responseTimeout:8_000});
  }
  return { call, agentReady:!!agent };
}

function Sel({ label,value,onChange,options }:{ label:string; value:string; onChange:(v:string)=>void; options:{value:string;label:string}[] }) {
  return (
    <div className="space-y-1">
      <Mono dim>{label}</Mono>
      <select value={value} onChange={e=>onChange(e.target.value)}
        className="w-full rounded-md border border-white/[0.07] bg-black/30 px-2 py-1.5 text-xs text-slate-300 font-mono outline-none focus:border-cyan-400/40">
        {options.map(o=><option key={o.value} value={o.value}>{o.label}</option>)}
      </select>
    </div>
  );
}

export function VoiceControls() {
  const { call,agentReady }=useAgentRpc();
  const personas=usePersonaInventory();
  const [persona,    setPersona]    =useState("");
  const [voice,      setVoice]      =useState("");
  const [language,   setLanguage]   =useState("en");
  const [instruct,   setInstruct]   =useState("");
  const [interrupt,  setInterrupt]  =useState("normal");
  const [busy,       setBusy]       =useState(false);
  const [result,     setResult]     =useState<RpcResult|null>(null);
  const [showPreview,setShowPreview]=useState(false);

  async function rpc(method:string,payload:Record<string,unknown>) {
    if (busy) return; setBusy(true); setResult(null);
    try {
      await call(method,payload);
      const labels:Record<string,string>={ set_persona:`Persona → ${payload.name}`, set_session_voice:`Voice applied${voice?`: ${voice}`:""}·${language}`, set_interruption_behavior:`Interruption → ${payload.mode}` };
      setResult({ok:true,message:labels[method]??"OK"});
    } catch(e){ setResult({ok:false,message:e instanceof Error?e.message:String(e)}); }
    finally { setBusy(false); }
  }

  if (!agentReady) return (<GlassCard className="p-4"><SectionHeader icon={<Users size={14}/>} title="Session Voice Controls"/><p className="text-xs text-slate-600 font-mono mt-1">Waiting for agent participant in room…</p></GlassCard>);

  const personaOpts=personas.data?.personas.map(p=>({value:p.name,label:p.display_name??p.name}))??[];

  return (
    <GlassCard className="p-4 space-y-3">
      <SectionHeader icon={<Users size={14}/>} title="Session Voice Controls" subtitle="RPC · session-scoped only"/>
      <div className="rounded-lg border border-white/[0.05] p-3 space-y-2">
        <Mono dim>Active persona</Mono>
        <div className="flex gap-2">
          {personaOpts.length>0
            ? <select value={persona} onChange={e=>setPersona(e.target.value)} className="flex-1 rounded-md border border-white/[0.07] bg-black/30 px-2 py-1.5 text-xs text-slate-300 font-mono outline-none focus:border-cyan-400/40"><option value="">— select persona —</option>{personaOpts.map(o=><option key={o.value} value={o.value}>{o.label}</option>)}</select>
            : <p className="flex-1 text-xs text-slate-600 font-mono py-1.5">No personas — telemetry offline?</p>}
          <button onClick={()=>persona&&rpc("set_persona",{name:persona})} disabled={!persona||busy}
            className={cn("flex items-center gap-1 shrink-0 rounded-md border px-2 py-1.5 text-xs transition-colors",persona&&!busy?"border-cyan-400/30 bg-cyan-400/10 text-cyan-400 hover:bg-cyan-400/15":"border-white/[0.05] text-slate-600 cursor-not-allowed")}>
            <CheckCircle2 size={11}/>Apply
          </button>
        </div>
      </div>
      <div className="rounded-lg border border-white/[0.05] overflow-hidden">
        <button onClick={()=>setShowPreview(v=>!v)} className="flex items-center justify-between w-full px-3 py-2 text-xs text-slate-400 hover:text-slate-200 transition-colors">
          <div className="flex items-center gap-2">
            <Mono dim>Reference voice</Mono>
            {voice?<span className="text-cyan-400 font-mono text-[10px] px-1.5 py-0.5 rounded border border-cyan-400/25 bg-cyan-400/10">{voice}</span>:<Mono dim>none selected</Mono>}
          </div>
          {showPreview?<ChevronUp size={12}/>:<ChevronDown size={12}/>}
        </button>
        {showPreview && <div className="border-t border-white/[0.05] p-3"><VoicePreviewList selectedVoice={voice} onSelect={setVoice}/></div>}
      </div>
      <div className="rounded-lg border border-white/[0.05] p-3 space-y-2">
        <Mono dim>Language · style</Mono>
        <Sel label="Language" value={language} onChange={setLanguage} options={LANGUAGES.map(l=>({value:l.value,label:l.label}))}/>
        <div className="space-y-1">
          <Mono dim>Style instruction (optional)</Mono>
          <input type="text" value={instruct} onChange={e=>setInstruct(e.target.value)} placeholder="e.g. warm, calm narrator"
            className="w-full rounded-md border border-white/[0.07] bg-black/30 px-2 py-1.5 text-xs text-slate-300 font-mono placeholder:text-slate-700 outline-none focus:border-cyan-400/40"/>
        </div>
        <button onClick={()=>rpc("set_session_voice",{voice,language,instruct})} disabled={busy}
          className="w-full rounded-md border border-cyan-400/30 bg-cyan-400/10 py-1.5 text-xs font-medium text-cyan-400 hover:bg-cyan-400/15 transition-colors">
          Apply Voice Settings
        </button>
      </div>
      <div className="rounded-lg border border-white/[0.05] p-3 space-y-2">
        <Sel label="Interruption behavior" value={interrupt} onChange={setInterrupt} options={INTERRUPTION_MODES.map(m=>({value:m.value,label:m.label}))}/>
        <button onClick={()=>rpc("set_interruption_behavior",{mode:interrupt})} disabled={busy}
          className="w-full rounded-md border border-white/[0.07] bg-black/15 py-1.5 text-xs font-medium text-slate-400 hover:text-slate-200 transition-colors">
          Apply Interruption Mode
        </button>
      </div>
      {result && <InlineAlert kind={result.ok?"success":"error"} message={result.message}/>}
    </GlassCard>
  );
}
EOF

# ==============================================================================
# 53 · components/session/MemoryControls.tsx
# Final operator wording: Save Session Snapshot / Restore Context / Search Memory
# ==============================================================================
cat > components/session/MemoryControls.tsx << 'EOF'
"use client";
import { useState } from "react";
import { useRoomContext, useRemoteParticipants } from "@livekit/components-react";
import { ParticipantKind } from "livekit-client";
import { GlassCard } from "@/components/shared/GlassCard"; import { SectionHeader } from "@/components/shared/SectionHeader";
import { InlineAlert } from "@/components/shared/InlineAlert"; import { Mono } from "@/components/shared/Mono";
import { Database, ToggleLeft, ToggleRight, Save, RotateCcw, Search } from "lucide-react"; import { cn } from "@/lib/utils";

type R={ ok:boolean; message:string };

export function MemoryControls() {
  const room=useRoomContext(); const remotes=useRemoteParticipants();
  const agent=remotes.find(p=>p.kind===ParticipantKind.AGENT||p.identity.startsWith("agent"));
  const [memOn,  setMemOn  ]=useState(false);
  const [summary,setSummary]=useState(""); const [query,setQuery]=useState("");
  const [busy,   setBusy   ]=useState(false); const [result,setResult]=useState<R|null>(null);

  async function rpc(method:string,payload:Record<string,unknown>):Promise<string> {
    if (!agent) throw new Error("No agent in room");
    return room.localParticipant.performRpc({destinationIdentity:agent.identity,method,payload:JSON.stringify(payload),responseTimeout:10_000});
  }
  async function run(fn:()=>Promise<void>) {
    if (busy) return; setBusy(true); setResult(null);
    try { await fn(); } catch(e){ setResult({ok:false,message:e instanceof Error?e.message:String(e)}); }
    finally { setBusy(false); }
  }

  if (!agent) return (<GlassCard className="p-4"><SectionHeader icon={<Database size={14}/>} title="Memory" subtitle="requires active session"/><p className="text-xs text-slate-600 font-mono mt-1">No agent in room — connect first.</p></GlassCard>);

  return (
    <GlassCard className="p-4 space-y-3">
      <SectionHeader icon={<Database size={14}/>} title="Memory" subtitle="explicit control-plane"/>
      <div className="flex items-center justify-between rounded-lg border border-white/[0.05] bg-black/20 px-3 py-2">
        <div><p className="text-xs font-medium text-slate-300">Qdrant memory</p><Mono dim>{memOn?"enabled — storing context":"disabled"}</Mono></div>
        <button onClick={()=>run(async()=>{ await rpc("set_memory_enabled",{enabled:!memOn}); setMemOn(v=>!v); setResult({ok:true,message:`Memory ${!memOn?"enabled":"disabled"}`}); })} disabled={busy} className="text-slate-400 hover:text-cyan-400 transition-colors">
          {memOn?<ToggleRight size={22} className="text-emerald-400"/>:<ToggleLeft size={22}/>}
        </button>
      </div>
      <div className="rounded-lg border border-white/[0.05] p-3 space-y-2">
        <div><Mono className="flex items-center gap-1.5"><Save size={11}/>Save Session Snapshot</Mono><Mono dim className="mt-0.5 block">Writes a memory checkpoint to Qdrant</Mono></div>
        <textarea rows={2} value={summary} onChange={e=>setSummary(e.target.value)} placeholder="Describe what happened in this session…"
          className="w-full rounded-md border border-white/[0.07] bg-black/30 px-2 py-1.5 text-xs text-slate-300 font-mono placeholder:text-slate-700 outline-none focus:border-cyan-400/40 resize-none"/>
        <button onClick={()=>run(async()=>{ await rpc("create_memory_checkpoint",{summary:summary.trim(),session_id:""}); setResult({ok:true,message:"Session snapshot saved to Qdrant"}); setSummary(""); })}
          disabled={!summary.trim()||busy}
          className={cn("w-full rounded-md border py-1.5 text-xs font-medium transition-colors",summary.trim()&&!busy?"border-cyan-400/30 bg-cyan-400/10 text-cyan-400 hover:bg-cyan-400/15":"border-white/[0.05] text-slate-600 cursor-not-allowed")}>
          Save Snapshot
        </button>
      </div>
      <div className="rounded-lg border border-white/[0.05] p-3 space-y-2">
        <Mono dim>Restore Context / Search Memory</Mono>
        <input type="text" value={query} onChange={e=>setQuery(e.target.value)} placeholder="What to recall? (e.g. user's name, last topic…)"
          className="w-full rounded-md border border-white/[0.07] bg-black/30 px-2 py-1.5 text-xs text-slate-300 font-mono placeholder:text-slate-700 outline-none focus:border-cyan-400/40"/>
        <div className="grid grid-cols-2 gap-1.5">
          <button onClick={()=>run(async()=>{ await rpc("restore_previous_context",{query:query.trim(),user_id:""}); setResult({ok:true,message:"Restore Context requested — agent will inject retrieved context."}); })}
            disabled={!query.trim()||busy}
            className={cn("flex items-center justify-center gap-1 rounded-md border py-1.5 text-xs transition-colors",query.trim()&&!busy?"border-violet-400/30 bg-violet-400/10 text-violet-400 hover:bg-violet-400/15":"border-white/[0.05] text-slate-600 cursor-not-allowed")}>
            <RotateCcw size={11}/>Restore Context
          </button>
          <button onClick={()=>run(async()=>{ const r=await rpc("search_memory",{query:query.trim(),limit:5}); setResult({ok:true,message:r?.length>300?r.slice(0,300)+"…":(r||"No results")}); })}
            disabled={!query.trim()||busy}
            className={cn("flex items-center justify-center gap-1 rounded-md border py-1.5 text-xs transition-colors",query.trim()&&!busy?"border-cyan-400/30 bg-cyan-400/10 text-cyan-400 hover:bg-cyan-400/15":"border-white/[0.05] text-slate-600 cursor-not-allowed")}>
            <Search size={11}/>Search Memory
          </button>
        </div>
      </div>
      {result && <InlineAlert kind={result.ok?"success":"error"} message={result.message}/>}
    </GlassCard>
  );
}
EOF

# ==============================================================================
# 54 · components/session/SessionPanel.tsx — single canonical connected state
# Single-column layout. RoomContent renders all 6 session components.
# ==============================================================================
cat > components/session/SessionPanel.tsx << 'EOF'
"use client";
import { useState, useCallback } from "react";
import { LiveKitRoom, RoomAudioRenderer, useConnectionState } from "@livekit/components-react";
import { ConnectionState } from "livekit-client";
import "@livekit/components-styles";
import { GlassCard } from "@/components/shared/GlassCard"; import { SectionHeader } from "@/components/shared/SectionHeader";
import { StatusDot } from "@/components/shared/StatusDot"; import { InlineAlert } from "@/components/shared/InlineAlert";
import { Mono } from "@/components/shared/Mono";
import { MicButton }          from "./MicButton";
import { ContextPressureCard } from "./ContextPressureCard";
import { ChatPanel }          from "./ChatPanel";
import { TranscriptPanel }    from "./TranscriptPanel";
import { VoiceControls }      from "./VoiceControls";
import { MemoryControls }     from "./MemoryControls";
import { Radio, LogOut } from "lucide-react"; import { cn } from "@/lib/utils";

interface TokenData { token:string; url:string }

function ConnState() {
  const s=useConnectionState();
  const status=s===ConnectionState.Connected?"online":s===ConnectionState.Reconnecting?"degraded":s===ConnectionState.Disconnected?"offline":"unknown";
  return <div className="flex items-center gap-2"><StatusDot status={status}/><Mono>{s}</Mono></div>;
}

function RoomContent({ onDisconnect }:{ onDisconnect:()=>void }) {
  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <ConnState/>
        <button onClick={onDisconnect} className="flex items-center gap-1.5 rounded-md border border-white/[0.07] px-3 py-1.5 text-xs text-slate-500 hover:text-rose-400 hover:border-rose-400/30 transition-colors"><LogOut size={12}/>Disconnect</button>
      </div>
      <RoomAudioRenderer/>
      <MicButton/>
      <ContextPressureCard/>
      <ChatPanel/>
      <TranscriptPanel/>
      <VoiceControls/>
      <MemoryControls/>
    </div>
  );
}

export function SessionPanel() {
  const [td,        setTd]        =useState<TokenData|null>(null);
  const [connecting,setConnecting]=useState(false);
  const [error,     setError]     =useState<string|null>(null);

  const connect=useCallback(async()=>{
    setConnecting(true); setError(null);
    try {
      const res=await fetch("/api/livekit/token");
      const d=await res.json();
      if (!res.ok)         throw new Error(d.error??`HTTP ${res.status}`);
      if (!d.token||!d.url) throw new Error("Invalid token response from server");
      setTd(d as TokenData);
    } catch(e){ setError(e instanceof Error?e.message:String(e)); }
    finally { setConnecting(false); }
  },[]);

  const disconnect=useCallback(()=>{ setTd(null); setError(null); },[]);

  return (
    <GlassCard className="p-4 space-y-3">
      <SectionHeader icon={<Radio size={14}/>} title="Session" subtitle="voice-room · LiveKit"/>
      {!td ? (
        <div className="space-y-3">
          {error && <InlineAlert kind="error" message={error}/>}
          <button onClick={connect} disabled={connecting}
            className={cn("flex items-center gap-2 rounded-lg px-4 py-2.5 text-sm font-semibold transition-all border",
              connecting?"bg-white/[0.04] text-slate-600 cursor-not-allowed border-white/[0.05]":"bg-cyan-400/10 border-cyan-400/30 text-cyan-400 hover:bg-cyan-400/15")}>
            <Radio size={16} className={connecting?"animate-pulse":""}/>
            {connecting?"Connecting…":"Connect Session"}
          </button>
          <p className="text-xs text-slate-700 font-mono leading-relaxed">
            Joins voice-room in listen-only mode. Click "Start Mic" after connecting to publish audio.
          </p>
        </div>
      ) : (
        <LiveKitRoom token={td.token} serverUrl={td.url} connect={true} audio={false} video={false}
          onDisconnected={disconnect} onError={e=>{ setError(e.message); disconnect(); }}>
          <RoomContent onDisconnect={disconnect}/>
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
      <div className="mx-auto max-w-2xl"><SessionPanel/></div>
    </div>
  );
}
EOF

# ==============================================================================
# 56 · components/personas/PersonaManager.tsx
# ==============================================================================
cat > components/personas/PersonaManager.tsx << 'EOF'
"use client";
import { useState, useEffect } from "react";
import { GlassCard } from "@/components/shared/GlassCard"; import { SectionHeader } from "@/components/shared/SectionHeader";
import { InlineAlert } from "@/components/shared/InlineAlert"; import { Mono } from "@/components/shared/Mono";
import { Users, Plus, Save, Trash2, RefreshCw, Copy } from "lucide-react"; import { cn } from "@/lib/utils";

interface PFile { name:string; filename:string; size_bytes:number }
type R={ ok:boolean; message:string }

export function PersonaManager() {
  const [list,    setList]    =useState<PFile[]>([]); const [loading, setLoading]=useState(true);
  const [selected,setSelected]=useState(""); const [content, setContent]=useState("");
  const [dirty,   setDirty]   =useState(false); const [newName, setNewName]=useState("");
  const [result,  setResult]  =useState<R|null>(null); const [busy,setBusy]=useState(false);

  async function refresh() {
    setLoading(true);
    try { const r=await fetch("/api/personas"); const d=await r.json(); setList(d.personas??[]); }
    catch { setList([]); } finally { setLoading(false); }
  }
  async function load(name:string) {
    setResult(null);
    try { const r=await fetch(`/api/personas/${encodeURIComponent(name)}`); const d=await r.json(); if(d.ok){ setContent(d.content); setSelected(name); setDirty(false); } }
    catch { setResult({ok:false,message:"Load failed"}); }
  }
  async function save() {
    if (!selected||busy) return; setBusy(true); setResult(null);
    try {
      const r=await fetch(`/api/personas/${encodeURIComponent(selected)}`,{method:"PUT",headers:{"Content-Type":"application/json"},body:JSON.stringify({content})});
      const d=await r.json() as R; setResult(d); if(d.ok){ setDirty(false); await refresh(); }
    } catch(e){ setResult({ok:false,message:String(e)}); } finally { setBusy(false); }
  }
  async function create() {
    const n=newName.trim(); if(!n||busy) return; setBusy(true); setResult(null);
    try {
      const r=await fetch("/api/personas",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({name:n})});
      const d=await r.json() as R; setResult(d); if(d.ok){ setNewName(""); await refresh(); load(n); }
    } catch(e){ setResult({ok:false,message:String(e)}); } finally { setBusy(false); }
  }
  async function duplicate() {
    if (!selected||busy) return; const nn=`${selected}_copy`; setBusy(true); setResult(null);
    try {
      const cr=await fetch("/api/personas",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({name:nn})});
      const cd=await cr.json() as R;
      if(cd.ok){ await fetch(`/api/personas/${encodeURIComponent(nn)}`,{method:"PUT",headers:{"Content-Type":"application/json"},body:JSON.stringify({content})}); setResult({ok:true,message:`Duplicated as '${nn}'`}); await refresh(); load(nn); }
      else { setResult(cd); }
    } catch(e){ setResult({ok:false,message:String(e)}); } finally { setBusy(false); }
  }
  async function del() {
    if (!selected||!confirm(`Delete '${selected}'? This is irreversible.`)) return; setBusy(true); setResult(null);
    try {
      const r=await fetch(`/api/personas/${encodeURIComponent(selected)}`,{method:"DELETE"});
      const d=await r.json() as R; setResult(d); if(d.ok){ setSelected(""); setContent(""); await refresh(); }
    } catch(e){ setResult({ok:false,message:String(e)}); } finally { setBusy(false); }
  }
  useEffect(()=>{ refresh(); },[]);

  return (
    <GlassCard className="p-4 space-y-4">
      <SectionHeader icon={<Users size={14}/>} title="Persona File Management" subtitle="VOICEAI_ROOT/agent/personas/ · session switch via LiveKit RPC set_persona"/>
      <div className="flex gap-2">
        <input type="text" value={newName} onChange={e=>setNewName(e.target.value.replace(/[^a-zA-Z0-9_-]/g,""))} onKeyDown={e=>e.key==="Enter"&&create()} placeholder="new_persona_name" maxLength={64}
          className="flex-1 rounded-md border border-white/[0.07] bg-black/30 px-2 py-1.5 text-xs text-slate-300 font-mono placeholder:text-slate-700 outline-none focus:border-cyan-400/40"/>
        <button onClick={create} disabled={!newName.trim()||busy}
          className={cn("flex items-center gap-1 shrink-0 rounded-md border px-2 py-1.5 text-xs transition-colors",newName.trim()&&!busy?"border-emerald-400/30 bg-emerald-400/10 text-emerald-400 hover:bg-emerald-400/15":"border-white/[0.05] text-slate-600 cursor-not-allowed")}>
          <Plus size={11}/>Create
        </button>
        <button onClick={refresh} disabled={loading} className="rounded-md border border-white/[0.07] px-2 py-1.5 text-slate-500 hover:text-slate-300 transition-colors"><RefreshCw size={12} className={loading?"animate-spin":""}/></button>
      </div>
      <div className="grid grid-cols-1 gap-3 md:grid-cols-[180px_1fr]">
        <div className="rounded-lg border border-white/[0.05] bg-black/15 overflow-hidden min-h-[80px]">
          {list.length===0 && <p className="px-3 py-3 text-xs text-slate-600 font-mono">{loading?"Loading…":"No personas found"}</p>}
          {list.map(p=>(
            <button key={p.name} onClick={()=>load(p.name)}
              className={cn("w-full text-left px-3 py-2 text-xs font-medium transition-colors border-b border-white/[0.03] last:border-0",selected===p.name?"bg-cyan-400/10 text-cyan-400":"text-slate-400 hover:text-slate-200 hover:bg-white/[0.03]")}>
              {p.name}<Mono dim className="block mt-0.5">{(p.size_bytes/1024).toFixed(1)}KB</Mono>
            </button>
          ))}
        </div>
        <div className="space-y-2">
          {selected ? (
            <>
              <div className="flex items-center justify-between">
                <Mono className="text-slate-300">{selected}.md</Mono>
                <div className="flex gap-1.5">
                  <button onClick={duplicate} disabled={busy} title="Duplicate" className="rounded border border-white/[0.07] p-1 text-slate-500 hover:text-slate-300 transition-colors"><Copy size={11}/></button>
                  <button onClick={del} disabled={busy} title="Delete" className="rounded border border-rose-400/20 p-1 text-rose-400/50 hover:text-rose-400 transition-colors"><Trash2 size={11}/></button>
                </div>
              </div>
              <textarea value={content} onChange={e=>{ setContent(e.target.value); setDirty(true); }} rows={12}
                className="w-full rounded-md border border-white/[0.07] bg-black/30 px-3 py-2 text-xs text-slate-300 font-mono outline-none focus:border-cyan-400/40 resize-y"/>
              <button onClick={save} disabled={!dirty||busy}
                className={cn("flex items-center gap-1.5 w-full justify-center rounded-md border py-1.5 text-xs font-medium transition-colors",dirty&&!busy?"border-cyan-400/30 bg-cyan-400/10 text-cyan-400 hover:bg-cyan-400/15":"border-white/[0.05] text-slate-600 cursor-not-allowed")}>
                <Save size={12}/>{busy?"Saving…":dirty?"Save Changes":"No unsaved changes"}
              </button>
            </>
          ) : (
            <div className="flex items-center justify-center min-h-[120px] text-xs text-slate-600 font-mono">Select a persona to edit</div>
          )}
        </div>
      </div>
      {result && <InlineAlert kind={result.ok?"success":"error"} message={result.message}/>}
      <div className="rounded-lg border border-amber-400/15 bg-amber-400/[0.03] px-3 py-2">
        <p className="text-xs text-amber-400/70 font-mono leading-relaxed">File changes take effect on next session start. To switch persona mid-session use Session Voice Controls (LiveKit RPC set_persona).</p>
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
  return <div className="h-full overflow-y-auto p-4"><div className="mx-auto max-w-4xl"><PersonaManager/></div></div>;
}
EOF

# ==============================================================================
# 58 · components/memory/MemoryPanel.tsx — Qdrant stats + session redirect
# ==============================================================================
cat > components/memory/MemoryPanel.tsx << 'EOF'
"use client";
import { usePoll } from "@/hooks/usePoll";
import { GlassCard } from "@/components/shared/GlassCard"; import { SectionHeader } from "@/components/shared/SectionHeader";
import { StatusDot } from "@/components/shared/StatusDot"; import { Mono } from "@/components/shared/Mono";
import { Database, Info } from "lucide-react"; import { POLL } from "@/lib/constants";
import type { MemoryInventory } from "@/lib/types";

const fetchMem=()=>fetch("/api/proxy/telemetry/inventory/memory",{cache:"no-store"}).then(r=>{ if(!r.ok)throw new Error(`HTTP ${r.status}`); return r.json() as Promise<MemoryInventory>; });

function QdrantCard() {
  const { data,error,loading }=usePoll<MemoryInventory>(fetchMem, POLL.NORMAL);
  return (
    <GlassCard className="p-4 space-y-3">
      <SectionHeader icon={<Database size={14}/>} title="Qdrant" subtitle="127.0.0.1:6333 · memory backbone"/>
      {loading && <p className="text-xs text-slate-600 font-mono">Checking…</p>}
      {error   && <p className="text-xs text-rose-400 font-mono">{error}</p>}
      {data && (
        <>
          <StatusDot status={data.online?"online":"offline"} showLabel/>
          {data.online&&data.collections&&data.collections.length>0 && (
            <div className="rounded-lg border border-white/[0.05] bg-black/20 divide-y divide-white/[0.04]">
              {data.collections.map(c=>(<div key={c.name} className="flex items-center justify-between px-3 py-2"><Mono className="text-slate-400">{c.name}</Mono><Mono dim>{c.vectors_count.toLocaleString()} vectors</Mono></div>))}
            </div>
          )}
          {data.online&&(!data.collections||data.collections.length===0) && <p className="text-xs text-slate-600 font-mono">No collections. Run bootstrap.sh to initialise memory.</p>}
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
        <QdrantCard/>
        <GlassCard className="p-4">
          <SectionHeader icon={<Info size={14}/>} title="Memory Control-Plane" subtitle="session required"/>
          <p className="text-xs text-slate-600 font-mono leading-relaxed mt-1">
            Save Session Snapshot, Restore Context, and Search Memory all require an active LiveKit session (agent must be in the room). Open the Session tab, connect, then use the Memory panel there.
          </p>
        </GlassCard>
      </div>
    </div>
  );
}
EOF

# ==============================================================================
# 59 · components/tools/WebFetchPanel.tsx
# ==============================================================================
cat > components/tools/WebFetchPanel.tsx << 'EOF'
"use client";
import { useState } from "react";
import { GlassCard } from "@/components/shared/GlassCard"; import { SectionHeader } from "@/components/shared/SectionHeader";
import { InlineAlert } from "@/components/shared/InlineAlert"; import { Mono } from "@/components/shared/Mono";
import { Globe, Search, X } from "lucide-react"; import { cn } from "@/lib/utils";

interface FR { ok:boolean; status?:number; url?:string; content_type?:string; size_bytes?:number; truncated?:boolean; text?:string; error?:string }

export function WebFetchPanel() {
  const [url,setUrl]=useState(""); const [loading,setLoading]=useState(false); const [result,setResult]=useState<FR|null>(null);
  async function go() {
    const u=url.trim(); if(!u||loading) return; setLoading(true); setResult(null);
    try { const res=await fetch("/api/tools/webfetch",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({url:u})}); setResult(await res.json() as FR); }
    catch(e){ setResult({ok:false,error:e instanceof Error?e.message:String(e)}); }
    finally { setLoading(false); }
  }
  return (
    <div className="h-full overflow-y-auto p-4">
      <div className="mx-auto max-w-3xl space-y-4">
        <GlassCard className="p-4 space-y-3">
          <SectionHeader icon={<Globe size={14}/>} title="Safe Web Fetch" subtitle="explicit operator action · no autonomous browsing"/>
          <div className="rounded-lg border border-amber-400/20 bg-amber-400/[0.04] px-3 py-2">
            <p className="text-xs text-amber-400/80 font-mono leading-relaxed">HTTP/HTTPS only. No JavaScript execution. Loopback addresses blocked server-side. Results shown here only — nothing saved automatically.</p>
          </div>
          <div className="flex gap-2">
            <input type="url" value={url} onChange={e=>setUrl(e.target.value)} onKeyDown={e=>e.key==="Enter"&&go()} placeholder="https://example.com"
              className="flex-1 rounded-md border border-white/[0.07] bg-black/30 px-3 py-2 text-xs text-slate-300 font-mono placeholder:text-slate-700 outline-none focus:border-cyan-400/40"/>
            <button onClick={go} disabled={!url.trim()||loading}
              className={cn("flex items-center gap-1.5 shrink-0 rounded-md border px-3 py-2 text-xs font-medium transition-colors",url.trim()&&!loading?"border-cyan-400/30 bg-cyan-400/10 text-cyan-400 hover:bg-cyan-400/15":"border-white/[0.05] text-slate-600 cursor-not-allowed")}>
              <Search size={12} className={loading?"animate-spin":""}/>{loading?"Fetching…":"Fetch"}
            </button>
            {result && <button onClick={()=>{ setResult(null); setUrl(""); }} className="rounded-md border border-white/[0.07] px-2 py-2 text-slate-600 hover:text-slate-300 transition-colors"><X size={12}/></button>}
          </div>
          {result&&!result.ok && <InlineAlert kind="error" message={result.error??"Unknown error"}/>}
          {result?.ok && (
            <div className="space-y-2">
              <div className="rounded-lg border border-white/[0.05] bg-black/20 px-3 py-2 space-y-1.5">
                {([["URL",result.url??"—","text-slate-300"],["Status",String(result.status??"—"),result.status&&result.status<400?"text-emerald-400":"text-rose-400"],["Content-Type",result.content_type??"—","text-slate-400"],["Size",result.size_bytes!=null?`${result.size_bytes.toLocaleString()} bytes${result.truncated?" (truncated to 512KB)":""}` :"—","text-slate-400"]] as [string,string,string][]).map(([k,v,cls])=>(
                  <div key={k} className="flex justify-between gap-3"><Mono dim>{k}</Mono><Mono className={`${cls} truncate max-w-[280px] text-right`}>{v}</Mono></div>
                ))}
              </div>
              {result.text && (
                <div className="rounded-lg border border-white/[0.05] bg-black/20">
                  <div className="border-b border-white/[0.04] px-3 py-1.5"><Mono dim>Response body</Mono></div>
                  <pre className="max-h-96 overflow-y-auto p-3 text-xs text-slate-400 font-mono whitespace-pre-wrap break-all leading-relaxed">{result.text}</pre>
                </div>
              )}
            </div>
          )}
        </GlassCard>
      </div>
    </div>
  );
}

export function ToolsTab() { return <WebFetchPanel/>; }
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
echo "  1. Edit .env.local:"
echo "       LIVEKIT_API_KEY=devkey"
echo "       LIVEKIT_API_SECRET=devsecret"
echo "     (must match livekit.yaml in the voiceai backend)"
echo "  2. voiceai-ctl.sh start all && voiceai-ctl.sh health"
echo
echo "  ── Start dev server ─────────────────────────────────"
echo "       cd voiceai-dashboard && npm run dev"
echo "       open http://localhost:3000"
echo
echo "  Tabs: Overview · Session · Personas · Services · Memory · Tools"
echo "  Secrets: server-side only · no NEXT_PUBLIC_* leakage"
echo "  Network: loopback-only · no 0.0.0.0 · no public URLs"
echo