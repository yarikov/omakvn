import importlib.util
import json
from pathlib import Path
import unittest


MODULE_PATH = Path(__file__).parents[1] / "ipc_bridge.py"
SPEC = importlib.util.spec_from_file_location("ipc_bridge", MODULE_PATH)
assert SPEC and SPEC.loader
ipc_bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ipc_bridge)


class LineFramerTests(unittest.TestCase):
    def test_preserves_utf8_split_between_reads(self):
        payload = json.dumps(
            {"connection": "Idle", "status": "Привет 👋"},
            ensure_ascii=False,
        ).encode()
        split = payload.index("П".encode()) + 1
        framer = ipc_bridge.LineFramer()

        self.assertEqual(framer.feed(payload[:split]), [])
        lines = framer.feed(payload[split:] + b"\n")

        normalized = ipc_bridge.normalize_line(lines[0])
        self.assertIsNotNone(normalized)
        self.assertEqual(json.loads(normalized)["status"], "Привет 👋")
        self.assertTrue(normalized.isascii())

    def test_discards_oversized_line_and_recovers(self):
        framer = ipc_bridge.LineFramer(max_line_bytes=8)

        lines = framer.feed(b"123456789\nvalid\n")

        self.assertEqual(lines, [b"valid"])


class NormalizationTests(unittest.TestCase):
    def test_rejects_pathologically_nested_json(self):
        nested = b'{"connection":"Idle","profiles":' + b"[" * 2000 + b"]" * 2000 + b"}"

        self.assertIsNone(ipc_bridge.normalize_line(nested))

    def test_rejects_ascii_output_over_the_line_limit(self):
        value = "я" * (ipc_bridge.MAX_LINE_BYTES // 6 + 1)

        self.assertIsNone(ipc_bridge.normalize_line(json.dumps(value, ensure_ascii=False).encode()))


if __name__ == "__main__":
    unittest.main()
