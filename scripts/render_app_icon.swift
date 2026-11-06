import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// The approved artwork stays untouched. Only its macOS icon presentation changes.
guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: swift scripts/render_app_icon.swift input.png output.png")
}
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil),
      artwork.width == 1024, artwork.height == 1024,
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: 1024, height: 1024,
          bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Expected a readable 1024 × 1024 source icon")
}

// Give a legacy ICNS icon breathing room and smooth, continuous macOS corners.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let outline = RoundedRectangle(cornerRadius: 185, style: .continuous).path(in: tile).cgPath
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
context.interpolationQuality = .high
context.addPath(outline)
context.clip()
context.draw(artwork, in: tile)

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Could not create the macOS icon")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Could not save the macOS icon")
}
