# browser testing

## Docker Commands

Functional pass:

```bash
docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc '
set -euo pipefail
cd /workspace/skills/browser
cpanm --notest -L /root/perl5 --cpanfile cpanfile --installdeps .
npm install --prefix "$HOME" .
export PERL5LIB=/root/perl5/lib/perl5${PERL5LIB:+:$PERL5LIB}
export PATH=/root/perl5/bin:$PATH
prove -lr t
'
```

Covered pass:

```bash
docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc '
set -euo pipefail
cd /workspace/skills/browser
cpanm --notest -L /root/perl5 --cpanfile cpanfile --installdeps .
npm install --prefix "$HOME" .
export PERL5LIB=/root/perl5/lib/perl5${PERL5LIB:+:$PERL5LIB}
export PATH=/root/perl5/bin:$PATH
cover -delete
HARNESS_PERL_SWITCHES=-MDevel::Cover prove -lr t
cover -report text
'
```

Latest covered result for the current runtime-repair ticket:

- `lib/Browser/CLI.pm` `100.0%` statement, `100.0%` subroutine
- `lib/Browser/Runner.pm` `100.0%` statement, `100.0%` subroutine

## Direct Host Proof

Run from the skill repository:

```bash
cd ~/projects/skills/skills/browser
perl cli/get https://example.com --script 'return document.title'
```

Observed result:

- valid JSON payload returned
- `status` was `200`
- `title` was `Example Domain`
- `script_result` was `Example Domain`

## Latest DD Source Proof

Verified against the latest DD source checkout at:

```bash
~/projects/developer-dashboard
```

Verification flow:

```bash
tmp_home=$(mktemp -d)
export HOME="$tmp_home"
perl -I~/projects/developer-dashboard/lib ~/projects/developer-dashboard/bin/dashboard init
mkdir -p "$HOME/.developer-dashboard/skills"
cp -R ~/projects/skills/skills/browser "$HOME/.developer-dashboard/skills/browser"
cpanm --notest -L "$HOME/perl5" --cpanfile ~/projects/developer-dashboard/cpanfile --installdeps ~/projects/developer-dashboard
cpanm --notest -L "$HOME/perl5" --cpanfile "$HOME/.developer-dashboard/skills/browser/cpanfile" --installdeps "$HOME/.developer-dashboard/skills/browser"
export PERL5LIB="$HOME/perl5/lib/perl5"
export PATH="$HOME/perl5/bin:$PATH"
perl -I~/projects/developer-dashboard/lib ~/projects/developer-dashboard/bin/dashboard browser.get https://example.com --script 'return document.title'
```

Observed result:

- valid JSON payload returned through the DD command path
- `status` was `200`
- `title` was `Example Domain`
- `script_result` was `Example Domain`
- the skill started correctly without the earlier `uuid` ESM failure

## Result

- Docker test suite passed
- `lib/Browser/CLI.pm` reached `100.0%` statement coverage
- `lib/Browser/CLI.pm` reached `100.0%` subroutine coverage
- `lib/Browser/Runner.pm` reached `100.0%` statement coverage
- `lib/Browser/Runner.pm` reached `100.0%` subroutine coverage
- `browser.get` and `browser.post` both passed Playwright-backed integration tests inside Docker
- `browser.get` returns the rendered HTML body in its JSON payload
- browser responses include `content_type`, `body_text`, and `is_captcha`
- `browser.get` supports `--ask` and `--askme` for visible interactive takeover
- browser scripts can opt into injected jQuery with `--jquery`
- `browser.get` accepts `--playwright`, `--agent`, and `--flow` for full Playwright controller-mode journeys
- the Docker integration suite verifies controller-mode navigation from one page to another
- ask-mode plus controller-mode compatibility is covered in the runner unit suite because the shared Docker test container does not provide a desktop display server for headed browser launches
- ask-mode now uses `waitUntil => "load"` with no default timeout for the initial navigation so slow login pages can stay open for manual work
- `--timeout-ms` still overrides the initial ask-mode navigation timeout when the caller wants a bounded wait
- the README now includes explicit JavaScript versus Perl controller guidance and a large practical example library for normal and edge cases
- the README now includes platform-specific example sets for Amazon and X
- live X shell markup was fetched successfully for selector alignment
- live Amazon homepage rendering from the verification environment returned a non-HTML `202` path, so the Amazon examples are based on stable public Amazon navigation and search selectors rather than a full verified live render from this environment
- `--wait-until` now supports `networkidle`, `load`, and `domcontentloaded`
- README examples kept for this skill are verified against either the fixture/test environment or live targets documented in the current verification notes
- manual live checks confirmed these public examples in the verification environment:
  - `https://example.com` title and `h1`
  - `https://example.com` with jQuery `h1` extraction
  - `https://example.com` controller jump to `https://www.iana.org/domains/example`
  - `https://www.amazon.com/s?k=desk+lamp` with `--wait-until load`
  - `https://x.com` with `--wait-until load`
  - `https://x.com/jack/status/20` with `--wait-until load`
- current runtime repair verified that stale `$HOME/node_modules` installs are replaced with a fresh staged install from `package.json`
- current runtime repair verified that the skill works through the latest DD source checkout after loading DD and skill Perl dependencies

## Cleanup

- remove `cover_db` after verification
