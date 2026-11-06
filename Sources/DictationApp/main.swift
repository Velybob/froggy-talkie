import Foundation
import DictationModels

// A packaging check must run before constructing the App or DictationModel:
// no windows, preferences, hotkeys, microphone, model inference or network.
if CommandLine.arguments.dropFirst().elementsEqual(["--check-resources"]) {
    do {
        let manifest = try ModelManifest.bundled()
        print("Model manifest: \(manifest.revision), \(manifest.files.count) files, \(manifest.totalBytes) bytes")
    } catch {
        FileHandle.standardError.write(Data("Resource check failed: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
} else {
    LocalDictationApp.main()
}
