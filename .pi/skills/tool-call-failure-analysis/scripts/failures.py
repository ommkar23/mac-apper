#!/usr/bin/env python3
"""Inspect Pi sessions and index reviewed failure traces without re-running tool calls."""

import argparse
import json
import re
import sqlite3
import uuid
from pathlib import Path

DEFAULT_DB = Path(".pi/learnings/failures/failures.sqlite3")
TRACE_NAME = re.compile(r"^(?P<session>[0-9a-fA-F-]{36})-trace-(?P<number>[1-9][0-9]*)\.jsonl$")
MAX_LINE = 8 * 1024 * 1024


def records(path):
    with path.open("rb") as stream:
        for number, line in enumerate(stream, 1):
            if len(line) > MAX_LINE:
                raise ValueError(f"{path}:{number}: record exceeds {MAX_LINE} bytes")
            try:
                value = json.loads(line)
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                raise ValueError(f"{path}:{number}: invalid JSON: {error}") from error
            if not isinstance(value, dict):
                raise ValueError(f"{path}:{number}: expected an object")
            yield value


def calls(record):
    message = record.get("message", {})
    if record.get("type") != "message" or message.get("role") != "assistant":
        return []
    return [item for item in message.get("content", []) if isinstance(item, dict) and item.get("type") == "toolCall"]


def result(record):
    message = record.get("message", {})
    if record.get("type") == "message" and message.get("role") == "toolResult":
        return message
    return None


def validate_trace(entries):
    if not entries:
        raise ValueError("empty trace")
    seen, results, failures = set(), set(), []
    for entry in entries:
        for call in calls(entry):
            identifier = call.get("id")
            if not isinstance(identifier, str) or not identifier or identifier in seen:
                raise ValueError("missing or duplicate tool call ID")
            seen.add(identifier)
        reply = result(entry)
        if reply is not None:
            identifier = reply.get("toolCallId")
            if identifier not in seen or identifier in results or not isinstance(reply.get("isError"), bool):
                raise ValueError("orphan, duplicate, or invalid tool result")
            results.add(identifier)
            if reply["isError"]:
                failures.append(identifier)
    if seen != results or not failures:
        raise ValueError("trace must have matching call/result pairs and at least one failed call")
    return failures


def connect(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path)
    db.execute("PRAGMA foreign_keys = ON")
    db.executescript("""
        CREATE TABLE IF NOT EXISTS traces (
            session_id TEXT NOT NULL,
            trace_number INTEGER NOT NULL,
            records_json TEXT NOT NULL,
            PRIMARY KEY (session_id, trace_number)
        );
        CREATE TABLE IF NOT EXISTS failures (
            session_id TEXT NOT NULL,
            tool_call_id TEXT NOT NULL,
            trace_number INTEGER NOT NULL,
            PRIMARY KEY (session_id, tool_call_id),
            FOREIGN KEY (session_id, trace_number) REFERENCES traces(session_id, trace_number)
        );
    """)
    return db


def import_trace(db, path):
    match = TRACE_NAME.fullmatch(path.name)
    if match is None:
        raise ValueError(f"invalid trace filename: {path.name}")
    session, number = match.group("session"), int(match.group("number"))
    entries = list(records(path))
    failed_ids = validate_trace(entries)
    payload = json.dumps(entries, ensure_ascii=False, separators=(",", ":"))
    with db:
        existing = db.execute(
            "SELECT records_json FROM traces WHERE session_id=? AND trace_number=?", (session, number)
        ).fetchone()
        if existing is not None:
            if json.loads(existing[0]) != entries:
                raise ValueError(f"trace {session}-{number} already exists with different contents")
            return False
        overlaps = db.execute(
            f"SELECT tool_call_id FROM failures WHERE session_id=? AND tool_call_id IN ({','.join('?' for _ in failed_ids)})",
            (session, *failed_ids),
        ).fetchall()
        if len(overlaps) == len(failed_ids):
            return False
        if overlaps:
            raise ValueError("partial failure overlap; separate new failures before importing")
        db.execute("INSERT INTO traces VALUES (?, ?, ?)", (session, number, payload))
        db.executemany("INSERT INTO failures VALUES (?, ?, ?)", [(session, cid, number) for cid in failed_ids])
    return True


def save_trace(db, source, session_id, directory):
    """Save a reviewed trace and index it in one command; skip previously indexed failures."""
    if str(uuid.UUID(session_id)) != session_id:
        raise ValueError("session ID must be a canonical UUID")
    entries = list(records(source))
    failed_ids = validate_trace(entries)
    placeholders = ",".join("?" for _ in failed_ids)
    existing = db.execute(
        f"SELECT tool_call_id FROM failures WHERE session_id=? AND tool_call_id IN ({placeholders})",
        (session_id, *failed_ids),
    ).fetchall()
    if len(existing) == len(failed_ids):
        return None
    if existing:
        raise ValueError("partial failure overlap; separate new failures before saving")
    directory.mkdir(parents=True, exist_ok=True)
    stored = db.execute(
        "SELECT COALESCE(MAX(trace_number), 0) FROM traces WHERE session_id=?", (session_id,)
    ).fetchone()[0]
    on_disk = [int(match.group("number")) for path in directory.glob(f"{session_id}-trace-*.jsonl")
               if (match := TRACE_NAME.fullmatch(path.name))]
    number = max([stored, *on_disk]) + 1
    destination = directory / f"{session_id}-trace-{number}.jsonl"
    created = False
    try:
        with destination.open("x", encoding="utf-8") as stream:
            created = True
            for entry in entries:
                stream.write(json.dumps(entry, ensure_ascii=False, separators=(",", ":")) + "\n")
        import_trace(db, destination)
    except Exception:
        if created:
            destination.unlink()
        raise
    return destination


def export(db, directory):
    directory.mkdir(parents=True, exist_ok=True)
    for session, number, payload in db.execute(
        "SELECT session_id, trace_number, records_json FROM traces ORDER BY session_id, trace_number"
    ):
        path = directory / f"{session}-trace-{number}.jsonl"
        with path.open("x", encoding="utf-8") as stream:
            for entry in json.loads(payload):
                stream.write(json.dumps(entry, ensure_ascii=False, separators=(",", ":")) + "\n")
        print(path)


def list_failures(path):
    pending = {}
    for index, entry in enumerate(records(path), 1):
        for call in calls(entry):
            pending[call.get("id")] = (index, call.get("name"))
        reply = result(entry)
        if reply and reply.get("isError") is True:
            identifier = reply.get("toolCallId")
            call_index, name = pending.get(identifier, ("?", "?"))
            print(f"call line {call_index}, result line {index}: {name} {identifier}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    listing = sub.add_parser("list", help="list explicitly failed calls in a Pi session")
    listing.add_argument("session", type=Path)
    importing = sub.add_parser("import", help="index reviewed JSONL traces")
    importing.add_argument("traces", type=Path, nargs="+")
    importing.add_argument("--db", type=Path, default=DEFAULT_DB)
    saving = sub.add_parser("save", help="write a reviewed trace and automatically index it, skipping duplicates")
    saving.add_argument("reviewed", type=Path, help="reviewed JSONL with matched tool calls and results")
    saving.add_argument("--session-id", required=True)
    saving.add_argument("--output-dir", type=Path, default=DEFAULT_DB.parent)
    saving.add_argument("--db", type=Path, default=DEFAULT_DB)
    exporting = sub.add_parser("export", help="export stored JSONL traces, without overwriting")
    exporting.add_argument("--output-dir", type=Path, required=True)
    exporting.add_argument("--db", type=Path, default=DEFAULT_DB)
    args = parser.parse_args()
    try:
        if args.command == "list":
            list_failures(args.session)
        else:
            with connect(args.db) as db:
                if args.command == "import":
                    for path in args.traces:
                        print(f"{'imported' if import_trace(db, path) else 'already stored'}: {path}")
                elif args.command == "save":
                    path = save_trace(db, args.reviewed, args.session_id, args.output_dir)
                    print(f"saved and indexed: {path}" if path else "already stored; skipped")
                else:
                    export(db, args.output_dir)
    except (ValueError, OSError, sqlite3.Error) as error:
        parser.exit(1, f"error: {error}\n")


if __name__ == "__main__":
    main()
