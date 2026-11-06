---
type: nameforma.md
zuid: 0Q6jyMMM00D3Ywo0oukl7W
collection: world
title: Seed Variance in Base Wake Word Training
description: Seed 0-5 results for the base WakeNet, no-noise and background-noise settings, with run references
agent_instructions: Maintain synchronous awareness without a persistent urge to solve or fix anything until a consensus call to action emerges.
---

## Overview

The base model's score depends more on the random seed than on the background noise setting. Five no-noise seeds (0 to 5) span 13 to 40 positives out of 41, so single-seed noise comparisons can't rank noise settings.

All runs use `scripts/train.py` with 6000 steps and window 0.893 s. Results are in `lab/wakeword/out/`, with `scores.csv` per run. A run's `run.json` records its seed and `noise_snr` when that argument was passed.

## Replicate check

Same seed, same settings, same data reproduce exactly (max score difference 0.000000):

- Seed 0, 20-30 dB crumpling: `0Q6itZ/no-take-0Q6j8O` and `0Q6itZ/no-take-0Q6jG9`
- Seed 1, 3-30 dB crumpling: `0Q6jON/no-take-0Q6jOn` and `0Q6jON/no-take-0Q6jQs`

## No noise, seeds 0 to 5

Positives are out of 41. False triggers count every negative clip at p >= 0.5, including holdouts `_1` to `_3`, hard negatives `_4` to `_7q` and sentence negatives `_s1` to `_s3`.

| seed | run | positives | mean positive | false triggers |
|---|---|---:|---:|---:|
| 0 | `0Q6i9B/no-take-0Q6iKd` | 35 | 0.84 | 6 |
| 1 | `0Q6jON/no-take-0Q6jcF` | 36 | 0.86 | 0 |
| 2 | `0Q6jON/no-take-0Q6jeA` | 13 | 0.31 | 13 |
| 3 | `0Q6jON/no-take-0Q6jgu` | 29 | 0.67 | 6 |
| 4 | `0Q6jON/no-take-0Q6jjm` | 34 | 0.76 | 2 |
| 5 | `0Q6jON/no-take-0Q6jqo` | 40 | 0.97 | 11 |

## Background noise (one clip at a time)

Noise clips come from `lab/wakeword/noise/` (crumpling `lematt725251_01`, café `651259-cafe-05`). Archival copy of the café clip, in case the lab is lost: `media/noise/651259-cafe-05.m4a` (AAC 64 kb/s, 16 kHz mono, 5.0 s, encoded from the training clip).

Café attribution: "ext_cafe_kahvilakumpu_walla_park" by ampi_sound, https://freesound.org/s/651259/, CC BY-NC 4.0 (https://creativecommons.org/licenses/by-nc/4.0/). The training clip is the 15–20 s chunk of the source, converted to mono 16 kHz (verified by cross-correlation at offset 15.000 s, normalized correlation 1.0000). Attribution is also recorded in `media/attribution.json`.

| setting | seed | run | positives | mean positive | false triggers |
|---|---|---|---:|---:|---:|
| crumpling 3-30 dB | 0 | `0Q6iRY/no-take-0Q6ilW` | 30 | 0.70 | 1 hard neg, 1 holdout |
| crumpling 3-30 dB | 1 | `0Q6jON/no-take-0Q6jOn` | 37 | 0.87 | 4 holdout `_1`, 1 hard neg, 4 sentence |
| crumpling 20-30 dB | 0 | `0Q6itZ/no-take-0Q6jG9` | 20 | 0.50 | 0 |
| café 3-30 dB | 1 | `0Q6jON/no-take-0Q6jaC` | 35 | 0.84 | 0 |
| café 3-30 dB | 5 | `0Q6jON/no-take-0Q6jsx` | 26 | 0.62 | 0 |

The no-noise seed-5 run (`0Q6jqo`) had 40 positives and 11 false triggers. With café on the same seed, false triggers drop to 0 but positives drop to 26.

## Café paired by seed

Café at 3-30 dB compared with no noise on the same seed (positives out of 41; false triggers across all negatives):

| seed | no-noise run | positives | false | café run | positives | false |
|---|---|---:|---:|---|---:|---:|
| 0 | `0Q6i9B/no-take-0Q6iKd` | 35 | 6 | `0Q6jON/no-take-0Q6j-2` | 40 | 1 |
| 1 | `0Q6jON/no-take-0Q6jcF` | 36 | 0 | `0Q6jON/no-take-0Q6jaC` | 35 | 0 |
| 2 | `0Q6jON/no-take-0Q6jeA` | 13 | 13 | `0Q6jON/no-take-0Q6j_h` | 39 | 2 |
| 3 | `0Q6jON/no-take-0Q6jgu` | 29 | 6 | `0Q6jON/no-take-0Q6k1K` | 35 | 3 |
| 4 | `0Q6jON/no-take-0Q6jjm` | 34 | 2 | `0Q6jON/no-take-0Q6keL` | 37 | 2 |
| 5 | `0Q6jON/no-take-0Q6jqo` | 40 | 11 | `0Q6jON/no-take-0Q6jsx` | 26 | 0 |
| mean | | 31.2 | 6.3 | | 35.3 | 1.3 |

Café's mean positive score is 0.85, against 0.74 with no noise. Café has no more false triggers than no noise on any seed, and fewer on four of six. Positives are higher on seeds 0, 2, 3 and 4 and lower on seed 5, which drives most of the spread.

## Fan, paired by seed

Fan (`867601-fan-05.wav`, a steady air-conditioner recording, 3-30 dB) compared with no noise on the same seed:

| seed | no-noise run | positives | false | fan run | positives | false |
|---|---|---:|---:|---|---:|---:|
| 0 | `0Q6i9B/no-take-0Q6iKd` | 35 | 6 | `0Q6jON/no-take-0Q6kEt` | 36 | 1 |
| 1 | `0Q6jON/no-take-0Q6jcF` | 36 | 0 | `0Q6jON/no-take-0Q6kGX` | 18 | 21 |
| 2 | `0Q6jON/no-take-0Q6jeA` | 13 | 13 | `0Q6jON/no-take-0Q6kIy` | 22 | 16 |
| 3 | `0Q6jON/no-take-0Q6jgu` | 29 | 6 | `0Q6jON/no-take-0Q6kP1` | 40 | 4 |
| 4 | `0Q6jON/no-take-0Q6jjm` | 34 | 2 | `0Q6jON/no-take-0Q6kR9` | 41 | 1 |
| 5 | `0Q6jON/no-take-0Q6jqo` | 40 | 11 | `0Q6jON/no-take-0Q6kSo` | 28 | 0 |
| mean | | 31.2 | 6.3 | | 30.8 | 7.2 |

Fan's mean positives and false triggers match no noise. Its effect depends on the seed: best on seeds 3 and 4, worst on seed 1 (18 positives, 21 false triggers).

## Take check

`0Q6jON/no-take-0Q6jsx` (café, seed 5) scored on take `lab/wakeword/takes/turtlePro/20261104-075505`, which was not in training: positives 2 of 3 triggered (max 0.92, 0.99; the third at 0.02), negatives 0 of 3 triggered.

## Conclusions

- Seed dominates. The no-noise seeds alone range from 13 to 40 positives, which is wider than any noise effect so far.
- Café never adds false triggers relative to no noise (six seeds), and reduces them on four seeds (0, 2, 3 and 5), with seeds 1 and 4 unchanged. The cost in positives is on seed 5 only.
- Crumpling produces false triggers on seed 1 that café does not.
- Fan does not reduce false triggers on average (7.2 with fan, 6.3 with no noise) and swings widely by seed, so it doesn't replace café on this evidence.
- Seed 1 is the only no-noise seed with zero false triggers. One seed per setting is not enough to rank settings.
- The take miss (positive-003, a question-form wake word) is consistent with a TTS-to-human inflection gap rather than a labeling problem.

## Open items

- Training loss for seed 2, to check whether it stalled.
- A `--init` path for fine-tuning on user speech.
