import AppKit
import ImageIO
import SwiftUI

/// Runs the menu bar app, or the command line tool when the first argument is one of its commands.
@main
enum Main {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if let first = args.first, CLI.commands.contains(first) { exit(CLI.run(args)) }
        ShinyScreenshotApp.main()
    }
}

/// `shiny render`: styles and marks up an image file with the same renderer as the overlay, for scripts and agents.
enum CLI {
    static let commands: Set = ["render", "list", "help", "--help", "-h"]

    struct Failure: Error { let message: String }

    static let help = """
    Shiny Screenshot command line: put a screenshot on a background and mark it up.

    USAGE
      shiny render <image> [-o out.png] [options]   Render a styled, annotated image
      shiny list                                    Presets, backgrounds and every --style field with its choices
      shiny help

    Take the screenshot first, e.g. `screencapture -x -R 0,0,1280,800 shot.png` or `screencapture -x -l <windowID> shot.png`.

    OUTPUT
      -o, --out PATH        .png (default), .jpg or .heic. Default: <image>-shiny.png. Prints the path and pixel size.

    IMAGE
      --scale N             Pixels per point of the input. Default: from the file's DPI (144 dpi = 2), else 1.
                            Padding, radius, text sizes and line widths are in points.
      --crop X,Y,W,H        Keep only this part of the image.

    BACKGROUND (on by default)
      --preset NAME         A built-in or saved preset, e.g. "Launch", "Wallpaper", "Neon night" (see `shiny list`).
      --background NAME     A background, e.g. silk, prism, aurora, dusk, paper, clear.
      --style JSON|@FILE    Any style fields, merged in order, e.g. '{"frame":"macOS","padding":64,"shadowLook":"Float"}'.
      --title TEXT  --subtitle TEXT  --eyebrow TEXT
      --no-background       Just the image and its annotations.

    ANNOTATIONS (coordinates in input pixels, of the whole image even with --crop; drawn in the order given)
      --color C             For the annotations after it: red (default), orange, yellow, green, blue, purple or #RRGGBB.
      --arrow X1,Y1,X2,Y2   Arrow pointing from 1 to 2.
      --rect X,Y,W,H        Outlined box.
      --highlight X,Y,W,H   Yellow highlighter.
      --spotlight X,Y,W,H   Dims everything but these areas.
      --blur X,Y,W,H        Pixelates, for secrets.
      --step X,Y            Numbered badge, 1, 2, 3… in order.
      --text X,Y TEXT       Label; its first line is centred on Y. --text-size N (points, default 15) and
                            --outline (coloured text instead of a solid tag) apply to the labels after them.
      --pen X1,Y1,X2,Y2,…   Freehand line.

    EXAMPLE
      shiny render shot.png -o out.png --preset Wallpaper --title "New settings" \\
        --highlight 120,340,600,60 --color blue --arrow 900,700,700,380 --step 140,360 --text 760,700 "Click here"
    """

    static func run(_ args: [String]) -> Int32 {
        _ = NSApplication.shared
        do {
            switch args.first {
            case "render":
                let (url, size) = try render(Array(args.dropFirst()))
                print("\(url.path) \(size.width)x\(size.height)")
            case "list": print(list())
            default: print(help)
            }
            return 0
        } catch let f as Failure {
            FileHandle.standardError.write(Data("shiny: \(f.message)\nRun `shiny help` for usage.\n".utf8))
            return 1
        } catch {
            FileHandle.standardError.write(Data("shiny: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    /// Renders and writes the image; returns where, and its size in pixels.
    static func render(_ args: [String]) throws -> (URL, (width: Int, height: Int)) {
        var queue = args[...]
        func next(_ flag: String) throws -> String {
            guard let v = queue.popFirst() else { throw Failure(message: "\(flag) needs a value") }
            return v
        }
        func numbers(_ flag: String, _ count: Int?) throws -> [CGFloat] {
            let v = try next(flag)
            let n = v.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.map { CGFloat($0) }
            let ok = count.map { n.count == $0 } ?? (n.count >= 4 && n.count.isMultiple(of: 2))
            guard ok, n.count == v.split(separator: ",").count else {
                throw Failure(message: "\(flag) expects \(count.map { "\($0)" } ?? "an even number (4 or more) of") comma-separated numbers, got \"\(v)\"")
            }
            return n
        }

        var input: URL?, out: URL?, scale: CGFloat?, crop: CGRect?
        var style = Style()
        style.enabled = true
        var styleJSON: [[String: Any]] = []
        var color = palette[0], textSize: CGFloat = 15, filled = true
        // Annotations in input pixels, converted once the scale is known.
        var marks: [(Tool, [CGFloat], Color, String, CGFloat, Bool)] = []

        while let a = queue.popFirst() {
            switch a {
            case "-o", "--out": out = URL(filePath: try next(a))
            case "--scale":
                guard let s = Double(try next(a)), s > 0 else { throw Failure(message: "--scale expects a positive number") }
                scale = s
            case "--crop":
                let n = try numbers(a, 4)
                crop = CGRect(x: n[0], y: n[1], width: n[2], height: n[3])
            case "--preset":
                let name = try next(a)
                guard let p = (Preset.builtIn + Preset.saved).first(where: { $0.name.lowercased() == name.lowercased() }) else {
                    throw Failure(message: "no preset \"\(name)\". Presets: \((Preset.builtIn + Preset.saved).map(\.name).joined(separator: ", "))")
                }
                style.adopt(p.style)
            case "--background":
                let name = try next(a).lowercased()
                guard let b = Backdrop.allCases.first(where: { $0.rawValue == name || $0.name.lowercased() == name }) else {
                    throw Failure(message: "no background \"\(name)\". Backgrounds: \(Backdrop.allCases.map(\.rawValue).joined(separator: ", "))")
                }
                style.fill = .backdrop
                style.backdrop = b
            case "--style":
                var v = try next(a)
                if v.hasPrefix("@") { v = try String(contentsOf: URL(filePath: String(v.dropFirst())), encoding: .utf8) }
                guard let d = (try? JSONSerialization.jsonObject(with: Data(v.utf8))) as? [String: Any] else {
                    throw Failure(message: "--style expects a JSON object")
                }
                style = try merged(style, d)
                styleJSON.append(d)
            case "--title": style.title = try next(a)
            case "--subtitle": style.subtitle = try next(a)
            case "--eyebrow": style.eyebrow = try next(a)
            case "--no-background": style.enabled = false
            case "--color": color = try parseColor(try next(a))
            case "--text-size": guard let s = Double(try next(a)), s > 0 else { throw Failure(message: "--text-size expects a number") }
                textSize = s
            case "--outline": filled = false
            case "--arrow": marks.append((.arrow, try numbers(a, 4), color, "", textSize, filled))
            case "--rect": marks.append((.rect, try numbers(a, 4), color, "", textSize, filled))
            case "--highlight": marks.append((.highlight, try numbers(a, 4), color, "", textSize, filled))
            case "--spotlight": marks.append((.spotlight, try numbers(a, 4), color, "", textSize, filled))
            case "--blur": marks.append((.blur, try numbers(a, 4), color, "", textSize, filled))
            case "--step": marks.append((.step, try numbers(a, 2), color, "", textSize, filled))
            case "--pen": marks.append((.pen, try numbers(a, nil), color, "", textSize, filled))
            case "--text":
                let n = try numbers(a, 2)
                marks.append((.text, n, color, try next(a), textSize, filled))
            default:
                if a.hasPrefix("-") || input != nil { throw Failure(message: "unknown option \"\(a)\"") }
                input = URL(filePath: a)
            }
        }

        guard let input else { throw Failure(message: "render needs an image file") }
        guard let src = CGImageSourceCreateWithURL(input as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw Failure(message: "can't read an image from \(input.path)")
        }
        let dpi = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])?[kCGImagePropertyDPIWidth] as? Double
        let k = scale ?? max(1, ((dpi ?? 72) / 72).rounded())
        let session = Session(Capture.Frozen(image: image, scale: k,
                                            size: CGSize(width: CGFloat(image.width) / k, height: CGFloat(image.height) / k), windows: []),
                              displayID: 0)
        session.selectAll()
        if let crop {
            let r = CGRect(x: crop.minX / k, y: crop.minY / k, width: crop.width / k, height: crop.height / k).intersection(session.bounds)
            guard r.width >= 1, r.height >= 1 else { throw Failure(message: "--crop is outside the \(image.width)x\(image.height) image") }
            session.selection = r
        }
        session.style = style
        for (tool, n, color, text, size, filled) in marks {
            let p = stride(from: 0, to: n.count, by: 2).map { CGPoint(x: n[$0] / k, y: n[$0 + 1] / k) }
            // Boxes are X,Y,W,H; the session keeps them as two corners.
            let points = [.rect, .highlight, .spotlight, .blur].contains(tool) ? [p[0], CGPoint(x: p[0].x + p[1].x, y: p[0].y + p[1].y)] : p
            var a = Annotation(tool: tool, color: color, points: points, text: text, size: size, filled: filled)
            if tool == .step { a.number = session.annotations.filter { $0.tool == .step }.count + 1 }
            session.annotations.append(a)
        }

        guard let shot = Shot(session) else { throw Failure(message: "rendering failed") }
        let dest = out ?? input.deletingPathExtension().appendingPathExtension("shiny.png")
        let ext = dest.pathExtension.lowercased()
        let format: ExportFormat = ext == "jpg" || ext == "jpeg" ? .jpeg : ext == "heic" ? .heic : .png
        guard let data = format == .png ? Shot.png(shot.cgImage, size: shot.size, opaque: shot.opaque) : Shot.encoded(shot.cgImage, as: format) else {
            throw Failure(message: "encoding failed")
        }
        try data.write(to: dest)
        return (dest, (shot.cgImage.width, shot.cgImage.height))
    }

    /// The style with `fields` laid over it. Fails on a field that doesn't exist or a value it can't take,
    /// since Style's decoder would otherwise drop them silently.
    static func merged(_ style: Style, _ fields: [String: Any]) throws -> Style {
        var base = try JSONSerialization.jsonObject(with: JSONEncoder().encode(style)) as! [String: Any]
        let known = Set((try JSONSerialization.jsonObject(with: JSONEncoder().encode(Style())) as! [String: Any]).keys)
        for (key, value) in fields {
            // Optional fields that are nil by default (platform, customSize, textColor, imagePath) are missing from `known`.
            guard known.contains(key) || ["platform", "customSize", "textColor", "imagePath"].contains(key) else {
                throw Failure(message: "--style has no field \"\(key)\". Run `shiny list` for the fields.")
            }
            base[key] = value
        }
        let result = try JSONDecoder().decode(Style.self, from: JSONSerialization.data(withJSONObject: base))
        let check = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as! [String: Any]
        for (key, value) in fields where !(value is NSNull) {
            guard let got = check[key], (got as AnyObject).isEqual(value) else {
                throw Failure(message: "--style \"\(key)\" can't be \(value). Run `shiny list` for its choices.")
            }
        }
        return result
    }

    static func parseColor(_ s: String) throws -> Color {
        if let i = paletteNames.firstIndex(where: { $0.lowercased() == s.lowercased() }) { return palette[i] }
        if s.hasPrefix("#"), s.count == 7, let hex = Int(s.dropFirst(), radix: 16) { return Color(hex: hex) }
        throw Failure(message: "--color expects \(paletteNames.joined(separator: ", ").lowercased()) or #RRGGBB, got \"\(s)\"")
    }

    static func list() -> String {
        func cases<T: CaseIterable & RawRepresentable>(_ t: T.Type) -> String { t.allCases.map { "\($0.rawValue)" }.joined(separator: ", ") }
        let defaults = String(data: try! {
            let e = JSONEncoder()
            e.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try e.encode(Style())
        }(), encoding: .utf8)!
        return """
        PRESETS (--preset)
          \((Preset.builtIn + Preset.saved).map(\.name).joined(separator: ", "))

        BACKGROUNDS (--background, or --style '{"backdrop":…}')
          \(cases(Backdrop.self))

        STYLE FIELD CHOICES (--style)
          fill: \(cases(FillSource.self))   (custom uses "gradient", image uses "imagePath")
          gradient: {"kind": \(cases(GradientKind.self)), "colors": [up to 3], "angle": degrees}
          frame: \(cases(WindowFrame.self))
          shotLook: \(cases(ShotLook.self))
          shadowLook: \(cases(ShadowLook.self))
          layout: \(cases(ShotLayout.self))
          tilt: \(cases(Tilt.self))
          ratio: \(cases(Ratio.self))
          platform: \(cases(Platform.self))
          customSize: [width, height] in pixels
          placement: \(cases(Placement.self))
          pattern: \(cases(Pattern.self))   light: \(cases(LightScene.self))   shapes: \(cases(Shapes.self))   vfx: \(cases(VFX.self))
          heading: \(cases(Heading.self))   font: \(cases(TextFont.self))   weight: \(cases(TextWeight.self))   align: \(cases(TextAlign.self))
          watermarkCorner: \(cases(Corner.self))   size: \(cases(ExportSize.self))
          textColor, gradient colors: 0xRRGGBB as a decimal integer (white = 16777215)

        STYLE DEFAULTS (every field --style takes)
        \(defaults)
        """
    }
}
