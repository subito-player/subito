import Foundation

public enum Rename {
    // Never touches a folder the new name already has, so a second launch or a later rename back loses nothing.
    public static func copySupportFolder(from old: URL, to new: URL) throws -> Bool {
        let files = FileManager.default
        guard !files.fileExists(atPath: new.path), files.fileExists(atPath: old.path) else { return false }
        try files.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.copyItem(at: old, to: new)
        return true
    }
}
