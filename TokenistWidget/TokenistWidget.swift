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

    func getTimeline(in context: Context, completion: @escaping (Timeline<TokenistEntry>) -> Void) {
        let box = SendableBox(completion)
        Task {
            let entry = await fetchEntry()
            let nextRefresh = Date().addingTimeInterval(30 * 60)
            box.value(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    private func fetchEntry() async -> TokenistEntry {
        guard let key = KeychainStore.loadSessionKey(),
              let orgId = SharedDefaults.orgId,
              !orgId.isEmpty else {
            return TokenistEntry(date: Date(), snapshot: .empty, needsSetup: true, errorMessage: nil)
        }
        do {
            let client = ClaudeAPIClient(sessionKey: key)
            let response = try await client.fetchUsage(orgId: orgId)
            return TokenistEntry(
                date: Date(),
                snapshot: UsageSnapshot(from: response),
                needsSetup: false,
                errorMessage: nil
            )
        } catch {
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
            VStack(alignment: .leading, spacing: 10) {
                metricBlock(title: "Session", percent: entry.snapshot.sessionPct)
                metricBlock(title: "Weekly",  percent: entry.snapshot.weeklyPct)
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
            VStack(alignment: .leading, spacing: 6) {
                row(percent: entry.snapshot.sessionPct, label: "session")
                row(percent: entry.snapshot.weeklyPct,  label: "weekly")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func row(percent: Double, label: String) -> some View {
        HStack(spacing: 8) {
            MiniBar(percent: percent)
                .frame(width: 44, height: 6)
            Text("\(Int(percent.rounded()))% \(label)")
                .font(.callout.weight(.medium).monospacedDigit())
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
