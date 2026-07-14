import WidgetKit
import SwiftUI

private struct SendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

@main
struct TokenistWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenistWidget()
    }
}

struct TokenistWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TokenistWidget", provider: TokenistTimelineProvider()) { entry in
            TokenistWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tokenist")
        .description("Claude usage at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall])
        .contentMarginsDisabled()
    }
}

struct TokenistEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
    let needsSetup: Bool
    let errorMessage: String?
}

struct TokenistTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TokenistEntry {
        TokenistEntry(date: Date(), snapshot: .empty, needsSetup: false, errorMessage: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TokenistEntry) -> Void) {
        let sample = UsageSnapshot(
            sessionPct: 42,
            sessionResetsAt: Date().addingTimeInterval(60 * 60 * 2),
            weeklyPct: 23,
            weeklyResetsAt: Date().addingTimeInterval(60 * 60 * 24 * 3),
            fableWeeklyPct: 31,
            fableWeeklyResetsAt: Date().addingTimeInterval(60 * 60 * 24 * 3),
            opusWeeklyPct: nil,
            sonnetWeeklyPct: 10,
            extraSpending: nil,
            extraBudget: nil,
            extraCurrency: nil,
            extraEnabled: false,
            fetchedAt: Date()
        )
        completion(TokenistEntry(date: Date(), snapshot: sample, needsSetup: false, errorMessage: nil))
    }

    // How long the widget trusts a cache written by the main app before doing
    // its own network fetch. The app refreshes every 60s while foregrounded
    // and calls WidgetCenter.reloadAllTimelines after each success, so anything
    // newer than this window is almost certainly the same data the user just saw.
    private static let freshCacheWindow: TimeInterval = 5 * 60

    // Refresh policy budget — iOS treats this as a hint; accessory widgets get a
    // tighter budget than home-screen ones, so 15 minutes is the floor worth asking for.
    private static let timelineRefreshInterval: TimeInterval = 15 * 60

    func getTimeline(in context: Context, completion: @escaping (Timeline<TokenistEntry>) -> Void) {
        let box = SendableBox(completion)
        Task {
            let entry = await loadEntry()
            let nextRefresh = Date().addingTimeInterval(Self.timelineRefreshInterval)
            box.value(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    private func loadEntry() async -> TokenistEntry {
        guard KeychainStore.loadSessionKey() != nil,
              let orgId = SharedDefaults.orgId,
              !orgId.isEmpty else {
            return TokenistEntry(date: Date(), snapshot: .empty, needsSetup: true, errorMessage: nil)
        }

        let cached = SharedSnapshotStore.load()

        // Cache-first: if the main app pushed something recent, render instantly
        // without burning the widget extension's limited execution time on a network call.
        if let cached, -cached.fetchedAt.timeIntervalSinceNow < Self.freshCacheWindow {
            return TokenistEntry(date: Date(), snapshot: cached, needsSetup: false, errorMessage: nil)
        }

        // Stale or missing cache: try the network, falling back to the stale cache on failure.
        guard let key = KeychainStore.loadSessionKey() else {
            return TokenistEntry(date: Date(), snapshot: .empty, needsSetup: true, errorMessage: nil)
        }
        do {
            let client = ClaudeAPIClient(sessionKey: key)
            let response = try await client.fetchUsage(orgId: orgId)
            let fresh = UsageSnapshot(from: response)
            SharedSnapshotStore.save(fresh)
            return TokenistEntry(date: Date(), snapshot: fresh, needsSetup: false, errorMessage: nil)
        } catch {
            if let cached {
                return TokenistEntry(date: Date(), snapshot: cached, needsSetup: false, errorMessage: nil)
            }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return TokenistEntry(date: Date(), snapshot: .empty, needsSetup: false, errorMessage: message)
        }
    }
}

// MARK: - Widget views

struct TokenistWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TokenistEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularView(entry: entry)
        case .accessoryRectangular:
            RectangularView(entry: entry)
        case .systemSmall:
            SmallView(entry: entry)
        default:
            Text("Unsupported").font(.caption)
        }
    }
}

private struct SmallView: View {
    let entry: TokenistEntry

    var body: some View {
        if entry.needsSetup {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.title2)
                Text("Open Tokenist to sign in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Group {
                if let fable = entry.snapshot.fableWeeklyPct {
                    VStack(alignment: .leading, spacing: 8) {
                        compactMetricBlock(title: "Session", percent: entry.snapshot.sessionPct)
                        compactMetricBlock(title: "Weekly", percent: entry.snapshot.weeklyPct)
                        compactMetricBlock(title: "Fable", percent: fable)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        metricBlock(title: "Session", percent: entry.snapshot.sessionPct)
                        metricBlock(title: "Weekly", percent: entry.snapshot.weeklyPct)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
        }
    }

    @ViewBuilder
    private func metricBlock(title: String, percent: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.33))
            Text("\(Int(percent.rounded()))%")
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText(value: percent))
            MiniBar(
                percent: percent,
                trackColor: Color(.systemGray5),
                fillColor: .green
            )
            .frame(height: 5)
            .padding(.top, 2)
        }
    }

    private func compactMetricBlock(title: String, percent: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.4))
                Spacer()
                Text("\(Int(percent.rounded()))%")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .contentTransition(.numericText(value: percent))
            }
            MiniBar(percent: percent, trackColor: Color(.systemGray5), fillColor: .green)
                .frame(height: 5)
        }
    }
}

private struct CircularView: View {
    let entry: TokenistEntry

    var body: some View {
        if entry.needsSetup {
            Image(systemName: "person.crop.circle.badge.questionmark")
        } else {
            Gauge(value: min(1, max(0, entry.snapshot.sessionPct / 100))) {
                Text("Sess")
            } currentValueLabel: {
                Text("\(Int(entry.snapshot.sessionPct.rounded()))")
                    .font(.system(.headline, design: .rounded))
            }
            .gaugeStyle(.accessoryCircular)
        }
    }
}

private struct RectangularView: View {
    let entry: TokenistEntry

    var body: some View {
        if entry.needsSetup {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tokenist").font(.headline)
                Text("Open the app to sign in").font(.caption2)
            }
        } else {
            Group {
                if let fable = entry.snapshot.fableWeeklyPct {
                    VStack(alignment: .leading, spacing: 2) {
                        row(percent: entry.snapshot.sessionPct, label: "session", compact: true)
                        row(percent: entry.snapshot.weeklyPct, label: "weekly", compact: true)
                        row(percent: fable, label: "Fable", compact: true)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        row(percent: entry.snapshot.sessionPct, label: "session")
                        row(percent: entry.snapshot.weeklyPct, label: "weekly")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func row(percent: Double, label: String, compact: Bool = false) -> some View {
        HStack(spacing: 8) {
            MiniBar(percent: percent)
                .frame(width: compact ? 36 : 44, height: compact ? 5 : 6)
            Text("\(Int(percent.rounded()))% \(label)")
                .font((compact ? Font.caption : Font.callout).weight(.medium).monospacedDigit())
        }
    }
}

private struct MiniBar: View {
    let percent: Double
    var trackColor: Color = .primary.opacity(0.25)
    var fillColor: Color = .primary

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor)
                Capsule()
                    .fill(fillColor)
                    .frame(width: fillWidth(in: proxy.size))
            }
        }
    }

    private func fillWidth(in size: CGSize) -> CGFloat {
        let fraction = CGFloat(min(1, max(0, percent / 100)))
        guard fraction > 0 else { return 0 }
        // Keep the fill at least as wide as it is tall so the leading
        // edge stays horizontally rounded instead of flipping vertical.
        return max(size.height, size.width * fraction)
    }
}

#Preview(as: .accessoryCircular) {
    TokenistWidget()
} timeline: {
    TokenistEntry(
        date: .now,
        snapshot: UsageSnapshot(
            sessionPct: 42,
            sessionResetsAt: .now.addingTimeInterval(7000),
            weeklyPct: 23,
            weeklyResetsAt: .now.addingTimeInterval(86400 * 3),
            fableWeeklyPct: 31,
            fableWeeklyResetsAt: .now.addingTimeInterval(86400 * 3),
            opusWeeklyPct: nil,
            sonnetWeeklyPct: 10,
            extraSpending: nil,
            extraBudget: nil,
            extraCurrency: nil,
            extraEnabled: false,
            fetchedAt: .now
        ),
        needsSetup: false,
        errorMessage: nil
    )
}
