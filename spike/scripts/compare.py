#!/usr/bin/env python3
"""Check exact byte reproducibility; differences are not support verdicts."""
import hashlib
import json
import pathlib
import sys

run = pathlib.Path(sys.argv[1])
def collect(directory):
    records = []
    for manifest in sorted((run / directory).glob('*/artifacts.json')):
        for artifact in json.loads(manifest.read_text()):
            artifact['file'] = manifest.parent.name + '/' + artifact['file']
            records.append(artifact)
    records.sort(key=lambda a: (a['fixture'], a['method']))
    assert len(records) == 48
    assert len({(a['fixture'], a['method']) for a in records}) == 48
    for a in records:
        assert (a['width'], a['height']) == (460, 430)
        data = (run / directory / a['file']).read_bytes()
        assert data[:8] == b'\x89PNG\r\n\x1a\n'
        assert hashlib.sha256(data).hexdigest() == a['sha256']
        assert len(data) <= 2097152
    (run / directory / 'artifacts.json').write_text(json.dumps(records, indent=2) + '\n')
    return records
first, repeat = collect('first'), collect('repeat')
mismatches = [a['file'] for a, b in zip(first, repeat) if a != b]
lookup = {(a['fixture'], a['method']): a for a in first}
fixtures = sorted({a['fixture'] for a in first})
summary = {'artifacts_per_run': len(first), 'dimensions': [460, 430],
           'exact_repeat_mismatches': mismatches,
           'cold_vs_after_host_hash_equal': [f for f in fixtures if lookup[f, 'image-renderer']['sha256'] == lookup[f, 'image-renderer-after-host']['sha256']],
           'note': 'Hash equality/difference is not a visual support verdict.'}
(run / 'reproducibility.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))
