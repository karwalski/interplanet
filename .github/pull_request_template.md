## Description

Briefly describe what this PR changes and why.

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Performance improvement
- [ ] Refactor (no behaviour change)
- [ ] Language port (new or updated SDK)

## Related issue or story

Closes # (if applicable) / Story ID (e.g. `58.1`):

## Testing

Describe how you tested this change:

- [ ] Playwright E2E tests pass (`npx playwright test --reporter=list`)
- [ ] Python tests pass (`python -m unittest discover -s tests/`)
- [ ] C tests pass (`make test` in `c/`)
- [ ] No console errors in the browser

## Screenshots (if UI change)

<!-- Add before/after screenshots for any visual changes -->

## Checklist

- [ ] Code follows the project style (2-space indent, `const` > `let`, no `var`)
- [ ] Any new user-visible strings are added to `assets/i18n.js` for all locales
- [ ] Version `?v=` query strings bumped in `index.html` if any JS/CSS changed
- [ ] `CACHE_VERSION` in `sw.js` updated to match
- [ ] `FEATURES.md` updated if a new feature was shipped
- [ ] No hardcoded English strings in `sky.js` or `ltx.html`
