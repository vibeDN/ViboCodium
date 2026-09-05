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

## Plugins: language-support extensions only, not arbitrary JS extensions

Scope is deliberately narrowed to *language extensions* — the ones that
add support for a language (grammar, theme, snippets, language server),
not general-purpose extensions with arbitrary logic/UI (GitLens-style
things). That's a much smaller, fully achievable target in two tiers,
with no Node.js and no VS Code extension host anywhere in this app:

1. **Declarative contributions — no JS execution at all.** Nearly all
   language extensions are just data: TextMate grammars, color/icon
   themes, snippets, and language configuration declared in
   `package.json`'s `contributes` block. We parse and render these
   natively (our own TextMate-grammar interpreter + theme engine).
   This alone buys VS Code-grade syntax highlighting and theming for
   any language that has a published extension, without running any
   extension code.
2. **LSP client, native, no extension host involved.** Language Server
   Protocol is a standard JSON-RPC-over-stdio protocol; a native Swift
   LSP client spawns and talks to any language server directly.
   `sourcekit-lsp` ships with the Swift toolchain we already need for
   compilation, so Swift smart-editing (autocomplete, diagnostics,
   go-to-definition) comes essentially for free from the toolchain work.
   Other languages get the same treatment: point the client at
   whatever LSP server that language's extension bundles or expects.

A full VS Code extension host (real Node.js + V8, running arbitrary
marketplace JS extensions via the full `vscode` API surface) is
explicitly out of scope — that was a multi-year effort even for Eclipse
Theia's dedicated team, and it isn't needed for language support, which
is the actual goal here.

### Tier 3: the toolchain itself, not just editing support

A language extension shouldn't just make a language look nice — it
should be able to bring a real compiler/interpreter for that language
and actually run code, the same way the Swift toolchain does. This
needs the same trick the jitter already relies on, generalized:

iOS's codesign enforcement blocks executing any binary that wasn't part
of the app's signature at install time — that applies to a downloaded
Python interpreter or a downloaded C compiler exactly as much as it
applies to freshly-compiled Swift output. A debug-flagged
(JIT-enabled) process is exempted from that, so the same mechanism
covers both:

- `dlopen` a downloaded interpreter/compiler as a dylib inside our
  already-JIT-enabled main process, or
- launch a separate toolchain binary as a helper process and
  `vAttach` it the same way we self-attach (debug-flag someone else's
  pid instead of our own).

So `JITBridge` shouldn't be built as a one-shot "JIT-enable myself at
launch" module — it should expose a general "launch/load a binary under
a debug flag" primitive, and both the Swift edit-compile-run loop and
any language extension's toolchain are just callers of it. The debug
flag only lasts for the life of the process, so this has to be redone
each cold launch — which we're already doing anyway for the Swift
loop, so toolchains piggyback on the same moment for free.

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

**What the jitter is actually for, now that plugins don't need it:**
the edit-compile-run loop. iOS's AMFI won't execute freshly-generated
code pages in a running process unless that process is JIT-enabled or
flagged as debugged — that blocks a fast "Run" button (compile new
Swift code on-device and execute it immediately) which would otherwise
need a full resign-and-reinstall cycle every time. Self-JIT is what
makes a tight edit-compile-run loop possible at all.

## Swift toolchain + on-device IPA signing

On-device compile (Swift toolchain) → `.app` bundle → resign into an
installable `.ipa`, all within the same app, no separate build server.
Signing reuses `SideSign`'s entitlements/provisioning/signature
construction rather than reimplementing CMS-based code signing from
scratch. Install-onto-self-device likely needs the same AFC/installd
path `minimuxer` already implements.

The signed-reinstall path (via SideSign/minimuxer) is for producing a
real, persistent, installed `.ipa`. The jitter-enabled fast path (see
above) is for iterating during development without paying that cost on
every change.

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
- [x] `JITBridge` (`Modules/JITBridge`): pairing file storage, tunnel,
      debug session, heartbeat keepalive, and the general "debug-flag a
      pid" primitive (`JITBridge.attach`/`enableSelfJIT`), written
      directly against `Vendor/idevice`'s current FFI signatures.
      Compiles clean on a real macOS/Xcode CI runner (GitHub Actions,
      `.github/workflows/jitbridge-ci.yml`) against a device-only
      `IDevice.xcframework`. Not yet exercised against a real device -
      DDI mount and getting a pairing file in the first place are still
      open (see the module's README).
- [ ] `SigningKit`: wraps `SideSign` for on-device IPA signing.
- [ ] On-device install step (AFC/installd, `minimuxer`-style).
- [ ] `RemoteServer`/`ProcessControl` (already in `JITBridge`, unused
      so far) wired up to actually launch+attach a toolchain helper
      process, not just self-attach.
- [ ] Native Metal-backed text editor core.
- [ ] On-device Swift compiler toolchain pipeline (first consumer of
      `JITBridge`'s debug-flag primitive).
- [ ] Per-language toolchain loading (dlopen'd interpreter, or a
      debug-flagged helper process) for non-Swift language extensions.
- [ ] Language-extension tier 1: TextMate grammar + theme engine
      (declarative extension contributions, no JS).
- [ ] Language-extension tier 2: native LSP client (sourcekit-lsp
      first).
