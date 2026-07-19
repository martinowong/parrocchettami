import AppKit
import SwiftUI

enum RichTextAction: Equatable {
    case bold
    case italic
    case underline
    case resetFormatting
}

struct RichTextEditor: NSViewRepresentable {
    @Environment(\.interfaceZoom) private var interfaceZoom

    @Binding var text: String
    @Binding var action: RichTextAction?
    let isEditable: Bool
    let searchText: String
    let allowsRichText: Bool
    let initialRTFData: Data?
    let onFormattingChange: () -> Void
    let onRichTextChange: (Data) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = allowsRichText
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = NSFont.systemFont(ofSize: 15 * interfaceZoom)
        if allowsRichText,
           let initialRTFData,
           let attributed = NSAttributedString(rtf: initialRTFData, documentAttributes: nil) {
            textView.textStorage?.setAttributedString(attributed)
        } else {
            textView.string = text
        }
        context.coordinator.configureParagraphStyle(for: textView)
        context.coordinator.updateSearchHighlights(in: textView)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.parent = self
        textView.isEditable = isEditable
        textView.isRichText = allowsRichText

        if textView.string != text {
            context.coordinator.isUpdatingFromSwiftUI = true
            textView.string = text
            context.coordinator.applyDefaultAttributes(to: textView)
            context.coordinator.isUpdatingFromSwiftUI = false
        }

        if let action {
            if context.coordinator.handledAction != action {
                context.coordinator.handledAction = action
                context.coordinator.apply(action, to: textView)
                DispatchQueue.main.async {
                    self.action = nil
                }
            }
        } else {
            context.coordinator.handledAction = nil
        }

        context.coordinator.updateSearchHighlights(in: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        var isUpdatingFromSwiftUI = false
        var handledAction: RichTextAction?
        private var lastSelectedRange = NSRange(location: NSNotFound, length: 0)

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingFromSwiftUI,
                  let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            publishRichText(from: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            if range.length > 0 {
                lastSelectedRange = range
            }
        }

        func configureParagraphStyle(for textView: NSTextView) {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 5 * parent.interfaceZoom
            paragraphStyle.paragraphSpacing = 0
            textView.defaultParagraphStyle = paragraphStyle
            textView.typingAttributes = defaultAttributes(paragraphStyle: paragraphStyle)
            applyDefaultAttributes(to: textView)
        }

        func applyDefaultAttributes(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let range = NSRange(location: 0, length: storage.length)
            guard range.length > 0 else { return }
            storage.addAttributes(defaultAttributes(paragraphStyle: textView.defaultParagraphStyle ?? NSParagraphStyle()), range: range)
        }

        func apply(_ action: RichTextAction, to textView: NSTextView) {
            if action == .resetFormatting {
                applyDefaultAttributes(to: textView)
                return
            }

            let currentRange = textView.selectedRange()
            let selectedRange = currentRange.length > 0 ? currentRange : lastSelectedRange
            guard selectedRange.length > 0,
                  selectedRange.location != NSNotFound,
                  let storage = textView.textStorage,
                  NSMaxRange(selectedRange) <= storage.length else { return }

            switch action {
            case .bold:
                toggleTrait(.bold, in: storage, range: selectedRange, textView: textView)
            case .italic:
                toggleTrait(.italic, in: storage, range: selectedRange, textView: textView)
            case .underline:
                let hasUnderline = storage.attribute(.underlineStyle, at: selectedRange.location, effectiveRange: nil) as? Int ?? 0
                if hasUnderline == 0 {
                    storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: selectedRange)
                } else {
                    storage.removeAttribute(.underlineStyle, range: selectedRange)
                }
            case .resetFormatting:
                break
            }

            if action != .resetFormatting {
                parent.onFormattingChange()
                publishRichText(from: textView)
            }
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                textView.setSelectedRange(selectedRange)
            }
        }

        func publishRichText(from textView: NSTextView) {
            let range = NSRange(location: 0, length: textView.string.utf16.count)
            guard let data = textView.rtf(from: range) else { return }
            parent.onRichTextChange(data)
        }

        private func toggleTrait(
            _ trait: NSFontDescriptor.SymbolicTraits,
            in storage: NSTextStorage,
            range: NSRange,
            textView: NSTextView
        ) {
            var everyRunHasTrait = true
            storage.enumerateAttribute(.font, in: range) { value, _, _ in
                let font = value as? NSFont
                    ?? textView.font
                    ?? NSFont.systemFont(ofSize: 15 * parent.interfaceZoom)
                if !font.fontDescriptor.symbolicTraits.contains(trait) {
                    everyRunHasTrait = false
                }
            }

            storage.enumerateAttribute(.font, in: range) { value, runRange, _ in
                let currentFont = value as? NSFont
                    ?? textView.font
                    ?? NSFont.systemFont(ofSize: 15 * parent.interfaceZoom)
                var traits = currentFont.fontDescriptor.symbolicTraits
                if everyRunHasTrait {
                    traits.remove(trait)
                } else {
                    traits.insert(trait)
                }
                let descriptor = currentFont.fontDescriptor.withSymbolicTraits(traits)
                let font = NSFont(descriptor: descriptor, size: currentFont.pointSize) ?? currentFont
                storage.addAttribute(.font, value: font, range: runRange)
            }
        }

        func updateSearchHighlights(in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.removeAttribute(.backgroundColor, range: fullRange)

            for range in TranscriptSearch.matchRanges(in: textView.string, query: parent.searchText) {
                storage.addAttribute(
                    .backgroundColor,
                    value: NSColor.controlAccentColor.withAlphaComponent(0.22),
                    range: NSRange(range, in: textView.string)
                )
            }
        }

        private func defaultAttributes(paragraphStyle: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
            [
                .font: NSFont.systemFont(ofSize: 15 * parent.interfaceZoom),
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: paragraphStyle
            ]
        }
    }
}
