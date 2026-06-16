# Security Assessment — TrackLifts (iOS)

_Date: 2026-06-15 · Scope: entire repository (app target, `tools/`, build config, `website/`) · Method: static review only_

> **Remediation update — 2026-06-16:** 7 of 10 findings remediated in code and verified by a clean build (**H-1**, **M-1** partial, **L-1**, **L-2**, **L-3**, **L-4**, **L-5**). Three remain open and need owner action/testing: **M-2** (data-protection entitlement — needs on-device verification that CloudKit still syncs while the device is locked), **L-6** (dev-only import tool — streaming rewrite can't be verified against the full USDA dataset), **L-7** (dedup TOCTOU — needs a concurrent-import stress test). Per-finding status is noted on each entry and in the §4 table.

## 1. Executive summary

TrackLifts is a **native SwiftUI/SwiftData iOS app** (gym + nutrition tracker) with a local-first, privacy-conscious architecture: data lives on-device in SwiftData, syncs only through the user's **private CloudKit** database, and there is **no app-owned backend, no login, and zero third-party/SPM dependencies**. That design eliminates entire vulnerability classes by construction — there are no server endpoints to attack, no session/cookie/CSRF surface, no SQL string-building, and no supply chain. The companion `website/` is a static marketing site with no inputs.

The real attack surface is narrow and well-defined: **two outbound HTTPS integrations** — Google Gemini (cloud meal-photo recognition) and Open Food Facts (community-editable food database) — plus on-device capture (camera/mic/photo) and CloudKit/KVS data the app reads back and trusts. The team's security hygiene is generally strong: explicit cloud opt-in with clear disclosure, on-device speech, image downsizing to cap cost, no secrets in git history, no PII/secret logging, and Release builds free of test hooks.

The dominant theme of the findings is **insufficient validation of values crossing the trust boundary from third parties** — numbers from Gemini and (especially) the community-editable Open Food Facts are persisted and rendered without bounds-checking, which produces a confirmed, durable crash (denial of service) and corrupted nutrition/health totals.

**Counts (Confirmed/Firm, excluding Tentative):**

| Severity | Count |
|---|---|
| Critical | 0 |
| High | 1 |
| Medium | 2 |
| Low | 7 |
| Informational / Hardening | several |

**Top risks in plain language:**

1. **A single bad food record crashes the app (High).** A nutrient value from Open Food Facts or Gemini that is huge/negative/out-of-range is stored and later force-converted with `Int(Double)`, which *traps* (crashes) in Swift. Because OFF is editable by anyone and the bad value is persisted and CloudKit-synced, this is a durable, self-replicating denial of service — the diary view crashes on open with no easy way to delete the offending entry.
2. **The Gemini API key ships inside the app and rides in the URL (Medium).** Acceptable for the current dev posture (key is gitignored, not in the binary for simulator runs), but as written a shipped build would leak an extractable, billable credential — which the code's own comment acknowledges.
3. **Health/diet data at rest uses the default file-protection class, not the strongest (Medium).** Bodyweight and full dietary history are recoverable from a jailbroken/imaged device after first unlock.

---

## 2. Scope & methodology

**Scope:** The entire tracked repository — the iOS app target (`tracklifts/`), the standalone `tools/usda-import.swift` data tool, build configuration (`tracklifts.xcodeproj/project.pbxproj`, entitlements), and the static `website/`.

**Methodology:** Recon + threat model, then a fan-out of parallel review passes (injection/taint + availability; persistence/cloud/config; capture/permissions/privacy) consolidated and **independently re-verified firsthand** for every High/Medium claim. Taint was traced from each source (Gemini JSON, OFF JSON, scanned barcodes, meal text, KVS, photo bytes) to its sinks (SwiftData predicates, URL construction, `Int()` conversions, nutrition math, HealthKit). **All git history** was scanned for leaked keys, and the `.gitignore`/secret-bundling story was reviewed.

**Limits:** This is **static review only** — no runtime/DAST, no live API fuzzing, no on-device forensic test of the file-protection class, and no execution of the (device-only) camera/mic paths. Dependency-CVE analysis was trivial (zero third-party dependencies). CloudKit server-side ACL behavior is assumed per Apple's documented private-database model and was not exercised live.

**Coverage note:** Several OWASP categories are **not applicable by architecture** and are stated as such in §5 rather than omitted: server-side AuthN, traditional AuthZ/IDOR, CSRF/CORS/cookies, SSTI, deserialization-RCE, rate limiting, and supply chain.

---

## 3. Findings

### H-1 — Unvalidated nutrient magnitudes from Open Food Facts / Gemini cause a durable crash (DoS) and corrupt totals

**Status — ✅ Fixed (2026-06-16):** Clamped at ingress — `mapNutriments` drops non-finite/negative values and caps magnitude, OFF serving weight is bounded, `estimate` bounds Gemini grams/kcal and sanitizes every macro, and `fromPerServing` got a central finite-and-cap backstop. Additionally, all 13 nutrient `Int(...)` display sinks now route through a new saturating `Double.safeInt` (NaN/Inf/overflow → safe number, never a trap), which also retroactively de-fangs any already-synced bad record. Build green.

- **Severity:** High **Confidence:** Confirmed (crash mechanism); reachability via OFF poisoning is Firm
- **CWE:** CWE-20 (Improper Input Validation), CWE-681 (Incorrect Numeric Conversion), CWE-1284 (Improper Validation of Quantity), CWE-400 (Uncontrolled Resource Consumption) — OWASP A03/A04
- **Location (sources):** `tracklifts/Data/OpenFoodFacts.swift:98-129` (`mapNutriments`), `tracklifts/Data/FoodVisionProvider.swift:150-163` (`estimate`); **carrier:** `tracklifts/Models/Nutrition.swift:136-139` (`fromPerServing` — no finite/bound check); **persistence:** `tracklifts/Features/Food/FoodSearchView.swift:425-440` (`upsert`, assigns `per100g` with no clamp); **sinks (≈14):** `FoodSearchView.swift:374` (search-result row), `:451`, `:479-485`; `CaptureConfirmSheet.swift:79`; `FoodDiaryView.swift:179,370,416`; `RecipeEditorView.swift:141`.

**Description.** Open Food Facts is a **community-editable** database — anyone can edit a product's `energy-kcal_100g` (and other nutriments) with no authentication. `mapNutriments` copies those numbers straight into a `NutrientVector` (`OpenFoodFacts.swift:104`: `v[Nutrient.energy.rawValue] = kcal`), with no upper bound, no negativity check, and no finiteness check. The same is true of Gemini's returned per-item nutrition in `estimate(...)`, which only guards `grams > 0 && kcal > 0`. `NutrientVector.fromPerServing` and the `+`/`scaled(by:)` operators (`Nutrition.swift:112-120,136-139`) propagate these values unmodified, and finite-but-huge values (e.g. `1e308 × 100`) overflow to `+Infinity`.

The values are then rendered with `Int(<double>.rounded())` in ~14 places. **In Swift, `Int(_:)` of a value greater than `Int.max` (≈9.22e18), or of `±Infinity`, is a runtime trap — i.e. a hard crash**, not a recoverable error.

**Impact.**

- **Immediate (no persistence required):** `FoodSearchView.swift:374` renders `Int(r.per100g.energy.rounded())` for *every* Open Food Facts search result. A poisoned/erroneous OFF record (energy ≥ ~1e19) attached to a common food name crashes the **search list** the instant results appear.
- **Durable & self-replicating:** if the user taps to log such a food, `upsert` (`FoodSearchView.swift:425`) persists the unclamped vector as a `FoodItem`, and the resulting `DiaryEntry` snapshot carries the poisoned value. `FoodDiaryView.swift:179` (daily total) and `:416` (entry row) then trap **on every open of that day's diary** — and because the entry is mirrored through CloudKit, the poison record propagates to the user's other devices. Recovery is hard: the view that would let you swipe-to-delete the entry crashes before it renders.
- **Data integrity / HealthKit amplification:** negative values (e.g. `protein: -50`) are accepted verbatim, silently corrupting daily totals and rolling averages, and are written out to Apple Health on day-sync.

**Proof of concept / exploit path.**

1. On Open Food Facts, edit (or create) a product named e.g. "chicken breast" and set `energy-kcal_100g` to `99999999999999999999` (≈1e20, > `Int.max`). No login barrier prevents typical edits.
2. Victim opens TrackLifts → Food search → types "chicken". The poisoned product returns in the top 25; the results list renders `Int(1e20.rounded())` → **crash**. (A genuine OFF data-entry error of the same shape triggers it identically — OFF data quality is famously noisy, so the bug is reachable without an attacker.)
3. If the victim had instead logged it, the diary for that day now crashes on open and the crash syncs to their iPad.

**Remediation.** Sanitize at the trust boundary — reject or clamp before storing, and make the display conversions total:

- In `mapNutriments` and `estimate(...)`, drop any value that is not finite and within a sane per-nutrient domain, e.g.:
  ```swift
  func clean(_ v: Double?) -> Double? {
      guard let v, v.isFinite, v >= 0, v <= 100_000 else { return nil }   // per-100g ceiling
      return v
  }
  ```
  Apply to energy/macros/sodium; for `estimate`, also bound `grams` (e.g. `0 < grams <= 5_000`) and return `nil` to fall back to a plain "no match" when out of range.
- Add a defensive `.isFinite` filter inside `NutrientVector.fromPerServing`/`+` as a backstop.
- Replace every `Int(x.rounded())` on nutrient-derived doubles with a saturating helper, e.g. `func intClamped(_ x: Double) -> Int { x.isFinite ? Int(x.rounded().clamped(to: Double(Int.min)...Double(Int.max))) : 0 }`, so a future unclamped path degrades to a wrong-but-safe number instead of a crash.

---

### M-1 — Gemini API key bundled into the app and passed in the URL query string

**Status — ◑ Partially fixed (2026-06-16):** The key now travels in the `x-goog-api-key` header instead of the URL query string, so it can't leak into proxy/server URL logs. **Still open:** the key is still bundled in the app — a backend proxy (App Attest / DeviceCheck) so no key ships in the binary requires infrastructure the owner must stand up.

- **Severity:** Medium **Confidence:** Confirmed
- **CWE:** CWE-798 (Hard-coded Credential), CWE-522 (Insufficiently Protected Credentials), CWE-598 (Sensitive Data in Query String) — OWASP A05/A07
- **Location:** `tracklifts/Data/FoodVisionProvider.swift:50-58` (key read from bundled `Secrets.plist`), `:104` (`...:generateContent?key=\(key)`); bundling via the synchronized root group in `project.pbxproj`.

**Description.** For a real (non-simulator) build the key is read from `Secrets.plist`, which the Xcode synchronized file group copies **into the app bundle**, making the credential extractable from the IPA. It is then placed in the request **URL** (`?key=`) rather than a header — the weakest placement Google offers, prone to landing in proxy/URL logs. The file's own header comment states "A shipped build should proxy through a backend instead," confirming the current form is dev-only.

**Impact.** Anyone who installs a shipped build can extract the key and spend the developer's Gemini quota (financial/wallet abuse); query-string placement widens log exposure.

**Mitigating context (why Medium, not High):** no real key is in git — `Secrets.plist` and the scheme env var are correctly `.gitignore`'d, and **a full git-history scan found no leaked `AIza…` key**. For simulator runs the key comes from a scheme env var, never the binary. This finding is about the *shipping* posture.

**Remediation.** For any distribution, proxy Gemini through a small backend that holds the key server-side and authenticates the app via **App Attest / DeviceCheck**, so no key ships in the binary. If a direct call must remain temporarily, at minimum move the key from the query string to the `x-goog-api-key` header and ensure `Secrets.plist` is excluded from the Release bundle.

---

### M-2 — Health/diet data at rest uses the default file-protection class

**Status — ⏳ Deferred (owner action + on-device test):** Not auto-applied. Adding `NSFileProtectionComplete` can block CloudKit background sync while the device is locked; it must be verified on a real device that sync still works (`completeUnlessOpen` is the usual compromise). Left for the owner to apply and test to avoid silently breaking sync.

- **Severity:** Medium **Confidence:** Firm
- **CWE:** CWE-311 (Missing Encryption of Sensitive Data), CWE-312 (Cleartext Storage) — OWASP A02
- **Location:** `tracklifts/Shared/CloudSync.swift:70-89` (`ModelConfiguration` created with no protection option); reinforced by absence project-wide (no `NSPersistentStoreFileProtectionKey` / `default-data-protection` entitlement anywhere).

**Description.** The SwiftData `ModelContainer` is built from a bare `ModelConfiguration(schema:cloudKitDatabase:)` with no Data Protection class set, so the on-disk SQLite store inherits the app default (effectively `NSFileProtectionCompleteUntilFirstUserAuthentication`) rather than `…Complete`. The store holds sensitive, HealthKit-adjacent data: `BodyWeightEntry` (bodyweight time series), the full food diary (`DiaryEntry`/`FoodItem`), and `WaterEntry`. After the first unlock following boot, that file is readable at rest by anyone with filesystem/backup access to a jailbroken or forensically imaged device.

**Impact.** Recoverable dietary and bodyweight history — a special category of personal data — at rest, weaker than users reasonably expect for health data.

**Remediation.** Apply the strongest protection compatible with background CloudKit sync. Add `com.apple.developer.default-data-protection = NSFileProtectionComplete` to `tracklifts.entitlements`, or set `NSPersistentStoreFileProtectionKey: FileProtectionType.completeUnlessOpen` on the underlying store description (`completeUnlessOpen` is the usual compromise so a locked device can still sync). Verify mirroring still works after the change.

---

### L-1 — CloudPrefs adopts unvalidated NSUbiquitousKeyValueStore values into profile/goals

**Status — ✅ Fixed (2026-06-16):** New `CloudPrefs.sanitized(_:)` rejects non-finite / overflow KVS scalars before they're written into local defaults, on both the fresh-install and steady-state paths. (Full per-key domain validation — age 0–130, etc. — remains as a further hardening, but the NaN/Inf/overflow corruption vector is closed.)

- **Severity:** Low **Confidence:** Firm
- **CWE:** CWE-349 (Acceptance of Extraneous Untrusted Data), CWE-20 — OWASP A08
- **Location:** `tracklifts/Shared/CloudPrefs.swift:69-95` (`adoptRemoteIfFreshInstall`/`applyRemote`, `defaults.set(remote, forKey:)`).

**Description.** Values read back from iCloud key-value store are copied straight into `UserDefaults` with no type or range validation (only a `valuesEqual` gate). The mirrored keys drive onboarding state and TDEE/goal math (sex, age, height, bodyweight-derived goals, nutrition/water targets, units). A corrupted, rolled-back, or hostile KVS payload (plist scalars) becomes the user's profile on a fresh install. `didOnboard` is handled monotonically (good), but the scalars are not bounded.

**Impact.** Out-of-range or wrong-typed preferences silently become the user's goals/demographics (e.g. negative targets, absurd age feeding energy math). No memory-safety impact.

**Remediation.** Validate each key on read: confirm expected type and clamp to a sane domain (age 0–130; height/weight/targets positive and bounded; unit raw values in the known enum set) before `defaults.set`; skip values that fail.

---

### L-2 — Speech recognition silently falls back to server-based when on-device is unsupported

**Status — ✅ Fixed (2026-06-16):** `start()` now refuses with `.unavailable` when `supportsOnDeviceRecognition` is false, and the request unconditionally sets `requiresOnDeviceRecognition = true`. Behavior change (intended): voice capture is unavailable — rather than server-based — on devices/locales without on-device support, honoring the stated on-device promise.

- **Severity:** Low **Confidence:** Firm
- **CWE:** CWE-359 (Exposure of Private Information) — OWASP A04
- **Location:** `tracklifts/Features/Capture/SpeechCapture.swift:81`.

**Description.** `if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }` has no `else`. When on-device recognition is unavailable for the device/locale, `requiresOnDeviceRecognition` stays `false` and `SFSpeechRecognizer` sends audio to Apple's servers — contradicting the Info.plist promise ("transcribes your speech **on-device**"). In practice `en-US` supports on-device on modern hardware, so this rarely fires; no audio ever goes to a third party or the app's own backend.

**Impact.** On an edge device/locale, spoken-meal audio could leave the device to Apple despite the on-device claim.

**Remediation.** Make on-device mandatory to honor the stated invariant: `guard recognizer.supportsOnDeviceRecognition else { status = .unavailable; return }` before enabling the request.

---

### L-3 — EXIF/GPS stripping before upload is incidental to the resize redraw (regression-prone)

**Status — ✅ Fixed (2026-06-16):** Added a load-bearing SECURITY comment on `prepareJPEG` documenting that the unconditional redraw is what strips EXIF/GPS and must not be shortcut. (Runtime behavior was already safe; this prevents a future regression.)

- **Severity:** Low **Confidence:** Firm
- **CWE:** CWE-212 (Improper Removal of Sensitive Information Before Transfer) — OWASP A04
- **Location:** `tracklifts/Features/Capture/CaptureView.swift:317-326` (`prepareJPEG`).

**Description.** Meal photos are re-rendered through `UIGraphicsImageRenderer` and re-encoded with `jpegData(...)`, which produces a JPEG with **no inherited EXIF/GPS** — the metadata lives on the original asset, not the redrawn pixel buffer. So today no location data reaches Gemini. The risk is that this privacy property is an *undocumented side effect* of always redrawing; a future "skip resize when already small, send original `Data`" optimization would silently leak GPS.

**Impact.** None currently; regression-only exposure of photo geolocation to a third party.

**Remediation.** Keep the unconditional re-render and add a comment marking it load-bearing for metadata stripping; ideally add a test asserting the output has no GPS dictionary, or strip explicitly via `CGImageDestination` with the GPS/EXIF dictionaries removed.

---

### L-4 — Scanned barcode interpolated into a URL path with a force-unwrap

**Status — ✅ Fixed (2026-06-16):** Both `URLComponents(string:)!` force-unwraps in `OpenFoodFacts` (barcode `lookup` and text `search`) replaced with `guard let … else { return … }`.

- **Severity:** Low **Confidence:** Firm
- **CWE:** CWE-20, CWE-74 (Injection into URL path) — OWASP A03
- **Location:** `tracklifts/Data/OpenFoodFacts.swift:25` (`URLComponents(string: "\(host)/api/v2/product/\(gtin).json")!`).

**Description.** The scanned barcode (attacker-printable as arbitrary text in code128/code39) is reduced to digits with `barcode.filter(\.isNumber)` and `guard gtin.count >= 8` *before* interpolation, so today no path-breaking characters survive and the `!` cannot fail — **not currently exploitable**. It is flagged because the safety is an emergent property of the digit filter, not a local invariant: a future relaxation of the filter or reuse with a less-sanitized source would expose path injection / a force-unwrap crash. (The text-search path at `:34-42` correctly uses `URLQueryItem` percent-encoding — clean.)

**Remediation.** Build the path on a `URLComponents` object and guard the optional (`guard let url = comps.url else { return nil }`) instead of `!`; optionally cap `gtin.count` to GTIN-14 length.

---

### L-5 — Missing input/response size caps (meal text, OFF query, HTTP body)

**Status — ✅ Fixed (2026-06-16):** Meal-text parse capped at 2,000 chars (`MealTextParser.parse`); OFF query capped at 100 chars (`OpenFoodFactsProvider.search`). The HTTP response-size ceiling (the Tentative sub-part) was not added — low value over HTTPS to a fixed host.

- **Severity:** Low **Confidence:** Firm (input caps); Tentative (response-size cap)
- **CWE:** CWE-770 (Allocation Without Limits), CWE-400 — OWASP A04
- **Location:** `tracklifts/Features/Capture/CaptureView.swift:177` (`TextEditor`, no max length) → `MealTextParser.parse`; `tracklifts/Data/OpenFoodFacts.swift:31-45` (no `search_terms` length cap), `:49-63` (`URLSession.data` buffers the full response with no byte ceiling).

**Description.** The free-text meal field and OFF query have no maximum length; a multi-megabyte paste runs the (linear but allocating) parser on the main actor and can be sent as a giant query string. `get(...)` buffers the entire HTTP response into memory with only a 12-second timeout — a compromised/oversized response is unbounded in size (though TLS + the constant OFF host make this Tentative).

**Impact.** Main-thread jank / transient memory pressure; no crash, no recursion. (Result-count caps *are* correctly applied elsewhere — `fetchLimit`, `page_size=25`, match cap 8.)

**Remediation.** `text.prefix(2_000)` before `parse`; `q.prefix(100)` before building the OFF request; optionally enforce a response-size ceiling.

---

### L-6 — `usda-import.swift` dev tool: unbounded CSV memory + unvalidated output path

**Status — ⏳ Deferred:** Dev-only tool with no production impact. A streaming rewrite can't be verified against the full multi-GB USDA dataset (only the tiny fixture is in-repo), so it was not auto-applied.

- **Severity:** Low **Confidence:** Confirmed (severity capped — developer-only tool)
- **CWE:** CWE-789 (Excessive Allocation), CWE-400, CWE-22 (Path Traversal)
- **Location:** `tools/usda-import.swift:96-101` (`String(contentsOfFile:)` slurps the whole CSV, then materializes every line + a per-line `[Character]`), `:134,205-211` (`--output` used verbatim as a write target; `--input` concatenated into read paths).

**Description.** On the real (non-fixture) FoodData Central download — hundreds of MB / millions of rows — the tool buffers the entire file and re-copies each line, which can balloon to multiple GB and OOM the script. Separately, `--output`/`--input` are used as filesystem paths with no normalization or confinement (a `../../` argument writes/reads outside the project). No shell is invoked (no command injection) and output is `JSONEncoder` (no CSV-injection sink). This is a build-time tool driven by the developer, so production exposure is nil.

**Remediation.** Stream the CSV line-by-line and parse over `Substring` (drop the `[Character]` rebuild); resolve and confine `--input`/`--output` to an expected subtree, or document that the tool trusts its invoker.

---

### L-7 — CloudDedup count-guard TOCTOU vs. background CloudKit import

**Status — ⏳ Deferred:** Tentative confidence, and the fix touches delete logic — a safe change needs a concurrent-import stress test to confirm it doesn't merge distinct records. Not auto-applied.

- **Severity:** Low **Confidence:** Tentative
- **CWE:** CWE-367 (TOCTOU Race Condition) — OWASP A04
- **Location:** `tracklifts/Data/CloudDedup.swift:99-125` (`dedupeFoods`: `fetchCount` at `:106`, guard `:107`, fetch `:108`, `lastFoodSeedCount = count - deleted` at `:124`); same shape in `dedupeExercises` `:76-97`.

**Description.** The COUNT and the subsequent fetch are two separate reads of a store that `NSPersistentCloudKitContainer` mutates on a background queue between them. A concurrent import landing mid-pass means the survivor bookkeeping is computed from a stale count, and for the name-keyed branch (`:113`, foods with `fdcId == 0`) two genuinely distinct same-name foods could be merged. Several factors lower severity: the whole class is `@MainActor` (no in-process data race); the canonical pick is deterministic (oldest `createdAt`); referrers are re-pointed before delete; and diary entries snapshot their own nutrients, so logged history is never orphaned. An 8s debounce plus 5s/30s floors further shrink the window.

**Impact.** Edge-case wrongful merge of two distinct name-collided seed foods (favorite flag + diary re-pointing). Logged nutrition totals are preserved regardless.

**Remediation.** Drop the COUNT-then-fetch micro-optimization in favor of a single fetch per pass, or recompute `lastFoodSeedCount` from a re-COUNT taken *after* the dedup `save()`; for the name-keyed branch, additionally require matching nutrient vectors before collapsing.

---

## 4. Summary table

| ID | Title | Severity | Confidence | Status | Location |
|---|---|---|---|---|---|
| H-1 | Unvalidated OFF/Gemini nutrient magnitudes → `Int()` trap crash + corrupted totals | High | Confirmed | ✅ Fixed | `OpenFoodFacts.swift:104`, `Nutrition.swift:136`, `FoodSearchView.swift:374,425` |
| M-1 | Gemini API key bundled in app + in URL query string | Medium | Confirmed | ◑ Partial | `FoodVisionProvider.swift:50-58,104` |
| M-2 | Health/diet data at rest uses default file-protection class | Medium | Firm | ⏳ Deferred | `CloudSync.swift:70-89` |
| L-1 | CloudPrefs adopts unvalidated iCloud KVS values into profile/goals | Low | Firm | ✅ Fixed | `CloudPrefs.swift:69-95` |
| L-2 | Speech falls back to server recognition, breaking "on-device" promise | Low | Firm | ✅ Fixed | `SpeechCapture.swift:81` |
| L-3 | EXIF/GPS stripping is incidental to resize redraw (regression-prone) | Low | Firm | ✅ Fixed | `CaptureView.swift:317-326` |
| L-4 | Barcode interpolated into URL path with force-unwrap | Low | Firm | ✅ Fixed | `OpenFoodFacts.swift:25` |
| L-5 | Missing input/response size caps (meal text, OFF query, HTTP body) | Low | Firm/Tentative | ✅ Fixed | `CaptureView.swift:177`, `OpenFoodFacts.swift:31-63` |
| L-6 | `usda-import.swift`: unbounded CSV memory + unvalidated output path | Low | Confirmed | ⏳ Deferred | `tools/usda-import.swift:96-101,205-211` |
| L-7 | CloudDedup count-guard TOCTOU vs. background CloudKit import | Low | Tentative | ⏳ Deferred | `CloudDedup.swift:99-125` |

---

## 5. Hardening & defense-in-depth

- **Website CSP/headers (Informational):** `website/*.html` ships no `Content-Security-Policy`, `X-Frame-Options`, or `Referrer-Policy`. There is no XSS/redirect risk (no inputs; `app.js` uses only `textContent` and parsed floats — no `innerHTML`; all external links are `href="#"` placeholders with no `target="_blank"`), so this is pure defense-in-depth — add a restrictive CSP and clickjacking protection at the hosting layer. The "Privacy" footer link is a dead `#` and should point at a real policy before launch.
- **Gemini URL force-unwrap (Informational):** `FoodVisionProvider.swift:104` force-unwraps the constructed URL; build it via `URLComponents` and fail gracefully if `nil`.
- **Prompt robustness (quality, not security):** the photo-note is folded in as "authoritative" (`FoodVisionProvider.swift:91`); only the user's own results are affected, but keeping the JSON-only reaffirmation last (as it already does) is the right call.
- **Recipe nesting correctness:** recipe-derived foods can be added as ingredients of other recipes (`RecipeEditorView`), and aggregation reads a stale snapshot — a correctness nit (not recursion/DoS). Consider excluding `source == .recipe` from the ingredient picker.
- **Belt-and-suspenders upload cap:** also cap `httpBody.count` for the Gemini request as a byte ceiling alongside the existing 1024px/q0.8 dimension cap.

---

## 6. Residual risk & follow-ups

- **Areas examined and found clean / not applicable** (stated explicitly per the engagement): **SQL/Predicate injection** — all SwiftData queries use parameterized `#Predicate`, no string-built SQL (clean); **XSS/output handling** — static site, `textContent` only (clean); **ReDoS** — the single meal-text regex is linear, no catastrophic backtracking (clean); **deserialization/RCE** — `JSONDecoder` only, no `eval`/`NSExpression(format:)`/dynamic loading (clean); **cryptography** — no custom crypto; relies on platform TLS with **no ATS exceptions** (all endpoints HTTPS) plus CloudKit encryption (clean); **secrets in VCS** — full-history scan found no leaked key (clean); **logging** — no PII/secret/token logging; only static container ID + CloudKit error strings logged `public` (clean); **HealthKit** — disjoint read/write sets, authorization checked, never logged or sent off-device (clean); **AuthN/AuthZ/multi-tenant** — no accounts; identity and tenant isolation are delegated to the user's **private CloudKit** database per Apple ID (no public/shared DB anywhere) (N/A by design); **CSRF/CORS/cookies/rate-limiting** — no app-owned server, no cookies/sessions (N/A); **supply chain** — **zero third-party/SPM/remote packages** and **no CI/CD, Docker, or IaC files** (N/A); **Release build hardening** — `ENABLE_TESTABILITY`/`DEBUG`/assertions are Debug-only, Release uses whole-module + dSYM, script sandboxing on (clean); **cloud-photo consent** — explicit opt-in defaulting OFF with a clear "sent to Google Gemini" disclosure (clean); **image cost cap** — JPEG downsized to ≤1024px @ q0.8 on the sole upload path (clean).
- **Needs dynamic/out-of-band verification:** (a) the **file-protection class (M-2)** should be confirmed on a real device with a forensic-style at-rest read after fixing; (b) **CloudKit private-database ACLs** were assumed per Apple's model, not exercised live; (c) the **CloudDedup TOCTOU (L-7)** is best confirmed by a stress test that forces a CloudKit import to land mid-dedup; (d) **device-only capture paths** (camera/mic) could not be executed in static review.
- **Priority order for remediation:** fix **H-1** first (validate/clamp at the OFF and Gemini boundaries + saturating `Int()` helper — it is the only finding that crashes the app and self-replicates via CloudKit), then **M-2** (file protection) and **M-1** (don't ship the embedded key — proxy it) before any public release.
