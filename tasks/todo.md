# Task: Log redesign · combine tabs · marketing website

## App changes (main agent) — DONE
- [x] A1 — Log page: date ("JUN 8") is now the hero; weekday ("MONDAY") is the small ember eyebrow above it (`SessionRow`).
- [x] A2 — Combined **Exercises + Splits → "Library"** tab with FORGE ember segmented switcher.
  - [x] `Features/Library/LibraryView.swift` (LibraryMode + LibraryView + LibraryModeSwitcher).
  - [x] `ExerciseLibraryView` / `SplitsListView` → embeddable content (own NavigationStack/title removed).
  - [x] `RootView`: Log · Library · Progress · Settings.
  - [x] `trackliftsUITests` tab taps updated (Library + segment ids).
- [x] Build: ** BUILD SUCCEEDED ** (iPhone 17 Pro, iOS 26.2).

## Website (`website/`)
- [x] Brand-locked scaffold: `styles.css` (FORGE tokens + components + phone-mockup atoms), `app.js` (reveal/nav/count-up/parallax), `assets/mark.svg` (ember flame).
- [x] Agent W-A: `index.html` flagship landing (wow hero + features + showcase + CTA).
- [x] Agent W-B: `features.html` + `download.html`.
- [x] Integrate + cohesion/QA pass (fixed dangling hero copy, dup class, empty App Store logos; added branded `assets/og.png`).
- [x] Link integrity: all internal anchors/links resolve; every page wired to styles.css/app.js/og.png/nav/footer.

## Review
**App** — both changes shipped and compile (BUILD SUCCEEDED, iPhone 17 Pro / iOS 26.2):
- Log rows now lead with the **date** (`.display(28)` "JUN 8") and a small ember weekday eyebrow above — the date is the hero.
- Exercises + Splits merged into a single **Library** tab (`LibraryView`) with a custom FORGE ember segmented switcher (matched-geometry slide). Each half kept all functionality (search, favorites, custom/bodyweight, splits build/reorder/bulk-favorite). RootView is now Log · Library · Progress · Settings. UITests updated to tap Library + `librarySegment.*`.

**Website** (`website/`) — spectacular 3-page marketing site in the app's FORGE language:
- `styles.css` (FORGE tokens + components + in-browser phone-mockup atoms), `app.js` (scroll reveal, sticky nav, count-ups, parallax, mobile menu), `assets/mark.svg` (ember flame), `assets/og.png` (branded social card, rendered via rsvg-convert + bundled Bebas/Archivo).
- `index.html`: cinematic hero (ember sparks + glow + floating Log-screen phone with the new date-hero rows), count-up stat band, 4 alternating feature sections (incl. the new combined Library segmented tab + Progress charts + pulsing New PR!), feature grid, how-it-works, 3-device showcase, CTA.
- `features.html`: deep numbered tour + spec band + FAQ accordions. `download.html`: conversion hero + requirement tiles + steps.
- Built by 2 parallel agents against the brand-locked scaffold; QA'd for cohesion + link integrity.

To preview: open `website/index.html` (needs internet for Google Fonts).
