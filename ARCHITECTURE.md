# ViboCodium — architecture notes

An IDE that runs on iOS devices: native Swift + Metal editor, a
self-written JIT enabler on top of `idevice`, on-device Swift compiler
toolchain, and on-device IPA signing. Test hardware: A14.

## Scope

1. **Jitter** — our own code, written against the raw `idevice` FFI
   (not a vendored app's wrapper). Runs automatically at our app's
   launch (self-attach via `getpid()`), no companion app, no
   NetworkExtension, no paid Apple Developer account required.
2. **Editor UI/features** — native, written in Swift + Metal (and
   Objective-C where it's the pragmatic choice, e.g. for some system
   interop). VS Code / vscodium is a *feature reference* only — we are
   not embedding its Electron shell or its source. Nothing from it is
   vendored.
3. **Swift toolchain + IPA signing** — on-device: compile Swift source,
   sign the resulting `.app` into an installable `.ipa`, all inside the
   same app.

## Components

| Path                          | Source                                       | Role                                                                 |
|--------------------------------|-----------------------------------------------|-----------------------------------------------------------------------|
| `Vendor/idevice`               | github.com/jkcoxson/idevice (MIT)             | Rust library + C FFI for device pairing, tunneling (RSD/lockdown), and the debugserver protocol. Has an official `just xcframework` recipe producing `IDevice.xcframework` (device/sim/Catalyst/macOS). This is what our own JIT module and device-communication code binds against directly. |
| `Vendor/SideStore`              | github.com/SideStore/sidestore (AGPLv3)       | Reference for the sideload install/resign pipeline. |
| `Vendor/SideStore/Dependencies/SideSign` | github.com/SideStore/SideSign          | Code signing (entitlements, provisioning, CMS signature construction) — used for the on-device IPA signing step. |
| `Vendor/SideStore/Dependencies/minimuxer` | github.com/SideStore/minimuxer        | Already solves in-process device tunneling (EMProxy: userspace WireGuard over a `utun` socket, no system VPN config, no NetworkExtension entitlement) and app install/AFC. Reference/possible dependency for the on-device install step after signing. |

Previously vendored and now dropped:
- `StikDebug` — its JIT logic depends on an external companion VPN app
  (LocalDevVPN) providing a fixed route to the device's local services.
  We don't want that dependency, and we're writing our own JIT module
  against `idevice` directly instead, so there's nothing left in that
  repo we need.
- `vscodium` — not a fork, just build scripts around `microsoft/vscode`
  (Electron). We're not embedding vscode/Electron at all; the editor is
  native. Kept as an external reference (URL only), not vendored.

All AGPLv3-licensed upstreams match this project's own license.
`idevice` is MIT, compatible either way.

## Why not Electron, why not a WebView

Electron does not run on iOS (no multi-process execution, no JIT-mapped
memory for arbitrary third-party apps). A WKWebView hosting `vscode-web`
was the fallback idea, but the current plan drops it: the editor is a
native Swift + Metal renderer (glyph atlas, GPU-composited
scrolling/terminal), not a JS engine in a WebView. VS Code is a feature
and UX reference only.

## JIT: self-written, no companion app

Both StikDebug and minimuxer implement essentially the same sequence on
top of `idevice`: read the pairing file, mount the Developer Disk Image
if needed, open an RSD/lockdown tunnel, connect a debug proxy, and send
`vAttach;<pid>` for our own process, then keep a heartbeat alive so the
process stays flagged as debugged (which keeps JIT enabled) even after
detaching. We reimplement this directly against `Vendor/idevice`'s C
API instead of vendoring either project's wrapper:

- No external VPN app (StikDebug's approach requires LocalDevVPN).
- No NetworkExtension entitlement, so no paid Apple Developer account
  requirement for this piece.
- One less large vendored dependency to track/patch.

If we need an in-process local tunnel (instead of assuming one already
exists), `minimuxer`'s EMProxy/`utun` approach is the reference to copy
from — it's the same idea SideStore already ships and does not require
a system VPN configuration.

## Swift toolchain + on-device IPA signing

On-device compile (Swift toolchain) → `.app` bundle → resign into an
installable `.ipa`, all within the same app, no separate build server.
Signing reuses `SideSign`'s entitlements/provisioning/signature
construction rather than reimplementing CMS-based code signing from
scratch. Install-onto-self-device likely needs the same AFC/installd
path `minimuxer` already implements.

Test target hardware: A14 (e.g. iPhone 12 class). On-device Swift
compilation is real work with real memory/CPU constraints on that chip
— worth budgeting for once we get there.

## Build system: no Bazel

None of the upstreams use Bazel (SideStore: `xcodebuild` + `Makefile` +
Fastlane; `idevice`: `cargo` + `just`). We keep each on its native
toolchain and glue with a root `Makefile` + an Xcode workspace, rather
than maintaining a hand-rolled Bazel graph against upstreams that move
on their own schedule.

## Status

- [x] Vendor submodules: `idevice`, `SideStore` (+ nested SideSign,
      minimuxer).
- [ ] Xcode workspace + app target scaffold.
- [ ] `JITBridge`: our own module against `Vendor/idevice`'s
      xcframework — pairing, DDI mount, tunnel, self-attach by pid,
      heartbeat keepalive.
- [ ] `SigningKit`: wraps `SideSign` for on-device IPA signing.
- [ ] On-device install step (AFC/installd, `minimuxer`-style).
- [ ] Native Metal-backed text editor core.
- [ ] On-device Swift compiler toolchain pipeline.
