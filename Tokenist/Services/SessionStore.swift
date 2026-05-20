import Foundation
import Observation

@Observable
@MainActor
final class SessionStore {
    enum Phase: Equatable {
        case unconfigured
        case configured(orgId: String)
    }

    private(set) var phase: Phase

    init() {
        let hasKey = KeychainStore.loadSessionKey() != nil
        let orgId = SharedDefaults.orgId
        if hasKey, let orgId, !orgId.isEmpty {
            self.phase = .configured(orgId: orgId)
        } else {
            self.phase = .unconfigured
        }
    }

    func saveCredentials(sessionKey: String, orgId: String) throws {
        try KeychainStore.saveSessionKey(sessionKey)
        SharedDefaults.orgId = orgId
        phase = .configured(orgId: orgId)
        WidgetCenterBridge.reloadAll()
    }

    func signOut() {
        KeychainStore.deleteSessionKey()
        SharedDefaults.orgId = nil
        phase = .unconfigured
        WidgetCenterBridge.reloadAll()
    }

    func currentSessionKey() -> String? {
        KeychainStore.loadSessionKey()
    }
}

import WidgetKit

enum WidgetCenterBridge {
    static func reloadAll() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
