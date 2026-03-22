//
//  Transcriber.swift
//  Azayaka
//
//  On-device transcription using SpeechAnalyzer + SpeechTranscriber (macOS 26+).
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

        // Create a SpeechTranscriber with time-indexed preset for segment timestamps
        let transcriber = SpeechTranscriber(
            locale: Locale(identifier: "en-US"),
            preset: .timeIndexedTranscriptionWithAlternatives
        )

        // Create SpeechAnalyzer with the audio file, finish when file ends
        let analyzer = try await SpeechAnalyzer(
            inputAudioFile: audioFile,
            modules: [transcriber],
            finishAfterFile: true
        )

        // Collect results
        var lines: [String] = []
        for try await result in transcriber.results {
            let startSeconds = result.range.start.seconds
            guard !startSeconds.isNaN else { continue }
            let timestamp = formatTimestamp(startSeconds)
            let text = String(result.text.characters)
            if !text.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty {
                lines.append("[\(timestamp)] \(text)")
            }
        }

        if lines.isEmpty {
            throw TranscriberError.noResults
        }

        // Keep analyzer alive until results are consumed
        _ = analyzer

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
