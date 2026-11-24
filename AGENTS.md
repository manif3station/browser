# Repository Guidelines

## Project Structure

Perl command entrypoints are in `cli/`; reusable code lives in `lib/Browser/`. The persistent Playwright worker is `libexec/persistent-browser.js`. Tests are in `t/`, fixtures in `t/fixtures/`, and user and agent documentation in `README.md`, `docs/`, and `SKILLS.md`.

## Development and Tests

Run commands from this directory. `prove -lr t` runs the full Perl test suite; run focused tests first, such as `prove -v t/253-current-tabs.t`. `perl cli/get https://example.com` exercises a local GET. Node-based browser checks require Node 20 or later and a usable Playwright browser; report skipped integration tests and why.

## Style

Follow surrounding Perl style: four-space indentation, `Browser::*` package names, and descriptive snake_case subroutines. Keep CLI behavior and JSON output documented in `SKILLS.md`. Add focused regression coverage with numbered test filenames (for example, `t/253-current-tabs.t`) and update user-facing docs when behavior changes.

## Required Delivery

For browser behavior changes, update `SKILLS.md`, bump `.env` and `package.json` versions together, add and run focused and full tests, commit, push, install with `d2 skill install browser`, then verify the installed command. Report actual test totals and skipped checks.

## Commit Message Format

Use a short completion-style subject followed by a blank line and concise bullets covering the behavior, documentation/version changes, tests, push/install, and live verification. Example:

```text
Completed the full delivery sequence.

- Added the behavior and documented how to use it.
- Updated the skill version and regression coverage.
- Tests passed; note any skipped integration checks and why.
- Pushed, installed, and verified the installed command.
```
