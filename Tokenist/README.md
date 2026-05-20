# Tokenist

A small SwiftUI app that surfaces your Claude.ai usage at a glance — 5-hour session burn, weekly cap, per-model (Opus / Sonnet) weekly usage, and extra-usage spend if enabled.

## How it works

Tokenist talks to the same private endpoints that claude.ai itself uses:

- `GET https://claude.ai/api/organizations` — list organizations on the account
- `GET https://claude.ai/api/organizations/{org_id}/usage` — current usage windows

Authentication is your `sessionKey` cookie from a logged-in claude.ai browser session. The cookie is stored locally in the iOS/macOS Keychain; nothing is sent to any third-party server.

## Setup

1. Build and run the app in Xcode (`TokenistApp.swift`).
2. In a browser logged into claude.ai: **DevTools → Application → Cookies → `sessionKey`**. Copy the value.
3. Paste the cookie into the onboarding screen, validate, pick your organization, and save.
4. The main screen shows your current usage bars. Pull to refresh.

## Project layout

```
Models/      ClaudeUsage.swift           — response & snapshot models
Services/    ClaudeAPIClient.swift       — claude.ai API client
             KeychainStore.swift         — cookie storage
             SessionStore.swift          — observable session state
             SharedDefaults.swift        — shared user defaults
Views/       OnboardingView.swift        — cookie entry + org picker
             RootView.swift              — onboarded vs. configured router
             UsageView.swift             — usage bars + refresh
TokenistApp.swift                        — @main entry point
```

## Disclaimer

This app uses unofficial, undocumented claude.ai endpoints. They can change or break without warning. Tokenist is not affiliated with Anthropic.
