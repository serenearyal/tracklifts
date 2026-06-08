//
//  Appearance.swift
//  tracklifts
//
//  Global UIKit appearance so navigation bars, the tab bar, and segmented
//  controls match the FORGE language without per-screen overrides.
//

import UIKit
import SwiftUI

enum Appearance {
    static func configure() {
        let ink = UIColor(Palette.ink)
        let ember = UIColor(Palette.ember)

        // Navigation bars — transparent so the app background shows through.
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundColor = .clear
        nav.shadowColor = .clear
        nav.titleTextAttributes = [
            .foregroundColor: ink,
            .font: UIFont(name: "Archivo-Bold", size: 17) ?? .systemFont(ofSize: 17, weight: .bold),
        ]
        if let bebas = UIFont(name: "BebasNeue-Regular", size: 40) {
            nav.largeTitleTextAttributes = [.foregroundColor: ink, .font: bebas]
        } else {
            nav.largeTitleTextAttributes = [.foregroundColor: ink]
        }
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = ember

        // Tab bar — translucent dark blur with ember selection.
        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundColor = UIColor(Palette.bgBottom).withAlphaComponent(0.7)
        let item = tab.stackedLayoutAppearance
        item.selected.iconColor = ember
        item.normal.iconColor = UIColor(Palette.inkTertiary)
        let selFont = UIFont(name: "Archivo-Bold", size: 10) ?? .systemFont(ofSize: 10, weight: .bold)
        let normFont = UIFont(name: "Archivo-Medium", size: 10) ?? .systemFont(ofSize: 10, weight: .medium)
        item.selected.titleTextAttributes = [.foregroundColor: ember, .font: selFont]
        item.normal.titleTextAttributes = [.foregroundColor: UIColor(Palette.inkTertiary), .font: normFont]
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        // Segmented controls.
        let seg = UISegmentedControl.appearance()
        seg.selectedSegmentTintColor = ember
        seg.backgroundColor = UIColor(Palette.surfaceRaised)
        seg.setTitleTextAttributes([
            .foregroundColor: UIColor.black,
            .font: UIFont(name: "Archivo-Bold", size: 13) ?? .systemFont(ofSize: 13, weight: .bold),
        ], for: .selected)
        seg.setTitleTextAttributes([
            .foregroundColor: UIColor(Palette.inkSecondary),
            .font: UIFont(name: "Archivo-SemiBold", size: 13) ?? .systemFont(ofSize: 13, weight: .semibold),
        ], for: .normal)
    }
}
