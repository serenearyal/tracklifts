//
//  CaptureView.swift
//  tracklifts
//
//  Phase 4 — the unified capture sheet. Camera-first: snap (or pick) a meal photo
//  for cloud recognition, or describe it in text / speak it for on-device parsing.
//  Every mode reduces to `[ParsedItem]` → `CaptureMatcher` → `CaptureConfirmList`,
//  the one review-and-commit step. Photo loading + failures are staged by
//  `PhotoStatusOverlay` (a vision-scan loader + tailored recovery screens).
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct CaptureView: View {
    var day: Date = .now

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var text = ""
    @State private var batch: CaptureBatch?
    @State private var noMatches = false
    @State private var speech = SpeechCapture()

    // Photo (cloud Gemini, opt-in)
    @AppStorage("photoAICloudEnabled") private var photoEnabled = false
    @State private var showingCamera = false
    @State private var showingGallery = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showingPhotoOptIn = false
    @State private var pendingPhoto: PhotoSource?
    @State private var photoFlow: PhotoFlow = .idle
    @State private var workingImage: UIImage?
    @State private var analyzeTask: Task<Void, Never>?

    @FocusState private var focused: Bool

    enum PhotoSource { case camera, gallery }

    /// A parsed+matched set, wrapped so it can drive `navigationDestination(item:)`.
    /// Identity is the only thing navigation needs, hence by-id `Hashable` (its
    /// `CaptureMatch`es carry SwiftData models that aren't Hashable).
    struct CaptureBatch: Identifiable, Hashable {
        let id = UUID()
        var matches: [CaptureMatch]
        static func == (a: CaptureBatch, b: CaptureBatch) -> Bool { a.id == b.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        ZStack {
            sheet
            if photoFlow != .idle {
                PhotoStatusOverlay(
                    flow: photoFlow,
                    image: workingImage,
                    cameraAvailable: cameraAvailable,
                    onRetry:  { if let img = workingImage { analyzeImage(img) } },
                    onRetake: { photoFlow = .idle; deferred { start(.camera) } },
                    onGallery: { photoFlow = .idle; deferred { start(.gallery) } },
                    onType:   { photoFlow = .idle; focused = true },
                    onClose:  { analyzeTask?.cancel(); photoFlow = .idle }
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: photoFlow)
    }

    private var sheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    photoSection
                    orDivider("or describe it")
                    textSection
                    voiceRow
                    if noMatches {
                        Text("Couldn’t pick out any foods. Try “food, amount” — e.g. “2 eggs, 1 cup rice”.")
                            .font(.sans(13)).foregroundStyle(Palette.down)
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .navigationTitle("Log a Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.inkSecondary)
                }
            }
            .keyboardDoneBar()
            .onDisappear { speech.stop() }
            .onChange(of: speech.transcript) { _, t in if !t.isEmpty { text = t } }
            .onChange(of: photoItem) { _, item in if let item { analyzeGallery(item) } }
            .fullScreenCover(isPresented: $showingCamera) {
                MealCameraPicker { image in analyzeImage(image) }.ignoresSafeArea()
            }
            .photosPicker(isPresented: $showingGallery, selection: $photoItem, matching: .images)
            .confirmationDialog("Use photo recognition?", isPresented: $showingPhotoOptIn, titleVisibility: .visible) {
                Button("Enable") {
                    photoEnabled = true
                    if let p = pendingPhoto { pendingPhoto = nil; deferred { start(p) } }
                }
                Button("Cancel", role: .cancel) { pendingPhoto = nil }
            } message: {
                Text("Your photo is sent to Google Gemini to identify foods. Typed and voice capture stay on your device.")
            }
            .navigationDestination(item: $batch) { b in
                CaptureConfirmList(matches: b.matches, day: day) { dismiss() }
            }
        }
    }

    // MARK: - Photo (primary)

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Snap your meal", systemImage: "camera.fill")
            if cameraAvailable {
                EmberButton(title: "Take a Photo", systemImage: "camera.fill") { start(.camera) }
                Button { start(.gallery) } label: {
                    captureChip(title: "Choose from gallery", system: "photo.on.rectangle.angled")
                }
                .buttonStyle(.plain)
            } else {
                EmberButton(title: "Choose from Gallery", systemImage: "photo.on.rectangle.angled") { start(.gallery) }
                Text("Camera capture needs a real device — pick a meal photo from your library instead.")
                    .font(.sans(12)).foregroundStyle(Palette.inkTertiary)
            }
            if photoEnabled, !GeminiConfig.isConfigured {
                Text("Add your Gemini API key (Secrets.plist) to enable photo recognition.")
                    .font(.sans(12)).foregroundStyle(Palette.inkTertiary)
            }
        }
    }

    private func captureChip(title: String, system: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: system).font(.system(size: 15, weight: .bold))
            Text(title).font(.sans(14, .semibold))
            Spacer()
        }
        .foregroundStyle(Palette.ember)
        .padding(.vertical, 12).padding(.horizontal, 14)
        .background(Palette.surface, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.ember.opacity(0.35), lineWidth: 1))
    }

    // MARK: - Text

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("e.g. 2 eggs, a cup of oatmeal with blueberries, and 200g chicken breast")
                        .font(.sans(15)).foregroundStyle(Palette.inkTertiary)
                        .padding(.vertical, 16).padding(.horizontal, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .font(.sans(15)).foregroundStyle(Palette.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 104)
                    .padding(.vertical, 8).padding(.horizontal, 10)
            }
            .background(Palette.surface, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.hairline, lineWidth: 1))

            EmberButton(title: "Find Foods", systemImage: "arrow.right") { parse() }
                .disabled(trimmed.isEmpty)
                .opacity(trimmed.isEmpty ? 0.5 : 1)
        }
    }

    // MARK: - Voice

    private var voiceRow: some View {
        let active = speech.isListening
        let tint = active ? Palette.down : Palette.ember
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { if active { speech.stop() } else { focused = false; await speech.start() } }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: active ? "stop.fill" : "mic.fill").font(.system(size: 15, weight: .bold))
                    Text(active ? "Listening… tap to stop" : "Speak your meal").font(.sans(14, .semibold))
                    Spacer()
                    if active { Circle().fill(Palette.down).frame(width: 9, height: 9) }
                }
                .foregroundStyle(tint)
                .padding(.vertical, 12).padding(.horizontal, 14)
                .background(Palette.surface, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)

            if speech.status == .denied {
                Text("Microphone or speech access is off — enable it in Settings to use voice.")
                    .font(.sans(12)).foregroundStyle(Palette.inkTertiary)
            } else if speech.status == .unavailable {
                Text("On-device speech isn’t available here (the Simulator has no microphone).")
                    .font(.sans(12)).foregroundStyle(Palette.inkTertiary)
            }
        }
    }

    // MARK: - Bits

    private func orDivider(_ label: String) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
            Text(label.uppercased()).font(.sans(11, .bold)).tracking(1).foregroundStyle(Palette.inkTertiary).fixedSize()
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
    }

    // MARK: - Actions

    /// Gate photo behind the opt-in, then present the chosen source.
    private func start(_ source: PhotoSource) {
        guard photoEnabled else { pendingPhoto = source; showingPhotoOptIn = true; return }
        switch source {
        case .camera: showingCamera = true
        case .gallery: showingGallery = true
        }
    }

    private func parse() {
        let items = MealTextParser.parse(text)
        guard !items.isEmpty else { noMatches = true; return }
        noMatches = false
        batch = CaptureBatch(matches: CaptureMatcher.match(items, in: context))
    }

    private func analyzeGallery(_ item: PhotosPickerItem) {
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            photoItem = nil
            guard let data, let image = UIImage(data: data) else {
                workingImage = nil
                photoFlow = .failed(.unreadable)
                return
            }
            analyzeImage(image)
        }
    }

    private func analyzeImage(_ image: UIImage) {
        workingImage = image
        noMatches = false
        guard GeminiConfig.isConfigured else { photoFlow = .failed(.notConfigured); return }
        guard let jpeg = prepareJPEG(image) else { photoFlow = .failed(.unreadable); return }
        photoFlow = .analyzing
        analyzeTask?.cancel()
        analyzeTask = Task {
            do {
                let items = try await FoodVision.shared.recognize(jpeg)
                guard !Task.isCancelled else { return }
                photoFlow = .idle
                batch = CaptureBatch(matches: CaptureMatcher.match(items, in: context))
            } catch {
                guard !Task.isCancelled else { return }
                photoFlow = .failed(Self.failure(from: error))
            }
        }
    }

    private static func failure(from error: Error) -> PhotoFailure {
        guard let e = error as? FoodVisionError else { return .unreadable }
        switch e {
        case .empty: return .noFood
        case .notConfigured: return .notConfigured
        case .badResponse: return .unreadable
        }
    }

    /// Normalize to a reasonably-sized JPEG to control upload size + cost.
    private func prepareJPEG(_ image: UIImage, maxDimension: CGFloat = 1024) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: target).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }

    /// Run after the current UI update settles — avoids presenting a cover while
    /// the status overlay is still dismissing.
    private func deferred(_ action: @escaping () -> Void) { Task { @MainActor in action() } }
}
