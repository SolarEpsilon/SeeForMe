//
//  SettingsView.swift
//  SeeForMe
//
//  Created by Ronan M on 8/9/25.
//

import Foundation
import SwiftUI

struct SettingsView: View {
    @AppStorage("enableVoice") var enableVoice = true
    @AppStorage("enableHaptics") var enableHaptics = true
    
    var body: some View {
        NavigationView {
            Form {
                Toggle("Enable Voice", isOn: $enableVoice)
                Toggle("Enable Haptics", isOn: $enableHaptics)
            }
            .navigationTitle("Settings")
        }
    }
}
