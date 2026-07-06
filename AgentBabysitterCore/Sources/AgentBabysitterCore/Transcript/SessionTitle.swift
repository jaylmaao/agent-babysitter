import Foundation

/// Distills a user transcript entry into the one-line "what it's working on"
/// caption the menu shows. The filter list comes from surveying real Claude
/// Code and Codex transcripts — "user"-typed lines are full of protocol
/// noise that no human typed.
public enum SessionTitle {

    /// Wrappers agents write in the user's voice. Anything leading with one
    /// of these is bookkeeping, not a prompt.
    private static let noisePrefixes = [
        "<command-name>",         // Claude Code slash-command wrapper
        "<local-command-stdout>", // Claude Code command output echo
        "<system-reminder>",      // injected context, not typed
        "<environment_context>",  // Codex session preamble
        "<user_instructions>",    // Codex AGENTS.md injection
        "<turn_context>",         // Codex per-turn preamble
        "Caveat: ",               // Claude Code resume preamble
        "[",                      // protocol notices: "[Request interrupted…]", "[task started]"
    ]

    /// The prompt as a menu caption — first line, trimmed, capped — or nil
    /// when the text is agent bookkeeping rather than something a person
    /// typed (keep the previous title in that case).
    public static func candidate(fromPromptText text: String, isMeta: Bool,
                                 maxLength: Int = 80) -> String? {
        guard !isMeta else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !noisePrefixes.contains(where: trimmed.hasPrefix) else { return nil }
        let firstLine = trimmed.split(separator: "\n", omittingEmptySubsequences: true)
            .first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !firstLine.isEmpty else { return nil }
        return firstLine.count > maxLength
            ? String(firstLine.prefix(maxLength - 1)) + "…"
            : firstLine
    }
}
