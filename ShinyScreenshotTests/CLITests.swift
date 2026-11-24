import AppKit
import Testing
@testable import ShinyScreenshot

/// `shiny render`: argument parsing, crop and scale, style validation.
struct CLITests {
    func input() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "cli-\(UUID()).png")
        try Shot.png(Fixture.gradient(400, 300), size: CGSize(width: 400, height: 300))!.write(to: url)
        return url
    }

    @Test func rendersCropWithoutBackgroundAtScale() throws {
        let src = try input(), out = src.deletingLastPathComponent().appending(path: "\(UUID()).png")
        let (url, size) = try CLI.render([src.path, "-o", out.path, "--scale", "2", "--crop", "10,20,200,100", "--no-background",
                                          "--arrow", "20,30,150,90", "--step", "50,50", "--text", "60,60", "Hi"])
        #expect(url == out && size == (200, 100))
        #expect(FileManager.default.fileExists(atPath: out.path))
    }

    @Test func backgroundAddsPadding() throws {
        let src = try input()
        let (_, size) = try CLI.render([src.path, "--scale", "1", "--style", #"{"padding":50,"frame":"None"}"#])
        #expect(size == (500, 400))
    }

    @Test func rejectsBadInput() throws {
        let src = try input()
        for args in [["--style", #"{"frme":"macOS"}"#], ["--style", #"{"frame":"mac"}"#], ["--arrow", "1,2,3"],
                     ["--preset", "nope"], ["--color", "teal"], ["--bogus"]] {
            #expect(throws: CLI.Failure.self) { try CLI.render([src.path] + args) }
        }
    }
}
