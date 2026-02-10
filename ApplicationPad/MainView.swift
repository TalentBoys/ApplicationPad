//
//  MainView.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import SwiftUI

struct MainView: View {
    var body: some View {
        AppGridView(showSettingsHint: true, isLauncher: false)
            .frame(minWidth: 900, minHeight: 600)
            .background(VisualEffectView())
    }
}

#Preview {
    MainView()
}
