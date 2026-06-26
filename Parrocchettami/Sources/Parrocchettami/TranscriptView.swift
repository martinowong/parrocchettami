import SwiftUI

struct TranscriptView: View {
    let result: TranscriptionResult
    @Binding var outputFormat: OutputFormat
    @Binding var grouping: Double
    let onCopy: (String) -> Void
    let onSave: (String, OutputFormat) -> Void

    @State private var editedText: String = ""
    @State private var hasEdits = false
    @State private var didCopy = false
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var undoStack: [String] = []
    @State private var isEditing = false
    @FocusState private var isFocused: Bool
    @FocusState private var isSearchFocused: Bool

    private var displayText: String {
        hasEdits ? editedText : formattedText
    }

    private var formattedText: String {
        result.formatted(as: outputFormat, grouping: grouping)
    }

    private var trimmedSearchText: String {
        TranscriptSearch.normalizedQuery(searchText)
    }

    private var searchTargetText: String {
        outputFormat == .plain ? displayText : formattedText
    }

    private var searchMatchCount: Int {
        TranscriptSearch.matchCount(in: searchTargetText, query: searchText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls
                .padding(16)

            Divider()

            if showSearch {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                Divider()
            }

            textArea
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.16))
        )
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .onChange(of: formattedText) { _, new in
            if !hasEdits { editedText = new }
        }
        .onAppear {
            if editedText.isEmpty { editedText = formattedText }
        }
        .onChange(of: showSearch) { _, isShown in
            if isShown {
                DispatchQueue.main.async { isSearchFocused = true }
            } else {
                searchText = ""
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in transcript", text: $searchText)
                .textFieldStyle(.plain)
                .font(.caption)
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
    }

    private var textArea: some View {
        ScrollView {
            Group {
                if outputFormat == .plain {
                    if isEditing {
                        TextEditor(text: $editedText)
                            .font(.system(size: 14))
                            .focused($isFocused)
                            .accessibilityLabel("Transcript editor")
                            .onChange(of: editedText) { old, new in
                                if new != old && new != formattedText {
                                    undoStack.append(old)
                                    if undoStack.count > 50 { undoStack.removeFirst() }
                                    hasEdits = true
                                }
                            }
                    } else {
                        Text(highlightedTranscript(displayText))
                            .font(.system(size: 14))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text(highlightedTranscript(formattedText))
                        .font(outputFormat == .srt
                              ? .system(size: 12, design: .monospaced)
                              : .system(size: 14))
                        .foregroundStyle(formattedText.isEmpty ? .secondary : .primary)
                }
            }
            .textSelection(.enabled)
            .accessibilityLabel("Transcript")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(minHeight: 220, idealHeight: 320, maxHeight: 440)
    }

    private func highlightedTranscript(_ text: String) -> AttributedString {
        TranscriptSearch.highlightedText(text, query: searchText)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    formatPicker
                    Spacer(minLength: 12)
                    actionButtons
                }

                VStack(alignment: .leading, spacing: 10) {
                    formatPicker
                    actionButtons
                }
            }

            if outputFormat != .plain {
                phraseLengthControl
            }
        }
    }

    private var formatPicker: some View {
        HStack(spacing: 8) {
            Picker("Format", selection: $outputFormat) {
                ForEach(OutputFormat.allCases, id: \.self) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 280)
            .accessibilityLabel("Transcript format")
            .onChange(of: outputFormat) { _, _ in
                hasEdits = false
                isEditing = false
                editedText = formattedText
                undoStack.removeAll()
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            if outputFormat == .plain {
                Button(action: {
                    isEditing.toggle()
                    if isEditing && !hasEdits { editedText = formattedText }
                }) {
                    Image(systemName: isEditing ? "pencil.slash" : "pencil")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 34, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(isEditing ? "Done editing" : "Edit transcript")
                .accessibilityLabel(isEditing ? "Done editing transcript" : "Edit transcript")
            }

            if outputFormat == .plain && isEditing && hasEdits {
                Button(action: undo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 34, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(undoStack.isEmpty)
                .help("Undo edit")
                .accessibilityLabel("Undo transcript edit")

                Button(action: resetEdits) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 34, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Reset to original")
                .accessibilityLabel("Reset transcript to original")
            }

            Button(action: toggleSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 34, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("f", modifiers: .command)
            .help("Find in transcript (⌘F)")
            .accessibilityLabel(showSearch ? "Hide transcript search" : "Find in transcript")

            Button {
                onCopy(displayText)
                didCopy = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { didCopy = false }
            } label: {
                Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Copies the current transcript text to the clipboard.")

            Button {
                onSave(displayText, outputFormat)
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Exports the current transcript in the selected format.")
        }
    }

    private var phraseLengthControl: some View {
        HStack(spacing: 10) {
            Label("Phrase length", systemImage: "text.word.spacing")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()

            Slider(value: $grouping, in: 0...1)
                .accessibilityLabel("Phrase length")
                .accessibilityValue(phraseLengthLabel)

            Text(phraseLengthLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
        }
    }

    private var phraseLengthLabel: String {
        switch grouping {
        case ..<0.34: return "Short"
        case 0.67...: return "Long"
        default: return "Medium"
        }
    }

    private func toggleSearch() {
        showSearch.toggle()
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        editedText = previous
        if undoStack.isEmpty { hasEdits = false }
    }

    private func resetEdits() {
        editedText = formattedText
        hasEdits = false
        isEditing = false
        undoStack.removeAll()
    }
}
