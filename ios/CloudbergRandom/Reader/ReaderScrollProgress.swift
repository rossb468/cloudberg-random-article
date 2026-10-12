import SwiftUI

extension View {
    /// Reports how far a scroll view is scrolled, as a fraction of its
    /// scrollable height, every time it moves — so a percentage read can follow
    /// the scroll instead of only changing when the top paragraph does.
    ///
    /// Needs iOS 18's scroll geometry; on iOS 17 the reader falls back to the
    /// top paragraph's position.
    @ViewBuilder
    func onReaderScrollProgress(_ action: @escaping (Double) -> Void) -> some View {
        if #available(iOS 18.0, *) {
            onScrollGeometryChange(for: Double.self) { geometry in
                let scrollable = geometry.contentSize.height - geometry.containerSize.height
                guard scrollable > 1 else { return 0 }
                let offset = geometry.contentOffset.y + geometry.contentInsets.top
                return min(max(offset / scrollable, 0), 1)
            } action: { _, progress in
                action(progress)
            }
        } else {
            self
        }
    }
}
