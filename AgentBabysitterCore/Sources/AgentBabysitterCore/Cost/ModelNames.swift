import Foundation

/// Human labels for model ids in the stats window: "claude-opus-4-8" →
/// "Opus 4.8". Only Claude ids are transformed (their shape is known);
/// anything else passes through untouched rather than guessed.
public enum ModelNames {

    public static func pretty(_ id: String) -> String {
        var trimmed = id
        // Date suffix: claude-haiku-4-5-20251001 → claude-haiku-4-5
        if let range = trimmed.range(of: #"-\d{8}$"#, options: .regularExpression) {
            trimmed = String(trimmed[..<range.lowerBound])
        }
        guard trimmed.hasPrefix("claude-") else { return id }
        let parts = trimmed.dropFirst("claude-".count).split(separator: "-").map(String.init)
        let numbers = parts.filter { $0.allSatisfy(\.isNumber) }
        let words = parts.filter { !$0.allSatisfy(\.isNumber) }
        guard let family = words.last, !family.isEmpty else { return id }
        let version = numbers.joined(separator: ".")
        let name = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? name : "\(name) \(version)"
    }
}
