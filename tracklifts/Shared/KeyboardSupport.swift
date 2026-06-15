//
//  KeyboardSupport.swift
//  tracklifts
//
//  Number / decimal pads have no return key, so a focused numeric field can
//  trap the user. These helpers give every numeric field a way out.
//

import SwiftUI
import UIKit
import Combine

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

    /// Pads the bottom by the live keyboard height so content rises above the keyboard.
    /// Use inside a custom full-screen overlay/ZStack (e.g. the photo review card),
    /// where SwiftUI's automatic avoidance doesn't apply — it only insets the one
    /// primary scroll container, not a sibling layer stacked over it.
    func keyboardAvoidingPadding() -> some View {
        modifier(KeyboardAvoidingPadding())
    }
}

/// Bottom padding that tracks the keyboard. The keyboard frame is in screen space, so
/// padding by its full height clears the keyboard with a little breathing room (the
/// home-indicator inset) on devices that have one.
private struct KeyboardAvoidingPadding: ViewModifier {
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.bottom, height)
            // We move the content ourselves, so opt out of SwiftUI's own keyboard inset —
            // otherwise a device where it partially applies would double-lift the card.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .animation(.easeOut(duration: 0.25), value: height)
            .onReceive(Self.heightChanges) { height = $0 }
    }

    private static var heightChanges: AnyPublisher<CGFloat, Never> {
        let center = NotificationCenter.default
        let show = center.publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { ($0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height }
        let hide = center.publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ in CGFloat(0) }
        return show.merge(with: hide).eraseToAnyPublisher()
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
