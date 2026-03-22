//
//  AppDelegate.swift
//  Koe
//
//  Created by Martin Persson on 2022-12-25.
//

import AVFoundation
import AVFAudio
import Cocoa
import KeyboardShortcuts
import ScreenCaptureKit
import UserNotifications
import SwiftUI

@main
struct Koe: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            Preferences()
                .fixedSize()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, SCStreamDelegate, SCStreamOutput {
    var stream: SCStream!
    var filePath: String!
    var audioFile: AVAudioFile?
    var audioSettings: [String : Any]!
    var updateTimer: Timer?
    var isRecording = false

    var statusItem: NSStatusItem!
    var menu = NSMenu()
    let info = NSMenuItem(title: "One moment, waiting on update".local, action: nil, keyEquivalent: "")
    let preferences = NSWindow()
    let ud = UserDefaults.standard

    var startTime: Date?
    var micSampleFIFO: [[Float]] = [[], []]
    let micFIFOLock = NSLock()
    var micConverter: AVAudioConverter?
    var micConverterInputFormat: AVAudioFormat?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        lazy var userDesktop = (NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true) as [String]).first!

        let saveDirectory = (UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") ?? userDesktop) as NSString

        ud.register(
            defaults: [
                Preferences.kAudioFormat: AudioFormat.aac.rawValue,
                Preferences.kAudioQuality: AudioQuality.high.rawValue,
                Preferences.kRecordMic: false,

                Preferences.kFileName: "Recording at %t".local,
                Preferences.kSaveDirectory: saveDirectory,
                Preferences.kAutoClipboard: false,

                Preferences.kWebhookEnabled: false,
                Preferences.kWebhookURL: "",

                Preferences.kCountdownSecs: 0
            ]
        )
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        statusItem.menu = menu
        menu.minimumWidth = 250
        createMenu()

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error { print("Notification authorisation denied: \(error.localizedDescription)") }
        }
    }

    func requestPermissions() {
        allowShortcuts(false)
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Koe needs permissions!".local
            alert.informativeText = "Koe needs screen recording permissions to capture system audio.".local
            alert.addButton(withTitle: "Open Settings".local)
            alert.addButton(withTitle: "Okay".local)
            alert.addButton(withTitle: "No thanks, quit".local)
            alert.alertStyle = .informational
            switch(alert.runModal()) {
                case .alertFirstButtonReturn:
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                case .alertThirdButtonReturn: NSApp.terminate(self)
                default: return
            }
            self.allowShortcuts(true)
        }
    }

    func copyToClipboard(_ content: [any NSPasteboardWriting]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(content)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        if isRecording {
            stopRecording()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}

extension String {
    var local: String { return NSLocalizedString(self, comment: "") }
}
