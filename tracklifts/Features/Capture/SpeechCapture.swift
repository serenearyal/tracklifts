//
//  SpeechCapture.swift
//  tracklifts
//
//  Phase 4 — on-device speech-to-text for the capture sheet (iOS 17 path). Wraps
//  `SFSpeechRecognizer` + `AVAudioEngine`; the live transcript feeds the same
//  `MealTextParser` the typed field uses. `requiresOnDeviceRecognition` keeps the
//  audio + text on the device, honoring the offline-voice principle. Device-only
//  to verify — the Simulator has no microphone input.
//

import Foundation
import Observation
import AVFoundation
import Speech

@MainActor
@Observable
final class SpeechCapture {
    enum Status: Equatable { case idle, listening, denied, unavailable }

    private(set) var status: Status = .idle
    private(set) var transcript = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var isListening: Bool { status == .listening }

    /// Ask for mic + speech permission, then begin live transcription.
    func start() async {
        guard status != .listening else { return }
        transcript = ""

        guard let recognizer, recognizer.isAvailable else { status = .unavailable; return }
        guard await requestPermissions() else { status = .denied; return }

        do {
            try beginSession(with: recognizer)
            status = .listening
        } catch {
            stop()
            status = .unavailable
        }
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if status == .listening { status = .idle }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Permissions

    private func requestPermissions() async -> Bool {
        let speechOK = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        guard speechOK else { return false }
        return await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
    }

    // MARK: Engine

    private func beginSession(with recognizer: SFSpeechRecognizer) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        // The handler runs off the main actor; pull out Sendable values, then hop back.
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let finished = error != nil || (result?.isFinal ?? false)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let text { self.transcript = text }
                if finished { self.stop() }
            }
        }

        engine.prepare()
        try engine.start()
    }
}
