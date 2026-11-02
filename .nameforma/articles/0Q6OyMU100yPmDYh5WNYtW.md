---
type: nameforma.md
zuid: 0Q6OyMU100yPmDYh5WNYtW
collection: world
title: Wake Word Training from the Latest Samples
description: Design for a first IaPapo wake-word model trained on the clips from the Training Wizard's latest take
agent_instructions: Maintain synchronous awareness without a persistent urge to solve or fix anything until a consensus call to action emerges.
---

## Overview

This is the first training experiment for the IaPapo wake word, following the minimal-experiment step in [[0Q6My1bn00B6S0Bm_cAcdW]] (Wake Word Recognition). It uses the clips from one run of the Training Wizard on the iPad, not a full training set. The goal is to learn whether the recorded voice is a usable signal before building a training pipeline.

## Data

Source: take `20261101-130400` in the app's `Documents/WakeWord/`, copied from the iPad to `lab/wakeword/20261101-130400/` (git-ignored via `lab`).

| File | Label | Length | How it ended |
|---|---|---|---|
| negative-001 | negative | 4.0 s | mic-check sentence, ended on match |
| negative-002 | negative | 3.0 s | prompt matched |
| negative-003 | negative | 10.6 s | timeout; about 0.6 s over the 10 s cap |
| negative-004 | negative | 7.0 s | prompt matched |
| positive-001 | positive | 2.1 s | 2 s timeout |
| positive-002 | positive | 2.1 s | 2 s timeout |
| positive-003 | positive | 2.1 s | 2 s timeout |

Format of every clip: WAVE, mono, 48 kHz, Float32.

Gaps against the plan in [[0Q6My1bn00B6S0Bm_cAcdW]]:

- **Negatives, general:** the three long PVA requests (happy, sad, neutral) are not recorded yet. The wizard's negatives are the mic-check sentence, "I love Iowa Popovers…", and a weather question.
- **Negatives, self-echo:** no `say` clips played through the speakers and picked up by the mic.
- **Embedded mentions:** not recorded. Whether they count as positives or negatives is still open.
- **Speakers:** one speaker, one device.

## Labels

- `positive-*`: wake word. The recognizer ignores case, so the three variants are all positives.
- `negative-*`: no wake word. The mic-check negative and the prompt-matched negatives are kept as they are.

## Pipeline

1. Resample every clip to one rate, and downmix to mono if needed. The clips are already mono.
2. Trim each positive to its speech onset and offset. Trimming is for training only; do not change the saved files.
3. Cut negatives into overlapping windows. Set the window length from the trimmed positive duration, so clip length cannot separate the classes.
4. Extract features and train a small classifier. The model type is open; the article lists a dedicated on-device net, a third-party toolkit, and a Core ML conversion.
5. Export the model and log its scores for each window.

## Evaluation

- **Held-out data:** these seven clips cannot evaluate themselves. Hold out a whole take, or record a new one, before trusting any score.
- **Per-source counts:** count triggers on positives and on negatives separately, as the article suggests, so a false trigger on the user's own speech is visible.
- **Success for this experiment:** the model triggers on held-out "IaPapo" clips and stays quiet on held-out negatives. A pass here does not yet cover other voices or rooms.

## Decisions

- Model type and framework.
- Window length and hop size.
- Whether to keep the mic-check negative, which contains the wake-word-free check sentence.
- Whether the timed negatives should be re-recorded at a fixed length, given the 10.6 s clip.

## Next steps

1. Record the happy, sad, and neutral requests as negatives.
2. Record `say` clips through the speakers as self-echo negatives.
3. Run the minimal experiment on this take, with a held-out take for evaluation.
