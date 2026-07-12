import SwiftUI
import UniformTypeIdentifiers

struct InputWorkspace: View {
    @Environment(\.interfaceZoom) private var interfaceZoom

    @ObservedObject var recorder: AudioRecorder

    let isReady: Bool
    let isTranscribing: Bool
    let elapsedTime: TimeInterval
    let onChooseFile: () -> Void
    let onToggleRecording: () -> Void
    let onStopRecording: () -> Void
    let onDiscardRecording: () -> Void
    let onDropFile: (URL) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sourceActions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                fileDropTarget
                recordingAction
            }

            VStack(spacing: 16) {
                fileDropTarget
                recordingAction
            }
        }
        .frame(minHeight: 300 * interfaceZoom)
    }

    private var fileDropTarget: some View {
        Button(action: onChooseFile) {
            SourceActionTile(tint: .blue,
                             symbol: isDropTargeted ? "arrow.down.doc.fill" : "waveform.badge.plus",
                             title: isDropTargeted ? "Drop to transcribe" : "Choose an audio file",
                             subtitle: isDropTargeted ? "Release to start transcription" : "or drag and drop it here",
                             detail: isDropTargeted ? nil : "All common audio formats") {
                Label("Drop a file here", systemImage: "arrow.down.doc")
                    .lineLimit(1)
                Spacer(minLength: 12)
                ShortcutHint("⌘O", tint: .blue)
            }
        }
        .buttonStyle(SourceActionButtonStyle(tint: .blue, isEmphasized: isDropTargeted))
        .frame(maxWidth: .infinity, minHeight: 300 * interfaceZoom)
        .keyboardShortcut("o", modifiers: .command)
        .focusEffectDisabled()
        .disabled(recorder.isRecording || !isReady || isTranscribing)
        .help("Choose audio to transcribe (⌘O)")
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose an audio file")
        .accessibilityHint("Choose a file or drag audio into this area.")
    }

    private var recordingAction: some View {
        Group {
            if recorder.isRecording {
                recordingCard
            } else {
                idleRecordingAction
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300 * interfaceZoom)
    }

    private var idleRecordingAction: some View {
        ZStack(alignment: .bottom) {
            Button(action: onToggleRecording) {
                SourceActionTile(tint: .green,
                                 symbol: "mic.fill",
                                 title: "Record from microphone",
                                 subtitle: "Capture a new recording") {
                    Color.clear
                        .frame(height: 20)
                }
            }
            .buttonStyle(SourceActionButtonStyle(tint: .green, isEmphasized: false))
            .keyboardShortcut("r", modifiers: .command)
            .focusEffectDisabled()
            .disabled(!isReady || isTranscribing)
            .help("Start recording (⌘R)")
            .accessibilityHint("Starts recording from the selected microphone.")

            HStack(spacing: 12) {
                microphonePicker
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                    .frame(height: 20)
                ShortcutHint("⌘R", tint: .green)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 22)
            .padding(.vertical, 17)
        }
    }

    private var recordingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label(recorder.isPaused ? "Recording paused" : "Recording", systemImage: "record.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                RollingTimerView(elapsedTime: elapsedTime)
                    .foregroundStyle(.red)
                Spacer()
            }

            VStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 28 * interfaceZoom, weight: .medium))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, isActive: !recorder.isPaused)

                LiveWaveform(levels: recorder.levels)
                    .frame(height: 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                Button(recorder.isPaused ? "Resume" : "Pause", action: onToggleRecording)
                    .buttonStyle(.bordered)
                    .keyboardShortcut("r", modifiers: .command)

                Button("Finish", action: onStopRecording)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(.return, modifiers: .command)

                Button("Discard", action: onDiscardRecording)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.red.opacity(0.22), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var microphonePicker: some View {
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
            .frame(maxWidth: 200)
            .accessibilityLabel("Microphone")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard isReady, !isTranscribing, !recorder.isRecording,
              let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            let ext = url.pathExtension.lowercased()
            guard ["wav", "wave", "mp3", "m4a", "flac", "ogg", "opus", "aiff", "aac"].contains(ext) else {
                return
            }
            DispatchQueue.main.async {
                onDropFile(url)
            }
        }
        return true
    }

}

private struct SourceIcon: View {
    @Environment(\.interfaceZoom) private var interfaceZoom

    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 24 * interfaceZoom, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 58 * interfaceZoom, height: 58 * interfaceZoom)
            .background(.regularMaterial, in: Circle())
            .background(color.opacity(0.10), in: Circle())
            .overlay(Circle().stroke(color.opacity(0.16), lineWidth: 1))
            .shadow(color: color.opacity(0.12), radius: 4, y: 2)
    }
}

private struct SourceActionTile<Footer: View>: View {
    @Environment(\.interfaceZoom) private var interfaceZoom

    let tint: Color
    let symbol: String
    let title: String
    let subtitle: String
    let detail: String?
    @ViewBuilder let footer: () -> Footer

    init(tint: Color,
         symbol: String,
         title: String,
         subtitle: String,
         detail: String? = nil,
         @ViewBuilder footer: @escaping () -> Footer) {
        self.tint = tint
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.footer = footer
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 11) {
                Spacer(minLength: 20)

                SourceIcon(symbol: symbol, color: tint)

                Text(title)
                    .font(.system(size: 15 * interfaceZoom, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 13 * interfaceZoom))
                    .foregroundStyle(.secondary)

                if let detail {
                    Text(detail)
                        .font(.system(size: 11 * interfaceZoom))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 22)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
                .overlay(Color.primary.opacity(0.06))

            HStack(spacing: 10, content: footer)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 22)
                .padding(.vertical, 17)
                .background(tint.opacity(0.025))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ShortcutHint: View {
    let key: String
    let tint: Color

    init(_ key: String, tint: Color) {
        self.key = key
        self.tint = tint
    }

    var body: some View {
        Text(key)
            .font(.system(.callout, design: .rounded).weight(.medium))
            .foregroundStyle(tint)
            .fixedSize()
            .accessibilityLabel("Keyboard shortcut \(key)")
    }
}

private struct SourceActionButtonStyle: ButtonStyle {
    let tint: Color
    let isEmphasized: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(tint.opacity(isEmphasized ? 0.11 : 0.035))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isEmphasized ? tint.opacity(0.72) : Color.primary.opacity(0.09), lineWidth: isEmphasized ? 2 : 1)
            }
            .shadow(color: .black.opacity(configuration.isPressed ? 0.05 : 0.10), radius: configuration.isPressed ? 3 : 10, y: configuration.isPressed ? 1 : 4)
            .brightness(configuration.isPressed ? -0.015 : 0)
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 1), value: configuration.isPressed)
    }
}

private struct RollingTimerView: View {
    let elapsedTime: TimeInterval

    private var minutes: Int { Int(elapsedTime) / 60 }
    private var seconds: Int { Int(elapsedTime) % 60 }

    var body: some View {
        HStack(spacing: 1) {
            Text("\(minutes)")
                .contentTransition(.numericText())
            Text(":")
            Text(String(format: "%02d", seconds))
                .contentTransition(.numericText())
        }
        .font(.system(.callout, design: .monospaced))
        .animation(.spring(response: 0.15, dampingFraction: 0.8), value: elapsedTime)
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
