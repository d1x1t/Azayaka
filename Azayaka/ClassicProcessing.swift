//
//  ClassicProcessing.swift
//  Azayaka
//
//  Audio stream processing — handles system audio writing and mic mixing.
//

import ScreenCaptureKit

extension AppDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        switch outputType {
        case .audio:
            guard let samples = sampleBuffer.asPCMBuffer, let audioFile else { return }
            mixPendingMicInto(buffer: samples)
            do {
                try audioFile.write(from: samples)
            }
            catch { print("audio file writing issue: \(error)") }
        case .microphone:
            if let micPCM = sampleBuffer.asPCMBuffer {
                let sysFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
                if let converted = convertBuffer(micPCM, to: sysFormat) {
                    appendToMicFIFO(converted)
                }
            }
        default:
            break // ignore .screen frames
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("closing stream with error:\n".local, error)
        DispatchQueue.main.async {
            self.stream = nil
            self.stopRecording()
        }
    }

    func convertBuffer(_ input: AVAudioPCMBuffer, to outputFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        if input.format.sampleRate == outputFormat.sampleRate && input.format.channelCount == outputFormat.channelCount {
            return input
        }

        if micConverter == nil || micConverterInputFormat != input.format {
            micConverter = AVAudioConverter(from: input.format, to: outputFormat)
            micConverterInputFormat = input.format
        }
        guard let converter = micConverter else { return nil }

        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(input.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else { return nil }

        var error: NSError?
        var hasData = true
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if hasData {
                hasData = false
                outStatus.pointee = .haveData
                return input
            }
            outStatus.pointee = .noDataNow
            return nil
        }
        if let error { print("Mic conversion error: \(error)"); return nil }
        return outputBuffer
    }

    func appendToMicFIFO(_ buffer: AVAudioPCMBuffer) {
        guard let chData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let chanCount = Int(buffer.format.channelCount)
        micFIFOLock.lock()
        defer { micFIFOLock.unlock() }
        for c in 0..<min(chanCount, micSampleFIFO.count) {
            micSampleFIFO[c].append(contentsOf: UnsafeBufferPointer(start: chData[c], count: frames))
        }
        if chanCount == 1 && micSampleFIFO.count > 1 {
            micSampleFIFO[1].append(contentsOf: UnsafeBufferPointer(start: chData[0], count: frames))
        }
        let maxSamples = 48000
        for c in 0..<micSampleFIFO.count {
            if micSampleFIFO[c].count > maxSamples {
                micSampleFIFO[c].removeFirst(micSampleFIFO[c].count - maxSamples)
            }
        }
    }

    func mixPendingMicInto(buffer sysBuffer: AVAudioPCMBuffer) {
        micFIFOLock.lock()
        guard !micSampleFIFO.isEmpty, !micSampleFIFO[0].isEmpty else {
            micFIFOLock.unlock()
            return
        }
        guard let sysCh = sysBuffer.floatChannelData else {
            micFIFOLock.unlock()
            return
        }
        let sysFrames = Int(sysBuffer.frameLength)
        let sysChanCount = Int(sysBuffer.format.channelCount)

        let available = min(micSampleFIFO[0].count, sysFrames)
        for c in 0..<sysChanCount {
            let micCh = min(c, micSampleFIFO.count - 1)
            for f in 0..<available {
                sysCh[c][f] = max(-1.0, min(1.0, sysCh[c][f] + micSampleFIFO[micCh][f]))
            }
        }
        for c in 0..<micSampleFIFO.count {
            micSampleFIFO[c].removeFirst(available)
        }
        micFIFOLock.unlock()
    }
}

// https://developer.apple.com/documentation/screencapturekit/capturing_screen_content_in_macos
extension CMSampleBuffer {
    var asPCMBuffer: AVAudioPCMBuffer? {
        try? self.withAudioBufferList { audioBufferList, _ -> AVAudioPCMBuffer? in
            guard let absd = self.formatDescription?.audioStreamBasicDescription else { return nil }
            guard let format = AVAudioFormat(standardFormatWithSampleRate: absd.mSampleRate, channels: absd.mChannelsPerFrame) else { return nil }
            return AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: audioBufferList.unsafePointer)
        }
    }
}
