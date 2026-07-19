# Changelog

All notable changes to Parrocchettami are documented here.

## 1.1.1 — 2026-07-19

### Guided onboarding

- Added a mascot-led first-run tutorial with an animated splash screen and contextual spotlights over the real app controls.
- Added replaying the tutorial from the app's information menu.
- Added sound and gradient-pulse feedback while moving through the tutorial.

### Transcript review and persistence

- Added low-confidence word review using Parakeet's per-word confidence values.
- Autosave transcript text and rich-text corrections, with saving feedback and reset to the original model output.
- Persist language choice, output format, phrase grouping, rich text, and source filename with history entries.

### History and settings

- Added searchable transcript previews and automatic titles for new microphone recordings.
- Added an Archived section with restore support.
- Added a configurable recent-history retention limit that never removes archived transcripts.
- Improved app settings and menu integration for the new history and onboarding controls.

### Reliability

- Improved model-download, subprocess, recorder, search, and transcript-state handling.
- Added regression coverage for confidence review and persisted history metadata.

## 1.1.0 — 2026-07-13

Parrocchettami 1.1 is a substantial native macOS redesign focused on making transcription, recording, and transcript review feel clearer, faster, and more at home on the Mac.

### A more native workspace

- Introduced a persistent sidebar for starting new transcriptions and reopening recent work.
- Redesigned the file and microphone choices as two large, responsive source cards.
- Kept recording controls in context instead of replacing the entire screen when recording starts.
- Added inline history search, rename, archive, and delete actions.
- Synchronized transcript titles between the document card and the selected sidebar entry.
- Improved keyboard focus behavior so focus rings appear when they are useful instead of being assigned at launch.

### A richer transcript experience

- Rebuilt the transcript as a focused document card with clearer hierarchy and higher contrast.
- Added native Rich Text, Timestamped, and SRT format switching.
- Added bold, italic, and underline formatting with a persistent native text editor.
- Added contextual transcript search with match counts and in-text highlighting.
- Added one-click copy and export controls.
- Added a clickable word count that switches to character count.
- Moved duration, detected language, and output format into the transcript metadata line.
- Added inline transcript-title editing without a separate dialog.
- Smoothed editing, search, count, and button transitions with Reduce Motion support.

### Zoom and accessibility

- Added **Zoom In**, **Zoom Out**, and **Actual Size** commands with `⌘+`, `⌘−`, and `⌘0`.
- Made the sidebar, controls, transcript typography, search fields, and source cards scale together while remaining crisp and clickable.
- Added responsive fallbacks for compact windows and the largest zoom level.
- Improved control labels, hints, selection behavior, and keyboard shortcuts throughout the app.

### Recording and audio handling

- Added a clearer recording state with elapsed time, live waveform, pause/resume, finish, and discard controls.
- Improved microphone selection and recording feedback.
- Added validation for empty or malformed OPUS files with more useful error details.
- Improved bundled `opusdec` execution and helper signing.

### Transcription reliability

- Requested timestamp data explicitly from `parakeet-cli` for timestamped and SRT output.
- Made CLI output decoding more resilient to noisy, pretty-printed, and mixed diagnostic output.
- Preserved usable transcript text when newer CLI output contains decoder-token objects instead of rendered timed words.
- Restored the successful plain-text fallback when JSON output is unavailable.

### Distribution

- Updated the Sparkle feed to the dedicated Parrocchettami website repository.
- Hardened packaging validation for the app, Sparkle framework, bundled CLI, OPUS helper, and dependent libraries.
- Added helper-specific entitlements for bundled audio conversion components.

### Compatibility

- Requires macOS 14 or later.
- The published DMG is for Apple Silicon Macs.
- Transcription remains fully local and offline.
- This release is ad-hoc signed and not notarized; macOS may require **right-click → Open** on first launch.
