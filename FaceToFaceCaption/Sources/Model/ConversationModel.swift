import Foundation
import Observation
import CaptionCore

@MainActor
@Observable
final class ConversationModel {
    static let shared = ConversationModel()

    enum Phase: Equatable {
        case setup, conversation
    }

    enum Turn: Equatable {
        case idle
        case listening(Speaker)
        case finishing(Speaker)
    }

    enum Banner: Equatable {
        case speechMissing(Speaker)
        case micStopped
        case translationMissing
    }

    private static let mineKey = "pair.mine"
    private static let partnerKey = "pair.partner"

    var phase: Phase = .setup
    private(set) var turn: Turn = .idle

    var pair: LanguagePair {
        didSet {
            guard pair != oldValue else { return }
            UserDefaults.standard.set(pair.mine, forKey: Self.mineKey)
            UserDefaults.standard.set(pair.partner, forKey: Self.partnerKey)
            translators.removeAll()
        }
    }

    private(set) var conversation = Conversation()
    private(set) var level: Double = 0
    var banner: Banner?
    private(set) var clearedBackup: Conversation?
    var isSetupSheetPresented = false

    let displays = DisplayMonitor()

    var partnerCaption: PartnerCaption { conversation.partnerCaption() }

    private var speech: SpeechService?
    private var listenTask: Task<Void, Never>?
    private var turnTask: Task<Void, Never>?
    private var translating: Set<UUID> = []
    private var translators: [Speaker: TranslationService] = [:]
    private var clearUndoTask: Task<Void, Never>?

    private init() {
        let defaults = UserDefaults.standard
        // UNVERIFIED (2026-09-13, written on Windows): Locale.identifier(_:) with an
        // .bcp47 style argument exists on the iOS 26 SDK's Locale type.
        let deviceIdentifier = Locale.current.identifier(.bcp47)
        let defaultMine = deviceIdentifier.isEmpty ? "en-US" : deviceIdentifier
        let mine = defaults.string(forKey: Self.mineKey) ?? defaultMine
        let partner = defaults.string(forKey: Self.partnerKey) ?? (mine.hasPrefix("en") ? "es-ES" : "en-US")
        self.pair = LanguagePair(mine: mine, partner: partner)
    }

    // MARK: - Turns

    func toggleTurn(_ speaker: Speaker) {
        guard turnTask == nil else { return }
        switch turn {
        case .listening(let current) where current == speaker:
            turnTask = Task {
                await self.finishTurn()
                self.turnTask = nil
            }
        case .listening:
            turnTask = Task {
                await self.finishTurn()
                await self.startTurn(speaker)
                self.turnTask = nil
            }
        case .idle:
            turnTask = Task {
                await self.startTurn(speaker)
                self.turnTask = nil
            }
        case .finishing:
            break
        }
    }

    private func startTurn(_ speaker: Speaker) async {
        let service = SpeechService(localeIdentifier: pair.spoken(by: speaker))
        speech = service
        turn = .listening(speaker)
        do {
            let events = try await service.start()
            listenTask = Task { [weak self] in
                guard let self else { return }
                do {
                    for try await event in events {
                        switch event {
                        case .volatile(let text):
                            self.conversation.receiveVolatile(text, from: speaker)
                        case .final(let text):
                            if let id = self.conversation.receiveFinal(text, from: speaker) {
                                self.requestTranslation(id)
                            }
                        case .level(let value):
                            self.level = value
                        }
                    }
                } catch {
                    self.handleSpeechFailure(error, speaker: speaker)
                }
            }
        } catch {
            handleSpeechFailure(error, speaker: speaker)
        }
    }

    private func handleSpeechFailure(_ error: Error, speaker: Speaker) {
        if case SpeechServiceError.modelNotInstalled = error {
            banner = .speechMissing(speaker)
        } else {
            banner = .micStopped
        }
        conversation.closeOpenLine(of: speaker)
        speech = nil
        turn = .idle
        level = 0
    }

    func finishTurn() async {
        guard case .listening(let speaker) = turn else { return }
        turn = .finishing(speaker)
        await speech?.finish()
        await listenTask?.value
        conversation.closeOpenLine(of: speaker)
        speech = nil
        level = 0
        turn = .idle
    }

    // MARK: - Translation

    private func requestTranslation(_ id: UUID) {
        guard conversation.needsTranslation(id),
              !translating.contains(id),
              let line = conversation.line(id) else { return }
        let source = line.committed
        let speaker = line.speaker
        conversation.markPending(id)
        translating.insert(id)
        Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.translator(for: speaker).translate(source)
                self.conversation.applyTranslation(text, to: id, source: source)
            } catch TranslationServiceError.notInstalled {
                self.banner = .translationMissing
                self.conversation.failTranslation(of: id, source: source)
            } catch {
                self.conversation.failTranslation(of: id, source: source)
            }
            self.translating.remove(id)
            // Re-request if the committed text grew while this call was in flight, but never
            // spin forever retrying a failure — the retry button (retryTranslation) covers that.
            if self.conversation.line(id)?.translationState != .failed {
                self.requestTranslation(id)
            }
        }
    }

    func retryTranslation(_ id: UUID) {
        requestTranslation(id)
    }

    private func translator(for speaker: Speaker) -> TranslationService {
        if let existing = translators[speaker] { return existing }
        let service = TranslationService(source: pair.spoken(by: speaker), target: pair.target(for: speaker))
        translators[speaker] = service
        return service
    }

    // MARK: - Transcript

    func clear() {
        clearUndoTask?.cancel()
        clearedBackup = conversation
        conversation.clear()
        clearUndoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.clearedBackup = nil
        }
    }

    func undoClear() {
        clearUndoTask?.cancel()
        if let backup = clearedBackup {
            conversation = backup
        }
        clearedBackup = nil
    }

    // MARK: - Phase / setup sheet

    func startConversation() {
        phase = .conversation
    }

    /// Opens the language setup sheet from the transcript's language chip, finishing any turn
    /// in progress first. Reuses `isSetupSheetPresented` rather than `phase` — the chip is a
    /// sheet over the conversation, not a return to the launch flow.
    func openSetupSheet() {
        if case .listening = turn, turnTask == nil {
            turnTask = Task {
                await self.finishTurn()
                self.turnTask = nil
            }
        }
        isSetupSheetPresented = true
    }
}
