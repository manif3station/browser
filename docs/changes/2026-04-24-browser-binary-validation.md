# browser binary validation

## Summary

Harden Playwright browser discovery so broken launcher wrappers are not passed through as `executablePath`.

## Included

- relative PATH hits such as `bin/chrome` are rejected
- configured browser binaries are validated before use
- broken wrapper scripts are ignored instead of crashing the browser command at launch
- common macOS app bundle browser locations remain part of the candidate set
