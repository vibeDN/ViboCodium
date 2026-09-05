.PHONY: help bootstrap idevice-xcframework app-project app-build clean

help:
	@echo "Targets:"
	@echo "  bootstrap           - fetch/update all vendor submodules (incl. nested)"
	@echo "  idevice-xcframework - build Vendor/idevice's IDevice.xcframework (macOS only)"
	@echo "  app-project         - generate App/ViboCodium.xcodeproj via XcodeGen (macOS only)"
	@echo "  app-build           - build the ViboCodium app target, unsigned (macOS only)"
	@echo "  clean               - remove untracked build artifacts (not submodules)"

bootstrap:
	git submodule update --init --recursive

# JITBridge depends on Vendor/idevice/swift, which needs IDevice.xcframework
# built before it resolves. Requires a Mac (cross-compiles the Rust crate
# for aarch64-apple-ios, then `xcodebuild -create-xcframework`) - see
# Modules/JITBridge/README.md. Builds device-only, not idevice's own
# `just xcframework` (which also builds simulator/Catalyst/macOS slices we
# don't need - we only ever target a real device).
idevice-xcframework:
	./scripts/build-idevice-xcframework.sh

# Requires `brew install xcodegen`. Regenerates App/ViboCodium.xcodeproj
# from App/project.yml - the .xcodeproj itself isn't checked into git.
app-project:
	cd App && xcodegen generate

app-build: app-project
	cd App && xcodebuild build -project ViboCodium.xcodeproj -scheme ViboCodium \
		-destination 'generic/platform=iOS' \
		CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

clean:
	git clean -fdx -e Vendor
