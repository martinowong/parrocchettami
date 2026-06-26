import SwiftUI

struct StatusBadge: View {
    let isReady: Bool
    let isWorking: Bool
    let hasError: Bool

    private var label: String {
        if hasError { return "Setup required" }
        if isWorking { return "Working" }
        return isReady ? "Ready" : "Loading"
    }

    private var color: Color {
        if hasError { return .orange }
        if isWorking { return .accentColor }
        return isReady ? .green : .secondary
    }

    var body: some View {
        HStack(spacing: 7) {
            if isWorking {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
            }

            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(label)")
    }
}

struct SetupRequiredView: View {
    let message: String
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("Transcription engine unavailable")
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    if let onRetry {
                        Button("Retry", action: onRetry)
                            .buttonStyle(.bordered)
                            .accessibilityHint("Checks again for the bundled transcription engine.")
                    }
                    Text("Reinstall the app or contact the person who shared it with you.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.orange.opacity(0.22)))
        .accessibilityElement(children: .contain)
    }
}

struct ModelSetupView: View {
    @ObservedObject var installer: ModelInstaller

    private var percentage: String {
        "\(Int(installer.progress * 100))%"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
                .font(.title2)

            VStack(alignment: .leading, spacing: 7) {
                Text("Download the speech model")
                    .font(.headline)
                Text("Parrocchettami needs a 742 MB speech model once. After setup, transcription works entirely offline.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if installer.isDownloading {
                    HStack(spacing: 10) {
                        ProgressView(value: installer.progress)
                            .accessibilityLabel("Model download progress")
                            .accessibilityValue(percentage)
                        Text(percentage)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                        Button("Cancel", action: installer.cancelDownload)
                            .buttonStyle(.borderless)
                            .accessibilityHint("Stops the model download.")
                    }
                } else {
                    HStack(spacing: 10) {
                        Button("Download Model", action: installer.startDownload)
                            .buttonStyle(.borderedProminent)
                            .accessibilityHint("Downloads the offline speech model needed for transcription.")
                        Text("Requires about 1 GB of free disk space")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let error = installer.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.accentColor.opacity(0.18)))
        .accessibilityElement(children: .contain)
    }
}

struct TranscriptionProgressView: View {
    let fileName: String
    let audioDuration: TimeInterval?
    let phase: TranscriptionPhase
    var onCancel: (() -> Void)?

    private var durationText: String {
        guard let dur = audioDuration else { return "" }
        let m = Int(dur) / 60
        let s = Int(dur) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    var body: some View {
        HStack(spacing: 14) {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Transcription in progress")
            VStack(alignment: .leading, spacing: 2) {
                Text(phase.rawValue)
                    .font(.callout.weight(.semibold))
                HStack(spacing: 6) {
                    Text(fileName.isEmpty ? "Preparing your recording" : fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !durationText.isEmpty {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(durationText)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            if let onCancel {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .accessibilityHint("Stops the current transcription.")
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.secondary.opacity(0.14)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(phase.rawValue), \(fileName.isEmpty ? "preparing your recording" : fileName)")
    }
}
