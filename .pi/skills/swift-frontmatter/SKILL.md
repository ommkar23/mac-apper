---
name: swift-frontmatter
description: Write, review, replace, or remove concise frontmatter for project Swift files. Use when asked to document a Swift file's purpose or manage its frontmatter.
---

# Swift frontmatter

- Read the target file first. Describe **only what its code does**, not related files. Keep the brief short and human-reviewable; do not repeat its path.
- Use `get_frontmatter` with the project-relative `path` to inspect the current brief.
- Use `add_frontmatter` with `path` and `content` to create **or replace** it. Supply `content` as Swift line comments (`// ...`); the tool inserts it verbatim between the markers.
- Use `remove_frontmatter` with `path` to delete only the marked brief.
- These tools operate on existing project Swift files. Do not edit the markers by hand.
