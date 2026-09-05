import IDevice

/// A connected `RemoteServerClient` (the Instruments/DVT protocol server),
/// the thing `ProcessControl` and other DVT services talk through.
final class RemoteServer {
    let handle: OpaquePointer
    private var isClosed = false

    private init(handle: OpaquePointer) {
        self.handle = handle
    }

    static func connect(over tunnel: DeviceTunnel) throws -> RemoteServer {
        var handle: OpaquePointer?
        let error = remote_server_connect_rsd(tunnel.adapter, tunnel.handshake, &handle)
        try throwIfError(error, fallback: "Failed to connect remote server")

        guard let handle else {
            throw JITBridgeError.handleAllocationFailed("Remote server")
        }
        return RemoteServer(handle: handle)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        remote_server_free(handle)
    }

    deinit {
        close()
    }
}
