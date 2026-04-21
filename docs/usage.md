# browser usage

## Commands

Installed DD usage:

```bash
dashboard browser.get https://example.com
dashboard browser.get https://example.com --script 'return document.title'
dashboard browser.post https://example.com/form
dashboard browser.post https://example.com/form --data 'name=dashboard' --script 'return document.body.textContent.trim()'
```

Local repository usage during development:

```bash
perl cli/get https://example.com
perl cli/post https://example.com/form --data 'name=dashboard'
```

## Output

Each command prints one JSON object to stdout. The payload includes the request method, requested URL, final URL, HTTP status, and optional script result.

For `browser.get`, the payload also includes the page title. For `browser.post`, the payload also includes the response body so the caller can inspect returned content from the CLI.

The skill declares its Node-side dependencies in `package.json`, matching the DD skill dependency contract. DD installs that file with:

```bash
npm install --prefix "$HOME" <skill-root>
```

For direct local development outside DD, use:

```bash
npm install --prefix "$HOME" .
```

## Script Behavior

`--script` accepts a Playwright JavaScript function body, matching the `evaluate()` string-mode contract documented by the Playwright Perl module.

Examples:

```bash
dashboard browser.get https://example.com --script 'return document.querySelector("h1").textContent'
dashboard browser.post https://example.com/form --data "name=dd" --script 'return window.__BROWSER_POST__.status'
```

For `browser.post`, the skill loads the response content into a page before evaluating the script. It also exposes response metadata through `window.__BROWSER_POST__`.

## Edge Cases

- if the skill is not installed, `dashboard browser.get` and `dashboard browser.post` will not dispatch
- if Playwright dependencies are missing, the command will fail until DD installs the skill dependencies
- if the target URL cannot be reached, Playwright raises an error and the command exits non-zero
- if a POST response is not HTML, the skill wraps the body in a simple HTML document so a DOM-based script can still inspect it
- if the Node runtime has not been installed from `package.json` yet, the first command run can take longer while the skill installs `playwright`, `express`, and `uuid` into `$HOME/node_modules`
