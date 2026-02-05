#!/usr/bin/env swift
import AppKit

// Create app icon using SF Symbols
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))

image.lockFocus()

// Background - rounded rect with gradient
let bgRect = NSRect(x: 0, y: 0, width: size, height: size)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 220, yRadius: 220)

let gradient = NSGradient(colors: [
    NSColor(red: 0.1, green: 0.8, blue: 0.4, alpha: 1.0),
    NSColor(red: 0.0, green: 0.6, blue: 0.3, alpha: 1.0)
])!
gradient.draw(in: bgPath, angle: -45)

// Battery symbol
if let symbol = NSImage(systemSymbolName: "battery.100.bolt", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: 400, weight: .medium)
    let configured = symbol.withSymbolConfiguration(config)!

    let symbolSize = configured.size
    let x = (size - symbolSize.width) / 2
    let y = (size - symbolSize.height) / 2

    configured.draw(
        in: NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )
}

image.unlockFocus()

// Generate icns
let iconsetPath = "/tmp/AppIcon.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetPath)
try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

for (name, s) in sizes {
    let resized = NSImage(size: NSSize(width: s, height: s))
    resized.lockFocus()
    image.draw(
        in: NSRect(x: 0, y: 0, width: s, height: s),
        from: NSRect(x: 0, y: 0, width: size, height: size),
        operation: .copy,
        fraction: 1.0
    )
    resized.unlockFocus()

    if let tiff = resized.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiff),
       let png = bitmap.representation(using: .png, properties: [:]) {
        let path = "\(iconsetPath)/\(name).png"
        try! png.write(to: URL(fileURLWithPath: path))
    }
}

print("Iconset created at \(iconsetPath)")
