"""Unit tests for the wake-word matcher (scripts/wakeword_matcher.py). Run with: .venv/bin/python scripts/test_wakeword_matcher.py"""

import os
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wakeword_matcher import clip_triggers, triggers  # noqa: E402


class MatcherTests(unittest.TestCase):
    def test_threshold_is_inclusive(self):
        self.assertTrue(triggers([0.5], 0.5)[0])

    def test_just_below_threshold_does_not_trigger(self):
        self.assertFalse(triggers([0.4999], 0.5)[0])

    def test_each_window_is_decided_separately(self):
        np.testing.assert_array_equal(triggers([0.1, 0.6, 0.5], 0.5), [False, True, True])

    def test_clip_triggers_when_any_window_does(self):
        self.assertTrue(clip_triggers([0.1, 0.2, 0.9], 0.5))

    def test_clip_does_not_trigger_when_no_window_does(self):
        self.assertFalse(clip_triggers([0.1, 0.49, 0.2], 0.5))

    def test_threshold_moves_the_decision(self):
        self.assertFalse(clip_triggers([0.6], 0.7))
        self.assertTrue(clip_triggers([0.6], 0.5))


if __name__ == "__main__":
    unittest.main()
