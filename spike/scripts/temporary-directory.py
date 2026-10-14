#!/usr/bin/env python3
"""Allocate disposable spike work in the private repository .tmp, never system temp."""
import os
from pathlib import Path
import re
import stat
import sys
import tempfile

PROJECT = Path(__file__).resolve().parents[2]


def temporary_root(project=PROJECT):
    project = Path(project)
    if not stat.S_ISDIR(project.lstat().st_mode):
        raise ValueError('Temporary project root must be an existing nonlinked directory')
    root = project / '.tmp'
    try:
        root.mkdir(mode=0o700)
    except FileExistsError:
        pass
    info = root.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError('Repository .tmp must be private, owner-owned and nonlinked')
    return root


def allocate(prefix, project=PROJECT):
    if re.fullmatch(r'[a-z][a-z0-9-]{0,63}', prefix) is None:
        raise ValueError('Invalid temporary directory prefix')
    return Path(tempfile.mkdtemp(prefix=prefix + '-', dir=temporary_root(project)))


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: temporary-directory.py PREFIX')
    print(allocate(sys.argv[1]))
