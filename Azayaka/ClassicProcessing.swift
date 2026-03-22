//
//  ClassicProcessing.swift
//  Azayaka
//
//  Created by Martin Persson on 2024-08-08.
//

import ScreenCaptureKit

// This file contains code related to the "classic" recorder. It uses an
// AVAssetWriter instead of the ScreenCaptureKit recorder found in macOS Sequoia.
// System audio-only recording still uses this.

extension AppDelegate {
    func initClassicRecorder(conf: SCStreamConfiguration, encoder: AVVideoCodecType, filePath: String, fileType: AVFileType) {
        startTime = nil

        vW = try? AVAssetWriter.init(outputURL: URL(fileURLWithPath: filePath), fileType: fileType)
        let fpsMultiplier: Double = Double(ud.integer(forKey: Preferences.kFrameRate))/8
        let encoderMultiplier: Double = encoder == .hevc ? 0.5 : 0.9
        let targetBitrate = (Double(conf.width) * Double(conf.height) * fpsMultiplier * encoderMultiplier * ud.double(forKey: Preferences.kVideoQuality))
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: encoder,
            AVVideoWidthKey: conf.width,
            AVVideoHeightKey: conf.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(targetBitrate),
                AVVideoExpectedSourceFrameRateKey: ud.integer(forKey: Preferences.kFrameRate)
            ] as [String : Any]
        ]
        vwInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
        awInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioSettings)
        vwInput.expectsMediaDataInRealTime = true
        awInput.expectsMediaDataInRealTime = true
        
        if vW.canAdd(vwInput) {
            vW.add(vwInput)
        }
        
        if vW.canAdd(awInput) {
            vW.add(awInput)
        }
        
        recordMic = ud.bool(forKey: Preferences.kRecordMic)
        if recordMic {
            micInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioSettings)
            micInput.expectsMediaDataInRealTime = true
            
            if vW.canAdd(micInput) {
                vW.add(micInput)
            }
        }

        // on macOS 15, the system recorder will handle mic recording directly with SCK + AVAssetWriter
        if #unavailable(macOS 15), recordMic {
            let input = audioEngine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.inputFormat(forBus: 0)) { [self] (buffer, time) in
                if micInput.isReadyForMoreMediaData && startTime != nil {
                    micInput.append(buffer.asSampleBuffer!)
                }
            }
            try! audioEngine.start()
        }

        vW.startWriting()
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard (streamType == .systemaudio || !useSystemRecorder) && sampleBuffer.isValid else { return }

        switch outputType {
            case .screen:
                if screen == nil && window == nil { break }
                guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                      let attachments = attachmentsArray.first else { return }
                guard let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
                      let status = SCFrameStatus(rawValue: statusRawValue),
                      status == .complete else { return }
                
                if vW != nil && vW?.status == .writing, startTime == nil {
                    startTime = Date.now
                    vW.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                }
                if vwInput.isReadyForMoreMediaData {
                    vwInput.append(sampleBuffer)
                }
                break
            case .audio:
                if streamType == .systemaudio { // write directly to file if not video recording
                    guard let samples = sampleBuffer.asPCMBuffer else { return }
                    mixPendingMicInto(buffer: samples)
                    do {
                        try audioFile!.write(from: samples)
                    }
                    catch { assertionFailure("audio file writing issue".local) }
                } else { // otherwise send the audio data to AVAssetWriter
                    if (awInput != nil) && awInput.isReadyForMoreMediaData {
                        awInput.append(sampleBuffer)
                    }
                }
            case .microphone: // only available on sequoia - older versions will use AVAudioEngine
                if streamType == .systemaudio {
                    if let micPCM = sampleBuffer.asPCMBuffer {
                        // Convert mic to system audio format (sample rate + channels may differ)
                        let sysFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
                        if let converted = convertBuffer(micPCM, to: sysFormat) {
                            pendingMicBuffers.append(converted)
                        }
                    }
                } else {
                    if (micInput != nil) && micInput.isReadyForMoreMediaData {
                        micInput.append(sampleBuffer)
                    }
                }
            @unknown default:
                assertionFailure("unknown stream type".local)
        }
    }

    func convertBuffer(_ input: AVAudioPCMBuffer, to outputFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Skip conversion if formats already match
        if input.format.sampleRate == outputFormat.sampleRate && input.format.channelCount == outputFormat.channelCount {
            return input
        }

        // Create or reuse converter
        if micConverter == nil || micConverterInputFormat != input.format {
            micConverter = AVAudioConverter(from: input.format, to: outputFormat)
            micConverterInputFormat = input.format
        }
        guard let converter = micConverter else { return nil }

        // Calculate output frame count based on sample rate ratio
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

    func mixPendingMicInto(buffer sysBuffer: AVAudioPCMBuffer) {
        guard !pendingMicBuffers.isEmpty else { return }
        let micBuffers = pendingMicBuffers
        pendingMicBuffers.removeAll()

        guard let sysCh = sysBuffer.floatChannelData else { return }
        let sysFrames = Int(sysBuffer.frameLength)
        let sysChanCount = Int(sysBuffer.format.channelCount)

        for micBuf in micBuffers {
            guard let micCh = micBuf.floatChannelData else { continue }
            let frames = min(Int(micBuf.frameLength), sysFrames)
            let micChanCount = Int(micBuf.format.channelCount)
            for f in 0..<frames {
                for c in 0..<sysChanCount {
                    let mc = min(c, micChanCount - 1)
                    sysCh[c][f] = max(-1.0, min(1.0, sysCh[c][f] + micCh[mc][f]))
                }
            }
        }
    }
}

// https://developer.apple.com/documentation/screencapturekit/capturing_screen_content_in_macos
// For Sonoma updated to https://developer.apple.com/forums/thread/727709
extension CMSampleBuffer {
    var asPCMBuffer: AVAudioPCMBuffer? {
        try? self.withAudioBufferList { audioBufferList, _ -> AVAudioPCMBuffer? in
            guard let absd = self.formatDescription?.audioStreamBasicDescription else { return nil }
            guard let format = AVAudioFormat(standardFormatWithSampleRate: absd.mSampleRate, channels: absd.mChannelsPerFrame) else { return nil }
            return AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: audioBufferList.unsafePointer)
        }
    }
}

// Based on https://gist.github.com/aibo-cora/c57d1a4125e145e586ecb61ebecff47c
extension AVAudioPCMBuffer {
    var asSampleBuffer: CMSampleBuffer? {
        let asbd = self.format.streamDescription
        var sampleBuffer: CMSampleBuffer? = nil
        var format: CMFormatDescription? = nil

        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        ) == noErr else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Int32(asbd.pointee.mSampleRate)),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )

        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleCount: CMItemCount(self.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        ) == noErr else { return nil }

        guard CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer!,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: self.mutableAudioBufferList
        ) == noErr else { return nil }

        return sampleBuffer
    }
}
