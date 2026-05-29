import Foundation

// Raw response shape from GET https://claude.ai/api/organizations/{org_id}/usage
// Verified 2026-05-20 against a real account.
//
// Many top-level fields can be null depending on the user's plan
// (seven_day_opus, seven_day_oauth_apps, seven_day_cowork, etc.).
// We ignore the ones we don't surface in the UI.

struct UsageResponse: Codable, Equatable, Sendable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let sevenDaySonnet: UsageWindow?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
    }
}

struct UsageWindow: Codable, Equatable, Sendable {
    let utilization: Double
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct ExtraUsage: Codable, Equatable, Sendable {
    let isEnabled: Bool
    let monthlyLimit: Double?     // cents, null when extra_usage is disabled
    let usedCredits: Double?      // cents, null when extra_usage is disabled
    let utilization: Double?      // fraction 0..1, or null
    let currency: String?         // null when extra_usage is disabled
    let disabledReason: String?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
        case currency
        case disabledReason = "disabled_reason"
    }
}

// Organizations list — GET https://claude.ai/api/organizations
struct Organization: Codable, Equatable, Identifiable, Sendable {
    let uuid: String
    let name: String
    var id: String { uuid }
}

// Snapshot consumed by the UI and persisted to the App Group for the widget.
struct UsageSnapshot: Codable, Equatable, Sendable {
    var sessionPct: Double
    var sessionResetsAt: Date?
    var weeklyPct: Double
    var weeklyResetsAt: Date?
    var opusWeeklyPct: Double?
    var sonnetWeeklyPct: Double?
    var extraSpending: Double?    // dollars
    var extraBudget: Double?      // dollars
    var extraCurrency: String?
    var extraEnabled: Bool
    var fetchedAt: Date

    static let empty = UsageSnapshot(
        sessionPct: 0,
        sessionResetsAt: nil,
        weeklyPct: 0,
        weeklyResetsAt: nil,
        opusWeeklyPct: nil,
        sonnetWeeklyPct: nil,
        extraSpending: nil,
        extraBudget: nil,
        extraCurrency: nil,
        extraEnabled: false,
        fetchedAt: .distantPast
    )

    init(from response: UsageResponse, fetchedAt: Date = Date()) {
        self.sessionPct = response.fiveHour?.utilization ?? 0
        self.sessionResetsAt = response.fiveHour?.resetsAt
        self.weeklyPct = response.sevenDay?.utilization ?? 0
        self.weeklyResetsAt = response.sevenDay?.resetsAt
        self.opusWeeklyPct = response.sevenDayOpus?.utilization
        self.sonnetWeeklyPct = response.sevenDaySonnet?.utilization

        if let extra = response.extraUsage {
            self.extraSpending = extra.usedCredits.map { $0 / 100 }
            self.extraBudget = extra.monthlyLimit.map { $0 / 100 }
            self.extraCurrency = extra.currency
            self.extraEnabled = extra.isEnabled
        } else {
            self.extraSpending = nil
            self.extraBudget = nil
            self.extraCurrency = nil
            self.extraEnabled = false
        }

        self.fetchedAt = fetchedAt
    }

    init(
        sessionPct: Double,
        sessionResetsAt: Date?,
        weeklyPct: Double,
        weeklyResetsAt: Date?,
        opusWeeklyPct: Double?,
        sonnetWeeklyPct: Double?,
        extraSpending: Double?,
        extraBudget: Double?,
        extraCurrency: String?,
        extraEnabled: Bool,
        fetchedAt: Date
    ) {
        self.sessionPct = sessionPct
        self.sessionResetsAt = sessionResetsAt
        self.weeklyPct = weeklyPct
        self.weeklyResetsAt = weeklyResetsAt
        self.opusWeeklyPct = opusWeeklyPct
        self.sonnetWeeklyPct = sonnetWeeklyPct
        self.extraSpending = extraSpending
        self.extraBudget = extraBudget
        self.extraCurrency = extraCurrency
        self.extraEnabled = extraEnabled
        self.fetchedAt = fetchedAt
    }
}
