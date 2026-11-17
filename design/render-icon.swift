import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
let c = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
c.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x*1024, y: (1-y)*1024) }
c.move(to: pt(0.26,0.80)); c.addLine(to: pt(0.26,0.23)); c.addLine(to: pt(0.52,0.23)); c.addCurve(to: pt(0.52,0.55), control1: pt(0.83,0.23), control2: pt(0.83,0.55)); c.addLine(to: pt(0.26,0.55)); c.move(to: pt(0.48,0.55)); c.addLine(to: pt(0.76,0.80)); c.move(to: pt(0.59,0.79)); c.addLine(to: pt(0.76,0.80)); c.addLine(to: pt(0.74,0.63)); c.setLineWidth(78); c.setLineCap(.round); c.setLineJoin(.round); c.setStrokeColor(CGColor(red: 0.88, green: 0.10, blue: 0.19, alpha: 1)); c.strokePath()
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(d, c.makeImage()!, nil)
assert(CGImageDestinationFinalize(d))
