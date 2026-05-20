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
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Reads your Claude usage from claude.ai. Paste your session cookie to get started.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Session cookie")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("sk-ant-sid01-…", text: $cookie, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .lineLimit(3...6)
                            .focused($cookieFocused)
                            .font(.system(.callout, design: .monospaced))
                        Link(destination: Self.cookieHelpURL) {
                            HStack(spacing: 4) {
                                Text("How to find your sessionKey")
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.footnote)
                        }
                    }

                    Button {
                        Task { await fetchOrgs() }
                    } label: {
                        if status == .loading {
                            ProgressView()
                        } else {
                            Text("Validate cookie")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || status == .loading)

                    if !orgs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Organization")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Picker("Account", selection: Binding(
                                get: { selectedOrgId ?? "" },
                                set: { selectedOrgId = $0.isEmpty ? nil : $0 }
                            )) {
                                ForEach(orgs) { org in
                                    Text(org.name).tag(org.uuid)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        Button("Save & Continue") {
                            save()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .disabled(selectedOrgId == nil)
                    }

                    if case .error(let msg) = status {
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }

                    Spacer(minLength: 0)
                }
                .padding()
            }
            .navigationTitle("Tokenist")
            .scrollDismissesKeyboard(.interactively)
            .onAppear { cookieFocused = true }
        }
    }

    // MARK: - Actions

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
