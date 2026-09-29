# Releasing InterPlanet packages

This document describes how a port is released to a package registry.
Publishing is a maintainer decision. Nothing in the repository publishes a
package unless a maintainer pushes a release tag.

**Status (29 September 2026):** no package has been published to any registry,
and the repository has no git tags, so the publish workflows have never run.
Until a package is published, every registry install command in the
documentation must stay labelled "not yet published", with a tested
install-from-source command next to it.

---

## Tag convention

Each port is versioned and released independently. A release tag has the form

```
<language>/<library>/v<MAJOR>.<MINOR>.<PATCH>
```

where `<language>/<library>` is the port's directory and the version is the one
in that port's manifest (and in [`versions.json`](../versions.json)). Examples:

| Tag | Directory | Registry name |
|-----|-----------|---------------|
| `python/planet-time/v0.1.0` | `python/planet-time/` | PyPI `interplanet-time` |
| `javascript/planet-time/v1.4.0` | `javascript/planet-time/` | npm `interplanet-planet-time` |
| `javascript/ltx/v1.1.0` | `javascript/ltx/` | npm `interplanet-ltx` |

Use an annotated tag on a commit that is already on `main`:

```bash
git tag -a python/planet-time/v0.1.0 -m "interplanet-time 0.1.0"
git push origin python/planet-time/v0.1.0
```

## Publish workflows

Only three ports have a publish workflow. Each is triggered by its tag prefix
and does nothing else.

| Workflow | Tag pattern | Builds | Registry name | Secret |
|----------|-------------|--------|---------------|--------|
| [`publish-python-planet-time.yml`](../.github/workflows/publish-python-planet-time.yml) | `python/planet-time/v*` | `python/planet-time/` | PyPI `interplanet-time` | `PYPI_TOKEN` |
| [`publish-js-planet-time.yml`](../.github/workflows/publish-js-planet-time.yml) | `javascript/planet-time/v*` | `javascript/planet-time/` | npm `interplanet-planet-time` | `NPM_TOKEN` |
| [`publish-js-ltx-sdk.yml`](../.github/workflows/publish-js-ltx-sdk.yml) | `javascript/ltx/v*` | `javascript/ltx/` | npm `interplanet-ltx` | `NPM_TOKEN` |

There is no publish workflow for `@interplanet/time` or `@interplanet/ltx`
(TypeScript), `interplanet-ltx` (Python), `interplanet-time-cli`, or any other
port. Adding one means copying the pattern above with a new tag prefix.

The `@interplanet` npm scope must be owned by the maintainer's npm account
before either TypeScript package can be published.

## Release checklist

Before tagging:

- [ ] The name in the manifest is the name the documentation advertises.
- [ ] The manifest version is bumped, and `versions.json` and the tables in
      `LANGUAGE-SUPPORT.md` and `README.md` match it
      (`node scripts/check-versions.js` passes).
- [ ] The port's tests and its fixture runner pass against
      `c/planet-time/fixtures/reference.json` (see the
      [Conformance workflow](../.github/workflows/conformance.yml) and
      [LANGUAGE-SUPPORT.md](../LANGUAGE-SUPPORT.md#conformance)).
- [ ] A local dry run of the package contents looks right:
      `npm pack --dry-run` for npm, `python -m build` then inspect `dist/` for PyPI.
      Known gap: `javascript/ltx/package.json` declares `types: dist/ltx-sdk.d.ts`,
      but that file does not exist, so the package currently ships without types.
- [ ] The registry name is still free, or already owned by the maintainer.
- [ ] The registry token secret is set in the repository settings.

After the publish workflow succeeds:

- [ ] Install the package from the registry in a clean directory and import it.
- [ ] Remove the "not yet published" label for that package, and only that
      package, from `README.md`, `LANGUAGE-SUPPORT.md` and the port's README.
      Keep the install-from-source command as an alternative.
- [ ] Update the registry status section in `LANGUAGE-SUPPORT.md` with the
      date the package was published.
