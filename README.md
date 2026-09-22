# browser

## Description

`browser` is a Developer Dashboard skill that exposes Playwright-backed browser work through skill CLI commands. It lets DD users fetch pages, inspect the DOM with JavaScript, inject jQuery for page-side extraction, or run Perl controller scripts for real browser journeys.

## Value

The skill gives a DD user one installable tool for:

- reading browser-rendered HTML from the CLI
- extracting values from the current page with JavaScript
- using jQuery-style selectors without requiring the target page to ship jQuery
- automating clicks, fills, navigation, and multi-page flows with Perl controller scripts
- pausing for manual CAPTCHA or login work and then continuing
- running a structured web search that automatically skips past any CAPTCHA-walled engine instead of hand-picking one

## Problem It Solves

Without a shared browser skill, quick browser tasks usually fragment into shell snippets, one-off Node scripts, and ad hoc Playwright experiments. That makes them hard to share, hard to rerun, and hard to align with the DD skill system.

## What It Does To Solve It

`browser` provides:

- `dashboard browser.get <url>`
- `dashboard browser.post <url>`
- `dashboard browser.png <url>`
- `dashboard browser.pdf <url>`
- `dashboard browser.search <query>`
- JavaScript page-context scripting through `--script`
- Perl controller scripting through `--playwright`, `--agent`, or `--flow`
- jQuery injection through `--jquery`
- interactive visible-browser takeover through `--ask` and `--askme`
- HTML body, text body, status, final URL, and CAPTCHA detection in the output payload
- screenshot capture with a printed PNG file path
- full-page PDF capture with a printed PDF file path (Chromium-based browsers only, D2B-196)
- structured, ranked web search results with automatic CAPTCHA-triggered engine fallback

## Developer Dashboard Feature Added

This skill adds:

- the dotted command `dashboard browser.get`
- the dotted command `dashboard browser.post`
- the dotted command `dashboard browser.png`
- the dotted command `dashboard browser.pdf`
- the dotted command `dashboard browser.search`
- the dotted command `dashboard browser.skills`
- a DD skill example that depends on `aptfile`, `brewfile`, `cpanfile`, and `package.json`

## Layout

- `cli/get` GET entrypoint
- `cli/post` POST entrypoint
- `cli/png` screenshot entrypoint
- `cli/pdf` PDF entrypoint
- `cli/search` search entrypoint
- `cli/skills` browser.skills agent-manual entrypoint
- `lib/Browser/CLI.pm` CLI parsing and JSON output
- `lib/Browser/Runner.pm` Playwright execution orchestration (GET/POST, controller mode)
- `lib/Browser/Runner/Capture.pm` PNG/PDF full-page file-output capture, extracted from Runner.pm (D2B-196); `run_png`/`run_pdf` are both thin callers of a shared internal `_capture` helper (path reservation, directory guard, cleanup-on-failure, result-assembly) that owns everything except each format's own write callback (screenshot() for PNG; emulateMedia/evaluate/dimension-validation/pdf() for PDF) (D2B-197)
- `lib/Browser/Runner/NodeRuntime.pm` Node dependency version-satisfaction, the shared install lock, and the runtime stamp file
- `lib/Browser/Runner/NodeRuntime/Install.pm` the npm-install workspace cluster (`install_node_runtime`, current-dependency-tree replacement before a staged install, the portable recursive copy), extracted from NodeRuntime.pm to keep it under the 500-line guideline (D2B-198)
- `lib/Browser/Runner/VersionCompare.pm` semver-subset comparison (exact/`*`/`latest`/caret-range specs), extracted from NodeRuntime.pm (D2B-155)
- `lib/Browser/Runner/BrowserPath.pm` browser binary discovery/validation and Playwright launch options
- `lib/Browser/Search.pm` multi-engine search fallback strategy and per-engine result parsing
- `aptfile`, `brewfile`, `package.json`, and `cpanfile` dependency declarations
- `t/` tests
- `docs/` skill docs
- `.env` version metadata
- `Changes` changelog

## Installation

Install the skill into Developer Dashboard by repo name:

```bash
dashboard skills install browser
```

The skill's own home-root lookup (used to locate this `node_modules` tree and the jQuery runtime, not any literal `$HOME`-prefixed command below) falls back to `$ENV{USERPROFILE}` when `$ENV{HOME}` is unset (D2B-199) - Windows never sets `HOME` itself, only `USERPROFILE`, and a bare `$ENV{HOME} || die` died on every Windows invocation regardless of browser until this fallback was added; `HOME` still wins whenever both are set, on every platform.

Developer Dashboard installs the skill's `package.json` runtime into `$HOME` using the DD Node dependency path (`NODE_PATH` is joined with the platform's own path-list separator - `:` on Unix, `;` on Windows - never a hardcoded one). The stale-check-and-install sequence for that shared `$HOME/node_modules` tree holds an exclusive file lock for its whole duration, so two concurrent `browser.get`/`browser.post`/`browser.png` invocations that both find the runtime stale cannot race each other's clear-and-copy and corrupt the shared tree - the second invocation simply waits for the first to finish. The skill also verifies that installed module versions still satisfy `package.json`, and if they do not, it stages a fresh `npx --yes npm install ...` under the DD cache and replaces the stale module trees before launching Playwright. Only module directories still named in the current `package.json` are cleared this way - a directory left over from a dependency later removed from `package.json` is deliberately left untouched, since `$HOME/node_modules` is the user's real home directory, not one this skill exclusively owns, so clearing anything not explicitly still-expected risks destroying an unrelated `node_modules` tree kept there for something else entirely (D2B-128, investigated and accepted as a known limitation rather than fixed). A `^0.y.z` dependency spec follows npm's own caret rules for pre-1.0 versions: `^0.0.z` only ever matches that exact patch version, and `^0.y.z` (y>0) matches any patch within that same minor version - neither accepts a different minor or major version the way a `^1.y.z` spec would. The skill's own `package.json` is read from disk and JSON-decoded at most once per stale-runtime check (cached by path+mtime), rather than separately for the fingerprint, the install spec list, and the installed-version comparison.

Before launch, the skill also validates any configured or discovered browser binary path. Relative PATH hits such as `bin/chrome` are rejected, and unusable wrapper scripts are ignored instead of being passed through to Playwright as `executablePath`. PATH auto-detection splits on the platform's own path-list separator and, on Windows, also tries a `.exe` suffix when the bare command name isn't found. After PATH lookup, the skill also checks standard install locations directly: on Windows, Program Files, Program Files (x86), and LOCALAPPDATA (D2B-126); on any other platform (in practice, macOS), `/Applications` and the user's own `~/Applications` - since Chrome/Chromium's own installers don't reliably add themselves to PATH on either platform. These direct-location paths are harmless no-ops on a platform they don't apply to (e.g. the macOS paths on Linux just fail the same absolute-path/launchability check every candidate goes through). PATH hits are still tried first, so the direct-location checks only end up mattering when PATH lookup didn't already find a usable binary. This `CHROMIUM_BIN`/auto-detected path is only ever applied for `--browser chrome` (the default) or `--browser chromium` - requesting `--browser firefox` or `--browser webkit` always launches Playwright's own bundled firefox/webkit binary and never inherits a configured Chromium path. `--browser edge` launches Microsoft Edge via Playwright's `channel: 'msedge'` option instead of an `executablePath` - Edge shares Chromium's engine but is resolved by Playwright's own installed-channel lookup, not by this skill's `CHROMIUM_BIN`/PATH auto-detection (D2B-192).

For direct local development outside DD, you can preinstall the Node-side runtime with:

```bash
npm install --prefix "$HOME" .
```

## License

`browser` is released under the MIT License.

See [LICENSE](LICENSE).

## CLI Usage

Installed DD usage:

```bash
dashboard browser.get https://example.com
dashboard browser.get https://example.com --script 'return document.title'
dashboard browser.get https://example.com --jquery --script 'return $("h1").first().text()'
dashboard browser.png https://example.com
dashboard browser.png https://example.com --file /tmp/example-shot
dashboard browser.get https://example.com/login --ask --timeout-ms 120000
dashboard browser.get https://example.com/start --flow --script 'my $response = $page->goto("https://example.com/final", { waitUntil => "networkidle" }); return { title => $page->title(), url => $page->url(), status => $response->status() };'
dashboard browser.post https://example.com/form --data 'name=dashboard'
dashboard browser.get https://example.com --no-headless
dashboard browser.get --help
```

`--help` prints usage text and exits 0 for any of `browser.get`/`browser.post`/`browser.png`/`browser.search`, taking priority over every other flag or validation - it works even with no URL/query given, and even combined with other flags. `browser.skills` prints this skill's `SKILLS.md` agent manual.

`--data` is refused on `browser.get`/`browser.png` - only `browser.post` reads it. Likewise, `--wait-until`/`--timeout-ms` are refused on `browser.post` - `browser.get`/`browser.png` read them, and `browser.search` also reads `--timeout-ms` (bounding each engine attempt, default 10 seconds). `--file` is refused on `browser.get`/`browser.post` - only `browser.png` reads it.

`--data` is sent as the raw POST body - this skill never explicitly sets a `Content-Type` header for it, and there is no `--header` flag to set one yourself. A server that relies on `Content-Type` to parse the body (e.g. expecting `application/x-www-form-urlencoded` for form-style data like `--data 'name=dashboard'`) may not interpret it as intended; confirm the target server accepts the body this skill actually sends before relying on `--data` for that use case (D2B-137). Passing `--data --help` or `--data --version` as two separate arguments (not `--data='--help'`/`--data='--version'` as one combined argument) is misinterpreted as a help/version request instead of sending `--help`/`--version` as the literal POST body - `--help`/`--version` are detected by scanning the whole argument list for a standalone matching element before any flag value is parsed, so the equals-form (`--data=--help`) is unaffected (D2B-138). This is not specific to `--data`: the same whole-argument-list scan runs before any flag's value is parsed, so passing `--help`/`--version` as the separate-token value of every string-valued flag, wherever supported across the four commands (`--script`, `--browser`, `--wait-until`, `--file`, `--engine`, `--engines`, and `--data` itself), is misinterpreted the same way - only the equals-form (`--flag=--help`) is safe (D2B-140).

`browser.get`/`browser.post`/`browser.png` all run headless by default; pass `--headless`/`--no-headless` to set it explicitly, useful for debugging what a run is actually doing without using `--ask`'s interactive pause-and-confirm flow. `--ask`/`--askme` unconditionally force headless off for their interactive mode, overriding an explicit `--headless` - `--headless`/`--no-headless` only has an effect on a non-interactive run.

Direct local development:

```bash
perl cli/get https://example.com
perl cli/post https://example.com/form --data 'name=dashboard'
perl cli/png https://example.com --file /tmp/example-shot
perl cli/search 'which mini PC can run a ~30B Qwen3 at 1M context'
```

## Search Usage

`browser.search <query>` returns structured, ranked results (`rank`, `title`, `url`, `snippet`) from an ordered list of search engines, defaulting to bing, google, duckduckgo in that order.

```bash
dashboard browser.search 'which mini PC can run a ~30B Qwen3 at 1M context'
```

If an engine's response looks CAPTCHA/bot-walled (the same `is_captcha` check `browser.get` already reports), the skill transparently tries the next engine instead of stopping. The response payload names which engine actually served the results (`engine_used`) and every engine that was tried (`engines_tried`). Results are not deduplicated by URL - two entries sharing the same URL (e.g. an ad plus its matching organic result on the source page) are both kept as separate results, each still consuming its own `--max` slot (D2B-175).

Override the engine order or limit the query to a single engine:

```bash
dashboard browser.search 'query' --engine google
dashboard browser.search 'query' --engines duckduckgo,bing
```

Cap the number of results:

```bash
dashboard browser.search 'query' --max 5
```

Each engine attempt is bounded by `--timeout-ms` (default 10000, i.e. 10 seconds), so a slow or unresponsive engine fails fast and moves on to the next one instead of stacking multiple long waits:

```bash
dashboard browser.search 'query' --timeout-ms 5000
```

If every engine in the list comes back walled, the command fails with a structured error naming each walled engine and pointing to `browser.get --ask` for interactive use - the bounded per-engine timeout means it never hangs waiting for a response that will not come.

## Screenshot Usage

`browser.png` captures a rendered page screenshot and prints the saved PNG path to stdout.

If `--file` is provided without a `.png` suffix, the skill appends `.png` for the user:

```bash
dashboard browser.png https://example.com --file /tmp/example-shot
```

Output:

```text
/tmp/example-shot.png
```

If `--file` already ends in `.png`, the skill keeps that filename unchanged:

```bash
dashboard browser.png https://example.com --file /tmp/example-shot.png
```

If `--file` is omitted, the skill writes to a random tmp path and prints it:

```bash
dashboard browser.png https://example.com
```

Example output:

```text
/tmp/browser-g7Zegnat6TicyRMS.png
```

## PDF Usage

`browser.pdf` (D2B-196) captures a full-page PDF via Playwright's Chromium DevTools `printToPDF` and prints the saved path to stdout, mirroring `browser.png`'s `--file` conventions exactly (appends `.pdf` when omitted, keeps an existing `.pdf` suffix unchanged, writes to a random tmp path when `--file` is omitted entirely):

```bash
dashboard browser.pdf https://example.com --file /tmp/example-report
```

Output:

```text
/tmp/example-report.pdf
```

PDF export is a Chromium-only Playwright capability - `--browser firefox`/`webkit` is refused with a clear error before a browser is even launched, since neither supports `page->pdf()` at all:

```bash
dashboard browser.pdf https://example.com --browser firefox
```

```text
browser.pdf only supports Chromium-based browsers (chrome, chromium, edge) - Playwright's PDF export has no Firefox/WebKit support
```

`browser.pdf` measures the page's rendered `scrollWidth`/`scrollHeight` under `screen` media (forced explicitly, since Chromium's PDF export otherwise renders under `print` media by default) and sizes the PDF to exactly that, so the output is one continuous page rather than Playwright's default paginated US-Letter output. The measurement must resolve to a `{width, height}` object with positive numeric values no greater than 19200px (roughly 200in at 96dpi, Chromium's practical PDF page-size limit) - a missing, non-numeric, zero, negative, oversized, or otherwise malformed measurement is refused with a clear error before `pdf()` is ever called.

## Mode Selection

Use JavaScript mode when:

- you only need to inspect the current page
- you want to extract text, attributes, links, headings, JSON blobs, or table rows
- you want to use `--jquery`
- you do not need to click, fill, navigate, or continue through a journey

Use Perl controller mode when:

- you need to click something
- you need to fill a form
- you need to navigate to another page
- you need to handle a login flow
- you need a sequence of actions across one or more pages
- you want `--ask` and then scripted continuation

Use `--jquery` when:

- you are in JavaScript mode
- you want jQuery-style page extraction helpers like `window.jQuery(...)`
- the target page does not already provide jQuery

Do not use `--jquery` for Perl logic:

- `--jquery` injects jQuery into the page
- Perl controller scripts run outside the page
- if a Perl controller script needs jQuery-powered extraction, call `$page->evaluate(...)` and use `window.jQuery(...)` inside that JavaScript

`browser.png`/`browser.pdf` also run `--script`/`--jquery` before taking their screenshot/PDF (D2B-131, D2B-196), so a script can dismiss a cookie banner or scroll to an element first - the script's return value appears in the result's `script_result` field, matching `browser.get`/`browser.post`, at the Perl API level (`Browser::Runner->request()`'s return value). This parity does not extend to either command's own CLI stdout, though: `dashboard browser.png`/`dashboard browser.pdf` only ever print the saved file's path, unlike `browser.get`/`browser.post`'s CLI output, which prints the full JSON result including `script_result` (D2B-136). A failing script (or a missing jQuery runtime with `--jquery`) makes `browser.png`/`browser.pdf` fail too, exactly like `browser.get`/`browser.post` already do - neither is immune to script errors the way an old silent no-op once was.

## Script Types

Default `--script` mode is JavaScript:

```bash
dashboard browser.get https://example.com --script 'return document.title'
```

Controller mode changes `--script` into Perl:

```bash
dashboard browser.get https://example.com/login --playwright --script '
my $button = $page->select(q{button[type="submit"]});
$button->click();
return { url => $page->url(), title => $page->title() };
'
```

Controller-mode aliases are equivalent:

- `--playwright`
- `--agent`
- `--flow`

## Verified Examples

The examples below are the ones I am prepared to stand behind. They were verified either:

- against the deterministic browser fixture used in the automated test suite
- or against live public pages that returned working JSON from the skill in the current verification environment

The rule for this skill is to prove, fix, and document examples in their working form rather than leave optimistic templates behind.

### Verified Core Examples

1. Read the title from `example.com`.

```bash
dashboard browser.get https://example.com --script 'return document.title'
```

2. Read the first heading from `example.com`.

```bash
dashboard browser.get https://example.com --script 'return document.querySelector("h1")?.textContent?.trim() || null'
```

3. Read all links from `example.com`.

```bash
dashboard browser.get https://example.com --script 'return Array.from(document.querySelectorAll("a")).map(a => a.href)'
```

4. Read the page location object from `example.com`.

```bash
dashboard browser.get https://example.com --script 'return { href: location.href, host: location.host, path: location.pathname }'
```

5. Use jQuery to read the first heading from `example.com`.

```bash
dashboard browser.get https://example.com --jquery --script 'return window.jQuery("h1").first().text()'
```

6. Use Perl controller mode to read the current page URL and title.

```bash
dashboard browser.get https://example.com --playwright --script '
return { url => $page->url(), title => $page->title() };
'
```

7. Use Perl controller mode to jump from `example.com` to the IANA page.

```bash
dashboard browser.get https://example.com --flow --script '
my $response = $page->goto("https://www.iana.org/domains/example", { waitUntil => "load" });
return { url => $page->url(), status => $response->status(), title => $page->title() };
'
```

### Verified Amazon Examples

These verified Amazon examples start on search result URLs directly and use `--wait-until load`. In the current verification environment, starting from the Amazon homepage with the default `networkidle` wait is not reliable enough to document as a proven example.

8. Read the title from an Amazon search results page.

```bash
dashboard browser.get 'https://www.amazon.com/s?k=desk+lamp' --wait-until load --script 'return document.title'
```

9. Count the Amazon search results.

```bash
dashboard browser.get 'https://www.amazon.com/s?k=desk+lamp' --wait-until load --script 'return document.querySelectorAll("[data-component-type=\"s-search-result\"]").length'
```

10. Read the first five Amazon result titles.

```bash
dashboard browser.get 'https://www.amazon.com/s?k=desk+lamp' --wait-until load --script 'return Array.from(document.querySelectorAll("[data-component-type=\"s-search-result\"] h2")).slice(0, 5).map(h => h.textContent.trim())'
```

11. Read the first five Amazon result links.

```bash
dashboard browser.get 'https://www.amazon.com/s?k=desk+lamp' --wait-until load --script 'return Array.from(document.querySelectorAll("[data-component-type=\"s-search-result\"] h2 a")).slice(0, 5).map(a => a.href)'
```

12. Read the first five Amazon result prices when present.

```bash
dashboard browser.get 'https://www.amazon.com/s?k=desk+lamp' --wait-until load --script 'return Array.from(document.querySelectorAll("[data-component-type=\"s-search-result\"]")).slice(0, 5).map(node => ({ title: node.querySelector("h2")?.textContent?.trim() || null, price: node.querySelector(".a-price .a-offscreen")?.textContent || null }))'
```

13. Use jQuery to read Amazon result titles.

```bash
dashboard browser.get 'https://www.amazon.com/s?k=desk+lamp' --wait-until load --jquery --script 'return window.jQuery("[data-component-type=\"s-search-result\"] h2").slice(0, 5).map((_, el) => window.jQuery(el).text().trim()).get()'
```

14. Use Perl controller mode on an Amazon search results page.

```bash
dashboard browser.get 'https://www.amazon.com/s?k=desk+lamp' --wait-until load --playwright --script '
return {
  url     => $page->url(),
  title   => $page->title(),
  results => $page->evaluate(q{return document.querySelectorAll("[data-component-type=\"s-search-result\"]").length}),
};
'
```

15. Open the first Amazon search result from a verified search page.

```bash
dashboard browser.get 'https://www.amazon.com/s?k=desk+lamp' --wait-until load --playwright --script '
my $href = $page->evaluate(q{return document.querySelector("[data-component-type=\"s-search-result\"] h2 a")?.href || null});
die "No Amazon search result link found\n" if !$href;
$page->goto($href, { waitUntil => "load" });
return { url => $page->url(), title => $page->title() };
'
```

### Verified X Examples

These X examples were aligned to working live requests from `x.com` in the current verification environment.

16. Read the logged-out X page title.

```bash
dashboard browser.get https://x.com --wait-until load --script 'return document.title'
```

17. Detect whether the logged-out X shell exposes `main`.

```bash
dashboard browser.get https://x.com --wait-until load --script 'return !!document.querySelector("main[role=main], main")'
```

18. Read all preload script URLs from the X shell.

```bash
dashboard browser.get https://x.com --wait-until load --script 'return Array.from(document.querySelectorAll("link[rel=preload][as=\"script\"]")).map(link => link.href)'
```

19. Read whether the X shell references `abs.twimg.com`.

```bash
dashboard browser.get https://x.com --wait-until load --script 'return document.documentElement.innerHTML.includes("abs.twimg.com")'
```

20. Read the visible shell text from X.

```bash
dashboard browser.get https://x.com --wait-until load --script 'return document.querySelector("main")?.innerText || document.body.innerText'
```

21. Use jQuery to read visible links from X.

```bash
dashboard browser.get https://x.com --wait-until load --jquery --script 'return window.jQuery("a[href]").slice(0, 10).map((_, el) => ({ text: window.jQuery(el).text().trim(), href: el.href })).get()'
```

22. Open the X login page with controller mode.

```bash
dashboard browser.get https://x.com --wait-until load --playwright --script '
my $response = $page->goto("https://x.com/login", { waitUntil => "load" });
return { url => $page->url(), status => $response->status(), title => $page->title() };
'
```

23. Jump from X to a public post URL with controller mode.

```bash
dashboard browser.get https://x.com --wait-until load --flow --script '
my $response = $page->goto("https://x.com/jack/status/20", { waitUntil => "load" });
return { url => $page->url(), status => $response->status(), title => $page->title() };
'
```

24. Read the first article on a public X post page.

```bash
dashboard browser.get https://x.com/jack/status/20 --wait-until load --script 'return document.querySelector("article")?.innerText || null'
```

25. Read the `data-testid` values exposed on a public X post page.

```bash
dashboard browser.get https://x.com/jack/status/20 --wait-until load --script 'return Array.from(document.querySelectorAll("[data-testid]")).map(el => el.getAttribute("data-testid")).filter(Boolean)'
```

## Edge Cases

1. If the skill is not installed, DD will not dispatch `browser.get` or `browser.post`.
2. If Playwright or Node dependencies are missing, the command fails until DD installs the skill dependencies.
3. If the target host is unavailable, the Playwright run exits 2.
4. If the page is large, `browser.get` returns a large JSON payload because it includes the rendered HTML body.
5. If the response looks like a challenge page, `is_captcha` is set to true and `body_text` provides a readable summary. Detection requires a real, unescaped opening tag with a `class` attribute containing `g-recaptcha`/`h-captcha` (quoted or unquoted), or a `src`/`action` attribute containing `recaptcha/api`/`hcaptcha.com`, in the page's HTML - not a bare substring match anywhere in the body, so a documentation page showing example widget-integration markup inside a `<pre>` block is not mistaken for a live embed - or a challenge-page title (e.g. "unusual traffic from your computer network", or Cloudflare's own "Just a moment..." interstitial and "Attention Required! | Cloudflare" block-page titles, D2B-173). This is still a substring check within the matched attribute (not exact-value or full markup validation), so an unrelated compound class name containing `g-recaptcha` as a substring, or the same markup appearing inside an HTML comment, can still false-positive - and not any mention of "captcha" in the page's rendered text, so an ordinary page that merely discusses captchas without a real embed or matching title is not flagged.
6. If a POST response is not HTML, the skill always wraps it (HTML-escaped inside a `<pre>` block) so DOM scripts still have a page to inspect, with no risk of embedded markup executing. A body is only ever trusted and returned unwrapped when the response's content type is exactly (ignoring parameters like `; charset=...`) `text/html` or `application/xhtml+xml`, or the body itself starts with a properly-bounded `<!doctype html>`/`<html>` tag - a bare tag-shaped fragment like `<div>...</div>` that lacks an explicit HTML content-type declaration is always escaped/wrapped too (never trusted on its shape alone), since a hand-rolled tag-shape check cannot safely distinguish that from a crafted body smuggling a live `<script>` sibling past it via HTML's own implicit tag-closing rules.
7. If `--ask` or `--askme` is used, the command opens a visible browser and waits for confirmation input before continuing.
8. If `--ask` is used, the initial navigation defaults to `load` with no timeout; add `--timeout-ms` if you want a bounded initial wait.
9. If `--ask` is used on a host without a display server, the headed browser launch can fail until the command runs in a desktop-capable environment.
10. If `--jquery` is used, it only helps page-side JavaScript or `$page->evaluate(...)` calls, not Perl itself.
11. If controller mode is used, write the script in single quotes so the shell does not consume Perl variables like `$page`.
12. If a selector guess is wrong, the controller script can die on `undef`; use defensive selection and inspection patterns first.
13. If a target site keeps long-lived network activity open, avoid forcing `networkidle` where a simple `load` or explicit sleep is enough.
14. If a site needs several intermediate clicks before the real destination appears, inspect controls first rather than guessing the final selector.
15. If the first page after login differs by account state, build the script to detect candidate destinations dynamically.
16. A URL argument is refused as missing when it is undefined, an empty string, or whitespace-only (D2B-156) - a URL that happens to be the single character `0` is accepted and used as-is, not rejected by Perl truthiness.
17. If every engine `browser.search` tries comes back CAPTCHA-walled, the command fails immediately with a structured error naming each walled engine rather than hanging or picking a partial result.
18. `browser.search --engine`/`--engines` only accept the names in the default engine list (`bing`, `google`, `duckduckgo`); an unrecognised name is refused by name rather than silently ignored. Matching is case-insensitive - `--engine Bing` or `--engines DuckDuckGo,BING` resolve the same as their lowercase forms. A repeated name in `--engines` (e.g. `bing,bing`) is deduplicated, preserving the order of first occurrence, so it is never tried twice.
19. `--browser` only accepts `chrome`, `chromium`, `firefox`, `webkit`, or `edge` - an unrecognised value (e.g. a typo) is refused with a clear "Unsupported browser type" error before ever reaching Playwright, instead of an opaque native error. Matching is case-insensitive - `--browser Chrome` or `--browser WEBKIT` resolve the same as their lowercase forms (D2B-185).
20. If `--ask`/`--askme`'s confirmation read finds stdin already at EOF (closed, redirected from `/dev/null`, or already drained by a prior read), the command refuses with "stdin is not interactive" instead of silently treating the missing keypress as confirmation and continuing as if a human had pressed Enter. This checks only for EOF, not whether stdin is a real TTY - an open pipe or file that still has a line to read (e.g. containing "\n") is accepted the same as a real keypress.
21. `--engines` tolerates whitespace around the commas (e.g. `--engines "bing, google"` or `--engines "  duckduckgo  ,  bing  "`) - each name is trimmed before being looked up, rather than failing with "Unknown engine" on the untrimmed, space-padded value.
22. `browser.search` result `title`/`snippet`/`url` fields have common HTML entities decoded (`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`, numeric decimal/hex entities like `&#39;`/`&#x27;`, and common typographic entities - `&nbsp;`, `&mdash;`, `&ndash;`, `&lsquo;`/`&rsquo;`, `&ldquo;`/`&rdquo;`, `&hellip;`, `&copy;`, `&trade;`, `&reg;` - D2B-176) - a result whose source markup encodes an ampersand or apostrophe returns the real character, not the literal entity text. This matters most for `url`: search-engine result markup routinely HTML-entity-encodes the ampersand separating query-string parameters in an `href`, so without decoding, `url` would contain the literal `&amp;` sequence instead of `&`, corrupting the query string for anything that re-uses that URL.
23. A numeric HTML entity naming a UTF-16 surrogate codepoint (`&#xD800;`-`&#xDFFF;`, e.g. `&#xD800;` or the decimal form `&#56320;`) is left as literal entity text rather than decoded - surrogate codepoints are not valid standalone Unicode characters, and decoding one would produce invalid UTF-8 in the JSON output instead of the real character a valid entity represents.
24. `--file` is refused on `browser.get`/`browser.post` with a clear "--file is only read by browser.png/browser.pdf - it has no effect on GET/POST" error, instead of being silently accepted and ignored - only `browser.png`/`browser.pdf` read it (D2B-196).
25. `--timeout-ms` is refused with "--timeout-ms must not be negative" on `browser.get`/`browser.post`/`browser.png`, matching `browser.search`'s own negativity guard - a negative value never silently reaches Playwright's native timeout option.
26. `--engines` tolerates an empty segment from a leading, trailing, or doubled comma (e.g. `--engines ,bing` or `bing,,google`) by silently dropping it, rather than dying with an unhelpful blank "Unknown engine: " error - an `--engines` value naming only empty segments still refuses with "named no engines at all".
27. `browser.post`'s `final_url` result field reports the actual HTTP response URL instead of the page's untouched `about:blank` default when nothing navigates the page after the POST (the common case for a plain, non-controller POST). If a controller script, the response body's own embedded script, or manual `--ask` interaction deliberately navigates the page back to literally `about:blank`, that is indistinguishable from never having navigated at all, and `final_url` still reports the response URL in that rare case rather than the literal string `about:blank` - `about:blank` was never a useful answer to report either way.
28. `browser.get`/`browser.post`/`browser.png` default to a headless browser; `--headless`/`--no-headless` sets it explicitly - useful for watching a non-interactive run without pausing for manual input. `--ask`/`--askme` unconditionally force headless off for their own interactive mode, overriding an explicit `--headless` - `--headless`/`--no-headless` only has an effect when neither is used.
29. If the system's `node` binary is older than v20 (`package.json` declares `"engines": { "node": ">=20" }`, matching Playwright's own declared minimum), the skill fails fast with a clear "Node.js v20+ is required ... found vN. Please upgrade Node.js." error before attempting to load Playwright, instead of letting the real cause surface later as a cryptic native error from deep inside Playwright's own module-loading chain.
30. `--help` is recognized on `browser.get`/`browser.post`/`browser.png`/`browser.search` and always short-circuits to printing usage text and exiting 0, taking priority over every other flag or missing-argument validation - passing `--help` alongside other flags, or with no URL/query at all, still just prints usage rather than attempting a request or reporting an unrelated error.
31. A URL argument beginning with a literal `-` (e.g. `-example.com`) is misparsed as an unknown option rather than being used as the URL, since `browser.get`/`browser.post`/`browser.png` share the same Getopt::Long-based option parser - pass it after a literal `--` separator (e.g. `dashboard browser.get -- -example.com`) to have it treated as the positional URL argument instead, Getopt::Long's own standard end-of-options convention.
32. The same applies to `browser.search`'s query argument: a query beginning with a literal `-` (e.g. `-test query`) is misparsed as an unknown option rather than being used as the query - pass it after a literal `--` separator (e.g. `dashboard browser.search -- -test query`) to have it treated as the positional query argument instead.
33. `browser.png`'s `--file` is refused with a clear "--file points at an existing directory" error naming the path when it resolves to a path that is an existing directory (e.g. a directory literally named `shot.png`), instead of reaching Playwright's screenshot() call and surfacing a cryptic native error deep inside its own module-loading chain.
34. `--script` is refused with "--script must not be empty" when passed an explicit empty string, in both plain JS mode and controller mode (`--playwright`/`--agent`/`--flow`) - D2B-158. Omitting `--script` entirely remains an unaffected silent no-op in plain JS mode; in controller mode, omitting `--script` entirely is refused with "Controller mode requires --script" too, matching the empty-string case - D2B-184.
35. `--timeout-ms 0` on `browser.get`/`browser.post`/`browser.png` (and `browser.search`) is accepted and passed straight through to Playwright, which conventionally treats a `0` timeout as *disabling* the navigation timeout entirely, not as an instant/zero-wait request - a `0` value can genuinely hang rather than fail fast. This is distinct from `--ask`/`--askme`'s own no-timeout default, which produces the same underlying `timeout: 0` behavior but via omitting `--timeout-ms` altogether rather than passing it explicitly - D2B-172.
36. The `--` end-of-options escape from items 31/32 is itself honored even when the escaped positional value is literally `--help` or `--version` - `dashboard browser.get -- --version` treats `--version` as the literal URL rather than a version request, and `dashboard browser.search -- --help` treats `--help` as the literal query rather than a help request (D2B-186).
37. `--browser edge` launches Microsoft Edge via Playwright's `channel: 'msedge'` launch option rather than an `executablePath` - unlike `chrome`/`chromium`, it never inherits `CHROMIUM_BIN` or a PATH/direct-location-detected binary, even when one is configured (D2B-192).
38. `browser.pdf` is refused with a clear error naming the Chromium-only restriction when `--browser firefox`/`webkit` is requested, before a browser is ever launched - Playwright's PDF export (Chromium DevTools' `printToPDF`) has no Firefox/WebKit support at all (D2B-196).

## Continuous Integration

`.github/workflows/cross-platform.yml` runs a real (non-mocked) Playwright browser launch on every push/pull request, across `ubuntu-latest`, `ubuntu-24.04-arm`, `macos-latest`, `macos-13`, and `windows-latest` for each of `chrome`/`chromium`/`edge`/`firefox`/`webkit` - the only place a genuine launch is exercised, since every `t/*.t` test in this repo mocks Playwright instead. Windows arm64 is intentionally absent - it is not a generally-available GitHub-hosted runner as of this writing. The chrome-install step substitutes `chromium` for `ubuntu-24.04-arm` specifically, since Playwright's own installer refuses the branded `chrome` channel entirely on Linux ARM64 - the runtime `--browser chrome` flag is unaffected, since this skill's `chrome` browser type has no `executablePath` set on a fresh runner anyway and already launches Playwright's bundled chromium build either way (D2B-199). `edge` is excluded from the `ubuntu-24.04-arm` combination entirely, since Microsoft ships no Edge build for Linux ARM64 at all - unlike chrome, there is no substitute install target that would actually exercise edge there. Playwright's own install CLI names the Edge channel `msedge`, not `edge`, so the install step maps this skill's `--browser edge` value to that install target name specifically (D2B-200).

## Documentation

See:

- `SKILLS.md` - the condensed, agent-facing manual (also printed verbatim by `dashboard browser.skills`)
- `docs/overview.md`
- `docs/usage.md`
- `docs/changes/2026-04-21-browser-gating.md`
- `docs/changes/2026-04-22-controller-mode.md`
- `docs/changes/2026-04-22-ask-timeout.md`
- `docs/changes/2026-04-22-example-library.md`
- `docs/changes/2026-04-22-node-runtime-repair.md`
- `docs/changes/2026-04-22-platform-examples.md`
- `docs/changes/2026-04-22-proven-examples.md`
- `docs/changes/2026-04-24-browser-binary-validation.md`
- `docs/changes/2026-04-24-browser-png.md`
- `docs/changes/2026-05-06-mit-license.md`
