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

For direct local development, prepare the Node-side runtime with:

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

## Normal Cases

### JavaScript Mode Examples

1. Get the page title.

```bash
dashboard browser.get https://example.com --script 'return document.title'
```

2. Get the first `h1`.

```bash
dashboard browser.get https://example.com --script 'return document.querySelector("h1")?.textContent?.trim() || null'
```

3. Count links on the page.

```bash
dashboard browser.get https://example.com --script 'return document.querySelectorAll("a").length'
```

4. Return all link URLs.

```bash
dashboard browser.get https://example.com --script 'return Array.from(document.querySelectorAll("a")).map(a => a.href)'
```

5. Return visible page text.

```bash
dashboard browser.get https://example.com --script 'return document.body ? document.body.innerText : ""'
```

6. Read a meta description.

```bash
dashboard browser.get https://example.com --script 'return document.querySelector("meta[name=description]")?.content || null'
```

7. Read a canonical URL.

```bash
dashboard browser.get https://example.com --script 'return document.querySelector("link[rel=canonical]")?.href || null'
```

8. Return all `h2` headings.

```bash
dashboard browser.get https://example.com --script 'return Array.from(document.querySelectorAll("h2")).map(el => el.textContent.trim())'
```

9. Read a table into objects.

```bash
dashboard browser.get https://example.com --script 'return Array.from(document.querySelectorAll("table tr")).map(tr => Array.from(tr.querySelectorAll("th,td")).map(td => td.textContent.trim()))'
```

10. Read image alt text.

```bash
dashboard browser.get https://example.com --script 'return Array.from(document.querySelectorAll("img")).map(img => ({ src: img.src, alt: img.alt }))'
```

11. Extract all buttons.

```bash
dashboard browser.get https://example.com --script 'return Array.from(document.querySelectorAll("button")).map(btn => btn.textContent.trim())'
```

12. Find JSON-LD blocks.

```bash
dashboard browser.get https://example.com --script 'return Array.from(document.querySelectorAll("script[type=\"application/ld+json\"]")).map(s => s.textContent)'
```

13. Return all form field names.

```bash
dashboard browser.get https://example.com --script 'return Array.from(document.querySelectorAll("input, textarea, select")).map(el => ({ name: el.name || null, type: el.type || el.tagName }))'
```

14. Inspect the current location object.

```bash
dashboard browser.get https://example.com --script 'return { href: location.href, host: location.host, path: location.pathname }'
```

15. Read the first paragraph.

```bash
dashboard browser.get https://example.com --script 'return document.querySelector("p")?.textContent?.trim() || null'
```

16. Get all text from a specific section.

```bash
dashboard browser.get https://example.com --script 'return document.querySelector("main")?.innerText || null'
```

17. Detect if a login form exists.

```bash
dashboard browser.get https://example.com --script 'return !!document.querySelector("input[type=password]")'
```

18. Read selected attributes from cards.

```bash
dashboard browser.get https://example.com --script 'return Array.from(document.querySelectorAll(".card")).map(card => ({ id: card.id || null, text: card.textContent.trim() }))'
```

19. Extract the first five rows from a list.

```bash
dashboard browser.get https://example.com --script 'return Array.from(document.querySelectorAll("li")).slice(0, 5).map(li => li.textContent.trim())'
```

20. Return a page summary object.

```bash
dashboard browser.get https://example.com --script 'return { title: document.title, h1: document.querySelector("h1")?.textContent || null, links: document.querySelectorAll("a").length }'
```

### jQuery Mode Examples

21. Read the first `h1` with jQuery.

```bash
dashboard browser.get https://example.com --jquery --script 'return window.jQuery("h1").first().text()'
```

22. Count all links with jQuery.

```bash
dashboard browser.get https://example.com --jquery --script 'return window.jQuery("a").length'
```

23. Collect all link URLs with jQuery.

```bash
dashboard browser.get https://example.com --jquery --script 'return window.jQuery("a").map((_, el) => el.href).get()'
```

24. Read visible text from `main` with jQuery.

```bash
dashboard browser.get https://example.com --jquery --script 'return window.jQuery("main").text().trim()'
```

25. Read table rows with jQuery.

```bash
dashboard browser.get https://example.com --jquery --script 'return window.jQuery("table tr").map((_, tr) => window.jQuery(tr).text().trim()).get()'
```

26. Read all button labels with jQuery.

```bash
dashboard browser.get https://example.com --jquery --script 'return window.jQuery("button").map((_, el) => window.jQuery(el).text().trim()).get()'
```

27. Filter links that contain `docs`.

```bash
dashboard browser.get https://example.com --jquery --script 'return window.jQuery("a").filter((_, el) => (el.href || "").includes("docs")).map((_, el) => el.href).get()'
```

28. Read input placeholders.

```bash
dashboard browser.get https://example.com --jquery --script 'return window.jQuery("input").map((_, el) => ({ name: el.name || null, placeholder: el.placeholder || null })).get()'
```

29. Read card titles.

```bash
dashboard browser.get https://example.com --jquery --script 'return window.jQuery(".card h2").map((_, el) => window.jQuery(el).text().trim()).get()'
```

30. Read `data-*` attributes.

```bash
dashboard browser.get https://example.com --jquery --script 'return window.jQuery("[data-id]").map((_, el) => ({ id: window.jQuery(el).data("id"), text: window.jQuery(el).text().trim() })).get()'
```

### Perl Controller Examples For One Page

31. Click a button on the current page, then report the new title.

```bash
dashboard browser.get https://example.com --playwright --script '
my $button = $page->select(q{button});
$button->click() if $button;
sleep 1;
return { title => $page->title(), url => $page->url() };
'
```

32. Fill a search input and click submit.

```bash
dashboard browser.get https://example.com --playwright --script '
my $input = $page->select(q{input[type="search"], input[name="q"]});
$input->fill("developer dashboard") if $input;
my $submit = $page->select(q{button[type="submit"], input[type="submit"]});
$submit->click() if $submit;
sleep 2;
return { title => $page->title(), url => $page->url() };
'
```

33. Extract page text from Perl after a click.

```bash
dashboard browser.get https://example.com --playwright --script '
my $tab = $page->select(q{button[data-tab="details"]});
$tab->click() if $tab;
sleep 1;
my $text = $page->evaluate(q{return document.body.innerText});
return { text => $text };
'
```

34. Trigger a menu open and then inspect buttons.

```bash
dashboard browser.get https://example.com --playwright --script '
my $menu = $page->select(q{button[aria-label*="Menu"]});
$menu->click() if $menu;
sleep 1;
my $items = $page->evaluate(q{return Array.from(document.querySelectorAll("button,a")).map(el => (el.innerText || "").trim()).filter(Boolean)});
return { items => $items };
'
```

35. Fill email and password fields without leaving the page.

```bash
dashboard browser.get https://example.com/login --playwright --script '
my $email = $page->select(q{input[type="email"], input[name="email"]});
$email->fill("user@example.com") if $email;
my $password = $page->select(q{input[type="password"], input[name="password"]});
$password->fill("secret") if $password;
return { title => $page->title(), url => $page->url() };
'
```

36. Click a checkbox and inspect the checked state.

```bash
dashboard browser.get https://example.com/preferences --playwright --script '
my $box = $page->select(q{input[type="checkbox"]});
$box->click() if $box;
my $checked = $page->evaluate(q{return document.querySelector("input[type=\"checkbox\"]")?.checked || false});
return { checked => $checked };
'
```

37. Open a modal and read its content.

```bash
dashboard browser.get https://example.com --playwright --script '
my $open = $page->select(q{button[data-open="modal"]});
$open->click() if $open;
sleep 1;
my $modal = $page->evaluate(q{return document.querySelector(".modal, [role=\"dialog\"]")?.innerText || null});
return { modal => $modal };
'
```

38. Trigger a sort and read the reordered rows.

```bash
dashboard browser.get https://example.com/table --playwright --script '
my $sort = $page->select(q{button[data-sort="name"]});
$sort->click() if $sort;
sleep 1;
my $rows = $page->evaluate(q{return Array.from(document.querySelectorAll("table tr")).map(tr => tr.innerText.trim())});
return { rows => $rows };
'
```

39. Use Perl control with page-side jQuery extraction.

```bash
dashboard browser.get https://example.com --playwright --jquery --script '
my $text = $page->evaluate(q{return window.jQuery("h1").first().text()});
return { heading => $text };
'
```

40. Pause for manual login, then inspect the current page.

```bash
dashboard browser.get https://example.com/login --ask --playwright --script '
return { title => $page->title(), url => $page->url() };
'
```

### Perl Controller Examples For Multi-Page Flows

41. Jump from one page to another with `goto`.

```bash
dashboard browser.get https://example.com/start --flow --script '
my $response = $page->goto("https://example.com/final", { waitUntil => "networkidle" });
return { url => $page->url(), status => $response->status(), title => $page->title() };
'
```

42. Login page, then go to account.

```bash
dashboard browser.get https://example.com/login --playwright --script '
my $email = $page->select(q{input[type="email"]});
$email->fill("user@example.com") if $email;
my $password = $page->select(q{input[type="password"]});
$password->fill("secret") if $password;
my $submit = $page->select(q{button[type="submit"]});
$submit->click() if $submit;
sleep 2;
my $response = $page->goto("https://example.com/account", { waitUntil => "networkidle" });
return { url => $page->url(), status => $response->status(), title => $page->title() };
'
```

43. Manual login first, then go to billing.

```bash
dashboard browser.get https://example.com/login --ask --agent --script '
my $response = $page->goto("https://example.com/billing", { waitUntil => "networkidle" });
return { url => $page->url(), title => $page->title(), status => $response->status() };
'
```

44. Visit a page, then a documentation page, then read headings.

```bash
dashboard browser.get https://example.com --flow --script '
$page->goto("https://example.com/docs", { waitUntil => "networkidle" });
my $headings = $page->evaluate(q{return Array.from(document.querySelectorAll("h1,h2")).map(el => el.textContent.trim())});
return { url => $page->url(), headings => $headings };
'
```

45. Search on one page, then follow the first result.

```bash
dashboard browser.get https://example.com/search --flow --script '
my $input = $page->select(q{input[type="search"], input[name="q"]});
$input->fill("browser skill") if $input;
my $submit = $page->select(q{button[type="submit"]});
$submit->click() if $submit;
sleep 2;
my $href = $page->evaluate(q{return document.querySelector("a")?.href || null});
$page->goto($href, { waitUntil => "networkidle" }) if $href;
return { url => $page->url(), title => $page->title() };
'
```

46. Open a menu page and then navigate to usage.

```bash
dashboard browser.get https://example.com/app --flow --script '
my $menu = $page->select(q{button[aria-label*="Menu"]});
$menu->click() if $menu;
sleep 1;
my $usage = $page->evaluate(q{return document.querySelector("a[href*=\"usage\"]")?.href || null});
$page->goto($usage, { waitUntil => "networkidle" }) if $usage;
return { url => $page->url(), title => $page->title() };
'
```

47. Go to settings and then scrape the settings page text.

```bash
dashboard browser.get https://example.com/app --flow --script '
my $settings = $page->evaluate(q{return document.querySelector("a[href*=\"settings\"]")?.href || null});
$page->goto($settings, { waitUntil => "networkidle" }) if $settings;
my $text = $page->evaluate(q{return document.body.innerText});
return { url => $page->url(), text => $text };
'
```

48. Multi-step form flow across pages.

```bash
dashboard browser.get https://example.com/step-1 --flow --script '
my $next = $page->select(q{button[type="submit"], a[href*="step-2"]});
$next->click() if $next;
sleep 1;
$page->goto("https://example.com/step-2", { waitUntil => "networkidle" });
return { url => $page->url(), title => $page->title() };
'
```

49. Start on a public page, then navigate into an admin page and read table data.

```bash
dashboard browser.get https://example.com/public --flow --script '
$page->goto("https://example.com/admin", { waitUntil => "networkidle" });
my $rows = $page->evaluate(q{return Array.from(document.querySelectorAll("table tr")).map(tr => tr.innerText.trim())});
return { url => $page->url(), rows => $rows };
'
```

50. Ollama-style pattern: manual sign-in, then move to a usage-like page and inspect text.

```bash
dashboard browser.get https://ollama.com/signin --ask --playwright --script '
my $href = $page->evaluate(q{
  const link = Array.from(document.querySelectorAll("a")).find(a =>
    (a.href || "").includes("usage") ||
    (a.href || "").includes("billing") ||
    (a.href || "").includes("account")
  );
  return link ? link.href : null;
});
die "Could not find account-like page after login\n" if !$href;
$page->goto($href, { waitUntil => "networkidle" });
my $usage = $page->evaluate(q{return document.querySelector("main")?.innerText || document.body.innerText});
return { url => $page->url(), title => $page->title(), usage => $usage };
'
```

### Amazon-Focused Examples

These Amazon examples are shaped around stable public Amazon navigation and search selectors commonly seen on the main site, especially `#twotabsearchtextbox`, `#nav-search-submit-button`, `#nav-cart`, `#nav-link-accountList`, and `#nav-orders`.

In the current verification environment, direct live Amazon homepage rendering returned a non-HTML `202` path instead of a normal fully rendered page, so these examples are realistic Amazon-oriented patterns rather than fully re-verified live-render selectors from this container.

51. Read whether the Amazon search box is present.

```bash
dashboard browser.get https://www.amazon.com --script 'return !!document.querySelector("#twotabsearchtextbox")'
```

52. Read the Amazon search form action.

```bash
dashboard browser.get https://www.amazon.com --script 'return document.querySelector("form[action*=\"/s\"]")?.getAttribute("action") || null'
```

53. Read the Amazon cart link target.

```bash
dashboard browser.get https://www.amazon.com --script 'return document.querySelector("#nav-cart")?.href || null'
```

54. Read the Amazon account link target.

```bash
dashboard browser.get https://www.amazon.com --script 'return document.querySelector("#nav-link-accountList")?.href || null'
```

55. Read the Amazon orders link target.

```bash
dashboard browser.get https://www.amazon.com --script 'return document.querySelector("#nav-orders")?.href || null'
```

56. Read the Amazon global nav text.

```bash
dashboard browser.get https://www.amazon.com --script 'return document.querySelector("#nav-xshop")?.innerText || null'
```

57. Read the selected Amazon search department.

```bash
dashboard browser.get https://www.amazon.com --script 'return document.querySelector("#searchDropdownBox")?.value || null'
```

58. Read the Amazon search placeholder.

```bash
dashboard browser.get https://www.amazon.com --script 'return document.querySelector("#twotabsearchtextbox")?.getAttribute("placeholder") || null'
```

59. List the first ten Amazon nav links.

```bash
dashboard browser.get https://www.amazon.com --script 'return Array.from(document.querySelectorAll("#nav-xshop a")).slice(0, 10).map(a => ({ text: a.textContent.trim(), href: a.href }))'
```

60. Detect whether the Amazon homepage exposes a sign-in link.

```bash
dashboard browser.get https://www.amazon.com --script 'return !!document.querySelector("#nav-link-accountList, a[href*=\"signin\"]")'
```

61. Search Amazon for a keyword by building the search URL directly.

```bash
dashboard browser.get "https://www.amazon.com/s?k=mechanical+keyboard" --script 'return { title: document.title, results: document.querySelectorAll("[data-component-type=\"s-search-result\"]").length }'
```

62. Read Amazon search result titles.

```bash
dashboard browser.get "https://www.amazon.com/s?k=usb+c+hub" --script 'return Array.from(document.querySelectorAll("[data-component-type=\"s-search-result\"] h2")).slice(0, 5).map(h => h.textContent.trim())'
```

63. Read Amazon search result product links.

```bash
dashboard browser.get "https://www.amazon.com/s?k=usb+c+hub" --script 'return Array.from(document.querySelectorAll("[data-component-type=\"s-search-result\"] h2 a")).slice(0, 5).map(a => a.href)'
```

64. Read Amazon search result prices when present.

```bash
dashboard browser.get "https://www.amazon.com/s?k=usb+c+hub" --script 'return Array.from(document.querySelectorAll("[data-component-type=\"s-search-result\"]")).slice(0, 5).map(node => ({ title: node.querySelector("h2")?.textContent?.trim() || null, price: node.querySelector(".a-price .a-offscreen")?.textContent || null }))'
```

65. Use jQuery to read Amazon result titles.

```bash
dashboard browser.get "https://www.amazon.com/s?k=wireless+mouse" --jquery --script 'return window.jQuery("[data-component-type=\"s-search-result\"] h2").slice(0, 5).map((_, el) => window.jQuery(el).text().trim()).get()'
```

66. Navigate from the Amazon homepage to a search result page with Perl controller mode.

```bash
dashboard browser.get https://www.amazon.com --playwright --script '
my $response = $page->goto("https://www.amazon.com/s?k=desk+lamp", { waitUntil => "networkidle" });
return { url => $page->url(), status => $response->status(), title => $page->title() };
'
```

67. Open the first Amazon search result from a search page.

```bash
dashboard browser.get "https://www.amazon.com/s?k=desk+lamp" --playwright --script '
my $href = $page->evaluate(q{return document.querySelector("[data-component-type=\"s-search-result\"] h2 a")?.href || null});
die "No Amazon search result link found\n" if !$href;
$page->goto($href, { waitUntil => "networkidle" });
return { url => $page->url(), title => $page->title() };
'
```

68. Read the product title from an Amazon product page.

```bash
dashboard browser.get https://www.amazon.com/dp/B0EXAMPLE --script 'return document.querySelector("#productTitle")?.textContent?.trim() || null'
```

69. Read the buy box price from an Amazon product page.

```bash
dashboard browser.get https://www.amazon.com/dp/B0EXAMPLE --script 'return document.querySelector(".a-price .a-offscreen")?.textContent || null'
```

70. Read whether an Amazon product page shows an Add to Cart button.

```bash
dashboard browser.get https://www.amazon.com/dp/B0EXAMPLE --script 'return !!document.querySelector("#add-to-cart-button, input[name=\"submit.add-to-cart\"]")'
```

### X-Focused Examples

These X examples are aligned to the current logged-out X shell observed from `https://x.com` in live fetches from the verification environment. The current page shell includes the responsive logged-out client and script bundles from `abs.twimg.com`, while interactive content such as timelines and logged-in actions may still vary after hydration.

71. Read the logged-out X page title.

```bash
dashboard browser.get https://x.com --script 'return document.title'
```

72. Detect whether the X logged-out shell has a `main` landmark.

```bash
dashboard browser.get https://x.com --script 'return !!document.querySelector("main[role=main], main")'
```

73. Read all script bundle URLs from the X shell.

```bash
dashboard browser.get https://x.com --script 'return Array.from(document.querySelectorAll("script[src]")).map(s => s.src)'
```

74. Read all preload script URLs from the X shell.

```bash
dashboard browser.get https://x.com --script 'return Array.from(document.querySelectorAll("link[rel=preload][as=\"script\"]")).map(link => link.href)'
```

75. Read whether the shell references `abs.twimg.com`.

```bash
dashboard browser.get https://x.com --script 'return document.documentElement.innerHTML.includes("abs.twimg.com")'
```

76. Read whether the shell references `api.x.com`.

```bash
dashboard browser.get https://x.com --script 'return document.documentElement.innerHTML.includes("api.x.com")'
```

77. List the first 20 links on the X shell.

```bash
dashboard browser.get https://x.com --script 'return Array.from(document.querySelectorAll("a[href]")).slice(0, 20).map(a => ({ text: (a.innerText || a.textContent || "").trim(), href: a.href }))'
```

78. Detect whether a login link is present.

```bash
dashboard browser.get https://x.com --script 'return !!document.querySelector("a[href*=\"/login\"]")'
```

79. Detect whether a signup link is present.

```bash
dashboard browser.get https://x.com --script 'return !!document.querySelector("a[href*=\"/i/flow/signup\"], a[href*=\"/signup\"]")'
```

80. Read the visible shell text from `main`.

```bash
dashboard browser.get https://x.com --script 'return document.querySelector("main")?.innerText || document.body.innerText'
```

81. Read all `aria-label` values from the first batch of links and buttons.

```bash
dashboard browser.get https://x.com --script 'return Array.from(document.querySelectorAll("a, button")).slice(0, 30).map(el => ({ text: (el.innerText || el.textContent || "").trim(), aria: el.getAttribute("aria-label"), href: el.href || null }))'
```

82. Inspect X shell headings.

```bash
dashboard browser.get https://x.com --script 'return Array.from(document.querySelectorAll("h1,h2,h3")).map(el => el.textContent.trim())'
```

83. Use jQuery to read the first 10 visible links on X.

```bash
dashboard browser.get https://x.com --jquery --script 'return window.jQuery("a[href]").slice(0, 10).map((_, el) => ({ text: window.jQuery(el).text().trim(), href: el.href })).get()'
```

84. Use jQuery to read all preloaded script URLs.

```bash
dashboard browser.get https://x.com --jquery --script 'return window.jQuery("link[rel=\"preload\"][as=\"script\"]").map((_, el) => el.href).get()'
```

85. Open the X login page directly with controller mode.

```bash
dashboard browser.get https://x.com --playwright --script '
my $response = $page->goto("https://x.com/login", { waitUntil => "networkidle" });
return { url => $page->url(), status => $response->status(), title => $page->title() };
'
```

86. Start at X and then jump to a public post URL.

```bash
dashboard browser.get https://x.com --flow --script '
my $response = $page->goto("https://x.com/jack/status/20", { waitUntil => "networkidle" });
return { url => $page->url(), status => $response->status(), title => $page->title() };
'
```

87. Read the first tweet-like article text from a public X post page.

```bash
dashboard browser.get https://x.com/jack/status/20 --script 'return document.querySelector("article")?.innerText || null'
```

88. Read all article test IDs from a public X page.

```bash
dashboard browser.get https://x.com/jack/status/20 --script 'return Array.from(document.querySelectorAll("[data-testid]")).map(el => el.getAttribute("data-testid")).filter(Boolean)'
```

89. Pause for manual X login, then inspect the current page URL and title.

```bash
dashboard browser.get https://x.com/login --ask --playwright --script '
return { url => $page->url(), title => $page->title() };
'
```

90. Pause for manual X login, then move to a profile and inspect visible page text.

```bash
dashboard browser.get https://x.com/login --ask --playwright --script '
$page->goto("https://x.com/OpenAI", { waitUntil => "networkidle" });
my $text = $page->evaluate(q{return document.querySelector("main")?.innerText || document.body.innerText});
return { url => $page->url(), title => $page->title(), text => $text };
'
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
