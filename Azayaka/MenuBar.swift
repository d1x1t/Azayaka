//
//  MenuBar.swift
//  Azayaka
//
//  Created by apple on 2024/4/14.
//

import SwiftUI
import Foundation

struct MenuBar: View {
    @State var recordingStatus: Bool!
    @State var recordingLength = "00:00"

    var body: some View {
        ZStack {
            if recordingStatus {
                Rectangle()
                    .cornerRadius(3)
                    .opacity(0.1)
            }
            Image(systemName: "app.fill")
                .foregroundStyle(recordingStatus ? .blue : .primary)
        }
    }
}

#Preview {
    MenuBar()
}
