---
type: nameforma.md
zuid: 0Q714-2F00TtWRuz61JxtW
collection: world
title: "0Q714-_Wakeword_Training"
description: How the IaPapo wake-word model is trained, exported, checked against Python and Swift, and the live test planned for the training wizard
agent_instructions: Maintain synchronous awareness without a persistent urge to solve or fix anything until a consensus call to action emerges.
---

## Overview

This is the operational article for the IaPapo wake word: how a model is trained from the Training Wizard's clips, how it is exported and checked, and what runs next. For the design history, see [[07WqEVFnlDiApKhTb0c0Wt]] (Wakeword Research).

The current model is `0Q6-ou`: seed 5 of the `JNaU8v4L6` sweep, exported to Core ML.

## Data

- **Takes.** Recorded by the Training Wizard on the iPad, one speaker, one device. Each take holds three positives and one to three negatives. Held-out takes are `20261102-082403`, `20261103-163155` and `20261104-075505`. Clips in the training set must not be used to judge the model.
- **Format.** Mono WAV from the wizard. The training loader resamples 48 kHz to 16 kHz with `resample_poly` and averages channels if a clip is not mono.
- **Trimming.** Positives and negatives are trimmed to speech onset and offset for training only; saved files do not change.
- **Window.** 0.893 s (14287 samples), set by the longest trimmed positive, so every wake word fits whole. Scoring slides the window every 0.25 s.

## Pipeline

1. Resample each clip to 16 kHz and average channels if needed.
2. Trim positives and negatives. Background noise is added as augmentation, so no silence-only file is needed.
3. Extract log-mel features: 25 ms frames, 10 ms hop, 40 mel bands.
4. Train `WakeNet` in PyTorch with `scripts/python/train.py`. Save the weights and each clip's window scores to `scores.csv` in `lab/wakeword/out/<version>/no-take-<run id>/`.
5. Export to Core ML with `scripts/export.sh <run folder>`. This writes `wakenet.mlpackage` and archives `run.json`, `scores.csv`, `run.log`, `train.json` and `export.json` under `models/wakeword/<version>/<run id>/`. An archive made from a commit is not overwritten.
6. Evaluate on held-out takes with `scripts/python/evaluate.py`, and read results with `scripts/eval-table.py <run id> --threshold <t>`.

## Verification

- **Core ML against PyTorch.** `scripts/python/test_coreml_match.py <run folder> <take folder>` scores every window through both models. On `0Q6-ou` and take `20261104-075505`, all 69 windows match, with max difference 2.3e-06 against tolerance 1e-3. Record: `match-<id>.json` in the run folder.
- **Swift front end against Python.** `VACore` test `logMelMatchesPython` compares `LogMelFrontEnd` with reference features from `scripts/python/export_frontend_reference.py`. It passes on the 69 windows of `20261104-075505`. The test covers features only, not resampling and not scores. Reference data lives in `lab/wakeword/reference/frontend/`.
- **Swift scores against Python eval.** `VACore` test `wakeScoresMatchPythonEval` runs the Swift front end and the Core ML model on the same windows and compares per-clip maximum probabilities with `eval-0Q70Tk.json`, within 1e-3. It passes for `0Q6-ou` on `20261104-075505`. It covers that one take only.

## Held-out results for 0Q6-ou

Scored from `eval-*.json` records. Three takes, one speaker.

- **At 0.5 (base-model comparison):**
  - `20261102-082403`: positives 2 of 3 trigger; negatives 1 of 3 trigger (max 0.687).
  - `20261103-163155`: positives 1 of 3; negatives 0 of 3.
  - `20261104-075505`: positives 2 of 3; negatives 2 of 3 (max 0.654 and 0.573).
- **At 0.8 (tuned wakeword setting):**
  - `20261102-082403`: positives 1 of 3; negatives 0 of 3.
  - `20261103-163155`: positives 0 of 3; negatives 0 of 3.
  - `20261104-075505`: positives 2 of 3; negatives 0 of 3.

At 0.8 there are no false triggers on the held-out negatives. The misses are positives scoring between 0.02 and 0.57. The threshold is the only on-device tuning knob, and 0.8 is the current wakeword setting.

Only the three takes above are held out. A `train.py` change needs a new sweep and a new held-out check before any new export is chosen.

## Live test (planned)

The offline checks never run the model on live microphone audio. The planned v1 is a live matcher in the Training Wizard that shows the running score while each positive clip is recorded. It changes no chat state.

Prerequisites, in order:

1. **Resampling.** Port `resample_poly` to Swift in `VACore`, a 3:1 polyphase FIR with a Kaiser window (β = 5). Verify taps against scipy. Confirm the iPad's capture rate first.
2. **Bundle the model.** Add `wakenet.mlpackage` for the chosen run to the VA target and record which run it is.
3. **Live matcher.** Wire `LogMelFrontEnd` and the Core ML model into the app, using the same threshold rule as `wakeword_matcher`.
4. **Sliding window.** Keep the last 14287 samples at 16 kHz, score every 0.25 s, and track the highest score since the clip started.
5. **Wizard view.** Show the running maximum and mark when it crosses the threshold.
6. **Score record.** Save each clip's score timeline beside its `.wav`, with the model's run ID.
7. **Device check.** Compare live scores on the iPad with the offline match on the same audio.

Data flow: an `AsyncStream` of buffers from the mic or a replay file, the resampler (producing `Mono16kHzStream`), a hop cutter (`Hop`, 4000 samples each), then the matcher. `ClipCheck` moves into VACore first. The app target stays thin: microphone, file and SwiftData storage, and SwiftUI views.

Open decisions:

- The iPad's capture rate, which sets the resampling ratio.
- Tail policy for the hop cutter: a shorter final hop or zero-padding with a flag.
- Live threshold, if the device path differs from the offline numbers.
- Window policy: maximum over all windows, or only windows ending inside the clip.

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
