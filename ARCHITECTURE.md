# ViboCodium — architecture notes

An IDE that runs on iOS devices: native Swift editor, on-device JIT via
StikDebug, sideload signing via SideStore's pipeline.

## Components

| Path                          | Source                                       | Role                                                                 |
|--------------------------------|-----------------------------------------------|-----------------------------------------------------------------------|
| `Vendor/StikDebug`             | github.com/StikDebug/stikdebug (AGPLv3)       | On-device JIT enable + device pairing/mounting, via vendored `idevice` (Rust) FFI. Source for `IdeviceFFIBridge.swift`, `JITEnableContext.swift`, `mountDDI.swift`. |
| `Vendor/SideStore`              | github.com/SideStore/sidestore (AGPLv3)       | Sideload install/resign pipeline (free-dev-cert refresh, no jailbreak). |
| `Vendor/SideStore/Dependencies/SideSign` | github.com/SideStore/SideSign          | Code signing (entitlements, provisioning) used by SideStore.          |
| `Vendor/SideStore/Dependencies/minimuxer` | github.com/SideStore/minimuxer        | Device tunnel/muxer (Rust), used by SideStore to talk to the device.  |
| `Vendor/vscodium`               | github.com/VSCodium/vscodium (MIT)            | Not a fork — build scripts that pull `microsoft/vscode` and strip MS branding/telemetry. Kept as a reference for extension/grammar/LSP compatibility, not for its Electron shell. |

All AGPLv3-licensed upstreams match this project's own license — no
relicensing needed when we copy code out of them into our own modules.

## Why not Electron

`vscodium` is build tooling around `microsoft/vscode`, which is an
Electron app (Chromium + Node). Electron does not run on iOS: it needs
multi-process execution and JIT-mapped memory that the iOS app sandbox
does not grant to arbitrary third-party apps. There is no viable port.

## Editor: native Swift + Metal, not a WebView

The editor surface itself is written natively in Swift, using Metal for
text/terminal rendering (glyph atlas, GPU-composited scrolling), the way
Zed/Warp do it — not a WKWebView hosting `vscode-web`. This drops the
JS-engine-in-a-WebView problem entirely for the core editor UI.

`vscodium`/`microsoft/vscode` still matters as a *compatibility*
reference: TextMate grammars, themes, and the LSP client protocol are
worth reusing as data/spec, not as running Electron code.

JIT (via StikDebug's approach) remains necessary for anything that has to
execute arbitrary JS/interpreted code on-device — e.g. a VS Code
extension host, if/when we support real extensions. It is not required
for the native editor UI itself.

## Build system: no Bazel

None of the three upstreams use Bazel, and there's no upside to
introducing it:

- `vscode`/`vscodium`: gulp + webpack + yarn, a large JS/TS toolchain
  upstream itself doesn't run through Bazel.
- `SideStore`: `xcodebuild` driven by a `Makefile`, plus Fastlane for
  tests, with its own dependencies as git submodules.
- `StikDebug`: a plain Xcode project + one SPM package + a vendored
  precompiled `idevice` static lib (`libidevice_ffi.a`, ~93MB, built
  from the Rust `idevice` crate).

Rewriting any of this under `rules_apple`/`rules_swift`/`rules_nodejs`
would mean maintaining a hand-rolled build graph against upstreams that
change on their own schedule (vscode ships every two weeks). We keep
each vendor on its native toolchain and glue things together with a
top-level `Makefile` + an Xcode workspace, matching what SideStore
already does for itself.

## Status

- [x] Vendor submodules wired up (StikDebug, SideStore incl. nested
      SideSign/minimuxer, vscodium).
- [ ] Xcode workspace + app target scaffold.
- [ ] `JITBridge` local Swift package wrapping StikDebug's device/JIT
      code + vendored `idevice` lib.
- [ ] `SigningKit` local Swift package wrapping SideStore's
      SideSign/minimuxer pipeline for IPA signing.
- [ ] Native Metal-backed text editor core.
- [ ] Swift compiler pipeline (on-device vs. remote build — undecided).
