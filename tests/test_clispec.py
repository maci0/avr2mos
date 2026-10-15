"""CLI Spec checks for the avr2mos translator. Drives the built binary."""

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "zig-out" / "bin" / "avr2mos"


def run(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run([str(BIN), *args], capture_output=True, text=True, check=False)


class CliSpecTest(unittest.TestCase):
    def test_schema_offline(self) -> None:
        done = run(["schema"])
        self.assertEqual(done.returncode, 0, done.stderr)
        doc = json.loads(done.stdout)
        self.assertEqual(doc["clispec"], "0.3")
        self.assertEqual(doc["name"], "avr2mos")
        self.assertEqual(doc["version"], "0.1.0")
        self.assertEqual(doc["output"], {"tty": "text", "piped": "text"})
        names = [cmd["name"] for cmd in doc["commands"]]
        self.assertEqual(names, ["schema", "version", "translate"])
        kinds = {err["kind"]: err["exit_code"] for err in doc["errors"]}
        self.assertEqual(kinds["usage"], 2)
        self.assertEqual(kinds["failure"], 1)
        translate = next(cmd for cmd in doc["commands"] if cmd["name"] == "translate")
        self.assertEqual(translate["effects"], "idempotent")
        fields = {field["name"] for field in translate["output_fields"]}
        self.assertIn("changed", fields)

    def test_schema_filter_and_text_mode_stays_json(self) -> None:
        done = run(["--format", "text", "schema", "version"])
        self.assertEqual(done.returncode, 0, done.stderr)
        doc = json.loads(done.stdout)
        self.assertEqual([cmd["name"] for cmd in doc["commands"]], ["version"])

    def test_version_text_is_not_json(self) -> None:
        done = run(["--format", "text", "version"])
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout, "avr2mos 0.1.0\n")

    def test_version_json(self) -> None:
        done = run(["--format", "json", "version"])
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(json.loads(done.stdout), {"version": "0.1.0"})

    def test_output_flag_is_still_the_destination(self) -> None:
        done = run(["-o", "json", "version"])
        self.assertEqual(done.returncode, 2)
        self.assertFalse(done.stderr.strip().splitlines()[-1].startswith("{"))

    def test_json_usage_envelope(self) -> None:
        done = run(["--format", "json", "--bogus"])
        self.assertEqual(done.returncode, 2)
        last = done.stderr.strip().splitlines()[-1]
        self.assertEqual(json.loads(last)["error"]["kind"], "usage")

    def test_bad_format_has_no_envelope(self) -> None:
        done = run(["--format", "nope"])
        self.assertEqual(done.returncode, 2)
        self.assertFalse(done.stderr.strip().splitlines()[-1].startswith("{"))

    def test_translate_json_reports_changed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "in.bin"
            out = Path(tmp) / "out.bin"
            src.write_bytes(b"\x00\x00")
            first = run(["--format", "json", "--input", str(src), "--output", str(out)])
            self.assertEqual(first.returncode, 0, first.stderr)
            payload = json.loads(first.stdout)
            self.assertEqual(payload["input"], str(src))
            self.assertEqual(payload["output"], str(out))
            self.assertIsInstance(payload["bytes"], int)
            self.assertTrue(payload["changed"])
            self.assertTrue(out.exists())
            second = run(["--format", "json", "translate", "--input", str(src), "--output", str(out)])
            self.assertEqual(second.returncode, 0, second.stderr)
            again = json.loads(second.stdout)
            self.assertFalse(again["changed"])
            self.assertEqual(again["bytes"], payload["bytes"])


if __name__ == "__main__":
    unittest.main()
