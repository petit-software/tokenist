import SwiftUI

struct MacOnboardingView: View {
    @Environment(SessionStore.self) private var session

    @State private var cookie: String = ""
    @State private var orgs: [Organization] = []
    @State private var selectedOrgId: String?
    @State private var status: Status = .idle

    enum Status: Equatable {
        case idle, loading, error(String), loaded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tokenist")
                .font(.title2.weight(.semibold))
            Text("Paste your claude.ai session cookie to get started.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Session cookie").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $cookie)
                    .font(.system(.callout, design: .monospaced))
                    .frame(height: 64)
                    .padding(6)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .topLeading) {
                        if cookie.isEmpty {
                            Text("sk-ant-sid01-…")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                        }
                    }
                Text("In a browser logged into claude.ai: DevTools → Application → Cookies → sessionKey.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                if case .loading = status {
                    ProgressView().controlSize(.small)
                }
                Button("Validate cookie") {
                    Task { await fetchOrgs() }
                }
                .disabled(cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || status == .loading)
                .keyboardShortcut(.defaultAction)
                Spacer()
            }

            if !orgs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Organization").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { selectedOrgId ?? "" },
                        set: { selectedOrgId = $0.isEmpty ? nil : $0 }
                    )) {
                        ForEach(orgs) { org in
                            Text(org.name).tag(org.uuid)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                Button {
                    save()
                } label: {
                    Text("Save & Connect").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedOrgId == nil)
            }

            if case .error(let msg) = status {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding(16)
    }

    private func fetchOrgs() async {
        status = .loading
        let trimmed = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = ClaudeAPIClient(sessionKey: trimmed)
        do {
            let fetched = try await client.listOrganizations()
            orgs = fetched
            selectedOrgId = fetched.first?.uuid
            status = .loaded
        } catch {
            orgs = []
            selectedOrgId = nil
            status = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func save() {
        guard let orgId = selectedOrgId else { return }
        let trimmed = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try session.saveCredentials(sessionKey: trimmed, orgId: orgId)
        } catch {
            status = .error("Could not save to Keychain: \(error.localizedDescription)")
        }
    }
}
