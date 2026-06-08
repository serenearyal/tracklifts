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
