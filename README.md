# Parrocchettami

A native macOS app for local, offline audio transcription using NVIDIA Parakeet speech recognition. No cloud, no Python, no internet required after initial setup.

## Features

- **Drag & drop or file picker** — WAV, MP3, M4A, FLAC, OGG, AIFF, AAC
- **Live microphone recording** — real-time waveform, mic selector, pause/resume, timer
- **Multilingual transcription** — 25 European languages via Parakeet TDT 0.6B v3 (auto-detect or manual)
- **Three output formats**
  - **Plain Text** — clean transcription, optionally editable with undo/save
  - **Timestamped** — word-level timestamps with adjustable phrase grouping
  - **SRT** — subtitle export with sentence grouping
- **Cancel transcription** — abort long-running transcriptions
- **Edit & search** — edit plain text results, undo edits (up to 50 steps), find text
- **Persistent history** — recent transcriptions saved locally, reopen/export/delete
- **Fast & local** — Metal-accelerated on Apple Silicon, everything stays on your Mac
- **Copy & export** — copy to clipboard or save as `.txt` / `.srt`

## Requirements

- macOS 14 (Sonoma) or later for the bundled Metal CLI
- Apple Silicon or Intel Mac
- ~707 MB disk space for the speech model
- ~3 MB for the parakeet-cli binary
- Microphone permission (for recording mode only)

## Quick Start

```bash
# 1. Download the speech model and CLI binary (one-time)
./setup.sh

# 2. Build and launch the app
./run.sh
```

The app appears in your Dock with a custom icon. The status pill shows green "Ready" once the model is found.

## Usage

### Transcribe a file
1. Drag an audio file onto the **Open File** card, or click it to browse (⌘O)
2. Optionally select a language from the dropdown (default: auto-detect)
3. Wait for transcription — audio duration is shown during progress
4. Switch between **Plain Text** / **Timestamped** / **SRT** using the segmented control
5. Adjust phrase grouping with the **Short ↔ Long** slider
6. Click **Copy** or **Export** to save

### Record live audio
1. Click the **Record** button (⌘R)
2. Grant microphone permission if prompted
3. Speak — the waveform animates in real time, timer shows elapsed time
4. Click again to **pause**, click once more to resume
5. Click **Done** (⌘↩) to stop and transcribe
6. Or click **Cancel** during transcription to abort

### Edit a transcript
1. In **Plain Text** mode, click the pencil icon to enter edit mode
2. Make changes — undo is available while editing
3. Click the pencil again or reset to discard edits
4. Copy or export the edited version

### Microphone selection
Use the dropdown below the Record button to choose a different mic. Click the refresh icon to re-scan available devices.

### History
Past transcriptions appear below results. Click the reopen icon to load one back, export to save, or delete individual entries. **Clear All** wipes history.

### Language selection
Choose from 25 European languages in the header dropdown, or leave on **Auto-detect** to let the model decide.

## How It Works

Parrocchettami wraps [parakeet.cpp](https://github.com/mudler/parakeet.cpp) — a C++/ggml port of NVIDIA's Parakeet ASR models. When you start a transcription:

1. Audio is converted to 16kHz mono WAV (using macOS `afconvert` if needed)
2. `parakeet-cli` is called as a subprocess with the GGUF model and optional language flag
3. JSON output (text + per-word timestamps) is parsed
4. Results are formatted according to the selected output mode and grouping setting

The model loads into RAM for each transcription (Metal GPU-accelerated on Apple Silicon), and is freed after completion. Everything runs locally.

## Project Structure

```
├── Parrocchettami/              # SwiftUI app source
│   ├── Package.swift
│   └── Sources/Parrocchettami/
│       ├── App.swift            # Entry point & window setup
│       ├── ContentView.swift    # Top-level layout & state management
│       ├── InputWorkspace.swift # Record/file cards, waveform, mic picker
│       ├── StatusViews.swift    # Status badge, progress bar, setup error
│       ├── TranscriptView.swift # Results, formatting, edit/search/undo
│       ├── AudioRecorder.swift  # Mic capture, peak metering, pause/resume
│       ├── Transcriber.swift    # CLI orchestration, JSON parsing, cancel
│       └── HistoryManager.swift # Persistent transcription history
├── bin/                         # (downloaded) parakeet-cli binary
├── models/                      # (downloaded) GGUF speech model
├── parrocchettami.icon/         # Icon Composer app icon source
├── setup.sh                     # One-time dependency download
├── run.sh                       # Build .app bundle & launch
├── Makefile                     # Convenience targets
├── README.md                    # This file
└── AGENTS.md                    # Developer/agent reference
```

## Build Targets

```bash
make setup     # Download CLI + model
make build     # Compile the Swift app
make run       # Build & launch (env var → swift run)
make clean     # Remove build artifacts + downloaded dependencies
```

## Troubleshooting

**"parakeet-cli not found"** — Run `./setup.sh` to download the binary and model.

**Model not found** — Ensure `models/tdt-0.6b-v3-q5_k.gguf` exists (~707 MB). Run `./setup.sh` again if needed.

**"Cannot copy audio file"** — If the project is in Documents/Desktop/Downloads, macOS TCC may block file access. Move the project to a non-protected location (e.g. `~/Developer/`).

**Recording produces silence or wrong mic** — Use the dropdown below the Record button to select the correct microphone. Click the refresh icon to re-scan.

**Microphone access denied** — System Settings → Privacy & Security → Microphone → enable Terminal (or Parrocchettami if running as .app).

**App won't open (Gatekeeper)** — Right-click the app → **Open** on first launch. The app is unsigned.

**Language not working** — Ensure the language code is supported. See `ContentView.swift` → `supportedLanguages` for the full list.

## License

Parrocchettami's source code is released under the GNU General Public
License, version 3 or later (GPL-3.0-or-later). See [LICENSE](LICENSE).

You may use, study, modify, and redistribute the app under the GPL. If you
distribute modified versions or binary builds, keep the same GPL freedoms,
include the license and notices, and make the corresponding source code
available under GPL-3.0-or-later.

Donations, sponsorships, paid support, and pay-what-you-want downloads are
welcome and compatible with this license. Parrocchettami is not intended to
include ads, tracking, or data sales.

Third-party components have their own licenses and attribution requirements.
See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), including:
- [parakeet.cpp](https://github.com/mudler/parakeet.cpp) - MIT
- [Parakeet TDT 0.6B v3 model](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) / GGUF conversion - CC BY 4.0
