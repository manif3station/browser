# browser overview

## Purpose

`browser` is a Developer Dashboard skill that exposes Playwright-backed browser work through skill CLI commands. It gives DD users a reusable way to drive a browser session from `dashboard browser.get` and `dashboard browser.post` without dropping into ad-hoc scripts first.

## Value

This skill brings browser automation into the DD skill system so a user can:

- fetch and inspect a page through a real browser session
- run a small Playwright JavaScript snippet against the page DOM
- issue a POST request through Playwright and inspect the returned page content
- keep that automation isolated inside an installable DD skill

## Delivery

The skill ships:

- `cli/get` and `cli/post` command entrypoints
- `lib/Browser/CLI.pm` for CLI parsing and output
- `lib/Browser/Runner.pm` for Playwright execution
- dependency files for DD skill installation on Debian-family and macOS hosts
- a skill-local Node runtime bootstrap path under `local/playwright-node/`
- skill-local tests, docs, ticket records, versioning, and changelog files
