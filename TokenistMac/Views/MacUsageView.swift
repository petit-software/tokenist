import SwiftUI

struct MacUsageView: View {
    let orgId: String
    @Environment(SessionStore.self) private var session
    @Environment(MacDataStore.self) private var dataStore
    @State private var ticker = Date()
    @AppStorage("notif.enabled") private var notificationsEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tokenist").font(.headline)
                Spacer()
                if dataStore.isLoading {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await dataStore.refreshNow() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(dataStore.isLoading)
            }

            UsageRow(
                title: "5-hour session",
                percent: dataStore.snapshot.sessionPct,
                resetText: resetText(dataStore.snapshot.sessionResetsAt)
            )
            UsageRow(
                title: "Weekly (all models)",
                percent: dataStore.snapshot.weeklyPct,
                resetText: resetText(dataStore.snapshot.weeklyResetsAt)
            )
            if let opus = dataStore.snapshot.opusWeeklyPct {
                UsageRow(title: "Opus weekly", percent: opus, resetText: nil)
            }
            if let sonnet = dataStore.snapshot.sonnetWeeklyPct {
                UsageRow(title: "Sonnet weekly", percent: sonnet, resetText: nil)
            }

            if dataStore.snapshot.extraEnabled,
               let spending = dataStore.snapshot.extraSpending,
               let budget = dataStore.snapshot.extraBudget,
               budget > 0 {
                UsageRow(
                    title: "Extra usage",
                    percent: spending / budget * 100,
                    resetText: currencyDetail(
                        spending: spending,
                        budget: budget,
                        currency: dataStore.snapshot.extraCurrency ?? "USD"
                    )
                )
            }

            if let err = dataStore.lastError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Divider().padding(.vertical, 2)

            HStack {
                Text(dataStore.snapshot.fetchedAt == .distantPast
                     ? "Loading…"
                     : "Updated \(dataStore.snapshot.fetchedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Toggle(isOn: $notificationsEnabled) {
                        Label("Threshold alerts (75 / 90 / 95%)", systemImage: "bell")
                    }
                    Divider()
                    Button {
                        if let key = session.currentSessionKey() {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(key, forType: .string)
                        }
                    } label: {
                        Label("Copy cookie", systemImage: "document.on.document")
                    }
                    Link(destination: URL(string: "https://github.com/petit-software/tokenist")!) {
                        Label("GitHub", systemImage: "info")
                    }
                    Divider()
                    Button(role: .destructive) {
                        session.signOut()
                    } label: {
                        Label("Sign out", systemImage: "key.horizontal")
                    }
                    Divider()
                    Button("Quit Tokenist") {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(14)
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { date in
            ticker = date
        }
        .onChange(of: notificationsEnabled) { _, newValue in
            if newValue {
                Task { _ = await NotificationManager.shared.requestAuthorization() }
            }
        }
    }

    private func resetText(_ resetsAt: Date?) -> String? {
        guard let resetsAt else { return nil }
        let seconds = resetsAt.timeIntervalSince(ticker)
        if seconds <= 0 { return "resets now" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return "resets " + (formatter.string(from: seconds) ?? "—")
    }

    private func currencyDetail(spending: Double, budget: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        let spent = formatter.string(from: spending as NSNumber) ?? "\(spending)"
        let cap = formatter.string(from: budget as NSNumber) ?? "\(budget)"
        return "\(spent) of \(cap)"
    }
}

private struct UsageRow: View {
    let title: String
    let percent: Double
    let resetText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text("\(Int(percent.rounded()))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(.gray.opacity(0.18))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(tint)
                        .frame(width: proxy.size.width * CGFloat(min(1, max(0, percent / 100))))
                }
            }
            .frame(height: 6)
            if let resetText {
                Text(resetText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var tint: Color {
        switch percent {
        case ..<50: .green
        case ..<75: .yellow
        case ..<90: .orange
        default: .red
        }
    }
}
