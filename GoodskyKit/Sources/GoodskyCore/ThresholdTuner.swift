import Foundation

/// What Josh said about a Jacket Call after living with it.
public enum JacketFeedback: String, Codable, Sendable, CaseIterable {
    /// 👍 The call was right.
    case right
    /// 👎 I was cold. Should have dressed warmer.
    case tooCold
    /// 👎 I was too warm. Should have dressed lighter.
    case tooWarm
    /// 👎 Got rained on without a rain jacket.
    case gotWet
    /// 👎 Carried a rain jacket for nothing.
    case stayedDry

    public var label: String {
        switch self {
        case .right: "Nailed it"
        case .tooCold: "I was cold"
        case .tooWarm: "I was too warm"
        case .gotWet: "Got rained on"
        case .stayedDry: "Didn't need the rain jacket"
        }
    }

    /// 👎 options that make sense for a verdict. (Can't be "too cold" in a real coat, etc.)
    public static func complaints(for call: JacketCall) -> [JacketFeedback] {
        var options: [JacketFeedback] = []
        if call.verdict != .realCoat { options.append(.tooCold) }
        if call.verdict != .noJacket { options.append(.tooWarm) }
        if call.verdict == .rainJacket { options.append(.stayedDry) } else { options.append(.gotWet) }
        return options
    }
}

/// One vote, kept so the app can show history and so a day can only be voted on once.
public struct FeedbackRecord: Codable, Sendable, Equatable {
    public var date: Date
    /// "2026-11-06": one vote per local day.
    public var day: String
    public var verdict: JacketVerdict
    public var feedback: JacketFeedback
    public var minFeelsLikeF: Double
    public var peakPrecipChance: Double
    public var before: JacketSettings
    public var after: JacketSettings

    public init(date: Date, day: String, verdict: JacketVerdict, feedback: JacketFeedback,
                minFeelsLikeF: Double, peakPrecipChance: Double, before: JacketSettings, after: JacketSettings) {
        self.date = date
        self.day = day
        self.verdict = verdict
        self.feedback = feedback
        self.minFeelsLikeF = minFeelsLikeF
        self.peakPrecipChance = peakPrecipChance
        self.before = before
        self.after = after
    }
}

public struct TuningResult: Sendable, Equatable {
    public var settings: JacketSettings
    /// Human-readable changes, e.g. "Jacket below 62° → 64°". Empty when nothing moved.
    public var changes: [String]
    /// Snarky acknowledgement for the toast.
    public var message: String
}

/// Nudges the Jacket Call thresholds from 👍/👎 feedback.
///
/// Each 👎 moves the one threshold that would have changed the call, partway toward the value that
/// would have flipped it (half the gap, at least `minStep`, at most `maxStep`). Small steps mean one
/// weird day can't wreck the settings, but a consistent pattern moves them in about a week.
public enum ThresholdTuner {
    public static let minStep = 1.0
    public static let maxStep = 4.0
    public static let rainStep = 0.05
    public static let windStep = 2.0

    /// Limits so feedback can never push settings somewhere absurd. Same ranges as Settings.
    public static let jacketRange = 35.0...80.0
    public static let coatRange = 0.0...80.0
    public static let rainRange = 0.1...0.9
    public static let windRange = 10.0...40.0

    public static func apply(_ feedback: JacketFeedback, to call: JacketCall,
                             settings: JacketSettings) -> TuningResult {
        var s = settings.sanitized
        let before = s
        let lo = call.minFeelsLikeF

        switch feedback {
        case .right:
            return TuningResult(settings: s, changes: [], message: "Obviously. I'm never wrong. Noted anyway.")

        case .tooCold:
            // Make this day count as one step warmer.
            if lo >= s.jacketBelowF {
                s.jacketBelowF = nudge(s.jacketBelowF, toward: lo + 1, range: jacketRange)
            } else if lo >= s.coatBelowF {
                s.coatBelowF = nudge(s.coatBelowF, toward: lo + 1, range: coatRange)
            }
            // Raising jacket must drag nothing; raising coat is capped by jacket below.
            s.coatBelowF = min(s.coatBelowF, s.jacketBelowF)

        case .tooWarm:
            if call.windBumped {
                // Wind made it a jacket day. Wind needs to be stronger to count.
                s.windyMph = clamp(s.windyMph + windStep, windRange)
            } else if lo < s.coatBelowF {
                s.coatBelowF = nudge(s.coatBelowF, toward: lo - 1, range: coatRange)
            } else if lo < s.jacketBelowF {
                s.jacketBelowF = nudge(s.jacketBelowF, toward: lo - 1, range: jacketRange)
                s.coatBelowF = min(s.coatBelowF, s.jacketBelowF)
            }

        case .gotWet:
            // Rain chance needs to count sooner.
            s.rainChanceThreshold = clamp(s.rainChanceThreshold - rainStep, rainRange)

        case .stayedDry:
            s.rainChanceThreshold = clamp(s.rainChanceThreshold + rainStep, rainRange)
        }

        s.rainChanceThreshold = (s.rainChanceThreshold * 100).rounded() / 100
        let changes = describeChanges(from: before, to: s)
        return TuningResult(settings: s, changes: changes, message: message(for: feedback, changed: !changes.isEmpty))
    }

    static func nudge(_ value: Double, toward target: Double, range: ClosedRange<Double>) -> Double {
        let gap = target - value
        guard gap != 0 else { return value }
        let step = min(max(abs(gap) / 2, minStep), maxStep)
        let moved = value + (gap > 0 ? step : -step)
        return clamp(moved.rounded(), range)
    }

    static func clamp(_ v: Double, _ r: ClosedRange<Double>) -> Double { min(max(v, r.lowerBound), r.upperBound) }

    public static func describeChanges(from a: JacketSettings, to b: JacketSettings) -> [String] {
        var out: [String] = []
        if a.jacketBelowF != b.jacketBelowF {
            out.append("Jacket below \(Format.degrees(a.jacketBelowF)) → \(Format.degrees(b.jacketBelowF))")
        }
        if a.coatBelowF != b.coatBelowF {
            out.append("Real coat below \(Format.degrees(a.coatBelowF)) → \(Format.degrees(b.coatBelowF))")
        }
        if a.rainChanceThreshold != b.rainChanceThreshold {
            out.append("Rain jacket at \(Format.percent(a.rainChanceThreshold)) → \(Format.percent(b.rainChanceThreshold))")
        }
        if a.windyMph != b.windyMph {
            out.append("Windy at \(Format.mph(a.windyMph)) → \(Format.mph(b.windyMph))")
        }
        return out
    }

    static func message(for feedback: JacketFeedback, changed: Bool) -> String {
        guard changed else {
            return "Noted, but I'm already at the limit. Maybe move somewhere with better weather."
        }
        switch feedback {
        case .right: return "Obviously."
        case .tooCold: return "Fine, you delicate little icicle. I'll call jackets sooner."
        case .tooWarm: return "Okay, hot stuff. I'll ease off the layers."
        case .gotWet: return "My bad. I'll take rain more seriously. You can dry off now."
        case .stayedDry: return "Fine. I'll stop crying wolf about rain. A little."
        }
    }

    /// "2026-11-06" in the given calendar. Used to allow one vote per day.
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
