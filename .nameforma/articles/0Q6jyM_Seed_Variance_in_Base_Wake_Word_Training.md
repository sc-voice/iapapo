---
type: nameforma.md
zuid: 0Q6jyMMM00D3Ywo0oukl7W
collection: world
title: "0Q6jyM_Seed_Variance_in_Base_Wake_Word_Training"
description: Seed 1-20 results for the base WakeNet on the current train.py, with seed 15 as the export candidate, plus earlier noise comparisons
agent_instructions: Maintain synchronous awareness without a persistent urge to solve or fix anything until a consensus call to action emerges.
---

## Overview

The base model's score depends on the random seed more than on the training code or the background noise setting. Changes to `scripts/python/train.py` can reorder which seed scores best, so the export seed has to be re-checked after each change.

Seed 15 is the current export candidate. Seeds 5 and 15 have been the strongest across most changes so far, but the sweep below shows that is not a fixed rule.

All runs use `scripts/python/train.py` with 6000 steps, batch 32, lr 0.001, window 0.893 s, and noise SNR 3-30 dB unless noted. Results are in `lab/wakeword/out/`, with `scores.csv` and `run.log` per run. A run's `run.json` records its seed and `train_args`.

## Replicate check

Same seed, same settings, same data reproduce exactly (max score difference 0.000000):

- Current code, seed 15: `dkQlX-bLy/no-take-0Q6x2K` and `dkQlX-bLy/no-take-0Q6x7T`. `scores.csv` is identical and `wakenet.pt` is byte-identical.
- Earlier code, seed 0, 20-30 dB crumpling: `0Q6itZ/no-take-0Q6j8O` and `0Q6itZ/no-take-0Q6jG9`.
- Earlier code, seed 1, 3-30 dB crumpling: `0Q6jON/no-take-0Q6jOn` and `0Q6jON/no-take-0Q6jQs`.

## Current code (dkQlX-bLy), seeds 5 and 15

Positives are out of 41. False triggers count every negative clip at p >= 0.5 (322 negatives). Mean positive is the mean of the per-clip score in `scores.csv`.

| seed | run | positives | false triggers | mean positive | final loss |
|---:|---|---:|---:|---:|---:|
| 5 | `dkQlX-bLy/no-take-0Q6w_e` | 35 | 0 | 0.800 | 0.0010 |
| 15 | `dkQlX-bLy/no-take-0Q6x2K` | 41 | 0 | 0.986 | 0.0001 |
| 15 (repeat) | `dkQlX-bLy/no-take-0Q6x7T` | 41 | 0 | 0.986 | 0.0001 |

## Previous code (uyH5DWIyZ), seeds 1 to 20

Same settings as above on the earlier `train.py`. Seed 5 appears twice with identical results.

| seed | run | positives | false triggers | mean positive | final loss |
|---:|---|---:|---:|---:|---:|
| 1 | `uyH5DWIyZ/no-take-0Q6siR` | 34 | 0 | 0.834 | 0.0001 |
| 2 | `uyH5DWIyZ/no-take-0Q6skB` | 29 | 21 | 0.679 | 0.0046 |
| 3 | `uyH5DWIyZ/no-take-0Q6slh` | 37 | 2 | 0.865 | 0.0001 |
| 4 | `uyH5DWIyZ/no-take-0Q6seT` | 41 | 4 | 0.997 | 0.0001 |
| 5 | `uyH5DWIyZ/no-take-0Q6sXS` | 38 | 0 | 0.902 | 0.0003 |
| 5 (repeat) | `uyH5DWIyZ/no-take-0Q6sVq` | 38 | 0 | 0.902 | 0.0003 |
| 6 | `uyH5DWIyZ/no-take-0Q6sn1` | 28 | 18 | 0.627 | 0.0074 |
| 7 | `uyH5DWIyZ/no-take-0Q6soL` | 29 | 6 | 0.684 | 0.0042 |
| 8 | `uyH5DWIyZ/no-take-0Q6spg` | 29 | 29 | 0.667 | 0.0093 |
| 9 | `uyH5DWIyZ/no-take-0Q6sq-` | 37 | 1 | 0.893 | 0.0001 |
| 10 | `uyH5DWIyZ/no-take-0Q6ssI` | 41 | 51 | 0.998 | 0.0017 |
| 11 | `uyH5DWIyZ/no-take-0Q6tKD` | 12 | 16 | 0.389 | 0.0077 |
| 12 | `uyH5DWIyZ/no-take-0Q6tLX` | 23 | 8 | 0.512 | 0.0031 |
| 13 | `uyH5DWIyZ/no-take-0Q6tMs` | 33 | 0 | 0.782 | 0.0001 |
| 14 | `uyH5DWIyZ/no-take-0Q6tOG` | 36 | 1 | 0.886 | 0.0001 |
| 15 | `uyH5DWIyZ/no-take-0Q6tPc` | 40 | 1 | 0.928 | 0.0001 |
| 16 | `uyH5DWIyZ/no-take-0Q6tQy` | 33 | 0 | 0.792 | 0.0002 |
| 17 | `uyH5DWIyZ/no-take-0Q6tSH` | 35 | 52 | 0.793 | 0.0074 |
| 18 | `uyH5DWIyZ/no-take-0Q6tTc` | 35 | 3 | 0.850 | 0.0001 |
| 19 | `uyH5DWIyZ/no-take-0Q6tUw` | 41 | 18 | 0.990 | 0.0002 |
| 20 | `uyH5DWIyZ/no-take-0Q6tWF` | 30 | 21 | 0.733 | 0.0056 |

Seed 5 gives a different result on the earlier code in another version folder: `0Q6nUb/no-take-0Q6nUm` has 41 positives, 0 false triggers and mean 0.995. The version folder matters, so compare seeds only within the same `train.py` version.

## Earlier code (0Q6jON batch), seeds 0 to 5, no noise

Positives are out of 41. False triggers count every negative clip at p >= 0.5, including holdouts `_1` to `_3`, hard negatives `_4` to `_7q` and sentence negatives `_s1` to `_s3`.

| seed | run | positives | mean positive | false triggers |
|---|---|---:|---:|---:|
| 0 | `0Q6i9B/no-take-0Q6iKd` | 35 | 0.84 | 6 |
| 1 | `0Q6jON/no-take-0Q6jcF` | 36 | 0.86 | 0 |
| 2 | `0Q6jON/no-take-0Q6jeA` | 13 | 0.31 | 13 |
| 3 | `0Q6jON/no-take-0Q6jgu` | 29 | 0.67 | 6 |
| 4 | `0Q6jON/no-take-0Q6jjm` | 34 | 0.76 | 2 |
| 5 | `0Q6jON/no-take-0Q6jqo` | 40 | 0.97 | 11 |

## Background noise (earlier code, one clip at a time)

Noise clips come from `lab/wakeword/noise/` (café `651259-cafe-05`). Archival copy of the café clip, in case the lab is lost: `media/noise/651259-cafe-05.wav`, byte-identical to the training clip (nf hash `MrxpPH1y8MbxsXSWL3s6SRtvonw_u_BtwBRBC1rWvuW`). An AAC copy is not a substitute: it decodes to different samples and a different hash.

Café attribution: "ext_cafe_kahvilakumpu_walla_park" by ampi_sound, https://freesound.org/s/651259/, CC BY-NC 4.0 (https://creativecommons.org/licenses/by-nc/4.0/). The training clip is the 15–20 s chunk of the source, converted to mono 16 kHz (verified by cross-correlation at offset 15.000 s, normalized correlation 1.0000). Attribution is also recorded in `media/attribution.json`.

| setting | seed | run | positives | mean positive | false triggers |
|---|---|---|---:|---:|---:|
| crumpling 3-30 dB | 0 | `0Q6iRY/no-take-0Q6ilW` | 30 | 0.70 | 1 hard neg, 1 holdout |
| crumpling 3-30 dB | 1 | `0Q6jON/no-take-0Q6jOn` | 37 | 0.87 | 4 holdout `_1`, 1 hard neg, 4 sentence |
| crumpling 20-30 dB | 0 | `0Q6itZ/no-take-0Q6jG9` | 20 | 0.50 | 0 |
| café 3-30 dB | 1 | `0Q6jON/no-take-0Q6jaC` | 35 | 0.84 | 0 |
| café 3-30 dB | 5 | `0Q6jON/no-take-0Q6jsx` | 26 | 0.62 | 0 |

## Café paired by seed (earlier code)

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

## Fan, paired by seed (earlier code)

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

`0Q6jON/no-take-0Q6jsx` (café, seed 5, earlier code) scored on take `lab/wakeword/takes/turtlePro/20261104-075505`, which was not in training: positives 2 of 3 triggered (max 0.92, 0.99; the third at 0.02), negatives 0 of 3 triggered.

## Conclusions

Current code (dkQlX-bLy):

- Seed 15 reproduces exactly and is the export candidate: 41/41 positives, 0 false triggers, mean 0.986.
- Seed 5 is weaker on this code: 35/41 positives, mean 0.800.

Previous code (uyH5DWIyZ), seeds 1 to 20:

- Seed 15 has the fewest false triggers among seeds with at least 40 of 41 positives (1). Seeds 4, 10 and 19 also reach 40 or more positives, with 4, 51 and 18 false triggers.
- Seed 5 gave 38/41 on this version, not the 41/41 of the earlier 0Q6nUb version.
- Seeds 2, 6, 8, 11, 12, 17 and 20 have high loss (above 0.003) and many false triggers. Seed 2's loss from the earlier batch is now known: 0.0046.

Earlier code (0Q6jON batch, seeds 0 to 5):

- Seed dominates. The no-noise seeds range from 13 to 40 positives, wider than any noise effect so far.
- Café never adds false triggers relative to no noise on six seeds, and reduces them on four (0, 2, 3 and 5).
- Crumpling produces false triggers on seed 1 that café does not.
- Fan does not reduce false triggers on average and swings widely by seed, so it doesn't replace café on this evidence.

## Open items

- A `--init` path for fine-tuning on user speech. `train.py` has no such flag yet.
- Whether seeds 5 and 15 remain the best across further `train.py` changes. Each change needs a fresh seed sweep before the export seed is chosen.
