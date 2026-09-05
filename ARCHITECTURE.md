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
   interop). We are not embedding VS Code's Electron shell or its
   source — but we do want its ecosystem value (plugins, polish). See
   "Plugins / VS Code compatibility" below for how that's staged.
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

## Plugins / VS Code compatibility (tiered)

Real, full VS Code extension-API compatibility is a multi-year effort
(it took Eclipse Theia's dedicated team years to get most of the way
there). Rather than promise that, this is staged so each tier ships
real value on its own and the next tier builds on it:

1. **Declarative contributions — no JS execution at all.** A large
   share of real-world extensions are just data: themes, TextMate
   grammars, snippets, and language configuration declared in
   `package.json`'s `contributes` block. We parse and render these
   natively (our own TextMate-grammar interpreter + theme engine).
   This alone buys VS Code-grade syntax highlighting and theming, and
   most of "looks and feels like vscode," without running any
   extension code.
2. **LSP client, independent of VS Code's extension host.** Language
   Server Protocol is a standard JSON-RPC-over-stdio protocol; a
   native Swift LSP client can drive any language server directly.
   `sourcekit-lsp` ships with the Swift toolchain we already need for
   compilation, so Swift smart-editing (autocomplete, diagnostics,
   go-to-definition) comes essentially for free from tier 3's toolchain
   work, no Node involved.
3. **Real extension host, for actual marketplace JS extensions.**
   Embed `nodejs-mobile` (community-maintained Node.js port for
   iOS/Android, MIT — the original Janea Systems project, now at
   github.com/nodejs-mobile/nodejs-mobile) to run vscode's own
   `extensionHostProcess.js` bundle, and implement the native side of
   its RPC protocol (`MainThreadDocuments`, `MainThreadEditors`, etc.)
   incrementally, API by API, starting from whatever the
   highest-value/most-used extensions actually touch. This is where
   the jitter matters again — not for the whole UI anymore, just to
   get JIT-speed V8 in this one process instead of interpreter-only.

Tiers 1 and 2 are the realistic near-term scope. Tier 3 is real but
open-ended; treat it as "grows extension by extension," not a
one-shot deliverable.

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
- [ ] Tier 1: TextMate grammar + theme engine (declarative extension
      contributions, no JS).
- [ ] Tier 2: native LSP client (sourcekit-lsp first).
- [ ] Tier 3: nodejs-mobile + real extension host RPC (open-ended).
