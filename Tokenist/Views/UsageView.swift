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
            snapshot = UsageSnapshot(from: response, fetchedAt: now())
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct UsageView: View {
    let orgId: String
    @Environment(SessionStore.self) private var session
    @State private var model: UsageViewModel
    @State private var ticker = Date()

    init(orgId: String) {
        self.orgId = orgId
        _model = State(initialValue: UsageViewModel(orgId: orgId))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        UsageBar(
                            title: "Session",
                            percent: model.snapshot.sessionPct,
                            detail: resetText(model.snapshot.sessionResetsAt)
                        )
                        UsageBar(
                            title: "Weekly",
                            percent: model.snapshot.weeklyPct,
                            detail: resetText(model.snapshot.weeklyResetsAt)
                        )
                    }
                    GridRow {
                        UsageBar(
                            title: "Opus",
                            percent: model.snapshot.opusWeeklyPct ?? 0,
                            detail: model.snapshot.opusWeeklyPct == nil ? "—" : nil
                        )
                        UsageBar(
                            title: "Sonnet",
                            percent: model.snapshot.sonnetWeeklyPct ?? 0,
                            detail: model.snapshot.sonnetWeeklyPct == nil ? "—" : nil
                        )
                    }
                }
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
                        Button("Sign out", role: .destructive) { session.signOut() }
                    } label: {
                        Image(systemName: "key.horizontal")
                    }
                }
            }
            .task { await refresh() }
            .refreshable { await refresh() }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
                ticker = date
            }
        }
    }

    private func refresh() async {
        guard let key = session.currentSessionKey() else {
            session.signOut()
            return
        }
        await model.refresh(sessionKey: key)
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
                    .monospacedDigit()
                    .contentTransition(.numericText(value: percent))
                Text("%")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.gray.opacity(0.15))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(barTint(percent))
                        .frame(width: proxy.size.width * CGFloat(min(1, max(0, percent / 100))))
                        .animation(.easeOut(duration: 0.6), value: percent)
                }
            }
            .frame(height: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
