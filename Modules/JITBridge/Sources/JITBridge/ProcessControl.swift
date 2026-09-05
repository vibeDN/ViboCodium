import IDevice

/// Launches and controls processes on the device via the DVT
/// `ProcessControlClient` service.
final class ProcessControl {
    let handle: OpaquePointer
    private var isClosed = false

    private init(handle: OpaquePointer) {
        self.handle = handle
    }

    static func open(on server: RemoteServer) throws -> ProcessControl {
        var handle: OpaquePointer?
        let error = process_control_new(server.handle, &handle)
        try throwIfError(error, fallback: "Failed to open process control")

        guard let handle else {
            throw JITBridgeError.handleAllocationFailed("Process control")
        }
        return ProcessControl(handle: handle)
    }

    /// Launches `bundleID`, optionally suspended, and returns its pid.
    func launchApp(bundleID: String, startSuspended: Bool, killExisting: Bool) throws -> UInt64 {
        var pid: UInt64 = 0
        let error = bundleID.withCString { bundleIDPtr in
            process_control_launch_app(
                handle,
                bundleIDPtr,
                nil, 0,
                nil, 0,
                startSuspended,
                killExisting,
                &pid
            )
        }
        try throwIfError(error, fallback: "Failed to launch \(bundleID)")
        return pid
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        process_control_free(handle)
    }

    deinit {
        close()
    }
}
