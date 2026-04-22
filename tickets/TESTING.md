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

## Cleanup

- remove `cover_db` after verification
