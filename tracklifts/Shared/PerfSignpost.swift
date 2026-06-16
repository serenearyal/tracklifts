//
//  PerfSignpost.swift
//  tracklifts
//
//  Lightweight Instruments instrumentation (os_signpost via OSSignposter) so the
//  first-launch seed hang and the per-render recompute of the heavy SwiftUI bodies
//  are observable in Instruments (Time Profiler / Hangs / os_signpost lanes).
//
//  Signposts compile to near-zero-cost no-ops when nothing is recording, so these
//  are safe to leave in shipping builds. Use a StaticString name (no interpolation)
//  to keep the not-recording path allocation-free.
//

import OSLog

/// Single shared signposter on a dedicated subsystem/category. Filter Instruments
/// to subsystem `serene.tracklifts`, category `Performance` to see these lanes.
enum Perf {
    /// `nonisolated` so it's reachable from any isolation context. `OSSignposter`
    /// is `Sendable`, and the app target is `@MainActor` by default — without this
    /// the static would be main-actor-isolated.
    nonisolated static let signposter = OSSignposter(
        subsystem: "serene.tracklifts", category: "Performance")

    /// Emits a one-shot `.event` signpost — used to count how often a heavy view
    /// body re-evaluates. Near-zero cost when not recording.
    nonisolated static func renderTick(_ name: StaticString) {
        signposter.emitEvent(name)
    }

    /// Brackets `body` in a begin/end interval signpost so synchronous work (e.g.
    /// the first-launch seed loop) shows up as a measurable interval — and any hang
    /// it causes lines up with it in the Hangs / Time Profiler instruments.
    nonisolated static func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try body()
    }
}
