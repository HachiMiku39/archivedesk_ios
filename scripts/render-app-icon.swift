import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Original geometric ArchiveDesk artwork; no third-party character imagery.
let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: size * 4, space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let gradient = CGGradient(colorsSpace: colorSpace, colors: [
    CGColor(red: 0.08, green: 0.20, blue: 0.39, alpha: 1),
    CGColor(red: 0.10, green: 0.52, blue: 0.68, alpha: 1)
] as CFArray, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 700, y: 1024),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
func rounded(_ rect: CGRect, radius: CGFloat, color: CGColor) {
    context.setFillColor(color)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
}
rounded(CGRect(x: 182, y: 181, width: 660, height: 574), radius: 54,
        color: CGColor(gray: 0, alpha: 0.17))
rounded(CGRect(x: 198, y: 222, width: 628, height: 508), radius: 48,
        color: CGColor(red: 0.91, green: 0.96, blue: 0.98, alpha: 1))
let light = CGColor(red: 0.72, green: 0.87, blue: 0.92, alpha: 1)
let dark = CGColor(red: 0.12, green: 0.34, blue: 0.49, alpha: 1)
rounded(CGRect(x: 162, y: 645, width: 700, height: 137), radius: 34, color: light)
rounded(CGRect(x: 460, y: 252, width: 104, height: 488), radius: 12, color: dark)
for index in 0..<8 {
    let x = index % 2 == 0 ? 470 : 510
    rounded(CGRect(x: x, y: 303 + index * 43, width: 44, height: 24), radius: 4, color: light)
}
rounded(CGRect(x: 479, y: 671, width: 66, height: 81), radius: 15, color: CGColor(gray: 1, alpha: 1))
rounded(CGRect(x: 496, y: 687, width: 32, height: 32), radius: 7, color: dark)
let destination = CommandLine.arguments.dropFirst().first ?? "ArchiveDeskIOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let writer = CGImageDestinationCreateWithURL(URL(fileURLWithPath: destination) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(writer, context.makeImage()!, nil)
guard CGImageDestinationFinalize(writer) else { fatalError("PNG write failed") }
