# Task: iCloud sync — CloudKit private DB + KVS prefs + seed dedup

Plan: `~/.claude/plans/enumerated-discovering-newt.md` (2026-06-09)

User data must survive delete/reinstall and sync across devices. No accounts,
no server. SwiftData+CloudKit for the 11 models, NSUbiquitousKeyValueStore for
prefs, idempotent dedup for the seeded catalog.

## Checklist

- [x] 1. Model inverses: `Exercise.splitItems`/`.loggedExercises`, `FoodItem.diaryEntries` (.nullify)
- [x] 2. NEW `Shared/CloudSync.swift`: container id, hermetic detection, `makeContainer()`
- [x] 3. `trackliftsApp.swift`: use `CloudSync.makeContainer()` + `CloudPrefs.shared.start()`
- [x] 4. NEW `tracklifts.entitlements`: iCloud/CloudKit + aps + KVS
- [x] 5. `project.pbxproj`: CODE_SIGN_ENTITLEMENTS + UIBackgroundModes (app target only, 4 lines)
- [x] 6. NEW `Data/CloudDedup.swift`: import-triggered + debounced seed dedup
- [x] 7. NEW `Shared/CloudPrefs.swift`: KVS mirror, monotonic didOnboard
- [x] 8. `ContentView.swift`: CloudDedup.start in .task + scenePhase hook
- [x] 9. `SeedManager.swift`: body-weight seed guard when remote says onboarded
- [x] 10. `SettingsView.swift`: iCloud Sync status card
- [x] 11. NEW `trackliftsTests/CloudSyncTests.swift`: dedup + prefs logic tests
- [x] 12. Docs: roadmap changelog (incl. release-blocking ops steps) + review here
- [x] Build green + logic tests pass

## Review (2026-06-10)

**What shipped**
- `CloudSync.makeContainer()`: `.private("iCloud.serene.tracklifts")` for real launches;
  **in-memory `.none`** for hermetic launches (`--reset-store`/`--seed-sample`/
  `--show-onboarding`/`--local-store`, unit-test host via `XCTestConfigurationFilePath`,
  previews) so test runs can't pollute the real store or export tombstones to iCloud;
  on CloudKit init failure falls back to the on-disk store without sync (never bricks).
- CloudKit-required inverses added (additive → lightweight migration): `Exercise.splitItems`,
  `Exercise.loggedExercises`, `FoodItem.diaryEntries`, all `.nullify` (UI already nil-tolerant).
- `CloudDedup`: collapses duplicate **seed-origin** records after CloudKit merges
  (every fresh install seeds before first import). Deterministic canonical (oldest
  `createdAt`), favorite OR, bodyweight "differs-from-library-default wins", referrers
  re-pointed via the to-one side with inverse arrays snapshotted first (iOS 17 rule).
  Runs at launch, on `NSPersistentCloudKitContainer` import-finished events, and on
  scenePhase-active (debounced 30s/5s).
- `CloudPrefs`: iCloud KVS mirror of 13 prefs (profile ×8, goals ×4, weightUnit) +
  **monotonic `didOnboard`** (true is pushed/adopted; false never propagates — so
  "Recalculate" on one device can't re-onboard the others). Fresh-install adoption
  restores prefs and skips onboarding. Compare-before-write loop guard.
- Settings: iCloud Sync status card (`CKContainer.accountStatus`, refreshes on
  `.CKAccountChanged`); honest copy for signed-out state.
- `seedBodyWeightIfNeeded` skips the legacy-value seed when KVS says the account
  already onboarded (real weigh-ins are en route).

**Verification**
- `build-for-testing` clean, **zero warnings** (fixed a Sendable capture by holding the
  ModelContext in MainActor static state instead of the observer closure).
- `trackliftsTests`: **25/25 pass** — 10 new (4 CloudDedup: merge+re-point, explicit
  bodyweight-unmark wins, diary re-point + portion cascade, idempotency; 6 CloudPrefs:
  adoption, no-adoption-when-onboarded, monotonic didOnboard both directions,
  no-ping-pong, unset-keys-never-pushed) on iPhone 17 / iOS 26.2 sim.
- UI suite not run (convention) — unaffected: hermetic flags cover all 3 launch sites.

**Manual sync test recipe (user)**
1. Sign the sim into iCloud (Settings → Apple ID). Run the app from Xcode (no launch args).
2. Onboard, log a workout + food + weigh-in, favorite an exercise. Background the app;
   `xcrun simctl icloud_sync booted`. Check CloudKit Console → tracklifts container →
   Development → Private DB → zone `com.apple.coredata.cloudkit.zone` for `CD_*` records.
3. Delete the app → reinstall → run: onboarding should be skipped (KVS), targets/unit
   restored, logs stream back; the library may briefly show duplicates, then collapse
   to 69+custom after the import-triggered dedup. Sims get no push: every "wait" =
   background/foreground cycle + `simctl icloud_sync`.
4. Optional two-device: second sim, same Apple ID; edit goalEnergy on one, foreground
   the other. Test on a real device before release.

**Addendum (2026-06-10): first device test lost data — observability added.**
User deleted the app on the phone before the initial CloudKit export had ever
completed (KVS prefs made it up — they're instant — so onboarding was skipped
and targets restored, but the logs never reached iCloud). Root gap: a CloudKit
setup failure or pending first export was invisible — the Settings card only
showed *account* status. Added: `CloudSync.mode` (cloudKit / localFallback(reason)
/ hermetic — fallback no longer silent), `CloudSyncMonitor` (@Observable; records
last export/import/setup event + last error from
`NSPersistentCloudKitContainer.eventChangedNotification`, logs via os.Logger
subsystem `serene.tracklifts` category `cloudsync`), and the Settings card now
shows true health: mode errors in red, "last activity Xm ago", "Waiting for the
first sync…" before the initial upload. **Rule: never delete the app until the
card shows recent sync activity (or CD_* records are visible in CloudKit
Console → Development).**

**Addendum 2 (2026-06-10): root cause of the device failure — fixed.**
The Settings card surfaced `SwiftDataError error 1` on the user's phone.
Reproduced in the sim; unified log showed CoreData 134060: *"CloudKit
integration requires that all relationships be optional"* — non-optional
to-many arrays (`var days: [SplitDay] = []`) fail validation even with
defaults, so the CloudKit container had NEVER come up anywhere (which is the
true cause of the data loss: nothing ever uploaded). Fix: all 8 to-many
relationships now `[T]? = []`; `orderedX` accessors absorb the unwrap; new
`entryCount`/`setCount`/`dayCount`/`itemCount` conveniences; ~20 call sites
updated. `CloudSync` now logs the full underlying error chain (os.Logger
`serene.tracklifts`/`cloudsync`). Verified: sim launch logs **"CloudKit-backed
container up"** (followed only by Cocoa 134400 = sim not signed into iCloud,
expected); 25/25 logic tests pass; zero warnings. Lesson captured in
`tasks/lessons.md`.

**Release blockers (ops, not code)** — also in the roadmap changelog:
- Paid Apple Developer Program on team M9Q5YCJ5NU; build once in Xcode with automatic
  signing to auto-register the `iCloud.serene.tracklifts` container.
- CloudKit Console: deploy schema Development → Production **before** TestFlight/App
  Store; re-deploy after future model changes (keep them additive).
