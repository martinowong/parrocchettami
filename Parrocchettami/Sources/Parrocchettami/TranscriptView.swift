import SwiftUI

struct TranscriptView: View {
    @Environment(\.interfaceZoom) private var interfaceZoom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let result: TranscriptionResult
    let originalText: String
    let title: String
    let durationText: String?
    let languageName: String
    let initialRichTextData: Data?
    @Binding var outputFormat: OutputFormat
    @Binding var grouping: Double
    let onCopy: (String) -> Void
    let onSave: (String, OutputFormat, Data?) -> Void
    let onRename: (String) -> Void
    let onPersistEdits: (String, Data?) -> Void
    let onPresentationChange: (OutputFormat, Double) -> Void
    var tutorialStep: TutorialStep? = nil

    @State private var editedText: String = ""
    @State private var hasEdits = false
    @State private var didCopy = false
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var undoStack: [String] = []
    @State private var isEditing = false
    @State private var pendingRichTextAction: RichTextAction?
    @State private var richTextData: Data?
    @State private var isRenamingTitle = false
    @State private var titleDraft = ""
    @State private var showsCharacterCount = false
    @State private var showConfidenceReview = false
    @State private var isSaving = false
    @State private var lastSavedText = ""
    @State private var lastSavedRichTextData: Data?
    @State private var autosaveTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isTitleFocused: Bool

    private var displayText: String {
        hasEdits ? editedText : formattedText
    }

    private var formattedText: String {
        result.formatted(as: outputFormat, grouping: grouping)
    }

    private var isEditableFormat: Bool {
        outputFormat == .markdown || outputFormat == .rtf
    }

    private var trimmedSearchText: String {
        TranscriptSearch.normalizedQuery(searchText)
    }

    private var searchTargetText: String {
        isEditableFormat ? displayText : formattedText
    }

    private var searchMatchCount: Int {
        TranscriptSearch.matchCount(in: searchTargetText, query: searchText)
    }

    private var lowConfidenceCount: Int {
        ConfidenceReview.lowConfidenceWords(in: result.words).count
    }

    private var confidenceReviewIsVisible: Bool {
        showConfidenceReview || tutorialStep == .review
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            documentControls
                .padding(.horizontal, 30)
                .padding(.top, 18)

            if outputFormat == .timestamped || outputFormat == .srt {
                phraseLengthControl
                    .padding(.horizontal, 30)
                    .padding(.top, 12)
            }

            textArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .focusedSceneValue(\.findInTranscriptAction, toggleSearch)
        .onChange(of: formattedText) { _, new in
            if !hasEdits { editedText = new }
        }
        .onAppear {
            if editedText.isEmpty { editedText = formattedText }
            if richTextData == nil { richTextData = initialRichTextData }
            lastSavedText = editedText
            lastSavedRichTextData = richTextData
            hasEdits = editedText != originalText || initialRichTextData != nil
        }
        .onChange(of: title) { _, newTitle in
            if !isRenamingTitle {
                titleDraft = newTitle
            }
        }
        .onChange(of: showSearch) { _, isShown in
            if isShown {
                DispatchQueue.main.async { isSearchFocused = true }
            } else {
                searchText = ""
            }
        }
        .onChange(of: outputFormat) { _, newFormat in
            onPresentationChange(newFormat, grouping)
        }
        .onChange(of: grouping) { _, newGrouping in
            onPresentationChange(outputFormat, newGrouping)
        }
        .onDisappear {
            autosaveTask?.cancel()
            persistEditsIfNeeded()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8 * interfaceZoom) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13 * interfaceZoom, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Find in transcript", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12 * interfaceZoom))
                .focused($isSearchFocused)
                .accessibilityLabel("Find in transcript")
            if !trimmedSearchText.isEmpty {
                Text(searchMatchCount == 1 ? "1 match" : "\(searchMatchCount) matches")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(searchMatchCount == 0 ? .red : .secondary)
                    .fixedSize()
                    .accessibilityLabel(searchMatchCount == 1 ? "1 match" : "\(searchMatchCount) matches")
            }
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12 * interfaceZoom)
        .padding(.vertical, 8 * interfaceZoom)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var textArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                documentHeader
                Divider()
                    .padding(.top, 18)
                    .padding(.bottom, 22)

                Group {
                    if isEditableFormat && (!confidenceReviewIsVisible || isEditing) {
                        RichTextEditor(
                            text: $editedText,
                            action: $pendingRichTextAction,
                            isEditable: isEditing,
                            searchText: searchText,
                            allowsRichText: outputFormat == .rtf,
                            initialRTFData: initialRichTextData,
                            onFormattingChange: {
                                hasEdits = true
                                scheduleAutosave()
                            },
                            onRichTextChange: {
                                richTextData = $0
                                scheduleAutosave()
                            }
                        )
                            .focused($isFocused)
                            .accessibilityLabel(isEditing ? "Transcript editor" : "Transcript")
                            .onChange(of: editedText) { old, new in
                                if new != old {
                                    undoStack.append(old)
                                    if undoStack.count > 50 { undoStack.removeFirst() }
                                    hasEdits = new != originalText
                                    scheduleAutosave()
                                }
                            }
                            .frame(minHeight: 280)
                    } else {
                        transcriptText(isEditableFormat ? displayText : formattedText)
                    }
                }
                .textSelection(.enabled)
                .accessibilityLabel("Transcript")
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.11), lineWidth: 1)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(minHeight: 320, maxHeight: .infinity)
    }

    private var documentHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: outputFormat == .srt ? "captions.bubble" : "text.quote")
                .font(.system(size: 18 * interfaceZoom, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 34 * interfaceZoom, height: 34 * interfaceZoom)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                if isRenamingTitle {
                    TextField("Transcript title", text: $titleDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13 * interfaceZoom, weight: .semibold))
                        .focused($isTitleFocused)
                        .onSubmit(completeTitleRename)
                        .onExitCommand(perform: cancelTitleRename)
                        .frame(maxWidth: 420)
                } else {
                    Button(action: beginTitleRename) {
                        Text(title.isEmpty ? "Transcript" : title)
                            .font(.system(size: 13 * interfaceZoom, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .buttonStyle(.plain)
                    .help("Click to rename")
                }
                documentMetadata
            }

            Spacer()

            if hasEdits {
                Label(isSaving ? "Saving…" : "Saved", systemImage: isSaving ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                    .font(.system(size: 11 * interfaceZoom, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary.opacity(0.7), in: Capsule())
            }
        }
    }

    private var documentMetadata: some View {
        HStack(spacing: 5 * interfaceZoom) {
            Button(action: toggleCountMetric) {
                ZStack(alignment: .leading) {
                    if showsCharacterCount {
                        Text(characterCountLabel)
                            .transition(countTransition)
                    } else {
                        Text(wordCountLabel)
                            .transition(countTransition)
                    }
                }
                .animation(countAnimation, value: showsCharacterCount)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(showsCharacterCount ? "Show word count" : "Show character count")
            .accessibilityLabel(showsCharacterCount ? "Character count" : "Word count")
            .accessibilityValue(showsCharacterCount ? characterCountLabel : wordCountLabel)

            if let durationText {
                metadataSeparator
                Text(durationText)
            }

            metadataSeparator
            Text(languageName)

            metadataSeparator
            Text(outputFormat.rawValue)
        }
        .font(.system(size: 11 * interfaceZoom))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var metadataSeparator: some View {
        Text("·")
            .accessibilityHidden(true)
    }

    private var countTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: 0.86, anchor: .center).combined(with: .opacity)
    }

    private var countAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.78)
    }

    private func transcriptText(_ text: String) -> some View {
        Text(highlightedTranscript(text))
            .font(outputFormat == .srt
                  ? .system(size: 12 * interfaceZoom, design: .monospaced)
                  : .system(size: 15 * interfaceZoom))
            .lineSpacing((outputFormat == .srt ? 2 : 5) * interfaceZoom)
            .foregroundStyle(text.isEmpty ? .secondary : .primary)
            .frame(maxWidth: .infinity, minHeight: 280, alignment: .topLeading)
    }

    private var copyButton: some View {
        Button(action: copyTranscript) {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .frame(width: 18 * interfaceZoom, height: 18 * interfaceZoom)
        }
        .modifier(AdaptiveGlassButtonStyle())
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .popButtonPressEffect()
        .tint(didCopy ? .green : .accentColor)
        .accessibilityLabel(didCopy ? "Transcript copied" : "Copy transcript to clipboard")
        .accessibilityHint("Copies the current transcript text to the clipboard.")
        .help("Copy transcript to clipboard")
    }

    private var formattingButtons: some View {
        HStack(spacing: 4) {
            formatButton("bold", label: "Bold", action: .bold)
            formatButton("italic", label: "Italic", action: .italic)
            formatButton("underline", label: "Underline", action: .underline)
        }
    }

    private func formatButton(_ symbol: String, label: String, action: RichTextAction) -> some View {
        Button {
            pendingRichTextAction = action
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13 * interfaceZoom, weight: .semibold))
                .frame(width: 26 * interfaceZoom, height: 26 * interfaceZoom)
        }
        .modifier(AdaptiveGlassButtonStyle())
        .buttonBorderShape(.roundedRectangle(radius: 7))
        .popButtonPressEffect()
        .accessibilityLabel(label)
        .help(label)
    }

    private func highlightedTranscript(_ text: String) -> AttributedString {
        var attributed = confidenceReviewIsVisible
            ? ConfidenceReview.highlightedText(text, words: result.words)
            : AttributedString(text)
        TranscriptSearch.applyHighlights(to: &attributed, query: searchText)
        return attributed
    }

    @ViewBuilder
    private var documentControls: some View {
        if #available(macOS 26.0, *) {
            documentControlsContent
        } else {
            documentControlsContent
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.07), radius: 12, y: 5)
        }
    }

    private var documentControlsContent: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                formatSelector

                Button {
                    onSave(displayText, outputFormat, richTextData)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.system(size: 13 * interfaceZoom))
                }
                .modifier(AdaptiveGlassButtonStyle())
                .popButtonPressEffect()
                .help("Export in the selected format")
                .accessibilityHint("Exports the current transcript in the selected format.")
                .tutorialTarget(.export)

                Spacer()

                if isEditableFormat {
                    Button(action: toggleEditing) {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                            .font(.system(size: 13 * interfaceZoom, weight: .medium))
                            .frame(width: 18 * interfaceZoom, height: 18 * interfaceZoom)
                    }
                    .modifier(AdaptiveGlassButtonStyle())
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .popButtonPressEffect()
                    .help(isEditing ? "Done editing" : "Edit transcript")
                    .accessibilityLabel(isEditing ? "Done editing transcript" : "Edit transcript")
                }

                if lowConfidenceCount > 0 {
                    Button {
                        withAnimation(controlAnimation) {
                            showConfidenceReview.toggle()
                            if showConfidenceReview { isEditing = false }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                            Text("\(lowConfidenceCount)")
                                .monospacedDigit()
                        }
                        .font(.system(size: 12 * interfaceZoom, weight: .medium))
                    }
                    .modifier(AdaptiveGlassButtonStyle())
                    .popButtonPressEffect()
                    .tint(confidenceReviewIsVisible ? .orange : .accentColor)
                    .help("Highlight words below 72% confidence")
                    .accessibilityLabel(confidenceReviewIsVisible ? "Hide low-confidence word highlights" : "Highlight \(lowConfidenceCount) low-confidence words")
                    .tutorialTarget(.confidence)
                }

                Button(action: toggleSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13 * interfaceZoom, weight: .medium))
                        .frame(width: 18 * interfaceZoom, height: 18 * interfaceZoom)
                }
                .modifier(AdaptiveGlassButtonStyle())
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .popButtonPressEffect()
                .keyboardShortcut("f", modifiers: .command)
                .help("Find in transcript (⌘F)")
                .accessibilityLabel(showSearch ? "Hide transcript search" : "Find in transcript")

                copyButton
            }

            if (isEditableFormat && isEditing) || showSearch {
                Divider()

                contextualToolsRow
                    .transition(.opacity.combined(with: .offset(y: -5 * interfaceZoom)))
            }
        }
        .padding(10 * interfaceZoom)
        .animation(controlAnimation, value: isEditing)
        .animation(controlAnimation, value: showSearch)
    }

    private var contextualToolsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10 * interfaceZoom) {
                if isEditableFormat && isEditing {
                    editingTools
                        .transition(.opacity)
                }

                Spacer(minLength: 12 * interfaceZoom)

                if showSearch {
                    searchBar
                        .frame(minWidth: 140 * interfaceZoom, idealWidth: 250 * interfaceZoom, maxWidth: 320 * interfaceZoom)
                        .layoutPriority(1)
                        .transition(.opacity.combined(with: .offset(x: 8 * interfaceZoom)))
                }
            }

            VStack(alignment: .leading, spacing: 8 * interfaceZoom) {
                if isEditableFormat && isEditing {
                    editingTools
                }
                if showSearch {
                    searchBar
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var editingTools: some View {
        HStack(spacing: 8) {
            if outputFormat == .rtf {
                formattingButtons

                Divider()
                    .frame(height: 22)
            }

            Button(action: undo) {
                Image(systemName: "arrow.uturn.backward")
            }
            .modifier(AdaptiveGlassButtonStyle())
            .popButtonPressEffect()
            .disabled(undoStack.isEmpty)
            .help("Undo edit")
            .accessibilityLabel("Undo transcript edit")

            Button(action: resetEdits) {
                Image(systemName: "arrow.counterclockwise")
            }
            .modifier(AdaptiveGlassButtonStyle())
            .popButtonPressEffect()
            .disabled(!hasEdits)
            .help("Reset to original")
            .accessibilityLabel("Reset transcript to original")
        }
    }

    private var controlAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.24)
    }

    @ViewBuilder
    private var formatSelector: some View {
        Picker("Format", selection: $outputFormat) {
            ForEach(OutputFormat.allCases, id: \.self) { format in
                Text(format.rawValue).tag(format)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .font(.system(size: 13 * interfaceZoom))
        .frame(width: 360 * interfaceZoom)
        .accessibilityLabel("Transcript format")
        .onChange(of: outputFormat) { _, newFormat in
            resetForFormat(newFormat)
        }
    }

    private var phraseLengthControl: some View {
        HStack(spacing: 10) {
            Label("Phrase length", systemImage: "text.word.spacing")
                .font(.system(size: 11 * interfaceZoom))
                .foregroundStyle(.secondary)
                .fixedSize()

            Slider(value: $grouping, in: 0...1)
                .accessibilityLabel("Phrase length")
                .accessibilityValue(phraseLengthLabel)

            Text(phraseLengthLabel)
                .font(.system(size: 11 * interfaceZoom))
                .foregroundStyle(.secondary)
                .frame(width: 58 * interfaceZoom, alignment: .trailing)
        }
        .frame(maxWidth: 620, alignment: .leading)
    }

    private var wordCount: Int {
        displayText.split(whereSeparator: { $0.isWhitespace }).count
    }

    private var characterCount: Int {
        displayText.count
    }

    private var wordCountLabel: String {
        wordCount == 1 ? "1 word" : "\(wordCount) words"
    }

    private var characterCountLabel: String {
        characterCount == 1 ? "1 character" : "\(characterCount) characters"
    }

    private var phraseLengthLabel: String {
        switch grouping {
        case ..<0.34: return "Short"
        case 0.67...: return "Long"
        default: return "Medium"
        }
    }

    private func toggleSearch() {
        withAnimation(controlAnimation) {
            showSearch.toggle()
        }
    }

    private func toggleCountMetric() {
        withAnimation(countAnimation) {
            showsCharacterCount.toggle()
        }
    }

    private func selectFormat(_ format: OutputFormat) {
        guard outputFormat != format else { return }
        withAnimation(.snappy(duration: 0.28)) {
            outputFormat = format
        }
        resetForFormat(format)
    }

    private func resetForFormat(_ format: OutputFormat) {
        isEditing = false
        editedText = result.formatted(as: format, grouping: grouping)
        hasEdits = isEditableFormat && editedText != originalText
        richTextData = nil
        undoStack.removeAll()
        onPresentationChange(format, grouping)
    }

    private func toggleEditing() {
        withAnimation(controlAnimation) {
            isEditing.toggle()
            if isEditing && !hasEdits {
                editedText = formattedText
            }
        }
        if isEditing {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }

    private func beginTitleRename() {
        titleDraft = title
        isRenamingTitle = true
        DispatchQueue.main.async {
            isTitleFocused = true
        }
    }

    private func completeTitleRename() {
        let trimmedTitle = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            cancelTitleRename()
            return
        }
        onRename(trimmedTitle)
        isRenamingTitle = false
    }

    private func cancelTitleRename() {
        titleDraft = title
        isRenamingTitle = false
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        editedText = previous
        hasEdits = editedText != originalText
    }

    private func resetEdits() {
        editedText = originalText
        pendingRichTextAction = .resetFormatting
        richTextData = nil
        hasEdits = false
        isEditing = false
        undoStack.removeAll()
        scheduleAutosave()
    }

    private func copyTranscript() {
        onCopy(displayText)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            didCopy = false
        }
    }

    private func scheduleAutosave() {
        guard isEditableFormat else { return }
        isSaving = true
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            persistEditsIfNeeded()
        }
    }

    private func persistEditsIfNeeded() {
        guard editedText != lastSavedText || richTextData != lastSavedRichTextData else {
            isSaving = false
            return
        }
        onPersistEdits(editedText, richTextData)
        lastSavedText = editedText
        lastSavedRichTextData = richTextData
        isSaving = false
    }
}

private struct AdaptiveGlassButtonStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
