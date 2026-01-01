# PHP-iOS Makefile
# Builds the complete PHP-iOS Swift Package

.PHONY: all build test clean sample-app sample-app-sim build-php build-php-device build-php-sim evo evo-force ensure-php-lib ensure-php-lib-sim clean-php-build clean-php-libs

# Default target
all: build

# Build the Swift package
build:
	@echo "Building PHP-iOS Swift Package..."
	swift build

# Run tests
test:
	@echo "Running tests..."
	swift test

# Build sample app
sample-app: ensure-php-lib
	@echo "Building sample app (iOS device)..."
	@cd SampleApp && \
	SDK_PATH="$$(xcrun --sdk iphoneos --show-sdk-path)" && \
	TOOLCHAIN_BIN="$$(dirname "$$(xcrun --find swiftc)")" && \
	TARGET="arm64-apple-ios16.0" && \
	ROOT_DIR="$$(pwd -P)/.." && \
	LIB_DIR="$$ROOT_DIR/Sources/PhpIOS/lib" && \
	DEST="$$(mktemp -t ios-device-destination)" && \
	printf '{\n  "version": 1,\n  "sdk": "%s",\n  "toolchain-bin-dir": "%s",\n  "target": "%s",\n  "extra-cc-flags": ["-isysroot", "%s"],\n  "extra-swiftc-flags": [],\n  "extra-cpp-flags": ["-isysroot", "%s"],\n  "extra-linker-flags": ["-isysroot", "%s", "-L", "%s"]\n}\n' "$$SDK_PATH" "$$TOOLCHAIN_BIN" "$$TARGET" "$$SDK_PATH" "$$SDK_PATH" "$$SDK_PATH" "$$LIB_DIR" > "$$DEST" && \
	swift build --destination "$$DEST" && \
	rm -f "$$DEST"

# Build + run sample app in iOS simulator
sample-app-sim: ensure-php-lib-sim
	@echo "Building sample app (iOS simulator)..."
	@cd SampleApp && \
	set -e; \
	SIM_NAME="$${SIM_NAME:-iPhone 17 Pro Max}"; \
	SIM_ID="$${SIM_ID:-E484F833-DE24-4985-A93A-3476886C9672}"; \
	SIM_ARCH="$${SIM_ARCH:-arm64}"; \
	DESTINATION="platform=iOS Simulator"; \
	if [ -n "$$SIM_ID" ]; then \
		DESTINATION="$$DESTINATION,id=$$SIM_ID"; \
	else \
		DESTINATION="$$DESTINATION,name=$$SIM_NAME"; \
	fi; \
	if [ -n "$$SIM_ARCH" ]; then \
		DESTINATION="$$DESTINATION,arch=$$SIM_ARCH"; \
	fi; \
	SIM_TARGET="$$SIM_NAME"; \
	if [ -n "$$SIM_ID" ]; then \
		SIM_TARGET="$$SIM_ID"; \
	fi; \
	ROOT_DIR="$$(pwd -P)/.."; \
	DERIVED_DATA="$$(pwd -P)/.build/DerivedData"; \
	PHP_LIB_DIR="$$ROOT_DIR/Sources/PhpIOS/lib-sim"; \
	APP_PATH="$$(find "$$DERIVED_DATA/Build/Products" -name "SampleApp.app" -print -quit 2>/dev/null || true)"; \
	if [ -n "$$APP_PATH" ] && [ ! -f "$$APP_PATH/Info.plist" ]; then \
		rm -rf "$$APP_PATH"; \
		APP_PATH=""; \
	fi; \
	PHP_IOS_LIB_DIR="$$PHP_LIB_DIR" xcodebuild \
		-workspace SampleApp.xcodeproj/project.xcworkspace \
		-scheme SampleApp \
		-destination "$$DESTINATION" \
		-configuration Debug \
		ONLY_ACTIVE_ARCH=YES \
		EXCLUDED_ARCHS="x86_64" \
		-derivedDataPath "$$DERIVED_DATA" \
		build; \
	APP_PATH="$$(find "$$DERIVED_DATA/Build/Products" -name "SampleApp.app" -print -quit 2>/dev/null || true)"; \
	if [ -z "$$APP_PATH" ]; then \
		echo "Sample app not found in DerivedData"; \
		exit 1; \
	fi; \
	if [ ! -f "$$APP_PATH/Info.plist" ]; then \
		echo "Info.plist not found in $$APP_PATH"; \
		exit 1; \
	fi; \
	BUNDLE_ID="$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$$APP_PATH/Info.plist")"; \
	xcrun simctl boot "$$SIM_TARGET" >/dev/null 2>&1 || true; \
	xcrun simctl bootstatus "$$SIM_TARGET" -b; \
	xcrun simctl install "$$SIM_TARGET" "$$APP_PATH"; \
	xcrun simctl launch "$$SIM_TARGET" "$$BUNDLE_ID"

# Ensure PHP static library exists
ensure-php-lib:
	@if [ ! -f Sources/PhpIOS/lib/libphp-ios.a ]; then \
		echo "Missing Sources/PhpIOS/lib/libphp-ios.a. Building PHP static library..."; \
		$(MAKE) build-php; \
	fi

# Ensure PHP static library exists (simulator)
ensure-php-lib-sim:
	@if [ ! -f Sources/PhpIOS/lib-sim/libphp-ios.a ]; then \
		echo "Missing Sources/PhpIOS/lib-sim/libphp-ios.a. Building PHP static library for simulator..."; \
		$(MAKE) build-php-sim; \
	fi

# Build PHP static library
build-php: build-php-device

build-php-device:
	@echo "Building PHP static library (device)..."
	cd Toolchain && ./build-php.sh --sdk=iphoneos

build-php-sim:
	@echo "Building PHP static library (simulator)..."
	cd Toolchain && ./build-php.sh --sdk=iphonesimulator

clean-php-build:
	@echo "Cleaning PHP build artifacts..."
	rm -rf Toolchain/build
	rm -rf Toolchain/sdk-device Toolchain/sdk-sim

clean-php-libs:
	@echo "Cleaning PHP libraries..."
	rm -rf Sources/PhpIOS/lib/bin Sources/PhpIOS/lib/include Sources/PhpIOS/lib/lib
	rm -rf Sources/PhpIOS/lib/php Sources/PhpIOS/lib/var
	rm -f Sources/PhpIOS/lib/libphp-ios.a
	rm -rf Sources/PhpIOS/lib-sim

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	swift package clean
	rm -rf .build
	rm -rf SampleApp/.build
	rm -rf Toolchain/build
	rm -rf Toolchain/php-*
	rm -rf Toolchain/sdk-device Toolchain/sdk-sim

# Install dependencies
deps:
	@echo "Installing dependencies..."
	swift package resolve

# Generate Xcode project
xcode:
	@echo "Generating Xcode project..."
	swift package generate-xcodeproj

# Format code
format:
	@echo "Formatting Swift code..."
	find Sources Tests SampleApp -name "*.swift" -exec swift-format -i {} \;

# Lint code
lint:
	@echo "Linting Swift code..."
	find Sources Tests SampleApp -name "*.swift" -exec swift-format lint {} \;

# Help
help:
	@echo "Available targets:"
	@echo "  build       - Build the Swift package"
	@echo "  test        - Run tests"
	@echo "  sample-app  - Build sample app (iOS device)"
	@echo "  sample-app-sim - Build and run sample app (iOS simulator)"
	@echo "  evo         - Run full pipeline (skip existing libs)"
	@echo "  evo-force   - Run full pipeline from scratch"
	@echo "  build-php   - Build PHP static library (device)"
	@echo "  build-php-sim - Build PHP static library (simulator)"
	@echo "  clean-php-build - Clean PHP build artifacts"
	@echo "  clean-php-libs  - Remove built PHP libraries"
	@echo "  clean       - Clean build artifacts"
	@echo "  deps        - Install dependencies"
	@echo "  xcode       - Generate Xcode project"
	@echo "  format      - Format Swift code"
	@echo "  lint        - Lint Swift code"
	@echo "  help        - Show this help"
# Build PHP libs + tests + sample app (simulator)
evo:
	@set -e; \
	$(MAKE) ensure-php-lib; \
	$(MAKE) ensure-php-lib-sim; \
	$(MAKE) clean-php-build; \
	$(MAKE) test; \
	$(MAKE) sample-app-sim;

# Build everything from scratch
evo-force:
	@set -e; \
	$(MAKE) clean; \
	$(MAKE) clean-php-libs; \
	$(MAKE) build-php-device; \
	$(MAKE) build-php-sim; \
	$(MAKE) clean-php-build; \
	$(MAKE) test; \
	$(MAKE) sample-app-sim;
