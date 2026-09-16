import Testing
@testable import CaptionCore

@Suite struct ConversationTests {
    @Test func volatileThenFinal() {
        var conversation = Conversation()
        conversation.receiveVolatile("Xin ch", from: .me)
        conversation.receiveFinal("Xin chào", from: .me)

        #expect(conversation.lines.count == 1)
        let line = conversation.lines[0]
        #expect(line.committed == "Xin chào")
        #expect(line.volatile == "")
        #expect(line.isOpen == true)
    }

    @Test func twoFinalsConcatenateRaw() {
        var conversation = Conversation()
        conversation.receiveFinal("Xin chào", from: .me)
        conversation.receiveFinal(", bạn khỏe không?", from: .me)

        #expect(conversation.lines.count == 1)
        #expect(conversation.lines[0].committed == "Xin chào, bạn khỏe không?")
    }

    @Test func closeOpenLineDropsEmptyKeepsCommitted() {
        var conversation = Conversation()
        conversation.receiveVolatile("uh", from: .me)
        conversation.closeOpenLine(of: .me)
        #expect(conversation.lines.isEmpty)

        conversation.receiveFinal("Hello", from: .partner)
        conversation.closeOpenLine(of: .partner)
        #expect(conversation.lines.count == 1)
        #expect(conversation.lines[0].isOpen == false)
        #expect(conversation.lines[0].committed == "Hello")
    }

    @Test func newVolatileAfterCloseCreatesNewLine() {
        var conversation = Conversation()
        conversation.receiveFinal("Hello", from: .me)
        conversation.closeOpenLine(of: .me)
        conversation.receiveVolatile("Again", from: .me)

        #expect(conversation.lines.count == 2)
        #expect(conversation.lines[1].id != conversation.lines[0].id)
        #expect(conversation.lines[1].isOpen == true)
    }

    @Test func readerTextSwitchesOnReader() {
        var conversation = Conversation()
        let id = conversation.receiveFinal("Hello", from: .me)!
        conversation.applyTranslation("Xin chào", to: id, source: "Hello")

        let line = conversation.line(id)!
        #expect(Conversation.readerText(line, reader: .me) == "Hello")
        #expect(Conversation.readerText(line, reader: .partner) == "Xin chào")
    }

    @Test func applyTranslationIgnoresStaleShorterSource() {
        var conversation = Conversation()
        let id = conversation.receiveFinal("Hello there", from: .me)!
        conversation.applyTranslation("Xin chào bạn", to: id, source: "Hello there")
        conversation.applyTranslation("Xin chào", to: id, source: "Hello")

        let line = conversation.line(id)!
        #expect(line.translation == "Xin chào bạn")
        #expect(line.translatedSource == "Hello there")
    }

    @Test func applyTranslationStateTracksSourceFreshness() {
        var conversation = Conversation()
        let id = conversation.receiveFinal("Hello", from: .me)!
        conversation.receiveFinal(" there", from: .me)
        #expect(conversation.line(id)!.committed == "Hello there")

        conversation.applyTranslation("Xin chào", to: id, source: "Hello")
        #expect(conversation.line(id)!.translationState == .pending)

        conversation.applyTranslation("Xin chào bạn", to: id, source: "Hello there")
        #expect(conversation.line(id)!.translationState == .done)
    }

    @Test func needsTranslationTracksPendingAndGrowth() {
        var conversation = Conversation()
        let id = conversation.receiveFinal("Hello", from: .me)!
        #expect(conversation.needsTranslation(id) == true)

        conversation.markPending(id)
        #expect(conversation.needsTranslation(id) == false)

        conversation.applyTranslation("Xin chào", to: id, source: "Hello")
        #expect(conversation.needsTranslation(id) == false)

        conversation.receiveFinal(" there", from: .me)
        #expect(conversation.needsTranslation(id) == true)
    }

    @Test func trimKeepsNewestLines() {
        var conversation = Conversation(maxLines: 2)
        conversation.receiveFinal("One", from: .me)
        conversation.closeOpenLine(of: .me)
        conversation.receiveFinal("Two", from: .partner)
        conversation.closeOpenLine(of: .partner)
        conversation.receiveFinal("Three", from: .me)
        conversation.closeOpenLine(of: .me)

        #expect(conversation.lines.count == 2)
        #expect(conversation.lines.map(\.committed) == ["Two", "Three"])
    }

    @Test func partnerCaptionAwaitingTranslation() {
        var conversation = Conversation()
        let firstId = conversation.receiveFinal("Hi", from: .partner)!
        conversation.closeOpenLine(of: .partner)
        _ = conversation.receiveFinal("Hello", from: .me)!

        let caption = conversation.partnerCaption()
        #expect(caption.current == nil)
        #expect(caption.previous == Conversation.readerText(conversation.line(firstId)!, reader: .partner))
        #expect(caption.isAwaitingTranslation == true)
    }
}
