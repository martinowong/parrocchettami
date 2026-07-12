import Foundation
import SwiftUI

enum TranscriptSearch {
    static func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matchCount(in text: String, query: String) -> Int {
        matchRanges(in: text, query: query).count
    }

    static func matchRanges(in text: String, query: String) -> [Range<String.Index>] {
        let query = normalizedQuery(query)
        guard !query.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchStart..<text.endIndex
              ) {
            ranges.append(range)
            searchStart = range.upperBound
        }

        return ranges
    }

    static func highlightedText(_ text: String, query: String) -> AttributedString {
        let query = normalizedQuery(query)
        var attributed = AttributedString(text)
        guard !query.isEmpty else { return attributed }

        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex,
              let range = attributed[searchStart..<attributed.endIndex].range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive]
              ) {
            attributed[range].backgroundColor = Color.accentColor.opacity(0.22)
            attributed[range].foregroundColor = .primary
            searchStart = range.upperBound
        }

        return attributed
    }
}
