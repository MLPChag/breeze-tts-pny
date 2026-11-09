import contextlib
import http.client
import io
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'server'))
from breeze_pny.events import capture_events, event
from breeze_pny.files import acquire
from breeze_pny.native import NativePCM


class DiagnosticChecks(unittest.TestCase):
    def test_event_log_closes_and_does_not_capture_later_runs(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            path = Path(directory) / 'companion.jsonl'
            with self.assertRaises(ValueError):
                with capture_events(path):
                    event('speech', character='spike', adapter='base', seconds=1.0)
                    raise ValueError('fixture')
            event('later')
            rows = [json.loads(line) for line in path.read_text().splitlines()]
            self.assertEqual(rows, [{'event': 'speech', 'character': 'spike', 'adapter': 'base', 'seconds': 1.0}])
            path.rename(path.with_suffix('.closed'))  # Windows rejects this if the handler remains open.

    def test_cancel_during_a_chunked_read_is_reported_as_cancellation(self):
        stream = NativePCM(0, {}, '')
        stream.started = time.monotonic()
        def interrupted(_):
            stream.cancelled.set()
            raise http.client.IncompleteRead(b'', 4)
        stream.response = Mock()
        stream.response.read1.side_effect = interrupted
        with self.assertRaises(ConnectionAbortedError): list(stream.chunks())
        self.assertFalse(stream.completed)

    def test_incomplete_read_without_cancellation_remains_an_error(self):
        stream = NativePCM(0, {}, '')
        stream.started = time.monotonic()
        stream.response = Mock()
        stream.response.read1.side_effect = http.client.IncompleteRead(b'', 4)
        with self.assertRaises(http.client.IncompleteRead): list(stream.chunks())
        with self.assertRaises(RuntimeError): stream.receipt()

    def test_checksum_error_does_not_echo_a_url_credential(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as directory:
            source = 'https://user:private@example.invalid/model?token=private'
            with patch('breeze_pny.files.OPENER.open', return_value=io.BytesIO(b'bad download')):
                with self.assertRaises(ValueError) as error:
                    acquire(source, Path(directory) / 'model.gguf', '0' * 64)
            self.assertIn('model.gguf', str(error.exception))
            self.assertNotIn('private', str(error.exception))
