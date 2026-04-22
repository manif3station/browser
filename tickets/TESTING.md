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

## Cleanup

- remove `cover_db` after verification
