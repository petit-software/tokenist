import SwiftUI

@main
struct TokenistMacApp: App {
    @State private var session: SessionStore
    @State private var dataStore: MacDataStore
    @State private var isMenuPresented = false

    init() {
        let s = SessionStore()
        _session = State(initialValue: s)
        _dataStore = State(initialValue: MacDataStore(credentialsProvider: { @MainActor in
            guard case .configured(let orgId) = s.phase,
                  let key = s.currentSessionKey() else { return nil }
            return (orgId: orgId, sessionKey: key)
        }))
    }

    var body: some Scene {
        MenuBarExtra {
            MacRootView()
                .environment(session)
                .environment(dataStore)
                .frame(width: 340)
                .onAppear { isMenuPresented = true }
                .onDisappear { isMenuPresented = false }
        } label: {
            MenuBarLabel(
                snapshot: dataStore.snapshot,
                isLoading: dataStore.isLoading,
                isMenuPresented: isMenuPresented
            )
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    let snapshot: UsageSnapshot
    let isLoading: Bool
    let isMenuPresented: Bool

    var body: some View {
        if snapshot.fetchedAt == .distantPast {
            MenuBarIcon(size: 24)
        } else {
            HStack(spacing: 4) {
                MenuBarProgress(percent: snapshot.sessionPct)
                    .frame(width: 42, height: 8)
                if isMenuPresented {
                    MenuBarIcon(size: 20)
                } else {
                    Text("\(Int(snapshot.sessionPct.rounded()))%")
                        .monospacedDigit()
                }
            }
        }
    }
}

private struct MenuBarIcon: View {
    let size: CGFloat

    var body: some View {
        Image("TokenistBarIcon")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
            .fixedSize()
            .clipped()
            .accessibilityLabel("Tokenist")
    }
}

private struct MenuBarProgress: View {
    let percent: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .stroke(.primary.opacity(0.4), lineWidth: 1)
                Capsule()
                    .fill(.primary)
                    .frame(width: proxy.size.width * CGFloat(min(1, max(0, percent / 100))))
            }
        }
    }
}
