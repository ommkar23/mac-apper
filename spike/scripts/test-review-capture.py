#!/usr/bin/env python3
"""Offline signal ownership regressions: no real process is signaled."""
import importlib.util
import pathlib
import signal
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('capture', pathlib.Path(__file__).with_name('review-capture.py'))
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


class OwnershipTests(unittest.TestCase):
    def test_changed_start_or_path_never_signals(self):
        original = {'pid': 42, 'kernelPath': '/owned/render-spike', 'startSeconds': 100, 'startMicroseconds': 7}
        for current in (None, dict(original, startSeconds=101), dict(original, kernelPath='/unrelated')):
            child = Mock(pid=42)
            with patch.object(capture, 'identity', return_value=current):
                with self.assertRaises(RuntimeError):
                    capture.signal_owned(child, original, signal.SIGTERM)
            child.send_signal.assert_not_called()

    def test_exact_identity_allows_only_direct_child_signal(self):
        original = {'pid': 42, 'kernelPath': '/owned/render-spike', 'startSeconds': 100, 'startMicroseconds': 7}
        child = Mock(pid=42)
        with patch.object(capture, 'identity', return_value=original):
            capture.signal_owned(child, original, signal.SIGTERM)
        child.send_signal.assert_called_once_with(signal.SIGTERM)


if __name__ == '__main__':
    unittest.main()
