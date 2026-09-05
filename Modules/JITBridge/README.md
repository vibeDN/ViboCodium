# JITBridge

A general "debug-flag a pid" primitive, written directly against
`Vendor/idevice`'s C API (not a vendored app's Swift wrapper). See
`ARCHITECTURE.md` at the repo root for the full rationale.

Public API is `JITBridge.attach(pid:endpoint:hostname:holding:)` and the
`JITBridge.enableSelfJIT(endpoint:)` convenience for self-attaching this
process. Both the Swift edit-compile-run loop and any per-language
toolchain helper process are meant to call the same primitive - there is
nothing StikDebug- or self-JIT-specific baked in below the public API.

## Build prerequisite: `IDevice.xcframework`

This package declares its own `.binaryTarget` pointing directly at
`Vendor/idevice/swift/IDevice.xcframework` - a build artifact that is
**not checked into the repo** and must be produced locally before this
package resolves. Building it requires a Mac (it invokes `xcodebuild
-create-xcframework` and cross-compiles the underlying Rust crate):

Deliberately *not* consumed via `Vendor/idevice/swift/Package.swift` as a
package dependency: that manifest declares `// swift-tools-version: 5.3`
with a space before the version number, which is only valid syntax for
tools-version 5.4+ - newer toolchains (Xcode 26.6+) reject it outright
with "horizontal whitespace sequence ... supported by only Swift >=
5.4". That's a real bug upstream we can't fix inside a submodule, so
`JITBridge`'s own `Package.swift` binds straight to the `.xcframework`
file instead of resolving their manifest at all.

```sh
make idevice-xcframework   # or: ./scripts/build-idevice-xcframework.sh
```

This runs `scripts/build-idevice-xcframework.sh`, not idevice's own `just
xcframework` recipe - that recipe also builds simulator/Catalyst/macOS
slices, which we don't need: we only ever target a real iOS device, and
those other platforms already have Xcode and real VS Code. Our script
builds just the `aarch64-apple-ios` slice, which is most of what made the
full recipe slow.

This cannot be done from this Linux sandbox - there is no Xcode, no iOS
SDK, and no Apple Rust cross-toolchain here. The Swift source in this
package has been written and reviewed against `Vendor/idevice`'s current
FFI signatures (`ffi/src/*.rs`), but has not been compiled or run - that
has to happen on a Mac with the xcframework in place. CI
(`.github/workflows/jitbridge-ci.yml`) does exactly that on a
GitHub-hosted macOS runner.

## What's deliberately not here yet

- **Getting a pairing file in the first place.** `PairingFile` only
  stores/reads one; the one-time pairing UX (or however we end up
  obtaining it) is a separate piece.
- **The local tunnel endpoint.** `DeviceEndpoint` is a plain
  address/port the caller supplies. The intended long-term source is an
  in-process tunnel along the lines of `minimuxer`'s EMProxy (userspace
  WireGuard over a `utun` socket, no companion VPN app, no
  NetworkExtension entitlement) - not implemented here yet.
