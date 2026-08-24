# Astrelia — Web workspace

Node/Playwright workspace for any web piece of Astrelia and its headless tests.

## Setup

```sh
cd Web
npm install
npx playwright install chromium
```

## Headless tests

```sh
npm test            # headless Chromium
npm run test:headed # watch it run
npm run report      # open the last HTML report
```

Tests live in `e2e/`. The current smoke tests are self-contained (no server). Once
there's a real web app, add a `webServer` block to `playwright.config.ts` so
Playwright boots the dev server before the suite.
