//
//  Recording.swift
//  Azayaka
//
//  Created by Martin Persson on 2022-12-26.
//

import ScreenCaptureKit
import AVFAudio
import KeyboardShortcuts

extension AppDelegate {
    @objc func prepRecord(_ sender: NSMenuItem) {
        statusItem.menu = nil
        updateAudioSettings()

        let countdown = ud.integer(forKey: Preferences.kCountdownSecs)
        if countdown > 0 {
            let cdMenu = NSMenu()
            cdMenu.addItem(NSMenuItemWithIcon(icon: "chevron.forward.2", title: "Skip countdown".local, action: #selector(skipCountdown)))
            cdMenu.addItem(NSMenuItemWithIcon(icon: "xmark", title: "Cancel".local, action: #selector(stopCountdown)))
            addMenuFooter(toMenu: cdMenu)
            statusItem.menu = cdMenu
        }
        allowShortcuts(true)
        Task {
            guard await CountdownManager.shared.showCountdown(countdown) else {
                stopRecording(withError: true)
                return
            }
            allowShortcuts(false)
            do {
                try prepareAudioRecording()
            } catch {
                stopRecording(withError: true)
                return
            }
            await startAudioCapture()
        }
    }

    @objc func stopCountdown() { CountdownManager.shared.finishCountdown(startRecording: false) }
    @objc func skipCountdown() { CountdownManager.shared.finishCountdown(startRecording: true) }

    func startAudioCapture() async {
        // Get available content for the SCContentFilter
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            if case SCStreamError.userDeclined = error {
                requestPermissions()
            } else {
                alertRecordingFailure(error)
            }
            stopRecording(withError: true)
            return
        }

        guard let display = content.displays.first else {
            stopRecording(withError: true)
            return
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        var conf = SCStreamConfiguration()
        conf.width = 2
        conf.height = 2
        conf.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale.max)
        conf.capturesAudio = true
        conf.sampleRate = audioSettings["AVSampleRateKey"] as! Int
        conf.channelCount = audioSettings["AVNumberOfChannelsKey"] as! Int
        if #available(macOS 15.0, *) {
            conf.captureMicrophone = await ud.bool(forKey: Preferences.kRecordMic)
        }

        stream = SCStream(filter: filter, configuration: conf, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
            if #available(macOS 15.0, *), conf.captureMicrophone {
                try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: .global())
            }
            startTime = Date.now
            isRecording = true
            try await stream.startCapture()
            allowShortcuts(true)
        } catch {
            alertRecordingFailure(error)
            stream = nil
            stopRecording(withError: true)
            return
        }

        DispatchQueue.main.async { [self] in
            updateIcon()
            createMenu()
        }
    }

    @objc func stopRecording(withError: Bool = false) {
        DispatchQueue.main.async { [self] in
            statusItem.menu = nil

            if stream != nil {
                stream.stopCapture()
                stream = nil
            }

            startTime = nil
            isRecording = false
            audioFile = nil

            updateTimer?.invalidate()

            updateIcon()
            createMenu()

            if !withError {
                allowShortcuts(true)
                sendRecordingFinishedNotification()
                copyToClipboard([NSURL(fileURLWithPath: filePath)])

                // Transcribe the recording on-device (macOS 26+)
                if #available(macOS 26.0, *), let path = filePath {
                    let audioURL = URL(fileURLWithPath: path)
                    Task {
                        do {
                            let transcriber = Transcriber()
                            let transcript = try await transcriber.transcribe(fileURL: audioURL)
                            let txtURL = audioURL.deletingPathExtension().appendingPathExtension("txt")
                            try transcript.write(to: txtURL, atomically: true, encoding: .utf8)
                            print("Transcript saved to \(txtURL.path)")
                            await MainActor.run {
                                self.sendTranscriptFinishedNotification(path: txtURL.path)
                            }
                        } catch {
                            print("Transcription failed: \(error)")
                        }
                    }
                }
            }
        }
    }

    func updateAudioSettings() {
        audioSettings = [AVSampleRateKey : 48000, AVNumberOfChannelsKey : 2]
        switch ud.string(forKey: Preferences.kAudioFormat) {
        case AudioFormat.aac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            audioSettings[AVEncoderBitRateKey] = ud.integer(forKey: Preferences.kAudioQuality) * 1000
        case AudioFormat.alac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatAppleLossless
            audioSettings[AVEncoderBitDepthHintKey] = 16
        case AudioFormat.flac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatFLAC
        case AudioFormat.opus.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatOpus
            audioSettings[AVEncoderBitRateKey] = ud.integer(forKey: Preferences.kAudioQuality) * 1000
        default:
            assertionFailure("unknown audio format while setting audio settings: ".local + (ud.string(forKey: Preferences.kAudioFormat) ?? "[no defaults]".local))
        }
    }

    func prepareAudioRecording() throws {
        var fileEnding = ud.string(forKey: Preferences.kAudioFormat) ?? "wat"
        switch fileEnding {
        case AudioFormat.aac.rawValue: fallthrough
        case AudioFormat.alac.rawValue: fileEnding = "m4a"
        case AudioFormat.flac.rawValue: fileEnding = "flac"
        case AudioFormat.opus.rawValue: fileEnding = "ogg"
        default: assertionFailure("loaded unknown audio format: ".local + fileEnding)
        }
        filePath = "\(getFilePath()).\(fileEnding)"
        do {
            audioFile = try AVAudioFile(forWriting: URL(fileURLWithPath: filePath), settings: audioSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Couldn't initialise the audio file!".local
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "Okay".local)
                alert.alertStyle = .critical
                alert.runModal()
            }
            throw error
        }
    }

    func getFilePath() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "y-MM-dd HH.mm.ss"
        var fileName = ud.string(forKey: Preferences.kFileName)
        if fileName == nil || fileName!.isEmpty {
            fileName = "Recording at %t".local
        }
        let fileNameWithDates = fileName!.replacingOccurrences(of: "%t", with: dateFormatter.string(from: Date())).prefix(Int(NAME_MAX) - 5)

        let saveDirectory = ud.string(forKey: Preferences.kSaveDirectory)
        do {
            try FileManager.default.createDirectory(atPath: saveDirectory!, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Failed to create destination folder: ".local + error.localizedDescription)
        }

        return saveDirectory! + "/" + fileNameWithDates
    }

    func getRecordingLength() -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        formatter.unitsStyle = .positional
        return formatter.string(from: Date.now.timeIntervalSince(startTime ?? Date.now)) ?? "Unknown".local
    }

    func getRecordingSize() -> String {
        let byteFormat = ByteCountFormatter()
        byteFormat.allowedUnits = [.useMB]
        byteFormat.countStyle = .file
        do {
            if let filePath = filePath {
                let fileAttr = try FileManager.default.attributesOfItem(atPath: filePath)
                return byteFormat.string(fromByteCount: fileAttr[FileAttributeKey.size] as! Int64)
            }
        } catch {
            print(String(format: "failed to fetch file for size indicator: %@".local, error.localizedDescription))
        }
        return "Unknown".local
    }

    func alertRecordingFailure(_ error: Error) {
        allowShortcuts(false)
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Recording failed!".local
            alert.informativeText = String(format: "Couldn't start the recording:\n\"%@\"".local, error.localizedDescription)
            alert.addButton(withTitle: "Okay".local)
            alert.alertStyle = .critical
            alert.runModal()
            self.allowShortcuts(true)
        }
    }
}
