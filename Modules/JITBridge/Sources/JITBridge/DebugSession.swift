import Foundation
import IDevice

/// A debugserver session over the debug proxy: this is the thing that
/// actually flips a target process into the "debugged" state, which is
/// what makes iOS's codesign/AMFI enforcement allow it to run
/// freshly-generated or otherwise-unsigned code pages.
///
/// This is deliberately not tied to "our own process" - `attach(pid:)`
/// takes any pid, so the same primitive covers both self-JIT (attach to
/// `getpid()`) and licensing a downloaded toolchain's helper process to
/// run (attach to whatever pid that helper was launched with).
final class DebugSession {
    private let handle: OpaquePointer
    private var isClosed = false
    private var isAttached = false

    private init(handle: OpaquePointer) {
        self.handle = handle
    }

    static func connect(over tunnel: DeviceTunnel) throws -> DebugSession {
        var handle: OpaquePointer?
        let error = debug_proxy_connect_rsd(tunnel.adapter, tunnel.handshake, &handle)
        try throwIfError(error, fallback: "Failed to connect debug proxy")

        guard let handle else {
            throw JITBridgeError.handleAllocationFailed("Debug proxy")
        }
        return DebugSession(handle: handle)
    }

    /// Attaches to `pid` and switches the connection to no-ack mode
    /// (the standard debugserver handshake for a fresh session).
    func attach(pid: Int32) throws {
        // Best-effort: some debugserver versions expect a couple of stray
        // acks before the mode switch. Failures here aren't fatal.
        try? throwIfError(debug_proxy_send_ack(handle), fallback: "ack")
        try? throwIfError(debug_proxy_send_ack(handle), fallback: "ack")

        _ = try? sendCommand("QStartNoAckMode")
        debug_proxy_set_ack_mode(handle, 0)

        let hexPID = String(UInt32(bitPattern: pid), radix: 16)
        _ = try sendCommand("vAttach;\(hexPID)")
        isAttached = true
    }

    /// Sends the interrupt (Ctrl-C) byte. Only meaningful while attached and
    /// the target is running; not required for a plain attach-then-detach.
    func interrupt() throws {
        var breakByte: UInt8 = 0x03
        let error = debug_proxy_send_raw(handle, &breakByte, 1)
        try throwIfError(error, fallback: "Failed to send interrupt")
    }

    /// Detaches, which implicitly resumes the target if it was stopped.
    /// The debugged flag this session set on the target sticks for that
    /// process's lifetime regardless of detaching.
    func detach() throws {
        guard isAttached else { return }
        isAttached = false
        _ = try sendCommand("D")
    }

    /// Sends a debugserver command with no arguments (every command this
    /// module needs - QStartNoAckMode, vAttach, D - takes none).
    @discardableResult
    private func sendCommand(_ command: String) throws -> String? {
        guard let commandHandle = command.withCString({ debugserver_command_new($0, nil, 0) }) else {
            throw JITBridgeError.handleAllocationFailed("Debugserver command '\(command)'")
        }
        defer { debugserver_command_free(commandHandle) }

        var response: UnsafeMutablePointer<CChar>?
        let error = debug_proxy_send_command(handle, commandHandle, &response)
        try throwIfError(error, fallback: "Debugserver command '\(command)' failed")

        defer { if let response { idevice_string_free(response) } }
        guard let response else { return nil }
        return String(cString: response)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        if isAttached {
            _ = try? detach()
        }
        debug_proxy_free(handle)
    }

    deinit {
        close()
    }
}
