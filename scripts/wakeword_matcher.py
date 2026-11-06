"""The wake-word matcher: turns window probabilities into trigger decisions.

A window triggers when its probability is at or above the threshold. A clip triggers when any of
its windows does. Every script that makes a trigger decision calls these functions, so the rule
lives in one place.
"""

import numpy as np


def triggers(probs, threshold):
    """Boolean array: which windows trigger at this threshold."""
    return np.asarray(probs) >= threshold


def clip_triggers(probs, threshold):
    """True when any window of the clip triggers."""
    return bool(triggers(probs, threshold).any())
