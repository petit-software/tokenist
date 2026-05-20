import Foundation

// Shared UserDefaults suite. Both the main app and the widget extension
// read/write the org_id here so the widget can call the API without
// going back to the app.

enum SharedDefaults {
    static let suiteName = "group.com.bartbak.tokenist"
    private static let orgIdKey = "tokenist.orgId"

    private static var store: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static var orgId: String? {
        get { store.string(forKey: orgIdKey) }
        set { store.set(newValue, forKey: orgIdKey) }
    }
}
