<img width="512" height="512" alt="image" src="https://github.com/user-attachments/assets/9cc75aa8-922f-4e4a-9887-7f99b5152f8f" />

# Tokenist

<img width="6340" height="3736" alt="image" src="https://github.com/user-attachments/assets/7f4ea00d-5edb-4ec7-8fb0-588a941534c9" />


iOS + macOS app that shows your Claude.ai usage at a glance — 5-hour session %, weekly %, Opus/Sonnet weekly, extra spending. Includes a Lock Screen widget, Home Screen widget, and a Mac menu-bar tray app.

> ⚠️ Personal use only. The data source is an undocumented Claude.ai endpoint that would fail App Store review. Build from source, run on your own devices.

---

## What you'll need

- A Mac with **Xcode 26+**
- **XcodeGen** — install with `brew install xcodegen`
- An **Apple ID** signed into Xcode (free works; paid Developer account works too)
- A **claude.ai** account

---

## Setup, step by step

### 1. Clone and open the project

```sh
git clone https://github.com/petit-software/tokenist.git
cd tokenist
xcodegen generate
open Tokenist.xcodeproj
```

### 2. Set your signing team in Xcode

You need to do this **once** per target so Xcode signs the builds with your Apple ID.

In Xcode:

1. Click the blue **Tokenist** project at the top of the file navigator on the left
2. Select the **Tokenist** target → **Signing & Capabilities** tab
3. Change **Bundle Identifier** to something unique, e.g. `com.yourname.tokenist`
4. Pick your **Team** from the dropdown
5. Repeat for the **TokenistWidget** target. Use the same prefix with `.widget` at the end (e.g. `com.yourname.tokenist.widget`)
6. Repeat for the **TokenistMac** target if you'll use the Mac app. Use `.mac` at the end (e.g. `com.yourname.tokenist.mac`)

### 3. Get your Claude session cookie

This is the only auth Tokenist needs. You'll paste it into the app in step 4.

1. Open [claude.ai](https://claude.ai) in a desktop browser and sign in
2. Open Developer Tools:
   - **Chrome / Edge**: ⌥⌘I, or *View → Developer → Developer Tools*
   - **Safari**: enable the Develop menu in *Settings → Advanced*, then ⌥⌘I
   - **Firefox**: ⌥⌘I
3. Go to the **Application** tab (Chrome/Edge) or **Storage** (Safari/Firefox) → **Cookies** → `https://claude.ai`
4. Find the cookie named `sessionKey`
5. Click it, copy its **value** — a long string starting with `sk-ant-sid01-…`

> Keep this somewhere handy. It expires every few weeks and you'll re-paste it when it does.

### 4. Run on your iPhone

1. Plug your iPhone into your Mac with a USB cable
2. In Xcode's top toolbar, click the device dropdown (next to the play button) and pick your iPhone
3. Make sure the scheme says **Tokenist** (iOS app)
4. Press **⌘R**
5. The first time, iOS will ask you to trust the developer profile:
   *Settings → General → VPN & Device Management → tap your developer profile → Trust*
6. Open **Tokenist** on your iPhone
7. Paste the `sessionKey` value into the cookie field
8. Tap **Validate cookie** → pick your organization → **Save & Continue**

You're done. The app will show your usage and auto-refresh.

### 5. Add widgets to your iPhone (optional)

**Lock Screen widget**:
1. Lock the phone, then long-press the Lock Screen
2. Tap **Customize** → tap **Lock Screen**
3. Tap the area above or below the clock
4. Search **Tokenist** and add it

**Home Screen widget**:
1. Long-press any empty space on the Home Screen
2. Tap **+** in the top corner
3. Search **Tokenist** and add the small tile

### 6. Run the Mac menu-bar app (optional)

1. In Xcode, change the scheme (top toolbar) to **TokenistMac**
2. Pick **My Mac** as the device
3. Press **⌘R**
4. Tokenist appears in the menu bar (right side, near Wi-Fi / battery — small pill with a %)
5. Click it → paste your `sessionKey` → pick your org → **Save & Connect**

---

## When the cookie expires

You'll see "Session cookie is invalid or expired." in the app. Fix:

1. Get a fresh cookie following step 3 above
2. In the iPhone app: tap the key icon (top-left) → **Sign out** → paste the new cookie
3. In the Mac app: click the menu-bar icon → ⋯ menu → **Sign out** → paste the new cookie

Each device has its own copy of the cookie. They don't sync (by design — keeps it simple).

---

## How it works

Each app stores your `sessionKey` in the local Keychain and calls `claude.ai/api/organizations/{org_id}/usage` directly. No backend, no server, no Mac required (the Mac app is just another viewer). Widgets fetch on their own timeline, so the iPhone widgets work even when the app is closed.

## Verify the endpoint manually (debugging only)

If the app's data looks wrong, you can curl the endpoint directly:

```sh
export CLAUDE_COOKIE='paste-here'

# list orgs
curl -s --cookie "sessionKey=$CLAUDE_COOKIE" \
  -H "User-Agent: Mozilla/5.0" \
  https://claude.ai/api/organizations | jq

# pick a uuid, then:
export ORG_ID='uuid-from-above'
curl -s --cookie "sessionKey=$CLAUDE_COOKIE" \
  -H "User-Agent: Mozilla/5.0" \
  "https://claude.ai/api/organizations/$ORG_ID/usage" | jq
```

If the JSON shape has changed, update `Tokenist/Models/ClaudeUsage.swift` to match.

## Project layout

```
project.yml                    XcodeGen spec (source of truth — .xcodeproj is regenerated)
Tokenist/                      iOS app
TokenistWidget/                WidgetKit extension (Lock Screen + Home Screen)
TokenistMac/                   macOS menu-bar app
```

## Constraints to be aware of

- `claude.ai/api/.../usage` is undocumented — Anthropic could change or remove it any time
- Session cookies expire periodically (every few weeks)
- The Mac app uses ad-hoc signing for local development; it runs on your own Mac but isn't suitable for distribution to others
