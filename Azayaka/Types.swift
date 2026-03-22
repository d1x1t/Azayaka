//
//  Types.swift
//  Azayaka
//
//  Created by Martin Persson on 2022-12-27.
//

import Foundation
import KeyboardShortcuts

enum AudioQuality: Int {
    case normal = 128, good = 192, high = 256, extreme = 320
}

enum AudioFormat: String {
    case aac, alac, flac, opus
}

struct GHRelease: Decodable {
    let tag_name: String
}

extension KeyboardShortcuts.Name {
    static let recordSystemAudio = Self("recordSystemAudio")
}

// https://stackoverflow.com/a/73232453
extension utsname {
    static var sMachine: String {
        var utsname = utsname()
        uname(&utsname)
        return withUnsafePointer(to: &utsname.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
    }
    static var isAppleSilicon: Bool {
        sMachine == "arm64"
    }
}
