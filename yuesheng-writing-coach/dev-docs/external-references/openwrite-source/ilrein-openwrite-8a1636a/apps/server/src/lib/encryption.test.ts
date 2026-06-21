import { describe, expect, it } from "vitest"
import { decryptApiKey, encryptApiKey, generateEncryptionKey, hashApiKey } from "./encryption"

describe("encryption", () => {
  it("round-trips an API key through encrypt/decrypt", async () => {
    const env = { ENCRYPTION_KEY: await generateEncryptionKey() }
    const secret = "sk-or-v1-abcdef0123456789"

    const encrypted = await encryptApiKey(secret, env)
    expect(encrypted).not.toContain(secret)

    const decrypted = await decryptApiKey(encrypted, env)
    expect(decrypted).toBe(secret)
  })

  it("produces a different ciphertext per encryption (random IV)", async () => {
    const env = { ENCRYPTION_KEY: await generateEncryptionKey() }

    const first = await encryptApiKey("same-secret", env)
    const second = await encryptApiKey("same-secret", env)
    expect(first).not.toBe(second)
  })

  it("fails to decrypt with the wrong key", async () => {
    const encrypted = await encryptApiKey("secret", {
      ENCRYPTION_KEY: await generateEncryptionKey(),
    })

    await expect(
      decryptApiKey(encrypted, { ENCRYPTION_KEY: await generateEncryptionKey() })
    ).rejects.toThrow()
  })

  it("rejects when ENCRYPTION_KEY is missing", async () => {
    await expect(encryptApiKey("secret", {})).rejects.toThrow(/ENCRYPTION_KEY/)
  })

  it("hashes keys deterministically for identification", async () => {
    const first = await hashApiKey("sk-test-123")
    const second = await hashApiKey("sk-test-123")
    const other = await hashApiKey("sk-test-456")

    expect(first).toBe(second)
    expect(first).not.toBe(other)
    expect(first.length).toBeLessThanOrEqual(32)
  })
})
