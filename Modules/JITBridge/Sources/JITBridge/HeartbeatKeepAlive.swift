import Foundation
import IDevice

/// Keeps the device's heartbeat service satisfied (marco/polo) for as long
/// as this object is alive, so a long-held tunnel/debug session doesn't get
/// dropped as idle. Opens its own tunnel connection, separate from whatever
/// tunnel the caller is using for other services.
final class HeartbeatKeepAlive {
    private static let defaultIntervalSeconds: UInt64 = 2
    private static let maxIntervalSeconds: UInt64 = 3

    private let queue = DispatchQueue(label: "jitbridge.heartbeat", qos: .utility)
    private let startedSemaphore = DispatchSemaphore(value: 0)
    private let stoppedSemaphore = DispatchSemaphore(value: 0)
    private let stateLock = NSLock()
    private var stopRequested = false
    private var startupError: Error?

    private let endpoint: DeviceEndpoint
    private let pairingFile: OpaquePointer

    init(endpoint: DeviceEndpoint, pairingFile: OpaquePointer) {
        self.endpoint = endpoint
        self.pairingFile = pairingFile
    }

    /// Starts the keepalive loop in the background and blocks until either
    /// it's confirmed running or it failed to start.
    func start() throws {
        queue.async { [weak self] in self?.run() }
        startedSemaphore.wait()
        if let startupError {
            throw startupError
        }
    }

    func stop() {
        stateLock.lock()
        stopRequested = true
        stateLock.unlock()
        _ = stoppedSemaphore.wait(timeout: .now() + .seconds(Int(Self.maxIntervalSeconds) + 1))
    }

    private func shouldStop() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stopRequested
    }

    private func run() {
        let tunnel: DeviceTunnel
        var client: OpaquePointer?

        do {
            tunnel = try DeviceTunnel.open(endpoint: endpoint, hostname: "ViboCodiumHeartbeat", pairingFile: pairingFile)
            let error = heartbeat_connect_rsd(tunnel.adapter, tunnel.handshake, &client)
            try throwIfError(error, fallback: "Failed to connect heartbeat")
        } catch {
            startupError = error
            startedSemaphore.signal()
            stoppedSemaphore.signal()
            return
        }

        defer {
            if let client { heartbeat_client_free(client) }
            tunnel.close()
            stoppedSemaphore.signal()
        }

        startedSemaphore.signal()

        guard let client else { return }
        var interval = Self.defaultIntervalSeconds

        while !shouldStop() {
            var suggestedInterval: UInt64 = 0
            let error = heartbeat_get_marco(client, interval, &suggestedInterval)

            if shouldStop() { break }

            if error != nil {
                idevice_error_free(error)
                interval = Self.defaultIntervalSeconds
                continue
            }

            interval = min(max(suggestedInterval, 1), Self.maxIntervalSeconds)

            let poloError = heartbeat_send_polo(client)
            if poloError != nil {
                idevice_error_free(poloError)
                interval = Self.defaultIntervalSeconds
            }
        }
    }
}
