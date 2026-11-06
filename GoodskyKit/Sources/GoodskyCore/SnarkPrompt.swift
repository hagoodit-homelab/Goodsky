import Foundation

/// Prompt text and output filter for the on-device Foundation Models snark line.
///
/// The model call itself lives in the app (FoundationModels is Apple-only). Everything that can be
/// tested without the model lives here: what we ask for, and whether the answer is usable.
public enum SnarkPrompt {
    /// Session instructions. Kept short: the on-device model is small and literal.
    public static let instructions = """
    You write one-line weather roasts for a personal weather app called Goodsky. \
    The user decides whether to wear a jacket based on your line. \
    Voice: savage, funny, a little mean, like a sarcastic friend. Mild cursing (damn, hell, ass, crap) is welcome. \
    Rules: one sentence or two short ones, under 120 characters. \
    Always agree with the verdict you're given. Never mention being an AI, a model or an app. \
    No hashtags, no emoji, no quotation marks, no greetings, no "stay safe".
    """

    /// The per-day request: the verdict and the facts behind it, plus one template line as a style example.
    public static func prompt(for call: JacketCall, current: CurrentConditions?, example: String,
                              calendar: Calendar) -> String {
        var facts: [String] = [
            "Verdict: \(call.verdict.title.lowercased()).",
            "Why: \(call.reason)",
            timingFact(call, calendar: calendar),
            "Feels like \(Format.degrees(call.minFeelsLikeF)) to \(Format.degrees(call.maxFeelsLikeF)) while out.",
        ]
        if let wet = call.firstWetHour {
            facts.append("\(call.precipKind.noun.capitalizedFirst) from \(Format.hour(wet, calendar: calendar)), up to \(Format.percent(call.peakPrecipChance)) chance.")
        }
        if call.maxWindMph >= 15 { facts.append("Wind up to \(Format.mph(call.maxWindMph)).") }
        if let current { facts.append("Right now: \(current.conditionText.lowercased()), \(Format.degrees(current.temperatureF)).") }
        return """
        \(facts.joined(separator: "\n"))
        Example of the voice (don't copy it): \(example)
        Write today's line.
        """
    }

    /// Now vs later, spelled out so the line doesn't yell "wear it" when he can skip it till evening.
    static func timingFact(_ call: JacketCall, calendar: Calendar) -> String {
        switch call.timing {
        case .allDay: return call.verdict == .noJacket ? "No need all day." : "Needed the whole time."
        case .later(let from): return "Not needed yet; needed from \(Format.hour(from, calendar: calendar))."
        case .nowOnly(let until): return "Needed now; can ditch it by \(Format.hour(until, calendar: calendar))."
        case .stepUp(let now, let at):
            return "\(now.title) now, \(call.verdict.title.lowercased()) from \(Format.hour(at, calendar: calendar))."
        }
    }

    public static let maxLength = 140
    public static let minLength = 12

    /// Cleans up a model answer, or returns `nil` if it should be thrown away for the template line.
    ///
    /// Rejects refusals, assistant-speak, wholesome filler (the "too tame" signal), multi-line rambles,
    /// and lines that argue with the verdict.
    public static func accept(_ raw: String, for verdict: JacketVerdict) -> String? {
        var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep only the first non-empty line.
        if let first = line.split(whereSeparator: \.isNewline).first {
            line = String(first).trimmingCharacters(in: .whitespaces)
        }
        // Strip wrapping quotes and a leading label like "Line:".
        let quotes = CharacterSet(charactersIn: "\"'“”‘’`")
        line = line.trimmingCharacters(in: quotes).trimmingCharacters(in: .whitespaces)
        for label in ["line:", "roast:", "today's line:", "goodsky:"] where line.lowercased().hasPrefix(label) {
            line = String(line.dropFirst(label.count)).trimmingCharacters(in: .whitespaces.union(quotes))
        }

        guard line.count >= minLength, line.count <= maxLength else { return nil }
        let lower = line.lowercased()
        if rejectPhrases.contains(where: lower.contains) { return nil }
        if contradicts(lower, verdict: verdict) { return nil }
        return line
    }

    /// Signs of a refusal, assistant-speak, or a line too tame to bother with.
    static let rejectPhrases = [
        "i can't", "i cannot", "i'm sorry", "i am sorry", "as an ai", "language model", "i'm unable",
        "i won't", "respectful", "offensive", "inappropriate",
        "stay safe", "have a great day", "have a nice day", "enjoy your day", "remember to", "don't forget to",
        "#",
    ]

    /// Crude check that the line doesn't tell him the opposite of the verdict.
    static func contradicts(_ lower: String, verdict: JacketVerdict) -> Bool {
        switch verdict {
        case .noJacket:
            return ["wear a jacket", "grab a jacket", "bring a jacket", "need a jacket", "rain jacket", "coat on"]
                .contains(where: lower.contains)
        case .jacket, .realCoat:
            return ["no jacket", "leave the jacket", "skip the jacket", "don't need a jacket"].contains(where: lower.contains)
        case .rainJacket:
            return ["no rain", "stays dry", "leave the rain jacket", "skip the rain jacket", "no jacket"]
                .contains(where: lower.contains)
        }
    }
}
