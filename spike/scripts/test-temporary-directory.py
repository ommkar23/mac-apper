#!/usr/bin/env python3
"""Offline allocator checks. No rendering, compiler, app or credential work."""
import importlib.util
from pathlib import Path
import stat
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
scripts = Path(__file__).resolve().parent


class TemporaryDirectoryTests(unittest.TestCase):
    def test_shell_entry_points_use_the_repository_allocator(self):
        for name in ('run.sh', 'minimal.sh', 'review.sh'):
            source = (scripts / name).read_text()
            self.assertIn('temporary-directory.py', source)
            self.assertNotIn('mktemp -d "$root/evidence/', source)
            self.assertLess(source.index('export TMPDIR='), source.index('sdk=$('))

    def test_private_root_and_unique_paths(self):
        module = allocator()
        root = module.temporary_root()
        self.assertEqual(root, scripts.parent.parent / '.tmp')
        self.assertEqual(stat.S_IMODE(root.lstat().st_mode), 0o700)
        with tempfile.TemporaryDirectory(prefix='spike-temp-test-', dir=root) as directory:
            project = Path(directory)
            first = module.allocate('spike-run', project)
            second = module.allocate('spike-run', project)
            self.assertNotEqual(first, second)
            self.assertEqual(first.parent, project / '.tmp')
            self.assertEqual(stat.S_IMODE(first.lstat().st_mode), 0o700)

    def test_unsafe_roots_fail_without_fallback(self):
        module = allocator()
        with tempfile.TemporaryDirectory(prefix='spike-temp-test-', dir=module.temporary_root()) as directory:
            project = Path(directory)
            root = project / '.tmp'
            outside = project / 'outside'
            outside.mkdir()
            root.symlink_to(outside, target_is_directory=True)
            with self.assertRaises(ValueError):
                module.allocate('spike-run', project)
            self.assertEqual(list(outside.iterdir()), [])
            root.unlink()
            root.write_text('not a directory')
            with self.assertRaises(ValueError):
                module.allocate('spike-run', project)
            self.assertEqual(root.read_text(), 'not a directory')
            root.unlink()
            root.mkdir(mode=0o755)
            root.chmod(0o755)
            with self.assertRaises(ValueError):
                module.allocate('spike-run', project)

    def test_invalid_prefixes_fail(self):
        module = allocator()
        for prefix in ('', '..', '../escape', '/escape', 'a/b', 'a\\b', 'a\n'):
            with self.assertRaises(ValueError):
                module.allocate(prefix)


def allocator():
    spec = importlib.util.spec_from_file_location('temporary_directory', scripts / 'temporary-directory.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


if __name__ == '__main__':
    unittest.main()
