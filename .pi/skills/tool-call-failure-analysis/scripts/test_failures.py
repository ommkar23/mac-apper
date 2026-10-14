import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("failures", Path(__file__).with_name("failures.py"))
failures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(failures)
SESSION = "01a0d77b-7b39-75b8-8866-18e95cd2b0bc"


def trace(path, ids, recovery=False):
    entries = []
    for identifier in ids:
        entries.extend([
            {"type": "message", "message": {"role": "assistant", "content": [
                {"type": "toolCall", "id": identifier, "name": "bash", "arguments": {"command": "false"}}
            ]}},
            {"type": "message", "message": {"role": "toolResult", "toolCallId": identifier,
                                            "isError": True, "content": [{"type": "text", "text": "failed"}]}},
        ])
    if recovery:
        entries.extend([
            {"type": "message", "message": {"role": "assistant", "content": [
                {"type": "toolCall", "id": "recovery", "name": "bash", "arguments": {"command": "true"}}
            ]}},
            {"type": "message", "message": {"role": "toolResult", "toolCallId": "recovery",
                                            "isError": False, "content": [{"type": "text", "text": "ok"}]}},
        ])
    path.write_text("".join(json.dumps(item) + "\n" for item in entries))
    return entries


class TraceTests(unittest.TestCase):
    def test_cli_defaults_archive_under_pi(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "reviewed.jsonl"
            expected = trace(source, ["default-path"])
            script = Path(__file__).with_name("failures.py").resolve()
            subprocess.run(
                [sys.executable, str(script), "save", str(source), "--session-id", SESSION],
                cwd=root, check=True, capture_output=True,
            )
            archive = root / ".pi" / "learnings" / "failures"
            self.assertTrue((archive / "failures.sqlite3").is_file())
            self.assertEqual(list(failures.records(archive / f"{SESSION}-trace-1.jsonl")), expected)
            self.assertFalse((root / "learnings").exists())

    def test_idempotent_import_overlap_rejected_and_export(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            one = root / f"{SESSION}-trace-1.jsonl"
            two = root / f"{SESSION}-trace-2.jsonl"
            expected = trace(one, ["fail-1", "fail-2"], recovery=True)
            trace(two, ["fail-2"])
            with failures.connect(root / "db.sqlite3") as db:
                self.assertTrue(failures.import_trace(db, one))
                self.assertFalse(failures.import_trace(db, one))
                self.assertFalse(failures.import_trace(db, two))  # Same failed call, different filename.
                trace(two, ["fail-2", "new"])
                with self.assertRaisesRegex(ValueError, "partial failure overlap"):
                    failures.import_trace(db, two)
                self.assertEqual(db.execute("SELECT count(*) FROM failures").fetchone()[0], 2)
                failures.export(db, root / "export")
                with self.assertRaises(FileExistsError):
                    failures.export(db, root / "export")
            self.assertEqual(list(failures.records(root / "export" / one.name)), expected)

    def test_save_assigns_next_number_and_skips_duplicate_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "reviewed.jsonl"
            trace(source, ["same"], recovery=True)
            with failures.connect(root / "db.sqlite3") as db:
                first = failures.save_trace(db, source, SESSION, root / "traces")
                self.assertEqual(first.name, f"{SESSION}-trace-1.jsonl")
                self.assertIsNone(failures.save_trace(db, source, SESSION, root / "traces"))
                self.assertEqual(len(list((root / "traces").glob("*.jsonl"))), 1)
                self.assertEqual(db.execute("SELECT count(*) FROM failures").fetchone()[0], 1)
                trace(source, ["different"])
                second = failures.save_trace(db, source, SESSION, root / "traces")
                self.assertEqual(second.name, f"{SESSION}-trace-2.jsonl")

    def test_save_rejects_partial_overlap_without_losing_new_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "reviewed.jsonl"
            with failures.connect(root / "db.sqlite3") as db:
                trace(source, ["same"])
                failures.save_trace(db, source, SESSION, root / "traces")
                trace(source, ["same", "new"])
                with self.assertRaisesRegex(ValueError, "overlap"):
                    failures.save_trace(db, source, SESSION, root / "traces")
                self.assertEqual(db.execute("SELECT count(*) FROM failures").fetchone()[0], 1)
                self.assertEqual(len(list((root / "traces").glob("*.jsonl"))), 1)

    def test_rejects_missing_result_and_trace_without_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / f"{SESSION}-trace-1.jsonl"
            entries = trace(path, ["failure"])
            with failures.connect(Path(temp) / "db.sqlite3") as db:
                path.write_text(json.dumps(entries[0]) + "\n")
                with self.assertRaisesRegex(ValueError, "matching"):
                    failures.import_trace(db, path)
                entries[1]["message"]["isError"] = False
                path.write_text("".join(json.dumps(item) + "\n" for item in entries))
                with self.assertRaisesRegex(ValueError, "at least one"):
                    failures.import_trace(db, path)


if __name__ == "__main__":
    unittest.main()
