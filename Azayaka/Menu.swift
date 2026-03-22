//
//  Menu.swift
//  Azayaka
//
//  Created by Martin Persson on 2022-12-26.
//
import SwiftUI
import KeyboardShortcuts

extension AppDelegate: NSMenuDelegate {
    func createMenu() {
        menu.removeAllItems()
        menu.delegate = self

        if isRecording {
            menu.addItem(header("Recording Call Audio".local, size: 12))

            menu.addItem(NSMenuItem(title: "Stop Recording".local, action: #selector(stopRecording), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(info)

            updateTimer?.invalidate()
            updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                self.updateMenu()
            }
            RunLoop.current.add(updateTimer!, forMode: .common)
            updateTimer?.fire()
        } else {
            let audio = NSMenuItemWithIcon(icon: "waveform.circle.fill", title: "Record Call Audio".local, action: #selector(prepRecord))
            audio.identifier = NSUserInterfaceItemIdentifier(rawValue: "audio")
            menu.addItem(audio)
        }

        addMenuFooter(toMenu: menu)
        statusItem.menu = menu
    }

    func updateMenu() {
        if isRecording {
            updateIcon()
            info.attributedTitle = NSAttributedString(string: String(format: "Duration: %@\nFile size: %@".local, arguments: [getRecordingLength(), getRecordingSize()]))
        }
    }

    func header(_ title: String, size: CGFloat = 10) -> NSMenuItem {
        let headerItem: NSMenuItem
        if #available(macOS 14.0, *) {
            headerItem = NSMenuItem.sectionHeader(title: title.uppercased())
        } else {
            headerItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            headerItem.attributedTitle = NSAttributedString(string: title.uppercased(), attributes: [.font: NSFont.systemFont(ofSize: size, weight: .heavy)])
        }
        return headerItem
    }

    func addMenuFooter(toMenu menu: NSMenu) {
        menu.addItem(NSMenuItem.separator())
        if let updateNotice = UpdateHandler.createUpdateNotice() {
            menu.addItem(updateNotice)
        }
        menu.addItem(NSMenuItem(title: "Preferences…".local, action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit Azayaka".local, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    func menuWillOpen(_ menu: NSMenu) {
        allowShortcuts(false)
    }

    func menuDidClose(_ menu: NSMenu) {
        allowShortcuts(true)
    }

    func updateIcon() {
        if let button = statusItem.button {
            let iconView = NSHostingView(rootView: MenuBar(recordingStatus: isRecording))
            iconView.frame = NSRect(x: 0, y: 1, width: 33, height: 20)
            button.subviews = [iconView]
            button.frame = iconView.frame
            button.setAccessibilityLabel("Azayaka")
        }
    }

    @objc func openUpdatePage() {
        NSWorkspace.shared.open(URL(string: UpdateHandler.updateURL)!)
    }
}

class NSMenuItemWithIcon: NSMenuItem {
    init(icon: String, title: String, action: Selector?, keyEquivalent: String = "") {
        super.init(title: title, action: action, keyEquivalent: keyEquivalent)
        let attr = NSMutableAttributedString()
        let imageAttachment = NSTextAttachment()
        imageAttachment.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        attr.append(NSAttributedString(attachment: imageAttachment))
        attr.append(NSAttributedString(string: " \(title)"))
        self.attributedTitle = attr
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not a thing")
    }
}
