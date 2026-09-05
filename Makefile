.PHONY: help bootstrap clean

help:
	@echo "Targets:"
	@echo "  bootstrap  - fetch/update all vendor submodules (incl. nested)"
	@echo "  clean      - remove untracked build artifacts (not submodules)"

bootstrap:
	git submodule update --init --recursive

clean:
	git clean -fdx -e Vendor
