# browser ask timeout

## Summary

Keep ask-mode browser sessions open on slow login pages.

## Included

- change the initial ask-mode navigation from `networkidle` to `load`
- remove the default initial timeout for ask-mode navigation
- keep `--timeout-ms` as an explicit override for callers who want a bounded initial wait
