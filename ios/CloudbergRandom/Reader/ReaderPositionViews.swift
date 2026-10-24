import SwiftUI

/// Offered after the position jumps far from where you were reading.
struct ReturnPill: View {
    let jump: JumpDetector.Jump
    let palette: ReaderSettings.Palette
    var onReturn: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onReturn) {
                Label("Back to \(Int((jump.fromProgress * 100).rounded()))%", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
                    .padding(.leading, 16)
                    .padding(.trailing, 10)
                    .padding(.vertical, 10)
            }
            Divider().frame(height: 20)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .accessibilityLabel("Stay here")
        }
        .foregroundStyle(palette.text)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(palette.accent.opacity(0.5)))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }
}
