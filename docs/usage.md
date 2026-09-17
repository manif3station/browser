# browser usage

## Commands

Installed DD usage:

```bash
dashboard browser.get https://example.com
dashboard browser.get https://example.com --script 'return document.title'
dashboard browser.get https://example.com --ask
dashboard browser.get https://example.com --jquery --script 'return $("h1").first().text()'
dashboard browser.get https://example.com --flow --script 'my $response = $page->goto("https://www.iana.org/domains/example", { waitUntil => "load" }); return { title => $page->title(), url => $page->url(), status => $response->status() };'
dashboard browser.get https://example.com/login --ask --timeout-ms 120000
dashboard browser.get 'https://www.amazon.com/s?k=desk+lamp' --wait-until load --script 'return document.title'
dashboard browser.get https://x.com --wait-until load --script 'return document.title'
dashboard browser.post https://example.com/form
dashboard browser.post https://example.com/form --data 'name=dashboard' --script 'return document.body.textContent.trim()'
dashboard browser.png https://example.com
dashboard browser.png https://example.com --file /tmp/example-shot
dashboard browser.search 'which mini PC can run a ~30B Qwen3 at 1M context'
dashboard browser.search 'query' --engine google
dashboard browser.search 'query' --engines duckduckgo,bing --max 5
```

Local repository usage during development:

```bash
perl cli/get https://example.com
perl cli/post https://example.com/form --data 'name=dashboard'
perl cli/png https://example.com --file /tmp/example-shot
perl cli/search 'query'
```

## Output

`browser.get` and `browser.post` print one JSON object to stdout. The payload includes the request method, requested URL, final URL, HTTP status, optional script result, response `content_type`, extracted `body_text`, and an `is_captcha` flag.

For `browser.get`, the payload also includes the page title and the rendered page HTML body. For `browser.post`, the payload also includes the response body so the caller can inspect returned content from the CLI.

`browser.png` prints only the saved PNG file path to stdout.

Example:

```text
/tmp/example-shot.png
```

Example GET payload shape:

```json
{"requested_url":"https://www.google.com","final_url":"https://www.google.com/","method":"GET","status":200,"title":"Google","content_type":"text/html; charset=utf-8","body":"<!DOCTYPE html>...","body_text":"Google Search ...","is_captcha":false}
```

The skill declares its Node-side dependencies in `package.json`, matching the DD skill dependency contract. DD installs that file with:

```bash
npm install --prefix "$HOME" <skill-root>
```

The skill also checks that the installed `$HOME/node_modules` versions still satisfy `package.json`. If the installed tree is stale or mismatched, it stages a fresh `npx --yes npm install ...` in the DD cache and replaces the affected module directories before launching Playwright.

The skill only passes `executablePath` to Playwright when the browser path is validated as an absolute, launchable binary. Relative PATH wrappers such as `bin/chrome` are ignored.

For direct local development outside DD, use:

```bash
npm install --prefix "$HOME" .
```

## Screenshot Behavior

`browser.png` captures the rendered page after navigation and writes one PNG file.

If `--file` is omitted, the skill writes to a generated tmp path under `/tmp` and prints that path.

If `--file` is supplied without a `.png` suffix, the skill appends `.png`.

If `--file` already ends in `.png`, the skill keeps the filename as-is and does not add another suffix.

## Script Behavior

By default, `--script` accepts a Playwright JavaScript function body, matching the `evaluate()` string-mode contract documented by the Playwright Perl module.

Examples:

```bash
dashboard browser.get https://example.com --script 'return document.querySelector("h1").textContent'
dashboard browser.post https://example.com/form --data "name=dd" --script 'return window.__BROWSER_POST__.status'
```

For `browser.post`, the skill loads the response content into a page before evaluating the script. It also exposes response metadata through `window.__BROWSER_POST__`.

Use JavaScript mode when you want to inspect the current page only.

Use Perl controller mode when you need to click, fill, navigate, log in, or continue across pages.

Use `--wait-until load` or `--wait-until domcontentloaded` when a public site never settles into a useful `networkidle` state.

## Controller Mode

`--playwright`, `--agent`, and `--flow` are equivalent flags. Any of them switches `--script` from page-context JavaScript into a Perl Playwright controller script.

In controller mode, your script receives:

- `$page`
- `$browser`
- `$playwright`
- `$response`
- `$method`
- `$url`

This is the mode to use when the script needs to click, fill, navigate, log in, or continue through multiple pages after the starting URL loads.

Example:

```bash
dashboard browser.get https://example.com/login --flow --script 'my $response = $page->goto("https://example.com/account", { waitUntil => "networkidle" }); return { title => $page->title(), url => $page->url(), status => $response->status() };'
```

Example with a fuller journey shape:

```bash
dashboard browser.get https://example.com/login --playwright --script 'my $email = $page->select("#email"); $email->fill("user@example.com"); my $password = $page->select("#password"); $password->fill("secret"); my $submit = $page->select("button[type=submit]"); $submit->click(); my $response = $page->goto("https://example.com/account", { waitUntil => "networkidle" }); return { title => $page->title(), url => $page->url(), status => $response->status() };'
```

The final JSON payload is captured after the controller script finishes, so `final_url`, `title`, `body`, and `body_text` reflect the current page at the end of the flow.

## Wait Modes

The skill supports:

- `--wait-until networkidle`
- `--wait-until load`
- `--wait-until domcontentloaded`

If not set:

- normal non-interactive GET runs default to `networkidle`
- ask-mode GET runs default to `load`

For sites like Amazon, `--wait-until load` is often the safer documented choice.

## jQuery Mode

Playwright does not automatically provide jQuery in the page context.

`--jquery` tells the skill to inject its locally installed jQuery runtime into the page before your script runs. That gives your script access to `window.$` and `window.jQuery` even when the target page did not load jQuery itself.

Example:

```bash
dashboard browser.get https://example.com --jquery --script 'return window.jQuery("h1").first().text()'
```

`--jquery` is for page-side extraction. It does not change Perl controller syntax.

## Interactive Mode

`browser.get` accepts `--ask` and `--askme` as the same interactive mode.

When used:

- the browser launches non-headless
- the page stays open for manual login or CAPTCHA work
- the command waits for you to press Enter in the terminal
- after that, the final payload is captured from the current page state
- if controller mode is also enabled, the Playwright control script runs after that manual pause
- the initial page navigation uses `waitUntil => "load"` instead of `networkidle`
- the initial page navigation disables the timeout unless `--timeout-ms` is set
- the confirmation read must find stdin still open with input to read; if stdin is closed, redirected from `/dev/null`, or already at EOF, the command refuses with "stdin is not interactive - --ask/--askme requires a real terminal to confirm on" instead of silently treating the missing keypress as an implicit confirmation. This checks only for EOF, not whether stdin is an actual TTY - an open pipe or file with a line still to read is accepted the same as a real keypress.

Example:

```bash
dashboard browser.get 'https://www.google.com/search?q=developer+dashboard' --ask
```

Example with controller mode:

```bash
dashboard browser.get https://example.com/login --ask --agent --script 'my $response = $page->goto("https://example.com/account", { waitUntil => "networkidle" }); return { title => $page->title(), url => $page->url(), status => $response->status() };'
```

If you still want a bounded initial wait in ask-mode:

```bash
dashboard browser.get https://example.com/login --ask --timeout-ms 120000
```

## Example Library

The full example library is kept in `README.md` and includes:

- fixture-verified examples
- live-verified Amazon examples
- live-verified X examples

Only the remaining examples in `README.md` are treated as proven examples.

## Captcha Detection

The skill marks a response as captcha-like only when the page's HTML
(the current DOM for `browser.get`, or the response HTML being inspected
for `browser.post`) contains one of four specific substrings associated
with real reCAPTCHA/hCaptcha embeds (`g-recaptcha`, `h-captcha`,
`recaptcha/api`, `hcaptcha.com`), or when the page **title** matches a
challenge phrase (`captcha`, `unusual traffic`, `verify you are human`).
It is a plain case-insensitive substring match, not markup validation,
and it does not scan the page's visible rendered text (`body_text`) for a
bare mention of "captcha" - an ordinary page whose body text merely
discusses captchas, without one of those four markers actually present in
the HTML, is not flagged.

This is intended as a practical CLI signal, not a perfect classifier.

## Search Mode

`browser.search <query>` drives `browser.get`'s own GET path against an ordered list of search engines and returns structured results instead of raw HTML. Like `browser.get`, it always launches headless - there is no interactive/`--ask` mode for search.

The default engine order is `bing`, `google`, `duckduckgo`. For each engine in order, the skill checks the same `is_captcha` flag `browser.get` already computes on the response; if it is true, that engine is skipped and the next one is tried. The response payload names `engine_used` (which engine actually served the results) and `engines_tried` (every engine attempted, in order).

Each result has `rank`, `title`, `url`, and `snippet`, extracted from that engine's own result markup. A layout change on one engine's search page only affects that engine's own parser. `title` and `snippet` have common HTML entities (`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`, and numeric decimal/hex entities like `&#39;`/`&#x27;`) decoded, so they contain the real characters rather than literal entity text. This decoding requires the trailing semicolon and is a single pass (a double-encoded `&amp;amp;` decodes once, to `&amp;`, not recursively to `&`); an entity outside the valid Unicode range is left as literal text rather than raising an error.

Example payload shape:

```json
{"query":"which mini PC can run a ~30B Qwen3 at 1M context","engine_used":"bing","engines_tried":["bing"],"results":[{"rank":1,"title":"...","url":"...","snippet":"..."}]}
```

`--engine NAME` restricts the search to one named engine (refused if the engine isn't one of the defaults). `--engines a,b,c` overrides the whole order; whitespace around each comma-separated name is tolerated (e.g. `--engines "bing, google"`), so a human-typed list with spaces doesn't fail with "Unknown engine". Engine name matching is case-insensitive (`--engine Bing` and `--engines DuckDuckGo,BING` both work). A repeated name in the list (e.g. `--engines bing,bing`) is deduplicated, preserving the order of first occurrence, so a walled engine is never retried a second time. `--max N` caps how many results are returned (default 10). `--timeout-ms N` bounds each individual engine attempt (default 10000) - a slow/unresponsive engine fails fast instead of exhausting Playwright's own longer internal default before moving to the next engine.

If every engine in the list comes back walled, the command refuses with a structured error naming each one and pointing to `browser.get --ask` for interactive use, rather than hanging or returning an empty success.

## Edge Cases

- if the skill is not installed, `dashboard browser.get` and `dashboard browser.post` will not dispatch
- if Playwright dependencies are missing, the command will fail until DD installs the skill dependencies
- if the target URL cannot be reached, Playwright raises an error and the command exits non-zero
- if a POST response is not HTML, the skill wraps the body in a simple HTML document so a DOM-based script can still inspect it
- if the Node runtime has not been installed from `package.json` yet, the first command run can take longer while the skill stages and installs `playwright`, `express`, `jquery`, and `uuid` into `$HOME/node_modules`
- if `$HOME/node_modules` contains stale module trees from an older install, the skill clears the affected package directories and reinstalls them from the current `package.json`
- if `CHROMIUM_BIN` is not set, the skill looks for a usable system Chromium or Chrome binary on `PATH`
- if `CHROMIUM_BIN` points at a broken wrapper or non-launchable binary, the skill ignores it instead of passing it through to Playwright
- if the page HTML is large, `browser.get` returns that full HTML in the JSON payload
- if `browser.png` is called without `--file`, the generated filename is random and will vary between runs
- if `--ask` or `--askme` is used on a host without a display server, the headed browser launch can fail until the command is run in a desktop-capable environment
- if a login page keeps long-lived background requests open, ask-mode avoids `networkidle` on the initial load so the browser session can stay open for manual work
- if controller mode is used, write the script in single quotes so shell expansion does not consume Perl variables like `$page`
