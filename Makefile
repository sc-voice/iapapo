.DEFAULT_GOAL := help

# Concrete simulator: test runs reject generic destinations. iPad is the primary device.
SIMULATOR = platform=iOS Simulator,name=iPad Pro 13-inch (M5)

# Toolchain the project is built and verified with. install fails if the machine differs.
XCODE_EXPECT = 26.2
MACOS_EXPECT = 26.5
# One Python environment for training, export and match checks (pyproject.toml, locked in uv.lock).
PY = .venv/bin/python

build-app:
	xcodebuild -project VA/VA.xcodeproj -scheme VA -destination '$(SIMULATOR)' build

build-core:
	swift build --package-path VACore

# Restore the checkout to "as if new": remove generated and per-user state.
# Leaves local/ and .nameforma logs alone.
clean-all: clean-core clean-app
	rm -rf VACore/.build VACore/.swiftpm
	rm -rf VA/VA.xcodeproj/xcuserdata VA/VA.xcodeproj/project.xcworkspace/xcuserdata
	rm -rf ~/Library/Developer/Xcode/DerivedData/VA-*

clean-app:
	xcodebuild -project VA/VA.xcodeproj -scheme VA clean

clean-core:
	swift package --package-path VACore clean

help:
	@echo "IaPapo Build Targets"
	@echo ""
	@echo "  make build-app    Build VA app for iOS Simulator"
	@echo "  make build-core   Build VACore package"
	@echo "  make clean-all    Clean everything"
	@echo "  make clean-app    Clean VA app build artifacts"
	@echo "  make clean-core   Clean VACore build artifacts"
	@echo "  make help         Show this list"
	@echo "  make install      Check Xcode/macOS versions, build the Python env, resolve Swift packages"
	@echo "  make export       Core ML export of a wake-word run (RUN=<run folder>)"
	@echo "  make match        Core ML vs PyTorch match on a wake-word run (RUN=<run folder> TAKE=<take folder>)"
	@echo "  make report-loc   Print lines of tracked code by area and language"
	@echo "  make test-all    Run VACore, VA app and wake-word matcher tests"
	@echo "  make test-app     Run VA app tests"
	@echo "  make test-core    Run VACore tests"
	@echo "  make test-wakeword Run wake-word matcher unit tests, Core ML match and Swift front-end match"
	@echo "  make wake-base    Train the base wake-word CNN and write a run folder (scripts/train.sh)"
	@echo "  make wake-sample  Generate wake-word samples for every agent voice (scripts/sample_agents.sh)"

# One-time setup on a fresh checkout. Does not train or build the app.
install:
	@xcodebuild -version | head -1 | grep -q "^Xcode $(XCODE_EXPECT)$$" || \
		{ echo "install: need Xcode $(XCODE_EXPECT), found: $$(xcodebuild -version | head -1)"; exit 1; }
	@sw_vers -productVersion | grep -q "^$(MACOS_EXPECT)" || \
		{ echo "install: need macOS $(MACOS_EXPECT).x, found: $$(sw_vers -productVersion)"; exit 1; }
	@command -v uv >/dev/null || { echo "install: needs uv (brew install uv)"; exit 1; }
	uv sync --frozen
	swift package --package-path VACore resolve
	@$(PY) -c "import sys, torch, coremltools; print('python     ', sys.version.split()[0]); print('torch      ', torch.__version__); print('coremltools', coremltools.__version__)" 2>/dev/null
	@echo "install: ready"

# Core ML export for one wake-word run: writes wakenet.mlpackage and export.json into the run folder.
# RUN has no default: pass it, e.g. make export RUN=lab/wakeword/out/<version>/<run>.
export:
	@test -n "$(RUN)" || { echo "make export needs RUN=<run folder>"; exit 1; }
	scripts/export.sh $(RUN)

# Core ML match for one wake-word run on one take. The run folder must already hold wakenet.pt,
# wakenet.mlpackage (scripts/python/export_coreml.py) and run.json. RUN and TAKE have no default: pass both.
match:
	@test -n "$(RUN)" -a -n "$(TAKE)" || { echo "make match needs RUN=<run folder> TAKE=<take folder>"; exit 1; }
	$(PY) scripts/python/test_coreml_match.py $(RUN) $(TAKE)

report-loc:
	scripts/report-loc.sh

test-all: test-core test-app test-wakeword

test-app:
	xcodebuild -project VA/VA.xcodeproj -scheme VA -destination '$(SIMULATOR)' test

test-core:
	swift test --package-path VACore

# Wake-word matcher end to end: its unit tests, Core ML vs PyTorch match on one run, and the
# Swift front end vs Python features. RUN and TAKE are described at match.
test-wakeword:
	$(PY) scripts/python/tests/test_wakeword_matcher.py
	$(PY) scripts/python/tests/test_nfhash.py
	$(MAKE) match
	swift test -c release --package-path VACore --filter logMel

wake-base:
	scripts/train.sh $(ARGS)
	say -v "Voice 1" "Trained wakeword base model"
	scripts/train-summary.py

wake-sample:
	scripts/sample_agents.sh
