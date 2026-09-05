import Foundation
import IDevice

/// Stores and loads the RemotePairing pairing file this app uses to talk to
/// its own device over the local RSD/lockdown tunnel.
///
/// Obtaining the pairing file in the first place (the one-time pairing UX)
/// is deliberately not this module's job - callers are expected to supply
/// one (imported, or produced by a pairing flow) and hand it to `PairingFile`
/// for storage.
public enum PairingFile {
    private static let fileName = "device_pairing.plist"

    public static var storageURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JITBridge", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    public static var exists: Bool {
        FileManager.default.fileExists(atPath: storageURL.path)
    }

    /// Copies a pairing file (e.g. one the user picked via a file importer)
    /// into this module's storage location, replacing any existing one.
    public static func store(from sourceURL: URL) throws {
        let directory = storageURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: storageURL.path) {
            try FileManager.default.removeItem(at: storageURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: storageURL)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
    }

    /// Reads the stored pairing file into an `idevice` handle. The caller
    /// owns the returned handle and must free it with `rp_pairing_file_free`.
    static func readHandle() throws -> OpaquePointer {
        guard exists else {
            throw JITBridgeError.pairingFileNotFound(storageURL)
        }

        var handle: OpaquePointer?
        let error = storageURL.path.withCString { path in
            rp_pairing_file_read(path, &handle)
        }
        try throwIfError(error, fallback: "Failed to read pairing file")

        guard let handle else {
            throw JITBridgeError.handleAllocationFailed("Pairing file handle")
        }
        return handle
    }
}
