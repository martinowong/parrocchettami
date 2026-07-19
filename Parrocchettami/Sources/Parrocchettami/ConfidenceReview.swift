import Foundation
import SwiftUI

enum ConfidenceReview {
    static let defaultThreshold = 0.72

    static func lowConfidenceWords(
        in words: [TimedWord],
        threshold: Double = defaultThreshold
    ) -> [TimedWord] {
        words.filter { $0.conf < threshold }
    }

    static func ranges(
        in text: String,
        words: [TimedWord],
        threshold: Double = defaultThreshold
    ) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex

        for word in words {
            let token = word.w.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, searchStart < text.endIndex else { continue }

            let searchRange = searchStart..<text.endIndex
            guard let range = text.range(
                of: token,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            ) else { continue }

            if word.conf < threshold {
                ranges.append(range)
            }
            searchStart = range.upperBound
        }

        return ranges
    }

    static func highlightedText(
        _ text: String,
        words: [TimedWord],
        threshold: Double = defaultThreshold
    ) -> AttributedString {
        var attributed = AttributedString(text)
        var searchStart = attributed.startIndex

        for word in words {
            let token = word.w.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, searchStart < attributed.endIndex,
                  let range = attributed[searchStart..<attributed.endIndex].range(
                    of: token,
                    options: [.caseInsensitive, .diacriticInsensitive]
                  ) else { continue }

            if word.conf < threshold {
                attributed[range].backgroundColor = Color.orange.opacity(0.24)
                attributed[range].foregroundColor = .primary
            }
            searchStart = range.upperBound
        }

        return attributed
    }
}
