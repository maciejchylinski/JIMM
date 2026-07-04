import Foundation

/// Shared matching for exercise name search (Add / Replace panels).
enum ExerciseSearchMatching {
    private enum MatchBucket: Int {
        case exactName = 0
        case exactAlias = 1
        case prefixName = 2
        case prefixAlias = 3
        case containsName = 4
        case containsAlias = 5
        case allTokensAcrossFields = 6
    }

    private struct ScoredExercise {
        let exercise: Exercise
        let bucket: MatchBucket
        let secondaryRank: Int
        let tertiaryRank: String
    }

    static func trimmedQuery(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ranked suggestions using visible names first, then hidden aliases/tags.
    static func rankedSuggestions(in exercises: [Exercise], query: String, limit: Int = 12) -> [Exercise] {
        let normalizedQuery = normalizeForSearch(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let scored = exercises.compactMap { exercise -> ScoredExercise? in
            guard let bucket = bestBucket(for: exercise, normalizedQuery: normalizedQuery) else { return nil }
            let normalizedName = normalizeForSearch(exercise.name)
            return ScoredExercise(
                exercise: exercise,
                bucket: bucket,
                secondaryRank: secondaryRank(for: normalizedName, normalizedQuery: normalizedQuery),
                tertiaryRank: normalizedName
            )
        }

        return scored
            .sorted {
                if $0.bucket.rawValue != $1.bucket.rawValue {
                    return $0.bucket.rawValue < $1.bucket.rawValue
                }
                if $0.secondaryRank != $1.secondaryRank {
                    return $0.secondaryRank < $1.secondaryRank
                }
                return $0.tertiaryRank < $1.tertiaryRank
            }
            .prefix(limit)
            .map(\.exercise)
    }

    /// Exact match (trimmed, case-insensitive) — used to hide “create new” when an exercise already exists.
    static func isExactNameMatch(exerciseName: String, query: String) -> Bool {
        let q = trimmedQuery(query)
        guard !q.isEmpty else { return false }
        let n = trimmedQuery(exerciseName)
        return n.caseInsensitiveCompare(q) == .orderedSame
    }

    static func hasExactMatch(in exercises: [Exercise], query: String) -> Bool {
        exercises.contains { isExactNameMatch(exerciseName: $0.name, query: query) }
    }

    private static func bestBucket(for exercise: Exercise, normalizedQuery: String) -> MatchBucket? {
        let normalizedName = normalizeForSearch(exercise.name)
        if normalizedName == normalizedQuery { return .exactName }
        if normalizedName.hasPrefix(normalizedQuery) { return .prefixName }
        if normalizedName.contains(normalizedQuery) { return .containsName }

        let aliases = aliasesForSearch(exercise.searchMetadata)
        if aliases.contains(normalizedQuery) { return .exactAlias }
        if aliases.contains(where: { $0.hasPrefix(normalizedQuery) }) { return .prefixAlias }
        if aliases.contains(where: { $0.contains(normalizedQuery) }) { return .containsAlias }

        let queryTokens = normalizedQuery.split(separator: " ").map(String.init)
        if !queryTokens.isEmpty {
            let combined = ([normalizedName] + aliases).joined(separator: " ")
            let allTokensMatch = queryTokens.allSatisfy { token in combined.contains(token) }
            if allTokensMatch {
                return .allTokensAcrossFields
            }
        }
        return nil
    }

    /// Lower is better: shorter base names rank above longer variants (Assisted, Weighted, etc.).
    private static func secondaryRank(for normalizedName: String, normalizedQuery: String) -> Int {
        var rank = normalizedName.count
        rank += modifierPenalty(for: normalizedName) * 100
        if normalizedName == normalizedQuery {
            rank -= 1_000
        } else if normalizedName.hasPrefix(normalizedQuery) {
            rank -= 100
        }
        return rank
    }

    private static func modifierPenalty(for normalizedName: String) -> Int {
        let modifiers = [
            "assisted",
            "weighted",
            "resistance band",
            "band",
            "machine",
            "cable",
            "smith",
            "seated",
            "incline",
            "decline",
            "wide grip",
            "wide",
            "narrow",
            "single arm",
            "one arm",
            "neutral grip",
            "close grip",
            "archer",
            "plyo",
            "clapping",
            "reverse grip"
        ]
        for (index, modifier) in modifiers.enumerated() {
            if normalizedName.contains(modifier) {
                return index + 1
            }
        }
        return 0
    }

    nonisolated private static func aliasesForSearch(_ raw: String) -> [String] {
        raw
            .components(separatedBy: .newlines)
            .map { normalizeForSearch($0) }
            .filter { !$0.isEmpty }
    }

    nonisolated private static func normalizeForSearch(_ raw: String) -> String {
        let folded = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let cleanedScalars = folded.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " }
        let cleaned = String(cleanedScalars)
        return cleaned
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
