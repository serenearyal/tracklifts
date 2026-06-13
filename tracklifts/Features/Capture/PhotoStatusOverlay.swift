//
//  PhotoStatusOverlay.swift
//  tracklifts
//
//  Phase 4 — the photo-recognition experience while (and after) Gemini runs. Two
//  states, both staged over the actual photo you captured so the wait + any miss
//  feel intentional, not like a dropped request:
//   • analyzing — a viewfinder "vision scan" (sweeping ember beam, corner brackets)
//     with a frosted status card cycling through what it's doing.
//   • failed — a tailored recovery screen (no food found / unreadable / no key)
//     with real next steps: retake, gallery, try again, or fall back to typing.
//  Pure presentation; all actions are callbacks owned by CaptureView.
//

import SwiftUI
import UIKit

/// Why a photo recognition attempt ended without items.
enum PhotoFailure: Equatable { case noFood, unreadable, notConfigured }

/// The photo pipeline's visible state. `.idle` shows nothing.
enum PhotoFlow: Equatable { case idle, analyzing, failed(PhotoFailure) }

struct PhotoStatusOverlay: View {
    let flow: PhotoFlow
    let image: UIImage?
    let cameraAvailable: Bool
    var onRetry: () -> Void
    var onRetake: () -> Void
    var onGallery: () -> Void
    var onType: () -> Void
    var onClose: () -> Void

    /// Cards are centered at a fixed width (never full-bleed), so they always sit
    /// inside the screen with side margins on every device + text size.
    private let cardMaxWidth: CGFloat = 320

    var body: some View {
        ZStack {
            backdrop
            switch flow {
            case .analyzing:           analyzing
            case .failed(let failure): failed(failure)
            case .idle:                Color.clear
            }
            VStack {
                HStack { Spacer(); closeButton }
                Spacer()
            }
            .padding(.horizontal, 18).padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // This modal has tight, fixed geometry — let text grow a little for
        // legibility, but cap it so large accessibility sizes can't blow the
        // cards past the screen (text also shrinks-to-fit below as a backstop).
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    // MARK: - Backdrop (the captured photo, darkened, with grain)

    private var backdrop: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .blur(radius: isFailed ? 7 : 0)
                    .overlay(LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0.84)],
                                            startPoint: .top, endPoint: .bottom))
                    .overlay(Color.black.opacity(isFailed ? 0.3 : 0))
            } else {
                AppBackground()
            }
            GrainOverlay().opacity(0.06).blendMode(.overlay)
        }
        .ignoresSafeArea()
        .clipped()
    }

    private var isFailed: Bool { if case .failed = flow { return true }; return false }

    // MARK: - Analyzing

    @State private var sweep = false

    private var analyzing: some View {
        VStack(spacing: 40) {
            Spacer()
            scanner
            Spacer()
            statusCard
        }
        .padding(.bottom, 30)
    }

    private var scanner: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22).fill(Palette.ember.opacity(0.04))
            // The sweeping beam, clipped to the frame.
            RoundedRectangle(cornerRadius: 2)
                .fill(LinearGradient(colors: [.clear, Palette.ember.opacity(0.95), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 2.5)
                .shadow(color: Palette.ember, radius: 10)
                .shadow(color: Palette.ember.opacity(0.6), radius: 24)
                .offset(y: sweep ? 150 : -150)
        }
        .frame(width: 264, height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            CornerBrackets()
                .stroke(Palette.ember, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .shadow(color: Palette.ember.opacity(0.6), radius: 8)
        )
        .onAppear {
            sweep = false
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { sweep = true }
        }
    }

    @State private var phraseIndex = 0
    @State private var pulse = false
    @State private var shimmer = false
    private let phrases = ["Looking at your plate", "Identifying foods", "Estimating portions", "Matching your catalog"]

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Circle().fill(Palette.ember).frame(width: 7, height: 7)
                    .shadow(color: Palette.ember, radius: 6).opacity(pulse ? 1 : 0.25)
                Text(phrases[phraseIndex].uppercased())
                    .font(.sans(12, .bold)).tracking(1.0).foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .id(phraseIndex)
                    .transition(.opacity)
                Spacer(minLength: 0)
            }
            shimmerBar
        }
        .padding(16)
        .frame(maxWidth: cardMaxWidth, alignment: .leading)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.hairline, lineWidth: 1))
        .padding(.horizontal, 16)
        .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true } }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.3))
                withAnimation(.easeInOut(duration: 0.35)) { phraseIndex = (phraseIndex + 1) % phrases.count }
            }
        }
    }

    private var shimmerBar: some View {
        GeometryReader { geo in
            Capsule().fill(Palette.surfaceRaised)
                .overlay(
                    Capsule()
                        .fill(LinearGradient(colors: [.clear, Palette.ember, .clear],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * 0.45)
                        .offset(x: shimmer ? geo.size.width * 0.8 : -geo.size.width * 0.45)
                )
                .clipShape(Capsule())
        }
        .frame(height: 4)
        .onAppear {
            shimmer = false
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: false)) { shimmer = true }
        }
    }

    // MARK: - Failed

    @State private var cardIn = false

    private func failed(_ failure: PhotoFailure) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Palette.ember.opacity(0.14)).frame(width: 76, height: 76)
                Circle().strokeBorder(Palette.ember.opacity(0.35), lineWidth: 1).frame(width: 76, height: 76)
                Image(systemName: failure.symbol).font(.system(size: 28, weight: .bold)).foregroundStyle(Palette.ember)
            }
            VStack(spacing: 8) {
                Text(failure.headline).font(.display(30)).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                Text(failure.message).font(.sans(14)).foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            actions(for: failure).padding(.top, 4)
        }
        .padding(22)
        .frame(maxWidth: cardMaxWidth)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Palette.hairline, lineWidth: 1))
        .padding(.horizontal, 16)
        .scaleEffect(cardIn ? 1 : 0.93).opacity(cardIn ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { cardIn = true } }
    }

    @ViewBuilder
    private func actions(for failure: PhotoFailure) -> some View {
        VStack(spacing: 10) {
            switch failure {
            case .noFood:
                if cameraAvailable {
                    EmberButton(title: "Retake Photo", systemImage: "camera.fill", action: onRetake)
                    secondary("Choose from Gallery", "photo.on.rectangle.angled", onGallery)
                } else {
                    EmberButton(title: "Choose Photo", systemImage: "photo.on.rectangle.angled", action: onGallery)
                }
                typeInstead
            case .unreadable:
                EmberButton(title: "Try Again", systemImage: "arrow.clockwise", action: onRetry)
                secondary(cameraAvailable ? "Retake Photo" : "Choose Photo",
                          cameraAvailable ? "camera.fill" : "photo.on.rectangle.angled",
                          cameraAvailable ? onRetake : onGallery)
                typeInstead
            case .notConfigured:
                EmberButton(title: "Type It Instead", systemImage: "keyboard", action: onType)
                secondary("Close", "xmark", onClose)
            }
        }
    }

    private var typeInstead: some View {
        Button(action: onType) {
            Text("or type it instead")
                .font(.sans(13, .semibold)).foregroundStyle(Palette.inkSecondary).underline()
        }
        .buttonStyle(.plain).padding(.top, 2)
    }

    private func secondary(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14, weight: .bold))
                Text(title.uppercased()).font(.sans(12, .bold)).tracking(0.5)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(Palette.ember)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(Palette.surface.opacity(0.55), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.ember.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Close

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.ink)
                .frame(width: 38, height: 38).background(.ultraThinMaterial, in: .circle)
                .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}

/// Four L-shaped viewfinder corners stroked around the frame.
private struct CornerBrackets: Shape {
    var length: CGFloat = 30
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let l = length
        // top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + l)); p.addLine(to: CGPoint(x: rect.minX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
        // top-right
        p.move(to: CGPoint(x: rect.maxX - l, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
        // bottom-right
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))
        // bottom-left
        p.move(to: CGPoint(x: rect.minX + l, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        return p
    }
}

private extension PhotoFailure {
    var symbol: String {
        switch self {
        case .noFood:        "eye.slash"
        case .unreadable:    "exclamationmark.triangle.fill"
        case .notConfigured: "key.fill"
        }
    }
    var headline: String {
        switch self {
        case .noFood:        "No food in frame"
        case .unreadable:    "Couldn’t read that"
        case .notConfigured: "Photo AI is off"
        }
    }
    var message: String {
        switch self {
        case .noFood:        "We couldn’t spot a meal in that shot. Aim at a plate, bowl, or glass so the food fills most of the frame — good light helps."
        case .unreadable:    "The analyzer didn’t come back with anything readable. Check your connection and try again."
        case .notConfigured: "Add your Gemini API key to turn on photo logging. Typing and voice work without it."
        }
    }
}
