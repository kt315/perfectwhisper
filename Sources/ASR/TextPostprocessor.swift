import Foundation

/// Post-processing of raw Whisper output.
///
/// For now only the safest steps: whitespace normalization and filtering out
/// classic silence hallucinations. Anything that changes the meaning of the text
/// is deliberately left alone.
enum TextPostprocessor {
    /// Exact matches (case- and punctuation-insensitive) that Whisper emits
    /// on silence, noise or a truncated recording.
    private static let hallucinations: Set<String> = [
        "спасибо за просмотр",
        "спасибо за внимание",
        "продолжение следует",
        "подписывайтесь на канал",
        "ставьте лайки",
        "до новых встреч",
        "субтитры сделал dimatorzok",
        "thank you for watching",
        "thanks for watching",
        "дякую за перегляд",
        "thank you for listening",
        "subscribe to my channel",
        "see you next time",
        "bye",
        "пока",
        ".",
        "…",
    ]

    static func clean(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\u{200B}", with: "")
        text = text.replacingOccurrences(of: "\r", with: "\n")

        // Merge line breaks: this is dictation, not a document.
        text = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")

        // Collapse repeated spaces.
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if isHallucination(text) { return "" }
        return text
    }

    /// Characteristic fragments that Whisper invents on silence and noise.
    /// A substring match is enough: real dictation almost never contains such
    /// constructs, while hallucinations always look exactly like this.
    private static let hallucinationMarkers: [String] = [
        "субтитры сделал",
        "субтитры создал",
        "субтитры подготовил",
        "редактор субтитров",
        "dimatorzok",
        "диматорзок",
        "дима торзок",
    ]

    static func isHallucination(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,!?…-—\"'«»()"))
        if hallucinations.contains(normalized) { return true }
        // Don't cut long meaningful text even if a marker matches.
        guard text.count < 160 else { return false }
        return hallucinationMarkers.contains { normalized.contains($0) }
    }
}
