# Goodsky

A personal iOS + Apple Watch weather app that answers one question fast:
**do I need a jacket, a rain jacket, or nothing today?** It comes with attitude.

## What's here (Phases 0–2)

| Piece | Where |
|---|---|
| **Jacket Call** logic (pure, unit-tested) | `GoodskyKit/Sources/GoodskyCore/JacketAdvisor.swift` |
| Next-hour precipitation summary ("Rain reaches you around 4:15, lasts about 40 minutes.") | `GoodskyKit/Sources/GoodskyCore/PrecipSummarizer.swift` |
| Templated snark lines (cursing included) | `GoodskyKit/Sources/GoodskyCore/SnarkLibrary.swift` |
| WeatherKit → core model mapping, location, widget fetch/cache | `GoodskyKit/Sources/GoodskyWeather/` |
| iPhone app: Jacket Call hero, current conditions, next hour, 48h hourly, 10-day, Settings, Apple Weather attribution | `App/iOS`, `App/Shared` |
| iPhone home + lock screen widgets, Watch complications / Smart Stack (one shared source) | `Widgets/` |
| Watch companion app: Jacket Call + 👍/👎, next-hour chart, hourly, 10-day | `Watch/` |
| Minimal radar: plain-English next hour on top, past-hour loop, light/moderate/heavy colors | `App/iOS/Radar/`, `GoodskyCore/Radar.swift` |
| 👍/👎 "was this right?" threshold tuning (pure, unit-tested) | `GoodskyCore/ThresholdTuner.swift`, `App/Shared/FeedbackControls.swift` |
| Foundation Models snark with the template fallback | `App/Shared/SnarkWriter.swift`, `GoodskyCore/SnarkPrompt.swift` |
| Weather alerts banner (display only) | `GoodskyCore/Alerts.swift`, `App/iOS/AlertBannerView.swift` |
| Phone ↔ watch settings sync (WatchConnectivity, newest wins) | `App/Shared/SettingsSync.swift` |
| Xcode project spec (XcodeGen) | `project.yml` |
| Xcode Cloud hook | `ci_scripts/ci_post_clone.sh` |

### How the Jacket Call works

1. Pick the "out and about" window: 7am–7pm by default. During the day it runs from now until the
   window ends. Late in the evening it switches to the next 12 hours.
2. Look at every forecast hour in that window, using **Goodsky's feels-like** temperature, wind, and
   precipitation chance and amount. WeatherKit's feels-like is basically wind chill below 50°F and
   heat index above 80°F, and just the air temperature in between. So Goodsky builds its own
   (`GoodskyCore/FeltTemperature.swift`) from the air temperature, adjusting for: sun on you (by sun
   height and cloud cover, up to +8°), a clear sky after dark (−3°), wind in the 50–80° band
   (−0.5° per mph over 3), damp air (−2°), the temperature falling (−2°) or rising (+1°), and being
   out after dark in the evening (−2°). A sunny 62° morning comes out around 66°, and a clear,
   breezy 62° evening around 51°. The current-conditions card shows the same number.
   The Jacket Call card adds a "why" line for the coldest hour ("5 PM · Feels 10° colder than the air:
   clear sky, wind, damp air"), the watch shows it under the reason, and tapping either the line or
   "Feels 51° ⓘ" opens the full breakdown: air temperature, each adjustment, and the result.
3. Pick the verdict:
   - Any hour with ≥ 40% chance **and** ≥ 0.01″ expected → 🧥☔ **Rain jacket**. Rain beats
     jacket. Snow, sleet or mix on a cold day becomes ❄️ **Real coat** instead.
   - Otherwise, coldest feels-like < 45°F → ❄️ **Real coat**; < 62°F → 🧥 **Jacket**.
   - A windy day (≥ 20 mph) within 8° of the jacket threshold → 🧥 **Jacket**.
   - Otherwise → 😎 **No jacket**.
4. Work out **now vs later**. "Now" is the first 2 hours of the window, when you step out. Each
   hour gets its own verdict, and the call gets a timing:
   - **All day**: you need it now and later (cold at both ends counts, even with a warm midday).
   - **Later**: fine when you head out, needed from a set hour → "Jacket later" ("Fine without
     one now, but you'll want it by 5 PM.").
   - **For now**: needed now, then it warms up or dries out with at least 2 hours to spare →
     "Jacket for now" ("Wear it now; you can ditch it by 11 AM.").
   - **Step up**: one thing now, something heavier later ("Jacket now, rain jacket by 3 PM.").
   When now and later differ, the call is split into two phases (`JacketCall.now` / `.later`). The
   iPhone hero shows them side by side (**Now · 😎 No jacket · Feels 66°** → **From 5 PM · 🧥 Jacket ·
   Feels 52°**) with the action for the way out: "Bring a jacket for later.", "Wear a jacket out, then
   stash it.", or "Wear a jacket, and bring a rain jacket for later." The watch and the medium widget
   get a one-liner: "😎 Now · 🧥 5 PM". On a cold–warm–cold day (jacket at both ends, 2+ warm hours
   between) a third, midday phase appears: "🧥 7 AM · 😎 11 AM · 🧥 4 PM" and "Wear a jacket out, stash it
   midday, and keep it with you for later."
5. Add one reason line and one snark line. The snark line is picked deterministically per day and
   situation, so it doesn't change on every refresh.

All thresholds are in Settings and shared with the widgets through the App Group. The watch gets
them over WatchConnectivity, because App Groups don't cross devices.

### 👍/👎 tuning

Under the Jacket Call: "Was this right?" A 👎 asks what went wrong (cold, too warm, got rained on,
didn't need the rain jacket). Each answer moves the **one** threshold that would have changed the
call, by half the gap to the value that would have flipped it, at least 1° and at most 4°.
Rain answers move the rain-chance threshold 5 points. Wind-bumped days raise the windy threshold
instead. One vote per day, and Undo puts things back. History is in Settings.

### Radar

The sentence on top (from WeatherKit's minute forecast) is the answer. The map is backup: a loop
of the past hour in 5-minute frames from the **Iowa Environmental Mesonet** NEXRAD N0Q composite
(public domain, US only, no key). Each tile is decoded back to dBZ using IEM's exact color ramp,
then repainted as light / moderate / heavy using the same rain-rate bands as the next-hour summary
(Marshall-Palmer), with drizzle and clutter under 15 dBZ hidden.

RainViewer was ruled out. Since January 2026 its free tier caps zoom at 7 (too coarse for a metro
view) and dropped nowcast. IEM has no nowcast either, which is why the minute summary carries the
future.

### Snark

In the app, Apple's on-device model (Foundation Models, iOS 26 + Apple Intelligence) writes the
line, with one template line as a style example. `SnarkPrompt.accept` throws the answer out if it
refuses, gets wholesome ("stay safe"), rambles, or contradicts the verdict. Then the template line
stays. Widgets and the watch always use templates. There's a toggle in Settings.

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

- **Phase 2 (done in code, needs a device test):** minimal radar, watch companion app, Foundation
  Models snark with the templated fallback, 👍/👎 threshold tuning, weather alerts banner.
- **Later:** homelab push service ("rain in 15 min"), saved locations, Live Activities.
