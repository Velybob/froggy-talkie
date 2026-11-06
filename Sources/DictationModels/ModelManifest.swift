import CryptoKit
import Foundation

public struct ModelManifest: Codable, Sendable {
    public struct File: Codable, Sendable {
        public let path: String
        public let bytes: Int64
        public let sha256: String
    }

    public let repository: String
    public let revision: String
    public let directory: String
    public let files: [File]
    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }

    public static func bundled(in application: Bundle = .main) throws -> Self {
        let url: URL?
        if application.bundleURL.pathExtension == "app" {
            // SwiftPM's generated accessor searches beside the executable or at
            // an absolute build path. A distributable macOS app uses Resources.
            url = application.resourceURL?.appendingPathComponent("LocalDictation_DictationModels.bundle/parakeet-ultra.json")
        } else {
            url = Bundle.module.url(forResource: "parakeet-ultra", withExtension: "json")
        }
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            throw ModelDownloadError.invalidManifest
        }
        let manifest = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try manifest.validate()
        return manifest
    }

    func validate() throws {
        let pathCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        func safePath(_ value: String) -> Bool {
            value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
                !$0.isEmpty && $0 != "." && $0 != ".." && $0.unicodeScalars.allSatisfy(pathCharacters.contains)
            }
        }
        guard safePath(repository), repository.split(separator: "/").count == 2,
              safePath(directory), !directory.contains("/"), !directory.hasPrefix("."),
              revision.count == 40, revision.allSatisfy({ $0.isHexDigit && $0.isASCII }),
              !files.isEmpty, Set(files.map(\.path)).count == files.count else {
            throw ModelDownloadError.invalidManifest
        }
        var size: Int64 = 0
        for file in files {
            let sum = size.addingReportingOverflow(file.bytes)
            guard safePath(file.path), file.bytes > 0, !sum.overflow,
                  file.sha256.count == 64,
                  file.sha256.allSatisfy({ $0.isHexDigit && $0.isASCII }) else {
                throw ModelDownloadError.invalidManifest
            }
            size = sum.partialValue
        }
    }

    func url(for file: File) -> URL {
        // Manifest validation forbids URL metacharacters and traversal components.
        URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(file.path)")!
    }

    public static var applicationSupportRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Froggy Talkie/Models", isDirectory: true)
    }

    /// Keep an explicit user choice and the existing development layout working.
    public static func initialRoot(storedPath: String?, bundleURL: URL) -> URL {
        if let storedPath, !storedPath.isEmpty { return URL(fileURLWithPath: storedPath, isDirectory: true) }
        let development = bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Models", isDirectory: true)
        if FileManager.default.fileExists(atPath: development.appendingPathComponent("parakeet-ultra-coreml").path) {
            return development
        }
        return applicationSupportRoot
    }
}

public enum ModelDownloadError: LocalizedError {
    case invalidManifest, busy, unsafeDirectory, invalidResponse, integrity(String)

    public var errorDescription: String? {
        switch self {
        case .invalidManifest: "Не удалось прочитать список файлов модели. Переустановите приложение."
        case .busy: "Модель уже загружается."
        case .unsafeDirectory: "Папка модели содержит символическую ссылку. Выберите обычную папку."
        case .invalidResponse: "Сервер не отдал файл модели. Проверьте подключение и повторите загрузку."
        case .integrity(let path): "Файл модели не прошёл проверку: \(path). Повторите загрузку."
        }
    }
}

enum ModelFileVerifier {
    static func verify(_ url: URL, file: ModelManifest.File) throws -> Bool {
        try Task.checkCancellation()
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true,
              properties.fileSize.map(Int64.init) == file.bytes else { return false }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined() == file.sha256.lowercased()
    }
}
