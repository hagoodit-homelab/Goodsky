import Foundation
import GoodskyCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Writes the app's snark line with Apple's on-device model, when it's available and willing.
///
/// Returns `nil` whenever the template line should be used instead: model unavailable (older
/// device, Apple Intelligence off, watchOS), a guardrail refusal, an error, or an answer that
/// fails `SnarkPrompt.accept` (refusal, too tame, argues with the verdict).
/// Widgets and complications never call this; they always use `SnarkLibrary`.
enum SnarkWriter {
    static var isAvailable: Bool {
        #if canImport(FoundationModels) && os(iOS)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    /// Plain-English reason the model can't be used, for Settings. `nil` when it's ready.
    static var unavailableReason: String? {
        #if canImport(FoundationModels) && os(iOS)
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in iOS Settings to use this."
        case .unavailable(.modelNotReady):
            return "Apple's model is still downloading. Using templates until it's ready."
        case .unavailable(.deviceNotEligible):
            return "This iPhone can't run Apple's on-device model. Templates it is."
        case .unavailable:
            return "Apple's on-device model isn't available right now."
        }
        #else
        return "Apple's on-device model isn't available here."
        #endif
    }

    static func line(for report: GoodskyReport) async -> String? {
        #if canImport(FoundationModels) && os(iOS)
        guard isAvailable, let call = report.call else { return nil }
        let prompt = SnarkPrompt.prompt(for: call, current: report.snapshot.current, example: report.snark,
                                        calendar: report.snapshot.calendar)
        do {
            let session = LanguageModelSession(instructions: SnarkPrompt.instructions)
            let response = try await session.respond(
                to: prompt,
                options: GenerationOptions(temperature: 0.9, maximumResponseTokens: 80)
            )
            return SnarkPrompt.accept(response.content, for: call.verdict)
        } catch {
            // Guardrail violations land here too. The templates don't have guardrails.
            return nil
        }
        #else
        return nil
        #endif
    }
}
