# browser gating

## Summary

Created the first gated version of the `browser` skill.

## Included

- isolated skill repository layout
- Playwright dependency files for DD skill installation
- `package.json` for DD-managed Node dependency installation
- `browser.get` and `browser.post` CLI commands
- runtime bootstrap aligned to DD's `npm install --prefix "$HOME" <skill-root>` behavior
- Docker-based test and coverage gate
- skill-local README, docs, changelog, and ticket records
