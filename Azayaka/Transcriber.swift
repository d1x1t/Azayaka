//
//  Transcriber.swift
//  Azayaka
//
//  On-device transcription using SpeechAnalyzer + DictationTranscriber (macOS 26+).
//  Transcribes an audio file and returns timestamped text.
//

import Speech
import AVFAudio

final class Transcriber {

    enum TranscriberError: Error, LocalizedError {
        case noResults
        case authorizationDenied

        var errorDescription: String? {
            switch self {
            case .noResults: return "No transcription results were produced."
            case .authorizationDenied: return "Speech recognition permission was denied."
            }
        }
    }

    /// Transcribe an audio file and return a timestamped transcript string.
    /// Each line: [HH:MM:SS] transcribed text
    @available(macOS 26.0, *)
    func transcribe(fileURL: URL) async throws -> String {
        // Request authorization
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard status == .authorized else {
            throw TranscriberError.authorizationDenied
        }

        let audioFile = try AVAudioFile(forReading: fileURL)

        // DictationTranscriber with timeIndexedLongDictation produces
        // sentence-level segments instead of word-by-word fragments
        let transcriber = DictationTranscriber(
            locale: Locale(identifier: "en-US"),
            preset: .timeIndexedLongDictation
        )

        let analyzer = try await SpeechAnalyzer(
            inputAudioFile: audioFile,
            modules: [transcriber],
            finishAfterFile: true
        )

        // Collect raw segments
        struct Segment {
            let startSeconds: Double
            let text: String
        }
        var segments: [Segment] = []

        for try await result in transcriber.results {
            let startSeconds = result.range.start.seconds
            guard !startSeconds.isNaN else { continue }
            let text = String(result.text.characters).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !text.isEmpty {
                segments.append(Segment(startSeconds: startSeconds, text: text))
            }
        }

        // Keep analyzer alive until results are consumed
        _ = analyzer

        if segments.isEmpty {
            throw TranscriberError.noResults
        }

        // Post-process: merge consecutive segments with <2s gap into one line
        var merged: [(timestamp: Double, text: String)] = []
        for seg in segments {
            if let last = merged.last,
               seg.startSeconds - last.timestamp < 2.0,
               !last.text.hasSuffix(".") && !last.text.hasSuffix("?") && !last.text.hasSuffix("!") {
                // Merge into previous segment
                merged[merged.count - 1].text += " " + seg.text
            } else {
                merged.append((timestamp: seg.startSeconds, text: seg.text))
            }
        }

        let lines = merged.map { "[\(formatTimestamp($0.timestamp))] \($0.text)" }
        return lines.joined(separator: "\n")
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
