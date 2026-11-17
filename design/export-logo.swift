import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil)!
let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
func png(_ size: Int) -> Data {
    let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    c.interpolationQuality = .high
    c.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    let data = NSMutableData()
    let out = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(out, c.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(out))
    return data as Data
}
let sizes = [16, 32, 48, 64, 128, 256]
let images = sizes.map(png)
var ico = Data()
func u16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { ico.append(contentsOf: $0) } }
func u32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { ico.append(contentsOf: $0) } }
u16(0); u16(1); u16(UInt16(sizes.count))
var offset = 6 + sizes.count * 16
for (size, data) in zip(sizes, images) {
    ico.append(contentsOf: [UInt8(size == 256 ? 0 : size), UInt8(size == 256 ? 0 : size), 0, 0])
    u16(1); u16(32); u32(UInt32(data.count)); u32(UInt32(offset)); offset += data.count
}
for data in images { ico.append(data) }
try ico.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
try png(1024).write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
