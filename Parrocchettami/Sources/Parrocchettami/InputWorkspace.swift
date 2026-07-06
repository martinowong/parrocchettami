import SwiftUI
import UniformTypeIdentifiers

struct InputWorkspace: View {
    @ObservedObject var recorder: AudioRecorder

    let isReady: Bool
    let isTranscribing: Bool
    let elapsedTime: TimeInterval
    let selectedFileName: String
    let onChooseFile: () -> Void
    let onToggleRecording: () -> Void
    let onStopRecording: () -> Void
    let onDiscardRecording: () -> Void
    let onDropFile: (URL) -> Void
    let onClearFile: () -> Void

    @State private var isDropTargeted = false
    @FocusState private var focusedControl: WorkspaceFocus?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                fileSurface
                    .frame(minWidth: 300)
                recordingSurface
                    .frame(minWidth: 300)
            }

            VStack(spacing: 16) {
                fileSurface
                recordingSurface
            }
        }
        .frame(minHeight: 210)
    }

    private var fileSurface: some View {
        Button(action: onChooseFile) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isDropTargeted ? Color.accentColor : Color.accentColor.opacity(0.12))
                        .frame(width: 68, height: 68)

                    Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "waveform.badge.plus")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(isDropTargeted ? Color.white : Color.accentColor)
                }

                VStack(spacing: 5) {
                    Text(isDropTargeted ? "Drop to transcribe" : "Choose an audio file")
                        .font(.title3.weight(.semibold))
                    Text("or drag and drop it here")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text("WAV, MP3, M4A, FLAC, OGG, AIFF, AAC")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .contentShape(Rectangle())
        }
        .buttonStyle(WorkspaceButtonStyle(
            isEmphasized: isDropTargeted,
            isFocused: focusedControl == .file
        ))
        .disabled(!isReady || isTranscribing || recorder.isRecording)
        .keyboardShortcut("o", modifiers: .command)
        .focused($focusedControl, equals: .file)
        .focusEffectDisabled()
        .help("Choose audio to transcribe (⌘O)")
        .accessibilityLabel("Choose an audio file")
        .accessibilityHint("Opens a file picker. You can also drag and drop an audio file here.")
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay(alignment: .bottomLeading) {
            if !selectedFileName.isEmpty {
                SelectedFileBadge(fileName: selectedFileName, onClear: onClearFile)
                    .padding(14)
            }
        }
    }

    private var recordingSurface: some View {
        VStack(spacing: 18) {
            Button(action: onToggleRecording) {
                ZStack {
                    if recorder.isRecording && !recorder.isPaused {
                        Circle()
                            .stroke(Color.red.opacity(0.22), lineWidth: 9)
                            .frame(width: 92, height: 92)
                    }

                    Circle()
                        .fill(recordingButtonFill)
                        .frame(width: 74, height: 74)

                    Image(systemName: recorder.isRecording
                        ? (recorder.isPaused ? "play.fill" : "pause.fill")
                        : "mic.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(recordingButtonForeground)
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: .command)
            .focusable(false)
            .help(recorder.isRecording
                ? (recorder.isPaused ? "Resume recording (⌘R)" : "Pause recording (⌘R)")
                : "Start recording (⌘R)")
            .accessibilityLabel(recordingToggleAccessibilityLabel)
            .accessibilityHint(recordingToggleAccessibilityHint)

            VStack(spacing: 5) {
                Text(recordingTitle)
                    .font(.title3.weight(.semibold))
                Text(recordingSubtitle)
                    .font(recorder.isRecording && !recorder.isPaused ? .system(.callout, design: .monospaced) : .callout)
                    .foregroundStyle(recorder.isRecording && !recorder.isPaused ? Color.red : Color.secondary)
            }

            if recorder.isRecording {
                LiveWaveform(levels: recorder.levels)
                    .frame(height: 24)
                recordingSecondaryActions
            } else {
                microphonePicker
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(recorder.isRecording ? Color.red.opacity(0.09) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(recordingBorderColor, lineWidth: recorder.isRecording || focusedControl == .recording ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.07), radius: 10, y: 4)
        .disabled(!isReady || isTranscribing)
        .focused($focusedControl, equals: .recording)
        .focusEffectDisabled()
        .focusable(true)
        .onKeyPress(.space) {
            onToggleRecording()
            return .handled
        }
        .onKeyPress(.return) {
            onToggleRecording()
            return .handled
        }
        .accessibilityAddTraits(.isButton)
    }

    private var recordingSecondaryActions: some View {
        HStack(spacing: 10) {
            Button(action: onDiscardRecording) {
                Label("Discard", systemImage: "xmark.circle")
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Discard recording")
            .accessibilityLabel("Discard recording")
            .accessibilityHint("Stops recording and deletes the current take.")

            Button(action: onStopRecording) {
                Label("Finish", systemImage: "stop.circle.fill")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Finish recording (⌘↩)")
            .accessibilityLabel("Finish recording")
            .accessibilityHint("Stops recording and starts transcription.")
        }
        .labelStyle(.titleAndIcon)
        .frame(maxWidth: 280)
    }

    private var recordingButtonFill: Color {
        if recorder.isRecording && !recorder.isPaused { return .red }
        return Color.secondary.opacity(0.13)
    }

    private var recordingButtonForeground: Color {
        recorder.isRecording && !recorder.isPaused ? .white : .primary
    }

    private var recordingBorderColor: Color {
        if recorder.isRecording { return Color.red.opacity(0.8) }
        if focusedControl == .recording { return Color.accentColor.opacity(0.9) }
        return Color.secondary.opacity(0.16)
    }

    private var recordingTitle: String {
        if recorder.isPaused { return "Recording paused" }
        if recorder.isRecording { return "Recording" }
        return "Record from microphone"
    }

    private var recordingSubtitle: String {
        if recorder.isPaused { return "Resume or finish the recording" }
        if recorder.isRecording { return formattedTime }
        return "Capture a new recording"
    }

    private var recordingToggleAccessibilityLabel: String {
        if recorder.isPaused { return "Resume recording" }
        if recorder.isRecording { return "Pause recording" }
        return "Start recording"
    }

    private var recordingToggleAccessibilityHint: String {
        if recorder.isPaused { return "Continues recording from the selected microphone." }
        if recorder.isRecording { return "Pauses recording without finishing it." }
        return "Starts recording from the selected microphone."
    }

    private var microphonePicker: some View {
        HStack(spacing: 6) {
            Image(systemName: "mic")
                .foregroundStyle(.secondary)

            if recorder.availableMics.isEmpty {
                Text("No microphone found")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Picker("Microphone", selection: $recorder.selectedMic) {
                    ForEach(recorder.availableMics) { microphone in
                        Text(microphone.name).tag(Optional(microphone))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 190)
                .accessibilityLabel("Microphone")
            }

            Button(action: recorder.refreshMics) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Refresh microphones")
            .accessibilityLabel("Refresh microphones")
        }
        .font(.caption)
    }

    private var formattedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard isReady, !isTranscribing, !recorder.isRecording,
              let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async { onDropFile(url) }
        }
        return true
    }
}

private enum WorkspaceFocus: Hashable {
    case file
    case recording
}

private struct WorkspaceButtonStyle: ButtonStyle {
    let isEmphasized: Bool
    let isFocused: Bool
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isEmphasized ? tint.opacity(0.09) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(borderColor, lineWidth: isEmphasized || isFocused ? 2 : 1)
            )
            .shadow(color: .black.opacity(configuration.isPressed ? 0.03 : 0.07), radius: configuration.isPressed ? 2 : 10, y: configuration.isPressed ? 1 : 4)
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }

    private var borderColor: Color {
        if isEmphasized || isFocused { return tint.opacity(0.9) }
        return Color.secondary.opacity(0.16)
    }
}

private struct SelectedFileBadge: View {
    let fileName: String
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "waveform")
                .foregroundStyle(Color.accentColor)
            Text(fileName)
                .lineLimit(1)
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear selected file")
            .accessibilityLabel("Clear selected file")
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(0.15)))
    }
}

private struct LiveWaveform: View {
    let levels: [Float]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Color.red.opacity(0.85))
                    .frame(width: 2.5, height: max(3, CGFloat(level) * 36))
            }
        }
        .animation(.easeOut(duration: 0.06), value: levels)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Input level")
        .accessibilityValue("\(Int(((levels.max() ?? 0) * 100).rounded())) percent")
    }
}
