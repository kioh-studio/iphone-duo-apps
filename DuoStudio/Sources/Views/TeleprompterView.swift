import SwiftUI

/// The Script guide's teleprompter, for the subject's display (not mirrored — it has to be
/// readable). Fills the top `Theme.Layout.teleprompterFraction` of the screen, text near the top
/// edge where the outer camera is. While recording, the text slides up at `scriptSpeed` points per
/// second (`model.scriptOffset`); idle, it rests at the start. The clock is read inside a
/// `TimelineView`, so no timer lives in the model. Drawn on the outer display / over video, so it
/// uses the `overlay*` tokens.
struct TeleprompterView: View {
    @Environment(StudioModel.self) private var model

    private var isEmpty: Bool { model.scriptText.isEmpty }

    var body: some View {
        TimelineView(.animation(paused: model.recordingPhase != .recording)) { _ in
            let offset = model.scriptOffset(at: ProcessInfo.processInfo.systemUptime)
            Text(isEmpty ? "Write a script on the inner screen" : model.scriptText)
                .font(Theme.TypeFace.outerScript)
                .lineSpacing(Theme.Space.sm)
                .foregroundStyle(isEmpty ? Theme.Palette.overlayMuted : Theme.Palette.overlayInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .offset(y: -CGFloat(offset))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(Theme.Space.md)
        .containerRelativeFrame(.vertical, alignment: .top) { length, _ in
            length * Theme.Layout.teleprompterFraction
        }
        .clipped()
        .background(Theme.Palette.scriptScrim, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        .accessibilityLabel("Script")
        .accessibilityValue(isEmpty ? "Empty" : model.scriptText)
    }
}
