import { mkdirSync, lstatSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Disposable fixture storage only. Never removes the shared root or follows a root link.
export function projectTempRoot() {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..', '.tmp');
  try { mkdirSync(root, { mode: 0o700 }); }
  catch (error) { if (error.code !== 'EEXIST') throw error; }
  const info = lstatSync(root);
  if (!info.isDirectory() || info.isSymbolicLink() || info.uid !== process.getuid() || (info.mode & 0o077) !== 0) {
    throw new Error('Repository .tmp must be private, owner-owned and nonlinked');
  }
  return root;
}
