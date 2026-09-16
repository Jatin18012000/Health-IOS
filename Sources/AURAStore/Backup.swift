import Foundation
import CryptoKit
import GRDB

/// Encrypted backup of everything AURA holds.
///
/// ## Why this exists when FileVault already encrypts the disk
///
/// FileVault protects the data *on this Mac*. A backup by definition leaves it —
/// onto an external drive, into a sync folder, attached to an email to yourself.
/// The moment it does, FileVault is no longer involved, and four years of
/// someone's health data is sitting in a file anyone who picks up the drive can
/// open. So the backup carries its own encryption and is useless without the
/// passphrase.
///
/// ## The part that is easy to get wrong
///
/// **A live SQLite database cannot be backed up by copying the file.** With WAL
/// journaling — which both stores use — recent writes live in a separate `-wal`
/// file, so a plain copy captures a database missing its most recent changes,
/// and silently: it opens fine and is simply out of date. `VACUUM INTO` is the
/// supported way to take a consistent snapshot of a live database, and is what
/// this uses.
public enum Backup {

    public struct Manifest: Codable, Sendable {
        public let createdAt: Date
        public let files: [String]
        public let formatVersion: Int
    }

    /// Public, and `LocalizedError`, because these are read by the person
    /// doing the backup. An internal error type thrown out of a public function
    /// reaches the UI as "The operation couldn't be completed", which on a
    /// wrong passphrase is precisely the case where saying nothing useful is
    /// worst.
    public enum BackupError: Error, Sendable, LocalizedError {
        case passphraseTooShort
        case notABackup
        case wrongPassphrase
        case corrupt(String)

        public var errorDescription: String? {
            switch self {
            case .passphraseTooShort:
                "Use at least \(Backup.minimumPassphrase) characters. A short passphrase is the weakest part of an encrypted file by a wide margin."
            case .notABackup:
                "That isn't an AURA backup."
            case .wrongPassphrase:
                "Wrong passphrase — or the file has been altered since it was written. Encryption can't tell those apart, and both mean don't trust it."
            case .corrupt(let detail):
                "The backup is unreadable: \(detail)"
            }
        }
    }

    /// Minimum passphrase length.
    ///
    /// Not security theatre: a short passphrase on an AES-GCM file is the
    /// weakest link by a wide margin, and the only defence is refusing it.
    public static let minimumPassphrase = 12

    /// Write an encrypted archive of both databases.
    ///
    /// - Parameters:
    ///   - stores: the database files to include, by name.
    ///   - url: where to write the archive.
    ///   - passphrase: at least 12 characters. There is no recovery — losing it
    ///     loses the backup, which is the point of encrypting it.
    public static func write(stores: [String: URL], to url: URL,
                             passphrase: String) throws {
        guard passphrase.count >= minimumPassphrase else {
            throw BackupError.passphraseTooShort
        }

        let scratch = FileManager.default.temporaryDirectory
            .appending(path: "aura-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var payload: [String: Data] = [:]
        for (name, source) in stores {
            let snapshot = scratch.appending(path: name)
            // The consistent-snapshot call. A plain file copy would quietly
            // omit anything still in the WAL.
            let queue = try DatabaseQueue(path: source.path)
            try queue.write { db in
                try db.execute(sql: "VACUUM INTO ?", arguments: [snapshot.path])
            }
            payload[name] = try Data(contentsOf: snapshot)
        }

        let manifest = Manifest(createdAt: Date(),
                                files: payload.keys.sorted(),
                                formatVersion: 1)
        let bundle = try JSONEncoder().encode(
            Bundle(manifest: manifest, payload: payload))

        // A fresh random salt per backup, stored in the clear alongside the
        // ciphertext. Reusing one across backups would let the same passphrase
        // produce the same key every time.
        let salt = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        let key = derive(passphrase: passphrase, salt: salt)
        let sealed = try AES.GCM.seal(bundle, using: key)

        guard let combined = sealed.combined else {
            throw BackupError.corrupt("could not seal")
        }

        var output = Data(Self.magic)
        output.append(salt)
        output.append(combined)
        try output.write(to: url, options: .atomic)
    }

    /// Restore an archive, writing each database into `directory`.
    public static func restore(from url: URL, into directory: URL,
                               passphrase: String) throws -> Manifest {
        let raw = try Data(contentsOf: url)
        guard raw.count > magic.count + 32,
              Array(raw.prefix(magic.count)) == magic else {
            throw BackupError.notABackup
        }

        let salt = raw.dropFirst(magic.count).prefix(32)
        let ciphertext = raw.dropFirst(magic.count + 32)
        let key = derive(passphrase: passphrase, salt: Data(salt))

        let opened: Data
        do {
            opened = try AES.GCM.open(
                AES.GCM.SealedBox(combined: Data(ciphertext)), using: key)
        } catch {
            // AES-GCM authenticates, so a wrong passphrase and a tampered file
            // are indistinguishable here — and both mean "do not trust this".
            throw BackupError.wrongPassphrase
        }

        let bundle = try JSONDecoder().decode(Bundle.self, from: opened)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        for (name, data) in bundle.payload {
            try data.write(to: directory.appending(path: name), options: .atomic)
        }
        return bundle.manifest
    }

    /// Identifies the file before anything tries to decrypt it, so a wrong file
    /// gives a clear answer rather than a passphrase failure.
    static let magic: [UInt8] = Array("AURABK01".utf8)

    struct Bundle: Codable {
        let manifest: Manifest
        let payload: [String: Data]
    }

    /// Passphrase to key.
    ///
    /// HKDF over SHA-256. Worth being honest about the trade: HKDF is *fast*,
    /// which is right for deriving a key from high-entropy input and wrong for
    /// resisting a brute-force attack on a human-chosen passphrase. A
    /// deliberately slow KDF — scrypt or Argon2 — is the stronger choice here,
    /// and neither ships in CryptoKit. Recorded in `docs/DECISIONS_PENDING.md`
    /// rather than quietly settled, because the length minimum above is
    /// currently doing more work than it should have to.
    static func derive(passphrase: String, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(passphrase.utf8)),
            salt: salt,
            info: Data("aura.backup.v1".utf8),
            outputByteCount: 32)
    }
}
