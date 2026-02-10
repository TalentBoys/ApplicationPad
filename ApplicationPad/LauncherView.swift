//
//  LauncherView.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import SwiftUI

struct LauncherView: View {
    var body: some View {
        ZStack {
            VisualEffectView()

            AppGridView(showSettingsHint: false)
        }
        .frame(width: 700, height: 500)
    }
}

#Preview {
    LauncherView()
}
