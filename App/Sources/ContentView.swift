import SwiftUI
import JITBridge

/// Placeholder scaffold, not the real editor UI: proves the app target
/// actually links and calls into JITBridge, not just that the package
/// compiles standalone. Real usage needs a stored pairing file and a
/// reachable tunnel endpoint - see Modules/JITBridge/README.md - so this
/// will fail with a clear error until that plumbing exists.
struct ContentView: View {
    @State private var status = "Not attempted"

    var body: some View {
        VStack(spacing: 16) {
            Text("ViboCodium")
                .font(.largeTitle)
            Text(status)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Enable self JIT") {
                enableSelfJIT()
            }
        }
        .padding()
    }

    private func enableSelfJIT() {
        status = "Attaching..."
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try JITBridge.enableSelfJIT(endpoint: DeviceEndpoint(address: "127.0.0.1"))
                DispatchQueue.main.async { status = "JIT enabled" }
            } catch {
                DispatchQueue.main.async { status = "Failed: \(error)" }
            }
        }
    }
}
