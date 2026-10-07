# On-device test log

Fill this in on a physical Apple Watch. Leave a row blank until that check has actually been run. Simulator results do not count for the checks below.

## Device

| Field | Value |
|---|---|
| Date | |
| Watch model | |
| watchOS | |
| iPhone model | |
| iOS | |
| App version | |
| Build | |

## §12 checks

| Check | Result | Notes |
|---|---|---|
| Health permission request succeeds on the watch | | |
| Live BPM changes while wearing the watch and moving | | |
| Lower the wrist, then raise it: the session continues and BPM updates resume | | |
| Wrist down updates the screen at most once a minute, with no animation; alerts still fire | | |
| One warning on entry, a distinct threshold haptic, no vibration storm, re-arm after hysteresis | | |
| Pause and resume: no alerts while paused; pause is a break, not a gap | | |
| iPhone off or out of range for the whole session; recording arrives after reconnecting | | Phase 7 |
| Force-quit or crash mid-session, then reopen: the session continues and the recording has a `recovered` event | | |
| No workout left to recover: the open recording finalizes as `interrupted` | | |
| Battery guard: start near 15% unplugged; the session ends at 10% with a complete recording and end reason `batteryGuard` | | |
| Stop with Save to Health off: the session ends cleanly and nothing new appears in Fitness | | |
| Start with under 5 MB free: the session does not start, and the watch explains why | | |

## Battery and endurance

Run a 2-hour session before the 10-hour session. Note the drop per hour. A watch rated under 10 hours can still pass if the guard ends it cleanly with a complete recording. Charge to 100% before the long session, leave Low Power Mode off for that run, and test Low Power Mode separately.

| Run | Start battery | End battery | Duration | Sample count | Gap seconds | Guard fired | Notes |
|---|---|---|---|---|---|---|---|
| 2-hour measurement | | | | | | | |
| 10-hour session, or until the guard | | | | | | | |
| Low Power Mode, separate from the reference run | | | | | | | |
