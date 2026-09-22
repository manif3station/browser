# browser — agent manual

This is the condensed, agent-facing reference for the `browser` Developer
Dashboard skill. For narrative background see `README.md`; for worked
examples see `docs/usage.md`; for ticket-level status, see this project's
Tira board, not markdown files in `tickets/`.

## Commands

```
dashboard browser.get <url> [OPTIONS]
dashboard browser.post <url> [OPTIONS]
dashboard browser.png <url> [OPTIONS]
dashboard browser.pdf <url> [OPTIONS]
dashboard browser.search <query> [OPTIONS]
dashboard browser.skills
```

`--help` works on all five of `get`/`post`/`png`/`pdf`/`search` - it always
short-circuits to printing usage and exiting 0, before any other
validation, even combined with other flags or with no URL/query given.
`--version` works the same way (D2B-124), printing the installed skill's
version from `.env` and exiting 0 - `--help` wins if both are given.
`browser.skills` prints this file verbatim.

`browser.pdf` (D2B-196) captures a full-page PDF via Playwright's
Chromium DevTools `printToPDF` - Chromium-based browsers only
(`chrome`/`chromium`/`edge`); `--browser firefox`/`webkit` is refused
with a clear error before a browser is ever launched, since Playwright's
PDF export has no Firefox/WebKit support. Like `browser.png`, it prints
just the destination file path to stdout (not a JSON payload), appends
`.pdf` when `--file` omits it, and refuses with a clear error when
`--file` names an existing directory. The page is measured under
`screen` media (forced explicitly, since `pdf()` otherwise renders under
`print` media) and sized to exactly that measurement instead of
Playwright's default paginated US-Letter output; the measurement must
resolve to a `{width, height}` object with positive numeric values no
greater than 19200px (~200in at 96dpi) - a missing, non-numeric, zero,
negative, oversized, or otherwise malformed measurement is refused with
a clear error before `pdf()` runs.

## Flags (browser.get/post/png/pdf)

- `--script TEXT` — JS `page.evaluate()` call, or (with `--playwright`/
  `--agent`/`--flow`) a Perl controller script with `$page`/`$browser`/
  `$playwright` in scope. An explicit empty string is refused with
  "--script must not be empty" in both plain and controller mode
  (D2B-158) - omitting `--script` entirely remains a silent no-op in
  plain JS mode, but in controller mode is refused the same way with
  "Controller mode requires --script" (D2B-184).
- `--jquery` — inject jQuery before running `--script`.
- `--playwright` / `--agent` / `--flow` — all three are aliases enabling
  Perl controller mode for `--script`.
- `--data TEXT` — POST body. Refused on GET/PNG. Sent raw; this skill
  never explicitly sets a Content-Type header, and there is no --header
  flag to set one yourself (D2B-137). Passing `--data --help`/`--data
  --version` as two separate arguments is misinterpreted as a
  help/version request instead of sent as the literal body - the
  equals-form (`--data=--help`) is unaffected (D2B-138). This applies to
  every string-valued flag, wherever supported across the four commands,
  not just --data: --help/--version
  passed as a flag's separate-token value (e.g. `--script --help`,
  `--browser --version`) is misinterpreted the same way, since the whole
  argument list is scanned before any flag value is parsed - only the
  equals-form (`--flag=--help`) is safe for any flag (D2B-140).
- `--browser NAME` — `chrome` (default), `chromium`, `firefox`, `webkit`,
  `edge` (case-insensitive, e.g. `Chrome`/`WEBKIT` are accepted the same as
  the matching lowercase form, D2B-185). Only `chrome`/`chromium` read
  `CHROMIUM_BIN`/PATH auto-detection; firefox/webkit always launch
  Playwright's own bundled binary. `edge` launches Microsoft Edge via
  Playwright's `channel: 'msedge'` option (Edge shares Chromium's engine,
  so it never gets `CHROMIUM_BIN`/`executablePath` treatment - D2B-192).
- `--headless` / `--no-headless` — default headless=1. `--ask`/`--askme`
  unconditionally force headless off, overriding an explicit `--headless`.
- `--ask` / `--askme` — visible browser, waits for a real keypress on
  stdin before continuing. Refuses with "stdin is not interactive" if
  stdin is already at EOF. No timeout on the initial navigation unless
  `--timeout-ms` is also given.
- `--wait-until MODE` — `load`, `domcontentloaded`, `networkidle`.
  Refused on POST.
- `--timeout-ms N` — refused with "must not be negative" if negative;
  refused entirely on POST. `0` is accepted and passed through to
  Playwright, which conventionally disables the navigation timeout
  entirely - it does not mean "instant" and can genuinely hang, the
  same caveat browser.search documents below.
- `--file PATH` — PNG-only screenshot destination; refused on GET/POST.

## Flags (browser.search)

- `--engine NAME` / `--engines LIST` — mutually exclusive. Names must be
  `bing`, `google`, or `duckduckgo` (case-insensitive); both `--engine`'s
  single name and each `--engines` comma-separated segment are trimmed of
  leading/trailing whitespace (including a raw-UTF-8-byte non-breaking
  space, D2B-127) - whitespace *inside* a name (e.g. `b ing`) is not
  tolerated and is rejected as an unknown engine. Empty segments are
  dropped; names dedupe preserving first-occurrence order.
- `--max N` — default 10; refused if negative.
- `--timeout-ms N` — per-engine request timeout, default 10s; refused if
  negative. `0` is accepted and passed through to Playwright, which
  conventionally disables the navigation timeout entirely - it does not
  mean "instant" and can genuinely hang.

Falls through to the next configured engine on either a CAPTCHA wall or a
timeout/exception on the current engine; returns the first engine that
succeeds. If every engine is walled, fails with a structured error naming
each one, with a default 10s per-engine bound - see the `--timeout-ms 0`
caveat above for the one way this can still hang.

## Result payload shape

GET/POST: `requested_url`, `final_url`, `method`, `status`, `title` (GET
only), `content_type`, `headers` (full response header map, D2B-114),
`body`, `body_text`, `is_captcha`, `script_result` (if `--script` given).
PNG/PDF: `requested_url`, `final_url`, `method`,
`status`, `title`, `content_type`, `headers` (full response header map,
D2B-115), `file`, `script_result` (if `--script` given, D2B-131 /
D2B-196). Search:
`query`, `engine_used`,
`engines_tried`, `results` (each with `rank`, `title`, `url`, `snippet`).

## Prerequisites

- Node.js v20+ is required (matches Playwright's own declared minimum).
  `browser.get`/`browser.post`/`browser.png`/`browser.pdf`/`browser.search` all check
  the system's `node` binary version before loading Playwright, and fail
  fast with "Node.js v20+ is required (Playwright's own declared
  minimum) - found vN. Please upgrade Node.js." if it's older - this is
  not something to work around, the real fix is upgrading Node.
  `--help` and `browser.skills` never call Playwright at all, so they
  work regardless of the installed Node version.

## Known, disclosed limitations (not bugs)

- `browser.post`'s `final_url` cannot distinguish "never navigated" from
  "a script/response/user deliberately navigated back to literally
  `about:blank`" - both report the response's real URL in that rare case.
- CAPTCHA detection requires a real, unescaped `class`/`src`/`action`
  attribute match or a title match - not full markup validation, so an
  unrelated compound class name or a matching phrase inside an HTML
  comment can still false-positive.
- A POST response body is only ever trusted and returned unwrapped when
  its content type is exactly (ignoring parameters like `; charset=...`,
  surrounding ASCII HTML whitespace, and case) `text/html`/`application/xhtml+xml`
  or it starts with a properly-bounded doctype/`<html>` tag - anything else
  (including a genuinely well-formed but undeclared HTML fragment) is
  always HTML-escaped and wrapped in a `<pre>` block first.
- A URL/query argument beginning with a literal `-` is misparsed as an
  unknown option on `get`/`post`/`png`/`search` alike - pass it after a
  literal `--` separator (e.g. `dashboard browser.get -- -example.com`) to
  have it treated as the positional argument instead. This escape is itself
  honored even when the escaped value is literally `--help` or `--version`
  (e.g. `dashboard browser.get -- --version` treats `--version` as the
  literal URL, not a version request) - the help/version short-circuit
  respects a preceding `--` the same way `Getopt::Long` itself does
  (D2B-186).
- `browser.png`/`browser.pdf`'s `--file` is refused with a clear error
  naming the path when it resolves to an existing directory (e.g. one
  literally named `shot.png`), instead of reaching Playwright's
  screenshot()/pdf() call.
- `browser.pdf` only supports Chromium-based browsers - `--browser
  firefox`/`webkit` is refused with a clear error before a browser is
  ever launched (Playwright's PDF export has no support for either).

## Layout

- `cli/get`, `cli/post`, `cli/png`, `cli/pdf`, `cli/search`, `cli/skills`
  — thin entrypoint scripts.
- `lib/Browser/CLI.pm` — argument parsing and JSON/usage output.
- `lib/Browser/Runner.pm` — Playwright execution (GET/POST, controller
  mode, CAPTCHA detection, response-document trust boundary).
- `lib/Browser/Runner/Capture.pm` — PNG/PDF full-page file-output capture
  (screenshot()/pdf()), extracted from Runner.pm (D2B-196). `run_png` and
  `run_pdf` are both thin callers of a shared internal `_capture` helper
  that owns path reservation, the directory guard, cleanup-on-failure,
  and result-hashref assembly (D2B-197).
- `lib/Browser/Runner/NodeRuntime.pm` — Node dependency install, version
  satisfaction, the shared install lock, and the minimum-Node-version
  check.
- `lib/Browser/Runner/VersionCompare.pm` — semver-subset comparison
  (exact/`*`/`latest`/caret-range specs), extracted from
  NodeRuntime.pm (D2B-155).
- `lib/Browser/Runner/BrowserPath.pm` — browser binary discovery/
  validation and Playwright launch options.
- `lib/Browser/Search.pm` — multi-engine fallback and per-engine result
  parsing.

## Delivery process

Every change flows through the project's Tira board (SOW → EPIC → Ticket
→ TDD → Codex review → 100% coverage on touched `lib/` modules →
perlsec audit → owner review → push → install → done). Never bypass this
to hand-edit shipped code without a ticket.
