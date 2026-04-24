# EPIC-009

## Title

Harden browser binary detection.

## Outcome

Make the `browser` skill reject broken or relative browser launcher paths before they reach Playwright, so installed DD commands do not fail on wrapper scripts like `bin/chrome`.

## Tickets

- `DD-032` Validate browser launch paths before passing them to Playwright
