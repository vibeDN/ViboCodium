import IDevice

/// A Swift-native error wrapping the C `IdeviceFfiError` produced by
/// `Vendor/idevice`'s FFI layer (see `ffi/src/errors.rs`).
public struct IdeviceError: Error, CustomStringConvertible {
    public let code: Int32
    public let subCode: Int32
    public let message: String

    public var description: String {
        "IdeviceError(code: \(code), subCode: \(subCode)): \(message)"
    }
}

/// Consumes an `IdeviceFfiError` pointer returned by an FFI call: frees it
/// and throws a `IdeviceError` if it's non-null, otherwise does nothing.
///
/// Every idevice FFI call in this module follows the same convention: a
/// non-null return value is an owned error that must be freed exactly once.
func throwIfError(_ error: UnsafeMutablePointer<IdeviceFfiError>?, fallback: String) throws {
    guard let error else { return }
    defer { idevice_error_free(error) }

    let message: String
    if let cMessage = error.pointee.message, let decoded = String(validatingUTF8: cMessage) {
        message = decoded
    } else {
        message = fallback
    }

    throw IdeviceError(code: error.pointee.code, subCode: error.pointee.sub_code, message: message)
}

enum JITBridgeError: Error, CustomStringConvertible {
    case pairingFileNotFound(URL)
    case invalidTargetAddress(String)
    case handleAllocationFailed(String)
    case timedOut(String)

    var description: String {
        switch self {
        case .pairingFileNotFound(let url):
            return "Pairing file not found at \(url.path)"
        case .invalidTargetAddress(let address):
            return "Could not parse target address: \(address)"
        case .handleAllocationFailed(let what):
            return "\(what) was not created despite a successful call"
        case .timedOut(let what):
            return "Timed out waiting for \(what)"
        }
    }
}
