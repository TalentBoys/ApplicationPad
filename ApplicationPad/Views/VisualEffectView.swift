//
//  VisualEffectView.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct VisualEffectView: NSViewRepresentable {
    var style: String = "default"

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        applyStyle(to: view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        applyStyle(to: nsView)
    }

    private func applyStyle(to view: NSVisualEffectView) {
        switch style {
        case "classicBlur":
            view.material = .fullScreenUI
            view.appearance = NSAppearance(named: .darkAqua)
        default:
            view.material = .hudWindow
            view.appearance = nil
        }
    }
}

struct DesktopBlurBackground: View {
    @State private var wallpaperImage: NSImage?

    var body: some View {
        ZStack {
            if let image = wallpaperImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            } else {
                Color.black
            }
            Color.black.opacity(0.4)
        }
        .onAppear {
            DispatchQueue.global(qos: .userInitiated).async {
                let image = captureAndBlurDesktop()
                DispatchQueue.main.async {
                    wallpaperImage = image
                }
            }
        }
    }

    private func captureAndBlurDesktop() -> NSImage? {
        guard let screen = NSScreen.main else { return nil }

        if let wallpaperURL = NSWorkspace.shared.desktopImageURL(for: screen),
           let ciImage = loadCIImage(from: wallpaperURL) {
            return applyGaussianBlur(to: ciImage, radius: 40, screenSize: screen.frame.size)
        }

        return nil
    }

    private func loadCIImage(from url: URL) -> CIImage? {
        // Handle dynamic wallpapers (.heic) and static images
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }
        return CIImage(cgImage: cgImage)
    }

    private func applyGaussianBlur(to image: CIImage, radius: Double, screenSize: CGSize) -> NSImage? {
        let context = CIContext(options: [.useSoftwareRenderer: false])

        // Scale image to screen size for proper aspect fill
        let scaleX = screenSize.width / image.extent.width
        let scaleY = screenSize.height / image.extent.height
        let scale = max(scaleX, scaleY)
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Crop to screen size
        let cropRect = CGRect(
            x: (scaledImage.extent.width - screenSize.width) / 2,
            y: (scaledImage.extent.height - screenSize.height) / 2,
            width: screenSize.width,
            height: screenSize.height
        )
        let croppedImage = scaledImage.cropped(to: cropRect)

        // Apply clamp to avoid dark edges from blur
        let clampFilter = CIFilter.affineClamp()
        clampFilter.inputImage = croppedImage
        clampFilter.transform = .identity
        guard let clampedImage = clampFilter.outputImage else { return nil }

        // Apply Gaussian blur
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = clampedImage
        blurFilter.radius = Float(radius)
        guard let blurredImage = blurFilter.outputImage else { return nil }

        // Crop back to original bounds
        let finalImage = blurredImage.cropped(to: croppedImage.extent)

        guard let cgResult = context.createCGImage(finalImage, from: finalImage.extent) else { return nil }
        return NSImage(cgImage: cgResult, size: screenSize)
    }
}
