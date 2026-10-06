# Apple Watch Heart-Rate Threshold Alert App

## Architecture & Agent Build Guide

Personal-use iPhone + Apple Watch application: heart-rate monitoring, threshold alerts and long-session recording
Swift / SwiftUI / HealthKit / WatchConnectivity (watch) · React Native / Expo / TypeScript (iPhone companion)

> **Primary objective (v1.2):** Run a user-started heart-rate monitoring session on Apple Watch for up to 10 hours, record every heart-rate reading the watch provides, compare each reading locally against a user-set threshold, and give haptic warnings before and at the threshold. The iPhone app receives finished recordings and shows history and reports. It is not needed while a session is running.

> **Product in one line:** Like the Workout app, but for heart rate only. Start a session, get warned before you reach your number, and see the whole session as a chart afterwards.

Version 1.2 | October 2026

> **How this document is used.** This guide defines *what* to build and the rules it must obey. `docs/IMPLEMENTATION_PLAN.md` defines *in what order*, phase by phase. If they conflict, this guide wins; raise the conflict rather than working around it. Changes are marked *(v1.1)* or *(v1.2)* and listed in Appendix A.

---

## 1. Build Brief

Build a small, reliable personal wellness app consisting of a watchOS app and a companion iOS app. The watch is the source of truth for live heart-rate evaluation **and for the session recording**, so alerts and data capture never depend on the phone being nearby, unlocked, or connected.

| Decision | Required choice |
|---|---|
| UI framework | SwiftUI on watchOS; React Native (Expo, TypeScript) for the iPhone companion app *(v1.1)* |
| Live HR source | HealthKit on Apple Watch, **heart rate only** *(v1.2)* |
| Background model | Active HKWorkoutSession + HKLiveWorkoutBuilder, activity type `.other`, location `.indoor` (no GPS) *(v1.2)* |
| Session length *(v1.2)* | Designed for up to 10 hours; the practical limit is battery (Section 7.1) |
| Recording *(v1.2)* | Every HR sample stored on the watch with its timestamp, append-only, flushed to disk at least every 60 s |
| Threshold evaluation | On-device on Apple Watch, on every fresh HR update |
| Phone/watch communication | WatchConnectivity. **MVP:** finished recordings go watch → phone with `transferFile`. **Later phase:** settings phone → watch with `updateApplicationContext`. On the phone, WatchConnectivity is reached only through a small native module *(v1.1, v1.2)* |
| Settings (MVP) *(v1.2)* | Set on the watch (Digital Crown on the start screen). Phone-side settings are a later phase |
| Persistence | Watch: UserDefaults for settings; session files in the app container. Phone: SQLite for session index + summaries; recording files on disk *(v1.1, v1.2)* |
| Networking | None. The watch never uses the network *(v1.1)* |
| Accounts/cloud | None for MVP. Optional Supabase backup is a post-MVP, phone-only phase *(v1.1)* |
| Alert method | Watch haptics |
| Apple Health *(v1.2)* | Saving the session to Apple Health as a workout is an option, **off by default**. The app's own recording is the data of record |
| Distribution | Personal development install / TestFlight if desired |

> **Important platform constraint:** Do not design this as an always-on arbitrary background process. For reliable frequent heart-rate updates and background haptics, the monitoring mode must be a user-started workout-style HealthKit session. Apple documents that an active workout session can continue receiving HealthKit/sensor data and issue haptic alerts while backgrounded. *(v1.2)* There is no supported way for an iPhone app to wake on a timer and take a watch reading, so periodic phone-driven sampling is not an option.

### 1.1 Companion App Product Description (React Native) *(v1.1, revised v1.2)*

**What it is.** The phone-side home for your sessions: every recording the watch finishes appears here as a history entry with a full report. It is built in React Native with Expo and TypeScript, so the same codebase can later ship on Android alongside Wear OS watches.

**What it does (MVP).**

- **Receive:** finished recordings arrive from the watch automatically, even if the phone app was closed.
- **History:** a list of sessions (date, duration, average/max BPM, alert count).
- **Report:** a chart of the whole session with the warning and target lines drawn on it. An interval picker (Raw / 1 min / 5 min / 15 min) controls how readings are grouped; each grouped point shows the average with a min–max band. A stats panel shows duration, average, min, max, time above warning, time above target, number of alerts, and gaps. Gaps in data are shown as breaks, never filled in.
- **Export:** share the recording as CSV (raw or at the selected interval).
- **Disclose:** a short, persistent disclaimer that this is a personal wellness tool, not diagnosis or emergency monitoring.

**Later phases.** Set the target on the phone and push it to the watch; presets; sync status; optional sign-in and Supabase backup.

**What it deliberately does not do.**

- It does **not** read live heart rate, evaluate thresholds, or trigger alerts. That loop runs entirely on the watch.
- It does **not** need to be open, nearby, or connected while a session runs.
- It does **not** change recorded samples. It only groups them for display and export.

**How it talks to the watch.** The React Native app calls a small native module (Swift on iOS) that owns the phone's `WCSession`. JavaScript sees a typed `WatchBridge` interface (for example `getStatus()`, `importPendingRecordings()`, `onRecordingReceived()`), never WatchConnectivity directly. Future Wear OS or Garmin adapters implement the same interface.

**Who it is for.** A single user managing their own device. No social, subscription, or analytics features.

---

## 2. MVP Scope

### Must have *(v1.2: rewritten)*

**Watch**

- Start screen showing the alert target (e.g. "Alert at 150 BPM, warn at 135"); target adjustable with the Digital Crown; warning level default 90% of target.
- Start, Pause, Resume, End controls (Workout-app style: swipe right from the live screen for controls).
- Live screen: current BPM dominant, elapsed time, zone label/colour, target BPM, battery %.
- Record **every** heart-rate sample with its timestamp, for sessions up to 10 hours.
- Flush the recording to disk at least every 60 s; recover and continue the same recording after an app crash or relaunch.
- Warning haptic at the warning zone; stronger, distinct haptic at the target; cooldown and hysteresis.
- Stale-sample handling for alerts; gap marking for the recording.
- Battery guard: show estimated time remaining; at 10% battery, save and end the session cleanly.
- Low-power display behaviour when the wrist is down.
- End summary on the watch: duration, average/min/max BPM, time above target, alert count.
- "Save to Apple Health" setting, default off.

**iPhone**

- Receive finished recordings automatically (queued transfer) and store them.
- History list and per-session report: chart, interval picker, stats, CSV export.
- Permission/error states (Health permission denied, watch app not installed, no sessions yet).

### Explicitly out of scope for v1

- Medical diagnosis, arrhythmia detection, or emergency-service calling.
- Cloud backend, login, accounts, analytics, subscriptions, social features. *(Supabase is a later phase.)*
- Continuous 24/7 monitoring without a user-started session.
- Metrics other than heart rate (GPS, distance, calories display, HRV, SpO2). *(v1.2)*
- Heart-rate zones/presets beyond one target + warning level. *(v1.2)*
- Phone-side settings and a live phone view during a session. *(v1.2: later phase)*
- Importing data from the Workout app, Apple Health history, or Strava. *(v1.2)*
- Custom ML model; Apple Health clinical interpretation.
- Android / Wear OS / Garmin apps. *(v1.1: later phases; v1 code must not block them.)*

---

## 3. User Experience *(v1.2: rewritten)*

### Apple Watch flow

1. Open the watch app. The start screen shows "Alert at 150 BPM · warn at 135".
2. Turn the Digital Crown to change the target if needed (saved on the watch).
3. Tap **Start**. First time only: grant Health permission.
4. Live screen shows BPM, elapsed time, zone and battery.
5. Haptics fire as the warning and target are reached, even with the screen off or the app in the background.
6. Swipe right for **Pause / Resume / End**.
7. Tap **End** → summary screen → **Done**. The recording is queued to the iPhone automatically.

### iPhone flow

1. Open the app. Nothing to configure for the MVP.
2. Sessions appear in **History** as the watch sends them.
3. Tap a session to open its **Report**.
4. Change the interval (Raw / 1 / 5 / 15 min) to zoom the level of detail.
5. Tap **Export** to share a CSV.

---

## 4. System Architecture *(v1.2: updated)*

```
┌──────────────────────────────────┐   WatchConnectivity   ┌─────────────────────────────┐
│ iPhone App (React Native/Expo)   │   transferFile        │ Apple Watch App (SwiftUI)   │
│                                  │◀──────────────────────│                             │
│ HistoryScreen         (TS)       │   recordings          │ StartView / LiveView        │
│ ReportScreen          (TS)       │                       │ ControlsView / SummaryView  │
│ report/aggregate      (TS)       │                       │ HeartRateMonitor            │
│ sessionRepository  (TS, SQLite)  │──────────────────────▶│ ThresholdEngine             │
│ SettingsScreen  (TS, later)      │   settings (later)    │ HapticAlertService          │
│ WatchBridge interface (TS)       │                       │ SessionRecorder             │
│  └─ AppleWatchBridge             │                       │ BatteryGuard                │
│     (Swift module, WCSession)    │                       │ RecordingTransfer           │
└──────────────────────────────────┘                       │ WatchSettingsStore          │
                                                           └──────────────┬──────────────┘
                                                                          │
                                                                          ▼
                                                              HealthKit / Apple sensors
                                                              HKWorkoutSession
                                                              HKLiveWorkoutBuilder
```

> **Design rule:** The watch performs the real-time threshold decision locally. WatchConnectivity is for synchronization, not for the critical alert loop. A temporary phone disconnect must not prevent an alert.

> **Design rule (v1.1):** The React Native layer never contains alert or threshold-decision logic. Any future watch platform (Wear OS, Garmin) runs its own local alert loop in the same way.

> **Design rule (v1.2):** The watch's recording is the data of record. It is written on the watch during the session and sent whole at the end. The phone never edits samples; it only groups them for display and export. Nothing is sent per sample.

---

## 5. Recommended Project Structure *(v1.1, updated v1.2)*

```
HeartThreshold/
├── docs/
│   ├── ARCHITECTURE.md              # this guide
│   ├── IMPLEMENTATION_PLAN.md       # phase order + checkpoints
│   └── TEST_LOG.md                  # on-device test results
├── contracts/                       # platform-neutral source of truth
│   ├── heart-rate-settings.schema.json
│   ├── session-recording.schema.json     # header, samples, events, summary
│   ├── threshold-test-vectors.json       # every ThresholdEngine port must pass
│   └── aggregation-test-vectors.json     # bucket avg/min/max, gaps, pauses
├── apps/
│   └── mobile/                      # Expo React Native app (iOS now, Android later)
│       ├── app.config.ts
│       ├── app/                     # screens (expo-router)
│       │   ├── index.tsx            # HistoryScreen
│       │   ├── session/[id].tsx     # ReportScreen
│       │   └── settings.tsx         # later phase
│       ├── src/
│       │   ├── domain/              # TS types mirroring contracts/, validation
│       │   ├── report/              # aggregate.ts, downsample.ts, csv.ts
│       │   ├── storage/             # sessionRepository (SQLite), recordingFiles
│       │   └── watch/
│       │       ├── WatchBridge.ts   # platform-neutral interface
│       │       ├── AppleWatchBridge.ts
│       │       └── MockWatchBridge.ts
│       ├── modules/
│       │   └── watch-bridge/        # local Expo native module
│       │       └── ios/WatchBridgeModule.swift   # owns phone-side WCSession + inbox
│       └── targets/
│           └── watch/               # watchOS app (SwiftUI), via @bacons/apple-targets
│               ├── expo-target.config.js
│               ├── HeartThresholdWatchApp.swift  # incl. workout recovery hook
│               ├── Models/
│               │   ├── HeartRateSettings.swift
│               │   ├── HeartRateZone.swift
│               │   ├── HeartRateSample.swift
│               │   ├── SessionEvent.swift
│               │   └── MonitoringSummary.swift
│               ├── Constants/
│               │   └── AppConstants.swift
│               ├── Views/
│               │   ├── StartView.swift
│               │   ├── LiveView.swift          # (was MonitoringView)
│               │   ├── ControlsView.swift
│               │   └── SummaryView.swift
│               ├── Health/
│               │   └── HeartRateMonitor.swift
│               ├── Domain/
│               │   └── (ThresholdEngine + SummaryCalculator from the Swift package)
│               ├── Recording/
│               │   ├── SessionRecorder.swift
│               │   └── RecordingStore.swift     # files, cleanup, pending transfers
│               ├── Services/
│               │   ├── HapticAlertService.swift
│               │   ├── BatteryGuard.swift
│               │   ├── RecordingTransfer.swift  # transferFile + re-queue
│               │   └── WatchSyncReceiver.swift  # later phase (settings from phone)
│               └── Storage/
│                   └── WatchSettingsStore.swift
├── packages/
│   └── threshold-engine-swift/      # Swift package: ThresholdEngine, SummaryCalculator + tests
└── supabase/                        # post-MVP: migrations, RLS, storage policies
```

Reserved for later phases (do not create until that phase): `apps/wear-os/` (Kotlin), `apps/garmin/` (Monkey C).

Notes:

- Watch source lives in `apps/mobile/targets/watch/`, outside the generated `ios/` folder, so `expo prebuild --clean` never deletes it.
- `contracts/` is the cross-platform agreement. Swift, TypeScript, and any later Kotlin or Monkey C code must match its field names and pass its test vectors.

---

## 6. Data Models *(v1.2: extended)*

```swift
struct HeartRateSettings: Codable, Equatable {
    var targetBPM: Double              // e.g. 150
    var warningFraction: Double        // e.g. 0.90
    var warningCooldown: TimeInterval  // e.g. 60 s
    var thresholdCooldown: TimeInterval// e.g. 30 s
    var hysteresisBPM: Double          // e.g. 5 BPM
    var staleTimeout: TimeInterval     // e.g. 10 s  (alerts/display)
    var batteryGuardLevel: Double      // e.g. 0.10  (10 %)
    var saveToHealth: Bool             // default false
    var warningBPM: Double { targetBPM * warningFraction }
}

enum HeartRateZone: String, Codable { case normal, warning, threshold, stale }

struct HeartRateSample: Codable {
    let offset: TimeInterval   // seconds since startedAt (wall clock, includes pauses)
    let bpm: Double
}

enum SessionEventKind: String, Codable {
    case warning, threshold, staleStart, staleEnd,
         paused, resumed, recovered, batteryGuard, settingsChanged
}

struct SessionEvent: Codable {
    let offset: TimeInterval
    let kind: SessionEventKind
}

enum EndReason: String, Codable { case user, batteryGuard, interrupted, error }

struct MonitoringSummary: Codable, Identifiable {
    let id: UUID                       // generated on the watch at Start
    let startedAt: Date
    let endedAt: Date
    let activeSeconds: TimeInterval    // excludes paused time
    let sampleCount: Int
    let avgBPM: Double
    let minBPM: Double
    let maxBPM: Double
    let warningEvents: Int
    let thresholdEvents: Int
    let secondsAboveWarning: TimeInterval
    let secondsAboveTarget: TimeInterval
    let gapSeconds: TimeInterval
    let endReason: EndReason
}

struct SessionRecording: Codable {     // the file sent to the phone
    let schemaVersion: Int             // 1
    let id: UUID
    let sourcePlatform: String         // "watchos"
    let deviceModel: String
    let watchAppVersion: String
    let startedAt: Date
    let settings: HeartRateSettings    // snapshot at start (+ settingsChanged events)
    let samples: [HeartRateSample]
    let events: [SessionEvent]
    let summary: MonitoringSummary
}
```

The React Native app holds TypeScript mirrors in `apps/mobile/src/domain/`. The canonical definitions are `contracts/*.schema.json`. `id` is generated on the watch and reused as the primary key everywhere (phone SQLite, Supabase), so imports and uploads are idempotent. Time-in-zone values are computed by `SummaryCalculator` from the samples, holding each sample's value until the next sample, capped at the gap threshold.

---

## 7. Apple Watch Heart-Rate Pipeline

Use the watchOS HealthKit workout architecture rather than periodically querying the Health store. Apple recommends HKWorkoutSession with HKLiveWorkoutBuilder for live workout data. During an active workout session, watchOS allows the app to continue receiving HealthKit/sensor data in the background and to issue haptic alerts.

### HealthKit setup

- Enable HealthKit capability for the watchOS target.
- Enable Background Modes → Workout processing for the watchOS target.
- Add NSHealthShareUsageDescription (heart rate is read to provide user-configured wellness alerts and session recordings) and NSHealthUpdateUsageDescription (only needed for the optional save-to-Health setting and the workout session itself).
- Request **read**: `heartRate`. Request **share**: `workoutType()` (needed to run the live workout builder, even when the workout is later discarded). Request nothing else. *(v1.2)*
- Create HKWorkoutConfiguration with `activityType = .other` and `locationType = .indoor`. Indoor means no GPS, which is the biggest battery saving for long sessions. *(v1.2)*
- Create HKWorkoutSession and its associated HKLiveWorkoutBuilder / HKLiveWorkoutDataSource.
- Start the activity in the foreground from explicit user action.
- Receive updated statistics through the live builder delegate and extract the newest heart-rate value in count/min.
- *(v1.1)* With Expo, declare capabilities, entitlements, and Info.plist keys in `targets/watch/expo-target.config.js` / app config, not by hand-editing the generated `ios/` project.

### Reading samples *(v1.2)*

- In `workoutBuilder(_:didCollectDataOf:)`, for the heart-rate type read `statistics(for:)?.mostRecentQuantity()` and `mostRecentQuantityDateInterval()`.
- Use the end of that date interval as the sample timestamp. Skip it if it is not newer than the last recorded sample (the delegate can fire without a new reading).
- Pass each new sample to ThresholdEngine (alerts) and SessionRecorder (recording), in that order.

### Ending a session *(v1.2)*

- `saveToHealth == true`: `endCollection` → `finishWorkout` → `session.end()`.
- `saveToHealth == false` (default): `discardWorkout()` → `session.end()`. The app's recording is unaffected.

### Crash and relaunch recovery *(v1.2)*

- Persist `activeSessionId` in UserDefaults at Start; clear it after the recording is finalized.
- Implement the app delegate's `handleActiveWorkoutRecovery()` and call `HKHealthStore.recoverActiveWorkoutSession`. Re-attach the builder delegate, reopen the recording for `activeSessionId`, append a `recovered` event, and continue.
- If the app launches with an `activeSessionId` but no workout to recover, finalize that recording from what is on disk with `endReason = .interrupted` and queue it for transfer.

### HeartRateMonitor responsibilities

- Request authorization.
- Start, pause, resume, and stop the workout session; handle recovery.
- Publish currentBPM, lastSampleDate, authorizationState, sessionState, and any error.
- Forward each new sample to ThresholdEngine and SessionRecorder.
- Avoid heavy processing on every sample.

```swift
@MainActor
final class HeartRateMonitor: NSObject, ObservableObject {
    @Published private(set) var currentBPM: Double?
    @Published private(set) var sessionState: SessionState = .idle
    @Published private(set) var lastSampleDate: Date?

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?

    func requestAuthorization() async throws { /* read heartRate, share workoutType */ }
    func startMonitoring() async throws { /* .other + .indoor session + builder */ }
    func pause() { /* session.pause() */ }
    func resume() { /* session.resume() */ }
    func stopMonitoring(saveToHealth: Bool) async { /* finish or discard, end */ }
    func recover() async throws { /* recoverActiveWorkoutSession */ }
}
```

### 7.1 Long Sessions and Recording *(v1.2: new)*

**Sampling.** During an active session the watch delivers a heart-rate reading roughly every few seconds (commonly about every 5 s). The app cannot set this rate. Ten hours is roughly 7,000–7,500 samples, about 150–250 KB.

**Rule: record every sample; the "interval" is a report setting.** Never down-sample on the watch. The phone groups samples into the interval the user picks, and can regroup at any time.

**On-disk format (watch).** One folder per session: `Documents/sessions/<id>/`

| File | Written | Content |
|---|---|---|
| `header.json` | At Start | id, startedAt, schemaVersion, device model, app version, settings snapshot |
| `samples.csv` | Appended | `offset_s,bpm` per line |
| `events.csv` | Appended | `offset_s,kind` per line |
| `summary.json` | At End | MonitoringSummary |
| `session-<id>.json` | At End | Full SessionRecording bundle, built from the above, for transfer |

- Buffer samples and events in memory; append to disk every 60 s **or** every 12 samples, whichever comes first, and immediately on pause, end, and when the app moves to the background.
- Use FileHandle appends; never rewrite the whole file during a session.
- After a crash, at most the unflushed buffer (≤ 60 s) is lost.

**Pauses.** While paused: no alerts, no gap counting, and paused time is excluded from `activeSeconds`. `paused`/`resumed` events mark the span.

**Gaps (report).** Any span over 60 s between consecutive samples while not paused is a gap. The report draws a break in the line and never interpolates. This is separate from `staleTimeout` (10 s), which only affects alerts and the live display.

**Battery guard.** `BatteryGuard` enables battery monitoring and reads the level every 60 s.

- Estimates time remaining from the drain rate over the last 15 minutes and shows it on the live screen.
- At or below `batteryGuardLevel` (default 10%): play a distinct haptic, end the session with `endReason = .batteryGuard`, finalize and queue the recording.

**Display while the wrist is down.** When `isLuminanceReduced` is true (Always On, wrist down), update the screen at most once per minute, with no animations. Full update rate only when the wrist is raised. Alerts always evaluate every sample regardless of display state.

**Other battery rules.** Heart rate only; indoor location; no network on the watch; no per-sample WatchConnectivity; no per-sample disk writes.

**Low Power Mode.** If the user enables the watch's Low Power Mode, heart-rate readings may arrive less often. Record what arrives and let gaps show honestly; never fabricate readings.

**Battery expectations.** Apple's published "workout tracking" ratings (October 2026): Ultra 4 up to 18 h; Series 12 up to 10 h; SE 3 up to 7 h. An indoor, heart-rate-only session should do better than these ratings, but this must be measured. A 10-hour session is the design target; on watches rated under 10 h the battery guard ends the session cleanly with a complete recording.

**Storage cleanup.** Keep finished recordings on the watch until the phone acknowledges them, then delete all but the most recent 5.

---

## 8. Threshold and Alert Logic

Do not implement the alert as a single `if bpm >= target` statement. Heart rate naturally oscillates around boundaries. Use zones, cooldowns, and hysteresis to avoid repeated haptics.

| Zone | Condition | Default haptic | Repeat rule |
|---|---|---|---|
| Normal | HR < warning BPM | None | No alert |
| Warning | warning BPM ≤ HR < target BPM | Notification / directionUp | At entry, then only after warning cooldown |
| Threshold | HR ≥ target BPM | Success/failure-style stronger haptic | At entry, then only after threshold cooldown |
| Stale | No fresh HR sample for chosen timeout | Optional single attention haptic | Once per stale episode |

```swift
func evaluate(bpm: Double, now: Date) -> HeartRateZone {
    if bpm >= settings.targetBPM { return .threshold }
    if bpm >= settings.warningBPM { return .warning }
    return .normal
}
// Alert only when:
// 1. entering a higher-risk zone, OR
// 2. still in that zone after its cooldown,
// AND suppress re-entry chatter until HR falls below the boundary by hysteresisBPM.
```

Suggested defaults: warningFraction = 0.90, warningCooldown = 60 s, thresholdCooldown = 30 s, hysteresisBPM = 5 BPM. These are UX defaults, not medical recommendations.

ThresholdEngine must be a pure type (no HealthKit, no UI, injectable clock) and must pass every case in `contracts/threshold-test-vectors.json`. Future ports (Kotlin, Monkey C) must pass the same vectors. *(v1.1)* Every alert the engine fires is also written to the recording as a `warning` or `threshold` event. *(v1.2)*

### Haptic implementation

Keep haptics behind a tiny service so alert behavior can change without touching HealthKit code. Use supported watchOS haptic types through `WKInterfaceDevice.current().play(...)`. Avoid an uncontrolled repeating haptic loop.

```swift
final class HapticAlertService {
    func warning()          { WKInterfaceDevice.current().play(.notification) }
    func thresholdReached() { WKInterfaceDevice.current().play(.failure) }
    func batteryGuard()     { WKInterfaceDevice.current().play(.retry) }   // v1.2
}
```

---

## 9. iPhone ↔ Watch Communication *(v1.2: reorganized)*

Use WatchConnectivity for everything between the two devices. App Groups do **not** share data between iPhone and Apple Watch (they are different devices). *(v1.1)*

### 9.1 Recordings: watch → phone (MVP)

- At End, build `session-<id>.json` and call `WCSession.default.transferFile(url, metadata: ["sessionId": id, "schemaVersion": 1])`. Transfers are queued by the system and continue in the background; the phone app does not need to be running.
- On every watch app launch, re-queue finished recordings that are not yet acknowledged, skipping any already in `outstandingFileTransfers`.
- **Phone side (native module):** in `session(_:didReceive:)`, move the file into the app's `Documents/inbox/` **before the delegate method returns** (the system deletes the received file afterwards). Then send an acknowledgement to the watch (`transferUserInfo(["ackSessionId": id])`) and, if JavaScript is running, emit `onRecordingReceived`.
- **Phone side (JavaScript):** on app start and on each `onRecordingReceived`, call `importPendingRecordings()`, validate each file against the contract, upsert by `id` into SQLite, keep the raw file, and clear it from the inbox. Imports must be idempotent.

### 9.2 Settings: phone → watch (later phase)

`updateApplicationContext` is the preferred mental model because the watch only needs the newest settings. In the MVP, settings are edited on the watch, so this path is not required.

- Encode HeartRateSettings to a property-list-safe dictionary.
- Persist the setting immediately on the iPhone, then call updateApplicationContext.
- On watch receipt, validate before saving locally. If a session is running, apply immediately, reset cooldowns, and record a `settingsChanged` event.
- Never make the watch wait for the phone before starting a session.

```swift
// iPhone (inside WatchBridgeModule.swift): latest-state sync — later phase
try WCSession.default.updateApplicationContext([
    "settingsVersion": 1,
    "targetBPM": settings.targetBPM,
    "warningFraction": settings.warningFraction,
    "warningCooldown": settings.warningCooldown,
    "thresholdCooldown": settings.thresholdCooldown,
    "hysteresisBPM": settings.hysteresisBPM
])
```

---

## 10. UI Specification *(v1.2: rewritten)*

### Watch (Workout-app style, minimal)

- **StartView:** one large card, "Alert at 150 BPM · warn at 135". Digital Crown adjusts the target in 1 BPM steps. Large **Start** button. Small gear for Save-to-Health and warning %.
- **LiveView:** current BPM is the dominant element, with a heart icon; zone label and colour (NORMAL / WARNING / THRESHOLD / WAITING FOR HR); elapsed time; target and warning BPM; battery % and estimated time left. When HR is stale, grey out the BPM and label it; never show an old BPM as current. Wrist-down: once-per-minute updates, no animation.
- **ControlsView** (swipe right from LiveView): **Pause/Resume** and **End**. End asks for confirmation.
- **SummaryView:** duration, avg/min/max BPM, time above target, warning and threshold counts, end reason if not user-ended, **Done**.
- None of these screens requires phone reachability.

### iPhone

- **HistoryScreen:** list of sessions, newest first: date, duration, avg/max BPM, alert count. Empty state explains how to start a session on the watch.
- **ReportScreen:**
  - Chart: x = time, y = BPM. Line = average per bucket; shaded band = min–max per bucket. Horizontal reference lines at warning and target BPM. Alert markers from events. Gaps and pauses drawn as breaks.
  - Interval chips: Raw / 1 min / 5 min / 15 min (default 1 min). "Raw" draws every sample, down-sampled for drawing only (≤ 1,500 points); export keeps every sample.
  - Stats grid: duration, avg, min, max, time above warning, time above target, alerts, gaps.
  - Export: CSV of raw samples or of the selected interval.
  - Disclaimer: personal wellness tool, not diagnosis or emergency monitoring.
- **SettingsScreen:** later phase.

---

## 11. Reliability and Edge Cases

| Condition | Required behavior |
|---|---|
| Health permission denied | Explain permission is required; do not repeatedly prompt in a loop. |
| No HR sample yet | Show Waiting for heart rate; no threshold evaluation. |
| Stale sample | After `staleTimeout`, zone becomes stale; old value is not used for alerts. |
| Phone disconnected | Monitoring, haptics and recording continue from local settings. |
| Settings changed mid-session | Apply immediately, reset cooldowns, record `settingsChanged`. |
| Session interrupted | Surface state and recover if HealthKit supports recovery; never pretend monitoring is active. |
| HR oscillates around target | Hysteresis + cooldown prevents vibration spam. |
| App backgrounded | Active workout session continues the HealthKit pipeline; recorder flushes on background. |
| Watch reboot/app termination | Recover via `handleActiveWorkoutRecovery`; if no workout to recover, finalize as `interrupted` and transfer. |
| Invalid settings | Clamp/reject and keep last valid settings. |
| Phone app killed / not running *(v1.1)* | Recordings queue via transferFile and arrive when possible; native module stores them in the inbox. |
| Battery reaches guard level *(v1.2)* | Haptic, end with `batteryGuard`, finalize and queue recording. |
| Battery dies before guard *(v1.2)* | Data up to the last flush is on disk; on next launch finalize as `interrupted` and transfer. |
| Watch removed from wrist *(v1.2)* | Readings stop arriving; stale for alerts, gaps in the report. Do not end the session automatically. |
| Low Power Mode on *(v1.2)* | Fewer readings may arrive; record what arrives; gaps shown. |
| Watch storage low *(v1.2)* | Before Start, require free space for a 10-hour recording (≥ 5 MB); otherwise show a message. |
| Duplicate file delivery *(v1.2)* | Phone import is idempotent by `id`. |
| No network / Supabase unreachable *(v1.1, post-MVP)* | Phone works from local storage; uploads retry later. |

---

## 12. Testing Plan / Definition of Done

### Unit tests

- ThresholdEngine zones below, at and above each boundary; hysteresis; cooldown reminders. (shared vectors)
- SummaryCalculator: avg/min/max, time above warning/target, gap seconds, paused time excluded. *(v1.2)*
- TypeScript aggregation: bucket avg/min/max/count, empty buckets as gaps, pauses as breaks. (shared `aggregation-test-vectors.json`) *(v1.2)*
- Recording round trip: write samples/events in chunks → finalize → bundle validates against the schema. *(v1.2)*
- Settings and recording decoding reject invalid or missing versions safely.
- React Native `WatchBridge` consumers tested against `MockWatchBridge` (Jest). *(v1.1)*

### On-device tests

- HealthKit permission request succeeds on a real Apple Watch.
- Live BPM changes while wearing the watch and moving.
- Lower wrist / return to watch face; session continues and BPM updates continue.
- Warning, threshold, no vibration storm, re-arm after hysteresis.
- Pause/resume: no alerts while paused; pause shown as a break in the report. *(v1.2)*
- iPhone off or out of range for the whole session; recording arrives after reconnecting. *(v1.2)*
- Force-quit / crash the watch app mid-session; the session recovers and the recording continues with a `recovered` event. *(v1.2)*
- Battery guard: start at low battery (≈ 15%); session ends cleanly at 10% with a complete recording. *(v1.2)*
- **Endurance: a 10-hour session on the target watch, starting from 100%.** Record start/end battery, sample count, gaps and whether the guard fired in `docs/TEST_LOG.md`. *(v1.2)*
- Stop monitoring; the workout/session ends cleanly; with save-to-Health off, nothing appears in Fitness. *(v1.2)*

> **Acceptance gate:** Do not call the MVP complete until background heart-rate updates, haptics, crash recovery and a long-session (target 10 h) recording have been tested on physical Apple Watch hardware. Simulator-only testing is insufficient.

---

## 13. Agent Implementation Sequence *(v1.2: re-sequenced; phase gates in IMPLEMENTATION_PLAN.md)*

1. **Contracts and pure logic:** schemas, ThresholdEngine, SummaryCalculator, TS aggregation, all with shared test vectors.
2. **Scaffold:** Expo React Native app (development build) + watchOS SwiftUI target via `@bacons/apple-targets`.
3. **Live heart rate:** HeartRateMonitor (`.other`, `.indoor`, HR only); LiveView shows real BPM.
4. **Recording:** SessionRecorder + RecordingStore; Pause/Resume/End; SummaryView.
5. **Alerts and watch-first setup:** StartView with Digital Crown target; ThresholdEngine → HapticAlertService; stale handling.
6. **Long-session hardening:** recovery, battery guard, wrist-down display, gaps, interrupted finalization, storage cleanup.
7. **Phone receive and report:** WatchBridge native module (transferFile inbox + ack), SQLite import, History, Report, CSV export.
8. **Acceptance:** all Section 12 tests including the 10-hour run.
9. **Later:** phone settings → watch, presets, Supabase, other watch platforms.

---

## 14. Copy/Paste Instruction for a Coding Agent

```text
Build the application described in docs/ARCHITECTURE.md as a React Native (Expo, TypeScript)
iPhone app with a native SwiftUI watchOS app target. Follow docs/IMPLEMENTATION_PLAN.md for
phase order; ARCHITECTURE.md rules take precedence if they conflict.

NON-NEGOTIABLE ARCHITECTURE:
- Apple Watch is the real-time decision maker for alerts AND the recorder of session data.
- Use HKWorkoutSession + HKLiveWorkoutBuilder, activityType .other, locationType .indoor,
  heart rate only, during an explicitly user-started session. Workout processing background mode.
- Record every heart-rate sample with its timestamp. Never down-sample on the watch.
  Flush to disk at least every 60 s using appends. Support sessions up to 10 hours.
- Implement workout recovery (handleActiveWorkoutRecovery / recoverActiveWorkoutSession) and
  finalize interrupted recordings on next launch.
- Battery guard ends the session cleanly at the configured level (default 10%).
- Wrist-down display updates at most once per minute; alerts still evaluate every sample.
- Do not depend on the iPhone during a session. Send the finished recording with
  WCSession.transferFile; the phone native module moves it to an inbox before returning,
  then acknowledges. Imports are idempotent by session id.
- The React Native app reaches WatchConnectivity only through the WatchBridge native module.
  No threshold or alert logic in JavaScript/TypeScript. The phone never edits samples.
- Watch source lives in apps/mobile/targets/watch (outside ios/). Never hand-edit generated
  ios/ files; configure through Expo config and expo-target.config.js.
- ThresholdEngine, SummaryCalculator and TS aggregation must pass the vectors in contracts/.
- MVP is local-only: no backend, login, analytics, or cloud dependency.

ENGINEERING RULES:
- Small testable types; async/await; UI updates on the main actor.
- Validate every payload crossing a device boundary against contracts/.
- Do not swallow HealthKit, workout-session, file or transfer errors.
- Never fabricate or interpolate heart-rate data; show gaps.
- Wellness wording only; never claim diagnosis or emergency monitoring.
- Test doubles only in tests/previews.
- README: setup, capabilities, usage strings, device test procedure, known limits.
```

---

## 15. References Used for This Architecture

- Running workout sessions – Apple Developer Documentation
  <https://developer.apple.com/documentation/HealthKit/running-workout-sessions>
- HKLiveWorkoutBuilder – Apple Developer Documentation
  <https://developer.apple.com/documentation/HealthKit/HKLiveWorkoutBuilder>
- Watch Connectivity – Apple Developer Documentation
  <https://developer.apple.com/documentation/WatchConnectivity>
- WCSession applicationContext – Apple Developer Documentation
  <https://developer.apple.com/documentation/watchconnectivity/wcsession/applicationcontext>
- *(v1.2)* WCSession transferFile(_:metadata:) – Apple Developer Documentation
  <https://developer.apple.com/documentation/watchconnectivity/wcsession/transferfile(_:metadata:)>
- *(v1.2)* HKHealthStore recoverActiveWorkoutSession – Apple Developer Documentation
  <https://developer.apple.com/documentation/healthkit/hkhealthstore/recoveractiveworkoutsession(completion:)>
- Enabling Background Sessions – Apple Developer Documentation
  <https://developer.apple.com/documentation/watchkit/enabling-background-sessions>
- *(v1.2)* Apple Watch battery – Apple
  <https://www.apple.com/watch/battery/>
- *(v1.2)* Use Low Power Mode on your Apple Watch – Apple Support
  <https://support.apple.com/HT213336>
- *(v1.1)* Expo Apple Targets (watch targets in Expo projects)
  <https://github.com/EvanBacon/expo-apple-targets>
- *(v1.1)* Expo Modules API (local native modules)
  <https://docs.expo.dev/modules/overview/>

> **Architecture note:** Apple platform behavior can change across watchOS/Xcode releases. The coding agent should compile against the installed SDK and reconcile any API signature changes with current Apple documentation rather than inventing workarounds.

---

## Appendix A — Change log

### v1.2 (October 2026): long-session recording and Workout-style watch app

1. Primary objective and one-line product description: 10-hour sessions, record every reading, report on phone.
2. Section 1: rows for HR source, background model (`.other`/`.indoor`), session length, recording, communication, MVP settings on watch, persistence, Apple Health option; note that phone-timed sampling is not possible.
3. Section 1.1: companion app MVP is history + report + CSV export; settings move to a later phase.
4. Section 2: must-haves rewritten (watch start screen, controls, recording, recovery, battery guard, summary; phone report). Out-of-scope list extended.
5. Section 3: user flows rewritten (watch-first).
6. Section 4: diagram adds SessionRecorder, BatteryGuard, RecordingTransfer, report modules; new design rule (watch recording is the data of record).
7. Section 5: new files for recording, battery guard, transfer, views, report; new contracts.
8. Section 6: HeartRateSample, SessionEvent, EndReason, SessionRecording; MonitoringSummary extended; new settings fields.
9. Section 7: permissions, sample reading, ending, recovery; new Section 7.1 (sampling, file format, flush, pauses, gaps, battery guard, display, battery expectations, cleanup).
10. Section 8: alerts written as events; battery-guard haptic.
11. Section 9: reorganized: recordings via transferFile (MVP), settings via application context (later).
12. Sections 10–15: UI, edge cases, tests (incl. 10-hour endurance and crash recovery), sequence, agent instruction and references updated.

### v1.1 (October 2026): React Native companion app

React Native/Expo for the iPhone app; Section 1.1 product description; WatchBridge native module; Expo monorepo structure with `contracts/`; shared threshold test vectors; Supabase and other watch platforms as later phases.
