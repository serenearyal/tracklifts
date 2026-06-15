# Lessons

## 2026-06-10 — CloudKit + SwiftData: relationships must be *Optional*, defaults are not enough

**What happened:** Shipped CloudKit sync believing "all properties need defaults,
relationships need inverses" was the full compliance rule. On device (and sim),
`ModelContainer(cloudKitDatabase: .private)` threw the opaque
`SwiftDataError error 1` on every launch, the silent local fallback masked it,
and the user lost data on delete+reinstall because nothing had ever uploaded.
The real CoreData error (134060, visible only in the unified log) named the rule:
**CloudKit requires every relationship to be Optional** — including to-many
arrays like `var days: [SplitDay] = []`. Defaults don't satisfy it.

**Rules for next time:**
1. **Boot the exact cloud configuration before calling sync "done."** A
   `build`/`test` pass proves nothing about `ModelContainer` runtime validation.
   One `simctl launch` + `log show --predicate 'subsystem == "serene.tracklifts"'`
   would have caught this pre-ship (it's how it was caught post-ship).
2. **Never ship a silent fallback.** The `.none` fallback was right to keep the
   app launching, but it shipped without surfacing *why* — account status looked
   "available" while sync was dead. Any degraded mode needs a visible state +
   logged reason from day one (now: `CloudSync.mode` + `CloudSyncMonitor`).
3. **SwiftDataError descriptions are useless** ("error 1"). Always log
   `String(describing:)` + walk `NSUnderlyingErrorKey`, and read the CoreData
   lines in the unified log — that's where the actual reason lives.
4. The full CloudKit/SwiftData checklist for this repo: defaults on every
   property, **every relationship Optional**, inverse on every relationship,
   no `#Unique`, no `.deny`; access arrays via the `orderedX` / `xCount`
   computed accessors, never the raw optionals.

## 2026-06-10 — "Scroll the focused field up" means the *card*, not the bare field

**What happened:** Asked to make a focused numeric field rise above the keyboard,
I scrolled the focused field itself to `anchor: .top`. In the workout logger that
pinned the *set row* to the very top, hiding the exercise-name header above it —
so the user couldn't tell which exercise they were editing. Correction: scroll the
enclosing **context container** (the exercise card / section) to the top, with the
focused field below it but still clear of the keyboard.

**Rule:** When lifting a focused control for keyboard avoidance, scroll the
smallest unit that still answers "what am I editing?" — usually the card/section,
not the field. Map the field's focus identity back to its parent's scroll id
(here `LogWorkoutView.focusedEntryID` maps the focused set → its `LoggedExercise`
section id) and scroll to that. The reusable helper is
`ScrollViewProxy.scrollFieldToTop(_:)` in `Shared/KeyboardSupport.swift`.

**Follow-up bug:** to leave breathing room below the top edge I switched the helper
to a fractional `scrollTo(id, anchor: UnitPoint(y: 0.1))` — and scrolling stopped
working entirely. **Fractional `UnitPoint` anchors silently no-op in `List`; only
`.top` / `.center` / `.bottom` are reliable there.**

**Resolved by driving the simulator (the user told me to stop guessing and test it):**
a UI test (`testKeyboardScrollPosition`) seeds a session, focuses set fields, and
screenshots. The screenshots showed `scrollTo(.top)` parking the exercise *title under
the transparent nav bar* (the real "blur"), and that `.contentMargins(.top:)` does NOT
move where `scrollTo` lands (70 vs 115 were pixel-identical). The fix: scroll the card
with **`anchor: .center`** — title lands crisp below the bar. Lesson: for these
position-tuning bugs, a build proves nothing; capture a screenshot via XCUITest +
`xcresulttool export attachments` and actually look. (Also: the exercise picker is a
lazy `List`, so off-screen rows/fields aren't queryable — seed data and open an existing
session instead of driving the picker.)

## 2026-06-15 — Don't trust fuzzy DB name-matching for AI-proposed foods; cross-check density

**What happened:** A photographed coffee logged as "Alcoholic beverage, liqueur,
coffee". The note→Gemini path was fine; `CaptureMatcher` was catalog-first and took
`FoodSearch.run(name, limit: 8).first` with no confidence check. USDA names defeat that
three ways at once: no entry's name starts with "coffee" (every hit ties at word-prefix
rank, broken *alphabetically* → "Alcoholic…" wins), the limit-8 fetch is sorted
alphabetically *before* ranking so the real coffee rows are cut off, and because *a* hit
existed it discarded the model's own coffee estimate. I checked the catalog directly:
"smarter ranking" doesn't save it — relevance ranking confidently returns "SILK Coffee,
soymilk" for coffee and "Rice flour, white" for white rice.

**Rule:** When an LLM proposes a food *and its own nutrition*, treat the AI estimate as
the default and only upgrade to a catalog row on a **confident** match — name coverage
(every query token present, query accounts for ≥ half the catalog name's tokens) AND an
**energy-density sanity check** (catalog kcal/100 g within ~2× of the estimate). Density
is the signal string-matching lacks (liqueur 336 vs coffee ~50 kcal/100 g). Bias to
false-negatives: falling back to the estimate is safe; a categorically-wrong match
(alcohol for coffee) is not. The gate (`CaptureMatcher.confidentMatch`) makes the matcher
correct *regardless* of `FoodSearch` ranking, so don't "simplify" it back to catalog-first.

## 2026-06-15 — SwiftUI keyboard avoidance doesn't reach a custom overlay stacked over a sheet

**What happened:** The photo-review note card lives in a full-screen `ZStack` overlay
(`zIndex 2`) layered over the capture sheet's `NavigationStack`/`ScrollView`. I planned to
"anchor the card low and let default keyboard avoidance lift it" — it didn't move at all,
so on re-scan the focused field + Analyze button sat *under* the keyboard. SwiftUI's
automatic avoidance only insets the **one primary scroll container** (the ScrollView
underneath); a sibling overlay layer gets nothing. `.keyboardDoneBar()` (a `.keyboard`
toolbar) attaches fine but does not move the content.

**Rule:** For text entry inside a custom full-screen overlay/ZStack (not a plain sheet or
ScrollView), don't rely on automatic avoidance — drive it yourself: observe
`keyboardWillShow/Hide` for the frame-end height and `.padding(.bottom, height)` the
content, plus `.ignoresSafeArea(.keyboard, edges: .bottom)` so the system can't also
inset and double-lift. Reusable helper now: `View.keyboardAvoidingPadding()` in
`Shared/KeyboardSupport.swift`. (Note: I couldn't screenshot this exact flow — it needs a
Gemini key + the full photo→results→re-scan path — so per the standing keyboard lesson
this still wants an on-device eyeball.)
