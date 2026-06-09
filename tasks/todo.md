# Task: Onboarding — targets, timeframe/pace, layout, debug, goals, tickers

Plan: `~/.claude/plans/velvety-puzzling-hamming.md`

## Round 1 — sane targets, pace step, debug button (DONE)
- [x] `NutritionPlan`: clamp inputs, sex-aware floor, rate-derived `energyDelta`, pace model
- [x] Onboarding: Target & pace step, prefill, weight guard, hero-number scale fix
- [x] Settings: `#if DEBUG` Restart Onboarding; `MacroPreview` minimumScaleFactor

## Round 2 — mandatory flow, lean bulk, keyboard, cropping (DONE)
- [x] Removed "Skip for now"; added **Lean bulk** goal + `FitnessGoal.direction`
- [x] Goal weight typable; keyboard scroll fix (`ScrollViewReader` + `@FocusState`)
- [x] Cropping fix: `.background(AppBackground())` instead of `ZStack` (unbounded-width gotcha)
- [x] `--show-onboarding` hook + `OnboardingScreenshotTests`

## Round 3 — recomp, tickers, custom pace (DONE)
- [x] **Recomp** goal — maintenance calories + 2.0 g/kg protein (direction 0 → skips pace step)
- [x] **Swipeable sliders** on age / height / weight / goal weight (ember-tinted `Slider`
      alongside the +/- steppers; weight also gained steppers) via `tickerStepper` / `tickerField`
- [x] **Custom pace** — 4th pace with its own rate slider + steppers, dynamic
      Sustainable/Aggressive badge; scrolls into view when picked
- [x] Model refactor: rate-based `dailyEnergyDelta(goal:weeklyRateKg:)` + `weeklyRateKg(...)`
      core, pace-based convenience overloads kept; `Profile` stores pace + custom rate
- [x] Tests: recomp (maintenance + higher protein, skips pace), custom rate drives delta/timeframe + stays clamped

## Verification (Round 3)
- `NutritionPlanTests` — **14/14 pass** (added recomp + custom-rate tests).
- `OnboardingScreenshotTests` — drove the flow; inspected all 9 states. Confirmed: Recomp in the
  goal list; sliders on every numeric input; weight field above the keyboard; Custom pace shows its
  rate control + badge; plan reads "…at a custom pace". No cropping.
- `** TEST SUCCEEDED **` (build clean, iOS 17 target).
