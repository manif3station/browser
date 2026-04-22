# browser

## Description

`browser` is a Developer Dashboard skill that exposes Playwright-backed browser work through skill CLI commands. It gives DD users a reusable way to fetch a page, run either a page-context JavaScript snippet or a full Playwright control script, and issue browser-managed POST requests from the command line.

## Value

The skill brings browser automation into DD without requiring each user to build their own one-off Playwright wrapper first.

It helps a user:

- inspect a page through a real browser session
- run a small DOM task directly from the CLI
- run a multi-page browser journey from one starting URL
- issue a POST request and inspect the returned content
- keep this automation isolated in an installable DD skill

## Problem It Solves

Without a shared skill, quick browser-driven automation often ends up split across shell history, ad-hoc Node scripts, and throwaway Perl wrappers. That makes repeatable browser tasks harder to share and harder to rerun through Developer Dashboard.

## What It Does To Solve It

`browser` provides:

- `cli/get` for `dashboard browser.get <url>`
- `cli/post` for `dashboard browser.post <url>`
- HTML page body output for `browser.get`
- text extraction, content type reporting, and captcha detection for browser responses
- interactive visible-browser takeover through `--ask` and `--askme`
- optional jQuery injection through `--jquery`
- optional page-context JavaScript through `--script`
- optional Playwright controller mode through `--playwright`, `--agent`, and `--flow`
- optional `--data` for `browser.post`
- DD dependency files so the skill can install its Perl and system prerequisites
- `package.json` so DD can install the Node runtime dependencies into `$HOME`

## Developer Dashboard Feature Added

This skill adds:

- the dotted command `dashboard browser.get`
- the dotted command `dashboard browser.post`
- a reusable example of a skill that depends on `aptfile`, `brewfile`, and `cpanfile`

## Layout

- `cli/get` skill CLI GET entrypoint
- `cli/post` skill CLI POST entrypoint
- `config/config.json` skill-local config placeholder
- `lib/Browser/CLI.pm` CLI parsing and JSON output
- `lib/Browser/Runner.pm` Playwright execution
- `aptfile`, `brewfile`, `package.json`, and `cpanfile` dependency declarations
- `t/` skill-local tests
- `docs/` skill-local documentation
- `tickets/` skill-local project-management records
- `.env` skill-local version metadata
- `Changes` skill-local changelog

## Installation

Install the skill through Developer Dashboard from a git repository:

```bash
dashboard skills install <git-url-to-browser-skill>
```

Example:

```bash
dashboard skills install git@github.mf:manif3station/browser.git
```

## CLI Usage

Direct local development:

```bash
perl cli/get https://example.com
perl cli/post https://example.com/form --data 'name=dashboard'
```

Installed DD usage:

```bash
dashboard browser.get https://example.com
dashboard browser.get https://example.com --script 'return document.title'
dashboard browser.get https://example.com --ask
dashboard browser.get https://example.com --jquery --script 'return $("h1").first().text()'
dashboard browser.get https://example.com --flow --script 'my $response = $page->goto("https://example.com/next", { waitUntil => "networkidle" }); return { title => $page->title(), url => $page->url(), status => $response->status() };'
dashboard browser.post https://example.com/form
dashboard browser.post https://example.com/form --data 'name=dashboard'
dashboard browser.post https://example.com/form --script 'return window.__BROWSER_POST__.status'
```

The skill ships `package.json` so DD can install the required Node packages with its normal skill dependency flow. For direct local development, the same dependency shape can be prepared with:

```bash
npm install --prefix "$HOME" .
```

## Practical Examples

Normal case, fetch a page title:

```bash
dashboard browser.get https://example.com --script 'return document.title'
```

Normal case, fetch the rendered HTML body:

```bash
dashboard browser.get https://example.com
```

Normal case, inspect whether a page looks like a bot-check:

```bash
dashboard browser.get 'https://www.google.com/search?q=developer+dashboard'
```

The payload now includes:

- `content_type`
- `body_text`
- `is_captcha`

Normal case, open a visible browser so you can complete a captcha or login and then continue:

```bash
dashboard browser.get 'https://www.google.com/search?q=developer+dashboard' --ask
```

`--askme` is accepted as the same interaction mode.

Normal case, inject jQuery so the script can use `$()` selectors:

```bash
dashboard browser.get https://example.com --jquery --script 'return window.jQuery("h1").first().text()'
```

Normal case, run a full multi-page Playwright flow from one starting URL:

```bash
dashboard browser.get https://example.com/start --flow --script 'my $response = $page->goto("https://example.com/final", { waitUntil => "networkidle" }); return { title => $page->title(), url => $page->url(), status => $response->status() };'
```

Normal case, pause for manual login or CAPTCHA work and then continue with a Playwright flow:

```bash
dashboard browser.get https://example.com/login --ask --playwright --script 'my $response = $page->goto("https://example.com/account", { waitUntil => "networkidle" }); return { title => $page->title(), url => $page->url(), status => $response->status() };'
```

Normal case, inspect a heading:

```bash
dashboard browser.get https://example.com --script 'return document.querySelector("h1").textContent'
```

Normal case, issue a POST and inspect the returned body:

```bash
dashboard browser.post https://example.com/form --data 'name=dashboard' --script 'return document.body.textContent.trim()'
```

Normal case, remove the skill:

```bash
dashboard skills uninstall browser
```

## Edge Cases

- if the skill is not installed, DD will not dispatch `browser.get` or `browser.post`
- if Playwright or node dependencies are missing, the command fails until skill dependencies are installed
- if the target host is unavailable, the Playwright run exits non-zero
- if a POST response is plain text instead of HTML, the skill wraps it in HTML so DOM scripts still have a page to inspect
- if the Node runtime has not been installed from `package.json` yet, the first command run may take longer while it runs the same `npm install --prefix "$HOME" <skill-root>` flow DD uses
- if the page is large, `browser.get` returns the full rendered HTML body and the JSON payload can become large
- if a site responds with a CAPTCHA or challenge page, `is_captcha` is set to true and `body_text` gives a readable summary of the challenge content
- if `--ask` or `--askme` is used, the command opens a visible browser and waits for you to press Enter in the terminal before it captures the final payload
- if `--ask` or `--askme` is used in an environment without a display server, the visible browser launch can fail until the command is run on a host with a desktop session
- if `--jquery` is used, the skill injects its locally installed jQuery runtime into the page before your script runs
- if `--playwright`, `--agent`, or `--flow` is used, `--script` is treated as a Perl Playwright control script instead of page-context JavaScript
- if controller mode navigates to another page, the final payload reflects the current page state after the flow

## Documentation

See:

- `docs/overview.md`
- `docs/usage.md`
- `docs/changes/2026-04-21-browser-gating.md`
- `docs/changes/2026-04-22-controller-mode.md`
