import CueCore
import Foundation
import Testing

struct RenameTests {
    @Test func theOldFolderIsCopiedWhenTheNewNameHasNone() throws {
        try withTempDir { dir in
            let old = dir.appendingPathComponent("me.blint.attacca")
            let new = dir.appendingPathComponent("me.blint.subito")
            try write("keys", to: old.appendingPathComponent("keymap.json"))
            #expect(try Rename.copySupportFolder(from: old, to: new))
            #expect(try String(contentsOf: new.appendingPathComponent("keymap.json"), encoding: .utf8) == "keys")
            #expect(FileManager.default.fileExists(atPath: old.appendingPathComponent("keymap.json").path))
        }
    }

    @Test func aFolderTheNewNameAlreadyHasIsNeverTouched() throws {
        try withTempDir { dir in
            let old = dir.appendingPathComponent("me.blint.attacca")
            let new = dir.appendingPathComponent("me.blint.subito")
            try write("old", to: old.appendingPathComponent("keymap.json"))
            try write("new", to: new.appendingPathComponent("keymap.json"))
            #expect(try !Rename.copySupportFolder(from: old, to: new))
            #expect(try String(contentsOf: new.appendingPathComponent("keymap.json"), encoding: .utf8) == "new")
            let missing = dir.appendingPathComponent("missing")
            #expect(try !Rename.copySupportFolder(from: missing, to: dir.appendingPathComponent("x")))
        }
    }
}
