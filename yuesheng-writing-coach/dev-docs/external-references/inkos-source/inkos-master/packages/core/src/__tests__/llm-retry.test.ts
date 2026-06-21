import { describe, expect, it } from "vitest";
import { isTransientLLMHttpError } from "../llm/provider.js";

describe("isTransientLLMHttpError", () => {
  it("retries transient upstream HTTP failures (429/502/503/504)", () => {
    expect(isTransientLLMHttpError(new Error("Request failed with status code 503"))).toBe(true);
    expect(isTransientLLMHttpError(new Error("502 Bad Gateway"))).toBe(true);
    expect(isTransientLLMHttpError(new Error("504 Gateway Timeout"))).toBe(true);
    expect(isTransientLLMHttpError(new Error("429 Too Many Requests"))).toBe(true);
  });

  it("matches the real aggregator 503 message that aborted whole runs", () => {
    expect(
      isTransientLLMHttpError(
        new Error("503 The model provider is temporarily unavailable. Please retry later or contact support."),
      ),
    ).toBe(true);
  });

  it("matches transient phrasing without a status code", () => {
    expect(isTransientLLMHttpError(new Error("the model is currently overloaded"))).toBe(true);
    expect(isTransientLLMHttpError(new Error("service unavailable, try again later"))).toBe(true);
    expect(isTransientLLMHttpError(new Error("rate limit exceeded"))).toBe(true);
  });

  it("looks through a nested cause", () => {
    const err = new Error("upstream call failed") as Error & { cause?: unknown };
    err.cause = new Error("503 temporarily unavailable");
    expect(isTransientLLMHttpError(err)).toBe(true);
  });

  it("does NOT retry permanent failures", () => {
    expect(isTransientLLMHttpError(new Error("401 Unauthorized"))).toBe(false);
    expect(isTransientLLMHttpError(new Error("403 Forbidden"))).toBe(false);
    expect(isTransientLLMHttpError(new Error("400 Bad Request"))).toBe(false);
    expect(isTransientLLMHttpError(new Error("some ordinary validation error"))).toBe(false);
  });

  it("does NOT retry a 500 / MODEL_NOT_AVAILABLE (model not on inference — retry is futile)", () => {
    expect(isTransientLLMHttpError(new Error("500 Internal Server Error"))).toBe(false);
    expect(
      isTransientLLMHttpError(new Error('{"code":500,"reason":"MODEL_NOT_AVAILABLE","message":"model not available"}')),
    ).toBe(false);
  });
});
