// generate_icon.swift
//
// Offline CoreGraphics generator for the TrackLifts ("FORGE") app icon + brand
// mark. Produces four 1024×1024 PNGs:
//   1. AppIcon-1024.png         — primary (ember barbell on dark forge canvas)
//   2. AppIcon-Dark-1024.png    — dark-appearance variant (deeper canvas)
//   3. AppIcon-Tinted-1024.png  — tinted variant (gray mark on solid black)
//   4. Logo.png                 — mark only on transparent bg (in-app use)
//
// Re-runnable:  swift tools/generate_icon.swift
//
// No network, no image-gen APIs — pure CoreGraphics.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Paths

let projectRoot = "/Users/serenearyal/Documents/projects/misc/tracklifts"
let appIconDir = "\(projectRoot)/tracklifts/Assets.xcassets/AppIcon.appiconset"
let logoDir = "\(projectRoot)/tracklifts/Assets.xcassets/Logo.imageset"

let S = 1024            // canvas size (px), square
let size = CGFloat(S)

// MARK: - Color helpers

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: a
    )
}

// Palette (matches Shared/DesignSystem.swift + spec).
let bgTopLeft = rgb(0x1A1712)        // warm charcoal
let bgBottomRight = rgb(0x0B0A09)    // near-black
let emberHi = rgb(0xFFB23E)
let ember = rgb(0xFF7A33)
let emberLo = rgb(0xF24E1E)
let emberGlow = rgb(0xFF7A33)

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: - Context factory

func makeContext() -> CGContext {
    let ctx = CGContext(
        data: nil,
        width: S, height: S,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: srgb,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // Quality: smooth gradients + curves.
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    return ctx
}

// MARK: - Background

/// Full-bleed diagonal charcoal→black gradient (top-left → bottom-right).
func drawBackgroundGradient(_ ctx: CGContext, top: CGColor, bottom: CGColor) {
    let grad = CGGradient(
        colorsSpace: srgb,
        colors: [top, bottom] as CFArray,
        locations: [0, 1]
    )!
    // Diagonal: from top-left corner to bottom-right corner.
    ctx.drawLinearGradient(
        grad,
        start: CGPoint(x: 0, y: size),       // top-left (CG origin is bottom-left)
        end: CGPoint(x: size, y: 0),         // bottom-right
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
}

/// Soft radial ember glow, centered slightly below the middle.
func drawEmberGlow(_ ctx: CGContext, alpha: CGFloat, radius: CGFloat) {
    let grad = CGGradient(
        colorsSpace: srgb,
        colors: [emberGlow.copy(alpha: alpha)!, emberGlow.copy(alpha: 0)!] as CFArray,
        locations: [0, 1]
    )!
    // "Slightly below the middle" in screen terms = below center.
    // CG origin is bottom-left, so a lower screen position is a smaller y.
    let center = CGPoint(x: size * 0.5, y: size * 0.42)
    ctx.saveGState()
    ctx.drawRadialGradient(
        grad,
        startCenter: center, startRadius: 0,
        endCenter: center, endRadius: radius,
        options: []
    )
    ctx.restoreGState()
}

// MARK: - Film grain

/// A small random monochrome-noise CGImage. Drawn scaled to fill the canvas
/// at low opacity for a faint film-grain texture.
func makeNoiseImage(side: Int) -> CGImage {
    let bpp = 4
    let bytesPerRow = side * bpp
    var data = [UInt8](repeating: 0, count: side * side * bpp)
    for i in stride(from: 0, to: data.count, by: bpp) {
        let v = UInt8.random(in: 0...255)
        data[i] = v; data[i + 1] = v; data[i + 2] = v
        data[i + 3] = 255
    }
    let ctx = CGContext(
        data: &data,
        width: side, height: side,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: srgb,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return ctx.makeImage()!
}

/// Overlay faint grain across the whole canvas.
func drawGrain(_ ctx: CGContext, opacity: CGFloat) {
    let noise = makeNoiseImage(side: 220)
    ctx.saveGState()
    ctx.setAlpha(opacity)
    ctx.setBlendMode(.overlay)
    ctx.interpolationQuality = .none   // keep grain crisp, not blurred
    // Tile the noise a few times so the texture isn't obviously stretched.
    let tiles = 3
    let tileSize = size / CGFloat(tiles)
    for ty in 0..<tiles {
        for tx in 0..<tiles {
            let rect = CGRect(x: CGFloat(tx) * tileSize,
                              y: CGFloat(ty) * tileSize,
                              width: tileSize, height: tileSize)
            ctx.draw(noise, in: rect)
        }
    }
    ctx.restoreGState()
}

// MARK: - Geometry helpers

/// Rotate a point around a center by `angle` radians.
func rotate(_ p: CGPoint, around c: CGPoint, by angle: CGFloat) -> CGPoint {
    let s = sin(angle), co = cos(angle)
    let dx = p.x - c.x, dy = p.y - c.y
    return CGPoint(x: c.x + dx * co - dy * s,
                   y: c.y + dx * s + dy * co)
}

/// A rounded-rect path centered at `center`, sized w×h, rotated `angle` rad
/// about that center. Built in local space then transformed.
func roundedRectPath(center: CGPoint, w: CGFloat, h: CGFloat,
                     radius: CGFloat, angle: CGFloat) -> CGPath {
    let local = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
    let r = min(radius, min(w, h) / 2)
    let base = CGPath(roundedRect: local, cornerWidth: r, cornerHeight: r, transform: nil)
    var t = CGAffineTransform(translationX: center.x, y: center.y)
        .rotated(by: angle)
    return base.copy(using: &t)!
}

// MARK: - The mark (ascending barbell)

/// Describes the barbell layout for a given canvas, parameterized by how much
/// of the width the mark should span.
struct BarbellLayout {
    let center: CGPoint
    let angle: CGFloat            // tilt in radians (+ = upward to the right, screen-space)
    let axis: CGVector           // unit vector along the bar
    let perp: CGVector           // unit vector perpendicular to the bar

    // Bar.
    let barLength: CGFloat
    let barThickness: CGFloat

    // Inner (big) plates.
    let innerPlateW: CGFloat     // along axis (thickness of plate)
    let innerPlateH: CGFloat     // along perp  (diameter of plate)
    let innerPlateOffset: CGFloat // distance of plate center from canvas center

    // Outer (smaller) plates.
    let outerPlateW: CGFloat
    let outerPlateH: CGFloat
    let outerPlateOffset: CGFloat

    // Sleeve cap (collar) just inside each inner plate.
    let collarW: CGFloat
    let collarH: CGFloat
    let collarOffset: CGFloat
}

/// Build a barbell layout. `span` ≈ fraction of canvas width the mark occupies
/// (bounding the outermost plate tips). 18° upward tilt by default.
func makeBarbell(span: CGFloat) -> BarbellLayout {
    let center = CGPoint(x: size / 2, y: size / 2)

    // Screen-space tilt is 18° upward toward the right. In CG (y-up) that is a
    // positive rotation.
    let angle = 18.0 * .pi / 180.0
    let axis = CGVector(dx: cos(angle), dy: sin(angle))
    let perp = CGVector(dx: -sin(angle), dy: cos(angle))

    // The full extent along the axis (tip-to-tip of outer plates).
    let fullExtent = size * span

    // Outer plates sit at the very ends — distinctly SMALLER than the hero
    // plate so the silhouette reads as "big plate + small collar plate",
    // not a thin stack / dumbbell.
    let outerPlateW = fullExtent * 0.072          // plate thickness (along bar)
    let outerPlateH = fullExtent * 0.250          // plate diameter (perp)
    let outerPlateOffset = fullExtent / 2 - outerPlateW / 2

    // Inner (hero) plates — clearly the dominant, bold plate.
    let innerPlateW = fullExtent * 0.120
    let innerPlateH = fullExtent * 0.500
    let gapBetweenPlates = fullExtent * 0.030
    let innerPlateOffset = outerPlateOffset - outerPlateW / 2
        - gapBetweenPlates - innerPlateW / 2

    // Bar: a capsule running the whole length, ending a touch past the inner
    // plates so it visually threads through them.
    let barThickness = fullExtent * 0.118
    let barLength = fullExtent * 0.995

    // Collar (sleeve cap) snug against the inboard face of each inner plate.
    let collarW = fullExtent * 0.045
    let collarH = barThickness * 1.62
    let collarOffset = innerPlateOffset - innerPlateW / 2 - collarW / 2 + fullExtent * 0.001

    return BarbellLayout(
        center: center, angle: angle, axis: axis, perp: perp,
        barLength: barLength, barThickness: barThickness,
        innerPlateW: innerPlateW, innerPlateH: innerPlateH, innerPlateOffset: innerPlateOffset,
        outerPlateW: outerPlateW, outerPlateH: outerPlateH, outerPlateOffset: outerPlateOffset,
        collarW: collarW, collarH: collarH, collarOffset: collarOffset
    )
}

/// Point at a signed distance `d` along the bar axis from center.
func along(_ l: BarbellLayout, _ d: CGFloat) -> CGPoint {
    CGPoint(x: l.center.x + l.axis.dx * d, y: l.center.y + l.axis.dy * d)
}

/// Build the combined silhouette path of the whole barbell (for shadow + as a
/// single fillable shape). Even-odd not needed — overlapping fills are unioned
/// by a single fill on this compound path.
func barbellPath(_ l: BarbellLayout) -> CGPath {
    let path = CGMutablePath()

    // Bar capsule.
    path.addPath(roundedRectPath(
        center: l.center, w: l.barLength, h: l.barThickness,
        radius: l.barThickness / 2, angle: l.angle))

    for side in [CGFloat(1), CGFloat(-1)] {
        // Collars.
        path.addPath(roundedRectPath(
            center: along(l, side * l.collarOffset),
            w: l.collarW, h: l.collarH,
            radius: l.collarH * 0.28, angle: l.angle))
        // Inner plates.
        path.addPath(roundedRectPath(
            center: along(l, side * l.innerPlateOffset),
            w: l.innerPlateW, h: l.innerPlateH,
            radius: l.innerPlateW * 0.46, angle: l.angle))
        // Outer plates.
        path.addPath(roundedRectPath(
            center: along(l, side * l.outerPlateOffset),
            w: l.outerPlateW, h: l.outerPlateH,
            radius: l.outerPlateW * 0.46, angle: l.angle))
    }
    return path
}

/// Fill the mark with the ember gradient along the 18° axis (top-left→bottom-
/// right in screen terms ≈ along the perp/diagonal). We clip to the silhouette
/// and paint a linear gradient across its bounding box.
func fillEmberGradient(_ ctx: CGContext, path: CGPath, l: BarbellLayout) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    let grad = CGGradient(
        colorsSpace: srgb,
        colors: [emberHi, ember, emberLo] as CFArray,
        locations: [0, 0.55, 1]   // hold the bright emberHi a bit longer
    )!
    let b = path.boundingBox
    // Top-left → bottom-right of the mark's bounding box (screen sense).
    ctx.drawLinearGradient(
        grad,
        start: CGPoint(x: b.minX, y: b.maxY),
        end: CGPoint(x: b.maxX, y: b.minY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()
}

/// Fill the mark with a vertical light-gray gradient (#F2F2F2 → #9A9A9A) for
/// the tinted variant — no ember color.
func fillGrayGradient(_ ctx: CGContext, path: CGPath) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let grad = CGGradient(
        colorsSpace: srgb,
        colors: [rgb(0xF2F2F2), rgb(0x9A9A9A)] as CFArray,
        locations: [0, 1]
    )!
    let b = path.boundingBox
    ctx.drawLinearGradient(
        grad,
        start: CGPoint(x: b.midX, y: b.maxY),   // top
        end: CGPoint(x: b.midX, y: b.minY),     // bottom
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()
}

/// Soft drop shadow under the whole mark: render the silhouette in black with a
/// CG shadow, offset slightly downward (screen) and blurred.
func drawMarkShadow(_ ctx: CGContext, path: CGPath, alpha: CGFloat, blur: CGFloat,
                    dy: CGFloat) {
    ctx.saveGState()
    // Screen-down = negative y in CG.
    ctx.setShadow(offset: CGSize(width: 0, height: -dy), blur: blur,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha))
    ctx.addPath(path)
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
}

/// Subtle top-left white sheen on the bar (forged-metal highlight): a thin
/// bright capsule riding the upper edge of the bar, clipped to the bar.
func drawBarSheen(_ ctx: CGContext, l: BarbellLayout, alpha: CGFloat) {
    // Clip to the bar capsule only.
    let bar = roundedRectPath(
        center: l.center, w: l.barLength, h: l.barThickness,
        radius: l.barThickness / 2, angle: l.angle)
    ctx.saveGState()
    ctx.addPath(bar)
    ctx.clip()

    // A soft gradient band hugging the top-left (upper) edge of the bar.
    // Offset the sheen capsule toward the perpendicular-up direction.
    let lift = l.barThickness * 0.30
    let sheenCenter = CGPoint(
        x: l.center.x + l.perp.dx * lift,
        y: l.center.y + l.perp.dy * lift)
    let sheen = roundedRectPath(
        center: sheenCenter, w: l.barLength * 0.92, h: l.barThickness * 0.42,
        radius: l.barThickness * 0.21, angle: l.angle)

    ctx.addPath(sheen)
    ctx.clip()
    let grad = CGGradient(
        colorsSpace: srgb,
        colors: [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha),
                 CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
        locations: [0, 1]
    )!
    // Brightest at the upper edge, fading down toward the bar core.
    let topEdge = CGPoint(
        x: sheenCenter.x + l.perp.dx * (l.barThickness * 0.21),
        y: sheenCenter.y + l.perp.dy * (l.barThickness * 0.21))
    let lowEdge = CGPoint(
        x: sheenCenter.x - l.perp.dx * (l.barThickness * 0.21),
        y: sheenCenter.y - l.perp.dy * (l.barThickness * 0.21))
    ctx.drawLinearGradient(grad, start: topEdge, end: lowEdge,
                           options: [.drawsBeforeStartLocation])
    ctx.restoreGState()
}

/// Soft top-left edge highlight on each plate to give them forged dimension.
func drawPlateSheen(_ ctx: CGContext, l: BarbellLayout, alpha: CGFloat) {
    for side in [CGFloat(1), CGFloat(-1)] {
        for (w, h, off, rad) in [
            (l.innerPlateW, l.innerPlateH, l.innerPlateOffset, l.innerPlateW * 0.46),
            (l.outerPlateW, l.outerPlateH, l.outerPlateOffset, l.outerPlateW * 0.46),
        ] {
            let c = along(l, side * off)
            let plate = roundedRectPath(center: c, w: w, h: h, radius: rad, angle: l.angle)
            ctx.saveGState()
            ctx.addPath(plate)
            ctx.clip()
            let grad = CGGradient(
                colorsSpace: srgb,
                colors: [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha),
                         CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
                locations: [0, 1]
            )!
            // Highlight along the top edge of the plate (perp-up direction).
            let topEdge = CGPoint(x: c.x + l.perp.dx * h / 2, y: c.y + l.perp.dy * h / 2)
            let botEdge = CGPoint(x: c.x - l.perp.dx * h * 0.10, y: c.y - l.perp.dy * h * 0.10)
            ctx.drawLinearGradient(grad, start: topEdge, end: botEdge,
                                   options: [.drawsBeforeStartLocation])
            ctx.restoreGState()
        }
    }
}

/// Render the full ember mark (shadow + gradient fill + sheens). `span` sizes it.
func drawEmberMark(_ ctx: CGContext, span: CGFloat,
                   shadowAlpha: CGFloat = 0.35, shadowBlur: CGFloat = 46,
                   shadowDY: CGFloat = 16) {
    let l = makeBarbell(span: span)
    let path = barbellPath(l)
    drawMarkShadow(ctx, path: path, alpha: shadowAlpha, blur: shadowBlur, dy: shadowDY)
    fillEmberGradient(ctx, path: path, l: l)
    drawBarSheen(ctx, l: l, alpha: 0.16)
    drawPlateSheen(ctx, l: l, alpha: 0.10)
}

// MARK: - PNG output

/// Re-render an image into an opaque (no-alpha) RGB bitmap. App icons must NOT
/// carry an alpha channel or App Store validation rejects them.
func flattenOpaque(_ image: CGImage) -> CGImage {
    let ctx = CGContext(
        data: nil,
        width: S, height: S,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: srgb,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

/// Write a CGImage as PNG. `opaque` flattens away the alpha channel (for icons).
func writePNG(_ image: CGImage, to path: String, opaque: Bool = false) {
    let out = opaque ? flattenOpaque(image) : image
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fputs("ERROR: could not create destination for \(path)\n", stderr)
        exit(1)
    }
    CGImageDestinationAddImage(dest, out, nil)
    if !CGImageDestinationFinalize(dest) {
        fputs("ERROR: could not write \(path)\n", stderr)
        exit(1)
    }
    print("wrote \(path)")
}

// MARK: - Compositions

/// Primary / dark icon: full-bleed canvas + glow + mark + grain.
func renderIconCanvas(top: CGColor, bottom: CGColor,
                      glowAlpha: CGFloat, glowRadius: CGFloat,
                      grainOpacity: CGFloat) -> CGImage {
    let ctx = makeContext()
    drawBackgroundGradient(ctx, top: top, bottom: bottom)
    drawEmberGlow(ctx, alpha: glowAlpha, radius: glowRadius)
    drawEmberMark(ctx, span: 0.66)
    drawGrain(ctx, opacity: grainOpacity)
    return ctx.makeImage()!
}

/// Tinted icon: solid black bg + gray-gradient mark (no ember, no glow/grain).
func renderTintedIcon() -> CGImage {
    let ctx = makeContext()
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

    let l = makeBarbell(span: 0.66)
    let path = barbellPath(l)
    // Gentle shadow so the shape still reads as raised on pure black.
    drawMarkShadow(ctx, path: path, alpha: 0.30, blur: 40, dy: 14)
    fillGrayGradient(ctx, path: path)
    return ctx.makeImage()!
}

/// In-app logo: mark only, transparent background, slightly larger span.
func renderLogo() -> CGImage {
    let ctx = makeContext()
    // Transparent canvas — draw nothing for the background.
    drawEmberMark(ctx, span: 0.80, shadowAlpha: 0.32, shadowBlur: 40, shadowDY: 14)
    return ctx.makeImage()!
}

// MARK: - Run

// 1. Primary.
let primary = renderIconCanvas(
    top: bgTopLeft, bottom: bgBottomRight,
    glowAlpha: 0.45, glowRadius: 520, grainOpacity: 0.035)
writePNG(primary, to: "\(appIconDir)/AppIcon-1024.png", opaque: true)

// 2. Dark (deepen the canvas a touch).
let darkTop = rgb(0x141009)
let darkBottom = rgb(0x070605)
let dark = renderIconCanvas(
    top: darkTop, bottom: darkBottom,
    glowAlpha: 0.40, glowRadius: 500, grainOpacity: 0.035)
writePNG(dark, to: "\(appIconDir)/AppIcon-Dark-1024.png", opaque: true)

// 3. Tinted.
writePNG(renderTintedIcon(), to: "\(appIconDir)/AppIcon-Tinted-1024.png", opaque: true)

// 4. Logo (transparent).
writePNG(renderLogo(), to: "\(logoDir)/Logo.png")

print("done.")
