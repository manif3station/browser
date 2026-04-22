# browser node runtime repair

## Summary

Repair the `browser` skill runtime bootstrap so stale Node module trees do not break Playwright startup.

## Included

- staged `npx` package installs aligned with the latest DD package.json pattern
- cleanup of affected installed module directories before copying fresh runtime dependencies into `$HOME/node_modules`
- CommonJS-safe `uuid` dependency pinning for the Perl Playwright server path
- automatic Chromium or Chrome binary discovery from `PATH`
- verification against Docker, direct host execution, and the latest DD source checkout
