// 生成 App 图标（1024×1024，和网页左上角的「租」字标志一样）：swift tools/make_icon.swift 输出路径
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let rect = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(starting: NSColor(srgbRed: 0.427, green: 0.420, blue: 0.969, alpha: 1),
           ending: NSColor(srgbRed: 0.659, green: 0.333, blue: 0.969, alpha: 1))!.draw(in: rect, angle: -45)
let font = NSFont(name: "PingFangSC-Semibold", size: 560) ?? NSFont.boldSystemFont(ofSize: 560)
let text = NSAttributedString(string: "租", attributes: [.font: font, .foregroundColor: NSColor.white])
let b = text.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading])
text.draw(at: NSPoint(x: (CGFloat(size) - b.width) / 2, y: (CGFloat(size) - b.height) / 2 - 10))
NSGraphicsContext.restoreGraphicsState()
// iOS 图标不能带透明通道：生成后按 ios/README.md 用 sips 转一下
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("写好了 \(out)")
