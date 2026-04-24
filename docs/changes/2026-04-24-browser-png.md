# browser screenshot command

## Summary

Add `browser.png` as a first-class browser skill command for rendered page screenshots.

## Included

- `cli/png` entrypoint for `dashboard browser.png`
- screenshot capture through the shared browser runner
- `--file` support with automatic `.png` suffix normalization when missing
- default random `/tmp/browser-*.png` output when `--file` is omitted
- stdout contract that prints only the saved PNG path
