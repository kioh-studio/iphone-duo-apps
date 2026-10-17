import Foundation

/// The one mode dial: two groups (Photo: Pose, Selfie; Video: Frame, Script, Dance, Interview).
/// `StudioModel.mode` is the single source of truth - shoot kind, video guide and capture mode are
/// derived from it (plus the Solo toggle for the video modes that can be shot alone).
enum StudioMode: String, CaseIterable, Codable, Sendable {
    case pose, selfie, frame, script, dance, interview

    enum Group: Sendable { case photo, video }

    var group: Group {
        switch self {
        case .pose, .selfie: return .photo
        case .frame, .script, .dance, .interview: return .video
        }
    }

    var title: String {
        switch self {
        case .pose: return "Pose"
        case .selfie: return "Selfie"
        case .frame: return "Frame"
        case .script: return "Script"
        case .dance: return "Dance"
        case .interview: return "Interview"
        }
    }

    /// One line shown under the dial.
    var summary: String {
        switch self {
        case .pose: return "Pick a pose. Your subject sees it on the outer screen with a live score and lines up on their own."
        case .selfie: return "Prop the phone up and step in front. The guide and score move to this screen."
        case .frame: return "A TikTok-safe frame with live hints, so whoever is on camera stays in shot."
        case .script: return "Your script scrolls on the outer screen beside the lens. Read it while looking at the camera."
        case .dance: return "Follow the ghost in time with the music, get a score, and keep the original audio."
        case .interview: return "Both cameras at once, saved as one vertical split-screen clip. Questions stay on your side."
        }
    }

    /// Short phrase for the onboarding list.
    var tagline: String {
        switch self {
        case .pose: return "Match a pose, see the score live"
        case .selfie: return "Prop it up, shoot yourself"
        case .frame: return "Stay in a TikTok-safe frame"
        case .script: return "Teleprompter beside the lens"
        case .dance: return "Follow any dance video, get scored"
        case .interview: return "Both cameras, one split-screen clip"
        }
    }

    /// Modes whose guide scores a match % (shown in the top bar).
    var scoresMatch: Bool { self == .pose || self == .selfie || self == .dance }

    /// Video modes that can be shot alone on a stand (the Solo toggle).
    var supportsSolo: Bool { self == .frame || self == .script || self == .dance }

    static func modes(in group: Group) -> [StudioMode] {
        allCases.filter { $0.group == group }
    }
}
