import Foundation
import Observation

@MainActor
@Observable
final class MacDataStore {
    var snapshot: UsageSnapshot = .empty
    var isLoading = false
    var lastError: String?

    private let credentialsProvider: @MainActor () -> (orgId: String, sessionKey: String)?
    private var refreshTask: Task<Void, Never>?

    init(credentialsProvider: @MainActor @escaping () -> (orgId: String, sessionKey: String)?) {
        self.credentialsProvider = credentialsProvider
        startLoop()
    }

    func refreshNow() async {
        guard let creds = credentialsProvider() else { return }
        await refresh(orgId: creds.orgId, sessionKey: creds.sessionKey)
    }

    private func startLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let creds = self.credentialsProvider() {
                    await self.refresh(orgId: creds.orgId, sessionKey: creds.sessionKey)
                    try? await Task.sleep(for: .seconds(60))
                } else {
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        }
    }

    private func refresh(orgId: String, sessionKey: String) async {
        isLoading = true
        defer { isLoading = false }
        let client = ClaudeAPIClient(sessionKey: sessionKey)
        do {
            let response = try await client.fetchUsage(orgId: orgId)
            snapshot = UsageSnapshot(from: response)
            lastError = nil
            await NotificationManager.shared.evaluate(snapshot)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
