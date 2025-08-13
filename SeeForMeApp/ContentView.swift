//
//  ContentView.swift
//  See For Me
//
//  Created by Ronan M on 7/7/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        HostedViewController()
            .ignoresSafeArea()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
