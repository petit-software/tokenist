import SwiftUI

struct OnboardingView: View {
    @Environment(SessionStore.self) private var session

    @State private var cookie: String = ""
    @State private var orgs: [Organization] = []
    @State private var selectedOrgId: String?
    @State private var status: Status = .idle
    @FocusState private var cookieFocused: Bool

    enum Status: Equatable {
        case idle
        case loading
        case error(String)
        case loaded
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Tokenist reads your Claude usage from claude.ai. Paste your session cookie below to get started.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Connect to Claude")
                }

                Section {
                    TextField("sk-ant-sid01-…", text: $cookie, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(3...6)
                        .focused($cookieFocused)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Session cookie")
                } footer: {
                    Text("In a browser logged into claude.ai: DevTools → Application → Cookies → sessionKey. Copy the value here.")
                }

                Section {
                    Button {
                        Task { await fetchOrgs() }
                    } label: {
                        if case .loading = status {
                            ProgressView()
                        } else {
                            Text("Validate cookie")
                        }
                    }
                    .disabled(cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || status == .loading)
                }

                if !orgs.isEmpty {
                    Section("Organization") {
                        Picker("Account", selection: Binding(
                            get: { selectedOrgId ?? "" },
                            set: { selectedOrgId = $0.isEmpty ? nil : $0 }
                        )) {
                            ForEach(orgs) { org in
                                Text(org.name).tag(org.uuid)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }

                    Section {
                        Button {
                            save()
                        } label: {
                            Text("Save & Continue")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedOrgId == nil)
                    }
                }

                if case .error(let msg) = status {
                    Section {
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Tokenist")
            .onAppear { cookieFocused = true }
        }
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
