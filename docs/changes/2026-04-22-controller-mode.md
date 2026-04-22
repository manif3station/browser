# browser controller mode

## Summary

Add full Playwright controller-mode journeys to the `browser` skill.

## Included

- `--playwright`, `--agent`, and `--flow` as equivalent controller-mode flags
- Perl-side Playwright control scripts with access to `$page`, `$browser`, `$playwright`, `$response`, `$method`, and `$url`
- controller-mode compatibility with `--ask` so manual login or CAPTCHA work can continue into scripted navigation
- Docker-verified controller-mode navigation coverage and runner-level ask-mode compatibility coverage
