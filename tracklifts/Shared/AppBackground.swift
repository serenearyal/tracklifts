//
//  AppBackground.swift
//  tracklifts
//
//  The shared atmosphere: a warm-charcoal vertical wash, two soft ember glows,
//  and a fine film-grain overlay for depth. Sits behind every screen.
//

import SwiftUI
import UIKit

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.bgTop, Palette.bgBottom],
                           startPoint: .top, endPoint: .bottom)

            // Ember glow, upper-right.
            Circle()
                .fill(Grad.glow(Palette.ember))
                .frame(width: 460, height: 460)
                .blur(radius: 40)
                .offset(x: 150, y: -260)
                .opacity(0.55)

            // Cooler counter-glow, lower-left, for balance.
            Circle()
                .fill(Grad.glow(Color(hex: 0x3A6EA5)))
                .frame(width: 420, height: 420)
                .blur(radius: 50)
                .offset(x: -170, y: 360)
                .opacity(0.30)

            GrainOverlay()
                .opacity(0.05)
                .blendMode(.overlay)
        }
        .ignoresSafeArea()
    }
}

/// A tiled, cached film-grain texture (cheap — built once).
struct GrainOverlay: View {
    var body: some View {
        Image(uiImage: NoiseTexture.shared)
            .resizable(resizingMode: .tile)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

enum NoiseTexture {
    static let shared: UIImage = make(size: 140)

    private static func make(size: Int) -> UIImage {
        let bytesPerPixel = 4
        let bytesPerRow = size * bytesPerPixel
        var data = [UInt8](repeating: 0, count: size * size * bytesPerPixel)
        for i in stride(from: 0, to: data.count, by: bytesPerPixel) {
            let v = UInt8.random(in: 0...255)
            data[i] = v; data[i + 1] = v; data[i + 2] = v
            data[i + 3] = 255
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: &data, width: size, height: size,
                            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        if let cg = ctx?.makeImage() {
            return UIImage(cgImage: cg)
        }
        return UIImage()
    }
}
