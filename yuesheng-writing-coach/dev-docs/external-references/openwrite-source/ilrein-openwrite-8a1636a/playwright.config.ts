import { defineConfig, devices } from "@playwright/test"

export default defineConfig({
  testDir: "./e2e",
  timeout: 60_000,
  retries: process.env.CI ? 2 : 0,
  // One shared wrangler-dev server + local D1; serialize to avoid cross-test races
  workers: 1,
  fullyParallel: false,
  reporter: process.env.CI ? "github" : "list",
  use: {
    baseURL: "http://localhost:3000",
    trace: "retain-on-failure",
  },
  projects: [
    { name: "desktop", use: { ...devices["Desktop Chrome"] } },
    // Pixel 7 emulation runs on chromium, so a single browser install covers both
    { name: "mobile", use: { ...devices["Pixel 7"] } },
  ],
  webServer: {
    command: "bun run e2e:server",
    url: "http://localhost:3000/health",
    timeout: 180_000,
    reuseExistingServer: !process.env.CI,
  },
})
