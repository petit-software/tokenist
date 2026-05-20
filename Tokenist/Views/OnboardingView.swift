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

    private static let cookieHelpURL = URL(string: "https://github.com/petit-software/tokenist#3-get-your-claude-session-cookie")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Reads your Claude usage from claude.ai. Paste your session cookie to get started.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Session cookie")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("sk-ant-sid01-…", text: $cookie, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .lineLimit(3...6)
                            .focused($cookieFocused)
                            .font(.system(.body, design: .monospaced))
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))

                        Link(destination: Self.cookieHelpURL) {
                            HStack(spacing: 4) {
                                Text("How to find your sessionKey")
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.caption)
                        }
                    }

                    Button {
                        Task { await fetchOrgs() }
                    } label: {
                        Group {
                            if case .loading = status {
                                ProgressView()
                            } else {
                                Text("Validate cookie")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || status == .loading)

                    if !orgs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Organization")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: Binding(
                                get: { selectedOrgId ?? "" },
                                set: { selectedOrgId = $0.isEmpty ? nil : $0 }
                            )) {
                                ForEach(orgs) { org in
                                    Text(org.name).tag(org.uuid)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }

                        Button {
                            save()
                        } label: {
                            Text("Save & Continue")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(selectedOrgId == nil)
                    }

                    if case .error(let msg) = status {
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
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
