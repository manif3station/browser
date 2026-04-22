# browser usage

## Commands

Installed DD usage:

```bash
dashboard browser.get https://example.com
dashboard browser.get https://example.com --script 'return document.title'
dashboard browser.get https://example.com --ask
dashboard browser.get https://example.com --jquery --script 'return $("h1").first().text()'
dashboard browser.get https://example.com --flow --script 'my $response = $page->goto("https://example.com/final", { waitUntil => "networkidle" }); return { title => $page->title(), url => $page->url(), status => $response->status() };'
dashboard browser.get https://example.com/login --ask --timeout-ms 120000
dashboard browser.post https://example.com/form
dashboard browser.post https://example.com/form --data 'name=dashboard' --script 'return document.body.textContent.trim()'
```

Local repository usage during development:

```bash
perl cli/get https://example.com
perl cli/post https://example.com/form --data 'name=dashboard'
```

## Output

Each command prints one JSON object to stdout. The payload includes the request method, requested URL, final URL, HTTP status, optional script result, response `content_type`, extracted `body_text`, and an `is_captcha` flag.

For `browser.get`, the payload also includes the page title and the rendered page HTML body. For `browser.post`, the payload also includes the response body so the caller can inspect returned content from the CLI.

Example GET payload shape:

```json
{"requested_url":"https://www.google.com","final_url":"https://www.google.com/","method":"GET","status":200,"title":"Google","content_type":"text/html; charset=utf-8","body":"<!DOCTYPE html>...","body_text":"Google Search ...","is_captcha":false}
```

The skill declares its Node-side dependencies in `package.json`, matching the DD skill dependency contract. DD installs that file with:

```bash
npm install --prefix "$HOME" <skill-root>
```

For direct local development outside DD, use:

```bash
npm install --prefix "$HOME" .
```

## Script Behavior

By default, `--script` accepts a Playwright JavaScript function body, matching the `evaluate()` string-mode contract documented by the Playwright Perl module.

Examples:

```bash
dashboard browser.get https://example.com --script 'return document.querySelector("h1").textContent'
dashboard browser.post https://example.com/form --data "name=dd" --script 'return window.__BROWSER_POST__.status'
```

For `browser.post`, the skill loads the response content into a page before evaluating the script. It also exposes response metadata through `window.__BROWSER_POST__`.

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

## jQuery Mode

Playwright does not automatically provide jQuery in the page context.

`--jquery` tells the skill to inject its locally installed jQuery runtime into the page before your script runs. That gives your script access to `window.$` and `window.jQuery` even when the target page did not load jQuery itself.

Example:

```bash
dashboard browser.get https://example.com --jquery --script 'return window.jQuery("h1").first().text()'
```

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

## Captcha Detection

The skill marks a response as captcha-like when the rendered page looks like a bot challenge, such as content that includes:

- `captcha`
- `recaptcha`
- `unusual traffic`
- `verify you are human`

This is intended as a practical CLI signal, not a perfect classifier.

## Edge Cases

- if the skill is not installed, `dashboard browser.get` and `dashboard browser.post` will not dispatch
- if Playwright dependencies are missing, the command will fail until DD installs the skill dependencies
- if the target URL cannot be reached, Playwright raises an error and the command exits non-zero
- if a POST response is not HTML, the skill wraps the body in a simple HTML document so a DOM-based script can still inspect it
- if the Node runtime has not been installed from `package.json` yet, the first command run can take longer while the skill installs `playwright`, `express`, and `uuid` into `$HOME/node_modules`
- if the page HTML is large, `browser.get` returns that full HTML in the JSON payload
- if `--ask` or `--askme` is used on a host without a display server, the headed browser launch can fail until the command is run in a desktop-capable environment
- if a login page keeps long-lived background requests open, ask-mode avoids `networkidle` on the initial load so the browser session can stay open for manual work
- if controller mode is used, write the script in single quotes so shell expansion does not consume Perl variables like `$page`
