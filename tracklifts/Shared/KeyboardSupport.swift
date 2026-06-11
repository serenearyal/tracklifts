//
//  KeyboardSupport.swift
//  tracklifts
//
//  Number / decimal pads have no return key, so a focused numeric field can
//  trap the user. These helpers give every numeric field a way out.
//

import SwiftUI
import UIKit

extension View {
    /// Adds a keyboard accessory bar with a trailing "Done" that resigns the
    /// focused field. Reliable inside sheets and navigation stacks; pair it with
    /// `.scrollDismissesKeyboard(.interactively)` as a belt-and-suspenders escape.
    func keyboardDoneBar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { KeyboardDismiss.resign() }
                    .font(.sans(15, .semibold))
                    .foregroundStyle(Palette.ember)
            }
        }
    }
}

enum KeyboardDismiss {
    /// Resigns whatever text field is first responder — no `@FocusState` needed.
    static func resign() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension ScrollViewProxy {
    /// Lifts the focused field high in the scroll viewport so it clears the keyboard
    /// with plenty of visible context (instead of the default "just above the keyboard").
    /// Call from an `onChange(of:)` on the field's `@FocusState`; `id` is the value given
    /// to the field's `.id(...)` — often the focus value itself. A nil id (focus cleared)
    /// is a no-op.
    ///
    /// Only `.top` / `.center` / `.bottom` are reliable anchors in `List` (fractional
    /// `UnitPoint`s silently no-op, and `contentMargins(.top:)` is ignored by `scrollTo`).
    /// `.top` lands the target under a transparent nav bar; pass `.center` when the target
    /// is a card whose title must stay clear of the bar.
    func scrollFieldToTop<ID: Hashable>(_ id: ID?, anchor: UnitPoint = .top) {
        guard let id else { return }
        withAnimation(.snappy) { scrollTo(id, anchor: anchor) }
    }
}
