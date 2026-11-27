import SwiftUI

/// Keeps the scroll viewport full-height while letting the first and last rows
/// scroll clear of the floating controls.
struct FloatingConversationBars<Content: View, Top: View, Bottom: View>: View {
    @State private var topHeight: CGFloat = 0
    @State private var bottomHeight: CGFloat = 0

    @ViewBuilder let content: (EdgeInsets) -> Content
    @ViewBuilder let top: () -> Top
    @ViewBuilder let bottom: () -> Bottom

    var body: some View {
        content(EdgeInsets(top: topHeight, leading: 0, bottom: bottomHeight, trailing: 0))
            .overlay(alignment: .top) {
                topControls
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        topHeight = $0
                    }
            }
            .overlay(alignment: .bottom) {
                bottom()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        bottomHeight = $0
                    }
            }
    }

    @ViewBuilder
    private var topControls: some View {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            GlassEffectContainer(spacing: 4) {
                top()
            }
        } else {
            top()
        }
    }
}

extension View {
    @ViewBuilder
    func conversationGlass(
        in shape: some Shape,
        fallback: Color,
        border: Color,
        shadow: Color = .clear
    ) -> some View {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(fallback, in: shape)
                .overlay(shape.stroke(border, lineWidth: 1))
                .shadow(color: shadow, radius: 10, x: 0, y: 4)
        }
    }
}
