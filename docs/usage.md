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
dashboard browser.get https://example.com --no-headless
dashboard browser.get --help
```

`--help` prints usage text and exits 0 for any of the four commands, taking priority over every other flag or missing-argument validation - it works even with no URL/query given, and even combined with other flags. `browser.skills` prints this skill's `SKILLS.md` agent manual.

`browser.get`/`browser.post`/`browser.png` all run headless by default; `--headless`/`--no-headless` sets it explicitly, useful for watching a non-interactive run without pausing for manual input. `--ask`/`--askme` unconditionally force headless off for their own interactive mode, overriding an explicit `--headless` - `--headless`/`--no-headless` only has an effect on a non-interactive run.

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

`browser.get`, `browser.post`, and `browser.png` all accept `--ask` and `--askme` as the same interactive mode - they are declared once in the shared CLI option parsing all three methods use, not just for `browser.get`.

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
for `browser.post`) contains a real, unescaped opening tag with a
`class` attribute whose value contains `g-recaptcha`/`h-captcha`, or a
`src`/`action` attribute whose value contains `recaptcha/api`/
`hcaptcha.com` (quoted or unquoted) - or when the page **title**
matches a challenge phrase (`captcha`, `unusual traffic`, `verify you
are human`). This is still a substring check within the matched
attribute value, not exact-value matching or full markup validation, so
an unrelated compound class name that happens to contain `g-recaptcha`
as a substring (or the same markup appearing inside an HTML comment)
can still false-positive; requiring a literal `<...>` tag around the
attribute is specifically what stops the common case this ticket
exists to fix - a documentation or tutorial page merely *showing*
example widget-integration markup inside a `<pre>` block,
HTML-entity-escaped so it contains no real `<`/`>` characters even
though the attribute text itself survives the escaping untouched
(D2B-083). The title check matches the whole word `captcha`
(so a plural like "CAPTCHAs" is not matched), plus a separate
case-insensitive substring check specifically for `recaptcha` so a title
like "reCAPTCHA verification required" is also caught - this second
check is deliberately narrow to `recaptcha` rather than any word ending
in `captcha`, so an unrelated title like "NoCaptcha documentation" is
not flagged. Neither check scans the page's visible rendered text
(`body_text`) for a bare mention of "captcha" - an ordinary page whose
body text merely discusses captchas, without one of those four markers
actually present in the HTML or a matching title, is not flagged.

This is intended as a practical CLI signal, not a perfect classifier.

## Search Mode

`browser.search <query>` drives `browser.get`'s own GET path against an ordered list of search engines and returns structured results instead of raw HTML. Like `browser.get`, it always launches headless - there is no interactive/`--ask` mode for search.

The default engine order is `bing`, `google`, `duckduckgo`. For each engine in order, the skill checks the same `is_captcha` flag `browser.get` already computes on the response; if it is true, that engine is skipped and the next one is tried. An engine whose result markup no longer matches its parser (e.g. the site's layout changed) is likewise skipped and the next engine tried, rather than returning an empty result set as if the query genuinely had no results - this is a heuristic keyed on response size: a response body longer than 200 characters that parses to zero results is treated as a markup-drift failure (not the last engine), while a short/trivial body parsing to zero results is treated as a genuine no-results page. Because this is a heuristic, not a certainty, a genuinely large "no results found" page from a real search engine could still be misclassified as markup drift and skipped in favor of trying the next engine - only when every engine has been tried does an empty result set come back as success either way. The response payload names `engine_used` (which engine actually served the results) and `engines_tried` (every engine attempted, in order).

Each result has `rank`, `title`, `url`, and `snippet`, extracted from that engine's own result markup. A layout change on one engine's search page only affects that engine's own parser. `title`, `snippet`, and `url` have common HTML entities (`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`, and numeric decimal/hex entities like `&#39;`/`&#x27;`) decoded, so they contain the real characters rather than literal entity text. `url` needs this as much as the text fields do: result markup routinely HTML-entity-encodes the `&` separating query-string parameters inside an `href`, and without decoding, `url` would contain the literal `&amp;` sequence instead of `&`, silently corrupting the query string for anything that re-uses that URL (e.g. feeding it back into `browser.get`). This decoding requires the trailing semicolon and is a single pass (a double-encoded `&amp;amp;` decodes once, to `&amp;`, not recursively to `&`); an entity outside the valid Unicode range, or naming a UTF-16 surrogate codepoint (`&#xD800;`-`&#xDFFF;`, decimal or hex), is left as literal entity text rather than decoded - a surrogate codepoint is not a valid standalone Unicode character, and decoding one would produce invalid UTF-8 in the JSON payload instead of a real character.

Example payload shape:

```json
{"query":"which mini PC can run a ~30B Qwen3 at 1M context","engine_used":"bing","engines_tried":["bing"],"results":[{"rank":1,"title":"...","url":"...","snippet":"..."}]}
```

`--engine NAME` restricts the search to one named engine (refused if the engine isn't one of the defaults). `--engines a,b,c` overrides the whole order; whitespace around each comma-separated name is tolerated (e.g. `--engines "bing, google"`), so a human-typed list with spaces doesn't fail with "Unknown engine". Engine name matching is case-insensitive (`--engine Bing` and `--engines DuckDuckGo,BING` both work). A repeated name in the list (e.g. `--engines bing,bing`) is deduplicated, preserving the order of first occurrence, so a walled engine is never retried a second time. `--max N` caps how many results are returned (default 10) - a negative value is refused with "--max must not be negative". `--timeout-ms N` bounds each individual engine attempt (default 10000) - a slow/unresponsive engine fails fast instead of exhausting Playwright's own longer internal default before moving to the next engine; a negative value is likewise refused with "--timeout-ms must not be negative" rather than being passed through unchecked to Playwright's own timeout option.

If every engine in the list comes back walled, the command refuses with a structured error naming each one and pointing to `browser.get --ask` for interactive use, rather than hanging or returning an empty success.

## Edge Cases

- if the skill is not installed, `dashboard browser.get` and `dashboard browser.post` will not dispatch
- if Playwright dependencies are missing, the command will fail until DD installs the skill dependencies
- if the target URL cannot be reached, Playwright raises an error and the command exits non-zero
- if a POST response body is not explicitly HTML, the skill always wraps it in a simple HTML document (HTML-escaped inside a `<pre>` block) so a DOM-based script can still inspect it without any risk of embedded markup executing - a body is only ever trusted and returned unwrapped when the response's content type is *exactly* (ignoring parameters like `; charset=...`) `text/html` or `application/xhtml+xml`, or the body itself starts with a properly-bounded doctype/`<html>` tag (a header like `application/json; note=text/html`, or a body starting `<htmlscript>`, does not count); a bare fragment that merely *looks* tag-shaped (e.g. `<data>foo</data>`, or even a genuinely well-formed one like `<div><span>hi</span></div>`) but lacks that explicit HTML content-type declaration is always escaped/wrapped too (never trusted on its shape alone), since a hand-rolled tag-shape check cannot safely distinguish that from a crafted body smuggling a live `<script>` sibling past it via HTML's own implicit tag-closing rules (D2B-079)
- if the Node runtime has not been installed from `package.json` yet, the first command run can take longer while the skill stages and installs `playwright`, `express`, `jquery`, and `uuid` into `$HOME/node_modules`
- if `$HOME/node_modules` contains stale module trees from an older install, the skill clears the affected package directories and reinstalls them from the current `package.json`
- if `CHROMIUM_BIN` is not set, the skill looks for a usable system Chromium or Chrome binary on `PATH`
- if `CHROMIUM_BIN` points at a broken wrapper or non-launchable binary, the skill ignores it instead of passing it through to Playwright
- if the page HTML is large, `browser.get` returns that full HTML in the JSON payload
- if `browser.png` is called without `--file`, the generated filename is random and will vary between runs
- if `--ask` or `--askme` is used on a host without a display server, the headed browser launch can fail until the command is run in a desktop-capable environment
- if a login page keeps long-lived background requests open, ask-mode avoids `networkidle` on the initial load so the browser session can stay open for manual work
- if controller mode is used, write the script in single quotes so shell expansion does not consume Perl variables like `$page`
- `--file` is refused on `browser.get`/`browser.post` with "--file is only read by browser.png - it has no effect on GET/POST" - only `browser.png` reads it
- `browser.post`'s `final_url` reports the actual response URL, not the page's untouched `about:blank` default, for a plain POST that nothing navigates afterward - setContent() (used to inject the response body for display) does not itself navigate the page. The one disclosed limitation: if a controller script, the response body's own embedded script, or manual `--ask` interaction deliberately navigates the page back to literally `about:blank`, that is indistinguishable from never having navigated, and `final_url` still reports the response URL rather than the literal string `about:blank` in that rare case (D2B-092)
- `browser.get`/`browser.post`/`browser.png` default to a headless browser; `--headless`/`--no-headless` sets it explicitly - but `--ask`/`--askme` unconditionally force headless off for their own interactive mode, overriding an explicit `--headless` (D2B-093)
- if the system's `node` binary is older than v20 (`package.json` declares `"engines": { "node": ">=20" }`, matching Playwright's own declared minimum), the skill fails fast with a clear "Node.js v20+ is required ... found vN" error before attempting to load Playwright, instead of a cryptic native error surfacing later from deep inside Playwright's own module-loading chain (D2B-095)
