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

## Problem It Solves

Without a shared browser skill, quick browser tasks usually fragment into shell snippets, one-off Node scripts, and ad hoc Playwright experiments. That makes them hard to share, hard to rerun, and hard to align with the DD skill system.

## What It Does To Solve It

`browser` provides:

- `dashboard browser.get <url>`
- `dashboard browser.post <url>`
- JavaScript page-context scripting through `--script`
- Perl controller scripting through `--playwright`, `--agent`, or `--flow`
- jQuery injection through `--jquery`
- interactive visible-browser takeover through `--ask` and `--askme`
- HTML body, text body, status, final URL, and CAPTCHA detection in the output payload

## Developer Dashboard Feature Added

This skill adds:

- the dotted command `dashboard browser.get`
- the dotted command `dashboard browser.post`
- a DD skill example that depends on `aptfile`, `brewfile`, `cpanfile`, and `package.json`

## Layout

- `cli/get` GET entrypoint
- `cli/post` POST entrypoint
- `lib/Browser/CLI.pm` CLI parsing and JSON output
- `lib/Browser/Runner.pm` Playwright execution
- `aptfile`, `brewfile`, `package.json`, and `cpanfile` dependency declarations
- `t/` tests
- `docs/` skill docs
- `tickets/` project-management records
- `.env` version metadata
- `Changes` changelog

## Installation

Install through Developer Dashboard:

```bash
dashboard skills install <git-url-to-browser-skill>
```

Example:

```bash
dashboard skills install git@github.mf:manif3station/browser.git
```

Developer Dashboard installs the skill's `package.json` runtime into `$HOME` using the DD Node dependency path. The skill also verifies that installed module versions still satisfy `package.json`, and if they do not, it stages a fresh `npx --yes npm install ...` under the DD cache and replaces the stale module trees before launching Playwright.

For direct local development outside DD, you can preinstall the Node-side runtime with:

```bash
npm install --prefix "$HOME" .
```

## CLI Usage

Installed DD usage:

```bash
dashboard browser.get https://example.com
dashboard browser.get https://example.com --script 'return document.title'
dashboard browser.get https://example.com --jquery --script 'return $("h1").first().text()'
dashboard browser.get https://example.com/login --ask --timeout-ms 120000
dashboard browser.get https://example.com/start --flow --script 'my $response = $page->goto("https://example.com/final", { waitUntil => "networkidle" }); return { title => $page->title(), url => $page->url(), status => $response->status() };'
dashboard browser.post https://example.com/form --data 'name=dashboard'
```

Direct local development:

```bash
perl cli/get https://example.com
perl cli/post https://example.com/form --data 'name=dashboard'
```

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
3. If the target host is unavailable, the Playwright run exits non-zero.
4. If the page is large, `browser.get` returns a large JSON payload because it includes the rendered HTML body.
5. If the response looks like a challenge page, `is_captcha` is set to true and `body_text` provides a readable summary.
6. If a POST response is plain text instead of HTML, the skill wraps it in HTML so DOM scripts still have a page to inspect.
7. If `--ask` or `--askme` is used, the command opens a visible browser and waits for terminal confirmation before continuing.
8. If `--ask` is used, the initial navigation defaults to `load` with no timeout; add `--timeout-ms` if you want a bounded initial wait.
9. If `--ask` is used on a host without a display server, the headed browser launch can fail until the command runs in a desktop-capable environment.
10. If `--jquery` is used, it only helps page-side JavaScript or `$page->evaluate(...)` calls, not Perl itself.
11. If controller mode is used, write the script in single quotes so the shell does not consume Perl variables like `$page`.
12. If a selector guess is wrong, the controller script can die on `undef`; use defensive selection and inspection patterns first.
13. If a target site keeps long-lived network activity open, avoid forcing `networkidle` where a simple `load` or explicit sleep is enough.
14. If a site needs several intermediate clicks before the real destination appears, inspect controls first rather than guessing the final selector.
15. If the first page after login differs by account state, build the script to detect candidate destinations dynamically.

## Documentation

See:

- `docs/overview.md`
- `docs/usage.md`
- `docs/changes/2026-04-21-browser-gating.md`
- `docs/changes/2026-04-22-controller-mode.md`
- `docs/changes/2026-04-22-ask-timeout.md`
- `docs/changes/2026-04-22-example-library.md`
- `docs/changes/2026-04-22-platform-examples.md`
- `docs/changes/2026-04-22-proven-examples.md`
