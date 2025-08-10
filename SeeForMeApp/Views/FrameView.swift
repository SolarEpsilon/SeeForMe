//
//  FrameView.swift
//  SeeForMe
//
//  Created by Ronan M on 7/18/25.
//

import Foundation
import SwiftUI

struct FrameView: View {
    var image: CGImage?
    // Label to identify image
    private let label = Text("frame")
    
    var body: some View {
        if let image = image {
            Image(image, scale: 1.0, orientation: .up, label: label)
        } else {
            Color.black
        }
    }
}

struct FrameView_Previews: PreviewProvider {
    static var previews: some View {
        FrameView()
    }
}
