import SwiftUI

@MainActor
@Observable
final class UsageViewModel {
    var snapshot: UsageSnapshot = .empty
    var isLoading = false
    var lastError: String?

    private let orgId: String
    private let now: @Sendable () -> Date

    init(
        orgId: String,
        snapshot: UsageSnapshot = .empty,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.orgId = orgId
        self.snapshot = snapshot
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
        } catch ClaudeAPIClient.APIError.cancelled {
            // SwiftUI can cancel a refresh when its task is replaced or the view changes.
            // This is expected lifecycle control, not a user-facing failure.
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct UsageView: View {
    let orgId: String
    private let refreshEnabled: Bool
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: UsageViewModel
    @State private var ticker = Date()
    @State private var showsAbout = false
    @AppStorage("notif.enabled") private var notificationsEnabled = false
    @AppStorage("usage.showRemaining") private var showRemainingUsage = false

    private static let refreshInterval: Duration = .seconds(60)

    init(
        orgId: String,
        initialSnapshot: UsageSnapshot = .empty,
        refreshEnabled: Bool = true
    ) {
        self.orgId = orgId
        self.refreshEnabled = refreshEnabled
        _model = State(
            initialValue: UsageViewModel(orgId: orgId, snapshot: initialSnapshot)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                usageMetrics

                if let err = model.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .contentMargins(.top, 16, for: .scrollContent)
            .contentMargins(.bottom, 24, for: .scrollContent)
            .scrollIndicators(.hidden)
            .refreshable { await refresh() }
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
                        Toggle(isOn: $showRemainingUsage) {
                            Label("Show remaining usage", systemImage: "gauge.with.dots.needle.33percent")
                        }
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
                        Button {
                            showsAbout = true
                        } label: {
                            Label("About", systemImage: "info.circle")
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
            .sheet(isPresented: $showsAbout) {
                AboutSheet()
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

    private var usageMetrics: some View {
        let opus = visibleModelPercent(model.snapshot.opusWeeklyPct)
        let sonnet = visibleModelPercent(model.snapshot.sonnetWeeklyPct)
        let extraUsage = visibleExtraUsage

        return LazyVStack(spacing: 12) {
            sessionBar
                .containerRelativeFrame(.vertical, count: 3, span: 1, spacing: 12)
                .frame(minHeight: 180)

            WeeklyUsageCard(
                allModelsPercent: displayedPercent(model.snapshot.weeklyPct),
                allModelsDetail: resetText(model.snapshot.weeklyResetsAt),
                fablePercent: model.snapshot.fableWeeklyPct.map(displayedPercent),
                fableDetail: resetText(model.snapshot.fableWeeklyResetsAt),
                showsRemaining: showRemainingUsage
            )
            .containerRelativeFrame(.vertical, count: 3, span: 2, spacing: 12)
            .frame(minHeight: 320)

            if opus != nil || sonnet != nil || extraUsage != nil {
                LazyVGrid(columns: metricColumns, spacing: 12) {
                    if let opus {
                        UsageBar(
                            title: metricTitle("Opus"),
                            percent: displayedPercent(opus),
                            detail: nil,
                            showsRemaining: showRemainingUsage
                        )
                        .containerRelativeFrame(.vertical, count: 3, span: 1, spacing: 12)
                        .frame(minHeight: 180)
                    }
                    if let sonnet {
                        UsageBar(
                            title: metricTitle("Sonnet"),
                            percent: displayedPercent(sonnet),
                            detail: nil,
                            showsRemaining: showRemainingUsage
                        )
                        .containerRelativeFrame(.vertical, count: 3, span: 1, spacing: 12)
                        .frame(minHeight: 180)
                    }
                    if let extraUsage {
                        UsageBar(
                            title: showRemainingUsage ? "Extra budget left" : "Extra",
                            percent: displayedPercent(extraUsage.percent),
                            detail: extraUsage.detail,
                            showsRemaining: showRemainingUsage
                        )
                        .containerRelativeFrame(.vertical, count: 3, span: 1, spacing: 12)
                        .frame(minHeight: 180)
                    }
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
            title: metricTitle("Session"),
            percent: displayedPercent(model.snapshot.sessionPct),
            detail: resetText(model.snapshot.sessionResetsAt),
            showsRemaining: showRemainingUsage
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

    private func displayedPercent(_ usedPercent: Double) -> Double {
        guard showRemainingUsage else { return usedPercent }
        return min(100, max(0, 100 - usedPercent))
    }

    private func metricTitle(_ title: String) -> String {
        showRemainingUsage ? "\(title) left" : title
    }

    private func refresh() async {
        guard refreshEnabled else { return }
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

private struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    ZStack {
                        Link(destination: URL(string: "https://petit.software")!) {
                            Image("PetitLabel")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.primary)
                                .frame(maxWidth: 280)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Visit Petit Software")

                        Text("If you find this app useful, please share it with your friends as a sign of gratitude. – Your friends @ Petit")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 22)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: max(0, proxy.size.height - 40), alignment: .center)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 20)
                }
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
                    Link(destination: URL(string: "https://github.com/petit-software/tokenist")!) {
                        Image(systemName: "arrow.up.right")
                    }
                    .accessibilityLabel("GitHub")
                }
            }
        }
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

private struct WeeklyUsageCard: View {
    let allModelsPercent: Double
    let allModelsDetail: String?
    let fablePercent: Double?
    let fableDetail: String?
    let showsRemaining: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(showsRemaining ? "Weekly left" : "Weekly")
                .font(.headline)

            VStack(spacing: 16) {
                if let fablePercent {
                    WeeklyMetric(
                        title: showsRemaining ? "Fable left" : "Fable",
                        percent: fablePercent,
                        detail: fableDetail,
                        showsRemaining: showsRemaining
                    )

                    Divider()
                }

                WeeklyMetric(
                    title: showsRemaining ? "All models left" : "All models",
                    percent: allModelsPercent,
                    detail: allModelsDetail,
                    showsRemaining: showsRemaining
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.primary.opacity(0.2), lineWidth: 0.5)
        }
    }
}

private struct WeeklyMetric: View {
    let title: String
    let percent: Double
    let detail: String?
    let showsRemaining: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(percent.rounded()))")
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText(value: percent))
                    .animation(.smooth(duration: 0.6), value: percent)
                Text("%")
                    .font(.headline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.regularMaterial)
                    Capsule()
                        .fill(barTint(showsRemaining ? 100 - percent : percent))
                        .frame(width: fillWidth(percent: percent, in: proxy.size))
                }
            }
            .frame(height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct UsageBar: View {
    let title: String
    let percent: Double
    let detail: String?
    let showsRemaining: Bool

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
                        .fill(Color(uiColor: .systemBackground))
                    Capsule()
                        .fill(barTint(showsRemaining ? 100 - percent : percent))
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

private extension UsageSnapshot {
    static func preview(
        session: Double,
        weekly: Double,
        fable: Double
    ) -> UsageSnapshot {
        UsageSnapshot(
            sessionPct: session,
            sessionResetsAt: .now.addingTimeInterval(2 * 60 * 60),
            weeklyPct: weekly,
            weeklyResetsAt: .now.addingTimeInterval(3 * 24 * 60 * 60),
            fableWeeklyPct: fable,
            fableWeeklyResetsAt: .now.addingTimeInterval(3 * 24 * 60 * 60),
            opusWeeklyPct: nil,
            sonnetWeeklyPct: nil,
            extraSpending: nil,
            extraBudget: nil,
            extraCurrency: nil,
            extraEnabled: false,
            fetchedAt: .now
        )
    }
}

private struct UsagePreview: View {
    let snapshot: UsageSnapshot

    var body: some View {
        UsageView(
            orgId: "preview",
            initialSnapshot: snapshot,
            refreshEnabled: false
        )
        .environment(SessionStore())
    }
}

#Preview("Minimal usage") {
    UsagePreview(snapshot: .preview(session: 5, weekly: 10, fable: 3))
}

#Preview("Mid-range usage") {
    UsagePreview(snapshot: .preview(session: 42, weekly: 58, fable: 31))
}

#Preview("Maxed usage") {
    UsagePreview(snapshot: .preview(session: 100, weekly: 100, fable: 100))
}
