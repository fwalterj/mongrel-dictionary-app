import Foundation

// Recoverable cleanup only. On failure leave the original item in place.
for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path) else { continue }
    do {
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        print("Moved to Trash: \(url.path)")
    } catch {
        fputs("Preserved \(path): \(error)\n", stderr)
        exit(1)
    }
}
