.DEFAULT_GOAL := help

# Concrete simulator: test runs reject generic destinations. iPad is the primary device.
SIMULATOR = platform=iOS Simulator,name=iPad Pro 13-inch (M5)

help:
	@echo "IaPapo Build Targets"
	@echo ""
	@echo "  make build-core   Build VACore package"
	@echo "  make test-core    Run VACore tests"
	@echo "  make build-app    Build VA app for iOS Simulator"
	@echo "  make test         Run VACore and VA app tests"
	@echo "  make test-app     Run VA app tests"
	@echo "  make clean-core   Clean VACore build artifacts"
	@echo "  make clean-app    Clean VA app build artifacts"
	@echo "  make clean-all    Clean everything"

build-core:
	swift build --package-path VACore

test-core:
	swift test --package-path VACore

build-app:
	xcodebuild -project VA/VA.xcodeproj -scheme VA -destination '$(SIMULATOR)' build

test: test-core test-app

test-app:
	xcodebuild -project VA/VA.xcodeproj -scheme VA -destination '$(SIMULATOR)' test

clean-core:
	swift package --package-path VACore clean

clean-app:
	xcodebuild -project VA/VA.xcodeproj -scheme VA clean

# Restore the checkout to "as if new": remove generated and per-user state.
# Leaves local/ and .nameforma logs alone.
clean-all: clean-core clean-app
	rm -rf VACore/.build VACore/.swiftpm
	rm -rf VA/VA.xcodeproj/xcuserdata VA/VA.xcodeproj/project.xcworkspace/xcuserdata
	rm -rf ~/Library/Developer/Xcode/DerivedData/VA-*
