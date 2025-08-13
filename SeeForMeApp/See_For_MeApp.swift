//
//  See_For_MeApp.swift
//  See For Me
//
//  Created by Ronan M on 7/7/25.
//

import SwiftUI

@main
struct See_For_MeApp: App {
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding = false
    
    var body: some Scene {
        WindowGroup {
            if hasSeenOnboarding {
                StartScreenView()
            } else {
                OnboardingView {
                    hasSeenOnboarding = true
                }
            }
        }
    }
}
