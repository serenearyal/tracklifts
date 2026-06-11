//
//  BarcodeScannerView.swift
//  tracklifts
//
//  Barcode capture for the food log (Phase 3). Two on-device paths, both ending
//  at the same `onScan(GTIN)` callback:
//   • Live camera — VisionKit's DataScannerViewController.
//   • A photo from the library — VNDetectBarcodesRequest on the picked image, for
//     logging a product later (no box in hand) or when there's no camera (e.g. the
//     Simulator, where live scanning is unsupported but photo pick still works).
//  Everything stays on-device; no image leaves the phone.
//

import SwiftUI
import VisionKit
import Vision    // VNDetectBarcodesRequest + VNBarcodeSymbology
import PhotosUI  // PhotosPicker (no photo-library usage string needed)
import UIKit

struct BarcodeScannerView: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var photoItem: PhotosPickerItem?
    @State private var detecting = false
    @State private var noBarcodeFound = false

    /// Retail symbologies, shared by the live scanner and the (off-main) photo detector.
    nonisolated private static let symbologies: [VNBarcodeSymbology] = [.ean13, .ean8, .upce, .code128, .code39]

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported {
                    DataScannerRepresentable(symbologies: Self.symbologies, onScan: handle)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    noCameraState
                }
            }
            .background(AppBackground())
            .overlay { if detecting { detectingOverlay } }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.inkSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ember)
                    }
                }
            }
            .onChange(of: photoItem) { _, item in if let item { detect(item) } }
            .alert("No barcode found", isPresented: $noBarcodeFound) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Couldn't read a barcode in that photo. Try a clearer, closer shot — or scan the barcode directly.")
            }
        }
    }

    /// Hand the payload up, then close the scanner.
    private func handle(_ code: String) {
        onScan(code)
        dismiss()
    }

    /// No live camera (e.g. the Simulator) — offer the photo path instead of a dead end.
    private var noCameraState: some View {
        VStack(spacing: 18) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 44, weight: .bold)).foregroundStyle(Palette.inkTertiary)
            Text("Live scanning needs a camera")
                .font(.display(24)).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
            Text("This device has no camera available. You can still pick a photo of a barcode from your library.")
                .font(.sans(14)).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.center)
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                Label("Choose a Photo", systemImage: "photo.on.rectangle.angled")
                    .font(.sans(15, .bold)).tracking(0.5).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Grad.ember, in: .rect(cornerRadius: 16))
            }
            .padding(.top, 4)
        }
        .padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var detectingOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(Palette.ember)
                Text("Reading barcode…").font(.sans(14, .semibold)).foregroundStyle(Palette.ink)
            }
            .padding(24).background(Palette.surface, in: .rect(cornerRadius: 16))
        }
    }

    /// Load the chosen photo and look for a barcode in it (off the main actor).
    private func detect(_ item: PhotosPickerItem) {
        detecting = true
        Task {
            let code = await Self.barcode(in: item)
            detecting = false
            photoItem = nil // reset so re-picking the same image re-triggers detection
            if let code { handle(code) } else { noBarcodeFound = true }
        }
    }

    /// Decode the image and run Vision's barcode detector. `nonisolated` so the
    /// CPU-bound `perform` runs off the main actor.
    nonisolated private static func barcode(in item: PhotosPickerItem) async -> String? {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let cgImage = image.cgImage else { return nil }
        let request = VNDetectBarcodesRequest()
        request.symbologies = symbologies
        let handler = VNImageRequestHandler(cgImage: cgImage,
                                            orientation: CGImagePropertyOrientation(image.imageOrientation),
                                            options: [:])
        try? handler.perform([request])
        let codes = (request.results ?? []).compactMap(\.payloadStringValue).filter { !$0.isEmpty }
        return codes.first
    }
}

/// UIKit bridge for `DataScannerViewController`, recognizing common retail symbologies.
private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let symbologies: [VNBarcodeSymbology]
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: symbologies)],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        try? scanner.startScanning() // no-op if already scanning
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var handled = false // fire once — the view dismisses on first hit
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            emitFirstBarcode(in: addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            emitFirstBarcode(in: [item])
        }

        private func emitFirstBarcode(in items: [RecognizedItem]) {
            guard !handled else { return }
            for case let .barcode(barcode) in items {
                if let payload = barcode.payloadStringValue, !payload.isEmpty {
                    handled = true
                    onScan(payload)
                    return
                }
            }
        }
    }
}

private extension CGImagePropertyOrientation {
    /// Map a `UIImage.Orientation` so Vision reads the photo the right way up.
    nonisolated init(_ ui: UIImage.Orientation) {
        switch ui {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
