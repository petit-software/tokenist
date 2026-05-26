import SwiftUI

struct OnboardingView: View {
    @Environment(SessionStore.self) private var session

    @State private var cookie: String = ""
    @State private var orgs: [Organization] = []
    @State private var selectedOrgId: String?
    @State private var status: Status = .idle
    @State private var showCookieHelp = false
    @FocusState private var cookieFocused: Bool

    enum Status: Equatable {
        case idle, loading, error(String), loaded
    }

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
                    Button {
                        showCookieHelp = true
                    } label: {
                        Label("How to find your session cookie", systemImage: "questionmark")
                    }
                }
            }
            .sheet(isPresented: $showCookieHelp) {
                CookieHelpSheet()
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

private struct CookieHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    private static let repoURL = URL(string: "https://github.com/petit-software/tokenist")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("How to get session cookie")
                        .font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 32)

                    Text("Tokenist reads your Claude usage by calling the same endpoints claude.ai uses. To do that it needs your session cookie.")
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 32)

                    VStack(alignment: .leading, spacing: 22) {
                        StepRow(
                            number: 1,
                            title: "Sign in to claude.ai",
                            detail: "Use a desktop browser — mobile browsers don't expose cookies."
                        )
                        StepRow(
                            number: 2,
                            title: "Open Developer Tools",
                            detail: "Chrome or Edge: ⌘ + ⌥ + I. Safari: enable the Develop menu in Settings, then ⌘ + ⌥ + C."
                        )
                        StepRow(
                            number: 3,
                            title: "Find the sessionKey cookie",
                            detail: "Application → Cookies → claude.ai → sessionKey."
                        )
                        StepRow(
                            number: 4,
                            title: "Copy the Value",
                            detail: "It starts with sk-ant-sid01-…"
                        )
                        StepRow(
                            number: 5,
                            title: "Paste it back here",
                            detail: "Then tap Validate cookie to pick an organization."
                        )
                    }
                    .padding(.horizontal, 32)

                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: "lock.fill")
                        Text("The cookie is saved to the iOS Keychain on this device and is only sent to Anthropic.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
                    .padding(.trailing, 12)
                    .padding(.leading, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quinary, in: .rect(cornerRadius: 16, style: .continuous))
                    .padding(.top, 4)
                    .padding(.horizontal, 32)
                }
                .padding(.vertical, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: Self.repoURL) {
                        Label("GitHub", systemImage: "info")
                    }
                }
            }
        }
    }
}

private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String

    private static let symbolWidth: CGFloat = 36
    private static let symbolSpacing: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: Self.symbolSpacing) {
                Image(systemName: "\(number).circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .tint)
                    .frame(width: Self.symbolWidth, alignment: .center)
                Text(title)
                    .font(.title3.weight(.semibold))
            }
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, Self.symbolWidth + Self.symbolSpacing)
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
