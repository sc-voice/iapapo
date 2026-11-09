---
type: nameforma.md
zuid: 0Q714zzN00K2ZTSEXafvdW
collection: world
title: "0Q714z_Wakeword_Research"
description: How the IaPapo wake-word design was reached: options, the CNN analysis, and the base-model seed sweep
agent_instructions: Maintain synchronous awareness without a persistent urge to solve or fix anything until a consensus call to action emerges.
---

## Overview

Wake-word recognition drives the chat transition from IDLE to LISTENING, so it runs on device and must not depend on continuous transcription. This article records how the design was reached. For how to run the pipeline, see [[0Q714-2F00TtWRuz61JxtW]] (Wakeword Training).

The wake word is "IaPapo" (ee-yah-PAH-poh).

## Options considered

- **Text scan of the transcript.** Rejected. It depends on exact spelling (unusual names are misrecognized), needs continuous full transcription with battery and privacy cost, produces flickering matches, and cannot separate speech aimed at the agent from nearby speech or the agent's own TTS.
- **Acoustic keyword spotter.** Chosen. A small model classifies the audio directly and hands off to transcription only after the trigger fires. Apple-native route: Create ML sound classifier through SoundAnalysis. Third-party routes: Picovoice Porcupine (commercial) or openWakeWord (needs Core ML conversion). Preferred first test: Create ML. The project instead trains its own WakeNet in PyTorch and exports to Core ML.

## Model architecture

`WakeNet` is a three-block CNN over 40-band log-mel features (16 kHz, 25 ms frames, 10 ms hop). Its strengths are low cost for always-on use and standard speech features. Its weakness is `AdaptiveAvgPool2d(1)`: it averages over time as well as frequency, so the model detects presence well but cannot tell a 6-phoneme phrase from a 4-phoneme one. The three improvements considered, in order of effort:

- **Reduced temporal pooling.** Pool to `(1, 4)` or `(1, 8)` bins. Low effort.
- **CNN-GRU hybrid.** Use the CNN as a front end and pass its sequence to a GRU or LSTM. Medium effort.
- **Dilated temporal convolutions (TCN).** High effort, long-range patterns without a sequential bottleneck.

Conclusion: the current model is a presence detector and suits a first-stage trigger. Sequence sensitivity is not needed for the wake word itself, so none of the three changes is scheduled.

## Training data

- **Positives.** "IaPapo" in three intonations, from the Training Wizard: "IaPapo", "IAPAPO!", "IaPapo?". Case is ignored by the recognizer, so all three count.
- **Negatives, general.** Everyday speech without the wake word. Three long requests (happy, sad, neutral) are planned; the wizard's three prompts are recorded now.
- **Negatives, self-echo.** The agent's own TTS picked up by the mic while speaking. Planned as `say` clips through the device speakers.
- **Embedded mentions** ("The quick IaPapo jumped over the lazy dog") are open: positive if the trigger is the token alone, negative if it needs a following pause.
- **Base model data.** The current base model is trained on synthetic voices. The single user-tuned knob on device is the wake threshold.

## Seed sweep on the current code

The base model's score depends on the random seed more than on code or noise changes, so the export seed is chosen by sweep after each `train.py` change. The current sweep is version `JNaU8v4L6`, seeds 1 to 20 plus repeats, all with noise.

Scored on the 41 training positives and 322 training negatives at 0.5 (`lab/wakeword/out/JNaU8v4L6`, from each run's `scores.csv`):

```
seed  run                       pos>=.5    neg>=.5   holdout neg>=.5
5     0Q6-ou                    41/41      0/322     0/69
15    0Q6-Uz,-YT,-a4,_01        41/41      1/322     1/69 each
4     0Q6-na                    41/41      2/322     2/69
9     0Q6-u8                    41/41      2/322     0/69
10    0Q6-vS                    41/41     25/322    11/69
16    0Q6_1M                    40/41      0/322     0/69
18    0Q6_3-                    40/41      1/322     1/69
2     0Q6-kz                    39/41      2/322     2/69
1     0Q6-jh                    37/41      8/322     4/69
3     0Q6-mG                    34/41      2/322     2/69
19    0Q6_5I                    34/41     15/322    11/69
17    0Q6_2g                    34/41     34/322    13/69
6     0Q6-qC                    31/41     11/322     7/69
8     0Q6-sq                    31/41     27/322    13/69
14    0Q6--j                    28/41      0/322     0/69
12    0Q6-y4                    26/41     12/322     5/69
20    0Q6_6c                    26/41     20/322    11/69
13    0Q6-zP                    25/41      0/322     0/69
7     0Q6-rW                    25/41     12/322     7/69
11    0Q6-wm                    20/41      8/322     6/69
15    0Q6-he (broken)            1/41     84/322    32/69
```

Notes:

- Ranked by positives triggered, then fewer negatives. Seed 5 has no negatives at 0.5 on the training clips, and seed 15 holds up across its four healthy runs.
- These are in-sample scores. They measure fit to the training clips, not generalization.
- Run `0Q6-he` (seed 15) is broken: 1 of 41 positives and 84 negatives trigger at 0.5. It is excluded from the seed 15 summary.
- The export candidate is seed 5, run `0Q6-ou`. It is the only sweep run with held-out takes; see [[0Q714-2F00TtWRuz61JxtW]].

The earlier sweeps used `train.py` versions `dkQlX-bLy`, `uyH5DWIyZ` and `0Q6jON`. Their seed tables are superseded and are not carried here; the code history is in git. Lessons kept from them: seeds matter more than noise, café noise did not add false triggers on the earlier code, and fan noise swung widely by seed.

## Decisions

- Acoustic keyword spotting, with a self-trained WakeNet, exported to Core ML.
- Everything runs on device; recordings and models stay local.
- Base model trained on synthetic voices. On-device customization is the threshold only.
- Export seed is chosen by sweep on each `train.py` version. Current export: seed 5 (`0Q6-ou`).
- Threshold: 0.5 for the base-model comparison across runs; 0.8 for the tuned wakeword setting (see [[0Q714-2F00TtWRuz61JxtW]]).

## Open issues

- Does the trigger mean the token alone, or the token followed by a pause?
- Pause-based gating in noise: learn the token alone, or keep a pause as a learned boundary?
- Whether to require the wake word twice for noise robustness.
- Create ML versus a third-party engine.
- Whether the agent should respond only to the enrolled user.
- A `--init` path for fine-tuning on user speech. `train.py` has no such flag yet.
- Whether seed 5 stays the best across further `train.py` changes. Each change needs a fresh seed sweep.

## Glossary

- **Keyword spotter:** a classifier that detects a fixed word or phrase in audio without full transcription.
- **SoundAnalysis:** Apple's framework for classifying audio streams with Core ML models.
- **Self-echo:** the agent's own TTS output captured by the mic as user speech.
- **Presence detector:** a model that answers whether a pattern occurred, not when or in what order.
