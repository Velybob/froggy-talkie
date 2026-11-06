import CryptoKit
import Foundation
import Testing
@testable import DictationModels

private func entry(_ path: String, _ data: Data) -> ModelManifest.File {
    .init(path: path, bytes: Int64(data.count),
        sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
}

private func manifest(_ files: [ModelManifest.File]) -> ModelManifest {
    .init(repository: "example/model", revision: String(repeating: "a", count: 40), directory: "model", files: files)
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("froggy-model-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}

private actor FixtureTransport: ModelTransport {
    let data: Data
    let fail: Bool
    private(set) var calls = 0
    init(_ data: Data, fail: Bool = false) { self.data = data; self.fail = fail }
    func fetch(_ url: URL, expectedBytes: Int64, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        calls += 1
        if fail { throw URLError(.notConnectedToInternet) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: file)
        progress(Int64(data.count))
        return file
    }
}

@Test func bundledManifestPinsEveryFileAndItsRevision() throws {
    let model = try ModelManifest.bundled()
    #expect(model.files.count == 20)
    #expect(model.totalBytes == 632_314_500)
    #expect(model.revision == "95eaa59a39d4394f047a4dc5cce480388a60d1b6")
    #expect(model.files.allSatisfy { model.url(for: $0).absoluteString.contains("/resolve/\(model.revision)/") })
}

@Test func packagedAppLoadsItsOwnManifestAndNeverFallsBackToTheBuildTree() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let app = root.appendingPathComponent("Fixture.app")
    let resources = app.appendingPathComponent("Contents/Resources/LocalDictation_DictationModels.bundle")
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    let plist = ["CFBundleIdentifier": "org.example.fixture", "CFBundlePackageType": "APPL"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: app.appendingPathComponent("Contents/Info.plist"))
    let bundle = try #require(Bundle(url: app))
    #expect(throws: ModelDownloadError.self) { try ModelManifest.bundled(in: bundle) }
    let expected = try ModelManifest.bundled()
    try JSONEncoder().encode(expected).write(to: resources.appendingPathComponent("parakeet-ultra.json"))
    #expect(try ModelManifest.bundled(in: bundle).revision == expected.revision)
}

@Test func manifestRejectsTraversalURLsDuplicatesAndOverflow() throws {
    let data = Data("fixture".utf8)
    for path in ["../escape", "/absolute", "dir/../../escape", "a//b", "a?token=x", "a#fragment", "a\\b", "."] {
        #expect(throws: ModelDownloadError.self) { try manifest([entry(path, data)]).validate() }
    }
    let file = entry("weights.bin", data)
    #expect(throws: ModelDownloadError.self) { try manifest([file, file]).validate() }
    #expect(throws: ModelDownloadError.self) { try manifest([]).validate() }
    let huge = ModelManifest.File(path: "a", bytes: .max, sha256: file.sha256)
    #expect(throws: ModelDownloadError.self) { try manifest([huge, file]).validate() }
    let unsafe = ModelManifest(repository: "example/model?x", revision: String(repeating: "a", count: 40),
        directory: "model", files: [file])
    #expect(throws: ModelDownloadError.self) { try unsafe.validate() }
}

@Test func installationPublishesOnlyVerifiedFilesAndCleansStaging() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let data = Data("verified fixture".utf8)
    let network = FixtureTransport(data)
    try await ModelDownloader(transport: network).install(to: root, manifest: manifest([entry("weights/a.bin", data)]))
    #expect(try Data(contentsOf: root.appendingPathComponent("model/weights/a.bin")) == data)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["model"])
    #expect(await network.calls == 1)
}

@Test func completeInstallationWorksOfflineWithoutNetwork() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appendingPathComponent("model"), withIntermediateDirectories: false)
    let data = Data("cached weights".utf8)
    try data.write(to: root.appendingPathComponent("model/weights.bin"))
    let network = FixtureTransport(Data(), fail: true)
    try await ModelDownloader(transport: network).install(to: root, manifest: manifest([entry("weights.bin", data)]))
    #expect(await network.calls == 0)
}

@Test func corruptDownloadPreservesPreviousModelAndRemovesPartialFiles() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let old = Data("old".utf8), expected = Data("new".utf8)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("model"), withIntermediateDirectories: false)
    try old.write(to: root.appendingPathComponent("model/weights.bin"))
    let downloader = ModelDownloader(transport: FixtureTransport(Data("bad".utf8)))
    await #expect(throws: ModelDownloadError.self) {
        try await downloader.install(to: root, manifest: manifest([entry("weights.bin", expected)]))
    }
    #expect(try Data(contentsOf: root.appendingPathComponent("model/weights.bin")) == old)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["model"])
}

@Test func networkFailureDoesNotPublishAnIncompleteModel() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let downloader = ModelDownloader(transport: FixtureTransport(Data(), fail: true))
    await #expect(throws: URLError.self) {
        try await downloader.install(to: root, manifest: manifest([entry("weights.bin", Data("fixture".utf8))]))
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
}

@Test func repairReusesVerifiedFilesAndPreservesOldDirectory() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appendingPathComponent("model"), withIntermediateDirectories: false)
    let data = Data("valid".utf8), old = Data("old".utf8)
    try data.write(to: root.appendingPathComponent("model/a.bin"))
    try old.write(to: root.appendingPathComponent("model/b.bin"))
    let network = FixtureTransport(data)
    try await ModelDownloader(transport: network).install(to: root,
        manifest: manifest([entry("a.bin", data), entry("b.bin", data)]))
    #expect(await network.calls == 1)
    #expect(try Data(contentsOf: root.appendingPathComponent("model/b.bin")) == data)
    let backup = try #require(FileManager.default.contentsOfDirectory(atPath: root.path).first { $0.hasPrefix("model-previous-") })
    #expect(try Data(contentsOf: root.appendingPathComponent(backup + "/b.bin")) == old)
}

@Test func symbolicLinkCannotRedirectAnInstallation() async throws {
    let root = try temporaryDirectory(), outside = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("model"), withDestinationURL: outside)
    let downloader = ModelDownloader(transport: FixtureTransport(Data("fixture".utf8)))
    await #expect(throws: ModelDownloadError.self) {
        try await downloader.install(to: root, manifest: manifest([entry("weights.bin", Data("fixture".utf8))]))
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
}

private struct WaitingTransport: ModelTransport {
    let started: AsyncStream<Void>.Continuation
    func fetch(_ url: URL, expectedBytes: Int64, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        started.yield(())
        try await Task.sleep(for: .seconds(60))
        throw URLError(.timedOut)
    }
}

@Test(.timeLimit(.minutes(1))) func cancellationCleansUpAndConcurrentInstallIsRejected() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let (events, continuation) = AsyncStream<Void>.makeStream()
    defer { continuation.finish() }
    let downloader = ModelDownloader(transport: WaitingTransport(started: continuation))
    let model = manifest([entry("weights.bin", Data("fixture".utf8))])
    let task = Task { try await downloader.install(to: root, manifest: model) }
    var iterator = events.makeAsyncIterator()
    _ = await iterator.next()
    await #expect(throws: ModelDownloadError.self) { try await downloader.install(to: root, manifest: model) }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
}

@Test func existingModelSelectionIsPreservedAndFreshInstallUsesApplicationSupport() {
    #expect(ModelManifest.initialRoot(storedPath: "/custom/Models", bundleURL: URL(fileURLWithPath: "/Applications/Froggy Talkie.app")).path == "/custom/Models")
    #expect(ModelManifest.initialRoot(storedPath: nil, bundleURL: URL(fileURLWithPath: "/Applications/Froggy Talkie.app")) == ModelManifest.applicationSupportRoot)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["FROGGY_TEST_NETWORK"] == "1"))
func pinnedHTTPSDownloadPassesIntegrityCheck() async throws {
    let model = try ModelManifest.bundled()
    let file = try #require(model.files.first { $0.bytes == 243 })
    let temporary = try await HTTPSModelTransport().fetch(model.url(for: file), expectedBytes: file.bytes) { _ in }
    defer { try? FileManager.default.removeItem(at: temporary) }
    #expect(try ModelFileVerifier.verify(temporary, file: file))
}
