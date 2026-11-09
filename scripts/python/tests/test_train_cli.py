"""Tests for scripts/python/train_cli.py, the train.json input record.

Run with: .venv/bin/python scripts/python/tests/test_train_cli.py
"""

import contextlib
import io
import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import train_cli  # noqa: E402

ROOT = train_cli.ROOT

# Pinned output for no arguments. A changed default shows up here as a visible diff.
GOLDEN_DEFAULTS = """{
  "batch": 32,
  "extra": "lab/wakeword/extra",
  "holdout": [],
  "lr": 0.001,
  "media": "media",
  "no_extra": false,
  "noise": "lab/wakeword/noise",
  "noise_snr": [
    3.0,
    30.0
  ],
  "schema": 1,
  "seed": 0,
  "steps": 6000,
  "take": null,
  "threshold": 0.5,
  "wakeword": "iapapo",
  "window_scale": 1.0
}
"""


def emit(argv):
    """Run train_cli.main and return what it printed to stdout."""
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        train_cli.main(argv)
    return buf.getvalue()


def argv_from(record):
    """Turn a train.json record back into command-line arguments, for the idempotence test."""
    argv = []
    for key, value in record.items():
        if key == "schema" or value is None or value is False:
            continue
        flag = "--" + key.replace("_", "-")
        if value is True:
            argv.append(flag)
        elif isinstance(value, list):
            argv += [flag] + [str(v) for v in value]
        else:
            argv += [flag, str(value)]
    return argv


class TrainCliTest(unittest.TestCase):
    def setUp(self):
        # Paths are resolved against the current directory, so run from the repo root unless a test says otherwise.
        self._saved_cwd = os.getcwd()
        os.chdir(ROOT)

    def tearDown(self):
        os.chdir(self._saved_cwd)

    def test_defaults_golden(self):
        self.assertEqual(emit([]), GOLDEN_DEFAULTS)

    def test_equivalent_forms_identical_bytes(self):
        forms = [
            ["--seed", "15"],
            ["--seed", "15", "--steps", "6000"],
            ["--seed", "15", "--steps", "6000", "--batch", "32", "--lr", "0.001", "--threshold", "0.5",
             "--noise-snr", "3", "30", "--window-scale", "1.0"],
            ["--step", "6000", "--seed", "15"],
            ["--seed", "1", "--seed", "15"],
            ["--noise-snr", "3", "30", "--seed", "15"],
            ["--seed", "15", "--lr", "1e-3"],
        ]
        expected = emit(forms[0])
        for argv in forms:
            with self.subTest(argv=argv):
                self.assertEqual(emit(argv), expected)

    def test_values_are_typed(self):
        rec = train_cli.build(["--noise-snr", "5", "30", "--lr", "1e-3", "--seed", "15"])
        self.assertEqual(rec["noise_snr"], [5.0, 30.0])
        self.assertTrue(all(isinstance(v, float) for v in rec["noise_snr"]))
        self.assertEqual(rec["lr"], 0.001)
        self.assertIsInstance(rec["seed"], int)

    def test_paths_are_repo_relative_from_any_directory(self):
        scripts = os.path.join(ROOT, "scripts")
        os.chdir(scripts)
        self.assertEqual(train_cli.build(["--media", "python"])["media"], "scripts/python")
        os.chdir(ROOT)
        self.assertEqual(train_cli.build(["--media", "python"])["media"], "python")

    def test_bare_take_name_resolves_under_takes(self):
        rec = train_cli.build(["--take", "20261101-183517"])
        self.assertEqual(rec["take"], "lab/wakeword/takes/20261101-183517")

    def test_idempotent(self):
        once = train_cli.build(["--seed", "15", "--take", "20261101-183517", "--no-extra", "--holdout", "a", "b"])
        twice = train_cli.build(argv_from(once))
        self.assertEqual(twice, once)

    def test_rejections_exit_2_with_empty_stdout(self):
        bad = [["--bogus"], ["--seed", "abc"], ["--seed", "-1"], ["--seed", "4294967296"],
               ["--steps", "1.5"], ["--noise-snr", "3"]]
        for argv in bad:
            with self.subTest(argv=argv):
                buf = io.StringIO()
                with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(io.StringIO()):
                    with self.assertRaises(SystemExit) as ctx:
                        train_cli.main(argv)
                self.assertEqual(ctx.exception.code, 2)
                self.assertEqual(buf.getvalue(), "")

    def test_output_is_sorted_json_with_schema_and_writes_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.chdir(tmp)
            out = emit(["--seed", "15"])
            self.assertEqual(os.listdir(tmp), [])
        rec = json.loads(out)
        self.assertEqual(rec["schema"], train_cli.SCHEMA)
        self.assertEqual(list(json.loads(out).keys()), sorted(rec.keys()))


if __name__ == "__main__":
    unittest.main()
