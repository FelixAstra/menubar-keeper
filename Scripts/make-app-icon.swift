#!/usr/bin/env swift
// Fits the app icon artwork into macOS's rounded-square (squircle) grid and writes
// `Resources/MenuBarKeeper.icns`.
//
// Why this step exists
// --------------------
// The design export is a full-bleed 1024×1024 **opaque square** (all four corners have
// alpha 255). The macOS app icon grid is "1024 canvas, 824×824 content centred, corners
// transparent", and **the system does not apply that shape to third-party apps**. Dropped
// into the bundle as-is, the icon shows up in Finder as a plain white square.
//
// (Xcode 14+ applies the mask automatically for an asset catalog "Single Size" app icon.
// This project builds with `swiftc` and a hand-assembled bundle, so there is no asset
// catalog doing that work — it has to be done here.)
//
// Why Swift and not Python
// ------------------------
// The first version of this script used Pillow, which is not part of macOS: a fresh clone
// had to `pip install` it before `make icon` would do anything, and the tracked artwork
// lived in a gitignored folder, so the input was missing too. Both failure modes are gone
// here — the artwork is committed as `Supporting/AppIconSource.png`, and this script needs
// nothing but the Swift toolchain and `iconutil`, both of which are already required to
// build the app at all.
//
// Usage
// -----
//     make icon                                     # the usual way
//     swift Scripts/make-app-icon.swift             # same, invoked directly
//     swift Scripts/make-app-icon.swift <source> <out.icns>
//
// Re-run it after changing the icon design; `Scripts/build.sh` copies the result into the
// bundle.

import CoreGraphics
import Foundation
import ImageIO

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let root = scriptURL.deletingLastPathComponent().deletingLastPathComponent()

let defaultSource = root.appendingPathComponent("Supporting/AppIconSource.png")
let defaultOutput = root.appendingPathComponent("Resources/MenuBarKeeper.icns")
let iconsetDir = root.appendingPathComponent("build/MenuBarKeeper.iconset")

let canvas = 1024       // canvas edge length
let content = 824       // Big Sur icon grid: 824×824 content, 100pt margin on each side
let offset = (canvas - content) / 2
let squircleN = 5.0     // superellipse exponent; n=5 approximates Apple's squircle

/// iconset filenames required by iconutil -> pixel edge length
let sizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-app-icon: \(message)\n".utf8))
    exit(1)
}

/// A size×size superellipse path. Core Graphics anti-aliases the clip, so unlike the
/// raster version this does not need supersampling.
func squirclePath(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let radius = rect.width / 2
    let cx = rect.midX
    let cy = rect.midY
    let steps = 4096
    for i in 0..<steps {
        let t = 2 * Double.pi * Double(i) / Double(steps)
        let cosT = cos(t)
        let sinT = sin(t)
        let x = radius * copysign(pow(abs(cosT), 2 / squircleN), cosT)
        let y = radius * copysign(pow(abs(sinT), 2 / squircleN), sinT)
        let point = CGPoint(x: cx + x, y: cy + y)
        i == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

func makeContext(pixels: Int) -> CGContext {
    guard let context = CGContext(data: nil,
                                  width: pixels,
                                  height: pixels,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fail("could not create a \(pixels)×\(pixels) bitmap context")
    }
    context.interpolationQuality = .high
    return context
}

/// Downscales by repeated halving. A single 1024 -> 16 step throws away too many samples
/// and the 16pt icon comes out muddy; halving keeps every step inside the filter's reach.
func downscale(_ image: CGImage, to pixels: Int) -> CGImage {
    var current = image
    var side = image.width
    while side / 2 >= pixels {
        let next = side / 2
        let context = makeContext(pixels: next)
        context.draw(current, in: CGRect(x: 0, y: 0, width: next, height: next))
        guard let scaled = context.makeImage() else {
            fail("could not downscale to \(next)px")
        }
        current = scaled
        side = next
    }
    if side != pixels {
        let context = makeContext(pixels: pixels)
        context.draw(current, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        guard let scaled = context.makeImage() else {
            fail("could not resize to \(pixels)px")
        }
        current = scaled
    }
    return current
}

// MARK: - Read the artwork

let sourcePath = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : defaultSource
let outputPath = CommandLine.arguments.count > 2
    ? URL(fileURLWithPath: CommandLine.arguments[2])
    : defaultOutput

guard FileManager.default.fileExists(atPath: sourcePath.path) else {
    fail("source artwork not found: \(sourcePath.path)")
}
guard let sourceHandle = CGImageSourceCreateWithURL(sourcePath as CFURL, nil),
      let sourceImage = CGImageSourceCreateImageAtIndex(sourceHandle, 0, nil) else {
    fail("could not read \(sourcePath.path) as an image")
}

// MARK: - Composite onto the icon grid

let square = makeContext(pixels: canvas)
// Everything outside the squircle stays transparent: clipping here is the whole point.
square.saveGState()
square.addPath(squirclePath(in: CGRect(x: offset, y: offset, width: content, height: content)))
square.clip()
square.draw(sourceImage, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
square.restoreGState()

guard let master = square.makeImage() else {
    fail("could not render the masked master image")
}

// MARK: - Write the .iconset and convert it

let fileManager = FileManager.default
if fileManager.fileExists(atPath: iconsetDir.path) {
    try? fileManager.removeItem(at: iconsetDir)
}
try? fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

for entry in sizes {
    let image = entry.px == canvas ? master : downscale(master, to: entry.px)
    let file = iconsetDir.appendingPathComponent(entry.name) as CFURL
    guard let destination = CGImageDestinationCreateWithURL(file, "public.png" as CFString, 1, nil) else {
        fail("could not create \(entry.name)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fail("could not write \(entry.name)")
    }
}

try? fileManager.createDirectory(at: outputPath.deletingLastPathComponent(),
                                 withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDir.path, "-o", outputPath.path]
try? iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fail("iconutil exited with status \(iconutil.terminationStatus)")
}

print("Wrote \(outputPath.path)")
