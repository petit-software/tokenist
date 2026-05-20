import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        switch session.phase {
        case .unconfigured:
            OnboardingView()
        case .configured(let orgId):
            UsageView(orgId: orgId)
        }
    }
}
