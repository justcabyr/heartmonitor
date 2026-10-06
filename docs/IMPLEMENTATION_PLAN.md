# HeartThreshold — Incremental Implementation Plan

A Workout-style Apple Watch app for heart rate only: alerts before and at your threshold, recording of every reading for sessions up to 10 hours, and a React Native iPhone app for history and reports. Built so Wear OS (Google Pixel Watch, Samsung Galaxy Watch) and Garmin can be added later without a rewrite.

Version 2.0 | October 2026 · Companion to `docs/ARCHITECTURE.md` (v1.2)

---

## 0. How to use this plan (and how Cursor should use it)

- **ARCHITECTURE.md = what and why.** Rules, data models, recording format, alert logic. It wins any conflict.
- **IMPLEMENTATION_PLAN.md = when and in what order.** Work one phase at a time. Each phase has a goal, tasks, a **Done when** gate, and **Take note** items (accounts, devices, costs, decisions) placed where they come up.
- Do not start a phase until the previous phase's **Done when** gate passes. Commit after every passing gate.
- Keep both files in `docs/`, and `.cursor/rules/heartthreshold.mdc` in the repo, so Cursor always loads the rules.
- Each phase ends with a **Cursor prompt**. Keep prompts to one phase.

**Assumption for this version:** the main test device is a recent Apple Watch. If yours is rated under 10 hours of workout tracking (see Phase 0), the 10-hour test becomes "runs until the battery guard ends it cleanly with a complete recording".

Phase map:

| # | Phase | Device needed | Account needed |
|---|---|---|---|
| 0 | Machine & accounts setup | — | Apple ID (free) |
| 1 | Contracts & pure logic | — | — |
| 2 | Scaffold Expo app + watch target | Simulators | Free Apple ID in Xcode |
| 3 | Live heart rate on the watch | **iPhone + Apple Watch** | Free or paid |
| 4 | Recording, controls, watch summary | iPhone + Apple Watch | Free or paid |
| 5 | Alerts + watch-first start screen | iPhone + Apple Watch | Free or paid |
| 6 | Long-session hardening (10 h) | iPhone + Apple Watch | Free or paid |
| 7 | Phone: receive recordings, history, report | iPhone + Apple Watch | Free or paid |
| 8 | MVP acceptance | iPhone + Apple Watch | **Paid recommended** |
| 9 | TestFlight distribution | iPhone + Apple Watch | **Apple Developer Program (paid)** |
| 10 | Phone settings, presets, sync status | iPhone + Apple Watch | — |
| 11 | Supabase: accounts + cloud backup | — | Supabase (free tier) |
| 12 | Android phone + Wear OS watch (Pixel, Galaxy) | Android phone + Wear OS watch | Google Play Console |
| 13 | Samsung-specific extras (optional) | Galaxy Watch4+ | Samsung partner program |
| 14 | Garmin Connect IQ watch app | Garmin watch | Garmin developer account |

Phases 0–8 are the MVP.

---

## 1. Platform reality check (read once)

| Watch | Pairs with | Watch-side language | Live HR API | Background during a session | Phone↔watch channel |
|---|---|---|---|---|---|
| Apple Watch | iPhone only | Swift / SwiftUI | HealthKit `HKWorkoutSession` + `HKLiveWorkoutBuilder` | Runs while workout session active | WatchConnectivity |
| Google Pixel Watch | Android only | Kotlin / Compose for Wear OS | Health Services `ExerciseClient` | Runs while exercise active (foreground service) | Wearable Data Layer API |
| Samsung Galaxy Watch4+ | Android only | Kotlin (same Wear OS app) | Health Services `ExerciseClient` (optional: Samsung Health Sensor SDK) | Same as Wear OS | Wearable Data Layer API |
| Garmin (Connect IQ) | **iPhone and Android** | Monkey C | `Toybox.Sensor` / `Activity` HR in a device app | App must stay in the foreground; no general background processing | Connect IQ Mobile SDK, via the Garmin Connect app |

What this means:

1. **Every watch platform needs its own native watch app.** You share the *contract*: field names, validation rules, threshold and aggregation test vectors, and the recording format.
2. **The phone app is shared** (React Native on iOS and Android) and talks to any watch through one TypeScript interface, `WatchBridge`, with one adapter per platform.
3. **Garmin is the odd one out:** it works with both phones, but sync goes through Garmin's own app and background messaging is very limited. Garmin devices also have little memory, so long recordings there may need per-minute aggregates on the watch.
4. Samsung Galaxy Watches run Wear OS, so the Wear OS app covers them. The Samsung Health Sensor SDK is only for extra raw signals and needs Samsung partner approval to distribute.

---

## 2. Design principles that keep multi-watch support cheap

**2.1 Contract-first.** `contracts/` holds JSON Schemas for `HeartRateSettings` and `SessionRecording` (header, samples, events, summary), plus `threshold-test-vectors.json` and `aggregation-test-vectors.json`. Every implementation is tested against the same files.

Threshold vector example:

```json
{
  "name": "warning entry fires once, then cooldown suppresses",
  "settings": { "targetBPM": 180, "warningFraction": 0.9, "warningCooldown": 60,
                "thresholdCooldown": 30, "hysteresisBPM": 5 },
  "samples": [ { "t": 0, "bpm": 150 }, { "t": 5, "bpm": 163 }, { "t": 10, "bpm": 165 },
               { "t": 70, "bpm": 164 } ],
  "expected": [ { "t": 0, "zone": "normal",  "alert": null },
                { "t": 5, "zone": "warning", "alert": "warning" },
                { "t": 10,"zone": "warning", "alert": null },
                { "t": 70,"zone": "warning", "alert": "warning" } ]
}
```

Aggregation vector example:

```json
{
  "name": "1-minute buckets with a gap and a pause",
  "intervalSeconds": 60,
  "samples": [ { "t": 0, "bpm": 70 }, { "t": 30, "bpm": 80 }, { "t": 200, "bpm": 90 } ],
  "events":  [ { "t": 240, "kind": "paused" }, { "t": 400, "kind": "resumed" } ],
  "expected": [ { "start": 0,   "avg": 75, "min": 70, "max": 80, "count": 2 },
                { "start": 60,  "gap": true },
                { "start": 120, "gap": true },
                { "start": 180, "avg": 90, "min": 90, "max": 90, "count": 1 },
                { "start": 240, "paused": true },
                { "start": 300, "paused": true },
                { "start": 360, "paused": true } ]
}
```

**2.2 One phone-side interface.**

```ts
// apps/mobile/src/watch/WatchBridge.ts
export type WatchPlatform = 'watchos' | 'wearos' | 'garmin';

export interface WatchStatus {
  platform: WatchPlatform;
  paired: boolean;
  appInstalled: boolean;
  reachable: boolean;            // live connection right now (often false; that's fine)
}

export interface WatchBridge {
  platform: WatchPlatform;
  isSupported(): Promise<boolean>;
  getStatus(): Promise<WatchStatus>;
  onStatusChange(cb: (s: WatchStatus) => void): () => void;

  // MVP: recordings arrive from the watch
  importPendingRecordings(): Promise<SessionRecording[]>;   // drains the native inbox
  onRecordingReceived(cb: () => void): () => void;           // "inbox has something"

  // Later phase (10): settings to the watch
  pushSettings?(s: HeartRateSettings): Promise<'sent' | 'queued' | 'unavailable'>;
}
```

Adapters: `AppleWatchBridge` (Phase 7), `MockWatchBridge` (tests, Android until Phase 12), `WearOsBridge` (Phase 12), `GarminBridge` (Phase 14). Screens only ever import `WatchBridge`.

**2.3 Platform-tagged data.** Every recording carries `sourcePlatform`, `deviceModel`, `watchAppVersion`.

**2.4 Watch-generated IDs.** The watch creates the session `id` (UUID) at Start. Phone SQLite and Supabase use it as the primary key, so retries never duplicate.

**2.5 No alert logic outside watches; no sample edits outside watches.** The phone displays, groups, exports and stores.

---

## 3. How the React Native app and the watch app communicate

**They are one product in one repo, but two separate apps running on two separate devices.**

- **Repo/project:** The Expo project generates an Xcode workspace (`ios/`). The watch app is an extra *target* inside it, created by `@bacons/apple-targets` from source in `apps/mobile/targets/watch/`. There aren't two unrelated Xcode projects.
- **Bundle relationship:** The watch app is embedded in the iPhone app. Bundle IDs share a prefix, e.g. `com.yourname.heartthreshold` (phone) and `com.yourname.heartthreshold.watchkitapp` (watch). Installing the phone app offers the watch app on the paired watch.
- **Runtime channel:** Apple's WatchConnectivity (`WCSession`). React Native can't call it directly, so a small Swift native module does.

```
 Apple Watch (Swift)                     iPhone native                       React Native (JS/TS)
 ───────────────────                     ─────────────                       ────────────────────
 Session runs for hours
   SessionRecorder → Documents/sessions/<id>/  (appends every ≤60 s)
 User taps End
   build session-<id>.json
   WCSession.transferFile ──────────▶   WatchBridgeModule.swift
   (queued by watchOS; phone app         didReceive(file):
    does not need to be running)           move to Documents/inbox/   (before returning!)
                                           transferUserInfo(ack) ──▶ watch deletes old files
                                           emit onRecordingReceived ──▶ importPendingRecordings()
                                                                          validate → SQLite upsert by id
                                                                          HistoryScreen / ReportScreen
```

| Data | Direction | Call | Why |
|---|---|---|---|
| Finished recording (MVP) | Watch → Phone | `transferFile` | Large payload, queued, survives either app not running |
| Recording acknowledgement (MVP) | Phone → Watch | `transferUserInfo` | Queued; lets the watch clean up |
| Settings (Phase 10) | Phone → Watch | `updateApplicationContext` | Only the latest value matters |
| Live BPM to phone (optional, much later) | Watch → Phone | `sendMessage` | Only when both apps are active; never required |

Two details that trip people up:

- **The received file is deleted by iOS when the delegate method returns.** The native module must move it to the inbox inside that method. That's also why the module, not JavaScript, owns the inbox: JavaScript may not be running when the file arrives.
- **App Groups don't connect iPhone and Watch.** They only share data between apps on the same device.

**Library choice:** write the small local Expo module (`apps/mobile/modules/watch-bridge`) rather than depending on `react-native-watch-connectivity`. That library is a useful reference, but this app needs a handful of calls, file-inbox handling, and the exact `WatchBridge` shape later adapters will copy.

---

## 4. Phases

### Phase 0 — Machine & accounts setup

**Goal:** a machine that can build iOS + watchOS, and decisions you'd otherwise make in a hurry.

Tasks:
- Mac with current Xcode (iOS + watchOS SDKs and simulators). Node LTS, npm or pnpm, Watchman, CocoaPods.
- Cursor; create the repo with `docs/` and `.cursor/rules/` from day one.
- **Decide your bundle ID prefix now** (e.g. `com.yourname.heartthreshold`). Changing it after TestFlight is painful.

**Take note:**
- An Apple ID added in Xcode (Settings → Accounts) gives a free "Personal Team". Enough to start.
- **Check your test watch's battery rating** (Apple's "workout tracking" figure, October 2026): Ultra 4 up to 18 h, Series 12 up to 10 h, SE 3 up to 7 h; older models vary. This sets what the 10-hour test in Phase 6 and 8 can achieve.

**Done when:** `xcodebuild -version` and `node -v` work; repo committed with `docs/` and the Cursor rule.

---

### Phase 1 — Contracts & pure logic (no device needed)

**Goal:** the alert brain, summary maths and report grouping exist, are tested, and are platform-neutral.

Tasks:
- `contracts/heart-rate-settings.schema.json`, `contracts/session-recording.schema.json` with `schemaVersion`. Validation ranges: `targetBPM` 60–230, `warningFraction` 0.5–0.99, cooldowns 5–600 s, `hysteresisBPM` 1–20, `batteryGuardLevel` 0.05–0.30. (UX limits, not medical advice.)
- `contracts/threshold-test-vectors.json`: boundaries, hysteresis chatter, cooldown repeat, stale episode, settings change mid-session.
- `contracts/aggregation-test-vectors.json`: bucket avg/min/max/count; empty buckets as gaps; pauses as breaks; 10-hour synthetic input (performance).
- `packages/threshold-engine-swift/`: `ThresholdEngine` (pure, injected clock) and `SummaryCalculator` (avg/min/max, time above warning/target, gap seconds, paused time excluded) with XCTests loading the vectors.
- `apps/mobile/src/domain/`: TS types + zod validation. `apps/mobile/src/report/aggregate.ts` + `downsample.ts` + `csv.ts` with Jest tests loading the aggregation vectors.

**Done when:** `swift test` passes in the package; Jest passes; every vector is exercised.

**Cursor prompt:**

> Read docs/ARCHITECTURE.md sections 6, 7.1 and 8, and docs/IMPLEMENTATION_PLAN.md Phase 1. Create contracts/ (two schemas and both vector files covering every case listed), a Swift package packages/threshold-engine-swift with pure ThresholdEngine and SummaryCalculator plus XCTests that load the vectors, and TS types + zod validation + report/aggregate.ts, downsample.ts, csv.ts in apps/mobile with Jest tests. No UI, no HealthKit.

---

### Phase 2 — Scaffold Expo app + watch target

**Goal:** one repo that builds a React Native iPhone app with an embedded SwiftUI watch app, in simulators.

Tasks:
- Create `apps/mobile` with Expo (TypeScript, expo-router). Use **development builds**, not Expo Go.
- Add `@bacons/apple-targets`; create the watch target; lay out `targets/watch/` exactly as ARCHITECTURE §5. watchOS deployment target 10.0 or later.
- Link the Phase 1 Swift package into the watch target.
- Watch config: HealthKit entitlement, Workout processing background mode, `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`.
- Placeholder screens: phone `HistoryScreen`, `ReportScreen`; watch `StartView`, `LiveView` with "--" BPM.
- `npx expo prebuild -p ios --clean` must regenerate everything with no manual Xcode edits.

**Take note:**
- **Never hand-edit `ios/`.** All config goes in `app.config.ts` / `expo-target.config.js`.
- Simulators are fine here; live heart rate isn't meaningful in the simulator.

**Done when:** after a clean prebuild, the phone app runs in the iOS Simulator and the watch app runs in a paired watchOS Simulator from the same workspace.

**Cursor prompt:**

> Implement Phase 2 of docs/IMPLEMENTATION_PLAN.md. Scaffold apps/mobile with Expo + TypeScript + expo-router, add @bacons/apple-targets and a watch target in apps/mobile/targets/watch using the exact layout in docs/ARCHITECTURE.md §5. Configure HealthKit, workout-processing background mode and usage strings via config, not ios/. Link packages/threshold-engine-swift. Placeholder UIs only. Verify prebuild --clean regenerates cleanly.

---

### Phase 3 — Live heart rate on the watch (first real hardware)

**Goal:** wear the watch, tap Start, see your real BPM.

Tasks:
- `HeartRateMonitor` per ARCHITECTURE §7: authorization (read heartRate, share workoutType), `.other` + `.indoor` session, live builder, sample reading with timestamp de-duplication, start/stop with discard (save-to-Health off).
- `LiveView` shows real BPM, elapsed time and session state.

**Take note — first physical device deployment:**
- Enable **Developer Mode** on the iPhone, then on the Apple Watch (Settings → Privacy & Security → Developer Mode). Each restarts.
- Connect the iPhone by cable the first time; select your team for **both** targets; let Xcode manage signing. Keep the watch unlocked and near the phone; first install can be slow.
- **Free Personal Team limits:** apps expire after **7 days**; some accounts hit a provisioning error on the HealthKit entitlement. If you do, enrol in the paid program now rather than at Phase 8.

**Done when:** on hardware, BPM updates live; lowering the wrist and returning shows the session still running; ending the session leaves nothing in Fitness.

**Cursor prompt:**

> Implement Phase 3 of docs/IMPLEMENTATION_PLAN.md: HeartRateMonitor per ARCHITECTURE §7 (activityType .other, locationType .indoor, heart rate only, timestamp de-duplication, discard on end) and a LiveView showing live BPM, elapsed time and state. Surface every HealthKit/workout error; no fake data outside previews.

---

### Phase 4 — Recording, controls, watch summary

**Goal:** every reading is saved safely on the watch, and you can pause, resume and end like the Workout app.

Tasks:
- `SessionRecorder` + `RecordingStore` per ARCHITECTURE §7.1: session folder, `header.json` at Start, buffered appends to `samples.csv` / `events.csv` every 60 s or 12 samples, flush on pause/end/background, `summary.json` + `session-<id>.json` bundle at End (validated against the schema).
- `ControlsView` (swipe right from LiveView): Pause/Resume, End with confirmation. Paused time excluded; `paused`/`resumed` events recorded.
- `SummaryView` after End using `SummaryCalculator`.
- Debug-only screen listing recordings on the watch with sample counts (for testing).

**Done when:** a 30-minute session on hardware produces a valid bundle whose sample count roughly matches duration ÷ ~5 s; pause/resume appear as events; summary numbers match a recount from `samples.csv`.

**Cursor prompt:**

> Implement Phase 4 of docs/IMPLEMENTATION_PLAN.md: SessionRecorder and RecordingStore exactly per ARCHITECTURE §7.1 (append-only files, flush rules, bundle at end), ControlsView with Pause/Resume/End, SummaryView using SummaryCalculator. Never down-sample. Add a debug-only recordings list.

---

### Phase 5 — Alerts + watch-first start screen

**Goal:** the product's core value works with no phone involvement.

Tasks:
- `StartView` per ARCHITECTURE §10: target card, Digital Crown adjusts target (saved in `WatchSettingsStore`), warning % and Save-to-Health in a small settings sheet.
- Feed every sample into `ThresholdEngine`; drive `HapticAlertService`; write `warning`/`threshold` events to the recording.
- Stale handling: after `staleTimeout`, zone `stale`, BPM greyed, no alerts from old values; `staleStart`/`staleEnd` events.
- Zone colour on LiveView; alert counts in SummaryView.

**Done when:** on hardware, ARCHITECTURE §12 haptic checks pass: one warning on entry, distinct threshold haptic, no vibration storm, re-arm after hysteresis. Test with a low target (e.g. 100 BPM) and a brisk walk or stairs.

**Cursor prompt:**

> Implement Phase 5 of docs/IMPLEMENTATION_PLAN.md: StartView with Digital Crown target, ThresholdEngine → HapticAlertService on every sample, alert and stale events written to the recording, zone UI per ARCHITECTURE §10.

---

### Phase 6 — Long-session hardening (10 hours)

**Goal:** a session can run all day and survive crashes, low battery and wrist-off periods without losing data.

Tasks:
- Crash/relaunch recovery: `activeSessionId` in UserDefaults; `handleActiveWorkoutRecovery()` → `recoverActiveWorkoutSession`; reopen recording; `recovered` event. If nothing to recover, finalize as `interrupted`.
- `BatteryGuard`: level every 60 s, time-remaining estimate on LiveView, end at 10% with `batteryGuard` haptic and end reason.
- Wrist-down display: when `isLuminanceReduced`, update at most once per minute, no animations.
- Gaps: SummaryCalculator counts spans > 60 s (not paused) as gaps.
- Free-space check before Start (≥ 5 MB).
- Storage cleanup policy (after Phase 7 acks: keep last 5).

**Take note:**
- Run a **2-hour session** first and note battery drop per hour. Multiply out; if it won't reach 10 h on your watch, that's expected for lower-rated models. The battery guard must still end it cleanly.
- To test recovery: start a session, then force-quit the app from the watch (or stop it from Xcode). Reopen; the session should resume.
- Charge to 100% before the 10-hour test and keep the watch's normal settings. Don't enable Low Power Mode for the reference test; test it separately.

**Done when:** recovery test passes; battery guard test passes (start ≈ 15%, ends cleanly at 10%); a **10-hour session** (or until guard on lower-rated watches) produces a complete recording. Results logged in `docs/TEST_LOG.md`.

**Cursor prompt:**

> Implement Phase 6 of docs/IMPLEMENTATION_PLAN.md: workout recovery and interrupted finalization, BatteryGuard, wrist-down display throttling, gap accounting and the free-space check, all per ARCHITECTURE §7 and §7.1. Add a TEST_LOG.md template with the §12 on-device checks.

---

### Phase 7 — Phone: receive recordings, history, report

**Goal:** sessions show up on the phone with a chart you can read.

Tasks:
- Watch `RecordingTransfer`: `transferFile` at End; re-queue unacknowledged on launch (skip ones in `outstandingFileTransfers`); delete acked except last 5.
- Local Expo module `modules/watch-bridge` (Swift): activate `WCSession`; in `didReceive(file)` move to `Documents/inbox/` before returning, send ack, emit event; `importPendingRecordings`; `getStatus`.
- `AppleWatchBridge.ts` + `MockWatchBridge.ts`; screens import only `WatchBridge`.
- Import: validate (zod) → upsert summary into SQLite (`expo-sqlite`) by `id` → keep raw bundle in app storage → clear inbox. Run on app start and on each event.
- `HistoryScreen` and `ReportScreen` per ARCHITECTURE §10. Chart: `victory-native` (Skia) recommended; average line + min–max band, warning/target lines, alert markers, breaks for gaps/pauses. Interval chips Raw/1/5/15 min. Stats grid. CSV export via `expo-file-system` + `expo-sharing`.

**Take note:**
- WatchConnectivity only works on a real paired iPhone + Watch (or a paired simulator pair). The watch app must have launched once after install.
- File transfers can take a while; that's normal. Test with the phone out of range for the whole session.

**Done when:** end a session with the phone app closed → open the app later → the session appears exactly once with a correct chart and stats; a 10-hour recording opens and scrolls smoothly; CSV opens correctly in a spreadsheet.

**Cursor prompt:**

> Implement Phase 7 of docs/IMPLEMENTATION_PLAN.md: watch RecordingTransfer, the watch-bridge Expo module (inbox move inside didReceive, ack, events), AppleWatchBridge/MockWatchBridge per §2.2, idempotent import into SQLite, HistoryScreen and ReportScreen per ARCHITECTURE §10 using report/aggregate.ts. No alert logic in TS.

---

### Phase 8 — MVP acceptance

**Goal:** the v1 MVP is done.

Tasks:
- Run every ARCHITECTURE §12 check on hardware, including the 10-hour session end to end (watch → phone report). Log results.
- README: setup, capabilities, usage strings, device test procedure, known limits (battery by model, Low Power Mode effect).

**Take note — Apple Developer Program:**
- **Enrol now if you haven't** (US$99/year; individual enrolment is quick, organisation enrolment needs a D-U-N-S number and takes longer). Builds stop expiring after 7 days and HealthKit provisioning is reliable. Required for Phase 9.

**Done when:** all §12 checks pass on physical hardware. This is the **MVP gate**.

---

### Phase 9 — TestFlight distribution

Tasks:
- Register bundle IDs (phone + watch); enable HealthKit on the watch App ID.
- Create the app record in App Store Connect; build with EAS Build (`eas build -p ios`) or archive in Xcode (watch app ships inside the iOS build).
- Upload; add yourself as an **internal tester** (no Beta App Review for internal testers).
- Complete App Privacy details; publish a privacy policy URL.

**Take note:**
- External TestFlight testers require Beta App Review.
- App Store Guideline 5.1.3: no personal health information in iCloud; no advertising/data-mining use of HealthKit data; no sharing with third parties without consent. Your own backend (Supabase) is allowed with disclosure. Say "wellness", never "medical".

**Done when:** you install from TestFlight and Phase 8 checks still pass on that build.

---

### Phase 10 — Phone settings, presets, sync status

**Goal:** set things up from the phone as well as the watch.

Tasks:
- `SettingsScreen` (target, warning %, cooldowns hidden under "Advanced", Save-to-Health).
- `pushSettings` in the native module → `updateApplicationContext`; watch `WatchSyncReceiver` validates, saves, applies mid-session with a `settingsChanged` event, and acknowledges.
- Last-write-wins between watch and phone edits using `settingsVersion` + timestamp.
- Presets (e.g. "Walk 120", "Workout 160") stored on both sides.
- Sync status: Saved locally / Sent to Watch / Watch unavailable.

**Done when:** change target on phone → watch shows it within seconds (app open) or on next launch; editing on the watch is reflected on the phone; phone Bluetooth off during a session changes nothing on the watch.

---

### Phase 11 — Supabase: accounts + cloud backup (phone only)

**Goal:** history survives a phone change; groundwork for multi-device history.

Tasks:
- Create a Supabase project. **Pick the region before creating it** (e.g. `ca-central-1` Canada, `us-east-1`, `eu-west-2`).
- Auth: email magic link or email/password. If you add Google login, App Store rules also require Sign in with Apple (or an equivalent privacy-focused option).
- **Summaries in a table; raw recordings in Storage.** A 10-hour session is ~7,000 samples; storing them as rows works but is wasteful. Upload the bundle JSON to a private bucket at `recordings/<user_id>/<session_id>.json` and keep the summary row for lists and stats.
- Sync: local SQLite + files remain the source of truth on the phone; an outbox queues uploads; push when online and signed in; pull on login. Upserts by session `id`.
- The **watch never talks to Supabase.**

```sql
create table public.monitoring_sessions (
  id uuid primary key,                      -- generated on the watch
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  active_seconds numeric not null,
  sample_count int not null,
  avg_bpm numeric not null,
  min_bpm numeric not null,
  max_bpm numeric not null,
  warning_events int not null default 0,
  threshold_events int not null default 0,
  seconds_above_warning numeric not null default 0,
  seconds_above_target numeric not null default 0,
  gap_seconds numeric not null default 0,
  target_bpm numeric not null,
  warning_bpm numeric not null,
  end_reason text not null check (end_reason in ('user','batteryGuard','interrupted','error')),
  source_platform text not null check (source_platform in ('watchos','wearos','garmin')),
  device_model text,
  watch_app_version text,
  recording_path text,                      -- Storage object path
  schema_version int not null default 1,
  created_at timestamptz not null default now()
);

create table public.user_settings (
  user_id uuid primary key default auth.uid() references auth.users on delete cascade,
  settings jsonb not null,
  settings_version int not null,
  updated_at timestamptz not null default now()
);

alter table public.monitoring_sessions enable row level security;
alter table public.user_settings enable row level security;

create policy "own sessions" on public.monitoring_sessions
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own settings" on public.user_settings
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Private bucket for raw recordings, one folder per user
insert into storage.buckets (id, name, public) values ('recordings', 'recordings', false);

create policy "own recordings" on storage.objects for all
  using (bucket_id = 'recordings' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'recordings' and (storage.foldername(name))[1] = auth.uid()::text);
```

**Take note:**
- Only the anon (publishable) key goes in the app; never the service-role key.
- Add "Delete my account and data" (deletes rows and Storage objects). App Store requires account deletion if you offer account creation.
- Update the privacy policy and App Privacy labels: recordings stored on your server.
- The free tier pauses inactive projects; fine for personal use, revisit before real users.

**Done when:** sign in on a second phone (or reinstall) → history, reports and settings restore; airplane mode → app works, syncs later, no duplicates.

#### Is Supabase the right database?

For this app, **yes**. Summaries and settings are small, relational, per-user records, and raw recordings are files. Postgres + Row Level Security + Storage + built-in auth covers both, there's a Canadian region, and everything exports with standard tools.

| Option | Good at | Weak spot here | Verdict |
|---|---|---|---|
| **Supabase** (Postgres + Storage) | Relational summaries, file storage, RLS, auth, SQL, region choice, no lock-in | Offline sync is your job (outbox) | **Recommended** |
| Supabase + PowerSync | Automatic SQLite↔Postgres offline sync, React Native SDK | Extra service; overkill for append-only sessions | Only if you add multi-device editing |
| Firebase (Firestore + Storage) | Built-in offline cache and sync | NoSQL, weaker for stats queries, Google lock-in | Reasonable if you want zero sync code |
| Convex | Reactive TypeScript backend | Less mature mobile offline story | Not better for this case |
| Local-only | Simplest, most private | No backup or cross-device history | Fine as long as you want |

If you ever handle other people's health data commercially, check privacy law where your users are (e.g. PIPEDA/provincial laws in Canada, HIPAA where US healthcare entities are involved) and the provider's compliance offerings.

---

### Phase 12 — Android phone + Wear OS watch (Pixel Watch, Galaxy Watch)

Tasks:
- Android phone: the same `apps/mobile` app. `WearOsBridge.ts` + Android native module using the **Wearable Data Layer API**: `ChannelClient` or a `DataClient` asset for recording files (watch → phone), `DataClient` for settings.
- Wear OS watch: `apps/wear-os/`, Kotlin + Compose for Wear OS.
  - Live HR: **Health Services `ExerciseClient`** with a foreground service (equivalent of the HealthKit workout session); heart rate only.
  - Port `ThresholdEngine` and `SummaryCalculator` to Kotlin; they must pass the shared vectors.
  - Same recording format, flush rules, battery guard and recovery behaviour (resume via the active exercise on relaunch).
  - Haptics via `Vibrator` with distinct patterns.
- `sourcePlatform: "wearos"`.

**Take note:**
- **Google Play Console** (one-time US$25; new personal accounts must run a closed test before production access, check current rules).
- Wear OS health permissions are moving from the broad body-sensors permission to granular ones (e.g. read heart rate). Follow current Health Services docs at build time.
- Play requires a health apps declaration and data safety form.
- Test on a **real** Pixel Watch or Galaxy Watch; battery life for 10-hour sessions varies a lot by model.

**Done when:** Phases 3–8 acceptance checks pass on a Wear OS watch with an Android phone, and the report screen shows its recordings unchanged.

---

### Phase 13 — Samsung-specific extras (optional)

Galaxy Watch4 and later are already covered by Phase 12. Only for Samsung-only signals (e.g. inter-beat interval for HRV).

- Samsung Health Sensor SDK: Galaxy Watch4+ only, no emulator; **distribution requires Samsung partner approval**.
- Keep it behind a capability check so the same Wear OS app runs on non-Samsung watches.

---

### Phase 14 — Garmin Connect IQ

Tasks:
- `apps/garmin/`: Connect IQ **device app** in Monkey C.
- Read HR during a recorded activity; port `ThresholdEngine`; validate with the shared vectors via a small harness.
- Recording: device memory is limited. Store per-minute aggregates (avg/min/max/count) on the watch, which the report already understands, or raw samples if the target device has room.
- Alerts via `Attention.vibrate()` with distinct patterns.
- Phone side: `GarminBridge.ts` + native modules wrapping the **Connect IQ Mobile SDK** (iOS and Android).

**Take note:**
- Free Garmin developer account; Connect IQ Store review.
- **The app must stay in the foreground during a session**; background services run only briefly every few minutes. Send the recording at session end while the app is open.
- Declare supported devices; test on your actual model. Garmin battery life for long sessions is typically excellent.

**Done when:** alert behaviour matches the shared vectors on a real Garmin; a recording reaches phone history and renders in the same report.

---

## 5. "Take note" timeline (quick reference)

| When | What | Cost / effort |
|---|---|---|
| Phase 0 | Bundle ID prefix; Apple ID in Xcode; check your watch's battery rating | Free |
| Phase 2 | Expo development builds; never edit `ios/` by hand | — |
| Phase 3 | Developer Mode on iPhone + Watch; first device install; 7-day free-signing expiry | Free |
| Phase 3 (if HealthKit signing fails) or Phase 8 | Enrol in Apple Developer Program | US$99/yr |
| Phase 6 | 2-hour battery measurement, then the 10-hour test; recovery test | Time |
| Phase 7 | Real paired devices for WatchConnectivity; watch app launched once | — |
| Phase 9 | App Store Connect record, internal TestFlight, App Privacy, privacy policy URL | Included |
| Phase 11 | Supabase region (before creation); anon key only; account deletion; Sign in with Apple if adding Google login | Free tier |
| Phase 12 | Google Play Console; closed testing; health declarations; real Wear OS device | US$25 one-time |
| Phase 13 | Samsung partner approval for Sensor SDK apps | Application |
| Phase 14 | Garmin developer account; foreground-only constraint; store review | Free |

---

## 6. Risks to watch

| Risk | Mitigation |
|---|---|
| Battery doesn't last 10 hours on the user's watch | Indoor, HR-only session; throttled wrist-down display; battery guard ends cleanly; document per-model expectations |
| Data loss on crash or dead battery | Append-only files flushed every ≤60 s; workout recovery; interrupted finalization on next launch |
| Transfer never arrives / duplicates | Queued `transferFile`, re-queue until acked, idempotent import by id |
| Expo/`@bacons/apple-targets` or Xcode update breaks the watch target | Pin versions; upgrade on a branch; keep watch code free of Expo dependencies |
| Logic drift between Swift / TS / Kotlin / Monkey C | Shared vectors are mandatory tests for every port |
| Over-claiming health capability | Wellness wording; disclaimer on phone and watch |

---

## Appendix — Cursor setup

1. Place `docs/ARCHITECTURE.md` and `docs/IMPLEMENTATION_PLAN.md` in the repo.
2. Place `.cursor/rules/heartthreshold.mdc` in the repo (always applies).
3. Start each phase with its prompt; ask Cursor to list the **Done when** checks it believes pass, and which need a physical device, before you commit.
4. Reject proposals that contradict ARCHITECTURE.md (alert logic in TypeScript, down-sampling on the watch, sending samples one by one, editing `ios/`), and point to the rule.
