---
type: nameforma.md
zuid: 07Wqf04JG93DcfScN77pEK
collection: world
slug: "07Wqf0-Wakeword-Training"
description: How the IaPapo wake-word model is trained, exported, checked against Python and Swift, and the live test planned for the training wizard
agent_instructions: "Follow high-stakes readback/hearback communication protocol with human confirmation before taking any action that changes stored data"
---

# Wakeword Training

The Voice Assistant (VA) wakeword is "iapapo", 
a Portuguese portmanteau of "IA" (inteligência artificial) and "batepapo" (internet chat).

This article describes how the wakeword model is built and deployed.

1. Training is based on a set of six phrases (3 positive, 3 negative)
1. Train Python models using synthetic Apple voice clips
1. Evaluate Python models using human voice clips
1. Export Python models as CoreML for Swift
1. Evaluate Swift CoreML model using Python model as reference
1. Archive and Deploy Swift CoreML

The current model is 0Q7YdK, which was trained by N9qAHM3FB on November 15, 2026.

## Training Data

### Spoken Phrases
Six phrases were used in training.
Positive phrases are short with differing inflections:

- IaPapo
- IaPapo!
- IaPapo?

Negative phrases are longer with hard negatives:

- We are testing the microphone
- I love Iowa Popovers. Do you have a recipe?
- I am really worried about the weather tomorrow. What's the forecast?

These phrases were spoken on macOS 26 by synthetic voices: Allison, Aman, Ava, Daniel, Evan, Jamie, Lee, Matilda, Moira, Nathan, Rishi, Serena, Stephanie, Tessa, Tom, Veena, Voice_1_en_US, and Zoe.

Initially, the plan was create a base model using synthetic voices and then provide recorded human voices to tune the base model. In practice, however, the base model itself was able to discern human wakewords adequately.
The Training Wizard does have panels to record human sound clips, but those will only be available as an advanced preference. 
The Training Wizard now focuses on teaching the user how to say the wakeword effectively with live feedback.

## Train Python Model

Since training is reproduceable by specifying a training seed,
we can train multiple models for evaluation.
In practice seeds 1-20 have proven sufficient to generate workable models.

> Command: `scripts/train.sh --seed N`
> Example:
```
    scripts/train.sh --seed 16
```

- **Default Settings:** 6000 steps, learning rate 0.001, batch 32, threshold 0.5, noise SNR 3 to 30 dB. The window is set by the longest trimmed positive.
- **No holdout by default.** The run prints a warning, and its scores are on training data. Use the held-out takes after training.
- **Output files:** each run folder holds `wakenet.pt` (the weights), `scores.csv`, `run.json`, `run.log` and `train.json`. `wakenet.pt` is required for export and held-out evaluation.
- **Machine record:** `run.json` records macOS, CPU, RAM and torch threads. Older runs don't have these fields.
- **Runtime:** about 13 minutes per seed on this machine.
- **Training version** is the SHA-256 hash of train.py, encoded in nf's base64 alphabet, with the first 9 characters used as the version (e.g., N9qAHM3FB).
- **One at a time.** Never run seeds in parallel.
- **Training Run** is identified by the first 6 characters of a ZUID (e.g., 0Q7YdK). The ZUID format is defined in [zuid.ts](https://github.com/sc-voice/nx-scv/blob/nx-nameforma/pkg/nameforma/src/zuid.ts): a UUIDv7 written as 22 base-63 characters.
- **Status:** seeds 1 to 20 are trained on macOS 27. Seed 16 is the strongest on training positives. Seeds 5 and 15 were the earlier best. Seed 0 is unused.

The trained output for each seed will be in a run folder at: `lab/wakeword/out/<version>/no-take-<run id>/`
Example:

```
  lab/wakeword/out/N9qAHM3FB/no-take-0Q7YdK/
```

Since runs are timestamped, their ids will be different and weights need to be compared. With the same seed, Python weights will be an exact match. However the CoreML weights will differ slightly due to the export process.

## Evaluate Python Model

Each candidate run is scored on the three held-out takes with the Python pipeline. The choice of run for export rests on these scores, not on the training-data scores in the seed sweep.

> Commands used for seed 16 (`0Q7YdK`):
>
> ```
> ./scripts/eval-take.sh 0Q7YdK lab/wakeword/takes/turtlePro/20261102-082403 --pipeline python
> ./scripts/eval-take.sh 0Q7YdK lab/wakeword/takes/turtlePro/20261103-163155 --pipeline python
> ./scripts/eval-take.sh 0Q7YdK lab/wakeword/takes/turtlePro/20261104-075505 --pipeline python
> ./scripts/eval-table.py lab/wakeword/out/N9qAHM3FB/no-take-0Q7YdK 0Q7aE_z 0Q7aF0J 0Q7aF0e --threshold 0.5
> ```

Note: for convenience, the eval-table script also accepts the run id alone, and shows the newest record for each take and pipeline. For example:

> Example:
```
    ./scripts/eval-table.py 0Q7YdK
```

- **Command:** `scripts/eval-take.sh <run id> <full take path> --pipeline python`. The take path must be the full path, such as `lab/wakeword/takes/turtlePro/20261102-082403`. A bare take name is not found.
- **Table:** `scripts/eval-table.py <run folder> <eval ids> --threshold <t>` shows the per-clip scores and triggers.
- **Thresholds:** report at 0.5 and at 0.8, the current wakeword setting.
- **Eval IDs:** eval records take the first 10 characters of `nf id`. The 7-character prefix collided on macOS: IDs that differ only in letter case name the same file, and a later record overwrote an earlier one. Training run IDs are still 6 characters.
- **Takes:** described under "Held-out results for 0Q6-ou" and in Spoken Phrases.

### Seed 16 (run `0Q7YdK`)

Eval records `0Q7aE_z`, `0Q7aF0J` and `0Q7aF0e`, written by `eval-take.sh` with the Python pipeline. They used 7-character IDs and remain in the run folder. The 2026-11-16 re-verification (`make wake-export`) wrote newer records with 10-character IDs, and those are the ones `verify_export.py` checks. Triggers are the same at 0.5 and 0.8 for every clip.

| Take | Clip | Score | Triggers at 0.5 and 0.8 |
|---|---|---|---|
| 20261102-082403 | negative-001 | 0.0151 | no |
| 20261102-082403 | negative-002 | 0.0826 | no |
| 20261102-082403 | negative-003 | 0.0334 | no |
| 20261102-082403 | positive-001 | 0.9984 | yes |
| 20261102-082403 | positive-002 | 0.0166 | no |
| 20261102-082403 | positive-003 | 0.9805 | yes |
| 20261103-163155 | negative-001 | 0.3042 | no |
| 20261103-163155 | negative-002 | 0.9255 | yes |
| 20261103-163155 | negative-003 | 0.0082 | no |
| 20261103-163155 | positive-001 | 0.2287 | no |
| 20261103-163155 | positive-002 | 0.9991 | yes |
| 20261103-163155 | positive-003 | 0.9995 | yes |
| 20261104-075505 | negative-001 | 0.0003 | no |
| 20261104-075505 | negative-002 | 0.0041 | no |
| 20261104-075505 | negative-003 | 0.1077 | no |
| 20261104-075505 | positive-001 | 0.9999 | yes |
| 20261104-075505 | positive-002 | 0.9999 | yes |
| 20261104-075505 | positive-003 | 0.9929 | yes |

Summary: positives 7 of 9 trigger at both thresholds. Negatives 1 of 9 trigger at both thresholds, from `20261103-163155/negative-002`. The archived `0Q6-ou` on the same takes is in "Held-out results for 0Q6-ou": at 0.8, 4 of 9 positives trigger and no negatives do.

The criteria for choosing seed 16 were (descending order):

- Highest mean positive score
- Minimal negative fails
- Perfect score on 20261104-075505

## Export Python Model

Export turns a chosen run's `wakenet.pt` into a Core ML package. Do this only for a run that has passed the held-out check in "Evaluate Python Model".

### Export and Validate

> Command: `make wake-export RUN=<run id>`
> Example:
> ```
>   make wake-export RUN=0Q7YdK
> ```

- **Output in the run folder:** `wakenet.mlpackage` and `export.json`.
- **Archive:** `make wake-export RUN=<run id> ARCHIVE=1` archives only after verification passes. Without `ARCHIVE=1` the run is verified and nothing is written to `models/`. It copies `wakenet.mlpackage`, `run.json`, `scores.csv`, `run.log`, `train.json`, `export.json` and the eval records to `models/wakeword/<version>/<run id>/`. It does not copy `wakenet.pt`. Copy the weights by hand only for a production candidate.
- **Window length:** `export_coreml.py` reads `window_len` from the run's `run.json` and writes it into the Core ML user metadata. `WakeScorer` requires that metadata. A run without `window_len` in `run.json` predates the current `train.py` and must be retrained.
- **Commit record:** the archive's `export.json` records `git_commit` as the current HEAD, or `UNCOMMITTED` if `scripts/` has changes not in HEAD.
- **No overwrite:** export refuses to overwrite an archive that records a commit. Delete that folder first to re-export.
- **Environment:** `make wake-export` runs with the project's `.venv`.
- **Verification:** `make wake-export RUN=<run id>` exports, then checks: `window_len` is in `run.json`; Core ML matches PyTorch on a held-out take within 1e-3; Swift `eval_take` matches the Python eval on each held-out take within 1e-3; trigger counts at 0.5 and 0.8 match the Python records. It fails on the first failed check. Export writes only into the run folder, not `models/`. Passed for `0Q7YdK` on 2026-11-16: Core ML matches PyTorch on all three held-out takes, and Swift and Python evals agree on every clip.

### Archive Model

If model passes, it should be archived. 
Archival writes into `models/`, which is stored data, so confirm with the user before running it. Only a model that passed verification is archived.

> Command:
>
> ```
> make wake-export RUN=<run id> ARCHIVE=1
> ```
>
> Example:
>
> ```
>     make wake-export RUN=0Q7YdK ARCHIVE=1
> ```

## Evaluate Swift CoreML Model

## Archive and Deploy Swift Model

- **Order:** export, verify, archive, deploy. Each step needs the previous one to pass.
- **Deploy (planned):** `make build-model` compiles the archived `wakenet.mlpackage` into `VACore/Sources/VACore/Resources/wakenet.mlmodelc`. It should read from `models/`, not `lab/`. The bundled model is what the app and the Swift tests load.
- **When:** run it only when the shipped model changes. It rewrites a tracked resource, so it is not part of a routine build. Confirm with the user first.
- **Tests:** after archiving, dev tests read the archived model, not `lab/`. Training folders are not needed to run tests.

## Unorganized Information Follows

### Other Data

- **Takes.** Recorded by the Training Wizard on the iPad, one speaker, one device. Each take holds three positives and one to three negatives. Held-out takes are `20261102-082403`, `20261103-163155` and `20261104-075505`. Clips in the training set must not be used to judge the model.
- **Format.** Mono WAV from the wizard. The training loader resamples 48 kHz to 16 kHz with `resample_poly` and averages channels if a clip is not mono.
- **Trimming.** Training trims positives and negatives to speech onset and offset, with 0.1 s of padding. Saved files do not change. Held-out takes and the live path are not trimmed, since a take is a live recording and the live path cannot know where speech starts.
- **Window.** 0.893 s (14287 samples), set by `positive-Rishi_enhanced__`, the longest trimmed positive in the 41-clip training set, so every wake word fits whole. Positives contain only the wake word; a clip with extra speech stretches the window. Scoring slides the window every 0.25 s.


## Pipeline

1. Extract log-mel features: 25 ms frames, 10 ms frame period, 40 mel bands. Background noise is added as augmentation during training, so no silence-only file is needed.

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

The training clips use synthetic voices that pronounce "iapapo" as "eye-ah-papo", so lower scores are expected on the first two takes:

- `20261102-082403`: "ee-ah-papo". Not trained on, but a valid pronunciation.
- `20261103-163155`: "eye-ah-papo" with kitchen noise. Trained pronunciation, with background noise.
- `20261104-075505`: "eye-ah-papo". Optimal user input.

Only the three takes above are held out. A `train.py` change needs a new sweep and a new held-out check before any new export is chosen.

## Seed sweep (macOS 27)

Seeds 1 to 20 trained on macOS 27.2.1 with the current `train.py`, default settings except the seed, and no holdout. Scores are on training data, so they do not replace the held-out check above. Sorted by mean positive score, descending.

| Seed | Run | Positives mean | Pos ≥0.5 | Pos ≥0.9 | Negatives ≥0.5 |
|---|---|---|---|---|---|
| 16 | 0Q7YdK | 0.996 | 41/41 | 41 | 1/322 |
| 4 | 0Q7YLM | 0.956 | 40/41 | 36 | 0/322 |
| 15 | 0Q7Xzy | 0.935 | 39/41 | 35 | 2/322 |
| 9 | 0Q7YVE | 0.933 | 40/41 | 34 | 1/322 |
| 3 | 0Q7YFu | 0.903 | 39/41 | 31 | 0/322 |
| 5 | 0Q7XrQ | 0.887 | 38/41 | 30 | 0/322 |
| 2 | 0Q7YEZ | 0.872 | 37/41 | 29 | 3/322 |
| 17 | 0Q7Yeh | 0.820 | 36/41 | 23 | 62/322 |
| 10 | 0Q7YWa | 0.781 | 32/41 | 25 | 2/322 |
| 1 | 0Q7YAZ | 0.774 | 33/41 | 26 | 0/322 |
| 13 | 0Q7Yad | 0.770 | 34/41 | 17 | 0/322 |
| 20 | 0Q7Yik | 0.727 | 28/41 | 17 | 34/322 |
| 19 | 0Q7YhN | 0.684 | 30/41 | 18 | 30/322 |
| 18 | 0Q7Yg1 | 0.637 | 26/41 | 20 | 1/322 |
| 8 | 0Q7YTv | 0.631 | 27/41 | 11 | 20/322 |
| 6 | 0Q7YRG | 0.556 | 22/41 | 11 | 9/322 |
| 14 | 0Q7Ybz | 0.514 | 21/41 | 14 | 0/322 |
| 12 | 0Q7YZH | 0.490 | 19/41 | 13 | 18/322 |
| 11 | 0Q7YXw | 0.457 | 17/41 | 6 | 14/322 |
| 7 | 0Q7YSa | 0.446 | 16/41 | 10 | 9/322 |

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
- **Total time.** The whole chain from the first buffer to the last score: resampling, stride cutting, windowing and scoring. It excludes decoding the file and loading the model. It is compute time, not real-time latency.
- **Bins.** Five equal-width bins of probability. Column titles give the top of each bin, so `1.0…` is 0.8 to 1.0.
- **Cells.** `windows@runs`. A run is a block of consecutive window indices in the same bin.

<!-- Purpose: show how the stride period affects the number of matches and runs. The evaluation clip may have been the holdout hello clip (media/iapapo/holdout/Ava_premium_hello.m4a); not verified. -->

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

## References

Facts for picking this work back up. Each item points to a file or a run; check it before relying on it.

**Models and runs**

- Bundled Core ML model: `VACore/Sources/VACore/Resources/wakenet.mlmodelc`, built from `0Q6-ou` on macOS 26. Its `weights/weight.bin` has SHA-256 `9892ea45…ae5d`. A copy is in `local/macos26/wakenet.mlmodelc`. Its metadata has no `window_len`, so `WakeScorer` throws `missingWindowLength`.
- `0Q6-ou` weights (`wakenet.pt`) are gone. Only its records remain in `models/wakeword/JNaU8v4L6/0Q6-ou/`, so it cannot be re-exported.
- Run versions in `lab/wakeword/out/`:
  - `N9qAHM3FB`: current `train.py`, which records the machine fields. Seeds 1 to 20 are here.
  - `JNaU8v4L6`: `train.py` before the machine fields were added. Seeds 5 and 15 are here.
- Older versions (macOS 26) are in `lab/macos26/wakeword/out/`, including `deprecated/`.
- Seed 5 (`0Q7XrQ` in `N9qAHM3FB`, and `0Q7XpC` in `JNaU8v4L6`) is byte-identical to the rerun, so the config reproduces on macOS 27.
- Seed 0 is unused.

**Data**

- Hello sentence: `media/iapapo/holdout/Ava_premium_hello.m4a`, 2.67 s. It holds a long sentence containing the wake word, so it is a holdout clip and never a training positive. Moving it out of `media/iapapo/` keeps it out of training. A WAV copy from my session is in `lab/wakeword/takes/hello/`, unused.

**Tests**

- Six VACore test files load the hello clip from `media/iapapo/holdout/`. Their paths were updated during this session.
- After that change, the audio-path failures are gone. The `missingWindowLength` failures remain in the `WakeMonitor` and `ProductionHop` tests. Re-exporting a model with `window_len`, or a fallback to the known 14287-sample window, would fix them.
- `make test-core` still exits with an error.
- `lab/wakeword/reference/resample/` does not exist, so the resampler test cannot run.

**Rules and decisions**

- Confirm with the user before any action that changes stored data.
- The macOS 26 to 27 upgrade happened on 2026-11-15. It is the suspected cause of the gap between the archived model and the new runs. That is unconfirmed, and no macOS 26 environment is left to test it.

**Open**

- Export of a candidate, which needs a chosen run and a held-out check.
- Whether to bundle a new model or keep `0Q6-ou` with a fallback for `window_len`.
- Leftover run folders from failed or killed runs: `hello-0Q7XlX`, `hello-0Q7XlY`, `no-take-0Q7XlN` and `no-take-0Q7XlJ` in `JNaU8v4L6`, which were not reviewed.
