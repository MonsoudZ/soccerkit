import CoreGraphics

/// Shared helpers converting between normalized (0...1) board coordinates and the
/// absolute geometry of the rendered pitch. Used by the interactive canvas, the
/// individual markers, and the static export view.

func normalize(_ point: CGPoint, in rect: CGRect) -> CGPoint {
    CGPoint(
        x: clamp((point.x - rect.minX) / rect.width),
        y: clamp((point.y - rect.minY) / rect.height)
    )
}

func absolute(_ point: CGPoint, in rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
}

func absolute(_ normalizedRect: CGRect, in rect: CGRect) -> CGRect {
    CGRect(
        x: rect.minX + normalizedRect.minX * rect.width,
        y: rect.minY + normalizedRect.minY * rect.height,
        width: normalizedRect.width * rect.width,
        height: normalizedRect.height * rect.height
    )
}

func clamp(_ value: CGFloat, min: CGFloat = 0, max: CGFloat = 1) -> CGFloat {
    Swift.min(Swift.max(value, min), max)
}
