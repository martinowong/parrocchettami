import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct ContentView: View {
    @EnvironmentObject private var transcriber: Transcriber
    @EnvironmentObject private var appUpdater: AppUpdater
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var history = HistoryManager()
    @StateObject private var modelInstaller = ModelInstaller()

    @State private var selectedFile: URL?
    @State private var fileName = ""
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var outputFormat: OutputFormat = .plain
    @State private var grouping: Double = 0.5
    @State private var showDiagnostics = false
    @State private var audioDuration: TimeInterval?
    @State private var selectedLanguage: String = ""
    @State private var showCredits = false
    @State private var retryFileURL: URL?
    @State private var retryFileDisplayName: String?
    @State private var lastRecordingConversionError: String?
    @State private var showClearHistoryConfirmation = false
    @State private var showDeleteEntryConfirmation: HistoryEntry?
    @State private var showAllHistory = false
    @State private var showDiscardRecordingConfirmation = false
    @State private var historySearchText = ""
    @FocusState private var isLanguageFocused: Bool

    private static let recordingNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    let supportedLanguages: [(code: String, name: String)] = [
        ("", "Auto-detect"),
        ("en", "English"), ("fr", "French"), ("de", "German"), ("es", "Spanish"),
        ("it", "Italian"), ("pt", "Portuguese"), ("nl", "Dutch"), ("pl", "Polish"),
        ("ru", "Russian"), ("uk", "Ukrainian"), ("cs", "Czech"),
        ("sv", "Swedish"), ("da", "Danish"), ("fi", "Finnish"),
        ("hu", "Hungarian"), ("ro", "Romanian"), ("sk", "Slovak"), ("bg", "Bulgarian"),
        ("el", "Greek"), ("hr", "Croatian"), ("sl", "Slovenian"), ("et", "Estonian"),
        ("lt", "Lithuanian"), ("lv", "Latvian"), ("mt", "Maltese"),
    ]

    private var isBusy: Bool {
        (recorder.isRecording && !recorder.isPaused) || transcriber.isTranscribing
    }

    private var selectedLanguageName: String {
        supportedLanguages.first(where: { $0.code == selectedLanguage })?.name ?? "Auto-detect"
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    if transcriber.cliError != nil {
                        if transcriber.cliError?.localizedCaseInsensitiveContains("model") == true {
                            ModelSetupView(installer: modelInstaller)
                        } else if let error = transcriber.cliError {
                            SetupRequiredView(message: error, onRetry: { Task { await transcriber.locateCLI() } })
                        }
                    }

                    if transcriber.transcriptionResult == nil && !transcriber.isTranscribing {
                        inputSection
                    }

                    if transcriber.isTranscribing {
                        TranscriptionProgressView(
                            fileName: fileName,
                            audioDuration: audioDuration,
                            phase: transcriber.transcriptionPhase,
                            onCancel: { transcriber.cancel() }
                        )
                    }

                    if let result = transcriber.transcriptionResult {
                        TranscriptView(
                            result: result,
                            outputFormat: $outputFormat,
                            grouping: $grouping,
                            onCopy: copyToClipboard,
                            onSave: exportResult
                        )
                    }

                    if !history.entries.isEmpty {
                        historySection
                    }

                    diagnostics
                }
                .frame(maxWidth: 920)
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            }

            creditsButton
                .padding(14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(InitialFocusClearingView().frame(width: 0, height: 0))
        .alert("Something went wrong", isPresented: $showAlert) {
            if let retryURL = retryFileURL {
                Button("Retry") {
                    selectedFile = retryURL
                    fileName = retryFileDisplayName ?? retryURL.lastPathComponent
                    retryFileURL = nil
                    let retryDisplayName = retryFileDisplayName
                    retryFileDisplayName = nil
                    startTranscription(retryURL, displayName: retryDisplayName)
                }
            }
            Button("OK") {
                retryFileURL = nil
            }
        } message: {
            Text(alertMessage ?? "")
        }
        .confirmationDialog(
            "Clear transcription history?",
            isPresented: $showClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
                Button("Clear History", role: .destructive) {
                    history.clearAll()
                    showAllHistory = false
                    historySearchText = ""
                }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all saved transcription history from this Mac.")
        }
        .confirmationDialog(
            "Discard current recording?",
            isPresented: $showDiscardRecordingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Recording", role: .destructive) {
                discardRecording()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This stops recording and deletes the current take.")
        }
        .confirmationDialog(
            "Delete transcription?",
            isPresented: Binding(
                get: { showDeleteEntryConfirmation != nil },
                set: { if !$0 { showDeleteEntryConfirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let entry = showDeleteEntryConfirmation {
                Button("Delete", role: .destructive) {
                    history.delete(entry)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let entry = showDeleteEntryConfirmation {
                Text("The transcription of \"\(entry.fileName)\" will be permanently removed.")
            }
        }
        .onChange(of: modelInstaller.isInstalled) { _, installed in
            if installed { Task { await transcriber.locateCLI() } }
        }
    }

    private var creditsButton: some View {
        Button {
            showCredits.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Credits and licenses")
        .accessibilityLabel("Credits and licenses")
        .popover(isPresented: $showCredits, arrowEdge: .bottom) {
            CreditsView(
                parakeetVersion: transcriber.parakeetVersion,
                canCheckForUpdates: appUpdater.canCheckForUpdates,
                onCheckForUpdates: appUpdater.checkForUpdates
            )
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(transcriber.transcriptionResult == nil ? "Turn audio into text" : "Your transcript")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text(transcriber.transcriptionResult == nil
                     ? "Private, fast transcription that stays entirely on your Mac."
                     : "Review, reformat, copy, or export the finished transcription.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 24)

            StatusBadge(
                isReady: transcriber.cliReady,
                isWorking: isBusy,
                hasError: transcriber.cliError != nil
            )

            if transcriber.transcriptionResult != nil && !isBusy {
                Button("New Transcription", action: clearFile)
                    .buttonStyle(.bordered)
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityHint("Clears the current result and returns to the input screen.")
            }
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New transcription")
                .font(.headline)
                .padding(.horizontal, 4)

            HStack(spacing: 10) {
                Label("Language", systemImage: "globe")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)

                Menu {
                    ForEach(supportedLanguages, id: \.code) { lang in
                        Button {
                            selectedLanguage = lang.code
                        } label: {
                            if selectedLanguage == lang.code {
                                Label(lang.name, systemImage: "checkmark")
                            } else {
                                Text(lang.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(selectedLanguageName)
                            .lineLimit(1)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(minWidth: 150, alignment: .leading)
                    .background(.quaternary.opacity(0.8), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isLanguageFocused ? Color.accentColor.opacity(0.9) : .clear, lineWidth: 2)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
                .focused($isLanguageFocused)
                .focusEffectDisabled()
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Transcription language")
                .accessibilityValue(selectedLanguageName)

                Spacer()
            }
            .padding(.horizontal, 4)

            InputWorkspace(
                recorder: recorder,
                isReady: transcriber.cliReady,
                isTranscribing: transcriber.isTranscribing,
                elapsedTime: elapsedTime,
                selectedFileName: fileName,
                onChooseFile: openFilePicker,
                onToggleRecording: toggleRecording,
                onStopRecording: stopRecording,
                onDiscardRecording: { showDiscardRecordingConfirmation = true },
                onDropFile: { setFile($0) },
                onClearFile: clearFile
            )
        }
        .accessibilityElement(children: .contain)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Transcriptions")
                    .font(.headline)
                Spacer()
                if filteredHistoryEntries.count > 5 {
                    Button(showAllHistory ? "Show Recent" : "Show All") {
                        showAllHistory.toggle()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(showAllHistory ? "Show recent transcription history" : "Show all transcription history")
                }
                Button("Clear All") {
                    showClearHistoryConfirmation = true
                }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear all transcription history")
                    .accessibilityHint("Asks for confirmation before deleting saved history.")
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .contain)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search history", text: $historySearchText)
                    .textFieldStyle(.plain)

                if !historySearchText.isEmpty {
                    Button {
                        historySearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear history search")
                }
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.14)))
            .accessibilityLabel("Search transcription history")

            VStack(spacing: 12) {
                ForEach(visibleHistoryEntries) { entry in
                    HistoryRow(
                        entry: entry,
                        onReopen: {
                            transcriber.transcriptionResult = entry.result
                            fileName = entry.fileName
                            selectedFile = nil
                            audioDuration = entry.audioDuration
                            outputFormat = .plain
                            grouping = 0.5
                        },
                        onExport: {
                            let display = entry.result.formatted(as: .plain)
                            exportResult(display, format: .plain)
                        },
                        onArchive: { history.archive(entry) },
                        onDelete: { showDeleteEntryConfirmation = entry }
                    )
                }
            }
            .padding(.top, 10)

            if visibleHistoryEntries.isEmpty {
                Text("No matching transcriptions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
            }
        }
    }

    private var visibleHistoryEntries: ArraySlice<HistoryEntry> {
        filteredHistoryEntries.prefix(showAllHistory ? 20 : 5)
    }

    private var filteredHistoryEntries: [HistoryEntry] {
        let query = historySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeEntries = history.entries.filter { !$0.isArchived }
        guard !query.isEmpty else { return activeEntries }
        return activeEntries.filter { entry in
            entry.fileName.localizedCaseInsensitiveContains(query)
                || entry.text.localizedCaseInsensitiveContains(query)
        }
    }

    private var diagnostics: some View {
        DisclosureGroup("Diagnostics", isExpanded: $showDiagnostics) {
            ScrollView([.vertical, .horizontal]) {
                Text(diagnosticText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 96, maxHeight: 220)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.16)))
            .padding(.top, 8)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .accessibilityLabel("Diagnostics")
    }

    private var diagnosticText: String {
        var sections: [String] = []

        if !transcriber.debugLog.isEmpty {
            sections.append(transcriber.debugLog)
        }
        if let error = recorder.lastError {
            sections.append("Recorder: \(error)")
        }
        if let error = lastRecordingConversionError {
            sections.append("Recording conversion: \(error)")
        }
        if let error = history.lastError {
            sections.append("History: \(error)")
        }
        if let error = modelInstaller.errorMessage {
            sections.append("Model installer: \(error)")
        }

        return sections.isEmpty ? "No diagnostic information yet." : sections.joined(separator: "\n\n")
    }

    private func toggleRecording() {
        if recorder.isPaused {
            recorder.resumeRecording()
            startTimer(reset: false)
            return
        }
        if recorder.isRecording {
            recorder.pauseRecording()
            stopTimer()
            return
        }

        Task {
            guard await recorder.requestPermission() else {
                await MainActor.run {
                    showError("Microphone access is disabled. Enable it in System Settings › Privacy & Security › Microphone.")
                }
                return
            }

            await MainActor.run {
                if let error = recorder.startRecording() {
                    showError("Recording failed: \(error)")
                } else {
                    startTimer()
                }
            }
        }
    }

    private func stopRecording() {
        recorder.stopRecording { url, errorMessage in
            stopTimer()
            lastRecordingConversionError = errorMessage
            guard let url else {
                showError(errorMessage ?? recorder.lastError ?? "The recording could not be converted to audio.")
                return
            }
            setFile(url, displayName: "Recording \(Self.recordingNameFormatter.string(from: Date()))")
        }
    }

    private func discardRecording() {
        recorder.discardRecording()
        stopTimer()
        elapsedTime = 0
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose audio to transcribe"
        panel.prompt = "Choose"
        panel.message = "Choose an audio file. It will be processed locally on this Mac."
        panel.allowedContentTypes = supportedAudioTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        setFile(url)
    }

    private var supportedAudioTypes: [UTType] {
        [
            .wav, .mp3, .mpeg4Audio,
            UTType(filenameExtension: "flac") ?? .audio,
            UTType(filenameExtension: "ogg") ?? .audio,
            UTType(filenameExtension: "opus") ?? .audio,
            UTType(filenameExtension: "m4a") ?? .audio,
            UTType(filenameExtension: "aiff") ?? .audio,
            UTType(filenameExtension: "aac") ?? .audio
        ]
    }

    private func setFile(_ url: URL, displayName: String? = nil) {
        let ext = url.pathExtension.lowercased()
        let supported = ["wav", "wave", "mp3", "m4a", "flac", "ogg", "opus", "aiff", "aac"]
        guard supported.contains(ext) else {
            showError("“\(url.lastPathComponent)” is not a supported audio file.\nSupported formats: WAV, MP3, M4A, FLAC, OGG, OPUS, AIFF, AAC.")
            return
        }

        selectedFile = url
        fileName = displayName ?? url.lastPathComponent
        grouping = 0.5
        outputFormat = .plain
        transcriber.transcriptionResult = nil
        audioDuration = nil
        retryFileURL = nil
        retryFileDisplayName = nil
        lastRecordingConversionError = nil
        Task {
            let duration = await getDuration(url)
            await MainActor.run {
                if selectedFile == url { audioDuration = duration }
            }
        }
        startTranscription(url, displayName: displayName)
    }

    private func getDuration(_ url: URL) async -> TimeInterval? {
        let needsScoped = url.startAccessingSecurityScopedResource()
        defer { if needsScoped { url.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    private func clearFile() {
        selectedFile = nil
        fileName = ""
        audioDuration = nil
        retryFileURL = nil
        retryFileDisplayName = nil
        lastRecordingConversionError = nil
        showAllHistory = false
        transcriber.transcriptionResult = nil
        if transcriber.isTranscribing {
            transcriber.cancel()
        }
        outputFormat = .plain
        grouping = 0.5
    }

    private func startTranscription(_ url: URL, displayName: String? = nil) {
        guard !transcriber.isTranscribing else { return }
        selectedFile = url
        fileName = displayName ?? url.lastPathComponent
        Task {
            do {
                let result = try await transcriber.transcribe(fileURL: url, language: selectedLanguage)
                await MainActor.run {
                    transcriber.transcriptionResult = result
                    history.add(from: result, fileName: fileName, audioDuration: audioDuration)
                    if displayName != nil {
                        cleanupTemporaryRecording(at: url)
                    }
                }
            } catch {
                let isCancelled = (error as? TranscriberError).map {
                    if case .cancelled = $0 { return true }
                    return false
                } ?? false
                if !isCancelled {
                    await MainActor.run {
                        retryFileURL = url
                        retryFileDisplayName = fileName
                        showError(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func cleanupTemporaryRecording(at url: URL) {
        guard url.lastPathComponent == "recording.wav",
              url.deletingLastPathComponent().lastPathComponent == "parrocchettami" else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func startTimer(reset: Bool = true) {
        if reset { elapsedTime = 0 }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            elapsedTime += 0.1
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func showError(_ message: String) {
        alertMessage = message
        showAlert = true
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exportResult(_ text: String, format: OutputFormat) {
        let panel = NSSavePanel()
        panel.title = "Export Transcription"
        panel.prompt = "Export"
        panel.nameFieldStringValue = format == .srt ? "transcription.srt" : "transcription.txt"
        panel.allowedContentTypes = format == .srt
            ? [UTType(filenameExtension: "srt") ?? .plainText]
            : [.plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            showError("The transcription could not be exported: \(error.localizedDescription)")
        }
    }
}

private struct InitialFocusClearingView: NSViewRepresentable {
    func makeNSView(context: Context) -> InitialFocusClearingNSView {
        InitialFocusClearingNSView()
    }

    func updateNSView(_ nsView: InitialFocusClearingNSView, context: Context) {
        nsView.clearInitialFocusIfNeeded()
    }
}

private final class InitialFocusClearingNSView: NSView {
    private var didClearInitialFocus = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        clearInitialFocusIfNeeded()
    }

    func clearInitialFocusIfNeeded() {
        guard !didClearInitialFocus else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  !self.didClearInitialFocus,
                  let window = self.window else { return }
            window.makeFirstResponder(nil)
            self.didClearInitialFocus = true
        }
    }
}

private struct CreditsView: View {
    let parakeetVersion: String
    let canCheckForUpdates: Bool
    let onCheckForUpdates: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Credits")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 6) {
                    Text("Parrocchettami")
                        .font(.headline)
                    Text(.init("parrocchettami is a project by [Martino Wong @oradecima](https://oradecima.com), developed with AI tools."))
                }

                Divider()

                credit(
                    title: "parakeet.cpp",
                    description: "Created by Ettore Di Giacinto (mudler) with contributions from the parakeet.cpp community. Parrocchettami uses its parakeet-cli transcription engine.",
                    links: [
                        ("Source", "https://github.com/mudler/parakeet.cpp"),
                        ("MIT License", "https://github.com/mudler/parakeet.cpp/blob/master/LICENSE")
                    ]
                )

                Text("Engine version: \(parakeetVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                credit(
                    title: "NVIDIA Parakeet TDT 0.6B v3",
                    description: "Speech-recognition model by NVIDIA, distributed here as a Q5_K GGUF conversion by mudler.",
                    links: [
                        ("Original model", "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3"),
                        ("GGUF conversion", "https://huggingface.co/mudler/parakeet-cpp-gguf"),
                        ("CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/")
                    ]
                )

                Text("Parrocchettami is not endorsed by NVIDIA, the parakeet.cpp authors, or the GGUF distributor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Check for Updates...", action: onCheckForUpdates)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCheckForUpdates)
            }
            .padding(20)
        }
        .frame(width: 430, height: 440)
    }

    private func credit(
        title: String,
        description: String,
        links: [(label: String, url: String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(description)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                ForEach(links, id: \.url) { link in
                    if let url = URL(string: link.url) {
                        Link(link.label, destination: url)
                    }
                }
            }
            .font(.caption)
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let onReopen: () -> Void
    let onExport: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.fileName)
                    .font(.callout)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(entry.formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(entry.text.prefix(60).replacingOccurrences(of: "\n", with: " "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Button(action: onReopen) {
                    Label("Open", systemImage: "doc.text")
                        .font(.callout.weight(.medium))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 8)
                        .frame(height: 32)
                }
                .buttonStyle(.bordered)
                .help("Open transcript")
                .accessibilityLabel("Open \(entry.fileName)")

                Button(action: onExport) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Export")
                .accessibilityLabel("Export \(entry.fileName)")

                Button(action: onArchive) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Archive")
                .accessibilityLabel("Archive \(entry.fileName)")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Delete")
                .accessibilityLabel("Delete \(entry.fileName)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
        .accessibilityElement(children: .contain)
    }
}
