import { test, expect } from '@playwright/test';

// Self-contained smoke tests that don't need a running server — they just prove
// headless Chromium launches, renders DOM, and executes page JS. Replace/extend
// these once there's a real Astrolabe web app to point at.

test('headless chromium renders DOM', async ({ page, browserName }) => {
  expect(browserName).toBe('chromium');
  await page.setContent('<h1 id="title">Astrolabe ✦</h1>');
  await expect(page.locator('#title')).toHaveText('Astrolabe ✦');
});

test('page JS evaluates', async ({ page }) => {
  const answer = await page.evaluate(() => 6 * 7);
  expect(answer).toBe(42);
});
