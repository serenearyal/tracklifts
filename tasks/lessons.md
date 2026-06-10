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
