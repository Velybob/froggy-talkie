import AppKit

@MainActor
public struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]
    public let originalChangeCount: Int

    public static func capture(from board: NSPasteboard, maxBytes: Int = 16 * 1024 * 1024) -> Self? {
        let count = board.changeCount
        let originals = board.pasteboardItems ?? []
        if originals.isEmpty && !(board.types ?? []).isEmpty { return nil }
        var items: [[NSPasteboard.PasteboardType: Data]] = []
        var size = 0
        for item in originals {
            var copied: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type), data.count <= maxBytes - size else { return nil }
                size += data.count
                copied[type] = data
            }
            items.append(copied)
        }
        guard board.changeCount == count else { return nil }
        return Self(items: items, originalChangeCount: count)
    }

    @discardableResult
    public func restore(to board: NSPasteboard, ifUnchangedSince ownedChangeCount: Int) -> Bool {
        guard board.changeCount == ownedChangeCount else { return false }
        let restored = items.map { representations -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in representations { item.setData(data, forType: type) }
            return item
        }
        board.clearContents()
        return restored.isEmpty || board.writeObjects(restored)
    }
}
