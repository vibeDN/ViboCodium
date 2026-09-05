# ViboCodium
An IDE for iOS devices: a native Swift + Metal editor, a self-written
JIT enabler (`JITBridge`) on top of `idevice`, and sideload signing via
SideStore's pipeline.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the component breakdown and
build-system decisions.

## Getting started (macOS only)

```sh
make bootstrap            # pull in vendored submodules
make idevice-xcframework  # build IDevice.xcframework (device-only)
make app-build            # generate + build the ViboCodium app target
```
