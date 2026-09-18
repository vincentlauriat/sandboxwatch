#!/usr/bin/env swift

import AppKit
import Foundation

// Generates the macOS AppIcon for SandboxWatch.
//
//   swift Scripts/make-icon.swift preview
//       → /tmp/sbw-icon-preview.png at 1024×1024, opened in Preview
//   swift Scripts/make-icon.swift all <output.appiconset>
//       → the ten sizes macOS requires, plus Contents.json
//
// The mark is drawn, not lettered: a lens — an outer ring, an inner aperture, and a highlight —
// on a deep blue field. It reads as "watching" at 16 pt, which a glyph or a word does not.
// SF Symbols are deliberately not used: Apple's licence does not allow them in an app icon.

let top = NSColor(red: 0.16, green: 0.42, blue: 0.78, alpha: 1)
let bottom = NSColor(red: 0.06, green: 0.13, blue: 0.32, alpha: 1)

func renderIcon(size: Int) -> Data? {
    let side = CGFloat(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icons sit inside a margin rather than filling the square.
    let inset = side * 0.06
    let plate = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let radius = plate.width * 0.225
    let shape = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)
    NSGradient(starting: top, ending: bottom)?.draw(in: shape, angle: -90)

    // The lens: a ring, an aperture, and one highlight so it does not read as a flat target.
    let centre = NSPoint(x: plate.midX, y: plate.midY)
    let outer = plate.width * 0.30
    let ringWidth = plate.width * 0.055

    let ring = NSBezierPath(ovalIn: NSRect(
        x: centre.x - outer, y: centre.y - outer, width: outer * 2, height: outer * 2))
    ring.lineWidth = ringWidth
    NSColor.white.withAlphaComponent(0.95).setStroke()
    ring.stroke()

    let aperture = plate.width * 0.135
    NSColor.white.withAlphaComponent(0.95).setFill()
    NSBezierPath(ovalIn: NSRect(
        x: centre.x - aperture, y: centre.y - aperture,
        width: aperture * 2, height: aperture * 2)).fill()

    let glint = plate.width * 0.042
    NSColor(red: 0.16, green: 0.42, blue: 0.78, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(
        x: centre.x - aperture * 0.35 - glint, y: centre.y + aperture * 0.25,
        width: glint * 2, height: glint * 2)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

func write(_ data: Data, to path: String) {
    try? data.write(to: URL(fileURLWithPath: path))
    print("  \((path as NSString).lastPathComponent)")
}

let macIcons: [(size: Int, scale: Int, render: Int)] = [
    (16, 1, 16), (16, 2, 32),
    (32, 1, 32), (32, 2, 64),
    (128, 1, 128), (128, 2, 256),
    (256, 1, 256), (256, 2, 512),
    (512, 1, 512), (512, 2, 1024),
]

let arguments = CommandLine.arguments
switch arguments.count > 1 ? arguments[1] : "preview" {
case "all":
    guard arguments.count > 2 else {
        FileHandle.standardError.write(Data("usage: make-icon.swift all <output.appiconset>\n".utf8))
        exit(1)
    }
    let out = arguments[2]
    try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

    var images: [[String: String]] = []
    for (size, scale, render) in macIcons {
        let name = "icon_\(size)x\(size)\(scale == 1 ? "" : "@\(scale)x").png"
        guard let data = renderIcon(size: render) else { continue }
        write(data, to: "\(out)/\(name)")
        images.append([
            "idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name,
        ])
    }
    let contents: [String: Any] = [
        "images": images,
        "info": ["version": 1, "author": "xcode"],
    ]
    let json = try! JSONSerialization.data(
        withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    write(json, to: "\(out)/Contents.json")

default:
    let path = "/tmp/sbw-icon-preview.png"
    guard let data = renderIcon(size: 1024) else { exit(1) }
    write(data, to: path)
    NSWorkspace.shared.open(URL(fileURLWithPath: path))
}
