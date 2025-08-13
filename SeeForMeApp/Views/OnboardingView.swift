//
//  OnboardingView.swift
//  SeeForMe
//
//  Created by Ronan M on 8/10/25.
//

import Foundation
import SwiftUI

struct OnboardingView: View {
    var onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to SeeForMe")
                .font(.largeTitle).bold()
                .accessibilityAddTraits(.isHeader)
            
            Text("Make sure VoiceOver or haptics are enabled. Then point your camera at an object. We'll tell you what it is and how far away it is.")
                .multilineTextAlignment(.center)
                .padding()
            
            Button(action: onDismiss) {
                Text("Get Started")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.cornerRadius(8))
                    .foregroundColor(.white)
            }
            .accessibilityHint("Closes onboarding and starts object detection")
        }
        .padding()
    }
}
