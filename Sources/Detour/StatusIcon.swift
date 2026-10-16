import AppKit
import DetourCore

/// The menu bar icons, drawn rather than taken from SF Symbols so the detour arrow reads at 18 pt.
/// Template images, so macOS tints them for light and dark menu bars.
enum StatusIcon {
    static func image(_ icon: Summary.Icon) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()
            switch icon {
            case .watching:
                arrow(x: 9).stroke()
            case .detouring:
                let path = line()
                path.move(to: NSPoint(x: 5.5, y: 15.8))
                path.line(to: NSPoint(x: 5.5, y: 11.5))
                path.curve(to: NSPoint(x: 7.8, y: 9.4), controlPoint1: NSPoint(x: 5.5, y: 10.1),
                           controlPoint2: NSPoint(x: 6.4, y: 9.4))
                path.line(to: NSPoint(x: 9.7, y: 9.4))
                path.curve(to: NSPoint(x: 12, y: 7.3), controlPoint1: NSPoint(x: 11.1, y: 9.4),
                           controlPoint2: NSPoint(x: 12, y: 8.7))
                path.line(to: NSPoint(x: 12, y: 3.4))
                path.move(to: NSPoint(x: 8.9, y: 6.3))
                path.line(to: NSPoint(x: 12, y: 3.2))
                path.line(to: NSPoint(x: 15.1, y: 6.3))
                path.stroke()
            case .paused:
                NSColor.black.withAlphaComponent(0.5).setStroke()
                arrow(x: 7).stroke()
                NSColor.black.setFill()
                NSBezierPath(roundedRect: NSRect(x: 11.6, y: 9.5, width: 1.9, height: 6), xRadius: 0.7, yRadius: 0.7).fill()
                NSBezierPath(roundedRect: NSRect(x: 14.8, y: 9.5, width: 1.9, height: 6), xRadius: 0.7, yRadius: 0.7).fill()
            case .problem:
                NSColor.black.withAlphaComponent(0.5).setStroke()
                arrow(x: 7).stroke()
                NSColor.black.setStroke()
                let bar = line(width: 2)
                bar.move(to: NSPoint(x: 14, y: 8.6))
                bar.line(to: NSPoint(x: 14, y: 12.8))
                bar.stroke()
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 14 - 1.15, y: 15.4 - 1.15, width: 2.3, height: 2.3)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = switch icon {
        case .watching: "Detour"
        case .detouring: "Detour: Tailscale is off"
        case .paused: "Detour: paused"
        case .problem: "Detour: can't control Tailscale"
        }
        return image
    }

    /// A straight arrow pointing up, centered on `x`.
    private static func arrow(x: CGFloat) -> NSBezierPath {
        let path = line()
        path.move(to: NSPoint(x: x, y: 15.5))
        path.line(to: NSPoint(x: x, y: 3.2))
        path.move(to: NSPoint(x: x - 3.4, y: 6.4))
        path.line(to: NSPoint(x: x, y: 3))
        path.line(to: NSPoint(x: x + 3.4, y: 6.4))
        return path
    }

    private static func line(width: CGFloat = 1.7) -> NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return path
    }
}
