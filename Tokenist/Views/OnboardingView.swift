import SwiftUI

struct OnboardingView: View {
    @Environment(SessionStore.self) private var session

    @State private var cookie: String = ""
    @State private var orgs: [Organization] = []
    @State private var selectedOrgId: String?
    @State private var status: Status = .idle
    @FocusState private var cookieFocused: Bool

    enum Status: Equatable {
        case idle, loading, error(String), loaded
    }

    private static let cookieHelpURL = URL(string: "https://github.com/petit-software/tokenist#3-get-your-claude-session-cookie")!

    var body: some View {
        NavigationStack {
            Form {
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
                    Link(destination: Self.cookieHelpURL) {
                        HStack(spacing: 4) {
                            Text("How to find your sessionKey")
                            Image(systemName: "arrow.up.right")
                        }
                    }
                }

                Section {
                    Button {
                        Task { await fetchOrgs() }
                    } label: {
                        HStack {
                            Spacer()
                            if status == .loading {
                                ProgressView()
                            } else {
                                Text("Validate cookie")
                            }
                            Spacer()
                        }
                    }
                    .disabled(cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || status == .loading)
                }

                if !orgs.isEmpty {
                    Section {
                        Picker("Account", selection: Binding(
                            get: { selectedOrgId ?? "" },
                            set: { selectedOrgId = $0.isEmpty ? nil : $0 }
                        )) {
                            ForEach(orgs) { org in
                                Text(org.name).tag(org.uuid)
                            }
                        }
                    } header: {
                        Text("Organization")
                    }

                    Section {
                        Button {
                            save()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Save & Continue")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
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
            .navigationSubtitle("Reads your Claude usage from claude.ai")
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
