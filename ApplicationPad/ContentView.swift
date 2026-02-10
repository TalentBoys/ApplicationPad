//
//  ContentView.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import SwiftUI

struct ContentView: View {
    let apps = AppScanner.scan()

    let columns = Array(
        repeating: GridItem(.flexible(), spacing: 20),
        count: 6
    )

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(apps) { app in
                    VStack {
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 64, height: 64)

                        Text(app.name)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .onTapGesture {
                        NSWorkspace.shared.open(app.url)
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

#Preview {
    ContentView()
}
