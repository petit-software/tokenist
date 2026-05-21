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
                    VStack(spacing: 12) {
                        AppIconView()
                        VStack(spacing: 4) {
                            Text("Tokenist")
                                .font(.largeTitle.weight(.bold))
                            Text("Read your Claude usage")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section {
                    TextField("Session cookie: sk-ant-sid01-…", text: $cookie, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(3...6)
                        .focused($cookieFocused)
                        .font(.system(.body, design: .monospaced))
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
                        ForEach(orgs) { org in
                            Button {
                                selectedOrgId = org.uuid
                            } label: {
                                HStack {
                                    Text(org.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedOrgId == org.uuid {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: Self.cookieHelpURL) {
                        Label("How to find your session key", systemImage: "questionmark.circle")
                    }
                }
            }
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

private struct AppIconView: View {
    var body: some View {
        if let image = Self.bundleIcon {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .clipShape(.rect(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .padding(.vertical, 12)
        }
    }

    private static var bundleIcon: UIImage? {
        guard
            let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let files = primary["CFBundleIconFiles"] as? [String],
            let lastName = files.last
        else { return nil }
        return UIImage(named: lastName)
    }
}
