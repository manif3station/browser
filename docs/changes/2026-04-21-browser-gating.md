# browser gating

## Summary

Created the first gated version of the `browser` skill.

## Included

- isolated skill repository layout
- Playwright dependency files for DD skill installation
- `package.json` for DD-managed Node dependency installation
- `browser.get` and `browser.post` CLI commands
- runtime bootstrap aligned to DD's `npm install --prefix "$HOME" <skill-root>` behavior
- `browser.get` now returns the rendered HTML body alongside the page metadata
- browser responses now include `content_type`, `body_text`, and `is_captcha`
- `browser.get` now supports `--ask` and `--askme` for visible interactive takeover before payload capture
- browser scripts can opt into injected jQuery through `--jquery`
- Docker-based test and coverage gate
- skill-local README, docs, changelog, and ticket records
