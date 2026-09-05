import Foundation
import IDevice

/// Where to reach the device's local RemotePairing/RSD service.
///
/// Unlike StikDebug (which assumes a companion VPN app, e.g. LocalDevVPN,
/// has already set up a route to a fixed address like 10.7.0.1), this is
/// left as a plain parameter. The intended long-term source for this
/// address is an in-process tunnel, the way `minimuxer`'s EMProxy sets one
/// up via a userspace WireGuard loopback over a `utun` socket - no companion
/// app, no NetworkExtension entitlement. That piece isn't implemented here
/// yet; whatever sets it up is responsible for handing this module an
/// address that's actually reachable.
public struct DeviceEndpoint {
    public let address: String
    public let port: UInt16

    public init(address: String, port: UInt16 = 49152) {
        self.address = address
        self.port = port
    }
}

/// An open RSD tunnel to the device: the adapter/handshake pair every other
/// service (remote server, debug proxy, heartbeat) connects through.
final class DeviceTunnel {
    let adapter: OpaquePointer
    let handshake: OpaquePointer
    private var isClosed = false

    private init(adapter: OpaquePointer, handshake: OpaquePointer) {
        self.adapter = adapter
        self.handshake = handshake
    }

    /// Opens a fresh tunnel. `hostname` is just the name this host presents
    /// to the device during the RemotePairing handshake - it has no bearing
    /// on networking.
    static func open(endpoint: DeviceEndpoint, hostname: String, pairingFile: OpaquePointer) throws -> DeviceTunnel {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = endpoint.port.bigEndian

        let parsed = endpoint.address.withCString { inet_pton(AF_INET, $0, &addr.sin_addr) }
        guard parsed == 1 else {
            throw JITBridgeError.invalidTargetAddress(endpoint.address)
        }

        var adapter: OpaquePointer?
        var handshake: OpaquePointer?

        // idevice_sockaddr/idevice_socklen_t (see idevice.h) are plain
        // typedefs for `struct sockaddr`/`socklen_t` on non-Windows, so the
        // bare Darwin types below are the same thing as far as the importer
        // is concerned - this mirrors what StikDebug's shipped code does.
        let error = hostname.withCString { hostnamePtr -> UnsafeMutablePointer<IdeviceFfiError>? in
            withUnsafeMutablePointer(to: &addr) { addrPtr -> UnsafeMutablePointer<IdeviceFfiError>? in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    tunnel_create_rppairing(
                        sockaddrPtr,
                        socklen_t(MemoryLayout<sockaddr_in>.stride),
                        hostnamePtr,
                        pairingFile,
                        nil,
                        nil,
                        &adapter,
                        &handshake
                    )
                }
            }
        }

        try throwIfError(error, fallback: "Failed to create device tunnel")

        guard let adapter, let handshake else {
            throw JITBridgeError.handleAllocationFailed("Tunnel adapter/handshake")
        }

        return DeviceTunnel(adapter: adapter, handshake: handshake)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        rsd_handshake_free(handshake)
        adapter_free(adapter)
    }

    deinit {
        close()
    }
}
