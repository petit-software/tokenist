import Foundation
import UserNotifications
import OSLog

private let log = Logger(subsystem: "com.tokenist.Tokenist", category: "notif")

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    enum Metric: String, CaseIterable {
        case session, weekly, fable, opus, sonnet

        var title: String {
            switch self {
            case .session: "5-hour session"
            case .weekly:  "Weekly usage"
            case .fable:   "Fable weekly"
            case .opus:    "Opus weekly"
            case .sonnet:  "Sonnet weekly"
            }
        }
    }

    static let thresholds: [Int] = [75, 90, 95]

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "notif.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "notif.enabled") }
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            log.error("auth failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func evaluate(_ snapshot: UsageSnapshot) async {
        guard isEnabled else { return }

        check(.session, percent: snapshot.sessionPct, resetsAt: snapshot.sessionResetsAt)
        check(.weekly,  percent: snapshot.weeklyPct,  resetsAt: snapshot.weeklyResetsAt)
        if let pct = snapshot.fableWeeklyPct {
            check(.fable, percent: pct, resetsAt: snapshot.fableWeeklyResetsAt)
        }
        if let pct = snapshot.opusWeeklyPct {
            check(.opus,   percent: pct, resetsAt: snapshot.weeklyResetsAt)
        }
        if let pct = snapshot.sonnetWeeklyPct {
            check(.sonnet, percent: pct, resetsAt: snapshot.weeklyResetsAt)
        }
    }

    private func check(_ metric: Metric, percent: Double, resetsAt: Date?) {
        let stateKey = "notif.state.\(metric.rawValue)"
        var state = loadState(key: stateKey)

        // Reset tracking whenever the window itself resets
        if state.windowResetsAt != resetsAt {
            state = ThresholdState(windowResetsAt: resetsAt, maxFired: 0)
        }

        let rounded = Int(percent.rounded())
        let toFire = Self.thresholds.filter { $0 <= rounded && $0 > state.maxFired }
        guard let highest = toFire.max() else {
            saveState(state, key: stateKey)
            return
        }

        fire(metric: metric, threshold: highest, percent: percent)
        state.maxFired = highest
        saveState(state, key: stateKey)
    }

    private func fire(metric: Metric, threshold: Int, percent: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Tokenist"
        content.body = "\(metric.title) is at \(Int(percent.rounded()))%."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "tokenist.\(metric.rawValue).\(threshold).\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                log.error("add request failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        log.info("fired \(metric.rawValue) at \(threshold)% (actual \(Int(percent.rounded()))%)")
    }

    private func loadState(key: String) -> ThresholdState {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(ThresholdState.self, from: data) else {
            return ThresholdState(windowResetsAt: nil, maxFired: 0)
        }
        return decoded
    }

    private func saveState(_ state: ThresholdState, key: String) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private struct ThresholdState: Codable {
        var windowResetsAt: Date?
        var maxFired: Int
    }
}
