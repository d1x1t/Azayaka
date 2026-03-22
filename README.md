# Koe

**A simple macOS menu bar audio recorder for capturing system audio and microphone** — perfect for recording calls, meetings, and any audio playing on your Mac. Includes on-device transcription.

## Features

- **One-click recording** — capture system audio from any app (Teams, Zoom, YouTube, etc.)
- **Microphone mixing** — optionally mix your mic into the same audio track
- **On-device transcription** — automatically transcribe recordings using Apple's SpeechAnalyzer (macOS 26+)
- **Webhook integration** — optionally POST transcripts to any URL (Make, Zapier, n8n, etc.)
- **Audio format options** — AAC, ALAC (lossless), FLAC, or Opus
- **Configurable quality** — 128–320 Kbps for lossy formats
- **Keyboard shortcut** — start/stop recording without touching the mouse
- **Menu bar app** — stays out of your way; click to record, click again to stop

## How it works

Uses macOS ScreenCaptureKit to capture system audio (requires Screen Recording permission). When microphone recording is enabled, mic audio is resampled to match the system audio format and mixed into a single output track in real time. After recording stops, the audio file is transcribed on-device and saved as a .txt file alongside the recording.

## Requirements

- macOS 13 (Ventura) or later (transcription requires macOS 26)
- Screen Recording permission (for system audio capture)
- Microphone permission (optional, for mic recording)
- Speech Recognition permission (for transcription)

## Building

1. Open `Azayaka.xcodeproj` in Xcode
2. Select your signing team in **Signing & Capabilities**
3. Build and run (Cmd+R)
4. Grant Screen Recording permission when prompted

## Credits

Based on [Azayaka](https://github.com/Mnpn/Azayaka) by Martin Persson. This fork removes video/screen recording and adds microphone mixing, on-device transcription, and webhook integration.
