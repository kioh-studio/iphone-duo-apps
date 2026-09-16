import Foundation

/// Where a caption line's translation stands.
public enum TranslationState: Sendable, Equatable {
    case none, pending, done, failed
}

/// One turn of speech from one speaker, as it is built up from live recognition results.
public struct CaptionLine: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let speaker: Speaker
    /// Concatenated final (committed) recognition segments.
    public internal(set) var committed: String
    /// The current partial (volatile) result; replaced wholesale on each update.
    public internal(set) var volatile: String
    public internal(set) var translation: String?
    public internal(set) var translationState: TranslationState
    /// The `committed` text `translation` was produced from.
    public internal(set) var translatedSource: String?
    public internal(set) var isOpen: Bool

    /// `committed` plus whatever partial text hasn't been finalized yet.
    public var original: String { committed + volatile }
}

/// What the partner's facing display should show right now.
public struct PartnerCaption: Sendable, Equatable {
    public var current: String?
    public var previous: String?
    public var isAwaitingTranslation: Bool

    public init(current: String?, previous: String?, isAwaitingTranslation: Bool) {
        self.current = current
        self.previous = previous
        self.isAwaitingTranslation = isAwaitingTranslation
    }
}

/// The running transcript of a face-to-face conversation: pure state, no I/O.
///
/// Both speakers write into the same timeline. At most one line per speaker is "open" (still
/// receiving live recognition results) at a time; a line closes when its speaker's turn ends.
public struct Conversation: Sendable, Equatable {
    public private(set) var lines: [CaptionLine]
    public let maxLines: Int

    public init(maxLines: Int = 200) {
        self.lines = []
        self.maxLines = maxLines
    }

    /// The open line of `speaker`, if any — the last line by that speaker with `isOpen == true`.
    private func openLineIndex(for speaker: Speaker) -> Int? {
        lines.lastIndex { $0.speaker == speaker && $0.isOpen }
    }

    /// Replaces the partial (in-progress) text of `speaker`'s open line, opening one if needed.
    public mutating func receiveVolatile(_ text: String, from speaker: Speaker) {
        if let idx = openLineIndex(for: speaker) {
            lines[idx].volatile = text
        } else {
            lines.append(
                CaptionLine(
                    id: UUID(),
                    speaker: speaker,
                    committed: "",
                    volatile: text,
                    translation: nil,
                    translationState: .none,
                    translatedSource: nil,
                    isOpen: true
                )
            )
        }
        trim()
    }

    /// Appends a finalized recognition segment to `speaker`'s open line (opening one if needed)
    /// and clears the volatile text. Segments are concatenated raw — SpeechTranscriber segments
    /// carry their own spacing and CJK has no spaces, so no separator is inserted.
    ///
    /// Returns the line's id if its committed text is non-empty after trimming, else nil.
    @discardableResult
    public mutating func receiveFinal(_ text: String, from speaker: Speaker) -> UUID? {
        let idx: Int
        if let existing = openLineIndex(for: speaker) {
            idx = existing
        } else {
            lines.append(
                CaptionLine(
                    id: UUID(),
                    speaker: speaker,
                    committed: "",
                    volatile: "",
                    translation: nil,
                    translationState: .none,
                    translatedSource: nil,
                    isOpen: true
                )
            )
            idx = lines.count - 1
        }
        lines[idx].committed += text
        lines[idx].volatile = ""
        let id = lines[idx].id
        let trimmed = lines[idx].committed.trimmingCharacters(in: .whitespacesAndNewlines)
        trim()
        return trimmed.isEmpty ? nil : id
    }

    /// Ends `speaker`'s turn: clears any partial text and marks the open line closed. A line left
    /// with no committed text (only ever had a partial that never finalized) is removed entirely.
    public mutating func closeOpenLine(of speaker: Speaker) {
        guard let idx = openLineIndex(for: speaker) else { return }
        lines[idx].volatile = ""
        lines[idx].isOpen = false
        if lines[idx].committed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.remove(at: idx)
        }
    }

    /// Marks a line as awaiting a translation result.
    public mutating func markPending(_ id: UUID) {
        guard let idx = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[idx].translationState = .pending
    }

    /// Records a translation result for `id`, produced from `source`. Ignored if the line no
    /// longer exists, or if `source` is shorter than the source of a translation already applied
    /// (committed text only grows, so a shorter source is a stale, out-of-order result). The
    /// resulting state is `.done` if `source` matches the line's current committed text, else
    /// `.pending` (the committed text has grown further since this translation was requested).
    public mutating func applyTranslation(_ text: String, to id: UUID, source: String) {
        guard let idx = lines.firstIndex(where: { $0.id == id }) else { return }
        if let previousSource = lines[idx].translatedSource, source.count < previousSource.count {
            return
        }
        lines[idx].translation = text
        lines[idx].translatedSource = source
        lines[idx].translationState = (source == lines[idx].committed) ? .done : .pending
    }

    /// Marks a translation attempt as failed, but only if `source` still matches the line's
    /// current committed text (an out-of-date failure is simply ignored). Keeps any previous
    /// translation in place.
    public mutating func failTranslation(of id: UUID, source: String) {
        guard let idx = lines.firstIndex(where: { $0.id == id }) else { return }
        guard source == lines[idx].committed else { return }
        lines[idx].translationState = .failed
    }

    public func line(_ id: UUID) -> CaptionLine? {
        lines.first { $0.id == id }
    }

    /// True if `id` names a line with non-empty committed text whose translation is missing,
    /// stale, or hasn't been (re)requested for the current committed text.
    public func needsTranslation(_ id: UUID) -> Bool {
        guard let line = line(id) else { return false }
        guard !line.committed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard line.translatedSource != line.committed else { return false }
        return line.translationState != .pending
    }

    public mutating func clear() {
        lines.removeAll()
    }

    /// Drops the oldest closed lines once `lines.count` exceeds `maxLines`. Open lines are never
    /// removed; if every line happens to be open, trimming simply stops.
    private mutating func trim() {
        while lines.count > maxLines {
            guard let idx = lines.firstIndex(where: { !$0.isOpen }) else { break }
            lines.remove(at: idx)
        }
    }

    /// What `reader` should see of `line`: their own lines read as the original text, the other
    /// speaker's lines read as the translation. Returns nil when there's nothing to show yet.
    public static func readerText(_ line: CaptionLine, reader: Speaker) -> String? {
        if reader == line.speaker {
            let trimmed = line.original.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let translation = line.translation, !translation.isEmpty else { return nil }
        return translation
    }

    /// The current/previous text the partner's facing display should show, and whether the
    /// newest line (if it's mine) is still waiting on its translation.
    public func partnerCaption() -> PartnerCaption {
        let visible = lines.filter { !$0.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let newest = visible.last
        let older = visible.dropLast().last
        let current = newest.flatMap { Conversation.readerText($0, reader: .partner) }
        let previous = older.flatMap { Conversation.readerText($0, reader: .partner) }
        let isAwaitingTranslation = newest.map { line in
            line.speaker == .me && (line.translationState == .pending || line.translatedSource != line.committed)
        } ?? false
        return PartnerCaption(current: current, previous: previous, isAwaitingTranslation: isAwaitingTranslation)
    }
}
