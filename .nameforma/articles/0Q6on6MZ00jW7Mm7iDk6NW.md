---
type: nameforma.md
zuid: 0Q6on6MZ00jW7Mm7iDk6NW
collection: world
title: Live Wake Word Test in the Training Wizard
description: Plan for a live matcher inside the iPad training wizard, showing the running score while positives are recorded
---

## Overview

The wake-word model has been checked offline only: on training clips, and on one take against PyTorch and against the Swift front end. None of those checks runs the model on live audio from the device's microphone. A live test closes that gap, and it is cheapest to build inside the training wizard, which already records positive clips.

The first version (v1) shows the running score while each positive clip is recorded. It changes no chat state and makes no decisions beyond showing whether the threshold was crossed.

## Why

* **Device path.** Live audio goes through the device's mic, its sample rate, and the app's resampling. The offline takes do not.
* **Matcher fidelity.** Seeing the score rise and fall during a real utterance shows whether the matcher behaves as the offline numbers say.
* **UX.** A live meter shows the user when the wake word was heard, which helps decide how the app should respond.
* **Samples.** Every recorded clip gets a score timeline, so later evaluation can use the clips and their live scores together.

## Current state

* `VACore` is linked into the app. It contains `LogMelFrontEnd` (a direct-DFT log-mel front end, matching training to within 1e-4 on the reference windows) and the offline `wakeword_matcher` rule.
* The training wizard (`VA/VA/TrainingWizard.swift`) records clips with `ClipRecorder` at the device's sample rate, and does not resample at capture.
* The speech model's `AVAudioConverter` feeds Apple's speech analyzer, a separate channel. It is not the wake-word path. The training loader uses `resample_poly`, so the live path must reproduce that.
* No model is bundled in the app. The VA target has no `.mlpackage`.

## Prerequisites

1. **Resampling.** Port scipy's `resample_poly` to Swift in VACore. For 48 kHz to 16 kHz this is a 3:1 polyphase FIR with a Kaiser window (β = 5). Verify the taps against scipy output rather than from memory. Confirm the iPad's capture rate first, since it sets the ratio. Check that the log-mel features match the reference on the same audio. Every later score depends on this.
2. **Bundle the model.** Add `wakenet.mlpackage` for one chosen run to the VA target, and record which run it is. The export candidate is `dkQlX-bLy/no-take-0Q6x7T`.
3. **Live matcher.** Wire `LogMelFrontEnd` and the Core ML model into the app, with the same threshold rule as `wakeword_matcher`.
4. **Sliding window.** Keep the last `window_len` samples at 16 kHz, read from the run's `run.json` (set during base training; 14287 samples, 0.893 s, in run `dkQlX-bLy/no-take-0Q6x7T`). Every 0.25 s, compute features, run the model, and track the highest score since the clip started.
5. **Wizard view.** While a positive clip is open, show the running maximum and mark the moment it crosses the threshold. This changes only the view.
6. **Score record per clip.** Save each clip's score timeline beside its `.wav`, with the model's `run_id` and `graph_id`, so each sample carries the score that matched it.
7. **Device check.** Run the wizard on the iPad and compare its live scores with the offline match on the same audio.

## Pipeline and boundary

Objective: test as much as possible off-device in VACore, and keep the app target to UI and device wiring.

Data flow, one path for live and replay:

1. **Source.** `AsyncStream<AVAudioPCMBuffer>`. Live, the mic's `onBuffer` yields into it. Replay, a file reader yields 1024-frame buffers from a take WAV.
2. **Resampler.** The `resample_poly` port, run over the whole stream, producing `Mono16kHzStream` (`AsyncStream<[Float]>`: each element is mono float samples at 16 kHz). Use the output array's actual length; do not assume the input length times the ratio.
3. **Hop stream.** `hopStream(from: Mono16kHzStream) -> AsyncStream<Hop>` keeps leftover samples and emits a `Hop` every 4000 samples (0.25 s at 16 kHz). It is pure logic on arrays, with no AVFoundation types.
4. **Matcher.** Consumes `AsyncStream<Hop>`, keeps a `window_len` window from `run.json`, and yields one score per window.

The names are chosen so the format is visible at each call site: `Mono16kHzStream` says what the samples are, and `Hop` is one fixed-length piece of that stream.

`Hop` is a struct with two fields: `index: Int` (0, 1, 2 from the clip's start) and `signal: [Float]` (4000 mono samples at 16 kHz). A stream name belongs to the stream, not to each hop.

Split:

- **VACore (tested with `swift test` on the Mac):** `ClipCheck` and its rules, the buffer source, the resampler, the hop cutter, and the matcher with its score stream.
- **App target (thin):** `Microphone` with the audio session and engine tap, the adapter from `onBuffer` to the stream, file and SwiftData storage, and the SwiftUI views.

`ClipCheck` is the first move: it is pure math on samples and has no device dependency. The current `ClipRecorder` rules (clipped, too quiet against the session floor plus 30 dB, under 15 dB SNR) stay as they are while moving.

The app target sets `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = YES`, so the same build runs on the Mac. Mac runs cover the logic; the iPad still decides the mic, route, and device-rate behavior.

Hop files on disk, if needed for listening or labelling: `positive-003-hop001.wav`. Unlabelled until scored or reviewed. A glued set of hops is not the clip unless the hops are contiguous, the tail is kept, and rate and format match.

## Decisions still open

* Capture rate on the iPad (prerequisite 1). Sets the resampling ratio and blocks everything else. Verify the Swift `resample_poly` port against scipy on the same take, through the Mac replay path first.
* Tail policy for the hop cutter: emit a shorter final hop, or zero-pad with a flag.
* Threshold for the live view. The offline default is 0.5. The live view may need a different value once the device path is measured.
* Window policy. Whether to report the maximum over all windows, or only windows that end inside the clip.
* Whether the live view should show the word-end time. That needs a reference alignment, which the offline takes don't have.

## Out of scope for v1

* Latency benchmarking. This comes after the live view exists.
* Chat-state integration. The wizard's state machine is unchanged, so the chat does not advance on a detection.
* Background or foreground-only operation beyond the wizard.

## Related

* [[0Q6OyMU100yPmDYh5WNYtW]]: wake-word training from the latest samples
* [[0Q6My1bn00B6S0Bm_cAcdW]]: wake-word recognition options
* [[0Q5p2ZIX007TIhdrSV7gtW]]: IaPapo voice assistant design
