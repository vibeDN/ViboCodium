import Foundation
import IDevice

/// The general "debug-flag a pid" primitive this whole module exists for.
///
/// Not a one-shot "JIT-enable myself at launch" helper: both the Swift
/// edit-compile-run loop (self-attach to `getpid()`) and a per-language
/// toolchain's helper process (attach to whatever pid that helper runs as)
/// are just callers of the same `attach(pid:endpoint:holding:)`. A
/// debug-flagged process is exempted from iOS's codesign/AMFI enforcement
/// against executing freshly-generated or otherwise-unsigned code pages -
/// see ARCHITECTURE.md for why that's the whole point.
public enum JITBridge {
    /// Attaches a debugserver session to `pid`, runs `body` while attached
    /// (with a heartbeat keeping the underlying tunnel alive), then detaches.
    ///
    /// The debug flag this sets on the target process persists for that
    /// process's lifetime regardless of detaching - it has to be redone on
    /// every fresh process launch (including this app's own cold start).
    public static func attach(
        pid: Int32,
        endpoint: DeviceEndpoint,
        hostname: String = "ViboCodiumJITBridge",
        holding body: () throws -> Void = {}
    ) throws {
        let pairingHandle = try PairingFile.readHandle()
        defer { rp_pairing_file_free(pairingHandle) }

        let tunnel = try DeviceTunnel.open(endpoint: endpoint, hostname: hostname, pairingFile: pairingHandle)
        defer { tunnel.close() }

        let session = try DebugSession.connect(over: tunnel)
        defer { session.close() }

        try session.attach(pid: pid)

        let heartbeat = HeartbeatKeepAlive(endpoint: endpoint, pairingFile: pairingHandle)
        try heartbeat.start()
        defer { heartbeat.stop() }

        try body()
        try session.detach()
    }

    /// Convenience for the most common case: attach to this process's own
    /// pid so it can run freshly-compiled code without a full resign and
    /// reinstall on every edit-compile-run cycle.
    public static func enableSelfJIT(endpoint: DeviceEndpoint) throws {
        try attach(pid: getpid(), endpoint: endpoint)
    }
}
