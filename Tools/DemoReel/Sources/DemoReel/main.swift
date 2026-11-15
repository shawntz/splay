import Foundation

// demoreel: renders docs/assets/demo from Splay's layout engine.
//
//   swift run demoreel                      every clip: GIF, MP4 and poster
//   swift run demoreel strip widths         only these clips
//   swift run demoreel --stills DIR 0 2.5   PNG frames of each clip at these times, nothing else
//   swift run demoreel --keep-frames        also keep the GIF's frames in .build/demoreel
//
// The GIFs are encoded by make_gif.py next to Package.swift, which needs python3 with Pillow and numpy.

let package = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let repo = package.deletingLastPathComponent().deletingLastPathComponent()
let out = repo.appending(path: "docs/assets/demo")
let work = package.appending(path: ".build/demoreel")

var args = Array(CommandLine.arguments.dropFirst())
let keepFrames = args.contains("--keep-frames")
args.removeAll { $0 == "--keep-frames" }
var stills: (folder: URL, times: [Double])?
if let i = args.firstIndex(of: "--stills") {
    let folder = URL(filePath: args[i + 1])
    let times = args[(i + 2)...].compactMap(Double.init)
    stills = (folder, times)
    args.removeSubrange(i...)
}
let names = args.isEmpty ? Scenes.all : args
for name in names where !Scenes.all.contains(name) {
    fputs("demoreel: no clip named \(name); the clips are \(Scenes.all.joined(separator: ", "))\n", stderr)
    exit(1)
}

try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for name in names {
    print("\(name):")
    let scene = Scenes.make(name)
    let renderer = Renderer(scene: scene)
    print(String(format: "  %.1f s", scene.timeline.duration))
    if let stills {
        try! FileManager.default.createDirectory(at: stills.folder, withIntermediateDirectories: true)
        for t in stills.times {
            let ctx = Output.context(width: 1920)
            renderer.draw(ctx, at: t, opaque: false)
            Output.writePNG(ctx.makeImage()!, to: stills.folder.appending(path: String(format: "%@-%06.2f.png", name, t)))
        }
        continue
    }
    Output.poster(renderer, to: out.appending(path: "\(name)-poster.png"))
    Output.video(renderer, fps: 60, bitrate: 1_100_000, to: out.appending(path: "\(name).mp4"))
    print("  wrote \(name).mp4 and \(name)-poster.png")
    let frames = work.appending(path: name)
    let count = Output.frames(renderer, fps: 25, width: 960, into: frames)
    // Colours drawn as deliberate steps, which the GIF's palette must hold exactly.
    let keep = ([0x0A1A44] + Renderer.wallpaperSteps).map { String(format: "%06x", $0) }
    try! keep.joined(separator: "\n").write(to: frames.appending(path: "keep.txt"), atomically: true, encoding: .utf8)
    let python = Process()
    python.executableURL = URL(filePath: "/usr/bin/env")
    python.arguments = ["python3", "-I", package.appending(path: "make_gif.py").path, frames.path,
                        out.appending(path: "\(name).gif").path, "--fps", "25",
                        "--keep", frames.appending(path: "keep.txt").path]
    try! python.run()
    python.waitUntilExit()
    guard python.terminationStatus == 0 else {
        fputs("demoreel: make_gif.py failed for \(name)\n", stderr)
        exit(1)
    }
    print("  wrote \(name).gif from \(count) frames")
    if !keepFrames { try? FileManager.default.removeItem(at: frames) }
}
