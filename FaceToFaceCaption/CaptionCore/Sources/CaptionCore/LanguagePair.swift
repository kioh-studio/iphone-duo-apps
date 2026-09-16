import Foundation

/// Which side of the conversation is speaking.
public enum Speaker: String, Sendable, Codable, CaseIterable {
    case me, partner

    /// The other participant.
    public var other: Speaker {
        self == .me ? .partner : .me
    }
}

/// The two languages in play, as BCP-47 identifiers, e.g. "vi-VN", "en-US".
public struct LanguagePair: Sendable, Equatable, Codable {
    public var mine: String
    public var partner: String

    public init(mine: String, partner: String) {
        self.mine = mine
        self.partner = partner
    }

    /// The language `speaker` speaks.
    public func spoken(by speaker: Speaker) -> String {
        speaker == .me ? mine : partner
    }

    /// The language `speaker`'s words are translated into.
    public func target(for speaker: Speaker) -> String {
        speaker == .me ? partner : mine
    }

    /// `mine` and `partner` exchanged.
    public var swapped: LanguagePair {
        LanguagePair(mine: partner, partner: mine)
    }
}
