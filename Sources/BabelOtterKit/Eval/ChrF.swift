import Foundation

/// Character n-gram F-score (Popovic 2015): n = 1...6, beta = 2.
///
/// Precision and recall are averaged over the orders first, then combined,
/// as in the original definition. Whitespace is ignored, so a translation is
/// not rewarded or punished for spacing.
enum ChrF {

    static let maxOrder = 6
    static let beta = 2.0

    static func score(hypothesis: String, reference: String) -> Double {
        let hypothesisCharacters = Array(hypothesis.filter { !$0.isWhitespace })
        let referenceCharacters = Array(reference.filter { !$0.isWhitespace })
        var precisions: [Double] = []
        var recalls: [Double] = []
        for order in 1...maxOrder {
            let hypothesisGrams = grams(hypothesisCharacters, order)
            let referenceGrams = grams(referenceCharacters, order)
            let hypothesisTotal = hypothesisGrams.values.reduce(0, +)
            let referenceTotal = referenceGrams.values.reduce(0, +)
            if hypothesisTotal == 0 || referenceTotal == 0 { continue }
            let matched = hypothesisGrams.reduce(0) { $0 + min($1.value, referenceGrams[$1.key] ?? 0) }
            precisions.append(Double(matched) / Double(hypothesisTotal))
            recalls.append(Double(matched) / Double(referenceTotal))
        }
        guard !precisions.isEmpty else { return 0 }
        let precision = precisions.reduce(0, +) / Double(precisions.count)
        let recall = recalls.reduce(0, +) / Double(recalls.count)
        let weight = beta * beta
        let denominator = weight * precision + recall
        guard denominator > 0 else { return 0 }
        return 100 * (1 + weight) * precision * recall / denominator
    }

    static func grams(_ characters: [Character], _ order: Int) -> [String: Int] {
        var counts: [String: Int] = [:]
        guard characters.count >= order else { return counts }
        for start in 0...(characters.count - order) {
            counts[String(characters[start..<(start + order)]), default: 0] += 1
        }
        return counts
    }
}
