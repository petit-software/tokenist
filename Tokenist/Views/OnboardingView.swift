import SwiftUI

struct OnboardingView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme

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
        ZStack {
            AtmosphericBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    cookieField

                    primaryButton(
                        label: "Validate cookie",
                        isLoading: status == .loading,
                        isDisabled: cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || status == .loading
                    ) {
                        Task { await fetchOrgs() }
                    }

                    if !orgs.isEmpty {
                        orgPicker
                        primaryButton(
                            label: "Save & Continue",
                            isLoading: false,
                            isDisabled: selectedOrgId == nil
                        ) {
                            save()
                        }
                    }

                    if case .error(let msg) = status {
                        errorBanner(msg)
                    }

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 22)
                .padding(.top, 32)
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
                .font(.system(size: 40, weight: .bold))
                .tracking(-0.6)
            Text("Reads your Claude usage from claude.ai. Paste your session cookie to get started.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var cookieField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session cookie")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            TextField("sk-ant-sid01-…", text: $cookie, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(3...6)
                .focused($cookieFocused)
                .font(.system(.callout, design: .monospaced))
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(glassSurface(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(highlightStroke, lineWidth: 0.6)
                )
                .shadow(color: .black.opacity(0.07), radius: 18, y: 8)

            Link(destination: Self.cookieHelpURL) {
                HStack(spacing: 4) {
                    Text("How to find your sessionKey")
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                }
                .font(.footnote.weight(.medium))
            }
        }
    }

    private var orgPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Organization")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

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
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(glassSurface(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(highlightStroke, lineWidth: 0.6)
                )
                .shadow(color: .black.opacity(0.07), radius: 18, y: 8)
            }
        }
    }

    private func primaryButton(
        label: String,
        isLoading: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(label)
                        .font(.body.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 26)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isDisabled
                                ? [Color.gray.opacity(0.45), Color.gray.opacity(0.35)]
                                : [Color(red: 0.36, green: 0.58, blue: 0.96),
                                   Color(red: 0.25, green: 0.45, blue: 0.92)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6)
            )
            .foregroundStyle(.white)
            .shadow(
                color: isDisabled ? .clear : Color(red: 0.25, green: 0.45, blue: 0.92).opacity(0.32),
                radius: 18, y: 8
            )
        }
        .disabled(isDisabled)
        .animation(.easeOut(duration: 0.18), value: isDisabled)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.red.opacity(0.25), lineWidth: 0.6)
        )
    }

    // MARK: - Styling helpers

    private func glassSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.regularMaterial)
    }

    private var highlightStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.white.opacity(0.6)
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

// MARK: - Atmospheric background

private struct AtmosphericBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.05, green: 0.08, blue: 0.16),
                        Color(red: 0.07, green: 0.12, blue: 0.22)
                      ]
                    : [
                        Color(red: 0.92, green: 0.95, blue: 1.0),
                        Color(red: 0.97, green: 0.98, blue: 1.0)
                      ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Soft blue glow upper-left
            Circle()
                .fill(Color(red: 0.40, green: 0.62, blue: 0.96).opacity(colorScheme == .dark ? 0.35 : 0.55))
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .offset(x: -120, y: -240)

            // Cooler glow lower-right
            Circle()
                .fill(Color(red: 0.62, green: 0.78, blue: 0.98).opacity(colorScheme == .dark ? 0.25 : 0.50))
                .frame(width: 360, height: 360)
                .blur(radius: 140)
                .offset(x: 140, y: 320)
        }
        .ignoresSafeArea()
    }
}
