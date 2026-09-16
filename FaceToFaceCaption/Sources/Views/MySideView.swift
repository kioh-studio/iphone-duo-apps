import SwiftUI
import CaptionCore

struct MySideView: View {
    enum Layout { case sharedTable, separateScreens }

    let layout: Layout

    @Environment(ConversationModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            header
            if let banner = model.banner {
                BannerView(banner: banner)
            }
            transcript
            controls
        }
        .background(Theme.Palette.paper)
        .overlay(alignment: .bottom) {
            if model.clearedBackup != nil {
                undoBar
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                model.openSetupSheet()
            } label: {
                Text("\(LanguageCatalog.shortCode(model.pair.mine)) ⇄ \(LanguageCatalog.shortCode(model.pair.partner))")
                    .font(Theme.TypeFace.label)
                    .tracking(Theme.TypeFace.labelTracking)
                    .foregroundStyle(Theme.Palette.neutral)
            }
            Spacer()
            Button("Clear") { model.clear() }
                .font(Theme.TypeFace.secondary)
                .foregroundStyle(Theme.Palette.neutral)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
    }

    private var transcript: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.lg) {
                if model.conversation.lines.isEmpty {
                    emptyState
                } else {
                    ForEach(model.conversation.lines) { line in
                        TranscriptRow(line: line)
                    }
                }
            }
            .padding(Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.bottom)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Nothing said yet.")
                .font(Theme.TypeFace.body)
                .foregroundStyle(Theme.Palette.muted)
            Text(
                layout == .sharedTable
                    ? "Lay the phone between you. They read the top half; you read this one."
                    : "They read the facing screen; you read this one."
            )
            .font(Theme.TypeFace.secondary)
            .foregroundStyle(Theme.Palette.neutral)
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch layout {
        case .sharedTable:
            TurnButton(speaker: .me)
                .padding(Theme.Space.md)
        case .separateScreens:
            HStack(spacing: Theme.Space.md) {
                TurnButton(speaker: .me)
                TurnButton(speaker: .partner)
            }
            .padding(Theme.Space.md)
        }
    }

    private var undoBar: some View {
        HStack {
            Text("Conversation cleared")
                .font(Theme.TypeFace.body)
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            Button("Undo") { model.undoClear() }
                .font(Theme.TypeFace.body)
                .foregroundStyle(Theme.Palette.accent)
        }
        .padding(Theme.Space.md)
        .background(Theme.Palette.paper2)
    }
}

private struct TranscriptRow: View {
    let line: CaptionLine

    @Environment(ConversationModel.self) private var model

    private var tag: String { line.speaker == .me ? "YOU" : "THEM" }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(tag)
                .font(Theme.TypeFace.label)
                .tracking(Theme.TypeFace.labelTracking)
                .foregroundStyle(Theme.Palette.neutral)

            primaryText

            if let secondary = Conversation.readerText(line, reader: .partner) {
                Text(secondary)
                    .font(Theme.TypeFace.secondary)
                    .foregroundStyle(Theme.Palette.muted)
            }

            statusRow
        }
    }

    @ViewBuilder
    private var primaryText: some View {
        if line.speaker == .me {
            (
                Text(line.committed).foregroundStyle(Theme.Palette.ink)
                    + Text(line.volatile).foregroundStyle(Theme.Palette.neutral)
            )
            .font(Theme.TypeFace.body)
        } else if let translation = line.translation {
            Text(translation)
                .font(Theme.TypeFace.body)
                .foregroundStyle(Theme.Palette.ink)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch line.translationState {
        case .pending:
            PendingDots()
        case .failed:
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Theme.Palette.danger)
                Text("Couldn't translate.")
                    .foregroundStyle(Theme.Palette.danger)
                Button("Retry") { model.retryTranslation(line.id) }
                    .foregroundStyle(Theme.Palette.accent)
            }
            .font(Theme.TypeFace.secondary)
        case .none, .done:
            EmptyView()
        }
    }
}
