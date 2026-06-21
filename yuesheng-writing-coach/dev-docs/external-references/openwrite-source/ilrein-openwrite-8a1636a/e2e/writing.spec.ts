import { expect, type Page, test } from "@playwright/test"

/**
 * Full writer journey against the real worker (wrangler dev + local D1):
 * sign up, create a project and chapter, write with autosave, verify
 * persistence across reload, and check the editor toolbar on mobile.
 */

async function signUp(page: Page, tag: string): Promise<void> {
  const email = `e2e-${tag}-${Date.now()}@example.com`
  await page.goto("/register")
  await page.getByLabel("Name").fill("E2E Tester")
  await page.getByLabel("Email").fill(email)
  await page.getByLabel("Password").fill("e2e-password-123")
  await page.getByRole("button", { name: "Create account" }).click()
  await page.waitForURL("**/dashboard**", { timeout: 20_000 })
}

async function createProjectViaDialog(page: Page, title: string): Promise<string> {
  await page.goto("/dashboard/projects")
  await page
    .getByRole("button", { name: /new project/i })
    .first()
    .click()
  await page.getByLabel(/title/i).fill(title)
  await page.getByRole("button", { name: "Create Project", exact: true }).click()
  await expect(page.getByText(title).first()).toBeVisible({ timeout: 15_000 })

  // Resolve the created project's id through the API the page is already authenticated against
  const projectId = await page.evaluate(async (projectTitle) => {
    const response = await fetch("/api/projects", { credentials: "include" })
    const data = (await response.json()) as { projects: { id: string; title: string }[] }
    return data.projects.find((p) => p.title === projectTitle)?.id ?? ""
  }, title)

  expect(projectId).not.toBe("")
  return projectId
}

async function openEditorWithFirstChapter(page: Page, projectId: string): Promise<void> {
  await page.goto(`/projects/${projectId}/write`)
  await page.getByRole("button", { name: /create chapter 1/i }).click()
  await expect(page.locator(".ProseMirror")).toBeVisible({ timeout: 15_000 })
}

test("writer journey: sign up, create a project, write with autosave", async ({ page }) => {
  await signUp(page, "journey")
  const projectId = await createProjectViaDialog(page, `E2E Novel ${Date.now()}`)
  await openEditorWithFirstChapter(page, projectId)

  // Write prose and wait for the debounced autosave to confirm
  await page.locator(".ProseMirror").click()
  await page.keyboard.type("The rain hammered the cobblestones as Mira slipped through the gate.")
  await expect(page.getByText(/Saved at/)).toBeVisible({ timeout: 15_000 })

  // Content survives a reload
  await page.reload()
  await expect(page.locator(".ProseMirror")).toContainText("rain hammered the cobblestones", {
    timeout: 15_000,
  })

  // Toolbar formatting applies to the document
  await page.locator(".ProseMirror").click()
  await page.keyboard.press("ControlOrMeta+a")
  await page.getByTitle("Bold").click()
  await expect(page.locator(".ProseMirror strong")).toContainText("rain hammered")

  // Chapter sidebar shows the chapter with its word count
  await expect(page.getByText("Chapter 1").first()).toBeVisible()
})

test("mobile: toolbar stays on a single scrollable row above the editor", async ({
  page,
  isMobile,
}) => {
  test.skip(!isMobile, "mobile-only regression test")

  await signUp(page, "mobile")
  const projectId = await createProjectViaDialog(page, `E2E Mobile ${Date.now()}`)
  await openEditorWithFirstChapter(page, projectId)

  const toolbar = page.getByTestId("editor-toolbar")
  await expect(toolbar).toBeVisible()

  // Regression: the toolbar must not wrap into a second row that
  // overlaps the editor content (it scrolls horizontally instead)
  const box = await toolbar.boundingBox()
  expect(box).not.toBeNull()
  expect(box?.height ?? 0).toBeLessThan(56)

  const overflows = await toolbar.evaluate((el) => el.scrollWidth > el.clientWidth)
  expect(overflows).toBe(true)

  // Controls remain usable: type, bold via toolbar
  await page.locator(".ProseMirror").click()
  await page.keyboard.type("Mobile words")
  await page.keyboard.press("ControlOrMeta+a")
  await page.getByTitle("Bold").click()
  await expect(page.locator(".ProseMirror strong")).toContainText("Mobile words")
})
