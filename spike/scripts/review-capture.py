#!/usr/bin/env python3
"""Fresh direct children; kernel executable/start identity gates timeout signals."""
import ctypes
import hashlib
import json
import os
import pathlib
import signal
import struct
import subprocess
import sys
import time

libproc = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
libproc.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
libproc.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int]


def identity(pid):
    path = ctypes.create_string_buffer(4096)
    info = ctypes.create_string_buffer(136)  # Darwin proc_bsdinfo, PROC_PIDTBSDINFO=3
    if libproc.proc_pidpath(pid, path, len(path)) <= 0:
        return None
    if libproc.proc_pidinfo(pid, 3, 0, info, len(info)) != len(info):
        return None
    seconds, microseconds = struct.unpack_from('=QQ', info.raw, 120)
    return {'pid': pid, 'kernelPath': os.fsdecode(path.value), 'startSeconds': seconds,
            'startMicroseconds': microseconds}


def signal_owned(child, captured, sig):
    # poll deliberately not called here: an unreaped direct child cannot be PID-reused.
    if captured is None or identity(child.pid) != captured:
        raise RuntimeError('identity mismatch; no signal or cleanup permitted')
    child.send_signal(sig)


def run_owned(exe, arguments, log):
    with log.open('w') as stream:
        child = subprocess.Popen([exe, *arguments], stdout=stream, stderr=subprocess.STDOUT)
        captured = None
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            captured = identity(child.pid)
            if captured and captured['kernelPath'] == str(pathlib.Path(exe).resolve()):
                break
            time.sleep(0.005)
        if not captured or captured['kernelPath'] != str(pathlib.Path(exe).resolve()):
            # Reap a naturally exited child when possible, never signal without identity.
            # A still-running unidentifiable child blocks completion and retains all files.
            child.wait(timeout=30)
            raise RuntimeError('owned executable identity unavailable; no signal sent')
        timed_out = False
        try:
            child.wait(timeout=30)
        except subprocess.TimeoutExpired:
            timed_out = True
            signal_owned(child, captured, signal.SIGTERM)
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                signal_owned(child, captured, signal.SIGKILL)
                child.wait(timeout=5)
    try:
        os.kill(child.pid, 0)  # Liveness query only, never a PID-only signal.
        absent = False
    except ProcessLookupError:
        absent = True
    result = dict(captured, exitCode=child.returncode, waited=True, ESRCH=absent, timeout=timed_out)
    if timed_out or child.returncode != 0 or not absent:
        raise RuntimeError(f'capture failed; retained evidence: {result}')
    return result


def capture(exe, image, fixture, output, log):
    result = run_owned(exe, ['--review', str(output), image, fixture], log)
    if 'all owned windows closed' not in log.read_text():
        raise RuntimeError('window closure confirmation missing')
    data = output.read_bytes()
    if not (0 < len(data) <= 2097152 and data[:8] == b'\x89PNG\r\n\x1a\n'
            and struct.unpack('>II', data[16:24]) == (720, 540)):
        raise RuntimeError('invalid PNG header/bounds')
    return result, {'fixture': fixture, 'file': output.name, 'width': 720, 'height': 540,
                    'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                    'pngValidated': True, 'visualFidelity': 'not automatically verified'}


def main():
    exe, work, review, image = sys.argv[1:]
    work, review = pathlib.Path(work), pathlib.Path(review)
    listing = run_owned(exe, ['--review-list'], work / 'fixture-list.log')
    (work / 'listing-lifecycle.json').write_text(json.dumps(listing, indent=2) + '\n')
    fixtures = (work / 'fixture-list.log').read_text().splitlines()
    assert len(fixtures) >= 20 and len(fixtures) == len(set(fixtures))
    manifest = {'method': 'NSHostingView.cacheDisplay in owned NSWindow',
                'configuration': {'widthPoints': 720, 'heightPoints': 540, 'scale': 1,
                                  'appearance': 'aqua/light', 'window': 'borderless/off-desktop/non-key/inactive',
                                  'activationPolicy': 'prohibited', 'settlingSeconds': 0.25,
                                  'maximumPNGBytes': 2097152, 'animations': 'disabled',
                                  'locale': 'en_US_POSIX', 'state': 'fixed source-defined local seeds',
                                  'localImage': image},
                'artifacts': []}
    lifecycle = []
    repeat_dir = work / 'repeat'
    repeat_dir.mkdir()
    for fixture in fixtures:
        process, artifact = capture(exe, image, fixture, review / f'{fixture}.png', work / f'{fixture}.log')
        lifecycle.append(dict(process, fixture=fixture, passName='primary'))
        manifest['artifacts'].append(artifact)
        (review / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        (work / 'lifecycle.json').write_text(json.dumps(lifecycle, indent=2) + '\n')
        process, repeated = capture(exe, image, fixture, repeat_dir / f'{fixture}.png', work / f'{fixture}-repeat.log')
        lifecycle.append(dict(process, fixture=fixture, passName='repeat'))
        artifact['freshRepeatByteIdentical'] = artifact['sha256'] == repeated['sha256']
        (review / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        (work / 'lifecycle.json').write_text(json.dumps(lifecycle, indent=2) + '\n')
    assert set(p.name for p in review.iterdir()) == {'manifest.json'} | {f'{f}.png' for f in fixtures}
    print(f'{len(fixtures)} primary PNGs; {len(lifecycle)} exact-owned children reaped; '
          f'{sum(a["freshRepeatByteIdentical"] for a in manifest["artifacts"])} byte-identical repeats')


if __name__ == '__main__':
    main()
