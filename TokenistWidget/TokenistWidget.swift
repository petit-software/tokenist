import WidgetKit
import SwiftUI
import AppIntents

enum WidgetDisplayMode: String, AppEnum {
    // Preserve the original raw values so existing widget configurations migrate.
    case linear = "detailed"
    case circular = "percentagesOnly"

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Display")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .linear: "Linear",
        .circular: "Circular"
    ]
}

struct TokenistWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Tokenist Display"
    static let description = IntentDescription("Choose how usage appears in the widget.")

    @Parameter(title: "Display", default: .linear)
    var displayMode: WidgetDisplayMode

    @Parameter(title: "Show remaining usage", default: false)
    var showsRemainingUsage: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$displayMode), remaining usage \(\.$showsRemainingUsage)")
    }
}

@main
struct TokenistWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenistWidget()
    }
}

struct TokenistWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "TokenistWidget",
            intent: TokenistWidgetConfigurationIntent.self,
            provider: TokenistTimelineProvider()
        ) { entry in
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
    let displayMode: WidgetDisplayMode
    let showsRemainingUsage: Bool
}

struct TokenistTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TokenistEntry {
        TokenistEntry(
            date: Date(),
            snapshot: .empty,
            needsSetup: false,
            errorMessage: nil,
            displayMode: .linear,
            showsRemainingUsage: false
        )
    }

    func snapshot(
        for configuration: TokenistWidgetConfigurationIntent,
        in context: Context
    ) async -> TokenistEntry {
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
        return TokenistEntry(
            date: Date(),
            snapshot: sample,
            needsSetup: false,
            errorMessage: nil,
            displayMode: configuration.displayMode,
            showsRemainingUsage: configuration.showsRemainingUsage
        )
    }

    // How long the widget trusts a cache written by the main app before doing
    // its own network fetch. The app refreshes every 60s while foregrounded
    // and calls WidgetCenter.reloadAllTimelines after each success, so anything
    // newer than this window is almost certainly the same data the user just saw.
    private static let freshCacheWindow: TimeInterval = 5 * 60

    // Refresh policy budget — iOS treats this as a hint; accessory widgets get a
    // tighter budget than home-screen ones, so 15 minutes is the floor worth asking for.
    private static let timelineRefreshInterval: TimeInterval = 15 * 60

    func timeline(
        for configuration: TokenistWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<TokenistEntry> {
        let entry = await loadEntry(
            displayMode: configuration.displayMode,
            showsRemainingUsage: configuration.showsRemainingUsage
        )
        let nextRefresh = Date().addingTimeInterval(Self.timelineRefreshInterval)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func loadEntry(
        displayMode: WidgetDisplayMode,
        showsRemainingUsage: Bool
    ) async -> TokenistEntry {
        guard KeychainStore.loadSessionKey() != nil,
              let orgId = SharedDefaults.orgId,
              !orgId.isEmpty else {
            return TokenistEntry(
                date: Date(),
                snapshot: .empty,
                needsSetup: true,
                errorMessage: nil,
                displayMode: displayMode,
                showsRemainingUsage: showsRemainingUsage
            )
        }

        let cached = SharedSnapshotStore.load()

        // Cache-first: if the main app pushed something recent, render instantly
        // without burning the widget extension's limited execution time on a network call.
        if let cached, -cached.fetchedAt.timeIntervalSinceNow < Self.freshCacheWindow {
            return TokenistEntry(
                date: Date(),
                snapshot: cached,
                needsSetup: false,
                errorMessage: nil,
                displayMode: displayMode,
                showsRemainingUsage: showsRemainingUsage
            )
        }

        // Stale or missing cache: try the network, falling back to the stale cache on failure.
        guard let key = KeychainStore.loadSessionKey() else {
            return TokenistEntry(
                date: Date(),
                snapshot: .empty,
                needsSetup: true,
                errorMessage: nil,
                displayMode: displayMode,
                showsRemainingUsage: showsRemainingUsage
            )
        }
        do {
            let client = ClaudeAPIClient(sessionKey: key)
            let response = try await client.fetchUsage(orgId: orgId)
            let fresh = UsageSnapshot(from: response)
            SharedSnapshotStore.save(fresh)
            return TokenistEntry(
                date: Date(),
                snapshot: fresh,
                needsSetup: false,
                errorMessage: nil,
                displayMode: displayMode,
                showsRemainingUsage: showsRemainingUsage
            )
        } catch {
            if let cached {
                return TokenistEntry(
                    date: Date(),
                    snapshot: cached,
                    needsSetup: false,
                    errorMessage: nil,
                    displayMode: displayMode,
                    showsRemainingUsage: showsRemainingUsage
                )
            }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return TokenistEntry(
                date: Date(),
                snapshot: .empty,
                needsSetup: false,
                errorMessage: message,
                displayMode: displayMode,
                showsRemainingUsage: showsRemainingUsage
            )
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

private func widgetProgressTint(_ percent: Double) -> Color {
    switch percent {
    case ..<50: .green
    case ..<75: .yellow
    case ..<90: .orange
    default: .red
    }
}

private func displayedWidgetPercent(_ usedPercent: Double, showsRemaining: Bool) -> Double {
    guard showsRemaining else { return usedPercent }
    return min(100, max(0, 100 - usedPercent))
}

private func widgetMetricTitle(_ title: String, showsRemaining: Bool) -> String {
    guard showsRemaining else { return title }
    return title == "All models" ? "All left" : "\(title) left"
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
        } else if entry.displayMode == .circular {
            VStack(alignment: .leading, spacing: 0) {
                circularRow(
                    title: "Session",
                    percent: entry.snapshot.sessionPct
                )
                if let fable = entry.snapshot.fableWeeklyPct {
                    circularRow(title: "Fable", percent: fable)
                }
                circularRow(title: "All models", percent: entry.snapshot.weeklyPct)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
        } else {
            Group {
                if let fable = entry.snapshot.fableWeeklyPct {
                    VStack(alignment: .leading, spacing: 0) {
                        compactMetricBlock(title: "Session", percent: entry.snapshot.sessionPct)
                            .frame(maxHeight: .infinity)
                        compactMetricBlock(title: "Weekly", percent: entry.snapshot.weeklyPct)
                            .frame(maxHeight: .infinity)
                        compactMetricBlock(title: "Fable", percent: fable)
                            .frame(maxHeight: .infinity)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        metricBlock(title: "Session", percent: entry.snapshot.sessionPct)
                            .frame(maxHeight: .infinity)
                        metricBlock(title: "Weekly", percent: entry.snapshot.weeklyPct)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func circularRow(
        title: String,
        percent: Double
    ) -> some View {
        let displayedPercent = displayedWidgetPercent(
            percent,
            showsRemaining: entry.showsRemainingUsage
        )
        let displayedTitle = widgetMetricTitle(
            title,
            showsRemaining: entry.showsRemainingUsage
        )
        let progress = min(1, max(0, displayedPercent / 100))

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(displayedTitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("\(Int(displayedPercent.rounded()))%")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: displayedPercent))
            }

            Spacer(minLength: 4)

            ZStack {
                if progress <= 0 {
                    Circle()
                        .stroke(Color(.systemGray5), lineWidth: 6)
                        .frame(width: 21, height: 21)
                } else if progress < 1 {
                    // The path gap must account for both 6 pt rounded caps;
                    // a smaller angular gap is hidden by their extensions.
                    let gap: Double = 0.13
                    let unusedStart = min(1, progress + gap)
                    let unusedEnd = max(unusedStart, 1 - gap)

                    if unusedStart < unusedEnd {
                        Circle()
                            .trim(from: unusedStart, to: unusedEnd)
                            .stroke(
                                Color(.systemGray5),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 21, height: 21)
                    }
                }

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        widgetProgressTint(percent),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 21, height: 21)

            }
            .frame(width: 30, height: 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(displayedTitle)
        .accessibilityValue("\(Int(displayedPercent.rounded())) percent")
    }

    @ViewBuilder
    private func metricBlock(title: String, percent: Double) -> some View {
        let displayedPercent = displayedWidgetPercent(
            percent,
            showsRemaining: entry.showsRemainingUsage
        )

        VStack(alignment: .leading, spacing: 2) {
            Text(widgetMetricTitle(title, showsRemaining: entry.showsRemainingUsage))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.33))
            Text("\(Int(displayedPercent.rounded()))%")
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(.numericText(value: displayedPercent))
            MiniBar(
                percent: displayedPercent,
                trackColor: Color(.systemGray5),
                fillColor: widgetProgressTint(percent)
            )
            .frame(height: 9)
            .padding(.top, 2)
        }
    }

    private func compactMetricBlock(title: String, percent: Double) -> some View {
        let displayedPercent = displayedWidgetPercent(
            percent,
            showsRemaining: entry.showsRemainingUsage
        )

        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(widgetMetricTitle(title, showsRemaining: entry.showsRemainingUsage))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.4))
                Spacer()
                Text("\(Int(displayedPercent.rounded()))%")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
                    .contentTransition(.numericText(value: displayedPercent))
            }
            MiniBar(
                percent: displayedPercent,
                trackColor: Color(.systemGray5),
                fillColor: widgetProgressTint(percent)
            )
                .frame(height: 9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CircularView: View {
    let entry: TokenistEntry

    var body: some View {
        if entry.needsSetup {
            Image(systemName: "person.crop.circle.badge.questionmark")
        } else {
            let displayedPercent = displayedWidgetPercent(
                entry.snapshot.sessionPct,
                showsRemaining: entry.showsRemainingUsage
            )

            Gauge(value: min(1, max(0, displayedPercent / 100))) {
                Text(entry.showsRemainingUsage ? "Left" : "Sess")
            } currentValueLabel: {
                Text("\(Int(displayedPercent.rounded()))")
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
        let displayedPercent = displayedWidgetPercent(
            percent,
            showsRemaining: entry.showsRemainingUsage
        )
        let displayedLabel = widgetMetricTitle(
            label,
            showsRemaining: entry.showsRemainingUsage
        )

        return HStack(spacing: 8) {
            MiniBar(percent: displayedPercent, fillColor: widgetProgressTint(percent))
                .frame(width: compact ? 36 : 44, height: compact ? 5 : 6)
            Text("\(Int(displayedPercent.rounded()))% \(displayedLabel)")
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
            let coloredWidth = fillWidth(in: proxy.size)
            let gap: CGFloat = 4
            let unusedStart = min(proxy.size.width, coloredWidth + gap)
            let unusedWidth = max(0, proxy.size.width - unusedStart)
            let outerRadius = proxy.size.height / 2
            let gapRadius = min(2, outerRadius)

            ZStack(alignment: .leading) {
                if percent <= 0 {
                    Capsule().fill(trackColor)
                } else {
                    if percent < 100, unusedWidth > 0 {
                        UnevenRoundedRectangle(
                            cornerRadii: .init(
                                topLeading: gapRadius,
                                bottomLeading: gapRadius,
                                bottomTrailing: outerRadius,
                                topTrailing: outerRadius
                            ),
                            style: .continuous
                        )
                            .fill(trackColor)
                            .frame(width: unusedWidth)
                            .offset(x: unusedStart)
                    }

                    if percent >= 100 {
                        Capsule()
                            .fill(fillColor)
                            .frame(width: coloredWidth)
                    } else {
                        UnevenRoundedRectangle(
                            cornerRadii: .init(
                                topLeading: outerRadius,
                                bottomLeading: outerRadius,
                                bottomTrailing: gapRadius,
                                topTrailing: gapRadius
                            ),
                            style: .continuous
                        )
                        .fill(fillColor)
                        .frame(width: coloredWidth)
                    }
                }

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

private extension TokenistEntry {
    static func preview(
        displayMode: WidgetDisplayMode,
        percent: Double? = nil
    ) -> TokenistEntry {
        TokenistEntry(
            date: .now,
            snapshot: UsageSnapshot(
                sessionPct: percent ?? 54,
                sessionResetsAt: .now.addingTimeInterval(7000),
                weeklyPct: percent ?? 15,
                weeklyResetsAt: .now.addingTimeInterval(86400 * 3),
                fableWeeklyPct: percent ?? 19,
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
            errorMessage: nil,
            displayMode: displayMode,
            showsRemainingUsage: false
        )
    }
}

#Preview("Home Screen — Linear", as: .systemSmall) {
    TokenistWidget()
} timeline: {
    TokenistEntry.preview(displayMode: .linear)
}

#Preview("Home Screen — Circular", as: .systemSmall) {
    TokenistWidget()
} timeline: {
    TokenistEntry.preview(displayMode: .circular)
}

#Preview("Circular — 0%", as: .systemSmall) {
    TokenistWidget()
} timeline: {
    TokenistEntry.preview(displayMode: .circular, percent: 0)
}

#Preview("Circular — 50%", as: .systemSmall) {
    TokenistWidget()
} timeline: {
    TokenistEntry.preview(displayMode: .circular, percent: 50)
}

#Preview("Circular — 100%", as: .systemSmall) {
    TokenistWidget()
} timeline: {
    TokenistEntry.preview(displayMode: .circular, percent: 100)
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
        errorMessage: nil,
        displayMode: .linear,
        showsRemainingUsage: false
    )
}
