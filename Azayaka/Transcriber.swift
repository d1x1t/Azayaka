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

        // Split large segments at sentence boundaries (. ? !) for readability
        var lines: [String] = []
        for seg in segments {
            let sentences = splitIntoSentences(seg.text)
            for sentence in sentences {
                let trimmed = sentence.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    lines.append("[\(formatTimestamp(seg.startSeconds))] \(trimmed)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { substring, _, _, _ in
            if let s = substring {
                sentences.append(s)
            }
        }
        // If no sentence boundaries found, return the whole text
        return sentences.isEmpty ? [text] : sentences
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
