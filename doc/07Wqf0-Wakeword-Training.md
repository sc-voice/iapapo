---
type: nameforma.md
zuid: 07Wqf04JG93DcfScN77pEK
collection: world
title: "07Wqf0-Wakeword-Training"
description: How the IaPapo wake-word model is trained, exported, checked against Python and Swift, and the live test planned for the training wizard
agent_instructions: "Follow high-stakes readback/hearback communication protocol with human confirmation before taking any action that changes stored data"
---

## Overview

This is the operational article for the IaPapo wake word: how a model is trained from the Training Wizard's clips, how it is exported and checked, and what runs next. For the design history, see [[07WqEVFnlDiApKhTb0c0Wt]] (Wakeword Research).

The current model is `0Q6-ou`: seed 5 of the `JNaU8v4L6` sweep, exported to Core ML.

## Data

- **Takes.** Recorded by the Training Wizard on the iPad, one speaker, one device. Each take holds three positives and one to three negatives. Held-out takes are `20261102-082403`, `20261103-163155` and `20261104-075505`. Clips in the training set must not be used to judge the model.
- **Format.** Mono WAV from the wizard. The training loader resamples 48 kHz to 16 kHz with `resample_poly` and averages channels if a clip is not mono.
- **Trimming.** Training trims positives and negatives to speech onset and offset, with 0.1 s of padding. Saved files do not change. Held-out takes and the live path are not trimmed, since a take is a live recording and the live path cannot know where speech starts.
- **Window.** 0.893 s (14287 samples), set by the longest trimmed positive, so every wake word fits whole. Scoring slides the window every 0.25 s.

## Pipeline

1. Resample each clip to 16 kHz and average channels if needed.
2. Trim positives and negatives. Background noise is added as augmentation, so no silence-only file is needed.
3. Extract log-mel features: 25 ms frames, 10 ms frame period, 40 mel bands.
4. Train `WakeNet` in PyTorch with `scripts/python/train.py`. Save the weights and each clip's window scores to `scores.csv` in `lab/wakeword/out/<version>/no-take-<run id>/`.
5. Export to Core ML with `scripts/export.sh <run folder>`. This writes `wakenet.mlpackage` and archives `run.json`, `scores.csv`, `run.log`, `train.json` and `export.json` under `models/wakeword/<version>/<run id>/`. An archive made from a commit is not overwritten.
6. Evaluate on held-out takes with `scripts/eval-take.sh <run id> <take>`. It runs both pipelines by default: `scripts/python/eval_take.py`, and the Swift `eval_take` executable. The Swift one needs `swift build -c release --package-path VACore --product eval_take`, since a debug build is about 130 times slower. `--pipeline python` or `--pipeline swift` runs one side. Each record has a `pipeline` field, and `scripts/eval-table.py <run id> [eval ids] --threshold <t>` shows Python and Swift scores side by side. Without eval ids it uses the newest record for each take and pipeline.

## Verification

- **Core ML against PyTorch.** `scripts/python/test_coreml_match.py <run folder> <take folder>` scores every window through both models. On `0Q6-ou` and take `20261104-075505`, all 69 windows match, with max difference 2.3e-06 against tolerance 1e-3. Record: `match-<id>.json` in the run folder.
- **Swift front end against Python.** `VACore` test `logMelMatchesPython` compares `LogMelFrontEnd` with reference features from `scripts/python/export_frontend_reference.py`. It passes on the 69 windows of `20261104-075505`. The test covers features only, not resampling and not scores. Reference data lives in `lab/wakeword/reference/frontend/`.
- **Swift scores against Python eval.** `VACore` test `wakeScoresMatchPythonEval` runs the Swift front end and the Core ML model on the same windows and compares per-clip maximum probabilities with `eval-0Q70Tk.json`, within 1e-3. It passes for `0Q6-ou` on `20261104-075505`. It covers that one take only.
- **Swift resampler against scipy.** `VACore` test `arrayResamplerMatchesScipy` runs `ArrayResampler48To16`, the whole-clip version, on a 48 kHz take and compares the taps and output with `resample_poly`, within 1e-12 for taps and 1e-6 for samples. It covers a whole clip and a clip whose length is not a multiple of 3. Reference data comes from `scripts/python/export_resample_reference.py`, into `lab/wakeword/reference/resample/`.
- **Streaming resampler against the whole-clip version.** `VACore` test `streamingResamplerMatchesWholeClip` feeds the take, chunked by `WAVStreamer`, through `Resampler48To16` in chunk sizes 4000, 4096, 977 and 1. Output equals `ArrayResampler48To16` exactly at every size. `streamingResamplerFlushesPartialTail` does the same for a 100001-sample prefix, whose length is not a multiple of 3.
- **Stride cutter (`HopCutter`).** `VACore` test `hopCutterHopsGlueToWholeClipResampler` runs the take through `WAVStreamer`, `Resampler48To16` and `HopCutter`. Every stride is 4000 samples, and the strides glued together are the whole-clip resampler output followed by zeros. `hopCutterPadsTheFinalHopWithZeros` checks the padding on a synthetic ramp.

### Running the checks

- `make test-core` runs every VACore test except `showSwiftScores`, in release mode: `swift test -c release --package-path VACore --skip showSwiftScores`. It takes under a second of test time. In debug the same tests took about 46 s, because the naive DFT in `LogMelFrontEnd` is slow without optimization.
- `make test-wakeword RUN=<run folder> TAKE=<take folder>` runs the Python unit tests (matcher, nfhash, train CLI), the Core ML match for that run and take, and the `logMel` test in release mode. It does not run `wakeScoresMatchPythonEval`.
- `make test-app` runs the VA app tests on the simulator.
- `swift test -c release --package-path VACore --filter showSwiftScores` prints the Swift chain's per-clip maxima beside the Python eval for the three held-out takes. It is a report, not a check, and takes about 1 s in release.

Run `test-core` on every build. Run `test-wakeword` as a smoke test before a build that changes the model, the export or the front end. The two reference tests need their reference data first: `lab/wakeword/reference/frontend/` for `logMel`, and `lab/wakeword/reference/resample/` for the resampler test.

## Held-out results for 0Q6-ou

Scored from the untrimmed eval records `eval-0Q75u4Y.json`, `eval-0Q75u4t.json` and `eval-0Q75tps.json`, written by `scripts/python/eval_take.py` for each take. The Swift `eval_take` writes matching records for the same takes (`eval-0Q76sSw`, `eval-0Q76sTR` and `eval-0Q76sTx`), and its per-clip maxima match the Python ones at four decimal places for all three takes. Three takes, one speaker.

- **At 0.5 (base-model comparison):**
  - `20261102-082403`: positives 2 of 3 trigger; negatives 1 of 3 trigger (max 0.687).
  - `20261103-163155`: positives 0 of 3; negatives 0 of 3 (max 0.259).
  - `20261104-075505`: positives 2 of 3; negatives 2 of 3 (max 0.654 and 0.573).
- **At 0.8 (tuned wakeword setting):**
  - `20261102-082403`: positives 2 of 3; negatives 0 of 3.
  - `20261103-163155`: positives 0 of 3; negatives 0 of 3.
  - `20261104-075505`: positives 2 of 3; negatives 0 of 3.

At 0.8 there are no false triggers on the held-out negatives. The misses are positives scoring between 0.005 and 0.44. The threshold is the only on-device tuning knob, and 0.8 is the current wakeword setting.

How takes are used. We first planned to train on user takes to refine the synthetic base model. We then found that the base model already responds usefully to user takes, so the takes may only need a threshold adjustment. The three takes above are therefore held out: they are scored as live recordings, untrimmed, and not used for training.

Only the three takes above are held out. A `train.py` change needs a new sweep and a new held-out check before any new export is chosen.

## Live test (planned)

The offline checks never run the model on live microphone audio. The planned v1 is a live matcher in the Training Wizard that shows the running score while each positive clip is recorded. It changes no chat state.

Prerequisites, in order:

1. **Resampling.** Done in `VACore`: `Resampler48To16` is a streaming 3:1 polyphase FIR with a Kaiser window (β = 5), matching scipy's `resample_poly` through `ArrayResampler48To16`. Still to confirm: the iPad's capture rate, which must be 48 kHz or the ratio changes.
2. **Bundle the model.** Put `wakenet.mlpackage` for the chosen run in a resource folder of the VA target or VACore, so the Training Wizard can load it from the app bundle. Record which run it is. This is for the app only. The evaluator reads the package from the run folder and does not need the bundle.
3. **Live matcher.** Wire `LogMelFrontEnd` and the Core ML model into the app, using the same threshold rule as `wakeword_matcher`.
4. **Sliding window.** Done in `VACore`: `HopCutter` emits 4000-sample strides and zero-pads the final stride, and `SlidingWindow` cuts windows on the training grid (see Decided below). Not yet written: scoring each window with Core ML, and tracking the highest score since the clip started.
5. **Wizard view.** Show the running maximum and mark when it crosses the threshold.
6. **Score record.** Save each clip's score timeline beside its `.wav`, with the model's run ID.
7. **Device check.** Compare live scores on the iPad with the offline match on the same audio.

Data flow: an `AsyncStream` of buffers from the mic or a replay file, `Resampler48To16` (16 kHz samples), `HopCutter` (4000-sample strides), then the matcher. `ArrayResampler48To16` is the whole-clip reference, not part of the live path. `WAVStreamer` is a test helper that feeds a WAV in chunks, standing in for the mic. `ClipCheck` moves into VACore first. The app target stays thin: microphone, file and SwiftData storage, and SwiftUI views.

Open decisions:

- The iPad's capture rate, which sets the resampling ratio.
- Live threshold, if the device path differs from the offline numbers.
- Window policy: maximum over all windows, or only windows ending inside the clip.

Decided: the stride cutter's final stride is shorter and unpadded. The window stage works on samples, so it never sees zeros the input did not contain, and it emits only complete windows, as training does. Live streams are not flushed at stop. The test harness flushes, so it scores the whole input.

Design goal: reduce latency.

Decided: live windows sit on the training grid. Window `k` is samples `[4000k, 4000k + 14287)`, the positions `train.py` scores. A stride-boundary grid was considered and rejected. Its windows would start 1713 samples later, so live scores would not match the offline scores or the 0.8 threshold results. The grid also sets latency: the first window completes at 14287 samples, about 0.89 s after the mic starts. A stride-boundary grid would complete it at 16000 samples, about 1.0 s. Both grids score every 0.25 s after that. `SlidingWindow` implements the training grid.

## Production Stride Period

The stride is the distance between window starts. Its period is the time from one window start to the next, and one stride period is used throughout the pipeline. The training grid uses a stride period of 0.25 s, which the Python parity tests need. Production needs a shorter stride period, between 50 and 100 ms, to minimize latency.

- **Microphone buffer period and stride period match.** A microphone buffer's duration equals the stride period at both 48 kHz and 16 kHz. In samples, a 48 kHz microphone buffer is three times the stride period in 16 kHz samples, and both cover the same time. Wake monitor events therefore arrive once per stride period, provided the microphone buffers are uniform in size. The microphone buffer size is requested, not guaranteed, so `HopCutter` absorbs any difference.
- **Alignment.** Every candidate stride period is an integral multiple of the 10 ms frame period, which is 160 samples at 16 kHz, so each stride holds whole frames.
- **Test.** `VACore/Tests/VACoreTests/ProductionHopTests.swift`, in release: `swift test -c release --package-path VACore --filter productionHop`. The file keeps its name; code identifiers are not renamed here.
- **Input.** `media/iapapo/Ava_premium_hello.m4a`, 2.67 s, scored with the bundled model. Each 48 kHz microphone buffer in the test is 3 × stride period in 16 kHz samples, so microphone buffer duration equals stride period.
- **Total time.** The whole chain from the first buffer to the last score: resampling, stride cutting, windowing and scoring. It excludes decoding the file and loading the model. It is compute time, not real-time latency.
- **Bins.** Five equal-width bins of probability. Column titles give the top of each bin, so `1.0…` is 0.8 to 1.0.
- **Cells.** `windows@runs`. A run is a block of consecutive window indices in the same bin.

| Stride period | Windows | Total time | 1.0… | 0.8… | 0.6… | 0.4… | 0.2… |
|---|---|---|---|---|---|---|---|
| 250 ms | 8 | 46.4 ms | 1@1 | 0@0 | 0@0 | 1@1 | 6@2 |
| 100 ms | 18 | 97.0 ms | 3@1 | 0@0 | 0@0 | 2@1 | 13@2 |
| 90 ms | 20 | 106.9 ms | 4@1 | 1@1 | 0@0 | 0@0 | 15@3 |
| 80 ms | 23 | 122.3 ms | 4@1 | 0@0 | 1@1 | 0@0 | 18@3 |
| 70 ms | 26 | 136.3 ms | 5@1 | 0@0 | 1@1 | 0@0 | 20@3 |
| 60 ms | 30 | 157.5 ms | 6@2 | 0@0 | 1@1 | 0@0 | 23@3 |
| 50 ms | 36 | 185.8 ms | 7@2 | 0@0 | 1@1 | 2@2 | 26@3 |

Findings:

- Inference takes about 5 ms per window in release on this Mac, at every stride period.
- At 50 ms, the whole 2.67 s clip takes 186 ms, about 14 times faster than real time. This was not measured in real time.
- No Python reference exists at these stride periods, so the table shows counts and timing, not parity. Each candidate is compared with the 250 ms baseline for parity once a reference exists.
- The stride period is not yet decided. The training-grid decision above stands until the device check is done.

## Open items

- Whether embedded mentions ("The quick IaPapo jumped…") count as positives or negatives.
- Privacy of training audio and the model. The takes are the user's voice. Open questions: iCloud Drive and device backup, Advanced Data Protection, and synced Mac folders. Parked.
- On-device update of the final layer. Core ML ML Program; a hybrid pipeline with an updatable head is unconfirmed (`MLUpdateTask`). Parked.
- A held-out take for each new export, and speakers beyond one. The base-model holdout is a proposal, not a decision: train on many speakers, then test on the user's own takes, which must stay separate from any personal fine-tuning data.

## Next steps

1. Record the happy, sad and neutral requests as negatives.
2. Record `say` clips through the speakers as self-echo negatives.
3. Record a new held-out take, and evaluate `0Q6-ou` on it.
4. Live test prerequisites 1 to 7 above.

## Wake Ring and Ambient Floor

The ring drives the display only and does not change any score. The ambient floor and gate live in `WakeMonitor` in VACore.

- **Ring.** Shows a smoothed score, not the raw score. A higher raw score is shown at once. A lower one pulls the shown value down. The current decay is 0.562 per 0.25 s stride period, so a lone detection falls to 0.1 within one second. Open: the decay should use real elapsed time, and the one-second fall conflicts with a proposed four-second half-life.
- **Ambient floor.** The mean power of each hop, in dBFS, smoothed with a 1.5 s half-life, so each update uses an alpha of 1 - 0.5^(0.25 / 1.5), about 0.109, per 0.25 s hop. The first hop sets the starting value. Decided: the floor updates only while the gate is closed, so a loud event does not raise its own threshold. Open: compute the smoothing from real elapsed time, not hop count.
- **Gate.** Bistable, with hysteresis. Decided: the gate opens when the level is 6 dB above the ambient floor, with no time constant, and closes when the level falls to 3 dB above the floor and has stayed there for the minimum open duration. Open: the minimum open duration, proposed at 1.0 s, to be tuned on held-out recordings. Placeholder: the gate defaults to open until the closing logic lands, although the intended default is closed. The gate's state is reported in each event.
- **Events (proposed).** One `WakeMonitor` event per stride, carrying the raw score, the most recent microphone level, the ambient level and the gate state. Open: whether `WakeMonitor` computes the microphone level from samples or receives it from the caller. The stride is a `WakeMonitor` parameter, default 4000 samples, which must be a positive multiple of 160 samples, the frame period. Open: the stride period itself. 80 ms is under consideration, which would need a new Python parity reference.
