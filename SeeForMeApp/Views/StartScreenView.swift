//
//  StartScreenView.swift
//  SeeForMe
//
//  Created by Ronan M on 7/27/25.
//

import Foundation
import SwiftUI

struct StartScreenView: View {
    @State private var showDetection = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [.blue.opacity(0.7), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Text("🔍 SeeForMe")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)

                Text("Your AI-powered visual assistant\n— on device, in real time.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal)

                Button(action: {
                    showDetection = true
                }) {
                    Text("Start Detection")
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(radius: 10)
                }
                .padding(.horizontal, 40)
            }
            .padding()
        }
        .fullScreenCover(isPresented: $showDetection) {
            DetectionViewControllerWrapper()
        }
    }
}
