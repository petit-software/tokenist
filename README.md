# Tokenist

iOS + macOS app that shows your Claude.ai usage at a glance — 5-hour session %, weekly %, Opus/Sonnet weekly, extra spending. Reads from `https://claude.ai/api/organizations/{org_id}/usage` using your session cookie.

Includes a Lock Screen widget, Home Screen widget, and Mac menu-bar tray app.

> ⚠️ Personal use only. The data source is an undocumented endpoint that would fail App Store review. Build from source, run on your own devices.

## Setup

```sh
brew install xcodegen          # if you don't have it
git clone https://github.com/petit-software/tokenist.git
cd tokenist
xcodegen generate              # regenerates Tokenist.xcodeproj from project.yml
open Tokenist.xcodeproj
```

In `project.yml`, change `DEVELOPMENT_TEAM` and the bundle-ID prefix to your own. Then ⌘R in Xcode to run on simulator or device.

## How it works

Each app independently stores your `sessionKey` cookie in the local Keychain and calls `claude.ai/api/.../usage` directly. No backend, no server. The Mac app and the iOS app are independent viewers of the same Anthropic account.

Onboarding once per device: open claude.ai in a browser → DevTools → Application → Cookies → copy `sessionKey` value → paste into the app → pick your org.

## Project layout

```
Tokenist/
  project.yml                   XcodeGen spec (three targets)
  Tokenist/                     iOS app
    TokenistApp.swift           @main
    Models/ClaudeUsage.swift    Codable shape for /usage endpoint
    Services/
      KeychainStore.swift       local Keychain wrapper
      ClaudeAPIClient.swift     URLSession client for claude.ai
      SessionStore.swift        @Observable, gates onboarding vs main
      SharedDefaults.swift      App Group UserDefaults (org_id)
    Views/                      RootView, OnboardingView, UsageView
    Tokenist.entitlements
  TokenistWidget/               WidgetKit extension
    TokenistWidget.swift        Lock Screen + Home Screen widgets
    Info.plist
    TokenistWidget.entitlements
  TokenistMac/                  macOS menu-bar app
    TokenistMacApp.swift        MenuBarExtra
    MacDataStore.swift          background polling
    Views/                      MacRootView, MacOnboardingView, MacUsageView
```

## Verify the endpoint manually (for debugging the data shape)

```sh
export CLAUDE_COOKIE='paste-here'
curl -s --cookie "sessionKey=$CLAUDE_COOKIE" \
  -H "User-Agent: Mozilla/5.0" \
  https://claude.ai/api/organizations | jq
# pick a uuid, then:
export ORG_ID='uuid-from-above'
curl -s --cookie "sessionKey=$CLAUDE_COOKIE" \
  -H "User-Agent: Mozilla/5.0" \
  "https://claude.ai/api/organizations/$ORG_ID/usage" | jq
```

If the JSON shape changes (Anthropic-side update), adjust `Tokenist/Models/ClaudeUsage.swift`.

## Roadmap

### Done
- [x] iOS app — paste cookie → pick org → linear bars for each metric
- [x] Auto-refresh on appear + pull-to-refresh + manual refresh
- [x] Lock Screen widget (`accessoryCircular` + `accessoryRectangular`)
- [x] Home Screen widget (`systemSmall`)
- [x] Mac menu-bar app — independent fetcher, polls every 60 s

### Up next
- [ ] Threshold notifications — local notifications at 75 / 90 / 95%
- [ ] App icon + accent color
- [ ] Empty / error state polish

### Deferred (cost/value not worth it for personal use)
- [ ] iCloud Keychain sync — would require team-signing the Mac app (Xcode-only build loop) for ~30 s saved on cookie refresh
- [ ] Live Activity countdown (removed from plan)

## Constraints we know about
- `claude.ai/api/.../usage` is undocumented. Anthropic could change or remove it without notice.
- Session cookies expire periodically (every few weeks). Re-paste a fresh one when they do.
- Mac app uses ad-hoc signing for local development.
