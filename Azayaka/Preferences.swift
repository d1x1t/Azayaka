//
//  Preferences.swift
//  Azayaka
//
//  Created by Martin Persson on 2022-12-27.
//

import SwiftUI
import AVFAudio
import AVFoundation
import KeyboardShortcuts
import ServiceManagement

struct Preferences: View {
    static let kAudioFormat     = "audioFormat"
    static let kAudioQuality    = "audioQuality"
    static let kRecordMic       = "recordMic"

    static let kFileName        = "outputFileName"
    static let kSaveDirectory   = "saveDirectory"
    static let kAutoClipboard   = "autoCopyToClipboard"

    static let kUpdateCheck     = "updateCheck"
    static let kCountdownSecs   = "countDown"

    var body: some View {
        VStack {
            TabView {
                AudioSettings().tabItem {
                    Label("Audio", systemImage: "waveform")
                }

                OutputSettings().tabItem {
                    Label("Destination", systemImage: "folder")
                }

                ShortcutSettings().tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

                OtherSettings().tabItem {
                    Label("Other", systemImage: "gearshape")
                }
            }
        }.frame(width: 350)
    }

    struct AudioSettings: View {
        @AppStorage(kAudioFormat)    private var audioFormat: AudioFormat = .aac
        @AppStorage(kAudioQuality)   private var audioQuality: AudioQuality = .high
        @AppStorage(kRecordMic)      private var recordMic: Bool = false

        var body: some View {
            GroupBox {
                VStack {
                    Form {
                        let isLossless = audioFormat == .alac || audioFormat == .flac
                        Picker("Format", selection: $audioFormat) {
                            Text("AAC").tag(AudioFormat.aac)
                            Text("ALAC (Lossless)").tag(AudioFormat.alac)
                            Text("FLAC (Lossless)").tag(AudioFormat.flac)
                            Text("Opus").tag(AudioFormat.opus)
                        }.padding([.leading, .trailing], 10)
                        Picker("Quality", selection: $audioQuality) {
                            if isLossless {
                                Text("Lossless").tag(audioQuality)
                            }
                            Text("Normal - 128Kbps").tag(AudioQuality.normal)
                            Text("Good - 192Kbps").tag(AudioQuality.good)
                            Text("High - 256Kbps").tag(AudioQuality.high)
                            Text("Extreme - 320Kbps").tag(AudioQuality.extreme)
                        }.padding([.leading, .trailing], 10).disabled(isLossless)
                    }.frame(maxWidth: 250)
                }.padding([.top, .leading, .trailing], 10)
                Spacer(minLength: 5)
                VStack {
                    if #available(macOS 14, *) {
                        Toggle(isOn: $recordMic) {
                            Text("Record microphone")
                        }.onChange(of: recordMic) {
                            Task { await performMicCheck() }
                        }
                    } else {
                        Toggle(isOn: $recordMic) {
                            Text("Record microphone")
                        }.onChange(of: recordMic) { _ in
                            Task { await performMicCheck() }
                        }
                    }
                    Text("Mixed into a single audio track. Uses the currently set input device.")
                        .font(.footnote).foregroundColor(Color.gray)
                }.frame(maxWidth: .infinity).padding(10)
            }.onAppear {
                recordMic = recordMic && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            }.padding(10)
        }

        func performMicCheck() async {
            guard recordMic == true else { return }
            if await AVCaptureDevice.requestAccess(for: .audio) { return }

            recordMic = false
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Azayaka needs permissions!".local
                alert.informativeText = "Azayaka needs permission to record your microphone to do this.".local
                alert.addButton(withTitle: "Open Settings".local)
                alert.addButton(withTitle: "No thanks".local)
                alert.alertStyle = .warning
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }
            }
        }
    }

    struct OutputSettings: View {
        @AppStorage(kFileName)      private var fileName: String = "Recording at %t"
        @AppStorage(kSaveDirectory) private var saveDirectory: String?
        @AppStorage(kAutoClipboard) private var autoClipboard: Bool = false
        @State private var fileNameLength = 0
        private let dateFormatter = DateFormatter()

        var body: some View {
            VStack {
                GroupBox {
                    VStack {
                        Form {
                            TextField("File name", text: $fileName).frame(maxWidth: 250)
                                .onChange(of: fileName) { newText in
                                    fileNameLength = getFileNameLength(newText)
                                }
                                .onAppear {
                                    dateFormatter.dateFormat = "y-MM-dd HH.mm.ss"
                                    fileNameLength = getFileNameLength(fileName)
                                }
                                .foregroundStyle(fileNameLength > NAME_MAX ? .red : .primary)
                        }
                        Text("\"%t\" will be replaced with the recording's start time.")
                            .font(.subheadline).foregroundColor(Color.gray)
                    }.padding(10).frame(maxWidth: .infinity)
                }.padding([.top, .leading, .trailing], 10)
                GroupBox {
                    VStack(spacing: 15) {
                        VStack(spacing: 2) {
                            Button("Select output directory", action: updateOutputDirectory)
                            Text(String(format: "Currently set to \"%@\"".local, (saveDirectory != nil) ? URL(fileURLWithPath: saveDirectory!).lastPathComponent : "an unknown path - please set a new one"))
                                .font(.subheadline).foregroundColor(Color.gray)
                        }
                        VStack {
                            Toggle(isOn: $autoClipboard) {
                                Text("Automatically copy recordings to clipboard")
                            }
                        }
                    }.padding(10).frame(maxWidth: .infinity)
                }.padding([.leading, .trailing, .bottom], 10)
            }.onTapGesture {
                DispatchQueue.main.async {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
            }
        }

        func getFileNameLength(_ fileName: String) -> Int {
            return fileName.replacingOccurrences(of: "%t", with: dateFormatter.string(from: Date())).count
        }

        func updateOutputDirectory() {
            let openPanel = NSOpenPanel()
            openPanel.canChooseFiles = false
            openPanel.canChooseDirectories = true
            openPanel.allowedContentTypes = []
            openPanel.allowsOtherFileTypes = false
            if openPanel.runModal() == NSApplication.ModalResponse.OK {
                saveDirectory = openPanel.urls.first?.path
            }
        }
    }

    struct ShortcutSettings: View {
        var body: some View {
            VStack {
                GroupBox {
                    Form {
                        KeyboardShortcuts.Recorder("Record system audio".local, name: .recordSystemAudio)
                            .padding([.leading, .trailing], 10).padding(.bottom, 4)
                    }.frame(alignment: .center).padding([.leading, .trailing], 2).padding(.top, 10).frame(maxWidth: .infinity)
                    Text("Recordings can be stopped with the same shortcut.")
                        .font(.subheadline).foregroundColor(Color.gray).padding(.bottom, 10)
                }.padding(10)
            }
        }
    }

    struct OtherSettings: View {
        @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
        @AppStorage(kUpdateCheck)    private var updateCheck: Bool = true
        @AppStorage(kCountdownSecs)  private var countDown: Int = 0

        private var numberFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimum = 0
            formatter.maximum = 99
            return formatter
        }

        var body: some View {
            VStack {
                GroupBox {
                    VStack(alignment: .leading) {
                        Toggle(isOn: $launchAtLogin) {
                            Text("Launch at login")
                        }.onChange(of: launchAtLogin) { newValue in
                            do {
                                if newValue {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                print("Failed to \(newValue ? "enable" : "disable") launch at login: \(error.localizedDescription)")
                            }
                        }
                        Toggle(isOn: $updateCheck) {
                            Text("Check for updates at launch")
                        }
                    }.padding([.top, .leading, .trailing], 10).frame(width: 250)
                    Text("Azayaka will check [GitHub](https://github.com/Mnpn/Azayaka/releases) for new updates.")
                        .font(.footnote).foregroundColor(Color.gray).frame(maxWidth: .infinity).padding([.bottom, .leading, .trailing], 10)
                }.padding([.top, .leading, .trailing], 10)
                GroupBox {
                    VStack {
                        Form {
                            TextField("Countdown", value: $countDown, formatter: numberFormatter)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding([.leading, .trailing], 10)
                        }.frame(maxWidth: 200)
                        Text("Countdown to start recording, in seconds.")
                            .font(.subheadline).foregroundColor(Color.gray)
                    }.padding(10).frame(maxWidth: .infinity)
                }.padding([.leading, .trailing], 10)
                HStack {
                    Text("Azayaka \(getVersion()) (\(getBuild()))").foregroundColor(Color.secondary)
                    Spacer()
                    Text("https://mnpn.dev")
                }.padding(12).background { VisualEffectView() }.frame(height: 42)
            }
        }

        func getVersion() -> String {
            return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown".local
        }

        func getBuild() -> String {
            return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown".local
        }
    }

    struct VisualEffectView: NSViewRepresentable {
        func makeNSView(context: Context) -> NSVisualEffectView { return NSVisualEffectView() }
        func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
    }
}

#Preview {
    Preferences()
}

extension AppDelegate {
    @objc func openPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApp.mainMenu?.items.first?.submenu?.item(at: 2)?.performAction()
        } else if #available(macOS 13, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        for w in NSApplication.shared.windows {
            if w.level.rawValue == 0 || w.level.rawValue == 3 { w.level = .floating }
        }
    }
}

extension NSMenuItem {
    func performAction() {
        guard let menu else {
            return
        }
        menu.performActionForItem(at: menu.index(of: self))
    }
}
