
import AppKit
// Exports the SF Symbol "apple.logo" exactly as macOS draws it (no hand drawing): a 2048 px PNG and a vector PDF.
let out = CommandLine.arguments[1]
guard let sym = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil)?
    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 1000, weight: .regular)) else { fatalError("apple.logo not found") }
let s = sym.size
print("symbol size", s)
let px: CGFloat = 2048
let scale = (px * 0.9) / max(s.width, s.height)
let w = s.width * scale, h = s.height * scale
let rect = NSRect(x: (px - w) / 2, y: (px - h) / 2, width: w, height: h)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
sym.draw(in: rect)
NSColor.black.set(); rect.fill(using: .sourceAtop)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out + "/apple.logo-2048.png"))
var box = CGRect(x: 0, y: 0, width: s.width, height: s.height)
let ctx = CGContext(URL(fileURLWithPath: out + "/apple.logo.pdf") as CFURL, mediaBox: &box, nil)!
ctx.beginPDFPage(nil)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
sym.draw(in: box)
NSGraphicsContext.restoreGraphicsState()
ctx.endPDFPage(); ctx.closePDF()
print("exported apple.logo")
