//
//  Shortcuts.swift
//  Azayaka
//
//  Created by Martin Persson on 2024-08-11.
//

import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        KeyboardShortcuts.onKeyDown(for: .recordSystemAudio) { [self] in
            Task { await toggleRecording() }
        }
    }

    func toggleRecording() async {
        appDelegate.allowShortcuts(false)
        guard CountdownManager.shared.timer == nil else {
            CountdownManager.shared.finishCountdown(startRecording: false)
            appDelegate.allowShortcuts(true)
            return
        }
        if !appDelegate.isRecording {
            let menuItem = NSMenuItem()
            menuItem.identifier = NSUserInterfaceItemIdentifier("audio")
            appDelegate.prepRecord(menuItem)
        } else {
            appDelegate.stopRecording()
        }
    }
}

extension AppDelegate {
    func allowShortcuts(_ allow: Bool) {
        if allow {
            KeyboardShortcuts.enable(.recordSystemAudio)
        } else {
            KeyboardShortcuts.disable(.recordSystemAudio)
        }
    }
}
