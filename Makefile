.DEFAULT_GOAL := help

# Concrete simulator: test runs reject generic destinations. iPad is the primary device.
SIMULATOR = platform=iOS Simulator,name=iPad Pro 13-inch (M5)

help:
	@echo "IaPapo Build Targets"
	@echo ""
	@echo "  make build-core   Build VACore package"
	@echo "  make test-core    Run VACore tests"
	@echo "  make test-py      Run Core ML parity test on a wake-word run (RUN=<run folder>)"
	@echo "  make wake-sample  Generate wake-word samples for every agent voice (scripts/sample_agents.sh)"
	@echo "  make wake-base    Train the base wake-word CNN and write a run folder (scripts/train.sh)"
	@echo "  make build-app    Build VA app for iOS Simulator"
	@echo "  make test-all     Run VACore, VA app and Core ML parity tests"
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

# Core ML parity for one wake-word run. The run folder must already hold wakenet.pt,
# wakenet.mlpackage (scripts/export_coreml.py) and run.json. Override with RUN=<folder>.
RUN ?= lab/wakeword/out/0Q6YVG/20261102-082403-0Q6YVH

test-py:
	lab/wakeword/.venv-export/bin/python scripts/test_coreml_parity.py $(RUN)

test-all: test-core test-app test-py

wake-sample:
	scripts/sample_agents.sh

wake-base:
	scripts/train.sh $(ARGS)
	say -v "Voice 1" "Trained wakeword base model"
	scripts/train-summary.py

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
