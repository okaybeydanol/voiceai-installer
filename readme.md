# VoiceAI Installer

> Fully local, modular voice AI infrastructure — built for real-time, self-hosted, production-ready systems.

---

## 🚀 Overview

**VoiceAI Installer** is a staged, end-to-end setup system for building a fully local voice AI stack.

It orchestrates multiple AI components into a single cohesive system:

* 🧠 Local LLM server
* 🎤 Speech-to-Text (STT)
* 🔊 Text-to-Speech (TTS)
* 🧩 Agent orchestration layer
* 🧠 Memory system (RAG with Qdrant)
* 🌐 Tooling (web search, extensions)
* 📞 Telephony integration
* 🎙 Real-time communication (LiveKit)

All components are designed to run **locally**, with **modular architecture** and **clean separation of concerns**.

---

## 🧱 Architecture

The system is built as a **multi-service local AI stack**:

```
User Voice
   ↓
STT → Agent → LLM → Tools / Memory
   ↓            ↓
 TTS ← Response ← RAG (Qdrant)
   ↓
Audio Output (LiveKit / Phone)
```

Each service runs independently and communicates over internal APIs.

---

## ⚙️ Features

* Fully local AI stack (no external dependency required)
* Modular service-based architecture
* Real-time voice pipeline
* Event-driven agent system
* Persistent memory (vector DB + embeddings)
* Hot-reload capable services
* Telemetry & monitoring layer
* Admin surfaces (operator-only)
* Production-oriented setup (not a toy project)

---

## 🧩 System Components

### Core Services

* **LLM Server** (TabbyAPI)
* **STT Service** (Faster-Whisper)
* **TTS Stack** (Qwen3-TTS + Chatterbox)
* **Agent Runtime**
* **Memory Layer** (Qdrant)

### Infrastructure

* **LiveKit** (real-time communication)
* **Telemetry Service**
* **Admin Layer**
* **Systemd integration**

### AI Capabilities

* RAG (Retrieval-Augmented Generation)
* Persona system
* Voice activity detection (Silero VAD)
* Turn detection
* Tool integrations (web search, etc.)

---

## 🧠 Philosophy

This project is built with one goal:

> **Make local, production-grade voice AI systems reproducible.**

Instead of fragmented setups and ad-hoc scripts, this provides:

* Structured installation
* Predictable environment
* Clean service boundaries
* Scalable architecture

---

## 🛠 Installation

```bash
git clone https://github.com/YOUR_USERNAME/voiceai-installer.git
cd voiceai-installer

chmod +x bootstrap.sh
./bootstrap.sh

cd /home/{PROFILE_NAME}/ai-projects/voiceai/bin/
chmod +x voiceai-ctl.sh

./voiceai-ctl.sh start
./voiceai-ctl.sh status
./voiceai-ctl.sh logs agent
./voiceai-ctl.sh health
./voiceai-ctl.sh validate
```

---

## 📂 Project Structure

```
bootstrap/
  ├── 00_shared_helpers.sh
  ├── 01_prepare_layout_and_environment.sh
  ├── 02_run_preflight_and_shared_tools.sh
  ├── ...
  └── 11_download_models_and_finalize.sh

nextjs/
  └── build-dashboard.sh

bootstrap.sh
```

Each stage is designed to be:

* Idempotent
* Isolated
* Maintainable

---

## 📊 Current Status

🚧 **Active development**

* Core infrastructure: ✅
* LLM / STT / TTS: ✅
* Agent system: ✅
* Memory (Qdrant): ✅
* Telephony layer: ✅
* Dashboard (Next.js): ⏳

---

## 🔮 Roadmap

* [ ] Complete Next.js dashboard
* [ ] Improve agent reasoning loop
* [ ] Add more tool integrations
* [ ] Enhance telephony support
* [ ] Optimize resource management

---

## 🤝 Contributing

This project is currently evolving rapidly.

Contributions, feedback, and ideas are welcome.

---

## 📄 License

MIT License

---

## ⚡ Author

Built by someone obsessed with making local AI systems actually usable.