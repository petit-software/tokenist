import SwiftUI

struct MacRootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        switch session.phase {
        case .unconfigured:
            MacOnboardingView()
        case .configured(let orgId):
            MacUsageView(orgId: orgId)
        }
    }
}
