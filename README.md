<h1><img align="center" height="72" src="https://github.com/Mnpn/Azayaka/raw/main/Azayaka/Assets.xcassets/AppIcon.appiconset/Azayaka-256.png"> Azayaka</h1>

**A simple macOS menu bar audio recorder for capturing system audio and microphone** — perfect for recording calls, meetings, and any audio playing on your Mac.

Based on [Mnpn/Azayaka](https://github.com/Mnpn/Azayaka), simplified to focus on audio-only recording with microphone mixing.

## Features

- **One-click recording** — capture system audio from any app (Teams, Zoom, YouTube, etc.)
- **Microphone mixing** — optionally mix your mic into the same audio track
- **Audio format options** — AAC, ALAC (lossless), FLAC, or Opus
- **Configurable quality** — 128–320 Kbps for lossy formats
- **Keyboard shortcut** — start/stop recording without touching the mouse
- **Menu bar app** — stays out of your way, shows recording duration

## How it works

Uses macOS ScreenCaptureKit to capture system audio (requires Screen Recording permission). When microphone recording is enabled, mic audio is resampled to match the system audio format and mixed into a single output track in real time.

## Requirements

- macOS 13 (Ventura) or later
- Screen Recording permission (for system audio capture)
- Microphone permission (optional, for mic recording)

## Building

1. Open `Azayaka.xcodeproj` in Xcode
2. Select your signing team in **Signing & Capabilities**
3. Build and run (Cmd+R)
4. Grant Screen Recording permission when prompted

## Credits

Originally created by [Martin Persson (Mnpn)](https://github.com/Mnpn/Azayaka). This fork removes video/screen recording and adds microphone mixing for audio-only use.
