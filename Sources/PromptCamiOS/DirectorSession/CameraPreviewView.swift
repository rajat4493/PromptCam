import AVFoundation
import UIKit
import SwiftUI

/// The operator's viewfinder.
///
/// STATICALLY_REVIEWED — REQUIRES_MAC.
///
/// Wraps `AVCaptureVideoPreviewLayer` because SwiftUI has no native equivalent.
/// The layer is resized in `layoutSubviews` rather than via a frame observer,
/// so it tracks arbitrary scene-geometry changes — rotation, Split View,
/// resizing, and folding — without any hardcoded dimension.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }

    /// A `UIView` whose backing layer *is* the preview layer.
    final class PreviewContainerView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // Safe by construction: `layerClass` guarantees the type.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

/// Microphone level indicator.
///
/// Shows whether audio is actually arriving, which is the single most common
/// silent failure in a one-person shoot.
struct AudioLevelMeter: View {
    /// Normalised 0...1.
    let level: Double
    /// Whether capture is live. A meter that moves when nothing is recording
    /// would be misleading.
    let isActive: Bool

    private let segmentCount = 12

    var body: some View {
        HStack(spacing: Theme.Space.hairline) {
            ForEach(0..<segmentCount, id: \.self) { index in
                let threshold = Double(index + 1) / Double(segmentCount)
                RoundedRectangle(cornerRadius: 1)
                    .fill(color(for: threshold))
                    .frame(width: 3)
            }
        }
        .frame(height: 20)
        .animation(.linear(duration: 0.1), value: level)
        .accessibilityElement()
        .accessibilityLabel("Microphone level")
        .accessibilityValue(accessibilityDescription)
        // Level changes many times a second; announcing each one would make
        // VoiceOver unusable.
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func color(for threshold: Double) -> Color {
        guard isActive, level >= threshold else {
            return Theme.Palette.surfaceStrong
        }
        // The top sixth reads as "too hot", which is actionable.
        if threshold > 0.85 { return Theme.Palette.failure }
        if threshold > 0.7 { return Theme.Palette.warning }
        return Theme.Palette.ready
    }

    private var accessibilityDescription: String {
        guard isActive else { return "Not recording" }
        if level < 0.05 { return "No sound detected" }
        if level > 0.85 { return "Very loud" }
        return "\(Int(level * 100)) percent"
    }
}
