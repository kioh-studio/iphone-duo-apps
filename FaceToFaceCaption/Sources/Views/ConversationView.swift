import SwiftUI
import UIKit

struct ConversationView: View {
    @Environment(ConversationModel.self) private var model

    var body: some View {
        @Bindable var model = model
        content
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            .sensoryFeedback(.selection, trigger: model.turn)
            .sheet(isPresented: $model.isSetupSheetPresented) {
                LanguageSetupView(mode: .sheet)
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.displays.hasFacingDisplay {
            MySideView(layout: .separateScreens)
        } else {
            VStack(spacing: 0) {
                PartnerCaptionView(showsTurnButton: true)
                    .rotationEffect(.degrees(180))
                    .frame(maxHeight: .infinity)
                Color.clear.frame(height: Theme.Space.foldBand)
                MySideView(layout: .sharedTable)
                    .frame(maxHeight: .infinity)
            }
        }
    }
}
