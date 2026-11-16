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

# Compiles the lab wake-word model into VACore's resources. The output is a build artifact, kept out of git.
build-model:
	mkdir -p VACore/Sources/VACore/Resources
	xcrun coremlcompiler compile lab/wakeword/out/JNaU8v4L6/no-take-0Q6-ou/wakenet.mlpackage VACore/Sources/VACore/Resources

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

# Applies .swiftformat (2-space indent, 80 columns, LF) to the app and core sources.
format:
	swiftformat VA/VA VACore/Sources VACore/Tests

help:
	@echo "IaPapo Build Targets"
	@echo ""
	@echo "  make build-app    Build VA app for iOS Simulator"
	@echo "  make build-core   Build VACore package"
	@echo "  make build-model  Compile the lab wake-word model into VACore resources"
	@echo "  make clean-all    Clean everything"
	@echo "  make clean-app    Clean VA app build artifacts"
	@echo "  make clean-core   Clean VACore build artifacts"
	@echo "  make format       Apply .swiftformat to the app and core Swift sources"
	@echo "  make help         Show this list"
	@echo "  make install      Check Xcode/macOS versions, build the Python env, resolve Swift packages"
	@echo "  make wake-export  Export a wake-word run, then verify it (RUN=<run id> [ARCHIVE=1])"
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
	swift test -c release --package-path VACore --skip showSwiftScores --skip scoreFromWAVMatchesPythonEval --skip wakeScoresMatchPythonEval --skip logMelMatchesPython --skip frontEndFromWAVMatchesPython --skip arrayResamplerMatchesScipy

# Wake-word matcher end to end: its unit tests, Core ML vs PyTorch match on one run, and the
# Swift front end vs Python features. RUN and TAKE are described at match. Without them, the match
# step uses the held-out run and take from the wake-word article.
WAKE_DEFAULT_RUN := lab/wakeword/out/JNaU8v4L6/no-take-0Q6-ou
WAKE_DEFAULT_TAKE := lab/wakeword/takes/20261104-075505
test-wakeword:
	$(PY) scripts/python/tests/test_wakeword_matcher.py
	$(PY) scripts/python/tests/test_nfhash.py
	$(PY) scripts/python/tests/test_train_cli.py
	$(MAKE) match RUN="$(or $(RUN),$(WAKE_DEFAULT_RUN))" TAKE="$(or $(TAKE),$(WAKE_DEFAULT_TAKE))"
	swift test -c release --package-path VACore --filter 'scoreFromWAVMatchesPythonEval|wakeScoresMatchPythonEval|logMelMatchesPython|frontEndFromWAVMatchesPython|arrayResamplerMatchesScipy'

# Held-out takes for verifying an export (see the wake-word article, "Held-out results").
HELDOUT_TAKES := lab/wakeword/takes/turtlePro/20261102-082403 lab/wakeword/takes/turtlePro/20261103-163155 lab/wakeword/takes/turtlePro/20261104-075505

# Export one run to Core ML, then verify it against the held-out takes. Writes only into the run folder.
# RUN is a run ID (e.g. RUN=0Q7YdK) or a run folder path. ARCHIVE=1 also copies the verified model
# and records into models/ after verification passes.
RUN_DIR = $(if $(findstring /,$(RUN)),$(RUN),$(firstword $(wildcard lab/wakeword/out/*/no-take-$(RUN))))
wake-export:
	@test -n "$(RUN)" || { echo "make wake-export needs RUN=<run id or run folder>"; exit 1; }
	@test -n "$(RUN_DIR)" || { echo "wake-export: no run folder for RUN=$(RUN)"; exit 1; }
	@$(PY) -c "import json,sys; sys.exit(0 if json.load(open('$(RUN_DIR)/run.json')).get('window_len') else 1)" || { echo "wake-export: $(RUN_DIR)/run.json has no window_len; retrain the run"; exit 1; }
	$(PY) scripts/python/export_coreml.py $(RUN_DIR)
	swift build -c release --package-path VACore --product eval_take
	@for take in $(HELDOUT_TAKES); do $(PY) scripts/python/test_coreml_match.py $(RUN_DIR) $$take || exit 1; done
	@for take in $(HELDOUT_TAKES); do scripts/eval-take.sh $(RUN_DIR) $$take --pipeline both || exit 1; done
	$(PY) scripts/python/verify_export.py $(RUN_DIR) $(HELDOUT_TAKES)
	@if [ "$(ARCHIVE)" = "1" ]; then scripts/archive-export.sh $(RUN_DIR); else echo "verified; not archived (add ARCHIVE=1 to archive)"; fi

wake-base:
	scripts/train.sh $(ARGS)
	say -v "Voice 1" "Trained wakeword base model"
	scripts/train-summary.py

wake-sample:
	scripts/sample_agents.sh
