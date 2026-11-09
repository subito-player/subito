import Foundation

public enum TextTail {
    // Reads only the end of the file, so a long day's log costs the same as a short one.
    public static func lastLines(of url: URL, count: Int, maxBytes: Int = 65_536) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return [] }
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return [] }
        var lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        // A read from the middle starts inside a line.
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        if lines.last?.isEmpty == true { lines.removeLast() }
        return lines.suffix(count).map(String.init)
    }
}
