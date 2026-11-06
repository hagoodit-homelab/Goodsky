import Foundation

/// Hand-written one-liners, keyed by verdict and conditions. Cursing allowed; that's the point.
///
/// This is the reliable source of snark. Widgets and the watch always use it. The on-device
/// Foundation Models version (Phase 2) falls back to it when the model gets prudish.
public enum SnarkLibrary {
    /// Situations more specific than the verdict. Checked in this order; first match wins.
    public enum Mood: String, CaseIterable, Sendable {
        case snow, freezing, downpour, windy, scorching, perfect
    }

    public static func mood(for call: JacketCall) -> Mood? {
        if call.firstWetHour != nil && call.precipKind.isFrozen { return .snow }
        if call.minFeelsLikeF < 20 { return .freezing }
        if call.firstWetHour != nil && call.peakPrecipChance >= 0.8 { return .downpour }
        if call.windBumped || call.maxWindMph >= 25 { return .windy }
        if call.maxFeelsLikeF >= 90 { return .scorching }
        if call.verdict == .noJacket && call.minFeelsLikeF >= 65 && call.maxFeelsLikeF <= 80 { return .perfect }
        return nil
    }

    /// Lines for the call. Specific mood pool when one applies, otherwise the verdict pool.
    public static func lines(for call: JacketCall) -> [String] {
        if let mood = mood(for: call), let pool = moodLines[mood], !pool.isEmpty { return pool }
        return verdictLines[call.verdict] ?? []
    }

    /// A stable pick: same day + same situation gives the same line, so it doesn't change on every refresh.
    public static func line(for call: JacketCall, on date: Date, calendar: Calendar, salt: Int = 0) -> String {
        let pool = lines(for: call)
        guard !pool.isEmpty else { return "" }
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        let key = "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)|\(call.verdict.rawValue)|\(mood(for: call)?.rawValue ?? "-")|\(salt)"
        return pool[Int(fnv1a(key) % UInt64(pool.count))]
    }

    /// FNV-1a: deterministic across launches (unlike `Hasher`).
    static func fnv1a(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    // MARK: - The lines

    static let verdictLines: [JacketVerdict: [String]] = [
        .noJacket: [
            "Leave the damn jacket. You'll just carry it around like an idiot.",
            "No jacket. Go outside and pretend you're a functioning adult.",
            "It's nice out. Don't screw this up by staying indoors.",
            "Jacket? In this economy? In this weather? Hell no.",
            "Arms out. Let the world see those pale-ass elbows.",
            "Zero jacket required. I checked twice so you wouldn't have to think.",
            "Go jacketless, you magnificent bastard.",
            "The sky is behaving. Enjoy it before it remembers what it is.",
        ],
        .jacket: [
            "Grab a jacket. Not a parka, you drama queen. A jacket.",
            "Jacket weather. Yes, you'll take it off by noon. Bring it anyway.",
            "It's brisk. Cover your fragile little body.",
            "Throw on a jacket and stop arguing with me.",
            "Hoodie-or-jacket weather. Pick one, it's not a damn quiz.",
            "You'll want a layer. Trust me, I'm literally made of weather data.",
            "Bring a jacket or spend the day hugging yourself like a sad Victorian ghost.",
            "Chilly enough to be annoying. Jacket up.",
        ],
        .realCoat: [
            "Real coat. The big one. The one that makes you look like a sleeping bag.",
            "It's cold as hell out there. Dress like you want to keep your fingers.",
            "Coat, hat, gloves. I don't make the rules, the atmosphere does.",
            "This is not a light-jacket situation, you optimistic fool.",
            "Bundle the hell up. Your nostrils will thank you.",
            "Wear the heavy coat and stop pretending you're tough.",
            "Outside is actively hostile today. Armor up.",
        ],
        .rainJacket: [
            "Bring the damn rain jacket. You know you'll regret it.",
            "It's going to rain. Your hair is not waterproof. Act accordingly.",
            "Rain jacket. Unless you enjoy that wet-sock squish. Freak.",
            "The sky's gonna piss on you. Plan accordingly.",
            "Take the rain jacket. Umbrellas are for people who like losing umbrellas.",
            "Rain's coming. Don't be the soggy idiot in the meeting.",
            "Waterproof yourself, champ. It's gonna get damp as hell.",
            "Rain jacket today. I'm not saying I told you so yet, but I'm warming up.",
        ],
    ]

    static let moodLines: [Mood: [String]] = [
        .snow: [
            "Snow. Wear the coat, find the boots, and drive like you have a brain.",
            "It's snowing, so everyone around you is about to forget how cars work.",
            "Frozen crap falling from the sky. Real coat. Boots. Go.",
            "Snow day vibes, minus the actual day off. Bundle up.",
        ],
        .freezing: [
            "It's stupid cold. Like, \"why do people live here\" cold.",
            "Frostbite weather. Cover every inch of skin you care about.",
            "Cold enough to freeze the snark right out of me. Almost.",
            "The air hurts today. Wear everything you own.",
        ],
        .downpour: [
            "It's going to absolutely dump. Rain jacket, and maybe a damn boat.",
            "Heavy rain. Your cute shoes are going to die today. Choose wisely.",
            "The sky is about to fire-hose the whole damn city. Rain jacket.",
            "Monsoon cosplay today. Waterproof everything.",
        ],
        .windy: [
            "It's windy as hell. That jacket is a wind jacket now.",
            "Gusty enough to steal your hat and your dignity. Jacket.",
            "Wind's being a real jerk today. Zip up.",
            "Hold onto your coffee. And wear a damn jacket.",
        ],
        .scorching: [
            "No jacket. Honestly, consider no pants. It's hot as balls.",
            "It's hot as hell. Hydrate, you beautiful sweaty disaster.",
            "The sun is trying to kill you today. Sunscreen, not a jacket.",
            "Swamp-ass weather. Dress light and walk slow.",
        ],
        .perfect: [
            "It's stupidly perfect out. If you stay inside, that's on you.",
            "Perfect weather. Go touch some grass, you gremlin.",
            "Honestly? Gorgeous. I'm almost mad I can't roast you about it.",
            "This is the weather people move here for. Get your ass outside.",
        ],
    ]
}
