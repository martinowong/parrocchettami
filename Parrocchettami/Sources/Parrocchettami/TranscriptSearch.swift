import Foundation
import SwiftUI

enum TranscriptSearch {
    static func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matchCount(in text: String, query: String) -> Int {
        let query = normalizedQuery(query)
        guard !query.isEmpty else { return 0 }

        var count = 0
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchStart..<text.endIndex
              ) {
            count += 1
            searchStart = range.upperBound
        }

        return count
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
            attributed[range].backgroundColor = Color.yellow.opacity(0.35)
            searchStart = range.upperBound
        }

        return attributed
    }
}
