# Goodsky

A personal iOS + Apple Watch weather app that answers one question fast:
**do I need a jacket, a rain jacket, or nothing today?** It comes with attitude.

## What's here (Phase 0 + Phase 1)

| Piece | Where |
|---|---|
| **Jacket Call** logic (pure, unit-tested) | `GoodskyKit/Sources/GoodskyCore/JacketAdvisor.swift` |
| Next-hour precipitation summary ("Rain reaches you around 4:15, lasts about 40 minutes.") | `GoodskyKit/Sources/GoodskyCore/PrecipSummarizer.swift` |
| Templated snark lines (cursing included) | `GoodskyKit/Sources/GoodskyCore/SnarkLibrary.swift` |
| WeatherKit → core model mapping, location, widget fetch/cache | `GoodskyKit/Sources/GoodskyWeather/` |
| iPhone app: Jacket Call hero, current conditions, next hour, 48h hourly, 10-day, Settings, Apple Weather attribution | `App/iOS`, `App/Shared` |
| iPhone home + lock screen widgets, Watch complications / Smart Stack (one shared source) | `Widgets/` |
| Minimal watch app (hosts the complication, refreshes location) | `Watch/` |
| Xcode project spec (XcodeGen) | `project.yml` |
| Xcode Cloud hook | `ci_scripts/ci_post_clone.sh` |

### How the Jacket Call works

1. Pick the "out and about" window: 7am–7pm by default. During the day it runs from now until the
   window ends. Late in the evening it switches to the next 12 hours.
2. Look at every forecast hour in that window, using **feels-like** temperature, wind, and
   precipitation chance and amount.
3. Pick the verdict:
   - Any hour with ≥ 40% chance **and** ≥ 0.01″ expected → 🧥☔ **Rain jacket**. Rain beats
     jacket. Snow, sleet or mix on a cold day becomes ❄️ **Real coat** instead.
   - Otherwise, coldest feels-like < 45°F → ❄️ **Real coat**; < 62°F → 🧥 **Jacket**.
   - A windy day (≥ 20 mph) within 8° of the jacket threshold → 🧥 **Jacket**.
   - Otherwise → 😎 **No jacket**.
4. Add one reason line and one snark line. The snark line is picked deterministically per day and
   situation, so it doesn't change on every refresh.

All thresholds are in Settings and shared with the widgets through the App Group.

## Building

You need Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The `.xcodeproj` is
generated and not committed.

```bash
brew install xcodegen
```

```bash
xcodegen generate && open Goodsky.xcodeproj
```

Core logic tests run anywhere Swift runs (including Linux CI):

```bash
cd GoodskyKit && swift test
```

## One-time Apple setup

Team `84NHJE75L9`. Register these explicit App IDs. On **each** one, enable **WeatherKit** on
both the Capabilities tab and the App Services tab, and enable **App Groups** with
`group.com.hagoodit.goodsky`:

- `com.hagoodit.goodsky` (iPhone app)
- `com.hagoodit.goodsky.widgets` (iPhone widgets)
- `com.hagoodit.goodsky.watchkitapp` (Watch app)
- `com.hagoodit.goodsky.watchkitapp.widgets` (Watch complications)

WeatherKit can take around 30 minutes to start working after you enable it. Until then, calls fail
with an auth error.

## Xcode Cloud → TestFlight

Do this once on the Mac: generate the project, open it, then go to Integrate → Create Workflow.
Build `main`, Archive (iOS), and deliver to the internal TestFlight group **"Me"**.
`ci_scripts/ci_post_clone.sh` installs XcodeGen and regenerates the project on every cloud build.

## Roadmap

- **Phase 2:** minimal radar ("is rain coming at me?"), a fuller watch companion app, Foundation
  Models snark with the templated fallback, 👍/👎 threshold tuning, and a weather alerts banner.
- **Later:** homelab push service ("rain in 15 min"), saved locations, Live Activities.
