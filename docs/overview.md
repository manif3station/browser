# browser overview

## Purpose

`browser` is a Developer Dashboard skill that exposes Playwright-backed browser work through skill CLI commands. It gives DD users a reusable way to drive a browser session from `dashboard browser.get`, `dashboard browser.post`, `dashboard browser.png`, and `dashboard browser.search` without dropping into ad-hoc scripts first, plus `dashboard browser.skills` to print the skill's own agent-facing manual.

## Value

This skill brings browser automation into the DD skill system so a user can:

- fetch and inspect a page through a real browser session
- capture a rendered page screenshot to a predictable PNG path
- capture the rendered HTML body of that page from the CLI
- capture readable page text and detect obvious CAPTCHA or bot-check pages
- temporarily hand control to the user in a visible browser session when login or CAPTCHA completion is required
- optionally inject jQuery into the page context for jQuery-style extraction scripts
- run a small Playwright JavaScript snippet against the page DOM
- run a Playwright-driven multi-page journey from one starting URL through controller-mode scripts
- issue a POST request through Playwright and inspect the returned page content
- run a structured web search across an ordered list of engines, automatically skipping any engine that comes back CAPTCHA-walled
- keep that automation isolated inside an installable DD skill

## Delivery

The skill ships:

- `cli/get` and `cli/post` command entrypoints
- `cli/png` screenshot entrypoint
- `cli/search` search entrypoint
- `cli/skills` entrypoint that prints `SKILLS.md`, a condensed agent-facing manual
- `lib/Browser/CLI.pm` for CLI parsing and output
- `lib/Browser/Runner.pm` for Playwright execution orchestration, with `lib/Browser/Runner/NodeRuntime.pm` (Node dependency install) and `lib/Browser/Runner/BrowserPath.pm` (browser binary discovery/validation) split out as focused modules
- `lib/Browser/Search.pm` for the multi-engine fallback strategy and per-engine result parsing
- dependency files for DD skill installation on Debian-family and macOS hosts
- a `package.json` file for DD-managed Node dependency installation into `$HOME`
- browser-binary validation so broken wrapper paths are not handed to Playwright
- skill-local tests, docs, ticket records, versioning, and changelog files
