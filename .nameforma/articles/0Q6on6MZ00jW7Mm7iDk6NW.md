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
* The speech model already converts audio with `AVAudioConverter`. That is not the same method as the training loader, which uses `resample_poly`.
* No model is bundled in the app. The VA target has no `.mlpackage`.

## Prerequisites

1. **Resampling decision.** Pick the method the live path uses to reach 16 kHz, and check that its features match the reference features on the same audio. Training uses `resample_poly`. The speech model's `AVAudioConverter` path is the other candidate. Every later score depends on this.
2. **Bundle the model.** Add `wakenet.mlpackage` for one chosen run to the VA target, and record which run it is.
3. **Live matcher.** Wire `LogMelFrontEnd` and the Core ML model into the app, with the same threshold rule as `wakeword_matcher`.
4. **Sliding window.** Keep the last 0.893 s at 16 kHz. Every 0.25 s, compute features, run the model, and track the highest score since the clip started.
5. **Wizard view.** While a positive clip is open, show the running maximum and mark the moment it crosses the threshold. This changes only the view.
6. **Score record per clip.** Save each clip's score timeline beside its `.wav`, with the model's `run_id` and `graph_id`, so each sample carries the score that matched it.
7. **Device check.** Run the wizard on the iPad and compare its live scores with the offline match on the same audio.

## Decisions still open

* Resampling method (prerequisite 1). Blocks everything else.
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
