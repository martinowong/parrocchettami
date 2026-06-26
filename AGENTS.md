# AGENTS.md — Parrocchettami

## Overview

A native macOS SwiftUI app for offline audio transcription. Wraps the `parakeet-cli` binary (from [parakeet.cpp](https://github.com/mudler/parakeet.cpp)) and a GGUF speech model (tdt-0.6b-v3) from Hugging Face. No Python runtime, no server — just a SwiftUI app calling a C++ CLI subprocess.

## Architecture

```
User → SwiftUI App → parakeet-cli subprocess → GGUF model → JSON output → parsed & formatted
```

### Component Map

| Component | File | Role |
|-----------|------|------|
| App entry | `App.swift` | `@main`, sets activation policy, creates `Transcriber`, passes to `ContentView` |
| UI | `ContentView.swift` | Top-level layout: header, input workspace, progress, results, history, diagnostics |
| Input workspace | `InputWorkspace.swift` | Record & file cards, waveform, mic selector, drop zone |
| Status views | `StatusViews.swift` | Status badge, setup error view, transcription progress (with cancel + duration) |
| Transcript view | `TranscriptView.swift` | Result display, format picker, grouping slider, copy/export, edit/search/undo |
| Recording | `AudioRecorder.swift` | `AVAudioEngine` tap → CAF → `afconvert` → 16kHz mono WAV, peak level metering, pause/resume, CoreAudio mic enumeration |
| Transcription | `Transcriber.swift` | Resource discovery (`bin/parakeet-cli` + `models/*.gguf`), subprocess orchestration (with cancel), JSON parsing, output formatting, language parameter |
| History | `HistoryManager.swift` | Persistent transcription history in `~/Library/Application Support/Parrocchettami/history.json`, Codable entries, CRUD operations |

### Data Flow

```
AudioRecorder.stopRecording() → URL (WAV)
    │
    ▼
ContentView.setFile(url) → getDuration(url) → startTranscription(url, language)
    │
    ▼
Transcriber.transcribe(fileURL:language:)        [async throws, cancellable]
    ├── copy to temp dir (parrocchettami-transcribe/)
    ├── afconvert if not WAV
    ├── Process: parakeet-cli transcribe --model X --input X --json [--lang Y]
    ├── filter stderr (ggml_, [parakeet], main:)
    ├── find JSON line, decode → TranscriptionResponse
    └── return TranscriptionResult(text, words, frameSec)
    │
    ▼
ContentView stores in HistoryManager, passes to TranscriptView
    └── result.formatted(as: outputFormat, grouping: grouping)
        ├── .plain     → text (editable with undo)
        ├── .timestamped → [start-end] phrase\n
        └── .srt       → SRT subtitle blocks
```

## Key Types

### Transcriber (ObservableObject)
- `@Published cliReady: Bool` — both CLI and model found
- `@Published isTranscribing: Bool` — set during active transcription
- `@Published transcriptionResult: TranscriptionResult?` — latest result
- `@Published debugLog: String` — diagnostic trail
- `@Published cliError: String?` — setup error messages
- `locateCLI()` — searches for `parakeet-cli` and `.gguf` model
- `transcribe(fileURL:language:) async throws → TranscriptionResult` — the pipeline, optionally passing `--lang`
- `cancel()` — terminates the current subprocess, resumes continuation with `TranscriberError.cancelled`
- `currentProcess: Process?` — held reference for cancellation
- `currentContinuation: CheckedContinuation?` — held for cancellation

### TranscriptionResult
- `text: String` — full transcription
- `words: [TimedWord]` — from parakeet JSON `words` array
- `frameSec: Double` — encoder frame stride
- `formatted(as: OutputFormat, grouping: Double) → String` — output formatting
- `groupWords(_:grouping:) → [[TimedWord]]` — time-proximity clustering
  - `maxGap = 0.1 + grouping * 2.9` seconds
  - `maxWords = max(1, 1 + grouping * 29)`

### AudioRecorder (ObservableObject)
- `@Published isRecording: Bool`
- `@Published isPaused: Bool` — pause state for pause/resume
- `@Published levels: [Float]` — rolling 30-sample peak levels for waveform
- `@Published selectedMic: MicDevice?` — selected input device (CoreAudio IDs)
- `@Published availableMics: [MicDevice]` — discovered via CoreAudio
- `startRecording() → String?` — returns error or nil, sets device via `AudioUnitSetProperty`
- `pauseRecording()` — calls `engine.pause()`, freezes waveform
- `resumeRecording()` — calls `engine.start()`
- `stopRecording(completion: (URL?) → Void)` — `afconvert`s raw CAF → WAV, calls completion

### HistoryManager (ObservableObject)
- `@Published entries: [HistoryEntry]` — persisted list
- `add(from:fileName:audioDuration:)` — saves new entry, trims to 100 max
- `delete(_:)` — removes single entry
- `clearAll()` — wipes all history
- Persists to `~/Library/Application Support/Parrocchettami/history.json`

### HistoryEntry (Codable, Identifiable)
- `id: UUID, fileName, text, words: [TimedWord], frameSec, date, audioDuration`
- `result: TranscriptionResult` — computed for reopen
- `formattedDate: String` — short date/time for display

### OutputFormat (enum, CaseIterable)
- `.plain` — "Plain Text"
- `.timestamped` — "Timestamped"
- `.srt` — "SRT"

### TranscriberError
- `.notReady(String)` — CLI/model not found
- `.processFailed(String)` — subprocess error
- `.cancelled` — user cancelled; no error message shown

## External Dependencies

### parakeet-cli (v0.3.2)
- Downloaded from: `https://github.com/mudler/parakeet.cpp/releases/tag/v0.3.2`
- macOS Metal arm64: `parakeet-v0.3.2-bin-macos-metal-arm64.tar.gz`
- macOS CPU x64: `parakeet-v0.3.2-bin-macos-cpu-x64.tar.gz`
- Expected location: `$PROJECT_ROOT/bin/parakeet-cli`
- CLI usage: `parakeet-cli transcribe --model <model.gguf> --input <audio.wav> --json [--lang <locale>]`
- JSON output format: `{"text":"...","frame_sec":0.08,"words":[{"w":"...","start":0.0,"end":0.32,"conf":0.99},...]}`

### GGUF Model
- Downloaded from: `https://huggingface.co/mudler/parakeet-cpp-gguf/resolve/main/tdt-0.6b-v3-q5_k.gguf`
- Expected location: `$PROJECT_ROOT/models/tdt-0.6b-v3-q5_k.gguf`
- ~707 MB, q5_k quantization
- 25 European languages, TDT 0.6B architecture
- Language flag: `--lang <locale>` (e.g. `en`, `fr`, `de`). Omit for auto-detect.

### afconvert (macOS built-in)
- Path: `/usr/bin/afconvert`
- Used for: audio format conversion during transcription and recording
- Recording: `afconvert -f WAVE -d LEI16@16000 -c 1 raw.caf output.wav`
- Transcription: same args for non-WAV source files

## Build System

- **Package manager:** SwiftPM (`Package.swift`, tools version 5.9, macOS 14+)
- **Build:** `swift build -c release` → single executable
- **Bundle:** `run.sh` manually constructs a `.app` bundle with `Info.plist`
- **Icon:** `run.sh` compiles `parrocchettami.icon` with Xcode `actool` → `Assets.car` + `parrocchettami.icns`
- **Launch:** `open <app_bundle>` (kills previous instances first, strips quarantine)

### Info.plist (generated by run.sh)
```xml
CFBundleExecutable: Parrocchettami
CFBundleIdentifier: com.parrocchettami.app
CFBundleName: Parrocchettami
CFBundleIconFile: parrocchettami (if parrocchettami.icon exists)
CFBundleIconName: parrocchettami (if parrocchettami.icon exists)
LSMinimumSystemVersion: 14.0
NSMicrophoneUsageDescription: (microphone permission prompt text)
LSEnvironment: { PARROCCHETTAMI_HOME: <project root> }
```

## Resource Discovery

`Transcriber.resourceBaseDir()` resolves the project root in priority order:
1. `PARROCCHETTAMI_HOME` environment variable (set by Makefile's `run` target, or embedded in the .app bundle's `LSEnvironment`)
2. `.app` bundle's executable parent directory
3. Current working directory (fallback)

## Permissions

- **Microphone:** `NSMicrophoneUsageDescription` in Info.plist + `AVCaptureDevice.requestAccess(for: .audio)`
- **File access:** Uses security-scoped bookmarks via `URL.startAccessingSecurityScopedResource()` for drag-dropped/picked files; copies to temp dir before processing
- **File system:** History persists to `~/Library/Application Support/Parrocchettami/`
- **No network entitlements needed** — everything runs locally

## Features at a Glance

- Two input modes: drag-and-drop file or live microphone recording
- Pause/resume recording with separate "Done" button
- Real-time waveform with peak-level metering (CoreAudio)
- Audio duration estimation shown during transcription
- Cancellable transcription (terminates subprocess)
- Three output formats with adjustable phrase grouping
- Editable plain text with undo stack (max 50 steps) and search
- Language selection: auto-detect or 25 explicit European languages
- Persistent transcription history with reopen, export, delete
- Export as `.txt` or `.srt`

## Known Limitations

- **No speaker diarization** — Parakeet TDT is ASR only, not speaker identification
- **No real-time transcription** — processes whole files (not streaming). `parakeet.cpp` supports streaming but not yet integrated.
- **Single model** — hardcoded to `tdt-0.6b-v3-q5_k.gguf`. Changing models requires updating `modelSearchPaths()` in `Transcriber.swift` and `setup.sh`
- **Sendable warnings** — `Transcriber.swift` has Swift 6 concurrency warnings around `outputBuffer` mutation in pipe handlers (safe in practice, needs `@Sendable` annotation for Swift 6)
- **Unsigned app** — distributed without notarization; users must right-click → Open on first launch
- **AVAsset.duration deprecated** — `ContentView.getDuration()` uses the deprecated `asset.duration` path; should migrate to `load(.duration)` async API

## Key Environment Variables

| Variable | Set by | Used by |
|----------|--------|---------|
| `PARROCCHETTAMI_HOME` | Makefile, run.sh (LSEnvironment) | Transcriber.resourceBaseDir() |

## Testing Manually

```bash
# Verify parakeet-cli works
bin/parakeet-cli transcribe --model models/tdt-0.6b-v3-q5_k.gguf --input test.wav --json

# Test with language flag
bin/parakeet-cli transcribe --model models/tdt-0.6b-v3-q5_k.gguf --input test.wav --json --lang fr

# Build only
cd Parrocchettami && swift build -c release

# Run without .app bundle (for debugging)
PARROCCHETTAMI_HOME=$(pwd) swift run
```
