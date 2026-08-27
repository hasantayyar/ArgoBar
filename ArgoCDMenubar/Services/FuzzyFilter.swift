import Foundation

enum FuzzyFilter {
    static func matches(query: String, fields: [String]) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let searchableFields = fields
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "n/a" }
        guard !searchableFields.isEmpty else { return false }

        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        return tokens.allSatisfy { token in
            searchableFields.contains { fieldMatches(token, in: $0) }
        }
    }

    static func relevanceScore(query: String, weightedFields: [(text: String, weight: Int)]) -> Int {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        return weightedFields.compactMap { entry -> Int? in
            let field = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !field.isEmpty, field != "n/a" else { return nil }

            let subsequence = subsequenceScore(trimmed, in: field)
            if subsequence > 0 {
                return subsequence * entry.weight
            }
            if field.localizedCaseInsensitiveContains(trimmed) {
                return 10 * entry.weight
            }
            return nil
        }.max() ?? 0
    }

    private static func fieldMatches(_ token: String, in field: String) -> Bool {
        subsequenceScore(token, in: field) > 0
            || field.localizedCaseInsensitiveContains(token)
    }

    private static func subsequenceScore(_ query: String, in text: String) -> Int {
        let queryChars = Array(query.lowercased())
        let textChars = Array(text.lowercased())
        guard !queryChars.isEmpty else { return 0 }

        var score = 0
        var queryIndex = 0
        var previousMatchIndex: Int?

        for (textIndex, char) in textChars.enumerated() {
            guard queryIndex < queryChars.count, char == queryChars[queryIndex] else {
                continue
            }

            score += 1

            if let previousMatchIndex, previousMatchIndex == textIndex - 1 {
                score += 2
            }

            if textIndex == 0 || isBoundary(textChars[textIndex - 1]) {
                score += 1
            }

            previousMatchIndex = textIndex
            queryIndex += 1
        }

        return queryIndex == queryChars.count ? score : 0
    }

    private static func isBoundary(_ char: Character) -> Bool {
        char.isWhitespace || char == "-" || char == "/" || char == "_" || char == "."
    }
}
