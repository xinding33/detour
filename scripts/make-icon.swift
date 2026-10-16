// Draws AppIcon.icns at build time, so there are no binary assets in the repo.
// Usage: swift scripts/make-icon.swift OUTPUT.icns
import AppKit

let symbolName = "arrow.triangle.branch"
let background = NSColor(calibratedRed: 0.10, green: 0.20, blue: 0.32, alpha: 1)

let output = CommandLine.arguments[1]
let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let side = CGFloat(size * scale)
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        background.setFill()
        NSBezierPath(roundedRect: NSRect(x: side * 0.05, y: side * 0.05, width: side * 0.9, height: side * 0.9),
                     xRadius: side * 0.2, yRadius: side * 0.2).fill()
        let configuration = NSImage.SymbolConfiguration(pointSize: side * 0.5, weight: .medium)
            .applying(.init(paletteColors: [.white]))
        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) {
            // Keep the symbol's proportions, centered.
            let fit = min(side * 0.6 / symbol.size.width, side * 0.6 / symbol.size.height)
            let width = symbol.size.width * fit, height = symbol.size.height * fit
            symbol.draw(in: NSRect(x: (side - width) / 2, y: (side - height) / 2, width: width, height: height))
        }
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", folder.path, "-o", output]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { exit(1) }
