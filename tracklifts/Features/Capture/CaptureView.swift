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

    // AI capture (cloud Gemini, opt-in — covers photo + typed/spoken descriptions)
    @AppStorage("photoAICloudEnabled") private var aiEnabled = false
    @State private var showingCamera = false
    @State private var showingGallery = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showingAIOptIn = false
    @State private var pendingAction: CaptureAction?
    @State private var photoFlow: PhotoFlow = .idle
    @State private var workingImage: UIImage?
    @State private var photoNote = ""
    @State private var reviewAutofocus = false
    @State private var textBusy = false
    // Separate handles so starting the text-estimate flow doesn't cancel an in-flight
    // photo analysis (and vice versa); both are cancelled on close/disappear.
    @State private var textTask: Task<Void, Never>?
    @State private var photoTask: Task<Void, Never>?

    @FocusState private var focused: Bool

    /// A capture path gated behind the AI opt-in, so granting it can resume the action.
    enum CaptureAction { case camera, gallery, describe }

    /// A parsed+matched set, wrapped so it can drive `navigationDestination(item:)`.
    /// Identity is the only thing navigation needs, hence by-id `Hashable` (its
    /// `CaptureMatch`es carry SwiftData models that aren't Hashable).
    struct CaptureBatch: Identifiable, Hashable {
        let id = UUID()
        var matches: [CaptureMatch]
        var fromPhoto = false        // gates the "add a note & re-scan" affordance
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
                    note: $photoNote,
                    autofocusNote: reviewAutofocus,
                    onAnalyze: { if let img = workingImage { analyzeImage(img, note: photoNote) } },
                    onRetry:  { if let img = workingImage { analyzeImage(img, note: photoNote) } },
                    onRetake: { photoFlow = .idle; deferred { start(.camera) } },
                    onGallery: { photoFlow = .idle; deferred { start(.gallery) } },
                    onType:   { photoFlow = .idle; focused = true },
                    onClose:  { textTask?.cancel(); photoTask?.cancel(); photoFlow = .idle }
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
            .onDisappear { speech.stop(); textTask?.cancel(); photoTask?.cancel() }
            .onChange(of: speech.transcript) { _, t in if !t.isEmpty { text = t } }
            .onChange(of: photoItem) { _, item in if let item { analyzeGallery(item) } }
            .fullScreenCover(isPresented: $showingCamera) {
                MealCameraPicker { image in presentReview(image) }.ignoresSafeArea()
            }
            .photosPicker(isPresented: $showingGallery, selection: $photoItem, matching: .images)
            .confirmationDialog("Use AI estimation?", isPresented: $showingAIOptIn, titleVisibility: .visible) {
                Button("Enable") {
                    aiEnabled = true
                    if let action = pendingAction { pendingAction = nil; deferred { resume(action) } }
                }
                Button("Cancel", role: .cancel) { pendingAction = nil }
            } message: {
                Text("Your meal photo or description is sent to Google Gemini to estimate foods and calories. Spoken meals are transcribed on your device first.")
            }
            .navigationDestination(item: $batch) { b in
                CaptureConfirmList(matches: b.matches, day: day,
                                   onRescan: b.fromPhoto ? { rescan() } : nil) { dismiss() }
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
            if aiEnabled, !GeminiConfig.isConfigured {
                Text("Add your Gemini API key (Secrets.plist) to enable AI estimation.")
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
                    Text("e.g. a large latte with oat milk and 2 sugars, and a blueberry muffin")
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

            EmberButton(title: textBusy ? "Estimating…" : "Estimate",
                        systemImage: textBusy ? "hourglass" : "sparkles") { submitText() }
                .disabled(trimmed.isEmpty || textBusy)
                .opacity(trimmed.isEmpty || textBusy ? 0.5 : 1)
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

    /// Gate a cloud capture behind the AI opt-in, then present the chosen source.
    private func start(_ source: CaptureAction) {
        guard aiEnabled else { pendingAction = source; showingAIOptIn = true; return }
        switch source {
        case .camera: showingCamera = true
        case .gallery: showingGallery = true
        case .describe: submitText()
        }
    }

    /// Resume a gated action once the AI opt-in is granted.
    private func resume(_ action: CaptureAction) {
        switch action {
        case .camera: start(.camera)
        case .gallery: start(.gallery)
        case .describe: submitText()
        }
    }

    /// Typed/spoken meal: estimate with AI when available, else fall back to the
    /// on-device catalog match so logging still works offline / without a key.
    private func submitText() {
        let desc = trimmed
        guard !desc.isEmpty else { return }
        noMatches = false
        guard aiEnabled else { pendingAction = .describe; showingAIOptIn = true; return }
        guard GeminiConfig.isConfigured else { matchOnDevice(desc); return }
        estimateWithAI(desc)
    }

    private func estimateWithAI(_ desc: String) {
        textBusy = true
        focused = false
        textTask?.cancel()
        textTask = Task {
            defer { textBusy = false }
            do {
                let items = try await FoodText.shared.estimate(description: desc)
                guard !Task.isCancelled else { return }
                batch = CaptureBatch(matches: CaptureMatcher.match(items, in: context))
            } catch is CancellationError {
                // dismissed mid-flight — leave the sheet as-is
            } catch {
                // offline / no foods / bad response → fall back to on-device matching
                guard !Task.isCancelled else { return }
                matchOnDevice(desc)
            }
        }
    }

    /// On-device fallback: heuristic parse + catalog match (the pre-AI behavior).
    private func matchOnDevice(_ desc: String) {
        let items = MealTextParser.parse(desc)
        guard !items.isEmpty else { noMatches = true; return }
        noMatches = false
        batch = CaptureBatch(matches: CaptureMatcher.match(items, in: context))
    }

    private func analyzeGallery(_ item: PhotosPickerItem) {
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            photoItem = nil
            // Decode off the main actor (large library images are slow to decode).
            guard let data, let image = await Self.decodeImage(from: data) else {
                workingImage = nil
                photoFlow = .failed(.unreadable)
                return
            }
            presentReview(image)
        }
    }

    /// Stage the captured photo for review with an optional AI note. A fresh capture
    /// clears any prior note (a new photo is a new meal). If the key is missing we
    /// skip straight to the failure screen rather than ask for a note that can't run.
    private func presentReview(_ image: UIImage) {
        workingImage = image
        photoNote = ""
        reviewAutofocus = false
        noMatches = false
        guard GeminiConfig.isConfigured else { photoFlow = .failed(.notConfigured); return }
        photoFlow = .review
    }

    private func analyzeImage(_ image: UIImage, note: String?) {
        workingImage = image
        noMatches = false
        guard GeminiConfig.isConfigured else { photoFlow = .failed(.notConfigured); return }
        photoFlow = .analyzing
        photoTask?.cancel()
        photoTask = Task {
            // Resize + EXIF-strip + encode off the main actor (nonisolated static),
            // so a large photo doesn't hitch the UI while the loader is up.
            guard let jpeg = await Self.makeJPEG(from: image) else {
                guard !Task.isCancelled else { return }
                photoFlow = .failed(.unreadable); return
            }
            guard !Task.isCancelled else { return }
            do {
                let items = try await FoodVision.shared.recognize(jpeg, note: note)
                guard !Task.isCancelled else { return }
                photoFlow = .idle
                batch = CaptureBatch(matches: CaptureMatcher.match(items, in: context), fromPhoto: true)
            } catch {
                guard !Task.isCancelled else { return }
                photoFlow = .failed(Self.failure(from: error))
            }
        }
    }

    /// Re-run analysis with more context: cover the results with the review screen
    /// (its note field focused) and pop them. The photo + prior note are preserved so
    /// the user can extend the note; tapping Analyze produces a fresh batch.
    private func rescan() {
        reviewAutofocus = true
        photoFlow = .review
        batch = nil
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
    /// SECURITY: the unconditional re-render through `UIGraphicsImageRenderer` also
    /// strips EXIF/GPS metadata (it lives on the original asset, not the redrawn
    /// pixel buffer) before the photo leaves the device. Keep this redraw
    /// unconditional — do NOT add a "forward the original `Data` when it's already
    /// small" shortcut, or location metadata would leak to the cloud vision provider.
    ///
    /// `nonisolated async` so the awaited resize/encode runs off the main actor (on
    /// the cooperative pool — the `UIImage`/`Data` cross the boundary fine), keeping
    /// the UI smooth for large photos; only the resulting `Data` is handed back.
    nonisolated private static func makeJPEG(from image: UIImage, maxDimension: CGFloat = 1024) async -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: target).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }

    /// Decode raw photo `Data` into a `UIImage` off the main actor (large gallery
    /// images are expensive to decode); returns nil for unreadable data.
    nonisolated private static func decodeImage(from data: Data) async -> UIImage? {
        UIImage(data: data)
    }

    /// Run after the current UI update settles — avoids presenting a cover while
    /// the status overlay is still dismissing.
    private func deferred(_ action: @escaping () -> Void) { Task { @MainActor in action() } }
}
