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
        ZStack {
            backgroundTint

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    cookieGroup

                    primaryButton(
                        title: "Validate cookie",
                        isLoading: status == .loading,
                        isDisabled: cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || status == .loading
                    ) {
                        Task { await fetchOrgs() }
                    }

                    if !orgs.isEmpty {
                        orgGroup

                        primaryButton(
                            title: "Save & Continue",
                            isLoading: false,
                            isDisabled: selectedOrgId == nil
                        ) {
                            save()
                        }
                    }

                    if case .error(let msg) = status {
                        errorBanner(msg)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { cookieFocused = true }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tokenist")
                .font(.system(size: 38, weight: .bold))
            Text("Reads your Claude usage from claude.ai. Paste your session cookie to get started.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var cookieGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session cookie")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            TextField("sk-ant-sid01-…", text: $cookie, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(3...6)
                .focused($cookieFocused)
                .font(.system(.callout, design: .monospaced))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))

            Link(destination: Self.cookieHelpURL) {
                HStack(spacing: 4) {
                    Text("How to find your sessionKey")
                    Image(systemName: "arrow.up.right")
                }
                .font(.footnote.weight(.medium))
            }
            .padding(.horizontal, 4)
        }
    }

    private var orgGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Organization")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            Menu {
                Picker("", selection: Binding(
                    get: { selectedOrgId ?? "" },
                    set: { selectedOrgId = $0.isEmpty ? nil : $0 }
                )) {
                    ForEach(orgs) { org in
                        Text(org.name).tag(org.uuid)
                    }
                }
            } label: {
                HStack {
                    Text(currentOrgName)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
            }
        }
    }

    private func primaryButton(
        title: String,
        isLoading: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                } else {
                    Text(title)
                        .font(.body.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(.vertical, 14)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(Color(red: 0.27, green: 0.50, blue: 0.95))
        .disabled(isDisabled)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.red.opacity(0.15)), in: .rect(cornerRadius: 18))
    }

    // MARK: - Background

    private var backgroundTint: some View {
        LinearGradient(
            colors: [
                Color(red: 0.85, green: 0.92, blue: 1.0),
                Color(red: 0.95, green: 0.97, blue: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            Circle()
                .fill(Color(red: 0.40, green: 0.62, blue: 0.96).opacity(0.45))
                .frame(width: 360, height: 360)
                .blur(radius: 110)
                .offset(x: -110, y: -180)
                .ignoresSafeArea()
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(Color(red: 0.55, green: 0.72, blue: 0.97).opacity(0.35))
                .frame(width: 320, height: 320)
                .blur(radius: 130)
                .offset(x: 130, y: 280)
                .ignoresSafeArea()
        }
    }

    private var currentOrgName: String {
        guard let id = selectedOrgId, let org = orgs.first(where: { $0.uuid == id }) else {
            return "Select…"
        }
        return org.name
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
