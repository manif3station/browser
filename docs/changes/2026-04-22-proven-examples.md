# browser proven examples

## Summary

Remove unproven examples from the `browser` docs and add a wait override for live sites that do not settle under `networkidle`.

## Included

- `--wait-until` support with `networkidle`, `load`, and `domcontentloaded`
- a pruned README example set limited to examples that were either fixture-verified or manually verified against live targets
- removal of optimistic examples that were not actually proven
