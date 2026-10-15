import SwiftUI
import Testing
@testable import ShinyScreenshot

/// Background mode: canvas maths, every backdrop and ratio, style extremes, and where the preview and toolbar land.
struct BackgroundTests {
    /// Half the toolbar's rendered width (708 pt, measured by ViewTests.toolbarFitsTheWidthItIsLaidOutFor).
    static let toolbarHalfWidth: CGFloat = 354
    static let toolbarHalfHeight: CGFloat = 20

    static let screens: [CGSize] = [CGSize(width: 800, height: 600), CGSize(width: 1024, height: 640), CGSize(width: 1280, height: 800),
                                    CGSize(width: 1440, height: 900), CGSize(width: 1512, height: 982), CGSize(width: 1920, height: 1080),
                                    CGSize(width: 2560, height: 1440), CGSize(width: 3008, height: 1692), CGSize(width: 6016, height: 3384)]

    static func selections(on size: CGSize) -> [CGRect] {
        let w = size.width, h = size.height
        return [CGRect(origin: .zero, size: size),                                      // full screen
                CGRect(x: w / 2 - 20, y: h / 2 - 15, width: 40, height: 30),             // small, centred
                CGRect(x: 0, y: 0, width: 10, height: 10),                               // top-left corner
                CGRect(x: w - 10, y: h - 10, width: 10, height: 10),                     // bottom-right corner
                CGRect(x: 0, y: 0, width: w, height: 50),                                // strip along the top
                CGRect(x: w - 50, y: 0, width: 50, height: h),                           // strip down the right
                CGRect(x: 100, y: 100, width: w * 0.6, height: h * 0.6)]                 // typical
    }

    func styled(_ size: CGSize, _ selection: CGRect) -> Session {
        let s = Fixture.screen(size.width, size.height)
        s.selection = selection
        s.phase = .editing
        s.style.enabled = true
        return s
    }

    @Test func canvasAddsPaddingThenWidensToTheRatio() {
        let s = styled(CGSize(width: 1440, height: 900), CGRect(x: 100, y: 100, width: 600, height: 400))
        for ratio in Ratio.allCases {
            for padding: CGFloat in [0, 48, 160] {
                s.style.ratio = ratio
                s.style.padding = padding
                let c = s.canvas, inner = CGSize(width: 600 + 2 * padding, height: 400 + 2 * padding)
                #expect(c.width >= inner.width && c.height >= inner.height, "\(ratio) \(padding)")
                if let r = ratio.value {
                    // Within one device pixel: the canvas is rounded to whole pixels.
                    #expect(abs(c.width - c.height * r) <= r / s.scale + 1e-9, "\(ratio) \(padding)")
                    #expect(c.width == inner.width || c.height == inner.height, "only one side grows")
                } else {
                    #expect(c == inner)
                }
            }
        }
        s.style.enabled = false
        #expect(s.canvas == CGSize(width: 600, height: 400))
    }

    @Test func everyBackdropFillsThePaddingAndTransparentStaysClear() throws {
        let gray = RGBA(r: 128, g: 128, b: 128, a: 255)
        let s = Fixture.session(Fixture.solid(400, 300, CGColor(srgbRed: 128 / 255, green: 128 / 255, blue: 128 / 255, alpha: 1)), scale: 1)
        s.selection = CGRect(x: 50, y: 50, width: 200, height: 100)
        s.phase = .editing
        s.style.enabled = true
        s.style.shadow = 0
        for b in Backdrop.allCases {
            s.style.backdrop = b
            let px = Pixels(try #require(s.render(), "\(b)"))
            #expect(px.width == 296 && px.height == 196, "\(b)")
            #expect(px[3, 3].a == (b == .clear ? 0 : 255), "\(b) corner \(px[3, 3])")
            #expect(px[290, 190].a == (b == .clear ? 0 : 255), "\(b) corner \(px[290, 190])")
            #expect(px[148, 98].near(gray), "\(b) shot \(px[148, 98])")
        }
    }

    @Test func transparentBackgroundExportsRealAlpha() throws {
        let s = Fixture.session(Fixture.solid(800, 600, CGColor(srgbRed: 0, green: 0.5, blue: 1, alpha: 1)), scale: 2)
        s.selection = CGRect(x: 50, y: 50, width: 200, height: 100)
        s.phase = .editing
        s.style = Style(enabled: true, backdrop: .clear, padding: 0, radius: 32, shadow: 0, ratio: .auto)
        let rounded = try #require(Shot(s))
        let px = Pixels(rounded.cgImage)
        #expect(px.width == 400 && px.height == 200)
        #expect(px[0, 0].a == 0, "rounded corner should be see-through")
        #expect(px[200, 100].a == 255)

        let png = try #require(rounded.png)
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(![.none, .noneSkipFirst, .noneSkipLast].contains(decoded.alphaInfo), "PNG must carry alpha")
        #expect(Pixels(decoded)[0, 0].a == 0)

        s.style.padding = 48
        s.style.shadow = 0.8
        let shadowed = Pixels(try #require(s.render()))
        #expect(shadowed[2, 2].a < 8, "far corner \(shadowed[2, 2])")
        let underShot = shadowed[296, (48 + 100 + 12) * 2]
        #expect(underShot.a > 0 && underShot.a < 255, "shadow below the shot \(underShot)")
    }

    @Test func extremeStyleValuesStillRender() throws {
        let s = Fixture.session(Fixture.coded(400, 300), scale: 1)
        s.selection = CGRect(x: 10, y: 10, width: 100, height: 60)
        s.phase = .editing
        s.style.enabled = true
        for (padding, radius, shadow): (CGFloat, CGFloat, CGFloat) in [(0, 0, 0), (160, 32, 0.8), (0, 500, 1), (1000, 0, 0.8), (0.5, 0.5, 0.01)] {
            for ratio in Ratio.allCases {
                s.style.padding = padding
                s.style.radius = radius
                s.style.shadow = shadow
                s.style.ratio = ratio
                let image = try #require(s.render(), "\(padding) \(radius) \(shadow) \(ratio)")
                #expect(image.width == Int((s.canvas.width - 1e-6).rounded(.up)) && image.height == Int((s.canvas.height - 1e-6).rounded(.up)),
                        "\(padding) \(radius) \(shadow) \(ratio): \(image.width)×\(image.height) for \(s.canvas)")
            }
        }
    }

    @Test func previewFrameStaysOnScreenAndClearOfThePanel() {
        for size in Self.screens {
            for sel in Self.selections(on: size) {
                let s = styled(size, sel)
                for ratio in Ratio.allCases {
                    for padding: CGFloat in [0, 48, 160] {
                        s.style.ratio = ratio
                        s.style.padding = padding
                        let f = s.previewFrame, c = s.canvas, eps = 1e-6
                        let label = "\(size) \(sel) \(ratio) p\(padding): \(f)"
                        #expect(f.width > 0 && f.height > 0 && f.minX.isFinite && f.minY.isFinite, "\(label)")
                        #expect(f.minX >= 20 - eps && f.maxX <= size.width - 320 + eps, "\(label)")
                        #expect(f.minY >= 50 - eps && f.maxY <= size.height - 100 + eps, "\(label)")
                        #expect(abs(f.width / f.height - c.width / c.height) < 1e-6, "aspect \(label)")
                        #expect(f.width <= c.width + eps, "never scaled up \(label)")
                    }
                }
            }
        }
    }

    @Test func toolbarStaysOnScreen() {
        var offScreen: [(width: CGFloat, what: String)] = []
        for size in Self.screens {
            for sel in Self.selections(on: size) {
                for enabled in [false, true] {
                    let s = styled(size, sel)
                    s.style.enabled = enabled
                    let c = s.toolbarCenter(around: enabled ? s.previewFrame : sel)
                    // With Background on, the toolbar sits left of the panel (which starts at width − 285),
                    // or on screens too narrow for that, docks at the bottom below the vertically centred panel.
                    let onScreen = c.x - Self.toolbarHalfWidth >= 0 && c.x + Self.toolbarHalfWidth <= size.width
                        && c.y - Self.toolbarHalfHeight >= 0 && c.y + Self.toolbarHalfHeight <= size.height
                    let clearOfPanel = !enabled || c.x + Self.toolbarHalfWidth <= size.width - 285 || c.y >= size.height - 60
                    let fits = onScreen && clearOfPanel
                    if !fits { offScreen.append((size.width, "\(size) background=\(enabled) sel=\(sel) centre=\(c)")) }
                }
            }
        }
        #expect(offScreen.isEmpty, "\(offScreen.map(\.what))")
    }
}
