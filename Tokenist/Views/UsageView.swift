import SwiftUI

@MainActor
@Observable
final class UsageViewModel {
    var snapshot: UsageSnapshot = .empty
    var isLoading = false
    var lastError: String?

    private let orgId: String
    private let now: @Sendable () -> Date

    init(orgId: String, now: @escaping @Sendable () -> Date = Date.init) {
        self.orgId = orgId
        self.now = now
    }

    func refresh(sessionKey: String) async {
        isLoading = true
        defer { isLoading = false }
        let client = ClaudeAPIClient(sessionKey: sessionKey)
        do {
            let response = try await client.fetchUsage(orgId: orgId)
            let fresh = UsageSnapshot(from: response, fetchedAt: now())
            snapshot = fresh
            lastError = nil
            SharedSnapshotStore.save(fresh)
            WidgetCenterBridge.reloadAll()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct UsageView: View {
    let orgId: String
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: UsageViewModel
    @State private var ticker = Date()
    @AppStorage("notif.enabled") private var notificationsEnabled = false

    private static let refreshInterval: Duration = .seconds(60)

    init(orgId: String) {
        self.orgId = orgId
        _model = State(initialValue: UsageViewModel(orgId: orgId))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                usageMetrics
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let err = model.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding()
            .navigationTitle("Tokenist")
            .navigationSubtitle("Last updated \(model.snapshot.fetchedAt.formatted(.relative(presentation: .named)))")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if model.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Toggle(isOn: $notificationsEnabled) {
                            Label("Threshold alerts (75 / 90 / 95%)", systemImage: "bell")
                        }
                        Divider()
                        Button {
                            if let key = session.currentSessionKey() {
                                UIPasteboard.general.string = key
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
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await refresh()
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.refreshInterval)
                    if Task.isCancelled { break }
                    await refresh()
                }
            }
            .refreshable { await refresh() }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
                ticker = date
            }
            .onChange(of: notificationsEnabled) { _, newValue in
                if newValue {
                    Task { _ = await NotificationManager.shared.requestAuthorization() }
                }
            }
        }
    }

    @ViewBuilder
    private var usageMetrics: some View {
        let opus = visibleModelPercent(model.snapshot.opusWeeklyPct)
        let sonnet = visibleModelPercent(model.snapshot.sonnetWeeklyPct)
        let extraUsage = visibleExtraUsage
        let visibleMetricCount = 2
            + (opus == nil ? 0 : 1)
            + (sonnet == nil ? 0 : 1)
            + (extraUsage == nil ? 0 : 1)

        if visibleMetricCount <= 3 {
            VStack(spacing: 12) {
                sessionBar
                weeklyBar
                if let opus {
                    UsageBar(title: "Opus", percent: opus, detail: nil)
                }
                if let sonnet {
                    UsageBar(title: "Sonnet", percent: sonnet, detail: nil)
                }
                if let extraUsage {
                    UsageBar(
                        title: "Extra",
                        percent: extraUsage.percent,
                        detail: extraUsage.detail
                    )
                }
            }
        } else {
            LazyVGrid(columns: metricColumns, spacing: 12) {
                sessionBar
                weeklyBar
                if let opus {
                    UsageBar(title: "Opus", percent: opus, detail: nil)
                }
                if let sonnet {
                    UsageBar(title: "Sonnet", percent: sonnet, detail: nil)
                }
                if let extraUsage {
                    UsageBar(
                        title: "Extra",
                        percent: extraUsage.percent,
                        detail: extraUsage.detail
                    )
                }
            }
        }
    }

    private var metricColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private var sessionBar: some View {
        UsageBar(
            title: "Session",
            percent: model.snapshot.sessionPct,
            detail: resetText(model.snapshot.sessionResetsAt)
        )
    }

    private var weeklyBar: some View {
        UsageBar(
            title: "Weekly",
            percent: model.snapshot.weeklyPct,
            detail: resetText(model.snapshot.weeklyResetsAt)
        )
    }

    private var visibleExtraUsage: (percent: Double, detail: String)? {
        guard model.snapshot.extraEnabled,
              let spending = model.snapshot.extraSpending,
              let budget = model.snapshot.extraBudget,
              budget > 0 else { return nil }

        let detail = currencyDetail(
            spending: spending,
            budget: budget,
            currency: model.snapshot.extraCurrency ?? "USD"
        )
        return (spending / budget * 100, detail)
    }

    private func visibleModelPercent(_ percent: Double?) -> Double? {
        guard let percent, percent > 0 else { return nil }
        return percent
    }

    private func refresh() async {
        guard let key = session.currentSessionKey() else {
            session.signOut()
            return
        }
        await model.refresh(sessionKey: key)
        await NotificationManager.shared.evaluate(model.snapshot)
    }

    private func resetText(_ resetsAt: Date?) -> String? {
        guard let resetsAt else { return nil }
        let seconds = resetsAt.timeIntervalSince(ticker)
        if seconds <= 0 { return "resets now" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return "resets in " + (formatter.string(from: seconds) ?? "—")
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

// MARK: - Single shared card

private func barTint(_ pct: Double) -> Color {
    switch pct {
    case ..<50: .green
    case ..<75: .yellow
    case ..<90: .orange
    default: .red
    }
}

private func fillWidth(percent: Double, in size: CGSize) -> CGFloat {
    let fraction = CGFloat(min(1, max(0, percent / 100)))
    guard fraction > 0 else { return 0 }
    // Match the widget: keep fill ≥ height so the leading edge stays
    // horizontally rounded instead of flipping vertical.
    return max(size.height, size.width * fraction)
}

private struct UsageBar: View {
    let title: String
    let percent: Double
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(percent.rounded()))")
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText(value: percent))
                    .animation(.smooth(duration: 0.6), value: percent)
                Text("%")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.gray.opacity(0.15))
                    Capsule()
                        .fill(barTint(percent))
                        .frame(width: fillWidth(percent: percent, in: proxy.size))
                }
            }
            .frame(height: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
