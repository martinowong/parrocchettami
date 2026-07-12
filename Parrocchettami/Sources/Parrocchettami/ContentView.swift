import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct ContentView: View {
    private enum SidebarSelection: Hashable {
        case newTranscription
        case history(UUID)
    }

    private struct ErrorDetails: Identifiable {
        let id = UUID()
        let message: String
    }

    @EnvironmentObject private var transcriber: Transcriber
    @EnvironmentObject private var appUpdater: AppUpdater
    @EnvironmentObject private var interfaceZoom: InterfaceZoomController
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var history = HistoryManager()
    @StateObject private var modelInstaller = ModelInstaller()

    @State private var selectedFile: URL?
    @State private var fileName = ""
    @State private var errorDetails: ErrorDetails?
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
    @State private var renameEntry: HistoryEntry?
    @State private var renameText = ""
    @State private var currentHistoryEntryID: UUID?
    @State private var showDiscardRecordingConfirmation = false
    @State private var historySearchText = ""
    @State private var sidebarSelection: SidebarSelection? = .newTranscription
    @FocusState private var isSidebarRenameFocused: Bool

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

    private var interfaceDynamicTypeSize: DynamicTypeSize {
        switch interfaceZoom.scale {
        case ..<0.85: return .small
        case ..<0.95: return .medium
        case ..<1.05: return .large
        case ..<1.15: return .xLarge
        case ..<1.25: return .xxLarge
        case ..<1.35: return .xxxLarge
        default: return .accessibility1
        }
    }

    private var interfaceControlSize: ControlSize {
        switch interfaceZoom.scale {
        case ..<0.95: return .small
        case 1.05...: return .large
        default: return .regular
        }
    }

    var body: some View {
        content
            .environment(\.interfaceZoom, interfaceZoom.scale)
            .font(.system(size: 13 * interfaceZoom.scale))
            .dynamicTypeSize(interfaceDynamicTypeSize)
            .controlSize(interfaceControlSize)
    }

    private var content: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            if sidebarSelection == .newTranscription || isBusy || transcriber.cliError != nil {
                ToolbarItem(placement: .status) {
                    StatusBadge(
                        isReady: transcriber.cliReady,
                        isWorking: isBusy,
                        hasError: transcriber.cliError != nil
                    )
                }
            }

        }
        .modifier(FocusedSceneValuesModifier(
            openFileAction: openFilePicker,
            toggleRecordingAction: toggleRecording,
            stopRecordingAction: stopRecording,
            clearFileAction: clearFile,
            toggleDiagnosticsAction: { showDiagnostics.toggle() },
            isRecording: recorder.isRecording,
            isPaused: recorder.isPaused,
            isTranscribing: transcriber.isTranscribing,
            isReady: transcriber.cliReady,
            hasResult: transcriber.transcriptionResult != nil,
            hasFile: selectedFile != nil
        ))
        .background(WindowFocusResetter())
        .sheet(item: $errorDetails) { details in
            ErrorDetailsSheet(
                message: details.message,
                canRetry: retryFileURL != nil,
                retry: retryTranscription,
                dismiss: dismissErrorDetails
            )
        }
        .confirmationDialog(
            "Clear transcription history?",
            isPresented: $showClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
                Button("Clear History", role: .destructive) {
                    history.clearAll()
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
        .onChange(of: sidebarSelection) { _, selection in
            switch selection {
            case let .history(id):
                guard let entry = history.entries.first(where: { $0.id == id }) else { return }
                openHistoryEntry(entry)
            case .newTranscription, .none:
                if transcriber.transcriptionResult != nil || selectedFile != nil {
                    clearFile()
                }
            }
        }
    }

    private var creditsButton: some View {
        Button {
            showCredits.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 16 * interfaceZoom.scale))
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

    @ViewBuilder
    private var newTranscriptionButton: some View {
        if #available(macOS 26.0, *) {
            Button(action: startNewTranscription) {
                newTranscriptionLabel
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.roundedRectangle(radius: 11))
            .keyboardShortcut("n", modifiers: .command)
            .popButtonPressEffect()
        } else {
            Button(action: startNewTranscription) {
                newTranscriptionLabel
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 11))
            .keyboardShortcut("n", modifiers: .command)
            .popButtonPressEffect()
        }
    }

    private var newTranscriptionLabel: some View {
        HStack(spacing: 9 * interfaceZoom.scale) {
            Image(systemName: "plus")
                .fontWeight(.semibold)
                .foregroundStyle(.tint)
            Text("New Transcription")
                .font(.system(size: 13 * interfaceZoom.scale, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 4 * interfaceZoom.scale)
        .frame(maxWidth: .infinity, minHeight: 30 * interfaceZoom.scale, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            Section {
                sidebarSearchField
            }

            Section {
                newTranscriptionButton
                .listRowInsets(EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10))
                .accessibilityHint("Clears the current result and opens a fresh transcription.")
            }

            Section {
                ForEach(filteredHistoryEntries) { entry in
                    Group {
                        if renameEntry?.id == entry.id {
                            TextField("Transcript name", text: $renameText)
                                .textFieldStyle(.roundedBorder)
                                .focused($isSidebarRenameFocused)
                                .onSubmit { commitSidebarRename(entry) }
                                .onExitCommand { cancelSidebarRename() }
                        } else {
                            SidebarHistoryRow(entry: entry)
                        }
                    }
                        .listRowInsets(EdgeInsets(
                            top: 4 * interfaceZoom.scale,
                            leading: 10 * interfaceZoom.scale,
                            bottom: 4 * interfaceZoom.scale,
                            trailing: 10 * interfaceZoom.scale
                        ))
                        .tag(SidebarSelection.history(entry.id))
                        .contextMenu {
                            Button("Rename…") {
                                beginSidebarRename(entry)
                            }
                            Button("Export") {
                                exportResult(entry.result.formatted(as: .plain), format: .plain)
                            }
                            Button("Archive") {
                                history.archive(entry)
                                if sidebarSelection == .history(entry.id) {
                                    startNewTranscription()
                                }
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                showDeleteEntryConfirmation = entry
                            }
                        }
                }
            } header: {
                Text("Recent Transcriptions")
                    .font(.system(size: 11 * interfaceZoom.scale, weight: .semibold))
                    .padding(.leading, 8 * interfaceZoom.scale)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(
            min: 210 * interfaceZoom.scale,
            ideal: 230 * interfaceZoom.scale,
            max: 300 * interfaceZoom.scale
        )
        .navigationTitle("Parrocchettami")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                creditsButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("Clear History", role: .destructive) {
                        showClearHistoryConfirmation = true
                    }
                    .disabled(filteredHistoryEntries.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("History options")
            }
        }
    }

    private var sidebarSearchField: some View {
        HStack(spacing: 7 * interfaceZoom.scale) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12 * interfaceZoom.scale, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search transcripts", text: $historySearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13 * interfaceZoom.scale))

            if !historySearchText.isEmpty {
                Button {
                    historySearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12 * interfaceZoom.scale))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear transcript search")
            }
        }
        .padding(.horizontal, 9 * interfaceZoom.scale)
        .padding(.vertical, 6 * interfaceZoom.scale)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 8 * interfaceZoom.scale, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var detail: some View {
        switch sidebarSelection {
        case .history:
            if let result = transcriber.transcriptionResult {
                transcriptDetail(result)
            } else {
                ContentUnavailableView(
                    "Choose a transcript",
                    systemImage: "doc.text",
                    description: Text("Select a transcript from the sidebar to review it.")
                )
            }
        case .newTranscription, .none:
            if transcriber.isTranscribing {
                progressDetail
            } else if let result = transcriber.transcriptionResult {
                transcriptDetail(result)
            } else {
                newTranscriptionDetail
            }
        }
    }

    private var newTranscriptionDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("New transcription")
                        .font(.system(size: 30 * interfaceZoom.scale, weight: .bold, design: .rounded))

                    Label("All processing stays on this Mac", systemImage: "lock")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let error = transcriber.cliError {
                    if error.localizedCaseInsensitiveContains("model") {
                        ModelSetupView(installer: modelInstaller)
                    } else {
                        SetupRequiredView(message: error, onRetry: { Task { await transcriber.locateCLI() } })
                    }
                } else if !transcriber.cliReady {
                    PreparationStateView()
                } else {
                    inputSection
                }

                diagnostics
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var progressDetail: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Transcribing")
                .font(.system(size: 30 * interfaceZoom.scale, weight: .bold, design: .rounded))
            TranscriptionProgressView(
                fileName: fileName,
                audioDuration: audioDuration,
                phase: transcriber.transcriptionPhase,
                onCancel: { transcriber.cancel() }
            )
        }
        .frame(maxWidth: 720, alignment: .leading)
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func transcriptDetail(_ result: TranscriptionResult) -> some View {
        let entryID = currentHistoryEntryID
        let title = entryID
            .flatMap { id in history.entries.first(where: { $0.id == id })?.fileName }
            ?? fileName

        return TranscriptView(
            result: result,
            title: title,
            durationText: audioDuration.map(formattedDuration),
            languageName: selectedLanguageName,
            outputFormat: $outputFormat,
            grouping: $grouping,
            onCopy: copyToClipboard,
            onSave: exportResult,
            onRename: { newName in
                renameTranscript(id: entryID, to: newName)
            }
        )
        .id(entryID)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Transcription language")
                .accessibilityValue(selectedLanguageName)

                Spacer()
            }
            InputWorkspace(
                recorder: recorder,
                isReady: transcriber.cliReady,
                isTranscribing: transcriber.isTranscribing,
                elapsedTime: elapsedTime,
                onChooseFile: openFilePicker,
                onToggleRecording: toggleRecording,
                onStopRecording: stopRecording,
                onDiscardRecording: { showDiscardRecordingConfirmation = true },
                onDropFile: { setFile($0) }
            )
        }
        .accessibilityElement(children: .contain)
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
        transcriber.transcriptionResult = nil
        currentHistoryEntryID = nil
        if transcriber.isTranscribing {
            transcriber.cancel()
        }
        outputFormat = .plain
        grouping = 0.5
    }

    private func startNewTranscription() {
        clearFile()
        sidebarSelection = .newTranscription
    }

    private func beginSidebarRename(_ entry: HistoryEntry) {
        renameText = entry.fileName
        renameEntry = entry
        DispatchQueue.main.async {
            isSidebarRenameFocused = true
        }
    }

    private func commitSidebarRename(_ entry: HistoryEntry) {
        let trimmedName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            cancelSidebarRename()
            return
        }
        history.rename(entry, to: trimmedName)
        if currentHistoryEntryID == entry.id {
            fileName = trimmedName
        }
        renameEntry = nil
    }

    private func cancelSidebarRename() {
        renameEntry = nil
        renameText = ""
    }

    private func renameTranscript(id: UUID?, to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard let id,
              let entry = history.entries.first(where: { $0.id == id }) else { return }
        history.rename(entry, to: trimmedName)
        if currentHistoryEntryID == id {
            fileName = trimmedName
        }
    }

    private func openHistoryEntry(_ entry: HistoryEntry) {
        transcriber.transcriptionResult = entry.result
        fileName = entry.fileName
        selectedFile = nil
        audioDuration = entry.audioDuration
        outputFormat = .plain
        grouping = 0.5
        currentHistoryEntryID = entry.id
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
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
                    let entry = history.add(from: result, fileName: fileName, audioDuration: audioDuration)
                    currentHistoryEntryID = entry.id
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
        errorDetails = ErrorDetails(message: message)
    }

    private func retryTranscription() {
        guard let retryURL = retryFileURL else { return }
        selectedFile = retryURL
        fileName = retryFileDisplayName ?? retryURL.lastPathComponent
        let retryDisplayName = retryFileDisplayName
        retryFileURL = nil
        retryFileDisplayName = nil
        errorDetails = nil
        startTranscription(retryURL, displayName: retryDisplayName)
    }

    private func dismissErrorDetails() {
        retryFileURL = nil
        errorDetails = nil
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

private struct SidebarHistoryRow: View {
    @Environment(\.interfaceZoom) private var interfaceZoom
    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 10 * interfaceZoom) {
            Image(systemName: "doc.text")
                .font(.system(size: 13 * interfaceZoom))
                .frame(width: 16 * interfaceZoom)

            VStack(alignment: .leading, spacing: 2 * interfaceZoom) {
                Text(entry.fileName)
                    .font(.system(size: 13 * interfaceZoom))
                    .lineLimit(1)
                Text(entry.formattedDate)
                    .font(.system(size: 11 * interfaceZoom))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct PreparationStateView: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 3) {
                Text("Preparing offline transcription")
                    .font(.headline)
                Text("Checking the local transcription engine on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ErrorDetailsSheet: View {
    let message: String
    let canRetry: Bool
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Something went wrong")
                    .font(.title3.weight(.semibold))
                Text("The transcription could not be completed. The technical details below can be copied for support.")
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(message)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.quaternary)
            }

            HStack {
                Button("Copy Details") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message, forType: .string)
                }
                Spacer()
                Button("Close", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                if canRetry {
                    Button("Retry", action: retry)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: 640, maxWidth: 760, minHeight: 320, idealHeight: 460, maxHeight: 620)
    }
}
