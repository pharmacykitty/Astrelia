import { defineConfig, devices } from '@playwright/test';

// Headless Chromium only, for now. Add a webServer block here once there's a real
// web app to test against (e.g. a Vite/Next dev server).
export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  reporter: 'list',
  use: {
    headless: true,
    trace: 'on-first-retry',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
});
