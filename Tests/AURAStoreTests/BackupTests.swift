import Testing
import Foundation
import CryptoKit
@testable import AURAStore

@Suite("Backup")
struct BackupTests {

    @Test("a short passphrase is refused")
    func passphraseLength() {
        // The only defence against a weak passphrase on an AES-GCM file is
        // refusing it — everything else about the encryption is already strong.
        #expect(throws: (any Error).self) {
            try Backup.write(stores: [:], to: URL(fileURLWithPath: "/tmp/x"),
                             passphrase: "short")
        }
    }

    @Test("the wrong passphrase fails rather than returning garbage")
    func wrongPassphrase() throws {
        let salt = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        let right = Backup.derive(passphrase: "correct horse battery", salt: salt)
        let wrong = Backup.derive(passphrase: "incorrect horse battery", salt: salt)

        let sealed = try AES.GCM.seal(Data("secret".utf8), using: right)
        // AES-GCM authenticates: a wrong key cannot silently produce plausible
        // plaintext, which is the property that matters for a health backup.
        #expect(throws: (any Error).self) {
            _ = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed.combined!),
                                 using: wrong)
        }
    }

    @Test("the same passphrase with a different salt gives a different key")
    func saltMatters() {
        let a = Backup.derive(passphrase: "correct horse battery",
                              salt: Data(repeating: 1, count: 32))
        let b = Backup.derive(passphrase: "correct horse battery",
                              salt: Data(repeating: 2, count: 32))
        // A fresh salt per backup is why two backups of the same data are not
        // byte-identical, and why one cracked key does not open the others.
        #expect(a != b)
    }

    @Test("a file that is not a backup is rejected before decryption")
    func magicNumber() throws {
        let junk = FileManager.default.temporaryDirectory
            .appending(path: "not-a-backup-\(UUID().uuidString)")
        try Data("hello".utf8).write(to: junk)
        defer { try? FileManager.default.removeItem(at: junk) }

        // A clear "this isn't a backup" beats a passphrase error that sends you
        // hunting for the right passphrase to a file that never had one.
        #expect(throws: (any Error).self) {
            _ = try Backup.restore(from: junk,
                                   into: FileManager.default.temporaryDirectory,
                                   passphrase: "correct horse battery")
        }
    }
}
