# Frontend Starters Guide

Arlen ships two frontend starter presets for teams that want static assets plus
lightweight API wiring without bringing a full frontend toolchain into the
framework itself.

Generate them from app root with:

```bash
/path/to/Arlen/bin/arlen generate frontend Dashboard --preset vanilla-spa
/path/to/Arlen/bin/arlen generate frontend Portal --preset progressive-mpa
```

## 1. Which Preset Should You Choose?

Choose `vanilla-spa` when you want:

- a static shell that fetches JSON on load
- a small client-side entrypoint
- a good starting point for custom API dashboards

Choose `progressive-mpa` when you want:

- HTML-first pages with opt-in JavaScript enhancement
- a more form-driven feel
- a smaller client-side footprint by default

If you are unsure, start with `vanilla-spa`.

## 2. Generated Files

Each starter lands under `public/frontend/<slug>/` and includes:

- `index.html`
- `app.js`
- `styles.css`
- `starter_manifest.json`
- `README.md`

Because these files live under `public/`, they are served as normal static
assets and are included in release packaging automatically.

## 3. What the Starters Demonstrate

Both presets use built-in Arlen endpoints so the starter works without extra app
code:

- `/healthz?format=json`
- `/metrics`

That keeps the initial experience simple: generate the starter, run the app,
and open the generated page.

## 4. Open a Generated Starter

If you generated `Dashboard` with the default slugging behavior, open:

```text
http://127.0.0.1:3000/frontend/dashboard/index.html
```

The exact path is determined by the generated slug under `public/frontend/`.

## 5. Editing Strategy

Treat these starters as owned application code:

- edit `index.html` for layout and markup
- edit `app.js` for client behavior and fetch flows
- edit `styles.css` for presentation
- keep `starter_manifest.json` as the checked-in marker for which starter
  version seeded the folder

The generated folder also includes its own `README.md` with the preset name and
upgrade note.

## 6. Upgrade Expectations

Frontend starters are scaffolds, not managed packages. The intended workflow is:

1. generate once
2. customize freely
3. compare against a future framework starter manually if you want new ideas

`starter_manifest.json` exists to make that manual comparison easier.

## 7. Related Guides

If you need generated TypeScript contracts, typed transport helpers, or the
checked-in React/Vite reference workflow rather than static starter assets, use
`arlen typescript-codegen` from `docs/GETTING_STARTED_API_FIRST.md` and the
React/TypeScript reference examples instead of these starter presets.

- `docs/FIRST_APP_GUIDE.md`
- `docs/CONFIGURATION_REFERENCE.md`
- `docs/GETTING_STARTED_API_FIRST.md`
- `../examples/phase28_react_reference/README.md`
